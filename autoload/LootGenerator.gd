extends Node

## LootGenerator — Singleton for procedurally generating LootItem resources.
## Uses loot_table.json for configuration.

# =============================================================================
# CONFIGURATION (Loaded from loot_table.json)
# =============================================================================

var _loot_config: Dictionary = {}
var _rarity_config: Dictionary = {}
var _affixes_pool: Array = []
var _unique_items: Array = []
var _slot_base_stats: Dictionary = {}

# Total weight for rarity selection
var _total_rarity_weight: float = 0.0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	_load_loot_table()

func _load_loot_table() -> void:
	var path := "res://data/loot_table.json"
	if not FileAccess.file_exists(path):
		push_error("[LootGenerator] loot_table.json not found!")
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	
	if err != OK:
		push_error("[LootGenerator] Failed to parse loot_table.json: " + json.get_error_message())
		return
	
	_loot_config = json.data as Dictionary
	
	# Parse sections
	_rarity_config = _loot_config.get("rarity_config", {})
	
	var affixes_raw: Variant = _loot_config.get("affixes_pool", [])
	if affixes_raw is Array:
		_affixes_pool = affixes_raw
	
	var uniques_raw: Variant = _loot_config.get("unique_items", [])
	if uniques_raw is Array:
		_unique_items = uniques_raw
	
	var slots_raw: Variant = _loot_config.get("slot_base_stats", {})
	if slots_raw is Dictionary:
		_slot_base_stats = slots_raw
	
	# Calculate total weight
	_total_rarity_weight = 0.0
	for rarity_key in _rarity_config.keys():
		var cfg: Variant = _rarity_config.get(rarity_key, {})
		if cfg is Dictionary:
			_total_rarity_weight += float((cfg as Dictionary).get("weight", 0))
	
	print("[LootGenerator] Loaded. Rarities: ", _rarity_config.keys().size(), 
		  " | Affixes: ", _affixes_pool.size(),
		  " | Uniques: ", _unique_items.size())

# =============================================================================
# MAIN GENERATION
# =============================================================================

## Generate a new loot item.
## @param target_level: Player/World level (affects stat scaling)
## @param slot_type: Which equipment slot (e.g., "engine", "reactor"). Empty = random.
## @param force_rarity: Force a specific rarity (e.g., "legendary"). Empty = weighted random.
func generate_loot(target_level: int, slot_type: String = "", force_rarity: String = "") -> LootItem:
	# 1. Determine Rarity
	var rarity_str: String = force_rarity if force_rarity != "" else _roll_rarity()
	
	# 2. Unique Branch
	if rarity_str == "unique":
		return _generate_unique_item(slot_type)
	
	# 3. Procedural Branch
	return _generate_procedural_item(target_level, slot_type, rarity_str)

# =============================================================================
# RARITY SELECTION
# =============================================================================

func _roll_rarity() -> String:
	var roll := randf() * _total_rarity_weight
	var cumulative := 0.0
	
	for rarity_key in _rarity_config.keys():
		var cfg: Variant = _rarity_config.get(rarity_key, {})
		if cfg is Dictionary:
			cumulative += float((cfg as Dictionary).get("weight", 0))
			if roll <= cumulative:
				return rarity_key
	
	return "common" # Fallback

# =============================================================================
# UNIQUE ITEM GENERATION
# =============================================================================

func _generate_unique_item(preferred_slot: String) -> LootItem:
	if _unique_items.is_empty():
		# No uniques defined, fallback to legendary
		return _generate_procedural_item(1, preferred_slot, "legendary")
	
	# Filter by slot if specified
	var candidates: Array = []
	for u in _unique_items:
		if u is Dictionary:
			if preferred_slot == "" or str((u as Dictionary).get("slot", "")) == preferred_slot:
				candidates.append(u)
	
	if candidates.is_empty():
		candidates = _unique_items.duplicate()
	
	# Pick random unique
	var unique_data: Dictionary = candidates[randi() % candidates.size()] as Dictionary
	
	var item := LootItem.new()
	item.id = str(unique_data.get("id", "unique_" + str(randi())))
	item.display_name = str(unique_data.get("name", "Unknown Unique"))
	item.rarity = LootItem.Rarity.UNIQUE
	item.level = 1 # Uniques don't scale by level
	item.slot = str(unique_data.get("slot", ""))
	item.is_unique = true
	item.special_ability_id = str(unique_data.get("special_ability_id", ""))
	item.asset = str(unique_data.get("icon", unique_data.get("asset", "")))
	
	# Fixed stats
	var stats_raw: Variant = unique_data.get("stats", {})
	if stats_raw is Dictionary:
		item.base_stats = (stats_raw as Dictionary).duplicate()
	
	return item

# =============================================================================
# PROCEDURAL ITEM GENERATION
# =============================================================================

func _generate_procedural_item(target_level: int, slot_type: String, rarity_str: String) -> LootItem:
	var item := LootItem.new()
	
	# Generate unique ID
	item.id = "item_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
	
	# Rarity
	item.rarity = LootItem._string_to_rarity(rarity_str)
	item.level = 1 # Always start at level 1 (Stats are scaled by target_level)
	
	# Slot (random if not specified)
	# Slot (random if not specified)
	if slot_type == "":
		var slots := ["primary", "reactor", "engine", "armor", "shield", "missiles", "targeting", "utility"]
		slot_type = slots[randi() % slots.size()]
	item.slot = slot_type
	
	# Resolve Asset (Icon)
	if DataManager:
		var slot_def = DataManager.get_slot(slot_type)
		var icon_def = slot_def.get("icon")
		if icon_def is Dictionary:
			item.asset = str(icon_def.get(rarity_str, icon_def.get("common", "")))
		elif icon_def is String:
			item.asset = icon_def
	
	print("[LootGenerator] Generating item for slot: ", slot_type)
	
	# Get rarity config
	var rarity_cfg: Dictionary = _rarity_config.get(rarity_str, {}) as Dictionary
	var affix_count: int = int(rarity_cfg.get("affix_count", 0))
	var power_mult: float = float(rarity_cfg.get("power_multiplier", 1.0))
	
	# Level scaling: +10% per level
	var level_mult: float = 1.0 + (float(target_level) - 1.0) * 0.1
	
	# Select affixes (no duplicate stats)
	var selected_affixes: Array[Dictionary] = []
	var used_stats: Array[String] = []
	
	# Prefer slot-relevant stats
	var preferred_stats: Array = []
	var slot_stats_raw: Variant = _slot_base_stats.get(slot_type, [])
	if slot_stats_raw is Array:
		preferred_stats = slot_stats_raw
	
	# Shuffle affixes pool
	var shuffled_pool := _affixes_pool.duplicate()
	shuffled_pool.shuffle()
	
	# First pass: try to get preferred stats
	for affix in shuffled_pool:
		if selected_affixes.size() >= affix_count:
			break
		if affix is Dictionary:
			var stat: String = str((affix as Dictionary).get("stat", ""))
			if stat in preferred_stats and stat not in used_stats:
				selected_affixes.append(affix as Dictionary)
				used_stats.append(stat)
	
	# Second pass: fill remaining slots with any stat
	for affix in shuffled_pool:
		if selected_affixes.size() >= affix_count:
			break
		if affix is Dictionary:
			var stat: String = str((affix as Dictionary).get("stat", ""))
			if stat not in used_stats:
				selected_affixes.append(affix as Dictionary)
				used_stats.append(stat)
	
	# Calculate stat values
	for affix in selected_affixes:
		var stat_name: String = str(affix.get("stat", ""))
		var affix_name: String = str(affix.get("name", ""))
		var base_range: Variant = affix.get("base_range", [0, 0])
		
		if base_range is Array and (base_range as Array).size() >= 2:
			var range_arr := base_range as Array
			var min_val: float = float(range_arr[0])
			var max_val: float = float(range_arr[1])
			
			# Roll value
			var base_value: float = randf_range(min_val, max_val)
			var final_value: float = base_value * power_mult * level_mult
			
			# Round appropriately
			if stat_name in ["max_hp", "power", "special_damage", "move_speed"]:
				item.base_stats[stat_name] = int(round(final_value))
			else:
				item.base_stats[stat_name] = snapped(final_value, 0.01)
			
			item.affixes.append(affix_name)
	
	# Generate display name
	item.display_name = _generate_item_name(item)
	
	return item

# =============================================================================
# NAME GENERATION
# =============================================================================

func _generate_item_name(item: LootItem) -> String:
	var slot_names: Dictionary = {
		"primary": "Primary Weapon",
		"reactor": "Reactor",
		"engine": "Engine",
		"armor": "Armor Plating",
		"shield": "Shield Module",
		"missiles": "Missile System",
		"targeting": "Targeting Computer",
		"utility": "Utility Module"
	}
	
	var base_name: String = slot_names.get(item.slot, "Component")
	
	# Prefix from first affix
	if not item.affixes.is_empty():
		return str(item.affixes[0]) + " " + base_name
	
	return base_name

# =============================================================================
# UTILITY
# =============================================================================

## Get all available unique items
func get_unique_items() -> Array:
	return _unique_items.duplicate()

## Get rarity config (for debug/UI)
func get_rarity_config() -> Dictionary:
	return _rarity_config.duplicate()
