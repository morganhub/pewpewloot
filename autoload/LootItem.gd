class_name LootItem
extends Resource

## LootItem — Resource class representing a generated loot item.
## Contains metadata, stats, affixes, and unique item properties.

# =============================================================================
# ENUMS
# =============================================================================

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	UNIQUE
}

# =============================================================================
# PROPERTIES
# =============================================================================

## Unique identifier for this item instance
@export var id: String = ""

## Display name (localized if needed)
@export var display_name: String = ""

## Rarity tier
@export var rarity: Rarity = Rarity.COMMON

## Item level (affects stat scaling)
@export var level: int = 1

## Upgrade level (1-9, 0 = not upgraded)
@export var upgrade: int = 0

## Equipment slot (reactor, engine, armor, shield, missiles, targeting, utility, special)
@export var slot: String = ""

## Final computed stats dictionary { stat_name: value }
## Keys: max_hp, move_speed, power, fire_rate, crit_chance, dodge_chance, missile_speed_pct, special_cd, special_damage
@export var base_stats: Dictionary = {}

## List of affix names applied to this item
@export var affixes: Array[String] = []

## True if this is a unique item with fixed properties
@export var is_unique: bool = false

## For unique items: the special ability ID they grant
@export var special_ability_id: String = ""

# =============================================================================
# SERIALIZATION
# =============================================================================

## Convert this resource to a Dictionary for JSON storage
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"rarity": _rarity_to_string(rarity),
		"level": level,
		"upgrade": upgrade,
		"slot": slot,
		"stats": base_stats.duplicate(),
		"affixes": affixes.duplicate(),
		"is_unique": is_unique,
		"special_ability_id": special_ability_id
	}

## Create a LootItem from a Dictionary (loaded from JSON)
static func from_dict(data: Dictionary) -> LootItem:
	var item := LootItem.new()
	item.id = str(data.get("id", ""))
	item.display_name = str(data.get("name", ""))
	item.rarity = _string_to_rarity(str(data.get("rarity", "common")))
	item.level = int(data.get("level", 1))
	item.upgrade = int(data.get("upgrade", 0))
	item.slot = str(data.get("slot", ""))
	
	var stats_raw: Variant = data.get("stats", {})
	if stats_raw is Dictionary:
		item.base_stats = (stats_raw as Dictionary).duplicate()
	
	var affixes_raw: Variant = data.get("affixes", [])
	if affixes_raw is Array:
		for a in affixes_raw:
			item.affixes.append(str(a))
	
	item.is_unique = bool(data.get("is_unique", false))
	item.special_ability_id = str(data.get("special_ability_id", ""))
	
	return item

# =============================================================================
# HELPERS
# =============================================================================

func _rarity_to_string(r: Rarity) -> String:
	match r:
		Rarity.COMMON: return "common"
		Rarity.UNCOMMON: return "uncommon"
		Rarity.RARE: return "rare"
		Rarity.EPIC: return "epic"
		Rarity.LEGENDARY: return "legendary"
		Rarity.UNIQUE: return "unique"
		_: return "common"

static func _string_to_rarity(s: String) -> Rarity:
	match s.to_lower():
		"common": return Rarity.COMMON
		"uncommon": return Rarity.UNCOMMON
		"rare": return Rarity.RARE
		"epic": return Rarity.EPIC
		"legendary": return Rarity.LEGENDARY
		"unique": return Rarity.UNIQUE
		_: return Rarity.COMMON

## Get the rarity as a string for display
func get_rarity_string() -> String:
	return _rarity_to_string(rarity)

## Calculate total stat value (for sorting/comparison)
func get_total_power() -> int:
	var total := 0
	for value in base_stats.values():
		total += int(value)
	return total
