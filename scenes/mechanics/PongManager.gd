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
## - time_slow : armé à la collecte — la première balle qui entre dans le camp
##   du propriétaire déclenche un ralenti global (balles/IA/missiles), l'input
##   joueur reste temps réel.
## - ghost_ball : les balles du propriétaire traversent le mur central ET les
##   barrières shield_orb pendant duration_sec (alpha réduit).
## - crystal_trail : chaque rebond (mur/raquette/brique) d'une balle du
##   propriétaire lâche un cristal (cap crystal_trail_max_crystals).
## POWERUPS "MODE" (category "mode", cooldown global partagé
## mode_powerup_cooldown_sec entre deux collectes de mode) :
## - shrink_walls : les murs latéraux se resserrent (inset progressif), écrasent
##   briques/powerups recouverts ; reset au but, retrait en fin d'effet.
## - wind : vent latéral global sur toutes les balles (flips télégraphiés),
##   avec traits + débris visuels dans le sens du vent.
## - blackout : pénombre plein écran, trous de lumière sur balle/raquettes/
##   powerups/portails (shader pong_blackout.gdshader).
## - heavy_ball : balles plus grosses et plus lentes, dégâts/cristaux de but
##   x heavy_ball_goal_mult.
## TIE-BREAK automatique : tiebreak_after_sec sans but -> splash central,
## vitesse x tiebreak_speed_mult et enjeux x tiebreak_reward_mult jusqu'au
## prochain but (re-déclenchable).
## ÉVÉNEMENTS (off par défaut, activés par vague/freemode) :
## - invasion : drones traversants qui dévient la balle (rebond radial),
##   destructibles par les missiles armed_paddle.
## - meteor : boss décoratif destructible au centre (1 impact de balle = -1 HP,
##   rebond radial), destruction = cristaux + score ; respawn optionnel (libre).
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
var _ball_radius_base: float = 16.0 # rayon data — _ball_radius = base × heavy
var _ball_base_speed: float = 420.0
var _ball_speed_max: float = 900.0
var _ball_speed_increase: float = 15.0
var _max_bounce_angle_deg: float = 55.0
var _min_vy_ratio: float = 0.26 # sin(15°) : interdit les trajectoires à 75-105° de la verticale
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

# --- Powerups classiques additionnels (side -> secondes restantes) ---
# time_slow : armé à la collecte, déclenché quand une balle entre dans la
# moitié du propriétaire ; ralenti global sauf input joueur.
var _time_slow_armed: Dictionary = {}
var _time_slow_left: float = 0.0
var _time_slow_factor: float = 0.5
var _time_slow_vignette: ColorRect = null
# ghost_ball : les balles du side traversent briques et barrières.
var _ghost: Dictionary = {}
# crystal_trail : rebonds -> cristaux (budget par activation).
var _crystal_trail: Dictionary = {}
var _crystal_trail_budget: Dictionary = {}
var _crystal_trail_max: int = 10

# --- Powerups "mode" (globaux, cooldown partagé) ---
var _mode_cooldown: float = 0.0
var _mode_cooldown_sec: float = 60.0
# shrink_walls : inset des murs latéraux appliqué aux rebonds/clamps.
var _shrink_walls_time: float = 0.0
var _wall_inset: float = 0.0
var _shrink_walls_speed: float = 28.0
var _shrink_walls_max_ratio: float = 0.22
var _shrink_wall_lines: Array = [] # [{ "sign": -1/1, "lines": Array[Line2D] }]
# wind : courbure latérale globale + traits/débris visuels.
var _wind_time: float = 0.0
var _wind_dir: int = 1
var _wind_flip_timer: float = 0.0
var _wind_strength: float = 900.0
var _wind_flip_interval: float = 6.0
var _wind_telegraph_sec: float = 1.0
var _wind_fx: WindFX = null
# blackout : pénombre à trous de lumière (shader).
var _blackout_time: float = 0.0
var _blackout_total: float = 0.0
var _blackout_rect: ColorRect = null
# heavy_ball : rayon/vitesse des balles + multiplicateur des buts.
var _heavy_time: float = 0.0
var _heavy_radius_mult: float = 1.5
var _heavy_speed_mult: float = 0.8
var _heavy_goal_mult: float = 1.5

# --- Tie-break automatique (tiebreak_after_sec sans but) ---
var _since_goal: float = 0.0
var _tiebreak_after: float = 30.0
var _tiebreak_speed_mult: float = 1.5
var _tiebreak_reward_mult: float = 2.0
var _tiebreak_active: bool = false

# --- Événement invasion : drones traversants ---
var _invasion_chance: float = 0.0
var _invasion_interval: float = 25.0
var _invasion_timer: float = 25.0
var _invasion_pending: float = 0.0
var _invasion_from_left: bool = true
var _invasion_arrow: Label = null
var _drones: Array = [] # { "node", "pos", "dir", "speed", "radius", "hit_cd" }

# --- Événement météore central : boss destructible ---
var _meteor_enabled: bool = false
var _meteor: Dictionary = {} # { "node", "pos", "radius", "hp", "max_hp", "label", "arriving", "hit_cd" }
var _meteor_spawned_once: bool = false
var _meteor_respawn_timer: float = 0.0

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
	_ball_radius_base = _ball_radius
	_ball_base_speed = maxf(60.0, float(_config.get("ball_speed_px_sec", _cfg.get("ball_speed_px_sec_default", 420.0))))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	_ball_speed_increase = maxf(0.0, float(_cfg.get("ball_speed_increase_per_hit", 15.0)))
	_max_bounce_angle_deg = clampf(float(_cfg.get("ball_max_bounce_angle_deg", 55.0)), 10.0, 80.0)
	_min_vy_ratio = clampf(float(_cfg.get("ball_min_vy_ratio", 0.26)), 0.02, 0.9)
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

	# Nouveaux powerups / modes / événements (2026-07).
	_mode_cooldown_sec = maxf(0.0, float(_get_conf("mode_powerup_cooldown_sec", 60.0)))
	_time_slow_factor = clampf(float(_get_conf("time_slow_factor", 0.5)), 0.1, 1.0)
	_crystal_trail_max = maxi(1, int(_get_conf("crystal_trail_max_crystals", 10)))
	_shrink_walls_speed = maxf(1.0, float(_get_conf("shrink_walls_px_sec", 28.0)))
	_shrink_walls_max_ratio = clampf(float(_get_conf("shrink_walls_max_inset_ratio", 0.22)), 0.02, 0.4)
	_wind_strength = maxf(0.0, float(_get_conf("wind_strength_px_sec2", 900.0)))
	_wind_flip_interval = maxf(1.0, float(_get_conf("wind_flip_interval_sec", 6.0)))
	_wind_telegraph_sec = clampf(float(_get_conf("wind_telegraph_sec", 1.0)), 0.2, _wind_flip_interval)
	_heavy_radius_mult = maxf(1.0, float(_get_conf("heavy_ball_radius_mult", 1.5)))
	_heavy_speed_mult = clampf(float(_get_conf("heavy_ball_speed_mult", 0.8)), 0.3, 1.0)
	_heavy_goal_mult = maxf(1.0, float(_get_conf("heavy_ball_goal_mult", 1.5)))
	_tiebreak_after = maxf(0.0, float(_get_conf("tiebreak_after_sec", 30.0)))
	_tiebreak_speed_mult = maxf(1.0, float(_get_conf("tiebreak_speed_mult", 1.5)))
	_tiebreak_reward_mult = maxf(1.0, float(_get_conf("tiebreak_reward_mult", 2.0)))
	_invasion_chance = clampf(float(_get_conf("invasion_chance", 0.0)), 0.0, 1.0)
	_invasion_interval = maxf(3.0, float(_get_conf("invasion_interval_sec", 25.0)))
	_invasion_timer = _invasion_interval
	_meteor_enabled = bool(_get_conf("meteor_enabled", false))

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
	_invasion_chance = clampf(float(cfg.get("invasion_chance", _invasion_chance)), 0.0, 1.0)
	# Clés relues au prochain spawn (drones / météore) : poussées dans _config
	# pour que _get_conf les voie sans re-setup.
	for live_key in ["invasion_drone_speed_px_sec", "meteor_hp_base", "meteor_respawn_interval_sec"]:
		if cfg.has(live_key):
			_config[live_key] = cfg[live_key]

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
	var visual: Node2D = _build_sprite_fit(ball_asset, Vector2.ONE * _ball_radius_base * 2.0)
	if visual == null:
		visual = _build_ball_circle()
	node.add_child(visual)
	node.global_position = pos
	# heavy_ball : le node porte l'échelle du rayon effectif (visuel = base).
	node.scale = Vector2.ONE * (_ball_radius / maxf(1.0, _ball_radius_base))
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
		points.append(Vector2(cos(a), sin(a)) * _ball_radius_base)
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
	# time_slow : la SIMULATION (balles, IA, missiles, portails, drones,
	# météore) tourne au ralenti ; les timers d'effets, le spawn de powerups et
	# l'input joueur restent en temps réel.
	var sim: float = delta * (_time_slow_factor if _time_slow_left > 0.0 else 1.0)
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_reset_ball(1) # first serve goes toward the player
		State.SERVE:
			_update_enemy_paddle(sim)
			_update_powerups(delta)
			_update_missiles(sim)
			_update_portal(sim)
			_update_invasion(sim)
			_update_meteor(sim)
			_update_effect_timers(delta)
			_update_mode_effects(delta)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_serve()
		State.PLAY:
			_update_enemy_paddle(sim)
			_update_balls(sim)
			_update_powerups(delta)
			_update_missiles(sim)
			_update_portal(sim)
			_update_invasion(sim)
			_update_meteor(sim)
			_update_effect_timers(delta)
			_update_mode_effects(delta)
			_check_time_slow_trigger()
			_update_tiebreak(delta)
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
	var serve_speed: float = _ball_base_speed * _speed_mult()
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		ball["speed"] = serve_speed
		ball["vel"] = Vector2(sin(angle), cos(angle) * float(_serve_dir)) * serve_speed
	_state = State.PLAY

## Multiplicateur global de vitesse de balle (heavy_ball × tie-break).
func _speed_mult() -> float:
	var mult: float = 1.0
	if _heavy_time > 0.0:
		mult *= _heavy_speed_mult
	if _tiebreak_active:
		mult *= _tiebreak_speed_mult
	return mult

## Multiplicateur des enjeux de but (dégâts ET cristaux) — heavy × tie-break.
func _goal_reward_mult() -> float:
	var mult: float = 1.0
	if _heavy_time > 0.0:
		mult *= _heavy_goal_mult
	if _tiebreak_active:
		mult *= _tiebreak_reward_mult
	return mult

## Re-scale les vitesses des balles EN VOL (activation/expiration heavy/tiebreak).
func _rescale_ball_speeds(factor: float) -> void:
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		var speed: float = maxf(30.0, float(ball.get("speed", _ball_base_speed)) * factor)
		ball["speed"] = speed
		var vel: Vector2 = ball.get("vel", Vector2.ZERO)
		if vel.length_squared() > 1.0:
			ball["vel"] = vel.normalized() * speed

func _update_balls(delta: float) -> void:
	var remaining: float = minf(delta, 0.25)
	# Anti-tunneling recalé sur la vitesse max EFFECTIVE (le tie-break peut
	# dépasser _ball_speed_max nominal).
	var step_cap: float = minf(MAX_BALL_STEP_SEC,
		(_ball_radius * 1.5) / maxf(1.0, _ball_speed_max * _speed_mult()))
	while remaining > 0.0 and _state == State.PLAY:
		var step: float = minf(remaining, step_cap)
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
	# Vent latéral global (powerup mode "wind") : même pattern que la courbe —
	# nudge horizontal puis renormalisation à la vitesse scalaire.
	if _wind_time > 0.0 and vel.length_squared() > 1.0:
		vel = (vel + Vector2(float(_wind_dir) * _wind_strength * step, 0.0)).normalized() \
			* float(ball.get("speed", _ball_base_speed))
	var pos: Vector2 = node.global_position + vel * step

	# Side walls: reflect and re-seat on the wall to avoid double bounces.
	# _wall_inset > 0 = murs rétrécissants (powerup mode "shrink_walls").
	var left_x: float = _wall_margin + _wall_inset + _ball_radius
	var right_x: float = viewport_size.x - _wall_margin - _wall_inset - _ball_radius
	if pos.x <= left_x and vel.x < 0.0:
		pos.x = left_x
		vel.x = -vel.x
		vel = _enforce_min_vertical(vel, float(ball.get("speed", _ball_base_speed)))
		ball["vel"] = vel
		_on_ball_bounced(ball, pos)
	elif pos.x >= right_x and vel.x > 0.0:
		pos.x = right_x
		vel.x = -vel.x
		vel = _enforce_min_vertical(vel, float(ball.get("speed", _ball_base_speed)))
		ball["vel"] = vel
		_on_ball_bounced(ball, pos)

	# Player paddle (bottom): only intercepts a ball travelling downward.
	# Sweep du plan superieur : la balle est posee au point d'impact EXACT du
	# substep (fini le re-seat vertical brutal qui teleportait la balle sur
	# les arrivees de biais — courbe/vent — et les contacts lateraux).
	if vel.y > 0.0 and _player and is_instance_valid(_player):
		var p: Vector2 = _player.global_position
		var p_half: Vector2 = _paddle_half_extents("player")
		var plane_y: float = p.y - p_half.y - _ball_radius
		var prev: Vector2 = node.global_position
		if prev.y <= plane_y and pos.y > plane_y:
			var t: float = (plane_y - prev.y) / maxf(0.0001, pos.y - prev.y)
			var hit_x: float = lerpf(prev.x, pos.x, t)
			if absf(hit_x - p.x) <= p_half.x + _ball_radius:
				pos = Vector2(hit_x, plane_y)
				ball["vel"] = vel
				vel = _bounce_off_paddle(ball, hit_x, p.x, p_half.x, true)
				ball["hitter"] = "player"
				_on_ball_bounced(ball, pos)
		elif _circle_hits_paddle(pos, p, p_half):
			if pos.y <= p.y:
				# Coin/flanc haut : rebond sans correction de position.
				ball["vel"] = vel
				vel = _bounce_off_paddle(ball, pos.x, p.x, p_half.x, true)
				ball["hitter"] = "player"
				_on_ball_bounced(ball, pos)
			else:
				# Flanc bas : repousse laterale minimale, la balle file au but.
				var push_sign: float = 1.0 if pos.x >= p.x else -1.0
				pos.x = p.x + push_sign * (p_half.x + _ball_radius)
				if (vel.x > 0.0) != (push_sign > 0.0):
					vel.x = -vel.x

	# Enemy paddle (top): only intercepts a ball travelling upward.
	# Miroir du sweep joueur (plan inferieur de la raquette CPU).
	if vel.y < 0.0 and _enemy_paddle and is_instance_valid(_enemy_paddle):
		var e: Vector2 = _enemy_paddle.global_position
		var e_half: Vector2 = _paddle_half_extents("enemy")
		var plane_y_e: float = e.y + e_half.y + _ball_radius
		var prev_e: Vector2 = node.global_position
		if prev_e.y >= plane_y_e and pos.y < plane_y_e:
			var t_e: float = (plane_y_e - prev_e.y) / minf(-0.0001, pos.y - prev_e.y)
			var hit_x_e: float = lerpf(prev_e.x, pos.x, t_e)
			if absf(hit_x_e - e.x) <= e_half.x + _ball_radius:
				pos = Vector2(hit_x_e, plane_y_e)
				ball["vel"] = vel
				vel = _bounce_off_paddle(ball, hit_x_e, e.x, e_half.x, false)
				ball["hitter"] = "enemy"
				_on_ball_bounced(ball, pos)
		elif _circle_hits_paddle(pos, e, e_half):
			if pos.y >= e.y:
				# Coin/flanc bas : rebond sans correction de position.
				ball["vel"] = vel
				vel = _bounce_off_paddle(ball, pos.x, e.x, e_half.x, false)
				ball["hitter"] = "enemy"
				_on_ball_bounced(ball, pos)
			else:
				# Flanc haut : repousse laterale minimale, la balle file au but.
				var push_sign_e: float = 1.0 if pos.x >= e.x else -1.0
				pos.x = e.x + push_sign_e * (e_half.x + _ball_radius)
				if (vel.x > 0.0) != (push_sign_e > 0.0):
					vel.x = -vel.x

	ball["vel"] = vel
	# Mur de briques central : rebond + dégât de brique.
	pos = _collide_ball_bricks(ball, pos)
	# Drones d'invasion et météore central : rebonds radiaux.
	pos = _collide_ball_drones(ball, pos)
	pos = _collide_ball_meteor(ball, pos)
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

## Anti-blocage : une trajectoire quasi horizontale (75-105° vs la verticale)
## rebondit indéfiniment entre les murs gauche/droite. Au rebond de mur, la
## composante verticale est ramenée au minimum (ball_min_vy_ratio de la vitesse,
## 0.26 = sin(15°)) en conservant la vitesse scalaire et les signes.
func _enforce_min_vertical(vel: Vector2, speed: float) -> Vector2:
	var min_vy: float = speed * _min_vy_ratio
	if absf(vel.y) >= min_vy:
		return vel
	var sign_y: float = -1.0 if vel.y <= 0.0 else 1.0
	var vx_mag: float = sqrt(maxf(0.0, speed * speed - min_vy * min_vy))
	return Vector2(vx_mag * (1.0 if vel.x >= 0.0 else -1.0), sign_y * min_vy)

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
	var speed: float = minf(float(ball.get("speed", _ball_base_speed)) + _ball_speed_increase,
		_ball_speed_max * _speed_mult())
	ball["speed"] = speed
	return dir * speed

## Rebond d'une balle (mur/raquette/brique) : crystal_trail lâche un cristal
## sur place tant que le hitter porte l'effet et que le budget reste positif.
func _on_ball_bounced(ball: Dictionary, at_pos: Vector2) -> void:
	var side: String = str(ball.get("hitter", ""))
	if side == "" or float(_crystal_trail.get(side, 0.0)) <= 0.0:
		return
	var budget: int = int(_crystal_trail_budget.get(side, 0))
	if budget <= 0:
		return
	_crystal_trail_budget[side] = budget - 1
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", at_pos)

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
	var min_x: float = _wall_margin + _wall_inset + e_half.x
	var max_x: float = viewport_size.x - _wall_margin - _wall_inset - e_half.x
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
	# Multiplicateur d'enjeux lu AVANT _register_goal (qui coupe le tie-break).
	var reward_mult: float = _goal_reward_mult()
	_register_goal()
	# But encaissé = pénalité (pas d'esquive possible : ignore_dodge).
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP; die() below 0.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent * reward_mult)))
		_player.call("take_damage", dmg, true)

func _on_player_scored() -> void:
	_serve_dir = 1
	var crystals: int = maxi(0, int(round(float(_crystals_per_point) * _goal_reward_mult())))
	_register_goal()
	if _game and is_instance_valid(_game) and _game.has_method("spawn_pong_reward_crystals"):
		_game.call("spawn_pong_reward_crystals", crystals)

## Après CHAQUE but : reset du compteur tie-break (et de son état actif), et
## les murs rétrécissants repartent de la largeur pleine (reset au but).
func _register_goal() -> void:
	_since_goal = 0.0
	if _tiebreak_active:
		_tiebreak_active = false
		_rescale_ball_speeds(1.0 / maxf(1.0, _tiebreak_speed_mult))
	_wall_inset = 0.0

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
	# Les powerups "mode" (category "mode" : shrink_walls, wind, blackout,
	# heavy_ball) partagent un cooldown global — exclus de la roulette tant
	# qu'il court, la pondération se refait sur les défs restantes.
	var eligible: Array = []
	for def_v in _powerup_pool:
		if not (def_v is Dictionary):
			continue
		if _mode_cooldown > 0.0 and str((def_v as Dictionary).get("category", "")) == "mode":
			continue
		eligible.append(def_v)
	var total: float = 0.0
	for def_v in eligible:
		total += maxf(0.0, float((def_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var roll: float = randf() * total
	for def_v in eligible:
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
		"time_slow":
			# Armé : se déclenchera quand une balle entrera dans la moitié du
			# propriétaire (_check_time_slow_trigger).
			_time_slow_armed[hitter_id] = duration
		"ghost_ball":
			_ghost[hitter_id] = duration
		"crystal_trail":
			_crystal_trail[hitter_id] = duration
			_crystal_trail_budget[hitter_id] = _crystal_trail_max
		"shrink_walls":
			_shrink_walls_time = maxf(_shrink_walls_time, duration)
		"wind":
			if _wind_time <= 0.0:
				_wind_dir = 1 if randf() < 0.5 else -1
				_wind_flip_timer = _wind_flip_interval
			_wind_time = maxf(_wind_time, duration)
		"blackout":
			_blackout_time = maxf(_blackout_time, duration)
			_blackout_total = _blackout_time
			_ensure_blackout_overlay()
		"heavy_ball":
			if _heavy_time <= 0.0:
				_rescale_ball_speeds(_heavy_speed_mult)
				_set_ball_radius_mult(_heavy_radius_mult)
			_heavy_time = maxf(_heavy_time, duration)
		_:
			pass
	# Un powerup "mode" collecté déclenche le cooldown global de la catégorie.
	if str(def.get("category", "")) == "mode":
		_mode_cooldown = _mode_cooldown_sec
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
		if _ghost.has(side):
			_ghost[side] = float(_ghost[side]) - delta
			if float(_ghost[side]) <= 0.0:
				_ghost.erase(side)
		if _crystal_trail.has(side):
			_crystal_trail[side] = float(_crystal_trail[side]) - delta
			if float(_crystal_trail[side]) <= 0.0:
				_crystal_trail.erase(side)
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
	# Balles fantômes : alpha réduit tant que leur hitter porte l'effet.
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		var ball_node: Node2D = ball.get("node") as Node2D
		if ball_node and is_instance_valid(ball_node):
			ball_node.modulate.a = 0.55 if float(_ghost.get(str(ball.get("hitter", "")), 0.0)) > 0.0 else 1.0

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
		# Détruit les drones d'invasion (missiles des deux camps).
		if not consumed:
			for j in range(_drones.size() - 1, -1, -1):
				var drone: Dictionary = _drones[j]
				var d_pos: Vector2 = drone.get("pos", Vector2.ZERO)
				var d_reach: float = float(drone.get("radius", 26.0)) + 8.0
				if pos.distance_squared_to(d_pos) <= d_reach * d_reach:
					if VFXManager:
						VFXManager.spawn_impact(d_pos, 18.0, self)
					var d_node: Variant = drone.get("node", null)
					if d_node is Node2D and is_instance_valid(d_node):
						(d_node as Node2D).queue_free()
					_drones.remove_at(j)
					if _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
						_game.call("add_wave_bonus_score", maxi(0, int(_get_conf("invasion_drone_score", 25))), pos)
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
func _spawn_portal_pair(duration: float, owner_side: String = "player") -> void:
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
	if owner_side == "enemy":
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
	# Balle fantôme (ghost_ball) : traverse les barrières (les deux camps).
	if float(_ghost.get(str(ball.get("hitter", "")), 0.0)) > 0.0:
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
	# Balle fantôme (ghost_ball) : traverse le mur central.
	if float(_ghost.get(str(ball.get("hitter", "")), 0.0)) > 0.0:
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
		_on_ball_bounced(ball, pos)
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
# TIE-BREAK AUTOMATIQUE + TIME_SLOW (déclencheur / vignette)
# =============================================================================

## tiebreak_after_sec sans but -> splash + vitesse et enjeux multipliés
## jusqu'au prochain but (_register_goal désactive et remet le compteur à 0).
func _update_tiebreak(delta: float) -> void:
	if _tiebreak_after <= 0.0 or _tiebreak_active:
		return
	_since_goal += delta
	if _since_goal >= _tiebreak_after:
		_tiebreak_active = true
		_rescale_ball_speeds(_tiebreak_speed_mult)
		_show_tiebreak_splash()

func _show_tiebreak_splash() -> void:
	var title: String = _translate_or("pong_tiebreak_title", "TIE BREAK")
	var sub: String = _translate_or("pong_tiebreak_sub", "Speed and stakes doubled!")
	if _game and is_instance_valid(_game) and _game.has_method("show_center_splash"):
		_game.call("show_center_splash", title, sub, "#FF5C5C")
	elif VFXManager:
		VFXManager.spawn_floating_text(get_viewport_rect().size * 0.5, title, Color("#FF5C5C"), self)

func _translate_or(key: String, fallback: String) -> String:
	if LocaleManager:
		var text: String = LocaleManager.translate(key)
		if text != "" and text != key:
			return text
	return fallback

## time_slow armé : la première balle qui entre dans la moitié du propriétaire
## déclenche le ralenti (player = moitié basse, enemy = moitié haute).
func _check_time_slow_trigger() -> void:
	if _time_slow_armed.is_empty():
		return
	var half_y: float = get_viewport_rect().size.y * 0.5
	for ball_v in _balls:
		var node: Node2D = (ball_v as Dictionary).get("node") as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var y: float = node.global_position.y
		for side_v in _time_slow_armed.keys():
			var side: String = str(side_v)
			if (side == "player" and y > half_y) or (side == "enemy" and y < half_y):
				_time_slow_left = maxf(_time_slow_left, float(_time_slow_armed[side]))
				_time_slow_armed.erase(side)
				_ensure_time_slow_vignette()
		if _time_slow_armed.is_empty():
			break

func _ensure_time_slow_vignette() -> void:
	if _time_slow_vignette == null or not is_instance_valid(_time_slow_vignette):
		_time_slow_vignette = ColorRect.new()
		_time_slow_vignette.color = Color(str(_get_conf("time_slow_vignette_color", "#4AA8FF1E")))
		_time_slow_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_time_slow_vignette.z_as_relative = false
		_time_slow_vignette.z_index = 45
		add_child(_time_slow_vignette)
	_time_slow_vignette.position = Vector2.ZERO
	_time_slow_vignette.size = get_viewport_rect().size
	_time_slow_vignette.visible = true

# =============================================================================
# POWERUPS "MODE" (shrink_walls / wind / blackout / heavy_ball) — timers réels
# =============================================================================

func _update_mode_effects(delta: float) -> void:
	_mode_cooldown = maxf(0.0, _mode_cooldown - delta)
	if _time_slow_left > 0.0:
		_time_slow_left = maxf(0.0, _time_slow_left - delta)
		if _time_slow_left <= 0.0 and _time_slow_vignette and is_instance_valid(_time_slow_vignette):
			_time_slow_vignette.visible = false
	if _heavy_time > 0.0:
		_heavy_time -= delta
		if _heavy_time <= 0.0:
			_heavy_time = 0.0
			_rescale_ball_speeds(1.0 / maxf(0.05, _heavy_speed_mult))
			_set_ball_radius_mult(1.0)
	_update_shrink_walls(delta)
	_update_wind(delta)
	_update_blackout(delta)

## heavy_ball : _ball_radius (collision) = base × mult, le node de chaque balle
## porte l'échelle correspondante (les visuels sont construits à la taille base).
func _set_ball_radius_mult(mult: float) -> void:
	_ball_radius = _ball_radius_base * maxf(0.1, mult)
	for ball_v in _balls:
		var node: Node2D = (ball_v as Dictionary).get("node") as Node2D
		if node and is_instance_valid(node):
			node.scale = Vector2.ONE * maxf(0.1, mult)

# --- shrink_walls : murs latéraux mobiles ---

func _update_shrink_walls(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if _shrink_walls_time > 0.0:
		_shrink_walls_time -= delta
		_wall_inset = minf(_wall_inset + _shrink_walls_speed * delta,
			viewport_size.x * _shrink_walls_max_ratio)
	elif _wall_inset > 0.0:
		# Fin d'effet : retrait des murs (4× plus vite qu'ils n'avancent).
		_wall_inset = maxf(0.0, _wall_inset - _shrink_walls_speed * 4.0 * delta)
	if _wall_inset <= 0.0 and _shrink_walls_time <= 0.0:
		_free_shrink_wall_lines()
		return
	_crush_out_of_bounds(viewport_size)
	_ensure_shrink_wall_lines()
	_animate_shrink_walls(viewport_size)

## Les murs mobiles "écrasent" ce qu'ils recouvrent : briques du mur central
## (explosion visuelle, sans récompense) et powerups (despawn).
func _crush_out_of_bounds(viewport_size: Vector2) -> void:
	var left_bound: float = _wall_margin + _wall_inset
	var right_bound: float = viewport_size.x - _wall_margin - _wall_inset
	for i in range(_bricks.size() - 1, -1, -1):
		var rect: Rect2 = (_bricks[i] as Dictionary).get("rect", Rect2())
		if rect.position.x < left_bound or rect.end.x > right_bound:
			if VFXManager:
				VFXManager.spawn_impact(rect.get_center(), 16.0, self)
			var node_v: Variant = (_bricks[i] as Dictionary).get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_bricks.remove_at(i)
	for i in range(_powerups.size() - 1, -1, -1):
		var powerup: Dictionary = _powerups[i]
		var p_pos: Vector2 = powerup.get("pos", Vector2.ZERO)
		var radius: float = float(powerup.get("radius", 22.0))
		if p_pos.x - radius < left_bound or p_pos.x + radius > right_bound:
			_free_powerup(powerup)
			_powerups.remove_at(i)

func _ensure_shrink_wall_lines() -> void:
	if not _shrink_wall_lines.is_empty():
		return
	var layers_v: Variant = _get_conf("shrink_walls_line_layers", [])
	for side_sign in [-1, 1]:
		var lines: Array = []
		if layers_v is Array:
			var idx: int = 0
			for layer_v in (layers_v as Array):
				if not (layer_v is Dictionary):
					continue
				var layer: Dictionary = layer_v as Dictionary
				lines.append(_build_shield_line(float(layer.get("width_px", 8.0)),
					Color(str(layer.get("color", "#FF9A3C"))), bool(layer.get("additive", true)), 13 + idx))
				idx += 1
		if lines.is_empty():
			lines.append(_build_shield_line(5.0, Color("#FF9A3C"), false, 13))
		_shrink_wall_lines.append({ "sign": side_sign, "lines": lines })

## Tracé vertical électrique (même recette que les barrières shield_orb).
func _animate_shrink_walls(viewport_size: Vector2) -> void:
	var segments: int = 16
	var jitter: float = maxf(0.0, float(_get_conf("shield_jitter_px", 2.5)))
	for wall_v in _shrink_wall_lines:
		var wall: Dictionary = wall_v as Dictionary
		var x0: float = (_wall_margin + _wall_inset) if int(wall.get("sign", -1)) < 0 \
			else (viewport_size.x - _wall_margin - _wall_inset)
		var points := PackedVector2Array()
		for i in range(segments + 1):
			var y: float = viewport_size.y * float(i) / float(segments)
			points.append(Vector2(
				x0 + sin(y * 0.045 + _elapsed * 7.0) * 4.0 + randf_range(-jitter, jitter), y))
		for line_v in (wall.get("lines", []) as Array):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).points = points

func _free_shrink_wall_lines() -> void:
	for wall_v in _shrink_wall_lines:
		for line_v in ((wall_v as Dictionary).get("lines", []) as Array):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
	_shrink_wall_lines.clear()

# --- wind : flips télégraphiés + traits/débris dans le sens du vent ---

func _update_wind(delta: float) -> void:
	if _wind_time <= 0.0:
		if _wind_fx != null and _wind_fx.is_active():
			_wind_fx.clear()
		return
	_wind_time -= delta
	if _wind_time <= 0.0:
		if _wind_fx != null:
			_wind_fx.clear()
		return
	_wind_flip_timer -= delta
	var telegraphing: bool = _wind_flip_timer <= _wind_telegraph_sec
	if _wind_flip_timer <= 0.0:
		_wind_dir = -_wind_dir
		_wind_flip_timer = _wind_flip_interval
		telegraphing = false
	if _wind_fx == null:
		_wind_fx = WindFX.new(self, {
			"streak_count": int(_get_conf("wind_streak_count", 14)),
			"streak_color": str(_get_conf("wind_streak_color", "#9AD8FF66")),
			"debris_count": int(_get_conf("wind_debris_count", 6)),
			"debris_color": str(_get_conf("wind_debris_color", "#C8E8FFAA")),
		})
	_wind_fx.ensure_visuals()
	# Flèche de télégraphe : direction du PROCHAIN flip, visible seulement
	# pendant le telegraph — le vent actif est montré par les traits.
	_wind_fx.update_arrow(telegraphing, Vector2(float(-_wind_dir), 0.0), _elapsed)
	_wind_fx.animate(delta, Vector2(float(_wind_dir), 0.0))

# --- blackout : pénombre à trous de lumière ---

const BLACKOUT_MAX_LIGHTS: int = 16
const BLACKOUT_SHADER_PATH: String = "res://scenes/mechanics/pong_blackout.gdshader"

func _ensure_blackout_overlay() -> void:
	if _blackout_rect and is_instance_valid(_blackout_rect):
		return
	_blackout_rect = ColorRect.new()
	_blackout_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout_rect.z_as_relative = false
	_blackout_rect.z_index = 40
	_blackout_rect.position = Vector2.ZERO
	_blackout_rect.size = get_viewport_rect().size
	if ResourceLoader.exists(BLACKOUT_SHADER_PATH):
		var shader: Shader = load(BLACKOUT_SHADER_PATH) as Shader
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_blackout_rect.material = mat
	if _blackout_rect.material == null:
		# Fallback sans shader : pénombre légère uniforme (pas de trous).
		_blackout_rect.color = Color(0.0, 0.0, 0.0, 0.5)
	add_child(_blackout_rect)

func _update_blackout(delta: float) -> void:
	if _blackout_time <= 0.0:
		return
	_blackout_time -= delta
	if _blackout_time <= 0.0:
		if _blackout_rect and is_instance_valid(_blackout_rect):
			_blackout_rect.queue_free()
		_blackout_rect = null
		return
	if _blackout_rect == null or not is_instance_valid(_blackout_rect):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_blackout_rect.size = viewport_size
	# Fade in/out (0.4 s) aux deux bouts de l'effet.
	var fade: float = clampf(minf(_blackout_time, _blackout_total - _blackout_time) / 0.4, 0.0, 1.0)
	var darkness: float = clampf(float(_get_conf("blackout_opacity", 0.85)), 0.0, 1.0) * fade
	var mat: ShaderMaterial = _blackout_rect.material as ShaderMaterial
	if mat == null:
		_blackout_rect.color = Color(0.0, 0.0, 0.0, 0.5 * fade)
		return
	# Trous de lumière : balles, raquettes, powerups, portails, météore, drones.
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	var ball_r: float = maxf(20.0, float(_get_conf("blackout_light_radius_ball_px", 90.0)))
	var paddle_r: float = maxf(40.0, float(_get_conf("blackout_light_radius_paddle_px", 150.0)))
	var item_r: float = maxf(20.0, float(_get_conf("blackout_light_radius_item_px", 95.0)))
	for ball_v in _balls:
		if positions.size() >= BLACKOUT_MAX_LIGHTS:
			break
		var ball_node: Node2D = (ball_v as Dictionary).get("node") as Node2D
		if ball_node and is_instance_valid(ball_node):
			positions.append(ball_node.global_position)
			radii.append(ball_r)
	if _player and is_instance_valid(_player) and positions.size() < BLACKOUT_MAX_LIGHTS:
		positions.append(_player.global_position)
		radii.append(paddle_r)
	if _enemy_paddle and is_instance_valid(_enemy_paddle) and positions.size() < BLACKOUT_MAX_LIGHTS:
		positions.append(_enemy_paddle.global_position)
		radii.append(paddle_r)
	for powerup_v in _powerups:
		if positions.size() >= BLACKOUT_MAX_LIGHTS:
			break
		positions.append((powerup_v as Dictionary).get("pos", Vector2.ZERO))
		radii.append(item_r)
	for portal_key in ["entry", "exit"]:
		var portal_node: Variant = _portal.get(portal_key, null)
		if portal_node is Node2D and is_instance_valid(portal_node) and positions.size() < BLACKOUT_MAX_LIGHTS:
			positions.append((portal_node as Node2D).global_position)
			radii.append(item_r)
	if not _meteor.is_empty() and positions.size() < BLACKOUT_MAX_LIGHTS:
		positions.append(_meteor.get("pos", Vector2.ZERO))
		radii.append(float(_meteor.get("radius", 70.0)) + 50.0)
	for drone_v in _drones:
		if positions.size() >= BLACKOUT_MAX_LIGHTS:
			break
		positions.append((drone_v as Dictionary).get("pos", Vector2.ZERO))
		radii.append(item_r * 0.8)
	var count: int = positions.size()
	# Les uniform arrays ont une taille fixe : padding hors écran.
	while positions.size() < BLACKOUT_MAX_LIGHTS:
		positions.append(Vector2(-9999.0, -9999.0))
		radii.append(1.0)
	mat.set_shader_parameter("darkness", darkness)
	mat.set_shader_parameter("viewport_size", viewport_size)
	mat.set_shader_parameter("light_count", count)
	mat.set_shader_parameter("light_pos", positions)
	mat.set_shader_parameter("light_radius", radii)

# =============================================================================
# ÉVÉNEMENT INVASION (drones traversants — rebond radial, tués par missiles)
# =============================================================================

func _update_invasion(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	# Déplacement des drones existants (même pendant SERVE).
	for i in range(_drones.size() - 1, -1, -1):
		var drone: Dictionary = _drones[i]
		var pos: Vector2 = drone.get("pos", Vector2.ZERO)
		pos.x += float(drone.get("dir", 1.0)) * float(drone.get("speed", 260.0)) * delta
		drone["pos"] = pos
		drone["hit_cd"] = maxf(0.0, float(drone.get("hit_cd", 0.0)) - delta)
		var node_v: Variant = drone.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).global_position = pos
		if pos.x < -80.0 or pos.x > viewport_size.x + 80.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_drones.remove_at(i)
	# Télégraphe en cours -> spawn à échéance.
	if _invasion_pending > 0.0:
		_invasion_pending -= delta
		if _invasion_arrow and is_instance_valid(_invasion_arrow):
			_invasion_arrow.modulate.a = 0.4 + 0.6 * absf(sin(_elapsed * 10.0))
		if _invasion_pending <= 0.0:
			if _invasion_arrow and is_instance_valid(_invasion_arrow):
				_invasion_arrow.queue_free()
			_invasion_arrow = null
			_spawn_invasion_drones()
		return
	if _invasion_chance <= 0.0:
		return
	_invasion_timer -= delta
	if _invasion_timer <= 0.0:
		_invasion_timer = _invasion_interval
		if randf() < _invasion_chance and _drones.is_empty():
			_invasion_pending = maxf(0.2, float(_get_conf("invasion_telegraph_sec", 1.0)))
			_invasion_from_left = randf() < 0.5
			_show_invasion_arrow()

func _show_invasion_arrow() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var label := Label.new()
	label.text = ">>" if _invasion_from_left else "<<"
	label.add_theme_font_size_override("font_size", 46)
	label.add_theme_color_override("font_color", Color("#FF6B5C"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_as_relative = false
	label.z_index = 55
	label.position = Vector2(12.0 if _invasion_from_left else viewport_size.x - 76.0,
		viewport_size.y * 0.5 - 23.0)
	add_child(label)
	_invasion_arrow = label

func _spawn_invasion_drones() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var count: int = clampi(int(_get_conf("invasion_drone_count", 3)), 1, 8)
	var speed: float = maxf(60.0, float(_get_conf("invasion_drone_speed_px_sec", 260.0)))
	var radius: float = maxf(8.0, float(_get_conf("invasion_drone_radius_px", 26.0)))
	var band_min: float = clampf(float(_get_conf("invasion_band_top_ratio", 0.30)), 0.05, 0.9)
	var band_max: float = clampf(float(_get_conf("invasion_band_bottom_ratio", 0.70)), band_min, 0.95)
	var dir: float = 1.0 if _invasion_from_left else -1.0
	for i in range(count):
		var node := Node2D.new()
		node.z_as_relative = false
		node.z_index = 9
		var visual: Node2D = _build_sprite_fit(_resolve_enemy_asset_path(), Vector2.ONE * radius * 2.0)
		if visual == null:
			var tri := Polygon2D.new()
			tri.polygon = PackedVector2Array([
				Vector2(-radius, -radius * 0.7), Vector2(radius, 0.0), Vector2(-radius, radius * 0.7)
			])
			tri.color = Color("#FF6B5C")
			visual = tri
		visual.rotation = 0.0 if dir > 0.0 else PI
		node.add_child(visual)
		var y: float = viewport_size.y * lerpf(band_min, band_max,
			(float(i) + randf() * 0.8) / maxf(1.0, float(count)))
		var x: float = (-radius - 20.0 - float(i) * 110.0) if dir > 0.0 \
			else (viewport_size.x + radius + 20.0 + float(i) * 110.0)
		node.global_position = Vector2(x, y)
		add_child(node)
		_drones.append({ "node": node, "pos": node.global_position, "dir": dir,
			"speed": speed, "radius": radius, "hit_cd": 0.0 })

## Rebond radial sur un drone (le drone survit à la balle — seuls les missiles
## des raquettes armées le détruisent, dans _update_missiles).
func _collide_ball_drones(ball: Dictionary, pos: Vector2) -> Vector2:
	if _drones.is_empty():
		return pos
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	for drone_v in _drones:
		var drone: Dictionary = drone_v as Dictionary
		if float(drone.get("hit_cd", 0.0)) > 0.0:
			continue
		var d_pos: Vector2 = drone.get("pos", Vector2.ZERO)
		var reach: float = float(drone.get("radius", 26.0)) + _ball_radius
		var offset: Vector2 = pos - d_pos
		if offset.length_squared() > reach * reach:
			continue
		var normal: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else Vector2.UP
		if vel.dot(normal) < 0.0:
			ball["vel"] = vel.bounce(normal)
		pos = d_pos + normal * (reach + 0.5)
		drone["hit_cd"] = 0.2
		if VFXManager:
			VFXManager.spawn_impact(pos, 12.0, self)
		break
	return pos

# =============================================================================
# ÉVÉNEMENT MÉTÉORE CENTRAL (boss destructible : 1 impact de balle = -1 HP)
# =============================================================================

func _update_meteor(delta: float) -> void:
	if not _meteor_enabled:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if _meteor.is_empty():
		if _meteor_spawned_once:
			# Respawn optionnel (mode libre) après destruction.
			if float(_get_conf("meteor_respawn_interval_sec", 0.0)) > 0.0:
				_meteor_respawn_timer -= delta
				if _meteor_respawn_timer <= 0.0:
					_spawn_meteor()
		else:
			# Premier spawn : ratio de la durée, borné (indispensable en libre
			# continuous où la durée est quasi infinie).
			var wait: float = minf(
				_duration * clampf(float(_get_conf("meteor_time_ratio", 0.35)), 0.0, 1.0),
				maxf(1.0, float(_get_conf("meteor_max_wait_sec", 30.0))))
			if _elapsed >= wait:
				_spawn_meteor()
		return
	_meteor["hit_cd"] = maxf(0.0, float(_meteor.get("hit_cd", 0.0)) - delta)
	# Entrée en translation depuis le haut (jamais de pop).
	var pos: Vector2 = _meteor.get("pos", Vector2.ZERO)
	if bool(_meteor.get("arriving", false)):
		var target_y: float = viewport_size.y * clampf(float(_get_conf("meteor_center_y_ratio", 0.5)), 0.2, 0.8)
		pos.y = move_toward(pos.y, target_y, 220.0 * delta)
		_meteor["pos"] = pos
		if absf(pos.y - target_y) < 0.5:
			_meteor["arriving"] = false
	var node_v: Variant = _meteor.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).global_position = pos

func _spawn_meteor() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var fit: float = maxf(40.0, float(_get_conf("meteor_fit_px", 150.0)))
	var radius: float = fit * 0.5
	var hp: int = maxi(1, int(round(float(_get_conf("meteor_hp", _get_conf("meteor_hp_base", 8))))))
	var node := Node2D.new()
	node.name = "PongMeteor"
	node.z_as_relative = false
	node.z_index = 9
	# Visuel : un boss .tres tiré au sort dans meteor_bosses[] (String ou
	# { "asset_anim": ... }), sinon cercle procédural.
	var bosses_v: Variant = _get_conf("meteor_bosses", [])
	var asset_path: String = ""
	if bosses_v is Array and not (bosses_v as Array).is_empty():
		var pick: Variant = (bosses_v as Array)[randi() % (bosses_v as Array).size()]
		if pick is Dictionary:
			asset_path = str((pick as Dictionary).get("asset_anim", ""))
		else:
			asset_path = str(pick)
	var visual: Node2D = _build_sprite_fit(asset_path, Vector2.ONE * fit)
	if visual == null:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(24):
			var a: float = TAU * float(i) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		circle.polygon = pts
		circle.color = Color("#8A93A6")
		visual = circle
	node.add_child(visual)
	var label := Label.new()
	label.text = str(hp)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(maxf(18.0, radius * 0.55)))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.size = Vector2(fit, fit)
	label.position = -label.size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	node.global_position = Vector2(viewport_size.x * 0.5, -radius - 10.0)
	add_child(node)
	_meteor = { "node": node, "pos": node.global_position, "radius": radius,
		"hp": hp, "max_hp": hp, "label": label, "arriving": true, "hit_cd": 0.0 }
	_meteor_spawned_once = true

## Rebond radial (cercle inscrit) + 1 dégât par impact (cooldown anti multi-hit).
func _collide_ball_meteor(ball: Dictionary, pos: Vector2) -> Vector2:
	if _meteor.is_empty():
		return pos
	var m_pos: Vector2 = _meteor.get("pos", Vector2.ZERO)
	var reach: float = float(_meteor.get("radius", 70.0)) + _ball_radius
	var offset: Vector2 = pos - m_pos
	if offset.length_squared() > reach * reach:
		return pos
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	var normal: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else Vector2.UP
	if vel.dot(normal) < 0.0:
		ball["vel"] = vel.bounce(normal)
	pos = m_pos + normal * (reach + 0.5)
	if float(_meteor.get("hit_cd", 0.0)) <= 0.0:
		_meteor["hit_cd"] = 0.1
		_damage_meteor(pos)
	return pos

func _damage_meteor(at_pos: Vector2) -> void:
	_meteor["hp"] = int(_meteor.get("hp", 1)) - 1
	var hp: int = int(_meteor["hp"])
	var label: Label = _meteor.get("label") as Label
	if label and is_instance_valid(label):
		label.text = str(maxi(0, hp))
	if VFXManager:
		VFXManager.spawn_impact(at_pos, 14.0, self)
	if hp > 0:
		var node: Node2D = _meteor.get("node") as Node2D
		if node and is_instance_valid(node):
			var brightness: float = lerpf(0.55, 1.0,
				float(hp) / float(maxi(1, int(_meteor.get("max_hp", 1)))))
			node.modulate = Color(brightness, brightness, brightness, 1.0)
		return
	_destroy_meteor()

## Destruction : multi-explosions échelonnées + cristaux sur place + score.
func _destroy_meteor() -> void:
	var pos: Vector2 = _meteor.get("pos", Vector2.ZERO)
	var radius: float = float(_meteor.get("radius", 70.0))
	var node: Node2D = _meteor.get("node") as Node2D
	if node and is_instance_valid(node):
		node.queue_free()
	_meteor = {}
	_meteor_respawn_timer = maxf(0.0, float(_get_conf("meteor_respawn_interval_sec", 0.0)))
	if _game and is_instance_valid(_game):
		if _game.has_method("spawn_reward_crystal_at"):
			for i in range(maxi(0, int(_get_conf("meteor_crystals", 6)))):
				var offset := Vector2(randf_range(-radius, radius), randf_range(-radius, radius) * 0.6)
				_game.call("spawn_reward_crystal_at", pos + offset)
		if _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", maxi(0, int(_get_conf("meteor_score", 150))), pos)
	if VFXManager:
		var tween := create_tween()
		for i in range(5):
			var at: Vector2 = pos + Vector2(randf_range(-radius, radius), randf_range(-radius, radius)) * 0.7
			tween.tween_interval(0.08)
			tween.tween_callback(VFXManager.spawn_impact.bind(at, 26.0, self))

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
