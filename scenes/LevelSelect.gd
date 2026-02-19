extends Control

## LevelSelect — Sélection du niveau avec système de cards.
## Cards cliquables, grisées si bloquées.
## Header: Flèche retour + "Choisir un niveau" | Ship + Crystals

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var back_button: TextureButton = $TopBar/HeaderLine1/BackButton
@onready var header_title: Label = $TopBar/HeaderLine2/HeaderTitle
@onready var crystal_label: Label = $TopBar/HeaderLine1/HeaderInfo/CrystalLabel
@onready var ship_label: Label = $TopBar/HeaderLine1/HeaderInfo/ShipLabel

@onready var cards_container: GridContainer = $ScrollContainer/CardsContainer

var _game_config: Dictionary = {}
var world_id: String = ""
var _inventory_warning_label: Label = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	App.play_menu_music()
	back_button.pressed.connect(_on_back_pressed)
	
	world_id = App.current_world_id
	
	_update_header()
	_setup_inventory_warning_ui()
	_update_inventory_warning_ui()
	_setup_background()
	_load_levels()
	
	# Back Button Icon
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.texture_normal = load(back_icon_path)

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			_game_config = json.data

func _setup_background() -> void:
	var world := App.get_world(world_id)
	var world_theme: Dictionary = world.get("theme", {})
	var bg_path: String = str(world_theme.get("background", ""))
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var bg_node = get_node_or_null("Background")
		if bg_node and bg_node is TextureRect:
			bg_node.texture = load(bg_path)

func _update_header() -> void:
	var world := App.get_world(world_id)
	var world_name := str(world.get("name", world_id))
	header_title.text = world_name
	
	# Crystals
	var crystals: int = ProfileManager.get_crystals()
	crystal_label.text = "💎 " + str(crystals)
	
	# Ship
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var ship_name := str(ship.get("name", ship_id))
	ship_label.text = "🚀 " + ship_name

func _setup_inventory_warning_ui() -> void:
	var existing_label: Label = get_node_or_null("InventoryWarningLabel") as Label
	if existing_label:
		_inventory_warning_label = existing_label
		return
	
	var warning_label := Label.new()
	warning_label.name = "InventoryWarningLabel"
	warning_label.visible = false
	warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warning_label.z_index = 100
	warning_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	warning_label.offset_top = 112.0
	warning_label.offset_bottom = 138.0
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label.add_theme_font_size_override("font_size", 16)
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2, 1.0))
	warning_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	warning_label.add_theme_constant_override("outline_size", 3)
	add_child(warning_label)
	move_child(warning_label, get_child_count() - 1)
	_inventory_warning_label = warning_label

func _update_inventory_warning_ui() -> void:
	if not _inventory_warning_label:
		return
	var current_size: int = ProfileManager.get_unequipped_inventory_count()
	var max_size: int = ProfileManager.get_max_inventory_size()
	var is_full: bool = current_size >= max_size
	_inventory_warning_label.visible = is_full
	if not is_full:
		return
	_inventory_warning_label.text = LocaleManager.translate(
		"inventory_full_warning_level_select",
		{
			"current": str(current_size),
			"max": str(max_size)
		}
	)

func _load_levels() -> void:
	# Clear existing cards
	for child in cards_container.get_children():
		child.queue_free()
	
	var world := App.get_world(world_id)
	var levels_data: Variant = world.get("levels", [])
	var levels_array: Array = []
	if levels_data is Array:
		levels_array = levels_data as Array
	
	if levels_array.is_empty():
		return
	
	var prog := _get_active_progress()
	var wprog: Variant = prog.get(world_id, {})
	var max_unlocked := 0
	if wprog is Dictionary:
		max_unlocked = int((wprog as Dictionary).get("max_unlocked_level", 0))
	
	var default_colors: Array = _game_config.get("default_card_colors", ["#3a4f6f", "#6f3a4f", "#4f6f3a", "#6f5a3a"])
	
	for i in range(levels_array.size()):
		var level_data: Variant = levels_array[i]
		if not level_data is Dictionary:
			continue
		
		var level_dict := level_data as Dictionary
		var level_name := str(level_dict.get("name", "Niveau " + str(i + 1)))
		var level_type := str(level_dict.get("type", "normal"))
		var backgrounds: Dictionary = level_dict.get("backgrounds", {})
		var card_path: String = str(backgrounds.get("card", ""))
		var far_layer: String = str(backgrounds.get("far_layer", ""))
		
		# If boss level, prefix name
		if level_type == "boss":
			level_name = "👑 " + level_name
		
		# Check if unlocked
		var unlocked := (i <= max_unlocked)
		
		# Use card image, fallback to far_layer, then color
		var bg_path := card_path if card_path != "" else far_layer
		
		# Create card
		var card := _create_level_card(i, level_name, level_type, bg_path, unlocked, default_colors[i % default_colors.size()])
		cards_container.add_child(card)

func _create_level_card(level_index: int, level_name: String, level_type: String, bg_path: String, unlocked: bool, fallback_color: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 180)
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
		var color_rect := ColorRect.new()
		color_rect.color = Color(fallback_color)
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(color_rect)
	
	# Title overlay (bottom with 50% opacity background)
	var title_overlay := ColorRect.new()
	title_overlay.color = Color(0, 0, 0, 0.5)
	title_overlay.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	title_overlay.offset_top = -45
	title_overlay.offset_bottom = 0
	title_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_container.add_child(title_overlay)
	
	var title_label := Label.new()
	title_label.text = level_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.add_theme_font_size_override("font_size", 18)
	title_overlay.add_child(title_label)
	
	# Boss indicator
	if level_type == "boss":
		var boss_badge := ColorRect.new()
		boss_badge.color = Color(0.8, 0.2, 0.2, 0.8)
		boss_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		boss_badge.offset_left = -60
		boss_badge.offset_right = 0
		boss_badge.offset_bottom = 25
		boss_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(boss_badge)
		
		var boss_label := Label.new()
		boss_label.text = "BOSS"
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		boss_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		boss_label.add_theme_font_size_override("font_size", 12)
		boss_badge.add_child(boss_label)
	
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
		lock_label.add_theme_font_size_override("font_size", 40)
		lock_overlay.add_child(lock_label)
	
	# Click detection
	var click_button := Button.new()
	click_button.flat = true
	click_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_button.mouse_filter = Control.MOUSE_FILTER_STOP
	click_button.disabled = not unlocked
	click_button.pressed.connect(_on_level_card_clicked.bind(level_index))
	card.add_child(click_button)
	
	# Store metadata
	card.set_meta("level_index", level_index)
	card.set_meta("unlocked", unlocked)
	
	return card

func _on_level_card_clicked(level_index: int) -> void:
	App.current_level_index = level_index
	
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/Game.tscn")

func _get_active_progress() -> Dictionary:
	var profile := ProfileManager.get_active_profile()
	var prog: Variant = profile.get("progress", {})
	if prog is Dictionary:
		return prog as Dictionary
	return {}

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/WorldSelect.tscn")
