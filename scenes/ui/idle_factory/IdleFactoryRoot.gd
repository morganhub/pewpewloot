@tool
extends Control
## IdleFactoryRoot — racine de scenes/ui/idle_factory/IdleFactoryZone.tscn.
## Toute la disposition est EDITABLE AU PIXEL dans l'editeur Godot : deplace/
## redimensionne les noeuds-reperes de la .tscn (Control) et le contenu suit :
##   TriTopLeft / TriTopRight / TriBotLeft / TriBotRight -> 4 GeneratorPanel
##       (le triangle rectangle isocele est dessine pour remplir le repere,
##        angle droit au coin ecran, hypotenuse vers le vaisseau)
##   StripHost  -> ResourceStrip (ligne des 5 ressources, sous les triangles bas)
##   FinalHost  -> bouton unlock final 1M Tritanium
## Aucune logique economique ici : lecture via IdleFactoryManager, refresh
## mutualise a refresh_hz (un seul Timer pour tous les panneaux).
class_name IdleFactoryRoot

const GeneratorPanelScript = preload("res://scenes/ui/idle_factory/GeneratorPanel.gd")
const ResourceStripScript = preload("res://scenes/ui/idle_factory/ResourceStrip.gd")
const NumberFormat = preload("res://scenes/mechanics/number_format.gd")

## Ordre impose : generators[i] -> ce repere avec ce coin (spec §8.1).
const CORNER_MARKERS := [
	{ "node": "TriTopLeft", "corner": 0 },
	{ "node": "TriTopRight", "corner": 1 },
	{ "node": "TriBotLeft", "corner": 2 },
	{ "node": "TriBotRight", "corner": 3 },
]

var _cfg: Dictionary = {}
var _ui_cfg: Dictionary = {}
var _panels: Array = []
var _strip: Node = null
var _final_btn: Button
var _locked_overlay: Label
var _refresh_timer: Timer
# FINAL FORM (final_boss.md §3.3) : usine remplacee par 5 decos animees inactives.
var _final_form_built: bool = false
var _final_pulse_tween: Tween = null

func _ready() -> void:
	# Editeur : preview seule (les autoloads/managers ne tournent pas).
	if Engine.is_editor_hint():
		set_process(true)
		return
	set_process(false) # _process ne sert qu'a la preview editeur
	# Le root laisse passer les clics (vaisseau central tapable) ; seuls les
	# panneaux/boutons enfants interceptent.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cfg = DataManager.get_idle_factory_config() if DataManager else {}
	var ui_v: Variant = _cfg.get("ui", {})
	_ui_cfg = ui_v if ui_v is Dictionary else {}
	if _cfg.is_empty():
		visible = false
		return
	if _is_final_form():
		# Retour sur la home apres l'achat : reconstruction statique, aucune
		# choregraphie (final_boss.md §2).
		_final_form_built = true
		_build_final_form(false)
		_build_final_button()
	else:
		_build_panels()
		_build_strip()
		_build_final_button()
		_build_locked_overlay()
		_apply_gating()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0 / maxf(1.0, float(_ui_cfg.get("refresh_hz", 8.0)))
	_refresh_timer.timeout.connect(_refresh_all)
	add_child(_refresh_timer)
	_refresh_timer.start()

	if IdleFactoryManager:
		IdleFactoryManager.generator_state_changed.connect(func(_id): _refresh_all())
		# Premier achat : la choregraphie + le lancement vivent EXCLUSIVEMENT ici
		# (un seul chemin — final_boss.md §3.3.4).
		IdleFactoryManager.final_unlock_purchased.connect(_on_final_unlock_purchased)
	if ProfileManager and ProfileManager.has_signal("level_up"):
		ProfileManager.level_up.connect(func(_lvl, _pts): _apply_gating())

## Reevaluation du gating + refresh complet (retour sur la home apres un run).
func refresh_gating() -> void:
	if _is_final_form():
		_refresh_final_button()
		return
	_apply_gating()
	_refresh_all()

# =============================================================================
# CONSTRUCTION (contenu ancre sur les reperes de la .tscn)
# =============================================================================

## Recupere un repere par nom ; cree un Control ancre par defaut si absent
## (robustesse si la .tscn est incomplete).
func _marker(node_name: String, fallback_preset: int) -> Control:
	var n := get_node_or_null(NodePath(node_name))
	if n is Control:
		return n as Control
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(fallback_preset)
	add_child(c)
	return c

func _build_panels() -> void:
	if not IdleFactoryManager:
		return
	var gen_ids: Array[String] = IdleFactoryManager.get_generator_ids()
	for i in range(gen_ids.size()):
		if i >= CORNER_MARKERS.size():
			break
		var marker := _marker(str(CORNER_MARKERS[i]["node"]), Control.PRESET_TOP_LEFT)
		var panel := GeneratorPanelScript.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		marker.add_child(panel)
		panel.setup(gen_ids[i], _cfg)
		panel.call("set_corner", int(CORNER_MARKERS[i]["corner"]))
		_panels.append(panel)

func _build_strip() -> void:
	var host := _marker("StripHost", Control.PRESET_BOTTOM_WIDE)
	_strip = ResourceStripScript.new()
	(_strip as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(_strip)
	_strip.call("setup", _cfg)

func _build_final_button() -> void:
	var host := _marker("FinalHost", Control.PRESET_CENTER_TOP)
	_final_btn = Button.new()
	_final_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_final_btn.add_theme_font_size_override("font_size", int(_ui_cfg.get("final_button_font_size", 16)))
	_final_btn.pressed.connect(_on_final_pressed)
	host.add_child(_final_btn)
	_refresh_final_button()

func _refresh_final_button() -> void:
	if not _final_btn or not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	var final_cfg: Dictionary = _cfg.get("final_unlock", {})
	if IdleFactoryManager.is_final_unlock_purchased():
		# FINAL FORM : le bouton devient la porte d'entree permanente du mode
		# (final_boss.md §3.3.3) — actif, relabelle, pulse doux.
		_final_btn.text = _tr_key("final_boss_enter", "BOSS FINAL")
		_final_btn.disabled = false
		_start_final_button_pulse()
		return
	var cost := float(final_cfg.get("cost", 1000000))
	var res_id := str(final_cfg.get("resource_id", "tritanium"))
	_final_btn.text = NumberFormat.compact(cost) + " " + _tr_key("idle_resource_" + res_id, res_id.to_upper())
	_final_btn.disabled = IdleFactoryManager.get_resource_amount(res_id) < cost

func _start_final_button_pulse() -> void:
	if _final_pulse_tween and _final_pulse_tween.is_valid():
		return
	_final_pulse_tween = create_tween().set_loops()
	_final_pulse_tween.tween_property(_final_btn, "modulate", Color(1.25, 1.15, 0.85), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_final_pulse_tween.tween_property(_final_btn, "modulate", Color.WHITE, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_final_pressed() -> void:
	# Deja achete : le bouton est le gateway — relance le mode, rien d'autre
	# (final_boss.md §3.3.3, un seul chemin pour la choregraphie).
	if IdleFactoryManager and IdleFactoryManager.is_ready() and IdleFactoryManager.is_final_unlock_purchased():
		_launch_final_boss()
		return
	var ok := IdleFactoryManager.purchase_final_unlock()
	if AudioManager:
		AudioManager.play_sfx("res://assets/sfx/ui_confirm.wav" if ok else "res://assets/sfx/ui_deny.wav", 0.0)
	_refresh_final_button()

# =============================================================================
# GATING (grise + banniere tant que player_level < unlock_player_level)
# =============================================================================

## Banniere non bloquante (le vaisseau central reste tapable) ; le blocage des
## clics est fait par panneau via GeneratorPanel.set_locked(). Ancree sur le
## repere LockedBanner si present, sinon centree en haut.
func _build_locked_overlay() -> void:
	var host := get_node_or_null("LockedBanner")
	_locked_overlay = Label.new()
	_locked_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locked_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_locked_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_overlay.add_theme_font_size_override("font_size", int(_ui_cfg.get("locked_overlay_font_size", 22)))
	_locked_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_locked_overlay.add_theme_constant_override("outline_size", 5)
	var required := int(_cfg.get("unlock_player_level", 10))
	_locked_overlay.text = _tr_key("idle_locked_level", "Débloqué au niveau {level}").replace("{level}", str(required))
	if host is Control:
		_locked_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		(host as Control).add_child(_locked_overlay)
	else:
		_locked_overlay.set_anchors_preset(Control.PRESET_CENTER)
		add_child(_locked_overlay)

func _apply_gating() -> void:
	if _is_final_form():
		return # Final form : plus de gating, plus de panneaux (final_boss.md §3.3)
	var required := int(_cfg.get("unlock_player_level", 10))
	var level := ProfileManager.get_player_level() if ProfileManager else 1
	var locked := level < required
	if _locked_overlay:
		_locked_overlay.visible = locked
	for panel in _panels:
		panel.call("set_locked", locked)
	if _final_btn:
		_final_btn.visible = not locked

# =============================================================================
# REFRESH MUTUALISE
# =============================================================================

func _refresh_all() -> void:
	if not visible or not IdleFactoryManager or not IdleFactoryManager.is_ready():
		return
	if _is_final_form():
		# Final form : seul le bouton reste vivant (final_boss.md §3.3.5).
		_refresh_final_button()
		return
	for panel in _panels:
		panel.call("refresh")
	_refresh_final_button()
	if _strip and is_instance_valid(_strip):
		_strip.call("refresh")

# =============================================================================
# FINAL FORM (final_boss.md §3) — apres l'achat 1M : usine gelee, 4 triangles +
# strip remplaces par 5 decos animees INACTIVES, bouton = gateway du mode 3D.
# =============================================================================

## Cle de coin (assets final_form.triangle_assets) dans l'ordre de CORNER_MARKERS.
const FINALFORM_CORNER_KEYS := ["tl", "tr", "bl", "br"]

func _is_final_form() -> bool:
	return IdleFactoryManager != null and IdleFactoryManager.is_ready() \
		and IdleFactoryManager.is_final_unlock_purchased()

func _final_form_cfg() -> Dictionary:
	var v: Variant = _cfg.get("final_form", {})
	return v if v is Dictionary else {}

## Construit les 5 decos (4 triangles + strip). `animated_intro` = pop-in
## sequentiel (premier achat) ; false = reconstruction statique (retour home).
func _build_final_form(animated_intro: bool) -> void:
	var ff := _final_form_cfg()
	var tri_assets_v: Variant = ff.get("triangle_assets", {})
	var tri_assets: Dictionary = tri_assets_v if tri_assets_v is Dictionary else {}
	var trans_v: Variant = ff.get("transition", {})
	var trans: Dictionary = trans_v if trans_v is Dictionary else {}
	var pop_sec := maxf(0.05, float(trans.get("pop_in_sec", 0.25)))
	var stagger := maxf(0.0, float(trans.get("pop_stagger_sec", 0.12)))
	var decos: Array = []
	for i in range(CORNER_MARKERS.size()):
		var marker := _marker(str(CORNER_MARKERS[i]["node"]), Control.PRESET_TOP_LEFT)
		var deco := _make_finalform_deco(str(tri_assets.get(FINALFORM_CORNER_KEYS[i], "")),
			int(CORNER_MARKERS[i]["corner"]), ff)
		marker.add_child(deco)
		decos.append(deco)
	var strip_host := _marker("StripHost", Control.PRESET_BOTTOM_WIDE)
	var strip_deco := _make_finalform_deco(str(ff.get("strip_asset", "")), -1, ff)
	strip_host.add_child(strip_deco)
	decos.append(strip_deco)
	if animated_intro:
		for i in range(decos.size()):
			var d: Control = decos[i]
			d.modulate.a = 0.0
			d.scale = Vector2.ONE * 0.85
			d.pivot_offset = d.size * 0.5
			var tw := create_tween()
			tw.tween_interval(float(i) * stagger)
			tw.tween_property(d, "modulate:a", 1.0, pop_sec)
			tw.parallel().tween_property(d, "scale", Vector2.ONE, pop_sec) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Une deco : wrapper Control inactif (MOUSE_FILTER_IGNORE) + visuel.
## Priorite : SpriteFrames anime (pattern ItemCard : AnimatedSprite2D enfant,
## recentre/rescale sur resized) > Texture2D etiree > fallback procedural
## (triangle Polygon2D au coin / rectangle) teinte fallback_color.
func _make_finalform_deco(asset_path: String, corner: int, ff: Dictionary) -> Control:
	var deco_wrap := Control.new()
	deco_wrap.name = "FinalFormDeco"
	deco_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var res: Resource = null
	if asset_path != "" and ResourceLoader.exists(asset_path):
		res = load(asset_path)
	if res is SpriteFrames:
		var anim := AnimatedSprite2D.new()
		anim.name = "AnimSprite"
		anim.sprite_frames = res as SpriteFrames
		var names: PackedStringArray = anim.sprite_frames.get_animation_names()
		var anim_name: StringName = &"default"
		if not anim.sprite_frames.has_animation(anim_name) and names.size() > 0:
			anim_name = StringName(names[0])
		if anim.sprite_frames.has_animation(anim_name):
			anim.play(anim_name)
		anim.centered = true
		deco_wrap.add_child(anim)
		var fit := func() -> void:
			var frame_size := _finalform_frame_size(anim)
			if frame_size.x > 0.0 and frame_size.y > 0.0:
				anim.scale = deco_wrap.size / frame_size
			anim.position = deco_wrap.size * 0.5
		deco_wrap.resized.connect(fit)
		fit.call_deferred()
	elif res is Texture2D:
		var rect := TextureRect.new()
		rect.texture = res as Texture2D
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deco_wrap.add_child(rect)
	else:
		# Fallback procedural : geometrie du GeneratorPanel (angle droit au coin
		# ecran) recoloree or, ou rectangle pour la strip (corner -1).
		var color := Color(str(ff.get("fallback_color", "#E8C347")))
		var poly := Polygon2D.new()
		poly.color = Color(color, 0.5)
		deco_wrap.add_child(poly)
		var update := func() -> void:
			poly.polygon = _finalform_fallback_pts(corner, deco_wrap.size)
		deco_wrap.resized.connect(update)
		update.call_deferred()
	# Pulse d'ambiance discret (decoratif, jamais interactif).
	var pulse_sec := maxf(0.3, float(ff.get("deco_pulse_sec", 2.4)))
	var pulse := create_tween().set_loops()
	pulse.tween_property(deco_wrap, "modulate:a", 0.82, pulse_sec * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(deco_wrap, "modulate:a", 1.0, pulse_sec * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return deco_wrap

func _finalform_frame_size(anim: AnimatedSprite2D) -> Vector2:
	if anim == null or anim.sprite_frames == null:
		return Vector2.ZERO
	var anim_name := anim.animation
	if anim.sprite_frames.get_frame_count(anim_name) <= 0:
		return Vector2.ZERO
	var tex := anim.sprite_frames.get_frame_texture(anim_name, 0)
	return tex.get_size() if tex else Vector2.ZERO

## Meme geometrie de triangle que GeneratorPanel/_draw editeur : angle droit au
## coin ecran (0=HG 1=HD 2=BG 3=BD) ; corner -1 = rectangle plein (strip).
func _finalform_fallback_pts(corner: int, s: Vector2) -> PackedVector2Array:
	match corner:
		0: return PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(0, s.y)])
		1: return PackedVector2Array([Vector2(s.x, 0), Vector2.ZERO, Vector2(s.x, s.y)])
		2: return PackedVector2Array([Vector2(0, s.y), Vector2.ZERO, Vector2(s.x, s.y)])
		3: return PackedVector2Array([Vector2(s.x, s.y), Vector2(s.x, 0), Vector2(0, s.y)])
		_: return PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)])

## PREMIER ACHAT (signal final_unlock_purchased) : choregraphie de
## transformation puis lancement auto du mode — chemin UNIQUE (§3.3.4).
func _on_final_unlock_purchased(_reward_id: String) -> void:
	if _final_form_built:
		_refresh_all()
		return
	_final_form_built = true
	var trans_v: Variant = _final_form_cfg().get("transition", {})
	var trans: Dictionary = trans_v if trans_v is Dictionary else {}
	var fade := maxf(0.05, float(trans.get("fade_out_sec", 0.5)))
	var tw := create_tween().set_parallel(true)
	for panel in _panels:
		if panel is CanvasItem and is_instance_valid(panel):
			tw.tween_property(panel, "modulate:a", 0.0, fade)
	if _strip is CanvasItem and is_instance_valid(_strip):
		tw.tween_property(_strip, "modulate:a", 0.0, fade)
	if _locked_overlay and is_instance_valid(_locked_overlay):
		_locked_overlay.visible = false
	await tw.finished
	for panel in _panels:
		if panel is Node and is_instance_valid(panel):
			(panel as Node).queue_free()
	_panels.clear()
	if _strip is Node and is_instance_valid(_strip):
		(_strip as Node).queue_free()
	_strip = null
	_build_final_form(true)
	_refresh_final_button()
	_launch_final_boss()

## Porte d'entree du mode : flush usine puis navigation SceneSwitcher standard
## (pattern HomeScreen._goto_from_home).
func _launch_final_boss() -> void:
	if IdleFactoryManager:
		IdleFactoryManager.flush_to_profile()
	var scene_path := str(_final_form_cfg().get("scene_path", "res://scenes/ultimate/FinalBossMode.tscn"))
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.call("goto_screen", scene_path)

func _tr_key(key: String, fallback: String) -> String:
	if LocaleManager and LocaleManager.has_method("translate"):
		var t := str(LocaleManager.translate(key))
		if t != key:
			return t
	return fallback

# =============================================================================
# PREVIEW EDITEUR (@tool) — dessine les triangles/zones dans la vue 2D pour
# permettre l'edition au pixel des reperes. Aucun effet au runtime.
# =============================================================================

## Couleurs des 4 generateurs dans l'ordre des coins (zelerium, neorite,
## ionium, tritanium) — miroir de data/idle_factory.json pour la preview.
const EDITOR_PREVIEW_COLORS := [
	Color("#F5C542"), Color("#7CD24A"), Color("#B76DF5"), Color("#F58A2A")
]

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw() # suit les deplacements de reperes en continu

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var font := ThemeDB.fallback_font
	for i in range(CORNER_MARKERS.size()):
		var m := get_node_or_null(NodePath(str(CORNER_MARKERS[i]["node"])))
		if not (m is Control):
			continue
		var r := Rect2((m as Control).position, (m as Control).size)
		var corner := int(CORNER_MARKERS[i]["corner"])
		var color: Color = EDITOR_PREVIEW_COLORS[i % EDITOR_PREVIEW_COLORS.size()]
		# Triangle rectangle : angle droit au coin ecran (meme geometrie que GeneratorPanel).
		var pts: PackedVector2Array
		match corner:
			1: pts = PackedVector2Array([r.position + Vector2(r.size.x, 0), r.position, r.position + r.size])
			2: pts = PackedVector2Array([r.position + Vector2(0, r.size.y), r.position, r.position + r.size])
			3: pts = PackedVector2Array([r.position + r.size, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y)])
			_: pts = PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y)])
		draw_colored_polygon(pts, Color(color, 0.25))
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, color, 2.0)
		draw_string(font, r.position + Vector2(8, 20), str(CORNER_MARKERS[i]["node"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	for zone_name in ["StripHost", "FinalHost", "LockedBanner"]:
		var z := get_node_or_null(NodePath(zone_name))
		if not (z is Control):
			continue
		var zr := Rect2((z as Control).position, (z as Control).size)
		draw_rect(zr, Color(0.4, 0.75, 1.0, 0.18), true)
		draw_rect(zr, Color(0.4, 0.75, 1.0, 0.9), false, 2.0)
		draw_string(font, zr.position + Vector2(8, 20), zone_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.9, 1.0))
