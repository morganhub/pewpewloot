extends Control

@onready var world_list: ItemList = $MarginContainer/VBoxContainer/WorldList
@onready var back_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BackButton
@onready var next_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/NextButton

var selected_world_id: String = ""

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	world_list.item_selected.connect(_on_world_selected)

	_load_worlds()
	_update_buttons()

func _load_worlds() -> void:
	world_list.clear()
	selected_world_id = ""

	var prog := _get_active_progress()

	for w in App.get_worlds():
		var world_name := str(w.get("name", "Unknown"))
		var world_id := str(w.get("id", ""))

		var idx := world_list.item_count
		world_list.add_item(world_name)
		world_list.set_item_metadata(idx, world_id)

		var wprog: Variant = prog.get(world_id, {})
		var unlocked := false
		if wprog is Dictionary:
			unlocked = bool((wprog as Dictionary).get("unlocked", false))

		if not unlocked:
			world_list.set_item_disabled(idx, true)


func _update_buttons() -> void:
	next_button.disabled = (selected_world_id == "")

func _on_world_selected(index: int) -> void:
	var raw_id: Variant = world_list.get_item_metadata(index)
	selected_world_id = str(raw_id)
	_update_buttons()

func _get_active_progress() -> Dictionary:
	var p := ProfileManager.get_active_profile()
	var prog: Variant = p.get("progress", {})
	if prog is Dictionary:
		return prog as Dictionary
	return {}
	
func _on_next_pressed() -> void:
	if selected_world_id == "":
		return
	var switcher := get_tree().current_scene
	print("NEXT world =", selected_world_id)
	App.set_meta("selected_world_id", selected_world_id)
	switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")
