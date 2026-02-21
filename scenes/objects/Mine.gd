extends Area2D

@export var scroll_speed: float = 100.0
@export var lateral_speed: float = 40.0
@export var spin_speed_deg: float = 60.0
@export var damage: int = 25
@export var max_hp: int = 20
@export var mine_width: int = 40
@export var mine_height: int = 40
@export var visual_asset: String = ""
@export var visual_asset_duration: float = 0.0
@export var visual_asset_loop: bool = true
@export var contact_sfx_path: String = ""
@export var explosion_asset: String = ""
@export var explosion_asset_duration: float = 0.0
@export var explosion_asset_loop: bool = false

var current_hp: int = 20
var _exploded: bool = false
var _velocity: Vector2 = Vector2.ZERO
const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {} # path -> Resource

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	if not is_in_group("mines"):
		add_to_group("mines")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if current_hp <= 0:
		current_hp = max_hp
	_apply_visual()
	_apply_hitbox()
	_init_movement()
	z_index = -8

func _process(delta: float) -> void:
	# Keep motion slow and diagonal (down-left/down-right) with horizontal wall bounce.
	global_position += _velocity * delta
	rotation += deg_to_rad(spin_speed_deg) * delta * signf(_velocity.x)
	_apply_horizontal_bounce()
	if global_position.y > get_viewport_rect().size.y + 120.0:
		queue_free()

func take_damage(amount: int) -> void:
	if _exploded:
		return
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	if current_hp <= 0:
		_explode()

func _on_body_entered(body: Node2D) -> void:
	if _exploded:
		return
	if body.is_in_group("player"):
		var remaining_damage := damage
		if body.has_method("absorb_damage_with_shield"):
			remaining_damage = int(body.absorb_damage_with_shield(damage, global_position))
		if remaining_damage > 0 and body.has_method("take_damage"):
			body.take_damage(remaining_damage)
		_explode()

func _on_area_entered(area: Area2D) -> void:
	if _exploded:
		return
	if not area.has_method("get"):
		return
	if bool(area.get("is_player_projectile")):
		var hit_damage: int = int(area.get("damage"))
		take_damage(hit_damage)
		if area.has_method("deactivate"):
			area.deactivate("hit_mine")

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	
	if contact_sfx_path != "" and ResourceLoader.exists(contact_sfx_path):
		AudioManager.play_sfx(contact_sfx_path)
	
	var asset_path := ""
	var asset_anim := ""
	if explosion_asset != "":
		var res: Resource = _load_cached_resource(explosion_asset)
		if res is SpriteFrames:
			asset_anim = explosion_asset
		elif res is Texture2D:
			asset_path = explosion_asset
	
	var container := get_parent()
	if container:
		var fx_size: float = maxf(float(mine_width), float(mine_height)) * 0.6
		VFXManager.spawn_explosion(
			global_position,
			fx_size,
			Color("#FF8800"),
			container,
			asset_path,
			asset_anim,
			-1.0,
			0.3,
			maxf(0.0, explosion_asset_duration),
			explosion_asset_loop
		)
	
	queue_free()

func _apply_visual() -> void:
	if visual_asset != "":
		var res: Resource = _load_cached_resource(visual_asset)
		if res is SpriteFrames:
			_apply_animated_visual(res as SpriteFrames)
		elif res is Texture2D:
			_apply_static_visual(res as Texture2D)
	
	if sprite.texture:
		var tex_size := sprite.texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2(float(mine_width) / tex_size.x, float(mine_height) / tex_size.y)

func _apply_hitbox() -> void:
	var shape := CircleShape2D.new()
	shape.radius = maxf(4.0, float(mine_width) * 0.5)
	collision_shape.shape = shape

func _init_movement() -> void:
	var dir_x := -1.0 if randf() < 0.5 else 1.0
	var y_speed := maxf(10.0, absf(scroll_speed))
	var x_speed := maxf(5.0, absf(lateral_speed))
	_velocity = Vector2(x_speed * dir_x, y_speed)

func _apply_horizontal_bounce() -> void:
	var viewport_size := get_viewport_rect().size
	var radius := _get_collision_radius()
	var left_bound := radius
	var right_bound := viewport_size.x - radius
	
	if global_position.x <= left_bound and _velocity.x < 0.0:
		global_position.x = left_bound
		_velocity.x = absf(_velocity.x)
	elif global_position.x >= right_bound and _velocity.x > 0.0:
		global_position.x = right_bound
		_velocity.x = -absf(_velocity.x)
	
	# Always keep trajectory downward.
	_velocity.y = absf(_velocity.y)

func _get_collision_radius() -> float:
	if collision_shape and collision_shape.shape is CircleShape2D:
		return (collision_shape.shape as CircleShape2D).radius
	return maxf(4.0, float(mine_width) * 0.5)

func _apply_static_visual(tex: Texture2D) -> void:
	var anim_sprite := get_node_or_null("AnimatedSprite2D")
	if anim_sprite:
		anim_sprite.visible = false
	sprite.visible = true
	sprite.texture = tex

func _apply_animated_visual(frames: SpriteFrames) -> void:
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite == null:
		anim_sprite = AnimatedSprite2D.new()
		anim_sprite.name = "AnimatedSprite2D"
		add_child(anim_sprite)
	
	anim_sprite.visible = true
	var anim_name: StringName = VFXManager.play_sprite_frames(
		anim_sprite,
		frames,
		&"default",
		visual_asset_loop,
		maxf(0.0, visual_asset_duration)
	)
	if anim_name != &"" and anim_sprite.sprite_frames:
		var frame_tex: Texture2D = anim_sprite.sprite_frames.get_frame_texture(anim_name, 0)
		if frame_tex:
			var f_size := frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				anim_sprite.scale = Vector2(float(mine_width) / f_size.x, float(mine_height) / f_size.y)
	
	sprite.visible = false

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
