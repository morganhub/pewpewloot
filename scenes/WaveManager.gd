extends Node

## WaveManager — Gère le spawn des vagues d'ennemis et d'obstacles.
## Lit les données de niveau et instancie les ennemis/obstacles via Game.gd.

signal spawn_enemy(enemy_data: Dictionary, spawn_pos: Vector2)
signal spawn_obstacle(obstacle_data: Dictionary, positions: Array, speed: float)
signal spawn_snake(config: Dictionary)
signal spawn_gate_runner(config: Dictionary)
signal spawn_pong(config: Dictionary)
signal spawn_breakout(config: Dictionary)
signal spawn_ball_launcher(config: Dictionary)
signal spawn_vertical_climb(config: Dictionary)
signal spawn_absorb(config: Dictionary)
signal spawn_lane_runner(config: Dictionary)
signal spawn_slice_rush(config: Dictionary)
signal spawn_match3(config: Dictionary)
signal spawn_gravity_hole(config: Dictionary)
signal spawn_star_drift(config: Dictionary)
signal spawn_asteroid_field(config: Dictionary)
signal spawn_suika_up(config: Dictionary)
signal spawn_survivor(config: Dictionary)
signal level_completed
signal wave_started(wave_index: int)
signal story_check_before_wave(wave_index: int)
signal free_mode_level_changed(level: int)

const ObstacleSpawnerScript: Script = preload("res://scenes/obstacles/ObstacleSpawner.gd")

var _current_level_data: Dictionary = {}
var _waves: Array = []
var _current_wave_index: int = 0
var _pending_wave_index: int = -1
var _is_active: bool = false
var _is_wave_running: bool = false
var _current_wave_elapsed: float = 0.0
var _current_wave_duration: float = 20.0
var _current_wave_type: String = "enemy"
var _clear_advance_timer: float = 0.0
var _pending_spawns: Array = [] # {time, enemy_id, pattern_id}
var _available_move_pattern_ids: Array[String] = []
var _active_obstacle_spawners: Array = [] # Active ObstacleSpawner nodes
var _skin_overrides: Dictionary = {} # World-level skin overrides
var _world_wave_runtime_cfg: Dictionary = {}
var _enemy_skin_type_cache: Dictionary = {} # skin_path -> "frames" | "texture" | "unknown"
var _override_elite_replacement_chance: float = 0.0
var _world_id: String = ""
var _log_resource_warmup_enabled: bool = false
var _active_enemy_count: int = 0
var _active_obstacle_count: int = 0

const DEFAULT_MOVE_PATTERN_ID := "linear_cross_fast"
const DEBUG_WAVE_PATTERN_LOG := false
const DEBUG_WAVE_LIFECYCLE_LOG := false
const DEBUG_RESOURCE_WARMUP_LOG := true
const DEBUG_SPAWN_COST_LOG := false
const DEBUG_SPAWN_COST_THRESHOLD_MS := 4.0
const MAX_ENEMY_SPAWNS_PER_FRAME: int = 6
const MAX_WAVE_ELAPSED_STEP_SEC: float = 0.25
const WAVE_END_FLYOFF_MIN_SPEED: float = 1080.0
const WAVE_END_FLYOFF_MAX_SPEED: float = 2040.0
const WAVE_END_FLYOFF_DURATION_SEC: float = 1.6
const WAVE_CLEAR_ADVANCE_DELAY_SEC: float = 2.0
const SPAWN_STOP_BEFORE_WAVE_END_SEC: float = 5.0
const ARTILLERY_WAVE_DEFAULT_ROWS: int = 3
const ARTILLERY_WAVE_DEFAULT_COUNT: int = 18
const ARTILLERY_WAVE_DEFAULT_SPAWN_INTERVAL_SEC: float = 0.08
const ARTILLERY_WAVE_DEFAULT_FIRE_RATE_SEC: float = 3.0

# =============================================================================
# MODE LIBRE — un seul wave_type en boucle infinie, difficulté par "level"
# (1 -> max, +1 tous les seconds_per_level). Config : data/freemode.json.
# =============================================================================

# Durée d'itération des modes "continuous" : le manager ne se termine jamais
# de lui-même, la difficulté est re-scalée en place au changement de level.
const FREE_MODE_CONTINUOUS_DURATION_SEC: float = 86400.0

var _free_mode_active: bool = false
var _free_mode_wave_type: String = ""
var _free_mode_cfg: Dictionary = {} # bloc freemode.json > modes.<type>
# Mode FIESTA : enchaîne des rounds de TOUS les mini-jeux débloqués (type
# différent à chaque round), le level persiste entre les rounds. Les modes
# "continuous" sont forcés en rounds réels (timer visible).
var _free_mode_fiesta: bool = false
var _fiesta_cfg: Dictionary = {} # bloc freemode.json > fiesta
var _fiesta_modes_cfg: Dictionary = {} # freemode.json > modes (complet)
var _fiesta_pool: Array = [] # wave_types débloqués par le profil
var _fiesta_current_type: String = ""
var _free_seconds_per_level: float = 45.0
var _free_max_level: int = 20
var _free_round_duration_default: float = 40.0
var _free_elapsed: float = 0.0
var _free_level: int = 1
# Temps total (sec) pour ATTEINDRE le level i+2 (index 0 = seuil du level 2),
# précalculé depuis leveling.level_time_steps (fallback seconds_per_level).
var _free_level_thresholds: Array[float] = []

## À appeler AVANT setup(). Le niveau synthétique passé à setup() contient la
## vague de level 1 (build_free_mode_wave(1)) ; les itérations suivantes sont
## régénérées dans _complete_current_wave().
func set_free_mode(wave_type: String, freemode_cfg: Dictionary) -> void:
	_free_mode_active = true
	_free_mode_wave_type = wave_type
	_free_mode_cfg = {}
	var modes_v: Variant = freemode_cfg.get("modes", {})
	if modes_v is Dictionary:
		var mode_v: Variant = (modes_v as Dictionary).get(wave_type, {})
		if mode_v is Dictionary:
			_free_mode_cfg = (mode_v as Dictionary).duplicate(true)
	_free_mode_fiesta = wave_type == "fiesta"
	_fiesta_pool.clear()
	_fiesta_current_type = ""
	if _free_mode_fiesta:
		var fiesta_v: Variant = freemode_cfg.get("fiesta", {})
		_fiesta_cfg = (fiesta_v as Dictionary).duplicate(true) if fiesta_v is Dictionary else {}
		_fiesta_modes_cfg = (modes_v as Dictionary).duplicate(true) if modes_v is Dictionary else {}
		# Pool = mini-jeux DÉBLOQUÉS du profil (∩ modes freemode existants).
		if DataManager:
			for id_v in DataManager.get_freemode_mode_ids():
				if ProfileManager == null or ProfileManager.is_wave_type_unlocked(str(id_v)):
					_fiesta_pool.append(str(id_v))
		if _fiesta_pool.is_empty() and DataManager:
			_fiesta_pool = DataManager.get_freemode_mode_ids() # garde-fou
		_fiesta_advance_type()
	var level_steps: Array = []
	var leveling_v: Variant = freemode_cfg.get("leveling", {})
	if leveling_v is Dictionary:
		_free_seconds_per_level = maxf(5.0, float((leveling_v as Dictionary).get("seconds_per_level", 45.0)))
		_free_max_level = maxi(1, int((leveling_v as Dictionary).get("max_level", 20)))
		var steps_v: Variant = (leveling_v as Dictionary).get("level_time_steps", [])
		if steps_v is Array:
			level_steps = steps_v as Array
	var defaults_v: Variant = freemode_cfg.get("defaults", {})
	if defaults_v is Dictionary:
		_free_round_duration_default = maxf(10.0, float((defaults_v as Dictionary).get("round_duration_sec", 40.0)))
	_free_elapsed = 0.0
	_free_level = 1
	_build_free_level_thresholds(level_steps)

## Échelonnement configurable de la montée de level : level_time_steps[] =
## paliers {until_level, seconds} — le passage au level L coûte les "seconds"
## du premier palier dont until_level >= L (fallback : seconds_per_level).
## Permet une cadence rapide au début et plus lente en fin de rampe.
func _build_free_level_thresholds(level_steps: Array) -> void:
	_free_level_thresholds.clear()
	var total: float = 0.0
	for target_level in range(2, _free_max_level + 1):
		total += _seconds_for_level_up(target_level, level_steps)
		_free_level_thresholds.append(total)

func _seconds_for_level_up(target_level: int, level_steps: Array) -> float:
	for step_v in level_steps:
		if not (step_v is Dictionary):
			continue
		var step: Dictionary = step_v as Dictionary
		if target_level <= int(step.get("until_level", 0)):
			return maxf(2.0, float(step.get("seconds", _free_seconds_per_level)))
	return _free_seconds_per_level

func get_free_mode_level() -> int:
	return _free_level

## Type de vague en cours (utilisé par Game pour le splash/tir coupé en mode
## libre : le niveau synthétique ne porte qu'un placeholder).
func get_current_wave_type() -> String:
	return _current_wave_type

## Fiesta : tire le mini-jeu du prochain round (jamais deux fois de suite le
## même) et charge sa config (base_wave/per_level du type).
func _fiesta_advance_type() -> void:
	if _fiesta_pool.is_empty():
		return
	if _fiesta_pool.size() == 1:
		_fiesta_current_type = str(_fiesta_pool[0])
	else:
		var next_type: String = _fiesta_current_type
		while next_type == _fiesta_current_type:
			next_type = str(_fiesta_pool[randi() % _fiesta_pool.size()])
		_fiesta_current_type = next_type
	var mode_v: Variant = _fiesta_modes_cfg.get(_fiesta_current_type, {})
	_free_mode_cfg = (mode_v as Dictionary).duplicate(true) if mode_v is Dictionary else {}

## Vague du mode libre au level donné : {type, duration, countdown_hidden}
## + base_wave, puis chaque clé numérique de per_level ajoutée en
## (level-1) x delta sur la valeur de base_wave. Les listes pattern_ids[]
## éventuelles sont résolues en un pattern_id tiré au hasard par itération.
func build_free_mode_wave(level: int) -> Dictionary:
	# loop_style "continuous" : une seule itération quasi infinie, la montée de
	# difficulté est poussée en place au manager (update_free_mode_config) — pas
	# de réengagement d'état (indispensable pour pong et les modes à match).
	# FIESTA : jamais continuous — chaque mini-jeu joue un round RÉEL puis passe
	# au suivant (comme des vagues story), le timer de round reste visible.
	var continuous: bool = not _free_mode_fiesta \
		and str(_free_mode_cfg.get("loop_style", "restart")) == "continuous"
	var round_duration: float = FREE_MODE_CONTINUOUS_DURATION_SEC if continuous \
		else maxf(10.0, float(_free_mode_cfg.get("round_duration_sec", _free_round_duration_default)))
	if _free_mode_fiesta:
		# Durée du round : celle du MODE s'il en déclare une (rounds
		# intrinsèques : absorb, gravity_hole, snake, gate_runner), sinon la
		# durée fiesta.
		round_duration = maxf(10.0, float(_free_mode_cfg.get("round_duration_sec",
			_fiesta_cfg.get("round_duration_sec", _free_round_duration_default))))
	var wave: Dictionary = {
		"type": _fiesta_current_type if _free_mode_fiesta else _free_mode_wave_type,
		"countdown_hidden": not _free_mode_fiesta,
		"duration": round_duration,
		# Progression 0->1 du level (1->max_level). En continuous, la durée est
		# quasi infinie : les rampes temporelles *_start->*_end des managers
		# (elapsed/duration) resteraient figées à 0 — ils substituent cette
		# valeur à _ramp_t() pour que les clés *_end restent effectives.
		"_free_level_progress": clampf(float(level - 1) / float(maxi(1, _free_max_level - 1)), 0.0, 1.0)
	}
	var base_v: Variant = _free_mode_cfg.get("base_wave", {})
	if base_v is Dictionary:
		for key in (base_v as Dictionary).keys():
			wave[key] = (base_v as Dictionary)[key]
	var per_level_v: Variant = _free_mode_cfg.get("per_level", {})
	if per_level_v is Dictionary and level > 1:
		for key in (per_level_v as Dictionary).keys():
			var delta_v: Variant = (per_level_v as Dictionary)[key]
			var base_val_v: Variant = wave.get(key, 0.0)
			if (delta_v is float or delta_v is int) and (base_val_v is float or base_val_v is int):
				wave[key] = float(base_val_v) + float(delta_v) * float(level - 1)
	var pattern_ids_v: Variant = wave.get("pattern_ids", null)
	if pattern_ids_v is Array and not (pattern_ids_v as Array).is_empty():
		var pool: Array = pattern_ids_v as Array
		wave["pattern_id"] = str(pool[randi() % pool.size()])
		wave.erase("pattern_ids")
	return wave

func _tick_free_mode_level(delta: float) -> void:
	if not _free_mode_active:
		return
	_free_elapsed += delta
	var new_level: int = _free_level
	while new_level < _free_max_level and new_level - 1 < _free_level_thresholds.size() \
		and _free_elapsed >= _free_level_thresholds[new_level - 1]:
		new_level += 1
	if new_level != _free_level:
		_free_level = new_level
		free_mode_level_changed.emit(_free_level)

func setup(level_id: String, world_id: String = "") -> void:
	_current_level_data = DataManager.get_level_data(level_id)
	if _current_level_data.is_empty():
		push_warning("[WaveManager] Level data not found: " + level_id)
		return
	
	# Load world-level skin overrides
	if world_id != "":
		_skin_overrides = DataManager.get_world_skin_overrides(world_id)
	else:
		_skin_overrides = {}
	_world_id = world_id
	_world_wave_runtime_cfg = {}
	if world_id != "" and DataManager:
		var world_data: Dictionary = DataManager.get_world(world_id)
		var runtime_cfg_v: Variant = world_data.get("wave_runtime_defaults", {})
		if runtime_cfg_v is Dictionary:
			_world_wave_runtime_cfg = (runtime_cfg_v as Dictionary).duplicate(true)
	
	_waves = _current_level_data.get("waves", [])
	if _free_mode_active:
		# Mode libre : la vague jouée est toujours régénérée localement (le
		# niveau synthétique ne porte qu'un placeholder).
		_waves = [build_free_mode_wave(_free_level)]
	_current_wave_index = 0
	_current_wave_elapsed = 0.0
	_current_wave_duration = 20.0
	_current_wave_type = "enemy"
	_clear_advance_timer = 0.0
	_is_wave_running = false
	_pending_wave_index = -1
	_pending_spawns.clear()
	_enemy_skin_type_cache.clear()
	_active_enemy_count = 0
	_active_obstacle_count = 0
	_refresh_move_pattern_pool()
	_prewarm_wave_resources()
	_is_active = true

	if _waves.is_empty():
		_is_active = false
		level_completed.emit()
		return
	# Wave 1 is NOT queued here: setup() runs behind the loading screen, so an
	# immediate start would play the first wave invisibly (and the start-of-run
	# cleanup would finish_now() any manager wave, skipping it). Game calls
	# start_waves() once the bootstrap (loading + intro story) is done.

	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Setup level: ", level_id, " with ", _waves.size(), " waves. Skin overrides: ", _skin_overrides.keys())

## Called by Game at the end of the run bootstrap (post-loading, post-story):
## queues the first wave. Idempotent.
func start_waves() -> void:
	if not _is_active or _is_wave_running or _pending_wave_index >= 0:
		return
	_queue_wave_start(_current_wave_index)

func set_override_elite_replacement_chance(chance: float) -> void:
	_override_elite_replacement_chance = clampf(chance, 0.0, 1.0)

func set_performance_config(performance_cfg: Dictionary) -> void:
	_log_resource_warmup_enabled = OS.is_debug_build() and bool(performance_cfg.get("log_wave_resource_warmup", false))

func track_enemy_node(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	_active_enemy_count += 1
	enemy.tree_exiting.connect(_on_tracked_enemy_exiting, CONNECT_ONE_SHOT)

func track_obstacle_node(obstacle: Node) -> void:
	if not is_instance_valid(obstacle):
		return
	_active_obstacle_count += 1
	obstacle.tree_exiting.connect(_on_tracked_obstacle_exiting, CONNECT_ONE_SHOT)

func _on_tracked_enemy_exiting() -> void:
	_active_enemy_count = maxi(0, _active_enemy_count - 1)

func _on_tracked_obstacle_exiting() -> void:
	_active_obstacle_count = maxi(0, _active_obstacle_count - 1)

func stop() -> void:
	_is_active = false
	_is_wave_running = false
	_current_wave_elapsed = 0.0
	_clear_advance_timer = 0.0
	_pending_wave_index = -1
	_pending_spawns.clear()
	_enemy_skin_type_cache.clear()
	_active_enemy_count = 0
	_active_obstacle_count = 0
	# Arrêter tous les spawners d'obstacles actifs
	for spawner in _active_obstacle_spawners:
		if is_instance_valid(spawner):
			spawner.stop()
			spawner.queue_free()
	_active_obstacle_spawners.clear()

func _process(delta: float) -> void:
	if not _is_active:
		return

	_tick_free_mode_level(delta)
	_process_pending_spawns(delta)
	if not _is_wave_running:
		return
	# Prevent a single long frame from skipping almost a full wave (and its spawns).
	_current_wave_elapsed += minf(delta, MAX_WAVE_ELAPSED_STEP_SEC)
	if _current_wave_elapsed >= _current_wave_duration:
		_complete_current_wave()
		return
	if _should_advance_cleared_wave(delta):
		_complete_current_wave()

func continue_after_story() -> void:
	if _pending_wave_index < 0 or _pending_wave_index >= _waves.size():
		_pending_wave_index = -1
		return
	var next_wave: Dictionary = _waves[_pending_wave_index]
	_start_wave(next_wave)
	_pending_wave_index = -1

func _queue_wave_start(index: int) -> void:
	if index < 0 or index >= _waves.size():
		return
	_pending_wave_index = index
	story_check_before_wave.emit(index)

func _complete_current_wave() -> void:
	_is_wave_running = false
	_current_wave_elapsed = 0.0
	# If spawns were throttled this frame, flush the ready queue before clearing.
	_flush_ready_spawns_unlimited()
	_pending_spawns.clear()
	_start_wave_end_enemy_flyoff()
	for spawner in _active_obstacle_spawners:
		if is_instance_valid(spawner):
			spawner.stop()
			spawner.queue_free()
	_active_obstacle_spawners.clear()

	var next_wave_index: int = _current_wave_index + 1
	if next_wave_index >= _waves.size():
		if _free_mode_active:
			# Boucle infinie : régénérer la vague au level courant et repartir
			# au lieu de terminer le niveau. En fiesta, le prochain round change
			# de mini-jeu (le level, lui, persiste : difficulté croissante).
			if _free_mode_fiesta:
				_fiesta_advance_type()
			_waves = [build_free_mode_wave(_free_level)]
			_current_wave_index = 0
			_queue_wave_start(0)
			return
		_is_active = false
		level_completed.emit()
		return
	_current_wave_index = next_wave_index
	_queue_wave_start(_current_wave_index)

## Called by Game when the GateRunnerManager reports its scripted content is over
## (all gates/swarms dispatched and no enemy ship left on screen). Ends the wave
## early so there is no idle period before the next wave.
func notify_gate_runner_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "gate_runner":
		return
	_complete_current_wave()

## Called by Game when the PongManager reports the pong match is over.
func notify_pong_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "pong":
		return
	_complete_current_wave()

## Called by Game when the BreakoutManager reports the wall is cleared or the
## timer is over.
func notify_breakout_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "breakout":
		return
	_complete_current_wave()

## Called by Game when the BallLauncherManager reports the run is over.
func notify_ball_launcher_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "ball_launcher":
		return
	_complete_current_wave()

## Called by Game when the VerticalClimbManager reports the climb is over.
func notify_vertical_climb_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "vertical_climb":
		return
	_complete_current_wave()

## Called by Game when the AbsorbManager reports the hunt is over.
func notify_absorb_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "absorb":
		return
	_complete_current_wave()

## Called by Game when the LaneRunnerManager reports the run is over.
func notify_lane_runner_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "lane_runner":
		return
	_complete_current_wave()

## Called by Game when the SliceRushManager reports the slicing is over.
func notify_slice_rush_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "slice_rush":
		return
	_complete_current_wave()

## Called by Game when the Match3Manager reports the board is done.
func notify_match3_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "match3":
		return
	_complete_current_wave()

## Called by Game when the GravityHoleManager reports the wave is over.
func notify_gravity_hole_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "gravity_hole":
		return
	_complete_current_wave()

## Called by Game when the StarDriftManager reports the drift is over.
func notify_star_drift_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "star_drift":
		return
	_complete_current_wave()

## Called by Game when the SurvivorManager reports the survival is over.
func notify_survivor_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "survivor":
		return
	_complete_current_wave()

## Called by Game when the SuikaUpManager reports the boss died or escaped.
func notify_suika_up_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "suika_up":
		return
	_complete_current_wave()

func _should_advance_cleared_wave(delta: float) -> bool:
	if _current_wave_type == "snake" or _current_wave_type == "gate_runner" \
		or _current_wave_type == "pong" or _current_wave_type == "breakout" \
		or _current_wave_type == "ball_launcher" \
		or _current_wave_type == "vertical_climb" or _current_wave_type == "absorb" \
		or _current_wave_type == "lane_runner" or _current_wave_type == "slice_rush" \
		or _current_wave_type == "match3" or _current_wave_type == "gravity_hole" \
		or _current_wave_type == "star_drift" or _current_wave_type == "suika_up" \
		or _current_wave_type == "survivor":
		_clear_advance_timer = 0.0
		return false
	if not _pending_spawns.is_empty():
		_clear_advance_timer = 0.0
		return false
	if _has_obstacle_spawner_still_spawning():
		_clear_advance_timer = 0.0
		return false
	if _active_enemy_count > 0:
		_clear_advance_timer = 0.0
		return false
	if _active_obstacle_count > 0:
		_clear_advance_timer = 0.0
		return false

	_clear_advance_timer += delta
	return _clear_advance_timer >= WAVE_CLEAR_ADVANCE_DELAY_SEC

func _has_obstacle_spawner_still_spawning() -> bool:
	for i in range(_active_obstacle_spawners.size() - 1, -1, -1):
		var spawner: Variant = _active_obstacle_spawners[i]
		if not is_instance_valid(spawner):
			_active_obstacle_spawners.remove_at(i)
			continue
		if spawner.has_method("is_spawning_finished") and bool(spawner.call("is_spawning_finished")):
			continue
		return true
	return false

func _start_wave_end_enemy_flyoff() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("start_wave_end_flyoff"):
			var is_swarm_enemy: bool = enemy.is_in_group("swarm_enemies")
			# Swarm enemies scatter in all directions; classic waves keep their upward exit arc.
			var angle: float = randf_range(0.0, TAU) if is_swarm_enemy else randf_range(PI, TAU)
			var dir: Vector2 = Vector2(cos(angle), sin(angle)).normalized()
			var speed: float = randf_range(WAVE_END_FLYOFF_MIN_SPEED, WAVE_END_FLYOFF_MAX_SPEED)
			enemy.call("start_wave_end_flyoff", dir, speed, WAVE_END_FLYOFF_DURATION_SEC)
		else:
			enemy.queue_free()

func _start_wave(wave: Dictionary) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Starting wave idx: ", _current_wave_index)

	# Defensive auto-correction: an obstacle wave declared without explicit type
	# would silently fall through to the enemy branch and produce an empty 20s wave.
	# Résolu AVANT wave_started : Game lit get_current_wave_type() au signal
	# (splash/tir coupé du type réel — indispensable en mode libre fiesta).
	var wave_type: String = str(wave.get("type", ""))
	if wave_type == "":
		if wave.has("obstacle_id"):
			push_warning("[WaveManager] wave#" + str(_current_wave_index) + " missing 'type' but has obstacle_id -> auto-set type='obstacle'")
			wave_type = "obstacle"
		elif str(wave.get("enemy_id", "")) == "artillery":
			wave_type = "artillery"
		else:
			wave_type = "enemy"
	_current_wave_type = wave_type

	wave_started.emit(_current_wave_index)

	_pending_spawns.clear()
	_current_wave_duration = maxf(0.1, _resolve_wave_duration(wave))
	_current_wave_elapsed = 0.0
	_clear_advance_timer = 0.0
	_is_wave_running = true

	match wave_type:
		"obstacle":
			_start_obstacle_wave(wave)
		"snake":
			_start_snake_wave(wave)
		"gate_runner":
			_start_gate_runner_wave(wave)
		"pong":
			_start_pong_wave(wave)
		"breakout":
			_start_breakout_wave(wave)
		"ball_launcher":
			_start_ball_launcher_wave(wave)
		"vertical_climb":
			_start_vertical_climb_wave(wave)
		"absorb":
			_start_absorb_wave(wave)
		"lane_runner":
			_start_lane_runner_wave(wave)
		"slice_rush":
			_start_slice_rush_wave(wave)
		"match3":
			_start_match3_wave(wave)
		"gravity_hole":
			_start_gravity_hole_wave(wave)
		"star_drift":
			_start_star_drift_wave(wave)
		"suika_up":
			_start_suika_up_wave(wave)
		"survivor":
			_start_survivor_wave(wave)
		"asteroid_split":
			_start_asteroid_split_wave(wave)
		"swarm":
			_start_swarm_wave(wave)
		"tank":
			_start_tank_wave(wave)
		"artillery":
			_start_artillery_wave(wave)
		_:
			_start_enemy_wave(wave)

	if DEBUG_SPAWN_COST_LOG:
		var wave_cost_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		if wave_cost_ms >= DEBUG_SPAWN_COST_THRESHOLD_MS:
			print("[WavePerf] wave_start cost=", snappedf(wave_cost_ms, 0.1), "ms type=", wave_type, " idx=", _current_wave_index)

func _resolve_wave_duration(wave: Dictionary) -> float:
	var wave_type: String = str(wave.get("type", "enemy"))
	var duration: float = _resolve_base_wave_duration(wave)
	var forced_duration: float = float(_world_wave_runtime_cfg.get("force_duration_sec", -1.0))
	# Gate runner / asteroid waves are time-boxed by design, so an explicit
	# per-wave "duration" must take precedence over the world force_duration_sec.
	var honor_explicit_duration: bool = (wave_type == "gate_runner" or wave_type == "asteroid_split") and wave.has("duration")
	# Pong/breakout/ball_launcher/climb/absorb/lane_runner/slice_rush/match3/
	# gravity_hole waves are self-timed by their manager: keep both clocks
	# identical and never let force_duration_sec truncate them.
	if wave_type == "pong" or wave_type == "breakout" or wave_type == "ball_launcher" \
		or wave_type == "vertical_climb" \
		or wave_type == "absorb" or wave_type == "lane_runner" or wave_type == "slice_rush" \
		or wave_type == "match3" or wave_type == "gravity_hole" or wave_type == "star_drift" \
		or wave_type == "suika_up" or wave_type == "snake" or wave_type == "survivor":
		honor_explicit_duration = true
		if not wave.has("duration"):
			match wave_type:
				"survivor":
					duration = _resolve_survivor_default_duration()
				"snake":
					duration = _resolve_snake_default_duration()
				"pong":
					duration = _resolve_pong_default_duration()
				"breakout":
					duration = _resolve_breakout_default_duration()
				"ball_launcher":
					duration = _resolve_ball_launcher_default_duration()
				"vertical_climb":
					duration = _resolve_vertical_climb_default_duration()
				"lane_runner":
					duration = _resolve_lane_runner_default_duration()
				"slice_rush":
					duration = _resolve_slice_rush_default_duration()
				"match3":
					duration = _resolve_match3_default_duration()
				"gravity_hole":
					duration = _resolve_gravity_hole_default_duration()
				"star_drift":
					duration = _resolve_star_drift_default_duration()
				"suika_up":
					duration = _resolve_suika_up_default_duration()
				_:
					duration = _resolve_absorb_default_duration()
	if forced_duration > 0.0 and not honor_explicit_duration:
		duration = forced_duration
	if wave_type == "suika_up" or wave_type == "match3" or wave_type == "snake":
		# Self-finish (mort/fuite du boss) : marge pour l'anim de fuite.
		duration += 6.0
	if wave_type == "gravity_hole":
		# The manager plays `duration` seconds of gameplay PLUS the intro/outro
		# cover choreography: pad the WaveManager clock so the hard timeout
		# stays a safety net and can never cut the outro mid-transition.
		duration += _resolve_gravity_hole_transition_margin()
	return maxf(0.1, duration)

func _resolve_base_wave_duration(wave: Dictionary) -> float:
	return maxf(0.1, float(wave.get("duration", 20.0)))

func _resolve_spawn_cutoff_time() -> float:
	return maxf(0.0, _current_wave_duration - SPAWN_STOP_BEFORE_WAVE_END_SEC)

func _is_spawn_delay_allowed(delay: float) -> bool:
	return delay <= _resolve_spawn_cutoff_time()

func _start_enemy_wave(wave: Dictionary) -> void:
	var raw_enemy_id: String = str(wave.get("enemy_id", ""))
	var enemy_id: String = raw_enemy_id
	if enemy_id == "" or DataManager.get_enemy(enemy_id).is_empty():
		var fallback_id: String = "swarmer" if not DataManager.get_enemy("swarmer").is_empty() else ""
		push_error("[WaveManager] wave#" + str(_current_wave_index) + " invalid enemy_id='" + raw_enemy_id + "' -> fallback='" + fallback_id + "'")
		enemy_id = fallback_id
	var base_interval: float = maxf(0.05, float(wave.get("interval", _resolve_default_enemy_interval())))
	var count: int = _resolve_enemy_spawn_count(base_interval)
	var interval: float = _resolve_enemy_spawn_interval(base_interval)
	var pattern_id: String = _pick_random_move_pattern_id()

	print("[Wave] wave ", _current_wave_index + 1, " move_pattern=", pattern_id, " enemy_id=", enemy_id, " count=", count)

	# Resolve skin: world-level override > wave-level fallback > none
	var enemy_skin: String = ""
	var enemy_overrides: Variant = _skin_overrides.get("enemies", {})
	if enemy_overrides is Dictionary:
		enemy_skin = str((enemy_overrides as Dictionary).get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(wave.get("enemy_skin", ""))
	
	if DEBUG_WAVE_PATTERN_LOG:
		print("[WaveManager] Wave ", _current_wave_index, " enemy=", enemy_id, " random_pattern=", pattern_id, " enemy_skin=", enemy_skin)
	
	# Optional modifier
	var modifier_id: String = str(wave.get("enemy_modifier_id", ""))
	
	# Ajouter les spawns prévus avec leur délai
	for i in range(count):
		var spawn_delay: float = i * interval
		if not _is_spawn_delay_allowed(spawn_delay):
			break
		var spawn_enemy_id: String = enemy_id
		if enemy_id != "elite" and _override_elite_replacement_chance > 0.0:
			if randf() <= _override_elite_replacement_chance and not DataManager.get_enemy("elite").is_empty():
				spawn_enemy_id = "elite"
		var spawn_skin: String = enemy_skin
		if spawn_enemy_id != enemy_id:
			spawn_skin = _resolve_enemy_skin_for_id(spawn_enemy_id)
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": spawn_enemy_id,
			"pattern_id": pattern_id,
			"modifier_id": modifier_id,
			"enemy_skin": spawn_skin
		})

func _start_swarm_wave(wave: Dictionary) -> void:
	var swarm_cfg: Dictionary = _resolve_swarm_config()
	var raw_enemy_id: String = str(wave.get("enemy_id", ""))
	var enemy_id: String = raw_enemy_id
	if enemy_id == "" or DataManager.get_enemy(enemy_id).is_empty():
		var fallback_id: String = "swarmer" if not DataManager.get_enemy("swarmer").is_empty() else ""
		push_error("[WaveManager] swarm wave#" + str(_current_wave_index) + " invalid enemy_id='" + raw_enemy_id + "' -> fallback='" + fallback_id + "'")
		enemy_id = fallback_id

	var count: int = maxi(1, int(wave.get("count", swarm_cfg.get("default_count", 35))))
	var interval: float = maxf(0.01, float(wave.get("spawn_interval_sec", swarm_cfg.get("spawn_interval_sec", 0.15))))
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zone_top_ratio: float = clampf(float(wave.get("zone_top_ratio", swarm_cfg.get("zone_top_ratio", 0.12))), 0.0, 0.95)
	var zone_height_ratio: float = clampf(float(wave.get("zone_height_ratio", swarm_cfg.get("zone_height_ratio", 0.25))), 0.01, 1.0 - zone_top_ratio)
	var zone_rect := Rect2(
		0.0,
		viewport_size.y * zone_top_ratio,
		viewport_size.x,
		viewport_size.y * zone_height_ratio
	)
	var entry_speed: float = maxf(1.0, float(wave.get("entry_speed_px_sec", swarm_cfg.get("entry_speed_px_sec", 900.0))))
	var drift_speed_min: float = maxf(0.0, float(wave.get("drift_speed_min", swarm_cfg.get("drift_speed_min", 18.0))))
	var drift_speed_max: float = maxf(drift_speed_min, float(wave.get("drift_speed_max", swarm_cfg.get("drift_speed_max", 42.0))))
	var direction_change_min: float = maxf(0.05, float(wave.get("direction_change_interval_min", swarm_cfg.get("direction_change_interval_min", 0.8))))
	var direction_change_max: float = maxf(direction_change_min, float(wave.get("direction_change_interval_max", swarm_cfg.get("direction_change_interval_max", 1.8))))

	var enemy_skin: String = ""
	var enemy_overrides: Variant = _skin_overrides.get("enemies", {})
	if enemy_overrides is Dictionary:
		enemy_skin = str((enemy_overrides as Dictionary).get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(wave.get("enemy_skin", ""))

	var modifier_id: String = str(wave.get("enemy_modifier_id", ""))
	print("[Wave] wave ", _current_wave_index + 1, " type=swarm enemy_id=", enemy_id, " count=", count, " interval=", interval)

	for i in range(count):
		var spawn_delay: float = float(i) * interval
		if not _is_spawn_delay_allowed(spawn_delay):
			break
		var spawn_enemy_id: String = enemy_id
		if enemy_id != "elite" and _override_elite_replacement_chance > 0.0:
			if randf() <= _override_elite_replacement_chance and not DataManager.get_enemy("elite").is_empty():
				spawn_enemy_id = "elite"
		var spawn_skin: String = enemy_skin
		if spawn_enemy_id != enemy_id:
			spawn_skin = _resolve_enemy_skin_for_id(spawn_enemy_id)
		var target_pos := Vector2(
			randf_range(zone_rect.position.x, zone_rect.position.x + zone_rect.size.x),
			randf_range(zone_rect.position.y, zone_rect.position.y + zone_rect.size.y)
		)
		var spawn_pos := Vector2(target_pos.x, -80.0)
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": spawn_enemy_id,
			"pattern_id": "",
			"modifier_id": modifier_id,
			"enemy_skin": spawn_skin,
			"spawn_pos": spawn_pos,
			"movement_mode": "swarm",
			"swarm_target_position": target_pos,
			"swarm_zone_rect": zone_rect,
			"swarm_entry_speed": entry_speed,
			"swarm_drift_speed": randf_range(drift_speed_min, drift_speed_max),
			"swarm_direction_change_interval_min": direction_change_min,
			"swarm_direction_change_interval_max": direction_change_max
		})

func _start_tank_wave(wave: Dictionary) -> void:
	var tank_cfg: Dictionary = _resolve_tank_wave_config()
	var enemy_id: String = str(wave.get("enemy_id", "tank"))
	if enemy_id == "" or DataManager.get_enemy(enemy_id).is_empty():
		enemy_id = "tank"
	if DataManager.get_enemy(enemy_id).is_empty():
		push_error("[WaveManager] tank wave#" + str(_current_wave_index) + " could not resolve tank enemy.")
		return

	var interval: float = maxf(0.1, float(wave.get("interval", tank_cfg.get("default_interval_sec", 9.0))))
	var count: int = maxi(1, int(wave.get("count", ceil(maxf(0.1, _resolve_spawn_cutoff_time()) / interval))))
	var hp_multiplier: float = maxf(0.01, float(wave.get("hp_multiplier", tank_cfg.get("default_hp_multiplier", 1.35))))
	var speed_px_sec: float = maxf(1.0, float(wave.get("speed_px_sec", tank_cfg.get("speed_px_sec", 150.0))))
	var scale_multiplier: float = maxf(0.01, float(wave.get("scale_multiplier", tank_cfg.get("scale_multiplier", 2.0))))
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center_ratio: float = clampf(float(wave.get("center_x_ratio", tank_cfg.get("center_x_ratio", 0.5))), 0.0, 1.0)
	var jitter_ratio: float = clampf(float(wave.get("center_x_jitter_ratio", tank_cfg.get("center_x_jitter_ratio", 0.08))), 0.0, 0.45)
	var spawn_y: float = float(wave.get("spawn_y", tank_cfg.get("spawn_y", -110.0)))
	var base_x: float = viewport_size.x * center_ratio
	var jitter_px: float = viewport_size.x * jitter_ratio

	var enemy_skin: String = ""
	var enemy_overrides: Variant = _skin_overrides.get("enemies", {})
	if enemy_overrides is Dictionary:
		enemy_skin = str((enemy_overrides as Dictionary).get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(wave.get("enemy_skin", ""))

	var modifier_id: String = str(wave.get("enemy_modifier_id", ""))
	print("[Wave] wave ", _current_wave_index + 1, " type=tank enemy_id=", enemy_id, " count=", count, " interval=", interval)

	for i in range(count):
		var spawn_delay: float = float(i) * interval
		if not _is_spawn_delay_allowed(spawn_delay):
			break
		var spawn_x: float = clampf(base_x + randf_range(-jitter_px, jitter_px), 0.0, viewport_size.x)
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": enemy_id,
			"pattern_id": "",
			"modifier_id": modifier_id,
			"enemy_skin": enemy_skin,
			"spawn_pos": Vector2(spawn_x, spawn_y),
			"movement_mode": "tank",
			"tank_speed_px_sec": speed_px_sec,
			"visual_scale_multiplier": scale_multiplier,
			"hp_multiplier": hp_multiplier
		})

func _start_artillery_wave(wave: Dictionary) -> void:
	var enemy_id: String = str(wave.get("enemy_id", "artillery"))
	if enemy_id == "" or DataManager.get_enemy(enemy_id).is_empty():
		enemy_id = "artillery"
	if DataManager.get_enemy(enemy_id).is_empty():
		push_error("[WaveManager] artillery wave#" + str(_current_wave_index) + " could not resolve artillery enemy.")
		return

	var rows: int = maxi(1, int(wave.get("rows", int(_world_wave_runtime_cfg.get("artillery_rows", ARTILLERY_WAVE_DEFAULT_ROWS)))))
	var world_default_count: int = int(_world_wave_runtime_cfg.get("artillery_count", ARTILLERY_WAVE_DEFAULT_COUNT))
	var requested_count: int = maxi(rows, int(wave.get("count", world_default_count)))
	var count: int = int(ceil(float(requested_count) / float(rows))) * rows
	var max_units: int = int(wave.get("max_units", int(_world_wave_runtime_cfg.get("artillery_max_units", 0))))
	if max_units > 0:
		var clamped_max_units: int = maxi(rows, int(floor(float(max_units) / float(rows))) * rows)
		if clamped_max_units >= rows:
			count = mini(count, clamped_max_units)
	var spawn_interval: float = maxf(0.01, float(wave.get("spawn_interval_sec", _world_wave_runtime_cfg.get("artillery_spawn_interval_sec", ARTILLERY_WAVE_DEFAULT_SPAWN_INTERVAL_SEC))))
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var top_margin_ratio: float = clampf(float(wave.get("top_margin_ratio", 0.20)), 0.05, 0.8)
	var horizontal_margin_ratio: float = clampf(float(wave.get("horizontal_margin_ratio", 0.12)), 0.0, 0.45)
	var row_spacing_px: float = maxf(24.0, float(wave.get("row_spacing_px", 78.0)))
	var entry_speed_px_sec: float = maxf(1.0, float(wave.get("entry_speed_px_sec", 1200.0)))
	var spawn_y: float = float(wave.get("spawn_y", -140.0))
	var recoil_distance_px: float = maxf(0.0, float(wave.get("recoil_distance_px", 16.0)))
	var recoil_recover_speed_px_sec: float = maxf(1.0, float(wave.get("recoil_recover_speed_px_sec", 72.0)))
	var fire_rate_sec: float = maxf(0.05, float(wave.get("fire_rate_sec", _world_wave_runtime_cfg.get("artillery_fire_rate_sec", ARTILLERY_WAVE_DEFAULT_FIRE_RATE_SEC))))

	var enemy_skin: String = ""
	var enemy_overrides: Variant = _skin_overrides.get("enemies", {})
	if enemy_overrides is Dictionary:
		enemy_skin = str((enemy_overrides as Dictionary).get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(wave.get("enemy_skin", ""))

	var modifier_id: String = str(wave.get("enemy_modifier_id", ""))
	print("[Wave] wave ", _current_wave_index + 1, " type=artillery enemy_id=", enemy_id, " count=", count, " rows=", rows)

	var min_x: float = viewport_size.x * horizontal_margin_ratio
	var max_x: float = viewport_size.x * (1.0 - horizontal_margin_ratio)
	@warning_ignore("integer_division")
	var row_count: int = count / rows

	var spawn_index: int = 0
	for row_index in range(rows):
		if row_count <= 0:
			continue
		var target_y: float = viewport_size.y * top_margin_ratio + float(row_index) * row_spacing_px
		var step_x: float = 0.0 if row_count <= 1 else (max_x - min_x) / float(row_count - 1)
		for column_index in range(row_count):
			var target_x: float = viewport_size.x * 0.5 if row_count <= 1 else min_x + step_x * float(column_index)
			var spawn_delay: float = float(spawn_index) * spawn_interval
			if not _is_spawn_delay_allowed(spawn_delay):
				break
			_pending_spawns.append({
				"delay": spawn_delay,
				"enemy_id": enemy_id,
				"pattern_id": "",
				"modifier_id": modifier_id,
				"enemy_skin": enemy_skin,
				"spawn_pos": Vector2(target_x, spawn_y - float(row_index) * 26.0),
				"movement_mode": "artillery",
				"artillery_target_position": Vector2(target_x, target_y),
				"artillery_entry_speed_px_sec": entry_speed_px_sec,
				"artillery_recoil_distance_px": recoil_distance_px,
				"artillery_recoil_recover_speed_px_sec": recoil_recover_speed_px_sec,
				"fire_rate_override": fire_rate_sec
			})
			spawn_index += 1

func _resolve_enemy_spawn_count(interval: float) -> int:
	var safe_interval: float = maxf(0.05, interval)
	var multiplier: float = _resolve_enemy_density_multiplier()
	var spawn_window: float = maxf(0.1, _resolve_spawn_cutoff_time())
	var base_count: int = maxi(1, int(ceil(spawn_window / safe_interval)))
	var count: int = maxi(1, int(ceil(float(base_count) * multiplier)))
	var max_count: int = maxi(1, int(_world_wave_runtime_cfg.get("enemy_max_spawns_per_wave", 160)))
	var global_cap: int = _resolve_enemy_density_cap()
	if global_cap > 0:
		max_count = mini(max_count, global_cap)
	return mini(count, max_count)

func _resolve_enemy_spawn_interval(base_interval: float) -> float:
	var multiplier: float = _resolve_enemy_density_multiplier()
	var scaled: float = maxf(0.05, base_interval) / maxf(0.01, multiplier)
	return clampf(scaled, 0.05, _current_wave_duration)

func _resolve_enemy_density_multiplier() -> float:
	if DataManager == null:
		return 1.0
	var cfg: Dictionary = DataManager.get_game_config()
	var gameplay_v: Variant = cfg.get("gameplay", {})
	if not (gameplay_v is Dictionary):
		return 1.0
	return maxf(0.01, float((gameplay_v as Dictionary).get("enemy_density_multiplier", 1.0)))

func _resolve_enemy_density_cap() -> int:
	if DataManager == null:
		return 0
	var cfg: Dictionary = DataManager.get_game_config()
	var gameplay_v: Variant = cfg.get("gameplay", {})
	if not (gameplay_v is Dictionary):
		return 0
	return maxi(0, int((gameplay_v as Dictionary).get("enemy_density_max_per_wave", 0)))

func _resolve_default_enemy_interval() -> float:
	return maxf(0.05, float(_world_wave_runtime_cfg.get("enemy_target_interval_sec", 1.0)))

func _resolve_swarm_config() -> Dictionary:
	if DataManager == null:
		return {}
	return DataManager.get_wave_type_config("swarm")

func _resolve_tank_wave_config() -> Dictionary:
	if DataManager == null:
		return {}
	return DataManager.get_wave_type_config("tank")

func _resolve_enemy_skin_for_id(enemy_id: String) -> String:
	var enemy_overrides: Variant = _skin_overrides.get("enemies", {})
	if enemy_overrides is Dictionary:
		return str((enemy_overrides as Dictionary).get(enemy_id, ""))
	return ""

func _start_obstacle_wave(wave: Dictionary) -> void:
	var spawner_node: Node = ObstacleSpawnerScript.new()
	spawner_node.name = "ObstacleSpawner_" + str(_current_wave_index)
	add_child(spawner_node)
	
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _current_wave_duration
	payload["spawn_cutoff_time"] = _resolve_spawn_cutoff_time()
	spawner_node.setup(payload)
	spawner_node.obstacle_spawn_request.connect(_on_obstacle_spawn_request)
	spawner_node.finished.connect(_on_obstacle_spawner_finished.bind(spawner_node))
	_active_obstacle_spawners.append(spawner_node)
	
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Obstacle wave started: pattern=", wave.get("pattern"),
			" obstacle=", wave.get("obstacle_id"))

func _start_snake_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_snake_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_snake.emit(payload)

func _resolve_snake_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("snake") if DataManager else {}
	return maxf(10.0, float(cfg.get("round_duration_sec", 45.0)))

## Called by Game when the SnakeManager reports the wave is over (boss kill).
func notify_snake_finished() -> void:
	if not _is_wave_running:
		return
	if _current_wave_type != "snake":
		return
	_complete_current_wave()

func _start_gate_runner_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = maxf(0.1, _resolve_gate_runner_default_duration(wave))
	payload["wave_index"] = _current_wave_index
	spawn_gate_runner.emit(payload)

func _start_pong_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_pong_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_pong.emit(payload)

func _resolve_pong_default_duration() -> float:
	var pong_cfg: Dictionary = DataManager.get_pong_config() if DataManager else {}
	return maxf(5.0, float(pong_cfg.get("duration_sec_default", 30.0)))

func _start_breakout_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_breakout_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_breakout.emit(payload)

func _resolve_breakout_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("breakout") if DataManager else {}
	return maxf(5.0, float(cfg.get("duration_sec_default", 45.0)))

func _start_ball_launcher_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_ball_launcher_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_ball_launcher.emit(payload)

func _resolve_ball_launcher_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("ball_launcher") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 60.0)))

func _start_suika_up_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_suika_up_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_suika_up.emit(payload)

func _resolve_suika_up_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("suika_up") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 60.0)))

func _start_vertical_climb_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_vertical_climb_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_vertical_climb.emit(payload)

func _resolve_vertical_climb_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("vertical_climb") if DataManager else {}
	return maxf(5.0, float(cfg.get("duration_sec_default", 40.0)))

func _start_absorb_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_absorb_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_absorb.emit(payload)

func _resolve_absorb_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("absorb") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 30.0)))

func _start_lane_runner_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_lane_runner_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_lane_runner.emit(payload)

func _resolve_lane_runner_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("lane_runner") if DataManager else {}
	return maxf(8.0, float(cfg.get("duration_sec_default", 35.0)))

func _start_slice_rush_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_slice_rush_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_slice_rush.emit(payload)

func _resolve_slice_rush_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("slice_rush") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 30.0)))

func _start_match3_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_match3_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_match3.emit(payload)

func _resolve_match3_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("match3") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 45.0)))

func _start_gravity_hole_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_gravity_hole_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_gravity_hole.emit(payload)

func _resolve_gravity_hole_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("gravity_hole") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 40.0)))

func _resolve_gravity_hole_transition_margin() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("gravity_hole") if DataManager else {}
	return clampf(float(cfg.get("transition_margin_sec", 6.0)), 2.0, 20.0)

func _start_star_drift_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_star_drift_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_star_drift.emit(payload)

func _resolve_star_drift_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("star_drift") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 50.0)))

func _start_survivor_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_survivor_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_survivor.emit(payload)

func _resolve_survivor_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("survivor") if DataManager else {}
	return maxf(10.0, float(cfg.get("duration_sec_default", 80.0)))

func _start_asteroid_split_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		payload["duration"] = _resolve_asteroid_split_default_duration()
	payload["wave_index"] = _current_wave_index
	spawn_asteroid_field.emit(payload)

func _resolve_asteroid_split_default_duration() -> float:
	var cfg: Dictionary = DataManager.get_wave_type_config("asteroid_split") if DataManager else {}
	return maxf(5.0, float(cfg.get("duration_sec_default", 35.0)))

func _resolve_gate_runner_default_duration(wave: Dictionary) -> float:
	# Default duration = last scheduled event time + buffer (if no explicit duration).
	var forced_duration: float = float(_world_wave_runtime_cfg.get("force_duration_sec", -1.0))
	if forced_duration > 0.0:
		return forced_duration
	var last_offset: float = 0.0
	var gates_v: Variant = wave.get("gates", [])
	if gates_v is Array:
		for gate_variant in (gates_v as Array):
			if gate_variant is Dictionary:
				last_offset = maxf(last_offset, float((gate_variant as Dictionary).get("time_offset", 0.0)))
	var swarm_v: Variant = wave.get("swarm", {})
	if swarm_v is Dictionary:
		last_offset = maxf(last_offset, float((swarm_v as Dictionary).get("time_offset", 0.0)))
	elif swarm_v is Array:
		for s_variant in (swarm_v as Array):
			if s_variant is Dictionary:
				last_offset = maxf(last_offset, float((s_variant as Dictionary).get("time_offset", 0.0)))
	return last_offset + 10.0

func _on_obstacle_spawn_request(obstacle_data: Dictionary, positions: Array, speed: float) -> void:
	spawn_obstacle.emit(obstacle_data, positions, speed)

func _on_obstacle_spawner_finished(spawner: Node) -> void:
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Obstacle spawner finished: ", spawner.name)
	_active_obstacle_spawners.erase(spawner)
	if is_instance_valid(spawner):
		spawner.queue_free()

func _refresh_move_pattern_pool() -> void:
	_available_move_pattern_ids.clear()
	var all_patterns: Array = DataManager.get_all_move_patterns()
	for pattern in all_patterns:
		if pattern is Dictionary:
			var p_dict: Dictionary = pattern as Dictionary
			var pattern_id: String = str(p_dict.get("id", ""))
			if pattern_id != "":
				_available_move_pattern_ids.append(pattern_id)

	if _available_move_pattern_ids.is_empty():
		_available_move_pattern_ids.append(DEFAULT_MOVE_PATTERN_ID)

func _pick_random_move_pattern_id() -> String:
	if _available_move_pattern_ids.is_empty():
		_refresh_move_pattern_pool()
	var idx: int = randi() % _available_move_pattern_ids.size()
	return _available_move_pattern_ids[idx]

func _get_random_spawn_position() -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var margin_x: float = 50.0
	var min_x: float = margin_x
	var max_x: float = maxf(margin_x, viewport_size.x - margin_x)
	var x: float = randf_range(min_x, max_x)
	# Spawn near top edge, inside visible screen bounds.
	var y: float = randf_range(0.0, 80.0)
	return Vector2(x, y)

func _process_pending_spawns(delta: float) -> void:
	var spawns_triggered: int = 0
	for i in range(_pending_spawns.size() - 1, -1, -1):
		var spawn: Dictionary = _pending_spawns[i]
		spawn["delay"] -= delta
		_pending_spawns[i] = spawn
		
		if spawn["delay"] <= 0:
			if spawns_triggered >= MAX_ENEMY_SPAWNS_PER_FRAME:
				spawn["delay"] = 0.0
				_pending_spawns[i] = spawn
				continue
			_trigger_spawn(spawn)
			_pending_spawns.remove_at(i)
			spawns_triggered += 1

func _trigger_spawn(spawn_info: Dictionary) -> void:
	var t0_usec: int = 0
	if DEBUG_SPAWN_COST_LOG:
		t0_usec = Time.get_ticks_usec()

	var enemy_id: String = str(spawn_info.get("enemy_id", ""))
	var enemy_data := DataManager.get_enemy(enemy_id).duplicate(false)
	if enemy_data.is_empty():
		push_error("[WaveManager] Unknown enemy_id at spawn time (wave#" + str(_current_wave_index) + "): '" + enemy_id + "' -> spawn skipped")
		return
		
	# Override pattern si défini dans la vague
	if spawn_info["pattern_id"] != "":
		enemy_data["move_pattern_id"] = spawn_info["pattern_id"]
		enemy_data["_move_pattern_data"] = DataManager.get_move_pattern(str(spawn_info["pattern_id"]))
		
	# Inject modifier if present
	if spawn_info.get("modifier_id", "") != "":
		enemy_data["modifier_id"] = spawn_info["modifier_id"]
	if spawn_info.has("fire_rate_override"):
		enemy_data["fire_rate"] = float(spawn_info.get("fire_rate_override", enemy_data.get("fire_rate", 2.0)))
	if spawn_info.has("hp_multiplier"):
		enemy_data["hp"] = int(round(float(enemy_data.get("hp", 50)) * maxf(0.01, float(spawn_info.get("hp_multiplier", 1.0)))))
	if spawn_info.has("visual_scale_multiplier"):
		var scale_multiplier: float = maxf(0.01, float(spawn_info.get("visual_scale_multiplier", 1.0)))
		var size_v: Variant = enemy_data.get("size", {})
		if size_v is Dictionary:
			var size_dict: Dictionary = (size_v as Dictionary).duplicate(true)
			size_dict["width"] = float(size_dict.get("width", 30.0)) * scale_multiplier
			size_dict["height"] = float(size_dict.get("height", 30.0)) * scale_multiplier
			enemy_data["size"] = size_dict

	# Optional visual override per wave.
	var enemy_skin: String = str(spawn_info.get("enemy_skin", ""))
	_apply_enemy_skin_override(enemy_data, enemy_skin)

	if str(spawn_info.get("movement_mode", "")) == "swarm":
		enemy_data["_movement_mode"] = "swarm"
		enemy_data["_swarm_target_position"] = spawn_info.get("swarm_target_position", Vector2.ZERO)
		enemy_data["_swarm_zone_rect"] = spawn_info.get("swarm_zone_rect", Rect2())
		enemy_data["_swarm_entry_speed"] = float(spawn_info.get("swarm_entry_speed", 900.0))
		enemy_data["_swarm_drift_speed"] = float(spawn_info.get("swarm_drift_speed", 30.0))
		enemy_data["_swarm_direction_change_interval_min"] = float(spawn_info.get("swarm_direction_change_interval_min", 0.8))
		enemy_data["_swarm_direction_change_interval_max"] = float(spawn_info.get("swarm_direction_change_interval_max", 1.8))
	elif str(spawn_info.get("movement_mode", "")) == "tank":
		enemy_data["_movement_mode"] = "tank"
		enemy_data["_tank_speed_px_sec"] = float(spawn_info.get("tank_speed_px_sec", 150.0))
	elif str(spawn_info.get("movement_mode", "")) == "artillery":
		enemy_data["_movement_mode"] = "artillery"
		enemy_data["_artillery_target_position"] = spawn_info.get("artillery_target_position", Vector2.ZERO)
		enemy_data["_artillery_entry_speed_px_sec"] = float(spawn_info.get("artillery_entry_speed_px_sec", 1200.0))
		enemy_data["_artillery_recoil_distance_px"] = float(spawn_info.get("artillery_recoil_distance_px", 16.0))
		enemy_data["_artillery_recoil_recover_speed_px_sec"] = float(spawn_info.get("artillery_recoil_recover_speed_px_sec", 72.0))

	# Spawn position is randomized per enemy spawn unless a wave mode provides one.
	var spawn_pos: Vector2 = spawn_info.get("spawn_pos", _get_random_spawn_position())

	spawn_enemy.emit(enemy_data, spawn_pos)

	if DEBUG_SPAWN_COST_LOG:
		var spawn_cost_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		if spawn_cost_ms >= DEBUG_SPAWN_COST_THRESHOLD_MS:
			print(
				"[WavePerf] spawn cost=", snappedf(spawn_cost_ms, 0.1), "ms",
				" enemy=", enemy_id,
				" pattern=", str(spawn_info.get("pattern_id", "")),
				" skin=", str(spawn_info.get("enemy_skin", ""))
			)

func _flush_ready_spawns_unlimited() -> void:
	for i in range(_pending_spawns.size() - 1, -1, -1):
		var spawn_info_v: Variant = _pending_spawns[i]
		if not (spawn_info_v is Dictionary):
			continue
		var spawn_info: Dictionary = spawn_info_v as Dictionary
		if float(spawn_info.get("delay", 0.0)) > 0.0:
			continue
		_trigger_spawn(spawn_info)

func _apply_enemy_skin_override(enemy_data: Dictionary, enemy_skin: String) -> void:
	if enemy_skin == "":
		return
	if not ResourceLoader.exists(enemy_skin):
		push_warning("[WaveManager] enemy_skin resource does not exist: " + enemy_skin)
		return

	var visual: Dictionary = {}
	var visual_variant: Variant = enemy_data.get("visual", {})
	if visual_variant is Dictionary:
		visual = (visual_variant as Dictionary).duplicate(true)

	var skin_type: String = _resolve_enemy_skin_type(enemy_skin)
	if skin_type == "frames":
		visual["asset_anim"] = enemy_skin
		visual["asset"] = ""
	elif skin_type == "texture":
		visual["asset"] = enemy_skin
		visual["asset_anim"] = ""
	else:
		var ext: String = enemy_skin.get_extension().to_lower()
		if ext == "tres" or ext == "res":
			visual["asset_anim"] = enemy_skin
			visual["asset"] = ""
		else:
			visual["asset"] = enemy_skin
			visual["asset_anim"] = ""

	enemy_data["visual"] = visual

func get_pending_spawn_count() -> int:
	return _pending_spawns.size()

func _resolve_enemy_skin_type(enemy_skin: String) -> String:
	if _enemy_skin_type_cache.has(enemy_skin):
		return str(_enemy_skin_type_cache[enemy_skin])

	var skin_type: String = "unknown"
	var ext: String = enemy_skin.get_extension().to_lower()
	if ext == "tres" or ext == "res":
		skin_type = "frames"
	else:
		skin_type = "texture"

	_enemy_skin_type_cache[enemy_skin] = skin_type
	return skin_type

func _prewarm_wave_resources() -> void:
	var seen_paths: Dictionary = {}
	_collect_wave_visual_resources(seen_paths)
	_collect_fiesta_pool_resources(seen_paths)
	_collect_move_pattern_resources(seen_paths)

	for path_variant in seen_paths.keys():
		var path: String = str(path_variant)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var was_cached: bool = ResourceLoader.has_cached(path)
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if DEBUG_RESOURCE_WARMUP_LOG and _log_resource_warmup_enabled:
			print("[WaveManager] Warmup ", ("reused " if was_cached else "loaded "), path)

## Fiesta : prewarm des assets de TOUS les mini-jeux du pool (le type change à
## chaque round — sans ça, hitch au premier spawn de chaque nouveau mode).
## Réutilise _collect_wave_visual_resources via un swap temporaire de _waves.
func _collect_fiesta_pool_resources(target: Dictionary) -> void:
	if not _free_mode_fiesta or _fiesta_pool.is_empty():
		return
	var saved_waves: Array = _waves
	var pseudo_waves: Array = []
	for type_v in _fiesta_pool:
		pseudo_waves.append({"type": str(type_v)})
	_waves = pseudo_waves
	_collect_wave_visual_resources(target)
	_waves = saved_waves

func _collect_wave_visual_resources(target: Dictionary) -> void:
	var enemy_overrides: Dictionary = {}
	var raw_overrides: Variant = _skin_overrides.get("enemies", {})
	if raw_overrides is Dictionary:
		enemy_overrides = raw_overrides as Dictionary

	if not (_waves is Array):
		return

	for wave_variant in _waves:
		if not (wave_variant is Dictionary):
			continue
		var wave: Dictionary = wave_variant as Dictionary
		var wave_type: String = str(wave.get("type", "enemy"))
		if wave_type == "obstacle":
			continue
		if wave_type == "snake":
			var sn_cfg: Dictionary = DataManager.get_wave_type_config("snake") if DataManager else {}
			_add_warmup_path(target, str(wave.get("segment_asset", sn_cfg.get("segment_asset", ""))))
			_add_warmup_path(target, str(wave.get("tail_asset", sn_cfg.get("tail_asset", ""))))
			var sn_seg_assets_v: Variant = wave.get("segment_assets", sn_cfg.get("segment_assets", []))
			if sn_seg_assets_v is Array:
				for sn_seg_asset_v in (sn_seg_assets_v as Array):
					_add_warmup_path(target, str(sn_seg_asset_v))
			var sn_items_v: Variant = wave.get("items", sn_cfg.get("items", []))
			if sn_items_v is Array:
				for sn_item_v in (sn_items_v as Array):
					if sn_item_v is Dictionary:
						_add_warmup_path(target, str((sn_item_v as Dictionary).get("asset", "")))
			var sn_bosses_v: Variant = wave.get("bosses", sn_cfg.get("bosses", []))
			if sn_bosses_v is Array:
				for sn_boss_v in (sn_bosses_v as Array):
					if sn_boss_v is Dictionary:
						_add_warmup_path(target, str((sn_boss_v as Dictionary).get("asset_anim", "")))
			# Événements (13 juillet 2026) : zone, vermine, astéroïdes (assets
			# dédiés + skins d'obstacles du monde en fallback).
			_add_warmup_path(target, str(wave.get("zone_asset", sn_cfg.get("zone_asset", ""))))
			_add_warmup_path(target, str(wave.get("pest_asset", sn_cfg.get("pest_asset", ""))))
			var sn_ast_assets_v: Variant = wave.get("asteroid_assets", sn_cfg.get("asteroid_assets", []))
			if sn_ast_assets_v is Array:
				for sn_ast_asset_v in (sn_ast_assets_v as Array):
					_add_warmup_path(target, str(sn_ast_asset_v))
			var sn_obs_overrides_v: Variant = _skin_overrides.get("obstacles", {})
			if sn_obs_overrides_v is Dictionary:
				var sn_explosives_v: Variant = (sn_obs_overrides_v as Dictionary).get("explosives", [])
				if sn_explosives_v is Array:
					for sn_skin_v in (sn_explosives_v as Array):
						_add_warmup_path(target, str(sn_skin_v))
			continue
		if wave_type == "survivor":
			var sv_cfg: Dictionary = DataManager.get_wave_type_config("survivor") if DataManager else {}
			for sv_key in ["chest_asset"]:
				_add_warmup_path(target, str(wave.get(sv_key, sv_cfg.get(sv_key, ""))))
			var sv_gems_v: Variant = wave.get("gem_tiers", sv_cfg.get("gem_tiers", []))
			if sv_gems_v is Array:
				for sv_gem_v in (sv_gems_v as Array):
					if sv_gem_v is Dictionary:
						_add_warmup_path(target, str((sv_gem_v as Dictionary).get("asset", "")))
			var sv_weapons_v: Variant = wave.get("weapons", sv_cfg.get("weapons", []))
			if sv_weapons_v is Array:
				for sv_weapon_v in (sv_weapons_v as Array):
					if sv_weapon_v is Dictionary:
						_add_warmup_path(target, str((sv_weapon_v as Dictionary).get("icon", "")))
						var sv_base_v: Variant = (sv_weapon_v as Dictionary).get("base", {})
						if sv_base_v is Dictionary:
							_add_warmup_path(target, str((sv_base_v as Dictionary).get("orb_asset", "")))
			var sv_passives_v: Variant = wave.get("passives", sv_cfg.get("passives", []))
			if sv_passives_v is Array:
				for sv_passive_v in (sv_passives_v as Array):
					if sv_passive_v is Dictionary:
						_add_warmup_path(target, str((sv_passive_v as Dictionary).get("icon", "")))
			# Sprites des ennemis des phases (via le dataset enemies standard).
			var sv_phases_v: Variant = wave.get("enemy_phases", sv_cfg.get("enemy_phases", []))
			if sv_phases_v is Array:
				for sv_phase_v in (sv_phases_v as Array):
					if not (sv_phase_v is Dictionary):
						continue
					var sv_pool_v: Variant = (sv_phase_v as Dictionary).get("pool", [])
					if sv_pool_v is Array:
						for sv_entry_v in (sv_pool_v as Array):
							if not (sv_entry_v is Dictionary):
								continue
							var sv_enemy: Dictionary = DataManager.get_enemy(str((sv_entry_v as Dictionary).get("id", ""))) if DataManager else {}
							var sv_visual_v: Variant = sv_enemy.get("visual", {})
							if sv_visual_v is Dictionary:
								_add_warmup_path(target, str((sv_visual_v as Dictionary).get("asset", "")))
								_add_warmup_path(target, str((sv_visual_v as Dictionary).get("asset_anim", "")))
			continue
		if wave_type == "gate_runner":
			var gr_cfg: Dictionary = DataManager.get_gate_runner_config() if DataManager else {}
			_add_warmup_path(target, str(gr_cfg.get("splash_asset_path", "")))
			# Nouveaux assets (clone doré, méga-drone, piscine de déflation).
			for gr_asset_key in ["golden_clone_asset", "mega_drone_asset", "deflation_pool_asset"]:
				_add_warmup_path(target, str(gr_cfg.get(gr_asset_key, "")))
			var swarm_enemy_id: String = str(gr_cfg.get("swarm_enemy_id_default", "swarmer"))
			var swarm_v: Variant = wave.get("swarm", {})
			if swarm_v is Dictionary:
				swarm_enemy_id = str((swarm_v as Dictionary).get("enemy_id", swarm_enemy_id))
			var gr_enemy_data: Dictionary = DataManager.get_enemy(swarm_enemy_id)
			if not gr_enemy_data.is_empty():
				var gr_visual_v: Variant = gr_enemy_data.get("visual", {})
				if gr_visual_v is Dictionary:
					var gr_visual: Dictionary = gr_visual_v as Dictionary
					_add_warmup_path(target, str(gr_visual.get("asset", "")))
					_add_warmup_path(target, str(gr_visual.get("asset_anim", "")))
			var gr_skin: String = str(enemy_overrides.get(swarm_enemy_id, ""))
			if gr_skin != "":
				_add_warmup_path(target, gr_skin)
			continue
		if wave_type == "pong":
			var pong_cfg: Dictionary = DataManager.get_pong_config() if DataManager else {}
			_add_warmup_path(target, str(wave.get("ball_asset", pong_cfg.get("ball_asset", ""))))
			_add_warmup_path(target, str(wave.get("enemy_paddle_asset", pong_cfg.get("enemy_paddle_asset", ""))))
			var paddle_enemy_id: String = str(pong_cfg.get("enemy_visual_enemy_id", "fighter"))
			var paddle_enemy: Dictionary = DataManager.get_enemy(paddle_enemy_id)
			if not paddle_enemy.is_empty():
				var paddle_visual_v: Variant = paddle_enemy.get("visual", {})
				if paddle_visual_v is Dictionary:
					_add_warmup_path(target, str((paddle_visual_v as Dictionary).get("asset", "")))
					_add_warmup_path(target, str((paddle_visual_v as Dictionary).get("asset_anim", "")))
			var paddle_skin: String = str(enemy_overrides.get(paddle_enemy_id, ""))
			if paddle_skin != "":
				_add_warmup_path(target, paddle_skin)
			# Powerups pong : icônes, missiles, portails, briques du mur central.
			var pong_pool_v: Variant = wave.get("powerup_pool", pong_cfg.get("powerup_pool", []))
			if pong_pool_v is Array:
				for pong_powerup_v in (pong_pool_v as Array):
					if pong_powerup_v is Dictionary:
						_add_warmup_path(target, str((pong_powerup_v as Dictionary).get("asset", "")))
			for pong_asset_key in ["armed_missile_asset", "portal_entry_asset", "portal_exit_asset"]:
				_add_warmup_path(target, str(wave.get(pong_asset_key, pong_cfg.get(pong_asset_key, ""))))
			var pong_bricks_v: Variant = wave.get("wall_brick_assets", pong_cfg.get("wall_brick_assets", []))
			if pong_bricks_v is Array:
				for pong_brick_v in (pong_bricks_v as Array):
					_add_warmup_path(target, str(pong_brick_v))
			# Météore central : boss .tres tirés au sort (String ou {asset_anim}).
			var pong_meteors_v: Variant = wave.get("meteor_bosses", pong_cfg.get("meteor_bosses", []))
			if pong_meteors_v is Array:
				for pong_meteor_v in (pong_meteors_v as Array):
					if pong_meteor_v is Dictionary:
						_add_warmup_path(target, str((pong_meteor_v as Dictionary).get("asset_anim", "")))
					else:
						_add_warmup_path(target, str(pong_meteor_v))
			continue
		if wave_type == "asteroid_split":
			var ast_cfg: Dictionary = DataManager.get_wave_type_config("asteroid_split") if DataManager else {}
			var ast_assets_v: Variant = wave.get("assets", ast_cfg.get("assets", []))
			if ast_assets_v is Array:
				for asset_v in (ast_assets_v as Array):
					_add_warmup_path(target, str(asset_v))
			continue
		if wave_type == "breakout":
			var bk_cfg: Dictionary = DataManager.get_wave_type_config("breakout") if DataManager else {}
			_add_warmup_path(target, str(wave.get("ball_asset", bk_cfg.get("ball_asset", ""))))
			var bk_assets_v: Variant = wave.get("brick_assets", bk_cfg.get("brick_assets", []))
			if bk_assets_v is Array:
				for bk_asset_v in (bk_assets_v as Array):
					_add_warmup_path(target, str(bk_asset_v))
			# Bonus tombants : brique speciale + capsule par def du pool.
			var bk_pool_v: Variant = wave.get("bonus_pool", bk_cfg.get("bonus_pool", []))
			if bk_pool_v is Array:
				for bk_bonus_v in (bk_pool_v as Array):
					if bk_bonus_v is Dictionary:
						_add_warmup_path(target, str((bk_bonus_v as Dictionary).get("brick_asset", "")))
						_add_warmup_path(target, str((bk_bonus_v as Dictionary).get("drop_asset", "")))
			# Briques speciales, debris, missiles laser.
			for bk_asset_key in ["armored_brick_asset", "mystery_brick_asset", "bomb_brick_asset", "boss_brick_asset", "debris_asset", "laser_missile_asset"]:
				_add_warmup_path(target, str(wave.get(bk_asset_key, bk_cfg.get(bk_asset_key, ""))))
			continue
		if wave_type == "ball_launcher":
			var bl_cfg: Dictionary = DataManager.get_wave_type_config("ball_launcher") if DataManager else {}
			_add_warmup_path(target, str(wave.get("ball_asset", bl_cfg.get("ball_asset", ""))))
			var bl_blocks_v: Variant = wave.get("block_assets", bl_cfg.get("block_assets", []))
			if bl_blocks_v is Array:
				for bl_asset_v in (bl_blocks_v as Array):
					_add_warmup_path(target, str(bl_asset_v))
			var bl_tokens_v: Variant = wave.get("token_assets", bl_cfg.get("token_assets", []))
			if bl_tokens_v is Array:
				for bl_token_v in (bl_tokens_v as Array):
					_add_warmup_path(target, str(bl_token_v))
			# Nouveaux blocs spéciaux (bonus/malus) : un asset dédié par type.
			for bl_special_key in ["lightning_block_asset", "bomb_charge_block_asset", "aim_plus_block_asset", "giant_ball_block_asset", "healer_block_asset", "cursed_block_asset", "mover_block_asset", "armored_block_asset", "portal_in_block_asset", "portal_out_block_asset"]:
				_add_warmup_path(target, str(wave.get(bl_special_key, bl_cfg.get(bl_special_key, ""))))
			continue
		if wave_type == "suika_up":
			var su_cfg: Dictionary = DataManager.get_wave_type_config("suika_up") if DataManager else {}
			var su_levels_v: Variant = wave.get("levels", su_cfg.get("levels", {}))
			if su_levels_v is Dictionary:
				for su_level_v in (su_levels_v as Dictionary).values():
					if su_level_v is Dictionary:
						_add_warmup_path(target, str((su_level_v as Dictionary).get("asset", "")))
			var su_bombs_v: Variant = wave.get("boss_bomb_levels", su_cfg.get("boss_bomb_levels", {}))
			if su_bombs_v is Dictionary:
				for su_bomb_v in (su_bombs_v as Dictionary).values():
					if su_bomb_v is Dictionary:
						_add_warmup_path(target, str((su_bomb_v as Dictionary).get("asset", "")))
			var su_bosses_v: Variant = wave.get("bosses", su_cfg.get("bosses", []))
			if su_bosses_v is Array:
				for su_boss_v in (su_bosses_v as Array):
					if su_boss_v is Dictionary:
						_add_warmup_path(target, str((su_boss_v as Dictionary).get("asset_anim", "")))
			for su_asset_key in ["trajectory_dot_asset", "redline_asset", "reactor_frame_asset", "reactor_background_asset", "launcher_socket_asset", "power_gauge_asset", "merge_fx_anim",
				"prism_asset", "square_asset", "dark_asset", "discharge_icon_asset", "support_boss_asset_anim"]:
				_add_warmup_path(target, str(wave.get(su_asset_key, su_cfg.get(su_asset_key, ""))))
			# Pickups (améliorations 13 juillet 2026).
			var su_pickups_v: Variant = wave.get("pickup_types", su_cfg.get("pickup_types", []))
			if su_pickups_v is Array:
				for su_pickup_v in (su_pickups_v as Array):
					if su_pickup_v is Dictionary:
						_add_warmup_path(target, str((su_pickup_v as Dictionary).get("asset", "")))
			for su_expl_key in ["boss_hit_explosion", "boss_death_explosion"]:
				var su_expl_v: Variant = wave.get(su_expl_key, su_cfg.get(su_expl_key, {}))
				if su_expl_v is Dictionary:
					_add_warmup_path(target, str((su_expl_v as Dictionary).get("asset", "")))
					_add_warmup_path(target, str((su_expl_v as Dictionary).get("asset_anim", "")))
			continue
		if wave_type == "vertical_climb":
			var vc_cfg: Dictionary = DataManager.get_wave_type_config("vertical_climb") if DataManager else {}
			_add_warmup_path(target, str(vc_cfg.get("lava_asset", "")))
			_add_warmup_path(target, str(vc_cfg.get("crystal_asset", "")))
			var vc_assets_v: Variant = wave.get("platform_assets", vc_cfg.get("platform_assets", []))
			if vc_assets_v is Array:
				for vc_asset_v in (vc_assets_v as Array):
					_add_warmup_path(target, str(vc_asset_v))
			# Assets par type de plateforme + pickups/zone étoile (2026-07-12).
			for vc_asset_key in ["boost_platform_asset", "spring_platform_asset", "conveyor_platform_asset", "elevator_platform_asset", "multi_platform_asset", "jetpack_pickup_asset", "parachute_pickup_asset", "parachute_canopy_asset", "star_zone_asset"]:
				_add_warmup_path(target, str(wave.get(vc_asset_key, vc_cfg.get(vc_asset_key, ""))))
			continue
		if wave_type == "lane_runner":
			var lr_cfg: Dictionary = DataManager.get_wave_type_config("lane_runner") if DataManager else {}
			var lr_wall_assets_v: Variant = wave.get("wall_assets", lr_cfg.get("wall_assets", []))
			if lr_wall_assets_v is Array:
				for lr_asset_v in (lr_wall_assets_v as Array):
					_add_warmup_path(target, str(lr_asset_v))
			var lr_col_assets_v: Variant = wave.get("collectible_assets", lr_cfg.get("collectible_assets", []))
			if lr_col_assets_v is Array:
				for lr_col_v in (lr_col_assets_v as Array):
					_add_warmup_path(target, str(lr_col_v))
			# Pickups spéciaux, portails, pièce géante, tourelle au sol (2026-07-12).
			for lr_key in ["portal_entry_asset", "portal_exit_asset", "ram_pickup_asset", "pew_pickup_asset", "ghost_pickup_asset", "magnet_pickup_asset", "coin_x2_pickup_asset", "turbo_pickup_asset", "freeze_pickup_asset", "giant_coin_asset", "ground_turret_asset"]:
				_add_warmup_path(target, str(wave.get(lr_key, lr_cfg.get(lr_key, ""))))
			# World obstacle skins can replace the wall assets at runtime.
			var lr_obs_overrides_v: Variant = _skin_overrides.get("obstacles", {})
			if lr_obs_overrides_v is Dictionary:
				var lr_explosives_v: Variant = (lr_obs_overrides_v as Dictionary).get("explosives", [])
				if lr_explosives_v is Array:
					for lr_skin_v in (lr_explosives_v as Array):
						_add_warmup_path(target, str(lr_skin_v))
			continue
		if wave_type == "slice_rush":
			var sr_cfg: Dictionary = DataManager.get_wave_type_config("slice_rush") if DataManager else {}
			var sr_types_v: Variant = wave.get("object_types", sr_cfg.get("object_types", []))
			if sr_types_v is Array:
				for sr_type_v in (sr_types_v as Array):
					if not (sr_type_v is Dictionary):
						continue
					var sr_assets_v: Variant = (sr_type_v as Dictionary).get("assets", [])
					if sr_assets_v is Array:
						for sr_asset_v in (sr_assets_v as Array):
							_add_warmup_path(target, str(sr_asset_v))
			var sr_bomb_assets_v: Variant = wave.get("bomb_assets", sr_cfg.get("bomb_assets", []))
			if sr_bomb_assets_v is Array:
				for sr_bomb_v in (sr_bomb_assets_v as Array):
					_add_warmup_path(target, str(sr_bomb_v))
			_add_warmup_path(target, str(wave.get("bomb_aura_asset", sr_cfg.get("bomb_aura_asset", ""))))
			_add_warmup_path(target, str(wave.get("slice_effect_anim", sr_cfg.get("slice_effect_anim", ""))))
			_add_warmup_path(target, str(wave.get("explosion_anim", sr_cfg.get("explosion_anim", ""))))
			# Bonus tranchables, leurres, pinata, overlay blindé (2026-07-12).
			for sr_key in ["hourglass_asset", "freeze_glove_asset", "chronos_asset", "laser_ext_asset", "armored_overlay_asset", "pinata_asset"]:
				_add_warmup_path(target, str(wave.get(sr_key, sr_cfg.get(sr_key, ""))))
			var sr_decoy_assets_v: Variant = wave.get("decoy_bomb_assets", sr_cfg.get("decoy_bomb_assets", []))
			if sr_decoy_assets_v is Array:
				for sr_decoy_v in (sr_decoy_assets_v as Array):
					_add_warmup_path(target, str(sr_decoy_v))
			# World obstacle skins can replace object textures at runtime.
			var sr_obs_overrides_v: Variant = _skin_overrides.get("obstacles", {})
			if sr_obs_overrides_v is Dictionary:
				var sr_explosives_v: Variant = (sr_obs_overrides_v as Dictionary).get("explosives", [])
				if sr_explosives_v is Array:
					for sr_skin_v in (sr_explosives_v as Array):
						_add_warmup_path(target, str(sr_skin_v))
			continue
		if wave_type == "match3":
			var m3_cfg: Dictionary = DataManager.get_wave_type_config("match3") if DataManager else {}
			var m3_sets_v: Variant = wave.get("tile_sets", m3_cfg.get("tile_sets", []))
			if m3_sets_v is Array:
				for m3_set_v in (m3_sets_v as Array):
					if not (m3_set_v is Dictionary):
						continue
					_add_warmup_path(target, str((m3_set_v as Dictionary).get("normal", "")))
					_add_warmup_path(target, str((m3_set_v as Dictionary).get("special", "")))
			_add_warmup_path(target, str(wave.get("explosion_anim", m3_cfg.get("explosion_anim", ""))))
			_add_warmup_path(target, str(wave.get("glow_asset", m3_cfg.get("glow_asset", ""))))
			_add_warmup_path(target, str(wave.get("special_aura_asset", m3_cfg.get("special_aura_asset", ""))))
			# Boss (anims .tres), icônes consommables, overlays variantes (2026-07-12).
			var m3_bosses_v: Variant = wave.get("bosses", m3_cfg.get("bosses", []))
			if m3_bosses_v is Array:
				for m3_boss_v in (m3_bosses_v as Array):
					if m3_boss_v is Dictionary:
						_add_warmup_path(target, str((m3_boss_v as Dictionary).get("asset_anim", "")))
			for m3_key in ["boss_death_explosion", "paint_icon_asset", "frost_overlay_asset", "cage_overlay_asset", "timebomb_overlay_asset", "anchor_tile_asset", "joker_drone_asset"]:
				_add_warmup_path(target, str(wave.get(m3_key, m3_cfg.get(m3_key, ""))))
			continue
		if wave_type == "gravity_hole":
			var gh_cfg: Dictionary = DataManager.get_wave_type_config("gravity_hole") if DataManager else {}
			_add_warmup_path(target, str(wave.get("transition_asset", gh_cfg.get("transition_asset", ""))))
			_add_warmup_path(target, str(wave.get("aura_asset", gh_cfg.get("aura_asset", ""))))
			# All candidate dimension backgrounds: loading a full-screen JPG at
			# the cover frame would hitch, so warm every possible pick.
			var gh_bgs_v: Variant = wave.get("bg_assets", gh_cfg.get("bg_assets", []))
			if gh_bgs_v is Array:
				for gh_bg_v in (gh_bgs_v as Array):
					_add_warmup_path(target, str(gh_bg_v))
			var gh_props_v: Variant = wave.get("props", gh_cfg.get("props", []))
			if gh_props_v is Array:
				for gh_prop_v in (gh_props_v as Array):
					if gh_prop_v is Dictionary:
						var gh_prop_assets_v: Variant = (gh_prop_v as Dictionary).get("assets", [])
						if gh_prop_assets_v is Array:
							for gh_asset_v in (gh_prop_assets_v as Array):
								_add_warmup_path(target, str(gh_asset_v))
			var gh_wave_assets_v: Variant = wave.get("prop_assets", [])
			if gh_wave_assets_v is Array:
				for gh_wa_v in (gh_wave_assets_v as Array):
					_add_warmup_path(target, str(gh_wa_v))
			var gh_core_assets_v: Variant = wave.get("final_core_assets", gh_cfg.get("final_core_assets", []))
			if gh_core_assets_v is Array:
				for gh_core_v in (gh_core_assets_v as Array):
					_add_warmup_path(target, str(gh_core_v))
			# Refonte Agar.io (2026-07-13) : géants, pickups, flèche, zones, rival, comète, dimension.
			var gh_giants_v: Variant = wave.get("giants", gh_cfg.get("giants", []))
			if gh_giants_v is Array:
				for gh_giant_v in (gh_giants_v as Array):
					if gh_giant_v is Dictionary:
						var gh_giant_assets_v: Variant = (gh_giant_v as Dictionary).get("assets", [])
						if gh_giant_assets_v is Array:
							for gh_ga_v in (gh_giant_assets_v as Array):
								_add_warmup_path(target, str(gh_ga_v))
			var gh_comet_assets_v: Variant = wave.get("comet_assets", gh_cfg.get("comet_assets", []))
			if gh_comet_assets_v is Array:
				for gh_ca_v in (gh_comet_assets_v as Array):
					_add_warmup_path(target, str(gh_ca_v))
			for gh_key in ["target_arrow_asset", "magnet_pickup_asset", "compass_pickup_asset", "overdrive_pickup_asset", "companion_pickup_asset", "stabilizer_pickup_asset", "companion_asset", "electric_zone_asset", "rival_vortex_asset", "bonus_bg_asset"]:
				_add_warmup_path(target, str(wave.get(gh_key, gh_cfg.get(gh_key, ""))))
			# World obstacle skins can replace prop textures at runtime.
			var gh_obs_overrides_v: Variant = _skin_overrides.get("obstacles", {})
			if gh_obs_overrides_v is Dictionary:
				var gh_explosives_v: Variant = (gh_obs_overrides_v as Dictionary).get("explosives", [])
				if gh_explosives_v is Array:
					for gh_skin_v in (gh_explosives_v as Array):
						_add_warmup_path(target, str(gh_skin_v))
			continue
		if wave_type == "star_drift":
			var sd_cfg: Dictionary = DataManager.get_wave_type_config("star_drift") if DataManager else {}
			var sd_hazards_v: Variant = wave.get("hazard_types", sd_cfg.get("hazard_types", []))
			if sd_hazards_v is Array:
				for sd_hazard_v in (sd_hazards_v as Array):
					if not (sd_hazard_v is Dictionary):
						continue
					var sd_hz_assets_v: Variant = (sd_hazard_v as Dictionary).get("assets", [])
					if sd_hz_assets_v is Array:
						for sd_hz_asset_v in (sd_hz_assets_v as Array):
							_add_warmup_path(target, str(sd_hz_asset_v))
			var sd_tiers_v: Variant = wave.get("pickup_tiers", sd_cfg.get("pickup_tiers", []))
			if sd_tiers_v is Array:
				for sd_tier_v in (sd_tiers_v as Array):
					if not (sd_tier_v is Dictionary):
						continue
					var sd_tier_assets_v: Variant = (sd_tier_v as Dictionary).get("assets", [])
					if sd_tier_assets_v is Array:
						for sd_tier_asset_v in (sd_tier_assets_v as Array):
							_add_warmup_path(target, str(sd_tier_asset_v))
			# Powerups, mine et étoile de constellation (refonte 13 juillet 2026).
			var sd_powerups_v: Variant = wave.get("powerup_types", sd_cfg.get("powerup_types", []))
			if sd_powerups_v is Array:
				for sd_pw_v in (sd_powerups_v as Array):
					if not (sd_pw_v is Dictionary):
						continue
					var sd_pw_assets_v: Variant = (sd_pw_v as Dictionary).get("assets", [])
					if sd_pw_assets_v is Array:
						for sd_pw_asset_v in (sd_pw_assets_v as Array):
							_add_warmup_path(target, str(sd_pw_asset_v))
			_add_warmup_path(target, str(wave.get("mine_asset", sd_cfg.get("mine_asset", ""))))
			_add_warmup_path(target, str(wave.get("constellation_star_asset", sd_cfg.get("constellation_star_asset", ""))))
			# World obstacle skins feed the meteors (use_world_obstacles).
			var sd_obs_overrides_v: Variant = _skin_overrides.get("obstacles", {})
			if sd_obs_overrides_v is Dictionary:
				var sd_explosives_v: Variant = (sd_obs_overrides_v as Dictionary).get("explosives", [])
				if sd_explosives_v is Array:
					for sd_skin_v in (sd_explosives_v as Array):
						_add_warmup_path(target, str(sd_skin_v))
			continue
		if wave_type == "absorb":
			var ab_cfg: Dictionary = DataManager.get_wave_type_config("absorb") if DataManager else {}
			var ab_assets_v: Variant = wave.get("prey_assets", ab_cfg.get("prey_assets", []))
			if ab_assets_v is Array:
				for ab_asset_v in (ab_assets_v as Array):
					_add_warmup_path(target, str(ab_asset_v))
			var ab_enemy_id: String = str(ab_cfg.get("enemy_visual_enemy_id", "fighter"))
			var ab_enemy: Dictionary = DataManager.get_enemy(ab_enemy_id)
			if not ab_enemy.is_empty():
				var ab_visual_v: Variant = ab_enemy.get("visual", {})
				if ab_visual_v is Dictionary:
					_add_warmup_path(target, str((ab_visual_v as Dictionary).get("asset", "")))
					_add_warmup_path(target, str((ab_visual_v as Dictionary).get("asset_anim", "")))
			var ab_skin: String = str(enemy_overrides.get(ab_enemy_id, ""))
			if ab_skin != "":
				_add_warmup_path(target, ab_skin)
			# Arène + pickups + types spéciaux (2026-07-12).
			var ab_arena_v: Variant = wave.get("arena_backgrounds", ab_cfg.get("arena_backgrounds", []))
			if ab_arena_v is Array:
				for ab_arena_bg_v in (ab_arena_v as Array):
					_add_warmup_path(target, str(ab_arena_bg_v))
			for ab_asset_key in ["decoy_pickup_asset", "freeze_pickup_asset", "overcharge_pickup_asset", "crystallize_pickup_asset", "repulse_pickup_asset", "toxic_prey_asset", "predator_asset", "golden_prey_asset", "devourer_asset"]:
				_add_warmup_path(target, str(wave.get(ab_asset_key, ab_cfg.get(ab_asset_key, ""))))
			continue

		var enemy_id: String = str(wave.get("enemy_id", ""))
		if enemy_id == "":
			continue

		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
		if enemy_data.is_empty():
			continue

		var visual_variant: Variant = enemy_data.get("visual", {})
		if visual_variant is Dictionary:
			var visual: Dictionary = visual_variant as Dictionary
			_add_warmup_path(target, str(visual.get("asset", "")))
			_add_warmup_path(target, str(visual.get("asset_anim", "")))
			_add_warmup_path(target, str(visual.get("on_death_asset", "")))
			_add_warmup_path(target, str(visual.get("on_death_asset_anim", "")))

		var missile_id: String = str(enemy_data.get("missile_id", ""))
		if missile_id != "":
			var missile_data: Dictionary = DataManager.get_missile(missile_id)
			if not missile_data.is_empty():
				var missile_visual_variant: Variant = missile_data.get("visual", {})
				if missile_visual_variant is Dictionary:
					var missile_visual: Dictionary = missile_visual_variant as Dictionary
					_add_warmup_path(target, str(missile_visual.get("asset", "")))
					_add_warmup_path(target, str(missile_visual.get("asset_anim", "")))

				_add_warmup_path(target, str(missile_data.get("sound", "")))

				var explosion_variant: Variant = missile_data.get("explosion", {})
				var explosion_data: Dictionary = {}
				if explosion_variant is Dictionary and not (explosion_variant as Dictionary).is_empty():
					explosion_data = explosion_variant as Dictionary
				else:
					explosion_data = DataManager.get_default_explosion()
				_add_warmup_path(target, str(explosion_data.get("asset", "")))
				_add_warmup_path(target, str(explosion_data.get("asset_anim", "")))

		var skin_override: String = str(enemy_overrides.get(enemy_id, ""))
		if skin_override != "":
			_add_warmup_path(target, skin_override)
		else:
			_add_warmup_path(target, str(wave.get("enemy_skin", "")))

func _collect_move_pattern_resources(target: Dictionary) -> void:
	var all_patterns: Array = DataManager.get_all_move_patterns()
	for pattern_variant in all_patterns:
		if not (pattern_variant is Dictionary):
			continue
		var pattern: Dictionary = pattern_variant as Dictionary
		var res_path: String = str(pattern.get("path", pattern.get("resource", "")))
		_add_warmup_path(target, res_path)

func _add_warmup_path(target: Dictionary, path: String) -> void:
	if path == "":
		return
	target[path] = true
