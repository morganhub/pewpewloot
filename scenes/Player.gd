extends CharacterBody2D

## Player — Le vaisseau du joueur contrôlé par touch/mouse.
## Utilise les stats du loadout actif (vitesse, HP, armes).

# =============================================================================
# PLAYER STATS (ch argées depuis le loadout)
# =============================================================================

var max_hp: int = 100
var current_hp: int = 100
var move_speed: float = 200.0
var fire_rate: float = 0.3
var base_damage: int = 10
var damage_multiplier: float = 1.0  # Anciennement 'power' du json qui était un multiplier, maintenant c'est des dégâts fixes 'power'

# Advanced Stats
var crit_chance: float = 0.05
var dodge_chance: float = 0.02
var missile_speed_pct: float = 1.0
var special_cd: float = 10.0
var current_missile_id: String = "missile_default"

# =============================================================================
# STATE
# =============================================================================

var _fire_timer: float = 0.0
var _can_shoot: bool = true

var visual_container: Node2D = null
var shape_visual: Polygon2D = null

# TODO: Remplacer par le vrai sprite du vaisseau
# Placeholder: Triangle vert via Polygon2D dans la scène

func _ready() -> void:
	_init_visual_nodes()
	_load_stats_from_loadout()
	_setup_visual()
	position = Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y - 100)

func _init_visual_nodes() -> void:
	# Créer un conteneur visuel s'il n'existe pas
	visual_container = Node2D.new()
	visual_container.name = "VisualContainer"
	add_child(visual_container)
	
	# Créer le Polygon2D pour les formes
	shape_visual = Polygon2D.new()
	shape_visual.name = "Shape"
	visual_container.add_child(shape_visual)
	
	# Masquer les anciens placeholders éventuels
	for child in get_children():
		if child != visual_container and (child is Polygon2D or child is Sprite2D or child.name == "Visual"):
			child.visible = false

func _setup_visual() -> void:
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var visual_data: Variant = ship.get("visual", {})
	if not visual_data is Dictionary:
		visual_data = {}
	var visual_dict := visual_data as Dictionary
	
	# Gestion de l'asset vs shape
	var asset_path: String = str(visual_dict.get("asset", ""))
	var use_asset: bool = false
	
	var width: float = 40.0
	var height: float = 40.0
	
	print("[Player] Visual Setup - Asset Path: ", asset_path)
	if asset_path != "":
		print("[Player] Resource Exists? ", ResourceLoader.exists(asset_path))
	
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			print("[Player] Texture loaded: ", texture)
			use_asset = true
			shape_visual.visible = false
			
			var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
			if not sprite:
				sprite = Sprite2D.new()
				sprite.name = "Sprite2D"
				visual_container.add_child(sprite)
			
			sprite.visible = true
			sprite.texture = texture
			
			# Scale
			var tex_size = texture.get_size()
			print("[Player] Texture size: ", tex_size)
			if tex_size.x > 0 and tex_size.y > 0:
				sprite.scale = Vector2(width / tex_size.x, height / tex_size.y)
				print("[Player] Sprite scale: ", sprite.scale)
	
	if not use_asset:
		var color := Color(visual_dict.get("color", "#CCCCCC"))
		var shape_type := str(visual_dict.get("shape", "triangle"))
		
		var sprite: Sprite2D = visual_container.get_node_or_null("Sprite2D")
		if sprite:
			sprite.visible = false
			
		shape_visual.visible = true
		shape_visual.color = color
		shape_visual.polygon = _create_shape_polygon(shape_type, width, height)

func _load_stats_from_loadout() -> void:
	# Récupérer le vaisseau actif
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	
	# Récupérer les stats de base du vaisseau
	var stats: Variant = ship.get("stats", {})
	if stats is Dictionary:
		var stats_dict := stats as Dictionary
		max_hp = int(stats_dict.get("max_hp", 100))
		move_speed = float(stats_dict.get("move_speed", 200))
		base_damage = int(stats_dict.get("power", 10))
		fire_rate = float(stats_dict.get("fire_rate", 0.3))
		
		crit_chance = float(stats_dict.get("crit_chance", 0.05))
		dodge_chance = float(stats_dict.get("dodge_chance", 0.02))
		missile_speed_pct = float(stats_dict.get("missile_speed_pct", 1.0))
		special_cd = float(stats_dict.get("special_cd", 10.0))
	
	# Load missile ID from ship data
	current_missile_id = str(ship.get("missile_id", "missile_default"))
	
	# TODO: Ajouter les bonus des items équipés (Additif pour %, Additif pour stats plates)
	# Exemple:
	# var loadout := ProfileManager.get_loadout_for_ship(ship_id)
	# for slot in loadout:
	#	var item_id = loadout[slot]
	#	var item = DataManager.get_item(item_id) # ou inventory
	#   ... apply bonuses
	
	current_hp = max_hp
	print("[Player] Stats Loaded:")
	print("  HP: ", max_hp)
	print("  Dmg: ", base_damage)
	print("  Crit: ", crit_chance * 100, "%")
	print("  Dodge: ", dodge_chance * 100, "%")
	print("  Spd%: ", missile_speed_pct * 100, "%")

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_shooting(delta)

func _handle_movement(delta: float) -> void:
	# Déplacement via position de la souris/touch
	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()
	
	# Smooth movement vers la souris
	var distance := global_position.distance_to(mouse_pos)
	if distance > 5:  # Dead zone
		# Interpolation directe de la position
		position = position.lerp(mouse_pos, delta * 15.0)
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()
	
	# Clamper à l'écran
	var viewport_size := get_viewport_rect().size
	global_position.x = clampf(global_position.x, 20, viewport_size.x - 20)
	global_position.y = clampf(global_position.y, 20, viewport_size.y - 20)

func _handle_shooting(delta: float) -> void:
	_fire_timer -= delta
	
	if _fire_timer <= 0 and _can_shoot:
		_fire()
		_fire_timer = fire_rate

func _fire() -> void:
	# TODO: Instancier un projectile basé sur le loadout
	# Pour le moment, tir simple placeholder
	print("[Player] Fire!")
	
	# Récupérer le missile_pattern du slot "primary"
	var ship_id := ProfileManager.get_active_ship_id()
	var loadout := ProfileManager.get_loadout_for_ship(ship_id)
	var _primary_item_id := str(loadout.get("primary", ""))
	
	# TODO: Si item équipé, utiliser son missile_pattern
	# Sinon, utiliser le tir par défaut du vaisseau
	
	# Placeholder: Tir simple direct
	_spawn_projectile(Vector2.UP, 400, 10)

func _spawn_projectile(direction: Vector2, speed: float, damage: int) -> void:
	# Calcul critique
	var is_critical := randf() <= crit_chance
	var final_damage := damage
	# Note: On passe damage de base, le Enemy fera x2 si critical, ou on le fait ici ?
	# Si on le fait ici c'est plus simple pour le projectile manager qui passe juste damage
	# Mais pour l'affichage pop-up damages sur l'ennemi il faut savoir si c'est critique
	# Le paramètre is_critical sert à l'affichage Projectile (jaune) et à Enemy (affichage jaune)
	
	if is_critical:
		final_damage *= 2
	
	final_damage = int(final_damage * damage_multiplier)

	# Utiliser le ProjectileManager avec pooling
	var pattern_data := {
		"trajectory": "straight",
		"speed": speed,
		"damage": final_damage,
		"size": 8,
		"color": "#44FF44"
	}
	
	# Injecter les visuels du missile
	var missile_data := DataManager.get_missile(current_missile_id)
	var visual_data: Dictionary = missile_data.get("visual", {})
	if not visual_data.is_empty():
		pattern_data["visual_data"] = visual_data
	
	ProjectileManager.spawn_player_projectile(
		global_position + Vector2(0, -20),
		direction,
		speed,
		final_damage,
		pattern_data,
		is_critical
	)

func take_damage(amount: int) -> void:
	# Dodge check
	if randf() <= dodge_chance:
		VFXManager.spawn_floating_text(global_position, "DODGE", Color.CYAN, get_parent())
		return
	
	current_hp -= amount
	current_hp = maxi(0, current_hp)
	
	print("[Player] Took damage: ", amount, " | HP: ", current_hp, "/", max_hp)
	
	# Feedback visuel
	VFXManager.flash_sprite(self, Color.RED, 0.15)
	VFXManager.screen_shake(5, 0.15)
	
	if current_hp <= 0:
		die()

func die() -> void:
	print("[Player] GAME OVER")
	# TODO: Transition vers écran game over
	queue_free()

func heal(amount: int) -> void:
	current_hp += amount
	current_hp = mini(current_hp, max_hp)
	print("[Player] Healed: ", amount, " | HP: ", current_hp, "/", max_hp)

# =============================================================================
# UTILITY (Visual generation)
# =============================================================================

func _create_shape_polygon(shape_type: String, width: float, height: float) -> PackedVector2Array:
	match shape_type:
		"circle":
			return _create_circle(max(width, height) / 2.0)
		"rectangle":
			return PackedVector2Array([
				Vector2(-width/2, -height/2),
				Vector2(width/2, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"triangle":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, height/2),
				Vector2(-width/2, height/2)
			])
		"diamond":
			return PackedVector2Array([
				Vector2(0, -height/2),
				Vector2(width/2, 0),
				Vector2(0, height/2),
				Vector2(-width/2, 0)
			])
		"hexagon":
			return _create_hexagon(max(width, height) / 2.0)
		_:
			return _create_triangle_default(width, height)

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 16
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _create_hexagon(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := (i / 6.0) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _create_triangle_default(width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -height/2),
		Vector2(width/2, height/2),
		Vector2(-width/2, height/2)
	])
