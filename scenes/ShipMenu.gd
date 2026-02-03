extends Control

## ShipMenu — Menu de sélection de vaisseau et d'équipement.
## Accessible depuis l'écran d'accueil via le bouton "Vaisseau".
## Le vaisseau sélectionné ici s'applique à toutes les missions.

# =============================================================================
# CONSTANTES
# =============================================================================

const INVENTORY_COLUMNS := 8
const INVENTORY_ROWS := 4
const ITEM_CARD_SIZE := Vector2(80, 80)

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var content: VBoxContainer = $MarginContainer/ScrollContainer/Content
@onready var title_label: Label = $MarginContainer/ScrollContainer/Content/TitleLabel
@onready var crystal_label: Label = $MarginContainer/ScrollContainer/Content/CrystalLabel
@onready var ship_option_list: ItemList = $MarginContainer/ScrollContainer/Content/ShipSection/ShipOptionList
@onready var ship_info_label: Label = $MarginContainer/ScrollContainer/Content/ShipSection/ShipInfoLabel
@onready var slots_label: Label = $MarginContainer/ScrollContainer/Content/SlotsLabel
@onready var slots_grid: GridContainer = $MarginContainer/ScrollContainer/Content/SlotsGrid
@onready var inventory_label: Label = $MarginContainer/ScrollContainer/Content/InventoryLabel
@onready var inventory_grid: GridContainer = $MarginContainer/ScrollContainer/Content/InventoryGrid
@onready var generate_item_button: Button = $MarginContainer/ScrollContainer/Content/DebugSection/GenerateItemButton
@onready var back_button: Button = $MarginContainer/ScrollContainer/Content/NavButtons/BackButton

# Popup
@onready var item_popup: PanelContainer = $ItemPopup
@onready var popup_title: Label = $ItemPopup/VBox/PopupTitle
@onready var popup_item_name: Label = $ItemPopup/VBox/ItemName
@onready var popup_stats: Label = $ItemPopup/VBox/StatsLabel
@onready var popup_equip_btn: Button = $ItemPopup/VBox/Buttons/EquipButton
@onready var popup_cancel_btn: Button = $ItemPopup/VBox/Buttons/CancelButton

# =============================================================================
# ÉTAT
# =============================================================================

var selected_ship_id: String = ""
var selected_slot: String = ""
var slot_buttons: Dictionary = {}  # slot_id -> Button
var inventory_cards: Array = []  # Array of item card Controls

# Pour le popup
var popup_item_id: String = ""
var popup_is_equipped: bool = false
var popup_slot_id: String = ""

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Connexions
	ship_option_list.item_selected.connect(_on_ship_selected)
	generate_item_button.pressed.connect(_on_generate_item_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Popup
	popup_equip_btn.pressed.connect(_on_popup_equip_pressed)
	popup_cancel_btn.pressed.connect(_on_popup_cancel_pressed)
	item_popup.visible = false
	
	# Appliquer les traductions
	_apply_translations()
	
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
	popup_cancel_btn.text = LocaleManager.translate("item_popup_cancel")
	
	var crystals: int = ProfileManager.get_crystals()
	if crystal_label:
		crystal_label.text = "💎 " + str(crystals)

# =============================================================================
# VAISSEAUX
# =============================================================================

func _load_ships() -> void:
	ship_option_list.clear()
	
	var unlocked_ships := ProfileManager.get_unlocked_ships()
	var active_ship := ProfileManager.get_active_ship_id()
	var select_index := 0
	
	for i in range(unlocked_ships.size()):
		var ship_id: String = str(unlocked_ships[i])
		var ship := DataManager.get_ship(ship_id)
		var ship_name := str(ship.get("name", ship_id))
		
		ship_option_list.add_item(ship_name)
		ship_option_list.set_item_metadata(i, ship_id)
		
		if ship_id == active_ship:
			select_index = i
	
	# Sélectionner le vaisseau actif
	if ship_option_list.item_count > 0:
		ship_option_list.select(select_index)
		_on_ship_selected(select_index)

func _on_ship_selected(index: int) -> void:
	var ship_id: String = str(ship_option_list.get_item_metadata(index))
	selected_ship_id = ship_id
	
	# Sauvegarder la sélection
	ProfileManager.set_active_ship(ship_id)
	
	# Afficher les infos du vaisseau
	var ship := DataManager.get_ship(ship_id)
	var desc := str(ship.get("description", ""))
	var stats: Variant = ship.get("stats", {})
	
	var info_text := str(ship.get("name", ship_id)) + "\n"
	info_text += desc + "\n\n"
	
	if stats is Dictionary:
		var stats_dict := stats as Dictionary
		info_text += "Power: " + str(stats_dict.get("power", 0)) + "\n"
		info_text += "HP: " + str(stats_dict.get("max_hp", 0)) + "\n"
		info_text += "Speed: " + str(stats_dict.get("move_speed", 0))
	
	# Afficher le spécial
	var special: Variant = ship.get("special", {})
	if special is Dictionary:
		var special_dict := special as Dictionary
		info_text += "\n\nSpécial: " + str(special_dict.get("name", "?"))
	
	# Afficher le passif
	var passive: Variant = ship.get("passive", {})
	if passive is Dictionary:
		var passive_dict := passive as Dictionary
		info_text += "\nPassif: " + str(passive_dict.get("name", "?"))
	
	ship_info_label.text = info_text
	
	# Mettre à jour les slots et inventaire pour ce vaisseau
	_update_slot_buttons()
	_update_inventory_grid()

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
			btn.text = slot_name + "\n" + LocaleManager.translate("slot_empty")
			btn.custom_minimum_size = Vector2(150, 60)
			btn.pressed.connect(_on_slot_pressed.bind(slot_id))
			
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

func _on_slot_pressed(slot_id: String) -> void:
	if selected_ship_id == "":
		return
	
	# Vérifier si un item est équipé sur ce slot
	var equipped_id := ProfileManager.get_equipped_item_id(selected_ship_id, slot_id)
	if equipped_id != "":
		# Ouvrir le popup pour retirer l'item
		_show_item_popup(equipped_id, true, slot_id)

# =============================================================================
# GRILLE D'INVENTAIRE
# =============================================================================

func _update_inventory_grid() -> void:
	# Nettoyer l'ancienne grille
	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_cards.clear()
	
	var inventory := ProfileManager.get_inventory()
	
	# Filtrer par slot si sélectionné
	var filtered: Array = []
	for item in inventory:
		if item is Dictionary:
			var item_dict := item as Dictionary
			if selected_slot == "" or str(item_dict.get("slot", "")) == selected_slot:
				filtered.append(item_dict)
	
	# Mettre à jour le label
	if selected_slot != "":
		var slot_data := DataManager.get_slot(selected_slot)
		inventory_label.text = LocaleManager.translate("ship_menu_inventory_filtered", {"slot": str(slot_data.get("name", selected_slot))})
	else:
		inventory_label.text = LocaleManager.translate("ship_menu_inventory")
	
	# Créer les cartes d'items
	for i in range(filtered.size()):
		var item: Dictionary = filtered[i]
		var card := _create_item_card(item)
		inventory_grid.add_child(card)
		inventory_cards.append(card)

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
	card.custom_minimum_size = ITEM_CARD_SIZE
	
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
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)
	
	# Slot de l'item
	var slot_data := DataManager.get_slot(slot)
	var slot_label := Label.new()
	slot_label.text = str(slot_data.get("name", slot))
	slot_label.add_theme_font_size_override("font_size", 9)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.modulate.a = 0.7
	vbox.add_child(slot_label)
	
	# Indicateur d'upgrade (si meilleur que l'équipé)
	if _is_upgrade(item):
		var upgrade_label := Label.new()
		upgrade_label.text = "↑"
		upgrade_label.add_theme_color_override("font_color", Color.GREEN)
		upgrade_label.add_theme_font_size_override("font_size", 16)
		upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(upgrade_label)
	
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
	
	# Bouton action
	if is_equipped:
		popup_equip_btn.text = LocaleManager.translate("item_popup_unequip")
	else:
		popup_equip_btn.text = LocaleManager.translate("item_popup_equip")
		# Désactiver si pas de vaisseau sélectionné
		popup_equip_btn.disabled = (selected_ship_id == "")
	
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
	ProfileManager.add_item_to_inventory(item)
	
	print("[ShipMenu] Generated item: ", item.get("name", "?"))
	
	# Refresh inventory immédiatement
	_update_inventory_grid()

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
	
	var roll: int = randi() % max(1, total_weight)
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
					var value: int = min_val + randi() % max(1, max_val - min_val + 1)
					stats[stat_name] = value
	
	return stats

# =============================================================================
# NAVIGATION
# =============================================================================

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")

# =============================================================================
# UTILITAIRES
# =============================================================================

func _get_rarity_color(rarity_id: String) -> Color:
	var rarity := DataManager.get_rarity(rarity_id)
	var color_hex := str(rarity.get("color", "#FFFFFF"))
	return Color.html(color_hex)
