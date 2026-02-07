extends Control

## WorldSelect — Sélection du monde avec système de cards.
## Cards cliquables, grisées si bloquées.
## Header: Flèche retour + "Choisir un monde" | Ship + Crystals

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var header: HBoxContainer = $Header
@onready var back_button: Button = $Header/BackButton
@onready var header_title: Label = $Header/HeaderTitle
@onready var header_info: HBoxContainer = $Header/HeaderInfo
@onready var crystal_label: Label = $Header/HeaderInfo/CrystalLabel
@onready var ship_label: Label = $Header/HeaderInfo/ShipLabel

@onready var cards_container: GridContainer = $ScrollContainer/CardsContainer

var _game_config: Dictionary = {}
var _selected_world_id: String = ""

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	App.play_menu_music()
	back_button.pressed.connect(_on_back_pressed)
	
	_update_header()
	_setup_background()
	_load_worlds()
	
	# Back Button Icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.icon = load(back_icon_path)
		back_button.text = ""

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			_game_config = json.data

func _setup_background() -> void:
	var world_select_config: Dictionary = _game_config.get("world_select", {})
	var main_config: Dictionary = _game_config.get("main_menu", {})
	
	var bg_path: String = str(world_select_config.get("background", ""))
	if bg_path == "":
		bg_path = str(main_config.get("background", ""))
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var bg_node = get_node_or_null("Background")
		if bg_node and bg_node is TextureRect:
			bg_node.texture = load(bg_path)

func _update_header() -> void:
	header_title.text = "Choisir un monde"
	
	# Crystals
	var crystals: int = ProfileManager.get_crystals()
	crystal_label.text = "💎 " + str(crystals)
	
	# Ship
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var ship_name := str(ship.get("name", ship_id))
	ship_label.text = "🚀 " + ship_name

func _load_worlds() -> void:
	# Clear existing cards
	for child in cards_container.get_children():
		child.queue_free()
	
	var prog := _get_active_progress()
	var default_colors: Array = _game_config.get("default_card_colors", ["#3a4f6f", "#6f3a4f", "#4f6f3a", "#6f5a3a"])
	
	var color_index := 0
	for w in App.get_worlds():
		var world_id := str(w.get("id", ""))
		var world_name := str(w.get("name", "Unknown"))
		var w_theme: Dictionary = w.get("theme", {})
		var bg_path: String = str(w_theme.get("background", ""))
		var color_palette: String = str(w_theme.get("color_palette", ""))
		
		# Check if unlocked
		var wprog: Variant = prog.get(world_id, {})
		var unlocked := false
		if wprog is Dictionary:
			unlocked = bool((wprog as Dictionary).get("unlocked", false))
		
		# Create card
		var card := _create_world_card(world_id, world_name, bg_path, color_palette, unlocked, default_colors[color_index % default_colors.size()])
		cards_container.add_child(card)
		color_index += 1

func _create_world_card(world_id: String, world_name: String, bg_path: String, color_palette: String, unlocked: bool, fallback_color: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 200)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create internal structure
	var bg_container := Control.new()
	bg_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg_container)
	
	# Background (image or color)
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(bg_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(tex_rect)
	else:
		var bg_color := color_palette if color_palette != "" else fallback_color
		var color_rect := ColorRect.new()
		color_rect.color = Color(bg_color)
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(color_rect)
	
	# Title overlay (bottom with 50% opacity background)
	var title_overlay := ColorRect.new()
	title_overlay.color = Color(0, 0, 0, 0.5)
	title_overlay.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	title_overlay.offset_top = -50
	title_overlay.offset_bottom = 0
	title_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_container.add_child(title_overlay)
	
	var title_label := Label.new()
	title_label.text = world_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.add_theme_font_size_override("font_size", 20)
	title_overlay.add_child(title_label)
	
	# Lock overlay if not unlocked
	if not unlocked:
		var lock_overlay := ColorRect.new()
		lock_overlay.color = Color(0.2, 0.2, 0.2, 0.7)
		lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(lock_overlay)
		
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_label.add_theme_font_size_override("font_size", 48)
		lock_overlay.add_child(lock_label)
	
	# Click detection
	var click_button := Button.new()
	click_button.flat = true
	click_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_button.mouse_filter = Control.MOUSE_FILTER_STOP
	click_button.disabled = not unlocked
	click_button.pressed.connect(_on_world_card_clicked.bind(world_id))
	card.add_child(click_button)
	
	# Store metadata
	card.set_meta("world_id", world_id)
	card.set_meta("unlocked", unlocked)
	
	return card

func _on_world_card_clicked(world_id: String) -> void:
	_selected_world_id = world_id
	App.current_world_id = world_id
	
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _get_active_progress() -> Dictionary:
	var p := ProfileManager.get_active_profile()
	var prog: Variant = p.get("progress", {})
	if prog is Dictionary:
		return prog as Dictionary
	return {}

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/HomeScreen.tscn")
