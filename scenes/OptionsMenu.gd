extends Control

## OptionsMenu — Menu des options avec sélection de langue.
## Accessible depuis l'écran d'accueil via le bouton "Options".

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/Header/BackButton
@onready var language_label: Label = $MarginContainer/VBoxContainer/LanguageSection/LanguageLabel
@onready var language_dropdown: OptionButton = $MarginContainer/VBoxContainer/LanguageSection/LanguageDropdown

@onready var sound_label: Label = $MarginContainer/VBoxContainer/SoundSection/SoundLabel
@onready var music_label: Label = $MarginContainer/VBoxContainer/SoundSection/MusicBox/Label
@onready var music_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/MusicBox/MusicSlider
@onready var sfx_label: Label = $MarginContainer/VBoxContainer/SoundSection/SFXBox/Label
@onready var sfx_slider: HSlider = $MarginContainer/VBoxContainer/SoundSection/SFXBox/SFXSlider

var _game_config: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	_setup_background()
	_setup_language_dropdown()
	_setup_audio_sliders()
	_apply_translations()
	
	# Connect signals
	back_button.pressed.connect(_on_back_pressed)
	language_dropdown.item_selected.connect(_on_language_selected)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	
	# Setup Back Button Icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.icon = load(back_icon_path)
		back_button.text = ""
		back_button.flat = true
		back_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

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

func _setup_audio_sliders() -> void:
	var vol_music = ProfileManager.get_setting("music_volume", 1.0)
	var vol_sfx = ProfileManager.get_setting("sfx_volume", 1.0)
	
	if music_slider: music_slider.value = vol_music
	if sfx_slider: sfx_slider.value = vol_sfx

func _apply_translations() -> void:
	title_label.text = LocaleManager.translate("options_title")
	language_label.text = LocaleManager.translate("options_language")
	
	if sound_label: sound_label.text = LocaleManager.translate("options_sound")
	if music_label: music_label.text = LocaleManager.translate("options_music")
	if sfx_label: sfx_label.text = LocaleManager.translate("options_sfx")
	
	if back_button.icon == null:
		back_button.text = LocaleManager.translate("options_back")
	else:
		back_button.text = ""

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
