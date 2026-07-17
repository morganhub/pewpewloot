extends Control
## Header bar for menus: XP progress, protocols count, crystals.
## Reads config from game.json "menu_header". Builds UI in _ready().
## Emits crystals_pressed when the crystals block is clicked (navigate to shop).

signal crystals_pressed

const DEBUG_HEADER_LAYOUT := false
const DEBUG_RECT_HEIGHT := false  # Affiche hauteurs rectangle XP / protocols pour debug

var _cfg: Dictionary = {}
var _last_debug_vp: float = -1.0
var _last_debug_header: float = -1.0
var _last_debug_crystals_right: float = -1.0
var _debug_timer: float = 0.0
var _rect_style: StyleBoxFlat = null
var _rect_style_no_border: StyleBoxFlat = null
var _xp_bar_track_style: StyleBoxFlat = null
var _xp_bar_fill_style: StyleBoxFlat = null
var _xp_bar_border_width: int = 0
var _xp_track_content: Control = null

# Nodes created at runtime
var _level_icon: TextureRect
var _level_label: Label
var _level_rect_wrapper: Control  # wrapper hauteur fixe pour rectangle XP
var _level_panel: PanelContainer  # panel barre XP (pour clic afficher chiffres)
var _protocols_rect_wrapper: Control  # wrapper hauteur fixe pour rectangle protocols
var _xp_track_panel: PanelContainer
var _xp_fill_panel: PanelContainer
var _xp_label: Label
var _xp_label_wrapper: MarginContainer
var _protocols_icon: TextureRect
var _protocols_label: Label
var _crystals_panel: Button
var _crystal_icon: TextureRect
var _crystal_label: Label

func _ready() -> void:
	_cfg = _get_config()
	if _cfg.is_empty():
		return
	_build_styles()
	_build_ui()

func _get_config() -> Dictionary:
	if DataManager == null:
		return {}
	var game: Dictionary = DataManager.get_game_config()
	var h: Variant = game.get("menu_header", {})
	return h if h is Dictionary else {}

func _normalize_screen_key(raw_name: String) -> String:
	var s: String = raw_name.strip_edges().to_lower()
	if s.is_empty():
		return ""
	# Supporte variantes avec/sans underscore.
	if s == "homescreen" or s == "home_screen":
		return "homescreen"
	if s == "shipmenu" or s == "ship_menu":
		return "shipmenu"
	if s == "worldselect" or s == "world_select":
		return "world_select"
	if s == "levelselect" or s == "level_select":
		return "level_select"
	if s == "skillsmenu" or s == "skills_menu":
		return "skillsmenu"
	if s == "optionsmenu" or s == "options_menu":
		return "optionsmenu"
	if s == "shopmenu" or s == "shop_menu":
		return "shopmenu"
	if s == "profileselect" or s == "profile_select":
		return "profileselect"
	if s == "pausemenu" or s == "pause_menu":
		return "pausemenu"
	if s == "lootresultscreen" or s == "loot_result_screen":
		return "lootresultscreen"
	return s

func _get_header_screen_key() -> String:
	# 1) Priorité au parent direct du MenuHeader (le plus fiable dans ce projet).
	var parent_node: Node = get_parent()
	if parent_node != null:
		if parent_node is Node and (parent_node as Node).scene_file_path != "":
			var parent_scene_key := _normalize_screen_key((parent_node as Node).scene_file_path.get_file().get_basename())
			if not parent_scene_key.is_empty():
				return parent_scene_key
		var parent_name_key := _normalize_screen_key(str(parent_node.name))
		if not parent_name_key.is_empty():
			return parent_name_key

	# 2) Fallback sur current_scene.
	var scene = get_tree().current_scene
	if scene != null:
		var by_path := _normalize_screen_key(scene.scene_file_path.get_file().get_basename())
		if not by_path.is_empty():
			return by_path
		var by_name := _normalize_screen_key(str(scene.name))
		if not by_name.is_empty():
			return by_name
	return ""

func _get_header_background_color_hex() -> String:
	var key: String = _get_header_screen_key()
	if key.is_empty():
		return str(_cfg.get("default_background_color", "")).strip_edges()
	var color_key := key + "_background_color"
	# Si la clé écran existe, sa valeur est prioritaire (même vide => transparent)
	if _cfg.has(color_key):
		return str(_cfg.get(color_key, "")).strip_edges()
	# Sinon fallback sur la valeur par défaut
	return str(_cfg.get("default_background_color", "")).strip_edges()

func _get_header_background_opacity() -> float:
	var key: String = _get_header_screen_key()
	if key.is_empty():
		return float(_cfg.get("default_background_opacity", 0.85))
	var opacity_key := key + "_background_opacity"
	var op: Variant = _cfg.get(opacity_key, null) if _cfg.has(opacity_key) else null
	if op == null:
		op = _cfg.get("default_background_opacity", 0.85)
	return float(op)

func _get_minimum_size() -> Vector2:
	# Ne jamais imposer une largeur min au parent : le header doit tenir dans le viewport.
	var h: float = custom_minimum_size.y
	return Vector2(0.0, h)

func _build_styles() -> void:
	var rect_cfg: Dictionary = _cfg.get("rectangle", {})
	var radius: float = float(rect_cfg.get("border_radius", 12))
	var bg_color: Color = Color.from_string(str(rect_cfg.get("background_color", "#1a1a2e")), Color.BLACK)
	var opacity: float = float(rect_cfg.get("background_opacity", 0.85))
	bg_color.a = opacity

	_rect_style = StyleBoxFlat.new()
	_rect_style.set_bg_color(bg_color)
	_rect_style.set_corner_radius_all(int(radius))
	var border_hex: String = str(rect_cfg.get("border_color", "")).strip_edges()
	if border_hex != "":
		var bw: int = int(rect_cfg.get("border_width", 1))
		_rect_style.set_border_width_all(maxi(1, bw))
		_rect_style.set_border_color(Color.from_string(border_hex, Color.TRANSPARENT))
	var cm_l: int = int(rect_cfg.get("content_margin_left", 0))
	var cm_t: int = int(rect_cfg.get("content_margin_top", 0))
	var cm_r: int = int(rect_cfg.get("content_margin_right", 0))
	var cm_b: int = int(rect_cfg.get("content_margin_bottom", 0))
	_rect_style.content_margin_left = cm_l
	_rect_style.content_margin_top = cm_t
	_rect_style.content_margin_right = cm_r
	_rect_style.content_margin_bottom = cm_b

	# Même style sans bordure pour protocols et cristaux (bordure réservée au bloc level)
	_rect_style_no_border = _rect_style.duplicate()
	_rect_style_no_border.set_border_width_all(0)

	var xp_cfg: Dictionary = _cfg.get("xp_bar", {})
	var track_color: Color = Color.from_string(str(xp_cfg.get("track_color", "#2d2d44")), Color.DARK_GRAY)
	var bg_opacity: float = float(rect_cfg.get("background_opacity", 0.85))
	track_color.a = bg_opacity
	var fill_color: Color = Color.from_string(str(xp_cfg.get("fill_color", "#6b4c9a")), Color.PURPLE)
	_xp_bar_track_style = StyleBoxFlat.new()
	_xp_bar_track_style.set_bg_color(track_color)
	_xp_bar_track_style.set_corner_radius_all(int(radius))
	_xp_bar_border_width = 0
	var xp_border_hex: String = str(xp_cfg.get("border_color", "")).strip_edges()
	if xp_border_hex != "":
		var xp_border_color: Color = _parse_hex_color(xp_border_hex, Color.TRANSPARENT)
		var xp_bw: int = mini(8, maxi(1, int(xp_cfg.get("border_width", 1))))
		_xp_bar_border_width = xp_bw
		_xp_bar_track_style.set_border_width_all(xp_bw)
		_xp_bar_track_style.set_border_color(xp_border_color)
		# Inset du contenu = épaisseur de l'outline (barre + chiffres à l'intérieur)
		_xp_bar_track_style.content_margin_left = xp_bw
		_xp_bar_track_style.content_margin_top = xp_bw
		_xp_bar_track_style.content_margin_right = xp_bw
		_xp_bar_track_style.content_margin_bottom = xp_bw
	_xp_bar_fill_style = StyleBoxFlat.new()
	_xp_bar_fill_style.set_bg_color(fill_color)
	_xp_bar_fill_style.set_corner_radius_all(int(radius))

func _build_ui() -> void:
	var height_px: int = int(_cfg.get("height_px", 72))
	var margin_l: int = int(_cfg.get("margin_left", 20))
	var margin_r: int = int(_cfg.get("margin_right", 20))
	var margin_t: int = int(_cfg.get("margin_top", 8))
	var grad_h: int = int(_cfg.get("bottom_gradient_height_px", 20))
	if grad_h < 0:
		grad_h = 0
	if grad_h > height_px:
		grad_h = height_px

	custom_minimum_size.y = height_px
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor_bottom = 0.0
	z_index = 50
	clip_contents = true
	# Ne jamais imposer une largeur min : prendre celle du parent (viewport).
	custom_minimum_size.x = 0

	# Fond couleur pleine + dégradé sur la bande basse (X px), paramétrable par écran (game.json)
	var _bg_color_hex: String = _get_header_background_color_hex()
	if _bg_color_hex != "":
		var _bg_opacity: float = _get_header_background_opacity()
		var bg_color: Color = Color.from_string(_bg_color_hex, Color.BLACK)
		bg_color.a = _bg_opacity
		# Partie haute : couleur pleine (hors bande de dégradé)
		if grad_h < height_px:
			var top_solid := ColorRect.new()
			top_solid.name = "HeaderBackgroundSolidTop"
			top_solid.color = bg_color
			top_solid.set_anchors_preset(Control.PRESET_TOP_WIDE)
			top_solid.offset_top = 0.0
			top_solid.offset_bottom = -float(grad_h)
			top_solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(top_solid)
		# Partie basse : dégradé strict alpha 1 -> 0 (sans texture pour éviter les artefacts blancs)
		if grad_h > 0:
			var fade_rect := ColorRect.new()
			fade_rect.name = "HeaderBackgroundFadeBottom"
			fade_rect.color = bg_color
			fade_rect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			fade_rect.offset_top = -float(grad_h)
			fade_rect.offset_bottom = 0.0
			fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var fade_shader := Shader.new()
			fade_shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = COLOR;\n\tc.a *= clamp(1.0 - UV.y, 0.0, 1.0);\n\tCOLOR = c;\n}\n"
			var fade_mat := ShaderMaterial.new()
			fade_mat.shader = fade_shader
			fade_rect.material = fade_mat
			add_child(fade_rect)
		# Si grad_h == 0, fond plein partout
		if grad_h == 0:
			var full_solid := ColorRect.new()
			full_solid.name = "HeaderBackgroundSolidFull"
			full_solid.color = bg_color
			full_solid.set_anchors_preset(Control.PRESET_FULL_RECT)
			full_solid.set_offsets_preset(Control.PRESET_FULL_RECT)
			full_solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(full_solid)

	var root := MarginContainer.new()
	root.name = "RootMargin"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", margin_l)
	root.add_theme_constant_override("margin_right", margin_r)
	root.add_theme_constant_override("margin_top", margin_t)
	add_child(root)

	# Layout par ancres (pas HBox) pour forcer un vrai 33/33/33 indépendant du contenu
	var layout := Control.new()
	layout.name = "HeaderLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(layout)

	var left_cell := HBoxContainer.new()
	left_cell.name = "LeftCell"
	left_cell.set_anchor(SIDE_LEFT, 0.0)
	left_cell.set_anchor(SIDE_RIGHT, 1.0 / 3.0)
	left_cell.set_anchor(SIDE_TOP, 0.0)
	left_cell.set_anchor(SIDE_BOTTOM, 1.0)
	left_cell.set_offset(SIDE_LEFT, 0)
	left_cell.set_offset(SIDE_RIGHT, 0)
	left_cell.set_offset(SIDE_TOP, 0)
	left_cell.set_offset(SIDE_BOTTOM, 0)
	left_cell.alignment = BoxContainer.ALIGNMENT_BEGIN
	layout.add_child(left_cell)

	var center_cell := HBoxContainer.new()
	center_cell.name = "CenterCell"
	center_cell.set_anchor(SIDE_LEFT, 1.0 / 3.0)
	center_cell.set_anchor(SIDE_RIGHT, 2.0 / 3.0)
	center_cell.set_anchor(SIDE_TOP, 0.0)
	center_cell.set_anchor(SIDE_BOTTOM, 1.0)
	center_cell.set_offset(SIDE_LEFT, 0)
	center_cell.set_offset(SIDE_RIGHT, 0)
	center_cell.set_offset(SIDE_TOP, 0)
	center_cell.set_offset(SIDE_BOTTOM, 0)
	center_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(center_cell)

	var right_cell := HBoxContainer.new()
	right_cell.name = "RightCell"
	right_cell.set_anchor(SIDE_LEFT, 2.0 / 3.0)
	right_cell.set_anchor(SIDE_RIGHT, 1.0)
	right_cell.set_anchor(SIDE_TOP, 0.0)
	right_cell.set_anchor(SIDE_BOTTOM, 1.0)
	right_cell.set_offset(SIDE_LEFT, 0)
	right_cell.set_offset(SIDE_RIGHT, 0)
	right_cell.set_offset(SIDE_TOP, 0)
	right_cell.set_offset(SIDE_BOTTOM, 0)
	right_cell.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(right_cell)

	# --- Level + XP block (left): icône trophée + niveau en dehors, seul le rectangle contient la barre XP ---
	var rect_cfg: Dictionary = _cfg.get("rectangle", {})
	var rect_height: int = int(rect_cfg.get("height", height_px))
	var align_h: String = str(rect_cfg.get("content_align_h", "center")).strip_edges()
	var align_v: String = str(rect_cfg.get("content_align_v", "center")).strip_edges()
	var cm_l: int = int(rect_cfg.get("content_margin_left", 8))
	var cm_t: int = int(rect_cfg.get("content_margin_top", 8))
	var cm_r: int = int(rect_cfg.get("content_margin_right", 8))
	var cm_b: int = int(rect_cfg.get("content_margin_bottom", 8))
	var icon_overlap: int = int(rect_cfg.get("icon_overlap_px", 12))

	var level_cfg: Dictionary = _cfg.get("level", {})
	var level_asset: String = _resolve_asset(str(level_cfg.get("asset", "")))
	var icon_size: int = int(level_cfg.get("icon_size", 48))
	var icon_size_clamped: int = mini(icon_size, height_px)

	# Wrapper: icône à gauche (z-index au-dessus) + rectangle (barre XP uniquement)
	var level_block_wrapper := HBoxContainer.new()
	level_block_wrapper.name = "LevelBlockWrapper"
	level_block_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_block_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	level_block_wrapper.add_theme_constant_override("separation", -icon_overlap)
	left_cell.add_child(level_block_wrapper)

	_level_icon = TextureRect.new()
	_level_icon.name = "LevelIcon"
	_level_icon.custom_minimum_size = Vector2(icon_size_clamped, icon_size_clamped)
	_level_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_level_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_level_icon.z_index = 1
	if level_asset != "" and ResourceLoader.exists(level_asset):
		_level_icon.texture = load(level_asset) as Texture2D
	level_block_wrapper.add_child(_level_icon)

	var level_rect_wrapper := Control.new()
	level_rect_wrapper.name = "LevelRectWrapper"
	level_rect_wrapper.custom_minimum_size.y = rect_height
	level_rect_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_rect_wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_block_wrapper.add_child(level_rect_wrapper)
	_level_rect_wrapper = level_rect_wrapper

	var level_panel := PanelContainer.new()
	level_panel.name = "LevelPanel"
	# Pour le bloc XP, on ne veut que la barre (track) et pas un gros rectangle arrondi derrière :
	# on utilise un style vide pour que seul XpBarPanel soit visible.
	var level_panel_style := StyleBoxEmpty.new()
	level_panel.add_theme_stylebox_override("panel", level_panel_style)
	level_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.set_offsets_preset(Control.PRESET_FULL_RECT)
	level_panel.clip_contents = true
	level_rect_wrapper.add_child(level_panel)
	_level_panel = level_panel

	# Barre XP seule dans le rectangle (pas d'icône dedans)
	var xp_bar_cfg: Dictionary = _cfg.get("xp_bar", {})
	var bar_min_w: int = int(xp_bar_cfg.get("bar_min_width", 120))
	var bar_fixed: int = int(xp_bar_cfg.get("width", 0))
	var bar_w: int = bar_fixed if bar_fixed > 0 else bar_min_w
	var xp_text_ml: int = int(xp_bar_cfg.get("text_margin_left", 0))
	var xp_text_mr: int = int(xp_bar_cfg.get("text_margin_right", 0))
	var xp_wrapper := MarginContainer.new()
	xp_wrapper.name = "XpBarWrapper"
	xp_wrapper.custom_minimum_size.x = bar_w + xp_text_ml + xp_text_mr + 2 * _xp_bar_border_width
	# Largeur fixe centrée dans la colonne si width > 0, sinon comportement extensible comme avant
	if bar_fixed > 0:
		xp_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		xp_wrapper.add_theme_constant_override("margin_left", 0)
	else:
		xp_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_wrapper.add_theme_constant_override("margin_left", -icon_overlap)
	level_panel.add_child(xp_wrapper)

	var xp_panel := PanelContainer.new()
	xp_panel.name = "XpBarPanel"
	# Track de fond : même largeur que le wrapper
	if bar_fixed > 0:
		xp_panel.custom_minimum_size.x = bar_w + xp_text_ml + xp_text_mr + 2 * _xp_bar_border_width
		xp_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		xp_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_panel.add_theme_stylebox_override("panel", _xp_bar_track_style)
	xp_wrapper.add_child(xp_panel)
	_xp_track_panel = xp_panel

	# Un seul conteneur à l'intérieur du track (zone déjà inset par le content_margin du style).
	# Barre et chiffres se superposent (même zone) pour ne pas augmenter la hauteur.
	var xp_content_box := Control.new()
	xp_content_box.name = "XpTrackContent"
	xp_content_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_content_box.set_offsets_preset(Control.PRESET_FULL_RECT)
	xp_panel.add_child(xp_content_box)
	_xp_track_content = xp_content_box
	xp_content_box.resized.connect(_update_xp_fill_size)

	var xp_inner := HBoxContainer.new()
	xp_inner.name = "XpBarInner"
	xp_inner.add_theme_constant_override("separation", 0)
	xp_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_inner.set_offsets_preset(Control.PRESET_FULL_RECT)
	var xp_fill := PanelContainer.new()
	xp_fill.name = "XpBarFill"
	xp_fill.add_theme_stylebox_override("panel", _xp_bar_fill_style)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_inner.add_child(xp_fill)
	_xp_fill_panel = xp_fill
	var xp_spacer := Control.new()
	xp_spacer.name = "XpSpacer"
	xp_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_inner.add_child(xp_spacer)
	xp_content_box.add_child(xp_inner)

	_xp_label = Label.new()
	_xp_label.name = "XpLabel"
	_xp_label.horizontal_alignment = _parse_h_align(align_h)
	_xp_label.vertical_alignment = _parse_v_align(align_v)
	_xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_label.set_offsets_preset(Control.PRESET_FULL_RECT)
	var xp_text_col: String = str(xp_bar_cfg.get("text_color", "#ffffff"))
	_xp_label.add_theme_color_override("font_color", Color.from_string(xp_text_col, Color.WHITE))
	_xp_label.add_theme_font_size_override("font_size", int(xp_bar_cfg.get("font_size", 16)))
	_xp_label_wrapper = MarginContainer.new()
	_xp_label_wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_label_wrapper.set_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_label_wrapper.add_theme_constant_override("margin_left", xp_text_ml)
	_xp_label_wrapper.add_theme_constant_override("margin_right", xp_text_mr)
	_xp_label_wrapper.add_child(_xp_label)
	_xp_label_wrapper.z_index = 5 # Guarantee it renders above the fill panels
	xp_content_box.add_child(_xp_label_wrapper)
	# Chiffres XP visibles uniquement au clic/appui sur la barre
	_xp_label_wrapper.visible = false
	_xp_label.visible = true
	
	_level_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_rect_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_label_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	level_block_wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	level_block_wrapper.gui_input.connect(_on_xp_bar_gui_input)

	_xp_track_panel.resized.connect(_update_xp_fill_size)

	# --- Stars block: icône à gauche (z-index au-dessus), seul le nombre dans le rectangle ---
	var protocols_cfg: Dictionary = _cfg.get("stars", {})
	var protocols_asset: String = _resolve_asset(str(protocols_cfg.get("asset", "")))
	var proto_icon_sz: int = int(protocols_cfg.get("icon_size", 32))
	var proto_icon_sz_clamped: int = mini(proto_icon_sz, height_px)
	var proto_offset_x: int = int(protocols_cfg.get("center_offset_x", 0))
	if proto_offset_x != 0:
		center_cell.set_offset(SIDE_LEFT, proto_offset_x)
		center_cell.set_offset(SIDE_RIGHT, proto_offset_x)

	var protocols_block_wrapper := HBoxContainer.new()
	protocols_block_wrapper.name = "ProtocolsBlockWrapper"
	protocols_block_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	protocols_block_wrapper.add_theme_constant_override("separation", -icon_overlap)
	center_cell.add_child(protocols_block_wrapper)

	_protocols_icon = TextureRect.new()
	_protocols_icon.name = "ProtocolsIcon"
	_protocols_icon.custom_minimum_size = Vector2(proto_icon_sz_clamped, proto_icon_sz_clamped)
	_protocols_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_protocols_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_protocols_icon.z_index = 1
	if protocols_asset != "" and ResourceLoader.exists(protocols_asset):
		_protocols_icon.texture = load(protocols_asset) as Texture2D
	protocols_block_wrapper.add_child(_protocols_icon)

	_protocols_label = Label.new()
	_protocols_label.horizontal_alignment = _parse_h_align(align_h)
	_protocols_label.vertical_alignment = _parse_v_align(align_v)
	_protocols_label.add_theme_color_override("font_color", Color.from_string(str(protocols_cfg.get("text_color", "#ffffff")), Color.WHITE))
	_protocols_label.add_theme_font_size_override("font_size", int(protocols_cfg.get("font_size", 18)))

	var protocols_rect_wrapper := Control.new()
	protocols_rect_wrapper.name = "ProtocolsRectWrapper"
	protocols_rect_wrapper.custom_minimum_size.y = rect_height
	protocols_rect_wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	protocols_block_wrapper.add_child(protocols_rect_wrapper)
	_protocols_rect_wrapper = protocols_rect_wrapper

	var protocols_panel := PanelContainer.new()
	protocols_panel.name = "ProtocolsPanel"
	protocols_panel.add_theme_stylebox_override("panel", _rect_style_no_border.duplicate())
	protocols_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	protocols_panel.set_offsets_preset(Control.PRESET_FULL_RECT)
	protocols_panel.clip_contents = true
	var stars_inner := MarginContainer.new()
	stars_inner.add_theme_constant_override("margin_left", int(protocols_cfg.get("text_margin_left", cm_l)))
	stars_inner.add_theme_constant_override("margin_right", int(protocols_cfg.get("text_margin_right", cm_r)))
	stars_inner.add_theme_constant_override("margin_top", cm_t)
	stars_inner.add_theme_constant_override("margin_bottom", cm_b)
	stars_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars_inner.add_child(_protocols_label)
	protocols_panel.add_child(stars_inner)
	protocols_rect_wrapper.add_child(protocols_panel)

	# --- Crystals block: enfant normal du right_cell HBox (alignment=END le pousse à droite) ---
	var crystals_cfg: Dictionary = _cfg.get("crystals", {})
	var crystal_icon_sz: int = int(crystals_cfg.get("icon_size", 28))
	var crystal_icon_sz_clamped: int = mini(crystal_icon_sz, height_px)

	var crystals_container := MarginContainer.new()
	crystals_container.name = "CrystalsContainer"
	crystals_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_cell.add_child(crystals_container)

	var crystals_inner_hbox := HBoxContainer.new()
	crystals_inner_hbox.add_theme_constant_override("separation", -icon_overlap)
	crystals_inner_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	crystals_container.add_child(crystals_inner_hbox)

	_crystal_icon = TextureRect.new()
	_crystal_icon.custom_minimum_size = Vector2(crystal_icon_sz_clamped, crystal_icon_sz_clamped)
	_crystal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crystal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crystal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crystal_icon.z_index = 1
	var crystal_asset: String = _resolve_asset(str(crystals_cfg.get("icon_asset", "shared:crystal_icon")))
	if crystal_asset != "":
		var tex: Texture2D = _load_texture(crystal_asset)
		if tex:
			_crystal_icon.texture = tex
	crystals_inner_hbox.add_child(_crystal_icon)

	var crystal_number_panel := PanelContainer.new()
	crystal_number_panel.name = "CrystalNumberPanel"
	crystal_number_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_number_panel.custom_minimum_size.y = rect_height
	crystal_number_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crystal_number_panel.add_theme_stylebox_override("panel", _rect_style_no_border.duplicate())
	crystal_number_panel.clip_contents = true

	var crystals_inner := MarginContainer.new()
	crystals_inner.add_theme_constant_override("margin_left", int(crystals_cfg.get("text_margin_left", cm_l)))
	crystals_inner.add_theme_constant_override("margin_right", int(crystals_cfg.get("text_margin_right", cm_r)))
	crystals_inner.add_theme_constant_override("margin_top", cm_t)
	crystals_inner.add_theme_constant_override("margin_bottom", cm_b)
	crystals_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_number_panel.add_child(crystals_inner)

	_crystal_label = Label.new()
	_crystal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crystal_label.horizontal_alignment = _parse_h_align(align_h)
	_crystal_label.vertical_alignment = _parse_v_align(align_v)
	_crystal_label.add_theme_color_override("font_color", Color.from_string(str(crystals_cfg.get("text_color", "#ffffff")), Color.WHITE))
	_crystal_label.add_theme_font_size_override("font_size", int(crystals_cfg.get("font_size", 18)))
	crystals_inner.add_child(_crystal_label)

	crystals_inner_hbox.add_child(crystal_number_panel)

	_crystals_panel = Button.new()
	_crystals_panel.name = "CrystalsPanel"
	_crystals_panel.flat = true
	_crystals_panel.focus_mode = Control.FOCUS_NONE
	var empty_style := StyleBoxEmpty.new()
	_crystals_panel.add_theme_stylebox_override("normal", empty_style)
	_crystals_panel.add_theme_stylebox_override("hover", empty_style)
	_crystals_panel.add_theme_stylebox_override("pressed", empty_style)
	_crystals_panel.add_theme_stylebox_override("disabled", empty_style)
	_crystals_panel.pressed.connect(_on_crystals_pressed)
	crystals_container.add_child(_crystals_panel)

	# Level label on top of level icon (level number, centré dans le symbole selon icon_size)
	var level_center := CenterContainer.new()
	level_center.name = "LevelLabelCenter"
	level_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_center.set_offsets_preset(Control.PRESET_FULL_RECT)
	level_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_icon.add_child(level_center)

	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_color_override("font_color", Color.from_string(str(level_cfg.get("text_color", "#ffffff")), Color.WHITE))
	var level_font_sz: int = int(level_cfg.get("font_size", 20))
	_level_label.add_theme_font_size_override("font_size", level_font_sz)
	_level_label.custom_minimum_size = Vector2.ZERO
	level_center.add_child(_level_label)

	_update_values()
	call_deferred("_update_xp_fill_size")
	call_deferred("_clamp_width_to_viewport")
	if DEBUG_RECT_HEIGHT:
		call_deferred("_debug_rect_heights")

func _debug_rect_heights() -> void:
	if not DEBUG_RECT_HEIGHT:
		return
	var rect_cfg: Dictionary = _cfg.get("rectangle", {})
	var rect_height: int = int(rect_cfg.get("height", 48))
	var height_px: int = int(_cfg.get("height_px", 72))
	var cm_l: int = int(rect_cfg.get("content_margin_left", 0))
	var cm_t: int = int(rect_cfg.get("content_margin_top", 0))
	var cm_r: int = int(rect_cfg.get("content_margin_right", 0))
	var cm_b: int = int(rect_cfg.get("content_margin_bottom", 0))
	print("[MenuHeader] === DEBUG RECT HEIGHT ===")
	print("  Config: rectangle.height=%d  header height_px=%d" % [rect_height, height_px])
	print("  rectangle content_margin: L=%d T=%d R=%d B=%d" % [cm_l, cm_t, cm_r, cm_b])
	print("  _rect_style content_margin: L=%d T=%d R=%d B=%d" % [_rect_style.content_margin_left, _rect_style.content_margin_top, _rect_style.content_margin_right, _rect_style.content_margin_bottom])
	print("  _xp_bar_track_style content_margin (inset barre): L=%d T=%d R=%d B=%d" % [_xp_bar_track_style.content_margin_left, _xp_bar_track_style.content_margin_top, _xp_bar_track_style.content_margin_right, _xp_bar_track_style.content_margin_bottom])
	print("  Header: size=%s custom_minimum_size=%s clip_contents=%s" % [size, custom_minimum_size, clip_contents])
	var root: Control = get_child(0) if get_child_count() > 0 else null
	var layout_node: Control = root.get_child(0) if root and root.get_child_count() > 0 else null
	if layout_node:
		print("  HeaderLayout: size=%s custom_minimum_size=%s" % [layout_node.size, layout_node.custom_minimum_size])
		for cell_node in layout_node.get_children():
			if cell_node is Control:
				print("    %s: pos=%s size=%s anchors=[%.3f, %.3f]" % [cell_node.name, cell_node.position, cell_node.size, cell_node.anchor_left, cell_node.anchor_right])
	if is_instance_valid(_level_rect_wrapper):
		var wr: Control = _level_rect_wrapper
		var panel: Control = wr.get_child(0) if wr.get_child_count() > 0 else null
		print("  [XP] LevelRectWrapper: size=%s custom_minimum_size=%s size_flags_vertical=%s" % [wr.size, wr.custom_minimum_size, wr.size_flags_vertical])
		if panel:
			print("        LevelPanel (enfant): size=%s custom_minimum_size=%s clip_contents=%s" % [panel.size, panel.custom_minimum_size, panel.clip_contents])
		var level_block: Control = wr.get_parent() if is_instance_valid(wr) else null
		if level_block:
			print("        LevelBlockWrapper (parent): size=%s custom_minimum_size=%s" % [level_block.size, level_block.custom_minimum_size])
		if panel and panel.get_child_count() > 0:
			var xp_wrap: Control = panel.get_child(0)
			print("        XpBarWrapper (1er enfant panel): size=%s custom_minimum_size=%s" % [xp_wrap.size, xp_wrap.custom_minimum_size])
			if xp_wrap.get_child_count() > 0:
				var xp_track: Control = xp_wrap.get_child(0)
				print("        XpBarPanel (track): size=%s custom_minimum_size=%s" % [xp_track.size, xp_track.custom_minimum_size])
	else:
		print("  [XP] LevelRectWrapper non trouvé")
	if is_instance_valid(_protocols_rect_wrapper):
		var wr: Control = _protocols_rect_wrapper
		var panel: Control = wr.get_child(0) if wr.get_child_count() > 0 else null
		print("  [Protocols] ProtocolsRectWrapper: size=%s custom_minimum_size=%s size_flags_vertical=%s" % [wr.size, wr.custom_minimum_size, wr.size_flags_vertical])
		if panel:
			print("        ProtocolsPanel (enfant): size=%s custom_minimum_size=%s clip_contents=%s" % [panel.size, panel.custom_minimum_size, panel.clip_contents])
		var proto_block: Control = wr.get_parent() if is_instance_valid(wr) else null
		if proto_block:
			print("        ProtocolsBlockWrapper (parent): size=%s custom_minimum_size=%s" % [proto_block.size, proto_block.custom_minimum_size])
	else:
		print("  [Protocols] ProtocolsRectWrapper non trouvé")
	print("[MenuHeader] === FIN DEBUG RECT HEIGHT ===")

func _resolve_asset(path_or_shared: String) -> String:
	var s := path_or_shared.strip_edges()
	if s.begins_with("shared:"):
		var id := s.trim_prefix("shared:")
		if DataManager != null and DataManager.has_method("get_shared_asset_path"):
			return DataManager.get_shared_asset_path(id, "")
		return ""
	return s

## Parse une chaîne hex (#RRGGBB ou #RRGGBBAA) sans planter ; retourne fallback si invalide.
func _parse_hex_color(hex: String, fallback: Color) -> Color:
	var s := hex.strip_edges()
	if s.is_empty():
		return fallback
	if not s.begins_with("#"):
		s = "#" + s
	if s.length() != 7 and s.length() != 9:
		return fallback
	for i in range(1, s.length()):
		var c: String = s[i]
		if not (c >= "0" and c <= "9" or c >= "a" and c <= "f" or c >= "A" and c <= "F"):
			return fallback
	return Color(s)

func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if DataManager != null and DataManager.has_method("get_texture_from_resource_path"):
		return DataManager.get_texture_from_resource_path(path)
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			return res as Texture2D
		if res is SpriteFrames:
			var sf: SpriteFrames = res as SpriteFrames
			var names := sf.get_animation_names()
			if names.size() > 0 and sf.get_frame_count(names[0]) > 0:
				return sf.get_frame_texture(names[0], 0)
	return null

func _parse_h_align(s: String) -> HorizontalAlignment:
	match s.to_lower():
		"left":
			return HORIZONTAL_ALIGNMENT_LEFT
		"right":
			return HORIZONTAL_ALIGNMENT_RIGHT
		_:
			return HORIZONTAL_ALIGNMENT_CENTER

func _parse_v_align(s: String) -> VerticalAlignment:
	match s.to_lower():
		"top":
			return VERTICAL_ALIGNMENT_TOP
		"bottom":
			return VERTICAL_ALIGNMENT_BOTTOM
		_:
			return VERTICAL_ALIGNMENT_CENTER

func _update_values() -> void:
	if not is_instance_valid(_level_label):
		return
	var level: int = ProfileManager.get_player_level() if ProfileManager else 1
	_level_label.text = str(level)

	var xp_current: int = ProfileManager.get_player_xp() if ProfileManager else 0
	var xp_max: int = ProfileManager.get_xp_for_level(level) if ProfileManager else 100
	var ratio: float = 1.0 if xp_max <= 0 else clampf(float(xp_current) / float(xp_max), 0.0, 1.0)
	if is_instance_valid(_xp_label):
		var locale: String = LocaleManager.get_locale() if LocaleManager else "en"
		# Premier chiffre sans unité (k/m/M), le second suffit pour comprendre
		_xp_label.text = str(xp_current) + "/" + _format_compact_number(xp_max, locale)
	_xp_bar_ratio = ratio

	var stars_count: int = 0
	var stars_max: int = 0
	if App and App.has_method("get_worlds") and ProfileManager and ProfileManager.has_method("get_level_stars"):
		for wv in App.get_worlds():
			if wv is Dictionary:
				var wid: String = str((wv as Dictionary).get("id", ""))
				if wid == "": continue
				var levels_v: Variant = wv.get("levels", [])
				var levels: Array = levels_v if levels_v is Array else []
				stars_max += levels.size() * 3
				for lvl in levels:
					if lvl is Dictionary:
						var lid: String = str((lvl as Dictionary).get("id", ""))
						if lid == "": lid = wid + "_lvl_" + str((lvl as Dictionary).get("index", 0))
						stars_count += ProfileManager.get_level_stars(wid, lid)

	var format_str: String = str(_cfg.get("stars", {}).get("format", "{count}/{max}"))
	if is_instance_valid(_protocols_label):
		_protocols_label.text = format_str.replace("{count}", str(stars_count)).replace("{max}", str(stars_max))

	var crystals: int = ProfileManager.get_crystals() if ProfileManager else 0
	if is_instance_valid(_crystal_label):
		var locale: String = LocaleManager.get_locale() if LocaleManager else "en"
		_crystal_label.text = _format_compact_number(crystals, locale)

	_update_xp_fill_size()

func _on_xp_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_instance_valid(_xp_label_wrapper):
			_xp_label_wrapper.visible = not _xp_label_wrapper.visible
	elif event is InputEventScreenTouch and not event.pressed:
		if is_instance_valid(_xp_label_wrapper):
			_xp_label_wrapper.visible = not _xp_label_wrapper.visible

var _xp_bar_ratio: float = 0.0

func _update_xp_fill_size() -> void:
	if not is_instance_valid(_xp_fill_panel) or not is_instance_valid(_xp_track_panel):
		return
	var ref: Control = _xp_track_content if is_instance_valid(_xp_track_content) else _xp_track_panel
	var sz: Vector2 = ref.size
	if sz.x <= 0 or sz.y <= 0:
		return
	var fill_w: int = maxi(0, int(sz.x * _xp_bar_ratio))
	_xp_fill_panel.custom_minimum_size = Vector2(fill_w, int(sz.y))

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_update_values()
	elif what == NOTIFICATION_ENTER_TREE:
		if ProfileManager:
			if not ProfileManager.level_up.is_connected(_on_profile_updated):
				ProfileManager.level_up.connect(_on_profile_updated)
			# MAJ live du compteur de cristaux (achats idle factory, shop, gains).
			if ProfileManager.has_signal("crystals_changed") \
					and not ProfileManager.crystals_changed.is_connected(_on_crystals_changed):
				ProfileManager.crystals_changed.connect(_on_crystals_changed)
	elif what == NOTIFICATION_RESIZED:
		_clamp_width_to_viewport()

func _process(delta: float) -> void:
	if visible and is_inside_tree():
		_debug_timer += delta
		_clamp_width_to_viewport()

func _on_profile_updated(_new_level: int, _points: int) -> void:
	_update_values()

func _on_crystals_changed(amount: int) -> void:
	if is_instance_valid(_crystal_label):
		var locale: String = LocaleManager.get_locale() if LocaleManager else "en"
		_crystal_label.text = _format_compact_number(amount, locale)

func _clamp_width_to_viewport() -> void:
	var vp_rect: Rect2 = get_viewport_rect()
	var vp_w: float = vp_rect.size.x
	if vp_w <= 0.0:
		return
	if size.x > vp_w:
		size = Vector2(vp_w, size.y)
	set_anchor(SIDE_RIGHT, 1.0)
	set_offset(SIDE_RIGHT, 0.0)
	set_offset(SIDE_LEFT, 0.0)
	_debug_header_layout(vp_w)

func _on_crystals_pressed() -> void:
	crystals_pressed.emit()

## Format entier en court : 1-999 tel quel, 1k-99,9k (1 decimale), 100k-999k (entier),
## 1,0m-99,9m (1 decimale), 100m-999m (entier), milliards "M" (fr) / "b" (en).
func _format_compact_number(value: int, locale: String) -> String:
	if value < 1000:
		return str(value)
	if value < 100_000:
		var v: float = value / 1000.0
		var s: String = "%.1f" % v
		if locale == "fr":
			s = s.replace(".", ",")
		return s + "k"
	if value < 1_000_000:
		return str(value / 1000.0) + "k"
	if value < 100_000_000:
		var v: float = value / 1_000_000.0
		var s: String = "%.1f" % v
		if locale == "fr":
			s = s.replace(".", ",")
		return s + "m"
	if value < 1_000_000_000:
		return str(value / 1_000_000.0) + "m"
	var billion_suffix: String = "M" if locale == "fr" else "b"
	if value < 100_000_000_000:
		var v: float = value / 1_000_000_000.0
		var s: String = "%.1f" % v
		if locale == "fr":
			s = s.replace(".", ",")
		return s + billion_suffix
	return str(value / 1_000_000_000.0) + billion_suffix

func _debug_header_layout(vp_width: float) -> void:
	if not DEBUG_HEADER_LAYOUT:
		return
	var header_w: float = size.x
	var crystals_left: float = 0.0
	var crystals_right: float = 0.0
	if is_instance_valid(_crystals_panel):
		var global_pos: Vector2 = _crystals_panel.global_position
		crystals_left = global_pos.x
		crystals_right = global_pos.x + _crystals_panel.size.x
	var changed: bool = (abs(_last_debug_vp - vp_width) > 1.0 or abs(_last_debug_header - header_w) > 1.0 or abs(_last_debug_crystals_right - crystals_right) > 1.0)
	var throttle_ok: bool = _debug_timer >= 2.0
	if changed or throttle_ok:
		if throttle_ok:
			_debug_timer = 0.0
		_last_debug_vp = vp_width
		_last_debug_header = header_w
		_last_debug_crystals_right = crystals_right
		var status: String = "dans" if crystals_right <= vp_width else "HORS"
		print("[MenuHeader] viewport_width=%.0f header_width=%.0f crystals_left=%.0f crystals_right=%.0f (cristaux %s ecran)" % [vp_width, header_w, crystals_left, crystals_right, status])

## Call from parent when returning to the menu (e.g. after a game) to refresh header.
func refresh() -> void:
	_update_values()
