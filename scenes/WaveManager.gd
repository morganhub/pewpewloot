extends Node

## WaveManager — Gère le spawn des vagues d'ennemis et d'obstacles.
## Lit les données de niveau et instancie les ennemis/obstacles via Game.gd.

signal spawn_enemy(enemy_data: Dictionary, spawn_pos: Vector2)
signal spawn_obstacle(obstacle_data: Dictionary, positions: Array, speed: float)
signal spawn_path_trial(config: Dictionary)
signal level_completed
signal wave_started(wave_index: int)
signal story_check_before_wave(wave_index: int)

const ObstacleSpawnerScript: Script = preload("res://scenes/obstacles/ObstacleSpawner.gd")

var _current_level_data: Dictionary = {}
var _waves: Array = []
var _current_wave_index: int = 0
var _pending_wave_index: int = -1
var _is_active: bool = false
var _is_wave_running: bool = false
var _current_wave_elapsed: float = 0.0
var _current_wave_duration: float = 20.0
var _pending_spawns: Array = [] # {time, enemy_id, pattern_id}
var _available_move_pattern_ids: Array[String] = []
var _active_obstacle_spawners: Array = [] # Active ObstacleSpawner nodes
var _skin_overrides: Dictionary = {} # World-level skin overrides
var _world_wave_runtime_cfg: Dictionary = {}
var _enemy_skin_type_cache: Dictionary = {} # skin_path -> "frames" | "texture" | "unknown"
var _override_elite_replacement_chance: float = 0.0
var _world_id: String = ""

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
	_current_wave_index = 0
	_current_wave_elapsed = 0.0
	_current_wave_duration = 20.0
	_is_wave_running = false
	_pending_wave_index = -1
	_pending_spawns.clear()
	_enemy_skin_type_cache.clear()
	_refresh_move_pattern_pool()
	_prewarm_wave_resources()
	_is_active = true

	if _waves.is_empty():
		_is_active = false
		level_completed.emit()
		return
	_queue_wave_start(_current_wave_index)
	
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Setup level: ", level_id, " with ", _waves.size(), " waves. Skin overrides: ", _skin_overrides.keys())

func set_override_elite_replacement_chance(chance: float) -> void:
	_override_elite_replacement_chance = clampf(chance, 0.0, 1.0)

func stop() -> void:
	_is_active = false
	_is_wave_running = false
	_current_wave_elapsed = 0.0
	_pending_wave_index = -1
	_pending_spawns.clear()
	_enemy_skin_type_cache.clear()
	# Arrêter tous les spawners d'obstacles actifs
	for spawner in _active_obstacle_spawners:
		if is_instance_valid(spawner):
			spawner.stop()
			spawner.queue_free()
	_active_obstacle_spawners.clear()

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_process_pending_spawns(delta)
	if not _is_wave_running:
		return
	# Prevent a single long frame from skipping almost a full wave (and its spawns).
	_current_wave_elapsed += minf(delta, MAX_WAVE_ELAPSED_STEP_SEC)
	if _current_wave_elapsed >= _current_wave_duration:
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
		_is_active = false
		level_completed.emit()
		return
	_current_wave_index = next_wave_index
	_queue_wave_start(_current_wave_index)

func _start_wave_end_enemy_flyoff() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("start_wave_end_flyoff"):
			# Arc 180°: left-mid -> top -> right-mid (never downward).
			var angle: float = randf_range(PI, TAU)
			var dir: Vector2 = Vector2(cos(angle), sin(angle)).normalized()
			var speed: float = randf_range(WAVE_END_FLYOFF_MIN_SPEED, WAVE_END_FLYOFF_MAX_SPEED)
			enemy.call("start_wave_end_flyoff", dir, speed, WAVE_END_FLYOFF_DURATION_SEC)
		else:
			enemy.queue_free()

func _start_wave(wave: Dictionary) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Starting wave idx: ", _current_wave_index)
	wave_started.emit(_current_wave_index)
	
	_pending_spawns.clear()
	_current_wave_duration = maxf(0.1, _resolve_wave_duration(wave))
	_current_wave_elapsed = 0.0
	_is_wave_running = true

	var wave_type: String = str(wave.get("type", "enemy"))
	
	match wave_type:
		"obstacle":
			_start_obstacle_wave(wave)
		"path_trial":
			_start_path_trial_wave(wave)
		_:
			_start_enemy_wave(wave)

	if DEBUG_SPAWN_COST_LOG:
		var wave_cost_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		if wave_cost_ms >= DEBUG_SPAWN_COST_THRESHOLD_MS:
			print("[WavePerf] wave_start cost=", snappedf(wave_cost_ms, 0.1), "ms type=", wave_type, " idx=", _current_wave_index)

func _resolve_wave_duration(wave: Dictionary) -> float:
	var duration: float = _resolve_base_wave_duration(wave)
	var forced_duration: float = float(_world_wave_runtime_cfg.get("force_duration_sec", -1.0))
	if forced_duration > 0.0:
		duration = forced_duration
	if str(wave.get("type", "enemy")) == "path_trial":
		duration += _resolve_path_trial_start_delay(wave)
	return maxf(0.1, duration)

func _resolve_base_wave_duration(wave: Dictionary) -> float:
	return maxf(0.1, float(wave.get("duration", 20.0)))

func _resolve_path_trial_start_delay(wave: Dictionary) -> float:
	var defaults: Dictionary = DataManager.get_path_trial_defaults() if DataManager else {}
	return maxf(
		0.0,
		float(
			wave.get(
				"start_delay_sec",
				wave.get(
					"warmup_sec",
					defaults.get("start_delay_sec", defaults.get("warmup_sec", 1.5))
				)
			)
		)
	)

func _start_enemy_wave(wave: Dictionary) -> void:
	var enemy_id: String = str(wave.get("enemy_id", "enemy_basic"))
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
		var spawn_enemy_id: String = enemy_id
		if enemy_id != "elite" and _override_elite_replacement_chance > 0.0:
			if randf() <= _override_elite_replacement_chance and not DataManager.get_enemy("elite").is_empty():
				spawn_enemy_id = "elite"
		var spawn_skin: String = enemy_skin
		if spawn_enemy_id != enemy_id:
			spawn_skin = _resolve_enemy_skin_for_id(spawn_enemy_id)
		var spawn_delay: float = i * interval
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": spawn_enemy_id,
			"pattern_id": pattern_id,
			"modifier_id": modifier_id,
			"enemy_skin": spawn_skin
		})

func _resolve_enemy_spawn_count(interval: float) -> int:
	var safe_interval: float = maxf(0.05, interval)
	var count: int = maxi(1, int(ceil(_current_wave_duration / safe_interval)))
	var max_count: int = maxi(1, int(_world_wave_runtime_cfg.get("enemy_max_spawns_per_wave", 160)))
	return mini(count, max_count)

func _resolve_enemy_spawn_interval(base_interval: float) -> float:
	return clampf(maxf(0.05, base_interval), 0.05, _current_wave_duration)

func _resolve_default_enemy_interval() -> float:
	return maxf(0.05, float(_world_wave_runtime_cfg.get("enemy_target_interval_sec", 1.0)))

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
	spawner_node.setup(payload)
	spawner_node.obstacle_spawn_request.connect(_on_obstacle_spawn_request)
	spawner_node.finished.connect(_on_obstacle_spawner_finished.bind(spawner_node))
	_active_obstacle_spawners.append(spawner_node)
	
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Obstacle wave started: pattern=", wave.get("pattern"),
			" obstacle=", wave.get("obstacle_id"))

func _start_path_trial_wave(wave: Dictionary) -> void:
	var payload: Dictionary = wave.duplicate(true)
	if not payload.has("duration"):
		var pattern_duration: float = _resolve_base_wave_duration(wave)
		var forced_duration: float = float(_world_wave_runtime_cfg.get("force_duration_sec", -1.0))
		if forced_duration > 0.0:
			pattern_duration = forced_duration
		payload["duration"] = maxf(0.1, pattern_duration)
	if not payload.has("start_delay_sec"):
		payload["start_delay_sec"] = _resolve_path_trial_start_delay(wave)
	var pattern_id: String = str(payload.get("pattern_id", "")).strip_edges()
	if pattern_id != "":
		var pattern_data: Dictionary = DataManager.get_move_pattern(pattern_id)
		if not pattern_data.is_empty():
			payload["pattern_data"] = pattern_data.duplicate(true)
	payload["wave_index"] = _current_wave_index
	spawn_path_trial.emit(payload)

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
		push_warning("[WaveManager] Unknown enemy_id in wave: " + enemy_id)
		return
		
	# Override pattern si défini dans la vague
	if spawn_info["pattern_id"] != "":
		enemy_data["move_pattern_id"] = spawn_info["pattern_id"]
		enemy_data["_move_pattern_data"] = DataManager.get_move_pattern(str(spawn_info["pattern_id"]))
		
	# Inject modifier if present
	if spawn_info.get("modifier_id", "") != "":
		enemy_data["modifier_id"] = spawn_info["modifier_id"]

	# Optional visual override per wave.
	var enemy_skin: String = str(spawn_info.get("enemy_skin", ""))
	_apply_enemy_skin_override(enemy_data, enemy_skin)

	# Spawn position is now randomized per enemy spawn.
	var spawn_pos: Vector2 = _get_random_spawn_position()

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
	_collect_move_pattern_resources(seen_paths)

	for path_variant in seen_paths.keys():
		var path: String = str(path_variant)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var was_cached: bool = ResourceLoader.has_cached(path)
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if DEBUG_RESOURCE_WARMUP_LOG:
			print("[WaveManager] Warmup ", ("reused " if was_cached else "loaded "), path)

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
		if wave_type == "path_trial":
			_add_warmup_path(target, str(wave.get("hazard_asset_override", "")))
			_add_warmup_path(target, str(wave.get("hazard_start_asset_override", "")))
			_add_warmup_path(target, str(wave.get("path_asset_override", "")))
			var defaults: Dictionary = DataManager.get_path_trial_defaults() if DataManager else {}
			_add_warmup_path(target, str(defaults.get("default_hazard_asset", "")))
			_add_warmup_path(target, str(defaults.get("default_hazard_start_asset", "")))
			_add_warmup_path(target, str(defaults.get("default_path_asset", "")))
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
