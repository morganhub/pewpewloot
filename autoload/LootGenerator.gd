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
var _boss_loot_quality_bonus: float = 25.0

# Total weight for rarity selection
var _total_rarity_weight: float = 0.0
const _RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary", "unique"]

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

	# Boss global quality bonus (+25 by default).
	_boss_loot_quality_bonus = float(_loot_config.get("boss_loot_quality_bonus", 25.0))
	
	# Calculate total weight
	_total_rarity_weight = 0.0
	for rarity_key in _rarity_config.keys():
		var cfg: Variant = _rarity_config.get(rarity_key, {})
		if cfg is Dictionary:
			_total_rarity_weight += float((cfg as Dictionary).get("weight", 0))

	# Prefer uniques from DataManager (data/loot/uniques.json) over embedded config.
	_refresh_unique_items_cache()
	
	print("[LootGenerator] Loaded. Rarities: ", _rarity_config.keys().size(), 
		  " | Affixes: ", _affixes_pool.size(),
		  " | Uniques: ", _unique_items.size(),
		  " | BossQualityBonus: ", _boss_loot_quality_bonus)

func _refresh_unique_items_cache() -> void:
	if DataManager:
		var dm_uniques: Variant = DataManager.get_uniques()
		if dm_uniques is Array and (dm_uniques as Array).size() > 0:
			_unique_items = (dm_uniques as Array).duplicate(true)

func get_boss_loot_quality_bonus() -> float:
	return _boss_loot_quality_bonus

# =============================================================================
# MAIN GENERATION
# =============================================================================

## Generate a new loot item.
## @param target_level: Player/World level (affects stat scaling)
## @param slot_type: Which equipment slot (e.g., "engine", "reactor"). Empty = random.
## @param force_rarity: Force a specific rarity (e.g., "legendary"). Empty = weighted random.
## @param quality_mult: quality bonus used to bias rarity upward.
func generate_loot(target_level: int, slot_type: String = "", force_rarity: String = "", quality_mult: float = 1.0) -> LootItem:
	# 1. Determine Rarity
	var rarity_str: String = force_rarity if force_rarity != "" else _roll_rarity(quality_mult)
	
	# 2. Unique Branch
	if rarity_str == "unique":
		return _generate_unique_item(slot_type)
	
	# 3. Procedural Branch
	return _generate_procedural_item(target_level, slot_type, rarity_str)

## Generate loot specifically for bosses.
## - Uses global bonus from loot_table.json (boss_loot_quality_bonus)
## - Uses boss-specific unique pool from bosses.json -> loot_table
func generate_boss_loot(target_level: int, boss_id: String, extra_quality_bonus: float = 0.0) -> LootItem:
	var total_quality_bonus: float = maxf(0.0, _boss_loot_quality_bonus + extra_quality_bonus)
	var rarity_str := _roll_rarity(total_quality_bonus)
	var boss_unique_ids := _get_boss_unique_ids(boss_id)
	
	if rarity_str == "unique":
		if boss_unique_ids.is_empty():
			# Keep deterministic behavior: if no boss table is configured,
			# degrade unique roll to legendary instead of leaking other boss uniques.
			return _generate_procedural_item(target_level, "", "legendary")
		return _generate_unique_item("", boss_unique_ids)
	
	return _generate_procedural_item(target_level, "", rarity_str)

# =============================================================================
# RARITY SELECTION
# =============================================================================

func _roll_rarity(quality_mult: float = 1.0) -> String:
	var quality_bonus: float = maxf(0.0, quality_mult)
	var adjusted := _get_adjusted_rarity_weights(quality_bonus)
	
	var total_weight: float = 0.0
	for rarity_id in _RARITY_ORDER:
		total_weight += float(adjusted.get(rarity_id, 0.0))
	
	if total_weight <= 0.0:
		return "rare"
	
	var roll := randf() * total_weight
	var cumulative := 0.0
	for rarity_id in _RARITY_ORDER:
		cumulative += float(adjusted.get(rarity_id, 0.0))
		if roll <= cumulative:
			return rarity_id
	
	return "rare"

func _get_adjusted_rarity_weights(quality_bonus: float) -> Dictionary:
	var weights := {
		"common": 0.0,
		"uncommon": 0.0,
		"rare": 0.0,
		"epic": 0.0,
		"legendary": 0.0,
		"unique": 0.0
	}
	
	# Pull base weights from config
	for rarity_id in _RARITY_ORDER:
		var cfg: Variant = _rarity_config.get(rarity_id, {})
		if cfg is Dictionary:
			weights[rarity_id] = float((cfg as Dictionary).get("weight", 0.0))
	
	# Bias towards higher rarities with quality bonus.
	weights["common"] = float(weights["common"]) * maxf(0.0, 1.0 - quality_bonus * 0.05)
	weights["uncommon"] = float(weights["uncommon"]) * maxf(0.0, 1.0 - quality_bonus * 0.04)
	weights["rare"] = float(weights["rare"]) * (1.0 + quality_bonus * 0.04)
	weights["epic"] = float(weights["epic"]) * (1.0 + quality_bonus * 0.08)
	weights["legendary"] = float(weights["legendary"]) * (1.0 + quality_bonus * 0.12)
	weights["unique"] = float(weights["unique"]) * (1.0 + quality_bonus * 0.18)
	
	# Strict rule: if quality bonus exceeds 10, common/uncommon are forbidden.
	if quality_bonus > 10.0:
		weights["common"] = 0.0
		weights["uncommon"] = 0.0
	
	return weights

# =============================================================================
# UNIQUE ITEM GENERATION
# =============================================================================

func _generate_unique_item(preferred_slot: String, allowed_unique_ids: Array = []) -> LootItem:
	_refresh_unique_items_cache()
	
	if _unique_items.is_empty():
		# No uniques defined, fallback to legendary
		return _generate_procedural_item(1, preferred_slot, "legendary")
	
	# Filter by slot if specified
	var candidates: Array = []
	for u in _unique_items:
		if u is Dictionary:
			var u_dict := u as Dictionary
			var u_id := str(u_dict.get("id", ""))
			var slot_ok := preferred_slot == "" or str(u_dict.get("slot", "")) == preferred_slot
			var allowed_ok := allowed_unique_ids.is_empty() or allowed_unique_ids.has(u_id)
			if slot_ok and allowed_ok:
				candidates.append(u_dict)
	
	if candidates.is_empty():
		# If boss pool was requested but empty/invalid, fallback to legendary
		# rather than pulling an unrelated unique from another boss.
		if not allowed_unique_ids.is_empty():
			return _generate_procedural_item(1, preferred_slot, "legendary")
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
	item.special_ability_id = str(unique_data.get("special_ability_id", unique_data.get("unique_power_id", "")))
	item.source_boss_id = str(unique_data.get("source_boss", ""))
	item.asset = str(unique_data.get("icon", unique_data.get("sprite", unique_data.get("asset", ""))))
	
	# Fixed stats
	var stats_raw: Variant = unique_data.get("stats", {})
	if stats_raw is Dictionary:
		var normalized: Dictionary = {}
		for raw_key in (stats_raw as Dictionary).keys():
			var key := str(raw_key)
			var value := float((stats_raw as Dictionary)[raw_key])
			var mapped := _map_unique_stat_to_ship_stat(key, value)
			var final_key: String = str(mapped.get("key", key))
			var final_value: float = float(mapped.get("value", value))
			normalized[final_key] = float(normalized.get(final_key, 0.0)) + final_value
		item.base_stats = normalized
	
	return item

func _map_unique_stat_to_ship_stat(stat_key: String, value: float) -> Dictionary:
	match stat_key:
		"damage":
			return {"key": "power", "value": value}
		"cooldown_reduction":
			# Convert legacy percent-like value to the game's flat cooldown stat.
			# Example: 10 -> -1.0s, 25 -> -2.5s
			return {"key": "special_cd", "value": -absf(value) / 10.0}
		"fire_rate":
			# Legacy unique data often uses percent-like values (e.g. 10 for +10%).
			if value > 1.0:
				return {"key": "fire_rate", "value": value / 100.0}
			return {"key": "fire_rate", "value": value}
		_:
			return {"key": stat_key, "value": value}

func _get_boss_unique_ids(boss_id: String) -> Array:
	var ids: Array = []
	if not DataManager:
		return ids
	
	var boss_data := DataManager.get_boss(boss_id)
	if boss_data.is_empty():
		return ids
	
	var raw_table: Variant = boss_data.get("loot_table", [])
	if raw_table is Array:
		for entry in raw_table:
			var id := str(entry).strip_edges()
			if id != "":
				ids.append(id)
	
	return ids

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
	_refresh_unique_items_cache()
	return _unique_items.duplicate()

## Get rarity config (for debug/UI)
func get_rarity_config() -> Dictionary:
	return _rarity_config.duplicate()
