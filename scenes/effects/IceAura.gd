extends Area2D

## IceAura — Aura de froid autour du joueur (branche Frozen, niveau 3+).
## Ralentit les ennemis proches automatiquement.

var aura_radius: float = 100.0
var slow_factor: float = 0.15
var _tick_timer: float = 0.0
const TICK_INTERVAL: float = 0.5

func setup(radius: float, slow: float) -> void:
	aura_radius = radius
	slow_factor = slow
	_update_shape()
	_update_visuals()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # Enemy layer
	
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = aura_radius
	col.shape = shape
	add_child(col)
	
	_update_visuals()

func _update_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			child.shape.radius = aura_radius

func _update_visuals() -> void:
	var old := get_node_or_null("AuraVisual")
	if old:
		old.queue_free()
	
	var visual := Polygon2D.new()
	visual.name = "AuraVisual"
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * aura_radius)
	visual.polygon = points
	visual.color = Color(0.5, 0.85, 1.0, 0.15)
	add_child(visual)

func _process(delta: float) -> void:
	# Follow player
	var player := get_parent()
	if player and player is CharacterBody2D:
		global_position = player.global_position
	
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_chill_aura()

func _apply_chill_aura() -> void:
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") and body.has_method("apply_status_effect"):
			var chill := StatusEffect.create_chill(slow_factor, 1)
			body.apply_status_effect(chill)
