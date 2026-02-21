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

@onready var sound_label: Label = $MarginContainer/VBoxContainer/SoundSection/SoundLabel
@onready var music_label: Label = $MarginContainer/VBoxContainer/SoundSection/MusicBox/Label
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/MusicBox/MusicSlider
@onready var sfx_label: Label = $MarginContainer/VBoxContainer/SoundSection/SFXBox/Label
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/SFXBox/SFXSlider
@onready var screenshake_label: Label = $MarginContainer/VBoxContainer/SoundSection/ScreenShakeBox/Label
@onready var screenshake_checkbox: Button = $MarginContainer/VBoxContainer/SoundSection/ScreenShakeBox/ScreenShakeCheckbox
@onready var health_values_label: Label = $MarginContainer/VBoxContainer/SoundSection/HealthValuesBox/Label
@onready var health_values_checkbox: Button = $MarginContainer/VBoxContainer/SoundSection/HealthValuesBox/HealthValuesCheckbox

var _game_config: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	_setup_background()
	_setup_language_dropdown()
	_apply_dropdown_style(language_dropdown)
	_setup_audio_sliders()
	_setup_screenshake_toggle()
	_setup_health_values_toggle()
	_apply_translations()
	
	# Connect signals
	back_button.pressed.connect(_on_back_pressed)
	language_dropdown.item_selected.connect(_on_language_selected)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	screenshake_checkbox.toggled.connect(_on_screenshake_toggled)
	health_values_checkbox.toggled.connect(_on_health_values_toggled)
	
	# Setup Back Button Icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.texture_normal = load(back_icon_path)

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
	var item_text := Color(dropdown_cfg.get("item_text_color", "#000000"))
	var hover_text := Color(dropdown_cfg.get("highlight_text_color", "#000000"))

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

func _refresh_toggle_button_text(btn: Button, enabled: bool) -> void:
	if not btn:
		return
	var on_text: String = LocaleManager.translate("options_toggle_on")
	var off_text: String = LocaleManager.translate("options_toggle_off")
	btn.text = on_text if enabled else off_text

func _apply_translations() -> void:
	title_label.text = LocaleManager.translate("options_title")
	language_label.text = LocaleManager.translate("options_language")
	
	if sound_label: sound_label.text = LocaleManager.translate("options_sound")
	if music_label: music_label.text = LocaleManager.translate("options_music")
	if sfx_label: sfx_label.text = LocaleManager.translate("options_sfx")
	if screenshake_label: screenshake_label.text = LocaleManager.translate("options_screenshake")
	if health_values_label: health_values_label.text = LocaleManager.translate("options_health_bar_values")
	_refresh_toggle_button_text(screenshake_checkbox, screenshake_checkbox.button_pressed if screenshake_checkbox else false)
	_refresh_toggle_button_text(health_values_checkbox, health_values_checkbox.button_pressed if health_values_checkbox else false)
	
	# No back button text anymore as it is an icon

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
