# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhaseSuikaPurge
## Phase « suika_purge » (spec final_boss.md §5.2 #3, revue au test du 23/07) :
## le boss largue des BOMBES qui dérivent vers le plan du joueur à hauteur
## constante. Deux bombes de MÊME NIVEAU qui se touchent FUSIONNENT (1+1→2,
## 2+2→3) ; une NIVEAU 3 s'arme puis EXPLOSE SUR LE BOSS (seule source de
## dégâts au segment — niveaux 1/2 inoffensifs pour lui, et les tirs directs
## sont absorbés via blocks_direct_damage). Les TIRS du joueur POUSSENT les
## bombes (interception take_shots_in_sphere) : on les rassemble pour forcer
## les fusions. Une bombe qui atteint le plan du joueur explose sur LUI.
## Le boss continue d'arroser (harcèlement de projectiles visés).

var _bombs: Array = [] # {node, label, level, pos, vel, arm: float (-1 = pas armée)}
var _meshes: Array = [] # SphereMesh partagés par niveau (1..3)
var _drop_timer: float = 1.5
var _harass_timer: float = 2.5
var _bomb_y: float = 2.0
var _plane_z: float = 5.5
var _boss_front_z: float = -4.5
var _half_width: float = 3.0

func _on_setup() -> void:
	blocks_direct_damage = true
	var plane: Dictionary = mode.plane_config()
	_plane_z = float(plane.get("z", 5.5))
	_half_width = maxf(1.0, float(plane.get("half_width", 3.4)) - 0.3)
	_bomb_y = (float(plane.get("y_min", 1.1)) + float(plane.get("y_max", 3.3))) * 0.5
	_boss_front_z = mode.get_boss_position().z + 1.6
	for level in range(1, 4):
		var mesh := SphereMesh.new()
		var radius := _radius_for(level)
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		_meshes.append(mesh)
	_drop_timer = 1.2
	_harass_timer = 2.5

func _radius_for(level: int) -> float:
	return maxf(0.08, float(params.get("bomb_radius_l" + str(level), 0.22 + 0.12 * float(level - 1))))

func _color_for(level: int) -> Color:
	return Color(str(params.get("bomb_color_l" + str(level), "#C25050")))

func tick(delta: float) -> void:
	_tick_harass(delta)
	_tick_drop(delta)
	var push_radius := maxf(0.2, float(params.get("push_radius", 0.5)))
	var push_impulse := maxf(0.1, float(params.get("push_impulse", 1.6)))
	for i in range(_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = _bombs[i]
		var node := bomb["node"] as Node3D
		if node == null or not is_instance_valid(node):
			_bombs.remove_at(i)
			continue
		var pos: Vector3 = bomb["pos"]
		# Bombe ARMÉE (niveau 3) : pulse puis EXPLOSION SUR LE BOSS.
		if float(bomb["arm"]) >= 0.0:
			bomb["arm"] = float(bomb["arm"]) - delta
			var k := 1.0 + 0.25 * sin(float(bomb["arm"]) * 22.0)
			node.scale = Vector3.ONE * k
			if float(bomb["arm"]) <= 0.0:
				mode.damage_segment_by_share(clampf(float(params.get("lvl3_damage_share", 0.25)), 0.01, 1.0))
				_free_bomb(i)
			continue
		# Poussée par les TIRS du joueur (consommés — ils ne traversent pas).
		var pushes: Array = mode.take_shots_in_sphere(pos, push_radius + _radius_for(int(bomb["level"])))
		for vel_v in pushes:
			bomb["vel"] = (bomb["vel"] as Vector3) + (vel_v as Vector3).normalized() * push_impulse
		# Dérive : vitesse amortie vers la vitesse de croisière (+z), murs en X.
		var vel: Vector3 = bomb["vel"]
		var cruise_z := maxf(0.1, float(params.get("bomb_speed_z", 0.55)))
		vel.z = lerpf(vel.z, cruise_z, 1.0 - exp(-0.8 * delta))
		vel.x = lerpf(vel.x, 0.0, 1.0 - exp(-0.6 * delta))
		vel.y = 0.0
		pos += vel * delta
		if absf(pos.x) >= _half_width:
			pos.x = clampf(pos.x, -_half_width, _half_width)
			vel.x = -vel.x * 0.8
		pos.y = _bomb_y
		pos.z = clampf(pos.z, _boss_front_z - 0.5, _plane_z + 0.3)
		bomb["pos"] = pos
		bomb["vel"] = vel
		node.position = pos
		node.rotation.y += 1.4 * delta
		# Atteint le plan du joueur : explose sur LUI.
		if pos.z >= _plane_z:
			mode.apply_player_damage(clampf(float(params.get("bomb_reach_damage_percent", 10)), 0.0, 100.0))
			_free_bomb(i)
			if not mode.is_fighting():
				return
			continue
	_resolve_merges()

## Fusion suika : deux bombes de MÊME niveau en contact → niveau + 1 au
## barycentre ; un niveau 3 fraîchement formé S'ARME aussitôt.
func _resolve_merges() -> void:
	var merge_mult := maxf(0.8, float(params.get("merge_dist_mult", 1.1)))
	for i in range(_bombs.size()):
		for j in range(i + 1, _bombs.size()):
			var a: Dictionary = _bombs[i]
			var b: Dictionary = _bombs[j]
			if float(a["arm"]) >= 0.0 or float(b["arm"]) >= 0.0:
				continue
			var level := int(a["level"])
			if level != int(b["level"]) or level >= 3:
				continue
			var reach := (_radius_for(level) * 2.0) * merge_mult
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			if pa.distance_to(pb) > reach:
				continue
			var mid := (pa + pb) * 0.5
			# Libère les deux (ordre décroissant pour préserver les indices).
			_free_bomb(j)
			_free_bomb(i)
			_spawn_bomb(level + 1, mid)
			return # une fusion par frame : indices sûrs, cadence lisible

func _tick_drop(delta: float) -> void:
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	_drop_timer = maxf(0.6, float(params.get("drop_interval_sec", 2.6)))
	if _bombs.size() >= int(params.get("max_bombs", 10)):
		return
	var boss: Vector3 = mode.get_boss_position()
	var x := clampf(boss.x + randf_range(-1.6, 1.6), -_half_width, _half_width)
	_spawn_bomb(1, Vector3(x, _bomb_y, _boss_front_z))

func _spawn_bomb(level: int, pos: Vector3) -> void:
	level = clampi(level, 1, 3)
	var node := MeshInstance3D.new()
	node.mesh = _meshes[level - 1]
	node.material_override = mode.shared_unshaded(_color_for(level))
	node.position = pos
	mode.world_node().add_child(node)
	# Niveau affiché sur la bombe (lisibilité — pattern labels de valeurs).
	var label := Label3D.new()
	label.text = str(level)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.004
	label.outline_size = 24
	label.position = Vector3(0, _radius_for(level) + 0.16, 0)
	node.add_child(label)
	var arm := -1.0
	if level >= 3:
		arm = maxf(0.2, float(params.get("lvl3_arm_sec", 0.6)))
	_bombs.append({ "node": node, "label": label, "level": level,
		"pos": pos, "vel": Vector3(randf_range(-0.3, 0.3), 0.0, float(params.get("bomb_speed_z", 0.55))),
		"arm": arm })

func _free_bomb(index: int) -> void:
	if index < 0 or index >= _bombs.size():
		return
	var bomb: Dictionary = _bombs[index]
	var node := bomb["node"] as Node
	if node and is_instance_valid(node):
		node.queue_free()
	_bombs.remove_at(index)

## Le boss continue d'arroser pendant la purge (demande utilisateur).
func _tick_harass(delta: float) -> void:
	_harass_timer -= delta
	if _harass_timer > 0.0:
		return
	_harass_timer = maxf(1.0, float(params.get("harass_interval_sec", 3.6)))
	var count := clampi(int(params.get("harass_count", 2)), 1, 6)
	var to_ship: Vector3 = (mode.get_ship_position() - mode.get_boss_position()).normalized()
	for i in range(count):
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		mode.spawn_boss_bullet(to_ship.rotated(Vector3.UP, t * 0.22), params)

func cleanup() -> void:
	for i in range(_bombs.size() - 1, -1, -1):
		_free_bomb(i)
	_bombs.clear()
