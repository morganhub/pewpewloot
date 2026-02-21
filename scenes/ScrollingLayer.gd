extends Node2D

## ScrollingLayer
## Gère le défilement infini d'une texture (ou d'un groupe d'objets)
## Correspond à une "couche" de background.

var _speed: float = 0.0
var _tile_height: float = 0.0
var _tile_step: float = 0.0
var _scroll_offset: float = 0.0
var _add_material: CanvasItemMaterial = null
var _tiles: Array[Node2D] = []
var _viewport_size: Vector2 = Vector2.ZERO
var _region_sprite: Sprite2D = null
var _use_region_scroll: bool = false

const REGION_SCROLL_EXTRA_HEIGHT_PX: float = 2.0

func setup(resource: Resource, scroll_speed: float, viewport_size: Vector2, use_add_blend: bool = false) -> void:
	_speed = scroll_speed
	_tile_height = 0.0
	_tile_step = 0.0
	_scroll_offset = 0.0
	_viewport_size = viewport_size
	_region_sprite = null
	_use_region_scroll = false
	_clear_children()
	_tiles.clear()

	if use_add_blend:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	else:
		_add_material = null

	if resource == null:
		return

	if resource is Texture2D:
		_setup_texture_layer(resource as Texture2D, viewport_size)
		return

	if resource is SpriteFrames:
		_setup_sprite_frames_layer(resource as SpriteFrames, viewport_size)
		return

	push_warning("[ScrollingLayer] Unsupported background resource type: " + str(resource.get_class()))

func _setup_texture_layer(texture: Texture2D, viewport_size: Vector2) -> void:
	if texture == null:
		return

	var texture_size: Vector2 = texture.get_size()
	_tile_height = texture_size.y
	if _tile_height <= 0.0:
		push_warning("[ScrollingLayer] Texture height is invalid.")
		return

	# Texture2D backgrounds use a single repeated region sprite.
	# This removes tile joins (seams/overlaps) entirely.
	_tile_step = maxf(1.0, _tile_height)
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.position = Vector2.ZERO
	s.region_enabled = true
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if _add_material != null:
		s.material = _add_material
	add_child(s)
	_region_sprite = s
	_use_region_scroll = true

	position = Vector2.ZERO
	_apply_region_scroll()

func _setup_sprite_frames_layer(frames: SpriteFrames, viewport_size: Vector2) -> void:
	if frames == null:
		return

	var anim_names: PackedStringArray = frames.get_animation_names()
	if anim_names.is_empty():
		push_warning("[ScrollingLayer] SpriteFrames has no animation.")
		return

	var anim: StringName = StringName(anim_names[0])
	var frame_count: int = frames.get_frame_count(anim)
	if frame_count <= 0:
		push_warning("[ScrollingLayer] SpriteFrames animation has no frame.")
		return

	var first_frame: Texture2D = frames.get_frame_texture(anim, 0)
	if first_frame == null:
		push_warning("[ScrollingLayer] SpriteFrames first frame is invalid.")
		return

	_tile_height = first_frame.get_size().y
	if _tile_height <= 0.0:
		push_warning("[ScrollingLayer] SpriteFrames frame height is invalid.")
		return

	_tile_step = maxf(1.0, _tile_height)
	var tile_count: int = maxi(3, int(ceil((viewport_size.y + _tile_height * 2.0) / _tile_step)))
	for i in range(tile_count):
		var s := AnimatedSprite2D.new()
		s.sprite_frames = frames
		s.animation = anim
		s.centered = false
		if _add_material != null:
			s.material = _add_material
		add_child(s)
		_tiles.append(s)
		s.play()

	position = Vector2.ZERO
	_apply_tiled_scroll_positions()

func _clear_children() -> void:
	for child in get_children():
		child.queue_free()

func _process(delta: float) -> void:
	if _tile_height <= 0.0 or _tile_step <= 0.0:
		return
	var current_viewport_size: Vector2 = get_viewport_rect().size
	if current_viewport_size != _viewport_size:
		_viewport_size = current_viewport_size
	if not is_zero_approx(_speed):
		_scroll_offset = fposmod(_scroll_offset + (_speed * delta), _tile_step)

	if _use_region_scroll:
		_apply_region_scroll()
	else:
		_apply_tiled_scroll_positions()

func _apply_region_scroll() -> void:
	if _region_sprite == null or not is_instance_valid(_region_sprite):
		return
	var width: float = maxf(1.0, _viewport_size.x)
	var height: float = maxf(1.0, _viewport_size.y + REGION_SCROLL_EXTRA_HEIGHT_PX)
	# In region-scroll mode, sampling source Y has inverted visual direction.
	# Keep positive speed = downward visual movement to match tiled layers.
	var sample_y: float = fposmod(-_scroll_offset, _tile_step)
	_region_sprite.region_rect = Rect2(0.0, sample_y, width, height)

func _apply_tiled_scroll_positions() -> void:
	if _tiles.is_empty():
		return

	for i in range(_tiles.size()):
		var tile := _tiles[i]
		if tile == null or not is_instance_valid(tile):
			continue
		tile.position = Vector2(0.0, -_tile_height + float(i) * _tile_step + _scroll_offset)
