extends RefCounted

const HIGHLIGHT_GLOW_SHADER_CODE := """
shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.42, 1.0);
uniform float glow_thickness = 6.0;
uniform float glow_intensity = 1.25;
uniform float pulse_frequency = 1.6;
uniform float pulse_amplitude = 0.22;
uniform vec2 source_tex_size = vec2(256.0, 128.0);

void fragment() {
	vec2 uv = UV;
	vec2 px = 1.0 / max(source_tex_size, vec2(1.0));
	float center_alpha = texture(TEXTURE, uv).a;
	float ring = 0.0;
	float smooth_edge = max(glow_thickness * 0.35, 1.0);

	for (int i = 0; i < 16; i++) {
		float a = (6.2831853 / 16.0) * float(i);
		vec2 dir = vec2(cos(a), sin(a));
		float near_alpha = texture(TEXTURE, uv + dir * px * glow_thickness).a;
		float far_alpha = texture(TEXTURE, uv + dir * px * (glow_thickness + smooth_edge)).a;
		ring = max(ring, max(near_alpha, far_alpha * 0.7));
	}

	float edge = clamp(ring - center_alpha, 0.0, 1.0);
	edge *= smoothstep(0.0, 1.0, edge);
	float pulse = 1.0 + sin(TIME * pulse_frequency * 6.2831853) * pulse_amplitude;
	float alpha_out = edge * glow_intensity * pulse * glow_color.a;
	COLOR = vec4(glow_color.rgb, alpha_out);
}
"""

## Helper centralise pour appliquer des StyleBoxTexture en mode 9-slice.
## Compatible avec des configs partielles: fallback propre si des cles manquent.

static func build_texture_stylebox(asset_path: String, cfg: Dictionary = {}, fallback_content_margin: int = -1) -> StyleBoxTexture:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null

	var style := StyleBoxTexture.new()
	style.texture = load(asset_path)
	_apply_nine_slice(style, cfg)
	_apply_content_margins(style, cfg, fallback_content_margin)
	_apply_axis_stretch(style, cfg)
	style.draw_center = bool(_get_nested(cfg, ["draw_center"], true))
	return style

static func _apply_nine_slice(style: StyleBoxTexture, cfg: Dictionary) -> void:
	var ns_raw: Variant = cfg.get("nine_slice", {})
	var ns: Dictionary = ns_raw if ns_raw is Dictionary else {}

	var left: float = _slice_value(cfg, ns, "left")
	var right: float = _slice_value(cfg, ns, "right")
	var top: float = _slice_value(cfg, ns, "top")
	var bottom: float = _slice_value(cfg, ns, "bottom")

	if left >= 0.0:
		style.texture_margin_left = left
	if right >= 0.0:
		style.texture_margin_right = right
	if top >= 0.0:
		style.texture_margin_top = top
	if bottom >= 0.0:
		style.texture_margin_bottom = bottom

static func _apply_content_margins(style: StyleBoxTexture, cfg: Dictionary, fallback_content_margin: int) -> void:
	var cm_raw: Variant = cfg.get("content_margin", {})
	var cm: Dictionary = cm_raw if cm_raw is Dictionary else {}

	var left: float = _content_value(cfg, cm, "left")
	var right: float = _content_value(cfg, cm, "right")
	var top: float = _content_value(cfg, cm, "top")
	var bottom: float = _content_value(cfg, cm, "bottom")

	if left >= 0.0:
		style.content_margin_left = left
	elif fallback_content_margin >= 0:
		style.content_margin_left = fallback_content_margin

	if right >= 0.0:
		style.content_margin_right = right
	elif fallback_content_margin >= 0:
		style.content_margin_right = fallback_content_margin

	if top >= 0.0:
		style.content_margin_top = top
	elif fallback_content_margin >= 0:
		style.content_margin_top = fallback_content_margin

	if bottom >= 0.0:
		style.content_margin_bottom = bottom
	elif fallback_content_margin >= 0:
		style.content_margin_bottom = fallback_content_margin

static func _apply_axis_stretch(style: StyleBoxTexture, cfg: Dictionary) -> void:
	var stretch_h: String = str(_get_nested(cfg, ["stretch_horizontal"], "stretch")).to_lower()
	var stretch_v: String = str(_get_nested(cfg, ["stretch_vertical"], "stretch")).to_lower()
	style.axis_stretch_horizontal = _axis_mode_from_text(stretch_h) as StyleBoxTexture.AxisStretchMode
	style.axis_stretch_vertical = _axis_mode_from_text(stretch_v) as StyleBoxTexture.AxisStretchMode

static func _axis_mode_from_text(value: String) -> int:
	match value:
		"tile":
			return StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		"tile_fit":
			return StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		_:
			return StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

static func _slice_value(cfg: Dictionary, ns: Dictionary, side: String) -> float:
	var ns_value: float = _to_float_or(ns.get(side, null), -1.0)
	if ns_value >= 0.0:
		return ns_value

	match side:
		"left":
			return _to_float_or(cfg.get("slice_left", cfg.get("patch_margin_left", null)), -1.0)
		"right":
			return _to_float_or(cfg.get("slice_right", cfg.get("patch_margin_right", null)), -1.0)
		"top":
			return _to_float_or(cfg.get("slice_top", cfg.get("patch_margin_top", null)), -1.0)
		"bottom":
			return _to_float_or(cfg.get("slice_bottom", cfg.get("patch_margin_bottom", null)), -1.0)
		_:
			return -1.0

static func _content_value(cfg: Dictionary, cm: Dictionary, side: String) -> float:
	var cm_value: float = _to_float_or(cm.get(side, null), -1.0)
	if cm_value >= 0.0:
		return cm_value

	match side:
		"left":
			return _to_float_or(cfg.get("content_margin_left", null), -1.0)
		"right":
			return _to_float_or(cfg.get("content_margin_right", null), -1.0)
		"top":
			return _to_float_or(cfg.get("content_margin_top", null), -1.0)
		"bottom":
			return _to_float_or(cfg.get("content_margin_bottom", null), -1.0)
		_:
			return -1.0

static func _to_float_or(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback

static func _get_nested(source: Dictionary, path: Array, fallback: Variant) -> Variant:
	var current: Variant = source
	for part in path:
		if not (current is Dictionary):
			return fallback
		var dict := current as Dictionary
		if not dict.has(str(part)):
			return fallback
		current = dict[str(part)]
	return current

## Builds a 9-slice StyleBoxTexture from an existing Texture2D (e.g. from a SpriteFrames frame).
static func build_stylebox_from_texture(tex: Texture2D, cfg: Dictionary, fallback_content_margin: int = -1) -> StyleBoxTexture:
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	_apply_nine_slice(style, cfg)
	_apply_content_margins(style, cfg, fallback_content_margin)
	_apply_axis_stretch(style, cfg)
	style.draw_center = bool(_get_nested(cfg, ["draw_center"], true))
	return style

## Duplicates a StyleBoxTexture and shifts content by offset_y (e.g. +5 for "pressed" state).
static func _stylebox_with_content_offset(style: StyleBoxTexture, offset_y: float) -> StyleBoxTexture:
	if style == null or offset_y == 0.0:
		return style
	var copy := StyleBoxTexture.new()
	copy.texture = style.texture
	copy.texture_margin_left = style.texture_margin_left
	copy.texture_margin_right = style.texture_margin_right
	copy.texture_margin_top = style.texture_margin_top
	copy.texture_margin_bottom = style.texture_margin_bottom
	copy.content_margin_left = style.content_margin_left
	copy.content_margin_right = style.content_margin_right
	copy.content_margin_top = style.content_margin_top + offset_y
	copy.content_margin_bottom = maxf(0.0, style.content_margin_bottom - offset_y)
	copy.axis_stretch_horizontal = style.axis_stretch_horizontal
	copy.axis_stretch_vertical = style.axis_stretch_vertical
	copy.draw_center = style.draw_center
	return copy

static func _get_pressed_offset_y() -> float:
	var buttons := _get_buttons_section()
	return _to_float_or(buttons.get("pressed_offset_y", null), 5.0)

## Retourne une copie du StyleBoxTexture avec le décalage Y hover/pressed (game.json buttons.pressed_offset_y).
## À utiliser pour les boutons qui ont leur propre style : passer le style normal, utiliser le retour pour hover/pressed/focus.
static func get_stylebox_with_hover_offset(style: StyleBox) -> StyleBox:
	if style is StyleBoxTexture:
		return _stylebox_with_content_offset(style as StyleBoxTexture, _get_pressed_offset_y())
	return style

const HOVER_TRANSLATE_DURATION := 0.15

## Translate Y au survol: utilise game.json buttons.pressed_offset_y, animation ease-in-out.
static func apply_button_hover_translate(btn: Control) -> void:
	if btn == null:
		return
	var offset_y: float = _get_pressed_offset_y()
	if offset_y == 0.0:
		return
	if btn.get_meta("hover_translate_applied", false):
		return
	btn.set_meta("hover_translate_applied", true)
	btn.mouse_entered.connect(_on_button_hover_entered.bind(btn, offset_y))
	btn.mouse_exited.connect(_on_button_hover_exited.bind(btn, offset_y))

static func _on_button_hover_entered(btn: Control, offset_y: float) -> void:
	_stop_button_hover_tween(btn)
	var base_y: float = btn.get_meta("hover_base_y", btn.position.y)
	btn.set_meta("hover_base_y", base_y)
	var tw := btn.create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(btn, "position:y", base_y + offset_y, HOVER_TRANSLATE_DURATION)
	btn.set_meta("hover_tween", tw)

static func _on_button_hover_exited(btn: Control, offset_y: float) -> void:
	_stop_button_hover_tween(btn)
	var base_y: float = btn.get_meta("hover_base_y", btn.position.y - offset_y)
	var tw := btn.create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(btn, "position:y", base_y, HOVER_TRANSLATE_DURATION)
	tw.finished.connect(func(): btn.set_meta("hover_base_y", btn.position.y))
	btn.set_meta("hover_tween", tw)

static func _stop_button_hover_tween(btn: Control) -> void:
	if not btn.has_meta("hover_tween"):
		return
	var tw: Variant = btn.get_meta("hover_tween")
	if tw is Tween and is_instance_valid(tw as Tween):
		(tw as Tween).kill()
	btn.remove_meta("hover_tween")

## Builds normal and hover styleboxes for the validation button.
## Supports .png (single texture; hover = same style with content offset) or .tres SpriteFrames (frame 0 for both, hover with offset).
## Returns { "normal": StyleBoxTexture, "hover": StyleBoxTexture } or empty if asset invalid.
static func build_validation_styleboxes(asset_path: String, cfg: Dictionary) -> Dictionary:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return {}
	var offset_y: float = _get_pressed_offset_y()
	var ext: String = asset_path.get_extension().to_lower()
	if ext in ["png", "jpg", "webp"]:
		var fallback_margin: int = 14
		var cm: Variant = cfg.get("content_margin", {})
		if cm is Dictionary and (cm as Dictionary).get("left", -1) >= 0:
			fallback_margin = -1
		var style_normal: StyleBoxTexture = build_texture_stylebox(asset_path, cfg, fallback_margin)
		if style_normal == null:
			return {}
		var style_hover: StyleBoxTexture = _stylebox_with_content_offset(style_normal, offset_y)
		return { "normal": style_normal, "hover": style_hover }
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null or not (res is SpriteFrames):
		return {}
	var frames: SpriteFrames = res as SpriteFrames
	var anim_names: Array = frames.get_animation_names()
	var anim_name: StringName = &"default"
	if anim_names.size() > 0:
		anim_name = anim_names[0]
	var frame_count: int = frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return {}
	var tex_normal: Texture2D = frames.get_frame_texture(anim_name, 0)
	var res_fallback_margin: int = 14
	var res_cm: Variant = cfg.get("content_margin", {})
	if res_cm is Dictionary and (res_cm as Dictionary).get("left", -1) >= 0:
		res_fallback_margin = -1
	var res_style_normal := build_stylebox_from_texture(tex_normal, cfg, res_fallback_margin)
	if res_style_normal == null:
		return {}
	var res_style_hover := _stylebox_with_content_offset(res_style_normal, offset_y)
	return { "normal": res_style_normal, "hover": res_style_hover }

## Applies a text shadow to a Button by overlaying a Label child.
## Godot 4 Button does not support font_shadow natively; this workaround
## hides the native text and adds a Label with shadow on top.
## `shadow_size` must be one of "small", "medium", "large" (reads from game.json button_shadow).
## If the button text is empty, does nothing.
## Safe to call multiple times: updates existing ShadowLabel if present.
static func apply_button_shadow(button: Button, shadow_size: String = "medium") -> void:
	if button == null:
		return
	var cfg := _get_shadow_config(shadow_size)
	var shadow_color: Color = Color.from_string(str(cfg.get("shadow_color", "#000000")), Color.BLACK)
	var offset_x: int = int(cfg.get("shadow_offset_x", 2))
	var offset_y: int = int(cfg.get("shadow_offset_y", 2))
	var outline_size: int = int(cfg.get("shadow_outline_size", 0))

	var existing: Label = button.get_node_or_null("ShadowLabel")
	if existing != null:
		_sync_shadow_label(button, existing, shadow_color, offset_x, offset_y, outline_size)
		return

	if button.text.is_empty():
		return

	var font_val: Font = button.get_theme_font("font")
	var font_size_val: int = button.get_theme_font_size("font_size")
	var font_color: Color = Color.WHITE
	if button.has_theme_color_override("font_color"):
		font_color = button.get_theme_color("font_color")
	var btn_text := button.text

	button.text = ""
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))

	var lbl := Label.new()
	lbl.name = "ShadowLabel"
	lbl.text = btn_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_val:
		lbl.add_theme_font_override("font", font_val)
	if font_size_val > 0:
		lbl.add_theme_font_size_override("font_size", font_size_val)
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_color_override("font_shadow_color", shadow_color)
	lbl.add_theme_constant_override("shadow_offset_x", offset_x)
	lbl.add_theme_constant_override("shadow_offset_y", offset_y)
	lbl.add_theme_constant_override("shadow_outline_size", outline_size)
	button.add_child(lbl)

## Updates the text of a ShadowLabel-equipped Button. Use this instead of `button.text = ...`.
static func set_button_shadow_text(button: Button, new_text: String) -> void:
	if button == null:
		return
	var lbl: Label = button.get_node_or_null("ShadowLabel")
	if lbl != null:
		lbl.text = new_text
	else:
		button.text = new_text

## Updates the font color of a ShadowLabel-equipped Button.
static func set_button_shadow_color(button: Button, color: Color) -> void:
	if button == null:
		return
	var lbl: Label = button.get_node_or_null("ShadowLabel")
	if lbl != null:
		lbl.add_theme_color_override("font_color", color)

static func _sync_shadow_label(button: Button, lbl: Label, shadow_color: Color, ox: int, oy: int, outline: int) -> void:
	if not button.text.is_empty():
		lbl.text = button.text
		button.text = ""
	lbl.add_theme_color_override("font_shadow_color", shadow_color)
	lbl.add_theme_constant_override("shadow_offset_x", ox)
	lbl.add_theme_constant_override("shadow_offset_y", oy)
	lbl.add_theme_constant_override("shadow_outline_size", outline)

static func _apply_letter_spacing_via_font(control: Control, spacing: int) -> void:
	if spacing == 0:
		return
	var base_font: Font = control.get_theme_font("font")
	var fv := FontVariation.new()
	if base_font:
		fv.base_font = base_font
	fv.spacing_glyph = spacing
	control.add_theme_font_override("font", fv)

static func _get_game_config() -> Dictionary:
	var dm: Node = Engine.get_main_loop().root.get_node_or_null("/root/DataManager") if Engine.get_main_loop() else null
	if dm != null and dm.has_method("get_game_config"):
		return dm.get_game_config()
	# Fallback si DataManager pas encore prêt (ex. éditeur ou chargement initial)
	if FileAccess.file_exists("res://data/game.json"):
		var f := FileAccess.open("res://data/game.json", FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				f.close()
				return json.data
			f.close()
	return {}

static func _get_buttons_section() -> Dictionary:
	var game_cfg := _get_game_config()
	var section: Variant = game_cfg.get("buttons", {})
	return section if section is Dictionary else {}

static func _get_shadow_config(size_key: String) -> Dictionary:
	var fallback := {"shadow_color": "#000000", "shadow_offset_x": 2, "shadow_offset_y": 2, "shadow_outline_size": 0}
	var buttons := _get_buttons_section()
	var shadow_section: Variant = buttons.get("shadow", {})
	if not (shadow_section is Dictionary):
		return fallback
	var preset: Variant = (shadow_section as Dictionary).get(size_key, {})
	if not (preset is Dictionary) or (preset as Dictionary).is_empty():
		return fallback
	return preset as Dictionary

## Returns the font preset dict for a given size ("small", "medium", "large").
static func get_button_font_preset(size_key: String) -> Dictionary:
	var fallback_map := {
		"small": {"font_size": 14, "letter_spacing": 0},
		"medium": {"font_size": 18, "letter_spacing": 0},
		"large": {"font_size": 24, "letter_spacing": 1},
	}
	var buttons := _get_buttons_section()
	var presets: Variant = buttons.get("font_presets", {})
	if presets is Dictionary and (presets as Dictionary).has(size_key):
		var p: Variant = (presets as Dictionary).get(size_key, {})
		if p is Dictionary and not (p as Dictionary).is_empty():
			return p as Dictionary
	return fallback_map.get(size_key, fallback_map["medium"])

## Returns the default button style config (asset, nine_slice, text_color, etc.).
static func get_default_button_style() -> Dictionary:
	var buttons := _get_buttons_section()
	var style: Variant = buttons.get("default_style", {})
	return style if style is Dictionary else {}

## Returns the default button minimum size (min_width, min_height) for in-game popups.
static func get_default_button_min_size() -> Vector2:
	var style := get_default_button_style()
	var w: int = int(style.get("min_width", 220))
	var h: int = int(style.get("min_height", 56))
	return Vector2(w, h)

## Returns the validation button config.
static func get_validation_config() -> Dictionary:
	var buttons := _get_buttons_section()
	var v: Variant = buttons.get("validation", {})
	return v if v is Dictionary else {}

## Returns the cancellation button config (same structure as validation, different asset).
static func get_cancellation_config() -> Dictionary:
	var buttons := _get_buttons_section()
	var c: Variant = buttons.get("cancellation", {})
	return c if c is Dictionary else {}

## Returns the highlight button config (same structure as validation + glow params).
static func get_highlight_config() -> Dictionary:
	var buttons := _get_buttons_section()
	var h: Variant = buttons.get("highlight", {})
	return h if h is Dictionary else {}

## Applies the default button style (asset 9-slice + text_color) and font preset to a Button.
static func apply_default_button_style(btn: Button, font_size_key: String = "medium") -> void:
	if btn == null:
		return
	var style_cfg := get_default_button_style()
	var asset_path := str(style_cfg.get("asset", ""))
	var stylebox := build_texture_stylebox(asset_path, style_cfg, 15)
	if stylebox:
		var style_pressed: StyleBoxTexture = _stylebox_with_content_offset(stylebox, _get_pressed_offset_y())
		btn.add_theme_stylebox_override("normal", stylebox)
		btn.add_theme_stylebox_override("hover", style_pressed)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("focus", style_pressed)
		btn.add_theme_stylebox_override("disabled", stylebox)

	var col_hex := str(style_cfg.get("text_color", "#FFFFFF"))
	var col := Color.html(col_hex)
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", col)
	btn.add_theme_color_override("font_pressed_color", col)
	btn.add_theme_color_override("font_focus_color", col)
	btn.add_theme_color_override("font_disabled_color", Color(col.r, col.g, col.b, 0.5))

	var font_cfg := get_button_font_preset(font_size_key)
	btn.add_theme_font_size_override("font_size", int(font_cfg.get("font_size", 18)))
	_apply_letter_spacing_via_font(btn, int(font_cfg.get("letter_spacing", 0)))
	apply_button_hover_translate(btn)

## Applies the validation 9-slice button style to a Button (normal + hover/pressed/focus with content offset).
## Pass font_size_key to also set the centralized font preset; pass "" to skip font override.
static func apply_validation_to_button(btn: Button, validation_cfg: Dictionary = {}, font_size_key: String = "") -> void:
	if btn == null:
		return
	var cfg := validation_cfg if not validation_cfg.is_empty() else get_validation_config()
	if cfg.is_empty():
		return
	var asset_path: String = str(cfg.get("asset", ""))
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var styles: Dictionary = build_validation_styleboxes(asset_path, cfg)
	if styles.is_empty():
		return
	var style_normal: StyleBoxTexture = styles.get("normal", null)
	var style_hover: StyleBoxTexture = styles.get("hover", null)
	if style_normal == null:
		return
	if style_hover == null:
		style_hover = style_normal
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("focus", style_hover)
	btn.add_theme_stylebox_override("disabled", style_normal)
	var text_color_hex: String = str(cfg.get("text_color", "#ffffff"))
	var col := Color(text_color_hex)
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", col)
	btn.add_theme_color_override("font_pressed_color", col)
	btn.add_theme_color_override("font_focus_color", col)
	btn.add_theme_color_override("font_disabled_color", Color(col.r, col.g, col.b, 0.5))

	if font_size_key != "":
		var font_cfg := get_button_font_preset(font_size_key)
		var size_override: Variant = cfg.get("text_size", cfg.get("font_size", null))
		if size_override != null:
			btn.add_theme_font_size_override("font_size", int(size_override))
		else:
			btn.add_theme_font_size_override("font_size", int(cfg.get("font_size", font_cfg.get("font_size", 18))))
		var ls: int = int(cfg.get("letter_spacing", font_cfg.get("letter_spacing", 0)))
		_apply_letter_spacing_via_font(btn, ls)
	else:
		var ls: int = int(cfg.get("letter_spacing", 0))
		_apply_letter_spacing_via_font(btn, ls)
	apply_button_hover_translate(btn)

## Applies the cancellation 9-slice button style (same as validation but from buttons.cancellation).
static func apply_cancellation_to_button(btn: Button, cancellation_cfg: Dictionary = {}, font_size_key: String = "medium") -> void:
	var cfg := cancellation_cfg if not cancellation_cfg.is_empty() else get_cancellation_config()
	apply_validation_to_button(btn, cfg, font_size_key)

## Applies highlight style and animated alpha-aware glow around the button shape.
static func apply_highlight_to_button(btn: Button, highlight_cfg: Dictionary = {}, font_size_key: String = "medium") -> void:
	if btn == null:
		return
	var cfg := highlight_cfg if not highlight_cfg.is_empty() else get_highlight_config()
	apply_validation_to_button(btn, cfg, font_size_key)
	_attach_highlight_glow(btn, cfg)

static func _attach_highlight_glow(btn: Button, cfg: Dictionary) -> void:
	var asset_path: String = str(cfg.get("asset", ""))
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var tex: Texture2D = _resolve_button_texture(asset_path)
	if tex == null:
		return

	var glow_node: TextureRect = btn.get_node_or_null("HighlightGlowTexture")
	if glow_node == null:
		glow_node = TextureRect.new()
		glow_node.name = "HighlightGlowTexture"
		glow_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow_node.texture = tex
		glow_node.z_index = -1
		glow_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow_node.stretch_mode = TextureRect.STRETCH_SCALE
		btn.add_child(glow_node)
	else:
		glow_node.texture = tex

	var extra_margin: float = maxf(4.0, float(cfg.get("glow_thickness", 6.0)) + 2.0)
	glow_node.offset_left = -extra_margin
	glow_node.offset_top = -extra_margin
	glow_node.offset_right = extra_margin
	glow_node.offset_bottom = extra_margin

	var mat: ShaderMaterial = glow_node.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = HIGHLIGHT_GLOW_SHADER_CODE
		glow_node.material = mat

	var glow_color := Color.from_string(str(cfg.get("glow_color", "#FFD86B")), Color(1.0, 0.85, 0.42, 1.0))
	mat.set_shader_parameter("glow_color", glow_color)
	mat.set_shader_parameter("glow_thickness", maxf(1.0, float(cfg.get("glow_thickness", 6.0))))
	mat.set_shader_parameter("glow_intensity", maxf(0.0, float(cfg.get("glow_intensity", 1.25))))
	mat.set_shader_parameter("pulse_frequency", maxf(0.05, float(cfg.get("pulse_frequency", 1.6))))
	mat.set_shader_parameter("pulse_amplitude", maxf(0.0, float(cfg.get("pulse_amplitude", 0.22))))
	mat.set_shader_parameter("source_tex_size", tex.get_size())

static func _resolve_button_texture(asset_path: String) -> Texture2D:
	var ext: String = asset_path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp"]:
		var tex_res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
		return tex_res as Texture2D
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var anims: Array = frames.get_animation_names()
		if anims.is_empty():
			return null
		var anim: StringName = anims[0]
		if frames.get_frame_count(anim) <= 0:
			return null
		return frames.get_frame_texture(anim, 0)
	return null

const GREYSCALE_SHADER_CODE := """
shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(g), c.rgb, saturation) * brightness;
	COLOR = c;
}
"""

## Applies (or removes) a desaturated/greyscale look on a CanvasItem to signal a
## disabled/locked state while keeping the artwork readable. Pass enabled=false
## to restore the normal colors (only removes a greyscale material it added).
static func set_greyscale(ci: CanvasItem, enabled: bool, brightness: float = 0.7) -> void:
	if not is_instance_valid(ci):
		return
	if not enabled:
		var current: ShaderMaterial = ci.material as ShaderMaterial
		if current != null and current.shader != null and current.shader.code == GREYSCALE_SHADER_CODE:
			ci.material = null
		return
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = GREYSCALE_SHADER_CODE
	mat.set_shader_parameter("saturation", 0.0)
	mat.set_shader_parameter("brightness", clampf(brightness, 0.0, 1.0))
	ci.material = mat
