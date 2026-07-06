extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## ProfileSelect — Sélection/création de profil avec popup pour création.
## Design moderne avec fond similaire à HomeScreen.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var title_label: Label = $CenterContainer/MainPanel/TitleLabel
@onready var list_label: Label = $CenterContainer/MainPanel/ProfileListContainer/ListLabel
@onready var profile_list: ItemList = $CenterContainer/MainPanel/ProfileListContainer/ProfileList
@onready var create_button: Button = $CenterContainer/MainPanel/ButtonsContainer/CreateButton
@onready var delete_button: Button = $CenterContainer/MainPanel/ButtonsContainer/DeleteButton
@onready var back_button: TextureButton = $CenterContainer/MainPanel/HeaderContainer/BackButton

@onready var create_popup: PanelContainer = $CreatePopup
@onready var popup_title: Label = $CreatePopup/MarginContainer/PopupContent/PopupTitle
@onready var popup_name_label: Label = $CreatePopup/MarginContainer/PopupContent/NameLabel
@onready var popup_name_input: LineEdit = $CreatePopup/MarginContainer/PopupContent/NameInput
@onready var popup_validate: Button = $CreatePopup/MarginContainer/PopupContent/ButtonsRow/ValidateButton
@onready var popup_cancel: Button = $CreatePopup/MarginContainer/PopupContent/ButtonsRow/CancelButton

var selected_profile_id: String = ""
var _game_config: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	App.play_menu_music()
	_load_game_config()
	_setup_background()
	_apply_popup_style()
	
	# Connect signals
	create_button.pressed.connect(_on_create_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	profile_list.item_selected.connect(_on_profile_selected)
	profile_list.item_activated.connect(_on_profile_activated)
	
	# Popup signals
	popup_validate.pressed.connect(_on_popup_validate_pressed)
	popup_cancel.pressed.connect(_on_popup_cancel_pressed)
	
	create_popup.visible = false
	_refresh_list()

	UIStyle.apply_default_button_style(create_button, "medium")
	UIStyle.apply_default_button_style(delete_button, "medium")
	var val_cfg := UIStyle.get_validation_config()
	UIStyle.apply_validation_to_button(popup_validate, val_cfg, "medium")
	UIStyle.apply_default_button_style(popup_cancel, "medium")
	UIStyle.apply_button_shadow(create_button, "medium")
	UIStyle.apply_button_shadow(delete_button, "medium")
	UIStyle.apply_button_shadow(popup_validate, "medium")
	UIStyle.apply_button_shadow(popup_cancel, "medium")
	_apply_typography()
	_apply_translations()

func _load_game_config() -> void:
	if DataManager:
		_game_config = DataManager.get_game_config()
	else:
		_game_config = {}

func _setup_background() -> void:
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	var bg_path: String = str(menu_config.get("background", ""))
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and background_rect:
			background_rect.texture = tex
			background_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		if background_rect:
			background_rect.visible = false

func _apply_popup_style() -> void:
	if not create_popup: return
	
	var popup_config: Dictionary = _game_config.get("popups", {})
	var popup_bg_cfg: Dictionary = popup_config.get("background", {}) if popup_config.get("background") is Dictionary else {}
	var popup_bg_asset: String = str(popup_bg_cfg.get("asset", ""))
	var margin: int = int(popup_config.get("margin", 20))
	
	var style := UIStyle.build_texture_stylebox(popup_bg_asset, popup_bg_cfg, margin)
	if style:
		create_popup.add_theme_stylebox_override("panel", style)
	
	# Footer : bouton retour en bas
	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)
	if back_button:
		back_button.visible = false

func _get_profile_select_config() -> Dictionary:
	var screens_v: Variant = _game_config.get("screens", {})
	if screens_v is Dictionary:
		var screen_cfg_v: Variant = (screens_v as Dictionary).get("profile_select", {})
		if screen_cfg_v is Dictionary:
			return screen_cfg_v as Dictionary
	var root_v: Variant = _game_config.get("profile_select", {})
	return root_v if root_v is Dictionary else {}

func _apply_typography() -> void:
	var cfg := _get_profile_select_config()
	if title_label:
		title_label.add_theme_font_size_override("font_size", int(cfg.get("title_font_size", 36)))
	if list_label:
		list_label.add_theme_font_size_override("font_size", int(cfg.get("list_label_font_size", 20)))
	if profile_list:
		profile_list.add_theme_font_size_override("font_size", int(cfg.get("profile_list_font_size", 20)))
	var button_font_size: int = int(cfg.get("button_font_size", 22))
	if create_button:
		create_button.add_theme_font_size_override("font_size", button_font_size)
	if delete_button:
		delete_button.add_theme_font_size_override("font_size", button_font_size)
	if popup_title:
		popup_title.add_theme_font_size_override("font_size", int(cfg.get("popup_title_font_size", 24)))
	if popup_name_label:
		popup_name_label.add_theme_font_size_override("font_size", int(cfg.get("popup_label_font_size", 18)))
	if popup_name_input:
		popup_name_input.add_theme_font_size_override("font_size", int(cfg.get("popup_input_font_size", 18)))
	var popup_button_font_size: int = int(cfg.get("popup_button_font_size", 18))
	if popup_validate:
		popup_validate.add_theme_font_size_override("font_size", popup_button_font_size)
	if popup_cancel:
		popup_cancel.add_theme_font_size_override("font_size", popup_button_font_size)

func _apply_translations() -> void:
	if title_label:
		title_label.text = LocaleManager.translate("profile_select_title")
	if list_label:
		list_label.text = LocaleManager.translate("profile_select_choose")
	if create_button:
		create_button.text = LocaleManager.translate("profile_select_create")
	if delete_button:
		delete_button.text = LocaleManager.translate("profile_select_delete")
	if popup_title:
		popup_title.text = LocaleManager.translate("profile_select_create_title")
	if popup_name_label:
		popup_name_label.text = LocaleManager.translate("profile_select_name_label")
	if popup_name_input:
		popup_name_input.placeholder_text = LocaleManager.translate("profile_select_name_hint")
	if popup_validate:
		popup_validate.text = LocaleManager.translate("profile_select_validate")
	if popup_cancel:
		popup_cancel.text = LocaleManager.translate("profile_select_back")

func _refresh_list() -> void:
	profile_list.clear()
	selected_profile_id = ""

	for p in ProfileManager.profiles:
		var profile_name := str(p.get("name", "Unnamed"))
		var id := str(p.get("id", ""))
		profile_list.add_item(profile_name)
		profile_list.set_item_metadata(profile_list.item_count - 1, id)

	_update_buttons()

func _update_buttons() -> void:
	var has_selection := selected_profile_id != ""
	delete_button.disabled = not has_selection

func _on_profile_selected(index: int) -> void:
	var raw_id: Variant = profile_list.get_item_metadata(index)
	selected_profile_id = str(raw_id)
	_update_buttons()

func _on_profile_activated(index: int) -> void:
	# Double-click ou Enter = Sélectionner le profil
	var raw_id: Variant = profile_list.get_item_metadata(index)
	var profile_id := str(raw_id)
	if profile_id != "":
		ProfileManager.set_active_profile(profile_id)
		var switcher := get_tree().current_scene
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

func _on_create_pressed() -> void:
	popup_name_input.text = ProfileManager.get_suggested_player_display_name()
	create_popup.visible = true
	popup_name_input.grab_focus()

func _on_popup_validate_pressed() -> void:
	var raw_name := popup_name_input.text.strip_edges()
	if raw_name.length() < 2:
		return

	ProfileManager.create_profile(raw_name)
	
	create_popup.visible = false
	_refresh_list()

func _on_popup_cancel_pressed() -> void:
	create_popup.visible = false

func _on_delete_pressed() -> void:
	if selected_profile_id == "":
		return
	ProfileManager.delete_profile(selected_profile_id)
	_refresh_list()

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")
	else:
		get_tree().quit()
