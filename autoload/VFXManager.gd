extends Node

## VFXManager — Gère les effets visuels (explosions, impacts, screen shake).
## Utilise des particles/animations placeholder en attendant les vrais assets.

# =============================================================================
# CAMERA SHAKE
# =============================================================================

var _camera: Camera2D = null
var _shake_amount: float = 0.0
var _shake_duration: float = 0.0

func set_camera(camera: Camera2D) -> void:
	_camera = camera

func screen_shake(intensity: float, duration: float) -> void:
	_shake_amount = intensity
	_shake_duration = duration

func _process(delta: float) -> void:
	if _shake_duration > 0:
		_shake_duration -= delta
		
		if _camera:
			_camera.offset = Vector2(
				randf_range(-_shake_amount, _shake_amount),
				randf_range(-_shake_amount, _shake_amount)
			)
		
		# Decay
		_shake_amount = lerp(_shake_amount, 0.0, delta * 5.0)
	elif _camera:
		_camera.offset = Vector2.ZERO

# =============================================================================
# EXPLOSION
# =============================================================================

func spawn_explosion(pos: Vector2, size: float, color: Color, container: Node2D) -> void:
	# TODO: Remplacer par AnimatedSprite2D avec spritesheet explosion
	# Pour le moment: cercle qui grandit et fade
	
	var explosion := Node2D.new()
	explosion.global_position = pos
	container.add_child(explosion)
	
	# Cercle visuel
	var circle := Polygon2D.new()
	circle.color = color
	circle.polygon = _create_circle(size)
	explosion.add_child(circle)
	
	# Animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(circle, "scale", Vector2(2.5, 2.5), 0.3)
	tween.tween_property(circle, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(explosion.queue_free)
	
	# Particles placeholder (points qui s'éloignent)
	for i in range(8):
		_spawn_particle(pos, size, color, container)

func _spawn_particle(pos: Vector2, size: float, color: Color, container: Node2D) -> void:
	var particle := Polygon2D.new()
	particle.global_position = pos
	particle.color = color
	particle.polygon = _create_circle(size / 3.0)
	container.add_child(particle)
	
	var direction := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance := randf_range(30, 60)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "global_position", pos + direction * distance, 0.4)
	tween.tween_property(particle, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(particle.queue_free)

# =============================================================================
# HIT FLASH
# =============================================================================

func flash_sprite(node: Node2D, flash_color: Color = Color.WHITE, duration: float = 0.1) -> void:
	# Trouver le Polygon2D ou Sprite2D
	var visual: Node = null
	for child in node.get_children():
		if child is Polygon2D or child is Sprite2D:
			visual = child
			break
	
	if not visual:
		return
	
	var original_color: Color = Color.WHITE
	if visual is Polygon2D:
		original_color = (visual as Polygon2D).color
		(visual as Polygon2D).color = flash_color
	elif visual is Sprite2D:
		original_color = (visual as Sprite2D).modulate
		(visual as Sprite2D).modulate = flash_color
	
	# Tween retour à la couleur originale
	var tween := create_tween()
	if visual is Polygon2D:
		tween.tween_property(visual, "color", original_color, duration)
	elif visual is Sprite2D:
		tween.tween_property(visual, "modulate", original_color, duration)

# =============================================================================
# IMPACT
# =============================================================================

func spawn_impact(pos: Vector2, size: float, container: Node2D) -> void:
	# Petit flash au point d'impact
	var impact := Polygon2D.new()
	impact.global_position = pos
	impact.color = Color.YELLOW
	impact.polygon = _create_circle(size)
	container.add_child(impact)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(impact, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_property(impact, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(impact.queue_free)

# =============================================================================
# FLOATING TEXT
# =============================================================================

func spawn_floating_text(pos: Vector2, text: String, color: Color, container: Node2D) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.global_position = pos + Vector2(-20, -20) # Centrer approximativement
	label.add_theme_font_size_override("font_size", 16)
	container.add_child(label)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 40, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)

# =============================================================================
# UTILITY
# =============================================================================

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 12
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
