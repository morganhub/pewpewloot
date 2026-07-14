class_name WindFX
extends RefCounted
## Visuels de vent partagés (pong/breakout/snake) : flèche de télégraphe
## (grosse, pulse d'alpha, visible uniquement pendant le telegraph), traits
## filants de tailles variées (Line2D additifs) et petits débris losanges qui
## dérivent en oscillant perpendiculairement au vent. Les nodes sont créés en
## enfants du host (le manager) et wrappés dans la zone de jeu fournie.

var _host: Node2D = null
var _cfg: Dictionary = {}
var _streaks: Array = [] # { "node": Line2D, "pos": Vector2, "speed": float, "len": float }
var _debris: Array = [] # { "node": Polygon2D, "pos": Vector2, "speed": float, "amp": float, "phase": float }
var _arrow: Label = null
var _material: CanvasItemMaterial = null
var _rect: Rect2 = Rect2()


func _init(host: Node2D, cfg: Dictionary = {}) -> void:
	_host = host
	_cfg = cfg


func is_active() -> bool:
	return not _streaks.is_empty()


## Crée traits + débris + flèche (idempotent). rect = zone de jeu ;
## Rect2() vide = viewport entier du host.
func ensure_visuals(rect: Rect2 = Rect2()) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_rect = rect if rect.size != Vector2.ZERO else _host.get_viewport_rect()
	_ensure_arrow()
	if not _streaks.is_empty():
		return
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var streak_color := Color(str(_cfg.get("streak_color", "#9AD8FF66")))
	for i in range(clampi(int(_cfg.get("streak_count", 14)), 0, 40)):
		var line := Line2D.new()
		line.width = randf_range(1.5, 3.0)
		line.default_color = streak_color
		line.material = _material
		line.z_as_relative = false
		line.z_index = int(_cfg.get("z_index", 7))
		_host.add_child(line)
		_streaks.append({
			"node": line,
			"pos": Vector2(
				randf_range(_rect.position.x, _rect.end.x),
				randf_range(_rect.position.y + _rect.size.y * 0.05, _rect.end.y - _rect.size.y * 0.05)),
			"speed": randf_range(420.0, 900.0),
			"len": randf_range(40.0, 110.0)
		})
	var debris_color := Color(str(_cfg.get("debris_color", "#C8E8FFAA")))
	for i in range(clampi(int(_cfg.get("debris_count", 6)), 0, 20)):
		var dot := Polygon2D.new()
		var s: float = randf_range(3.0, 6.0)
		dot.polygon = PackedVector2Array([Vector2(-s, 0), Vector2(0, -s), Vector2(s, 0), Vector2(0, s)])
		dot.color = debris_color
		dot.z_as_relative = false
		dot.z_index = int(_cfg.get("z_index", 7))
		_host.add_child(dot)
		_debris.append({
			"node": dot,
			"pos": Vector2(
				randf_range(_rect.position.x, _rect.end.x),
				randf_range(_rect.position.y + _rect.size.y * 0.1, _rect.end.y - _rect.size.y * 0.1)),
			"speed": randf_range(140.0, 260.0),
			"amp": randf_range(10.0, 30.0),
			"phase": randf() * TAU
		})


func _ensure_arrow() -> void:
	if _arrow != null and is_instance_valid(_arrow):
		return
	var arrow := Label.new()
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", int(_cfg.get("arrow_font_size", 80)))
	arrow.add_theme_color_override("font_color", Color(str(_cfg.get("arrow_color", "#9AD8FF"))))
	arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	arrow.add_theme_constant_override("outline_size", 8)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.z_as_relative = false
	arrow.z_index = 55
	arrow.size = Vector2(_rect.size.x, 88.0)
	arrow.position = Vector2(_rect.position.x, _rect.position.y + _rect.size.y * float(_cfg.get("arrow_y_ratio", 0.24)))
	arrow.visible = false
	_host.add_child(arrow)
	_arrow = arrow


## Flèche de télégraphe : visible seulement pendant le telegraph, pointe dans
## dir (">>>"/"<<<" horizontal, "vvv"/"^^^" vertical), pulse d'alpha.
func update_arrow(visible_now: bool, dir: Vector2, pulse_phase: float) -> void:
	if _arrow == null or not is_instance_valid(_arrow):
		if not visible_now:
			return
		if _rect.size == Vector2.ZERO and _host != null and is_instance_valid(_host):
			_rect = _host.get_viewport_rect()
		_ensure_arrow()
		if _arrow == null:
			return
	if not visible_now:
		_arrow.visible = false
		return
	if absf(dir.x) >= absf(dir.y):
		_arrow.text = ">>>" if dir.x > 0.0 else "<<<"
	else:
		_arrow.text = "vvv" if dir.y > 0.0 else "^^^"
	_arrow.visible = true
	_arrow.modulate.a = 0.5 + 0.5 * absf(sin(pulse_phase * 9.0))


## Traits qui filent dans le sens du vent (wrap bord à bord dans la zone) +
## débris qui dérivent en oscillant (sinus perpendiculaire au vent).
func animate(delta: float, dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	for streak_v in _streaks:
		var streak: Dictionary = streak_v as Dictionary
		var len_px: float = float(streak.get("len", 60.0))
		var pos: Vector2 = (streak.get("pos", Vector2.ZERO) as Vector2) + dir * float(streak.get("speed", 500.0)) * delta
		pos = _wrap(pos, dir, len_px, true)
		streak["pos"] = pos
		var line: Line2D = streak.get("node") as Line2D
		if line and is_instance_valid(line):
			line.points = PackedVector2Array([pos - dir * len_px, pos])
	for debris_v in _debris:
		var debris: Dictionary = debris_v as Dictionary
		var pos: Vector2 = (debris.get("pos", Vector2.ZERO) as Vector2) + dir * float(debris.get("speed", 200.0)) * delta
		pos = _wrap(pos, dir, 12.0, false)
		debris["pos"] = pos
		debris["phase"] = float(debris.get("phase", 0.0)) + delta * 3.0
		var dot: Polygon2D = debris.get("node") as Polygon2D
		if dot and is_instance_valid(dot):
			dot.position = pos + perp * (sin(float(debris["phase"])) * float(debris.get("amp", 20.0)))


## Wrap bord à bord le long de l'axe du vent ; la coordonnée transverse est
## re-randomisée (traits) pour varier les trajectoires.
func _wrap(pos: Vector2, dir: Vector2, margin: float, rerand_across: bool) -> Vector2:
	var wrapped := false
	if dir.x > 0.0 and pos.x - margin > _rect.end.x:
		pos.x = _rect.position.x - margin
		wrapped = true
	elif dir.x < 0.0 and pos.x + margin < _rect.position.x:
		pos.x = _rect.end.x + margin
		wrapped = true
	if dir.y > 0.0 and pos.y - margin > _rect.end.y:
		pos.y = _rect.position.y - margin
		wrapped = true
	elif dir.y < 0.0 and pos.y + margin < _rect.position.y:
		pos.y = _rect.end.y + margin
		wrapped = true
	if wrapped and rerand_across:
		if absf(dir.x) >= absf(dir.y):
			pos.y = randf_range(_rect.position.y + _rect.size.y * 0.05, _rect.end.y - _rect.size.y * 0.05)
		else:
			pos.x = randf_range(_rect.position.x + _rect.size.x * 0.05, _rect.end.x - _rect.size.x * 0.05)
	return pos


func clear() -> void:
	for streak_v in _streaks:
		var node_v: Variant = (streak_v as Dictionary).get("node", null)
		if node_v is Node and is_instance_valid(node_v):
			(node_v as Node).queue_free()
	_streaks.clear()
	for debris_v in _debris:
		var node_v: Variant = (debris_v as Dictionary).get("node", null)
		if node_v is Node and is_instance_valid(node_v):
			(node_v as Node).queue_free()
	_debris.clear()
	if _arrow and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null
