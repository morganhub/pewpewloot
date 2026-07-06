extends Control

## GameOverOverlay — Affiche "PERDU" puis déclenche le menu de pause après un délai.

signal animation_finished

@onready var label: Label = $Label

var _display_duration: float = 1.0

func set_display_duration(seconds: float) -> void:
	_display_duration = maxf(0.0, seconds)

func _ready() -> void:
	_apply_typography()
	# Animation simple: Fade in ?
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, _display_duration)
	tween.tween_callback(func(): animation_finished.emit())

func _apply_typography() -> void:
	if label == null:
		return
	var game_cfg: Dictionary = DataManager.get_game_config() if DataManager else {}
	var cfg_v: Variant = game_cfg.get("game_over_overlay", {})
	var cfg: Dictionary = cfg_v if cfg_v is Dictionary else {}
	label.add_theme_font_size_override("font_size", int(cfg.get("label_font_size", 64)))
