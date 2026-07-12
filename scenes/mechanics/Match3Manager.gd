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
##
## Refonte 12 juillet 2026 (wave_types_improvements) :
## - Grille repositionnee dans les 2/3 BAS de l'ecran (grid_center_y_ratio) ;
##   un BOSS (modele suika_up : pick aleatoire dans bosses[], PH = .tres des
##   boss du jeu) occupe le tiers haut avec une barre de vie HUD. Chaque tuile
##   detruite lui retire un % de vie (bonus cascade), module par
##   boss_toughness_mult (croissant en Libre). Le tuer = recompenses + fin
##   anticipee (story) / respawn d'un nouveau boss (Libre). A 60 s le boss
##   S'ENFUIT vers le haut (story) — pas de bonus.
## - Consommables MARTEAU (detruit une tuile choisie, mode arme) et PEINTURE
##   (3 tuiles -> type majoritaire) : icones bas-droite grisees a 0 stock,
##   badge de quantite, gagnes sur les gros matchs (>= consumable_min_tiles).
## - Variantes rares (scheduler 40-70 s, anti-repetition) : tuiles GIVREES
##   (2 matchs adjacents pour liberer), CAGES (1 match adjacent), BOMBES A
##   RETARDEMENT (compteur de coups, a 0 detruisent leurs voisines SANS
##   recompense), tuile ANCRE (descend d'une ligne par coup, rangee basse =
##   cristaux), GRAVITE LATERALE (fenetre : compaction vers la droite, refill
##   par la gauche), DOUBLE JOKER (drone wildcard temporaire, Libre hauts
##   levels). Plateau a trous = data pure (board_mask[]).
## - Evenements (scheduler 30-45 s) : pluie de speciales, seisme (reshuffle +
##   cristaux), objectif eclair (10 tuiles d'un type en 15 s), mode fievre
##   (matchs >= 4 -> speciale au refill), refill beni (2 triplets garantis).
##   Conditionnels toujours actifs : CASCADE DOREE (profondeur >= 4 -> fenetre
##   score x2) et OVERDRIVE (>= 3 speciales drainees en une resolution -> le
##   prochain tap raye sa ligne au laser).

signal finished

enum State { INTRO, IDLE, SWAPPING, RESOLVING, FALLING, SHUFFLE, BOSS_DEATH, BOSS_ESCAPE, DONE }

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

# Boss (modele suika_up) : vie normalisee 1 -> 0, barre HUD partagee.
var _boss_defs: Array = []
var _boss_def: Dictionary = {}
var _boss_node: Node2D = null
var _boss_sprite: Node2D = null
var _boss_health: float = 1.0
var _boss_center: Vector2 = Vector2.ZERO
var _boss_visual_size: Vector2 = Vector2(200, 200)
var _boss_respawn_timer: float = 0.0
# Cellules mortes (plateau a trous, data board_mask[]) : "col,row" -> true.
var _dead_cells: Dictionary = {}
# Consommables : stocks + icones bas-droite { id: { root, badge, halo, pos } }.
var _hammer_stock: int = 0
var _paint_stock: int = 0
var _hammer_armed: bool = false
var _last_consumable_gain: String = ""
var _consumable_icons: Dictionary = {}
# Variantes rares : scheduler + fenetres (jamais deux fenetres a la fois).
var _variant_timer: float = 0.0
var _last_variant_id: String = ""
var _lateral_gravity_left: float = 0.0
var _joker_left: float = 0.0
var _joker_cell: Vector2i = Vector2i(-1, -1)
var _anchor_cell: Vector2i = Vector2i(-1, -1)
var _move_effects_pending: bool = false
# Evenements : scheduler + fenetres.
var _event_timer: float = 0.0
var _last_event_id: String = ""
var _special_rain_left: float = 0.0
var _fever_left: float = 0.0
var _fever_pending_specials: int = 0
var _objective_type: int = -1
var _objective_left: int = 0
var _objective_time_left: float = 0.0
# Conditionnels toujours actifs.
var _golden_window_left: float = 0.0
var _overdrive_armed: bool = false
# Bandeau + label de statut (objectif / cascade doree / overdrive).
var _event_banner: Label = null
var _banner_time: float = 0.0
var _status_label: Label = null

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

	_parse_board_mask()
	_prepare_assets()
	_compute_geometry()
	_resolve_score_per_block()
	_build_grid()
	_begin_player_mode()
	_begin_hud_mode()
	_ensure_countdown_label()
	_build_consumable_bar()
	if bool(_get_conf("boss_enabled", true)):
		_spawn_boss()

	_variant_timer = randf_range(
		maxf(5.0, float(_get_conf("variant_interval_sec_min", 40.0))),
		maxf(5.0, float(_get_conf("variant_interval_sec_max", 70.0))))
	_event_timer = randf_range(
		maxf(5.0, float(_get_conf("event_interval_sec_min", 30.0))),
		maxf(5.0, float(_get_conf("event_interval_sec_max", 45.0))))

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	# Glide the ship into its board cell during the intro.
	_animate_ship_to(_cell_center(_ship_cell), _state_timer)
	set_process(true)

## Mode libre "continuous" (marqueur countdown_hidden) : la boucle ne finit
## jamais par le timer — le boss respawne au lieu de conclure la vague.
func _is_free_mode() -> bool:
	return bool(_config.get("countdown_hidden", false))

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — plateau et cascades préservés. Les nouvelles valeurs
## s'appliquent aux prochains refills (tuiles existantes inchangées).
func update_free_mode_config(cfg: Dictionary) -> void:
	_tile_type_count = clampi(int(cfg.get("tile_type_count", _tile_type_count)), 3, 6)
	for key in ["special_chance", "boss_toughness_mult", "_free_level_progress"]:
		if cfg.has(key):
			_config[key] = cfg[key]

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
	if _hud.has_method("hide_boss_health"):
		_hud.call("hide_boss_health")

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
	# Grille dans les 2/3 bas (le tiers haut est au boss) ; garde : le bas du
	# plateau ne descend jamais sous la reserve de la barre de consommables.
	var center_y: float = viewport_size.y * clampf(float(_get_conf("grid_center_y_ratio", 0.66)), 0.2, 0.85)
	var bottom_margin: float = maxf(0.0, float(_get_conf("grid_bottom_margin_px", 90.0)))
	var origin_y: float = minf(center_y - board_span * 0.5,
		viewport_size.y - bottom_margin - board_span)
	_grid_origin = Vector2(side_margin, origin_y)

## Plateau a trous (data pure) : board_mask[] = cellules mortes [col, row].
func _parse_board_mask() -> void:
	_dead_cells.clear()
	var mask_v: Variant = _get_conf("board_mask", [])
	if not (mask_v is Array):
		return
	for cell_v in (mask_v as Array):
		if cell_v is Array and (cell_v as Array).size() >= 2:
			var col: int = int((cell_v as Array)[0])
			var row: int = int((cell_v as Array)[1])
			_dead_cells["%d,%d" % [col, row]] = true

func _is_dead_cell(cell: Vector2i) -> bool:
	return _dead_cells.has("%d,%d" % [cell.x, cell.y])

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

	@warning_ignore("integer_division")
	_ship_cell = Vector2i(_grid_size / 2, _grid_size / 2)
	_dead_cells.erase("%d,%d" % [_ship_cell.x, _ship_cell.y]) # le vaisseau n'est jamais sur un trou
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
			if _is_dead_cell(cell):
				_mark_dead_cell_visual(cell)
				continue
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

## Marqueur sombre sur une cellule morte du board_mask (lisibilite du trou).
func _mark_dead_cell_visual(cell: Vector2i) -> void:
	var rect := Polygon2D.new()
	var half: float = _cell_px * 0.5
	rect.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	])
	rect.color = Color(str(_get_conf("dead_cell_color", "#0000004D")))
	rect.position = _cell_center(cell)
	rect.z_as_relative = false
	rect.z_index = 9
	_grid_root.add_child(rect)

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

## Wildcard : vaisseau OU drone-joker temporaire. Ni l'un ni l'autre ne compte
## comme tuile reelle ni ne se detruit.
func _is_wild(entry: Dictionary) -> bool:
	return bool(entry.get("is_ship", false)) or bool(entry.get("is_joker", false))

## Verrouillee (givree/cagee) : ni swap ni match tant que le verrou tient.
func _is_locked(entry: Dictionary) -> bool:
	return int(entry.get("frozen", 0)) > 0 or bool(entry.get("caged", false))

## Swappable : ni verrouillee ni ancre (l'ancre descend seule).
func _is_swappable(entry: Dictionary) -> bool:
	return not _is_locked(entry) and not bool(entry.get("is_anchor", false))

## Returns the REAL cells to destroy (never the ship): every horizontal or
## vertical run of >= 3 compatible cells (tile of type t or a wildcard) holding
## at least 2 real tiles. A run of wildcards + one tile never matches. Locked
## tiles (frozen/caged) and the anchor never match.
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
						compatible = (_is_wild(e) or int(e.get("type", -1)) == t) \
							and not _is_locked(e) and not bool(e.get("is_anchor", false))
					if compatible:
						run_cells.append(cell)
						if not _is_wild(entry_v as Dictionary):
							run_real += 1
					else:
						if run_cells.size() >= 3 and run_real >= 2:
							for c in run_cells:
								var ce: Dictionary = _entry_at(c)
								if not _is_wild(ce):
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
			var entry_a_v: Variant = _entry_at(a)
			if not (entry_a_v is Dictionary) or not _is_swappable(entry_a_v as Dictionary):
				continue
			for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = a + dir
				if b.x >= _grid_size or b.y >= _grid_size:
					continue
				var entry_b_v: Variant = _entry_at(b)
				if not (entry_b_v is Dictionary) or not _is_swappable(entry_b_v as Dictionary):
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
	if _state != State.IDLE or (_elapsed >= _duration and not _is_free_mode()):
		return
	var world: Vector2 = _to_world(screen_pos)
	# Barre de consommables (bas-droite) AVANT le mapping plateau.
	var consumable_id: String = _consumable_at(world)
	if consumable_id != "":
		_on_consumable_tapped(consumable_id)
		return
	var cell: Vector2i = _world_to_cell(world)
	# Marteau armé : le prochain tap détruit la tuile visée (ou désarme).
	if _hammer_armed:
		_hammer_tap(cell)
		return
	# OVERDRIVE armé : le tap raye sa ligne au laser du vaisseau-joker.
	if _overdrive_armed and cell.x >= 0:
		_fire_overdrive(cell.y)
		return
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
	_tick_windows(delta)

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_idle()
		State.IDLE:
			if _elapsed >= _duration and not _is_free_mode():
				_start_boss_escape()
			else:
				_update_schedulers(delta)
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
		State.BOSS_DEATH, State.BOSS_ESCAPE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()

	# Respawn du boss en Libre (la boucle continue apres un kill).
	if _boss_respawn_timer > 0.0 and _state != State.DONE:
		_boss_respawn_timer -= delta
		if _boss_respawn_timer <= 0.0:
			_spawn_boss()

	_update_banner(delta)
	_update_status_label()

## Fenetres temporaires (evenements/variantes) — temps reel, hors pause.
func _tick_windows(delta: float) -> void:
	_special_rain_left = maxf(0.0, _special_rain_left - delta)
	_fever_left = maxf(0.0, _fever_left - delta)
	_golden_window_left = maxf(0.0, _golden_window_left - delta)
	if _lateral_gravity_left > 0.0:
		_lateral_gravity_left -= delta
		if _lateral_gravity_left <= 0.0 and VFXManager and _player and is_instance_valid(_player):
			VFXManager.spawn_floating_text(_cell_center(_ship_cell) + Vector2(0.0, -60.0),
				_translate_or("match3_gravity_end", "GRAVITY BACK!"), Color("#9AD8FF"), self)
	if _joker_left > 0.0:
		_joker_left -= delta
		if _joker_left <= 0.0:
			_expire_joker()
	if _objective_time_left > 0.0:
		_objective_time_left -= delta
		if _objective_time_left <= 0.0 and _objective_left > 0:
			_objective_type = -1
			_objective_left = 0 # objectif manqué, sans pénalité

func _any_window_active() -> bool:
	return _special_rain_left > 0.0 or _fever_left > 0.0 or _lateral_gravity_left > 0.0 \
		or _joker_left > 0.0 or (_objective_time_left > 0.0 and _objective_left > 0)

func _enter_idle() -> void:
	_cascade_depth = 0
	if _elapsed >= _duration and not _is_free_mode():
		_start_boss_escape()
		return
	# Effets du coup joué (une fois le plateau stabilisé) : compte à rebours
	# des bombes + descente de l'ancre ; une détonation enchaîne sa résolution.
	if _move_effects_pending:
		_move_effects_pending = false
		_descend_anchor()
		if _tick_timebombs():
			return # passée en RESOLVING (destruction sans récompense)
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
	# Givrées/cagées/ancre : intouchables au swap.
	if not _is_swappable(entry_a_v as Dictionary) or not _is_swappable(entry_b_v as Dictionary):
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
		if _joker_cell == origin:
			_joker_cell = target
		elif _joker_cell == target:
			_joker_cell = origin
		_move_effects_pending = true # coup joué : timebombs -1, ancre descend
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
	# Cascade dorée (conditionnel toujours actif) : une cascade profonde arme
	# une fenêtre où les scores sont multipliés (consommée par le temps).
	if depth >= maxi(2, int(_get_conf("golden_cascade_depth", 4))) and _golden_window_left <= 0.0:
		_golden_window_left = maxf(2.0, float(_get_conf("golden_cascade_window_sec", 10.0)))
		_show_banner(_translate_or("match3_golden", "GOLDEN CASCADE x2!"), Color("#FFD866"))
	_run_resolution(_find_matches().keys(), depth, true)

## Coeur de résolution partagé (matchs, marteau, overdrive, détonations) :
## détruit le lot initial puis draine la chaîne d'effets spéciaux.
## rewarded=false (bombes à retardement) : ni score, ni cristaux, ni dégâts boss.
func _run_resolution(initial_cells: Array, depth: int, rewarded: bool) -> void:
	_state = State.RESOLVING
	_step_crystals = 0
	_step_vfx = 0
	_step_pops = 0
	if initial_cells.is_empty():
		_state_timer = 0.05
		return
	# Mode fièvre : un gros match génère une tuile explosive au prochain refill.
	if rewarded and _fever_left > 0.0 \
		and initial_cells.size() >= maxi(3, int(_get_conf("fever_min_tiles", 4))):
		_fever_pending_specials += 1
	# Gain de consommables sur les gros matchs.
	if rewarded and initial_cells.size() >= maxi(3, int(_get_conf("consumable_min_tiles", 4))):
		_maybe_gain_consumable(_cell_center(initial_cells[0]))
	var effect_queue: Array = []
	_collect_specials(initial_cells, effect_queue)
	_destroy_cells(initial_cells, depth, rewarded)
	# Drain the special-effects chain: each effect sweeps more cells, which can
	# enqueue more specials (their grid removal acts as the visited set).
	var stagger: float = maxf(0.0, float(_get_conf("effect_chain_stagger_sec", 0.08)))
	var effect_index: int = 0
	while not effect_queue.is_empty():
		var fx: Dictionary = effect_queue.pop_front()
		var swept: Array = _effect_swept_cells(fx)
		_spawn_effect_visual(fx, float(effect_index) * stagger)
		_collect_specials(swept, effect_queue)
		_destroy_cells(swept, depth, rewarded)
		effect_index += 1
	# OVERDRIVE : 3 spéciales drainées dans UNE résolution arment le laser.
	if rewarded and not _overdrive_armed \
		and effect_index >= maxi(2, int(_get_conf("overdrive_specials", 3))):
		_overdrive_armed = true
		_show_banner(_translate_or("match3_overdrive", "OVERDRIVE!"), Color("#FF6BD8"))
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
	if entry_v is Dictionary and not _is_wild(entry_v as Dictionary) \
		and not bool((entry_v as Dictionary).get("is_anchor", false)):
		out.append(cell)

## Destroys a batch of real cells: one score award (per batch), capped crystal
## and equipment rolls per block, pop animation + explosion VFX (capped).
## rewarded=false : détonation punitive — aucun score/cristal/dégât boss.
func _destroy_cells(cells: Array, depth: int, rewarded: bool = true) -> void:
	if cells.is_empty():
		return
	var centroid: Vector2 = Vector2.ZERO
	for cell_v in cells:
		centroid += _cell_center(cell_v)
	centroid /= float(cells.size())

	if rewarded and _game and is_instance_valid(_game):
		var mult: float = 1.0 + maxf(0.0, float(_get_conf("cascade_score_multiplier", 0.5))) * float(depth)
		if _golden_window_left > 0.0:
			mult *= maxf(1.0, float(_get_conf("golden_score_mult", 2.0)))
		var points: int = int(round(float(_score_per_block) * float(cells.size()) * mult))
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, centroid)

	# Dégâts au boss : proportionnels aux tuiles détruites + bonus cascade.
	if rewarded:
		_damage_boss(float(cells.size()) * maxf(0.0, float(_get_conf("boss_damage_per_tile", 0.006))) \
			* (1.0 + maxf(0.0, float(_get_conf("boss_cascade_damage_mult", 0.5))) * float(depth)))

	var pop_sec: float = maxf(0.05, float(_get_conf("resolve_pop_sec", 0.2)))
	var max_vfx: int = maxi(0, int(_get_conf("max_explosion_vfx_per_step", 10)))
	var max_pops: int = maxi(0, int(_get_conf("max_pop_tweens_per_step", 24)))
	var max_crystals: int = maxi(0, int(_get_conf("max_crystals_per_step", 3)))
	for cell_v in cells:
		var entry_v: Variant = _entry_at(cell_v)
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		if _is_wild(entry) or bool(entry.get("is_anchor", false)):
			continue
		var at_pos: Vector2 = _cell_center(cell_v)
		# Objectif éclair : compter les tuiles du type ciblé.
		if rewarded and _objective_left > 0 and _objective_time_left > 0.0 \
			and int(entry.get("type", -1)) == _objective_type:
			_objective_left -= 1
			if _objective_left <= 0:
				_complete_flash_objective(at_pos)
		_set_entry(cell_v, null)
		if rewarded:
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
	# Un match adjacent relâche les verrous voisins (givre -1 charge, cage libérée).
	if rewarded:
		_relax_locks_around(cells)

## Les voisins (4 directions) des cellules détruites perdent un cran de verrou.
func _relax_locks_around(cells: Array) -> void:
	var seen: Dictionary = {}
	for cell_v in cells:
		var center: Vector2i = cell_v
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = center + dir
			var key: String = "%d,%d" % [neighbor.x, neighbor.y]
			if seen.has(key):
				continue
			seen[key] = true
			var entry_v: Variant = _entry_at(neighbor)
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var frozen: int = int(entry.get("frozen", 0))
			if frozen > 0:
				entry["frozen"] = frozen - 1
				if frozen - 1 <= 0:
					_remove_lock_overlay(entry)
				else:
					var overlay_v: Variant = entry.get("overlay", null)
					if overlay_v is Node2D and is_instance_valid(overlay_v):
						(overlay_v as Node2D).modulate.a = 0.55 # givre fissuré
			elif bool(entry.get("caged", false)):
				entry["caged"] = false
				_remove_lock_overlay(entry)

func _remove_lock_overlay(entry: Dictionary) -> void:
	var overlay_v: Variant = entry.get("overlay", null)
	if overlay_v is Node2D and is_instance_valid(overlay_v):
		(overlay_v as Node2D).queue_free()
	entry["overlay"] = null

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

## Gravité + refill, paramétrés par direction : BAS par défaut (compaction par
## colonne, refill par le haut) ; fenêtre GRAVITÉ LATÉRALE : compaction des
## rangées vers la DROITE, refill entrant par la GAUCHE. Les cellules mortes
## (board_mask) sont traversées (les tuiles tombent au travers).
func _enter_falling() -> void:
	_state = State.FALLING
	var fall_per_cell: float = maxf(0.01, float(_get_conf("fall_sec_per_cell", 0.07)))
	var fall_min: float = maxf(0.02, float(_get_conf("fall_min_sec", 0.12)))
	var fall_max: float = maxf(fall_min, float(_get_conf("fall_max_sec", 0.4)))
	var special_chance: float = clampf(float(_get_conf("special_chance", 0.06)), 0.0, 1.0)
	# Pluie de spéciales : chance multipliée pendant la fenêtre.
	if _special_rain_left > 0.0:
		special_chance = clampf(special_chance * maxf(1.0, float(_get_conf("special_rain_mult", 4.0))), 0.0, 1.0)
	var lateral: bool = _lateral_gravity_left > 0.0
	var longest: float = 0.0

	for line in range(_grid_size):
		# Cellules jouables de la ligne, dans l'ordre de compaction (fond -> source).
		var writables: Array = []
		for idx in range(_grid_size - 1, -1, -1):
			var cell: Vector2i = Vector2i(idx, line) if lateral else Vector2i(line, idx)
			if not _is_dead_cell(cell):
				writables.append(cell)
		# Entrées existantes dans le même ordre.
		var entries: Array = []
		for cell_v in writables:
			var entry_v: Variant = _entry_at(cell_v)
			if entry_v != null:
				entries.append(entry_v)
			_set_entry(cell_v, null)
		# Compaction : les entrées remplissent le fond, les trous restent en source.
		for i in range(writables.size()):
			if i < entries.size():
				var dest: Vector2i = writables[i]
				var entry: Dictionary = entries[i] as Dictionary
				_set_entry(dest, entry)
				var target: Vector2 = _cell_center(dest)
				if bool(entry.get("is_ship", false)):
					if _ship_cell != dest:
						_ship_cell = dest
						var dur_ship: float = clampf(fall_per_cell * 2.0, fall_min, fall_max)
						longest = maxf(longest, dur_ship)
						_animate_ship_to(target, dur_ship)
				else:
					if bool(entry.get("is_joker", false)):
						_joker_cell = dest
					var node_v: Variant = entry.get("node", null)
					if node_v is Node2D and is_instance_valid(node_v):
						var node: Node2D = node_v as Node2D
						var dist: float = node.position.distance_to(target) / maxf(1.0, _pitch)
						if dist > 0.01:
							var dur: float = clampf(fall_per_cell * dist, fall_min, fall_max)
							longest = maxf(longest, dur)
							var fall: Tween = node.create_tween()
							fall.tween_property(node, "position", target, dur) \
								.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				# Refill : la nouvelle tuile arrive empilée hors plateau côté source.
				var dest2: Vector2i = writables[i]
				var stack: int = i - entries.size() + 1
				var spawn_pos: Vector2
				if lateral:
					spawn_pos = _cell_center(Vector2i(0, line)) - Vector2(float(stack) * _pitch, 0.0)
				else:
					spawn_pos = _cell_center(Vector2i(line, 0)) - Vector2(0.0, float(stack) * _pitch)
				var special: bool = randf() <= special_chance
				# Mode fièvre : spéciales garanties en attente (gros matchs).
				if not special and _fever_pending_specials > 0:
					special = true
					_fever_pending_specials -= 1
				var new_entry: Dictionary = _make_tile_entry(randi() % _tile_type_count, special, spawn_pos)
				_set_entry(dest2, new_entry)
				var target2: Vector2 = _cell_center(dest2)
				var dist2: float = spawn_pos.distance_to(target2) / maxf(1.0, _pitch)
				var dur2: float = clampf(fall_per_cell * dist2, fall_min, fall_max)
				longest = maxf(longest, dur2)
				var node_v2: Variant = new_entry.get("node", null)
				if node_v2 is Node2D and is_instance_valid(node_v2):
					var drop: Tween = (node_v2 as Node2D).create_tween()
					drop.tween_property(node_v2, "position", target2, dur2) \
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
			# Vaisseau, joker, ancre et verrouillées restent en place au shuffle.
			if entry_v is Dictionary and not _is_wild(entry_v as Dictionary) \
				and not bool((entry_v as Dictionary).get("is_anchor", false)) \
				and not _is_locked(entry_v as Dictionary):
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
# BOSS (modele suika_up : pick aleatoire, barre HUD, degats par match, fuite)
# =============================================================================

func _spawn_boss() -> void:
	_boss_defs = []
	var defs_v: Variant = _get_conf("bosses", [])
	if defs_v is Array:
		for def_v in (defs_v as Array):
			if def_v is Dictionary:
				_boss_defs.append(def_v)
	if _boss_defs.is_empty():
		return
	var forced_id: String = str(_get_conf("boss_id", ""))
	_boss_def = _boss_defs[randi() % _boss_defs.size()]
	if forced_id != "":
		for def_v in _boss_defs:
			if str((def_v as Dictionary).get("id", "")) == forced_id:
				_boss_def = def_v
				break
	_boss_health = 1.0
	_boss_respawn_timer = 0.0
	var viewport_size: Vector2 = get_viewport_rect().size
	var area_h: float = viewport_size.y * clampf(float(_get_conf("boss_area_height_ratio", 0.3)), 0.1, 0.5)
	_boss_center = Vector2(viewport_size.x * 0.5, area_h * 0.55)
	_build_boss_node()
	if _hud and is_instance_valid(_hud) and _hud.has_method("show_boss_health"):
		_hud.call("show_boss_health", _boss_display_name(), 1000)
		_hud.call("update_boss_health", 1000, 1000)

func _boss_display_name() -> String:
	return _translate_or(str(_boss_def.get("name_key", "")), str(_boss_def.get("id", "Boss")))

## AnimatedSprite2D depuis asset_anim (.tres SpriteFrames des boss du jeu — PH
## assumes), fallback hexagone ; arrivee en tween depuis le haut de l'ecran.
func _build_boss_node() -> void:
	if _boss_node and is_instance_valid(_boss_node):
		_boss_node.queue_free()
	_boss_node = Node2D.new()
	_boss_node.name = "Match3Boss"
	_boss_node.z_as_relative = false
	_boss_node.z_index = 9
	var fit_px: float = maxf(80.0, float(_get_conf("boss_fit_px", 210.0)))
	_boss_visual_size = Vector2(fit_px, fit_px)
	var frames_res: Resource = _load_cached_resource(str(_boss_def.get("asset_anim", "")))
	var built: bool = false
	if frames_res is SpriteFrames:
		var frames: SpriteFrames = frames_res as SpriteFrames
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name):
			var names: PackedStringArray = frames.get_animation_names()
			if names.size() > 0:
				anim_name = StringName(names[0])
		if frames.has_animation(anim_name):
			anim.play(anim_name)
			if frames.get_frame_count(anim_name) > 0:
				var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
				if frame_tex:
					var f_size: Vector2 = frame_tex.get_size()
					if f_size.x > 0.0 and f_size.y > 0.0:
						var s: float = fit_px / maxf(f_size.x, f_size.y)
						anim.scale = Vector2.ONE * s
						_boss_visual_size = f_size * s
		_boss_node.add_child(anim)
		_boss_sprite = anim
		built = true
	if not built:
		var hex := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 - PI * 0.5
			pts.append(Vector2(cos(a), sin(a)) * fit_px * 0.5)
		hex.polygon = pts
		hex.color = Color("#B455E8")
		_boss_node.add_child(hex)
		_boss_sprite = hex
	_boss_node.position = Vector2(_boss_center.x, -_boss_visual_size.y)
	add_child(_boss_node)
	var arrival: Tween = _boss_node.create_tween()
	arrival.tween_property(_boss_node, "position", _boss_center,
		maxf(0.2, float(_get_conf("boss_arrival_sec", 0.9)))) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## pct = degats bruts (avant boss_toughness_mult, croissant en Libre).
func _damage_boss(pct: float) -> void:
	if _boss_node == null or not is_instance_valid(_boss_node) or _boss_health <= 0.0 or pct <= 0.0:
		return
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	var toughness: float = maxf(0.1, float(_get_conf("boss_toughness_mult", 1.0)))
	var applied: float = pct / toughness
	_boss_health = clampf(_boss_health - applied, 0.0, 1.0)
	if _hud and is_instance_valid(_hud) and _hud.has_method("update_boss_health"):
		_hud.call("update_boss_health", int(round(_boss_health * 1000.0)), 1000)
	if VFXManager and _boss_sprite and is_instance_valid(_boss_sprite):
		VFXManager.flash_sprite(_boss_node, Color(1.0, 0.7, 0.7), 0.1)
		if applied >= 0.03:
			VFXManager.spawn_floating_text(_boss_node.position + Vector2(0.0, -_boss_visual_size.y * 0.4),
				"-%d%%" % int(round(applied * 100.0)), Color("#FF8A5C"), self)
	if _boss_health <= 0.0:
		_on_boss_killed()

func _on_boss_killed() -> void:
	_grant_boss_kill_rewards()
	if VFXManager:
		VFXManager.spawn_explosion(_boss_node.position,
			_boss_visual_size.length() * 0.8, Color(1.0, 0.6, 0.3), self,
			"", str(_get_conf("boss_death_explosion", "res://assets/vfx/boss_explosion.tres")),
			-1.0, 0.3, 0.7, false)
		VFXManager.screen_shake(8.0, 0.35)
	var death_sec: float = maxf(0.3, float(_get_conf("boss_death_anim_sec", 1.6)))
	var fade: Tween = _boss_node.create_tween()
	fade.tween_property(_boss_node, "modulate:a", 0.0, death_sec * 0.8)
	fade.tween_callback(_boss_node.queue_free)
	if _is_free_mode():
		# Libre : la boucle continue, un nouveau boss arrive (toughness relue live).
		if _hud and is_instance_valid(_hud) and _hud.has_method("hide_boss_health"):
			_hud.call("hide_boss_health")
		_boss_respawn_timer = maxf(0.5, float(_get_conf("boss_respawn_delay_sec", 2.5)))
	else:
		# Story : victoire anticipee apres l'anim de mort.
		_state = State.BOSS_DEATH
		_state_timer = death_sec

func _grant_boss_kill_rewards() -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var center: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
	var points: int = maxi(0, int(_get_conf("boss_kill_score", 4000)))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, center)
	if _game.has_method("spawn_reward_crystal_at"):
		for i in range(maxi(1, int(_get_conf("boss_kill_crystals", 8)))):
			_game.call("spawn_reward_crystal_at",
				center + Vector2(randf_range(-60.0, 60.0), randf_range(-30.0, 30.0)), {
					"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
				})
	if _game.has_method("spawn_reward_equipment_at"):
		var extra: Dictionary = {
			"auto_collect_delay_sec": maxf(0.0, float(_get_conf("auto_collect_delay_sec", 2.0))),
			"auto_collect_speed_px_sec": maxf(50.0, float(_get_conf("auto_collect_speed_px_sec", 950.0)))
		}
		var min_rarity: String = str(_get_conf("boss_kill_loot_min_rarity", "uncommon"))
		if min_rarity != "":
			_game.call("spawn_reward_equipment_at", center, 1.0, extra, min_rarity)
		else:
			_game.call("spawn_reward_equipment_at", center,
				maxf(1.0, float(_get_conf("boss_kill_loot_quality_mult", 8.0))), extra)

## Fin du timer (story) : le boss remonte hors ecran, pas de bonus.
func _start_boss_escape() -> void:
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	if _boss_node == null or not is_instance_valid(_boss_node) or _boss_health <= 0.0:
		_finish()
		return
	_state = State.BOSS_ESCAPE
	_state_timer = maxf(0.2, float(_get_conf("boss_escape_anim_sec", 1.0)))
	var escape: Tween = _boss_node.create_tween()
	escape.tween_property(_boss_node, "position:y", -_boss_visual_size.y, _state_timer) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _hud and is_instance_valid(_hud) and _hud.has_method("hide_boss_health"):
		_hud.call("hide_boss_health")

# =============================================================================
# CONSOMMABLES (marteau / peinture) — icones bas-droite, badge de stock
# =============================================================================

func _build_consumable_bar() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var icon_px: float = maxf(32.0, float(_get_conf("consumable_icon_px", 64.0)))
	var margin: float = maxf(0.0, float(_get_conf("consumable_margin_px", 16.0)))
	var gap: float = maxf(0.0, float(_get_conf("consumable_gap_px", 14.0)))
	var bottom_off: float = maxf(10.0, float(_get_conf("consumable_bottom_offset_px", 46.0)))
	var defs: Array = [
		{ "id": "paint", "asset_key": "paint_icon_asset", "tint": "#7FE58C", "glyph": "P" },
		{ "id": "hammer", "asset_key": "hammer_icon_asset", "tint": "#FFB05C", "glyph": "M" }
	]
	for i in range(defs.size()):
		var def: Dictionary = defs[i]
		var pos := Vector2(viewport_size.x - margin - icon_px * 0.5 - (icon_px + gap) * float(i),
			viewport_size.y - bottom_off)
		var root := Node2D.new()
		root.name = "Consumable_%s" % str(def["id"])
		root.z_as_relative = false
		root.z_index = 61
		root.position = pos
		var built: bool = false
		var icon_res: Resource = _load_cached_resource(str(_get_conf(str(def["asset_key"]), "")))
		if icon_res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = icon_res as Texture2D
			var tex_size: Vector2 = (icon_res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (icon_px / maxf(tex_size.x, tex_size.y))
			root.add_child(sprite)
			built = true
		if not built:
			var circle := Polygon2D.new()
			var pts := PackedVector2Array()
			for k in range(20):
				var a: float = TAU * float(k) / 20.0
				pts.append(Vector2(cos(a), sin(a)) * icon_px * 0.5)
			circle.polygon = pts
			circle.color = Color(str(def["tint"]))
			root.add_child(circle)
			var glyph := Label.new()
			glyph.text = str(def["glyph"])
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			glyph.add_theme_font_size_override("font_size", int(icon_px * 0.5))
			glyph.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
			glyph.size = Vector2(icon_px, icon_px)
			glyph.position = -Vector2(icon_px, icon_px) * 0.5
			root.add_child(glyph)
		# Halo d'armement (marteau) : anneau cache par defaut.
		var halo := Line2D.new()
		var halo_pts := PackedVector2Array()
		for k in range(24):
			var a2: float = TAU * float(k) / 24.0
			halo_pts.append(Vector2(cos(a2), sin(a2)) * (icon_px * 0.62))
		halo.points = halo_pts
		halo.closed = true
		halo.width = 4.0
		halo.default_color = Color("#FFF3B0")
		halo.material = _add_material
		halo.visible = false
		root.add_child(halo)
		# Badge de quantite (coin haut-droit).
		var badge := Label.new()
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", int(icon_px * 0.38))
		badge.add_theme_color_override("font_color", Color("#FFFFFF"))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 4)
		badge.position = Vector2(icon_px * 0.18, -icon_px * 0.62)
		root.add_child(badge)
		add_child(root)
		_consumable_icons[str(def["id"])] = { "root": root, "badge": badge, "halo": halo, "pos": pos, "radius": icon_px * 0.62 }
	_refresh_consumable_icons()

func _refresh_consumable_icons() -> void:
	for id in _consumable_icons.keys():
		var icon: Dictionary = _consumable_icons[id]
		var stock: int = _hammer_stock if str(id) == "hammer" else _paint_stock
		var root_v: Variant = icon.get("root", null)
		if root_v is Node2D and is_instance_valid(root_v):
			# Grisee (disabled) a 0 stock.
			(root_v as Node2D).modulate = Color(1, 1, 1, 1) if stock > 0 else Color(0.42, 0.42, 0.42, 0.55)
		var badge_v: Variant = icon.get("badge", null)
		if badge_v is Label and is_instance_valid(badge_v):
			(badge_v as Label).text = str(stock) if stock > 0 else ""
		var halo_v: Variant = icon.get("halo", null)
		if halo_v is Line2D and is_instance_valid(halo_v):
			(halo_v as Line2D).visible = str(id) == "hammer" and _hammer_armed

## Icone touchee par un tap monde (rayon genereux) — "" sinon.
func _consumable_at(world: Vector2) -> String:
	for id in _consumable_icons.keys():
		var icon: Dictionary = _consumable_icons[id]
		if world.distance_to(icon.get("pos", Vector2.ZERO)) <= float(icon.get("radius", 40.0)):
			return str(id)
	return ""

func _on_consumable_tapped(id: String) -> void:
	if id == "hammer":
		if _hammer_stock <= 0:
			return
		_hammer_armed = not _hammer_armed
	elif id == "paint":
		if _paint_stock <= 0:
			return
		_hammer_armed = false
		_use_paint()
	_refresh_consumable_icons()

## Marteau armé : tap sur une tuile (jamais vaisseau/joker) = destruction.
func _hammer_tap(cell: Vector2i) -> void:
	var entry_v: Variant = _entry_at(cell) if cell.x >= 0 else null
	if entry_v is Dictionary and not _is_wild(entry_v as Dictionary):
		_hammer_armed = false
		_hammer_stock = maxi(0, _hammer_stock - 1)
		if VFXManager:
			VFXManager.screen_shake(4.0, 0.15)
		_run_resolution([cell], 0, true)
	else:
		_hammer_armed = false # tap hors plateau/vaisseau = désarme
	_refresh_consumable_icons()

## Peinture : 3 tuiles aléatoires converties vers le type le plus présent.
func _use_paint() -> void:
	var counts: Dictionary = {}
	var candidates: Array = []
	for row in range(_grid_size):
		for col in range(_grid_size):
			var entry_v: Variant = _entry_at(Vector2i(col, row))
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			if _is_wild(entry) or bool(entry.get("is_anchor", false)) or _is_locked(entry) \
				or entry.has("timebomb"):
				continue
			var t: int = int(entry.get("type", -1))
			counts[t] = int(counts.get(t, 0)) + 1
			candidates.append(entry)
	if candidates.is_empty():
		return
	var target_type: int = 0
	var best: int = -1
	for t in counts.keys():
		if int(counts[t]) > best:
			best = int(counts[t])
			target_type = int(t)
	_paint_stock = maxi(0, _paint_stock - 1)
	candidates.shuffle()
	var converted: int = 0
	for entry_v in candidates:
		if converted >= 3:
			break
		var entry: Dictionary = entry_v as Dictionary
		if int(entry.get("type", -1)) == target_type:
			continue
		entry["type"] = target_type
		_apply_tile_visual(entry)
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
			VFXManager.flash_sprite(node_v as Node2D, Color.WHITE, 0.15)
		converted += 1
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.spawn_floating_text(_cell_center(_ship_cell) + Vector2(0.0, -50.0),
			_translate_or("match3_paint_used", "PAINT!"), Color("#7FE58C"), self)
	if not _find_matches().is_empty():
		_enter_resolving(0)

## Gain sur gros match : anti-répétition, caps de stock, floating.
func _maybe_gain_consumable(at_pos: Vector2) -> void:
	var cap: int = maxi(1, int(_get_conf("consumable_max_stock", 5)))
	var picks: Array = ["hammer", "paint"]
	picks.shuffle()
	for id in picks:
		if str(id) == _last_consumable_gain and picks.size() > 1:
			continue
		var chance_key: String = "hammer_drop_chance" if str(id) == "hammer" else "paint_drop_chance"
		if randf() > clampf(float(_get_conf(chance_key, 0.05)), 0.0, 1.0):
			continue
		if str(id) == "hammer":
			if _hammer_stock >= cap:
				continue
			_hammer_stock += 1
		else:
			if _paint_stock >= cap:
				continue
			_paint_stock += 1
		_last_consumable_gain = str(id)
		if VFXManager:
			VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -40.0),
				_translate_or("match3_hammer" if str(id) == "hammer" else "match3_paint",
					"HAMMER +1" if str(id) == "hammer" else "PAINT +1"),
				Color("#FFB05C") if str(id) == "hammer" else Color("#7FE58C"), self)
		_refresh_consumable_icons()
		return

# =============================================================================
# VARIANTES RARES + ÉVÉNEMENTS (schedulers anti-répétition, fenêtres exclusives)
# =============================================================================

func _update_schedulers(delta: float) -> void:
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = randf_range(
			maxf(5.0, float(_get_conf("event_interval_sec_min", 30.0))),
			maxf(5.0, float(_get_conf("event_interval_sec_max", 45.0))))
		if not _any_window_active():
			_trigger_random_event()
	_variant_timer -= delta
	if _variant_timer <= 0.0:
		_variant_timer = randf_range(
			maxf(5.0, float(_get_conf("variant_interval_sec_min", 40.0))),
			maxf(5.0, float(_get_conf("variant_interval_sec_max", 70.0))))
		if not _any_window_active():
			_trigger_random_variant()

func _weighted_pick(weights: Dictionary, last_id: String) -> String:
	var pool: Dictionary = weights.duplicate()
	for key in pool.keys().duplicate():
		if float(pool[key]) <= 0.0:
			pool.erase(key)
	if pool.size() > 1:
		pool.erase(last_id)
	if pool.is_empty():
		return ""
	var total: float = 0.0
	for key in pool:
		total += float(pool[key])
	var roll: float = randf() * total
	for key in pool:
		roll -= float(pool[key])
		if roll <= 0.0:
			return str(key)
	return ""

func _trigger_random_event() -> void:
	var picked: String = _weighted_pick({
		"special_rain": float(_get_conf("special_rain_weight", 25.0)),
		"quake": float(_get_conf("quake_weight", 15.0)),
		"objective": float(_get_conf("flash_objective_weight", 20.0)),
		"fever": float(_get_conf("fever_weight", 20.0)),
		"blessed": float(_get_conf("blessed_weight", 20.0))
	}, _last_event_id)
	if picked == "":
		return
	_last_event_id = picked
	match picked:
		"special_rain":
			_special_rain_left = maxf(2.0, float(_get_conf("special_rain_duration_sec", 10.0)))
			_show_banner(_translate_or("match3_event_special_rain", "SPECIAL RAIN!"), Color("#C77CFF"))
		"quake":
			_show_banner(_translate_or("match3_event_quake", "QUAKE!"), Color("#FFB05C"))
			if VFXManager:
				VFXManager.screen_shake(7.0, 0.4)
			if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(1, int(_get_conf("quake_crystals", 3))))
			_enter_shuffle()
		"objective":
			_objective_type = randi() % _tile_type_count
			_objective_left = maxi(3, int(_get_conf("objective_count", 10)))
			_objective_time_left = maxf(5.0, float(_get_conf("objective_time_sec", 15.0)))
			_show_banner(_translate_or("match3_event_objective", "FLASH OBJECTIVE!"), _objective_tint())
		"fever":
			_fever_left = maxf(2.0, float(_get_conf("fever_duration_sec", 5.0)))
			_show_banner(_translate_or("match3_event_fever", "FEVER!"), Color("#FF6B9A"))
		"blessed":
			_show_banner(_translate_or("match3_event_blessed", "BLESSED REFILL!"), Color("#8FD3FF"))
			_bless_board()

func _objective_tint() -> Color:
	if _objective_type >= 0 and _objective_type < _tile_sets.size():
		var type_set: Dictionary = _tile_sets[_objective_type]
		var tint: Color = type_set.get("tint", Color.WHITE) as Color
		if tint.is_equal_approx(Color.WHITE):
			return type_set.get("fallback", Color.WHITE) as Color
		return tint
	return Color.WHITE

## Objectif éclair réussi : pluie de cristaux.
func _complete_flash_objective(at_pos: Vector2) -> void:
	_objective_type = -1
	_objective_time_left = 0.0
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -50.0),
			_translate_or("match3_objective_done", "OBJECTIVE DONE!"), Color("#7CFC9A"), self)
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", maxi(1, int(_get_conf("objective_crystals", 6))))

## Refill béni (immédiat) : 2 triplets forcés dans les rangées hautes, la
## résolution enchaîne — relance garantie du rythme.
func _bless_board() -> void:
	var forced: int = 0
	for attempt in range(30):
		if forced >= 2:
			break
		var row: int = randi() % maxi(1, int(float(_grid_size) * 0.4))
		var col: int = randi() % maxi(1, _grid_size - 2)
		var t: int = randi() % _tile_type_count
		var ok: bool = true
		for k in range(3):
			var entry_v: Variant = _entry_at(Vector2i(col + k, row))
			if not (entry_v is Dictionary) or _is_wild(entry_v as Dictionary) \
				or bool((entry_v as Dictionary).get("is_anchor", false)) \
				or _is_locked(entry_v as Dictionary):
				ok = false
				break
		if not ok:
			continue
		for k in range(3):
			var entry: Dictionary = _entry_at(Vector2i(col + k, row))
			entry["type"] = t
			_apply_tile_visual(entry)
		forced += 1
	if forced > 0 and not _find_matches().is_empty():
		_enter_resolving(0)

func _trigger_random_variant() -> void:
	var weights: Dictionary = {
		"frost": float(_get_conf("frost_weight", 20.0)),
		"cage": float(_get_conf("cage_weight", 20.0)),
		"timebomb": float(_get_conf("timebomb_weight", 15.0)),
		"anchor": float(_get_conf("anchor_weight", 15.0)),
		"lateral": float(_get_conf("lateral_gravity_weight", 15.0))
	}
	# Double joker : hauts levels Libre uniquement (gate progression).
	var progress_v: Variant = _config.get("_free_level_progress", null)
	if (progress_v is float or progress_v is int) \
		and float(progress_v) >= clampf(float(_get_conf("double_joker_min_level_progress", 0.4)), 0.0, 1.0):
		weights["joker"] = float(_get_conf("double_joker_weight", 15.0))
	if _find_anchor_cell().x >= 0:
		weights.erase("anchor") # une seule ancre à la fois
	var picked: String = _weighted_pick(weights, _last_variant_id)
	if picked == "":
		return
	_last_variant_id = picked
	match picked:
		"frost":
			_apply_lock_batch("frost", maxi(1, int(_get_conf("frost_count", 5))))
			_show_banner(_translate_or("match3_variant_frost", "FROZEN TILES!"), Color("#8FE8FF"))
		"cage":
			_apply_lock_batch("cage", maxi(1, int(_get_conf("cage_count", 4))))
			_show_banner(_translate_or("match3_variant_cage", "CAGES!"), Color("#C8D2E8"))
		"timebomb":
			_apply_timebombs(maxi(1, int(_get_conf("timebomb_count", 2))))
			_show_banner(_translate_or("match3_variant_timebomb", "TIME BOMBS!"), Color("#FF5C5C"))
		"anchor":
			_spawn_anchor()
		"lateral":
			_lateral_gravity_left = maxf(5.0, float(_get_conf("lateral_gravity_duration_sec", 25.0)))
			_show_banner(_translate_or("match3_lateral", "SIDE GRAVITY!"), Color("#9AD8FF"))
		"joker":
			_spawn_joker()

## Tuiles candidates aux verrous/bombes : normales, ni spéciales ni marquées.
func _plain_tile_cells() -> Array:
	var out: Array = []
	for row in range(_grid_size):
		for col in range(_grid_size):
			var cell := Vector2i(col, row)
			var entry_v: Variant = _entry_at(cell)
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			if _is_wild(entry) or bool(entry.get("is_anchor", false)) \
				or bool(entry.get("is_special", false)) or _is_locked(entry) \
				or entry.has("timebomb"):
				continue
			out.append(cell)
	return out

func _apply_lock_batch(kind: String, count: int) -> void:
	var cells: Array = _plain_tile_cells()
	cells.shuffle()
	for i in range(mini(count, cells.size())):
		var entry: Dictionary = _entry_at(cells[i])
		if kind == "frost":
			entry["frozen"] = 2
		else:
			entry["caged"] = true
		_attach_lock_overlay(entry, kind)

func _apply_timebombs(count: int) -> void:
	var cells: Array = _plain_tile_cells()
	cells.shuffle()
	for i in range(mini(count, cells.size())):
		var entry: Dictionary = _entry_at(cells[i])
		entry["timebomb"] = maxi(2, int(_get_conf("timebomb_moves", 6)))
		_attach_lock_overlay(entry, "timebomb")

## Overlay de verrou/bombe sur la tuile : asset dédié sinon PH — givre = voile
## bleuté, cage = hachures verticales (demande user), bombe = anneau rouge
## pulsant + compteur.
func _attach_lock_overlay(entry: Dictionary, kind: String) -> void:
	var node_v: Variant = entry.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var node: Node2D = node_v as Node2D
	_remove_lock_overlay(entry)
	var overlay := Node2D.new()
	overlay.name = "LockOverlay"
	overlay.z_index = 3
	var half: float = _cell_px * 0.46
	var asset_key: String = "%s_overlay_asset" % kind
	var asset_res: Resource = _load_cached_resource(str(_get_conf(asset_key, "")))
	if asset_res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = asset_res as Texture2D
		var tex_size: Vector2 = (asset_res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (_cell_px / maxf(tex_size.x, tex_size.y))
		overlay.add_child(sprite)
	elif kind == "frost":
		var veil := Polygon2D.new()
		veil.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
		])
		veil.color = Color("#BFE8FF66")
		overlay.add_child(veil)
	elif kind == "cage":
		for k in range(4):
			var bar := Line2D.new()
			var x: float = -half + (half * 2.0) * (float(k) + 0.5) / 4.0
			bar.points = PackedVector2Array([Vector2(x, -half), Vector2(x, half)])
			bar.width = maxf(2.0, _cell_px * 0.06)
			bar.default_color = Color("#C8D2E8CC")
			overlay.add_child(bar)
	else: # timebomb : anneau rouge
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * half)
		ring.points = pts
		ring.closed = true
		ring.width = 4.0
		ring.default_color = Color("#FF5C5C")
		ring.material = _add_material
		overlay.add_child(ring)
		var pulse: Tween = ring.create_tween()
		pulse.set_loops()
		pulse.tween_property(ring, "modulate:a", 0.35, 0.4)
		pulse.tween_property(ring, "modulate:a", 1.0, 0.4)
	if kind == "timebomb":
		var count_label := Label.new()
		count_label.name = "TimebombCount"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", int(_cell_px * 0.42))
		count_label.add_theme_color_override("font_color", Color("#FFFFFF"))
		count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		count_label.add_theme_constant_override("outline_size", 4)
		count_label.size = Vector2(_cell_px, _cell_px)
		count_label.position = -Vector2(_cell_px, _cell_px) * 0.5
		count_label.text = str(int(entry.get("timebomb", 0)))
		overlay.add_child(count_label)
		entry["count_label"] = count_label
	node.add_child(overlay)
	entry["overlay"] = overlay

## Coup joué : les compteurs des bombes descendent ; à 0 -> détonation SANS
## récompense (voisines comprises). Retourne true si une résolution a démarré.
func _tick_timebombs() -> bool:
	var due: Array = []
	for row in range(_grid_size):
		for col in range(_grid_size):
			var cell := Vector2i(col, row)
			var entry_v: Variant = _entry_at(cell)
			if not (entry_v is Dictionary) or not (entry_v as Dictionary).has("timebomb"):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var left: int = int(entry.get("timebomb", 0)) - 1
			entry["timebomb"] = left
			var label_v: Variant = entry.get("count_label", null)
			if label_v is Label and is_instance_valid(label_v):
				(label_v as Label).text = str(maxi(0, left))
			if left <= 0:
				due.append(cell)
	if due.is_empty():
		return false
	var cells: Dictionary = {}
	for cell_v in due:
		var center: Vector2i = cell_v
		cells["%d,%d" % [center.x, center.y]] = center
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = center + dir
			var entry_v: Variant = _entry_at(n)
			if entry_v is Dictionary and not _is_wild(entry_v as Dictionary) \
				and not bool((entry_v as Dictionary).get("is_anchor", false)):
				cells["%d,%d" % [n.x, n.y]] = n
	if VFXManager:
		VFXManager.screen_shake(6.0, 0.25)
	_run_resolution(cells.values(), 0, false)
	return true

# --- Ancre ---

func _find_anchor_cell() -> Vector2i:
	for row in range(_grid_size):
		for col in range(_grid_size):
			var entry_v: Variant = _entry_at(Vector2i(col, row))
			if entry_v is Dictionary and bool((entry_v as Dictionary).get("is_anchor", false)):
				return Vector2i(col, row)
	return Vector2i(-1, -1)

## Remplace une tuile de la rangée haute par l'ancre (objectif « ingrédient »).
func _spawn_anchor() -> void:
	var candidates: Array = []
	for col in range(_grid_size):
		var cell := Vector2i(col, 0)
		var entry_v: Variant = _entry_at(cell)
		if entry_v is Dictionary and not _is_wild(entry_v as Dictionary) \
			and not _is_locked(entry_v as Dictionary):
			candidates.append(cell)
	if candidates.is_empty():
		return
	var cell: Vector2i = candidates[randi() % candidates.size()]
	var old: Dictionary = _entry_at(cell)
	var old_node_v: Variant = old.get("node", null)
	if old_node_v is Node2D and is_instance_valid(old_node_v):
		(old_node_v as Node2D).queue_free()
	var node := Node2D.new()
	node.name = "AnchorTile"
	node.position = _cell_center(cell)
	_grid_root.add_child(node)
	var entry: Dictionary = { "node": node, "sprite": null, "type": -2,
		"is_ship": false, "is_special": false, "special_effect": "", "is_anchor": true }
	var asset_res: Resource = _load_cached_resource(str(_get_conf("anchor_tile_asset", "")))
	if asset_res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = asset_res as Texture2D
		var tex_size: Vector2 = (asset_res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (_cell_px * 0.82 / maxf(tex_size.x, tex_size.y))
		node.add_child(sprite)
		entry["sprite"] = sprite
	else:
		# PH : ancre dorée procédurale (anneau + tige + croisillon).
		var gold := Color("#FFD866")
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(16):
			var a: float = TAU * float(k) / 16.0
			pts.append(Vector2(cos(a), sin(a)) * _cell_px * 0.18 + Vector2(0.0, _cell_px * 0.2))
		ring.points = pts
		ring.closed = true
		ring.width = 4.0
		ring.default_color = gold
		node.add_child(ring)
		var rod := Line2D.new()
		rod.points = PackedVector2Array([Vector2(0.0, _cell_px * 0.02), Vector2(0.0, -_cell_px * 0.34)])
		rod.width = 5.0
		rod.default_color = gold
		node.add_child(rod)
		var cross := Line2D.new()
		cross.points = PackedVector2Array([Vector2(-_cell_px * 0.18, -_cell_px * 0.18), Vector2(_cell_px * 0.18, -_cell_px * 0.18)])
		cross.width = 5.0
		cross.default_color = gold
		node.add_child(cross)
	_set_entry(cell, entry)
	_show_banner(_translate_or("match3_variant_anchor", "ANCHOR!"), Color("#FFD866"))

## L'ancre descend d'une ligne par coup joué (échange avec la tuile dessous) ;
## rangée basse atteinte = livraison (cristaux + score) et despawn.
func _descend_anchor() -> void:
	var cell: Vector2i = _find_anchor_cell()
	if cell.x < 0:
		return
	if cell.y >= _grid_size - 1:
		_deliver_anchor(cell)
		return
	var below := Vector2i(cell.x, cell.y + 1)
	if _is_dead_cell(below):
		return # bloquée sur un trou (rare, assumé)
	var below_v: Variant = _entry_at(below)
	if not (below_v is Dictionary) or _is_wild(below_v as Dictionary):
		return
	_swap_entries(cell, below)
	var swap_sec: float = maxf(0.05, float(_get_conf("swap_tween_sec", 0.15)))
	_animate_entry_to(_entry_at(below), _cell_center(below), swap_sec)
	_animate_entry_to(_entry_at(cell), _cell_center(cell), swap_sec)
	if below.y >= _grid_size - 1:
		_deliver_anchor(below)

func _deliver_anchor(cell: Vector2i) -> void:
	var entry_v: Variant = _entry_at(cell)
	if not (entry_v is Dictionary):
		return
	var at_pos: Vector2 = _cell_center(cell)
	var node_v: Variant = (entry_v as Dictionary).get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_set_entry(cell, null)
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -50.0),
			_translate_or("match3_anchor", "ANCHOR DELIVERED!"), Color("#FFD866"), self)
	if _game and is_instance_valid(_game):
		var points: int = maxi(0, int(_get_conf("anchor_score", 300)))
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, at_pos)
		if _game.has_method("spawn_reward_crystal_at"):
			for i in range(maxi(1, int(_get_conf("anchor_crystals", 5)))):
				_game.call("spawn_reward_crystal_at",
					at_pos + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0)), {
						"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
					})

# --- Double joker (drone wildcard temporaire) ---

func _spawn_joker() -> void:
	var cells: Array = _plain_tile_cells()
	if cells.is_empty():
		return
	var cell: Vector2i = cells[randi() % cells.size()]
	var old: Dictionary = _entry_at(cell)
	var old_node_v: Variant = old.get("node", null)
	if old_node_v is Node2D and is_instance_valid(old_node_v):
		(old_node_v as Node2D).queue_free()
	var node := Node2D.new()
	node.name = "JokerDrone"
	node.position = _cell_center(cell)
	_grid_root.add_child(node)
	var entry: Dictionary = { "node": node, "sprite": null, "type": -1,
		"is_ship": false, "is_special": false, "special_effect": "", "is_joker": true }
	var asset_res: Resource = _load_cached_resource(str(_get_conf("joker_drone_asset", "")))
	if asset_res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = asset_res as Texture2D
		var tex_size: Vector2 = (asset_res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (_cell_px * 0.78 / maxf(tex_size.x, tex_size.y))
		node.add_child(sprite)
		entry["sprite"] = sprite
	else:
		# PH : triangle-drone cyan + halo (lisible comme 2e wildcard).
		var tri := Polygon2D.new()
		var half: float = _cell_px * 0.34
		tri.polygon = PackedVector2Array([
			Vector2(0.0, -half), Vector2(half * 0.9, half), Vector2(-half * 0.9, half)
		])
		tri.color = Color("#5CE8FF")
		node.add_child(tri)
		var halo := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * _cell_px * 0.44)
		halo.points = pts
		halo.closed = true
		halo.width = 3.0
		halo.default_color = Color("#5CE8FF88")
		halo.material = _add_material
		node.add_child(halo)
	_set_entry(cell, entry)
	_joker_cell = cell
	_joker_left = maxf(5.0, float(_get_conf("double_joker_duration_sec", 40.0)))
	_show_banner(_translate_or("match3_joker", "DOUBLE JOKER!"), Color("#5CE8FF"))

## Fin de fenêtre : le drone repart, une tuile fraîche prend sa place.
func _expire_joker() -> void:
	var cell: Vector2i = _joker_cell
	if cell.x < 0 or not (_entry_at(cell) is Dictionary) \
		or not bool((_entry_at(cell) as Dictionary).get("is_joker", false)):
		# Fallback : scan (le joker a pu bouger via gravité/swap non traqué).
		cell = Vector2i(-1, -1)
		for row in range(_grid_size):
			for col in range(_grid_size):
				var e_v: Variant = _entry_at(Vector2i(col, row))
				if e_v is Dictionary and bool((e_v as Dictionary).get("is_joker", false)):
					cell = Vector2i(col, row)
					break
			if cell.x >= 0:
				break
	if cell.x < 0:
		return
	var entry: Dictionary = _entry_at(cell)
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_set_entry(cell, _make_tile_entry(randi() % _tile_type_count, false, _cell_center(cell)))
	_joker_cell = Vector2i(-1, -1)

# --- OVERDRIVE (laser du vaisseau-joker sur la ligne visée) ---

func _fire_overdrive(row: int) -> void:
	_overdrive_armed = false
	var cells: Array = []
	for col in range(_grid_size):
		_append_sweepable(cells, Vector2i(col, row))
	var a := Vector2(_grid_origin.x, _cell_center(Vector2i(0, row)).y)
	var b := Vector2(_grid_origin.x + _pitch * float(_grid_size) - (_pitch - _cell_px), a.y)
	_play_line_effect(a, b, 0.0)
	if VFXManager:
		VFXManager.screen_shake(5.0, 0.2)
	_run_resolution(cells, 0, true)

# --- Bandeau + label de statut + locales ---

func _translate_or(key: String, fallback: String) -> String:
	if key != "" and typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

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
		_event_banner.position = Vector2(0.0, viewport_size.y * 0.34)
		add_child(_event_banner)
	_event_banner.text = text
	_event_banner.add_theme_color_override("font_color", color)
	_event_banner.visible = true
	_banner_time = 1.2

func _update_banner(delta: float) -> void:
	if _banner_time <= 0.0:
		return
	_banner_time -= delta
	if _event_banner and is_instance_valid(_event_banner):
		_event_banner.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 8.0))
		if _banner_time <= 0.0:
			_event_banner.visible = false

## Statut discret (priorité : objectif éclair > overdrive > cascade dorée).
func _update_status_label() -> void:
	var text: String = ""
	var color := Color.WHITE
	if _objective_left > 0 and _objective_time_left > 0.0:
		text = "%d — %ds" % [_objective_left, int(ceil(_objective_time_left))]
		color = _objective_tint()
	elif _overdrive_armed:
		text = _translate_or("match3_overdrive_hint", "TAP A ROW!")
		color = Color("#FF6BD8")
	elif _golden_window_left > 0.0:
		text = "x2 %ds" % int(ceil(_golden_window_left))
		color = Color("#FFD866")
	if text == "":
		if _status_label and is_instance_valid(_status_label):
			_status_label.visible = false
		return
	if _status_label == null or not is_instance_valid(_status_label):
		_status_label = Label.new()
		_status_label.name = "Match3StatusLabel"
		_status_label.add_theme_font_size_override("font_size", 22)
		_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_status_label.add_theme_constant_override("outline_size", 4)
		_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_label.z_as_relative = false
		_status_label.z_index = 60
		add_child(_status_label)
	var viewport_size: Vector2 = get_viewport_rect().size
	_status_label.visible = true
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.position = Vector2(16.0, viewport_size.y * 0.3)

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
		var new_line := Line2D.new()
		new_line.joint_mode = Line2D.LINE_JOINT_ROUND
		new_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		new_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		new_line.material = _add_material
		new_line.z_as_relative = false
		new_line.z_index = 55
		add_child(new_line)
		return new_line
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
		var new_circle := Polygon2D.new()
		var points := PackedVector2Array()
		for i in range(24):
			var angle: float = TAU * float(i) / 24.0
			points.append(Vector2(cos(angle), sin(angle)))
		new_circle.polygon = points
		new_circle.material = _add_material
		new_circle.z_as_relative = false
		new_circle.z_index = 54
		add_child(new_circle)
		return new_circle
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

## Timer de vague (départ du boss) : SOUS la barre de vie du boss (position
## réelle du BossHealthContainer du HUD, fallback countdown_y_ratio) — modèle suika.
func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 40.0)
	var label_y: float = viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9)
	if _hud and is_instance_valid(_hud):
		var container: Control = _hud.get_node_or_null("BossHealthContainer") as Control
		if container != null and container.visible:
			label_y = container.global_position.y + container.size.y + 4.0
	_countdown_label.position = Vector2(0.0, label_y)
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
