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

const DEFAULT_MOVE_PATTERN_ID := "linear_cross_fast"
const DEBUG_WAVE_PATTERN_LOG := true

func setup(level_id: String) -> void:
	_current_level_data = DataManager.get_level_data(level_id)
	if _current_level_data.is_empty():
		push_warning("[WaveManager] Level data not found: " + level_id)
		return
	
	_waves = _current_level_data.get("waves", [])
	_current_wave_index = 0
	_level_time = 0.0
	_pending_spawns.clear()
	_refresh_move_pattern_pool()
	_is_active = true
	
	print("[WaveManager] Setup level: ", level_id, " with ", _waves.size(), " waves.")

func stop() -> void:
	_is_active = false
	_pending_spawns.clear()
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
	print("[WaveManager] Starting wave at time: ", wave.get("time"))
	wave_started.emit(_current_wave_index)
	
	var wave_type: String = str(wave.get("type", "enemy"))
	
	match wave_type:
		"obstacle":
			_start_obstacle_wave(wave)
		_:
			_start_enemy_wave(wave)

func _start_enemy_wave(wave: Dictionary) -> void:
	var enemy_id: String = str(wave.get("enemy_id", "enemy_basic"))
	var count: int = int(wave.get("count", 1))
	var interval: float = float(wave.get("interval", 1.0))
	var pattern_id: String = _pick_random_move_pattern_id()
	if DEBUG_WAVE_PATTERN_LOG:
		print("[WaveManager] Wave ", _current_wave_index, " enemy=", enemy_id, " random_pattern=", pattern_id)
	
	# Optional modifier
	var modifier_id: String = str(wave.get("enemy_modifier_id", ""))
	
	# Ajouter les spawns prévus avec leur délai
	for i in range(count):
		var spawn_delay: float = i * interval
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": enemy_id,
			"pattern_id": pattern_id,
			"modifier_id": modifier_id
		})

func _start_obstacle_wave(wave: Dictionary) -> void:
	var spawner_node: Node = ObstacleSpawnerScript.new()
	spawner_node.name = "ObstacleSpawner_" + str(_current_wave_index)
	add_child(spawner_node)
	
	spawner_node.setup(wave)
	spawner_node.obstacle_spawn_request.connect(_on_obstacle_spawn_request)
	spawner_node.finished.connect(_on_obstacle_spawner_finished.bind(spawner_node))
	_active_obstacle_spawners.append(spawner_node)
	
	print("[WaveManager] Obstacle wave started: pattern=", wave.get("pattern"),
		" obstacle=", wave.get("obstacle_id"))

func _on_obstacle_spawn_request(obstacle_data: Dictionary, positions: Array, speed: float) -> void:
	spawn_obstacle.emit(obstacle_data, positions, speed)

func _on_obstacle_spawner_finished(spawner: Node) -> void:
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
	for i in range(_pending_spawns.size() - 1, -1, -1):
		var spawn: Dictionary = _pending_spawns[i]
		spawn["delay"] -= delta
		
		if spawn["delay"] <= 0:
			_trigger_spawn(spawn)
			_pending_spawns.remove_at(i)

func _trigger_spawn(spawn_info: Dictionary) -> void:
	var enemy_id: String = str(spawn_info.get("enemy_id", ""))
	var enemy_data := DataManager.get_enemy(enemy_id).duplicate()
	if enemy_data.is_empty():
		push_warning("[WaveManager] Unknown enemy_id in wave: " + enemy_id)
		return
		
	# Override pattern si défini dans la vague
	if spawn_info["pattern_id"] != "":
		enemy_data["move_pattern_id"] = spawn_info["pattern_id"]
		
	# Inject modifier if present
	if spawn_info.get("modifier_id", "") != "":
		enemy_data["modifier_id"] = spawn_info["modifier_id"]

	# Spawn position is now randomized per enemy spawn.
	var spawn_pos: Vector2 = _get_random_spawn_position()

	spawn_enemy.emit(enemy_data, spawn_pos)
