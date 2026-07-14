extends Node2D

## SliceRushManager — Orchestre une vague "slice_rush" (inspiration Fruit
## Ninja) : le vaisseau descend se verrouiller en bas au centre (tir coupe,
## verrou X+Y gere par Player.gd) et tire un laser glowing continu vers le
## doigt pendant le geste. Des objets jaillissent du bas hors ecran en arc
## balistique (rafales irregulieres) et le joueur les tranche d'un trace
## rapide : trait fin + halo additif qui suivent le doigt. Un objet casse se
## separe en deux moities re-tranchables (score croissant par profondeur) ;
## les objets rares/legendaires demandent plusieurs passes et lachent des
## equipements de rarete >= rare (quality_mult > 10). Les bombes a aura rouge
## ne doivent PAS etre tranchees (degats % HP max, shield d'abord). Le
## vaisseau etant immobile, cristaux et drops sont aimantes automatiquement
## vers lui apres un delai. Tir coupe, contacts manuels par distance (pas de
## physics engine). Detection de slice a l'evenement drag (zero tunneling).
##
## Extension 12 juillet 2026 (wave_types_improvements) :
## - Bombes : anneau sinusoidal multi-couches procedural (Line2D fermees, data
##   bomb_ring_layers) EN PLUS de l'aura — visibilite mobile.
## - 4 objets bonus tranchables (1 max a l'ecran, cooldown + anti-repetition,
##   chances progressives) : SABLIER (bullet-time via _sim_scale), GANT DE GEL
##   (fige tout), CHRONOS (+5 s, story), EXTENSION LASER (le laser
##   vaisseau->doigt tranche, coupe sur transition d'entree en zone seulement).
## - Variantes (Libre via chances data) : BLINDES (2 coupes en croix), LIES
##   (chaine entre 2 objets — la trancher casse les deux), PRECISION (couper
##   le long de la ligne = x3), REBONDISSANTS (1 rebond sol invisible), NUEES
##   DE MINIS (burst de 6-8 petits), BOMBES LEURRES (orange = cristaux),
##   gravite lourde = data pur (score_global_mult).
## - Evenements Libre (scheduler alternant, jamais 2 a la fois, chances 0 en
##   story) : RAFALE LEGENDAIRE (1x/level), PLUIE DIAGONALE (salve laterale),
##   BOSS PINATA (10 passes, timer propre, pluie de loot), VAGUE PIEGEE
##   (5 bombes encadrant 1 legendaire).
## - COMBO FEVER (toujours actif) : 8 coupes sans manque -> 5 s de cristal
##   garanti par objet casse ; compteur discret au HUD.

signal finished

enum State { INTRO, RUN, DONE }

const STRONG_RESOURCE_CACHE_MAX: int = 64
static var _resource_cache: Dictionary = {} # path -> Resource
static var _missing_paths: Dictionary = {} # path -> true

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _obstacle_skins: Array = [] # world skin_overrides.obstacles.explosives

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 30.0
var _elapsed: float = 0.0

# Parsed sliceable types. Entries: { "id": String, "textures": Array[Texture2D],
# "weight": float, "size_px": float, "tint": Color, "slices_to_break": int,
# "score_base": int, "score_per_extra_cut": int, "crystal_chance": float,
# "drop_chance": float, "drop_count_min": int, "drop_count_max": int }
var _object_types: Array = []
var _type_weight_total: float = 0.0
var _bomb_textures: Array = []
var _bomb_aura_frames: SpriteFrames = null

# Live entities (whole objects, pieces, bombs). Entries:
# { "node": Node2D, "sprite": Sprite2D, "vel": Vector2, "radius": float,
#   "kind": String ("object"|"piece"|"bomb"), "type": Dictionary,
#   "slices_remaining": int, "depth": int, "last_slice_msec": int,
#   "spin": float, "region": Rect2, "sprite_scale": float }
var _objects: Array = []

# Burst scheduler.
var _in_burst: bool = false
var _burst_remaining: int = 0
var _spawn_timer: float = 0.35
var _bombs_in_burst: int = 0

# Finger tracking (raw touches; the ship is frozen so nothing else reads them).
var _touch_id: int = -1
var _finger_world: Vector2 = Vector2.ZERO
var _finger_prev_world: Vector2 = Vector2.ZERO

# Slice trail + ship laser (2 Line2D layers each) + slice flash pool.
var _add_material: CanvasItemMaterial = null # UNIQUE, shared by every glow
var _trail_points: Array = [] # [{ "pos": Vector2, "born_msec": int }]
var _trail_core: Line2D = null
var _trail_glow: Line2D = null
var _laser_core: Line2D = null
var _laser_glow: Line2D = null
var _flash_pool: Array = [] # [{ "node": Line2D, "tween": Tween }]

# Rewards.
var _reward_multiplier: float = 1.0
var _equipment_drops_spawned: int = 0

# Objets bonus (specials tranchables) : timers d'effets + exclusivite.
var _hourglass_time_left: float = 0.0
var _freeze_time_left: float = 0.0
var _laser_slice_time_left: float = 0.0
var _special_cooldown: float = 0.0
var _last_special_id: String = ""
var _effect_vignette: ColorRect = null
var _special_textures: Dictionary = {} # id -> Texture2D (peut manquer -> orbe PH)
# Variantes.
var _mini_swarm_cooldown: float = 0.0
var _burst_mini: bool = false
var _decoy_textures: Array = []
var _pinata_texture: Texture2D = null
var _armored_overlay_texture: Texture2D = null
# Objets lies : { "na": Node2D, "nb": Node2D, "line": Line2D }.
var _links: Array = []
# Evenements Libre : scheduler alternant + spawns scriptes differes.
var _event_timer: float = 0.0
var _last_event_id: String = ""
var _legendary_burst_done: bool = false
var _pinata_active: bool = false
var _forced_queue: Array = [] # [{ opts de _spawn_object }]
var _forced_timer: float = 0.0
# Combo fever.
var _combo_count: int = 0
var _fever_time_left: float = 0.0
var _combo_label: Label = null
# Bandeau evenement (pattern BreakoutManager).
var _event_banner: Label = null
var _banner_time: float = 0.0

var _countdown_label: Label = null
var _finished_emitted: bool = false

const FLASH_POOL_SIZE: int = 8
# Teintes des objets bonus (fallback si <id>_asset absent : orbe procedural).
const SPECIAL_TINTS: Dictionary = {
	"hourglass": "#FFD866", "freeze_glove": "#8FE8FF",
	"chronos": "#7FE58C", "laser_ext": "#B455E8"
}
const SPECIAL_CHANCE_KEYS: Dictionary = {
	"hourglass": "hourglass_chance", "freeze_glove": "freeze_glove_chance",
	"chronos": "chronos_chance", "laser_ext": "laser_slice_chance"
}
const SPECIAL_LOCALE_KEYS: Dictionary = {
	"hourglass": "slice_rush_hourglass", "freeze_glove": "slice_rush_freeze",
	"chronos": "slice_rush_chronos", "laser_ext": "slice_rush_laser"
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("slice_rush") if DataManager else {}
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []

	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("duration_sec_default", 30.0))))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	_prepare_assets()
	_setup_trail_nodes()
	_begin_player_mode()
	_begin_hud_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	_spawn_timer = 0.35 # first burst arrives quickly after the intro
	_event_timer = randf_range(
		maxf(4.0, float(_get_conf("event_interval_sec_min", 18.0))),
		maxf(4.0, float(_get_conf("event_interval_sec_max", 30.0))))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la session EN COURS est re-scalée
## au changement de level — objets en vol et combo préservés. Toutes les clés
## sont lues live via _get_conf : il suffit de les merger.
func update_free_mode_config(cfg: Dictionary) -> void:
	for key in ["bomb_chance", "burst_size_max",
		"burst_pause_sec_min", "burst_pause_sec_max",
		"bomb_damage_percent", "_free_level_progress",
		"hourglass_chance", "freeze_glove_chance", "chronos_chance",
		"laser_slice_chance", "armored_chance", "linked_chance",
		"precision_chance", "bouncy_chance", "mini_swarm_chance",
		"decoy_bomb_chance", "legendary_burst_chance", "diagonal_rain_chance",
		"pinata_chance", "trap_wave_chance", "gravity_px_sec2",
		"launch_speed_min_px_sec", "launch_speed_max_px_sec", "score_global_mult"]:
		if cfg.has(key):
			_config[key] = cfg[key]
	# Nouveau level : la rafale legendaire redevient disponible (1x/level).
	_legendary_burst_done = false

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_slice_rush"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_slice_rush", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_slice_rush"):
		_player.call("end_slice_rush")

## The power buttons swallow touches near the bottom of the screen (slice
## zone) and are useless here (no shooting); the joystick circles are noise.
func _begin_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", true)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", false)

func _restore_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", false)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", true)

# =============================================================================
# ASSETS (resolved once at setup — never load() in a gameplay frame)
# =============================================================================

static func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _resource_cache.has(path):
		return _resource_cache[path] as Resource
	if _missing_paths.has(path):
		return null
	if not ResourceLoader.exists(path):
		_missing_paths[path] = true
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res != null:
		if _resource_cache.size() >= STRONG_RESOURCE_CACHE_MAX:
			_resource_cache.clear()
		_resource_cache[path] = res
	else:
		_missing_paths[path] = true
	return res

func _prepare_assets() -> void:
	_object_types.clear()
	_type_weight_total = 0.0
	var types_v: Variant = _config.get("object_types", _cfg.get("object_types", []))
	if types_v is Array:
		for type_v in (types_v as Array):
			if not (type_v is Dictionary):
				continue
			var src: Dictionary = type_v as Dictionary
			var textures: Array = _resolve_textures(src.get("assets", []))
			if textures.is_empty():
				textures = _resolve_textures(_obstacle_skins)
			if textures.is_empty():
				continue
			var parsed: Dictionary = {
				"id": str(src.get("id", "object")),
				"textures": textures,
				"weight": maxf(0.01, float(src.get("weight", 1.0))),
				"size_px": maxf(24.0, float(src.get("size_px", 96.0))),
				"tint": Color(str(src.get("tint", "#FFFFFF"))),
				"slices_to_break": maxi(1, int(src.get("slices_to_break", 1))),
				"score_base": maxi(0, int(src.get("score_base", 20))),
				"score_per_extra_cut": maxi(0, int(src.get("score_per_extra_cut", 15))),
				"crystal_chance": clampf(float(src.get("crystal_chance", 0.1)), 0.0, 1.0),
				"drop_chance": clampf(float(src.get("drop_chance", 0.0)), 0.0, 1.0),
				"drop_count_min": maxi(1, int(src.get("drop_count_min", 1))),
				"drop_count_max": maxi(1, int(src.get("drop_count_max", 1)))
			}
			_type_weight_total += float(parsed["weight"])
			_object_types.append(parsed)

	_bomb_textures = _resolve_textures(_get_conf("bomb_assets", []))
	var aura_res: Resource = _load_cached_resource(str(_get_conf("bomb_aura_asset", "")))
	_bomb_aura_frames = aura_res as SpriteFrames if aura_res is SpriteFrames else null
	# Bonus, leurres, pinata, overlay blinde : resolus une fois (jamais en frame).
	_special_textures.clear()
	for special_id in SPECIAL_TINTS.keys():
		var sp_res: Resource = _load_cached_resource(str(_get_conf("%s_asset" % special_id, "")))
		if sp_res is Texture2D:
			_special_textures[special_id] = sp_res
	_decoy_textures = _resolve_textures(_get_conf("decoy_bomb_assets", []))
	if _decoy_textures.is_empty():
		_decoy_textures = _bomb_textures
	var pinata_res: Resource = _load_cached_resource(str(_get_conf("pinata_asset", "")))
	_pinata_texture = pinata_res as Texture2D if pinata_res is Texture2D else null
	var armored_res: Resource = _load_cached_resource(str(_get_conf("armored_overlay_asset", "")))
	_armored_overlay_texture = armored_res as Texture2D if armored_res is Texture2D else null

func _resolve_textures(paths_v: Variant) -> Array:
	var out: Array = []
	if not (paths_v is Array):
		return out
	for path_v in (paths_v as Array):
		var res: Resource = _load_cached_resource(str(path_v))
		if res is Texture2D:
			out.append(res)
	return out

func _pick_object_type() -> Dictionary:
	if _object_types.is_empty():
		return {}
	var roll: float = randf() * _type_weight_total
	for type in _object_types:
		roll -= float((type as Dictionary).get("weight", 1.0))
		if roll <= 0.0:
			return type
	return _object_types[_object_types.size() - 1]

# =============================================================================
# TRAIL / LASER / FLASH (glow = 2 layers sharing ONE additive material)
# =============================================================================

func _setup_trail_nodes() -> void:
	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_trail_glow = _build_glow_line(float(_get_conf("trail_glow_width_px", 18.0)),
		Color(str(_get_conf("trail_glow_color", "#7BD8FFB4"))), true, 55)
	_trail_core = _build_glow_line(float(_get_conf("trail_core_width_px", 4.0)),
		Color(str(_get_conf("trail_core_color", "#FFFFFF"))), false, 56)
	_laser_glow = _build_glow_line(float(_get_conf("laser_glow_width_px", 12.0)),
		Color(str(_get_conf("laser_glow_color", "#B455E87D"))), true, 53)
	_laser_core = _build_glow_line(float(_get_conf("laser_core_width_px", 3.0)),
		Color(str(_get_conf("laser_core_color", "#F3C7FF"))), false, 54)
	_laser_glow.visible = false
	_laser_core.visible = false

func _build_glow_line(width: float, color: Color, additive: bool, z: int) -> Line2D:
	var line := Line2D.new()
	line.width = maxf(1.0, width)
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_as_relative = false
	line.z_index = z
	if additive:
		line.material = _add_material
	add_child(line)
	return line

func _update_trail() -> void:
	if _trail_core == null or not is_instance_valid(_trail_core):
		return
	var lifetime_msec: int = int(maxf(0.02, float(_get_conf("trail_point_lifetime_sec", 0.16))) * 1000.0)
	var now: int = Time.get_ticks_msec()
	while not _trail_points.is_empty() and now - int(_trail_points[0].get("born_msec", 0)) > lifetime_msec:
		_trail_points.pop_front()
	if _trail_points.size() < 2:
		_trail_core.clear_points()
		_trail_glow.clear_points()
		return
	var pts := PackedVector2Array()
	for p in _trail_points:
		pts.append(to_local(p.get("pos", Vector2.ZERO)))
	_trail_core.points = pts
	_trail_glow.points = pts

func _update_laser() -> void:
	if _laser_core == null or not is_instance_valid(_laser_core):
		return
	var active: bool = _touch_id != -1 and bool(_get_conf("laser_enabled", true)) \
		and _player != null and is_instance_valid(_player)
	_laser_core.visible = active
	_laser_glow.visible = active
	if not active:
		return
	var from: Vector2 = to_local(_player.global_position + Vector2(0.0, -20.0))
	var to: Vector2 = to_local(_finger_world)
	var pts := PackedVector2Array([from, to])
	_laser_core.points = pts
	_laser_glow.points = pts
	# Extension laser : rayon élargi/recoloré tant que la lame est active.
	if _laser_slice_time_left > 0.0:
		_laser_core.width = maxf(1.0, float(_get_conf("laser_core_width_px", 3.0))) * 1.6
		_laser_glow.width = maxf(1.0, float(_get_conf("laser_glow_width_px", 12.0))) * 1.6
		_laser_core.default_color = Color(str(_get_conf("laser_slice_core_color", "#FFE7FF")))
		_laser_glow.default_color = Color(str(_get_conf("laser_slice_glow_color", "#E86BFFAA")))
	else:
		_laser_core.width = maxf(1.0, float(_get_conf("laser_core_width_px", 3.0)))
		_laser_glow.width = maxf(1.0, float(_get_conf("laser_glow_width_px", 12.0)))
		_laser_core.default_color = Color(str(_get_conf("laser_core_color", "#F3C7FF")))
		_laser_glow.default_color = Color(str(_get_conf("laser_glow_color", "#B455E87D")))

## Reusable Line2D flash along the cut (the "stronger/wider" slice mark).
func _spawn_slice_flash(a: Vector2, b: Vector2) -> void:
	var entry: Dictionary = {}
	for candidate in _flash_pool:
		var node_v: Variant = (candidate as Dictionary).get("node", null)
		if node_v is Line2D and is_instance_valid(node_v) and not (node_v as Line2D).visible:
			entry = candidate
			break
	if entry.is_empty():
		if _flash_pool.size() < FLASH_POOL_SIZE:
			var line := _build_glow_line(float(_get_conf("slice_flash_width_px", 26.0)),
				Color(str(_get_conf("slice_flash_color", "#BFF0FF"))), true, 57)
			line.visible = false
			entry = {"node": line, "tween": null}
			_flash_pool.append(entry)
		else:
			entry = _flash_pool[0] # recycle the oldest one
	var flash_v: Variant = entry.get("node", null)
	if not (flash_v is Line2D) or not is_instance_valid(flash_v):
		return
	var flash: Line2D = flash_v as Line2D
	var old_tween_v: Variant = entry.get("tween", null)
	if old_tween_v is Tween and (old_tween_v as Tween).is_valid():
		(old_tween_v as Tween).kill()
	flash.points = PackedVector2Array([to_local(a), to_local(b)])
	flash.modulate.a = 1.0
	flash.visible = true
	var fade: float = maxf(0.05, float(_get_conf("slice_flash_fade_sec", 0.28)))
	var tween: Tween = flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: flash.visible = false)
	entry["tween"] = tween

# =============================================================================
# INPUT (raw touches read in _input like VirtualJoystick — the only input
# phase proven to always receive touches in this project; detection happens
# at the drag event, zero tunneling). Mouse is handled explicitly too: the
# cross guards on _touch_id make touch/mouse emulation pairs process once.
# =============================================================================

const MOUSE_CAPTURE_ID: int = -2

func _input(event: InputEvent) -> void:
	if _state != State.RUN:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _touch_id == -1:
			_begin_slice_gesture(touch.index, touch.position)
		elif not touch.pressed and touch.index == _touch_id:
			_touch_id = -1
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_drag_slice_gesture(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed and _touch_id == -1:
			_begin_slice_gesture(MOUSE_CAPTURE_ID, mouse_btn.position)
		elif not mouse_btn.pressed and _touch_id == MOUSE_CAPTURE_ID:
			_touch_id = -1
	elif event is InputEventMouseMotion:
		if _touch_id == MOUSE_CAPTURE_ID:
			_drag_slice_gesture((event as InputEventMouseMotion).position)

func _begin_slice_gesture(capture_id: int, screen_pos: Vector2) -> void:
	_touch_id = capture_id
	_finger_world = _to_world(screen_pos)
	_finger_prev_world = _finger_world
	_trail_points.clear()
	_push_trail_point(_finger_world)

func _drag_slice_gesture(screen_pos: Vector2) -> void:
	_finger_prev_world = _finger_world
	_finger_world = _to_world(screen_pos)
	_try_slice_segment(_finger_prev_world, _finger_world)
	_push_trail_point(_finger_world)

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

func _push_trail_point(pos: Vector2) -> void:
	var min_dist: float = maxf(1.0, float(_get_conf("trail_min_point_dist_px", 8.0)))
	if not _trail_points.is_empty():
		var last: Vector2 = (_trail_points[_trail_points.size() - 1] as Dictionary).get("pos", Vector2.ZERO)
		if last.distance_to(pos) < min_dist:
			return
	_trail_points.append({"pos": pos, "born_msec": Time.get_ticks_msec()})
	var max_points: int = maxi(4, int(_get_conf("trail_max_points", 28)))
	while _trail_points.size() > max_points:
		_trail_points.pop_front()

# =============================================================================
# RUN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	var dt: float = minf(delta, 0.05)
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()

	# Sablier/gel : seule la SIMULATION (objets + spawner) est ralentie ;
	# trait, laser, input, timers d'effets et _elapsed restent en temps reel.
	var sim_dt: float = dt * _sim_scale()

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.RUN
		State.RUN:
			_tick_spawner(sim_dt)
			_tick_forced_spawns(sim_dt)
			_update_events(dt)

	_update_objects(sim_dt)
	_update_links()
	_animate_bomb_rings()
	_tick_effect_timers(dt)
	_update_trail()
	_try_slice_trail()
	_try_slice_laser()
	_update_laser()
	_update_banner(dt)
	_update_combo_label()

	if _elapsed >= _duration:
		_finish()

## Facteur de simulation des pickups sablier (bullet-time) / gant de gel
## (fige tout) — le gel domine.
func _sim_scale() -> float:
	if _freeze_time_left > 0.0:
		return 0.0
	if _hourglass_time_left > 0.0:
		return clampf(float(_get_conf("hourglass_slow_factor", 0.5)), 0.05, 1.0)
	return 1.0

func _tick_effect_timers(dt: float) -> void:
	_hourglass_time_left = maxf(0.0, _hourglass_time_left - dt)
	_freeze_time_left = maxf(0.0, _freeze_time_left - dt)
	_laser_slice_time_left = maxf(0.0, _laser_slice_time_left - dt)
	_special_cooldown = maxf(0.0, _special_cooldown - dt)
	_mini_swarm_cooldown = maxf(0.0, _mini_swarm_cooldown - dt)
	_fever_time_left = maxf(0.0, _fever_time_left - dt)
	_update_effect_vignette()

## Vignette discrete pendant sablier (bleu) / gel (glace) — feedback lisible.
func _update_effect_vignette() -> void:
	var color_html: String = ""
	if _freeze_time_left > 0.0:
		color_html = str(_get_conf("freeze_vignette_color", "#8FE8FF2E"))
	elif _hourglass_time_left > 0.0:
		color_html = str(_get_conf("hourglass_vignette_color", "#4A90E830"))
	if color_html == "":
		if _effect_vignette and is_instance_valid(_effect_vignette):
			_effect_vignette.visible = false
		return
	if _effect_vignette == null or not is_instance_valid(_effect_vignette):
		_effect_vignette = ColorRect.new()
		_effect_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_effect_vignette.z_as_relative = false
		_effect_vignette.z_index = 44
		add_child(_effect_vignette)
	_effect_vignette.position = Vector2.ZERO
	_effect_vignette.size = get_viewport_rect().size
	_effect_vignette.color = Color(color_html)
	_effect_vignette.visible = true

# =============================================================================
# SPAWN (irregular bursts + ballistic arcs)
# =============================================================================

func _tick_spawner(dt: float) -> void:
	_spawn_timer -= dt
	if _spawn_timer > 0.0:
		return
	if _elapsed >= _duration - maxf(0.5, float(_get_conf("spawn_stop_before_end_sec", 3.0))):
		return
	if not _in_burst:
		_in_burst = true
		_bombs_in_burst = 0
		_burst_mini = false
		var size_min: int = maxi(1, int(_get_conf("burst_size_min", 2)))
		var size_max: int = maxi(size_min, int(_get_conf("burst_size_max", 4)))
		_burst_remaining = randi_range(size_min, size_max)
		# Nuee de minis : le burst entier devient 6-8 petits objets a faucher
		# d'un grand geste (cooldown dedie, Libre via chance data).
		if _mini_swarm_cooldown <= 0.0 \
			and randf() <= clampf(float(_get_conf("mini_swarm_chance", 0.0)), 0.0, 1.0):
			_burst_mini = true
			_mini_swarm_cooldown = maxf(5.0, float(_get_conf("mini_swarm_cooldown_sec", 25.0)))
			_burst_remaining = randi_range(
				maxi(2, int(_get_conf("mini_count_min", 6))),
				maxi(2, int(_get_conf("mini_count_max", 8))))
	if _count_launchables() < maxi(1, int(_get_conf("max_active_objects", 12))):
		_spawn_object({"mini": true} if _burst_mini else {})
	_burst_remaining -= 1
	if _burst_remaining <= 0:
		_in_burst = false
		var pause_min: float = maxf(0.1, float(_get_conf("burst_pause_sec_min", 0.7)))
		var pause_max: float = maxf(pause_min, float(_get_conf("burst_pause_sec_max", 1.6)))
		var end_scale: float = clampf(float(_get_conf("burst_pause_scale_end", 0.7)), 0.2, 1.0)
		_spawn_timer = randf_range(pause_min, pause_max) * lerpf(1.0, end_scale, _ramp_t())
	else:
		_spawn_timer = maxf(0.03, float(_get_conf("burst_object_interval_sec", 0.14)))

## En mode libre "continuous", _duration est quasi infinie (rampe temporelle
## figée à 0) : _free_level_progress (progression 0->1 du level) la remplace.
func _ramp_t() -> float:
	var progress_v: Variant = _config.get("_free_level_progress", null)
	if progress_v is float or progress_v is int:
		return clampf(float(progress_v), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _count_launchables() -> int:
	var count: int = 0
	for entry in _objects:
		var kind: String = str((entry as Dictionary).get("kind", ""))
		if kind == "object" or kind == "bomb":
			count += 1
	return count

## opts (spawns scriptes/variantes) : "mini" bool, "bomb"/"decoy" bool forces,
## "type_id" String (type force, ex. legendaire), "x" float (colonne scriptee),
## "side_entry" -1/1 (entree laterale pluie diagonale), "pinata" bool,
## "plain" bool (partenaire de paire liee : aucun roll de variante).
## Retourne le node racine spawne (null si rien).
func _spawn_object(opts: Dictionary = {}) -> Node2D:
	var plain: bool = bool(opts.get("plain", false))
	var is_mini: bool = bool(opts.get("mini", false))
	var is_pinata: bool = bool(opts.get("pinata", false))
	var forced: bool = is_pinata or opts.has("bomb") or opts.has("decoy") \
		or opts.has("type_id") or opts.has("side_entry") or plain or is_mini
	# Objet bonus (1 max a l'ecran, cooldown + anti-repetition, progressif) :
	# prioritaire sur le roll bombe, jamais sur un spawn force.
	if not forced:
		var special_id: String = _roll_special()
		if special_id != "":
			return _spawn_special_object(special_id)
	var is_bomb: bool = bool(opts.get("bomb", false))
	var is_decoy: bool = bool(opts.get("decoy", false))
	if not forced:
		is_bomb = _elapsed >= maxf(0.0, float(_get_conf("bomb_grace_sec", 2.5))) \
			and _bombs_in_burst < maxi(0, int(_get_conf("bomb_max_per_burst", 1))) \
			and randf() <= clampf(float(_get_conf("bomb_chance", 0.14)), 0.0, 1.0) \
			and not _bomb_textures.is_empty()
		# Bombe leurre (orange = cristaux) : lecture fine des couleurs, Libre.
		if not is_bomb:
			is_decoy = randf() <= clampf(float(_get_conf("decoy_bomb_chance", 0.0)), 0.0, 1.0) \
				and not _decoy_textures.is_empty()
	if is_bomb and _bomb_textures.is_empty():
		return null
	if is_decoy and _decoy_textures.is_empty():
		return null
	if not (is_bomb or is_decoy) and _object_types.is_empty():
		return null

	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(10.0, float(_get_conf("spawn_x_margin_px", 90.0)))
	var x: float = clampf(float(opts.get("x", randf_range(margin, viewport_size.x - margin))),
		margin, viewport_size.x - margin)
	var start := Vector2(x, viewport_size.y + maxf(0.0, float(_get_conf("spawn_y_below_px", 60.0))))
	var speed: float = randf_range(
		maxf(100.0, float(_get_conf("launch_speed_min_px_sec", 1450.0))),
		maxf(100.0, float(_get_conf("launch_speed_max_px_sec", 1750.0)))
	)
	var vel: Vector2
	var side_entry: int = int(opts.get("side_entry", 0))
	if side_entry != 0:
		# Pluie diagonale : entree par un COTE en arc tendu (vel horizontale
		# dominante, la gravite dessine l'arc).
		start = Vector2(-60.0 if side_entry > 0 else viewport_size.x + 60.0,
			viewport_size.y * randf_range(0.3, 0.5))
		vel = Vector2(float(side_entry) * speed * 0.72, -speed * randf_range(0.28, 0.42))
	else:
		# Launch angle leans toward the screen center so arcs stay on screen.
		var angle: float = deg_to_rad(randf_range(
			float(_get_conf("launch_angle_deg_min", 3.0)),
			float(_get_conf("launch_angle_deg_max", 14.0))
		))
		var side: float = signf(viewport_size.x * 0.5 - x)
		if absf(side) < 0.5:
			side = -1.0 if randf() < 0.5 else 1.0
		vel = Vector2(sin(angle) * side, -cos(angle)) * speed
	if is_pinata:
		# Lancee au centre, plus lente : elle doit rester jouable 10 s.
		start.x = viewport_size.x * 0.5
		vel = Vector2(randf_range(-90.0, 90.0), -speed * 0.62)

	var type: Dictionary = {}
	if not (is_bomb or is_decoy):
		if opts.has("type_id") or is_pinata:
			type = _pick_object_type_by_id(str(opts.get("type_id", "relic_legendary")))
		else:
			type = _pick_object_type()
		if type.is_empty():
			return null
	var size_px: float = maxf(24.0, float(_get_conf("bomb_size_px", 100.0)))
	if not (is_bomb or is_decoy):
		# Random per-target size inside the configured range (visual variety;
		# radius, pieces and pickup reach all follow the spawned size).
		var scale_min: float = maxf(0.1, float(_get_conf("object_scale_min", 0.6)))
		var scale_max: float = maxf(scale_min, float(_get_conf("object_scale_max", 1.5)))
		size_px = float(type.get("size_px", 96.0)) * randf_range(scale_min, scale_max)
		if is_mini:
			size_px *= clampf(float(_get_conf("mini_scale", 0.5)), 0.2, 1.0)
		if is_pinata:
			size_px = float(type.get("size_px", 96.0)) * maxf(1.0, float(_get_conf("pinata_scale", 2.2)))
	var texture: Texture2D = null
	var tint: Color = Color.WHITE
	if is_bomb:
		texture = _bomb_textures[randi() % _bomb_textures.size()]
		tint = Color(str(_get_conf("bomb_tint", "#6E6E6E")))
	elif is_decoy:
		texture = _decoy_textures[randi() % _decoy_textures.size()]
		tint = Color(str(_get_conf("decoy_tint", "#FF9A3C")))
	elif is_pinata and _pinata_texture != null:
		texture = _pinata_texture
		tint = Color.WHITE
	else:
		texture = (type.get("textures") as Array)[randi() % (type.get("textures") as Array).size()]
		tint = type.get("tint", Color.WHITE) as Color
		if is_pinata:
			tint = Color("#FFD866") # PH : legendaire scale dore

	var root := Node2D.new()
	root.name = "SliceBomb" if (is_bomb or is_decoy) else ("SlicePinata" if is_pinata else "SliceObject")
	root.z_as_relative = false
	root.z_index = 12
	root.position = start
	var region := Rect2(Vector2.ZERO, texture.get_size())
	var sprite_scale: float = size_px / maxf(1.0, maxf(region.size.x, region.size.y))
	var sprite := _build_region_sprite(texture, region, sprite_scale, tint)
	root.add_child(sprite)
	var rings: Array = []
	if is_bomb or is_decoy:
		_attach_bomb_aura(root, size_px)
		rings = _attach_bomb_rings(root, size_px, is_decoy)
	add_child(root)

	if is_bomb:
		_bombs_in_burst += 1
	var entry: Dictionary = {
		"node": root,
		"sprite": sprite,
		"vel": vel,
		"prev_pos": start,
		"radius": size_px * 0.5,
		"kind": "bomb" if is_bomb else ("decoy" if is_decoy else ("pinata" if is_pinata else "object")),
		"type": type,
		"slices_remaining": 1 if (is_bomb or is_decoy) else int(type.get("slices_to_break", 1)),
		"depth": 0,
		"last_slice_msec": -100000,
		"spin": 0.0,
		"region": region,
		"sprite_scale": sprite_scale
	}
	if not rings.is_empty():
		entry["rings"] = rings
		entry["ring_phase"] = randf() * TAU
	if is_mini:
		entry["value_mult"] = clampf(float(_get_conf("mini_score_mult", 0.5)), 0.05, 1.0)
	if is_pinata:
		entry["slices_remaining"] = maxi(2, int(_get_conf("pinata_slices", 10)))
		entry["pinata_until"] = _elapsed + maxf(3.0, float(_get_conf("pinata_duration_sec", 10.0)))
		_pinata_active = true
	# Variantes par objet (jamais sur les spawns forces/minis/partenaires) :
	# blinde > lie > precision > rebondissant — au plus une par objet.
	if not forced and str(entry["kind"]) == "object":
		if int(entry["slices_remaining"]) == 1 \
			and randf() <= clampf(float(_get_conf("armored_chance", 0.0)), 0.0, 1.0):
			entry["armored"] = true
			entry["armor_dir"] = Vector2.ZERO
			entry["slices_remaining"] = 2
			_attach_armored_overlay(root, size_px)
		elif randf() <= clampf(float(_get_conf("precision_chance", 0.0)), 0.0, 1.0):
			entry["precision_angle"] = randf_range(0.0, PI)
			_attach_precision_line(root, size_px, float(entry["precision_angle"]))
		elif randf() <= clampf(float(_get_conf("bouncy_chance", 0.0)), 0.0, 1.0):
			entry["bouncy"] = true
			sprite.modulate = tint * Color(str(_get_conf("bouncy_tint", "#9AFFB0")))
	_objects.append(entry)
	# Paire liee : un partenaire "plain" spawn a cote, chaine entre les deux.
	if not forced and str(entry["kind"]) == "object" \
		and not entry.has("armored") and not entry.has("precision_angle") \
		and randf() <= clampf(float(_get_conf("linked_chance", 0.0)), 0.0, 1.0):
		var partner: Node2D = _spawn_object({
			"plain": true,
			"x": x + (120.0 if x < viewport_size.x * 0.5 else -120.0)
		})
		if partner != null:
			_create_link(root, partner)
	return root

func _pick_object_type_by_id(type_id: String) -> Dictionary:
	for type_v in _object_types:
		if str((type_v as Dictionary).get("id", "")) == type_id:
			return type_v as Dictionary
	# Fallback : le type le plus rare (dernier de la liste par convention).
	return {} if _object_types.is_empty() else (_object_types[_object_types.size() - 1] as Dictionary)

func _build_region_sprite(texture: Texture2D, region: Rect2, sprite_scale: float, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.modulate = tint
	return sprite

## Pulsing red aura behind the bomb (pattern: ObstacleExplosive._setup_aura).
func _attach_bomb_aura(root: Node2D, size_px: float) -> void:
	if _bomb_aura_frames == null:
		return
	var aura := AnimatedSprite2D.new()
	aura.name = "Aura"
	aura.sprite_frames = _bomb_aura_frames
	var anim_name: StringName = &"default"
	if not _bomb_aura_frames.has_animation(anim_name):
		var names: PackedStringArray = _bomb_aura_frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if _bomb_aura_frames.has_animation(anim_name):
		aura.play(anim_name)
	aura.material = _add_material
	aura.z_index = -1
	var frame_tex: Texture2D = _bomb_aura_frames.get_frame_texture(anim_name, 0) \
		if _bomb_aura_frames.has_animation(anim_name) and _bomb_aura_frames.get_frame_count(anim_name) > 0 else null
	var base_scale: float = 1.0
	if frame_tex:
		var f_size: Vector2 = frame_tex.get_size()
		if f_size.x > 0.0 and f_size.y > 0.0:
			base_scale = size_px / maxf(f_size.x, f_size.y)
	var scale_min: float = base_scale * maxf(0.2, float(_get_conf("bomb_aura_scale_min", 1.15)))
	var scale_max: float = base_scale * maxf(0.2, float(_get_conf("bomb_aura_scale_max", 1.45)))
	aura.scale = Vector2.ONE * scale_min
	root.add_child(aura)
	root.move_child(aura, 0)
	var pulse_sec: float = maxf(0.1, float(_get_conf("bomb_aura_pulse_sec", 0.45)))
	var tween: Tween = aura.create_tween()
	tween.set_loops()
	tween.tween_property(aura, "scale", Vector2.ONE * scale_max, pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(aura, "scale", Vector2.ONE * scale_min, pulse_sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Anneau sinusoidal multi-couches autour des bombes (visibilite mobile) :
## Line2D fermees dont le rayon ondule, couches data bomb_ring_layers (rouge)
## / decoy_ring_layers (orange, leurres). Points recalcules chaque frame par
## _animate_bomb_rings. Retourne les Line2D creees (stockees dans le dict).
func _attach_bomb_rings(root: Node2D, _size_px: float, is_decoy: bool) -> Array:
	if not bool(_get_conf("bomb_ring_enabled", true)):
		return []
	var layers_v: Variant = _get_conf("decoy_ring_layers" if is_decoy else "bomb_ring_layers", [])
	var layers: Array = (layers_v as Array) if layers_v is Array else []
	if layers.is_empty():
		layers = [
			{"color": "#FF9A3C66" if is_decoy else "#FF3D2A66", "width_px": 14.0, "additive": true},
			{"color": "#FFB35CCC" if is_decoy else "#FF6B4ACC", "width_px": 7.0, "additive": true},
			{"color": "#FFE8C0" if is_decoy else "#FFD8C0", "width_px": 3.0, "additive": false}
		]
	var rings: Array = []
	for layer_v in layers:
		if not (layer_v is Dictionary):
			continue
		var layer: Dictionary = layer_v as Dictionary
		var line := Line2D.new()
		line.closed = true
		line.width = maxf(1.0, float(layer.get("width_px", 6.0)))
		line.default_color = Color(str(layer.get("color", "#FF3D2A")))
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.z_index = -1 # derriere le sprite de la bombe, devant l'aura
		if bool(layer.get("additive", true)):
			line.material = _add_material
		root.add_child(line)
		rings.append(line)
	return rings

## Ondulation des anneaux : rayon = r0 + sin(angle*freq + t*speed + phase)*amp,
## les MEMES points pour toutes les couches (seules largeurs/couleurs varient).
func _animate_bomb_rings() -> void:
	if _objects.is_empty():
		return
	var segments: int = maxi(12, int(_get_conf("bomb_ring_segments", 40)))
	var amplitude: float = maxf(0.0, float(_get_conf("bomb_ring_wave_amplitude_px", 6.0)))
	var frequency: float = maxf(1.0, float(_get_conf("bomb_ring_wave_frequency", 6.0)))
	var speed: float = float(_get_conf("bomb_ring_wave_speed", 6.0))
	var radius_ratio: float = maxf(0.2, float(_get_conf("bomb_ring_radius_ratio", 0.75)))
	for entry_v in _objects:
		var entry: Dictionary = entry_v as Dictionary
		var rings_v: Variant = entry.get("rings", null)
		if not (rings_v is Array) or (rings_v as Array).is_empty():
			continue
		var r0: float = float(entry.get("radius", 50.0)) * 2.0 * radius_ratio
		var phase: float = float(entry.get("ring_phase", 0.0))
		var pts := PackedVector2Array()
		for i in range(segments):
			var a: float = TAU * float(i) / float(segments)
			var r: float = r0 + sin(a * frequency + _elapsed * speed + phase) * amplitude
			pts.append(Vector2(cos(a), sin(a)) * r)
		for line_v in (rings_v as Array):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).points = pts

## Overlay « blinde » : plaques metalliques (asset) ou croix procedurale grise.
func _attach_armored_overlay(root: Node2D, size_px: float) -> void:
	if _armored_overlay_texture != null:
		var overlay := Sprite2D.new()
		overlay.texture = _armored_overlay_texture
		var tex_size: Vector2 = _armored_overlay_texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			overlay.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
		overlay.z_index = 1
		root.add_child(overlay)
		return
	var steel := Color(str(_get_conf("armored_cross_color", "#B8C2D4")))
	for angle in [PI * 0.25, -PI * 0.25]:
		var bar := Line2D.new()
		var half: float = size_px * 0.42
		var dir := Vector2(cos(angle), sin(angle))
		bar.points = PackedVector2Array([-dir * half, dir * half])
		bar.width = maxf(3.0, size_px * 0.08)
		bar.default_color = steel
		bar.begin_cap_mode = Line2D.LINE_CAP_ROUND
		bar.end_cap_mode = Line2D.LINE_CAP_ROUND
		bar.z_index = 1
		root.add_child(bar)

## Ligne de precision : trancher LE LONG de cette ligne = score x3.
func _attach_precision_line(root: Node2D, size_px: float, angle: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var half: float = size_px * 0.55
	var glow := Line2D.new()
	glow.points = PackedVector2Array([-dir * half, dir * half])
	glow.width = 10.0
	glow.default_color = Color(str(_get_conf("precision_line_glow_color", "#FFE06655")))
	glow.material = _add_material
	glow.z_index = 1
	root.add_child(glow)
	var core := Line2D.new()
	core.points = glow.points
	core.width = 3.0
	core.default_color = Color(str(_get_conf("precision_line_color", "#FFE066")))
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	core.z_index = 2
	root.add_child(core)

# =============================================================================
# PHYSICS
# =============================================================================

func _update_objects(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var gravity: float = maxf(100.0, float(_get_conf("gravity_px_sec2", 1500.0)))
	for i in range(_objects.size() - 1, -1, -1):
		var entry: Dictionary = _objects[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_objects.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		entry["prev_pos"] = node.position
		var vel: Vector2 = entry.get("vel", Vector2.ZERO)
		vel.y += gravity * dt
		entry["vel"] = vel
		node.position += vel * dt
		var spin: float = float(entry.get("spin", 0.0))
		if absf(spin) > 0.001:
			node.rotation += spin * dt
		# Rebondissant : UNE seconde chance sur un sol invisible. La pinata
		# rebondit tant que son timer court, puis retombe pour de bon.
		var floor_y: float = viewport_size.y * clampf(float(_get_conf("bounce_floor_ratio", 0.92)), 0.5, 1.0)
		var is_pinata: bool = str(entry.get("kind", "")) == "pinata"
		var can_bounce: bool = (bool(entry.get("bouncy", false)) and not bool(entry.get("bounced", false))) \
			or (is_pinata and _elapsed < float(entry.get("pinata_until", 0.0)))
		if can_bounce and vel.y > 0.0 and node.position.y >= floor_y:
			vel.y = -absf(vel.y) * clampf(float(_get_conf("bounce_restitution", 0.85)), 0.2, 1.0)
			entry["vel"] = vel
			entry["bounced"] = true
			if VFXManager:
				VFXManager.spawn_impact(Vector2(node.position.x, floor_y), 16.0, self)
		# Fallen back below the screen = a simple miss, no penalty.
		if (node.position.y > viewport_size.y + 140.0 and vel.y > 0.0) \
			or node.position.x < -260.0 or node.position.x > viewport_size.x + 260.0:
			# Combo fever : seul un objet launchable normal rate brise la serie
			# (bombes, leurres, morceaux, bonus et pinata expiree n'y touchent pas).
			if str(entry.get("kind", "")) == "object":
				_combo_count = 0
			if is_pinata:
				_pinata_active = false
			_release_links_for(node)
			node.queue_free()
			_objects.remove_at(i)

# =============================================================================
# SLICING
# =============================================================================

## Blade segment vs the object's LAST TRAVEL segment (not just its current
## point): a fast-arcing object cannot tunnel through the blade between two
## events, and the swept test grants a natural time tolerance. The hit radius
## is widened by hit_radius_multiplier (sprites have transparent borders and
## Fruit Ninja-style slicing should feel generous). Every object crossed by
## the same segment is sliced (multi-slice combos).
func _try_slice_segment(a: Vector2, b: Vector2) -> void:
	var cooldown_msec: int = maxi(0, int(_get_conf("slice_cooldown_msec", 200)))
	var radius_mult: float = maxf(1.0, float(_get_conf("hit_radius_multiplier", 1.35)))
	var now: int = Time.get_ticks_msec()
	for i in range(_objects.size() - 1, -1, -1):
		var entry: Dictionary = _objects[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		if now - int(entry.get("last_slice_msec", -100000)) < cooldown_msec:
			continue
		var center: Vector2 = (node_v as Node2D).position
		var prev: Vector2 = entry.get("prev_pos", center)
		var closest_pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a, b, prev, center)
		if closest_pair.size() < 2:
			continue
		if closest_pair[0].distance_to(closest_pair[1]) > float(entry.get("radius", 40.0)) * radius_mult:
			continue
		entry["last_slice_msec"] = now
		_objects[i] = entry
		_on_object_sliced(i, (b - a).normalized())
	_try_cut_links(a, b)

## The VISIBLE trail is the blade: every frame, each live trail segment (the
## exact points the Line2D draws) is tested against each object's swept travel
## segment. Catches slow drags (no speed gate) and objects that fly into a
## freshly drawn trail — if the glow crosses the sprite, it cuts. A segment
## only cuts an object if drawn AFTER the object's last cut, so multi-slice
## tiers still require one new stroke per extra cut (a parked trail cannot
## chain-cut through the cooldown alone).
func _try_slice_trail() -> void:
	if _trail_points.size() < 2 or _objects.is_empty():
		return
	var cooldown_msec: int = maxi(0, int(_get_conf("slice_cooldown_msec", 200)))
	var radius_mult: float = maxf(1.0, float(_get_conf("hit_radius_multiplier", 1.35)))
	var now: int = Time.get_ticks_msec()
	for i in range(_objects.size() - 1, -1, -1):
		var entry: Dictionary = _objects[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var last_slice: int = int(entry.get("last_slice_msec", -100000))
		if now - last_slice < cooldown_msec:
			continue
		var center: Vector2 = (node_v as Node2D).position
		var prev: Vector2 = entry.get("prev_pos", center)
		var reach: float = float(entry.get("radius", 40.0)) * radius_mult
		for j in range(_trail_points.size() - 1):
			var p1: Dictionary = _trail_points[j + 1]
			if int(p1.get("born_msec", 0)) <= last_slice:
				continue
			var a: Vector2 = (_trail_points[j] as Dictionary).get("pos", Vector2.ZERO)
			var b: Vector2 = p1.get("pos", Vector2.ZERO)
			var closest_pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a, b, prev, center)
			if closest_pair.size() < 2 or closest_pair[0].distance_to(closest_pair[1]) > reach:
				continue
			entry["last_slice_msec"] = now
			_objects[i] = entry
			_on_object_sliced(i, (b - a).normalized())
			break
	# Chaînes des paires liées : le trait vivant les tranche aussi.
	if not _links.is_empty():
		for j in range(_trail_points.size() - 1):
			_try_cut_links((_trail_points[j] as Dictionary).get("pos", Vector2.ZERO),
				(_trail_points[j + 1] as Dictionary).get("pos", Vector2.ZERO))

func _on_object_sliced(index: int, slice_dir: Vector2) -> void:
	var entry: Dictionary = _objects[index]
	var kind: String = str(entry.get("kind", ""))
	if kind == "bomb":
		_explode_bomb(index)
		return
	if kind == "decoy":
		_slice_decoy(index)
		_register_combo_cut()
		return
	if kind == "special":
		_collect_special(index)
		_register_combo_cut()
		return
	var node_v: Variant = entry.get("node", null)
	var center: Vector2 = (node_v as Node2D).position if node_v is Node2D and is_instance_valid(node_v) else Vector2.ZERO
	# Blinde : la 2e coupe ne compte que si elle CROISE la premiere.
	if bool(entry.get("armored", false)):
		var first_dir: Vector2 = entry.get("armor_dir", Vector2.ZERO)
		if first_dir == Vector2.ZERO:
			entry["armor_dir"] = slice_dir
		else:
			var diff: float = absf(first_dir.angle_to(slice_dir))
			diff = minf(diff, PI - diff) # direction non signee
			if rad_to_deg(diff) < maxf(5.0, float(_get_conf("armored_cross_angle_deg", 45.0))):
				# Coupe parallele : rejetee (flash gris, pas de decrement).
				_objects[index] = entry
				if VFXManager and node_v is Node2D and is_instance_valid(node_v):
					VFXManager.flash_sprite(node_v as Node2D, Color("#8A93A6"), 0.12)
				return
	# Precision : coupe alignee sur la ligne marquee = score x3.
	if entry.has("precision_angle"):
		var line_dir := Vector2(cos(float(entry["precision_angle"])), sin(float(entry["precision_angle"])))
		var pd: float = absf(line_dir.angle_to(slice_dir))
		pd = minf(pd, PI - pd)
		if rad_to_deg(pd) <= maxf(2.0, float(_get_conf("precision_angle_tolerance_deg", 25.0))):
			entry["value_mult"] = float(entry.get("value_mult", 1.0)) \
				* maxf(1.0, float(_get_conf("precision_score_mult", 3.0)))
			if VFXManager:
				VFXManager.spawn_floating_text(center + Vector2(0.0, -50.0),
					_translate_or("slice_rush_precise", "PRECISE!"), Color("#FFE066"), self)
	var remaining: int = int(entry.get("slices_remaining", 1)) - 1
	entry["slices_remaining"] = remaining
	_objects[index] = entry
	_register_combo_cut()
	if remaining > 0:
		# Not broken yet (rare/legendary/armored/pinata): flash + small nudge.
		var sprite_v: Variant = entry.get("sprite", null)
		if sprite_v is Sprite2D and is_instance_valid(sprite_v) and VFXManager:
			VFXManager.flash_sprite(node_v as Node2D, Color.WHITE, 0.12)
		var vel: Vector2 = entry.get("vel", Vector2.ZERO)
		entry["vel"] = vel + slice_dir.orthogonal() * 90.0
		_objects[index] = entry
		_spawn_slice_flash(center - slice_dir * float(entry.get("radius", 40.0)),
			center + slice_dir * float(entry.get("radius", 40.0)))
		return
	_break_object(index, slice_dir)

func _break_object(index: int, slice_dir: Vector2) -> void:
	var entry: Dictionary = _objects[index]
	var node_v: Variant = entry.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		_objects.remove_at(index)
		return
	var node: Node2D = node_v as Node2D
	var center: Vector2 = node.position
	var radius: float = float(entry.get("radius", 40.0))

	if str(entry.get("kind", "")) == "pinata":
		_award_pinata_rewards(center)
	else:
		_award_cut_rewards(entry, center)

	if VFXManager:
		VFXManager.spawn_explosion(
			center,
			maxf(20.0, float(_get_conf("slice_effect_size_px", 70.0))),
			Color.WHITE,
			self,
			"",
			str(_get_conf("slice_effect_anim", "")),
			-1.0,
			0.25,
			maxf(0.0, float(_get_conf("slice_effect_anim_duration", 0.35))),
			false
		)
	_spawn_slice_flash(center - slice_dir * radius, center + slice_dir * radius)

	# Pinata et bonus : pas de morceaux (recompense deja versee).
	var no_pieces: bool = str(entry.get("kind", "")) == "pinata"
	if not no_pieces and int(entry.get("depth", 0)) < maxi(0, int(_get_conf("pieces_max_depth", 2))) \
		and _objects.size() < maxi(4, int(_get_conf("max_active_entities", 26))):
		_spawn_pieces(entry, slice_dir)

	if str(entry.get("kind", "")) == "pinata":
		_pinata_active = false
	_release_links_for(node)
	node.queue_free()
	_objects.remove_at(index)

## Splits the current texture region in two halves. The piece root is rotated
## so the cut edge follows the slice direction; halves separate along the
## perpendicular, inherit part of the velocity and get an upward kick + spin.
func _spawn_pieces(entry: Dictionary, slice_dir: Vector2) -> void:
	var node_v: Variant = entry.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var origin: Vector2 = (node_v as Node2D).position
	var region: Rect2 = entry.get("region", Rect2())
	if region.size.x <= 2.0 or region.size.y <= 2.0:
		return
	var texture_v: Variant = null
	var sprite_v: Variant = entry.get("sprite", null)
	if sprite_v is Sprite2D and is_instance_valid(sprite_v):
		texture_v = (sprite_v as Sprite2D).texture
	if not (texture_v is Texture2D):
		return
	var texture: Texture2D = texture_v as Texture2D
	var sprite_scale: float = float(entry.get("sprite_scale", 1.0))
	var tint: Color = (sprite_v as Sprite2D).modulate
	# Cut edge aligned with the slice: local Y = slice direction.
	var theta: float = slice_dir.angle() - PI * 0.5
	var parent_vel: Vector2 = entry.get("vel", Vector2.ZERO)
	var inherit: float = clampf(float(_get_conf("piece_inherit_vel", 0.55)), 0.0, 1.0)
	var separation: float = maxf(0.0, float(_get_conf("piece_separation_speed_px_sec", 260.0)))
	var kick: float = maxf(0.0, float(_get_conf("piece_upward_kick_px_sec", 180.0)))
	var spin_base: float = deg_to_rad(maxf(0.0, float(_get_conf("piece_spin_deg_sec", 240.0))))
	var half_w: float = region.size.x * 0.5

	for side in [-1.0, 1.0]:
		var half_region := Rect2(
			region.position + Vector2(half_w if side > 0.0 else 0.0, 0.0),
			Vector2(half_w, region.size.y)
		)
		var root := Node2D.new()
		root.name = "SlicePiece"
		root.z_as_relative = false
		root.z_index = 12
		root.position = origin
		root.rotation = theta
		var sprite := _build_region_sprite(texture, half_region, sprite_scale, tint)
		sprite.position = Vector2(side * half_w * 0.5 * sprite_scale, 0.0)
		root.add_child(sprite)
		add_child(root)
		var sep_dir: Vector2 = Vector2.RIGHT.rotated(theta) * side
		_objects.append({
			"node": root,
			"sprite": sprite,
			"vel": parent_vel * inherit + sep_dir * separation + Vector2(0.0, -kick),
			"prev_pos": origin,
			"radius": float(entry.get("radius", 40.0)) * clampf(float(_get_conf("piece_radius_factor", 0.62)), 0.2, 1.0),
			"kind": "piece",
			"type": entry.get("type", {}),
			"slices_remaining": 1,
			"depth": int(entry.get("depth", 0)) + 1,
			"last_slice_msec": Time.get_ticks_msec(),
			"spin": side * spin_base * randf_range(0.7, 1.3),
			"region": half_region,
			"sprite_scale": sprite_scale
		})

# =============================================================================
# BOMBS
# =============================================================================

func _explode_bomb(index: int) -> void:
	var entry: Dictionary = _objects[index]
	var node_v: Variant = entry.get("node", null)
	var center: Vector2 = (node_v as Node2D).position if node_v is Node2D and is_instance_valid(node_v) else Vector2.ZERO
	if VFXManager:
		VFXManager.spawn_explosion(
			center,
			maxf(40.0, float(_get_conf("explosion_size_px", 150.0))),
			Color(1.0, 0.4, 0.25),
			self,
			"",
			str(_get_conf("explosion_anim", "")),
			-1.0,
			0.3,
			maxf(0.0, float(_get_conf("explosion_anim_duration", 0.6))),
			false
		)
		VFXManager.screen_shake(
			maxf(0.0, float(_get_conf("bomb_shake_intensity", 10.0))),
			maxf(0.05, float(_get_conf("bomb_shake_sec", 0.35)))
		)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_objects.remove_at(index)
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("bomb_damage_percent", 0.3)), 0.0, 1.0)
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))

## Bombe LEURRE (orange) : la trancher est une bonne action — cristaux + score,
## explosion douce, aucun dégât.
func _slice_decoy(index: int) -> void:
	var entry: Dictionary = _objects[index]
	var node_v: Variant = entry.get("node", null)
	var center: Vector2 = (node_v as Node2D).position if node_v is Node2D and is_instance_valid(node_v) else Vector2.ZERO
	if VFXManager:
		VFXManager.spawn_explosion(center, maxf(30.0, float(_get_conf("slice_effect_size_px", 70.0))),
			Color("#FFB35C"), self, "", str(_get_conf("slice_effect_anim", "")), -1.0, 0.25,
			maxf(0.0, float(_get_conf("slice_effect_anim_duration", 0.35))), false)
		VFXManager.spawn_floating_text(center + Vector2(0.0, -50.0),
			_translate_or("slice_rush_decoy", "DECOY!"), Color("#FF9A3C"), self)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_objects.remove_at(index)
	if _game and is_instance_valid(_game):
		var points: int = int(round(float(_get_conf("decoy_score", 30)) * _reward_multiplier))
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, center)
		if _game.has_method("spawn_reward_crystal_at"):
			for i in range(maxi(1, int(_get_conf("decoy_crystals", 2)))):
				_game.call("spawn_reward_crystal_at",
					center + Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0)), {
						"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
					})

# =============================================================================
# OBJETS BONUS (sablier / gant de gel / chronos / extension laser)
# =============================================================================

## Roll exclusif : 1 special max a l'ecran, cooldown global, anti-repetition,
## chances progressives (x lerp(0.3, 1, rampe)). Retourne l'id ou "".
func _roll_special() -> String:
	if _special_cooldown > 0.0:
		return ""
	for entry_v in _objects:
		if str((entry_v as Dictionary).get("kind", "")) == "special":
			return ""
	var ratio: float = lerpf(0.3, 1.0, _ramp_t())
	var ids: Array = SPECIAL_CHANCE_KEYS.keys()
	ids.shuffle()
	for id_v in ids:
		var special_id: String = str(id_v)
		if special_id == _last_special_id:
			continue
		var chance: float = clampf(float(_get_conf(str(SPECIAL_CHANCE_KEYS[special_id]), 0.0)), 0.0, 1.0)
		if chance > 0.0 and randf() <= chance * ratio:
			_special_cooldown = maxf(2.0, float(_get_conf("special_cooldown_sec", 20.0)))
			_last_special_id = special_id
			return special_id
	return ""

## Objet bonus tranchable : arc balistique normal, orbe procedural pulsant
## tinte (asset <id>_asset prioritaire), 1 coupe, pas de morceaux.
func _spawn_special_object(special_id: String) -> Node2D:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(10.0, float(_get_conf("spawn_x_margin_px", 90.0)))
	var x: float = randf_range(margin, viewport_size.x - margin)
	var start := Vector2(x, viewport_size.y + maxf(0.0, float(_get_conf("spawn_y_below_px", 60.0))))
	var speed: float = randf_range(
		maxf(100.0, float(_get_conf("launch_speed_min_px_sec", 1450.0))),
		maxf(100.0, float(_get_conf("launch_speed_max_px_sec", 1750.0)))) * 0.92
	var angle: float = deg_to_rad(randf_range(
		float(_get_conf("launch_angle_deg_min", 3.0)), float(_get_conf("launch_angle_deg_max", 14.0))))
	var side: float = signf(viewport_size.x * 0.5 - x)
	if absf(side) < 0.5:
		side = -1.0 if randf() < 0.5 else 1.0
	var size_px: float = maxf(32.0, float(_get_conf("special_size_px", 76.0)))
	var tint := Color(str(SPECIAL_TINTS.get(special_id, "#FFFFFF")))

	var root := Node2D.new()
	root.name = "SliceSpecial"
	root.z_as_relative = false
	root.z_index = 13
	root.position = start
	var sprite: Sprite2D = null
	var texture: Texture2D = _special_textures.get(special_id, null)
	if texture != null:
		var region := Rect2(Vector2.ZERO, texture.get_size())
		sprite = _build_region_sprite(texture, region,
			size_px / maxf(1.0, maxf(region.size.x, region.size.y)), Color.WHITE)
		root.add_child(sprite)
	else:
		# PH : orbe tinte + anneau glow (meme langage capsule que les autres modes).
		var core := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		core.polygon = pts
		core.color = Color(tint.r, tint.g, tint.b, 0.85)
		root.add_child(core)
		var ring := Line2D.new()
		ring.closed = true
		ring.points = pts
		ring.width = 6.0
		ring.default_color = tint
		ring.material = _add_material
		root.add_child(ring)
	add_child(root)
	_objects.append({
		"node": root,
		"sprite": sprite,
		"vel": Vector2(sin(angle) * side, -cos(angle)) * speed,
		"prev_pos": start,
		"radius": size_px * 0.5,
		"kind": "special",
		"type": {},
		"special_id": special_id,
		"slices_remaining": 1,
		"depth": 0,
		"last_slice_msec": -100000,
		"spin": 0.0,
		"region": Rect2(),
		"sprite_scale": 1.0
	})
	return root

## Applique l'effet du bonus tranché + floating localisé.
func _collect_special(index: int) -> void:
	var entry: Dictionary = _objects[index]
	var special_id: String = str(entry.get("special_id", ""))
	var node_v: Variant = entry.get("node", null)
	var center: Vector2 = (node_v as Node2D).position if node_v is Node2D and is_instance_valid(node_v) else Vector2.ZERO
	match special_id:
		"hourglass":
			_hourglass_time_left = maxf(0.5, float(_get_conf("hourglass_duration_sec", 3.0)))
		"freeze_glove":
			_freeze_time_left = maxf(0.3, float(_get_conf("freeze_duration_sec", 1.5)))
		"chronos":
			_duration += maxf(1.0, float(_get_conf("chronos_bonus_sec", 5.0)))
		"laser_ext":
			_laser_slice_time_left = maxf(1.0, float(_get_conf("laser_slice_duration_sec", 6.0)))
	if VFXManager:
		VFXManager.spawn_impact(center, 22.0, self)
		VFXManager.spawn_floating_text(center + Vector2(0.0, -50.0),
			_translate_or(str(SPECIAL_LOCALE_KEYS.get(special_id, "")), special_id.to_upper()),
			Color(str(SPECIAL_TINTS.get(special_id, "#FFFFFF"))), self)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_objects.remove_at(index)

# =============================================================================
# OBJETS LIÉS (chaîne entre deux objets — la trancher casse les deux)
# =============================================================================

func _create_link(node_a: Node2D, node_b: Node2D) -> void:
	var line := Line2D.new()
	line.width = maxf(2.0, float(_get_conf("chain_width_px", 5.0)))
	line.default_color = Color(str(_get_conf("chain_color", "#C8D2E8")))
	line.z_as_relative = false
	line.z_index = 11
	add_child(line)
	_links.append({ "na": node_a, "nb": node_b, "line": line })

## Suit les deux extrémités ; se dissout si l'un des objets a disparu.
func _update_links() -> void:
	if _links.is_empty():
		return
	for i in range(_links.size() - 1, -1, -1):
		var link: Dictionary = _links[i]
		var na_v: Variant = link.get("na", null)
		var nb_v: Variant = link.get("nb", null)
		var line_v: Variant = link.get("line", null)
		if not (na_v is Node2D) or not is_instance_valid(na_v) \
			or not (nb_v is Node2D) or not is_instance_valid(nb_v):
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
			_links.remove_at(i)
			continue
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).points = PackedVector2Array([
				to_local((na_v as Node2D).global_position),
				to_local((nb_v as Node2D).global_position)])

## Libère la chaîne rattachée à un objet qui casse/sort (le partenaire survit).
func _release_links_for(node: Node2D) -> void:
	for i in range(_links.size() - 1, -1, -1):
		var link: Dictionary = _links[i]
		if link.get("na", null) == node or link.get("nb", null) == node:
			var line_v: Variant = link.get("line", null)
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
			_links.remove_at(i)

## Segment de lame vs segment de chaîne : couper la chaîne casse LES DEUX.
func _try_cut_links(a: Vector2, b: Vector2) -> void:
	if _links.is_empty():
		return
	for i in range(_links.size() - 1, -1, -1):
		var link: Dictionary = _links[i]
		var na_v: Variant = link.get("na", null)
		var nb_v: Variant = link.get("nb", null)
		if not (na_v is Node2D) or not is_instance_valid(na_v) \
			or not (nb_v is Node2D) or not is_instance_valid(nb_v):
			continue
		var pa: Vector2 = (na_v as Node2D).position
		var pb: Vector2 = (nb_v as Node2D).position
		var closest: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a, b, pa, pb)
		if closest.size() < 2 or closest[0].distance_to(closest[1]) > 14.0:
			continue
		var dir: Vector2 = (b - a).normalized()
		if VFXManager:
			VFXManager.spawn_floating_text((pa + pb) * 0.5 + Vector2(0.0, -40.0),
				"x2", Color("#C8D2E8"), self)
		_break_by_node(na_v as Node2D, dir)
		_break_by_node(nb_v as Node2D, dir)
		# _break_object -> _release_links_for a déjà retiré le lien.

func _break_by_node(node: Node2D, dir: Vector2) -> void:
	for i in range(_objects.size() - 1, -1, -1):
		if (_objects[i] as Dictionary).get("node", null) == node:
			_break_object(i, dir)
			return

# =============================================================================
# EXTENSION LASER (le rayon vaisseau→doigt tranche pendant l'effet)
# =============================================================================

## Coupe uniquement sur TRANSITION d'entrée en zone (flag laser_in par objet) :
## un laser posé sur un rare n'enchaîne jamais les coupes sans nouveau passage.
func _try_slice_laser() -> void:
	if _laser_slice_time_left <= 0.0 or _touch_id == -1 \
		or _player == null or not is_instance_valid(_player):
		return
	var a: Vector2 = _player.global_position + Vector2(0.0, -20.0)
	var b: Vector2 = _finger_world
	var laser_dir: Vector2 = (b - a).normalized()
	if laser_dir == Vector2.ZERO:
		return
	var radius_mult: float = maxf(1.0, float(_get_conf("hit_radius_multiplier", 1.35)))
	var cooldown_msec: int = maxi(0, int(_get_conf("slice_cooldown_msec", 200)))
	var now: int = Time.get_ticks_msec()
	for i in range(_objects.size() - 1, -1, -1):
		var entry: Dictionary = _objects[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var center: Vector2 = (node_v as Node2D).position
		var prev: Vector2 = entry.get("prev_pos", center)
		var closest: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a, b, prev, center)
		var inside: bool = closest.size() >= 2 \
			and closest[0].distance_to(closest[1]) <= float(entry.get("radius", 40.0)) * radius_mult
		var was_inside: bool = bool(entry.get("laser_in", false))
		entry["laser_in"] = inside
		_objects[i] = entry
		if inside and not was_inside and now - int(entry.get("last_slice_msec", -100000)) >= cooldown_msec:
			entry["last_slice_msec"] = now
			_objects[i] = entry
			_on_object_sliced(i, laser_dir)
	_try_cut_links(a, b)

# =============================================================================
# ÉVÉNEMENTS LIBRE + COMBO FEVER + BANDEAU
# =============================================================================

## Scheduler alternant (pattern absorb) : un tick toutes les event_interval,
## pick pondéré par les chances (anti-répétition), puis roll de la chance du
## candidat — un événement ne part jamais pendant un autre (file forcée pleine
## ou pinata en vol).
func _update_events(dt: float) -> void:
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(
		maxf(4.0, float(_get_conf("event_interval_sec_min", 18.0))),
		maxf(4.0, float(_get_conf("event_interval_sec_max", 30.0))))
	if not _forced_queue.is_empty() or _pinata_active:
		return
	var weights: Dictionary = {}
	if not _legendary_burst_done:
		weights["legendary"] = clampf(float(_get_conf("legendary_burst_chance", 0.0)), 0.0, 1.0)
	weights["diagonal"] = clampf(float(_get_conf("diagonal_rain_chance", 0.0)), 0.0, 1.0)
	weights["pinata"] = clampf(float(_get_conf("pinata_chance", 0.0)), 0.0, 1.0)
	weights["trap"] = clampf(float(_get_conf("trap_wave_chance", 0.0)), 0.0, 1.0)
	for key in weights.keys().duplicate():
		if float(weights[key]) <= 0.0:
			weights.erase(key)
	weights.erase(_last_event_id)
	if weights.is_empty():
		return
	var total: float = 0.0
	for key in weights:
		total += float(weights[key])
	var roll: float = randf() * total
	var picked: String = ""
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			picked = str(key)
			break
	if picked == "" or randf() > float(weights.get(picked, 0.0)):
		return
	_last_event_id = picked
	_trigger_event(picked)

func _trigger_event(event_id: String) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	match event_id:
		"legendary":
			_legendary_burst_done = true
			_show_banner(_translate_or("slice_rush_legendary_burst", "LEGENDARY BURST!"), Color("#FFD56B"))
			var count: int = randi_range(2, maxi(2, int(_get_conf("legendary_burst_count", 3))))
			for i in range(count):
				_forced_queue.append({ "type_id": "relic_legendary", "next_delay": 0.35 })
		"diagonal":
			_show_banner(_translate_or("slice_rush_diagonal_rain", "DIAGONAL RAIN!"), Color("#9AD8FF"))
			var side: int = -1 if randf() < 0.5 else 1
			if VFXManager:
				VFXManager.spawn_impact(Vector2(20.0 if side > 0 else viewport_size.x - 20.0,
					viewport_size.y * 0.4), 24.0, self)
			var rain: int = randi_range(4, maxi(4, int(_get_conf("diagonal_rain_count", 6))))
			for i in range(rain):
				_forced_queue.append({ "side_entry": side, "next_delay": 0.28 })
		"pinata":
			_show_banner(_translate_or("slice_rush_pinata", "PINATA!"), Color("#FFD866"))
			_forced_queue.append({ "pinata": true, "next_delay": 0.2 })
		"trap":
			# 5 bombes encadrant 1 légendaire : colonnes scriptées lisibles.
			_show_banner(_translate_or("slice_rush_trap", "TRAP!"), Color("#FF5C5C"))
			var margin: float = maxf(10.0, float(_get_conf("spawn_x_margin_px", 90.0)))
			var usable: float = viewport_size.x - margin * 2.0
			for i in range(6):
				var opts: Dictionary = { "x": margin + usable * (float(i) + 0.5) / 6.0, "next_delay": 0.22 }
				if i == 2:
					opts["type_id"] = "relic_legendary"
				else:
					opts["bomb"] = true
				_forced_queue.append(opts)

## Draine les spawns scriptés des événements (échelonnés, gelés par le gel).
func _tick_forced_spawns(dt: float) -> void:
	if _forced_queue.is_empty():
		return
	_forced_timer -= dt
	if _forced_timer > 0.0:
		return
	var spec: Dictionary = _forced_queue.pop_front()
	_forced_timer = maxf(0.05, float(spec.get("next_delay", 0.3)))
	_spawn_object(spec)

## Combo fever : chaque coupe réussie incrémente ; au seuil, fenêtre de
## cristaux garantis puis le compteur repart.
func _register_combo_cut() -> void:
	_combo_count += 1
	var target: int = maxi(3, int(_get_conf("fever_combo_target", 8)))
	if _combo_count >= target and _fever_time_left <= 0.0:
		_combo_count = 0
		_fever_time_left = maxf(1.0, float(_get_conf("fever_duration_sec", 5.0)))
		_show_banner(_translate_or("slice_rush_fever", "COMBO FEVER!"), Color("#7CFC9A"))

## Compteur discret (pattern streak lane_runner) : visible dès 3 coupes.
func _update_combo_label() -> void:
	if _combo_label == null or not is_instance_valid(_combo_label):
		_combo_label = Label.new()
		_combo_label.name = "SliceRushComboLabel"
		_combo_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("combo_font_size", 20))))
		_combo_label.add_theme_color_override("font_color", Color("#7CFC9A"))
		_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_combo_label.add_theme_constant_override("outline_size", 4)
		_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combo_label.z_as_relative = false
		_combo_label.z_index = 60
		add_child(_combo_label)
	if _fever_time_left > 0.0:
		_combo_label.visible = true
		_combo_label.text = "FEVER %ds" % int(ceil(_fever_time_left))
	elif _combo_count >= 3:
		_combo_label.visible = true
		_combo_label.text = "x%d" % _combo_count
	else:
		_combo_label.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_combo_label.position = Vector2(16.0,
		viewport_size.y * clampf(float(_get_conf("combo_y_ratio", 0.22)), 0.02, 0.9))

## Pluie de la piñata terminée : cristaux + 1 équipement garanti (hors cap).
func _award_pinata_rewards(at_pos: Vector2) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var points: int = int(round(float(_get_conf("pinata_score", 200)) * _reward_multiplier))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)
	if _game.has_method("spawn_reward_crystal_at"):
		for i in range(maxi(1, int(_get_conf("pinata_crystals", 8)))):
			_game.call("spawn_reward_crystal_at",
				at_pos + Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0)), {
					"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
				})
	if _game.has_method("spawn_reward_equipment_at"):
		_game.call("spawn_reward_equipment_at", at_pos,
			maxf(10.5, float(_get_conf("drop_quality_mult", 12.0))), {
				"auto_collect_delay_sec": maxf(0.0, float(_get_conf("auto_collect_delay_sec", 2.0))),
				"auto_collect_speed_px_sec": maxf(50.0, float(_get_conf("auto_collect_speed_px_sec", 950.0)))
			})

func _translate_or(key: String, fallback: String) -> String:
	if key != "" and typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Bandeau clignotant d'événement (pattern BreakoutManager).
func _show_banner(text: String, color: Color) -> void:
	if _event_banner == null or not is_instance_valid(_event_banner):
		var viewport_size: Vector2 = get_viewport_rect().size
		_event_banner = Label.new()
		_event_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_event_banner.add_theme_font_size_override("font_size", 40)
		_event_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_event_banner.add_theme_constant_override("outline_size", 5)
		_event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event_banner.z_as_relative = false
		_event_banner.z_index = 55
		_event_banner.size = Vector2(viewport_size.x, 46.0)
		_event_banner.position = Vector2(0.0, viewport_size.y * 0.3)
		add_child(_event_banner)
	_event_banner.text = text
	_event_banner.add_theme_color_override("font_color", color)
	_event_banner.visible = true
	_banner_time = 1.2

func _update_banner(dt: float) -> void:
	if _banner_time <= 0.0:
		return
	_banner_time -= dt
	if _event_banner and is_instance_valid(_event_banner):
		_event_banner.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 8.0))
		if _banner_time <= 0.0:
			_event_banner.visible = false

# =============================================================================
# REWARDS (score + crystals + rare-or-better equipment, auto-collected)
# =============================================================================

func _award_cut_rewards(entry: Dictionary, at_pos: Vector2) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var type_v: Variant = entry.get("type", {})
	var type: Dictionary = (type_v as Dictionary) if type_v is Dictionary else {}
	var depth: int = int(entry.get("depth", 0))
	var base: int = int(type.get("score_base", 20)) if depth == 0 \
		else int(type.get("score_per_extra_cut", 15)) * depth
	# value_mult : minis (x0.5) / precision (x3) ; score_global_mult : preset
	# gravite lourde (Libre per_level).
	var mult: float = float(entry.get("value_mult", 1.0)) \
		* maxf(0.1, float(_get_conf("score_global_mult", 1.0)))
	var points: int = int(round(float(base) * _reward_multiplier * mult))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)

	# Combo fever : cristal garanti par objet casse pendant la fenetre.
	var crystal_chance: float = clampf(float(type.get("crystal_chance", 0.1)), 0.0, 1.0)
	if _fever_time_left > 0.0:
		crystal_chance = 1.0
	if randf() <= crystal_chance \
		and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", at_pos, {
			"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
		})

	var max_drops: int = maxi(0, int(_get_conf("max_equipment_drops", 3)))
	if _equipment_drops_spawned >= max_drops:
		return
	if randf() > clampf(float(type.get("drop_chance", 0.0)), 0.0, 1.0):
		return
	if not _game.has_method("spawn_reward_equipment_at"):
		return
	var count: int = randi_range(
		maxi(1, int(type.get("drop_count_min", 1))),
		maxi(1, int(type.get("drop_count_max", 1)))
	)
	count = mini(count, max_drops - _equipment_drops_spawned)
	var quality_mult: float = maxf(10.5, float(_get_conf("drop_quality_mult", 12.0)))
	for i in range(count):
		var jitter := Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 16.0))
		_game.call("spawn_reward_equipment_at", at_pos + jitter, quality_mult, {
			"auto_collect_delay_sec": maxf(0.0, float(_get_conf("auto_collect_delay_sec", 2.0))),
			"auto_collect_speed_px_sec": maxf(50.0, float(_get_conf("auto_collect_speed_px_sec", 950.0)))
		})
		_equipment_drops_spawned += 1

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "SliceRushCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_get_conf("countdown_color", "#FFFFFF"))))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.z_as_relative = false
	_countdown_label.z_index = 60
	add_child(_countdown_label)

func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Restore the player and the HUD BEFORE notifying the wave chain.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # objects, pieces, trail and flashes are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
