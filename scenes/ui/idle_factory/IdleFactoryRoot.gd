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
		IdleFactoryManager.final_unlock_purchased.connect(func(_reward): _refresh_all())
	if ProfileManager and ProfileManager.has_signal("level_up"):
		ProfileManager.level_up.connect(func(_lvl, _pts): _apply_gating())

## Reevaluation du gating + refresh complet (retour sur la home apres un run).
func refresh_gating() -> void:
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
		_final_btn.text = _tr_key("idle_final_activated", "ACTIVÉ")
		_final_btn.disabled = true
		return
	var cost := float(final_cfg.get("cost", 1000000))
	var res_id := str(final_cfg.get("resource_id", "tritanium"))
	_final_btn.text = NumberFormat.compact(cost) + " " + _tr_key("idle_resource_" + res_id, res_id.to_upper())
	_final_btn.disabled = IdleFactoryManager.get_resource_amount(res_id) < cost

func _on_final_pressed() -> void:
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
	for panel in _panels:
		panel.call("refresh")
	_refresh_final_button()
	if _strip and is_instance_valid(_strip):
		_strip.call("refresh")

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
