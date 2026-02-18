extends Control

## ShipMenu — Menu de sélection de vaisseau et d'équipement.
## Accessible depuis l'écran d'accueil via le bouton "Vaisseau".
## Le vaisseau sélectionné ici s'applique à toutes les missions.



# =============================================================================
# CONSTANTES


# =============================================================================

const GRID_COLUMNS := 4
const GRID_GAP := 12
const ItemCardScene = preload("res://scenes/components/ItemCard.tscn")
const ItemDetailsPopupScene = preload("res://scenes/components/ItemDetailsPopup.tscn")
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
@onready var back_button: TextureButton = %BackButton

# Popup
@onready var item_popup: PanelContainer = $ItemPopup
@onready var popup_title: Label = $ItemPopup/MarginContainer/VBox/Header/PopupTitle
@onready var popup_item_name: Label = $ItemPopup/MarginContainer/VBox/ItemName
@onready var popup_stats: Label = $ItemPopup/MarginContainer/VBox/StatsLabel
@onready var popup_equip_btn: Button = %EquipButton
@onready var popup_cancel_btn: Button = %CloseButton

# Powers UI
@onready var sp_name_label: Label = %SPName
@onready var sp_icon_rect: TextureRect = %SPIcon
@onready var up_button: Button = %UPButton
@onready var unique_popup: PanelContainer = %UniqueSelectionPopup
@onready var unique_list: VBoxContainer = %PowerList
@onready var unique_cancel_btn: Button = %CancelSelectionButton

# Filtres et pagination
# Filtres et pagination
@onready var filters_container: VBoxContainer = $MarginContainer/ScrollContainer/Content/FiltersContainer
@onready var page_label: Label = %PageLabel
@onready var prev_page_btn: Button = %PrevPageBtn
@onready var next_page_btn: Button = %NextPageBtn
@onready var popup_upgrade_btn: Button = %UpgradeButton
@onready var popup_delete_btn: Button = %DeleteButton

var _filter_icon_buttons: Dictionary = {} # slot_id -> TextureButton



# =============================================================================
# ÉTAT


# =============================================================================

var selected_ship_id: String = ""
var selected_slot: String = ""
var _game_config: Dictionary = {} # Initialized empty, loaded in _ready
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
var filter_rarity: String = "" # "" = all, else rarity_id
var _rarity_badge_buttons: Dictionary = {} # rarity_id -> Button
var rarity_filter_label: Label = null
var multi_recycle_btn: TextureButton = null
var _item_details_popup: Control = null


# Ship scroll state for infinite cycling (replaced by pagination)
var current_ship_page: int = 0
var _ship_visible_count: int = 4
# _all_ships_data removed (unused)
var _drag_start_pos: Vector2 = Vector2.ZERO
var _min_drag_distance: float = 50.0
var _is_dragging: bool = false
var _previous_selected_ship_id: String = ""
var _is_initial_load: bool = true


# =============================================================================
# LIFECYCLE


# =============================================================================

func _ready() -> void:
	_load_game_config()
	
	if content: content.mouse_filter = Control.MOUSE_FILTER_PASS
	if inventory_grid: inventory_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	if slots_grid: slots_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	
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
	
	# Load Back Button Texture
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path):
		back_button.texture_normal = load(back_icon_path)

	
	
	# Popup (Legacy, removed)
	if item_popup: item_popup.visible = false

	
	if up_button: up_button.pressed.connect(_on_up_button_pressed)
	if unique_cancel_btn: unique_cancel_btn.pressed.connect(func(): unique_popup.visible = false)
	unique_popup.visible = false
	
	# Filtres et pagination
	# Filtres (New Icon System)
	# Clean up old UI elements if they exist
	if prev_page_btn: prev_page_btn.pressed.connect(_on_prev_page_pressed)
	if next_page_btn: next_page_btn.pressed.connect(_on_next_page_pressed)

	# Instantiate Item Details Popup
	_item_details_popup = ItemDetailsPopupScene.instantiate()
	_item_details_popup.visible = false
	_item_details_popup.z_index = 100 # Ensure on top
	add_child(_item_details_popup)
	
	# Redirect legacy reference to new popup
	if item_popup: item_popup.visible = false # Hide old
	item_popup = _item_details_popup # Update ref so existing code uses new popup
	
	_item_details_popup.close_requested.connect(func(): _item_details_popup.visible = false)
	_item_details_popup.upgrade_requested.connect(func(id): 
		popup_item_id = id
		_on_popup_upgrade_pressed()
	)
	_item_details_popup.recycle_requested.connect(func(id): 
		popup_item_id = id
		_on_popup_recycle_pressed(id)
	)
	_item_details_popup.equip_requested.connect(_on_popup_equip_requested)
	_item_details_popup.unequip_requested.connect(_on_popup_unequip_requested)


	_setup_filter_icons_ui()
	_setup_rarity_filter_ui()
	
	# Appliquer les traductions
	_apply_translations()
	App.play_menu_music()
	
	# Parallax Connection
	var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
	v_scroll.value_changed.connect(_update_background_parallax)
	


	
	# Force reload ships if empty (e.g. JSON edit while running)
	if DataManager.get_ships().size() == 0:
		DataManager.reload_all()
			
	# Handle resize
	resized.connect(_on_resized)
	
	# Initial load deferred to ensure correct size
	call_deferred("_initial_layout")
	if content: _fix_mobile_scroll_recursive(content)
	# Power Buttons Styling
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	
	# 1. Super Power Button config
	var power_cfg: Dictionary = ship_opts.get("power_button", {}) if ship_opts.get("power_button") is Dictionary else {}
	var power_asset: String = str(power_cfg.get("asset", ""))
	var power_text_color: Color = Color(power_cfg.get("text_color", "#000000"))
	var power_font_size: int = int(power_cfg.get("font_size", 30))
	var power_letter_spacing: int = int(power_cfg.get("letter_spacing", 2))
	
	var power_style_box: StyleBox
	if power_asset != "" and ResourceLoader.exists(power_asset):
		power_style_box = StyleBoxTexture.new()
		power_style_box.texture = load(power_asset)
	else:
		power_style_box = StyleBoxFlat.new()
		power_style_box.bg_color = Color(0.2, 0.2, 0.2, 1)
	
	# Apply to SP Label
	if sp_name_label:
		sp_name_label.add_theme_color_override("font_color", power_text_color)
		sp_name_label.add_theme_font_size_override("font_size", power_font_size)
		sp_name_label.add_theme_constant_override("letter_spacing", power_letter_spacing)

	# 2. Unique Power Button config
	var up_cfg: Dictionary = ship_opts.get("unique_power_button", {}) if ship_opts.get("unique_power_button") is Dictionary else {}
	var up_asset: String = str(up_cfg.get("asset", ""))
	var up_text_color: Color = Color(up_cfg.get("text_color", "#000000"))
	var up_font_size: int = int(up_cfg.get("font_size", 30))
	var up_letter_spacing: int = int(up_cfg.get("letter_spacing", 2))

	var up_style_box: StyleBox
	if up_asset != "" and ResourceLoader.exists(up_asset):
		up_style_box = StyleBoxTexture.new()
		up_style_box.texture = load(up_asset)
	else:
		up_style_box = StyleBoxFlat.new()
		up_style_box.bg_color = Color(0.2, 0.2, 0.2, 1)

	if up_button:
		up_button.custom_minimum_size = Vector2(0, 60)
		up_button.add_theme_stylebox_override("normal", up_style_box)
		up_button.add_theme_stylebox_override("hover", up_style_box)
		up_button.add_theme_stylebox_override("pressed", up_style_box)
		up_button.add_theme_stylebox_override("focus", up_style_box)
		up_button.add_theme_color_override("font_color", up_text_color)
		up_button.add_theme_font_size_override("font_size", up_font_size)
		# Button doesn't have letter_spacing directly, but it affects fallback or we can use it if we had a custom label
		up_button.add_theme_constant_override("letter_spacing", up_letter_spacing)
		up_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Super Power Display (SPInfo) background
	if sp_icon_rect:
		var sp_info = sp_icon_rect.get_parent()
		if sp_info is Control:
			var parent = sp_info.get_parent()
			var idx = sp_info.get_index()
			
			var new_panel = PanelContainer.new()
			new_panel.name = "SPStyledContainer"
			new_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			new_panel.custom_minimum_size = Vector2(0, 60)
			new_panel.add_theme_stylebox_override("panel", power_style_box)
			new_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# Update background size for parallax
	_setup_visuals() # Re-applies background size logic
	if scroll_container:
		_update_background_parallax(scroll_container.get_v_scroll_bar().value)

func _update_background_parallax(scroll_val: float) -> void:
	var bg = get_node_or_null("Background")
	if not bg or not scroll_container: return
	
	# Determine Scroll Progress (0.0 to 1.0)
	var v_scroll: VScrollBar = scroll_container.get_v_scroll_bar()
	var max_scroll: float = v_scroll.max_value - v_scroll.page
	
	var progress: float = 0.0
	if max_scroll > 0:
		progress = clamp(scroll_val / max_scroll, 0.0, 1.0)
		
	# Target: Move background UP as we scroll DOWN.
	# Available movement = Background Height - Viewport Height
	# We set bg height to 1.2x viewport in setup.
	var viewport_h: float = get_viewport_rect().size.y
	if viewport_h == 0: viewport_h = size.y
	
	var bg_h: float = bg.custom_minimum_size.y
	if bg_h < viewport_h: bg_h = viewport_h # Safety
	
	var max_shift: float = bg_h - viewport_h
	
	# Apply slight ease or direct linear mapping? Linear is predictable.
	var shift_y: float = -progress * max_shift
	
	bg.position.y = shift_y


func _setup_visuals() -> void:
	var content_vbox = $MarginContainer/ScrollContainer/Content
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
			# PARALLAX CHANGE: Use Top Wide to allow height modification and movement
			bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bg)
			move_child(bg, 0)
		
		# Ensure background is taller than screen for parallax (1.2x)
		var viewport_h = get_viewport_rect().size.y
		if viewport_h == 0: viewport_h = size.y
		bg.custom_minimum_size.y = viewport_h * 1.2
		bg.texture = tex
		
		# Initial Parallax Update
		if scroll_container:
			_update_background_parallax(scroll_container.get_v_scroll_bar().value)
	
	# 2. Section Backgrounds
	var sections_cfg: Dictionary = ship_config.get("sections", {})
	
	# Ship Selection (Covers the whole ship selector and stats)
	var ship_section_node = content_vbox.get_node_or_null("ShipSection")
	if ship_section_node:
		var stats_idx = ship_stats_container.get_index() if ship_stats_container else -1
		if stats_idx >= 0:
			_add_spacer(ship_section_node, 20, "SpacerStats", stats_idx + 1)
	
	_apply_section_background("ShipSection", sections_cfg.get("ship_selection", {}))
	
	# Equipment Section (Group Label + Grid)
	var equipment_nodes = []
	if slots_label: equipment_nodes.append(slots_label)
	if slots_grid: equipment_nodes.append(slots_grid)
	
	if not equipment_nodes.is_empty():
		var eq_section = _ensure_group_node("EquipmentSection", equipment_nodes)
		_add_spacer(eq_section, 10, "SpacerEqTitle", eq_section.get_node("SlotsLabel").get_index())
		_add_spacer(eq_section, 20, "SpacerEqGrid", eq_section.get_node("SlotsGrid").get_index())
		_add_spacer(eq_section, 30, "SpacerEqBottom")
		_apply_section_background(eq_section.name, sections_cfg.get("equipment", {}))
	
	# Inventory Section (Group Label + Filters + Grid + Pagination)
	var inventory_nodes = []
	if inventory_label: inventory_nodes.append(inventory_label)
	var filters = content_vbox.get_node_or_null("FiltersContainer")
	if filters: inventory_nodes.append(filters)
	if inventory_grid: inventory_nodes.append(inventory_grid)
	
	# Pagination
	var pagination = content_vbox.get_node_or_null("PaginationContainer")
	if pagination: inventory_nodes.append(pagination)
	
	if not inventory_nodes.is_empty():
		var inv_section = _ensure_group_node("InventorySection", inventory_nodes)
		_add_spacer(inv_section, 10, "SpacerInvTitle", inv_section.get_node("InventoryLabel").get_index())
		if filters:
			filters.add_theme_constant_override("separation", 10)
		_add_spacer(inv_section, 30, "SpacerInvGrid", inv_section.get_node("InventoryGrid").get_index())
		_apply_section_background(inv_section.name, sections_cfg.get("inventory", {}))
		
	# Powers Section (Title + Content)
	var powers_title = content_vbox.get_node_or_null("PowersTitleLabel")
	var powers_content = content_vbox.get_node_or_null("PowersSection") # The HBox
	var powers_nodes = []
	if powers_title: powers_nodes.append(powers_title)
	if powers_content: powers_nodes.append(powers_content)
	
	if not powers_nodes.is_empty():
		var p_section = _ensure_group_node("PowersSectionGroup", powers_nodes)
		_add_spacer(p_section, 10, "SpacerPowerTop", 0)
		_add_spacer(p_section, 10, "SpacerPowerBottom")
		_apply_section_background(p_section.name, sections_cfg.get("powers", {}))

	# 5. Section Titles Styling
	var title_cfg: Dictionary = _game_config.get("ship_menu", {}).get("title", {})
	var t_font_sz: int = int(title_cfg.get("font_size", 24))
	var t_linesp: int = int(title_cfg.get("letter_spacing", 2))
	var t_color_hex: String = str(title_cfg.get("text_color", "#FFFFFF"))
	var t_color: Color = Color.html(t_color_hex)
	
	var titles = []
	# Ship Title
	var ss_node = content_vbox.get_node_or_null("ShipSection")
	if ss_node:
		var st = ss_node.get_node_or_null("ShipTitleLabel")
		if st: titles.append(st)
	
	# Powers Title
	if powers_title: titles.append(powers_title)
	if slots_label: titles.append(slots_label)
	if inventory_label: titles.append(inventory_label)
	
	for t in titles:
		t.add_theme_font_size_override("font_size", t_font_sz)
		t.add_theme_constant_override("letter_spacing", t_linesp)
		t.add_theme_color_override("font_color", t_color)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# 3. Fix Double Separator
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
	
	# 5. Popup Buttons Styling (Upgrade, Recycle, Close, Equip)
	_update_popup_buttons_style()
		
		
	# 6. Back Button
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.texture_normal = load(back_icon_path)
		
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

	
	# 8. Shop Button Icon
	# 9. Dropdown Styling
	# 9. Dropdown Styling
	# Removed Legacy SlotFilter styling
	
	_create_slot_buttons()
	_update_slot_buttons()
	_update_inventory_grid()

func _ensure_group_node(group_name: String, nodes: Array) -> Control:
	var content_vbox = $MarginContainer/ScrollContainer/Content
	var existing = content_vbox.get_node_or_null(group_name)
	if existing: return existing as Control
	
	if nodes.is_empty(): return null
	
	# Create the group container
	var group = VBoxContainer.new()
	group.name = group_name
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 10)
	
	# Add it at the position of the first node
	var first_node = nodes[0] as Control
	var idx = first_node.get_index()
	content_vbox.add_child(group)
	content_vbox.move_child(group, idx)
	
	# Reparent all nodes to the group
	for node in nodes:
		if node is Control:
			node.reparent(group)
			
	return group

func _apply_section_background(section_node_name: String, section_cfg: Dictionary) -> void:
	var bg_path: String = str(section_cfg.get("background", ""))
	if bg_path == "" or not ResourceLoader.exists(bg_path):
		return
	
	# Look in Content or anywhere else
	var section_node = get_node_or_null("MarginContainer/ScrollContainer/Content/" + section_node_name)
	if not section_node:
		# Maybe it was already wrapped?
		section_node = get_node_or_null("MarginContainer/ScrollContainer/Content/" + section_node_name + "Wrapper/" + section_node_name)
		
	if not section_node:
		return
	
	var parent = section_node.get_parent()
	if parent and parent.name == section_node_name + "Wrapper":
		# Already wrapped, just update texture
		var existing_style = parent.get_theme_stylebox("panel")
		if existing_style is StyleBoxTexture:
			existing_style.texture = load(bg_path)
		return
	
	var wrapper = PanelContainer.new()
	wrapper.name = section_node_name + "Wrapper"
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var wrapper_style = StyleBoxTexture.new()
	wrapper_style.texture = load(bg_path)
	wrapper_style.content_margin_left = 15
	wrapper_style.content_margin_right = 15
	wrapper_style.content_margin_top = 15
	wrapper_style.content_margin_bottom = 15
	wrapper.add_theme_stylebox_override("panel", wrapper_style)
	
	var idx = section_node.get_index()
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)
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
	
	# Allow scroll pass on popup items? Native popup handling is different.
	# But setting mouse_filter pass on option button itself is good.
	opt_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
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
	
	popup.add_theme_color_override("font_hover_color", highlight_text)
	popup.add_theme_color_override("font_color", item_text)


func _update_popup_buttons_style() -> void:
	var details_cfg: Dictionary = _game_config.get("ship_menu", {}).get("ship_details", {}).get("buttons", {})
	var font_sz = int(details_cfg.get("font_size", 18))
	var text_col = Color(details_cfg.get("text_color", "#FFFFFF"))
	
	# Mapping key -> button node
	var buttons_map = {
		"upgrade": popup_upgrade_btn,
		"recycle": popup_delete_btn,
		"close": popup_cancel_btn,
		"equip": popup_equip_btn
	}
	
	for key in buttons_map:
		var btn = buttons_map[key]
		if not btn: continue
		
		# Common styles
		btn.add_theme_font_size_override("font_size", font_sz)
		btn.add_theme_color_override("font_color", text_col)
		
		var btn_cfg = details_cfg.get(key, {})
		if btn_cfg.is_empty(): continue
			
		var w = int(btn_cfg.get("width", 140))
		var h = int(btn_cfg.get("height", 50))
		var asset = str(btn_cfg.get("asset", ""))
		
		btn.custom_minimum_size = Vector2(w, h)
		
		if asset != "" and ResourceLoader.exists(asset):
			var style = StyleBoxTexture.new()
			var tex = load(asset)
			style.texture = tex
			# Ensure text is readable over image
			style.content_margin_left = 5
			style.content_margin_right = 5
			style.content_margin_top = 0
			style.content_margin_bottom = 0
			
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
			btn.add_theme_stylebox_override("focus", style)
			btn.add_theme_stylebox_override("disabled", style) # Ensure asset remains when disabled
			# Only disable flat if we are using stylebox
			btn.flat = false
		else:
			# If no asset, maybe keep default or flat
			pass


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
	
	var ship_menu_cfg: Dictionary = _game_config.get("ship_menu", {})
	var ship_sel_cfg: Dictionary = ship_menu_cfg.get("ship_selection", {}) if ship_menu_cfg.get("ship_selection") is Dictionary else {}
	var cfg_width: float = float(ship_sel_cfg.get("width", 0))
	var cfg_height: float = float(ship_sel_cfg.get("height", 0))
	var ship_ratio: float = (8.34 / 7.0)
	
	var s_width: float = 0.0
	var s_height: float = 0.0
	if cfg_width > 0.0 and cfg_height > 0.0:
		s_width = cfg_width
		s_height = cfg_height
	elif cfg_width > 0.0:
		s_width = cfg_width
		s_height = s_width * ship_ratio
	elif cfg_height > 0.0:
		s_height = cfg_height
		s_width = s_height / ship_ratio
	else:
		var ship_avail: float = screen_width - ship_margin - float((ship_visible_count - 1) * ship_gap)
		s_width = floor(ship_avail / float(ship_visible_count))
		# Safety subtract
		s_width -= 1.0
		s_height = s_width * ship_ratio
	
	_ship_card_size = Vector2(maxf(1.0, s_width), maxf(1.0, s_height))
	
	var v_gap = 40
	
	# Apply to grids
	if slots_grid:
		slots_grid.columns = GRID_COLUMNS
		slots_grid.add_theme_constant_override("h_separation", GRID_GAP)
		slots_grid.add_theme_constant_override("v_separation", v_gap)
		
	if inventory_grid:
		inventory_grid.columns = GRID_COLUMNS
		inventory_grid.add_theme_constant_override("h_separation", GRID_GAP)
		inventory_grid.add_theme_constant_override("v_separation", v_gap)
		# Set minimum height for 3 rows to avoid yoyo effect
		var inv_rows: int = 3
		var min_inv_h: float = float(inv_rows) * _item_card_size.y + float(inv_rows - 1) * float(v_gap) + 30.0
		inventory_grid.custom_minimum_size.y = min_inv_h
	
	# Apply separation to ship cards container
	if ship_cards_container:
		ship_cards_container.add_theme_constant_override("separation", GRID_GAP)

func _apply_translations() -> void:
	# 1. Ship Title
	var content_node = $MarginContainer/ScrollContainer/Content
	var ship_sec = content_node.get_node_or_null("ShipSection")
	if ship_sec:
		var st = ship_sec.get_node_or_null("ShipTitleLabel")
		if st: 
			var txt = LocaleManager.translate("ship_menu_ships")
			if txt == "ship_menu_ships": txt = "VAISSEAUX"
			st.text = txt.to_upper()
	
	# 2. Powers Title
	var pt = content_node.get_node_or_null("PowersTitleLabel")
	if pt: 
		var txt = LocaleManager.translate("ship_menu_powers")
		if txt == "ship_menu_powers": txt = "POUVOIRS"
		pt.text = txt.to_upper()

	# 3. Equipment
	var eq_txt = LocaleManager.translate("ship_menu_equipment")
	if eq_txt == "ship_menu_equipment": eq_txt = "EQUIPEMENT"
	slots_label.text = eq_txt.to_upper()

	# 4. Inventory
	var inv_txt = LocaleManager.translate("ship_menu_inventory")
	if inv_txt == "ship_menu_inventory": inv_txt = "INVENTAIRE"
	inventory_label.text = inv_txt.to_upper()

	generate_item_button.text = LocaleManager.translate("ship_menu_generate_item")
	# back_button is now a TextureButton, no text property
	if popup_cancel_btn: popup_cancel_btn.text = LocaleManager.translate("item_popup_close")
	
	if popup_cancel_btn: popup_cancel_btn.text = LocaleManager.translate("item_popup_close")
	
	# Clean up old labels in PowersSection if they still exist (though removed from tscn mostly)
	# var powers_section := content_node.get_node_or_null("PowersSection") # Unused variable removed
	# Since _setup_visuals wraps it, the path changes.
	# But _setup_visuals uses reparent. "PowersSection" is now child of "PowersSectionGroup" which is child of "Content".
	# So $MarginContainer/.../Content/PowersSection might fail if already wrapped.
	# We should search for it or assume wrapper structure if set up.
	# Or better: don't rely on it because we removed the labels in .tscn anyway.
	# We can just skip updating SP/UP labels since we use the main PowersTitleLabel now.
	
	# Localiser le label de filtre
	# Localiser le label de filtre (SUPPRIMÉ)
	# var slot_filter_label := get_node_or_null("MarginContainer/ScrollContainer/Content/FiltersContainer/SlotFilterLabel")
	# if slot_filter_label:
	# 	slot_filter_label.text = LocaleManager.translate("ship_menu_slot_label")
		
	if rarity_filter_label:
		rarity_filter_label.text = LocaleManager.translate("ship_menu_rarity_label")
	
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
		DataManager.reload_all()
		all_ships = DataManager.get_ships()
		
	var total_ships := all_ships.size()
	var active_id: String = ProfileManager.get_active_ship_id()
	var unlocked_ids := ProfileManager.get_unlocked_ships()
	
	if selected_ship_id == "":
		selected_ship_id = active_id
	if DataManager.get_ship(selected_ship_id).is_empty():
		selected_ship_id = active_id
	if DataManager.get_ship(selected_ship_id).is_empty() and total_ships > 0:
		var first_ship: Variant = all_ships[0]
		if first_ship is Dictionary:
			selected_ship_id = str((first_ship as Dictionary).get("id", ""))
	
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
			ship_count_label.text = count_str
	
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

func _create_ship_card(ship_id: String, _ship_name: String, is_unlocked: bool, is_selected: bool, ship_data: Dictionary) -> void:
	# 1. Le Conteneur Principal
	var card := PanelContainer.new()
	card.custom_minimum_size = _ship_card_size
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("panel", style_bg)
	
	# 2. Récupération des assets
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var ship_select_cfg: Dictionary = ship_opts.get("ship_select_button", {}) if ship_opts.get("ship_select_button") is Dictionary else {}
	var asset_animation: String = str(ship_select_cfg.get("asset_animation", ""))
	var asset_selected: String = str(ship_select_cfg.get("asset_selected", ""))
	var asset_unselected: String = str(ship_select_cfg.get("asset_unselected", ""))
	var anim_duration_cfg: float = maxf(0.0, float(ship_select_cfg.get("asset_animation_duration", ship_select_cfg.get("animation_duration", 0.0))))
	var anim_loop_cfg: bool = bool(ship_select_cfg.get("asset_animation_loop", false))
	var anim_w_cfg: float = float(ship_select_cfg.get("animation_width", 0.0))
	var anim_h_cfg: float = float(ship_select_cfg.get("animation_height", 0.0))
	
	# 3. LAYER 1: Background
	var bg_rect = TextureRect.new()
	bg_rect.name = "BgTexture"
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	if is_selected:
		# Selected: play animation once, then freeze on the last frame
		if asset_animation != "" and ResourceLoader.exists(asset_animation):
			var frames: Resource = load(asset_animation)
			if frames is SpriteFrames:
				var anim = AnimatedSprite2D.new()
				anim.centered = true
				anim.position = _ship_card_size / 2.0
				# Scale down to fit card size
				var frame_data: SpriteFrames = frames as SpriteFrames
				var first_anim_nm: StringName = _get_first_spriteframes_animation(frame_data)
				
				# Determine source size for scaling: use config if present, else texture size
				var src_size := Vector2.ZERO
				if anim_w_cfg > 0.0 and anim_h_cfg > 0.0:
					src_size = Vector2(anim_w_cfg, anim_h_cfg)
				else:
					var first_tex: Texture2D = _get_spriteframes_first_frame(frame_data)
					if first_tex:
						src_size = first_tex.get_size()
				
				if src_size.x > 0 and src_size.y > 0:
					var fit_scale := minf(_ship_card_size.x / src_size.x, _ship_card_size.y / src_size.y)
					anim.scale = Vector2(fit_scale, fit_scale)
				
				bg_rect.add_child(anim)
				var selected_anim_name: StringName = &"default"
				if first_anim_nm != &"":
					selected_anim_name = first_anim_nm
				VFXManager.play_sprite_frames(
					anim,
					frame_data,
					selected_anim_name,
					anim_loop_cfg,
					anim_duration_cfg
				)
		else:
			# Fallback: use asset_selected PNG if no animation
			if asset_selected != "" and ResourceLoader.exists(asset_selected):
				bg_rect.texture = load(asset_selected)
	else:
		if asset_unselected != "" and ResourceLoader.exists(asset_unselected):
			bg_rect.texture = load(asset_unselected)
	card.add_child(bg_rect)
	
	# 4. LAYER 2: Ship Visual (Le fix est ici)
	# On crée un Control pour "isoler" l'image des contraintes du PanelContainer
	var icon_wrapper := Control.new()
	icon_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrapper.custom_minimum_size = _ship_card_size
	icon_wrapper.pivot_offset = _ship_card_size / 2.0
	card.add_child(icon_wrapper) 
	
	var visual: Dictionary = ship_data.get("visual", {})
	var visual_asset: String = str(visual.get("asset", ""))
	var visual_anim: String = str(visual.get("asset_anim", ""))
	var visual_anim_duration: float = maxf(0.0, float(visual.get("asset_anim_duration", 0.0)))
	var visual_anim_loop: bool = bool(visual.get("asset_anim_loop", true))
	var ship_menu_cfg: Dictionary = _game_config.get("ship_menu", {})
	var ship_sel_cfg: Dictionary = ship_menu_cfg.get("ship_selection", {}) if ship_menu_cfg.get("ship_selection") is Dictionary else {}
	var allow_animated: bool = bool(ship_sel_cfg.get("animated", true))
	
	var icon_rect := TextureRect.new()
	icon_rect.name = "ShipIcon"
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	icon_wrapper.add_child(icon_rect)
	
	var asset_res: Resource = null
	if visual_asset != "" and ResourceLoader.exists(visual_asset):
		asset_res = load(visual_asset)
	
	var static_texture: Texture2D = null
	if asset_res is Texture2D:
		static_texture = asset_res as Texture2D
	
	var anim_frames: SpriteFrames = null
	if asset_res is SpriteFrames:
		anim_frames = asset_res as SpriteFrames
	elif visual_anim != "" and ResourceLoader.exists(visual_anim):
		var anim_res: Resource = load(visual_anim)
		if anim_res is SpriteFrames:
			anim_frames = anim_res as SpriteFrames
	
	var has_animated_icon := false
	var first_anim_name: StringName = _get_first_spriteframes_animation(anim_frames)
	var first_frame_tex: Texture2D = _get_spriteframes_first_frame(anim_frames)
	
	if allow_animated and anim_frames != null and first_anim_name != &"":
		has_animated_icon = true
		var anim_sprite := AnimatedSprite2D.new()
		anim_sprite.name = "ShipIconAnim"
		anim_sprite.centered = true
		anim_sprite.position = _ship_card_size / 2.0
		VFXManager.play_sprite_frames(
			anim_sprite,
			anim_frames,
			first_anim_name,
			visual_anim_loop,
			visual_anim_duration
		)
		if first_frame_tex:
			var f_size = first_frame_tex.get_size()
			if f_size.x > 0.0 and f_size.y > 0.0:
				var fit_scale := minf(_ship_card_size.x / f_size.x, _ship_card_size.y / f_size.y) * 0.8
				anim_sprite.scale = Vector2(fit_scale, fit_scale)
		icon_wrapper.add_child(anim_sprite)
	
	icon_rect.visible = not has_animated_icon
	if not has_animated_icon:
		if static_texture:
			icon_rect.texture = static_texture
		elif first_frame_tex:
			# animated=false: fallback to first frame when no static texture is provided
			icon_rect.texture = first_frame_tex
		
	# 5. État Initial (Pre-set)
	if not is_unlocked:
		icon_wrapper.modulate = Color(0.2, 0.2, 0.2, 1)
	
	# 6. LOGIQUE D'ANIMATION (réservé pour futur usage)
	
	# 7. Bouton Invisible pour l'interaction
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var empty_style = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 1, 1, 0.05)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	if is_selected:
		btn.disabled = true
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		btn.pressed.connect(func(): 
			if not _is_dragging:
				_on_ship_card_pressed(ship_id)
		)
	
	card.add_child(btn)
	
	# Metadata & Finalisation
	card.set_meta("ship_id", ship_id)
	card.set_meta("price", int(ship_data.get("crystal_price", 0)))
	ship_cards_container.add_child(card)

func _get_first_spriteframes_animation(frames: SpriteFrames) -> StringName:
	if frames == null:
		return &""
	if frames.has_animation(&"default"):
		return &"default"
	var names: PackedStringArray = frames.get_animation_names()
	if names.is_empty():
		return &""
	return StringName(names[0])

func _get_spriteframes_first_frame(frames: SpriteFrames) -> Texture2D:
	var anim_name: StringName = _get_first_spriteframes_animation(frames)
	if anim_name == &"":
		return null
	if frames.get_frame_count(anim_name) <= 0:
		return null
	var frame_tex = frames.get_frame_texture(anim_name, 0)
	if frame_tex is Texture2D:
		return frame_tex as Texture2D
	return null
	
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
	var ship_data := DataManager.get_ship(ship_id)
	if ship_data.is_empty():
		return
	var price := int(ship_data.get("crystal_price", 0))
	
	# Trouver la carte du vaisseau
	for card in ship_cards_container.get_children():
		if card.has_meta("ship_id") and card.get_meta("ship_id") == ship_id:
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
	_cleanup_orphaned_icons()
	
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
		var cfg_icon = str(cfg.get("icon_asset", ""))
		if (cfg_icon == "" or not ResourceLoader.exists(cfg_icon)) and stat_icons_override.has(key):
			cfg["icon_asset"] = stat_icons_override[key]
		return cfg
	
	# 2. SUMMARY ROW (Power, Crystals, Shop)
	var summary_row = HBoxContainer.new()
	summary_row.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_row.add_theme_constant_override("separation", 30)
	ship_stats_container.add_child(summary_row)
	
	# Power
	_add_stat_summary_item(summary_row, "POWER", str(int(final_stats.power)), get_cfg.call("power"))
	
	# Crystals
	_add_stat_summary_item(summary_row, "CRISTAUX", str(ProfileManager.get_crystals()), get_cfg.call("crystals"))
	
	# Shop (icon only)
	_add_stat_summary_shop_button(summary_row, get_cfg.call("shop"))
	
	# 3. DETAILED STATS GRID
	var grid = HBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 40)
	ship_stats_container.add_child(grid)
	
	var col1 = VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override("separation", 10)
	grid.add_child(col1)
	
	var col2 = VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 10)
	grid.add_child(col2)
	
	# Left Column: HP, Vitesse, Missile
	var max_hp = max(float(max_vals.get("max_hp", 100)), float(final_stats.max_hp) * 1.2)
	var hp_label = LocaleManager.translate("stat.max_hp").to_upper()
	if hp_label == "STAT.MAX_HP": hp_label = "HP"
	
	_add_detailed_stat(col1, hp_label, final_stats.max_hp, max_hp, get_cfg.call("hp"), colors.get("hp", "#ffffff"))
	# Right Column: Crit, Dodge, Special
	# Values already in 1-100 format
	var crit_val = final_stats.crit_chance
	var dodge_val = final_stats.dodge_chance
	
	# Dynamic Max: Ensure bar isn't pegged if value exceeds default max
	var max_crit = max(float(max_vals.get("crit_chance", 50)), crit_val * 1.2)
	var max_dodge = max(float(max_vals.get("dodge_chance", 30)), dodge_val * 1.2)
	var max_special = max(float(max_vals.get("special", 100)), float(final_stats.special_score) * 1.2)
	var max_speed = max(float(max_vals.get("move_speed", 300)), float(final_stats.move_speed) * 1.2)
	var max_missile = max(float(max_vals.get("missile", 100)), float(final_stats.missile_score) * 1.2)
	
	_add_detailed_stat(col1, "VITESSE", final_stats.move_speed, max_speed, get_cfg.call("speed"), colors.get("speed", "#ffffff"))
	_add_detailed_stat(col1, "MISSILE", final_stats.missile_score, max_missile, get_cfg.call("missile"), colors.get("missile", "#ffffff"))
	
	_add_detailed_stat(col2, "CRIT CHANCE", crit_val, max_crit, get_cfg.call("crit_chance"), colors.get("crit_chance", "#ffffff"))
	_add_detailed_stat(col2, "DODGE", dodge_val, max_dodge, get_cfg.call("dodge_chance"), colors.get("dodge_chance", "#ffffff"))
	_add_detailed_stat(col2, "SPECIAL", final_stats.special_score, max_special, get_cfg.call("special"), colors.get("special", "#ffffff"))
	_update_locking_ui(ship_id)
	if ship_stats_container: _fix_mobile_scroll_recursive(ship_stats_container)
	
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
	else:
		pass# Not enough crystals!

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
			var slot_name := str(slot_dict.get("name", slot_id))
			
			# Create ItemCard in Empty State
			var card = ItemCardScene.instantiate()
			card.custom_minimum_size = _item_card_size
			card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			
			var ship_opts: Dictionary = _game_config.get("ship_options", {})
			var config = {
				"equipment_button": ship_opts.get("equipment_button", {})
			}
			# Setup empty visuals
			card.setup_empty(slot_id, slot_name, config)
			
			# Connect signal
			card.card_pressed.connect(func(_i, s): _on_slot_pressed(s))
			
			slots_grid.add_child(card)
			slot_buttons[slot_id] = card # Store the ItemCard instance

func _update_slot_buttons() -> void:
	if selected_ship_id == "":
		return
	
	var loadout := ProfileManager.get_loadout_for_ship(selected_ship_id)
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	
	# Prepare config for ItemCard setup
	var config = {
		"rarity_frames": _game_config.get("rarity_frames", {}),
		"rarity_colors": _game_config.get("rarity_colors", {}),
		"level_assets": ship_opts.get("level_indicator_assets", {}),
		"placeholders": ship_opts.get("item_placeholders", {}),
		"slot_icons": ship_opts.get("slot_icons", {}),
		"equipment_button": ship_opts.get("equipment_button", {}),
		"show_upgrade": false # Equipment slots dont show upgrade arrows usually
	}
	
	for slot_id in slot_buttons.keys():
		var card = slot_buttons[slot_id]
		if not card or not is_instance_valid(card): continue
		
		# Get slot name logic
		var slot_data := DataManager.get_slot(slot_id)
		var slot_name := str(slot_data.get("name", slot_id))
		
		var equipped_item_id := str(loadout.get(slot_id, ""))
		
		if equipped_item_id != "":
			# EQUIPPED -> Setup as Item
			var item := ProfileManager.get_item_by_id(equipped_item_id)
			if item.is_empty():
				# Fallback if item deleted but ref exists (shouldnt happen)
				card.setup_empty(slot_id, slot_name, config)
			else:
				card.setup_item(item, slot_id, config)
		else:
			# EMPTY -> Setup as Empty
			card.setup_empty(slot_id, slot_name, config)
	
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
		# Auto Filter via Icon
		_on_filter_icon_pressed(slot_id)

# =============================================================================
# GRILLE D'INVENTAIRE
# =============================================================================

func _update_inventory_grid() -> void:
	# Nettoyer l'ancienne grille
	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_cards.clear()
	
	var filtered := _get_filtered_inventory()
			
	# Pagination
	var start_idx := current_page * items_per_page
	var end_idx: int = int(min(start_idx + items_per_page, filtered.size()))
	
	# Mettre à jour le label
	inventory_label.text = LocaleManager.translate("ship_menu_inventory")
	
	# Créer les cartes d'items pour la page courante
	for i in range(start_idx, end_idx):
		var item: Dictionary = filtered[i]
		var card := _create_item_card(item)
		inventory_grid.add_child(card)
		inventory_cards.append(card)
	
	_update_page_label()
	if inventory_grid: _fix_mobile_scroll_recursive(inventory_grid)

	
func _create_item_card(item: Dictionary) -> Control:
	var card = ItemCardScene.instantiate()
	card.custom_minimum_size = _item_card_size
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Prepare config for ItemCard
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var config = {
		"rarity_frames": _game_config.get("rarity_frames", {}),
		"rarity_colors": _game_config.get("rarity_colors", {}),
		"level_assets": ship_opts.get("level_indicator_assets", {}),
		"placeholders": ship_opts.get("item_placeholders", {}),
		"slot_icons": ship_opts.get("slot_icons", {}),
		"equipment_button": ship_opts.get("equipment_button", {}),
		"show_upgrade": _is_upgrade(item)
	}
	
	var slot_id = str(item.get("slot", ""))
	card.setup_item(item, slot_id, config)

	# Keep swipe scrolling active even when dragging on card content.
	var card_content := card.get_node_or_null("Content")
	if card_content is Control:
		card_content.mouse_filter = Control.MOUSE_FILTER_PASS
	var card_button := card.get_node_or_null("Button")
	if card_button is Control:
		card_button.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Connect signal
	card.card_pressed.connect(_on_card_pressed)
	
	return card

func _on_card_pressed(item_id: String, slot_id: String) -> void:
	# From Inventory -> Not equipped
	_show_item_popup(item_id, false, slot_id)

func _show_item_popup(item_id: String, is_equipped_in_slot: bool, slot_id: String) -> void:
	popup_item_id = item_id
	popup_is_equipped = is_equipped_in_slot
	popup_slot_id = slot_id
	
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var config = {
		"rarity_colors": _game_config.get("rarity_colors", {}),
		"placeholders": ship_opts.get("item_placeholders", {})
	}
	
	if _item_details_popup:
		_item_details_popup.setup(item_id, slot_id, is_equipped_in_slot, config)
		_item_details_popup.visible = true
		# Center on screen
		_item_details_popup.position = (size - _item_details_popup.size) / 2.0

func _on_popup_equip_requested(item_id: String, slot_id: String) -> void:
	# Resolve slot if generic (e.g. from Inventory "missile" -> "missile_1")
	var target_slot = slot_id
	var ship_data = DataManager.get_ship(selected_ship_id)
	var slots_def = ship_data.get("slots", {})
	
	# If generic (not present in slots_def), find best match
	if not slots_def.has(target_slot):
		# Find slots with matching type
		var candidates = []
		for s_key in slots_def:
			var s_data = slots_def[s_key]
			var s_type = str(s_data.get("type", ""))
			if s_type == target_slot or s_key.begins_with(target_slot + "_"):
				candidates.append(s_key)
		
		candidates.sort() # Ensure missile_1 comes before missile_2
		
		# Pick first empty, or just first
		var loadout_for_resolution = ProfileManager.get_loadout_for_ship(selected_ship_id)
		var best_slot = ""
		for cand in candidates:
			if not loadout_for_resolution.has(cand) or str(loadout_for_resolution[cand]) == "":
				best_slot = cand
				break
		
		if best_slot == "" and candidates.size() > 0:
			best_slot = candidates[0] # Overwrite first
			
		if best_slot != "":
			target_slot = best_slot
		else:
			# Fallback: If ship has NO slots defined (e.g. uses global slots like "shield", "engine" directly)
			# And candidates was empty (meaning target_slot wasn't found as a TYPE either)
			# We check if target_slot matches a known global slot ID.
			# If so, we use it directly.
			var global_slot = DataManager.get_slot(target_slot)
			if not global_slot.is_empty():
				# It's a valid global slot, and ship didn't specify restrictions. Use it.
				pass
			else:
				return

	# Check if slot is occupied (using resolved target_slot)
	var ship_loadout = ProfileManager.get_loadout_for_ship(selected_ship_id)
	var current_equipped = str(ship_loadout.get(target_slot, ""))
	
	if current_equipped != "":
		# Unequip current (pass SLOT ID)
		ProfileManager.unequip_item(selected_ship_id, target_slot)
		
	# Equip new
	ProfileManager.equip_item(selected_ship_id, target_slot, item_id)
	
	
	# Update UI but KEEP POPUP OPEN
	_update_slot_buttons()
	_update_inventory_grid()
	_update_ship_info(selected_ship_id)
	
	# Refresh Popup State (Toggle button to Unequip)
	# IMPORTANT: Pass resolved target_slot so popup knows where it is!
	_show_item_popup(item_id, true, target_slot)


func _on_popup_unequip_requested(item_id: String, slot_id: String) -> void:
	# Correctly pass slot_id instead of item_id
	ProfileManager.unequip_item(selected_ship_id, slot_id)
	
	
	# Update UI but KEEP POPUP OPEN
	_update_slot_buttons()
	_update_inventory_grid()
	_update_ship_info(selected_ship_id)
	
	# Refresh Popup State (Toggle button to Equip)
	# Pass slot_id (or generic if needed? Popup uses it for setup, but also sends it back).
	# If we unequipped, it's now in inventory.
	# But we want to show it as available.
	# We can pass generic slot type if we know it, or keep specific slot_id?
	# If we pass "missile_1", setup might fail to find "missile_1" data if item moved to inventory?
	# Actually item maintains its slot type.
	# Let's derive generic type from item data if possible, or just pass slot_id.
	# It shouldn't hurt.
	_show_item_popup(item_id, false, slot_id)

func _on_popup_recycle_pressed(item_id: String) -> void:
	var item = ProfileManager.get_item_by_id(item_id)
	if item.is_empty(): return
	
	# Calculate Value (Duplicate logic from ItemDetailsPopup for safety/speed)
	var rarity = str(item.get("rarity", "common"))
	var level = int(item.get("level", 1))
	
	var base_val: int = 5
	match rarity:
		"common": base_val = 5
		"uncommon": base_val = 15
		"rare": base_val = 40
		"epic": base_val = 100
		"legendary": base_val = 250
		"unique": base_val = 500
	var multiplier: float = 1.0 + (float(level) - 1.0) * 0.2
	var val = int(float(base_val) * multiplier)
	
	# Safety Check: Is this item equipped anywhere?
	# Relying on popup_is_equipped might fail if state is stale or confusing
	var loadout = ProfileManager.get_loadout_for_ship(selected_ship_id)
	for s_key in loadout:
		if str(loadout[s_key]) == item_id:
			ProfileManager.unequip_item(selected_ship_id, s_key)
			
	if val > 0:
		ProfileManager.add_crystals(val)
	ProfileManager.remove_item_from_inventory(item_id)
	
	if _item_details_popup: _item_details_popup.visible = false
	_update_inventory_grid()
	_update_slot_buttons()
	_update_ship_info(selected_ship_id)
	_apply_translations() # Refresh crystal count label





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
			# Reset filters to see the new item
			filter_slot = ""
			# if slot_filter: slot_filter.select(0)
			current_page = 0
			_update_inventory_grid()
		else:
			pass # Could not generate item: Inventory Full!
	else:
		pass # LootGenerator returned null!

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
	
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	
	# Super Power Styling
	var power_cfg: Dictionary = ship_opts.get("power_button", {}) if ship_opts.get("power_button") is Dictionary else {}
	var power_text_color: Color = Color(power_cfg.get("text_color", "#000000"))
	var power_font_size: int = int(power_cfg.get("font_size", 30))
	var power_letter_spacing: int = int(power_cfg.get("letter_spacing", 2))
	
	# Unique Power Styling
	var up_cfg: Dictionary = ship_opts.get("unique_power_button", {}) if ship_opts.get("unique_power_button") is Dictionary else {}
	var up_text_color: Color = Color(up_cfg.get("text_color", "#000000"))
	var up_font_size: int = int(up_cfg.get("font_size", 30))
	# up_letter_spacing unused

	
	# Update SP Info
	var ship := DataManager.get_ship(selected_ship_id)
	var sp_id := str(ship.get("special_power_id", ""))
	
	if sp_name_label:
		# Apply formatting 
		sp_name_label.add_theme_color_override("font_color", power_text_color)
		sp_name_label.add_theme_font_size_override("font_size", power_font_size)
		sp_name_label.add_theme_constant_override("letter_spacing", power_letter_spacing)
	
		if sp_id != "":
			var sp_data := DataManager.get_super_power(sp_id)
			sp_name_label.text = str(sp_data.get("name", sp_id))
		else:
			sp_name_label.text = LocaleManager.translate("ship_menu_none")

	# Update UP Button (Always visible, show "Aucun" with 0.7 opacity if none)
	if up_button:
		# Apply formatting
		up_button.mouse_filter = Control.MOUSE_FILTER_PASS
		up_button.add_theme_color_override("font_color", up_text_color)
		up_button.add_theme_color_override("font_hover_color", up_text_color)
		up_button.add_theme_color_override("font_pressed_color", up_text_color)
		up_button.add_theme_font_size_override("font_size", up_font_size)
		# Button doesn't support letter_spacing directly via theme constant
		
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

func _setup_filter_icons_ui() -> void:
	if not filters_container: return
	
	# Safeguard against duplication
	if filters_container.has_node("FilterIconsContainer"):
		return
	
	# Create a HBox for icons
	var icon_box = HBoxContainer.new()
	icon_box.name = "FilterIconsContainer"
	icon_box.add_theme_constant_override("separation", 10)
	
	# Add to FiltersContainer (Row 1)
	filters_container.add_child(icon_box)
	filters_container.move_child(icon_box, 0)
	
	_filter_icon_buttons.clear()
	
	# Populate Icons
	var slots := DataManager.get_slots()
	var ship_opts: Dictionary = _game_config.get("ship_options", {})
	var slot_icons_cfg: Dictionary = ship_opts.get("slot_icons", {})
	
	# 1. Add "ALL" Icon first
	var all_icon_path = str(slot_icons_cfg.get("all", ""))
	if all_icon_path != "" and ResourceLoader.exists(all_icon_path):
		var btn_all = TextureButton.new()
		btn_all.texture_normal = load(all_icon_path)
		btn_all.ignore_texture_size = true
		btn_all.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		
		# RESIZED: 50% larger (40 * 1.5 = 60)
		btn_all.custom_minimum_size = Vector2(60, 60)
		
		btn_all.mouse_filter = Control.MOUSE_FILTER_PASS # Allow scroll propagation
		btn_all.pressed.connect(func(): _on_filter_icon_pressed("all"))
		icon_box.add_child(btn_all)
		_filter_icon_buttons["all"] = btn_all
	
	# 2. Add Slot Icons
	for slot in slots:
		var slot_id = str(slot.get("id"))
		var icon_path = str(slot_icons_cfg.get(slot_id, ""))
		
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var btn = TextureButton.new()
			btn.texture_normal = load(icon_path)
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			# RESIZED: 50% larger (40 * 1.5 = 60)
			btn.custom_minimum_size = Vector2(60, 60)
			
			btn.mouse_filter = Control.MOUSE_FILTER_PASS # Allow scroll propagation
			
			btn.pressed.connect(func(): _on_filter_icon_pressed(slot_id))
			
			icon_box.add_child(btn)
			_filter_icon_buttons[slot_id] = btn
			
	_update_filter_visuals()

func _on_filter_icon_pressed(slot_id: String) -> void:
	if slot_id == "all":
		filter_slot = ""
	elif filter_slot == slot_id:
		filter_slot = "" # Deselect if already selected
	else:
		filter_slot = slot_id # Select new
	
	current_page = 0
	_update_filter_visuals()
	_update_inventory_grid()

func _setup_rarity_filter_ui() -> void:
	if not filters_container: return
	
	# Safeguard against duplication
	if filters_container.has_node("RarityFilterContainer"):
		return
	
	var rarity_box = HBoxContainer.new()
	rarity_box.name = "RarityFilterContainer"
	rarity_box.add_theme_constant_override("separation", 15)
	
	# Add to FiltersContainer (Row 2, after icons)
	filters_container.add_child(rarity_box)
	
	# RESTORED: "Slot:" or "Emplacement :" label Logic
	# Actually, user asked for "Empl. :" just BEFORE filters.
	# Since icons are the first row, we should add the label BEFORE the icon box.
	
	# Check if label already exists or add it
	var slot_label = filters_container.get_node_or_null("SlotLabelPlaceholder")
	if not slot_label:
		slot_label = Label.new()
		slot_label.name = "SlotLabelPlaceholder"
		slot_label.text = LocaleManager.translate("ship_menu_slot_label") # "Empl. :"
		# If translation missing, fallback
		if slot_label.text == "ship_menu_slot_label": slot_label.text = "Empl. :"
		
		# Insert at top (index 0), shifting icons to 1
		filters_container.add_child(slot_label)
		filters_container.move_child(slot_label, 0)
	else:
		slot_label.text = "Empl. :" # Force update or use translation
	
	rarity_filter_label = Label.new()
	rarity_filter_label.name = "RarityFilterLabel"
	rarity_filter_label.text = LocaleManager.translate("ship_menu_rarity_label")
	rarity_box.add_child(rarity_filter_label)
	
	var badges_box = HBoxContainer.new()
	badges_box.add_theme_constant_override("separation", 8)
	rarity_box.add_child(badges_box)
	
	_rarity_badge_buttons.clear()
	
	# Load assets config
	var rarity_assets: Dictionary = _game_config.get("rarity_filter_assets", {})
	
	# 1. "ALL" Button
	var btn_all = TextureButton.new()
	btn_all.name = "Rarity_all"
	
	# RESIZED: 50% larger than previous 45 (45 * 1.5 ~ 68)
	btn_all.custom_minimum_size = Vector2(68, 68)
	
	btn_all.ignore_texture_size = true
	btn_all.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_all.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var all_asset = str(rarity_assets.get("all", ""))
	if all_asset != "" and ResourceLoader.exists(all_asset):
		btn_all.texture_normal = load(all_asset)
	else:
		# Fallback: simple colored circle
		var style_all = StyleBoxFlat.new()
		style_all.set_corner_radius_all(34) # Adjusted for 68px
		style_all.bg_color = Color(0.1, 0.1, 0.1, 1)
		style_all.set_border_width_all(2)
		style_all.border_color = Color.WHITE
		# As texture button doesn't take stylebox easily without theme override,
		# we'll use a child Control or keep it simple.
		# Actually, TextureButton doesn't render stylebox panel. 
		# We'll stick to TextureButton but if no asset, we create a placeholder texture or use Button?
		# Let's use Button if no asset, but to keep consistent type in Dictionary, let's wrap or handle both.
		# Easier: Use TextureButton and generate placeholder texture if needed, OR just use Button and StyleBox if no asset.
		# Given the prompt asks for assets, we prioritize them.
		# If no asset, we use Button. To handle mixed types in _rarity_badge_buttons (Control), it's fine.
		btn_all = Button.new() # Re-instantiate as Button
		btn_all.custom_minimum_size = Vector2(30, 30)
		btn_all.add_theme_stylebox_override("normal", style_all)
		btn_all.add_theme_stylebox_override("hover", style_all)
		btn_all.add_theme_stylebox_override("pressed", style_all)
	
	btn_all.pressed.connect(func(): _on_rarity_filter_pressed(""))
	badges_box.add_child(btn_all)
	
	# Highlight container (OVERLAY now, not behind)
	if btn_all is TextureButton:
		var highlight = TextureRect.new()
		highlight.name = "Highlight"
		highlight.visible = false
		highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
		highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# CHANGED: On top (z-index logic or just draw order). 
		# Since it's a child added AFTER texture_normal is drawn by the button itself? 
		# TextureButton draws its generic texture. Children are drawn on top by default.
		# "show_behind_parent" was ON. We turn it OFF.
		highlight.show_behind_parent = false 
		
		# User request: "Mets juste sur un layer au dessus" (z-index/layer on top)
		# Adding as child of TextureButton draws it on top of the button's texture.
		# Ensure Z-Index is high just in case, though tree order usually suffices for controls.
		highlight.z_index = 1
		
		btn_all.add_child(highlight)
	
	_rarity_badge_buttons[""] = btn_all
	
	# 2. Rarity Buttons
	var rarities = DataManager.get_rarities()
	for r in rarities:
		var r_id = str(r.get("id"))
		var r_asset = str(rarity_assets.get(r_id, ""))
		
		var btn: Control
		
		if r_asset != "" and ResourceLoader.exists(r_asset):
			btn = TextureButton.new()
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			# RESIZED: 50% larger than 45 (45 * 1.5 ~ 68)
			btn.custom_minimum_size = Vector2(68, 68)
			
			(btn as TextureButton).texture_normal = load(r_asset)
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			var highlight = TextureRect.new()
			highlight.name = "Highlight"
			highlight.visible = false
			highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
			highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			# OVERLAY (On top + z-index)
			highlight.show_behind_parent = false
			highlight.z_index = 1
			
			btn.add_child(highlight)
			
		else:
			# Fallback to colored button
			var r_color_hex = str(r.get("color", "#FFFFFF"))
			var r_color = Color.html(r_color_hex)
			
			btn = Button.new()
			# RESIZED
			btn.custom_minimum_size = Vector2(68, 68)
			var style = StyleBoxFlat.new()
			style.set_corner_radius_all(34)
			style.bg_color = r_color
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
			
		if btn.has_signal("pressed"):
			btn.pressed.connect(func(): _on_rarity_filter_pressed(r_id))
			
		badges_box.add_child(btn)
		_rarity_badge_buttons[r_id] = btn
		
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rarity_box.add_child(spacer)
	
	multi_recycle_btn = TextureButton.new()
	var recycle_icon_path = "res://assets/ui/icons/crystal.png"
	if ResourceLoader.exists(recycle_icon_path):
		multi_recycle_btn.texture_normal = load(recycle_icon_path)

	
	# RESIZED: 50% larger (40 * 1.5 = 60)
	multi_recycle_btn.custom_minimum_size = Vector2(60, 60)
	
	multi_recycle_btn.ignore_texture_size = true
	multi_recycle_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	multi_recycle_btn.modulate = Color(1.0, 0.3, 0.3, 1.0)
	multi_recycle_btn.pressed.connect(_on_multi_recycle_pressed)
	rarity_box.add_child(multi_recycle_btn)
	
	_update_filter_visuals()

func _on_rarity_filter_pressed(rarity_id: String) -> void:
	if filter_rarity == rarity_id:
		filter_rarity = ""
	else:
		filter_rarity = rarity_id
	current_page = 0
	_update_filter_visuals()
	_update_inventory_grid()

func _on_multi_recycle_pressed() -> void:
	var filtered = _get_filtered_inventory()
	var equipped_ids = ProfileManager.get_all_equipped_item_ids()
	var items_to_recycle = []
	var total_crystals = 0
	
	for item in filtered:
		var i_id = str(item.get("id", ""))
		if not i_id in equipped_ids:
			items_to_recycle.append(i_id)
			var r_id = str(item.get("rarity", "common"))
			var level = int(item.get("upgrade", 0)) + 1
			var base_val: int = 5
			match r_id:
				"common": base_val = 5
				"uncommon": base_val = 15
				"rare": base_val = 40
				"epic": base_val = 100
				"legendary": base_val = 250
				"unique": base_val = 500
			var multiplier: float = 1.0 + (float(level) - 1.0) * 0.2
			total_crystals += int(float(base_val) * multiplier)
			
	if items_to_recycle.is_empty(): return
	_show_multi_recycle_confirmation(items_to_recycle, total_crystals)

func _show_multi_recycle_confirmation(items_to_recycle: Array, total_crystals: int) -> void:
	var popup = PanelContainer.new()
	# Start with width only; height will fit content.
	popup.custom_minimum_size = Vector2(420, 0)
	
	var pop_cfg = _game_config.get("popups", {})
	var bg_cfg = pop_cfg.get("background", {})
	var btn_cfg = pop_cfg.get("button", {})
	var recycle_cfg = pop_cfg.get("recycle", {})
	
	var style = StyleBoxTexture.new()
	var bg_asset = str(bg_cfg.get("asset", "res://assets/ui/popup_background.png"))
	if ResourceLoader.exists(bg_asset): style.texture = load(bg_asset)
	popup.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	# Keep extra safety padding so text/buttons never overlap popup frame.
	var m_val = 40
	margin.add_theme_constant_override("margin_left", m_val)
	margin.add_theme_constant_override("margin_right", m_val)
	margin.add_theme_constant_override("margin_top", m_val)
	margin.add_theme_constant_override("margin_bottom", m_val)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = LocaleManager.translate("ship_menu_multi_recycle_popup_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(bg_cfg.get("font_size", 24)) + 4)
	title.add_theme_color_override("font_color", Color.html(str(bg_cfg.get("text_color", "#000000"))))
	vbox.add_child(title)
	# Message
	var msg = Label.new()
	var template = LocaleManager.translate("ship_menu_multi_recycle_confirm")
	var item_suffix := "s" if items_to_recycle.size() > 1 else ""
	msg.text = template.replace("{count}", str(items_to_recycle.size())).replace("{crystals}", str(total_crystals)).replace("{item_suffix}", item_suffix)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.custom_minimum_size = Vector2(340, 0)
	msg.add_theme_font_size_override("font_size", int(recycle_cfg.get("font_size", 16)))
	msg.add_theme_color_override("font_color", Color.html(str(bg_cfg.get("text_color", "#000000"))))
	msg.add_theme_constant_override("letter_spacing", int(bg_cfg.get("letter_spacing", 0)))
	vbox.add_child(msg)
	
	# Spacer
	var sps = Control.new()
	sps.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(sps)
	
	# Buttons
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 30)
	vbox.add_child(hbox)
	
	var btn_asset = str(btn_cfg.get("asset", "res://assets/ui/button.png"))
	var btn_style = StyleBoxTexture.new()
	if ResourceLoader.exists(btn_asset):
		btn_style.texture = load(btn_asset)
	
	var btn_text_color = Color.html(str(btn_cfg.get("text_color", "#000000")))
	var btn_font_size = int(btn_cfg.get("font_size", 18))
	var btn_ls = int(btn_cfg.get("letter_spacing", 0))
	
	# Confirm
	var btn_confirm = Button.new()
	btn_confirm.text = LocaleManager.translate("confirm")
	btn_confirm.add_theme_stylebox_override("normal", btn_style)
	btn_confirm.add_theme_stylebox_override("hover", btn_style)
	btn_confirm.add_theme_stylebox_override("pressed", btn_style)
	btn_confirm.add_theme_color_override("font_color", btn_text_color)
	btn_confirm.add_theme_font_size_override("font_size", btn_font_size)
	btn_confirm.add_theme_constant_override("letter_spacing", btn_ls)
	btn_confirm.custom_minimum_size = Vector2(160, 50)
	btn_confirm.pressed.connect(func():
		_confirm_multi_recycle(items_to_recycle, total_crystals)
		popup.queue_free()
	)
	hbox.add_child(btn_confirm)
	
	# Cancel
	var btn_cancel = Button.new()
	btn_cancel.text = LocaleManager.translate("cancel")
	btn_cancel.add_theme_stylebox_override("normal", btn_style)
	btn_cancel.add_theme_stylebox_override("hover", btn_style)
	btn_cancel.add_theme_stylebox_override("pressed", btn_style)
	btn_cancel.add_theme_color_override("font_color", btn_text_color)
	btn_cancel.add_theme_font_size_override("font_size", btn_font_size)
	btn_cancel.add_theme_constant_override("letter_spacing", btn_ls)
	btn_cancel.custom_minimum_size = Vector2(160, 50)
	btn_cancel.pressed.connect(popup.queue_free)
	hbox.add_child(btn_cancel)
	
	add_child(popup)
	
	# Center Popup
	popup.layout_mode = 1 # Anchors
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	popup.z_index = 100 # Ensure on top

	# Fit popup to content size (and clamp to viewport) to avoid stretched/tall deformation.
	await get_tree().process_frame
	var content_min: Vector2 = margin.get_combined_minimum_size()
	var viewport_size := get_viewport_rect().size
	var desired_w: float = clampf(maxf(420.0, content_min.x), 420.0, maxf(420.0, viewport_size.x - 40.0))
	var desired_h: float = clampf(content_min.y, 0.0, maxf(200.0, viewport_size.y - 60.0))
	popup.custom_minimum_size = Vector2(desired_w, desired_h)
	popup.offset_left = -desired_w / 2.0
	popup.offset_right = desired_w / 2.0
	popup.offset_top = -desired_h / 2.0
	popup.offset_bottom = desired_h / 2.0

func _confirm_multi_recycle(item_ids: Array, crystals_earned: int) -> void:
	for i_id in item_ids:
		ProfileManager.remove_item_from_inventory(i_id)
	ProfileManager.add_crystals(crystals_earned)
	ProfileManager.save_to_disk()
	_update_inventory_grid()
	
	# Refresh ship stats header immediately (includes crystals).
	var ship_id := selected_ship_id if selected_ship_id != "" else ProfileManager.get_active_ship_id()
	if ship_id != "":
		_update_ship_info(ship_id)
	
	_apply_translations()

func _update_filter_visuals() -> void:
	for sid in _filter_icon_buttons:
		var btn: TextureButton = _filter_icon_buttons[sid]
		var is_selected: bool = (sid == "all" and filter_slot == "") or (sid == filter_slot)
		
		if is_selected:
			btn.modulate = Color(1, 1, 1, 1)
		else:
			btn.modulate = Color(0.3, 0.3, 0.3, 1) # Grayscale/Dimmed effect
			
	var highlight_asset = str(_game_config.get("rarity_highlight", ""))
	
	for rid in _rarity_badge_buttons:
		var btn: Control = _rarity_badge_buttons[rid]
		var is_selected: bool = (rid == filter_rarity)
		
		if btn is TextureButton:
			# Asset mode
			var highlight = btn.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = is_selected
				if highlight.texture == null and highlight_asset != "" and ResourceLoader.exists(highlight_asset):
					highlight.texture = load(highlight_asset)
			
			# Optional: Slight scale or modualte if not selected?
			if is_selected:
				btn.modulate = Color(1, 1, 1, 1)
				btn.scale = Vector2(1.1, 1.1)
				btn.pivot_offset = btn.size / 2.0
			else:
				btn.modulate = Color(0.7, 0.7, 0.7, 1)
				btn.scale = Vector2(1.0, 1.0)
				btn.pivot_offset = btn.size / 2.0
				
		elif btn is Button:
			# Validating if it has stylebox (Fallback mode)
			if btn.has_theme_stylebox_override("normal"):
				var style = btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
				if style:
					if is_selected:
						style.set_border_width_all(3)
						style.border_color = Color.YELLOW
						btn.scale = Vector2(1.1, 1.1)
						btn.pivot_offset = btn.size / 2.0
					else:
						style.set_border_width_all(0) # or 1
						# style.border_color = Color.TRANSPARENT
						btn.scale = Vector2(1.0, 1.0)
						btn.pivot_offset = btn.size / 2.0
					
					btn.add_theme_stylebox_override("normal", style)
					btn.add_theme_stylebox_override("hover", style)
					btn.add_theme_stylebox_override("pressed", style)

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
	var equipped_ids := ProfileManager.get_all_equipped_item_ids()
	var filtered: Array = []
	
	# Filtre par slot et exclude equipped
	for item in inv:
		if item is Dictionary:
			var item_dict := item as Dictionary
			var i_id = str(item_dict.get("id", ""))
			
			# Exclude equipped
			if i_id in equipped_ids:
				continue
				
			var matches_slot = filter_slot == "" or str(item_dict.get("slot", "")) == filter_slot
			var matches_rarity = filter_rarity == "" or str(item_dict.get("rarity", "")) == filter_rarity
			if matches_slot and matches_rarity:
				filtered.append(item_dict)
	
	# Tri par rareté (Default: Descending)
	# Always sort by rarity descending (Legendary -> Common)
	var rarity_order := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4, "unique": 5}
	filtered.sort_custom(func(a, b):
		var ra: int = int(rarity_order.get(str(a.get("rarity", "common")), 0))
		var rb: int = int(rarity_order.get(str(b.get("rarity", "common")), 0))
		# If rarity is equal, maybe sort by name or power?
		if ra == rb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return ra > rb # Descending
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
	
	# MAX LEVEL CHECK (Now 9 instead of 10)
	if level >= 9:
		push_warning("[ShipMenu] Item already at max level (9)!")
		return

	# COST CHECK
	var upgrade_data = DataManager.get_level_upgrade_data(level) 
	var next_data = upgrade_data.get("upgrade_to_next", {})
	var cost = int(next_data.get("cost", 999999))
	
	var user_crystals = ProfileManager.get_crystals()
	if user_crystals < cost:
		# TODO: Feedback visual "Not enough crystals"
		return

	# Deduct Cost
	ProfileManager.remove_crystals(cost)
	
	# Disable button temporarily
	if popup_upgrade_btn: 
		popup_upgrade_btn.disabled = true
		popup_upgrade_btn.text = LocaleManager.translate("upgrading") + "..."
	
	# Disable NEW popup button
	if _item_details_popup and _item_details_popup.upgrade_btn:
		_item_details_popup.upgrade_btn.disabled = true
		_item_details_popup.upgrade_btn.text = LocaleManager.translate("upgrading") + "..."
	
	# CRAFTING DELAY (3 seconds)
	var sh_opts = _game_config.get("ship_menu", {})
	
	# 1. LOOP SOUND
	var loop_sound_path = str(sh_opts.get("upgrade_craft_sound", ""))
	var loop_player: AudioStreamPlayer = null
	if loop_sound_path != "" and ResourceLoader.exists(loop_sound_path):
		loop_player = AudioStreamPlayer.new()
		loop_player.stream = load(loop_sound_path)
		add_child(loop_player)
		loop_player.play()
	else:
		pass # Craft loop sound not found: 
		
	# 2. CRAFT ANIM
	var craft_anim_path = str(sh_opts.get("upgrade_craft_anim", ""))
	var craft_anim_duration: float = maxf(0.0, float(sh_opts.get("upgrade_craft_anim_duration", 0.0)))
	var craft_anim_loop: bool = bool(sh_opts.get("upgrade_craft_anim_loop", true))
	var craft_anim_node: AnimatedSprite2D = null
	if craft_anim_path != "" and ResourceLoader.exists(craft_anim_path):
		var frames: Resource = load(craft_anim_path)
		if frames is SpriteFrames:
			craft_anim_node = AnimatedSprite2D.new()
			VFXManager.play_sprite_frames(
				craft_anim_node,
				frames as SpriteFrames,
				&"default",
				craft_anim_loop,
				craft_anim_duration
			)
			# No Z-index, put behind text (child 0)
			# craft_anim_node.z_index = 20 
			craft_anim_node.scale = Vector2(2.0, 2.0)
			
			if is_instance_valid(item_popup):
				item_popup.add_child(craft_anim_node)
				item_popup.move_child(craft_anim_node, 0)
				craft_anim_node.centered = true
				craft_anim_node.position = item_popup.size / 2.0
	
	# WAIT
	await get_tree().create_timer(3.0).timeout
	
	# CLEANUP LOOP
	if is_instance_valid(loop_player):
		loop_player.stop()
		loop_player.queue_free()
		
	if is_instance_valid(craft_anim_node):
		craft_anim_node.queue_free()
	
	# RNG LOGIC
	var roll = randi() % 100 # 0-99
	var tier = "decent"
	var tier_label = "Decent Upgrade"
	
	# Weights: Decent 40, Great 45, Perfect 15
	# < 40 = decent (40%)
	# < 85 = great (45%)
	# >= 85 = perfect (15%)
	
	if roll < 40:
		tier = "decent"
	elif roll < 85:
		tier = "great"
	else:
		tier = "perfect"
		
	var tiers_cfg = next_data.get("tiers", {})
	var tier_data = tiers_cfg.get(tier, {})
	# Localize the tier label
	tier_label = LocaleManager.translate("upgrade_" + tier)
	if tier_label == "upgrade_" + tier: # Fallback if missing
		tier_label = str(tier_data.get("label", tier.capitalize()))
	
	# Data multipliers
	var mult_min = float(tier_data.get("multiplier_min", 1.05))
	var mult_max = float(tier_data.get("multiplier_max", 1.10))
	var multiplier = randf_range(mult_min, mult_max)
	
	
	# AUDIO FEEDBACK
	sh_opts = _game_config.get("ship_menu", {})
	var sound_path = str(sh_opts.get("upgrade_sound", ""))
	if sound_path != "" and ResourceLoader.exists(sound_path):
		# Assuming simple AudioManager
		# AudioManager.play_sfx(sound_path)
		var audio = AudioStreamPlayer.new()
		audio.stream = load(sound_path)
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)

	# APPLY UPGRADE TO ITEM
	# 1. Update Stats
	var stats = item.get("stats", {})
	for key in stats:
		var val = float(stats[key])
		# Apply multiplier and ceil to ensure progress
		# Special handling for small values (fire_rate 0.3) vs big (power 100, crit 5)
		if val < 1.0 and val > 0.0:
			# Percentage-like stats: simple multiply keeps them small
			stats[key] = val * multiplier
		else:
			# Large numbers: ceil to avoid 10.0 -> 10.05 not showing change
			stats[key] = ceil(val * multiplier)
			
	item["stats"] = stats
	item["level"] = level + 1
	
	# 2. Save
	ProfileManager.save_to_disk()
	
	# VISUAL FEEDBACK (Animation & Delay)
	_show_upgrade_feedback(tier, tier_label)
	
	# Wait for animation
	await get_tree().create_timer(1.5).timeout
	
	if popup_upgrade_btn: 
		popup_upgrade_btn.disabled = false
	
	# Refresh UI
	_show_item_popup(popup_item_id, popup_is_equipped, popup_slot_id)
	_update_inventory_grid()
	_update_slot_buttons()
	if popup_is_equipped and selected_ship_id != "":
		_update_ship_info(selected_ship_id)
	_apply_translations() # Refresh crystal count

func _show_upgrade_feedback(tier: String, label_text: String) -> void:
	# 1. Background Anim (Tier Based)
	var sh_opts: Dictionary = _game_config.get("ship_menu", {})
	var anim_path = str(sh_opts.get("upgrade_anim_" + tier, ""))
	var anim_duration: float = maxf(0.0, float(sh_opts.get("upgrade_anim_" + tier + "_duration", 0.0)))
	var anim_loop: bool = bool(sh_opts.get("upgrade_anim_" + tier + "_loop", false))
	
	if anim_path != "" and ResourceLoader.exists(anim_path):
		var frames: Resource = load(anim_path)
		if frames is SpriteFrames:
			var anim = AnimatedSprite2D.new()
			VFXManager.play_sprite_frames(
				anim,
				frames as SpriteFrames,
				&"default",
				anim_loop,
				anim_duration
			)
			anim.scale = Vector2(2.0, 2.0)
			
			item_popup.add_child(anim)
			item_popup.move_child(anim, 0) # Background
			anim.centered = true
			anim.position = item_popup.size / 2.0
			
			# Cleanup after 2 seconds
			get_tree().create_timer(2.0).timeout.connect(anim.queue_free)
	
	# 2. Success Text Label
	var color = Color.WHITE
	if tier == "great": color = Color.YELLOW
	if tier == "perfect": color = Color.MAGENTA
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	
	item_popup.add_child(lbl)
	# Position absolutely: Center X, Y=100 (below header/badge)
	lbl.global_position = item_popup.global_position + Vector2(item_popup.size.x / 2.0, 100) - Vector2(lbl.size.x / 2.0, 0)
	# Since size isn't calculated yet, use anchors or center alignment
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.position.y = 100 # Offset Y
	lbl.z_index = 30 # On top of everything
	
	# Animation: Scale up + Fade out
	lbl.pivot_offset = lbl.size / 2.0 # Center pivot for scaling
	# Wait one frame for size update for pivot
	await get_tree().process_frame
	lbl.pivot_offset = lbl.size / 2.0
	
	var tween = create_tween()
	lbl.scale = Vector2(0.5, 0.5)
	lbl.modulate.a = 0.0
	tween.tween_property(lbl, "scale", Vector2(1.2, 1.2), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(lbl, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tween.tween_callback(lbl.queue_free)





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
	# Reuse the gameplay stat pipeline so ShipMenu and in-game values stay aligned,
	# including Pew Pew/Paragon modifiers from SkillManager.
	var final_stats: Dictionary = {}
	if StatsCalculator and StatsCalculator.has_method("calculate_ship_stats"):
		final_stats = StatsCalculator.calculate_ship_stats(ship_id)
	
	if final_stats.is_empty():
		var base_ship = DataManager.get_ship(ship_id)
		var base_stats = base_ship.get("stats", {})
		if base_stats is Dictionary:
			final_stats = (base_stats as Dictionary).duplicate(true)
		else:
			final_stats = {}
	
	# Ensure required keys exist for ShipMenu display calculations.
	final_stats["power"] = float(final_stats.get("power", 10.0))
	final_stats["max_hp"] = float(final_stats.get("max_hp", 100.0))
	final_stats["move_speed"] = float(final_stats.get("move_speed", 200.0))
	final_stats["fire_rate"] = float(final_stats.get("fire_rate", 0.3))
	final_stats["missile_speed_pct"] = float(final_stats.get("missile_speed_pct", 100.0))
	final_stats["crit_chance"] = float(final_stats.get("crit_chance", 5.0))
	final_stats["dodge_chance"] = float(final_stats.get("dodge_chance", 2.0))
	final_stats["special_damage"] = float(final_stats.get("special_damage", 0.0))
	final_stats["special_cd"] = max(1.0, float(final_stats.get("special_cd", 10.0)))
	
	
	# Composite Scores for UI
	# Missile Score: (fire_rate + missile_speed_pct) * power (User requested formula)
	# Note: fire_rate here is refire delay (0.5 etc), but user wants to add it.
	var fr = float(final_stats.get("fire_rate", 0.5))
	var m_spd = float(final_stats.get("missile_speed_pct", 100.0))
	var pwr = float(final_stats.get("power", 10.0))
	final_stats.missile_score = int(round((fr + m_spd / 100.0) * pwr))
	
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
	if not parent: return
	
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
		_add_ship_stat_icon(icon_control, icon_path, w, h, cfg)
		
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

func _add_stat_summary_shop_button(parent: Control, cfg: Dictionary) -> void:
	if not parent: return
	
	var item_hbox = HBoxContainer.new()
	item_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(item_hbox)
	
	var icon_path = str(cfg.get("icon_asset", ""))
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		var ui_icons: Dictionary = _game_config.get("ui_icons", {})
		var fallback_shop_icon = str(ui_icons.get("shop_icon", ""))
		if fallback_shop_icon != "" and ResourceLoader.exists(fallback_shop_icon):
			icon_path = fallback_shop_icon
	
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		var default_icon = "res://assets/ui/icons/crystal.png"
		if ResourceLoader.exists(default_icon):
			icon_path = default_icon
	
	var w = int(cfg.get("icon_width", 30) * 2.2)
	var h = int(cfg.get("icon_height", 30) * 2.2)
	
	var shop_btn := TextureButton.new()
	shop_btn.custom_minimum_size = Vector2(w, h)
	shop_btn.ignore_texture_size = true
	shop_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	shop_btn.pressed.connect(_on_shop_button_pressed)
	item_hbox.add_child(shop_btn)
	
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return
	
	var icon_control = Control.new()
	icon_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_btn.add_child(icon_control)
	_add_ship_stat_icon(icon_control, icon_path, w, h, cfg)

func _add_ship_stat_icon(icon_parent: Control, icon_path: String, w: int, h: int, cfg: Dictionary) -> void:
	if not icon_parent:
		return
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return
	
	var icon_res: Resource = load(icon_path)
	var repeat_seconds: float = maxf(0.0, float(cfg.get("animation_repeat_seconds", 0.0)))
	var icon_anim_duration: float = maxf(0.0, float(cfg.get("icon_anim_duration", 0.0)))
	var icon_anim_loop: bool = bool(cfg.get("icon_anim_loop", repeat_seconds <= 0.0))
	
	if icon_res is Texture2D:
		var icon = TextureRect.new()
		icon.texture = icon_res as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_parent.add_child(icon)
		return
	
	if icon_res is SpriteFrames:
		var source_frames := icon_res as SpriteFrames
		var anim_name: StringName = _get_first_spriteframes_animation(source_frames)
		if anim_name == &"":
			return
		
		var frames_for_playback: SpriteFrames = source_frames
		
		var anim = AnimatedSprite2D.new()
		anim.sprite_frames = frames_for_playback
		anim.centered = true
		anim.position = Vector2(w / 2.0, h / 2.0)
		
		var frame_tex = _get_spriteframes_first_frame(frames_for_playback)
		if frame_tex:
			var frame_size = frame_tex.get_size()
			if frame_size.x > 0.0 and frame_size.y > 0.0:
				var fit_scale := minf(float(w) / frame_size.x, float(h) / frame_size.y)
				anim.scale = Vector2(fit_scale, fit_scale)
		
		icon_parent.add_child(anim)
		_play_ship_stat_icon(anim, anim_name, repeat_seconds, icon_anim_duration, icon_anim_loop)

func _play_ship_stat_icon(
	anim: AnimatedSprite2D,
	anim_name: StringName,
	repeat_seconds: float,
	play_duration: float,
	play_loop: bool
) -> void:
	if not anim:
		return
	
	var source_frames: SpriteFrames = anim.sprite_frames
	if source_frames == null:
		return
	VFXManager.play_sprite_frames(anim, source_frames, anim_name, play_loop, play_duration)
	if repeat_seconds <= 0.0:
		return
	
	_repeat_ship_stat_icon(anim, anim_name, repeat_seconds, play_duration, play_loop)

func _repeat_ship_stat_icon(
	anim: AnimatedSprite2D,
	anim_name: StringName,
	repeat_seconds: float,
	play_duration: float,
	play_loop: bool
) -> void:
	while is_instance_valid(anim):
		var tree := anim.get_tree()
		if tree == null:
			return
		await tree.create_timer(repeat_seconds).timeout
		if not is_instance_valid(anim):
			return
		var source_frames: SpriteFrames = anim.sprite_frames
		if source_frames == null:
			return
		VFXManager.play_sprite_frames(anim, source_frames, anim_name, play_loop, play_duration)

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
		_add_ship_stat_icon(icon_control, icon_path, w, h, cfg)
		
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
			# Crit/Dodge stored in 1-100 format, display directly as percentage
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

func _fix_mobile_scroll_recursive(node: Node) -> void:
	# Si c'est un élément d'interface (Control)
	if node is Control:
		# Si c'est un bouton ou quelque chose d'interactif
		if node is Button or node is TextureButton or node is OptionButton:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
			# Cas particulier : parfois les boutons ont des enfants (labels, icones) qui bloquent
			# On continuera la récursion pour les mettre en IGNORE
		
		# Si c'est purement visuel (Label, TextureRect, Panel, Barres, etc.)
		# ET que ce n'est pas le ScrollContainer lui-même
		elif not node is ScrollContainer and not node is VScrollBar and not node is HScrollBar:
			# Preserve explicit PASS already configured for swipe propagation.
			if node.mouse_filter != Control.MOUSE_FILTER_PASS:
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# On applique la même chose à tous les enfants (Récursion)
	for child in node.get_children():
		_fix_mobile_scroll_recursive(child)


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

func _cleanup_orphaned_icons() -> void:
	# Safety cleanup for accumulating icons in DebugSection
	if generate_item_button:
		var parent = generate_item_button.get_parent()
		if parent:
			for child in parent.get_children():
				if child != generate_item_button:
					# Clean up any accumulated icons/controls that might have been added by mistake
					# Avoid deleting legitimate layout nodes (Label, HSeparator)
					if child is HSeparator or child is Label or child is Button:
						continue
						
					child.queue_free()


func _add_spacer(parent: Control, height: float, s_name: String, index: int = -1) -> Control:
	var existing = parent.get_node_or_null(s_name)
	if existing:
		existing.custom_minimum_size.y = height
		return existing
	var s = Control.new()
	s.name = s_name
	s.custom_minimum_size.y = height
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)
	if index >= 0:
		parent.move_child(s, index)
	return s
