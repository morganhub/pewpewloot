extends Area2D

## IceAura — Aura de froid autour du joueur (branche Frozen).
## Ralentit les ennemis proches, peut les geler apres exposition, et appliquer un DoT de froid.

var aura_radius: float = 100.0
var slow_factor: float = 0.15
var freeze_aura_time: float = 0.0
var freeze_duration: float = 2.0
var freeze_dot_dps: float = 0.0
var _tick_timer: float = 0.0
var _visual_asset: String = ""
var _visual_asset_anim: String = ""
var _visual_asset_anim_duration: float = 0.0
var _visual_asset_anim_loop: bool = true
var _visual_size: float = 220.0
const TICK_INTERVAL: float = 0.5
const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {} # path -> Resource

func setup(
	radius: float,
	slow: float,
	freeze_time: float = 0.0,
	freeze_time_duration: float = 2.0,
	freeze_dot: float = 0.0,
	visual_data: Dictionary = {}
) -> void:
	aura_radius = radius
	slow_factor = slow
	freeze_aura_time = maxf(0.0, freeze_time)
	freeze_duration = maxf(0.1, freeze_time_duration)
	freeze_dot_dps = maxf(0.0, freeze_dot)
	_visual_asset = str(visual_data.get("asset", ""))
	_visual_asset_anim = str(visual_data.get("asset_anim", ""))
	_visual_asset_anim_duration = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	_visual_asset_anim_loop = bool(visual_data.get("asset_anim_loop", true))
	_visual_size = maxf(20.0, float(visual_data.get("size", aura_radius * 2.0)))
	_update_shape()
	_update_visuals()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Enemy layer

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = aura_radius
	col.shape = shape
	add_child(col)

	_update_visuals()

func _update_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			var circle := child.shape as CircleShape2D
			circle.radius = aura_radius

func _update_visuals() -> void:
	var old := get_node_or_null("AuraVisual")
	if old:
		old.queue_free()

	var visual := Node2D.new()
	visual.name = "AuraVisual"
	visual.z_index = -8
	add_child(visual)

	if _try_add_animated_visual(
		visual,
		_visual_asset_anim,
		_visual_size,
		Color(0.75, 0.9, 1.0, 0.55),
		_visual_asset_anim_duration,
		_visual_asset_anim_loop
	):
		return
	if _try_add_static_visual(visual, _visual_asset, _visual_size, Color(0.75, 0.9, 1.0, 0.5)):
		return

	var ring := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * aura_radius)
	ring.polygon = points
	ring.color = Color(0.5, 0.85, 1.0, 0.15)
	visual.add_child(ring)

func _process(delta: float) -> void:
	var player := get_parent()
	if player and player is CharacterBody2D:
		global_position = player.global_position

	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_chill_aura()

func _apply_chill_aura() -> void:
	var overlapping := get_overlapping_bodies()
	var active_enemies: Array = []

	for body in overlapping:
		if not body.is_in_group("enemies"):
			continue
		active_enemies.append(body)
		if body.has_method("apply_status_effect"):
			var chill := StatusEffect.create_chill(slow_factor, 1)
			body.apply_status_effect(chill)

		if freeze_aura_time > 0.0 and body.has_method("set_aura_exposure_time") and body.has_method("get_aura_exposure_time"):
			var exposure: float = float(body.get_aura_exposure_time()) + TICK_INTERVAL
			body.set_aura_exposure_time(exposure)
			if exposure >= freeze_aura_time and body.has_method("apply_status_effect"):
				var freeze := StatusEffect.create_freeze(freeze_duration)
				body.apply_status_effect(freeze)

		if freeze_dot_dps > 0.0 and "is_frozen" in body and bool(body.is_frozen) and body.has_method("take_damage"):
			var dot_tick := maxi(1, int(round(freeze_dot_dps * TICK_INTERVAL)))
			body.take_damage(dot_tick)

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if active_enemies.has(enemy):
			continue
		if enemy.has_method("set_aura_exposure_time") and enemy.has_method("get_aura_exposure_time"):
			var current_exposure: float = float(enemy.get_aura_exposure_time())
			enemy.set_aura_exposure_time(maxf(0.0, current_exposure - TICK_INTERVAL))

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
