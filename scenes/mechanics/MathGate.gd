extends Node2D

## MathGate — Rangee de portes mathematiques (2 ou 3 cotes) qui descend l'ecran.
## Le joueur traverse l'une des portes pour appliquer son operation a la
## ressource HP. Les portes soeurs sont neutralisees (pas de double collision).
##
## Options (dict de setup, toutes composables) :
## - center:{} present -> rangee a 3 portes (largeur = viewport/3).
## - door.golden -> porte doree (couleur colors.golden, rendu premium).
## - shift_interval_sec > 0 -> paire permutante : les operations TOURNENT d'un
##   cote a intervalle (flash telegraphie).
## - slide_amplitude_px > 0 -> toute la rangee glisse lateralement (sinus) en
##   descendant : viser une porte devient du timing.
## - auction -> enchere : les valeurs add/subtract decroissent pendant la
##   descente (x auction_start_mult en haut -> x auction_end_mult en bas) ;
##   passer tot paie plus (et punit plus). gate_passed emet la valeur EFFECTIVE.
## - equation -> les valeurs add/subtract s'affichent en somme (« +12+7 »).
## Les nombres sont formates en compact K/M (NumberFormat).

signal gate_passed(operation: String, value: float)

const NumberFormat := preload("res://scenes/mechanics/number_format.gd")

var _door_speed: float = 170.0
var _band_height: float = 96.0
var _consumed: bool = false
var _viewport_size: Vector2 = Vector2(720, 1280)

# Etat par cote ("left"/"center"/"right" — center optionnel).
var _sides: Array = []
var _ops: Dictionary = {}
var _values: Dictionary = {}
var _golden: Dictionary = {}
var _equations: Dictionary = {} # side -> texte pre-calcule ("12+7") ou ""
var _color_bonus: Color = Color("#3FBF6A")
var _color_malus: Color = Color("#E8553B")
var _color_golden: Color = Color("#FFD866")

# Paire permutante (> 0) : les opérations tournent d'un côté toutes les
# _shift_interval secondes, avec un flash télégraphié avant le swap.
var _shift_interval: float = 0.0
var _shift_telegraph: float = 0.5
var _shift_timer: float = 0.0
# Coulissante : offset X sinusoïdal appliqué au node entier.
var _slide_amp: float = 0.0
var _slide_hz: float = 0.25
var _slide_phase: float = 0.0
# Enchère : multiplicateur des valeurs add/subtract selon la descente.
var _auction: bool = false
var _auction_start: float = 1.5
var _auction_end: float = 0.6
var _spawn_y: float = -120.0
var _auction_rerender: float = 0.0
# Réfs des visuels par côté (side -> { fill, border, label }) pour re-render
# au swap/enchère sans reconstruire les Area2D.
var _doors: Dictionary = {}

func setup(params: Dictionary) -> void:
	_viewport_size = get_viewport_rect().size
	_door_speed = maxf(10.0, float(params.get("door_speed", 170.0)))
	_band_height = maxf(24.0, float(params.get("band_height", 96.0)))

	var colors_v: Variant = params.get("colors", {})
	if colors_v is Dictionary:
		_color_bonus = _parse_color(str((colors_v as Dictionary).get("bonus", "#3FBF6A")), _color_bonus)
		_color_malus = _parse_color(str((colors_v as Dictionary).get("malus", "#E8553B")), _color_malus)
		_color_golden = _parse_color(str((colors_v as Dictionary).get("golden", "#FFD866")), _color_golden)

	_sides = ["left", "right"]
	var center_v: Variant = params.get("center", {})
	if center_v is Dictionary and not (center_v as Dictionary).is_empty():
		_sides = ["left", "center", "right"]
	var equation_gate: bool = bool(params.get("equation", false))
	for side in _sides:
		var door_v: Dictionary = params.get(side, {}) if params.get(side) is Dictionary else {}
		_ops[side] = str(door_v.get("operation", "add"))
		_values[side] = float(door_v.get("value", 0.0))
		_golden[side] = bool(door_v.get("golden", false))
		_equations[side] = _make_equation_text(str(_ops[side]), float(_values[side])) if equation_gate else ""

	_shift_interval = maxf(0.0, float(params.get("shift_interval_sec", 0.0)))
	_shift_telegraph = clampf(float(params.get("shift_telegraph_sec", 0.5)), 0.05, 2.0)
	_shift_timer = _shift_interval
	_slide_amp = maxf(0.0, float(params.get("slide_amplitude_px", 0.0)))
	_slide_hz = maxf(0.01, float(params.get("slide_speed_hz", 0.25)))
	_slide_phase = randf() * TAU
	_auction = bool(params.get("auction", false))
	_auction_start = maxf(0.1, float(params.get("auction_start_mult", 1.5)))
	_auction_end = clampf(float(params.get("auction_end_mult", 0.6)), 0.05, _auction_start)

	_spawn_y = float(params.get("spawn_y", -120.0))
	position = Vector2(0.0, _spawn_y)
	_build_doors()

func _build_doors() -> void:
	var count: int = _sides.size()
	var door_width: float = _viewport_size.x / float(count)
	for i in range(count):
		_build_single_door(str(_sides[i]), Vector2(door_width * (float(i) + 0.5), 0.0), door_width)
	_render_doors()

func _build_single_door(side: String, center: Vector2, door_width: float) -> void:
	var area := Area2D.new()
	area.name = side.capitalize() + "Door"
	area.collision_layer = 0
	area.collision_mask = 2 # Player physics body layer
	area.monitoring = true
	area.monitorable = false
	area.position = center
	add_child(area)

	var bg := ColorRect.new()
	bg.name = "Fill"
	bg.size = Vector2(door_width, _band_height)
	bg.position = Vector2(-door_width * 0.5, -_band_height * 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(bg)

	var border := Line2D.new()
	border.width = 4.0
	border.points = PackedVector2Array([
		Vector2(-door_width * 0.5, -_band_height * 0.5),
		Vector2(door_width * 0.5, -_band_height * 0.5),
		Vector2(door_width * 0.5, _band_height * 0.5),
		Vector2(-door_width * 0.5, _band_height * 0.5),
		Vector2(-door_width * 0.5, -_band_height * 0.5)
	])
	area.add_child(border)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(door_width, _band_height)
	label.position = Vector2(-door_width * 0.5, -_band_height * 0.5)
	# 3 portes = cases plus etroites : police reduite pour tenir.
	label.add_theme_font_size_override("font_size", 52 if _sides.size() <= 2 else 42)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(label)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(door_width, _band_height)
	col.shape = shape
	area.add_child(col)

	# Bind par CÔTÉ (pas par valeur) : les paires permutantes échangent leurs
	# opérations après construction — on lit l'op/value courants au passage.
	area.body_entered.connect(_on_door_body_entered.bind(side))
	_doors[side] = { "fill": bg, "border": border, "label": label }

## (Re)peint toutes les portes depuis l'état courant (setup, swap, enchère).
func _render_doors() -> void:
	for side in _sides:
		_render_door(str(side), str(_ops[side]), _effective_value(str(side)))

func _render_door(side: String, operation: String, value: float) -> void:
	var door_v: Variant = _doors.get(side, {})
	if not (door_v is Dictionary):
		return
	var door: Dictionary = door_v as Dictionary
	var fill_color: Color = _color_bonus if _is_operation_bonus(operation, value) else _color_malus
	if bool(_golden.get(side, false)):
		fill_color = _color_golden
	var fill_v: Variant = door.get("fill", null)
	if fill_v is ColorRect and is_instance_valid(fill_v):
		(fill_v as ColorRect).color = Color(fill_color.r, fill_color.g, fill_color.b, 0.42)
	var border_v: Variant = door.get("border", null)
	if border_v is Line2D and is_instance_valid(border_v):
		(border_v as Line2D).default_color = fill_color
	var label_v: Variant = door.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		var equation_text: String = str(_equations.get(side, ""))
		if equation_text != "" and not _auction:
			(label_v as Label).text = equation_text
		else:
			(label_v as Label).text = _format_operation_label(operation, value)

## Valeur EFFECTIVE d'un côté : l'enchère fait fondre les valeurs add/subtract
## pendant la descente (× start en haut -> × end au niveau du bas jouable).
func _effective_value(side: String) -> float:
	var base: float = float(_values.get(side, 0.0))
	if not _auction:
		return base
	var op: String = str(_ops.get(side, ""))
	if op != "add" and op != "subtract":
		return base
	var end_y: float = _viewport_size.y * 0.85
	var progress: float = clampf((position.y - _spawn_y) / maxf(1.0, end_y - _spawn_y), 0.0, 1.0)
	var mult: float = lerpf(_auction_start, _auction_end, progress)
	return maxf(1.0, round(base * mult))

## Équation d'affichage (« 12+7 » au lieu de « 19 ») pour add/subtract entiers
## suffisamment grands ; split aléatoire stable (calculé une fois au setup).
func _make_equation_text(operation: String, value: float) -> String:
	if operation != "add" and operation != "subtract":
		return ""
	if not is_equal_approx(value, round(value)) or value < 4.0:
		return ""
	var total: int = int(round(value))
	var a: int = clampi(int(round(float(total) * randf_range(0.3, 0.7))), 1, total - 1)
	var b: int = total - a
	if operation == "add":
		return "+%d+%d" % [a, b]
	return "-%d-%d" % [a, b]

func _on_door_body_entered(body: Node2D, side: String) -> void:
	if _consumed:
		return
	if body == null or not body.is_in_group("player"):
		return
	_consumed = true
	gate_passed.emit(str(_ops.get(side, "add")), _effective_value(side))
	_disable_doors()
	queue_free()

func _disable_doors() -> void:
	for child in get_children():
		if child is Area2D:
			(child as Area2D).set_deferred("monitoring", false)

func _process(delta: float) -> void:
	position.y += _door_speed * delta
	# Coulissante : toute la rangée glisse latéralement (les bords sortent de
	# l'écran — viser devient du timing).
	if _slide_amp > 0.0:
		_slide_phase += delta * TAU * _slide_hz
		position.x = sin(_slide_phase) * _slide_amp
	_update_shifting(delta)
	# Enchère : re-render périodique des valeurs qui fondent.
	if _auction and not _consumed:
		_auction_rerender -= delta
		if _auction_rerender <= 0.0:
			_auction_rerender = 0.15
			_render_doors()
	if position.y - _band_height * 0.5 > _viewport_size.y + 60.0:
		queue_free()

## Rangée permutante : télégraphe (fills pulsés vers le blanc) puis ROTATION
## des opérations d'un côté + re-render. Punit la décision trop anticipée.
func _update_shifting(delta: float) -> void:
	if _shift_interval <= 0.0 or _consumed:
		return
	_shift_timer -= delta
	if _shift_timer <= _shift_telegraph:
		# Flash télégraphié : pulse rapide vers le blanc, bien visible.
		var pulse: float = 0.5 + 0.5 * sin(_shift_timer * TAU * 6.0)
		for side in _sides:
			var door_v: Variant = _doors.get(side, {})
			if door_v is Dictionary:
				var fill_v: Variant = (door_v as Dictionary).get("fill", null)
				if fill_v is ColorRect and is_instance_valid(fill_v):
					(fill_v as ColorRect).modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.2, 2.2, 2.2), pulse)
	if _shift_timer > 0.0:
		return
	_shift_timer = _shift_interval
	# Rotation d'un cran (2 côtés = swap classique, 3 côtés = carrousel).
	var first_side: String = str(_sides[0])
	var carry_op: String = str(_ops[first_side])
	var carry_value: float = float(_values[first_side])
	var carry_golden: bool = bool(_golden[first_side])
	var carry_equation: String = str(_equations.get(first_side, ""))
	for i in range(_sides.size() - 1):
		var to_side: String = str(_sides[i])
		var from_side: String = str(_sides[i + 1])
		_ops[to_side] = _ops[from_side]
		_values[to_side] = _values[from_side]
		_golden[to_side] = _golden[from_side]
		_equations[to_side] = _equations.get(from_side, "")
	var last_side: String = str(_sides[_sides.size() - 1])
	_ops[last_side] = carry_op
	_values[last_side] = carry_value
	_golden[last_side] = carry_golden
	_equations[last_side] = carry_equation
	for side in _sides:
		var door_v: Variant = _doors.get(side, {})
		if door_v is Dictionary:
			var fill_v: Variant = (door_v as Dictionary).get("fill", null)
			if fill_v is ColorRect and is_instance_valid(fill_v):
				(fill_v as ColorRect).modulate = Color.WHITE
	_render_doors()

func _is_operation_bonus(operation: String, value: float) -> bool:
	match operation:
		"add":
			return value >= 0.0
		"subtract":
			return false
		"multiply":
			return value >= 1.0
		"divide":
			return value <= 1.0
		_:
			return true

func _format_operation_label(operation: String, value: float) -> String:
	var num: String = NumberFormat.compact(value)
	match operation:
		"add":
			return "+" + num
		"subtract":
			return "-" + num
		"multiply":
			return "x" + num
		"divide":
			return "/" + num
		_:
			return num

func _parse_color(color_value: String, fallback: Color) -> Color:
	if color_value != "" and Color.html_is_valid(color_value):
		return Color.html(color_value)
	return fallback
