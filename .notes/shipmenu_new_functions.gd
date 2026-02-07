# =============================================================================
# FILTRES ET PAGINATION - À ajouter à ShipMenu.gd
# =============================================================================

func _populate_slot_filter() -> void:
	if not slot_filter: return
	
	slot_filter.clear()
	slot_filter.add_item("Tous", -1)
	
	var slots := DataManager.get_slots()
	for i in range(slots.size()):
		if slots[i] is Dictionary:
			var slot_id := str(slots[i].get("id", ""))
			var slot_name := str(slots[i].get("name", slot_id))
			slot_filter.add_item(slot_name, i)
			slot_filter.set_item_metadata(i + 1, slot_id)

func _on_slot_filter_changed(index: int) -> void:
	if index == 0:
		filter_slot = ""
	else:
		filter_slot = str(slot_filter.get_item_metadata(index))
	
	current_page = 0
	_update_inventory_grid()

func _on_rarity_sort_pressed() -> void:
	filter_rarity_enabled = not filter_rarity_enabled
	if filter_rarity_enabled:
		filter_rarity_asc = not filter_rarity_asc
		rarity_sort_btn.text = "↑" if filter_rarity_asc else "↓"
	else:
		rarity_sort_btn.text = "-"
	
	current_page = 0
	_update_inventory_grid()

func _on_prev_page_pressed() -> void:
	if current_page > 0:
		current_page -= 1
		_update_inventory_grid()

func _on_next_page_pressed() -> void:
	var filtered := _get_filtered_inventory()
	var total_pages := ceili(float(filtered.size()) / float(items_per_page))
	
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
			var ra := rarity_order.get(str(a.get("rarity", "common")), 0)
			var rb := rarity_order.get(str(b.get("rarity", "common")), 0)
			return rb > ra if filter_rarity_asc else ra > rb
		)
	
	return filtered

func _update_page_label() -> void:
	if not page_label: return
	
	var filtered := _get_filtered_inventory()
	var total_pages := max(1, ceili(float(filtered.size()) / float(items_per_page)))
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

func _on_popup_delete_pressed() -> void:
	if popup_item_id == "":
		return
	
	# TODO: Ajouter un popup de confirmation
	# Pour l'instant, suppression directe
	if popup_is_equipped:
		ProfileManager.unequip_item(selected_ship_id, popup_slot_id)
	
	ProfileManager.remove_item_from_inventory(popup_item_id)
	print("[ShipMenu] Item deleted: ", popup_item_id)
	
	item_popup.visible = false
	_update_slot_buttons()
	_update_inventory_grid()

# =============================================================================
# MODIFICATIONS À _update_inventory_grid
# =============================================================================
# Remplacer la fonction existante par:

func _update_inventory_grid() -> void:
	# Nettoyer l'ancienne grille
	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_cards.clear()
	
	var filtered := _get_filtered_inventory()
	
	# Pagination
	var start_idx := current_page * items_per_page
	var end_idx := min(start_idx + items_per_page, filtered.size())
	
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

# =============================================================================
# MODIFICATIONS À _show_item_popup
# =============================================================================
# Ajouter après la section "Bouton action":

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
	var level := int(item.get("level", 1))
	
	# Titre
	popup_title.text = LocaleManager.translate("item_popup_title")
	
	# Nom de l'item avec rareté
	popup_item_name.text = "[" + rarity_name + "] " + item_name + " (Lvl " + str(level) + ")"
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
	
	item_popup.visible = true
