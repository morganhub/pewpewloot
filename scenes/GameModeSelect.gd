extends Control

## GameModeSelect — Écran de choix du mode après « Jouer » : deux grandes
## cards à image de fond (config game.json > game_mode_select) — « Histoire »
## (flux mondes/niveaux classique) et « Libre » (un mini-jeu wave_type joué en
## boucle infinie, écran FreeModeSelect). Cards procédurales sur le pattern de
## WorldSelect (image cover + overlay opacité + label centré ombré).

const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const H_MARGIN := 20.0
const HOVER_DURATION := 0.12

@onready var background: TextureRect = $Background
@onready var title_label: Label = $TitleLabel
@onready var card_list: VBoxContainer = $CardList

var _game_config: Dictionary = {}
var _cfg: Dictionary = {}
var _card_height_ratio := 0.34
var _card_corner_radius := 16
var _card_label_font_size := 42
var _overlay_opacity := 0.45
var _hover_translate_y := 4.0

func _ready() -> void:
	# Toute entrée dans cet écran sort du mode libre (le flag n'est reposé que
	# par FreeModeSelect au lancement d'une run).
	App.free_mode_active = false
	App.free_mode_wave_type = ""
	_load_config()
	App.play_menu_music()
	title_label.text = LocaleManager.translate("game_mode_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", int(_cfg.get("title_font_size", 36)))
	_apply_label_shadow(title_label)
	_build_cards()
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
	var cfg_v: Variant = _game_config.get("game_mode_select", {})
	_cfg = (cfg_v as Dictionary) if cfg_v is Dictionary else {}
	_card_height_ratio = clampf(float(_cfg.get("card_height_ratio", 0.34)), 0.15, 0.48)
	_card_corner_radius = int(_cfg.get("card_corner_radius", 16))
	_card_label_font_size = int(_cfg.get("card_label_font_size", 42))
	_overlay_opacity = clampf(float(_cfg.get("overlay_opacity", 0.45)), 0.0, 1.0)
	_hover_translate_y = float(_cfg.get("hover_translate_y", 4))

	var bg_path := _resolve_asset_path(str(_cfg.get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_game_config.get("main_menu", {}).get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background.texture = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

func _build_cards() -> void:
	for child in card_list.get_children():
		child.queue_free()
	var cards_v: Variant = _cfg.get("cards", {})
	var cards: Dictionary = (cards_v as Dictionary) if cards_v is Dictionary else {}
	for mode_id in ["story", "free"]:
		var card_cfg_v: Variant = cards.get(mode_id, {})
		var card_cfg: Dictionary = (card_cfg_v as Dictionary) if card_cfg_v is Dictionary else {}
		card_list.add_child(_create_mode_card(mode_id, card_cfg))

func _create_mode_card(mode_id: String, card_cfg: Dictionary) -> Control:
	var wrapper := Control.new()
	wrapper.name = "ModeCard_" + mode_id
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	flat.set_corner_radius_all(_card_corner_radius)
	card.add_theme_stylebox_override("panel", flat)
	wrapper.add_child(card)

	var clip := Control.new()
	clip.name = "Clip"
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(clip)

	var bg_path := _resolve_asset_path(str(card_cfg.get("background", "")))
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

	var name_label := Label.new()
	name_label.text = LocaleManager.translate(str(card_cfg.get("locale_key", "game_mode_" + mode_id)))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.add_theme_font_size_override("font_size", _card_label_font_size)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	_apply_label_shadow(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(name_label)

	if _hover_translate_y != 0.0:
		wrapper.mouse_entered.connect(_on_card_hover_enter.bind(wrapper))
		wrapper.mouse_exited.connect(_on_card_hover_exit.bind(wrapper))
	wrapper.gui_input.connect(_on_card_gui_input.bind(mode_id))
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

func _on_card_gui_input(event: InputEvent, mode_id: String) -> void:
	if not _is_primary_press(event):
		return
	match mode_id:
		"story":
			_goto("res://scenes/WorldSelect.tscn")
		"free":
			_goto("res://scenes/FreeModeSelect.tscn")

func _is_primary_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false

func _apply_layout() -> void:
	var viewport_size := size
	var header_offset := _get_menu_header_offset()
	var footer_height := _get_menu_footer_height()

	title_label.position = Vector2(H_MARGIN, header_offset + 4.0)
	title_label.size = Vector2(viewport_size.x - H_MARGIN * 2.0, 44.0)

	var list_top := header_offset + 52.0
	var list_bottom := viewport_size.y - footer_height - 8.0
	card_list.position = Vector2(H_MARGIN, list_top)
	card_list.size = Vector2(viewport_size.x - H_MARGIN * 2.0, maxf(100.0, list_bottom - list_top))
	var card_height: float = viewport_size.y * _card_height_ratio
	for child in card_list.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = Vector2(0, card_height)

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

func _goto(scene_path: String) -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen(scene_path)

func _on_back_pressed() -> void:
	_goto("res://scenes/HomeScreen.tscn")

func _on_header_crystals_pressed() -> void:
	_goto("res://scenes/ShopMenu.tscn")

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
