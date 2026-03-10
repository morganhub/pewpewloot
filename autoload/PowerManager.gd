extends Node

## PowerManager — Gère l'exécution des super pouvoirs et pouvoirs uniques.
## Gère l'invincibilité, les mouvements cinématiques et les patterns de tirs spéciaux.

const BOSS_VOID_ZONE := preload("res://scenes/effects/BossVoidZone.gd")
const BOSS_LASER_ZONE := preload("res://scenes/effects/BossLaserZone.gd")
const STRONG_RESOURCE_CACHE_MAX: int = 256
const DEFAULT_PLAYER_POWER_PROJECTILE_SPEED: float = 400.0
const DEFAULT_BOSS_POWER_PROJECTILE_SPEED: float = 400.0
const DEFAULT_PLAYER_POWER_PROJECTILE_DAMAGE: int = 50
const DEFAULT_BOSS_POWER_PROJECTILE_DAMAGE: int = 20
const TARGETING_VIEW_MARGIN: float = 96.0
static var _strong_resource_cache: Dictionary = {} # path -> Resource

func _ready() -> void:
	call_deferred("_warmup_all_power_assets")

func execute_power(power_id: String, source: Node2D) -> void:
	var data := DataManager.get_power(power_id)
	if data.is_empty():
		push_warning("[PowerManager] Power not found: " + power_id)
		return
	_cache_power_resources(data)
	
	print("[PowerManager] Executing power: ", data.get("name", power_id), " on ", source.name)
	
	var duration: float = float(data.get("duration", 2.0))
	var invincibility: bool = bool(data.get("invincibility", false))
	
	# Feedback Visuel
	VFXManager.flash_sprite(source, Color.WHITE, 0.2)
	VFXManager.spawn_floating_text(source.global_position, "POWER ACTIVE!", Color.ORANGE, get_tree().root)

	# 0. Flag d'exécution
	if "_is_executing_power" in source:
		source.set("_is_executing_power", true)
		get_tree().create_timer(duration).timeout.connect(func():
			if is_instance_valid(source) and "_is_executing_power" in source:
				source.set("_is_executing_power", false)
		)

	# 1. Invincibilité
	if invincibility and source.has_method("set_invincible"):
		source.set_invincible(true)
		# Timer pour désactiver
		get_tree().create_timer(duration).timeout.connect(func():
			if is_instance_valid(source) and source.has_method("set_invincible"):
				source.set_invincible(false)
		)
	
	# 2. Mouvement du vaisseau
	var move_data: Variant = data.get("ship_movement", null)
	if move_data is Dictionary:
		_handle_movement(source, move_data as Dictionary, duration)
	
	# 3. Projectiles
	var proj_data: Variant = data.get("projectile", null)
	if proj_data is Dictionary:
		_handle_projectiles(source, proj_data as Dictionary)

	# 4. Hazards (boss-only): void zones, lasers, etc.
	var hazard_data: Variant = data.get("hazard", null)
	if hazard_data is Dictionary:
		_handle_hazard(source, hazard_data as Dictionary, duration)

	var hazards_data: Variant = data.get("hazards", null)
	if hazards_data is Array:
		for entry in (hazards_data as Array):
			if entry is Dictionary:
				_handle_hazard(source, entry as Dictionary, duration)

func _extract_targeting_data(data: Dictionary) -> Dictionary:
	var targeting_variant: Variant = data.get("targeting", {})
	if targeting_variant is Dictionary:
		return (targeting_variant as Dictionary).duplicate(true)
	return {}

func _resolve_power_target(source: Node2D, targeting_data: Dictionary = {}) -> Node2D:
	if not is_instance_valid(source):
		return null
	if not source.is_in_group("player"):
		var player_node := source.get_tree().get_first_node_in_group("player")
		return player_node as Node2D if player_node is Node2D else null

	var require_on_screen: bool = bool(targeting_data.get("require_on_screen", true))
	var prioritize_boss: bool = bool(targeting_data.get("prioritize_boss", true))
	var viewport_rect := Rect2(Vector2.ZERO, source.get_viewport_rect().size).grow(TARGETING_VIEW_MARGIN)
	var best_target: Node2D = null
	var best_distance: float = INF

	for candidate_variant in source.get_tree().get_nodes_in_group("enemies"):
		if not (candidate_variant is Node2D):
			continue
		var candidate := candidate_variant as Node2D
		if not is_instance_valid(candidate):
			continue
		if require_on_screen and not viewport_rect.has_point(candidate.global_position):
			continue
		if prioritize_boss and candidate.is_in_group("boss"):
			return candidate
		var distance_to_source: float = source.global_position.distance_to(candidate.global_position)
		if distance_to_source < best_distance:
			best_distance = distance_to_source
			best_target = candidate

	return best_target

func _get_target_direction(from_position: Vector2, target_node: Node2D, fallback: Vector2) -> Vector2:
	if target_node and is_instance_valid(target_node):
		var to_target: Vector2 = (target_node.global_position - from_position).normalized()
		if to_target != Vector2.ZERO:
			return to_target
	return fallback

func _handle_hazard(source: Node2D, hazard_data: Dictionary, default_duration: float) -> void:
	if not is_instance_valid(source):
		return

	var resolved_hazard_data: Dictionary = hazard_data.duplicate(true)
	var targeting_data: Dictionary = _extract_targeting_data(resolved_hazard_data)
	var resolved_target: Node2D = _resolve_power_target(source, targeting_data)
	if resolved_target:
		resolved_hazard_data["target_node"] = resolved_target
	if not resolved_hazard_data.has("damage_target_group"):
		resolved_hazard_data["damage_target_group"] = "enemies" if source.is_in_group("player") else "player"

	var hazard_type: String = str(resolved_hazard_data.get("type", ""))
	if hazard_type == "":
		return

	var container: Node = source.get_parent()
	if container == null:
		container = get_tree().root

	match hazard_type:
		"void_zone":
			var zone_node: Variant = BOSS_VOID_ZONE.new()
			if zone_node is Area2D:
				var zone := zone_node as Area2D
				container.add_child(zone)
				zone.global_position = source.global_position
				if zone.has_method("setup"):
					zone.call("setup", source, resolved_hazard_data, default_duration)

		"laser_line", "laser_cone":
			var laser_data := resolved_hazard_data.duplicate(true)
			if hazard_type == "laser_line":
				laser_data["mode"] = "line"
			else:
				laser_data["mode"] = "cone"

			var laser_node: Variant = BOSS_LASER_ZONE.new()
			if laser_node is Area2D:
				var laser := laser_node as Area2D
				container.add_child(laser)
				laser.global_position = source.global_position
				if laser.has_method("setup"):
					laser.call("setup", source, laser_data, default_duration)

		_:
			push_warning("[PowerManager] Unknown hazard type: " + hazard_type)

func _handle_movement(source: Node2D, move_data: Dictionary, duration: float) -> void:
	var type: String = str(move_data.get("type", ""))
	var _speed: float = float(move_data.get("speed", 300))
	var dist_pct: float = float(move_data.get("distance_pct", 50))
	
	var viewport_size := source.get_viewport_rect().size
	var tween := source.create_tween()
	var start_pos := source.global_position
	
	match type:
		"horizontal_sweep":
			# Aller au bord gauche puis balayer vers la droite (ou inverse)
			var left_x = viewport_size.x * 0.1
			var right_x = viewport_size.x * 0.9
			tween.tween_property(source, "global_position:x", left_x, duration * 0.2)
			tween.tween_property(source, "global_position:x", right_x, duration * 0.6)
			tween.tween_property(source, "global_position:x", start_pos.x, duration * 0.2)
			
		"horizontal_dodge":
			# Tonneau rapide latéral
			var offset = viewport_size.x * (dist_pct / 100.0)
			if start_pos.x > viewport_size.x / 2: offset *= -1 # Aller vers le centre
			tween.tween_property(source, "global_position:x", start_pos.x + offset, duration * 0.5).set_trans(Tween.TRANS_SINE)
			tween.tween_property(source, "global_position:x", start_pos.x, duration * 0.5).set_trans(Tween.TRANS_SINE)
			
		"spin_center":
			# Aller au centre et tourner
			var center = Vector2(viewport_size.x / 2, viewport_size.y * 0.3)
			tween.tween_property(source, "global_position", center, duration * 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tween.tween_property(source, "rotation_degrees", 360.0, duration * 0.6)
			tween.tween_property(source, "global_position", start_pos, duration * 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(source, "rotation_degrees", 0.0, duration * 0.2)
			
		"dash_forward":
			# Dash vers le bas puis remonte
			var target_y = start_pos.y + 200
			tween.tween_property(source, "global_position:y", target_y, duration * 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			tween.tween_property(source, "global_position:y", start_pos.y, duration * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			# Rotation visuals handled by VFX? Or rotate source? 
			# Vaut mieux éviter de rotate le CharacterBody2D car ça casse les contrôles inputs (axis).
			# On suppose que c'est visuel seulement, ou on laisse tel quel.
			
		_:
			pass

func _handle_projectiles(source: Node2D, proj_data: Dictionary) -> void:
	var waves: int = maxi(1, int(proj_data.get("waves", 1)))
	var wave_delay: float = maxf(0.0, float(proj_data.get("wave_delay", 0.2)))
	var count: int = maxi(1, int(proj_data.get("count", 10)))
	var trajectory: String = str(proj_data.get("trajectory", "radial"))
	var safe_zones: Variant = proj_data.get("safe_zones", null)
	var aim_target: bool = bool(proj_data.get("aim_target", false))
	var homing_turn_rate: float = float(proj_data.get("homing_turn_rate", 3.0))
	var homing_duration: float = float(proj_data.get("homing_duration", -1.0))
	var max_lifetime: float = maxf(0.1, float(proj_data.get("despawn_after_sec", proj_data.get("max_lifetime", 20.0))))
	var acceleration: float = float(proj_data.get("acceleration", 0.0))
	var rotation_speed: float = float(proj_data.get("rotation_speed", 90.0))
	var is_player_source: bool = source.is_in_group("player")
	var default_speed: float = DEFAULT_PLAYER_POWER_PROJECTILE_SPEED if is_player_source else DEFAULT_BOSS_POWER_PROJECTILE_SPEED
	var default_damage: int = DEFAULT_PLAYER_POWER_PROJECTILE_DAMAGE if is_player_source else DEFAULT_BOSS_POWER_PROJECTILE_DAMAGE
	var projectile_speed: float = maxf(1.0, float(proj_data.get("speed", default_speed)))
	var projectile_damage: int = maxi(1, int(round(float(proj_data.get("damage", default_damage)))))
	var targeting_data: Dictionary = _extract_targeting_data(proj_data)
	if targeting_data.is_empty() and bool(proj_data.get("aim_target", false)):
		targeting_data = {"mode": "single_target", "prioritize_boss": true, "require_on_screen": true} if is_player_source else {"mode": "player"}
	elif targeting_data.is_empty() and is_player_source and count == 1:
		targeting_data = {"mode": "single_target", "prioritize_boss": true, "require_on_screen": true}
	var resolved_target: Node2D = _resolve_power_target(source, targeting_data)
	var visual_data: Dictionary = _build_power_projectile_visual_data(proj_data)
	var explosion_data: Dictionary = _build_power_projectile_explosion_data(proj_data)
	if trajectory == "homing" and homing_duration < 0.0 and not is_player_source:
		homing_duration = 1.5
	
	var pattern: Dictionary = {
		"trajectory": trajectory,
		"aim_target": aim_target,
		"max_lifetime": max_lifetime,
		"despawn_after_sec": max_lifetime,
		"acceleration": acceleration,
		"rotation_speed": rotation_speed,
		"visual_data": visual_data
	}
	if not explosion_data.is_empty():
		pattern["explosion_data"] = explosion_data
	if trajectory == "homing":
		pattern["homing_turn_rate"] = homing_turn_rate
		if homing_duration >= 0.0:
			pattern["homing_duration"] = homing_duration
	
	for i in range(waves):
		call_deferred("_spawn_wave", source, count, pattern, trajectory, projectile_speed, projectile_damage, safe_zones, resolved_target)
		await source.get_tree().create_timer(wave_delay).timeout
		if not is_instance_valid(source): return

func _spawn_wave(
	source: Node2D,
	count: int,
	pattern: Dictionary,
	trajectory: String,
	projectile_speed: float,
	projectile_damage: int,
	safe_zones: Variant = null,
	target_node: Node2D = null
) -> void:
	if not is_instance_valid(source): return
	
	var center := source.global_position
	var is_player := source.is_in_group("player")
	var fallback_direction: Vector2 = Vector2.UP if is_player else Vector2.DOWN
	var target_direction: Vector2 = _get_target_direction(center, target_node, fallback_direction)
	
	if trajectory == "radial":
		# Safe Zones Calculation
		var safe_angles: Array = [] # List of [start_rad, end_rad]
		if safe_zones is Dictionary:
			var zone_count: int = int(safe_zones.get("count", 1))
			var zone_width: float = deg_to_rad(float(safe_zones.get("width_degrees", 20)))
			
			for k in range(zone_count):
				# Random center for the safe zone
				var angle_center := randf() * TAU
				var start := angle_center - (zone_width / 2.0)
				var end := angle_center + (zone_width / 2.0)
				safe_angles.append([start, end])

		for j in range(count):
			var angle := (j / float(count)) * TAU
			
			# Check against safe zones
			var skip := false
			for zone in safe_angles:
				# Normalize angle checks (handles wrapping)
				var a = fposmod(angle, TAU)
				var s = fposmod(zone[0], TAU)
				var e = fposmod(zone[1], TAU)
				
				# Simple range check handling wrap-around
				if s < e:
					if a >= s and a <= e: skip = true
				else: # Wrap around case (e.g. 350 to 10 degrees)
					if a >= s or a <= e: skip = true
				if skip: break
			
			if skip: continue

			var dir := target_direction.rotated(angle)
			_spawn(center, dir, is_player, pattern, projectile_speed, projectile_damage)
			
	elif trajectory == "rain_down":
		var viewport_width := source.get_viewport_rect().size.x
		for j in range(count):
			var x := randf_range(0, viewport_width)
			var start := Vector2(x, -50)
			var dir := Vector2.DOWN
			_spawn(start, dir, is_player, pattern, projectile_speed, projectile_damage)
			
	elif trajectory == "spiral":
		for j in range(count):
			var angle := (j / float(count)) * TAU
			var dir := target_direction.rotated(angle)
			_spawn(center, dir, is_player, pattern, projectile_speed, projectile_damage)
			
	else:
		# Default burst
		for j in range(count):
			var dir := target_direction if target_node and is_instance_valid(target_node) else fallback_direction.rotated(randf_range(-0.5, 0.5))
			_spawn(center, dir, is_player, pattern, projectile_speed, projectile_damage)

func _spawn(
	pos: Vector2,
	dir: Vector2,
	is_player: bool,
	pattern: Dictionary,
	projectile_speed: float,
	projectile_damage: int
) -> void:
	if is_player:
		ProjectileManager.spawn_player_projectile(pos, dir, projectile_speed, projectile_damage, pattern, true)
	else:
		ProjectileManager.spawn_enemy_projectile(pos, dir, projectile_speed, projectile_damage, pattern)

func _build_power_projectile_visual_data(proj_data: Dictionary) -> Dictionary:
	var visual_data: Dictionary = {}
	var missile_data: Dictionary = _get_power_missile_data(proj_data)
	var missile_visual_variant: Variant = missile_data.get("visual", {})
	if missile_visual_variant is Dictionary:
		visual_data = (missile_visual_variant as Dictionary).duplicate(true)

	var explicit_visual_variant: Variant = proj_data.get("visual", {})
	if explicit_visual_variant is Dictionary:
		visual_data.merge(explicit_visual_variant as Dictionary, true)

	if proj_data.has("size"):
		visual_data["size"] = float(proj_data.get("size", 20.0))
	if proj_data.has("width_pct"):
		visual_data["width_pct"] = float(proj_data.get("width_pct", 0.0))
	if proj_data.has("height_pct"):
		visual_data["height_pct"] = float(proj_data.get("height_pct", 0.0))
	if proj_data.has("color"):
		visual_data["color"] = str(proj_data.get("color", "#FFFF00"))
	if proj_data.has("shape"):
		visual_data["shape"] = str(proj_data.get("shape", "circle"))
	if proj_data.has("asset"):
		visual_data["asset"] = str(proj_data.get("asset", ""))
	if proj_data.has("asset_anim"):
		visual_data["asset_anim"] = str(proj_data.get("asset_anim", ""))
	if proj_data.has("asset_anim_duration"):
		visual_data["asset_anim_duration"] = float(proj_data.get("asset_anim_duration", 0.0))
	if proj_data.has("asset_anim_loop"):
		visual_data["asset_anim_loop"] = bool(proj_data.get("asset_anim_loop", true))
	if proj_data.has("asset_duration"):
		visual_data["asset_duration"] = float(proj_data.get("asset_duration", 0.0))
	if proj_data.has("asset_loop"):
		visual_data["asset_loop"] = bool(proj_data.get("asset_loop", true))
	if proj_data.has("pulsating"):
		visual_data["pulsating"] = bool(proj_data.get("pulsating", false))
	if proj_data.has("pulsating_size"):
		visual_data["pulsating_size"] = float(proj_data.get("pulsating_size", 1.0))
	if proj_data.has("pulsating_frequency"):
		visual_data["pulsating_frequency"] = float(proj_data.get("pulsating_frequency", 1.0))

	if not visual_data.has("color"):
		visual_data["color"] = "#FFFF00"
	if not visual_data.has("shape"):
		visual_data["shape"] = "circle"
	if not visual_data.has("size") and not (visual_data.has("width_pct") and visual_data.has("height_pct")):
		visual_data["size"] = 20.0

	return visual_data

func _build_power_projectile_explosion_data(proj_data: Dictionary) -> Dictionary:
	var explosion_data: Dictionary = {}
	var explicit_explosion_variant: Variant = proj_data.get("explosion", {})
	if explicit_explosion_variant is Dictionary and not (explicit_explosion_variant as Dictionary).is_empty():
		explosion_data = (explicit_explosion_variant as Dictionary).duplicate(true)

	if explosion_data.is_empty():
		var missile_data: Dictionary = _get_power_missile_data(proj_data)
		var missile_explosion_variant: Variant = missile_data.get("explosion", {})
		if missile_explosion_variant is Dictionary and not (missile_explosion_variant as Dictionary).is_empty():
			explosion_data = (missile_explosion_variant as Dictionary).duplicate(true)

	if explosion_data.is_empty():
		explosion_data = DataManager.get_default_explosion()

	return explosion_data

func _get_power_missile_data(proj_data: Dictionary) -> Dictionary:
	var missile_id: String = str(proj_data.get("missile_id", "")).strip_edges()
	if missile_id == "":
		return {}
	return DataManager.get_missile(missile_id)

func _warmup_all_power_assets() -> void:
	var all_powers: Array = []
	if DataManager and DataManager.has_method("get_all_super_powers"):
		all_powers.append_array(DataManager.get_all_super_powers())
	if DataManager and DataManager.has_method("get_all_unique_powers"):
		all_powers.append_array(DataManager.get_all_unique_powers())
	if DataManager and DataManager.has_method("get_all_boss_powers"):
		all_powers.append_array(DataManager.get_all_boss_powers())

	for power_variant in all_powers:
		if power_variant is Dictionary:
			_cache_power_resources(power_variant as Dictionary)

func _cache_power_resources(power_data: Dictionary) -> void:
	var paths: Array = []
	var seen: Dictionary = {}

	var projectile_variant: Variant = power_data.get("projectile", null)
	if projectile_variant is Dictionary:
		var projectile_data: Dictionary = projectile_variant as Dictionary
		_collect_resource_paths_recursive(projectile_data, paths, seen)
		var missile_data: Dictionary = _get_power_missile_data(projectile_data)
		if not missile_data.is_empty():
			_collect_resource_paths_recursive(missile_data.get("visual", {}), paths, seen)
			_collect_resource_paths_recursive(missile_data.get("explosion", {}), paths, seen)

	_collect_resource_paths_recursive(power_data.get("hazard", null), paths, seen)
	_collect_resource_paths_recursive(power_data.get("hazards", null), paths, seen)

	for path_variant in paths:
		_load_cached_resource(str(path_variant))

func _collect_resource_paths_recursive(value: Variant, out_paths: Array, seen: Dictionary) -> void:
	if value is Dictionary:
		for nested_value in (value as Dictionary).values():
			_collect_resource_paths_recursive(nested_value, out_paths, seen)
		return

	if value is Array:
		for nested_entry in (value as Array):
			_collect_resource_paths_recursive(nested_entry, out_paths, seen)
		return

	if not (value is String):
		return
	var path: String = str(value).strip_edges()
	if path == "" or not path.begins_with("res://"):
		return
	if seen.has(path):
		return
	seen[path] = true
	out_paths.append(path)

func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _strong_resource_cache.has(path):
		var cached: Variant = _strong_resource_cache[path]
		if cached is Resource:
			return cached as Resource

	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource != null:
		if _strong_resource_cache.size() >= STRONG_RESOURCE_CACHE_MAX:
			_strong_resource_cache.clear()
		_strong_resource_cache[path] = resource
	return resource
