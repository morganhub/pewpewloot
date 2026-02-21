extends Node

## PowerManager — Gère l'exécution des super pouvoirs et pouvoirs uniques.
## Gère l'invincibilité, les mouvements cinématiques et les patterns de tirs spéciaux.

const BOSS_VOID_ZONE := preload("res://scenes/effects/BossVoidZone.gd")
const BOSS_LASER_ZONE := preload("res://scenes/effects/BossLaserZone.gd")

func execute_power(power_id: String, source: Node2D) -> void:
	var data := DataManager.get_power(power_id)
	if data.is_empty():
		push_warning("[PowerManager] Power not found: " + power_id)
		return
	
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

func _handle_hazard(source: Node2D, hazard_data: Dictionary, default_duration: float) -> void:
	if not is_instance_valid(source):
		return

	var hazard_type: String = str(hazard_data.get("type", ""))
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
					zone.call("setup", source, hazard_data, default_duration)

		"laser_line", "laser_cone":
			var laser_data := hazard_data.duplicate(true)
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
	var waves: int = int(proj_data.get("waves", 1))
	var wave_delay: float = float(proj_data.get("wave_delay", 0.2))
	var count: int = int(proj_data.get("count", 10))
	var trajectory: String = str(proj_data.get("trajectory", "radial"))
	var size: float = float(proj_data.get("size", 20))
	var color_hex: String = str(proj_data.get("color", "#FFFF00"))
	var safe_zones: Variant = proj_data.get("safe_zones", null)
	var aim_target: bool = bool(proj_data.get("aim_target", false))
	var homing_turn_rate: float = float(proj_data.get("homing_turn_rate", 3.0))
	var homing_duration: float = float(proj_data.get("homing_duration", -1.0))
	var is_player_source: bool = source.is_in_group("player")
	if trajectory == "homing" and homing_duration < 0.0 and not is_player_source:
		homing_duration = 1.5
	
	var pattern := {
		"trajectory": trajectory,
		"aim_target": aim_target,
		"speed": 400.0,
		"damage": 50, # High damage info
		"visual_data": {
			"size": size,
			"color": color_hex,
			"shape": "circle",
			"asset": str(proj_data.get("asset", "")),
			"asset_anim": str(proj_data.get("asset_anim", "")),
			"asset_anim_duration": float(proj_data.get("asset_anim_duration", 0.0)),
			"asset_anim_loop": bool(proj_data.get("asset_anim_loop", true))
		}
	}
	if trajectory == "homing":
		pattern["homing_turn_rate"] = homing_turn_rate
		if homing_duration >= 0.0:
			pattern["homing_duration"] = homing_duration
	
	for i in range(waves):
		call_deferred("_spawn_wave", source, count, pattern, trajectory, safe_zones)
		await source.get_tree().create_timer(wave_delay).timeout
		if not is_instance_valid(source): return

func _spawn_wave(source: Node2D, count: int, pattern: Dictionary, trajectory: String, safe_zones: Variant = null) -> void:
	if not is_instance_valid(source): return
	
	var center := source.global_position
	var is_player := source.is_in_group("player")
	
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

			var dir := Vector2(cos(angle), sin(angle))
			_spawn(center, dir, is_player, pattern)
			
	elif trajectory == "rain_down":
		var viewport_width := source.get_viewport_rect().size.x
		for j in range(count):
			var x := randf_range(0, viewport_width)
			var start := Vector2(x, -50)
			var dir := Vector2.DOWN
			_spawn(start, dir, is_player, pattern)
			
	elif trajectory == "spiral":
		pattern["trajectory"] = "spiral" # Handled in Projectile.gd
		for j in range(count):
			var angle := (j / float(count)) * TAU
			var dir := Vector2(cos(angle), sin(angle))
			_spawn(center, dir, is_player, pattern)
			
	else:
		# Default burst
		for j in range(count):
			var dir := Vector2.DOWN.rotated(randf_range(-0.5, 0.5))
			_spawn(center, dir, is_player, pattern)

func _spawn(pos: Vector2, dir: Vector2, is_player: bool, pattern: Dictionary) -> void:
	if is_player:
		ProjectileManager.spawn_player_projectile(pos, dir, 400, 50, pattern, true) # true = is_crit (visual effect)
	else:
		ProjectileManager.spawn_enemy_projectile(pos, dir, 400, 20, pattern)
