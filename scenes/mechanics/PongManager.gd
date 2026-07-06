extends Node2D

## PongManager — Orchestre une vague "pong" :
## le vaisseau joueur est verrouille en bas de l'ecran et ecrase en raquette,
## un vaisseau ennemi devient une raquette en haut, une balle rebondit entre
## les deux (rebonds sur les bords gauche/droit).
## But encaisse (balle derriere le joueur) = degats en % des HP max,
## but marque (balle derriere l'ennemi) = cristaux bonus qui tombent du haut.
## Duree limitee, compte a rebours seul au HUD. Les collisions balle/raquettes
## sont resolues en AABB manuel (pas de physics engine), comme les contacts
## du GateRunner.

signal finished

enum State { INTRO, SERVE, PLAY, DONE }

# Anti-tunneling: cap the ball integration step on long frames.
const MAX_BALL_STEP_SEC: float = 1.0 / 30.0

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _enemy_skins: Dictionary = {} # world-level skin overrides: enemy_id -> skin path

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 30.0
var _elapsed: float = 0.0

# Ball (manual movement, no physics engine)
var _ball: Node2D = null
var _ball_velocity: Vector2 = Vector2.ZERO
var _ball_radius: float = 16.0
var _ball_speed: float = 420.0
var _ball_base_speed: float = 420.0
var _ball_speed_max: float = 900.0
var _ball_speed_increase: float = 15.0
var _max_bounce_angle_deg: float = 55.0
var _wall_margin: float = 10.0
var _serve_dir: int = 1 # +1 = toward the player (down), -1 = toward the enemy (up)
var _serve_delay: float = 0.8
var _serve_angle_max_deg: float = 30.0

# Enemy paddle: a light Node2D driven here, NOT an Enemy.gd instance
# (no HP, no shooting, no "enemies" group, no physics collision).
var _enemy_paddle: Node2D = null
var _enemy_half_extents: Vector2 = Vector2(96.0, 16.0)
var _enemy_speed: float = 320.0
var _enemy_reaction_interval: float = 0.35
var _enemy_reaction_timer: float = 0.0
var _enemy_aim_error_px: float = 40.0
var _enemy_target_x: float = 0.0

# Player paddle: manual AABB around _player.global_position.
var _player_half_extents: Vector2 = Vector2(96.0, 16.0)

var _damage_percent: float = 0.2
var _crystals_per_point: int = 3

var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_pong_config() if DataManager else {}
	var skins_v: Variant = _config.get("_enemy_skins", {})
	_enemy_skins = (skins_v as Dictionary) if skins_v is Dictionary else {}

	# Per-wave overrides (world_x.json) take precedence over global defaults (game.json).
	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 30.0))))
	_ball_radius = maxf(4.0, float(_cfg.get("ball_radius_px", 16.0)))
	_ball_base_speed = maxf(60.0, float(_config.get("ball_speed_px_sec", _cfg.get("ball_speed_px_sec_default", 420.0))))
	_ball_speed = _ball_base_speed
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	_ball_speed_increase = maxf(0.0, float(_cfg.get("ball_speed_increase_per_hit", 15.0)))
	_max_bounce_angle_deg = clampf(float(_cfg.get("ball_max_bounce_angle_deg", 55.0)), 10.0, 80.0)
	_wall_margin = maxf(0.0, float(_cfg.get("wall_margin_px", 10.0)))
	_serve_delay = maxf(0.1, float(_cfg.get("serve_delay_sec", 0.8)))
	_serve_angle_max_deg = clampf(float(_cfg.get("serve_angle_max_deg", 30.0)), 0.0, 60.0)

	_player_half_extents = Vector2(
		maxf(16.0, float(_cfg.get("player_paddle_half_width_px", 96.0))),
		maxf(6.0, float(_cfg.get("player_paddle_half_height_px", 16.0)))
	)
	_enemy_half_extents = Vector2(
		maxf(16.0, float(_cfg.get("enemy_paddle_half_width_px", 96.0))),
		maxf(6.0, float(_cfg.get("enemy_paddle_half_height_px", 16.0)))
	)
	_enemy_speed = maxf(30.0, float(_config.get("enemy_paddle_speed_px_sec", _cfg.get("enemy_paddle_speed_px_sec_default", 320.0))))
	_enemy_reaction_interval = clampf(float(_config.get("enemy_reaction_interval_sec", _cfg.get("enemy_reaction_interval_sec_default", 0.35))), 0.02, 2.0)
	_enemy_aim_error_px = maxf(0.0, float(_config.get("enemy_aim_error_px", _cfg.get("enemy_aim_error_px_default", 40.0))))

	_damage_percent = clampf(float(_config.get("damage_percent_per_goal", _cfg.get("damage_percent_per_goal", 0.2))), 0.0, 1.0)
	_crystals_per_point = maxi(0, int(_config.get("crystals_per_point", _cfg.get("crystals_per_point_default", 3))))

	_begin_player_mode()
	_spawn_enemy_paddle()
	_spawn_ball()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.6)))
	set_process(true)

## Mode libre "continuous" : la difficulté du match EN COURS est re-scalée au
## changement de level — la balle, l'échange et les positions sont préservés
## (aucun re-service, contrairement à une nouvelle itération de vague).
func update_free_mode_config(cfg: Dictionary) -> void:
	_ball_base_speed = maxf(60.0, float(cfg.get("ball_speed_px_sec", _ball_base_speed)))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	if _ball_speed < _ball_base_speed:
		_ball_speed = _ball_base_speed
		if _ball_velocity != Vector2.ZERO:
			_ball_velocity = _ball_velocity.normalized() * _ball_speed
	_enemy_speed = maxf(30.0, float(cfg.get("enemy_paddle_speed_px_sec", _enemy_speed)))
	_enemy_reaction_interval = clampf(float(cfg.get("enemy_reaction_interval_sec", _enemy_reaction_interval)), 0.02, 2.0)
	_enemy_aim_error_px = maxf(0.0, float(cfg.get("enemy_aim_error_px", _enemy_aim_error_px)))
	_damage_percent = clampf(float(cfg.get("damage_percent_per_goal", _damage_percent)), 0.0, 1.0)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_pong"):
		# Merge so begin_pong sees both global defaults and per-wave overrides.
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_pong", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_pong"):
		_player.call("end_pong")

# =============================================================================
# SPAWNING
# =============================================================================

func _spawn_enemy_paddle() -> void:
	_enemy_paddle = Node2D.new()
	_enemy_paddle.name = "EnemyPaddle"
	_enemy_paddle.z_as_relative = false
	_enemy_paddle.z_index = 10
	add_child(_enemy_paddle)
	var viewport_size: Vector2 = get_viewport_rect().size
	var y_ratio: float = clampf(float(_cfg.get("enemy_paddle_y_ratio", 0.1)), 0.03, 0.45)
	_enemy_paddle.global_position = Vector2(viewport_size.x * 0.5, viewport_size.y * y_ratio)
	_enemy_target_x = _enemy_paddle.global_position.x
	_enemy_reaction_timer = 0.0
	var visual_node: Node2D = _build_sprite_fit(_resolve_enemy_asset_path(), _enemy_half_extents * 2.0)
	if visual_node == null:
		visual_node = _build_paddle_rect()
	_enemy_paddle.add_child(visual_node)

func _resolve_enemy_asset_path() -> String:
	# Dedicated paddle asset (per-wave override, then wave-type config) wins
	# over the world skin / enemy visual.
	var paddle_asset: String = str(_config.get("enemy_paddle_asset", _cfg.get("enemy_paddle_asset", "")))
	if paddle_asset != "":
		return paddle_asset
	var enemy_id: String = str(_cfg.get("enemy_visual_enemy_id", "fighter"))
	var asset_path: String = str(_enemy_skins.get(enemy_id, ""))
	if asset_path != "":
		return asset_path
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id) if DataManager else {}
	var visual_v: Variant = enemy_data.get("visual", {})
	if visual_v is Dictionary:
		var visual: Dictionary = visual_v as Dictionary
		asset_path = str(visual.get("asset_anim", ""))
		if asset_path == "":
			asset_path = str(visual.get("asset", ""))
	return asset_path

## Builds a visual (.tres SpriteFrames or .png/.jpg texture) stretched onto the
## exact target box, so paddles and ball always match their collision size.
func _build_sprite_fit(asset_path: String, target_size: Vector2) -> Node2D:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null
	var res: Resource = load(asset_path)
	if res == null:
		return null
	if res is SpriteFrames:
		var animated := AnimatedSprite2D.new()
		animated.sprite_frames = res as SpriteFrames
		var anim_names: PackedStringArray = animated.sprite_frames.get_animation_names()
		var anim_name: StringName = &"default"
		if not animated.sprite_frames.has_animation(anim_name) and anim_names.size() > 0:
			anim_name = StringName(anim_names[0])
		if animated.sprite_frames.has_animation(anim_name):
			animated.play(anim_name)
		var frame_size: Vector2 = _get_animated_frame_size(animated.sprite_frames, anim_name)
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			animated.scale = target_size / frame_size
		return animated
	if res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = res as Texture2D
		var tex_size: Vector2 = (res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = target_size / tex_size
		return sprite
	return null

func _get_animated_frame_size(frames: SpriteFrames, anim_name: StringName) -> Vector2:
	if frames == null or not frames.has_animation(anim_name):
		return Vector2.ZERO
	if frames.get_frame_count(anim_name) <= 0:
		return Vector2.ZERO
	var tex: Texture2D = frames.get_frame_texture(anim_name, 0)
	if tex == null:
		return Vector2.ZERO
	return tex.get_size()

func _build_paddle_rect() -> Node2D:
	var rect := Polygon2D.new()
	var hw: float = _enemy_half_extents.x
	var hh: float = _enemy_half_extents.y
	rect.polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)
	])
	rect.color = Color(str(_cfg.get("enemy_paddle_fallback_color", "#E8553B")))
	return rect

func _spawn_ball() -> void:
	_ball = Node2D.new()
	_ball.name = "PongBall"
	_ball.z_as_relative = false
	_ball.z_index = 10
	add_child(_ball)
	# Custom ball visual (per-wave override, then wave-type config); fallback to
	# the procedural circle when no asset is set.
	var ball_asset: String = str(_config.get("ball_asset", _cfg.get("ball_asset", "")))
	var visual: Node2D = _build_sprite_fit(ball_asset, Vector2.ONE * _ball_radius * 2.0)
	if visual == null:
		visual = _build_ball_circle()
	_ball.add_child(visual)
	_ball.visible = false

func _build_ball_circle() -> Node2D:
	var circle := Polygon2D.new()
	var points := PackedVector2Array()
	var segments: int = 24
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * _ball_radius)
	circle.polygon = points
	circle.color = Color(str(_cfg.get("ball_color", "#FFE08A")))
	return circle

# =============================================================================
# MATCH LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# A dead player means the game-over flow took over: freeze the match
	# without emitting finished (the next wave must not start during game over).
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_reset_ball(1) # first serve goes toward the player
		State.SERVE:
			_update_enemy_paddle(delta)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_serve()
		State.PLAY:
			_update_enemy_paddle(delta)
			_update_ball(delta)
	if _elapsed >= _duration:
		_finish()

## Recenters the ball and schedules the next serve (short breather after a goal).
func _reset_ball(serve_dir: int) -> void:
	_serve_dir = 1 if serve_dir >= 0 else -1
	_ball_speed = _ball_base_speed
	_ball_velocity = Vector2.ZERO
	if _ball and is_instance_valid(_ball):
		var viewport_size: Vector2 = get_viewport_rect().size
		_ball.global_position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
		_ball.visible = true
	_state = State.SERVE
	_state_timer = _serve_delay

func _serve() -> void:
	var angle: float = deg_to_rad(randf_range(-_serve_angle_max_deg, _serve_angle_max_deg))
	_ball_velocity = Vector2(sin(angle), cos(angle) * float(_serve_dir)) * _ball_speed
	_state = State.PLAY

func _update_ball(delta: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	var remaining: float = minf(delta, 0.25)
	while remaining > 0.0 and _state == State.PLAY:
		var step: float = minf(remaining, MAX_BALL_STEP_SEC)
		remaining -= step
		_step_ball(step)

func _step_ball(step: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var pos: Vector2 = _ball.global_position + _ball_velocity * step

	# Side walls: reflect and re-seat on the wall to avoid double bounces.
	var left_x: float = _wall_margin + _ball_radius
	var right_x: float = viewport_size.x - _wall_margin - _ball_radius
	if pos.x <= left_x and _ball_velocity.x < 0.0:
		pos.x = left_x
		_ball_velocity.x = -_ball_velocity.x
	elif pos.x >= right_x and _ball_velocity.x > 0.0:
		pos.x = right_x
		_ball_velocity.x = -_ball_velocity.x

	# Player paddle (bottom): only intercepts a ball travelling downward.
	if _ball_velocity.y > 0.0 and _player and is_instance_valid(_player):
		var p: Vector2 = _player.global_position
		if _circle_hits_paddle(pos, p, _player_half_extents):
			pos.y = p.y - _player_half_extents.y - _ball_radius
			_bounce_off_paddle(pos.x, p.x, _player_half_extents.x, true)

	# Enemy paddle (top): only intercepts a ball travelling upward.
	if _ball_velocity.y < 0.0 and _enemy_paddle and is_instance_valid(_enemy_paddle):
		var e: Vector2 = _enemy_paddle.global_position
		if _circle_hits_paddle(pos, e, _enemy_half_extents):
			pos.y = e.y + _enemy_half_extents.y + _ball_radius
			_bounce_off_paddle(pos.x, e.x, _enemy_half_extents.x, false)

	_ball.global_position = pos

	# Goals: the ball fully leaves the screen behind a paddle.
	if pos.y - _ball_radius > viewport_size.y:
		_on_enemy_scored()
	elif pos.y + _ball_radius < 0.0:
		_on_player_scored()

func _circle_hits_paddle(ball_pos: Vector2, paddle_center: Vector2, half_extents: Vector2) -> bool:
	var dx: float = absf(ball_pos.x - paddle_center.x)
	var dy: float = absf(ball_pos.y - paddle_center.y)
	return dx <= half_extents.x + _ball_radius and dy <= half_extents.y + _ball_radius

## Classic pong bounce: the exit angle is proportional to where the ball hit
## the paddle, and the ball speeds up a little on every paddle hit (capped).
func _bounce_off_paddle(ball_x: float, paddle_x: float, half_width: float, upward: bool) -> void:
	var offset: float = clampf((ball_x - paddle_x) / maxf(1.0, half_width), -1.0, 1.0)
	var angle: float = deg_to_rad(offset * _max_bounce_angle_deg)
	var dir := Vector2(sin(angle), -cos(angle) if upward else cos(angle))
	_ball_speed = minf(_ball_speed + _ball_speed_increase, _ball_speed_max)
	_ball_velocity = dir * _ball_speed

## Reactivity = retarget sampling interval + aim error: the paddle only refreshes
## its target every _enemy_reaction_interval seconds, with a random offset.
func _update_enemy_paddle(delta: float) -> void:
	if _enemy_paddle == null or not is_instance_valid(_enemy_paddle):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_enemy_reaction_timer -= delta
	if _enemy_reaction_timer <= 0.0:
		_enemy_reaction_timer = _enemy_reaction_interval
		var aim_x: float = viewport_size.x * 0.5
		if _ball and is_instance_valid(_ball) and _ball.visible:
			aim_x = _ball.global_position.x + randf_range(-_enemy_aim_error_px, _enemy_aim_error_px)
		_enemy_target_x = aim_x
	var min_x: float = _wall_margin + _enemy_half_extents.x
	var max_x: float = viewport_size.x - _wall_margin - _enemy_half_extents.x
	var target: float = clampf(_enemy_target_x, min_x, max_x)
	_enemy_paddle.global_position.x = move_toward(_enemy_paddle.global_position.x, target, _enemy_speed * delta)

# =============================================================================
# SCORING
# =============================================================================

func _on_enemy_scored() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP; die() below 0.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent)))
		_player.call("take_damage", dmg)
	_reset_ball(-1) # breather: the next serve goes toward the enemy

func _on_player_scored() -> void:
	if _game and is_instance_valid(_game) and _game.has_method("spawn_pong_reward_crystals"):
		_game.call("spawn_pong_reward_crystals", _crystals_per_point)
	_reset_ball(1)

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "PongCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_cfg.get("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_cfg.get("countdown_color", "#FFFFFF"))))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.z_as_relative = false
	_countdown_label.z_index = 60
	add_child(_countdown_label)

func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_cfg.get("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Restore the player BEFORE notifying the wave chain, so the next wave
	# always starts with a normal ship (shape, free Y, shooting handled by Game).
	_restore_player_mode()
	finished.emit()
	queue_free() # ball, enemy paddle and label are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
