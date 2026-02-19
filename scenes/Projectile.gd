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
var _max_lifetime: float = 20.0
var is_critical: bool = false
var _debug_id: int = 0
var _first_frame: bool = true

# New: Acceleration & Explosion
var _acceleration: float = 0.0
var _explosion_data: Dictionary = {}
var _homing_turn_rate: float = 3.0
var _target: Node2D = null

# Skill Tree Modifiers
var skill_modifiers: Dictionary = {}

# Fluid trail
var _fluid_id: String = ""

# Visual
@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D
var _pulsating_enabled: bool = false
var _pulsating_size: float = 1.0
var _pulsating_frequency: float = 1.0
var _base_polygon_scale: Vector2 = Vector2.ONE
var _base_sprite_scale: Vector2 = Vector2.ONE
var _base_anim_sprite_scale: Vector2 = Vector2.ONE

# TODO: Remplacer Polygon2D par Sprite2D quand les assets seront disponibles
# @onready var sprite: Sprite2D = $Sprite2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_debug_id = randi() % 10000
	# DO NOT call deactivate() here as it triggers early return to pool!
	
func activate(pos: Vector2, dir: Vector2, spd: float, dmg: int, pattern_data: Dictionary = {}, is_crit: bool = false, viewport_size_arg: Vector2 = Vector2.ZERO, p_skill_modifiers: Dictionary = {}) -> void:
	# Reset state
	_first_frame = true
	show()
	modulate = Color.WHITE
	global_position = pos
	skill_modifiers = p_skill_modifiers
	
	direction = dir.normalized()
	speed = spd
	damage = dmg
	_pattern_data = pattern_data
	_time_alive = 0.0
	is_active = true
	is_critical = is_crit
	_fluid_id = str(pattern_data.get("fluid_id", ""))
	
	var viewport_size = viewport_size_arg
	
	# Setup Collision Layer/Mask Dynamically
	if is_player_projectile:
		# Layer: PlayerProjectile (8)
		collision_layer = 8
		# Mask: Enemy (4) + World (1) + Obstacles (32)
		collision_mask = 4 + 1 + 32
	else:
		# Layer: EnemyProjectile (16)
		collision_layer = 16
		# Mask: Player (2) + World (1)
		collision_mask = 2 + 1

	# Appliquer le pattern
	_trajectory_type = str(pattern_data.get("trajectory", "straight"))
	
	# Acceleration from missile data
	_acceleration = float(pattern_data.get("acceleration", 0.0))
	
	# Homing turn rate
	_homing_turn_rate = float(pattern_data.get("homing_turn_rate", 3.0))
	
	# Explosion data (missile-specific or default)
	var missile_explosion: Dictionary = pattern_data.get("explosion_data", {})
	if missile_explosion.is_empty():
		_explosion_data = DataManager.get_default_explosion()
	else:
		_explosion_data = missile_explosion
	
	# Visuel Data
	# On s'attend à recevoir soit data complète, soit on fallback sur le pattern_data (legacy)
	var visual_data: Dictionary = pattern_data.get("visual_data", {})
	if visual_data.is_empty():
		print("[Projectile] ⚠️ No visual_data provided, using fallback")
		# Fallback legacy: use pattern_data as visual source
		visual_data = {
			"color": pattern_data.get("color", "#FFFF00"),
			"size": pattern_data.get("size", 8),
			"shape": "circle",
			"asset": "" 
		}

	_setup_visual(visual_data, viewport_size)
	
	# Initial rotation
	rotation = direction.angle() + PI / 2
	
	show()
	set_process(true)

func _setup_visual(visual_data: Dictionary, viewport_size_arg: Vector2) -> void:
	# Calculate size based on percentage of screen height (if provided) or legacy pixel size
	# Use passed viewport size if available (safer during spawn), else fallback
	var viewport_height: float = 1280.0 # Default fallback
	if viewport_size_arg != Vector2.ZERO:
		viewport_height = viewport_size_arg.y
	elif is_inside_tree():
		viewport_height = get_viewport_rect().size.y
	var width_pct: float = float(visual_data.get("width_pct", 0.0))
	var height_pct: float = float(visual_data.get("height_pct", 0.0))
	
	var final_width: float
	var final_height: float
	
	if width_pct > 0.0 and height_pct > 0.0:
		# Use percentage-based sizing
		final_width = viewport_height * width_pct
		final_height = viewport_height * height_pct
	else:
		# Legacy: use pixel size
		var size: float = float(visual_data.get("size", 8)) * 1.5
		final_width = size
		final_height = size
	
	var asset_path: String = str(visual_data.get("asset", ""))
	var asset_anim: String = str(visual_data.get("asset_anim", ""))
	var asset_anim_duration: float = maxf(0.0, float(visual_data.get("asset_anim_duration", 0.0)))
	var asset_anim_loop: bool = bool(visual_data.get("asset_anim_loop", true))
	var asset_duration: float = maxf(0.0, float(visual_data.get("asset_duration", asset_anim_duration)))
	var asset_loop: bool = bool(visual_data.get("asset_loop", asset_anim_loop))
	var use_asset: bool = false
	_pulsating_enabled = bool(visual_data.get("pulsating", false))
	_pulsating_size = clampf(float(visual_data.get("pulsating_size", 1.0)), 0.0, 10.0)
	_pulsating_frequency = maxf(float(visual_data.get("pulsating_frequency", 1.0)), 0.0)
	
	# Reset visual scales because projectiles are pooled and reused.
	visual.scale = Vector2.ONE
	var reset_sprite: Sprite2D = get_node_or_null("Sprite2D")
	if reset_sprite:
		reset_sprite.scale = Vector2.ONE
	var reset_anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if reset_anim_sprite:
		reset_anim_sprite.scale = Vector2.ONE
	

	
	# Priority 1: AnimatedSprite (asset_anim)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames_res: Resource = load(asset_anim)
		if frames_res is SpriteFrames:
			var frames: SpriteFrames = frames_res as SpriteFrames
			use_asset = true
			visual.visible = false
			_apply_sprite_frames_visual(frames, final_width, final_height, asset_anim_loop, asset_anim_duration)

	# Priority 2: Static Sprite (asset)
	if not use_asset and asset_path != "" and ResourceLoader.exists(asset_path):
		var asset_res: Resource = load(asset_path)
		if asset_res is SpriteFrames:
			use_asset = true
			visual.visible = false
			_apply_sprite_frames_visual(asset_res as SpriteFrames, final_width, final_height, asset_loop, asset_duration)
		elif asset_res is Texture2D:
			var texture: Texture2D = asset_res as Texture2D
			use_asset = true
			visual.visible = false
			
			# Hide anim sprite if exists
			var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
			if anim_sprite:
				anim_sprite.visible = false
			
			var sprite: Sprite2D = get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			# Scale to match target size
			var tex_size: Vector2 = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(final_width / tex_size.x, final_height / tex_size.y)
		else:
			push_warning("[Projectile] Unsupported visual asset type: " + str(asset_res.get_class()) + " (" + asset_path + ")")

	
	# Priority 3: Fallback Polygon2D shape
	if not use_asset:
		var shape_color := Color(visual_data.get("color", "#FFFF00"))
		if is_critical: shape_color = Color.YELLOW
		
		# Hide sprites
		var sprite: Sprite2D = get_node_or_null("Sprite2D")
		if sprite: sprite.visible = false
		var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim_sprite: anim_sprite.visible = false
		
		# Show and configure Polygon2D
		visual.visible = true
		visual.color = shape_color
		
		# Generate shape polygon
		var shape_type: String = str(visual_data.get("shape", "circle"))
		visual.polygon = _create_shape_polygon(shape_type, final_width, final_height)

	# Cache baseline scales for pulsating animation.
	_base_polygon_scale = visual.scale
	var sprite_ref: Sprite2D = get_node_or_null("Sprite2D")
	if sprite_ref:
		_base_sprite_scale = sprite_ref.scale
	else:
		_base_sprite_scale = Vector2.ONE
	var anim_sprite_ref: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite_ref:
		_base_anim_sprite_scale = anim_sprite_ref.scale
	else:
		_base_anim_sprite_scale = Vector2.ONE
	_update_pulsating_visual()

	
	# Collision - use average of width/height
	var avg_size: float = (final_width + final_height) / 2.0
	var col_shape := collision.shape as CircleShape2D
	if col_shape:
		col_shape.radius = avg_size / 2.0

	# Initial rotation
	rotation = direction.angle() + PI / 2
	
	show()
	set_process(true)

func _apply_sprite_frames_visual(frames: SpriteFrames, final_width: float, final_height: float, loop: bool = true, duration: float = 0.0) -> void:
	if frames == null:
		return
	
	var anim_names: PackedStringArray = frames.get_animation_names()
	if anim_names.is_empty():
		push_warning("[Projectile] SpriteFrames has no animation.")
		return
	
	var anim_name: StringName = StringName(anim_names[0])
	if frames.get_frame_count(anim_name) <= 0:
		push_warning("[Projectile] SpriteFrames animation has no frame: " + String(anim_name))
		return
	
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if not anim_sprite:
		anim_sprite = AnimatedSprite2D.new()
		anim_sprite.name = "AnimatedSprite2D"
		add_child(anim_sprite)
	
	anim_sprite.visible = true
	anim_sprite.modulate = Color.WHITE
	var played_anim: StringName = VFXManager.play_sprite_frames(
		anim_sprite,
		frames,
		anim_name,
		loop,
		duration
	)
	if played_anim == &"":
		return
	
	# Scale to match target size
	var playback_frames: SpriteFrames = anim_sprite.sprite_frames
	var frame_tex: Texture2D = null
	if playback_frames:
		frame_tex = playback_frames.get_frame_texture(played_anim, 0)
	if frame_tex:
		var f_size: Vector2 = frame_tex.get_size()
		if f_size.x > 0 and f_size.y > 0:
			anim_sprite.scale = Vector2(final_width / f_size.x, final_height / f_size.y)
	
	# Hide static sprite if exists
	var static_sprite: Sprite2D = get_node_or_null("Sprite2D")
	if static_sprite:
		static_sprite.visible = false

func _create_shape_polygon(shape_type: String, width: float, height: float) -> PackedVector2Array:
	match shape_type:
		"circle":
			return _create_circle_polygon(max(width, height) / 2.0)
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
		_:
			return _create_circle_polygon(max(width, height) / 2.0)

func deactivate(_reason: String = "unknown") -> void:
	# Remove debug
	var debug = get_node_or_null("DEBUG_SQUARE")
	if debug: debug.queue_free()
	
	if is_active:
		# print("[Projectile #%d] Deactivated: reason=%s" % [_debug_id, _reason])
		is_active = false
		hide()
		set_process(false)
		projectile_deactivated.emit(self)

func _process(delta: float) -> void:
	if not is_active:
		return
		
	if _first_frame:
		_first_frame = false
	
	_time_alive += delta
	
	# Apply acceleration
	if _acceleration != 0.0:
		speed += _acceleration * delta
		speed = maxf(speed, 50.0) # Minimum speed
	
	# Lifetime check
	if _time_alive >= _max_lifetime:
		deactivate("lifetime")
		return
	
	_update_pulsating_visual()
	
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
		"homing":
			_move_homing(delta)
		_:
			_move_straight(delta)
	
	# Check hors écran (Marge plus large pour laisser les projectiles "infinis" traverser tout l'espace possible)
	var viewport_size := get_viewport_rect().size
	var margin := 500.0
	if global_position.x < -margin or global_position.x > viewport_size.x + margin \
	or global_position.y < -margin or global_position.y > viewport_size.y + margin:
		# print("[Projectile] Deactivated off-screen at ", global_position)
		deactivate("off_screen")
		return
	if _fluid_id != "":
		FluidManager.emit_fluid(global_position, _fluid_id, direction * speed)

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

func _move_homing(delta: float) -> void:
	# Find target if not set
	if _target == null or not is_instance_valid(_target):
		if is_player_projectile:
			# Target closest enemy
			var enemies := get_tree().get_nodes_in_group("enemies")
			var closest_dist := INF
			for e in enemies:
				if e is Node2D:
					var dist := global_position.distance_to(e.global_position)
					if dist < closest_dist:
						closest_dist = dist
						_target = e
		else:
			# Target player
			_target = get_tree().get_first_node_in_group("player")
	
	if _target and is_instance_valid(_target):
		var to_target: Vector2 = (_target.global_position - global_position).normalized()
		direction = direction.lerp(to_target, _homing_turn_rate * delta).normalized()
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
		# Apply skill tree on-hit effects
		_apply_skill_on_hit(body)
		_spawn_explosion()
		deactivate()
	
	# Projectile joueur touche obstacle destructible (AnimatableBody2D / Pusher)
	elif is_player_projectile and body.is_in_group("destructible_obstacles"):
		if body.has_method("take_damage"):
			body.take_damage(damage, is_critical)
		_spawn_explosion()
		deactivate("hit_obstacle")
	
	# Projectile joueur touche obstacle non-destructible (AnimatableBody2D)
	elif is_player_projectile and body.is_in_group("obstacles"):
		_spawn_explosion()
		deactivate("hit_obstacle")
	
	# Projectile ennemi touche joueur
	elif not is_player_projectile and body.is_in_group("player"):
		# 3. Interaction avec les Projectiles - Check Shield
		var hit_shield = false
		
		# Cas 1: Le body est le Player et possède une méthode de check (Bridge 2D->3D)
		if body.has_method("check_shield_collision"):
			if body.check_shield_collision(self):
				hit_shield = true
		
		if hit_shield:
			print("[Projectile] Blocked by Shield!")
			_spawn_explosion() # Petit effet sticky sur le bouclier
			deactivate("hit_shield")
			return

		# Vérifier dodge côté joueur ou ici ?
		# On laisse le joueur gérer son dodge dans take_damage ou ici ?
		# Pour l'instant on appelle take_damage standard
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_spawn_explosion()
		deactivate()

func _spawn_explosion() -> void:
	if _explosion_data.is_empty():
		return
	
	var size_val: float = float(_explosion_data.get("size", 20))
	var anim_path: String = str(_explosion_data.get("asset_anim", ""))
	var anim_duration: float = maxf(0.0, float(_explosion_data.get("asset_anim_duration", 0.0)))
	var anim_loop: bool = bool(_explosion_data.get("asset_anim_loop", false))
	var asset_path: String = str(_explosion_data.get("asset", ""))
	var color_hex: String = str(_explosion_data.get("color", "#FFAA00"))
	
	# Priority: asset_anim > asset > geometric (color)
	VFXManager.spawn_explosion(
		global_position,
		size_val,
		Color(color_hex),
		get_parent(),
		asset_path,
		anim_path,
		-1.0,
		0.3,
		anim_duration,
		anim_loop
	)
	
	# Fluid explosion burst
	var explosion_fluid: String = str(_explosion_data.get("fluid_id", ""))
	if explosion_fluid == "":
		explosion_fluid = DataManager.get_default_explosion_fluid_id()
	if explosion_fluid != "":
		FluidManager.emit_explosion(global_position, explosion_fluid)

func _on_area_entered(area: Area2D) -> void:
	# Collision avec les murs (Obstacle Waller)
	if area.is_in_group("walls"):
		# _spawn_explosion() # Disabled per request
		deactivate("hit_wall")
	
	# Projectile joueur touche obstacle destructible (Area2D / Explosive)
	elif is_player_projectile and area.is_in_group("destructible_obstacles"):
		if area.has_method("take_damage"):
			area.take_damage(damage, is_critical)
		elif area.get_parent() and area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(damage, is_critical)
		_spawn_explosion()
		deactivate("hit_obstacle")
	
	# Projectile joueur touche obstacle non-destructible (Area2D)
	elif is_player_projectile and area.is_in_group("obstacles"):
		_spawn_explosion()
		deactivate("hit_obstacle")

# =============================================================================
# SKILL TREE ON-HIT EFFECTS
# =============================================================================

func _apply_skill_on_hit(body: Node2D) -> void:
	if skill_modifiers.is_empty():
		return
	if not body.has_method("apply_status_effect"):
		return

	var branch: String = str(skill_modifiers.get("branch", ""))

	match branch:
		"frozen":
			_apply_frozen_effects(body)
		"poison":
			_apply_poison_effects(body)
		"void":
			_apply_void_effects(body)

func _apply_frozen_effects(body: Node2D) -> void:
	# Chill Slow
	var slow_pct := float(skill_modifiers.get("slow_percent", 0.15))
	var max_stacks := int(skill_modifiers.get("max_stacks", 3))
	var chill := StatusEffect.create_chill(slow_pct, max_stacks)
	body.apply_status_effect(chill)

	# Track hits for Deep Freeze
	if skill_modifiers.get("freeze_enabled", false):
		if body.has_method("increment_chill_hit_count"):
			body.increment_chill_hit_count()
			var hit_threshold := int(skill_modifiers.get("freeze_hit_count", 10))
			if body.get_chill_hit_count() >= hit_threshold:
				var freeze_dur := float(skill_modifiers.get("freeze_duration", 2.0))
				var freeze := StatusEffect.create_freeze(freeze_dur)
				body.apply_status_effect(freeze)

	# Ice Shards: if enemy is frozen and we hit it, spawn shards
	if skill_modifiers.get("shatter_enabled", false):
		if "is_frozen" in body and body.is_frozen:
			_spawn_ice_shards(body)

func _apply_poison_effects(body: Node2D) -> void:
	# Poison DoT
	var dot_pct := float(skill_modifiers.get("dot_percent", 0.20))
	var dot_dur := float(skill_modifiers.get("dot_duration", 3.0))
	# Add bonus duration from Plague Spreader
	dot_dur += float(skill_modifiers.get("dot_duration_bonus", 0.0))
	var total_dot_damage := float(damage) * dot_pct
	var poison := StatusEffect.create_poison(total_dot_damage, dot_dur)
	body.apply_status_effect(poison)

	# Corrosive
	if skill_modifiers.get("corrosive_enabled", false):
		var vuln := float(skill_modifiers.get("vulnerability_bonus", 0.25))
		var corrosive := StatusEffect.create_corrosive(vuln, dot_dur)
		body.apply_status_effect(corrosive)

	# Toxic Pool (spawns if the hit didn't kill or was a crit)
	if skill_modifiers.get("pool_enabled", false):
		var should_spawn_pool := false
		if is_critical:
			should_spawn_pool = true
		elif "current_hp" in body and body.current_hp > 0:
			should_spawn_pool = true

		if should_spawn_pool:
			_spawn_toxic_pool(body.global_position)

func _apply_void_effects(body: Node2D) -> void:
	# Void Pull (micro-pull toward impact point)
	var pull_strength := float(skill_modifiers.get("pull_strength", 30.0))
	# Pull toward the player (the shooter)
	var player := get_tree().get_first_node_in_group("player")
	var pull_target := global_position
	if player and is_instance_valid(player):
		pull_target = player.global_position
	var void_pull := StatusEffect.create_void_pull(pull_strength, pull_target)
	body.apply_status_effect(void_pull)

	# Singularity Chance
	if skill_modifiers.get("singularity_enabled", false):
		var chance := float(skill_modifiers.get("singularity_chance", 0.10))
		if randf() <= chance:
			_spawn_singularity(global_position)

func _spawn_ice_shards(body: Node2D) -> void:
	var shard_count: int = int(skill_modifiers.get("shatter_projectile_count", 6))
	var _shard_radius: float = float(skill_modifiers.get("shatter_radius", 80))
	var shard_dmg: int = int(float(damage) * float(skill_modifiers.get("shatter_damage_pct", 0.5)))
	var shard_visual: Dictionary = {
		"color": "#88DDFF",
		"shape": "diamond",
		"size": float(skill_modifiers.get("shard_asset_size", 5.0)),
		"asset": str(skill_modifiers.get("shard_asset", "")),
		"asset_anim": str(skill_modifiers.get("shard_asset_anim", "")),
		"asset_anim_duration": float(skill_modifiers.get("shard_asset_anim_duration", 0.0)),
		"asset_anim_loop": bool(skill_modifiers.get("shard_asset_anim_loop", true))
	}

	# Spawn small projectiles in a radial pattern from the frozen enemy
	for i in range(shard_count):
		var angle: float = (float(i) / float(shard_count)) * TAU
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var shard_pattern: Dictionary = {
			"trajectory": "straight",
			"visual_data": shard_visual
		}
		ProjectileManager.spawn_player_projectile(
			body.global_position, dir, 200.0, shard_dmg, shard_pattern, false
		)

func _spawn_toxic_pool(pos: Vector2) -> void:
	var pool_scene_res: Resource = load("res://scenes/effects/ToxicPool.tscn")
	if pool_scene_res is PackedScene:
		var pool_scene: PackedScene = pool_scene_res as PackedScene
		var pool_node: Node = pool_scene.instantiate()
		if not (pool_node is Node2D):
			return
		var pool: Node2D = pool_node as Node2D
		var container := get_parent()
		if container:
			container.call_deferred("add_child", pool)
			pool.call_deferred("set_global_position", pos)
			if pool.has_method("setup"):
				var pool_radius: float = float(skill_modifiers.get("pool_radius", 50))
				pool_radius *= (1.0 + float(skill_modifiers.get("pool_radius_bonus", 0.0)))
				var pool_duration: float = float(skill_modifiers.get("pool_duration", 3.0))
				var pool_dps: float = float(skill_modifiers.get("pool_damage_per_sec", 8))
				var visual_data: Dictionary = {
					"asset": str(skill_modifiers.get("pool_asset", "")),
					"asset_anim": str(skill_modifiers.get("pool_asset_anim", "")),
					"asset_anim_duration": float(skill_modifiers.get("pool_asset_anim_duration", 0.0)),
					"asset_anim_loop": bool(skill_modifiers.get("pool_asset_anim_loop", true)),
					"size": float(skill_modifiers.get("pool_asset_size", pool_radius * 2.0)),
					"pool_fluid_id": str(skill_modifiers.get("pool_fluid_id", ""))
				}
				pool.call_deferred("setup", pool_radius, pool_duration, pool_dps, visual_data)

func _spawn_singularity(pos: Vector2) -> void:
	var singularity_scene_res: Resource = load("res://scenes/effects/Singularity.tscn")
	if singularity_scene_res is PackedScene:
		var singularity_scene: PackedScene = singularity_scene_res as PackedScene
		var singularity_node: Node = singularity_scene.instantiate()
		if not (singularity_node is Node2D):
			return
		var singularity: Node2D = singularity_node as Node2D
		var container := get_parent()
		if container:
			container.call_deferred("add_child", singularity)
			singularity.call_deferred("set_global_position", pos)
			if singularity.has_method("setup"):
				var s_radius: float = float(skill_modifiers.get("singularity_radius", 80))
				s_radius *= (1.0 + float(skill_modifiers.get("void_radius_bonus", 0.0)))
				var s_duration: float = float(skill_modifiers.get("singularity_duration", 1.0))
				var s_dmg_base: float = float(skill_modifiers.get("singularity_damage_base", 5))
				var s_dmg_exp: float = float(skill_modifiers.get("singularity_damage_exponent", 2.0))
				var has_spaghetti: bool = bool(skill_modifiers.get("spaghettification_enabled", false))
				var visual_data: Dictionary = {
					"asset": str(skill_modifiers.get("singularity_asset", "")),
					"asset_anim": str(skill_modifiers.get("singularity_asset_anim", "")),
					"asset_anim_duration": float(skill_modifiers.get("singularity_asset_anim_duration", 0.0)),
					"asset_anim_loop": bool(skill_modifiers.get("singularity_asset_anim_loop", true)),
					"size": float(skill_modifiers.get("singularity_asset_size", s_radius * 2.0))
				}
				singularity.call_deferred("setup", s_radius, s_duration, s_dmg_base, s_dmg_exp, has_spaghetti, visual_data)

# =============================================================================
# UTILITY
# =============================================================================

func _get_pulsating_multiplier() -> float:
	if not _pulsating_enabled:
		return 1.0
	if _pulsating_frequency <= 0.0:
		return 1.0
	if is_equal_approx(_pulsating_size, 1.0):
		return 1.0
	
	var cycle_time: float = fmod(_time_alive, _pulsating_frequency) / _pulsating_frequency
	var eased_value: float = 0.5 - (0.5 * cos(cycle_time * TAU))
	return lerpf(1.0, _pulsating_size, eased_value)

func _update_pulsating_visual() -> void:
	var pulse_scale: float = _get_pulsating_multiplier()
	visual.scale = _base_polygon_scale * pulse_scale
	
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite:
		sprite.scale = _base_sprite_scale * pulse_scale
	
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite:
		anim_sprite.scale = _base_anim_sprite_scale * pulse_scale

func _create_circle_polygon(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 8
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
