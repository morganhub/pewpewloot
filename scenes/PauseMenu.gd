extends Control

## PauseMenu — Menu de pause avec options de navigation.

signal resume_requested
signal restart_requested
signal level_select_requested
signal quit_requested

@onready var panel: PanelContainer = $Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func show_menu() -> void:
	show()
	get_tree().paused = true

func set_continue_enabled(enabled: bool) -> void:
	var resume_btn := panel.get_node_or_null("VBoxContainer/ResumeButton") as Button
	if resume_btn:
		resume_btn.disabled = not enabled

func hide_menu() -> void:
	hide()
	get_tree().paused = false

func _on_resume_pressed() -> void:
	hide_menu()
	resume_requested.emit()

func _on_restart_pressed() -> void:
	hide_menu()
	restart_requested.emit()

func _on_level_select_pressed() -> void:
	hide_menu()
	level_select_requested.emit()

func _on_quit_pressed() -> void:
	hide_menu()
	quit_requested.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		hide_menu()
