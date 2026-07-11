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
##
## POWERUPS (data : powerup_pool[], apparition toutes les
## powerup_interval_sec) : collectés par LA BALLE — l'effet va au dernier
## camp qui l'a frappée (ownership last-hitter).
## - multiball : la balle qui touche se dédouble (cap multiball_max_balls —
##   le match peut dégénérer en nuée de balles ; chaque balle sortie compte
##   un but, le service ne repart que quand il n'en reste plus).
## - armed_paddle : la raquette du propriétaire tire des missiles pendant
##   duration_sec — un missile détruit les powerups sur sa route, stun la
##   raquette ennemie (armed_stun_sec) ou inflige un léger % au joueur.
## - giant_paddle : raquette du propriétaire +100 % de largeur (scale_mult)
##   pendant duration_sec (hitbox + visuel).
## - portals : paire de portails MOUVANTS (rect épais orange = entrée, bleu =
##   sortie) pendant duration_sec — la balle entrant dans l'orange ressort
##   par le bleu avec la même vélocité (direction/angle conservés).
## - brick_wall : mur central procédural (<= wall_max_bricks briques, tailles
##   façon breakout) — il faut creuser un passage pour atteindre l'adversaire,
##   sinon la balle rebondit vers chez soi.
## Tous les assets (powerups, missiles, portails, briques) et durées sont
## paramétrables dans wave_types.json > pong (PH procéduraux si vides).

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

# Balles (mouvement manuel, multiball) : { "node": Node2D, "vel": Vector2,
# "speed": float, "hitter": String ("player"/"enemy"/"" — dernier frappeur,
# propriétaire des powerups collectés), "portal_cd": float }.
var _balls: Array = []
var _ball_radius: float = 16.0
var _ball_base_speed: float = 420.0
var _ball_speed_max: float = 900.0
var _ball_speed_increase: float = 15.0
var _max_bounce_angle_deg: float = 55.0
var _wall_margin: float = 10.0
var _serve_dir: int = 1 # +1 = toward the player (down), -1 = toward the enemy (up)
var _serve_delay: float = 0.8
var _serve_angle_max_deg: float = 30.0

# Powerups : { "node": Node2D, "pos": Vector2, "radius": float,
# "def": Dictionary (entrée powerup_pool), "despawn": float }.
var _powerups: Array = []
var _powerup_timer: float = 20.0
var _powerup_interval: float = 20.0
var _powerup_despawn: float = 10.0
var _powerup_radius: float = 22.0
var _powerup_pool: Array = []
var _multiball_max: int = 12
# Effets temporisés par camp ("player"/"enemy") : secondes restantes.
var _armed: Dictionary = {}
var _armed_fire_timers: Dictionary = {}
var _giant: Dictionary = {}
var _giant_scale: float = 2.0
# Rétrécissement de la raquette ADVERSE du collecteur : side -> secondes.
var _shrink: Dictionary = {}
var _shrink_scale: float = 0.5
# Effet balle courbe : les balles dont hitter == side serpentent.
var _curve: Dictionary = {}
var _curve_strength: float = 2200.0
var _curve_freq: float = 1.4
# Barrières électriques derrière la ligne du propriétaire :
# side -> { "time": float, "lines": Array[Line2D] }.
var _shields: Dictionary = {}
# Matériau additif PARTAGÉ par toutes les couches de glow (un seul, batching).
var _shield_material: CanvasItemMaterial = null
var _enemy_stun: float = 0.0
var _armed_fire_interval: float = 0.8
var _armed_missile_speed: float = 520.0
var _armed_stun_sec: float = 1.5
var _armed_player_damage_pct: float = 0.05
# Missiles des raquettes armées : { "node", "pos", "vel", "from_player" }.
var _missiles: Array = []
# Portails : { "entry": Node2D, "exit": Node2D, "time_left": float,
# "phase": float } — la balle entre dans l'orange, ressort par le bleu.
var _portal: Dictionary = {}
# Mur de briques central : { "node", "rect": Rect2, "hp", "max_hp" }.
var _bricks: Array = []
# Glow visuel de la raquette géante du joueur (suit le vaisseau).
var _player_giant_glow: Polygon2D = null
# Overlay rouge matérialisant la hitbox RÉDUITE du joueur (shrink adverse).
var _player_shrink_overlay: Polygon2D = null

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

	# Powerups (pool pondéré data, PH procéduraux si assets vides).
	_powerup_interval = maxf(3.0, float(_get_conf("powerup_interval_sec", 20.0)))
	_powerup_despawn = maxf(2.0, float(_get_conf("powerup_despawn_sec", 30.0)))
	_powerup_radius = maxf(8.0, float(_get_conf("powerup_radius_px", 66.0)))
	_powerup_timer = _powerup_interval
	var pool_v: Variant = _get_conf("powerup_pool", [])
	_powerup_pool = (pool_v as Array).duplicate(true) if pool_v is Array else []
	if not bool(_get_conf("powerups_enabled", true)):
		_powerup_pool = []
	_multiball_max = clampi(int(_get_conf("multiball_max_balls", 12)), 1, 40)
	_armed_fire_interval = maxf(0.1, float(_get_conf("armed_fire_interval_sec", 0.8)))
	_armed_missile_speed = maxf(80.0, float(_get_conf("armed_missile_speed_px_sec", 520.0)))
	_armed_stun_sec = maxf(0.1, float(_get_conf("armed_stun_sec", 1.5)))
	_armed_player_damage_pct = clampf(float(_get_conf("armed_missile_player_damage_percent", 0.05)), 0.0, 1.0)
	_curve_strength = maxf(0.0, float(_get_conf("curve_strength_px_sec2", 2200.0)))
	_curve_freq = maxf(0.05, float(_get_conf("curve_frequency_hz", 1.4)))

	_begin_player_mode()
	_spawn_enemy_paddle()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.6)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté du match EN COURS est re-scalée au
## changement de level — les balles, l'échange et les positions sont préservés
## (aucun re-service, contrairement à une nouvelle itération de vague).
func update_free_mode_config(cfg: Dictionary) -> void:
	_ball_base_speed = maxf(60.0, float(cfg.get("ball_speed_px_sec", _ball_base_speed)))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		if float(ball.get("speed", 0.0)) < _ball_base_speed:
			ball["speed"] = _ball_base_speed
			var vel: Vector2 = ball.get("vel", Vector2.ZERO)
			if vel != Vector2.ZERO:
				ball["vel"] = vel.normalized() * _ball_base_speed
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

## Crée une balle (multiball : plusieurs vivent en même temps).
func _spawn_ball(pos: Vector2, vel: Vector2, hitter: String) -> Dictionary:
	var node := Node2D.new()
	node.name = "PongBall"
	node.z_as_relative = false
	node.z_index = 10
	add_child(node)
	# Custom ball visual (per-wave override, then wave-type config); fallback to
	# the procedural circle when no asset is set.
	var ball_asset: String = str(_config.get("ball_asset", _cfg.get("ball_asset", "")))
	var visual: Node2D = _build_sprite_fit(ball_asset, Vector2.ONE * _ball_radius * 2.0)
	if visual == null:
		visual = _build_ball_circle()
	node.add_child(visual)
	node.global_position = pos
	var ball: Dictionary = {
		"node": node,
		"vel": vel,
		"speed": maxf(vel.length(), _ball_base_speed) if vel != Vector2.ZERO else _ball_base_speed,
		"hitter": hitter,
		"portal_cd": 0.0,
		"curve_phase": randf() * TAU
	}
	_balls.append(ball)
	return ball

func _free_ball(ball: Dictionary) -> void:
	var node_v: Variant = ball.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()

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
			_update_powerups(delta)
			_update_missiles(delta)
			_update_portal(delta)
			_update_effect_timers(delta)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_serve()
		State.PLAY:
			_update_enemy_paddle(delta)
			_update_balls(delta)
			_update_powerups(delta)
			_update_missiles(delta)
			_update_portal(delta)
			_update_effect_timers(delta)
	if _elapsed >= _duration:
		_finish()

## Recenters a single serve ball (breather after the LAST ball is gone).
func _reset_ball(serve_dir: int) -> void:
	_serve_dir = 1 if serve_dir >= 0 else -1
	for i in range(_balls.size() - 1, -1, -1):
		_free_ball(_balls[i])
	_balls.clear()
	var viewport_size: Vector2 = get_viewport_rect().size
	_spawn_ball(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5), Vector2.ZERO, "")
	_state = State.SERVE
	_state_timer = _serve_delay

func _serve() -> void:
	var angle: float = deg_to_rad(randf_range(-_serve_angle_max_deg, _serve_angle_max_deg))
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		ball["speed"] = _ball_base_speed
		ball["vel"] = Vector2(sin(angle), cos(angle) * float(_serve_dir)) * _ball_base_speed
	_state = State.PLAY

func _update_balls(delta: float) -> void:
	var remaining: float = minf(delta, 0.25)
	while remaining > 0.0 and _state == State.PLAY:
		var step: float = minf(remaining, MAX_BALL_STEP_SEC)
		remaining -= step
		for i in range(_balls.size() - 1, -1, -1):
			var ball: Dictionary = _balls[i]
			ball["portal_cd"] = maxf(0.0, float(ball.get("portal_cd", 0.0)) - step)
			if not _step_ball(ball, step):
				_free_ball(ball)
				_balls.remove_at(i)
		if _balls.is_empty() and _state == State.PLAY:
			# Plus aucune balle en jeu : re-service (direction du dernier but).
			_reset_ball(_serve_dir)
			break

## Avance UNE balle d'un sous-pas. false = la balle sort (but).
func _step_ball(ball: Dictionary, step: float) -> bool:
	var viewport_size: Vector2 = get_viewport_rect().size
	var node: Node2D = ball.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		return false
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	# Balle courbe : nudge perpendiculaire AVANT l'intégration pour que murs,
	# raquettes et write-back voient tous la vélocité courbée.
	vel = _apply_curve_to_vel(ball, vel, step)
	var pos: Vector2 = node.global_position + vel * step

	# Side walls: reflect and re-seat on the wall to avoid double bounces.
	var left_x: float = _wall_margin + _ball_radius
	var right_x: float = viewport_size.x - _wall_margin - _ball_radius
	if pos.x <= left_x and vel.x < 0.0:
		pos.x = left_x
		vel.x = -vel.x
	elif pos.x >= right_x and vel.x > 0.0:
		pos.x = right_x
		vel.x = -vel.x

	# Player paddle (bottom): only intercepts a ball travelling downward.
	if vel.y > 0.0 and _player and is_instance_valid(_player):
		var p: Vector2 = _player.global_position
		var p_half: Vector2 = _paddle_half_extents("player")
		if _circle_hits_paddle(pos, p, p_half):
			pos.y = p.y - p_half.y - _ball_radius
			ball["vel"] = vel
			vel = _bounce_off_paddle(ball, pos.x, p.x, p_half.x, true)
			ball["hitter"] = "player"

	# Enemy paddle (top): only intercepts a ball travelling upward.
	if vel.y < 0.0 and _enemy_paddle and is_instance_valid(_enemy_paddle):
		var e: Vector2 = _enemy_paddle.global_position
		var e_half: Vector2 = _paddle_half_extents("enemy")
		if _circle_hits_paddle(pos, e, e_half):
			pos.y = e.y + e_half.y + _ball_radius
			ball["vel"] = vel
			vel = _bounce_off_paddle(ball, pos.x, e.x, e_half.x, false)
			ball["hitter"] = "enemy"

	ball["vel"] = vel
	# Mur de briques central : rebond + dégât de brique.
	pos = _collide_ball_bricks(ball, pos)
	# Portails : entrée orange -> sortie bleue, vélocité conservée.
	pos = _apply_portal_to_ball(ball, pos)
	# Powerups : collectés par la balle pour le compte du dernier frappeur.
	_collect_powerups_at(ball, pos)
	# Barrières électriques : réflexion derrière la ligne du propriétaire.
	pos = _apply_shields_to_ball(ball, pos)
	node.global_position = pos

	# Goals: the ball fully leaves the screen behind a paddle.
	if pos.y - _ball_radius > viewport_size.y:
		_on_enemy_scored()
		return false
	elif pos.y + _ball_radius < 0.0:
		_on_player_scored()
		return false
	return true

## Multiplicateur net de largeur d'une raquette (giant × shrink cumulables —
## source UNIQUE : hitbox, offset de rebond, clamp IA, missiles et visuels).
func _paddle_width_mult(side: String) -> float:
	var mult: float = 1.0
	if float(_giant.get(side, 0.0)) > 0.0:
		mult *= _giant_scale
	if float(_shrink.get(side, 0.0)) > 0.0:
		mult *= _shrink_scale
	return mult

## Demi-dimensions effectives d'une raquette (largeur × mult net).
func _paddle_half_extents(side: String) -> Vector2:
	var base: Vector2 = _player_half_extents if side == "player" else _enemy_half_extents
	return Vector2(base.x * _paddle_width_mult(side), base.y)

func _circle_hits_paddle(ball_pos: Vector2, paddle_center: Vector2, half_extents: Vector2) -> bool:
	var dx: float = absf(ball_pos.x - paddle_center.x)
	var dy: float = absf(ball_pos.y - paddle_center.y)
	return dx <= half_extents.x + _ball_radius and dy <= half_extents.y + _ball_radius

## Classic pong bounce: the exit angle is proportional to where the ball hit
## the paddle, and the ball speeds up a little on every paddle hit (capped).
func _bounce_off_paddle(ball: Dictionary, ball_x: float, paddle_x: float, half_width: float, upward: bool) -> Vector2:
	var offset: float = clampf((ball_x - paddle_x) / maxf(1.0, half_width), -1.0, 1.0)
	var angle: float = deg_to_rad(offset * _max_bounce_angle_deg)
	var dir := Vector2(sin(angle), -cos(angle) if upward else cos(angle))
	var speed: float = minf(float(ball.get("speed", _ball_base_speed)) + _ball_speed_increase, _ball_speed_max)
	ball["speed"] = speed
	return dir * speed

## Balle courbe : nudge perpendiculaire sinusoïdal puis renormalisation à la
## vitesse scalaire de la balle (aucune dérive possible, le bookkeeping
## d'accélération des rebonds est préservé). La courbe suit le hitter COURANT :
## une réflexion de barrière re-taggue la balle et transfère (ou coupe) l'effet.
## La phase n'est pas reset au rebond — le perp suit vel, zigzag miroir naturel.
func _apply_curve_to_vel(ball: Dictionary, vel: Vector2, step: float) -> Vector2:
	var side: String = str(ball.get("hitter", ""))
	if side == "" or float(_curve.get(side, 0.0)) <= 0.0 or vel.length_squared() < 1.0:
		return vel
	var phase: float = float(ball.get("curve_phase", 0.0)) + step * TAU * _curve_freq
	ball["curve_phase"] = phase
	var perp := Vector2(-vel.y, vel.x).normalized()
	return (vel + perp * sin(phase) * _curve_strength * step).normalized() \
		* float(ball.get("speed", _ball_base_speed))

## Reactivity = retarget sampling interval + aim error: the paddle only refreshes
## its target every _enemy_reaction_interval seconds, with a random offset.
## Multiball : vise la balle la plus MENAÇANTE (qui monte, la plus proche).
## Stunnée par un missile (raquette armée), elle ne bouge plus.
func _update_enemy_paddle(delta: float) -> void:
	if _enemy_paddle == null or not is_instance_valid(_enemy_paddle):
		return
	if _enemy_stun > 0.0:
		_enemy_stun -= delta
		_enemy_paddle.modulate = Color(0.55, 0.55, 0.95, 1.0)
		return
	_enemy_paddle.modulate = Color.WHITE
	var viewport_size: Vector2 = get_viewport_rect().size
	_enemy_reaction_timer -= delta
	if _enemy_reaction_timer <= 0.0:
		_enemy_reaction_timer = _enemy_reaction_interval
		var aim_x: float = viewport_size.x * 0.5
		var best_score: float = INF
		for ball_v in _balls:
			var ball: Dictionary = ball_v as Dictionary
			var node: Node2D = ball.get("node") as Node2D
			if node == null or not is_instance_valid(node):
				continue
			var vel: Vector2 = ball.get("vel", Vector2.ZERO)
			# Balles montantes prioritaires (les descendantes comptent "loin").
			var threat: float = node.global_position.y if vel.y < 0.0 else node.global_position.y + viewport_size.y
			if threat < best_score:
				best_score = threat
				aim_x = node.global_position.x + randf_range(-_enemy_aim_error_px, _enemy_aim_error_px)
		_enemy_target_x = aim_x
	var e_half: Vector2 = _paddle_half_extents("enemy")
	var min_x: float = _wall_margin + e_half.x
	var max_x: float = viewport_size.x - _wall_margin - e_half.x
	var target: float = clampf(_enemy_target_x, min_x, max_x)
	_enemy_paddle.global_position.x = move_toward(_enemy_paddle.global_position.x, target, _enemy_speed * delta)

# =============================================================================
# SCORING
# =============================================================================

## Multiball : chaque balle sortie compte un but PUIS est retirée par
## l'appelant ; le re-service n'a lieu que quand il ne reste plus de balle
## (_update_balls), dans la direction du dernier but.
func _on_enemy_scored() -> void:
	_serve_dir = -1
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP; die() below 0.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent)))
		_player.call("take_damage", dmg)

func _on_player_scored() -> void:
	_serve_dir = 1
	if _game and is_instance_valid(_game) and _game.has_method("spawn_pong_reward_crystals"):
		_game.call("spawn_pong_reward_crystals", _crystals_per_point)

# =============================================================================
# POWERUPS (spawn périodique, collecte par la balle, ownership last-hitter)
# =============================================================================

func _update_powerups(delta: float) -> void:
	if _powerup_pool.is_empty():
		return
	_powerup_timer -= delta
	if _powerup_timer <= 0.0:
		_powerup_timer = _powerup_interval
		_spawn_powerup()
	for i in range(_powerups.size() - 1, -1, -1):
		var powerup: Dictionary = _powerups[i]
		powerup["despawn"] = float(powerup.get("despawn", 0.0)) - delta
		var node_v: Variant = powerup.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			# Pulse doux pour attirer l'oeil ; clignote en fin de vie.
			var node: Node2D = node_v as Node2D
			node.scale = Vector2.ONE * (1.0 + 0.08 * sin(_elapsed * 6.0))
			if float(powerup["despawn"]) < 2.0:
				node.modulate.a = 0.4 + 0.6 * absf(sin(_elapsed * 10.0))
		if float(powerup["despawn"]) <= 0.0:
			_free_powerup(powerup)
			_powerups.remove_at(i)

func _spawn_powerup() -> void:
	var def: Dictionary = _pick_powerup_def()
	if def.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var pos := Vector2(
		randf_range(viewport_size.x * 0.18, viewport_size.x * 0.82),
		randf_range(viewport_size.y * 0.3, viewport_size.y * 0.7))
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 9
	var visual: Node2D = _build_sprite_fit(str(def.get("asset", "")), Vector2.ONE * _powerup_radius * 2.0)
	if visual == null:
		# PH procédural : anneau + coeur coloré (tint data).
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * _powerup_radius)
		circle.polygon = pts
		circle.color = Color(str(def.get("tint", "#8FD3FF")))
		visual = circle
	node.add_child(visual)
	var label := Label.new()
	# `label` du def en priorité (désambiguïse shield_orb/shrink_enemy).
	label.text = str(def.get("label", str(def.get("id", "?")).left(1))).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(_powerup_radius))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(_powerup_radius * 2.0, _powerup_radius * 2.0)
	label.position = -label.size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	node.global_position = pos
	add_child(node)
	_powerups.append({"node": node, "pos": pos, "radius": _powerup_radius, "def": def, "despawn": _powerup_despawn})

func _pick_powerup_def() -> Dictionary:
	var total: float = 0.0
	for def_v in _powerup_pool:
		if def_v is Dictionary:
			total += maxf(0.0, float((def_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var roll: float = randf() * total
	for def_v in _powerup_pool:
		if not (def_v is Dictionary):
			continue
		roll -= maxf(0.0, float((def_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			return def_v as Dictionary
	return {}

func _free_powerup(powerup: Dictionary) -> void:
	var node_v: Variant = powerup.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()

## Collecte au contact de la balle — l'effet va au DERNIER FRAPPEUR de cette
## balle (une balle jamais frappée traverse les powerups sans les prendre).
func _collect_powerups_at(ball: Dictionary, pos: Vector2) -> void:
	var hitter_id: String = str(ball.get("hitter", ""))
	if hitter_id == "":
		return
	for i in range(_powerups.size() - 1, -1, -1):
		var powerup: Dictionary = _powerups[i]
		var p_pos: Vector2 = powerup.get("pos", Vector2.ZERO)
		var reach: float = float(powerup.get("radius", 22.0)) + _ball_radius
		if pos.distance_squared_to(p_pos) > reach * reach:
			continue
		var def: Dictionary = powerup.get("def", {}) as Dictionary
		_free_powerup(powerup)
		_powerups.remove_at(i)
		_apply_powerup(def, hitter_id, ball, pos)

func _apply_powerup(def: Dictionary, hitter_id: String, ball: Dictionary, at_pos: Vector2) -> void:
	var duration: float = maxf(0.5, float(def.get("duration_sec", 15.0)))
	match str(def.get("id", "")):
		"multiball":
			# La balle qui touche se dédouble (miroir x + léger angle).
			if _balls.size() < _multiball_max:
				var vel: Vector2 = ball.get("vel", Vector2.DOWN * _ball_base_speed)
				var new_vel: Vector2 = Vector2(-vel.x, vel.y).rotated(deg_to_rad(randf_range(-12.0, 12.0)))
				if new_vel.length_squared() < 1.0:
					new_vel = Vector2.DOWN * _ball_base_speed
				var clone: Dictionary = _spawn_ball(at_pos, new_vel.normalized() * float(ball.get("speed", _ball_base_speed)), hitter_id)
				clone["portal_cd"] = 0.3
		"armed_paddle":
			_armed[hitter_id] = duration
			if not _armed_fire_timers.has(hitter_id):
				_armed_fire_timers[hitter_id] = 0.0
		"giant_paddle":
			_giant_scale = maxf(1.1, float(def.get("scale_mult", 2.0)))
			_giant[hitter_id] = duration
			_refresh_paddle_visuals()
		"shield_orb":
			_spawn_shield(hitter_id, duration)
		"shrink_enemy":
			# Rétrécit la raquette ADVERSE du collecteur.
			_shrink_scale = clampf(float(def.get("scale_mult", 0.5)), 0.1, 0.95)
			_shrink["enemy" if hitter_id == "player" else "player"] = duration
			_refresh_paddle_visuals()
		"curve_ball":
			_curve[hitter_id] = duration
		"portals":
			_spawn_portal_pair(duration, hitter_id)
		"brick_wall":
			_spawn_brick_wall()
		_:
			pass
	if VFXManager:
		VFXManager.spawn_impact(at_pos, 14.0, self)

## Décrémente les effets temporisés (armed/giant/shrink/curve/shield) et
## pilote le tir des raquettes armées.
func _update_effect_timers(delta: float) -> void:
	for side_v in ["player", "enemy"]:
		var side: String = side_v
		if _armed.has(side):
			_armed[side] = float(_armed[side]) - delta
			if float(_armed[side]) <= 0.0:
				_armed.erase(side)
			else:
				_armed_fire_timers[side] = float(_armed_fire_timers.get(side, 0.0)) - delta
				if float(_armed_fire_timers[side]) <= 0.0:
					_armed_fire_timers[side] = _armed_fire_interval
					_fire_paddle_missile(side)
		if _giant.has(side):
			_giant[side] = float(_giant[side]) - delta
			if float(_giant[side]) <= 0.0:
				_giant.erase(side)
				_refresh_paddle_visuals()
		if _shrink.has(side):
			_shrink[side] = float(_shrink[side]) - delta
			if float(_shrink[side]) <= 0.0:
				_shrink.erase(side)
				_refresh_paddle_visuals()
		if _curve.has(side):
			_curve[side] = float(_curve[side]) - delta
			if float(_curve[side]) <= 0.0:
				_curve.erase(side)
		if _shields.has(side):
			var shield: Dictionary = _shields[side]
			shield["time"] = float(shield.get("time", 0.0)) - delta
			if float(shield["time"]) <= 0.0:
				_free_shield(side)
	# Les visuels de hitbox du joueur (glow géant / overlay réduit) suivent le
	# vaisseau ; les barrières se ré-échantillonnent chaque frame (électricité).
	if _player_giant_glow and is_instance_valid(_player_giant_glow) \
		and _player and is_instance_valid(_player):
		_player_giant_glow.global_position = _player.global_position
	if _player_shrink_overlay and is_instance_valid(_player_shrink_overlay) \
		and _player and is_instance_valid(_player):
		_player_shrink_overlay.global_position = _player.global_position
	_animate_shields()

# =============================================================================
# RAQUETTES ARMÉES (missiles : détruisent les powerups, stun l'adversaire)
# =============================================================================

func _fire_paddle_missile(side: String) -> void:
	var from: Vector2 = Vector2.ZERO
	if side == "player":
		if _player == null or not is_instance_valid(_player):
			return
		from = _player.global_position + Vector2(0.0, -20.0)
	else:
		if _enemy_paddle == null or not is_instance_valid(_enemy_paddle):
			return
		from = _enemy_paddle.global_position + Vector2(0.0, 20.0)
	var size_v: Variant = _get_conf("armed_missile_size_px", [10, 26])
	var missile_size := Vector2(10.0, 26.0)
	if size_v is Array and (size_v as Array).size() >= 2:
		missile_size = Vector2(float((size_v as Array)[0]), float((size_v as Array)[1]))
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 11
	var visual: Node2D = _build_sprite_fit(str(_get_conf("armed_missile_asset", "")), missile_size)
	if visual == null:
		var rect := Polygon2D.new()
		var half: Vector2 = missile_size * 0.5
		rect.polygon = PackedVector2Array([
			Vector2(0.0, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		rect.color = Color(str(_get_conf("armed_missile_color", "#FF8A5C")))
		visual = rect
	if side == "enemy":
		visual.rotation = PI # pointe vers le bas
	node.add_child(visual)
	node.global_position = from
	add_child(node)
	_missiles.append({
		"node": node,
		"pos": from,
		"vel": Vector2(0.0, -_armed_missile_speed if side == "player" else _armed_missile_speed),
		"from_player": side == "player"
	})

func _update_missiles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(_missiles.size() - 1, -1, -1):
		var missile: Dictionary = _missiles[i]
		var pos: Vector2 = (missile.get("pos", Vector2.ZERO) as Vector2) + (missile.get("vel", Vector2.ZERO) as Vector2) * delta
		missile["pos"] = pos
		var node_v: Variant = missile.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).global_position = pos
		var consumed: bool = false
		# Détruit les powerups sur sa route ("dénie" le bonus à l'adversaire).
		for j in range(_powerups.size() - 1, -1, -1):
			var powerup: Dictionary = _powerups[j]
			var reach: float = float(powerup.get("radius", 22.0)) + 8.0
			if pos.distance_squared_to(powerup.get("pos", Vector2.ZERO) as Vector2) <= reach * reach:
				if VFXManager:
					VFXManager.spawn_impact(powerup.get("pos", Vector2.ZERO) as Vector2, 12.0, self)
				_free_powerup(powerup)
				_powerups.remove_at(j)
				consumed = true
				break
		# Impact raquette adverse : stun (ennemi) ou léger % (joueur).
		if not consumed and bool(missile.get("from_player", true)):
			if _enemy_paddle and is_instance_valid(_enemy_paddle):
				var e_half: Vector2 = _paddle_half_extents("enemy")
				var e: Vector2 = _enemy_paddle.global_position
				if absf(pos.x - e.x) <= e_half.x and absf(pos.y - e.y) <= e_half.y + 8.0:
					_enemy_stun = _armed_stun_sec
					if VFXManager:
						VFXManager.spawn_impact(pos, 16.0, self)
					consumed = true
		elif not consumed:
			if _player and is_instance_valid(_player):
				var p_half: Vector2 = _paddle_half_extents("player")
				var p: Vector2 = _player.global_position
				if absf(pos.x - p.x) <= p_half.x and absf(pos.y - p.y) <= p_half.y + 8.0:
					if _player.has_method("take_damage"):
						var max_hp_v: Variant = _player.get("max_hp")
						var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
						_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * _armed_player_damage_pct))))
					if VFXManager:
						VFXManager.spawn_impact(pos, 16.0, self)
					consumed = true
		if consumed or pos.y < -40.0 or pos.y > viewport_size.y + 40.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_missiles.remove_at(i)

## Glow visuel de la raquette géante (l'ennemi scale son node ; le joueur est
## un vaisseau écrasé par begin_pong -> on matérialise la hitbox élargie).
## Visuels de largeur des raquettes — writer UNIQUE de _enemy_paddle.scale.
## Le net giant × shrink pilote tout : > 1 = glow vert (hitbox élargie),
## < 1 = overlay rouge (hitbox réduite), ≈ 1 = rien (effets qui s'annulent).
func _refresh_paddle_visuals() -> void:
	if _enemy_paddle and is_instance_valid(_enemy_paddle):
		_enemy_paddle.scale = Vector2(_paddle_width_mult("enemy"), 1.0)
	if _player_giant_glow and is_instance_valid(_player_giant_glow):
		_player_giant_glow.queue_free()
	_player_giant_glow = null
	if _player_shrink_overlay and is_instance_valid(_player_shrink_overlay):
		_player_shrink_overlay.queue_free()
	_player_shrink_overlay = null
	var net: float = _paddle_width_mult("player")
	if net > 1.001:
		_player_giant_glow = _build_hitbox_overlay(net, Color(0.5, 0.9, 0.55, 0.4))
	elif net < 0.999:
		var overlay_color := Color(str(_get_conf("shrink_overlay_color", "#FF3D5A73")))
		_player_shrink_overlay = _build_hitbox_overlay(net, overlay_color)

## Rectangle translucide matérialisant la hitbox effective du joueur (le
## vaisseau écrasé ne peut pas être re-scalé : c'est l'overlay qui informe).
func _build_hitbox_overlay(width_mult: float, color: Color) -> Polygon2D:
	var overlay := Polygon2D.new()
	var half := Vector2(_player_half_extents.x * width_mult, _player_half_extents.y)
	overlay.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	overlay.color = color
	overlay.z_as_relative = false
	overlay.z_index = 9
	add_child(overlay)
	if _player and is_instance_valid(_player):
		overlay.global_position = _player.global_position
	return overlay

# =============================================================================
# PORTAILS DIMENSIONNELS (entrée orange -> sortie bleue, vélocité conservée)
# =============================================================================

## L'entrée (orange) apparaît dans la moitié de l'ACTIVATEUR : joueur -> bas,
## CPU -> haut (les deux ratios Y sont simplement échangés).
func _spawn_portal_pair(duration: float, owner: String = "player") -> void:
	_clear_portal()
	var viewport_size: Vector2 = get_viewport_rect().size
	var portal_size := Vector2(
		maxf(20.0, float(_get_conf("portal_width_px", 137.5))),
		maxf(6.0, float(_get_conf("portal_height_px", 22.5))))
	var entry: Node2D = _build_portal_node(str(_get_conf("portal_entry_asset", "")),
		Color(str(_get_conf("portal_entry_color", "#FF8A2A"))), portal_size)
	var exit: Node2D = _build_portal_node(str(_get_conf("portal_exit_asset", "")),
		Color(str(_get_conf("portal_exit_color", "#4AA8FF"))), portal_size)
	var entry_ratio: float = clampf(float(_get_conf("portal_entry_y_ratio", 0.62)), 0.05, 0.95)
	var exit_ratio: float = clampf(float(_get_conf("portal_exit_y_ratio", 0.36)), 0.05, 0.95)
	if owner == "enemy":
		var swap: float = entry_ratio
		entry_ratio = exit_ratio
		exit_ratio = swap
	var x_min: float = clampf(float(_get_conf("portal_x_min_ratio", 0.25)), 0.0, 1.0)
	var x_max: float = maxf(x_min, clampf(float(_get_conf("portal_x_max_ratio", 0.75)), 0.0, 1.0))
	entry.global_position = Vector2(viewport_size.x * randf_range(x_min, x_max), viewport_size.y * entry_ratio)
	exit.global_position = Vector2(viewport_size.x * randf_range(x_min, x_max), viewport_size.y * exit_ratio)
	_portal = {
		"entry": entry, "exit": exit,
		"size": portal_size,
		"time_left": duration,
		"phase": randf() * TAU,
		"entry_base_x": entry.global_position.x,
		"exit_base_x": exit.global_position.x
	}

func _build_portal_node(asset_path: String, color: Color, portal_size: Vector2) -> Node2D:
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 8
	var visual: Node2D = _build_sprite_fit(asset_path, portal_size)
	if visual == null:
		# PH : rectangle ÉPAIS coloré (orange = entrée, bleu = sortie).
		var rect := Polygon2D.new()
		var half: Vector2 = portal_size * 0.5
		rect.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		rect.color = color
		visual = rect
	node.add_child(visual)
	add_child(node)
	return node

func _update_portal(delta: float) -> void:
	if _portal.is_empty():
		return
	_portal["time_left"] = float(_portal.get("time_left", 0.0)) - delta
	if float(_portal["time_left"]) <= 0.0:
		_clear_portal()
		return
	# Portails MOUVANTS : oscillation horizontale opposée (sinus).
	_portal["phase"] = float(_portal.get("phase", 0.0)) + delta * TAU * maxf(0.01, float(_get_conf("portal_move_speed_hz", 0.35)))
	var amplitude: float = maxf(0.0, float(_get_conf("portal_move_amplitude_px", 120.0)))
	var viewport_size: Vector2 = get_viewport_rect().size
	var entry: Node2D = _portal.get("entry") as Node2D
	var exit: Node2D = _portal.get("exit") as Node2D
	var portal_size: Vector2 = _portal.get("size", Vector2(110, 18))
	if entry and is_instance_valid(entry):
		entry.global_position.x = clampf(float(_portal.get("entry_base_x", 0.0)) + sin(float(_portal["phase"])) * amplitude,
			portal_size.x * 0.5 + _wall_margin, viewport_size.x - portal_size.x * 0.5 - _wall_margin)
	if exit and is_instance_valid(exit):
		exit.global_position.x = clampf(float(_portal.get("exit_base_x", 0.0)) - sin(float(_portal["phase"])) * amplitude,
			portal_size.x * 0.5 + _wall_margin, viewport_size.x - portal_size.x * 0.5 - _wall_margin)

func _clear_portal() -> void:
	for key in ["entry", "exit"]:
		var node_v: Variant = _portal.get(key, null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_portal = {}

## La balle entre dans l'ORANGE et ressort par le BLEU avec la MÊME vélocité
## (direction et angle de pénétration conservés) — cooldown anti re-trigger.
func _apply_portal_to_ball(ball: Dictionary, pos: Vector2) -> Vector2:
	if _portal.is_empty() or float(ball.get("portal_cd", 0.0)) > 0.0:
		return pos
	var entry: Node2D = _portal.get("entry") as Node2D
	var exit: Node2D = _portal.get("exit") as Node2D
	if entry == null or not is_instance_valid(entry) or exit == null or not is_instance_valid(exit):
		return pos
	var portal_size: Vector2 = _portal.get("size", Vector2(110, 18))
	var half: Vector2 = portal_size * 0.5
	var e: Vector2 = entry.global_position
	if absf(pos.x - e.x) <= half.x + _ball_radius and absf(pos.y - e.y) <= half.y + _ball_radius:
		var vel: Vector2 = ball.get("vel", Vector2.DOWN)
		var out_dir: Vector2 = vel.normalized() if vel.length_squared() > 1.0 else Vector2.DOWN
		ball["portal_cd"] = 0.3
		if VFXManager:
			VFXManager.spawn_impact(e, 12.0, self)
			VFXManager.spawn_impact(exit.global_position, 12.0, self)
		return exit.global_position + out_dir * (half.y + _ball_radius + 4.0)
	return pos

# =============================================================================
# BARRIÈRES ÉLECTRIQUES (shield_orb : mur de renvoi derrière sa propre ligne)
# =============================================================================

## Ligne multi-couches (glow additifs + core opaque) — recette StarDrift.
func _build_shield_line(width: float, color: Color, additive: bool, z: int) -> Line2D:
	var line := Line2D.new()
	line.width = maxf(1.0, width)
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_as_relative = false
	line.z_index = z
	if additive:
		if _shield_material == null:
			_shield_material = CanvasItemMaterial.new()
			_shield_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		line.material = _shield_material
	add_child(line)
	return line

## Re-collect du même camp = simple reset du temps restant.
func _spawn_shield(side: String, duration: float) -> void:
	if _shields.has(side):
		var existing: Dictionary = _shields[side]
		existing["time"] = duration
		return
	var layers_v: Variant = _get_conf("shield_line_layers", [])
	var lines: Array = []
	if layers_v is Array:
		var idx: int = 0
		for layer_v in (layers_v as Array):
			if not (layer_v is Dictionary):
				continue
			var layer: Dictionary = layer_v as Dictionary
			var color := Color(str(layer.get("color", "#4FA8FF")))
			var width: float = float(layer.get("width_px", 8.0))
			var additive: bool = bool(layer.get("additive", true))
			lines.append(_build_shield_line(width, color, additive, 12 + idx))
			idx += 1
	if lines.is_empty():
		lines.append(_build_shield_line(6.0, Color("#5CE8FF"), false, 12))
	_shields[side] = { "time": duration, "lines": lines }
	_animate_shields()

func _free_shield(side: String) -> void:
	var shield_v: Variant = _shields.get(side, {})
	if shield_v is Dictionary:
		for line_v in ((shield_v as Dictionary).get("lines", []) as Array):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
	_shields.erase(side)

## Y de la barrière d'un camp : entre la raquette et son but.
func _shield_line_y(side: String) -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var offset_ratio: float = clampf(float(_get_conf("shield_offset_from_goal_ratio", 0.045)), 0.005, 0.2)
	if side == "player":
		return viewport_size.y * (1.0 - offset_ratio)
	return viewport_size.y * offset_ratio

## Ré-échantillonne chaque frame : sinusoïde qui défile + jitter aléatoire par
## point = arc électrique. Le MÊME tracé est assigné à toutes les couches.
func _animate_shields() -> void:
	if _shields.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var segments: int = maxi(4, int(_get_conf("shield_segments", 24)))
	var amplitude: float = maxf(0.0, float(_get_conf("shield_wave_amplitude_px", 6.0)))
	var speed: float = float(_get_conf("shield_wave_speed", 7.0))
	var freq: float = float(_get_conf("shield_wave_frequency", 0.045))
	var jitter: float = maxf(0.0, float(_get_conf("shield_jitter_px", 2.5)))
	var x_start: float = _wall_margin
	var x_end: float = viewport_size.x - _wall_margin
	for side_v in _shields.keys():
		var side: String = str(side_v)
		var y0: float = _shield_line_y(side)
		var points := PackedVector2Array()
		for i in range(segments + 1):
			var x: float = lerpf(x_start, x_end, float(i) / float(segments))
			var y: float = y0 + sin(x * freq + _elapsed * speed) * amplitude \
				+ randf_range(-jitter, jitter)
			points.append(Vector2(x, y))
		for line_v in ((_shields[side] as Dictionary).get("lines", []) as Array):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).points = points

## Réflexion : une balle qui franchit la ligne vers le but du propriétaire est
## renvoyée (renvois illimités pendant la durée). Le camp sauvé devient le
## dernier frappeur. Les missiles des raquettes armées TRAVERSENT la barrière
## (accordée à la balle uniquement). Écrit ball["vel"] (les briques mutent le
## dict après le write-back local de _step_ball).
func _apply_shields_to_ball(ball: Dictionary, pos: Vector2) -> Vector2:
	if _shields.is_empty():
		return pos
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	if _shields.has("player") and vel.y > 0.0:
		var y_player: float = _shield_line_y("player")
		if pos.y + _ball_radius >= y_player and pos.y - _ball_radius <= y_player:
			vel.y = -absf(vel.y)
			ball["vel"] = vel
			ball["hitter"] = "player"
			pos.y = y_player - _ball_radius
			if VFXManager:
				VFXManager.spawn_impact(Vector2(pos.x, y_player), 14.0, self)
	if _shields.has("enemy") and vel.y < 0.0:
		var y_enemy: float = _shield_line_y("enemy")
		if pos.y - _ball_radius <= y_enemy and pos.y + _ball_radius >= y_enemy:
			vel.y = absf(vel.y)
			ball["vel"] = vel
			ball["hitter"] = "enemy"
			pos.y = y_enemy + _ball_radius
			if VFXManager:
				VFXManager.spawn_impact(Vector2(pos.x, y_enemy), 14.0, self)
	return pos

# =============================================================================
# MUR DE BRIQUES CENTRAL (hybride breakout : creuser un passage)
# =============================================================================

## Mur procédural centré (<= wall_max_bricks briques). Powerup repris alors
## qu'un mur existe = refill des briques manquantes.
func _spawn_brick_wall() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var rows: int = clampi(int(_get_conf("wall_rows", 2)), 1, 4)
	var cols: int = clampi(int(_get_conf("wall_cols", 8)), 2, 12)
	var max_bricks: int = clampi(int(_get_conf("wall_max_bricks", 20)), 1, 20)
	var brick_h: float = maxf(12.0, float(_get_conf("wall_brick_height_px", 42.0)))
	var spacing: float = maxf(0.0, float(_get_conf("wall_brick_spacing_px", 5.0)))
	var side_margin: float = maxf(4.0, float(_get_conf("wall_side_margin_px", 26.0)))
	var brick_hp: int = maxi(1, int(_get_conf("wall_brick_hp", 2)))
	var brick_w: float = maxf(16.0, (viewport_size.x - side_margin * 2.0 - float(cols - 1) * spacing) / float(cols))
	var center_y: float = viewport_size.y * clampf(float(_get_conf("wall_center_y_ratio", 0.5)), 0.25, 0.75)
	var wall_h: float = float(rows) * brick_h + float(rows - 1) * spacing
	var assets_v: Variant = _get_conf("wall_brick_assets", [])
	var assets: Array = (assets_v as Array) if assets_v is Array else []
	var placed: int = _bricks.size()
	for row in range(rows):
		for col in range(cols):
			if placed >= max_bricks:
				return
			var center := Vector2(
				side_margin + brick_w * 0.5 + float(col) * (brick_w + spacing),
				center_y - wall_h * 0.5 + brick_h * 0.5 + float(row) * (brick_h + spacing))
			# Refill : ne pas doubler une brique déjà présente à cet emplacement.
			var occupied: bool = false
			for brick_v in _bricks:
				if ((brick_v as Dictionary).get("rect", Rect2()) as Rect2).get_center().distance_squared_to(center) < 16.0:
					occupied = true
					break
			if occupied:
				placed += 1
				continue
			var node := Node2D.new()
			node.z_as_relative = false
			node.z_index = 8
			var asset_path: String = str(assets[randi() % assets.size()]) if not assets.is_empty() else ""
			var visual: Node2D = _build_sprite_fit(asset_path, Vector2(brick_w, brick_h))
			if visual == null:
				var rect := Polygon2D.new()
				rect.polygon = PackedVector2Array([
					Vector2(-brick_w * 0.5, -brick_h * 0.5), Vector2(brick_w * 0.5, -brick_h * 0.5),
					Vector2(brick_w * 0.5, brick_h * 0.5), Vector2(-brick_w * 0.5, brick_h * 0.5)
				])
				rect.color = Color("#8A93A6")
				visual = rect
			node.add_child(visual)
			node.global_position = center
			add_child(node)
			_bricks.append({
				"node": node,
				"rect": Rect2(center - Vector2(brick_w, brick_h) * 0.5, Vector2(brick_w, brick_h)),
				"hp": brick_hp,
				"max_hp": brick_hp
			})
			placed += 1

## Cercle vs AABB : rebond sur la brique la plus proche (1 par sous-pas),
## brique -1 HP (assombrie), détruite -> VFX. Retourne la position corrigée.
func _collide_ball_bricks(ball: Dictionary, pos: Vector2) -> Vector2:
	if _bricks.is_empty():
		return pos
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	for i in range(_bricks.size() - 1, -1, -1):
		var brick: Dictionary = _bricks[i]
		var rect: Rect2 = brick.get("rect", Rect2())
		var closest := Vector2(
			clampf(pos.x, rect.position.x, rect.end.x),
			clampf(pos.y, rect.position.y, rect.end.y))
		var d: Vector2 = pos - closest
		if d.length_squared() > _ball_radius * _ball_radius:
			continue
		var normal: Vector2
		if d.length_squared() > 0.0001:
			normal = d.normalized()
		else:
			var center_delta: Vector2 = pos - rect.get_center()
			if absf(center_delta.x) / maxf(1.0, rect.size.x) > absf(center_delta.y) / maxf(1.0, rect.size.y):
				normal = Vector2(signf(center_delta.x), 0.0)
			else:
				normal = Vector2(0.0, signf(center_delta.y))
		if vel.dot(normal) < 0.0:
			ball["vel"] = vel.bounce(normal)
		pos = closest + normal * (_ball_radius + 0.5)
		brick["hp"] = int(brick.get("hp", 1)) - 1
		var node_v: Variant = brick.get("node", null)
		if int(brick["hp"]) <= 0:
			if node_v is Node2D and is_instance_valid(node_v):
				if VFXManager:
					VFXManager.spawn_impact(rect.get_center(), 14.0, self)
				(node_v as Node2D).queue_free()
			_bricks.remove_at(i)
		elif node_v is Node2D and is_instance_valid(node_v):
			var brightness: float = lerpf(0.55, 1.0, float(brick["hp"]) / float(maxi(1, int(brick.get("max_hp", 1)))))
			(node_v as Node2D).modulate = Color(brightness, brightness, brightness, 1.0)
		break
	return pos

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
