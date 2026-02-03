extends Control

@onready var profile_list: ItemList = $MarginContainer/VBoxContainer/HBoxContainer/ProfileList
@onready var name_input: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/NameInput
@onready var portrait_option: OptionButton = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/PortraitOption
@onready var create_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/CreateButton
@onready var select_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/SelectButton
@onready var delete_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/DeleteButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/BackButton


var selected_profile_id: String = ""

func _ready() -> void:
	print("ProfileSelect READY")
	create_button.pressed.connect(_on_create_pressed)
	select_button.pressed.connect(_on_select_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	profile_list.item_selected.connect(_on_profile_selected)

	# Portrait choices (placeholder)
	portrait_option.clear()
	for i in range(6):
		portrait_option.add_item("Portrait " + str(i + 1), i)

	_refresh_list()

func _refresh_list() -> void:
	profile_list.clear()
	selected_profile_id = ""

	for p in ProfileManager.profiles:
		var profile_name := str(p.get("name", "Unnamed"))
		var id := str(p.get("id", ""))
		profile_list.add_item(profile_name)
		# stocker l'id dans les metadata de l'item
		profile_list.set_item_metadata(profile_list.item_count - 1, id)

	_update_buttons()


func _update_buttons() -> void:
	var has_selection := selected_profile_id != ""
	select_button.disabled = not has_selection
	delete_button.disabled = not has_selection
	
	if ProfileManager.active_profile_id != "":
		# On vient de HomeScreen
		back_button.text = LocaleManager.translate("item_popup_cancel")
	else:
		# On est au root (pas de profil chargé)
		back_button.text = LocaleManager.translate("home_quit")

func _on_profile_selected(index: int) -> void:
	var raw_id: Variant = profile_list.get_item_metadata(index)
	selected_profile_id = str(raw_id)
	_update_buttons()

func _on_create_pressed() -> void:
	print("Create pressed")
	var raw_name := name_input.text.strip_edges()
	if raw_name.length() < 2:
		return

	var portrait_id := portrait_option.get_selected_id()
	ProfileManager.create_profile(raw_name, portrait_id)
	name_input.text = ""
	_refresh_list()

func _on_select_pressed() -> void:
	if selected_profile_id == "":
		return
	ProfileManager.set_active_profile(selected_profile_id)

	# Aller vers l'écran d'accueil
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")

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
