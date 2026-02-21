extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## LootResultScreen — Écran de décision après avoir battu un boss et obtenu un item.
## Permet de Garder, Équiper ou Désassembler (Recycler) l'objet.

signal finished
signal restart_requested
signal exit_requested
signal menu_requested

var _item: Dictionary = {}
var _session_loot: Array = []
var _current_page: int = 0
var _items_per_page: int = 3
var _game_config: Dictionary = {}
var _is_victory: bool = true
var _boss_loot_resolved: bool = false
var _secondary_nav_label: String = "Sélection niveau"
var _menu_nav_label: String = "Menu"

@onready var item_name_label: Label = %ItemNameLabel
@onready var item_type_label: Label = %ItemTypeLabel
@onready var stats_container: VBoxContainer = %StatsContainer
@onready var background_rect: TextureRect = %Background
@onready var equip_btn: Button = %EquipButton
@onready var disassemble_btn: Button = %DisassembleButton
@onready var panel_container: PanelContainer = $CenterContainer/PanelContainer

# Navigation Buttons
@onready var restart_btn: Button = %RestartButton
@onready var exit_btn: Button = %ExitButton
@onready var menu_btn: Button = %MenuButton

# Inventory Nodes
@onready var items_grid: HBoxContainer = %ItemsGrid
@onready var prev_btn: Button = %PrevButton
@onready var next_btn: Button = %NextButton
@onready var session_container: VBoxContainer = %SessionLootContainer
@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Title
@onready var top_separator: HSeparator = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HSeparator
@onready var item_stats_panel: Panel = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Panel
@onready var item_spacer: Control = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Spacer
@onready var boss_buttons_container: HBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonsContainer
@onready var mid_separator: HSeparator = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HSeparator2

func setup(item: Dictionary, session_loot: Array = [], is_victory: bool = true) -> void:
	_item = item
	_session_loot = session_loot
	_is_victory = is_victory
	_boss_loot_resolved = (not _is_victory) or _item.is_empty()
	_load_assets()
	_sort_session_loot()
	
	if title_label:
		title_label.text = "NIVEAU RÉUSSI !" if is_victory else "ÉCHEC DU NIVEAU"
		
		# Ensure white text as requested
		var pop_cfg = _game_config.get("popups", {})
		var title_col = str(pop_cfg.get("background", {}).get("text_color", "#FFFFFF"))
		title_label.add_theme_color_override("font_color", Color.html(title_col))
	
	_update_ui()
	_update_inventory_ui()
	_apply_navigation_labels()
	
	# Connect pagination buttons
	if not prev_btn.pressed.is_connected(_on_prev_page):
		prev_btn.pressed.connect(_on_prev_page)
	if not next_btn.pressed.is_connected(_on_next_page):
		next_btn.pressed.connect(_on_next_page)

func _sort_session_loot() -> void:
	var priority = {
		"unique": 5,
		"legendary": 4,
		"epic": 3,
		"rare": 2,
		"uncommon": 1,
		"common": 0
	}
	_session_loot.sort_custom(func(a, b):
		return priority.get(a.get("rarity", "common"), 0) > priority.get(b.get("rarity", "common"), 0)
	)

func _load_assets() -> void:
	# Charger game.json pour les assets
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_game_config = json.data
	
	var reward_config: Dictionary = _game_config.get("reward_screen", {})
	var popup_config: Dictionary = _game_config.get("popups", {})
	
	# Background (Main Overlay)
	var bg_path: String = str(reward_config.get("background", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background_rect.texture = load(bg_path)
		%FallbackBg.visible = false
	else:
		%FallbackBg.visible = true
	
	# Popup Frame (PanelContainer)
	var popup_bg_cfg: Dictionary = popup_config.get("background", {}) if popup_config.get("background") is Dictionary else {}
	var popup_bg: String = str(popup_bg_cfg.get("asset", ""))
	var m = int(popup_config.get("margin", 30))
	var style := UIStyle.build_texture_stylebox(popup_bg, popup_bg_cfg, m)
	if style:
		panel_container.add_theme_stylebox_override("panel", style)
	
	# Title Styling
	if title_label:
		var title_cfg = popup_config.get("background", {})
		title_label.add_theme_font_size_override("font_size", int(title_cfg.get("font_size", 32)))
		title_label.add_theme_color_override("font_color", Color.html(str(title_cfg.get("text_color", "#FFFFFF"))))

	# Buttons
	var pop_btn_cfg = popup_config.get("button", {})
	_apply_button_style(equip_btn, pop_btn_cfg)
	_apply_button_style(disassemble_btn, pop_btn_cfg)
	_apply_button_style(restart_btn, pop_btn_cfg)
	_apply_button_style(exit_btn, pop_btn_cfg)
	_apply_button_style(menu_btn, pop_btn_cfg)
	
	var equip_path: String = str(reward_config.get("button_equip", ""))
	if equip_path != "" and ResourceLoader.exists(equip_path):
		equip_btn.text = ""
		equip_btn.icon = load(equip_path)
		equip_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var destroy_path: String = str(reward_config.get("button_destroy", ""))
	if destroy_path != "" and ResourceLoader.exists(destroy_path):
		disassemble_btn.text = ""
		disassemble_btn.icon = load(destroy_path)
		disassemble_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _apply_button_style(btn: Button, cfg: Dictionary) -> void:
	if not btn or cfg.is_empty(): return
	
	var asset = str(cfg.get("asset", ""))
	var style := UIStyle.build_texture_stylebox(asset, cfg, 15)
	if style:
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("focus", style)
	
	# Use text_color (now #FFFFFF in game.json)
	var col = str(cfg.get("text_color", "#FFFFFF"))
	btn.add_theme_color_override("font_color", Color.html(col))
	btn.add_theme_color_override("font_hover_color", Color.html(col))
	btn.add_theme_color_override("font_pressed_color", Color.html(col))
	btn.add_theme_color_override("font_focus_color", Color.html(col))
	
	btn.add_theme_font_size_override("font_size", int(cfg.get("font_size", 18)))
	btn.add_theme_constant_override("letter_spacing", int(cfg.get("letter_spacing", 0)))

func _update_ui() -> void:
	# Clear previous stats
	if stats_container:
		for child in stats_container.get_children():
			child.queue_free()
	
	var has_boss_loot := _is_victory and not _item.is_empty()
	_set_boss_loot_section_visible(has_boss_loot)
		
	if not has_boss_loot:
		item_name_label.text = "Session Terminée"
		item_type_label.visible = false
		return
	
	item_type_label.visible = true
	
	var rarity: String = str(_item.get("rarity", "common"))
	var slot_id: String = str(_item.get("slot", "unknown"))
	
	# Set Slot Type as Title (eg. "Shield")
	var slot_data = DataManager.get_slot(slot_id)
	var slot_pretty_name = str(slot_data.get("name", slot_id)).capitalize()
	item_name_label.text = slot_pretty_name
	
	# Rarity Text + Color
	var rarity_key := "rarity_" + rarity
	var rarity_text := LocaleManager.translate(rarity_key)
	if rarity_text == rarity_key:
		rarity_text = rarity.capitalize()
	item_type_label.text = rarity_text.to_upper()
	var rarity_color := _get_rarity_color_from_config(rarity)
	item_name_label.add_theme_color_override("font_color", rarity_color)
	item_type_label.add_theme_color_override("font_color", rarity_color)
	
	# Stats with Icons
	var stats = _item.get("stats", {})
	if stats is Dictionary:
		var s_dict = stats as Dictionary
		for key in s_dict.keys():
			_add_stat_row(key, s_dict[key])
	
	# Recycle value update
	var val = ProfileManager.calculate_recycle_value(_item)
	if disassemble_btn.icon == null:
		disassemble_btn.text = "♻️ Recycler (+" + str(val) + " 💎)"

func _set_boss_loot_section_visible(visible_state: bool) -> void:
	if top_separator:
		top_separator.visible = visible_state
	if item_name_label:
		item_name_label.visible = visible_state
	if item_type_label:
		item_type_label.visible = visible_state
	if item_stats_panel:
		item_stats_panel.visible = visible_state
	if item_spacer:
		item_spacer.visible = visible_state
	if boss_buttons_container:
		boss_buttons_container.visible = visible_state
	if mid_separator:
		mid_separator.visible = visible_state
	if equip_btn:
		equip_btn.visible = visible_state
	if disassemble_btn:
		disassemble_btn.visible = visible_state

func _add_stat_row(stat_key: String, value: Variant) -> void:
	var stat_icons = {
		"power": "res://assets/ui/icons/power.png",
		"level": "res://assets/ui/icons/trophy.png",
		"crystals": "res://assets/ui/icons/crystal.png",
		"hp": "res://assets/ui/icons/heart.png",
		"max_hp": "res://assets/ui/icons/heart.png",
		"speed": "res://assets/ui/icons/speed.png",
		"move_speed": "res://assets/ui/icons/speed.png",
		"missile": "res://assets/ui/icons/missile.png",
		"crit_chance": "res://assets/ui/icons/crit.png",
		"crit_damage": "res://assets/ui/icons/crit.png",
		"dodge_chance": "res://assets/ui/icons/dodge.png",
		"fire_rate": "res://assets/ui/icons/missile.png",
		"missile_speed_pct": "res://assets/ui/icons/missile.png",
		"missile_damage": "res://assets/ui/icons/missile.png",
		"damage_reduction": "res://assets/ui/icons/hp.png",
		"special_cd": "res://assets/ui/icons/special.png",
		"special_damage": "res://assets/ui/icons/special.png",
		"shield_capacity": "res://assets/ui/icons/shield.png",
		"shield_regen": "res://assets/ui/icons/shield.png",
		"loot_radius": "res://assets/ui/icons/all.png",
		"luck": "res://assets/ui/icons/crit.png",
		"xp_multiplier": "res://assets/ui/icons/trophy.png"
	}
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	
	# Icon
	var icon_path = str(stat_icons.get(stat_key, ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_rect = TextureRect.new()
		icon_rect.texture = load(icon_path)
		icon_rect.custom_minimum_size = Vector2(24, 24)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon_rect)
	
	# Label
	var lbl = Label.new()
	var pretty_key = stat_key.replace("_", " ").capitalize()
	
	# Percent logic
	var is_percent := stat_key in [
		"crit_chance", "crit_damage", "dodge_chance", "damage_reduction",
		"fire_rate", "missile_damage", "missile_speed_pct", "loot_radius", "xp_multiplier"
	]
	
	var val_str = ""
	if is_percent:
		val_str = "%.1f%%" % float(value)
	elif stat_key == "special_cd":
		val_str = "%.1fs" % float(value)
	else:
		val_str = str(value)
		
	lbl.text = pretty_key + " : " + val_str
	lbl.add_theme_font_size_override("font_size", 18)
	
	# Match popup text color
	var pop_cfg = _game_config.get("popups", {}).get("background", {})
	var font_col = str(pop_cfg.get("text_color", "#FFFFFF"))
	lbl.add_theme_color_override("font_color", Color.html(font_col))
	
	hbox.add_child(lbl)
	
	stats_container.add_child(hbox)

func _get_rarity_color_from_config(rarity: String) -> Color:
	var rarity_colors: Variant = _game_config.get("rarity_colors", {})
	if rarity_colors is Dictionary and (rarity_colors as Dictionary).has(rarity):
		return Color.html(str((rarity_colors as Dictionary).get(rarity, "#FFFFFF")))
	return DataManager.get_rarity_color(rarity)

func _update_inventory_ui() -> void:
	if _session_loot.is_empty():
		session_container.visible = false
		return
	
	session_container.visible = true
	
	# Clear grid
	for child in items_grid.get_children():
		child.queue_free()
	
	# Paginate
	var start = _current_page * _items_per_page
	var end = min(start + _items_per_page, _session_loot.size())
	
	var item_card_scene = load("res://scenes/components/ItemCard.tscn")
	var inv_config = {
		"rarity_frames": _game_config.get("rarity_frames", {}),
		"level_assets": _game_config.get("ship_options", {}).get("level_indicator_assets", {}),
		"slot_icons": _game_config.get("ship_options", {}).get("slot_icons", {}),
		"placeholders": _game_config.get("ship_options", {}).get("item_placeholders", {}),
		"hide_badges": true
	}
	
	for i in range(start, end):
		var item_data = _session_loot[i]
		var card = item_card_scene.instantiate()
		items_grid.add_child(card)
		
		var slot_id = str(item_data.get("slot", "primary"))
		card.setup_item(item_data, slot_id, inv_config)
		
		# Connect click
		card.card_pressed.connect(_on_item_clicked)
	
	# Update buttons
	prev_btn.disabled = (_current_page == 0)
	var max_page = ceil(float(_session_loot.size()) / _items_per_page) - 1
	next_btn.disabled = (_current_page >= max_page)
	
	# Hide buttons if only 1 page
	prev_btn.visible = (_session_loot.size() > _items_per_page)
	next_btn.visible = (_session_loot.size() > _items_per_page)

func _on_prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_update_inventory_ui()

func _on_next_page() -> void:
	var max_page = ceil(float(_session_loot.size()) / _items_per_page) - 1
	if _current_page < max_page:
		_current_page += 1
		_update_inventory_ui()

func _on_item_clicked(_id: String, _slot: String, item_data: Dictionary) -> void:
	# Show Details Popup
	var popup_scene = load("res://scenes/components/ItemDetailsPopup.tscn")
	if popup_scene:
		var popup = popup_scene.instantiate()
		add_child(popup)
		
		var inv_config = {
			"rarity_frames": _game_config.get("rarity_frames", {}),
			"level_assets": _game_config.get("ship_options", {}).get("level_indicator_assets", {}),
			"slot_icons": _game_config.get("ship_options", {}).get("slot_icons", {}),
			"placeholders": _game_config.get("ship_options", {}).get("item_placeholders", {})
		}
		
		var item_id = str(item_data.get("id", ""))
		var slot_id = str(item_data.get("slot", "primary"))
		# Re-fetch from profile to have latest level/stats
		var latest_item = ProfileManager.get_item_by_id(item_id)
		if latest_item.is_empty(): latest_item = item_data
		
		popup.setup(item_id, slot_id, ProfileManager.is_item_equipped(item_id), inv_config)
		
		# Signals handling (Interactive popup)
		popup.close_requested.connect(func(): popup.queue_free())
		
		popup.upgrade_requested.connect(func(id):
			if ProfileManager.upgrade_item(id):
				_update_inventory_ui()
				# Re-setup popup with new data
				popup.setup(id, slot_id, ProfileManager.is_item_equipped(id), inv_config)
		)
		
		popup.recycle_requested.connect(func(id):
			# Remove from inventory and session recap
			for i in range(_session_loot.size()):
				if str(_session_loot[i].get("id", "")) == id:
					var item = _session_loot[i]
					# Recycler via helper centralisé
					ProfileManager.add_crystals(ProfileManager.calculate_recycle_value(item))
					_session_loot.remove_at(i)
					break
			ProfileManager.remove_item_from_inventory(id)
			_update_inventory_ui()
			popup.queue_free()
		)
		
		popup.equip_requested.connect(func(id, slot):
			var ship_id = ProfileManager.get_active_ship_id()
			ProfileManager.equip_item(ship_id, slot, id)
			_update_inventory_ui()
			popup.setup(id, slot, true, inv_config)
		)
		
		popup.unequip_requested.connect(func(id, slot):
			var ship_id = ProfileManager.get_active_ship_id()
			ProfileManager.unequip_item(ship_id, slot)
			_update_inventory_ui()
			popup.setup(id, slot, false, inv_config)
		)

func _on_equip_pressed() -> void:
	if not _is_victory or _item.is_empty():
		return
	_ensure_boss_loot_in_inventory()
	_boss_loot_resolved = true
	var ship_id := ProfileManager.get_active_ship_id()
	ProfileManager.equip_item(ship_id, str(_item.get("slot", "primary")), str(_item.get("id", "")))
	_close()

func _on_disassemble_pressed() -> void:
	if not _is_victory or _item.is_empty():
		return
	_boss_loot_resolved = true
	# Convertir en cristaux via logic centralisée
	var val = ProfileManager.calculate_recycle_value(_item)
	ProfileManager.add_crystals(val)
	_close()

func _on_restart_pressed() -> void:
	restart_requested.emit()
	_close(false)

func _on_exit_pressed() -> void:
	exit_requested.emit()
	_close(false)

func _on_menu_pressed() -> void:
	menu_requested.emit()
	_close(false)

func set_navigation_labels(secondary_label: String, menu_label: String = "Menu") -> void:
	_secondary_nav_label = secondary_label
	_menu_nav_label = menu_label
	_apply_navigation_labels()

func _apply_navigation_labels() -> void:
	if exit_btn:
		exit_btn.text = _secondary_nav_label
	if menu_btn:
		menu_btn.text = _menu_nav_label

func _close(emit_finished: bool = true) -> void:
	_finalize_boss_loot_if_needed()
	if emit_finished:
		finished.emit()
	queue_free()

func _finalize_boss_loot_if_needed() -> void:
	if _boss_loot_resolved:
		return
	if not _is_victory or _item.is_empty():
		_boss_loot_resolved = true
		return
	_ensure_boss_loot_in_inventory()
	_boss_loot_resolved = true

func _ensure_boss_loot_in_inventory() -> bool:
	var item_id := str(_item.get("id", ""))
	if item_id != "" and not ProfileManager.get_item_by_id(item_id).is_empty():
		return true
	return ProfileManager.add_item_to_inventory(_item)

# =============================================================================
# XP DISPLAY
# =============================================================================

var _xp_gained: int = 0
var _xp_before: int = 0
var _xp_after: int = 0
var _level_before: int = 0
var _level_after: int = 0

# Animated XP bar references
var _xp_bar: ProgressBar = null
var _xp_left_label: Label = null
var _xp_right_label: Label = null
var _xp_pct_label: Label = null
var _xp_gained_label: Label = null
var _xp_levelup_label: Label = null

func set_xp_data(xp_gained: int, xp_before: int, xp_after: int, level_before: int, level_after: int) -> void:
	_xp_gained = xp_gained
	_xp_before = xp_before
	_xp_after = xp_after
	_level_before = level_before
	_level_after = level_after
	_build_xp_section()

func _build_xp_section() -> void:
	# Find the main VBox in the panel
	var main_vbox: VBoxContainer = null
	if panel_container:
		var margin = panel_container.get_child(0)
		if margin:
			main_vbox = margin.get_child(0) as VBoxContainer
	
	if not main_vbox:
		return
	
	# Remove old XP section if re-called
	var old := main_vbox.get_node_or_null("XPSection")
	if old:
		old.queue_free()
	
	# Create XP section
	var xp_section := VBoxContainer.new()
	xp_section.name = "XPSection"
	xp_section.add_theme_constant_override("separation", 6)
	main_vbox.add_child(xp_section)
	# Move it before the navigation buttons (RestartButton/ExitButton)
	main_vbox.move_child(xp_section, main_vbox.get_child_count() - 2)
	
	var sep := HSeparator.new()
	xp_section.add_child(sep)
	
	# XP gained text
	_xp_gained_label = Label.new()
	_xp_gained_label.text = "⭐ XP gagné: +" + str(_xp_gained)
	_xp_gained_label.add_theme_font_size_override("font_size", 18)
	_xp_gained_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_xp_gained_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_section.add_child(_xp_gained_label)
	
	# Level up notification (hidden initially, shown during animation)
	_xp_levelup_label = Label.new()
	_xp_levelup_label.add_theme_font_size_override("font_size", 16)
	_xp_levelup_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_xp_levelup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_levelup_label.visible = false
	xp_section.add_child(_xp_levelup_label)
	
	# XP Progress bar row
	var bar_row := HBoxContainer.new()
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_row.add_theme_constant_override("separation", 8)
	xp_section.add_child(bar_row)
	
	# Left level label
	_xp_left_label = Label.new()
	_xp_left_label.text = str(_level_before)
	_xp_left_label.add_theme_font_size_override("font_size", 15)
	_xp_left_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	bar_row.add_child(_xp_left_label)
	
	# Progress bar
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(320, 18)
	_xp_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.25)
	bar_bg.corner_radius_top_left = 4
	bar_bg.corner_radius_top_right = 4
	bar_bg.corner_radius_bottom_left = 4
	bar_bg.corner_radius_bottom_right = 4
	_xp_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.6, 1.0)
	bar_fill.corner_radius_top_left = 4
	bar_fill.corner_radius_top_right = 4
	bar_fill.corner_radius_bottom_left = 4
	bar_fill.corner_radius_bottom_right = 4
	_xp_bar.add_theme_stylebox_override("fill", bar_fill)
	bar_row.add_child(_xp_bar)
	
	# Right level label
	_xp_right_label = Label.new()
	_xp_right_label.text = str(_level_before + 1)
	_xp_right_label.add_theme_font_size_override("font_size", 15)
	_xp_right_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	bar_row.add_child(_xp_right_label)
	
	# Percentage label (centered below bar)
	_xp_pct_label = Label.new()
	_xp_pct_label.add_theme_font_size_override("font_size", 13)
	_xp_pct_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	_xp_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_section.add_child(_xp_pct_label)
	
	# Set initial bar state
	var xp_for_lvl := float(ProfileManager.get_xp_for_level(_level_before))
	_xp_bar.max_value = max(1.0, xp_for_lvl)
	_xp_bar.value = float(_xp_before)
	_update_xp_pct_label()
	
	# Start the animation after a short delay
	get_tree().create_timer(0.5).timeout.connect(_animate_xp_bar)

func _update_xp_pct_label() -> void:
	if _xp_bar and _xp_pct_label:
		var pct := 0.0
		if _xp_bar.max_value > 0:
			pct = (_xp_bar.value / _xp_bar.max_value) * 100.0
		_xp_pct_label.text = "%.0f%%" % pct

func _animate_xp_bar() -> void:
	if not is_instance_valid(_xp_bar):
		return
	
	var levels_to_animate := _level_after - _level_before
	var current_display_level := _level_before
	
	if levels_to_animate <= 0:
		# No level up — just animate from xp_before to xp_after in the same level
		var xp_for_lvl := float(ProfileManager.get_xp_for_level(current_display_level))
		_xp_bar.max_value = max(1.0, xp_for_lvl)
		var tween := create_tween()
		tween.tween_method(_set_xp_bar_value, float(_xp_before), float(_xp_after), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		return
	
	# Multiple levels gained — chain animations
	_chain_level_animations(current_display_level, levels_to_animate, 0)

func _chain_level_animations(display_level: int, total_levels: int, current_step: int) -> void:
	if not is_instance_valid(_xp_bar):
		return
	
	if current_step > total_levels:
		return
	
	if current_step == 0:
		# First step: fill current level bar from xp_before to max
		var xp_for_lvl := float(ProfileManager.get_xp_for_level(display_level))
		_xp_bar.max_value = max(1.0, xp_for_lvl)
		var self_wr_step0: WeakRef = weakref(self)
		var next_level_step0: int = display_level + 1
		var total_levels_step0: int = total_levels
		var next_step0: int = current_step + 1
		
		var tween := create_tween()
		tween.tween_method(_set_xp_bar_value, float(_xp_before), xp_for_lvl, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_callback(func():
			var inst0: Node = self_wr_step0.get_ref() as Node
			if inst0 == null or not is_instance_valid(inst0):
				return
			inst0._show_level_up_flash(next_level_step0)
			# Short pause then continue
			get_tree().create_timer(0.4).timeout.connect(func():
				var inst0b: Node = self_wr_step0.get_ref() as Node
				if inst0b == null or not is_instance_valid(inst0b):
					return
				inst0b._chain_level_animations(next_level_step0, total_levels_step0, next_step0)
			)
		)
	elif current_step < total_levels:
		# Intermediate levels: reset to 0, update labels, fill to max
		_update_level_labels(display_level)
		var xp_for_lvl := float(ProfileManager.get_xp_for_level(display_level))
		_xp_bar.max_value = max(1.0, xp_for_lvl)
		_xp_bar.value = 0
		_update_xp_pct_label()
		var self_wr_mid: WeakRef = weakref(self)
		var next_level_mid: int = display_level + 1
		var total_levels_mid: int = total_levels
		var next_step_mid: int = current_step + 1
		
		var tween := create_tween()
		tween.tween_method(_set_xp_bar_value, 0.0, xp_for_lvl, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_callback(func():
			var inst1: Node = self_wr_mid.get_ref() as Node
			if inst1 == null or not is_instance_valid(inst1):
				return
			inst1._show_level_up_flash(next_level_mid)
			get_tree().create_timer(0.3).timeout.connect(func():
				var inst1b: Node = self_wr_mid.get_ref() as Node
				if inst1b == null or not is_instance_valid(inst1b):
					return
				inst1b._chain_level_animations(next_level_mid, total_levels_mid, next_step_mid)
			)
		)
	else:
		# Final step: reset to 0, update labels, animate to xp_after
		_update_level_labels(display_level)
		var xp_for_lvl := float(ProfileManager.get_xp_for_level(display_level))
		_xp_bar.max_value = max(1.0, xp_for_lvl)
		_xp_bar.value = 0
		_update_xp_pct_label()
		
		var tween := create_tween()
		tween.tween_method(_set_xp_bar_value, 0.0, float(_xp_after), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_xp_bar_value(val: float) -> void:
	if is_instance_valid(_xp_bar):
		_xp_bar.value = val
		_update_xp_pct_label()

func _update_level_labels(level: int) -> void:
	if is_instance_valid(_xp_left_label):
		_xp_left_label.text = str(level)
	if is_instance_valid(_xp_right_label):
		_xp_right_label.text = str(level + 1)

func _show_level_up_flash(new_level: int) -> void:
	if not is_instance_valid(_xp_levelup_label):
		return
	
	var levels_gained := _level_after - _level_before
	_xp_levelup_label.text = "🎉 LEVEL UP! " + str(new_level) + " (+" + str(levels_gained) + " pts de compétence)"
	_xp_levelup_label.visible = true
	
	# Flash effect
	_xp_levelup_label.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_xp_levelup_label, "modulate", Color(1, 1, 1, 1), 0.3)
