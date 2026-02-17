extends Area2D

@export var scroll_speed: float = 90.0
@export var damage: int = 15
@export var rotation_speed: float = 45.0
@export var laser_length_pct: float = 0.30
@export var duration: float = 6.0
@export var orb_width: int = 32
@export var orb_height: int = 32
@export var beam_thickness: float = 18.0
@export var ability_asset: String = ""
@export var ability_asset_duration: float = 0.0
@export var ability_asset_loop: bool = true
@export var laser_asset: String = ""
@export var laser_asset_duration: float = 0.0
@export var laser_asset_loop: bool = true
@export var contact_sfx_path: String = ""
@export var contact_cooldown_sec: float = 0.35

var _time_alive: float = 0.0
var _next_damage_time_msec: int = 0

@onready var orb_sprite: Sprite2D = $Orb
@onready var orb_collision: CollisionShape2D = $CollisionShape2D
@onready var laser_container: Node2D = $LaserContainer
@onready var laser_hitbox: Area2D = $LaserContainer/LaserHitbox
@onready var beam_sprite: Sprite2D = $LaserContainer/LaserHitbox/Beam
@onready var beam_shape: CollisionShape2D = $LaserContainer/LaserHitbox/BeamShape

func _ready() -> void:
	if not is_in_group("arcane_orbs"):
		add_to_group("arcane_orbs")
	if not body_entered.is_connected(_on_orb_body_entered):
		body_entered.connect(_on_orb_body_entered)
	if not laser_hitbox.body_entered.is_connected(_on_laser_body_entered):
		laser_hitbox.body_entered.connect(_on_laser_body_entered)
	_setup_orb_visual()
	_setup_orb_hitbox()
	_setup_laser()
	z_index = -7

func _process(delta: float) -> void:
	_time_alive += delta
	global_position.y += scroll_speed * delta
	laser_container.rotation_degrees += rotation_speed * delta
	_damage_overlapping_players()
	
	if _time_alive >= duration:
		queue_free()
		return
	
	if global_position.y > get_viewport_rect().size.y + 180.0:
		queue_free()

func _setup_orb_visual() -> void:
	var tex: Texture2D = null
	var frames: SpriteFrames = null
	if ability_asset != "" and ResourceLoader.exists(ability_asset):
		var res = load(ability_asset)
		if res is SpriteFrames:
			frames = res as SpriteFrames
		elif res is Texture2D:
			tex = res as Texture2D
	if frames != null:
		_apply_orb_frames(frames)
		return
	
	if tex == null:
		tex = _create_solid_texture(Color("#D000FF"))
	_apply_orb_texture(tex)

func _setup_orb_hitbox() -> void:
	var shape := CircleShape2D.new()
	shape.radius = maxf(4.0, float(max(orb_width, orb_height)) * 0.5)
	orb_collision.shape = shape

func _setup_laser() -> void:
	var viewport_width := get_viewport_rect().size.x
	var total_length := maxf(24.0, viewport_width * laser_length_pct)
	var thickness := maxf(4.0, beam_thickness)
	
	var rect := RectangleShape2D.new()
	rect.size = Vector2(total_length, thickness)
	beam_shape.shape = rect
	
	var tex: Texture2D = null
	var frames: SpriteFrames = null
	if laser_asset != "" and ResourceLoader.exists(laser_asset):
		var res = load(laser_asset)
		if res is SpriteFrames:
			frames = res as SpriteFrames
		elif res is Texture2D:
			tex = res as Texture2D
	if frames != null:
		_apply_beam_frames(frames, total_length, thickness)
		return
	
	if tex == null:
		tex = _create_solid_texture(Color("#A040FF"))
	_apply_beam_texture(tex, total_length, thickness)

func _on_orb_body_entered(body: Node2D) -> void:
	_try_damage_player(body)

func _on_laser_body_entered(body: Node2D) -> void:
	_try_damage_player(body)

func _try_damage_player(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_damage_time_msec:
		return
	_next_damage_time_msec = now_msec + int(contact_cooldown_sec * 1000.0)
	
	var remaining_damage := damage
	if body.has_method("absorb_damage_with_shield"):
		remaining_damage = int(body.absorb_damage_with_shield(damage, global_position))
	if remaining_damage > 0 and body.has_method("take_damage"):
		body.take_damage(remaining_damage)
	
	if contact_sfx_path != "" and ResourceLoader.exists(contact_sfx_path):
		AudioManager.play_sfx(contact_sfx_path, 0.1)

func _damage_overlapping_players() -> void:
	for body in get_overlapping_bodies():
		if body is Node2D:
			_try_damage_player(body as Node2D)
	for body in laser_hitbox.get_overlapping_bodies():
		if body is Node2D:
			_try_damage_player(body as Node2D)

func _create_solid_texture(color: Color) -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _apply_orb_texture(tex: Texture2D) -> void:
	var orb_anim: AnimatedSprite2D = get_node_or_null("OrbAnim")
	if orb_anim:
		orb_anim.visible = false
	
	orb_sprite.visible = true
	orb_sprite.texture = tex
	var used := _get_effective_used_rect(tex)
	if used.size.x > 0.0 and used.size.y > 0.0:
		orb_sprite.scale = Vector2(float(orb_width) / used.size.x, float(orb_height) / used.size.y)
		orb_sprite.offset = _get_centering_offset(tex.get_size(), used)

func _apply_orb_frames(frames: SpriteFrames) -> void:
	orb_sprite.visible = false
	
	var orb_anim: AnimatedSprite2D = get_node_or_null("OrbAnim")
	if orb_anim == null:
		orb_anim = AnimatedSprite2D.new()
		orb_anim.name = "OrbAnim"
		add_child(orb_anim)
	
	orb_anim.visible = true
	var anim_name := _get_default_anim_name(frames)
	if anim_name != "":
		var played_anim: StringName = VFXManager.play_sprite_frames(
			orb_anim,
			frames,
			StringName(anim_name),
			ability_asset_loop,
			maxf(0.0, ability_asset_duration)
		)
		if played_anim == &"":
			return
		var frame_tex: Texture2D = null
		if orb_anim.sprite_frames:
			frame_tex = orb_anim.sprite_frames.get_frame_texture(played_anim, 0)
		if frame_tex:
			var used := _get_effective_used_rect(frame_tex)
			if used.size.x > 0.0 and used.size.y > 0.0:
				orb_anim.scale = Vector2(float(orb_width) / used.size.x, float(orb_height) / used.size.y)
				orb_anim.offset = _get_centering_offset(frame_tex.get_size(), used)

func _apply_beam_texture(tex: Texture2D, total_length: float, thickness: float) -> void:
	var beam_anim: AnimatedSprite2D = laser_hitbox.get_node_or_null("BeamAnim")
	if beam_anim:
		beam_anim.visible = false
	
	beam_sprite.visible = true
	beam_sprite.texture = tex
	var used := _get_effective_used_rect(tex)
	if used.size.x > 0.0 and used.size.y > 0.0:
		beam_sprite.scale = Vector2(total_length / used.size.x, thickness / used.size.y)
		beam_sprite.offset = _get_centering_offset(tex.get_size(), used)

func _apply_beam_frames(frames: SpriteFrames, total_length: float, thickness: float) -> void:
	beam_sprite.visible = false
	
	var beam_anim: AnimatedSprite2D = laser_hitbox.get_node_or_null("BeamAnim")
	if beam_anim == null:
		beam_anim = AnimatedSprite2D.new()
		beam_anim.name = "BeamAnim"
		laser_hitbox.add_child(beam_anim)
	
	beam_anim.visible = true
	var anim_name := _get_default_anim_name(frames)
	if anim_name != "":
		var played_anim: StringName = VFXManager.play_sprite_frames(
			beam_anim,
			frames,
			StringName(anim_name),
			laser_asset_loop,
			maxf(0.0, laser_asset_duration)
		)
		if played_anim == &"":
			return
		var frame_tex: Texture2D = null
		if beam_anim.sprite_frames:
			frame_tex = beam_anim.sprite_frames.get_frame_texture(played_anim, 0)
		if frame_tex:
			var used := _get_effective_used_rect(frame_tex)
			if used.size.x > 0.0 and used.size.y > 0.0:
				beam_anim.scale = Vector2(total_length / used.size.x, thickness / used.size.y)
				beam_anim.offset = _get_centering_offset(frame_tex.get_size(), used)

func _get_default_anim_name(frames: SpriteFrames) -> String:
	if frames.has_animation("default"):
		return "default"
	var names := frames.get_animation_names()
	if names.size() > 0:
		return str(names[0])
	return ""

func _get_effective_used_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(0, 0, 0, 0)
	var full_size := Vector2(tex.get_size())
	var fallback := Rect2(Vector2.ZERO, full_size)
	var img: Image = tex.get_image()
	if img == null:
		return fallback
	var used := img.get_used_rect()
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return fallback
	return Rect2(used.position, used.size)

func _get_centering_offset(texture_size: Vector2i, used_rect: Rect2) -> Vector2:
	var texture_center := Vector2(texture_size) * 0.5
	var used_center := used_rect.position + used_rect.size * 0.5
	return texture_center - used_center
