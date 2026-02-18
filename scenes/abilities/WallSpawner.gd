class_name WallSpawner
extends Node2D

var spawn_timer: float = 0.0
var spawn_interval: float = 5.0
var wall_asset_path: String = ""

# Wall scene to instantiate
# Since we created Wall.tscn, we can load it
const WALL_SCENE = preload("res://scenes/abilities/objects/Wall.tscn")

func _ready() -> void:
	# Random start delay
	spawn_timer = randf_range(0.0, 2.0)

var config: Dictionary = {}
var ability_id: String = "wall_spawner"

func setup(p_config: Dictionary) -> void:
	config = p_config
	# Override specific defaults if needed, but Manager handles defaults too
	wall_asset_path = str(config.get("ability_asset", ""))
	if wall_asset_path == "":
		var visuals = config.get("visuals", {})
		wall_asset_path = str(visuals.get("ability_asset", ""))
	
	# Initial delay randomization to desync enemies
	spawn_timer = randf_range(0.0, float(config.get("spawn_interval", 3.0)))

func _process(delta: float) -> void:
	spawn_timer += delta
	# Check local timer (minimal frequency per enemy, though manager overrides global)
	# Actually, if we rely on Manager for global frequency, local timer is just "retry rate".
	# If we are ready, we ask Manager.
	if spawn_timer >= 0.5: # Try every 0.5s or frame? 
		# If we try every frame, the first enemy in processing order always wins.
		# Randomize retry?
		pass
	
	# Let's say we try to spawn based on interval config, but Manager can deny.
	# If denied, we retry soon?
	var interval = float(config.get("spawn_interval", 3.0))
	if spawn_timer >= interval:
		if _try_spawn_wall():
			spawn_timer = 0.0 # Reset on success
		else:
			spawn_timer = interval - 0.2 # Retry shortly
			# Or keep at interval to valid "ready" state logic.
			
func _try_spawn_wall() -> bool:
	var viewport_size = get_viewport_rect().size
	# Proposed X (Random)
	var x = randf_range(50, viewport_size.x - 50)
	var proposed_pos = Vector2(x, -50)
	
	if EnemyAbilityManager.can_spawn(ability_id, config, proposed_pos):
		print("[WallSpawner] Spawning wall at ", proposed_pos)
		_spawn_wall_at(proposed_pos)
		return true
	return false

func _spawn_wall_at(pos: Vector2) -> void:
	var wall = WALL_SCENE.instantiate()
	wall.global_position = pos
	
	# Pass SFX path
	var visuals = config.get("visuals", {})
	wall.contact_sfx_path = str(visuals.get("contact_sfx", ""))
	
	# Apply visual if provided
	if wall_asset_path != "" and ResourceLoader.exists(wall_asset_path):
		var sprite = wall.get_node_or_null("Sprite2D")
		var col = wall.get_node_or_null("CollisionShape2D")
		if sprite:
			var tex = load(wall_asset_path)
			sprite.texture = tex
			# Disable region crop from placeholder
			sprite.region_enabled = false
			
			if col and col.shape is RectangleShape2D:
				col.shape = col.shape.duplicate()
				var target_size: Vector2 = col.shape.size # Garder la taille de collision d'origine
				var tex_size: Vector2 = tex.get_size()
				
				# Stretch : on scale le sprite pour couvrir exactement la hitbox
				if tex_size.x > 0 and tex_size.y > 0:
					sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)
				
				# Aussi mettre à jour la DetectionArea pour rester synchronisée
				var area = wall.get_node_or_null("DetectionArea/CollisionShape2D")
				if area and area.shape is RectangleShape2D:
					area.shape = area.shape.duplicate()
					area.shape.size = target_size
	
	# Add to Game Layer (not as child of Enemy/Spawner, but sibling/root)
	# So it persists/moves independently?
	# "descendront" - handled by Wall.gd
	# Start pos is top.
	# Add to "GameLayer" usually.
	# Try to find GameLayer via group or parent chain.
	# Enemy is usually child of GameLayer.
	var parent = get_parent() # Enemy
	if parent:
		var game_layer = parent.get_parent()
		if game_layer:
			game_layer.add_child(wall)
		else:
			get_tree().root.add_child(wall) # Fallback
	else:
		get_tree().root.add_child(wall)
		
	# Register with Manager
	EnemyAbilityManager.register_spawn(ability_id, wall, config)

