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
func play_story(story_id: String) -> void:
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
	get_tree().root.add_child(_current_overlay)
	
	# Connecter le signal de fin
	_current_overlay.story_finished.connect(_on_story_finished, CONNECT_ONE_SHOT)
	
	# Lancer la lecture
	_current_overlay.play(story_id)
	
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
