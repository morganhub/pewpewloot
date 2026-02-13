extends Node

## ProfileManager — Gestion des profils joueurs avec persistance.
## Supporte: progression mondes, vaisseaux débloqués, inventaire, loadouts.

var active_profile_id: String = ""
var profiles: Array[Dictionary] = []
func _ready() -> void:
	load_from_disk()

var settings: Dictionary = {
	"music_volume": 1.0,
	"sfx_volume": 1.0,
	"locale": "en"
}

# =============================================================================
# CHARGEMENT / SAUVEGARDE
# =============================================================================

func load_from_disk() -> void:
	var data := SaveManager.load_json()

	profiles.clear()
	var raw_profiles: Variant = data.get("profiles", [])
	if raw_profiles is Array:
		for p in raw_profiles:
			if p is Dictionary:
				# Migration automatique des anciens profils
				var migrated := _migrate_profile(p as Dictionary)
				profiles.append(migrated)

	active_profile_id = ""
	var raw_active: Variant = data.get("active_profile_id", "")
	if raw_active is String:
		active_profile_id = raw_active
		
	var raw_settings: Variant = data.get("settings", {})
	if raw_settings is Dictionary:
		settings.merge(raw_settings, true)
	
	# Sauvegarder si des migrations ont eu lieu
	save_to_disk()

func save_to_disk() -> void:
	var data := {
		"profiles": profiles,
		"active_profile_id": active_profile_id,
		"settings": settings
	}
	SaveManager.save_json(data)

# =============================================================================
# MIGRATION PROFIL (anciens → nouveaux champs)
# =============================================================================

func _migrate_profile(profile: Dictionary) -> Dictionary:
	var migrated := profile.duplicate(true)
	var needs_save := false
	
	# Migration: progress
	if not migrated.has("progress"):
		migrated["progress"] = _create_default_progress()
		needs_save = true
	
	# Migration: ships_unlocked
	if not migrated.has("ships_unlocked"):
		migrated["ships_unlocked"] = DataManager.get_default_unlocked_ships().duplicate()
		needs_save = true
	
	# Migration: active_ship_id
	if not migrated.has("active_ship_id"):
		var unlocked: Variant = migrated.get("ships_unlocked", [])
		if unlocked is Array and (unlocked as Array).size() > 0:
			migrated["active_ship_id"] = str((unlocked as Array)[0])
		else:
			migrated["active_ship_id"] = "ship_car"
		needs_save = true
	
	# Migration: inventory
	if not migrated.has("inventory"):
		migrated["inventory"] = []
		needs_save = true
	
	# Migration: loadouts
	if not migrated.has("loadouts"):
		migrated["loadouts"] = {}
		needs_save = true

	# Migration: crystals
	if not migrated.has("crystals"):
		migrated["crystals"] = 0
		needs_save = true
	
	if needs_save:
		print("[ProfileManager] Migrated profile: ", str(migrated.get("name", "unknown")))
	
	return migrated

func _create_default_progress() -> Dictionary:
	return {
		"world_1": {"unlocked": true, "max_unlocked_level": 0, "boss_killed": false},
		"world_2": {"unlocked": false, "max_unlocked_level": 0, "boss_killed": false},
		"world_3": {"unlocked": false, "max_unlocked_level": 0, "boss_killed": false},
		"world_4": {"unlocked": false, "max_unlocked_level": 0, "boss_killed": false},
		"world_5": {"unlocked": false, "max_unlocked_level": 0, "boss_killed": false},
	}

# =============================================================================
# PROFILS (CRUD)
# =============================================================================

func has_any_profile() -> bool:
	return profiles.size() > 0

func get_active_profile() -> Dictionary:
	for p in profiles:
		if p.get("id", "") == active_profile_id:
			return p
	return {}

func get_active_profile_name() -> String:
	var profile := get_active_profile()
	return str(profile.get("name", "Unknown"))

func set_active_profile(profile_id: String) -> void:
	active_profile_id = profile_id
	save_to_disk()

func create_profile(profile_name: String, portrait_id: int) -> String:
	var id := str(Time.get_unix_time_from_system()) + "_" + str(randi())

	var profile := {
		"id": id,
		"name": profile_name,
		"portrait_id": portrait_id,
		"progress": _create_default_progress(),
		"ships_unlocked": DataManager.get_default_unlocked_ships().duplicate(),
		"active_ship_id": DataManager.get_default_unlocked_ships()[0] if DataManager.get_default_unlocked_ships().size() > 0 else "ship_car",
		"inventory": [],
		"loadouts": {},
		"crystals": 0
	}

	profiles.append(profile)
	active_profile_id = id
	save_to_disk()
	return id

func delete_profile(profile_id: String) -> void:
	for i in range(profiles.size()):
		if profiles[i].get("id", "") == profile_id:
			profiles.remove_at(i)
			break

	if active_profile_id == profile_id:
		active_profile_id = str(profiles[0].get("id", "")) if profiles.size() > 0 else ""

	save_to_disk()

## Calcule la valeur de recyclage d'un item
func calculate_recycle_value(item: Dictionary) -> int:
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
	return int(float(base_val) * multiplier)

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
# PROGRESSION MONDES/NIVEAUX
# =============================================================================

func _get_progress_dict(profile: Dictionary) -> Dictionary:
	var prog: Variant = profile.get("progress", {})
	if prog is Dictionary:
		return prog as Dictionary
	return {}

func complete_level(world_id: String, level_index: int, levels_per_world: int = 6) -> void:
	var profile := get_active_profile()
	if profile.is_empty():
		return

	var prog := _get_progress_dict(profile)

	# Assure la structure du monde
	var world_prog: Dictionary = {}
	var raw_wp: Variant = prog.get(world_id, {})
	if raw_wp is Dictionary:
		world_prog = raw_wp as Dictionary
	else:
		world_prog = {"unlocked": true, "max_unlocked_level": 0, "boss_killed": false}

	world_prog["unlocked"] = true

	var max_unlocked := int(world_prog.get("max_unlocked_level", 0))
	if level_index >= max_unlocked:
		world_prog["max_unlocked_level"] = min(level_index + 1, levels_per_world - 1)

	# Boss ?
	if level_index == levels_per_world - 1:
		world_prog["boss_killed"] = true

	prog[world_id] = world_prog

	# Ecrit dans le profil dans la liste profiles
	_apply_progress_to_active_profile(prog)

func unlock_next_world_if_needed(current_world_id: String) -> void:
	# world_1 -> world_2 etc.
	var current_num := int(current_world_id.replace("world_", ""))
	var next_id := "world_" + str(current_num + 1)

	var profile := get_active_profile()
	if profile.is_empty():
		return

	var prog := _get_progress_dict(profile)
	var raw_next: Variant = prog.get(next_id, {})
	var next_prog: Dictionary = {}
	if raw_next is Dictionary:
		next_prog = raw_next as Dictionary

	# Débloque uniquement si pas déjà
	if not bool(next_prog.get("unlocked", false)):
		next_prog["unlocked"] = true
		next_prog["max_unlocked_level"] = 0
		next_prog["boss_killed"] = false
		prog[next_id] = next_prog
		_apply_progress_to_active_profile(prog)

func _apply_progress_to_active_profile(new_progress: Dictionary) -> void:
	_update_active_profile("progress", new_progress)

# =============================================================================
# VAISSEAUX
# =============================================================================

## Retourne le vaisseau actif du profil
func get_active_ship_id() -> String:
	var profile := get_active_profile()
	return str(profile.get("active_ship_id", "ship_car"))

## Change le vaisseau actif
func set_active_ship(ship_id: String) -> void:
	_update_active_profile("active_ship_id", ship_id)

## Retourne la liste des vaisseaux débloqués
func get_unlocked_ships() -> Array:
	var profile := get_active_profile()
	var unlocked: Variant = profile.get("ships_unlocked", [])
	if unlocked is Array:
		return unlocked as Array
	return []

## Débloque un vaisseau
func unlock_ship(ship_id: String) -> void:
	var profile := get_active_profile()
	var unlocked: Variant = profile.get("ships_unlocked", [])
	var ships_array: Array = []
	if unlocked is Array:
		ships_array = (unlocked as Array).duplicate()
	
	if not ships_array.has(ship_id):
		ships_array.append(ship_id)
		_update_active_profile("ships_unlocked", ships_array)

# =============================================================================
# INVENTAIRE
# =============================================================================

## Retourne l'inventaire du profil actif
func get_inventory() -> Array:
	var profile := get_active_profile()
	var inv: Variant = profile.get("inventory", [])
	if inv is Array:
		return inv as Array
	return []

## Constante: Limite d'inventaire (10 pages × 16 items)
const MAX_INVENTORY_SIZE := 160

## Ajoute un item à l'inventaire
func add_item_to_inventory(item: Dictionary) -> bool:
	var profile := get_active_profile()
	var inv: Variant = profile.get("inventory", [])
	var inv_array: Array = []
	if inv is Array:
		inv_array = (inv as Array).duplicate()
	
	# Vérifier la limite
	if inv_array.size() >= MAX_INVENTORY_SIZE:
		push_warning("[ProfileManager] Inventory full! Cannot add item.")
		return false
	
	# Initialiser le level si absent
	var item_copy := item.duplicate()
	if not item_copy.has("level"):
		item_copy["level"] = 1
	
	inv_array.append(item_copy)
	_update_active_profile("inventory", inv_array)
	return true

## Vérifie si l'inventaire est plein
func is_inventory_full() -> bool:
	return get_inventory().size() >= MAX_INVENTORY_SIZE

## Supprime un item de l'inventaire par son ID
func remove_item_from_inventory(item_id: String) -> void:
	var profile := get_active_profile()
	var inv: Variant = profile.get("inventory", [])
	var inv_array: Array = []
	if inv is Array:
		inv_array = (inv as Array).duplicate()
	
	for i in range(inv_array.size()):
		var item: Variant = inv_array[i]
		if item is Dictionary and str((item as Dictionary).get("id", "")) == item_id:
			inv_array.remove_at(i)
			break
	
	_update_active_profile("inventory", inv_array)

## Trouve un item dans l'inventaire par son ID
func get_item_by_id(item_id: String) -> Dictionary:
	var inv := get_inventory()
	for item in inv:
		if item is Dictionary and str((item as Dictionary).get("id", "")) == item_id:
			return item as Dictionary
	return {}

## Calcule le coût d'upgrade pour un level donné
func get_upgrade_cost(current_level: int) -> int:
	# Coût exponentiel: 10 * (level^1.5)
	if current_level >= 10:
		return 0  # Max level atteint
	return int(10.0 * pow(float(current_level), 1.5))

## Upgrade un item (augmente son level et ses stats)
func upgrade_item(item_id: String) -> bool:
	var item := get_item_by_id(item_id)
	if item.is_empty():
		return false
	
	var current_level := int(item.get("level", 1))
	if current_level >= 10:
		return false
	
	var upgrade_data = DataManager.get_level_upgrade_data(current_level)
	var next_data = upgrade_data.get("upgrade_to_next", {})
	var cost := int(next_data.get("cost", 999999))
	
	if not spend_crystals(cost):
		return false
	
	# Logic Upgrade (Stats)
	var roll = randf() * 100.0
	var tier = "decent"
	# Weights: Decent 40, Great 45, Perfect 15
	if roll < 40: tier = "decent"
	elif roll < 85: tier = "great"
	else: tier = "perfect"
	
	var tiers_cfg = next_data.get("tiers", {})
	var tier_data = tiers_cfg.get(tier, {})
	var mult_min = float(tier_data.get("multiplier_min", 1.05))
	var mult_max = float(tier_data.get("multiplier_max", 1.10))
	var multiplier = randf_range(mult_min, mult_max)
	
	var stats = item.get("stats", {}).duplicate()
	for key in stats:
		var val = float(stats[key])
		# Heuristic: if small integer, increment or keep as float?
		# Match ShipMenu logic
		if val < 5.0 and val > 1.0:
			stats[key] = val * multiplier
		else:
			# Large numbers (HP, Shield, Damage)
			stats[key] = ceil(val * multiplier)
	
	# Update globally
	var inv := get_inventory()
	for i in range(inv.size()):
		if inv[i] is Dictionary and str(inv[i].get("id", "")) == item_id:
			inv[i]["level"] = current_level + 1
			inv[i]["stats"] = stats
			_update_active_profile("inventory", inv)
			return true
	
	return false


# =============================================================================
# LOADOUTS (équipement par vaisseau)
# =============================================================================

## Retourne le loadout d'un vaisseau
func get_loadout_for_ship(ship_id: String) -> Dictionary:
	var profile := get_active_profile()
	var loadouts: Variant = profile.get("loadouts", {})
	if loadouts is Dictionary:
		var ship_loadout: Variant = (loadouts as Dictionary).get(ship_id, {})
		if ship_loadout is Dictionary:
			return ship_loadout as Dictionary
	return {}

## Retourne tous les IDs d'items équipés (tous vaisseaux confondus)
func get_all_equipped_item_ids() -> Array:
	var equipped: Array = []
	var profile := get_active_profile()
	var loadouts: Variant = profile.get("loadouts", {})
	if loadouts is Dictionary:
		for ship_id in (loadouts as Dictionary):
			var ship_loadout: Variant = (loadouts as Dictionary)[ship_id]
			if ship_loadout is Dictionary:
				for slot_id in (ship_loadout as Dictionary):
					# Ignorer keys spéciales
					if slot_id == "selected_unique_power": continue
					
					var item_id: String = str((ship_loadout as Dictionary)[slot_id])
					if item_id != "" and not equipped.has(item_id):
						equipped.append(item_id)
	return equipped

## Vérifie si un item est équipé sur n'importe quel vaisseau
func is_item_equipped(item_id: String) -> bool:
	var equipped := get_all_equipped_item_ids()
	return equipped.has(item_id)

## Équipe un item sur un slot pour un vaisseau
func equip_item(ship_id: String, slot: String, item_id: String) -> void:
	var profile := get_active_profile()
	var loadouts: Variant = profile.get("loadouts", {})
	var loadouts_dict: Dictionary = {}
	if loadouts is Dictionary:
		loadouts_dict = (loadouts as Dictionary).duplicate(true)
	
	if not loadouts_dict.has(ship_id):
		loadouts_dict[ship_id] = {}
	
	var ship_loadout: Dictionary = loadouts_dict[ship_id]
	ship_loadout[slot] = item_id
	loadouts_dict[ship_id] = ship_loadout
	
	_update_active_profile("loadouts", loadouts_dict)

# =============================================================================
# ECONOMY (CRYSTALS)
# =============================================================================

func get_crystals() -> int:
	var profile := get_active_profile()
	return int(profile.get("crystals", 0))

func add_crystals(amount: int) -> void:
	var current := get_crystals()
	_update_active_profile("crystals", current + amount)

func spend_crystals(amount: int) -> bool:
	var current := get_crystals()
	if current >= amount:
		_update_active_profile("crystals", current - amount)
		return true
	return false

func remove_crystals(amount: int) -> void:
	var current := get_crystals()
	_update_active_profile("crystals", max(0, current - amount))


## Déséquipe un item d'un slot
func unequip_item(ship_id: String, slot: String) -> void:
	var profile := get_active_profile()
	var loadouts: Variant = profile.get("loadouts", {})
	var loadouts_dict: Dictionary = {}
	if loadouts is Dictionary:
		loadouts_dict = (loadouts as Dictionary).duplicate(true)
	
	if loadouts_dict.has(ship_id):
		var ship_loadout: Variant = loadouts_dict[ship_id]
		if ship_loadout is Dictionary:
			(ship_loadout as Dictionary).erase(slot)
			loadouts_dict[ship_id] = ship_loadout
	
	_update_active_profile("loadouts", loadouts_dict)

## Retourne l'ID de l'item équipé sur un slot
func get_equipped_item_id(ship_id: String, slot: String) -> String:
	var loadout := get_loadout_for_ship(ship_id)
	return str(loadout.get(slot, ""))

## Retourne l'item équipé sur un slot (données complètes)
func get_equipped_item(ship_id: String, slot: String) -> Dictionary:
	var item_id := get_equipped_item_id(ship_id, slot)
	if item_id == "":
		return {}
	return get_item_by_id(item_id)

# =============================================================================
# UNIQUE POWERS (From Items)
# =============================================================================

## Retourne la liste des Unique Power IDs disponibles via l'équipement actuel
func get_available_unique_powers(ship_id: String) -> Array:
	var powers: Array = []
	var loadout := get_loadout_for_ship(ship_id)
	
	for slot_id in loadout:
		# Ignorer les clés spéciales comme "selected_unique_power"
		if slot_id == "selected_unique_power":
			continue
			
		var item_id: String = str(loadout[slot_id])
		if item_id == "": continue
		
		# Récupérer l'item complet
		var item := get_item_by_id(item_id)
		if item.is_empty(): continue
		
		var power_id: String = str(item.get("unique_power_id", ""))
		# Fallback: Check base unique definition in DataManager
		if power_id == "":
			var base_unique := DataManager.get_unique(item_id)
			if not base_unique.is_empty():
				power_id = str(base_unique.get("unique_power_id", ""))
		
		if power_id != "" and not powers.has(power_id):
			powers.append(power_id)
			
	return powers

## Retourne l'Unique Power actif pour le vaisseau (celui choisi ou par défaut)
func get_active_unique_power(ship_id: String) -> String:
	var avail := get_available_unique_powers(ship_id)
	if avail.is_empty():
		return ""
		
	# Vérifier la sauvegarde
	var loadout := get_loadout_for_ship(ship_id)
	var selected: String = str(loadout.get("selected_unique_power", ""))
	
	if selected != "" and avail.has(selected):
		return selected
		
	# Par défaut: le premier trouvé
	return avail[0]

## Défini l'Unique Power actif
func set_active_unique_power(ship_id: String, power_id: String) -> void:
	var profile := get_active_profile()
	var loadouts: Variant = profile.get("loadouts", {})
	var loadouts_dict: Dictionary = {}
	if loadouts is Dictionary:
		loadouts_dict = (loadouts as Dictionary).duplicate(true)
	
	if not loadouts_dict.has(ship_id):
		loadouts_dict[ship_id] = {}
		
	var ship_loadout: Dictionary = loadouts_dict[ship_id]
	ship_loadout["selected_unique_power"] = power_id
	loadouts_dict[ship_id] = ship_loadout
	
	_update_active_profile("loadouts", loadouts_dict)

# =============================================================================
# UTILITAIRES INTERNES
# =============================================================================

## Met à jour un champ du profil actif et sauvegarde
func _update_active_profile(key: String, value: Variant) -> void:
	for i in range(profiles.size()):
		if str(profiles[i].get("id", "")) == active_profile_id:
			var updated := profiles[i]
			updated[key] = value
			profiles[i] = updated
			break
	save_to_disk()
# =============================================================================
# SETTINGS
# =============================================================================

func get_setting(key: String, default: Variant = null) -> Variant:
	return settings.get(key, default)

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_to_disk()
