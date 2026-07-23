# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhaseSuikaPurge
## Phase « suika_purge » — V3 (collisions revues au test du 24/07) :
## le vaisseau TIRE DES BLOCS (niveau 1 ou 2, cadence du build × fire_rate_scale
## -60 %) qui fusionnent avec le champ. Règles :
## - Fusions IDENTIQUES uniquement (1+1=2 … 4+4=5) — TOUTES les paires en
##   contact fusionnent CHAQUE FRAME (marquage dead + rebuild : le bug
##   « une seule fusion par frame » faisait passer les blocs à travers).
## - Contact NON-identique = VRAIE COLLISION : séparation des sphères, rebond
##   des vitesses le long de la normale, SPIN imprimé aux deux — on pousse les
##   bombes pour rapprocher les identiques (un bloc tiré devient bombe du
##   champ à son premier impact).
## - Les bombes NAVIGUENT EN X/Y/Z : dérive sinusoïdale latérale ET verticale
##   (seed par bombe), croisière +z vers le joueur, murs latéraux et bornes
##   verticales en rebond.
## - L'EXPLOSION exige le NIVEAU 5 ; seules les fusions PROVOQUÉES PAR LE
##   JOUEUR (marquage tainted propagé) blessent le boss.
## - HITBOX = somme des RAYONS RÉELS par niveau (sphère visuelle = collision).

var _bombs: Array = [] # {node, level, pos, vel, spin, seed, arm, tainted, launched, dead}
var _meshes: Array = []
var _drop_timer: float = 1.2
var _harass_timer: float = 2.5
var _t: float = 0.0
var _plane_z: float = 5.5
var _boss_front_z: float = -4.5
var _half_width: float = 3.0
var _y_min: float = 1.1
var _y_max: float = 3.3

func _on_setup() -> void:
	blocks_direct_damage = true
	overrides_player_fire = true
	fire_rate_scale = clampf(float(params.get("fire_rate_scale", 0.4)), 0.05, 2.0)
	var plane: Dictionary = mode.plane_config()
	_plane_z = float(plane.get("z", 5.5))
	_half_width = maxf(1.0, float(plane.get("half_width", 3.4)) - 0.3)
	_y_min = float(plane.get("y_min", 1.1))
	_y_max = float(plane.get("y_max", 3.3))
	_boss_front_z = mode.get_boss_position().z + 1.6
	for level in range(1, 6):
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
	var defaults := [0.2, 0.28, 0.38, 0.5, 0.65]
	var fallback: float = defaults[clampi(level, 1, 5) - 1]
	return maxf(0.06, float(params.get("bomb_radius_l" + str(level), fallback)))

func _color_for(level: int) -> Color:
	var defaults := ["#B84C4C", "#D96A3A", "#F58A2A", "#FF6A4C", "#FFD24A"]
	return Color(str(params.get("bomb_color_l" + str(level), defaults[clampi(level, 1, 5) - 1])))

## TIR DÉLÉGUÉ : lance un BLOC (1 ou 2, tainted) droit devant, à la hauteur du
## vaisseau (visée positionnelle en X ET Y).
func player_fire(origin: Vector3) -> void:
	var level := 2 if randf() < clampf(float(params.get("launch_level2_chance", 0.35)), 0.0, 1.0) else 1
	var speed := maxf(2.0, float(params.get("launch_speed", 9.0)))
	_spawn_bomb(level, origin + Vector3(0, 0, -0.6), true, true, Vector3(0, 0, -speed))

func tick(delta: float) -> void:
	_t += delta
	_tick_harass(delta)
	_tick_drop(delta)
	# --- mouvement ---
	for i in range(_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = _bombs[i]
		var node := bomb["node"] as Node3D
		if node == null or not is_instance_valid(node):
			_bombs.remove_at(i)
			continue
		var pos: Vector3 = bomb["pos"]
		# NIVEAU 5 ARMÉ : pulse puis résolution (dégâts boss si tainted).
		if float(bomb["arm"]) >= 0.0:
			bomb["arm"] = float(bomb["arm"]) - delta
			node.scale = Vector3.ONE * (1.0 + 0.25 * sin(float(bomb["arm"]) * 22.0))
			if float(bomb["arm"]) <= 0.0:
				if bool(bomb["tainted"]):
					mode.damage_segment_by_share(clampf(float(params.get("lvl5_damage_share", 0.34)), 0.01, 1.0))
				_free_bomb_at(i)
			continue
		var vel: Vector3 = bomb["vel"]
		if bool(bomb["launched"]):
			pos += vel * delta
			if pos.z <= _boss_front_z:
				_free_bomb_at(i)
				continue
		else:
			# NAVIGATION X/Y/Z : croisière +z + dérive sinusoïdale latérale ET
			# verticale (seed par bombe) ; rebonds sur murs et bornes de hauteur.
			var seed_f := float(bomb["seed"])
			var cruise_z := maxf(0.1, float(params.get("bomb_speed_z", 0.5)))
			var wander_x := sin(_t * float(params.get("wander_speed", 0.8)) + seed_f) \
				* float(params.get("wander_amp_x", 0.5))
			var wander_y := sin(_t * float(params.get("wander_speed", 0.8)) * 0.7 + seed_f * 1.7) \
				* float(params.get("wander_amp_y", 0.35))
			vel.x = lerpf(vel.x, wander_x, 1.0 - exp(-0.9 * delta))
			vel.y = lerpf(vel.y, wander_y, 1.0 - exp(-0.9 * delta))
			vel.z = lerpf(vel.z, cruise_z, 1.0 - exp(-0.8 * delta))
			pos += vel * delta
			if absf(pos.x) >= _half_width:
				pos.x = clampf(pos.x, -_half_width, _half_width)
				vel.x = -vel.x * 0.8
			if pos.y <= _y_min + 0.15 or pos.y >= _y_max - 0.15:
				pos.y = clampf(pos.y, _y_min + 0.15, _y_max - 0.15)
				vel.y = -vel.y * 0.8
			pos.z = clampf(pos.z, _boss_front_z - 0.5, _plane_z + 0.3)
			if pos.z >= _plane_z:
				mode.apply_player_damage(clampf(float(params.get("bomb_reach_damage_percent", 10)), 0.0, 100.0))
				_free_bomb_at(i)
				if not mode.is_fighting():
					return
				continue
		# SPIN de collision (amorti) + rotation lente de base.
		var spin: Vector3 = bomb["spin"]
		spin = spin.lerp(Vector3.ZERO, 1.0 - exp(-1.2 * delta))
		bomb["spin"] = spin
		node.rotation += (spin + Vector3(0, 0.9, 0)) * delta
		bomb["pos"] = pos
		bomb["vel"] = vel
		node.position = pos
	_resolve_contacts()

## TOUS les contacts de la frame : fusions (identiques) + rebonds (différents).
## Fusions par marquage `dead` + rebuild du tableau — plusieurs fusions par
## frame, zéro arithmétique d'indices (le bug « à travers » venait du
## une-fusion-par-frame).
func _resolve_contacts() -> void:
	var merge_mult := maxf(0.8, float(params.get("merge_dist_mult", 1.05)))
	var bounce := clampf(float(params.get("bounce", 0.7)), 0.0, 1.0)
	var spin_kick := maxf(0.0, float(params.get("spin_kick", 3.0)))
	var spawns: Array = [] # {level, pos, tainted}
	for i in range(_bombs.size()):
		var a: Dictionary = _bombs[i]
		if bool(a["dead"]) or float(a["arm"]) >= 0.0:
			continue
		for j in range(i + 1, _bombs.size()):
			var b: Dictionary = _bombs[j]
			if bool(b["dead"]) or float(b["arm"]) >= 0.0:
				continue
			var la := int(a["level"])
			var lb := int(b["level"])
			var reach := (_radius_for(la) + _radius_for(lb)) * merge_mult
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			var dist := pa.distance_to(pb)
			if dist > reach:
				continue
			if la == lb and la < 5:
				# FUSION (identiques) — marquage, résolution après le scan.
				a["dead"] = true
				b["dead"] = true
				spawns.append({ "level": la + 1, "pos": (pa + pb) * 0.5,
					"tainted": bool(a["tainted"]) or bool(b["tainted"]) })
				break # a est consommée
			# COLLISION (différents ou niveau 5) : séparation + rebond + spin.
			var normal := (pb - pa).normalized() if dist > 0.001 else Vector3.RIGHT
			var overlap := reach - dist
			a["pos"] = pa - normal * overlap * 0.5
			b["pos"] = pb + normal * overlap * 0.5
			var va: Vector3 = a["vel"]
			var vb: Vector3 = b["vel"]
			var rel := (va - vb).dot(normal)
			if rel > 0.0:
				var impulse := normal * rel * bounce
				a["vel"] = va - impulse
				b["vel"] = vb + impulse
			var kick := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin_kick
			a["spin"] = (a["spin"] as Vector3) + kick
			b["spin"] = (b["spin"] as Vector3) - kick
			# Un bloc TIRÉ devient bombe du champ à son premier impact
			# (il rejoint la mêlée au lieu de traverser).
			if bool(a["launched"]):
				a["launched"] = false
			if bool(b["launched"]):
				b["launched"] = false
	# Purge des fusionnées + spawns des niveaux supérieurs.
	for i in range(_bombs.size() - 1, -1, -1):
		if bool((_bombs[i] as Dictionary)["dead"]):
			_free_bomb_at(i)
	for spawn in spawns:
		var s: Dictionary = spawn
		_spawn_bomb(int(s["level"]), s["pos"], bool(s["tainted"]), false,
			Vector3(0, 0, float(params.get("bomb_speed_z", 0.5)) * 0.5))

func _tick_drop(delta: float) -> void:
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	_drop_timer = maxf(0.6, float(params.get("drop_interval_sec", 2.4)))
	if _bombs.size() >= int(params.get("max_bombs", 14)):
		return
	var boss: Vector3 = mode.get_boss_position()
	var x := clampf(boss.x + randf_range(-1.8, 1.8), -_half_width, _half_width)
	var y := randf_range(_y_min + 0.3, _y_max - 0.3)
	_spawn_bomb(1, Vector3(x, y, _boss_front_z), false, false,
		Vector3(randf_range(-0.3, 0.3), 0.0, float(params.get("bomb_speed_z", 0.5))))

func _spawn_bomb(level: int, pos: Vector3, tainted: bool, launched: bool, vel: Vector3) -> void:
	level = clampi(level, 1, 5)
	var node := MeshInstance3D.new()
	node.mesh = _meshes[level - 1]
	node.material_override = mode.shared_unshaded(_color_for(level))
	node.position = pos
	mode.world_node().add_child(node)
	var label := Label3D.new()
	label.text = str(level)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.004
	label.outline_size = 24
	label.position = Vector3(0, _radius_for(level) + 0.14, 0)
	node.add_child(label)
	var arm := -1.0
	if level >= 5:
		arm = maxf(0.2, float(params.get("lvl5_arm_sec", 0.6)))
	_bombs.append({ "node": node, "level": level, "pos": pos, "vel": vel,
		"spin": Vector3.ZERO, "seed": randf() * TAU, "arm": arm,
		"tainted": tainted, "launched": launched, "dead": false })

func _free_bomb_at(index: int) -> void:
	if index < 0 or index >= _bombs.size():
		return
	var node := (_bombs[index] as Dictionary)["node"] as Node
	if node and is_instance_valid(node):
		node.queue_free()
	_bombs.remove_at(index)

## Le boss continue d'arroser pendant la purge.
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
		_free_bomb_at(i)
	_bombs.clear()
