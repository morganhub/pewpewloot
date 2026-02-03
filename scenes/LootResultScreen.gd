extends Control

## LootResultScreen — Écran de décision après avoir battu un boss et obtenu un item.
## Permet de Garder, Équiper ou Désassembler (Recycler) l'objet.

signal finished

var _item: Dictionary = {}
var _upgrade_value: int = 5 # Crystals pour Common

@onready var item_name_label: Label = %ItemNameLabel
@onready var item_type_label: Label = %ItemTypeLabel
@onready var stats_label: Label = %StatsLabel
@onready var disassemble_btn: Button = %DisassembleButton

func setup(item: Dictionary) -> void:
	_item = item
	_update_ui()

func _update_ui() -> void:
	if _item.is_empty():
		return
	
	var rarity: String = str(_item.get("rarity", "common"))
	var type: String = str(_item.get("slot", "unknown"))
	var level: int = int(_item.get("level", 1))
	
	# Nom et couleur
	item_name_label.text = str(_item.get("name", "Unknown Item"))
	var color := DataManager.get_rarity_color(rarity)
	item_name_label.modulate = color
	
	# Type et Niveau
	item_type_label.text = type.capitalize() + " - Lv." + str(level)
	
	# Stats et Description (générées comme dans ShipMenu)
	var description: String = ""
	var stats: Variant = _item.get("stats", {})
	if stats is Dictionary:
		var s := stats as Dictionary
		if s.has("bonus"): description += "Bonus Power: +" + str(s["bonus"]) + "\n"
		if s.has("damage"): description += "Damage: " + str(s["damage"]) + "\n"
		if s.has("reload"): description += "Reload: -" + str(s["reload"]) + "%\n"
		if s.has("crit_chance"): description += "Crit: +" + str(float(s["crit_chance"])*100) + "%\n"
	
	stats_label.text = description
	
	# Calcul valeur recyclage
	match rarity:
		"common": _upgrade_value = 5
		"rare": _upgrade_value = 15
		"epic": _upgrade_value = 40
		"legendary": _upgrade_value = 100
		_: _upgrade_value = 5
	
	disassemble_btn.text = "♻️ Recycler (+" + str(_upgrade_value) + " 💎)"

func _on_keep_pressed() -> void:
	# Ajouter à l'inventaire
	ProfileManager.add_item_to_inventory(_item)
	_close()

func _on_equip_pressed() -> void:
	# Ajouter à l'inventaire ET équiper
	ProfileManager.add_item_to_inventory(_item)
	
	var ship_id := ProfileManager.get_active_ship_id()
	var slot := str(_item.get("slot", "primary"))
	var item_id := str(_item.get("id", ""))
	
	ProfileManager.equip_item(ship_id, slot, item_id)
	print("[LootResult] Item equipped on ", ship_id, " slot ", slot)
	_close()

func _on_disassemble_pressed() -> void:
	# Convertir en cristaux
	ProfileManager.add_crystals(_upgrade_value)
	print("[LootResult] Disassembled for ", _upgrade_value, " crystals")
	_close()

func _close() -> void:
	finished.emit()
	queue_free()
