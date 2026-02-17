extends Area2D

## ToxicPool — Zone de degats persistante (branche Poison).
## Inflige des degats aux ennemis dans sa zone pendant sa duree.

var pool_radius: float = 50.0
var pool_duration: float = 3.0
var pool_dps: float = 8.0
var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _visual_asset: String = ""
var _visual_asset_anim: String = ""
var _visual_asset_anim_duration: float = 0.0
var _visual_asset_anim_loop: bool = true
var _visual_size: float = 120.0
const TICK_INTERVAL: float = 0.5

func setup(radius: float, duration: float, dps: float, visual_data: Dictionary = {}) -> void:
	pool_radius = radius
	pool_duration = duration
	pool_dps = dps
	_visual_asset = str(visual_data.get("asset", ""))
	_visual_asset_anim = str(visual_data.get("asset_anim", ""))
	_visual_asset_anim_duration = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	_visual_asset_anim_loop = bool(visual_data.get("asset_anim_loop", true))
	_visual_size = maxf(20.0, float(visual_data.get("size", pool_radius * 2.0)))
	_update_visuals()
	_update_shape()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Enemy layer

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = pool_radius
	col.shape = shape
	add_child(col)

	_update_visuals()

	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.7, 0.2)

func _update_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			var circle := child.shape as CircleShape2D
			circle.radius = pool_radius

func _update_visuals() -> void:
	var old := get_node_or_null("PoolVisual")
	if old:
		old.queue_free()

	var visual := Node2D.new()
	visual.name = "PoolVisual"
	visual.z_index = -6
	add_child(visual)

	if _try_add_animated_visual(
		visual,
		_visual_asset_anim,
		_visual_size,
		Color(0.65, 1.0, 0.65, 0.55),
		_visual_asset_anim_duration,
		_visual_asset_anim_loop
	):
		return
	if _try_add_static_visual(visual, _visual_asset, _visual_size, Color(0.65, 1.0, 0.65, 0.5)):
		return

	var ring := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * pool_radius)
	ring.polygon = points
	ring.color = Color(0.2, 0.9, 0.1, 0.4)
	visual.add_child(ring)

func _process(delta: float) -> void:
	_elapsed += delta
	_tick_timer += delta

	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_damage()

	if _elapsed >= pool_duration:
		_fade_and_die()
		set_process(false)

func _apply_damage() -> void:
	var tick_damage := int(pool_dps * TICK_INTERVAL)
	if tick_damage < 1:
		tick_damage = 1

	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(tick_damage)
		if body.has_method("apply_status_effect"):
			var poison := StatusEffect.create_poison(float(tick_damage) * 2.0, 2.0)
			body.apply_status_effect(poison)

func _fade_and_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
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
	var res := load(asset_anim)
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
	var res := load(asset)
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
