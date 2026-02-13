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
var death_asset: String = ""
var death_anim: String = ""
var loot_quality_multiplier: float = 1.0

# Movement
var move_pattern_id: String = "straight_down"
var move_speed: float = 100.0
var _move_pattern_data: Dictionary = {}
var _move_time: float = 0.0
var _move_state: int = 0 # 0: Enter, 1: Hover/Loop, 2: Leave
var _move_state_timer: float = 0.0

var _start_position: Vector2 = Vector2.ZERO
var _stat_multiplier: float = 1.0

# Shooting
var missile_pattern_id: String = "single_straight"
var missile_id: String = "missile_default"
var fire_rate: float = 2.0
var _fire_timer: float = 0.0
var _missile_pattern_data: Dictionary = {}

# Lifetime
var _lifetime_timer: float = 0.0
var _is_leaving: bool = false
const MAX_LIFETIME: float = 12.0

# Shared ability: mine spawner (minefreak)
const MINE_SCENE = preload("res://scenes/objects/Mine.tscn")
const ARCANE_ORB_SCENE = preload("res://scenes/objects/ArcaneOrb.tscn")
const GRAVITY_WELL_SCENE = preload("res://scenes/objects/GravityWell.tscn")
var _minefreak_enabled: bool = false
var _minefreak_visuals: Dictionary = {}
var _minefreak_ability_config: Dictionary = {}
var _arcane_enabled: bool = false
var _arcane_visuals: Dictionary = {}
var _arcane_ability_config: Dictionary = {}
var _graviton_enabled: bool = false
var _graviton_visuals: Dictionary = {}
var _graviton_ability_config: Dictionary = {}

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

func setup(enemy_data: Dictionary, stat_multiplier: float = 1.0, modifier_id: String = "") -> void:
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
	
	# Apply Modifier (Elite)
	if modifier_id == "":
		modifier_id = str(enemy_data.get("modifier_id", ""))
		
	if modifier_id != "":
		EnemyModifiers.apply_modifier(self, modifier_id)

func _setup_visual(enemy_data: Dictionary) -> void:
	var size_data: Variant = enemy_data.get("size", {"width": 30, "height": 30})
	var width: float = 30.0
	var height: float = 30.0
	
	if size_data is Dictionary:
		var size_dict := size_data as Dictionary
		width = float(size_dict.get("width", 30))
		height = float(size_dict.get("height", 30))
	
	# Gestion de l'asset vs shape
	var visual_data: Variant = enemy_data.get("visual", {})
	var asset_path: String = ""
	var asset_anim: String = ""
	var color_hex: String = "#FF4444"
	var shape_type: String = "circle"
	
	if visual_data is Dictionary:
		var v_dict := visual_data as Dictionary
		asset_path = str(v_dict.get("asset", ""))
		asset_anim = str(v_dict.get("asset_anim", ""))
		color_hex = str(v_dict.get("color", "#FF4444"))
		shape_type = str(v_dict.get("shape", "circle"))

	var use_asset: bool = false
	
	# Priority 1: AnimatedSprite (asset_anim)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames = load(asset_anim)
		if frames is SpriteFrames:
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if not anim_sprite:
				anim_sprite = AnimatedSprite2D.new()
				anim_sprite.name = "AnimatedSprite2D"
				visual_container.add_child(anim_sprite)
			
			anim_sprite.visible = true
			anim_sprite.sprite_frames = frames
			anim_sprite.play("default")
			
			# Scale
			var frame_tex = frames.get_frame_texture("default", 0)
			if frame_tex:
				var f_size = frame_tex.get_size()
				anim_sprite.scale = Vector2(width / f_size.x, height / f_size.y) * 1.2
				
			# Hide static sprite
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if sprite: sprite.visible = false
	
	# Priority 2: Static Sprite (asset)
	if not use_asset and asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			use_asset = true
			shape_visual.visible = false
			
			# Hide anim sprite
			var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
			if anim_sprite: anim_sprite.visible = false
			
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
		var color := Color(color_hex)
		
		# Cacher le sprite si existant
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
		var anim_sprite: AnimatedSprite2D = visual_container.get_node_or_null("AnimatedSprite2D")
		if anim_sprite: anim_sprite.visible = false
			
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
	
	# Death VFX data
	var visual_data_v: Dictionary = enemy_data.get("visual", {})
	if "death_asset" not in self:
		var script_script = get_script()
		# Add script variables dynamically? No.
		# Just set instance meta or simple vars if declared.
		pass
	
	set("death_asset", str(visual_data_v.get("on_death_asset", "")))
	set("death_anim", str(visual_data_v.get("on_death_asset_anim", "")))

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

func apply_stat_multipliers(stats: Dictionary) -> void:
	var hp_mult = float(stats.get("hp_mult", 1.0))
	if hp_mult != 1.0:
		max_hp = int(max_hp * hp_mult)
		current_hp = max_hp
		health_bar.max_value = max_hp
		health_bar.value = current_hp
		
	var spd_mult = float(stats.get("speed_mult", 1.0))
	if spd_mult != 1.0:
		move_speed *= spd_mult
		
	var dmg_mult = float(stats.get("damage_mult", 1.0))
	if dmg_mult != 1.0:
		_stat_multiplier *= dmg_mult

func set_health_bar_frame(path: String) -> void:
	if not ResourceLoader.exists(path): return
	var tex = load(path)
	
	var frame = TextureRect.new()
	frame.name = "EliteFrame"
	frame.texture = tex
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Adjust size/position to surround the bar
	# Assuming frame asset is designed to wrap around
	health_bar.add_child(frame)
	frame.layout_mode = 1 # Anchors
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Add some margin/padding?
	frame.offset_left = -5
	frame.offset_top = -5
	frame.offset_right = 5
	frame.offset_bottom = 5
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

# =============================================================================
# LIFECYCLE
# =============================================================================

func _process(delta: float) -> void:
	# Lifetime Management (Except Bosses)
	if not _is_leaving and not enemy_id.begins_with("boss_"): 
		# Note: Better check might be group "bosses" but enemy_id prefix is safe enough if group not set
		_lifetime_timer += delta
		if _lifetime_timer >= MAX_LIFETIME:
			_is_leaving = true
			
	_update_movement(delta)
	_update_shooting(delta)
	_update_minefreak_spawn()
	_update_arcane_spawn()
	_update_graviton_spawn()
	
	# Handle wave firing
	if _is_firing_waves:
		_update_wave_firing(delta)
	
	# Vérifier si hors écran (en bas)
	if global_position.y > get_viewport_rect().size.y + 100:
		queue_free()

func _update_wave_firing(delta: float) -> void:
	_wave_timer += delta
	
	var wave_count: int = int(_missile_pattern_data.get("wave_count", 1))
	var wave_interval: float = float(_missile_pattern_data.get("wave_interval", 0.5))
	
	if _wave_timer >= wave_interval:
		_wave_timer = 0.0
		_current_wave += 1
		
		if _current_wave < wave_count:
			_fire_single_wave()
		else:
			_is_firing_waves = false
			_current_wave = 0


# =============================================================================
# MOVEMENT
# =============================================================================

func _update_movement(delta: float) -> void:
	if _is_leaving:
		_move_leave_screen(delta)
		return

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
		"enter_hover_leave":
			_move_enter_hover_leave(delta)
		"loop_center":
			_move_loop_center(delta)
		"figure_eight":
			_move_figure_eight(delta)
		"random_strafe":
			_move_random_strafe(delta)
		"bezier_curve":
			_move_bezier_curve(delta)
		"swoop_dive":
			_move_swoop_dive(delta)
		"spiral_inward":
			_move_spiral_inward(delta)
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

func _move_circular(delta: float) -> void:
	var radius: float = float(_move_pattern_data.get("radius", 80))
	var angular_speed: float = float(_move_pattern_data.get("angular_speed", 2.0))
	var clockwise: bool = bool(_move_pattern_data.get("clockwise", true))
	
	# Direction moves the center of rotation
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 0, "y": 0.5})
	var move_dir := Vector2.ZERO
	if dir_data is Dictionary:
		var d_dict := dir_data as Dictionary
		move_dir = Vector2(float(d_dict.get("x", 0)), float(d_dict.get("y", 0.5)))
	
	# Current center moves over time
	var center_pos := _start_position + (move_dir.normalized() * move_speed * _move_time)
	
	var angle := _move_time * angular_speed * (1 if clockwise else -1)
	var offset := Vector2(cos(angle), sin(angle)) * radius
	global_position = center_pos + offset

func _move_leave_screen(delta: float) -> void:
	# Move towards y = 1.5 * viewport (+50%)
	# Standard leave direction: DOWN
	var direction := Vector2(0, 1)
	velocity = direction * move_speed
	
	# Override if specific leave direction needed? No, standard down is fine.
	# Or follow current trajectory? User asked for "y = 1.5"
	var viewport_h := get_viewport_rect().size.y
	var target_y := viewport_h * 1.5
	
	# Accelerate slightly when leaving?
	velocity = direction * (move_speed * 1.5)
	move_and_slide()

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

func _move_enter_hover_leave(delta: float) -> void:
	var hover_duration: float = float(_move_pattern_data.get("hover_duration", 3.0))
	var target_y: float = float(_move_pattern_data.get("target_y", 150.0))
	
	match _move_state:
		0: # Enter
			var dist = target_y - global_position.y
			if dist < 5:
				_move_state = 1
				_move_state_timer = hover_duration
				velocity = Vector2.ZERO
			else:
				velocity = Vector2.DOWN * move_speed
		
		1: # Hover
			velocity = Vector2.ZERO
			# Optional: slight bobbing
			global_position.y += sin(Time.get_ticks_msec() * 0.005) * 0.5
			
			_move_state_timer -= delta
			if _move_state_timer <= 0:
				_move_state = 2
				
		2: # Leave
			velocity = Vector2.DOWN * move_speed

	move_and_slide()

func _move_loop_center(delta: float) -> void:
	var loop_radius: float = float(_move_pattern_data.get("loop_radius", 100))
	var center_x := get_viewport_rect().size.x / 2.0
	var center_y := get_viewport_rect().size.y * 0.4
	var target := Vector2(center_x, center_y)
	
	match _move_state:
		0: # Goto center start
			var start_loop_pos = target + Vector2(0, loop_radius) # Start loop from bottom of circle
			var to_target = start_loop_pos - global_position
			if to_target.length() < 10:
				_move_state = 1
				_move_state_timer = 0 # Use as angle accumulator
			else:
				velocity = to_target.normalized() * move_speed
				move_and_slide()
				
		1: # Loop
			_move_state_timer += delta * 3.0 # Speed
			var angle = _move_state_timer - PI/2 # Start at bottom (-90 deg rotated?) No, circle math logic
			# Circle logic: center + (sin, cos)
			# We want start at bottom (0, radius).
			# Angle 0 => (radius, 0) right. PI/2 => (0, radius) bottom.
			
			var loop_angle = _move_state_timer + PI/2
			var offset = Vector2(cos(loop_angle), sin(loop_angle)) * loop_radius
			global_position = target + offset
			
			if _move_state_timer >= TAU: # Full circle
				_move_state = 2
				
		2: # Leave
			velocity = Vector2(0, 1) * move_speed
			move_and_slide()

func _move_figure_eight(_delta: float) -> void:
	var radius: float = float(_move_pattern_data.get("radius", 60))
	
	# Lemniscate of Bernoulli (figure-8)
	var t: float = _move_time * 2.0
	var scale_factor: float = radius / (1.0 + sin(t) * sin(t))
	var x_offset: float = scale_factor * cos(t)
	var y_offset: float = scale_factor * sin(t) * cos(t)
	
	global_position = _start_position + Vector2(x_offset, y_offset + _move_time * move_speed * 0.2)

var _strafe_target_x: float = 0.0
var _strafe_timer: float = 0.0

func _move_random_strafe(delta: float) -> void:
	var strafe_interval: float = float(_move_pattern_data.get("strafe_interval", 1.5))
	var strafe_distance: float = float(_move_pattern_data.get("strafe_distance", 80))
	var dir_data: Variant = _move_pattern_data.get("direction", {"x": 0, "y": 0.3})
	var base_dir := Vector2.ZERO
	
	if dir_data is Dictionary:
		var dir_dict := dir_data as Dictionary
		base_dir = Vector2(float(dir_dict.get("x", 0)), float(dir_dict.get("y", 0.3)))
	
	_strafe_timer += delta
	if _strafe_timer >= strafe_interval:
		_strafe_timer = 0.0
		_strafe_target_x = global_position.x + randf_range(-strafe_distance, strafe_distance)
		# Clamp to screen
		var viewport_size := get_viewport_rect().size
		_strafe_target_x = clampf(_strafe_target_x, 50, viewport_size.x - 50)
	
	# Move towards strafe target
	var x_diff: float = _strafe_target_x - global_position.x
	var x_move: float = sign(x_diff) * min(abs(x_diff), move_speed * delta)
	
	velocity = base_dir.normalized() * move_speed
	velocity.x += x_move * 2.0
	move_and_slide()

var _bezier_t: float = 0.0
var _bezier_start: Vector2 = Vector2.ZERO
var _bezier_control: Vector2 = Vector2.ZERO
var _bezier_end: Vector2 = Vector2.ZERO

func _move_bezier_curve(delta: float) -> void:
	# Initialize bezier points
	if _bezier_start == Vector2.ZERO:
		_bezier_start = _start_position
		var offset_x: float = float(_move_pattern_data.get("control_offset_x", 150))
		var offset_y: float = float(_move_pattern_data.get("control_offset_y", 100))
		# Randomize control point direction
		if randf() > 0.5:
			offset_x *= -1
		_bezier_control = _start_position + Vector2(offset_x, offset_y)
		_bezier_end = Vector2(_start_position.x, get_viewport_rect().size.y + 50)
	
	_bezier_t += delta * 0.5 * (move_speed / 100.0)
	_bezier_t = minf(_bezier_t, 1.0)
	
	# Quadratic Bezier: B(t) = (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
	var t: float = _bezier_t
	var inv_t: float = 1.0 - t
	global_position = inv_t * inv_t * _bezier_start + 2 * inv_t * t * _bezier_control + t * t * _bezier_end

func _move_swoop_dive(delta: float) -> void:
	var swoop_depth: float = float(_move_pattern_data.get("swoop_depth", 200))
	var swoop_width: float = float(_move_pattern_data.get("swoop_width", 100))
	
	match _move_state:
		0: # Swooping arc
			var t: float = _move_time * (move_speed / 100.0)
			if t < PI:
				var x_offset: float = sin(t) * swoop_width
				var y_offset: float = (1.0 - cos(t)) * swoop_depth * 0.5
				global_position = _start_position + Vector2(x_offset, y_offset)
			else:
				_move_state = 1
		1: # Dive towards player
			var player_node := get_tree().get_first_node_in_group("player")
			if player_node and player_node is Node2D:
				var player := player_node as Node2D
				var to_player: Vector2 = (player.global_position - global_position).normalized()
				velocity = to_player * move_speed * 1.5
			else:
				velocity = Vector2.DOWN * move_speed * 1.5
			move_and_slide()

func _move_spiral_inward(_delta: float) -> void:
	var initial_radius: float = float(_move_pattern_data.get("initial_radius", 200))
	var spiral_speed: float = float(_move_pattern_data.get("spiral_speed", 30))
	var viewport_size := get_viewport_rect().size
	var center := Vector2(viewport_size.x / 2, viewport_size.y * 0.5)
	
	var current_radius: float = maxf(initial_radius - _move_time * spiral_speed, 10.0)
	var angle: float = _move_time * (move_speed / 50.0)
	
	var offset := Vector2(cos(angle), sin(angle)) * current_radius
	global_position = center + offset

# =============================================================================
# SHOOTING
# =============================================================================

func _update_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0:
		_fire()
		_fire_timer = fire_rate

var _current_wave: int = 0
var _wave_timer: float = 0.0
var _is_firing_waves: bool = false

func _fire() -> void:
	if _missile_pattern_data.is_empty():
		return
	
	var wave_count: int = int(_missile_pattern_data.get("wave_count", 1))
	var wave_interval: float = float(_missile_pattern_data.get("wave_interval", 0.0))
	
	# If pattern has waves, start wave firing sequence
	if wave_count > 1 and wave_interval > 0.0 and not _is_firing_waves:
		_is_firing_waves = true
		_current_wave = 0
		_wave_timer = 0.0
		set_process(true)
	
	_fire_single_wave()
	
func _fire_single_wave() -> void:
	if _missile_pattern_data.is_empty():
		return

	var projectile_count: int = int(_missile_pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(_missile_pattern_data.get("spread_angle", 0))
	var trajectory := str(_missile_pattern_data.get("trajectory", "straight"))
	var speed: float = float(_missile_pattern_data.get("speed", 200))
	var base_damage: int = int(_missile_pattern_data.get("damage", 10))
	var damage: int = int(base_damage * _stat_multiplier)
	var spawn_strategy: String = str(_missile_pattern_data.get("spawn_strategy", "shooter"))

	# Injecter les data visuelles du missile et override speed
	var missile_data := DataManager.get_missile(missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		_missile_pattern_data["visual_data"] = visual_data
	
	# Inject acceleration from missile
	var acceleration: float = float(missile_data.get("acceleration", 0.0))
	_missile_pattern_data["acceleration"] = acceleration
	
	# Inject explosion data from missile (individual) or use default
	var missile_explosion: Dictionary = missile_data.get("explosion", {})
	if not missile_explosion.is_empty() and missile_explosion.keys().size() > 0:
		_missile_pattern_data["explosion_data"] = missile_explosion
	
	var missile_speed_override: float = float(missile_data.get("speed", 0))
	if missile_speed_override > 0:
		speed = missile_speed_override
		
	# Play sound (once per wave/salvo)
	var sound_path: String = str(missile_data.get("sound", ""))
	if sound_path != "":
		AudioManager.play_sfx(sound_path, 0.1)
	
	# Get spawn positions based on strategy
	var spawn_positions: Array = _get_spawn_positions(spawn_strategy, projectile_count)
	var player_node: Node2D = get_tree().get_first_node_in_group("player")
	
	var is_aimed := (trajectory == "aimed") or bool(_missile_pattern_data.get("aim_target", false))
	
	for i in range(spawn_positions.size()):
		var spawn_pos: Vector2 = spawn_positions[i]
		var direction: Vector2 = Vector2.DOWN
		
		if is_aimed and player_node:
			direction = (player_node.global_position - spawn_pos).normalized()
		else:
			# Default direction based on spawn strategy
			direction = _get_default_direction(spawn_strategy, spawn_pos)
		
		# Apply spread angle if multiple projectiles from same position
		if spawn_strategy == "shooter" and projectile_count > 1:
			var is_full_circle: bool = abs(spread_angle - 360.0) < 10.0  # Allow small tolerance
			
			if is_full_circle:
				# For full circle (radial): Divide evenly around 360 degrees
				var angle_step: float = TAU / float(projectile_count)
				var angle: float = angle_step * float(i)
				direction = Vector2.DOWN.rotated(angle)
			else:
				# For partial spread: Fan out from center
				var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
				var start_angle: float = -deg_to_rad(spread_angle) / 2.0
				var angle: float = start_angle + angle_step * i
				direction = direction.rotated(angle)
		
		ProjectileManager.spawn_enemy_projectile(spawn_pos, direction, speed, damage, _missile_pattern_data)

func _get_spawn_positions(strategy: String, count: int) -> Array:
	var positions: Array = []
	var viewport_size := get_viewport_rect().size
	var player_node: Node2D = get_tree().get_first_node_in_group("player")
	
	match strategy:
		"shooter":
			for i in range(count):
				positions.append(global_position)
		
		"screen_bottom":
			var margin: float = 50.0
			var step_x: float = (viewport_size.x - margin * 2) / max(1, count - 1) if count > 1 else 0.0
			for i in range(count):
				var x: float = margin + step_x * i if count > 1 else viewport_size.x / 2.0
				positions.append(Vector2(x, viewport_size.y + 20))
		
		"screen_top":
			var margin: float = 50.0
			var step_x: float = (viewport_size.x - margin * 2) / max(1, count - 1) if count > 1 else 0.0
			for i in range(count):
				var x: float = margin + step_x * i if count > 1 else viewport_size.x / 2.0
				positions.append(Vector2(x, -20))
		
		"target_circle":
			var radius: float = float(_missile_pattern_data.get("spawn_radius", 150))
			var target_pos: Vector2 = player_node.global_position if player_node else Vector2(viewport_size.x / 2, viewport_size.y / 2)
			for i in range(count):
				var angle: float = (float(i) / float(count)) * TAU
				var offset := Vector2(cos(angle), sin(angle)) * radius
				positions.append(target_pos + offset)
		
		"corners":
			positions.append(Vector2(30, 30))
			positions.append(Vector2(viewport_size.x - 30, 30))
			positions.append(Vector2(30, viewport_size.y - 30))
			positions.append(Vector2(viewport_size.x - 30, viewport_size.y - 30))
		
		"flanking":
			var half: int = count / 2
			var step_y: float = viewport_size.y / max(1, half)
			for i in range(half):
				positions.append(Vector2(-20, step_y * i + step_y / 2))  # Left
				positions.append(Vector2(viewport_size.x + 20, step_y * i + step_y / 2))  # Right
		
		"random_edge":
			for i in range(count):
				var edge: int = randi() % 4
				var pos: Vector2
				match edge:
					0:  # Top
						pos = Vector2(randf_range(0, viewport_size.x), -20)
					1:  # Bottom
						pos = Vector2(randf_range(0, viewport_size.x), viewport_size.y + 20)
					2:  # Left
						pos = Vector2(-20, randf_range(0, viewport_size.y))
					3:  # Right
						pos = Vector2(viewport_size.x + 20, randf_range(0, viewport_size.y))
				positions.append(pos)
		
		_:
			for i in range(count):
				positions.append(global_position)
	
	return positions

func _get_default_direction(strategy: String, spawn_pos: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var center := Vector2(viewport_size.x / 2, viewport_size.y / 2)
	
	match strategy:
		"screen_bottom":
			return Vector2.UP
		"screen_top":
			return Vector2.DOWN
		"corners", "flanking", "random_edge":
			return (center - spawn_pos).normalized()
		"target_circle":
			var player: Node2D = get_tree().get_first_node_in_group("player")
			if player:
				return (player.global_position - spawn_pos).normalized()
			return (center - spawn_pos).normalized()
		_:
			return Vector2.DOWN

func setup_minefreak(mod_data: Dictionary) -> void:
	_minefreak_enabled = true
	_minefreak_visuals = mod_data.get("visuals", {})
	_minefreak_ability_config = mod_data.get("ability_config", {})

func setup_arcane_enchanted(mod_data: Dictionary) -> void:
	_arcane_enabled = true
	_arcane_visuals = mod_data.get("visuals", {})
	_arcane_ability_config = mod_data.get("ability_config", {})

func setup_graviton(mod_data: Dictionary) -> void:
	_graviton_enabled = true
	_graviton_visuals = mod_data.get("visuals", {})
	_graviton_ability_config = mod_data.get("ability_config", {})

func _update_minefreak_spawn() -> void:
	if not _minefreak_enabled:
		return
	
	var spawn_config := {"ability_config": _minefreak_ability_config}
	if not EnemyAbilityManager.can_spawn("mine_spawner", spawn_config, global_position):
		return
	
	if MINE_SCENE == null:
		return
	
	var mine = MINE_SCENE.instantiate()
	if mine == null:
		return
	
	# Configure mine from modifier visuals + ability config
	mine.set("damage", int(_minefreak_ability_config.get("damage", 25)))
	mine.set("mine_width", int(_minefreak_visuals.get("width", 40)))
	mine.set("mine_height", int(_minefreak_visuals.get("height", 40)))
	mine.set("visual_asset", str(_minefreak_visuals.get("ability_asset", "")))
	mine.set("contact_sfx_path", str(_minefreak_visuals.get("contact_sfx", "")))
	mine.set("explosion_asset", str(_minefreak_visuals.get("explosion_asset", "")))
	
	# Optional tuning hook if later added in data.
	if _minefreak_ability_config.has("mine_hp"):
		var hp := int(_minefreak_ability_config.get("mine_hp", 20))
		mine.set("max_hp", hp)
		mine.set("current_hp", hp)
	if _minefreak_ability_config.has("scroll_speed"):
		mine.set("scroll_speed", float(_minefreak_ability_config.get("scroll_speed", 100.0)))
	if _minefreak_ability_config.has("lateral_speed"):
		mine.set("lateral_speed", float(_minefreak_ability_config.get("lateral_speed", 40.0)))
	if _minefreak_ability_config.has("spin_speed_deg"):
		mine.set("spin_speed_deg", float(_minefreak_ability_config.get("spin_speed_deg", 60.0)))
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(mine)
	if mine is Node2D:
		(mine as Node2D).global_position = global_position
		EnemyAbilityManager.register_spawn("mine_spawner", mine as Node2D, spawn_config)

func _update_arcane_spawn() -> void:
	if not _arcane_enabled:
		return
	
	var spawn_config := {"ability_config": _arcane_ability_config}
	if not EnemyAbilityManager.can_spawn("arcane_spawner", spawn_config, global_position):
		return
	
	if ARCANE_ORB_SCENE == null:
		return
	
	var orb = ARCANE_ORB_SCENE.instantiate()
	if orb == null:
		return
	
	# Configure Arcane Orb from modifier visuals + ability config
	orb.set("damage", int(_arcane_ability_config.get("damage", 15)))
	orb.set("rotation_speed", float(_arcane_ability_config.get("rotation_speed", 45.0)))
	orb.set("laser_length_pct", float(_arcane_ability_config.get("laser_length_pct", 0.30)))
	orb.set("duration", float(_arcane_ability_config.get("duration", 6.0)))
	orb.set("orb_width", int(_arcane_visuals.get("width", 32)))
	orb.set("orb_height", int(_arcane_visuals.get("height", 32)))
	orb.set("ability_asset", str(_arcane_visuals.get("ability_asset", "")))
	orb.set("laser_asset", str(_arcane_visuals.get("laser_asset", "")))
	orb.set("contact_sfx_path", str(_arcane_visuals.get("contact_sfx", "")))
	
	if _arcane_ability_config.has("scroll_speed"):
		orb.set("scroll_speed", float(_arcane_ability_config.get("scroll_speed", 90.0)))
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(orb)
	if orb is Node2D:
		(orb as Node2D).global_position = global_position
		EnemyAbilityManager.register_spawn("arcane_spawner", orb as Node2D, spawn_config)

func _update_graviton_spawn() -> void:
	if not _graviton_enabled:
		return
	
	var spawn_config := {
		"ability_config": _graviton_ability_config,
		"visuals": _graviton_visuals
	}
	if not EnemyAbilityManager.can_spawn("gravity_spawner", spawn_config, global_position):
		return
	
	if GRAVITY_WELL_SCENE == null:
		return
	
	var well = GRAVITY_WELL_SCENE.instantiate()
	if well == null:
		return
	
	var container: Node = get_parent()
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	
	container.add_child(well)
	if well is Node2D:
		(well as Node2D).global_position = global_position
		if well.has_method("setup"):
			well.setup(spawn_config)
		EnemyAbilityManager.register_spawn("gravity_spawner", well as Node2D, spawn_config)

# =============================================================================
# DAMAGE & DEATH
# =============================================================================

func take_damage(amount: int, is_critical: bool = false) -> void:
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	health_bar.value = current_hp
	_update_health_bar_color()
	
	# Play SFX (Enemy Hit)
	# Check if we should play every hit? Maybe limit frequency or only critical?
	# For now playing on every hit.
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("collisions", {})
	var sfx_path = str(sfx_config.get("enemy", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.2)
	
	# Feedback visuel
	var flash_color := Color.WHITE
	if is_critical:
		flash_color = Color.YELLOW
		VFXManager.spawn_floating_text(global_position, "CRIT!", Color.YELLOW, get_parent())
	
	VFXManager.flash_sprite(visual_container, flash_color, 0.1)
	
	if current_hp <= 0:
		die()

func die() -> void:
	enemy_died.emit(self)
	
	# VFX explosion
	var on_death_asset: String = ""
	var on_death_anim: String = ""
	if "death_asset" in self: on_death_asset = get("death_asset")
	if "death_anim" in self: on_death_anim = get("death_anim")
	
	VFXManager.spawn_explosion(global_position, 25, shape_visual.color, get_parent(), on_death_asset, on_death_anim)
	VFXManager.screen_shake(3, 0.2)
	
	# --- LOOT DROP LOGIC ---
	# Config: Chance of Equipment vs PowerUp
	# Let's say: 10% base chance for ANY loot.
	# If loot drops: 20% Equipment, 80% PowerUp? Or separate rolls?
	# Implementation: Separate rolls.
	
	# 1. Equipment (LootGenerator)
	# Chance based on enemy strength/type?
	# Using loot_chance * loot_quality_multiplier for Equipment
	if randf() <= (loot_chance * 0.5): # Halve chance for equipment to balance
		var level: int = 1
		if App: level = App.current_level_index + 1
		
		var item: LootItem = LootGenerator.generate_loot(level, "", "", loot_quality_multiplier)
		if item:
			var drop_scene = load("res://scenes/LootDrop.tscn")
			if drop_scene:
				var drop = drop_scene.instantiate()
				get_parent().call_deferred("add_child", drop)
				drop.call_deferred("setup", item.to_dict(), global_position)
	
	# 2. PowerUps (Shield / Rapid Fire)
	# Using loot_chance for PowerUps
	if randf() <= loot_chance:
		_spawn_powerup()
	
	queue_free()

func _spawn_powerup() -> void:
	var gameplay_config = DataManager.get_game_data().get("gameplay", {}).get("power_ups", {})
	if gameplay_config.is_empty():
		return

	# Roll Type
	# 50/50 split between Shield and Rapid Fire
	var type_roll = randf()
	var item_data: Dictionary = {}
	
	if type_roll < 0.5:
		item_data = {
			"type": "powerup",
			"effect": "shield",
			"name": "Shield Module",
			"visual_asset": str(gameplay_config.get("shield", {}).get("asset", ""))
		}
	else:
		item_data = {
			"type": "powerup",
			"effect": "fire_rate",
			"name": "Rapid Fire",
			"visual_asset": str(gameplay_config.get("rapid_fire", {}).get("asset", ""))
		}
	
	# Spawn Drop
	var drop_scene = load("res://scenes/LootDrop.tscn")
	if drop_scene:
		var drop = drop_scene.instantiate()
		get_parent().call_deferred("add_child", drop)
		drop.call_deferred("setup", item_data, global_position)

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
