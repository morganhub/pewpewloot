extends Control

## ProfileSelect — Sélection/création de profil avec popup pour création.
## Design moderne avec fond similaire à HomeScreen.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var profile_list: ItemList = $CenterContainer/MainPanel/ProfileListContainer/ProfileList
@onready var create_button: Button = $CenterContainer/MainPanel/ButtonsContainer/CreateButton
@onready var delete_button: Button = $CenterContainer/MainPanel/ButtonsContainer/DeleteButton
@onready var back_button: Button = $CenterContainer/MainPanel/ButtonsContainer/BackButton

@onready var create_popup: Panel = $CreatePopup
@onready var popup_name_label: Label = $CreatePopup/PopupContent/NameLabel
@onready var popup_name_input: LineEdit = $CreatePopup/PopupContent/NameInput
@onready var popup_portrait_label: Label = $CreatePopup/PopupContent/PortraitLabel
@onready var popup_portrait_option: OptionButton = $CreatePopup/PopupContent/PortraitOption
@onready var popup_validate: Button = $CreatePopup/PopupContent/ButtonsRow/ValidateButton
@onready var popup_cancel: Button = $CreatePopup/PopupContent/ButtonsRow/CancelButton

var selected_profile_id: String = ""
var _game_config: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	App.play_menu_music()
	_load_game_config()
	_setup_background()
	
	# Connect signals
	create_button.pressed.connect(_on_create_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	profile_list.item_selected.connect(_on_profile_selected)
	profile_list.item_activated.connect(_on_profile_activated)
	
	# Popup signals
	popup_validate.pressed.connect(_on_popup_validate_pressed)
	popup_cancel.pressed.connect(_on_popup_cancel_pressed)
	
	# Portrait choices (placeholder)
	popup_portrait_option.clear()
	for i in range(6):
		popup_portrait_option.add_item("Portrait " + str(i + 1), i)
	
	create_popup.visible = false
	_refresh_list()

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			_game_config = json.data

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
	
	# Back button text
	# Back button text/icon
	if ProfileManager.active_profile_id != "":
		# Mode Back
		var ui_icons: Dictionary = _game_config.get("ui_icons", {})
		var back_icon = str(ui_icons.get("back_button", ""))
		if back_icon != "" and ResourceLoader.exists(back_icon):
			back_button.icon = load(back_icon)
			back_button.text = ""
		else:
			back_button.icon = null
			back_button.text = "← Retour"
	else:
		# Mode Quit
		back_button.icon = null
		back_button.text = "🚪 Quitter"

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
	# Show popup
	popup_name_input.text = ""
	popup_portrait_option.select(0)
	create_popup.visible = true
	popup_name_input.grab_focus()

func _on_popup_validate_pressed() -> void:
	var raw_name := popup_name_input.text.strip_edges()
	if raw_name.length() < 2:
		return

	var portrait_id := popup_portrait_option.get_selected_id()
	ProfileManager.create_profile(raw_name, portrait_id)
	
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
	if ProfileManager.active_profile_id != "":
		# Retour à l'accueil
		var switcher := get_tree().current_scene
		switcher.goto_screen("res://scenes/HomeScreen.tscn")
	else:
		# Quitter le jeu
		get_tree().quit()
