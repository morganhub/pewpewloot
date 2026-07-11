extends Node2D

## MathGate — Paire de portes mathematiques (gauche/droite) qui descend l'ecran.
## Le joueur traverse l'une des deux portes pour appliquer son operation a la
## ressource HP. La porte soeur est neutralisee pour eviter une double collision.

signal gate_passed(operation: String, value: float)

var _door_speed: float = 170.0
var _band_height: float = 96.0
var _consumed: bool = false
var _viewport_size: Vector2 = Vector2(720, 1280)

var _left_op: String = "add"
var _left_value: float = 0.0
var _right_op: String = "multiply"
var _right_value: float = 1.0
var _color_bonus: Color = Color("#3FBF6A")
var _color_malus: Color = Color("#E8553B")

# Paire permutante (> 0) : les opérations échangent de côté toutes les
# _shift_interval secondes, avec un flash télégraphié avant le swap.
var _shift_interval: float = 0.0
var _shift_telegraph: float = 0.5
var _shift_timer: float = 0.0
# Réfs des visuels par côté ("left"/"right" -> { fill, border, label }) pour
# re-render au swap sans reconstruire les Area2D.
var _doors: Dictionary = {}

func setup(params: Dictionary) -> void:
	_viewport_size = get_viewport_rect().size
	_door_speed = maxf(10.0, float(params.get("door_speed", 170.0)))
	_band_height = maxf(24.0, float(params.get("band_height", 96.0)))

	var colors_v: Variant = params.get("colors", {})
	if colors_v is Dictionary:
		_color_bonus = _parse_color(str((colors_v as Dictionary).get("bonus", "#3FBF6A")), _color_bonus)
		_color_malus = _parse_color(str((colors_v as Dictionary).get("malus", "#E8553B")), _color_malus)

	var left_v: Dictionary = params.get("left", {}) if params.get("left") is Dictionary else {}
	var right_v: Dictionary = params.get("right", {}) if params.get("right") is Dictionary else {}
	_left_op = str(left_v.get("operation", "add"))
	_left_value = float(left_v.get("value", 0.0))
	_right_op = str(right_v.get("operation", "multiply"))
	_right_value = float(right_v.get("value", 1.0))

	_shift_interval = maxf(0.0, float(params.get("shift_interval_sec", 0.0)))
	_shift_telegraph = clampf(float(params.get("shift_telegraph_sec", 0.5)), 0.05, 2.0)
	_shift_timer = _shift_interval

	position = Vector2(0.0, float(params.get("spawn_y", -120.0)))
	_build_doors()

func _build_doors() -> void:
	var half_w: float = _viewport_size.x * 0.5
	_build_single_door("left", Vector2(half_w * 0.5, 0.0), half_w)
	_build_single_door("right", Vector2(half_w + half_w * 0.5, 0.0), half_w)
	_render_doors()

func _build_single_door(side: String, center: Vector2, door_width: float) -> void:
	var area := Area2D.new()
	area.name = "LeftDoor" if side == "left" else "RightDoor"
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
	label.add_theme_font_size_override("font_size", 52)
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

## (Re)peint les deux portes depuis l'état courant (setup ET après swap).
func _render_doors() -> void:
	_render_door("left", _left_op, _left_value)
	_render_door("right", _right_op, _right_value)

func _render_door(side: String, operation: String, value: float) -> void:
	var door_v: Variant = _doors.get(side, {})
	if not (door_v is Dictionary):
		return
	var door: Dictionary = door_v as Dictionary
	var fill_color: Color = _color_bonus if _is_operation_bonus(operation, value) else _color_malus
	var fill_v: Variant = door.get("fill", null)
	if fill_v is ColorRect and is_instance_valid(fill_v):
		(fill_v as ColorRect).color = Color(fill_color.r, fill_color.g, fill_color.b, 0.42)
	var border_v: Variant = door.get("border", null)
	if border_v is Line2D and is_instance_valid(border_v):
		(border_v as Line2D).default_color = fill_color
	var label_v: Variant = door.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).text = _format_operation_label(operation, value)

func _on_door_body_entered(body: Node2D, side: String) -> void:
	if _consumed:
		return
	if body == null or not body.is_in_group("player"):
		return
	_consumed = true
	if side == "left":
		gate_passed.emit(_left_op, _left_value)
	else:
		gate_passed.emit(_right_op, _right_value)
	_disable_doors()
	queue_free()

func _disable_doors() -> void:
	for child in get_children():
		if child is Area2D:
			(child as Area2D).set_deferred("monitoring", false)

func _process(delta: float) -> void:
	position.y += _door_speed * delta
	_update_shifting(delta)
	if position.y - _band_height * 0.5 > _viewport_size.y + 60.0:
		queue_free()

## Paire permutante : télégraphe (fills pulsés vers le blanc) puis échange des
## opérations gauche/droite + re-render. Punit la décision trop anticipée.
func _update_shifting(delta: float) -> void:
	if _shift_interval <= 0.0 or _consumed:
		return
	_shift_timer -= delta
	if _shift_timer <= _shift_telegraph:
		# Flash télégraphié : pulse rapide vers le blanc, bien visible.
		var pulse: float = 0.5 + 0.5 * sin(_shift_timer * TAU * 6.0)
		for side in ["left", "right"]:
			var door_v: Variant = _doors.get(side, {})
			if door_v is Dictionary:
				var fill_v: Variant = (door_v as Dictionary).get("fill", null)
				if fill_v is ColorRect and is_instance_valid(fill_v):
					(fill_v as ColorRect).modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.2, 2.2, 2.2), pulse)
	if _shift_timer > 0.0:
		return
	_shift_timer = _shift_interval
	var swap_op: String = _left_op
	var swap_value: float = _left_value
	_left_op = _right_op
	_left_value = _right_value
	_right_op = swap_op
	_right_value = swap_value
	for side in ["left", "right"]:
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
	var num: String = _format_number(value)
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

func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return str(snappedf(value, 0.01))

func _parse_color(color_value: String, fallback: Color) -> Color:
	if color_value != "" and Color.html_is_valid(color_value):
		return Color.html(color_value)
	return fallback
