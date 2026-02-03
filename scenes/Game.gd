extends Node2D

## Game — Scène principale du gameplay.
## Spawn le joueur, ennemis, gère le background animé.

# =============================================================================
# REFERENCES
# =============================================================================

@onready var background: TextureRect = $Background
@onready var game_layer: Node2D = $GameLayer
@onready var hud_container: Control = $HUD
@onready var camera: Camera2D = $Camera2D

var player: CharacterBody2D = null
var hud: CanvasLayer = null
var boss_hud: Control = null

var enemies_killed: int = 0
var boss_spawned: bool = false
var current_level_index: int = 0 # Défini par LevelSelect ou WorldSelect
var current_world_id: String = "world_1" # Par défaut, peut être change par WorldSelect

# =============================================================================
# BACKGROUND
# =============================================================================

var _bg_scroll_speed: float = 50.0
var _bg_offset: float = 0.0

func _ready() -> void:
	_setup_background()
	_setup_camera()
	_setup_hud()
	_spawn_player()
	_setup_projectile_manager()
	_start_enemy_spawner()

func _setup_background() -> void:
	# Nettoyer le placeholder existant
	if background:
		background.queue_free()
		background = null
	
	# Créer un conteneur pour les layers
	var bg_container := Node2D.new()
	bg_container.name = "BackgroundContainer"
	add_child(bg_container)
	move_child(bg_container, 0)
	
	# Récupérer les données du niveau
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	var level_data := DataManager.get_level_data(level_id)
	
	if level_data.is_empty():
		push_warning("[Game] No data found for level: " + level_id)
		return
	
	var bgs: Dictionary = level_data.get("backgrounds", {})
	var viewport_size := get_viewport_rect().size
	var base_speed: float = 50.0
	
	print("[Game] Loading background for ", level_id)
	
	# 1. FAR LAYER (0.2x, JPG Opaque, Tiling)
	var far_path: String = str(bgs.get("far_layer", ""))
	if far_path != "":
		_create_layer(bg_container, far_path, base_speed * 0.2, viewport_size)
	
	# 2. MID LAYER (1.0x, PNG Alpha, Random/Tiling)
	var mid_layers := _flatten_layers(bgs.get("mid_layer", []))
	for path in mid_layers:
		_create_layer(bg_container, path, base_speed * 1.0, viewport_size)
	
	# 3. NEAR LAYER (2.5x, PNG Alpha, Fast/Blur)
	var near_layers := _flatten_layers(bgs.get("near_layer", []))
	for path in near_layers:
		_create_layer(bg_container, path, base_speed * 2.5, viewport_size)

func _create_layer(parent: Node, path: String, speed: float, viewport_size: Vector2) -> void:
	if path == "": return
	
	var tex := load(path)
	if tex:
		var layer_script = load("res://scenes/ScrollingLayer.gd")
		var layer = layer_script.new()
		parent.add_child(layer)
		layer.setup(tex, speed, viewport_size)
	else:
		push_warning("[Game] Could not load background texture: " + path)

func _flatten_layers(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item in data:
			result.append_array(_flatten_layers(item))
	elif data is String:
		result.append(data)
	return result

func _process(delta: float) -> void:
	# Le background se gère tout seul via ScrollingLayer._process
	_update_hud()

# func _update_background(delta: float) -> void: ... DELETED

# =============================================================================
# CAMERA
# =============================================================================

func _setup_camera() -> void:
	VFXManager.set_camera(camera)

# =============================================================================
# HUD
# =============================================================================

func _setup_hud() -> void:
	var hud_scene := load("res://scenes/GameHUD.tscn")
	hud = hud_scene.instantiate()
	hud_container.add_child(hud)
	
	# Initialiser la barre de vie
	if player:
		hud.set_player_max_hp(player.max_hp)

func _update_hud() -> void:
	if player and hud:
		hud.update_player_hp(player.current_hp, player.max_hp)

# =============================================================================
# PLAYER
# =============================================================================

func _spawn_player() -> void:
	var player_scene := load("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	game_layer.add_child(player)
	print("[Game] Player spawned")
	
	# Connecter les signaux
	player.tree_exiting.connect(_on_player_died)

func _on_player_died() -> void:
	print("[Game] Player died! Game Over.")
	# TODO: Transition vers écran Game Over
	await get_tree().create_timer(2.0).timeout
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

# =============================================================================
# PROJECTILES
# =============================================================================

func _setup_projectile_manager() -> void:
	ProjectileManager.set_container(game_layer)

# =============================================================================
# ENEMIES
# =============================================================================

# =============================================================================
# ENEMIES (WAVE SYSTEM)
# =============================================================================

var wave_manager: Node = null

func _start_enemy_spawner() -> void:
	# Instancier le WaveManager
	var wm_script = load("res://scenes/WaveManager.gd")
	wave_manager = wm_script.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	
	wave_manager.spawn_enemy.connect(_on_wave_enemy_spawn)
	wave_manager.level_completed.connect(_on_level_completed)
	
	# Démarrer le niveau actuel
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	wave_manager.setup(level_id)

func _on_wave_enemy_spawn(enemy_data: Dictionary, _spawn_pos_hint: Vector2) -> void:
	# Instancier l'ennemi
	var enemy_scene := load("res://scenes/Enemy.tscn")
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	
	# Position calculée ici pour le moment (Haut de l'écran, aléatoire X ou pattern)
	# Si le pattern est "straight_down", on veut probablement random X.
	# Si c'est un pattern complexe, peut-être fixe ?
	# Pour ce prototype, on garde random X.
	var viewport_width := get_viewport_rect().size.x
	var spawn_pos := Vector2(randf_range(50, viewport_width - 50), -50)
	
	# Calcul du scaling par niveau
	var scaling_multiplier: float = 1.0 + (current_level_index * 0.1)
	
	game_layer.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.setup(enemy_data, scaling_multiplier)
	
	# Connecter le signal de mort
	enemy.enemy_died.connect(_on_enemy_died)
	# print("[Game] Wave Spawn: ", enemy_data.get("name", "?"))

func _on_level_completed() -> void:
	print("[Game] Level Completed! Spawning Boss...")
	_spawn_boss()

func _on_enemy_died(enemy: CharacterBody2D) -> void:
	print("[Game] Enemy died")
	
	# Ajouter score
	if hud:
		hud.add_score(enemy.score)
	
	enemies_killed += 1
	
	# Note: Le boss spawn est maintenant géré par WaveManager -> _on_level_completed

func _spawn_boss() -> void:
	boss_spawned = true
	print("[Game] BOSS INCOMING!")
	
	# Arrêter le spawn d'ennemis normaux
	for child in get_children():
		if child is Timer:
			child.stop()
	
	# Spawn le boss
	var boss_data := DataManager.get_boss("boss_world1")
	if boss_data.is_empty():
		print("[Game] Boss data not found!")
		return
	
	var boss_scene := load("res://scenes/Boss.tscn")
	var boss: CharacterBody2D = boss_scene.instantiate()
	
	var viewport_width := get_viewport_rect().size.x
	var spawn_pos := Vector2(viewport_width / 2, 100)
	
	game_layer.add_child(boss)
	boss.global_position = spawn_pos
	boss.setup(boss_data)
	
	# Afficher la barre de vie du boss dans le HUD existant
	if hud:
		hud.show_boss_health(boss_data.get("name", "Boss"), boss.max_hp)
		
	# Connecter signaux
	boss.boss_died.connect(_on_boss_died)
	boss.health_changed.connect(_on_boss_health_changed)
	
	VFXManager.screen_shake(15, 0.8)

func _on_boss_health_changed(new_hp: int, max_hp: int) -> void:
	if hud:
		hud.update_boss_health(new_hp, max_hp)

func _on_boss_died(boss: CharacterBody2D) -> void:
	print("[Game] BOSS DEFEATED!")
	
	# Gros score bonus
	if hud:
		hud.add_score(boss.score)
	
	# TODO: Victory screen
	
	# Générer un loot épique/légendaire
	var slot_ids := DataManager.get_slot_ids()
	if slot_ids.is_empty(): 
		_return_to_home()
		return
		
	var random_slot := str(slot_ids[randi() % slot_ids.size()])
	var item_id := "boss_loot_" + str(Time.get_ticks_msec())
	
	var item := {
		"id": item_id,
		"name": "Boss Reward",
		"slot": random_slot,
		"rarity": "epic" if randf() > 0.2 else "legendary",
		"level": current_level_index + 1,
		"stats": {"bonus": randi() % 20 + 10} # Placeholder stats
	}
	
	# Afficher l'écran de résultat
	var loot_screen_scene := load("res://scenes/LootResultScreen.tscn")
	var loot_screen: Control = loot_screen_scene.instantiate()
	hud_container.add_child(loot_screen)
	loot_screen.setup(item)
	loot_screen.finished.connect(_return_to_home)
	
	# Mettre en pause le jeu
	get_tree().paused = true

func _return_to_home() -> void:
	get_tree().paused = false
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")
