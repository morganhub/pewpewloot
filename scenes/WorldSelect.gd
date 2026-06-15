extends Control

const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const H_MARGIN := 20.0
const STAR_LIST_SIZE := 28.0
const HOVER_DURATION := 0.12

@onready var background: TextureRect = $Background
@onready var title_label: Label = $TitleLabel
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var world_list: VBoxContainer = $ScrollContainer/WorldList

var _game_config: Dictionary = {}
var _world_select_cfg: Dictionary = {}
var _items: Array[Dictionary] = []
var _locked_asset_path := ""
var _locked_opacity := 0.45
var _score_star_empty_tex: Texture2D = null
var _score_star_filled_tex: Texture2D = null

var _card_height := 80.0
var _card_corner_radius := 12
var _overlay_opacity := 0.70
var _hover_translate_y := 4.0
var _frame_tex: Texture2D = null
var _frame_margin := {"top": 4, "right": 4, "bottom": 4, "left": 4}
var _content_margin := {"top": 5, "bottom": 5, "left": 0, "right": 0}

func _ready() -> void:
	_load_config()
	App.play_menu_music()
	_setup_ui()
	_load_world_items()
	_apply_layout()

	var mh: Control = get_node_or_null("MenuHeader")
	if mh and mh.has_signal("crystals_pressed") and not mh.crystals_pressed.is_connected(_on_header_crystals_pressed):
		mh.crystals_pressed.connect(_on_header_crystals_pressed)

	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)

func prepare_for_transition() -> void:
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_node_ready():
			_apply_layout()

func _load_config() -> void:
	_game_config = DataManager.get_game_config()
	_world_select_cfg = _game_config.get("world_select", {})

	_locked_asset_path = _resolve_asset_path(
		str(_world_select_cfg.get("locked_asset", "res://assets/ui/buttons/locked.png"))
	)
	_locked_opacity = clampf(float(_world_select_cfg.get("locked_opacity", 0.45)), 0.05, 1.0)
	_card_height = maxf(40.0, float(_world_select_cfg.get("card_height", 80)))
	_card_corner_radius = int(_world_select_cfg.get("card_corner_radius", 12))
	_overlay_opacity = clampf(float(_world_select_cfg.get("overlay_opacity", 0.70)), 0.0, 1.0)
	_hover_translate_y = float(_world_select_cfg.get("hover_translate_y", 4))

	var fm_v: Variant = _world_select_cfg.get("card_frame_margin", {})
	if fm_v is Dictionary:
		_frame_margin = fm_v as Dictionary
	var cm_v: Variant = _world_select_cfg.get("card_content_margin", {})
	if cm_v is Dictionary:
		_content_margin = cm_v as Dictionary

	var frame_path := _resolve_asset_path(str(_world_select_cfg.get("card_frame_asset", "")))
	if frame_path != "" and ResourceLoader.exists(frame_path):
		_frame_tex = ResourceLoader.load(frame_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

	var bg_path := _resolve_asset_path(str(_world_select_cfg.get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_game_config.get("main_menu", {}).get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background.texture = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

	var score_cfg: Dictionary = _game_config.get("score_parameters", {}) if _game_config.get("score_parameters") is Dictionary else {}
	var star_empty_path: String = _resolve_asset_path(str(score_cfg.get("star_empty_asset", "")))
	var star_filled_path: String = _resolve_asset_path(str(score_cfg.get("star_filled_asset", "")))
	if star_empty_path != "" and ResourceLoader.exists(star_empty_path):
		_score_star_empty_tex = ResourceLoader.load(star_empty_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if star_filled_path != "" and ResourceLoader.exists(star_filled_path):
		_score_star_filled_tex = ResourceLoader.load(star_filled_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

func _setup_ui() -> void:
	title_label.text = LocaleManager.translate("world_select_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_shadow(title_label)

func _load_world_items() -> void:
	_items.clear()
	for child in world_list.get_children():
		child.queue_free()

	var progress := _get_active_progress()
	var worlds: Array = App.get_worlds()

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
		if ProfileManager.is_debug_mode_enabled() and world_id == "world_9":
			unlocked = true

		var levels_v: Variant = world.get("levels", [])
		var levels: Array = levels_v if levels_v is Array else []
		var star_data: Array = _get_world_total_stars(world_id, levels)

		var bg_path := ""
		var world_theme: Variant = world.get("theme", {})
		if world_theme is Dictionary:
			bg_path = _resolve_asset_path(str((world_theme as Dictionary).get("background", "")))

		var entry := {
			"world_index": i,
			"id": world_id,
			"name": str(world.get("name", world_id)),
			"unlocked": unlocked,
			"bg_path": bg_path,
			"stars_earned": star_data[0],
			"stars_max": star_data[1],
		}

		var card := _create_world_card(entry)
		world_list.add_child(card)
		entry["node"] = card
		_items.append(entry)

func _create_world_card(entry: Dictionary) -> Control:
	var fm_t: float = float(_frame_margin.get("top", 4))
	var fm_r: float = float(_frame_margin.get("right", 4))
	var fm_b: float = float(_frame_margin.get("bottom", 4))
	var fm_l: float = float(_frame_margin.get("left", 4))
	var total_height: float = _card_height + fm_t + fm_b

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(0, total_height)
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	# Frame image behind the card
	if _frame_tex != null:
		var frame_rect := NinePatchRect.new()
		frame_rect.name = "Frame"
		frame_rect.texture = _frame_tex
		frame_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(frame_rect)

	# Inner card positioned with frame margins
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
	wrapper.add_child(card)

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

	var margin_left := Control.new()
	margin_left.custom_minimum_size = Vector2(16, 0)
	margin_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(margin_left)

	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	_apply_label_shadow(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	var star_container := HBoxContainer.new()
	star_container.alignment = BoxContainer.ALIGNMENT_END
	star_container.add_theme_constant_override("separation", 6)
	star_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var star_tex: Texture2D = _score_star_filled_tex
	if star_tex != null:
		var star_icon := TextureRect.new()
		star_icon.texture = star_tex
		star_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		star_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star_icon.custom_minimum_size = Vector2(STAR_LIST_SIZE, STAR_LIST_SIZE)
		star_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_container.add_child(star_icon)

	var star_label := Label.new()
	star_label.text = "%d / %d" % [int(entry.get("stars_earned", 0)), int(entry.get("stars_max", 0))]
	star_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star_label.add_theme_font_size_override("font_size", 20)
	star_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_apply_label_shadow(star_label)
	star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_container.add_child(star_label)

	hbox.add_child(star_container)

	var margin_right := Control.new()
	margin_right.custom_minimum_size = Vector2(16, 0)
	margin_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(margin_right)

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

	# Hover translate
	if _hover_translate_y != 0.0:
		wrapper.mouse_entered.connect(_on_card_hover_enter.bind(wrapper))
		wrapper.mouse_exited.connect(_on_card_hover_exit.bind(wrapper))

	var world_id: String = str(entry.get("id", ""))
	wrapper.gui_input.connect(_on_card_gui_input.bind(world_id, unlocked))

	return wrapper

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

func _on_card_gui_input(event: InputEvent, world_id: String, unlocked: bool) -> void:
	if not unlocked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_navigate_to_world(world_id)
			return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_navigate_to_world(world_id)

func _navigate_to_world(world_id: String) -> void:
	App.current_world_id = world_id
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/LevelSelect.tscn")

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

	world_list.custom_minimum_size.x = viewport_size.x - H_MARGIN * 2.0

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

func _get_world_total_stars(world_id: String, levels: Array) -> Array:
	var earned: int = 0
	var maximum: int = levels.size() * 3
	for lvl in levels:
		if not (lvl is Dictionary):
			continue
		var lid: String = str((lvl as Dictionary).get("id", ""))
		if lid == "" and lvl is Dictionary:
			lid = world_id + "_lvl_" + str((lvl as Dictionary).get("index", 0))
		earned += ProfileManager.get_level_stars(world_id, lid)
	return [earned, maximum]

func _on_back_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

func _on_header_crystals_pressed() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/ShopMenu.tscn")

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

func _apply_label_shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
