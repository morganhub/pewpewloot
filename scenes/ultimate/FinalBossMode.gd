extends Control
class_name FinalBossMode
## FINAL BOSS — mode 3D ultime (spec markdown/final_boss.md).
## Écran SceneSwitcher standard (Control racine) contenant le pattern 3D validé
## du projet : SubViewportContainer > SubViewport (own_world_3d) > Camera3D
## (cf. Player.gd shield / SuppressorShield.gd). Renderer gl_compatibility :
## matériaux UNSHADED + couleurs vives, aucune lumière requise.
## Layout portrait signature : boss au fond (tiers haut de l'écran), vaisseau
## sur un PLAN DE CONTRÔLE 2D (X/Y à Z fixe) en bas — finger-follow inertiel
## (recette star_drift), tir automatique. Stats réelles du vaisseau actif via
## StatsCalculator (le build/loot du joueur compte).
## Lot 1 : phase `barrage` seule — les ids de phases non implémentés sont
## sautés avec un warning (combat = barrage → victoire), cf. data/final_boss.json.

const PhaseBarrageScript = preload("res://scenes/ultimate/phases/PhaseBarrage.gd")
const PhasePongDuelScript = preload("res://scenes/ultimate/phases/PhasePongDuel.gd")
const PhaseSuikaPurgeScript = preload("res://scenes/ultimate/phases/PhaseSuikaPurge.gd")
const PhaseGateGauntletScript = preload("res://scenes/ultimate/phases/PhaseGateGauntlet.gd")
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

const HOME_SCENE_PATH := "res://scenes/HomeScreen.tscn"
const SELF_SCENE_PATH := "res://scenes/ultimate/FinalBossMode.tscn"

enum State { INTRO, FIGHT, VICTORY, DEFEAT }

# --- config / état global ---------------------------------------------------
var _cfg: Dictionary = {}
var _state: int = State.INTRO
var _elapsed: float = 0.0

# --- 3D ---------------------------------------------------------------------
var _world: SubViewport = null
var _camera: Camera3D = null
var _camera_base_pos: Vector3 = Vector3.ZERO
var _boss_root: Node3D = null
var _boss_base_pos: Vector3 = Vector3.ZERO
var _boss_mats: Array = [] # [{mat, base_color}] pour le flash de dégât
var _boss_flash_timer: float = 0.0
var _ship_root: Node3D = null
var _ship_visual: Node3D = null # GLB 3D ou quad texturé (attitude pilotée)
var _ship_is_mesh: bool = false # true = GLB (attitude euler), false = quad couché
var _ship_vel_x: float = 0.0
var _ship_vel_y: float = 0.0
var _ship_bank: float = 0.0
var _ship_pitch: float = 0.0
var _stars: Array = [] # starfield dérivant {node, speed} — la vie du décor
var _grid_lines: Array = [] # lignes de sol défilantes {node, speed}
var _debris: Array = [] # débris GLB rotatifs {node, drift, spin}
var _ambient_time: float = 0.0
var _boss_total_hp: float = 60000.0 # scalé au DPS du build (_load_player_stats)
# Esquive du boss : sidestep RÉEL (la position vivante sert aux collisions —
# le tir rate physiquement) + tilt, chance/cooldown data.
var _dodge_cd: float = 0.0
var _dodge_t: float = 999.0
var _dodge_dir: float = 1.0
# Buff de dégâts temporisé (portes gate_gauntlet : ×2 / ÷2).
var _damage_buff_mult: float = 1.0
var _damage_buff_timer: float = 0.0

# --- joueur -----------------------------------------------------------------
var _stats: Dictionary = {}
var _player_hp: float = 100.0
var _player_max_hp: float = 100.0
var _player_shield: float = 0.0
var _player_max_shield: float = 0.0
var _invuln_timer: float = 0.0
var _fire_timer: float = 0.0
var _finger_down: bool = false
var _finger_pos: Vector2 = Vector2.ZERO
var _ship_target: Vector3 = Vector3.ZERO

# --- projectiles (records légers, collisions par distance) ------------------
var _player_shots: Array = [] # {node, pos: Vector3, vel: Vector3}
var _boss_bullets: Array = [] # {node, pos, vel, damage_pct}
# Ressources PARTAGÉES des spawns runtime (performance_improvements.md §1.6 :
# un seul matériau/mesh pour des éléments répétés — jamais d'instance par node).
# NB : les matériaux du BOSS restent uniques (le flash de dégât les mute).
var _mat_cache: Dictionary = {} # color hex -> StandardMaterial3D partagé
var _shot_mesh: Mesh = null # capsule partagée des tirs joueur
var _bullet_mesh_cache: Dictionary = {} # radius -> SphereMesh partagé
var _warmup_nodes: Array = [] # instances de warmup rendues pendant l'INTRO

# --- phases -----------------------------------------------------------------
var _phase_defs: Array = []
var _phase_index: int = -1
var _phase = null # FinalBossPhaseBase
var _segment_hp: float = 0.0
var _segment_max: float = 1.0
var _crystals_earned: int = 0

# --- HUD --------------------------------------------------------------------
var _boss_bar_fill: Panel = null
var _boss_bar_full_width: float = 0.0
var _phase_label: Label = null
var _hp_fill: Panel = null
var _shield_fill: Panel = null
var _bar_full_width: float = 0.0
var _timer_label: Label = null
var _toast_label: Label = null
var _toast_hint_label: Label = null # consigne sous le titre (« ce qu'il se passe »)
var _pause_layer: Control = null
var _end_layer: Control = null

func _ready() -> void:
	# CRITIQUE : sans IGNORE, le Control racine (STOP par defaut) consomme les
	# events souris pendant la passe GUI et _unhandled_input ne recoit RIEN
	# (bug constate au test du 23/07 : vaisseau impossible a bouger a la souris).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cfg = DataManager.get_final_boss_config() if DataManager else {}
	if _cfg.is_empty():
		push_warning("[FinalBossMode] data/final_boss.json vide — retour home.")
		_go_home()
		return
	_load_player_stats()
	_register_attempt()
	_build_3d()
	# Warmup des visuels spawnés en cours de combat : shaders compilés + upload
	# GPU payés PENDANT l'intro, pas au premier tir (performance_improvements.md
	# §1.3 — le chargement ne suffit pas, il faut un premier RENDU).
	_warmup_runtime_visuals()
	# HUD + intro en DIFFÉRÉ : la taille réelle du Control (layout SceneSwitcher/
	# MarginContainer) n'est fiable qu'après la frame courante — le HUD bâti sur
	# get_viewport_rect() débordait en bas sur téléphone (cœur coupé, test 23/07).
	call_deferred("_late_setup")

func _late_setup() -> void:
	_build_hud()
	_build_pause_layer()
	var music := str(_cfg.get("music", ""))
	if music != "" and App:
		App.play_music(music)
	# Intro courte : toast du nom du boss puis phase 1.
	_show_toast(_tr_key("final_boss_name", "L'ARCHITECTE"))
	_state = State.INTRO
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		_clear_warmup_nodes()
		_state = State.FIGHT
		_start_phase(0))

## Hook SceneSwitcher (appelé avant destruction de l'écran).
func prepare_for_transition() -> void:
	get_tree().paused = false

func _exit_tree() -> void:
	get_tree().paused = false

# =============================================================================
# SETUP — stats joueur, records
# =============================================================================

func _load_player_stats() -> void:
	var ship_id := ProfileManager.get_active_ship_id() if ProfileManager else ""
	_stats = StatsCalculator.calculate_ship_stats(ship_id) if StatsCalculator else {}
	_player_max_hp = maxf(1.0, float(_stats.get("max_hp", 100)))
	_player_hp = _player_max_hp
	_player_max_shield = maxf(0.0, float(_stats.get("shield", 0)))
	_player_shield = _player_max_shield
	# HP du boss SCALÉS AU DPS RÉEL du build (retour test 23/07 : un build
	# endgame one-shotait le segment en 4 tirs). total = max(plancher JSON,
	# DPS × target_fight_sec) — durée de combat ~constante pour tous les builds.
	var boss_v: Variant = _cfg.get("boss", {})
	var boss: Dictionary = boss_v if boss_v is Dictionary else {}
	_boss_total_hp = maxf(1.0, float(boss.get("total_hp", 60000)))
	if str(boss.get("hp_mode", "fixed")) == "dps_scaled":
		var player_v: Variant = _cfg.get("player", {})
		var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
		var rate := clampf(float(_stats.get("fire_rate", 1.0)),
			float(player_cfg.get("fire_rate_min", 0.5)), float(player_cfg.get("fire_rate_max", 6.0)))
		var crit := clampf(float(_stats.get("crit_chance", 0)), 0.0, 100.0)
		var dps := maxf(1.0, float(_stats.get("power", 100))) * rate * (1.0 + crit / 100.0)
		var target_sec := maxf(30.0, float(boss.get("target_fight_sec", 420.0)))
		_boss_total_hp = maxf(_boss_total_hp, dps * target_sec)

func _register_attempt() -> void:
	if not ProfileManager:
		return
	var stats := ProfileManager.get_final_boss_stats()
	ProfileManager.update_final_boss_stats({ "attempts": int(stats.get("attempts", 0)) + 1 })

# =============================================================================
# SETUP — 3D (pattern SubViewportContainer validé du projet)
# =============================================================================

func _build_3d() -> void:
	var container := SubViewportContainer.new()
	container.name = "ViewportHost"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_world = SubViewport.new()
	_world.name = "World"
	_world.own_world_3d = true
	_world.transparent_bg = false
	_world.handle_input_locally = false
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_world)

	var arena_v: Variant = _cfg.get("arena", {})
	var arena: Dictionary = arena_v if arena_v is Dictionary else {}

	# Environnement : fond spatial uni + glow (si supporté en gl_compatibility —
	# sinon no-op silencieux, les couleurs unshaded vives suffisent).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(str(arena.get("background_color", "#0A0C14")))
	env.glow_enabled = bool(arena.get("glow_enabled", true))
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)

	# Caméra fixe portrait : boss au fond (haut d'écran), plan de jeu en bas.
	var cam_v: Variant = _cfg.get("camera", {})
	var cam_cfg: Dictionary = cam_v if cam_v is Dictionary else {}
	_camera = Camera3D.new()
	_camera.fov = clampf(float(cam_cfg.get("fov_deg", 50.0)), 20.0, 90.0)
	_world.add_child(_camera)
	var cam_pos := _vec3(cam_cfg.get("pos", [0.0, 3.2, 8.5]))
	var cam_look := _vec3(cam_cfg.get("look_at", [0.0, 2.0, -6.0]))
	_camera.look_at_from_position(cam_pos, cam_look, Vector3.UP)
	_camera.current = true
	_camera_base_pos = cam_pos

	_build_arena(arena)
	_build_boss()
	_build_ship()

func _build_arena(arena: Dictionary) -> void:
	var arena_root := Node3D.new()
	arena_root.name = "Arena"
	_world.add_child(arena_root)
	# Plateau disque facetté.
	var floor_mesh := CylinderMesh.new()
	var floor_radius := maxf(2.0, float(arena.get("floor_radius", 7.0)))
	floor_mesh.top_radius = floor_radius
	floor_mesh.bottom_radius = floor_radius
	floor_mesh.height = 0.3
	floor_mesh.radial_segments = 10 # facettes visibles = DA low-poly
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = _unshaded_cached(Color(str(arena.get("floor_color", "#1C2030"))))
	floor_inst.position = Vector3(0, -0.15, 0)
	arena_root.add_child(floor_inst)
	# Anneau accent au bord du plateau (lisibilité de l'arène — le sol sombre
	# seul disparaissait sur le fond, retour test 23/07).
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = floor_radius - 0.65
	torus.outer_radius = floor_radius - 0.45
	torus.rings = 10
	torus.ring_segments = 24
	ring.mesh = torus
	ring.material_override = _unshaded_cached(Color(str(arena.get("ring_color", "#F58A2A"))))
	ring.position = Vector3(0, 0.04, -1.0)
	arena_root.add_child(ring)
	# Piliers de fond (props primitifs, silhouette d'arène).
	var prop_color := Color(str(arena.get("prop_color", "#262C40")))
	for i in range(6):
		var a := TAU * float(i) / 6.0 + 0.26
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		var h := 1.2 + 1.6 * absf(sin(float(i) * 2.17))
		box.size = Vector3(0.5, h, 0.5)
		pillar.mesh = box
		pillar.material_override = _unshaded_cached(prop_color)
		pillar.position = Vector3(cos(a) * (floor_radius - 0.6), h * 0.5, sin(a) * (floor_radius - 0.6) - 1.0)
		arena_root.add_child(pillar)
	# Fond spatial PROFOND : planète + lune derrière le boss (échelle = la
	# profondeur se lit) + STARFIELD dérivant vers la caméra (le mouvement
	# permanent qui « fait 3D » même vaisseau immobile — retour test 23/07).
	var planet := MeshInstance3D.new()
	var planet_mesh := SphereMesh.new()
	planet_mesh.radius = 4.2
	planet_mesh.height = 8.4
	planet_mesh.radial_segments = 16
	planet_mesh.rings = 8
	planet.mesh = planet_mesh
	planet.material_override = _unshaded_cached(Color(str(arena.get("planet_color", "#2E3A66"))))
	planet.position = Vector3(-5.5, 6.5, -20.0)
	arena_root.add_child(planet)
	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 1.1
	moon_mesh.height = 2.2
	moon_mesh.radial_segments = 10
	moon_mesh.rings = 5
	moon.mesh = moon_mesh
	moon.material_override = _unshaded_cached(Color(str(arena.get("moon_color", "#F58A2A"))))
	moon.position = Vector3(5.2, 8.2, -17.0)
	arena_root.add_child(moon)
	_build_starfield(arena)

## Étoiles/poussières qui dérivent vers la caméra puis se replacent au fond —
## mesh + matériau PARTAGÉS, records légers, wrap sans allocation.
func _build_starfield(arena: Dictionary) -> void:
	var count := clampi(int(arena.get("star_count", 40)), 0, 120)
	if count <= 0:
		return
	var star_size := maxf(0.01, float(arena.get("star_size", 0.055)))
	var star_mesh := SphereMesh.new()
	star_mesh.radius = star_size
	star_mesh.height = star_size * 2.0
	star_mesh.radial_segments = 4
	star_mesh.rings = 2
	var star_mat := _unshaded_cached(Color(str(arena.get("star_color", "#BFD4FF"))))
	var speed_min := maxf(0.1, float(arena.get("star_speed_min", 1.2)))
	var speed_max := maxf(speed_min, float(arena.get("star_speed_max", 3.2)))
	for i in range(count):
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		star.material_override = star_mat
		star.position = Vector3(randf_range(-8.0, 8.0), randf_range(0.0, 7.5), randf_range(-16.0, 9.0))
		# Variété d'échelle + étirement en Z (lignes de vitesse) : les proches
		# rapides filent, les lointaines flottent — la parallaxe se LIT.
		var s := randf_range(0.6, 1.8)
		var speed := randf_range(speed_min, speed_max)
		star.scale = Vector3(s, s, s * (1.0 + speed * 0.5))
		_world.add_child(star)
		_stars.append({ "node": star, "speed": speed })
	_build_grid_lines(arena)
	_build_debris(arena)

## Lignes transversales défilant vers la caméra sur le sol (repère de vitesse
## classique) — mesh/matériau partagés, wrap sans allocation.
func _build_grid_lines(arena: Dictionary) -> void:
	var count := clampi(int(arena.get("grid_line_count", 9)), 0, 24)
	if count <= 0:
		return
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(14.0, 0.02, 0.06)
	var line_mat := _unshaded_cached(Color(str(arena.get("grid_color", "#3D4670"))))
	var speed := maxf(0.2, float(arena.get("grid_speed", 3.0)))
	for i in range(count):
		var line := MeshInstance3D.new()
		line.mesh = line_mesh
		line.material_override = line_mat
		line.position = Vector3(0.0, 0.02, -14.0 + 22.0 * float(i) / float(count))
		_world.add_child(line)
		_grid_lines.append({ "node": line, "speed": speed })

## Débris 3D RÉELS (les GLB fragments Ludo) qui dérivent en tournant à
## mi-profondeur : des vrais volumes en mouvement — l'indice de 3D le plus fort.
func _build_debris(arena: Dictionary) -> void:
	var count := clampi(int(arena.get("debris_count", 4)), 0, 8)
	var meshes_v: Variant = arena.get("debris_meshes", [])
	var paths: Array = meshes_v if meshes_v is Array else []
	if count <= 0 or paths.is_empty():
		return
	for i in range(count):
		var path := str(paths[i % paths.size()])
		if path == "" or not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		if not (res is PackedScene):
			continue
		var inst := (res as PackedScene).instantiate()
		if not (inst is Node3D):
			if inst:
				inst.queue_free()
			continue
		var node := inst as Node3D
		_force_unshaded(node) # pas de lumière : un matériau shaded rendrait noir
		node.scale = Vector3.ONE * randf_range(0.5, 0.95)
		node.position = Vector3(randf_range(-7.0, 7.0), randf_range(1.5, 6.0), randf_range(-14.0, 2.0))
		_world.add_child(node)
		_debris.append({ "node": node,
			"drift": Vector3(randf_range(-0.15, 0.15), randf_range(-0.05, 0.05), randf_range(0.35, 0.8)),
			"spin": Vector3(randf_range(-0.5, 0.5), randf_range(-0.7, 0.7), randf_range(-0.4, 0.4)) })

## AABB combinée d'une liste de MeshInstance3D dans l'espace de `inst`.
func _combined_aabb(inst: Node3D, meshes: Array) -> AABB:
	var combined := AABB()
	var first := true
	for m_v in meshes:
		var mi := m_v as MeshInstance3D
		var rel: Transform3D = inst.global_transform.affine_inverse() * mi.global_transform
		var local_aabb: AABB = mi.get_aabb()
		for i in range(8):
			var corner: Vector3 = rel * local_aabb.get_endpoint(i)
			if first:
				combined = AABB(corner, Vector3.ZERO)
				first = false
			else:
				combined = combined.expand(corner)
	return combined

## Normalise un GLB décoratif : échelle -> dimension max cible, recentré.
func _normalize_node_to_size(inst: Node3D, target_max_dim: float) -> bool:
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		meshes.append(inst)
	if meshes.is_empty():
		return false
	var combined := _combined_aabb(inst, meshes)
	var max_dim: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if max_dim <= 0.001:
		return false
	var factor := target_max_dim / max_dim
	inst.scale = Vector3.ONE * factor
	inst.position = -(combined.get_center() * factor)
	return true

## Passe tous les matériaux d'une hiérarchie en unshaded (duplication par
## surface — les GLB importés arrivent shaded, invisibles sans lumière).
func _force_unshaded(root: Node3D) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for m_v in meshes:
		var mi := m_v as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_active_material(s)
			if src is StandardMaterial3D:
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(s, mat)

## Boss placeholder Lot 1 : primitives low-poly (le mesh Blender arrive au Lot 4
## via boss.mesh — s'il est renseigné et existe, il remplace le placeholder).
func _build_boss() -> void:
	var boss_v: Variant = _cfg.get("boss", {})
	var boss: Dictionary = boss_v if boss_v is Dictionary else {}
	_boss_root = Node3D.new()
	_boss_root.name = "Boss"
	_boss_root.position = _vec3(_cfg.get("boss_position", [0.0, 2.6, -6.0]))
	_boss_base_pos = _boss_root.position
	_world.add_child(_boss_root)
	var radius := maxf(0.5, float(boss.get("radius", 1.9)))
	# Mesh dédié (GLB Ludo image->3D, cf. missing_assets_3D.md) : accepte un
	# Mesh (.tres/.res) OU une PackedScene (.glb importé). Normalisé à l'AABB
	# (échelle -> radius, centré) + matériaux passés en unshaded et enregistrés
	# pour le flash de dégât. Fallback primitives si absent/invalide.
	if _try_build_boss_mesh(str(boss.get("mesh", "")), radius):
		return
	var body_color := Color(str(boss.get("body_color", "#3A3F52")))
	var accent := Color(str(boss.get("accent_color", "#F58A2A")))
	var eye_color := Color(str(boss.get("eye_color", "#FF5C5C")))
	# Corps : sphère facettée sombre.
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = radius
	body_mesh.height = radius * 2.0
	body_mesh.radial_segments = 12
	body_mesh.rings = 6
	body.mesh = body_mesh
	body.material_override = _unshaded(body_color)
	_boss_root.add_child(body)
	_boss_mats.append({ "mat": body.material_override, "base": body_color })
	# Épaulières accent.
	for side in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(radius * 0.9, radius * 0.55, radius * 0.55)
		shoulder.mesh = sbox
		shoulder.material_override = _unshaded(accent)
		shoulder.position = Vector3(side * radius * 1.15, radius * 0.25, 0)
		shoulder.rotation.z = side * 0.3
		_boss_root.add_child(shoulder)
		_boss_mats.append({ "mat": shoulder.material_override, "base": accent })
	# Œil (point focal, face au joueur).
	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = radius * 0.28
	eye_mesh.height = radius * 0.56
	eye.mesh = eye_mesh
	eye.material_override = _unshaded(eye_color)
	eye.position = Vector3(0, radius * 0.15, radius * 0.8)
	_boss_root.add_child(eye)
	_boss_mats.append({ "mat": eye.material_override, "base": eye_color })

## Charge boss.mesh (Mesh OU PackedScene .glb) dans _boss_root. true = succès.
func _try_build_boss_mesh(mesh_path: String, target_radius: float) -> bool:
	if mesh_path == "" or not ResourceLoader.exists(mesh_path):
		return false
	var res: Resource = load(mesh_path)
	var inst: Node3D = null
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		inst = mi
	elif res is PackedScene:
		var node := (res as PackedScene).instantiate()
		if node is Node3D:
			inst = node as Node3D
		elif node != null:
			node.queue_free()
	if inst == null:
		return false
	_boss_root.add_child(inst)
	var ok := _normalize_boss_visual(inst, target_radius)
	if not ok:
		inst.queue_free()
		return false
	return true

## Normalise le visuel GLB : échelle -> diamètre 2×radius (les collisions par
## distance testent `dist <= radius`), recentré sur l'origine du boss, tous les
## matériaux passés en UNSHADED (DA flat + zéro coût lumière en
## gl_compatibility) et enregistrés dans _boss_mats pour le flash de dégât.
func _normalize_boss_visual(inst: Node3D, target_radius: float) -> bool:
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		meshes.append(inst)
	if meshes.is_empty():
		return false
	var combined := _combined_aabb(inst, meshes)
	var max_dim: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if max_dim <= 0.001:
		return false
	var scale_factor := (target_radius * 2.0) / max_dim
	inst.scale = Vector3.ONE * scale_factor
	inst.position = -(combined.get_center() * scale_factor)
	# Matériaux : duplique chaque surface en unshaded + registre pour le flash.
	for m_v in meshes:
		var mi := m_v as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_active_material(s)
			var mat: StandardMaterial3D = null
			if src is StandardMaterial3D:
				mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = Color(str((_cfg.get("boss", {}) as Dictionary).get("body_color", "#3A3F52")))
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(s, mat)
			_boss_mats.append({ "mat": mat, "base": mat.albedo_color })
	return true

## Vaisseau du joueur : billboard Sprite3D du vaisseau ACTIF (identité + zéro
## asset neuf — final_boss.md §4.3) ; mesh low-poly possible au Lot 4.
func _build_ship() -> void:
	var plane := _plane_cfg()
	_ship_root = Node3D.new()
	_ship_root.name = "PlayerShip"
	var start_y: float = lerpf(float(plane.get("y_min", 0.7)), float(plane.get("y_max", 2.7)), 0.35)
	_ship_root.position = Vector3(0.0, start_y, float(plane.get("z", 5.5)))
	_ship_target = _ship_root.position
	_world.add_child(_ship_root)
	var player_v: Variant = _cfg.get("player", {})
	var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
	# PRIORITÉ : GLB 3D du vaisseau actif (assets/ultimate/ship_<id>.glb —
	# généré Ludo image→3D, demande test 23/07 : « pas le .tres 2D, l'asset
	# 3D »). Fallback : quad billboard couché, puis prisme.
	if bool(player_cfg.get("ship_mesh_enabled", true)):
		var ship_id := ProfileManager.get_active_ship_id() if ProfileManager else ""
		var glb_path := "res://assets/ultimate/ship_" + ship_id + ".glb"
		if ship_id != "" and ResourceLoader.exists(glb_path):
			var res: Resource = load(glb_path)
			if res is PackedScene:
				var inst := (res as PackedScene).instantiate()
				if inst is Node3D:
					var node := inst as Node3D
					_force_unshaded(node)
					if _normalize_node_to_size(node, maxf(0.2, float(player_cfg.get("ship_mesh_width", 0.72)))):
						_ship_root.add_child(node)
						_ship_visual = node
						_ship_is_mesh = true
						return
					node.queue_free()
				elif inst:
					inst.queue_free()
	var tex := _active_ship_texture()
	if tex != null:
		# Quad texturé ORIENTÉ MANUELLEMENT vers la caméra (pas un billboard
		# auto : on garde la main sur le ROULIS -> banking lors des mouvements
		# latéraux, le geste qui « fait 3D » — retour test 23/07).
		var quad_inst := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var world_width := maxf(0.2, float(player_cfg.get("ship_world_width", 0.9)))
		var aspect := float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
		quad.size = Vector2(world_width, world_width * aspect)
		quad_inst.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad_inst.material_override = mat
		_ship_root.add_child(quad_inst)
		_ship_visual = quad_inst
	else:
		var fallback := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.8, 0.8, 0.3)
		fallback.mesh = prism
		fallback.material_override = _unshaded_cached(Color("#8FD8FF"))
		_ship_root.add_child(fallback)
		_ship_visual = fallback

## Texture du vaisseau actif : frame 0 du SpriteFrames `asset_anim`, sinon
## `asset` (même logique d'extraction statique que DataManager/MenuHeader).
func _active_ship_texture() -> Texture2D:
	var ship_id := ProfileManager.get_active_ship_id() if ProfileManager else ""
	var ship: Dictionary = {}
	if DataManager and DataManager.has_method("get_ship_by_id"):
		var ship_v: Variant = DataManager.call("get_ship_by_id", ship_id)
		if ship_v is Dictionary:
			ship = ship_v as Dictionary
	if ship.is_empty() and DataManager and DataManager.has_method("get_ships"):
		for s in DataManager.get_ships():
			if s is Dictionary and str((s as Dictionary).get("id", "")) == ship_id:
				ship = s as Dictionary
				break
	var visual_v: Variant = ship.get("visual", {})
	var visual: Dictionary = visual_v if visual_v is Dictionary else {}
	for key in ["asset_anim", "asset"]:
		var path := str(visual.get(key, ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		if res is Texture2D:
			return res as Texture2D
		if res is SpriteFrames:
			var frames := res as SpriteFrames
			var names: PackedStringArray = frames.get_animation_names()
			var anim: StringName = &"default"
			if not frames.has_animation(anim) and names.size() > 0:
				anim = StringName(names[0])
			if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
				return _flatten_frame(frames.get_frame_texture(anim, 0))
	return null

## Une frame de SpriteFrames est souvent un AtlasTexture (région d'une planche).
## StandardMaterial3D IGNORE la région et échantillonne l'atlas ENTIER (bug
## constaté au test : les 20 frames affichées sur le quad). On aplatit donc la
## frame en ImageTexture autonome (une fois, au build — coût derrière le fade).
func _flatten_frame(tex: Texture2D) -> Texture2D:
	if tex == null or not (tex is AtlasTexture):
		return tex
	var img: Image = tex.get_image() # get_image() d'un AtlasTexture = la région seule
	if img == null:
		return tex
	return ImageTexture.create_from_image(img)

## Matériau UNIQUE (réservé aux parts du boss : le flash de dégât mute albedo).
func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

## Matériau PARTAGÉ par couleur (arène, vaisseau fallback, projectiles) —
## batching préservé, zéro churn de matériau par spawn (§1.6 du guide perf).
func _unshaded_cached(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var mat := _unshaded(color)
	_mat_cache[key] = mat
	return mat

## Mesh partagé des balles boss par rayon (les params varient par phase mais
## sont constants pendant une phase).
func _bullet_mesh(radius: float) -> SphereMesh:
	var key := snappedf(radius, 0.001)
	if _bullet_mesh_cache.has(key):
		return _bullet_mesh_cache[key] as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	_bullet_mesh_cache[key] = mesh
	return mesh

## Rend une fois, pendant l'INTRO, chaque visuel spawné en cours de combat
## (tir joueur + balle boss de la 1re phase) : compilation shader + upload GPU
## payés derrière le toast d'intro, jamais au premier tir en jeu.
func _warmup_runtime_visuals() -> void:
	var player_v: Variant = _cfg.get("player", {})
	var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
	var warm_positions := [Vector3(1.6, 0.6, -4.0), Vector3(-1.6, 0.6, -4.0)]
	# Tir joueur.
	var shot := MeshInstance3D.new()
	shot.mesh = _shared_shot_mesh(player_cfg)
	shot.material_override = _unshaded_cached(Color(str(player_cfg.get("projectile_color", "#8FD8FF"))))
	shot.position = warm_positions[0]
	_world.add_child(shot)
	_warmup_nodes.append(shot)
	# Balle boss (params de la première phase déclarée).
	var phases := _phases_from_cfg()
	var params: Dictionary = {}
	if phases.size() > 0:
		var params_v: Variant = (phases[0] as Dictionary).get("params", {})
		params = params_v if params_v is Dictionary else {}
	var bullet := MeshInstance3D.new()
	bullet.mesh = _bullet_mesh(maxf(0.04, float(params.get("bullet_radius", 0.16))))
	bullet.material_override = _unshaded_cached(Color(str(params.get("bullet_color", "#FF9A4A"))))
	bullet.position = warm_positions[1]
	_world.add_child(bullet)
	_warmup_nodes.append(bullet)

func _clear_warmup_nodes() -> void:
	for node in _warmup_nodes:
		if node is Node and is_instance_valid(node):
			(node as Node).queue_free()
	_warmup_nodes.clear()

func _shared_shot_mesh(player_cfg: Dictionary) -> Mesh:
	if _shot_mesh == null:
		# Capsule allongée (bolt) : axe Y = direction de vol (orientée au spawn).
		var capsule := CapsuleMesh.new()
		var radius := maxf(0.03, float(player_cfg.get("projectile_radius", 0.09)))
		capsule.radius = radius
		capsule.height = maxf(radius * 2.5, float(player_cfg.get("shot_length", 0.6)))
		capsule.radial_segments = 6
		capsule.rings = 2
		_shot_mesh = capsule
	return _shot_mesh

## Basis dont l'axe Y local pointe le long de `dir` (orientation des capsules).
func _basis_align_y(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length_squared() < 0.000001:
		return Basis() if d.y >= 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(d))

func _vec3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		var a := v as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO

func _plane_cfg() -> Dictionary:
	var v: Variant = _cfg.get("control_plane", {})
	return v if v is Dictionary else {}

# =============================================================================
# HUD
# =============================================================================

func _hud_cfg() -> Dictionary:
	var v: Variant = _cfg.get("hud", {})
	return v if v is Dictionary else {}

func _build_hud() -> void:
	var hud_cfg := _hud_cfg()
	# Taille RÉELLE du Control (layout SceneSwitcher) — get_viewport_rect()
	# débordait en bas sur téléphone (cœur coupé, test 23/07). Appelé en différé.
	var vp := size
	if vp.x < 2.0 or vp.y < 2.0:
		vp = get_viewport_rect().size
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	# --- barre de boss (haut) + nom + phase ---
	var margin := 18.0
	var boss_bar_h := float(hud_cfg.get("boss_bar_height_px", 22))
	_boss_bar_full_width = vp.x - margin * 2.0
	var boss_track := Panel.new()
	boss_track.position = Vector2(margin, 54)
	boss_track.size = Vector2(_boss_bar_full_width, boss_bar_h)
	boss_track.add_theme_stylebox_override("panel", _flat_box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.25)))
	boss_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_track)
	_boss_bar_fill = Panel.new()
	_boss_bar_fill.position = Vector2.ZERO
	_boss_bar_fill.size = Vector2(_boss_bar_full_width, boss_bar_h)
	_boss_bar_fill.add_theme_stylebox_override("panel", _flat_box(Color(str(hud_cfg.get("boss_bar_color", "#F58A2A"))), Color(0, 0, 0, 0)))
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_track.add_child(_boss_bar_fill)
	var name_label := _make_label(_tr_key("final_boss_name", "L'ARCHITECTE"), int(hud_cfg.get("boss_name_font_size", 24)))
	name_label.position = Vector2(margin, 22)
	name_label.size = Vector2(_boss_bar_full_width, 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(name_label)
	_phase_label = _make_label("", int(hud_cfg.get("phase_font_size", 16)))
	_phase_label.position = Vector2(margin, 54 + boss_bar_h + 4)
	_phase_label.size = Vector2(_boss_bar_full_width, 22)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_phase_label)

	# --- barres joueur (bas) : HP + shield éventuel, avec icône (une barre
	# nue était illisible — retour test 23/07) ---
	var bar_h := float(hud_cfg.get("player_bar_height_px", 14))
	var bottom_margin := maxf(24.0, float(hud_cfg.get("bottom_margin_px", 64)))
	var hp_bar_y := vp.y - bottom_margin
	var icon_size := 22.0
	_bar_full_width = vp.x - margin * 2.0 - icon_size - 6.0
	var hp_icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/ui/icons/heart.png"):
		hp_icon.texture = load("res://assets/ui/icons/heart.png")
	hp_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	hp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hp_icon.position = Vector2(margin, hp_bar_y + bar_h * 0.5 - icon_size * 0.5)
	hp_icon.size = Vector2(icon_size, icon_size)
	hp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hp_icon)
	var hp_track := Panel.new()
	hp_track.position = Vector2(margin + icon_size + 6.0, hp_bar_y)
	hp_track.size = Vector2(_bar_full_width, bar_h)
	hp_track.add_theme_stylebox_override("panel", _flat_box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.25)))
	hp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hp_track)
	_hp_fill = Panel.new()
	_hp_fill.size = Vector2(_bar_full_width, bar_h)
	_hp_fill.add_theme_stylebox_override("panel", _flat_box(Color(str(hud_cfg.get("hp_color", "#E8553B"))), Color(0, 0, 0, 0)))
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_track.add_child(_hp_fill)
	if _player_max_shield > 0.0:
		var sh_bar_y := hp_bar_y - bar_h - 6.0
		var sh_icon := TextureRect.new()
		if ResourceLoader.exists("res://assets/ui/icons/shield.png"):
			sh_icon.texture = load("res://assets/ui/icons/shield.png")
		sh_icon.custom_minimum_size = Vector2(icon_size, icon_size)
		sh_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sh_icon.position = Vector2(margin, sh_bar_y + bar_h * 0.35 - icon_size * 0.5)
		sh_icon.size = Vector2(icon_size, icon_size)
		sh_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(sh_icon)
		var sh_track := Panel.new()
		sh_track.position = Vector2(margin + icon_size + 6.0, sh_bar_y)
		sh_track.size = Vector2(_bar_full_width, bar_h * 0.7)
		sh_track.add_theme_stylebox_override("panel", _flat_box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.25)))
		sh_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(sh_track)
		_shield_fill = Panel.new()
		_shield_fill.size = Vector2(_bar_full_width, bar_h * 0.7)
		_shield_fill.add_theme_stylebox_override("panel", _flat_box(Color(str(hud_cfg.get("shield_color", "#4FD8FF"))), Color(0, 0, 0, 0)))
		_shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh_track.add_child(_shield_fill)

	# --- timer (haut droite, sous la barre de boss) ---
	_timer_label = _make_label("0:00", int(hud_cfg.get("timer_font_size", 18)))
	_timer_label.position = Vector2(vp.x - margin - 90, 54 + boss_bar_h + 4)
	_timer_label.size = Vector2(90, 22)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_timer_label)

	# --- toast central : TITRE en gros + CONSIGNE dessous (pattern « Vague X »
	# des wave_types — chaque phase annonce ce qu'il se passe) ---
	_toast_label = _make_label("", int(hud_cfg.get("toast_font_size", 40)))
	_toast_label.set_anchors_preset(Control.PRESET_CENTER)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.position = Vector2(0, -vp.y * 0.18)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	hud.add_child(_toast_label)
	_toast_hint_label = _make_label("", int(hud_cfg.get("toast_hint_font_size", 20)))
	_toast_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_toast_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_hint_label.position = Vector2(0, -vp.y * 0.18 + float(hud_cfg.get("toast_font_size", 40)) + 14.0)
	_toast_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_hint_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_toast_hint_label.modulate.a = 0.0
	hud.add_child(_toast_hint_label)

	# --- bouton pause (coin haut-droit) ---
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.position = Vector2(vp.x - 62, 8)
	pause_btn.size = Vector2(54, 40)
	pause_btn.pressed.connect(_on_pause_pressed)
	hud.add_child(pause_btn)

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _flat_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb

func _show_toast(text: String, hint: String = "") -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.8)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
	if _toast_hint_label:
		_toast_hint_label.text = hint
		var tw2 := create_tween()
		tw2.tween_property(_toast_hint_label, "modulate:a", 1.0 if hint != "" else 0.0, 0.25)
		tw2.tween_interval(2.2)
		tw2.tween_property(_toast_hint_label, "modulate:a", 0.0, 0.4)

# =============================================================================
# PAUSE / FIN
# =============================================================================

func _build_pause_layer() -> void:
	_pause_layer = _build_overlay_panel()
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	var box := _pause_layer.get_node("Box") as VBoxContainer
	box.add_child(_make_label(_tr_key("final_boss_enter", "BOSS FINAL"), 30))
	var resume := _make_overlay_button(_tr_key("final_boss_resume", "REPRENDRE"))
	resume.pressed.connect(func() -> void:
		get_tree().paused = false
		_pause_layer.visible = false)
	box.add_child(resume)
	var abandon := _make_overlay_button(_tr_key("final_boss_abandon", "ABANDONNER"))
	abandon.pressed.connect(_go_home)
	box.add_child(abandon)

func _on_pause_pressed() -> void:
	if _state == State.VICTORY or _state == State.DEFEAT:
		return
	_pause_layer.visible = true
	get_tree().paused = true

## Panneau overlay générique : voile sombre + VBox centrée nommée "Box".
func _build_overlay_panel() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(veil)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_CENTER)
	# CENTRAGE RÉEL : sans grow BOTH, la VBox ancrée au centre pousse vers le
	# bas-droite en grandissant (menu décalé — retour test 23/07).
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(320, 0)
	layer.add_child(box)
	add_child(layer)
	return layer

## Boutons au style du jeu (mêmes assets que les menus story — UIStyle).
func _make_overlay_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 22)
	UIStyle.apply_default_button_style(b, "medium")
	UIStyle.apply_button_shadow(b, "medium")
	return b

func _show_end_screen(victory: bool) -> void:
	if _end_layer != null:
		return
	_state = State.VICTORY if victory else State.DEFEAT
	_clear_bullets()
	_end_layer = _build_overlay_panel()
	var box := _end_layer.get_node("Box") as VBoxContainer
	var title := _make_label(
		_tr_key("final_boss_victory", "ARCHITECTE VAINCU !") if victory else _tr_key("final_boss_defeat", "VAISSEAU DÉTRUIT"), 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if victory:
		box.add_child(_make_label(_tr_key("final_boss_time", "Temps : {time}").replace("{time}", _format_time(_elapsed)), 20))
	else:
		var phase_name := _phase_display_name(_phase_index)
		box.add_child(_make_label(_tr_key("final_boss_phase_reached", "Phase atteinte : {phase}").replace("{phase}", phase_name), 20))
	box.add_child(_make_label(_tr_key("final_boss_crystals_earned", "Cristaux : +{count}").replace("{count}", str(_crystals_earned)), 20))
	if victory:
		var replay := _make_overlay_button(_tr_key("final_boss_replay", "REJOUER"))
		# Relance propre : re-navigation vers la même scène (ré-instanciation).
		replay.pressed.connect(func() -> void: _goto_scene(SELF_SCENE_PATH))
		box.add_child(replay)
	else:
		var retry := _make_overlay_button(_tr_key("final_boss_retry", "RÉESSAYER"))
		retry.pressed.connect(_retry_phase)
		box.add_child(retry)
	var home := _make_overlay_button(_tr_key("final_boss_home", "MENU PRINCIPAL"))
	home.pressed.connect(_go_home)
	box.add_child(home)
	_write_end_records(victory)

func _write_end_records(victory: bool) -> void:
	if not ProfileManager:
		return
	var stats := ProfileManager.get_final_boss_stats()
	var patch := {}
	var reached := _phase_index + 1
	if victory:
		reached = _phase_defs.size()
		patch["kills"] = int(stats.get("kills", 0)) + 1
		var best := float(stats.get("best_time_sec", 0.0))
		if best <= 0.0 or _elapsed < best:
			patch["best_time_sec"] = _elapsed
	patch["best_phase_reached"] = maxi(int(stats.get("best_phase_reached", 0)), reached)
	ProfileManager.update_final_boss_stats(patch)

## Défaite : retry au CHECKPOINT de phase (final_boss.md §5.1) — HP restaurés,
## projectiles purgés, la phase courante repart de zéro.
func _retry_phase() -> void:
	if _end_layer:
		_end_layer.queue_free()
		_end_layer = null
	_player_hp = _player_max_hp
	_player_shield = _player_max_shield
	_invuln_timer = 0.0
	_clear_bullets()
	_register_attempt()
	_state = State.FIGHT
	_start_phase(_phase_index)

func _go_home() -> void:
	get_tree().paused = false
	if App:
		App.play_menu_music()
	_goto_scene(HOME_SCENE_PATH)

func _goto_scene(path: String) -> void:
	get_tree().paused = false
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.call("goto_screen", path)

# =============================================================================
# PHASES
# =============================================================================

func _start_phase(index: int) -> void:
	if _phase != null:
		_phase.cleanup()
		_phase = null
	_phase_defs = _phases_from_cfg()
	if index >= _phase_defs.size():
		_on_victory()
		return
	_phase_index = index
	_damage_buff_mult = 1.0
	_damage_buff_timer = 0.0
	var def: Dictionary = _phase_defs[index]
	var phase_id := str(def.get("id", ""))
	_segment_max = maxf(1.0, _boss_total_hp * clampf(float(def.get("hp_share", 0.1)), 0.001, 1.0))
	_segment_hp = _segment_max
	var params_v: Variant = def.get("params", {})
	var params: Dictionary = params_v if params_v is Dictionary else {}
	match phase_id:
		"barrage":
			_phase = PhaseBarrageScript.new()
		"pong_duel":
			_phase = PhasePongDuelScript.new()
		"suika_purge":
			_phase = PhaseSuikaPurgeScript.new()
		"gate_gauntlet":
			_phase = PhaseGateGauntletScript.new()
		_:
			# Phase pas encore codée : FALLBACK BARRAGE (params escaladés par
			# index) — toute la barre de boss se vide avant la victoire (retour
			# test 23/07 : « vaincu » avec la barre encore pleine).
			push_warning("[FinalBossMode] phase '" + phase_id + "' non implementee -> fallback barrage")
			_phase = PhaseBarrageScript.new()
			var base: Dictionary = {}
			for d in _phase_defs:
				if str((d as Dictionary).get("id", "")) == "barrage":
					var bp: Variant = (d as Dictionary).get("params", {})
					base = (bp as Dictionary).duplicate(true) if bp is Dictionary else {}
					break
			for key in params.keys():
				base[key] = params[key]
			var esc := 1.0 + 0.08 * float(index)
			base["bullet_speed"] = float(base.get("bullet_speed", 6.0)) * esc
			base["pattern_interval_sec"] = maxf(0.8, float(base.get("pattern_interval_sec", 2.2)) / esc)
			params = base
	_phase.setup(self, params)
	_show_toast(_phase_display_name(index), _tr_key("final_boss_phase_" + phase_id + "_hint", ""))

func _phases_from_cfg() -> Array:
	var v: Variant = _cfg.get("phases", [])
	var out: Array = []
	if v is Array:
		for entry in (v as Array):
			if entry is Dictionary:
				out.append(entry)
	return out

func _phase_display_name(index: int) -> String:
	if index < 0 or index >= _phase_defs.size():
		return ""
	var pid := str((_phase_defs[index] as Dictionary).get("id", ""))
	return _tr_key("final_boss_phase_" + pid, pid.to_upper())

func _on_phase_cleared() -> void:
	var rewards_v: Variant = _cfg.get("rewards", {})
	var rewards: Dictionary = rewards_v if rewards_v is Dictionary else {}
	var crystals := maxi(0, int(rewards.get("phase_clear_crystals", 0)))
	if crystals > 0 and ProfileManager:
		ProfileManager.add_crystals(crystals)
		_crystals_earned += crystals
	_start_phase(_phase_index + 1)

func _on_victory() -> void:
	var rewards_v: Variant = _cfg.get("rewards", {})
	var rewards: Dictionary = rewards_v if rewards_v is Dictionary else {}
	var crystals := maxi(0, int(rewards.get("kill_crystals", 0)))
	if crystals > 0 and ProfileManager:
		ProfileManager.add_crystals(crystals)
		_crystals_earned += crystals
	_show_end_screen(true)

# =============================================================================
# BOUCLE — mouvement, tir, projectiles, collisions par distance
# =============================================================================

func _process(delta: float) -> void:
	# Rattrapage borné (performance_improvements.md §4) : une frame longue ne
	# doit pas faire tunneler les balles à travers la fenêtre d'impact du plan
	# (|z - plane_z| <= 0.25) ni téléporter le vaisseau.
	delta = minf(delta, 0.1)
	# L'ambiance (starfield, bob du boss, parallaxe caméra, orientation du
	# vaisseau) tourne dans TOUS les états — la scène ne doit jamais être figée
	# (retour test 23/07 : « tout est statique, on dirait de la 2D »).
	_update_ambient(delta)
	if _state != State.FIGHT:
		return
	_elapsed += delta
	_update_ship(delta)
	_update_fire(delta)
	_update_player_shots(delta)
	_update_boss_bullets(delta)
	_update_boss_flash(delta)
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
	if _damage_buff_timer > 0.0:
		_damage_buff_timer -= delta
		if _damage_buff_timer <= 0.0:
			_damage_buff_mult = 1.0
	if _phase != null:
		_phase.tick(delta)
		if _segment_hp <= 0.0 or _phase.is_objective_done():
			_on_phase_cleared()
	_update_hud()

## Ambiance permanente : le mouvement continu qui vend la 3D.
func _update_ambient(delta: float) -> void:
	_ambient_time += delta
	# Starfield : dérive vers la caméra, wrap au fond (sans allocation).
	for star_v in _stars:
		var star: Dictionary = star_v
		var node := star["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		node.position.z += float(star["speed"]) * delta
		if node.position.z > 9.5:
			node.position = Vector3(randf_range(-8.0, 8.0), randf_range(0.0, 7.5), -16.0)
	# Grille de sol défilante (repère de vitesse).
	for line_v in _grid_lines:
		var line: Dictionary = line_v
		var lnode := line["node"] as Node3D
		if lnode == null or not is_instance_valid(lnode):
			continue
		lnode.position.z += float(line["speed"]) * delta
		if lnode.position.z > 8.0:
			lnode.position.z -= 22.0
	# Débris GLB : dérive lente + rotation continue (vrais volumes en mouvement).
	for deb_v in _debris:
		var deb: Dictionary = deb_v
		var dnode := deb["node"] as Node3D
		if dnode == null or not is_instance_valid(dnode):
			continue
		dnode.position += (deb["drift"] as Vector3) * delta
		var spin := deb["spin"] as Vector3
		dnode.rotation += spin * delta
		if dnode.position.z > 8.5:
			dnode.position = Vector3(randf_range(-7.0, 7.0), randf_range(1.5, 6.0), -14.0)
	# Boss : respiration (bob + balancement) + ESQUIVE (sidestep réel : la
	# position vivante sert aux collisions, le tir raté rate vraiment).
	if _boss_root and is_instance_valid(_boss_root):
		var boss_v: Variant = _cfg.get("boss", {})
		var boss: Dictionary = boss_v if boss_v is Dictionary else {}
		var bob := float(boss.get("bob_amplitude", 0.16))
		var bob_speed := float(boss.get("bob_speed", 1.1))
		_dodge_cd = maxf(0.0, _dodge_cd - delta)
		var dodge_x := 0.0
		var dodge_yaw := 0.0
		var dodge_dur := maxf(0.1, float(boss.get("dodge_duration_sec", 0.7)))
		if _dodge_t < dodge_dur:
			_dodge_t += delta
			# Arc aller-retour lisse (sin 0->PI) : écart puis retour au centre.
			var k := sin(PI * clampf(_dodge_t / dodge_dur, 0.0, 1.0))
			dodge_x = _dodge_dir * float(boss.get("dodge_offset", 1.5)) * k
			# ROTATION AXE Y : le mesh montre son profil pendant l'esquive —
			# la 3D du GLB se lit (retour test 23/07 : « rotation 3D, pas tilt »).
			dodge_yaw = _dodge_dir * deg_to_rad(float(boss.get("dodge_yaw_deg", 45.0))) * k
		_boss_root.position = _boss_base_pos + Vector3(dodge_x, sin(_ambient_time * bob_speed) * bob, 0)
		_boss_root.rotation.y = sin(_ambient_time * float(boss.get("sway_speed", 0.5))) \
			* deg_to_rad(float(boss.get("sway_deg", 6.0))) + dodge_yaw
	# Caméra : PARALLAXE sur la position du vaisseau — bouger latéralement
	# déplace le point de vue, les plans (starfield/planète/boss) glissent à
	# des vitesses différentes = profondeur lisible.
	if _camera and is_instance_valid(_camera) and _ship_root:
		var cam_v: Variant = _cfg.get("camera", {})
		var cam_cfg: Dictionary = cam_v if cam_v is Dictionary else {}
		var plane := _plane_cfg()
		var mid_y := (float(plane.get("y_min", 1.1)) + float(plane.get("y_max", 3.3))) * 0.5
		var target_pos := _camera_base_pos + Vector3(
			_ship_root.position.x * float(cam_cfg.get("parallax_x", 0.35)),
			(_ship_root.position.y - mid_y) * float(cam_cfg.get("parallax_y", 0.12)), 0.0)
		_camera.position = _camera.position.lerp(target_pos, 1.0 - exp(-6.0 * delta))
		_camera.look_at(_vec3(cam_cfg.get("look_at", [0.0, 2.0, -6.0])), Vector3.UP)
	# Vaisseau : sprite top-down COUCHÉ dans la perspective (pitch ship_lie_deg,
	# nez vers le boss — fini la carte plate face caméra du test 23/07) +
	# LACET en rotation dans le plan (le nez suit le mouvement) + ROULIS
	# d'ailes (rotation autour de l'axe du nez).
	if _ship_visual and is_instance_valid(_ship_visual):
		var player_v: Variant = _cfg.get("player", {})
		var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
		var lie := deg_to_rad(clampf(float(player_cfg.get("ship_lie_deg", 60.0)), 0.0, 85.0))
		var bank_max := deg_to_rad(maxf(0.0, float(player_cfg.get("bank_max_deg", 30.0))))
		var yaw_max := deg_to_rad(maxf(0.0, float(player_cfg.get("yaw_max_deg", 14.0))))
		var pitch_max := deg_to_rad(maxf(0.0, float(player_cfg.get("pitch_max_deg", 14.0))))
		var response := maxf(0.5, float(player_cfg.get("bank_response", 8.0)))
		var lateral := clampf(-_ship_vel_x * 0.12, -1.0, 1.0)
		var vertical := clampf(_ship_vel_y * 0.14, -1.0, 1.0)
		_ship_bank = lerpf(_ship_bank, lateral, 1.0 - exp(-response * delta))
		_ship_pitch = lerpf(_ship_pitch, vertical, 1.0 - exp(-response * delta))
		if _ship_is_mesh:
			# GLB 3D : base data (nez vers le boss, `ship_mesh_rotation_deg`
			# corrige l'orientation du modèle) + attitude euler complète —
			# tangage (X), lacet (Y), roulis (Z).
			var base_deg := _vec3(player_cfg.get("ship_mesh_rotation_deg", [0.0, 180.0, 0.0]))
			_ship_visual.rotation = Vector3(
				deg_to_rad(base_deg.x) - _ship_pitch * pitch_max,
				deg_to_rad(base_deg.y) + _ship_bank * yaw_max,
				deg_to_rad(base_deg.z) + _ship_bank * bank_max)
		else:
			# Quad billboard : couché dans la perspective + tangage + lacet
			# in-plane + roulis d'ailes.
			var basis := Basis()
			basis = basis.rotated(Vector3.RIGHT, -(lie - _ship_pitch * pitch_max))
			_ship_visual.transform.basis = basis
			_ship_visual.rotate_object_local(Vector3(0, 0, 1), _ship_bank * yaw_max)
			_ship_visual.rotate_object_local(Vector3(0, 1, 0), _ship_bank * bank_max)

## _input (PAS _unhandled_input) : pattern input gameplay du projet (Player,
## managers) — _unhandled_input ne recevait RIEN car ScreenRoot (MarginContainer
## STOP du SceneSwitcher) consomme les events pendant la passe GUI (test 23/07 :
## aucune interaction souris/doigt). On LIT sans consommer : les boutons HUD
## recoivent toujours leurs clics via la passe GUI.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_finger_down = (event as InputEventScreenTouch).pressed
		_finger_pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		_finger_down = true
		_finger_pos = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_finger_down = (event as InputEventMouseButton).pressed
		_finger_pos = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion and _finger_down:
		_finger_pos = (event as InputEventMouseMotion).position

## Finger-follow inertiel sur le plan de contrôle (recette star_drift §4.3) :
## le doigt cible une position (bande écran remappée), le vaisseau glisse vers
## elle en approche exponentielle bornée par max_speed.
func _update_ship(delta: float) -> void:
	var plane := _plane_cfg()
	var half_w := maxf(0.5, float(plane.get("half_width", 3.4)))
	var y_min := float(plane.get("y_min", 0.7))
	var y_max := float(plane.get("y_max", 2.7))
	if _finger_down:
		var vp := get_viewport_rect().size
		var band_top := clampf(float(plane.get("screen_band_top_ratio", 0.4)), 0.0, 1.0)
		var band_bottom := clampf(float(plane.get("screen_band_bottom_ratio", 0.96)), band_top + 0.01, 1.0)
		var nx := clampf(_finger_pos.x / maxf(1.0, vp.x), 0.0, 1.0)
		var ny := clampf(inverse_lerp(band_top, band_bottom, _finger_pos.y / maxf(1.0, vp.y)), 0.0, 1.0)
		_ship_target = Vector3((nx - 0.5) * 2.0 * half_w, lerpf(y_max, y_min, ny), float(plane.get("z", 5.5)))
	var gain := maxf(0.5, float(plane.get("follow_gain", 7.0)))
	var max_speed := maxf(1.0, float(plane.get("max_speed", 14.0)))
	var to_target := _ship_target - _ship_root.position
	var step := to_target * (1.0 - exp(-gain * delta))
	var max_step := max_speed * delta
	if step.length() > max_step:
		step = step.normalized() * max_step
	_ship_root.position += step
	_ship_root.position.x = clampf(_ship_root.position.x, -half_w, half_w)
	_ship_root.position.y = clampf(_ship_root.position.y, y_min, y_max)
	# Vitesses lissées (consommées par lacet/roulis/tangage dans _update_ambient).
	var inst_vel_x := step.x / maxf(delta, 0.0001)
	var inst_vel_y := step.y / maxf(delta, 0.0001)
	_ship_vel_x = lerpf(_ship_vel_x, inst_vel_x, 1.0 - exp(-10.0 * delta))
	_ship_vel_y = lerpf(_ship_vel_y, inst_vel_y, 1.0 - exp(-10.0 * delta))

## Tir auto vers le boss : cadence = fire_rate réel du build (clampé data),
## dégâts = power réel, crit appliqué (continuité loot — final_boss.md §4.3).
func _update_fire(delta: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	var player_v: Variant = _cfg.get("player", {})
	var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
	var rate := clampf(float(_stats.get("fire_rate", 1.0)),
		float(player_cfg.get("fire_rate_min", 0.5)), float(player_cfg.get("fire_rate_max", 6.0)))
	_fire_timer = 1.0 / maxf(0.1, rate)
	if _player_shots.size() >= int(player_cfg.get("max_projectiles", 80)):
		return
	# TIR DROIT DEVANT par défaut (visée POSITIONNELLE — s'aligner en X/Y,
	# demande test 24/07 : aide aussi la poussée des bombes suika).
	# fire_mode "auto_aim" data pour revenir à l'ancien comportement.
	var dir := Vector3(0.0, 0.0, -1.0)
	if str(player_cfg.get("fire_mode", "straight")) == "auto_aim":
		dir = (get_boss_position() - _ship_root.position).normalized()
	var speed := maxf(4.0, float(player_cfg.get("projectile_speed", 26.0)))
	# Mesh + matériau PARTAGÉS (warmés à l'intro) — zéro création de ressource
	# dans ce hot path (§1.1/§1.6 du guide perf). Capsule ORIENTÉE le long de
	# la trajectoire : le tir se lit comme un bolt laser, pas une bille.
	var node := MeshInstance3D.new()
	node.mesh = _shared_shot_mesh(player_cfg)
	node.material_override = _unshaded_cached(Color(str(player_cfg.get("projectile_color", "#8FD8FF"))))
	node.position = _ship_root.position + dir * 0.5
	node.transform.basis = _basis_align_y(dir)
	_world.add_child(node)
	_player_shots.append({ "node": node, "pos": node.position, "vel": dir * speed })

func _update_player_shots(delta: float) -> void:
	var boss_pos := get_boss_position()
	var boss_cfg_v: Variant = _cfg.get("boss", {})
	var boss_cfg: Dictionary = boss_cfg_v if boss_cfg_v is Dictionary else {}
	var boss_radius := maxf(0.5, float(boss_cfg.get("radius", 1.9)))
	var dodge_trigger := maxf(boss_radius + 0.5, float(boss_cfg.get("dodge_trigger_dist", 3.5)))
	for i in range(_player_shots.size() - 1, -1, -1):
		var shot: Dictionary = _player_shots[i]
		var pos: Vector3 = shot["pos"]
		pos += (shot["vel"] as Vector3) * delta
		shot["pos"] = pos
		var node := shot["node"] as Node3D
		if node and is_instance_valid(node):
			node.position = pos
		# Fenêtre d'esquive : à l'approche, UNE chance (par tir) que le boss
		# fasse un sidestep — la position vivante bouge, le tir rate vraiment.
		if not bool(shot.get("rolled", false)) and pos.distance_to(boss_pos) <= dodge_trigger:
			shot["rolled"] = true
			_maybe_boss_dodge(pos.x, boss_cfg)
			boss_pos = get_boss_position()
		if pos.distance_to(boss_pos) <= boss_radius:
			# Phase à mécanique exclusive (suika_purge...) : le boss absorbe les
			# tirs SANS dégât — seule la mécanique de la phase le blesse.
			if _phase == null or not bool(_phase.blocks_direct_damage):
				_damage_boss_segment()
			_free_record(shot)
			_player_shots.remove_at(i)
		elif pos.z < boss_pos.z - 4.0 or absf(pos.x) > 14.0 or pos.y < -2.0 or pos.y > 12.0:
			_free_record(shot)
			_player_shots.remove_at(i)

## Tente une esquive : cooldown + chance data ; le boss part du côté OPPOSÉ au
## tir entrant (l'arc de sidestep vit dans _update_ambient).
func _maybe_boss_dodge(shot_x: float, boss_cfg: Dictionary) -> void:
	var dodge_dur := maxf(0.1, float(boss_cfg.get("dodge_duration_sec", 0.7)))
	if _dodge_t < dodge_dur or _dodge_cd > 0.0:
		return
	if randf() >= clampf(float(boss_cfg.get("dodge_chance", 0.22)), 0.0, 1.0):
		return
	_dodge_dir = 1.0 if shot_x <= _boss_base_pos.x else -1.0
	_dodge_t = 0.0
	_dodge_cd = maxf(0.5, float(boss_cfg.get("dodge_cooldown_sec", 4.0)))

func _damage_boss_segment() -> void:
	var damage := maxf(1.0, float(_stats.get("power", 100)))
	var crit_chance := clampf(float(_stats.get("crit_chance", 0)), 0.0, 100.0)
	if randf() * 100.0 < crit_chance:
		damage *= 2.0
	damage *= _damage_buff_mult # portes gate_gauntlet (×2 / ÷2)
	_segment_hp = maxf(0.0, _segment_hp - damage)
	_flash_boss()

## Buff/malus de dégâts temporisé (gate_gauntlet) — remplace le précédent.
func apply_damage_buff(mult: float, duration: float) -> void:
	_damage_buff_mult = clampf(mult, 0.05, 10.0)
	_damage_buff_timer = maxf(0.1, duration)

func _flash_boss() -> void:
	_boss_flash_timer = 0.08
	for entry in _boss_mats:
		((entry as Dictionary)["mat"] as StandardMaterial3D).albedo_color = Color(1.6, 1.6, 1.6)

# --- Helpers PUBLICS pour les scripts de phase (scenes/ultimate/phases/) -----

## Le SubViewport 3D (les phases y ajoutent leurs nodes : balle, murs...).
func world_node() -> Node:
	return _world

## Matériau unshaded partagé par couleur (cache commun du mode).
func shared_unshaded(color: Color) -> StandardMaterial3D:
	return _unshaded_cached(color)

func plane_config() -> Dictionary:
	return _plane_cfg()

## Dégâts au joueur par une mécanique de phase (mêmes règles : dodge, invuln,
## shield d'abord). Après appel, vérifier mode.is_fighting() avant de continuer.
func apply_player_damage(percent: float) -> void:
	_hit_player(percent)

## Dégâts au segment en PART du segment (ex. 0.34 = un tiers) — balle de pong,
## kill de serpent... Flash inclus.
func damage_segment_by_share(share: float) -> void:
	_segment_hp = maxf(0.0, _segment_hp - _segment_max * clampf(share, 0.0, 1.0))
	_flash_boss()

func is_fighting() -> bool:
	return _state == State.FIGHT

## Caméra 3D (phases : bornes de visibilité du terrain — pong).
func camera_node() -> Camera3D:
	return _camera

## Toast public pour les phases (annonces de buff...).
func show_phase_toast(title: String, hint: String = "") -> void:
	_show_toast(title, hint)

## Consomme les tirs joueur dans une sphère (interception par une mécanique de
## phase — ex. bombes suika poussées par les tirs). Retourne les vélocités des
## tirs consommés (direction de poussée).
func take_shots_in_sphere(center: Vector3, radius: float) -> Array:
	var out: Array = []
	for i in range(_player_shots.size() - 1, -1, -1):
		var shot: Dictionary = _player_shots[i]
		if (shot["pos"] as Vector3).distance_to(center) <= radius:
			out.append(shot["vel"])
			_free_record(shot)
			_player_shots.remove_at(i)
	return out

func _update_boss_flash(delta: float) -> void:
	if _boss_flash_timer <= 0.0:
		return
	_boss_flash_timer -= delta
	if _boss_flash_timer <= 0.0:
		for entry in _boss_mats:
			var d := entry as Dictionary
			(d["mat"] as StandardMaterial3D).albedo_color = d["base"]

## Helper public pour les phases : projectile du boss vers `dir` (normalisé).
func spawn_boss_bullet(dir: Vector3, params: Dictionary) -> void:
	var perf_v: Variant = _cfg.get("perf", {})
	var perf: Dictionary = perf_v if perf_v is Dictionary else {}
	if _boss_bullets.size() >= int(perf.get("max_boss_bullets", 90)):
		return
	var speed := maxf(1.0, float(params.get("bullet_speed", 6.0)))
	var radius := maxf(0.04, float(params.get("bullet_radius", 0.16)))
	# Mesh (par rayon) + matériau (par couleur) PARTAGÉS — §1.6 du guide perf.
	var node := MeshInstance3D.new()
	node.mesh = _bullet_mesh(radius)
	node.material_override = _unshaded_cached(Color(str(params.get("bullet_color", "#FF9A4A"))))
	node.position = get_boss_position() + dir * 1.2
	_world.add_child(node)
	_boss_bullets.append({ "node": node, "pos": node.position, "vel": dir * speed,
		"damage_pct": clampf(float(params.get("bullet_damage_percent", 8)), 0.0, 100.0),
		"born": _ambient_time })

func _update_boss_bullets(delta: float) -> void:
	var plane_z := float(_plane_cfg().get("z", 5.5))
	var player_v: Variant = _cfg.get("player", {})
	var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
	var hit_radius := maxf(0.1, float(player_cfg.get("hit_radius", 0.35)))
	for i in range(_boss_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = _boss_bullets[i]
		var pos: Vector3 = bullet["pos"]
		pos += (bullet["vel"] as Vector3) * delta
		bullet["pos"] = pos
		var node := bullet["node"] as Node3D
		if node and is_instance_valid(node):
			node.position = pos
			# Pulse de menace (lisibilité des balles — retour test 23/07).
			var pulse := 1.0 + 0.18 * sin((_ambient_time - float(bullet.get("born", 0.0))) * 9.0)
			node.scale = Vector3.ONE * pulse
		# Fenêtre d'impact : la balle traverse le plan de contrôle.
		if absf(pos.z - plane_z) <= 0.25:
			var dx := pos.x - _ship_root.position.x
			var dy := pos.y - _ship_root.position.y
			if dx * dx + dy * dy <= hit_radius * hit_radius:
				_hit_player(float(bullet["damage_pct"]))
				# MORT : _show_end_screen -> _clear_bullets() a VIDÉ le tableau
				# pendant cette itération — continuer ferait des remove_at hors
				# bornes (crash constaté au test 23/07). On sort immédiatement.
				if _state != State.FIGHT:
					return
				_free_record(bullet)
				_boss_bullets.remove_at(i)
				continue
		if pos.z > plane_z + 2.0:
			_free_record(bullet)
			_boss_bullets.remove_at(i)

## Dégâts joueur : dodge réel du build, invuln brève, shield d'abord (règles
## communes du jeu — final_boss.md §4.3).
func _hit_player(damage_percent: float) -> void:
	if _invuln_timer > 0.0:
		return
	var dodge := clampf(float(_stats.get("dodge_chance", 0)), 0.0, 100.0)
	if randf() * 100.0 < dodge:
		return
	var player_v: Variant = _cfg.get("player", {})
	var player_cfg: Dictionary = player_v if player_v is Dictionary else {}
	_invuln_timer = maxf(0.1, float(player_cfg.get("contact_invuln_sec", 0.8)))
	var damage := _player_max_hp * damage_percent / 100.0
	if _player_shield > 0.0:
		var absorbed := minf(_player_shield, damage)
		_player_shield -= absorbed
		damage -= absorbed
	_player_hp = maxf(0.0, _player_hp - damage)
	if _ship_root:
		var tw := create_tween()
		tw.tween_property(_ship_root, "scale", Vector3.ONE * 0.8, 0.08)
		tw.tween_property(_ship_root, "scale", Vector3.ONE, 0.16)
	if _player_hp <= 0.0:
		_show_end_screen(false)

func _clear_bullets() -> void:
	for shot in _player_shots:
		_free_record(shot)
	_player_shots.clear()
	for bullet in _boss_bullets:
		_free_record(bullet)
	_boss_bullets.clear()

func _free_record(record: Dictionary) -> void:
	var node := record.get("node") as Node
	if node and is_instance_valid(node):
		node.queue_free()

# =============================================================================
# HUD refresh + helpers publics phases
# =============================================================================

func _update_hud() -> void:
	# Barre de boss = HP TOTAL restant (segments suivants pleins + segment courant).
	var total := 0.0
	var remaining := 0.0
	for i in range(_phase_defs.size()):
		var share := clampf(float((_phase_defs[i] as Dictionary).get("hp_share", 0.1)), 0.001, 1.0)
		total += share
		if i > _phase_index:
			remaining += share
		elif i == _phase_index:
			remaining += share * (_segment_hp / _segment_max)
	if _boss_bar_fill and total > 0.0:
		_boss_bar_fill.size.x = _boss_bar_full_width * clampf(remaining / total, 0.0, 1.0)
	if _phase_label:
		_phase_label.text = _phase_display_name(_phase_index)
	if _hp_fill:
		_hp_fill.size.x = _bar_full_width * clampf(_player_hp / _player_max_hp, 0.0, 1.0)
	if _shield_fill and _player_max_shield > 0.0:
		_shield_fill.size.x = _bar_full_width * clampf(_player_shield / _player_max_shield, 0.0, 1.0)
	if _timer_label:
		_timer_label.text = _format_time(_elapsed)

func _format_time(sec: float) -> String:
	var total := int(sec)
	@warning_ignore("integer_division")
	return str(total / 60) + ":" + str(total % 60).pad_zeros(2)

func get_ship_position() -> Vector3:
	return _ship_root.position if _ship_root else Vector3.ZERO

func get_boss_position() -> Vector3:
	return _boss_root.position if _boss_root else Vector3.ZERO

func _tr_key(key: String, fallback: String) -> String:
	if LocaleManager and LocaleManager.has_method("translate"):
		var t := str(LocaleManager.translate(key))
		if t != key:
			return t
	return fallback
