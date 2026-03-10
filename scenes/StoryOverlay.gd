extends CanvasLayer
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

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
# Portraits actifs par côté ("left"/"right") et speaker associé
var _portraits_by_side: Dictionary = {}
var _speaker_asset_by_side: Dictionary = {}
# Mode debug : en-tête et bouton Next (uniquement en éditeur)
var _debug_header: Control = null
var _debug_next_button: Button = null
# Skip au clic pendant l'attente entre bulles
var _waiting_for_skip: bool = false
var _skip_requested: bool = false

# =============================================================================
# CONFIGURATION (lue depuis global_settings)
# =============================================================================

var _character_size: Vector2 = Vector2(200, 300)
var _anim_speed: float = 0.6
var _anim_ease_type: String = "ease_in_out"
var _exit_anim_type: String = "slide"
var _text_interval: float = 2.5
var _bubble_asset: String = ""
var _bubble_arrow_left_asset: String = ""
var _bubble_arrow_right_asset: String = ""
var _bubble_arrow_offset_left: Vector2 = Vector2.ZERO
var _bubble_arrow_offset_right: Vector2 = Vector2.ZERO
# 9-slice margins (bord de la texture non étiré)
var _patch_margin_left: int = 20
var _patch_margin_top: int = 20
var _patch_margin_right: int = 20
var _patch_margin_bottom: int = 20
# Marge intérieure pour le texte dans la bulle (padding)
var _content_margin_left: int = 24
var _content_margin_top: int = 16
var _content_margin_right: int = 24
var _content_margin_bottom: int = 16
# Offset bulle depuis le personnage (left = depuis top/right du perso à gauche, right = depuis top/left du perso à droite)
var _bubble_offset_left: Vector2 = Vector2(60.0, -40.0)
var _bubble_offset_right: Vector2 = Vector2(-60.0, -40.0)
# Position des portraits : gauche x=0 / droite x=right, y=bottom; valeurs négatives possibles
var _portrait_offset_left: Vector2 = Vector2.ZERO
var _portrait_offset_right: Vector2 = Vector2.ZERO
# Cutout portrait (fond noir JPG) : seuil luminosité 0=tout garder, 1=tout couper ; softness = transition
var _portrait_cutout_cutoff: float = 0.06
var _portrait_cutout_softness: float = 0.04
# Couleur du texte dans les bulles (hex, ex. "#000000")
var _bubble_text_color: Color = Color.BLACK
var _enable_bounce_enter: bool = true
var _fade_out_opacity: float = 0.5

# =============================================================================
# API PUBLIQUE
# =============================================================================

func _input(event: InputEvent) -> void:
	if not _waiting_for_skip:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skip_requested = true
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_skip_requested = true
		get_viewport().set_input_as_handled()

## Lance la lecture d'une séquence de story.
## debug_mode: affiche en haut id/world/level/wave et un bouton "Next" en fin de séquence.
func play(story_id: String, debug_mode: bool = false) -> void:
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
	
	# Réinitialiser les portraits actifs pour cette séquence
	_portraits_by_side.clear()
	_speaker_asset_by_side.clear()
	_current_portrait = null
	_current_bubble = null
	
	# Fade in le fond sombre
	await _fade_bg_in()
	
	# Mode debug : en-tête en haut (id, world, level, wave)
	if debug_mode:
		_show_debug_header()
	
	# Jouer tous les dialogues
	var dialogues: Variant = _story_data.get("dialogues", [])
	if dialogues is Array:
		for i in range((dialogues as Array).size()):
			var dialogue: Variant = (dialogues as Array)[i]
			if dialogue is Dictionary:
				await _play_dialogue(dialogue as Dictionary)
	
	# Mode debug : bouton Next au centre, attendre le clic avant de continuer
	if debug_mode:
		await _show_debug_next_and_wait()
		_clear_debug_ui()

	# Fin de séquence : animer la sortie de tous les portraits encore visibles
	await _clear_all_portraits()
	
	# Fade out le fond
	await _fade_bg_out()
	
	_is_playing = false
	print("[StoryOverlay] Story finished: ", story_id)
	story_finished.emit()

# =============================================================================
# MODE DEBUG (en-tête + bouton Next)
# =============================================================================

func _show_debug_header() -> void:
	_clear_debug_ui()
	var seq_id: String = str(_story_data.get("id", ""))
	var world: String = str(_story_data.get("world", "-"))
	var level_v: Variant = _story_data.get("level", null)
	var level_str: String = "-" if level_v == null else str(level_v)
	var wave: String = str(_story_data.get("wave", "-"))
	var line: String = "id: %s  |  world: %s  |  level: %s  |  wave: %s" % [seq_id, world, level_str, wave]
	
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.9)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	
	var label := Label.new()
	label.text = line
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)
	
	container.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 16
	panel.offset_left = 20
	panel.offset_right = -20
	panel.size.y = 0
	panel.position = Vector2(20, 16)
	var screen_size := get_viewport().get_visible_rect().size
	panel.size = Vector2(screen_size.x - 40, 44)
	
	_debug_header = panel

func _show_debug_next_and_wait() -> void:
	var btn := Button.new()
	btn.text = "Next"
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(160, 56)
	container.add_child(btn)
	UIStyle.apply_default_button_style(btn, "medium")
	UIStyle.apply_button_shadow(btn, "medium")
	var screen_size := get_viewport().get_visible_rect().size
	btn.position = Vector2(screen_size.x * 0.5 - 80, screen_size.y * 0.5 - 28)
	_debug_next_button = btn
	await btn.pressed

func _clear_debug_ui() -> void:
	if _debug_header != null and is_instance_valid(_debug_header):
		_debug_header.queue_free()
		_debug_header = null
	if _debug_next_button != null and is_instance_valid(_debug_next_button):
		_debug_next_button.queue_free()
		_debug_next_button = null

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
	# speaker_size (optionnel) override la taille des portraits
	var speaker_size: Variant = _settings.get("speaker_size", {})
	if speaker_size is Dictionary:
		var ss := speaker_size as Dictionary
		_character_size = Vector2(
			float(ss.get("x", _character_size.x)),
			float(ss.get("y", _character_size.y))
		)
	
	_anim_speed = float(_settings.get("anim_speed", 0.6))
	_anim_ease_type = str(_settings.get("anim_ease_type", "ease_in_out"))
	_exit_anim_type = str(_settings.get("exit_anim_type", "slide"))
	_text_interval = float(_settings.get("text_interval", 2.5))
	_enable_bounce_enter = bool(_settings.get("enable_bounce_enter", true))
	_fade_out_opacity = clampf(float(_settings.get("fadeOutOpacity", 0.5)), 0.0, 1.0)
	_bubble_asset = str(_settings.get("bubble_asset", ""))
	_bubble_arrow_left_asset = str(_settings.get("bubble_arrow_left_asset", ""))
	_bubble_arrow_right_asset = str(_settings.get("bubble_arrow_right_asset", ""))
	var arr_left: Variant = _settings.get("bubble_arrow_offset_left", {})
	if arr_left is Dictionary:
		var o := arr_left as Dictionary
		_bubble_arrow_offset_left = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	var arr_right: Variant = _settings.get("bubble_arrow_offset_right", {})
	if arr_right is Dictionary:
		var o := arr_right as Dictionary
		_bubble_arrow_offset_right = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	
	var patch: Variant = _settings.get("bubble_patch_margin", {})
	if patch is Dictionary:
		var p := patch as Dictionary
		_patch_margin_left = int(p.get("left", 20))
		_patch_margin_top = int(p.get("top", 20))
		_patch_margin_right = int(p.get("right", 20))
		_patch_margin_bottom = int(p.get("bottom", 20))
	var content: Variant = _settings.get("bubble_content_margin", {})
	if content is Dictionary:
		var c := content as Dictionary
		_content_margin_left = int(c.get("left", 24))
		_content_margin_top = int(c.get("top", 16))
		_content_margin_right = int(c.get("right", 24))
		_content_margin_bottom = int(c.get("bottom", 16))
	# Si content_margin est 0 ou absent, utiliser les patch margins pour que texte et 9-patch soient alignés
	if _content_margin_left <= 0:
		_content_margin_left = _patch_margin_left
	if _content_margin_top <= 0:
		_content_margin_top = _patch_margin_top
	if _content_margin_right <= 0:
		_content_margin_right = _patch_margin_right
	if _content_margin_bottom <= 0:
		_content_margin_bottom = _patch_margin_bottom
	var off_left: Variant = _settings.get("bubble_offset_left", {})
	if off_left is Dictionary:
		var o := off_left as Dictionary
		_bubble_offset_left = Vector2(float(o.get("x", 60)), float(o.get("y", -40)))
	var off_right: Variant = _settings.get("bubble_offset_right", {})
	if off_right is Dictionary:
		var o := off_right as Dictionary
		_bubble_offset_right = Vector2(float(o.get("x", -60)), float(o.get("y", -40)))
	var po_left: Variant = _settings.get("portrait_offset_left", {})
	if po_left is Dictionary:
		var o := po_left as Dictionary
		_portrait_offset_left = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	var po_right: Variant = _settings.get("portrait_offset_right", {})
	if po_right is Dictionary:
		var o := po_right as Dictionary
		_portrait_offset_right = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	_portrait_cutout_cutoff = float(_settings.get("portrait_cutout_cutoff", 0.06))
	_portrait_cutout_softness = float(_settings.get("portrait_cutout_softness", 0.04))
	var text_color_str: String = str(_settings.get("bubble_text_color", "#000000")).strip_edges()
	if text_color_str != "":
		_bubble_text_color = Color(text_color_str)

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

## Attend _text_interval secondes, ou moins si l'utilisateur clique/touche l'écran.
func _wait_interval_or_skip() -> void:
	_skip_requested = false
	_waiting_for_skip = true
	var elapsed := 0.0
	while elapsed < _text_interval and not _skip_requested:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	_waiting_for_skip = false

func _clear_all_portraits() -> void:
	for side in _portraits_by_side.keys():
		var portrait: TextureRect = _portraits_by_side[side]
		if portrait != null and is_instance_valid(portrait):
			await _animate_exit(portrait, side)
			portrait.queue_free()
	_portraits_by_side.clear()
	_speaker_asset_by_side.clear()
	_current_portrait = null

func _fade_non_speaker(speaker_side: String) -> void:
	var other_side: String = "right" if speaker_side == "left" else "left"
	if not _portraits_by_side.has(other_side):
		return
	var p: TextureRect = _portraits_by_side[other_side]
	if p == null or not is_instance_valid(p) or not p.material is ShaderMaterial:
		return
	var current_opacity: float = (p.material as ShaderMaterial).get_shader_parameter("opacity")
	if is_equal_approx(current_opacity, _fade_out_opacity):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p.material, "shader_parameter/opacity", _fade_out_opacity, 0.25)
	await tw.finished

func _restore_speaker_opacity(speaker_side: String) -> void:
	if not _portraits_by_side.has(speaker_side):
		return
	var p: TextureRect = _portraits_by_side[speaker_side]
	if p == null or not is_instance_valid(p) or not p.material is ShaderMaterial:
		return
	var current_opacity: float = (p.material as ShaderMaterial).get_shader_parameter("opacity")
	if is_equal_approx(current_opacity, 1.0):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p.material, "shader_parameter/opacity", 1.0, 0.25)
	await tw.finished

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
	
	# Récupérer / créer le portrait pour ce côté (réutilisé tant que speaker_asset ne change pas)
	var portrait: TextureRect = null
	var prev: Variant = _portraits_by_side.get(side, null)
	var prev_asset: String = str(_speaker_asset_by_side.get(side, ""))
	var reuse := speaker_asset != "" and prev is TextureRect and is_instance_valid(prev) and prev_asset == speaker_asset
	
	# Fade out l'autre côté AVANT l'entrée du nouveau locuteur
	await _fade_non_speaker(side)
	
	if reuse:
		portrait = prev
	else:
		if prev is TextureRect and is_instance_valid(prev):
			await _animate_exit(prev, side)
			prev.queue_free()
		if speaker_asset != "":
			portrait = _create_portrait(speaker_asset, side)
			container.add_child(portrait)
			await _animate_enter(portrait, side)
			_portraits_by_side[side] = portrait
			_speaker_asset_by_side[side] = speaker_asset
	_current_portrait = portrait
	
	# Remettre le locuteur à pleine opacité (s'il avait été fade out précédemment)
	await _restore_speaker_opacity(side)
	
	# Afficher chaque bulle de texte
	if text_keys is Array:
		for i in range((text_keys as Array).size()):
			var key: String = str((text_keys as Array)[i])
			var text: String = LocaleManager.get_story_string(key)
			
			# Créer la bulle (déjà ajoutée au container dans _create_bubble)
			var bubble := await _create_bubble(text, side)
			_current_bubble = bubble
			
			# Fade in la bulle
			bubble.modulate.a = 0.0
			var fade_in := create_tween()
			fade_in.tween_property(bubble, "modulate:a", 1.0, 0.3) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			await fade_in.finished
			
			# Attendre l'intervalle (clic/touch = passer tout de suite au suivant)
			await _wait_interval_or_skip()
			
			# Fade out la bulle
			var fade_out := create_tween()
			fade_out.tween_property(bubble, "modulate:a", 0.0, 0.2) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			await fade_out.finished
			
			# Nettoyer la bulle
			bubble.queue_free()
			_current_bubble = null

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
		# Shader pour rendre le noir transparent (JPG avec fond noir)
		var shader_res := load("res://scenes/story_portrait_cutout.gdshader") as Shader
		if shader_res:
			var mat := ShaderMaterial.new()
			mat.shader = shader_res
			mat.set_shader_parameter("cutoff", _portrait_cutout_cutoff)
			mat.set_shader_parameter("softness", _portrait_cutout_softness)
			mat.set_shader_parameter("opacity", 1.0)
			portrait.material = mat
	else:
		# Placeholder : carré coloré si pas d'asset
		push_warning("[StoryOverlay] Portrait asset not found: " + asset_path)
	
	# Position d'ancrage (x=0 à gauche / x=right à droite, y=bas de l'écran; offsets réglables dans story.json)
	var screen_size := get_viewport().get_visible_rect().size
	if side == "left":
		var y_pos: float = screen_size.y - _character_size.y + _portrait_offset_left.y
		portrait.position = Vector2(_portrait_offset_left.x, y_pos)
		portrait.flip_h = true
	else:
		var y_pos: float = screen_size.y - _character_size.y + _portrait_offset_right.y
		portrait.position = Vector2(screen_size.x - _character_size.x + _portrait_offset_right.x, y_pos)
		portrait.flip_h = false
	
	return portrait

# =============================================================================
# BULLE DE DIALOGUE
# =============================================================================

func _create_bubble(text: String, side: String) -> Control:
	var screen_size := get_viewport().get_visible_rect().size
	
	var bubble_container := Control.new()
	bubble_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_container.modulate.a = 0.0
	# Mettre dans l'arbre tout de suite pour que le layout du label soit calculé
	container.add_child(bubble_container)
	
	var bubble_width: float = screen_size.x * 0.65
	var bubble_x: float
	# Référence: même position que le portrait (voir _create_portrait)
	var char_top: float
	var char_right: float
	var right_char_left: float
	if side == "left":
		char_top = screen_size.y - _character_size.y + _portrait_offset_left.y
		char_right = _portrait_offset_left.x + _character_size.x
		bubble_x = char_right + _bubble_offset_left.x
	else:
		char_top = screen_size.y - _character_size.y + _portrait_offset_right.y
		right_char_left = screen_size.x - _character_size.x + _portrait_offset_right.x
		bubble_x = right_char_left + _bubble_offset_right.x - bubble_width
	
	# Marges effectives : au moins les patch margins (découpage du 9-patch).
	# Pour que les coins collent aux bords, la zone texte = zone étirable du 9-patch → utiliser eff = patch.
	# Si tu mets content_margin > patch_margin, le texte a plus de marge (eff = content).
	var eff_left: int = maxi(_content_margin_left, _patch_margin_left)
	var eff_top: int = maxi(_content_margin_top, _patch_margin_top)
	var eff_right: int = maxi(_content_margin_right, _patch_margin_right)
	var eff_bottom: int = maxi(_content_margin_bottom, _patch_margin_bottom)
	var text_width: float = bubble_width - float(eff_left + eff_right)
	
	# Label temporaire pour mesurer la hauteur de contenu (doit être dans l'arbre)
	var measure_label := RichTextLabel.new()
	measure_label.text = text
	measure_label.bbcode_enabled = true
	measure_label.fit_content = true
	measure_label.scroll_active = false
	measure_label.custom_minimum_size = Vector2(text_width, 0)
	measure_label.size = Vector2(text_width, 4000)
	measure_label.add_theme_font_size_override("normal_font_size", 22)
	measure_label.add_theme_color_override("default_color", _bubble_text_color)
	measure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_container.add_child(measure_label)
	await get_tree().process_frame
	await get_tree().process_frame
	var content_height: float = measure_label.get_content_height()
	if content_height <= 0.0:
		content_height = measure_label.get_minimum_size().y
	if content_height <= 0.0:
		content_height = 40.0
	measure_label.queue_free()
	
	var bubble_height: float = content_height + float(eff_top + eff_bottom)
	bubble_height = maxf(bubble_height, 60.0)
	# Taille minimale pour que le 9-patch ait une zone étirable positive (coins bien alignés aux bords)
	var min_bubble_width: float = float(_patch_margin_left + _patch_margin_right + 1)
	var min_bubble_height: float = float(_patch_margin_top + _patch_margin_bottom + 1)
	bubble_width = maxf(bubble_width, min_bubble_width)
	bubble_height = maxf(bubble_height, min_bubble_height)
	# Position verticale: depuis le top du personnage + offset y
	var bubble_y: float
	if side == "left":
		bubble_y = char_top + _bubble_offset_left.y
	else:
		bubble_y = char_top + _bubble_offset_right.y
	
	# Fond de la bulle (9-slice unique, sans flèche)
	var bubble_bg: Control
	
	if _bubble_asset != "" and ResourceLoader.exists(_bubble_asset):
		var nine_patch := NinePatchRect.new()
		nine_patch.texture = load(_bubble_asset)
		nine_patch.set_patch_margin(Side.SIDE_LEFT, _patch_margin_left)
		nine_patch.set_patch_margin(Side.SIDE_TOP, _patch_margin_top)
		nine_patch.set_patch_margin(Side.SIDE_RIGHT, _patch_margin_right)
		nine_patch.set_patch_margin(Side.SIDE_BOTTOM, _patch_margin_bottom)
		nine_patch.position = Vector2(bubble_x, bubble_y)
		nine_patch.size = Vector2(bubble_width, bubble_height)
		nine_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_bg = nine_patch
	else:
		var color_rect := ColorRect.new()
		color_rect.color = Color(0.15, 0.15, 0.2, 0.9)
		color_rect.position = Vector2(bubble_x, bubble_y)
		color_rect.size = Vector2(bubble_width, bubble_height)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_bg = color_rect
	
	bubble_container.add_child(bubble_bg)
	bubble_container.move_child(bubble_bg, 0)
	
	# Flèche en bas : offset depuis le coin bas-gauche (left) ou bas-droit (right) de la bulle
	var arrow_asset: String = _bubble_arrow_left_asset if side == "left" else _bubble_arrow_right_asset
	var arrow_offset: Vector2 = _bubble_arrow_offset_left if side == "left" else _bubble_arrow_offset_right
	if arrow_asset != "" and ResourceLoader.exists(arrow_asset):
		var arrow_tex: Texture2D = load(arrow_asset) as Texture2D
		if arrow_tex != null:
			var arrow_rect := TextureRect.new()
			arrow_rect.texture = arrow_tex
			arrow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			arrow_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			arrow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var aw: float = float(arrow_tex.get_width())
			var ah: float = float(arrow_tex.get_height())
			arrow_rect.size = Vector2(aw, ah)
			if side == "left":
				arrow_rect.position = Vector2(
					bubble_x + arrow_offset.x,
					bubble_y + bubble_height - ah + arrow_offset.y
				)
			else:
				arrow_rect.position = Vector2(
					bubble_x + bubble_width - aw + arrow_offset.x,
					bubble_y + bubble_height - ah + arrow_offset.y
				)
			bubble_container.add_child(arrow_rect)
	# Texte dans la bulle (marges effectives = max(content, patch) pour aligner avec le 9-patch)
	var label := RichTextLabel.new()
	label.text = text
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.position = Vector2(
		bubble_x + eff_left,
		bubble_y + eff_top
	)
	label.size = Vector2(
		bubble_width - float(eff_left + eff_right),
		bubble_height - float(eff_top + eff_bottom)
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 22)
	label.add_theme_color_override("default_color", _bubble_text_color)
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
	var trans_type := Tween.TRANS_BACK if _enable_bounce_enter else Tween.TRANS_SINE
	tween.tween_property(portrait, "position", target_pos, _anim_speed) \
		.set_ease(_get_ease_type()).set_trans(trans_type)
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
