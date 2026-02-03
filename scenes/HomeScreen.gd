extends Control

## HomeScreen — Écran d'accueil après sélection/chargement du profil.
## Affiche le profil actif et le vaisseau sélectionné.
## Navigation: Jouer, Vaisseau, Options, Quitter.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var crystal_label: Label = $MarginContainer/VBoxContainer/CrystalLabel
@onready var profile_label: Label = $MarginContainer/VBoxContainer/ProfileLabel
@onready var ship_label: Label = $MarginContainer/VBoxContainer/ShipLabel
@onready var play_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/PlayButton
@onready var ship_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/ShipButton
@onready var options_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/OptionsButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/QuitButton
@onready var change_profile_button: Button = $MarginContainer/VBoxContainer/ChangeProfileButton

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Connexions
	play_button.pressed.connect(_on_play_pressed)
	ship_button.pressed.connect(_on_ship_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	change_profile_button.pressed.connect(_on_change_profile_pressed)
	
	# Appliquer les traductions et afficher les infos
	_apply_translations()
	_update_info()

func _apply_translations() -> void:
	title_label.text = LocaleManager.t("app_title")
	play_button.text = LocaleManager.t("home_play")
	ship_button.text = LocaleManager.t("home_ship_menu")
	options_button.text = LocaleManager.t("home_options")
	quit_button.text = LocaleManager.t("home_quit")

func _update_info() -> void:
	var profile := ProfileManager.get_active_profile()
	var profile_name := str(profile.get("name", "???"))
	
	# Profil
	profile_label.text = LocaleManager.translate("home_profile", {"name": profile_name})
	
	# Vaisseau actif
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var ship_name := str(ship.get("name", ship_id))
	ship_label.text = LocaleManager.translate("home_ship", {"name": ship_name})
	
	# Bouton changer de profil avec nom du profil actif
	# Bouton changer de profil avec nom du profil actif
	change_profile_button.text = LocaleManager.translate("home_change_profile", {"name": profile_name})
	
	var crystals: int = ProfileManager.get_crystals()
	if crystal_label:
		crystal_label.text = "💎 " + str(crystals)

# =============================================================================
# NAVIGATION
# =============================================================================

func _on_play_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_ship_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/ShipMenu.tscn")

func _on_options_pressed() -> void:
	# Placeholder - Options pas encore implémentées
	pass

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_change_profile_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/ProfileSelect.tscn")
