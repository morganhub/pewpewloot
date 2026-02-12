extends Control

## SceneSwitcher — Point d'entrée et gestionnaire de transitions entre écrans.
## Charge le dernier profil utilisé ou redirige vers ProfileSelect.

@onready var screen_root: Control = $ScreenRoot
@onready var fade: ColorRect = $Fade

var current_screen: Node = null

func _ready() -> void:
	# On démarre en noir puis on fade-out après le 1er écran
	fade.color.a = 1.0

	# Déterminer l'écran de démarrage
	var start_screen := _get_start_screen()
	goto_screen(start_screen, false)

	# Fade out initial
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
		# Use Loading Screen (CanvasLayer for top-most z-index to cover HUD/etc)
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 100
		canvas_layer.name = "LoadingLayer"
		add_child(canvas_layer)
		
		var loading_screen = load("res://scenes/ui/LoadingScreen.tscn").instantiate()
		canvas_layer.add_child(loading_screen)
		
		# Start loading process (includes fade in)
		loading_screen.start_loading(scene_path)
		
		# Wait for completion signal
		var packed_scene = await loading_screen.loading_completed
		
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
		else:
			push_error("[SceneSwitcher] Failed to load scene: " + scene_path)
			
		# Fade out loading screen
		await loading_screen.fade_out()
		
		# Cleanup
		canvas_layer.queue_free()
		
	else:
		# Simple Fade Transition for menus (faster, less intrusive)
		if with_fade:
			await _fade_to(1.0) # Fade to Black

		if current_screen != null:
			current_screen.queue_free()
			current_screen = null

		var packed: PackedScene = load(scene_path)
		current_screen = packed.instantiate()
		screen_root.add_child(current_screen)
		if current_screen is Control:
			current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			
		if with_fade:
			await _fade_to(0.0) # Fade to Transparent

func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, 0.2)
	await tw.finished
