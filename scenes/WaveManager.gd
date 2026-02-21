extends Node

## WaveManager — Gère le spawn des vagues d'ennemis et d'obstacles.
## Lit les données de niveau et instancie les ennemis/obstacles via Game.gd.

signal spawn_enemy(enemy_data: Dictionary, spawn_pos: Vector2)
signal spawn_obstacle(obstacle_data: Dictionary, positions: Array, speed: float)
signal level_completed
signal wave_started(wave_index: int)

const ObstacleSpawnerScript: Script = preload("res://scenes/obstacles/ObstacleSpawner.gd")

var _current_level_data: Dictionary = {}
var _waves: Array = []
var _current_wave_index: int = 0
var _level_time: float = 0.0
var _is_active: bool = false
var _pending_spawns: Array = [] # {time, enemy_id, pattern_id}
var _available_move_pattern_ids: Array[String] = []
var _active_obstacle_spawners: Array = [] # Active ObstacleSpawner nodes
var _skin_overrides: Dictionary = {} # World-level skin overrides
var _enemy_skin_type_cache: Dictionary = {} # skin_path -> "frames" | "texture" | "unknown"

const DEFAULT_MOVE_PATTERN_ID := "linear_cross_fast"
const DEBUG_WAVE_PATTERN_LOG := false
const DEBUG_WAVE_LIFECYCLE_LOG := false
const DEBUG_RESOURCE_WARMUP_LOG := true
const DEBUG_SPAWN_COST_LOG := false
const DEBUG_SPAWN_COST_THRESHOLD_MS := 4.0
const MAX_ENEMY_SPAWNS_PER_FRAME: int = 2

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
	
	_waves = _current_level_data.get("waves", [])
	_current_wave_index = 0
	_level_time = 0.0
	_pending_spawns.clear()
	_enemy_skin_type_cache.clear()
	_refresh_move_pattern_pool()
	_prewarm_wave_resources()
	_is_active = true
	
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Setup level: ", level_id, " with ", _waves.size(), " waves. Skin overrides: ", _skin_overrides.keys())

func stop() -> void:
	_is_active = false
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
	
	_level_time += delta
	_check_waves()
	_process_pending_spawns(delta)

func _check_waves() -> void:
	if _current_wave_index >= _waves.size():
		# Plus de vagues à lancer, attendre que tout soit clean ? 
		# Pour l'instant on considère le niveau fini quand le temps dépasse la dernière vague + marge
		var all_spawners_done := true
		for spawner in _active_obstacle_spawners:
			if is_instance_valid(spawner):
				all_spawners_done = false
				break
		if _pending_spawns.is_empty() and all_spawners_done and _level_time > _get_last_wave_time() + 10.0:
			if _is_active:
				_is_active = false
				level_completed.emit()
		return

	var next_wave: Dictionary = _waves[_current_wave_index]
	var wave_time: float = float(next_wave.get("time", 0.0))
	
	if _level_time >= wave_time:
		_start_wave(next_wave)
		_current_wave_index += 1
		# Check recursivement si plusieurs vagues ont le même temps
		_check_waves()

func _get_last_wave_time() -> float:
	if _waves.is_empty(): return 0.0
	return float(_waves.back().get("time", 0.0))

func _start_wave(wave: Dictionary) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Starting wave at time: ", wave.get("time"))
	wave_started.emit(_current_wave_index)
	
	var wave_type: String = str(wave.get("type", "enemy"))
	
	match wave_type:
		"obstacle":
			_start_obstacle_wave(wave)
		_:
			_start_enemy_wave(wave)

	if DEBUG_SPAWN_COST_LOG:
		var wave_cost_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		if wave_cost_ms >= DEBUG_SPAWN_COST_THRESHOLD_MS:
			print("[WavePerf] wave_start cost=", snappedf(wave_cost_ms, 0.1), "ms type=", wave_type, " idx=", _current_wave_index)

func _start_enemy_wave(wave: Dictionary) -> void:
	var enemy_id: String = str(wave.get("enemy_id", "enemy_basic"))
	var count: int = int(wave.get("count", 1))
	var interval: float = float(wave.get("interval", 1.0))
	var pattern_id: String = _pick_random_move_pattern_id()
	
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
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": enemy_id,
			"pattern_id": pattern_id,
			"modifier_id": modifier_id,
			"enemy_skin": enemy_skin
		})

func _start_obstacle_wave(wave: Dictionary) -> void:
	var spawner_node: Node = ObstacleSpawnerScript.new()
	spawner_node.name = "ObstacleSpawner_" + str(_current_wave_index)
	add_child(spawner_node)
	
	spawner_node.setup(wave)
	spawner_node.obstacle_spawn_request.connect(_on_obstacle_spawn_request)
	spawner_node.finished.connect(_on_obstacle_spawner_finished.bind(spawner_node))
	_active_obstacle_spawners.append(spawner_node)
	
	if DEBUG_WAVE_LIFECYCLE_LOG:
		print("[WaveManager] Obstacle wave started: pattern=", wave.get("pattern"),
			" obstacle=", wave.get("obstacle_id"))

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
		if str(wave.get("type", "enemy")) == "obstacle":
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
