extends Node2D

## Match3Manager — Orchestre une vague "match3" (inspiration Candy Crush) :
## plateau 9x9 centre a l'ecran, 5-6 types de tuiles (configurable par vague),
## swap classique par drag d'une tuile vers sa voisine (valide seulement si un
## match en resulte, sinon revert anime). Le vaisseau du joueur occupe UNE case
## en tuile JOKER : il complete les alignements (2 tuiles identiques + lui =
## match) mais ne disparait jamais ; il est retreci a la taille d'une cellule,
## porte un glow additif configurable, tombe avec la gravite et se swappe
## comme les autres (position pilotee via Player.set_match3_lock_pos).
## Des tuiles EXPLOSIVES (2e asset .tres par type, plus rares, arrivent par le
## refill) declenchent au match un effet special : clear_line / clear_column
## (trait glow qui grossit puis fade) ou clear_circle (cercle qui grandit),
## avec chainage si un effet detruit une autre tuile explosive. Cascades
## classiques (gravite + refill par le haut + re-resolution en chaine),
## reshuffle anti-blocage. Aucun degat : pure vague recompense — chaque bloc
## detruit donne du score proportionnel aux seuils du niveau, une chance de
## cristal et de rares items (cap par vague), tous aimantes vers le vaisseau.
## Tir coupe, contacts manuels (pas de physics engine).

signal finished

enum State { INTRO, IDLE, SWAPPING, RESOLVING, FALLING, SHUFFLE, DONE }

const MOUSE_CAPTURE_ID: int = -2
const STRONG_RESOURCE_CACHE_MAX: int = 64
static var _resource_cache: Dictionary = {} # path -> Resource
static var _missing_paths: Dictionary = {} # path -> true

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _swap_valid: bool = false
var _duration: float = 45.0
var _elapsed: float = 0.0

# Board. _grid[row][col] = entry Dictionary or null. Entries:
# { "node": Node2D|null (null for the ship), "sprite": Node2D|null,
#   "type": int, "is_ship": bool, "is_special": bool, "special_effect": String }
var _grid: Array = []
var _grid_size: int = 9
var _tile_type_count: int = 5
var _ship_cell: Vector2i = Vector2i(4, 4)
var _cell_px: float = 72.0
var _pitch: float = 76.0
var _grid_origin: Vector2 = Vector2.ZERO
var _grid_root: Node2D = null
var _cascade_depth: int = 0

# Resolved tile sets: [{ "normal": SpriteFrames|null, "special": SpriteFrames|null,
#   "tint": Color, "special_tint": Color, "scale_mult": float, "fallback": Color }]
var _tile_sets: Array = []

# Input (slice_rush pattern: _input + cross guards touch/mouse).
var _touch_id: int = -1
var _drag_origin_cell: Vector2i = Vector2i(-1, -1)
var _drag_start_world: Vector2 = Vector2.ZERO
var _gesture_consumed: bool = false
var _pressed_node: Node2D = null

# Rewards.
var _score_per_block: int = 8
var _equipment_drops_spawned: int = 0
var _step_crystals: int = 0
var _step_vfx: int = 0
var _step_pops: int = 0

# Shared additive material + effect pools.
var _add_material: CanvasItemMaterial = null
var _line_pool: Array = [] # [{ "node": Line2D, "tween": Tween }]
var _circle_pool: Array = [] # [{ "node": Polygon2D, "tween": Tween }]

var _countdown_label: Label = null
var _finished_emitted: bool = false

const LINE_POOL_SIZE: int = 6
const CIRCLE_POOL_SIZE: int = 4

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("match3") if DataManager else {}

	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("duration_sec_default", 45.0))))
	_grid_size = clampi(int(_get_conf("grid_size", 9)), 5, 12)
	_tile_type_count = clampi(int(_get_conf("tile_type_count", 5)), 3, 6)

	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_prepare_assets()
	_compute_geometry()
	_resolve_score_per_block()
	_build_grid()
	_begin_player_mode()
	_begin_hud_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	# Glide the ship into its board cell during the intro.
	_animate_ship_to(_cell_center(_ship_cell), _state_timer)
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — plateau et cascades préservés. Les nouvelles valeurs
## s'appliquent aux prochains refills (tuiles existantes inchangées).
func update_free_mode_config(cfg: Dictionary) -> void:
	_tile_type_count = clampi(int(cfg.get("tile_type_count", _tile_type_count)), 3, 6)
	if cfg.has("special_chance"):
		_config["special_chance"] = cfg["special_chance"]

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_match3"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_match3", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_match3"):
		_player.call("end_match3")

## The power buttons overlap the lowest board rows; useless here (no shooting).
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
	_tile_sets.clear()
	var fallback_colors: Array = []
	var fb_v: Variant = _get_conf("tile_fallback_colors", [])
	if fb_v is Array:
		fallback_colors = fb_v as Array
	var sets_v: Variant = _config.get("tile_sets", _cfg.get("tile_sets", []))
	if sets_v is Array:
		for idx in range((sets_v as Array).size()):
			var src_v: Variant = (sets_v as Array)[idx]
			if not (src_v is Dictionary):
				continue
			var src: Dictionary = src_v as Dictionary
			var normal_res: Resource = _load_cached_resource(str(src.get("normal", "")))
			var special_res: Resource = _load_cached_resource(str(src.get("special", "")))
			var fallback: Color = Color(str(fallback_colors[idx % maxi(1, fallback_colors.size())])) \
				if not fallback_colors.is_empty() else Color.from_hsv(float(idx) / 6.0, 0.7, 0.95)
			_tile_sets.append({
				"normal": normal_res as SpriteFrames if normal_res is SpriteFrames else null,
				"special": special_res as SpriteFrames if special_res is SpriteFrames else null,
				"tint": Color(str(src.get("tint", "#FFFFFF"))),
				"special_tint": Color(str(src.get("special_tint", "#FFFFFF"))),
				"scale_mult": maxf(0.2, float(src.get("scale_mult", 1.0))),
				"fallback": fallback
			})
	# Defensive: never fewer sets than the requested type count.
	while _tile_sets.size() < _tile_type_count:
		_tile_sets.append({
			"normal": null, "special": null,
			"tint": Color.WHITE, "special_tint": Color.WHITE, "scale_mult": 1.0,
			"fallback": Color.from_hsv(float(_tile_sets.size()) / 6.0, 0.7, 0.95)
		})

func _pick_special_effect() -> String:
	var weights_v: Variant = _get_conf("special_effect_weights", {})
	var weights: Dictionary = (weights_v as Dictionary) if weights_v is Dictionary else {}
	var line_w: float = maxf(0.0, float(weights.get("clear_line", 40.0)))
	var col_w: float = maxf(0.0, float(weights.get("clear_column", 40.0)))
	var circle_w: float = maxf(0.0, float(weights.get("clear_circle", 20.0)))
	var total: float = maxf(0.001, line_w + col_w + circle_w)
	var roll: float = randf() * total
	if roll < line_w:
		return "clear_line"
	if roll < line_w + col_w:
		return "clear_column"
	return "clear_circle"

# =============================================================================
# BOARD GEOMETRY + BUILD
# =============================================================================

func _compute_geometry() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, float(_get_conf("grid_side_margin_px", 24.0)))
	var spacing: float = maxf(0.0, float(_get_conf("cell_spacing_px", 4.0)))
	_cell_px = (viewport_size.x - side_margin * 2.0 - spacing * float(_grid_size - 1)) / float(_grid_size)
	_pitch = _cell_px + spacing
	var board_span: float = _pitch * float(_grid_size) - spacing
	var center_y: float = viewport_size.y * clampf(float(_get_conf("grid_center_y_ratio", 0.5)), 0.2, 0.8)
	_grid_origin = Vector2(side_margin, center_y - board_span * 0.5)

func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + Vector2(float(cell.x), float(cell.y)) * _pitch + Vector2.ONE * _cell_px * 0.5

func _world_to_cell(pos: Vector2) -> Vector2i:
	var local: Vector2 = pos - _grid_origin
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var col: int = int(local.x / _pitch)
	var row: int = int(local.y / _pitch)
	if col >= _grid_size or row >= _grid_size:
		return Vector2i(-1, -1)
	return Vector2i(col, row)

func _entry_at(cell: Vector2i) -> Variant:
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_size or cell.y >= _grid_size:
		return null
	return _grid[cell.y][cell.x]

func _set_entry(cell: Vector2i, entry: Variant) -> void:
	_grid[cell.y][cell.x] = entry

func _swap_entries(a: Vector2i, b: Vector2i) -> void:
	var tmp: Variant = _grid[a.y][a.x]
	_grid[a.y][a.x] = _grid[b.y][b.x]
	_grid[b.y][b.x] = tmp

## Initial board: random fill, then re-roll matched cells until clean (the
## wildcard-aware scan covers the ship jokering). No specials at generation.
func _build_grid() -> void:
	_grid_root = Node2D.new()
	_grid_root.name = "Match3Board"
	_grid_root.z_as_relative = false
	_grid_root.z_index = 10
	add_child(_grid_root)

	_ship_cell = Vector2i(_grid_size / 2, _grid_size / 2)
	_grid = []
	for row in range(_grid_size):
		var line: Array = []
		for col in range(_grid_size):
			line.append(null)
		_grid.append(line)
	_set_entry(_ship_cell, {"node": null, "sprite": null, "type": -1, "is_ship": true, "is_special": false, "special_effect": ""})

	for row in range(_grid_size):
		for col in range(_grid_size):
			var cell := Vector2i(col, row)
			if _entry_at(cell) != null:
				continue
			_set_entry(cell, _make_tile_entry(randi() % _tile_type_count, false, _cell_center(cell)))

	# Clean the board of accidental initial matches (bounded re-roll).
	for attempt in range(20):
		var matched: Dictionary = _find_matches()
		if matched.is_empty():
			break
		for cell_v in matched.keys():
			var entry: Dictionary = _entry_at(cell_v)
			entry["type"] = randi() % _tile_type_count
			_apply_tile_visual(entry)

func _make_tile_entry(type: int, special: bool, at_pos: Vector2) -> Dictionary:
	var node := Node2D.new()
	node.name = "Tile"
	node.position = at_pos
	_grid_root.add_child(node)
	var entry: Dictionary = {
		"node": node,
		"sprite": null,
		"type": type,
		"is_ship": false,
		"is_special": special,
		"special_effect": _pick_special_effect() if special else ""
	}
	_apply_tile_visual(entry)
	return entry

## (Re)builds the tile visual from its type/special state. Reused by the
## shuffle fallback re-roll.
func _apply_tile_visual(entry: Dictionary) -> void:
	var node_v: Variant = entry.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var node: Node2D = node_v as Node2D
	var old_sprite_v: Variant = entry.get("sprite", null)
	if old_sprite_v is Node and is_instance_valid(old_sprite_v):
		(old_sprite_v as Node).queue_free()
	var old_aura_v: Variant = entry.get("aura", null)
	if old_aura_v is Node and is_instance_valid(old_aura_v):
		(old_aura_v as Node).queue_free()
	entry["aura"] = null
	var type_set: Dictionary = _tile_sets[int(entry.get("type", 0)) % _tile_sets.size()]
	var special: bool = bool(entry.get("is_special", false))
	var frames: SpriteFrames = type_set.get("special") if special else type_set.get("normal")
	var tile_px: float = _cell_px * clampf(float(_get_conf("tile_fill_ratio", 0.82)), 0.3, 1.0) * float(type_set.get("scale_mult", 1.0))
	var sprite: Node2D = null
	if frames != null:
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name):
			var names: PackedStringArray = frames.get_animation_names()
			if names.size() > 0:
				anim_name = StringName(names[0])
		if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
			anim.play(anim_name)
			anim.frame = randi() % frames.get_frame_count(anim_name)
			anim.speed_scale = randf_range(0.9, 1.1)
			var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
			if frame_tex:
				var f_size: Vector2 = frame_tex.get_size()
				if f_size.x > 0.0 and f_size.y > 0.0:
					anim.scale = Vector2.ONE * (tile_px / maxf(f_size.x, f_size.y))
		anim.modulate = (type_set.get("special_tint") if special else type_set.get("tint")) as Color
		sprite = anim
	else:
		var rect := Polygon2D.new()
		var half: float = tile_px * 0.5
		rect.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
		])
		rect.color = type_set.get("fallback") as Color
		sprite = rect
	node.add_child(sprite)
	entry["sprite"] = sprite
	# Specials keep their type asset for readability; the "bomb" identity comes
	# from a strong additive aura behind the tile plus a marked pulse.
	if special:
		_attach_special_aura(entry, node, tile_px)
		var base_scale: Vector2 = sprite.scale
		var pulse_scale: float = maxf(1.0, float(_get_conf("special_pulse_scale", 1.15)))
		var pulse: Tween = sprite.create_tween()
		pulse.set_loops()
		var pulse_sec: float = maxf(0.1, float(_get_conf("special_pulse_sec", 0.6)))
		pulse.tween_property(sprite, "scale", base_scale * pulse_scale, pulse_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(sprite, "scale", base_scale, pulse_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Additive glow aura behind a special (bomb-like) tile, tinted per type.
func _attach_special_aura(entry: Dictionary, node: Node2D, tile_px: float) -> void:
	var aura_res: Resource = _load_cached_resource(str(_get_conf("special_aura_asset", "")))
	if not (aura_res is SpriteFrames):
		return
	var frames: SpriteFrames = aura_res as SpriteFrames
	var aura := AnimatedSprite2D.new()
	aura.name = "SpecialAura"
	aura.sprite_frames = frames
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if frames.has_animation(anim_name):
		aura.play(anim_name)
	aura.material = _add_material
	var type_set: Dictionary = _tile_sets[int(entry.get("type", 0)) % _tile_sets.size()]
	var aura_tint: Color = type_set.get("special_tint", Color.WHITE) as Color
	aura_tint.a = clampf(float(_get_conf("special_aura_alpha", 0.9)), 0.0, 1.0)
	aura.modulate = aura_tint
	var aura_px: float = tile_px * maxf(0.5, float(_get_conf("special_aura_scale", 1.55)))
	var base_scale: float = 1.0
	if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
		var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
		if frame_tex:
			var f_size: Vector2 = frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				base_scale = aura_px / maxf(f_size.x, f_size.y)
	aura.scale = Vector2.ONE * base_scale
	node.add_child(aura)
	node.move_child(aura, 0)
	entry["aura"] = aura
	var pulse_sec: float = maxf(0.1, float(_get_conf("special_pulse_sec", 0.6)))
	var aura_pulse: float = maxf(1.0, float(_get_conf("special_pulse_scale", 1.15)))
	var pulse: Tween = aura.create_tween()
	pulse.set_loops()
	pulse.tween_property(aura, "scale", Vector2.ONE * base_scale * aura_pulse, pulse_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(aura, "scale", Vector2.ONE * base_scale, pulse_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# =============================================================================
# MATCH DETECTION (type masks with the ship as wildcard)
# =============================================================================

## Returns the REAL cells to destroy (never the ship): every horizontal or
## vertical run of >= 3 compatible cells (tile of type t or the ship) holding
## at least 2 real tiles. A run of ship + one tile never matches.
func _find_matches() -> Dictionary:
	var out: Dictionary = {}
	for axis in range(2):
		for i in range(_grid_size):
			for t in range(_tile_type_count):
				var run_cells: Array = []
				var run_real: int = 0
				for j in range(_grid_size + 1):
					var entry_v: Variant = null
					var cell := Vector2i(-1, -1)
					if j < _grid_size:
						cell = Vector2i(j, i) if axis == 0 else Vector2i(i, j)
						entry_v = _entry_at(cell)
					var compatible: bool = false
					if entry_v is Dictionary:
						var e: Dictionary = entry_v as Dictionary
						compatible = bool(e.get("is_ship", false)) or int(e.get("type", -1)) == t
					if compatible:
						run_cells.append(cell)
						if not bool((entry_v as Dictionary).get("is_ship", false)):
							run_real += 1
					else:
						if run_cells.size() >= 3 and run_real >= 2:
							for c in run_cells:
								var ce: Dictionary = _entry_at(c)
								if not bool(ce.get("is_ship", false)):
									out[c] = true
						run_cells = []
						run_real = 0
	return out

## True if at least one adjacent swap (right/down covers all pairs, ship
## included) would produce a match.
func _has_possible_move() -> bool:
	for row in range(_grid_size):
		for col in range(_grid_size):
			var a := Vector2i(col, row)
			for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = a + dir
				if b.x >= _grid_size or b.y >= _grid_size:
					continue
				_swap_entries(a, b)
				var ok: bool = not _find_matches().is_empty()
				_swap_entries(a, b)
				if ok:
					return true
	return false

# =============================================================================
# INPUT (slice_rush pattern: _input + touch/mouse cross guards)
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _touch_id == -1:
			_begin_gesture(touch.index, touch.position)
		elif not touch.pressed and touch.index == _touch_id:
			_end_gesture()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_drag_gesture(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed and _touch_id == -1:
			_begin_gesture(MOUSE_CAPTURE_ID, mouse_btn.position)
		elif not mouse_btn.pressed and _touch_id == MOUSE_CAPTURE_ID:
			_end_gesture()
	elif event is InputEventMouseMotion:
		if _touch_id == MOUSE_CAPTURE_ID:
			_drag_gesture((event as InputEventMouseMotion).position)

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

func _begin_gesture(capture_id: int, screen_pos: Vector2) -> void:
	if _state != State.IDLE or _elapsed >= _duration:
		return
	var world: Vector2 = _to_world(screen_pos)
	var cell: Vector2i = _world_to_cell(world)
	if cell.x < 0:
		return
	var entry_v: Variant = _entry_at(cell)
	if not (entry_v is Dictionary):
		return
	_touch_id = capture_id
	_drag_origin_cell = cell
	_drag_start_world = world
	_gesture_consumed = false
	# Press feedback: slight tile grow (the ship keeps its glow only).
	var node_v: Variant = (entry_v as Dictionary).get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		_pressed_node = node_v as Node2D
		var press_tween: Tween = _pressed_node.create_tween()
		press_tween.tween_property(_pressed_node, "scale", Vector2.ONE * maxf(1.0, float(_get_conf("pressed_tile_scale", 1.08))), 0.08)

func _drag_gesture(screen_pos: Vector2) -> void:
	if _gesture_consumed or _state != State.IDLE:
		return
	var world: Vector2 = _to_world(screen_pos)
	var delta: Vector2 = world - _drag_start_world
	var threshold: float = _cell_px * clampf(float(_get_conf("swap_drag_threshold_ratio", 0.3)), 0.1, 0.9)
	if maxf(absf(delta.x), absf(delta.y)) < threshold:
		return
	var dir := Vector2i(int(signf(delta.x)), 0) if absf(delta.x) > absf(delta.y) else Vector2i(0, int(signf(delta.y)))
	_gesture_consumed = true
	_release_pressed_node()
	_try_begin_swap(_drag_origin_cell, dir)

func _end_gesture() -> void:
	_touch_id = -1
	_gesture_consumed = false
	_release_pressed_node()

func _release_pressed_node() -> void:
	if _pressed_node and is_instance_valid(_pressed_node):
		var release_tween: Tween = _pressed_node.create_tween()
		release_tween.tween_property(_pressed_node, "scale", Vector2.ONE, 0.08)
	_pressed_node = null

# =============================================================================
# RUN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_idle()
		State.IDLE:
			if _elapsed >= _duration:
				_finish()
		State.SWAPPING:
			_state_timer -= delta
			if _state_timer <= 0.0:
				if _swap_valid:
					_enter_resolving(0)
				else:
					_enter_idle()
		State.RESOLVING:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_falling()
		State.FALLING:
			_state_timer -= delta
			if _state_timer <= 0.0:
				var matched: Dictionary = _find_matches()
				if not matched.is_empty():
					_enter_resolving(_cascade_depth + 1)
				else:
					_enter_idle()
		State.SHUFFLE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.IDLE

func _enter_idle() -> void:
	_cascade_depth = 0
	if _elapsed >= _duration:
		_finish()
		return
	if not _has_possible_move():
		_enter_shuffle()
		return
	_state = State.IDLE

# =============================================================================
# SWAP
# =============================================================================

func _try_begin_swap(origin: Vector2i, dir: Vector2i) -> void:
	var target: Vector2i = origin + dir
	if target.x < 0 or target.y < 0 or target.x >= _grid_size or target.y >= _grid_size:
		return
	var entry_a_v: Variant = _entry_at(origin)
	var entry_b_v: Variant = _entry_at(target)
	if not (entry_a_v is Dictionary) or not (entry_b_v is Dictionary):
		return
	var swap_sec: float = maxf(0.05, float(_get_conf("swap_tween_sec", 0.15)))
	_swap_entries(origin, target)
	_swap_valid = not _find_matches().is_empty()
	if _swap_valid:
		# Commit: both entries glide to their new cells.
		_animate_entry_to(entry_a_v as Dictionary, _cell_center(target), swap_sec)
		_animate_entry_to(entry_b_v as Dictionary, _cell_center(origin), swap_sec)
		if _ship_cell == origin:
			_ship_cell = target
		elif _ship_cell == target:
			_ship_cell = origin
		_state = State.SWAPPING
		_state_timer = swap_sec + 0.02
	else:
		# Revert: undo the logical swap, play a there-and-back animation.
		_swap_entries(origin, target)
		_animate_entry_round_trip(entry_a_v as Dictionary, _cell_center(origin), _cell_center(target), swap_sec)
		_animate_entry_round_trip(entry_b_v as Dictionary, _cell_center(target), _cell_center(origin), swap_sec)
		_state = State.SWAPPING
		_state_timer = swap_sec * 2.0 + 0.02

func _animate_entry_to(entry: Dictionary, target: Vector2, dur: float) -> void:
	if bool(entry.get("is_ship", false)):
		_animate_ship_to(target, dur)
		return
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var tween: Tween = (node_v as Node2D).create_tween()
		tween.tween_property(node_v, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _animate_entry_round_trip(entry: Dictionary, home: Vector2, away: Vector2, leg_sec: float) -> void:
	if bool(entry.get("is_ship", false)):
		var ship_tween: Tween = create_tween()
		ship_tween.tween_method(_set_ship_pos, home, away, leg_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ship_tween.tween_method(_set_ship_pos, away, home, leg_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var tween: Tween = (node_v as Node2D).create_tween()
		tween.tween_property(node_v, "position", away, leg_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(node_v, "position", home, leg_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_ship_pos(pos: Vector2) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_match3_lock_pos"):
		_player.call("set_match3_lock_pos", pos)

func _animate_ship_to(target: Vector2, dur: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var from: Vector2 = _player.call("get_match3_lock_pos") if _player.has_method("get_match3_lock_pos") else _player.global_position
	var tween: Tween = create_tween()
	tween.tween_method(_set_ship_pos, from, target, maxf(0.05, dur)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# =============================================================================
# RESOLVE (destructions + special effects chain)
# =============================================================================

func _enter_resolving(depth: int) -> void:
	_cascade_depth = depth
	_state = State.RESOLVING
	_step_crystals = 0
	_step_vfx = 0
	_step_pops = 0
	var matched: Dictionary = _find_matches()
	if matched.is_empty():
		_state_timer = 0.05
		return
	var effect_queue: Array = []
	_collect_specials(matched.keys(), effect_queue)
	_destroy_cells(matched.keys(), depth)
	# Drain the special-effects chain: each effect sweeps more cells, which can
	# enqueue more specials (their grid removal acts as the visited set).
	var stagger: float = maxf(0.0, float(_get_conf("effect_chain_stagger_sec", 0.08)))
	var effect_index: int = 0
	while not effect_queue.is_empty():
		var fx: Dictionary = effect_queue.pop_front()
		var swept: Array = _effect_swept_cells(fx)
		_spawn_effect_visual(fx, float(effect_index) * stagger)
		_collect_specials(swept, effect_queue)
		_destroy_cells(swept, depth)
		effect_index += 1
	var pop_sec: float = maxf(0.05, float(_get_conf("resolve_pop_sec", 0.2)))
	_state_timer = pop_sec + float(effect_index) * stagger + 0.05

func _collect_specials(cells: Array, effect_queue: Array) -> void:
	for cell_v in cells:
		var entry_v: Variant = _entry_at(cell_v)
		if entry_v is Dictionary and bool((entry_v as Dictionary).get("is_special", false)):
			effect_queue.append({"cell": cell_v, "effect": str((entry_v as Dictionary).get("special_effect", "clear_line"))})

## Cells swept by a special effect (occupied, never the ship).
func _effect_swept_cells(fx: Dictionary) -> Array:
	var out: Array = []
	var center: Vector2i = fx.get("cell", Vector2i.ZERO)
	var effect: String = str(fx.get("effect", "clear_line"))
	if effect == "clear_circle":
		var radius: int = maxi(1, int(_get_conf("circle_radius_cells", 2)))
		for row in range(maxi(0, center.y - radius), mini(_grid_size, center.y + radius + 1)):
			for col in range(maxi(0, center.x - radius), mini(_grid_size, center.x + radius + 1)):
				var dx: int = col - center.x
				var dy: int = row - center.y
				if dx * dx + dy * dy > radius * radius:
					continue
				_append_sweepable(out, Vector2i(col, row))
	elif effect == "clear_column":
		for row in range(_grid_size):
			_append_sweepable(out, Vector2i(center.x, row))
	else: # clear_line
		for col in range(_grid_size):
			_append_sweepable(out, Vector2i(col, center.y))
	return out

func _append_sweepable(out: Array, cell: Vector2i) -> void:
	var entry_v: Variant = _entry_at(cell)
	if entry_v is Dictionary and not bool((entry_v as Dictionary).get("is_ship", false)):
		out.append(cell)

## Destroys a batch of real cells: one score award (per batch), capped crystal
## and equipment rolls per block, pop animation + explosion VFX (capped).
func _destroy_cells(cells: Array, depth: int) -> void:
	if cells.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	for cell_v in cells:
		centroid += _cell_center(cell_v)
	centroid /= float(cells.size())

	if _game and is_instance_valid(_game):
		var mult: float = 1.0 + maxf(0.0, float(_get_conf("cascade_score_multiplier", 0.5))) * float(depth)
		var points: int = int(round(float(_score_per_block) * float(cells.size()) * mult))
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, centroid)

	var pop_sec: float = maxf(0.05, float(_get_conf("resolve_pop_sec", 0.2)))
	var max_vfx: int = maxi(0, int(_get_conf("max_explosion_vfx_per_step", 10)))
	var max_pops: int = maxi(0, int(_get_conf("max_pop_tweens_per_step", 24)))
	var max_crystals: int = maxi(0, int(_get_conf("max_crystals_per_step", 3)))
	for cell_v in cells:
		var entry_v: Variant = _entry_at(cell_v)
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		if bool(entry.get("is_ship", false)):
			continue
		var at_pos: Vector2 = _cell_center(cell_v)
		_set_entry(cell_v, null)
		_award_block_rewards(at_pos, max_crystals)
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			if _step_pops < max_pops:
				_step_pops += 1
				var pop: Tween = node.create_tween()
				pop.set_parallel(true)
				pop.tween_property(node, "scale", Vector2.ZERO, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				pop.tween_property(node, "modulate:a", 0.0, pop_sec)
				pop.chain().tween_callback(node.queue_free)
			else:
				node.queue_free()
		if _step_vfx < max_vfx and VFXManager:
			_step_vfx += 1
			VFXManager.spawn_explosion(
				at_pos,
				_cell_px * maxf(0.3, float(_get_conf("explosion_size_ratio", 1.1))),
				Color.WHITE,
				self,
				"",
				str(_get_conf("explosion_anim", "")),
				-1.0,
				0.25,
				maxf(0.0, float(_get_conf("explosion_anim_duration", 0.35))),
				false
			)

func _award_block_rewards(at_pos: Vector2, max_crystals: int) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	if _step_crystals < max_crystals \
		and randf() <= clampf(float(_get_conf("crystal_chance", 0.04)), 0.0, 1.0) \
		and _game.has_method("spawn_reward_crystal_at"):
		_step_crystals += 1
		_game.call("spawn_reward_crystal_at", at_pos, {
			"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
		})
	if _equipment_drops_spawned < maxi(0, int(_get_conf("max_equipment_drops", 2))) \
		and randf() <= clampf(float(_get_conf("equipment_drop_chance", 0.01)), 0.0, 1.0) \
		and _game.has_method("spawn_reward_equipment_at"):
		_equipment_drops_spawned += 1
		_game.call("spawn_reward_equipment_at", at_pos, maxf(0.1, float(_get_conf("equipment_quality_mult", 1.0))), {
			"auto_collect_delay_sec": maxf(0.0, float(_get_conf("auto_collect_delay_sec", 2.0))),
			"auto_collect_speed_px_sec": maxf(50.0, float(_get_conf("auto_collect_speed_px_sec", 950.0)))
		})

func _resolve_score_per_block() -> void:
	var s3: int = 0
	if _game and is_instance_valid(_game) and DataManager:
		var level_id: String = str(_game.get("current_world_id")) + "_lvl_" + str(int(_game.get("current_level_index")))
		s3 = int(DataManager.get_level_data(level_id).get("score_3stars", 0))
	if s3 > 0:
		_score_per_block = maxi(1, int(round(float(s3) * maxf(0.0, float(_get_conf("score_block_ratio", 0.0006))))))
	else:
		_score_per_block = maxi(1, int(_get_conf("score_block_fallback", 8)))

# =============================================================================
# GRAVITY + REFILL
# =============================================================================

func _enter_falling() -> void:
	_state = State.FALLING
	var fall_per_cell: float = maxf(0.01, float(_get_conf("fall_sec_per_cell", 0.07)))
	var fall_min: float = maxf(0.02, float(_get_conf("fall_min_sec", 0.12)))
	var fall_max: float = maxf(fall_min, float(_get_conf("fall_max_sec", 0.4)))
	var special_chance: float = clampf(float(_get_conf("special_chance", 0.06)), 0.0, 1.0)
	var longest: float = 0.0

	for col in range(_grid_size):
		var write_row: int = _grid_size - 1
		for row in range(_grid_size - 1, -1, -1):
			var cell := Vector2i(col, row)
			var entry_v: Variant = _entry_at(cell)
			if entry_v == null:
				continue
			if write_row != row:
				var dest := Vector2i(col, write_row)
				_set_entry(dest, entry_v)
				_set_entry(cell, null)
				var dist: int = write_row - row
				var dur: float = clampf(fall_per_cell * float(dist), fall_min, fall_max)
				longest = maxf(longest, dur)
				var entry: Dictionary = entry_v as Dictionary
				if bool(entry.get("is_ship", false)):
					_ship_cell = dest
					_animate_ship_to(_cell_center(dest), dur)
				else:
					var node_v: Variant = entry.get("node", null)
					if node_v is Node2D and is_instance_valid(node_v):
						var fall: Tween = (node_v as Node2D).create_tween()
						fall.tween_property(node_v, "position", _cell_center(dest), dur) \
							.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			write_row -= 1
		# Refill the holes left at the top of the column, stacked above the board.
		var holes: int = write_row + 1
		for k in range(holes):
			var dest_cell := Vector2i(col, k)
			var spawn_pos: Vector2 = _cell_center(Vector2i(col, 0)) - Vector2(0.0, float(holes - k) * _pitch)
			var special: bool = randf() <= special_chance
			var entry: Dictionary = _make_tile_entry(randi() % _tile_type_count, special, spawn_pos)
			_set_entry(dest_cell, entry)
			var dist_cells: float = (float(holes - k) * _pitch + float(k) * _pitch) / _pitch
			var dur2: float = clampf(fall_per_cell * dist_cells, fall_min, fall_max)
			longest = maxf(longest, dur2)
			var node_v2: Variant = entry.get("node", null)
			if node_v2 is Node2D and is_instance_valid(node_v2):
				var drop: Tween = (node_v2 as Node2D).create_tween()
				drop.tween_property(node_v2, "position", _cell_center(dest_cell), dur2) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_state_timer = longest + 0.05

# =============================================================================
# ANTI-DEADLOCK SHUFFLE
# =============================================================================

## Permutes the non-ship entries until the board has no instant match AND at
## least one possible move; falls back to a full type re-roll on failure.
func _enter_shuffle() -> void:
	_state = State.SHUFFLE
	var cells: Array = []
	var entries: Array = []
	for row in range(_grid_size):
		for col in range(_grid_size):
			var cell := Vector2i(col, row)
			var entry_v: Variant = _entry_at(cell)
			if entry_v is Dictionary and not bool((entry_v as Dictionary).get("is_ship", false)):
				cells.append(cell)
				entries.append(entry_v)
	var valid: bool = false
	for attempt in range(40):
		entries.shuffle()
		for i in range(cells.size()):
			_set_entry(cells[i], entries[i])
		if _find_matches().is_empty():
			valid = true
			break
	if not valid or not _has_possible_move():
		# Fallback: re-roll the types in place until clean (reuses the nodes).
		for attempt in range(20):
			for entry_v in entries:
				var entry: Dictionary = entry_v as Dictionary
				entry["type"] = randi() % _tile_type_count
				_apply_tile_visual(entry)
			if _find_matches().is_empty():
				break
	var shuffle_sec: float = maxf(0.1, float(_get_conf("shuffle_tween_sec", 0.45)))
	for i in range(cells.size()):
		var entry: Dictionary = entries[i] as Dictionary
		# entries[i] sits at cells[i] by construction (last permutation applied).
		var target: Vector2 = _cell_center(cells[i])
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var tween: Tween = (node_v as Node2D).create_tween()
			tween.tween_property(node_v, "position", target, shuffle_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_state_timer = shuffle_sec + 0.05

# =============================================================================
# SPECIAL EFFECT VISUALS (shared additive material, pooled)
# =============================================================================

func _spawn_effect_visual(fx: Dictionary, delay: float) -> void:
	var center: Vector2i = fx.get("cell", Vector2i.ZERO)
	var effect: String = str(fx.get("effect", "clear_line"))
	if effect == "clear_circle":
		_play_circle_effect(_cell_center(center), delay)
	else:
		var horizontal: bool = effect == "clear_line"
		var a: Vector2
		var b: Vector2
		if horizontal:
			a = Vector2(_grid_origin.x, _cell_center(center).y)
			b = Vector2(_grid_origin.x + _pitch * float(_grid_size) - (_pitch - _cell_px), _cell_center(center).y)
		else:
			a = Vector2(_cell_center(center).x, _grid_origin.y)
			b = Vector2(_cell_center(center).x, _grid_origin.y + _pitch * float(_grid_size) - (_pitch - _cell_px))
		_play_line_effect(a, b, delay)

## Line sweep: width grows 0 -> line_effect_width_px, then fades out.
func _play_line_effect(a: Vector2, b: Vector2, delay: float) -> void:
	var entry: Dictionary = _acquire_pooled(_line_pool, LINE_POOL_SIZE, func() -> Node2D:
		var line := Line2D.new()
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.material = _add_material
		line.z_as_relative = false
		line.z_index = 55
		add_child(line)
		return line
	)
	var line_v: Variant = entry.get("node", null)
	if not (line_v is Line2D) or not is_instance_valid(line_v):
		return
	var line: Line2D = line_v as Line2D
	line.points = PackedVector2Array([to_local(a), to_local(b)])
	line.default_color = Color(str(_get_conf("line_effect_color", "#BFF0FFD8")))
	line.width = 0.0
	line.modulate.a = 1.0
	line.visible = true
	var grow: float = maxf(0.02, float(_get_conf("line_effect_grow_sec", 0.12)))
	var fade: float = maxf(0.05, float(_get_conf("line_effect_fade_sec", 0.25)))
	var tween: Tween = line.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(line, "width", maxf(2.0, float(_get_conf("line_effect_width_px", 20.0))), grow) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: line.visible = false)
	entry["tween"] = tween

## Circle burst: unit polygon scaled 0 -> radius, then fades out.
func _play_circle_effect(center: Vector2, delay: float) -> void:
	var entry: Dictionary = _acquire_pooled(_circle_pool, CIRCLE_POOL_SIZE, func() -> Node2D:
		var circle := Polygon2D.new()
		var points := PackedVector2Array()
		for i in range(24):
			var angle: float = TAU * float(i) / 24.0
			points.append(Vector2(cos(angle), sin(angle)))
		circle.polygon = points
		circle.material = _add_material
		circle.z_as_relative = false
		circle.z_index = 54
		add_child(circle)
		return circle
	)
	var circle_v: Variant = entry.get("node", null)
	if not (circle_v is Polygon2D) or not is_instance_valid(circle_v):
		return
	var circle: Polygon2D = circle_v as Polygon2D
	circle.position = to_local(center)
	circle.color = Color(str(_get_conf("circle_effect_color", "#FFD56BC8")))
	circle.scale = Vector2.ONE * 0.01
	circle.modulate.a = 1.0
	circle.visible = true
	var radius_px: float = float(maxi(1, int(_get_conf("circle_radius_cells", 2)))) * _pitch + _cell_px * 0.5
	var grow: float = maxf(0.02, float(_get_conf("circle_effect_grow_sec", 0.18)))
	var fade: float = maxf(0.05, float(_get_conf("circle_effect_fade_sec", 0.25)))
	var tween: Tween = circle.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(circle, "scale", Vector2.ONE * radius_px, grow).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(circle, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: circle.visible = false)
	entry["tween"] = tween

## Grabs the first hidden node of the pool, or builds one (bounded), or
## recycles the oldest (killing its tween).
func _acquire_pooled(pool: Array, cap: int, builder: Callable) -> Dictionary:
	for candidate in pool:
		var node_v: Variant = (candidate as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v) and not (node_v as Node2D).visible:
			return candidate
	if pool.size() < cap:
		var built: Node2D = builder.call()
		built.visible = false
		var entry: Dictionary = {"node": built, "tween": null}
		pool.append(entry)
		return entry
	var oldest: Dictionary = pool[0]
	var old_tween_v: Variant = oldest.get("tween", null)
	if old_tween_v is Tween and (old_tween_v as Tween).is_valid():
		(old_tween_v as Tween).kill()
	return oldest

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "Match3CountdownLabel"
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
	queue_free() # tiles, effects and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
