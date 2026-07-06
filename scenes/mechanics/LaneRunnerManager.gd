extends Node2D

## LaneRunnerManager — Orchestre une vague "lane_runner" (inspiration Subway
## Surfers / Temple Run) : le vaisseau est verrouille sur des voies fixes (snap
## X gere par Player.gd) et des murs indestructibles pleine-voie descendent a
## haute vitesse en rangees telegraphiees laissant toujours au moins une voie
## atteignable. Collision = degats % HP + breve invulnerabilite ; froler un mur
## juste apres un changement de voie (near-miss) = chance de cristal. Des
## trainees de collectibles (pieces facon Subway Surfers) apparaissent dans la
## voie sure : chaque piece rapporte du score (base x reward_multiplier de la
## vague/du monde) et une chance de cristal. Tir coupe, contacts manuels par
## distance (pas de physics engine). La vitesse et la cadence des rangees
## montent progressivement pendant la vague.

signal finished

enum State { INTRO, RUN, DONE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _obstacle_skins: Array = [] # world skin_overrides.obstacles.explosives

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 35.0
var _elapsed: float = 0.0
var _time: float = 0.0

# Lane geometry (mirrors the Player lane lock so both stay in sync).
var _lane_count: int = 3
var _lane_side_margin_px: float = 70.0

# Row scheduling / difficulty ramp.
var _row_timer: float = 0.0
var _last_free_lane: int = 1
var _pattern_rows: Array = [] # optional scripted rows: [[blocked lanes], ...]
var _pattern_row_index: int = 0
var _spawn_cutoff_sec: float = 2.5

# Rewards.
var _reward_multiplier: float = 1.0
var _collectible_score: int = 15

# Alive walls. Entries: { "node": Node2D, "lane": int, "half_height": float,
# "hit": bool, "passed": bool }
var _walls: Array = []
# Alive collectibles. Entries: { "node": Node2D, "lane": int, "pulse": float }
var _collectibles: Array = []

var _hit_invuln_timer: float = 0.0
var _countdown_label: Label = null
var _finished_emitted: bool = false

const PLAYER_HALF_HEIGHT_PX: float = 26.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("lane_runner") if DataManager else {}
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []

	_duration = maxf(8.0, float(_config.get("duration", _cfg.get("duration_sec_default", 35.0))))
	_lane_count = maxi(2, int(_get_conf("lane_count", 3)))
	_lane_side_margin_px = maxf(10.0, float(_get_conf("lane_side_margin_px", 70.0)))
	_spawn_cutoff_sec = maxf(0.5, float(_get_conf("spawn_stop_before_end_sec", 2.5)))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_collectible_score = maxi(0, int(_get_conf("collectible_score", 15)))

	var rows_v: Variant = _config.get("pattern_rows", [])
	if rows_v is Array:
		for row_v in (rows_v as Array):
			if row_v is Array:
				_pattern_rows.append((row_v as Array).duplicate())

	_last_free_lane = int(_lane_count / 2.0)
	_begin_player_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	_row_timer = 0.35 # first row arrives quickly after the intro
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_lane_runner"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_lane_runner", merged)

func _restore_player_mode() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _hit_invuln_timer > 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)
	_hit_invuln_timer = 0.0
	if _player.has_method("end_lane_runner"):
		_player.call("end_lane_runner")

# =============================================================================
# LANE GEOMETRY
# =============================================================================

func _lane_width() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	return maxf(1.0, viewport_size.x - _lane_side_margin_px * 2.0) / float(_lane_count)

func _lane_center_x(lane: int) -> float:
	return _lane_side_margin_px + _lane_width() * (float(clampi(lane, 0, _lane_count - 1)) + 0.5)

## Difficulty ramp position (0 at wave start -> 1 at wave end).
func _ramp_t() -> float:
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _current_speed() -> float:
	var v_start: float = maxf(50.0, float(_get_conf("wall_speed_px_sec_start", 380.0)))
	var v_end: float = maxf(v_start, float(_get_conf("wall_speed_px_sec_end", 600.0)))
	return lerpf(v_start, v_end, _ramp_t())

func _current_row_interval() -> float:
	var i_start: float = maxf(0.3, float(_get_conf("row_interval_sec_start", 1.7)))
	var i_end: float = clampf(float(_get_conf("row_interval_sec_end", 1.05)), 0.3, i_start)
	return lerpf(i_start, i_end, _ramp_t())

# =============================================================================
# ROWS (walls + collectible trail)
# =============================================================================

## Picks the blocked lanes of the next row. Scripted rows (pattern_rows) are
## consumed in a loop when provided; otherwise the row is procedural with a
## solvability guarantee: the guaranteed free lane never moves by more than one
## lane between two consecutive rows.
func _next_row_blocked_lanes() -> Array:
	if not _pattern_rows.is_empty():
		var scripted_v: Variant = _pattern_rows[_pattern_row_index % _pattern_rows.size()]
		_pattern_row_index += 1
		var scripted: Array = []
		if scripted_v is Array:
			for lane_v in (scripted_v as Array):
				var lane: int = clampi(int(lane_v), 0, _lane_count - 1)
				if not scripted.has(lane):
					scripted.append(lane)
		# Defensive: a fully blocked scripted row would be unwinnable.
		if scripted.size() >= _lane_count:
			scripted.remove_at(randi() % scripted.size())
		if not scripted.is_empty():
			_update_last_free_lane_from_blocked(scripted)
			return scripted
	# Procedural: move the safe lane by at most one step, then block others.
	var free_lane: int = clampi(_last_free_lane + (randi() % 3) - 1, 0, _lane_count - 1)
	_last_free_lane = free_lane
	var candidates: Array = []
	for i in range(_lane_count):
		if i != free_lane:
			candidates.append(i)
	candidates.shuffle()
	var blocked_count: int = 1
	var double_chance: float = clampf(float(_get_conf("double_wall_chance", 0.3)), 0.0, 1.0)
	if _lane_count > 2 and randf() <= double_chance:
		blocked_count = mini(2, candidates.size())
	var blocked: Array = []
	for i in range(blocked_count):
		blocked.append(candidates[i])
	return blocked

func _update_last_free_lane_from_blocked(blocked: Array) -> void:
	var free_lanes: Array = []
	for i in range(_lane_count):
		if not blocked.has(i):
			free_lanes.append(i)
	if free_lanes.is_empty():
		return
	# Keep the free lane closest to the previous one as the reference path.
	var best: int = int(free_lanes[0])
	for lane_v in free_lanes:
		if absi(int(lane_v) - _last_free_lane) < absi(best - _last_free_lane):
			best = int(lane_v)
	_last_free_lane = best

func _spawn_row() -> void:
	var blocked: Array = _next_row_blocked_lanes()
	var wall_height: float = maxf(24.0, float(_get_conf("wall_height_px", 88.0)))
	var wall_width: float = _lane_width() * clampf(float(_get_conf("wall_width_ratio", 0.92)), 0.3, 1.0)
	var spawn_y: float = minf(-20.0, float(_get_conf("wall_spawn_y", -130.0)))
	for lane_v in blocked:
		var lane: int = int(lane_v)
		var node := Node2D.new()
		node.name = "LaneWall"
		node.z_as_relative = false
		node.z_index = 10
		node.position = Vector2(_lane_center_x(lane), spawn_y - wall_height * 0.5)
		node.add_child(_build_wall_visual(wall_width, wall_height))
		add_child(node)
		_walls.append({
			"node": node,
			"lane": lane,
			"half_height": wall_height * 0.5,
			"hit": false,
			"passed": false
		})
	var trail_chance: float = clampf(float(_get_conf("collectible_trail_chance", 0.75)), 0.0, 1.0)
	if randf() <= trail_chance:
		_spawn_collectible_trail(_last_free_lane, spawn_y - wall_height)

## A vertical trail of collectibles in the safe lane, laid out above the row it
## escorts so the player scoops it right after the dodge.
func _spawn_collectible_trail(lane: int, base_y: float) -> void:
	var count_min: int = maxi(1, int(_get_conf("collectible_count_min", 3)))
	var count_max: int = maxi(count_min, int(_get_conf("collectible_count_max", 5)))
	var count: int = count_min + (randi() % (count_max - count_min + 1))
	var spacing: float = maxf(20.0, float(_get_conf("collectible_spacing_px", 72.0)))
	var size_px: float = maxf(12.0, float(_get_conf("collectible_size_px", 42.0)))
	for i in range(count):
		var node := Node2D.new()
		node.name = "LaneCollectible"
		node.z_as_relative = false
		node.z_index = 12
		node.position = Vector2(_lane_center_x(lane), base_y - spacing * float(i + 1))
		node.add_child(_build_collectible_visual(size_px))
		add_child(node)
		_collectibles.append({
			"node": node,
			"lane": lane,
			"pulse": randf() * TAU
		})

# =============================================================================
# VISUALS
# =============================================================================

## Wall visual: per-wave "wall_assets" override > world obstacle skins >
## type assets. The texture tiles horizontally (cover-crop per tile, never
## stretched) to fill the full lane width; fallback = flat tinted rectangle.
func _build_wall_visual(width: float, height: float) -> Node2D:
	var root := Node2D.new()
	var asset_path: String = ""
	var wave_assets_v: Variant = _config.get("wall_assets", null)
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		var arr: Array = wave_assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	elif not _obstacle_skins.is_empty():
		asset_path = str(_obstacle_skins[randi() % _obstacle_skins.size()])
	else:
		var cfg_assets_v: Variant = _cfg.get("wall_assets", [])
		if cfg_assets_v is Array and not (cfg_assets_v as Array).is_empty():
			var cfg_arr: Array = cfg_assets_v as Array
			asset_path = str(cfg_arr[randi() % cfg_arr.size()])

	var texture: Texture2D = null
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			texture = res as Texture2D

	if texture == null:
		var rect := Polygon2D.new()
		rect.polygon = PackedVector2Array([
			Vector2(-width * 0.5, -height * 0.5),
			Vector2(width * 0.5, -height * 0.5),
			Vector2(width * 0.5, height * 0.5),
			Vector2(-width * 0.5, height * 0.5)
		])
		rect.color = Color(str(_get_conf("wall_fallback_color", "#8A93A6")))
		root.add_child(rect)
		return root

	var tile_count: int = maxi(1, int(ceil(width / height)))
	var tile_w: float = width / float(tile_count)
	var tex_size: Vector2 = texture.get_size()
	var tint := Color(str(_get_conf("wall_tint", "#FFFFFF")))
	for i in range(tile_count):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.modulate = tint
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			# Cover-crop: uniform scale to fill the tile, source region centered.
			var scale_f: float = maxf(tile_w / tex_size.x, height / tex_size.y)
			var src_size := Vector2(tile_w / scale_f, height / scale_f)
			sprite.region_enabled = true
			sprite.region_rect = Rect2((tex_size - src_size) * 0.5, src_size)
			sprite.scale = Vector2.ONE * scale_f
		sprite.position = Vector2(-width * 0.5 + tile_w * (float(i) + 0.5), 0.0)
		root.add_child(sprite)
	return root

## Collectible visual: per-wave "collectible_assets" override > type assets,
## random per piece, tinted; fallback = small golden diamond.
func _build_collectible_visual(size_px: float) -> Node2D:
	var asset_path: String = ""
	var assets_v: Variant = _config.get("collectible_assets", _cfg.get("collectible_assets", []))
	if assets_v is Array and not (assets_v as Array).is_empty():
		var arr: Array = assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	var tint := Color(str(_get_conf("collectible_tint", "#FFD56B")))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Texture2D:
			var sprite := Sprite2D.new()
			sprite.texture = res as Texture2D
			sprite.modulate = tint
			var tex_size: Vector2 = (res as Texture2D).get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			return sprite
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -size_px * 0.5),
		Vector2(size_px * 0.4, 0.0),
		Vector2(0.0, size_px * 0.5),
		Vector2(-size_px * 0.4, 0.0)
	])
	diamond.color = tint
	return diamond

# =============================================================================
# RUN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	var dt: float = minf(delta, 0.1)
	_time += dt
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	_tick_hit_invuln(dt)

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.RUN
		State.RUN:
			_row_timer -= dt
			if _row_timer <= 0.0 and _elapsed < _duration - _spawn_cutoff_sec:
				_row_timer = _current_row_interval()
				_spawn_row()

	var speed: float = _current_speed()
	_update_walls(dt, speed)
	_update_collectibles(dt, speed)

	if _elapsed >= _duration:
		_finish()

func _tick_hit_invuln(dt: float) -> void:
	if _hit_invuln_timer <= 0.0:
		return
	_hit_invuln_timer -= dt
	if _hit_invuln_timer <= 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)

func _player_lane() -> int:
	if _player.has_method("get_lane_runner_lane"):
		return int(_player.call("get_lane_runner_lane"))
	return -1

func _update_walls(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_lane: int = _player_lane()
	var player_y: float = _player.global_position.y
	for i in range(_walls.size() - 1, -1, -1):
		var entry: Dictionary = _walls[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_walls.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		var half_height: float = float(entry.get("half_height", 44.0))

		# Contact: same lane + vertical overlap with the ship band.
		if not bool(entry.get("hit", false)) and _hit_invuln_timer <= 0.0 \
			and int(entry.get("lane", -1)) == player_lane \
			and absf(node.position.y - player_y) <= half_height + PLAYER_HALF_HEIGHT_PX:
			entry["hit"] = true
			_walls[i] = entry
			_on_wall_hit()
			continue

		# Fully passed the ship line: near-miss check, once per wall.
		if not bool(entry.get("passed", false)) and node.position.y - half_height > player_y + PLAYER_HALF_HEIGHT_PX:
			entry["passed"] = true
			_walls[i] = entry
			if not bool(entry.get("hit", false)):
				_check_near_miss(int(entry.get("lane", -1)), player_lane, node.position)

		if node.position.y - half_height > viewport_size.y + 60.0:
			node.queue_free()
			_walls.remove_at(i)

## Collision: % of max HP through the standard damage pipeline (shield first),
## then a short invulnerability so a wall never chews the ship twice.
func _on_wall_hit() -> void:
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("hit_damage_percent", 0.15)), 0.0, 1.0)
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
	if _player == null or not is_instance_valid(_player):
		return # the hit was lethal, the player is already gone
	_hit_invuln_timer = maxf(0.2, float(_get_conf("hit_invuln_sec", 1.0)))
	if _player.has_method("set_invincible"):
		_player.call("set_invincible", true)
	if VFXManager:
		VFXManager.screen_shake(6, 0.2)

## Near-miss: the wall passed in the lane right next to the ship AND the player
## dodged into its lane recently -> crystal chance (skill reward).
func _check_near_miss(wall_lane: int, player_lane: int, at_pos: Vector2) -> void:
	if wall_lane < 0 or player_lane < 0 or absi(wall_lane - player_lane) != 1:
		return
	var window_msec: int = int(maxf(0.0, float(_get_conf("near_miss_window_sec", 0.6))) * 1000.0)
	if _player.has_method("get_lane_runner_msec_since_switch") \
		and int(_player.call("get_lane_runner_msec_since_switch")) > window_msec:
		return
	var chance: float = clampf(float(_get_conf("near_miss_crystal_chance", 0.35)), 0.0, 1.0)
	if randf() > chance:
		return
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", Vector2(at_pos.x, _player.global_position.y))

func _update_collectibles(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_lane: int = _player_lane()
	var player_y: float = _player.global_position.y
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 48.0)))
	for i in range(_collectibles.size() - 1, -1, -1):
		var entry: Dictionary = _collectibles[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_collectibles.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		# Gentle pulse so the trail reads as "to grab".
		var pulse: float = 1.0 + sin(_time * TAU * 1.6 + float(entry.get("pulse", 0.0))) * 0.12
		node.scale = Vector2.ONE * pulse

		if int(entry.get("lane", -1)) == player_lane and absf(node.position.y - player_y) <= pickup_radius:
			var at_pos: Vector2 = node.global_position
			node.queue_free()
			_collectibles.remove_at(i)
			_collect(at_pos)
			continue

		if node.position.y > viewport_size.y + 60.0:
			node.queue_free()
			_collectibles.remove_at(i)

## Collectible reward: score (base x wave/world multiplier) + crystal chance.
func _collect(at_pos: Vector2) -> void:
	var points: int = int(round(float(_collectible_score) * _reward_multiplier))
	if _game and is_instance_valid(_game):
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, at_pos)
		var chance: float = clampf(float(_get_conf("collectible_crystal_chance", 0.12)), 0.0, 1.0)
		if randf() <= chance and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_pos)
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.flash_sprite(_player, Color(1.0, 0.9, 0.55), 0.1)

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "LaneRunnerCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_get_conf("countdown_color", "#FFFFFF"))))
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
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9))
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
	queue_free() # walls and collectibles are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
