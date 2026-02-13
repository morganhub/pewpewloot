class_name EnemyAbilityManager
extends Node

## EnemyAbilityManager
## Gère les cooldowns partagés et les limites de spawn pour les compétences d'ennemis.
## Empêche le spam d'obstacles/projectiles si beaucoup d'élites sont présents.

static var _next_spawn_times: Dictionary = {} # { "ability_id": next_allowed_time_msec }
static var _active_instances: Dictionary = {} # { "ability_id": [node, ...] }
static var next_mine_spawn_time: int = 0
static var next_arcane_spawn_time: int = 0
static var next_graviton_spawn_time: int = 0

const DEFAULT_COOLDOWN: float = 2.0
const MIN_SPACING_X: float = 100.0
const MIN_SPACING_Y: float = 100.0

static func reset() -> void:
	_next_spawn_times.clear()
	_active_instances.clear()
	next_mine_spawn_time = 0
	next_arcane_spawn_time = 0
	next_graviton_spawn_time = 0

static func can_spawn(ability_id: String, config: Dictionary, desired_pos: Vector2) -> bool:
	if ability_id == "mine_spawner":
		return can_spawn_mine(config, desired_pos)
	if ability_id == "arcane_spawner":
		return can_spawn_arcane(config)
	if ability_id == "gravity_spawner":
		return can_spawn_graviton(config, desired_pos)
	
	var resolved_config := _resolve_spawn_config(config)
	var current_time = Time.get_ticks_msec()
	
	# 1. Check Cooldown Global
	if current_time < _next_spawn_times.get(ability_id, 0):
		return false
		
	# 2. Check Max Count
	var max_count = int(resolved_config.get("max_per_screen", 5))
	var current_instances = _get_active_instances(ability_id)
	if current_instances.size() >= max_count:
		return false
		
	# 3. Check Minimum Spacing
	var min_spacing_x = float(resolved_config.get("minimum_spacing_x", MIN_SPACING_X))
	var min_spacing_y = float(resolved_config.get("minimum_spacing_y", MIN_SPACING_Y))
	
	for inst in current_instances:
		var dist_x = abs(inst.global_position.x - desired_pos.x)
		var dist_y = abs(inst.global_position.y - desired_pos.y)
		
		if dist_y < min_spacing_y and dist_x < min_spacing_x:
			return false
	
	return true

static func can_spawn_mine(config: Dictionary, desired_pos: Vector2) -> bool:
	var current_time = Time.get_ticks_msec()
	var resolved_config := _resolve_spawn_config(config)
	
	if current_time < next_mine_spawn_time:
		return false
	
	var mines := _get_group_nodes("mines")
	var max_per_screen := int(resolved_config.get("max_per_screen", 6))
	if mines.size() >= max_per_screen:
		return false
	
	var min_spacing_x := float(resolved_config.get("minimum_spacing_x", MIN_SPACING_X))
	var min_spacing_y := float(resolved_config.get("minimum_spacing_y", MIN_SPACING_Y))
	
	for mine in mines:
		if not (mine is Node2D):
			continue
		var mine_node := mine as Node2D
		var dist_x := absf(mine_node.global_position.x - desired_pos.x)
		var dist_y := absf(mine_node.global_position.y - desired_pos.y)
		if dist_x < min_spacing_x and dist_y < min_spacing_y:
			return false
	
	return true

static func can_spawn_arcane(config: Dictionary) -> bool:
	var current_time = Time.get_ticks_msec()
	var resolved_config := _resolve_spawn_config(config)
	
	if current_time < next_arcane_spawn_time:
		return false
	
	var arcane_orbs := _get_group_nodes("arcane_orbs")
	var max_per_screen := int(resolved_config.get("max_per_screen", 3))
	if arcane_orbs.size() >= max_per_screen:
		return false
	
	return true

static func can_spawn_graviton(config: Dictionary, desired_pos: Vector2) -> bool:
	var current_time = Time.get_ticks_msec()
	var resolved_config := _resolve_spawn_config(config)
	
	if current_time < next_graviton_spawn_time:
		return false
	
	var wells := _get_group_nodes("gravity_wells")
	var max_per_screen := int(resolved_config.get("max_per_screen", 2))
	if wells.size() >= max_per_screen:
		return false
	
	var min_spacing_x := float(resolved_config.get("minimum_spacing_x", 150.0))
	for well in wells:
		if not (well is Node2D):
			continue
		var x_dist := absf((well as Node2D).global_position.x - desired_pos.x)
		if x_dist < min_spacing_x:
			return false
	
	return true

static func register_spawn(ability_id: String, instance: Node2D, config: Dictionary) -> void:
	var resolved_config := _resolve_spawn_config(config)
	
	# Set Cooldown
	var interval_sec = float(resolved_config.get("spawn_interval", DEFAULT_COOLDOWN))
	var current_time = Time.get_ticks_msec()
	var next_allowed = current_time + int(interval_sec * 1000.0)
	_next_spawn_times[ability_id] = next_allowed
	if ability_id == "mine_spawner":
		next_mine_spawn_time = next_allowed
	if ability_id == "arcane_spawner":
		next_arcane_spawn_time = next_allowed
	if ability_id == "gravity_spawner":
		next_graviton_spawn_time = next_allowed
	
	# Track Instance
	if not _active_instances.has(ability_id):
		_active_instances[ability_id] = []
	_active_instances[ability_id].append(instance)

static func _get_active_instances(ability_id: String) -> Array:
	if not _active_instances.has(ability_id):
		return []
	
	# Clean up invalid refs
	var valid = []
	for inst in _active_instances[ability_id]:
		if is_instance_valid(inst):
			valid.append(inst)
	_active_instances[ability_id] = valid
	return valid

static func _resolve_spawn_config(config: Dictionary) -> Dictionary:
	var ability_cfg = config.get("ability_config", {})
	if ability_cfg is Dictionary and not (ability_cfg as Dictionary).is_empty():
		return ability_cfg as Dictionary
	return config

static func _get_group_nodes(group_name: String) -> Array:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).get_nodes_in_group(group_name)
	return []
