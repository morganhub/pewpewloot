extends Area2D

## ObstacleExplosive — Obstacle qui explose au contact avec le joueur (one-shot).
## Inflige des dégâts puis disparaît. Peut être détruit par les tirs joueur si destructible.
## Supporte les shapes "rectangle" (width/height) et "circle" (radius).

signal obstacle_destroyed(obstacle: Node2D)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _anim_sprite: AnimatedSprite2D = null  # Créé dynamiquement si .tres
var _visual_node: Node2D = null  # Pointe vers sprite ou _anim_sprite selon le cas
var _aura_node: Node2D = null  # Sprite2D ou AnimatedSprite2D pour l'aura
var _health_bar: ProgressBar = null  # Barre de vie (obstacles destructibles uniquement)
var _health_bar_fill_style: StyleBoxFlat = null
var _health_bar_anchor_offset: Vector2 = Vector2.ZERO  # centre barre en local (pour garder "au-dessus" quand on tourne)
var _health_bar_half_size: Vector2 = Vector2.ZERO
var _health_bar_color_high: Color = Color.GREEN
var _health_bar_color_mid: Color = Color.YELLOW
var _health_bar_color_low: Color = Color.RED

var speed: float = 200.0
var damage: float = 25.0
var is_destructible: bool = false
var hp: float = 0.0
var max_hp: float = 0.0
var _obstacle_data: Dictionary = {}
var _viewport_height: float = 0.0
var _viewport_width: float = 0.0
var _drift_velocity: Vector2 = Vector2.ZERO
var _lifetime: float = 0.0

# Rotation (global_settings explosives)
var _rotation_enabled: bool = false
var _rotation_speed: float = 0.0

# Fluid trail
var _fluid_id: String = ""

const OFFSCREEN_MARGIN: float = 100.0  # Marge gauche/droite
const OFFSCREEN_MARGIN_BOTTOM: float = 500.0  # Trajectoire finit bien sous l'écran
const LIFETIME_TIMEOUT: float = 30.0  # Despawn de sécurité après 30 s
const STRONG_RESOURCE_CACHE_MAX: int = 256
const OBSTACLE_BLEND_MODE := CanvasItemMaterial.BLEND_MODE_MIX
static var _strong_resource_cache: Dictionary = {}  # path -> Resource
static var _first_frame_texture_cache: Dictionary = {}  # frame_key -> Texture2D

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
	
	# Aura autour des explosifs (global_settings dans obstacles.json)
	_setup_aura()
	
	# Rotation (global_settings explosives)
	var gs: Dictionary = DataManager.get_obstacles_global_settings()
	_rotation_enabled = bool(gs.get("rotation", false))
	_rotation_speed = float(gs.get("rotation_speed", 0))
	
	# Barre de vie (visible seulement après le premier coup)
	if is_destructible and max_hp > 0:
		_setup_health_bar()

func _apply_visual(target_w: float, target_h: float, data: Dictionary) -> void:
	var sprite_path: String = str(data.get("sprite_path", ""))
	var sprite_duration: float = maxf(0.0, float(data.get("sprite_duration", 0.0)))
	var sprite_loop: bool = bool(data.get("sprite_loop", true))
	
	if sprite_path == "":
		_visual_node = sprite
		_ensure_obstacle_blend_mode(sprite)
		sprite.modulate = Color(1, 1, 1, 1)
		if _anim_sprite:
			_anim_sprite.visible = false
		if sprite.texture:
			var tex_size := sprite.texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(target_w / tex_size.x, target_h / tex_size.y)
		return
	
	var res: Resource = _load_cached_resource(sprite_path)
	if res == null:
		_visual_node = sprite
		_ensure_obstacle_blend_mode(sprite)
		sprite.modulate = Color(1, 1, 1, 1)
		if _anim_sprite:
			_anim_sprite.visible = false
		return
	
	# Cas 1 : SpriteFrames (.tres animé) → AnimatedSprite2D
	if res is SpriteFrames:
		sprite.visible = false
		if _anim_sprite == null or not is_instance_valid(_anim_sprite):
			_anim_sprite = AnimatedSprite2D.new()
			_anim_sprite.name = "AnimatedSprite2D"
			add_child(_anim_sprite)
		_ensure_obstacle_blend_mode(_anim_sprite)
		_anim_sprite.modulate = Color(1, 1, 1, 1)
		_visual_node = _anim_sprite
		_anim_sprite.visible = true
		
		var played_anim: StringName = &""
		var frames_data: SpriteFrames = res as SpriteFrames
		var default_anim: StringName = VFXManager.get_first_animation_name(frames_data, &"default")
		if sprite_loop and sprite_duration <= 0.0 and default_anim != &"":
			_anim_sprite.sprite_frames = frames_data
			_anim_sprite.animation = default_anim
			_anim_sprite.speed_scale = 1.0
			_anim_sprite.frame = 0
			_anim_sprite.play(default_anim)
			played_anim = default_anim
		else:
			played_anim = VFXManager.play_sprite_frames(
				_anim_sprite,
				frames_data,
				&"default",
				sprite_loop,
				sprite_duration
			)
		
		# Scale l'animation pour couvrir target_w x target_h
		var frame_tex: Texture2D = null
		if played_anim != &"" and _anim_sprite.sprite_frames:
			frame_tex = _get_cached_first_frame_texture(_anim_sprite.sprite_frames, played_anim)
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
	_ensure_obstacle_blend_mode(sprite)
	sprite.modulate = Color(1, 1, 1, 1)
	sprite.texture = tex
	sprite.visible = true
	if _anim_sprite:
		_anim_sprite.visible = false
	sprite.region_enabled = false
	var loaded_tex_size := tex.get_size()
	if loaded_tex_size.x > 0 and loaded_tex_size.y > 0:
		sprite.scale = Vector2(target_w / loaded_tex_size.x, target_h / loaded_tex_size.y)

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
			_first_frame_texture_cache.clear()
		_strong_resource_cache[path] = resource
	return resource

func _get_cached_first_frame_texture(frames: SpriteFrames, anim_name: StringName) -> Texture2D:
	if frames == null or anim_name == &"":
		return null
	var frame_key: String = _build_frame_cache_key(frames, anim_name)
	if _first_frame_texture_cache.has(frame_key):
		var cached: Variant = _first_frame_texture_cache[frame_key]
		if cached is Texture2D:
			return cached as Texture2D

	var texture: Texture2D = frames.get_frame_texture(anim_name, 0)
	if texture != null:
		_first_frame_texture_cache[frame_key] = texture
	return texture

func _build_frame_cache_key(frames: SpriteFrames, anim_name: StringName) -> String:
	var path: String = frames.resource_path
	if path == "":
		path = "rid:" + str(frames.get_rid().get_id())
	return path + "|" + String(anim_name)

func _ensure_obstacle_blend_mode(node: CanvasItem) -> void:
	if node == null:
		return

	if node.material != null and not (node.material is CanvasItemMaterial):
		return

	var mat: CanvasItemMaterial = null
	if node.material is CanvasItemMaterial:
		mat = node.material as CanvasItemMaterial
	else:
		mat = CanvasItemMaterial.new()
		node.material = mat
	mat.blend_mode = OBSTACLE_BLEND_MODE

func _setup_drift(data: Dictionary) -> void:
	var drift_spd: float = float(data.get("_drift_speed", data.get("drift_speed", 0.0)))
	var drift_dir_name: String = str(data.get("_drift_direction", ""))
	if drift_spd > 0.0 and drift_dir_name != "" and DRIFT_DIR_VECTORS.has(drift_dir_name):
		_drift_velocity = (DRIFT_DIR_VECTORS[drift_dir_name] as Vector2) * drift_spd

func _setup_aura() -> void:
	var gs: Dictionary = DataManager.get_obstacles_global_settings()
	var asset_path: String = str(gs.get("asset", "")).strip_edges()
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return

	# Rayon (ou demi-taille) de l'obstacle généré aléatoirement
	var obstacle_radius: float = 20.0
	var shape_ref: Shape2D = collision_shape.shape
	if shape_ref is CircleShape2D:
		obstacle_radius = (shape_ref as CircleShape2D).radius
	elif shape_ref is RectangleShape2D:
		var sz: Vector2 = (shape_ref as RectangleShape2D).size
		obstacle_radius = minf(sz.x, sz.y) * 0.5

	# radius_min / radius_max = ce qu'on ajoute au radius de l'obstacle (additifs)
	var add_min: float = float(gs.get("radius_min", 0))
	var add_max: float = float(gs.get("radius_max", 10))
	var effective_radius_min: float = obstacle_radius + add_min
	var effective_radius_max: float = obstacle_radius + add_max
	if effective_radius_max < effective_radius_min:
		effective_radius_max = effective_radius_min
	effective_radius_min = maxf(1.0, effective_radius_min)
	effective_radius_max = maxf(effective_radius_min, effective_radius_max)

	var radius_expand_duration: float = maxf(0.2, float(gs.get("radius_expand_duration", 1.0)))
	var anim_duration: float = maxf(0.1, float(gs.get("anim_duration", 2.0)))

	var res: Resource = _load_cached_resource(asset_path)
	if res == null:
		return

	var base_radius: float = 32.0
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var default_anim: StringName = VFXManager.get_first_animation_name(frames, &"default")
		if default_anim != &"":
			var frame_tex: Texture2D = frames.get_frame_texture(default_anim, 0)
			if frame_tex:
				var sz := frame_tex.get_size()
				base_radius = minf(sz.x, sz.y) * 0.5
		_aura_node = AnimatedSprite2D.new()
		_aura_node.name = "Aura"
		_aura_node.z_index = -1
		add_child(_aura_node)
		move_child(_aura_node, 0)
		(_aura_node as AnimatedSprite2D).sprite_frames = frames
		(_aura_node as AnimatedSprite2D).animation = default_anim
		(_aura_node as AnimatedSprite2D).play(default_anim)
		if anim_duration > 0.0 and default_anim != &"" and frames.get_frame_count(default_anim) > 0:
			var fc: int = frames.get_frame_count(default_anim)
			var fps_anim: float = 10.0
			if frames.get_animation_speed(default_anim) > 0.0:
				fps_anim = frames.get_animation_speed(default_anim)
			var cycle_duration: float = float(fc) / fps_anim
			(_aura_node as AnimatedSprite2D).speed_scale = cycle_duration / anim_duration
	else:
		var tex: Texture2D = res as Texture2D
		if not tex:
			return
		var sz := tex.get_size()
		if sz.x > 0 and sz.y > 0:
			base_radius = minf(sz.x, sz.y) * 0.5
		_aura_node = Sprite2D.new()
		_aura_node.name = "Aura"
		_aura_node.z_index = -1
		(_aura_node as Sprite2D).texture = tex
		(_aura_node as Sprite2D).centered = true
		add_child(_aura_node)
		move_child(_aura_node, 0)

	if _aura_node == null:
		return

	_ensure_obstacle_blend_mode(_aura_node as CanvasItem)
	var scale_min: float = effective_radius_min / base_radius
	var scale_max: float = effective_radius_max / base_radius
	_aura_node.scale = Vector2(scale_min, scale_min)

	var tw := create_tween()
	tw.set_loops(0)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(_aura_node, "scale", Vector2(scale_max, scale_max), radius_expand_duration)
	tw.tween_property(_aura_node, "scale", Vector2(scale_min, scale_min), radius_expand_duration)

func _get_obstacle_health_bar_config() -> Dictionary:
	var gameplay: Variant = DataManager.get_game_data().get("gameplay", {})
	if not gameplay is Dictionary:
		return {}
	var bar_cfg: Variant = (gameplay as Dictionary).get("enemy_health_bar", {})
	if bar_cfg is Dictionary:
		return (bar_cfg as Dictionary).duplicate(true)
	return {}

func _parse_color_or_default(color_value: String, fallback: Color) -> Color:
	if color_value == "":
		return fallback
	if Color.html_is_valid(color_value):
		return Color.html(color_value)
	return fallback

func _setup_health_bar() -> void:
	var cfg: Dictionary = _get_obstacle_health_bar_config()
	var bar_width: float = maxf(1.0, float(cfg.get("width", 44)))
	var bar_height: float = maxf(1.0, float(cfg.get("height", 8)))
	var offset_x: float = float(cfg.get("offset_x", -bar_width * 0.5))
	var offset_y: float = float(cfg.get("offset_y", -32))

	_health_bar = ProgressBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.max_value = max_hp
	_health_bar.value = hp
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(bar_width, bar_height)
	_health_bar.size = Vector2(bar_width, bar_height)
	_health_bar.position = Vector2(offset_x, offset_y)
	_health_bar.visible = false
	_health_bar_anchor_offset = Vector2(0, offset_y + bar_height * 0.5)
	_health_bar_half_size = Vector2(bar_width * 0.5, bar_height * 0.5)

	var outline_px: int = maxi(0, int(cfg.get("outline_px", 1)))
	var outline_color: Color = _parse_color_or_default(str(cfg.get("outline_color", "#000000")), Color.BLACK)
	var bg_color: Color = _parse_color_or_default(str(cfg.get("background_color", "#66000000")), Color(0.2, 0, 0, 0.2))
	var corner_radius: int = maxi(0, int(cfg.get("corner_radius", 1)))

	_health_bar_color_high = _parse_color_or_default(str(cfg.get("color_high", "#1CFF00")), Color.GREEN)
	_health_bar_color_mid = _parse_color_or_default(str(cfg.get("color_mid", "#FFE100")), Color.YELLOW)
	_health_bar_color_low = _parse_color_or_default(str(cfg.get("color_low", "#FF3D3D")), Color.RED)

	_health_bar_fill_style = StyleBoxFlat.new()
	_health_bar_fill_style.bg_color = _health_bar_color_high
	_health_bar_fill_style.border_color = outline_color
	_health_bar_fill_style.set_border_width_all(outline_px)
	_health_bar_fill_style.set_corner_radius_all(corner_radius)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.border_color = outline_color
	bg_style.set_border_width_all(outline_px)
	bg_style.set_corner_radius_all(corner_radius)

	_health_bar.add_theme_stylebox_override("fill", _health_bar_fill_style)
	_health_bar.add_theme_stylebox_override("background", bg_style)
	add_child(_health_bar)

func _update_obstacle_health_bar_color() -> void:
	if _health_bar == null:
		return
	var hp_percent: float = (hp / max_hp) if max_hp > 0 else 1.0
	var target_color: Color = _health_bar_color_low
	if hp_percent > 0.75:
		target_color = _health_bar_color_high
	elif hp_percent > 0.33:
		target_color = _health_bar_color_mid
	if _health_bar_fill_style:
		_health_bar_fill_style.bg_color = target_color

func _ready() -> void:
	var vp_size := get_viewport_rect().size
	_viewport_height = vp_size.y
	_viewport_width = vp_size.x
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= LIFETIME_TIMEOUT:
		queue_free()
		return
	position.y += speed * delta
	position += _drift_velocity * delta
	if _rotation_enabled and _rotation_speed != 0.0:
		rotation += deg_to_rad(_rotation_speed) * delta
	if _health_bar:
		_health_bar.rotation = -rotation
		_health_bar.position = _health_bar_anchor_offset.rotated(-rotation) - _health_bar_half_size
	if _fluid_id != "":
		FluidManager.emit_fluid(global_position, _fluid_id, _drift_velocity)
	
	# Nettoyage hors écran (bas, gauche, droite)
	if global_position.y > _viewport_height + OFFSCREEN_MARGIN_BOTTOM:
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
	if _health_bar:
		_health_bar.visible = true
		_health_bar.value = hp
		_update_obstacle_health_bar_color()
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
