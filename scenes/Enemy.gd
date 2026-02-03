extends CharacterBody2D

## Enemy — Ennemi générique avec move_pattern et missile_pattern.
## Affiche une barre de vie colorée (vert/jaune/rouge).

# =============================================================================
# SIGNALS
# =============================================================================

signal enemy_died(enemy: CharacterBody2D)

# =============================================================================
# PROPERTIES
# =============================================================================

var enemy_id: String = ""
var enemy_name: String = "Enemy"
var max_hp: int = 50
var current_hp: int = 50
var score: int = 10
var loot_chance: float = 0.1

# Movement
var move_pattern_id: String = "straight_down"
var move_speed: float = 100.0
var _move_pattern_data: Dictionary = {}
var _move_time: float = 0.0

var _start_position: Vector2 = Vector2.ZERO
var _stat_multiplier: float = 1.0

# Shooting
var missile_pattern_id: String = "single_straight"
var missile_id: String = "missile_default"
var fire_rate: float = 2.0
var _fire_timer: float = 0.0
var _missile_pattern_data: Dictionary = {}

# Visual
@onready var visual_container: Node2D = $Visual
@onready var shape_visual: Polygon2D = $Visual/Shape
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision: CollisionShape2D = $CollisionShape2D

# TODO: Remplacer par Sprite2D
# @onready var sprite: Sprite2D = $Sprite2D

# =============================================================================
# SETUP
# =============================================================================

func setup(enemy_data: Dictionary, stat_multiplier: float = 1.0) -> void:
	enemy_id = str(enemy_data.get("id", "unknown"))
	enemy_name = str(enemy_data.get("name", "Enemy"))
	max_hp = int(enemy_data.get("hp", 50) * stat_multiplier)  # Scaling HP
	current_hp = max_hp
	score = int(enemy_data.get("score", 10))
	loot_chance = float(enemy_data.get("loot_chance", 0.1))
	_stat_multiplier = stat_multiplier
	
	# Movement pattern
	move_pattern_id = str(enemy_data.get("move_pattern_id", "straight_down"))
	_move_pattern_data = DataManager.get_move_pattern(move_pattern_id)
	move_speed = float(_move_pattern_data.get("speed", 100)) # Note: On pourrait scaler speed aussi ? Pour l'instant non.
	
	# Missile pattern
	missile_pattern_id = str(enemy_data.get("missile_pattern_id", "single_straight"))
	missile_id = str(enemy_data.get("missile_id", "missile_default"))
	_missile_pattern_data = DataManager.get_missile_pattern(missile_pattern_id)
	fire_rate = float(enemy_data.get("fire_rate", 2.0))
	
	# Visual setup
	_setup_visual(enemy_data)
	_setup_health_bar()
	
	_start_position = global_position
	_fire_timer = randf_range(0, fire_rate)  # Random offset

func _setup_visual(enemy_data: Dictionary) -> void:
	var size_data: Variant = enemy_data.get("size", {"width": 30, "height": 30})
	var width: float = 30.0
	var height: float = 30.0
	
	if size_data is Dictionary:
		var size_dict := size_data as Dictionary
		width = float(size_dict.get("width", 30))
		height = float(size_dict.get("height", 30))
	
	# Gestion de l'asset vs shape
	var asset_path: String = str(enemy_data.get("asset", ""))
	var use_asset: bool = false
	
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			use_asset = true
			shape_visual.visible = false
			
			# Chercher ou créer le Sprite2D
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				visual_container.add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			# Redimensionner l'image pour qu'elle corresponde à la taille définie
			var tex_size = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(width / tex_size.x, height / tex_size.y) * 1.2 # Scale +20%
	
	if not use_asset:
		# Fallback: Forme géométrique
		var color := Color(enemy_data.get("color", "#FF4444"))
		var shape_type := str(enemy_data.get("shape", "circle"))
		
		# Cacher le sprite si existant
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
			
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width * 1.2, height * 1.2) # Scale +20%
	
	# Collision (toujours basée sur la taille)
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = (max(width, height) / 2.0) * 1.2 # Scale +20%
	collision.shape = circle_shape

	# Physics Layer Setup
	# Layer 3 (Value 4) = Enemies
	collision_layer = 4
	# Mask: World(1) + PlayerProjectiles(8)
	# Removed Player(2) to prevent physical pushing
	collision_mask = 1 + 8 

func get_contact_damage() -> int:
	# Retourne les dégâts de collision (similaire à un missile par défaut)
	var dmg: int = 10
	if not _missile_pattern_data.is_empty():
		dmg = int(_missile_pattern_data.get("damage", 10))
	return int(dmg * _stat_multiplier)

func _setup_health_bar() -> void:
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.size = Vector2(40, 4)
	health_bar.position = Vector2(-20, -30)
	_update_health_bar_color()

# =============================================================================
# LIFECYCLE
# =============================================================================

func _process(delta: float) -> void:
	_update_movement(delta)
	_update_shooting(delta)
	
	# Vérifier si hors écran (en bas)
	if global_position.y > get_viewport_rect().size.y + 100:
		queue_free()

# =============================================================================
# MOVEMENT
# =============================================================================

func _update_movement(delta: float) -> void:
	_move_time += delta
	
	var pattern_type := str(_move_pattern_data.get("type", "linear"))
	
	match pattern_type:
		"linear":
			_move_linear(delta)
		"zigzag":
			_move_zigzag(delta)
		"sine_wave":
			_move_sine_wave(delta)
		"circular":
			_move_circular(delta)
		"static":
			pass  # Ne bouge pas
		"homing":
			_move_homing(delta)
		"bounce":
			_move_bounce(delta)
		_:
			_move_linear(delta)

func _move_linear(_delta: float) -> void:
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 0, "y": 1})
	var direction := Vector2.ZERO
	
	if dir_data is Dictionary:
		var dir_dict := dir_data as Dictionary
		direction = Vector2(float(dir_dict.get("x", 0)), float(dir_dict.get("y", 1)))
	
	velocity = direction.normalized() * move_speed
	move_and_slide()

func _move_zigzag(_delta: float) -> void:
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 1, "y": 0.5})
	var base_dir := Vector2.ZERO
	
	if dir_data is Dictionary:
		var dir_dict := dir_data as Dictionary
		base_dir = Vector2(float(dir_dict.get("x", 1)), float(dir_dict.get("y", 0.5)))
	
	var amplitude: float = float(_move_pattern_data.get("amplitude", 50))
	var frequency: float = float(_move_pattern_data.get("frequency", 2.0))
	
	var zigzag_offset := sin(_move_time * frequency) * amplitude
	velocity = base_dir.normalized() * move_speed
	velocity.x += zigzag_offset
	move_and_slide()

func _move_sine_wave(delta: float) -> void:
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 0, "y": 1})
	var base_dir := Vector2.ZERO
	
	if dir_data is Dictionary:
		var dir_dict := dir_data as Dictionary
		base_dir = Vector2(float(dir_dict.get("x", 0)), float(dir_dict.get("y", 1)))
	
	var amplitude: float = float(_move_pattern_data.get("amplitude", 100))
	var frequency: float = float(_move_pattern_data.get("frequency", 1.5))
	
	var perpendicular := Vector2(-base_dir.y, base_dir.x)
	var wave_offset := perpendicular * sin(_move_time * frequency * TAU) * amplitude * delta
	
	velocity = base_dir.normalized() * move_speed + wave_offset * 10
	move_and_slide()

func _move_circular(_delta: float) -> void:
	var radius: float = float(_move_pattern_data.get("radius", 80))
	var angular_speed: float = float(_move_pattern_data.get("angular_speed", 2.0))
	var clockwise: bool = bool(_move_pattern_data.get("clockwise", true))
	
	var angle := _move_time * angular_speed * (1 if clockwise else -1)
	var offset := Vector2(cos(angle), sin(angle)) * radius
	global_position = _start_position + offset

func _move_homing(delta: float) -> void:
	# Chercher le joueur
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node and player_node is Node2D:
		var player := player_node as Node2D
		var to_player: Vector2 = (player.global_position - global_position).normalized()
		var turn_rate: float = float(_move_pattern_data.get("turn_rate", 3.0))
		
		velocity = velocity.lerp(to_player * move_speed, turn_rate * delta)
		move_and_slide()
	else:
		_move_linear(delta)

func _move_bounce(delta: float) -> void:
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 1, "y": 0.3})
	
	if velocity == Vector2.ZERO:
		if dir_data is Dictionary:
			var dir_dict := dir_data as Dictionary
			velocity = Vector2(float(dir_dict.get("x", 1)), float(dir_dict.get("y", 0.3))).normalized() * move_speed
	
	move_and_slide()
	
	# Rebond sur les bords
	var viewport_size := get_viewport_rect().size
	if global_position.x <= 0 or global_position.x >= viewport_size.x:
		velocity.x *= -1

# =============================================================================
# SHOOTING
# =============================================================================

func _update_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0:
		_fire()
		_fire_timer = fire_rate

func _fire() -> void:
	if _missile_pattern_data.is_empty():
		return
	
	var projectile_count: int = int(_missile_pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(_missile_pattern_data.get("spread_angle", 0))
	var trajectory := str(_missile_pattern_data.get("trajectory", "straight"))
	var speed: float = float(_missile_pattern_data.get("speed", 200))
	var base_damage: int = int(_missile_pattern_data.get("damage", 10))
	var damage: int = int(base_damage * _stat_multiplier)

	# Injecter les data visuelles du missile et override speed
	var missile_data := DataManager.get_missile(missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		_missile_pattern_data["visual_data"] = visual_data
	
	var missile_speed_override: float = float(missile_data.get("speed", 0))
	if missile_speed_override > 0:
		speed = missile_speed_override
	
	# Direction de base (vers le bas, ou aimed vers le joueur)
	var base_direction := Vector2.DOWN
	
	if trajectory == "aimed":
		var player_node := get_tree().get_first_node_in_group("player")
		if player_node and player_node is Node2D:
			var player := player_node as Node2D
			base_direction = (player.global_position - global_position).normalized()
	
	# Spawn les projectiles
	if projectile_count == 1:
		ProjectileManager.spawn_enemy_projectile(global_position, base_direction, speed, damage, _missile_pattern_data)
	else:
		var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
		var start_angle: float = -deg_to_rad(spread_angle) / 2.0
		
		for i in range(projectile_count):
			var angle: float = start_angle + angle_step * i
			var direction := base_direction.rotated(angle)
			ProjectileManager.spawn_enemy_projectile(global_position, direction, speed, damage, _missile_pattern_data)

# =============================================================================
# DAMAGE & DEATH
# =============================================================================

func take_damage(amount: int, is_critical: bool = false) -> void:
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	health_bar.value = current_hp
	_update_health_bar_color()
	
	# Feedback visuel
	var flash_color := Color.WHITE
	if is_critical:
		flash_color = Color.YELLOW
		VFXManager.spawn_floating_text(global_position, "CRIT!", Color.YELLOW, get_parent())
	
	VFXManager.flash_sprite(visual_container, flash_color, 0.1)
	
	if current_hp <= 0:
		die()

func die() -> void:
	print("[Enemy] ", enemy_name, " died! Score: ", score)
	
	# VFX explosion
	VFXManager.spawn_explosion(global_position, 25, shape_visual.color, get_parent())
	VFXManager.screen_shake(3, 0.2)
	
	# Spawn loot si chance
	if randf() <= loot_chance:
		_spawn_loot()
	
	enemy_died.emit(self)
	queue_free()

func _spawn_loot() -> void:
	# Générer un item aléatoire
	var slot_ids := DataManager.get_slot_ids()
	if slot_ids.is_empty():
		return
	
	var random_slot: String = str(slot_ids[randi() % slot_ids.size()])
	var item_id := "loot_" + str(Time.get_ticks_msec()) + "_" + str(randi())
	
	var item := {
		"id": item_id,
		"name": "Loot " + random_slot,
		"slot": random_slot,
		"rarity": "common",
		"level": 1,
		"stats": {"bonus": randi() % 10 + 1}
	}
	
	# Spawn le visual
	var loot_scene := load("res://scenes/LootDrop.tscn")
	var loot: Area2D = loot_scene.instantiate()
	get_parent().call_deferred("add_child", loot)
	loot.setup.call_deferred(item, global_position)

func _update_health_bar_color() -> void:
	var hp_percent := float(current_hp) / float(max_hp)
	
	if hp_percent > 0.75:
		health_bar.modulate = Color.GREEN
	elif hp_percent > 0.33:
		health_bar.modulate = Color.YELLOW
	else:
		health_bar.modulate = Color.RED

# =============================================================================
# UTILITY
# =============================================================================

func _create_shape_polygon(shape_type: String, width: float, height: float) -> PackedVector2Array:
	match shape_type:
		"circle":
			return _create_circle(max(width, height) / 2.0)
		"rectangle":
			return PackedVector2Array([
				Vector2(-width/2, -height/2),
				Vector2(width/2, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"triangle":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"diamond":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, 0),
				Vector2(0, height/2),
				Vector2(-width/2, 0)
			])
		"hexagon":
			return _create_hexagon(max(width, height) / 2.0)
		_:
			return _create_circle(max(width, height) / 2.0)

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 16
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _create_hexagon(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := (i / 6.0) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
