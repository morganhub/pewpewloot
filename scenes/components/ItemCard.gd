extends PanelContainer

signal card_pressed(item_id: String, slot_id: String)
signal long_pressed(item_id: String, slot_id: String)

@onready var content: Control = $Content
@onready var icon_rect: TextureRect = $Content/Icon
@onready var level_badge: Control = $Content/LevelBadge
@onready var level_label: Label = $Content/LevelBadge/Label
@onready var slot_indicator: Control = $Content/SlotIndicator
@onready var slot_icon: TextureRect = $Content/SlotIndicator/Icon
@onready var action_indicator: Label = $Content/ActionIndicator
@onready var empty_label: Label = $Content/EmptyLabel
@onready var button: Button = $Button

var item_id: String = ""
var slot_id: String = ""
var _press_start_time: int = 0
var _long_press_triggered: bool = false
const LONG_PRESS_DURATION: int = 500 # ms

func _ensure_nodes() -> void:
	if not content: content = $Content
	if not icon_rect: icon_rect = $Content/Icon
	if not level_badge: level_badge = $Content/LevelBadge
	if not level_label: level_label = $Content/LevelBadge/Label
	if not slot_indicator: slot_indicator = $Content/SlotIndicator
	if not slot_icon: slot_icon = $Content/SlotIndicator/Icon
	if not action_indicator: action_indicator = $Content/ActionIndicator
	if not empty_label: empty_label = $Content/EmptyLabel
	if not button: button = $Button

func _ready() -> void:
	_ensure_nodes()
	button.button_down.connect(_on_button_down)
	button.button_up.connect(_on_button_up)

func _process(_delta: float) -> void:
	if _press_start_time > 0 and not _long_press_triggered:
		if Time.get_ticks_msec() - _press_start_time >= LONG_PRESS_DURATION:
			_long_press_triggered = true
			long_pressed.emit(item_id, slot_id)

func _on_button_down() -> void:
	_press_start_time = Time.get_ticks_msec()
	_long_press_triggered = false

func _on_button_up() -> void:
	_press_start_time = 0
	if not _long_press_triggered:
		card_pressed.emit(item_id, slot_id)

# Setup for an item (Inventory or Equipped)
func setup_item(data: Dictionary, p_slot_id: String, config: Dictionary = {}) -> void:
	_ensure_nodes()
	item_id = str(data.get("id", ""))
	slot_id = p_slot_id
	
	# 1. Background (Rarity)
	var rarity = str(data.get("rarity", "common"))
	var bg_asset = ""
	var rarity_frames = config.get("rarity_frames", {})
	bg_asset = str(rarity_frames.get(rarity, ""))
	_set_background(bg_asset)
	
	# 2. Icon
	var icon_path = str(data.get("asset", ""))
	
	# If no valid asset on item, try to resolve from DataManager (Affixes) based on rarity
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		var slot_def = DataManager.get_slot(slot_id)
		var icon_def = slot_def.get("icon")
		if icon_def is Dictionary:
			icon_path = str(icon_def.get(rarity, icon_def.get("common", "")))
		elif icon_def is String:
			icon_path = icon_def

	# Fallback to placeholder if still invalid
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		var placeholders = config.get("placeholders", {})
		icon_path = str(placeholders.get(slot_id, ""))
		

	_set_icon(icon_path)
	
	# Robust Centering & Sizing (80% size = 10% margins)
	# Remove scale/pivot logic which fails if size is 0 initally.
	# Use Anchors instead.
	# Robust Centering & Sizing (Reduced by 15% -> ~68% size)
	# Center = 0.5. Half size = 0.34. Anchors: 0.16 to 0.84.
	icon_rect.use_parent_material = true # Optimization
	icon_rect.anchor_left = 0.2
	icon_rect.anchor_top = 0.2
	icon_rect.anchor_right = 0.8
	icon_rect.anchor_bottom = 0.8
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.scale = Vector2(1, 1) # Reset scale just in case
	icon_rect.pivot_offset = Vector2.ZERO
	# Reset offsets to ensuring anchors work relative to parent (0 margin)
	icon_rect.offset_left = 0
	icon_rect.offset_top = 0
	icon_rect.offset_right = 0
	icon_rect.offset_bottom = 0
	
	# 3. Level Badge
	var level = int(data.get("level", 1))
	_setup_level_badge(level, config.get("level_assets", {}))
	
	# 4. Slot Indicator
	var slot_icons = config.get("slot_icons", {})
	var s_icon_path = str(slot_icons.get(slot_id, ""))
	_setup_slot_indicator(s_icon_path)
	
	# Visibility based on config
	var hide_badges = config.get("hide_badges", false)
	level_badge.visible = not hide_badges
	slot_indicator.visible = not hide_badges
	
	# 5. Upgrade / Action Indicator
	var show_upgrade = config.get("show_upgrade", false)
	action_indicator.visible = show_upgrade
	
	# 6. Empty Label
	empty_label.visible = false

# Setup for empty slot (Equipment)
func setup_empty(p_slot_id: String, slot_name: String, config: Dictionary = {}) -> void:
	_ensure_nodes()
	item_id = ""
	slot_id = p_slot_id
	
	# Style
	var eq_cfg = config.get("equipment_button", {})
	var bg_asset = str(eq_cfg.get("asset", ""))
	_set_background(bg_asset, true)
	
	icon_rect.visible = false
	level_badge.visible = false
	slot_indicator.visible = false
	action_indicator.visible = false
	
	empty_label.visible = true
	empty_label.text = slot_name
	empty_label.add_theme_color_override("font_color", Color.WHITE)

func _set_background(path: String, is_empty: bool = false) -> void:
	if path != "" and ResourceLoader.exists(path):
		var texture_style = StyleBoxTexture.new()
		texture_style.texture = load(path)
		add_theme_stylebox_override("panel", texture_style)
	else:
		var flat_style = StyleBoxFlat.new()
		flat_style.bg_color = Color(0.2, 0.2, 0.2, 1) if is_empty else Color(0.1, 0.1, 0.1, 1)
		flat_style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", flat_style)

func _set_icon(path: String) -> void:
	# Clean up previous animation
	var existing = icon_rect.get_node_or_null("AnimSprite")
	if existing: existing.queue_free()
	
	if path != "" and ResourceLoader.exists(path):
		icon_rect.visible = true
		
		if path.ends_with(".tres") or path.ends_with(".res"):
			var res = load(path)
			if res is SpriteFrames:
				icon_rect.texture = null
				var anim = AnimatedSprite2D.new()
				anim.name = "AnimSprite"
				anim.sprite_frames = res
				anim.play("default") # Assume 'default' animation
				anim.centered = true
				icon_rect.add_child(anim)
				
				# Center the animation
				anim.position = icon_rect.size / 2.0
				# Connect resize to keep centered
				if not icon_rect.resized.is_connected(_on_icon_resized):
					icon_rect.resized.connect(_on_icon_resized)
				return
		
		# Fallback / Normal Texture
		if icon_rect.resized.is_connected(_on_icon_resized):
			icon_rect.resized.disconnect(_on_icon_resized)
		icon_rect.texture = load(path)
	else:
		icon_rect.visible = false

func _on_icon_resized() -> void:
	var anim = icon_rect.get_node_or_null("AnimSprite")
	if anim:
		anim.position = icon_rect.size / 2.0

func _setup_level_badge(level: int, assets: Dictionary) -> void:
	level_label.text = str(level)
	
	# Determine background asset
	var bg_path = ""
	if level <= 2: bg_path = str(assets.get("1-2", ""))
	elif level <= 5: bg_path = str(assets.get("3-5", ""))
	elif level <= 8: bg_path = str(assets.get("6-8", ""))
	else: bg_path = str(assets.get("9", ""))
	
	var badge_bg = level_badge.get_node_or_null("BadgeBG")
	if not badge_bg:
		badge_bg = TextureRect.new()
		badge_bg.name = "BadgeBG"
		badge_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		level_badge.add_child(badge_bg)
		# Ensure behind label
		var lbl = level_badge.get_node("Label")
		if lbl: level_badge.move_child(lbl, -1)
		badge_bg.show_behind_parent = true 
	
	if bg_path != "" and ResourceLoader.exists(bg_path):
		badge_bg.texture = load(bg_path)
		badge_bg.visible = true
	else:
		badge_bg.visible = false
	
	# Size and Font
	var font_sz = int(assets.get("font_size", 16))
	var font_col = Color(str(assets.get("text_color", "#FFFFFF")))
	level_label.add_theme_font_size_override("font_size", font_sz)
	level_label.add_theme_color_override("font_color", font_col)
	
	# INCREASE SIZE BY 20%
	var w = int(assets.get("width", 24)) * 1.2
	var h = int(assets.get("height", 24)) * 1.2
	level_badge.custom_minimum_size = Vector2(w, h)
	
	# Update offsets to center (assumes anchored Top-Left or Top-Center?)
	# If defaults are used, it might be Top-Left. 
	# Let's adjust offset to maintain center but shift UP (-4 px)
	level_badge.offset_left = -w/2.0
	level_badge.offset_right = w/2.0
	level_badge.offset_top = -12 
	level_badge.offset_bottom = h - 12
	
	level_badge.visible = true

func _setup_slot_indicator(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		slot_icon.texture = load(path)
		slot_indicator.visible = true
		
		# ENFORCE SIZE (Same as Level Badge approx, e.g. 48x48)
		# Assuming SlotIndicator is Control. 
		var size_val = 48 # Base 40 * 1.2
		slot_indicator.custom_minimum_size = Vector2(size_val, size_val)
		
		# Move DOWN (+12 px)
		slot_indicator.offset_bottom = 12
		slot_indicator.offset_top = -size_val + 12
		slot_indicator.offset_left = -size_val/2.0
		slot_indicator.offset_right = size_val/2.0
		
	else:
		slot_indicator.visible = false
