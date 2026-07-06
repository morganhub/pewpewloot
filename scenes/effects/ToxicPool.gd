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
var _visual_opacity: float = 0.7
var _pool_fluid_id: String = ""
var _fluid_pool_handle: int = -1
var _affects_enemies: bool = true
var _affects_player: bool = false
var _apply_poison_to_enemies: bool = true
var _fade_tween: Tween = null
const TICK_INTERVAL: float = 0.5
const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {} # path -> Resource
static var _visible_size_cache: Dictionary = {} # texture key -> visible max dimension

func setup(radius: float, duration: float, dps: float, visual_data: Dictionary = {}, behavior: Dictionary = {}) -> void:
	pool_radius = radius
	pool_duration = duration
	pool_dps = dps
	_visual_asset = str(visual_data.get("asset", ""))
	_visual_asset_anim = str(visual_data.get("asset_anim", ""))
	_visual_asset_anim_duration = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	_visual_asset_anim_loop = bool(visual_data.get("asset_anim_loop", true))
	_visual_size = maxf(20.0, float(visual_data.get("size", pool_radius * 2.0)))
	_visual_opacity = clampf(float(visual_data.get("opacity", _visual_opacity)), 0.0, 1.0)
	_pool_fluid_id = str(visual_data.get("pool_fluid_id", ""))
	_affects_enemies = bool(behavior.get("affects_enemies", true))
	_affects_player = bool(behavior.get("affects_player", false))
	_apply_poison_to_enemies = bool(behavior.get("apply_poison_to_enemies", true))
	_update_collision_mask()
	_update_visuals()
	_update_shape()
	# Démarrer le fluid pool si un preset est défini
	if _pool_fluid_id != "" and FluidManager.is_active():
		_fluid_pool_handle = FluidManager.start_pool(global_position, _pool_fluid_id, pool_radius, pool_duration)
	if is_inside_tree():
		_set_fade_target(_visual_opacity, 0.12)

func _ready() -> void:
	collision_layer = 0
	_update_collision_mask()

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = pool_radius
	col.shape = shape
	add_child(col)

	_update_visuals()

	modulate.a = 0.0
	_set_fade_target(_visual_opacity, 0.12)

func _set_fade_target(target_alpha: float, duration: float) -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(
		self,
		"modulate:a",
		clampf(target_alpha, 0.0, 1.0),
		maxf(0.01, duration)
	)

func _update_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			var circle := child.shape as CircleShape2D
			circle.radius = pool_radius

func _update_collision_mask() -> void:
	collision_mask = 0
	if _affects_enemies:
		collision_mask |= 4 # Enemy layer
	if _affects_player:
		collision_mask |= 2 # Player layer

func _update_visuals() -> void:
	# Si un fluid pool est actif, pas besoin de visuel .tres
	if _pool_fluid_id != "":
		return

	var old := get_node_or_null("PoolVisual")
	if old:
		old.queue_free()

	var visual := Node2D.new()
	visual.name = "PoolVisual"
	visual.z_index = -6
	add_child(visual)

	# pool_visual.size in JSON is the circle radius; scale sprite to diameter so it fits inside the circle
	var target_diameter: float = _visual_size * 2.0
	if _try_add_animated_visual(
		visual,
		_visual_asset_anim,
		target_diameter,
		Color.WHITE,
		_visual_asset_anim_duration,
		_visual_asset_anim_loop
	):
		return
	if _try_add_static_visual(visual, _visual_asset, target_diameter, Color.WHITE):
		return

	var ring := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * pool_radius)
	ring.polygon = points
	ring.color = Color(0.2, 0.9, 0.1, 1.0)
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
		if _affects_enemies and body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(tick_damage)
		if _affects_enemies and _apply_poison_to_enemies and body.has_method("apply_status_effect"):
			var poison := StatusEffect.create_poison(float(tick_damage) * 2.0, 2.0)
			body.apply_status_effect(poison)
		if _affects_player and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(tick_damage)

func _fade_and_die() -> void:
	# Arrêter le fluid pool si actif
	if _fluid_pool_handle >= 0:
		FluidManager.stop_pool(_fluid_pool_handle)
		_fluid_pool_handle = -1
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.15)
	_fade_tween.tween_callback(queue_free)

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
		var reference_size: float = _get_texture_visible_max_dimension(frame_tex)
		if reference_size > 0.0:
			var scale_factor: float = target_size / reference_size
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

	var reference_size: float = _get_texture_visible_max_dimension(texture)
	if reference_size > 0.0:
		var scale_factor: float = target_size / reference_size
		sprite.scale = Vector2.ONE * scale_factor
	return true

func _get_texture_visible_max_dimension(texture: Texture2D) -> float:
	if texture == null:
		return 0.0
	var texture_size: Vector2 = texture.get_size()
	var fallback_max_dim: float = maxf(texture_size.x, texture_size.y)
	if fallback_max_dim <= 0.0:
		return 0.0

	var cache_key: String = _get_texture_cache_key(texture)
	if _visible_size_cache.has(cache_key):
		return float(_visible_size_cache.get(cache_key, fallback_max_dim))

	var visible_max_dim: float = fallback_max_dim
	var image: Image = texture.get_image()
	if image != null and not image.is_empty():
		var width: int = image.get_width()
		var height: int = image.get_height()
		if width > 0 and height > 0:
			var min_x: int = width
			var min_y: int = height
			var max_x: int = -1
			var max_y: int = -1
			for y in range(height):
				for x in range(width):
					if image.get_pixel(x, y).a <= 0.0:
						continue
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
			if max_x >= 0 and max_y >= 0:
				var visible_w: int = max_x - min_x + 1
				var visible_h: int = max_y - min_y + 1
				visible_max_dim = float(maxi(1, maxi(visible_w, visible_h)))

	_visible_size_cache[cache_key] = visible_max_dim
	return visible_max_dim

func _get_texture_cache_key(texture: Texture2D) -> String:
	var path: String = texture.resource_path.strip_edges()
	if path != "":
		return path
	return "instance:%s" % str(texture)

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
