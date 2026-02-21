extends Area2D
class_name BossVoidZone

var radius: float = 120.0
var telegraph_duration: float = 0.8
var active_duration: float = 2.5
var damage_per_second: float = 20.0
var tick_interval: float = 0.2
var follow_source: bool = false
var source: Node2D = null
var source_offset: Vector2 = Vector2.ZERO

var _time_alive: float = 0.0
var _tick_timer: float = 0.0
var _is_active: bool = false
var _telegraph_color: Color = Color(0.65, 0.2, 1.0, 0.25)
var _active_color: Color = Color(0.45, 0.0, 0.85, 0.45)

var _zone_visual: Polygon2D = null
var _ring_visual: Polygon2D = null
var _collision: CollisionShape2D = null

func setup(caster: Node2D, hazard_data: Dictionary, default_duration: float = 2.0) -> void:
	source = caster
	radius = maxf(16.0, float(hazard_data.get("radius", 120.0)))
	telegraph_duration = maxf(0.0, float(hazard_data.get("telegraph_duration", 0.8)))
	active_duration = maxf(0.1, float(hazard_data.get("active_duration", maxf(0.4, default_duration * 0.6))))
	damage_per_second = maxf(1.0, float(hazard_data.get("damage_per_second", 20.0)))
	tick_interval = maxf(0.05, float(hazard_data.get("tick_interval", 0.2)))
	follow_source = bool(hazard_data.get("follow_source", false))
	var raw_offset: Variant = hazard_data.get("offset", [0.0, 0.0])
	if raw_offset is Array and (raw_offset as Array).size() >= 2:
		var arr := raw_offset as Array
		source_offset = Vector2(float(arr[0]), float(arr[1]))
	_telegraph_color = Color(str(hazard_data.get("telegraph_color", "#AA55FF")))
	_telegraph_color.a = clampf(float(hazard_data.get("telegraph_alpha", _telegraph_color.a)), 0.05, 1.0)
	_active_color = Color(str(hazard_data.get("active_color", "#6611CC")))
	_active_color.a = clampf(float(hazard_data.get("active_alpha", _active_color.a)), 0.05, 1.0)

	_update_position_from_source()
	_update_shape()
	_update_visual(false)

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0

	_collision = CollisionShape2D.new()
	_collision.shape = CircleShape2D.new()
	add_child(_collision)

	_zone_visual = Polygon2D.new()
	_zone_visual.z_index = -3
	add_child(_zone_visual)

	_ring_visual = Polygon2D.new()
	_ring_visual.z_index = -2
	add_child(_ring_visual)

	_update_shape()
	_update_visual(false)

func _process(delta: float) -> void:
	_time_alive += delta
	_tick_timer += delta

	if follow_source:
		_update_position_from_source()

	if not _is_active and _time_alive >= telegraph_duration:
		_set_active_state(true)

	if _is_active:
		if _tick_timer >= tick_interval:
			_tick_timer -= tick_interval
			_apply_damage_tick()
		if _time_alive >= telegraph_duration + active_duration:
			queue_free()
	else:
		var pulse: float = 0.5 - (0.5 * cos((_time_alive * 8.0)))
		modulate.a = lerpf(0.65, 1.0, pulse)

func _set_active_state(active: bool) -> void:
	_is_active = active
	_tick_timer = 0.0
	collision_mask = 2 if active else 0
	_update_visual(active)
	modulate.a = 1.0

func _apply_damage_tick() -> void:
	var damage_tick: int = maxi(1, int(round(damage_per_second * tick_interval)))
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage_tick)

func _update_position_from_source() -> void:
	if source and is_instance_valid(source):
		global_position = source.global_position + source_offset

func _update_shape() -> void:
	if _collision and _collision.shape is CircleShape2D:
		(_collision.shape as CircleShape2D).radius = radius

	if _zone_visual:
		_zone_visual.polygon = _create_circle_polygon(radius, 40)
	if _ring_visual:
		var outer := _create_circle_polygon(radius * 1.02, 40)
		var inner := _create_circle_polygon(radius * 0.82, 40)
		_ring_visual.polygon = _create_ring_polygon(outer, inner)

func _update_visual(active: bool) -> void:
	if _zone_visual:
		_zone_visual.color = _active_color if active else _telegraph_color
	if _ring_visual:
		var c := _active_color if active else _telegraph_color
		c.a = clampf(c.a + 0.2, 0.1, 1.0)
		_ring_visual.color = c

func _create_circle_polygon(r: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points

func _create_ring_polygon(outer: PackedVector2Array, inner: PackedVector2Array) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for p in outer:
		points.append(p)
	for i in range(inner.size() - 1, -1, -1):
		points.append(inner[i])
	return points
