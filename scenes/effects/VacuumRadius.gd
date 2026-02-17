extends Area2D

## VacuumRadius — Aspire les loot drops vers le joueur (branche Utility Loot).
## Attire les LootDrops dans un rayon étendu.

var vacuum_radius: float = 150.0

func setup(radius: float) -> void:
	vacuum_radius = radius
	_update_shape()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0  # We'll manually check overlaps
	
	# Visual hint (very subtle)
	var visual := Polygon2D.new()
	visual.name = "VacuumVisual"
	var points: PackedVector2Array = []
	var segments := 24
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * vacuum_radius)
	visual.polygon = points
	visual.color = Color(1.0, 1.0, 1.0, 0.05)
	add_child(visual)

func _update_shape() -> void:
	# No collision shape needed — we use distance checks from LootDrop
	pass

func _process(_delta: float) -> void:
	# Follow player
	var player := get_parent()
	if player and player is CharacterBody2D:
		global_position = player.global_position
