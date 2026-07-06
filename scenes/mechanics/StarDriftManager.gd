extends Node2D

## StarDriftManager — Orchestre une vague "star_drift" (inspiration Super
## Starfish) : tir coupé, le vaisseau suit le doigt avec inertie (mode
## finger-follow géré par Player.gd) pendant que le cosmos défile. Des hazards
## descendent en continu (météores dérivants, trous noirs à attraction légère)
## et des quasars verticaux télégraphés balayent une colonne d'écran. Des
## traînées serpentines de pickups gradués (petit/moyen/gros) rapportent du
## score (base x reward_multiplier) et une chance de cristal aimanté ; frôler
## un hazard sans le toucher (near-miss) = chance de cristal. Survie
## chronométrée : countdown seul au HUD, la vitesse de scroll et la densité
## montent au fil de la vague. Contacts manuels par distance (pas de physics),
## assets résolus une seule fois au setup (refs fortes, zéro load en hot path).

signal finished

enum State { INTRO, RUN, DONE }
enum QuasarState { IDLE, TELEGRAPH, ACTIVE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _obstacle_skins: Array = [] # world skin_overrides.obstacles.explosives

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 50.0
var _elapsed: float = 0.0
var _time: float = 0.0
var _spawn_cutoff_sec: float = 2.5
var _reward_multiplier: float = 1.0

# Parsed hazard/pickup type descriptors (runtime dicts with resolved assets).
var _hazard_types: Array = []
var _pickup_tiers: Array = []
var _hazard_weight_total: float = 0.0
var _pickup_weight_total: float = 0.0

# Timers.
var _hazard_timer: float = 0.0
var _trail_timer: float = 0.0
var _quasar_timer: float = 0.0

# Alive hazards. Entries: { "node": Node2D, "type": Dictionary, "vx": float,
# "base_x": float, "wobble_phase": float, "spin": float, "hit": bool,
# "passed": bool, "min_dist": float }
var _hazards: Array = []
# Alive pickups. Entries: { "node": Node2D, "tier": Dictionary,
# "base_scale": float, "pulse": float }
var _pickups: Array = []
# Pickup spawns queued to spread trail instantiation over several frames.
var _pending_pickups: Array = [] # { "pos": Vector2, "tier": Dictionary }
# Fixed quasar slots (Line2D recycled, never freed during the wave).
var _quasar_slots: Array = [] # { "telegraph","core","glow": Line2D, "state": int, "timer": float, "x": float }

# Strong refs: path -> Resource, resolved once in setup() (perf guide §3).
var _resolved_assets: Dictionary = {}

# Ship trail (core + glow sharing ONE additive material with the quasars).
var _add_material: CanvasItemMaterial = null
var _trail_core: Line2D = null
var _trail_glow: Line2D = null
var _trail_points: Array = [] # { "pos": Vector2, "born_msec": int }

var _hit_invuln_timer: float = 0.0
var _countdown_label: Label = null
var _finished_emitted: bool = false

const PLAYER_HALF_SIZE_PX: float = 26.0
const MAX_PICKUP_SPAWNS_PER_FRAME: int = 4

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("star_drift") if DataManager else {}
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []

	_duration = maxf(8.0, float(_config.get("duration", _cfg.get("duration_sec_default", 50.0))))
	_spawn_cutoff_sec = maxf(0.5, float(_get_conf("spawn_stop_before_end_sec", 2.5)))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	_parse_hazard_types()
	_parse_pickup_tiers()
	_setup_trail_nodes()
	_setup_quasar_slots()
	_begin_player_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	_hazard_timer = 0.6 # first hazard arrives quickly after the intro
	_trail_timer = 0.3
	_quasar_timer = maxf(1.0, float(_get_conf("quasar_first_delay_sec", 12.0)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_star_drift"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_star_drift", merged)

func _restore_player_mode() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _hit_invuln_timer > 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)
	_hit_invuln_timer = 0.0
	if _player.has_method("end_star_drift"):
		_player.call("end_star_drift")

# =============================================================================
# CONFIG PARSING + ASSET RESOLUTION (all loads happen here, never in the loop)
# =============================================================================

## Wave override replaces the whole hazard_types/pickup_tiers array (no partial
## merge), matching how _get_conf resolves every other key.
func _parse_hazard_types() -> void:
	_hazard_types.clear()
	_hazard_weight_total = 0.0
	var types_v: Variant = _get_conf("hazard_types", [])
	if types_v is Array:
		for type_v in (types_v as Array):
			if not (type_v is Dictionary):
				continue
			var src: Dictionary = type_v as Dictionary
			var size_base: float = maxf(16.0, float(src.get("size_px", 88.0)))
			var size_min: float = maxf(16.0, float(src.get("size_px_min", size_base)))
			var size_max: float = maxf(size_min, float(src.get("size_px_max", size_base)))
			var collision_px: float = maxf(4.0, float(src.get("collision_radius_px", 36.0)))
			var entry: Dictionary = {
				"behavior": str(src.get("behavior", "meteor")),
				"weight": maxf(0.0, float(src.get("weight", 1.0))),
				"size_px_min": size_min,
				"size_px_max": size_max,
				# collision_radius_px is anchored on the average size; the real
				# radius scales with the size rolled at spawn.
				"collision_ratio": collision_px / maxf(1.0, (size_min + size_max) * 0.5),
				"tint": Color(str(src.get("tint", "#FFFFFF"))),
				"speed_multiplier": maxf(0.1, float(src.get("speed_multiplier", 1.0))),
				"drift_x_px_sec_max": maxf(0.0, float(src.get("drift_x_px_sec_max", 0.0))),
				"wobble_amplitude_px": maxf(0.0, float(src.get("wobble_amplitude_px", 0.0))),
				"wobble_frequency_hz": maxf(0.0, float(src.get("wobble_frequency_hz", 0.0))),
				"spin_deg_sec_max": maxf(0.0, float(src.get("spin_deg_sec_max", 0.0))),
				"damage_percent": clampf(float(src.get("damage_percent", 0.12)), 0.0, 1.0),
				"pull_radius_px": maxf(0.0, float(src.get("pull_radius_px", 0.0))),
				"pull_strength_px_sec": maxf(0.0, float(src.get("pull_strength_px_sec", 0.0))),
				"resources": _resolve_asset_list(src)
			}
			_hazard_types.append(entry)
			_hazard_weight_total += float(entry["weight"])

func _parse_pickup_tiers() -> void:
	_pickup_tiers.clear()
	_pickup_weight_total = 0.0
	var tiers_v: Variant = _get_conf("pickup_tiers", [])
	if tiers_v is Array:
		for tier_v in (tiers_v as Array):
			if not (tier_v is Dictionary):
				continue
			var src: Dictionary = tier_v as Dictionary
			var entry: Dictionary = {
				"weight": maxf(0.0, float(src.get("weight", 1.0))),
				"size_px": maxf(10.0, float(src.get("size_px", 40.0))),
				"tint": Color(str(src.get("tint", "#FFD56B"))),
				"score": maxi(0, int(src.get("score", 10))),
				"crystal_chance": clampf(float(src.get("crystal_chance", 0.1)), 0.0, 1.0),
				"resources": _resolve_asset_list(src)
			}
			_pickup_tiers.append(entry)
			_pickup_weight_total += float(entry["weight"])

## Priority: declared "assets" of the type/tier > world obstacle skins (only
## when the entry opts in via use_world_obstacles). Both .tres (SpriteFrames)
## and .png/.jpg (Texture2D) are accepted; unknown paths are skipped.
func _resolve_asset_list(src: Dictionary) -> Array:
	var paths: Array = []
	var assets_v: Variant = src.get("assets", [])
	if assets_v is Array:
		for asset_v in (assets_v as Array):
			var p: String = str(asset_v)
			if p != "":
				paths.append(p)
	if paths.is_empty() and bool(src.get("use_world_obstacles", false)):
		for skin_v in _obstacle_skins:
			var sp: String = str(skin_v)
			if sp != "":
				paths.append(sp)
	var resources: Array = []
	for path_v in paths:
		var path: String = str(path_v)
		var res: Resource = _load_resolved(path)
		if res is SpriteFrames or res is Texture2D:
			resources.append(res)
	return resources

func _load_resolved(path: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _resolved_assets.has(path):
		return _resolved_assets[path] as Resource
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res != null:
		_resolved_assets[path] = res
	return res

func _pick_weighted(entries: Array, weight_total: float) -> Dictionary:
	if entries.is_empty():
		return {}
	var roll: float = randf() * maxf(0.001, weight_total)
	for entry_v in entries:
		roll -= float((entry_v as Dictionary).get("weight", 1.0))
		if roll <= 0.0:
			return entry_v as Dictionary
	return entries[entries.size() - 1] as Dictionary

# =============================================================================
# VISUAL BUILDER (.tres animated OR static texture, fallback tinted polygon)
# =============================================================================

## Returns the entity node itself (no wrapper): AnimatedSprite2D for
## SpriteFrames, Sprite2D for Texture2D, tinted Polygon2D diamond otherwise.
func _build_asset_visual(resources: Array, size_px: float, tint: Color) -> Node2D:
	if not resources.is_empty():
		var res: Resource = resources[randi() % resources.size()] as Resource
		if res is SpriteFrames:
			var frames: SpriteFrames = res as SpriteFrames
			var anim_names: PackedStringArray = frames.get_animation_names()
			if not anim_names.is_empty():
				var anim_name: StringName = StringName(anim_names[0])
				if frames.has_animation(&"default"):
					anim_name = &"default"
				if frames.get_frame_count(anim_name) > 0:
					var anim_sprite := AnimatedSprite2D.new()
					anim_sprite.sprite_frames = frames
					anim_sprite.modulate = tint
					anim_sprite.play(anim_name)
					var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
					if frame_tex:
						var f_size: Vector2 = frame_tex.get_size()
						if f_size.x > 0.0 and f_size.y > 0.0:
							anim_sprite.scale = Vector2.ONE * (size_px / maxf(f_size.x, f_size.y))
					return anim_sprite
		elif res is Texture2D:
			var texture: Texture2D = res as Texture2D
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.modulate = tint
			var tex_size: Vector2 = texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
			return sprite
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -size_px * 0.5),
		Vector2(size_px * 0.45, 0.0),
		Vector2(0.0, size_px * 0.5),
		Vector2(-size_px * 0.45, 0.0)
	])
	diamond.color = tint
	return diamond

# =============================================================================
# DIFFICULTY RAMP
# =============================================================================

## Difficulty ramp position (0 at wave start -> 1 at wave end).
func _ramp_t() -> float:
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _current_scroll_speed() -> float:
	var v_start: float = maxf(40.0, float(_get_conf("scroll_speed_px_sec_start", 240.0)))
	var v_end: float = maxf(v_start, float(_get_conf("scroll_speed_px_sec_end", 430.0)))
	return lerpf(v_start, v_end, _ramp_t())

func _current_hazard_interval() -> float:
	var i_start: float = maxf(0.2, float(_get_conf("hazard_interval_sec_start", 1.6)))
	var i_end: float = clampf(float(_get_conf("hazard_interval_sec_end", 0.85)), 0.2, i_start)
	return lerpf(i_start, i_end, _ramp_t())

func _current_trail_interval() -> float:
	var i_start: float = maxf(0.4, float(_get_conf("trail_interval_sec_start", 2.4)))
	var i_end: float = clampf(float(_get_conf("trail_interval_sec_end", 1.5)), 0.4, i_start)
	return lerpf(i_start, i_end, _ramp_t())

func _current_quasar_interval() -> float:
	var i_start: float = maxf(2.0, float(_get_conf("quasar_interval_sec_start", 14.0)))
	var i_end: float = clampf(float(_get_conf("quasar_interval_sec_end", 8.0)), 2.0, i_start)
	return lerpf(i_start, i_end, _ramp_t())

# =============================================================================
# SPAWNING
# =============================================================================

func _spawn_hazard_wave() -> void:
	var cap: int = maxi(1, int(_get_conf("max_active_hazards", 12)))
	if _hazards.size() >= cap:
		return
	var count: int = 1
	# Second half of the wave: growing chance of a 2-hazard burst.
	var burst_max: int = maxi(1, int(_get_conf("hazard_burst_max_end", 2)))
	var ramp: float = _ramp_t()
	if burst_max > 1 and ramp > 0.55 and randf() <= (ramp - 0.55) * 2.0:
		count = burst_max
	count = mini(count, cap - _hazards.size())
	if count <= 1:
		_spawn_hazard(0.0, 1.0)
		return
	# Burst: one hazard per screen half (random order) so a ship-sized corridor
	# always stays open between simultaneous spawns.
	var halves: Array = [[0.0, 0.5], [0.5, 1.0]]
	if randf() < 0.5:
		halves.reverse()
	for i in range(count):
		var half: Array = halves[i % 2]
		_spawn_hazard(float(half[0]), float(half[1]))

func _spawn_hazard(range_min_ratio: float = 0.0, range_max_ratio: float = 1.0) -> void:
	var type: Dictionary = _pick_weighted(_hazard_types, _hazard_weight_total)
	if type.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(0.0, float(_get_conf("spawn_side_margin_px", 60.0)))
	var spawn_y: float = minf(-20.0, float(_get_conf("spawn_y", -140.0)))
	# Rolled size, capped to a screen-width ratio so a ship-sized corridor
	# always remains even next to the biggest hazards.
	var size: float = randf_range(float(type.get("size_px_min", 88.0)), float(type.get("size_px_max", 88.0)))
	size = minf(size, viewport_size.x * clampf(float(_get_conf("hazard_max_size_screen_ratio", 0.33)), 0.1, 0.6))
	var span: float = maxf(1.0, viewport_size.x - margin * 2.0)
	var x_min: float = margin + span * clampf(range_min_ratio, 0.0, 1.0)
	var x_max: float = margin + span * clampf(range_max_ratio, 0.0, 1.0)
	var x: float = randf_range(x_min, maxf(x_min + 1.0, x_max))
	var node: Node2D = _build_asset_visual(type.get("resources", []) as Array,
		size, type.get("tint", Color.WHITE) as Color)
	node.name = "StarDriftHazard"
	node.z_as_relative = false
	node.z_index = 10
	node.position = Vector2(x, spawn_y)
	add_child(node)
	var drift_max: float = float(type.get("drift_x_px_sec_max", 0.0))
	_hazards.append({
		"node": node,
		"type": type,
		"size_px": size,
		"radius": size * float(type.get("collision_ratio", 0.41)),
		"vx": randf_range(-drift_max, drift_max),
		"base_x": x,
		"wobble_phase": randf() * TAU,
		"spin": deg_to_rad(randf_range(-1.0, 1.0) * float(type.get("spin_deg_sec_max", 0.0))),
		"hit": false,
		"passed": false,
		"min_dist": INF
	})

## A serpentine (sine) trail of pickups; the tier is rolled once per trail so
## it reads as one homogeneous "snake". With trail_end_bonus the last pickup is
## upgraded one tier (the shiny star at the end of the snake).
func _spawn_pickup_trail() -> void:
	if _pickup_tiers.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(0.0, float(_get_conf("trail_side_margin_px", 80.0)))
	var amp: float = randf_range(
		maxf(0.0, float(_get_conf("trail_sine_amplitude_px_min", 40.0))),
		maxf(0.0, float(_get_conf("trail_sine_amplitude_px_max", 130.0))))
	var wavelength: float = maxf(60.0, float(_get_conf("trail_sine_wavelength_px", 420.0)))
	var spacing: float = maxf(24.0, float(_get_conf("trail_spacing_px", 64.0)))
	var count_min: int = maxi(1, int(_get_conf("trail_count_min", 6)))
	var count_max: int = maxi(count_min, int(_get_conf("trail_count_max", 10)))
	var count: int = count_min + (randi() % (count_max - count_min + 1))
	var spawn_y: float = minf(-20.0, float(_get_conf("spawn_y", -140.0)))
	var x0: float = randf_range(margin + amp, maxf(margin + amp + 1.0, viewport_size.x - margin - amp))
	var phase0: float = randf() * TAU
	var tier_idx: int = _pickup_tiers.find(_pick_weighted(_pickup_tiers, _pickup_weight_total))
	if tier_idx < 0:
		tier_idx = 0
	var bonus_end: bool = bool(_get_conf("trail_end_bonus", true))
	for i in range(count):
		var t_idx: int = tier_idx
		if bonus_end and i == count - 1:
			t_idx = mini(tier_idx + 1, _pickup_tiers.size() - 1)
		var px: float = x0 + sin(phase0 + float(i) * TAU * spacing / wavelength) * amp
		px = clampf(px, 20.0, viewport_size.x - 20.0)
		_pending_pickups.append({
			"pos": Vector2(px, spawn_y - spacing * float(i)),
			"tier": _pickup_tiers[t_idx]
		})

## Queued trail pickups instantiate a few per frame so a long snake never costs
## a full 10-sprite burst on one frame (perf guide anti-hitch guard).
func _drain_pending_pickups() -> void:
	if _pending_pickups.is_empty():
		return
	var cap: int = maxi(1, int(_get_conf("max_active_pickups", 40)))
	var budget: int = MAX_PICKUP_SPAWNS_PER_FRAME
	while budget > 0 and not _pending_pickups.is_empty():
		if _pickups.size() >= cap:
			_pending_pickups.clear()
			return
		var pending: Dictionary = _pending_pickups.pop_front() as Dictionary
		_spawn_pickup(pending.get("pos", Vector2.ZERO) as Vector2, pending.get("tier", {}) as Dictionary)
		budget -= 1

func _spawn_pickup(at_pos: Vector2, tier: Dictionary) -> void:
	if tier.is_empty():
		return
	var node: Node2D = _build_asset_visual(tier.get("resources", []) as Array,
		float(tier.get("size_px", 40.0)), tier.get("tint", Color.WHITE) as Color)
	node.name = "StarDriftPickup"
	node.z_as_relative = false
	node.z_index = 12
	node.position = at_pos
	add_child(node)
	_pickups.append({
		"node": node,
		"tier": tier,
		"base_scale": node.scale.x,
		"pulse": randf() * TAU
	})

# =============================================================================
# QUASARS (screen-wide telegraphed beams, fixed pool of recycled Line2D)
# =============================================================================

func _setup_quasar_slots() -> void:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if not bool(_get_conf("quasar_enabled", true)):
		return
	var slot_count: int = clampi(int(_get_conf("quasar_max_active", 1)), 1, 3)
	var width: float = maxf(12.0, float(_get_conf("quasar_width_px", 90.0)))
	for i in range(slot_count):
		var telegraph := _build_glow_line(4.0, Color(str(_get_conf("quasar_warn_color", "#FF5A5A96"))), false, 52)
		var glow := _build_glow_line(width, Color(str(_get_conf("quasar_glow_color", "#B455E8A0"))), true, 53)
		var core := _build_glow_line(width * 0.35, Color(str(_get_conf("quasar_core_color", "#FFF3C7"))), false, 54)
		telegraph.visible = false
		glow.visible = false
		core.visible = false
		_quasar_slots.append({
			"telegraph": telegraph,
			"glow": glow,
			"core": core,
			"state": QuasarState.IDLE,
			"timer": 0.0,
			"x": 0.0
		})

func _try_trigger_quasar() -> void:
	for i in range(_quasar_slots.size()):
		var slot: Dictionary = _quasar_slots[i]
		if int(slot.get("state", QuasarState.IDLE)) != QuasarState.IDLE:
			continue
		var viewport_size: Vector2 = get_viewport_rect().size
		var margin: float = maxf(20.0, float(_get_conf("quasar_side_margin_px", 90.0)))
		var x: float = randf_range(margin, maxf(margin + 1.0, viewport_size.x - margin))
		var pts := PackedVector2Array([Vector2(x, -40.0), Vector2(x, viewport_size.y + 40.0)])
		var telegraph: Line2D = slot.get("telegraph") as Line2D
		telegraph.points = pts
		telegraph.visible = true
		(slot.get("glow") as Line2D).points = pts
		(slot.get("core") as Line2D).points = pts
		slot["state"] = QuasarState.TELEGRAPH
		slot["timer"] = maxf(0.2, float(_get_conf("quasar_telegraph_sec", 1.1)))
		slot["x"] = x
		_quasar_slots[i] = slot
		return

func _update_quasars(dt: float) -> void:
	for i in range(_quasar_slots.size()):
		var slot: Dictionary = _quasar_slots[i]
		var q_state: int = int(slot.get("state", QuasarState.IDLE))
		if q_state == QuasarState.IDLE:
			continue
		var timer: float = float(slot.get("timer", 0.0)) - dt
		if q_state == QuasarState.TELEGRAPH:
			# Pulsing warning line while the beam charges.
			var telegraph: Line2D = slot.get("telegraph") as Line2D
			telegraph.modulate.a = 0.55 + 0.45 * sin(_time * TAU * 3.0)
			if timer <= 0.0:
				telegraph.visible = false
				(slot.get("glow") as Line2D).visible = true
				(slot.get("core") as Line2D).visible = true
				slot["state"] = QuasarState.ACTIVE
				timer = maxf(0.2, float(_get_conf("quasar_active_sec", 1.4)))
		elif q_state == QuasarState.ACTIVE:
			var half_width: float = maxf(12.0, float(_get_conf("quasar_width_px", 90.0))) * 0.5
			if _hit_invuln_timer <= 0.0 and _player and is_instance_valid(_player) \
				and absf(_player.global_position.x - float(slot.get("x", 0.0))) <= half_width:
				_damage_player(clampf(float(_get_conf("quasar_damage_percent", 0.18)), 0.0, 1.0))
			if timer <= 0.0:
				(slot.get("glow") as Line2D).visible = false
				(slot.get("core") as Line2D).visible = false
				slot["state"] = QuasarState.IDLE
				timer = 0.0
		slot["timer"] = timer
		_quasar_slots[i] = slot

# =============================================================================
# SHIP TRAIL (samples the player position, core + glow additive lines)
# =============================================================================

func _setup_trail_nodes() -> void:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if not bool(_get_conf("ship_trail_enabled", true)):
		return
	_trail_glow = _build_glow_line(float(_get_conf("ship_trail_glow_width_px", 14.0)),
		Color(str(_get_conf("ship_trail_glow_color", "#8FD3FFB4"))), true, 55)
	_trail_core = _build_glow_line(float(_get_conf("ship_trail_core_width_px", 3.0)),
		Color(str(_get_conf("ship_trail_core_color", "#FFFFFF"))), false, 56)

func _build_glow_line(width: float, color: Color, additive: bool, z: int) -> Line2D:
	var line := Line2D.new()
	line.width = maxf(1.0, width)
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_as_relative = false
	line.z_index = z
	if additive:
		line.material = _add_material
	add_child(line)
	return line

func _update_ship_trail() -> void:
	if _trail_core == null or not is_instance_valid(_trail_core):
		return
	if _player and is_instance_valid(_player):
		_push_trail_point(_player.global_position)
	var lifetime_msec: int = int(maxf(0.05, float(_get_conf("ship_trail_point_lifetime_sec", 0.35))) * 1000.0)
	var now: int = Time.get_ticks_msec()
	while not _trail_points.is_empty() and now - int((_trail_points[0] as Dictionary).get("born_msec", 0)) > lifetime_msec:
		_trail_points.pop_front()
	if _trail_points.size() < 2:
		_trail_core.clear_points()
		_trail_glow.clear_points()
		return
	var pts := PackedVector2Array()
	for p in _trail_points:
		pts.append(to_local((p as Dictionary).get("pos", Vector2.ZERO)))
	_trail_core.points = pts
	_trail_glow.points = pts

func _push_trail_point(pos: Vector2) -> void:
	var min_dist: float = maxf(1.0, float(_get_conf("ship_trail_min_point_dist_px", 6.0)))
	if not _trail_points.is_empty():
		var last: Vector2 = (_trail_points[_trail_points.size() - 1] as Dictionary).get("pos", Vector2.ZERO)
		if last.distance_to(pos) < min_dist:
			return
	_trail_points.append({"pos": pos, "born_msec": Time.get_ticks_msec()})
	var max_points: int = maxi(4, int(_get_conf("ship_trail_max_points", 24)))
	while _trail_points.size() > max_points:
		_trail_points.pop_front()

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
			if _elapsed < _duration - _spawn_cutoff_sec:
				_hazard_timer -= dt
				if _hazard_timer <= 0.0:
					_hazard_timer = _current_hazard_interval()
					_spawn_hazard_wave()
				_trail_timer -= dt
				if _trail_timer <= 0.0:
					_trail_timer = _current_trail_interval()
					if randf() <= clampf(float(_get_conf("trail_chance", 0.9)), 0.0, 1.0):
						_spawn_pickup_trail()
				if not _quasar_slots.is_empty():
					_quasar_timer -= dt
					if _quasar_timer <= 0.0:
						_quasar_timer = _current_quasar_interval()
						_try_trigger_quasar()

	_drain_pending_pickups()
	var speed: float = _current_scroll_speed()
	_update_hazards(dt, speed)
	_update_pickups(dt, speed)
	_update_quasars(dt)
	_update_ship_trail()

	if _elapsed >= _duration:
		_finish()

func _tick_hit_invuln(dt: float) -> void:
	if _hit_invuln_timer <= 0.0:
		return
	_hit_invuln_timer -= dt
	if _hit_invuln_timer <= 0.0 and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)

func _update_hazards(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_pos: Vector2 = _player.global_position
	for i in range(_hazards.size() - 1, -1, -1):
		var entry: Dictionary = _hazards[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_hazards.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		var type: Dictionary = entry.get("type", {}) as Dictionary
		node.position.y += speed * float(type.get("speed_multiplier", 1.0)) * dt

		# Horizontal drift + sine wobble; soft bounce on the screen edges.
		var vx: float = float(entry.get("vx", 0.0))
		var base_x: float = float(entry.get("base_x", node.position.x)) + vx * dt
		if base_x < 20.0 or base_x > viewport_size.x - 20.0:
			vx = -vx
			entry["vx"] = vx
			base_x = clampf(base_x, 20.0, viewport_size.x - 20.0)
		entry["base_x"] = base_x
		var wobble_amp: float = float(type.get("wobble_amplitude_px", 0.0))
		var wobble_hz: float = float(type.get("wobble_frequency_hz", 0.0))
		node.position.x = base_x + (sin(_time * TAU * wobble_hz + float(entry.get("wobble_phase", 0.0))) * wobble_amp if wobble_amp > 0.0 and wobble_hz > 0.0 else 0.0)
		var spin: float = float(entry.get("spin", 0.0))
		if spin != 0.0:
			node.rotation += spin * dt

		# One distance per entry per frame, reused by pull / contact / near-miss.
		var dist: float = node.global_position.distance_to(player_pos)
		if dist < float(entry.get("min_dist", INF)):
			entry["min_dist"] = dist

		# Black-hole style light pull, stronger near the core, always escapable.
		var pull_radius: float = float(type.get("pull_radius_px", 0.0))
		if pull_radius > 0.0 and dist < pull_radius and dist > 1.0:
			var pull: float = float(type.get("pull_strength_px_sec", 0.0)) * (1.0 - dist / pull_radius) * dt
			if pull > 0.0 and _player.has_method("apply_external_displacement"):
				_player.call("apply_external_displacement", (node.global_position - player_pos).normalized() * pull)

		# Contact: manual distance check against the ship (radius rolled at spawn).
		var radius: float = float(entry.get("radius", 36.0))
		if not bool(entry.get("hit", false)) and _hit_invuln_timer <= 0.0 \
			and dist <= radius + PLAYER_HALF_SIZE_PX:
			entry["hit"] = true
			_hazards[i] = entry
			_damage_player(float(type.get("damage_percent", 0.12)))
			if _player == null or not is_instance_valid(_player):
				return # lethal hit, the player is already gone
			continue

		# Fully passed below the ship: near-miss check, once per hazard.
		if not bool(entry.get("passed", false)) \
			and node.position.y > player_pos.y + radius + PLAYER_HALF_SIZE_PX:
			entry["passed"] = true
			if not bool(entry.get("hit", false)):
				_check_near_miss(float(entry.get("min_dist", INF)), node.global_position)

		_hazards[i] = entry
		if node.position.y > viewport_size.y + float(entry.get("size_px", 88.0)):
			node.queue_free()
			_hazards.remove_at(i)

## Damage: % of max HP through the standard pipeline (shield first), then a
## short invulnerability window shared by every hazard source.
func _damage_player(damage_percent: float) -> void:
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * clampf(damage_percent, 0.0, 1.0)))))
	if _player == null or not is_instance_valid(_player):
		return # the hit was lethal
	_hit_invuln_timer = maxf(0.2, float(_get_conf("hit_invuln_sec", 1.0)))
	if _player.has_method("set_invincible"):
		_player.call("set_invincible", true)
	if VFXManager:
		VFXManager.screen_shake(6, 0.2)

## Near-miss: the hazard brushed past the ship without touching it -> crystal
## chance (skill reward, mirrors Super Starfish's close-call thrill).
func _check_near_miss(min_dist: float, at_pos: Vector2) -> void:
	if min_dist > maxf(0.0, float(_get_conf("near_miss_distance_px", 70.0))) + PLAYER_HALF_SIZE_PX:
		return
	var chance: float = clampf(float(_get_conf("near_miss_crystal_chance", 0.3)), 0.0, 1.0)
	if randf() > chance:
		return
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", Vector2(at_pos.x, _player.global_position.y))

func _update_pickups(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 52.0)))
	var pulse_hz: float = maxf(0.1, float(_get_conf("pickup_pulse_hz", 1.6)))
	for i in range(_pickups.size() - 1, -1, -1):
		var entry: Dictionary = _pickups[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		# Gentle pulse so the snake reads as "to grab".
		var pulse: float = 1.0 + sin(_time * TAU * pulse_hz + float(entry.get("pulse", 0.0))) * 0.12
		node.scale = Vector2.ONE * float(entry.get("base_scale", 1.0)) * pulse

		if node.global_position.distance_to(player_pos) <= pickup_radius:
			var at_pos: Vector2 = node.global_position
			var tier: Dictionary = entry.get("tier", {}) as Dictionary
			node.queue_free()
			_pickups.remove_at(i)
			_collect(tier, at_pos)
			continue

		if node.position.y > viewport_size.y + 60.0:
			node.queue_free()
			_pickups.remove_at(i)

## Pickup reward: tier score (x wave/world multiplier) + magnetized crystal chance.
func _collect(tier: Dictionary, at_pos: Vector2) -> void:
	var points: int = int(round(float(int(tier.get("score", 10))) * _reward_multiplier))
	if _game and is_instance_valid(_game):
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, at_pos)
		var chance: float = clampf(float(tier.get("crystal_chance", 0.1)), 0.0, 1.0)
		if randf() <= chance and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_pos,
				{"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))})
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.flash_sprite(_player, tier.get("tint", Color(1.0, 0.9, 0.55)) as Color, 0.1)

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "StarDriftCountdownLabel"
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
	queue_free() # hazards, pickups, beams and trail are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
