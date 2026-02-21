extends Control

## SkillsMenu — Ecran de l'arbre de competences.
## 3 onglets: Magic (exclusif), Utility (passif), Pew Pew (Paragon).
## Scrollable, avec popup de details.

signal back_requested

# =============================================================================
# REFERENCES
# =============================================================================

var _header: VBoxContainer
var _main_vbox: VBoxContainer
var _tab_container: HBoxContainer
var _scroll_container: ScrollContainer
var _skill_grid: VBoxContainer
var _footer: HBoxContainer
var _back_button: TextureButton
var _respec_button: Button
var _info_label: Label
var _skill_points_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _title_label: Label

var _active_tab: String = "magic"
const TAB_IDS: Array[String] = ["magic", "utility", "pew_pew"]
const BRANCH_TO_BLOCK := {
	"frozen": "cryo",
	"poison": "toxin",
	"void": "singularity",
	"loot": "fortune",
	"powers": "tech",
	"fire_patterns": "fire",
	"stat_boosts": "perfection"
}

var _skill_nodes: Dictionary = {} # skill_id -> Button
var _popup: Control = null
var _skills_menu_cfg: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_ui_config()
	_build_ui()
	_refresh_display()

func _load_ui_config() -> void:
	var game_cfg: Dictionary = DataManager.get_game_config()
	if game_cfg.is_empty():
		var file := FileAccess.open("res://data/game.json", FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				game_cfg = json.data
			file.close()
	var raw_cfg: Variant = game_cfg.get("SkillsMenu", {})
	if raw_cfg is Dictionary:
		_skills_menu_cfg = raw_cfg as Dictionary
	else:
		_skills_menu_cfg = {}

func _build_ui() -> void:
	# Root layout
	anchor_right = 1.0
	anchor_bottom = 1.0

	_add_page_background()

	_main_vbox = VBoxContainer.new()
	_main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 25)
	_main_vbox.add_theme_constant_override("separation", 10)
	add_child(_main_vbox)

	# --- Header ---
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	_main_vbox.add_child(_header)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	_header.add_child(title_row)

	_back_button = TextureButton.new()
	_back_button.custom_minimum_size = Vector2(75, 75)
	_back_button.ignore_texture_size = true
	_back_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var ui_icons: Dictionary = {}
	var game_cfg: Dictionary = DataManager.get_game_config()
	if game_cfg.has("ui_icons") and game_cfg["ui_icons"] is Dictionary:
		ui_icons = game_cfg["ui_icons"] as Dictionary
	var back_asset := str(ui_icons.get("back_button", ""))
	if back_asset != "" and ResourceLoader.exists(back_asset):
		_back_button.texture_normal = load(back_asset)
	_back_button.pressed.connect(_on_back_pressed)
	title_row.add_child(_back_button)

	_title_label = Label.new()
	_title_label.text = _translate("skills.menu.title", {}, "COMPETENCES")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_cfg := _get_config_dict(["title"], {})
	_title_label.add_theme_font_size_override("font_size", int(title_cfg.get("font_size", 38)))
	_title_label.add_theme_color_override("font_color", _to_color(title_cfg.get("text_color", "#FFFFFF"), Color.WHITE))
	title_row.add_child(_title_label)

	var right_spacer := Control.new()
	right_spacer.custom_minimum_size = Vector2(75, 75)
	title_row.add_child(right_spacer)

	# Level + Skill Points
	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 16)
	_header.add_child(info_row)

	var level_cfg := _get_config_dict(["level"], {})
	var level_panel := PanelContainer.new()
	level_panel.custom_minimum_size = Vector2(120, 56)
	level_panel.add_theme_stylebox_override(
		"panel",
		_make_background_style(level_cfg.get("background", "#172544"), Color(0.09, 0.15, 0.27), 8, 0)
	)
	info_row.add_child(level_panel)

	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.add_theme_font_size_override("font_size", int(level_cfg.get("text_size", 26)))
	_level_label.add_theme_color_override("font_color", _to_color(level_cfg.get("text_color", "#D6E4FF"), Color(0.84, 0.9, 1.0)))
	level_panel.add_child(_level_label)

	var points_cfg := _get_config_dict(["available_points"], {})
	var points_panel := PanelContainer.new()
	points_panel.custom_minimum_size = Vector2(120, 56)
	points_panel.add_theme_stylebox_override(
		"panel",
		_make_background_style(points_cfg.get("background", "#4A2F10"), Color(0.29, 0.18, 0.06), 8, 0)
	)
	info_row.add_child(points_panel)

	_skill_points_label = Label.new()
	_skill_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_points_label.add_theme_font_size_override("font_size", int(points_cfg.get("text_size", 26)))
	_skill_points_label.add_theme_color_override("font_color", _to_color(points_cfg.get("text_color", "#FFD56B"), Color(1.0, 0.84, 0.42)))
	points_panel.add_child(_skill_points_label)

	# XP Progress bar
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XPBar"
	_xp_bar.custom_minimum_size = Vector2(520, 30)
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	var xp_bar_style := StyleBoxFlat.new()
	xp_bar_style.bg_color = Color(0.1, 0.1, 0.2)
	xp_bar_style.corner_radius_top_left = 6
	xp_bar_style.corner_radius_top_right = 6
	xp_bar_style.corner_radius_bottom_left = 6
	xp_bar_style.corner_radius_bottom_right = 6
	xp_bar_style.border_color = Color(0.3, 0.35, 0.5, 0.6)
	xp_bar_style.border_width_top = 1
	xp_bar_style.border_width_bottom = 1
	xp_bar_style.border_width_left = 1
	xp_bar_style.border_width_right = 1
	_xp_bar.add_theme_stylebox_override("background", xp_bar_style)
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.3, 0.6, 1.0)
	xp_fill.corner_radius_top_left = 6
	xp_fill.corner_radius_top_right = 6
	xp_fill.corner_radius_bottom_left = 6
	xp_fill.corner_radius_bottom_right = 6
	_xp_bar.add_theme_stylebox_override("fill", xp_fill)

	var xp_row := HBoxContainer.new()
	xp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_child(xp_row)
	xp_row.add_child(_xp_bar)

	var xp_text := Label.new()
	xp_text.name = "XPText"
	xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_text.add_theme_font_size_override("font_size", 14)
	xp_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	xp_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	xp_text.add_theme_constant_override("shadow_offset_x", 1)
	xp_text.add_theme_constant_override("shadow_offset_y", 1)
	xp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_child(xp_text)

	# --- Tab Buttons ---
	_tab_container = HBoxContainer.new()
	_tab_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_container.add_theme_constant_override("separation", 8)
	_main_vbox.add_child(_tab_container)

	for tab_id in TAB_IDS:
		var btn := Button.new()
		btn.name = "Tab_" + tab_id
		btn.text = _tab_label(tab_id)
		btn.custom_minimum_size = Vector2(220, 52)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		_tab_container.add_child(btn)

	# --- Scroll Content ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main_vbox.add_child(_scroll_container)

	_skill_grid = VBoxContainer.new()
	_skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_grid.add_theme_constant_override("separation", 12)
	_scroll_container.add_child(_skill_grid)

	# --- Info Label ---
	var subtitle_cfg := _get_config_dict(["subtitle"], {})
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", int(subtitle_cfg.get("font_size", 20)))
	_info_label.add_theme_color_override("font_color", _to_color(subtitle_cfg.get("text_color", "#C2C9E8"), Color(0.76, 0.79, 0.9)))
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_vbox.add_child(_info_label)

	# --- Footer ---
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override("separation", 16)
	_main_vbox.add_child(_footer)

	_respec_button = Button.new()
	_respec_button.custom_minimum_size = Vector2(230, 56)
	var respec_cfg := _get_config_dict(["respec"], {})
	_apply_button_style(
		_respec_button,
		respec_cfg.get("background", "#4A2632"),
		_to_color(respec_cfg.get("text_color", "#FFFFFF"), Color.WHITE),
		int(respec_cfg.get("text_size", 20)),
		true
	)
	_respec_button.pressed.connect(_on_respec_pressed)
	_footer.add_child(_respec_button)

	_apply_mouse_filter_pass_recursive(_main_vbox)

func _add_page_background() -> void:
	var bg_value: Variant = _get_config_value(["background"], "#0B1020")
	var bg_texture := _background_texture(bg_value)
	if bg_texture != null:
		var bg_tex := TextureRect.new()
		bg_tex.texture = bg_texture
		bg_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg_tex)
		return
	var bg := ColorRect.new()
	bg.color = _to_color(bg_value, Color(0.05, 0.05, 0.12, 1.0))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

func _apply_mouse_filter_pass_recursive(node: Node) -> void:
	if node is Control:
		if node is VScrollBar or node is HScrollBar:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_apply_mouse_filter_pass_recursive(child)

# =============================================================================
# DISPLAY
# =============================================================================

func _refresh_display() -> void:
	_update_header()
	_update_tabs()
	_build_skill_tree()
	_update_respec_button()
	if _main_vbox:
		_apply_mouse_filter_pass_recursive(_main_vbox)

func _update_header() -> void:
	var level := ProfileManager.get_player_level()
	var xp := ProfileManager.get_player_xp()
	var sp := ProfileManager.get_skill_points()
	var xp_required_for_level: int = max(1, ProfileManager.get_xp_for_level(level))

	_level_label.text = str(level)
	_skill_points_label.text = str(sp)
	_title_label.text = _translate("skills.menu.title", {}, "COMPETENCES")

	# XP bar
	if _xp_bar:
		var range_xp: float = float(xp_required_for_level)
		var progress_xp: float = float(clampi(xp, 0, xp_required_for_level))
		var legacy_current: int = ProfileManager.get_xp_for_level(level)
		var legacy_next: int = ProfileManager.get_xp_for_level(level + 1)
		var legacy_range: float = float(legacy_next - legacy_current)
		var legacy_progress: float = float(xp - legacy_current)
		_debug_xp_values(
			level,
			xp,
			xp_required_for_level,
			range_xp,
			progress_xp,
			legacy_current,
			legacy_next,
			legacy_range,
			legacy_progress
		)
		_xp_bar.max_value = range_xp
		_xp_bar.value = progress_xp

		var pct := 0.0
		if _xp_bar.max_value > 0:
			pct = _xp_bar.value / _xp_bar.max_value
		var fill_color := Color(0.3, 0.6, 1.0).lerp(Color(0.3, 1.0, 0.5), pct)
		var xp_fill_style := StyleBoxFlat.new()
		xp_fill_style.bg_color = fill_color
		xp_fill_style.corner_radius_top_left = 6
		xp_fill_style.corner_radius_top_right = 6
		xp_fill_style.corner_radius_bottom_left = 6
		xp_fill_style.corner_radius_bottom_right = 6
		_xp_bar.add_theme_stylebox_override("fill", xp_fill_style)

		var xp_text: Label = _xp_bar.get_node_or_null("XPText")
		if xp_text:
			xp_text.text = str(int(progress_xp)) + " / " + str(int(range_xp)) + "  (" + str(int(pct * 100)) + "%)"

	match _active_tab:
		"magic":
			var branch := ProfileManager.get_active_magic_branch()
			if branch != "":
				_info_label.text = _translate(
					"skills.menu.info.magic_active",
					{"branch": _branch_name(branch)},
					"Branche active: " + _branch_name(branch)
				)
			else:
				_info_label.text = _translate("skills.menu.info.magic_choose", {}, "Choisissez une branche magique.")
		"utility":
			_info_label.text = _translate("skills.menu.info.utility", {}, "Competences passives toujours actives.")
		"pew_pew":
			_info_label.text = _translate("skills.menu.info.pew_ready", {}, "Perfection active.")

func _debug_xp_values(
	level: int,
	xp: int,
	xp_required_for_level: int,
	used_range_xp: float,
	used_progress_xp: float,
	legacy_current: int,
	legacy_next: int,
	legacy_range_xp: float,
	legacy_progress_xp: float
) -> void:
	# Debug orienté diagnostic: compare la formule utilisee (xp locale) avec l'ancienne formule.
	var appears_local_xp: bool = xp >= 0 and xp <= xp_required_for_level
	var legacy_formula_negative: bool = legacy_progress_xp < 0.0

	print(
		"[SkillsMenu][XP DEBUG] level=", level,
		" stored_xp=", xp,
		" used_formula(local): progress=", int(used_progress_xp), " range=", int(used_range_xp),
		" | legacy_formula: progress=", int(legacy_progress_xp), " range=", int(legacy_range_xp),
		" | legacy_inputs(current=", legacy_current, ", next=", legacy_next, ")",
		" | flags{appears_local_xp=", appears_local_xp,
		", legacy_formula_negative=", legacy_formula_negative, "}"
	)

func _get_pew_pew_unlock_progress() -> Dictionary:
	var tree_data := DataManager.get_skill_tree("pew_pew")
	var unlock_req := int(tree_data.get("unlock_requirement", 15))
	var spent_other_trees := ProfileManager.get_spent_skill_points("pew_pew")
	return {
		"required": unlock_req,
		"spent": spent_other_trees
	}

func _update_tabs() -> void:
	for tab_id in TAB_IDS:
		var btn: Button = _tab_container.get_node_or_null("Tab_" + tab_id)
		if btn == null:
			continue
		btn.text = _tab_label(tab_id)
		var btn_cfg := _get_config_dict(["skills", "buttons", tab_id], {})
		var bg_value: Variant = btn_cfg.get("background", "#2D3A5C")
		var text_color := _to_color(btn_cfg.get("text_color", "#FFFFFF"), Color.WHITE)
		var text_size := int(btn_cfg.get("text_size", 18))
		_apply_button_style(btn, bg_value, text_color, text_size, tab_id == _active_tab)

func _apply_button_style(button: Button, bg_value: Variant, text_color: Color, text_size: int, active: bool) -> void:
	var style := _make_background_style(bg_value, Color(0.2, 0.2, 0.28), 7, 0)
	if style is StyleBoxFlat and not active:
		var flat_style := style as StyleBoxFlat
		flat_style.bg_color = flat_style.bg_color.lerp(Color(0.0, 0.0, 0.0), 0.45)
	var final_color := text_color
	if not active:
		final_color = text_color.lerp(Color(0.55, 0.55, 0.62), 0.35)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", final_color)
	button.add_theme_color_override("font_pressed_color", final_color)
	button.add_theme_color_override("font_hover_color", final_color)
	button.add_theme_color_override("font_focus_color", final_color)
	button.add_theme_color_override("font_disabled_color", final_color)
	button.add_theme_font_size_override("font_size", text_size)

func _update_respec_button() -> void:
	var cost := ProfileManager.get_respec_cost()
	var crystals := ProfileManager.get_crystals()
	_respec_button.text = _translate("skills.menu.respec.button", {"cost": cost}, "Respec (" + str(cost) + ")")
	_respec_button.disabled = crystals < cost

	var unlocked := ProfileManager.get_skills_unlocked()
	if unlocked.is_empty():
		_respec_button.disabled = true

# =============================================================================
# SKILL TREE BUILDER
# =============================================================================

func _build_skill_tree() -> void:
	for child in _skill_grid.get_children():
		child.queue_free()
	_skill_nodes.clear()

	var tree_data: Dictionary = DataManager.get_skill_tree(_active_tab)
	if tree_data.is_empty():
		var empty_label := Label.new()
		empty_label.text = _translate("skills.menu.empty", {}, "Aucune competence disponible")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 19)
		_skill_grid.add_child(empty_label)
		return

	var branches_dict: Variant = tree_data.get("branches", {})
	if not (branches_dict is Dictionary):
		var invalid_label := Label.new()
		invalid_label.text = _translate("skills.menu.invalid_format", {}, "Format de donnees invalide")
		invalid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		invalid_label.add_theme_font_size_override("font_size", 19)
		_skill_grid.add_child(invalid_label)
		return

	for branch_id in (branches_dict as Dictionary).keys():
		var branch_data: Variant = (branches_dict as Dictionary)[branch_id]
		if branch_data is Dictionary:
			_build_branch(str(branch_id), branch_data as Dictionary)

func _build_branch(branch_id: String, branch_data: Dictionary) -> void:
	var block_id := str(BRANCH_TO_BLOCK.get(branch_id, branch_id))
	var block_cfg := _get_config_dict(["skills", "blocks", block_id], {})
	var branch_color := _to_color(branch_data.get("color", "#FFFFFF"), Color.WHITE)

	var branch_panel := PanelContainer.new()
	branch_panel.add_theme_stylebox_override(
		"panel",
		_make_background_style(block_cfg.get("background", "#1A1F31"), Color(0.1, 0.12, 0.19), 10, 8)
	)
	_skill_grid.add_child(branch_panel)

	var branch_vbox := VBoxContainer.new()
	branch_vbox.add_theme_constant_override("separation", 8)
	branch_panel.add_child(branch_vbox)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 8)
	branch_vbox.add_child(header)

	var title_cfg := _get_config_dict(["skills", "blocks", block_id, "title"], {})
	var header_icon := str(title_cfg.get("icon_asset", ""))
	if header_icon == "":
		header_icon = str(branch_data.get("icon", ""))
	_add_icon_texture(header, header_icon, 30, 30)

	var title_label := Label.new()
	title_label.text = _branch_name(branch_id)
	title_label.add_theme_font_size_override("font_size", int(title_cfg.get("text_size", 24)))
	title_label.add_theme_color_override("font_color", _to_color(title_cfg.get("text_color", "#FFFFFF"), branch_color))
	header.add_child(title_label)

	var levels_raw: Variant = branch_data.get("levels", [])
	if levels_raw is Array:
		# For fire_patterns branch: add "Ship Default" special entry at top
		if branch_id == "fire_patterns":
			_build_fire_default_node(branch_vbox, block_cfg, branch_color)
		for node_data in levels_raw:
			if node_data is Dictionary:
				_build_skill_node(node_data as Dictionary, branch_vbox, branch_id, branch_data, block_cfg, branch_color)

	# Perfection requirement footer (Pew Pew unlock condition).
	if _active_tab == "pew_pew" and branch_id == "stat_boosts":
		var progress := _get_pew_pew_unlock_progress()
		var unlock_req := int(progress.get("required", 15))
		var spent := int(progress.get("spent", 0))
		var req_label := Label.new()
		req_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		req_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		req_label.add_theme_font_size_override("font_size", 14)
		if spent >= unlock_req:
			req_label.add_theme_color_override("font_color", Color(0.74, 0.98, 0.74, 0.95))
		else:
			req_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.62, 0.95))
		req_label.text = _translate(
			"skills.menu.perfection.requirement",
			{"required_points": unlock_req, "spent_points": spent},
			"Perfection: " + str(spent) + "/" + str(unlock_req) + " points depenses hors Perfection."
		)
		branch_vbox.add_child(req_label)

## Builds the special "Ship Default" node at the top of the fire_patterns branch.
func _build_fire_default_node(parent: VBoxContainer, block_cfg: Dictionary, branch_color: Color) -> void:
	var equipped_id := ProfileManager.get_equipped_fire_pattern()
	var is_equipped := (equipped_id == "fire_ship_default")

	var skills_cfg := _get_config_dict(["skills", "blocks", str(BRANCH_TO_BLOCK.get("fire_patterns", "fire")), "skills"], {})
	var base_text_color := _to_color(skills_cfg.get("text_color", "#D8DCE6"), Color(0.85, 0.86, 0.9))
	var icon_size := int(skills_cfg.get("skill_icon_size", 30))
	var title_size := int(skills_cfg.get("title_text_size", 19))
	var desc_size := int(skills_cfg.get("description_text_size", 14))

	var node_panel := PanelContainer.new()
	node_panel.custom_minimum_size = Vector2(0, 74)
	parent.add_child(node_panel)

	var node_style := StyleBoxFlat.new()
	node_style.corner_radius_top_left = 8
	node_style.corner_radius_top_right = 8
	node_style.corner_radius_bottom_left = 8
	node_style.corner_radius_bottom_right = 8
	node_style.content_margin_left = 12
	node_style.content_margin_right = 12
	node_style.content_margin_top = 8
	node_style.content_margin_bottom = 8

	var block_bg := _to_color(block_cfg.get("background", "#1A1F31"), Color(0.1, 0.12, 0.19))
	if is_equipped:
		node_style.bg_color = block_bg.lerp(Color("#FFD700"), 0.15)
		node_style.border_color = Color("#FFD700")
		node_style.border_width_left = 3
		node_style.border_width_right = 3
		node_style.border_width_top = 3
		node_style.border_width_bottom = 3
	else:
		node_style.bg_color = block_bg.lerp(branch_color, 0.26)
		node_style.border_color = branch_color
		node_style.border_width_left = 2
		node_style.border_width_right = 2
		node_style.border_width_top = 2
		node_style.border_width_bottom = 2
	node_panel.add_theme_stylebox_override("panel", node_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	node_panel.add_child(hbox)

	# Use branch icon (same as other skill nodes)
	var icon_added := _add_icon_texture(hbox, "res://assets/ui/skills/branch_fire.png", icon_size, icon_size)
	if not icon_added:
		var icon_label := Label.new()
		icon_label.text = "🚀"
		icon_label.add_theme_font_size_override("font_size", icon_size)
		icon_label.add_theme_color_override("font_color", branch_color)
		hbox.add_child(icon_label)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var title_label := Label.new()
	title_label.text = _translate("skills.skill.fire_ship_default.title", {}, "Tir du vaisseau")
	title_label.add_theme_font_size_override("font_size", title_size)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	text_col.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = _translate("skills.skill.fire_ship_default.description", {}, "Utilise le tir natif du vaisseau.")
	desc_label.add_theme_font_size_override("font_size", desc_size)
	desc_label.add_theme_color_override("font_color", base_text_color.lerp(Color(0.58, 0.58, 0.62), 0.35))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_label)

	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_col)

	var equip_btn := Button.new()
	equip_btn.name = "EquipBtn_fire_ship_default"
	equip_btn.custom_minimum_size = Vector2(120, 38)
	equip_btn.add_theme_font_size_override("font_size", 14)
	if is_equipped:
		equip_btn.text = _translate("skills.menu.button.equipped", {}, "Equipe")
		equip_btn.disabled = true
		equip_btn.add_theme_color_override("font_color", Color("#FFD700"))
	else:
		equip_btn.text = _translate("skills.menu.button.equip", {}, "Equiper")
		equip_btn.pressed.connect(_on_equip_fire_pattern.bind("fire_ship_default"))
		var equip_texture := _load_texture_from_path("res://assets/ui/buttons/btn_equip.png")
		if equip_texture:
			var equip_style := StyleBoxTexture.new()
			equip_style.texture = equip_texture
			equip_btn.add_theme_stylebox_override("normal", equip_style)
			equip_btn.add_theme_stylebox_override("hover", equip_style)
			equip_btn.add_theme_stylebox_override("pressed", equip_style)
	right_col.add_child(equip_btn)

func _build_skill_node(
	node_data: Dictionary,
	parent: VBoxContainer,
	branch_id: String,
	branch_data: Dictionary,
	block_cfg: Dictionary,
	branch_color: Color
) -> void:
	var skill_id := str(node_data.get("id", ""))
	var skill_title := _translate(
		"skills.skill." + skill_id + ".title",
		{},
		str(node_data.get("title", skill_id))
	)
	var skill_desc := _translate(
		"skills.skill." + skill_id + ".description",
		{},
		str(node_data.get("description", ""))
	)
	var max_rank := int(node_data.get("max_rank", 1))
	var current_rank := ProfileManager.get_skill_rank(skill_id)
	var is_unlocked := current_rank > 0
	var can_unlock := SkillManager.can_unlock_skill(skill_id)

	var skills_cfg := _get_config_dict(["skills", "blocks", str(BRANCH_TO_BLOCK.get(branch_id, branch_id)), "skills"], {})
	var base_text_color := _to_color(skills_cfg.get("text_color", "#D8DCE6"), Color(0.85, 0.86, 0.9))
	var icon_size := int(skills_cfg.get("skill_icon_size", 30))
	var title_size := int(skills_cfg.get("title_text_size", 19))
	var desc_size := int(skills_cfg.get("description_text_size", 14))

	var node_panel := PanelContainer.new()
	node_panel.custom_minimum_size = Vector2(0, 74)
	parent.add_child(node_panel)

	var node_style := StyleBoxFlat.new()
	node_style.corner_radius_top_left = 8
	node_style.corner_radius_top_right = 8
	node_style.corner_radius_bottom_left = 8
	node_style.corner_radius_bottom_right = 8
	node_style.content_margin_left = 12
	node_style.content_margin_right = 12
	node_style.content_margin_top = 8
	node_style.content_margin_bottom = 8

	var block_bg_color := _to_color(block_cfg.get("background", "#1A1F31"), Color(0.1, 0.12, 0.19))
	if is_unlocked:
		node_style.bg_color = block_bg_color.lerp(branch_color, 0.26)
		node_style.border_color = branch_color
		node_style.border_width_left = 2
		node_style.border_width_right = 2
		node_style.border_width_top = 2
		node_style.border_width_bottom = 2
	elif can_unlock:
		node_style.bg_color = block_bg_color.lerp(Color(0.18, 0.2, 0.24), 0.35)
		node_style.border_color = branch_color.lerp(Color.WHITE, 0.35)
		node_style.border_width_left = 1
		node_style.border_width_right = 1
		node_style.border_width_top = 1
		node_style.border_width_bottom = 1
	else:
		node_style.bg_color = block_bg_color.lerp(Color(0, 0, 0), 0.45)
		node_style.border_color = Color(0.3, 0.3, 0.35, 0.5)
		node_style.border_width_left = 1
		node_style.border_width_right = 1
		node_style.border_width_top = 1
		node_style.border_width_bottom = 1

	node_panel.add_theme_stylebox_override("panel", node_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	node_panel.add_child(hbox)

	var icon_added := false
	if not can_unlock and not is_unlocked:
		var locked_cfg := _get_config_dict(["skills", "blocks", str(BRANCH_TO_BLOCK.get(branch_id, branch_id)), "locked_icon"], {})
		var lock_asset := str(locked_cfg.get("asset", ""))
		var lock_w := int(locked_cfg.get("width", icon_size))
		var lock_h := int(locked_cfg.get("height", icon_size))
		icon_added = _add_icon_texture(hbox, lock_asset, lock_w, lock_h)

	if not icon_added:
		var skill_icon_asset := str(node_data.get("icon", ""))
		if skill_icon_asset == "":
			skill_icon_asset = str(branch_data.get("icon", ""))
		icon_added = _add_icon_texture(hbox, skill_icon_asset, icon_size, icon_size)

	if not icon_added:
		var icon_label := Label.new()
		icon_label.text = "•"
		icon_label.add_theme_font_size_override("font_size", icon_size)
		icon_label.add_theme_color_override("font_color", branch_color)
		hbox.add_child(icon_label)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var title_label := Label.new()
	title_label.text = skill_title
	title_label.add_theme_font_size_override("font_size", title_size)
	if is_unlocked:
		title_label.add_theme_color_override("font_color", Color.WHITE)
	elif can_unlock:
		title_label.add_theme_color_override("font_color", base_text_color)
	else:
		title_label.add_theme_color_override("font_color", base_text_color.lerp(Color(0.45, 0.45, 0.5), 0.45))
	text_col.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = skill_desc
	desc_label.add_theme_font_size_override("font_size", desc_size)
	desc_label.add_theme_color_override("font_color", base_text_color.lerp(Color(0.58, 0.58, 0.62), 0.35))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_label)

	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_col)

	if max_rank > 1:
		var rank_label := Label.new()
		rank_label.text = str(current_rank) + "/" + str(max_rank)
		rank_label.add_theme_font_size_override("font_size", 15)
		rank_label.add_theme_color_override("font_color", branch_color)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_col.add_child(rank_label)

	var unlock_btn := Button.new()
	unlock_btn.name = "UnlockBtn_" + skill_id
	unlock_btn.custom_minimum_size = Vector2(120, 38)
	unlock_btn.add_theme_font_size_override("font_size", 14)
	var button_state := "locked"

	if is_unlocked and (max_rank <= 1 or current_rank >= max_rank):
		button_state = "acquired"
		unlock_btn.text = _translate("skills.menu.button.acquired", {}, "Acquis")
		unlock_btn.disabled = true
	elif can_unlock:
		button_state = "unlocked"
		unlock_btn.text = _translate("skills.menu.button.activate", {}, "Activer")
		unlock_btn.pressed.connect(_on_skill_pressed.bind(skill_id))
	else:
		button_state = "locked"
		unlock_btn.text = _translate("skills.menu.button.locked", {}, "Verrouille")
		unlock_btn.disabled = true

	if _apply_skill_state_button_asset(unlock_btn, button_state):
		unlock_btn.text = ""

	hbox.add_child(unlock_btn)
	_skill_nodes[skill_id] = unlock_btn

	# --- Fire Pattern: Equip Button ---
	var skill_type := str(node_data.get("type", ""))
	if skill_type == "fire_pattern" and is_unlocked:
		var equipped_id := ProfileManager.get_equipped_fire_pattern()
		var is_equipped := (equipped_id == skill_id)
		var equip_btn := Button.new()
		equip_btn.name = "EquipBtn_" + skill_id
		equip_btn.custom_minimum_size = Vector2(120, 38)
		equip_btn.add_theme_font_size_override("font_size", 14)
		if is_equipped:
			equip_btn.text = _translate("skills.menu.button.equipped", {}, "Equipe")
			equip_btn.disabled = true
			equip_btn.add_theme_color_override("font_color", Color("#FFD700"))
		else:
			equip_btn.text = _translate("skills.menu.button.equip", {}, "Equiper")
			equip_btn.pressed.connect(_on_equip_fire_pattern.bind(skill_id))
		# Try to apply equip button asset
		var equip_texture := _load_texture_from_path("res://assets/ui/buttons/btn_equip.png")
		if equip_texture and not is_equipped:
			var equip_style := StyleBoxTexture.new()
			equip_style.texture = equip_texture
			equip_btn.add_theme_stylebox_override("normal", equip_style)
			equip_btn.add_theme_stylebox_override("hover", equip_style)
			equip_btn.add_theme_stylebox_override("pressed", equip_style)
		hbox.add_child(equip_btn)
		# Golden border for equipped skill
		if is_equipped:
			node_style.border_color = Color("#FFD700")
			node_style.border_width_left = 3
			node_style.border_width_right = 3
			node_style.border_width_top = 3
			node_style.border_width_bottom = 3

func _add_icon_texture(parent: Control, asset_path: String, width: int, height: int) -> bool:
	var texture := _load_texture_from_path(asset_path)
	if texture == null:
		return false
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(max(width, 1), max(height, 1))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(icon)
	return true

func _apply_skill_state_button_asset(button: Button, state: String) -> bool:
	var state_key := state
	# Reuse unlocked visuals for acquired state if no dedicated variant exists.
	if state_key == "acquired":
		state_key = "unlocked"
	var cfg := _get_config_dict(["skills", "state_buttons", state_key], {})
	var asset_path := str(cfg.get("asset", ""))
	var texture := _load_texture_from_path(asset_path)
	if texture == null:
		return false

	var width := int(cfg.get("width", int(button.custom_minimum_size.x)))
	var height := int(cfg.get("height", int(button.custom_minimum_size.y)))
	button.custom_minimum_size = Vector2(maxi(1, width), maxi(1, height))
	button.add_theme_font_size_override("font_size", 1)
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))

	var style := StyleBoxTexture.new()
	style.texture = texture
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_stylebox_override("disabled", style)
	return true

# =============================================================================
# EVENTS
# =============================================================================

func _on_tab_pressed(tab_id: String) -> void:
	_active_tab = tab_id
	_refresh_display()

func _on_skill_pressed(skill_id: String) -> void:
	var success := ProfileManager.spend_skill_point(skill_id)
	if success:
		AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav", 0.0)
		_refresh_display()
	else:
		AudioManager.play_sfx("res://assets/sfx/ui_deny.wav", 0.0)

func _on_equip_fire_pattern(pattern_id: String) -> void:
	var success := ProfileManager.set_equipped_fire_pattern(pattern_id)
	if success:
		AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav", 0.0)
		_refresh_display()
	else:
		AudioManager.play_sfx("res://assets/sfx/ui_deny.wav", 0.0)

func _on_respec_pressed() -> void:
	var cost := ProfileManager.get_respec_cost()
	var crystals := ProfileManager.get_crystals()

	if crystals < cost:
		_info_label.text = _translate(
			"skills.menu.not_enough_crystals",
			{"cost": cost},
			"Pas assez de cristaux (" + str(cost) + ")"
		)
		return

	_show_respec_confirm(cost)

func _show_respec_confirm(cost: int) -> void:
	if _popup:
		_popup.queue_free()

	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_popup)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	_popup.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 220)
	panel.position = Vector2(-210, -110)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.18)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = _translate(
		"skills.menu.respec.confirm",
		{"cost": cost},
		"Reinitialiser toutes les competences ? Cout: " + str(cost)
	)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 18)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var confirm := Button.new()
	confirm.text = _translate("skills.menu.respec.confirm_button", {}, "Confirmer")
	confirm.custom_minimum_size = Vector2(160, 45)
	confirm.add_theme_font_size_override("font_size", 16)
	confirm.pressed.connect(func():
		ProfileManager.respec_skills()
		_popup.queue_free()
		_popup = null
		_refresh_display()
	)
	btn_row.add_child(confirm)

	var cancel := Button.new()
	cancel.text = _translate("skills.menu.respec.cancel_button", {}, "Annuler")
	cancel.custom_minimum_size = Vector2(160, 45)
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.pressed.connect(func():
		_popup.queue_free()
		_popup = null
	)
	btn_row.add_child(cancel)

func _on_back_pressed() -> void:
	back_requested.emit()
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

# =============================================================================
# CONFIG & I18N HELPERS
# =============================================================================

func _tab_label(tab_id: String) -> String:
	match tab_id:
		"magic":
			return _translate("skills.tab.magic", {}, "MAGIE")
		"utility":
			return _translate("skills.tab.utility", {}, "UTILITAIRE")
		"pew_pew":
			return _translate("skills.tab.pew_pew", {}, "PEW PEW")
		_:
			return tab_id

func _branch_name(branch_id: String) -> String:
	return _translate("skills.branch." + branch_id, {}, branch_id.capitalize())

func _translate(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var translated := key
	if LocaleManager and LocaleManager.has_method("translate"):
		translated = LocaleManager.translate(key, params)
	if translated == key and fallback != "":
		return fallback
	return translated

func _get_config_value(path: Array, default_value: Variant) -> Variant:
	var current: Variant = _skills_menu_cfg
	for part in path:
		if not (current is Dictionary):
			return default_value
		current = (current as Dictionary).get(str(part), null)
		if current == null:
			return default_value
	return current

func _get_config_dict(path: Array, default_value: Dictionary = {}) -> Dictionary:
	var value: Variant = _get_config_value(path, default_value)
	if value is Dictionary:
		return value as Dictionary
	return default_value

func _to_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var as_string := str(value).strip_edges()
		if _looks_like_asset_path(as_string):
			return fallback
		return Color.from_string(as_string, fallback)
	if value is Dictionary:
		var as_dict := value as Dictionary
		var color_string := str(as_dict.get("color", ""))
		if color_string != "":
			return Color.from_string(color_string, fallback)
	return fallback

func _make_background_style(bg_value: Variant, fallback_color: Color, radius: int, content_margin: int) -> StyleBox:
	var texture := _background_texture(bg_value)
	if texture != null:
		var tex_style := StyleBoxTexture.new()
		tex_style.texture = texture
		return tex_style

	var flat := StyleBoxFlat.new()
	flat.bg_color = _to_color(bg_value, fallback_color)
	flat.corner_radius_top_left = radius
	flat.corner_radius_top_right = radius
	flat.corner_radius_bottom_left = radius
	flat.corner_radius_bottom_right = radius
	if content_margin > 0:
		flat.content_margin_left = content_margin
		flat.content_margin_right = content_margin
		flat.content_margin_top = content_margin
		flat.content_margin_bottom = content_margin
	return flat

func _background_texture(bg_value: Variant) -> Texture2D:
	if bg_value is String:
		return _load_texture_from_path(str(bg_value))
	if bg_value is Dictionary:
		var bg_dict := bg_value as Dictionary
		return _load_texture_from_path(str(bg_dict.get("asset", "")))
	return null

func _load_texture_from_path(raw_path: String) -> Texture2D:
	var path := _normalize_resource_path(raw_path)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	if resource is Texture2D:
		return resource
	return null

func _normalize_resource_path(raw_path: String) -> String:
	var path := raw_path.strip_edges()
	if path == "":
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path.begins_with("./"):
		path = path.trim_prefix("./")
	if path.begins_with("/"):
		path = path.trim_prefix("/")
	return "res://" + path

func _looks_like_asset_path(value: String) -> bool:
	var lower := value.to_lower()
	if lower.begins_with("res://") or lower.begins_with("user://"):
		return true
	return (
		lower.ends_with(".png")
		or lower.ends_with(".jpg")
		or lower.ends_with(".jpeg")
		or lower.ends_with(".webp")
		or lower.ends_with(".svg")
		or lower.find("/") >= 0
		or lower.find("\\") >= 0
	)
