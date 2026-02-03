extends Area2D

## Projectile — Bullet/missile générique pour joueur et ennemis.
## Utilise les patterns de missile_patterns.json.

# =============================================================================
# SIGNALS
# =============================================================================

signal projectile_deactivated(projectile: Area2D)

# =============================================================================
# PROPERTIES
# =============================================================================

var is_player_projectile: bool = true
var direction: Vector2 = Vector2.UP
var speed: float = 300.0
var damage: int = 10
var is_active: bool = false

# Pattern data (optionnel)
var _pattern_data: Dictionary = {}
var _trajectory_type: String = "straight"
var _time_alive: float = 0.0
var _max_lifetime: float = 5.0
var is_critical: bool = false

# Visual
@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D

# TODO: Remplacer Polygon2D par Sprite2D quand les assets seront disponibles
# @onready var sprite: Sprite2D = $Sprite2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	deactivate()

func activate(pos: Vector2, dir: Vector2, spd: float, dmg: int, pattern_data: Dictionary = {}, is_crit: bool = false) -> void:
	global_position = pos
	direction = dir.normalized()
	speed = spd
	damage = dmg
	_pattern_data = pattern_data
	_time_alive = 0.0
	is_active = true
	is_critical = is_crit
	
	# Setup Collision Layer/Mask Dynamically
	if is_player_projectile:
		# Layer: PlayerProjectile (8)
		collision_layer = 8
		# Mask: Enemy (4) + World (1)
		collision_mask = 4 + 1
	else:
		# Layer: EnemyProjectile (16)
		collision_layer = 16
		# Mask: Player (2) + World (1)
		collision_mask = 2 + 1

	# Appliquer le pattern
	_trajectory_type = str(pattern_data.get("trajectory", "straight"))
	
	# Visuel Data
	# On s'attend à recevoir soit data complète, soit on fallback sur le pattern_data (legacy)
	var visual_data: Dictionary = pattern_data.get("visual_data", {})
	if visual_data.is_empty():
		# Fallback legacy: use pattern_data as visual source
		visual_data = {
			"color": pattern_data.get("color", "#FFFF00"),
			"size": pattern_data.get("size", 8),
			"shape": "circle",
			"asset": "" 
		}

	_setup_visual(visual_data)
	
	# Rotation initiale
	rotation = direction.angle() + PI / 2
	
	show()
	set_process(true)

func _setup_visual(visual_data: Dictionary) -> void:
	var size: float = float(visual_data.get("size", 8)) * 1.5 # Scale +50%
	if is_critical:
		size *= 1.5
	
	var asset_path: String = str(visual_data.get("asset", ""))
	var use_asset: bool = false
	
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			use_asset = true
			visual.visible = false
			
			var sprite: Sprite2D = get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			# Scale
			var tex_size = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(size * 2 / tex_size.x, size * 2 / tex_size.y)
	
	if not use_asset:
		var color := Color(visual_data.get("color", "#FFFF00"))
		if is_critical: color = Color.YELLOW
		
		# Cacher sprite
		var sprite: Sprite2D = get_node_or_null("Sprite2D")
		if sprite: sprite.visible = false
		
		visual.visible = true
		visual.color = color
		visual.polygon = _create_circle_polygon(size)
	
	# Collision
	var shape := collision.shape as CircleShape2D
	if shape:
		shape.radius = size / 2.0
	
	# Rotation initiale
	rotation = direction.angle() + PI / 2
	
	show()
	set_process(true)

func deactivate() -> void:
	is_active = false
	hide()
	set_process(false)
	projectile_deactivated.emit(self)

func _process(delta: float) -> void:
	if not is_active:
		return
	
	_time_alive += delta
	
	# Lifetime check
	if _time_alive >= _max_lifetime:
		deactivate()
		return
	
	# Movement selon trajectory
	match _trajectory_type:
		"straight":
			_move_straight(delta)
		"sine_wave":
			_move_sine_wave(delta)
		"aimed":
			_move_straight(delta)  # Aimed est déjà calculé au spawn
		"spiral":
			_move_spiral(delta)
		_:
			_move_straight(delta)
	
	# Check hors écran
	var viewport_size := get_viewport_rect().size
	if global_position.x < -50 or global_position.x > viewport_size.x + 50:
		deactivate()
	if global_position.y < -50 or global_position.y > viewport_size.y + 50:
		deactivate()

# =============================================================================
# MOVEMENT PATTERNS
# =============================================================================

func _move_straight(delta: float) -> void:
	global_position += direction * speed * delta

func _move_sine_wave(delta: float) -> void:
	var amplitude: float = float(_pattern_data.get("amplitude", 50))
	var frequency: float = float(_pattern_data.get("frequency", 2.0))
	
	var base_move := direction * speed * delta
	var perpendicular := Vector2(-direction.y, direction.x)
	var wave_offset := perpendicular * sin(_time_alive * frequency * TAU) * amplitude * delta
	
	global_position += base_move + wave_offset

func _move_spiral(delta: float) -> void:
	var rotation_speed: float = float(_pattern_data.get("rotation_speed", 90))
	direction = direction.rotated(deg_to_rad(rotation_speed) * delta)
	rotation = direction.angle() + PI / 2
	global_position += direction * speed * delta

# =============================================================================
# COLLISIONS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return
	
	# Projectile joueur touche ennemi
	if is_player_projectile and body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage, is_critical)
		deactivate()
	
	# Projectile ennemi touche joueur
	elif not is_player_projectile and body.is_in_group("player"):
		# Vérifier dodge côté joueur ou ici ?
		# On laisse le joueur gérer son dodge dans take_damage ou ici ?
		# Pour l'instant on appelle take_damage standard
		if body.has_method("take_damage"):
			body.take_damage(damage)
		deactivate()

func _on_area_entered(_area: Area2D) -> void:
	# Collision avec d'autres projectiles (optionnel)
	pass

# =============================================================================
# UTILITY
# =============================================================================

func _create_circle_polygon(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 8
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
