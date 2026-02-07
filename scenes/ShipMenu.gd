extends Control

## ShipMenu — Menu de sélection de vaisseau et d'équipement.
## Accessible depuis l'écran d'accueil via le bouton "Vaisseau".
## Le vaisseau sélectionné ici s'applique à toutes les missions.



# =============================================================================
# CONSTANTES


# =============================================================================

const INVENTORY_COLUMNS := 3
const INVENTORY_ROWS := 3
const ITEM_CARD_SIZE := Vector2(100, 100)



# =============================================================================
# RÉFÉRENCES UI


# =============================================================================

@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var content: VBoxContainer = $MarginContainer/ScrollContainer/Content
@onready var title_label: Label = $MarginContainer/ScrollContainer/Content/Header/TitleLabel
@onready var crystal_label: Label = $MarginContainer/ScrollContainer/Content/CrystalContainer/CrystalLabel
@onready var ship_scroll: ScrollContainer = %ShipScroll
@onready var ship_cards_container: GridContainer = %ShipCardsContainer
@onready var ship_prev_btn: Button = %ShipPrevBtn
@onready var ship_next_btn: Button = %ShipNextBtn
@onready var ship_unlock_btn: Button = %ShipUnlockButton
@onready var unlock_popup: PanelContainer = %UnlockPopup
@onready var unlock_message: Label = %Message
@onready var confirm_unlock_btn: Button = %ConfirmUnlockBtn
@onready var cancel_unlock_btn: Button = %CancelUnlockBtn
@onready var ship_info_label: Label = $MarginContainer/ScrollContainer/Content/ShipSection/ShipInfoLabel
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
var _game_config: Dictionary = {}
var _recycle_value: int = 0
var slot_buttons: Dictionary = {}  # slot_id -> Button
var inventory_cards: Array = []  # Array of item card Controls

# Pour le popup
var popup_item_id: String = ""
var popup_is_equipped: bool = false
var popup_slot_id: String = ""

# Pagination et filtres
var current_page: int = 0
var items_per_page: int = 9  # 3 colonnes × 3 lignes
var filter_slot: String = ""  # "" = tous, sinon slot_id spécifique
var filter_rarity_asc: bool = false  # false = descendant, true = ascendant
var filter_rarity_enabled: bool = false



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
	var shop_btn: Button = %ShopButton
	if shop_btn: shop_btn.pressed.connect(_on_shop_button_pressed)
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
	
	_load_game_config()
	_apply_popup_style()
	
	# Initialisation
	_load_ships()
	_create_slot_buttons()
	_update_slot_buttons()
	_update_inventory_grid()

func _apply_translations() -> void:
	title_label.text = LocaleManager.translate("ship_menu_title")
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
	var slot_filter_label := %SlotFilterLabel if has_node("%SlotFilterLabel") else $MarginContainer/ScrollContainer/Content/FiltersContainer/SlotFilterLabel
	if slot_filter_label:
		slot_filter_label.text = LocaleManager.translate("ship_menu_slot_label")
	
	var crystals: int = ProfileManager.get_crystals()
	if crystal_label:
		crystal_label.text = "💎 " + str(crystals)



# =============================================================================
# VAISSEAUX


# =============================================================================

func _load_ships() -> void:
	for child in ship_cards_container.get_children():
		child.queue_free()
	
	var all_ships := DataManager.get_ships()
	var active_id := ProfileManager.get_active_ship_id()
	var unlocked_ids := ProfileManager.get_unlocked_ships()
	
	if selected_ship_id == "":
		selected_ship_id = active_id
	
	for ship in all_ships:
		if ship is Dictionary:
			var ship_dict := ship as Dictionary
			var s_id := str(ship_dict.get("id", ""))
			var s_name_key := "ship." + s_id + ".name"
			var s_name := LocaleManager.translate(s_name_key)
			if s_name == s_name_key: s_name = str(ship_dict.get("name", s_id))
			
			var is_unlocked := unlocked_ids.has(s_id)
			var is_selected := (s_id == selected_ship_id)
			
			_create_ship_card(s_id, s_name, is_unlocked, is_selected, ship_dict)
	
	_update_ship_info(selected_ship_id)
	_update_scroll_buttons()

func _create_ship_card(ship_id: String, ship_name: String, is_unlocked: bool, is_selected: bool, ship_data: Dictionary) -> void:
	# Card Container (PanelContainer for background)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120) # Height fixed, width expands
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Load ship visual asset as background
	var visual: Variant = ship_data.get("visual", {})
	var asset_path := ""
	if visual is Dictionary:
		asset_path = str((visual as Dictionary).get("asset", ""))
	
	# Background TextureRect
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if asset_path != "" and ResourceLoader.exists(asset_path):
		bg.texture = load(asset_path)
	else:
		# Fallback grey
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.3, 0.3, 1)
		card.add_theme_stylebox_override("panel", style)
	
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)
	
	# Greyed out if locked
	if not is_unlocked:
		bg.modulate = Color(0.5, 0.5, 0.5, 1)
	
	# Footer Container (at bottom)
	var footer := PanelContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -30
	footer.offset_bottom = 0
	
	var footer_style := StyleBoxFlat.new()
	if is_selected:
		footer_style.bg_color = Color(0.2, 0.7, 0.3, 0.9) # Green
	else:
		footer_style.bg_color = Color(0.3, 0.3, 0.3, 0.9) # Grey
	footer.add_theme_stylebox_override("panel", footer_style)
	card.add_child(footer)
	
	# Footer HBox (Name + Checkmark)
	var footer_hbox := HBoxContainer.new()
	footer_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(footer_hbox)
	
	var name_label := Label.new()
	name_label.text = ship_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(name_label)
	
	if is_selected:
		var check := Label.new()
		check.text = "✓"
		check.modulate = Color(0.7, 0.7, 0.7, 1) # Grey checkmark
		footer_hbox.add_child(check)
	
	# Invisible button for click handling
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func(): _on_ship_card_pressed(ship_id))
	card.add_child(btn)
	
	# Store metadata for overlay logic
	card.set_meta("ship_id", ship_id)
	card.set_meta("is_unlocked", is_unlocked)
	card.set_meta("price", int(ship_data.get("crystal_price", 0)))
	
	ship_cards_container.add_child(card)

func _on_ship_card_pressed(ship_id: String) -> void:
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
	
	# Afficher les infos du vaisseau localisées
	var ship := DataManager.get_ship(ship_id)
	var ship_name := LocaleManager.translate("ship." + ship_id + ".name")
	var desc := LocaleManager.translate("ship." + ship_id + ".desc")
	var stats: Variant = ship.get("stats", {})
	
	var info_text := ship_name + "\n"
	info_text += desc + "\n\n"
	
	if stats is Dictionary:
		var stats_dict := stats as Dictionary
		info_text += LocaleManager.translate("stat_power") + ": " + str(stats_dict.get("power", 0)) + "\n"
		info_text += LocaleManager.translate("stat_hp") + ": " + str(stats_dict.get("max_hp", 0)) + "\n"
		info_text += LocaleManager.translate("stat_speed") + ": " + str(stats_dict.get("move_speed", 0))
	
	
	ship_info_label.text = info_text
	
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
			var existing_overlay := card.get_node_or_null("PurchaseOverlay")
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
	# Similaire à _on_ship_card_pressed mais juste pour l'update UI info
	var ship := DataManager.get_ship(ship_id)
	var stats: Variant = ship.get("stats", {})
	
	var s_name_key := "ship." + ship_id + ".name"
	var s_name := LocaleManager.translate(s_name_key)
	if s_name == s_name_key: s_name = str(ship.get("name", ship_id))
	var s_desc_key := "ship." + ship_id + ".desc"
	var desc := LocaleManager.translate(s_desc_key)
	if desc == s_desc_key: desc = str(ship.get("description", ""))
	
	var info_text := s_name + "\n"
	info_text += desc + "\n\n"
	
	if stats is Dictionary:
		var stats_dict := stats as Dictionary
		info_text += LocaleManager.translate("stat_power") + ": " + str(stats_dict.get("power", 0)) + "\n"
		info_text += LocaleManager.translate("stat_hp") + ": " + str(stats_dict.get("max_hp", 0)) + "\n"
		info_text += LocaleManager.translate("stat_speed") + ": " + str(stats_dict.get("move_speed", 0))
	
	ship_info_label.text = info_text
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
	if ship_scroll:
		ship_scroll.scroll_horizontal -= 100 # Approximate scroll
		
func _on_ship_scroll_right() -> void:
	if ship_scroll:
		ship_scroll.scroll_horizontal += 100

func _update_scroll_buttons() -> void:
	if not ship_prev_btn or not ship_scroll: return
	# Simplification: toujours visible si besoin
	pass

func _on_shop_button_pressed() -> void:
	# TODO: Ouvrir popup de shop avec paliers de cristaux
	print("[ShipMenu] Shop button pressed - Not yet implemented")



# =============================================================================
# SLOTS D'ÉQUIPEMENT


# =============================================================================

func _create_slot_buttons() -> void:
	# Nettoyer les anciens boutons
	for child in slots_grid.get_children():
		child.queue_free()
	slot_buttons.clear()
	
	# Créer un bouton pour chaque slot
	var slots := DataManager.get_slots()
	for slot in slots:
		if slot is Dictionary:
			var slot_dict := slot as Dictionary
			var slot_id := str(slot_dict.get("id", ""))
			var slot_name := str(slot_dict.get("name", slot_id))
			
			var btn := Button.new()
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.clip_text = true
			btn.expand_icon = true
			# Largeur flexible, hauteur fixe
			btn.custom_minimum_size = Vector2(0, 90)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Font plus grande (+30%)
			btn.add_theme_font_size_override("font_size", 13)
			
			# Texte initial
			btn.text = slot_name + "\n" + LocaleManager.translate("slot_empty")
			
			btn.pressed.connect(func(): _on_slot_pressed(slot_id))
			
			slots_grid.add_child(btn)
			slot_buttons[slot_id] = btn

func _update_slot_buttons() -> void:
	if selected_ship_id == "":
		return
	
	var loadout := ProfileManager.get_loadout_for_ship(selected_ship_id)
	
	for slot_id in slot_buttons.keys():
		var btn: Button = slot_buttons[slot_id]
		var slot_data := DataManager.get_slot(slot_id)
		var slot_name := str(slot_data.get("name", slot_id))
		
		var equipped_item_id := str(loadout.get(slot_id, ""))
		if equipped_item_id != "":
			var item := ProfileManager.get_item_by_id(equipped_item_id)
			var item_name := str(item.get("name", "???"))
			var rarity := str(item.get("rarity", "common"))
			btn.text = slot_name + "\n" + item_name
			btn.modulate = _get_rarity_color(rarity)
		else:
			btn.text = slot_name + "\n" + LocaleManager.translate("slot_empty")
			btn.modulate = Color.WHITE
	
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
	var item_name := str(item.get("name", "Item"))
	var rarity := str(item.get("rarity", "common"))
	var slot := str(item.get("slot", ""))
	
	var rarity_color := _get_rarity_color(rarity)
	var bg_color := rarity_color
	bg_color.a = 0.2
	
	# Container principal
	var card := PanelContainer.new()
	# card.custom_minimum_size = ITEM_CARD_SIZE  # On veut que ça remplisse la largeur
	card.custom_minimum_size.y = ITEM_CARD_SIZE.y # Fix height only
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Style avec bordure arrondie
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = rarity_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
	
	# VBox pour le contenu
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)
	
	# Nom de l'item (tronqué si trop long)
	var name_label := Label.new()
	var display_name := item_name
	if display_name.length() > 10:
		display_name = display_name.substr(0, 8) + ".."
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", rarity_color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)
	
	# Slot de l'item
	var slot_data := DataManager.get_slot(slot)
	var slot_label := Label.new()
	slot_label.text = str(slot_data.get("name", slot))
	slot_label.add_theme_font_size_override("font_size", 12)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.modulate.a = 0.7
	vbox.add_child(slot_label)
	
	# Ligne d'info (Level + Upgrade)
	var info_hbox := HBoxContainer.new()
	info_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(info_hbox)
	
	# Level
	var level := int(item.get("level", 1))
	var level_label := Label.new()
	level_label.text = "Lvl " + str(level)
	level_label.add_theme_font_size_override("font_size", 13)
	info_hbox.add_child(level_label)
	
	# Upgrade arrow
	if _is_upgrade(item):
		var upgrade_label := Label.new()
		upgrade_label.text = " ↑"
		upgrade_label.add_theme_color_override("font_color", Color.GREEN)
		upgrade_label.add_theme_font_size_override("font_size", 12)
		info_hbox.add_child(upgrade_label)
	
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
	var rarity_data := DataManager.get_rarity(rarity)
	var rarity_name := str(rarity_data.get("name", rarity))
	var slot := str(item.get("slot", ""))
	var slot_data := DataManager.get_slot(slot)
	var slot_name := str(slot_data.get("name", slot))
	
	# Titre
	popup_title.text = LocaleManager.translate("item_popup_title")
	
	# Nom de l'item avec rareté
	popup_item_name.text = "[" + rarity_name + "] " + item_name
	popup_item_name.add_theme_color_override("font_color", _get_rarity_color(rarity))
	
	# Stats
	var stats_text := slot_name + "\n\n" + LocaleManager.translate("item_popup_stats") + "\n"
	var stats: Variant = item.get("stats", {})
	if stats is Dictionary:
		for stat_key in (stats as Dictionary).keys():
			stats_text += "  " + str(stat_key) + ": +" + str((stats as Dictionary)[stat_key]) + "\n"
	popup_stats.text = stats_text
	
	# Afficher le level dans le titre
	var level := int(item.get("level", 1))
	popup_item_name.text = "[" + rarity_name + "] " + item_name + " (Lvl " + str(level) + ")"
	
	# Bouton action
	if is_equipped:
		popup_equip_btn.text = LocaleManager.translate("item_popup_unequip")
	else:
		popup_equip_btn.text = LocaleManager.translate("item_popup_equip")
		# Désactiver si pas de vaisseau sélectionné
		popup_equip_btn.disabled = (selected_ship_id == "")
	
	# Bouton upgrade
	if popup_upgrade_btn:
		if level >= 10:
			popup_upgrade_btn.text = "MAX LEVEL"
			popup_upgrade_btn.disabled = true
		else:
			var cost := ProfileManager.get_upgrade_cost(level)
			popup_upgrade_btn.text = "Upgrade (" + str(cost) + "💎)"
			popup_upgrade_btn.disabled = (ProfileManager.get_crystals() < cost)
	
	# Bouton delete
	if popup_delete_btn:
		popup_delete_btn.disabled = false
		# Calcul valeur recyclage
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

func _on_popup_cancel_pressed() -> void:
	item_popup.visible = false



# =============================================================================
# DEBUG: Génération d'items


# =============================================================================

func _on_generate_item_pressed() -> void:
	var item := _generate_random_item()
	if ProfileManager.add_item_to_inventory(item):
		print("[ShipMenu] Generated item: ", item.get("name", "?"))
		# Reset filters to see the new item
		filter_slot = ""
		if slot_filter: slot_filter.select(0)
		current_page = 0
		_update_inventory_grid()
	else:
		print("[ShipMenu] Could not generate item: Inventory Full!")

func _generate_random_item() -> Dictionary:
	# ID unique
	var item_id := "item_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
	
	# Slot aléatoire
	var slot_ids := DataManager.get_slot_ids()
	var slot_id := str(slot_ids[randi() % slot_ids.size()])
	
	# Rareté aléatoire (pondérée)
	var rarity_id := _roll_rarity()
	var rarity_data := DataManager.get_rarity(rarity_id)
	var rarity_name := str(rarity_data.get("name", rarity_id))
	
	# Slot data pour le nom
	var slot_data := DataManager.get_slot(slot_id)
	var slot_name := str(slot_data.get("name", slot_id))
	
	# Nom auto-généré
	var item_name := rarity_name + " " + slot_name + " #" + str(randi() % 1000)
	
	# Stats placeholder
	var stats := _generate_random_stats(slot_id, rarity_id)
	
	return {
		"id": item_id,
		"slot": slot_id,
		"rarity": rarity_id,
		"name": item_name,
		"stats": stats
	}

func _roll_rarity() -> String:
	var rarities := DataManager.get_rarities()
	var total_weight := 0
	
	for rarity in rarities:
		if rarity is Dictionary:
			# Exclure les uniques de la génération debug
			if str(rarity.get("id", "")) != "unique":
				total_weight += int(rarity.get("weight", 1))
	
	var roll: int = randi() % int(max(1, total_weight))
	var current := 0
	
	for rarity in rarities:
		if rarity is Dictionary:
			var rid := str(rarity.get("id", ""))
			if rid != "unique":
				current += int(rarity.get("weight", 1))
				if roll < current:
					return rid
	
	return "common"

func _generate_random_stats(slot_id: String, rarity_id: String) -> Dictionary:
	var stats := {}
	var affixes := DataManager.get_affixes_for_slot(slot_id)
	var rarity_data := DataManager.get_rarity(rarity_id)
	var affix_count := int(rarity_data.get("affix_count", 1))
	
	# Mélanger les affixes et en prendre quelques-uns
	affixes.shuffle()
	
	for i in range(min(affix_count, affixes.size())):
		var affix: Variant = affixes[i]
		if affix is Dictionary:
			var affix_dict := affix as Dictionary
			var stat_name := str(affix_dict.get("stat", "unknown"))
			var ranges: Variant = affix_dict.get("range", {})
			
			if ranges is Dictionary:
				var range_dict := ranges as Dictionary
				var rarity_range: Variant = range_dict.get(rarity_id, [1, 5])
				if rarity_range is Array and (rarity_range as Array).size() >= 2:
					var min_val := int((rarity_range as Array)[0])
					var max_val := int((rarity_range as Array)[1])
					var value: int = min_val + randi() % int(max(1, max_val - min_val + 1))
					stats[stat_name] = value
	
	return stats



# =============================================================================
# NAVIGATION


# =============================================================================

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")



# =============================================================================
# UNIQUE POWER SELECTION


# =============================================================================

func _update_powers_ui() -> void:
	if selected_ship_id == "": return
	
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

	# Update UP Button
	if up_button:
		var avail := ProfileManager.get_available_unique_powers(selected_ship_id)
		if avail.is_empty():
			up_button.text = LocaleManager.translate("ship_menu_none")
			up_button.disabled = true
		else:
			up_button.disabled = false
			var active := ProfileManager.get_active_unique_power(selected_ship_id)
			if active != "":
				var p_data := DataManager.get_unique_power(active)
				up_button.text = str(p_data.get("name", active))
			else:
				up_button.text = "Select..."

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
		rarity_sort_btn.text = "↓"
	elif not filter_rarity_asc:
		filter_rarity_asc = true # Switch to Ascending
		rarity_sort_btn.text = "↑"
	else:
		filter_rarity_enabled = false # Disable
		rarity_sort_btn.text = "-"
	
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
		item_popup.visible = false
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
