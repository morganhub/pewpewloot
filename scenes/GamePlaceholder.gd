extends Control

@onready var info_label: Label = $CenterContainer/Box/InfoLabel
@onready var complete_button: Button = $CenterContainer/Box/CompleteButton
@onready var back_button: Button = $CenterContainer/Box/BackButton

func _ready() -> void:
	complete_button.pressed.connect(_on_complete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_refresh_info()

func _refresh_info() -> void:
	var world_id := App.current_world_id
	var level_index := App.current_level_index
	
	# Récupérer le nom du monde et du niveau
	var world := App.get_world(world_id)
	var world_name := str(world.get("name", world_id))
	
	# Récupérer le vaisseau actif
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var ship_name := str(ship.get("name", ship_id))
	
	info_label.text = "En cours : " + world_name + " / niveau " + str(level_index + 1)
	info_label.text += "\nVaisseau : " + ship_name

func _on_complete_pressed() -> void:
	var world_id := App.current_world_id
	var level_index := App.current_level_index

	# Marque le niveau comme complété -> unlock suivant
	ProfileManager.complete_level(world_id, level_index, 6)

	# Si boss terminé (index 5), débloque monde suivant
	if level_index == 5:
		ProfileManager.unlock_next_world_if_needed(world_id)

	# Retour à LevelSelect pour constater les unlocks
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/LevelSelect.tscn")
