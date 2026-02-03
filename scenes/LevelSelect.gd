extends Control

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var level_list: ItemList = $MarginContainer/VBoxContainer/LevelList
@onready var back_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BackButton
@onready var play_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PlayButton

var selected_level_index: int = -1
var world_id: String = ""

func _ready() -> void:
	print("LevelSelect READY")
	print("selected_world_id meta =", App.get_meta("selected_world_id"))
	print("LevelList node =", level_list)
	back_button.pressed.connect(_on_back_pressed)
	play_button.pressed.connect(_on_play_pressed)
	level_list.item_selected.connect(_on_level_selected)

	var raw: Variant = App.get_meta("selected_world_id")
	world_id = str(raw)

	_load_levels()
	_update_buttons()

func _get_active_progress() -> Dictionary:
	var p := ProfileManager.get_active_profile()
	var prog: Variant = p.get("progress", {})
	if prog is Dictionary:
		return prog as Dictionary
	return {}
	
func _load_levels() -> void:
	level_list.clear()
	selected_level_index = -1

	# Récupérer les données du monde depuis DataManager
	var world := App.get_world(world_id)
	var world_name := str(world.get("name", world_id))
	
	# Les niveaux sont maintenant dans un array "levels" dans le JSON
	var levels_data: Variant = world.get("levels", [])
	var levels_array: Array = []
	if levels_data is Array:
		levels_array = levels_data as Array
	
	var levels_count := levels_array.size()
	if levels_count == 0:
		levels_count = 6  # fallback

	title_label.text = "Monde : " + world_name

	var prog := _get_active_progress()
	var wprog: Variant = prog.get(world_id, {})
	var max_unlocked := 0
	if wprog is Dictionary:
		max_unlocked = int((wprog as Dictionary).get("max_unlocked_level", 0))

	for i in range(levels_count):
		var label := "Niveau " + str(i + 1)
		
		# Utiliser le nom du niveau depuis les données JSON si disponible
		if i < levels_array.size():
			var level_data: Variant = levels_array[i]
			if level_data is Dictionary:
				var level_dict := level_data as Dictionary
				var level_type := str(level_dict.get("type", "normal"))
				if level_type == "boss":
					label = "Boss : " + str(level_dict.get("name", "Boss"))
				else:
					label = str(level_dict.get("name", "Niveau " + str(i + 1)))

		level_list.add_item(label)
		level_list.set_item_metadata(i, i)
		if i > max_unlocked:
			level_list.set_item_disabled(i, true)

func _update_buttons() -> void:
	play_button.disabled = (selected_level_index < 0)

func _on_level_selected(index: int) -> void:
	var raw_idx: Variant = level_list.get_item_metadata(index)
	selected_level_index = int(raw_idx)
	_update_buttons()

func _on_play_pressed() -> void:
	if selected_level_index < 0:
		return
	App.set_meta("selected_level_index", selected_level_index)

	# Lancer directement le gameplay
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/WorldSelect.tscn")
