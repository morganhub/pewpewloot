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
	_apply_button_styles()
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
	
	var validation_cfg: Dictionary = UIStyle.get_validation_config()
	var resume_btn := panel.get_node_or_null("Margin/VBox/ResumeButton") as Button
	if resume_btn and not validation_cfg.is_empty() and str(validation_cfg.get("asset", "")) != "":
		UIStyle.apply_validation_to_button(resume_btn, validation_cfg, "large")

func _apply_button_styles() -> void:
	var resume_btn := panel.get_node_or_null("Margin/VBox/ResumeButton") as Button
	if resume_btn:
		pass  # already applied in _apply_popup_style
	var restart_btn := panel.get_node_or_null("Margin/VBox/RestartButton") as Button
	if restart_btn:
		UIStyle.apply_default_button_style(restart_btn, "medium")
	var level_btn := panel.get_node_or_null("Margin/VBox/LevelSelectButton") as Button
	if level_btn:
		UIStyle.apply_default_button_style(level_btn, "medium")
	var quit_btn := panel.get_node_or_null("Margin/VBox/QuitButton") as Button
	if quit_btn:
		var cancel_cfg: Dictionary = UIStyle.get_cancellation_config()
		if not cancel_cfg.is_empty() and str(cancel_cfg.get("asset", "")) != "":
			UIStyle.apply_cancellation_to_button(quit_btn, cancel_cfg, "medium")
		else:
			UIStyle.apply_default_button_style(quit_btn, "medium")
	var btn_size: Vector2 = UIStyle.get_default_button_min_size()
	for name in ["ResumeButton", "RestartButton", "LevelSelectButton", "QuitButton"]:
		var btn: Button = panel.get_node_or_null("Margin/VBox/" + name) as Button
		if btn:
			btn.custom_minimum_size = btn_size

func show_menu() -> void:
	_translate()
	show()
	get_tree().paused = true

func _translate() -> void:
	var title = panel.get_node_or_null("Margin/VBox/Title")
	if title: title.text = LocaleManager.translate("pause_title")
	
	var resume_btn = panel.get_node_or_null("Margin/VBox/ResumeButton")
	if resume_btn:
		resume_btn.text = LocaleManager.translate("pause_resume")
		UIStyle.apply_button_shadow(resume_btn, "large")
	
	var restart_btn = panel.get_node_or_null("Margin/VBox/RestartButton")
	if restart_btn:
		restart_btn.text = LocaleManager.translate("pause_restart")
		UIStyle.apply_button_shadow(restart_btn, "medium")
	
	var level_btn = panel.get_node_or_null("Margin/VBox/LevelSelectButton")
	if level_btn:
		level_btn.text = LocaleManager.translate("pause_level_select")
		UIStyle.apply_button_shadow(level_btn, "medium")
	
	var quit_btn = panel.get_node_or_null("Margin/VBox/QuitButton")
	if quit_btn:
		quit_btn.text = LocaleManager.translate("pause_quit")
		UIStyle.apply_button_shadow(quit_btn, "medium")

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
