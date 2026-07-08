extends Node2D

## BreakoutManager — Orchestre une vague "breakout" :
## le vaisseau joueur devient une raquette en bas (mode pong reutilise) et
## renvoie une balle vers un mur de briques en haut de l'ecran. Brique
## detruite = chance de cristal ; mur nettoye avant le timer = pluie de
## cristaux + fin anticipee ; balle perdue en bas = degats en % des HP max
## puis resserve. Duree limitee, compte a rebours seul au HUD.
## Collisions balle/raquette/briques en manuel (cercle vs AABB, normales de
## coin incluses) — pas de physics engine, comme le pong.

signal finished

enum State { INTRO, SERVE, PLAY, DONE }

# Anti-tunneling: cap the ball integration step on long frames.
const MAX_BALL_STEP_SEC: float = 1.0 / 30.0
const BRICK_SHADER: Shader = preload("res://scenes/mechanics/brick_rounded.gdshader")

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 45.0
var _elapsed: float = 0.0

# Ball (manual movement, no physics engine)
var _ball: Node2D = null
var _ball_velocity: Vector2 = Vector2.ZERO
var _ball_radius: float = 14.0
var _ball_speed: float = 460.0
var _ball_base_speed: float = 460.0
var _ball_speed_max: float = 900.0
var _ball_speed_increase_hit: float = 12.0
var _ball_speed_increase_brick: float = 4.0
var _max_bounce_angle_deg: float = 55.0
var _wall_margin: float = 10.0
var _serve_delay: float = 0.8
var _serve_angle_max_deg: float = 35.0

# Player paddle: manual AABB around _player.global_position (pong mode).
var _player_half_extents: Vector2 = Vector2(96.0, 16.0)

# Brick wall. Entries: { "node": Node2D, "rect": Rect2, "hp": int,
# "max_hp": int, "tint": Color }
var _bricks: Array = []
var _brick_size: Vector2 = Vector2(96.0, 40.0)
var _grid_bottom_y: float = 0.0
var _brick_material: ShaderMaterial = null

var _damage_percent: float = 0.15
var _crystal_brick_chance: float = 0.18
var _crystals_on_clear: int = 6
var _brick_flash_sec: float = 0.1

var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("breakout") if DataManager else {}

	# Per-wave overrides (world_x.json) take precedence over global defaults.
	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 45.0))))
	_ball_radius = maxf(4.0, float(_cfg.get("ball_radius_px", 14.0)))
	_ball_base_speed = maxf(60.0, float(_config.get("ball_speed_px_sec", _cfg.get("ball_speed_px_sec_default", 460.0))))
	_ball_speed = _ball_base_speed
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	_ball_speed_increase_hit = maxf(0.0, float(_cfg.get("ball_speed_increase_per_hit", 12.0)))
	_ball_speed_increase_brick = maxf(0.0, float(_cfg.get("ball_speed_increase_per_brick", 4.0)))
	_max_bounce_angle_deg = clampf(float(_cfg.get("ball_max_bounce_angle_deg", 55.0)), 10.0, 80.0)
	_wall_margin = maxf(0.0, float(_cfg.get("wall_margin_px", 10.0)))
	_serve_delay = maxf(0.1, float(_cfg.get("serve_delay_sec", 0.8)))
	_serve_angle_max_deg = clampf(float(_cfg.get("serve_angle_max_deg", 35.0)), 0.0, 60.0)

	_player_half_extents = Vector2(
		maxf(16.0, float(_cfg.get("player_paddle_half_width_px", 96.0))),
		maxf(6.0, float(_cfg.get("player_paddle_half_height_px", 16.0)))
	)

	_damage_percent = clampf(float(_config.get("damage_percent_per_ball_lost", _cfg.get("damage_percent_per_ball_lost", 0.15))), 0.0, 1.0)
	_crystal_brick_chance = clampf(float(_config.get("crystal_brick_chance", _cfg.get("crystal_brick_chance", 0.18))), 0.0, 1.0)
	_crystals_on_clear = maxi(0, int(_config.get("crystals_on_clear", _cfg.get("crystals_on_clear", 6))))
	_brick_flash_sec = maxf(0.02, float(_cfg.get("brick_hp_flash_sec", 0.1)))

	_begin_player_mode()
	_build_brick_grid()
	_spawn_ball()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.6)))
	set_process(true)

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — balle et mur préservés (aucun re-service). rows/cols
## scalés s'appliquent au prochain mur (reconstruit au clear, itération naturelle).
func update_free_mode_config(cfg: Dictionary) -> void:
	_ball_base_speed = maxf(60.0, float(cfg.get("ball_speed_px_sec", _ball_base_speed)))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	if _ball_speed < _ball_base_speed:
		_ball_speed = _ball_base_speed
		if _ball_velocity != Vector2.ZERO:
			_ball_velocity = _ball_velocity.normalized() * _ball_speed
	_damage_percent = clampf(float(cfg.get("damage_percent_per_ball_lost", _damage_percent)), 0.0, 1.0)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_pong"):
		# Reuses the pong paddle mode: Y locked at the paddle line, visual squash.
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_pong", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_pong"):
		_player.call("end_pong")

# =============================================================================
# BRICK WALL
# =============================================================================

func _build_brick_grid() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, float(_cfg.get("grid_side_margin_px", 26.0)))
	var spacing: float = clampf(float(_cfg.get("brick_spacing_px", 5.0)), 0.0, 24.0)
	var rows: int = clampi(int(_config.get("rows", _cfg.get("rows_default", 5))), 1, 10)
	var cols: int = clampi(int(_config.get("cols", _cfg.get("cols_default", 6))), 2, 12)
	var brick_h: float = maxf(12.0, float(_cfg.get("brick_height_px", 42.0)))
	var usable_w: float = viewport_size.x - side_margin * 2.0
	var brick_w: float = maxf(16.0, (usable_w - float(cols - 1) * spacing) / float(cols))
	_brick_size = Vector2(brick_w, brick_h)
	var top_y: float = viewport_size.y * clampf(float(_cfg.get("grid_top_ratio", 0.12)), 0.05, 0.5)

	# One shared material for the whole wall: same size for every brick.
	_brick_material = ShaderMaterial.new()
	_brick_material.shader = BRICK_SHADER
	_brick_material.set_shader_parameter("rect_size", _brick_size)
	_brick_material.set_shader_parameter("radius_px", clampf(float(_cfg.get("brick_corner_radius_px", 7.0)), 0.0, minf(brick_w, brick_h) * 0.5))

	var grid_root := Node2D.new()
	grid_root.name = "BrickGrid"
	grid_root.z_as_relative = false
	grid_root.z_index = 10
	add_child(grid_root)

	var row_hp: Array = _resolve_row_hp(rows)
	var assets: Array = _resolve_brick_assets()
	var tints_v: Variant = _cfg.get("row_tints", [])
	var tints: Array = (tints_v as Array) if tints_v is Array else []

	for r in range(rows):
		var tex: Texture2D = _resolve_brick_texture(assets, r)
		var tint: Color = Color.WHITE
		if not tints.is_empty():
			tint = Color(str(tints[r % tints.size()]))
		var hp: int = maxi(1, int(row_hp[r]))
		for c in range(cols):
			var center := Vector2(
				side_margin + (brick_w + spacing) * float(c) + brick_w * 0.5,
				top_y + (brick_h + spacing) * float(r) + brick_h * 0.5
			)
			var brick_node := Node2D.new()
			brick_node.position = center
			var visual: Node2D = _make_brick_visual(tex, tint)
			brick_node.add_child(visual)
			grid_root.add_child(brick_node)
			var entry: Dictionary = {
				"node": brick_node,
				"rect": Rect2(center - _brick_size * 0.5, _brick_size),
				"hp": hp,
				"max_hp": hp,
				"tint": tint
			}
			_bricks.append(entry)
			_refresh_brick_tint(entry)
	_grid_bottom_y = top_y + float(rows) * (brick_h + spacing)

func _resolve_row_hp(rows: int) -> Array:
	var src_v: Variant = _config.get("row_hp", _cfg.get("row_hp_default", [2, 2, 1, 1, 1]))
	var src: Array = (src_v as Array) if src_v is Array else [1]
	if src.is_empty():
		src = [1]
	var result: Array = []
	for r in range(rows):
		result.append(maxi(1, int(src[mini(r, src.size() - 1)])))
	return result

## Asset priority: per-wave "brick_assets" override > wave-type defaults.
func _resolve_brick_assets() -> Array:
	var wave_assets_v: Variant = _config.get("brick_assets", [])
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		return wave_assets_v as Array
	var cfg_assets_v: Variant = _cfg.get("brick_assets", [])
	if cfg_assets_v is Array:
		return cfg_assets_v as Array
	return []

## One texture per row (the list cycles), for the classic tiered-wall look.
func _resolve_brick_texture(assets: Array, row: int) -> Texture2D:
	if assets.is_empty():
		return null
	return _texture_from_path(str(assets[row % assets.size()]))

func _texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Texture2D:
		return res as Texture2D
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			return frames.get_frame_texture(names[0], 0)
	return null

## "Cover" fill: the texture is cropped to the brick aspect ratio (centered)
## then scaled to the exact brick size — never stretched. The shared shader
## material rounds the corners.
func _make_brick_visual(tex: Texture2D, tint: Color) -> Node2D:
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var brick_aspect: float = _brick_size.x / _brick_size.y
			var tex_aspect: float = tex_size.x / tex_size.y
			var region_size: Vector2
			if tex_aspect > brick_aspect:
				region_size = Vector2(tex_size.y * brick_aspect, tex_size.y)
			else:
				region_size = Vector2(tex_size.x, tex_size.x / brick_aspect)
			sprite.region_enabled = true
			sprite.region_rect = Rect2((tex_size - region_size) * 0.5, region_size)
			sprite.scale = _brick_size / region_size
		sprite.material = _brick_material
		return sprite
	# Fallback: flat rounded rectangle (no asset configured).
	return _make_brick_polygon(tint)

func _make_brick_polygon(tint: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var half: Vector2 = _brick_size * 0.5
	var radius: float = clampf(float(_cfg.get("brick_corner_radius_px", 7.0)), 0.0, minf(half.x, half.y))
	var points := PackedVector2Array()
	var corners: Array = [
		[Vector2(half.x - radius, -half.y + radius), -PI * 0.5],
		[Vector2(half.x - radius, half.y - radius), 0.0],
		[Vector2(-half.x + radius, half.y - radius), PI * 0.5],
		[Vector2(-half.x + radius, -half.y + radius), PI]
	]
	var segments: int = 5
	for corner in corners:
		var corner_center: Vector2 = corner[0]
		var start_angle: float = corner[1]
		for i in range(segments + 1):
			var a: float = start_angle + (PI * 0.5) * float(i) / float(segments)
			points.append(corner_center + Vector2(cos(a), sin(a)) * radius)
	poly.polygon = points
	poly.color = tint if tint != Color.WHITE else Color("#8A93A6")
	return poly

func _refresh_brick_tint(brick: Dictionary) -> void:
	var node_v: Variant = brick.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var hp: int = int(brick.get("hp", 1))
	var max_hp: int = maxi(1, int(brick.get("max_hp", 1)))
	var tint: Color = brick.get("tint", Color.WHITE)
	# Damaged bricks darken progressively (tiering stays readable).
	var brightness: float = lerpf(0.55, 1.0, float(hp) / float(max_hp))
	(node_v as Node2D).modulate = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)

# =============================================================================
# BALL
# =============================================================================

func _spawn_ball() -> void:
	_ball = Node2D.new()
	_ball.name = "BreakoutBall"
	_ball.z_as_relative = false
	_ball.z_index = 11
	add_child(_ball)
	var ball_asset: String = str(_config.get("ball_asset", _cfg.get("ball_asset", "")))
	var visual: Node2D = _build_ball_sprite(ball_asset)
	if visual == null:
		visual = _build_ball_circle()
	_ball.add_child(visual)
	_ball.visible = false

func _build_ball_sprite(asset_path: String) -> Node2D:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null
	var tex: Texture2D = _texture_from_path(asset_path)
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sprite.scale = (Vector2.ONE * _ball_radius * 2.0) / tex_size
	return sprite

func _build_ball_circle() -> Node2D:
	var circle := Polygon2D.new()
	var points := PackedVector2Array()
	var segments: int = 24
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * _ball_radius)
	circle.polygon = points
	circle.color = Color(str(_cfg.get("ball_color", "#8FD3FF")))
	return circle

# =============================================================================
# MATCH LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# A dead player means the game-over flow took over: freeze the wave
	# without emitting finished.
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_reset_ball()
		State.SERVE:
			_stick_ball_to_paddle()
			_state_timer -= delta
			if _state_timer <= 0.0:
				_serve()
		State.PLAY:
			_update_ball(delta)
	if _elapsed >= _duration:
		_finish()

## Ball lost or wave start: the ball sticks to the paddle for a short breather.
func _reset_ball() -> void:
	_ball_speed = _ball_base_speed
	_ball_velocity = Vector2.ZERO
	_state = State.SERVE
	_state_timer = _serve_delay
	if _ball and is_instance_valid(_ball):
		_ball.visible = true
		_stick_ball_to_paddle()

func _stick_ball_to_paddle() -> void:
	if _ball == null or not is_instance_valid(_ball) or _player == null or not is_instance_valid(_player):
		return
	_ball.global_position = _player.global_position - Vector2(0.0, _player_half_extents.y + _ball_radius + 6.0)

func _serve() -> void:
	var angle: float = deg_to_rad(randf_range(-_serve_angle_max_deg, _serve_angle_max_deg))
	_ball_velocity = Vector2(sin(angle), -cos(angle)) * _ball_speed
	_state = State.PLAY

func _update_ball(delta: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	var remaining: float = minf(delta, 0.25)
	while remaining > 0.0 and _state == State.PLAY:
		var step: float = minf(remaining, MAX_BALL_STEP_SEC)
		remaining -= step
		_step_ball(step)

func _step_ball(step: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var pos: Vector2 = _ball.global_position + _ball_velocity * step

	# Side and top walls: reflect and re-seat to avoid double bounces.
	var left_x: float = _wall_margin + _ball_radius
	var right_x: float = viewport_size.x - _wall_margin - _ball_radius
	var top_y: float = _wall_margin + _ball_radius
	if pos.x <= left_x and _ball_velocity.x < 0.0:
		pos.x = left_x
		_ball_velocity.x = -_ball_velocity.x
	elif pos.x >= right_x and _ball_velocity.x > 0.0:
		pos.x = right_x
		_ball_velocity.x = -_ball_velocity.x
	if pos.y <= top_y and _ball_velocity.y < 0.0:
		pos.y = top_y
		_ball_velocity.y = -_ball_velocity.y

	# Player paddle: only intercepts a ball travelling downward.
	if _ball_velocity.y > 0.0 and _player and is_instance_valid(_player):
		var p: Vector2 = _player.global_position
		var dx: float = absf(pos.x - p.x)
		var dy: float = absf(pos.y - p.y)
		if dx <= _player_half_extents.x + _ball_radius and dy <= _player_half_extents.y + _ball_radius:
			pos.y = p.y - _player_half_extents.y - _ball_radius
			_bounce_off_paddle(pos.x, p.x)

	# Bricks: circle vs AABB with corner normals; one brick per substep.
	if pos.y - _ball_radius < _grid_bottom_y + 8.0:
		pos = _collide_with_bricks(pos)

	_ball.global_position = pos

	# Ball lost below the screen.
	if pos.y - _ball_radius > viewport_size.y:
		_on_ball_lost()

func _bounce_off_paddle(ball_x: float, paddle_x: float) -> void:
	var offset: float = clampf((ball_x - paddle_x) / maxf(1.0, _player_half_extents.x), -1.0, 1.0)
	var angle: float = deg_to_rad(offset * _max_bounce_angle_deg)
	_ball_speed = minf(_ball_speed + _ball_speed_increase_hit, _ball_speed_max)
	_ball_velocity = Vector2(sin(angle), -cos(angle)) * _ball_speed

func _collide_with_bricks(pos: Vector2) -> Vector2:
	var radius_sq: float = _ball_radius * _ball_radius
	for i in range(_bricks.size() - 1, -1, -1):
		var brick: Dictionary = _bricks[i]
		var rect: Rect2 = brick.get("rect", Rect2())
		var closest := Vector2(
			clampf(pos.x, rect.position.x, rect.end.x),
			clampf(pos.y, rect.position.y, rect.end.y)
		)
		var delta: Vector2 = pos - closest
		var dist_sq: float = delta.length_squared()
		if dist_sq > radius_sq:
			continue
		var normal: Vector2
		if dist_sq > 0.0001:
			normal = delta.normalized()
		else:
			# Ball center inside the brick: push out along the least-penetrated axis.
			var center_delta: Vector2 = pos - rect.get_center()
			if absf(center_delta.x) / maxf(1.0, rect.size.x) > absf(center_delta.y) / maxf(1.0, rect.size.y):
				normal = Vector2(signf(center_delta.x), 0.0)
			else:
				normal = Vector2(0.0, signf(center_delta.y))
		if _ball_velocity.dot(normal) < 0.0:
			_ball_velocity = _ball_velocity.bounce(normal)
		_ball_speed = minf(_ball_speed + _ball_speed_increase_brick, _ball_speed_max)
		_ball_velocity = _ball_velocity.normalized() * _ball_speed
		pos = closest + normal * (_ball_radius + 0.5)
		_damage_brick(i)
		break
	return pos

func _damage_brick(index: int) -> void:
	var brick: Dictionary = _bricks[index]
	brick["hp"] = int(brick.get("hp", 1)) - 1
	var node_v: Variant = brick.get("node", null)
	if int(brick["hp"]) <= 0:
		var rect: Rect2 = brick.get("rect", Rect2())
		_bricks.remove_at(index)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
		if _game and is_instance_valid(_game) and randf() <= _crystal_brick_chance:
			if _game.has_method("spawn_reward_crystal_at"):
				_game.call("spawn_reward_crystal_at", rect.get_center())
		if _bricks.is_empty():
			_on_wall_cleared()
		return
	_refresh_brick_tint(brick)
	if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
		VFXManager.flash_sprite(node_v, Color(1.6, 1.6, 1.6), _brick_flash_sec)

func _on_ball_lost() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP; die() below 0.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent)))
		_player.call("take_damage", dmg)
	_reset_ball()

## Wall cleared before the timer: crystal rain and early finish.
func _on_wall_cleared() -> void:
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", _crystals_on_clear)
	_finish()

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "BreakoutCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_cfg.get("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_cfg.get("countdown_color", "#FFFFFF"))))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.z_as_relative = false
	_countdown_label.z_index = 60
	add_child(_countdown_label)

func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_cfg.get("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Restore the player BEFORE notifying the wave chain.
	_restore_player_mode()
	finished.emit()
	queue_free() # ball, bricks and label are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
