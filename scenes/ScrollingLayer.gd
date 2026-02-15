extends Node2D

## ScrollingLayer
## Gère le défilement infini d'une texture (ou d'un groupe d'objets)
## Correspond à une "couche" de background.

var _speed: float = 0.0
var _tile_height: float = 0.0
var _offset_y: float = 0.0
var _add_material: CanvasItemMaterial = null

func setup(resource: Resource, scroll_speed: float, viewport_size: Vector2, use_add_blend: bool = false) -> void:
	_speed = scroll_speed
	_offset_y = 0.0
	_tile_height = 0.0
	_clear_children()

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

	var needed_height: float = viewport_size.y + _tile_height * 2.0
	var current_y: float = -_tile_height

	while current_y < needed_height:
		var s := Sprite2D.new()
		s.texture = texture
		s.centered = false
		s.position = Vector2(0.0, current_y)
		if _add_material != null:
			s.material = _add_material
		add_child(s)
		current_y += _tile_height

	position.y = 0.0

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

	var needed_height: float = viewport_size.y + _tile_height * 2.0
	var current_y: float = -_tile_height

	while current_y < needed_height:
		var s := AnimatedSprite2D.new()
		s.sprite_frames = frames
		s.animation = anim
		s.centered = false
		s.position = Vector2(0.0, current_y)
		if _add_material != null:
			s.material = _add_material
		add_child(s)
		s.play()
		current_y += _tile_height

	position.y = 0.0

func _clear_children() -> void:
	for child in get_children():
		child.queue_free()

func _process(delta: float) -> void:
	# Algorithme de défilement demandé :
	# offset_y += (vitesse) * delta
	# Wrap : si offset_y > hauteur alors offset_y = 0
	
	_offset_y += _speed * delta
	
	if _tile_height > 0.0:
		if _offset_y >= _tile_height:
			_offset_y -= _tile_height
		elif _offset_y <= -_tile_height:
			_offset_y += _tile_height
	
	# Appliquer le décalage localement
	position.y = _offset_y
