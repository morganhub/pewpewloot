extends Node

## StoryManager — Autoload qui gère le lancement des cinématiques.
## Instancie dynamiquement le StoryOverlay et bloque les inputs en dessous.

# =============================================================================
# SIGNALS
# =============================================================================

signal story_finished

# =============================================================================
# ÉTAT INTERNE
# =============================================================================

const STORY_OVERLAY_SCENE := preload("res://scenes/StoryOverlay.tscn")

var _current_overlay: CanvasLayer = null
var _is_playing: bool = false

# =============================================================================
# API PUBLIQUE
# =============================================================================

## Lance une cinématique par son ID. Retourne quand elle est terminée (await).
## run_while_paused: si true, l'overlay reste actif quand l'arbre est en pause (début de niveau en Game).
## debug_mode: affiche id/world/level/wave et un bouton Next (éditeur uniquement).
func play_story(story_id: String, run_while_paused: bool = false, debug_mode: bool = false) -> void:
	if _is_playing:
		push_warning("[StoryManager] A story is already playing.")
		return
	
	# Vérifier que la story existe dans DataManager
	var story_data := DataManager.get_story(story_id)
	if story_data.is_empty():
		push_warning("[StoryManager] Story not found: " + story_id)
		return
	
	_is_playing = true
	print("[StoryManager] Launching story: ", story_id)
	
	# Instancier l'overlay
	_current_overlay = STORY_OVERLAY_SCENE.instantiate()
	if run_while_paused:
		_current_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_current_overlay)
	
	# Connecter le signal de fin
	_current_overlay.story_finished.connect(_on_story_finished, CONNECT_ONE_SHOT)
	
	# Lancer la lecture (avec mode debug si demandé)
	_current_overlay.play(story_id, debug_mode)
	
	# Attendre la fin
	await _current_overlay.story_finished

## Vérifie si une cinématique est en cours
func is_playing() -> bool:
	return _is_playing

# =============================================================================
# HELPERS : Vérification et lancement depuis un monde ou niveau
# =============================================================================

## Vérifie et lance la story d'un monde si elle n'a pas été vue.
## Retourne true si une story a été lancée, false sinon.
func check_and_play_world_story(world_id: String) -> bool:
	var world_data := DataManager.get_world(world_id)
	var world_story_id: String = str(world_data.get("story_id", ""))
	
	if world_story_id != "" and not ProfileManager.has_viewed_story(world_story_id):
		await play_story(world_story_id)
		ProfileManager.mark_story_viewed(world_story_id)
		return true
	
	return false

## Vérifie et lance la story d'un niveau spécifique si elle n'a pas été vue.
## Retourne true si une story a été lancée, false sinon.
func check_and_play_level_story(world_id: String, level_index: int) -> bool:
	var world_data := DataManager.get_world(world_id)
	var levels: Variant = world_data.get("levels", [])
	if not (levels is Array):
		return false
	
	var levels_array := levels as Array
	if level_index < 0 or level_index >= levels_array.size():
		return false
	
	var level_data: Variant = levels_array[level_index]
	if not (level_data is Dictionary):
		return false
	
	var level_story_id: String = str((level_data as Dictionary).get("story_id", ""))
	
	if level_story_id != "" and not ProfileManager.has_viewed_story(level_story_id):
		await play_story(level_story_id)
		ProfileManager.mark_story_viewed(level_story_id)
		return true
	
	return false

# =============================================================================
# CALLBACKS INTERNES
# =============================================================================

func _on_story_finished() -> void:
	_is_playing = false
	
	# Nettoyer l'overlay
	if _current_overlay != null:
		_current_overlay.queue_free()
		_current_overlay = null
	
	print("[StoryManager] Story finished, overlay cleaned up.")
	story_finished.emit()

## Mode debug (éditeur) : enchaîne toutes les séquences story sur le HomeScreen.
## Une même overlay est réutilisée ; à la fin de chaque séquence, le bouton "Next" passe à la suivante.
func play_debug_story_flow() -> void:
	if not OS.has_feature("editor"):
		return
	var ids: Array = DataManager.get_story_sequence_ids()
	if ids.is_empty():
		push_warning("[StoryManager] No story sequences for debug flow.")
		return
	# Une seule overlay pour tout le flux
	_current_overlay = STORY_OVERLAY_SCENE.instantiate()
	get_tree().root.add_child(_current_overlay)
	for story_id in ids:
		var sid: String = str(story_id)
		_current_overlay.play(sid, true)
		await _current_overlay.story_finished
	if _current_overlay != null:
		_current_overlay.queue_free()
		_current_overlay = null
	print("[StoryManager] Debug story flow finished.")
