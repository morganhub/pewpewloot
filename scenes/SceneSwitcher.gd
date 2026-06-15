extends Control

## SceneSwitcher — Point d'entrée et gestionnaire de transitions entre écrans.
## Charge le dernier profil utilisé ou redirige vers ProfileSelect.

const MENU_PREWARM_SCENE_PATHS: PackedStringArray = [
	"res://scenes/WorldSelect.tscn",
	"res://scenes/ShipMenu.tscn",
	"res://scenes/SkillsMenu.tscn",
	"res://scenes/OptionsMenu.tscn",
	"res://scenes/LevelSelect.tscn"
]
const MENU_PREWARM_YIELD_EVERY := 6

@onready var screen_root: Control = $ScreenRoot
@onready var fade: ColorRect = $Fade

var current_screen: Node = null
var _current_screen_path: String = ""
var _screen_before_shop: String = ""
var _prewarmed_screens: Dictionary = {} # scene_path -> PackedScene
var _menu_prewarm_started: bool = false

func _ready() -> void:
	fade.z_index = 1000
	fade.color.a = 1.0

	# Show bootstrap LoadingScreen (bar + main_menu background), load data + scenes, then go to ProfileSelect or HomeScreen
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 1000
	canvas_layer.name = "LoadingLayer"
	add_child(canvas_layer)

	var loading_screen = load("res://scenes/ui/LoadingScreen.tscn").instantiate()
	canvas_layer.add_child(loading_screen)
	loading_screen.start_bootstrap_loading()

	var target_screen_path: String = await loading_screen.bootstrap_completed

	_prepare_current_screen_for_transition()
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	var packed: PackedScene = _get_or_load_menu_scene(target_screen_path)
	if packed != null:
		current_screen = packed.instantiate()
		screen_root.add_child(current_screen)
		if current_screen is Control:
			current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_current_screen_path = target_screen_path
	else:
		push_error("[SceneSwitcher] Failed to load bootstrap scene: " + target_screen_path)

	await loading_screen.fade_out()
	canvas_layer.queue_free()

	await _fade_to(0.0)

func _get_start_screen() -> String:
	# Si un profil actif existe, aller directement à HomeScreen
	if ProfileManager.active_profile_id != "":
		var profile := ProfileManager.get_active_profile()
		if not profile.is_empty():
			print("[SceneSwitcher] Auto-loading profile: ", profile.get("name", "?"))
			return "res://scenes/HomeScreen.tscn"
	
	# Si des profils existent mais aucun n'est actif, aller à ProfileSelect
	if ProfileManager.has_any_profile():
		return "res://scenes/ProfileSelect.tscn"
	
	# Aucun profil, aller à ProfileSelect pour en créer un
	return "res://scenes/ProfileSelect.tscn"

func goto_screen(scene_path: String, with_fade: bool = true) -> void:
	# Only use LoadingScreen for entering the Game scene (slow load, preload needed)
	var is_game_scene = scene_path.to_lower().contains("game.tscn")
	
	if is_game_scene:
		# Use Loading Screen (CanvasLayer with highest layer so it stays on top of Game HUD/StoryOverlay)
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 1000
		canvas_layer.name = "LoadingLayer"
		add_child(canvas_layer)
		
		var loading_screen = load("res://scenes/ui/LoadingScreen.tscn").instantiate()
		canvas_layer.add_child(loading_screen)
		
		# Start loading process (includes fade in)
		loading_screen.start_loading(scene_path)
		
		# Wait for completion signal
		var packed_scene = await loading_screen.loading_completed
		
		_prepare_current_screen_for_transition()
		# Remove old screen
		if current_screen != null:
			current_screen.queue_free()
			current_screen = null
		
		# Instantiate new screen
		if packed_scene:
			current_screen = packed_scene.instantiate()
			screen_root.add_child(current_screen)
			if current_screen is Control:
				current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_current_screen_path = scene_path
		else:
			push_error("[SceneSwitcher] Failed to load scene: " + scene_path)
			
		# Fade out loading screen
		await loading_screen.fade_out()

		# Cleanup loading layer (Game is now visible with its background)
		canvas_layer.queue_free()
		# Ensure loading visuals are fully flushed before post-loading hooks.
		await get_tree().process_frame

		# Pause + story overlay if needed (after loading screen is gone)
		if current_screen != null and current_screen.has_method("run_post_loading_story"):
			await current_screen.run_post_loading_story()
		
	else:
		# Simple Fade Transition for menus (faster, less intrusive)
		var is_shop: bool = scene_path.get_file().to_lower().contains("shopmenu")
		if is_shop and _current_screen_path != "":
			_screen_before_shop = _current_screen_path
		if with_fade:
			await _fade_to(1.0) # Fade to Black

		_prepare_current_screen_for_transition()
		if current_screen != null:
			current_screen.queue_free()
			current_screen = null

		var packed: PackedScene = _get_or_load_menu_scene(scene_path)
		if packed == null:
			push_error("[SceneSwitcher] Failed to load menu scene: " + scene_path)
			if with_fade:
				await _fade_to(0.0)
			return
		current_screen = packed.instantiate()
		screen_root.add_child(current_screen)
		if current_screen is Control:
			current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_current_screen_path = scene_path
			
		if with_fade:
			await _fade_to(0.0) # Fade to Transparent

func get_screen_before_shop() -> String:
	return _screen_before_shop

func _prepare_current_screen_for_transition() -> void:
	if current_screen == null or not is_instance_valid(current_screen):
		return
	if current_screen.has_method("prepare_for_transition"):
		current_screen.call("prepare_for_transition")

func request_menu_prewarm() -> void:
	if _menu_prewarm_started:
		return
	_menu_prewarm_started = true
	call_deferred("_run_menu_prewarm")

func _run_menu_prewarm() -> void:
	for scene_path in MENU_PREWARM_SCENE_PATHS:
		var path: String = str(scene_path)
		if _prewarmed_screens.has(path):
			continue

		var packed: PackedScene = await _load_scene_threaded(path)
		if packed != null:
			_prewarmed_screens[path] = packed
		await get_tree().process_frame

	var warmed_count := 0
	var resource_paths: Array[String] = _build_menu_prewarm_resource_list()
	for path in resource_paths:
		if path == "" or not ResourceLoader.exists(path):
			continue
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		warmed_count += 1
		if warmed_count % MENU_PREWARM_YIELD_EVERY == 0:
			await get_tree().process_frame

func _get_or_load_menu_scene(scene_path: String) -> PackedScene:
	var cached: Variant = _prewarmed_screens.get(scene_path, null)
	if cached is PackedScene:
		return cached as PackedScene
	return _load_scene_sync(scene_path)

func get_menu_prewarm_resource_paths() -> Array:
	return _build_menu_prewarm_resource_list()

func _load_scene_sync(scene_path: String) -> PackedScene:
	if scene_path == "":
		return null
	if not ResourceLoader.exists(scene_path):
		return null
	var resource: Resource = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource is PackedScene:
		return resource as PackedScene
	return null

func _load_scene_threaded(scene_path: String) -> PackedScene:
	if scene_path == "":
		return null
	if not ResourceLoader.exists(scene_path):
		return null

	var request_error = ResourceLoader.load_threaded_request(
		scene_path,
		"",
		false,
		ResourceLoader.CACHE_MODE_REUSE
	)

	if request_error != OK and request_error != ERR_BUSY:
		return _load_scene_sync(scene_path)

	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded: Resource = ResourceLoader.load_threaded_get(scene_path)
			if loaded is PackedScene:
				return loaded as PackedScene
			return _load_scene_sync(scene_path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return _load_scene_sync(scene_path)
		await get_tree().process_frame
	return _load_scene_sync(scene_path)

func _build_menu_prewarm_resource_list() -> Array[String]:
	var ordered_paths: Array[String] = []
	var seen: Dictionary = {}

	var game_cfg: Dictionary = DataManager.get_game_config()
	_collect_resource_paths_recursive(game_cfg.get("main_menu", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("world_select", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("ship_menu", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("SkillsMenu", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("ui_icons", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("buttons", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("popups", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("rarity_frames", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(game_cfg.get("rarity_filter_assets", {}), ordered_paths, seen)
	_collect_resource_paths_recursive(DataManager.get_ships(), ordered_paths, seen)
	_collect_resource_paths_recursive(DataManager.get_skills_config(), ordered_paths, seen)

	var worlds: Array = App.get_worlds()
	for world_variant in worlds:
		if not (world_variant is Dictionary):
			continue
		var world: Dictionary = world_variant as Dictionary
		var _world_theme: Variant = world.get("theme", {})
		if _world_theme is Dictionary:
			_collect_resource_paths_recursive(_world_theme as Dictionary, ordered_paths, seen)

	return ordered_paths

func _collect_resource_paths_recursive(value: Variant, ordered_paths: Array[String], seen: Dictionary) -> void:
	if value is Dictionary:
		for nested_value in (value as Dictionary).values():
			_collect_resource_paths_recursive(nested_value, ordered_paths, seen)
		return

	if value is Array:
		for nested_entry in (value as Array):
			_collect_resource_paths_recursive(nested_entry, ordered_paths, seen)
		return

	if value is String:
		_add_resource_candidate(str(value), ordered_paths, seen)

func _add_resource_candidate(raw_path: String, ordered_paths: Array[String], seen: Dictionary) -> void:
	var normalized: String = _normalize_resource_path(raw_path)
	if normalized == "":
		return
	if seen.has(normalized):
		return
	seen[normalized] = true
	ordered_paths.append(normalized)

func _normalize_resource_path(raw_path: String) -> String:
	var path := raw_path.strip_edges()
	if path == "":
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var lower: String = path.to_lower()
	if not _looks_like_resource_asset(lower):
		return ""
	if path.begins_with("./"):
		path = path.trim_prefix("./")
	if path.begins_with("/"):
		path = path.trim_prefix("/")
	return "res://" + path

func _looks_like_resource_asset(path_lower: String) -> bool:
	return (
		path_lower.ends_with(".png")
		or path_lower.ends_with(".jpg")
		or path_lower.ends_with(".jpeg")
		or path_lower.ends_with(".webp")
		or path_lower.ends_with(".svg")
		or path_lower.ends_with(".tres")
		or path_lower.ends_with(".res")
		or path_lower.ends_with(".tscn")
		or path_lower.ends_with(".gd")
		or path_lower.ends_with(".ogg")
		or path_lower.ends_with(".wav")
		or path_lower.ends_with(".mp3")
		or path_lower.ends_with(".ttf")
		or path_lower.ends_with(".otf")
		or path_lower.ends_with(".fnt")
		or path_lower.ends_with(".shader")
		or path_lower.ends_with(".gdshader")
	)

func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, 0.2)
	await tw.finished
