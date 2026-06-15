extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## OptionsMenu — Menu des options avec sélection de langue.
## Accessible depuis l'écran d'accueil via le bouton "Options".

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var back_button: TextureButton = $MarginContainer/VBoxContainer/Header/BackButton
@onready var language_label: Label = $MarginContainer/VBoxContainer/LanguageSection/LanguageLabel
@onready var language_dropdown: OptionButton = $MarginContainer/VBoxContainer/LanguageSection/LanguageDropdown

@onready var music_label: Label = $MarginContainer/VBoxContainer/SoundSection/MusicBox/Label
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/MusicBox/MusicSlider
@onready var sfx_label: Label = $MarginContainer/VBoxContainer/SoundSection/SFXBox/Label
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/SFXBox/SFXSlider
@onready var screenshake_label: Label = $MarginContainer/VBoxContainer/SoundSection/ScreenShakeBox/Label
@onready var screenshake_checkbox: Button = $MarginContainer/VBoxContainer/SoundSection/ScreenShakeBox/ScreenShakeCheckbox
@onready var health_values_label: Label = $MarginContainer/VBoxContainer/SoundSection/HealthValuesBox/Label
@onready var health_values_checkbox: Button = $MarginContainer/VBoxContainer/SoundSection/HealthValuesBox/HealthValuesCheckbox
@onready var debug_mode_label: Label = $MarginContainer/VBoxContainer/DebugSection/DebugModeBox/Label
@onready var debug_mode_checkbox: Button = $MarginContainer/VBoxContainer/DebugSection/DebugModeBox/DebugModeCheckbox
@onready var story_label: Label = $MarginContainer/VBoxContainer/StorySection/StoryLabel
@onready var reset_stories_button: Button = $MarginContainer/VBoxContainer/StorySection/ResetStoriesButton

var _game_config: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	_setup_background()
	_setup_fonts()
	_setup_language_dropdown()
	_apply_dropdown_style(language_dropdown)
	# Taille du popup langue = même que le label "Langue"
	var opts_cfg: Dictionary = _game_config.get("options_menu", {})
	var content_sz: int = int(opts_cfg.get("title_text_size", 24))
	var lang_popup: PopupMenu = language_dropdown.get_popup() if language_dropdown else null
	if lang_popup:
		lang_popup.add_theme_font_size_override("font_size", content_sz)
	_setup_audio_sliders()
	_setup_screenshake_toggle()
	_setup_health_values_toggle()
	_setup_debug_mode_toggle()
	_apply_translations()
	UIStyle.apply_default_button_style(reset_stories_button, "medium")
	UIStyle.apply_default_button_style(screenshake_checkbox, "small")
	UIStyle.apply_default_button_style(health_values_checkbox, "small")
	UIStyle.apply_default_button_style(debug_mode_checkbox, "small")
	
	# Connect signals
	back_button.pressed.connect(_on_back_pressed)
	language_dropdown.item_selected.connect(_on_language_selected)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	screenshake_checkbox.toggled.connect(_on_screenshake_toggled)
	health_values_checkbox.toggled.connect(_on_health_values_toggled)
	debug_mode_checkbox.toggled.connect(_on_debug_mode_toggled)
	reset_stories_button.pressed.connect(_on_reset_stories_pressed)
	
	# Footer : clic sur le bouton retour du bas
	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)
	if back_button:
		back_button.visible = false

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			_game_config = json.data

func _setup_background() -> void:
	var options_config: Dictionary = _game_config.get("options_menu", {})
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	
	var bg_path: String = str(options_config.get("background", ""))
	if bg_path == "":
		bg_path = str(menu_config.get("background", ""))
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and background_rect:
			background_rect.texture = tex
			background_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# Fallback: dark background
		if background_rect:
			background_rect.visible = false

func _setup_fonts() -> void:
	var cfg: Dictionary = _game_config.get("options_menu", {})
	var content_font_size: int = int(cfg.get("title_text_size", 24))  # même taille que "Langue" pour tout le contenu
	if language_label: language_label.add_theme_font_size_override("font_size", content_font_size)
	if story_label: story_label.add_theme_font_size_override("font_size", content_font_size)
	if music_label: music_label.add_theme_font_size_override("font_size", content_font_size)
	if sfx_label: sfx_label.add_theme_font_size_override("font_size", content_font_size)
	if screenshake_label: screenshake_label.add_theme_font_size_override("font_size", content_font_size)
	if health_values_label: health_values_label.add_theme_font_size_override("font_size", content_font_size)
	if debug_mode_label: debug_mode_label.add_theme_font_size_override("font_size", content_font_size)
	if language_dropdown: language_dropdown.add_theme_font_size_override("font_size", content_font_size)
	if reset_stories_button: reset_stories_button.add_theme_font_size_override("font_size", content_font_size)
	if screenshake_checkbox: screenshake_checkbox.add_theme_font_size_override("font_size", content_font_size)
	if health_values_checkbox: health_values_checkbox.add_theme_font_size_override("font_size", content_font_size)
	if debug_mode_checkbox: debug_mode_checkbox.add_theme_font_size_override("font_size", content_font_size)

func _setup_language_dropdown() -> void:
	# Sync dropdown selection with current locale
	var current_locale := LocaleManager.get_locale()
	match current_locale:
		"fr":
			language_dropdown.select(0)
		"en":
			language_dropdown.select(1)
		_:
			language_dropdown.select(0)

func _apply_dropdown_style(opt_btn: OptionButton) -> void:
	if not opt_btn:
		return

	var dropdown_cfg: Dictionary = _game_config.get("ui_dropdown", {})
	var popup: PopupMenu = opt_btn.get_popup()
	if not popup:
		return

	for i in range(popup.item_count):
		popup.set_item_as_checkable(i, false)

	var item_bg_asset: String = str(dropdown_cfg.get("item_bg_asset", ""))
	var popup_style: StyleBox = StyleBoxFlat.new()
	var tex_style := UIStyle.build_texture_stylebox(item_bg_asset, dropdown_cfg, 10)
	if tex_style:
		popup_style = tex_style
	else:
		var flat := popup_style as StyleBoxFlat
		flat.bg_color = Color(0.1, 0.1, 0.1, 0.95)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(dropdown_cfg.get("highlight_bg_color", "#FFD700"))
	# Texte du popup en blanc, taille lisible
	var item_text_hex: String = str(dropdown_cfg.get("item_text_color", "#ffffff")).strip_edges()
	var item_text := Color.from_string(item_text_hex, Color.WHITE)
	var hover_text_hex: String = str(dropdown_cfg.get("highlight_text_color", "#ffffff")).strip_edges()
	var hover_text := Color.from_string(hover_text_hex, Color.WHITE)
	var popup_font_sz: int = int(dropdown_cfg.get("popup_font_size", 22))
	popup.add_theme_font_size_override("font_size", popup_font_sz)
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.add_theme_stylebox_override("hover", hover_style)
	popup.add_theme_color_override("font_color", item_text)
	popup.add_theme_color_override("font_hover_color", hover_text)

func _setup_audio_sliders() -> void:
	var vol_music = ProfileManager.get_setting("music_volume", 1.0)
	var vol_sfx = ProfileManager.get_setting("sfx_volume", 1.0)
	
	if music_slider: music_slider.value = vol_music
	if sfx_slider: sfx_slider.value = vol_sfx

func _setup_screenshake_toggle() -> void:
	var enabled := bool(ProfileManager.get_setting("screenshake_enabled", true))
	if screenshake_checkbox:
		screenshake_checkbox.button_pressed = enabled
		_refresh_toggle_button_text(screenshake_checkbox, enabled)

func _setup_health_values_toggle() -> void:
	var enabled: bool = bool(ProfileManager.get_setting("show_health_bar_values", true))
	if health_values_checkbox:
		health_values_checkbox.button_pressed = enabled
		_refresh_toggle_button_text(health_values_checkbox, enabled)

func _setup_debug_mode_toggle() -> void:
	var enabled: bool = bool(ProfileManager.get_setting("manual_debug_mode", false))
	if debug_mode_checkbox:
		debug_mode_checkbox.button_pressed = enabled
		_refresh_toggle_button_text(debug_mode_checkbox, enabled)

func _refresh_toggle_button_text(btn: Button, enabled: bool) -> void:
	if not btn:
		return
	var on_text: String = LocaleManager.translate("options_toggle_on")
	var off_text: String = LocaleManager.translate("options_toggle_off")
	var t: String = on_text if enabled else off_text
	if btn.get_node_or_null("ShadowLabel"):
		UIStyle.set_button_shadow_text(btn, t)
	else:
		btn.text = t
		UIStyle.apply_button_shadow(btn, "small")

func _apply_translations() -> void:
	title_label.text = LocaleManager.translate("options_title")
	language_label.text = LocaleManager.translate("options_language")
	
	if music_label: music_label.text = LocaleManager.translate("options_music")
	if sfx_label: sfx_label.text = LocaleManager.translate("options_sfx")
	if screenshake_label: screenshake_label.text = LocaleManager.translate("options_screenshake")
	if health_values_label: health_values_label.text = LocaleManager.translate("options_health_bar_values")
	if debug_mode_label: debug_mode_label.text = LocaleManager.translate("options_manual_debug_mode")
	_refresh_toggle_button_text(screenshake_checkbox, screenshake_checkbox.button_pressed if screenshake_checkbox else false)
	_refresh_toggle_button_text(health_values_checkbox, health_values_checkbox.button_pressed if health_values_checkbox else false)
	_refresh_toggle_button_text(debug_mode_checkbox, debug_mode_checkbox.button_pressed if debug_mode_checkbox else false)
	if story_label: story_label.text = LocaleManager.translate("options_story")
	if reset_stories_button:
		if reset_stories_button.get_node_or_null("ShadowLabel"):
			UIStyle.set_button_shadow_text(reset_stories_button, LocaleManager.translate("options_reset_stories"))
		else:
			reset_stories_button.text = LocaleManager.translate("options_reset_stories")
			UIStyle.apply_button_shadow(reset_stories_button, "medium")

# =============================================================================
# CALLBACKS
# =============================================================================

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")

func _on_language_selected(index: int) -> void:
	var new_locale: String = ""
	match index:
		0:
			new_locale = "fr"
		1:
			new_locale = "en"
	
	if new_locale != "" and new_locale != LocaleManager.get_locale():
		LocaleManager.set_locale(new_locale)
		# Re-apply translations immediately
		_apply_translations()
		print("[OptionsMenu] Language changed to: ", new_locale)

func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	ProfileManager.set_setting("music_volume", value)

func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	ProfileManager.set_setting("sfx_volume", value)

func _on_screenshake_toggled(enabled: bool) -> void:
	ProfileManager.set_setting("screenshake_enabled", enabled)
	_refresh_toggle_button_text(screenshake_checkbox, enabled)

func _on_health_values_toggled(enabled: bool) -> void:
	ProfileManager.set_setting("show_health_bar_values", enabled)
	_refresh_toggle_button_text(health_values_checkbox, enabled)

func _on_debug_mode_toggled(enabled: bool) -> void:
	ProfileManager.set_setting("manual_debug_mode", enabled)
	_refresh_toggle_button_text(debug_mode_checkbox, enabled)

func _on_reset_stories_pressed() -> void:
	ProfileManager.reset_viewed_stories()
	UIStyle.set_button_shadow_text(reset_stories_button, LocaleManager.translate("options_reset_stories_done"))
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func(): UIStyle.set_button_shadow_text(reset_stories_button, LocaleManager.translate("options_reset_stories")))
