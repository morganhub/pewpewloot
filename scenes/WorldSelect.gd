extends Control

const H_MARGIN := 36.0
const BOTTOM_MARGIN := 24.0
const TITLE_TO_CAROUSEL_GAP := 14.0
const DETAILS_OVERLAP := 24.0
const DETAILS_GAP := 16.0
const ACTION_BUTTON_HEIGHT := 72.0
const ITEM_HEIGHT_RATIO := 0.9
const ITEM_SPACING := 64.0
const DRAG_THRESHOLD := 12.0
const SNAP_DURATION := 0.24
const MAX_CAROUSEL_HEIGHT := 520.0
const MIN_DETAILS_HEIGHT := 92.0
const MAX_DETAILS_HEIGHT := 200.0
const MIN_ACTION_BUTTON_HEIGHT := 52.0
const HARD_MIN_DETAILS_HEIGHT := 48.0
const HARD_MIN_ACTION_BUTTON_HEIGHT := 40.0

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
@onready var action_button: Button = $ActionButton

var _game_config: Dictionary = {}
var _world_select_cfg: Dictionary = {}
var _default_card_colors: Array = []
var _items: Array[Dictionary] = []

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

func _ready() -> void:
	_load_config()
	App.play_menu_music()
	_setup_static_ui()
	_load_world_items()
	_apply_layout()
	_current_index = _find_last_unlocked_world_index()
	_snap_to_index(_current_index, false)
	_check_story_triggers()

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

	var back_cfg: Dictionary = {}
	var back_cfg_v: Variant = _world_select_cfg.get("back_button", {})
	if back_cfg_v is Dictionary:
		back_cfg = back_cfg_v as Dictionary
	_back_button_pos = Vector2(
		float(back_cfg.get("x", 35.0)),
		float(back_cfg.get("y", 35.0))
	)
	_back_button_size = Vector2(
		maxf(24.0, float(back_cfg.get("width", 75.0))),
		maxf(24.0, float(back_cfg.get("height", 75.0)))
	)

	_locked_asset_path = _resolve_asset_path(
		str(_world_select_cfg.get("locked_asset", "res://assets/ui/buttons/locked.png"))
	)
	_locked_opacity = clampf(float(_world_select_cfg.get("locked_opacity", 0.45)), 0.05, 1.0)

	var bg_path := _resolve_asset_path(str(_world_select_cfg.get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_game_config.get("main_menu", {}).get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background.texture = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

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
	if button_bg_path != "":
		_apply_button_style(action_button, button_bg_path)
	action_button.add_theme_font_size_override(
		"font_size",
		int(_world_select_cfg.get("button_font_size", 24))
	)
	action_button.add_theme_color_override(
		"font_color",
		_parse_color(_world_select_cfg.get("button_font_color", "#FFFFFF"), Color.WHITE)
	)

	var back_icon_path := _resolve_asset_path(str(ui_icons.get("back_button", "")))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path):
		back_button.texture_normal = ResourceLoader.load(
			back_icon_path,
			"",
			ResourceLoader.CACHE_MODE_REUSE
		) as Texture2D

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

	title_label.text = LocaleManager.translate("world_select_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.text = LocaleManager.translate("world_select_next")

	details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _load_world_items() -> void:
	_items.clear()
	for child in carousel_track.get_children():
		child.queue_free()

	var progress := _get_active_progress()
	var worlds: Array = App.get_worlds()
	var color_count: int = maxi(1, _default_card_colors.size())

	for i in range(worlds.size()):
		var wv: Variant = worlds[i]
		if not (wv is Dictionary):
			continue
		var world := wv as Dictionary
		var world_id := str(world.get("id", ""))
		var wprog: Variant = progress.get(world_id, {})
		var unlocked := (world_id == "world_1")
		if wprog is Dictionary:
			unlocked = bool((wprog as Dictionary).get("unlocked", unlocked))

		var fallback_color := str(_default_card_colors[i % color_count])
		var entry := {
			"id": world_id,
			"name": str(world.get("name", world_id)),
			"description": str(world.get("description", "")),
			"asset_path": _resolve_world_asset_path(world),
			"fallback_color": fallback_color,
			"unlocked": unlocked
		}

		var node := _create_world_card(entry)
		carousel_track.add_child(node)
		entry["node"] = node
		_items.append(entry)

	_reference_aspect_ratio = _estimate_reference_aspect_ratio()

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

func _resolve_world_asset_path(world: Dictionary) -> String:
	var explicit_path := _resolve_asset_path(str(world.get("image", world.get("preview_asset", ""))))
	if explicit_path != "":
		return explicit_path

	var levels_v: Variant = world.get("levels", [])
	if levels_v is Array and (levels_v as Array).size() > 0:
		var first_level_v: Variant = (levels_v as Array)[0]
		if first_level_v is Dictionary:
			var backgrounds: Variant = (first_level_v as Dictionary).get("backgrounds", {})
			if backgrounds is Dictionary:
				var card_path := _resolve_asset_path(str((backgrounds as Dictionary).get("card", "")))
				if card_path != "":
					return card_path
				var far_path := _resolve_asset_path(str((backgrounds as Dictionary).get("far_layer", "")))
				if far_path != "":
					return far_path

	var world_theme: Variant = world.get("theme", {})
	if world_theme is Dictionary:
		return _resolve_asset_path(str((world_theme as Dictionary).get("background", "")))
	return ""

func _create_world_card(entry: Dictionary) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true

	var visual := Control.new()
	visual.name = "Visual"
	visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(visual)
	_add_world_visual(visual, entry)

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

func _add_world_visual(parent: Control, entry: Dictionary) -> void:
	var asset_path := _resolve_asset_path(str(entry.get("asset_path", "")))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
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

	var fallback := ColorRect.new()
	fallback.color = _parse_color(entry.get("fallback_color", "#3a4f6f"), Color(0.2, 0.25, 0.4, 1.0))
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(fallback)

func _apply_layout() -> void:
	var viewport_size := size
	var content_width := maxf(300.0, viewport_size.x - H_MARGIN * 2.0)

	back_button.position = _back_button_pos
	back_button.size = _back_button_size
	back_button.custom_minimum_size = _back_button_size

	var title_height := clampf(viewport_size.y * 0.07, 42.0, 66.0)
	var title_top := _back_button_pos.y + _back_button_size.y + 8.0
	title_label.position = Vector2(H_MARGIN, title_top)
	title_label.size = Vector2(content_width, title_height)

	var carousel_top := title_top + title_height + TITLE_TO_CAROUSEL_GAP
	var space_for_block := maxf(0.0, viewport_size.y - BOTTOM_MARGIN - carousel_top)
	var action_height := clampf(ACTION_BUTTON_HEIGHT, MIN_ACTION_BUTTON_HEIGHT, ACTION_BUTTON_HEIGHT)
	var details_height := clampf(viewport_size.y * 0.2, MIN_DETAILS_HEIGHT, MAX_DETAILS_HEIGHT)
	var non_carousel_space := (details_height - DETAILS_OVERLAP) + DETAILS_GAP + action_height

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

	non_carousel_space = (details_height - DETAILS_OVERLAP) + DETAILS_GAP + action_height
	var available_for_carousel := maxf(0.0, space_for_block - non_carousel_space)
	var carousel_height := minf(MAX_CAROUSEL_HEIGHT, available_for_carousel)

	carousel_area.position = Vector2(H_MARGIN, carousel_top)
	carousel_area.size = Vector2(content_width, carousel_height)
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

	action_button.position = Vector2(
		(viewport_size.x - details_width) * 0.5,
		details_panel.position.y + details_height + DETAILS_GAP
	)
	action_button.size = Vector2(details_width, action_height)

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
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

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
	App.current_world_id = str(selected.get("id", "world_1"))
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _on_card_tapped(global_pos: Vector2) -> void:
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
	action_button.text = LocaleManager.translate("world_select_next") if unlocked else _get_locked_label()

	left_arrow.visible = _current_index > 0
	right_arrow.visible = _current_index < _items.size() - 1

func _get_locked_label() -> String:
	var locked_label := LocaleManager.translate("skills.menu.button.locked")
	return "Locked" if locked_label == "skills.menu.button.locked" else locked_label

func _find_last_unlocked_world_index() -> int:
	if _items.is_empty():
		return 0
	var last_idx := 0
	for i in range(_items.size()):
		if bool(_items[i].get("unlocked", false)):
			last_idx = i
	return clampi(last_idx, 0, _items.size() - 1)

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

func _check_story_triggers() -> void:
	for world_variant in App.get_worlds():
		if not (world_variant is Dictionary):
			continue
		var story_id := str((world_variant as Dictionary).get("story_id", ""))
		if story_id == "" or ProfileManager.has_viewed_story(story_id):
			continue

		process_mode = Node.PROCESS_MODE_DISABLED
		await StoryManager.play_story(story_id)
		ProfileManager.mark_story_viewed(story_id)
		process_mode = Node.PROCESS_MODE_INHERIT
		break
