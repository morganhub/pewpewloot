# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhaseGateGauntlet
## Phase « gate_gauntlet » (spec final_boss.md §5.2 #4) : des PAIRES DE PORTES
## (panneaux gauche/droite ×2 vert / ÷2 rouge, valeur affichée) glissent du
## boss vers le plan du joueur. Au passage du plan, le côté où se trouve le
## VAISSEAU s'applique : buff (mult_good) ou malus (mult_bad) de dégâts
## temporisé (mode.apply_damage_buff — consommé par les tirs). Le boss
## continue d'arroser (harcèlement) — citation directe du gate_runner 2D.

var _gates: Array = [] # {root, good_side (-1 gauche | 1 droite), z, resolved}
var _spawn_timer: float = 2.0
var _harass_timer: float = 2.5
var _gate_y: float = 2.0
var _plane_z: float = 5.5
var _boss_front_z: float = -4.5
var _half_width: float = 3.0

func _on_setup() -> void:
	var plane: Dictionary = mode.plane_config()
	_plane_z = float(plane.get("z", 5.5))
	_half_width = maxf(1.0, float(plane.get("half_width", 3.4)) - 0.3)
	_gate_y = (float(plane.get("y_min", 1.1)) + float(plane.get("y_max", 3.3))) * 0.5
	_boss_front_z = mode.get_boss_position().z + 1.6
	_spawn_timer = 1.5
	_harass_timer = 2.5

func tick(delta: float) -> void:
	_tick_harass(delta)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = maxf(2.0, float(params.get("gate_interval_sec", 6.0)))
		if _gates.size() < int(params.get("max_gates", 3)):
			_spawn_gate_pair()
	var speed := maxf(0.5, float(params.get("gate_speed_z", 2.4)))
	for i in range(_gates.size() - 1, -1, -1):
		var gate: Dictionary = _gates[i]
		var root := gate["root"] as Node3D
		if root == null or not is_instance_valid(root):
			_gates.remove_at(i)
			continue
		var z := float(gate["z"]) + speed * delta
		gate["z"] = z
		root.position.z = z
		# Passage du plan : le CÔTÉ du vaisseau décide (une seule résolution).
		if not bool(gate["resolved"]) and z >= _plane_z:
			gate["resolved"] = true
			_resolve_gate(gate)
		if z > _plane_z + 1.5:
			root.queue_free()
			_gates.remove_at(i)

func _resolve_gate(gate: Dictionary) -> void:
	var ship_side := -1.0 if mode.get_ship_position().x < 0.0 else 1.0
	var good := ship_side == float(gate["good_side"])
	var duration := maxf(1.0, float(params.get("buff_duration_sec", 8.0)))
	if good:
		mode.apply_damage_buff(maxf(1.0, float(params.get("mult_good", 2.0))), duration)
		mode.show_phase_toast("×" + str(int(float(params.get("mult_good", 2.0)))),
			mode._tr_key("final_boss_buff_good", "DÉGÂTS BOOSTÉS !"))
	else:
		mode.apply_damage_buff(clampf(float(params.get("mult_bad", 0.5)), 0.05, 1.0), duration)
		mode.show_phase_toast("÷" + str(int(round(1.0 / maxf(0.05, float(params.get("mult_bad", 0.5)))))),
			mode._tr_key("final_boss_buff_bad", "Dégâts réduits..."))

## Paire de panneaux pleine largeur : côté BON (vert, ×N) tiré au hasard,
## l'autre = MALUS (rouge, ÷N). Valeurs lisibles en Label3D.
func _spawn_gate_pair() -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, _gate_y, _boss_front_z)
	mode.world_node().add_child(root)
	var good_side := -1.0 if randf() < 0.5 else 1.0
	var height := 2.4
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var is_good: bool = side == good_side
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(_half_width - 0.12, height, 0.1)
		panel.mesh = box
		var color := Color(str(params.get("panel_good_color", "#3FBF6A"))) if is_good \
			else Color(str(params.get("panel_bad_color", "#E8553B")))
		color.a = clampf(float(params.get("panel_alpha", 0.3)), 0.08, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		panel.material_override = mat
		panel.position = Vector3(side * _half_width * 0.5, 0.0, 0.0)
		root.add_child(panel)
		var label := Label3D.new()
		var mult_good := int(maxf(1.0, float(params.get("mult_good", 2.0))))
		var div_bad := int(round(1.0 / clampf(float(params.get("mult_bad", 0.5)), 0.05, 1.0)))
		label.text = ("×" + str(mult_good)) if is_good else ("÷" + str(div_bad))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 220
		label.pixel_size = 0.005
		label.outline_size = 36
		label.position = Vector3(side * _half_width * 0.5, 0.2, 0.15)
		root.add_child(label)
	_gates.append({ "root": root, "good_side": good_side, "z": _boss_front_z, "resolved": false })

## Le boss continue d'arroser pendant les portes.
func _tick_harass(delta: float) -> void:
	_harass_timer -= delta
	if _harass_timer > 0.0:
		return
	_harass_timer = maxf(1.0, float(params.get("harass_interval_sec", 4.0)))
	var count := clampi(int(params.get("harass_count", 2)), 1, 6)
	var to_ship: Vector3 = (mode.get_ship_position() - mode.get_boss_position()).normalized()
	for i in range(count):
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		mode.spawn_boss_bullet(to_ship.rotated(Vector3.UP, t * 0.22), params)

func cleanup() -> void:
	for gate in _gates:
		var root := (gate as Dictionary).get("root") as Node
		if root and is_instance_valid(root):
			root.queue_free()
	_gates.clear()
