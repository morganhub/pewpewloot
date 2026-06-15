extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## HomeScreen — Écran d'accueil après sélection/chargement du profil.
## Layout: Top 40% for title/info, Bottom 60% for buttons.
## Buttons are 75% screen width.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var menu_header: Control = $MenuHeader
@onready var top_section: VBoxContainer = $TopSection
@onready var bottom_section: VBoxContainer = $BottomSection

@onready var title_label: Label = $TopSection/TitleLabel
@onready var logo_texture: TextureRect = $TopSection/LogoTexture
@onready var logo_anim_container: Control = $TopSection/LogoAnimContainer
@onready var logo_anim: AnimatedSprite2D = $TopSection/LogoAnimContainer/LogoAnim

@onready var play_button: Button = $BottomSection/PlayButton
@onready var ship_button: Button = $BottomSection/ShipButton
@onready var skills_button: Button = $BottomSection/SkillsButton
@onready var options_button: Button = $BottomSection/OptionsButton
@onready var quit_button: Button = $BottomSection/QuitButton
@onready var change_profile_button: Button = $BottomSection/ChangeProfileButton
@onready var unlock_all_button: Button = $BottomSection/UnlockAllButton
@onready var reset_viewed_stories_button: Button = $BottomSection/ResetViewedStoriesButton
@onready var reset_to_level_one_button: Button = $BottomSection/ResetToLevelOneButton
@onready var start_story_button: Button = $BottomSection/StartStoryButton

var _game_config: Dictionary = {}
static var _logo_first_visit: bool = true

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	App.play_menu_music()
	_setup_layout()
	_setup_background()
	_setup_logo()
	_setup_buttons()
	_apply_translations()
	if menu_header and menu_header.has_signal("crystals_pressed"):
		if not menu_header.crystals_pressed.is_connected(_on_crystals_header_pressed):
			menu_header.crystals_pressed.connect(_on_crystals_header_pressed)
	_request_menu_prewarm()
	
	# Connect signals
	play_button.pressed.connect(_on_play_pressed)
	ship_button.pressed.connect(_on_ship_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	change_profile_button.pressed.connect(_on_change_profile_pressed)
	
	# Temporary dev button (editor only): regenerate movement curve resources.
	if unlock_all_button:
		unlock_all_button.visible = ProfileManager.is_debug_mode_enabled()
		if unlock_all_button.visible:
			unlock_all_button.pressed.connect(_on_unlock_all_pressed)
	if reset_viewed_stories_button:
		reset_viewed_stories_button.visible = ProfileManager.is_debug_mode_enabled()
		if reset_viewed_stories_button.visible:
			reset_viewed_stories_button.pressed.connect(_on_reset_viewed_stories_pressed)
	if reset_to_level_one_button:
		reset_to_level_one_button.visible = ProfileManager.is_debug_mode_enabled()
		if reset_to_level_one_button.visible:
			reset_to_level_one_button.pressed.connect(_on_reset_to_level_one_pressed)
	if start_story_button:
		start_story_button.visible = ProfileManager.is_debug_mode_enabled()
		if start_story_button.visible:
			start_story_button.pressed.connect(_on_start_story_pressed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and menu_header != null and menu_header.has_method("refresh"):
		menu_header.refresh()

func _load_game_config() -> void:
	if DataManager:
		_game_config = DataManager.get_game_config()
	else:
		_game_config = {}

func _setup_layout() -> void:
	var header_height: int = 0
	var h: Variant = _game_config.get("menu_header", {})
	if h is Dictionary:
		header_height = int((h as Dictionary).get("height_px", 72))
		var margin_t: int = int((h as Dictionary).get("margin_top", 8))
		header_height += margin_t
	if top_section:
		top_section.offset_top = 30 + header_height
	if bottom_section:
		bottom_section.offset_top = 0

func _setup_background() -> void:
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	var bg_path: String = str(menu_config.get("background", ""))
	var bg_anim_path: String = str(menu_config.get("background_anim", ""))
	
	# Priority: anim > static > fallback color
	if bg_anim_path != "" and ResourceLoader.exists(bg_anim_path):
		# TODO: Handle animated background
		pass
	elif bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and background_rect:
			background_rect.texture = tex
			background_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# Fallback: dark gradient
		if background_rect:
			background_rect.visible = false

func _setup_logo() -> void:
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	var logo_path: String = str(menu_config.get("logo", ""))
	var logo_anim_path: String = str(menu_config.get("logo_anim", ""))
	var logo_anim_duration: float = maxf(0.0, float(menu_config.get("logo_anim_duration", 2.0)))
	var logo_anim_loop: bool = bool(menu_config.get("logo_anim_loop", false))
	var width_pct: float = float(menu_config.get("logo_width_pct", 0.5))
	var height_pct: float = float(menu_config.get("logo_height_pct", 0.2))
	
	var viewport_size := get_viewport_rect().size
	var target_size := Vector2(viewport_size.x * width_pct, viewport_size.y * height_pct)
	
	# Apply sizing and 'contain' behavior
	if logo_texture:
		logo_texture.custom_minimum_size = target_size
		logo_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	if logo_anim_container:
		logo_anim_container.custom_minimum_size = target_size
	
	# Reset visibility (default to text)
	title_label.visible = true
	if logo_texture: logo_texture.visible = false
	if logo_anim_container: logo_anim_container.visible = false
	
	# Au premier passage dans la session : logo animé. Retours au menu : logo statique (main_menu.logo)
	var was_first_visit: bool = _logo_first_visit
	if _logo_first_visit:
		_logo_first_visit = false
	var use_animated_logo: bool = was_first_visit and (logo_anim_path != "" and ResourceLoader.exists(logo_anim_path))
	
	# Logo animé : uniquement au démarrage du jeu
	if use_animated_logo:
		var frames: Resource = load(logo_anim_path)
		if frames is SpriteFrames and logo_anim:
			VFXManager.play_sprite_frames(
				logo_anim,
				frames as SpriteFrames,
				&"default",
				logo_anim_loop,
				logo_anim_duration
			)
			
			if not logo_anim_container.resized.is_connected(_center_logo_anim):
				logo_anim_container.resized.connect(_center_logo_anim)
			_center_logo_anim()
			
			logo_anim_container.scale = Vector2.ZERO
			logo_anim_container.modulate.a = 0.0
			logo_anim_container.pivot_offset = target_size / 2
			
			var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(logo_anim_container, "scale", Vector2.ONE, 3.0)
			tween.tween_property(logo_anim_container, "modulate:a", 1.0, 3.0)
			
			if logo_anim_container: logo_anim_container.visible = true
			title_label.visible = false
			return

	# Logo statique (retours au menu ou si pas d'anim) : main_menu.logo
	if logo_path != "" and ResourceLoader.exists(logo_path):
		var tex = load(logo_path)
		if tex and logo_texture:
			logo_texture.texture = tex
			logo_texture.visible = true
			title_label.visible = false
			logo_texture.pivot_offset = target_size / 2
			if was_first_visit:
				logo_texture.scale = Vector2.ZERO
				logo_texture.modulate.a = 0.0
				var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tween.tween_property(logo_texture, "scale", Vector2.ONE, 3.0)
				tween.tween_property(logo_texture, "modulate:a", 1.0, 3.0)
			else:
				logo_texture.scale = Vector2.ONE
				logo_texture.modulate.a = 1.0
			return

func _center_logo_anim() -> void:
	if logo_anim and logo_anim_container:
		var container_size = logo_anim_container.size
		logo_anim.position = container_size / 2
		
		# Containment logic for AnimatedSprite2D
		var frames = logo_anim.sprite_frames
		if frames:
			var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
			var frame_tex: Texture2D = null
			if anim_name != &"":
				frame_tex = frames.get_frame_texture(anim_name, 0)
			if frame_tex:
				var tex_size = frame_tex.get_size()
				if tex_size.x > 0 and tex_size.y > 0:
					var scale_factor = min(container_size.x / tex_size.x, container_size.y / tex_size.y)
					logo_anim.scale = Vector2(scale_factor, scale_factor)

func _setup_buttons() -> void:
	var buttons_config: Dictionary = _game_config.get("home_buttons", {})
	var shared_cfg := _extract_shared_button_cfg(buttons_config)
	var validation_cfg: Dictionary = UIStyle.get_validation_config()
	if not validation_cfg.is_empty() and str(validation_cfg.get("asset", "")) != "":
		var play_cfg: Dictionary = buttons_config.get("play", {})
		var merged_cfg: Dictionary = validation_cfg.duplicate()
		if play_cfg.has("letter_spacing"):
			merged_cfg["letter_spacing"] = play_cfg["letter_spacing"]
		if play_cfg.has("text_color"):
			merged_cfg["text_color"] = play_cfg["text_color"]
		if play_cfg.has("text_size"):
			merged_cfg["text_size"] = play_cfg["text_size"]
		UIStyle.apply_validation_to_button(play_button, merged_cfg, "large")
		play_button.text = LocaleManager.translate("home_play")
		_apply_button_text_shadow(play_button)
	else:
		_setup_single_button(play_button, _merge_button_cfg(shared_cfg, buttons_config.get("play", {})), "home_play")
	_setup_single_button(ship_button, _merge_button_cfg(shared_cfg, buttons_config.get("ship", {})), "home_ship_menu")
	_setup_single_button(options_button, _merge_button_cfg(shared_cfg, buttons_config.get("options", {})), "home_options")
	var cancel_cfg: Dictionary = UIStyle.get_cancellation_config()
	if not cancel_cfg.is_empty() and str(cancel_cfg.get("asset", "")) != "":
		var quit_cfg: Dictionary = buttons_config.get("quit", {})
		var cancel_merged: Dictionary = cancel_cfg.duplicate()
		if quit_cfg.has("text_size"):
			cancel_merged["text_size"] = quit_cfg["text_size"]
		if quit_cfg.has("letter_spacing"):
			cancel_merged["letter_spacing"] = quit_cfg["letter_spacing"]
		UIStyle.apply_cancellation_to_button(quit_button, cancel_merged, "large")
		quit_button.text = LocaleManager.translate("home_quit")
		_apply_button_text_shadow(quit_button)
	else:
		_setup_single_button(quit_button, _merge_button_cfg(shared_cfg, buttons_config.get("quit", {})), "home_quit")
	_setup_single_button(skills_button, _merge_button_cfg(shared_cfg, buttons_config.get("skills", {})), "home_skills")
	_setup_single_button(change_profile_button, _merge_button_cfg(shared_cfg, buttons_config.get("change_profile", {})), "home_change_profile_short")
	UIStyle.apply_button_shadow(unlock_all_button, "small")
	UIStyle.apply_button_shadow(reset_viewed_stories_button, "small")
	UIStyle.apply_button_shadow(reset_to_level_one_button, "small")
	UIStyle.apply_button_shadow(start_story_button, "small")

func _extract_shared_button_cfg(buttons_config: Dictionary) -> Dictionary:
	var shared := {}
	if buttons_config.has("default_nine_slice"):
		shared["nine_slice"] = buttons_config.get("default_nine_slice", {})
	if buttons_config.has("default_content_margin"):
		shared["content_margin"] = buttons_config.get("default_content_margin", {})
	if buttons_config.has("default_stretch_horizontal"):
		shared["stretch_horizontal"] = buttons_config.get("default_stretch_horizontal", "stretch")
	if buttons_config.has("default_stretch_vertical"):
		shared["stretch_vertical"] = buttons_config.get("default_stretch_vertical", "stretch")
	if buttons_config.has("default_draw_center"):
		shared["draw_center"] = buttons_config.get("default_draw_center", true)
	if buttons_config.has("default_text_size"):
		shared["default_text_size"] = buttons_config.get("default_text_size")
	return shared

func _merge_button_cfg(shared_cfg: Dictionary, per_button_cfg: Variant) -> Dictionary:
	var merged := shared_cfg.duplicate(true)
	if per_button_cfg is Dictionary:
		for key in (per_button_cfg as Dictionary).keys():
			merged[key] = (per_button_cfg as Dictionary)[key]
	return merged

func _setup_single_button(button: Button, config: Dictionary, translation_key: String) -> void:
	var asset_path: String = str(config.get("asset", ""))
	var asset_anim: String = str(config.get("asset_anim", ""))
	var asset_anim_duration: float = maxf(0.0, float(config.get("asset_anim_duration", 0.0)))
	var asset_anim_loop: bool = bool(config.get("asset_anim_loop", true))
	var show_text: bool = bool(config.get("show_text", true))
	var text_color_hex: String = str(config.get("text_color", "#FFFFFF"))
	
	var letter_spacing: int = int(config.get("letter_spacing", 0))
	
	# Reset state
	button.icon = null
	# Clear existing children that might be anims (if reused) or specific nodes
	for child in button.get_children():
		if child.name == "BgAnim": child.queue_free()
	
	var _has_visual_bg: bool = false
	
	# 1. GESTION ASSET ANIMÉ (Priorité 1)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames: Resource = load(asset_anim)
		if frames is SpriteFrames:
			_has_visual_bg = true
			# Style transparent pour le bouton (plus de cadre gris)
			var style_empty = StyleBoxEmpty.new()
			_apply_style_override(button, style_empty)
			
			# Ajouter AnimatedSprite2D
			var anim = AnimatedSprite2D.new()
			anim.name = "BgAnim"
			VFXManager.play_sprite_frames(
				anim,
				frames as SpriteFrames,
				&"default",
				asset_anim_loop,
				asset_anim_duration
			)
			anim.show_behind_parent = true 
			button.add_child(anim)
			
			# Centrage initial et connexion signal
			_center_child_sprite(button, anim)
			if not button.resized.is_connected(_center_child_sprite.bind(button, anim)):
				button.resized.connect(_center_child_sprite.bind(button, anim))
				
			# Scale logic (simple fit)
			var tex = frames.get_frame_texture("default", 0)
			if tex:
				# anim.scale can be computed here if needed in the future.
				# Current behavior keeps native animation scale.
				pass
	
	# 2. GESTION ASSET STATIQUE (Priorité 2)
	elif asset_path != "" and ResourceLoader.exists(asset_path):
		var style := UIStyle.build_texture_stylebox(asset_path, config, 10)
		if style:
			_has_visual_bg = true
			_apply_style_override(button, style)
	
	# 3. TEXTE
	if show_text:
		var text_size_val: Variant = config.get("text_size", config.get("default_text_size", null))
		if text_size_val != null:
			button.add_theme_font_size_override("font_size", int(text_size_val))
		button.text = LocaleManager.t(translation_key)
		
		# Appliquer la couleur personnalisée
		var col := Color(text_color_hex)
		button.add_theme_color_override("font_color", col)
		button.add_theme_color_override("font_pressed_color", col)
		button.add_theme_color_override("font_hover_color", col)
		button.add_theme_color_override("font_focus_color", col)
		
		# Appliquer l'espacement des lettres (letter_spacing)
		if letter_spacing != 0:
			var current_font = button.get_theme_font("font")
			if current_font:
				var fv = FontVariation.new()
				fv.base_font = current_font
				fv.spacing_glyph = letter_spacing
				button.add_theme_font_override("font", fv)
		_apply_button_text_shadow(button)
	else:
		button.text = ""

func _apply_button_text_shadow(button: Button) -> void:
	UIStyle.apply_button_shadow(button, "large")

func _apply_style_override(btn: Button, style: StyleBox) -> void:
	btn.add_theme_stylebox_override("normal", style)
	var hover_style: StyleBox = UIStyle.get_stylebox_with_hover_offset(style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("focus", hover_style)
	UIStyle.apply_button_hover_translate(btn) 

func _center_child_sprite(btn: Control, sprite: Node2D) -> void:
	sprite.position = btn.size / 2

func _apply_translations() -> void:
	title_label.text = LocaleManager.t("app_title")

func _request_menu_prewarm() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("request_menu_prewarm"):
		switcher.call_deferred("request_menu_prewarm")

func _goto_from_home(scene_path: String) -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen(scene_path)

func prepare_for_transition() -> void:
	pass

# =============================================================================
# NAVIGATION
# =============================================================================

func _on_play_pressed() -> void:
	_goto_from_home("res://scenes/WorldSelect.tscn")

func _on_ship_pressed() -> void:
	_goto_from_home("res://scenes/ShipMenu.tscn")

func _on_skills_pressed() -> void:
	_goto_from_home("res://scenes/SkillsMenu.tscn")

func _on_options_pressed() -> void:
	_goto_from_home("res://scenes/OptionsMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_crystals_header_pressed() -> void:
	_goto_from_home("res://scenes/ShopMenu.tscn")

func _on_change_profile_pressed() -> void:
	_goto_from_home("res://scenes/ProfileSelect.tscn")

func _on_unlock_all_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	if unlock_all_button == null:
		return

	var profile := ProfileManager.get_active_profile()
	if profile.is_empty():
		return

	for world_variant in App.get_worlds():
		if not (world_variant is Dictionary):
			continue
		var world_id: String = str((world_variant as Dictionary).get("id", ""))
		if world_id == "":
			continue

		var levels_per_world: int = max(1, App.get_world_level_count(world_id))
		ProfileManager.complete_level(world_id, levels_per_world - 1, levels_per_world)

	ProfileManager.save_to_disk()

	unlock_all_button.disabled = true
	UIStyle.set_button_shadow_text(unlock_all_button, "Unlocked!")
	await get_tree().create_timer(1.0).timeout
	unlock_all_button.disabled = false
	UIStyle.set_button_shadow_text(unlock_all_button, "Unlock All Worlds")

func _on_reset_viewed_stories_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	if reset_viewed_stories_button == null:
		return
	ProfileManager.reset_viewed_stories()
	reset_viewed_stories_button.disabled = true
	UIStyle.set_button_shadow_text(reset_viewed_stories_button, "Reset!")
	await get_tree().create_timer(1.0).timeout
	reset_viewed_stories_button.disabled = false
	UIStyle.set_button_shadow_text(reset_viewed_stories_button, "Reset viewed stories")

func _on_reset_to_level_one_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	if reset_to_level_one_button == null:
		return
	ProfileManager.reset_player_level_progress()
	reset_to_level_one_button.disabled = true
	UIStyle.set_button_shadow_text(reset_to_level_one_button, "Level 1!")
	await get_tree().create_timer(1.0).timeout
	reset_to_level_one_button.disabled = false
	UIStyle.set_button_shadow_text(reset_to_level_one_button, "Reset to level 1")

func _on_start_story_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	StoryManager.play_debug_story_flow()
