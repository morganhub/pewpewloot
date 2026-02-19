extends Area2D

## ObstacleExplosive — Obstacle qui explose au contact avec le joueur (one-shot).
## Inflige des dégâts puis disparaît. Peut être détruit par les tirs joueur si destructible.
## Supporte les shapes "rectangle" (width/height) et "circle" (radius).

signal obstacle_destroyed(obstacle: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _anim_sprite: AnimatedSprite2D = null  # Créé dynamiquement si .tres
var _visual_node: Node2D = null  # Pointe vers sprite ou _anim_sprite selon le cas

var speed: float = 200.0
var damage: float = 25.0
var is_destructible: bool = false
var hp: float = 0.0
var max_hp: float = 0.0
var _obstacle_data: Dictionary = {}
var _viewport_height: float = 0.0
var _viewport_width: float = 0.0
var _drift_velocity: Vector2 = Vector2.ZERO

# Fluid trail
var _fluid_id: String = ""

const OFFSCREEN_MARGIN: float = 100.0

# Directions de drift (normalisées)
const DRIFT_DIR_VECTORS: Dictionary = {
	"N":  Vector2(0, -1),
	"NE": Vector2(0.7071, -0.7071),
	"E":  Vector2(1, 0),
	"SE": Vector2(0.7071, 0.7071),
	"S":  Vector2(0, 1),
	"SW": Vector2(-0.7071, 0.7071),
	"W":  Vector2(-1, 0),
	"NW": Vector2(-0.7071, -0.7071)
}

func setup(data: Dictionary, scroll_speed: float) -> void:
	_obstacle_data = data
	speed = scroll_speed
	damage = float(data.get("damage", 25))
	is_destructible = bool(data.get("is_destructible", false))
	hp = float(data.get("hp", 0))
	max_hp = hp
	_fluid_id = str(data.get("fluid_id", ""))
	
	var shape_type: String = str(data.get("shape", "rectangle"))
	
	# Déterminer les dimensions selon le type de shape
	var target_width: float
	var target_height: float
	if shape_type == "circle":
		var radius: float = float(data.get("radius", 20))
		target_width = radius * 2.0
		target_height = radius * 2.0
		# Remplacer la shape par un CircleShape2D
		var circle_shape := CircleShape2D.new()
		circle_shape.radius = radius
		collision_shape.shape = circle_shape
	else:
		target_width = float(data.get("width", 40))
		target_height = float(data.get("height", 40))
		# RectangleShape2D
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(target_width, target_height)
		collision_shape.shape = rect_shape
	
	# Charger le visuel (sprite statique ou animé .tres)
	_apply_visual(target_width, target_height, data)
	
	# Groupes
	add_to_group("obstacles")
	if is_destructible:
		add_to_group("destructible_obstacles")
	
	# Collision setup : Layer 32 (layer 6), détecte le joueur (layer 2)
	collision_layer = 32
	collision_mask = 2
	monitoring = true
	monitorable = true
	
	# Drift
	_setup_drift(data)

func _apply_visual(target_w: float, target_h: float, data: Dictionary) -> void:
	var sprite_path: String = str(data.get("sprite_path", ""))
	var sprite_duration: float = maxf(0.0, float(data.get("sprite_duration", 0.0)))
	var sprite_loop: bool = bool(data.get("sprite_loop", true))
	
	if sprite_path == "" or not ResourceLoader.exists(sprite_path):
		_visual_node = sprite
		if sprite.texture:
			var tex_size := sprite.texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(target_w / tex_size.x, target_h / tex_size.y)
		return
	
	var res: Resource = load(sprite_path)
	
	# Cas 1 : SpriteFrames (.tres animé) → AnimatedSprite2D
	if res is SpriteFrames:
		sprite.visible = false
		_anim_sprite = AnimatedSprite2D.new()
		_anim_sprite.name = "AnimatedSprite2D"
		add_child(_anim_sprite)
		_visual_node = _anim_sprite
		
		var played_anim: StringName = VFXManager.play_sprite_frames(
			_anim_sprite,
			res as SpriteFrames,
			&"default",
			sprite_loop,
			sprite_duration
		)
		
		# Scale l'animation pour couvrir target_w x target_h
		var frame_tex: Texture2D = null
		if played_anim != &"" and _anim_sprite.sprite_frames:
			frame_tex = _anim_sprite.sprite_frames.get_frame_texture(played_anim, 0)
		if frame_tex:
			var f_size := frame_tex.get_size()
			if f_size.x > 0 and f_size.y > 0:
				_anim_sprite.scale = Vector2(target_w / f_size.x, target_h / f_size.y)
		return
	
	# Cas 2 : Texture2D statique (.png, .jpg…)
	var tex := res as Texture2D
	if not tex:
		_visual_node = sprite
		return
	
	_visual_node = sprite
	sprite.texture = tex
	sprite.region_enabled = false
	var loaded_tex_size := tex.get_size()
	if loaded_tex_size.x > 0 and loaded_tex_size.y > 0:
		sprite.scale = Vector2(target_w / loaded_tex_size.x, target_h / loaded_tex_size.y)

func _setup_drift(data: Dictionary) -> void:
	var drift_spd: float = float(data.get("_drift_speed", data.get("drift_speed", 0.0)))
	var drift_dir_name: String = str(data.get("_drift_direction", ""))
	if drift_spd > 0.0 and drift_dir_name != "" and DRIFT_DIR_VECTORS.has(drift_dir_name):
		_drift_velocity = (DRIFT_DIR_VECTORS[drift_dir_name] as Vector2) * drift_spd

func _ready() -> void:
	var vp_size := get_viewport_rect().size
	_viewport_height = vp_size.y
	_viewport_width = vp_size.x
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position.y += speed * delta
	position += _drift_velocity * delta
	if _fluid_id != "":
		FluidManager.emit_fluid(global_position, _fluid_id, _drift_velocity)
	
	# Nettoyage hors écran (bas, gauche, droite)
	if global_position.y > _viewport_height + OFFSCREEN_MARGIN:
		queue_free()
	elif global_position.x < -OFFSCREEN_MARGIN or global_position.x > _viewport_width + OFFSCREEN_MARGIN:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Infliger des dégâts au joueur
		if body.has_method("take_damage"):
			body.take_damage(damage)
		
		# VFX explosion (petit flash)
		_play_explosion()
		
		# One-shot : disparaît après contact
		queue_free()

func take_damage(amount: float, _is_critical: bool = false) -> void:
	if not is_destructible:
		return
	
	hp -= amount
	# Feedback visuel : flash blanc
	_flash_damage()
	
	if hp <= 0:
		die()

func die() -> void:
	_play_explosion()
	obstacle_destroyed.emit(self)
	queue_free()

func _play_explosion() -> void:
	# Utilise VFXManager si disponible
	if Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if tree.root.has_node("VFXManager"):
			var size := float(_obstacle_data.get("radius", _obstacle_data.get("width", 40)))
			VFXManager.spawn_explosion(
				global_position,
				size,
				Color("#FF6600"),
				get_parent(),
				"", "", -1.0, 0.3, 0.0, false
			)

func _flash_damage() -> void:
	var target: Node2D = _visual_node if _visual_node else sprite
	if target:
		target.modulate = Color.WHITE * 3.0
		var tween := create_tween()
		tween.tween_property(target, "modulate", Color.WHITE, 0.15)
