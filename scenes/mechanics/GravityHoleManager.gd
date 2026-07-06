extends Node2D

## GravityHoleManager — Orchestre une vague "gravity_hole" (inspiration
## Hole.io) : le vaisseau devient un champ gravitationnel mobile qui absorbe
## les props de decor plus petits que sa masse. Champ derivant : les props
## entrent lentement par les 4 bords et traversent l'ecran. La bascule de
## background (niveau -> dimension gravitationnelle, aleatoire dans bg_assets)
## est masquee par une aura noire/constellation qui couvre l'ecran puis shrink
## sur le vaisseau ou elle reste en aura persistante — choregraphie inverse a
## la fin. Objectifs v1 : timer + noyau final (masse suffisante = pluie de
## cristaux + fin anticipee). Tir coupe, mouvement libre TOUTES directions
## (zone interdite du haut levee par le mode joueur). Contacts par distance,
## pas de physics engine ; pas de drops d'equipement (score/cristaux only).

signal finished

enum State { INTRO, RUN, FINAL, OUTRO, DONE }
enum PropState { DRIFT, ABSORBING }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _obstacle_skins: Array = [] # world skin fallback for prop visuals

var _state: int = State.INTRO
var _time: float = 0.0
var _run_duration: float = 40.0
var _run_elapsed: float = 0.0
var _final_reserve: float = 8.0
var _reward_mult: float = 1.0

# Vortex mass/radius (owned here, pushed to Player for label + aura scale).
var _mass: float = 10.0
var _start_mass: float = 10.0
var _radius: float = 42.0

# Drift field. Entries: { "node": Node2D, "label": Label|null,
# "required_mass": float, "mass_gain": float, "radius_px": float,
# "velocity": Vector2, "rot_speed": float, "state": PropState,
# "absorb_t": float, "absorb_sec": float, "start_scale": Vector2,
# "type_tint": Color, "score_base": int, "crystal_chance": float,
# "is_final": bool, "seen_on_screen": bool, "near": bool }
var _props: Array = []
var _spawn_timer: float = 0.0
var _oversize_cooldown: float = 0.0
var _solvability_timer: float = 0.0
var _no_target_timer: float = 0.0
var _total_gain_offered: float = 0.0
var _final_spawned: bool = false

# Transition (intro/outro cover) state.
var _chosen_bg: String = ""
var _transition_sprite: AnimatedSprite2D = null
var _transition_tween: Tween = null
var _transition_follow: bool = false
var _outro_started: bool = false

var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("gravity_hole") if DataManager else {}
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []

	_run_duration = maxf(10.0, float(_get_conf("duration", _get_conf("duration_sec_default", 40.0))))
	_final_reserve = clampf(float(_get_conf("final_reserve_sec", 8.0)), 3.0, _run_duration * 0.5)
	_start_mass = maxf(1.0, float(_get_conf("start_mass", 10.0)))
	_mass = _start_mass
	_radius = _compute_radius()
	_reward_mult = maxf(0.05, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	var bgs_v: Variant = _get_conf("bg_assets", [])
	if bgs_v is Array and not (bgs_v as Array).is_empty():
		var bgs: Array = bgs_v as Array
		_chosen_bg = str(bgs[randi() % bgs.size()])

	_ensure_countdown_label()
	# countdown_hidden (mode libre) : le label n'est jamais créé — guard.
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = false
	_begin_intro()
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_gravity_hole"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_gravity_hole", merged)
		_push_player_state()

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_gravity_hole"):
		_player.call("end_gravity_hole")

func _push_player_state() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_gravity_hole_mass"):
		_player.call("set_gravity_hole_mass", _mass)
	if _player.has_method("set_gravity_hole_radius"):
		_player.call("set_gravity_hole_radius", _radius)

func _compute_radius() -> float:
	var base: float = maxf(10.0, float(_get_conf("absorption_radius_base_px", 42.0)))
	var growth: float = maxf(0.0, float(_get_conf("absorption_radius_growth", 6.0)))
	var cap: float = maxf(base, float(_get_conf("absorption_radius_max_px", 150.0)))
	return minf(base + sqrt(maxf(0.0, _mass)) * growth, cap)

# =============================================================================
# TRANSITION (black constellation cover: intro = engulf then shrink onto the
# ship; outro = grow from the ship, restore under full cover, leave). The
# sprite is a manager child so queue_free() always cleans it up.
# =============================================================================

static var _resource_cache: Dictionary = {}

static func _load_cached_resource(path: String) -> Resource:
	if path == "" :
		return null
	if _resource_cache.has(path):
		return _resource_cache[path]
	if not ResourceLoader.exists(path):
		_resource_cache[path] = null
		return null
	var res: Resource = load(path)
	_resource_cache[path] = res
	return res

func _frames_max_dim(frames: SpriteFrames) -> float:
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
		var tex: Texture2D = frames.get_frame_texture(anim_name, 0)
		if tex:
			var s: Vector2 = tex.get_size()
			return maxf(1.0, maxf(s.x, s.y))
	return 1.0

func _make_transition_sprite() -> AnimatedSprite2D:
	var res: Resource = _load_cached_resource(str(_get_conf("transition_asset", "")))
	if not (res is SpriteFrames):
		return null
	var frames: SpriteFrames = res as SpriteFrames
	var sprite := AnimatedSprite2D.new()
	sprite.name = "GravityTransition"
	sprite.sprite_frames = frames
	var anim_name: StringName = &"default"
	if not frames.has_animation(anim_name):
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0:
			anim_name = StringName(names[0])
	if frames.has_animation(anim_name):
		sprite.play(anim_name)
	sprite.z_as_relative = false
	sprite.z_index = 95 # above gameplay/labels, below the HUD CanvasLayer
	add_child(sprite)
	return sprite

func _transition_scale_for_px(diameter_px: float) -> float:
	if _transition_sprite == null or _transition_sprite.sprite_frames == null:
		return 1.0
	return diameter_px / _frames_max_dim(_transition_sprite.sprite_frames)

func _aura_diameter_px() -> float:
	return _radius * 2.0 * maxf(0.2, float(_get_conf("aura_visual_ratio", 1.08)))

func _kill_transition_tween() -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null

func _begin_intro() -> void:
	_state = State.INTRO
	_transition_sprite = _make_transition_sprite()
	if _transition_sprite == null:
		# No transition asset: hard swap, still fully functional.
		_on_intro_cover()
		_on_intro_handoff()
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var enter_sec: float = maxf(0.1, float(_get_conf("transition_enter_sec", 0.9)))
	var hold_sec: float = maxf(0.05, float(_get_conf("transition_hold_sec", 0.25)))
	var shrink_sec: float = maxf(0.1, float(_get_conf("transition_shrink_sec", 0.8)))
	var cover_scale: float = _transition_scale_for_px(
		viewport_size.length() * maxf(0.5, float(_get_conf("transition_cover_diagonal_ratio", 1.15))))
	_transition_sprite.position = Vector2(-80.0, -80.0)
	_transition_sprite.scale = Vector2.ONE * _transition_scale_for_px(maxf(8.0, float(_get_conf("transition_start_px", 90.0))))
	var cover_tint := Color(str(_get_conf("transition_tint", "#150E28F0")))
	_transition_sprite.modulate = Color(cover_tint.r, cover_tint.g, cover_tint.b, 0.0)
	_kill_transition_tween()
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_sprite, "modulate:a", cover_tint.a, 0.2)
	_transition_tween.tween_property(_transition_sprite, "position", viewport_size * 0.5, enter_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_sprite, "scale", Vector2.ONE * cover_scale, enter_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.set_parallel(false)
	_transition_tween.tween_callback(_on_intro_cover)
	_transition_tween.tween_interval(hold_sec)
	_transition_tween.tween_callback(func() -> void: _transition_follow = true)
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_sprite, "scale", Vector2.ONE * _transition_scale_for_px(_aura_diameter_px()), shrink_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(_transition_sprite, "modulate", Color(str(_get_conf("aura_tint", "#2A1848C8"))), shrink_sec)
	_transition_tween.set_parallel(false)
	_transition_tween.tween_callback(_on_intro_handoff)

## Under full cover: swap the background and enter the player mode (aura still
## hidden — the cover sprite IS the vortex for now).
func _on_intro_cover() -> void:
	if _game and is_instance_valid(_game) and _chosen_bg != "" and _game.has_method("begin_wave_background_override"):
		_game.call("begin_wave_background_override", _chosen_bg,
			0.0, float(_get_conf("bg_scroll_speed_px_sec", 14.0)))
	_begin_player_mode()

func _on_intro_handoff() -> void:
	_transition_follow = false
	if _player and is_instance_valid(_player) and _player.has_method("set_gravity_hole_aura_visible"):
		var sync_frame: int = _transition_sprite.frame if (_transition_sprite and is_instance_valid(_transition_sprite)) else -1
		_player.call("set_gravity_hole_aura_visible", true, sync_frame)
	if _transition_sprite and is_instance_valid(_transition_sprite):
		_transition_sprite.queue_free()
	_transition_sprite = null
	_state = State.RUN
	_run_elapsed = 0.0
	_spawn_timer = 0.2
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = true

func _begin_outro() -> void:
	if _outro_started or _state == State.DONE:
		return
	_outro_started = true
	_state = State.OUTRO
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = false
	_transition_sprite = _make_transition_sprite()
	if _transition_sprite == null:
		_on_outro_cover()
		_finish()
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var enter_sec: float = maxf(0.1, float(_get_conf("transition_enter_sec", 0.9)))
	var hold_sec: float = maxf(0.05, float(_get_conf("transition_hold_sec", 0.25)))
	var shrink_sec: float = maxf(0.1, float(_get_conf("transition_shrink_sec", 0.8)))
	var cover_scale: float = _transition_scale_for_px(
		viewport_size.length() * maxf(0.5, float(_get_conf("transition_cover_diagonal_ratio", 1.15))))
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	_transition_sprite.position = player_pos
	_transition_sprite.scale = Vector2.ONE * _transition_scale_for_px(_aura_diameter_px())
	_transition_sprite.modulate = Color(str(_get_conf("aura_tint", "#2A1848C8")))
	if _player and is_instance_valid(_player) and _player.has_method("set_gravity_hole_aura_visible"):
		_player.call("set_gravity_hole_aura_visible", false)
	_transition_follow = true
	_kill_transition_tween()
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_sprite, "scale", Vector2.ONE * cover_scale, shrink_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_sprite, "modulate", Color(str(_get_conf("transition_tint", "#150E28F0"))), shrink_sec)
	_transition_tween.set_parallel(false)
	_transition_tween.tween_callback(_on_outro_cover)
	_transition_tween.tween_interval(hold_sec)
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(_transition_sprite, "position", Vector2(-80.0, -80.0), enter_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(_transition_sprite, "scale", Vector2.ONE * _transition_scale_for_px(maxf(8.0, float(_get_conf("transition_start_px", 90.0)))), enter_sec)
	_transition_tween.tween_property(_transition_sprite, "modulate:a", 0.0, enter_sec)
	_transition_tween.set_parallel(false)
	_transition_tween.tween_callback(_finish)

## Under full cover: restore the level background and the player, clear the
## remaining props while nobody can see it.
func _on_outro_cover() -> void:
	_transition_follow = false
	if _game and is_instance_valid(_game) and _game.has_method("end_wave_background_override"):
		_game.call("end_wave_background_override", 0.0)
	_restore_player_mode()
	for entry in _props:
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_props.clear()

# =============================================================================
# PROPS (drift field)
# =============================================================================

func _pick_prop_type() -> Dictionary:
	var types_v: Variant = _get_conf("props", [])
	if not (types_v is Array) or (types_v as Array).is_empty():
		return {}
	var types: Array = types_v as Array
	var weights_override: Dictionary = {}
	var wo_v: Variant = _config.get("prop_weights", {})
	if wo_v is Dictionary:
		weights_override = wo_v as Dictionary
	var total: float = 0.0
	var weights: Array = []
	for t_v in types:
		var t: Dictionary = t_v as Dictionary
		var w: float = maxf(0.0, float(weights_override.get(str(t.get("id", "")), t.get("weight", 1.0))))
		weights.append(w)
		total += w
	if total <= 0.0:
		return types[0] as Dictionary
	var roll: float = randf() * total
	for i in range(types.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			return types[i] as Dictionary
	return types[types.size() - 1] as Dictionary

## Weighted edge pick: 0 top, 1 bottom, 2 left, 3 right.
func _pick_edge() -> int:
	var ew_v: Variant = _get_conf("edge_weights", {})
	var ew: Dictionary = (ew_v as Dictionary) if ew_v is Dictionary else {}
	var names: Array = ["top", "bottom", "left", "right"]
	var total: float = 0.0
	var weights: Array = []
	for n in names:
		var w: float = maxf(0.0, float(ew.get(n, 0.25)))
		weights.append(w)
		total += w
	if total <= 0.0:
		return 0
	var roll: float = randf() * total
	for i in range(4):
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return 3

func _spawn_prop(force_absorbable: bool = false, forced_edge: int = -1) -> void:
	var type: Dictionary = _pick_prop_type()
	if type.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var size_px: float = maxf(16.0, float(type.get("size_px", 56.0)))
	var required: float = maxf(1.0, round(_mass * randf_range(
		float(type.get("mass_ratio_min", 0.3)), float(type.get("mass_ratio_max", 0.6)))))
	if force_absorbable:
		required = maxf(1.0, round(_mass * clampf(float(_get_conf("eatable_rescue_ratio", 0.55)), 0.1, 0.9)))
	var mass_gain: float = maxf(1.0, round(required * maxf(0.05, float(type.get("mass_gain_ratio", 0.6)))))
	if required <= _mass:
		_total_gain_offered += mass_gain

	var edge: int = forced_edge if forced_edge >= 0 else _pick_edge()
	var offset: float = size_px * 0.5 + maxf(0.0, float(_get_conf("spawn_margin_px", 26.0)))
	var pos: Vector2
	match edge:
		0: pos = Vector2(randf_range(0.0, viewport_size.x), -offset)
		1: pos = Vector2(randf_range(0.0, viewport_size.x), viewport_size.y + offset)
		2: pos = Vector2(-offset, randf_range(0.0, viewport_size.y))
		_: pos = Vector2(viewport_size.x + offset, randf_range(0.0, viewport_size.y))
	var inset: float = clampf(float(_get_conf("aim_center_inset_ratio", 0.25)), 0.0, 0.45)
	var aim := Vector2(
		randf_range(viewport_size.x * inset, viewport_size.x * (1.0 - inset)),
		randf_range(viewport_size.y * inset, viewport_size.y * (1.0 - inset)))
	var speed: float = randf_range(
		maxf(5.0, float(_get_conf("drift_speed_min_px_sec", 28.0))),
		maxf(6.0, float(_get_conf("drift_speed_max_px_sec", 70.0))))

	var node := Node2D.new()
	node.name = "GravityProp"
	node.z_as_relative = false
	node.z_index = 10
	node.position = pos
	var type_tint := Color(str(type.get("tint", "#FFFFFF")))
	var visual: Node2D = _build_prop_visual(type, size_px)
	node.add_child(visual)
	add_child(node)

	var entry: Dictionary = {
		"node": node,
		"label": null,
		"required_mass": required,
		"mass_gain": mass_gain,
		"radius_px": size_px * 0.5,
		"velocity": (aim - pos).normalized() * speed,
		"rot_speed": deg_to_rad(randf_range(-1.0, 1.0) * maxf(0.0, float(_get_conf("rotation_speed_deg_max", 25.0)))),
		"state": PropState.DRIFT,
		"absorb_t": 0.0,
		"absorb_sec": 0.2,
		"start_scale": node.scale,
		"type_tint": type_tint,
		"score_base": int(type.get("score_base", 15)),
		"crystal_chance": clampf(float(type.get("crystal_chance", 0.1)), 0.0, 1.0),
		"is_final": false,
		"seen_on_screen": false,
		"near": false
	}
	if bool(_get_conf("prop_labels_enabled", false)):
		entry["label"] = _attach_value_label(node, required, size_px, int(_get_conf("value_label_font_size", 20)))
	_props.append(entry)
	_apply_prop_tint(entry)

## The final core: a huge, slow, top-center descending structure. Its required
## mass derives from the total mass offered during the run (density-agnostic).
func _spawn_final_core() -> void:
	_final_spawned = true
	var viewport_size: Vector2 = get_viewport_rect().size
	var size_px: float = maxf(60.0, float(_get_conf("final_core_size_px", 200.0)))
	var efficiency: float = clampf(float(_get_conf("final_core_efficiency_ratio", 0.55)), 0.05, 1.0)
	var margin: float = clampf(float(_get_conf("final_core_margin_ratio", 0.1)), 0.0, 0.9)
	var required: float = maxf(_start_mass * 2.0, round((_start_mass + _total_gain_offered * efficiency) * (1.0 - margin)))

	var node := Node2D.new()
	node.name = "GravityFinalCore"
	node.z_as_relative = false
	node.z_index = 12
	node.position = Vector2(viewport_size.x * 0.5, -size_px * 0.5 - 20.0)
	var core_type: Dictionary = {
		"assets": _get_conf("final_core_assets", []),
		"tint": str(_get_conf("final_core_tint", "#B455E8"))
	}
	var visual: Node2D = _build_prop_visual(core_type, size_px)
	node.add_child(visual)
	add_child(node)

	var entry: Dictionary = {
		"node": node,
		"label": _attach_value_label(node, required, size_px, maxi(28, int(_get_conf("value_label_font_size", 20)) + 14)),
		"required_mass": required,
		"mass_gain": maxf(1.0, round(required * 0.5)),
		"radius_px": size_px * 0.5,
		"velocity": Vector2(0.0, maxf(15.0, float(_get_conf("final_core_speed_px_sec", 55.0)))),
		"rot_speed": deg_to_rad(8.0),
		"state": PropState.DRIFT,
		"absorb_t": 0.0,
		"absorb_sec": 0.35,
		"start_scale": node.scale,
		"type_tint": Color(str(_get_conf("final_core_tint", "#B455E8"))),
		"score_base": 0,
		"crystal_chance": 0.0,
		"is_final": true,
		"seen_on_screen": false,
		"near": false
	}
	_props.append(entry)
	_apply_prop_tint(entry)

func _attach_value_label(node: Node2D, value: float, size_px: float, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(10, font_size))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(int(round(value)))
	label.size = Vector2(160.0, 40.0)
	label.position = Vector2(-80.0, -size_px * 0.5 - 40.0)
	node.add_child(label)
	return label

## Prop visual priority: type assets > per-wave prop_assets override > world
## obstacle skins > flat polygon circle.
func _build_prop_visual(type: Dictionary, size_px: float) -> Node2D:
	var asset_path: String = ""
	var type_assets_v: Variant = type.get("assets", [])
	if type_assets_v is Array and not (type_assets_v as Array).is_empty():
		var arr: Array = type_assets_v as Array
		asset_path = str(arr[randi() % arr.size()])
	if asset_path == "":
		var wave_assets_v: Variant = _config.get("prop_assets", [])
		if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
			var warr: Array = wave_assets_v as Array
			asset_path = str(warr[randi() % warr.size()])
	if asset_path == "" and not _obstacle_skins.is_empty():
		asset_path = str(_obstacle_skins[randi() % _obstacle_skins.size()])
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
	var res: Resource = _load_cached_resource(asset_path)
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

## Readability: turquoise = absorbable, red = too big, yellow (pulsed in
## _update_props) = close to absorbable. Blended over the type tint so the
## prop sprite stays recognizable.
func _apply_prop_tint(entry: Dictionary) -> void:
	var node_v: Variant = entry.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var required: float = float(entry.get("required_mass", 0.0))
	var absorbable: bool = required <= _mass
	var near: bool = (not absorbable) \
		and required - _mass <= _mass * maxf(0.0, float(_get_conf("near_mass_margin_ratio", 0.2)))
	entry["near"] = near
	var type_tint: Color = entry.get("type_tint", Color.WHITE)
	var state_color: Color
	if absorbable:
		state_color = Color(str(_get_conf("color_absorbable", "#4FD8C8")))
	elif near:
		state_color = Color(str(_get_conf("color_near", "#F2E45B")))
	else:
		state_color = Color(str(_get_conf("color_oversize", "#E8553B")))
	(node_v as Node2D).modulate = type_tint * Color.WHITE.lerp(state_color, 0.6)
	var label_v: Variant = entry.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).add_theme_color_override("font_color", state_color)

func _retint_all_props() -> void:
	for entry in _props:
		_apply_prop_tint(entry)

# =============================================================================
# RUN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		set_process(false)
		return
	var dt: float = minf(delta, 0.1)
	_time += dt
	_oversize_cooldown = maxf(0.0, _oversize_cooldown - dt)

	if _transition_follow and _transition_sprite and is_instance_valid(_transition_sprite):
		_transition_sprite.global_position = _player.global_position

	match _state:
		State.INTRO, State.OUTRO:
			pass
		State.RUN:
			_run_elapsed += minf(delta, 0.25)
			_tick_spawner(dt)
			_tick_solvability(dt)
			if not _final_spawned and _run_elapsed >= _run_duration - _final_reserve:
				_spawn_final_core()
				_state = State.FINAL
			elif _run_elapsed >= _run_duration:
				_begin_outro()
		State.FINAL:
			_run_elapsed += minf(delta, 0.25)
			_tick_solvability(dt)
			if _run_elapsed >= _run_duration:
				_begin_outro()

	_update_countdown_label()
	_update_props(dt)
	if _state == State.RUN or _state == State.FINAL:
		_check_contacts()

func _tick_spawner(dt: float) -> void:
	_spawn_timer -= dt
	if _spawn_timer > 0.0:
		return
	var jitter: float = maxf(0.0, float(_get_conf("spawn_interval_jitter_sec", 0.3)))
	_spawn_timer = maxf(0.15, float(_get_conf("spawn_interval_sec", 0.8)) + randf_range(-jitter, jitter))
	var cap: int = clampi(int(_get_conf("max_active_props", 16)), 1, 42)
	if _props.size() >= cap:
		return
	_spawn_prop()

## Continuous solvability: the drift is stochastic, so the absorb-manager
## spawn-time guard is not enough. If no absorbable prop is visible for
## no_target_grace_sec, convert the smallest visible one; on an empty screen,
## force-spawn two small absorbable props from opposite edges.
func _tick_solvability(dt: float) -> void:
	_solvability_timer -= dt
	if _solvability_timer > 0.0:
		return
	_solvability_timer = 0.25
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var visible_count: int = 0
	var has_target: bool = false
	var smallest: Dictionary = {}
	var smallest_required: float = INF
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT or bool(entry.get("is_final", false)):
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		if not viewport_rect.has_point((node_v as Node2D).position):
			continue
		visible_count += 1
		var required: float = float(entry.get("required_mass", 0.0))
		if required <= _mass:
			has_target = true
			break
		if required < smallest_required:
			smallest_required = required
			smallest = entry
	if has_target:
		_no_target_timer = 0.0
		return
	_no_target_timer += 0.25
	if _no_target_timer < maxf(0.25, float(_get_conf("no_target_grace_sec", 1.2))):
		return
	_no_target_timer = 0.0
	if visible_count == 0:
		_spawn_prop(true, 2)
		_spawn_prop(true, 3)
		return
	# Rescue: shrink the smallest visible prop below the current mass.
	if not smallest.is_empty():
		var rescued: float = maxf(1.0, round(_mass * clampf(float(_get_conf("eatable_rescue_ratio", 0.55)), 0.1, 0.9)))
		smallest["required_mass"] = rescued
		smallest["mass_gain"] = maxf(1.0, round(rescued * 0.6))
		_apply_prop_tint(smallest)
		var node_v: Variant = smallest.get("node", null)
		if VFXManager and node_v is Node2D and is_instance_valid(node_v):
			VFXManager.flash_sprite(node_v as Node2D, Color(1.0, 1.0, 1.0), 0.18)

func _update_props(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var despawn_margin: float = maxf(20.0, float(_get_conf("despawn_margin_px", 90.0)))
	var pull: float = maxf(0.0, float(_get_conf("attract_pull_px_sec", 150.0)))
	var near_hz: float = maxf(0.05, float(_get_conf("near_pulse_hz", 1.6)))
	var spin: float = deg_to_rad(maxf(0.0, float(_get_conf("absorb_spin_deg_sec", 320.0))))
	var player_pos: Vector2 = _player.global_position
	for i in range(_props.size() - 1, -1, -1):
		var entry: Dictionary = _props[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_props.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D

		if int(entry.get("state", PropState.DRIFT)) == PropState.ABSORBING:
			# Suction animation toward the live ship position, then gone.
			var t: float = float(entry.get("absorb_t", 0.0)) + dt / maxf(0.05, float(entry.get("absorb_sec", 0.2)))
			entry["absorb_t"] = t
			if t >= 1.0:
				node.queue_free()
				_props.remove_at(i)
				continue
			node.position = node.position.lerp(player_pos, clampf(t * t + dt * 6.0, 0.0, 1.0))
			node.scale = (entry.get("start_scale", Vector2.ONE) as Vector2) * (1.0 - t)
			node.rotation += spin * dt
			continue

		node.position += (entry.get("velocity", Vector2.ZERO) as Vector2) * dt
		node.rotation += float(entry.get("rot_speed", 0.0)) * dt
		# Visible suction: absorbable props inside the vortex drift toward it.
		var required: float = float(entry.get("required_mass", 0.0))
		var dist: float = node.position.distance_to(player_pos)
		if required <= _mass and dist < _radius and dist > 1.0:
			var strength: float = pull * (1.0 - dist / _radius)
			node.position += (player_pos - node.position).normalized() * strength * dt
		# Near-absorbable tension pulse (no tween: cheap sine on modulate).
		if bool(entry.get("near", false)):
			var factor: float = 0.35 + 0.35 * (0.5 + 0.5 * sin(_time * TAU * near_hz))
			var type_tint: Color = entry.get("type_tint", Color.WHITE)
			node.modulate = type_tint * Color.WHITE.lerp(Color(str(_get_conf("color_near", "#F2E45B"))), factor)

		if viewport_rect.has_point(node.position):
			entry["seen_on_screen"] = true
		elif bool(entry.get("seen_on_screen", false)):
			var out: float = maxf(maxf(-node.position.x, node.position.x - viewport_size.x),
				maxf(-node.position.y, node.position.y - viewport_size.y))
			if out > despawn_margin + float(entry.get("radius_px", 30.0)):
				node.queue_free()
				_props.remove_at(i)

func _check_contacts() -> void:
	var capture_ratio: float = clampf(float(_get_conf("capture_ratio", 0.82)), 0.3, 1.0)
	var player_pos: Vector2 = _player.global_position
	for i in range(_props.size() - 1, -1, -1):
		var entry: Dictionary = _props[i]
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT:
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var dist: float = (node_v as Node2D).position.distance_to(player_pos)
		if float(entry.get("required_mass", 0.0)) <= _mass:
			if dist <= _radius * capture_ratio:
				_begin_absorb_prop(entry)
		else:
			if dist <= _radius * capture_ratio + float(entry.get("radius_px", 30.0)) * 0.4:
				_oversize_contact(entry, node_v as Node2D)

## Rewards apply at animation START (no double trigger); the entry then plays
## its suction animation in _update_props and frees itself.
func _begin_absorb_prop(entry: Dictionary) -> void:
	entry["state"] = PropState.ABSORBING
	entry["absorb_t"] = 0.0
	var size_px: float = float(entry.get("radius_px", 28.0)) * 2.0
	entry["absorb_sec"] = remap(clampf(size_px, 40.0, 200.0), 40.0, 200.0,
		maxf(0.05, float(_get_conf("absorb_min_sec", 0.12))),
		maxf(0.06, float(_get_conf("absorb_max_sec", 0.35))))
	var node_v: Variant = entry.get("node", null)
	var at_pos: Vector2 = _player.global_position
	if node_v is Node2D and is_instance_valid(node_v):
		at_pos = (node_v as Node2D).global_position
		entry["start_scale"] = (node_v as Node2D).scale
	var label_v: Variant = entry.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).visible = false

	_mass += float(entry.get("mass_gain", 1.0))
	_radius = _compute_radius()
	_push_player_state()
	if _player.has_method("pulse_gravity_hole_aura"):
		_player.call("pulse_gravity_hole_aura")
	_retint_all_props()

	var was_final: bool = bool(entry.get("is_final", false))
	if _game and is_instance_valid(_game):
		var score: int = int(round(float(entry.get("score_base", 0)) * _reward_mult))
		if score > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", score, at_pos)
		if was_final:
			# Jackpot: the final core is swallowed, crystal rain + early end.
			if _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(0, int(_get_conf("final_core_crystals", 10))))
			if VFXManager:
				VFXManager.screen_shake(7.0, 0.3)
			_begin_outro()
			return
		if randf() <= float(entry.get("crystal_chance", 0.0)) and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_pos,
				{"force_magnet_after_sec": maxf(0.2, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))})

## Touching a too-big structure hurts (shield first, never lethal by default),
## sheds flat mass, knocks the ship back and deflects the prop away so the
## cooldown cannot be chained on the same contact.
func _oversize_contact(entry: Dictionary, node: Node2D) -> void:
	if _oversize_cooldown > 0.0:
		return
	_oversize_cooldown = maxf(0.2, float(_get_conf("oversize_contact_cooldown_sec", 1.0)))
	var dir_away: Vector2 = (_player.global_position - node.position).normalized()
	if dir_away == Vector2.ZERO:
		dir_away = Vector2.DOWN
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("oversize_contact_damage_percent", 0.12)), 0.0, 1.0)
		var dmg: int = maxi(1, int(ceil(float(max_hp) * pct)))
		if bool(_get_conf("oversize_never_lethal", true)):
			var hp_v: Variant = _player.get("current_hp")
			var current_hp: int = int(hp_v) if (hp_v is int or hp_v is float) else max_hp
			dmg = mini(dmg, maxi(0, current_hp - 1))
		if dmg > 0:
			_player.call("take_damage", dmg)
	_mass = maxf(_start_mass, _mass - maxf(0.0, float(_get_conf("oversize_mass_loss_flat", 6.0))))
	_radius = _compute_radius()
	_push_player_state()
	if _player.has_method("apply_external_displacement"):
		_player.call("apply_external_displacement", dir_away * maxf(0.0, float(_get_conf("oversize_knockback_px", 80.0))))
	# Deflect the prop so it leaves the contact zone instead of grinding.
	var vel: Vector2 = entry.get("velocity", Vector2.ZERO)
	entry["velocity"] = -dir_away * maxf(vel.length(), 20.0)
	if VFXManager:
		VFXManager.flash_sprite(_player, Color(1.0, 0.35, 0.3), 0.25)
		VFXManager.screen_shake(6.0, 0.25)
	_retint_all_props()

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "GravityHoleCountdownLabel"
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
	if _countdown_label == null or not is_instance_valid(_countdown_label) or not _countdown_label.visible:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _run_duration - _run_elapsed))))

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	_kill_transition_tween()
	# Defensive restores (no-ops after a clean outro).
	if _game and is_instance_valid(_game) and _game.has_method("end_wave_background_override"):
		_game.call("end_wave_background_override", maxf(0.0, float(_get_conf("bg_fallback_fade_sec", 0.25))))
	_restore_player_mode()
	finished.emit()
	queue_free() # props, labels and transition sprite are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore player + background if freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_kill_transition_tween()
		if _game and is_instance_valid(_game) and _game.has_method("end_wave_background_override"):
			_game.call("end_wave_background_override", 0.0)
		_restore_player_mode()
