extends Node2D

## IceShards — Éclats de glace quand un ennemi gelé est détruit (branche Frozen).
## Spawne des projectiles radiaux depuis la position de l'ennemi brisé.
## Note: Ce script est principalement géré par Projectile._spawn_ice_shards().
## Ce fichier est un placeholder si on veut ajouter un effet visuel d'explosion de glace.

var shard_count: int = 6
var shard_radius: float = 80.0
var shard_damage_pct: float = 0.5

func _ready() -> void:
	# Simple visual burst effect
	_create_burst_visual()
	
	# Auto-cleanup after animation
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

func _create_burst_visual() -> void:
	# Create radial ice particles
	for i in range(shard_count):
		var angle := (float(i) / float(shard_count)) * TAU
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(0, -4),
			Vector2(3, 0),
			Vector2(0, 4),
			Vector2(-3, 0)
		])
		shard.color = Color(0.53, 0.87, 1.0, 0.8)
		shard.position = Vector2(cos(angle), sin(angle)) * 5.0
		add_child(shard)
		
		# Animate outward
		var target_pos := Vector2(cos(angle), sin(angle)) * shard_radius
		var tween := create_tween()
		tween.tween_property(shard, "position", target_pos, 0.3).set_ease(Tween.EASE_OUT)
