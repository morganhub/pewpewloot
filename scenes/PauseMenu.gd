extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## PauseMenu — Menu de pause avec options de navigation.

signal resume_requested
signal restart_requested
signal level_select_requested
signal quit_requested

@onready var panel: PanelContainer = $Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_popup_style()
	hide()

func _apply_popup_style() -> void:
	if not panel: return
	
	var game_config: Dictionary = {}
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			game_config = json.data
	
	var popup_config: Dictionary = game_config.get("popups", {})
	var popup_bg_cfg: Dictionary = popup_config.get("background", {}) if popup_config.get("background") is Dictionary else {}
	var popup_bg_asset: String = str(popup_bg_cfg.get("asset", ""))
	var margin: int = int(popup_config.get("margin", 20))
	
	var style := UIStyle.build_texture_stylebox(popup_bg_asset, popup_bg_cfg, margin)
	if style:
		panel.add_theme_stylebox_override("panel", style)

func show_menu() -> void:
	_translate()
	show()
	get_tree().paused = true

func _translate() -> void:
	var title = panel.get_node_or_null("Margin/VBox/Title")
	if title: title.text = LocaleManager.translate("pause_title")
	
	var resume_btn = panel.get_node_or_null("Margin/VBox/ResumeButton")
	if resume_btn: resume_btn.text = LocaleManager.translate("pause_resume")
	
	var restart_btn = panel.get_node_or_null("Margin/VBox/RestartButton")
	if restart_btn: restart_btn.text = LocaleManager.translate("pause_restart")
	
	var level_btn = panel.get_node_or_null("Margin/VBox/LevelSelectButton")
	if level_btn: level_btn.text = LocaleManager.translate("pause_level_select")
	
	var quit_btn = panel.get_node_or_null("Margin/VBox/QuitButton")
	if quit_btn: quit_btn.text = LocaleManager.translate("pause_quit")

func set_continue_enabled(enabled: bool) -> void:
	var resume_btn := panel.get_node_or_null("Margin/VBox/ResumeButton") as Button
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
