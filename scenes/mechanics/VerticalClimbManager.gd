extends Node2D

## VerticalClimbManager — Orchestre une vague "vertical_climb" :
## avarie moteur, le vaisseau ne vole plus et doit rebondir d'accelerateur en
## accelerateur (plateformes) pour rester au-dessus d'une nappe de lave
## mortelle qui monte. Chaque plateforme TOMBE apres le rebond (usage unique).
## Le monde defile vers le bas quand le vaisseau depasse la ligne d'ascension
## (illusion de montee infinie). Cristaux a ramasser sur la route ; tomber
## dans la lave = mort (tous les HP). Duree limitee, compte a rebours au HUD.
## Y du vaisseau pilote par ce manager (Player.set_climb_y), X reste au joueur.

signal finished

enum State { INTRO, PLAY, DONE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 40.0
var _elapsed: float = 0.0

# Ship vertical physics (X is player-controlled).
var _ship_y: float = 0.0
var _ship_vy: float = 0.0
var _intro_from_y: float = 0.0
var _gravity: float = 1650.0
var _bounce_speed: float = 760.0
var _boost_bounce_speed: float = 1150.0
var _ascent_line_y: float = 0.0
var _ship_half_h: float = 22.0
var _ship_half_w: float = 34.0

# Platforms. Entries: { node, x, y, half_w, half_h, moving, move_phase,
# falling, fall_vy, boost, crystal }
var _platforms: Array = []
var _platform_size: Vector2 = Vector2(140.0, 20.0)
var _gap_min: float = 105.0
var _gap_max: float = 145.0
var _max_dx: float = 170.0
var _side_margin: float = 70.0
var _highest_platform_y: float = 0.0
var _last_platform_x: float = 0.0
var _moving_amp: float = 62.0
var _moving_hz: float = 0.55
var _time: float = 0.0

# Lava band (screen-space hazard, rises slowly, recedes when climbing fast).
var _lava_node: Node2D = null
var _lava_sprite: Sprite2D = null
var _lava_top_y: float = 0.0
var _lava_top_min_y: float = 0.0
var _lava_top_max_y: float = 0.0
var _lava_rise: float = 4.0
var _lava_bob_amp: float = 7.0
var _lava_bob_hz: float = 0.7

var _crystal_pickup_radius: float = 36.0
var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("vertical_climb") if DataManager else {}
	var viewport_size: Vector2 = get_viewport_rect().size

	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 40.0))))
	_gravity = maxf(200.0, float(_config.get("gravity_px_sec2", _cfg.get("gravity_px_sec2", 1650.0))))
	_bounce_speed = maxf(120.0, float(_config.get("bounce_speed_px_sec", _cfg.get("bounce_speed_px_sec", 760.0))))
	_boost_bounce_speed = maxf(_bounce_speed, float(_cfg.get("boost_bounce_speed_px_sec", 1150.0)))
	_ascent_line_y = viewport_size.y * clampf(float(_cfg.get("ascent_line_ratio", 0.34)), 0.15, 0.6)
	_ship_half_h = maxf(6.0, float(_cfg.get("ship_half_height_px", 22.0)))
	_ship_half_w = maxf(6.0, float(_cfg.get("ship_half_width_px", 34.0)))

	_platform_size = Vector2(
		maxf(40.0, float(_cfg.get("platform_width_px", 140.0))),
		maxf(8.0, float(_cfg.get("platform_height_px", 20.0)))
	)
	_gap_min = maxf(40.0, float(_config.get("platform_gap_y_min_px", _cfg.get("platform_gap_y_min_px", 105.0))))
	_gap_max = maxf(_gap_min, float(_config.get("platform_gap_y_max_px", _cfg.get("platform_gap_y_max_px", 145.0))))
	_max_dx = maxf(40.0, float(_cfg.get("platform_max_dx_px", 170.0)))
	_side_margin = maxf(20.0, float(_cfg.get("platform_side_margin_px", 70.0)))
	_moving_amp = maxf(0.0, float(_cfg.get("moving_amplitude_px", 62.0)))
	_moving_hz = maxf(0.05, float(_cfg.get("moving_speed_hz", 0.55)))

	_lava_rise = maxf(0.0, float(_config.get("lava_rise_px_sec", _cfg.get("lava_rise_px_sec", 4.0))))
	_lava_bob_amp = maxf(0.0, float(_cfg.get("lava_bob_amplitude_px", 7.0)))
	_lava_bob_hz = maxf(0.05, float(_cfg.get("lava_bob_frequency_hz", 0.7)))
	_lava_top_max_y = viewport_size.y * clampf(float(_cfg.get("lava_top_base_ratio", 0.88)), 0.5, 0.98)
	_lava_top_min_y = viewport_size.y * clampf(float(_cfg.get("lava_top_min_ratio", 0.55)), 0.3, 0.9)
	_lava_top_y = _lava_top_max_y

	_crystal_pickup_radius = maxf(12.0, float(_cfg.get("crystal_pickup_radius_px", 36.0)))

	_begin_player_mode()
	_spawn_lava()
	_build_initial_platforms(viewport_size)
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.8)))
	set_process(true)

## Mode libre "continuous" : la difficulté de l'ascension EN COURS est re-scalée
## au changement de level — position, plateformes et lave préservées. Les gaps
## scalés s'appliquent aux prochaines plateformes générées vers le haut.
func update_free_mode_config(cfg: Dictionary) -> void:
	_gravity = maxf(200.0, float(cfg.get("gravity_px_sec2", _gravity)))
	_bounce_speed = maxf(120.0, float(cfg.get("bounce_speed_px_sec", _bounce_speed)))
	_boost_bounce_speed = maxf(_bounce_speed, float(_cfg.get("boost_bounce_speed_px_sec", 1150.0)))
	_gap_min = maxf(40.0, float(cfg.get("platform_gap_y_min_px", _gap_min)))
	_gap_max = maxf(_gap_min, float(cfg.get("platform_gap_y_max_px", _gap_max)))
	_lava_rise = maxf(0.0, float(cfg.get("lava_rise_px_sec", _lava_rise)))

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_climb"):
		_player.call("begin_climb")
		_intro_from_y = _player.global_position.y
		_ship_y = _intro_from_y
		_ship_vy = 0.0

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_climb"):
		_player.call("end_climb")

# =============================================================================
# WORLD BUILD
# =============================================================================

func _build_initial_platforms(viewport_size: Vector2) -> void:
	var start_y: float = viewport_size.y * clampf(float(_cfg.get("start_y_ratio", 0.62)), 0.3, 0.85)
	var start_x: float = viewport_size.x * 0.5
	if _player and is_instance_valid(_player):
		start_x = clampf(_player.global_position.x, _side_margin, viewport_size.x - _side_margin)
	# Guaranteed launch pad right under the ship's intro position.
	_spawn_platform(start_x, start_y + _ship_half_h + _platform_size.y * 0.5 + 4.0, true)
	_last_platform_x = start_x
	_highest_platform_y = start_y + _ship_half_h + _platform_size.y * 0.5 + 4.0
	_fill_platforms_upward()

## Keeps the sky populated: platforms are generated above the screen with a
## bounded horizontal delta so the next accelerator is always reachable.
func _fill_platforms_upward() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	while _highest_platform_y > -60.0:
		var gap: float = randf_range(_gap_min, _gap_max)
		var new_y: float = _highest_platform_y - gap
		var new_x: float = clampf(
			_last_platform_x + randf_range(-_max_dx, _max_dx),
			_side_margin, viewport_size.x - _side_margin
		)
		_spawn_platform(new_x, new_y, false)
		_highest_platform_y = new_y
		_last_platform_x = new_x

func _spawn_platform(x: float, y: float, force_static: bool) -> void:
	var node := Node2D.new()
	node.name = "ClimbPlatform"
	node.z_as_relative = false
	node.z_index = 9
	node.position = Vector2(x, y)
	var boost: bool = not force_static and randf() <= clampf(float(_cfg.get("boost_platform_chance", 0.12)), 0.0, 1.0)
	var moving: bool = not force_static and not boost \
		and randf() <= clampf(float(_cfg.get("moving_platform_chance", 0.22)), 0.0, 1.0)
	var visual: Node2D = _make_platform_visual()
	if boost:
		visual.modulate = Color(str(_cfg.get("boost_tint", "#FFD56B")))
	node.add_child(visual)
	add_child(node)

	var entry: Dictionary = {
		"node": node,
		"x": x,
		"y": y,
		"half_w": _platform_size.x * 0.5,
		"half_h": _platform_size.y * 0.5,
		"moving": moving,
		"move_phase": randf() * TAU,
		"falling": false,
		"fall_vy": 0.0,
		"boost": boost,
		"crystal": null
	}
	# Some accelerators carry a crystal to grab on the way up.
	if not force_static and randf() <= clampf(float(_cfg.get("crystal_platform_chance", 0.25)), 0.0, 1.0):
		var crystal: Node2D = _make_crystal_marker()
		if crystal:
			crystal.position = Vector2(0.0, -(_platform_size.y * 0.5 + 34.0))
			node.add_child(crystal)
			entry["crystal"] = crystal
	_platforms.append(entry)

## "Cover" fill: the platform asset (random from the list) is cropped to the
## platform aspect ratio then scaled to the exact platform size.
func _make_platform_visual() -> Node2D:
	var tex: Texture2D = _texture_from_path(_pick_platform_asset())
	if tex == null:
		var poly := Polygon2D.new()
		var half: Vector2 = _platform_size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		poly.color = Color("#7FA8C9")
		return poly
	var sprite := Sprite2D.new()
	sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		var target_aspect: float = _platform_size.x / _platform_size.y
		var tex_aspect: float = tex_size.x / tex_size.y
		var region_size: Vector2
		if tex_aspect > target_aspect:
			region_size = Vector2(tex_size.y * target_aspect, tex_size.y)
		else:
			region_size = Vector2(tex_size.x, tex_size.x / target_aspect)
		sprite.region_enabled = true
		sprite.region_rect = Rect2((tex_size - region_size) * 0.5, region_size)
		sprite.scale = _platform_size / region_size
	return sprite

## Asset priority: per-wave "platform_assets" override > wave-type defaults.
func _pick_platform_asset() -> String:
	var wave_assets_v: Variant = _config.get("platform_assets", [])
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		var wave_arr: Array = wave_assets_v as Array
		return str(wave_arr[randi() % wave_arr.size()])
	var cfg_assets_v: Variant = _cfg.get("platform_assets", [])
	if cfg_assets_v is Array and not (cfg_assets_v as Array).is_empty():
		var cfg_arr: Array = cfg_assets_v as Array
		return str(cfg_arr[randi() % cfg_arr.size()])
	return ""

func _make_crystal_marker() -> Node2D:
	var tex: Texture2D = _texture_from_path(str(_cfg.get("crystal_asset", "res://assets/ui/icons/crystal.png")))
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sprite.scale = (Vector2.ONE * 34.0) / Vector2(maxf(tex_size.x, tex_size.y), maxf(tex_size.x, tex_size.y))
	return sprite

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

func _spawn_lava() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_lava_node = Node2D.new()
	_lava_node.name = "LavaBand"
	_lava_node.z_as_relative = false
	_lava_node.z_index = 14
	add_child(_lava_node)
	var tex: Texture2D = _texture_from_path(str(_cfg.get("lava_asset", "")))
	var band_height: float = viewport_size.y - _lava_top_min_y + 80.0
	if tex != null:
		_lava_sprite = Sprite2D.new()
		_lava_sprite.texture = tex
		_lava_sprite.centered = false
		_lava_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_lava_sprite.region_enabled = true
		_lava_sprite.region_rect = Rect2(0.0, 0.0, viewport_size.x, band_height)
		_lava_sprite.modulate = Color(str(_cfg.get("lava_tint", "#FF9A55")))
		_lava_node.add_child(_lava_sprite)
	else:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(viewport_size.x, 0),
			Vector2(viewport_size.x, band_height), Vector2(0, band_height)
		])
		poly.color = Color("#E8553B")
		_lava_node.add_child(poly)
	_update_lava_position()

func _update_lava_position() -> void:
	if _lava_node == null or not is_instance_valid(_lava_node):
		return
	var bob: float = sin(_time * TAU * _lava_bob_hz) * _lava_bob_amp
	_lava_node.position = Vector2(0.0, _lava_top_y + bob)

# =============================================================================
# MATCH LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	var dt: float = minf(delta, 0.05)
	_time += dt
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	match _state:
		State.INTRO:
			_state_timer -= delta
			var t: float = 1.0 - clampf(_state_timer / maxf(0.05, float(_cfg.get("intro_tween_sec", 0.8))), 0.0, 1.0)
			var start_y: float = get_viewport_rect().size.y * clampf(float(_cfg.get("start_y_ratio", 0.62)), 0.3, 0.85)
			_ship_y = lerpf(_intro_from_y, start_y, t)
			_player.call("set_climb_y", _ship_y)
			if _state_timer <= 0.0:
				_ship_vy = -_bounce_speed # engine sputters: first launch
				_state = State.PLAY
		State.PLAY:
			_step_climb(dt)
	_update_lava_position()
	if _elapsed >= _duration:
		_finish()

func _step_climb(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var prev_bottom: float = _ship_y + _ship_half_h
	_ship_vy += _gravity * dt
	var new_y: float = _ship_y + _ship_vy * dt
	var new_bottom: float = new_y + _ship_half_h
	var ship_x: float = _player.global_position.x

	# Platform contacts: only while falling, only crossing the platform top.
	if _ship_vy > 0.0:
		for entry in _platforms:
			if bool(entry.get("falling", false)):
				continue
			var node_v: Variant = entry.get("node", null)
			if not (node_v is Node2D) or not is_instance_valid(node_v):
				continue
			var plat_pos: Vector2 = (node_v as Node2D).position
			var plat_top: float = plat_pos.y - float(entry.get("half_h", 10.0))
			if prev_bottom <= plat_top and new_bottom >= plat_top:
				var reach: float = float(entry.get("half_w", 56.0)) + _ship_half_w * 0.35
				if absf(ship_x - plat_pos.x) <= reach:
					new_y = plat_top - _ship_half_h
					_ship_vy = -(_boost_bounce_speed if bool(entry.get("boost", false)) else _bounce_speed)
					_drop_platform(entry)
					break

	# Above the ascent line, upward motion becomes downward world scroll.
	if new_y < _ascent_line_y:
		var scroll: float = _ascent_line_y - new_y
		new_y = _ascent_line_y
		_scroll_world(scroll)

	_ship_y = new_y
	_player.call("set_climb_y", _ship_y)

	_update_platforms(dt)
	_collect_crystals(ship_x)

	# Lava: slow rise, deadly on contact (full HP loss = level lost).
	_lava_top_y = clampf(_lava_top_y - _lava_rise * dt, _lava_top_min_y, _lava_top_max_y)
	if _ship_y + _ship_half_h >= _lava_top_y or _ship_y > viewport_size.y + 60.0:
		if _player.has_method("take_damage"):
			_player.call("take_damage", 99999)

func _scroll_world(amount: float) -> void:
	for entry in _platforms:
		entry["y"] = float(entry.get("y", 0.0)) + amount
	_highest_platform_y += amount
	# Climbing fast pushes the lava back down (it keeps chasing from below).
	_lava_top_y = clampf(_lava_top_y + amount, _lava_top_min_y, _lava_top_max_y)
	_fill_platforms_upward()

func _update_platforms(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(_platforms.size() - 1, -1, -1):
		var entry: Dictionary = _platforms[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_platforms.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		if bool(entry.get("falling", false)):
			entry["fall_vy"] = float(entry.get("fall_vy", 0.0)) + _gravity * 0.8 * dt
			entry["y"] = float(entry.get("y", 0.0)) + float(entry["fall_vy"]) * dt
			node.modulate.a = maxf(0.0, node.modulate.a - dt * 1.6)
		var x: float = float(entry.get("x", 0.0))
		if bool(entry.get("moving", false)) and not bool(entry.get("falling", false)):
			x += sin(_time * TAU * _moving_hz + float(entry.get("move_phase", 0.0))) * _moving_amp
			x = clampf(x, _side_margin, viewport_size.x - _side_margin)
		node.position = Vector2(x, float(entry.get("y", 0.0)))
		# Free platforms that left the screen (fallen or scrolled out).
		if float(entry.get("y", 0.0)) > viewport_size.y + 90.0:
			node.queue_free()
			_platforms.remove_at(i)

## The accelerator burns out after one use: flash, detach and fall.
func _drop_platform(entry: Dictionary) -> void:
	entry["falling"] = true
	entry["fall_vy"] = 40.0
	entry["moving"] = false
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
		VFXManager.flash_sprite(node_v, Color(1.7, 1.7, 1.7), 0.08)

func _collect_crystals(_ship_x: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	for entry in _platforms:
		var crystal_v: Variant = entry.get("crystal", null)
		if crystal_v == null or not (crystal_v is Node2D) or not is_instance_valid(crystal_v):
			continue
		var crystal: Node2D = crystal_v as Node2D
		if crystal.global_position.distance_to(player_pos) <= _crystal_pickup_radius:
			entry["crystal"] = null
			crystal.queue_free()
			# The real reward spawns on the ship and is magnet-collected
			# instantly by the standard bonus-crystal flow (score, VFX).
			if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
				_game.call("spawn_reward_crystal_at", player_pos)

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "ClimbCountdownLabel"
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
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_cfg.get("countdown_y_ratio", 0.1)), 0.02, 0.9))
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
	queue_free() # platforms, lava and label are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
