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

	position = Vector2(0.0, float(params.get("spawn_y", -120.0)))
	_build_doors()

func _build_doors() -> void:
	var half_w: float = _viewport_size.x * 0.5
	_build_single_door("LeftDoor", Vector2(half_w * 0.5, 0.0), half_w, _left_op, _left_value)
	_build_single_door("RightDoor", Vector2(half_w + half_w * 0.5, 0.0), half_w, _right_op, _right_value)

func _build_single_door(door_name: String, center: Vector2, door_width: float, operation: String, value: float) -> void:
	var is_bonus: bool = _is_operation_bonus(operation, value)
	var fill_color: Color = _color_bonus if is_bonus else _color_malus

	var area := Area2D.new()
	area.name = door_name
	area.collision_layer = 0
	area.collision_mask = 2 # Player physics body layer
	area.monitoring = true
	area.monitorable = false
	area.position = center
	add_child(area)

	var bg := ColorRect.new()
	bg.name = "Fill"
	bg.color = Color(fill_color.r, fill_color.g, fill_color.b, 0.42)
	bg.size = Vector2(door_width, _band_height)
	bg.position = Vector2(-door_width * 0.5, -_band_height * 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(bg)

	var border := Line2D.new()
	border.width = 4.0
	border.default_color = fill_color
	border.points = PackedVector2Array([
		Vector2(-door_width * 0.5, -_band_height * 0.5),
		Vector2(door_width * 0.5, -_band_height * 0.5),
		Vector2(door_width * 0.5, _band_height * 0.5),
		Vector2(-door_width * 0.5, _band_height * 0.5),
		Vector2(-door_width * 0.5, -_band_height * 0.5)
	])
	area.add_child(border)

	var label := Label.new()
	label.text = _format_operation_label(operation, value)
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

	area.body_entered.connect(_on_door_body_entered.bind(operation, value))

func _on_door_body_entered(body: Node2D, operation: String, value: float) -> void:
	if _consumed:
		return
	if body == null or not body.is_in_group("player"):
		return
	_consumed = true
	gate_passed.emit(operation, value)
	_disable_doors()
	queue_free()

func _disable_doors() -> void:
	for child in get_children():
		if child is Area2D:
			(child as Area2D).set_deferred("monitoring", false)

func _process(delta: float) -> void:
	position.y += _door_speed * delta
	if position.y - _band_height * 0.5 > _viewport_size.y + 60.0:
		queue_free()

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
