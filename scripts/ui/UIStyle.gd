extends RefCounted

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
