extends Control
## GeneratorPanel — panneau d'un generateur idle (spec homeScreenGame.md §8.3-8.4).
## Fond = triangle rectangle isocele dessine en _draw() (angle droit au coin
## ecran, hypotenuse face au vaisseau) : jamais deforme selon la largeur, le
## panneau prend la taille du noeud-repere de IdleFactoryZone.tscn.
## 100 % affichage : lit get_generator_view_data() et relaie les actions au
## manager. Le refresh est pilote par IdleFactoryRoot (pas de boucle locale).
## La jauge de charge ET le bouton BOOST vivent dans la ResourceStrip (sous
## chaque ressource), le nom de la ressource aussi. Le triangle ne porte que :
##   - cartouche niveau (nombre seul, cap 99) a l'angle droit ;
##   - bouton DEBLOQUER/AMELIORER (verbe + couts) cale au bord vertical
##     (gauche sur les triangles de gauche, droite sur ceux de droite) ;
##   - icone de la ressource, grossie, centree au centroide du triangle.
class_name IdleGeneratorPanel

const NumberFormat = preload("res://scenes/mechanics/number_format.gd")

var generator_id := ""
var _cfg: Dictionary = {}
var _ui_cfg: Dictionary = {}
var _res_color := Color.WHITE
var _corner := 0 # 0=HG, 1=HD, 2=BG, 3=BD (angle droit du triangle a ce coin)

var _icon: Control
var _level_badge: PanelContainer
var _level_label: Label
var _action_btn: Button
var _action_verb_label: Label
var _cost_label: Label
var _crystal_pair: Control
var _crystal_cost_label: Label
var _overdrive_active := false

func setup(gen_id: String, config: Dictionary) -> void:
	generator_id = gen_id
	_cfg = config
	var ui_v: Variant = config.get("ui", {})
	_ui_cfg = ui_v if ui_v is Dictionary else {}
	var res_id := str(_view().get("resource_id", ""))
	_res_color = _resource_color(res_id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # seuls les boutons interceptent
	_build_ui()
	refresh()

func _view() -> Dictionary:
	return IdleFactoryManager.get_generator_view_data(generator_id)

func _resource_cfg(res_id: String) -> Dictionary:
	var resources: Variant = _cfg.get("resources", {})
	if resources is Dictionary:
		var entry: Variant = (resources as Dictionary).get(res_id, {})
		if entry is Dictionary:
			return entry
	return {}

func _resource_color(res_id: String) -> Color:
	return Color.from_string(str(_resource_cfg(res_id).get("color", "#FFFFFF")), Color.WHITE)

## corner : 0 = haut-gauche, 1 = haut-droite, 2 = bas-gauche, 3 = bas-droite.
## Repositionne le contenu vers l'angle droit (partie epaisse du triangle).
func set_corner(corner: int) -> void:
	_corner = corner
	_anchor_content()
	queue_redraw()

# =============================================================================
# DESSIN DU TRIANGLE (procedural — jamais deforme)
# =============================================================================

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var pts := _triangle_points(w, h)
	var base := Color.from_string(str(_ui_cfg.get("triangle_base_color", "#10141F")), Color(0.06, 0.08, 0.12))
	var tint := clampf(float(_ui_cfg.get("triangle_tint_ratio", 0.35)), 0.0, 1.0)
	var fill := base.lerp(_res_color, tint)
	fill.a = clampf(float(_ui_cfg.get("triangle_fill_alpha", 0.92)), 0.0, 1.0)
	draw_colored_polygon(pts, fill)
	# Bordure (glow couleur ressource pendant l'Overdrive).
	var bw := float(_ui_cfg.get("triangle_border_width_px", 3.0))
	if bw > 0.0:
		var border := _res_color
		if _overdrive_active:
			border = _res_color.lightened(0.25)
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, border, bw, true)

## Sommets du triangle rectangle : angle droit au coin ecran, les deux cathetes
## suivent les bords du repere, hypotenuse vers le vaisseau. Isocele si repere carre.
func _triangle_points(w: float, h: float) -> PackedVector2Array:
	match _corner:
		1: # haut-droite : angle droit en (w,0)
			return PackedVector2Array([Vector2(w, 0), Vector2(0, 0), Vector2(w, h)])
		2: # bas-gauche : angle droit en (0,h)
			return PackedVector2Array([Vector2(0, h), Vector2(0, 0), Vector2(w, h)])
		3: # bas-droite : angle droit en (w,h)
			return PackedVector2Array([Vector2(w, h), Vector2(w, 0), Vector2(0, h)])
		_: # haut-gauche : angle droit en (0,0)
			return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(0, h)])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_anchor_content()
		queue_redraw()

# =============================================================================
# CONSTRUCTION DU CONTENU
# =============================================================================

func _build_ui() -> void:
	# Icone de la ressource produite, grossie, centree au centroide du triangle.
	var res_id := str(_view().get("resource_id", ""))
	_icon = _make_resource_icon(res_id, float(_ui_cfg.get("icon_size_px", 60.0)))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Cartouche niveau : encadre couleur ressource, nombre seul (cap 99),
	# positionne a l'angle droit du triangle.
	_level_badge = PanelContainer.new()
	_level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = _res_color.darkened(0.55)
	badge_style.border_color = _res_color
	badge_style.border_width_left = 2
	badge_style.border_width_right = 2
	badge_style.border_width_top = 2
	badge_style.border_width_bottom = 2
	badge_style.corner_radius_top_left = 6
	badge_style.corner_radius_top_right = 6
	badge_style.corner_radius_bottom_left = 6
	badge_style.corner_radius_bottom_right = 6
	badge_style.content_margin_left = 7
	badge_style.content_margin_right = 7
	badge_style.content_margin_top = 3
	badge_style.content_margin_bottom = 3
	_level_badge.add_theme_stylebox_override("panel", badge_style)
	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("title_font_size", 15)))
	_level_label.add_theme_color_override("font_color", Color.WHITE)
	_level_badge.add_child(_level_label)
	add_child(_level_badge)

	# Bouton d'action (DEBLOQUER / AMELIORER) : verbe + couts DANS le bouton.
	_action_btn = Button.new()
	_action_btn.custom_minimum_size = Vector2(150, 48)
	_action_btn.pressed.connect(_on_action_pressed)
	add_child(_action_btn)

	var btn_vbox := VBoxContainer.new()
	btn_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 1)
	btn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_btn.add_child(btn_vbox)

	_action_verb_label = Label.new()
	_action_verb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_verb_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("name_font_size", 14)))
	btn_vbox.add_child(_action_verb_label)

	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_vbox.add_child(cost_row)

	var cost_res := str(_view().get("cost_resource_id", ""))
	cost_row.add_child(_make_resource_icon(cost_res, 18.0))
	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("value_font_size", 16)))
	cost_row.add_child(_cost_label)

	# Paire cristaux (surcout flat) — visible uniquement si crystal_flat_cost > 0.
	var crystal_hbox := HBoxContainer.new()
	crystal_hbox.add_theme_constant_override("separation", 4)
	crystal_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(crystal_hbox)
	_crystal_pair = crystal_hbox
	crystal_hbox.add_child(_make_resource_icon("crystals", 18.0))
	_crystal_cost_label = Label.new()
	_crystal_cost_label.add_theme_font_size_override("font_size", int(_ui_cfg.get("value_font_size", 16)))
	crystal_hbox.add_child(_crystal_cost_label)
	# BOOST/jauge/nom de ressource : dans la ResourceStrip, pas ici.

	_anchor_content()

## Positionnement explicite selon le coin :
##   - rangee [cartouche niveau | bouton] le long de la cathete horizontale
##     (en haut pour les triangles hauts, en bas pour les bas), calee contre la
##     cathete verticale (gauche/droite) — la ou le triangle est le plus large ;
##   - icone centree au centroide du triangle (moyenne des 3 sommets).
func _anchor_content() -> void:
	if _action_btn == null:
		return
	var inset := float(_ui_cfg.get("triangle_content_inset_px", 12.0))
	var left := _corner == 0 or _corner == 2
	var top := _corner == 0 or _corner == 1

	_level_badge.reset_size()
	var badge_sz := _level_badge.size
	var btn_sz := _action_btn.custom_minimum_size
	_action_btn.size = btn_sz
	var row_h := maxf(badge_sz.y, btn_sz.y)
	var row_y := inset if top else size.y - row_h - inset

	if left:
		_level_badge.position = Vector2(inset, row_y + (row_h - badge_sz.y) / 2.0)
		_action_btn.position = Vector2(inset + badge_sz.x + 6.0, row_y)
	else:
		_level_badge.position = Vector2(size.x - inset - badge_sz.x, row_y + (row_h - badge_sz.y) / 2.0)
		_action_btn.position = Vector2(size.x - inset - badge_sz.x - 6.0 - btn_sz.x, row_y)

	# Centroide du triangle : a 1/3 des cathetes depuis l'angle droit.
	var cx := size.x / 3.0 if left else size.x * 2.0 / 3.0
	var cy := size.y / 3.0 if top else size.y * 2.0 / 3.0
	var icon_sz: Vector2 = _icon.get_combined_minimum_size()
	_icon.size = icon_sz
	_icon.position = Vector2(cx - icon_sz.x / 2.0, cy - icon_sz.y / 2.0)

## Icone d'une ressource : asset si present sur disque, sinon placeholder
## procedural (pastille couleur ressource + initiale) — cablage Ludo futur pret.
func _make_resource_icon(res_id: String, size_px: float) -> Control:
	var res_cfg := _resource_cfg(res_id)
	var icon_path := str(res_cfg.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(icon_path)
		tex_rect.custom_minimum_size = Vector2(size_px, size_px)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex_rect
	if res_id == "crystals" and DataManager and DataManager.has_method("get_texture_from_resource_path"):
		# Meme symbole que la top bar (shared:crystal_icon) : l'asset partage est un
		# SpriteFrames (.tres) — get_texture_from_resource_path en extrait la 1re
		# frame en Texture2D (un load() direct dans TextureRect.texture echoue).
		var crystal_tex: Texture2D = DataManager.get_texture_from_resource_path("shared:crystal_icon")
		if crystal_tex:
			var crystal_rect := TextureRect.new()
			crystal_rect.texture = crystal_tex
			crystal_rect.custom_minimum_size = Vector2(size_px, size_px)
			crystal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			crystal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return crystal_rect
	# Placeholder : pastille + initiale.
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	var style := StyleBoxFlat.new()
	style.bg_color = _resource_color(res_id).darkened(0.35)
	style.corner_radius_top_left = int(size_px / 2.0)
	style.corner_radius_top_right = int(size_px / 2.0)
	style.corner_radius_bottom_left = int(size_px / 2.0)
	style.corner_radius_bottom_right = int(size_px / 2.0)
	holder.add_theme_stylebox_override("panel", style)
	var letter := Label.new()
	letter.text = str(res_cfg.get("initial", res_id.substr(0, 1).to_upper()))
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", int(size_px * 0.5))
	letter.add_theme_color_override("font_color", Color.WHITE)
	holder.add_child(letter)
	return holder

# =============================================================================
# REFRESH (appele par IdleFactoryRoot a refresh_hz)
# =============================================================================

func refresh() -> void:
	if generator_id == "" or not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	var view := _view()
	var unlocked := bool(view.get("unlocked", false))

	# Cartouche niveau : nombre seul, cap affichage 99, cache tant que verrouille.
	_level_badge.visible = unlocked
	if unlocked:
		_level_label.text = str(mini(int(view.get("level", 0)), 99))
		_anchor_content() # la largeur du cartouche depend du nombre (1 vs 2 chiffres)
	_action_verb_label.text = _tr_key("idle_upgrade", "AMELIORER") if unlocked else _tr_key("idle_unlock", "DEBLOQUER")

	# Couts DANS le bouton : monnaie croissante + surcout flat en cristaux.
	_cost_label.text = NumberFormat.compact(float(int(view.get("next_cost", 0))))
	var crystal_flat := int(view.get("crystal_flat_cost", 0))
	_crystal_pair.visible = crystal_flat > 0
	if crystal_flat > 0:
		_crystal_cost_label.text = NumberFormat.compact(float(crystal_flat))
		_crystal_cost_label.add_theme_color_override("font_color",
			Color.WHITE if bool(view.get("can_afford_crystals", false)) else Color("#FF6A5E"))
	_cost_label.add_theme_color_override("font_color",
		Color.WHITE if bool(view.get("can_afford_cost", false)) else Color("#FF6A5E"))
	var can_act := (unlocked or bool(view.get("can_unlock", false))) and bool(view.get("can_afford", false))
	_action_btn.disabled = not can_act

	# Glow bordure pendant l'Overdrive verrouille uniquement (spec §8.5) —
	# seul marqueur d'Overdrive restant sur le triangle (pas de texte).
	var overdrive := bool(view.get("overdrive_active", false))
	if overdrive != _overdrive_active:
		_overdrive_active = overdrive
		queue_redraw()

# =============================================================================
# ACTIONS
# =============================================================================

func _on_action_pressed() -> void:
	var view := _view()
	var ok: bool
	if bool(view.get("unlocked", false)):
		ok = IdleFactoryManager.upgrade_generator(generator_id)
	else:
		ok = IdleFactoryManager.unlock_generator(generator_id)
	if AudioManager:
		AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav" if ok else "res://assets/sfx/ui_deny.wav", 0.0)
	refresh()

## Gating : grise le panneau et avale ses clics via un bloqueur interne
## (le vaisseau central et le reste de la home restent interactifs).
var _lock_blocker: Control = null

func set_locked(locked: bool) -> void:
	modulate = Color(0.55, 0.55, 0.6) if locked else Color.WHITE
	if locked and _lock_blocker == null:
		_lock_blocker = ColorRect.new()
		(_lock_blocker as ColorRect).color = Color(0, 0, 0, 0)
		_lock_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lock_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_lock_blocker)
	elif not locked and _lock_blocker != null:
		_lock_blocker.queue_free()
		_lock_blocker = null

func _tr_key(key: String, fallback: String) -> String:
	if LocaleManager and LocaleManager.has_method("translate"):
		var t := str(LocaleManager.translate(key))
		if t != key:
			return t
	return fallback
