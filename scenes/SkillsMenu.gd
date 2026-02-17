extends Control

## SkillsMenu — Écran de l'arbre de compétences.
## 3 onglets: Magic (exclusif), Utility (passif), Pew Pew (Paragon).
## Scrollable, avec popup de détails.

signal back_requested

# =============================================================================
# REFERENCES
# =============================================================================

var _header: VBoxContainer
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

var _active_tab: String = "magic"
const TAB_IDS: Array[String] = ["magic", "utility", "pew_pew"]
var _skill_nodes: Dictionary = {} # skill_id -> Button
var _popup: Control = null

# Tab colors
const TAB_COLORS := {
	"magic": Color(0.3, 0.5, 1.0),
	"utility": Color(0.3, 0.9, 0.4),
	"pew_pew": Color(1.0, 0.6, 0.2)
}

const TAB_LABELS := {
	"magic": "🔮 Magie",
	"utility": "🔧 Utilitaire",
	"pew_pew": "💥 Pew Pew"
}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_ui()
	_refresh_display()

func _build_ui() -> void:
	# Root layout
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)
	
	# --- Header ---
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_header)
	
	# Title row with back button on the left (like OptionsMenu / WorldSelect)
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	_header.add_child(title_row)
	
	_back_button = TextureButton.new()
	_back_button.custom_minimum_size = Vector2(50, 50)
	_back_button.ignore_texture_size = true
	_back_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var _game_cfg := {}
	var _gcf := FileAccess.open("res://data/game.json", FileAccess.READ)
	if _gcf:
		var _gj := JSON.new()
		if _gj.parse(_gcf.get_as_text()) == OK:
			_game_cfg = _gj.data
		_gcf.close()
	# Use ui_icons.back_button like OptionsMenu / WorldSelect
	var ui_icons: Dictionary = _game_cfg.get("ui_icons", {})
	var back_asset := str(ui_icons.get("back_button", ""))
	if back_asset != "" and ResourceLoader.exists(back_asset):
		_back_button.texture_normal = load(back_asset)
	_back_button.pressed.connect(_on_back_pressed)
	title_row.add_child(_back_button)
	
	var title := Label.new()
	title.text = "COMPÉTENCES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(title)
	
	# Level + Skill Points bar
	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 30)
	_header.add_child(info_row)
	
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 18)
	_level_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	info_row.add_child(_level_label)
	
	_skill_points_label = Label.new()
	_skill_points_label.add_theme_font_size_override("font_size", 18)
	_skill_points_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	info_row.add_child(_skill_points_label)
	
	# XP Progress bar
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XPBar"
	_xp_bar.custom_minimum_size = Vector2(500, 28)
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
	
	# XP text label centered on top of the bar
	var xp_text := Label.new()
	xp_text.name = "XPText"
	xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_text.add_theme_font_size_override("font_size", 13)
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
	main_vbox.add_child(_tab_container)
	
	for tab_id in TAB_IDS:
		var btn := Button.new()
		btn.name = "Tab_" + tab_id
		btn.text = TAB_LABELS[tab_id]
		btn.custom_minimum_size = Vector2(210, 45)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		_tab_container.add_child(btn)
	
	# --- Scroll Content ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(_scroll_container)
	
	_skill_grid = VBoxContainer.new()
	_skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_grid.add_theme_constant_override("separation", 12)
	_scroll_container.add_child(_skill_grid)
	
	# --- Info Label ---
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_info_label)
	
	# --- Footer ---
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override("separation", 16)
	main_vbox.add_child(_footer)
	
	_respec_button = Button.new()
	_respec_button.text = "🔄 Respec"
	_respec_button.custom_minimum_size = Vector2(200, 50)
	_respec_button.add_theme_font_size_override("font_size", 18)
	_respec_button.pressed.connect(_on_respec_pressed)
	_footer.add_child(_respec_button)

# =============================================================================
# DISPLAY
# =============================================================================

func _refresh_display() -> void:
	_update_header()
	_update_tabs()
	_build_skill_tree()
	_update_respec_button()

func _update_header() -> void:
	var level := ProfileManager.get_player_level()
	var xp := ProfileManager.get_player_xp()
	var sp := ProfileManager.get_skill_points()
	var xp_for_next := ProfileManager.get_xp_for_level(level + 1)
	var xp_for_current := ProfileManager.get_xp_for_level(level)
	
	_level_label.text = "Niveau " + str(level)
	_skill_points_label.text = "⭐ " + str(sp) + " pts"
	
	# XP bar
	if _xp_bar:
		var range_xp := float(xp_for_next - xp_for_current)
		var progress_xp := float(xp - xp_for_current)
		if range_xp > 0:
			_xp_bar.max_value = range_xp
			_xp_bar.value = progress_xp
		else:
			_xp_bar.max_value = 1
			_xp_bar.value = 1
		
		# Update fill color based on percentage
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
		
		# Update text overlay
		var xp_text: Label = _xp_bar.get_node_or_null("XPText")
		if xp_text:
			xp_text.text = str(int(progress_xp)) + " / " + str(int(range_xp)) + "  (" + str(int(pct * 100)) + "%)"
	
	# Info text based on tab
	match _active_tab:
		"magic":
			var branch := ProfileManager.get_active_magic_branch()
			if branch != "":
				_info_label.text = "Branche active: " + branch.capitalize() + " (exclusif)"
			else:
				_info_label.text = "Choisissez une branche magique (Frozen, Poison ou Void)"
		"utility":
			_info_label.text = "Compétences passives — toujours actives"
		"pew_pew":
			if ProfileManager.get_player_level() < 15:
				_info_label.text = "Débloqué au niveau 15 (actuel: " + str(ProfileManager.get_player_level()) + ")"
			else:
				_info_label.text = "Paragon — Points répétables pour booster vos stats"

func _update_tabs() -> void:
	for tab_id in TAB_IDS:
		var btn: Button = _tab_container.get_node_or_null("Tab_" + tab_id)
		if btn:
			if tab_id == _active_tab:
				var style := StyleBoxFlat.new()
				style.bg_color = TAB_COLORS[tab_id]
				style.corner_radius_top_left = 6
				style.corner_radius_top_right = 6
				style.corner_radius_bottom_left = 6
				style.corner_radius_bottom_right = 6
				btn.add_theme_stylebox_override("normal", style)
				btn.add_theme_color_override("font_color", Color.WHITE)
			else:
				btn.remove_theme_stylebox_override("normal")
				btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))

func _update_respec_button() -> void:
	var cost := ProfileManager.get_respec_cost()
	var crystals := ProfileManager.get_crystals()
	_respec_button.text = "🔄 Respec (💎 " + str(cost) + ")"
	_respec_button.disabled = crystals < cost
	
	# Also check if there's anything to respec
	var unlocked := ProfileManager.get_skills_unlocked()
	if unlocked.is_empty():
		_respec_button.disabled = true

# =============================================================================
# SKILL TREE BUILDER
# =============================================================================

func _build_skill_tree() -> void:
	# Clear
	for child in _skill_grid.get_children():
		child.queue_free()
	_skill_nodes.clear()
	
	var tree_data: Dictionary = DataManager.get_skill_tree(_active_tab)
	if tree_data.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Aucune compétence disponible"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_skill_grid.add_child(empty_label)
		return
	
	# branches is a Dictionary keyed by branch_id
	var branches_dict: Variant = tree_data.get("branches", {})
	if not branches_dict is Dictionary:
		var empty_label := Label.new()
		empty_label.text = "Format de données invalide"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_skill_grid.add_child(empty_label)
		return
	
	for branch_id in (branches_dict as Dictionary).keys():
		var branch_data: Dictionary = (branches_dict as Dictionary)[branch_id]
		if not branch_data is Dictionary:
			continue
		_build_branch(branch_id, branch_data as Dictionary)

func _build_branch(branch_id: String, branch_data: Dictionary) -> void:
	var branch_name: String = str(branch_data.get("name", branch_id.capitalize()))
	var branch_color_str: String = str(branch_data.get("color", "#FFFFFF"))
	var branch_color := Color(branch_color_str)
	
	# Branch header with placeholder icon
	var branch_header := HBoxContainer.new()
	branch_header.alignment = BoxContainer.ALIGNMENT_CENTER
	_skill_grid.add_child(branch_header)
	
	var separator_left := HSeparator.new()
	separator_left.custom_minimum_size = Vector2(40, 2)
	branch_header.add_child(separator_left)
	
	# Placeholder icon based on branch type
	var branch_icon := Label.new()
	match branch_id:
		"frozen": branch_icon.text = "❄️"
		"poison": branch_icon.text = "☠️"
		"void": branch_icon.text = "🌀"
		"loot": branch_icon.text = "💰"
		"powers": branch_icon.text = "🔋"
		"stat_boosts": branch_icon.text = "📈"
		_: branch_icon.text = "◆"
	branch_icon.add_theme_font_size_override("font_size", 22)
	branch_header.add_child(branch_icon)
	
	var branch_label := Label.new()
	branch_label.text = " " + branch_name + " "
	branch_label.add_theme_font_size_override("font_size", 20)
	branch_label.add_theme_color_override("font_color", branch_color)
	branch_header.add_child(branch_label)
	
	var separator_right := HSeparator.new()
	separator_right.custom_minimum_size = Vector2(40, 2)
	branch_header.add_child(separator_right)
	
	# Skill nodes are stored under "levels" in the JSON
	var levels: Array = []
	var raw_levels: Variant = branch_data.get("levels", [])
	if raw_levels is Array:
		levels = raw_levels
	
	for node_data in levels:
		if not node_data is Dictionary:
			continue
		_build_skill_node(node_data as Dictionary, branch_color, branch_id)

func _build_skill_node(node_data: Dictionary, branch_color: Color, branch_id: String = "") -> void:
	var skill_id: String = str(node_data.get("id", ""))
	var skill_title: String = str(node_data.get("title", skill_id))
	var skill_desc: String = str(node_data.get("description", ""))
	var skill_cost: int = int(node_data.get("cost", 1))
	var max_rank: int = int(node_data.get("max_rank", 1))
	var current_rank: int = ProfileManager.get_skill_rank(skill_id)
	var is_unlocked := current_rank > 0
	var can_unlock := SkillManager.can_unlock_skill(skill_id)
	
	# Container
	var node_panel := PanelContainer.new()
	node_panel.custom_minimum_size = Vector2(0, 60)
	_skill_grid.add_child(node_panel)
	
	var panel_style := StyleBoxFlat.new()
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	
	if is_unlocked:
		panel_style.bg_color = Color(branch_color.r, branch_color.g, branch_color.b, 0.25)
		panel_style.border_color = branch_color
		panel_style.border_width_left = 2
		panel_style.border_width_right = 2
		panel_style.border_width_top = 2
		panel_style.border_width_bottom = 2
	elif can_unlock:
		panel_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
		panel_style.border_color = Color(branch_color.r, branch_color.g, branch_color.b, 0.5)
		panel_style.border_width_left = 1
		panel_style.border_width_right = 1
		panel_style.border_width_top = 1
		panel_style.border_width_bottom = 1
	else:
		panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.6)
		panel_style.border_color = Color(0.3, 0.3, 0.35, 0.5)
		panel_style.border_width_left = 1
		panel_style.border_width_right = 1
		panel_style.border_width_top = 1
		panel_style.border_width_bottom = 1
	
	node_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Content row
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	node_panel.add_child(hbox)
	
	# Icon — placeholder based on type + branch
	var icon_label := Label.new()
	var skill_type: String = str(node_data.get("type", ""))
	match skill_type:
		"gameplay_modifier":
			match branch_id:
				"frozen": icon_label.text = "❄️"
				"poison": icon_label.text = "🧪"
				"void": icon_label.text = "🌀"
				"powers": icon_label.text = "⚡"
				_: icon_label.text = "⚡"
		"loot_modifier": icon_label.text = "💎"
		"stat_modifier": icon_label.text = "⬆️"
		_: icon_label.text = "●"
	icon_label.add_theme_font_size_override("font_size", 22)
	hbox.add_child(icon_label)
	
	# Text column
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)
	
	var title_label := Label.new()
	title_label.text = skill_title
	title_label.add_theme_font_size_override("font_size", 16)
	if is_unlocked:
		title_label.add_theme_color_override("font_color", Color.WHITE)
	elif can_unlock:
		title_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	else:
		title_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	text_col.add_child(title_label)
	
	var desc_label := Label.new()
	desc_label.text = skill_desc
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_label)
	
	# Rank / Cost
	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_col)
	
	if max_rank > 1:
		var rank_label := Label.new()
		rank_label.text = str(current_rank) + "/" + str(max_rank)
		rank_label.add_theme_font_size_override("font_size", 14)
		rank_label.add_theme_color_override("font_color", branch_color)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_col.add_child(rank_label)
	
	if not is_unlocked or (max_rank > 1 and current_rank < max_rank):
		var cost_label := Label.new()
		cost_label.text = "⭐" + str(skill_cost)
		cost_label.add_theme_font_size_override("font_size", 13)
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_col.add_child(cost_label)
	elif is_unlocked:
		var check := Label.new()
		check.text = "✅"
		check.add_theme_font_size_override("font_size", 18)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_col.add_child(check)
	
	# Unlock button
	var unlock_btn := Button.new()
	unlock_btn.name = "UnlockBtn_" + skill_id
	unlock_btn.custom_minimum_size = Vector2(70, 36)
	unlock_btn.add_theme_font_size_override("font_size", 13)
	
	if is_unlocked and (max_rank <= 1 or current_rank >= max_rank):
		unlock_btn.text = "Acquis"
		unlock_btn.disabled = true
	elif can_unlock and ProfileManager.get_skill_points() >= skill_cost:
		unlock_btn.text = "Activer"
		unlock_btn.pressed.connect(_on_skill_pressed.bind(skill_id))
	else:
		unlock_btn.text = "🔒"
		unlock_btn.disabled = true
	
	hbox.add_child(unlock_btn)
	_skill_nodes[skill_id] = unlock_btn

# =============================================================================
# EVENTS
# =============================================================================

func _on_tab_pressed(tab_id: String) -> void:
	_active_tab = tab_id
	_refresh_display()

func _on_skill_pressed(skill_id: String) -> void:
	var success := ProfileManager.spend_skill_point(skill_id)
	if success:
		# SFX
		AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav", 0.0)
		_refresh_display()
	else:
		# Error feedback
		AudioManager.play_sfx("res://assets/sfx/ui_deny.wav", 0.0)

func _on_respec_pressed() -> void:
	var cost := ProfileManager.get_respec_cost()
	var crystals := ProfileManager.get_crystals()
	
	if crystals < cost:
		_info_label.text = "Pas assez de cristaux ! (💎 " + str(cost) + " requis)"
		return
	
	# Show confirmation popup
	_show_respec_confirm(cost)

func _show_respec_confirm(cost: int) -> void:
	if _popup:
		_popup.queue_free()
	
	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_popup)
	
	# Dim background
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	_popup.add_child(dim)
	
	# Popup panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 200)
	panel.position = Vector2(-200, -100)
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
	msg.text = "Réinitialiser toutes les compétences ?\nCoût: 💎 " + str(cost)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 18)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg)
	
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)
	
	var confirm := Button.new()
	confirm.text = "Confirmer"
	confirm.custom_minimum_size = Vector2(140, 45)
	confirm.add_theme_font_size_override("font_size", 16)
	confirm.pressed.connect(func():
		ProfileManager.respec_skills()
		_popup.queue_free()
		_popup = null
		_refresh_display()
	)
	btn_row.add_child(confirm)
	
	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.custom_minimum_size = Vector2(140, 45)
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
