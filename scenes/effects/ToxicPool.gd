extends Area2D

## ToxicPool — Zone de dégâts persistante (branche Poison).
## Inflige des dégâts aux ennemis dans sa zone pendant sa durée.

var pool_radius: float = 50.0
var pool_duration: float = 3.0
var pool_dps: float = 8.0
var _elapsed: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = 0.5

func setup(radius: float, duration: float, dps: float) -> void:
	pool_radius = radius
	pool_duration = duration
	pool_dps = dps
	_update_visuals()

func _ready() -> void:
	# Collision setup: detect enemies
	collision_layer = 0
	collision_mask = 4  # Enemy layer
	
	# Create collision shape
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = pool_radius
	col.shape = shape
	add_child(col)
	
	# Visual
	_update_visuals()
	
	# Fade in
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.7, 0.2)

func _update_visuals() -> void:
	# Remove old visual if any
	var old := get_node_or_null("PoolVisual")
	if old:
		old.queue_free()
	
	# Draw a green translucent circle
	var visual := Polygon2D.new()
	visual.name = "PoolVisual"
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * pool_radius)
	visual.polygon = points
	visual.color = Color(0.2, 0.9, 0.1, 0.4)
	add_child(visual)

func _process(delta: float) -> void:
	_elapsed += delta
	_tick_timer += delta
	
	# Tick damage
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_damage()
	
	# Expire
	if _elapsed >= pool_duration:
		_fade_and_die()
		set_process(false)

func _apply_damage() -> void:
	var tick_damage := int(pool_dps * TICK_INTERVAL)
	if tick_damage < 1:
		tick_damage = 1
	
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(tick_damage)
		# Also apply poison status to enemies passing through
		if body.has_method("apply_status_effect"):
			var poison := StatusEffect.create_poison(float(tick_damage) * 2.0, 2.0)
			body.apply_status_effect(poison)

func _fade_and_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
