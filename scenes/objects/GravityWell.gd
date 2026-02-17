extends Area2D

@export var ability_asset: String = ""
@export var ability_asset_duration: float = 0.0
@export var ability_asset_loop: bool = true
@export var orb_width: int = 64
@export var orb_height: int = 64
@export var effect_radius: float = 250.0
@export var pull_strength: float = 400.0
@export var duration: float = 5.0
@export var speed: float = 70.0
@export var lateral_ratio: float = 0.65

var _life_time: float = 0.0
var _velocity: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	if not is_in_group("gravity_wells"):
		add_to_group("gravity_wells")
	_apply_visual()
	_apply_hitbox()
	_init_movement()
	z_index = -6

func setup(config: Dictionary) -> void:
	var visuals: Dictionary = config.get("visuals", {})
	var ability_cfg: Dictionary = config.get("ability_config", {})
	
	# Allow both nested and flat config payloads.
	if visuals.is_empty():
		visuals = config
	if ability_cfg.is_empty():
		ability_cfg = config
	
	ability_asset = str(visuals.get("ability_asset", ability_asset))
	ability_asset_duration = maxf(0.0, float(visuals.get("ability_asset_duration", ability_asset_duration)))
	ability_asset_loop = bool(visuals.get("ability_asset_loop", ability_asset_loop))
	orb_width = int(visuals.get("width", orb_width))
	orb_height = int(visuals.get("height", orb_height))
	effect_radius = float(visuals.get("effect_radius", effect_radius))
	
	pull_strength = float(ability_cfg.get("pull_strength", pull_strength))
	duration = float(ability_cfg.get("duration", duration))
	speed = float(ability_cfg.get("speed", speed))
	if ability_cfg.has("scroll_speed"):
		speed = float(ability_cfg.get("scroll_speed", speed))
	
	_apply_visual()
	_apply_hitbox()
	_init_movement()

func _physics_process(delta: float) -> void:
	_life_time += delta
	global_position += _velocity * delta
	_apply_horizontal_bounce()
	
	if _life_time >= duration:
		queue_free()
		return
	
	# Hard despawn as soon as the well center exits bottom screen bound.
	# Prevents pulling the player toward an off-screen point.
	if global_position.y > get_viewport_rect().size.y:
		queue_free()
		return
	
	_pull_players(delta)

func _pull_players(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	for player_node in players:
		if not (player_node is CharacterBody2D):
			continue
		var player := player_node as CharacterBody2D
		
		var to_center := global_position - player.global_position
		var distance := to_center.length()
		if distance <= 0.0001 or distance > effect_radius:
			continue
		
		var direction := to_center / distance
		var radius := maxf(effect_radius, 1.0)
		var falloff := clampf(1.0 - (distance / radius), 0.15, 1.0)
		# Apply instant pull (no persistent velocity imprint after despawn).
		var pull_step := minf(pull_strength * falloff * delta, distance)
		var pull_offset := direction * pull_step
		if player.has_method("apply_external_displacement"):
			player.call("apply_external_displacement", pull_offset)
		else:
			player.global_position += pull_offset

func _apply_visual() -> void:
	if ability_asset != "" and ResourceLoader.exists(ability_asset):
		var res = load(ability_asset)
		if res is SpriteFrames:
			_apply_animated_visual(res as SpriteFrames)
			return
		if res is Texture2D:
			_apply_static_visual(res as Texture2D)
			return
	
	_apply_static_visual(_create_fallback_texture(Color("#220033")))

func _apply_hitbox() -> void:
	var shape := CircleShape2D.new()
	shape.radius = maxf(8.0, effect_radius)
	collision_shape.shape = shape

func _init_movement() -> void:
	var dir_x := -1.0 if randf() < 0.5 else 1.0
	var vertical_speed := maxf(10.0, absf(speed))
	var horizontal_speed := vertical_speed * clampf(lateral_ratio, 0.1, 2.0)
	_velocity = Vector2(horizontal_speed * dir_x, vertical_speed)

func _apply_horizontal_bounce() -> void:
	var viewport_width := get_viewport_rect().size.x
	var visual_radius := maxf(4.0, float(max(orb_width, orb_height)) * 0.5)
	var left_bound := visual_radius
	var right_bound := viewport_width - visual_radius
	
	if global_position.x <= left_bound and _velocity.x < 0.0:
		global_position.x = left_bound
		_velocity.x = absf(_velocity.x)
	elif global_position.x >= right_bound and _velocity.x > 0.0:
		global_position.x = right_bound
		_velocity.x = -absf(_velocity.x)
	
	# Keep a downward trajectory after bounce.
	_velocity.y = absf(_velocity.y)

func _create_fallback_texture(color: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _apply_static_visual(tex: Texture2D) -> void:
	var anim_sprite := get_node_or_null("AnimatedSprite2D")
	if anim_sprite:
		anim_sprite.visible = false
	
	sprite.visible = true
	sprite.texture = tex
	var tex_size := tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sprite.scale = Vector2(float(orb_width) / tex_size.x, float(orb_height) / tex_size.y)

func _apply_animated_visual(frames: SpriteFrames) -> void:
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite == null:
		anim_sprite = AnimatedSprite2D.new()
		anim_sprite.name = "AnimatedSprite2D"
		add_child(anim_sprite)
	
	anim_sprite.visible = true
	anim_sprite.position = Vector2.ZERO
	anim_sprite.centered = true
	anim_sprite.sprite_frames = frames
	
	var anim_name := "default"
	if not frames.has_animation(anim_name):
		var names := frames.get_animation_names()
		if names.size() > 0:
			anim_name = str(names[0])
	
	if frames.has_animation(anim_name):
		var played_anim: StringName = VFXManager.play_sprite_frames(
			anim_sprite,
			frames,
			StringName(anim_name),
			ability_asset_loop,
			maxf(0.0, ability_asset_duration)
		)
		if played_anim == &"":
			return
		var frame_tex: Texture2D = null
		if anim_sprite.sprite_frames:
			frame_tex = anim_sprite.sprite_frames.get_frame_texture(played_anim, 0)
		if frame_tex:
			var f_size := frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				anim_sprite.scale = Vector2(float(orb_width) / f_size.x, float(orb_height) / f_size.y)
	
	sprite.visible = false
