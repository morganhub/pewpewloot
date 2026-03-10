extends Control

signal back_pressed

var _cfg: Dictionary = {}

func _ready() -> void:
	_cfg = _get_config()
	_build_ui()

func _get_config() -> Dictionary:
	if DataManager == null:
		return {}
	var game: Dictionary = DataManager.get_game_config()
	var f: Variant = game.get("menu_footer", {})
	return f if f is Dictionary else {}

func _build_ui() -> void:
	var height_px: int = int(_cfg.get("height_px", 72))
	var margin_l: int = int(_cfg.get("margin_left", 20))
	var margin_r: int = int(_cfg.get("margin_right", 20))
	var margin_b: int = int(_cfg.get("margin_bottom", 12))
	var bg_opacity: float = float(_cfg.get("background_opacity", 0.65))
	var bg_asset: String = str(_cfg.get("background_asset", ""))
	var border_top_h: int = int(_cfg.get("border_top_height", 0))
	var border_top_col: Color = Color.from_string(str(_cfg.get("border_top_color", "#FFFFFF")), Color.WHITE)
	var back_cfg: Dictionary = _cfg.get("back_button", {}) if _cfg.get("back_button") is Dictionary else {}
	var back_w: float = maxf(48.0, float(back_cfg.get("width", 180)))
	var back_h: float = maxf(40.0, float(back_cfg.get("height", 60)))
	var _back_icon_sz: float = maxf(24.0, float(back_cfg.get("icon_size", 40)))

	# Ancrage en bas, largeur écran complète
	custom_minimum_size.y = height_px
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -height_px
	offset_bottom = 0.0
	z_index = 10

	# Background + bordure haute
	var bg_panel := PanelContainer.new()
	bg_panel.name = "BackgroundPanel"
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style: StyleBox
	if bg_asset != "" and ResourceLoader.exists(bg_asset):
		var tex_style := StyleBoxTexture.new()
		tex_style.texture = load(bg_asset) as Texture2D
		tex_style.draw_center = true
		tex_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		tex_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		style = tex_style
		bg_panel.modulate = Color(1.0, 1.0, 1.0, bg_opacity)
	else:
		var flat_style := StyleBoxFlat.new()
		flat_style.bg_color = Color(0, 0, 0, bg_opacity)
		if border_top_h > 0:
			flat_style.border_width_top = border_top_h
			flat_style.border_color = border_top_col
		style = flat_style
	bg_panel.add_theme_stylebox_override("panel", style)
	add_child(bg_panel)

	# Bordure haute (toujours visible, au-dessus du fond)
	if border_top_h > 0:
		var border_line := ColorRect.new()
		border_line.name = "BorderTop"
		border_line.color = border_top_col
		border_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
		border_line.anchor_bottom = 0.0
		border_line.offset_top = 0.0
		border_line.offset_bottom = float(border_top_h)
		add_child(border_line)

	# Contenu avec marges gauche/droite/bas
	var root_margin := MarginContainer.new()
	root_margin.name = "RootMargin"
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", margin_l)
	root_margin.add_theme_constant_override("margin_right", margin_r)
	root_margin.add_theme_constant_override("margin_bottom", margin_b)
	add_child(root_margin)

	var hbox := HBoxContainer.new()
	hbox.name = "ContentRow"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root_margin.add_child(hbox)

	# Bouton retour à gauche (wrapper pour que le translate Y ne soit pas écrasé par le layout)
	var offset_y: float = 5.0
	if DataManager != null:
		var game_cfg: Dictionary = DataManager.get_game_config()
		var buttons_cfg: Dictionary = game_cfg.get("buttons", {}) if game_cfg.get("buttons") is Dictionary else {}
		offset_y = float(buttons_cfg.get("pressed_offset_y", 5))
	var wrapper := Control.new()
	wrapper.name = "BackButtonWrapper"
	wrapper.custom_minimum_size = Vector2(back_w, back_h + offset_y)
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(wrapper)

	var back_btn := TextureButton.new()
	back_btn.name = "BackButton"
	back_btn.unique_name_in_owner = true
	back_btn.custom_minimum_size = Vector2(back_w, back_h)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.ignore_texture_size = true
	back_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.position = Vector2(0.0, 0.0)
	back_btn.size = Vector2(back_w, back_h)

	# Icône depuis menu_footer.back_button.asset
	var back_asset: String = str(back_cfg.get("asset", ""))
	if back_asset != "" and ResourceLoader.exists(back_asset):
		back_btn.texture_normal = load(back_asset)

	back_btn.pressed.connect(_on_back_button_pressed)
	wrapper.add_child(back_btn)

	# Même animation translate Y que les autres boutons (game.json buttons.pressed_offset_y)
	const UIStyle = preload("res://scripts/ui/UIStyle.gd")
	UIStyle.apply_button_hover_translate(back_btn)

	# Spacer pour pousser le contenu éventuel à droite
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

func _on_back_button_pressed() -> void:
	back_pressed.emit()
