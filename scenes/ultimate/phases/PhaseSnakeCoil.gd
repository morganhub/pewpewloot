# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhaseSnakeCoil
## Phase « snake_coil » (spec final_boss.md §5.2 #5, revue au test du 24/07) :
## un LONG SERPENT DE CUBES 3D (5 assets GLB variés, fallback BoxMesh teinté)
## se promène en X/Y/Z dans l'arène — il APPROCHE du joueur (il grossit à
## l'écran par la perspective) puis REPART vers le fond. La tête suit une
## trajectoire sinusoïdale 3D lissée, le corps suit la trace (buffer de
## samples, recette du snake 2D). TOUS les cubes sont destructibles aux tirs
## (droit devant = visée positionnelle) ; LE DERNIER BLOC DÉTRUIT frappe le
## boss (`segment_damage_share_total` du segment). Tirs directs au boss
## absorbés (blocks_direct_damage). Harcèlement continu.

const TRAIL_STEP := 0.06

var _segments: Array = [] # {node, hits_left} — ordre tête -> queue (les morts sont retirés)
var _cube_scenes: Array = [] # PackedScene chargées (5 max)
var _trail: Array = [] # échantillons de la trace de tête (head -> queue)
var _head_pos: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _harass_timer: float = 2.5
var _plane_z: float = 5.5
var _boss_front_z: float = -4.5
var _half_width: float = 3.0
var _y_min: float = 1.1
var _y_max: float = 3.3

func _on_setup() -> void:
	blocks_direct_damage = true
	var plane: Dictionary = mode.plane_config()
	_plane_z = float(plane.get("z", 5.5))
	_half_width = maxf(1.0, float(plane.get("half_width", 3.4)) - 0.5)
	_y_min = float(plane.get("y_min", 1.1))
	_y_max = float(plane.get("y_max", 3.3))
	_boss_front_z = mode.get_boss_position().z + 1.6
	_load_cube_scenes()
	_spawn_snake()
	_harass_timer = 2.5

func _load_cube_scenes() -> void:
	var paths_v: Variant = params.get("cube_meshes", [])
	if not (paths_v is Array):
		return
	for path_v in (paths_v as Array):
		var path := str(path_v)
		if path != "" and ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is PackedScene:
				_cube_scenes.append(res)

func _spawn_snake() -> void:
	var count := clampi(int(params.get("segments", 14)), 4, 30)
	var seg_size := maxf(0.15, float(params.get("seg_size", 0.5)))
	var hits := maxi(1, int(params.get("segment_hits", 3)))
	_head_pos = Vector3(0.0, (_y_min + _y_max) * 0.5, (_boss_front_z + _plane_z) * 0.5)
	_trail.clear()
	# Trace initiale rectiligne vers le fond : le corps naît déplié.
	for i in range(count * int(maxf(1.0, float(params.get("seg_spacing", 0.55)) / TRAIL_STEP)) + 8):
		_trail.append(_head_pos + Vector3(0, 0, -TRAIL_STEP * float(i)))
	for i in range(count):
		var wrapper: Node3D = null
		if not _cube_scenes.is_empty():
			wrapper = mode.spawn_glb_prop(_cube_scenes[i % _cube_scenes.size()], seg_size)
		if wrapper == null:
			# Fallback : BoxMesh teinté (5 couleurs cyclées, data).
			wrapper = Node3D.new()
			mode.world_node().add_child(wrapper)
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3.ONE * seg_size
			mi.mesh = box
			var colors_v: Variant = params.get("cube_fallback_colors", [])
			var colors: Array = colors_v if colors_v is Array else []
			var color_s := str(colors[i % colors.size()]) if not colors.is_empty() else "#3A3F52"
			mi.material_override = mode.shared_unshaded(Color(color_s))
			wrapper.add_child(mi)
		wrapper.position = _trail[mini(i * int(float(params.get("seg_spacing", 0.55)) / TRAIL_STEP), _trail.size() - 1)]
		_segments.append({ "node": wrapper, "hits_left": hits })

func tick(delta: float) -> void:
	_tick_harass(delta)
	_t += delta
	_move_head(delta)
	_follow_trail(delta)
	_intercept_shots()

## Tête : promenade 3D lissée (sinusoïdes déphasées X/Y/Z) — l'axe Z couvre
## l'approche (le serpent grossit à l'écran) et le repli vers le fond.
func _move_head(delta: float) -> void:
	var speed := maxf(0.4, float(params.get("head_speed", 1.6)))
	var ax := _half_width - 0.2
	var ay := (_y_max - _y_min) * 0.5
	var mid_y := (_y_min + _y_max) * 0.5
	var mid_z := (_boss_front_z + _plane_z) * 0.5
	var az := (_plane_z - _boss_front_z) * 0.5 - 0.8
	var target := Vector3(
		sin(_t * 0.50) * ax * 0.7 + sin(_t * 0.23 + 1.7) * ax * 0.3,
		mid_y + sin(_t * 0.71 + 0.9) * ay * 0.8,
		mid_z + sin(_t * 0.33 + 2.1) * az)
	var to_target := target - _head_pos
	var step := to_target.normalized() * minf(speed * delta, to_target.length())
	_head_pos += step
	# Trace échantillonnée à pas fixe (recette snake 2D).
	if _trail.is_empty() or _head_pos.distance_to(_trail[0]) >= TRAIL_STEP:
		_trail.push_front(_head_pos)
		var max_len := (_segments.size() + 2) * int(maxf(1.0, float(params.get("seg_spacing", 0.55)) / TRAIL_STEP)) + 16
		while _trail.size() > max_len:
			_trail.pop_back()

## Le corps suit la trace : segment vivant k à k*spacing derrière la tête.
func _follow_trail(delta: float) -> void:
	var spacing_idx := int(maxf(1.0, float(params.get("seg_spacing", 0.55)) / TRAIL_STEP))
	for k in range(_segments.size()):
		var seg: Dictionary = _segments[k]
		var node := seg["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var idx := mini(k * spacing_idx, _trail.size() - 1)
		node.position = _trail[idx]
		node.rotation += Vector3(0.7, 1.1, 0.5) * delta # spin décoratif

## Tirs interceptés par les cubes (1 tir = 1 hit) ; cube détruit = pop ;
## LE DERNIER = dégâts au boss (share totale) — la phase se clôt.
func _intercept_shots() -> void:
	var hit_radius := maxf(0.2, float(params.get("hit_radius", 0.55)))
	for k in range(_segments.size() - 1, -1, -1):
		var seg: Dictionary = _segments[k]
		var node := seg["node"] as Node3D
		if node == null or not is_instance_valid(node):
			_segments.remove_at(k)
			continue
		var hits: Array = mode.take_shots_in_sphere(node.position, hit_radius)
		if hits.is_empty():
			continue
		seg["hits_left"] = int(seg["hits_left"]) - hits.size()
		if int(seg["hits_left"]) > 0:
			# Feedback : pop d'échelle bref.
			node.scale = Vector3.ONE * 1.25
			var tw: Tween = mode.create_tween()
			tw.tween_property(node, "scale", Vector3.ONE, 0.15)
			continue
		node.queue_free()
		_segments.remove_at(k)
		if _segments.is_empty():
			# LE DERNIER BLOC frappe le boss (demande utilisateur).
			mode.damage_segment_by_share(clampf(float(params.get("segment_damage_share_total", 1.0)), 0.05, 1.0))
			mode.show_phase_toast(mode._tr_key("final_boss_snake_broken", "SERPENT BRISÉ !"), "")
			return

func _tick_harass(delta: float) -> void:
	_harass_timer -= delta
	if _harass_timer > 0.0:
		return
	_harass_timer = maxf(1.0, float(params.get("harass_interval_sec", 4.2)))
	var count := clampi(int(params.get("harass_count", 2)), 1, 6)
	var to_ship: Vector3 = (mode.get_ship_position() - mode.get_boss_position()).normalized()
	for i in range(count):
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		mode.spawn_boss_bullet(to_ship.rotated(Vector3.UP, t * 0.22), params)

func cleanup() -> void:
	for seg in _segments:
		var node := (seg as Dictionary).get("node") as Node
		if node and is_instance_valid(node):
			node.queue_free()
	_segments.clear()
	_trail.clear()
