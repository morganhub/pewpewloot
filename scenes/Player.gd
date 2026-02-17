extends CharacterBody2D

## Player — Le vaisseau du joueur contrôlé par touch/mouse.
## Utilise les stats du loadout actif (vitesse, HP, armes).

# =============================================================================
# PLAYER STATS (chargées depuis le loadout)
# =============================================================================

signal shield_changed(current: float, max_val: float)

var max_hp: int = 100
var current_hp: int = 100
var move_speed: float = 200.0
var fire_rate: float = 0.3
var base_damage: int = 10
var damage_multiplier: float = 1.0  # Anciennement 'power' du json qui était un multiplier, maintenant c'est des dégâts fixes 'power'

# Advanced Stats
var crit_chance: float = 5.0
var dodge_chance: float = 2.0
var missile_speed_pct: float = 100.0
var special_cd: float = 10.0
var damage_reduction: float = 0.0
var current_missile_id: String = "missile_default"
var special_power_id: String = ""
var unique_power_id: String = ""

# Status
var is_invincible: bool = false
var shield_active: bool = false # Starts inactive (Pickup only)

# SHIELD SYSTEM
var shield = null # Initialized manually
var shield_max_energy: float = 100.0
var shield_energy: float = 100.0
var shield_regen_timer: float = 0.0
const ICE_AURA_SCENE: PackedScene = preload("res://scenes/effects/IceAura.tscn")
const DEFLECTION_TICK_INTERVAL: float = 0.03

# =============================================================================
# STATE
# =============================================================================

# Cooldown Tracking (Exposed for HUD)
var special_cd_max: float = 10.0
var unique_cd_max: float = 30.0
var special_cd_current: float = 0.0
var unique_cd_current: float = 0.0

# Boosts
var _fire_rate_boost_timer: float = 0.0
var _base_fire_rate: float = 0.3

# Shooting and movement state
var _fire_timer: float = 0.0
var _can_shoot: bool = true

var visual_container: Node2D = null
var shape_visual: Polygon2D = null
var _ice_aura_node: Node2D = null
var _deflection_aura_root: Node2D = null
var _deflection_radius: float = 0.0
var _deflection_strength: float = 0.0
var _deflection_tick_timer: float = 0.0

# Contact Damage
var _contact_timer: float = 0.0
var _contact_enemies: Array[Node2D] = []
@onready var hitbox: Area2D = null

# --- DEBUG PATTERN ROTATION - START ---
var _debug_pattern_rotation_enabled: bool = false # Set to false to disable
var _debug_pattern_index: int = 0
var _debug_rotation_timer: float = 0.0
var _debug_rotation_interval: float = 10.0 # Seconds between pattern changes
var _debug_pattern_list: Array = []
var _debug_has_fired_current_pattern: bool = false
# --- DEBUG PATTERN ROTATION - END ---

func _ready() -> void:
	_init_visual_nodes()
	_setup_collision_layers()
	_setup_hitbox()
	_load_stats_from_loadout()
	_setup_visual()
	_setup_shield()
	_apply_utility_skill_bonuses()
	_setup_magic_skill_effects()
	# Spawn at bottom of screen with margin (works for all screen sizes)
	var viewport_size := get_viewport_rect().size
	var ship_size := 84.0  # Approximate ship height
	var bottom_margin := 50.0
	position = Vector2(viewport_size.x / 2, viewport_size.y - ship_size - bottom_margin)
	
	# --- DEBUG PATTERN ROTATION - START ---
	if _debug_pattern_rotation_enabled:
		var all_patterns = DataManager.get_all_missile_patterns()
		for pattern in all_patterns:
			if pattern.has("id"):
				_debug_pattern_list.append(str(pattern["id"]))
		print("[DEBUG ROTATION] Enabled. Loaded ", _debug_pattern_list.size(), " patterns: ", _debug_pattern_list)
	# --- DEBUG PATTERN ROTATION - END ---

func _setup_collision_layers() -> void:
	collision_layer = 2
	collision_mask = 1

func _setup_hitbox() -> void:
	hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = 4
	add_child(hitbox)
	var col_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	col_shape.shape = shape
	hitbox.add_child(col_shape)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.body_exited.connect(_on_hitbox_body_exited)

func _setup_shield() -> void:
	# Attendre que les enfants soient prêts
	if not is_inside_tree(): await ready
	
	# 1. Chercher le noeud existant (plusieurs noms possibles)
	var possible_nodes = [get_node_or_null("ShieldSphere"), get_node_or_null("Shield"), get_node_or_null("VisualContainer/ShieldSphere")]
	for node in possible_nodes:
		if node:
			shield = node
			break
			
	# 2. Si pas trouvé, on l'instancie dynamiquement
	if not shield:
		print("[Player] ⚠️ Shield node not found in tree, instantiating dynamically...")
		var shield_scene = load("res://addons/nojoule-energy-shield/shield_sphere.tscn")
		if shield_scene:
			# Get config diameter
			var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
			var shield_dia = float(gameplay_config.get("shield", {}).get("shield_diameter", 150.0))
			
			# Structure 3D overlay pour 2D
			var svc = SubViewportContainer.new()
			svc.name = "ShieldViewportContainer"
			svc.stretch = true
			svc.custom_minimum_size = Vector2(shield_dia, shield_dia)
			svc.position = Vector2(-shield_dia/2.0, -shield_dia/2.0) # Centrer
			
			var sv = SubViewport.new()
			sv.name = "SubViewport"
			sv.transparent_bg = true
			sv.size = Vector2(shield_dia, shield_dia)
			sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			
			# Caméra 3D requise pour voir le mesh
			var cam = Camera3D.new()
			cam.name = "ShieldCamera"
			# Ajuster Z pour couvrir le diamètre (FOV approx)
			cam.position = Vector3(0, 0, 2.0)
			cam.current = true
			
			var shield_instance = shield_scene.instantiate()
			shield_instance.name = "ShieldSphere"
			
			# Hiérarchie
			add_child(svc)
			svc.add_child(sv)
			sv.add_child(cam)
			sv.add_child(shield_instance)
			
			shield = shield_instance
			print("[Player] ✅ Shield instantiated successfully (with SubViewport).")

	if shield:
		# Connecte le signal body_entered du shield (3D)
		if not shield.body_entered.is_connected(_on_shield_body_entered):
			shield.body_entered.connect(_on_shield_body_entered)
		
		# Initialiser l'état (Invisible au départ)
		shield_active = false
		if shield.has_method("collapse"):
			shield.collapse() # Ensure collapsed at start
		
		# FORCE HIDE AT START
		shield.visible = false 
		if shield.get_parent() is SubViewport: # Hide the viewport container if dynamic
			var container = shield.get_parent().get_parent()
			if container is SubViewportContainer:
				container.visible = false
				
		_update_shield_visuals()

func activate_shield() -> void:
	# Play SFX (Shield Gain)
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("gain", {})
	var sfx_path = str(sfx_config.get("shield", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.1)
		
	# Refresh stats just in case
	var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
	var base_absorb: float = float(gameplay_config.get("shield", {}).get("shield_absorb", 100.0))
	var shield_paragon_bonus_pct: float = 0.0
	if SkillManager:
		shield_paragon_bonus_pct = SkillManager.get_stat_modifier("shield_max")
	shield_max_energy = base_absorb * (1.0 + shield_paragon_bonus_pct / 100.0)
	if _skill_overcharge_bonus > 0.0:
		shield_max_energy *= (1.0 + _skill_overcharge_bonus)
	
	if shield_active:
		# Refresh energy
		shield_energy = shield_max_energy
		shield_changed.emit(shield_energy, shield_max_energy)
		return 

	shield_active = true
	shield_energy = shield_max_energy
	shield_changed.emit(shield_energy, shield_max_energy)
	
	if shield and is_instance_valid(shield):
		shield.visible = true
		
		# Show container if dynamic
		if shield.get_parent() is SubViewport:
			var container = shield.get_parent().get_parent()
			if container is SubViewportContainer:
				container.visible = true
				
		if shield.has_method("generate"):
			shield.generate()
		
		# Apply Visual Config
		# Keys in JSON match shader uniform names roughly but need "_", "color conversion".
		var visual_config = gameplay_config.get("shield", {}).get("visual", {})
		for key in visual_config:
			var val = visual_config[key]
			var param_name = "_" + key # Most uniforms start with _
			
			# Special cases mapping
			if key == "glow_strength" or key == "glow_enabled":
				param_name = key # No underscore for these in shader
			elif key == "color_shield":
				val = Color(val)
				param_name = "_color_shield"
				
			shield.update_material(param_name, val)
			
		# Force a safe default if not in config
		if not visual_config.has("color_shield"):
			shield.update_material("_color_shield", Color(0.0, 0.8, 1.0))
			
		print("[Player] Shield visible/generate called")
	print("[Player] 🛡️ SHIELD ACTIVATED via function! Energy: ", shield_energy)

# _init_visual_nodes and others...

func _init_visual_nodes() -> void:
	visual_container = Node2D.new()
	visual_container.name = "VisualContainer"
	add_child(visual_container)
	shape_visual = Polygon2D.new()
	shape_visual.name = "Shape"
	visual_container.add_child(shape_visual)
	for child in get_children():
		if child != visual_container and (child is Polygon2D or child is Sprite2D or child.name == "Visual"):
			child.visible = false

func _setup_visual() -> void:
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var visual_data: Variant = ship.get("visual", {})
	if not visual_data is Dictionary:
		visual_data = {}
	var visual_dict := visual_data as Dictionary
	
	var asset_path: String = str(visual_dict.get("asset", ""))
	var asset_anim: String = str(visual_dict.get("asset_anim", ""))
	var asset_anim_duration: float = maxf(0.0, float(visual_dict.get("asset_anim_duration", 0.0)))
	var asset_anim_loop: bool = bool(visual_dict.get("asset_anim_loop", true))
	var use_asset: bool = false
	
	var width: float = 84.0
	var height: float = 84.0
	
	# Priority 1: AnimatedSprite (asset_anim)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames: Resource = load(asset_anim)
		if frames is SpriteFrames:
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if not anim_sprite:
				anim_sprite = AnimatedSprite2D.new()
				anim_sprite.name = "AnimatedSprite2D"
				visual_container.add_child(anim_sprite)
			
			anim_sprite.visible = true
			var played_anim: StringName = VFXManager.play_sprite_frames(
				anim_sprite,
				frames as SpriteFrames,
				&"default",
				asset_anim_loop,
				asset_anim_duration
			)
			
			var frame_tex: Texture2D = null
			if played_anim != &"" and anim_sprite.sprite_frames:
				frame_tex = anim_sprite.sprite_frames.get_frame_texture(played_anim, 0)
			if frame_tex:
				var f_size = frame_tex.get_size()
				var scale_x = width / f_size.x
				var scale_y = height / f_size.y
				var final_scale = min(scale_x, scale_y)
				anim_sprite.scale = Vector2(final_scale * 2.0, final_scale * 2.0)
			
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if sprite: sprite.visible = false

	# Priority 2: Static Sprite (asset)
	if not use_asset and asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if anim_sprite: anim_sprite.visible = false
			
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				visual_container.add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			var tex_size = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				var scale_x = width / tex_size.x
				var scale_y = height / tex_size.y
				var final_scale = min(scale_x, scale_y)
				sprite.scale = Vector2(final_scale * 2.0, final_scale * 2.0)
	
	# Priority 3: Fallback shape
	if not use_asset:
		var color := Color(visual_dict.get("color", "#CCCCCC"))
		var shape_type := str(visual_dict.get("shape", "triangle"))
		
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite: sprite.visible = false
		var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
		if anim_sprite: anim_sprite.visible = false
		
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width * 2.0, height * 2.0)
	
	# Update collision shapes
	var final_radius = width
	var main_col = get_node_or_null("CollisionShape2D")
	if main_col and main_col.shape is CircleShape2D:
		main_col.shape.radius = final_radius * 0.8
	if hitbox:
		for child in hitbox.get_children():
			if child is CollisionShape2D and child.shape is CircleShape2D:
				child.shape.radius = final_radius * 0.9

func _load_stats_from_loadout() -> void:
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	
	# Use StatsCalculator to get aggregated stats (base + items)
	var stats := StatsCalculator.calculate_ship_stats(ship_id)
	
	max_hp = int(stats.get("max_hp", 100))
	move_speed = float(stats.get("move_speed", 200))
	base_damage = int(stats.get("power", 10))
	fire_rate = float(stats.get("fire_rate", 0.3))
	_base_fire_rate = fire_rate
	crit_chance = float(stats.get("crit_chance", 5.0))
	dodge_chance = float(stats.get("dodge_chance", 2.0))
	missile_speed_pct = float(stats.get("missile_speed_pct", 100.0))
	special_cd = float(stats.get("special_cd", 10.0))
	damage_reduction = float(stats.get("damage_reduction", 0.0))
	special_cd_max = special_cd
	
	current_missile_id = str(ship.get("missile_id", "missile_default"))
	current_hp = max_hp
	special_power_id = str(ship.get("special_power_id", ""))
	
	# Get unique power from equipped items (if any)
	var item_unique_power := StatsCalculator.get_equipped_unique_power(ship_id)
	if item_unique_power != "":
		unique_power_id = item_unique_power
	else:
		unique_power_id = ProfileManager.get_active_unique_power(ship_id)


func set_invincible(state: bool) -> void:
	is_invincible = state
	if is_invincible:
		modulate.a = 0.5 
	else:
		modulate.a = 1.0

func use_special() -> void:
	if special_power_id != "" and special_cd_current <= 0:
		var pm = get_tree().root.get_node_or_null("PowerManager")
		if pm:
			pm.execute_power(special_power_id, self)
			special_cd_current = special_cd_max # Start Cooldown

func use_unique() -> void:
	# Uniquement si un item UNIQUE est équipé
	# Pour le test, on force un pouvoir unique si pas de CD
	if unique_cd_current <= 0:
		unique_power_id = "unique_meteor_storm" # Placeholder logic
		var pm = get_tree().root.get_node_or_null("PowerManager")
		if pm:
			pm.execute_power(unique_power_id, self)
			unique_cd_current = unique_cd_max

func add_fire_rate_boost(duration: float) -> void:
	var final_duration: float = maxf(0.1, duration + _skill_power_extender_bonus)
	_fire_rate_boost_timer = final_duration
	
	# Fetch bonus pct
	var gameplay_config = DataManager.get_game_data().get("gameplay", {})
	var power_up_config = gameplay_config.get("power_ups", {})
	var bonus_pct: float = float(power_up_config.get("rapid_fire", {}).get("bonus", 50.0))
	
	# Apply boost: New Rate = Base Rate * (1 + bonus/100)
	# Note: fire_rate is RATE (Attacks/Sec) based on logic in _fire().
	# To make faster, we MULTIPLY rate.
	var intensity_bonus: float = maxf(0.0, _skill_overcharge_bonus)
	var multiplier: float = 1.0 + ((bonus_pct / 100.0) * (1.0 + intensity_bonus))
	if multiplier <= 0.1: multiplier = 1.0 # Safety
	
	fire_rate = _base_fire_rate * multiplier
	
	# Visual feedback
	VFXManager.spawn_floating_text(global_position, "RAPID FIRE! +" + str(int(bonus_pct)) + "%", Color.YELLOW, get_parent())
	modulate = Color(1.5, 1.5, 0.5) # Jaunâtre brillant

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_shooting(delta)
	_handle_contact_damage(delta)
	_handle_shield_regen(delta)
	_update_deflection_aura(delta)
	if _skill_emergency_cooldown_remaining > 0.0:
		_skill_emergency_cooldown_remaining = maxf(0.0, _skill_emergency_cooldown_remaining - delta)
	
	# Cooldowns
	if special_cd_current > 0:
		special_cd_current = max(0, special_cd_current - delta)
	if unique_cd_current > 0:
		unique_cd_current = max(0, unique_cd_current - delta)
		
	# Boosts
	if _fire_rate_boost_timer > 0:
		_fire_rate_boost_timer -= delta
		if _fire_rate_boost_timer <= 0:
			# Reset
			fire_rate = _base_fire_rate
			modulate = Color.WHITE

func set_can_shoot(state: bool) -> void:
	_can_shoot = state


func _handle_contact_damage(delta: float) -> void:
	if _contact_enemies.is_empty():
		_contact_timer = 0.0
		return
	
	# Si on vient d'entrer en contact ou si le timer tick
	if _contact_timer <= 0.0:
		_apply_contact_damage()
		_contact_timer = 1.0 # Reset timer to 1s
	else:
		_contact_timer -= delta

func _apply_contact_damage() -> void:
	# Appliquer les dégâts du premier ennemi dans la liste (ou tous ?)
	# Pour simplifier et éviter le spam massif, on prend le plus fort ou juste le premier.
	# "Tick de damage toutes les secondes", disons qu'on prend le max des contacts.
	var max_dmg := 0
	for enemy in _contact_enemies:
		if enemy.has_method("get_contact_damage"):
			max_dmg = max(max_dmg, enemy.get_contact_damage())
		else:
			# Fallback default damage
			max_dmg = max(max_dmg, 10)
	
	if max_dmg > 0:
		take_damage(max_dmg)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		if not _contact_enemies.has(body):
			_contact_enemies.append(body)
			# Trigger damage immediately on first touch if timer wasn't running
			if _contact_enemies.size() == 1:
				_contact_timer = 0.0

func _on_hitbox_body_exited(body: Node2D) -> void:
	if _contact_enemies.has(body):
		_contact_enemies.erase(body)

# =============================================================================
# SHIELD LOGIC
# =============================================================================

func _handle_shield_regen(_delta: float) -> void:
	# Pas de regen automatique dans ce mode "Pickup"
	pass

func _update_shield_visuals() -> void:
	if not shield or not is_instance_valid(shield): return
	# Couleur fixe pour le mode "One Hit" (Cyan/Bleu)
	if shield.has_method("update_material"):
		shield.update_material("albedo", Color(0.0, 0.8, 1.0))

func _on_shield_body_entered(body: Node) -> void:
	# Handler principal pour le signal du Shield (3D)
	# Tente de gérer l'impact si c'est un projectile compatible
	_check_shield_impact(body)

# Helper pour détecter les projectiles (compatible 2D bridge via Projectile.gd)
func check_shield_collision(projectile: Node2D) -> bool:
	if not shield_active or shield_energy <= 0:
		return false
		
	# Vérifie si c'est un projectile ennemi
	var is_player_proj = projectile.get("is_player_projectile")
	if is_player_proj == false:
		print("[Player] 🛡️ Shield Collision Check: HIT by Enemy Projectile!")
		_apply_shield_impact(projectile)
		return true # Impact géré
		
	return false

func _check_shield_impact(body: Node) -> void:
	# Wrapper générique
	if body.has_method("get") and body.get("is_player_projectile") == false:
		_apply_shield_impact(body)

func absorb_damage_with_shield(amount: int, impact_world_pos: Vector2 = Vector2.ZERO) -> int:
	if amount <= 0:
		return 0
	if not shield_active or shield_energy <= 0:
		return amount
	if not shield or not is_instance_valid(shield):
		return amount
	
	var incoming := float(amount)
	var absorbed := minf(shield_energy, incoming)
	shield_energy -= absorbed
	var remaining := incoming - absorbed
	
	# Keep UI synced to current shield value.
	if shield_energy > 0.0:
		shield_changed.emit(shield_energy, shield_max_energy)
	else:
		shield_changed.emit(0.0, shield_max_energy)
	
	# Play SFX (Shield Hit)
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("collisions", {})
	var sfx_path = str(sfx_config.get("shield", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.1)
	
	# Update Color based on health (Low Energy Warning)
	if shield.has_method("update_material"):
		var pct = shield_energy / shield_max_energy
		if pct < 0.3:
			shield.update_material("_color_shield", Color(1.0, 0.0, 0.0)) # Red Alert
		else:
			var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
			var visual_config = gameplay_config.get("shield", {}).get("visual", {})
			var base_col_str = str(visual_config.get("color_shield", "#00CCFF"))
			shield.update_material("_color_shield", Color(base_col_str))
	
	# Visual impact
	if shield.has_method("impact"):
		var rel_pos = impact_world_pos - self.global_position
		var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
		var shield_dia = float(gameplay_config.get("shield", {}).get("shield_diameter", 150.0))
		var scale_factor = 2.0 / shield_dia
		var impact_3d = Vector3(rel_pos.x * scale_factor, -rel_pos.y * scale_factor, 0.5)
		shield.impact(impact_3d)
	
	if shield_energy <= 0:
		# Break Shield
		shield_active = false
		shield_energy = 0
		shield_changed.emit(0, shield_max_energy)
		_trigger_emergency_shockwave()
		
		print("[Player] 💥 SHIELD BREAK! Collapsing...")
		
		# Collapse sequence
		get_tree().create_timer(0.2).timeout.connect(func():
			if shield:
				shield.collapse()
				get_tree().create_timer(1.0).timeout.connect(func():
					if shield and not shield_active:
						shield.visible = false
						if shield.get_parent() is SubViewport:
							var container = shield.get_parent().get_parent()
							if container is SubViewportContainer:
								container.visible = false
				)
		)
	
	return int(ceil(remaining))

func _apply_shield_impact(projectile: Node) -> void:
	if not shield or not shield_active:
		return
	
	# Determine damage
	var dmg = 10.0
	if projectile.has_method("get_damage"):
		dmg = projectile.get_damage()
	elif "damage" in projectile:
		dmg = float(projectile.damage)
	
	var impact_world_pos := global_position
	if projectile is Node2D:
		impact_world_pos = projectile.global_position
	
	# Keep existing behavior for projectiles: shield absorbs impact.
	absorb_damage_with_shield(int(round(dmg)), impact_world_pos)
	
	# Shield Reflector (powers_2): chance to reflect the projectile back
	if _skill_reflect_chance > 0.0 and randf() < _skill_reflect_chance:
		_reflect_projectile(projectile, int(round(dmg)))

func _reflect_projectile(source_projectile: Node, _original_damage: int) -> void:
	var spawn_pos := global_position
	if source_projectile is Node2D:
		spawn_pos = source_projectile.global_position
	
	# Reflect direction: 180° from the incoming projectile direction
	var reflect_dir := Vector2.UP
	if "direction" in source_projectile:
		reflect_dir = (-source_projectile.direction).normalized()
	
	# Use player's power as damage (not enemy projectile damage)
	var reflect_damage := base_damage
	
	# Grab the enemy projectile's visual pattern data to replicate its appearance
	var pattern_data := {}
	if "_pattern_data" in source_projectile:
		pattern_data = source_projectile._pattern_data.duplicate(true)
	
	var reflect_speed := 600.0
	if "speed" in source_projectile:
		reflect_speed = float(source_projectile.speed)
	
	ProjectileManager.spawn_player_projectile(spawn_pos, reflect_dir, reflect_speed, reflect_damage, pattern_data)



# INPUT STATE
var input_provider: Object = null # GameHUD ou autre
var _external_displacement: Vector2 = Vector2.ZERO

func apply_external_displacement(offset: Vector2) -> void:
	_external_displacement += offset

func _handle_movement(delta: float) -> void:
	var use_joystick := false
	var has_external_force := _external_displacement.length_squared() > 0.000001
	
	# Vérifier si on a un provider de joystick actif
	if input_provider and input_provider.has_method("is_joystick_active"):
		if input_provider.is_joystick_active():
			use_joystick = true
	
	if use_joystick:
		# 1:1 Direct Drag Movement (Touch Follow)
		# On récupère le déplacement relatif exact du doigt depuis la dernière frame
		var drag_delta := Vector2.ZERO
		if input_provider.has_method("get_joystick_drag_delta"):
			drag_delta = input_provider.get_joystick_drag_delta()
			
		position += drag_delta
	else:
		# Mouse Follow mode (Desktop)
		# Ne pas suivre la souris si on est sur mobile/touch (évite le teleport au release)
		var on_mobile := false
		if input_provider and input_provider.has_method("is_on_mobile"):
			on_mobile = input_provider.is_on_mobile()
		else:
			on_mobile = OS.has_feature("mobile")
			
		# If an external force (e.g. GravityWell) is active this frame, skip cursor recentering.
		# This keeps the pull effect visible even when the mouse is static.
		if not on_mobile and not has_external_force:
			var mouse_pos := get_global_mouse_position()
			var distance := global_position.distance_to(mouse_pos)
			if distance > 5:  # Dead zone
				position = position.lerp(mouse_pos, delta * 15.0)
			else:
				velocity = Vector2.ZERO
	
	# 1. Clamp Input-based Movement strictly to screen
	var viewport_size := get_viewport_rect().size
	# Margin for joystick drag
	var margin_y = 20.0
	
	# Clamp position BEFORE physics (stops user dragging out)
	# Allow going down ONLY if pushed by physics (checked later)
	# Actually, physics step happens in move_and_slide.
	# If we clamp here, we clamp the input result.
	if global_position.y > viewport_size.y - margin_y:
		global_position.y = viewport_size.y - margin_y
	
	move_and_slide()
	
	# Apply external forces (e.g. graviton pull) after input movement.
	if _external_displacement != Vector2.ZERO:
		global_position += _external_displacement
		_external_displacement = Vector2.ZERO
	
	# 2. Strict X Clamp
	global_position.x = clampf(global_position.x, 20, viewport_size.x - 20)
	
	# 3. Y Clamp - Top only (Prevent going up off screen)
	if global_position.y < 20:
		global_position.y = 20
		
	# 4. Check death by "Crushing" (Pushed off screen bottom by Wall)
	# Significant margin to avoid accidental death on edge
	if global_position.y > viewport_size.y + 50:
		take_damage(99999)

func _handle_shooting(delta: float) -> void:
	# --- DEBUG PATTERN ROTATION - START ---
	if _debug_pattern_rotation_enabled and not _debug_pattern_list.is_empty():
		_debug_rotation_timer += delta
		if _debug_rotation_timer >= _debug_rotation_interval:
			_debug_rotation_timer = 0.0
			_debug_pattern_index = (_debug_pattern_index + 1) % _debug_pattern_list.size()
			_debug_has_fired_current_pattern = false
			print("\n[DEBUG ROTATION] ═══ Switching to pattern #", _debug_pattern_index, ": ", _debug_pattern_list[_debug_pattern_index], " ═══\n")
	# --- DEBUG PATTERN ROTATION - END ---
	
	_fire_timer -= delta
	
	if _fire_timer <= 0 and _can_shoot:
		_fire()
		# _fire_timer est maintenant défini dans _fire() selon le pattern et le burst

func _fire() -> void:
	# --- DEBUG PATTERN ROTATION - START ---
	var missile_pattern_id: String
	if _debug_pattern_rotation_enabled and not _debug_pattern_list.is_empty():
		# Skip if already fired this pattern (only fire once per rotation)
		if _debug_has_fired_current_pattern:
			return
		missile_pattern_id = _debug_pattern_list[_debug_pattern_index]
		_debug_has_fired_current_pattern = true
	else:
		# Normal mode: use ship's pattern
		var ship_id := ProfileManager.get_active_ship_id()
		var ship := DataManager.get_ship(ship_id)
		missile_pattern_id = str(ship.get("missile_pattern_id", "single_straight"))
	# --- DEBUG PATTERN ROTATION - END ---
	
	var pattern_data := DataManager.get_missile_pattern(missile_pattern_id).duplicate()
	
	# --- DEBUG PATTERN ROTATION - START ---
	if _debug_pattern_rotation_enabled:
		print("[DEBUG FIRE] Pattern: ", missile_pattern_id)
		print("[DEBUG FIRE]   projectile_count=", pattern_data.get("projectile_count", "?"))
		print("[DEBUG FIRE]   spread_angle=", pattern_data.get("spread_angle", "?"))
		print("[DEBUG FIRE]   spawn_width=", pattern_data.get("spawn_width", "?"))
		print("[DEBUG FIRE]   spawn_strategy=", pattern_data.get("spawn_strategy", "?"))
		print("[DEBUG FIRE]   burst_count=", pattern_data.get("burst_count", "?"))
		print("[DEBUG FIRE]   Player pos: ", global_position)
	# --- DEBUG PATTERN ROTATION - END ---
	
	if pattern_data.is_empty():
		# Fallback to default
		pattern_data = {
			"projectile_count": 1,
			"spread_angle": 0,
			"trajectory": "straight",
			"speed": 400,
			"damage": base_damage,
			"size": 8,
			"color": "#44FF44"
		}
	
	# --- Pattern Parameters ---
	var base_speed: float = float(pattern_data.get("speed", 400))
	var pattern_damage: int = int(pattern_data.get("damage", 10))
	
	# Burst & Cooldown Logic
	var burst_count: int = int(pattern_data.get("burst_count", 1))
	var burst_interval: float = float(pattern_data.get("burst_interval", 0.0))
	var reload_time: float = float(pattern_data.get("cooldown", 1.0))
	
	# --- DEBUG PATTERN ROTATION - START ---
	# Limit to single burst in debug mode
	if _debug_pattern_rotation_enabled and burst_count > 1:
		print("[DEBUG FIRE]   Original burst_count=", burst_count, " → Limiting to 1 for debug")
		burst_count = 1
	# --- DEBUG PATTERN ROTATION - END ---
	
	# Apply Ship Stats / Bonuses
	var final_damage: int = int((base_damage + pattern_damage) * damage_multiplier)
	var final_speed: float = base_speed * (missile_speed_pct / 100.0)
	
	# Cooldown calculation: (Duration of burst) + (Reload time)
	# Ship fire_rate acts as a multiplier on reload time (higher rate = lower reload)
	var reload_modified: float = reload_time 
	if fire_rate > 0.0:
		reload_modified = reload_time / fire_rate
	
	var total_sequence_time: float = max(0.0, (burst_count - 1) * burst_interval) + reload_modified
	_fire_timer = total_sequence_time
	
	# Inject Visuals & Mechanics
	_inject_missile_properties(pattern_data)
	
	# Execute Burst Sequence
	_execute_burst_sequence(pattern_data, burst_count, burst_interval, final_speed, final_damage)

func _inject_missile_properties(pattern_data: Dictionary) -> void:
	var missile_data := DataManager.get_missile(current_missile_id)
	
	# Visuals
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		pattern_data["visual_data"] = visual_data
	
	# Acceleration
	pattern_data["acceleration"] = float(missile_data.get("acceleration", 0.0))
	
	# Explosion
	var missile_explosion: Dictionary = missile_data.get("explosion", {})
	if not missile_explosion.is_empty():
		pattern_data["explosion_data"] = missile_explosion
		
	# Speed Override
	var missile_speed: float = float(missile_data.get("speed", 0))
	if missile_speed > 0:
		pattern_data["speed"] = missile_speed * (missile_speed_pct / 100.0)
		
	# Sound
	pattern_data["sound"] = str(missile_data.get("sound", ""))

func _execute_burst_sequence(pattern_data: Dictionary, count: int, interval: float, speed: float, damage: int) -> void:
	for i in range(count):
		if not is_instance_valid(self): return
		
		# Spawn one "salvo" (can be multiple projectiles if count > 1 in pattern)
		_spawn_salvo(pattern_data, speed, damage)
		
		if count > 1 and i < count - 1:
			await get_tree().create_timer(interval).timeout

func _spawn_salvo(pattern_data: Dictionary, speed: float, damage: int) -> void:
	var projectile_count: int = int(pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(pattern_data.get("spread_angle", 0))
	var spawn_width: float = float(pattern_data.get("spawn_width", 0))
	var trajectory: String = str(pattern_data.get("trajectory", "straight"))
	var spawn_strategy: String = str(pattern_data.get("spawn_strategy", "shooter"))
	
	# Play sound (once per salvo)
	var sound_path: String = str(pattern_data.get("sound", ""))
	if sound_path != "":
		AudioManager.play_sfx(sound_path, 0.1) # Soft pitch random
		
	# Determine Base Position and Direction
	var base_pos: Vector2 = global_position + Vector2(0, -20)
	var base_dir: Vector2 = Vector2.UP
	var viewport_rect := get_viewport_rect()
	
	# --- DEBUG PATTERN ROTATION - START ---
	if _debug_pattern_rotation_enabled:
		print("[DEBUG SPAWN] Initial: base_pos=", base_pos, " | base_dir=", base_dir)
		print("[DEBUG SPAWN]   spawn_width=", spawn_width, " | spawn_strategy=", spawn_strategy)
	# --- DEBUG PATTERN ROTATION - END ---
	
	# Handle Special Strategies (Screen edges)
	if spawn_strategy == "screen_bottom":
		var p_size: float = float(pattern_data.get("size", 20.0))
		var y_pos = viewport_rect.size.y + p_size # Start below screen
		base_pos = Vector2(viewport_rect.size.x / 2, y_pos)
		base_dir = Vector2.UP
		if spawn_width <= 0: spawn_width = viewport_rect.size.x # FULL WIDTH
		if _debug_pattern_rotation_enabled:
			print("[DEBUG SPAWN] screen_bottom → base_pos=", base_pos, " | spawn_width=", spawn_width)
		
	elif spawn_strategy == "screen_top":
		var p_size: float = float(pattern_data.get("size", 32.0))
		# Spawn bien au-dessus de l'écran (taille + marge de sécurité)
		base_pos = Vector2(viewport_rect.size.x / 2, -p_size - 50.0) 
		base_dir = Vector2.DOWN
		if spawn_width <= 0: spawn_width = viewport_rect.size.x # FULL WIDTH
		if _debug_pattern_rotation_enabled:
			print("[DEBUG SPAWN] screen_top → base_pos=", base_pos, " | spawn_width=", spawn_width)

	# Aim Target Logic (override direction if aimed)
	var is_aimed := (trajectory == "aimed") or bool(pattern_data.get("aim_target", false))
	if is_aimed:
		var target := _find_nearest_enemy()
		if target:
			base_dir = (target.global_position - base_pos).normalized()

	# Spawn Logic: Spread Width vs Spread Angle
	if spawn_width > 0:
		# --- LINEAR SPREAD (Spread from X) ---
		var start_x: float = -spawn_width / 2.0
		var step_x: float = 0.0
		if projectile_count > 1:
			step_x = spawn_width / float(projectile_count - 1)
		else:
			start_x = 0 # Single projectile centered
			
		for i in range(projectile_count):
			var offset_x: float = start_x + (step_x * i)
			# Calculate offset relative to direction (perpendicular)
			var perpendicular: Vector2 = base_dir.rotated(PI/2)
			var spawn_pos: Vector2 = base_pos + (perpendicular * offset_x)
			
			_spawn_single_projectile(spawn_pos, base_dir, speed, damage, pattern_data)
			
	else:
		# --- ANGULAR SPREAD (Standard) ---
		if projectile_count == 1:
			_spawn_single_projectile(base_pos, base_dir, speed, damage, pattern_data)
		else:
			var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
			var start_angle: float = -deg_to_rad(spread_angle) / 2.0
			
			for i in range(projectile_count):
				var angle: float = start_angle + angle_step * i
				var direction := base_dir.rotated(angle)
				_spawn_single_projectile(base_pos, direction, speed, damage, pattern_data)

func _spawn_single_projectile(pos: Vector2, dir: Vector2, speed: float, dmg: int, pattern_data: Dictionary) -> void:
	var is_critical := randf() <= crit_chance / 100.0
	var final_dmg := dmg * (2 if is_critical else 1)
	
	# Clamp position roughly
	# Warning: clamp might screw up off-screen spawning (screen_bottom/screen_top)
	# So only clamp if standard shooter
	
	# --- Skill Tree: Get projectile modifiers ---
	var skill_mods: Dictionary = SkillManager.get_projectile_modifier()
	
	# Override missile visual if skill tree provides one
	var missile_override: String = str(skill_mods.get("missile_override", ""))
	if missile_override != "":
		var override_missile := DataManager.get_missile(missile_override)
		if not override_missile.is_empty():
			var override_visual: Dictionary = override_missile.get("visual", {})
			if not override_visual.is_empty():
				pattern_data["visual_data"] = override_visual
	
	ProjectileManager.spawn_player_projectile(
		pos,
		dir,
		speed,
		final_dmg,
		pattern_data,
		is_critical,
		skill_mods
	)

func take_damage(amount: int) -> void:
	# Dodge check
	if randf() <= dodge_chance / 100.0:
		VFXManager.spawn_floating_text(global_position, "DODGE", Color.CYAN, get_parent())
		return
	
	if is_invincible:
		return
	
	# Damage Reduction (capped at 75%)
	if damage_reduction > 0.0:
		var dr_clamped: float = clamp(damage_reduction, 0.0, 75.0)
		amount = int(ceil(float(amount) * (1.0 - dr_clamped / 100.0)))
		amount = maxi(amount, 1) # Always deal at least 1 damage
	
	# Shield absorb first
	if shield_active and shield_energy > 0:
		amount = absorb_damage_with_shield(amount, global_position)
		if amount <= 0:
			return
	
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	print("[Player] Took damage: ", amount, " | HP: ", current_hp, "/", max_hp)
	
	# Play SFX (Player Hit)
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("collisions", {})
	var sfx_path = str(sfx_config.get("player", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.1)
	
	# Feedback visuel
	VFXManager.flash_sprite(self, Color.RED, 0.15)
	if bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(5, 0.15)
	
	if current_hp <= 0:
		die()

func die() -> void:
	print("[Player] GAME OVER")
	# TODO: Transition vers écran game over
	queue_free()

func heal(amount: int) -> void:
	current_hp += amount
	current_hp = mini(current_hp, max_hp)
	print("[Player] Healed: ", amount, " | HP: ", current_hp, "/", max_hp)

# =============================================================================
# UTILITY (Visual generation)
# =============================================================================

# --- Skill Tree: Utility bonuses cache ---
var _skill_magnet_radius_bonus: float = 0.0
var _skill_vacuum_radius: float = 0.0
var _skill_power_extender_bonus: float = 0.0
var _skill_overcharge_bonus: float = 0.0
var _skill_reflect_chance: float = 0.0
var _skill_emergency_enabled: bool = false
var _skill_shockwave_radius: float = 0.0
var _skill_shockwave_force: float = 0.0
var _skill_shockwave_cooldown: float = 20.0
var _skill_shockwave_duration: float = 0.6
var _skill_shockwave_asset: String = ""
var _skill_shockwave_asset_anim: String = ""
var _skill_shockwave_asset_anim_duration: float = 0.0
var _skill_shockwave_asset_anim_loop: bool = false
var _skill_shockwave_size: float = 240.0
var _skill_emergency_cooldown_remaining: float = 0.0

func _apply_utility_skill_bonuses() -> void:
	var bonuses: Dictionary = SkillManager.get_utility_bonuses()
	_skill_magnet_radius_bonus = float(bonuses.get("crystal_magnet_radius", bonuses.get("magnet_radius_bonus", 0.0)))
	_skill_vacuum_radius = float(bonuses.get("vacuum_radius", 0.0))
	_skill_power_extender_bonus = float(bonuses.get("powerup_duration_bonus", bonuses.get("power_duration_bonus", 0.0)))
	_skill_overcharge_bonus = float(bonuses.get("powerup_intensity_bonus", bonuses.get("overcharge_bonus", 0.0)))
	_skill_reflect_chance = clampf(float(bonuses.get("reflect_chance", 0.0)), 0.0, 1.0)
	_skill_shockwave_radius = float(bonuses.get("shockwave_radius", 0.0))
	_skill_shockwave_force = float(bonuses.get("shockwave_force", 0.0))
	_skill_shockwave_cooldown = maxf(0.1, float(bonuses.get("shockwave_cooldown", 20.0)))
	_skill_shockwave_duration = maxf(0.05, float(bonuses.get("shockwave_duration", 0.6)))
	_skill_shockwave_asset = str(bonuses.get("shockwave_asset", ""))
	_skill_shockwave_asset_anim = str(bonuses.get("shockwave_asset_anim", ""))
	_skill_shockwave_asset_anim_duration = maxf(0.0, float(bonuses.get("shockwave_asset_anim_duration", _skill_shockwave_duration)))
	_skill_shockwave_asset_anim_loop = bool(bonuses.get("shockwave_asset_anim_loop", false))
	_skill_shockwave_size = maxf(20.0, float(bonuses.get("shockwave_asset_size", 240.0)))
	_skill_emergency_enabled = _skill_shockwave_radius > 0.0 and _skill_shockwave_force > 0.0

## Returns the magnet radius bonus from the skill tree (used by LootDrop.gd)
func get_magnet_radius_bonus() -> float:
	return _skill_magnet_radius_bonus

## Returns the vacuum radius bonus from the skill tree (used by LootDrop.gd)
func get_vacuum_radius_bonus() -> float:
	return _skill_vacuum_radius

## Returns the power duration bonus from the skill tree (used by PowerManager)
func get_power_duration_bonus() -> float:
	return _skill_power_extender_bonus

## Returns the overcharge bonus from the skill tree (used by PowerManager)
func get_overcharge_bonus() -> float:
	return _skill_overcharge_bonus

func _setup_magic_skill_effects() -> void:
	var mods: Dictionary = SkillManager.get_projectile_modifier()
	_setup_ice_aura(mods)
	_setup_deflection_aura(mods)

func _setup_ice_aura(mods: Dictionary) -> void:
	if _ice_aura_node and is_instance_valid(_ice_aura_node):
		_ice_aura_node.queue_free()
		_ice_aura_node = null

	if str(mods.get("branch", "")) != "frozen":
		return
	if not mods.has("aura_type"):
		return
	if ICE_AURA_SCENE == null:
		return

	var aura_instance: Node = ICE_AURA_SCENE.instantiate()
	if not (aura_instance is Node2D):
		return
	var aura_node: Node2D = aura_instance as Node2D
	add_child(aura_node)
	_ice_aura_node = aura_node

	if _ice_aura_node.has_method("setup"):
		var radius: float = float(mods.get("aura_radius", 120.0))
		radius *= (1.0 + float(mods.get("aura_radius_bonus", 0.0)))
		var slow_pct: float = float(mods.get("aura_slow_percent", 0.2))
		var freeze_time: float = float(mods.get("freeze_aura_time", 0.0))
		var freeze_duration: float = float(mods.get("freeze_duration", 2.0))
		var freeze_dot: float = float(mods.get("freeze_dot_dps", 0.0))
		var visual_data: Dictionary = {
			"asset": str(mods.get("aura_asset", "")),
			"asset_anim": str(mods.get("aura_asset_anim", "")),
			"asset_anim_duration": float(mods.get("aura_asset_anim_duration", 0.0)),
			"asset_anim_loop": bool(mods.get("aura_asset_anim_loop", true)),
			"size": float(mods.get("aura_asset_size", radius * 2.0))
		}
		_ice_aura_node.call("setup", radius, slow_pct, freeze_time, freeze_duration, freeze_dot, visual_data)

func _setup_deflection_aura(mods: Dictionary) -> void:
	if _deflection_aura_root and is_instance_valid(_deflection_aura_root):
		_deflection_aura_root.queue_free()
		_deflection_aura_root = null

	_deflection_radius = 0.0
	_deflection_strength = 0.0
	_deflection_tick_timer = 0.0

	if str(mods.get("branch", "")) != "void":
		return
	if not bool(mods.get("deflection_enabled", false)):
		return

	_deflection_radius = maxf(8.0, float(mods.get("deflection_aura_radius", 100.0)))
	_deflection_strength = clampf(float(mods.get("deflection_strength", 0.3)), 0.0, 1.0)
	var visual_data: Dictionary = {
		"asset": str(mods.get("deflection_aura_asset", "")),
		"asset_anim": str(mods.get("deflection_aura_asset_anim", "")),
		"asset_anim_duration": float(mods.get("deflection_aura_asset_anim_duration", 0.0)),
		"asset_anim_loop": bool(mods.get("deflection_aura_asset_anim_loop", true)),
		"size": float(mods.get("deflection_aura_asset_size", _deflection_radius * 2.0))
	}
	_deflection_aura_root = _create_aura_visual_node("DeflectionAuraVisual", _deflection_radius, visual_data, Color(0.75, 0.55, 1.0, 0.55))
	if _deflection_aura_root:
		_deflection_aura_root.z_index = -7
		add_child(_deflection_aura_root)

func _update_deflection_aura(delta: float) -> void:
	if _deflection_radius <= 0.0 or _deflection_strength <= 0.0:
		return
	if _deflection_aura_root and is_instance_valid(_deflection_aura_root):
		_deflection_aura_root.global_position = global_position

	_deflection_tick_timer += delta
	if _deflection_tick_timer < DEFLECTION_TICK_INTERVAL:
		return
	_deflection_tick_timer = 0.0

	if not ProjectileManager:
		return

	var enemy_projectiles: Variant = ProjectileManager.get("_active_enemy_projectiles")
	if not (enemy_projectiles is Array):
		return

	for projectile_value in (enemy_projectiles as Array):
		if not (projectile_value is Area2D):
			continue
		var projectile: Area2D = projectile_value as Area2D
		if not is_instance_valid(projectile):
			continue
		var is_active_val: Variant = projectile.get("is_active")
		if not bool(is_active_val):
			continue

		var to_player: Vector2 = global_position - projectile.global_position
		var distance: float = to_player.length()
		if distance <= 1.0 or distance > _deflection_radius:
			continue

		var toward_player: Vector2 = to_player / distance
		var tangent: Vector2 = Vector2(-toward_player.y, toward_player.x)
		var influence: float = clampf((1.0 - (distance / _deflection_radius)) * _deflection_strength, 0.0, 0.9)
		var current_direction: Vector2 = Vector2.ZERO
		var direction_value: Variant = projectile.get("direction")
		if direction_value is Vector2:
			current_direction = (direction_value as Vector2).normalized()
		if current_direction == Vector2.ZERO:
			current_direction = tangent

		var new_direction: Vector2 = current_direction.lerp(tangent, influence).normalized()
		if new_direction != Vector2.ZERO:
			projectile.set("direction", new_direction)
			projectile.global_position += tangent * (50.0 * influence * DEFLECTION_TICK_INTERVAL)

func _trigger_emergency_shockwave() -> void:
	if not _skill_emergency_enabled:
		return
	if _skill_emergency_cooldown_remaining > 0.0:
		return

	_skill_emergency_cooldown_remaining = _skill_shockwave_cooldown

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for enemy_value in enemies:
		if not (enemy_value is Node2D):
			continue
		var enemy: Node2D = enemy_value as Node2D
		if not is_instance_valid(enemy):
			continue

		var offset: Vector2 = enemy.global_position - global_position
		var distance: float = offset.length()
		if distance <= 0.0001 or distance > _skill_shockwave_radius:
			continue

		var falloff: float = 1.0 - (distance / _skill_shockwave_radius)
		var push: Vector2 = offset.normalized() * (_skill_shockwave_force * falloff)
		if enemy.has_method("apply_external_displacement"):
			enemy.call("apply_external_displacement", push)
		else:
			enemy.global_position += push * 0.04

	if VFXManager:
		var size: float = maxf(_skill_shockwave_size, _skill_shockwave_radius * 0.6)
		var emergency_text: String = "EMERGENCY"
		if LocaleManager and LocaleManager.has_method("translate"):
			emergency_text = LocaleManager.translate("skills.skill.powers_5.title")
		VFXManager.spawn_explosion(
			global_position,
			size,
			Color(0.5, 0.9, 1.0, 0.7),
			get_parent(),
			_skill_shockwave_asset,
			_skill_shockwave_asset_anim,
			_skill_shockwave_duration,
			0.35,
			_skill_shockwave_asset_anim_duration,
			_skill_shockwave_asset_anim_loop
		)
		VFXManager.spawn_floating_text(global_position, emergency_text, Color(0.7, 1.0, 1.0), get_parent())

func _create_aura_visual_node(node_name: String, radius: float, visual_data: Dictionary, tint: Color) -> Node2D:
	var root := Node2D.new()
	root.name = node_name
	root.global_position = global_position

	var asset_anim: String = str(visual_data.get("asset_anim", ""))
	var asset: String = str(visual_data.get("asset", ""))
	var asset_anim_duration: float = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	var asset_anim_loop: bool = bool(visual_data.get("asset_anim_loop", true))
	var target_size: float = maxf(20.0, float(visual_data.get("size", radius * 2.0)))

	var visual_node: Node2D = _build_visual_node(asset_anim, asset, target_size, tint, asset_anim_duration, asset_anim_loop)
	if visual_node:
		root.add_child(visual_node)
		return root

	var ring := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments: int = 24
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	ring.polygon = points
	ring.color = Color(tint.r, tint.g, tint.b, 0.22)
	root.add_child(ring)
	return root

func _build_visual_node(
	asset_anim: String,
	asset: String,
	target_size: float,
	tint: Color,
	anim_duration: float = 0.0,
	anim_loop: bool = true
) -> Node2D:
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var anim_res: Resource = load(asset_anim)
		if anim_res is SpriteFrames:
			var frames: SpriteFrames = anim_res as SpriteFrames
			var anim_sprite := AnimatedSprite2D.new()
			var anim_name: StringName = VFXManager.play_sprite_frames(
				anim_sprite,
				frames,
				&"default",
				anim_loop,
				anim_duration
			)
			if anim_name != &"":
				anim_sprite.modulate = tint
				var frame_tex: Texture2D = null
				if anim_sprite.sprite_frames:
					frame_tex = anim_sprite.sprite_frames.get_frame_texture(anim_name, 0)
				if frame_tex:
					var frame_size: Vector2 = frame_tex.get_size()
					if frame_size.x > 0.0 and frame_size.y > 0.0:
						var scale_factor: float = target_size / maxf(frame_size.x, frame_size.y)
						anim_sprite.scale = Vector2.ONE * scale_factor
				return anim_sprite

	if asset != "" and ResourceLoader.exists(asset):
		var tex_res: Resource = load(asset)
		if tex_res is Texture2D:
			var texture: Texture2D = tex_res as Texture2D
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.modulate = tint
			var tex_size: Vector2 = texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				var scale_factor: float = target_size / maxf(tex_size.x, tex_size.y)
				sprite.scale = Vector2.ONE * scale_factor
			return sprite

	return null

func _create_shape_polygon(shape_type: String, width: float, height: float) -> PackedVector2Array:
	match shape_type:
		"circle":
			return _create_circle(max(width, height) / 2.0)
		"rectangle":
			return PackedVector2Array([
				Vector2(-width/2, -height/2),
				Vector2(width/2, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"triangle":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"diamond":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, 0),
				Vector2(0, height/2),
				Vector2(-width/2, 0)
			])
		"hexagon":
			return _create_hexagon(max(width, height) / 2.0)
		_:
			return _create_triangle_default(width, height)

func _find_nearest_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_dist := INF
	
	for enemy in enemies:
		if not enemy is Node2D: continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
			
	return nearest

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 16
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _create_hexagon(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := (i / 6.0) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _create_triangle_default(width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -height/2),
		Vector2(width/2, height/2),
		Vector2(-width/2, height/2)
	])
