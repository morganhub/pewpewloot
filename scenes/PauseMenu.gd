extends CanvasLayer
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## PauseMenu — Menu de pause avec options de navigation.
## Taille du panel, boutons et polices pilotés par game.json → pauseMenu.

signal resume_requested
signal restart_requested
signal level_select_requested
signal quit_requested

@onready var panel: PanelContainer = $Panel
@onready var overlay: ColorRect = $Overlay
@onready var resume_countdown: CenterContainer = $ResumeCountdown
@onready var countdown_label: Label = $ResumeCountdown/CountdownLabel

const COUNTDOWN_SEQUENCE: Array[int] = [3, 2, 1]
const COUNTDOWN_TICK_DURATION: float = 0.8
# Plus le chiffre est petit, plus il commence gros (effet d'impact qui grossit en s'approchant de 0).
const COUNTDOWN_START_SCALES: Dictionary = {3: 1.4, 2: 1.7, 1: 2.1}
const COUNTDOWN_END_SCALE: float = 1.0

var _countdown_active: bool = false
var _countdown_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if resume_countdown:
		resume_countdown.process_mode = Node.PROCESS_MODE_ALWAYS
		resume_countdown.visible = false
	_apply_pause_menu_config()
	_apply_popup_style()
	_apply_button_styles()
	# Réappliquer la config pauseMenu après UIStyle pour que dimensions et polices du game.json gagnent (pas de contraintes en dur)
	_apply_pause_menu_config()
	hide()

func _get_game_config() -> Dictionary:
	if DataManager != null and DataManager.has_method("get_game_config"):
		return DataManager.get_game_config()
	var game_config: Dictionary = {}
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			game_config = json.data
	return game_config

func _apply_pause_menu_config() -> void:
	if not panel: return
	var game_config: Dictionary = _get_game_config()
	var cfg: Dictionary = game_config.get("pauseMenu", {})
	# Toujours appliquer avec des défauts (ne pas sortir si cfg vide) pour écraser les valeurs en dur de la scène
	var pw: int = int(cfg.get("panel_width", 380))
	var ph: int = int(cfg.get("panel_height", 360))
	panel.set_anchor(SIDE_LEFT, 0.5)
	panel.set_anchor(SIDE_TOP, 0.5)
	panel.set_anchor(SIDE_RIGHT, 0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.set_offset(SIDE_LEFT, -pw / 2.0)
	panel.set_offset(SIDE_RIGHT, pw / 2.0)
	panel.set_offset(SIDE_TOP, -ph / 2.0)
	panel.set_offset(SIDE_BOTTOM, ph / 2.0)
	panel.custom_minimum_size = Vector2(pw, ph)
	var margin_node: MarginContainer = panel.get_node_or_null("Margin") as MarginContainer
	if margin_node:
		var pm: int = int(cfg.get("panel_margin", 24))
		margin_node.add_theme_constant_override("margin_left", pm)
		margin_node.add_theme_constant_override("margin_top", pm)
		margin_node.add_theme_constant_override("margin_right", pm)
		margin_node.add_theme_constant_override("margin_bottom", pm)
	var vbox: VBoxContainer = panel.get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", int(cfg.get("separation", 18)))
	var title_label: Label = panel.get_node_or_null("Margin/VBox/Title") as Label
	if title_label:
		title_label.add_theme_font_size_override("font_size", int(cfg.get("title_font_size", 28)))
	if countdown_label:
		countdown_label.add_theme_font_size_override("font_size", int(cfg.get("countdown_font_size", 240)))
	var btn_font_sz: int = int(cfg.get("button_font_size", 22))
	var btn_w: int = int(cfg.get("button_min_width", 280))
	var btn_h: int = int(cfg.get("button_min_height", 56))
	var btn_max_w: int = int(cfg.get("button_max_width", 0))
	if btn_max_w > 0:
		btn_w = mini(btn_w, btn_max_w)
	for name in ["ResumeButton", "RestartButton", "LevelSelectButton", "QuitButton"]:
		var btn: Button = panel.get_node_or_null("Margin/VBox/" + name) as Button
		if btn:
			btn.add_theme_font_size_override("font_size", btn_font_sz)
			btn.custom_minimum_size = Vector2(btn_w, btn_h)
			if btn_max_w > 0:
				btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			else:
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _apply_popup_style() -> void:
	if not panel: return
	var game_config: Dictionary = _get_game_config()
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
	var cfg: Dictionary = _get_game_config().get("pauseMenu", {})
	var btn_w: int = int(cfg.get("button_min_width", 280))
	var btn_h: int = int(cfg.get("button_min_height", 56))
	var btn_max_w: int = int(cfg.get("button_max_width", 0))
	if btn_max_w > 0:
		btn_w = mini(btn_w, btn_max_w)
	for name in ["ResumeButton", "RestartButton", "LevelSelectButton", "QuitButton"]:
		var btn: Button = panel.get_node_or_null("Margin/VBox/" + name) as Button
		if btn:
			btn.custom_minimum_size = Vector2(btn_w, btn_h)
			if btn_max_w > 0:
				btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

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
	_start_resume_countdown()

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
	if event.is_action_pressed("ui_cancel") and visible and not _countdown_active:
		_start_resume_countdown()

# =============================================================================
# RESUME COUNTDOWN
# =============================================================================

func _start_resume_countdown() -> void:
	if _countdown_active:
		return
	_countdown_active = true
	if panel:
		panel.visible = false
	if overlay:
		var tw := overlay.create_tween()
		tw.tween_property(overlay, "color:a", 0.25, 0.15)
	if not resume_countdown or not countdown_label:
		_finish_resume_countdown()
		return
	resume_countdown.visible = true
	_play_countdown_sequence()

func _play_countdown_sequence() -> void:
	for n in COUNTDOWN_SEQUENCE:
		await _play_countdown_tick(n)
		if not _countdown_active:
			return
	_finish_resume_countdown()

func _play_countdown_tick(n: int) -> void:
	if not countdown_label:
		await get_tree().create_timer(COUNTDOWN_TICK_DURATION, true).timeout
		return
	# Kill le tween du tick precedent: sinon son fade-out continue d'ecrire modulate:a=0
	# pendant que ce tick essaie de l'afficher (ce qui faisait sauter le "2").
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	countdown_label.text = str(n)
	var start_scale: float = float(COUNTDOWN_START_SCALES.get(n, 1.6))
	# Le label a un custom_minimum_size fixe (cf .tscn): le pivot reste donc centre
	# et identique entre les chiffres -> le zoom part bien du centre du chiffre.
	countdown_label.pivot_offset = countdown_label.size * 0.5
	countdown_label.scale = Vector2.ONE * start_scale
	countdown_label.modulate.a = 1.0
	_countdown_tween = countdown_label.create_tween()
	_countdown_tween.set_parallel(true)
	_countdown_tween.tween_property(countdown_label, "scale", Vector2.ONE * COUNTDOWN_END_SCALE, COUNTDOWN_TICK_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade out sur la derniere partie du tick.
	var fade_duration: float = 0.25
	var fade_delay: float = maxf(0.0, COUNTDOWN_TICK_DURATION - fade_duration)
	_countdown_tween.tween_property(countdown_label, "modulate:a", 0.0, fade_duration).set_delay(fade_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(COUNTDOWN_TICK_DURATION, true).timeout

func _finish_resume_countdown() -> void:
	_countdown_active = false
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	if resume_countdown:
		resume_countdown.visible = false
	if countdown_label:
		countdown_label.scale = Vector2.ONE
		countdown_label.modulate.a = 1.0
	if overlay:
		overlay.color.a = 0.6
	if panel:
		panel.visible = true
	hide_menu()
	resume_requested.emit()
