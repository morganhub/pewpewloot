extends Node2D

signal finished

const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {}
static var _first_frame_texture_cache: Dictionary = {}

@onready var hazard_visual: Node2D = $HazardVisual
@onready var hazard_zone: Area2D = $HazardZone
@onready var hazard_shape: CollisionShape2D = $HazardZone/CollisionShape2D
@onready var path2d: Path2D = $Path2D
@onready var path_visual: Line2D = $PathVisual
@onready var safe_zone: Area2D = $SafeZone
@onready var safe_polygon: CollisionPolygon2D = $SafeZone/CollisionPolygon2D
@onready var damage_tick_timer: Timer = $DamageTickTimer

var _config: Dictionary = {}
var _path_pattern_data: Dictionary = {}
var _duration: float = 10.0
var _tick_damage: int = 10
var _tick_interval_sec: float = 0.5
var _speed: float = 180.0
var _path_width: float = 120.0
var _head_length_px: float = 260.0
var _tail_length_px: float = 180.0
var _start_delay_sec: float = 1.5
var _hazard_asset_path: String = ""
var _hazard_start_asset_path: String = ""
var _path_asset_path: String = ""
var _path_asset_scale: float = 3.0
var _elapsed: float = 0.0
var _path_progress: float = 0.0
var _path_total_length: float = 0.0
var _is_running: bool = false
var _start_visual_node: Node = null
var _active_visual_node: Node = null
var _in_start_phase: bool = true
var _active_path_points: PackedVector2Array = PackedVector2Array()
var _warmup_anchor: Vector2 = Vector2.ZERO
var _path_tiles_root: Node2D = null
var _path_tile_texture: Texture2D = null
var _path_tile_scale: Vector2 = Vector2.ONE
var _path_tile_pool: Array[Sprite2D] = []
var _path_speed_ramp_sec: float = 0.35
var _hazard_scroll_speed_px_sec: float = 45.0
var _hazard_overlay_opacity: float = 0.35
var _warning_frame_width: float = 3.0
var _warning_frame_color: Color = Color(1.0, 0.2, 0.2, 1.0)
var _warning_frame_pulse: bool = true
var _warning_frame_pulse_size: float = 4.0
var _damage_frame_pulse_size: float = 60.0
var _warning_frame_overlay: ColorRect = null
var _hazard_fade_duration_sec: float = 0.25
var _ending: bool = false
var _path_margin_top: float = 20.0
var _path_margin_left: float = 20.0
var _path_margin_right: float = 20.0
var _path_margin_bottom: float = 20.0
var _hazard_scroll_layers: Array[Sprite2D] = []
var _hazard_scroll_layer_height: float = 0.0
var _hazard_scroll_offset: float = 0.0
var _damage_pulse_tween: Tween = null

var _player: Node2D = null
var _player_in_hazard: bool = false
var _player_in_safe_zone: bool = false
var _path_anim_node: AnimatedSprite2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_path_tiles_root = Node2D.new()
	_path_tiles_root.name = "PathTiles"
	add_child(_path_tiles_root)
	_setup_zone_signals()
	if damage_tick_timer and not damage_tick_timer.timeout.is_connected(_on_damage_tick_timer_timeout):
		damage_tick_timer.timeout.connect(_on_damage_tick_timer_timeout)

func setup(config: Dictionary) -> void:
	_config = config.duplicate(true)
	_resolve_config_values()
	_configure_hazard_zone_shape()
	_build_path_curve()
	_setup_hazard_visual()
	_setup_path_visual()
	_reset_runtime_state()
	start()

func start() -> void:
	_is_running = true
	_ending = false
	hazard_visual.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(hazard_visual, "modulate:a", 1.0, _hazard_fade_duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if damage_tick_timer:
		damage_tick_timer.wait_time = _tick_interval_sec
		damage_tick_timer.start()
	set_process(true)

func stop() -> void:
	_is_running = false
	if damage_tick_timer:
		damage_tick_timer.stop()
	set_process(false)

func _process(delta: float) -> void:
	if not _is_running or _ending:
		return

	_elapsed += delta
	_update_hazard_background_scroll(delta)
	if _elapsed < _start_delay_sec:
		# Warmup phase: keep the path head frozen at the exact start anchor.
		_path_progress = 0.0
		_set_hazard_phase_visuals(true)
		_render_warmup_safe_zone()
		_refresh_player_zone_flags()
		return

	_set_hazard_phase_visuals(false)
	var active_elapsed: float = _elapsed - _start_delay_sec
	if active_elapsed >= _duration:
		_end_trial()
		return

	var speed_factor: float = 1.0
	if _path_speed_ramp_sec > 0.0:
		speed_factor = clampf(active_elapsed / _path_speed_ramp_sec, 0.0, 1.0)
	_path_progress += maxf(0.0, _speed) * speed_factor * delta
	_path_progress = minf(_path_progress, _path_total_length + _tail_length_px)
	_render_dynamic_safe_zone()
	_refresh_player_zone_flags()

func _resolve_config_values() -> void:
	var defaults: Dictionary = DataManager.get_path_trial_defaults() if DataManager else {}

	_path_pattern_data.clear()
	var pattern_variant: Variant = _config.get("pattern_data", {})
	if pattern_variant is Dictionary:
		_path_pattern_data = (pattern_variant as Dictionary).duplicate(true)
	var pattern_id: String = str(_config.get("pattern_id", "")).strip_edges()
	if _path_pattern_data.is_empty() and pattern_id != "":
		_path_pattern_data = DataManager.get_move_pattern(pattern_id).duplicate(true)
	if _path_pattern_data.is_empty():
		_path_pattern_data = {"id": "path_trial_fallback"}

	_duration = maxf(0.1, float(_config.get("duration", _config.get("trial_duration", 12.0))))
	_speed = maxf(0.0, float(_config.get("speed", _path_pattern_data.get("speed", 180.0))))
	_tick_damage = maxi(1, int(round(float(_config.get("tick_damage", defaults.get("default_tick_damage", 10))))))
	_tick_interval_sec = maxf(0.05, float(_config.get("tick_interval_sec", defaults.get("default_tick_interval_sec", 0.5))))
	_path_width = maxf(16.0, float(_config.get("path_width", defaults.get("path_width", 120.0))))
	_start_delay_sec = maxf(
		0.0,
		float(_config.get("start_delay_sec", _config.get("warmup_sec", defaults.get("start_delay_sec", defaults.get("warmup_sec", 1.5)))))
	)
	_head_length_px = maxf(_path_width, float(_config.get("head_length_px", defaults.get("head_length_px", 260.0))))
	_tail_length_px = maxf(_path_width * 0.5, float(_config.get("tail_length_px", defaults.get("tail_length_px", 180.0))))

	var force_default_hazard_asset: bool = bool(defaults.get("force_default_hazard_asset", true))
	if force_default_hazard_asset:
		_hazard_asset_path = str(defaults.get("default_hazard_asset", _config.get("hazard_asset_override", ""))).strip_edges()
	else:
		_hazard_asset_path = str(_config.get("hazard_asset_override", defaults.get("default_hazard_asset", ""))).strip_edges()
	_hazard_start_asset_path = str(_config.get("hazard_start_asset_override", defaults.get("default_hazard_start_asset", _hazard_asset_path))).strip_edges()
	var force_default_path_asset: bool = bool(defaults.get("force_default_path_asset", true))
	if force_default_path_asset:
		_path_asset_path = str(defaults.get("default_path_asset", _config.get("path_asset_override", ""))).strip_edges()
	else:
		_path_asset_path = str(_config.get("path_asset_override", defaults.get("default_path_asset", ""))).strip_edges()
	_path_asset_scale = maxf(0.1, float(_config.get("path_asset_scale", defaults.get("default_path_asset_scale", 1.0))))
	_path_speed_ramp_sec = maxf(0.0, float(_config.get("path_speed_ramp_sec", defaults.get("path_speed_ramp_sec", 0.35))))
	_hazard_scroll_speed_px_sec = maxf(
		0.0,
		float(_config.get("hazard_scroll_speed_px_sec", defaults.get("hazard_scroll_speed_px_sec", _resolve_default_background_scroll_speed())))
	)
	_hazard_overlay_opacity = clampf(float(_config.get("hazard_overlay_opacity", defaults.get("hazard_overlay_opacity", 0.35))), 0.0, 1.0)
	_warning_frame_width = maxf(0.0, float(_config.get("warning_frame_width", defaults.get("warning_frame_width", 3.0))))
	_warning_frame_color = Color(str(_config.get("warning_frame_color", defaults.get("warning_frame_color", "#FF3030"))))
	var pulse_raw: Variant = _config.get("warning_frame_pulse", defaults.get("warning_frame_pulse", true))
	if pulse_raw is String:
		_warning_frame_pulse = str(pulse_raw).to_lower() == "on"
	else:
		_warning_frame_pulse = bool(pulse_raw)
	_warning_frame_pulse_size = maxf(0.0, float(_config.get("warning_frame_pulse_size", defaults.get("warning_frame_pulse_size", 4.0))))
	_damage_frame_pulse_size = maxf(0.0, float(_config.get("damage_frame_pulse_size", defaults.get("damage_frame_pulse_size", 60.0))))
	_hazard_fade_duration_sec = maxf(0.0, float(_config.get("hazard_fade_duration_sec", defaults.get("hazard_fade_duration_sec", 0.25))))
	_path_margin_top = maxf(0.0, float(_config.get("path_margin_top", defaults.get("path_margin_top", 20.0))))
	_path_margin_left = maxf(0.0, float(_config.get("path_margin_left", defaults.get("path_margin_left", 20.0))))
	_path_margin_right = maxf(0.0, float(_config.get("path_margin_right", defaults.get("path_margin_right", 20.0))))
	_path_margin_bottom = maxf(0.0, float(_config.get("path_margin_bottom", defaults.get("path_margin_bottom", 20.0))))

func _resolve_default_background_scroll_speed() -> float:
	if not DataManager:
		return 45.0
	var cfg: Dictionary = DataManager.get_game_config()
	var gameplay_v: Variant = cfg.get("gameplay", {})
	if gameplay_v is Dictionary:
		var bg_v: Variant = (gameplay_v as Dictionary).get("background_scroll", {})
		if bg_v is Dictionary:
			return maxf(0.0, float((bg_v as Dictionary).get("near_speed", 45.0)))
	return 45.0

func _configure_hazard_zone_shape() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var rect_shape: RectangleShape2D = hazard_shape.shape as RectangleShape2D
	if rect_shape == null:
		rect_shape = RectangleShape2D.new()
		hazard_shape.shape = rect_shape
	rect_shape.size = viewport_size
	hazard_shape.position = viewport_size * 0.5

	hazard_zone.collision_layer = 0
	hazard_zone.collision_mask = 2
	hazard_zone.monitoring = true
	hazard_zone.monitorable = true

	safe_zone.collision_layer = 0
	safe_zone.collision_mask = 2
	safe_zone.monitoring = true
	safe_zone.monitorable = true

func _build_path_curve() -> void:
	var required_length: float = maxf(
		_speed * _duration + _head_length_px + _tail_length_px + 120.0,
		get_viewport_rect().size.y * 1.4
	)
	var curve: Curve2D = _build_runtime_random_curve(required_length)
	if curve == null or curve.point_count < 2:
		curve = _generate_fallback_curve()
	path2d.curve = curve
	_path_total_length = maxf(path2d.curve.get_baked_length(), 1.0)

func _build_runtime_random_curve(required_length: float) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_w: float = _path_width * 0.5
	var min_x: float = _path_margin_left + half_w
	var max_x: float = maxf(min_x + 1.0, viewport_size.x - _path_margin_right - half_w)
	var min_y: float = maxf(_path_margin_top + half_w, (viewport_size.y / 3.0) + _path_margin_top + half_w)
	var max_y: float = maxf(min_y + 1.0, viewport_size.y - _path_margin_bottom - half_w)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var cell: float = maxf(8.0, _path_width)
	var current: Vector2 = Vector2(
		_snap_to_grid(rng.randf_range(min_x, max_x), min_x, cell),
		_snap_to_grid(rng.randf_range(min_y, max_y), min_y, cell)
	)
	curve.add_point(current)
	var heading_idx: int = rng.randi_range(0, 3) # 0:R 1:L 2:D 3:U

	var travelled: float = 0.0
	var guard: int = 0
	while travelled < required_length and guard < 2500:
		guard += 1
		var dir: Vector2 = _dir_from_idx(heading_idx)
		var max_cells_to_border: int = _max_cells_to_border(current, dir, min_x, max_x, min_y, max_y, cell)
		if max_cells_to_border <= 0:
			heading_idx = _pick_orthogonal_heading(heading_idx, current, min_x, max_x, min_y, max_y, cell, rng)
			continue
		var min_cells: int = 1
		var max_cells: int = mini(5, max_cells_to_border)
		var cells: int = rng.randi_range(min_cells, max_cells)
		var segment_len: float = float(cells) * cell
		var candidate: Vector2 = current + (dir * segment_len)
		candidate.x = clampf(candidate.x, min_x, max_x)
		candidate.y = clampf(candidate.y, min_y, max_y)
		var actual_len: float = current.distance_to(candidate)
		if actual_len < cell * 0.5:
			heading_idx = _pick_orthogonal_heading(heading_idx, current, min_x, max_x, min_y, max_y, cell, rng)
			continue
		curve.add_point(candidate)
		travelled += actual_len
		current = candidate
		heading_idx = _pick_orthogonal_heading(heading_idx, current, min_x, max_x, min_y, max_y, cell, rng)

	if curve.point_count < 2:
		var center_x: float = viewport_size.x * 0.5
		curve.add_point(Vector2(center_x, min_y))
		curve.add_point(Vector2(center_x, max_y))

	_smooth_curve_handles(curve)
	return curve

func _snap_to_grid(value: float, origin: float, step: float) -> float:
	return origin + round((value - origin) / step) * step

func _dir_from_idx(idx: int) -> Vector2:
	match idx:
		0: return Vector2.RIGHT
		1: return Vector2.LEFT
		2: return Vector2.DOWN
		3: return Vector2.UP
		_: return Vector2.RIGHT

func _max_cells_to_border(pos: Vector2, dir: Vector2, min_x: float, max_x: float, min_y: float, max_y: float, cell: float) -> int:
	if dir.x > 0.0:
		return maxi(0, int(floor((max_x - pos.x) / cell)))
	if dir.x < 0.0:
		return maxi(0, int(floor((pos.x - min_x) / cell)))
	if dir.y > 0.0:
		return maxi(0, int(floor((max_y - pos.y) / cell)))
	return maxi(0, int(floor((pos.y - min_y) / cell)))

func _pick_orthogonal_heading(current_idx: int, pos: Vector2, min_x: float, max_x: float, min_y: float, max_y: float, cell: float, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = [current_idx]
	if current_idx <= 1:
		candidates.append(2)
		candidates.append(3)
	else:
		candidates.append(0)
		candidates.append(1)
	var valid: Array[int] = []
	for idx in candidates:
		var dir: Vector2 = _dir_from_idx(idx)
		if _max_cells_to_border(pos, dir, min_x, max_x, min_y, max_y, cell) > 0:
			valid.append(idx)
	if valid.is_empty():
		return current_idx
	# Keep straight most of the time; turn only by 90 degrees.
	if valid.has(current_idx) and rng.randf() < 0.55:
		return current_idx
	return valid[rng.randi_range(0, valid.size() - 1)]

func _smooth_curve_handles(curve: Curve2D) -> void:
	if curve == null or curve.point_count < 3:
		return
	# Orthogonal path: keep hard 90° corners without bezier deformation.
	for i in range(curve.point_count):
		curve.set_point_in(i, Vector2.ZERO)
		curve.set_point_out(i, Vector2.ZERO)
	return

func _resolve_curve(pattern_data: Dictionary) -> Curve2D:
	var p_type: String = str(pattern_data.get("type", "resource"))
	match p_type:
		"resource":
			var path: String = str(pattern_data.get("path", pattern_data.get("resource", ""))).strip_edges()
			if path != "" and ResourceLoader.exists(path):
				var loaded: Resource = _load_cached_resource(path)
				if loaded is Curve2D:
					return _fit_curve_to_viewport((loaded as Curve2D).duplicate(true))
		"proc":
			var proc_func: String = str(pattern_data.get("proc_func", "")).strip_edges()
			return _fit_curve_to_viewport(_build_proc_curve(proc_func, pattern_data))

	return _fit_curve_to_viewport(_build_proc_curve(str(pattern_data.get("proc_func", "")), pattern_data))

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
			return _generate_fallback_curve()

func _fit_curve_to_viewport(curve: Curve2D) -> Curve2D:
	if curve == null or curve.point_count < 2:
		return curve

	var bounds: Rect2 = _get_curve_bounds(curve)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001:
		return curve

	var viewport_size: Vector2 = get_viewport_rect().size
	var margin_x: float = viewport_size.x * 0.08
	var margin_y_top: float = viewport_size.y * 0.06
	var margin_y_bottom: float = viewport_size.y * 0.06

	var target_w: float = maxf(1.0, viewport_size.x - (margin_x * 2.0))
	var target_h: float = maxf(1.0, viewport_size.y - (margin_y_top + margin_y_bottom))
	var sx: float = target_w / maxf(bounds.size.x, 0.001)
	var sy: float = target_h / maxf(bounds.size.y, 0.001)
	var scale_factor: float = minf(sx, sy)
	if not is_finite(scale_factor) or scale_factor <= 0.0:
		scale_factor = 1.0

	var offset: Vector2 = Vector2(margin_x, margin_y_top) - (bounds.position * scale_factor)
	for i in range(curve.point_count):
		var p: Vector2 = curve.get_point_position(i)
		var in_h: Vector2 = curve.get_point_in(i)
		var out_h: Vector2 = curve.get_point_out(i)
		curve.set_point_position(i, p * scale_factor + offset)
		curve.set_point_in(i, in_h * scale_factor)
		curve.set_point_out(i, out_h * scale_factor)
	return curve

func _get_curve_bounds(curve: Curve2D) -> Rect2:
	if curve == null or curve.point_count <= 0:
		return Rect2()
	var p0: Vector2 = curve.get_point_position(0)
	var min_x: float = p0.x
	var max_x: float = p0.x
	var min_y: float = p0.y
	var max_y: float = p0.y
	for i in range(1, curve.point_count):
		var p: Vector2 = curve.get_point_position(i)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(maxf(0.001, max_x - min_x), maxf(0.001, max_y - min_y)))

func _build_proc_sine_wave_vertical(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var amplitude: float = maxf(40.0, float(pattern_data.get("amplitude", 120.0)))
	var frequency: float = maxf(0.2, float(pattern_data.get("frequency", 1.5)))
	var length: float = maxf(300.0, float(pattern_data.get("length", 1200.0)))
	var steps: int = maxi(24, int(pattern_data.get("steps", 96)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var y: float = t * length
		var x: float = sin(t * TAU * frequency) * amplitude
		curve.add_point(Vector2(x, y))
	return curve

func _build_proc_figure_eight_vertical(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var amplitude: float = maxf(40.0, float(pattern_data.get("amplitude", 120.0)))
	var cycles: float = maxf(0.5, float(pattern_data.get("cycles", 2.0)))
	var length: float = maxf(300.0, float(pattern_data.get("length", 1200.0)))
	var steps: int = maxi(24, int(pattern_data.get("steps", 96)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = t * TAU * cycles
		var x: float = sin(a) * amplitude
		var y: float = (t * length) + (sin(a * 2.0) * amplitude * 0.18)
		curve.add_point(Vector2(x, y))
	return curve

func _build_proc_impatient_circle(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var radius: float = maxf(30.0, float(pattern_data.get("radius", 85.0)))
	var loops: float = maxf(0.5, float(pattern_data.get("loops", 1.3)))
	var charge_distance: float = maxf(80.0, float(pattern_data.get("charge_distance", 280.0)))
	var steps: int = maxi(24, int(pattern_data.get("steps", 80)))
	var last_y: float = 0.0
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var a: float = t * TAU * loops
		var p: Vector2 = Vector2(cos(a), sin(a)) * radius
		p.y += t * radius * 4.0
		last_y = p.y
		curve.add_point(p)
	curve.add_point(Vector2(0.0, last_y + charge_distance))
	return curve

func _build_proc_heart_shape(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var scale_v: float = maxf(4.0, float(pattern_data.get("scale", 8.0)))
	var steps: int = maxi(40, int(pattern_data.get("steps", 120)))
	for i in range(steps):
		var t: float = (float(i) / float(steps - 1)) * TAU
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		curve.add_point(Vector2(x, y) * scale_v)
	return curve

func _build_proc_dna_helix(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var amplitude: float = maxf(30.0, float(pattern_data.get("amplitude", 90.0)))
	var tightness: float = maxf(1.0, float(pattern_data.get("tightness", 5.5)))
	var length: float = maxf(300.0, float(pattern_data.get("length", 1200.0)))
	var steps: int = maxi(24, int(pattern_data.get("steps", 120)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var y: float = t * length
		var x: float = sin(t * tightness * TAU) * amplitude
		curve.add_point(Vector2(x, y))
	return curve

func _build_proc_spirograph_flower(pattern_data: Dictionary) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var petals: float = maxf(2.0, float(pattern_data.get("petals", 6.0)))
	var radius: float = maxf(25.0, float(pattern_data.get("radius", 90.0)))
	var length: float = maxf(300.0, float(pattern_data.get("length", 1200.0)))
	var steps: int = maxi(48, int(pattern_data.get("steps", 140)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = t * TAU * petals
		var r: float = radius * (0.55 + (0.45 * sin(a * 0.5)))
		var x: float = cos(a) * r
		var y: float = (t * length) + sin(a) * r * 0.35
		curve.add_point(Vector2(x, y))
	return curve

func _generate_fallback_curve() -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	var viewport_size: Vector2 = get_viewport_rect().size
	var center_x: float = viewport_size.x * 0.5
	curve.add_point(Vector2(center_x, 30.0))
	curve.add_point(Vector2(center_x, viewport_size.y - 30.0))
	return curve

func _setup_hazard_visual() -> void:
	_clear_container_children(hazard_visual)
	_hazard_scroll_layers.clear()
	_hazard_scroll_layer_height = 0.0
	_hazard_scroll_offset = 0.0
	_setup_hazard_overlay()
	_start_visual_node = _build_hazard_visual_node(_hazard_start_asset_path, false, true)
	_active_visual_node = _build_hazard_visual_node(_hazard_asset_path, true, false)
	if _start_visual_node and is_instance_valid(_start_visual_node):
		_start_visual_node.z_as_relative = false
		_start_visual_node.z_index = -39
		hazard_visual.add_child(_start_visual_node)
	if _active_visual_node and is_instance_valid(_active_visual_node):
		_active_visual_node.z_as_relative = false
		_active_visual_node.z_index = -40
		hazard_visual.add_child(_active_visual_node)
	_setup_warning_frame_overlay()
	_set_hazard_phase_visuals(true)

func _setup_hazard_overlay() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var dim := ColorRect.new()
	dim.name = "HazardDimOverlay"
	dim.position = Vector2.ZERO
	dim.size = viewport_size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0.0, 0.0, 0.0, _hazard_overlay_opacity)
	hazard_visual.add_child(dim)

func _build_hazard_visual_node(asset_path: String, allow_scroll_background: bool, fit_to_path_start: bool = false) -> Node:
	var viewport_size: Vector2 = get_viewport_rect().size
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null

	var loaded: Resource = _load_cached_resource(asset_path)
	if loaded is SpriteFrames:
		var anim: AnimatedSprite2D = AnimatedSprite2D.new()
		anim.centered = true
		var played_anim: StringName = VFXManager.play_sprite_frames(anim, loaded as SpriteFrames, &"default", true, 0.0)
		var frame_tex: Texture2D = _get_cached_first_frame_texture(anim.sprite_frames, played_anim) if anim.sprite_frames else null
		if fit_to_path_start:
			anim.position = _get_path_start_anchor()
			anim.scale = _compute_start_marker_scale(frame_tex)
		elif frame_tex:
			anim.position = viewport_size * 0.5
			var factor: float = maxf(viewport_size.x / frame_tex.get_size().x, viewport_size.y / frame_tex.get_size().y)
			anim.scale = Vector2.ONE * factor
		else:
			anim.position = viewport_size * 0.5
		return anim

	if loaded is Texture2D:
		if allow_scroll_background:
			return _build_scrolling_hazard_pattern(loaded as Texture2D, viewport_size)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.centered = fit_to_path_start
		sprite.texture = loaded as Texture2D
		var tex_size: Vector2 = sprite.texture.get_size()
		if fit_to_path_start:
			sprite.position = _get_path_start_anchor()
			sprite.scale = _compute_start_marker_scale(sprite.texture)
		elif tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.position = Vector2.ZERO
			var factor_cover: float = maxf(viewport_size.x / tex_size.x, viewport_size.y / tex_size.y)
			sprite.scale = Vector2.ONE * factor_cover
		return sprite
	return null

func _get_path_start_anchor() -> Vector2:
	if path2d != null and path2d.curve != null:
		return path2d.curve.sample_baked(0.0, true)
	return get_viewport_rect().size * 0.5

func _compute_start_marker_scale(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ONE
	var size: Vector2 = tex.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ONE
	var factor: float = _path_width / maxf(size.x, size.y)
	return Vector2.ONE * maxf(0.01, factor)

func _build_scrolling_hazard_pattern(tex: Texture2D, viewport_size: Vector2) -> Node:
	var container := Node2D.new()
	container.name = "HazardPatternLoop"
	var tex_size: Vector2 = tex.get_size()
	var scale_x: float = 1.0
	if tex_size.x > 0.0:
		scale_x = viewport_size.x / tex_size.x
	var scaled_h: float = maxf(1.0, tex_size.y * scale_x)
	_hazard_scroll_layer_height = scaled_h
	_hazard_scroll_offset = 0.0

	for i in range(2):
		var layer := Sprite2D.new()
		layer.centered = false
		layer.texture = tex
		layer.scale = Vector2(scale_x, scale_x)
		layer.position = Vector2(0.0, float(i) * scaled_h - scaled_h)
		container.add_child(layer)
		_hazard_scroll_layers.append(layer)
	return container

func _update_hazard_background_scroll(delta: float) -> void:
	if _hazard_scroll_layers.is_empty() or _hazard_scroll_layer_height <= 0.0:
		return
	_hazard_scroll_offset = fmod(_hazard_scroll_offset + (_hazard_scroll_speed_px_sec * delta), _hazard_scroll_layer_height)
	for i in range(_hazard_scroll_layers.size()):
		var layer := _hazard_scroll_layers[i]
		if not is_instance_valid(layer):
			continue
		layer.position.y = float(i) * _hazard_scroll_layer_height - _hazard_scroll_layer_height + _hazard_scroll_offset

func _setup_warning_frame_overlay() -> void:
	if _warning_frame_width <= 0.0:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_warning_frame_overlay = ColorRect.new()
	_warning_frame_overlay.name = "WarningFrameOverlay"
	_warning_frame_overlay.position = Vector2.ZERO
	_warning_frame_overlay.size = viewport_size
	_warning_frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_frame_overlay.color = Color(1, 1, 1, 1)

	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec2 rect_px = vec2(720.0, 1280.0);
uniform float border_px = 3.0;
uniform vec4 border_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform bool pulse_enabled = true;
uniform float pulse_px = 4.0;
uniform float damage_pulse_px = 60.0;
uniform float damage_pulse_strength = 0.0;
void fragment() {
	float dx = min(UV.x, 1.0 - UV.x) * rect_px.x;
	float dy = min(UV.y, 1.0 - UV.y) * rect_px.y;
	float d = min(dx, dy);
	float a = 0.0;
	if (d <= border_px) {
		a = 1.0;
	} else if (pulse_enabled && d <= border_px + pulse_px) {
		float t = 1.0 - ((d - border_px) / max(pulse_px, 0.0001));
		a = t * (0.35 + 0.35 * abs(sin(TIME * 6.0)));
	}
	if (damage_pulse_strength > 0.0 && d <= border_px + damage_pulse_px) {
		float td = 1.0 - ((d - border_px) / max(damage_pulse_px, 0.0001));
		a = max(a, td * damage_pulse_strength);
	}
	COLOR = vec4(border_color.rgb, border_color.a * a);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("rect_px", viewport_size)
	mat.set_shader_parameter("border_px", _warning_frame_width)
	mat.set_shader_parameter("border_color", _warning_frame_color)
	mat.set_shader_parameter("pulse_enabled", _warning_frame_pulse)
	mat.set_shader_parameter("pulse_px", _warning_frame_pulse_size)
	mat.set_shader_parameter("damage_pulse_px", _damage_frame_pulse_size)
	mat.set_shader_parameter("damage_pulse_strength", 0.0)
	_warning_frame_overlay.material = mat
	hazard_visual.add_child(_warning_frame_overlay)

func _set_hazard_phase_visuals(start_phase: bool) -> void:
	_in_start_phase = start_phase
	if _start_visual_node and is_instance_valid(_start_visual_node):
		_start_visual_node.visible = start_phase
	if _active_visual_node and is_instance_valid(_active_visual_node):
		_active_visual_node.visible = not start_phase

func _setup_path_visual() -> void:
	if path_visual == null:
		return
	path_visual.width = _path_width
	path_visual.default_color = Color(0.75, 1.0, 0.95, 0.65)
	path_visual.clear_points()
	path_visual.texture = null
	path_visual.texture_mode = Line2D.LINE_TEXTURE_TILE
	path_visual.joint_mode = Line2D.LINE_JOINT_SHARP
	path_visual.begin_cap_mode = Line2D.LINE_CAP_BOX
	path_visual.end_cap_mode = Line2D.LINE_CAP_BOX
	path_visual.round_precision = 8
	path_visual.visible = true
	_path_tile_texture = null
	_path_tile_scale = Vector2.ONE
	_path_tile_pool.clear()
	_clear_container_children(_path_tiles_root)

	if _path_anim_node and is_instance_valid(_path_anim_node):
		_path_anim_node.queue_free()
		_path_anim_node = null

	if _path_asset_path == "" or not ResourceLoader.exists(_path_asset_path):
		return

	var loaded: Resource = _load_cached_resource(_path_asset_path)
	if loaded is Texture2D:
		_path_tile_texture = loaded as Texture2D
		_path_tile_scale = _compute_path_tile_scale(_path_tile_texture)
		path_visual.default_color = Color(1.0, 1.0, 1.0, 0.0)
		path_visual.visible = false
		return
	if loaded is SpriteFrames:
		var frames: SpriteFrames = loaded as SpriteFrames
		var first_anim: StringName = &"default"
		if not frames.has_animation(first_anim) and frames.get_animation_names().size() > 0:
			first_anim = StringName(frames.get_animation_names()[0])
		_path_tile_texture = _get_cached_first_frame_texture(frames, first_anim)
		if _path_tile_texture:
			_path_tile_scale = _compute_path_tile_scale(_path_tile_texture)
			path_visual.default_color = Color(1.0, 1.0, 1.0, 0.0)
			path_visual.visible = false

func _reset_runtime_state() -> void:
	_elapsed = 0.0
	_path_progress = 0.0
	_in_start_phase = true
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_player_in_hazard = _player != null and is_instance_valid(_player)
	_player_in_safe_zone = false
	_active_path_points = PackedVector2Array()
	_warmup_anchor = Vector2.ZERO
	safe_polygon.polygon = PackedVector2Array()
	path_visual.clear_points()
	_set_visible_tile_count(0)

func _render_warmup_safe_zone() -> void:
	if path2d.curve == null:
		return
	var start_point: Vector2 = path2d.curve.sample_baked(0.0, true)
	_warmup_anchor = start_point
	var radius: float = _path_width * 0.5
	var circle_points: PackedVector2Array = _create_circle_polygon(start_point, radius, 24)
	safe_polygon.polygon = circle_points
	path_visual.clear_points()
	path_visual.add_point(start_point + Vector2(0.0, -2.0))
	path_visual.add_point(start_point + Vector2(0.0, 2.0))
	_active_path_points = path_visual.points
	_render_path_tiles_range(0.0, _path_width)

	if _path_anim_node and is_instance_valid(_path_anim_node):
		_path_anim_node.position = start_point

func _render_dynamic_safe_zone() -> void:
	if path2d.curve == null:
		return

	var from_dist: float = maxf(0.0, _path_progress - _tail_length_px)
	var to_dist: float = minf(_path_total_length, _path_progress + _head_length_px)
	if to_dist <= from_dist:
		safe_polygon.polygon = PackedVector2Array()
		path_visual.clear_points()
		return

	var path_points: PackedVector2Array = _sample_curve_segment(path2d.curve, from_dist, to_dist, 22.0)
	path_visual.points = path_points
	_active_path_points = path_points
	_render_path_tiles_range(from_dist, to_dist)
	# Safe-zone is computed analytically from polyline distance to avoid
	# convex decomposition failures on collision polygon for sharp turns.
	safe_polygon.polygon = PackedVector2Array()

	if _path_anim_node and is_instance_valid(_path_anim_node):
		_path_anim_node.position = path2d.curve.sample_baked(minf(_path_total_length, _path_progress), true)

func _sample_curve_segment(curve: Curve2D, from_dist: float, to_dist: float, step_px: float = 20.0) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if curve == null:
		return points
	var span: float = maxf(1.0, to_dist - from_dist)
	var steps: int = maxi(8, int(ceil(span / maxf(2.0, step_px))))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var d: float = lerpf(from_dist, to_dist, t)
		points.append(curve.sample_baked(d, true))
	return points

func _create_circle_polygon(center: Vector2, radius: float, points: int = 24) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(8, points)
	for i in range(count):
		var a: float = (float(i) / float(count)) * TAU
		poly.append(center + (Vector2(cos(a), sin(a)) * radius))
	return poly

func _setup_zone_signals() -> void:
	if hazard_zone:
		if not hazard_zone.body_entered.is_connected(_on_hazard_body_entered):
			hazard_zone.body_entered.connect(_on_hazard_body_entered)
		if not hazard_zone.body_exited.is_connected(_on_hazard_body_exited):
			hazard_zone.body_exited.connect(_on_hazard_body_exited)
	if safe_zone:
		if not safe_zone.body_entered.is_connected(_on_safe_zone_body_entered):
			safe_zone.body_entered.connect(_on_safe_zone_body_entered)
		if not safe_zone.body_exited.is_connected(_on_safe_zone_body_exited):
			safe_zone.body_exited.connect(_on_safe_zone_body_exited)

func _on_hazard_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player = body
	_player_in_hazard = true

func _on_hazard_body_exited(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_in_hazard = false

func _on_safe_zone_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player = body
	_player_in_safe_zone = true

func _on_safe_zone_body_exited(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_in_safe_zone = false

func _on_damage_tick_timer_timeout() -> void:
	if not _is_running:
		return
	if _elapsed < _start_delay_sec:
		return
	_refresh_player_zone_flags()
	if _player == null or not is_instance_valid(_player):
		return
	if _player_in_hazard and not _player_in_safe_zone and _player.has_method("take_damage"):
		_player.call("take_damage", _tick_damage)
		_trigger_damage_frame_pulse()

func _trigger_damage_frame_pulse() -> void:
	if _warning_frame_overlay == null or not is_instance_valid(_warning_frame_overlay):
		return
	var mat: ShaderMaterial = _warning_frame_overlay.material as ShaderMaterial
	if mat == null:
		return
	if _damage_pulse_tween and _damage_pulse_tween.is_running():
		_damage_pulse_tween.kill()
	mat.set_shader_parameter("damage_pulse_strength", 1.0)
	_damage_pulse_tween = create_tween()
	_damage_pulse_tween.tween_method(_set_damage_pulse_strength, 1.0, 0.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_damage_pulse_strength(value: float) -> void:
	if _warning_frame_overlay == null or not is_instance_valid(_warning_frame_overlay):
		return
	var mat: ShaderMaterial = _warning_frame_overlay.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("damage_pulse_strength", value)

func _end_trial() -> void:
	if _ending:
		return
	_ending = true
	_is_running = false
	if damage_tick_timer:
		damage_tick_timer.stop()
	var fade_out := create_tween()
	fade_out.tween_property(hazard_visual, "modulate:a", 0.0, _hazard_fade_duration_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.finished.connect(func() -> void:
		finished.emit()
		queue_free()
	)

func _clear_container_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is Node:
			(child as Node).queue_free()

func _refresh_player_zone_flags() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_player_in_hazard = _player != null and is_instance_valid(_player)
	if not _player_in_hazard:
		_player_in_safe_zone = false
		return
	if _elapsed < _start_delay_sec:
		_player_in_safe_zone = to_local(_player.global_position).distance_to(_warmup_anchor) <= (_path_width * 0.5)
		return
	if _active_path_points.size() < 2:
		_player_in_safe_zone = false
		return
	var player_local: Vector2 = to_local(_player.global_position)
	_player_in_safe_zone = _distance_to_polyline(player_local, _active_path_points) <= (_path_width * 0.5)

func _distance_to_polyline(point: Vector2, polyline: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(polyline.size() - 1):
		var a: Vector2 = polyline[i]
		var b: Vector2 = polyline[i + 1]
		var d: float = _distance_to_segment(point, a, b)
		if d < best:
			best = d
	return best

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _compute_path_tile_scale(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ONE
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Vector2.ONE
	# Strict contain: tile visual size must never exceed path_width.
	var contain_factor: float = minf(_path_width / tex_size.x, _path_width / tex_size.y)
	# Keep optional downscale (<1.0), but block any upscaling above contained size.
	var user_scale: float = clampf(_path_asset_scale, 0.01, 1.0)
	var factor: float = contain_factor * user_scale
	return Vector2.ONE * maxf(0.01, factor)

func _render_path_tiles_range(from_dist: float, to_dist: float) -> void:
	if _path_tiles_root == null or _path_tile_texture == null or path2d.curve == null:
		_set_visible_tile_count(0)
		return
	if to_dist <= from_dist:
		_set_visible_tile_count(0)
		return
	var step: float = maxf(4.0, _path_width) # Never place two tiles under path_width.
	var start_index: int = int(ceil(from_dist / step))
	var end_index: int = int(floor(to_dist / step))
	var needed: int = maxi(0, end_index - start_index + 1)
	_ensure_tile_pool_size(needed)
	for i in range(needed):
		var d: float = float(start_index + i) * step
		var p: Vector2 = path2d.curve.sample_baked(clampf(d, 0.0, _path_total_length), true)
		var tile: Sprite2D = _path_tile_pool[i]
		tile.position = p
		tile.visible = true
		tile.texture = _path_tile_texture
		tile.scale = _path_tile_scale
	_set_visible_tile_count(needed)

func _ensure_tile_pool_size(count: int) -> void:
	if _path_tiles_root == null:
		return
	while _path_tile_pool.size() < count:
		var tile := Sprite2D.new()
		tile.centered = true
		tile.visible = false
		_path_tiles_root.add_child(tile)
		_path_tile_pool.append(tile)

func _set_visible_tile_count(count: int) -> void:
	for i in range(_path_tile_pool.size()):
		_path_tile_pool[i].visible = i < count

func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _strong_resource_cache.has(path):
		var cached: Variant = _strong_resource_cache[path]
		if cached is Resource:
			return cached as Resource

	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if loaded != null:
		if _strong_resource_cache.size() >= STRONG_RESOURCE_CACHE_MAX:
			_strong_resource_cache.clear()
			_first_frame_texture_cache.clear()
		_strong_resource_cache[path] = loaded
	return loaded

func _get_cached_first_frame_texture(frames: SpriteFrames, anim_name: StringName) -> Texture2D:
	if frames == null or anim_name == &"":
		return null
	var key: String = _build_frame_cache_key(frames, anim_name)
	if _first_frame_texture_cache.has(key):
		var cached: Variant = _first_frame_texture_cache[key]
		if cached is Texture2D:
			return cached as Texture2D
	var tex: Texture2D = frames.get_frame_texture(anim_name, 0)
	if tex:
		_first_frame_texture_cache[key] = tex
	return tex

func _build_frame_cache_key(frames: SpriteFrames, anim_name: StringName) -> String:
	var path: String = frames.resource_path
	if path == "":
		path = "rid:" + str(frames.get_rid().get_id())
	return path + "|" + String(anim_name)
