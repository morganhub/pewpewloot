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
const ENEMY_SCRIPT: Script = preload("res://scenes/Enemy.gd")
const WAVE_MANAGER_SCRIPT: Script = preload("res://scenes/WaveManager.gd")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/Boss.tscn")
const RUNTIME_WARMUP_PATHS: PackedStringArray = [
	"res://scenes/obstacles/ObstacleExplosive.tscn",
	"res://scenes/obstacles/ObstaclePusher.tscn",
	"res://scenes/objects/Mine.tscn",
	"res://scenes/objects/ArcaneOrb.tscn",
	"res://scenes/objects/GravityWell.tscn",
	"res://scenes/objects/SuppressorShield.tscn",
	"res://scenes/effects/ToxicPool.tscn",
	"res://scenes/effects/Singularity.tscn",
	"res://scenes/effects/IceAura.tscn",
	"res://scenes/effects/IceShards.tscn",
	"res://scenes/effects/VacuumRadius.tscn",
	"res://scenes/abilities/objects/Wall.tscn",
	"res://scenes/abilities/WallSpawner.gd",
	"res://scenes/effects/BossVoidZone.gd",
	"res://scenes/effects/BossLaserZone.gd"
]
const RUNTIME_WARMUP_PREFIXES: PackedStringArray = [
	"res://scenes/abilities/",
	"res://scenes/effects/",
	"res://scenes/objects/",
	"res://scenes/obstacles/"
]
const DEBUG_PERF_HITCH_LOG := true
const DEBUG_PERF_HITCH_THRESHOLD_MS := 22.0
const DEBUG_PERF_HITCH_COOLDOWN_MS := 250
const DEBUG_LEVEL_WARMUP_LOG := true
const DEBUG_RUNTIME_ENEMY_PREWARM_LOG := true
const DEBUG_SPAWN_PIPELINE_LOG := false
const DEBUG_SPAWN_PIPELINE_THRESHOLD_MS := 4.0

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
var session_xp: int = 0  # XP accumulated this session (= score)
var _end_screen_delay_seconds: float = 1.5
var _end_screen_context_action: String = "level_select"

const END_SCREEN_ACTION_LEVEL_SELECT := "level_select"
const END_SCREEN_ACTION_NEXT_LEVEL := "next_level"
const END_SCREEN_ACTION_WORLD_SELECT := "world_select"

var current_level_index: int = 0 # Défini par LevelSelect ou WorldSelect
var current_world_id: String = "world_1" # Par défaut, peut être change par WorldSelect
var _world_multipliers: Dictionary = {"hp": 1.0, "damage": 1.0, "speed": 1.0}
var _world_skin_overrides: Dictionary = {} # Centralized skin overrides from world JSON
var _last_hitch_log_ms: int = -10000
var _loot_drop_rules: Dictionary = {}
var _wave_powerup_drop_counts: Dictionary = {"shield": 0, "fire_rate": 0}

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
	_load_gameplay_config()
	
	add_to_group("game_controller")
	
	# Reset Managers
	EnemyAbilityManager.reset()
	ENEMY_SCRIPT._logged_patterns.clear()
	
	# Music
	var world = App.get_world(current_world_id)
	_world_multipliers = world.get("multipliers", {"hp": 1.0, "damage": 1.0, "speed": 1.0})
	_world_skin_overrides = DataManager.get_world_skin_overrides(current_world_id)
	print("[Game] World multipliers: ", _world_multipliers)
	print("[Game] World skin overrides keys: ", _world_skin_overrides.keys())
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
	_setup_fluid_simulation()
	_start_enemy_spawner()

func _load_gameplay_config() -> void:
	var game_cfg: Dictionary = DataManager.get_game_config()
	var gameplay_cfg: Variant = game_cfg.get("gameplay", {})
	if not (gameplay_cfg is Dictionary):
		_loot_drop_rules = _build_default_loot_drop_rules()
		return

	_loot_drop_rules = _build_default_loot_drop_rules()
	var loot_cfg: Variant = (gameplay_cfg as Dictionary).get("loot_drops", {})
	if loot_cfg is Dictionary:
		_loot_drop_rules.merge((loot_cfg as Dictionary), true)

	var end_session_cfg: Variant = (gameplay_cfg as Dictionary).get("end_session", {})
	if not (end_session_cfg is Dictionary):
		return

	_end_screen_delay_seconds = maxf(0.0, float((end_session_cfg as Dictionary).get("post_battle_delay_seconds", 1.5)))

func _build_default_loot_drop_rules() -> Dictionary:
	return {
		"enabled": true,
		"allow_equipment": true,
		"allow_powerups": true,
		"global_chance_scale": 0.7,
		"equipment_chance_scale": 0.45,
		"powerup_chance_scale": 0.55,
		"max_shield_per_wave": 1,
		"max_rapid_fire_per_wave": 1,
		"shield_weight": 1.0,
		"rapid_fire_weight": 1.0
	}

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
	var mid_layers := _flatten_layer_entries(bgs.get("mid_layer", []), 1.0)
	for mid_entry in mid_layers:
		var mid_path: String = str(mid_entry.get("path", ""))
		var mid_opacity: float = float(mid_entry.get("opacity", 1.0))
		_create_layer(bg_container, mid_path, base_speed * 1.0, viewport_size, true, mid_opacity)
	
	# 3. NEAR LAYER (2.5x, PNG Alpha, Fast/Blur)
	var near_layers := _flatten_layer_entries(bgs.get("near_layer", []), 1.0)
	for near_entry in near_layers:
		var near_path: String = str(near_entry.get("path", ""))
		var near_opacity: float = float(near_entry.get("opacity", 1.0))
		_create_layer(bg_container, near_path, base_speed * 2.5, viewport_size, true, near_opacity)

func _create_layer(
	parent: Node,
	path: String,
	speed: float,
	viewport_size: Vector2,
	use_add_blend: bool,
	opacity: float = 1.0
) -> void:
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
		if layer is CanvasItem:
			(layer as CanvasItem).modulate.a = clampf(opacity, 0.0, 1.0)
	else:
		push_warning("[Game] Could not load background resource: " + path)

func _flatten_layer_entries(data: Variant, default_opacity: float = 1.0) -> Array:
	var result: Array = []
	if data is Array:
		for item in data:
			result.append_array(_flatten_layer_entries(item, default_opacity))
	elif data is String:
		var path := str(data)
		if path != "":
			result.append({
				"path": path,
				"opacity": clampf(default_opacity, 0.0, 1.0)
			})
	elif data is Dictionary:
		var entry := data as Dictionary
		var path: String = str(entry.get("asset", entry.get("path", "")))
		if path != "":
			var opacity: float = clampf(float(entry.get("opacity", default_opacity)), 0.0, 1.0)
			result.append({
				"path": path,
				"opacity": opacity
			})
	return result

func _process(delta: float) -> void:
	# Le background se gère tout seul via ScrollingLayer._process
	_debug_log_frame_hitch(delta)
	_update_hud()

# func _update_background(delta: float) -> void: ... DELETED

func _debug_log_frame_hitch(delta: float) -> void:
	if not DEBUG_PERF_HITCH_LOG:
		return

	var delta_ms: float = delta * 1000.0
	if delta_ms < DEBUG_PERF_HITCH_THRESHOLD_MS:
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_hitch_log_ms < DEBUG_PERF_HITCH_COOLDOWN_MS:
		return
	_last_hitch_log_ms = now_ms

	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var pending_spawns: int = -1
	if wave_manager and wave_manager.has_method("get_pending_spawn_count"):
		pending_spawns = int(wave_manager.call("get_pending_spawn_count"))

	var enemy_projectiles: int = -1
	if ProjectileManager and ProjectileManager.has_method("get_active_enemy_projectile_count"):
		enemy_projectiles = int(ProjectileManager.call("get_active_enemy_projectile_count"))

	var camera_offset: Vector2 = Vector2.ZERO
	if camera:
		camera_offset = camera.offset

	print(
		"[Perf] Hitch dt=", snappedf(delta_ms, 0.1), "ms",
		" enemies=", enemy_count,
		" pending_spawns=", pending_spawns,
		" enemy_projectiles=", enemy_projectiles,
		" cam_offset=", camera_offset
	)

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
	if overlay.has_method("set_display_duration"):
		overlay.call("set_display_duration", _end_screen_delay_seconds)
	hud_container.add_child(overlay)
	
	# After animation, show session report (Loot/Inventory)
	overlay.animation_finished.connect(func():
		if is_instance_valid(overlay):
			overlay.queue_free()
		_show_end_session_screen(false, true)
	)
	
	# Ensure overlay is at the bottom for layering
	hud_container.move_child(overlay, 0)

# =============================================================================
# PROJECTILES
# =============================================================================

func _setup_projectile_manager() -> void:
	ProjectileManager.set_container(game_layer)

func _setup_fluid_simulation() -> void:
	FluidManager.setup(game_layer)

# =============================================================================
# ENEMIES
# =============================================================================

# =============================================================================
# ENEMIES (WAVE SYSTEM)
# =============================================================================

var wave_manager: Node = null

func _start_enemy_spawner() -> void:
	# Instancier le WaveManager
	wave_manager = WAVE_MANAGER_SCRIPT.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	
	wave_manager.spawn_enemy.connect(_on_wave_enemy_spawn)
	wave_manager.spawn_obstacle.connect(_on_wave_obstacle_spawn)
	wave_manager.level_completed.connect(_on_level_completed)
	wave_manager.wave_started.connect(_on_wave_started)
	
	# Démarrer le niveau actuel
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	_prime_runtime_enemy_spawn_costs(level_id)
	_prewarm_level_spawn_assets(level_id)
	_prewarm_runtime_support_assets()
	_configure_wave_counter(level_id)
	_reset_wave_powerup_drop_counters()
	wave_manager.setup(level_id, current_world_id)

func _prime_runtime_enemy_spawn_costs(level_id: String) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var payloads: Array = _build_runtime_enemy_warmup_payloads(level_data)
	if payloads.is_empty():
		return

	var host := Node2D.new()
	host.name = "RuntimeEnemyWarmupHost"
	host.visible = false
	game_layer.add_child(host)

	var patterns_warmed: bool = false
	for payload_variant in payloads:
		if not (payload_variant is Dictionary):
			continue
		var payload: Dictionary = payload_variant as Dictionary
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.visible = false
		host.add_child(enemy)
		enemy.global_position = Vector2(360.0, -280.0)
		enemy.setup(payload)

		# Warm all movement patterns in a real in-scene Enemy instance.
		# This avoids first-use curve fitting/path bake hitch when wave starts.
		if not patterns_warmed:
			var all_patterns: Array = DataManager.get_all_move_patterns()
			for pattern_variant in all_patterns:
				if pattern_variant is Dictionary:
					enemy.call("setup_movement", pattern_variant as Dictionary)
			patterns_warmed = true

		enemy.queue_free()

	host.queue_free()

	if DEBUG_RUNTIME_ENEMY_PREWARM_LOG:
		var elapsed_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		print(
			"[Game] Runtime enemy warmup done in ",
			snappedf(elapsed_ms, 0.1),
			"ms payloads=",
			payloads.size()
		)

func _build_runtime_enemy_warmup_payloads(level_data: Dictionary) -> Array:
	var result: Array = []
	var seen: Dictionary = {}

	var world_skin_overrides: Dictionary = DataManager.get_world_skin_overrides(current_world_id)
	var enemy_overrides: Dictionary = {}
	var raw_enemy_overrides: Variant = world_skin_overrides.get("enemies", {})
	if raw_enemy_overrides is Dictionary:
		enemy_overrides = raw_enemy_overrides as Dictionary

	var waves_variant: Variant = level_data.get("waves", [])
	if not (waves_variant is Array):
		return result

	for wave_variant in (waves_variant as Array):
		if not (wave_variant is Dictionary):
			continue
		var wave: Dictionary = wave_variant as Dictionary
		if str(wave.get("type", "enemy")) == "obstacle":
			continue

		var enemy_id: String = str(wave.get("enemy_id", ""))
		if enemy_id == "":
			continue

		var enemy_skin: String = str(enemy_overrides.get(enemy_id, ""))
		if enemy_skin == "":
			enemy_skin = str(wave.get("enemy_skin", ""))

		var key: String = enemy_id + "|" + enemy_skin
		if seen.has(key):
			continue
		seen[key] = true

		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id).duplicate(true)
		if enemy_data.is_empty():
			continue
		_apply_runtime_enemy_skin_override(enemy_data, enemy_skin)
		result.append(enemy_data)

	return result

func _apply_runtime_enemy_skin_override(enemy_data: Dictionary, enemy_skin: String) -> void:
	if enemy_skin == "":
		return
	if not ResourceLoader.exists(enemy_skin):
		return

	var visual: Dictionary = {}
	var visual_variant: Variant = enemy_data.get("visual", {})
	if visual_variant is Dictionary:
		visual = (visual_variant as Dictionary).duplicate(true)

	var skin_res: Resource = ResourceLoader.load(enemy_skin, "", ResourceLoader.CACHE_MODE_REUSE)
	var ext: String = enemy_skin.get_extension().to_lower()
	var is_frames: bool = (skin_res is SpriteFrames) or ext == "tres" or ext == "res"
	if is_frames:
		visual["asset_anim"] = enemy_skin
		visual["asset"] = ""
	else:
		visual["asset"] = enemy_skin
		visual["asset_anim"] = ""

	enemy_data["visual"] = visual

func _prewarm_level_spawn_assets(level_id: String) -> void:
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var boss_id: String = str(level_data.get("boss_id", ""))
	if boss_id == "":
		return

	var boss_data: Dictionary = DataManager.get_boss(boss_id)
	if boss_data.is_empty():
		return

	var visual_variant: Variant = boss_data.get("visual", {})
	if visual_variant is Dictionary:
		var visual: Dictionary = visual_variant as Dictionary
		_warmup_resource_path(str(visual.get("asset", "")))
		_warmup_resource_path(str(visual.get("asset_anim", "")))
		_warmup_resource_path(str(visual.get("on_death_asset", "")))
		_warmup_resource_path(str(visual.get("on_death_asset_anim", "")))

	var boss_overrides: Variant = _world_skin_overrides.get("bosses", {})
	if boss_overrides is Dictionary:
		_warmup_resource_path(str((boss_overrides as Dictionary).get(boss_id, "")))

func _prewarm_runtime_support_assets() -> void:
	var runtime_paths: Dictionary = {}
	for path_variant in RUNTIME_WARMUP_PATHS:
		var path: String = str(path_variant)
		if path != "":
			runtime_paths[path] = true

	_collect_runtime_support_paths(runtime_paths)
	for path_variant in runtime_paths.keys():
		_warmup_resource_path(str(path_variant))
	_warmup_runtime_support_nodes(runtime_paths)

func _warmup_runtime_support_nodes(runtime_paths: Dictionary) -> void:
	if runtime_paths.is_empty():
		return

	var host := Node2D.new()
	host.name = "RuntimeSupportWarmupHost"
	host.visible = true
	game_layer.add_child(host)

	for path_variant in runtime_paths.keys():
		var path: String = str(path_variant)
		if not _is_runtime_warmup_path(path):
			continue
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		var instance: Node = null
		if resource is PackedScene:
			instance = (resource as PackedScene).instantiate()
		elif resource is Script:
			var script_resource: Script = resource as Script
			if script_resource != null and script_resource.can_instantiate():
				var created: Variant = script_resource.new()
				if created is Node:
					instance = created as Node
		if instance == null:
			continue

		instance.process_mode = Node.PROCESS_MODE_DISABLED
		if instance is CanvasItem:
			(instance as CanvasItem).visible = true
		if instance is Node2D:
			(instance as Node2D).global_position = Vector2(360.0, 360.0)
		host.add_child(instance)
		instance.queue_free()

	host.queue_free()

func _is_runtime_warmup_path(path: String) -> bool:
	if path == "":
		return false
	for prefix_variant in RUNTIME_WARMUP_PREFIXES:
		var prefix: String = str(prefix_variant)
		if path.begins_with(prefix):
			return true
	return false

func _collect_runtime_support_paths(target: Dictionary) -> void:
	var modifiers_data: Variant = _load_json_file("res://data/enemy_modifiers.json")
	_collect_resource_paths_recursive(modifiers_data, target)

	_collect_current_level_wave_assets(target)
	_collect_resource_paths_recursive(DataManager.get_skills_config(), target)
	_collect_resource_paths_recursive(DataManager.get_game_config().get("gameplay", {}), target)
	_collect_resource_paths_recursive(DataManager.get_all_obstacles(), target)

	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/super_powers.json"), target)
	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/unique_powers.json"), target)
	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/boss_powers.json"), target)

func _collect_current_level_wave_assets(target: Dictionary) -> void:
	var level_id: String = current_world_id + "_lvl_" + str(current_level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var waves_variant: Variant = level_data.get("waves", [])
	if waves_variant is Array:
		for wave_variant in (waves_variant as Array):
			_collect_resource_paths_recursive(wave_variant, target)

func _load_json_file(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func _collect_resource_paths_recursive(value: Variant, target: Dictionary) -> void:
	if value is Dictionary:
		for nested in (value as Dictionary).values():
			_collect_resource_paths_recursive(nested, target)
		return
	if value is Array:
		for nested in (value as Array):
			_collect_resource_paths_recursive(nested, target)
		return
	if value is String:
		var path: String = str(value).strip_edges()
		if path.begins_with("res://"):
			target[path] = true

func _warmup_resource_path(path: String) -> void:
	if path == "":
		return
	var was_cached: bool = ResourceLoader.has_cached(path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if DEBUG_LEVEL_WARMUP_LOG:
		if loaded:
			print("[Game] Warmup ", ("reused " if was_cached else "loaded "), path)
		else:
			print("[Game] Warmup failed ", path)

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
	_reset_wave_powerup_drop_counters()
	var current_wave: int = wave_index + 1
	if hud and hud.has_method("update_wave_counter"):
		hud.call("update_wave_counter", current_wave)

func _reset_wave_powerup_drop_counters() -> void:
	_wave_powerup_drop_counts["shield"] = 0
	_wave_powerup_drop_counts["fire_rate"] = 0

func get_loot_drop_rules() -> Dictionary:
	return _loot_drop_rules.duplicate(true)

func can_spawn_powerup_drop(effect: String) -> bool:
	var normalized: String = effect.strip_edges().to_lower()
	if not bool(_loot_drop_rules.get("allow_powerups", true)):
		return false

	match normalized:
		"shield":
			return int(_wave_powerup_drop_counts.get("shield", 0)) < maxi(0, int(_loot_drop_rules.get("max_shield_per_wave", 1)))
		"fire_rate", "rapid_fire":
			return int(_wave_powerup_drop_counts.get("fire_rate", 0)) < maxi(0, int(_loot_drop_rules.get("max_rapid_fire_per_wave", 1)))
		_:
			return true

func try_reserve_powerup_drop(effect: String) -> bool:
	var normalized: String = effect.strip_edges().to_lower()
	if not can_spawn_powerup_drop(normalized):
		return false

	match normalized:
		"shield":
			_wave_powerup_drop_counts["shield"] = int(_wave_powerup_drop_counts.get("shield", 0)) + 1
		"fire_rate", "rapid_fire":
			_wave_powerup_drop_counts["fire_rate"] = int(_wave_powerup_drop_counts.get("fire_rate", 0)) + 1
		_:
			pass
	return true

func _on_wave_enemy_spawn(enemy_data: Dictionary, spawn_pos: Vector2) -> void:
	var t0_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t0_usec = Time.get_ticks_usec()

	# Instancier l'ennemi
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
	var t_instantiate_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_instantiate_usec = Time.get_ticks_usec()
	
	# Scaling basé sur les multipliers du world + progression dans le world
	var level_bonus: float = current_level_index * 0.05
	var hp_mult: float = float(_world_multipliers.get("hp", 1.0)) + level_bonus
	var dmg_mult: float = float(_world_multipliers.get("damage", 1.0)) + level_bonus
	var spd_mult: float = float(_world_multipliers.get("speed", 1.0))
	
	game_layer.add_child(enemy)
	enemy.global_position = spawn_pos
	var t_added_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_added_usec = Time.get_ticks_usec()
	enemy.setup(enemy_data)
	var t_setup_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_setup_usec = Time.get_ticks_usec()
	enemy.apply_stat_multipliers({"hp_mult": hp_mult, "damage_mult": dmg_mult, "speed_mult": spd_mult})
	
	# Connecter le signal de mort
	enemy.enemy_died.connect(_on_enemy_died)

	if DEBUG_SPAWN_PIPELINE_LOG:
		var t_end_usec: int = Time.get_ticks_usec()
		var total_ms: float = float(t_end_usec - t0_usec) / 1000.0
		if total_ms >= DEBUG_SPAWN_PIPELINE_THRESHOLD_MS:
			var instantiate_ms: float = float(t_instantiate_usec - t0_usec) / 1000.0
			var add_ms: float = float(t_added_usec - t_instantiate_usec) / 1000.0
			var setup_ms: float = float(t_setup_usec - t_added_usec) / 1000.0
			var stats_ms: float = float(t_end_usec - t_setup_usec) / 1000.0
			print(
				"[GameSpawn] total=", snappedf(total_ms, 0.1), "ms",
				" instantiate=", snappedf(instantiate_ms, 0.1), "ms",
				" add=", snappedf(add_ms, 0.1), "ms",
				" setup=", snappedf(setup_ms, 0.1), "ms",
				" stats+signals=", snappedf(stats_ms, 0.1), "ms",
				" enemy=", str(enemy_data.get("id", "?")),
				" pattern=", str(enemy_data.get("move_pattern_id", ""))
			)
	# print("[Game] Wave Spawn: ", enemy_data.get("name", "?"))

# =============================================================================
# OBSTACLES (WAVE SYSTEM)
# =============================================================================

const OBSTACLE_EXPLOSIVE_SCENE := preload("res://scenes/obstacles/ObstacleExplosive.tscn")
const OBSTACLE_PUSHER_SCENE := preload("res://scenes/obstacles/ObstaclePusher.tscn")

func _on_wave_obstacle_spawn(obstacle_data: Dictionary, positions: Array, speed: float) -> void:
	var obs_type: String = str(obstacle_data.get("type", "explosive"))
	var drift_dirs: Array = obstacle_data.get("_drift_directions_per_obstacle", [])
	
	for i in range(positions.size()):
		var pos: Variant = positions[i]
		if pos is Vector2:
			var obstacle: Node2D = null
			
			match obs_type:
				"pusher":
					obstacle = OBSTACLE_PUSHER_SCENE.instantiate()
				_:
					obstacle = OBSTACLE_EXPLOSIVE_SCENE.instantiate()
			
			# Injecter la direction de drift individuelle
			var per_obstacle_data: Dictionary = obstacle_data.duplicate()
			if i < drift_dirs.size() and str(drift_dirs[i]) != "":
				per_obstacle_data["_drift_direction"] = str(drift_dirs[i])
			
			# Randomiser les dimensions par obstacle
			_randomize_obstacle_dimensions(per_obstacle_data)
			# Choisir un sprite aléatoire dans l'array
			_pick_random_sprite(per_obstacle_data)
			
			obstacle.global_position = pos as Vector2
			game_layer.add_child(obstacle)
			obstacle.setup(per_obstacle_data, speed)
			
			# Connecter le signal de destruction si destructible
			if obstacle.has_signal("obstacle_destroyed"):
				obstacle.obstacle_destroyed.connect(_on_obstacle_destroyed)

func _randomize_obstacle_dimensions(data: Dictionary) -> void:
	var shape: String = str(data.get("shape", "rectangle"))
	if shape == "circle":
		var r_min: float = float(data.get("radius_min", data.get("radius", 20)))
		var r_max: float = float(data.get("radius_max", data.get("radius", 20)))
		data["radius"] = randf_range(r_min, r_max)
	else:
		var w_min: float = float(data.get("width_min", data.get("width", 200)))
		var w_max: float = float(data.get("width_max", data.get("width", 200)))
		var base_w: float = float(data.get("width", 200))
		var base_h: float = float(data.get("height", 30))
		var ratio: float = base_h / maxf(base_w, 1.0)
		var rand_w: float = randf_range(w_min, w_max)
		data["width"] = rand_w
		data["height"] = rand_w * ratio

func _pick_random_sprite(data: Dictionary) -> void:
	# Check world-level obstacle skin overrides first
	var shape: String = str(data.get("shape", ""))
	var obs_overrides: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides is Dictionary and shape != "":
		var shape_sprites: Variant = (obs_overrides as Dictionary).get(shape, [])
		if shape_sprites is Array:
			var arr: Array = shape_sprites as Array
			if arr.size() > 0:
				data["sprite_path"] = str(arr[randi() % arr.size()])
				return
	
	# Fallback to default sprite_path from obstacles.json
	var sprite_paths: Variant = data.get("sprite_path", "")
	if sprite_paths is Array:
		var arr: Array = sprite_paths as Array
		if arr.size() > 0:
			data["sprite_path"] = str(arr[randi() % arr.size()])
		else:
			data["sprite_path"] = ""
	# Si c'est déjà un String, on le laisse tel quel (compatibilité)

func _on_obstacle_destroyed(_obstacle: Node2D) -> void:
	# Score bonus pour destruction d'obstacles
	if hud and hud.has_method("add_score"):
		hud.add_score(5)

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
	
	# Track XP (Score = XP)
	session_xp += int(enemy.score)
	
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
	
	var boss: CharacterBody2D = BOSS_SCENE.instantiate()
	
	var viewport_width := get_viewport_rect().size.x
	var spawn_pos := Vector2(viewport_width / 2, 100)
	
	game_layer.add_child(boss)
	boss.global_position = spawn_pos
	
	# Apply world-level boss skin override
	var boss_overrides: Variant = _world_skin_overrides.get("bosses", {})
	if boss_overrides is Dictionary:
		var boss_skin: String = str((boss_overrides as Dictionary).get(boss_id, ""))
		if boss_skin != "" and ResourceLoader.exists(boss_skin):
			var visual: Dictionary = boss_data.get("visual", {}).duplicate(true)
			var ext: String = boss_skin.get_extension().to_lower()
			if ext == "tres" or ext == "res":
				visual["asset_anim"] = boss_skin
				visual["asset"] = ""
			else:
				visual["asset"] = boss_skin
				visual["asset_anim"] = ""
			boss_data["visual"] = visual
	
	boss.setup(boss_data)
	
	# Appliquer les multipliers du world au boss
	var boss_hp_mult: float = float(_world_multipliers.get("hp", 1.0))
	if boss_hp_mult != 1.0:
		boss.max_hp = int(boss.max_hp * boss_hp_mult)
		boss.current_hp = boss.max_hp
	
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
	
	# Track XP
	session_xp += int(boss.score)
	
	# Rendre le joueur invincible pour éviter de mourir pendant le popup de loot
	if player:
		player.is_invincible = true
		if player.has_method("set_can_shoot"):
			player.set_can_shoot(false)
	
	active_boss = null
			
	_show_end_session_screen(true)

func _show_end_session_screen(is_victory: bool = true, skip_delay: bool = false) -> void:
	if _end_session_started:
		return
	_end_session_started = true
	
	# Disable spawning/shooting immediately
	if player and player.has_method("set_can_shoot"):
		player.set_can_shoot(false)
	if wave_manager:
		wave_manager.stop()
	if FluidManager.is_active():
		FluidManager.cleanup()
		
	# 1. Feedback
	if hud:
		var txt = "VICTOIRE !" if is_victory else "DÉFAITE..."
		var color = Color.GREEN if is_victory else Color.RED
		VFXManager.spawn_floating_text(player.global_position if is_instance_valid(player) else Vector2(get_viewport_rect().size.x/2, get_viewport_rect().size.y/2), txt, color, hud_container)
	
	if not skip_delay and _end_screen_delay_seconds > 0.0:
		await get_tree().create_timer(_end_screen_delay_seconds).timeout
	
	# --- Skill Tree: Grant session XP ---
	var xp_before := ProfileManager.get_player_xp()
	var level_before := ProfileManager.get_player_level()
	var xp_mult: float = _resolve_session_xp_multiplier()
	var effective_session_xp: int = int(round(float(session_xp) * xp_mult))
	if session_xp > 0:
		ProfileManager.gain_xp(effective_session_xp)
	var xp_after := ProfileManager.get_player_xp()
	var level_after := ProfileManager.get_player_level()
	var xp_gained := effective_session_xp
	var _levels_gained := level_after - level_before
	
	# 2. Main Reward (Boss Loot) - Only on Victory
	var item := {}
	if is_victory:
		_apply_victory_progress()

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

		var utility_bonuses: Dictionary = SkillManager.get_utility_bonuses()
		var extra_loot_chance: float = clampf(float(utility_bonuses.get("boss_extra_loot_chance", 0.0)), 0.0, 1.0)
		if extra_loot_chance > 0.0 and randf() <= extra_loot_chance:
			var bonus_item: LootItem = LootGenerator.generate_boss_loot(target_level, boss_id)
			if bonus_item:
				var bonus_dict: Dictionary = bonus_item.to_dict()
				ProfileManager.add_item_to_inventory(bonus_dict)
				session_loot.append(bonus_dict)
				print("[Game] Bonus boss loot granted by Jackpot skill: ", bonus_dict.get("id", "unknown"))
	
	
	# 3. Setup and show Result Screen
	var nav_context: Dictionary = _resolve_end_screen_navigation(is_victory)
	_end_screen_context_action = str(nav_context.get("action", END_SCREEN_ACTION_LEVEL_SELECT))
	var secondary_label: String = str(nav_context.get("label", "Sélection niveau"))

	var loot_screen_scene := load("res://scenes/LootResultScreen.tscn")
	if loot_screen_scene:
		var loot_screen: Control = loot_screen_scene.instantiate()
		hud_container.add_child(loot_screen)
		loot_screen.setup(item, session_loot, is_victory)
		if loot_screen.has_method("set_navigation_labels"):
			loot_screen.set_navigation_labels(secondary_label, "Menu")
		# Pass XP data for display
		if loot_screen.has_method("set_xp_data"):
			loot_screen.set_xp_data(xp_gained, xp_before, xp_after, level_before, level_after)
		loot_screen.finished.connect(_return_to_home)
		loot_screen.restart_requested.connect(_on_restart_requested)
		loot_screen.exit_requested.connect(_on_end_screen_context_requested)
		if loot_screen.has_signal("menu_requested"):
			loot_screen.menu_requested.connect(_return_to_home)

func _resolve_session_xp_multiplier() -> float:
	if is_instance_valid(player) and player.has_method("get_xp_gain_multiplier"):
		return maxf(1.0, float(player.call("get_xp_gain_multiplier")))

	var active_ship_id := ProfileManager.get_active_ship_id()
	if active_ship_id != "" and StatsCalculator and StatsCalculator.has_method("calculate_ship_stats"):
		var stats: Dictionary = StatsCalculator.calculate_ship_stats(active_ship_id)
		var bonus_pct: float = float(stats.get("xp_multiplier", 0.0))
		return maxf(1.0, 1.0 + (bonus_pct / 100.0))

	return 1.0

func _apply_victory_progress() -> void:
	var levels_per_world: int = max(1, App.get_world_level_count(current_world_id))
	ProfileManager.complete_level(current_world_id, current_level_index, levels_per_world)

	var is_final_level_in_world: bool = current_level_index >= levels_per_world - 1
	if is_final_level_in_world and _has_next_world(current_world_id):
		ProfileManager.unlock_next_world_if_needed(current_world_id)

func _has_next_world(world_id: String) -> bool:
	var worlds: Array = App.get_worlds()
	for i in range(worlds.size()):
		var entry: Variant = worlds[i]
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == world_id:
			return (i + 1) < worlds.size()
	return false

func _resolve_end_screen_navigation(is_victory: bool) -> Dictionary:
	if not is_victory:
		return {
			"action": END_SCREEN_ACTION_LEVEL_SELECT,
			"label": "Sélection niveau"
		}

	var level_count: int = max(1, App.get_world_level_count(current_world_id))
	var has_next_level: bool = (current_level_index + 1) < level_count
	if has_next_level:
		return {
			"action": END_SCREEN_ACTION_NEXT_LEVEL,
			"label": "Niveau suivant"
		}

	return {
		"action": END_SCREEN_ACTION_WORLD_SELECT,
		"label": "Sélection monde"
	}

func _on_end_screen_context_requested() -> void:
	match _end_screen_context_action:
		END_SCREEN_ACTION_NEXT_LEVEL:
			_on_next_level_requested()
		END_SCREEN_ACTION_WORLD_SELECT:
			_on_world_select_requested()
		_:
			_on_level_select_requested()

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

func _on_next_level_requested() -> void:
	get_tree().paused = false

	ProjectileManager.clear_all_projectiles()

	var world_level_count: int = max(1, App.get_world_level_count(current_world_id))
	var next_level_index: int = min(current_level_index + 1, world_level_count - 1)
	App.current_world_id = current_world_id
	App.current_level_index = next_level_index
	current_level_index = next_level_index

	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/Game.tscn")

func _on_world_select_requested() -> void:
	App.play_menu_music()
	get_tree().paused = false

	ProjectileManager.clear_all_projectiles()

	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_quit_requested() -> void:
	_return_to_home()

func _stop_all_timers() -> void:
	for child in get_children():
		if child is Timer:
			child.stop()
