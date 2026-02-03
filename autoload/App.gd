extends Node

## App — Point d'accès central aux données de jeu.
## Délègue à DataManager pour les données (mondes, vaisseaux, etc.)
## Gère les métadonnées de session (selected_world_id, selected_level_index, etc.)

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
