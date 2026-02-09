extends Control

## ShipMenu — Menu de sélection de vaisseau et d'équipement.
## Accessible depuis l'écran d'accueil via le bouton "Vaisseau".
## Le vaisseau sélectionné ici s'applique à toutes les missions.



# =============================================================================
# CONSTANTES


# =============================================================================

const GRID_COLUMNS := 4
const GRID_GAP := 12
var _item_card_size := Vector2(100, 75)
var _ship_card_size := Vector2(100, 100)  # Ship cards size (3 visible at a time)



# =============================================================================
# RÉFÉRENCES UI


# =============================================================================

@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var content: VBoxContainer = $MarginContainer/ScrollContainer/Content
@onready var ship_count_label: Label = %ShipCountLabel
@onready var ship_unlock_btn: Button = %ShipUnlockButton
@onready var unlock_popup: PanelContainer = %UnlockPopup
@onready var unlock_message: Label = %Message
@onready var confirm_unlock_btn: Button = %ConfirmUnlockBtn
@onready var cancel_unlock_btn: Button = %CancelUnlockBtn
@onready var ship_stats_container: VBoxContainer = %ShipStatsContainer
@onready var ship_container: MarginContainer = %ShipContainer
@onready var ship_cards_container: HBoxContainer = %ShipCardsContainer
@onready var ship_prev_btn: Button = %ShipPrevBtn
@onready var ship_next_btn: Button = %ShipNextBtn
@onready var slots_label: Label = $MarginContainer/ScrollContainer/Content/SlotsLabel
@onready var slots_grid: GridContainer = $MarginContainer/ScrollContainer/Content/SlotsGrid
@onready var inventory_label: Label = $MarginContainer/ScrollContainer/Content/InventoryLabel
@onready var inventory_grid: GridContainer = $MarginContainer/ScrollContainer/Content/InventoryGrid
@onready var generate_item_button: Button = $MarginContainer/ScrollContainer/Content/DebugSection/GenerateItemButton
@onready var back_button: Button = $MarginContainer/ScrollContainer/Content/Header/BackButton

# Popup
@onready var item_popup: PanelContainer = $ItemPopup
@onready var popup_title: Label = $ItemPopup/MarginContainer/VBox/Header/PopupTitle
@onready var popup_item_name: Label = $ItemPopup/MarginContainer/VBox/ItemName
@onready var popup_stats: Label = $ItemPopup/MarginContainer/VBox/StatsLabel
@onready var popup_equip_btn: Button = $ItemPopup/MarginContainer/VBox/Buttons/EquipButton
@onready var popup_cancel_btn: Button = $ItemPopup/MarginContainer/VBox/Header/CloseButton

# Powers UI
@onready var sp_name_label: Label = %SPName
@onready var sp_icon_rect: TextureRect = %SPIcon
@onready var up_button: Button = %UPButton
@onready var unique_popup: PanelContainer = %UniqueSelectionPopup
@onready var unique_list: VBoxContainer = %PowerList
@onready var unique_cancel_btn: Button = %CancelSelectionButton

# Filtres et pagination
@onready var slot_filter: OptionButton = %SlotFilter
@onready var rarity_sort_btn: Button = %RaritySort
@onready var page_label: Label = %PageLabel
@onready var prev_page_btn: Button = %PrevPageBtn
@onready var next_page_btn: Button = %NextPageBtn
@onready var popup_upgrade_btn: Button = %UpgradeButton
@onready var popup_delete_btn: Button = %DeleteButton



# =============================================================================
# ÉTAT


# =============================================================================

var selected_ship_id: String = ""
var selected_slot: String = ""
var _game_config: Dictionary = {} # Initialized empty, loaded in _ready
var _recycle_value: int = 0
var slot_buttons: Dictionary = {}  # slot_id -> Button
var inventory_cards: Array = []  # Array of item card Controls

# Pour le popup
var popup_item_id: String = ""
var popup_is_equipped: bool = false
var popup_slot_id: String = ""

# Pagination et filtres
var current_page: int = 0
var items_per_page: int = 12  # 4 colonnes × 3 lignes
var filter_slot: String = ""  # "" = tous, sinon slot_id spécifique
var filter_rarity_asc: bool = false  # false = descendant, true = ascendant
var filter_rarity_enabled: bool = false

# Ship scroll state for infinite cycling (replaced by pagination)
var current_ship_page: int = 0
var _ship_visible_count: int = 4
var _all_ships_data: Array = []
var _drag_start_pos: Vector2 = Vector2.ZERO
var _min_drag_distance: float = 50.0
var _is_dragging: bool = false
var _previous_selected_ship_id: String = ""
var _is_initial_load: bool = true


# =============================================================================
# LIFECYCLE


# =============================================================================

func _ready() -> void:
	# Connexions
	# Ship Selection
	if ship_prev_btn: ship_prev_btn.pressed.connect(_on_ship_scroll_left)
	if ship_next_btn: ship_next_btn.pressed.connect(_on_ship_scroll_right)
	if ship_unlock_btn: ship_unlock_btn.pressed.connect(_on_ship_unlock_pressed)
	
	if confirm_unlock_btn: confirm_unlock_btn.pressed.connect(_on_confirm_unlock_pressed)
	if cancel_unlock_btn: cancel_unlock_btn.pressed.connect(func(): unlock_popup.visible = false)
	
	# Shop Button
	if ship_container: ship_container.gui_input.connect(_on_ship_scroll_gui_input)
	
	generate_item_button.pressed.connect(_on_generate_item_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Popup
	popup_equip_btn.pressed.connect(_on_popup_equip_pressed)
	if popup_cancel_btn: popup_cancel_btn.pressed.connect(_on_popup_cancel_pressed)
	item_popup.visible = false
	
	if up_button: up_button.pressed.connect(_on_up_button_pressed)
	if unique_cancel_btn: unique_cancel_btn.pressed.connect(func(): unique_popup.visible = false)
	unique_popup.visible = false
	
	# Filtres et pagination
	if slot_filter: slot_filter.item_selected.connect(_on_slot_filter_changed)
	if rarity_sort_btn: rarity_sort_btn.pressed.connect(_on_rarity_sort_pressed)
	if prev_page_btn: prev_page_btn.pressed.connect(_on_prev_page_pressed)
	if next_page_btn: next_page_btn.pressed.connect(_on_next_page_pressed)
	if popup_upgrade_btn: popup_upgrade_btn.pressed.connect(_on_popup_upgrade_pressed)
	if popup_delete_btn: popup_delete_btn.pressed.connect(_on_popup_recycle_pressed)
	
	_populate_slot_filter()
	
	# Appliquer les traductions
	_apply_translations()
	App.play_menu_music()
	
	_load_game_config()
	
	# Force reload ships if empty (e.g. JSON edit while running)
	if DataManager.get_ships().size() == 0:
		print("[ShipMenu] Warning: No ships found in DataManager. Attempting reload...")
		DataManager.reload_all()
			
	# Handle resize
	resized.connect(_on_resized)
	
	# Initial load deferred to ensure correct size
	call_deferred("_initial_layout")

	# Force update power buttons style
	# Power Buttons Styling
	# Power Buttons use power_button config (not ship_select_button)
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var power_cfg: Dictionary = ship_opts.get("power_button", {}) if ship_opts.get("power_button") is Dictionary else {}
	var power_asset: String = str(power_cfg.get("asset", ""))
	var power_text_color: Color = Color(power_cfg.get("text_color", "#FFFFFF"))
	var power_font_size: int = int(power_cfg.get("font_size", 16))
	var power_style_box = StyleBoxFlat.new()
	power_style_box.bg_color = Color(0.2, 0.2, 0.2, 1)
	
	if power_asset != "" and ResourceLoader.exists(power_asset):
		var tex = load(power_asset)
		power_style_box = StyleBoxTexture.new()
		power_style_box.texture = tex
		
	# 1. Unique Power Button (%UPButton)
	if up_button:
		up_button.custom_minimum_size = Vector2(0, 60) # Wide rectangle
		up_button.add_theme_stylebox_override("normal", power_style_box)
		up_button.add_theme_stylebox_override("hover", power_style_box)
		up_button.add_theme_stylebox_override("pressed", power_style_box)
		up_button.add_theme_stylebox_override("focus", power_style_box)
		# Ensure text is visible with configured color
		up_button.add_theme_color_override("font_color", power_text_color)
		up_button.add_theme_font_size_override("font_size", power_font_size)
		up_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		
	# 2. Super Power Display (SPInfo)
	# Access SPInfo container
	if sp_icon_rect:
		var sp_info = sp_icon_rect.get_parent()
		if sp_info is Control:
			# Strategy: Add a Panel node as first child of SPInfo and set it to full rect.
			var existing_bg = sp_info.get_node_or_null("SPBackgroundPanel")
			if not existing_bg:
				# Best bet without scene change: Add a Panel as a sibling of SPInfo, behind it?
				# SPInfo is in SPContainer (VBox).
				# Let's insert a PanelContainer in SPContainer, move SPInfo children into it.
				# Reference: sp_info (HBox)
				
				var parent = sp_info.get_parent()
				var idx = sp_info.get_index()
				
				var new_panel = PanelContainer.new()
				new_panel.name = "SPStyledContainer"
				new_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				new_panel.custom_minimum_size = Vector2(0, 60)
				new_panel.add_theme_stylebox_override("panel", power_style_box)
				
				parent.add_child(new_panel)
				parent.move_child(new_panel, idx)
				
				sp_info.reparent(new_panel)
				sp_info.alignment = BoxContainer.ALIGNMENT_CENTER
				sp_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _initial_layout() -> void:
	_calculate_layout_metrics()
	_setup_visuals()
	_load_ships()
	_update_slot_buttons()
	_update_inventory_grid()

func _on_resized() -> void:
	_calculate_layout_metrics()
	_load_ships()
	_update_inventory_grid()
	_update_slot_buttons()

func _setup_visuals() -> void:
	# 1. Main Background
	var ship_config: Dictionary = _game_config.get("ship_menu", {})
	var main_config: Dictionary = _game_config.get("main_menu", {})
	var bg_path: String = str(ship_config.get("background", main_config.get("background", "")))
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		var bg = get_node_or_null("Background")
		if not bg:
			bg = TextureRect.new()
			bg.name = "Background"
			bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bg)
			move_child(bg, 0)
		bg.texture = tex
	
	# 2. Section Backgrounds
	var sections_cfg: Dictionary = ship_config.get("sections", {})
	_apply_section_background("ShipSection", sections_cfg.get("ship_selection", {}))
	_apply_section_background("SlotsGrid", sections_cfg.get("equipment", {}))
	_apply_section_background("InventoryGrid", sections_cfg.get("inventory", {}))
	
	# 3. Fix Double Separator
	# Remove dynamically added separator if HSeparator3 already exists between slots and inventory
	var content_vbox = $MarginContainer/ScrollContainer/Content
	var dynamic_sep = content_vbox.get_node_or_null("SeparatorSlotsInventory")
	if dynamic_sep:
		dynamic_sep.queue_free()
	
	# 4. Popup Styling (Global)
	var popup_config: Dictionary = _game_config.get("popups", {})
	var popup_bg_asset: String = str(popup_config.get("background", {}).get("asset", ""))
	var margin: int = int(popup_config.get("margin", 20))
	
	if popup_bg_asset != "" and ResourceLoader.exists(popup_bg_asset):
		var style = StyleBoxTexture.new()
		style.texture = load(popup_bg_asset)
		style.content_margin_top = margin
		style.content_margin_bottom = margin
		style.content_margin_left = margin
		style.content_margin_right = margin
		
		if item_popup: item_popup.add_theme_stylebox_override("panel", style)
		if unlock_popup: unlock_popup.add_theme_stylebox_override("panel", style)
		if unique_popup: unique_popup.add_theme_stylebox_override("panel", style)
	
	# 5. Close button icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var close_icon_path: String = str(ui_icons.get("close_button", ""))
	if close_icon_path != "" and ResourceLoader.exists(close_icon_path) and popup_cancel_btn:
		popup_cancel_btn.icon = load(close_icon_path)
		popup_cancel_btn.text = ""
		popup_cancel_btn.flat = true
		popup_cancel_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		popup_cancel_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		popup_cancel_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		popup_cancel_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		
		
	# 6. Back Button
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.icon = load(back_icon_path)
		back_button.text = ""
		back_button.flat = true
		back_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		
	# NEW: Arrow Icons (Left/Right)
	var arrow_left_path: String = str(ui_icons.get("arrow_left", ""))
	var arrow_right_path: String = str(ui_icons.get("arrow_right", ""))
	
	var nav_btns = [ship_prev_btn, prev_page_btn]
	for btn in nav_btns:
		if btn and arrow_left_path != "" and ResourceLoader.exists(arrow_left_path):
			btn.icon = load(arrow_left_path)
			btn.text = ""
			# Optional: make flat or styled? Keeping default button style for now but with icon
			
	var next_btns = [ship_next_btn, next_page_btn]
	for btn in next_btns:
		if btn and arrow_right_path != "" and ResourceLoader.exists(arrow_right_path):
			btn.icon = load(arrow_right_path)
			btn.text = ""
	
	# 7. Sort Button Icon
	if rarity_sort_btn:
		var sort_icon_path: String = str(ui_icons.get("sort_desc", "")) # Default descending
		if filter_rarity_asc:
			sort_icon_path = str(ui_icons.get("sort_asc", ""))
		if sort_icon_path != "" and ResourceLoader.exists(sort_icon_path):
			rarity_sort_btn.icon = load(sort_icon_path)
			rarity_sort_btn.text = ""
	
	# 8. Shop Button Icon
	# 9. Dropdown Styling
	if slot_filter:
		_apply_dropdown_style(slot_filter)
	
	_create_slot_buttons()
	_update_slot_buttons()
	_update_inventory_grid()

func _apply_section_background(section_node_name: String, section_cfg: Dictionary) -> void:
	var bg_path: String = str(section_cfg.get("background", ""))
	if bg_path == "" or not ResourceLoader.exists(bg_path):
		return
	
	var content_vbox = $MarginContainer/ScrollContainer/Content
	var section_node = content_vbox.get_node_or_null(section_node_name)
	if not section_node:
		return
	
	# Wrap in a PanelContainer if not already wrapped
	if section_node.get_parent().name == section_node_name + "Wrapper":
		return # Already wrapped
	
	var wrapper = PanelContainer.new()
	wrapper.name = section_node_name + "Wrapper"
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style = StyleBoxTexture.new()
	style.texture = load(bg_path)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	wrapper.add_theme_stylebox_override("panel", style)
	
	var idx = section_node.get_index()
	content_vbox.add_child(wrapper)
	content_vbox.move_child(wrapper, idx)
	section_node.reparent(wrapper)

func _apply_dropdown_style(opt_btn: OptionButton) -> void:
	var dropdown_cfg: Dictionary = _game_config.get("ui_dropdown", {})
	var highlight_bg: Color = Color(dropdown_cfg.get("highlight_bg_color", "#FFD700"))
	var highlight_text: Color = Color(dropdown_cfg.get("highlight_text_color", "#000000"))
	var item_bg_asset: String = str(dropdown_cfg.get("item_bg_asset", ""))
	var item_text: Color = Color(dropdown_cfg.get("item_text_color", "#000000"))
	
	var popup = opt_btn.get_popup()
	
	# Hide radio buttons (checkable items in Godot usually show them)
	# This avoids the radio button icon occupying space.
	for i in range(popup.item_count):
		popup.set_item_as_checkable(i, false)
	
	# Styling via StyleBox overrides
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	if item_bg_asset != "" and ResourceLoader.exists(item_bg_asset):
		var tex_style = StyleBoxTexture.new()
		tex_style.texture = load(item_bg_asset)
		popup_style = tex_style
	
	popup.add_theme_stylebox_override("panel", popup_style)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = highlight_bg
	popup.add_theme_stylebox_override("hover", hover_style)
	
	popup.add_theme_color_override("font_hover_color", highlight_text)
	popup.add_theme_color_override("font_color", item_text)



func _calculate_layout_metrics() -> void:
	# Calculate card size for 3 columns with 12px gaps
	# ---------------------------------------------------------
	# 1. INVENTORY / SLOTS (Grid)
	# ---------------------------------------------------------
	var screen_width: float = size.x
	if screen_width == 0: screen_width = get_viewport_rect().size.x

	# Marge pour l'inventaire réduit pour prendre toute la place
	var inv_margin: float = 40.0 
	var inv_avail: float = screen_width - inv_margin - float((GRID_COLUMNS - 1) * GRID_GAP)
	var card_width: float = floor(inv_avail / float(GRID_COLUMNS))
	
	var card_height: float = card_width * (8.34 / 7.0)
	_item_card_size = Vector2(card_width, card_height)
	
	# ---------------------------------------------------------
	# 2. SHIPS (Carousel) -> INDEPENDENT
	# ---------------------------------------------------------
	var ship_visible_count: int = 4
	var ship_gap: int = 12 # Same gap
	# Marge réduite pour maximiser l'espace
	var ship_margin: float = 40.0 
	
	var ship_avail: float = screen_width - ship_margin - float((ship_visible_count - 1) * ship_gap)
	var s_width: float = floor(ship_avail / float(ship_visible_count))
	
	# Safety subtract
	s_width -= 1.0
	
	var s_height: float = s_width * (8.34 / 7.0)
	_ship_card_size = Vector2(s_width, s_height)
	
	# Apply to grids
	if slots_grid:
		slots_grid.columns = GRID_COLUMNS
		slots_grid.add_theme_constant_override("h_separation", GRID_GAP)
		slots_grid.add_theme_constant_override("v_separation", GRID_GAP)
		
	if inventory_grid:
		inventory_grid.columns = GRID_COLUMNS
		inventory_grid.add_theme_constant_override("h_separation", GRID_GAP)
		inventory_grid.add_theme_constant_override("v_separation", GRID_GAP)
	
	# Apply separation to ship cards container
	if ship_cards_container:
		ship_cards_container.add_theme_constant_override("separation", GRID_GAP)

func _apply_translations() -> void:
	slots_label.text = LocaleManager.translate("ship_menu_equipment", {"count": "8"})
	inventory_label.text = LocaleManager.translate("ship_menu_inventory")
	generate_item_button.text = LocaleManager.translate("ship_menu_generate_item")
	back_button.text = LocaleManager.translate("ship_menu_back")
	if popup_cancel_btn: popup_cancel_btn.text = LocaleManager.translate("item_popup_close")
	
	# Localiser les labels statiques dans PowersSection
	var powers_section := $MarginContainer/ScrollContainer/Content/PowersSection
	if powers_section:
		var sp_label := powers_section.get_node_or_null("SPContainer/Label")
		if sp_label: sp_label.text = LocaleManager.translate("ship_menu_super_power")
		var up_label := powers_section.get_node_or_null("UPContainer/Label")
		if up_label: up_label.text = LocaleManager.translate("ship_menu_unique_power")
	
	# Localiser le label de filtre
	var slot_filter_label := $MarginContainer/ScrollContainer/Content/FiltersContainer/SlotFilterLabel
	if slot_filter_label:
		slot_filter_label.text = LocaleManager.translate("ship_menu_slot_label")
	
	# Crystal label moved to stats area, so we don't update separate label here



# =============================================================================
# VAISSEAUX


# =============================================================================

func _load_ships() -> void:
	# Clear existing
	for child in ship_cards_container.get_children():
		child.queue_free()
	
	var all_ships := DataManager.get_ships()
	if all_ships.size() == 0:
		print("[ShipMenu] all_ships is empty. Reloading...")
		DataManager.reload_all()
		all_ships = DataManager.get_ships()
		
	print("[ShipMenu] Loaded ships count: ", all_ships.size())
	var total_ships := all_ships.size()
	var active_id := ProfileManager.get_active_ship_id()
	var unlocked_ids := ProfileManager.get_unlocked_ships()
	
	if selected_ship_id == "":
		selected_ship_id = active_id
	
	# Validate page index
	var total_pages: int = ceil(total_ships / float(_ship_visible_count))
	if total_pages == 0: total_pages = 1
	if current_ship_page < 0: current_ship_page = total_pages - 1
	if current_ship_page >= total_pages: current_ship_page = 0
	
	# Update Counter Label
	if ship_count_label:
		var count_str := str(unlocked_ids.size()) + " / " + str(total_ships)
		# Use translation key if available, else fallback
		var translated := LocaleManager.translate("ship_menu_unlocked_count", {"unlocked": str(unlocked_ids.size()), "total": str(total_ships)})
		if translated != "ship_menu_unlocked_count":
			ship_count_label.text = translated
		else:
			ship_count_label.text = "Vaisseaux: " + count_str
	
	# Pagination slicing
	var start_idx: int = current_ship_page * _ship_visible_count
	var end_idx: int = int(min(start_idx + _ship_visible_count, total_ships))
	
	for i in range(start_idx, end_idx):
		var ship = all_ships[i]
		if ship is Dictionary:
			var ship_dict := ship as Dictionary
			var s_id := str(ship_dict.get("id", ""))
			var s_name_key := "ship." + s_id + ".name"
			var s_name := LocaleManager.translate(s_name_key)
			if s_name == s_name_key: s_name = str(ship_dict.get("name", s_id))
			
			var is_unlocked := unlocked_ids.has(s_id)
			var is_selected := (s_id == active_id) # Active ship is marked
			if selected_ship_id == s_id:
				is_selected = true # Or visually distinct?
				# Actually, the checkmark is for active ship usually.
				# Let's keep logic: checkmark if active. But highlight if selected?
				# The create_ship_card logic handles "is_selected" as visual selection.
				# Let's pass (s_id == selected_ship_id)
				is_selected = (s_id == selected_ship_id)
			
			_create_ship_card(s_id, s_name, is_unlocked, is_selected, ship_dict)
	
	
	# Update Previous ID for next time
	_previous_selected_ship_id = selected_ship_id
	_is_initial_load = false
	
	_update_ship_info(selected_ship_id)
	_update_scroll_buttons()
	_update_slot_buttons()
	_update_inventory_grid()

func _create_ship_card(ship_id: String, ship_name: String, is_unlocked: bool, is_selected: bool, ship_data: Dictionary) -> void:
	# Card Container (PanelContainer) - uses calculated ship card size
	var card := PanelContainer.new()
	card.custom_minimum_size = _ship_card_size
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Transparent panel background
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0, 0, 0, 0)  # Transparent
	card.add_theme_stylebox_override("panel", style_bg)
	
	# LAYER 1: Background Asset (from ship_options.ship_select_button)
	# Use asset_selected or asset_unselected based on selection state
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var ship_select_cfg: Dictionary = ship_opts.get("ship_select_button", {}) if ship_opts.get("ship_select_button") is Dictionary else {}
	var asset_selected: String = str(ship_select_cfg.get("asset_selected", ""))
	var asset_unselected: String = str(ship_select_cfg.get("asset_unselected", ""))
	var bg_asset: String = asset_selected if is_selected else asset_unselected
	var text_color: Color = Color(ship_select_cfg.get("text_color", "#FFFFFF"))
	var _font_size: int = int(ship_select_cfg.get("font_size", 16))
	
	# Background TextureRect - FULL SIZE (scaling handled by icon_rect)
	var bg_rect = TextureRect.new()
	bg_rect.name = "BgTexture"
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	if bg_asset != "" and ResourceLoader.exists(bg_asset):
		# Check if it's a SpriteFrames (.tres) or Texture (.png)
		if bg_asset.ends_with(".tres"):
			var frames = load(bg_asset)
			if frames is SpriteFrames:
				var anim = AnimatedSprite2D.new()
				anim.sprite_frames = frames
				anim.play("default")
				anim.centered = false
				# Scale to fit bg_rect size? AnimatedSprite2D doesn't have size property like TextureRect
				# We add it to a container within bg_rect?
				# Actually, easier to swap bg_rect for a Control if animated.
				# But let's just make a dedicated node for anim if present.
				
				# For simplicity: If .tres, use a Control container that centers the anim
				var anim_container = Control.new()
				anim_container.set_anchors_preset(Control.PRESET_FULL_RECT)
				anim_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
				anim.position = _ship_card_size / 2.0 # Centered in the card
				anim.centered = true
				anim_container.add_child(anim)
				bg_rect.add_child(anim_container)
		else:
			bg_rect.texture = load(bg_asset)
	
	card.add_child(bg_rect)
	
	# LAYER 2: Ship Visual (Asset from ship_data)
	var visual: Variant = ship_data.get("visual", {})
	var visual_asset: String = ""
	if visual is Dictionary:
		visual_asset = str((visual as Dictionary).get("asset", ""))
	
	var icon_rect := TextureRect.new()
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.size = _ship_card_size # Force size for correct pivot
	icon_rect.pivot_offset = _ship_card_size / 2.0
	
	# PRE-SET TARGET STATE (Avoid flicker)
	if is_selected:
		icon_rect.rotation_degrees = 180.0
		icon_rect.scale = Vector2(1.0, 1.0)
	else:
		icon_rect.rotation_degrees = 0.0
		icon_rect.scale = Vector2(0.5, 0.5)

	if visual_asset != "" and ResourceLoader.exists(visual_asset):
		icon_rect.texture = load(visual_asset)
	
	if not is_unlocked:
		icon_rect.modulate = Color(0.2, 0.2, 0.2, 1) # Silhouette
	
	card.add_child(icon_rect)
	
	# ANIMATION LOGIC
	var was_previously_selected := (ship_id == _previous_selected_ship_id and _previous_selected_ship_id != "")
	
	if not _is_initial_load:
		if is_selected and not was_previously_selected:
			# NEW Selection: Animate from 0/0.5 to 180/1.0
			icon_rect.rotation_degrees = 0.0
			icon_rect.scale = Vector2(0.5, 0.5)
			
			var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(icon_rect, "rotation_degrees", 180.0, 1.0)
			tw.tween_property(icon_rect, "scale", Vector2(1.0, 1.0), 1.0)
			
		elif not is_selected and was_previously_selected:
			# DESELECTION: Animate from 180/1.0 to 0/0.5 (CCW)
			icon_rect.rotation_degrees = 180.0
			icon_rect.scale = Vector2(0.5, 0.5) # Modifié pour l'exemple pour voir l'effet

			var tw = create_tween()
			tw.set_parallel(true)
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# --- Étape 1 : Rotation à 0 et Scale à 1 en même temps ---
			tw.tween_property(icon_rect, "rotation_degrees", 180.0, 0.0)
			tw.tween_property(icon_rect, "scale", Vector2(1, 1), 0.0)

			# --- Étape 2 : Rotation supplémentaire après les deux premières ---
			# On utilise .chain() pour forcer cette animation à attendre la fin du bloc parallèle
			tw.chain().tween_property(icon_rect, "rotation_degrees", 0.0, 1.0)

	# Invisible Button for interaction
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS # Allow propagation for swipe
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new()) # Hover effect?
	# Maybe add a light hover overlay
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 1, 1, 0.1)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	# Disable button if already selected to prevent re-clicking
	if is_selected:
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		btn.pressed.connect(func(): 
			if not _is_dragging:
				_on_ship_card_pressed(ship_id)
		)
	
	card.add_child(btn)
	
	# Metadata
	card.set_meta("ship_id", ship_id)
	card.set_meta("price", int(ship_data.get("crystal_price", 0)))
	
	ship_cards_container.add_child(card)

func _on_ship_card_pressed(ship_id: String) -> void:
	# Prevent re-selecting the same ship
	if ship_id == selected_ship_id:
		return
	
	selected_ship_id = ship_id
	
	var unlocked_ids := ProfileManager.get_unlocked_ships()
	
	# Si verrouillé, afficher l'overlay d'achat
	if not unlocked_ids.has(ship_id):
		_show_purchase_overlay(ship_id)
		return
	
	# Vaisseau débloqué : on le sélectionne activement
	ProfileManager.set_active_ship(ship_id)
	
	# Re-render pour mettre à jour les visuels
	_load_ships()
	_update_ship_info(ship_id)
	
	
	# Mettre à jour les slots et inventaire pour ce vaisseau
	_update_slot_buttons()
	_update_inventory_grid()
	_update_locking_ui(selected_ship_id)

func _show_purchase_overlay(ship_id: String) -> void:
	# Trouver la carte du vaisseau
	for card in ship_cards_container.get_children():
		if card.has_meta("ship_id") and card.get_meta("ship_id") == ship_id:
			var price := int(card.get_meta("price"))
			
			# Vérifier si un overlay existe déjà
			var existing_overlay: Node = card.get_node_or_null("PurchaseOverlay")
			if existing_overlay:
				existing_overlay.queue_free()
				return # Toggle off
			
			# Créer l'overlay
			var overlay := PanelContainer.new()
			overlay.name = "PurchaseOverlay"
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			
			var overlay_style := StyleBoxFlat.new()
			overlay_style.bg_color = Color(0, 0, 0, 0.8)
			overlay.add_theme_stylebox_override("panel", overlay_style)
			
			var vbox := VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			overlay.add_child(vbox)
			
			# Spacer top
			var spacer_top := Control.new()
			spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vbox.add_child(spacer_top)
			
			# Prix
			var price_label := Label.new()
			price_label.text = str(price) + " 💎"
			price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price_label.add_theme_font_size_override("font_size", 20)
			vbox.add_child(price_label)
			
			# Bouton Acheter
			var buy_btn := Button.new()
			buy_btn.text = LocaleManager.translate("shop_buy")
			buy_btn.custom_minimum_size = Vector2(80, 35)
			buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var can_afford := ProfileManager.get_crystals() >= price
			buy_btn.disabled = not can_afford
			buy_btn.pressed.connect(func():
				selected_ship_id = ship_id
				_on_ship_unlock_pressed()
				overlay.queue_free()
			)
			vbox.add_child(buy_btn)
			
			# Spacer bottom
			var spacer_bottom := Control.new()
			spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vbox.add_child(spacer_bottom)
			
			card.add_child(overlay)
			break

func _update_ship_info(ship_id: String) -> void:
	# --- NEW STATS DISPLAY ---
	for child in ship_stats_container.get_children():
		child.queue_free()
		
	# 1. HEADER: Ship Name
	var ship := DataManager.get_ship(ship_id)
	var s_name_key := "ship." + ship_id + ".name"
	var s_name := LocaleManager.translate(s_name_key)
	if s_name == s_name_key: s_name = str(ship.get("name", ship_id))
	
	var name_lbl = Label.new()
	name_lbl.text = s_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ship_stats_container.add_child(name_lbl)
	
	# Calculated Stats
	var final_stats = _calculate_ship_stats(ship_id)
	var sh_config = _game_config.get("ship_menu", {})
	var max_vals = sh_config.get("stats_max_values", {})
	var stat_cfgs = sh_config.get("ship_stats", {})
	var stat_icons_override = sh_config.get("stat_icons", {}) # NEW: Read overrides
	var colors = sh_config.get("stat_colors", {})
	
	# Helper to merge icon override
	var get_cfg = func(key: String) -> Dictionary:
		var cfg = stat_cfgs.get(key, {}).duplicate()
		if stat_icons_override.has(key):
			cfg["icon_asset"] = stat_icons_override[key]
		return cfg
	
	# 2. SUMMARY ROW (Power, Levels, Crystals)
	var summary_row = HBoxContainer.new()
	summary_row.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_row.add_theme_constant_override("separation", 30)
	ship_stats_container.add_child(summary_row)
	
	# Power
	_add_stat_summary_item(summary_row, "POWER", str(int(final_stats.power)), get_cfg.call("power"))
	
	# Crystals
	_add_stat_summary_item(summary_row, "CRISTAUX", str(ProfileManager.get_crystals()), get_cfg.call("crystals"))
	
	# Levels (Worlds unlocked * 6 + current max_level)
	var levels_count = _calculate_levels_completed()
	_add_stat_summary_item(summary_row, "NIVEAUX", str(levels_count), get_cfg.call("level"))
	
	# 3. DETAILED STATS GRID
	var grid = HBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 40)
	ship_stats_container.add_child(grid)
	
	var col1 = VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(col1)
	
	var col2 = VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(col2)
	
	# Left Column: HP, Vitesse, Missile
	var max_hp = max(float(max_vals.get("max_hp", 100)), float(final_stats.max_hp) * 1.2)
	var hp_label = LocaleManager.translate("stat.max_hp").to_upper()
	if hp_label == "STAT.MAX_HP": hp_label = "HP"
	
	_add_detailed_stat(col1, hp_label, final_stats.max_hp, max_hp, get_cfg.call("hp"), colors.get("hp", "#ffffff"))
	# Right Column: Crit, Dodge, Special
	# Display percentage for crit/dodge
	var crit_val = final_stats.crit_chance * 100
	var dodge_val = final_stats.dodge_chance * 100
	
	# Dynamic Max: Ensure bar isn't pegged if value exceeds default max
	var max_crit = max(float(max_vals.get("crit_chance", 0.5) * 100), crit_val * 1.2)
	var max_dodge = max(float(max_vals.get("dodge_chance", 0.5) * 100), dodge_val * 1.2)
	var max_special = max(float(max_vals.get("special", 100)), float(final_stats.special_score) * 1.2)
	var max_speed = max(float(max_vals.get("move_speed", 300)), float(final_stats.move_speed) * 1.2)
	var max_missile = max(float(max_vals.get("missile", 100)), float(final_stats.missile_score) * 1.2)
	
	_add_detailed_stat(col1, "VITESSE", final_stats.move_speed, max_speed, get_cfg.call("speed"), colors.get("speed", "#ffffff"))
	_add_detailed_stat(col1, "MISSILE", final_stats.missile_score, max_missile, get_cfg.call("missile"), colors.get("missile", "#ffffff"))
	
	_add_detailed_stat(col2, "CRIT CHANCE", crit_val, max_crit, get_cfg.call("crit_chance"), colors.get("crit_chance", "#ffffff"))
	_add_detailed_stat(col2, "DODGE", dodge_val, max_dodge, get_cfg.call("dodge_chance"), colors.get("dodge_chance", "#ffffff"))
	_add_detailed_stat(col2, "SPECIAL", final_stats.special_score, max_special, get_cfg.call("special"), colors.get("special", "#ffffff"))
	_update_locking_ui(ship_id)

func _update_locking_ui(ship_id: String) -> void:
	if not ship_unlock_btn: return
	
	var unlocked_ids := ProfileManager.get_unlocked_ships()
	if unlocked_ids.has(ship_id):
		ship_unlock_btn.visible = false
	else:
		ship_unlock_btn.visible = true
		var ship := DataManager.get_ship(ship_id)
		var price := int(ship.get("crystal_price", 0))
		ship_unlock_btn.text = "Acheter (" + str(price) + " 💎)"
		
		var can_afford := (ProfileManager.get_crystals() >= price)
		ship_unlock_btn.disabled = not can_afford

func _on_ship_unlock_pressed() -> void:
	if selected_ship_id == "": return
	var ship := DataManager.get_ship(selected_ship_id)
	var price := int(ship.get("crystal_price", 0))
	
	unlock_popup.visible = true
	unlock_message.text = "Débloquer ce vaisseau pour " + str(price) + " cristaux ?"

func _on_confirm_unlock_pressed() -> void:
	if selected_ship_id == "": return
	var ship := DataManager.get_ship(selected_ship_id)
	var price := int(ship.get("crystal_price", 0))
	
	if ProfileManager.spend_crystals(price):
		ProfileManager.unlock_ship(selected_ship_id)
		ProfileManager.set_active_ship(selected_ship_id)
		unlock_popup.visible = false
		_load_ships() # Refresh UI
		_apply_translations() # Refresh crystals
		print("[ShipMenu] Unlocked ship: ", selected_ship_id)
	else:
		print("[ShipMenu] Not enough crystals!")

func _on_ship_scroll_left() -> void:
	current_ship_page -= 1
	_load_ships() # Should handle wrapping in _load_ships logic or before calling
	
func _on_ship_scroll_right() -> void:
	current_ship_page += 1
	_load_ships()

func _update_scroll_buttons() -> void:
	if not ship_prev_btn or not ship_next_btn or not ship_cards_container:
		return
	
	var all_ships := DataManager.get_ships()
	var show_arrows = all_ships.size() > _ship_visible_count
	
	var nav_container = ship_prev_btn.get_parent()
	if nav_container:
		nav_container.visible = show_arrows

func _on_ship_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_start_pos = event.position
			_is_dragging = false
			
	elif event is InputEventScreenDrag:
		if _drag_start_pos == Vector2.ZERO:
			return
			
		var drag_distance = event.position.x - _drag_start_pos.x
		if abs(drag_distance) > _min_drag_distance:
			_is_dragging = true
			if drag_distance > 0:
				_on_ship_scroll_left()
			else:
				_on_ship_scroll_right()
			_drag_start_pos = Vector2.ZERO # Consume drag


func _on_shop_button_pressed() -> void:
	# Navigate to ShopMenu via Switcher
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/ShopMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ShopMenu.tscn")



# =============================================================================
# SLOTS D'ÉQUIPEMENT


# =============================================================================

func _create_slot_buttons() -> void:
	for child in slots_grid.get_children():
		child.queue_free()
	slot_buttons.clear()
	
	var slots := DataManager.get_slots()
	for slot in slots:
		if slot is Dictionary:
			var slot_dict := slot as Dictionary
			var slot_id := str(slot_dict.get("id", ""))
			# var slot_name := str(slot_dict.get("name", slot_id))
			
			# Use a Container for layering
			var container := PanelContainer.new()
			container.custom_minimum_size = _item_card_size
			container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			container.clip_contents = true # Prevent expansion
			
			# LAYER 1: Background (equipment_button)
			var ship_opts: Dictionary = _game_config.get("ship_options", {})
			var equip_cfg: Dictionary = ship_opts.get("equipment_button", {}) if ship_opts.get("equipment_button") is Dictionary else {}
			var bg_asset: String = str(equip_cfg.get("asset", ""))
			var text_color: Color = Color(equip_cfg.get("text_color", "#FFFFFF"))
			var font_size: int = int(equip_cfg.get("font_size", 14))
			
			if bg_asset != "" and ResourceLoader.exists(bg_asset):
				var style = StyleBoxTexture.new()
				style.texture = load(bg_asset)
				container.add_theme_stylebox_override("panel", style)
			else:
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.2, 0.2, 0.2, 1)
				container.add_theme_stylebox_override("panel", style)
			
			# LAYER 2: Content container for positioning
			var content := Control.new()
			content.set_anchors_preset(Control.PRESET_FULL_RECT)
			container.add_child(content)
			
			# LAYER 2.1: Placeholder container
			var placeholder_container := Control.new()
			placeholder_container.name = "PlaceholderContainer"
			placeholder_container.set_anchors_preset(Control.PRESET_FULL_RECT)
			content.add_child(placeholder_container)
			
			# LAYER 3: Text VBox
			var vbox := VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			content.add_child(vbox)
			
			var label := Label.new()
			label.name = "InfoLabel"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", text_color)
			label.add_theme_font_size_override("font_size", font_size)
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.custom_minimum_size.x = _item_card_size.x - 10
			vbox.add_child(label)
			
			# LAYER 4: Slot Icon (initially hidden)
			var slot_icon := TextureRect.new()
			slot_icon.name = "SlotIcon"
			slot_icon.visible = false
			slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot_icon.custom_minimum_size = Vector2(28, 28)
			slot_icon.anchor_left = 0.5
			slot_icon.anchor_right = 0.5
			slot_icon.anchor_top = 1.0
			slot_icon.anchor_bottom = 1.0
			slot_icon.offset_left = -14
			slot_icon.offset_right = 14
			slot_icon.offset_top = -32
			slot_icon.offset_bottom = -4
			content.add_child(slot_icon)
			
			# LAYER 5: Level Indicator (Top-Center)
			var level_indicator := Control.new()
			level_indicator.name = "LevelIndicator"
			level_indicator.visible = false
			level_indicator.custom_minimum_size = Vector2(24, 24)
			# Anchor Top-Center
			level_indicator.anchor_left = 0.5
			level_indicator.anchor_right = 0.5
			level_indicator.anchor_top = 0.0
			level_indicator.anchor_bottom = 0.0
			level_indicator.offset_left = -12
			level_indicator.offset_right = 12
			level_indicator.offset_top = 0 # Top edge
			level_indicator.offset_bottom = 24
			content.add_child(level_indicator)
			
			# Add sub-nodes for level indicator (image + label)
			var li_bg := TextureRect.new()
			li_bg.name = "BgImage" # Can be TextureRect or AnimatedSprite2D placeholder
			li_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			li_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			level_indicator.add_child(li_bg)
			
			var li_label := Label.new()
			li_label.name = "Label"
			li_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			li_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			li_label.add_theme_font_size_override("font_size", 14)
			li_label.add_theme_color_override("font_color", Color.WHITE)
			li_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			level_indicator.add_child(li_label)

			
			# Invisible Button (LAYER 4)
			var btn := Button.new()
			btn.flat = true
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			
			btn.pressed.connect(func(): _on_slot_pressed(slot_id))
			
			container.add_child(btn)
			
			slots_grid.add_child(container)
			# Store the container to update text later
			slot_buttons[slot_id] = container

func _update_slot_buttons() -> void:
	if selected_ship_id == "":
		return
	
	var loadout := ProfileManager.get_loadout_for_ship(selected_ship_id)
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var slot_icons: Dictionary = ship_opts.get("slot_icons", {}) if ship_opts.get("slot_icons") is Dictionary else {}
	var lvl_assets: Dictionary = ship_opts.get("level_indicator_assets", {})
	
	for slot_id in slot_buttons.keys():
		var container: PanelContainer = slot_buttons[slot_id]
		
		# Locate components
		var content: Control = null
		for child in container.get_children():
			if child is Control and not child is Button and not child is TextureRect: # TextureRect might be stylebox bg? No, stylebox is on Panel.
				content = child
				break
		
		if not content: continue
		
		var label: Label = content.get_node_or_null("VBoxContainer/InfoLabel")
		var slot_icon: TextureRect = content.get_node_or_null("SlotIcon")
		var level_indicator: Control = content.get_node_or_null("LevelIndicator")
		
		var slot_data := DataManager.get_slot(slot_id)
		var slot_name := str(slot_data.get("name", slot_id))
		
		var equipped_item_id := str(loadout.get(slot_id, ""))
		
		if equipped_item_id != "":
			# --- EQUIPPED ---
			var item := ProfileManager.get_item_by_id(equipped_item_id)
			var rarity := str(item.get("rarity", "common"))
			var level := int(item.get("level", 1))
			
			# 1. Hide Text Label
			if label: label.visible = false
			
			# 2. Show Slot Icon
			if slot_icon:
				slot_icon.visible = true
				var icon_path := str(item.get("asset", ""))
				
				# Try placeholder if asset missing
				if icon_path == "" or not ResourceLoader.exists(icon_path):
					var placeholders: Dictionary = ship_opts.get("item_placeholders", {})
					icon_path = str(placeholders.get(slot_id, ""))
				
				# Final fallback to slot icon
				if icon_path == "" or not ResourceLoader.exists(icon_path):
					icon_path = str(slot_icons.get(slot_id, ""))
					
				# Clean up any existing animated icon
				var existing_anim = content.get_node_or_null("AnimatedSlotIcon")
				if existing_anim: existing_anim.queue_free()
				
				if icon_path != "" and ResourceLoader.exists(icon_path):
					if icon_path.ends_with(".tres"):
						# Animated Sprite
						slot_icon.visible = false # Hide static rect
						var frames = load(icon_path)
						if frames is SpriteFrames:
							var anim := AnimatedSprite2D.new()
							anim.name = "AnimatedSlotIcon"
							anim.sprite_frames = frames
							anim.play("default")
							anim.scale = Vector2(0.7, 0.7) # Same scale as inventory
							anim.centered = true
							
							# Center in content (assuming content is full rect or defined size)
							# Content is Control.PRESET_FULL_RECT inside PanelContainer
							anim.position = Vector2(_item_card_size.x / 2.0, _item_card_size.y / 2.0)
							
							content.add_child(anim)
					else:
						# Static Texture (Resize to big centered icon)
						slot_icon.visible = true
						slot_icon.texture = load(icon_path)
						
						# Apply big centered layout
						var reduced_size := _item_card_size * 0.7
						slot_icon.custom_minimum_size = reduced_size
						slot_icon.anchor_left = 0.5
						slot_icon.anchor_right = 0.5
						slot_icon.anchor_top = 0.5
						slot_icon.anchor_bottom = 0.5
						slot_icon.offset_left = -reduced_size.x / 2.0
						slot_icon.offset_right = reduced_size.x / 2.0
						slot_icon.offset_top = -reduced_size.y / 2.0
						slot_icon.offset_bottom = reduced_size.y / 2.0
				else:
					slot_icon.visible = false
			
			# 3. Show Level Indicator
			if level_indicator:
				level_indicator.visible = true
				var li_label := level_indicator.get_node_or_null("Label")
				if li_label: li_label.text = str(level)
				
				# Background logic
				var bg_path: String = ""
				if level <= 2: bg_path = str(lvl_assets.get("1-2", ""))
				elif level <= 5: bg_path = str(lvl_assets.get("3-5", ""))
				elif level <= 8: bg_path = str(lvl_assets.get("6-8", ""))
				elif level >= 9: bg_path = str(lvl_assets.get("9", ""))
				
				# Clean old bg anims if any
				for c in level_indicator.get_children():
					if c is AnimatedSprite2D: c.queue_free()
				
				var li_bg_tex: TextureRect = level_indicator.get_node_or_null("BgImage")
				
				if bg_path != "" and ResourceLoader.exists(bg_path):
					if bg_path.ends_with(".tres"):
						if li_bg_tex: li_bg_tex.visible = false
						var frames = load(bg_path)
						if frames is SpriteFrames:
							var bg_anim := AnimatedSprite2D.new()
							bg_anim.sprite_frames = frames
							bg_anim.play("default")
							bg_anim.centered = true
							bg_anim.position = Vector2(12, 12)
							# Insert at 0 to be behind label
							level_indicator.add_child(bg_anim)
							level_indicator.move_child(bg_anim, 0)
					else:
						if li_bg_tex:
							li_bg_tex.visible = true
							li_bg_tex.texture = load(bg_path)
				else:
					if li_bg_tex: li_bg_tex.texture = null
				
				# Apply style from config
				var font_col: Color = Color(lvl_assets.get("text_color", "#FFFFFF"))
				var font_sz: int = int(lvl_assets.get("font_size", 16))
				var w = int(lvl_assets.get("width", 24))
				var h = int(lvl_assets.get("height", 24))
				
				# Resize container
				level_indicator.custom_minimum_size = Vector2(w, h)
				level_indicator.offset_left = -w / 2
				level_indicator.offset_right = w / 2
				level_indicator.offset_bottom = h
				
				if li_label:
					li_label.add_theme_color_override("font_color", font_col)
					li_label.add_theme_font_size_override("font_size", font_sz)
					
				# Update anim position if exists (created in previous frame logic, but needs centering)
				for c in level_indicator.get_children():
					if c is AnimatedSprite2D:
						c.position = Vector2(w/2, h/2)
			
			# 4. Rarity Frame
			var frame_path := DataManager.get_rarity_frame_path(rarity)
			if frame_path != "" and ResourceLoader.exists(frame_path):
				var style = StyleBoxTexture.new()
				style.texture = load(frame_path)
				container.add_theme_stylebox_override("panel", style)
				
		else:
			# --- EMPTY ---
			# 1. Show Text Label
			if label:
				label.visible = true
				label.text = slot_name # Just name, no "Empty"
				label.modulate = Color.WHITE # Or config color
			
			# 2. Hide Icons
			if slot_icon: slot_icon.visible = false
			if level_indicator: level_indicator.visible = false
			
			# 3. Default Background
			var eq_cfg: Dictionary = ship_opts.get("equipment_button", {}) if ship_opts.get("equipment_button") is Dictionary else {}
			var eq_asset: String = str(eq_cfg.get("asset", ""))
			
			if eq_asset != "" and ResourceLoader.exists(eq_asset):
				var style = StyleBoxTexture.new()
				style.texture = load(eq_asset)
				container.add_theme_stylebox_override("panel", style)
			else:
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.2, 0.2, 0.2, 1)
				container.add_theme_stylebox_override("panel", style)
	
	_update_powers_ui()

func _on_slot_pressed(slot_id: String) -> void:
	if selected_ship_id == "": return
	
	selected_slot = slot_id
	var loadout := ProfileManager.get_loadout_for_ship(selected_ship_id)
	var equipped_id := str(loadout.get(slot_id, ""))
	
	if equipped_id != "":
		# Ouvrir le popup pour retirer l'item
		_show_item_popup(equipped_id, true, slot_id)
	else:
		# Auto Filter
		# Trouver l'index du slot dans le filtre
		for i in range(slot_filter.item_count):
			if str(slot_filter.get_item_metadata(i)) == slot_id:
				slot_filter.select(i)
				_on_slot_filter_changed(i)
				break



# =============================================================================
# GRILLE D'INVENTAIRE


# =============================================================================

func _update_inventory_grid() -> void:
	# Nettoyer l'ancienne grille
	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_cards.clear()
	
	var filtered := _get_filtered_inventory()
	print("[ShipMenu] Updating grid. Filtered items: ", filtered.size(), " Current Page: ", current_page)
	
	# Pagination
	var start_idx := current_page * items_per_page
	var end_idx: int = int(min(start_idx + items_per_page, filtered.size()))
	
	# Mettre à jour le label
	if filter_slot != "":
		var slot_data := DataManager.get_slot(filter_slot)
		inventory_label.text = LocaleManager.translate("ship_menu_inventory_filtered", {"slot": str(slot_data.get("name", filter_slot))})
	else:
		inventory_label.text = LocaleManager.translate("ship_menu_inventory")
	
	# Créer les cartes d'items pour la page courante
	for i in range(start_idx, end_idx):
		var item: Dictionary = filtered[i]
		var card := _create_item_card(item)
		inventory_grid.add_child(card)
		inventory_cards.append(card)
	
	_update_page_label()

func _create_item_card(item: Dictionary) -> PanelContainer:
	var item_id := str(item.get("id", ""))
	var rarity := str(item.get("rarity", "common"))
	var slot := str(item.get("slot", ""))
	var upgrade_level := int(item.get("upgrade", 0))
	
	var rarity_color := _get_rarity_color(rarity)
	var bg_color := rarity_color
	bg_color.a = 1.0
	
	# Container principal
	var card := PanelContainer.new()
	card.custom_minimum_size = _item_card_size
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.clip_contents = true
	
	# Style from ship_options
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var inv_cfg: Dictionary = ship_opts.get("inventory_button", {}) if ship_opts.get("inventory_button") is Dictionary else {}
	
	# Get placeholder path based on slot
	var placeholders: Dictionary = ship_opts.get("item_placeholders", {})
	var placeholder_path: String = str(item.get("asset", "")) # Try specific asset first
	
	if placeholder_path == "" or not ResourceLoader.exists(placeholder_path):
		# Fallback to slot placeholder
		placeholder_path = str(placeholders.get(slot, ""))
		
	# Final fallback to generic if still empty
	if placeholder_path == "" or not ResourceLoader.exists(placeholder_path):
		placeholder_path = str(ship_opts.get("item_placeholder", ""))
	
	# Determine frame asset (Priority: Rarity Frame > Inventory Button Asset > Flat)
	var frame_path := DataManager.get_rarity_frame_path(rarity)
	var final_asset := frame_path
	
	if final_asset == "" or not ResourceLoader.exists(final_asset):
		final_asset = str(inv_cfg.get("asset", ""))
	
	if final_asset != "" and ResourceLoader.exists(final_asset):
		var style = StyleBoxTexture.new()
		style.texture = load(final_asset)
		card.add_theme_stylebox_override("panel", style)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_color
		style.border_color = rarity_color
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		card.add_theme_stylebox_override("panel", style)
	
	# Content container (Control for absolute positioning)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(content)
	
	# LAYER 1: Placeholder image (PNG or .tres AnimatedSprite2D)
	if placeholder_path != "" and ResourceLoader.exists(placeholder_path):
		# Container for centering and scaling
		var placeholder_container := Control.new()
		placeholder_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(placeholder_container)
		
		if placeholder_path.ends_with(".tres"):
			# AnimatedSprite2D support
			var frames = load(placeholder_path)
			if frames is SpriteFrames:
				var anim := AnimatedSprite2D.new()
				anim.sprite_frames = frames
				anim.play("default")
				anim.centered = true
				anim.scale = Vector2(0.7, 0.7) # Reduced by 30%
				# Center in container
				anim.position = Vector2(_item_card_size.x / 2.0, _item_card_size.y / 2.0)
				placeholder_container.add_child(anim)
		else:
			# PNG/JPG texture support
			var placeholder := TextureRect.new()
			placeholder.texture = load(placeholder_path)
			placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# Reduce size by 30% (use 70% of card size)
			var reduced_size := _item_card_size * 0.7
			placeholder.custom_minimum_size = reduced_size
			# Center it
			placeholder.anchor_left = 0.5
			placeholder.anchor_right = 0.5
			placeholder.anchor_top = 0.5
			placeholder.anchor_bottom = 0.5
			placeholder.offset_left = -reduced_size.x / 2.0
			placeholder.offset_right = reduced_size.x / 2.0
			placeholder.offset_top = -reduced_size.y / 2.0
			placeholder.offset_bottom = reduced_size.y / 2.0
			placeholder_container.add_child(placeholder)
	
	# LAYER 2: Upgrade indicator (top-center)
	var display_level := int(item.get("level", 1))
	if display_level > 0 and display_level <= 10:
		# Determine background asset
		var lvl_assets: Dictionary = ship_opts.get("level_indicator_assets", {})
		var bg_path: String = ""
		
		# "1-2", "3-5", "6-8", "9"
		if display_level <= 2:
			bg_path = str(lvl_assets.get("1-2", ""))
		elif display_level <= 5:
			bg_path = str(lvl_assets.get("3-5", ""))
		elif display_level <= 8:
			bg_path = str(lvl_assets.get("6-8", ""))
		elif display_level >= 9:
			bg_path = str(lvl_assets.get("9", ""))
			
		# Increase size to accommodate larger font
		var w = int(lvl_assets.get("width", 24))
		var h = int(lvl_assets.get("height", 24))
		var li_size := Vector2(w, h)
		
		var indicator_container := Control.new()
		indicator_container.name = "LevelIndicator"
		indicator_container.custom_minimum_size = li_size
		# Anchor Top-Center
		indicator_container.anchor_left = 0.5
		indicator_container.anchor_right = 0.5
		indicator_container.anchor_top = 0.0
		indicator_container.anchor_bottom = 0.0
		indicator_container.offset_left = -li_size.x / 2
		indicator_container.offset_right = li_size.x / 2
		indicator_container.offset_top = 0
		indicator_container.offset_bottom = li_size.y
		content.add_child(indicator_container)
		
		# Background Image (same logic as slot buttons)
		if bg_path != "" and ResourceLoader.exists(bg_path):
			if bg_path.ends_with(".tres"):
				var frames = load(bg_path)
				if frames is SpriteFrames:
					var bg_anim := AnimatedSprite2D.new()
					bg_anim.sprite_frames = frames
					bg_anim.play("default")
					bg_anim.centered = true
					bg_anim.position = Vector2(li_size.x / 2, li_size.y / 2)
					indicator_container.add_child(bg_anim)
			else:
				var bg_tex := TextureRect.new()
				bg_tex.texture = load(bg_path)
				bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
				indicator_container.add_child(bg_tex)
		
		var upgrade_label := Label.new()
		upgrade_label.text = str(display_level)
		upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		upgrade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		var font_col: Color = Color(lvl_assets.get("text_color", "#FFFFFF"))
		var font_sz: int = int(lvl_assets.get("font_size", 16))
		
		upgrade_label.add_theme_font_size_override("font_size", font_sz)
		upgrade_label.add_theme_color_override("font_color", font_col)
		upgrade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		indicator_container.add_child(upgrade_label)
	
	# LAYER 3: Slot icon (bottom-center)
	var slot_icons: Dictionary = ship_opts.get("slot_icons", {}) if ship_opts.get("slot_icons") is Dictionary else {}
	var slot_icon_path: String = str(slot_icons.get(slot, ""))
	
	if slot_icon_path != "" and ResourceLoader.exists(slot_icon_path):
		var slot_icon := TextureRect.new()
		slot_icon.texture = load(slot_icon_path)
		slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot_icon.custom_minimum_size = Vector2(28, 28)
		slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Position at bottom-center
		slot_icon.anchor_left = 0.5
		slot_icon.anchor_right = 0.5
		slot_icon.anchor_top = 1.0
		slot_icon.anchor_bottom = 1.0
		slot_icon.offset_left = -14
		slot_icon.offset_right = 14
		slot_icon.offset_top = -32
		slot_icon.offset_bottom = -4
		
		content.add_child(slot_icon)
	
	# LAYER 4: Upgrade arrow indicator (if applicable)
	if _is_upgrade(item):
		var arrow_label := Label.new()
		arrow_label.text = "↑"
		arrow_label.add_theme_color_override("font_color", Color.GREEN)
		arrow_label.add_theme_font_size_override("font_size", 20)
		arrow_label.anchor_left = 1.0
		arrow_label.anchor_right = 1.0
		arrow_label.anchor_top = 0.0
		arrow_label.anchor_bottom = 0.0
		arrow_label.offset_left = -28
		arrow_label.offset_right = -4
		arrow_label.offset_top = 4
		arrow_label.offset_bottom = 28
		content.add_child(arrow_label)
	
	# Rendre cliquable
	var btn := Button.new()
	btn.flat = true
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.anchors_preset = Control.PRESET_FULL_RECT
	btn.pressed.connect(_on_inventory_card_pressed.bind(item_id))
	card.add_child(btn)
	
	return card

func _is_upgrade(item: Dictionary) -> bool:
	if selected_ship_id == "":
		return false
	
	var slot := str(item.get("slot", ""))
	var equipped_id := ProfileManager.get_equipped_item_id(selected_ship_id, slot)
	
	if equipped_id == "":
		# Pas d'item équipé = c'est une amélioration potentielle
		return true
	
	# Comparer les stats totales (simpliste)
	var item_stats: Variant = item.get("stats", {})
	var equipped := ProfileManager.get_item_by_id(equipped_id)
	var equipped_stats: Variant = equipped.get("stats", {})
	
	var item_total := _sum_stats(item_stats)
	var equipped_total := _sum_stats(equipped_stats)
	
	return item_total > equipped_total

func _sum_stats(stats: Variant) -> int:
	var total := 0
	if stats is Dictionary:
		for value in (stats as Dictionary).values():
			total += int(value)
	return total

func _on_inventory_card_pressed(item_id: String) -> void:
	_show_item_popup(item_id, false, "")



# =============================================================================
# POPUP DE DÉTAILS D'ITEM


# =============================================================================

func _show_item_popup(item_id: String, is_equipped: bool, slot_id: String) -> void:
	popup_item_id = item_id
	popup_is_equipped = is_equipped
	popup_slot_id = slot_id
	
	var item := ProfileManager.get_item_by_id(item_id)
	var item_name := str(item.get("name", "???"))
	var rarity := str(item.get("rarity", "common"))
	var level := int(item.get("level", 1))
	var slot := str(item.get("slot", ""))
	
	# Fetch Stat Config
	var sh_config = _game_config.get("ship_menu", {})
	var stat_cfgs = sh_config.get("ship_stats", {})
	var stat_icons_override = sh_config.get("stat_icons", {})
	
	# Clean up old dynamic elements (Stats Grid, Indicators)
	# Use immediate free (not queue_free) to prevent appending on same frame
	var content_vbox = item_popup.get_node("MarginContainer/VBox")
	var stats_grid = content_vbox.get_node_or_null("StatsGrid")
	if stats_grid:
		content_vbox.remove_child(stats_grid)
		stats_grid.free()
	
	# Hide legacy label if present
	if popup_stats: popup_stats.visible = false
	
	# Remove old overlay indicators from Frame (immediate)
	var to_remove: Array = []
	for child in item_popup.get_children():
		if child.name in ["PopupLevelIndicator", "PopupSlotIcon"]:
			to_remove.append(child)
	for child in to_remove:
		item_popup.remove_child(child)
		child.free()
	
	# 1. Header & Title (Existing)
	popup_title.text = LocaleManager.translate("item_popup_title")
	
	# 2. Item Name (Large, Rarity Color)
	popup_item_name.text = item_name
	popup_item_name.add_theme_color_override("font_color", _get_rarity_color(rarity))
	popup_item_name.add_theme_font_size_override("font_size", 22) # Large title
	
	# 3. Stats Grid (2 Columns)
	stats_grid = GridContainer.new()
	stats_grid.name = "StatsGrid"
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 10)
	# Insert after ItemName (index of ItemName + 1)
	content_vbox.add_child(stats_grid)
	content_vbox.move_child(stats_grid, popup_item_name.get_index() + 1)
	
	var item_stats: Dictionary = item.get("stats", {})
	
	for stat_key in item_stats.keys():
		var val = item_stats[stat_key]
		var cfg = stat_cfgs.get(stat_key, {}).duplicate()
		if stat_icons_override.has(stat_key):
			cfg["icon_asset"] = stat_icons_override[stat_key]
		
		# Icon (Large + 50%)
		var icon_path = str(cfg.get("icon_asset", ""))
		var icon_rect = TextureRect.new()
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon_rect.texture = load(icon_path)
		
		icon_rect.custom_minimum_size = Vector2(36, 36) # Approx 24 * 1.5
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		stats_grid.add_child(icon_rect)
		
		# Label (Name + Value)
		var text_label = Label.new()
		var tr_key = "stat." + stat_key
		var stat_name = LocaleManager.translate(tr_key)
		# Fallback if translation missing
		if stat_name == tr_key:
			stat_name = stat_key.capitalize()
			
		var val_str = ""
		if stat_key in ["crit_chance", "dodge_chance", "missile_speed_pct"]:
			var fval = float(val)
			# If small float (e.g. 0.11), convert to % (11)
			# If large (legacy 11), keep as is
			if fval <= 1.0:
				fval *= 100.0
			
			val_str = "+" + str(int(round(fval))) + "%"
		else:
			val_str = "+" + str(val)
			
		text_label.text = stat_name + "\n" + val_str
		text_label.add_theme_font_size_override("font_size", 16)
		stats_grid.add_child(text_label)

	# 4. Buttons (Update State)
	if is_equipped:
		popup_equip_btn.text = LocaleManager.translate("item_popup_unequip")
	else:
		popup_equip_btn.text = LocaleManager.translate("item_popup_equip")
		popup_equip_btn.disabled = (selected_ship_id == "")
	
	if popup_upgrade_btn:
		if level >= 10:
			popup_upgrade_btn.text = "MAX LEVEL"
			popup_upgrade_btn.disabled = true
		else:
			var cost := ProfileManager.get_upgrade_cost(level)
			popup_upgrade_btn.text = "Upgrade (" + str(cost) + "💎)"
			popup_upgrade_btn.disabled = (ProfileManager.get_crystals() < cost)
			
	if popup_delete_btn:
		popup_delete_btn.disabled = false
		var base_val: int = 5
		match rarity:
			"common": base_val = 5
			"rare": base_val = 15
			"epic": base_val = 40
			"legendary": base_val = 100
		var multiplier: float = 1.0 + (float(level) - 1.0) * 0.2
		_recycle_value = int(float(base_val) * multiplier)
		popup_delete_btn.text = "Recycler (+" + str(_recycle_value) + " 💎)"

	item_popup.visible = true
	
	# 5. Visuals: Rarity Frame
	var frame_path := DataManager.get_rarity_frame_path(rarity)
	_apply_bg_to_popup(item_popup, frame_path)
	
	# 6. Visuals: Overlays (Level Indicator & Slot Icon)
	_add_popup_overlays(level, slot)

func _add_popup_overlays(level: int, slot: String) -> void:
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	
# --- LEVEL INDICATOR (Top-Center) ---
	var lvl_assets: Dictionary = ship_opts.get("level_indicator_assets", {})
	# Use "a bit larger" (+20%) instead of +50%
	var w = int(lvl_assets.get("width", 32)) * 1.5 
	var h = int(lvl_assets.get("height", 32)) * 1.5
	var font_sz = int(lvl_assets.get("font_size", 26)) * 1.1
	var text_col = Color(lvl_assets.get("text_color", "#FFFFFF"))
	
	var bg_path = ""
	if level <= 2: bg_path = str(lvl_assets.get("1-2", ""))
	elif level <= 5: bg_path = str(lvl_assets.get("3-5", ""))
	elif level <= 8: bg_path = str(lvl_assets.get("6-8", ""))
	elif level >= 9: bg_path = str(lvl_assets.get("9", ""))
	
	# 1. Overlay transparent (s'étire sur tout le popup à cause du PanelContainer parent)
	var li_container = Control.new()
	li_container.name = "PopupLevelIndicator"
	li_container.mouse_filter = Control.MOUSE_FILTER_IGNORE # Important : laisse passer les clics
	li_container.z_index = 10
	
	item_popup.add_child(li_container)

	# 2. Le Badge réel (C'est lui qu'on dimensionne et positionne)
	var badge = Control.new()
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(w, h)
	
	# Ancrage Top-Center par rapport à l'Overlay
	badge.anchor_left = 0.5
	badge.anchor_right = 0.5
	badge.anchor_top = 0.0
	badge.anchor_bottom = 0.0
	
	# Offsets pour centrer
	badge.offset_left = -w/2
	badge.offset_right = w/2
	badge.offset_top = 0 
	badge.offset_bottom = h
	
	li_container.add_child(badge)
	
	# 3. Contenu (Icone et Label) : Ils remplissent le "Badge"
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var icon = TextureRect.new()
		icon.texture = load(bg_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(icon) # On ajoute au badge, pas au container global
		
	var lbl = Label.new()
	lbl.text = str(level)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", text_col)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(lbl) # On ajoute au badge
	
	# --- SLOT ICON (Bottom-Center) ---
	var slot_icons: Dictionary = ship_opts.get("slot_icons", {})
	var icon_path = str(slot_icons.get(slot, ""))
	
	if icon_path != "":
		# 1. Le conteneur sert de "calque" (Overlay)
		# Il sera étiré par le PanelContainer parent, c'est NORMAL.
		var si_container = Control.new()
		si_container.name = "PopupSlotIcon"
		si_container.mouse_filter = Control.MOUSE_FILTER_IGNORE # Important pour cliquer au travers
		si_container.z_index = 10
		
		item_popup.add_child(si_container)
		
		# 2. On configure la taille et la position sur l'ICÔNE elle-même
		# (et non plus sur le conteneur)
		var sw = 32 * 1.5
		var sh = 32 * 1.5
		
		var icon = TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		
		# On applique la taille fixe sur l'icone
		icon.custom_minimum_size = Vector2(sw, sh)
		
		# On ancre l'icone en bas au centre de son parent (si_container)
		# Comme si_container fait la taille du popup, ça placera l'icone en bas du popup.
		icon.anchor_left = 0.5
		icon.anchor_right = 0.5
		icon.anchor_top = 1.0 
		icon.anchor_bottom = 1.0
		
		# On applique les offsets pour centrer et remonter l'icone
		icon.offset_left = -sw / 2
		icon.offset_right = sw / 2
		icon.offset_top = -sh # Remonte de sa hauteur pour être "dedans"
		icon.offset_bottom = 0
		
		# Optionnel : Dimmer légèrement
		icon.modulate = Color(1, 1, 1, 0.8) 
		
		si_container.add_child(icon)

func _on_popup_equip_pressed() -> void:
	if popup_item_id == "":
		return
	
	if popup_is_equipped:
		# Retirer l'item
		ProfileManager.unequip_item(selected_ship_id, popup_slot_id)
	else:
		# Équiper l'item
		var item := ProfileManager.get_item_by_id(popup_item_id)
		var slot := str(item.get("slot", ""))
		ProfileManager.equip_item(selected_ship_id, slot, popup_item_id)
	
	item_popup.visible = false
	_update_slot_buttons()
	_update_inventory_grid()
	# Refresh ship stats display to reflect the equipment change
	if selected_ship_id != "":
		_update_ship_info(selected_ship_id)

func _on_popup_cancel_pressed() -> void:
	item_popup.visible = false



# =============================================================================
# DEBUG: Génération d'items


# =============================================================================

func _on_generate_item_pressed() -> void:
	# Use new LootGenerator
	# Retrieve Level (use ship level or 1 for now)
	var ship_level = 1 
	# Or calculate based on unlocked worlds:
	ship_level = _calculate_levels_completed()
	if ship_level < 1: ship_level = 1
	
	# Random slot?
	var item_res: Resource = LootGenerator.generate_loot(ship_level)
	if item_res:
		var item_dict = item_res.to_dict()
		if ProfileManager.add_item_to_inventory(item_dict):
			print("[ShipMenu] Generated item using LootGenerator: ", item_dict.get("name", "?"))
			# Reset filters to see the new item
			filter_slot = ""
			if slot_filter: slot_filter.select(0)
			current_page = 0
			_update_inventory_grid()
		else:
			print("[ShipMenu] Could not generate item: Inventory Full!")
	else:
		print("[ShipMenu] LootGenerator returned null!")

# LEGACY GENERATION REMOVED - Using LootGenerator singleton
			



# =============================================================================
# NAVIGATION


# =============================================================================

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/HomeScreen.tscn")



# =============================================================================
# UNIQUE POWER SELECTION


# =============================================================================

func _update_powers_ui() -> void:
	if selected_ship_id == "": return
	
	# Get config for unique power button
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var up_cfg: Dictionary = ship_opts.get("unique_power_button", {}) if ship_opts.get("unique_power_button") is Dictionary else {}
	var up_text_color: Color = Color(up_cfg.get("text_color", "#000000"))
	var up_font_size: int = int(up_cfg.get("font_size", 30))
	var up_letter_spacing: int = int(up_cfg.get("letter_spacing", 2))
	
	# Update SP Info
	var ship := DataManager.get_ship(selected_ship_id)
	var sp_id := str(ship.get("special_power_id", ""))
	
	if sp_id != "":
		var sp_data := DataManager.get_super_power(sp_id)
		if sp_name_label: 
			sp_name_label.text = str(sp_data.get("name", sp_id))
	else:
		if sp_name_label: 
			sp_name_label.text = LocaleManager.translate("ship_menu_none")

	# Update UP Button (Always visible, show "Aucun" with 0.7 opacity if none)
	if up_button:
		# Apply font styling from config
		up_button.add_theme_color_override("font_color", up_text_color)
		up_button.add_theme_color_override("font_hover_color", up_text_color)
		up_button.add_theme_color_override("font_pressed_color", up_text_color)
		up_button.add_theme_font_size_override("font_size", up_font_size)
		
		var avail := ProfileManager.get_available_unique_powers(selected_ship_id)
		if avail.is_empty():
			up_button.text = LocaleManager.translate("ship_menu_none")
			up_button.disabled = false # Still clickable but nothing to select
			up_button.modulate.a = 0.7 # Reduced opacity
		else:
			up_button.modulate.a = 1.0 # Full opacity
			up_button.disabled = false
			var active := ProfileManager.get_active_unique_power(selected_ship_id)
			if active != "":
				var p_data := DataManager.get_unique_power(active)
				up_button.text = str(p_data.get("name", active))
			else:
				up_button.text = LocaleManager.translate("ship_menu_none")
				up_button.modulate.a = 0.7 # No power selected

func _on_up_button_pressed() -> void:
	if selected_ship_id == "": return
	
	_refresh_unique_popup_list()
	if unique_popup:
		unique_popup.visible = true

func _refresh_unique_popup_list() -> void:
	if not unique_list: return
	
	# Clear children
	for child in unique_list.get_children():
		child.queue_free()
		
	var avail := ProfileManager.get_available_unique_powers(selected_ship_id)
	var active := ProfileManager.get_active_unique_power(selected_ship_id)
	
	for pid in avail:
		var p_data := DataManager.get_unique_power(pid)
		var p_name := str(p_data.get("name", pid))
		
		var btn := Button.new()
		btn.text = p_name
		if pid == active:
			btn.text += " (Active)"
			btn.modulate = Color.GREEN
			
		btn.pressed.connect(func(): _on_unique_power_selected(pid))
		unique_list.add_child(btn)

func _on_unique_power_selected(pid: String) -> void:
	ProfileManager.set_active_unique_power(selected_ship_id, pid)
	if unique_popup:
		unique_popup.visible = false
	_update_powers_ui()



# =============================================================================
# FILTRES ET PAGINATION


# =============================================================================

func _populate_slot_filter() -> void:
	if not slot_filter: return
	
	slot_filter.clear()
	slot_filter.add_item(LocaleManager.translate("ship_menu_all") if LocaleManager.has_key("ship_menu_all") else "Tous", 0)
	slot_filter.set_item_metadata(0, "")
	
	var slots := DataManager.get_slots()
	print("[ShipMenu] Populating filter with ", slots.size(), " slots.")
	
	for i in range(slots.size()):
		if slots[i] is Dictionary:
			var slot_dict := slots[i] as Dictionary
			var slot_id := str(slot_dict.get("id", ""))
			var slot_name := str(slot_dict.get("name", slot_id))
			
			slot_filter.add_item(slot_name, i + 1)
			slot_filter.set_item_metadata(i + 1, slot_id)

func _on_slot_filter_changed(index: int) -> void:
	if index == 0:
		filter_slot = ""
	else:
		filter_slot = str(slot_filter.get_item_metadata(index))
	
	current_page = 0
	_update_inventory_grid()

func _on_rarity_sort_pressed() -> void:
	if not filter_rarity_enabled:
		filter_rarity_enabled = true
		filter_rarity_asc = false # Start with Descending (rarity high to low)
	elif not filter_rarity_asc:
		filter_rarity_asc = true # Switch to Ascending
	else:
		filter_rarity_enabled = false # Disable
	
	# Update Icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var icon_path: String = ""
	if not filter_rarity_enabled:
		icon_path = ""
	elif filter_rarity_asc:
		icon_path = str(ui_icons.get("sort_asc", ""))
	else:
		icon_path = str(ui_icons.get("sort_desc", ""))
		
	if rarity_sort_btn:
		if icon_path != "" and ResourceLoader.exists(icon_path):
			rarity_sort_btn.icon = load(icon_path)
			rarity_sort_btn.text = ""
		else:
			rarity_sort_btn.icon = null
			rarity_sort_btn.text = "↑" if filter_rarity_asc else "↓"
			if not filter_rarity_enabled: rarity_sort_btn.text = "-"
	
	current_page = 0
	_update_inventory_grid()

func _on_prev_page_pressed() -> void:
	if current_page > 0:
		current_page -= 1
		_update_inventory_grid()

func _on_next_page_pressed() -> void:
	var filtered := _get_filtered_inventory()
	var total_pages: int = int(ceili(float(filtered.size()) / float(items_per_page)))
	
	if current_page < total_pages - 1:
		current_page += 1
		_update_inventory_grid()

func _get_filtered_inventory() -> Array:
	var inv := ProfileManager.get_inventory()
	var filtered: Array = []
	
	# Filtre par slot
	for item in inv:
		if item is Dictionary:
			var item_dict := item as Dictionary
			if filter_slot == "" or str(item_dict.get("slot", "")) == filter_slot:
				filtered.append(item_dict)
	
	# Tri par rareté
	if filter_rarity_enabled:
		var rarity_order := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4, "unique": 5}
		filtered.sort_custom(func(a, b):
			var ra: int = int(rarity_order.get(str(a.get("rarity", "common")), 0))
			var rb: int = int(rarity_order.get(str(b.get("rarity", "common")), 0))
			return rb > ra if filter_rarity_asc else ra > rb
		)
	
	return filtered

func _update_page_label() -> void:
	if not page_label: return
	
	var filtered := _get_filtered_inventory()
	var total_pages: int = int(max(1, ceili(float(filtered.size()) / float(items_per_page))))
	page_label.text = "Page " + str(current_page + 1) + "/" + str(total_pages)
	
	if prev_page_btn:
		prev_page_btn.disabled = (current_page == 0)
	if next_page_btn:
		next_page_btn.disabled = (current_page >= total_pages - 1)

func _on_popup_upgrade_pressed() -> void:
	if popup_item_id == "":
		return
	
	var item := ProfileManager.get_item_by_id(popup_item_id)
	var level := int(item.get("level", 1))
	
	if level >= 10:
		push_warning("[ShipMenu] Item already at max level!")
		return
	
	if ProfileManager.upgrade_item(popup_item_id):
		print("[ShipMenu] Item upgraded to level ", level + 1)
		# Refresh popup content instead of closing
		_show_item_popup(popup_item_id, popup_is_equipped, popup_slot_id)
		_update_inventory_grid()
		_apply_translations()  # Refresh crystal count
	else:
		push_warning("[ShipMenu] Upgrade failed!")

func _on_popup_recycle_pressed() -> void:
	if popup_item_id == "":
		return
	
	# TODO: Ajouter un popup de confirmation
	# Pour l'instant, suppression directe
	if popup_is_equipped:
		ProfileManager.unequip_item(selected_ship_id, popup_slot_id)
	
	# Recyclage
	if _recycle_value > 0:
		ProfileManager.add_crystals(_recycle_value)
		print("[ShipMenu] Recycled for ", _recycle_value, " crystals")
	
	ProfileManager.remove_item_from_inventory(popup_item_id)
	print("[ShipMenu] Item deleted: ", popup_item_id)
	
	item_popup.visible = false
	_update_inventory_grid()
	_update_slot_buttons()
	_apply_translations() # Refresh crystal count
	
	item_popup.visible = false
	_update_slot_buttons()
	_update_inventory_grid()



# =============================================================================
# UTILITAIRES


# =============================================================================

func _get_rarity_color(rarity_id: String) -> Color:
	var rarity := DataManager.get_rarity(rarity_id)
	var color_hex := str(rarity.get("color", "#FFFFFF"))
	return Color.html(color_hex)

# =============================================================================
# STAT CALCULATION & DISPLAY HELPERS
# =============================================================================

func _calculate_ship_stats(ship_id: String) -> Dictionary:
	var base_ship = DataManager.get_ship(ship_id)
	var base_stats = base_ship.get("stats", {})
	var final_stats = base_stats.duplicate(true)
	
	# Compute "Calculated" fields that aren't in raw JSON directly sometimes
	# or initialize defaults
	final_stats.special_damage = final_stats.get("special_damage", 0)
	
	# Equipment Modifiers
	var loadout = ProfileManager.get_loadout_for_ship(ship_id)
	for slot_id in loadout:
		if slot_id == "selected_unique_power": continue
		var item_id = str(loadout[slot_id])
		if item_id == "": continue
		var item = ProfileManager.get_item_by_id(item_id)
		if item.is_empty(): continue
		
		# Apply ITEM stats
		var i_stats = item.get("stats", {})
		for stat_key in i_stats:
			var val = float(i_stats[stat_key])
			
			# Map affix stat names to ship stat names
			# LootGenerator uses: "power", "max_hp", "move_speed", "crit_chance", "dodge_chance",
			#   "fire_rate", "missile_speed_pct", "special_cd", "special_damage"
			# Legacy items may use: "hp", "speed", "dodge", "cd_reduction"
			
			# Direct match stats (new LootGenerator format)
			if stat_key in ["power", "max_hp", "move_speed", "fire_rate", "missile_speed_pct", "special_damage"]:
				final_stats[stat_key] = float(final_stats.get(stat_key, 0)) + val
				print("[ShipMenu] DEBUG Item Stat: ", stat_key, " +", val, " New Total: ", final_stats[stat_key])
			elif stat_key in ["crit_chance", "dodge_chance"]:
				# HEURISTIC: If val > 1.0, assume it's legacy integer (e.g. 4 for 4%) and divide by 100
				if val > 1.0:
					val = val / 100.0
					print("[ShipMenu] DEBUG: Legacy ", stat_key, " detected. Converted to ", val)
				
				final_stats[stat_key] = float(final_stats.get(stat_key, 0)) + val
				print("[ShipMenu] DEBUG Item Stat: ", stat_key, " +", val, " New Total: ", final_stats[stat_key])
			elif stat_key == "special_cd":
				final_stats.special_cd = float(final_stats.get("special_cd", 10.0)) + val  # val is negative for reduction
			# Legacy format fallbacks
			elif stat_key == "speed":
				final_stats.move_speed = float(final_stats.get("move_speed", 200.0)) + val
			elif stat_key == "hp":
				final_stats.max_hp = float(final_stats.get("max_hp", 100)) + val
			elif stat_key == "dodge":
				var d_val = val
				if d_val > 1.0: d_val /= 100.0
				final_stats.dodge_chance = float(final_stats.get("dodge_chance", 0.02)) + d_val
			elif stat_key == "cd_reduction":
				final_stats.special_cd = max(1.0, float(final_stats.get("special_cd", 10.0)) * (1.0 - (val / 100.0)))
	
	print("[ShipMenu] DEBUG Final Stats: ", final_stats)
	
	# Composite Scores for UI
	# Missile Score: (fire_rate + missile_speed_pct) * power (User requested formula)
	# Note: fire_rate here is refire delay (0.5 etc), but user wants to add it.
	var fr = float(final_stats.get("fire_rate", 0.5))
	var m_spd = float(final_stats.get("missile_speed_pct", 1.0))
	var pwr = float(final_stats.get("power", 10.0))
	final_stats.missile_score = int(round((fr + m_spd) * pwr))
	print("[ShipMenu] DEBUG Missile Score: (", fr, " + ", m_spd, ") * ", pwr, " = ", final_stats.missile_score)
	
	# Special Score: damage / cooldown roughly
	# Special Score: damage / cooldown roughly
	var dmg = float(final_stats.get("special_damage", 0))
	var cd = float(final_stats.get("special_cd", 10.0))
	final_stats.special_score = dmg * (10.0 / max(1.0, cd))
	
	return final_stats

func _calculate_levels_completed() -> int:
	var profile = ProfileManager.get_active_profile()
	var progress = profile.get("progress", {})
	var count = 0
	# Assume 5 worlds, 6 levels each? Or iterate available
	for w_key in progress:
		if w_key.begins_with("world_"):
			var w_data = progress[w_key]
			# If unlocked and complete?
			# "max_unlocked_level" takes 0-5. if 5 and boss_killed -> 6 levels.
			var max_lvl = int(w_data.get("max_unlocked_level", 0))
			var boss = bool(w_data.get("boss_killed", false))
			# Each world has 6 levels (0 to 5)
			# max_unlocked_level is the NEXT level index to play.
			# So if max_unlocked_level is 3, we beat 0,1,2 => 3 levels.
			count += max_lvl
			# If we beat last level (5) max_unlocked stays 5 but boss_killed=true?
			# ProfileManager logic: max_unlocked clamped at 5. boss_killed=true means all done.
			if max_lvl == 5 and boss:
				count += 1 # The 6th level
	return count

func _add_stat_summary_item(parent: Control, label_text: String, value_text: String, cfg: Dictionary) -> void:
	var item_hbox = HBoxContainer.new()
	item_hbox.add_theme_constant_override("separation", 10)
	item_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var icon_path = str(cfg.get("icon_asset", ""))
	# Apply scaling: Icon +120% (x2.2), Font +25% (x1.25)
	var w = int(cfg.get("icon_width", 32) * 2.2) 
	var h = int(cfg.get("icon_height", 32) * 2.2)
	var font_sz = int(cfg.get("font_size", 22) * 1.25)
	var font_col = Color(str(cfg.get("font_color", "#FFFFFF")))

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_control = Control.new()
		icon_control.custom_minimum_size = Vector2(w, h)
		icon_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item_hbox.add_child(icon_control)
		
		# Support AnimatedSprite2D (.tres) or Texture (.png)
		if icon_path.ends_with(".tres"):
			var frames = load(icon_path)
			if frames is SpriteFrames:
				var anim = AnimatedSprite2D.new()
				anim.sprite_frames = frames
				anim.play("default")
				anim.position = Vector2(w/2.0, h/2.0)
				anim.centered = true
				# Scale anim if needed? usually pixel art, maybe scale node
				var anim_scale = w / 32.0 # Approximation if base is 32
				anim.scale = Vector2(anim_scale, anim_scale)
				icon_control.add_child(anim)
		else:
			var icon = TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_control.add_child(icon)
		
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", -2)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = label_text.to_upper()
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.add_theme_font_size_override("font_size", int(12 * 1.25)) # +25%
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_vbox.add_child(lbl)
	
	var val_lbl = Label.new()
	val_lbl.text = value_text
	val_lbl.add_theme_font_size_override("font_size", font_sz)
	val_lbl.add_theme_color_override("font_color", font_col)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_vbox.add_child(val_lbl)
	
	item_hbox.add_child(text_vbox)
	parent.add_child(item_hbox)

func _add_detailed_stat(parent: Control, label_text: String, current_value: float, max_value: float, cfg: Dictionary, bar_color_hex: String) -> void:
	var item_hbox = HBoxContainer.new()
	item_hbox.add_theme_constant_override("separation", 10)
	parent.add_child(item_hbox)
	
	var icon_path = str(cfg.get("icon_asset", ""))
	# Apply scaling: Icon +120% (x2.2), Font +25% (x1.25)
	var w = int(cfg.get("icon_width", 24) * 2.2)
	var h = int(cfg.get("icon_height", 24) * 2.2)
	var font_sz = int(cfg.get("font_size", 16) * 1.25)
	var font_col = Color(str(cfg.get("font_color", "#FFFFFF")))
	
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_control = Control.new()
		icon_control.custom_minimum_size = Vector2(w, h)
		icon_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item_hbox.add_child(icon_control)
		
		if icon_path.ends_with(".tres"):
			var frames = load(icon_path)
			if frames is SpriteFrames:
				var anim = AnimatedSprite2D.new()
				anim.sprite_frames = frames
				anim.play("default")
				anim.position = Vector2(w/2.0, h/2.0)
				anim.centered = true
				var anim_scale = w / 24.0 
				anim.scale = Vector2(anim_scale, anim_scale)
				icon_control.add_child(anim)
		else:
			var icon = TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_control.add_child(icon)
		
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 2)
	
	var lbl = Label.new()
	lbl.text = label_text.to_upper()
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", font_col)
	content_vbox.add_child(lbl)
	
	# Progress Bars
	var pct = clamp(current_value / max(1.0, max_value), 0.0, 1.0)
	print("[ShipMenu] DEBUG Bar '", label_text, "' Val:", current_value, " Max:", max_value, " Pct:", pct, " (", int(pct * 10), "/10 blocks)")
	
	var bar_control = Control.new()
	bar_control.custom_minimum_size = Vector2(0, 28)
	bar_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var color = Color.html(bar_color_hex)
	bar_control.draw.connect(func(): _draw_stat_bar(bar_control, pct, color))
	
	content_vbox.add_child(bar_control)
	item_hbox.add_child(content_vbox)
	
	# Value Label (Right aligned)
	var stat_font_size: int = int(_game_config.get("ship_options", {}).get("stats_number_font_size", 20))
	var val_label = Label.new()
	
	# Formatting logic
	var val_str: String = ""
	if current_value is float:
		if label_text in ["CRIT CHANCE", "DODGE"]: # Removed MISSILE from here
			# Crit/Dodge are 0.0-1.0 usually but passed as *100 in caller?
			# Caller passes: final_stats.crit_chance * 100. So it's 5.0 for 5%.
			val_str = str(snapped(current_value, 0.1))
			if val_str.ends_with(".0"): val_str = val_str.left(-2)
			val_str += "%"
		else:
			val_str = str(snapped(current_value, 0.1))
			if val_str.ends_with(".0"): val_str = val_str.left(-2)
	else:
		val_str = str(current_value)
	
	# Max 4 chars constraint (approximate implementation)
	# User wants 4 digits max. 
	if abs(current_value) >= 10000:
		val_str = str(snapped(current_value / 1000.0, 0.1)) + "k"
		if val_str.length() > 4: # e.g. 10.5k is 5 chars. 10k is 3.
			val_str = str(int(current_value / 1000.0)) + "k"
	elif abs(current_value) >= 1000:
		# 1234 is 4 chars. 1234.5 is 6.
		val_str = str(int(current_value))
	
	val_label.text = val_str
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	val_label.offset_right = -10 # Small margin from right edge
	val_label.add_theme_font_size_override("font_size", stat_font_size)
	val_label.add_theme_color_override("font_color", Color.WHITE)
	val_label.add_theme_constant_override("outline_size", 4)
	val_label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	bar_control.add_child(val_label)

func _draw_stat_bar(control: Control, percent: float, color: Color) -> void:
	var total_bars = 10
	var gap = 4
	var width = control.size.x / 1.5
	var height = control.size.y
	
	# Dynamic integer calculation to fit container without stretching artifacts
	var total_gap_width = (total_bars - 1) * gap
	var available_width = width - total_gap_width
	var bar_width = floor(max(0, available_width) / total_bars)
	
	var filled_bars = int(percent * total_bars)
	
	for i in range(total_bars):
		var x = int(i * (bar_width + gap))
		var rect = Rect2(x, 0, bar_width, height)
		
		# Draw clean integer rects
		if i < filled_bars:
			control.draw_rect(rect, color, true)
		else:
			# Empty slot styling (darker)
			control.draw_rect(rect, Color(0.2, 0.2, 0.2, 0.5), true)


# GAME CONFIG & POPUP STYLE
# =============================================================================

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_game_config = json.data
		file.close()

func _apply_popup_style() -> void:
	var popups_config: Dictionary = _game_config.get("popups", {})
	var default_bg: String = str(popups_config.get("default_background", ""))
	
	_apply_bg_to_popup(item_popup, default_bg)
	_apply_bg_to_popup(unique_popup, default_bg)
	_apply_bg_to_popup(unlock_popup, default_bg)

func _apply_bg_to_popup(popup: PanelContainer, bg_path: String) -> void:
	if not popup: return
	
	var style: StyleBoxFlat
	# Si on a une image, on l'utilise, sinon fallback bleu foncé
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var texture = load(bg_path)
		var texture_style = StyleBoxTexture.new()
		texture_style.texture = texture
		popup.add_theme_stylebox_override("panel", texture_style)
	else:
		if popup.get_theme_stylebox("panel") is StyleBoxFlat:
			style = popup.get_theme_stylebox("panel")
		else:
			style = StyleBoxFlat.new()
		
		# Fallback bleu foncé
		style.bg_color = Color(0.1, 0.1, 0.2, 0.95)
		style.set_corner_radius_all(16)
		popup.add_theme_stylebox_override("panel", style)
