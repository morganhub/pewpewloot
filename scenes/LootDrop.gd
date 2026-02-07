extends Area2D

## LootDrop — Item qui tombe et peut être collecté par le joueur.
## Représenté par une forme jaune (placeholder).

# =============================================================================
# PROPERTIES
# =============================================================================

var item_data: Dictionary = {}
var fall_speed: float = 100.0

@onready var visual: Polygon2D = $Visual

# =============================================================================
# LIFECYCLE
# =============================================================================

func setup(loot_item: Dictionary, pos: Vector2) -> void:
	item_data = loot_item
	global_position = pos
	
	# Visuel placeholder (diamant jaune)
	visual.color = Color.YELLOW
	var size := 15.0
	visual.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(size, 0),
		Vector2(0, size),
		Vector2(-size, 0)
	])
	
	# TODO: Remplacer par sprite de l'item selon rarity
	# var rarity := str(item_data.get("rarity", "common"))
	# visual.texture = load("res://assets/items/" + item_data.get("id", "unknown") + ".png")
	
	# Connecter signaux
	# Layer 4 (Loot), Mask 2 (Player)
	collision_layer = 4
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	
	# Animation de pulsation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(visual, "scale", Vector2(1.2, 1.2), 0.5)
	tween.tween_property(visual, "scale", Vector2(1.0, 1.0), 0.5)

func _process(delta: float) -> void:
	# Tombe lentement
	global_position.y += fall_speed * delta
	
	# Destruction si hors écran
	if global_position.y > get_viewport_rect().size.y + 50:
		queue_free()

# =============================================================================
# COLLECTION
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_collect()

func _collect() -> void:
	print("[LootDrop] Collected: ", item_data.get("name", "Item"))
	
	if item_data.get("type") == "powerup":
		# Power Up Logic
		var effect = item_data.get("effect", "")
		if effect == "fire_rate":
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("add_fire_rate_boost"):
				player.add_fire_rate_boost(10.0)
	else:
		# Item d'inventaire
		ProfileManager.add_item_to_inventory(item_data)
	
	# VFX de collection
	if visual:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector2(2.0, 2.0), 0.2)
		tween.tween_property(visual, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(queue_free)
