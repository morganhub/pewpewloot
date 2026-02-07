extends Node

## WaveManager — Gère le spawn des vagues d'ennemis.
## Lit les données de niveau et instancie les ennemis via Game.gd.

signal spawn_enemy(enemy_data: Dictionary, spawn_pos: Vector2)
signal level_completed
signal wave_started(wave_index: int)

var _current_level_data: Dictionary = {}
var _waves: Array = []
var _current_wave_index: int = 0
var _level_time: float = 0.0
var _is_active: bool = false
var _pending_spawns: Array = [] # {time, enemy_id, pattern_id}

func setup(level_id: String) -> void:
	_current_level_data = DataManager.get_level_data(level_id)
	if _current_level_data.is_empty():
		push_warning("[WaveManager] Level data not found: " + level_id)
		return
	
	_waves = _current_level_data.get("waves", [])
	_current_wave_index = 0
	_level_time = 0.0
	_pending_spawns.clear()
	_is_active = true
	
	print("[WaveManager] Setup level: ", level_id, " with ", _waves.size(), " waves.")

func stop() -> void:
	_is_active = false
	_pending_spawns.clear()

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
		if _pending_spawns.is_empty() and _level_time > _get_last_wave_time() + 10.0:
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
	
	var enemy_id: String = str(wave.get("enemy_id", "enemy_basic"))
	var count: int = int(wave.get("count", 1))
	var interval: float = float(wave.get("interval", 1.0))
	var pattern_id: String = str(wave.get("pattern_id", "straight_down"))
	
	# Ajouter les spawns prévus avec leur délai
	for i in range(count):
		var spawn_delay: float = i * interval
		_pending_spawns.append({
			"delay": spawn_delay,
			"enemy_id": enemy_id,
			"pattern_id": pattern_id,
			"origin_x": wave.get("origin_x", "50%"),
			"origin_y": wave.get("origin_y", -50)
		})

func _process_pending_spawns(delta: float) -> void:
	for i in range(_pending_spawns.size() - 1, -1, -1):
		var spawn: Dictionary = _pending_spawns[i]
		spawn["delay"] -= delta
		
		if spawn["delay"] <= 0:
			_trigger_spawn(spawn)
			_pending_spawns.remove_at(i)

func _trigger_spawn(spawn_info: Dictionary) -> void:
	var enemy_data := DataManager.get_enemy(spawn_info["enemy_id"]).duplicate()
	if enemy_data.is_empty():
		return
		
	# Override pattern si défini dans la vague
	if spawn_info["pattern_id"] != "":
		enemy_data["move_pattern_id"] = spawn_info["pattern_id"]

	# Calculer la position de spawn
	var viewport_size := get_viewport().get_visible_rect().size
	var spawn_pos := Vector2.ZERO
	
	# X
	var ox = spawn_info.get("origin_x", "50%")
	if ox is String and ox == "random":
		spawn_pos.x = randf_range(50, viewport_size.x - 50)
	elif ox is String and ox.ends_with("%"):
		var pct := float(ox.replace("%", "")) / 100.0
		spawn_pos.x = viewport_size.x * pct
	else:
		spawn_pos.x = float(ox)
		
	# Y
	var oy = spawn_info.get("origin_y", -50)
	if oy is String and oy == "random":
		spawn_pos.y = randf_range(50, viewport_size.y - 50)
	elif oy is String and oy.ends_with("%"):
		var pct := float(oy.replace("%", "")) / 100.0
		spawn_pos.y = viewport_size.y * pct
	else:
		spawn_pos.y = float(oy)

	spawn_enemy.emit(enemy_data, spawn_pos)
