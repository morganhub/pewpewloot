# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhasePongDuel
## Phase « pong_duel » (spec final_boss.md §5.2 #2, revue au test du 23/07) :
## le boss sert une BOULE 3D qui voyage entre lui et le plan du joueur.
## Rebonds UNIQUEMENT en X sur deux MURS LATÉRAUX VISIBLES (pas de rebond
## haut/bas — la balle vole à hauteur constante) ; le joueur la RATTRAPE en
## s'alignant en X (raquette) : renvoi avec angle selon le point d'impact
## (recette du pong 2D). Balle au but côté boss = damage_segment_by_share
## (ball_hit_damage_share — ~3 renvois gagnants vident le segment). Balle
## manquée = miss_damage_percent au joueur puis re-service. Un HARCÈLEMENT de
## projectiles ennemis continue en fond (à esquiver — demande utilisateur).

var _ball: MeshInstance3D = null
var _walls: Array = []
var _ball_pos: Vector3 = Vector3.ZERO
var _ball_vel: Vector3 = Vector3.ZERO
var _ball_speed: float = 8.0
var _serving: float = 0.0 # > 0 : délai avant le prochain service
var _harass_timer: float = 2.0
var _ball_y: float = 2.0
var _half_width: float = 3.0
var _plane_z: float = 5.5
var _boss_front_z: float = -4.5
# Terrain borné au FRUSTUM caméra (retour test 24/07 : balle invisible sur les
# côtés) : demi-largeur VISIBLE au plan joueur (near) et côté boss (far) —
# les murs suivent ce cône, la balle ne sort jamais de l'écran.
var _bound_near: float = 3.0
var _bound_far: float = 3.0

func _on_setup() -> void:
	var plane: Dictionary = mode.plane_config()
	_plane_z = float(plane.get("z", 5.5))
	_half_width = maxf(1.0, float(plane.get("half_width", 3.4)) - 0.2)
	_ball_y = (float(plane.get("y_min", 1.1)) + float(plane.get("y_max", 3.3))) * 0.5
	_boss_front_z = mode.get_boss_position().z + 1.4
	_ball_speed = maxf(2.0, float(params.get("ball_speed", 8.0)))
	_bound_near = _visible_half_x(_plane_z)
	_bound_far = _visible_half_x(_boss_front_z)
	_build_ball()
	_build_walls()
	_serving = maxf(0.2, float(params.get("serve_delay_sec", 1.0)))
	_harass_timer = 2.0

## Demi-largeur monde VISIBLE à la profondeur z (bord d'écran - marge px),
## clampée au terrain logique. Fallback : demi-largeur du plan.
func _visible_half_x(z: float) -> float:
	var cam: Camera3D = mode.camera_node()
	if cam == null:
		return _half_width
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	var pad := maxf(0.0, float(params.get("wall_screen_pad_px", 40.0)))
	var depth := absf(cam.global_position.z - z)
	var edge: Vector3 = cam.project_position(Vector2(vp.x - pad, vp.y * 0.5), depth)
	return clampf(absf(edge.x), 0.8, _half_width)

## Demi-largeur jouable à la profondeur z (interpolation near/far du cône).
func _half_at(z: float) -> float:
	var t := clampf((z - _boss_front_z) / maxf(0.01, _plane_z - _boss_front_z), 0.0, 1.0)
	return lerpf(_bound_far, _bound_near, t)

func _build_ball() -> void:
	_ball = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var radius := maxf(0.1, float(params.get("ball_radius", 0.32)))
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	_ball.mesh = mesh
	_ball.material_override = mode.shared_unshaded(Color(str(params.get("ball_color", "#8FE8FF"))))
	_ball.visible = false
	mode.world_node().add_child(_ball)

## Deux murs latéraux SEMI-TRANSPARENTS : le contexte « terrain de pong » se
## lit immédiatement (demande utilisateur — murs virtuels sur les côtés).
func _build_walls() -> void:
	var wall_color := Color(str(params.get("wall_color", "#F58A2A")))
	wall_color.a = clampf(float(params.get("wall_alpha", 0.22)), 0.05, 1.0)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.albedo_color = wall_color
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Murs INCLINÉS suivant le cône de visibilité (far -> near) : ils marquent
	# exactement la zone où la balle reste À L'ÉCRAN.
	for side in [-1.0, 1.0]:
		var a := Vector3(side * _bound_far, _ball_y, _boss_front_z)
		var b := Vector3(side * _bound_near, _ball_y, _plane_z + 0.4)
		var d := b - a
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 2.6, d.length())
		wall.mesh = box
		wall.material_override = wall_mat
		wall.position = (a + b) * 0.5
		wall.rotation.y = atan2(d.x, d.z)
		mode.world_node().add_child(wall)
		_walls.append(wall)

func tick(delta: float) -> void:
	_tick_harass(delta)
	if _serving > 0.0:
		_serving -= delta
		if _serving <= 0.0:
			_serve()
		return
	if _ball == null or not is_instance_valid(_ball):
		return
	_ball_pos += _ball_vel * delta
	# Rebond latéral sur les murs du cône visible (X uniquement — jamais
	# haut/bas) : la limite dépend de la profondeur (_half_at).
	var limit := _half_at(_ball_pos.z) - 0.15
	if absf(_ball_pos.x) >= limit:
		_ball_pos.x = clampf(_ball_pos.x, -limit, limit)
		_ball_vel.x = -_ball_vel.x
	# Côté joueur : rattrapée (alignement X) ou manquée.
	if _ball_vel.z > 0.0 and _ball_pos.z >= _plane_z:
		var paddle_half := maxf(0.2, float(params.get("paddle_half_width", 0.75)))
		var ship: Vector3 = mode.get_ship_position()
		if absf(_ball_pos.x - ship.x) <= paddle_half:
			# Renvoi : angle selon le point d'impact (recette pong), accélération.
			var t := clampf((_ball_pos.x - ship.x) / paddle_half, -1.0, 1.0)
			_ball_speed *= maxf(1.0, float(params.get("ball_speed_up", 1.06)))
			var lat := maxf(0.5, float(params.get("lateral_max_speed", 5.0)))
			_ball_vel = Vector3(t * lat, 0.0, -1.0).normalized() * _ball_speed
			_ball_pos.z = _plane_z - 0.05
		else:
			mode.apply_player_damage(clampf(float(params.get("miss_damage_percent", 15)), 0.0, 100.0))
			_ball.visible = false
			if not mode.is_fighting():
				return
			_serving = maxf(0.2, float(params.get("serve_delay_sec", 1.0)))
			return
	# Côté boss : impact = gros dégâts au segment, la balle repart vers le joueur.
	if _ball_vel.z < 0.0 and _ball_pos.z <= _boss_front_z:
		mode.damage_segment_by_share(clampf(float(params.get("ball_hit_damage_share", 0.34)), 0.01, 1.0))
		var ship_x: float = mode.get_ship_position().x
		var aim_t := clampf((ship_x - _ball_pos.x) / maxf(1.0, _half_width), -1.0, 1.0)
		var lat2 := maxf(0.5, float(params.get("lateral_max_speed", 5.0)))
		_ball_vel = Vector3(aim_t * lat2 * 0.7, 0.0, 1.0).normalized() * _ball_speed
		_ball_pos.z = _boss_front_z + 0.05
	# Spin décoratif + position.
	_ball.rotation += Vector3(2.2, 3.1, 1.7) * delta
	_ball.position = _ball_pos

## Service depuis le boss, visé vers la position courante du joueur.
func _serve() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	_ball_speed = maxf(2.0, float(params.get("ball_speed", 8.0)))
	var boss: Vector3 = mode.get_boss_position()
	_ball_pos = Vector3(boss.x, _ball_y, _boss_front_z + 0.1)
	var ship_x: float = mode.get_ship_position().x
	var aim_t := clampf((ship_x - _ball_pos.x) / maxf(1.0, _half_width), -1.0, 1.0)
	var lat := maxf(0.5, float(params.get("lateral_max_speed", 5.0)))
	_ball_vel = Vector3(aim_t * lat * 0.6, 0.0, 1.0).normalized() * _ball_speed
	_ball.visible = true
	_ball.position = _ball_pos

## Harcèlement : salves visées légères pendant le duel (esquive obligatoire).
func _tick_harass(delta: float) -> void:
	_harass_timer -= delta
	if _harass_timer > 0.0:
		return
	_harass_timer = maxf(1.0, float(params.get("harass_interval_sec", 3.2)))
	var count := clampi(int(params.get("harass_count", 2)), 1, 6)
	var to_ship: Vector3 = (mode.get_ship_position() - mode.get_boss_position()).normalized()
	for i in range(count):
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		mode.spawn_boss_bullet(to_ship.rotated(Vector3.UP, t * 0.22), params)

func cleanup() -> void:
	if _ball and is_instance_valid(_ball):
		_ball.queue_free()
	_ball = null
	for wall in _walls:
		if wall is Node and is_instance_valid(wall):
			(wall as Node).queue_free()
	_walls.clear()
