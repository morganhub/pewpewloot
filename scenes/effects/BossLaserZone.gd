extends Area2D
class_name BossLaserZone

var mode: String = "line" # line | cone
var length: float = 900.0
var width: float = 80.0
var cone_angle_deg: float = 38.0
var telegraph_duration: float = 0.8
var active_duration: float = 1.4
var damage_per_second: float = 28.0
var tick_interval: float = 0.1
var sweep_speed_deg: float = 0.0
var follow_source: bool = true
var track_player_on_activate: bool = true

var source: Node2D = null
var source_offset: Vector2 = Vector2.ZERO

var _time_alive: float = 0.0
var _tick_timer: float = 0.0
var _is_active: bool = false
var _telegraph_color: Color = Color(1.0, 0.35, 0.2, 0.25)
var _active_color: Color = Color(1.0, 0.15, 0.1, 0.55)

var _shape_node: Node = null
var _visual: Polygon2D = null

func setup(caster: Node2D, hazard_data: Dictionary, default_duration: float = 2.0) -> void:
	source = caster
	mode = str(hazard_data.get("mode", "line"))
	length = maxf(80.0, float(hazard_data.get("length", 900.0)))
	width = maxf(12.0, float(hazard_data.get("width", 80.0)))
	cone_angle_deg = clampf(float(hazard_data.get("cone_angle_deg", 38.0)), 10.0, 170.0)
	telegraph_duration = maxf(0.0, float(hazard_data.get("telegraph_duration", 0.8)))
	active_duration = maxf(0.15, float(hazard_data.get("active_duration", maxf(0.4, default_duration * 0.45))))
	damage_per_second = maxf(1.0, float(hazard_data.get("damage_per_second", 28.0)))
	tick_interval = maxf(0.05, float(hazard_data.get("tick_interval", 0.1)))
	sweep_speed_deg = float(hazard_data.get("sweep_speed_deg", 0.0))
	follow_source = bool(hazard_data.get("follow_source", true))
	track_player_on_activate = bool(hazard_data.get("track_player_on_activate", true))
	var raw_offset: Variant = hazard_data.get("offset", [0.0, 0.0])
	if raw_offset is Array and (raw_offset as Array).size() >= 2:
		var arr := raw_offset as Array
		source_offset = Vector2(float(arr[0]), float(arr[1]))
	_telegraph_color = Color(str(hazard_data.get("telegraph_color", "#FF8A55")))
	_telegraph_color.a = clampf(float(hazard_data.get("telegraph_alpha", _telegraph_color.a)), 0.05, 1.0)
	_active_color = Color(str(hazard_data.get("active_color", "#FF331A")))
	_active_color.a = clampf(float(hazard_data.get("active_alpha", _active_color.a)), 0.05, 1.0)

	_update_position_from_source()
	if bool(hazard_data.get("aim_player_on_spawn", true)):
		_aim_toward_player()
	_rebuild_shape_and_visual(false)

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0

	_visual = Polygon2D.new()
	_visual.z_index = -2
	add_child(_visual)

	_rebuild_shape_and_visual(false)

func _process(delta: float) -> void:
	_time_alive += delta
	_tick_timer += delta

	if follow_source:
		_update_position_from_source()

	if _is_active and sweep_speed_deg != 0.0:
		rotation_degrees += sweep_speed_deg * delta

	if not _is_active and _time_alive >= telegraph_duration:
		if track_player_on_activate:
			_aim_toward_player()
		_set_active_state(true)

	if _is_active:
		if _tick_timer >= tick_interval:
			_tick_timer -= tick_interval
			_apply_damage_tick()
		if _time_alive >= telegraph_duration + active_duration:
			queue_free()
	else:
		var pulse: float = 0.5 - (0.5 * cos((_time_alive * 10.0)))
		modulate.a = lerpf(0.65, 1.0, pulse)

func _set_active_state(active: bool) -> void:
	_is_active = active
	_tick_timer = 0.0
	collision_mask = 2 if active else 0
	_rebuild_shape_and_visual(active)
	modulate.a = 1.0

func _apply_damage_tick() -> void:
	var damage_tick: int = maxi(1, int(round(damage_per_second * tick_interval)))
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage_tick)

func _update_position_from_source() -> void:
	if source and is_instance_valid(source):
		global_position = source.global_position + source_offset.rotated(source.global_rotation)

func _aim_toward_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player is Node2D:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		rotation = dir.angle() + PI / 2.0

func _rebuild_shape_and_visual(active: bool) -> void:
	if _shape_node and is_instance_valid(_shape_node):
		_shape_node.queue_free()
	_shape_node = null

	if mode == "cone":
		var collision_poly := CollisionPolygon2D.new()
		collision_poly.polygon = _build_cone_polygon(length, cone_angle_deg)
		_shape_node = collision_poly
		add_child(collision_poly)
		if _visual:
			_visual.polygon = collision_poly.polygon
	else:
		var collision := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, length)
		collision.shape = rect
		collision.position = Vector2(0.0, -length * 0.5)
		_shape_node = collision
		add_child(collision)
		if _visual:
			_visual.polygon = _build_line_polygon(width, length)

	if _visual:
		_visual.color = _active_color if active else _telegraph_color

func _build_line_polygon(line_width: float, line_length: float) -> PackedVector2Array:
	var half_w: float = line_width * 0.5
	return PackedVector2Array([
		Vector2(-half_w, 0.0),
		Vector2(half_w, 0.0),
		Vector2(half_w, -line_length),
		Vector2(-half_w, -line_length)
	])

func _build_cone_polygon(cone_length: float, angle_deg: float) -> PackedVector2Array:
	var half: float = deg_to_rad(angle_deg * 0.5)
	var left := Vector2(0.0, -cone_length).rotated(-half)
	var right := Vector2(0.0, -cone_length).rotated(half)
	return PackedVector2Array([
		Vector2.ZERO,
		left,
		right
	])
