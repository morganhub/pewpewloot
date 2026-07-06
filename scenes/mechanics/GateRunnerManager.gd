extends Node2D

## GateRunnerManager — Orchestre une vague "gate_runner" :
## - portes mathematiques (MathGate) qui modifient la ressource HP du joueur,
## - un swarm a esquiver (drones gate_rush) qui reduit le HP au contact,
## - l'affichage de la Valeur Globale (menace restante) du swarm.
## Le joueur ne tire pas pendant la vague ; il retrecit et se demultiplie en un
## essaim de clones dont le nombre suit sa ressource HP (max 40 unites).

signal finished

const MATH_GATE_SCENE: PackedScene = preload("res://scenes/mechanics/MathGate.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _duration: float = 20.0
var _elapsed: float = 0.0
var _events: Array = [] # [{ "time": float, "kind": "gate"|"swarm", "data": Dictionary }]
var _next_event_idx: int = 0
var _swarm_scheduled: bool = false
var _swarm_spawned: bool = false

var _drones: Array = [] # [{ "node": Node2D, "pv": float }]
var _pending_drone_spawns: int = 0 # staggered spawns not yet instantiated
# Staggered drone spawns, processed in _process (no SceneTreeTimer: zero
# per-drone allocations and the stagger freezes with the pause).
var _drone_spawn_queue: Array = [] # [{ "time": float, "data": Dictionary, "pv": float }]
var _global_value: float = 0.0
var _contact_radius: float = 48.0
var _speed_mult: float = 1.0
var _enemy_skins: Dictionary = {} # world-level skin overrides: enemy_id -> skin path

var _value_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_gate_runner_config() if DataManager else {}
	_contact_radius = maxf(8.0, float(_cfg.get("contact_radius_px", 48.0)))
	_speed_mult = maxf(0.1, float(_config.get("speed_multiplier", _cfg.get("speed_multiplier", 1.0))))
	var skins_v: Variant = _config.get("_enemy_skins", {})
	_enemy_skins = (skins_v as Dictionary) if skins_v is Dictionary else {}
	_duration = maxf(1.0, float(_config.get("duration", 20.0)))
	_elapsed = 0.0
	_build_event_schedule()
	_begin_player_mode()
	_ensure_value_label()
	set_process(true)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_gate_runner"):
		_player.call("begin_gate_runner", _cfg)
	if _hud and is_instance_valid(_hud) and _hud.has_method("set_hp_bar_hidden"):
		_hud.call("set_hp_bar_hidden", true)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_gate_runner"):
		_player.call("end_gate_runner")
	if _hud and is_instance_valid(_hud) and _hud.has_method("set_hp_bar_hidden"):
		_hud.call("set_hp_bar_hidden", false)

func _build_event_schedule() -> void:
	_events.clear()
	_next_event_idx = 0
	_swarm_scheduled = false

	var gates_v: Variant = _config.get("gates", [])
	if gates_v is Array:
		for gate_variant in (gates_v as Array):
			if gate_variant is Dictionary:
				var gate: Dictionary = gate_variant as Dictionary
				_events.append({
					"time": maxf(0.0, float(gate.get("time_offset", 0.0))),
					"kind": "gate",
					"data": gate
				})

	# Accept either a single swarm dict or an array of swarms.
	var swarm_v: Variant = _config.get("swarm", {})
	if swarm_v is Dictionary and not (swarm_v as Dictionary).is_empty():
		_events.append({
			"time": maxf(0.0, float((swarm_v as Dictionary).get("time_offset", 0.0))),
			"kind": "swarm",
			"data": swarm_v
		})
		_swarm_scheduled = true
	elif swarm_v is Array:
		for s_variant in (swarm_v as Array):
			if s_variant is Dictionary:
				_events.append({
					"time": maxf(0.0, float((s_variant as Dictionary).get("time_offset", 0.0))),
					"kind": "swarm",
					"data": s_variant
				})
				_swarm_scheduled = true

	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)

func _process(delta: float) -> void:
	_elapsed += delta

	while _next_event_idx < _events.size() and float(_events[_next_event_idx].get("time", 0.0)) <= _elapsed:
		var event: Dictionary = _events[_next_event_idx]
		_next_event_idx += 1
		match str(event.get("kind", "")):
			"gate":
				_spawn_gate(event.get("data", {}))
			"swarm":
				_spawn_swarm(event.get("data", {}))

	while not _drone_spawn_queue.is_empty() and float((_drone_spawn_queue[0] as Dictionary).get("time", 0.0)) <= _elapsed:
		var pending: Dictionary = _drone_spawn_queue.pop_front()
		_pending_drone_spawns = maxi(0, _pending_drone_spawns - 1)
		_spawn_single_drone(pending.get("data", {}), float(pending.get("pv", 1.0)))

	_update_drone_contacts()
	_update_value_label()

	# General rule: end the wave as soon as there are no more enemy ships on
	# screen (and nothing left to spawn), to avoid an idle period. Only applies
	# once every scripted event has been dispatched and a swarm was scheduled.
	var all_events_dispatched: bool = _next_event_idx >= _events.size()
	if all_events_dispatched and _swarm_scheduled and _pending_drone_spawns <= 0 and _drones.is_empty():
		_finish()
		return

	if _elapsed >= _duration:
		_finish()

func _spawn_gate(gate_data: Dictionary) -> void:
	if MATH_GATE_SCENE == null:
		return
	var node: Node = MATH_GATE_SCENE.instantiate()
	if not (node is Node2D):
		return
	var gate: Node2D = node as Node2D
	gate.z_as_relative = false
	gate.z_index = -5
	add_child(gate)
	if gate.has_signal("gate_passed"):
		gate.connect("gate_passed", _on_gate_passed)
	if gate.has_method("setup"):
		gate.call("setup", {
			"left": gate_data.get("left", {}),
			"right": gate_data.get("right", {}),
			"door_speed": float(gate_data.get("door_speed", _cfg.get("default_door_speed", 170.0))) * _speed_mult,
			"band_height": float(_cfg.get("gate_band_height_px", 96.0)),
			"spawn_y": float(_cfg.get("gate_spawn_y", -120.0)),
			"colors": _cfg.get("colors", {})
		})

func _on_gate_passed(operation: String, value: float) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("apply_gate_operation"):
		_player.call("apply_gate_operation", operation, value)

func _spawn_swarm(swarm_data: Dictionary) -> void:
	_swarm_spawned = true
	var total_value: float = maxf(1.0, float(swarm_data.get("total_value", 1000.0)))
	var enemy_id: String = str(swarm_data.get("enemy_id", _cfg.get("swarm_enemy_id_default", "swarmer")))

	# Ratio total_value -> nombre de vaisseaux (ex: 20 => 360 total = 18 vaisseaux).
	var value_per_ship: float = maxf(1.0, float(_cfg.get("swarm_total_value_per_ship", _cfg.get("swarm_value_per_entity_divisor", 20.0))))
	var ent_min: int = maxi(1, int(_cfg.get("swarm_entity_min", 6)))
	var ent_cap: int = maxi(ent_min, int(_cfg.get("swarm_entity_cap", 80)))
	var entities: int = clampi(int(round(total_value / value_per_ship)), ent_min, ent_cap)
	var pv: float = ceil(total_value / float(entities))

	var enemy_data_base: Dictionary = DataManager.get_enemy(enemy_id)
	if enemy_data_base.is_empty():
		enemy_data_base = DataManager.get_enemy("swarmer")
	if enemy_data_base.is_empty():
		return

	# Apply the world-level skin so drones use the world swarm visual instead of
	# the default placeholder (fallback to the "swarmer" skin if no specific one).
	var enemy_skin: String = str(_enemy_skins.get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(_enemy_skins.get("swarmer", ""))
	_apply_skin(enemy_data_base, enemy_skin)

	var spawn_interval: float = maxf(0.0, float(_cfg.get("swarm_spawn_interval_sec", 0.12)))
	for i in range(entities):
		var delay: float = float(i) * spawn_interval
		if delay <= 0.0:
			_spawn_single_drone(enemy_data_base, pv)
		else:
			_pending_drone_spawns += 1
			_drone_spawn_queue.append({
				"time": _elapsed + delay,
				"data": enemy_data_base,
				"pv": pv
			})

func _apply_skin(enemy_data: Dictionary, skin: String) -> void:
	if skin == "" or not ResourceLoader.exists(skin):
		return
	var visual: Dictionary = {}
	var visual_v: Variant = enemy_data.get("visual", {})
	if visual_v is Dictionary:
		visual = (visual_v as Dictionary).duplicate(true)
	var ext: String = skin.get_extension().to_lower()
	if ext == "tres" or ext == "res":
		visual["asset_anim"] = skin
		visual["asset"] = ""
	else:
		visual["asset"] = skin
		visual["asset_anim"] = ""
	enemy_data["visual"] = visual

func _spawn_single_drone(enemy_data_base: Dictionary, pv: float) -> void:
	if ENEMY_SCENE == null:
		return
	var enemy_data: Dictionary = enemy_data_base.duplicate(true)
	enemy_data["hp"] = int(maxf(1.0, pv))
	enemy_data["score"] = 0
	enemy_data["loot_chance"] = 0.0
	enemy_data["_movement_mode"] = "gate_rush"
	enemy_data["_gate_rush_descent_speed"] = float(_cfg.get("swarm_descent_speed_px_sec", 240.0)) * _speed_mult
	enemy_data["_gate_rush_x_follow_speed"] = float(_cfg.get("swarm_x_follow_speed_px_sec", 130.0)) * _speed_mult
	enemy_data["_gate_rush_weave_amplitude"] = float(_cfg.get("swarm_weave_amplitude_px", 36.0))
	enemy_data["_gate_rush_weave_frequency"] = float(_cfg.get("swarm_weave_frequency_hz", 1.6))
	enemy_data["_gate_rush_target_spread_px"] = float(_cfg.get("swarm_target_spread_px", 240.0))

	var node: Node = ENEMY_SCENE.instantiate()
	if not (node is CharacterBody2D):
		return
	var drone: CharacterBody2D = node as CharacterBody2D
	var viewport_size: Vector2 = get_viewport_rect().size
	var spawn_x: float = randf_range(viewport_size.x * 0.15, viewport_size.x * 0.85)
	add_child(drone)
	drone.global_position = Vector2(spawn_x, float(_cfg.get("swarm_spawn_y", -90.0)))
	if drone.has_method("setup"):
		drone.call("setup", enemy_data)
	# Drones are not shot down (player does not fire) and must not trigger the
	# player's standard contact-damage path: this manager resolves contact.
	drone.collision_layer = 0
	drone.collision_mask = 0

	var entry: Dictionary = { "node": drone, "pv": pv }
	_drones.append(entry)

func _update_drone_contacts() -> void:
	if _drones.is_empty():
		return
	var player_valid: bool = _player != null and is_instance_valid(_player)
	var bottom_y: float = get_viewport_rect().size.y
	var player_scale: float = 1.0
	if player_valid and _player.has_method("get_gate_runner_scale"):
		player_scale = maxf(0.1, float(_player.call("get_gate_runner_scale")))
	var effective_radius: float = _contact_radius * player_scale
	# The escort swarm widens the contact footprint: more HP = more clones = a
	# bigger cloud to weave through (same risk/reward as the old growing ship).
	if player_valid and _player.has_method("get_gate_runner_swarm_radius"):
		effective_radius = maxf(effective_radius, float(_player.call("get_gate_runner_swarm_radius")))
	for i in range(_drones.size() - 1, -1, -1):
		var entry: Dictionary = _drones[i]
		var drone_v: Variant = entry.get("node", null)
		if not (drone_v is Node2D) or not is_instance_valid(drone_v):
			_drones.remove_at(i)
			continue
		var drone: Node2D = drone_v as Node2D
		if player_valid:
			var dist: float = drone.global_position.distance_to(_player.global_position)
			if dist <= effective_radius:
				# Contact: the drone deals its threat value and is consumed (no reward).
				var pv: float = float(entry.get("pv", 0.0))
				if _player.has_method("take_damage"):
					_player.call("take_damage", int(maxf(1.0, pv)))
				_drones.remove_at(i)
				drone.queue_free()
				continue
		# Dodged: the drone slips past the bottom -> reward the player with crystals.
		if drone.global_position.y > bottom_y:
			_award_dodge_crystal(drone.global_position)
			_drones.remove_at(i)
			drone.queue_free()

func _award_dodge_crystal(at_pos: Vector2) -> void:
	if _game and is_instance_valid(_game) and _game.has_method("spawn_gate_runner_crystal"):
		var spawn_pos: Vector2 = Vector2(at_pos.x, get_viewport_rect().size.y - 60.0)
		_game.call("spawn_gate_runner_crystal", spawn_pos)

func _recompute_global_value() -> void:
	var total: float = 0.0
	for entry in _drones:
		if entry is Dictionary:
			var drone_v: Variant = (entry as Dictionary).get("node", null)
			if drone_v is Node2D and is_instance_valid(drone_v):
				total += float((entry as Dictionary).get("pv", 0.0))
	_global_value = total

func _ensure_value_label() -> void:
	if _value_label and is_instance_valid(_value_label):
		return
	_value_label = Label.new()
	_value_label.name = "GlobalValueLabel"
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_size_override("font_size", 44)
	_value_label.add_theme_color_override("font_color", Color("#FFE08A"))
	_value_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_value_label.add_theme_constant_override("outline_size", 6)
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value_label.z_as_relative = false
	_value_label.z_index = 60
	_value_label.visible = false
	add_child(_value_label)

func _update_value_label() -> void:
	if _value_label == null or not is_instance_valid(_value_label):
		return
	_recompute_global_value()
	if _global_value <= 0.0:
		_value_label.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_value_label.size = Vector2(viewport_size.x, 60.0)
	_value_label.position = Vector2(0.0, viewport_size.y * 0.14)
	_value_label.text = str(int(round(_global_value)))
	_value_label.visible = true

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_restore_player_mode()
	finished.emit()
	queue_free()

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
