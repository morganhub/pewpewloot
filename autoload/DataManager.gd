extends Node

## DataManager — Charge et expose toutes les données de jeu depuis les fichiers JSON.
## Ces données sont read-only et chargées au démarrage.

# Données chargées
var _worlds: Dictionary = {}        # world_id -> data
var _ships: Array = []
var _enemies: Dictionary = {}       # enemy_id -> data
var _bosses: Dictionary = {}        # boss_id -> data
var _move_patterns: Dictionary = {} # pattern_id -> data
var _missile_patterns_player: Dictionary = {} # pattern_id -> data
var _missile_patterns_enemy: Dictionary = {} # pattern_id -> data
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
var _wave_types_config: Dictionary = {} # wave_types.json data (config par type de vague)
var _idle_factory_config: Dictionary = {} # idle_factory.json data (chaine de production HomeScreen)
var _override_protocols: Dictionary = {} # override_protocols.json data
var _skills: Dictionary = {} # skills.json data
var _obstacles: Dictionary = {} # obstacle_id -> data
var _obstacles_global_settings: Dictionary = {} # global_settings from obstacles.json
var _fluids: Dictionary = {} # fluid_preset_id -> data
var _stories: Dictionary = {} # story_id -> sequence data
var _story_settings: Dictionary = {} # global_settings from story.json
var _story_order: Array = [] # sequence ids in order from story.json (for debug flow)

var _default_unlocked_ships: Array = []

var _full_data_loaded: bool = false

func _ready() -> void:
	_load_game_config()
	_load_wave_types_config()
	_load_override_protocols()
	_load_idle_factory_config()
	pass

## Call this during bootstrap loading (e.g. from LoadingScreen). Loads all remaining JSON data.
func load_remaining_data() -> void:
	if _full_data_loaded:
		return
	_load_worlds()
	_load_ships()
	_load_patterns()
	_load_missiles()
	_load_powers()
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
	_full_data_loaded = true

func _load_all_data() -> void:
	_load_game_config()
	_load_override_protocols()
	load_remaining_data()


# =============================================================================
# SKILLS DATA (skills.json)
# =============================================================================

func _load_skills() -> void:
	var data := _load_json("res://data/skills.json")
	if not data.is_empty():
		_skills = data

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

## Returns the XP curve base, used in xp_for_level(N) = base * pow(N, exponent).
## Read from data/game.json -> progression (centralized).
## Falls back to data/skills.json then to legacy default for safety.
func get_xp_curve_base() -> int:
	var prog: Dictionary = _get_progression_config()
	if prog.has("xp_curve_base"):
		return int(prog.get("xp_curve_base"))
	return int(_skills.get("xp_curve_base", 100))

func get_xp_curve_exponent() -> float:
	var prog: Dictionary = _get_progression_config()
	if prog.has("xp_curve_exponent"):
		return float(prog.get("xp_curve_exponent"))
	return float(_skills.get("xp_curve_exponent", 1.5))

## Ratio appliquee au score pour le convertir en XP brute avant les multiplicateurs.
## Permet de decoupler l'echelle de score (UI/feedback) du rythme de progression XP.
func get_xp_per_score_ratio() -> float:
	var prog: Dictionary = _get_progression_config()
	return float(prog.get("xp_per_score_ratio", 1.0))

## Cap dur du niveau joueur. 0 = pas de cap.
func get_max_player_level() -> int:
	var prog: Dictionary = _get_progression_config()
	return int(prog.get("max_player_level", 0))

## Multiplicateur d'XP applique pour les runs faites dans un monde donne.
## Plus le world est "haut", plus le multiplicateur recompense les level-ups.
func get_world_xp_multiplier(world_id: String) -> float:
	var prog: Dictionary = _get_progression_config()
	var v: Variant = prog.get("world_xp_multipliers", {})
	if v is Dictionary:
		var mult: Variant = (v as Dictionary).get(world_id, 1.0)
		return maxf(0.0, float(mult))
	return 1.0

func _get_progression_config() -> Dictionary:
	var v: Variant = _game_config.get("progression", {})
	return v if v is Dictionary else {}

# =============================================================================
# GAME CONFIG (game.json)
# =============================================================================

func _load_game_config() -> void:
	_game_config = _load_json("res://data/game.json")

func _load_wave_types_config() -> void:
	_wave_types_config = _load_json("res://data/wave_types.json")
	_freemode_config = _load_json("res://data/freemode.json")

func _load_override_protocols() -> void:
	_override_protocols = _load_json("res://data/override_protocols.json")

func _load_idle_factory_config() -> void:
	_idle_factory_config = _load_json("res://data/idle_factory.json")

func get_idle_factory_config() -> Dictionary:
	return _idle_factory_config

func get_override_protocols_config() -> Dictionary:
	return _override_protocols.duplicate(true)

func get_override_protocols_ui_settings() -> Dictionary:
	var ui_settings: Variant = _override_protocols.get("ui_settings", {})
	if ui_settings is Dictionary:
		return (ui_settings as Dictionary).duplicate(true)
	return {}

func get_override_protocols() -> Array:
	var protocols: Variant = _override_protocols.get("protocols", [])
	if protocols is Array:
		return (protocols as Array).duplicate(true)
	return []

func get_override_protocol(protocol_id: String) -> Dictionary:
	for protocol_variant in get_override_protocols():
		if not (protocol_variant is Dictionary):
			continue
		var protocol_data := protocol_variant as Dictionary
		if str(protocol_data.get("id", "")) == protocol_id:
			return protocol_data.duplicate(true)
	return {}

func get_override_protocol_settings(protocol_id: String) -> Dictionary:
	var protocol: Dictionary = get_override_protocol(protocol_id)
	var settings: Variant = protocol.get("settings", {})
	if settings is Dictionary:
		return (settings as Dictionary).duplicate(true)
	return {}

func get_override_reward_multiplier(active_count: int) -> float:
	var settings: Dictionary = get_override_protocols_ui_settings()
	return _resolve_override_multiplier_for_count(
		settings.get("reward_multiplier_by_active_count", {}),
		active_count,
		float(settings.get("base_reward_multiplier", 1.0)),
		float(settings.get("per_protocol_multiplier", 0.2))
	)

func get_override_crystal_multiplier(active_count: int) -> float:
	var settings: Dictionary = get_override_protocols_ui_settings()
	return _resolve_override_multiplier_for_count(
		settings.get("crystal_multiplier_by_active_count", settings.get("reward_multiplier_by_active_count", {})),
		active_count,
		float(settings.get("base_crystal_multiplier", 1.0)),
		float(settings.get("per_protocol_crystal_multiplier", float(settings.get("per_protocol_multiplier", 0.2))))
	)

func _resolve_override_multiplier_for_count(
	count_data: Variant,
	active_count: int,
	fallback_base: float,
	fallback_per_protocol: float
) -> float:
	var count: int = maxi(0, mini(active_count, 10))
	if count_data is Dictionary:
		var mapping := count_data as Dictionary
		if mapping.has(str(count)):
			return maxf(0.0, float(mapping.get(str(count), fallback_base)))
		# Fallback to nearest previous configured value.
		for i in range(count, -1, -1):
			var key := str(i)
			if mapping.has(key):
				return maxf(0.0, float(mapping.get(key, fallback_base)))

	if count_data is Array:
		var values := count_data as Array
		if values.size() > count:
			return maxf(0.0, float(values[count]))
		if values.size() > 0:
			return maxf(0.0, float(values[values.size() - 1]))

	return maxf(0.0, fallback_base + fallback_per_protocol * float(count))

func get_game_config() -> Dictionary:
	return _game_config
	
func get_game_data() -> Dictionary:
	return _game_config

func _get_config_path(path: Array, fallback: Variant = {}) -> Variant:
	var current: Variant = _game_config
	for key in path:
		if not (current is Dictionary):
			return fallback
		var dict := current as Dictionary
		if not dict.has(key):
			return fallback
		current = dict.get(key)
	return current

func get_killstreak_config() -> Dictionary:
	var scoring: Variant = _get_config_path(["gameplay", "scoring"], _game_config.get("scoring", {}))
	if not (scoring is Dictionary):
		return {}
	var cfg: Variant = (scoring as Dictionary).get("killstreak_system", {})
	if cfg is Dictionary:
		return (cfg as Dictionary).duplicate(true)
	return {}

func get_bonus_crystals_config() -> Dictionary:
	var scoring: Variant = _get_config_path(["gameplay", "scoring"], _game_config.get("scoring", {}))
	if not (scoring is Dictionary):
		return {}
	var cfg: Variant = (scoring as Dictionary).get("bonus_crystals", {})
	if cfg is Dictionary:
		return (cfg as Dictionary).duplicate(true)
	return {}

func get_explosions_config() -> Dictionary:
	var cfg: Variant = _get_config_path(["gameplay", "explosions"], _game_config.get("explosions", {}))
	if cfg is Dictionary:
		return (cfg as Dictionary).duplicate(true)
	return {}

func get_fire_pattern_drops_config() -> Dictionary:
	var cfg: Variant = _get_config_path(["gameplay", "fire_pattern_drops"], _game_config.get("fire_pattern_drops", {}))
	if cfg is Dictionary:
		return (cfg as Dictionary).duplicate(true)
	return {}

# Pre-migration locations of wave-type configs inside game.json (legacy fallback).
const _WAVE_TYPE_LEGACY_GAME_KEYS: Dictionary = {
	"swarm": "swarm",
	"tank": "tank_wave",
	"path_trial": "path_trial_defaults",
	"gate_runner": "gate_runner",
	"pong": "pong"
}

## Config centralisée par type de vague (data/wave_types.json). La clé est la
## valeur de wave.type des world_x.json. Fallback legacy vers game.json pour
## les anciens emplacements gameplay.<key>.
func get_wave_type_config(wave_type: String) -> Dictionary:
	var cfg: Variant = _wave_types_config.get(wave_type, {})
	if cfg is Dictionary and not (cfg as Dictionary).is_empty():
		return (cfg as Dictionary).duplicate(true)
	var legacy_key: String = str(_WAVE_TYPE_LEGACY_GAME_KEYS.get(wave_type, wave_type))
	var legacy: Variant = _get_config_path(["gameplay", legacy_key], _game_config.get(legacy_key, {}))
	if legacy is Dictionary:
		return (legacy as Dictionary).duplicate(true)
	return {}

## Clé GLOBALE à la racine de wave_types.json (hors blocs par type) — ex.
## effect_labels_enabled : labels texte des effets sur les objets, béquille
## lisibilité tant que les assets ne sont pas explicites (applicable à tous
## les types, surchargeable par bloc/vague).
func get_wave_types_global(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = _wave_types_config.get(key, fallback)
	return fallback if value is Dictionary else value

## Tous les types de vagues déclarés dans wave_types.json (clés de config).
## Un type = un bloc Dictionary — les clés globales scalaires de la racine
## (effect_labels_enabled...) ne sont pas des types.
func get_wave_type_ids() -> Array:
	var ids: Array = []
	for key in _wave_types_config.keys():
		var id: String = str(key)
		if not id.begins_with("_") and _wave_types_config.get(key) is Dictionary:
			ids.append(id)
	return ids

# =============================================================================
# FREE MODE (data/freemode.json)
# =============================================================================

var _freemode_config: Dictionary = {}

func get_freemode_config() -> Dictionary:
	return _freemode_config.duplicate(true)

## Modes jouables en mode libre = intersection des types de wave_types.json et
## des blocs déclarés dans freemode.json > modes (liste dynamique : ajouter un
## type + son bloc freemode suffit à le faire apparaître dans le menu).
func get_freemode_mode_ids() -> Array:
	var modes_v: Variant = _freemode_config.get("modes", {})
	if not (modes_v is Dictionary):
		return []
	var wave_ids: Array = get_wave_type_ids()
	var ids: Array = []
	for key in (modes_v as Dictionary).keys():
		var id: String = str(key)
		if not id.begins_with("_") and wave_ids.has(id):
			ids.append(id)
	return ids

func get_freemode_mode_config(wave_type: String) -> Dictionary:
	var modes_v: Variant = _freemode_config.get("modes", {})
	if modes_v is Dictionary:
		var cfg: Variant = (modes_v as Dictionary).get(wave_type, {})
		if cfg is Dictionary:
			return (cfg as Dictionary).duplicate(true)
	return {}

## Insère un niveau construit au runtime (mode libre) dans le registre des
## niveaux : toutes les lectures get_level_data (background, wave counter,
## seuils de score, prewarm) restent ainsi cohérentes.
func register_synthetic_level(level_id: String, data: Dictionary) -> void:
	if level_id == "":
		return
	_levels[level_id] = data.duplicate(true)

func get_gate_runner_config() -> Dictionary:
	return get_wave_type_config("gate_runner")

func get_path_trial_defaults() -> Dictionary:
	return get_wave_type_config("path_trial")

func get_pong_config() -> Dictionary:
	return get_wave_type_config("pong")

func get_shared_asset_config(asset_id: String) -> Dictionary:
	var shared_assets: Variant = _get_config_path(["common", "shared_assets"], _game_config.get("shared_assets", {}))
	if not (shared_assets is Dictionary):
		return {}

	var raw_entry: Variant = (shared_assets as Dictionary).get(asset_id, {})
	if raw_entry is Dictionary:
		return (raw_entry as Dictionary).duplicate(true)

	var raw_path: String = str(raw_entry).strip_edges()
	if raw_path == "":
		return {}
	return {"asset": raw_path}

func get_shared_asset_path(asset_id: String, fallback: String = "") -> String:
	var cfg: Dictionary = get_shared_asset_config(asset_id)
	var path: String = str(cfg.get("asset", cfg.get("path", ""))).strip_edges()
	if path != "" and ResourceLoader.exists(path):
		return path
	return fallback

func get_shared_crystal_icon_config() -> Dictionary:
	var cfg: Dictionary = get_shared_asset_config("crystal_icon")
	var fallback := "res://assets/ui/icons/crystal.png"
	var asset_path := str(cfg.get("asset", "")).strip_edges()

	if asset_path == "" or not ResourceLoader.exists(asset_path):
		if ResourceLoader.exists(fallback):
			asset_path = fallback
		elif asset_path == "":
			asset_path = fallback
	cfg["asset"] = asset_path

	if not cfg.has("animation_repeat_seconds"):
		cfg["animation_repeat_seconds"] = 0.0
	if not cfg.has("animation_type"):
		cfg["animation_type"] = "loop"
	if not cfg.has("animation_duration"):
		cfg["animation_duration"] = 2.0
	return cfg

func get_shared_crystal_icon_path() -> String:
	var fallback := "res://assets/ui/icons/crystal.png"
	var cfg: Dictionary = get_shared_crystal_icon_config()
	var path := str(cfg.get("asset", fallback)).strip_edges()
	if path != "" and ResourceLoader.exists(path):
		return path
	if ResourceLoader.exists(fallback):
		return fallback
	return fallback

func get_texture_from_resource_path(path: String) -> Texture2D:
	var clean_path := path.strip_edges()
	if clean_path.begins_with("shared:"):
		var shared_id := clean_path.trim_prefix("shared:")
		clean_path = get_shared_asset_path(shared_id, "")
	if clean_path == "" or not ResourceLoader.exists(clean_path):
		return null
	var resource: Resource = ResourceLoader.load(clean_path, "", ResourceLoader.CACHE_MODE_REUSE)
	return _extract_texture_from_resource(resource, clean_path)

func _extract_texture_from_resource(resource: Resource, source_path: String = "") -> Texture2D:
	if resource is Texture2D:
		return resource as Texture2D
	if resource is SpriteFrames:
		var frames := resource as SpriteFrames
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name):
			var names: PackedStringArray = frames.get_animation_names()
			if names.is_empty():
				return _fallback_texture_from_spriteframes_path(source_path)
			anim_name = StringName(names[0])
		if frames.get_frame_count(anim_name) <= 0:
			return _fallback_texture_from_spriteframes_path(source_path)
		var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
		if frame_tex != null:
			return frame_tex
		return _fallback_texture_from_spriteframes_path(source_path)
	return null

func _fallback_texture_from_spriteframes_path(source_path: String) -> Texture2D:
	var clean_path := source_path.strip_edges()
	if clean_path == "":
		return null

	var base_path := clean_path.get_basename()
	if base_path == "":
		return null

	var candidates: Array[String] = [
		base_path + ".png",
		base_path + ".webp",
		base_path + ".jpg",
		base_path + ".jpeg"
	]

	for candidate in candidates:
		if not ResourceLoader.exists(candidate):
			continue
		var fallback_res: Resource = ResourceLoader.load(candidate, "", ResourceLoader.CACHE_MODE_REUSE)
		if fallback_res is Texture2D:
			return fallback_res as Texture2D
	return null

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

## Retourne les skin_overrides d'un monde (enemies, bosses, obstacles)
func get_world_skin_overrides(world_id: String) -> Dictionary:
	var world: Dictionary = _worlds.get(world_id, {})
	var overrides: Variant = world.get("skin_overrides", {})
	if overrides is Dictionary:
		return overrides as Dictionary
	return {}

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
	_missile_patterns_player.clear()
	_missile_patterns_enemy.clear()
	
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
					_missile_patterns_player[p_id] = p_dict
	
	# Missile patterns - ENEMY
	var missile_enemy_data := _load_json("res://data/patterns/missile_patterns_enemy.json")
	var raw_missile_enemy: Variant = missile_enemy_data.get("patterns", [])
	if raw_missile_enemy is Array:
		for pattern in raw_missile_enemy:
			if pattern is Dictionary:
				var p_dict := pattern as Dictionary
				var p_id: String = str(p_dict.get("id", ""))
				if p_id != "":
					_missile_patterns_enemy[p_id] = p_dict

## Retourne un move pattern par ID
func get_move_pattern(pattern_id: String) -> Dictionary:
	return _move_patterns.get(pattern_id, {})

## Retourne tous les move patterns
func get_all_move_patterns() -> Array:
	return _move_patterns.values()

## Retourne un missile pattern joueur par ID
func get_player_missile_pattern(pattern_id: String) -> Dictionary:
	return _missile_patterns_player.get(pattern_id, {})

## Retourne tous les missile patterns joueur
func get_all_player_missile_patterns() -> Array:
	return _missile_patterns_player.values()

## Retourne un missile pattern ennemi par ID
func get_enemy_missile_pattern(pattern_id: String) -> Dictionary:
	return _missile_patterns_enemy.get(pattern_id, {})

## Retourne tous les missile patterns ennemi
func get_all_enemy_missile_patterns() -> Array:
	return _missile_patterns_enemy.values()

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

func get_all_super_powers() -> Array:
	return _super_powers.values()

func get_unique_power(power_id: String) -> Dictionary:
	return _unique_powers.get(power_id, {})

func get_all_unique_powers() -> Array:
	return _unique_powers.values()

func get_unique_power_ids() -> Array:
	var ids: Array = _unique_powers.keys()
	ids.sort()
	return ids

func get_all_boss_powers() -> Array:
	return _boss_powers.values()

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
		for unique in (raw_uniques as Array):
			if not (unique is Dictionary):
				continue
			var unique_dict := _sanitize_unique_definition(unique as Dictionary)
			var unique_id: String = str(unique_dict.get("id", "")).strip_edges()
			if unique_id == "":
				continue
			_uniques.append(unique_dict)
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
	var rarity_colors: Variant = _get_config_path(["items", "rarity", "colors"], _game_config.get("rarity_colors", {}))
	if rarity_colors is Dictionary and (rarity_colors as Dictionary).has(rarity_id):
		return Color.html(str((rarity_colors as Dictionary).get(rarity_id, "#FFFFFF")))

	var rarity := get_rarity(rarity_id)
	var color_code := str(rarity.get("color", "#FFFFFF"))
	return Color.html(color_code)

## Retourne le chemin de la frame (bordure) associée à une rareté
func get_rarity_frame_path(rarity_id: String) -> String:
	var frames_v: Variant = _get_config_path(["items", "rarity", "frames"], _game_config.get("rarity_frames", {}))
	var frames: Dictionary = frames_v if frames_v is Dictionary else {}
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

func _sanitize_unique_definition(raw_unique: Dictionary) -> Dictionary:
	var unique := raw_unique.duplicate(true)

	# Keep at most 6 meaningful stats and drop zero-value vestiges.
	var stats_raw: Variant = unique.get("stats", {})
	var cleaned_stats: Dictionary = {}
	if stats_raw is Dictionary:
		var stat_count: int = 0
		for raw_key in (stats_raw as Dictionary).keys():
			if stat_count >= 6:
				break
			var stat_key: String = str(raw_key)
			var stat_value: float = float((stats_raw as Dictionary).get(raw_key, 0.0))
			if absf(stat_value) < 0.001:
				continue
			cleaned_stats[stat_key] = stat_value
			stat_count += 1
	if cleaned_stats.is_empty():
		cleaned_stats["power"] = 10.0
	unique["stats"] = cleaned_stats

	# Enforce unique power presence and validity.
	var power_id: String = str(unique.get("unique_power_id", unique.get("special_ability_id", ""))).strip_edges()
	if power_id == "" or get_unique_power(power_id).is_empty():
		var available_ids: Array = get_unique_power_ids()
		if available_ids.size() > 0:
			power_id = str(available_ids[0])
	if power_id != "":
		unique["unique_power_id"] = power_id
		unique["special_ability_id"] = power_id

	return unique

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
	_full_data_loaded = false
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
	var raw_gs: Variant = data.get("global_settings", {})
	if raw_gs is Dictionary:
		_obstacles_global_settings = (raw_gs as Dictionary).duplicate(true)
	var raw_obstacles: Variant = data.get("obstacles", {})
	if raw_obstacles is Dictionary:
		for key in raw_obstacles:
			var entry: Variant = raw_obstacles[key]
			if entry is Dictionary:
				var o_dict := entry as Dictionary
				var o_id: String = str(o_dict.get("id", key))
				_obstacles[o_id] = o_dict

func get_obstacle(obstacle_id: String) -> Dictionary:
	return _obstacles.get(obstacle_id, {})

func get_all_obstacles() -> Dictionary:
	return _obstacles

func get_obstacles_global_settings() -> Dictionary:
	return _obstacles_global_settings

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
	_story_order.clear()
	var data := _load_json("res://data/story.json")
	if data.is_empty():
		push_warning("[DataManager] No story data found.")
		return
	
	# Charger les global_settings
	var settings: Variant = data.get("global_settings", {})
	if settings is Dictionary:
		_story_settings = settings as Dictionary
	
	# Charger les séquences indexées par ID (ordre préservé pour le debug)
	var sequences: Variant = data.get("sequences", [])
	if sequences is Array:
		for seq in sequences:
			if seq is Dictionary:
				var seq_dict := seq as Dictionary
				var seq_id: String = str(seq_dict.get("id", ""))
				if seq_id != "":
					_stories[seq_id] = seq_dict
					_story_order.append(seq_id)

## Retourne la story "intro monde" pour un monde (world présent, level absent ou null).
## Déprécié: utiliser get_story_for_trigger(world_id, 0, "start") pour l'intro.
func get_story_for_world(world_id: String) -> Dictionary:
	return get_story_for_trigger(world_id, 0, "start")

## Retourne la story "avant niveau" pour (world_id, level_index).
## Déprécié: utiliser get_story_for_trigger(world_id, level_index, "start").
func get_story_for_level(world_id: String, level_index: int) -> Dictionary:
	return get_story_for_trigger(world_id, level_index, "start")

## Retourne une séquence pour (world_id, level_index, wave_trigger).
## wave_trigger: "start" (début niveau / intro monde), entier 1-based (avant cette wave), "end" (après boss).
## level_index 0-based. Intro monde = pas de level en JSON, jouée au level_index 0 + wave "start".
## Pour level_index 0 + "start", on renvoie d'abord l'intro monde (sans level) si elle existe.
func get_story_for_trigger(world_id: String, level_index: int, wave_trigger: Variant) -> Dictionary:
	var level_one_based: int = level_index + 1
	var want_start: bool = (str(wave_trigger) == "start")
	var want_end: bool = (str(wave_trigger) == "end")
	var want_wave: int = -1
	if not want_start and not want_end and wave_trigger != null:
		if wave_trigger is int:
			want_wave = int(wave_trigger)
		elif wave_trigger is float:
			want_wave = int(wave_trigger)
		else:
			want_wave = int(str(wave_trigger))
	# Pour (world, 0, "start"), priorité à l'intro monde (sans level)
	if want_start and level_index == 0:
		for seq_id in _stories:
			var seq: Dictionary = _stories[seq_id]
			if str(seq.get("world", "")) != world_id:
				continue
			if seq.get("level", null) != null:
				continue
			var sw: Variant = seq.get("wave", null)
			if str(sw) != "start":
				continue
			return seq
	for seq_id in _stories:
		var seq: Dictionary = _stories[seq_id]
		var w: String = str(seq.get("world", ""))
		if w != world_id:
			continue
		var lv: Variant = seq.get("level", null)
		var seq_level_one: int = -1
		if lv != null and (lv is int or lv is float):
			seq_level_one = int(lv) if lv is int else int(float(lv))
		var seq_wave: Variant = seq.get("wave", null)
		var seq_want_start: bool = (str(seq_wave) == "start")
		var seq_want_end: bool = (str(seq_wave) == "end")
		var seq_wave_num: int = -1
		if not seq_want_start and not seq_want_end and seq_wave != null:
			var sw_str: String = str(seq_wave)
			if sw_str.is_valid_int():
				seq_wave_num = int(sw_str)
			elif seq_wave is int:
				seq_wave_num = int(seq_wave)
			elif seq_wave is float:
				seq_wave_num = int(seq_wave)
			else:
				seq_wave_num = int(sw_str)
		# level match: intro (no level) only for level_index 0; else seq level must match level_one_based
		if seq_level_one < 0:
			if level_index != 0:
				continue
		elif seq_level_one != level_one_based:
			continue
		# wave match
		if want_start:
			if not seq_want_start:
				continue
			return seq
		if want_end:
			if not seq_want_end:
				continue
			return seq
		if want_wave >= 0:
			if seq_wave_num != want_wave:
				continue
			return seq
	return {}

## Retourne toutes les séquences "start" pour (world_id, level_index). Permet de jouer intro + level start pour le niveau 0.
func get_stories_for_trigger_start(world_id: String, level_index: int) -> Array:
	var out: Array = []
	var level_one_based: int = level_index + 1
	# Intro monde (sans level) pour level_index 0
	if level_index == 0:
		for seq_id in _stories:
			var seq: Dictionary = _stories[seq_id]
			if str(seq.get("world", "")) != world_id or seq.get("level", null) != null:
				continue
			var sw: Variant = seq.get("wave", null)
			if str(sw) != "start":
				continue
			out.append(seq)
	# Story niveau (level N)
	for seq_id in _stories:
		var seq: Dictionary = _stories[seq_id]
		if str(seq.get("world", "")) != world_id:
			continue
		var lv: Variant = seq.get("level", null)
		if lv == null:
			continue
		var lv_int: int = int(lv) if lv is int else int(float(lv))
		if lv_int != level_one_based:
			continue
		var sw: Variant = seq.get("wave", null)
		if str(sw) != "start":
			continue
		out.append(seq)
	return out

## Retourne une séquence de story par son ID
func get_story(story_id: String) -> Dictionary:
	return _stories.get(story_id, {})

## Retourne les IDs des séquences dans l'ordre du fichier story.json (pour le mode debug).
func get_story_sequence_ids() -> Array:
	return _story_order.duplicate()

## Retourne les paramètres globaux des stories
func get_story_settings() -> Dictionary:
	return _story_settings
