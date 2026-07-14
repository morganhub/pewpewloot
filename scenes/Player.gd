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
var crit_damage_bonus: float = 0.0
var missile_damage_bonus: float = 0.0
var shield_capacity_bonus: float = 0.0
var shield_regen_bonus: float = 0.0
var loot_radius_bonus: float = 0.0
var xp_multiplier_bonus: float = 0.0
var current_missile_id: String = "missile_default"
var special_power_id: String = ""
var unique_power_id: String = ""
var _healing_multiplier: float = 1.0

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
const DEFAULT_MAX_FIRE_RATE: float = 80.0
var _fire_rate_max: float = DEFAULT_MAX_FIRE_RATE

# Shooting and movement state
var _fire_timer: float = 0.0
var _can_shoot: bool = true

# Active fire pattern for the current run (obtained via in-run fire pattern drops).
# Empty string means the ship's native pattern is used. Resets every run.
var _active_fire_pattern_id: String = ""

# Gate Runner wave state: HP becomes a resource (can overflow max_hp). The ship
# shrinks and clones itself into an escort swarm whose unit count follows the
# resource; the big HP value is shown on the ship.
const NumberFormat := preload("res://scenes/mechanics/number_format.gd")
var _gate_runner_active: bool = false
var _gate_runner_ref_hp: float = 100.0
var _gate_runner_swarm_cfg: Dictionary = {}
var _gate_runner_clones: Array = [] # [{node, base_offset, offset, target_offset, phase, drift_timer}]
var _gate_runner_swarm_root: Node2D = null
var _gate_runner_swarm_radius: float = 0.0
var _gate_runner_swarm_time: float = 0.0
var _gate_runner_current_scale: float = 1.0
var _big_hp_label: Label = null
# Clone doré (gate_runner) : un clone marqué à protéger — bonus si le round se
# termine sans contact subi (logique côté GateRunnerManager, visuel ici).
var _gate_runner_golden_active: bool = false

# Pong wave state: Y locked on the paddle line, the ship visual squashed flat.
var _pong_active: bool = false
var _pong_lock_y: float = 0.0
var _pong_lock_tween: Tween = null

# Vertical climb wave state: Y is fully driven by the climb manager (gravity +
# bounces), X stays player-controlled.
var _climb_active: bool = false
var _climb_y: float = 0.0
# Wrap-around horizontal (Doodle Jump) : sortir d'un côté fait rentrer de
# l'autre — activé par la vague via begin_climb cfg (wrap_horizontal).
var _climb_wrap_x: bool = false

# Absorb wave state: the ship carries a mass shown on the big label; its size
# follows the mass (sqrt curve, capped).
var _absorb_active: bool = false
var _absorb_start_mass: float = 10.0
var _absorb_scale_base: float = 1.0
var _absorb_scale_min: float = 0.8
var _absorb_scale_max: float = 2.4

# Lane runner wave state: X snaps to a fixed set of lanes (Subway Surfers-like).
# One touch/click gesture = ONE lane shift max: the first horizontal move past
# the swipe threshold shifts, then the gesture is consumed until release.
# Y locked near the bottom. Arrow keys still shift lanes on desktop.
const LANE_MOUSE_CAPTURE_ID: int = -2
var _lane_runner_active: bool = false
var _lane_count: int = 3
var _lane_index: int = 1
var _lane_render_x: float = 0.0
var _lane_lock_y: float = 0.0
var _lane_side_margin_px: float = 70.0
var _lane_snap_speed: float = 14.0
var _lane_swipe_threshold_px: float = 48.0
var _lane_gesture_id: int = -1
var _lane_gesture_start_x: float = 0.0
var _lane_gesture_consumed: bool = false
var _lane_lock_tween: Tween = null
var _lane_last_switch_msec: int = -100000

# Ball launcher wave state: Y locked on the launch line (no squash — the ship
# stays a ship), X glides toward a target driven by the BallLauncherManager
# (finger follow / freeze while aiming). All regular movement input is
# neutralized; the manager reads the raw touches itself.
var _ball_launcher_active: bool = false
var _ball_launcher_lock_y: float = 0.0
var _ball_launcher_target_x: float = 0.0
var _ball_launcher_snap_speed: float = 14.0
var _ball_launcher_lock_tween: Tween = null

# Slice rush wave state: the ship is fully locked (X and Y) at the bottom
# center; the finger slices, the ship only fires the visual laser.
var _slice_rush_active: bool = false
var _slice_rush_lock_pos: Vector2 = Vector2.ZERO
var _slice_rush_lock_tween: Tween = null
# Suika up wave: full X+Y lock — le vaisseau borde le réacteur et tire sur le boss.
var _suika_up_active: bool = false
var _suika_up_lock_pos: Vector2 = Vector2.ZERO
var _suika_up_lock_tween: Tween = null

# Match3 wave state: the ship is a jokered tile inside the 9x9 board — fully
# locked, shrunk to cell size, position driven by the Match3Manager through
# set_match3_lock_pos (the manager tweens it cell to cell). A configurable
# additive glow marks it as the special tile.
var _match3_active: bool = false
var _match3_lock_pos: Vector2 = Vector2.ZERO
var _match3_glow: AnimatedSprite2D = null
var _match3_glow_tween: Tween = null

# Snake wave state: the ship is the SNAKE HEAD — fully locked, position AND
# facing driven each frame by the SnakeManager (steering at constant speed).
var _snake_active: bool = false
var _snake_lock_pos: Vector2 = Vector2.ZERO

# Gravity hole wave state: the ship is a free-roaming vortex (movement free in
# ALL directions — the forbidden top zone is lifted while active). Mass shown
# on the big label; animated aura as a direct Player child at index 0 (NOT in
# visual_container: the aura tracks the ABSORPTION radius pushed by the
# manager, while the ship scale tracks the mass — independent scales).
var _gravity_hole_active: bool = false
# Refonte Agar.io : vaisseau verrouillé au centre, le monde bouge autour.
var _gh_center_locked: bool = false
var _gh_lock_pos: Vector2 = Vector2.ZERO
var _gh_start_mass: float = 10.0
var _gh_scale_base: float = 1.0
var _gh_scale_min: float = 0.75
var _gh_scale_max: float = 1.55
var _gh_aura: AnimatedSprite2D = null
var _gh_aura_frame_dim: float = 0.0
var _gh_aura_visual_ratio: float = 1.08
var _gh_aura_base_scale: float = 1.0
var _gh_aura_pulse_scale: float = 1.15
var _gh_aura_pulse_sec: float = 0.18
var _gh_aura_pulse_tween: Tween = null

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

# Fluid trail
var _fluid_id: String = ""

# Fire Pattern: Aura system
var _aura_active: bool = false
var _aura_timer: float = 0.0
var _aura_dps: float = 0.0
var _aura_radius: float = 0.0
var _aura_tick_interval: float = 0.5
var _aura_area: Area2D = null
var _aura_visual: Node2D = null
var _aura_targets: Array[Node] = []

# --- DEBUG PATTERN ROTATION - START ---
var _debug_pattern_rotation_enabled: bool = false # Set to false to disable
var _debug_pattern_index: int = 0
var _debug_rotation_timer: float = 0.0
var _debug_rotation_interval: float = 10.0 # Seconds between pattern changes
var _debug_pattern_list: Array = []
var _debug_has_fired_current_pattern: bool = false
# --- DEBUG PATTERN ROTATION - END ---

func _ready() -> void:
	_load_fire_rate_caps()
	# Each run starts on the ship's native fire pattern; drops change it in-run.
	_active_fire_pattern_id = ""
	# Top-down movement: avoid carrying platform velocity after leaving moving obstacles.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING
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
		var all_patterns = DataManager.get_all_player_missile_patterns()
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
	shield_max_energy += maxf(0.0, shield_capacity_bonus)
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

# Skin par type de vague : ships.json > visual.wave_visuals.<wave_type> écrase
# les clés du visual de base (merge superficiel) ; "" = visuel générique.
var _wave_visual_type: String = ""
var _applied_visual_sig: String = ""

## Visual du vaisseau actif + overrides du wave type courant (fallback : base).
func _resolve_visual_dict(wave_type: String) -> Dictionary:
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var visual_data: Variant = ship.get("visual", {})
	if not visual_data is Dictionary:
		visual_data = {}
	var resolved: Dictionary = (visual_data as Dictionary).duplicate()
	if wave_type != "":
		var overrides_v: Variant = resolved.get("wave_visuals", {})
		if overrides_v is Dictionary:
			var override_v: Variant = (overrides_v as Dictionary).get(wave_type, null)
			if override_v is Dictionary:
				for key in (override_v as Dictionary).keys():
					resolved[key] = (override_v as Dictionary)[key]
	return resolved

## Signature du modèle résolu — sert à détecter un vrai changement de visuel
## (et donc à ne jouer l'anim de transition que dans ce cas).
func _visual_signature(visual_dict: Dictionary) -> String:
	return str(visual_dict.get("asset_anim", "")) + "|" + str(visual_dict.get("asset", "")) \
		+ "|" + str(visual_dict.get("shape", "")) + "|" + str(visual_dict.get("color", ""))

## Applique le skin du type de vague courant (appelé par Game._on_wave_started
## AVANT le begin_* du manager). Transition visuelle seulement si le modèle
## change réellement (skin spécifique <-> autre) ; fallback générique sinon.
func apply_wave_visual(wave_type: String) -> void:
	_wave_visual_type = wave_type
	var resolved := _resolve_visual_dict(wave_type)
	var sig := _visual_signature(resolved)
	if sig == _applied_visual_sig:
		return
	_applied_visual_sig = sig
	_play_swap_transition()
	_apply_visual_dict(resolved)

## Animation couvrant le vaisseau pendant le swap de modèle : grossit puis
## réduit (clé racine ship_swap_transition_anim de wave_types.json — éclair à
## terme, explosion placeholder). Parentée au parent du Player pour ne pas
## hériter du squash de visual_container.
func _play_swap_transition() -> void:
	var anim: String = str(DataManager.get_wave_types_global("ship_swap_transition_anim", ""))
	if anim == "" or not ResourceLoader.exists(anim):
		return
	var parent: Node = get_parent()
	if parent == null or not is_inside_tree():
		return
	VFXManager.spawn_explosion(global_position, 90.0, Color.WHITE, parent,
		"", anim, 0.6, 0.25, 0.6, false, 0.08, 0.4, 1.5, 0.4, 0.5, 170.0)

func _setup_visual() -> void:
	var resolved := _resolve_visual_dict(_wave_visual_type)
	_applied_visual_sig = _visual_signature(resolved)
	_apply_visual_dict(resolved)

func _apply_visual_dict(visual_dict: Dictionary) -> void:
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
	fire_rate = _clamp_fire_rate(float(stats.get("fire_rate", 0.3)))
	_base_fire_rate = fire_rate
	crit_chance = float(stats.get("crit_chance", 5.0))
	dodge_chance = float(stats.get("dodge_chance", 2.0))
	missile_speed_pct = float(stats.get("missile_speed_pct", 100.0))
	special_cd = float(stats.get("special_cd", 10.0))
	damage_reduction = float(stats.get("damage_reduction", 0.0))
	crit_damage_bonus = float(stats.get("crit_damage", 0.0))
	missile_damage_bonus = float(stats.get("missile_damage", 0.0))
	shield_capacity_bonus = float(stats.get("shield_capacity", 0.0))
	shield_regen_bonus = float(stats.get("shield_regen", 0.0))
	loot_radius_bonus = float(stats.get("loot_radius", 0.0))
	xp_multiplier_bonus = float(stats.get("xp_multiplier", 0.0))
	special_cd_max = special_cd
	
	current_missile_id = str(ship.get("missile_id", "missile_default"))
	current_hp = max_hp
	special_power_id = str(ship.get("special_power_id", ""))
	_fluid_id = str(ship.get("fluid_id", ""))
	
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
	if unique_cd_current > 0:
		return
	if unique_power_id == "":
		return

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
	
	fire_rate = _clamp_fire_rate(_base_fire_rate * multiplier)
	
	# Visual feedback
	VFXManager.spawn_floating_text(global_position, "RAPID FIRE! +" + str(int(bonus_pct)) + "%", Color.YELLOW, get_parent())
	modulate = Color(1.5, 1.5, 0.5) # Jaunâtre brillant

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_shooting(delta)
	_handle_contact_damage(delta)
	_handle_shield_regen(delta)
	_update_deflection_aura(delta)
	_update_aura(delta)
	_update_gate_runner_swarm_motion(delta)
	if _fluid_id != "":
		FluidManager.emit_fluid(global_position, _fluid_id, velocity)
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
			fire_rate = _clamp_fire_rate(_base_fire_rate)
			modulate = Color.WHITE

func _clamp_fire_rate(value: float) -> float:
	return clampf(value, 0.01, _fire_rate_max)

func _load_fire_rate_caps() -> void:
	var game_cfg: Dictionary = DataManager.get_game_config() if DataManager else {}
	var balance_raw: Variant = game_cfg.get("game_balance", {})
	var balance: Dictionary = balance_raw if balance_raw is Dictionary else {}
	_fire_rate_max = maxf(0.01, float(balance.get("fire_rate_max", DEFAULT_MAX_FIRE_RATE)))

func set_can_shoot(state: bool) -> void:
	_can_shoot = state
	if not state:
		# Cancel pending shot cycles immediately when gameplay is gated.
		_fire_timer = 0.0
	# Deactivate aura when shooting is disabled
	if not state:
		_deactivate_aura()

# =============================================================================
# GATE RUNNER WAVE
# =============================================================================

## Enters the gate-runner mode: HP becomes a resource (overflow allowed), the
## ship shrinks and clones itself into an escort swarm sized by the resource,
## and the big HP value is displayed.
func begin_gate_runner(cfg: Dictionary) -> void:
	_gate_runner_active = true
	_gate_runner_ref_hp = float(maxi(1, max_hp))
	_gate_runner_swarm_cfg = cfg.duplicate(true)
	_gate_runner_swarm_time = 0.0
	_apply_ship_scale(maxf(0.1, float(_gate_runner_swarm_cfg.get("player_swarm_ship_scale", 0.55))))
	_ensure_big_hp_label()
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.visible = true
	_update_gate_runner_swarm()
	_update_big_hp_label()

## Leaves the gate-runner mode: frees the clone swarm and resets the ship size.
## Le clamp des HP vers max_hp est piloté par `hp_clamp_on_wave_end` (cfg du
## begin) : true en histoire (fin de vague = retour à la normale), false en
## mode libre restart (la ressource PERSISTE de round en round — continuité).
func end_gate_runner() -> void:
	if not _gate_runner_active and (_big_hp_label == null or not is_instance_valid(_big_hp_label) or not _big_hp_label.visible):
		# Already restored; still make sure the ship state is neutral.
		_apply_ship_scale(1.0)
		_clear_gate_runner_swarm()
		return
	_gate_runner_active = false
	_gate_runner_golden_active = false
	if bool(_gate_runner_swarm_cfg.get("hp_clamp_on_wave_end", true)):
		clamp_hp_to_max()
	_apply_ship_scale(1.0)
	_clear_gate_runner_swarm()
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.visible = false

func is_gate_runner_active() -> bool:
	return _gate_runner_active

## Applies a gate math operation to the HP resource. Overflow above max_hp is
## allowed during the wave; reaching 0 triggers death.
func apply_gate_operation(operation: String, value: float) -> void:
	if not _gate_runner_active:
		return
	var hp: float = float(current_hp)
	match operation:
		"add":
			hp += value
		"subtract":
			hp -= value
		"multiply":
			hp *= value
		"divide":
			if absf(value) > 0.0001:
				hp /= value
		_:
			pass
	current_hp = int(round(hp))
	# Cap dur de la ressource : « 999 millions sera le maximum ».
	current_hp = mini(current_hp, int(_gate_runner_swarm_cfg.get("hp_resource_cap", 999999999)))
	if current_hp <= 0:
		current_hp = 0
		die()
		return
	_update_gate_runner_swarm()
	_update_big_hp_label()
	var is_bonus: bool = (operation == "add" and value >= 0.0) \
		or (operation == "multiply" and value >= 1.0) \
		or (operation == "divide" and value <= 1.0)
	_play_gate_juice(is_bonus)

## Clamps the HP resource back to max_hp (called when the gate-runner wave ends).
func clamp_hp_to_max() -> void:
	current_hp = clampi(current_hp, 0, max_hp)

## HP ratio -> escort size. The real ship is the swarm center and counts as one
## unit; clones are pure visuals (no hitbox, no shooting — drone contacts are
## resolved by GateRunnerManager against the whole swarm radius). The spread
## radius is capped so the on-screen footprint never exceeds what the old
## max-size ship used to take.
func _update_gate_runner_swarm() -> void:
	if not _gate_runner_active:
		return
	var cfg: Dictionary = _gate_runner_swarm_cfg
	var ratio: float = float(current_hp) / maxf(1.0, _gate_runner_ref_hp)
	var count_base: int = maxi(1, int(cfg.get("player_swarm_count_base", 12)))
	var count_min: int = maxi(1, int(cfg.get("player_swarm_count_min", 2)))
	var count_max: int = maxi(count_min, int(cfg.get("player_swarm_count_max", 40)))
	var total_units: int = clampi(int(round(ratio * float(count_base))), count_min, count_max)
	var spread_max: float = maxf(24.0, float(cfg.get("player_swarm_spread_max_px", 170.0)))
	var spread_min: float = clampf(float(cfg.get("player_swarm_spread_min_px", 52.0)), 8.0, spread_max)
	# Swarm area grows with the unit count -> radius grows with its square root.
	_gate_runner_swarm_radius = clampf(spread_max * sqrt(float(total_units) / float(count_max)), spread_min, spread_max)
	_ensure_gate_runner_swarm_root()
	_sync_gate_runner_clone_count(maxi(0, total_units - 1))
	_reflow_gate_runner_clones()
	_refresh_golden_clone_visual()

## Clone doré : marque/démarque le clone protégé (le premier de la liste — les
## resyncs retirent toujours en pop_back, il survit le plus longtemps). Visuel
## PH = tint or + scale golden_clone_scale ; asset dédié golden_clone_asset en
## overlay quand il existe.
func set_gate_runner_golden_clone(active: bool) -> void:
	_gate_runner_golden_active = active
	_refresh_golden_clone_visual()

func has_gate_runner_golden_clone() -> bool:
	return _gate_runner_golden_active and not _gate_runner_clones.is_empty()

func _refresh_golden_clone_visual() -> void:
	if _gate_runner_clones.is_empty():
		return
	var clone_scale: float = maxf(0.05, float(_gate_runner_swarm_cfg.get("player_swarm_clone_scale", 0.35)))
	var golden_scale: float = clone_scale * maxf(1.0, float(_gate_runner_swarm_cfg.get("golden_clone_scale", 1.6)))
	for i in range(_gate_runner_clones.size()):
		var entry: Dictionary = _gate_runner_clones[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var node: Node2D = node_v as Node2D
		var golden: bool = _gate_runner_golden_active and i == 0
		if golden:
			node.modulate = Color(1.5, 1.2, 0.45)
			node.scale = Vector2.ONE * golden_scale
			_ensure_golden_clone_overlay(node)
		else:
			node.modulate = Color.WHITE
			if node.scale.x > clone_scale + 0.001:
				node.scale = Vector2.ONE * clone_scale
			var overlay: Node = node.get_node_or_null("GoldenSkin")
			if overlay:
				overlay.queue_free()

## Overlay du clone doré : sprite dédié (golden_clone_asset) par-dessus le
## duplicata du vaisseau — visible seulement quand l'asset existe.
func _ensure_golden_clone_overlay(clone: Node2D) -> void:
	if clone.get_node_or_null("GoldenSkin") != null:
		return
	var asset_path: String = str(_gate_runner_swarm_cfg.get("golden_clone_asset", ""))
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if not (res is Texture2D):
		return
	var sprite := Sprite2D.new()
	sprite.name = "GoldenSkin"
	sprite.texture = res as Texture2D
	var tex_size: Vector2 = (res as Texture2D).get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sprite.scale = (Vector2.ONE * 64.0) / maxf(tex_size.x, tex_size.y)
	clone.add_child(sprite)

func get_gate_runner_scale() -> float:
	return _gate_runner_current_scale

## Current escort radius (px around the ship), 0 when no clone is out.
## GateRunnerManager uses it to size the drone contact zone.
func get_gate_runner_swarm_radius() -> float:
	if not _gate_runner_active or _gate_runner_clones.is_empty():
		return 0.0
	return _gate_runner_swarm_radius

func _ensure_gate_runner_swarm_root() -> void:
	if _gate_runner_swarm_root and is_instance_valid(_gate_runner_swarm_root):
		return
	_gate_runner_swarm_root = Node2D.new()
	_gate_runner_swarm_root.name = "GateRunnerSwarm"
	add_child(_gate_runner_swarm_root)
	# Clones draw below the real ship so the swarm center stays readable.
	move_child(_gate_runner_swarm_root, 0)

func _sync_gate_runner_clone_count(target: int) -> void:
	# Drop extra clones with a quick shrink-out.
	while _gate_runner_clones.size() > target:
		var entry: Dictionary = _gate_runner_clones.pop_back()
		var gone_v: Variant = entry.get("node", null)
		if gone_v is Node2D and is_instance_valid(gone_v):
			var gone: Node2D = gone_v as Node2D
			var out_tween: Tween = gone.create_tween()
			out_tween.tween_property(gone, "scale", Vector2.ZERO, 0.15)
			out_tween.finished.connect(gone.queue_free)
	# Spawn missing clones with a small pop-in.
	var clone_scale: float = maxf(0.05, float(_gate_runner_swarm_cfg.get("player_swarm_clone_scale", 0.35)))
	while _gate_runner_clones.size() < target:
		var clone: Node2D = _build_gate_runner_clone_visual()
		_gate_runner_swarm_root.add_child(clone)
		clone.scale = Vector2.ZERO
		var in_tween: Tween = clone.create_tween()
		in_tween.tween_property(clone, "scale", Vector2.ONE * clone_scale, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_gate_runner_clones.append({
			"node": clone,
			"base_offset": Vector2.ZERO,
			"offset": Vector2.ZERO,
			"target_offset": Vector2.ZERO,
			"phase": randf() * TAU,
			"drift_timer": randf_range(0.1, 0.6)
		})

## Copies the currently visible ship visual (animated sprite, sprite or shape).
func _build_gate_runner_clone_visual() -> Node2D:
	var root := Node2D.new()
	root.name = "PlayerClone"
	var source: Node2D = null
	if visual_container and is_instance_valid(visual_container):
		var anim: Node = visual_container.get_node_or_null("AnimatedSprite2D")
		var spr: Node = visual_container.get_node_or_null("Sprite2D")
		if anim is AnimatedSprite2D and (anim as AnimatedSprite2D).visible:
			source = anim as Node2D
		elif spr is Sprite2D and (spr as Sprite2D).visible:
			source = spr as Node2D
		elif shape_visual and is_instance_valid(shape_visual) and shape_visual.visible:
			source = shape_visual
	if source:
		var copy: Node2D = source.duplicate(0) as Node2D
		if copy:
			copy.visible = true
			copy.position = Vector2.ZERO
			if copy is AnimatedSprite2D and source is AnimatedSprite2D:
				(copy as AnimatedSprite2D).play((source as AnimatedSprite2D).animation)
			root.add_child(copy)
	return root

## Even sunflower distribution of the clones inside the swarm ring; targets are
## recomputed on every count change and the clones glide to their new slot.
func _reflow_gate_runner_clones() -> void:
	var n: int = _gate_runner_clones.size()
	if n <= 0:
		return
	var inner_radius: float = maxf(8.0, float(_gate_runner_swarm_cfg.get("player_swarm_inner_radius_px", 44.0)))
	const GOLDEN_ANGLE: float = 2.399963
	for i in range(n):
		var entry: Dictionary = _gate_runner_clones[i]
		var r: float = maxf(inner_radius, _gate_runner_swarm_radius * sqrt((float(i) + 0.75) / float(n)))
		var a: float = float(i) * GOLDEN_ANGLE
		entry["base_offset"] = Vector2(cos(a), sin(a)) * r
		entry["target_offset"] = entry["base_offset"]

## Light per-clone wander so the escort never looks static: slow drift around
## the home slot plus a small sine weave, all relative to the player position.
func _update_gate_runner_swarm_motion(delta: float) -> void:
	if not _gate_runner_active or _gate_runner_clones.is_empty():
		return
	_gate_runner_swarm_time += delta
	var cfg: Dictionary = _gate_runner_swarm_cfg
	var amp: float = maxf(0.0, float(cfg.get("player_swarm_weave_amplitude_px", 10.0)))
	var freq: float = maxf(0.05, float(cfg.get("player_swarm_weave_frequency_hz", 1.4)))
	var drift_min: float = maxf(0.1, float(cfg.get("player_swarm_drift_interval_min_sec", 0.8)))
	var drift_max: float = maxf(drift_min, float(cfg.get("player_swarm_drift_interval_max_sec", 1.8)))
	var follow: float = minf(1.0, delta * 3.5)
	var jitter: float = maxf(6.0, _gate_runner_swarm_radius * 0.16)
	for i in range(_gate_runner_clones.size() - 1, -1, -1):
		var entry: Dictionary = _gate_runner_clones[i]
		var clone_v: Variant = entry.get("node", null)
		if not (clone_v is Node2D) or not is_instance_valid(clone_v):
			_gate_runner_clones.remove_at(i)
			continue
		var clone: Node2D = clone_v as Node2D
		entry["drift_timer"] = float(entry.get("drift_timer", 0.0)) - delta
		if float(entry["drift_timer"]) <= 0.0:
			entry["drift_timer"] = randf_range(drift_min, drift_max)
			entry["target_offset"] = (entry.get("base_offset", Vector2.ZERO) as Vector2) \
				+ Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
		var current_offset: Vector2 = entry.get("offset", Vector2.ZERO) as Vector2
		entry["offset"] = current_offset.lerp(entry.get("target_offset", Vector2.ZERO) as Vector2, follow)
		var t: float = _gate_runner_swarm_time * TAU * freq + float(entry.get("phase", 0.0))
		clone.position = (entry["offset"] as Vector2) + Vector2(sin(t), cos(t * 0.83 + 1.7)) * amp

func _clear_gate_runner_swarm() -> void:
	_gate_runner_clones.clear()
	_gate_runner_swarm_radius = 0.0
	if _gate_runner_swarm_root and is_instance_valid(_gate_runner_swarm_root):
		_gate_runner_swarm_root.queue_free()
	_gate_runner_swarm_root = null

func _apply_ship_scale(mult: float) -> void:
	_gate_runner_current_scale = mult
	var s: Vector2 = Vector2.ONE * mult
	if visual_container and is_instance_valid(visual_container):
		visual_container.scale = s
	if hitbox and is_instance_valid(hitbox):
		hitbox.scale = s
	var main_col: Node = get_node_or_null("CollisionShape2D")
	if main_col is Node2D:
		(main_col as Node2D).scale = s

func _ensure_big_hp_label() -> void:
	if _big_hp_label and is_instance_valid(_big_hp_label):
		return
	_big_hp_label = Label.new()
	_big_hp_label.name = "GateRunnerHPLabel"
	_big_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big_hp_label.add_theme_font_size_override("font_size", 56)
	_big_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_big_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_big_hp_label.add_theme_constant_override("outline_size", 8)
	_big_hp_label.size = Vector2(240, 90)
	_big_hp_label.position = Vector2(-120, -150)
	_big_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_hp_label.z_as_relative = false
	_big_hp_label.z_index = 80
	add_child(_big_hp_label)

func _update_big_hp_label() -> void:
	if _big_hp_label == null or not is_instance_valid(_big_hp_label):
		return
	# Formatage compact K/M (« 1,5K », « 2,5M ») — lisibilité des gros nombres.
	_big_hp_label.text = NumberFormat.compact(float(current_hp))

func _play_gate_juice(is_bonus: bool) -> void:
	var col: Color = Color(0.45, 1.0, 0.55) if is_bonus else Color(1.0, 0.5, 0.45)
	if VFXManager and visual_container and is_instance_valid(visual_container):
		VFXManager.flash_sprite(visual_container, col, 0.15)

# =============================================================================
# PONG WAVE
# =============================================================================

## Enters pong mode: Y tweens down to the paddle line and stays locked there,
## X movement stays player-controlled, the ship visual is squashed into a paddle.
## The paddle collision itself is resolved by PongManager (manual AABB), so the
## hitbox/collision shapes are left untouched.
func begin_pong(cfg: Dictionary) -> void:
	_pong_active = true
	var viewport_size: Vector2 = get_viewport_rect().size
	var target_y: float = viewport_size.y * clampf(float(cfg.get("player_paddle_y_ratio", 0.9)), 0.5, 0.97)
	_pong_lock_y = global_position.y
	if _pong_lock_tween and _pong_lock_tween.is_valid():
		_pong_lock_tween.kill()
	var intro_sec: float = maxf(0.05, float(cfg.get("intro_tween_sec", 0.6)))
	_pong_lock_tween = create_tween()
	_pong_lock_tween.tween_property(self, "_pong_lock_y", target_y, intro_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Écrase le vaisseau EXACTEMENT sur la hitbox de raquette (cover) : la
	# balle ne doit jamais chevaucher le visuel sans rebondir. Fallback sur les
	# scales configurés (player_squash_scale_x/y) si le visuel n'est pas
	# mesurable (forme procédurale sans sprite).
	var squash := Vector2(
		maxf(0.05, float(cfg.get("player_squash_scale_x", 2.2))),
		maxf(0.05, float(cfg.get("player_squash_scale_y", 0.35)))
	)
	var base_size: Vector2 = _ship_visual_base_size()
	if base_size.x > 1.0 and base_size.y > 1.0:
		var paddle_size := Vector2(
			maxf(16.0, float(cfg.get("player_paddle_half_width_px", 96.0))) * 2.0,
			maxf(6.0, float(cfg.get("player_paddle_half_height_px", 16.0))) * 2.0
		)
		squash = paddle_size / base_size
	if visual_container and is_instance_valid(visual_container):
		_pong_lock_tween.parallel().tween_property(visual_container, "scale", squash, intro_sec) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Leaves pong mode: unlocks Y and restores the ship shape.
func end_pong() -> void:
	if _pong_lock_tween and _pong_lock_tween.is_valid():
		_pong_lock_tween.kill()
	_pong_lock_tween = null
	if not _pong_active:
		return
	_pong_active = false
	_apply_ship_scale(1.0)

func is_pong_active() -> bool:
	return _pong_active

## Taille affichée (px) du visuel vaisseau, container à l'échelle 1 : texture du
## sprite visible × son scale propre. Vector2.ZERO si aucun sprite mesurable.
func _ship_visual_base_size() -> Vector2:
	if visual_container == null or not is_instance_valid(visual_container):
		return Vector2.ZERO
	var anim: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
	if anim and anim.visible and anim.sprite_frames:
		var anim_name: StringName = anim.animation
		if anim.sprite_frames.has_animation(anim_name) and anim.sprite_frames.get_frame_count(anim_name) > 0:
			var tex: Texture2D = anim.sprite_frames.get_frame_texture(anim_name, 0)
			if tex:
				return tex.get_size() * anim.scale.abs()
	var spr: Sprite2D = visual_container.get_node_or_null("Sprite2D")
	if spr and spr.visible and spr.texture:
		return spr.texture.get_size() * spr.scale.abs()
	return Vector2.ZERO

# =============================================================================
# BALL LAUNCHER WAVE
# =============================================================================

## Enters ball-launcher mode: Y tweens down to the launch line and stays
## locked there (no visual squash — the ship stays a ship). X is driven by the
## BallLauncherManager through set_ball_launcher_x (finger follow, frozen
## while aiming); the ship glides toward that target with a fast exponential
## snap, like the lane runner.
func begin_ball_launcher(cfg: Dictionary) -> void:
	_ball_launcher_active = true
	_ball_launcher_snap_speed = maxf(2.0, float(cfg.get("ship_snap_speed", 14.0)))
	_ball_launcher_target_x = global_position.x
	_ball_launcher_lock_y = global_position.y
	var viewport_size: Vector2 = get_viewport_rect().size
	var target_y: float = viewport_size.y * clampf(float(cfg.get("player_y_ratio", 0.9)), 0.5, 0.97)
	if _ball_launcher_lock_tween and _ball_launcher_lock_tween.is_valid():
		_ball_launcher_lock_tween.kill()
	var intro_sec: float = maxf(0.05, float(cfg.get("intro_tween_sec", 0.6)))
	_ball_launcher_lock_tween = create_tween()
	_ball_launcher_lock_tween.tween_property(self, "_ball_launcher_lock_y", target_y, intro_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Leaves ball-launcher mode: unlocks X/Y.
func end_ball_launcher() -> void:
	if _ball_launcher_lock_tween and _ball_launcher_lock_tween.is_valid():
		_ball_launcher_lock_tween.kill()
	_ball_launcher_lock_tween = null
	_ball_launcher_active = false

## Called by the BallLauncherManager: horizontal launch-point target.
func set_ball_launcher_x(x: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_ball_launcher_target_x = clampf(x, 20.0, viewport_size.x - 20.0)

func is_ball_launcher_active() -> bool:
	return _ball_launcher_active

# =============================================================================
# VERTICAL CLIMB WAVE
# =============================================================================

## Enters climb mode: the VerticalClimbManager drives Y every frame through
## set_climb_y() (gravity + accelerator bounces), X stays player-controlled.
func begin_climb(cfg: Dictionary = {}) -> void:
	_climb_active = true
	_climb_y = global_position.y
	_climb_wrap_x = bool(cfg.get("wrap_horizontal", false))

func end_climb() -> void:
	_climb_active = false
	_climb_wrap_x = false

func set_climb_y(y: float) -> void:
	_climb_y = y

func get_climb_y() -> float:
	return _climb_y

func is_climb_active() -> bool:
	return _climb_active

# =============================================================================
# ABSORB WAVE
# =============================================================================

## Enters absorb mode: the AbsorbManager owns the mass value and pushes it
## through set_absorb_mass(); the ship grows with the mass (reuses the big
## gate-runner label and _apply_ship_scale). Movement stays fully free.
func begin_absorb(cfg: Dictionary) -> void:
	_absorb_active = true
	_absorb_start_mass = maxf(1.0, float(cfg.get("start_mass", 10.0)))
	_absorb_scale_base = maxf(0.1, float(cfg.get("ship_scale_base", 1.0)))
	_absorb_scale_min = maxf(0.05, float(cfg.get("ship_scale_min", 0.8)))
	_absorb_scale_max = maxf(_absorb_scale_min, float(cfg.get("ship_scale_max", 2.4)))
	_ensure_big_hp_label()
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.visible = true
	set_absorb_mass(_absorb_start_mass)

func set_absorb_mass(mass: float) -> void:
	if not _absorb_active:
		return
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.text = str(int(round(mass)))
	# Sqrt growth: the ship gets visibly bigger without ever exploding.
	var mult: float = clampf(_absorb_scale_base * sqrt(maxf(1.0, mass) / _absorb_start_mass), _absorb_scale_min, _absorb_scale_max)
	_apply_ship_scale(mult)

func end_absorb() -> void:
	if not _absorb_active:
		return
	_absorb_active = false
	_apply_ship_scale(1.0)
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.visible = false

func is_absorb_active() -> bool:
	return _absorb_active

# =============================================================================
# LANE RUNNER WAVE
# =============================================================================

## Enters lane-runner mode: Y tweens down to the run line and stays locked,
## X snaps to one of `lane_count` fixed lanes. Lane switching is swipe-based
## (see _input) or via the left/right arrows on desktop.
func begin_lane_runner(cfg: Dictionary) -> void:
	_lane_runner_active = true
	_lane_count = maxi(2, int(cfg.get("lane_count", 3)))
	_lane_side_margin_px = maxf(10.0, float(cfg.get("lane_side_margin_px", 70.0)))
	_lane_snap_speed = maxf(2.0, float(cfg.get("lane_snap_speed", 14.0)))
	_lane_swipe_threshold_px = maxf(8.0, float(cfg.get("swipe_threshold_px", 48.0)))
	_lane_gesture_id = -1
	_lane_gesture_consumed = false
	var viewport_size: Vector2 = get_viewport_rect().size
	var target_y: float = viewport_size.y * clampf(float(cfg.get("player_y_ratio", 0.82)), 0.4, 0.95)
	# Start on the lane nearest to the current ship position.
	var nearest: int = 0
	var best_dist: float = INF
	for i in range(_lane_count):
		var d: float = absf(get_lane_runner_lane_center_x(i) - global_position.x)
		if d < best_dist:
			best_dist = d
			nearest = i
	_lane_index = nearest
	_lane_render_x = global_position.x
	_lane_lock_y = global_position.y
	_lane_last_switch_msec = -100000
	if _lane_lock_tween and _lane_lock_tween.is_valid():
		_lane_lock_tween.kill()
	var intro_sec: float = maxf(0.05, float(cfg.get("intro_tween_sec", 0.7)))
	_lane_lock_tween = create_tween()
	_lane_lock_tween.tween_property(self, "_lane_lock_y", target_y, intro_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Leaves lane-runner mode: unlocks X/Y.
func end_lane_runner() -> void:
	if _lane_lock_tween and _lane_lock_tween.is_valid():
		_lane_lock_tween.kill()
	_lane_lock_tween = null
	_lane_runner_active = false
	_lane_gesture_id = -1
	_lane_gesture_consumed = false

## Lane-runner swipe input: one gesture (press -> first horizontal move past
## the threshold) = ONE lane shift; any further motion, including direction
## reversals, is ignored until the finger/button is released and re-pressed.
## Raw touches are read in _input like VirtualJoystick (the only phase proven
## reliable in the real scene); the mouse is handled explicitly with the same
## cross-guards as SliceRushManager so touch/mouse emulation pairs run once.
func _input(event: InputEvent) -> void:
	if not _lane_runner_active:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _lane_gesture_id == -1:
			_lane_gesture_begin(touch.index, touch.position)
		elif not touch.pressed and touch.index == _lane_gesture_id:
			_lane_gesture_id = -1
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _lane_gesture_id:
			_lane_gesture_feed(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed and _lane_gesture_id == -1:
			_lane_gesture_begin(LANE_MOUSE_CAPTURE_ID, mouse_btn.position)
		elif not mouse_btn.pressed and _lane_gesture_id == LANE_MOUSE_CAPTURE_ID:
			_lane_gesture_id = -1
	elif event is InputEventMouseMotion and _lane_gesture_id == LANE_MOUSE_CAPTURE_ID:
		_lane_gesture_feed((event as InputEventMouseMotion).position)

func _lane_gesture_begin(capture_id: int, screen_pos: Vector2) -> void:
	_lane_gesture_id = capture_id
	_lane_gesture_start_x = (get_canvas_transform().affine_inverse() * screen_pos).x
	_lane_gesture_consumed = false

func _lane_gesture_feed(screen_pos: Vector2) -> void:
	if _lane_gesture_consumed:
		return
	var dx: float = (get_canvas_transform().affine_inverse() * screen_pos).x - _lane_gesture_start_x
	if absf(dx) >= _lane_swipe_threshold_px:
		_lane_gesture_consumed = true
		_lane_runner_shift(1 if dx > 0.0 else -1)

func is_lane_runner_active() -> bool:
	return _lane_runner_active

func get_lane_runner_lane() -> int:
	return _lane_index

## Milliseconds since the last lane switch (near-miss window checks).
func get_lane_runner_msec_since_switch() -> int:
	return Time.get_ticks_msec() - _lane_last_switch_msec

func get_lane_runner_lane_center_x(lane: int) -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable: float = maxf(1.0, viewport_size.x - _lane_side_margin_px * 2.0)
	var lane_width: float = usable / float(_lane_count)
	return _lane_side_margin_px + lane_width * (float(clampi(lane, 0, _lane_count - 1)) + 0.5)

func _lane_runner_lane_width() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	return maxf(1.0, viewport_size.x - _lane_side_margin_px * 2.0) / float(_lane_count)

## Switches one lane over (clamped on the edge lanes).
func _lane_runner_shift(dir: int) -> void:
	var target: int = clampi(_lane_index + dir, 0, _lane_count - 1)
	if target == _lane_index:
		return
	_lane_index = target
	_lane_last_switch_msec = Time.get_ticks_msec()

## Téléportation externe (portails du lane_runner) : pose la voie ET snap le
## rendu instantanément (pas de glissement — c'est un blink, pas un dash).
func set_lane_runner_lane(lane: int) -> void:
	if not _lane_runner_active:
		return
	var target: int = clampi(lane, 0, _lane_count - 1)
	if target == _lane_index:
		return
	_lane_index = target
	_lane_last_switch_msec = Time.get_ticks_msec()
	_lane_render_x = get_lane_runner_lane_center_x(_lane_index)
	global_position.x = _lane_render_x

## Applied at the end of _handle_movement: X/Y are fully lane-driven — lane
## switches come from swipes (_input) or arrow keys; the ship glides onto its
## lane center (fast exponential snap).
func _apply_lane_runner_lock(delta: float) -> void:
	if Input.is_action_just_pressed("ui_left"):
		_lane_runner_shift(-1)
	elif Input.is_action_just_pressed("ui_right"):
		_lane_runner_shift(1)

	_lane_render_x = lerpf(
		_lane_render_x,
		get_lane_runner_lane_center_x(_lane_index),
		clampf(delta * _lane_snap_speed, 0.0, 1.0)
	)
	global_position.x = _lane_render_x
	global_position.y = _lane_lock_y

# =============================================================================
# SLICE RUSH WAVE
# =============================================================================

## Enters slice-rush mode: the ship tweens down to the bottom center and stays
## fully locked (X and Y). All regular movement input (stick / follow finger /
## mouse) is neutralized; the SliceRushManager reads the raw touches itself.
func begin_slice_rush(cfg: Dictionary) -> void:
	_slice_rush_active = true
	_slice_rush_lock_pos = global_position
	var viewport_size: Vector2 = get_viewport_rect().size
	var target := Vector2(
		viewport_size.x * clampf(float(cfg.get("player_x_ratio", 0.5)), 0.05, 0.95),
		viewport_size.y * clampf(float(cfg.get("player_y_ratio", 0.9)), 0.5, 0.95)
	)
	if _slice_rush_lock_tween and _slice_rush_lock_tween.is_valid():
		_slice_rush_lock_tween.kill()
	var intro_sec: float = maxf(0.05, float(cfg.get("intro_tween_sec", 0.7)))
	_slice_rush_lock_tween = create_tween()
	_slice_rush_lock_tween.tween_property(self, "_slice_rush_lock_pos", target, intro_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Leaves slice-rush mode: unlocks the ship.
func end_slice_rush() -> void:
	if _slice_rush_lock_tween and _slice_rush_lock_tween.is_valid():
		_slice_rush_lock_tween.kill()
	_slice_rush_lock_tween = null
	_slice_rush_active = false

func is_slice_rush_active() -> bool:
	return _slice_rush_active

# =============================================================================
# SUIKA UP WAVE
# =============================================================================

## Enters suika-up mode: the ship tweens to the boss/reactor border and stays
## fully locked (X and Y). The SuikaUpManager reads the raw touches itself;
## shooting is cut by Game — the ship only fires when a shape is consumed.
func begin_suika_up(cfg: Dictionary) -> void:
	_suika_up_active = true
	_suika_up_lock_pos = global_position
	var viewport_size: Vector2 = get_viewport_rect().size
	var target := Vector2(
		viewport_size.x * clampf(float(cfg.get("ship_lock_x_ratio", 0.5)), 0.05, 0.95),
		viewport_size.y * clampf(float(cfg.get("ship_lock_y_ratio", 0.36)), 0.15, 0.8)
	)
	if _suika_up_lock_tween and _suika_up_lock_tween.is_valid():
		_suika_up_lock_tween.kill()
	var intro_sec: float = maxf(0.05, float(cfg.get("intro_arrival_sec", 1.0)))
	_suika_up_lock_tween = create_tween()
	_suika_up_lock_tween.tween_property(self, "_suika_up_lock_pos", target, intro_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Leaves suika-up mode: unlocks the ship.
func end_suika_up() -> void:
	if _suika_up_lock_tween and _suika_up_lock_tween.is_valid():
		_suika_up_lock_tween.kill()
	_suika_up_lock_tween = null
	_suika_up_active = false

# =============================================================================
# MATCH 3 WAVE
# =============================================================================

## Enters match3 mode: full lock, ship shrunk to a board cell, additive glow
## attached behind the visuals. The Match3Manager drives the position through
## set_match3_lock_pos (tweened from the manager side).
func begin_match3(cfg: Dictionary) -> void:
	_match3_active = true
	_match3_lock_pos = global_position
	_apply_ship_scale(clampf(float(cfg.get("ship_scale_mult", 0.68)), 0.2, 1.5))
	_attach_match3_glow(cfg)

## Leaves match3 mode: restores scale, removes the glow, unlocks the ship.
func end_match3() -> void:
	if not _match3_active:
		_remove_match3_glow()
		return
	_match3_active = false
	_remove_match3_glow()
	_apply_ship_scale(1.0)

func is_match3_active() -> bool:
	return _match3_active

func set_match3_lock_pos(pos: Vector2) -> void:
	_match3_lock_pos = pos

func get_match3_lock_pos() -> Vector2:
	return _match3_lock_pos

# =============================================================================
# SNAKE WAVE
# =============================================================================

## Enters snake mode: the ship becomes the snake head — full lock, the
## SnakeManager drives position (set_snake_lock_pos) and heading
## (set_snake_facing) every frame.
func begin_snake(cfg: Dictionary) -> void:
	_snake_active = true
	_snake_lock_pos = global_position
	_apply_ship_scale(clampf(float(cfg.get("ship_scale_mult", 0.8)), 0.2, 1.5))

## Leaves snake mode: restores scale and heading, unlocks the ship.
func end_snake() -> void:
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = 0.0
	if not _snake_active:
		return
	_snake_active = false
	_apply_ship_scale(1.0)

func is_snake_active() -> bool:
	return _snake_active

func set_snake_lock_pos(pos: Vector2) -> void:
	_snake_lock_pos = pos

func set_snake_facing(angle: float) -> void:
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = angle

## Additive glow behind the ship so the joker tile reads instantly. Child of
## visual_container (index 0) -> follows the ship scale automatically.
func _attach_match3_glow(cfg: Dictionary) -> void:
	_remove_match3_glow()
	if visual_container == null or not is_instance_valid(visual_container):
		return
	var asset_path: String = str(cfg.get("glow_asset", ""))
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if not (res is SpriteFrames):
		return
	var frames: SpriteFrames = res as SpriteFrames
	_match3_glow = AnimatedSprite2D.new()
	_match3_glow.name = "Match3Glow"
	_match3_glow.sprite_frames = frames
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if frames.has_animation(anim_name):
		_match3_glow.play(anim_name)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_match3_glow.material = add_mat
	_match3_glow.modulate = Color(str(cfg.get("glow_tint", "#8FD3FFB4")))
	# Scale relative to the UNSCALED ship footprint (84 px baseline): the glow
	# is inside visual_container so _apply_ship_scale shrinks both together.
	var glow_px: float = 84.0 * maxf(0.2, float(cfg.get("glow_scale", 1.7)))
	var base_scale: float = 1.0
	if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
		var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
		if frame_tex:
			var f_size: Vector2 = frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				base_scale = glow_px / maxf(f_size.x, f_size.y)
	_match3_glow.scale = Vector2.ONE * base_scale
	visual_container.add_child(_match3_glow)
	visual_container.move_child(_match3_glow, 0)
	var pulse_sec: float = maxf(0.1, float(cfg.get("glow_pulse_sec", 0.8)))
	_match3_glow_tween = _match3_glow.create_tween()
	_match3_glow_tween.set_loops()
	_match3_glow_tween.tween_property(_match3_glow, "scale", Vector2.ONE * base_scale * 1.18, pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_match3_glow_tween.tween_property(_match3_glow, "scale", Vector2.ONE * base_scale, pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _remove_match3_glow() -> void:
	if _match3_glow_tween and _match3_glow_tween.is_valid():
		_match3_glow_tween.kill()
	_match3_glow_tween = null
	if _match3_glow and is_instance_valid(_match3_glow):
		_match3_glow.queue_free()
	_match3_glow = null

# =============================================================================
# GRAVITY HOLE WAVE
# =============================================================================

## Enters gravity-hole mode: the ship becomes a free-roaming gravity vortex.
## Movement stays fully free (and the top forbidden zone is lifted via
## _get_player_top_limit_y); the big label shows the mass; an animated aura
## sits behind the ship, hidden until the intro cover hands off to it. The
## absorption radius stays owned by the manager (set_gravity_hole_radius).
func begin_gravity_hole(cfg: Dictionary) -> void:
	# Defensive: no other special mode may leak into this one.
	if _absorb_active:
		end_absorb()
	if _slice_rush_active:
		end_slice_rush()
	if _match3_active:
		end_match3()
	if _lane_runner_active:
		end_lane_runner()
	_gravity_hole_active = true
	_gh_start_mass = maxf(1.0, float(cfg.get("start_mass", 10.0)))
	_gh_scale_base = maxf(0.2, float(cfg.get("visual_scale_base", 1.0)))
	_gh_scale_min = maxf(0.2, float(cfg.get("visual_scale_min", 0.75)))
	_gh_scale_max = maxf(_gh_scale_min, float(cfg.get("visual_scale_max", 1.55)))
	_gh_aura_pulse_scale = maxf(1.0, float(cfg.get("aura_pulse_scale", 1.15)))
	_gh_aura_pulse_sec = maxf(0.05, float(cfg.get("aura_pulse_sec", 0.18)))
	_ensure_big_hp_label()
	if _big_hp_label:
		_big_hp_label.visible = true
	_attach_gravity_hole_aura(cfg)
	set_gravity_hole_mass(_gh_start_mass)

## Mass drives the label and the ship visual scale (sqrt growth, clamped).
func set_gravity_hole_mass(mass: float) -> void:
	if not _gravity_hole_active:
		return
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.text = str(int(round(mass)))
	var mult: float = clampf(_gh_scale_base * sqrt(maxf(1.0, mass) / _gh_start_mass), _gh_scale_min, _gh_scale_max)
	_apply_ship_scale(mult)

## Verrou centre (refonte Agar.io) : le vaisseau reste à pos fixe, le monde
## défile autour. Neutralise tout l'input de déplacement (_handle_movement).
func set_gravity_hole_center_lock(pos: Vector2) -> void:
	_gh_center_locked = true
	_gh_lock_pos = pos
	global_position = pos

## Orientation smooth pilotée par le manager (angle absolu, radians — 0 = haut
## car le sprite pointe vers le haut). Restaurée à end_gravity_hole.
func set_gravity_hole_facing(angle: float) -> void:
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = angle

## The aura diameter follows the ABSORPTION radius pushed by the manager.
func set_gravity_hole_radius(radius_px: float) -> void:
	if _gh_aura == null or not is_instance_valid(_gh_aura) or _gh_aura_frame_dim <= 0.0:
		return
	_gh_aura_base_scale = maxf(0.01, radius_px * 2.0 * _gh_aura_visual_ratio / _gh_aura_frame_dim)
	if _gh_aura_pulse_tween == null or not _gh_aura_pulse_tween.is_valid():
		_gh_aura.scale = Vector2.ONE * _gh_aura_base_scale

## Handoff from the intro/outro cover sprite: same asset, same size formula —
## syncing the animation frame makes the swap seamless.
func set_gravity_hole_aura_visible(aura_visible: bool, sync_frame: int = -1) -> void:
	if _gh_aura == null or not is_instance_valid(_gh_aura):
		return
	_gh_aura.visible = aura_visible
	if sync_frame >= 0 and _gh_aura.sprite_frames != null:
		var anim_name: StringName = _gh_aura.animation
		if _gh_aura.sprite_frames.has_animation(anim_name) \
			and sync_frame < _gh_aura.sprite_frames.get_frame_count(anim_name):
			_gh_aura.frame = sync_frame
	if _gh_aura_pulse_tween == null or not _gh_aura_pulse_tween.is_valid():
		_gh_aura.scale = Vector2.ONE * _gh_aura_base_scale

## Small satisfaction kick on each absorption (kill-and-replace).
func pulse_gravity_hole_aura() -> void:
	if _gh_aura == null or not is_instance_valid(_gh_aura):
		return
	if _gh_aura_pulse_tween and _gh_aura_pulse_tween.is_valid():
		_gh_aura_pulse_tween.kill()
	_gh_aura_pulse_tween = _gh_aura.create_tween()
	_gh_aura_pulse_tween.tween_property(_gh_aura, "scale", Vector2.ONE * _gh_aura_base_scale * _gh_aura_pulse_scale, _gh_aura_pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_gh_aura_pulse_tween.tween_property(_gh_aura, "scale", Vector2.ONE * _gh_aura_base_scale, _gh_aura_pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Leaves gravity-hole mode: restores scale, label, rotation, center lock and
## the top zone (implicit).
func end_gravity_hole() -> void:
	_remove_gravity_hole_aura()
	_gh_center_locked = false
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = 0.0
	if not _gravity_hole_active:
		return
	_gravity_hole_active = false
	_apply_ship_scale(1.0)
	if _big_hp_label and is_instance_valid(_big_hp_label):
		_big_hp_label.visible = false

func is_gravity_hole_active() -> bool:
	return _gravity_hole_active

## Additive animated aura behind the ship, direct Player child at index 0
## (outside visual_container: its scale tracks the absorption radius, not the
## ship mass scale). Hidden until the intro handoff.
func _attach_gravity_hole_aura(cfg: Dictionary) -> void:
	_remove_gravity_hole_aura()
	var asset_path: String = str(cfg.get("aura_asset", ""))
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if not (res is SpriteFrames):
		return
	var frames: SpriteFrames = res as SpriteFrames
	_gh_aura = AnimatedSprite2D.new()
	_gh_aura.name = "GravityHoleAura"
	_gh_aura.sprite_frames = frames
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if frames.has_animation(anim_name):
		_gh_aura.play(anim_name)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_gh_aura.material = add_mat
	_gh_aura.modulate = Color(str(cfg.get("aura_tint", "#2A1848C8")))
	_gh_aura_visual_ratio = maxf(0.2, float(cfg.get("aura_visual_ratio", 1.08)))
	_gh_aura_frame_dim = 1.0
	if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
		var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
		if frame_tex:
			var f_size: Vector2 = frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				_gh_aura_frame_dim = maxf(f_size.x, f_size.y)
	_gh_aura.visible = false
	add_child(_gh_aura)
	move_child(_gh_aura, 0)

func _remove_gravity_hole_aura() -> void:
	if _gh_aura_pulse_tween and _gh_aura_pulse_tween.is_valid():
		_gh_aura_pulse_tween.kill()
	_gh_aura_pulse_tween = null
	if _gh_aura and is_instance_valid(_gh_aura):
		_gh_aura.queue_free()
	_gh_aura = null

# =============================================================================
# STAR DRIFT WAVE
# =============================================================================

## Star drift mode (Super Starfish): the ship glides after the finger with
## inertia — the velocity eases toward the target instead of snapping, so the
## ship keeps drifting when the finger stops or lifts. Free movement in all
## four directions (the top forbidden zone is bypassed: vertical dodging is
## part of the wave); shooting is cut by Game via set_can_shoot.
var _star_drift_active: bool = false
var _sd_velocity: Vector2 = Vector2.ZERO
var _sd_follow_gain: float = 7.0
var _sd_max_speed: float = 950.0
var _sd_inertia_response: float = 6.0
var _sd_finger_offset_y: float = -110.0
var _sd_deadzone_px: float = 4.0

func begin_star_drift(cfg: Dictionary) -> void:
	# Defensive: no other special mode may leak into this one.
	if _absorb_active:
		end_absorb()
	if _slice_rush_active:
		end_slice_rush()
	if _match3_active:
		end_match3()
	if _snake_active:
		end_snake()
	if _lane_runner_active:
		end_lane_runner()
	if _gravity_hole_active:
		end_gravity_hole()
	_star_drift_active = true
	_sd_velocity = Vector2.ZERO
	_sd_follow_gain = maxf(0.5, float(cfg.get("control_follow_gain", 7.0)))
	_sd_max_speed = maxf(100.0, float(cfg.get("control_max_speed_px_sec", 950.0)))
	_sd_inertia_response = maxf(0.5, float(cfg.get("control_inertia_response", 6.0)))
	_sd_finger_offset_y = float(cfg.get("control_finger_offset_y", -110.0))
	_sd_deadzone_px = maxf(0.0, float(cfg.get("control_deadzone_px", 4.0)))

func end_star_drift() -> void:
	if not _star_drift_active:
		return
	_star_drift_active = false
	_sd_velocity = Vector2.ZERO

func is_star_drift_active() -> bool:
	return _star_drift_active

# =============================================================================
# SURVIVOR MODE (VS-like) : même déplacement inertiel libre que star_drift
# (la branche _handle_movement est partagée) + orientation du vaisseau vers la
# direction du déplacement, pilotée par le SurvivorManager.
# =============================================================================
var _survivor_active: bool = false

## Ré-appelable (idempotent) : le passif move_speed du survivor ré-applique la
## config avec un control_max_speed_px_sec multiplié.
func begin_survivor(cfg: Dictionary) -> void:
	if not _survivor_active:
		# Defensive: no other special mode may leak into this one.
		if _absorb_active:
			end_absorb()
		if _slice_rush_active:
			end_slice_rush()
		if _match3_active:
			end_match3()
		if _snake_active:
			end_snake()
		if _lane_runner_active:
			end_lane_runner()
		if _gravity_hole_active:
			end_gravity_hole()
		if _star_drift_active:
			end_star_drift()
		_sd_velocity = Vector2.ZERO
	_survivor_active = true
	_sd_follow_gain = maxf(0.5, float(cfg.get("control_follow_gain", 7.0)))
	_sd_max_speed = maxf(100.0, float(cfg.get("control_max_speed_px_sec", 620.0)))
	_sd_inertia_response = maxf(0.5, float(cfg.get("control_inertia_response", 6.0)))
	_sd_finger_offset_y = float(cfg.get("control_finger_offset_y", -110.0))
	_sd_deadzone_px = maxf(0.0, float(cfg.get("control_deadzone_px", 4.0)))

func end_survivor() -> void:
	if not _survivor_active:
		return
	_survivor_active = false
	_sd_velocity = Vector2.ZERO
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = 0.0

func is_survivor_active() -> bool:
	return _survivor_active

## Vélocité de déplacement courante (pour le facing calculé par le manager).
func get_survivor_velocity() -> Vector2:
	return _sd_velocity

## Orientation smooth pilotée par le manager (0 = haut, sprite vers le haut).
func set_survivor_facing(angle: float) -> void:
	if visual_container and is_instance_valid(visual_container):
		visual_container.rotation = angle

# =============================================================================
# FIRE PATTERN: AURA SYSTEM
# =============================================================================

## Set up the Area2D for the aura damage zone.
func _setup_aura_area() -> void:
	if _aura_area != null:
		return
	_aura_area = Area2D.new()
	_aura_area.name = "AuraZone"
	_aura_area.collision_layer = 0
	_aura_area.collision_mask = 4 # Same as hitbox: detects enemies
	_aura_area.monitoring = true
	_aura_area.monitorable = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 1.0 # Will be updated dynamically
	col.shape = shape
	_aura_area.add_child(col)
	if not _aura_area.body_entered.is_connected(_on_aura_body_entered):
		_aura_area.body_entered.connect(_on_aura_body_entered)
	if not _aura_area.body_exited.is_connected(_on_aura_body_exited):
		_aura_area.body_exited.connect(_on_aura_body_exited)
	if not _aura_area.area_entered.is_connected(_on_aura_area_entered):
		_aura_area.area_entered.connect(_on_aura_area_entered)
	if not _aura_area.area_exited.is_connected(_on_aura_area_exited):
		_aura_area.area_exited.connect(_on_aura_area_exited)
	add_child(_aura_area)

## Sets the active fire pattern for the current run (from a fire pattern drop).
## Pass "" to revert to the ship's native pattern.
func set_active_fire_pattern(pattern_id: String) -> void:
	_active_fire_pattern_id = str(pattern_id)
	# If we leave an aura pattern, make sure the persistent aura stops.
	var fire_data := SkillManager.get_fire_pattern_data(_active_fire_pattern_id)
	if not bool(fire_data.get("is_aura", false)):
		_deactivate_aura()
	# Force the next shot to use the new pattern immediately.
	_fire_timer = 0.0

## Returns the active fire pattern id for the current run ("" = ship default).
func get_active_fire_pattern() -> String:
	return _active_fire_pattern_id

## Activate the aura with the given fire_data parameters.
func _activate_aura(fire_data: Dictionary) -> void:
	_setup_aura_area()
	var new_radius := float(fire_data.get("radius", 60.0))
	var new_dps := float(fire_data.get("tick_dps", 5.0))
	var new_interval := float(fire_data.get("tick_interval", 0.5))

	_aura_radius = new_radius
	_aura_dps = new_dps
	_aura_tick_interval = new_interval

	# Update collision shape radius
	for child in _aura_area.get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			child.shape.radius = _aura_radius

	if not _aura_active:
		_aura_active = true
		_aura_timer = 0.0
		_create_aura_visual()
		print("[Player] Aura ACTIVATED — radius=", _aura_radius, " dps=", _aura_dps)

## Deactivate the aura.
func _deactivate_aura() -> void:
	if not _aura_active:
		return
	_aura_active = false
	_aura_timer = 0.0
	_aura_targets.clear()
	if _aura_visual and is_instance_valid(_aura_visual):
		_aura_visual.queue_free()
		_aura_visual = null

## Create a simple visual indicator for the aura.
func _create_aura_visual() -> void:
	if _aura_visual and is_instance_valid(_aura_visual):
		_aura_visual.queue_free()
	var circle := Node2D.new()
	circle.name = "AuraVisual"
	var draw_node := _AuraDrawNode.new()
	draw_node.aura_radius = _aura_radius
	draw_node.aura_color = Color(1.0, 0.3, 0.1, 0.25)
	circle.add_child(draw_node)
	add_child(circle)
	_aura_visual = circle

## Update aura tick damage each frame.
func _update_aura(delta: float) -> void:
	if not _aura_active:
		return
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = _aura_tick_interval
		_apply_aura_damage()

## Apply tick damage to all enemies inside the aura.
func _apply_aura_damage() -> void:
	if _aura_area == null or not is_instance_valid(_aura_area):
		return
	var tick_damage := int(_aura_dps * _aura_tick_interval * damage_multiplier)
	if tick_damage <= 0:
		tick_damage = 1

	# Keep targets fresh from both body and area overlaps.
	var bodies := _aura_area.get_overlapping_bodies()
	for body in bodies:
		_register_aura_target(body)
	var areas := _aura_area.get_overlapping_areas()
	for area in areas:
		_register_aura_target(area)

	for target in _aura_targets.duplicate():
		if not is_instance_valid(target):
			_aura_targets.erase(target)
			continue
		if not target.is_in_group("enemies"):
			_aura_targets.erase(target)
			continue
		if target.has_method("take_damage"):
			target.take_damage(tick_damage)

func _resolve_aura_enemy(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.is_in_group("enemies"):
		return node
	var parent := node.get_parent()
	if parent and parent.is_in_group("enemies"):
		return parent
	return null

func _register_aura_target(node: Node) -> void:
	var enemy := _resolve_aura_enemy(node)
	if enemy == null:
		return
	if not _aura_targets.has(enemy):
		_aura_targets.append(enemy)

func _unregister_aura_target(node: Node) -> void:
	var enemy := _resolve_aura_enemy(node)
	if enemy == null:
		return
	if _aura_targets.has(enemy):
		_aura_targets.erase(enemy)

func _on_aura_body_entered(body: Node2D) -> void:
	_register_aura_target(body)

func _on_aura_body_exited(body: Node2D) -> void:
	_unregister_aura_target(body)

func _on_aura_area_entered(area: Area2D) -> void:
	_register_aura_target(area)

func _on_aura_area_exited(area: Area2D) -> void:
	_unregister_aura_target(area)

## Inner draw helper for the aura circle visual.
class _AuraDrawNode extends Node2D:
	var aura_radius: float = 60.0
	var aura_color: Color = Color(1.0, 0.3, 0.1, 0.25)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, aura_radius, aura_color)
		draw_arc(Vector2.ZERO, aura_radius, 0, TAU, 64, aura_color.lightened(0.4), 2.0)


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

func _handle_shield_regen(delta: float) -> void:
	if not shield_active:
		return
	if shield_energy >= shield_max_energy:
		return
	if shield_regen_bonus <= 0.0:
		return

	shield_energy = minf(shield_max_energy, shield_energy + (shield_regen_bonus * delta))
	shield_changed.emit(shield_energy, shield_max_energy)

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
		
		# Collapse sequence (pausable timers: freeze with the pause menu)
		get_tree().create_timer(0.2, false).timeout.connect(func():
			if shield:
				shield.collapse()
				get_tree().create_timer(1.0, false).timeout.connect(func():
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

func _get_follow_finger_config() -> Dictionary:
	if not DataManager:
		return {}
	var cfg: Dictionary = DataManager.get_game_config()
	var mc_v: Variant = cfg.get("mobile_controls", {})
	if not (mc_v is Dictionary):
		return {}
	var ff_v: Variant = (mc_v as Dictionary).get("follow_finger", {})
	if not (ff_v is Dictionary):
		return {}
	return ff_v as Dictionary

## Hauteur (en pixels) de la zone interdite en haut de l'ecran. Le joueur ne peut pas
## y entrer (ni via stick virtuel, ni via follow finger). Pilote par game.json -> mobile_controls.player_top_safe_zone_ratio.
func _get_player_top_limit_y(viewport_height: float) -> float:
	# Gravity hole / absorb (arène statique) : free movement in ALL directions —
	# only the hard screen margin remains (same 20 px used for the X/bottom
	# clamps).
	if _gravity_hole_active or _absorb_active:
		return 20.0
	var ratio: float = 0.25
	if DataManager:
		var cfg: Dictionary = DataManager.get_game_config()
		var mc_v: Variant = cfg.get("mobile_controls", {})
		if mc_v is Dictionary:
			ratio = float((mc_v as Dictionary).get("player_top_safe_zone_ratio", 0.25))
	ratio = clampf(ratio, 0.0, 0.9)
	return viewport_height * ratio

## Pousse le joueur vers le bas d'un montant donné (utilisé par les obstacles "pusher").
## Si le joueur est poussé hors de l'écran, la mécanique de mort existante s'en charge.
func push_down(y_amount: float) -> void:
	apply_external_displacement(Vector2(0, y_amount))

func _handle_movement(delta: float) -> void:
	# Slice rush wave: the ship is fully locked (X and Y) — short-circuit every
	# movement input path (stick, follow finger, desktop mouse, external forces).
	if _slice_rush_active:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position = _slice_rush_lock_pos
		return

	# Match3 wave: same full lock, the board manager drives the position.
	if _match3_active:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position = _match3_lock_pos
		return

	# Snake wave: same full lock, the SnakeManager drives head position/heading.
	if _snake_active:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position = _snake_lock_pos
		return

	# Gravity hole (refonte Agar.io) : vaisseau verrouillé au CENTRE de l'écran,
	# c'est le MONDE qui bouge — le manager lit l'input lui-même.
	if _gravity_hole_active and _gh_center_locked:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position = _gh_lock_pos
		return

	# Suika up wave: same full lock — the ship borders the reactor.
	if _suika_up_active:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position = _suika_up_lock_pos
		return

	# Ball launcher wave: Y locked on the launch line, X glides toward the
	# manager-driven target (finger follow / frozen while aiming). Regular
	# movement input is fully neutralized.
	if _ball_launcher_active:
		velocity = Vector2.ZERO
		_external_displacement = Vector2.ZERO
		global_position.x = lerpf(
			global_position.x,
			_ball_launcher_target_x,
			clampf(delta * _ball_launcher_snap_speed, 0.0, 1.0)
		)
		global_position.y = _ball_launcher_lock_y
		return

	# Star drift wave: fully inertial finger-follow (Super Starfish feel).
	# The velocity eases toward the target so the ship glides and overshoots
	# slightly; without a target it decelerates smoothly on its own inertia.
	# Free in all four directions (no top safe zone — vertical dodging is the
	# point); black-hole pulls arrive through _external_displacement.
	if _star_drift_active or _survivor_active:
		var sd_start_pos: Vector2 = global_position
		velocity = Vector2.ZERO
		var sd_target: Vector2 = global_position
		var sd_has_target := false
		var sd_touch := false
		if input_provider and input_provider.has_method("is_touching"):
			sd_touch = input_provider.is_touching()
		elif input_provider and input_provider.has_method("is_joystick_active"):
			sd_touch = input_provider.is_joystick_active()
		if sd_touch and input_provider and input_provider.has_method("get_finger_screen_position"):
			var sd_finger: Vector2 = input_provider.get_finger_screen_position()
			if sd_finger != Vector2.INF:
				sd_target = get_canvas_transform().affine_inverse() * (sd_finger + Vector2(0.0, _sd_finger_offset_y))
				sd_has_target = true
		if not sd_has_target:
			var sd_on_mobile: bool = OS.has_feature("mobile")
			if input_provider and input_provider.has_method("is_on_mobile"):
				sd_on_mobile = input_provider.is_on_mobile()
			if not sd_on_mobile:
				sd_target = get_global_mouse_position()
				sd_has_target = true
		var sd_desired: Vector2 = Vector2.ZERO
		if sd_has_target and global_position.distance_to(sd_target) > _sd_deadzone_px:
			sd_desired = ((sd_target - global_position) * _sd_follow_gain).limit_length(_sd_max_speed)
		_sd_velocity = _sd_velocity.lerp(sd_desired, clampf(delta * _sd_inertia_response, 0.0, 1.0))
		global_position += _sd_velocity * delta
		# This early-branch skips the shared path below: consume external
		# forces (black-hole pull) and clamp to the hard screen margins here.
		if _external_displacement != Vector2.ZERO:
			global_position += _external_displacement
			_external_displacement = Vector2.ZERO
		var sd_viewport_size: Vector2 = get_viewport_rect().size
		global_position.x = clampf(global_position.x, 20.0, sd_viewport_size.x - 20.0)
		global_position.y = clampf(global_position.y, 20.0, sd_viewport_size.y - 20.0)
		velocity = (global_position - sd_start_pos) / maxf(delta, 0.0001)
		return

	var start_pos: Vector2 = global_position
	# Clear any residual velocity from obstacle/platform contacts each frame.
	velocity = Vector2.ZERO

	var has_external_force := _external_displacement.length_squared() > 0.000001
	var control_mode: String = "virtual_stick"
	if typeof(ProfileManager) != TYPE_NIL and ProfileManager:
		control_mode = str(ProfileManager.get_setting("control_mode", "virtual_stick"))

	var touch_active := false
	if input_provider and input_provider.has_method("is_touching"):
		touch_active = input_provider.is_touching()
	elif input_provider and input_provider.has_method("is_joystick_active"):
		touch_active = input_provider.is_joystick_active()

	if control_mode == "follow_finger" and touch_active and input_provider and input_provider.has_method("get_finger_screen_position"):
		var finger_screen: Vector2 = input_provider.get_finger_screen_position()
		if finger_screen != Vector2.INF:
			var ff_cfg: Dictionary = _get_follow_finger_config()
			var lerp_speed: float = float(ff_cfg.get("lerp_speed", 18.0))
			var finger_offset_y: float = float(ff_cfg.get("finger_offset_y", -120.0))
			var deadzone_px: float = float(ff_cfg.get("deadzone_px", 4.0))
			# finger_screen_pos est en coordonnees ecran (CanvasLayer du HUD).
			# Comme le HUD est full screen, screen_pos == viewport_pos. On le convertit
			# en world via le canvas_transform du joueur.
			var canvas_xform: Transform2D = get_canvas_transform()
			var target_world: Vector2 = canvas_xform.affine_inverse() * (finger_screen + Vector2(0.0, finger_offset_y))
			# Empeche la cible de remonter dans la zone interdite du haut: le vaisseau ne
			# doit jamais essayer d'y aller (sinon il colle a la limite indefiniment).
			var ff_viewport_size: Vector2 = get_viewport_rect().size
			var ff_top_limit: float = _get_player_top_limit_y(ff_viewport_size.y)
			if target_world.y < ff_top_limit:
				target_world.y = ff_top_limit
			if global_position.distance_to(target_world) > deadzone_px:
				global_position = global_position.lerp(target_world, clampf(delta * lerp_speed, 0.0, 1.0))
	elif touch_active:
		# Mode stick virtuel: 1:1 Direct Drag Movement (Touch Follow)
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
		# Lane runner: X/Y are fully lane-driven (discrete swipes read in
		# _input); the passive mouse-follow must not fight the lane snap.
		var mouse_steering_allowed: bool = not _lane_runner_active
		if not on_mobile and not has_external_force and mouse_steering_allowed:
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
	
	# 2. Strict X Clamp — sauf wrap-around du mode climb (sortir d'un côté fait
	# rentrer de l'autre, Doodle Jump classique).
	if _climb_active and _climb_wrap_x:
		global_position.x = wrapf(global_position.x, -20.0, viewport_size.x + 20.0)
	else:
		global_position.x = clampf(global_position.x, 20, viewport_size.x - 20)
	
	# 3. Y Clamp - Top: zone interdite (par defaut 25% haut de l'ecran).
	# Le joueur ne peut pas y entrer, ni en stick virtuel ni en follow finger.
	var top_limit_y: float = _get_player_top_limit_y(viewport_size.y)
	if global_position.y < top_limit_y:
		global_position.y = top_limit_y

	# Pong wave: Y stays locked on the paddle line (X remains player-controlled).
	if _pong_active:
		global_position.y = _pong_lock_y

	# Vertical climb wave: Y is driven by the climb manager (X remains free).
	if _climb_active:
		global_position.y = _climb_y

	# Lane runner wave: X snaps to the current lane, Y locked on the run line.
	if _lane_runner_active:
		_apply_lane_runner_lock(delta)

	# 4. Check death by "Crushing" (Pushed off screen bottom by Wall)
	# Significant margin to avoid accidental death on edge
	if global_position.y > viewport_size.y + 50:
		take_damage(99999)

	# Keep velocity aligned with the actual frame displacement (used by fluid trail/VFX).
	var dt: float = maxf(delta, 0.0001)
	velocity = (global_position - start_pos) / dt

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

	# --- FIRE PATTERN SYSTEM: Use the active run pattern (from fire pattern drops) ---
	var fire_data := SkillManager.get_fire_pattern_data(_active_fire_pattern_id)
	var pattern_data: Dictionary

	if fire_data.get("is_aura", false):
		# Aura mode: activate aura instead of firing projectiles
		_activate_aura(fire_data)
		_fire_timer = 0.2 # Small cooldown to prevent spamming
		return

	if not fire_data.get("use_ship_default", false) and not fire_data.is_empty():
		# Custom fire pattern from skill tree
		pattern_data = fire_data.duplicate()
	else:
		# Ship default pattern
		pattern_data = DataManager.get_player_missile_pattern(missile_pattern_id).duplicate()
	
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

	# Inject missile visuals/mechanics before reading pattern parameters.
	# This ensures missile_data speed override is reflected in final_speed.
	_inject_missile_properties(pattern_data)
	
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
	var damage_mult := 1.0 + (missile_damage_bonus / 100.0)
	var final_damage: int = int((base_damage + pattern_damage) * damage_multiplier * maxf(0.1, damage_mult))
	var final_speed: float = base_speed * (missile_speed_pct / 100.0)
	
	# Cooldown calculation: (Duration of burst) + (Reload time)
	# Ship fire_rate acts as a multiplier on reload time (higher rate = lower reload)
	var reload_modified: float = reload_time 
	var effective_fire_rate: float = _clamp_fire_rate(fire_rate)
	if effective_fire_rate > 0.0:
		reload_modified = reload_time / effective_fire_rate
	
	var total_sequence_time: float = max(0.0, (burst_count - 1) * burst_interval) + reload_modified
	_fire_timer = total_sequence_time
	
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
		pattern_data["speed"] = missile_speed
		
	# Sound
	pattern_data["sound"] = str(missile_data.get("sound", ""))
	
	# Fluid trail (from missile data)
	var missile_fluid: String = str(missile_data.get("fluid_id", ""))
	if missile_fluid != "":
		pattern_data["fluid_id"] = missile_fluid

func _execute_burst_sequence(pattern_data: Dictionary, count: int, interval: float, speed: float, damage: int) -> void:
	for i in range(count):
		if not is_instance_valid(self): return
		if not _can_shoot: return
		
		# Spawn one "salvo" (can be multiple projectiles if count > 1 in pattern)
		_spawn_salvo(pattern_data, speed, damage)
		
		if count > 1 and i < count - 1:
			# Pausable timer: a burst must not keep firing while the game is paused.
			await get_tree().create_timer(interval, false).timeout
			if not _can_shoot:
				return

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
	var crit_mult := 2.0 + (crit_damage_bonus / 100.0)
	var final_dmg := int(round(float(dmg) * (crit_mult if is_critical else 1.0)))
	
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

## ignore_dodge : les PÉNALITÉS de mini-jeu (balle perdue breakout, but encaissé
## pong) ne sont pas des attaques esquivables — elles blessent toujours.
func take_damage(amount: int, ignore_dodge: bool = false) -> void:
	# Dodge check
	if not ignore_dodge and randf() <= dodge_chance / 100.0:
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

	# Gate-runner: the escort swarm loses ships as the HP resource drops.
	if _gate_runner_active:
		_update_gate_runner_swarm()
		_update_big_hp_label()
	
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
	var effective_amount: int = int(round(float(amount) * _healing_multiplier))
	effective_amount = maxi(0, effective_amount)
	current_hp += effective_amount
	current_hp = mini(current_hp, max_hp)
	print("[Player] Healed: ", effective_amount, " | HP: ", current_hp, "/", max_hp)

func set_healing_multiplier(multiplier: float) -> void:
	_healing_multiplier = clampf(multiplier, 0.0, 1.0)

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
	return _skill_magnet_radius_bonus + loot_radius_bonus

## Returns XP gain multiplier from equipped loot stats.
func get_xp_gain_multiplier() -> float:
	return maxf(1.0, 1.0 + (xp_multiplier_bonus / 100.0))

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
