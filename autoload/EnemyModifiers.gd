class_name EnemyModifiers
extends Node

## EnemyModifiers
## Factory static pour appliquer des modificateurs (Elites) aux ennemis.
## Charge les données depuis data/enemy_modifiers.json

static var _data: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded: return
	
	var file_path = "res://data/enemy_modifiers.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var text = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(text)
		if error == OK:
			_data = json.data
			#print("[EnemyModifiers] Loaded ", _data.size(), " modifiers.")
		else:
			push_error("[EnemyModifiers] JSON Parse Error: " + json.get_error_message())
	else:
		push_warning("[EnemyModifiers] File not found: " + file_path)
		
	_loaded = true

static func get_modifier(id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get(id, {})

static func apply_modifier(enemy: Node2D, modifier_id: String) -> void:
	if modifier_id == "": return
	
	var mod_data = get_modifier(modifier_id)
	if mod_data.is_empty():
		push_warning("[EnemyModifiers] Modifier not found: " + modifier_id)
		return
		
	#print("[EnemyModifiers] Applying ", modifier_id, " to ", enemy.name)
	var abilities = mod_data.get("abilities", [])
	
	# 1. Apply Stats
	var stats = mod_data.get("stats", {})
	if enemy.has_method("apply_stat_multipliers"):
		enemy.apply_stat_multipliers(stats)
		
	# 2. Apply Visuals
	var visuals = mod_data.get("visuals", {})
	
	# Scale
	var scale_mult = float(stats.get("scale", 1.0))
	if scale_mult != 1.0:
		enemy.scale *= scale_mult
		
	# Tint
	var tint = visuals.get("color_tint", "")
	if tint != "":
		if "suppressor_shield" not in abilities:
			enemy.modulate = Color(tint)
		
	# Aura (Background Effect)
	var aura_path = str(visuals.get("background_effect", ""))
	if aura_path != "":
		_attach_aura(enemy, aura_path)
		
	# Health Bar Frame
	var frame_path = str(visuals.get("health_bar_frame", ""))
	if frame_path != "" and enemy.has_method("set_health_bar_frame"):
		enemy.set_health_bar_frame(frame_path)
		
	# 3. Store loot bonus
	var quality_bonus = float(mod_data.get("loot_quality_bonus", 1.0))
	if enemy.get("loot_quality_multiplier") != null:
		enemy.loot_quality_multiplier = quality_bonus

	# 4. Abilities
	if "wall_spawner" in abilities:
		_attach_wall_spawner(enemy, mod_data)
	if "mine_spawner" in abilities and enemy.has_method("setup_minefreak"):
		enemy.setup_minefreak(mod_data)
	if "arcane_spawner" in abilities and enemy.has_method("setup_arcane_enchanted"):
		enemy.setup_arcane_enchanted(mod_data)
	if "gravity_spawner" in abilities and enemy.has_method("setup_graviton"):
		enemy.setup_graviton(mod_data)
	if "suppressor_shield" in abilities and enemy.has_method("setup_suppressor"):
		enemy.setup_suppressor(mod_data)

static func _attach_wall_spawner(enemy: Node2D, mod_data: Dictionary) -> void:
	var spawner_script = load("res://scenes/abilities/WallSpawner.gd")
	if not spawner_script: return
	
	var spawner = spawner_script.new()
	spawner.name = "WallSpawner"
	enemy.add_child(spawner)
	
	# Proper setup calls and respects the modifier config (interval, spacing, etc.)
	if spawner.has_method("setup"):
		spawner.setup(mod_data)
	
	spawner.set_process(true)

static func _attach_aura(enemy: Node2D, asset_path: String) -> void:
	# Check for Visual node (Enemy.gd) or general VisualContainer
	var container = enemy.get_node_or_null("Visual")
	if not container:
		container = enemy.get_node_or_null("VisualContainer")
	
	if not container:
		container = enemy # Fallback to root
		
	# Create Aura Sprite
	var aura = Sprite2D.new()
	aura.name = "EliteAura"
	aura.modulate.a = 0.5 # Semi-transparent
	
	# Load texture (or placeholder)
	if ResourceLoader.exists(asset_path):
		aura.texture = load(asset_path)
	else:
		# Placeholder: Circle
		# Use a simple GradientTexture2D or just let it fail gracefully?
		# Let's try to load a placeholder from standard assets if user hasn't provided one yet
		pass
		
	# Z-Index: Behind enemy (-1)
	aura.z_index = -1
	
	container.add_child(aura)
	# Animate Rotation
	var tween = enemy.create_tween().set_loops()
	tween.tween_property(aura, "rotation", TAU, 4.0).from(0.0)
