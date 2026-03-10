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
var damage_target_group: String = "player"

var source: Node2D = null
var source_offset: Vector2 = Vector2.ZERO

var _time_alive: float = 0.0
var _tick_timer: float = 0.0
var _is_active: bool = false
var _telegraph_color: Color = Color(1.0, 0.35, 0.2, 0.25)
var _active_color: Color = Color(1.0, 0.15, 0.1, 0.55)
var _target_node: Node2D = null
var _telegraph_texture: Texture2D = null
var _active_texture: Texture2D = null

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
	damage_target_group = str(hazard_data.get("damage_target_group", "enemies" if source and source.is_in_group("player") else "player"))
	_target_node = hazard_data.get("target_node") as Node2D
	var raw_offset: Variant = hazard_data.get("offset", [0.0, 0.0])
	if raw_offset is Array and (raw_offset as Array).size() >= 2:
		var arr := raw_offset as Array
		source_offset = Vector2(float(arr[0]), float(arr[1]))
	_telegraph_color = Color(str(hazard_data.get("telegraph_color", "#FF8A55")))
	_telegraph_color.a = clampf(float(hazard_data.get("telegraph_alpha", _telegraph_color.a)), 0.05, 1.0)
	_active_color = Color(str(hazard_data.get("active_color", "#FF331A")))
	_active_color.a = clampf(float(hazard_data.get("active_alpha", _active_color.a)), 0.05, 1.0)
	_telegraph_texture = _resolve_texture_from_hazard(hazard_data, "telegraph_")
	if _telegraph_texture == null:
		_telegraph_texture = _resolve_texture_from_hazard(hazard_data)
	_active_texture = _resolve_texture_from_hazard(hazard_data, "active_")
	if _active_texture == null:
		_active_texture = _resolve_texture_from_hazard(hazard_data)

	_update_position_from_source()
	if bool(hazard_data.get("aim_player_on_spawn", true)):
		_aim_toward_target()
	_rebuild_shape_and_visual(false)

func _ready() -> void:
	add_to_group("runtime_hazards")
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
			_aim_toward_target()
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
	collision_mask = _get_collision_mask_for_target_group() if active else 0
	_rebuild_shape_and_visual(active)
	modulate.a = 1.0

func _apply_damage_tick() -> void:
	var damage_tick: int = maxi(1, int(round(damage_per_second * tick_interval)))
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body == null:
			continue
		if not body.is_in_group(damage_target_group):
			continue
		if body.has_method("take_damage"):
			body.take_damage(damage_tick)

func _update_position_from_source() -> void:
	if source and is_instance_valid(source):
		global_position = source.global_position + source_offset.rotated(source.global_rotation)

func _aim_toward_target() -> void:
	var target := _resolve_target_node()
	if target == null:
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	if dir != Vector2.ZERO:
		rotation = dir.angle() + PI / 2.0

func _resolve_target_node() -> Node2D:
	if _target_node and is_instance_valid(_target_node):
		return _target_node
	if source and is_instance_valid(source) and source.is_in_group("player"):
		var best_enemy: Node2D = null
		var best_distance: float = INF
		for enemy_variant in get_tree().get_nodes_in_group("enemies"):
			if not (enemy_variant is Node2D):
				continue
			var enemy := enemy_variant as Node2D
			if not is_instance_valid(enemy):
				continue
			if enemy.is_in_group("boss"):
				return enemy
			var candidate_distance: float = global_position.distance_to(enemy.global_position)
			if candidate_distance < best_distance:
				best_distance = candidate_distance
				best_enemy = enemy
		return best_enemy
	var player := get_tree().get_first_node_in_group("player")
	return player as Node2D if player is Node2D else null

func _get_collision_mask_for_target_group() -> int:
	match damage_target_group:
		"enemies":
			return 4
		_:
			return 2

func _rebuild_shape_and_visual(active: bool) -> void:
	if _shape_node and is_instance_valid(_shape_node):
		_shape_node.queue_free()
	_shape_node = null

	var polygon: PackedVector2Array = PackedVector2Array()
	if mode == "cone":
		polygon = _build_cone_polygon(length, cone_angle_deg)
		var collision_poly := CollisionPolygon2D.new()
		collision_poly.polygon = polygon
		_shape_node = collision_poly
		add_child(collision_poly)
	else:
		polygon = _build_line_polygon(width, length)
		var collision := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, length)
		collision.shape = rect
		collision.position = Vector2(0.0, -length * 0.5)
		_shape_node = collision
		add_child(collision)

	if _visual:
		_visual.polygon = polygon
		_visual.uv = _build_uv_for_polygon(polygon)
		_visual.color = _active_color if active else _telegraph_color
		_visual.texture = _active_texture if active else _telegraph_texture
		_visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if _visual.texture != null else CanvasItem.TEXTURE_REPEAT_DISABLED

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

func _build_uv_for_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var uvs: PackedVector2Array = []
	if polygon.is_empty():
		return uvs
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var size := bounds.size
	if absf(size.x) < 0.001:
		size.x = 1.0
	if absf(size.y) < 0.001:
		size.y = 1.0
	for point in polygon:
		var normalized := point - bounds.position
		uvs.append(Vector2(normalized.x / size.x, normalized.y / size.y))
	return uvs

func _resolve_texture_from_hazard(hazard_data: Dictionary, prefix: String = "") -> Texture2D:
	var asset_anim: String = str(hazard_data.get(prefix + "asset_anim", ""))
	var asset_path: String = str(hazard_data.get(prefix + "asset", ""))
	var duration: float = maxf(0.0, float(hazard_data.get(prefix + "asset_anim_duration", hazard_data.get(prefix + "asset_duration", 0.0))))
	var loop: bool = bool(hazard_data.get(prefix + "asset_anim_loop", hazard_data.get(prefix + "asset_loop", true)))
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		return _build_texture_from_asset(asset_anim, loop, duration)
	if asset_path != "" and ResourceLoader.exists(asset_path):
		return _build_texture_from_asset(asset_path, loop, duration)
	return null

func _build_texture_from_asset(asset_path: String, loop: bool, duration: float) -> Texture2D:
	var resource: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource is Texture2D:
		return resource as Texture2D
	if not (resource is SpriteFrames):
		return null
	var frames: SpriteFrames = resource as SpriteFrames
	var animation_names: PackedStringArray = frames.get_animation_names()
	if animation_names.is_empty():
		return null
	var anim_name: StringName = StringName(animation_names[0])
	var frame_count: int = frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return null
	var animated_obj: Object = ClassDB.instantiate("AnimatedTexture")
	if animated_obj == null:
		return frames.get_frame_texture(anim_name, 0)
	if _object_has_property(animated_obj, "frames"):
		animated_obj.set("frames", frame_count)
	var fps: float = maxf(frames.get_animation_speed(anim_name), 0.01)
	if duration > 0.0:
		fps = float(frame_count) / duration
	if _object_has_property(animated_obj, "fps"):
		animated_obj.set("fps", fps)
	if _object_has_property(animated_obj, "one_shot"):
		animated_obj.set("one_shot", not loop)
	for i in range(frame_count):
		if animated_obj.has_method("set_frame_texture"):
			animated_obj.call("set_frame_texture", i, frames.get_frame_texture(anim_name, i))
		if animated_obj.has_method("set_frame_duration"):
			var frame_duration: float = maxf(0.001, frames.get_frame_duration(anim_name, i))
			animated_obj.call("set_frame_duration", i, frame_duration)
	if animated_obj is Texture2D:
		return animated_obj as Texture2D
	return frames.get_frame_texture(anim_name, 0)

func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	for info in obj.get_property_list():
		if info is Dictionary and str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false
