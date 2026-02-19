extends Node

## DataManager — Charge et expose toutes les données de jeu depuis les fichiers JSON.
## Ces données sont read-only et chargées au démarrage.

# Données chargées
var _worlds: Dictionary = {}        # world_id -> data
var _ships: Array = []
var _enemies: Dictionary = {}       # enemy_id -> data
var _bosses: Dictionary = {}        # boss_id -> data
var _move_patterns: Dictionary = {} # pattern_id -> data
var _missile_patterns: Dictionary = {} # pattern_id -> data
var _missiles: Dictionary = {} # missile_id -> data
var _slots: Array = []
var _slot_ids: Array = []
var _rarities: Array = []
var _affixes: Dictionary = {}
var _uniques: Array = []
var _uniques_by_id: Dictionary = {} # unique_id -> data
var _super_powers: Dictionary = {} # power_id -> data
var _unique_powers: Dictionary = {} # power_id -> data
var _boss_powers: Dictionary = {} # power_id -> data
var _effects: Dictionary = {} # effect_id -> data
var _game_config: Dictionary = {} # game.json data
var _skills: Dictionary = {} # skills.json data
var _obstacles: Dictionary = {} # obstacle_id -> data
var _fluids: Dictionary = {} # fluid_preset_id -> data
var _stories: Dictionary = {} # story_id -> sequence data
var _story_settings: Dictionary = {} # global_settings from story.json

var _default_unlocked_ships: Array = []

func _ready() -> void:
	_load_all_data()

func _load_all_data() -> void:
	_load_game_config() # Load generic game config first
	_load_worlds()
	_load_ships()
	_load_patterns()
	_load_missiles()
	_load_powers() # New
	_load_enemies()
	_load_bosses()
	_load_loot_data()
	_load_levels()
	_load_level_modifiers()
	_load_effects()
	_load_skills()
	_load_obstacles()
	_load_fluids()
	_load_stories()
	print("[DataManager] All data loaded.")
	print("[DataManager] Worlds: ", _worlds.size())
	print("[DataManager] Ships: ", _ships.size())
	print("[DataManager] Move Patterns: ", _move_patterns.size())
	print("[DataManager] Missile Patterns: ", _missile_patterns.size())
	print("[DataManager] Enemies: ", _enemies.size())
	print("[DataManager] Bosses: ", _bosses.size())
	print("[DataManager] Slots: ", _slots.size())
	print("[DataManager] Rarities: ", _rarities.size())
	print("[DataManager] Uniques: ", _uniques.size())
	print("[DataManager] Obstacles: ", _obstacles.size())
	print("[DataManager] Fluids: ", _fluids.size())
	print("[DataManager] Stories: ", _stories.size())


# =============================================================================
# SKILLS DATA (skills.json)
# =============================================================================

func _load_skills() -> void:
	var data := _load_json("res://data/skills.json")
	if not data.is_empty():
		_skills = data
		print("[DataManager] Skills loaded: ", _skills.get("trees", {}).keys())

func get_skills_config() -> Dictionary:
	return _skills

func get_skill_trees() -> Dictionary:
	return _skills.get("trees", {})

func get_skill_tree(tree_id: String) -> Dictionary:
	return _skills.get("trees", {}).get(tree_id, {})

func get_skill(skill_id: String) -> Dictionary:
	var trees: Dictionary = _skills.get("trees", {})
	for tree_id in trees:
		var tree_data: Dictionary = trees[tree_id]
		var branches: Dictionary = tree_data.get("branches", {})
		for branch_id in branches:
			var branch: Dictionary = branches[branch_id]
			var levels: Array = branch.get("levels", [])
			for level in levels:
				if level is Dictionary and str(level.get("id", "")) == skill_id:
					return level
	return {}

func get_skill_branch_for_id(skill_id: String) -> String:
	var trees: Dictionary = _skills.get("trees", {})
	for tree_id in trees:
		var branches: Dictionary = trees[tree_id].get("branches", {})
		for branch_id in branches:
			var levels: Array = branches[branch_id].get("levels", [])
			for level in levels:
				if level is Dictionary and str(level.get("id", "")) == skill_id:
					return branch_id
	return ""

func get_skill_tree_for_id(skill_id: String) -> String:
	var trees: Dictionary = _skills.get("trees", {})
	for tree_id in trees:
		var branches: Dictionary = trees[tree_id].get("branches", {})
		for branch_id in branches:
			var levels: Array = branches[branch_id].get("levels", [])
			for level in levels:
				if level is Dictionary and str(level.get("id", "")) == skill_id:
					return tree_id
	return ""

func get_respec_cost_base() -> int:
	return int(_skills.get("respec_cost_base", 100))

func get_xp_curve_base() -> int:
	return int(_skills.get("xp_curve_base", 100))

func get_xp_curve_exponent() -> float:
	return float(_skills.get("xp_curve_exponent", 1.5))

# =============================================================================
# GAME CONFIG (game.json)
# =============================================================================

func _load_game_config() -> void:
	_game_config = _load_json("res://data/game.json")

func get_game_config() -> Dictionary:
	return _game_config
	
func get_game_data() -> Dictionary:
	return _game_config

## Retourne le fluid_id par défaut pour les explosions (depuis game.json)
func get_default_explosion_fluid_id() -> String:
	var explosion_cfg: Variant = _game_config.get("default_explosion", {})
	if explosion_cfg is Dictionary:
		return str((explosion_cfg as Dictionary).get("fluid_id", ""))
	return ""

# =============================================================================
# WORLDS & LEVELS
# =============================================================================

var _levels: Dictionary = {}

func _load_levels() -> void:
	_levels.clear()
	# Charger les niveaux depuis les mondes chargés
	for world_id in _worlds:
		var world_data: Dictionary = _worlds[world_id]
		var levels_list: Variant = world_data.get("levels", [])
		if levels_list is Array:
			for level in levels_list:
				if level is Dictionary:
					var l_dict := level as Dictionary
					var l_id: String = str(l_dict.get("id", ""))
					# Si l'ID n'est pas défini, on en génère un
					if l_id == "":
						l_id = world_id + "_lvl_" + str(l_dict.get("index", 0))
						l_dict["id"] = l_id # Sauvegarder l'ID généré dans le dict
					
					_levels[l_id] = l_dict

func get_level_data(level_id: String) -> Dictionary:
	return _levels.get(level_id, {})

# =============================================================================
# WORLDS
# =============================================================================

func _load_worlds() -> void:
	_worlds.clear()
	var dir := DirAccess.open("res://data/worlds")
	if dir == null:
		push_warning("[DataManager] Could not open res://data/worlds")
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path := "res://data/worlds/" + file_name
			var data := _load_json(path)
			if data.has("id"):
				_worlds[data["id"]] = data
		file_name = dir.get_next()
	dir.list_dir_end()

## Retourne tous les mondes triés par ordre
func get_worlds() -> Array:
	var worlds_array := _worlds.values()
	worlds_array.sort_custom(_sort_by_order)
	return worlds_array

func _sort_by_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("order", 0)) < int(b.get("order", 0))

## Retourne un monde par son ID
func get_world(world_id: String) -> Dictionary:
	return _worlds.get(world_id, {})

## Retourne la liste des IDs de mondes
func get_world_ids() -> Array:
	return _worlds.keys()

## Retourne le nombre de niveaux d'un monde (inclut le boss)
func get_world_level_count(world_id: String) -> int:
	var world := get_world(world_id)
	var levels: Variant = world.get("levels", [])
	if levels is Array:
		return (levels as Array).size()
	return 6  # fallback

# =============================================================================
# SHIPS
# =============================================================================

func _load_ships() -> void:
	_ships.clear()
	_default_unlocked_ships.clear()
	
	var data := _load_json("res://data/ships/ships.json")
	var raw_ships: Variant = data.get("ships", [])
	if raw_ships is Array:
		_ships = raw_ships as Array
	
	var raw_default: Variant = data.get("default_unlocked", [])
	if raw_default is Array:
		_default_unlocked_ships = raw_default as Array

## Retourne tous les vaisseaux
func get_ships() -> Array:
	return _ships

## Retourne un vaisseau par son ID
func get_ship(ship_id: String) -> Dictionary:
	for ship in _ships:
		if not (ship is Dictionary):
			continue
		var ship_dict := ship as Dictionary
		var current_id := str(ship_dict.get("id", ""))
		if current_id == ship_id:
			return ship_dict
		var aliases: Variant = ship_dict.get("aliases", [])
		if aliases is Array:
			var alias_array := aliases as Array
			for alias in alias_array:
				if str(alias) == ship_id:
					return ship_dict
	return {}

## Retourne les IDs des vaisseaux débloqués par défaut
func get_default_unlocked_ships() -> Array:
	return _default_unlocked_ships

# =============================================================================
# PATTERNS (Movement & Missiles)
# =============================================================================

func _load_patterns() -> void:
	_move_patterns.clear()
	_missile_patterns.clear()
	
	# Move patterns
	var move_data := _load_json("res://data/patterns/move_patterns.json")
	var raw_move: Variant = move_data.get("patterns", [])
	if raw_move is Array:
		for pattern in raw_move:
			if pattern is Dictionary:
				var p_dict := pattern as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_move_patterns[p_id] = p_dict
	
	# Missile patterns - PLAYER
	var missile_player_data := _load_json("res://data/patterns/missile_patterns_player.json")
	var raw_missile_player: Variant = missile_player_data.get("patterns", [])
	if raw_missile_player is Array:
		for pattern in raw_missile_player:
			if pattern is Dictionary:
				var p_dict := pattern as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_missile_patterns[p_id] = p_dict
	
	# Missile patterns - ENEMY
	var missile_enemy_data := _load_json("res://data/patterns/missile_patterns_enemy.json")
	var raw_missile_enemy: Variant = missile_enemy_data.get("patterns", [])
	if raw_missile_enemy is Array:
		for pattern in raw_missile_enemy:
			if pattern is Dictionary:
				var p_dict := pattern as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_missile_patterns[p_id] = p_dict

## Retourne un move pattern par ID
func get_move_pattern(pattern_id: String) -> Dictionary:
	return _move_patterns.get(pattern_id, {})

## Retourne tous les move patterns
func get_all_move_patterns() -> Array:
	return _move_patterns.values()

## Retourne un missile pattern par ID
func get_missile_pattern(pattern_id: String) -> Dictionary:
	return _missile_patterns.get(pattern_id, {})

## Retourne tous les missile patterns
func get_all_missile_patterns() -> Array:
	return _missile_patterns.values()

# =============================================================================
# MISSILES (Visuals)
# =============================================================================

var _default_explosion: Dictionary = {}

func _load_missiles() -> void:
	_missiles.clear()
	_default_explosion.clear()
	var data := _load_json("res://data/missiles/missiles.json")
	
	# Load default explosion
	var raw_explosion: Variant = data.get("default_explosion", {})
	if raw_explosion is Dictionary:
		_default_explosion = raw_explosion as Dictionary
	
	var raw_missiles: Variant = data.get("missiles", [])
	if raw_missiles is Array:
		for missile in raw_missiles:
			if missile is Dictionary:
				var m_dict := missile as Dictionary
				var m_id: String = str(m_dict.get("id", ""))
				if m_id != "":
					_missiles[m_id] = m_dict

## Retourne un missile par son ID
func get_missile(missile_id: String) -> Dictionary:
	return _missiles.get(missile_id, {})

## Retourne l'explosion par défaut
func get_default_explosion() -> Dictionary:
	return _default_explosion

# =============================================================================
# POWERS (Super & Unique)
# =============================================================================

func _load_powers() -> void:
	_super_powers.clear()
	_unique_powers.clear()
	_boss_powers.clear()
	
	# Super Powers
	var super_data := _load_json("res://data/missiles/super_powers.json")
	var raw_super: Variant = super_data.get("powers", [])
	if raw_super is Array:
		for p in raw_super:
			if p is Dictionary:
				var p_dict := p as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_super_powers[p_id] = p_dict
	
	# Unique Powers
	var unique_data := _load_json("res://data/missiles/unique_powers.json")
	var raw_unique: Variant = unique_data.get("powers", [])
	if raw_unique is Array:
		for p in raw_unique:
			if p is Dictionary:
				var p_dict := p as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_unique_powers[p_id] = p_dict
	
	# Boss Powers
	var boss_data := _load_json("res://data/missiles/boss_powers.json")
	var raw_boss: Variant = boss_data.get("powers", [])
	if raw_boss is Array:
		for p in raw_boss:
			if p is Dictionary:
				var p_dict := p as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_boss_powers[p_id] = p_dict

func get_super_power(power_id: String) -> Dictionary:
	return _super_powers.get(power_id, {})

func get_unique_power(power_id: String) -> Dictionary:
	return _unique_powers.get(power_id, {})

func get_power(power_id: String) -> Dictionary:
	if _super_powers.has(power_id):
		return _super_powers[power_id]
	if _boss_powers.has(power_id):
		return _boss_powers[power_id]
	return _unique_powers.get(power_id, {})


# =============================================================================
# ENEMIES
# =============================================================================

func _load_enemies() -> void:
	_enemies.clear()
	
	var data := _load_json("res://data/enemies.json")
	var raw_enemies: Variant = data.get("enemies", [])
	if raw_enemies is Array:
		for enemy in raw_enemies:
			if enemy is Dictionary:
				var enemy_dict := enemy as Dictionary
				var enemy_id: String = str(enemy_dict.get("id", ""))
				if enemy_id != "":
					_enemies[enemy_id] = enemy_dict

## Retourne un ennemi par son ID
func get_enemy(enemy_id: String) -> Dictionary:
	return _enemies.get(enemy_id, {})

## Retourne tous les ennemis
func get_all_enemies() -> Array:
	return _enemies.values()

## Retourne un ennemi aléatoire
func get_random_enemy() -> Dictionary:
	var enemies := _enemies.values()
	if enemies.is_empty():
		return {}
	return enemies[randi() % enemies.size()]

# =============================================================================
# BOSSES
# =============================================================================

func _load_bosses() -> void:
	_bosses.clear()
	
	var data := _load_json("res://data/bosses.json")
	var raw_bosses: Variant = data.get("bosses", [])
	if raw_bosses is Array:
		for boss in raw_bosses:
			if boss is Dictionary:
				var boss_dict := boss as Dictionary
				var boss_id: String = str(boss_dict.get("id", ""))
				if boss_id != "":
					_bosses[boss_id] = boss_dict

## Retourne un boss par ID
func get_boss(boss_id: String) -> Dictionary:
	return _bosses.get(boss_id, {})

## Retourne tous les boss
func get_all_bosses() -> Array:
	return _bosses.values()

# =============================================================================
# LOOT (slots, rarities, affixes, uniques)
# =============================================================================

func _load_loot_data() -> void:
	_slots.clear()
	_slot_ids.clear()
	_rarities.clear()
	_affixes.clear()
	_uniques.clear()
	_uniques_by_id.clear()
	
	# loot_table.json contient slots, rarity_config, et affixes (consolidated)
	var loot_data := _load_json("res://data/loot_table.json")
	
	var raw_slots: Variant = loot_data.get("slots", [])
	if raw_slots is Array:
		_slots = raw_slots as Array
		for slot in _slots:
			if slot is Dictionary:
				_slot_ids.append(str((slot as Dictionary).get("id", "")))
	
	# Build rarities array from rarity_config dict for backward compatibility
	var rarity_config: Variant = loot_data.get("rarity_config", {})
	if rarity_config is Dictionary:
		for rarity_id in (rarity_config as Dictionary).keys():
			var cfg: Dictionary = (rarity_config as Dictionary)[rarity_id]
			var rarity_entry := {"id": rarity_id}
			rarity_entry.merge(cfg)
			_rarities.append(rarity_entry)
	
	var raw_affixes: Variant = loot_data.get("affixes", {})
	if raw_affixes is Dictionary:
		_affixes = raw_affixes as Dictionary
	
	# Boss unique pools are read directly from data/bosses.json -> bosses[].loot_table
	
	# Uniques
	var uniques_data := _load_json("res://data/loot/uniques.json")
	var raw_uniques: Variant = uniques_data.get("uniques", [])
	if raw_uniques is Array:
		_uniques = raw_uniques as Array
		for unique in _uniques:
			if unique is Dictionary:
				var unique_dict := unique as Dictionary
				var unique_id: String = str(unique_dict.get("id", ""))
				if unique_id != "":
					_uniques_by_id[unique_id] = unique_dict

## Retourne tous les slots (avec leurs métadonnées)
func get_slots() -> Array:
	return _slots

## Retourne les IDs des slots uniquement
func get_slot_ids() -> Array:
	return _slot_ids

## Retourne un slot par son ID
func get_slot(slot_id: String) -> Dictionary:
	for slot in _slots:
		if slot is Dictionary and str(slot.get("id", "")) == slot_id:
			return slot as Dictionary
	return {}

## Retourne toutes les raretés
func get_rarities() -> Array:
	return _rarities

## Retourne une rareté par son ID
func get_rarity(rarity_id: String) -> Dictionary:
	for rarity in _rarities:
		if rarity is Dictionary and str(rarity.get("id", "")) == rarity_id:
			return rarity as Dictionary
	return {}

## Retourne la couleur hexadécimale associée à une rareté
func get_rarity_color(rarity_id: String) -> Color:
	var rarity := get_rarity(rarity_id)
	var color_code := str(rarity.get("color", "#FFFFFF"))
	return Color(color_code)

## Retourne le chemin de la frame (bordure) associée à une rareté
func get_rarity_frame_path(rarity_id: String) -> String:
	var frames: Dictionary = _game_config.get("rarity_frames", {})
	if frames.has(rarity_id):
		return str(frames.get(rarity_id, ""))
	# Fallback to common if not found
	return str(frames.get("common", ""))

## Retourne les affixes disponibles pour un slot (global + spécifiques)
func get_affixes_for_slot(slot_id: String) -> Array:
	var result: Array = []
	
	# Affixes globaux
	var global: Variant = _affixes.get("global", [])
	if global is Array:
		result.append_array(global as Array)
	
	# Affixes spécifiques au slot
	var slot_specific: Variant = _affixes.get(slot_id, [])
	if slot_specific is Array:
		result.append_array(slot_specific as Array)
	
	return result

## Retourne tous les uniques
func get_uniques() -> Array:
	return _uniques

## Retourne un unique par son ID
func get_unique(unique_id: String) -> Dictionary:
	return _uniques_by_id.get(unique_id, {})

## Retourne les uniques d'un boss spécifique
func get_uniques_for_boss(boss_id: String) -> Array:
	var result: Array = []
	for unique in _uniques:
		if unique is Dictionary and str(unique.get("source_boss", "")) == boss_id:
			result.append(unique)
	return result

# =============================================================================
# UTILITY
# =============================================================================

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[DataManager] File not found: " + path)
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[DataManager] Could not open file: " + path)
		return {}
	
	var text := file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[DataManager] JSON parse error in: " + path)
		return {}
	
	if parsed is Dictionary:
		return parsed as Dictionary
	
	return {}

## Recharge toutes les données (utile pour le debug)
func reload_all() -> void:
	print("[DataManager] Reloading all data...")
	_load_all_data()

# =============================================================================
# EFFECTS
# =============================================================================

func _load_effects() -> void:
	_effects.clear()
	var data := _load_json("res://data/effects.json")
	var raw_effects: Variant = data.get("effects", [])
	if raw_effects is Array:
		for e in raw_effects:
			if e is Dictionary:
				var e_dict := e as Dictionary
				var e_id: String = str(e_dict.get("id", ""))
				if e_id != "":
					_effects[e_id] = e_dict

func get_effect(effect_id: String) -> Dictionary:
	return _effects.get(effect_id, {})

# =============================================================================
# LEVELS MODIFIERS (Upgrade System)
# =============================================================================

var _level_modifiers: Dictionary = {} # level (int) -> data

func _load_level_modifiers() -> void:
	_level_modifiers.clear()
	var data := _load_json("res://data/loot/levels.json")
	var raw_levels: Variant = data.get("levels", [])
	if raw_levels is Array:
		for lvl in raw_levels:
			if lvl is Dictionary:
				var l_dict := lvl as Dictionary
				var level_idx: int = int(l_dict.get("level", 0))
				if level_idx > 0:
					_level_modifiers[level_idx] = l_dict

func get_level_upgrade_data(level: int) -> Dictionary:
	return _level_modifiers.get(level, {})

# =============================================================================
# OBSTACLES DATA (obstacles.json)
# =============================================================================

func _load_obstacles() -> void:
	_obstacles.clear()
	var data := _load_json("res://data/obstacles.json")
	var raw_obstacles: Variant = data.get("obstacles", {})
	if raw_obstacles is Dictionary:
		for key in raw_obstacles:
			var entry: Variant = raw_obstacles[key]
			if entry is Dictionary:
				var o_dict := entry as Dictionary
				var o_id: String = str(o_dict.get("id", key))
				_obstacles[o_id] = o_dict
	print("[DataManager] Obstacles loaded: ", _obstacles.size())

func get_obstacle(obstacle_id: String) -> Dictionary:
	return _obstacles.get(obstacle_id, {})

func get_all_obstacles() -> Dictionary:
	return _obstacles

# =============================================================================
# FLUID PRESETS DATA (fluids/fluid_presets.json)
# =============================================================================

func _load_fluids() -> void:
	_fluids.clear()
	var data := _load_json("res://data/fluids/fluid_presets.json")
	if data.is_empty():
		push_warning("[DataManager] No fluid presets found.")
		return
	# Le fichier est directement un dict { preset_id: { ... } }
	for key in data:
		var entry: Variant = data[key]
		if entry is Dictionary:
			_fluids[key] = entry as Dictionary
	print("[DataManager] Fluid presets loaded: ", _fluids.size())

func get_fluid_preset(fluid_id: String) -> Dictionary:
	return _fluids.get(fluid_id, {})

func get_all_fluid_presets() -> Dictionary:
	return _fluids

# =============================================================================
# STORY DATA (story.json)
# =============================================================================

func _load_stories() -> void:
	_stories.clear()
	_story_settings.clear()
	var data := _load_json("res://data/story.json")
	if data.is_empty():
		push_warning("[DataManager] No story data found.")
		return
	
	# Charger les global_settings
	var settings: Variant = data.get("global_settings", {})
	if settings is Dictionary:
		_story_settings = settings as Dictionary
	
	# Charger les séquences indexées par ID
	var sequences: Variant = data.get("sequences", [])
	if sequences is Array:
		for seq in sequences:
			if seq is Dictionary:
				var seq_dict := seq as Dictionary
				var seq_id: String = str(seq_dict.get("id", ""))
				if seq_id != "":
					_stories[seq_id] = seq_dict

## Retourne une séquence de story par son ID
func get_story(story_id: String) -> Dictionary:
	return _stories.get(story_id, {})

## Retourne les paramètres globaux des stories
func get_story_settings() -> Dictionary:
	return _story_settings
