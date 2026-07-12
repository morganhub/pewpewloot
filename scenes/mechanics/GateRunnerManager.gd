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
const NumberFormat := preload("res://scenes/mechanics/number_format.gd")

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

# Murs à brèche (mode libre) : formations de drones "manual" pilotées ici —
# [{ "drones": Array, "base_x": Array, "y": float, "phase": float,
#    "amp": float, "speed": float }]. Contacts/despawn passent par _drones.
var _walls: Array = []
# Défi "cible exacte" : le scanner final bloque le self-finish tant qu'il
# n'est pas résolu (jackpot si |HP - cible| <= tolérance).
var _target_pending: bool = false
var _target_value: float = 0.0
var _target_line: Dictionary = {} # { "core": Line2D, "glow": Line2D, "label": Label, "y": float }
var _target_label: Label = null
var _target_material: CanvasItemMaterial = null

# Jackpot final (gen_jackpot_chance) : à la fin du round, l'excédent au-delà de
# max_hp est converti en score/cristaux (récompense les ×). Annoncé dès le début.
var _jackpot_active: bool = false
var _jackpot_label: Label = null
# Clone doré (gen_golden_clone_chance) : bonus si AUCUN contact subi du round.
var _golden_clone_active: bool = false
# Méga-drone : gros porteur traversant — contact = ressource ÷2, esquive = cristaux.
# { "node": Node2D, "label": Label, "radius": float, "y": float }
var _mega: Dictionary = {}
var _mega_hit_cd: float = 0.0
# Piscine de déflation : bande pleine largeur — la traverser divise la ressource
# ET adapte les valeurs restantes du round. { "node": Node2D, "y": float,
# "height": float, "consumed": bool }
var _deflation: Dictionary = {}

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
	if not _has_authored_content():
		_generate_content()
	_build_event_schedule()
	_begin_player_mode()
	_ensure_value_label()
	if _target_pending:
		# La cible est annoncée dès le début du round : le joueur choisit ses
		# portes pour ATTERRIR dessus, pas pour maximiser.
		_ensure_target_label()
	# Jackpot final : annoncé dès le début (empiler les × devient une stratégie).
	_jackpot_active = randf() < clampf(_gen_f("gen_jackpot_chance", 0.0), 0.0, 1.0)
	if _jackpot_active:
		_ensure_jackpot_label()
	# Clone doré : un round parfait (aucun contact subi) = bonus cristaux.
	_golden_clone_active = randf() < clampf(_gen_f("gen_golden_clone_chance", 0.0), 0.0, 1.0)
	if _golden_clone_active and _player and is_instance_valid(_player) \
		and _player.has_method("set_gate_runner_golden_clone"):
		_player.call("set_gate_runner_golden_clone", true)
	set_process(true)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_gate_runner"):
		# Cfg fusionné : la clé de continuité de la vague (freemode base_wave)
		# doit atteindre le Player — _cfg seul est le bloc global du type.
		var player_cfg: Dictionary = _cfg.duplicate(true)
		player_cfg["hp_clamp_on_wave_end"] = bool(_config.get("hp_clamp_on_wave_end",
			_cfg.get("hp_clamp_on_wave_end", true)))
		_player.call("begin_gate_runner", player_cfg)
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

	# Murs à brèche (mode libre ; scriptable en story via walls[]) : ils
	# alimentent _drones comme les nuées -> même chemin de fin anticipée.
	var walls_v: Variant = _config.get("walls", [])
	if walls_v is Array:
		for wall_variant in (walls_v as Array):
			if wall_variant is Dictionary:
				_events.append({
					"time": maxf(0.0, float((wall_variant as Dictionary).get("time_offset", 0.0))),
					"kind": "wall",
					"data": wall_variant
				})
				_swarm_scheduled = true

	# Scanner "cible exacte" : un seul par round, bloque le self-finish
	# jusqu'à sa résolution (_target_pending).
	var target_v: Variant = _config.get("target", {})
	if target_v is Dictionary and not (target_v as Dictionary).is_empty():
		_events.append({
			"time": maxf(0.0, float((target_v as Dictionary).get("time_offset", 0.0))),
			"kind": "target",
			"data": target_v
		})
		_target_pending = true
		_target_value = maxf(1.0, float((target_v as Dictionary).get("target_value", 1.0)))

	# Méga-drone traversant (un seul par round) : contact = ressource divisée.
	var mega_v: Variant = _config.get("mega_drone", {})
	if mega_v is Dictionary and not (mega_v as Dictionary).is_empty():
		_events.append({
			"time": maxf(0.0, float((mega_v as Dictionary).get("time_offset", 0.0))),
			"kind": "mega_drone",
			"data": mega_v
		})

	# Piscine de déflation : bande pleine largeur, passage obligé qui divise la
	# ressource (générée quand les nombres deviennent trop gros).
	var deflation_v: Variant = _config.get("deflation", {})
	if deflation_v is Dictionary and not (deflation_v as Dictionary).is_empty():
		_events.append({
			"time": maxf(0.0, float((deflation_v as Dictionary).get("time_offset", 0.0))),
			"kind": "deflation",
			"data": deflation_v
		})

	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)

## Vague scriptée (story) : gates[] ou swarm[] présents dans la vague — le
## générateur ne touche à rien, le contenu auteuré gagne toujours.
func _has_authored_content() -> bool:
	var gates_v: Variant = _config.get("gates", [])
	if gates_v is Array and not (gates_v as Array).is_empty():
		return true
	var swarm_v: Variant = _config.get("swarm", {})
	if swarm_v is Dictionary and not (swarm_v as Dictionary).is_empty():
		return true
	if swarm_v is Array and not (swarm_v as Array).is_empty():
		return true
	return false

## Résolution des knobs gen_* : vague (base_wave + per_level du mode libre) >
## défauts du type (wave_types.json > gate_runner) > fallback code.
func _gen_f(key: String, default_value: float) -> float:
	return float(_config.get(key, _cfg.get(key, default_value)))

## Mode libre : synthétise gates[]/swarm[]/walls[]/target depuis les knobs
## scalaires gen_* (scalés par level via per_level). Cadence story : une paire
## de portes toutes les gen_gate_interval_sec, la nuée suit sa porte de
## gen_swarm_offset_sec ; plus rien après duration - gen_tail_margin_sec (la
## dernière nuée doit être nettoyée avant le timeout dur pour laisser le
## self-finish clore le round). CONTINUITÉ : les ratios gen_*_hp_ratio (> 0 en
## libre, 0 en story) font suivre nuées et portes sur la ressource COURANTE du
## joueur, lue ICI à la génération du round — le risk/reward tient même riche.
func _generate_content() -> void:
	var first: float = maxf(0.5, _gen_f("gen_first_gate_offset_sec", 2.0))
	var interval: float = maxf(_gen_f("gen_gate_interval_min_sec", 2.5), _gen_f("gen_gate_interval_sec", 7.0))
	var swarm_offset: float = maxf(0.5, _gen_f("gen_swarm_offset_sec", 3.0))
	var cutoff: float = maxf(first + swarm_offset, _duration - maxf(0.0, _gen_f("gen_tail_margin_sec", 12.0)))
	var player_hp: float = 0.0
	if _player and is_instance_valid(_player):
		player_hp = maxf(0.0, float(_player.get("current_hp")))
	var total: float = maxf(1.0, _gen_f("gen_swarm_total_base", 350.0))
	var swarm_ratio: float = maxf(0.0, _gen_f("gen_swarm_hp_ratio", 0.0))
	if swarm_ratio > 0.0:
		total = maxf(total, player_hp * swarm_ratio)
	var step: float = maxf(0.0, _gen_f("gen_swarm_total_step", 100.0))
	step = maxf(step, total * maxf(0.0, _gen_f("gen_swarm_step_ratio", 0.0)))
	var add_base: float = maxf(1.0, _gen_f("gen_gate_add_value", 60.0))
	var add_ratio: float = maxf(0.0, _gen_f("gen_gate_add_hp_ratio", 0.0))
	if add_ratio > 0.0:
		add_base = maxf(add_base, player_hp * add_ratio)
	var sub_base: float = maxf(1.0, _gen_f("gen_gate_sub_value", 40.0))
	var sub_ratio: float = maxf(0.0, _gen_f("gen_gate_sub_hp_ratio", 0.0))
	if sub_ratio > 0.0:
		sub_base = maxf(sub_base, player_hp * sub_ratio)
	var wall_chance: float = clampf(_gen_f("gen_wall_chance", 0.0), 0.0, 1.0)
	var shift_chance: float = clampf(_gen_f("gen_shifting_gate_chance", 0.0), 0.0, 1.0)
	var golden_chance: float = clampf(_gen_f("gen_golden_gate_chance", 0.0), 0.0, 1.0)
	var triple_chance: float = clampf(_gen_f("gen_triple_gate_chance", 0.0), 0.0, 1.0)
	var sliding_chance: float = clampf(_gen_f("gen_sliding_gate_chance", 0.0), 0.0, 1.0)
	var auction_chance: float = clampf(_gen_f("gen_auction_gate_chance", 0.0), 0.0, 1.0)
	var equation_chance: float = clampf(_gen_f("gen_equation_chance", 0.0), 0.0, 1.0)
	var burst_chance: float = clampf(_gen_f("gen_burst_chance", 0.0), 0.0, 1.0)
	var burst_gap: float = maxf(0.4, _gen_f("gen_burst_gap_sec", 1.2))
	var gates: Array = []
	var swarms: Array = []
	var walls: Array = []
	var t: float = first
	# >= 1 slot garanti même avec des knobs dégénérés : _swarm_scheduled
	# reste vrai et la fin anticipée (plus de drones) fonctionne toujours.
	while t + swarm_offset <= cutoff or (gates.is_empty() and walls.is_empty()):
		# Un slot peut devenir un mur à brèche (jamais le premier : le round
		# s'ouvre toujours sur un choix de portes).
		if wall_chance > 0.0 and randf() < wall_chance and not (gates.is_empty() and walls.is_empty()):
			walls.append({ "time_offset": t, "total_value": total })
		elif burst_chance > 0.0 and randf() < burst_chance and not gates.is_empty():
			# Burst : 3 paires très rapprochées, SANS nuée entre elles.
			for burst_i in range(3):
				var burst_gate: Dictionary = _generate_gate(t + burst_gap * float(burst_i), add_base, sub_base)
				if burst_i == 0:
					burst_gate["burst"] = true # annonce au spawn de la première
				gates.append(burst_gate)
		else:
			var gate: Dictionary = _generate_gate(t, add_base, sub_base)
			var swarm_mult: float = 1.0
			# Triple choix : une 3e porte au centre (mixte aléatoire).
			if triple_chance > 0.0 and randf() < triple_chance:
				gate["center"] = _generate_extra_door(add_base, sub_base)
			# Porte dorée : un côté devient x gen_golden_gate_mult — mais la
			# nuée du slot est renforcée (cupidité/sécurité).
			if golden_chance > 0.0 and randf() < golden_chance:
				_make_gate_golden(gate, sub_base)
				swarm_mult = maxf(1.0, _gen_f("golden_gate_swarm_mult", 1.6))
			if shift_chance > 0.0 and randf() < shift_chance:
				gate["shift_interval_sec"] = maxf(0.4, _gen_f("gen_shift_interval_sec", 1.5))
			if sliding_chance > 0.0 and randf() < sliding_chance:
				gate["slide_amplitude_px"] = maxf(0.0, _gen_f("slide_amplitude_px", 120.0))
			if auction_chance > 0.0 and randf() < auction_chance:
				gate["auction"] = true
			elif equation_chance > 0.0 and randf() < equation_chance:
				gate["equation"] = true
			gates.append(gate)
			# enemy_id omis : _spawn_swarm retombe sur swarm_enemy_id_default.
			swarms.append({ "time_offset": t + swarm_offset, "total_value": total * swarm_mult })
		total += step
		t += interval
	_config["gates"] = gates
	_config["swarm"] = swarms
	_config["walls"] = walls
	# Méga-drone : un seul par round, sur un temps aléatoire du corps du round.
	if randf() < clampf(_gen_f("gen_mega_drone_chance", 0.0), 0.0, 1.0) and t > first + interval:
		_config["mega_drone"] = { "time_offset": randf_range(first + interval, maxf(first + interval, cutoff)) }
	# Piscine de déflation : dès que la ressource dépasse le seuil, le round
	# s'ouvre sur la piscine (passage obligé — on « se rafraîchit »).
	if player_hp >= maxf(1000.0, _gen_f("gen_deflation_trigger_hp", 100000.0)):
		_config["deflation"] = { "time_offset": maxf(0.2, first - 1.0) }
	# Défi "cible exacte" : la cible est SIMULÉE sur les portes générées ->
	# toujours atteignable en jouant le bon chemin (les permutations n'altèrent
	# pas l'ensemble des opérations disponibles, juste leur côté).
	var target_chance: float = clampf(_gen_f("gen_target_chance", 0.0), 0.0, 1.0)
	if target_chance > 0.0 and randf() < target_chance and not gates.is_empty() and player_hp > 0.0:
		var last_event_time: float = t - interval + swarm_offset
		_config["target"] = {
			"time_offset": last_event_time + maxf(1.0, _gen_f("gen_target_time_margin_sec", 4.0)),
			"target_value": _simulate_target_value(player_hp, gates)
		}

## Une paire de portes : [add | multiply] (double bonus), [subtract | divide]
## (double malus — jamais [subtract | subtract] : divide fait int(round(hp/2))
## >= 1 côté Player, donc chaque porte garde une option survivable), sinon
## mixte bonus/malus. add_base/sub_base = valeurs déjà scalées level/ressource.
func _generate_gate(time_offset: float, add_base: float, sub_base: float) -> Dictionary:
	var p_malus: float = clampf(_gen_f("gen_double_malus_chance", 0.0), 0.0, 1.0)
	var p_bonus: float = clampf(_gen_f("gen_double_bonus_chance", 0.5), 0.0, 1.0 - p_malus)
	var bonus_doors: Array = [
		{ "operation": "add", "value": _gen_value_from(add_base) },
		{ "operation": "multiply", "value": maxf(1.1, _gen_f("gen_gate_mult_value", 2.0)) }
	]
	var malus_doors: Array = [
		{ "operation": "subtract", "value": _gen_value_from(sub_base) },
		{ "operation": "divide", "value": maxf(1.1, _gen_f("gen_gate_div_value", 2.0)) }
	]
	var doors: Array = []
	var roll: float = randf()
	if roll < p_malus:
		doors = malus_doors
	elif roll < p_malus + p_bonus:
		doors = bonus_doors
	else:
		doors = [bonus_doors.pick_random(), malus_doors.pick_random()]
	doors.shuffle()
	return { "time_offset": time_offset, "left": doors[0], "right": doors[1] }

## 3e porte (triple choix) : un tirage mixte indépendant.
func _generate_extra_door(add_base: float, sub_base: float) -> Dictionary:
	var pool: Array = [
		{ "operation": "add", "value": _gen_value_from(add_base) },
		{ "operation": "multiply", "value": maxf(1.1, _gen_f("gen_gate_mult_value", 2.0)) },
		{ "operation": "subtract", "value": _gen_value_from(sub_base) },
		{ "operation": "divide", "value": maxf(1.1, _gen_f("gen_gate_div_value", 2.0)) }
	]
	return pool.pick_random()

## Porte dorée : un côté aléatoire devient x gen_golden_gate_mult (marqué
## golden pour le rendu), le côté opposé redevient un malus franc — le choix
## cupidité/sécurité reste entier.
func _make_gate_golden(gate: Dictionary, sub_base: float) -> void:
	var sides: Array = ["left", "right"]
	if gate.has("center"):
		sides.append("center")
	var golden_side: String = str(sides.pick_random())
	gate[golden_side] = {
		"operation": "multiply",
		"value": maxf(1.5, _gen_f("gen_golden_gate_mult", 3.0)),
		"golden": true
	}
	var other_side: String = "right" if golden_side == "left" else "left"
	gate[other_side] = [
		{ "operation": "subtract", "value": _gen_value_from(sub_base) },
		{ "operation": "divide", "value": maxf(1.1, _gen_f("gen_gate_div_value", 2.0)) }
	].pick_random()

## Valeur de porte add/subtract : jitter aléatoire puis arrondi au pas
## (gen_value_round_step) pour garder des chiffres lisibles sur les portes.
func _gen_value_from(base_value: float) -> float:
	var jitter: float = clampf(_gen_f("gen_gate_value_jitter", 0.25), 0.0, 0.9)
	var step: float = maxf(1.0, _gen_f("gen_value_round_step", 5.0))
	return maxf(step, snappedf(base_value * randf_range(1.0 - jitter, 1.0 + jitter), step))

## Simule un chemin aléatoire à travers les paires générées (mêmes arrondis
## que Player.apply_gate_operation, plancher 1) : le résultat sert de cible —
## atteignable par construction, la tolérance absorbe les dégâts de drones.
func _simulate_target_value(start_hp: float, gates: Array) -> float:
	var hp: float = maxf(1.0, start_hp)
	for gate_v in gates:
		if not (gate_v is Dictionary):
			continue
		var side: String = "left" if randf() < 0.5 else "right"
		var door_v: Variant = (gate_v as Dictionary).get(side, {})
		if not (door_v is Dictionary):
			continue
		var door: Dictionary = door_v as Dictionary
		var value: float = float(door.get("value", 0.0))
		match str(door.get("operation", "")):
			"add":
				hp += value
			"subtract":
				hp -= value
			"multiply":
				hp *= value
			"divide":
				if absf(value) > 0.0001:
					hp /= value
		hp = maxf(1.0, float(int(round(hp))))
	return hp

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
			"wall":
				_spawn_wall(event.get("data", {}))
			"target":
				_spawn_target(event.get("data", {}))
			"mega_drone":
				_spawn_mega_drone()
			"deflation":
				_spawn_deflation_pool()

	while not _drone_spawn_queue.is_empty() and float((_drone_spawn_queue[0] as Dictionary).get("time", 0.0)) <= _elapsed:
		var pending: Dictionary = _drone_spawn_queue.pop_front()
		_pending_drone_spawns = maxi(0, _pending_drone_spawns - 1)
		_spawn_single_drone(pending.get("data", {}), float(pending.get("pv", 1.0)))

	# Positionner les formations AVANT le test de contact.
	_update_walls(delta)
	_update_drone_contacts()
	_update_mega_drone(delta)
	_update_deflation_pool(delta)
	_update_target(delta)
	_update_value_label()

	# General rule: end the wave as soon as there are no more enemy ships on
	# screen (and nothing left to spawn), to avoid an idle period. Only applies
	# once every scripted event has been dispatched and a swarm was scheduled.
	# Un scanner de cible non résolu retient la fin (il doit passer le joueur) ;
	# idem méga-drone / piscine encore à l'écran.
	var all_events_dispatched: bool = _next_event_idx >= _events.size()
	if all_events_dispatched and _swarm_scheduled and _pending_drone_spawns <= 0 \
		and _drones.is_empty() and not _target_pending \
		and _mega.is_empty() and _deflation.is_empty():
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
			"center": gate_data.get("center", {}), # triple choix (optionnel)
			"door_speed": float(gate_data.get("door_speed", _cfg.get("default_door_speed", 170.0))) * _speed_mult,
			"band_height": float(_cfg.get("gate_band_height_px", 96.0)),
			"spawn_y": float(_cfg.get("gate_spawn_y", -120.0)),
			"colors": _cfg.get("colors", {}),
			# > 0 = paire permutante : les opérations échangent de côté à
			# intervalle régulier (flash télégraphié).
			"shift_interval_sec": float(gate_data.get("shift_interval_sec", 0.0)),
			"shift_telegraph_sec": float(_cfg.get("gate_shift_telegraph_sec", 0.5)),
			# Variantes composables : coulissante / enchère / équations.
			"slide_amplitude_px": float(gate_data.get("slide_amplitude_px", 0.0)),
			"slide_speed_hz": float(_cfg.get("slide_speed_hz", 0.25)),
			"auction": bool(gate_data.get("auction", false)),
			"auction_start_mult": float(_cfg.get("auction_start_mult", 1.5)),
			"auction_end_mult": float(_cfg.get("auction_end_mult", 0.6)),
			"equation": bool(gate_data.get("equation", false))
		})
	# Burst : la première paire du burst annonce l'enchaînement.
	if bool(gate_data.get("burst", false)) and VFXManager:
		var viewport_size: Vector2 = get_viewport_rect().size
		VFXManager.spawn_floating_text(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.3),
			_translate_or("gate_runner_burst", "GATE RUSH!"), Color("#FFD56B"), self)

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

# =============================================================================
# MUR À BRÈCHE (esquive pure : rangée pleine largeur, ouverture mobile)
# =============================================================================

## Rangée de drones en formation (mode "manual" : positions pilotées ici), une
## brèche au centre de la FORMATION — l'offset sinusoïdal global la promène
## sur l'écran. Les drones passent par _drones : contact = pv de dégâts,
## sortie par le bas = cristal d'esquive, fin de vague inchangée.
func _spawn_wall(wall_data: Dictionary) -> void:
	_swarm_spawned = true
	var viewport_size: Vector2 = get_viewport_rect().size
	var total_value: float = maxf(1.0, float(wall_data.get("total_value", 350.0)))
	var enemy_id: String = str(wall_data.get("enemy_id", _cfg.get("swarm_enemy_id_default", "swarmer")))
	var enemy_data_base: Dictionary = DataManager.get_enemy(enemy_id)
	if enemy_data_base.is_empty():
		enemy_data_base = DataManager.get_enemy("swarmer")
	if enemy_data_base.is_empty():
		return
	var enemy_skin: String = str(_enemy_skins.get(enemy_id, ""))
	if enemy_skin == "":
		enemy_skin = str(_enemy_skins.get("swarmer", ""))
	_apply_skin(enemy_data_base, enemy_skin)

	var gap_width: float = maxf(80.0, float(_cfg.get("gen_wall_gap_width_px", 360.0)))
	var spacing: float = maxf(24.0, float(_cfg.get("gen_wall_spacing_px", 64.0)))
	var margin: float = 40.0
	var amp: float = maxf(0.0, (viewport_size.x - gap_width) * 0.5 - margin)
	# Colonnes couvrant l'écran + l'amplitude d'oscillation (la formation
	# déborde latéralement pour que l'écran reste muré pendant la dérive).
	var base_xs: Array = []
	var x: float = -amp + margin
	while x <= viewport_size.x + amp - margin:
		if absf(x - viewport_size.x * 0.5) > gap_width * 0.5:
			base_xs.append(x)
		x += spacing
	if base_xs.is_empty():
		return
	var ent_cap: int = maxi(1, int(_cfg.get("swarm_entity_cap", 80)))
	while base_xs.size() > ent_cap:
		base_xs.remove_at(randi() % base_xs.size())
	var pv: float = ceil(total_value / float(base_xs.size()))

	var spawn_y: float = float(_cfg.get("swarm_spawn_y", -90.0))
	var drones: Array = []
	for bx in base_xs:
		drones.append(_spawn_wall_drone(enemy_data_base, pv, Vector2(float(bx), spawn_y)))
	_walls.append({
		"drones": drones,
		"base_x": base_xs,
		"y": spawn_y,
		"phase": randf() * TAU,
		"amp": amp,
		"speed": maxf(1.0, float(_cfg.get("swarm_descent_speed_px_sec", 210.0))) * _speed_mult
	})

func _spawn_wall_drone(enemy_data_base: Dictionary, pv: float, at_pos: Vector2) -> CharacterBody2D:
	if ENEMY_SCENE == null:
		return null
	var enemy_data: Dictionary = enemy_data_base.duplicate(true)
	enemy_data["hp"] = int(maxf(1.0, pv))
	enemy_data["score"] = 0
	enemy_data["loot_chance"] = 0.0
	enemy_data["_movement_mode"] = "manual"
	var node: Node = ENEMY_SCENE.instantiate()
	if not (node is CharacterBody2D):
		return null
	var drone: CharacterBody2D = node as CharacterBody2D
	add_child(drone)
	drone.global_position = at_pos
	if drone.has_method("setup"):
		drone.call("setup", enemy_data)
	# Comme les drones de nuée : pas de tir subi/émis, contact résolu ici.
	drone.collision_layer = 0
	drone.collision_mask = 0
	_drones.append({ "node": drone, "pv": pv })
	return drone

## Descend chaque formation et fait dériver sa brèche (offset sinusoïdal
## commun). Les drones consommés (contact) ou sortis (bas) sont despawnés par
## _update_drone_contacts — ici on ne positionne que les survivants.
func _update_walls(delta: float) -> void:
	if _walls.is_empty():
		return
	var drift_hz: float = maxf(0.01, float(_cfg.get("gen_wall_gap_drift_hz", 0.12)))
	var bottom_y: float = get_viewport_rect().size.y
	for i in range(_walls.size() - 1, -1, -1):
		var wall: Dictionary = _walls[i]
		wall["y"] = float(wall.get("y", 0.0)) + float(wall.get("speed", 210.0)) * delta
		wall["phase"] = float(wall.get("phase", 0.0)) + delta * TAU * drift_hz
		var offset_x: float = sin(float(wall["phase"])) * float(wall.get("amp", 0.0))
		var drones: Array = wall.get("drones", [])
		var base_x: Array = wall.get("base_x", [])
		var alive: int = 0
		for j in range(mini(drones.size(), base_x.size())):
			var drone_v: Variant = drones[j]
			if not (drone_v is Node2D) or not is_instance_valid(drone_v):
				continue
			alive += 1
			(drone_v as Node2D).global_position = Vector2(float(base_x[j]) + offset_x, float(wall["y"]))
		if alive == 0 or float(wall["y"]) > bottom_y + 120.0:
			_walls.remove_at(i)

# =============================================================================
# CIBLE EXACTE (scanner final : finir à ±tolérance de la cible = jackpot)
# =============================================================================

## Label persistant "CIBLE : N" en haut d'écran, affiché dès le début du round.
func _ensure_target_label() -> void:
	if _target_label and is_instance_valid(_target_label):
		return
	_target_label = Label.new()
	_target_label.name = "TargetValueLabel"
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_label.add_theme_font_size_override("font_size", int(_cfg.get("target_label_font_size", 30)))
	_target_label.add_theme_color_override("font_color", Color(str(_cfg.get("target_label_color", "#7FE8FF"))))
	_target_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_target_label.add_theme_constant_override("outline_size", 5)
	_target_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_label.z_as_relative = false
	_target_label.z_index = 60
	add_child(_target_label)
	var viewport_size: Vector2 = get_viewport_rect().size
	_target_label.size = Vector2(viewport_size.x, 40.0)
	_target_label.position = Vector2(0.0, viewport_size.y * 0.085)
	_target_label.text = LocaleManager.translate("gate_runner_target") % NumberFormat.compact(_target_value)

## Le scanner : ligne core+glow pleine largeur qui descend à la vitesse des
## portes et se résout au passage du vaisseau.
func _spawn_target(target_data: Dictionary) -> void:
	_target_value = maxf(1.0, float(target_data.get("target_value", _target_value)))
	if _target_material == null:
		_target_material = CanvasItemMaterial.new()
		_target_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow := Line2D.new()
	glow.width = 18.0
	glow.default_color = Color("#39C8FF66")
	glow.material = _target_material
	glow.z_as_relative = false
	glow.z_index = 55
	add_child(glow)
	var core := Line2D.new()
	core.width = 4.0
	core.default_color = Color("#D8F6FF")
	core.z_as_relative = false
	core.z_index = 56
	add_child(core)
	_target_line = { "core": core, "glow": glow, "y": float(_cfg.get("gate_spawn_y", -120.0)) }

func _update_target(delta: float) -> void:
	if _target_line.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var speed: float = maxf(10.0, float(_cfg.get("default_door_speed", 170.0))) * _speed_mult
	var y: float = float(_target_line.get("y", 0.0)) + speed * delta
	_target_line["y"] = y
	var points := PackedVector2Array([Vector2(0.0, y), Vector2(viewport_size.x, y)])
	for key in ["core", "glow"]:
		var line_v: Variant = _target_line.get(key, null)
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).points = points
	# Résolution : la ligne franchit le vaisseau (ou sort de l'écran sans lui).
	var resolved: bool = false
	var hit: bool = false
	if _player and is_instance_valid(_player) and y >= _player.global_position.y:
		resolved = true
		var hp: float = maxf(0.0, float(_player.get("current_hp")))
		var tolerance: float = maxf(1.0, _target_value * clampf(float(_cfg.get("gen_target_tolerance_ratio", 0.1)), 0.01, 0.9))
		hit = absf(hp - _target_value) <= tolerance
	elif y > viewport_size.y + 60.0:
		resolved = true
	if not resolved:
		return
	if hit:
		_grant_target_reward()
	_clear_target_line()
	_target_pending = false
	if _target_label and is_instance_valid(_target_label):
		_target_label.visible = false

func _grant_target_reward() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var at: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	var crystals: int = maxi(0, int(_cfg.get("gen_target_crystals", 10)))
	if _game and is_instance_valid(_game):
		# Pluie GARANTIE (spawn_gate_runner_crystal roulerait la chance dodge).
		if crystals > 0 and _game.has_method("spawn_reward_crystals_from_top"):
			_game.call("spawn_reward_crystals_from_top", crystals)
		var score: int = int(round(float(_cfg.get("gen_target_score", 2500)) \
			* maxf(0.0, float(_config.get("reward_multiplier", 1.0)))))
		if score > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", score, at)
	if VFXManager:
		VFXManager.spawn_floating_text(at + Vector2(0.0, -80.0),
			LocaleManager.translate("gate_runner_target_hit"), Color("#7FE8FF"), self)

func _clear_target_line() -> void:
	for key in ["core", "glow"]:
		var line_v: Variant = _target_line.get(key, null)
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).queue_free()
	_target_line = {}

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
				_lose_golden_clone()
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

# =============================================================================
# MÉGA-DRONE (gros porteur traversant : contact = ressource divisée, texte -50%)
# =============================================================================

func _spawn_mega_drone() -> void:
	if not _mega.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var node := Node2D.new()
	node.name = "MegaDrone"
	node.z_as_relative = false
	node.z_index = 12
	var mega_scale: float = maxf(1.0, float(_cfg.get("mega_drone_scale", 2.5)))
	var radius: float = 48.0 * mega_scale
	var visual: Node2D = _build_mega_drone_visual(mega_scale)
	node.add_child(visual)
	# « -50% » affiché SUR le drone (divisor 2 = -50 %).
	var divisor: float = maxf(1.1, _gen_f("mega_drone_penalty_divisor", 2.0))
	var label := Label.new()
	label.text = "-%d%%" % int(round((1.0 - 1.0 / divisor) * 100.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(28.0 * mega_scale * 0.6))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(radius * 2.0, radius * 2.0)
	label.position = -Vector2.ONE * radius
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	node.global_position = Vector2(viewport_size.x * randf_range(0.25, 0.75), -radius - 20.0)
	add_child(node)
	_mega = { "node": node, "label": label, "radius": radius }
	_mega_hit_cd = 0.0

## Visuel : asset dédié mega_drone_asset, sinon skin swarmer scalé + tint rouge.
func _build_mega_drone_visual(mega_scale: float) -> Node2D:
	var root := Node2D.new()
	var asset_path: String = str(_cfg.get("mega_drone_asset", ""))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = (Vector2.ONE * 96.0 * mega_scale) / maxf(tex_size.x, tex_size.y)
			root.add_child(sprite)
			return root
	# PH : disque rouge sombre menaçant.
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * 48.0 * mega_scale)
	poly.polygon = pts
	poly.color = Color("#8A1F2AD0")
	root.add_child(poly)
	return root

func _update_mega_drone(delta: float) -> void:
	if _mega.is_empty():
		return
	_mega_hit_cd = maxf(0.0, _mega_hit_cd - delta)
	var node: Node2D = _mega.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		_mega = {}
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var speed: float = maxf(40.0, float(_cfg.get("mega_drone_speed_px_sec", 160.0))) * _speed_mult
	var pos: Vector2 = node.global_position
	pos.y += speed * delta
	# Suivi X mou : impossible de l'ignorer, esquive au dernier moment requise.
	if _player and is_instance_valid(_player):
		pos.x = move_toward(pos.x, _player.global_position.x, speed * 0.35 * delta)
	node.global_position = pos
	var radius: float = float(_mega.get("radius", 96.0))
	# Contact avec l'essaim (rayon global) : ressource divisée.
	if _mega_hit_cd <= 0.0 and _player and is_instance_valid(_player):
		var swarm_radius: float = _contact_radius
		if _player.has_method("get_gate_runner_swarm_radius"):
			swarm_radius = maxf(swarm_radius, float(_player.call("get_gate_runner_swarm_radius")))
		if pos.distance_to(_player.global_position) <= radius + swarm_radius:
			_mega_hit_cd = 1.0
			if _player.has_method("apply_gate_operation"):
				_player.call("apply_gate_operation", "divide", maxf(1.1, _gen_f("mega_drone_penalty_divisor", 2.0)))
			_lose_golden_clone()
			if VFXManager:
				VFXManager.spawn_impact(pos, 30.0, self)
				if bool(ProfileManager.get_setting("screenshake_enabled", true)):
					VFXManager.screen_shake(10, 0.4)
			node.queue_free()
			_mega = {}
			return
	# Esquivé : sorti par le bas -> triple tirage de cristaux d'esquive.
	if pos.y - radius > viewport_size.y:
		for _i in range(3):
			_award_dodge_crystal(pos)
		node.queue_free()
		_mega = {}

# =============================================================================
# PISCINE DE DÉFLATION (bande pleine largeur : ÷ ressource + valeurs adaptées)
# =============================================================================

func _spawn_deflation_pool() -> void:
	if not _deflation.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var height: float = maxf(80.0, float(_cfg.get("deflation_zone_height_px", 220.0)))
	var node := Node2D.new()
	node.name = "DeflationPool"
	node.z_as_relative = false
	node.z_index = -6
	var asset_path: String = str(_cfg.get("deflation_pool_asset", ""))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2(viewport_size.x / tex_size.x, height / tex_size.y)
			node.add_child(sprite)
	if node.get_child_count() == 0:
		# PH : bande bleue translucide.
		var rect := ColorRect.new()
		rect.color = Color("#39A8FF55")
		rect.size = Vector2(viewport_size.x, height)
		rect.position = Vector2(-viewport_size.x * 0.5, -height * 0.5)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(rect)
	var divisor: float = maxf(2.0, _gen_f("deflation_divisor", 10.0))
	var label := Label.new()
	label.text = "÷%d" % int(round(divisor))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 46)
	label.add_theme_color_override("font_color", Color("#D8F6FF"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(viewport_size.x, height)
	label.position = Vector2(-viewport_size.x * 0.5, -height * 0.5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	node.global_position = Vector2(viewport_size.x * 0.5, -height * 0.5 - 40.0)
	add_child(node)
	_deflation = { "node": node, "height": height, "consumed": false }

func _update_deflation_pool(delta: float) -> void:
	if _deflation.is_empty():
		return
	var node: Node2D = _deflation.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		_deflation = {}
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var speed: float = maxf(10.0, float(_cfg.get("default_door_speed", 170.0))) * _speed_mult
	node.global_position.y += speed * delta
	var height: float = float(_deflation.get("height", 220.0))
	# Passage obligé : la bande couvre tout l'écran — le vaisseau la traverse.
	if not bool(_deflation.get("consumed", false)) and _player and is_instance_valid(_player) \
		and absf(node.global_position.y - _player.global_position.y) <= height * 0.5:
		_deflation["consumed"] = true
		_apply_deflation()
	if node.global_position.y - height * 0.5 > viewport_size.y + 60.0:
		node.queue_free()
		_deflation = {}

## Déflation : divise la ressource ET adapte tout ce qui reste du round (events
## non dispatchés, drones vivants, cible) — le risk/reward tient au niveau bas.
func _apply_deflation() -> void:
	var divisor: float = maxf(2.0, _gen_f("deflation_divisor", 10.0))
	if _player and is_instance_valid(_player) and _player.has_method("apply_gate_operation"):
		_player.call("apply_gate_operation", "divide", divisor)
	for i in range(_next_event_idx, _events.size()):
		var data_v: Variant = (_events[i] as Dictionary).get("data", {})
		if not (data_v is Dictionary):
			continue
		var data: Dictionary = data_v as Dictionary
		match str((_events[i] as Dictionary).get("kind", "")):
			"gate":
				for side in ["left", "center", "right"]:
					var door_v: Variant = data.get(side, {})
					if door_v is Dictionary and not (door_v as Dictionary).is_empty():
						var op: String = str((door_v as Dictionary).get("operation", ""))
						if op == "add" or op == "subtract":
							(door_v as Dictionary)["value"] = maxf(1.0, round(float((door_v as Dictionary).get("value", 0.0)) / divisor))
			"swarm", "wall":
				data["total_value"] = maxf(1.0, float(data.get("total_value", 1.0)) / divisor)
			"target":
				data["target_value"] = maxf(1.0, round(float(data.get("target_value", 1.0)) / divisor))
			_:
				pass
	# Drones déjà en vol : leur menace suit (le label global se recalcule).
	for entry in _drones:
		if entry is Dictionary:
			(entry as Dictionary)["pv"] = maxf(1.0, float((entry as Dictionary).get("pv", 1.0)) / divisor)
	if _target_pending:
		_target_value = maxf(1.0, round(_target_value / divisor))
		if _target_label and is_instance_valid(_target_label):
			_target_label.text = LocaleManager.translate("gate_runner_target") % NumberFormat.compact(_target_value)
	if VFXManager and _player and is_instance_valid(_player):
		var deflation_text: String = _translate_or("gate_runner_deflation", "DEFLATION ÷%d") % int(round(divisor))
		VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -100.0),
			deflation_text, Color("#7FD8FF"), self)

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
	# Taille data (+25 % le 2026-07-12 : 44 -> 55) : lisibilité de la menace.
	_value_label.add_theme_font_size_override("font_size", maxi(10, int(_cfg.get("swarm_value_label_font_size", 55))))
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
	_value_label.text = NumberFormat.compact(_global_value)
	_value_label.visible = true

# =============================================================================
# JACKPOT FINAL + CLONE DORÉ (résolutions de fin de round)
# =============================================================================

## Petit label persistant sous la CIBLE : le jackpot est annoncé dès le début
## (empiler les × pour dépasser le cap devient une stratégie de round).
func _ensure_jackpot_label() -> void:
	if _jackpot_label and is_instance_valid(_jackpot_label):
		return
	_jackpot_label = Label.new()
	_jackpot_label.name = "JackpotLabel"
	_jackpot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_jackpot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_jackpot_label.add_theme_font_size_override("font_size", 22)
	_jackpot_label.add_theme_color_override("font_color", Color("#FFD866"))
	_jackpot_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_jackpot_label.add_theme_constant_override("outline_size", 4)
	_jackpot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jackpot_label.z_as_relative = false
	_jackpot_label.z_index = 60
	add_child(_jackpot_label)
	var viewport_size: Vector2 = get_viewport_rect().size
	_jackpot_label.size = Vector2(viewport_size.x, 30.0)
	_jackpot_label.position = Vector2(0.0, viewport_size.y * 0.115)
	_jackpot_label.text = _translate_or("gate_runner_jackpot_active", "JACKPOT ON")

## Fin de round : l'excédent au-delà de max_hp est CONVERTI (cash-out) en score
## + cristaux, puis la ressource redescend à max_hp (resync essaim/label via
## une opération neutre).
func _grant_jackpot() -> void:
	if not _jackpot_active or _player == null or not is_instance_valid(_player):
		return
	var max_hp: int = int(_player.get("max_hp"))
	var overflow: int = int(_player.get("current_hp")) - max_hp
	if overflow <= 0:
		return
	var at: Vector2 = _player.global_position
	if _game and is_instance_valid(_game):
		var score: int = int(round(float(overflow) * maxf(0.0, _gen_f("jackpot_score_per_hp", 2.0)) \
			* maxf(0.0, float(_config.get("reward_multiplier", 1.0)))))
		if score > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", score, at)
		var crystals: int = clampi(int(float(overflow) / maxf(1.0, _gen_f("jackpot_hp_per_crystal", 50.0))),
			1, maxi(1, int(_gen_f("jackpot_crystals_max", 12.0))))
		if _game.has_method("spawn_reward_crystals_from_top"):
			_game.call("spawn_reward_crystals_from_top", crystals)
	_player.set("current_hp", max_hp)
	if _player.has_method("apply_gate_operation"):
		_player.call("apply_gate_operation", "add", 0.0) # resync essaim + label
	if VFXManager:
		VFXManager.spawn_floating_text(at + Vector2(0.0, -110.0),
			_translate_or("gate_runner_jackpot_hit", "JACKPOT! +%s") % NumberFormat.compact(float(overflow)),
			Color("#FFD866"), self)

## Premier contact subi du round : le clone doré explose, le bonus est perdu.
func _lose_golden_clone() -> void:
	if not _golden_clone_active:
		return
	_golden_clone_active = false
	if _player and is_instance_valid(_player):
		if VFXManager:
			VFXManager.spawn_impact(_player.global_position, 22.0, self)
		if _player.has_method("set_gate_runner_golden_clone"):
			_player.call("set_gate_runner_golden_clone", false)

## Round parfait : le clone doré a survécu -> pluie de cristaux.
func _grant_golden_clone_reward() -> void:
	if not _golden_clone_active:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("has_gate_runner_golden_clone") \
		and not bool(_player.call("has_gate_runner_golden_clone")):
		return
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", maxi(1, int(_gen_f("golden_clone_crystals", 6.0))))
	if VFXManager:
		VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -80.0),
			_translate_or("gate_runner_golden_clone", "GOLDEN CLONE SAVED!"), Color("#FFD866"), self)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	# Résolutions de fin de round AVANT la restauration du mode joueur (le
	# jackpot lit/écrit la ressource, le clone doré vérifie l'essaim).
	_grant_golden_clone_reward()
	_grant_jackpot()
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
