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

var _countdown_label: Label = null
var _finished_emitted: bool = false

const FLASH_POOL_SIZE: int = 8

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
		"bomb_damage_percent", "_free_level_progress"]:
		if cfg.has(key):
			_config[key] = cfg[key]

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

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.RUN
		State.RUN:
			_tick_spawner(dt)

	_update_objects(dt)
	_update_trail()
	_try_slice_trail()
	_update_laser()

	if _elapsed >= _duration:
		_finish()

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
		var size_min: int = maxi(1, int(_get_conf("burst_size_min", 2)))
		var size_max: int = maxi(size_min, int(_get_conf("burst_size_max", 4)))
		_burst_remaining = randi_range(size_min, size_max)
	if _count_launchables() < maxi(1, int(_get_conf("max_active_objects", 12))):
		_spawn_object()
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

func _spawn_object() -> void:
	var is_bomb: bool = _elapsed >= maxf(0.0, float(_get_conf("bomb_grace_sec", 2.5))) \
		and _bombs_in_burst < maxi(0, int(_get_conf("bomb_max_per_burst", 1))) \
		and randf() <= clampf(float(_get_conf("bomb_chance", 0.14)), 0.0, 1.0) \
		and not _bomb_textures.is_empty()
	if not is_bomb and _object_types.is_empty():
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(10.0, float(_get_conf("spawn_x_margin_px", 90.0)))
	var x: float = randf_range(margin, viewport_size.x - margin)
	var start := Vector2(x, viewport_size.y + maxf(0.0, float(_get_conf("spawn_y_below_px", 60.0))))
	var speed: float = randf_range(
		maxf(100.0, float(_get_conf("launch_speed_min_px_sec", 1450.0))),
		maxf(100.0, float(_get_conf("launch_speed_max_px_sec", 1750.0)))
	)
	# Launch angle leans toward the screen center so arcs stay on screen.
	var angle: float = deg_to_rad(randf_range(
		float(_get_conf("launch_angle_deg_min", 3.0)),
		float(_get_conf("launch_angle_deg_max", 14.0))
	))
	var side: float = signf(viewport_size.x * 0.5 - x)
	if absf(side) < 0.5:
		side = -1.0 if randf() < 0.5 else 1.0
	var vel := Vector2(sin(angle) * side, -cos(angle)) * speed

	var type: Dictionary = {} if is_bomb else _pick_object_type()
	if not is_bomb and type.is_empty():
		return
	var size_px: float = maxf(24.0, float(_get_conf("bomb_size_px", 100.0)))
	if not is_bomb:
		# Random per-target size inside the configured range (visual variety;
		# radius, pieces and pickup reach all follow the spawned size).
		var scale_min: float = maxf(0.1, float(_get_conf("object_scale_min", 0.6)))
		var scale_max: float = maxf(scale_min, float(_get_conf("object_scale_max", 1.5)))
		size_px = float(type.get("size_px", 96.0)) * randf_range(scale_min, scale_max)
	var texture: Texture2D = _bomb_textures[randi() % _bomb_textures.size()] if is_bomb \
		else (type.get("textures") as Array)[randi() % (type.get("textures") as Array).size()]
	var tint: Color = Color(str(_get_conf("bomb_tint", "#6E6E6E"))) if is_bomb \
		else (type.get("tint", Color.WHITE) as Color)

	var root := Node2D.new()
	root.name = "SliceBomb" if is_bomb else "SliceObject"
	root.z_as_relative = false
	root.z_index = 12
	root.position = start
	var region := Rect2(Vector2.ZERO, texture.get_size())
	var sprite_scale: float = size_px / maxf(1.0, maxf(region.size.x, region.size.y))
	var sprite := _build_region_sprite(texture, region, sprite_scale, tint)
	root.add_child(sprite)
	if is_bomb:
		_attach_bomb_aura(root, size_px)
	add_child(root)

	if is_bomb:
		_bombs_in_burst += 1
	_objects.append({
		"node": root,
		"sprite": sprite,
		"vel": vel,
		"prev_pos": start,
		"radius": size_px * 0.5,
		"kind": "bomb" if is_bomb else "object",
		"type": type,
		"slices_remaining": 1 if is_bomb else int(type.get("slices_to_break", 1)),
		"depth": 0,
		"last_slice_msec": -100000,
		"spin": 0.0,
		"region": region,
		"sprite_scale": sprite_scale
	})

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
		# Fallen back below the screen = a simple miss, no penalty.
		if (node.position.y > viewport_size.y + 140.0 and vel.y > 0.0) \
			or node.position.x < -160.0 or node.position.x > viewport_size.x + 160.0:
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

func _on_object_sliced(index: int, slice_dir: Vector2) -> void:
	var entry: Dictionary = _objects[index]
	if str(entry.get("kind", "")) == "bomb":
		_explode_bomb(index)
		return
	var remaining: int = int(entry.get("slices_remaining", 1)) - 1
	entry["slices_remaining"] = remaining
	_objects[index] = entry
	var node_v: Variant = entry.get("node", null)
	var center: Vector2 = (node_v as Node2D).position if node_v is Node2D and is_instance_valid(node_v) else Vector2.ZERO
	if remaining > 0:
		# Not broken yet (rare/legendary): flash feedback + small nudge.
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

	if int(entry.get("depth", 0)) < maxi(0, int(_get_conf("pieces_max_depth", 2))) \
		and _objects.size() < maxi(4, int(_get_conf("max_active_entities", 26))):
		_spawn_pieces(entry, slice_dir)

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
	var points: int = int(round(float(base) * _reward_multiplier))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)

	if randf() <= clampf(float(type.get("crystal_chance", 0.1)), 0.0, 1.0) \
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
