extends Control

const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const H_MARGIN := 20.0
const STAR_LIST_SIZE := 28.0
const EXPANDED_DETAILS_HEIGHT := 200.0
const EXPAND_DURATION := 0.35
const HOVER_DURATION := 0.12
const OVERRIDE_POPUP_WIDTH_RATIO := 0.86
const OVERRIDE_POPUP_HEIGHT_RATIO := 0.72

@onready var background: TextureRect = $Background
@onready var title_label: Label = $TitleLabel
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var level_list: VBoxContainer = $ScrollContainer/LevelList

var _game_config: Dictionary = {}
var _world_select_cfg: Dictionary = {}
var _level_select_cfg: Dictionary = {}
var _items: Array[Dictionary] = []
var _world_data: Dictionary = {}
var world_id := ""
var _expanded_index: int = -1
var _expand_tween: Tween = null
var _toggle_locked: bool = false

var _locked_asset_path := ""
var _locked_opacity := 0.45

var _card_height := 80.0
var _card_corner_radius := 12
var _overlay_opacity := 0.70
var _hover_translate_y := 4.0
var _frame_tex: Texture2D = null
var _frame_margin := {"top": 4, "right": 4, "bottom": 4, "left": 4}
var _content_margin := {"top": 5, "bottom": 5, "left": 0, "right": 0}
var _details_panel_bg_path := ""
var _details_nine_slice: Dictionary = {}
var _details_content_margin: Dictionary = {}

var _score_cfg: Dictionary = {}
var _score_star_size: Vector2 = Vector2(64.0, 64.0)
var _score_star_empty_tex: Texture2D = null
var _score_star_filled_tex: Texture2D = null

var _override_cfg: Dictionary = {}
var _override_ui_settings: Dictionary = {}
var _override_protocols: Array = []
var _active_override_protocol_ids: Array = []
var _override_popup_overlay: Control = null
var _override_popup_panel: Panel = null
var _override_popup_list: VBoxContainer = null
var _override_popup_summary: Label = null
var _override_checkbox_map: Dictionary = {}
var _override_button_active_bg: String = ""
var _override_button_inactive_bg: String = ""
var _protocol_settings: Dictionary = {}
var _proto_tap_start: Vector2 = Vector2.ZERO
var _proto_tap_item_id: String = ""

func _ready() -> void:
	_load_config()
	App.play_menu_music()
	_resolve_world_context()
	_refresh_header_and_background()
	_load_level_items()
	_apply_layout()
	_setup_override_popup()

	var mh: Control = get_node_or_null("MenuHeader")
	if mh and mh.has_signal("crystals_pressed") and not mh.crystals_pressed.is_connected(_on_header_crystals_pressed):
		mh.crystals_pressed.connect(_on_header_crystals_pressed)

	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)

func prepare_for_transition() -> void:
	_kill_expand_tween()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_node_ready():
			_apply_layout()

func _input(event: InputEvent) -> void:
	var popup_open: bool = _override_popup_overlay != null and _override_popup_overlay.visible
	if not popup_open:
		return

	var pos: Vector2 = Vector2.ZERO
	var is_press: bool = false
	var is_release: bool = false

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pos = touch.position
		is_press = touch.pressed
		is_release = not touch.pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.global_position
			is_press = mb.pressed
			is_release = not mb.pressed

	if is_press:
		_proto_tap_start = pos
		_proto_tap_item_id = _find_protocol_item_at(pos)
	elif is_release:
		if _proto_tap_item_id != "":
			var dist: float = _proto_tap_start.distance_to(pos)
			if dist <= 40.0:
				_on_override_protocol_row_pressed(_proto_tap_item_id)
				get_viewport().set_input_as_handled()
		_proto_tap_item_id = ""
		_proto_tap_start = Vector2.ZERO

# ─── Config ──────────────────────────────────────────────────

func _load_config() -> void:
	_game_config = DataManager.get_game_config()
	_protocol_settings = _game_config.get("protocol_settings", {})
	_world_select_cfg = _game_config.get("world_select", {})
	_level_select_cfg = _game_config.get("level_select", {}) if _game_config.get("level_select") is Dictionary else {}
	_score_cfg = _game_config.get("score_parameters", {}) if _game_config.get("score_parameters") is Dictionary else {}

	var star_size_cfg: Dictionary = _score_cfg.get("star_size", {}) if _score_cfg.get("star_size") is Dictionary else {}
	_score_star_size = Vector2(
		maxf(14.0, float(star_size_cfg.get("x", 64))),
		maxf(14.0, float(star_size_cfg.get("y", 64)))
	)
	var star_empty_path: String = _resolve_asset_path(str(_score_cfg.get("star_empty_asset", "")))
	var star_filled_path: String = _resolve_asset_path(str(_score_cfg.get("star_filled_asset", "")))
	if star_empty_path != "" and ResourceLoader.exists(star_empty_path):
		_score_star_empty_tex = ResourceLoader.load(star_empty_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if star_filled_path != "" and ResourceLoader.exists(star_filled_path):
		_score_star_filled_tex = ResourceLoader.load(star_filled_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

	_locked_asset_path = _resolve_asset_path(
		str(_world_select_cfg.get("locked_asset", "res://assets/ui/buttons/locked.png"))
	)
	_locked_opacity = clampf(float(_world_select_cfg.get("locked_opacity", 0.45)), 0.05, 1.0)

	_card_height = maxf(40.0, float(_level_select_cfg.get("card_height", 80)))
	_card_corner_radius = int(_level_select_cfg.get("card_corner_radius", 12))
	_overlay_opacity = clampf(float(_level_select_cfg.get("overlay_opacity", 0.70)), 0.0, 1.0)
	_hover_translate_y = float(_level_select_cfg.get("hover_translate_y", 4))

	var fm_v: Variant = _level_select_cfg.get("card_frame_margin", {})
	if fm_v is Dictionary:
		_frame_margin = fm_v as Dictionary
	var cm_v: Variant = _level_select_cfg.get("card_content_margin", {})
	if cm_v is Dictionary:
		_content_margin = cm_v as Dictionary

	var frame_path := _resolve_asset_path(str(_level_select_cfg.get("card_frame_asset", "")))
	if frame_path != "" and ResourceLoader.exists(frame_path):
		_frame_tex = ResourceLoader.load(frame_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

	_details_panel_bg_path = _resolve_asset_path(str(_level_select_cfg.get("details_panel_bg", "")))
	var dns_v: Variant = _level_select_cfg.get("details_nine_slice", {})
	_details_nine_slice = dns_v if dns_v is Dictionary else {}
	var dcm_v: Variant = _level_select_cfg.get("details_content_margin", {})
	_details_content_margin = dcm_v if dcm_v is Dictionary else {}

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
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_shadow(title_label)

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

# ─── Level card list ─────────────────────────────────────────

func _load_level_items() -> void:
	_items.clear()
	_expanded_index = -1
	for child in level_list.get_children():
		child.queue_free()

	var levels_v: Variant = _world_data.get("levels", [])
	if not (levels_v is Array):
		return
	var levels := levels_v as Array
	var max_unlocked := _get_max_unlocked_level()

	for i in range(levels.size()):
		var lv: Variant = levels[i]
		if not (lv is Dictionary):
			continue
		var level := lv as Dictionary
		var level_name := str(level.get("name", "Level " + str(i + 1)))
		var level_type := str(level.get("type", "normal"))
		if level_type == "boss":
			level_name = "👑 " + level_name

		var level_id: String = str(level.get("id", world_id + "_lvl_" + str(i)))
		var bg_path := ""
		var bgs_v: Variant = level.get("backgrounds", {})
		if bgs_v is Dictionary:
			bg_path = _resolve_asset_path(str((bgs_v as Dictionary).get("card", "")))

		var unlocked: bool = i <= max_unlocked or _is_debug_force_unlocked_level(i)

		var entry := {
			"level_index": i,
			"level_id": level_id,
			"name": level_name,
			"unlocked": unlocked,
			"bg_path": bg_path,
			"level_data": level,
		}

		var card := _create_level_card(entry)
		level_list.add_child(card)
		entry["node"] = card
		_items.append(entry)

func _create_level_card(entry: Dictionary) -> VBoxContainer:
	var fm_t: float = float(_frame_margin.get("top", 4))
	var fm_r: float = float(_frame_margin.get("right", 4))
	var fm_b: float = float(_frame_margin.get("bottom", 4))
	var fm_l: float = float(_frame_margin.get("left", 4))
	var total_height: float = _card_height + fm_t + fm_b

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	# Header wrapper (fixed-height Control so we can position frame + card)
	var header_wrapper := Control.new()
	header_wrapper.name = "HeaderWrapper"
	header_wrapper.custom_minimum_size = Vector2(0, total_height)
	header_wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(header_wrapper)

	# Frame image behind the card
	if _frame_tex != null:
		var frame_rect := NinePatchRect.new()
		frame_rect.name = "Frame"
		frame_rect.texture = _frame_tex
		frame_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_wrapper.add_child(frame_rect)

	# Inner card
	var card := PanelContainer.new()
	card.name = "Card"
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = fm_l
	card.offset_right = -fm_r
	card.offset_top = fm_t
	card.offset_bottom = fm_t + _card_height
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	flat.set_corner_radius_all(_card_corner_radius)
	flat.content_margin_left = 0
	flat.content_margin_right = 0
	flat.content_margin_top = 0
	flat.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", flat)
	header_wrapper.add_child(card)

	var clip := Control.new()
	clip.name = "Clip"
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(clip)

	var bg_path: String = str(entry.get("bg_path", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex := ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex:
			var bg_rect := TextureRect.new()
			bg_rect.texture = tex
			bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clip.add_child(bg_rect)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, _overlay_opacity)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(overlay)

	# Content with configurable margins
	var cm_t: float = float(_content_margin.get("top", 5))
	var cm_b: float = float(_content_margin.get("bottom", 5))
	var cm_l: float = float(_content_margin.get("left", 0))
	var cm_r: float = float(_content_margin.get("right", 0))

	var hbox := HBoxContainer.new()
	hbox.anchor_left = 0.0
	hbox.anchor_right = 1.0
	hbox.anchor_top = 0.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = cm_l
	hbox.offset_right = -cm_r
	hbox.offset_top = cm_t
	hbox.offset_bottom = -cm_b
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(hbox)

	var ml := Control.new()
	ml.custom_minimum_size = Vector2(16, 0)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(ml)

	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	_apply_label_shadow(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	var stars_hbox := HBoxContainer.new()
	stars_hbox.name = "Stars"
	stars_hbox.alignment = BoxContainer.ALIGNMENT_END
	stars_hbox.add_theme_constant_override("separation", 3)
	stars_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stars_hbox)

	var level_id: String = str(entry.get("level_id", ""))
	var star_count: int = 0
	if ProfileManager and ProfileManager.has_method("get_level_stars"):
		star_count = int(ProfileManager.call("get_level_stars", world_id, level_id))
	_build_star_icons(stars_hbox, star_count, STAR_LIST_SIZE)

	var mr := Control.new()
	mr.custom_minimum_size = Vector2(16, 0)
	mr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(mr)

	var unlocked: bool = bool(entry.get("unlocked", false))
	if not unlocked:
		clip.modulate = Color(1.0, 1.0, 1.0, _locked_opacity)
		var lock_icon := TextureRect.new()
		lock_icon.name = "LockIcon"
		lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_icon.set_anchors_preset(Control.PRESET_CENTER)
		lock_icon.custom_minimum_size = Vector2(48, 48)
		lock_icon.size = Vector2(48, 48)
		lock_icon.position = Vector2(-24, -24)
		lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _locked_asset_path != "" and ResourceLoader.exists(_locked_asset_path):
			lock_icon.texture = ResourceLoader.load(_locked_asset_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		clip.add_child(lock_icon)

	# Details panel (collapsed by default)
	var details := PanelContainer.new()
	details.name = "Details"
	details.visible = false
	details.clip_contents = true
	details.custom_minimum_size = Vector2(0, 0)
	details.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_details_panel_style(details)
	wrapper.add_child(details)

	# Hover translate on the header
	if _hover_translate_y != 0.0:
		header_wrapper.mouse_entered.connect(_on_card_hover_enter.bind(header_wrapper))
		header_wrapper.mouse_exited.connect(_on_card_hover_exit.bind(header_wrapper))

	var level_index: int = int(entry.get("level_index", 0))
	header_wrapper.gui_input.connect(_on_level_header_input.bind(level_index, unlocked))

	return wrapper

func _apply_details_panel_style(panel: PanelContainer) -> void:
	if _details_panel_bg_path != "" and ResourceLoader.exists(_details_panel_bg_path):
		var cfg := {}
		if not _details_nine_slice.is_empty():
			cfg["nine_slice"] = _details_nine_slice
		if not _details_content_margin.is_empty():
			cfg["content_margin"] = _details_content_margin
		var style: StyleBoxTexture = UIStyle.build_texture_stylebox(_details_panel_bg_path, cfg, 12)
		if style != null:
			panel.add_theme_stylebox_override("panel", style)
			return
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	flat.set_corner_radius_all(8)
	flat.content_margin_left = 14
	flat.content_margin_right = 14
	flat.content_margin_top = 10
	flat.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", flat)

func _on_card_hover_enter(card: Control) -> void:
	if not card.has_meta("hover_base_y"):
		card.set_meta("hover_base_y", card.position.y)
	var base_y: float = card.get_meta("hover_base_y")
	_stop_hover_tween(card)
	var tw := card.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card, "position:y", base_y + _hover_translate_y, HOVER_DURATION)
	card.set_meta("hover_tween", tw)

func _on_card_hover_exit(card: Control) -> void:
	if not card.has_meta("hover_base_y"):
		return
	var base_y: float = card.get_meta("hover_base_y")
	_stop_hover_tween(card)
	var tw := card.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card, "position:y", base_y, HOVER_DURATION)
	card.set_meta("hover_tween", tw)

func _stop_hover_tween(card: Control) -> void:
	if not card.has_meta("hover_tween"):
		return
	var old_tw: Variant = card.get_meta("hover_tween")
	if old_tw is Tween and is_instance_valid(old_tw):
		(old_tw as Tween).kill()

# ─── Toggle expand/collapse ──────────────────────────────────

func _on_level_header_input(event: InputEvent, level_index: int, unlocked: bool) -> void:
	if not unlocked or _toggle_locked:
		return
	var should_toggle := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			should_toggle = true
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			should_toggle = true
	if should_toggle:
		_toggle_locked = true
		_toggle_expand(level_index)
		get_viewport().set_input_as_handled()

func _toggle_expand(index: int) -> void:
	_kill_expand_tween()
	if index == _expanded_index:
		_do_collapse(index)
	else:
		var old := _expanded_index
		if old >= 0:
			_do_collapse_instant(old)
		_do_expand(index)

func _do_expand(index: int) -> void:
	if index < 0 or index >= _items.size():
		_toggle_locked = false
		return
	var entry: Dictionary = _items[index]
	var node: VBoxContainer = entry.get("node") as VBoxContainer
	if node == null:
		_toggle_locked = false
		return
	var details: PanelContainer = node.get_node_or_null("Details") as PanelContainer
	if details == null:
		_toggle_locked = false
		return

	_expanded_index = index
	_populate_details(details, entry)
	details.visible = true
	details.custom_minimum_size = Vector2(0, 0)

	var inner: Control = details.get_node_or_null("DetailsInner") as Control
	if inner:
		inner.modulate = Color(1, 1, 1, 0)
		inner.position = Vector2(0, -20)

	_expand_tween = create_tween()
	_expand_tween.set_parallel(true)
	_expand_tween.set_ease(Tween.EASE_IN_OUT)
	_expand_tween.set_trans(Tween.TRANS_CUBIC)
	_expand_tween.tween_property(details, "custom_minimum_size:y", EXPANDED_DETAILS_HEIGHT, EXPAND_DURATION)
	if inner:
		_expand_tween.tween_property(inner, "modulate:a", 1.0, EXPAND_DURATION * 0.7).set_delay(EXPAND_DURATION * 0.15)
		_expand_tween.tween_property(inner, "position:y", 0.0, EXPAND_DURATION)
	_expand_tween.chain().tween_callback(func() -> void:
		_expand_tween = null
		_toggle_locked = false
	)

func _do_collapse(index: int) -> void:
	if index < 0 or index >= _items.size():
		_toggle_locked = false
		return
	var entry: Dictionary = _items[index]
	var node: VBoxContainer = entry.get("node") as VBoxContainer
	if node == null:
		_toggle_locked = false
		return
	var details: PanelContainer = node.get_node_or_null("Details") as PanelContainer
	if details == null:
		_toggle_locked = false
		return

	_expanded_index = -1

	var inner: Control = details.get_node_or_null("DetailsInner") as Control

	_expand_tween = create_tween()
	_expand_tween.set_parallel(true)
	_expand_tween.set_ease(Tween.EASE_IN_OUT)
	_expand_tween.set_trans(Tween.TRANS_CUBIC)
	_expand_tween.tween_property(details, "custom_minimum_size:y", 0.0, EXPAND_DURATION)
	if inner:
		_expand_tween.tween_property(inner, "modulate:a", 0.0, EXPAND_DURATION * 0.5)
		_expand_tween.tween_property(inner, "position:y", -20.0, EXPAND_DURATION)
	_expand_tween.chain().tween_callback(func() -> void:
		details.visible = false
		var inner_node: VBoxContainer = details.get_node_or_null("DetailsInner") as VBoxContainer
		if inner_node:
			for child in inner_node.get_children():
				child.queue_free()
		_expand_tween = null
		_toggle_locked = false
	)

func _do_collapse_instant(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	var entry: Dictionary = _items[index]
	var node: VBoxContainer = entry.get("node") as VBoxContainer
	if node == null:
		return
	var details: PanelContainer = node.get_node_or_null("Details") as PanelContainer
	if details == null:
		return
	details.visible = false
	details.custom_minimum_size = Vector2(0, 0)
	var inner: VBoxContainer = details.get_node_or_null("DetailsInner") as VBoxContainer
	if inner:
		for child in inner.get_children():
			child.queue_free()
	if index == _expanded_index:
		_expanded_index = -1

func _populate_details(details: PanelContainer, entry: Dictionary) -> void:
	# Remove old inner content
	var old_inner: Node = details.get_node_or_null("DetailsInner")
	if old_inner:
		old_inner.queue_free()

	var inner := VBoxContainer.new()
	inner.name = "DetailsInner"
	inner.add_theme_constant_override("separation", 8)
	details.add_child(inner)

	var level_index: int = int(entry.get("level_index", 0))
	var level_id: String = str(entry.get("level_id", ""))
	var level_data: Dictionary = entry.get("level_data", {})

	var padding_top := Control.new()
	padding_top.custom_minimum_size = Vector2(0, 4)
	inner.add_child(padding_top)

	# Score row
	var personal_best: int = 0
	var stars: int = 0
	if ProfileManager:
		if ProfileManager.has_method("get_level_best_score"):
			personal_best = int(ProfileManager.call("get_level_best_score", world_id, level_id))
		if ProfileManager.has_method("get_level_stars"):
			stars = int(ProfileManager.call("get_level_stars", world_id, level_id))

	var score_label := Label.new()
	var best_text: String = _loc("score_personal_best_label", "Meilleur score")
	score_label.text = "%s : %s" % [best_text, str(personal_best) if personal_best > 0 else "-"]
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	_apply_label_shadow(score_label)
	inner.add_child(score_label)

	# Star thresholds
	var s1: int = int(level_data.get("score_1star", 0))
	var s2: int = int(level_data.get("score_2stars", 0))
	var s3: int = int(level_data.get("score_3stars", 0))
	if s1 > 0 or s2 > 0 or s3 > 0:
		var thresholds_vbox := VBoxContainer.new()
		thresholds_vbox.add_theme_constant_override("separation", 2)
		for star_i in range(1, 4):
			var threshold: int = [s1, s2, s3][star_i - 1]
			if threshold <= 0:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var earned_this: bool = stars >= star_i
			_add_star_threshold_row(row, star_i, threshold, earned_this)
			thresholds_vbox.add_child(row)
		inner.add_child(thresholds_vbox)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var proto_count: int = _active_override_protocol_ids.size()
	var proto_btn := Button.new()
	var proto_text: String = LocaleManager.translate("level_select_override_button", {"count": str(proto_count)})
	proto_btn.text = proto_text
	proto_btn.custom_minimum_size = Vector2(0, 48)
	proto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.apply_default_button_style(proto_btn, "medium")
	UIStyle.apply_button_shadow(proto_btn, "medium")
	proto_btn.pressed.connect(_on_override_button_pressed)
	btn_row.add_child(proto_btn)

	var play_btn := Button.new()
	play_btn.text = _loc("level_select_play", "JOUER")
	play_btn.custom_minimum_size = Vector2(0, 48)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var validation_cfg: Dictionary = UIStyle.get_validation_config()
	if not validation_cfg.is_empty() and str(validation_cfg.get("asset", "")) != "":
		var v := validation_cfg.duplicate(true)
		v["asset"] = _resolve_asset_path(str(v.get("asset", "")))
		if str(v.get("asset", "")) != "":
			UIStyle.apply_validation_to_button(play_btn, v, "large")
	else:
		UIStyle.apply_default_button_style(play_btn, "large")
	UIStyle.apply_button_shadow(play_btn, "large")
	play_btn.pressed.connect(_on_play_pressed.bind(level_index))
	btn_row.add_child(play_btn)

	inner.add_child(btn_row)

	# Global best score
	var profile_count: int = 1
	if ProfileManager and ProfileManager.has_method("get_profile_count"):
		profile_count = int(ProfileManager.call("get_profile_count"))
	if profile_count > 1 and ProfileManager and ProfileManager.has_method("get_global_best_score"):
		var global_v: Variant = ProfileManager.call("get_global_best_score", world_id, level_id)
		if global_v is Dictionary:
			var global_dict: Dictionary = global_v as Dictionary
			var global_score: int = int(global_dict.get("score", 0))
			if global_score > 0:
				var holder: String = str(global_dict.get("profile_name", ""))
				if holder == "":
					holder = _loc("score_unknown_profile", "Unknown")
				var global_lbl := Label.new()
				global_lbl.text = "👑 %s: %d (%s)" % [_loc("score_global_best_short", "Global"), global_score, holder]
				global_lbl.add_theme_font_size_override("font_size", 15)
				global_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
				_apply_label_shadow(global_lbl)
				inner.add_child(global_lbl)

func _add_star_threshold_row(row: HBoxContainer, star_count: int, threshold: int, earned: bool) -> void:
	for j in range(star_count):
		var tex: Texture2D = _score_star_filled_tex if earned else _score_star_empty_tex
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(18, 18)
			row.add_child(icon)
		else:
			var fb := Label.new()
			fb.text = "★" if earned else "☆"
			fb.add_theme_font_size_override("font_size", 14)
			row.add_child(fb)

	var thresh_lbl := Label.new()
	thresh_lbl.text = " : %d" % threshold
	thresh_lbl.add_theme_font_size_override("font_size", 16)
	thresh_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0) if not earned else Color(1.0, 0.85, 0.3, 1.0))
	_apply_label_shadow(thresh_lbl)
	row.add_child(thresh_lbl)

func _build_star_icons(container: HBoxContainer, filled_count: int, icon_size: float) -> void:
	for child in container.get_children():
		child.queue_free()
	var clamped: int = clampi(filled_count, 0, 3)
	for i in range(3):
		var filled: bool = i < clamped
		var tex: Texture2D = _score_star_filled_tex if filled else _score_star_empty_tex
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(icon_size, icon_size)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(icon)
		else:
			var fb := Label.new()
			fb.text = "★" if filled else "☆"
			fb.add_theme_font_size_override("font_size", int(maxf(12.0, icon_size * 0.6)))
			fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(fb)

# ─── Play / navigate ─────────────────────────────────────────

func _on_play_pressed(level_index: int) -> void:
	App.set_active_override_protocols(_active_override_protocol_ids)
	App.current_level_index = level_index
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_header_crystals_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/ShopMenu.tscn")

# ─── Layout ──────────────────────────────────────────────────

func _apply_layout() -> void:
	var viewport_size := size
	var header_offset := _get_menu_header_offset()
	var footer_height := _get_menu_footer_height()

	title_label.position = Vector2(H_MARGIN, header_offset + 4.0)
	title_label.size = Vector2(viewport_size.x - H_MARGIN * 2.0, 44.0)

	var scroll_top := header_offset + 52.0
	var scroll_bottom := viewport_size.y - footer_height - 8.0
	scroll_container.position = Vector2(H_MARGIN, scroll_top)
	scroll_container.size = Vector2(viewport_size.x - H_MARGIN * 2.0, maxf(100.0, scroll_bottom - scroll_top))

	level_list.custom_minimum_size.x = viewport_size.x - H_MARGIN * 2.0
	_layout_override_popup(viewport_size)

func _get_menu_header_offset() -> float:
	var h: Variant = _game_config.get("menu_header", {})
	if h is Dictionary:
		return float(int((h as Dictionary).get("height_px", 72)) + int((h as Dictionary).get("margin_top", 8)))
	return 0.0

func _get_menu_footer_height() -> float:
	var footer: Control = get_node_or_null("MenuFooter") as Control
	if footer:
		return footer.size.y
	return 80.0

# ─── Override protocols popup ────────────────────────────────

func _on_override_button_pressed() -> void:
	if not _is_current_world_override_unlocked():
		return
	_open_override_popup()

func _setup_override_popup() -> void:
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

	_override_popup_panel = Panel.new()
	_override_popup_panel.name = "Panel"
	_override_popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_override_popup_overlay.add_child(_override_popup_panel)
	_apply_override_popup_background()

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_override_popup_panel.add_child(margin)

	var main := VBoxContainer.new()
	main.name = "Main"
	main.add_theme_constant_override("separation", 12)
	margin.add_child(main)

	var title := Label.new()
	title.name = "Title"
	title.text = LocaleManager.translate("level_select_override_popup_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(_protocol_settings.get("popup_title_size", 36)))
	title.add_theme_color_override("font_color", _parse_color(_override_ui_settings.get("header_text_color", "#ffffff"), Color.WHITE))
	main.add_child(title)

	_override_popup_summary = Label.new()
	_override_popup_summary.name = "Summary"
	_override_popup_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_override_popup_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_override_popup_summary.add_theme_font_size_override("font_size", int(_protocol_settings.get("text_size", 20)))
	_override_popup_summary.add_theme_color_override("font_color", _parse_color(_override_ui_settings.get("item_title_color", "#C2C9E8"), Color(0.76, 0.79, 0.91)))
	main.add_child(_override_popup_summary)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(280, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)

	_override_popup_list = VBoxContainer.new()
	_override_popup_list.name = "ProtocolList"
	_override_popup_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_override_popup_list)

	var footer_wrapper := MarginContainer.new()
	footer_wrapper.name = "FooterWrapper"
	footer_wrapper.add_theme_constant_override("margin_bottom", 10)
	main.add_child(footer_wrapper)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer_wrapper.add_child(footer)

	var footer_default_cfg: Dictionary = UIStyle.get_default_button_style()
	var footer_btn_min_h: int = int(footer_default_cfg.get("min_height", 56))
	footer.add_theme_constant_override("separation", 10)

	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = LocaleManager.translate("level_select_override_reset")
	reset_btn.pressed.connect(_on_override_reset_pressed)
	reset_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2(0, footer_btn_min_h)
	UIStyle.apply_cancellation_to_button(reset_btn, {}, "medium")
	UIStyle.apply_button_shadow(reset_btn, "large")
	footer.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = LocaleManager.translate("level_select_override_close")
	close_btn.pressed.connect(_close_override_popup)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.custom_minimum_size = Vector2(0, footer_btn_min_h)
	UIStyle.apply_default_button_style(close_btn, "medium")
	UIStyle.apply_button_shadow(close_btn, "large")
	footer.add_child(close_btn)

	dim.gui_input.connect(_on_override_overlay_gui_input)

func _open_override_popup() -> void:
	if _override_popup_overlay == null:
		return
	_refresh_override_popup()
	_override_popup_overlay.visible = true

func _close_override_popup() -> void:
	if _override_popup_overlay == null:
		return
	_override_popup_overlay.visible = false

func _on_override_reset_pressed() -> void:
	_active_override_protocol_ids.clear()
	_save_override_selection()
	_refresh_override_popup()

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

func _refresh_override_popup() -> void:
	if _override_popup_list == null:
		return
	_layout_override_popup(size)
	_rebuild_override_popup_items()
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
	var validation_cfg: Dictionary = UIStyle.get_validation_config()

	var font_presets: Dictionary = {}
	var fp_v: Variant = _game_config.get("buttons", {}).get("font_presets", {})
	if fp_v is Dictionary:
		font_presets = fp_v as Dictionary
	var medium_preset: Dictionary = {}
	var mp_v: Variant = font_presets.get("medium", {})
	if mp_v is Dictionary:
		medium_preset = mp_v as Dictionary
	var small_preset: Dictionary = {}
	var sp_v: Variant = font_presets.get("small", {})
	if sp_v is Dictionary:
		small_preset = sp_v as Dictionary
	var title_font_size: int = int(medium_preset.get("font_size", 26))
	var desc_font_size: int = int(small_preset.get("font_size", 18))

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

		var active_cfg: Dictionary = validation_cfg if is_selected else default_cfg
		var cm_raw: Variant = active_cfg.get("content_margin", {})
		var cm: Dictionary = cm_raw if cm_raw is Dictionary else {}
		var cm_left: int = int(cm.get("left", 12))
		var cm_right: int = int(cm.get("right", 12))
		var cm_top: int = int(cm.get("top", 8))
		var cm_bottom: int = int(cm.get("bottom", 8))

		var item := PanelContainer.new()
		item.name = "Item_" + protocol_id
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var item_style_cfg: Dictionary = validation_cfg if is_selected else default_cfg
		var item_asset: String = _resolve_asset_path(str(item_style_cfg.get("asset", "")))
		if item_asset != "" and ResourceLoader.exists(item_asset):
			var item_style: StyleBoxTexture = UIStyle.build_texture_stylebox(item_asset, item_style_cfg, 10)
			if item_style != null:
				item.add_theme_stylebox_override("panel", item_style)

		var margin_ctr := MarginContainer.new()
		margin_ctr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin_ctr.add_theme_constant_override("margin_left", cm_left)
		margin_ctr.add_theme_constant_override("margin_right", cm_right)
		margin_ctr.add_theme_constant_override("margin_top", cm_top)
		margin_ctr.add_theme_constant_override("margin_bottom", cm_bottom)
		item.add_child(margin_ctr)

		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 4)
		margin_ctr.add_child(vbox)

		var title_color: Color = _parse_color(item_style_cfg.get("text_color", "#FFFFFF"), Color.WHITE)

		var title_lbl := Label.new()
		title_lbl.text = title_text.to_upper()
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.add_theme_font_size_override("font_size", title_font_size)
		title_lbl.add_theme_color_override("font_color", title_color)
		_apply_label_shadow(title_lbl)
		vbox.add_child(title_lbl)

		if description_text != "":
			var desc_lbl := Label.new()
			desc_lbl.text = description_text
			desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			desc_lbl.add_theme_font_size_override("font_size", desc_font_size)
			desc_lbl.add_theme_color_override("font_color", Color(title_color.r, title_color.g, title_color.b, 0.78))
			_apply_label_shadow(desc_lbl)
			vbox.add_child(desc_lbl)

		_override_popup_list.add_child(item)
		_override_checkbox_map[protocol_id] = item

func _find_protocol_item_at(global_pos: Vector2) -> String:
	for pid in _override_checkbox_map:
		var ctrl: Control = _override_checkbox_map[pid] as Control
		if ctrl == null or not is_instance_valid(ctrl) or not ctrl.visible:
			continue
		if Rect2(ctrl.global_position, ctrl.size).has_point(global_pos):
			return str(pid)
	return ""

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
		if protocol_id == "" or not allowed_ids.has(protocol_id) or cleaned.has(protocol_id):
			continue
		cleaned.append(protocol_id)
	return cleaned

func _is_current_world_override_unlocked() -> bool:
	return ProfileManager.is_world_cleared(world_id)

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
			var fallback_style := StyleBoxTexture.new()
			fallback_style.texture = texture
			fallback_style.texture_margin_left = 24
			fallback_style.texture_margin_top = 24
			fallback_style.texture_margin_right = 24
			fallback_style.texture_margin_bottom = 24
			_override_popup_panel.add_theme_stylebox_override("panel", fallback_style)
			return
	var generic_style := StyleBoxFlat.new()
	generic_style.bg_color = _parse_color(str(_override_ui_settings.get("popup_bg_color", "#1a1a2e")), Color(0.1, 0.1, 0.18))
	generic_style.set_corner_radius_all(16)
	_override_popup_panel.add_theme_stylebox_override("panel", generic_style)

func _layout_override_popup(viewport_size: Vector2) -> void:
	if _override_popup_overlay == null or _override_popup_panel == null:
		return
	var popup_width := viewport_size.x * OVERRIDE_POPUP_WIDTH_RATIO
	var popup_height := viewport_size.y * OVERRIDE_POPUP_HEIGHT_RATIO
	_override_popup_panel.size = Vector2(
		clampf(popup_width, 320.0, viewport_size.x - H_MARGIN * 2.0),
		clampf(popup_height, 320.0, viewport_size.y - 48.0)
	)
	_override_popup_panel.position = (viewport_size - _override_popup_panel.size) * 0.5
	var content_w := _override_popup_panel.size.x - 32.0
	var scroll_h := maxf(180.0, _override_popup_panel.size.y - 180.0)
	var scroll: ScrollContainer = _override_popup_panel.get_node_or_null("Margin/Main/Scroll")
	if scroll != null:
		scroll.custom_minimum_size = Vector2(content_w, scroll_h)
	if _override_popup_list != null:
		_override_popup_list.custom_minimum_size.x = content_w

# ─── Utilities ───────────────────────────────────────────────

func _get_max_unlocked_level() -> int:
	var progress := _get_active_progress()
	var world_progress_v: Variant = progress.get(world_id, {})
	if world_progress_v is Dictionary:
		return int((world_progress_v as Dictionary).get("max_unlocked_level", 0))
	return 0

func _is_debug_force_unlocked_level(level_index: int) -> bool:
	return ProfileManager.is_debug_mode_enabled() and world_id == "world_9" and level_index == 6

func _get_active_progress() -> Dictionary:
	var profile := ProfileManager.get_active_profile()
	var progress_v: Variant = profile.get("progress", {})
	if progress_v is Dictionary:
		return progress_v as Dictionary
	return {}

func _loc(key: String, fallback: String) -> String:
	if LocaleManager:
		var translated: String = str(LocaleManager.translate(key))
		if translated != "" and translated != key:
			return translated
	return fallback

func _resolve_asset_path(raw_path: String) -> String:
	var clean := raw_path.strip_edges()
	if clean.begins_with("shared:"):
		var shared_id := clean.trim_prefix("shared:")
		clean = DataManager.get_shared_asset_path(shared_id, "")
	return clean

func _parse_color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)

func _apply_label_shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

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

func _kill_expand_tween() -> void:
	if _expand_tween != null and is_instance_valid(_expand_tween):
		_expand_tween.kill()
	_expand_tween = null
