extends PanelContainer
## ResourceStrip — ligne recapitulative des 4 ressources idle produites
## (Zelerium | Neorite | Ionium | Tritanium). Les cristaux n'y figurent plus :
## ils sont affiches en permanence dans la top bar (MenuHeader, MAJ live via
## ProfileManager.crystals_changed).
## Fond : plaque metallique 9-slice (ui.strip_bg_asset) si presente,
## sinon transparent (cellules seules).
class_name IdleResourceStrip

const NumberFormat = preload("res://scenes/mechanics/number_format.gd")

var _cfg: Dictionary = {}
var _ui_cfg: Dictionary = {}
var _row: HBoxContainer
# res_id -> { qty: Label, rate: Label, gauge_track: Panel, gauge_fill: Panel,
#             boost_btn: Button, color: Color, display_ratio: float }
var _cells: Dictionary = {}
# res_id -> generator_id (la jauge de charge/boost vit sous la ressource produite)
var _res_to_generator: Dictionary = {}
var _steps_max := 20
var _climb_speed := 6.7 # 1 / duree de remontee (s) — vitesse de retour de jauge apres un tap

func setup(config: Dictionary) -> void:
	_cfg = config
	var ui_v: Variant = config.get("ui", {})
	_ui_cfg = ui_v if ui_v is Dictionary else {}

	var boost_v: Variant = config.get("boost", {})
	if boost_v is Dictionary:
		_steps_max = maxi(1, int((boost_v as Dictionary).get("steps_to_overdrive", 20)))
	_climb_speed = 1.0 / maxf(0.02, float(_ui_cfg.get("strip_gauge_climb_seconds", 0.15)))

	var gens_v: Variant = config.get("generators", [])
	if gens_v is Array:
		for gen in gens_v:
			if gen is Dictionary:
				_res_to_generator[str((gen as Dictionary).get("resource_id", ""))] = str((gen as Dictionary).get("id", ""))

	var bg_path := str(_ui_cfg.get("strip_bg_asset", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var bg_style := StyleBoxTexture.new()
		bg_style.texture = load(bg_path)
		var slice := 24
		bg_style.texture_margin_left = slice
		bg_style.texture_margin_right = slice
		bg_style.texture_margin_top = slice
		bg_style.texture_margin_bottom = slice
		bg_style.content_margin_left = 10
		bg_style.content_margin_right = 10
		bg_style.content_margin_top = 6
		bg_style.content_margin_bottom = 6
		add_theme_stylebox_override("panel", bg_style)
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(float(_ui_cfg.get("strip_cell_spacing_px", 6.0))))
	add_child(_row)

	var order_v: Variant = config.get("resource_order", [])
	var order: Array = order_v if order_v is Array else []
	for res_id in order:
		# Les cristaux ne sont plus monitores ici : deja affiches en permanence
		# dans la top bar (MenuHeader, MAJ live via ProfileManager.crystals_changed).
		if str(res_id) == "crystals":
			continue
		_build_cell(str(res_id))
	refresh()

func _resource_cfg(res_id: String) -> Dictionary:
	var resources: Variant = _cfg.get("resources", {})
	if resources is Dictionary:
		var entry: Variant = (resources as Dictionary).get(res_id, {})
		if entry is Dictionary:
			return entry
	return {}

func _build_cell(res_id: String) -> void:
	var res_cfg := _resource_cfg(res_id)
	var color := Color.from_string(str(res_cfg.get("color", "#FFFFFF")), Color.WHITE)

	var cell := PanelContainer.new()
	# Largeurs strictement egales : min width nulle + clip, la repartition
	# EXPAND_FILL du HBox n'est plus influencee par la longueur des textes
	# (les labels utilisent l'ellipsis pour ne pas imposer leur largeur min).
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = 1.0
	cell.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_string(str(_ui_cfg.get("panel_bg_color", "#10141FE6")), Color(0.06, 0.08, 0.12, 0.9))
	style.border_color = color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", style)
	_row.add_child(cell)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	cell.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 3)
	vbox.add_child(name_row)
	name_row.add_child(_make_icon(res_id, 16.0, color))
	var name_label := Label.new()
	name_label.text = _tr_key(str(res_cfg.get("name_key", res_id)), res_id.to_upper())
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("strip_name_font_size", 12)))
	name_label.add_theme_color_override("font_color", color)
	name_row.add_child(name_label)

	var qty_label := Label.new()
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	qty_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("strip_value_font_size", 18)))
	vbox.add_child(qty_label)

	var rate_label := Label.new()
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rate_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("strip_rate_font_size", 12)))
	rate_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	vbox.add_child(rate_label)

	# Jauge de charge/boost sous la ressource (spec — deplacee depuis le panneau).
	# Uniquement pour les ressources produites par un generateur (pas les cristaux).
	# Track/fill = Panel (pas PanelContainer) : Panel n'etire pas son enfant, donc
	# la largeur du fill (ratio de charge) est respectee.
	var gauge_track: Panel = null
	var gauge_fill: Panel = null
	if _res_to_generator.has(res_id):
		var gauge_h := float(_ui_cfg.get("strip_gauge_height_px", 7.0))
		gauge_track = Panel.new()
		gauge_track.custom_minimum_size = Vector2(0, gauge_h)
		gauge_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gauge_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track_style := StyleBoxFlat.new()
		track_style.bg_color = Color.from_string(str(_ui_cfg.get("gauge_bg_color", "#1A2030")), Color(0.1, 0.12, 0.19))
		track_style.corner_radius_top_left = 3
		track_style.corner_radius_top_right = 3
		track_style.corner_radius_bottom_left = 3
		track_style.corner_radius_bottom_right = 3
		gauge_track.add_theme_stylebox_override("panel", track_style)
		vbox.add_child(gauge_track)
		gauge_fill = Panel.new()
		gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gauge_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE) # colle a gauche, hauteur pleine
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = color
		fill_style.corner_radius_top_left = 3
		fill_style.corner_radius_top_right = 3
		fill_style.corner_radius_bottom_left = 3
		fill_style.corner_radius_bottom_right = 3
		gauge_fill.add_theme_stylebox_override("panel", fill_style)
		gauge_track.add_child(gauge_fill)

	# Bouton BOOST sous la jauge (deplace depuis le triangle). Pendant
	# l'Overdrive : temps restant a la place de "BOOST", non-interactif mais
	# pleine opacite (mouse_filter IGNORE, pas disabled).
	var boost_btn: Button = null
	if _res_to_generator.has(res_id):
		boost_btn = Button.new()
		boost_btn.text = _tr_key("idle_boost", "BOOST")
		boost_btn.custom_minimum_size = Vector2(0, float(_ui_cfg.get("strip_boost_height_px", 30.0)))
		boost_btn.add_theme_font_size_override("font_size", int(_ui_cfg.get("strip_boost_font_size", 13)))
		boost_btn.pressed.connect(_on_boost_pressed.bind(res_id))
		vbox.add_child(boost_btn)

	_cells[res_id] = { "qty": qty_label, "rate": rate_label, "gauge_track": gauge_track, "gauge_fill": gauge_fill, "boost_btn": boost_btn, "color": color, "display_ratio": 0.0 }

func _make_icon(res_id: String, size_px: float, color: Color) -> Control:
	var res_cfg := _resource_cfg(res_id)
	var icon_path := str(res_cfg.get("icon", ""))
	if res_id == "crystals" and DataManager and DataManager.has_method("get_texture_from_resource_path"):
		# Meme symbole que la top bar : SpriteFrames partage -> 1re frame en Texture2D.
		var crystal_tex: Texture2D = DataManager.get_texture_from_resource_path("shared:crystal_icon")
		if crystal_tex:
			var crystal_rect := TextureRect.new()
			crystal_rect.texture = crystal_tex
			crystal_rect.custom_minimum_size = Vector2(size_px, size_px)
			crystal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			crystal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return crystal_rect
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(icon_path)
		tex_rect.custom_minimum_size = Vector2(size_px, size_px)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex_rect
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(size_px, size_px)
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.3)
	style.corner_radius_top_left = int(size_px / 2.0)
	style.corner_radius_top_right = int(size_px / 2.0)
	style.corner_radius_bottom_left = int(size_px / 2.0)
	style.corner_radius_bottom_right = int(size_px / 2.0)
	dot.add_theme_stylebox_override("panel", style)
	return dot

func refresh() -> void:
	if not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	# Production effective par ressource = somme des generateurs qui la produisent.
	var rates: Dictionary = {}
	var mults: Dictionary = {}
	for gen_id in IdleFactoryManager.get_generator_ids():
		var view: Dictionary = IdleFactoryManager.get_generator_view_data(gen_id)
		var res_id := str(view.get("resource_id", ""))
		rates[res_id] = float(rates.get(res_id, 0.0)) + float(view.get("effective_production", 0.0))
		mults[res_id] = float(view.get("multiplier", 1.0))
	for res_id in _cells.keys():
		var cell: Dictionary = _cells[res_id]
		(cell["qty"] as Label).text = NumberFormat.compact(IdleFactoryManager.get_resource_amount(str(res_id)))
		var rate_label := cell["rate"] as Label
		var line := "+" + IdleFactoryManager.format_rate(float(rates.get(res_id, 0.0))) + "/s"
		var mult := float(mults.get(res_id, 1.0))
		if mult > 1.001:
			line += "  ×" + (str(int(mult)) if is_equal_approx(mult, round(mult)) else str(snappedf(mult, 0.1)))
		rate_label.text = line
		_refresh_boost_button(str(res_id))

## Etat du bouton BOOST d'une cellule : "BOOST" tappable si le generateur est
## debloque ; temps restant (pleine opacite, non-interactif) pendant l'Overdrive ;
## grise tant que le generateur est verrouille.
func _refresh_boost_button(res_id: String) -> void:
	var cell: Dictionary = _cells.get(res_id, {})
	var btn: Variant = cell.get("boost_btn")
	if btn == null or not is_instance_valid(btn):
		return
	var b := btn as Button
	var gen_id := str(_res_to_generator.get(res_id, ""))
	var view: Dictionary = IdleFactoryManager.get_generator_view_data(gen_id)
	if bool(view.get("overdrive_active", false)):
		b.text = IdleFactoryManager.format_duration(int(view.get("overdrive_remaining_sec", 0)))
		b.disabled = false
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_NONE
	else:
		b.text = _tr_key("idle_boost", "BOOST")
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.focus_mode = Control.FOCUS_ALL
		b.disabled = not bool(view.get("unlocked", false))

func _on_boost_pressed(res_id: String) -> void:
	var gen_id := str(_res_to_generator.get(res_id, ""))
	if gen_id == "" or not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	var steps := IdleFactoryManager.tap_generator(gen_id)
	if steps <= 0:
		return
	var cell: Dictionary = _cells.get(res_id, {})
	var btn: Variant = cell.get("boost_btn")
	var color: Color = cell.get("color", Color.WHITE)
	# Feedback : squash du bouton + texte flottant +10 % / OVERDRIVE.
	if btn != null and is_instance_valid(btn):
		var b := btn as Button
		b.pivot_offset = b.size / 2.0
		var tween := create_tween()
		tween.tween_property(b, "scale", Vector2(0.85, 0.85), 0.05)
		tween.tween_property(b, "scale", Vector2.ONE, 0.08)
	var steps_max := int(IdleFactoryManager.get_generator_view_data(gen_id).get("steps_max", 20))
	if steps >= steps_max:
		_spawn_float_text(res_id, _tr_key("idle_overdrive", "OVERDRIVE ×3"), color)
		if AudioManager:
			AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav", 0.0)
	else:
		var boost_v: Variant = _cfg.get("boost", {})
		var tap_pct := int(float((boost_v as Dictionary).get("tap_percent", 10.0))) if boost_v is Dictionary else 10
		_spawn_float_text(res_id, "+" + str(tap_pct) + " %", color)
	refresh()

## Texte flottant "+10 %" : apparait a DROITE du "+x/s" de la cellule concernee,
## sans affecter le centrage du "+x/s" (position calculee depuis la fin du texte
## centre, label hors layout enfant du rate_label).
func _spawn_float_text(res_id: String, text: String, color: Color) -> void:
	var cell: Dictionary = _cells.get(res_id, {})
	var rate: Variant = cell.get("rate")
	if rate == null or not is_instance_valid(rate):
		return
	var rate_label := rate as Label
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(_ui_cfg.get("strip_rate_font_size", 16)))
	label.add_theme_color_override("font_color", color.lightened(0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 10
	rate_label.add_child(label)
	# Fin du texte centre du "+x/s" : centre de la cellule + moitie de la largeur
	# rendue du texte, puis petit ecart.
	var font := rate_label.get_theme_font("font")
	var font_sz := rate_label.get_theme_font_size("font_size")
	var text_w := font.get_string_size(rate_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
	label.position = Vector2(rate_label.size.x / 2.0 + text_w / 2.0 + 6.0, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 6.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)

## Animation par frame des jauges de charge/boost (independante du refresh 8 Hz).
## Cible = (steps/steps_max) × ratio_de_temps_restant : la barre descend LINEAIREMENT
## jusqu'a 0 sur toute la fenetre de 5 s si le joueur ne tape plus (avertissement
## visuel). Un nouveau tap fait remonter la barre (animee) jusqu'au niveau de charge.
## Overdrive : cible = 1.0 (pleine verrouillee).
func _process(delta: float) -> void:
	if _cells.is_empty() or not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	for res_id in _cells.keys():
		var gen_id := str(_res_to_generator.get(res_id, ""))
		if gen_id == "":
			continue
		var cell: Dictionary = _cells[res_id]
		var track: Variant = cell.get("gauge_track")
		var fill: Variant = cell.get("gauge_fill")
		if track == null or fill == null or not is_instance_valid(track) or not is_instance_valid(fill):
			continue
		var target: float
		if IdleFactoryManager.is_overdrive_active(gen_id):
			target = 1.0
		else:
			var steps := IdleFactoryManager.get_charge_steps(gen_id)
			var remaining := IdleFactoryManager.get_temporary_remaining_ratio(gen_id)
			target = clampf(float(steps) / float(_steps_max), 0.0, 1.0) * remaining
		var disp := float(cell.get("display_ratio", 0.0))
		if target > disp:
			# Remontee animee (tap repris) vers le niveau de charge courant.
			disp = minf(target, disp + _climb_speed * delta)
		else:
			# Descente : suit exactement la cible = drain lineaire sur les 5 s.
			disp = target
		cell["display_ratio"] = disp
		# PRESET_LEFT_WIDE : ancre gauche + hauteur pleine ; largeur = offset_right.
		(fill as Control).offset_right = (track as Control).size.x * disp
		(fill as Control).visible = disp > 0.002

func _tr_key(key: String, fallback: String) -> String:
	if LocaleManager and LocaleManager.has_method("translate"):
		var t := str(LocaleManager.translate(key))
		if t != key:
			return t
	return fallback
