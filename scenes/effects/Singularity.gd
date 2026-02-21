extends Area2D

## Singularity — Zone d'attraction gravitationnelle (branche Void).
## Attire les ennemis vers le centre et inflige des degats croissants.

var singularity_radius: float = 80.0
var singularity_duration: float = 1.0
var damage_base: float = 5.0
var damage_exponent: float = 2.0
var spaghettification: bool = false

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _visual_asset: String = ""
var _visual_asset_anim: String = ""
var _visual_asset_anim_duration: float = 0.0
var _visual_asset_anim_loop: bool = true
var _visual_size: float = 160.0
const TICK_INTERVAL: float = 0.1
const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {} # path -> Resource

func setup(
	radius: float,
	duration: float,
	dmg_base: float,
	dmg_exp: float,
	has_spaghetti: bool = false,
	visual_data: Dictionary = {}
) -> void:
	singularity_radius = radius
	singularity_duration = duration
	damage_base = dmg_base
	damage_exponent = dmg_exp
	spaghettification = has_spaghetti
	_visual_asset = str(visual_data.get("asset", ""))
	_visual_asset_anim = str(visual_data.get("asset_anim", ""))
	_visual_asset_anim_duration = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	_visual_asset_anim_loop = bool(visual_data.get("asset_anim_loop", true))
	_visual_size = maxf(20.0, float(visual_data.get("size", singularity_radius * 2.0)))
	_update_visuals()
	_update_shape()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Enemy layer

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = singularity_radius
	col.shape = shape
	add_child(col)

	_update_visuals()

	scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _update_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			var circle := child.shape as CircleShape2D
			circle.radius = singularity_radius

func _update_visuals() -> void:
	var old := get_node_or_null("SingularityVisual")
	if old:
		old.queue_free()

	var visual := Node2D.new()
	visual.name = "SingularityVisual"
	visual.z_index = -7
	add_child(visual)

	if _try_add_animated_visual(
		visual,
		_visual_asset_anim,
		_visual_size,
		Color(0.85, 0.7, 1.0, 0.6),
		_visual_asset_anim_duration,
		_visual_asset_anim_loop
	):
		return
	if _try_add_static_visual(visual, _visual_asset, _visual_size, Color(0.85, 0.7, 1.0, 0.55)):
		return

	var ring := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments := 32
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * singularity_radius)
	ring.polygon = points
	ring.color = Color(0.4, 0.0, 0.8, 0.5)
	visual.add_child(ring)

	var core := Polygon2D.new()
	var core_points: PackedVector2Array = []
	for j in range(segments):
		var core_angle := (float(j) / float(segments)) * TAU
		core_points.append(Vector2(cos(core_angle), sin(core_angle)) * (singularity_radius * 0.3))
	core.polygon = core_points
	core.color = Color(0.2, 0.0, 0.4, 0.8)
	visual.add_child(core)

func _process(delta: float) -> void:
	_elapsed += delta
	_tick_timer += delta

	var visual := get_node_or_null("SingularityVisual")
	if visual:
		visual.rotation += delta * 3.0

	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_pull_and_damage()

	if _elapsed >= singularity_duration:
		_implode_and_die()
		set_process(false)

func _pull_and_damage() -> void:
	var time_ratio := _elapsed / singularity_duration
	var current_damage := int(damage_base * pow(1.0 + time_ratio, damage_exponent))

	var bodies := get_overlapping_bodies()
	for body in bodies:
		if not body.is_in_group("enemies"):
			continue

		var dir_to_center := global_position - body.global_position
		var dist := dir_to_center.length()
		if dist > 5.0:
			var pull_force := dir_to_center.normalized() * 150.0 * (1.0 - (dist / singularity_radius))
			if body.has_method("apply_external_displacement"):
				body.apply_external_displacement(pull_force * TICK_INTERVAL)
			else:
				body.global_position += pull_force * TICK_INTERVAL

		if body.has_method("take_damage"):
			body.take_damage(current_damage)

		if spaghettification and dist < singularity_radius * 0.5:
			var stretch := 1.0 + (1.0 - dist / (singularity_radius * 0.5)) * 0.5
			body.scale = Vector2(1.0 / stretch, stretch)

func _implode_and_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(queue_free)

func _try_add_animated_visual(
	parent: Node2D,
	asset_anim: String,
	target_size: float,
	tint: Color,
	anim_duration: float,
	anim_loop: bool
) -> bool:
	if asset_anim == "" or not ResourceLoader.exists(asset_anim):
		return false
	var res: Resource = _load_cached_resource(asset_anim)
	if not (res is SpriteFrames):
		return false
	var frames := res as SpriteFrames
	var anim_names: PackedStringArray = frames.get_animation_names()
	if anim_names.is_empty():
		return false
	var anim_name: StringName = StringName(anim_names[0])
	if frames.get_frame_count(anim_name) <= 0:
		return false

	var sprite := AnimatedSprite2D.new()
	var played_anim: StringName = VFXManager.play_sprite_frames(
		sprite,
		frames,
		anim_name,
		anim_loop,
		anim_duration
	)
	if played_anim == &"":
		return false
	sprite.modulate = tint
	parent.add_child(sprite)

	var frame_tex: Texture2D = sprite.sprite_frames.get_frame_texture(played_anim, 0)
	if frame_tex:
		var frame_size: Vector2 = frame_tex.get_size()
		if frame_size.x > 0 and frame_size.y > 0:
			var scale_factor: float = target_size / maxf(frame_size.x, frame_size.y)
			sprite.scale = Vector2.ONE * scale_factor
	return true

func _try_add_static_visual(parent: Node2D, asset: String, target_size: float, tint: Color) -> bool:
	if asset == "" or not ResourceLoader.exists(asset):
		return false
	var res: Resource = _load_cached_resource(asset)
	if not (res is Texture2D):
		return false
	var texture := res as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.modulate = tint
	parent.add_child(sprite)

	var tex_size: Vector2 = texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		var scale_factor: float = target_size / maxf(tex_size.x, tex_size.y)
		sprite.scale = Vector2.ONE * scale_factor
	return true

func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _strong_resource_cache.has(path):
		var cached: Variant = _strong_resource_cache[path]
		if cached is Resource:
			return cached as Resource
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource != null:
		if _strong_resource_cache.size() >= STRONG_RESOURCE_CACHE_MAX:
			_strong_resource_cache.clear()
		_strong_resource_cache[path] = resource
	return resource
