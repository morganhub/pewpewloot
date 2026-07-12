extends Node2D

## AbsorbManager — Orchestre une vague "absorb" (inspiration Agar.io) :
## ARÈNE STATIQUE (refonte 2026-07-12) — le décor ne défile plus : les proies
## entrent par les bords et ERRENT lentement dans l'arène (rebond doux aux
## bords, jamais de sortie), le joueur se déplace librement dans TOUTES les
## directions (zone interdite du haut levée). Chaque proie AFFICHE SA VALEUR.
## Contact avec plus petit que soi = absorption (masse et taille grossissent) ;
## contact avec plus gros = dégâts + perte de masse. Valeurs croissantes
## mélangées en fenêtre glissante. Climax : le Dévoreur (colosse) — masse
## suffisante = absorption + pluie de cristaux, sinon à esquiver.
## Tir coupé. Contacts manuels par distance (pas de physics engine).
##
## PICKUPS & ÉVÉNEMENTS (scheduler ALTERNÉ pickup <-> event, cooldown aléatoire
## absorb_event_cd_min/max_sec, anti-répétition par famille) :
## - Pickups (orbes flottants collectés au contact) : decoy (les proies
##   convergent vers le point), freeze (dérive figée), overcharge (mangeable
##   jusqu'à masse × ratio), crystallize (cristal garanti par absorption),
##   repulse (les trop-gros sont repoussés).
## - Événements : school (banc de mini-proies traversant), tide (dérive ×2.5),
##   eclipse (valeurs masquées), golden (proie dorée traversante, toujours
##   mangeable + cristaux), mist (brume — halo autour du vaisseau, shader
##   pong_blackout).
## VARIANTES (chances progressives × lerp(special_chance_start_ratio, 1,
## progression) roulées au spawn) : camo (valeur visible seulement de près),
## flee (fuyarde), predator (oversize qui POURSUIT tant qu'il est plus gros),
## split (libère des minis à l'absorption), toxic (violet : -masse),
## stale growth (grossit avec le temps à l'écran). Jeûne (fasting_*) et combo
## de gloutonnerie (5 absorptions < 3 s = gains ×2). FINAL : duel de Dévoreurs
## (un seul absorbable) et exode (les proies restantes fuient) sur chances.
## Fond d'arène dédié : arena_backgrounds[] via begin_wave_background_override
## (scroll 0 — figé), restauré à la fin.

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
# "base_value": float, "radius": float, "base_radius": float, "is_final": bool,
# "vel": Vector2, "wander_timer": float, "traverse": bool (sort de l'arène),
# "kind": ""|"toxic"|"golden"|"school"|"devourer_decoy", "camo": bool,
# "flee": bool, "predator": bool, "split": bool, "stale": float,
# "resync": float }
var _prey: Array = []
var _oversize_cooldown: float = 0.0

# --- Scheduler alterné pickups <-> événements (anti-répétition par famille) ---
var _sched_timer: float = 0.0
var _next_family_pickup: bool = true
var _last_pickup: String = ""
var _last_event: String = ""
# Pickups flottants : { "node": Node2D, "pos": Vector2, "vel": Vector2,
# "id": String, "despawn": float }.
var _pickups: Array = []
# --- Effets actifs (timers) ---
var _decoy_time: float = 0.0
var _decoy_pos: Vector2 = Vector2.ZERO
var _freeze_time: float = 0.0
var _overcharge_time: float = 0.0
var _crystallize_time: float = 0.0
var _repulse_time: float = 0.0
var _tide_time: float = 0.0
var _eclipse_time: float = 0.0
var _mist_time: float = 0.0
var _mist_rect: ColorRect = null
# --- Combo de gloutonnerie ---
var _absorb_times: Array = []
var _combo_time: float = 0.0
# --- Fond d'arène (override figé) ---
var _arena_bg_active: bool = false

const MIST_SHADER_PATH: String = "res://scenes/mechanics/pong_blackout.gdshader"

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
	_begin_arena_background()
	_sched_timer = randf_range(maxf(1.0, _conf_f("absorb_event_cd_min_sec", 12.0)),
		maxf(1.0, _conf_f("absorb_event_cd_max_sec", 24.0)))

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.5)))
	set_process(true)

## Per-wave override (world_X.json / freemode base_wave) > défauts du type.
func _conf_f(key: String, fallback: float) -> float:
	return float(_config.get(key, _cfg.get(key, fallback)))

## Progression 0->1 : level du mode libre (restart : ré-injecté chaque round)
## sinon temps écoulé — pilote les chances progressives des proies spéciales.
func _progress() -> float:
	if _config.has("_free_level_progress"):
		return clampf(float(_config.get("_free_level_progress", 0.0)), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _special_chance_mult() -> float:
	return lerpf(clampf(_conf_f("special_chance_start_ratio", 0.3), 0.0, 1.0), 1.0, _progress())

## Fond d'arène dédié (figé — scroll 0), restauré à la fin du round.
func _begin_arena_background() -> void:
	var arenas_v: Variant = _config.get("arena_backgrounds", _cfg.get("arena_backgrounds", []))
	if not (arenas_v is Array) or (arenas_v as Array).is_empty():
		return
	var path: String = str((arenas_v as Array).pick_random())
	if path == "" or not ResourceLoader.exists(path):
		return
	if _game and is_instance_valid(_game) and _game.has_method("begin_wave_background_override"):
		_game.call("begin_wave_background_override", path, 0.4, 0.0)
		_arena_bg_active = true

func _end_arena_background() -> void:
	if not _arena_bg_active:
		return
	_arena_bg_active = false
	if _game and is_instance_valid(_game) and _game.has_method("end_wave_background_override"):
		_game.call("end_wave_background_override", 0.4)

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

## kind: "" = proie d'arène normale (roll des variantes) ; "toxic"/"golden"/
## "school"/"devourer_decoy" = types forcés. Les finals et les traversants
## (golden/school/devourer) gardent une trajectoire imposée ; les autres
## errent dans l'arène.
func _spawn_prey(value: float, is_final: bool, kind: String = "", spawn_at: Vector2 = Vector2.INF, vel: Vector2 = Vector2.ZERO) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(30.0, float(_cfg.get("prey_side_margin_px", 60.0)))

	var node := Node2D.new()
	node.name = "AbsorbFinal" if is_final else "AbsorbPrey"
	node.z_as_relative = false
	node.z_index = 10
	var prey_scale: float = _prey_scale_for_value(value, is_final)
	var size_px: float = maxf(24.0, float(_cfg.get("prey_base_size_px", 64.0)) * prey_scale)
	var traverse: bool = is_final or kind == "golden" or kind == "school" or kind == "devourer_decoy"
	var entry_vel: Vector2 = vel
	if spawn_at != Vector2.INF:
		node.position = spawn_at
	elif is_final or kind == "devourer_decoy":
		# Climax : entrée par le haut, traversée lente vers le bas (lisible).
		var final_x: float = viewport_size.x * (0.35 if kind == "devourer_decoy" else 0.5)
		node.position = Vector2(final_x, float(_cfg.get("prey_spawn_y", -70.0)) - size_px * 0.5)
		entry_vel = Vector2.DOWN * maxf(20.0, float(_cfg.get("final_descent_speed_px_sec", 70.0)))
	else:
		# Arène : entrée par un bord aléatoire, cap initial vers le centre.
		node.position = _random_edge_position(viewport_size, size_px)
		var aim: Vector2 = Vector2(
			randf_range(viewport_size.x * 0.25, viewport_size.x * 0.75),
			randf_range(viewport_size.y * 0.3, viewport_size.y * 0.7))
		entry_vel = (aim - node.position).normalized() * _drift_speed()
	var visual: Node2D = _build_prey_visual_for_kind(size_px, kind)
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
	# LA VALEUR DOIT ÊTRE VISIBLE : z absolu élevé (le z hérité du node — 10 —
	# passait sous d'autres éléments et masquait les chiffres).
	label.z_as_relative = false
	label.z_index = 40
	node.add_child(label)
	add_child(node)

	var entry: Dictionary = {
		"node": node,
		"label": label,
		"value": value,
		"base_value": value,
		"radius": size_px * 0.5,
		"base_radius": size_px * 0.5,
		"is_final": is_final,
		"vel": entry_vel,
		"wander_timer": randf_range(0.6, 2.0),
		"traverse": traverse,
		"kind": kind,
		"camo": false,
		"flee": false,
		"predator": false,
		"split": false,
		"stale": 0.0,
		"resync": 0.5
	}
	# Variantes roulées au spawn (chances PROGRESSIVES) — proies d'arène seules.
	if not traverse and kind == "":
		var mult: float = _special_chance_mult()
		if randf() < clampf(_conf_f("toxic_chance", 0.0) * mult, 0.0, 1.0):
			entry["kind"] = "toxic"
			var toxic_visual: Node2D = _build_prey_visual_for_kind(size_px, "toxic")
			visual.queue_free()
			node.add_child(toxic_visual)
			node.move_child(toxic_visual, 0)
		elif value >= _mass and randf() < clampf(_conf_f("predator_chance", 0.0) * mult, 0.0, 1.0):
			entry["predator"] = true
		else:
			entry["flee"] = randf() < clampf(_conf_f("flee_chance", 0.0) * mult, 0.0, 1.0)
		entry["camo"] = randf() < clampf(_conf_f("camo_chance", 0.0) * mult, 0.0, 1.0)
		entry["split"] = randf() < clampf(_conf_f("split_chance", 0.0) * mult, 0.0, 1.0)
	_prey.append(entry)
	_apply_prey_tint(entry)

func _random_edge_position(viewport_size: Vector2, size_px: float) -> Vector2:
	var half: float = size_px * 0.5
	match randi() % 4:
		0: # haut
			return Vector2(randf_range(60.0, viewport_size.x - 60.0), -half - 20.0)
		1: # bas
			return Vector2(randf_range(60.0, viewport_size.x - 60.0), viewport_size.y + half + 20.0)
		2: # gauche
			return Vector2(-half - 20.0, randf_range(80.0, viewport_size.y - 80.0))
		_: # droite
			return Vector2(viewport_size.x + half + 20.0, randf_range(80.0, viewport_size.y - 80.0))

func _drift_speed() -> float:
	return randf_range(maxf(5.0, _conf_f("prey_drift_speed_min", 20.0)),
		maxf(maxf(5.0, _conf_f("prey_drift_speed_min", 20.0)), _conf_f("prey_drift_speed_max", 45.0)))

func _has_eatable_prey_alive() -> bool:
	for entry in _prey:
		if not bool(entry.get("is_final", false)) and str(entry.get("kind", "")) != "toxic" \
			and _is_eatable(float(entry.get("value", 0.0))):
			return true
	return false

func _prey_scale_for_value(value: float, is_final: bool) -> float:
	var s: float = sqrt(maxf(1.0, value) / _start_mass)
	var s_min: float = maxf(0.2, float(_cfg.get("prey_scale_min", 0.5)))
	var s_max: float = maxf(s_min, float(_cfg.get("prey_scale_max", 2.6)))
	if is_final:
		s_max *= 1.4
	return clampf(s, s_min, s_max)

## Visuel selon le type : asset dédié (toxic/golden/predator/devourer) sinon
## pipeline standard.
func _build_prey_visual_for_kind(size_px: float, kind: String) -> Node2D:
	var dedicated_key: String = ""
	match kind:
		"toxic":
			dedicated_key = "toxic_prey_asset"
		"golden":
			dedicated_key = "golden_prey_asset"
		"devourer_decoy":
			dedicated_key = "devourer_asset"
		_:
			pass
	if dedicated_key != "":
		var dedicated: Node2D = _build_sprite_fit(str(_cfg.get(dedicated_key, "")), size_px)
		if dedicated != null:
			return dedicated
	return _build_prey_visual(size_px)

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

## Mangeable selon la masse courante — la surcharge (overcharge) élargit
## temporairement le seuil à masse × overcharge_ratio.
func _is_eatable(value: float) -> bool:
	var threshold: float = _mass
	if _overcharge_time > 0.0:
		threshold = _mass * maxf(1.0, _conf_f("overcharge_ratio", 1.5))
	return value < threshold

## Green = eatable, red = too big; refreshed after every absorption.
## Toxic = violet fixe (piège lisible), golden = doré fixe.
func _apply_prey_tint(entry: Dictionary) -> void:
	var kind: String = str(entry.get("kind", ""))
	var label_v: Variant = entry.get("label", null)
	var node_v: Variant = entry.get("node", null)
	if kind == "toxic":
		if label_v is Label and is_instance_valid(label_v):
			(label_v as Label).add_theme_color_override("font_color", Color(str(_cfg.get("color_toxic", "#B455E8"))))
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).modulate = Color(1.05, 0.85, 1.15)
		return
	if kind == "golden":
		if label_v is Label and is_instance_valid(label_v):
			(label_v as Label).add_theme_color_override("font_color", Color("#FFD866"))
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).modulate = Color(1.25, 1.1, 0.7)
		return
	var eatable: bool = _is_eatable(float(entry.get("value", 0.0)))
	var color: Color = Color(str(_cfg.get("color_eatable", "#3FBF6A"))) if eatable \
		else Color(str(_cfg.get("color_oversize", "#E8553B")))
	var label2_v: Variant = entry.get("label", null)
	if label2_v is Label and is_instance_valid(label2_v):
		(label2_v as Label).add_theme_color_override("font_color", color)
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
			# Cap d'arène : la file attend qu'une place se libère.
			if _spawn_timer <= 0.0 and not _values_queue.is_empty() \
				and _arena_prey_count() < maxi(3, int(_conf_f("max_active_prey", 12.0))):
				_spawn_timer = _spawn_interval
				_spawn_next_prey()
			_update_scheduler(dt)
			# Devourer time: reserve reached or every prey already dispatched.
			if _elapsed >= _duration - _final_reserve and _values_queue.is_empty():
				_begin_final()
		State.FINAL:
			pass

	_update_effects(dt)
	_update_prey(dt)
	_update_pickups(dt)
	_check_contacts()

	if _elapsed >= _duration:
		_finish()

func _arena_prey_count() -> int:
	var count: int = 0
	for entry in _prey:
		if not bool((entry as Dictionary).get("traverse", false)):
			count += 1
	return count

## Passage au climax : exode (les proies restantes fuient — dernière chance)
## et duel de Dévoreurs (un absorbable, un énorme leurre) sur chances.
func _begin_final() -> void:
	if randf() < clampf(_conf_f("exodus_chance", 0.0), 0.0, 1.0) and _arena_prey_count() > 0:
		var viewport_size: Vector2 = get_viewport_rect().size
		for entry in _prey:
			var prey_entry: Dictionary = entry as Dictionary
			if bool(prey_entry.get("traverse", false)):
				continue
			var node_v: Variant = prey_entry.get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				var away: Vector2 = ((node_v as Node2D).position - viewport_size * 0.5).normalized()
				if away == Vector2.ZERO:
					away = Vector2.UP
				prey_entry["vel"] = away * _drift_speed() * 4.0
				prey_entry["traverse"] = true # elles sortent (dernière chance)
		if VFXManager and _player and is_instance_valid(_player):
			VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -80.0),
				_translate_or("absorb_exodus", "EXODUS!"), Color("#FFB05C"), self)
	if randf() < clampf(_conf_f("dual_devourer_chance", 0.0), 0.0, 1.0):
		# Le leurre : un colosse ×2, jamais mangeable — lire la valeur.
		_spawn_prey(maxf(_final_value * 2.0, _mass * 2.0), false, "devourer_decoy")
	_spawn_prey(_final_value, true)
	_state = State.FINAL

## Effets temporisés + jeûne + combo.
func _update_effects(dt: float) -> void:
	_decoy_time = maxf(0.0, _decoy_time - dt)
	_freeze_time = maxf(0.0, _freeze_time - dt)
	_crystallize_time = maxf(0.0, _crystallize_time - dt)
	_repulse_time = maxf(0.0, _repulse_time - dt)
	_tide_time = maxf(0.0, _tide_time - dt)
	_combo_time = maxf(0.0, _combo_time - dt)
	if _overcharge_time > 0.0:
		_overcharge_time -= dt
		if _overcharge_time <= 0.0:
			_retint_all_prey()
	if _eclipse_time > 0.0:
		_eclipse_time -= dt
	if _mist_time > 0.0:
		_mist_time -= dt
		_update_mist_overlay()
		if _mist_time <= 0.0 and _mist_rect and is_instance_valid(_mist_rect):
			_mist_rect.queue_free()
			_mist_rect = null
	# Jeûne (Libre hauts levels) : la masse fond en continu, plancher start_mass.
	var fasting: float = maxf(0.0, _conf_f("fasting_mass_loss_ratio_per_sec", 0.0))
	if fasting > 0.0 and _mass > _start_mass:
		_mass = maxf(_start_mass, _mass - _mass * fasting * dt)
		if _player and is_instance_valid(_player) and _player.has_method("set_absorb_mass"):
			_player.call("set_absorb_mass", _mass)

## Arène statique : les proies ERRENT (wander + rebond doux aux bords) ; les
## traversants (final, dévoreur-leurre, dorée, banc, exode) suivent leur
## trajectoire et sortent. Poursuites : prédateur (oversize -> joueur),
## fuyardes (mangeables qui s'écartent), leurre (tout le monde converge),
## répulseur (les trop-gros sont repoussés), gel (dérive figée), marée (×mult).
func _update_prey(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(30.0, float(_cfg.get("prey_side_margin_px", 60.0)))
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	var tide_mult: float = maxf(1.0, _conf_f("tide_speed_mult", 2.5)) if _tide_time > 0.0 else 1.0
	var camo_radius: float = maxf(40.0, _conf_f("camo_reveal_radius_px", 170.0))
	var stale_delay: float = maxf(1.0, _conf_f("stale_delay_sec", 10.0))
	var stale_rate: float = maxf(0.0, _conf_f("stale_growth_ratio_per_sec", 0.02))
	for i in range(_prey.size() - 1, -1, -1):
		var entry: Dictionary = _prey[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_prey.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		var vel: Vector2 = entry.get("vel", Vector2.ZERO)
		var traverse: bool = bool(entry.get("traverse", false))
		if not traverse:
			# Comportement d'arène : cibles de dérive par priorité.
			var value: float = float(entry.get("value", 0.0))
			if _decoy_time > 0.0:
				vel = (_decoy_pos - node.position).normalized() * _drift_speed() * 2.0
			elif bool(entry.get("predator", false)) and value > _mass:
				vel = (player_pos - node.position).normalized() \
					* maxf(10.0, _conf_f("predator_speed_px_sec", 55.0))
			elif (bool(entry.get("flee", false)) or bool(entry.get("predator", false))) \
				and _is_eatable(value) and node.position.distance_to(player_pos) < maxf(60.0, _conf_f("flee_radius_px", 240.0)):
				vel = (node.position - player_pos).normalized() * _drift_speed() * 1.4
			else:
				entry["wander_timer"] = float(entry.get("wander_timer", 1.0)) - dt
				if float(entry["wander_timer"]) <= 0.0:
					entry["wander_timer"] = randf_range(
						maxf(0.3, _conf_f("prey_wander_interval_min_sec", 1.5)),
						maxf(0.4, _conf_f("prey_wander_interval_max_sec", 3.0)))
					vel = Vector2.from_angle(randf() * TAU) * _drift_speed()
			# Répulseur : les trop-gros proches sont repoussés du vaisseau.
			if _repulse_time > 0.0 and not _is_eatable(value) \
				and node.position.distance_to(player_pos) < maxf(60.0, _conf_f("repulse_radius_px", 220.0)):
				vel = (node.position - player_pos).normalized() * maxf(80.0, _conf_f("repulse_push_px_sec", 260.0))
			entry["vel"] = vel
			if _freeze_time <= 0.0:
				node.position += vel * tide_mult * dt
			# Rebond doux aux bords : les proies ne quittent jamais l'arène.
			var radius: float = float(entry.get("radius", 30.0))
			if node.position.x < margin and vel.x < 0.0:
				vel.x = absf(vel.x)
				entry["vel"] = vel
			elif node.position.x > viewport_size.x - margin and vel.x > 0.0:
				vel.x = -absf(vel.x)
				entry["vel"] = vel
			if node.position.y < 80.0 and vel.y < 0.0:
				vel.y = absf(vel.y)
				entry["vel"] = vel
			elif node.position.y > viewport_size.y - 60.0 and vel.y > 0.0:
				vel.y = -absf(vel.y)
				entry["vel"] = vel
			node.position = Vector2(
				clampf(node.position.x, -radius - 40.0, viewport_size.x + radius + 40.0),
				clampf(node.position.y, -radius - 40.0, viewport_size.y + radius + 40.0))
			# Croissance des retardataires : la proie grossit avec le temps.
			entry["stale"] = float(entry.get("stale", 0.0)) + dt
			if stale_rate > 0.0 and float(entry["stale"]) > stale_delay:
				entry["value"] = float(entry["value"]) * (1.0 + stale_rate * dt)
				entry["resync"] = float(entry.get("resync", 0.5)) - dt
				if float(entry["resync"]) <= 0.0:
					entry["resync"] = 0.5
					_resync_prey_size(entry)
		else:
			node.position += vel * dt
			# Traversants : sortis de l'écran = despawn (final -> fin de vague).
			var out_margin: float = float(entry.get("radius", 30.0)) + 80.0
			if node.position.y > viewport_size.y + out_margin or node.position.y < -out_margin \
				or node.position.x < -out_margin or node.position.x > viewport_size.x + out_margin:
				var was_final: bool = bool(entry.get("is_final", false))
				node.queue_free()
				_prey.remove_at(i)
				if was_final:
					_finish()
				continue
		# Lisibilité des valeurs : éclipse masque tout, camo = visible de près.
		var label_v: Variant = entry.get("label", null)
		if label_v is Label and is_instance_valid(label_v):
			var show_label: bool = _eclipse_time <= 0.0
			if show_label and bool(entry.get("camo", false)):
				show_label = node.position.distance_to(player_pos) <= camo_radius
			(label_v as Label).visible = show_label

## Resynchronise label + taille d'une proie dont la valeur a changé (croissance).
func _resync_prey_size(entry: Dictionary) -> void:
	var label_v: Variant = entry.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).text = str(int(round(float(entry.get("value", 1.0)))))
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var growth: float = clampf(sqrt(float(entry.get("value", 1.0)) / maxf(1.0, float(entry.get("base_value", 1.0)))), 1.0, 1.8)
		(node_v as Node2D).scale = Vector2.ONE * growth
		entry["radius"] = float(entry.get("base_radius", 30.0)) * growth
	_apply_prey_tint(entry)

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
		if _is_eatable(float(entry.get("value", 0.0))):
			_absorb_prey(i, entry)
		else:
			_oversize_contact(entry)

func _absorb_prey(index: int, entry: Dictionary) -> void:
	var value: float = float(entry.get("value", 0.0))
	var was_final: bool = bool(entry.get("is_final", false))
	var kind: String = str(entry.get("kind", ""))
	var node_v: Variant = entry.get("node", null)
	var at_pos: Vector2 = _player.global_position
	if node_v is Node2D and is_instance_valid(node_v):
		at_pos = (node_v as Node2D).global_position
		(node_v as Node2D).queue_free()
	_prey.remove_at(index)
	# Toxique : le piège — absorbable mais la masse FOND (jamais sous start_mass).
	if kind == "toxic":
		_mass = maxf(_start_mass, _mass - value)
		if _player.has_method("set_absorb_mass"):
			_player.call("set_absorb_mass", _mass)
		if VFXManager:
			VFXManager.flash_sprite(_player, Color(0.85, 0.5, 1.0), 0.15)
		_retint_all_prey()
		return
	# Combo de gloutonnerie : N absorptions dans la fenêtre = gains ×mult.
	_absorb_times.append(_time)
	var window: float = maxf(0.5, _conf_f("combo_window_sec", 3.0))
	while not _absorb_times.is_empty() and _time - float(_absorb_times[0]) > window:
		_absorb_times.pop_front()
	if _combo_time <= 0.0 and _absorb_times.size() >= maxi(2, int(_conf_f("combo_hits", 5.0))):
		_combo_time = maxf(1.0, _conf_f("combo_duration_sec", 5.0))
		if VFXManager:
			VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -90.0),
				_translate_or("absorb_combo", "FEAST x2!"), Color("#FFD866"), self)
	var gain: float = value * (maxf(1.0, _conf_f("combo_mult", 2.0)) if _combo_time > 0.0 else 1.0)
	_mass += gain
	if _player.has_method("set_absorb_mass"):
		_player.call("set_absorb_mass", _mass)
	if VFXManager and _player.has_method("get_gate_runner_scale"):
		VFXManager.flash_sprite(_player, Color(1.0, 0.9, 0.4) if _combo_time > 0.0 else Color(0.55, 1.0, 0.6), 0.12)
	# Fractionnée : libère des minis sur place (le gain de la grosse est acquis).
	if bool(entry.get("split", false)):
		var split_count: int = randi_range(maxi(1, int(_conf_f("split_count_min", 2.0))), maxi(1, int(_conf_f("split_count_max", 3.0))))
		var fraction: float = clampf(_conf_f("split_fraction", 0.25), 0.05, 0.6)
		for s in range(split_count):
			var mini_value: float = maxf(1.0, round(value * fraction))
			var offset := Vector2.from_angle(randf() * TAU) * 60.0
			_spawn_prey(mini_value, false, "", at_pos + offset,
				Vector2.from_angle(randf() * TAU) * _drift_speed())
	_retint_all_prey()
	if _game and is_instance_valid(_game):
		if was_final:
			# Jackpot: the Devourer is swallowed, the wave ends early.
			if _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(0, int(_cfg.get("final_crystals", 8))))
			_finish()
			return
		if kind == "golden":
			# Proie dorée : cristaux GARANTIS en plus de la masse.
			if _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(1, int(_conf_f("golden_crystals", 4.0))))
			if VFXManager:
				VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -60.0),
					_translate_or("absorb_golden", "GOLDEN PREY!"), Color("#FFD866"), self)
			return
		# Cristallisation : garanti pendant l'effet, sinon la chance standard.
		var chance: float = 1.0 if _crystallize_time > 0.0 \
			else clampf(float(_cfg.get("crystal_absorb_chance", 0.3)), 0.0, 1.0)
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
# SCHEDULER ALTERNÉ PICKUPS <-> ÉVÉNEMENTS (anti-répétition par famille)
# =============================================================================

func _update_scheduler(dt: float) -> void:
	_sched_timer -= dt
	if _sched_timer > 0.0:
		return
	var cd_min: float = maxf(1.0, _conf_f("absorb_event_cd_min_sec", 12.0))
	_sched_timer = randf_range(cd_min, maxf(cd_min, _conf_f("absorb_event_cd_max_sec", 24.0)))
	if _next_family_pickup:
		var pickup_id: String = _pick_weighted(_config.get("absorb_pickups_weights",
			_cfg.get("absorb_pickups_weights", {})),
			{"decoy": 20, "freeze": 20, "overcharge": 20, "crystallize": 20, "repulse": 20}, _last_pickup)
		if pickup_id != "":
			_last_pickup = pickup_id
			_spawn_pickup(pickup_id)
	else:
		var event_id: String = _pick_weighted(_config.get("absorb_events_weights",
			_cfg.get("absorb_events_weights", {})),
			{"school": 22, "tide": 22, "eclipse": 18, "golden": 20, "mist": 18}, _last_event)
		if event_id != "":
			_last_event = event_id
			_execute_event(event_id)
	_next_family_pickup = not _next_family_pickup

## Tirage pondéré générique avec anti-répétition (le dernier id est exclu).
func _pick_weighted(weights_v: Variant, defaults: Dictionary, exclude: String) -> String:
	var weights: Dictionary = (weights_v as Dictionary).duplicate() if weights_v is Dictionary and not (weights_v as Dictionary).is_empty() \
		else defaults.duplicate()
	weights.erase(exclude)
	var total: float = 0.0
	for key in weights.keys():
		total += maxf(0.0, float(weights[key]))
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	for key in weights.keys():
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return str(key)
	return ""

# --- Pickups (orbes flottants collectés au contact du vaisseau) ---

const PICKUP_TINTS: Dictionary = {
	"decoy": "#FF8AD8", "freeze": "#8FD3FF", "overcharge": "#FFD866",
	"crystallize": "#7FE8C8", "repulse": "#C77CFF"
}
const PICKUP_GLYPHS: Dictionary = {
	"decoy": "L", "freeze": "G", "overcharge": "S", "crystallize": "C", "repulse": "R"
}

func _spawn_pickup(pickup_id: String) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var node := Node2D.new()
	node.name = "AbsorbPickup"
	node.z_as_relative = false
	node.z_index = 12
	var visual: Node2D = _build_sprite_fit(str(_cfg.get(pickup_id + "_pickup_asset", "")), 44.0)
	if visual == null:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(18):
			var a: float = TAU * float(i) / 18.0
			pts.append(Vector2(cos(a), sin(a)) * 22.0)
		circle.polygon = pts
		circle.color = Color(str(PICKUP_TINTS.get(pickup_id, "#8FD3FF")))
		node.add_child(circle)
		var label := Label.new()
		label.text = str(PICKUP_GLYPHS.get(pickup_id, "?"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 4)
		label.size = Vector2(44, 44)
		label.position = Vector2(-22, -22)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(label)
	else:
		node.add_child(visual)
	node.position = Vector2(
		randf_range(viewport_size.x * 0.18, viewport_size.x * 0.82),
		randf_range(viewport_size.y * 0.25, viewport_size.y * 0.75))
	add_child(node)
	_pickups.append({
		"node": node,
		"pos": node.position,
		"vel": Vector2.from_angle(randf() * TAU) * 14.0,
		"id": pickup_id,
		"despawn": maxf(3.0, _conf_f("pickup_despawn_sec", 12.0))
	})

func _update_pickups(dt: float) -> void:
	if _pickups.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else Vector2(-9999, -9999)
	var player_scale: float = 1.0
	if _player and is_instance_valid(_player) and _player.has_method("get_gate_runner_scale"):
		player_scale = maxf(0.1, float(_player.call("get_gate_runner_scale")))
	var player_radius: float = maxf(10.0, float(_cfg.get("contact_radius_base_px", 40.0))) * player_scale
	for i in range(_pickups.size() - 1, -1, -1):
		var pickup: Dictionary = _pickups[i]
		var node_v: Variant = pickup.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		pickup["despawn"] = float(pickup.get("despawn", 0.0)) - dt
		var pos: Vector2 = (pickup.get("pos", Vector2.ZERO) as Vector2) + (pickup.get("vel", Vector2.ZERO) as Vector2) * dt
		pos.x = clampf(pos.x, 40.0, viewport_size.x - 40.0)
		pos.y = clampf(pos.y, 80.0, viewport_size.y - 60.0)
		pickup["pos"] = pos
		node.position = pos
		node.scale = Vector2.ONE * (1.0 + 0.1 * sin(_time * 5.0))
		if float(pickup["despawn"]) < 2.0:
			node.modulate.a = 0.4 + 0.6 * absf(sin(_time * 9.0))
		if pos.distance_to(player_pos) <= player_radius + 26.0:
			var pickup_id: String = str(pickup.get("id", ""))
			node.queue_free()
			_pickups.remove_at(i)
			_apply_pickup(pickup_id, pos)
			continue
		if float(pickup["despawn"]) <= 0.0:
			node.queue_free()
			_pickups.remove_at(i)

func _apply_pickup(pickup_id: String, at_pos: Vector2) -> void:
	match pickup_id:
		"decoy":
			_decoy_time = maxf(1.0, _conf_f("decoy_duration_sec", 4.0))
			_decoy_pos = at_pos
		"freeze":
			_freeze_time = maxf(0.5, _conf_f("freeze_duration_sec", 3.0))
		"overcharge":
			_overcharge_time = maxf(1.0, _conf_f("overcharge_duration_sec", 4.0))
			_retint_all_prey() # le seuil mangeable vient de changer
		"crystallize":
			_crystallize_time = maxf(1.0, _conf_f("crystallize_duration_sec", 6.0))
		"repulse":
			_repulse_time = maxf(1.0, _conf_f("repulse_duration_sec", 5.0))
		_:
			pass
	if VFXManager:
		VFXManager.spawn_impact(at_pos, 18.0, self)

# --- Événements ---

func _execute_event(event_id: String) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	match event_id:
		"school":
			# Banc de poissons : file de minis traversant l'arène (elles sortent).
			var count: int = randi_range(maxi(2, int(_conf_f("school_count_min", 8.0))), maxi(3, int(_conf_f("school_count_max", 12.0))))
			var from_left: bool = randf() < 0.5
			var y: float = randf_range(viewport_size.y * 0.25, viewport_size.y * 0.75)
			var speed: float = maxf(60.0, _conf_f("school_speed_px_sec", 150.0))
			var mini_value: float = maxf(1.0, round(_mass * 0.02))
			for s in range(count):
				var x: float = (-40.0 - float(s) * 56.0) if from_left else (viewport_size.x + 40.0 + float(s) * 56.0)
				_spawn_prey(mini_value, false, "school",
					Vector2(x, y + sin(float(s) * 0.9) * 40.0),
					Vector2(speed if from_left else -speed, 0.0))
		"tide":
			_tide_time = maxf(1.0, _conf_f("tide_duration_sec", 5.0))
			_show_event_float("absorb_tide", "TIDE!", Color("#8FD3FF"))
		"eclipse":
			_eclipse_time = maxf(1.0, _conf_f("eclipse_duration_sec", 6.0))
			_show_event_float("absorb_eclipse", "ECLIPSE!", Color("#B48CFF"))
		"golden":
			# Proie dorée : géante rapide traversante, TOUJOURS mangeable.
			var golden_value: float = maxf(1.0, round(_mass * clampf(_conf_f("golden_value_ratio", 0.6), 0.05, 0.95)))
			var golden_left: bool = randf() < 0.5
			var golden_speed: float = maxf(120.0, _conf_f("golden_speed_px_sec", 350.0))
			_spawn_prey(golden_value, false, "golden",
				Vector2(-80.0 if golden_left else viewport_size.x + 80.0,
					randf_range(viewport_size.y * 0.3, viewport_size.y * 0.7)),
				Vector2(golden_speed if golden_left else -golden_speed, 0.0))
			_show_event_float("absorb_golden", "GOLDEN PREY!", Color("#FFD866"))
		"mist":
			_mist_time = maxf(1.0, _conf_f("mist_duration_sec", 6.0))
			_ensure_mist_overlay()
			_show_event_float("absorb_mist", "MIST!", Color("#9AA8BF"))
		_:
			pass

func _show_event_float(locale_key: String, fallback: String, color: Color) -> void:
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -80.0),
			_translate_or(locale_key, fallback), color, self)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Brume : pénombre percée d'un halo autour du vaisseau (shader pong_blackout,
## une seule lumière). Fallback sans shader : dim léger.
func _ensure_mist_overlay() -> void:
	if _mist_rect and is_instance_valid(_mist_rect):
		return
	_mist_rect = ColorRect.new()
	_mist_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mist_rect.z_as_relative = false
	_mist_rect.z_index = 45
	_mist_rect.position = Vector2.ZERO
	_mist_rect.size = get_viewport_rect().size
	if ResourceLoader.exists(MIST_SHADER_PATH):
		var shader: Shader = load(MIST_SHADER_PATH) as Shader
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_mist_rect.material = mat
	if _mist_rect.material == null:
		_mist_rect.color = Color(0.0, 0.0, 0.0, 0.45)
	add_child(_mist_rect)

func _update_mist_overlay() -> void:
	if _mist_rect == null or not is_instance_valid(_mist_rect):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_mist_rect.size = viewport_size
	var mat: ShaderMaterial = _mist_rect.material as ShaderMaterial
	if mat == null:
		return
	var fade: float = clampf(minf(_mist_time, 0.5) / 0.5, 0.0, 1.0)
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	positions.append(player_pos)
	radii.append(maxf(80.0, _conf_f("mist_light_radius_px", 220.0)))
	while positions.size() < 16:
		positions.append(Vector2(-9999.0, -9999.0))
		radii.append(1.0)
	mat.set_shader_parameter("darkness", clampf(_conf_f("mist_opacity", 0.8), 0.0, 1.0) * fade)
	mat.set_shader_parameter("viewport_size", viewport_size)
	mat.set_shader_parameter("light_count", 1)
	mat.set_shader_parameter("light_pos", positions)
	mat.set_shader_parameter("light_radius", radii)

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
	# Restore the player and the arena background BEFORE notifying the chain.
	_end_arena_background()
	_restore_player_mode()
	finished.emit()
	queue_free() # prey ships, pickups and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_end_arena_background()
		_restore_player_mode()
