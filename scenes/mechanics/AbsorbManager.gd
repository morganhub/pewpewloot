extends Node2D

## AbsorbManager — Orchestre une vague "absorb" (inspiration Agar.io) :
## des vaisseaux-proies bien espaces descendent a rythme regulier, chacun avec
## sa valeur de masse affichee. Contact avec plus petit que soi = absorption
## (la masse et la taille du vaisseau grossissent) ; contact avec plus gros =
## degats + perte de masse. Les valeurs croissent au fil de la vague mais leur
## ordre est melange dans une fenetre glissante : un gros peut arriver AVANT le
## petit qui le rend mangeable, forcant des trajectoires en zigzag. La vague se
## conclut par le Devoreur, un colosse au gros chiffre : masse suffisante =
## absorption + pluie de cristaux, sinon a esquiver. Tir coupe, mouvement
## totalement libre. Contacts manuels par distance (pas de physics engine).

signal finished

enum State { INTRO, HUNT, FINAL, DONE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _enemy_skins: Dictionary = {} # world-level skin overrides: enemy_id -> skin path

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 30.0
var _elapsed: float = 0.0
var _time: float = 0.0

# Player mass (owned here, pushed to Player for label + scale).
var _mass: float = 10.0
var _start_mass: float = 10.0

# Prey scheduling.
var _values_queue: Array = [] # ordered spawn values (window-shuffled)
var _spawn_interval: float = 1.5
var _spawn_timer: float = 0.0
var _descent_speed: float = 115.0
var _final_value: float = 100.0
var _final_reserve: float = 8.0

# Alive prey. Entries: { "node": Node2D, "label": Label, "value": float,
# "radius": float, "wobble_phase": float, "x": float, "is_final": bool }
var _prey: Array = []
var _oversize_cooldown: float = 0.0

var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("absorb") if DataManager else {}
	var skins_v: Variant = _config.get("_enemy_skins", {})
	_enemy_skins = (skins_v as Dictionary) if skins_v is Dictionary else {}

	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("duration_sec_default", 30.0))))
	_spawn_interval = maxf(0.4, float(_config.get("spawn_interval_sec", _cfg.get("spawn_interval_sec", 1.5))))
	_descent_speed = maxf(30.0, float(_config.get("descent_speed_px_sec", _cfg.get("descent_speed_px_sec", 115.0))))
	_start_mass = maxf(1.0, float(_config.get("start_mass", _cfg.get("start_mass", 10.0))))
	_final_reserve = clampf(float(_cfg.get("final_reserve_sec", 8.0)), 3.0, _duration * 0.5)
	_mass = _start_mass

	_build_value_schedule()
	_begin_player_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.5)))
	set_process(true)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_absorb"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_absorb", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_absorb"):
		_player.call("end_absorb")

# =============================================================================
# VALUE SCHEDULE (growing chain, window-shuffled)
# =============================================================================

## Simulates the perfect run to build a growing prey-value chain, then shuffles
## the order inside a sliding window. The bounded displacement (window) times
## the spawn interval stays far below the screen-crossing time, so an
## out-of-order big prey is always still catchable once its unlock arrives.
func _build_value_schedule() -> void:
	_values_queue.clear()
	var hunt_time: float = maxf(4.0, _duration - _final_reserve)
	var count: int = maxi(3, int(floor(hunt_time / _spawn_interval)))
	var ratio_min: float = clampf(float(_cfg.get("prey_value_ratio_min", 0.35)), 0.05, 0.95)
	var ratio_max: float = clampf(float(_cfg.get("prey_value_ratio_max", 0.7)), ratio_min, 0.95)
	var running: float = _start_mass
	for i in range(count):
		var value: float = maxf(1.0, round(running * randf_range(ratio_min, ratio_max)))
		_values_queue.append(value)
		running += value
	# The Devourer asks for a fraction of the theoretical maximum: eating most
	# of the chain (not necessarily all of it) is enough.
	var margin: float = clampf(float(_config.get("final_mass_margin", _cfg.get("final_mass_margin", 0.75))), 0.2, 1.0)
	_final_value = maxf(_start_mass * 2.0, round(running * margin))
	# Bounded shuffle: each value can be displaced by at most `shuffle_window`.
	var window: int = maxi(1, int(_config.get("shuffle_window", _cfg.get("shuffle_window", 3))))
	for i in range(_values_queue.size()):
		var j: int = mini(i + randi() % window, _values_queue.size() - 1)
		var tmp: Variant = _values_queue[i]
		_values_queue[i] = _values_queue[j]
		_values_queue[j] = tmp

# =============================================================================
# PREY
# =============================================================================

func _spawn_next_prey() -> void:
	if _values_queue.is_empty():
		return
	var value: float = float(_values_queue.pop_front())
	# Runtime solvability guard: never leave the player with zero eatable
	# targets — rescue the spawn by shrinking it below the current mass.
	if value >= _mass and not _has_eatable_prey_alive():
		value = maxf(1.0, round(_mass * clampf(float(_cfg.get("eatable_rescue_ratio", 0.55)), 0.1, 0.9)))
	_spawn_prey(value, false)

func _spawn_prey(value: float, is_final: bool) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(30.0, float(_cfg.get("prey_side_margin_px", 60.0)))
	var x: float = viewport_size.x * 0.5
	if not is_final:
		# "Well spaced": sample a few candidates, keep the one farthest from
		# the alive prey ships.
		var best_dist: float = -1.0
		for attempt in range(3):
			var candidate: float = randf_range(margin, viewport_size.x - margin)
			var dist: float = _min_distance_to_prey_x(candidate)
			if dist > best_dist:
				best_dist = dist
				x = candidate

	var node := Node2D.new()
	node.name = "AbsorbFinal" if is_final else "AbsorbPrey"
	node.z_as_relative = false
	node.z_index = 10
	var prey_scale: float = _prey_scale_for_value(value, is_final)
	var size_px: float = maxf(24.0, float(_cfg.get("prey_base_size_px", 64.0)) * prey_scale)
	node.position = Vector2(x, float(_cfg.get("prey_spawn_y", -70.0)) - size_px * 0.5)
	var visual: Node2D = _build_prey_visual(size_px)
	node.add_child(visual)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_size: int = maxi(10, int(_cfg.get("value_label_font_size", 26)))
	if is_final:
		font_size = maxi(font_size, int(_cfg.get("mass_label_font_size", 56)))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(int(round(value)))
	label.size = Vector2(160.0, 40.0)
	label.position = Vector2(-80.0, -size_px * 0.5 - 42.0)
	node.add_child(label)
	add_child(node)

	var entry: Dictionary = {
		"node": node,
		"label": label,
		"value": value,
		"radius": size_px * 0.5,
		"wobble_phase": randf() * TAU,
		"x": x,
		"is_final": is_final
	}
	_prey.append(entry)
	_apply_prey_tint(entry)

func _min_distance_to_prey_x(x: float) -> float:
	var best: float = 99999.0
	for entry in _prey:
		best = minf(best, absf(float(entry.get("x", 0.0)) - x))
	return best

func _has_eatable_prey_alive() -> bool:
	for entry in _prey:
		if not bool(entry.get("is_final", false)) and float(entry.get("value", 0.0)) < _mass:
			return true
	return false

func _prey_scale_for_value(value: float, is_final: bool) -> float:
	var s: float = sqrt(maxf(1.0, value) / _start_mass)
	var s_min: float = maxf(0.2, float(_cfg.get("prey_scale_min", 0.5)))
	var s_max: float = maxf(s_min, float(_cfg.get("prey_scale_max", 2.6)))
	if is_final:
		s_max *= 1.4
	return clampf(s, s_min, s_max)

## Prey visual: per-wave "prey_assets" override > world skin of the enemy id >
## enemies.json visual. Fitted onto the prey size (uniform).
func _build_prey_visual(size_px: float) -> Node2D:
	var asset_path: String = ""
	var wave_assets_v: Variant = _config.get("prey_assets", _cfg.get("prey_assets", []))
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		var arr: Array = wave_assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	if asset_path == "":
		var enemy_id: String = str(_cfg.get("enemy_visual_enemy_id", "fighter"))
		asset_path = str(_enemy_skins.get(enemy_id, ""))
		if asset_path == "":
			var enemy_data: Dictionary = DataManager.get_enemy(enemy_id) if DataManager else {}
			var visual_v: Variant = enemy_data.get("visual", {})
			if visual_v is Dictionary:
				asset_path = str((visual_v as Dictionary).get("asset_anim", ""))
				if asset_path == "":
					asset_path = str((visual_v as Dictionary).get("asset", ""))
	var visual: Node2D = _build_sprite_fit(asset_path, size_px)
	if visual == null:
		var circle := Polygon2D.new()
		var points := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			points.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		circle.polygon = points
		circle.color = Color("#8A93A6")
		visual = circle
	return visual

func _build_sprite_fit(asset_path: String, size_px: float) -> Node2D:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null
	var res: Resource = load(asset_path)
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name) and names.size() > 0:
			anim_name = StringName(names[0])
		if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
			var animated := AnimatedSprite2D.new()
			animated.sprite_frames = frames
			animated.play(anim_name)
			var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
			if frame_tex:
				var f_size: Vector2 = frame_tex.get_size()
				if f_size.x > 0.0 and f_size.y > 0.0:
					animated.scale = Vector2.ONE * (size_px / maxf(f_size.x, f_size.y))
			return animated
		return null
	if res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = res as Texture2D
		var tex_size: Vector2 = (res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
		return sprite
	return null

## Green = eatable, red = too big; refreshed after every absorption.
func _apply_prey_tint(entry: Dictionary) -> void:
	var eatable: bool = float(entry.get("value", 0.0)) < _mass
	var color: Color = Color(str(_cfg.get("color_eatable", "#3FBF6A"))) if eatable \
		else Color(str(_cfg.get("color_oversize", "#E8553B")))
	var label_v: Variant = entry.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).add_theme_color_override("font_color", color)
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).modulate = Color(1.0, 1.12, 1.0) if eatable else Color(1.12, 0.92, 0.92)

func _retint_all_prey() -> void:
	for entry in _prey:
		_apply_prey_tint(entry)

# =============================================================================
# MATCH LOOP
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
	_oversize_cooldown = maxf(0.0, _oversize_cooldown - dt)
	_update_countdown_label()

	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.HUNT
				_spawn_timer = 0.0
		State.HUNT:
			_spawn_timer -= dt
			if _spawn_timer <= 0.0 and not _values_queue.is_empty():
				_spawn_timer = _spawn_interval
				_spawn_next_prey()
			# Devourer time: reserve reached or every prey already dispatched.
			if _elapsed >= _duration - _final_reserve and _values_queue.is_empty():
				_spawn_prey(_final_value, true)
				_state = State.FINAL
		State.FINAL:
			pass

	_update_prey(dt)
	_check_contacts()

	if _elapsed >= _duration:
		_finish()

func _update_prey(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var wobble_amp: float = maxf(0.0, float(_cfg.get("prey_wobble_amplitude_px", 8.0)))
	var wobble_hz: float = maxf(0.05, float(_cfg.get("prey_wobble_frequency_hz", 0.8)))
	for i in range(_prey.size() - 1, -1, -1):
		var entry: Dictionary = _prey[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_prey.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		var speed: float = _descent_speed
		if bool(entry.get("is_final", false)):
			speed = maxf(20.0, float(_cfg.get("final_descent_speed_px_sec", 70.0)))
		var x: float = float(entry.get("x", node.position.x)) \
			+ sin(_time * TAU * wobble_hz + float(entry.get("wobble_phase", 0.0))) * wobble_amp
		node.position = Vector2(x, node.position.y + speed * dt)
		# Missed prey leaves by the bottom (no damage, just a lost opportunity).
		if node.position.y > viewport_size.y + float(entry.get("radius", 30.0)) + 60.0:
			var was_final: bool = bool(entry.get("is_final", false))
			node.queue_free()
			_prey.remove_at(i)
			if was_final:
				_finish()

func _check_contacts() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	var player_scale: float = 1.0
	if _player.has_method("get_gate_runner_scale"):
		player_scale = maxf(0.1, float(_player.call("get_gate_runner_scale")))
	var player_radius: float = maxf(10.0, float(_cfg.get("contact_radius_base_px", 40.0))) * player_scale
	for i in range(_prey.size() - 1, -1, -1):
		var entry: Dictionary = _prey[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_prey.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		var reach: float = player_radius + float(entry.get("radius", 30.0)) * 0.8
		if node.global_position.distance_to(player_pos) > reach:
			continue
		if float(entry.get("value", 0.0)) < _mass:
			_absorb_prey(i, entry)
		else:
			_oversize_contact(entry)

func _absorb_prey(index: int, entry: Dictionary) -> void:
	var value: float = float(entry.get("value", 0.0))
	var was_final: bool = bool(entry.get("is_final", false))
	var node_v: Variant = entry.get("node", null)
	var at_pos: Vector2 = _player.global_position
	if node_v is Node2D and is_instance_valid(node_v):
		at_pos = (node_v as Node2D).global_position
		(node_v as Node2D).queue_free()
	_prey.remove_at(index)
	_mass += value
	if _player.has_method("set_absorb_mass"):
		_player.call("set_absorb_mass", _mass)
	if VFXManager and _player.has_method("get_gate_runner_scale"):
		VFXManager.flash_sprite(_player, Color(0.55, 1.0, 0.6), 0.12)
	_retint_all_prey()
	if _game and is_instance_valid(_game):
		if was_final:
			# Jackpot: the Devourer is swallowed, the wave ends early.
			if _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(0, int(_cfg.get("final_crystals", 8))))
			_finish()
			return
		var chance: float = clampf(float(_cfg.get("crystal_absorb_chance", 0.3)), 0.0, 1.0)
		if randf() <= chance and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_pos)

## Touching a bigger ship hurts and sheds mass; the prey survives and keeps
## descending. A short cooldown avoids per-frame repeats.
func _oversize_contact(_entry: Dictionary) -> void:
	if _oversize_cooldown > 0.0:
		return
	_oversize_cooldown = maxf(0.2, float(_cfg.get("oversize_contact_cooldown_sec", 0.9)))
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_cfg.get("oversize_contact_damage_percent", 0.15)), 0.0, 1.0)
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
	var loss: float = clampf(float(_cfg.get("mass_loss_on_oversize_contact", 0.1)), 0.0, 0.9)
	_mass = maxf(_start_mass, _mass * (1.0 - loss))
	if _player.has_method("set_absorb_mass"):
		_player.call("set_absorb_mass", _mass)
	_retint_all_prey()

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "AbsorbCountdownLabel"
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
	queue_free() # prey ships and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
