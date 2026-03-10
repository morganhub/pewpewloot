extends Control

const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const H_MARGIN := 36.0
const BOTTOM_MARGIN := 24.0
const TITLE_TO_CAROUSEL_GAP := 14.0
const DETAILS_OVERLAP := 24.0
const DETAILS_GAP := 16.0
const WARNING_GAP := 8.0
const ACTION_BUTTON_HEIGHT := 72.0
const ITEM_HEIGHT_RATIO := 0.9
const ITEM_SPACING := 48.0
const DRAG_THRESHOLD := 12.0
const SNAP_DURATION := 0.24
const MAX_CAROUSEL_HEIGHT := 520.0
const MIN_DETAILS_HEIGHT := 92.0
const MAX_DETAILS_HEIGHT := 200.0
const MIN_ACTION_BUTTON_HEIGHT := 52.0
const HARD_MIN_DETAILS_HEIGHT := 48.0
const HARD_MIN_ACTION_BUTTON_HEIGHT := 40.0
const OVERRIDE_BUTTON_HEIGHT := 56.0
const OVERRIDE_BUTTON_GAP := 10.0
const OVERRIDE_HINT_DURATION := 2.0
const OVERRIDE_POPUP_WIDTH_RATIO := 0.86
const OVERRIDE_POPUP_HEIGHT_RATIO := 0.72

@onready var background: TextureRect = $Background
@onready var back_button: TextureButton = $BackButton
@onready var title_label: Label = $TitleLabel
@onready var carousel_area: Control = $CarouselArea
@onready var carousel_viewport: Control = $CarouselArea/CarouselViewport
@onready var carousel_track: Control = $CarouselArea/CarouselViewport/CarouselTrack
@onready var left_arrow: TextureButton = $CarouselArea/LeftArrow
@onready var right_arrow: TextureButton = $CarouselArea/RightArrow
@onready var details_panel: Control = $DetailsPanel
@onready var details_panel_bg: TextureRect = $DetailsPanel/Background
@onready var details_title: Label = $DetailsPanel/Content/Title
@onready var details_description: Label = $DetailsPanel/Content/Description
@onready var inventory_warning_label: Label = $InventoryWarningLabel
@onready var action_button: Button = $ActionButton

var _game_config: Dictionary = {}
var _world_select_cfg: Dictionary = {}
var _default_card_colors: Array = []
var _items: Array[Dictionary] = []
var _world_data: Dictionary = {}
var world_id := ""

var _current_index := 0
var _item_size := Vector2(700.0, 380.0)
var _track_offset := 0.0
var _track_tween: Tween = null

var _pointer_down := false
var _pointer_id := -1
var _dragging := false
var _drag_start_x := 0.0
var _drag_start_offset := 0.0

var _locked_asset_path := ""
var _locked_opacity := 0.45
var _image_width_pct := 0.52
var _arrow_size := Vector2(82.0, 82.0)
var _reference_aspect_ratio := 0.58
var _back_button_pos := Vector2(35.0, 35.0)
var _back_button_size := Vector2(75.0, 75.0)
var _override_cfg: Dictionary = {}
var _override_ui_settings: Dictionary = {}
var _override_protocols: Array = []
var _active_override_protocol_ids: Array = []
var _override_button: Button = null
var _override_hint_label: Label = null
var _override_popup_overlay: Control = null
var _override_popup_panel: PanelContainer = null
var _override_popup_list: VBoxContainer = null
var _override_popup_summary: Label = null
var _override_checkbox_map: Dictionary = {}
var _override_hint_nonce: int = 0
var _override_button_active_bg: String = ""
var _override_button_inactive_bg: String = ""
var _protocol_settings: Dictionary = {}

func _get_menu_header_offset() -> float:
	var h: Variant = _game_config.get("menu_header", {})
	if h is Dictionary:
		return float(int((h as Dictionary).get("height_px", 72)) + int((h as Dictionary).get("margin_top", 8)))
	return 0.0

func _ready() -> void:
	_load_config()
	App.play_menu_music()
	_setup_static_ui()
	_resolve_world_context()
	_refresh_header_and_background()
	_load_level_items()
	_apply_layout()
	_current_index = _find_last_unlocked_level_index()
	_snap_to_index(_current_index, false)
	_update_inventory_warning_ui()
	_apply_layout()
	_snap_to_index(_current_index, false)
	var mh: Control = get_node_or_null("MenuHeader")
	if mh and mh.has_signal("crystals_pressed") and not mh.crystals_pressed.is_connected(_on_header_crystals_pressed):
		mh.crystals_pressed.connect(_on_header_crystals_pressed)

	# Footer : clic sur le bouton retour du bas
	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)
	if back_button:
		back_button.visible = false

func prepare_for_transition() -> void:
	_kill_track_tween()
	_pointer_down = false
	_dragging = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if not is_node_ready():
			return
		_apply_layout()
		_snap_to_index(_current_index, false)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_pointer_down(e.index, e.position)
		else:
			_on_pointer_up(e.index, e.position)
		return

	if event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		_on_pointer_drag(e.index, e.position)
		return

	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			_on_pointer_down(-999, e.position)
		else:
			_on_pointer_up(-999, e.position)
		return

	if event is InputEventMouseMotion:
		var e := event as InputEventMouseMotion
		if _pointer_down and _pointer_id == -999:
			_on_pointer_drag(-999, e.position)

func _load_config() -> void:
	_game_config = DataManager.get_game_config()
	_protocol_settings = _game_config.get("protocol_settings", {})
	_world_select_cfg = _game_config.get("world_select", {})
	_default_card_colors = _game_config.get(
		"default_card_colors",
		["#3a4f6f", "#6f3a4f", "#4f6f3a", "#6f5a3a"]
	)

	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var details_cfg: Dictionary = {}
	var details_cfg_v: Variant = _world_select_cfg.get("details", {})
	if details_cfg_v is Dictionary:
		details_cfg = details_cfg_v as Dictionary

	_image_width_pct = clampf(float(_world_select_cfg.get("image_width_pct", 0.52)), 0.2, 0.95)

	var arrows_cfg: Dictionary = {}
	var arrows_cfg_v: Variant = _world_select_cfg.get("arrows", {})
	if arrows_cfg_v is Dictionary:
		arrows_cfg = arrows_cfg_v as Dictionary
	var arrow_w := float(arrows_cfg.get("width", 82.0))
	var arrow_h := float(arrows_cfg.get("height", 82.0))
	_arrow_size = Vector2(maxf(24.0, arrow_w), maxf(24.0, arrow_h))

	# Back button top-left is now visual-only (hidden) and kept for layout math
	_back_button_pos = Vector2(35.0, 35.0)
	_back_button_size = Vector2(75.0, 75.0)

	_locked_asset_path = _resolve_asset_path(
		str(_world_select_cfg.get("locked_asset", "res://assets/ui/buttons/locked.png"))
	)
	_locked_opacity = clampf(float(_world_select_cfg.get("locked_opacity", 0.45)), 0.05, 1.0)

	_override_cfg = DataManager.get_override_protocols_config()
	var override_ui_v: Variant = _override_cfg.get("ui_settings", {})
	if override_ui_v is Dictionary:
		_override_ui_settings = (override_ui_v as Dictionary).duplicate(true)
	else:
		_override_ui_settings = {}
	var protocols_v: Variant = _override_cfg.get("protocols", [])
	if protocols_v is Array:
		_override_protocols = (protocols_v as Array).duplicate(true)
	else:
		_override_protocols = []
	_override_button_active_bg = _resolve_asset_path(str(_override_ui_settings.get("button_active_bg", "")))
	_override_button_inactive_bg = _resolve_asset_path(str(_override_ui_settings.get("button_inactive_bg", "")))

	var details_bg_path := _resolve_asset_path(str(details_cfg.get("details_panel_bg", "")))
	if details_bg_path == "":
		details_bg_path = _resolve_asset_path(str(_world_select_cfg.get("details_panel_bg", "")))
	if details_bg_path != "" and ResourceLoader.exists(details_bg_path):
		details_panel_bg.texture = ResourceLoader.load(
			details_bg_path,
			"",
			ResourceLoader.CACHE_MODE_REUSE
		) as Texture2D

	details_title.add_theme_font_size_override(
		"font_size",
		int(details_cfg.get("title_text_size", 30))
	)
	details_description.add_theme_font_size_override(
		"font_size",
		int(details_cfg.get("description_text_size", 20))
	)
	var details_color := _parse_color(details_cfg.get("text_color", "#FFFFFF"), Color.WHITE)
	details_title.add_theme_color_override("font_color", details_color)
	details_description.add_theme_color_override("font_color", details_color)

	var button_bg_path := _resolve_asset_path(str(_world_select_cfg.get("button_bg", "")))
	var validation_cfg: Dictionary = UIStyle.get_validation_config()
	if not validation_cfg.is_empty() and str(validation_cfg.get("asset", "")) != "":
		var v := validation_cfg.duplicate(true)
		v["asset"] = _resolve_asset_path(str(v.get("asset", "")))
		if str(v.get("asset", "")) != "":
			UIStyle.apply_validation_to_button(action_button, v, "large")
	else:
		if button_bg_path != "":
			_apply_button_style(action_button, button_bg_path)
	action_button.add_theme_font_size_override(
		"font_size",
		int(_world_select_cfg.get("button_font_size", 24))
	)
	if validation_cfg.is_empty():
		action_button.add_theme_color_override(
			"font_color",
			_parse_color(_world_select_cfg.get("button_font_color", "#FFFFFF"), Color.WHITE)
		)

	var left_path := _resolve_asset_path(str(_world_select_cfg.get("arrow_left", ui_icons.get("arrow_left", ""))))
	var right_path := _resolve_asset_path(str(_world_select_cfg.get("arrow_right", ui_icons.get("arrow_right", ""))))
	if left_path != "" and ResourceLoader.exists(left_path):
		left_arrow.texture_normal = ResourceLoader.load(left_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if right_path != "" and ResourceLoader.exists(right_path):
		right_arrow.texture_normal = ResourceLoader.load(right_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

func _setup_static_ui() -> void:
	back_button.pressed.connect(_on_back_pressed)
	left_arrow.pressed.connect(_on_left_arrow_pressed)
	right_arrow.pressed.connect(_on_right_arrow_pressed)
	action_button.pressed.connect(_on_action_pressed)

	back_button.ignore_texture_size = true
	back_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	left_arrow.ignore_texture_size = true
	left_arrow.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	right_arrow.ignore_texture_size = true
	right_arrow.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.text = LocaleManager.translate("level_select_play")
	UIStyle.apply_button_shadow(action_button, "large")

	details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_warning_label.visible = false
	_setup_override_controls()

func _setup_override_controls() -> void:
	if _override_button == null:
		_override_button = Button.new()
		_override_button.name = "OverrideButton"
		_override_button.text = LocaleManager.translate("level_select_override_pending")
		_override_button.pressed.connect(_on_override_button_pressed)
		_override_button.add_theme_font_size_override(
			"font_size",
			int(_override_ui_settings.get("item_title_size", 20))
		)
		add_child(_override_button)
		UIStyle.apply_default_button_style(_override_button, "medium")
		UIStyle.apply_button_shadow(_override_button, "medium")

	if _override_hint_label == null:
		_override_hint_label = Label.new()
		_override_hint_label.name = "OverrideHintLabel"
		_override_hint_label.visible = false
		_override_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_override_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_override_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_override_hint_label.add_theme_font_size_override("font_size", 16)
		_override_hint_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
		_override_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_override_hint_label.add_theme_constant_override("outline_size", 2)
		add_child(_override_hint_label)

	if _override_popup_overlay != null:
		return

	_override_popup_overlay = Control.new()
	_override_popup_overlay.name = "OverridePopupOverlay"
	_override_popup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_override_popup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_override_popup_overlay.visible = false
	add_child(_override_popup_overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_override_popup_overlay.add_child(dim)

	_override_popup_panel = PanelContainer.new()
	_override_popup_panel.name = "Panel"
	_override_popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_override_popup_overlay.add_child(_override_popup_panel)
	_apply_override_popup_background()

	# Contenu : marges fixes
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_override_popup_panel.add_child(margin)

	var main := VBoxContainer.new()
	main.name = "Main"
	main.add_theme_constant_override("separation", 12)
	margin.add_child(main)

	# Titre du popup
	var title := Label.new()
	title.name = "Title"
	title.text = LocaleManager.translate("level_select_override_popup_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(_protocol_settings.get("title_size", _override_ui_settings.get("header_font_size", 28))))
	title.add_theme_color_override("font_color", _parse_color(_override_ui_settings.get("header_text_color", "#ffffff"), Color.WHITE))
	main.add_child(title)

	# Résumé (XP / cristaux)
	_override_popup_summary = Label.new()
	_override_popup_summary.name = "Summary"
	_override_popup_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_override_popup_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_override_popup_summary.add_theme_font_size_override("font_size", int(_protocol_settings.get("summary_size", _override_ui_settings.get("summary_font_size", 20))))
	_override_popup_summary.add_theme_color_override("font_color", _parse_color(_override_ui_settings.get("item_title_color", "#C2C9E8"), Color(0.76, 0.79, 0.91)))
	main.add_child(_override_popup_summary)

	# Zone scrollable : liste de boutons protocoles
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(280, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)

	_override_popup_list = VBoxContainer.new()
	_override_popup_list.name = "ProtocolList"
	_override_popup_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_override_popup_list)

	# Footer : Reset + Close (9-slice + shadow 3px comme partout)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 12)
	main.add_child(footer)

	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = LocaleManager.translate("level_select_override_reset")
	reset_btn.pressed.connect(_on_override_reset_pressed)
	UIStyle.apply_default_button_style(reset_btn, "medium")
	UIStyle.apply_button_shadow(reset_btn, "large")
	footer.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = LocaleManager.translate("level_select_override_close")
	close_btn.pressed.connect(_close_override_popup)
	UIStyle.apply_validation_to_button(close_btn, UIStyle.get_validation_config(), "medium")
	UIStyle.apply_button_shadow(close_btn, "large")
	footer.add_child(close_btn)

	dim.gui_input.connect(_on_override_overlay_gui_input)

func _resolve_world_context() -> void:
	world_id = App.current_world_id
	_world_data = App.get_world(world_id)
	if _world_data.is_empty():
		var worlds := App.get_worlds()
		if not worlds.is_empty() and worlds[0] is Dictionary:
			_world_data = worlds[0] as Dictionary
			world_id = str(_world_data.get("id", "world_1"))
			App.current_world_id = world_id

	_active_override_protocol_ids = _sanitize_protocol_selection(
		ProfileManager.get_world_active_override_protocols(world_id)
	)
	App.set_active_override_protocols(_active_override_protocol_ids)

func _refresh_header_and_background() -> void:
	var world_name_key: String = "worlds.%s.name" % world_id
	var world_name: String = LocaleManager.translate(world_name_key)
	if world_name == world_name_key or world_name.is_empty():
		world_name = str(_world_data.get("name", world_id))
	title_label.text = world_name

	var world_theme: Variant = _world_data.get("theme", {})
	var bg_path := ""
	if world_theme is Dictionary:
		bg_path = _resolve_asset_path(str((world_theme as Dictionary).get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_world_select_cfg.get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_game_config.get("main_menu", {}).get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background.texture = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

func _load_level_items() -> void:
	_items.clear()
	for child in carousel_track.get_children():
		child.queue_free()

	var levels_v: Variant = _world_data.get("levels", [])
	if not (levels_v is Array):
		return
	var levels := levels_v as Array
	var max_unlocked := _get_max_unlocked_level()
	var color_count: int = maxi(1, _default_card_colors.size())

	for i in range(levels.size()):
		var lv: Variant = levels[i]
		if not (lv is Dictionary):
			continue
		var level := lv as Dictionary
		var level_name := str(level.get("name", "Level " + str(i + 1)))
		var level_type := str(level.get("type", "normal"))
		if level_type == "boss":
			level_name = "👑 " + level_name
		var fallback_color := str(_default_card_colors[i % color_count])

		var entry := {
			"level_index": i,
			"name": level_name,
			"description": _build_level_description(level, i),
			"asset_path": _resolve_level_asset_path(level),
			"fallback_color": fallback_color,
			"unlocked": i <= max_unlocked or _is_debug_force_unlocked_level(i)
		}
		var node := _create_level_card(entry)
		carousel_track.add_child(node)
		entry["node"] = node
		_items.append(entry)

	_reference_aspect_ratio = 1.0

func _estimate_reference_aspect_ratio() -> float:
	var fallback_ratio := 0.58
	for entry in _items:
		var raw_path := str(entry.get("asset_path", ""))
		if raw_path == "":
			continue
		var ratio := _get_asset_aspect_ratio(raw_path)
		if ratio > 0.0:
			return ratio
	return fallback_ratio

func _get_asset_aspect_ratio(asset_path: String) -> float:
	var resolved_path := _resolve_asset_path(asset_path)
	if resolved_path == "" or not ResourceLoader.exists(resolved_path):
		return 0.0
	var res: Resource = ResourceLoader.load(resolved_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		var tex_size: Vector2 = (res as Texture2D).get_size()
		if tex_size.x > 0.0:
			return tex_size.y / tex_size.x
		return 0.0
	if res is SpriteFrames:
		var frames := res as SpriteFrames
		var anim_name := _get_first_animation_name(frames)
		if anim_name == &"" or frames.get_frame_count(anim_name) <= 0:
			return 0.0
		var frame_tex := frames.get_frame_texture(anim_name, 0)
		if frame_tex == null:
			return 0.0
		var frame_size: Vector2 = frame_tex.get_size()
		if frame_size.x > 0.0:
			return frame_size.y / frame_size.x
	return 0.0

func _resolve_level_asset_path(level: Dictionary) -> String:
	var backgrounds: Variant = level.get("backgrounds", {})
	if backgrounds is Dictionary:
		var bg_dict: Dictionary = backgrounds as Dictionary
		return _resolve_asset_path(str(bg_dict.get("sphere_texture", "")))
	return ""

func _get_level_sphere_texture_path_by_index(level_index: int) -> String:
	var levels_v: Variant = _world_data.get("levels", [])
	if not (levels_v is Array):
		return ""
	var levels: Array = levels_v as Array
	if level_index < 0 or level_index >= levels.size():
		return ""
	var lv: Variant = levels[level_index]
	if not (lv is Dictionary):
		return ""
	return _resolve_level_asset_path(lv as Dictionary)

func _build_level_description(level: Dictionary, index: int) -> String:
	var lore := str(level.get("description", level.get("lore", ""))).strip_edges()
	var tags: Array[String] = []
	var level_type := str(level.get("type", "normal"))
	if level_type == "boss":
		tags.append("BOSS")
	else:
		tags.append("Level " + str(index + 1))
	var duration := int(level.get("duration_sec", 0))
	if duration > 0:
		tags.append(str(duration) + "s")
	var story_id := str(level.get("story_id", ""))
	if story_id != "":
		tags.append("Story")
	var tags_line := " | ".join(tags)
	if lore == "":
		return tags_line
	return lore + "\n" + tags_line

func _create_level_card(entry: Dictionary) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual := Control.new()
	visual.name = "Visual"
	visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(visual)
	_add_level_visual(visual, entry)

	var lock_icon := TextureRect.new()
	lock_icon.name = "LockIcon"
	lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock_icon.set_anchors_preset(Control.PRESET_CENTER)
	lock_icon.custom_minimum_size = Vector2(120, 120)
	lock_icon.size = Vector2(120, 120)
	lock_icon.position = Vector2(-60, -60)
	lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _locked_asset_path != "" and ResourceLoader.exists(_locked_asset_path):
		lock_icon.texture = ResourceLoader.load(
			_locked_asset_path,
			"",
			ResourceLoader.CACHE_MODE_REUSE
		) as Texture2D
	root.add_child(lock_icon)

	var unlocked := bool(entry.get("unlocked", false))
	visual.modulate = Color(1.0, 1.0, 1.0, 1.0 if unlocked else _locked_opacity)
	lock_icon.visible = not unlocked

	return root

func _add_level_visual(parent: Control, entry: Dictionary) -> void:
	var level_index: int = int(entry.get("level_index", 0))
	var sphere_texture_path: String = _get_level_sphere_texture_path_by_index(level_index)
	if sphere_texture_path == "" or not ResourceLoader.exists(sphere_texture_path):
		_add_fallback_level_visual(parent, entry)
		return
	var res: Resource = ResourceLoader.load(sphere_texture_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		var sphere_script: GDScript = load("res://scenes/components/SphereView.gd") as GDScript
		if sphere_script != null:
			var sphere_view: Control = sphere_script.new()
			sphere_view.set_anchors_preset(Control.PRESET_FULL_RECT)
			sphere_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(sphere_view)
			var path_for_sphere: String = _get_level_sphere_texture_path_by_index(level_index)
			push_warning("[LevelSelect] sphere level_index=%s path=%s" % [level_index, path_for_sphere])
			sphere_view.set_texture_path(path_for_sphere)
			return
		var tex_rect := TextureRect.new()
		tex_rect.name = "Texture"
		tex_rect.texture = res as Texture2D
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tex_rect)
		return
	if res is SpriteFrames:
		var anim := AnimatedSprite2D.new()
		anim.name = "Anim"
		anim.centered = true
		anim.sprite_frames = res as SpriteFrames
		var anim_name := _get_first_animation_name(anim.sprite_frames)
		if anim_name != &"":
			anim.play(anim_name)
			anim.animation = anim_name
		parent.add_child(anim)
		return
	_add_fallback_level_visual(parent, entry)


func _add_fallback_level_visual(parent: Control, entry: Dictionary) -> void:
	var fallback := ColorRect.new()
	fallback.color = _parse_color(entry.get("fallback_color", "#3a4f6f"), Color(0.2, 0.25, 0.4, 1.0))
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(fallback)

func _apply_layout() -> void:
	var viewport_size := size
	var content_width := maxf(300.0, viewport_size.x - H_MARGIN * 2.0)
	var header_offset := _get_menu_header_offset()

	back_button.position = _back_button_pos + Vector2(0.0, header_offset)
	back_button.size = _back_button_size
	back_button.custom_minimum_size = _back_button_size

	var title_height := clampf(viewport_size.y * 0.07, 42.0, 66.0)
	var title_top := _back_button_pos.y + _back_button_size.y + 8.0 + header_offset
	title_label.position = Vector2(H_MARGIN, title_top)
	title_label.size = Vector2(content_width, title_height)

	var carousel_top := title_top + title_height + TITLE_TO_CAROUSEL_GAP
	var space_for_block := maxf(0.0, viewport_size.y - BOTTOM_MARGIN - carousel_top)
	var action_height := clampf(ACTION_BUTTON_HEIGHT, MIN_ACTION_BUTTON_HEIGHT, ACTION_BUTTON_HEIGHT)
	var override_height := clampf(OVERRIDE_BUTTON_HEIGHT, HARD_MIN_ACTION_BUTTON_HEIGHT, ACTION_BUTTON_HEIGHT)
	var details_height := clampf(viewport_size.y * 0.2, MIN_DETAILS_HEIGHT, MAX_DETAILS_HEIGHT)
	var warning_height := 34.0 if inventory_warning_label.visible else 0.0
	var non_carousel_space := (details_height - DETAILS_OVERLAP) + DETAILS_GAP + override_height + OVERRIDE_BUTTON_GAP + action_height

	if non_carousel_space > space_for_block:
		var overflow := non_carousel_space - space_for_block
		var details_reducible_soft := maxf(0.0, details_height - MIN_DETAILS_HEIGHT)
		var details_reduce_soft := minf(overflow, details_reducible_soft)
		details_height -= details_reduce_soft
		overflow -= details_reduce_soft

		var action_reducible_soft := maxf(0.0, action_height - MIN_ACTION_BUTTON_HEIGHT)
		var action_reduce_soft := minf(overflow, action_reducible_soft)
		action_height -= action_reduce_soft
		overflow -= action_reduce_soft

		if overflow > 0.0:
			var details_reducible_hard := maxf(0.0, details_height - HARD_MIN_DETAILS_HEIGHT)
			var details_reduce_hard := minf(overflow, details_reducible_hard)
			details_height -= details_reduce_hard
			overflow -= details_reduce_hard

		if overflow > 0.0:
			var action_reducible_hard := maxf(0.0, action_height - HARD_MIN_ACTION_BUTTON_HEIGHT)
			var action_reduce_hard := minf(overflow, action_reducible_hard)
			action_height -= action_reduce_hard
			overflow -= action_reduce_hard

	non_carousel_space = (details_height - DETAILS_OVERLAP) + DETAILS_GAP + override_height + OVERRIDE_BUTTON_GAP + action_height
	var available_for_carousel := maxf(0.0, space_for_block - non_carousel_space)
	var carousel_height := minf(MAX_CAROUSEL_HEIGHT, available_for_carousel)

	carousel_area.position = Vector2(0.0, carousel_top)
	carousel_area.size = Vector2(viewport_size.x, carousel_height)
	carousel_viewport.position = Vector2.ZERO

	left_arrow.custom_minimum_size = _arrow_size
	left_arrow.size = _arrow_size
	left_arrow.position = Vector2(12.0, (carousel_height - _arrow_size.y) * 0.5)
	right_arrow.custom_minimum_size = _arrow_size
	right_arrow.size = _arrow_size
	right_arrow.position = Vector2(
		carousel_area.size.x - _arrow_size.x - 12.0,
		(carousel_height - _arrow_size.y) * 0.5
	)

	var details_width := maxf(280.0, content_width * 0.9)
	details_panel.position = Vector2(
		(viewport_size.x - details_width) * 0.5,
		carousel_area.position.y + carousel_area.size.y - DETAILS_OVERLAP
	)
	details_panel.size = Vector2(details_width, details_height)

	if _override_button != null:
		_override_button.position = Vector2(
			(viewport_size.x - details_width) * 0.5,
			details_panel.position.y + details_height + DETAILS_GAP
		)
		_override_button.size = Vector2(details_width, override_height)

	action_button.position = Vector2(
		(viewport_size.x - details_width) * 0.5,
		details_panel.position.y + details_height + DETAILS_GAP + override_height + OVERRIDE_BUTTON_GAP
	)
	action_button.size = Vector2(details_width, action_height)

	inventory_warning_label.position = Vector2(action_button.position.x, action_button.position.y - warning_height - WARNING_GAP)
	inventory_warning_label.size = Vector2(action_button.size.x, warning_height)
	if _override_hint_label != null:
		var hint_height := maxf(34.0, warning_height)
		_override_hint_label.position = Vector2(
			action_button.position.x,
			(_override_button.position.y if _override_button != null else action_button.position.y) - hint_height - WARNING_GAP
		)
		_override_hint_label.size = Vector2(action_button.size.x, hint_height)

	var desired_item_width := clampf(
		viewport_size.x * _image_width_pct,
		160.0,
		maxf(200.0, carousel_viewport.size.x - 24.0)
	)
	var max_item_height := maxf(120.0, carousel_viewport.size.y * ITEM_HEIGHT_RATIO)
	var desired_item_height := desired_item_width * _reference_aspect_ratio
	_item_size = Vector2(
		desired_item_width,
		clampf(desired_item_height, 120.0, max_item_height)
	)
	_layout_track_items()
	_layout_override_popup(viewport_size)

func _layout_track_items() -> void:
	var total_width := 0.0
	for i in range(_items.size()):
		var entry := _items[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Control):
			continue
		var node := node_v as Control
		node.position = Vector2(i * (_item_size.x + ITEM_SPACING), 0.0)
		node.size = _item_size
		total_width = node.position.x + _item_size.x
		_layout_item_content(node)

	carousel_track.size = Vector2(maxf(total_width, _item_size.x), _item_size.y)
	_apply_track_offset()

func _layout_item_content(card: Control) -> void:
	var visual := card.get_node_or_null("Visual") as Control
	if visual == null:
		return

	var anim := visual.get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null:
		_fit_animated_sprite(anim, card.size)

func _fit_animated_sprite(anim: AnimatedSprite2D, target_size: Vector2) -> void:
	var frames := anim.sprite_frames
	if frames == null:
		return
	var anim_name := anim.animation
	if anim_name == &"":
		anim_name = _get_first_animation_name(frames)
	if anim_name == &"":
		return
	if frames.get_frame_count(anim_name) <= 0:
		return
	var tex := frames.get_frame_texture(anim_name, 0)
	if tex == null:
		return
	var src := tex.get_size()
	if src.x <= 0.0 or src.y <= 0.0:
		return
	var scale_factor := minf(target_size.x / src.x, target_size.y / src.y)
	anim.scale = Vector2.ONE * scale_factor
	anim.position = target_size * 0.5

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_header_crystals_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/ShopMenu.tscn")

func _on_left_arrow_pressed() -> void:
	_snap_to_index(_current_index - 1, true)

func _on_right_arrow_pressed() -> void:
	_snap_to_index(_current_index + 1, true)

func _on_action_pressed() -> void:
	if _items.is_empty():
		return
	var selected := _items[_current_index]
	if not bool(selected.get("unlocked", false)):
		return
	App.set_active_override_protocols(_active_override_protocol_ids)
	App.current_level_index = int(selected.get("level_index", 0))
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/Game.tscn")

func _on_card_tapped(global_pos: Vector2) -> void:
	if _override_popup_overlay != null and _override_popup_overlay.visible:
		return
	if not _is_inside_carousel(global_pos):
		return
	var tapped_index := _find_item_index_at_global_pos(global_pos)
	if tapped_index < 0:
		return
	_snap_to_index(tapped_index, false)
	_on_action_pressed()

func _find_item_index_at_global_pos(global_pos: Vector2) -> int:
	for i in range(_items.size()):
		var item_v: Variant = _items[i].get("node", null)
		if not (item_v is Control):
			continue
		var card := item_v as Control
		var card_rect := Rect2(card.global_position, card.size)
		if card_rect.has_point(global_pos):
			return i
	return -1

func _on_override_button_pressed() -> void:
	if not _is_current_world_override_unlocked():
		_show_override_locked_hint()
		return
	_open_override_popup()

func _on_override_reset_pressed() -> void:
	_active_override_protocol_ids.clear()
	_save_override_selection()
	_refresh_override_popup()
	_refresh_override_ui()

func _on_override_overlay_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _override_popup_panel == null:
		return
	var panel_rect := Rect2(_override_popup_panel.global_position, _override_popup_panel.size)
	if panel_rect.has_point(mouse_event.global_position):
		return
	_close_override_popup()

func _open_override_popup() -> void:
	if _override_popup_overlay == null:
		return
	_refresh_override_popup()
	_override_popup_overlay.visible = true

func _close_override_popup() -> void:
	if _override_popup_overlay == null:
		return
	_override_popup_overlay.visible = false

func _show_override_locked_hint() -> void:
	if _override_hint_label == null:
		return
	_override_hint_nonce += 1
	var nonce := _override_hint_nonce
	_override_hint_label.text = LocaleManager.translate("level_select_override_locked_hint")
	_override_hint_label.visible = true
	get_tree().create_timer(OVERRIDE_HINT_DURATION).timeout.connect(func() -> void:
		if nonce == _override_hint_nonce and _override_hint_label != null:
			_override_hint_label.visible = false
	)

func _on_pointer_down(id: int, global_pos: Vector2) -> void:
	if not _is_inside_carousel(global_pos):
		return
	_pointer_down = true
	_pointer_id = id
	_dragging = false
	_drag_start_x = global_pos.x
	_drag_start_offset = _track_offset
	_kill_track_tween()

func _on_pointer_drag(id: int, global_pos: Vector2) -> void:
	if not _pointer_down or id != _pointer_id:
		return
	var delta_x := global_pos.x - _drag_start_x
	if not _dragging and absf(delta_x) >= DRAG_THRESHOLD:
		_dragging = true
	if not _dragging:
		return
	var bounds := _get_offset_bounds()
	_set_track_offset(clampf(_drag_start_offset + delta_x, bounds.x, bounds.y))
	get_viewport().set_input_as_handled()

func _on_pointer_up(id: int, global_pos: Vector2 = Vector2.ZERO) -> void:
	if not _pointer_down or id != _pointer_id:
		return
	_pointer_down = false
	_pointer_id = -1
	if _dragging:
		_dragging = false
		_snap_to_index(_nearest_index_for_offset(_track_offset), true)
		return
	_on_card_tapped(global_pos)

func _is_inside_carousel(global_pos: Vector2) -> bool:
	var rect := Rect2(carousel_area.global_position, carousel_area.size)
	return rect.has_point(global_pos)

func _snap_to_index(index: int, animated: bool) -> void:
	if _items.is_empty():
		_current_index = 0
		left_arrow.visible = false
		right_arrow.visible = false
		action_button.disabled = true
		return

	_current_index = clampi(index, 0, _items.size() - 1)
	var target_offset := _offset_for_index(_current_index)
	var bounds := _get_offset_bounds()
	target_offset = clampf(target_offset, bounds.x, bounds.y)

	if not animated:
		_set_track_offset(target_offset)
	else:
		_kill_track_tween()
		_track_tween = create_tween()
		_track_tween.set_ease(Tween.EASE_OUT)
		_track_tween.set_trans(Tween.TRANS_QUAD)
		_track_tween.tween_method(_set_track_offset, _track_offset, target_offset, SNAP_DURATION)
		_track_tween.finished.connect(func() -> void:
			_track_tween = null
		)

	_refresh_selection_ui()

func _set_track_offset(value: float) -> void:
	_track_offset = value
	_apply_track_offset()

func _apply_track_offset() -> void:
	var y := (carousel_viewport.size.y - _item_size.y) * 0.5
	carousel_track.position = Vector2(_track_offset, y)

func _offset_for_index(index: int) -> float:
	var center_x := carousel_viewport.size.x * 0.5
	return center_x - (float(index) * (_item_size.x + ITEM_SPACING) + _item_size.x * 0.5)

func _get_offset_bounds() -> Vector2:
	if _items.size() <= 1:
		var centered := _offset_for_index(0)
		return Vector2(centered, centered)
	var first := _offset_for_index(0)
	var last := _offset_for_index(_items.size() - 1)
	return Vector2(minf(first, last), maxf(first, last))

func _nearest_index_for_offset(offset: float) -> int:
	if _items.is_empty():
		return 0
	var best_idx := 0
	var best_dist := INF
	for i in range(_items.size()):
		var dist := absf(offset - _offset_for_index(i))
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx

func _refresh_selection_ui() -> void:
	if _items.is_empty():
		return
	var selected := _items[_current_index]
	details_title.text = str(selected.get("name", ""))
	var desc := str(selected.get("description", "")).strip_edges()
	details_description.text = desc if desc != "" else "-"

	var unlocked := bool(selected.get("unlocked", false))
	action_button.disabled = not unlocked
	UIStyle.set_button_shadow_text(action_button, LocaleManager.translate("level_select_play") if unlocked else _get_locked_label())
	_refresh_override_ui()

	left_arrow.visible = _current_index > 0
	right_arrow.visible = _current_index < _items.size() - 1

func _refresh_override_ui() -> void:
	if _override_button == null:
		return

	var unlocked: bool = _is_current_world_override_unlocked()
	var selected_count: int = _active_override_protocol_ids.size()
	if unlocked:
		UIStyle.set_button_shadow_text(_override_button, LocaleManager.translate(
			"level_select_override_button",
			{"count": str(selected_count)}
		))
		_apply_override_button_style(true)
	else:
		UIStyle.set_button_shadow_text(_override_button, LocaleManager.translate("level_select_override_pending"))
		_apply_override_button_style(false)

func _refresh_override_popup() -> void:
	if _override_popup_list == null:
		return

	_rebuild_override_popup_items()
	if _override_popup_panel != null and _override_popup_list != null:
		var content_w := maxf(260.0, _override_popup_panel.size.x - 32.0)
		_override_popup_list.custom_minimum_size.x = content_w
	if _override_popup_summary == null:
		return

	var selected_count: int = _active_override_protocol_ids.size()
	var reward_multiplier: float = DataManager.get_override_reward_multiplier(selected_count)
	var crystal_multiplier: float = DataManager.get_override_crystal_multiplier(selected_count)
	_override_popup_summary.text = LocaleManager.translate(
		"level_select_override_summary",
		{
			"count": str(selected_count),
			"xp_multiplier": str(snappedf(reward_multiplier, 0.01)),
			"crystal_multiplier": str(snappedf(crystal_multiplier, 0.01))
		}
	)

func _rebuild_override_popup_items() -> void:
	if _override_popup_list == null:
		return

	for child in _override_popup_list.get_children():
		child.queue_free()
	_override_checkbox_map.clear()

	_active_override_protocol_ids = _sanitize_protocol_selection(_active_override_protocol_ids)

	var default_cfg: Dictionary = _game_config.get("buttons", {}).get("default_style", {})
	var btn_min_w := int(default_cfg.get("min_width", 220))
	var btn_min_h := int(default_cfg.get("min_height", 56))

	for protocol_variant in _override_protocols:
		if not (protocol_variant is Dictionary):
			continue
		var protocol_data := protocol_variant as Dictionary
		var protocol_id: String = str(protocol_data.get("id", "")).strip_edges()
		if protocol_id == "":
			continue

		var title_text: String = LocaleManager.translate(str(protocol_data.get("title_key", protocol_id)))
		var description_text: String = LocaleManager.translate(str(protocol_data.get("description_key", "")))
		var is_selected: bool = _active_override_protocol_ids.has(protocol_id)

		var btn := Button.new()
		btn.name = "Protocol_" + protocol_id
		btn.flat = true
		var display_text: String = title_text
		if description_text != "":
			display_text += "\n" + description_text
		btn.text = display_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(btn_min_w, maxi(btn_min_h, 52))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if is_selected:
			UIStyle.apply_validation_to_button(btn, UIStyle.get_validation_config(), "")
		else:
			UIStyle.apply_default_button_style(btn, "medium")

		UIStyle.apply_button_shadow(btn, "large")
		var shadow_lbl: Label = btn.get_node_or_null("ShadowLabel")
		if shadow_lbl != null:
			shadow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			shadow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			shadow_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		btn.pressed.connect(_on_override_protocol_row_pressed.bind(protocol_id))
		_override_popup_list.add_child(btn)
		_override_checkbox_map[protocol_id] = btn

func _on_override_protocol_row_pressed(protocol_id: String) -> void:
	var currently_enabled: bool = _active_override_protocol_ids.has(protocol_id)
	_on_override_protocol_toggled(not currently_enabled, protocol_id)

func _on_override_protocol_toggled(enabled: bool, protocol_id: String) -> void:
	if enabled:
		if not _active_override_protocol_ids.has(protocol_id):
			_active_override_protocol_ids.append(protocol_id)
	else:
		_active_override_protocol_ids.erase(protocol_id)
	_active_override_protocol_ids = _sanitize_protocol_selection(_active_override_protocol_ids)
	_save_override_selection()
	_refresh_override_popup()
	_refresh_override_ui()

func _save_override_selection() -> void:
	ProfileManager.set_world_active_override_protocols(world_id, _active_override_protocol_ids)
	App.set_active_override_protocols(_active_override_protocol_ids)

func _sanitize_protocol_selection(selection: Variant) -> Array:
	var cleaned: Array = []
	var allowed_ids: Dictionary = {}
	for protocol_variant in _override_protocols:
		if protocol_variant is Dictionary:
			var protocol_id: String = str((protocol_variant as Dictionary).get("id", "")).strip_edges()
			if protocol_id != "":
				allowed_ids[protocol_id] = true

	if not (selection is Array):
		return cleaned
	for raw_id in (selection as Array):
		var protocol_id: String = str(raw_id).strip_edges()
		if protocol_id == "":
			continue
		if not allowed_ids.has(protocol_id):
			continue
		if cleaned.has(protocol_id):
			continue
		cleaned.append(protocol_id)
	return cleaned

func _is_current_world_override_unlocked() -> bool:
	return ProfileManager.is_world_cleared(world_id)

func _apply_override_button_style(active: bool) -> void:
	if _override_button == null:
		return
	var style_path: String = _override_button_active_bg if active else _override_button_inactive_bg
	if style_path == "":
		return
	_apply_button_style(_override_button, style_path)

func _apply_override_popup_background() -> void:
	if _override_popup_panel == null:
		return
	var bg_cfg: Variant = _protocol_settings.get("popup_background", {})
	if bg_cfg is Dictionary:
		var cfg: Dictionary = bg_cfg as Dictionary
		var asset: String = _resolve_asset_path(str(cfg.get("asset", "")))
		if asset != "" and ResourceLoader.exists(asset):
			var style: StyleBoxTexture = UIStyle.build_texture_stylebox(asset, cfg, 10)
			if style != null:
				_override_popup_panel.add_theme_stylebox_override("panel", style)
				return
	var popup_bg_path: String = _resolve_asset_path(str(_override_ui_settings.get("popup_bg", "")))
	if popup_bg_path != "" and ResourceLoader.exists(popup_bg_path):
		var texture := ResourceLoader.load(popup_bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if texture != null:
			var style := StyleBoxTexture.new()
			style.texture = texture
			style.texture_margin_left = 24
			style.texture_margin_top = 24
			style.texture_margin_right = 24
			style.texture_margin_bottom = 24
			_override_popup_panel.add_theme_stylebox_override("panel", style)
			return
	var style := _make_override_flat_style(
		_parse_color(str(_override_ui_settings.get("popup_bg_color", "#1a1a2e")), Color(0.1, 0.1, 0.18)),
		16,
		0
	)
	_override_popup_panel.add_theme_stylebox_override("panel", style)

func _make_override_flat_style(bg_color: Color, radius: int, content_margin: int) -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	flat.bg_color = bg_color
	flat.set_corner_radius_all(radius)
	if content_margin > 0:
		flat.content_margin_left = content_margin
		flat.content_margin_right = content_margin
		flat.content_margin_top = content_margin
		flat.content_margin_bottom = content_margin
	return flat

func _apply_override_popup_button_style(button: Button, bg_hex: String, text_color: Color) -> void:
	var style := _make_override_flat_style(Color.from_string(bg_hex, Color(0.2, 0.2, 0.3)), 8, 0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_font_size_override("font_size", 20)

func _layout_override_popup(viewport_size: Vector2) -> void:
	if _override_popup_overlay == null:
		return
	if _override_popup_panel == null:
		return
	var popup_width := viewport_size.x * OVERRIDE_POPUP_WIDTH_RATIO
	var popup_height := viewport_size.y * OVERRIDE_POPUP_HEIGHT_RATIO
	_override_popup_panel.size = Vector2(
		clampf(popup_width, 320.0, viewport_size.x - H_MARGIN * 2.0),
		clampf(popup_height, 320.0, viewport_size.y - BOTTOM_MARGIN * 2.0)
	)
	_override_popup_panel.position = (viewport_size - _override_popup_panel.size) * 0.5
	var content_w := _override_popup_panel.size.x - 32.0
	var scroll_h := maxf(180.0, _override_popup_panel.size.y - 180.0)
	var scroll: ScrollContainer = _override_popup_panel.get_node_or_null("Margin/Main/Scroll")
	if scroll != null:
		scroll.custom_minimum_size = Vector2(content_w, scroll_h)
	if _override_popup_list != null:
		_override_popup_list.custom_minimum_size.x = content_w

func _find_last_unlocked_level_index() -> int:
	if _items.is_empty():
		return 0
	var max_unlocked := _get_max_unlocked_level()
	if _is_debug_force_unlocked_level(_items.size() - 1):
		max_unlocked = maxi(max_unlocked, _items.size() - 1)
	return clampi(max_unlocked, 0, _items.size() - 1)

func _get_max_unlocked_level() -> int:
	var progress := _get_active_progress()
	var world_progress_v: Variant = progress.get(world_id, {})
	if world_progress_v is Dictionary:
		return int((world_progress_v as Dictionary).get("max_unlocked_level", 0))
	return 0

func _is_debug_force_unlocked_level(level_index: int) -> bool:
	return ProfileManager.is_debug_mode_enabled() and world_id == "world_9" and level_index == 6

func _update_inventory_warning_ui() -> void:
	var current_size := ProfileManager.get_unequipped_inventory_count()
	var max_size := ProfileManager.get_max_inventory_size()
	var is_full := current_size >= max_size
	var was_visible := inventory_warning_label.visible
	inventory_warning_label.visible = is_full
	if is_full:
		inventory_warning_label.text = LocaleManager.translate(
			"inventory_full_warning_level_select",
			{"current": str(current_size), "max": str(max_size)}
		)
	if was_visible != is_full:
		_apply_layout()
		_snap_to_index(_current_index, false)

func _get_locked_label() -> String:
	var locked_label := LocaleManager.translate("skills.menu.button.locked")
	return "Locked" if locked_label == "skills.menu.button.locked" else locked_label

func _get_active_progress() -> Dictionary:
	var profile := ProfileManager.get_active_profile()
	var progress_v: Variant = profile.get("progress", {})
	if progress_v is Dictionary:
		return progress_v as Dictionary
	return {}

func _resolve_asset_path(raw_path: String) -> String:
	var clean := raw_path.strip_edges()
	if clean.begins_with("shared:"):
		var shared_id := clean.trim_prefix("shared:")
		clean = DataManager.get_shared_asset_path(shared_id, "")
	return clean

func _parse_color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)

func _apply_button_style(button: Button, texture_path: String) -> void:
	if texture_path == "" or not ResourceLoader.exists(texture_path):
		return
	var texture := ResourceLoader.load(texture_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if texture == null:
		return

	var normal := StyleBoxTexture.new()
	normal.texture = texture
	normal.texture_margin_left = 18
	normal.texture_margin_right = 18
	normal.texture_margin_top = 18
	normal.texture_margin_bottom = 18

	var hover := normal.duplicate() as StyleBoxTexture
	hover.modulate_color = Color(1.08, 1.08, 1.08, 1.0)

	var pressed := normal.duplicate() as StyleBoxTexture
	pressed.modulate_color = Color(0.9, 0.9, 0.9, 1.0)

	var disabled := normal.duplicate() as StyleBoxTexture
	disabled.modulate_color = Color(0.55, 0.55, 0.55, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)

func _get_first_animation_name(frames: SpriteFrames) -> StringName:
	if frames == null:
		return &""
	if frames.has_animation(&"default"):
		return &"default"
	var names := frames.get_animation_names()
	return StringName(names[0]) if not names.is_empty() else &""

func _kill_track_tween() -> void:
	if _track_tween != null and is_instance_valid(_track_tween):
		_track_tween.kill()
	_track_tween = null
