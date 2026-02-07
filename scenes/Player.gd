extends CharacterBody2D

## Player — Le vaisseau du joueur contrôlé par touch/mouse.
## Utilise les stats du loadout actif (vitesse, HP, armes).

# =============================================================================
# PLAYER STATS (ch argées depuis le loadout)
# =============================================================================

var max_hp: int = 100
var current_hp: int = 100
var move_speed: float = 200.0
var fire_rate: float = 0.3
var base_damage: int = 10
var damage_multiplier: float = 1.0  # Anciennement 'power' du json qui était un multiplier, maintenant c'est des dégâts fixes 'power'

# Advanced Stats
var crit_chance: float = 0.05
var dodge_chance: float = 0.02
var missile_speed_pct: float = 1.0
var special_cd: float = 10.0
var current_missile_id: String = "missile_default"
var special_power_id: String = ""
var unique_power_id: String = ""

# Status
var is_invincible: bool = false

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

# Contact Damage
var _contact_timer: float = 0.0
var _contact_enemies: Array[Node2D] = []
@onready var hitbox: Area2D = null

func _ready() -> void:
	_init_visual_nodes()
	_setup_collision_layers()
	_setup_hitbox()
	_load_stats_from_loadout()
	_setup_visual()
	# Spawn at bottom of screen with margin (works for all screen sizes)
	var viewport_size := get_viewport_rect().size
	var ship_size := 84.0  # Approximate ship height
	var bottom_margin := 50.0
	position = Vector2(viewport_size.x / 2, viewport_size.y - ship_size - bottom_margin)

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
	var use_asset: bool = false
	
	var width: float = 84.0
	var height: float = 84.0
	
	# Priority 1: AnimatedSprite (asset_anim)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames = load(asset_anim)
		if frames is SpriteFrames:
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if not anim_sprite:
				anim_sprite = AnimatedSprite2D.new()
				anim_sprite.name = "AnimatedSprite2D"
				visual_container.add_child(anim_sprite)
			
			anim_sprite.visible = true
			anim_sprite.sprite_frames = frames
			anim_sprite.play("default")
			
			var frame_tex = frames.get_frame_texture("default", 0)
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
	var stats: Variant = ship.get("stats", {})
	if stats is Dictionary:
		var stats_dict := stats as Dictionary
		max_hp = int(stats_dict.get("max_hp", 100))
		move_speed = float(stats_dict.get("move_speed", 200))
		base_damage = int(stats_dict.get("power", 10))
		fire_rate = float(stats_dict.get("fire_rate", 0.3))
		_base_fire_rate = fire_rate
		crit_chance = float(stats_dict.get("crit_chance", 0.05))
		dodge_chance = float(stats_dict.get("dodge_chance", 0.02))
		missile_speed_pct = float(stats_dict.get("missile_speed_pct", 1.0))
		special_cd = float(stats_dict.get("special_cd", 10.0))
		special_cd_max = special_cd
	
	current_missile_id = str(ship.get("missile_id", "missile_default"))
	current_hp = max_hp
	special_power_id = str(ship.get("special_power_id", ""))
	
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
	_fire_rate_boost_timer = duration
	# Apply 50% faster fire rate (divide delay by 1.5)
	fire_rate = _base_fire_rate / 1.5
	# Visual feedback
	VFXManager.spawn_floating_text(global_position, "RAPID FIRE!", Color.YELLOW, get_parent())
	modulate = Color(1.5, 1.5, 0.5) # Jaunâtre brillant

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_shooting(delta)
	_handle_contact_damage(delta)
	
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

# INPUT STATE
var input_provider: Object = null # GameHUD ou autre

func _handle_movement(delta: float) -> void:
	var use_joystick := false
	var joystick_output := Vector2.ZERO
	
	# Vérifier si on a un provider de joystick actif
	if input_provider and input_provider.has_method("is_joystick_active"):
		if input_provider.is_joystick_active():
			use_joystick = true
			joystick_output = input_provider.get_joystick_output()
	
	if use_joystick:
		# Joystick Mode (Accéléré de 50%)
		var movement := joystick_output * (move_speed * 1.5) * delta
		position += movement
	else:
		# Mouse Follow mode (Desktop)
		# Ne pas suivre la souris si on est sur mobile/touch (évite le teleport au release)
		var on_mobile := false
		if input_provider and input_provider.has_method("is_on_mobile"):
			on_mobile = input_provider.is_on_mobile()
		else:
			on_mobile = OS.has_feature("mobile")
			
		if not on_mobile:
			var mouse_pos := get_global_mouse_position()
			var distance := global_position.distance_to(mouse_pos)
			if distance > 5:  # Dead zone
				position = position.lerp(mouse_pos, delta * 15.0)
			else:
				velocity = Vector2.ZERO
	
	move_and_slide()
	
	# Clamper à l'écran
	var viewport_size := get_viewport_rect().size
	global_position.x = clampf(global_position.x, 20, viewport_size.x - 20)
	global_position.y = clampf(global_position.y, 20, viewport_size.y - 20)

func _handle_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0 and _can_shoot:
		_fire()
		_fire_timer = fire_rate

func _fire() -> void:
	# Récupérer le vaisseau actif et son pattern de tir
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var missile_pattern_id := str(ship.get("missile_pattern_id", "single_straight"))
	var pattern_data := DataManager.get_missile_pattern(missile_pattern_id).duplicate()
	
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
	
	var projectile_count: int = int(pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(pattern_data.get("spread_angle", 0))
	var trajectory := str(pattern_data.get("trajectory", "straight"))
	var speed: float = float(pattern_data.get("speed", 400))
	var pattern_damage: int = int(pattern_data.get("damage", 10))
	
	# Apply player bonuses
	var final_damage: int = int((base_damage + pattern_damage) * damage_multiplier)
	speed = speed * missile_speed_pct
	
	# Injecter les visuels du missile actuel
	var missile_data := DataManager.get_missile(current_missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		pattern_data["visual_data"] = visual_data
	
	# Inject acceleration from missile
	var acceleration: float = float(missile_data.get("acceleration", 0.0))
	pattern_data["acceleration"] = acceleration
	
	# Inject explosion data from missile
	var missile_explosion: Dictionary = missile_data.get("explosion", {})
	if not missile_explosion.is_empty():
		pattern_data["explosion_data"] = missile_explosion
	
	# Override speed if defined in missile
	var missile_speed: float = float(missile_data.get("speed", 0))
	if missile_speed > 0:
		speed = missile_speed * missile_speed_pct
	
	# Base direction
	var base_direction := Vector2.UP
	
	# Aim Target Logic
	var is_aimed := (trajectory == "aimed") or bool(pattern_data.get("aim_target", false))
	if is_aimed:
		var target := _find_nearest_enemy()
		if target:
			base_direction = (target.global_position - global_position).normalized()
	
	# Spawn projectiles with spread
	if projectile_count == 1:
		var is_critical := randf() <= crit_chance
		var dmg := final_damage * (2 if is_critical else 1)
		ProjectileManager.spawn_player_projectile(
			global_position + Vector2(0, -20),
			base_direction,
			speed,
			dmg,
			pattern_data,
			is_critical
		)
	else:
		var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
		var start_angle: float = -deg_to_rad(spread_angle) / 2.0
		
		for i in range(projectile_count):
			var angle: float = start_angle + angle_step * i
			var direction := base_direction.rotated(angle)
			var is_critical := randf() <= crit_chance
			var dmg := final_damage * (2 if is_critical else 1)
			ProjectileManager.spawn_player_projectile(
				global_position + Vector2(0, -20),
				direction,
				speed,
				dmg,
				pattern_data,
				is_critical
			)

func take_damage(amount: int) -> void:
	# Dodge check
	if randf() <= dodge_chance:
		VFXManager.spawn_floating_text(global_position, "DODGE", Color.CYAN, get_parent())
		return
	
	if is_invincible:
		return
	
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	print("[Player] Took damage: ", amount, " | HP: ", current_hp, "/", max_hp)
	
	# Feedback visuel
	VFXManager.flash_sprite(self, Color.RED, 0.15)
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
