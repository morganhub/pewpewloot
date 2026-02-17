extends Area2D

## Singularity — Zone d'attraction gravitationnelle (branche Void).
## Attire les ennemis vers le centre et inflige des dégâts croissants.

var singularity_radius: float = 80.0
var singularity_duration: float = 1.0
var damage_base: float = 5.0
var damage_exponent: float = 2.0
var spaghettification: bool = false

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = 0.1

func setup(radius: float, duration: float, dmg_base: float, dmg_exp: float, has_spaghetti: bool = false) -> void:
	singularity_radius = radius
	singularity_duration = duration
	damage_base = dmg_base
	damage_exponent = dmg_exp
	spaghettification = has_spaghetti
	_update_visuals()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Enemy layer
	
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = singularity_radius
	col.shape = shape
	add_child(col)
	
	_update_visuals()
	
	# Dramatic entrance
	scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _update_visuals() -> void:
	var old := get_node_or_null("SingularityVisual")
	if old:
		old.queue_free()
	
	# Purple/void swirling circle
	var visual := Polygon2D.new()
	visual.name = "SingularityVisual"
	var points: PackedVector2Array = []
	var segments := 32
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * singularity_radius)
	visual.polygon = points
	visual.color = Color(0.4, 0.0, 0.8, 0.5)
	add_child(visual)
	
	# Inner core
	var core := Polygon2D.new()
	core.name = "Core"
	var core_points: PackedVector2Array = []
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		core_points.append(Vector2(cos(angle), sin(angle)) * (singularity_radius * 0.3))
	core.polygon = core_points
	core.color = Color(0.2, 0.0, 0.4, 0.8)
	add_child(core)

func _process(delta: float) -> void:
	_elapsed += delta
	_tick_timer += delta
	
	# Rotate visual
	var visual := get_node_or_null("SingularityVisual")
	if visual:
		visual.rotation += delta * 3.0
	
	# Tick
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_pull_and_damage()
	
	# Expire
	if _elapsed >= singularity_duration:
		_implode_and_die()
		set_process(false)

func _pull_and_damage() -> void:
	var time_ratio := _elapsed / singularity_duration
	# Damage increases over time: base * (1 + time_ratio)^exponent
	var current_damage := int(damage_base * pow(1.0 + time_ratio, damage_exponent))
	
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if not body.is_in_group("enemies"):
			continue
		
		# Pull toward center
		var dir_to_center := (global_position - body.global_position)
		var dist := dir_to_center.length()
		if dist > 5.0:
			var pull_force := dir_to_center.normalized() * 150.0 * (1.0 - (dist / singularity_radius))
			if body.has_method("apply_external_displacement"):
				body.apply_external_displacement(pull_force * TICK_INTERVAL)
			else:
				body.global_position += pull_force * TICK_INTERVAL
		
		# Damage
		if body.has_method("take_damage"):
			body.take_damage(current_damage)
		
		# Spaghettification: stretch enemy sprite toward center
		if spaghettification and dist < singularity_radius * 0.5:
			var stretch := 1.0 + (1.0 - dist / (singularity_radius * 0.5)) * 0.5
			body.scale = Vector2(1.0 / stretch, stretch)

func _implode_and_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(queue_free)
