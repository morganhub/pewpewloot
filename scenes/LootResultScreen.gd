extends Control

## LootResultScreen — Écran de décision après avoir battu un boss et obtenu un item.
## Permet de Garder, Équiper ou Désassembler (Recycler) l'objet.

signal finished

var _item: Dictionary = {}
var _upgrade_value: int = 5 # Crystals pour Common

@onready var item_name_label: Label = %ItemNameLabel
@onready var item_type_label: Label = %ItemTypeLabel
@onready var stats_label: Label = %StatsLabel
@onready var background_rect: TextureRect = %Background
@onready var equip_btn: Button = %EquipButton
@onready var disassemble_btn: Button = %DisassembleButton

func setup(item: Dictionary) -> void:
	_item = item
	_load_assets()
	_update_ui()

func _load_assets() -> void:
	# Charger game.json pour les assets
	var game_config: Dictionary = {}
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			game_config = json.data
	
	var reward_config: Dictionary = game_config.get("reward_screen", {})
	
	# Background
	var bg_path: String = str(reward_config.get("background", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background_rect.texture = load(bg_path)
		%FallbackBg.visible = false
	else:
		%FallbackBg.visible = true
	
	# Buttons
	var equip_path: String = str(reward_config.get("button_equip", ""))
	if equip_path != "" and ResourceLoader.exists(equip_path):
		equip_btn.text = "" # Remove text if icon
		equip_btn.icon = load(equip_path)
		equip_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Style override to remove background if image covers all?
		# For now, keep standard button style with icon
	
	var destroy_path: String = str(reward_config.get("button_destroy", ""))
	if destroy_path != "" and ResourceLoader.exists(destroy_path):
		disassemble_btn.text = "" # Remove text if icon
		disassemble_btn.icon = load(destroy_path)
		disassemble_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	
	# Si pas d'icone, on met le texte
	if disassemble_btn.icon == null:
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
