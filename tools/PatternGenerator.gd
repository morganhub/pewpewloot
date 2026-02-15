@tool
extends Node
class_name PatternGenerator

const OUTPUT_DIR := "res://data/patterns/paths"
const REFERENCE_VIEWPORT_HEIGHT := 1280.0

func generate_all_curves() -> void:
	_ensure_output_dir()
	_save_curve("linear_cross_fast", _build_linear_cross_fast())
	_save_curve("sine_wave_vertical", _build_sine_wave_vertical())
	_save_curve("u_turn_retreat", _build_u_turn_retreat())
	_save_curve("staircase_descent", _build_staircase_descent())
	_save_curve("loop_de_loop_center", _build_loop_de_loop_center())
	_save_curve("double_loop_horizontal", _build_double_loop_horizontal())
	_save_curve("figure_eight_vertical", _build_figure_eight_vertical())
	_save_curve("impatient_circle", _build_impatient_circle())
	_save_curve("tear_drop_attack", _build_tear_drop_attack())
	_save_curve("boomerang_bottom", _build_boomerang_bottom())
	_save_curve("screen_hugger_left", _build_screen_hugger_left())
	_save_curve("cross_screen_dive", _build_cross_screen_dive())
	_save_curve("stop_and_go_zigzag", _build_stop_and_go_zigzag())
	_save_curve("heart_shape", _build_heart_shape())
	_save_curve("dna_helix", _build_dna_helix())
	_save_curve("butterfly_wings", _build_butterfly_wings())
	_save_curve("square_patrol", _build_square_patrol())
	_save_curve("spirograph_flower", _build_spirograph_flower())
	_save_curve("cobra_strike", _build_cobra_strike())
	_save_curve("bouncing_dvd", _build_bouncing_dvd())
	print("[PatternGenerator] Done.")

func _ensure_output_dir() -> void:
	var root := DirAccess.open("res://")
	if root == null:
		push_error("[PatternGenerator] Cannot open res://")
		return
	if not root.dir_exists("data/patterns/paths"):
		root.make_dir_recursive("data/patterns/paths")

func _save_curve(pattern_id: String, curve: Curve2D) -> void:
	if curve == null:
		push_warning("[PatternGenerator] curve is null for " + pattern_id)
		return
	var path := OUTPUT_DIR + "/" + pattern_id + ".tres"
	var err := ResourceSaver.save(curve, path)
	if err != OK:
		push_error("[PatternGenerator] Save failed for %s (%s)" % [path, err])
	else:
		print("[PatternGenerator] Saved: " + path)

func _curve_from_points(points: PackedVector2Array, smooth: float = 0.33, close_loop: bool = false) -> Curve2D:
	var curve := Curve2D.new()
	var count := points.size()
	if count < 2:
		return curve

	for i in range(count):
		var prev_i := (i - 1 + count) % count if close_loop else maxi(i - 1, 0)
		var next_i := (i + 1) % count if close_loop else mini(i + 1, count - 1)
		var prev := points[prev_i]
		var cur := points[i]
		var nxt := points[next_i]
		var tangent := (nxt - prev) * smooth

		var in_ctrl := -tangent if (close_loop or i > 0) else Vector2.ZERO
		var out_ctrl := tangent if (close_loop or i < count - 1) else Vector2.ZERO
		curve.add_point(cur, in_ctrl, out_ctrl)

	if close_loop:
		curve.add_point(points[0])

	return curve

func _build_linear_cross_fast() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(40, -80),
		Vector2(680, 1280)
	]), 0.0, false)

func _build_sine_wave_vertical() -> Curve2D:
	var curve := Curve2D.new()
	var amplitude := 120.0
	var frequency := 2.2
	var distance := _resolve_distance(1.8)
	var steps := 96
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := sin(t * TAU * frequency) * amplitude
		var y := t * distance
		curve.add_point(Vector2(x, y))
	return curve

func _build_u_turn_retreat() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(360, -120),
		Vector2(360, 260),
		Vector2(260, 500),
		Vector2(500, 500),
		Vector2(500, 120),
		Vector2(630, -120)
	]), 0.32, false)

func _build_staircase_descent() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(120, -80),
		Vector2(120, 150),
		Vector2(260, 150),
		Vector2(260, 330),
		Vector2(400, 330),
		Vector2(400, 510),
		Vector2(560, 510),
		Vector2(560, 700),
		Vector2(680, 700),
		Vector2(680, 980)
	]), 0.05, false)

func _build_loop_de_loop_center() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(360, -80),
		Vector2(360, 240),
		Vector2(500, 340),
		Vector2(360, 470),
		Vector2(220, 340),
		Vector2(360, 240),
		Vector2(360, 840)
	]), 0.42, false)

func _build_double_loop_horizontal() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(80, 180),
		Vector2(200, 70),
		Vector2(320, 180),
		Vector2(200, 300),
		Vector2(80, 180),
		Vector2(400, 180),
		Vector2(520, 70),
		Vector2(640, 180),
		Vector2(520, 300),
		Vector2(400, 180),
		Vector2(400, 980)
	]), 0.36, false)

func _build_figure_eight_vertical() -> Curve2D:
	var curve := Curve2D.new()
	var radius := 90.0
	var vertical_scale := 1.5
	var drift_y := 0.0
	var steps := 96
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := t * TAU
		var x := sin(angle) * cos(angle) * radius * 1.2
		var y := sin(angle) * radius * vertical_scale + drift_y * t
		curve.add_point(Vector2(x, y))
	return curve

func _build_impatient_circle() -> Curve2D:
	var curve := Curve2D.new()
	var radius := 70.0
	var turns := 1.6
	var steps := 96
	var center := Vector2(0.0, 140.0)
	var charge_distance := 900.0
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := t * TAU * turns
		var orbit_point := center + Vector2(cos(angle), sin(angle)) * radius
		curve.add_point(orbit_point)
	var last_y := center.y + radius
	curve.add_point(Vector2(0.0, last_y + charge_distance), Vector2.ZERO, Vector2.ZERO)
	return curve

func _build_tear_drop_attack() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(360, -90),
		Vector2(520, 200),
		Vector2(600, 520),
		Vector2(360, 940),
		Vector2(120, 520),
		Vector2(200, 200),
		Vector2(360, -90),
		Vector2(360, 1180)
	]), 0.34, false)

func _build_boomerang_bottom() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(120, 80),
		Vector2(280, 520),
		Vector2(520, 960),
		Vector2(240, 760),
		Vector2(80, 380),
		Vector2(200, 1280)
	]), 0.30, false)

func _build_screen_hugger_left() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(40, -100),
		Vector2(30, 180),
		Vector2(50, 360),
		Vector2(35, 580),
		Vector2(45, 780),
		Vector2(55, 1020),
		Vector2(70, 1280)
	]), 0.18, false)

func _build_cross_screen_dive() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(680, -120),
		Vector2(560, 120),
		Vector2(420, 420),
		Vector2(200, 740),
		Vector2(40, 1280)
	]), 0.40, false)

func _build_stop_and_go_zigzag() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(120, -80),
		Vector2(520, 120),
		Vector2(520, 240),
		Vector2(170, 420),
		Vector2(170, 560),
		Vector2(560, 760),
		Vector2(560, 900),
		Vector2(120, 1140)
	]), 0.06, false)

func _build_heart_shape() -> Curve2D:
	var curve := Curve2D.new()
	var scale := 8.5
	var center := Vector2(0.0, 200.0)
	var steps := 140
	for i in range(steps + 1):
		var t := (float(i) / float(steps)) * TAU
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		curve.add_point(center + Vector2(x * scale, -y * scale))
	return curve

func _build_dna_helix() -> Curve2D:
	var curve := Curve2D.new()
	var amplitude_primary := 90.0
	var amplitude_secondary := 35.0
	var tightness := 5.5
	var distance := _resolve_distance(2.0)
	var steps := 120
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := t * TAU * tightness
		var x := sin(angle) * amplitude_primary + sin(angle * 2.0 + PI * 0.5) * amplitude_secondary
		var y := t * distance
		curve.add_point(Vector2(x, y))
	return curve

func _build_butterfly_wings() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(360, 140),
		Vector2(190, 40),
		Vector2(80, 220),
		Vector2(210, 380),
		Vector2(360, 280),
		Vector2(510, 380),
		Vector2(640, 220),
		Vector2(530, 40),
		Vector2(360, 140),
		Vector2(360, 980)
	]), 0.36, false)

func _build_square_patrol() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(180, 180),
		Vector2(540, 180),
		Vector2(540, 540),
		Vector2(180, 540),
		Vector2(180, 180),
		Vector2(180, 980)
	]), 0.04, false)

func _build_spirograph_flower() -> Curve2D:
	var curve := Curve2D.new()
	var r_big := 90.0
	var r_small := 30.0
	var d := 55.0
	var turns := 6.0
	var scale := 1.0
	var center := Vector2(0.0, 260.0)
	var steps := 220
	for i in range(steps + 1):
		var t := (float(i) / float(steps)) * TAU * turns
		var k := (r_big - r_small) / r_small
		var x := (r_big - r_small) * cos(t) + d * cos(k * t)
		var y := (r_big - r_small) * sin(t) - d * sin(k * t)
		curve.add_point(center + Vector2(x, y) * scale)
	return curve

func _build_cobra_strike() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(360, -120),
		Vector2(300, 40),
		Vector2(430, 180),
		Vector2(280, 320),
		Vector2(430, 440),
		Vector2(360, 520),
		Vector2(360, 1280)
	]), 0.35, false)

func _build_bouncing_dvd() -> Curve2D:
	return _curve_from_points(PackedVector2Array([
		Vector2(120, 120),
		Vector2(680, 420),
		Vector2(120, 760),
		Vector2(680, 1080),
		Vector2(260, 1280)
	]), 0.02, false)

func _resolve_distance(multiplier: float) -> float:
	return maxf(350.0, REFERENCE_VIEWPORT_HEIGHT * multiplier)
