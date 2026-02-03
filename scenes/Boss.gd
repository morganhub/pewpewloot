extends CharacterBody2D

## Boss — Grand ennemi avec phases multiples et UI spéciale.
## Change de pattern selon les seuils de HP.

# =============================================================================
# SIGNALS
# =============================================================================

signal boss_died(boss: CharacterBody2D)
signal health_changed(current: int, max: int)
signal phase_changed(phase: int)

# =============================================================================
# PROPERTIES
# =============================================================================

var boss_id: String = ""
var boss_name: String = "Boss"
var max_hp: int = 500
var current_hp: int = 500
var score: int = 1000
var loot_unique_chance: float = 0.15

# Phases
var phases: Array = []
var current_phase: int = 0

# Movement & Shooting (current phase)
var move_pattern_id: String = "stationary"
var missile_pattern_id: String = "circle_8"
var missile_id: String = "missile_default"
var fire_rate: float = 2.0

var _move_pattern_data: Dictionary = {}
var _missile_pattern_data: Dictionary = {}
var _fire_timer: float = 0.0
var _move_time: float = 0.0
var _start_position: Vector2 = Vector2.ZERO

# Visual
@onready var visual_container: Node2D = $Visual
@onready var shape_visual: Polygon2D = $Visual/Shape
@onready var collision: CollisionShape2D = $CollisionShape2D

# =============================================================================
# SETUP
# =============================================================================

func setup(boss_data: Dictionary) -> void:
	boss_id = str(boss_data.get("id", "boss_unknown"))
	boss_name = str(boss_data.get("name", "Boss"))
	max_hp = int(boss_data.get("hp", 500))
	current_hp = max_hp
	score = int(boss_data.get("score", 1000))
	loot_unique_chance = float(boss_data.get("loot_unique_chance", 0.15))
	missile_id = str(boss_data.get("missile_id", "missile_default"))
	
	# Charger les phases
	var raw_phases: Variant = boss_data.get("phases", [])
	if raw_phases is Array:
		phases = raw_phases as Array
	
	# Initialiser la phase 1
	if not phases.is_empty():
		_apply_phase(0)
	
	# Visual setup
	_setup_visual(boss_data)
	
	_start_position = global_position
	_fire_timer = randf_range(0, fire_rate)
	
	print("[Boss] ", boss_name, " spawned with ", max_hp, " HP and ", phases.size(), " phases")

func _setup_visual(boss_data: Dictionary) -> void:
	var size_data: Variant = boss_data.get("size", {"width": 100, "height": 100})
	var width: float = 100.0
	var height: float = 100.0
	
	if size_data is Dictionary:
		var size_dict := size_data as Dictionary
		width = float(size_dict.get("width", 100))
		height = float(size_dict.get("height", 100))
	
	# Gestion de l'asset vs shape
	var asset_path: String = str(boss_data.get("asset", ""))
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
				sprite.scale = Vector2(width / tex_size.x, height / tex_size.y)
	
	if not use_asset:
		var color := Color(boss_data.get("color", "#AA44FF"))
		var shape_type := str(boss_data.get("shape", "hexagon"))
		
		# Cacher le sprite si existant
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
		
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width, height)
	
	# Collision
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = max(width, height) / 2.0
	collision.shape = circle_shape

# =============================================================================
# LIFECYCLE
# =============================================================================

func _process(delta: float) -> void:
	_update_movement(delta)
	_update_shooting(delta)
	_check_phase_transition()

# =============================================================================
# PHASES
# =============================================================================

func _check_phase_transition() -> void:
	for i in range(phases.size()):
		if i <= current_phase:
			continue
		
		var phase: Variant = phases[i]
		if phase is Dictionary:
			var phase_dict := phase as Dictionary
			var hp_threshold := int(phase_dict.get("hp_threshold", 0))
			var hp_percent := (float(current_hp) / float(max_hp)) * 100.0
			
			if hp_percent <= hp_threshold:
				_apply_phase(i)
				break

func _apply_phase(phase_index: int) -> void:
	if phase_index >= phases.size():
		return
	
	current_phase = phase_index
	var phase_data: Variant = phases[phase_index]
	
	if phase_data is Dictionary:
		var phase_dict := phase_data as Dictionary
		move_pattern_id = str(phase_dict.get("move_pattern_id", "stationary"))
		missile_pattern_id = str(phase_dict.get("missile_pattern_id", "circle_8"))
		if phase_dict.has("missile_id"):
			missile_id = str(phase_dict.get("missile_id", "missile_default"))
		fire_rate = float(phase_dict.get("fire_rate", 2.0))
		
		_move_pattern_data = DataManager.get_move_pattern(move_pattern_id)
		_missile_pattern_data = DataManager.get_missile_pattern(missile_pattern_id)
		
		print("[Boss] Phase ", current_phase + 1, " activated!")
		phase_changed.emit(current_phase + 1)
		
		# VFX de changement de phase
		VFXManager.screen_shake(15, 0.5)
		VFXManager.flash_sprite(visual_container, Color.WHITE, 0.3)

# =============================================================================
# MOVEMENT (Copié et adapté d'Enemy.gd)
# =============================================================================

func _update_movement(delta: float) -> void:
	_move_time += delta
	
	var pattern_type := str(_move_pattern_data.get("type", "static"))
	var move_speed := float(_move_pattern_data.get("speed", 60))
	
	match pattern_type:
		"static":
			pass
		"circular":
			_move_circular(delta, move_speed)
		"sine_wave":
			_move_sine_wave(delta, move_speed)
		"homing":
			_move_homing(delta, move_speed)
		_:
			pass

func _move_circular(_delta: float, _speed: float) -> void:
	var radius: float = float(_move_pattern_data.get("radius", 80))
	var angular_speed: float = float(_move_pattern_data.get("angular_speed", 2.0))
	var clockwise: bool = bool(_move_pattern_data.get("clockwise", true))
	
	var angle := _move_time * angular_speed * (1 if clockwise else -1)
	var offset := Vector2(cos(angle), sin(angle)) * radius
	global_position = _start_position + offset

func _move_sine_wave(_delta: float, _speed: float) -> void:
	var amplitude: float = float(_move_pattern_data.get("amplitude", 100))
	var frequency: float = float(_move_pattern_data.get("frequency", 1.5))
	
	var wave_x := sin(_move_time * frequency * TAU) * amplitude
	global_position.x = _start_position.x + wave_x

func _move_homing(delta: float, speed: float) -> void:
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node and player_node is Node2D:
		var player := player_node as Node2D
		var to_player: Vector2 = (player.global_position - global_position).normalized()
		velocity = velocity.lerp(to_player * speed, delta * 2.0)
		move_and_slide()

# =============================================================================
# SHOOTING (Copié d'Enemy.gd)
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
	var damage: int = int(_missile_pattern_data.get("damage", 15))
	
	# Injecter les data visuelles du missile
	var missile_data := DataManager.get_missile(missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		_missile_pattern_data["visual_data"] = visual_data
	
	var base_direction := Vector2.DOWN
	
	if trajectory == "aimed":
		var player_node := get_tree().get_first_node_in_group("player")
		if player_node and player_node is Node2D:
			var player := player_node as Node2D
			base_direction = (player.global_position - global_position).normalized()
	elif trajectory == "radial":
		# Cercle complet
		for i in range(projectile_count):
			var angle: float = (i / float(projectile_count)) * TAU
			var direction := Vector2(cos(angle), sin(angle))
			ProjectileManager.spawn_enemy_projectile(global_position, direction, speed, damage, _missile_pattern_data)
		return
	
	# Spawn normal avec spread
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
	
	# VFX hit
	var flash_color := Color.WHITE
	if is_critical:
		flash_color = Color.YELLOW
		VFXManager.spawn_floating_text(global_position, "CRIT!", Color.YELLOW, get_parent())
	
	VFXManager.flash_sprite(visual_container, flash_color, 0.1)
	VFXManager.screen_shake(5, 0.1)
	
	health_changed.emit(current_hp, max_hp)
	_check_phase_transition()
	
	if current_hp <= 0:
		die()

func die() -> void:
	print("[Boss] ", boss_name, " defeated! Score: ", score)
	
	# VFX explosion
	VFXManager.spawn_explosion(global_position, 50, shape_visual.color, get_parent())
	VFXManager.screen_shake(20, 0.8)
	
	# TODO: Spawn loot unique si chance
	
	boss_died.emit(self)
	queue_free()

# =============================================================================
# UTILITY
# =============================================================================

func _create_shape_polygon(shape_type: String, width: float, height: float) -> PackedVector2Array:
	match shape_type:
		"circle":
			return _create_circle(max(width, height) / 2.0)
		"hexagon":
			return _create_hexagon(max(width, height) / 2.0)
		_:
			return _create_hexagon(max(width, height) / 2.0)

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 24
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
