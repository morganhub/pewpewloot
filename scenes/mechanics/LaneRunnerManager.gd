extends Node2D

## LaneRunnerManager — Orchestre une vague "lane_runner" (inspiration Subway
## Surfers / Temple Run) : le vaisseau est verrouille sur des voies fixes (snap
## X gere par Player.gd) et des murs indestructibles pleine-voie descendent a
## haute vitesse en rangees telegraphiees laissant toujours au moins une voie
## atteignable. Collision = degats % HP + breve invulnerabilite ; froler un mur
## juste apres un changement de voie (near-miss) = chance de cristal. Des
## trainees de collectibles (pieces facon Subway Surfers) apparaissent dans la
## voie sure : chaque piece rapporte du score (base x reward_multiplier de la
## vague/du monde) et une chance de cristal. Tir coupe, contacts manuels par
## distance (pas de physics engine). La vitesse et la cadence des rangees
## montent progressivement pendant la vague.
##
## Elements speciaux (12 juillet 2026, un seul par rangee — exclusifs) :
## - PORTAIL : paire entree orange / sortie bleue sur deux voies distinctes,
##   la sortie plus haut a l'ecran — entrer = teleportation instantanee de voie
##   (Player.set_lane_runner_lane) + breve invulnerabilite.
## - BELIER (pickup) : les ram_charges prochains murs touches EXPLOSENT au lieu
##   d'infliger des degats (bulldozer, shake).
## - PEW PEW (pickup) : canon temporaire — missiles maison droit devant sur sa
##   voie, un missile detruit un mur (le joueur creuse son chemin).
## - TOURELLES (mode LIBRE hauts levels uniquement, jamais story) : salves de
##   projectiles ennemis lents en diagonale a travers les voies
##   (ProjectileManager.spawn_enemy_projectile, gate _free_level_progress).
##
## Extension 12 juillet 2026 (wave_types_improvements) :
## - 5 pickups temporels dans la chaine exclusive : FANTOME (traverse les murs,
##   aura translucide), AIMANT (pieces de toutes les voies), x2 PIECES, TURBO
##   volontaire (scroll x1.5 ET score x2 — risque/recompense), GEL (scroll x0.7).
## - PIECE GEANTE (x10) posee sur une voie BLOQUEE juste au-dessus de son mur :
##   detour risque, ou mur detruit (belier/pew) / traverse (fantome).
## - Variantes : CHICANES (2e rangee differee via _pending_rows), TRAIN (murs
##   empiles sur une voie, la voie sure ne peut pas y entrer tant qu'il descend),
##   DEMI-MURS (visuel deborde sur une voie adjacente, collision inchangee,
##   near-miss genereux dans la voie debordee), TOURELLES AU SOL (descendent
##   avec le scroll et tirent le long de leur colonne, Libre hauts levels).
## - Evenements Libre (chances 0 en story, jamais simultanes) : TUNNEL (penombre
##   shader pong_blackout, halos joueur+objets) et HEURE DE POINTE (rangees x2 +
##   trainee garantie). STREAK PARFAITE toujours active : 30 s sans collision de
##   mur -> pluie de cristaux, compteur discret en haut-gauche.
## La voie sure est aussi anti-monotone : jamais plus de safe_lane_max_static_sec
## sans etre FORCEE de changer de colonne.

signal finished

enum State { INTRO, RUN, DONE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _obstacle_skins: Array = [] # world skin_overrides.obstacles.explosives

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 35.0
var _elapsed: float = 0.0
var _time: float = 0.0

# Lane geometry (mirrors the Player lane lock so both stay in sync).
var _lane_count: int = 3
var _lane_side_margin_px: float = 70.0

# Row scheduling / difficulty ramp.
var _row_timer: float = 0.0
var _last_free_lane: int = 1
var _pattern_rows: Array = [] # optional scripted rows: [[blocked lanes], ...]
var _pattern_row_index: int = 0
var _spawn_cutoff_sec: float = 2.5

# Rewards.
var _reward_multiplier: float = 1.0
var _collectible_score: int = 15

# Alive walls. Entries: { "node": Node2D, "lane": int, "half_height": float,
# "hit": bool, "passed": bool }
var _walls: Array = []
# Alive collectibles. Entries: { "node": Node2D, "lane": int, "pulse": float,
# "kind": String } — kind "coin" (defaut), "ram" ou "pew" (pickups speciaux).
var _collectibles: Array = []

# Anti-monotonie : temps cumule sans changement de voie sure (forcage a seuil).
var _safe_lane_static_sec: float = 0.0
# Portails : { "entry_node", "exit_node", "entry_lane": int, "exit_lane": int,
# "pulse": float } — les deux nodes descendent au speed commun.
var _portals: Array = []
# Bonus belier : murs restants a detruire au contact.
var _ram_charges: int = 0
# Bonus pew pew : canon temporaire + missiles maison { "node", "lane": int }.
var _pew_time_left: float = 0.0
var _pew_fire_timer: float = 0.0
var _pew_missiles: Array = []
# Tourelles (libre hauts levels) : tirs differes { "time", "pos", "dir" }.
var _turret_timer: float = 0.0
var _turret_shots: Array = []
var _turret_any_fired: bool = false
# Pickups temporels : fantome / aimant / x2 pieces / turbo / gel.
var _ghost_time_left: float = 0.0
var _magnet_time_left: float = 0.0
var _coin_x2_time_left: float = 0.0
var _turbo_time_left: float = 0.0
var _freeze_time_left: float = 0.0
# Chicanes : rangees differees { "time": float } (file pausable, modele _turret_shots).
var _pending_rows: Array = []
# Train : voie interdite au chemin sur tant que ses murs empiles descendent.
var _train_lane: int = -1
var _train_walls_left: int = 0
# Tourelles au sol : { "node", "lane", "fire_timer" } — descendent avec le scroll.
var _ground_turrets: Array = []
# Evenements Libre (jamais simultanes) : tunnel (penombre) / heure de pointe.
var _tunnel_timer: float = 0.0
var _tunnel_time_left: float = 0.0
var _tunnel_duration: float = 6.0
var _tunnel_rect: ColorRect = null
var _rush_timer: float = 0.0
var _rush_time_left: float = 0.0
# Streak parfaite : secondes sans collision de mur (toujours actif).
var _streak_sec: float = 0.0
var _streak_label: Label = null
# Bandeau d'evenement clignotant (pattern BreakoutManager).
var _event_banner: Label = null
var _banner_time: float = 0.0

var _hit_invuln_timer: float = 0.0
var _countdown_label: Label = null
var _finished_emitted: bool = false

const PLAYER_HALF_HEIGHT_PX: float = 26.0
const TUNNEL_SHADER_PATH: String = "res://scenes/mechanics/pong_blackout.gdshader"
# Teintes fallback des pickups (cle data <kind>_pickup_color prioritaire).
const PICKUP_FALLBACK_COLORS: Dictionary = {
	"ram": "#FF8A5C", "pew": "#8FD3FF", "ghost": "#B8C4E8",
	"magnet": "#FF5C8A", "coin_x2": "#FFD866", "turbo": "#FFA53C", "freeze": "#8FE8FF"
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("lane_runner") if DataManager else {}
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []

	_duration = maxf(8.0, float(_config.get("duration", _cfg.get("duration_sec_default", 35.0))))
	_lane_count = maxi(2, int(_get_conf("lane_count", 3)))
	_lane_side_margin_px = maxf(10.0, float(_get_conf("lane_side_margin_px", 70.0)))
	_spawn_cutoff_sec = maxf(0.5, float(_get_conf("spawn_stop_before_end_sec", 2.5)))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_collectible_score = maxi(0, int(_get_conf("collectible_score", 15)))

	var rows_v: Variant = _config.get("pattern_rows", [])
	if rows_v is Array:
		for row_v in (rows_v as Array):
			if row_v is Array:
				_pattern_rows.append((row_v as Array).duplicate())

	_last_free_lane = int(_lane_count / 2.0)
	_begin_player_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	_row_timer = 0.35 # first row arrives quickly after the intro
	_tunnel_timer = maxf(5.0, float(_get_conf("tunnel_interval_sec", 25.0)))
	_rush_timer = maxf(5.0, float(_get_conf("rush_hour_interval_sec", 30.0)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la course EN COURS est re-scalée
## au changement de level — lane du joueur, murs et collectibles préservés.
## Toutes les clés sont lues live via _get_conf : il suffit de les merger.
func update_free_mode_config(cfg: Dictionary) -> void:
	for key in ["wall_speed_px_sec_start", "wall_speed_px_sec_end",
		"row_interval_sec_start", "row_interval_sec_end",
		"double_wall_chance", "turret_chance", "_free_level_progress",
		"ghost_pickup_chance", "magnet_pickup_chance", "coin_x2_pickup_chance",
		"turbo_pickup_chance", "freeze_pickup_chance", "giant_coin_chance",
		"chicane_chance", "train_chance", "half_wall_chance",
		"ground_turret_chance", "tunnel_chance", "rush_hour_chance"]:
		if cfg.has(key):
			_config[key] = cfg[key]

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_lane_runner"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_lane_runner", merged)

func _restore_player_mode() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _hit_invuln_timer > 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)
	_hit_invuln_timer = 0.0
	# Aura fantôme : toujours restaurée, même si le manager meurt pendant l'effet.
	if _ghost_time_left > 0.0:
		_player.modulate.a = 1.0
		_ghost_time_left = 0.0
	if _player.has_method("end_lane_runner"):
		_player.call("end_lane_runner")

# =============================================================================
# LANE GEOMETRY
# =============================================================================

func _lane_width() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	return maxf(1.0, viewport_size.x - _lane_side_margin_px * 2.0) / float(_lane_count)

func _lane_center_x(lane: int) -> float:
	return _lane_side_margin_px + _lane_width() * (float(clampi(lane, 0, _lane_count - 1)) + 0.5)

## Difficulty ramp position (0 at wave start -> 1 at wave end). En mode libre
## "continuous", _duration est quasi infinie (la rampe temporelle resterait
## figée à 0) : _free_level_progress (progression 0->1 du level) la remplace,
## les clés *_end restent donc effectives.
func _ramp_t() -> float:
	var progress_v: Variant = _config.get("_free_level_progress", null)
	if progress_v is float or progress_v is int:
		return clampf(float(progress_v), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _current_speed() -> float:
	var v_start: float = maxf(50.0, float(_get_conf("wall_speed_px_sec_start", 380.0)))
	var v_end: float = maxf(v_start, float(_get_conf("wall_speed_px_sec_end", 600.0)))
	return lerpf(v_start, v_end, _ramp_t())

func _current_row_interval() -> float:
	var i_start: float = maxf(0.3, float(_get_conf("row_interval_sec_start", 1.7)))
	var i_end: float = clampf(float(_get_conf("row_interval_sec_end", 1.05)), 0.3, i_start)
	var interval: float = lerpf(i_start, i_end, _ramp_t())
	# Heure de pointe : densite doublee, plancher 0.3 s pour rester jouable.
	if _rush_time_left > 0.0:
		interval = maxf(0.3, interval / maxf(1.0, float(_get_conf("rush_hour_density_mult", 2.0))))
	return interval

## Multiplicateur de scroll des pickups turbo (plus vite, score x2) et gel
## (ralenti). Cumulables : produit des deux.
func _scroll_mult() -> float:
	var mult: float = 1.0
	if _turbo_time_left > 0.0:
		mult *= maxf(1.0, float(_get_conf("turbo_speed_mult", 1.5)))
	if _freeze_time_left > 0.0:
		mult *= clampf(float(_get_conf("freeze_scroll_mult", 0.7)), 0.2, 1.0)
	return mult

# =============================================================================
# ROWS (walls + collectible trail)
# =============================================================================

## Picks the blocked lanes of the next row. Scripted rows (pattern_rows) are
## consumed in a loop when provided; otherwise the row is procedural with a
## solvability guarantee: the guaranteed free lane never moves by more than one
## lane between two consecutive rows.
func _next_row_blocked_lanes() -> Array:
	if not _pattern_rows.is_empty():
		var scripted_v: Variant = _pattern_rows[_pattern_row_index % _pattern_rows.size()]
		_pattern_row_index += 1
		var scripted: Array = []
		if scripted_v is Array:
			for lane_v in (scripted_v as Array):
				var lane: int = clampi(int(lane_v), 0, _lane_count - 1)
				if not scripted.has(lane):
					scripted.append(lane)
		# Defensive: a fully blocked scripted row would be unwinnable.
		if scripted.size() >= _lane_count:
			scripted.remove_at(randi() % scripted.size())
		if not scripted.is_empty():
			_update_last_free_lane_from_blocked(scripted)
			return scripted
	# Procedural: move the safe lane by at most one step, then block others.
	# Anti-monotonie : au-dela de safe_lane_max_static_sec sans bouger, le pas
	# est FORCE a +-1 (direction valide aux bords) — le joueur DOIT changer de
	# colonne au moins toutes les ~5 s.
	var step: int = (randi() % 3) - 1
	var max_static: float = maxf(0.0, float(_get_conf("safe_lane_max_static_sec", 5.0)))
	if max_static > 0.0 and _safe_lane_static_sec + _current_row_interval() >= max_static:
		if _last_free_lane <= 0:
			step = 1
		elif _last_free_lane >= _lane_count - 1:
			step = -1
		else:
			step = 1 if randf() < 0.5 else -1
	var free_lane: int = clampi(_last_free_lane + step, 0, _lane_count - 1)
	# Train en cours : la voie sure ne peut JAMAIS entrer dans sa colonne (des
	# murs empiles y descendent d'affilee) — le pas est inverse ou annule.
	if _train_lane >= 0 and free_lane == _train_lane:
		var reverse: int = clampi(_last_free_lane - step, 0, _lane_count - 1)
		free_lane = _last_free_lane if reverse == _train_lane else reverse
	if free_lane == _last_free_lane:
		_safe_lane_static_sec += _current_row_interval()
	else:
		_safe_lane_static_sec = 0.0
	_last_free_lane = free_lane
	var candidates: Array = []
	for i in range(_lane_count):
		if i != free_lane:
			candidates.append(i)
	candidates.shuffle()
	var blocked_count: int = 1
	var double_chance: float = clampf(float(_get_conf("double_wall_chance", 0.3)), 0.0, 1.0)
	if _lane_count > 2 and randf() <= double_chance:
		blocked_count = mini(2, candidates.size())
	var blocked: Array = []
	for i in range(blocked_count):
		blocked.append(candidates[i])
	return blocked

func _update_last_free_lane_from_blocked(blocked: Array) -> void:
	var free_lanes: Array = []
	for i in range(_lane_count):
		if not blocked.has(i):
			free_lanes.append(i)
	if free_lanes.is_empty():
		return
	# Keep the free lane closest to the previous one as the reference path.
	var best: int = int(free_lanes[0])
	for lane_v in free_lanes:
		if absi(int(lane_v) - _last_free_lane) < absi(best - _last_free_lane):
			best = int(lane_v)
	if best != _last_free_lane:
		_safe_lane_static_sec = 0.0
	else:
		_safe_lane_static_sec += _current_row_interval()
	_last_free_lane = best

func _spawn_row(allow_chicane: bool = true) -> void:
	var blocked: Array = _next_row_blocked_lanes()
	var wall_height: float = maxf(24.0, float(_get_conf("wall_height_px", 88.0)))
	var wall_width: float = _lane_width() * clampf(float(_get_conf("wall_width_ratio", 0.92)), 0.3, 1.0)
	var spawn_y: float = minf(-20.0, float(_get_conf("wall_spawn_y", -130.0)))
	# Train : une voie bloquee de la rangee recoit train_length murs empiles ;
	# tant qu'ils descendent, la voie sure ne peut pas entrer dans leur colonne
	# (garde dans _next_row_blocked_lanes, liberation par compteur).
	var train_lane_row: int = -1
	if _train_lane < 0 and not blocked.is_empty() \
		and randf() <= clampf(float(_get_conf("train_chance", 0.0)), 0.0, 1.0):
		train_lane_row = int(blocked[randi() % blocked.size()])
	for lane_v in blocked:
		var lane: int = int(lane_v)
		var is_train: bool = lane == train_lane_row
		var stack: int = maxi(1, int(_get_conf("train_length", 3))) if is_train else 1
		var spacing: float = wall_height + maxf(0.0, float(_get_conf("train_spacing_px", 26.0)))
		for k in range(stack):
			_spawn_wall(lane, Vector2(_lane_center_x(lane),
				spawn_y - wall_height * 0.5 - spacing * float(k)), wall_width, wall_height, is_train)
		if is_train:
			_train_lane = lane
			_train_walls_left = stack
	# Chicane : une 2e rangee arrive presque collee (file drainee dans _process).
	# Jamais pendant un train ni en cascade (une rangee differee ne relance pas).
	if allow_chicane and train_lane_row < 0 and _train_lane < 0 and _pending_rows.is_empty() \
		and randf() <= clampf(float(_get_conf("chicane_chance", 0.0)), 0.0, 1.0):
		_pending_rows.append({ "time": _time + maxf(0.1, float(_get_conf("chicane_gap_sec", 0.3))) })
	# Un seul element special par rangee (chaine exclusive, l'ordre = priorite :
	# portail > belier > pew > fantome > aimant > x2 > turbo > gel > piece geante
	# > tourelle au sol), sinon la trainee de pieces habituelle.
	var special_base_y: float = spawn_y - wall_height
	if randf() <= clampf(float(_get_conf("portal_chance", 0.0)), 0.0, 1.0):
		_spawn_portal(special_base_y)
	elif randf() <= clampf(float(_get_conf("ram_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("ram", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("pew_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("pew", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("ghost_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("ghost", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("magnet_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("magnet", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("coin_x2_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("coin_x2", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("turbo_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("turbo", _last_free_lane, special_base_y)
	elif randf() <= clampf(float(_get_conf("freeze_pickup_chance", 0.0)), 0.0, 1.0):
		_spawn_special_pickup("freeze", _last_free_lane, special_base_y)
	elif not blocked.is_empty() and randf() <= clampf(float(_get_conf("giant_coin_chance", 0.0)), 0.0, 1.0):
		_spawn_giant_coin(blocked, spawn_y, wall_height)
	elif randf() <= clampf(float(_get_conf("ground_turret_chance", 0.0)), 0.0, 1.0) \
		and _ramp_t() >= clampf(float(_get_conf("turret_min_level_progress", 0.45)), 0.0, 1.0):
		_spawn_ground_turret(special_base_y)
	else:
		var trail_chance: float = clampf(float(_get_conf("collectible_trail_chance", 0.75)), 0.0, 1.0)
		if _rush_time_left > 0.0:
			trail_chance = 1.0 # heure de pointe : chaque rangee paie
		if randf() <= trail_chance:
			_spawn_collectible_trail(_last_free_lane, special_base_y)

## Mur individuel. Demi-mur (roll half_wall_chance, hors train) : visuel elargi
## debordant vers une voie adjacente, COLLISION INCHANGEE (sa voie seule) ;
## passer dans la voie debordee = near-miss genereux sans switch requis.
func _spawn_wall(lane: int, pos: Vector2, wall_width: float, wall_height: float, is_train: bool) -> void:
	var node := Node2D.new()
	node.name = "LaneWall"
	node.z_as_relative = false
	node.z_index = 10
	node.position = pos
	var entry: Dictionary = {
		"node": node,
		"lane": lane,
		"half_height": wall_height * 0.5,
		"hit": false,
		"passed": false
	}
	if is_train:
		entry["train"] = true
	var visual_width: float = wall_width
	var visual_offset: float = 0.0
	if not is_train and randf() <= clampf(float(_get_conf("half_wall_chance", 0.0)), 0.0, 1.0):
		var dir: int = 1 if lane <= 0 else (-1 if lane >= _lane_count - 1 else (1 if randf() < 0.5 else -1))
		var mult: float = maxf(1.0, float(_get_conf("half_wall_width_mult", 1.4)))
		visual_width = wall_width * mult
		visual_offset = float(dir) * wall_width * (mult - 1.0) * 0.5
		entry["half"] = true
		entry["half_over_lane"] = clampi(lane + dir, 0, _lane_count - 1)
	var visual: Node2D = _build_wall_visual(visual_width, wall_height)
	visual.position.x = visual_offset
	node.add_child(visual)
	add_child(node)
	_walls.append(entry)

## Libere le compteur du train quand un de ses murs quitte le jeu (passe la
## ligne du vaisseau, detruit par belier/pew, ou node invalide).
func _release_train_wall(entry: Dictionary) -> void:
	if not bool(entry.get("train", false)) or bool(entry.get("train_released", false)):
		return
	entry["train_released"] = true
	_train_walls_left -= 1
	if _train_walls_left <= 0:
		_train_lane = -1

## A vertical trail of collectibles in the safe lane, laid out above the row it
## escorts so the player scoops it right after the dodge.
func _spawn_collectible_trail(lane: int, base_y: float) -> void:
	var count_min: int = maxi(1, int(_get_conf("collectible_count_min", 3)))
	var count_max: int = maxi(count_min, int(_get_conf("collectible_count_max", 5)))
	var count: int = count_min + (randi() % (count_max - count_min + 1))
	var spacing: float = maxf(20.0, float(_get_conf("collectible_spacing_px", 72.0)))
	var size_px: float = maxf(12.0, float(_get_conf("collectible_size_px", 42.0)))
	for i in range(count):
		var node := Node2D.new()
		node.name = "LaneCollectible"
		node.z_as_relative = false
		node.z_index = 12
		node.position = Vector2(_lane_center_x(lane), base_y - spacing * float(i + 1))
		node.add_child(_build_collectible_visual(size_px))
		add_child(node)
		_collectibles.append({
			"node": node,
			"lane": lane,
			"pulse": randf() * TAU,
			"kind": "coin"
		})

# =============================================================================
# ÉLÉMENTS SPÉCIAUX (portails, pickups bélier / pew pew)
# =============================================================================

## Paire de portails : entrée orange sur une voie, sortie bleue sur une AUTRE
## voie, plus haut à l'écran (« gauche -> droite un peu plus haut » généralisé).
## Les deux descendent au speed commun ; entrer téléporte instantanément.
func _spawn_portal(base_y: float) -> void:
	var entry_lane: int = randi() % _lane_count
	var exit_lane: int = (entry_lane + 1 + (randi() % (_lane_count - 1))) % _lane_count
	var size_px: float = maxf(24.0, float(_get_conf("portal_size_px", 56.0)))
	var y_offset: float = maxf(0.0, float(_get_conf("portal_exit_y_offset_px", 140.0)))
	var entry_node: Node2D = _build_portal_visual(size_px,
		Color(str(_get_conf("portal_entry_color", "#FF8A2A"))), str(_get_conf("portal_entry_asset", "")))
	entry_node.position = Vector2(_lane_center_x(entry_lane), base_y)
	add_child(entry_node)
	var exit_node: Node2D = _build_portal_visual(size_px,
		Color(str(_get_conf("portal_exit_color", "#4AA8FF"))), str(_get_conf("portal_exit_asset", "")))
	exit_node.position = Vector2(_lane_center_x(exit_lane), base_y - y_offset)
	add_child(exit_node)
	_portals.append({
		"entry_node": entry_node,
		"exit_node": exit_node,
		"entry_lane": entry_lane,
		"exit_lane": exit_lane,
		"pulse": randf() * TAU
	})

## Anneau procédural (Line2D fermée) + coeur translucide ; clé d'asset prête.
func _build_portal_visual(size_px: float, color: Color, asset_path: String) -> Node2D:
	var root := Node2D.new()
	root.name = "LanePortal"
	root.z_as_relative = false
	root.z_index = 11
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			sprite.modulate = color
			root.add_child(sprite)
			return root
	var core := Polygon2D.new()
	var core_pts := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		core_pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
	core.polygon = core_pts
	core.color = Color(color.r, color.g, color.b, 0.22)
	root.add_child(core)
	var ring := Line2D.new()
	ring.width = 6.0
	ring.default_color = color
	ring.closed = true
	ring.points = core_pts
	root.add_child(ring)
	return root

## Pickup spécial dans la voie sûre (remplace la traînée de sa rangée) : cercle
## coloré pulsant, collecté par le test de contact des collectibles (kind).
## Générique : clés data `<kind>_pickup_asset` / `<kind>_pickup_color`.
func _spawn_special_pickup(kind: String, lane: int, y: float) -> void:
	var size_px: float = maxf(12.0, float(_get_conf("collectible_size_px", 42.0))) * 1.25
	var color_key: String = "%s_pickup_color" % kind
	var asset_key: String = "%s_pickup_asset" % kind
	var tint := Color(str(_get_conf(color_key, str(PICKUP_FALLBACK_COLORS.get(kind, "#FFFFFF")))))
	var node := Node2D.new()
	node.name = "LaneSpecialPickup"
	node.z_as_relative = false
	node.z_index = 12
	node.position = Vector2(_lane_center_x(lane), y - size_px)
	var asset_path: String = str(_get_conf(asset_key, ""))
	var built: bool = false
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			sprite.modulate = tint
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			node.add_child(sprite)
			built = true
	if not built:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		circle.polygon = pts
		circle.color = tint
		node.add_child(circle)
	add_child(node)
	_collectibles.append({
		"node": node,
		"lane": lane,
		"pulse": randf() * TAU,
		"kind": kind
	})

## Applique l'effet d'un pickup spécial collecté.
func _apply_special_pickup(kind: String, at_pos: Vector2) -> void:
	match kind:
		"ram":
			_ram_charges = maxi(1, int(_get_conf("ram_charges", 3)))
		"pew":
			_pew_time_left = maxf(0.5, float(_get_conf("pew_duration_sec", 6.0)))
			_pew_fire_timer = 0.0 # premier tir immédiat
		"ghost":
			_ghost_time_left = maxf(0.5, float(_get_conf("ghost_duration_sec", 4.0)))
			if _player and is_instance_valid(_player):
				_player.modulate.a = clampf(float(_get_conf("ghost_alpha", 0.55)), 0.1, 1.0)
		"magnet":
			_magnet_time_left = maxf(0.5, float(_get_conf("magnet_duration_sec", 6.0)))
		"coin_x2":
			_coin_x2_time_left = maxf(0.5, float(_get_conf("coin_x2_duration_sec", 8.0)))
		"turbo":
			_turbo_time_left = maxf(0.5, float(_get_conf("turbo_duration_sec", 5.0)))
		"freeze":
			_freeze_time_left = maxf(0.5, float(_get_conf("freeze_duration_sec", 4.0)))
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -40.0),
			_translate_or("lane_runner_%s" % kind, kind.to_upper()),
			Color(str(PICKUP_FALLBACK_COLORS.get(kind, "#FFFFFF"))), self)
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.flash_sprite(_player, Color(1.0, 1.0, 1.0), 0.15)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Décrémente les timers des pickups temporels ; expiration du fantôme =
## restauration de l'aura (modulate.a du vaisseau).
func _tick_pickup_timers(dt: float) -> void:
	if _ghost_time_left > 0.0:
		_ghost_time_left -= dt
		if _ghost_time_left <= 0.0 and _player and is_instance_valid(_player):
			_player.modulate.a = 1.0
	_magnet_time_left = maxf(0.0, _magnet_time_left - dt)
	_coin_x2_time_left = maxf(0.0, _coin_x2_time_left - dt)
	_turbo_time_left = maxf(0.0, _turbo_time_left - dt)
	_freeze_time_left = maxf(0.0, _freeze_time_left - dt)

## Pièce géante « derrière » un mur : posée sur une voie BLOQUÉE de la rangée,
## juste au-dessus de son mur — détour risqué, ou mur détruit (bélier/pew) /
## traversé (fantôme). Jamais dans la voie sûre.
func _spawn_giant_coin(blocked: Array, spawn_y: float, wall_height: float) -> void:
	var lane: int = int(blocked[randi() % blocked.size()])
	var size_px: float = maxf(24.0, float(_get_conf("giant_coin_size_px", 72.0)))
	var gap: float = maxf(0.0, float(_get_conf("giant_coin_gap_px", 120.0)))
	var node := Node2D.new()
	node.name = "LaneGiantCoin"
	node.z_as_relative = false
	node.z_index = 12
	node.position = Vector2(_lane_center_x(lane), spawn_y - wall_height - gap)
	var asset_path: String = str(_get_conf("giant_coin_asset", ""))
	var built: bool = false
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			node.add_child(sprite)
			built = true
	if not built:
		node.add_child(_build_collectible_visual(size_px))
	add_child(node)
	_collectibles.append({ "node": node, "lane": lane, "pulse": randf() * TAU, "kind": "giant" })

# =============================================================================
# VISUALS
# =============================================================================

## Wall visual: per-wave "wall_assets" override > world obstacle skins >
## type assets. The texture tiles horizontally (cover-crop per tile, never
## stretched) to fill the full lane width; fallback = flat tinted rectangle.
func _build_wall_visual(width: float, height: float) -> Node2D:
	var root := Node2D.new()
	var asset_path: String = ""
	var wave_assets_v: Variant = _config.get("wall_assets", null)
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		var arr: Array = wave_assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	elif not _obstacle_skins.is_empty():
		asset_path = str(_obstacle_skins[randi() % _obstacle_skins.size()])
	else:
		var cfg_assets_v: Variant = _cfg.get("wall_assets", [])
		if cfg_assets_v is Array and not (cfg_assets_v as Array).is_empty():
			var cfg_arr: Array = cfg_assets_v as Array
			asset_path = str(cfg_arr[randi() % cfg_arr.size()])

	var texture: Texture2D = null
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			texture = res as Texture2D

	if texture == null:
		var rect := Polygon2D.new()
		rect.polygon = PackedVector2Array([
			Vector2(-width * 0.5, -height * 0.5),
			Vector2(width * 0.5, -height * 0.5),
			Vector2(width * 0.5, height * 0.5),
			Vector2(-width * 0.5, height * 0.5)
		])
		rect.color = Color(str(_get_conf("wall_fallback_color", "#8A93A6")))
		root.add_child(rect)
		return root

	var tile_count: int = maxi(1, int(ceil(width / height)))
	var tile_w: float = width / float(tile_count)
	var tex_size: Vector2 = texture.get_size()
	var tint := Color(str(_get_conf("wall_tint", "#FFFFFF")))
	for i in range(tile_count):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.modulate = tint
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			# Cover-crop: uniform scale to fill the tile, source region centered.
			var scale_f: float = maxf(tile_w / tex_size.x, height / tex_size.y)
			var src_size := Vector2(tile_w / scale_f, height / scale_f)
			sprite.region_enabled = true
			sprite.region_rect = Rect2((tex_size - src_size) * 0.5, src_size)
			sprite.scale = Vector2.ONE * scale_f
		sprite.position = Vector2(-width * 0.5 + tile_w * (float(i) + 0.5), 0.0)
		root.add_child(sprite)
	return root

## Collectible visual: per-wave "collectible_assets" override > type assets,
## random per piece, tinted; fallback = small golden diamond.
func _build_collectible_visual(size_px: float) -> Node2D:
	var asset_path: String = ""
	var assets_v: Variant = _config.get("collectible_assets", _cfg.get("collectible_assets", []))
	if assets_v is Array and not (assets_v as Array).is_empty():
		var arr: Array = assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	var tint := Color(str(_get_conf("collectible_tint", "#FFD56B")))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			sprite.modulate = tint
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			return sprite
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -size_px * 0.5),
		Vector2(size_px * 0.4, 0.0),
		Vector2(0.0, size_px * 0.5),
		Vector2(-size_px * 0.4, 0.0)
	])
	diamond.color = tint
	return diamond

# =============================================================================
# RUN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	var dt: float = minf(delta, 0.1)
	_time += dt
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	_tick_hit_invuln(dt)

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.RUN
		State.RUN:
			_row_timer -= dt
			if _row_timer <= 0.0 and _elapsed < _duration - _spawn_cutoff_sec:
				_row_timer = _current_row_interval()
				_spawn_row()
			# Chicanes : rangees differees (le 2e spawn passe par le pipeline
			# normal -> chemin +-1 garanti).
			while not _pending_rows.is_empty() \
				and float((_pending_rows[0] as Dictionary).get("time", 0.0)) <= _time \
				and _elapsed < _duration - _spawn_cutoff_sec:
				_pending_rows.pop_front()
				_spawn_row(false)

	var speed: float = _current_speed() * _scroll_mult()
	_update_walls(dt, speed)
	_update_collectibles(dt, speed)
	_update_portals(dt, speed)
	_update_ground_turrets(dt, speed)
	_update_pew(dt)
	_update_pew_missiles(dt)
	_update_turrets(dt)
	_tick_pickup_timers(dt)
	_update_events(dt)
	_update_streak(dt)
	_update_banner(dt)

	if _elapsed >= _duration:
		_finish()

func _tick_hit_invuln(dt: float) -> void:
	if _hit_invuln_timer <= 0.0:
		return
	_hit_invuln_timer -= dt
	if _hit_invuln_timer <= 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)

func _player_lane() -> int:
	if _player.has_method("get_lane_runner_lane"):
		return int(_player.call("get_lane_runner_lane"))
	return -1

func _update_walls(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_lane: int = _player_lane()
	var player_y: float = _player.global_position.y
	for i in range(_walls.size() - 1, -1, -1):
		var entry: Dictionary = _walls[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_release_train_wall(entry)
			_walls.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		var half_height: float = float(entry.get("half_height", 44.0))

		# Contact: same lane + vertical overlap with the ship band.
		if not bool(entry.get("hit", false)) \
			and int(entry.get("lane", -1)) == player_lane \
			and absf(node.position.y - player_y) <= half_height + PLAYER_HALF_HEIGHT_PX:
			# Fantôme : le mur est traversé — ni dégât, ni charge de bélier
			# consommée, ni near-miss (flag ghosted), et la streak continue.
			if _ghost_time_left > 0.0:
				if not bool(entry.get("ghosted", false)):
					entry["ghosted"] = true
					_walls[i] = entry
			# Bélier : le mur explose au lieu de blesser (même pendant l'invuln).
			elif _ram_charges > 0:
				_ram_charges -= 1
				_destroy_wall_at(i, str(_get_conf("ram_explosion_anim", "res://assets/vfx/boss_explosion.tres")),
					int(_get_conf("ram_wall_score", 25)), _lane_width() * 0.9)
				if VFXManager:
					VFXManager.screen_shake(float(_get_conf("ram_shake_intensity", 8.0)),
						maxf(0.05, float(_get_conf("ram_shake_sec", 0.3))))
				continue
			elif _hit_invuln_timer <= 0.0:
				entry["hit"] = true
				_walls[i] = entry
				_on_wall_hit()
				continue

		# Fully passed the ship line: near-miss check, once per wall.
		if not bool(entry.get("passed", false)) and node.position.y - half_height > player_y + PLAYER_HALF_HEIGHT_PX:
			entry["passed"] = true
			_walls[i] = entry
			_release_train_wall(entry)
			if not bool(entry.get("hit", false)) and not bool(entry.get("ghosted", false)):
				if bool(entry.get("half", false)) and player_lane == int(entry.get("half_over_lane", -99)):
					# Voie débordée par un demi-mur : near-miss généreux, sans
					# exiger un changement de voie récent.
					if randf() <= clampf(float(_get_conf("half_wall_near_miss_chance", 0.6)), 0.0, 1.0) \
						and _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
						_game.call("spawn_reward_crystal_at", Vector2(node.position.x, player_y))
				else:
					_check_near_miss(int(entry.get("lane", -1)), player_lane, node.position)

		if node.position.y - half_height > viewport_size.y + 60.0:
			node.queue_free()
			_walls.remove_at(i)

## Collision: % of max HP through the standard damage pipeline (shield first),
## then a short invulnerability so a wall never chews the ship twice.
func _on_wall_hit() -> void:
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("hit_damage_percent", 0.15)), 0.0, 1.0)
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
	if _player == null or not is_instance_valid(_player):
		return # the hit was lethal, the player is already gone
	_hit_invuln_timer = maxf(0.2, float(_get_conf("hit_invuln_sec", 1.0)))
	_streak_sec = 0.0 # la série parfaite se brise sur une collision de mur
	if _player.has_method("set_invincible"):
		_player.call("set_invincible", true)
	if VFXManager:
		VFXManager.screen_shake(6, 0.2)

## Near-miss: the wall passed in the lane right next to the ship AND the player
## dodged into its lane recently -> crystal chance (skill reward).
func _check_near_miss(wall_lane: int, player_lane: int, at_pos: Vector2) -> void:
	if wall_lane < 0 or player_lane < 0 or absi(wall_lane - player_lane) != 1:
		return
	var window_msec: int = int(maxf(0.0, float(_get_conf("near_miss_window_sec", 0.6))) * 1000.0)
	if _player.has_method("get_lane_runner_msec_since_switch") \
		and int(_player.call("get_lane_runner_msec_since_switch")) > window_msec:
		return
	var chance: float = clampf(float(_get_conf("near_miss_crystal_chance", 0.35)), 0.0, 1.0)
	if randf() > chance:
		return
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", Vector2(at_pos.x, _player.global_position.y))

func _update_collectibles(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_lane: int = _player_lane()
	var player_y: float = _player.global_position.y
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 48.0)))
	for i in range(_collectibles.size() - 1, -1, -1):
		var entry: Dictionary = _collectibles[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_collectibles.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		# Gentle pulse so the trail reads as "to grab".
		var pulse: float = 1.0 + sin(_time * TAU * 1.6 + float(entry.get("pulse", 0.0))) * 0.12
		node.scale = Vector2.ONE * pulse

		# Aimant : les pièces (et la géante) se ramassent depuis n'importe quelle
		# voie ; les pickups spéciaux gardent le test de voie.
		var kind: String = str(entry.get("kind", "coin"))
		var lane_ok: bool = int(entry.get("lane", -1)) == player_lane \
			or (_magnet_time_left > 0.0 and (kind == "coin" or kind == "giant"))
		if lane_ok and absf(node.position.y - player_y) <= pickup_radius:
			var at_pos: Vector2 = node.global_position
			node.queue_free()
			_collectibles.remove_at(i)
			if kind == "coin":
				_collect(at_pos)
			elif kind == "giant":
				_collect(at_pos, maxf(1.0, float(_get_conf("giant_coin_value_mult", 10.0))))
				if VFXManager:
					VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -40.0),
						_translate_or("lane_runner_giant", "GIANT COIN!"), Color("#FFD866"), self)
			else:
				_apply_special_pickup(kind, at_pos)
			continue

		if node.position.y > viewport_size.y + 60.0:
			node.queue_free()
			_collectibles.remove_at(i)

## Collectible reward: score (base x wave/world multiplier) + crystal chance.
## value_mult : pièce géante ; s'y multiplient x2 pièces et turbo (score x2).
func _collect(at_pos: Vector2, value_mult: float = 1.0) -> void:
	var mult: float = value_mult
	if _coin_x2_time_left > 0.0:
		mult *= maxf(1.0, float(_get_conf("coin_x2_score_mult", 2.0)))
	if _turbo_time_left > 0.0:
		mult *= maxf(1.0, float(_get_conf("turbo_score_mult", 2.0)))
	var points: int = int(round(float(_collectible_score) * _reward_multiplier * mult))
	if _game and is_instance_valid(_game):
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, at_pos)
		var chance: float = clampf(float(_get_conf("collectible_crystal_chance", 0.12)), 0.0, 1.0)
		if randf() <= chance and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_pos)
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.flash_sprite(_player, Color(1.0, 0.9, 0.55), 0.1)

## Détruit le mur d'index donné (bélier / missile pew pew) : explosion animée,
## score bonus, retrait immédiat des collisions.
func _destroy_wall_at(index: int, explosion_anim: String, base_score: int, explosion_size: float) -> void:
	if index < 0 or index >= _walls.size():
		return
	var entry: Dictionary = _walls[index]
	_release_train_wall(entry)
	var node_v: Variant = entry.get("node", null)
	var at_pos: Vector2 = Vector2.ZERO
	if node_v is Node2D and is_instance_valid(node_v):
		at_pos = (node_v as Node2D).global_position
		(node_v as Node2D).queue_free()
	_walls.remove_at(index)
	if VFXManager:
		VFXManager.spawn_explosion(at_pos, explosion_size, Color(1.0, 0.55, 0.3), self,
			"", explosion_anim, -1.0, 0.3, 0.6, false)
	var points: int = int(round(float(base_score) * _reward_multiplier))
	if points > 0 and _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)

# =============================================================================
# PORTAILS (téléportation instantanée de voie)
# =============================================================================

func _update_portals(dt: float, speed: float) -> void:
	if _portals.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_lane: int = _player_lane()
	var player_y: float = _player.global_position.y
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 48.0)))
	for i in range(_portals.size() - 1, -1, -1):
		var portal: Dictionary = _portals[i]
		var entry_v: Variant = portal.get("entry_node", null)
		var exit_v: Variant = portal.get("exit_node", null)
		if not (entry_v is Node2D) or not is_instance_valid(entry_v):
			_free_portal(i)
			continue
		var entry_node: Node2D = entry_v as Node2D
		entry_node.position.y += speed * dt
		var pulse: float = 1.0 + sin(_time * TAU * 2.2 + float(portal.get("pulse", 0.0))) * 0.1
		entry_node.scale = Vector2.ONE * pulse
		if exit_v is Node2D and is_instance_valid(exit_v):
			(exit_v as Node2D).position.y += speed * dt
			(exit_v as Node2D).scale = Vector2.ONE * pulse
		# Entrée touchée sur la voie du joueur -> blink vers la voie de sortie.
		if int(portal.get("entry_lane", -1)) == player_lane \
			and absf(entry_node.position.y - player_y) <= pickup_radius:
			_teleport_player(portal)
			_free_portal(i)
			continue
		if entry_node.position.y > viewport_size.y + 60.0:
			_free_portal(i)

func _teleport_player(portal: Dictionary) -> void:
	var exit_lane: int = int(portal.get("exit_lane", 0))
	var from_pos: Vector2 = _player.global_position
	if _player.has_method("set_lane_runner_lane"):
		_player.call("set_lane_runner_lane", exit_lane)
	# Brève invulnérabilité : un mur peut arriver sur la voie de sortie sans
	# que le joueur ait pu le lire — le blink ne doit jamais être un piège.
	var invuln: float = maxf(0.0, float(_get_conf("portal_invuln_sec", 0.5)))
	if invuln > 0.0:
		_hit_invuln_timer = maxf(_hit_invuln_timer, invuln)
		if _player.has_method("set_invincible"):
			_player.call("set_invincible", true)
	if VFXManager:
		VFXManager.spawn_impact(from_pos, 18.0, self)
		VFXManager.spawn_impact(_player.global_position, 18.0, self)
		VFXManager.flash_sprite(_player, Color(0.65, 0.85, 1.0), 0.18)

func _free_portal(index: int) -> void:
	var portal: Dictionary = _portals[index]
	for key in ["entry_node", "exit_node"]:
		var node_v: Variant = portal.get(key, null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_portals.remove_at(index)

# =============================================================================
# PEW PEW (canon temporaire : un missile détruit un mur de sa voie)
# =============================================================================

func _update_pew(dt: float) -> void:
	if _pew_time_left <= 0.0:
		return
	_pew_time_left -= dt
	_pew_fire_timer -= dt
	if _pew_fire_timer <= 0.0:
		_pew_fire_timer = maxf(0.1, float(_get_conf("pew_fire_interval_sec", 0.35)))
		_fire_pew_missile()

func _fire_pew_missile() -> void:
	var lane: int = _player_lane()
	if lane < 0:
		return
	var size_v: Variant = _get_conf("pew_missile_size_px", [8, 22])
	var missile_w: float = 8.0
	var missile_h: float = 22.0
	if size_v is Array and (size_v as Array).size() >= 2:
		missile_w = maxf(2.0, float((size_v as Array)[0]))
		missile_h = maxf(6.0, float((size_v as Array)[1]))
	var node := Node2D.new()
	node.name = "PewMissile"
	node.z_as_relative = false
	node.z_index = 13
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-missile_w * 0.5, missile_h * 0.5), Vector2(0.0, -missile_h * 0.5),
		Vector2(missile_w * 0.5, missile_h * 0.5)
	])
	body.color = Color(str(_get_conf("pew_missile_color", "#8FD3FF")))
	node.add_child(body)
	node.position = _player.global_position + Vector2(0.0, -30.0)
	add_child(node)
	_pew_missiles.append({ "node": node, "lane": lane })

func _update_pew_missiles(dt: float) -> void:
	if _pew_missiles.is_empty():
		return
	var missile_speed: float = maxf(100.0, float(_get_conf("pew_missile_speed_px_sec", 900.0)))
	for i in range(_pew_missiles.size() - 1, -1, -1):
		var missile: Dictionary = _pew_missiles[i]
		var node_v: Variant = missile.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pew_missiles.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y -= missile_speed * dt
		var lane: int = int(missile.get("lane", -1))
		var consumed: bool = false
		for j in range(_walls.size() - 1, -1, -1):
			var wall: Dictionary = _walls[j]
			if int(wall.get("lane", -1)) != lane:
				continue
			var wall_node_v: Variant = wall.get("node", null)
			if not (wall_node_v is Node2D) or not is_instance_valid(wall_node_v):
				continue
			if absf((wall_node_v as Node2D).position.y - node.position.y) \
				<= float(wall.get("half_height", 44.0)) + 12.0:
				_destroy_wall_at(j, str(_get_conf("pew_explosion_anim", "res://assets/vfx/mine_explosion.tres")),
					int(_get_conf("pew_wall_score", 15)), _lane_width() * 0.7)
				consumed = true
				break
		if consumed or node.position.y < -60.0:
			node.queue_free()
			_pew_missiles.remove_at(i)

# =============================================================================
# TOURELLES (mode LIBRE hauts levels : projectiles lents en diagonale)
# =============================================================================

## Story : jamais (pas de _free_level_progress ET turret_chance 0). Libre :
## gate par la progression de level PUIS proba par salve — rare puis croissant.
func _update_turrets(dt: float) -> void:
	# Tirs différés d'une salve en cours (échelonnés, pausables).
	while not _turret_shots.is_empty() and float((_turret_shots[0] as Dictionary).get("time", 0.0)) <= _time:
		var shot: Dictionary = _turret_shots.pop_front()
		_fire_turret_shot(shot.get("pos", Vector2.ZERO), shot.get("dir", Vector2.DOWN))
	var progress_v: Variant = _config.get("_free_level_progress", null)
	if not (progress_v is float or progress_v is int):
		return
	if float(progress_v) < clampf(float(_get_conf("turret_min_level_progress", 0.45)), 0.0, 1.0):
		return
	_turret_timer -= dt
	if _turret_timer > 0.0:
		return
	_turret_timer = maxf(1.0, float(_get_conf("turret_interval_sec", 6.0)))
	if randf() < clampf(float(_get_conf("turret_chance", 0.0)), 0.0, 1.0):
		_queue_turret_volley()

func _queue_turret_volley() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var from_left: bool = randf() < 0.5
	var pos := Vector2(-20.0 if from_left else viewport_size.x + 20.0,
		viewport_size.y * randf_range(0.15, 0.45))
	var dir := Vector2(0.55 if from_left else -0.55, 0.83).normalized()
	if VFXManager:
		VFXManager.spawn_impact(Vector2(clampf(pos.x, 10.0, viewport_size.x - 10.0), pos.y), 20.0, self)
	var count: int = maxi(1, int(_get_conf("turret_volley_count", 3)))
	var spacing: float = maxf(0.05, float(_get_conf("turret_volley_spacing_sec", 0.25)))
	for i in range(count):
		_turret_shots.append({
			"time": _time + 0.3 + spacing * float(i),
			"pos": pos,
			"dir": dir.rotated(deg_to_rad(-3.0 + 3.0 * float(i)))
		})

func _fire_turret_shot(pos: Vector2, dir: Vector2) -> void:
	var max_hp_v: Variant = _player.get("max_hp") if (_player and is_instance_valid(_player)) else 100
	var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
	var pct: float = clampf(float(_get_conf("turret_damage_percent", 0.1)), 0.0, 1.0)
	var damage: int = maxi(1, int(ceil(float(max_hp) * pct)))
	var speed: float = maxf(40.0, float(_get_conf("turret_bullet_speed_px_sec", 180.0)))
	if ProjectileManager:
		ProjectileManager.spawn_enemy_projectile(pos, dir, speed, damage)
		_turret_any_fired = true

# =============================================================================
# TOURELLES AU SOL (descendent avec le scroll, tirent le long de leur colonne)
# =============================================================================

## Roulée dans la chaîne exclusive de _spawn_row (gate turret_min_level_progress
## comme les salves). Posée sur une voie JAMAIS sûre au moment du spawn, elle
## descend avec le scroll et tire vers le BAS toutes les
## ground_turret_fire_interval_sec — on esquive en quittant la colonne.
## Télégraphe : impact VFX à l'apparition.
func _spawn_ground_turret(base_y: float) -> void:
	var lane: int = randi() % _lane_count
	if lane == _last_free_lane:
		lane = (lane + 1 + (randi() % (_lane_count - 1))) % _lane_count
	var size_px: float = maxf(24.0, float(_get_conf("ground_turret_size_px", 52.0)))
	var node := Node2D.new()
	node.name = "LaneGroundTurret"
	node.z_as_relative = false
	node.z_index = 11
	node.position = Vector2(_lane_center_x(lane), base_y)
	var asset_path: String = str(_get_conf("ground_turret_asset", ""))
	var built: bool = false
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			node.add_child(sprite)
			built = true
	if not built:
		# PH : socle circulaire sombre + canon rectangulaire pointé vers le bas.
		var base_poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		base_poly.polygon = pts
		base_poly.color = Color("#5A6272")
		node.add_child(base_poly)
		var barrel := Polygon2D.new()
		barrel.polygon = PackedVector2Array([
			Vector2(-size_px * 0.12, 0.0), Vector2(size_px * 0.12, 0.0),
			Vector2(size_px * 0.12, size_px * 0.75), Vector2(-size_px * 0.12, size_px * 0.75)
		])
		barrel.color = Color("#39404F")
		node.add_child(barrel)
	add_child(node)
	if VFXManager:
		VFXManager.spawn_impact(node.global_position, 24.0, self) # télégraphe
	_ground_turrets.append({ "node": node, "lane": lane,
		"fire_timer": maxf(0.2, float(_get_conf("ground_turret_fire_interval_sec", 1.2))) })

func _update_ground_turrets(dt: float, speed: float) -> void:
	if _ground_turrets.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(_ground_turrets.size() - 1, -1, -1):
		var entry: Dictionary = _ground_turrets[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_ground_turrets.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		if node.position.y > viewport_size.y + 80.0:
			node.queue_free()
			_ground_turrets.remove_at(i)
			continue
		if node.position.y < 0.0:
			continue # pas de tir hors écran
		entry["fire_timer"] = float(entry.get("fire_timer", 1.2)) - dt
		if float(entry["fire_timer"]) <= 0.0:
			entry["fire_timer"] = maxf(0.2, float(_get_conf("ground_turret_fire_interval_sec", 1.2)))
			_fire_ground_turret_shot(node.global_position + Vector2(0.0, 30.0))
		_ground_turrets[i] = entry

## Balle rapide (plus vite que le scroll max, sinon la tourelle rattraperait
## ses propres tirs) : danger de colonne lisible, purge commune à _finish.
func _fire_ground_turret_shot(pos: Vector2) -> void:
	var max_hp_v: Variant = _player.get("max_hp") if (_player and is_instance_valid(_player)) else 100
	var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
	var pct: float = clampf(float(_get_conf("ground_turret_damage_percent", 0.1)), 0.0, 1.0)
	var damage: int = maxi(1, int(ceil(float(max_hp) * pct)))
	var speed: float = maxf(60.0, float(_get_conf("ground_turret_bullet_speed_px_sec", 1100.0)))
	if ProjectileManager:
		ProjectileManager.spawn_enemy_projectile(pos, Vector2.DOWN, speed, damage)
		_turret_any_fired = true

# =============================================================================
# ÉVÉNEMENTS LIBRE (tunnel / heure de pointe) + STREAK PARFAITE
# =============================================================================

## Deux timers indépendants interval+chance (chances 0 en story) ; jamais les
## deux événements actifs en même temps — l'un retient l'autre.
func _update_events(dt: float) -> void:
	if _tunnel_time_left > 0.0:
		_tunnel_time_left -= dt
		if _tunnel_time_left <= 0.0 and _tunnel_rect and is_instance_valid(_tunnel_rect):
			_tunnel_rect.queue_free()
			_tunnel_rect = null
	_update_tunnel_overlay()
	if _rush_time_left > 0.0:
		_rush_time_left -= dt
	var busy: bool = _tunnel_time_left > 0.0 or _rush_time_left > 0.0
	_tunnel_timer -= dt
	if _tunnel_timer <= 0.0:
		_tunnel_timer = maxf(5.0, float(_get_conf("tunnel_interval_sec", 25.0)))
		if not busy and _state == State.RUN \
			and randf() <= clampf(float(_get_conf("tunnel_chance", 0.0)), 0.0, 1.0):
			_start_tunnel()
			busy = true
	_rush_timer -= dt
	if _rush_timer <= 0.0:
		_rush_timer = maxf(5.0, float(_get_conf("rush_hour_interval_sec", 30.0)))
		if not busy and _state == State.RUN \
			and randf() <= clampf(float(_get_conf("rush_hour_chance", 0.0)), 0.0, 1.0):
			_rush_time_left = maxf(1.0, float(_get_conf("rush_hour_duration_sec", 8.0)))
			_show_banner(_translate_or("lane_runner_rush_hour", "RUSH HOUR!"), Color("#FFB347"))

func _start_tunnel() -> void:
	_tunnel_duration = maxf(1.0, float(_get_conf("tunnel_duration_sec", 6.0)))
	_tunnel_time_left = _tunnel_duration
	_ensure_tunnel_overlay()
	_show_banner(_translate_or("lane_runner_tunnel", "TUNNEL!"), Color("#9AA8BF"))

## Pénombre : shader pong_blackout (16 lumières max). Fallback sans shader :
## dim léger fixe.
func _ensure_tunnel_overlay() -> void:
	if _tunnel_rect and is_instance_valid(_tunnel_rect):
		return
	_tunnel_rect = ColorRect.new()
	_tunnel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tunnel_rect.z_as_relative = false
	_tunnel_rect.z_index = 45
	_tunnel_rect.position = Vector2.ZERO
	_tunnel_rect.size = get_viewport_rect().size
	if ResourceLoader.exists(TUNNEL_SHADER_PATH):
		var shader: Shader = load(TUNNEL_SHADER_PATH) as Shader
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_tunnel_rect.material = mat
	if _tunnel_rect.material == null:
		_tunnel_rect.color = Color(0.0, 0.0, 0.0, 0.45)
	add_child(_tunnel_rect)

## Halos : joueur d'abord, puis murs/pièces/portails triés du bas de l'écran
## vers le haut (les dangers proches restent lisibles), cap 16 lumières.
func _update_tunnel_overlay() -> void:
	if _tunnel_rect == null or not is_instance_valid(_tunnel_rect):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_tunnel_rect.size = viewport_size
	var mat: ShaderMaterial = _tunnel_rect.material as ShaderMaterial
	if mat == null:
		return
	var fade: float = clampf(minf(_tunnel_duration - _tunnel_time_left, minf(_tunnel_time_left, 0.4)) / 0.4, 0.0, 1.0)
	var radius: float = maxf(60.0, float(_get_conf("tunnel_light_radius_px", 150.0)))
	var candidates: Array = []
	for entry_v in _walls:
		var wall_node_v: Variant = (entry_v as Dictionary).get("node", null)
		if wall_node_v is Node2D and is_instance_valid(wall_node_v):
			candidates.append((wall_node_v as Node2D).global_position)
	for entry_v in _collectibles:
		var col_node_v: Variant = (entry_v as Dictionary).get("node", null)
		if col_node_v is Node2D and is_instance_valid(col_node_v):
			candidates.append((col_node_v as Node2D).global_position)
	for portal_v in _portals:
		for key in ["entry_node", "exit_node"]:
			var portal_node_v: Variant = (portal_v as Dictionary).get(key, null)
			if portal_node_v is Node2D and is_instance_valid(portal_node_v):
				candidates.append((portal_node_v as Node2D).global_position)
	candidates.sort_custom(func(a, b): return (a as Vector2).y > (b as Vector2).y)
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	positions.append(player_pos)
	radii.append(radius * 1.3)
	for pos_v in candidates:
		if positions.size() >= 16:
			break
		positions.append(pos_v as Vector2)
		radii.append(radius)
	var light_count: int = positions.size()
	while positions.size() < 16:
		positions.append(Vector2(-9999.0, -9999.0))
		radii.append(1.0)
	mat.set_shader_parameter("darkness", clampf(float(_get_conf("tunnel_opacity", 0.85)), 0.0, 1.0) * fade)
	mat.set_shader_parameter("viewport_size", viewport_size)
	mat.set_shader_parameter("light_count", light_count)
	mat.set_shader_parameter("light_pos", positions)
	mat.set_shader_parameter("light_radius", radii)

## Streak parfaite (toujours active) : secondes sans collision de mur ; au seuil
## -> pluie de cristaux et le compteur repart (ré-empochable à l'infini). Les
## dégâts de projectiles passent par Player.take_damage (invisibles ici) : la
## série ne se brise que sur une collision de mur — assumé, documenté.
func _update_streak(dt: float) -> void:
	if _state == State.RUN:
		_streak_sec += dt
		var reward_sec: float = maxf(5.0, float(_get_conf("streak_reward_sec", 30.0)))
		if _streak_sec >= reward_sec:
			_streak_sec = 0.0
			var crystals: int = maxi(1, int(_get_conf("streak_crystals", 6)))
			if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", crystals)
			if VFXManager and _player and is_instance_valid(_player):
				VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -80.0),
					_translate_or("lane_runner_streak", "PERFECT STREAK!"), Color("#7CFC9A"), self)
	_update_streak_label()

func _ensure_streak_label() -> void:
	if _streak_label and is_instance_valid(_streak_label):
		return
	_streak_label = Label.new()
	_streak_label.name = "LaneRunnerStreakLabel"
	_streak_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("streak_font_size", 20))))
	_streak_label.add_theme_color_override("font_color", Color("#7CFC9A"))
	_streak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_streak_label.add_theme_constant_override("outline_size", 4)
	_streak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_label.z_as_relative = false
	_streak_label.z_index = 60
	add_child(_streak_label)

## HUD discret : n'apparaît qu'à partir de 5 s de série en cours.
func _update_streak_label() -> void:
	_ensure_streak_label()
	if _streak_label == null or not is_instance_valid(_streak_label):
		return
	if _streak_sec < 5.0:
		_streak_label.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_streak_label.visible = true
	_streak_label.position = Vector2(16.0,
		viewport_size.y * clampf(float(_get_conf("streak_y_ratio", 0.22)), 0.02, 0.9))
	_streak_label.text = "%ds" % int(_streak_sec)

## Bandeau clignotant d'événement (pattern BreakoutManager).
func _show_banner(text: String, color: Color) -> void:
	if _event_banner == null or not is_instance_valid(_event_banner):
		var viewport_size: Vector2 = get_viewport_rect().size
		_event_banner = Label.new()
		_event_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_event_banner.add_theme_font_size_override("font_size", 40)
		_event_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_event_banner.add_theme_constant_override("outline_size", 5)
		_event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event_banner.z_as_relative = false
		_event_banner.z_index = 55
		_event_banner.size = Vector2(viewport_size.x, 46.0)
		_event_banner.position = Vector2(0.0, viewport_size.y * 0.3)
		add_child(_event_banner)
	_event_banner.text = text
	_event_banner.add_theme_color_override("font_color", color)
	_event_banner.visible = true
	_banner_time = 1.2

func _update_banner(dt: float) -> void:
	if _banner_time <= 0.0:
		return
	_banner_time -= dt
	if _event_banner and is_instance_valid(_event_banner):
		_event_banner.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 8.0))
		if _banner_time <= 0.0:
			_event_banner.visible = false

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "LaneRunnerCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_get_conf("countdown_color", "#FFFFFF"))))
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
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9))
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
	# Les balles de tourelles vivent dans le pool global : purge (aucun autre
	# projectile n'est légitime pendant une vague lane_runner).
	if _turret_any_fired and ProjectileManager:
		ProjectileManager.clear_all_projectiles()
	# Restore the player BEFORE notifying the wave chain.
	_restore_player_mode()
	finished.emit()
	queue_free() # walls, collectibles, portails et missiles sont enfants -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
