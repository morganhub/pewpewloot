extends Node2D

## BallLauncherManager — Orchestre une vague "ball_launcher" (Holedown /
## Brick Breaker Journey) : le vaisseau se verrouille en bas (Y fixe, X libre =
## point de tir) et lance des volees de balles vers une grille de blocs
## numerotes (numero = coups restants). Tour par tour : visee (geste unique,
## drag vers le haut arme la ligne predictive) -> volee -> descente d'un cran +
## nouvelle rangee en haut (generation infinie, HP croissants). Jetons "+1
## balle" dans les cases vides = armada permanente. Rangee qui franchit la
## ligne de danger = degats en % des HP max (shield d'abord), blocs detruits
## sans score. Pure vague score/cristaux, compte a rebours seul au HUD.
## Collisions balle/bloc en manuel (cercle vs AABB, normales de coin) comme le
## breakout — pas de physics engine.

signal finished

enum State { INTRO, AIM, VOLLEY, STEP, DONE }

const MOUSE_CAPTURE_ID: int = -2
const BRICK_SHADER: Shader = preload("res://scenes/mechanics/brick_rounded.gdshader")

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 60.0
var _elapsed: float = 0.0
var _turn: int = 0

# Grid geometry (computed once at setup).
var _grid_cols: int = 7
var _block_size: Vector2 = Vector2(96.0, 44.0)
var _block_spacing: float = 5.0
var _grid_side_margin: float = 26.0
var _grid_top_y: float = 0.0
var _descend_step: float = 49.0
var _danger_y: float = 0.0
var _brick_material: ShaderMaterial = null
var _grid_root: Node2D = null

# Blocks: { "node": Node2D, "label": Label, "rect": Rect2, "hp": int,
# "max_hp": int }. Tokens: { "node": Node2D, "rect": Rect2 }.
var _blocks: Array = []
var _tokens: Array = []

# Balls: { "node": Node2D, "pos": Vector2, "vel": Vector2 }.
var _balls: Array = []
var _ball_count: int = 3
var _ball_count_max: int = 30
var _ball_radius: float = 10.0
var _ball_speed: float = 950.0
var _ball_launch_interval: float = 0.06
var _balls_to_launch: int = 0
var _launch_timer: float = 0.0
var _launch_dir: Vector2 = Vector2.UP
var _volley_timer: float = 0.0
var _turn_time_max: float = 9.0
var _min_vy_ratio: float = 0.18
var _ball_textures: Array = []

# Aim gesture (single gesture: finger follows -> drag up past threshold arms).
var _touch_id: int = -1
var _gesture_start_world: Vector2 = Vector2.ZERO
var _aim_armed: bool = false
var _aim_point_world: Vector2 = Vector2.ZERO
var _aim_arm_threshold: float = 48.0
var _aim_min_angle_deg: float = 14.0
var _aim_line: Node2D = null
var _aim_line_points: PackedVector2Array = PackedVector2Array()

# Aim zone hint: a translucent framed band at the bottom third telling the
# player where to press to aim. Shown during AIM until the first press lands
# inside it; a press OUTSIDE the zone re-shows it as a reminder.
var _aim_zone_top_y: float = 0.0
var _aim_zone_panel: Panel = null
var _aim_hint_label: Label = null
var _aim_hint_dismissed: bool = false

# Rewards / damage.
var _damage_percent_row: float = 0.15
var _block_score_base: int = 10
var _block_score_per_hp: int = 4
var _block_crystal_chance: float = 0.1
var _reward_multiplier: float = 1.0

# Row generation.
var _row_fill_min: float = 0.45
var _row_fill_max: float = 0.75
var _row_hp_base: float = 2.0
var _row_hp_growth: float = 0.8
var _row_hp_max: int = 60
var _token_chance: float = 0.22
var _block_textures: Array = []
var _token_texture: Texture2D = null

var _danger_line: Line2D = null
var _danger_pulse_sec: float = 0.9
var _countdown_label: Label = null
var _ball_count_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("ball_launcher") if DataManager else {}

	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 60.0))))
	_grid_cols = clampi(int(_get_conf("grid_cols", 7)), 3, 12)
	_block_spacing = clampf(float(_get_conf("block_spacing_px", 5.0)), 0.0, 24.0)
	_grid_side_margin = maxf(4.0, float(_get_conf("grid_side_margin_px", 26.0)))
	_ball_count = clampi(int(_get_conf("ball_count_start", 3)), 1, 200)
	_ball_count_max = clampi(int(_get_conf("ball_count_max", 30)), _ball_count, 200)
	_ball_radius = maxf(4.0, float(_get_conf("ball_radius_px", 10.0)))
	_ball_speed = maxf(120.0, float(_get_conf("ball_speed_px_sec", 950.0)))
	_ball_launch_interval = maxf(0.01, float(_get_conf("ball_launch_interval_sec", 0.06)))
	_turn_time_max = maxf(2.0, float(_get_conf("turn_time_max_sec", 9.0)))
	_min_vy_ratio = clampf(float(_get_conf("ball_min_vy_ratio", 0.18)), 0.02, 0.9)
	_aim_arm_threshold = maxf(12.0, float(_get_conf("aim_arm_threshold_px", 48.0)))
	_aim_min_angle_deg = clampf(float(_get_conf("aim_min_angle_deg", 14.0)), 2.0, 45.0)
	_damage_percent_row = clampf(float(_get_conf("damage_percent_per_row_crossed", 0.15)), 0.0, 1.0)
	_block_score_base = maxi(0, int(_get_conf("block_score_base", 10)))
	_block_score_per_hp = maxi(0, int(_get_conf("block_score_per_hp", 4)))
	_block_crystal_chance = clampf(float(_get_conf("block_crystal_chance", 0.1)), 0.0, 1.0)
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_row_fill_min = clampf(float(_get_conf("row_fill_ratio_min", 0.45)), 0.1, 1.0)
	_row_fill_max = clampf(float(_get_conf("row_fill_ratio_max", 0.75)), _row_fill_min, 1.0)
	_row_hp_base = maxf(1.0, float(_get_conf("row_hp_base", 2)))
	_row_hp_growth = maxf(0.0, float(_get_conf("row_hp_growth_per_turn", 0.8)))
	_row_hp_max = maxi(1, int(_get_conf("row_hp_max", 60)))
	_token_chance = clampf(float(_get_conf("token_chance", 0.22)), 0.0, 1.0)
	_danger_pulse_sec = maxf(0.1, float(_get_conf("danger_line_pulse_sec", 0.9)))

	_prepare_assets()
	_compute_geometry()
	_begin_player_mode()
	_begin_hud_mode()
	_build_danger_line()
	_build_aim_line()
	_build_aim_zone_hint()
	_build_initial_grid()
	_ensure_countdown_label()
	_ensure_ball_count_label()

	_elapsed = 0.0
	_turn = 0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.6)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — grille, tour et compte de balles préservés. Les
## nouvelles valeurs s'appliquent aux prochaines rangées spawnnées.
func update_free_mode_config(cfg: Dictionary) -> void:
	_row_hp_base = maxf(1.0, float(cfg.get("row_hp_base", _row_hp_base)))
	_row_hp_growth = maxf(0.0, float(cfg.get("row_hp_growth_per_turn", _row_hp_growth)))
	_row_fill_max = clampf(float(cfg.get("row_fill_ratio_max", _row_fill_max)), _row_fill_min, 1.0)
	_turn_time_max = maxf(2.0, float(cfg.get("turn_time_max_sec", _turn_time_max)))
	_damage_percent_row = clampf(float(cfg.get("damage_percent_per_row_crossed", _damage_percent_row)), 0.0, 1.0)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_ball_launcher"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_ball_launcher", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_ball_launcher"):
		_player.call("end_ball_launcher")

## The aim drag covers the whole screen: power buttons would swallow touches
## and are useless here (no shooting); the joystick circles are noise.
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

func _prepare_assets() -> void:
	_block_textures.clear()
	var block_assets_v: Variant = _config.get("block_assets", _cfg.get("block_assets", []))
	if block_assets_v is Array:
		for asset_v in (block_assets_v as Array):
			var tex: Texture2D = _texture_from_path(str(asset_v))
			if tex != null:
				_block_textures.append(tex)
	_token_texture = null
	var token_assets_v: Variant = _config.get("token_assets", _cfg.get("token_assets", []))
	if token_assets_v is Array:
		for token_v in (token_assets_v as Array):
			_token_texture = _texture_from_path(str(token_v))
			if _token_texture != null:
				break
	_ball_textures.clear()
	var ball_tex: Texture2D = _texture_from_path(str(_config.get("ball_asset", _cfg.get("ball_asset", ""))))
	if ball_tex != null:
		_ball_textures.append(ball_tex)

func _texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		return res as Texture2D
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			return frames.get_frame_texture(names[0], 0)
	return null

# =============================================================================
# GRID
# =============================================================================

func _compute_geometry() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable_w: float = viewport_size.x - _grid_side_margin * 2.0
	var block_w: float = maxf(16.0, (usable_w - float(_grid_cols - 1) * _block_spacing) / float(_grid_cols))
	var block_h: float = maxf(12.0, float(_get_conf("block_height_px", 44.0)))
	_block_size = Vector2(block_w, block_h)
	_descend_step = block_h + _block_spacing
	_grid_top_y = viewport_size.y * clampf(float(_get_conf("grid_top_ratio", 0.06)), 0.02, 0.4)
	_danger_y = viewport_size.y * clampf(float(_get_conf("danger_line_ratio", 0.76)), 0.4, 0.92)
	_aim_zone_top_y = viewport_size.y * clampf(float(_get_conf("aim_zone_top_ratio", 0.66)), 0.3, 0.95)

	# One shared shader material for every block (single batch, like breakout).
	_brick_material = ShaderMaterial.new()
	_brick_material.shader = BRICK_SHADER
	_brick_material.set_shader_parameter("rect_size", _block_size)
	_brick_material.set_shader_parameter("radius_px", clampf(float(_get_conf("block_corner_radius_px", 7.0)), 0.0, minf(block_w, block_h) * 0.5))

	_grid_root = Node2D.new()
	_grid_root.name = "BlockGrid"
	_grid_root.z_as_relative = false
	_grid_root.z_index = 10
	add_child(_grid_root)

## Initial wall: `initial_rows` rows stacked from the top, weakest at the
## bottom (HP grows with the virtual turn index, like the live generation).
func _build_initial_grid() -> void:
	var initial_rows: int = clampi(int(_get_conf("initial_rows", 3)), 1, 8)
	for i in range(initial_rows):
		# Oldest row (highest virtual turn) sits the lowest, like in real play.
		var row_y: float = _grid_top_y + float(i) * _descend_step
		_spawn_row(row_y, initial_rows - 1 - i)

func _row_hp_for_turn(turn: int) -> int:
	return clampi(int(round(_row_hp_base + float(turn) * _row_hp_growth)), 1, _row_hp_max)

func _cell_center_x(col: int) -> float:
	return _grid_side_margin + (_block_size.x + _block_spacing) * float(col) + _block_size.x * 0.5

## Spawns one row at `row_y` (top edge of the row). Guarantees at least one
## block and at least one hole; empty cells can host "+1 ball" tokens (max 2).
func _spawn_row(row_y: float, hp_turn: int) -> void:
	var fill_ratio: float = randf_range(_row_fill_min, _row_fill_max)
	var hp: int = _row_hp_for_turn(hp_turn)
	var filled: Array = []
	for c in range(_grid_cols):
		filled.append(randf() <= fill_ratio)
	# At least one block, at least one hole (a full wall would be unfair).
	var block_count: int = 0
	for c in range(_grid_cols):
		if filled[c]:
			block_count += 1
	if block_count == 0:
		filled[randi() % _grid_cols] = true
		block_count = 1
	if block_count == _grid_cols:
		filled[randi() % _grid_cols] = false
		block_count -= 1

	var tokens_in_row: int = 0
	for c in range(_grid_cols):
		var center := Vector2(_cell_center_x(c), row_y + _block_size.y * 0.5)
		if filled[c]:
			_spawn_block(center, hp)
		elif tokens_in_row < 2 and randf() <= _token_chance:
			_spawn_token(center)
			tokens_in_row += 1

func _spawn_block(center: Vector2, hp: int) -> void:
	var block_node := Node2D.new()
	block_node.position = center
	var tex: Texture2D = null
	if not _block_textures.is_empty():
		tex = _block_textures[randi() % _block_textures.size()]
	block_node.add_child(_make_block_visual(tex))
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(8, int(_get_conf("number_font_size", 20))))
	label.add_theme_color_override("font_color", Color(str(_get_conf("number_color", "#FFFFFF"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = _block_size
	label.position = -_block_size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_node.add_child(label)
	_grid_root.add_child(block_node)
	var entry: Dictionary = {
		"node": block_node,
		"label": label,
		"rect": Rect2(center - _block_size * 0.5, _block_size),
		"hp": hp,
		"max_hp": hp
	}
	_blocks.append(entry)
	_refresh_block_visual(entry)

## "Cover" fill like the breakout bricks: centered crop to the block aspect
## ratio then exact scale — never stretched; shared shader rounds the corners.
func _make_block_visual(tex: Texture2D) -> Node2D:
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var block_aspect: float = _block_size.x / _block_size.y
			var tex_aspect: float = tex_size.x / tex_size.y
			var region_size: Vector2
			if tex_aspect > block_aspect:
				region_size = Vector2(tex_size.y * block_aspect, tex_size.y)
			else:
				region_size = Vector2(tex_size.x, tex_size.x / block_aspect)
			sprite.region_enabled = true
			sprite.region_rect = Rect2((tex_size - region_size) * 0.5, region_size)
			sprite.scale = _block_size / region_size
		sprite.material = _brick_material
		return sprite
	var poly := Polygon2D.new()
	var half: Vector2 = _block_size * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	poly.color = Color("#8A93A6")
	return poly

func _refresh_block_visual(block: Dictionary) -> void:
	var node_v: Variant = block.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var hp: int = int(block.get("hp", 1))
	var max_hp: int = maxi(1, int(block.get("max_hp", 1)))
	# Damaged blocks darken progressively; the counter is the true readout.
	var darken_max: float = clampf(float(_get_conf("block_darken_max", 0.45)), 0.0, 0.9)
	var brightness: float = lerpf(1.0 - darken_max, 1.0, float(hp) / float(max_hp))
	(node_v as Node2D).modulate = Color(brightness, brightness, brightness, 1.0)
	var label_v: Variant = block.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).text = str(hp)

func _spawn_token(center: Vector2) -> void:
	var token_node := Node2D.new()
	token_node.position = center
	var token_size: float = _block_size.y * 0.62
	if _token_texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = _token_texture
		var tex_size: Vector2 = _token_texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * token_size) / maxf(tex_size.x, tex_size.y)
		sprite.modulate = Color(str(_get_conf("token_tint", "#FFD966")))
		token_node.add_child(sprite)
	var label := Label.new()
	label.text = "+1"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(8, int(int(_get_conf("number_font_size", 20)) * 0.8)))
	label.add_theme_color_override("font_color", Color(str(_get_conf("token_tint", "#FFD966"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = _block_size
	label.position = Vector2(-_block_size.x * 0.5, -_block_size.y * 0.5 - token_size * 0.55)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token_node.add_child(label)
	_grid_root.add_child(token_node)
	_tokens.append({
		"node": token_node,
		"rect": Rect2(center - Vector2.ONE * token_size * 0.5, Vector2.ONE * token_size)
	})

# =============================================================================
# DANGER LINE / AIM LINE
# =============================================================================

func _build_danger_line() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_danger_line = Line2D.new()
	_danger_line.name = "DangerLine"
	_danger_line.points = PackedVector2Array([
		Vector2(_grid_side_margin * 0.5, _danger_y),
		Vector2(viewport_size.x - _grid_side_margin * 0.5, _danger_y)
	])
	_danger_line.width = 3.0
	_danger_line.default_color = Color(str(_get_conf("danger_line_color", "#FF5A5AC8")))
	_danger_line.z_as_relative = false
	_danger_line.z_index = 9
	add_child(_danger_line)

func _build_aim_line() -> void:
	_aim_line = Node2D.new()
	_aim_line.name = "AimLine"
	_aim_line.z_as_relative = false
	_aim_line.z_index = 12
	_aim_line.draw.connect(_draw_aim_line)
	_aim_line.visible = false
	add_child(_aim_line)

## Translucent framed band covering the bottom third + a centered localized
## label. mouse_filter IGNORE so it never eats the raw touches read in _input.
func _build_aim_zone_hint() -> void:
	_aim_zone_panel = Panel.new()
	_aim_zone_panel.name = "AimZoneHint"
	_aim_zone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_zone_panel.z_as_relative = false
	_aim_zone_panel.z_index = 58
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(_get_conf("aim_zone_bg_color", "#8FD3FF20")))
	sb.border_color = Color(str(_get_conf("aim_zone_border_color", "#8FD3FFC0")))
	var bw: int = int(maxf(0.0, float(_get_conf("aim_zone_border_width_px", 3.0))))
	sb.border_width_left = bw
	sb.border_width_top = bw
	sb.border_width_right = bw
	sb.border_width_bottom = bw
	var cr: int = int(maxf(0.0, float(_get_conf("aim_zone_corner_radius_px", 18.0))))
	sb.corner_radius_top_left = cr
	sb.corner_radius_top_right = cr
	sb.corner_radius_bottom_left = cr
	sb.corner_radius_bottom_right = cr
	_aim_zone_panel.add_theme_stylebox_override("panel", sb)
	add_child(_aim_zone_panel)

	_aim_hint_label = Label.new()
	_aim_hint_label.name = "AimHintLabel"
	_aim_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aim_hint_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("aim_hint_font_size", 30))))
	_aim_hint_label.add_theme_color_override("font_color", Color(str(_get_conf("aim_hint_color", "#FFFFFF"))))
	_aim_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aim_hint_label.add_theme_constant_override("outline_size", 6)
	_aim_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_hint_label.z_as_relative = false
	_aim_hint_label.z_index = 59
	_aim_hint_label.text = _resolve_aim_hint_text()
	add_child(_aim_hint_label)

	_layout_aim_zone_hint()
	_set_aim_hint_shown(false)

func _resolve_aim_hint_text() -> String:
	var fallback: String = "Appuie ici pour viser !"
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate("ball_launcher_aim_hint")
		if translated != "" and translated != "ball_launcher_aim_hint":
			return translated
	return fallback

func _layout_aim_zone_hint() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.position = Vector2(0.0, _aim_zone_top_y)
		_aim_zone_panel.size = Vector2(viewport_size.x, maxf(1.0, viewport_size.y - _aim_zone_top_y))
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.size = Vector2(viewport_size.x, 54.0)
		# Sits near the top of the zone so it never overlaps the ship at the bottom.
		_aim_hint_label.position = Vector2(0.0, _aim_zone_top_y + 22.0)

func _set_aim_hint_shown(shown: bool) -> void:
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.visible = shown
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.visible = shown

## Shown only while aiming and not yet dismissed; gentle alpha pulse to draw
## the eye without stealing focus from the grid.
func _update_aim_zone_hint() -> void:
	var shown: bool = (_state == State.AIM) and not _aim_hint_dismissed
	_set_aim_hint_shown(shown)
	if not shown:
		return
	_layout_aim_zone_hint()
	var pulse_sec: float = maxf(0.1, float(_get_conf("aim_hint_pulse_sec", 1.2)))
	var a: float = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(TAU * _elapsed / pulse_sec))
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.modulate.a = a
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.modulate.a = a

## True when a screen press falls inside the bottom aim band (world space,
## same axis as _danger_y so it lines up with the ship's launch area).
func _is_in_aim_zone(screen_pos: Vector2) -> bool:
	return _to_world(screen_pos).y >= _aim_zone_top_y

func _draw_aim_line() -> void:
	if _aim_line_points.size() < 2:
		return
	var color := Color(str(_get_conf("aim_line_color", "#FFFFFF96")))
	var width: float = maxf(1.0, float(_get_conf("aim_line_width_px", 3.0)))
	var dash: float = maxf(4.0, float(_get_conf("aim_line_dash_px", 14.0)))
	for i in range(_aim_line_points.size() - 1):
		_aim_line.draw_dashed_line(_aim_line_points[i], _aim_line_points[i + 1], color, width, dash)

## Predictive trajectory: wall reflections only (blocks are ignored — part of
## the skill is reading the wall bounces, like the source games).
func _update_aim_line() -> void:
	if _aim_line == null or not is_instance_valid(_aim_line):
		return
	if not _aim_armed or _player == null or not is_instance_valid(_player):
		_aim_line.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var origin: Vector2 = _launch_origin()
	var dir: Vector2 = _resolve_aim_dir(origin)
	var max_bounces: int = clampi(int(_get_conf("aim_line_max_bounces", 2)), 0, 6)
	var left_x: float = _ball_radius
	var right_x: float = viewport_size.x - _ball_radius
	var top_y: float = _ball_radius
	var total_budget: float = viewport_size.y * 1.5
	var points := PackedVector2Array([origin])
	var pos: Vector2 = origin
	for _bounce in range(max_bounces + 1):
		if total_budget <= 0.0:
			break
		# Distance to each wall along dir.
		var t_best: float = total_budget
		var hit_axis: int = -1 # 0 = vertical wall, 1 = top
		if dir.x < -0.0001:
			var t: float = (left_x - pos.x) / dir.x
			if t > 0.0 and t < t_best:
				t_best = t
				hit_axis = 0
		elif dir.x > 0.0001:
			var t2: float = (right_x - pos.x) / dir.x
			if t2 > 0.0 and t2 < t_best:
				t_best = t2
				hit_axis = 0
		if dir.y < -0.0001:
			var t3: float = (top_y - pos.y) / dir.y
			if t3 > 0.0 and t3 < t_best:
				t_best = t3
				hit_axis = 1
		pos += dir * t_best
		total_budget -= t_best
		points.append(pos)
		if hit_axis == 0:
			dir.x = -dir.x
		elif hit_axis == 1:
			dir.y = -dir.y
		else:
			break
	_aim_line_points = points
	_aim_line.visible = true
	_aim_line.queue_redraw()

func _launch_origin() -> Vector2:
	if _player and is_instance_valid(_player):
		return _player.global_position + Vector2(0.0, -_ball_radius * 2.5)
	return Vector2.ZERO

## Aim direction = ship -> finger, clamped to at least `aim_min_angle_deg`
## above the horizontal (no flat shots that would ping-pong forever).
func _resolve_aim_dir(origin: Vector2) -> Vector2:
	var raw: Vector2 = _aim_point_world - origin
	if raw.length_squared() < 1.0:
		return Vector2.UP
	# Angle from straight up: 0 = up, +/-PI/2 = horizontal.
	var ang: float = atan2(raw.x, -raw.y)
	var max_ang: float = PI * 0.5 - deg_to_rad(_aim_min_angle_deg)
	if raw.y >= 0.0:
		# Finger below the ship: clamp to the nearest side limit.
		ang = max_ang * (1.0 if raw.x >= 0.0 else -1.0)
	else:
		ang = clampf(ang, -max_ang, max_ang)
	return Vector2(sin(ang), -cos(ang))

# =============================================================================
# INPUT (single gesture: follow X -> drag up past threshold arms the aim ->
# release fires; dropping back below the threshold cancels. Same raw-touch
# reading + mouse cross-guards as SliceRushManager/lane_runner.)
# =============================================================================

func _input(event: InputEvent) -> void:
	# Releases are ALWAYS processed (even outside AIM/VOLLEY): a finger lifted
	# during STEP/INTRO must free the capture or every next press is ignored.
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch.pressed:
			if touch.index == _touch_id:
				_gesture_end()
			return
		if (_state == State.AIM or _state == State.VOLLEY) and _touch_id == -1:
			_try_begin_gesture(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id and (_state == State.AIM or _state == State.VOLLEY):
			_gesture_feed(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mouse_btn.pressed:
			if _touch_id == MOUSE_CAPTURE_ID:
				_gesture_end()
			return
		if (_state == State.AIM or _state == State.VOLLEY) and _touch_id == -1:
			_try_begin_gesture(MOUSE_CAPTURE_ID, mouse_btn.position)
	elif event is InputEventMouseMotion and _touch_id == MOUSE_CAPTURE_ID:
		if _state == State.AIM or _state == State.VOLLEY:
			_gesture_feed((event as InputEventMouseMotion).position)

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

## Aiming only starts inside the bottom band. A press outside is ignored for
## aiming and re-shows the hint; a press inside dismisses it and captures.
func _try_begin_gesture(capture_id: int, screen_pos: Vector2) -> void:
	if not _is_in_aim_zone(screen_pos):
		_aim_hint_dismissed = false
		return
	_aim_hint_dismissed = true
	_gesture_begin(capture_id, screen_pos)

func _gesture_begin(capture_id: int, screen_pos: Vector2) -> void:
	_touch_id = capture_id
	_gesture_start_world = _to_world(screen_pos)
	_aim_armed = false
	_set_ship_target_x(_gesture_start_world.x)

func _gesture_feed(screen_pos: Vector2) -> void:
	var world: Vector2 = _to_world(screen_pos)
	if _state != State.AIM:
		# During the volley the finger only repositions the launch ship.
		_set_ship_target_x(world.x)
		return
	var rise: float = _gesture_start_world.y - world.y
	if _aim_armed:
		if rise < _aim_arm_threshold:
			# Dropped back below the threshold: cancel, resume the X follow.
			_aim_armed = false
			_update_aim_line()
			return
		_aim_point_world = world
	else:
		if rise >= _aim_arm_threshold:
			# Armed: the ship X freezes, the finger now steers the angle.
			_aim_armed = true
			_aim_point_world = world
		else:
			_set_ship_target_x(world.x)

func _gesture_end() -> void:
	_touch_id = -1
	if _state == State.AIM and _aim_armed:
		_aim_armed = false
		_fire_volley()
	_update_aim_line()

func _set_ship_target_x(x: float) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_ball_launcher_x"):
		_player.call("set_ball_launcher_x", x)

# =============================================================================
# VOLLEY
# =============================================================================

func _fire_volley() -> void:
	_launch_dir = _resolve_aim_dir(_launch_origin())
	_balls_to_launch = _ball_count
	_launch_timer = 0.0
	_volley_timer = 0.0
	_turn += 1
	_state = State.VOLLEY
	if _aim_line and is_instance_valid(_aim_line):
		_aim_line.visible = false

func _spawn_ball_node() -> Node2D:
	var ball := Node2D.new()
	ball.z_as_relative = false
	ball.z_index = 11
	if not _ball_textures.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = _ball_textures[0]
		var tex_size: Vector2 = (_ball_textures[0] as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * _ball_radius * 2.0) / tex_size
		ball.add_child(sprite)
	else:
		var circle := Polygon2D.new()
		var points := PackedVector2Array()
		var segments: int = 16
		for i in range(segments):
			var a: float = TAU * float(i) / float(segments)
			points.append(Vector2(cos(a), sin(a)) * _ball_radius)
		circle.polygon = points
		circle.color = Color(str(_get_conf("ball_color", "#8FD3FF")))
		ball.add_child(circle)
	add_child(ball)
	return ball

func _update_volley(delta: float) -> void:
	_volley_timer += delta
	# Staggered launches from the ship's current position.
	if _balls_to_launch > 0:
		_launch_timer -= delta
		if _launch_timer <= 0.0:
			_launch_timer = _ball_launch_interval
			_balls_to_launch -= 1
			var node: Node2D = _spawn_ball_node()
			var origin: Vector2 = _launch_origin()
			node.global_position = origin
			_balls.append({"node": node, "pos": origin, "vel": _launch_dir * _ball_speed})

	# Anti-tunneling: cap each integration step so a ball can never cross a
	# block in one move (fast balls -> several substeps per frame).
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_step: float = maxf(0.002, (_ball_radius * 0.9) / _ball_speed)
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.0:
		var step: float = minf(remaining, max_step)
		remaining -= step
		for i in range(_balls.size() - 1, -1, -1):
			if not _step_ball(_balls[i], step, viewport_size):
				var node_v: Variant = (_balls[i] as Dictionary).get("node", null)
				if node_v is Node2D and is_instance_valid(node_v):
					(node_v as Node2D).queue_free()
				_balls.remove_at(i)

	# Turn ends when every ball has exited (or on the anti-stall recall).
	if _balls_to_launch <= 0 and _balls.is_empty():
		_begin_step()
	elif _volley_timer >= _turn_time_max:
		_recall_balls()
		_begin_step()

## Moves one ball one substep. Returns false when the ball exits at the bottom.
func _step_ball(ball: Dictionary, step: float, viewport_size: Vector2) -> bool:
	var pos: Vector2 = ball.get("pos", Vector2.ZERO)
	var vel: Vector2 = ball.get("vel", Vector2.UP * _ball_speed)
	pos += vel * step

	var left_x: float = _ball_radius
	var right_x: float = viewport_size.x - _ball_radius
	var top_y: float = _ball_radius
	var bounced: bool = false
	if pos.x <= left_x and vel.x < 0.0:
		pos.x = left_x
		vel.x = -vel.x
		bounced = true
	elif pos.x >= right_x and vel.x > 0.0:
		pos.x = right_x
		vel.x = -vel.x
		bounced = true
	if pos.y <= top_y and vel.y < 0.0:
		pos.y = top_y
		vel.y = -vel.y
		bounced = true

	# Blocks: circle vs AABB with corner normals; one block per substep.
	var radius_sq: float = _ball_radius * _ball_radius
	for i in range(_blocks.size() - 1, -1, -1):
		var block: Dictionary = _blocks[i]
		var rect: Rect2 = block.get("rect", Rect2())
		var closest := Vector2(
			clampf(pos.x, rect.position.x, rect.end.x),
			clampf(pos.y, rect.position.y, rect.end.y)
		)
		var delta_v: Vector2 = pos - closest
		var dist_sq: float = delta_v.length_squared()
		if dist_sq > radius_sq:
			continue
		var normal: Vector2
		if dist_sq > 0.0001:
			normal = delta_v.normalized()
		else:
			var center_delta: Vector2 = pos - rect.get_center()
			if absf(center_delta.x) / maxf(1.0, rect.size.x) > absf(center_delta.y) / maxf(1.0, rect.size.y):
				normal = Vector2(signf(center_delta.x), 0.0)
			else:
				normal = Vector2(0.0, signf(center_delta.y))
		if vel.dot(normal) < 0.0:
			vel = vel.bounce(normal)
		pos = closest + normal * (_ball_radius + 0.5)
		bounced = true
		_damage_block(i)
		break

	# "+1 ball" tokens: collected on contact, no bounce.
	for i in range(_tokens.size() - 1, -1, -1):
		var token: Dictionary = _tokens[i]
		var t_rect: Rect2 = token.get("rect", Rect2())
		if t_rect.grow(_ball_radius * 0.5).has_point(pos):
			_collect_token(i)

	# Anti-loop: never let the trajectory go quasi-horizontal forever.
	if bounced:
		var min_vy: float = _ball_speed * _min_vy_ratio
		if absf(vel.y) < min_vy:
			var sign_y: float = -1.0 if vel.y <= 0.0 else 1.0
			vel.y = sign_y * min_vy
			var target_vx: float = sqrt(maxf(0.0, _ball_speed * _ball_speed - min_vy * min_vy))
			vel.x = target_vx * (1.0 if vel.x >= 0.0 else -1.0)
		vel = vel.normalized() * _ball_speed

	ball["pos"] = pos
	ball["vel"] = vel
	var node_v: Variant = ball.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).global_position = pos
	# Ball exits below the screen: collected for the next volley.
	return pos.y - _ball_radius <= viewport_size.y

## Anti-stall recall: remaining balls fade out on the spot.
func _recall_balls() -> void:
	var fade_sec: float = maxf(0.05, float(_get_conf("recall_fade_sec", 0.25)))
	for ball_v in _balls:
		var node_v: Variant = (ball_v as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			var tween: Tween = create_tween()
			tween.tween_property(node, "modulate:a", 0.0, fade_sec)
			tween.tween_callback(node.queue_free)
	_balls.clear()
	_balls_to_launch = 0

func _damage_block(index: int) -> void:
	var block: Dictionary = _blocks[index]
	block["hp"] = int(block.get("hp", 1)) - 1
	var node_v: Variant = block.get("node", null)
	if int(block["hp"]) <= 0:
		var rect: Rect2 = block.get("rect", Rect2())
		var max_hp: int = maxi(1, int(block.get("max_hp", 1)))
		_blocks.remove_at(index)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
		_award_block_rewards(rect.get_center(), max_hp)
		return
	_refresh_block_visual(block)
	if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
		VFXManager.flash_sprite(node_v, Color(1.6, 1.6, 1.6), maxf(0.02, float(_get_conf("block_hp_flash_sec", 0.1))))

func _award_block_rewards(at_pos: Vector2, max_hp: int) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var points: int = int(round(float(_block_score_base + max_hp * _block_score_per_hp) * _reward_multiplier))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)
	if randf() <= _block_crystal_chance and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", at_pos)

func _collect_token(index: int) -> void:
	var token: Dictionary = _tokens[index]
	_tokens.remove_at(index)
	var node_v: Variant = token.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var node: Node2D = node_v as Node2D
		var tween: Tween = create_tween()
		tween.tween_property(node, "scale", Vector2.ONE * 1.6, 0.12)
		tween.parallel().tween_property(node, "modulate:a", 0.0, 0.12)
		tween.tween_callback(node.queue_free)
	_ball_count = mini(_ball_count + 1, _ball_count_max)
	_refresh_ball_count_label()

# =============================================================================
# GRID STEP (descend + new row + danger line check)
# =============================================================================

func _begin_step() -> void:
	_state = State.STEP
	_state_timer = 0.25
	# Logical rects move instantly (no collisions during STEP), visuals tween.
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		var rect: Rect2 = block.get("rect", Rect2())
		rect.position.y += _descend_step
		block["rect"] = rect
		var node_v: Variant = block.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			var tween: Tween = create_tween()
			tween.tween_property(node, "position:y", node.position.y + _descend_step, 0.2) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for token_v in _tokens:
		var token: Dictionary = token_v as Dictionary
		var t_rect: Rect2 = token.get("rect", Rect2())
		t_rect.position.y += _descend_step
		token["rect"] = t_rect
		var t_node_v: Variant = token.get("node", null)
		if t_node_v is Node2D and is_instance_valid(t_node_v):
			var t_node: Node2D = t_node_v as Node2D
			var t_tween: Tween = create_tween()
			t_tween.tween_property(t_node, "position:y", t_node.position.y + _descend_step, 0.2) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_spawn_row(_grid_top_y, _turn)
	_apply_danger_line_crossings()

## Rows past the danger line: % max HP damage each (shield first), blocks and
## tokens destroyed without any reward. Never an instant game over.
func _apply_danger_line_crossings() -> void:
	var crossed_rows: Dictionary = {}
	for i in range(_blocks.size() - 1, -1, -1):
		var block: Dictionary = _blocks[i]
		var rect: Rect2 = block.get("rect", Rect2())
		if rect.end.y >= _danger_y:
			crossed_rows[int(round(rect.position.y))] = true
			var node_v: Variant = block.get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_blocks.remove_at(i)
	for i in range(_tokens.size() - 1, -1, -1):
		var t_rect: Rect2 = (_tokens[i] as Dictionary).get("rect", Rect2())
		if t_rect.end.y >= _danger_y:
			var t_node_v: Variant = (_tokens[i] as Dictionary).get("node", null)
			if t_node_v is Node2D and is_instance_valid(t_node_v):
				(t_node_v as Node2D).queue_free()
			_tokens.remove_at(i)
	var rows_crossed: int = crossed_rows.size()
	if rows_crossed <= 0:
		return
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent_row))) * rows_crossed
		_player.call("take_damage", dmg)
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(8, 0.3)

# =============================================================================
# MAIN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# A dead player means the game-over flow took over: freeze the wave
	# without emitting finished.
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	_update_danger_pulse()
	_update_ball_count_label_pos()
	_update_aim_zone_hint()
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.AIM
				_refresh_ball_count_label()
		State.AIM:
			_handle_keyboard_aim(delta)
			if _aim_armed:
				_update_aim_line()
		State.VOLLEY:
			_update_volley(delta)
		State.STEP:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.AIM
	if _elapsed >= _duration:
		_finish()

## Desktop comfort: arrows reposition the ship between volleys.
func _handle_keyboard_aim(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var move: float = 0.0
	if Input.is_action_pressed("ui_left"):
		move -= 1.0
	if Input.is_action_pressed("ui_right"):
		move += 1.0
	if move != 0.0 and _touch_id == -1:
		_set_ship_target_x(_player.global_position.x + move * 620.0 * delta)

func _update_danger_pulse() -> void:
	if _danger_line == null or not is_instance_valid(_danger_line):
		return
	var base_a: float = Color(str(_get_conf("danger_line_color", "#FF5A5AC8"))).a
	_danger_line.modulate.a = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(TAU * _elapsed / _danger_pulse_sec)) * base_a

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "BallLauncherCountdownLabel"
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

## Small "xN" armada counter following the ship.
func _ensure_ball_count_label() -> void:
	if _ball_count_label and is_instance_valid(_ball_count_label):
		return
	_ball_count_label = Label.new()
	_ball_count_label.name = "BallCountLabel"
	_ball_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ball_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ball_count_label.add_theme_font_size_override("font_size", maxi(8, int(_get_conf("number_font_size", 20))))
	_ball_count_label.add_theme_color_override("font_color", Color(str(_get_conf("ball_color", "#8FD3FF"))))
	_ball_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_ball_count_label.add_theme_constant_override("outline_size", 4)
	_ball_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball_count_label.z_as_relative = false
	_ball_count_label.z_index = 60
	_ball_count_label.size = Vector2(120.0, 24.0)
	add_child(_ball_count_label)
	_refresh_ball_count_label()

func _refresh_ball_count_label() -> void:
	if _ball_count_label and is_instance_valid(_ball_count_label):
		_ball_count_label.text = "×" + str(_ball_count)

func _update_ball_count_label_pos() -> void:
	if _ball_count_label == null or not is_instance_valid(_ball_count_label) \
		or _player == null or not is_instance_valid(_player):
		return
	_ball_count_label.position = _player.global_position + Vector2(-60.0, 30.0)

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	_recall_balls()
	# Restore the player and the HUD BEFORE notifying the wave chain.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # grid, balls, lines and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
