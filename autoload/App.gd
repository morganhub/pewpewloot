extends Node

## App — Point d'accès central aux données de jeu.
## Délègue à DataManager pour les données (mondes, vaisseaux, etc.)
## Gère les métadonnées de session (selected_world_id, selected_level_index, etc.)

var current_world_id: String = "world_1"
var current_level_index: int = 0

func _ready() -> void:
	pass

func play_music(path: String, fade_duration: float = 1.0) -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_music"):
		am.play_music(path, fade_duration)

func play_menu_music() -> void:
	var config = DataManager.get_game_config()
	var main_menu = config.get("main_menu", {})
	var music_path = str(main_menu.get("music", ""))
	if music_path != "":
		play_music(music_path, 1.0)

# =============================================================================
# ACCESSEURS DONNÉES (délégation à DataManager)
# =============================================================================

## Retourne tous les mondes (triés par ordre)
func get_worlds() -> Array:
	return DataManager.get_worlds()

## Retourne un monde par son ID
func get_world(world_id: String) -> Dictionary:
	return DataManager.get_world(world_id)

## Retourne le nombre de niveaux d'un monde
func get_world_level_count(world_id: String) -> int:
	return DataManager.get_world_level_count(world_id)

## Retourne tous les vaisseaux
func get_ships() -> Array:
	return DataManager.get_ships()

## Retourne un vaisseau par son ID
func get_ship_by_id(ship_id: String) -> Dictionary:
	return DataManager.get_ship(ship_id)

## Retourne les IDs des slots d'équipement
func get_slots() -> Array:
	return DataManager.get_slot_ids()

## Retourne les vaisseaux débloqués par défaut
func get_default_unlocked_ships() -> Array:
	return DataManager.get_default_unlocked_ships()
