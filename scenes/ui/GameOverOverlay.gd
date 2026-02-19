extends Control

## GameOverOverlay — Affiche "PERDU" puis déclenche le menu de pause après un délai.

signal animation_finished

var _display_duration: float = 1.0

func set_display_duration(seconds: float) -> void:
	_display_duration = maxf(0.0, seconds)

func _ready() -> void:
	# Animation simple: Fade in ?
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, _display_duration)
	tween.tween_callback(func(): animation_finished.emit())
