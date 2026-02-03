extends Control

## GameOverOverlay — Affiche "PERDU" puis déclenche le menu de pause après un délai.

signal animation_finished

func _ready() -> void:
	# Animation simple: Fade in ?
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)
	tween.tween_callback(func(): animation_finished.emit())
