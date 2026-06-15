extends Area2D

signal collected(crystal_data: Dictionary)
signal expired

var crystal_data: Dictionary = {}
var despawn_time_sec: float = 8.0
var pickup_radius: float = 28.0
var magnet_speed: float = 420.0
var size_px: float = 28.0
var _time_left: float = 0.0
var _base_fall_speed: float = 420.0
var _float_amplitude: float = 6.0
var _float_freq: float = 4.0
var _age: float = 0.0
var _player: Node2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var animated: AnimatedSprite2D = $AnimatedSprite2D

func setup(data: Dictionary, player_ref: Node2D) -> void:
	crystal_data = data.duplicate(true)
	_player = player_ref
	despawn_time_sec = maxf(0.1, float(crystal_data.get("despawn_time_sec", 8.0)))
	pickup_radius = maxf(8.0, float(crystal_data.get("pickup_radius", 28.0)))
	magnet_speed = maxf(10.0, float(crystal_data.get("magnet_speed", 420.0)))
	size_px = maxf(8.0, float(crystal_data.get("size_px", 28.0)))
	_base_fall_speed = maxf(40.0, float(crystal_data.get("fall_speed_px_sec", 420.0)))
	_time_left = despawn_time_sec
	_age = 0.0
	_apply_visual()
	LootDropHighlightSetup.setup_for_parent(self, size_px, size_px)

func _apply_visual() -> void:
	if sprite:
		sprite.visible = false
	if animated:
		animated.visible = false

	var asset_path: String = str(crystal_data.get("asset", "")).strip_edges()
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var res: Resource = load(asset_path)
	if res is SpriteFrames and animated:
		animated.sprite_frames = res as SpriteFrames
		var default_anim: StringName = &"default"
		if animated.sprite_frames.has_animation(default_anim):
			animated.play(default_anim)
		else:
			var names: PackedStringArray = animated.sprite_frames.get_animation_names()
			if names.size() > 0:
				animated.play(names[0])
		_apply_node_size(animated, _get_animated_frame_size(animated.sprite_frames))
		animated.visible = true
		return
	if res is Texture2D and sprite:
		sprite.texture = res as Texture2D
		_apply_node_size(sprite, (res as Texture2D).get_size())
		sprite.visible = true

func _apply_node_size(node: Node2D, tex_size: Vector2) -> void:
	if node == null:
		return
	var max_dim: float = maxf(tex_size.x, tex_size.y)
	if max_dim <= 0.0:
		return
	var scale_factor: float = size_px / max_dim
	node.scale = Vector2.ONE * scale_factor

func _get_animated_frame_size(frames: SpriteFrames) -> Vector2:
	if frames == null:
		return Vector2.ZERO
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() <= 0:
			return Vector2.ZERO
		anim_name = StringName(names[0])
	if frames.get_frame_count(anim_name) <= 0:
		return Vector2.ZERO
	var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
	if frame_tex == null:
		return Vector2.ZERO
	return frame_tex.get_size()

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		expired.emit()
		queue_free()
		return

	_age += delta
	var wave_offset: float = sin(_age * _float_freq) * _float_amplitude
	global_position.y += _base_fall_speed * delta
	global_position.x += wave_offset * delta

	if _player and is_instance_valid(_player):
		var dist: float = global_position.distance_to(_player.global_position)
		if dist <= pickup_radius:
			collected.emit(crystal_data)
			queue_free()
			return
		var to_player: Vector2 = (_player.global_position - global_position)
		if dist <= pickup_radius * 6.0 and to_player != Vector2.ZERO:
			global_position += to_player.normalized() * magnet_speed * delta
