extends Node

## StatsCalculator — Singleton for calculating aggregated ship stats.
## Combines base ship stats with equipped item bonuses.
## Used by Player.gd, ShipMenu.gd, and HomeScreen.gd.

# =============================================================================
# MAIN CALCULATION
# =============================================================================

## Calculate final stats for a ship including all equipped items.
## @param ship_id: The ship ID to calculate stats for.
## @return: Dictionary with all stat keys and their final values.
func calculate_ship_stats(ship_id: String) -> Dictionary:
	# Get base ship stats
	var ship := DataManager.get_ship(ship_id)
	var base_stats: Variant = ship.get("stats", {})
	
	var final_stats: Dictionary = {
		"max_hp": 100,
		"move_speed": 200.0,
		"power": 10,
		"fire_rate": 0.3,
		"crit_chance": 0.05,
		"dodge_chance": 0.02,
		"missile_speed_pct": 1.0,
		"special_cd": 10.0,
		"special_damage": 50
	}
	
	# Apply base ship stats
	if base_stats is Dictionary:
		for key in (base_stats as Dictionary).keys():
			final_stats[key] = (base_stats as Dictionary)[key]
	
	# Get loadout
	var loadout := ProfileManager.get_loadout_for_ship(ship_id)
	
	# Apply item bonuses
	for slot_id in loadout.keys():
		var item_id: String = str(loadout[slot_id])
		if item_id == "":
			continue
		
		var item_data := ProfileManager.get_item_by_id(item_id)
		if item_data.is_empty():
			continue
		
		# Get item stats
		var item_stats: Variant = item_data.get("stats", {})
		if item_stats is Dictionary:
			_apply_item_stats(final_stats, item_stats as Dictionary)
		
		# Apply upgrade bonus (each upgrade level adds +5% to all stats)
		var upgrade_level: int = int(item_data.get("upgrade", 0))
		if upgrade_level > 0:
			var upgrade_mult: float = 1.0 + (float(upgrade_level) * 0.05)
			# Only apply to stats that came from this item
			if item_stats is Dictionary:
				for stat_key in (item_stats as Dictionary).keys():
					var item_bonus: Variant = (item_stats as Dictionary)[stat_key]
					var additional_bonus: float = float(item_bonus) * (upgrade_mult - 1.0)
					final_stats[stat_key] = float(final_stats.get(stat_key, 0)) + additional_bonus
	
	# Ensure proper types
	final_stats["max_hp"] = int(round(float(final_stats["max_hp"])))
	final_stats["power"] = int(round(float(final_stats["power"])))
	final_stats["special_damage"] = int(round(float(final_stats["special_damage"])))
	final_stats["move_speed"] = snapped(float(final_stats["move_speed"]), 0.1)
	final_stats["fire_rate"] = snapped(float(final_stats["fire_rate"]), 0.01)
	final_stats["crit_chance"] = snapped(float(final_stats["crit_chance"]), 0.001)
	final_stats["dodge_chance"] = snapped(float(final_stats["dodge_chance"]), 0.001)
	final_stats["missile_speed_pct"] = snapped(float(final_stats["missile_speed_pct"]), 0.01)
	final_stats["special_cd"] = max(1.0, snapped(float(final_stats["special_cd"]), 0.1))
	
	return final_stats

## Apply item stats to the final stats dictionary (additive).
func _apply_item_stats(final_stats: Dictionary, item_stats: Dictionary) -> void:
	for stat_key in item_stats.keys():
		var value: Variant = item_stats[stat_key]
		var val_float = float(value)
		
		# Direct match (LootGenerator format)
		if final_stats.has(stat_key):
			final_stats[stat_key] = float(final_stats[stat_key]) + val_float
		# Legacy Mappings
		elif stat_key == "hp":
			final_stats["max_hp"] = float(final_stats.get("max_hp", 0)) + val_float
		elif stat_key == "speed":
			final_stats["move_speed"] = float(final_stats.get("move_speed", 0)) + val_float
		elif stat_key == "dodge":
			final_stats["dodge_chance"] = float(final_stats.get("dodge_chance", 0)) + (val_float / 100.0)
		elif stat_key == "crit":
			final_stats["crit_chance"] = float(final_stats.get("crit_chance", 0)) + (val_float / 100.0)
		elif stat_key == "cd_reduction":
			# Multiplicative reduction for CD? Or flat? Let's assume flat if simple, or %
			# Using simple additive for now as per ShipMenu logic
			final_stats["special_cd"] = max(1.0, float(final_stats.get("special_cd", 10.0)) - val_float)
		else:
			# Unknown stat, just add it
			final_stats[stat_key] = float(final_stats.get(stat_key, 0)) + val_float

# =============================================================================
# TOTAL POWER CALCULATION
# =============================================================================

## Calculate a single "Total Power" score for display.
## This is a weighted sum of all stats.
func calculate_total_power(ship_id: String) -> int:
	var stats := calculate_ship_stats(ship_id)
	
	# Weighted formula (adjust weights as needed)
	var power: float = 0.0
	power += float(stats.get("max_hp", 0)) * 0.5
	power += float(stats.get("power", 0)) * 3.0
	power += float(stats.get("move_speed", 0)) * 0.2
	power += float(stats.get("fire_rate", 0)) * 50.0
	power += float(stats.get("crit_chance", 0)) * 200.0
	power += float(stats.get("dodge_chance", 0)) * 150.0
	power += float(stats.get("missile_speed_pct", 0)) * 30.0
	power += float(stats.get("special_damage", 0)) * 1.5
	power -= float(stats.get("special_cd", 0)) * 2.0 # Lower CD is better
	
	return int(max(0, power))

# =============================================================================
# UNIQUE POWER HANDLING
# =============================================================================

## Get the unique power ID from equipped items (if any).
## Returns the first unique power found, or empty string if none.
func get_equipped_unique_power(ship_id: String) -> String:
	var loadout := ProfileManager.get_loadout_for_ship(ship_id)
	
	for slot_id in loadout.keys():
		var item_id: String = str(loadout[slot_id])
		if item_id == "":
			continue
		
		var item_data := ProfileManager.get_item_by_id(item_id)
		if item_data.is_empty():
			continue
		
		# Check if unique with special ability
		if item_data.get("is_unique", false):
			var ability_id: String = str(item_data.get("special_ability_id", ""))
			if ability_id != "":
				return ability_id
	
	return ""

## Get all equipped unique powers (in case multiple uniques are allowed).
func get_all_equipped_unique_powers(ship_id: String) -> Array[String]:
	var powers: Array[String] = []
	var loadout := ProfileManager.get_loadout_for_ship(ship_id)
	
	for slot_id in loadout.keys():
		var item_id: String = str(loadout[slot_id])
		if item_id == "":
			continue
		
		var item_data := ProfileManager.get_item_by_id(item_id)
		if item_data.get("is_unique", false):
			var ability_id: String = str(item_data.get("special_ability_id", ""))
			if ability_id != "" and ability_id not in powers:
				powers.append(ability_id)
	
	return powers
