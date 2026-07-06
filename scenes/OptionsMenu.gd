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
@onready var control_label: Label = $MarginContainer/VBoxContainer/ControlSection/ControlLabel
@onready var control_dropdown: OptionButton = $MarginContainer/VBoxContainer/ControlSection/ControlDropdown

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
@onready var debug_section: VBoxContainer = $MarginContainer/VBoxContainer/DebugSection
@onready var story_label: Label = $MarginContainer/VBoxContainer/StorySection/StoryLabel
@onready var reset_stories_button: Button = $MarginContainer/VBoxContainer/StorySection/ResetStoriesButton
@onready var story_section: HBoxContainer = $MarginContainer/VBoxContainer/StorySection

var _game_config: Dictionary = {}
var _debug_actions_section: VBoxContainer = null
var _debug_unlock_all_button: Button = null
var _debug_reset_stories_button: Button = null
var _debug_reset_level_button: Button = null
var _debug_start_story_button: Button = null
var _debug_reset_equipment_button: Button = null
var _debug_reset_profile_button: Button = null

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
	_setup_control_dropdown()
	_apply_dropdown_style(control_dropdown)
	if control_dropdown:
		var ctrl_popup: PopupMenu = control_dropdown.get_popup()
		if ctrl_popup:
			ctrl_popup.add_theme_font_size_override("font_size", content_sz)
	_setup_audio_sliders()
	_setup_screenshake_toggle()
	_setup_health_values_toggle()
	_setup_debug_mode_toggle()
	_setup_debug_actions_section()
	_apply_translations()
	UIStyle.apply_default_button_style(reset_stories_button, "medium")
	UIStyle.apply_default_button_style(screenshake_checkbox, "small")
	UIStyle.apply_default_button_style(health_values_checkbox, "small")
	UIStyle.apply_default_button_style(debug_mode_checkbox, "small")
	if story_section:
		story_section.visible = false
	
	# Connect signals
	back_button.pressed.connect(_on_back_pressed)
	language_dropdown.item_selected.connect(_on_language_selected)
	if control_dropdown:
		control_dropdown.item_selected.connect(_on_control_mode_selected)
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
	if title_label: title_label.add_theme_font_size_override("font_size", int(cfg.get("screen_title_text_size", 32)))
	if language_label: language_label.add_theme_font_size_override("font_size", content_font_size)
	if control_label: control_label.add_theme_font_size_override("font_size", content_font_size)
	if control_dropdown: control_dropdown.add_theme_font_size_override("font_size", content_font_size)
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

func _setup_control_dropdown() -> void:
	if not control_dropdown:
		return
	var current_mode: String = str(ProfileManager.get_setting("control_mode", "virtual_stick"))
	match current_mode:
		"follow_finger":
			control_dropdown.select(1)
		_:
			control_dropdown.select(0)

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
	_refresh_debug_actions_visibility()

func _setup_debug_actions_section() -> void:
	if debug_section == null:
		return
	if _debug_actions_section != null and is_instance_valid(_debug_actions_section):
		return
	_debug_actions_section = VBoxContainer.new()
	_debug_actions_section.name = "DebugActionsSection"
	_debug_actions_section.add_theme_constant_override("separation", 10)
	debug_section.add_child(_debug_actions_section)

	var title := Label.new()
	title.name = "DebugActionsTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(_get_options_config().get("title_text_size", 24)))
	_debug_actions_section.add_child(title)

	var grid := GridContainer.new()
	grid.name = "DebugActionsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_debug_actions_section.add_child(grid)

	_debug_unlock_all_button = _create_debug_button("UnlockAllButton", _on_debug_unlock_all_pressed)
	_debug_reset_stories_button = _create_debug_button("ResetStoriesButton", _on_debug_reset_stories_pressed)
	_debug_reset_level_button = _create_debug_button("ResetLevelButton", _on_debug_reset_level_pressed)
	_debug_start_story_button = _create_debug_button("StartStoryButton", _on_debug_start_story_pressed)
	_debug_reset_equipment_button = _create_debug_button("ResetEquipmentButton", _on_debug_reset_equipment_pressed)
	_debug_reset_profile_button = _create_debug_button("ResetProfileButton", _on_debug_reset_profile_pressed)
	for btn in [
		_debug_unlock_all_button,
		_debug_reset_stories_button,
		_debug_reset_level_button,
		_debug_start_story_button,
		_debug_reset_equipment_button,
		_debug_reset_profile_button
	]:
		grid.add_child(btn)
	_refresh_debug_actions_visibility()

func _create_debug_button(button_name: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.name = button_name
	btn.custom_minimum_size = Vector2(220, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", int(_get_options_config().get("title_text_size", 24)))
	UIStyle.apply_default_button_style(btn, "small")
	UIStyle.apply_button_shadow(btn, "small")
	btn.pressed.connect(callback)
	return btn

func _get_options_config() -> Dictionary:
	var screens_v: Variant = _game_config.get("screens", {})
	if screens_v is Dictionary:
		var opts_v: Variant = (screens_v as Dictionary).get("options_menu", {})
		if opts_v is Dictionary:
			return opts_v as Dictionary
	var cfg_v: Variant = _game_config.get("options_menu", {})
	return cfg_v if cfg_v is Dictionary else {}

func _refresh_debug_actions_visibility() -> void:
	if _debug_actions_section == null or not is_instance_valid(_debug_actions_section):
		return
	_debug_actions_section.visible = bool(ProfileManager.get_setting("manual_debug_mode", false))

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
	if control_label:
		control_label.text = LocaleManager.translate("options_control_mode")
	if control_dropdown:
		control_dropdown.set_item_text(0, LocaleManager.translate("options_control_virtual_stick"))
		control_dropdown.set_item_text(1, LocaleManager.translate("options_control_follow_finger"))
	
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
	_apply_debug_action_translations()

func _apply_debug_action_translations() -> void:
	if _debug_actions_section == null or not is_instance_valid(_debug_actions_section):
		return
	var title: Label = _debug_actions_section.get_node_or_null("DebugActionsTitle") as Label
	if title:
		title.text = LocaleManager.translate("options_debug_actions")
	_set_button_text(_debug_unlock_all_button, "options_debug_unlock_all")
	_set_button_text(_debug_reset_stories_button, "options_debug_reset_stories")
	_set_button_text(_debug_reset_level_button, "options_debug_reset_level")
	_set_button_text(_debug_start_story_button, "options_debug_start_story")
	_set_button_text(_debug_reset_equipment_button, "options_debug_reset_equipment")
	_set_button_text(_debug_reset_profile_button, "options_debug_reset_profile")

func _set_button_text(button: Button, locale_key: String) -> void:
	if button == null:
		return
	var text := LocaleManager.translate(locale_key)
	if button.get_node_or_null("ShadowLabel"):
		UIStyle.set_button_shadow_text(button, text)
	else:
		button.text = text
		UIStyle.apply_button_shadow(button, "small")

# =============================================================================
# CALLBACKS
# =============================================================================

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")

func _on_control_mode_selected(index: int) -> void:
	var mode: String = "virtual_stick"
	if index == 1:
		mode = "follow_finger"
	ProfileManager.set_setting("control_mode", mode)
	print("[OptionsMenu] Control mode changed to: ", mode)

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
	_refresh_debug_actions_visibility()

func _on_reset_stories_pressed() -> void:
	ProfileManager.reset_viewed_stories()
	UIStyle.set_button_shadow_text(reset_stories_button, LocaleManager.translate("options_reset_stories_done"))
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func(): UIStyle.set_button_shadow_text(reset_stories_button, LocaleManager.translate("options_reset_stories")))

func _on_debug_unlock_all_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
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
	_show_debug_button_done(_debug_unlock_all_button, "options_debug_unlock_all_done", "options_debug_unlock_all")

func _on_debug_reset_stories_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	ProfileManager.reset_viewed_stories()
	_show_debug_button_done(_debug_reset_stories_button, "options_debug_reset_stories_done", "options_debug_reset_stories")

func _on_debug_reset_level_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	ProfileManager.reset_player_level_progress()
	_show_debug_button_done(_debug_reset_level_button, "options_debug_reset_level_done", "options_debug_reset_level")

func _on_debug_start_story_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	StoryManager.play_debug_story_flow()

func _on_debug_reset_equipment_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	if ProfileManager.has_method("reset_active_equipment_state"):
		ProfileManager.call("reset_active_equipment_state")
	_show_debug_button_done(_debug_reset_equipment_button, "options_debug_reset_equipment_done", "options_debug_reset_equipment")

func _on_debug_reset_profile_pressed() -> void:
	if not ProfileManager.is_debug_mode_enabled():
		return
	if ProfileManager.has_method("delete_active_profile"):
		ProfileManager.call("delete_active_profile")
	else:
		ProfileManager.delete_profile(ProfileManager.active_profile_id)
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

func _show_debug_button_done(button: Button, done_key: String, reset_key: String) -> void:
	if button == null:
		return
	button.disabled = true
	UIStyle.set_button_shadow_text(button, LocaleManager.translate(done_key))
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func():
		if button != null and is_instance_valid(button):
			button.disabled = false
			UIStyle.set_button_shadow_text(button, LocaleManager.translate(reset_key))
	)
