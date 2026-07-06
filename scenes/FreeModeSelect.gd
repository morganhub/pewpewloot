extends Control

## FreeModeSelect — Écran du mode Libre : liste dynamique des mini-jeux
## (intersection wave_types.json / freemode.json > modes), déblocage par
## rencontre en mode Histoire (ProfileManager.wave_types_encountered) ou achat
## global « Débloquer tous les jeux » (prix cristaux dans game.json >
## shop_menu.free_mode_unlock_all). Tuiles : image de fond du mode
## (freemode.json tile_background), overlay opacité (game.json >
## free_mode_select), nom localisé game_wave_<type>, record du profil centré
## en bas. Tap sur une tuile débloquée -> run infinie (App.free_mode_*).

const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const ROUNDED_MASK_SHADER: Shader = preload("res://scenes/ui/rounded_mask.gdshader")
const H_MARGIN := 20.0
const HOVER_DURATION := 0.12

@onready var background: TextureRect = $Background
@onready var title_label: Label = $TitleLabel
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var content_box: VBoxContainer = $ScrollContainer/ContentBox

var _game_config: Dictionary = {}
var _cfg: Dictionary = {}
var _unlock_cfg: Dictionary = {} # shop_menu.free_mode_unlock_all
var _columns := 2
var _tile_height := 150.0
var _tile_corner_radius := 12
var _tile_label_font_size := 22
var _overlay_opacity := 0.55
var _hover_translate_y := 4.0
var _locked_asset_path := ""
var _locked_opacity := 0.35
var _best_score_font_size := 16
var _best_score_color := Color("#FFD56B")
var _plays_font_size := 20
var _plays_color := Color("#FFFFFF")

var _counter_label: Label = null
var _unlock_button: Button = null
var _tiles_grid: GridContainer = null
var _popup_overlay: Control = null

func _ready() -> void:
	App.free_mode_active = false
	App.free_mode_wave_type = ""
	_load_config()
	App.play_menu_music()
	title_label.text = LocaleManager.translate("free_mode_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", int(_cfg.get("title_font_size", 36)))
	_apply_label_shadow(title_label)
	_build_content()
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
	var cfg_v: Variant = _game_config.get("free_mode_select", {})
	_cfg = (cfg_v as Dictionary) if cfg_v is Dictionary else {}
	var shop_v: Variant = _game_config.get("shop_menu", {})
	if shop_v is Dictionary:
		var unlock_v: Variant = (shop_v as Dictionary).get("free_mode_unlock_all", {})
		_unlock_cfg = (unlock_v as Dictionary) if unlock_v is Dictionary else {}
	_columns = clampi(int(_cfg.get("columns", 2)), 1, 3)
	_tile_height = maxf(80.0, float(_cfg.get("tile_height", 150)))
	_tile_corner_radius = int(_cfg.get("tile_corner_radius", 12))
	_tile_label_font_size = int(_cfg.get("tile_label_font_size", 22))
	_overlay_opacity = clampf(float(_cfg.get("overlay_opacity", 0.55)), 0.0, 1.0)
	_hover_translate_y = float(_cfg.get("hover_translate_y", 4))
	_locked_asset_path = _resolve_asset_path(str(_cfg.get("locked_asset", "res://assets/ui/buttons/locked.png")))
	_locked_opacity = clampf(float(_cfg.get("locked_opacity", 0.35)), 0.05, 1.0)
	_best_score_font_size = int(_cfg.get("best_score_font_size", 16))
	_best_score_color = Color(str(_cfg.get("best_score_color", "#FFD56B")))
	_plays_font_size = int(_cfg.get("plays_font_size", 20))
	_plays_color = Color(str(_cfg.get("plays_color", "#FFFFFF")))

	var bg_path := _resolve_asset_path(str(_cfg.get("background", "")))
	if bg_path == "":
		bg_path = _resolve_asset_path(str(_game_config.get("main_menu", {}).get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background.texture = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

# =============================================================================
# CONTENU (compteur + bouton achat + grille de tuiles)
# =============================================================================

func _build_content() -> void:
	for child in content_box.get_children():
		child.queue_free()

	var mode_ids: Array = DataManager.get_freemode_mode_ids()
	var unlocked_count: int = ProfileManager.get_unlocked_wave_type_count(mode_ids)

	# Bloc 1 : compteur "Modes débloqués : X/Y" (Y dynamique).
	_counter_label = Label.new()
	_counter_label.text = LocaleManager.translate("free_mode_unlocked_count",
		{"current": str(unlocked_count), "total": str(mode_ids.size())})
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", int(_cfg.get("counter_font_size", 20)))
	_apply_label_shadow(_counter_label)
	content_box.add_child(_counter_label)

	# Bouton "Débloquer tous les jeux" (icône panier + prix boutique en argent
	# réel — IAP store, simulateur en attendant), masqué si inutile.
	if unlocked_count < mode_ids.size() and not ProfileManager.is_free_mode_all_unlocked():
		_unlock_button = Button.new()
		_unlock_button.text = "%s — %s" % [LocaleManager.translate("free_mode_unlock_all"), _unlock_price_label()]
		_unlock_button.custom_minimum_size = Vector2(0, 54)
		_unlock_button.add_theme_font_size_override("font_size", int(_cfg.get("unlock_button_font_size", 18)))
		var icon_path := _resolve_asset_path(str(_unlock_cfg.get("icon", "res://assets/ui/cart.png")))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var icon_tex := ResourceLoader.load(icon_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
			if icon_tex:
				_unlock_button.icon = icon_tex
				_unlock_button.expand_icon = true
				_unlock_button.add_theme_constant_override("icon_max_width", int(_cfg.get("unlock_icon_size", 26)))
		UIStyle.apply_default_button_style(_unlock_button, "medium")
		_unlock_button.pressed.connect(_on_unlock_all_pressed)
		content_box.add_child(_unlock_button)

	# Grille des tuiles de modes.
	_tiles_grid = GridContainer.new()
	_tiles_grid.columns = _columns
	_tiles_grid.add_theme_constant_override("h_separation", 12)
	_tiles_grid.add_theme_constant_override("v_separation", 12)
	content_box.add_child(_tiles_grid)

	for id_v in mode_ids:
		var wave_type: String = str(id_v)
		_tiles_grid.add_child(_create_mode_tile(wave_type))

func _create_mode_tile(wave_type: String) -> Control:
	var mode_cfg: Dictionary = DataManager.get_freemode_mode_config(wave_type)
	var unlocked: bool = ProfileManager.is_wave_type_unlocked(wave_type)
	var best_score: int = ProfileManager.get_free_mode_best_score(wave_type)

	var wrapper := Control.new()
	wrapper.name = "ModeTile_" + wave_type
	wrapper.custom_minimum_size = Vector2(0, _tile_height)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	flat.set_corner_radius_all(_tile_corner_radius)
	card.add_theme_stylebox_override("panel", flat)
	wrapper.add_child(card)

	var clip := Control.new()
	clip.name = "Clip"
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(clip)

	var bg_path := _resolve_asset_path(str(mode_cfg.get("tile_background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex := ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex:
			var bg_rect := TextureRect.new()
			bg_rect.texture = tex
			bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Coins réellement arrondis : masque SDF en coordonnées locales
			# (le clip_contents du parent coupe droit). Le "layer opacité" est
			# appliqué en modulate sombre pour rester dans le masque arrondi.
			var mask := ShaderMaterial.new()
			mask.shader = ROUNDED_MASK_SHADER
			mask.set_shader_parameter("radius_px", float(_tile_corner_radius))
			mask.set_shader_parameter("rect_size", bg_rect.size)
			bg_rect.material = mask
			bg_rect.resized.connect(func() -> void:
				mask.set_shader_parameter("rect_size", bg_rect.size)
			)
			var darken: float = clampf(1.0 - _overlay_opacity, 0.0, 1.0)
			bg_rect.self_modulate = Color(darken, darken, darken, 1.0)
			clip.add_child(bg_rect)

	# Nom du mode (clé game_wave_<type> — jamais l'id brut avec underscore).
	var name_label := Label.new()
	name_label.text = LocaleManager.translate("game_wave_" + wave_type)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.add_theme_font_size_override("font_size", _tile_label_font_size)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	_apply_label_shadow(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(name_label)

	# Historique centré en bas : nombre de parties jouées (plus gros) au-dessus
	# du record du profil.
	var play_count: int = ProfileManager.get_free_mode_play_count(wave_type)
	if play_count > 0:
		var plays_label := Label.new()
		plays_label.text = LocaleManager.translate("free_mode_plays", {"count": str(play_count)})
		plays_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plays_label.anchor_left = 0.0
		plays_label.anchor_right = 1.0
		plays_label.anchor_top = 1.0
		plays_label.anchor_bottom = 1.0
		plays_label.offset_top = -58.0
		plays_label.offset_bottom = -30.0
		plays_label.add_theme_font_size_override("font_size", _plays_font_size)
		plays_label.add_theme_color_override("font_color", _plays_color)
		_apply_label_shadow(plays_label)
		plays_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(plays_label)
	if best_score > 0:
		var score_label := Label.new()
		score_label.text = LocaleManager.translate("free_mode_best_score", {"score": str(best_score)})
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.anchor_left = 0.0
		score_label.anchor_right = 1.0
		score_label.anchor_top = 1.0
		score_label.anchor_bottom = 1.0
		score_label.offset_top = -30.0
		score_label.offset_bottom = -8.0
		score_label.add_theme_font_size_override("font_size", _best_score_font_size)
		score_label.add_theme_color_override("font_color", _best_score_color)
		_apply_label_shadow(score_label)
		score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(score_label)

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

	if _hover_translate_y != 0.0 and unlocked:
		wrapper.mouse_entered.connect(_on_tile_hover_enter.bind(wrapper))
		wrapper.mouse_exited.connect(_on_tile_hover_exit.bind(wrapper))
	wrapper.gui_input.connect(_on_tile_gui_input.bind(wave_type, unlocked))
	return wrapper

# =============================================================================
# INTERACTIONS
# =============================================================================

func _on_tile_gui_input(event: InputEvent, wave_type: String, unlocked: bool) -> void:
	if not _is_primary_press(event):
		return
	if not unlocked:
		_show_message_popup(LocaleManager.translate("free_mode_locked_hint"))
		get_viewport().set_input_as_handled()
		return
	_launch_free_mode(wave_type)

func _launch_free_mode(wave_type: String) -> void:
	App.free_mode_active = true
	App.free_mode_wave_type = wave_type
	# Monde neutre : skins/multipliers de world_1 (les mini-jeux gèrent leur
	# propre difficulté via freemode.json).
	App.current_world_id = "world_1"
	App.set_active_override_protocols([])
	_goto("res://scenes/Game.tscn")

func _unlock_price_label() -> String:
	return "$%s" % str(_unlock_cfg.get("price_usd", 4.99))

## Achat en argent réel via le store de la plateforme. product_id résolu selon
## l'OS depuis game.json > shop_menu.free_mode_unlock_all.
func _resolve_store_product_id() -> String:
	var key: String = "product_id_android"
	if OS.get_name() == "iOS":
		key = "product_id_ios"
	return str(_unlock_cfg.get(key, ""))

## SIMULATEUR IAP — même approche que ShopMenu pour les packs de cristaux :
## l'achat réussit immédiatement. Point de branchement pour les vraies
## connexions store (Google Play Billing / Apple StoreKit) : remplacer le corps
## par le lancement de la transaction et ne valider qu'au callback de succès.
func _simulate_store_purchase(product_id: String) -> bool:
	print("[FreeModeSelect] SIMULATED store purchase: ", product_id, " (", _unlock_price_label(), ")")
	return true

func _on_unlock_all_pressed() -> void:
	_show_confirm_popup(
		LocaleManager.translate("free_mode_unlock_confirm", {"price": _unlock_price_label()}),
		_try_buy_unlock_all
	)

func _try_buy_unlock_all() -> void:
	_close_popup()
	if not _simulate_store_purchase(_resolve_store_product_id()):
		return
	ProfileManager.set_free_mode_all_unlocked(true)
	_build_content()

# =============================================================================
# POPUPS (message simple / confirmation / renvoi boutique)
# =============================================================================

func _show_message_popup(message_text: String) -> void:
	_build_popup(message_text, [
		{"label": LocaleManager.translate("level_select_override_close"), "callback": _close_popup}
	])

func _show_confirm_popup(message_text: String, on_confirm: Callable) -> void:
	_build_popup(message_text, [
		{"label": LocaleManager.translate("free_mode_unlock_all"), "callback": on_confirm},
		{"label": LocaleManager.translate("level_select_override_close"), "callback": _close_popup}
	])

func _build_popup(message_text: String, buttons: Array) -> void:
	_close_popup()
	_popup_overlay = Control.new()
	_popup_overlay.name = "FreeModePopupOverlay"
	_popup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_popup_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_popup_dim_input)
	_popup_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.16, 0.96)
	style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var message := Label.new()
	message.text = message_text
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 22)
	_apply_label_shadow(message)
	content.add_child(message)

	for btn_cfg_v in buttons:
		if not (btn_cfg_v is Dictionary):
			continue
		var btn_cfg: Dictionary = btn_cfg_v as Dictionary
		var btn := Button.new()
		btn.text = str(btn_cfg.get("label", ""))
		btn.custom_minimum_size = Vector2(0, 54)
		var cb_v: Variant = btn_cfg.get("callback", null)
		if cb_v is Callable:
			btn.pressed.connect(cb_v as Callable)
		UIStyle.apply_default_button_style(btn, "medium")
		UIStyle.apply_button_shadow(btn, "large")
		content.add_child(btn)

func _close_popup() -> void:
	if _popup_overlay != null and is_instance_valid(_popup_overlay):
		_popup_overlay.queue_free()
	_popup_overlay = null

func _on_popup_dim_input(event: InputEvent) -> void:
	if _is_primary_press(event):
		_close_popup()

func _is_primary_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false

func _on_tile_hover_enter(card: Control) -> void:
	if not card.has_meta("hover_base_y"):
		card.set_meta("hover_base_y", card.position.y)
	var base_y: float = card.get_meta("hover_base_y")
	_stop_hover_tween(card)
	var tw := card.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(card, "position:y", base_y + _hover_translate_y, HOVER_DURATION)
	card.set_meta("hover_tween", tw)

func _on_tile_hover_exit(card: Control) -> void:
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

# =============================================================================
# LAYOUT / NAV
# =============================================================================

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
	content_box.custom_minimum_size.x = viewport_size.x - H_MARGIN * 2.0

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
	_goto("res://scenes/GameModeSelect.tscn")

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
