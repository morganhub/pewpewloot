extends Control

## LootResultScreen — Écran de décision après avoir battu un boss et obtenu un item.
## Permet de Garder, Équiper ou Désassembler (Recycler) l'objet.

signal finished
signal restart_requested
signal exit_requested

var _item: Dictionary = {}
var _session_loot: Array = []
var _current_page: int = 0
var _items_per_page: int = 3
var _game_config: Dictionary = {}
var _is_victory: bool = true
var _boss_loot_resolved: bool = false

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
	var popup_bg: String = str(popup_config.get("background", {}).get("asset", ""))
	if popup_bg != "" and ResourceLoader.exists(popup_bg):
		var style = StyleBoxTexture.new()
		style.texture = load(popup_bg)
		var m = int(popup_config.get("margin", 30))
		style.content_margin_left = m
		style.content_margin_right = m
		style.content_margin_top = m
		style.content_margin_bottom = m
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
	if asset != "" and ResourceLoader.exists(asset):
		var style = StyleBoxTexture.new()
		style.texture = load(asset)
		style.content_margin_left = 15
		style.content_margin_right = 15
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
	
	item_type_label.visible = false # Hide level as per request
	
	var rarity: String = str(_item.get("rarity", "common"))
	var slot_id: String = str(_item.get("slot", "unknown"))
	
	# Set Slot Type as Title (eg. "Shield")
	var slot_data = DataManager.get_slot(slot_id)
	var slot_pretty_name = str(slot_data.get("name", slot_id)).capitalize()
	item_name_label.text = slot_pretty_name
	
	# Rarity Color
	item_name_label.add_theme_color_override("font_color", DataManager.get_rarity_color(rarity))
	
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

func _set_boss_loot_section_visible(visible: bool) -> void:
	if top_separator:
		top_separator.visible = visible
	if item_name_label:
		item_name_label.visible = visible
	if item_type_label:
		item_type_label.visible = visible
	if item_stats_panel:
		item_stats_panel.visible = visible
	if item_spacer:
		item_spacer.visible = visible
	if boss_buttons_container:
		boss_buttons_container.visible = visible
	if mid_separator:
		mid_separator.visible = visible
	if equip_btn:
		equip_btn.visible = visible
	if disassemble_btn:
		disassemble_btn.visible = visible

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
		"dodge_chance": "res://assets/ui/icons/dodge.png"
	}
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	
	# Icon
	var icon_path = str(stat_icons.get(stat_key, ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tr = TextureRect.new()
		tr.texture = load(icon_path)
		tr.custom_minimum_size = Vector2(24, 24)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(tr)
	
	# Label
	var lbl = Label.new()
	var pretty_key = stat_key.replace("_", " ").capitalize()
	
	# Percent logic
	var is_percent = false
	if stat_key.ends_with("chance") or stat_key.ends_with("_pct") or stat_key == "dodge_chance" or stat_key == "crit_chance":
		is_percent = true
	
	var val_str = ""
	if is_percent:
		val_str = "%.1f%%" % (float(value) * 100.0)
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
