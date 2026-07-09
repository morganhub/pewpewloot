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

# Phases
var phases: Array = []
var current_phase: int = 0

# Movement & Shooting (current phase)
var move_pattern_id: String = "stationary"
var missile_pattern_id: String = "circle_8"
var missile_id: String = "missile_default"
var fire_rate: float = 2.0
var _base_fire_rate: float = 2.0

var _move_pattern_data: Dictionary = {}
var _missile_pattern_data: Dictionary = {}
var _fire_timer: float = 0.0
var _move_time: float = 0.0
var _start_position: Vector2 = Vector2.ZERO
var _move_target_position: Vector2 = Vector2.ZERO
var _move_state: String = "idle"
var _move_pause_timer: float = 0.0
var _move_speed_current: float = 0.0
var _move_cycle_origin: Vector2 = Vector2.ZERO
var _fire_rate_sequence: Array = []
var _fire_rate_sequence_index: int = 0
var _fire_rate_sequence_step_interval: float = 0.0
var _fire_rate_sequence_step_timer: float = 0.0
var _fire_rate_sequence_loop: bool = false
var _rotation_base_deg: float = 0.0
var _shot_rotation_offset_deg: float = 0.0
var _shot_rotation_velocity_deg: float = 0.0

# Special Power
var special_power_id: String = ""
var special_power_interval: float = 10.0
var _special_timer: float = 0.0
var is_invincible: bool = false
var _is_executing_power: bool = false
var _sound_config: Dictionary = {}
var _sound_timer: float = 0.0
var _sound_remaining_repeats: int = 0
var _overdrive_enabled: bool = false
var _overdrive_fire_rate_override: float = 0.05
var _damage_multiplier: float = 1.0
const DEFAULT_MAX_FIRE_RATE: float = 80.0

# Visual
var _boss_anim_duration: float = 2.0
var _boss_anim_frequency: float = 8.0
var _boss_anim_timer: float = 0.0
var _boss_anim_is_playing: bool = false
var _boss_played_anim_name: StringName = &""
@onready var visual_container: Node2D = $Visual
@onready var shape_visual: Polygon2D = $Visual/Shape
@onready var sprite_visual: Sprite2D = $Visual/Sprite2D
@onready var animated_visual: AnimatedSprite2D = $Visual/AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

const STRONG_RESOURCE_CACHE_MAX: int = 256
const DEBUG_BOSS_SETUP_COST_LOG := false
const DEBUG_BOSS_SETUP_COST_THRESHOLD_MS := 4.0
static var _strong_resource_cache: Dictionary = {}  # path -> Resource
static var _first_frame_texture_cache: Dictionary = {}  # frame_key -> Texture2D

# =============================================================================
# SETUP
# =============================================================================

func setup(boss_data: Dictionary) -> void:
	var t0_usec: int = 0
	if DEBUG_BOSS_SETUP_COST_LOG:
		t0_usec = Time.get_ticks_usec()

	boss_id = str(boss_data.get("id", "boss_unknown"))
	boss_name = str(boss_data.get("name", "Boss"))
	max_hp = int(boss_data.get("hp", 500))
	current_hp = max_hp
	score = int(boss_data.get("score", 1000))
	missile_id = str(boss_data.get("missile_id", "missile_default"))
	
	# Charger les phases
	var raw_phases: Variant = boss_data.get("phases", [])
	if raw_phases is Array:
		phases = raw_phases as Array

	_start_position = global_position
	
	# Initialiser la phase 1
	if not phases.is_empty():
		_apply_phase(0)
	
	# Initialiser les sons
	var sounds_data: Variant = boss_data.get("sounds", {})
	if sounds_data is Dictionary:
		_sound_config = sounds_data as Dictionary
		_sound_remaining_repeats = int(_sound_config.get("repeat", 0))
		_sound_timer = float(_sound_config.get("interval", 0))
		# Si -1 ou > 0, on démarre le premier son après l'intervalle (ou immédiatement ?)
		# On va lancer immédiatement si on a un repeat prévu.
		if _sound_remaining_repeats != 0:
			_play_boss_sound()
	var t_before_visual_usec: int = 0
	if DEBUG_BOSS_SETUP_COST_LOG:
		t_before_visual_usec = Time.get_ticks_usec()
	
	# Visual setup
	_setup_visual(boss_data)
	var t_after_visual_usec: int = 0
	if DEBUG_BOSS_SETUP_COST_LOG:
		t_after_visual_usec = Time.get_ticks_usec()
	
	_reset_visual_rotation()
	_fire_timer = randf_range(0.0, _get_effective_fire_rate())

	if DEBUG_BOSS_SETUP_COST_LOG:
		var t_end_usec: int = Time.get_ticks_usec()
		var total_ms: float = float(t_end_usec - t0_usec) / 1000.0
		if total_ms >= DEBUG_BOSS_SETUP_COST_THRESHOLD_MS:
			var pre_visual_ms: float = float(t_before_visual_usec - t0_usec) / 1000.0
			var visual_ms: float = float(t_after_visual_usec - t_before_visual_usec) / 1000.0
			var post_ms: float = float(t_end_usec - t_after_visual_usec) / 1000.0
			print(
				"[BossSetup] total=", snappedf(total_ms, 0.1), "ms",
				" pre_visual=", snappedf(pre_visual_ms, 0.1), "ms",
				" visual=", snappedf(visual_ms, 0.1), "ms",
				" post=", snappedf(post_ms, 0.1), "ms",
				" boss=", boss_id
			)
	
	print("[Boss] ", boss_name, " spawned with ", max_hp, " HP and ", phases.size(), " phases")

func _setup_visual(boss_data: Dictionary) -> void:
	var size_data: Variant = boss_data.get("size", {"width": 100, "height": 100})
	var width: float = 100.0
	var height: float = 100.0
	
	if size_data is Dictionary:
		var size_dict := size_data as Dictionary
		width = float(size_dict.get("width", 100))
		height = float(size_dict.get("height", 100))
	
	# Taille affichée utilisée pour la hitbox (sans dépasser le visible)
	var displayed_w: float = width
	var displayed_h: float = height
	
	# Gestion de l'asset vs shape vs anim
	var visual_data: Variant = boss_data.get("visual", {})
	var asset_path: String = ""
	var asset_anim: String = ""
	var asset_anim_duration: float = 0.0
	var _asset_anim_loop: bool = true
	var color_hex: String = "#AA44FF"
	var shape_type: String = "hexagon"
	
	if visual_data is Dictionary:
		var v_dict := visual_data as Dictionary
		asset_path = str(v_dict.get("asset", ""))
		asset_anim = str(v_dict.get("asset_anim", ""))
		asset_anim_duration = maxf(0.0, float(v_dict.get("asset_anim_duration", 2.0)))
		_boss_anim_duration = asset_anim_duration
		_boss_anim_frequency = maxf(0.0, float(v_dict.get("asset_anim_frequency", 8.0)))
		_boss_anim_timer = 0.0 # Force immediate first play
		_boss_anim_is_playing = false
		_asset_anim_loop = false # Force false for boss animations
		color_hex = str(v_dict.get("color", "#AA44FF"))
		shape_type = str(v_dict.get("shape", "hexagon"))
	
	var use_asset: bool = false
	
	# Priority 1: AnimatedSprite (asset_anim)
	if asset_anim != "":
		var sprite_frames: Resource = _load_cached_resource(asset_anim, "asset_anim")
		if sprite_frames is SpriteFrames:
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = animated_visual
			if not anim_sprite:
				anim_sprite = AnimatedSprite2D.new()
				anim_sprite.name = "AnimatedSprite2D"
				visual_container.add_child(anim_sprite)
				animated_visual = anim_sprite
			
			anim_sprite.visible = true
			var played_anim: StringName = &""
			var frames_data: SpriteFrames = sprite_frames as SpriteFrames
			var default_anim: StringName = VFXManager.get_first_animation_name(frames_data, &"default")
			played_anim = default_anim
			_boss_played_anim_name = default_anim
			if played_anim != &"":
				anim_sprite.sprite_frames = frames_data
				anim_sprite.animation = played_anim
				anim_sprite.stop()
				anim_sprite.frame = 0
				
				# Adjust speed scale to match duration
				var speed_fps := frames_data.get_animation_speed(played_anim)
				var frames_count := frames_data.get_frame_count(played_anim)
				if _boss_anim_duration > 0.0 and speed_fps > 0 and frames_count > 0:
					var original_duration := float(frames_count) / speed_fps
					anim_sprite.speed_scale = original_duration / _boss_anim_duration
				else:
					anim_sprite.speed_scale = 1.0
			
			# Scale: respect aspect ratio (one dimension constrained, other adapts), no stretch
			var frame_tex: Texture2D = null
			if played_anim != &"" and anim_sprite.sprite_frames:
				frame_tex = _get_cached_first_frame_texture(anim_sprite.sprite_frames, played_anim)
			if frame_tex:
				var f_size: Vector2 = frame_tex.get_size()
				if f_size.x > 0 and f_size.y > 0:
					var scale_factor: float = minf(width / f_size.x, height / f_size.y)
					anim_sprite.scale = Vector2(scale_factor, scale_factor)
					displayed_w = f_size.x * scale_factor
					displayed_h = f_size.y * scale_factor
				else:
					anim_sprite.scale = Vector2(width / 100.0, height / 100.0)
			else:
				anim_sprite.scale = Vector2(width / 100.0, height / 100.0)
			
			# Hide static sprite
			var sprite: Sprite2D = sprite_visual
			if sprite: sprite.visible = false
	
	# Priority 2: Static Sprite (asset)
	if not use_asset and asset_path != "":
		var texture_res: Resource = _load_cached_resource(asset_path, "asset")
		if texture_res is Texture2D:
			var texture: Texture2D = texture_res as Texture2D
			use_asset = true
			shape_visual.visible = false
			
			var anim_sprite: AnimatedSprite2D = animated_visual
			if anim_sprite: anim_sprite.visible = false
			
			var sprite: Sprite2D = sprite_visual
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				visual_container.add_child(sprite)
				sprite_visual = sprite
			
			sprite.visible = true
			sprite.texture = texture
			
			# Scale: respect aspect ratio, no stretch; hitbox = displayed size
			var tex_size: Vector2 = texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				var scale_factor: float = minf(width / tex_size.x, height / tex_size.y)
				sprite.scale = Vector2(scale_factor, scale_factor)
				displayed_w = tex_size.x * scale_factor
				displayed_h = tex_size.y * scale_factor
			else:
				sprite.scale = Vector2(width / 100.0, height / 100.0)
	
	if not use_asset:
		var color := Color(color_hex)
		
		var sprite: Sprite2D = sprite_visual
		if sprite: sprite.visible = false
		var anim_sprite: AnimatedSprite2D = animated_visual
		if anim_sprite: anim_sprite.visible = false
		
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width * 1.2, height * 1.2)
	
	# Collision: ne pas dépasser le visible (cercle inscrit dans la taille affichée)
	var circle_shape := CircleShape2D.new()
	if use_asset:
		circle_shape.radius = minf(displayed_w, displayed_h) / 2.0
	else:
		circle_shape.radius = (maxf(width, height) / 2.0) * 1.2
	collision.shape = circle_shape

	# Physics Layer Setup
	collision_layer = 4 # Layer 3: Enemy
	collision_mask = 1 + 8 # World + PlayerProjectiles (No Player)

func _load_cached_resource(path: String, _debug_label: String = "") -> Resource:
	if path == "":
		return null
	if _strong_resource_cache.has(path):
		var strong_cached: Variant = _strong_resource_cache[path]
		if strong_cached is Resource:
			return strong_cached as Resource

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

func set_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = maxf(0.0, multiplier)

func get_contact_damage() -> int:
	# Dégâts de contact du boss (assez élevés)
	var dmg: int = 20
	if not _missile_pattern_data.is_empty():
		dmg = int(_missile_pattern_data.get("damage", 20))
	return int(float(dmg) * _damage_multiplier)

# =============================================================================
# LIFECYCLE
# =============================================================================

func _process(delta: float) -> void:
	# Si en train d'exécuter un pouvoir (cinématique), on skip le mouvement standard ?
	# PowerManager gère les mouvements si besoin via Tweens.
	# On garde le mouvement standard sauf si le power lock le boss.
	# Pour l'instant on laisse tourner en parallèle.
	
	if not _is_executing_power:
		_update_movement(delta)
	_update_phase_modulators(delta)
	
	_update_shooting(delta)
	_update_special_power(delta)
	_update_sounds(delta)
	_update_visual_animation(delta)
	_check_phase_transition()

func _update_visual_animation(delta: float) -> void:
	if not is_instance_valid(animated_visual) or not animated_visual.visible or _boss_played_anim_name == &"":
		return
		
	_boss_anim_timer -= delta
	
	if _boss_anim_is_playing:
		if _boss_anim_timer <= 0.0:
			animated_visual.stop()
			animated_visual.frame = 0 # Retourne à la première frame
			_boss_anim_is_playing = false
			_boss_anim_timer = _boss_anim_frequency
	else:
		if _boss_anim_timer <= 0.0:
			animated_visual.play(_boss_played_anim_name)
			_boss_anim_is_playing = true
			_boss_anim_timer = _boss_anim_duration

func _update_phase_modulators(delta: float) -> void:
	if _fire_rate_sequence_step_interval > 0.0 and _fire_rate_sequence.size() > 1:
		_fire_rate_sequence_step_timer -= delta
		if _fire_rate_sequence_step_timer <= 0.0:
			if _fire_rate_sequence_index < _fire_rate_sequence.size() - 1:
				_fire_rate_sequence_index += 1
			elif _fire_rate_sequence_loop:
				_fire_rate_sequence_index = 0
			_fire_rate_sequence_step_timer = _fire_rate_sequence_step_interval

	_shot_rotation_offset_deg += _shot_rotation_velocity_deg * delta
	_shot_rotation_velocity_deg = move_toward(_shot_rotation_velocity_deg, 0.0, 900.0 * delta)
	_shot_rotation_offset_deg = lerpf(_shot_rotation_offset_deg, 0.0, minf(1.0, delta * 9.0))
	visual_container.rotation_degrees = _rotation_base_deg + _shot_rotation_offset_deg

func _update_special_power(delta: float) -> void:
	if special_power_id == "": return
	
	_special_timer -= delta
	if _special_timer <= 0:
		_trigger_special_power()
		_special_timer = special_power_interval

func _trigger_special_power() -> void:
	print("[Boss] Triggering Special Power: ", special_power_id)
	PowerManager.execute_power(special_power_id, self)

func set_invincible(state: bool) -> void:
	is_invincible = state
	if is_invincible:
		modulate.a = 0.7
		# VFX shield ?
		VFXManager.spawn_floating_text(global_position, "SHIELD UP!", Color.CYAN, get_parent())
	else:
		modulate.a = 1.0

func set_overdrive_enabled(enabled: bool, fire_rate_override: float = 0.05) -> void:
	_overdrive_enabled = enabled
	_overdrive_fire_rate_override = _clamp_fire_interval(maxf(0.01, fire_rate_override))
	if _overdrive_enabled:
		_fire_timer = minf(_fire_timer, _overdrive_fire_rate_override)
		_special_timer = minf(_special_timer, 0.15)

func _update_sounds(delta: float) -> void:
	if _sound_remaining_repeats == 0: return
	
	var interval: float = float(_sound_config.get("interval", 1.0))
	if interval <= 0: return
	
	_sound_timer -= delta
	if _sound_timer <= 0:
		_play_boss_sound()
		_sound_timer = interval
		
		# Gérer le décompte des répétitions (si pas infini)
		if _sound_remaining_repeats > 0:
			_sound_remaining_repeats -= 1

func _play_boss_sound() -> void:
	var asset: String = str(_sound_config.get("asset", ""))
	if asset != "":
		AudioManager.play_sfx(asset)

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
		_start_position = global_position
		move_pattern_id = str(phase_dict.get("move_pattern_id", "stationary"))
		missile_pattern_id = str(phase_dict.get("missile_pattern_id", "circle_8"))
		if phase_dict.has("missile_id"):
			missile_id = str(phase_dict.get("missile_id", "missile_default"))
		_base_fire_rate = _clamp_fire_interval(maxf(0.05, float(phase_dict.get("fire_rate", 2.0))))
		fire_rate = _base_fire_rate
		_move_pattern_data = _resolve_move_pattern_data(move_pattern_id)

		# Optional phase-based firing cadence
		_configure_fire_profile(phase_dict)

		_reset_visual_rotation()
		_reset_movement_state()
		
		_missile_pattern_data = DataManager.get_enemy_missile_pattern(missile_pattern_id)
		
		# Load special power settings
		special_power_id = str(phase_dict.get("special_power_id", ""))
		special_power_interval = float(phase_dict.get("special_power_interval", 10.0))
		_special_timer = special_power_interval # Reset timer on phase change
		if _overdrive_enabled:
			_fire_timer = minf(_fire_timer, _overdrive_fire_rate_override)
			_special_timer = minf(_special_timer, 0.15)
		
		print("[Boss] Phase ", current_phase + 1, " activated!")
		phase_changed.emit(current_phase + 1)
		
		# VFX de changement de phase
		VFXManager.screen_shake(15, 0.5)
		VFXManager.flash_sprite(visual_container, Color.WHITE, 0.3)

func _configure_fire_profile(phase_dict: Dictionary) -> void:
	_fire_rate_sequence.clear()
	_fire_rate_sequence_index = 0
	_fire_rate_sequence_step_interval = 0.0
	_fire_rate_sequence_step_timer = 0.0
	_fire_rate_sequence_loop = false

	var raw_profile: Variant = phase_dict.get("fire_profile", null)
	if not (raw_profile is Dictionary):
		return

	var profile := raw_profile as Dictionary
	var raw_rates: Variant = profile.get("rates", [])
	if raw_rates is Array:
		for rate in raw_rates:
			_fire_rate_sequence.append(_clamp_fire_interval(maxf(0.05, float(rate))))

	if _fire_rate_sequence.is_empty():
		return

	_fire_rate_sequence_step_interval = maxf(0.0, float(profile.get("step_interval", 0.0)))
	_fire_rate_sequence_step_timer = _fire_rate_sequence_step_interval
	_fire_rate_sequence_loop = bool(profile.get("loop", false))

func _reset_visual_rotation() -> void:
	_rotation_base_deg = 0.0
	_shot_rotation_offset_deg = 0.0
	_shot_rotation_velocity_deg = 0.0
	visual_container.rotation_degrees = 0.0

func _resolve_move_pattern_data(pattern_id: String) -> Dictionary:
	var data: Dictionary = DataManager.get_move_pattern(pattern_id)
	if data.is_empty():
		return _legacy_boss_move_pattern(pattern_id)

	var normalized := data.duplicate(true)
	var pattern_type: String = str(normalized.get("type", ""))
	if pattern_type == "proc":
		var proc_func: String = str(normalized.get("proc_func", ""))
		match proc_func:
			"sine_wave_vertical":
				normalized["type"] = "sine_wave"
				normalized["amplitude"] = float(normalized.get("amplitude", 160.0))
				normalized["frequency"] = float(normalized.get("frequency", 0.45))
			"figure_eight_vertical":
				normalized["type"] = "figure_eight"
				normalized["radius"] = float(normalized.get("radius", 140.0))
				normalized["frequency"] = float(normalized.get("frequency", 0.40))
			"impatient_circle":
				normalized["type"] = "circular"
				normalized["radius"] = float(normalized.get("radius", 140.0))
				normalized["angular_speed"] = float(normalized.get("angular_speed", 0.8))
				normalized["clockwise"] = true
			_:
				normalized = _legacy_boss_move_pattern(pattern_id)
	elif pattern_type == "resource":
		normalized = _legacy_boss_move_pattern(pattern_id)

	if normalized.is_empty():
		return _legacy_boss_move_pattern(pattern_id)
	return normalized

func _legacy_boss_move_pattern(pattern_id: String) -> Dictionary:
	match pattern_id:
		"boss_hold_center":
			return {
				"type": "hold",
				"x_offset": 0.0,
				"speed": 110.0,
				"shot_spin_deg": 7.0,
				"shot_spin_velocity_deg": 180.0
			}
		"boss_hold_left":
			return {
				"type": "hold",
				"x_offset": -150.0,
				"speed": 120.0,
				"shot_spin_deg": 8.0,
				"shot_spin_velocity_deg": 190.0
			}
		"boss_hold_right":
			return {
				"type": "hold",
				"x_offset": 150.0,
				"speed": 120.0,
				"shot_spin_deg": 8.0,
				"shot_spin_velocity_deg": 190.0
			}
		"boss_strafe_narrow":
			return {
				"type": "strafe_random",
				"x_range": 90.0,
				"speed_min": 90.0,
				"speed_max": 140.0,
				"pause_min": 0.45,
				"pause_max": 0.9,
				"shot_spin_deg": 8.0,
				"shot_spin_velocity_deg": 200.0
			}
		"boss_strafe_medium":
			return {
				"type": "strafe_random",
				"x_range": 140.0,
				"speed_min": 120.0,
				"speed_max": 185.0,
				"pause_min": 0.25,
				"pause_max": 0.65,
				"shot_spin_deg": 10.0,
				"shot_spin_velocity_deg": 220.0
			}
		"boss_strafe_wide":
			return {
				"type": "strafe_random",
				"x_range": 220.0,
				"speed_min": 140.0,
				"speed_max": 220.0,
				"pause_min": 0.15,
				"pause_max": 0.45,
				"shot_spin_deg": 11.0,
				"shot_spin_velocity_deg": 235.0
			}
		"boss_strafe_stop":
			return {
				"type": "strafe_random",
				"x_range": 180.0,
				"speed_min": 90.0,
				"speed_max": 165.0,
				"pause_min": 0.65,
				"pause_max": 1.25,
				"shot_spin_deg": 9.0,
				"shot_spin_velocity_deg": 210.0
			}
		"boss_strafe_erratic":
			return {
				"type": "strafe_random",
				"x_range": 240.0,
				"speed_min": 150.0,
				"speed_max": 280.0,
				"pause_min": 0.0,
				"pause_max": 0.3,
				"shot_spin_deg": 12.0,
				"shot_spin_velocity_deg": 255.0
			}
		"boss_strafe_hold":
			return {
				"type": "strafe_random",
				"x_range": 150.0,
				"speed_min": 80.0,
				"speed_max": 130.0,
				"pause_min": 0.9,
				"pause_max": 1.55,
				"shot_spin_deg": 8.0,
				"shot_spin_velocity_deg": 190.0
			}
		"boss_advance_short":
			return {
				"type": "advance_return",
				"x_range": 100.0,
				"advance_distance": 95.0,
				"reposition_speed_min": 90.0,
				"reposition_speed_max": 150.0,
				"advance_speed_min": 210.0,
				"advance_speed_max": 290.0,
				"return_speed_min": 170.0,
				"return_speed_max": 240.0,
				"pause_min": 0.25,
				"pause_max": 0.5,
				"linger_min": 0.18,
				"linger_max": 0.35,
				"cooldown_min": 0.7,
				"cooldown_max": 1.1,
				"shot_spin_deg": 12.0,
				"shot_spin_velocity_deg": 260.0
			}
		"boss_advance_medium":
			return {
				"type": "advance_return",
				"x_range": 130.0,
				"advance_distance": 150.0,
				"reposition_speed_min": 110.0,
				"reposition_speed_max": 175.0,
				"advance_speed_min": 260.0,
				"advance_speed_max": 350.0,
				"return_speed_min": 190.0,
				"return_speed_max": 280.0,
				"pause_min": 0.2,
				"pause_max": 0.4,
				"linger_min": 0.14,
				"linger_max": 0.3,
				"cooldown_min": 0.55,
				"cooldown_max": 0.95,
				"shot_spin_deg": 13.0,
				"shot_spin_velocity_deg": 280.0
			}
		"boss_advance_long":
			return {
				"type": "advance_return",
				"x_range": 160.0,
				"advance_distance": 220.0,
				"reposition_speed_min": 125.0,
				"reposition_speed_max": 195.0,
				"advance_speed_min": 320.0,
				"advance_speed_max": 430.0,
				"return_speed_min": 220.0,
				"return_speed_max": 330.0,
				"pause_min": 0.12,
				"pause_max": 0.28,
				"linger_min": 0.12,
				"linger_max": 0.22,
				"cooldown_min": 0.45,
				"cooldown_max": 0.8,
				"shot_spin_deg": 14.0,
				"shot_spin_velocity_deg": 300.0
			}
		"circle_clockwise":
			return {
				"type": "strafe_random",
				"x_range": 140.0,
				"speed_min": 110.0,
				"speed_max": 170.0,
				"pause_min": 0.25,
				"pause_max": 0.6
			}
		"bounce_horizontal":
			return {
				"type": "strafe_random",
				"x_range": 190.0,
				"speed_min": 120.0,
				"speed_max": 200.0,
				"pause_min": 0.15,
				"pause_max": 0.45
			}
		"figure_eight":
			return {
				"type": "advance_return",
				"x_range": 120.0,
				"advance_distance": 125.0,
				"reposition_speed_min": 105.0,
				"reposition_speed_max": 165.0,
				"advance_speed_min": 220.0,
				"advance_speed_max": 320.0,
				"return_speed_min": 180.0,
				"return_speed_max": 250.0,
				"pause_min": 0.2,
				"pause_max": 0.4,
				"linger_min": 0.16,
				"linger_max": 0.3,
				"cooldown_min": 0.6,
				"cooldown_max": 0.95
			}
		"random_strafe":
			return {
				"type": "strafe_random",
				"x_range": 240.0,
				"speed_min": 145.0,
				"speed_max": 260.0,
				"pause_min": 0.0,
				"pause_max": 0.35
			}
		_:
			return {
				"type": "static",
				"speed": 0.0
			}

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
		"hold":
			_move_hold(delta, move_speed)
		"strafe_random":
			_move_strafe_random(delta)
		"advance_return":
			_move_advance_return(delta)
		"circular":
			_move_circular(delta, move_speed)
		"sine_wave":
			_move_sine_wave(delta, move_speed)
		"figure_eight":
			_move_figure_eight(delta, move_speed)
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

func _move_figure_eight(_delta: float, _speed: float) -> void:
	var radius: float = float(_move_pattern_data.get("radius", 140.0))
	var frequency: float = float(_move_pattern_data.get("frequency", 0.35))
	var t: float = _move_time * frequency * TAU
	var x: float = sin(t) * radius
	var y: float = sin(2.0 * t) * (radius * 0.45)
	global_position = _start_position + Vector2(x, y)

func _move_homing(delta: float, speed: float) -> void:
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node and player_node is Node2D:
		var player := player_node as Node2D
		var to_player: Vector2 = (player.global_position - global_position).normalized()
		velocity = velocity.lerp(to_player * speed, delta * 2.0)
		move_and_slide()

func _reset_movement_state() -> void:
	_move_time = 0.0
	_move_state = "idle"
	_move_pause_timer = 0.0
	_move_speed_current = 0.0
	_move_cycle_origin = _start_position
	_move_target_position = _start_position
	velocity = Vector2.ZERO

	var pattern_type := str(_move_pattern_data.get("type", "static"))
	match pattern_type:
		"hold":
			_move_target_position = Vector2(_get_hold_target_x(), _start_position.y)
			_move_speed_current = maxf(1.0, float(_move_pattern_data.get("speed", 110.0)))
		"strafe_random":
			_select_next_strafe_target()
		"advance_return":
			_queue_next_advance_cycle()
		_:
			pass

func set_spawn_anchor_to_current_position() -> void:
	_start_position = global_position
	_reset_movement_state()

func _move_hold(delta: float, speed: float) -> void:
	var target := Vector2(_get_hold_target_x(), _start_position.y)
	global_position = global_position.move_toward(target, maxf(1.0, speed) * delta)

func _move_strafe_random(delta: float) -> void:
	if _move_pause_timer > 0.0:
		_move_pause_timer -= delta
		if _move_pause_timer <= 0.0:
			_select_next_strafe_target()
		return

	global_position = global_position.move_toward(_move_target_position, _move_speed_current * delta)
	if global_position.distance_to(_move_target_position) <= 4.0:
		global_position = _move_target_position
		_move_pause_timer = _random_from_pattern("pause_min", "pause_max", 0.2, 0.6)

func _move_advance_return(delta: float) -> void:
	match _move_state:
		"reposition":
			global_position = global_position.move_toward(_move_target_position, _move_speed_current * delta)
			if global_position.distance_to(_move_target_position) <= 4.0:
				global_position = _move_target_position
				_move_cycle_origin = _move_target_position
				_move_pause_timer = _random_from_pattern("pause_min", "pause_max", 0.2, 0.4)
				_move_state = "prepare_lunge"
		"prepare_lunge":
			_move_pause_timer -= delta
			if _move_pause_timer <= 0.0:
				var x_jitter: float = float(_move_pattern_data.get("advance_x_jitter", 24.0))
				var lunge_x := clampf(
					_move_cycle_origin.x + randf_range(-x_jitter, x_jitter),
					_get_horizontal_min_limit(),
					_get_horizontal_max_limit()
				)
				_move_target_position = Vector2(
					lunge_x,
					_start_position.y + float(_move_pattern_data.get("advance_distance", 120.0))
				)
				_move_speed_current = _random_from_pattern("advance_speed_min", "advance_speed_max", 220.0, 320.0)
				_move_state = "lunge"
		"lunge":
			global_position = global_position.move_toward(_move_target_position, _move_speed_current * delta)
			if global_position.distance_to(_move_target_position) <= 4.0:
				global_position = _move_target_position
				_move_pause_timer = _random_from_pattern("linger_min", "linger_max", 0.12, 0.3)
				_move_state = "linger"
		"linger":
			_move_pause_timer -= delta
			if _move_pause_timer <= 0.0:
				_move_target_position = _move_cycle_origin
				_move_speed_current = _random_from_pattern("return_speed_min", "return_speed_max", 180.0, 260.0)
				_move_state = "return"
		"return":
			global_position = global_position.move_toward(_move_target_position, _move_speed_current * delta)
			if global_position.distance_to(_move_target_position) <= 4.0:
				global_position = _move_target_position
				_move_pause_timer = _random_from_pattern("cooldown_min", "cooldown_max", 0.55, 0.95)
				_move_state = "cooldown"
		"cooldown":
			_move_pause_timer -= delta
			if _move_pause_timer <= 0.0:
				_queue_next_advance_cycle()
		_:
			_queue_next_advance_cycle()

func _select_next_strafe_target() -> void:
	_move_target_position = Vector2(_pick_random_horizontal_target(), _start_position.y)
	_move_speed_current = _random_from_pattern("speed_min", "speed_max", 100.0, 160.0)

func _queue_next_advance_cycle() -> void:
	_move_cycle_origin = Vector2(_pick_random_horizontal_target(), _start_position.y)
	_move_target_position = _move_cycle_origin
	_move_speed_current = _random_from_pattern("reposition_speed_min", "reposition_speed_max", 90.0, 150.0)
	_move_state = "reposition"

func _get_hold_target_x() -> float:
	var offset: float = float(_move_pattern_data.get("x_offset", 0.0))
	return clampf(_start_position.x + offset, _get_horizontal_min_limit(), _get_horizontal_max_limit())

func _pick_random_horizontal_target() -> float:
	var x_range: float = float(_move_pattern_data.get("x_range", 120.0))
	var x_bias: float = float(_move_pattern_data.get("x_bias", 0.0))
	var target_x := randf_range((_start_position.x + x_bias) - x_range, (_start_position.x + x_bias) + x_range)
	return clampf(target_x, _get_horizontal_min_limit(), _get_horizontal_max_limit())

func _get_horizontal_min_limit() -> float:
	return 70.0

func _get_horizontal_max_limit() -> float:
	return get_viewport_rect().size.x - 70.0

func _random_from_pattern(min_key: String, max_key: String, default_min: float, default_max: float) -> float:
	return randf_range(
		float(_move_pattern_data.get(min_key, default_min)),
		float(_move_pattern_data.get(max_key, default_max))
	)

# =============================================================================
# SHOOTING (Copié d'Enemy.gd)
# =============================================================================

func _update_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0:
		_fire()
		var next_interval: float = _clamp_fire_interval(_get_effective_fire_rate())
		var cooldown: float = float(_missile_pattern_data.get("cooldown_after_salve", 0.0))
		_fire_timer = next_interval + cooldown

func _get_effective_fire_rate() -> float:
	if _overdrive_enabled:
		return _clamp_fire_interval(_overdrive_fire_rate_override)
	if _fire_rate_sequence.is_empty():
		return _clamp_fire_interval(maxf(0.05, _base_fire_rate))
	var idx: int = clampi(_fire_rate_sequence_index, 0, _fire_rate_sequence.size() - 1)
	return _clamp_fire_interval(maxf(0.05, float(_fire_rate_sequence[idx])))

func _clamp_fire_interval(interval_sec: float) -> float:
	return maxf(_get_min_fire_interval(), interval_sec)

func _get_min_fire_interval() -> float:
	var game_cfg: Dictionary = DataManager.get_game_config() if DataManager else {}
	var balance_raw: Variant = game_cfg.get("game_balance", {})
	var balance: Dictionary = balance_raw if balance_raw is Dictionary else {}
	var max_rate: float = maxf(0.01, float(balance.get("fire_rate_max", DEFAULT_MAX_FIRE_RATE)))
	return 1.0 / max_rate

func _fire() -> void:
	if _missile_pattern_data.is_empty():
		return

	_trigger_fire_rotation()
	
	var projectile_count: int = int(_missile_pattern_data.get("projectile_count", 1))
	var spread_angle: float = float(_missile_pattern_data.get("spread_angle", 0))
	var trajectory := str(_missile_pattern_data.get("trajectory", "straight"))
	var speed: float = float(_missile_pattern_data.get("speed", 200))
	var damage: int = int(float(_missile_pattern_data.get("damage", 15)) * _damage_multiplier)
	var spawn_strategy: String = str(_missile_pattern_data.get("spawn_strategy", "shooter"))
	
	# Injecter les data visuelles du missile
	var missile_data := DataManager.get_missile(missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		_missile_pattern_data["visual_data"] = visual_data
	
	# Inject acceleration from missile
	var acceleration: float = float(missile_data.get("acceleration", 0.0))
	_missile_pattern_data["acceleration"] = acceleration

	# Optional homing lock duration override from missile data.
	if not _missile_pattern_data.has("homing_duration"):
		var homing_duration: float = float(missile_data.get("homing_duration", -1.0))
		if homing_duration >= 0.0:
			_missile_pattern_data["homing_duration"] = homing_duration
	
	# Inject explosion data from missile
	var missile_explosion: Dictionary = missile_data.get("explosion", {})
	if not missile_explosion.is_empty() and missile_explosion.keys().size() > 0:
		_missile_pattern_data["explosion_data"] = missile_explosion
	
	# Play sound (once per salvo)
	var sound_path: String = str(missile_data.get("sound", ""))
	if sound_path != "":
		AudioManager.play_sfx(sound_path, 0.1)
		
	# Get spawn positions based on strategy
	var spawn_positions: Array = _get_spawn_positions(spawn_strategy, projectile_count)
	var player_node: Node2D = get_tree().get_first_node_in_group("player")
	
	var is_aimed := (trajectory == "aimed") or bool(_missile_pattern_data.get("aim_target", false))
	
	# Special case for radial
	if trajectory == "radial" and spawn_strategy == "shooter":
		for i in range(projectile_count):
			var angle: float = (i / float(projectile_count)) * TAU
			var direction := Vector2(cos(angle), sin(angle))
			ProjectileManager.spawn_enemy_projectile(global_position, direction, speed, damage, _missile_pattern_data)
		return
	
	for i in range(spawn_positions.size()):
		var spawn_pos: Vector2 = spawn_positions[i]
		var direction: Vector2 = Vector2.DOWN
		
		if is_aimed and player_node:
			direction = (player_node.global_position - spawn_pos).normalized()
		else:
			direction = _get_default_direction(spawn_strategy, spawn_pos)
		
		# Apply spread angle if multiple projectiles from same position
		if spawn_strategy == "shooter" and projectile_count > 1:
			var angle_step: float = deg_to_rad(spread_angle) / max(1, projectile_count - 1)
			var start_angle: float = -deg_to_rad(spread_angle) / 2.0
			var angle: float = start_angle + angle_step * i
			direction = direction.rotated(angle)
		
		ProjectileManager.spawn_enemy_projectile(spawn_pos, direction, speed, damage, _missile_pattern_data)

func _trigger_fire_rotation() -> void:
	var spin_deg: float = float(_move_pattern_data.get("shot_spin_deg", 10.0))
	var spin_velocity: float = float(_move_pattern_data.get("shot_spin_velocity_deg", 220.0))
	var direction := -1.0 if (randi() % 2) == 0 else 1.0
	_shot_rotation_offset_deg = clampf(_shot_rotation_offset_deg + (direction * spin_deg), -24.0, 24.0)
	_shot_rotation_velocity_deg = direction * spin_velocity

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
			var half: int = int(floor(float(count) * 0.5))
			var step_y: float = viewport_size.y / max(1, half)
			for i in range(half):
				positions.append(Vector2(-20, step_y * i + step_y / 2))
				positions.append(Vector2(viewport_size.x + 20, step_y * i + step_y / 2))
		
		"random_edge":
			for i in range(count):
				var edge: int = randi() % 4
				var pos: Vector2
				match edge:
					0:
						pos = Vector2(randf_range(0, viewport_size.x), -20)
					1:
						pos = Vector2(randf_range(0, viewport_size.x), viewport_size.y + 20)
					2:
						pos = Vector2(-20, randf_range(0, viewport_size.y))
					3:
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

# =============================================================================
# DAMAGE & DEATH
# =============================================================================

func take_damage(amount: int, is_critical: bool = false) -> void:
	if is_invincible:
		VFXManager.spawn_floating_text(global_position, "IMMUNE", Color.GRAY, get_parent())
		return

	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	# VFX hit
	var flash_color := Color.WHITE
	if is_critical:
		flash_color = Color.YELLOW
		VFXManager.spawn_floating_text(global_position, "CRIT!", Color.YELLOW, get_parent())
	
	VFXManager.flash_sprite(visual_container, flash_color, 0.1)
	VFXManager.screen_shake(5, 0.1)
	
	# Play SFX (Boss Hit)
	var sfx_config = DataManager.get_game_data().get("gameplay", {}).get("sfx", {}).get("collisions", {})
	var sfx_path = str(sfx_config.get("boss", ""))
	if sfx_path != "":
		AudioManager.play_sfx(sfx_path, 0.1)
	
	health_changed.emit(current_hp, max_hp)
	_check_phase_transition()
	
	if current_hp <= 0:
		die()

func die() -> void:
	print("[Boss] ", boss_name, " defeated! Score: ", score)
	
	var base_size: float = collision.shape.radius * 2.0 if collision and collision.shape is CircleShape2D else 80.0
	var explosion_size: float = base_size
	var explosion_color: Color = Color("#FFC368")
	var explosion_asset: String = ""
	var explosion_asset_anim: String = ""
	var explosion_anim_duration: float = 0.0
	var explosion_anim_loop: bool = false
	var fade_out_duration: float = 0.16
	var fade_in_duration: float = 0.06
	var scale_start: float = 1.0
	var scale_middle: float = 1.0
	var scale_end: float = 1.0
	var scale_middle_ratio: float = 0.45
	var target_width: float = -1.0
	var target_height: float = -1.0

	var explosions_cfg: Dictionary = DataManager.get_explosions_config() if DataManager else {}
	var boss_expl_v: Variant = explosions_cfg.get("boss_death", {})
	if boss_expl_v is Dictionary:
		var boss_expl: Dictionary = boss_expl_v as Dictionary
		explosion_size = maxf(
			float(boss_expl.get("size_min", base_size)),
			base_size * maxf(0.1, float(boss_expl.get("size_multiplier", 2.8)))
		)
		explosion_color = Color(str(boss_expl.get("color", "#FFC368")))
		explosion_asset = str(boss_expl.get("asset", ""))
		explosion_asset_anim = str(boss_expl.get("asset_anim", ""))
		explosion_anim_duration = maxf(0.0, float(boss_expl.get("asset_anim_duration", 0.0)))
		explosion_anim_loop = bool(boss_expl.get("asset_anim_loop", false))
		fade_out_duration = maxf(0.05, float(boss_expl.get("fade_out_duration", fade_out_duration)))
		fade_in_duration = maxf(0.0, float(boss_expl.get("fade_in_duration", fade_in_duration)))
		scale_start = maxf(0.01, float(boss_expl.get("scale_start", scale_start)))
		scale_middle = maxf(0.01, float(boss_expl.get("scale_middle", scale_middle)))
		scale_end = maxf(0.01, float(boss_expl.get("scale_end", scale_end)))
		scale_middle_ratio = clampf(float(boss_expl.get("scale_middle_ratio", scale_middle_ratio)), 0.05, 0.95)
		target_width = float(boss_expl.get("width", target_width))
		target_height = float(boss_expl.get("height", target_height))

	# Boss death explosion is always one-shot.
	explosion_anim_loop = false

	VFXManager.spawn_explosion(
		global_position,
		explosion_size,
		explosion_color,
		get_parent(),
		explosion_asset,
		explosion_asset_anim,
		-1.0,
		fade_out_duration,
		explosion_anim_duration,
		explosion_anim_loop,
		fade_in_duration,
		scale_start,
		scale_middle,
		scale_end,
		scale_middle_ratio,
		target_width,
		target_height
	)
	VFXManager.screen_shake(30, 1.2)
	
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
