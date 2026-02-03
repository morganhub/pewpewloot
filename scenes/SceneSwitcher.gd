extends Control

## SceneSwitcher — Point d'entrée et gestionnaire de transitions entre écrans.
## Charge le dernier profil utilisé ou redirige vers ProfileSelect.

@onready var screen_root: Control = $ScreenRoot
@onready var fade: ColorRect = $Fade

var current_screen: Node = null

func _ready() -> void:
	# On démarre en noir puis on fade-out après le 1er écran
	fade.color.a = 1.0

	# Charger les profils depuis le disque
	ProfileManager.load_from_disk()
	
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
	if with_fade:
		await _fade_to(1.0)

	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	var packed: PackedScene = load(scene_path)
	current_screen = packed.instantiate()
	screen_root.add_child(current_screen)
	if current_screen is Control:
		current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if with_fade:
		await _fade_to(0.0)

func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, 0.2)
	await tw.finished
