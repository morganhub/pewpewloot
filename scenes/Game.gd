extends Node2D

## Game — Scène principale du gameplay.
## Spawn le joueur, ennemis, gère le background animé.

# =============================================================================
# REFERENCES
# =============================================================================

@onready var background: TextureRect = $Background
@onready var game_layer: Node2D = $GameLayer
@onready var hud_container: Control = $UI/HUD
@onready var camera: Camera2D = $Camera2D

const SCROLLING_LAYER_SCRIPT: Script = preload("res://scenes/ScrollingLayer.gd")

var player: CharacterBody2D = null
var hud: CanvasLayer = null
var boss_hud: Control = null
var pause_menu: Control = null

var enemies_killed: int = 0
var boss_spawned: bool = false
var session_loot: Array = [] # Track items collected in this session
var active_boss: CharacterBody2D = null
var _end_session_started: bool = false
var _player_death_registered: bool = false
var _wave_total_with_boss: int = 0

var current_level_index: int = 0 # Défini par LevelSelect ou WorldSelect
var current_world_id: String = "world_1" # Par défaut, peut être change par WorldSelect

func track_loot(item: Dictionary) -> void:
	session_loot.append(item)

# =============================================================================
# BACKGROUND
# =============================================================================

func _ready() -> void:
	# Load session data
	current_world_id = App.current_world_id
	current_level_index = App.current_level_index
	print("[Game] Ready. Level: ", current_world_id, " | Index: ", current_level_index)
	
	add_to_group("game_controller")
	
	# Reset Managers
	EnemyAbilityManager.reset()
	
	# Music
	var world = App.get_world(current_world_id)
	var world_theme = world.get("theme", {})
	var music = str(world_theme.get("music", ""))
	if music != "":
		App.play_music(music)
	else:
		App.play_menu_music() # Enforce menu music if no override
	
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
	bg_container.z_index = -100 # Ensure behind walls and entities
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
		_create_layer(bg_container, far_path, base_speed * 0.2, viewport_size, false)
	
	# 2. MID LAYER (1.0x, PNG Alpha, Random/Tiling)
	var mid_layers := _flatten_layers(bgs.get("mid_layer", []))
	for path in mid_layers:
		_create_layer(bg_container, path, base_speed * 1.0, viewport_size, true)
	
	# 3. NEAR LAYER (2.5x, PNG Alpha, Fast/Blur)
	var near_layers := _flatten_layers(bgs.get("near_layer", []))
	for path in near_layers:
		_create_layer(bg_container, path, base_speed * 2.5, viewport_size, true)

func _create_layer(parent: Node, path: String, speed: float, viewport_size: Vector2, use_add_blend: bool) -> void:
	if path == "": return
	
	# Preload resource to prevent "popping" during gameplay.
	# Supports Texture2D (.png, .jpg, AnimatedTexture .tres) and SpriteFrames (.tres).
	if not ResourceLoader.exists(path):
		push_warning("[Game] Background resource does not exist: " + path)
		return
		
	var layer_resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	
	if layer_resource:
		var layer: Node = SCROLLING_LAYER_SCRIPT.new()
		parent.add_child(layer)
		layer.call("setup", layer_resource, speed, viewport_size, use_add_blend)
	else:
		push_warning("[Game] Could not load background resource: " + path)

func _flatten_layers(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item in data:
			result.append_array(_flatten_layers(item))
	elif data is String:
		result.append(data)
	return result

func _process(_delta: float) -> void:
	# Le background se gère tout seul via ScrollingLayer._process
	_update_hud()

# func _update_background(delta: float) -> void: ... DELETED

# =============================================================================
# CAMERA
# =============================================================================

func _setup_camera() -> void:
	# Force Camera to Top-Left alignment to match background coordinates
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.position = Vector2.ZERO
	VFXManager.set_camera(camera)

# =============================================================================
# HUD
# =============================================================================

func _setup_hud() -> void:
	var hud_scene := load("res://scenes/GameHUD.tscn")
	hud = hud_scene.instantiate()
	hud_container.add_child(hud)
	
	# Connect pause signal
	hud.pause_requested.connect(_show_pause_menu)
	
	# Load and setup PauseMenu
	var pause_scene := load("res://scenes/PauseMenu.tscn")
	pause_menu = pause_scene.instantiate()
	hud_container.add_child(pause_menu)
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.level_select_requested.connect(_on_level_select_requested)
	pause_menu.quit_requested.connect(_on_quit_requested)
	
	# Initialiser la barre de vie
	if player:
		hud.set_player_max_hp(player.max_hp)
	
	hud.special_requested.connect(func(): if player: player.use_special())
	hud.unique_requested.connect(func(): if player: player.use_unique())

func _update_hud() -> void:
	if hud:
		if is_instance_valid(player):
			hud.update_player_hp(player.current_hp, player.max_hp)
		else:
			# Player may be null because it was queue_free'd on death
			# We force 0 to ensure the HUD shows death state
			hud.update_player_hp(0, 100)

# =============================================================================
# PLAYER
# =============================================================================

func _spawn_player() -> void:
	var player_scene := load("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.input_provider = hud # Assigner le joystick provider
	
	# Initial Position (20% from bottom = 80% of height)
	var viewport_size := get_viewport_rect().size
	player.position = Vector2(viewport_size.x / 2, viewport_size.y * 0.8)
	
	game_layer.add_child(player)
	print("[Game] Player spawned")
	
	if hud:
		hud.set_player_reference(player)
	
	# Connecter les signaux
	player.tree_exiting.connect(_on_player_died)

func _on_player_died() -> void:
	if _end_session_started or _player_death_registered:
		return
	
	_player_death_registered = true
	print("[Game] Player died! Game Over.")
	
	# Empêche le boss d'être tué après la mort du joueur (ex: projectile déjà en vol).
	if is_instance_valid(active_boss):
		if active_boss.has_method("set_invincible"):
			active_boss.call("set_invincible", true)
	
	# Show Game Over Overlay
	var overlay_scene := load("res://scenes/ui/GameOverOverlay.tscn")
	var overlay: Control = overlay_scene.instantiate()
	hud_container.add_child(overlay)
	
	# After animation, show session report (Loot/Inventory)
	overlay.animation_finished.connect(func():
		await get_tree().create_timer(1.5).timeout
		overlay.queue_free()
		_show_end_session_screen(false)
	)
	
	# Ensure overlay is at the bottom for layering
	hud_container.move_child(overlay, 0)

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
	wave_manager.wave_started.connect(_on_wave_started)
	
	# Démarrer le niveau actuel
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	_configure_wave_counter(level_id)
	wave_manager.setup(level_id)

func _configure_wave_counter(level_id: String) -> void:
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	var waves_variant: Variant = level_data.get("waves", [])
	var waves_count: int = 0
	if waves_variant is Array:
		waves_count = (waves_variant as Array).size()
	
	var boss_id: String = str(level_data.get("boss_id", ""))
	var has_boss: bool = boss_id != ""
	_wave_total_with_boss = waves_count + (1 if has_boss else 0)
	
	if hud and hud.has_method("configure_wave_counter"):
		hud.call("configure_wave_counter", _wave_total_with_boss)

func _on_wave_started(wave_index: int) -> void:
	var current_wave: int = wave_index + 1
	if hud and hud.has_method("update_wave_counter"):
		hud.call("update_wave_counter", current_wave)

func _on_wave_enemy_spawn(enemy_data: Dictionary, spawn_pos: Vector2) -> void:
	# Instancier l'ennemi
	var enemy_scene := load("res://scenes/Enemy.tscn")
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	
	# Calcul du scaling par niveau
	var scaling_multiplier: float = 1.0 + (current_level_index * 0.1)
	
	game_layer.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.setup(enemy_data, scaling_multiplier)
	
	# Connecter le signal de mort
	enemy.enemy_died.connect(_on_enemy_died)
	# print("[Game] Wave Spawn: ", enemy_data.get("name", "?"))

func _on_level_completed() -> void:
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	var level_data := DataManager.get_level_data(level_id)
	var boss_id: String = str(level_data.get("boss_id", ""))
	
	if boss_id != "":
		print("[Game] Level Waves Completed! Spawning Boss: ", boss_id)
		_spawn_boss(boss_id)
	else:
		print("[Game] Level Waves Completed! No Boss defined, triggering victory.")
		_show_end_session_screen(true)

func _on_enemy_died(enemy: CharacterBody2D) -> void:
	#print("[Game] Enemy died")
	
	# Ajouter score
	if hud:
		hud.add_score(enemy.score)
	
	enemies_killed += 1
	
	# Note: Le boss spawn est maintenant géré par WaveManager -> _on_level_completed

func _spawn_boss(boss_id: String) -> void:
	boss_spawned = true
	print("[Game] BOSS INCOMING: ", boss_id)
	if hud and hud.has_method("update_wave_counter"):
		hud.call("update_wave_counter", _wave_total_with_boss)
	
	# Arrêter le spawn d'ennemis normaux
	_stop_all_timers()
	if wave_manager:
		wave_manager.stop()
	
	# Spawn le boss
	var boss_data := DataManager.get_boss(boss_id)
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
	active_boss = boss
	
	# Afficher la barre de vie du boss dans le HUD existant
	if hud:
		hud.show_boss_health(boss_data.get("name", "Boss"), boss.max_hp)
		
	# Connecter signaux
	boss.boss_died.connect(_on_boss_died)
	boss.health_changed.connect(_on_boss_health_changed)
	
	if bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(15, 0.8)

func _on_boss_health_changed(new_hp: int, max_hp: int) -> void:
	if hud:
		hud.update_boss_health(new_hp, max_hp)

func _on_boss_died(boss: CharacterBody2D) -> void:
	if _player_death_registered:
		print("[Game] Boss died after player death; ignoring victory flow.")
		return
	
	if _end_session_started:
		return
	
	print("[Game] BOSS DEFEATED!")
	if hud:
		hud.add_score(boss.score)
	
	# Rendre le joueur invincible pour éviter de mourir pendant le popup de loot
	if player:
		player.is_invincible = true
		if player.has_method("set_can_shoot"):
			player.set_can_shoot(false)
	
	active_boss = null
			
	_show_end_session_screen(true)

func _show_end_session_screen(is_victory: bool = true) -> void:
	if _end_session_started:
		return
	_end_session_started = true
	
	# Disable spawning/shooting immediately
	if player and player.has_method("set_can_shoot"):
		player.set_can_shoot(false)
	if wave_manager:
		wave_manager.stop()
		
	# 1. Feedback
	if hud:
		var txt = "VICTOIRE !" if is_victory else "DÉFAITE..."
		var color = Color.GREEN if is_victory else Color.RED
		VFXManager.spawn_floating_text(player.global_position if is_instance_valid(player) else Vector2(get_viewport_rect().size.x/2, get_viewport_rect().size.y/2), txt, color, hud_container)
	
	await get_tree().create_timer(3.0).timeout
	
	# 2. Main Reward (Boss Loot) - Only on Victory
	var item := {}
	if is_victory:
		# Use universal boss loot pipeline:
		# - rarity rates from data/loot_table.json
		# - boss unique pool from data/bosses.json -> loot_table
		var target_level: int = max(1, current_level_index + 1)
		
		var level_id := current_world_id + "_lvl_" + str(current_level_index)
		var level_data := DataManager.get_level_data(level_id)
		var boss_id: String = str(level_data.get("boss_id", ""))
		
		var generated_item: LootItem = LootGenerator.generate_boss_loot(target_level, boss_id)
		if generated_item:
			item = generated_item.to_dict()
		else:
			push_warning("[Game] Boss reward generation failed, result screen will show no item.")
	
	
	# 3. Setup and show Result Screen
	var loot_screen_scene := load("res://scenes/LootResultScreen.tscn")
	if loot_screen_scene:
		var loot_screen: Control = loot_screen_scene.instantiate()
		hud_container.add_child(loot_screen)
		loot_screen.setup(item, session_loot, is_victory)
		loot_screen.finished.connect(_return_to_home)
		loot_screen.restart_requested.connect(_on_restart_requested)
		loot_screen.exit_requested.connect(_on_level_select_requested)

func _return_to_home() -> void:
	App.play_menu_music()
	get_tree().paused = false
	
	ProjectileManager.clear_all_projectiles()
	
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

# =============================================================================
# PAUSE MENU
# =============================================================================

func _show_pause_menu() -> void:
	if pause_menu:
		pause_menu.show_menu()

func _on_restart_requested() -> void:
	print("[Game] Restart requested for Level: ", current_world_id, " | Index: ", current_level_index)
	get_tree().paused = false
	
	ProjectileManager.clear_all_projectiles()
	
	# Recharger la scène de jeu avec les paramètres actuels
	# On passe par le SceneSwitcher s'il est disponible pour faire propre
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		# App.current_level_index est déjà set
		switcher.goto_screen("res://scenes/Game.tscn")
	else:
		# Fallback classique
		get_tree().reload_current_scene()

func _on_level_select_requested() -> void:
	App.play_menu_music()
	get_tree().paused = false
	
	ProjectileManager.clear_all_projectiles()
	
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _on_quit_requested() -> void:
	_return_to_home()

func _stop_all_timers() -> void:
	for child in get_children():
		if child is Timer:
			child.stop()
