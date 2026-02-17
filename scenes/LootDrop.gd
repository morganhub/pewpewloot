extends Area2D

## LootDrop — Item qui tombe et peut être collecté par le joueur.
## Représenté par une forme jaune (placeholder).

# =============================================================================
# PROPERTIES
# =============================================================================

var item_data: Dictionary = {}
var fall_speed: float = 100.0
var _is_collected: bool = false

@onready var visual: Polygon2D = $Visual

# =============================================================================
# LIFECYCLE
# =============================================================================

func setup(loot_item: Dictionary, pos: Vector2) -> void:
	_is_collected = false
	monitoring = true
	monitorable = true
	set_process(true)
	item_data = loot_item
	global_position = pos
	
	var is_powerup := str(item_data.get("type", "")) == "powerup"
	var default_size: float = 56.0 if is_powerup else 32.0
	var target_width: float = maxf(1.0, float(item_data.get("width", default_size)))
	var target_height: float = maxf(1.0, float(item_data.get("height", default_size)))
	var asset_anim_duration: float = maxf(0.0, float(item_data.get("asset_anim_duration", item_data.get("asset_duration", 0.0))))
	var asset_anim_loop: bool = bool(item_data.get("asset_anim_loop", item_data.get("asset_loop", true)))
	
	# Visual Setup (Sprite vs Polygon)
	# Support both 'visual_asset' (legacy/powerups) and 'asset' (LootItem)
	var asset_path = str(item_data.get("visual_asset", item_data.get("asset", "")))
	if not is_powerup:
		var gameplay_cfg: Dictionary = DataManager.get_game_data().get("gameplay", {})
		var loot_cfg_v: Variant = gameplay_cfg.get("loot", {})
		if loot_cfg_v is Dictionary:
			var loot_cfg := loot_cfg_v as Dictionary
			var generic_asset := str(loot_cfg.get("asset", ""))
			if generic_asset != "":
				asset_path = generic_asset
			target_width = maxf(1.0, float(loot_cfg.get("width", target_width)))
			target_height = maxf(1.0, float(loot_cfg.get("height", target_height)))
			asset_anim_duration = maxf(0.0, float(loot_cfg.get("asset_anim_duration", loot_cfg.get("asset_duration", asset_anim_duration))))
			asset_anim_loop = bool(loot_cfg.get("asset_anim_loop", loot_cfg.get("asset_loop", asset_anim_loop)))
	
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var loaded_res = load(asset_path)
		if loaded_res is SpriteFrames:
			var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if not anim_sprite:
				anim_sprite = AnimatedSprite2D.new()
				anim_sprite.name = "AnimatedSprite2D"
				add_child(anim_sprite)
			anim_sprite.visible = true
			anim_sprite.position = Vector2.ZERO
			anim_sprite.centered = true
			var frames: SpriteFrames = loaded_res as SpriteFrames
			
			var anim_name: StringName = VFXManager.play_sprite_frames(
				anim_sprite,
				frames,
				&"default",
				asset_anim_loop,
				asset_anim_duration
			)
			if anim_name != &"" and anim_sprite.sprite_frames:
				var frame_tex: Texture2D = anim_sprite.sprite_frames.get_frame_texture(anim_name, 0)
				if frame_tex:
					var frame_size := frame_tex.get_size()
					if frame_size.x > 0 and frame_size.y > 0:
						anim_sprite.scale = Vector2(target_width / frame_size.x, target_height / frame_size.y)
			
			var sprite_to_hide: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
			if sprite_to_hide:
				sprite_to_hide.visible = false
			visual.visible = false
		elif loaded_res is Texture2D:
			var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				add_child(sprite)
			sprite.visible = true
			sprite.texture = loaded_res as Texture2D
			visual.visible = false # Hide polygon
			# Scale icon from config.
			var tex_size = sprite.texture.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(target_width / tex_size.x, target_height / tex_size.y)
			
			var anim_to_hide: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if anim_to_hide:
				anim_to_hide.visible = false
		else:
			_apply_polygon_fallback(target_width, target_height)
	else:
		_apply_polygon_fallback(target_width, target_height)
	
	# TODO: Remplacer par sprite de l'item selon rarity
	# var rarity := str(item_data.get("rarity", "common"))
	# visual.texture = load("res://assets/items/" + item_data.get("id", "unknown") + ".png")
	
	# Connecter signaux
	# Layer 4 (Loot), Mask 2 (Player)
	collision_layer = 4
	collision_mask = 2
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	
	# Animation de pulsation
	_start_pulse_animation()

func _process(delta: float) -> void:
	if _is_collected:
		return

	global_position.y += fall_speed * delta

	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node and player_node is Node2D:
		var player_pos: Vector2 = (player_node as Node2D).global_position
		var magnet_radius: float = 0.0
		var is_powerup: bool = str(item_data.get("type", "")) == "powerup"
		if not is_powerup and player_node.has_method("get_magnet_radius_bonus"):
			magnet_radius += float(player_node.call("get_magnet_radius_bonus"))
		if player_node.has_method("get_vacuum_radius_bonus"):
			magnet_radius += float(player_node.call("get_vacuum_radius_bonus"))
		if magnet_radius > 0.0:
			var to_player: Vector2 = player_pos - global_position
			var distance: float = to_player.length()
			if distance <= magnet_radius and distance > 0.001:
				var pull_speed: float = 300.0 + (magnet_radius * 1.2)
				global_position += to_player.normalized() * pull_speed * delta
				if distance <= 24.0:
					_collect()
					return

	if global_position.y > get_viewport_rect().size.y + 50:
		queue_free()

# =============================================================================
# COLLECTION
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if _is_collected:
		return
	if body.is_in_group("player"):
		_collect()

func _collect() -> void:
	if _is_collected:
		return
	_is_collected = true
	
	# Hard lock against duplicate pickups from overlap/magnet spam.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_process(false)

	print("[LootDrop] Collected: ", item_data.get("name", "Item"))
	
	var is_powerup := str(item_data.get("type", "")) == "powerup"
	
	if is_powerup:
		# Power Up Logic
		var effect = item_data.get("effect", "")
		if effect == "fire_rate":
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("add_fire_rate_boost"):
				player.add_fire_rate_boost(10.0)
		elif effect == "shield":
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("activate_shield"):
				print("[LootDrop] SHIELD UP! (PowerUp Collected)")
				player.activate_shield()
	else:
		# Item d'inventaire
		ProfileManager.add_item_to_inventory(item_data)
		# Track for end of level summary
		get_tree().call_group("game_controller", "track_loot", item_data)
		# Only show toast notification for items, not powerups
		get_tree().call_group("game_hud", "show_loot_notification", item_data)
	
	# VFX de collection
	var visual_node := _get_active_visual_node()
	if visual_node:
		var base_scale := visual_node.scale
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual_node, "scale", base_scale * 2.0, 0.2)
		tween.tween_property(visual_node, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func _apply_polygon_fallback(target_width: float, target_height: float) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.visible = false
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite:
		anim_sprite.visible = false
	
	visual.visible = true
	visual.color = Color.YELLOW
	if item_data.get("effect") == "shield":
		visual.color = Color.CYAN
	elif item_data.get("effect") == "fire_rate":
		visual.color = Color.ORANGE
	
	var size := maxf(target_width, target_height) * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(size, 0),
		Vector2(0, size),
		Vector2(-size, 0)
	])

func _get_active_visual_node() -> Node2D:
	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite and anim_sprite.visible:
		return anim_sprite
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite and sprite.visible:
		return sprite
	if visual and visual.visible:
		return visual
	return null

func _start_pulse_animation() -> void:
	var pulse_node := _get_active_visual_node()
	if pulse_node == null:
		return
	var base_scale := pulse_node.scale
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(pulse_node, "scale", base_scale * 1.2, 0.5)
	tween.tween_property(pulse_node, "scale", base_scale, 0.5)
