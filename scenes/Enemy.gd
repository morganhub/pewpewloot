extends CharacterBody2D

## Enemy — Ennemi générique avec move_pattern et missile_pattern.
## Affiche une barre de vie colorée (vert/jaune/rouge).

# =============================================================================
# SIGNALS
# =============================================================================

signal enemy_died(enemy: CharacterBody2D)

# =============================================================================
# PROPERTIES
# =============================================================================

var enemy_id: String = ""
var enemy_name: String = "Enemy"
var max_hp: int = 50
var current_hp: int = 50
var score: int = 10
var loot_chance: float = 0.1
var death_asset: String = ""
var death_anim: String = ""
var loot_quality_multiplier: float = 1.0

# Movement
var move_pattern_id: String = "straight_down"
var move_speed: float = 100.0
var _move_pattern_data: Dictionary = {}
var _move_time: float = 0.0

var _start_position: Vector2 = Vector2.ZERO
var _path_origin: Vector2 = Vector2.ZERO
var _path_length: float = 0.0
var _path_speed_scale: float = 1.0
var _path_direction_sign: float = 1.0
var _path_loop: bool = false
var _path_rotate_to_path: bool = false
var _path_rotation_offset: float = 0.0
var _path_anchor_mode: String = "spawn"
var _path_is_valid: bool = false
var _cached_forward: Vector2 = Vector2.DOWN
var _last_path_world_pos: Vector2 = Vector2.ZERO
var _has_last_path_world_pos: bool = false
var _stat_multiplier: float = 1.0

const DEBUG_MOVE_PATTERN_LOG := true

# Shooting
var missile_pattern_id: String = "single_straight"
var missile_id: String = "missile_default"
var fire_rate: float = 2.0
var _fire_timer: float = 0.0
var _missile_pattern_data: Dictionary = {}

# Shared ability: mine spawner (minefreak)
const MINE_SCENE = preload("res://scenes/objects/Mine.tscn")
const ARCANE_ORB_SCENE = preload("res://scenes/objects/ArcaneOrb.tscn")
const GRAVITY_WELL_SCENE = preload("res://scenes/objects/GravityWell.tscn")
const SUPPRESSOR_SHIELD_SCENE = preload("res://scenes/objects/SuppressorShield.tscn")
var _minefreak_enabled: bool = false
var _minefreak_visuals: Dictionary = {}
var _minefreak_ability_config: Dictionary = {}
var _arcane_enabled: bool = false
var _arcane_visuals: Dictionary = {}
var _arcane_ability_config: Dictionary = {}
var _graviton_enabled: bool = false
var _graviton_visuals: Dictionary = {}
var _graviton_ability_config: Dictionary = {}
var _suppressor_enabled: bool = false
var _suppressor_visuals: Dictionary = {}
var _suppressor_ability_config: Dictionary = {}
var _suppressor_shield: Area2D = null

# Visual
@onready var visual_container: Node2D = $Visual
@onready var shape_visual: Polygon2D = $Visual/Shape
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision: CollisionShape2D = $CollisionShape2D
var path_2d: Path2D = null
var path_follow: PathFollow2D = null

# TODO: Remplacer par Sprite2D
# @onready var sprite: Sprite2D = $Sprite2D

# =============================================================================
# SETUP
# =============================================================================

func setup(enemy_data: Dictionary, stat_multiplier: float = 1.0, modifier_id: String = "") -> void:
	enemy_id = str(enemy_data.get("id", "unknown"))
	enemy_name = str(enemy_data.get("name", "Enemy"))
	max_hp = int(enemy_data.get("hp", 50) * stat_multiplier)  # Scaling HP
	current_hp = max_hp
	score = int(enemy_data.get("score", 10))
	loot_chance = float(enemy_data.get("loot_chance", 0.1))
	_stat_multiplier = stat_multiplier
	
	# Movement pattern
	move_pattern_id = str(enemy_data.get("move_pattern_id", "straight_down"))
	_move_pattern_data = DataManager.get_move_pattern(move_pattern_id)
	var base_pattern_speed: float = float(_move_pattern_data.get("speed", 100.0))
	var enemy_speed_mult: float = float(enemy_data.get("base_speed", 1.0))
	move_speed = base_pattern_speed * maxf(enemy_speed_mult, 0.0)
	
	# Missile pattern
	missile_pattern_id = str(enemy_data.get("missile_pattern_id", "single_straight"))
	missile_id = str(enemy_data.get("missile_id", "missile_default"))
	_missile_pattern_data = DataManager.get_missile_pattern(missile_pattern_id)
	fire_rate = float(enemy_data.get("fire_rate", 2.0))
	
	# Visual setup
	_setup_visual(enemy_data)
	_setup_health_bar()
	
	_start_position = global_position
	_ensure_path_nodes()
	setup_movement(_move_pattern_data)
	_fire_timer = randf_range(0, fire_rate)  # Random offset
	
	# Apply Modifier (Elite)
	if modifier_id == "":
		modifier_id = str(enemy_data.get("modifier_id", ""))
		
	if modifier_id != "":
		EnemyModifiers.apply_modifier(self, modifier_id)

func _setup_visual(enemy_data: Dictionary) -> void:
	var size_data: Variant = enemy_data.get("size", {"width": 30, "height": 30})
	var width: float = 30.0
	var height: float = 30.0
	
	if size_data is Dictionary:
		var size_dict := size_data as Dictionary
		width = float(size_dict.get("width", 30))
		height = float(size_dict.get("height", 30))
	
	# Gestion de l'asset vs shape
	var visual_data: Variant = enemy_data.get("visual", {})
	var asset_path: String = ""
	var asset_anim: String = ""
	var color_hex: String = "#FF4444"
	var shape_type: String = "circle"
	
	if visual_data is Dictionary:
		var v_dict := visual_data as Dictionary
		asset_path = str(v_dict.get("asset", ""))
		asset_anim = str(v_dict.get("asset_anim", ""))
		color_hex = str(v_dict.get("color", "#FF4444"))
		shape_type = str(v_dict.get("shape", "circle"))

	var use_asset: bool = false
	
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
			
			# Scale
			var frame_tex = frames.get_frame_texture("default", 0)
			if frame_tex:
				var f_size = frame_tex.get_size()
				anim_sprite.scale = Vector2(width / f_size.x, height / f_size.y) * 1.2
				
			# Hide static sprite
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if sprite: sprite.visible = false
	
	# Priority 2: Static Sprite (asset)
	if not use_asset and asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			use_asset = true
			shape_visual.visible = false
			
			# Hide anim sprite
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if anim_sprite: anim_sprite.visible = false
			
			# Chercher ou créer le Sprite2D
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				visual_container.add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			# Redimensionner l'image pour qu'elle corresponde à la taille définie
			var tex_size = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(width / tex_size.x, height / tex_size.y) * 1.2 # Scale +20%
	
	if not use_asset:
		# Fallback: Forme géométrique
		var color := Color(color_hex)
		
		# Cacher le sprite si existant
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
		var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
		if anim_sprite: anim_sprite.visible = false
			
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width * 1.2, height * 1.2) # Scale +20%
	
	# Collision (toujours basée sur la taille)
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = (max(width, height) / 2.0) * 1.2 # Scale +20%
	collision.shape = circle_shape

	# Physics Layer Setup
	# Layer 3 (Value 4) = Enemies
	collision_layer = 4
	# Mask: World(1) + PlayerProjectiles(8)
	# Removed Player(2) to prevent physical pushing
	collision_mask = 1 + 8 
	
	# Death VFX data
	var visual_data_v: Dictionary = enemy_data.get("visual", {})
	set("death_asset", str(visual_data_v.get("on_death_asset", "")))
	set("death_anim", str(visual_data_v.get("on_death_asset_anim", "")))

func get_contact_damage() -> int:
	# Retourne les dégâts de collision (similaire à un missile par défaut)
	var dmg: int = 10
	if not _missile_pattern_data.is_empty():
		dmg = int(_missile_pattern_data.get("damage", 10))
	return int(dmg * _stat_multiplier)

func _setup_health_bar() -> void:
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.size = Vector2(40, 4)
	health_bar.position = Vector2(-20, -30)
	_update_health_bar_color()

func apply_stat_multipliers(stats: Dictionary) -> void:
	var hp_mult = float(stats.get("hp_mult", 1.0))
	if hp_mult != 1.0:
		max_hp = int(max_hp * hp_mult)
		current_hp = max_hp
		health_bar.max_value = max_hp
		health_bar.value = current_hp
		
	var spd_mult = float(stats.get("speed_mult", 1.0))
	if spd_mult != 1.0:
		move_speed *= spd_mult
		
	var dmg_mult = float(stats.get("damage_mult", 1.0))
	if dmg_mult != 1.0:
		_stat_multiplier *= dmg_mult

func set_health_bar_frame(path: String) -> void:
	if not ResourceLoader.exists(path): return
	var tex = load(path)
	
	var frame = TextureRect.new()
	frame.name = "EliteFrame"
	frame.texture = tex
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Adjust size/position to surround the bar
	# Assuming frame asset is designed to wrap around
	health_bar.add_child(frame)
	frame.layout_mode = 1 # Anchors
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Add some margin/padding?
	frame.offset_left = -5
	frame.offset_top = -5
	frame.offset_right = 5
	frame.offset_bottom = 5
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

# =============================================================================
# LIFECYCLE
# =============================================================================

func _process(delta: float) -> void:
	_update_movement(delta)
	_update_shooting(delta)
	_update_minefreak_spawn()
	_update_arcane_spawn()
	_update_graviton_spawn()
	
	# Handle wave firing
	if _is_firing_waves:
		_update_wave_firing(delta)
	
	# Vérifier si hors écran (en bas)
	if global_position.y > get_viewport_rect().size.y + 100:
		queue_free()

func _update_wave_firing(delta: float) -> void:
	_wave_timer += delta
	
	var wave_count: int = int(_missile_pattern_data.get("wave_count", 1))
	var wave_interval: float = float(_missile_pattern_data.get("wave_interval", 0.5))
	
	if _wave_timer >= wave_interval:
		_wave_timer = 0.0
		_current_wave += 1
		
		if _current_wave < wave_count:
			_fire_single_wave()
		else:
			_is_firing_waves = false
			_current_wave = 0


# =============================================================================
# MOVEMENT
# =============================================================================

func _update_movement(delta: float) -> void:
	if not _path_is_valid:
		return

	_move_time += delta
	if _path_length <= 0.001:
		return

	var speed := maxf(0.0, move_speed) * _path_speed_scale
	var next_progress := path_follow.progress + (speed * _path_direction_sign * delta)

	if _path_loop:
		path_follow.progress = fposmod(next_progress, _path_length)
	else:
		path_follow.progress = clampf(next_progress, 0.0, _path_length)

	_sync_position_from_path()

func _ensure_path_nodes() -> void:
	if path_2d == null or not is_instance_valid(path_2d):
		path_2d = get_node_or_null("Path2D") as Path2D
		if path_2d == null:
			path_2d = Path2D.new()
			path_2d.name = "Path2D"
			add_child(path_2d)

	if path_follow == null or not is_instance_valid(path_follow):
		path_follow = path_2d.get_node_or_null("PathFollow2D") as PathFollow2D
		if path_follow == null:
			path_follow = PathFollow2D.new()
			path_follow.name = "PathFollow2D"
			path_2d.add_child(path_follow)

func setup_movement(pattern_data: Dictionary) -> void:
	_ensure_path_nodes()
	_move_time = 0.0
	_path_loop = bool(pattern_data.get("loop", false))
	# Keep enemy art orientation fixed (nose down in the source texture).
	_path_rotate_to_path = false
	# Default to 180deg so enemy visuals face "down" in the current art setup.
	# Can still be overridden per pattern via rotation_offset_deg.
	_path_rotation_offset = deg_to_rad(float(pattern_data.get("rotation_offset_deg", 180.0)))
	_path_speed_scale = maxf(0.001, float(pattern_data.get("path_speed_scale", 1.0)))
	_path_direction_sign = 1.0
	_has_last_path_world_pos = false
	_path_anchor_mode = str(pattern_data.get("path_anchor", ""))
	if _path_anchor_mode == "":
		_path_anchor_mode = "viewport" if bool(pattern_data.get("fit_to_viewport", false)) else "spawn"

	var curve := _resolve_curve(pattern_data)
	if curve == null or curve.point_count < 2:
		curve = _generate_fallback_path()
		_path_loop = false
		_path_rotate_to_path = false

	if bool(pattern_data.get("fit_to_viewport", false)):
		curve = _fit_curve_to_viewport(curve, pattern_data)

	path_2d.curve = curve
	_path_is_valid = (path_2d.curve != null and path_2d.curve.point_count >= 2)
	if not _path_is_valid:
		return

	_path_length = maxf(path_2d.curve.get_baked_length(), 0.001)
	var start_sample := _curve_start_point(path_2d.curve)
	if _path_direction_sign < 0.0 and not _path_loop:
		start_sample = path_2d.curve.sample_baked(_path_length, true)
		path_follow.progress = _path_length
	else:
		path_follow.progress = 0.0
	if _path_anchor_mode == "viewport":
		_path_origin = Vector2.ZERO
	else:
		# Keep spawn position as first sampled position even if curve starts elsewhere.
		_path_origin = global_position - start_sample
	path_follow.progress_ratio = 0.0
	rotation = 0.0
	_sync_position_from_path()
	_debug_log_move_pattern(pattern_data)

func _setup_path(pattern_data: Dictionary) -> void:
	# Backward-compatible alias.
	setup_movement(pattern_data)

func _resolve_curve(pattern_data: Dictionary) -> Curve2D:
	var pattern_type := str(pattern_data.get("type", ""))

	if pattern_type == "resource":
		var path := str(pattern_data.get("path", pattern_data.get("resource", "")))
		var loaded_curve := _load_curve_resource(path)
		if loaded_curve != null:
			return loaded_curve
		return null

	if pattern_type == "proc":
		var proc_func := str(pattern_data.get("proc_func", ""))
		return _build_proc_curve(proc_func, pattern_data)

	# Legacy compatibility
	var legacy_resource := str(pattern_data.get("resource", ""))
	if legacy_resource != "":
		var loaded_legacy := _load_curve_resource(legacy_resource)
		if loaded_legacy != null:
			return loaded_legacy

	return _build_procedural_curve(pattern_data)

func _load_curve_resource(resource_path: String) -> Curve2D:
	if not ResourceLoader.exists(resource_path):
		push_warning("[Enemy] Move pattern resource not found: " + resource_path)
		return null

	var resource := load(resource_path)
	if resource is Curve2D:
		return (resource as Curve2D).duplicate()

	push_warning("[Enemy] Resource is not a Curve2D: " + resource_path)
	return null

func _build_proc_curve(proc_func: String, pattern_data: Dictionary) -> Curve2D:
	match proc_func:
		"sine_wave_vertical":
			return _build_proc_sine_wave_vertical(pattern_data)
		"figure_eight_vertical":
			return _build_proc_figure_eight_vertical(pattern_data)
		"impatient_circle":
			return _build_proc_impatient_circle(pattern_data)
		"heart_shape":
			return _build_proc_heart_shape(pattern_data)
		"dna_helix":
			return _build_proc_dna_helix(pattern_data)
		"spirograph_flower":
			return _build_proc_spirograph_flower(pattern_data)
		_:
			push_warning("[Enemy] Unknown proc_func: " + proc_func)
			return null

func _build_procedural_curve(pattern_data: Dictionary) -> Curve2D:
	var pattern_type := str(pattern_data.get("type", "proc_line"))

	match pattern_type:
		"path":
			return null
		"proc_circle", "circular":
			if pattern_data.has("clockwise") and not bool(pattern_data.get("clockwise", true)):
				_path_direction_sign = -1.0
			var radius: float = float(pattern_data.get("radius", 100.0))
			var center_offset := _dict_to_vector(pattern_data.get("center_offset", {"x": 0.0, "y": 0.0}))
			return _generate_circle_path(radius, center_offset)
		"proc_wave", "zigzag", "sine_wave", "random_strafe", "bounce":
			return _generate_wave_path(pattern_data)
		"proc_line", "linear":
			var direction := _read_direction(pattern_data, Vector2.DOWN)
			var distance := _resolve_distance(pattern_data, 1.4)
			return _generate_line_path(distance, direction)
		"static":
			return _generate_line_path(1.0, Vector2.DOWN)
		"proc_bezier", "bezier_curve":
			return _generate_bezier_path(pattern_data)
		"proc_target", "homing", "rush_player", "swoop_dive":
			return _generate_targeted_path(pattern_data)
		"proc_figure_eight", "figure_eight", "loop_center":
			return _generate_figure_eight_path(pattern_data)
		"proc_spiral", "spiral_inward":
			return _generate_spiral_path(pattern_data)
		"proc_enter_hover_leave", "enter_hover_leave":
			var enter_distance := float(pattern_data.get("target_y", 180.0))
			var hover_duration := float(pattern_data.get("hover_duration", 2.0))
			var leave_distance := _resolve_distance(pattern_data, 1.3)
			return _generate_enter_hover_leave_path(enter_distance, hover_duration, leave_distance)
		_:
			return null

func _build_proc_sine_wave_vertical(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var amplitude: float = float(pattern_data.get("amplitude", 120.0))
	var frequency: float = float(pattern_data.get("frequency", 2.0))
	var distance: float = _resolve_distance(pattern_data, 1.8)
	var steps: int = maxi(24, int(pattern_data.get("steps", 96)))

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var x: float = sin(t * TAU * frequency) * amplitude
		var y: float = t * distance
		curve.add_point(Vector2(x, y))

	return curve

func _build_proc_figure_eight_vertical(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var radius: float = float(pattern_data.get("radius", 90.0))
	var vertical_scale: float = float(pattern_data.get("vertical_scale", 1.5))
	var drift_y: float = float(pattern_data.get("drift_y", 0.0 if bool(pattern_data.get("loop", true)) else _resolve_distance(pattern_data, 0.9)))
	var steps: int = maxi(32, int(pattern_data.get("steps", 96)))

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU
		var x: float = sin(angle) * cos(angle) * radius * 1.2
		var y: float = sin(angle) * radius * vertical_scale + drift_y * t
		curve.add_point(Vector2(x, y))

	return curve

func _build_proc_impatient_circle(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var radius: float = float(pattern_data.get("radius", 80.0))
	var turns: float = maxf(float(pattern_data.get("orbit_turns", 1.5)), 0.25)
	var steps: int = maxi(30, int(pattern_data.get("steps", 96)))
	var center: Vector2 = _dict_to_vector(pattern_data.get("center_offset", {"x": 0.0, "y": 140.0}))
	var charge_distance: float = float(pattern_data.get("charge_distance", _resolve_distance(pattern_data, 1.4)))

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU * turns
		var orbit_point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		curve.add_point(orbit_point)

	var last_y: float = center.y + radius
	curve.add_point(Vector2(0.0, last_y + charge_distance), Vector2.ZERO, Vector2.ZERO)
	return curve

func _build_proc_heart_shape(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var scale: float = float(pattern_data.get("scale", 10.0))
	var center: Vector2 = _dict_to_vector(pattern_data.get("center_offset", {"x": 0.0, "y": 200.0}))
	var steps: int = maxi(40, int(pattern_data.get("steps", 140)))

	for i in range(steps + 1):
		var t: float = (float(i) / float(steps)) * TAU
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		var point: Vector2 = center + Vector2(x * scale, -y * scale)
		curve.add_point(point)

	return curve

func _build_proc_dna_helix(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var amplitude_primary: float = float(pattern_data.get("amplitude", 90.0))
	var amplitude_secondary: float = float(pattern_data.get("secondary_amplitude", 35.0))
	var tightness: float = float(pattern_data.get("tightness", 5.0))
	var distance: float = _resolve_distance(pattern_data, 2.0)
	var steps: int = maxi(40, int(pattern_data.get("steps", 120)))

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU * tightness
		var x: float = sin(angle) * amplitude_primary + sin(angle * 2.0 + PI * 0.5) * amplitude_secondary
		var y: float = t * distance
		curve.add_point(Vector2(x, y))

	return curve

func _build_proc_spirograph_flower(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var r_big: float = float(pattern_data.get("spiro_R", 90.0))
	var r_small: float = maxf(float(pattern_data.get("spiro_r", 30.0)), 1.0)
	var d: float = float(pattern_data.get("spiro_d", 55.0))
	var turns: float = maxf(float(pattern_data.get("turns", 6.0)), 1.0)
	var scale: float = float(pattern_data.get("scale", 1.0))
	var center: Vector2 = _dict_to_vector(pattern_data.get("center_offset", {"x": 0.0, "y": 260.0}))
	var steps: int = maxi(60, int(pattern_data.get("steps", 220)))

	for i in range(steps + 1):
		var t: float = (float(i) / float(steps)) * TAU * turns
		var k: float = (r_big - r_small) / r_small
		var x: float = (r_big - r_small) * cos(t) + d * cos(k * t)
		var y: float = (r_big - r_small) * sin(t) - d * sin(k * t)
		curve.add_point(center + Vector2(x, y) * scale)

	return curve

func _sync_position_from_path() -> void:
	if not _path_is_valid or path_2d.curve == null:
		return

	var local_position := _sample_curve(path_follow.progress)
	global_position = _path_origin + local_position

	if _path_rotate_to_path:
		if _has_last_path_world_pos:
			var move_vec: Vector2 = global_position - _last_path_world_pos
			if move_vec.length_squared() > 0.0001:
				_cached_forward = move_vec.normalized()
				rotation = _cached_forward.angle() + _path_rotation_offset
			else:
				_update_path_rotation(local_position)
		else:
			_update_path_rotation(local_position)
	else:
		# Force visual orientation to remain unchanged by path direction.
		rotation = 0.0

	_last_path_world_pos = global_position
	_has_last_path_world_pos = true

func _update_path_rotation(current_local_position: Vector2) -> void:
	if _path_length <= 1.0:
		return

	var lookahead: float = clampf(float(_move_pattern_data.get("rotate_lookahead", 12.0)), 1.0, 64.0)
	var next_progress := path_follow.progress + (lookahead * _path_direction_sign)
	if _path_loop:
		next_progress = fposmod(next_progress, _path_length)
	else:
		next_progress = clampf(next_progress, 0.0, _path_length)

	var next_local_position := _sample_curve(next_progress)
	var tangent := next_local_position - current_local_position
	if tangent.length_squared() <= 0.0001:
		tangent = _cached_forward
	else:
		_cached_forward = tangent.normalized()

	rotation = tangent.angle() + _path_rotation_offset

func _sample_curve(progress_value: float) -> Vector2:
	if path_2d.curve == null:
		return Vector2.ZERO

	var sample_progress := progress_value
	if _path_loop and _path_length > 0.001:
		sample_progress = fposmod(sample_progress, _path_length)
	else:
		sample_progress = clampf(sample_progress, 0.0, _path_length)

	return path_2d.curve.sample_baked(sample_progress, true)

func _curve_start_point(curve: Curve2D) -> Vector2:
	if curve.point_count <= 0:
		return Vector2.ZERO
	return curve.get_point_position(0)

func _fit_curve_to_viewport(curve: Curve2D, pattern_data: Dictionary) -> Curve2D:
	if curve == null or curve.point_count <= 0:
		return curve

	var bounds := _get_curve_bounds(curve)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001:
		return curve

	var viewport_size: Vector2 = get_viewport_rect().size
	var width_ratio: float = maxf(0.001, float(pattern_data.get("fit_width_ratio", 1.0)))
	var height_ratio: float = maxf(0.001, float(pattern_data.get("fit_height_ratio", 1.0)))
	var target_width: float = viewport_size.x * width_ratio
	var target_height: float = viewport_size.y * height_ratio
	var scale_x: float = target_width / bounds.size.x
	var scale_y: float = target_height / bounds.size.y
	var preserve_aspect: bool = bool(pattern_data.get("fit_preserve_aspect", false))
	if preserve_aspect:
		var uniform: float = minf(scale_x, scale_y)
		scale_x = uniform
		scale_y = uniform
		target_width = bounds.size.x * uniform
		target_height = bounds.size.y * uniform

	var align_x: float = clampf(float(pattern_data.get("fit_align_x", 0.0)), 0.0, 1.0)
	var align_y: float = clampf(float(pattern_data.get("fit_align_y", 0.0)), 0.0, 1.0)
	var offset_x: float = (viewport_size.x - target_width) * align_x
	var offset_y: float = (viewport_size.y - target_height) * align_y

	var result := Curve2D.new()
	var point_count: int = curve.point_count
	for i in range(point_count):
		var old_pos: Vector2 = curve.get_point_position(i)
		var old_in: Vector2 = curve.get_point_in(i)
		var old_out: Vector2 = curve.get_point_out(i)

		var scaled_pos := Vector2(
			(old_pos.x - bounds.position.x) * scale_x + offset_x,
			(old_pos.y - bounds.position.y) * scale_y + offset_y
		)
		var scaled_in := Vector2(old_in.x * scale_x, old_in.y * scale_y)
		var scaled_out := Vector2(old_out.x * scale_x, old_out.y * scale_y)
		result.add_point(scaled_pos, scaled_in, scaled_out)

	return result

func _get_curve_bounds(curve: Curve2D) -> Rect2:
	var point_count: int = curve.point_count
	if point_count <= 0:
		return Rect2(Vector2.ZERO, Vector2.ONE)

	var first: Vector2 = curve.get_point_position(0)
	var min_x: float = first.x
	var min_y: float = first.y
	var max_x: float = first.x
	var max_y: float = first.y

	for i in range(point_count):
		var p: Vector2 = curve.get_point_position(i)
		var abs_in: Vector2 = p + curve.get_point_in(i)
		var abs_out: Vector2 = p + curve.get_point_out(i)

		min_x = minf(min_x, p.x)
		min_x = minf(min_x, abs_in.x)
		min_x = minf(min_x, abs_out.x)

		min_y = minf(min_y, p.y)
		min_y = minf(min_y, abs_in.y)
		min_y = minf(min_y, abs_out.y)

		max_x = maxf(max_x, p.x)
		max_x = maxf(max_x, abs_in.x)
		max_x = maxf(max_x, abs_out.x)

		max_y = maxf(max_y, p.y)
		max_y = maxf(max_y, abs_in.y)
		max_y = maxf(max_y, abs_out.y)

	return Rect2(Vector2(min_x, min_y), Vector2(maxf(max_x - min_x, 1.0), maxf(max_y - min_y, 1.0)))

func _debug_log_move_pattern(pattern_data: Dictionary) -> void:
	if not DEBUG_MOVE_PATTERN_LOG:
		return
	var pattern_type: String = str(pattern_data.get("type", "?"))
	var proc_name: String = str(pattern_data.get("proc_func", ""))
	var path_res: String = str(pattern_data.get("path", pattern_data.get("resource", "")))
	print("[EnemyMove] enemy=", enemy_id, " pattern=", move_pattern_id, " type=", pattern_type, " proc=", proc_name, " path=", path_res, " speed=", move_speed, " loop=", _path_loop, " anchor=", _path_anchor_mode, " fit=", bool(pattern_data.get("fit_to_viewport", false)))

func _generate_fallback_path() -> Curve2D:
	return _generate_line_path(maxf(get_viewport_rect().size.y * 1.4, 500.0), Vector2.DOWN)

func _resolve_distance(pattern_data: Dictionary, viewport_multiplier: float) -> float:
	var fallback := maxf(get_viewport_rect().size.y * viewport_multiplier, 350.0)
	return maxf(float(pattern_data.get("distance", fallback)), 1.0)

func _read_direction(pattern_data: Dictionary, fallback: Vector2) -> Vector2:
	var direction := _dict_to_vector(pattern_data.get("direction", {"x": fallback.x, "y": fallback.y}), fallback)
	if direction.length_squared() <= 0.0001:
		return fallback.normalized()
	return direction.normalized()

func _dict_to_vector(data: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if data is Dictionary:
		var dict_data := data as Dictionary
		return Vector2(float(dict_data.get("x", fallback.x)), float(dict_data.get("y", fallback.y)))
	return fallback

func _generate_line_path(distance: float, direction: Vector2 = Vector2.DOWN) -> Curve2D:
	var dir := direction
	if dir.length_squared() <= 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()

	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(dir * maxf(distance, 1.0))
	return curve

func _generate_wave_path(pattern_data: Dictionary) -> Curve2D:
	var curve := Curve2D.new()
	var direction := _read_direction(pattern_data, Vector2.DOWN)
	var perpendicular := Vector2(-direction.y, direction.x)
	var amplitude: float = float(pattern_data.get("amplitude", 80.0))
	var frequency: float = float(pattern_data.get("frequency", 1.5))
	var distance: float = _resolve_distance(pattern_data, 1.5)
	var steps: int = max(12, int(pattern_data.get("steps", 48)))

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var base := direction * (distance * t)
		var wave := perpendicular * sin(t * TAU * frequency) * amplitude
		curve.add_point(base + wave)

	return curve

func _generate_bezier_path(pattern_data: Dictionary) -> Curve2D:
	var steps: int = max(10, int(pattern_data.get("steps", 30)))
	var distance := _resolve_distance(pattern_data, 1.4)

	var control_offset_x: float = float(pattern_data.get("control_offset_x", 150.0))
	if bool(pattern_data.get("randomize_side", true)) and randf() > 0.5:
		control_offset_x *= -1.0
	var control_offset_y: float = float(pattern_data.get("control_offset_y", 120.0))

	var start := Vector2.ZERO
	var control := Vector2(control_offset_x, control_offset_y)
	var end := _dict_to_vector(pattern_data.get("end_offset", {"x": 0.0, "y": distance}), Vector2(0.0, distance))

	return _generate_quadratic_curve(start, control, end, steps)

func _generate_targeted_path(pattern_data: Dictionary) -> Curve2D:
	var steps: int = max(12, int(pattern_data.get("steps", 36)))
	var fallback_distance := _resolve_distance(pattern_data, 1.2)
	var fallback_direction := _read_direction(pattern_data, Vector2.DOWN)

	var target := fallback_direction * fallback_distance
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node and player_node is Node2D:
		target = (player_node as Node2D).global_position - _start_position

	var arc_height: float = float(pattern_data.get("arc_height", 120.0))
	var control := (target * 0.5) + Vector2(0.0, -arc_height)

	return _generate_quadratic_curve(Vector2.ZERO, control, target, steps)

func _generate_figure_eight_path(pattern_data: Dictionary) -> Curve2D:
	var curve := Curve2D.new()
	var radius: float = float(pattern_data.get("radius", 70.0))
	var drift_y: float = float(pattern_data.get("drift_y", _resolve_distance(pattern_data, 0.7)))
	var steps: int = max(20, int(pattern_data.get("steps", 72)))

	for i in range(steps + 1):
		var t := (float(i) / float(steps)) * TAU
		var denominator := 1.0 + sin(t) * sin(t)
		var x := (radius * cos(t)) / denominator
		var y := (radius * sin(t) * cos(t)) / denominator
		y += (drift_y * float(i) / float(steps))
		curve.add_point(Vector2(x, y))

	return curve

func _generate_spiral_path(pattern_data: Dictionary) -> Curve2D:
	var curve := Curve2D.new()
	var steps: int = max(24, int(pattern_data.get("steps", 96)))
	var turns: float = maxf(float(pattern_data.get("turns", 2.5)), 0.2)
	var start_radius: float = maxf(float(pattern_data.get("initial_radius", pattern_data.get("radius", 180.0))), 5.0)
	var end_radius: float = maxf(float(pattern_data.get("end_radius", 10.0)), 0.0)
	var center_offset := _dict_to_vector(pattern_data.get("center_offset", {"x": 0.0, "y": 0.0}))

	if pattern_data.has("clockwise") and not bool(pattern_data.get("clockwise", true)):
		_path_direction_sign = -1.0

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var radius := lerpf(start_radius, end_radius, t)
		var angle := t * TAU * turns
		var point := center_offset + Vector2(cos(angle), sin(angle)) * radius
		curve.add_point(point)

	return curve

func _generate_enter_hover_leave_path(enter_distance: float, hover_duration: float, leave_distance: float) -> Curve2D:
	var curve := Curve2D.new()
	var hover_length := maxf(hover_duration * 30.0, 20.0)

	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(0.0, maxf(enter_distance, 40.0)))
	curve.add_point(Vector2(hover_length * 0.5, maxf(enter_distance, 40.0)))
	curve.add_point(Vector2(0.0, maxf(enter_distance, 40.0)))
	curve.add_point(Vector2(0.0, maxf(enter_distance, 40.0) + maxf(leave_distance, 120.0)))
	return curve

func _generate_quadratic_curve(start: Vector2, control: Vector2, end: Vector2, steps: int) -> Curve2D:
	var curve := Curve2D.new()
	var safe_steps: int = maxi(2, steps)

	for i in range(safe_steps + 1):
		var t := float(i) / float(safe_steps)
		var inv_t := 1.0 - t
		var point := inv_t * inv_t * start + 2.0 * inv_t * t * control + t * t * end
		curve.add_point(point)

	return curve

func _generate_circle_path(radius: float, center_offset: Vector2 = Vector2.ZERO) -> Curve2D:
	var r := maxf(radius, 1.0)
	var kappa := 0.552284749831
	var curve := Curve2D.new()

	var p0 := center_offset + Vector2(r, 0.0)
	var p1 := center_offset + Vector2(0.0, r)
	var p2 := center_offset + Vector2(-r, 0.0)
	var p3 := center_offset + Vector2(0.0, -r)

	curve.add_point(p0, Vector2(0.0, -kappa * r), Vector2(0.0, kappa * r))
	curve.add_point(p1, Vector2(kappa * r, 0.0), Vector2(-kappa * r, 0.0))
	curve.add_point(p2, Vector2(0.0, kappa * r), Vector2(0.0, -kappa * r))
	curve.add_point(p3, Vector2(-kappa * r, 0.0), Vector2(kappa * r, 0.0))
	# Curve2D has no "closed" property in this Godot version; duplicate first point to close loop.
	curve.add_point(p0, Vector2(0.0, -kappa * r), Vector2.ZERO)

	return curve

# =============================================================================
# SHOOTING
# =============================================================================

func _update_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0:
		_fire()
		_fire_timer = fire_rate

var _current_wave: int = 0
var _wave_timer: float = 0.0
var _is_firing_waves: bool = false

func _fire() -> void:
	if _missile_pattern_data.is_empty():
		return
	
	var wave_count: int = int(_missile_pattern_data.get("wave_count", 1))
	var wave_interval: float = float(_missile_pattern_data.get("wave_interval", 0.0))
	
	# If pattern has waves, start wave firing sequence
	if wave_count > 1 and wave_interval > 0.0 and not _is_firing_waves:
		_is_firing_waves = true
		_current_wave = 0
		_wave_timer = 0.0
		set_process(true)
	
	_fire_single_wave()
	
func _fire_single_wave() -> void:
	if _missile_pattern_data.is_empty():
		return

	var projectile_count: int = int(_missile_pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(_missile_pattern_data.get("spread_angle", 0))
	var trajectory := str(_missile_pattern_data.get("trajectory", "straight"))
	var speed: float = float(_missile_pattern_data.get("speed", 200))
	var base_damage: int = int(_missile_pattern_data.get("damage", 10))
	var damage: int = int(base_damage * _stat_multiplier)
	var spawn_strategy: String = str(_missile_pattern_data.get("spawn_strategy", "shooter"))

	# Injecter les data visuelles du missile et override speed
	var missile_data := DataManager.get_missile(missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		_missile_pattern_data["visual_data"] = visual_data
	
	# Inject acceleration from missile
	var acceleration: float = float(missile_data.get("acceleration", 0.0))
	_missile_pattern_data["acceleration"] = acceleration
	
	# Inject explosion data from missile (individual) or use default
	var missile_explosion: Dictionary = missile_data.get("explosion", {})
	if not missile_explosion.is_empty() and missile_explosion.keys().size() > 0:
		_missile_pattern_data["explosion_data"] = missile_explosion
	
	var missile_speed_override: float = float(missile_data.get("speed", 0))
	if missile_speed_override > 0:
		speed = missile_speed_override
		
	# Play sound (once per wave/salvo)
	var sound_path: String = str(missile_data.get("sound", ""))
	if sound_path != "":
		AudioManager.play_sfx(sound_path, 0.1)
	
	# Get spawn positions based on strategy
	var spawn_positions: Array = _get_spawn_positions(spawn_strategy, projectile_count)
	var player_node: Node2D = get_tree().get_first_node_in_group("player")
	
	var is_aimed := (trajectory == "aimed") or bool(_missile_pattern_data.get("aim_target", false))
	
	for i in range(spawn_positions.size()):
		var spawn_pos: Vector2 = spawn_positions[i]
		var direction: Vector2 = Vector2.DOWN
		
		if is_aimed and player_node:
			direction = (player_node.global_position - spawn_pos).normalized()
		else:
			# Default direction based on spawn strategy
			direction = _get_default_direction(spawn_strategy, spawn_pos)
		
		# Apply spread angle if multiple projectiles from same position
		if spawn_strategy == "shooter" and projectile_count > 1:
			var is_full_circle: bool = abs(spread_angle - 360.0) < 10.0  # Allow small tolerance
			
			if is_full_circle:
				# For full circle (radial): Divide evenly around 360 degrees
				var angle_step: float = TAU / float(projectile_count)
				var angle: float = angle_step * float(i)
				direction = Vector2.DOWN.rotated(angle)
			else:
				# For partial spread: Fan out from center
				var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
				var start_angle: float = -deg_to_rad(spread_angle) / 2.0
				var angle: float = start_angle + angle_step * i
				direction = direction.rotated(angle)
		
		ProjectileManager.spawn_enemy_projectile(spawn_pos, direction, speed, damage, _missile_pattern_data)

func _get_spawn_positions(strategy: String, count: int) -> Array:
	var positions: Array = []
	var viewport_size := get_viewport_rect().size
	var player_node: Node2D = get_tree().get_first_node_in_group("player")
	
	match strategy:
		"shooter":
			for i in range(count):
				positions.append(global_position)
		
		"screen_bottom":
			var margin: float = 50.0
			var step_x: float = (viewport_size.x - margin * 2) / max(1, count - 1) if count > 1 else 0.0
			for i in range(count):
				var x: float = margin + step_x * i if count > 1 else viewport_size.x / 2.0
				positions.append(Vector2(x, viewport_size.y + 20))
		
		"screen_top":
			var margin: float = 50.0
			var step_x: float = (viewport_size.x - margin * 2) / max(1, count - 1) if count > 1 else 0.0
			for i in range(count):
				var x: float = margin + step_x * i if count > 1 else viewport_size.x / 2.0
				positions.append(Vector2(x, -20))
		
		"target_circle":
			var radius: float = float(_missile_pattern_data.get("spawn_radius", 150))
			var target_pos: Vector2 = player_node.global_position if player_node else Vector2(viewport_size.x / 2, viewport_size.y / 2)
			for i in range(count):
				var angle: float = (float(i) / float(count)) * TAU
				var offset := Vector2(cos(angle), sin(angle)) * radius
				positions.append(target_pos + offset)
		
		"corners":
			positions.append(Vector2(30, 30))
			positions.append(Vector2(viewport_size.x - 30, 30))
			positions.append(Vector2(30, viewport_size.y - 30))
			positions.append(Vector2(viewport_size.x - 30, viewport_size.y - 30))
		
		"flanking":
			var half: int = int(floor(float(count) * 0.5))
			var step_y: float = viewport_size.y / max(1, half)
			for i in range(half):
				positions.append(Vector2(-20, step_y * i + step_y / 2))  # Left
				positions.append(Vector2(viewport_size.x + 20, step_y * i + step_y / 2))  # Right
		
		"random_edge":
			for i in range(count):
				var edge: int = randi() % 4
				var pos: Vector2
				match edge:
					0:  # Top
						pos = Vector2(randf_range(0, viewport_size.x), -20)
					1:  # Bottom
						pos = Vector2(randf_range(0, viewport_size.x), viewport_size.y + 20)
					2:  # Left
						pos = Vector2(-20, randf_range(0, viewport_size.y))
					3:  # Right
						pos = Vector2(viewport_size.x + 20, randf_range(0, viewport_size.y))
				positions.append(pos)
		
		_:
			for i in range(count):
				positions.append(global_position)
	
	return positions

func _get_default_direction(strategy: String, spawn_pos: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var center := Vector2(viewport_size.x / 2, viewport_size.y / 2)
	
	match strategy:
		"screen_bottom":
			return Vector2.UP
		"screen_top":
			return Vector2.DOWN
		"corners", "flanking", "random_edge":
			return (center - spawn_pos).normalized()
		"target_circle":
			var player: Node2D = get_tree().get_first_node_in_group("player")
			if player:
				return (player.global_position - spawn_pos).normalized()
			return (center - spawn_pos).normalized()
		_:
			return Vector2.DOWN

func setup_minefreak(mod_data: Dictionary) -> void:
	_minefreak_enabled = true
	_minefreak_visuals = mod_data.get("visuals", {})
	_minefreak_ability_config = mod_data.get("ability_config", {})

func setup_arcane_enchanted(mod_data: Dictionary) -> void:
	_arcane_enabled = true
	_arcane_visuals = mod_data.get("visuals", {})
	_arcane_ability_config = mod_data.get("ability_config", {})

func setup_graviton(mod_data: Dictionary) -> void:
	_graviton_enabled = true
	_graviton_visuals = mod_data.get("visuals", {})
	_graviton_ability_config = mod_data.get("ability_config", {})

func setup_suppressor(mod_data: Dictionary) -> void:
	_suppressor_enabled = true
	_suppressor_visuals = mod_data.get("visuals", {})
	_suppressor_ability_config = mod_data.get("ability_config", {})
	_spawn_suppressor_shield()

func _spawn_suppressor_shield() -> void:
	if not _suppressor_enabled:
		return
	if _suppressor_shield and is_instance_valid(_suppressor_shield):
		return
	if SUPPRESSOR_SHIELD_SCENE == null:
		return
	
	var shield_instance = SUPPRESSOR_SHIELD_SCENE.instantiate()
	if not (shield_instance is Area2D):
		return
	
	_suppressor_shield = shield_instance as Area2D
	add_child(_suppressor_shield)
	_suppressor_shield.position = Vector2.ZERO
	_suppressor_shield.z_index = 1
	
	var shield_config := {
		"shield_scene_path": str(_suppressor_visuals.get("shield_scene_path", "res://addons/nojoule-energy-shield/shield_sphere.tscn")),
		"shield_diameter": float(_suppressor_visuals.get("shield_diameter", 140.0)),
		"color_tint": str(_suppressor_visuals.get("color_tint", "#0088FF")),
		"shield_hp": int(_suppressor_ability_config.get("shield_hp", 500)),
		"deflect_sfx": str(_suppressor_ability_config.get("deflect_sfx", ""))
	}
	if _suppressor_shield.has_method("setup"):
		_suppressor_shield.call("setup", shield_config)
	
	var on_broken := Callable(self, "_on_suppressor_shield_broken")
	if _suppressor_shield.has_signal("shield_broken") and not _suppressor_shield.is_connected("shield_broken", on_broken):
		_suppressor_shield.connect("shield_broken", on_broken)
	
	# Tant que le bouclier est actif, l'ennemi ne doit pas recevoir les tirs joueur.
	_set_projectile_hit_enabled(false)

func _on_suppressor_shield_broken() -> void:
	_set_projectile_hit_enabled(true)
	_suppressor_shield = null

func _set_projectile_hit_enabled(enabled: bool) -> void:
	if enabled:
		collision_mask |= 8
	else:
		collision_mask &= ~8

func _update_minefreak_spawn() -> void:
	if not _minefreak_enabled:
		return
	
	var spawn_config := {"ability_config": _minefreak_ability_config}
	if not EnemyAbilityManager.can_spawn("mine_spawner", spawn_config, global_position):
		return
	
	if MINE_SCENE == null:
		return
	
	var mine = MINE_SCENE.instantiate()
	if mine == null:
		return
	
	# Configure mine from modifier visuals + ability config
	mine.set("damage", int(_minefreak_ability_config.get("damage", 25)))
	mine.set("mine_width", int(_minefreak_visuals.get("width", 40)))
	mine.set("mine_height", int(_minefreak_visuals.get("height", 40)))
	mine.set("visual_asset", str(_minefreak_visuals.get("ability_asset", "")))
	mine.set("contact_sfx_path", str(_minefreak_visuals.get("contact_sfx", "")))
	mine.set("explosion_asset", str(_minefreak_visuals.get("explosion_asset", "")))
	
	# Optional tuning hook if later added in data.
	if _minefreak_ability_config.has("mine_hp"):
		var hp := int(_minefreak_ability_config.get("mine_hp", 20))
		mine.set("max_hp", hp)
		mine.set("current_hp", hp)
	if _minefreak_ability_config.has("scroll_speed"):
		mine.set("scroll_speed", float(_minefreak_ability_config.get("scroll_speed", 100.0)))
	if _minefreak_ability_config.has("lateral_speed"):
		mine.set("lateral_speed", float(_minefreak_ability_config.get("lateral_speed", 40.0)))
	if _minefreak_ability_config.has("spin_speed_deg"):
		mine.set("spin_speed_deg", float(_minefreak_ability_config.get("spin_speed_deg", 60.0)))
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(mine)
	if mine is Node2D:
		(mine as Node2D).global_position = global_position
		EnemyAbilityManager.register_spawn("mine_spawner", mine as Node2D, spawn_config)

func _update_arcane_spawn() -> void:
	if not _arcane_enabled:
		return
	
	var spawn_config := {"ability_config": _arcane_ability_config}
	if not EnemyAbilityManager.can_spawn("arcane_spawner", spawn_config, global_position):
		return
	
	if ARCANE_ORB_SCENE == null:
		return
	
	var orb = ARCANE_ORB_SCENE.instantiate()
	if orb == null:
		return
	
	# Configure Arcane Orb from modifier visuals + ability config
	orb.set("damage", int(_arcane_ability_config.get("damage", 15)))
	orb.set("rotation_speed", float(_arcane_ability_config.get("rotation_speed", 45.0)))
	orb.set("laser_length_pct", float(_arcane_ability_config.get("laser_length_pct", 0.30)))
	orb.set("duration", float(_arcane_ability_config.get("duration", 6.0)))
	orb.set("orb_width", int(_arcane_visuals.get("width", 32)))
	orb.set("orb_height", int(_arcane_visuals.get("height", 32)))
	orb.set("ability_asset", str(_arcane_visuals.get("ability_asset", "")))
	orb.set("laser_asset", str(_arcane_visuals.get("laser_asset", "")))
	orb.set("contact_sfx_path", str(_arcane_visuals.get("contact_sfx", "")))
	
	if _arcane_ability_config.has("scroll_speed"):
		orb.set("scroll_speed", float(_arcane_ability_config.get("scroll_speed", 90.0)))
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(orb)
	if orb is Node2D:
		(orb as Node2D).global_position = global_position
		EnemyAbilityManager.register_spawn("arcane_spawner", orb as Node2D, spawn_config)

func _update_graviton_spawn() -> void:
	if not _graviton_enabled:
		return
	
	var spawn_config := {
		"ability_config": _graviton_ability_config,
		"visuals": _graviton_visuals
	}
	if not EnemyAbilityManager.can_spawn("gravity_spawner", spawn_config, global_position):
		return
	
	if GRAVITY_WELL_SCENE == null:
		return
	
	var well = GRAVITY_WELL_SCENE.instantiate()
	if well == null:
		return
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(well)
	if well is Node2D:
		(well as Node2D).global_position = global_position
		if well.has_method("setup"):
			well.setup(spawn_config)
		EnemyAbilityManager.register_spawn("gravity_spawner", well as Node2D, spawn_config)

# =============================================================================
# DAMAGE & DEATH
# =============================================================================

func take_damage(amount: int, is_critical: bool = false) -> void:
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	health_bar.value = current_hp
	_update_health_bar_color()
	
	# Play SFX (Enemy Hit)
	# Check if we should play every hit? Maybe limit frequency or only critical?
	# For now playing on every hit.
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("collisions", {})
	var sfx_path = str(sfx_config.get("enemy", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.2)
	
	# Feedback visuel
	var flash_color := Color.WHITE
	if is_critical:
		flash_color = Color.YELLOW
		VFXManager.spawn_floating_text(global_position, "CRIT!", Color.YELLOW, get_parent())
	
	VFXManager.flash_sprite(visual_container, flash_color, 0.1)
	
	if current_hp <= 0:
		die()

func die() -> void:
	enemy_died.emit(self)
	
	# VFX explosion
	var on_death_asset: String = ""
	var on_death_anim: String = ""
	if "death_asset" in self: on_death_asset = get("death_asset")
	if "death_anim" in self: on_death_anim = get("death_anim")
	
	VFXManager.spawn_explosion(global_position, 25, shape_visual.color, get_parent(), on_death_asset, on_death_anim)
	VFXManager.screen_shake(3, 0.2)
	
	# --- LOOT DROP LOGIC ---
	# Config: Chance of Equipment vs PowerUp
	# Let's say: 10% base chance for ANY loot.
	# If loot drops: 20% Equipment, 80% PowerUp? Or separate rolls?
	# Implementation: Separate rolls.
	
	# 1. Equipment (LootGenerator)
	# Chance based on enemy strength/type?
	# Using loot_chance * loot_quality_multiplier for Equipment
	if randf() <= (loot_chance * 0.5): # Halve chance for equipment to balance
		var level: int = 1
		if App: level = App.current_level_index + 1
		
		var item: LootItem = LootGenerator.generate_loot(level, "", "", loot_quality_multiplier)
		if item:
			var drop_scene = load("res://scenes/LootDrop.tscn")
			if drop_scene:
				var drop = drop_scene.instantiate()
				get_parent().call_deferred("add_child", drop)
				drop.call_deferred("setup", item.to_dict(), global_position)
	
	# 2. PowerUps (Shield / Rapid Fire)
	# Using loot_chance for PowerUps
	if randf() <= loot_chance:
		_spawn_powerup()
	
	queue_free()

func _spawn_powerup() -> void:
	var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
	if gameplay_config.is_empty():
		return
	
	var shield_cfg: Dictionary = gameplay_config.get("shield", {})
	var rapid_fire_cfg: Dictionary = gameplay_config.get("rapid_fire", {})

	# Roll Type
	# 50/50 split between Shield and Rapid Fire
	var type_roll = randf()
	var item_data: Dictionary = {}
	
	if type_roll < 0.5:
		item_data = {
			"type": "powerup",
			"effect": "shield",
			"name": "Shield Module",
			"visual_asset": str(shield_cfg.get("asset", "")),
			"width": float(shield_cfg.get("width", 56.0)),
			"height": float(shield_cfg.get("height", 56.0))
		}
	else:
		item_data = {
			"type": "powerup",
			"effect": "fire_rate",
			"name": "Rapid Fire",
			"visual_asset": str(rapid_fire_cfg.get("asset", "")),
			"width": float(rapid_fire_cfg.get("width", 56.0)),
			"height": float(rapid_fire_cfg.get("height", 56.0))
		}
	
	# Spawn Drop
	var drop_scene = load("res://scenes/LootDrop.tscn")
	if drop_scene:
		var drop = drop_scene.instantiate()
		get_parent().call_deferred("add_child", drop)
		drop.call_deferred("setup", item_data, global_position)

func _update_health_bar_color() -> void:
	var hp_percent := float(current_hp) / float(max_hp)
	
	if hp_percent > 0.75:
		health_bar.modulate = Color.GREEN
	elif hp_percent > 0.33:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.RED

# =============================================================================
# UTILITY
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
			return _create_circle(max(width, height) / 2.0)

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
