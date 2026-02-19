extends CanvasLayer

## StoryOverlay — Système de cinématiques/dialogues data-driven.
## Affiche des personnages avec bulles de dialogue, animés par Tweens.
## Usage: StoryManager.play_story("story_world_1_intro")

# =============================================================================
# SIGNALS
# =============================================================================

signal story_finished

# =============================================================================
# RÉFÉRENCES SCÈNE
# =============================================================================

@onready var bg_dim: ColorRect = $BgDim
@onready var container: Control = $BgDim/Container

# =============================================================================
# ÉTAT INTERNE
# =============================================================================

var _settings: Dictionary = {}
var _story_data: Dictionary = {}
var _is_playing: bool = false

# Noeuds dynamiques actuels
var _current_portrait: TextureRect = null
var _current_bubble: Control = null

# =============================================================================
# CONFIGURATION (lue depuis global_settings)
# =============================================================================

var _character_size: Vector2 = Vector2(200, 300)
var _anim_speed: float = 0.6
var _anim_ease_type: String = "ease_in_out"
var _exit_anim_type: String = "slide"
var _text_interval: float = 2.5
var _bubble_left_asset: String = ""
var _bubble_right_asset: String = ""

# =============================================================================
# API PUBLIQUE
# =============================================================================

## Lance la lecture d'une séquence de story
func play(story_id: String) -> void:
	if _is_playing:
		push_warning("[StoryOverlay] Already playing a story.")
		return
	
	_story_data = DataManager.get_story(story_id)
	if _story_data.is_empty():
		push_error("[StoryOverlay] Story not found: " + story_id)
		story_finished.emit()
		return
	
	_settings = DataManager.get_story_settings()
	_apply_settings()
	_is_playing = true
	
	print("[StoryOverlay] Playing story: ", story_id)
	
	# Fade in le fond sombre
	await _fade_bg_in()
	
	# Jouer tous les dialogues
	var dialogues: Variant = _story_data.get("dialogues", [])
	if dialogues is Array:
		for i in range((dialogues as Array).size()):
			var dialogue: Variant = (dialogues as Array)[i]
			if dialogue is Dictionary:
				await _play_dialogue(dialogue as Dictionary)
	
	# Fade out le fond
	await _fade_bg_out()
	
	_is_playing = false
	print("[StoryOverlay] Story finished: ", story_id)
	story_finished.emit()

# =============================================================================
# SETTINGS
# =============================================================================

func _apply_settings() -> void:
	var char_size: Variant = _settings.get("character_size", {})
	if char_size is Dictionary:
		var cs := char_size as Dictionary
		_character_size = Vector2(
			float(cs.get("x", 200)),
			float(cs.get("y", 300))
		)
	
	_anim_speed = float(_settings.get("anim_speed", 0.6))
	_anim_ease_type = str(_settings.get("anim_ease_type", "ease_in_out"))
	_exit_anim_type = str(_settings.get("exit_anim_type", "slide"))
	_text_interval = float(_settings.get("text_interval", 2.5))
	_bubble_left_asset = str(_settings.get("bubble_left_asset", ""))
	_bubble_right_asset = str(_settings.get("bubble_right_asset", ""))

# =============================================================================
# ANIMATIONS DE FOND
# =============================================================================

func _fade_bg_in() -> void:
	bg_dim.color = Color(0, 0, 0, 0)
	var tween := create_tween()
	tween.tween_property(bg_dim, "color", Color(0, 0, 0, 0.7), 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _fade_bg_out() -> void:
	var tween := create_tween()
	tween.tween_property(bg_dim, "color", Color(0, 0, 0, 0), 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

# =============================================================================
# LECTURE D'UN DIALOGUE
# =============================================================================

func _play_dialogue(dialogue: Dictionary) -> void:
	var speaker_asset: String = str(dialogue.get("speaker_asset", ""))
	var side: String = str(dialogue.get("side", "left"))
	var text_keys: Variant = dialogue.get("text_keys", [])
	
	# Si un seul personnage (pas de "side" explicite), forcer à gauche
	if side == "":
		side = "left"
	
	# Créer et animer l'entrée du personnage
	var portrait := _create_portrait(speaker_asset, side)
	_current_portrait = portrait
	container.add_child(portrait)
	await _animate_enter(portrait, side)
	
	# Afficher chaque bulle de texte
	if text_keys is Array:
		for i in range((text_keys as Array).size()):
			var key: String = str((text_keys as Array)[i])
			var text: String = LocaleManager.get_story_string(key)
			
			# Créer la bulle
			var bubble := _create_bubble(text, side)
			_current_bubble = bubble
			container.add_child(bubble)
			
			# Fade in la bulle
			bubble.modulate.a = 0.0
			var fade_in := create_tween()
			fade_in.tween_property(bubble, "modulate:a", 1.0, 0.3) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			await fade_in.finished
			
			# Attendre l'intervalle
			await get_tree().create_timer(_text_interval).timeout
			
			# Fade out la bulle
			var fade_out := create_tween()
			fade_out.tween_property(bubble, "modulate:a", 0.0, 0.2) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			await fade_out.finished
			
			# Nettoyer la bulle
			bubble.queue_free()
			_current_bubble = null
	
	# Animer la sortie du personnage
	await _animate_exit(portrait, side)
	portrait.queue_free()
	_current_portrait = null

# =============================================================================
# PORTRAIT (TextureRect du personnage)
# =============================================================================

func _create_portrait(asset_path: String, side: String) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = _character_size
	portrait.size = _character_size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Charger la texture du personnage
	if asset_path != "" and ResourceLoader.exists(asset_path):
		portrait.texture = load(asset_path)
	else:
		# Placeholder : carré coloré si pas d'asset
		push_warning("[StoryOverlay] Portrait asset not found: " + asset_path)
	
	# Position d'ancrage (sera animée)
	var screen_size := get_viewport().get_visible_rect().size
	var y_pos: float = screen_size.y - _character_size.y - 20.0
	
	if side == "left":
		portrait.position = Vector2(40, y_pos)
	else:
		portrait.position = Vector2(screen_size.x - _character_size.x - 40, y_pos)
	
	return portrait

# =============================================================================
# BULLE DE DIALOGUE
# =============================================================================

func _create_bubble(text: String, side: String) -> Control:
	var screen_size := get_viewport().get_visible_rect().size
	
	# Conteneur de la bulle
	var bubble_container := Control.new()
	bubble_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Fond de la bulle (NinePatchRect si asset disponible, sinon ColorRect)
	var bubble_asset: String = _bubble_left_asset if side == "left" else _bubble_right_asset
	var bubble_bg: Control
	
	var bubble_width: float = screen_size.x * 0.65
	var bubble_height: float = 120.0
	var bubble_x: float
	var bubble_y: float = screen_size.y - _character_size.y - bubble_height - 40.0
	
	if side == "left":
		bubble_x = _character_size.x + 60.0
	else:
		bubble_x = screen_size.x - _character_size.x - bubble_width - 60.0
	
	if bubble_asset != "" and ResourceLoader.exists(bubble_asset):
		var nine_patch := NinePatchRect.new()
		nine_patch.texture = load(bubble_asset)
		nine_patch.position = Vector2(bubble_x, bubble_y)
		nine_patch.size = Vector2(bubble_width, bubble_height)
		nine_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_bg = nine_patch
	else:
		# Fallback : ColorRect arrondi
		var color_rect := ColorRect.new()
		color_rect.color = Color(0.15, 0.15, 0.2, 0.9)
		color_rect.position = Vector2(bubble_x, bubble_y)
		color_rect.size = Vector2(bubble_width, bubble_height)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_bg = color_rect
	
	bubble_container.add_child(bubble_bg)
	
	# Texte dans la bulle
	var label := RichTextLabel.new()
	label.text = text
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.position = Vector2(bubble_x + 16, bubble_y + 12)
	label.size = Vector2(bubble_width - 32, bubble_height - 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 22)
	label.add_theme_color_override("default_color", Color.WHITE)
	bubble_container.add_child(label)
	
	return bubble_container

# =============================================================================
# ANIMATIONS D'ENTRÉE / SORTIE
# =============================================================================

func _get_ease_type() -> Tween.EaseType:
	match _anim_ease_type:
		"ease_in": return Tween.EASE_IN
		"ease_out": return Tween.EASE_OUT
		"ease_in_out": return Tween.EASE_IN_OUT
		_: return Tween.EASE_IN_OUT

func _animate_enter(portrait: TextureRect, side: String) -> void:
	var target_pos := portrait.position
	var screen_size := get_viewport().get_visible_rect().size
	
	# Position de départ : hors écran
	if side == "left":
		portrait.position.x = -_character_size.x
	else:
		portrait.position.x = screen_size.x + _character_size.x
	
	# Slide vers la position d'ancrage
	var tween := create_tween()
	tween.tween_property(portrait, "position", target_pos, _anim_speed) \
		.set_ease(_get_ease_type()).set_trans(Tween.TRANS_BACK)
	await tween.finished

func _animate_exit(portrait: TextureRect, side: String) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	
	if _exit_anim_type == "fade":
		# Fondu de sortie
		var tween := create_tween()
		tween.tween_property(portrait, "modulate:a", 0.0, _anim_speed) \
			.set_ease(_get_ease_type()).set_trans(Tween.TRANS_SINE)
		await tween.finished
	else:
		# Slide de sortie (par défaut)
		var exit_pos := portrait.position
		if side == "left":
			exit_pos.x = -_character_size.x
		else:
			exit_pos.x = screen_size.x + _character_size.x
		
		var tween := create_tween()
		tween.tween_property(portrait, "position", exit_pos, _anim_speed) \
			.set_ease(_get_ease_type()).set_trans(Tween.TRANS_BACK)
		await tween.finished
