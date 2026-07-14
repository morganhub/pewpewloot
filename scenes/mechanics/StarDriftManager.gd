extends Node2D

## StarDriftManager — Orchestre une vague "star_drift" (inspiration Super
## Starfish) : tir coupé, le vaisseau suit le doigt avec inertie (mode
## finger-follow géré par Player.gd) pendant que le cosmos défile. Des hazards
## descendent en continu (météores dérivants — fragmentables au rebond de bord,
## trous noirs à attraction légère, trous BLANCS répulseurs, comètes latérales
## traversantes) et des quasars verticaux télégraphés balayent une colonne
## d'écran ; des grappes de MINES fixes (anneaux rouges oscillants) structurent
## l'espace en couloirs. Les pickups gradués (petit/moyen/gros) « volent » dans
## le décor en CHUTE LIBRE : ils suivent le scroll avec une gravité légère et
## des trajectoires sinueuses toujours orientées vers le bas — plus une
## formation rare en SERPENT VIVANT qui ondule et fuit le joueur. POWERUPS
## (étoile filante/invuln, dash double-tap, aimant, bouclier 1 charge) avec
## icônes de temps restant en bas-droite. ÉVÉNEMENTS en toasts centraux
## (pluie de météores sur une moitié, supernova, alignement de quasars,
## comète guide, constellation à relier dans l'ordre). Survie chronométrée
## (60 s story, infini en Libre continuous : la rampe suit
## _free_level_progress). Contacts manuels par distance (pas de physics),
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
var _duration: float = 60.0
var _elapsed: float = 0.0
var _time: float = 0.0
var _spawn_cutoff_sec: float = 2.5
var _reward_multiplier: float = 1.0

# Parsed hazard/pickup/powerup type descriptors (runtime dicts, resolved assets).
var _hazard_types: Array = []
var _pickup_tiers: Array = []
var _powerup_defs: Array = []
var _hazard_weight_total: float = 0.0
var _pickup_weight_total: float = 0.0
var _powerup_weight_total: float = 0.0

# Timers.
var _hazard_timer: float = 0.0
var _pickup_timer: float = 0.0
var _quasar_timer: float = 0.0
var _powerup_timer: float = 0.0
var _mine_timer: float = 0.0
var _event_timer: float = 0.0

# Alive hazards. Entries: { "node": Node2D, "type": Dictionary, "size_px",
# "radius", "vx", "base_x", "wobble_phase", "spin", "hit", "passed",
# "min_dist" } + optionnels : "is_fragment", "rings" (mines), "pvel"
# (projectiles supernova), "nova_ring"/"nova_t" (cible supernova).
var _hazards: Array = []
# Alive pickups (chute libre). Entries: { "node": Node2D, "tier": Dictionary,
# "base_scale", "pulse", "base_x", "vx", "vy_extra", "sway_phase" }
# + optionnel "powerup": Dictionary (def du powerup, collecte spéciale).
var _pickups: Array = []
# Spawns en file pour étaler les bursts (serpent, pluie) sur plusieurs frames.
var _spawn_queue: Array = [] # { "pos": Vector2, "tier": Dictionary, "powerup": Dictionary? }
# Fixed quasar slots (Line2D recycled, never freed during the wave).
var _quasar_slots: Array = [] # { "telegraph","core","glow": Line2D, "state": int, "timer": float, "x": float }

# Serpent vivant [V11] : tête virtuelle qui ondule/fuit et pond des pickups.
var _snake: Dictionary = {} # { "x", "phase", "tier_idx", "remaining", "total", "drop_timer" }
var _snake_cd: float = 0.0

# Powerups/buffs actifs.
var _star_invuln_timer: float = 0.0
var _dash_iframe_timer: float = 0.0
var _shield_grace_timer: float = 0.0
var _magnet_timer: float = 0.0
var _dash_charges: int = 0
var _shield_charges: int = 0
var _dash_active_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_speed_px_sec: float = 0.0
var _last_tap_msec: int = -100000
var _last_tap_pos: Vector2 = Vector2.ZERO
var _shield_halo: Node2D = null
var _trail_glow_base_color: Color = Color.WHITE
var _last_powerup_id: String = ""

# HUD bas-droite : icônes des buffs actifs (temps restant / charges).
var _buff_bar: Node2D = null
var _buff_icons: Dictionary = {} # id -> { "root": Node2D, "badge": Label }

# Événements (un seul actif à la fois, toasts centraux).
var _event_active: String = ""
var _event: Dictionary = {}
var _last_event_id: String = ""

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

	_duration = maxf(8.0, float(_config.get("duration", _cfg.get("duration_sec_default", 60.0))))
	_spawn_cutoff_sec = maxf(0.5, float(_get_conf("spawn_stop_before_end_sec", 2.5)))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	_parse_hazard_types()
	_parse_pickup_tiers()
	_parse_powerup_defs()
	_setup_trail_nodes()
	_setup_quasar_slots()
	_begin_player_mode()
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.7)))
	_hazard_timer = 0.6 # first hazard arrives quickly after the intro
	_pickup_timer = 0.3
	_quasar_timer = maxf(1.0, float(_get_conf("quasar_first_delay_sec", 12.0)))
	_powerup_timer = randf_range(
		maxf(3.0, float(_get_conf("powerup_interval_sec_min", 14.0))),
		maxf(3.0, float(_get_conf("powerup_interval_sec_max", 22.0))))
	_mine_timer = _current_mine_interval() * randf_range(0.6, 1.0)
	_event_timer = maxf(2.0, float(_get_conf("event_first_delay_sec", 12.0)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la dérive EN COURS est re-scalée
## au changement de level — position, hazards et traîne préservés. Toutes les
## clés sont lues live via _get_conf : il suffit de les merger.
func update_free_mode_config(cfg: Dictionary) -> void:
	for key in ["scroll_speed_px_sec_start", "scroll_speed_px_sec_end",
		"hazard_interval_sec_start", "hazard_interval_sec_end",
		"quasar_interval_sec_end", "event_interval_sec_min",
		"event_interval_sec_max", "_free_level_progress"]:
		if cfg.has(key):
			_config[key] = cfg[key]

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_star_drift"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_star_drift", merged)

func _restore_player_mode() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _any_invuln() and _player.has_method("set_invincible"):
		_player.call("set_invincible", false)
	_hit_invuln_timer = 0.0
	_star_invuln_timer = 0.0
	_dash_iframe_timer = 0.0
	_shield_grace_timer = 0.0
	if _player.has_method("end_star_drift"):
		_player.call("end_star_drift")

func _translate_or(key: String, fallback: String) -> String:
	if key != "" and typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Toast central d'événement (pipeline splash « Vague X » du jeu).
func _toast(key: String, fallback: String, color_html: String = "") -> void:
	if _game and is_instance_valid(_game) and _game.has_method("show_center_splash"):
		_game.call("show_center_splash", _translate_or(key, fallback), "", color_html)

# =============================================================================
# LABELS D'EFFETS (toggle global wave_types.json > effect_labels_enabled) —
# béquille lisibilité tant que les assets ne sont pas explicites.
# =============================================================================

func _effect_labels_enabled() -> bool:
	var global_default: bool = bool(DataManager.get_wave_types_global("effect_labels_enabled", false)) if DataManager else false
	return bool(_get_conf("effect_labels_enabled", global_default))

func _attach_effect_label(node: Node2D, text: String, size_px: float, color: Color) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("effect_label_font_size", 18))))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(240.0, 30.0)
	label.position = Vector2(-120.0, size_px * 0.5 + 6.0)
	node.add_child(label)

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
			var entry: Dictionary = _build_hazard_type(src)
			_hazard_types.append(entry)
			_hazard_weight_total += float(entry["weight"])

func _build_hazard_type(src: Dictionary) -> Dictionary:
	var size_base: float = maxf(16.0, float(src.get("size_px", 88.0)))
	var size_min: float = maxf(16.0, float(src.get("size_px_min", size_base)))
	var size_max: float = maxf(size_min, float(src.get("size_px_max", size_base)))
	var collision_px: float = maxf(4.0, float(src.get("collision_radius_px", 36.0)))
	return {
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
		# Fragmentation [V9] (météores) : se scinde au rebond de bord.
		"split_on_edge_chance": clampf(float(src.get("split_on_edge_chance", 0.0)), 0.0, 1.0),
		"split_count_min": maxi(2, int(src.get("split_count_min", 2))),
		"split_count_max": maxi(2, int(src.get("split_count_max", 3))),
		"split_min_size_px": maxf(20.0, float(src.get("split_min_size_px", 100.0))),
		# Comètes traversantes [V8] : spawn latéral, near-miss généreux.
		"comet_speed_px_sec_min": maxf(60.0, float(src.get("comet_speed_px_sec_min", 520.0))),
		"comet_speed_px_sec_max": maxf(60.0, float(src.get("comet_speed_px_sec_max", 680.0))),
		"comet_fall_px_sec": maxf(0.0, float(src.get("comet_fall_px_sec", 120.0))),
		"near_miss_mult": maxf(0.1, float(src.get("near_miss_mult", 1.0))),
		"resources": _resolve_asset_list(src)
	}

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

func _parse_powerup_defs() -> void:
	_powerup_defs.clear()
	_powerup_weight_total = 0.0
	var defs_v: Variant = _get_conf("powerup_types", [])
	if defs_v is Array:
		for def_v in (defs_v as Array):
			if not (def_v is Dictionary):
				continue
			var src: Dictionary = (def_v as Dictionary).duplicate(true)
			src["weight"] = maxf(0.0, float(src.get("weight", 1.0)))
			src["tint_color"] = Color(str(src.get("tint", "#FFFFFF")))
			src["resources"] = _resolve_asset_list(src)
			_powerup_defs.append(src)
			_powerup_weight_total += float(src["weight"])

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

func _build_circle_polygon(radius: float, color: Color, points: int = 20) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(points):
		var a: float = TAU * float(k) / float(points)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = color
	return poly

# =============================================================================
# DIFFICULTY RAMP
# =============================================================================

## Difficulty ramp position (0 at wave start -> 1 at wave end). En mode libre
## "continuous", _duration est quasi infinie (la rampe temporelle resterait
## figée à 0) : _free_level_progress (progression 0->1 du level) la remplace,
## les clés *_end restent donc effectives.
func _ramp_t() -> float:
	var progress_v: Variant = _config.get("_free_level_progress", null)
	if progress_v is float or progress_v is int:
		return clampf(float(progress_v), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _current_scroll_speed() -> float:
	var v_start: float = maxf(40.0, float(_get_conf("scroll_speed_px_sec_start", 240.0)))
	var v_end: float = maxf(v_start, float(_get_conf("scroll_speed_px_sec_end", 430.0)))
	return lerpf(v_start, v_end, _ramp_t())

func _current_hazard_interval() -> float:
	var floor_sec: float = maxf(0.1, float(_get_conf("hazard_interval_floor_sec", 0.3)))
	var i_start: float = maxf(floor_sec, float(_get_conf("hazard_interval_sec_start", 1.6)))
	var i_end: float = clampf(float(_get_conf("hazard_interval_sec_end", 0.85)), floor_sec, i_start)
	return lerpf(i_start, i_end, _ramp_t())

func _current_pickup_interval() -> float:
	var i_start: float = maxf(0.3, float(_get_conf("pickup_interval_sec_start", 1.7)))
	var i_end: float = clampf(float(_get_conf("pickup_interval_sec_end", 1.1)), 0.3, i_start)
	return lerpf(i_start, i_end, _ramp_t())

func _current_quasar_interval() -> float:
	var i_start: float = maxf(2.0, float(_get_conf("quasar_interval_sec_start", 14.0)))
	var i_end: float = clampf(float(_get_conf("quasar_interval_sec_end", 8.0)), 2.0, i_start)
	return lerpf(i_start, i_end, _ramp_t())

func _current_mine_interval() -> float:
	var i_start: float = maxf(3.0, float(_get_conf("mine_cluster_interval_sec_start", 16.0)))
	var i_end: float = clampf(float(_get_conf("mine_cluster_interval_sec_end", 9.0)), 3.0, i_start)
	return lerpf(i_start, i_end, _ramp_t())

# =============================================================================
# SPAWNING — HAZARDS
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

## forced_behavior : "" = tirage pondéré normal ; sinon le premier type portant
## ce behavior (pluie de météores).
func _spawn_hazard(range_min_ratio: float = 0.0, range_max_ratio: float = 1.0, forced_behavior: String = "") -> void:
	var type: Dictionary = {}
	if forced_behavior != "":
		for type_v in _hazard_types:
			if str((type_v as Dictionary).get("behavior", "")) == forced_behavior:
				type = type_v as Dictionary
				break
	if type.is_empty():
		type = _pick_weighted(_hazard_types, _hazard_weight_total)
	if type.is_empty():
		return
	var behavior: String = str(type.get("behavior", "meteor"))
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
	var pos := Vector2(x, spawn_y)
	var vx: float = randf_range(-1.0, 1.0) * float(type.get("drift_x_px_sec_max", 0.0))
	# Comète traversante [V8] : spawn LATÉRAL, traverse l'écran en diagonale douce.
	if behavior == "comet":
		var from_left: bool = randf() < 0.5
		var comet_speed: float = randf_range(
			float(type.get("comet_speed_px_sec_min", 520.0)),
			float(type.get("comet_speed_px_sec_max", 680.0)))
		vx = comet_speed if from_left else -comet_speed
		pos = Vector2(-size if from_left else viewport_size.x + size,
			viewport_size.y * randf_range(0.15, 0.6))
	_add_hazard_entry(type, pos, size, vx, false)

## Instancie un hazard et son record ; renvoie l'entry (grappe de mines,
## fragments, projectiles supernova réutilisent ce chemin).
func _add_hazard_entry(type: Dictionary, pos: Vector2, size: float, vx: float, is_fragment: bool) -> Dictionary:
	var behavior: String = str(type.get("behavior", "meteor"))
	var node: Node2D = _build_asset_visual(type.get("resources", []) as Array,
		size, type.get("tint", Color.WHITE) as Color)
	node.name = "StarDriftHazard"
	node.z_as_relative = false
	node.z_index = 10
	node.position = pos
	add_child(node)
	var entry: Dictionary = {
		"node": node,
		"type": type,
		"size_px": size,
		"radius": size * float(type.get("collision_ratio", 0.41)),
		"vx": vx,
		"base_x": pos.x,
		"wobble_phase": randf() * TAU,
		"spin": deg_to_rad(randf_range(-1.0, 1.0) * float(type.get("spin_deg_sec_max", 0.0))),
		"hit": false,
		"passed": false,
		"min_dist": INF
	}
	if is_fragment:
		entry["is_fragment"] = true
	# Comète : longue traînée (Line2D additive attachée au node, points locaux).
	if behavior == "comet":
		var trail := Line2D.new()
		trail.width = maxf(4.0, size * 0.3)
		trail.default_color = Color(1.0, 1.0, 1.0, 0.45)
		trail.material = _add_material
		var dir_sign: float = -1.0 if vx > 0.0 else 1.0
		trail.points = PackedVector2Array([Vector2.ZERO,
			Vector2(dir_sign * size * 1.6, -size * 0.35),
			Vector2(dir_sign * size * 3.2, -size * 0.7)])
		node.add_child(trail)
	# Mine [V13] : anneaux rouges oscillants (glow façon bombes slice_rush).
	if behavior == "mine":
		var rings: Array = []
		var layers_v: Variant = _get_conf("mine_ring_layers", [])
		var layers: Array = (layers_v as Array) if layers_v is Array else []
		if layers.is_empty():
			layers = [{"color": "#FF3D2A66", "width_px": 10.0, "additive": true},
				{"color": "#FF6A55AA", "width_px": 4.0, "additive": false}]
		for layer_v in layers:
			var layer: Dictionary = layer_v as Dictionary
			var ring := Line2D.new()
			ring.closed = true
			ring.width = maxf(1.0, float(layer.get("width_px", 6.0)))
			ring.default_color = Color(str(layer.get("color", "#FF3D2A66")))
			if bool(layer.get("additive", false)):
				ring.material = _add_material
			node.add_child(ring)
			rings.append(ring)
		entry["rings"] = rings
		entry["ring_phase"] = randf() * TAU
	_hazards.append(entry)
	return entry

## Fragmentation [V9] : le météore se scinde en 2-3 fragments divergents.
func _split_hazard(entry: Dictionary, node: Node2D) -> void:
	var type: Dictionary = entry.get("type", {}) as Dictionary
	var cap: int = maxi(1, int(_get_conf("max_active_hazards", 12)))
	var count: int = randi_range(int(type.get("split_count_min", 2)), int(type.get("split_count_max", 3)))
	count = mini(count, maxi(0, cap + 2 - _hazards.size())) # léger dépassement toléré
	var frag_size: float = maxf(28.0, float(entry.get("size_px", 100.0)) * 0.55)
	var drift_max: float = maxf(40.0, float(type.get("drift_x_px_sec_max", 60.0)))
	if VFXManager:
		VFXManager.spawn_impact(node.global_position, 26.0, self)
	for i in range(count):
		var frag_vx: float = randf_range(0.35, 1.0) * drift_max * (1.0 if i % 2 == 0 else -1.0)
		_add_hazard_entry(type, node.position + Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 10.0)),
			frag_size, frag_vx, true)

## Grappe de mines [V13] : motif compact laissant TOUJOURS un couloir libre
## d'au moins mine_corridor_min_px d'un côté de l'écran.
func _spawn_mine_cluster() -> void:
	var cap: int = maxi(1, int(_get_conf("max_active_hazards", 12)))
	var count: int = randi_range(
		maxi(1, int(_get_conf("mine_cluster_count_min", 4))),
		maxi(1, int(_get_conf("mine_cluster_count_max", 7))))
	count = mini(count, maxi(0, cap + 4 - _hazards.size()))
	if count <= 0:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var corridor: float = maxf(80.0, float(_get_conf("mine_corridor_min_px", 180.0)))
	var span: float = maxf(120.0, viewport_size.x - corridor - 40.0)
	var x0: float = 20.0 if randf() < 0.5 else viewport_size.x - 20.0 - span
	var spawn_y: float = minf(-20.0, float(_get_conf("spawn_y", -140.0)))
	var size: float = maxf(20.0, float(_get_conf("mine_size_px", 46.0)))
	var collision: float = maxf(6.0, float(_get_conf("mine_collision_radius_px", 26.0)))
	var mine_type: Dictionary = {
		"behavior": "mine",
		"collision_ratio": collision / size,
		"tint": Color.WHITE,
		"speed_multiplier": 1.0,
		"damage_percent": clampf(float(_get_conf("mine_damage_percent", 0.12)), 0.0, 1.0),
		"near_miss_mult": 1.0,
		"resources": _resolve_asset_list({"assets": [str(_get_conf("mine_asset", ""))]})
	}
	# Motif : ligne oblique / arc / L (offsets normalisés sur le span).
	var pattern: int = randi() % 3
	for i in range(count):
		var t: float = float(i) / maxf(1.0, float(count - 1))
		var off := Vector2.ZERO
		match pattern:
			0: off = Vector2(t * span, -t * 140.0) # oblique
			1: off = Vector2(t * span, -sin(t * PI) * 160.0) # arc
			_: off = Vector2(minf(t * 2.0, 1.0) * span * 0.5, -maxf(0.0, t - 0.5) * 2.0 * 200.0) # L
		_add_hazard_entry(mine_type, Vector2(x0 + off.x, spawn_y + off.y - 40.0), size, 0.0, false)

## Anneaux des mines : rayon ondulant recalculé dans UNE boucle (pas de tween).
func _animate_mine_rings() -> void:
	for entry in _hazards:
		if not entry.has("rings"):
			continue
		var base_r: float = float(entry.get("size_px", 46.0)) * 0.62
		var r: float = base_r * (1.0 + 0.18 * sin(_time * 4.0 + float(entry.get("ring_phase", 0.0))))
		var pts := PackedVector2Array()
		for k in range(18):
			var a: float = TAU * float(k) / 18.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		for ring_v in (entry.get("rings", []) as Array):
			if ring_v is Line2D and is_instance_valid(ring_v):
				(ring_v as Line2D).points = pts
				(ring_v as Line2D).modulate.a = 0.65 + 0.35 * sin(_time * 5.0 + float(entry.get("ring_phase", 0.0)))

# =============================================================================
# SPAWNING — PICKUPS (chute libre) + SERPENT + POWERUPS
# =============================================================================

## Pickups individuels « volants » : x aléatoire, gravité légère, sway sinueux.
func _spawn_pickup_burst() -> void:
	if _pickup_tiers.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(20.0, float(_get_conf("pickup_side_margin_px", 60.0)))
	var spawn_y: float = minf(-20.0, float(_get_conf("spawn_y", -140.0)))
	var count: int = randi_range(
		maxi(1, int(_get_conf("pickup_spawn_count_min", 1))),
		maxi(1, int(_get_conf("pickup_spawn_count_max", 2))))
	for i in range(count):
		var x: float = randf_range(margin, maxf(margin + 1.0, viewport_size.x - margin))
		_spawn_queue.append({
			"pos": Vector2(x, spawn_y - float(i) * 70.0),
			"tier": _pick_weighted(_pickup_tiers, _pickup_weight_total)
		})

## Serpent vivant [V11] : tête virtuelle au-dessus de l'écran qui ondule et
## FUIT le joueur en X, pondant un pickup à intervalle — le chapelet tombe
## ensuite comme des pickups normaux (chasse au trésor mobile).
func _try_start_snake() -> void:
	if not _snake.is_empty() or _snake_cd > 0.0 or _pickup_tiers.is_empty():
		return
	if randf() > clampf(float(_get_conf("snake_chance", 0.1)), 0.0, 1.0):
		return
	_snake_cd = maxf(4.0, float(_get_conf("snake_cooldown_sec", 18.0)))
	var viewport_size: Vector2 = get_viewport_rect().size
	var tier_idx: int = _pickup_tiers.find(_pick_weighted(_pickup_tiers, _pickup_weight_total))
	var total: int = randi_range(
		maxi(3, int(_get_conf("snake_count_min", 8))),
		maxi(3, int(_get_conf("snake_count_max", 10))))
	_snake = {
		"x": randf_range(viewport_size.x * 0.25, viewport_size.x * 0.75),
		"phase": randf() * TAU,
		"tier_idx": maxi(0, tier_idx),
		"remaining": total,
		"total": total,
		"drop_timer": 0.0
	}

func _tick_snake(dt: float) -> void:
	_snake_cd = maxf(0.0, _snake_cd - dt)
	if _snake.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	# La tête ondule et fuit doucement le X du joueur.
	var flee: float = maxf(0.0, float(_get_conf("snake_flee_px_sec", 45.0)))
	var head_x: float = float(_snake.get("x", viewport_size.x * 0.5))
	if _player and is_instance_valid(_player):
		head_x += signf(head_x - _player.global_position.x) * flee * dt
	_snake["phase"] = float(_snake.get("phase", 0.0)) + dt * TAU * maxf(0.05, float(_get_conf("snake_wave_freq_hz", 0.35)))
	head_x = clampf(head_x, 40.0, viewport_size.x - 40.0)
	_snake["x"] = head_x
	var wave_x: float = head_x + sin(float(_snake["phase"])) * maxf(0.0, float(_get_conf("snake_wave_amp_px", 90.0)))
	wave_x = clampf(wave_x, 24.0, viewport_size.x - 24.0)
	# Ponte : un pickup à intervalle fixe, le scroll espace le chapelet.
	_snake["drop_timer"] = float(_snake.get("drop_timer", 0.0)) - dt
	if float(_snake["drop_timer"]) > 0.0:
		return
	_snake["drop_timer"] = maxf(0.08, float(_get_conf("snake_drop_interval_sec", 0.22)))
	var remaining: int = int(_snake.get("remaining", 0)) - 1
	_snake["remaining"] = remaining
	var tier_idx: int = int(_snake.get("tier_idx", 0))
	if remaining <= 0 and bool(_get_conf("snake_end_bonus", true)):
		tier_idx = mini(tier_idx + 1, _pickup_tiers.size() - 1) # l'étoile brillante en bout
	var spawn_y: float = minf(-20.0, float(_get_conf("spawn_y", -140.0)))
	_spawn_queue.append({"pos": Vector2(wave_x, spawn_y), "tier": _pickup_tiers[tier_idx]})
	if remaining <= 0:
		_snake = {}

## Powerup : tombe comme un pickup (halo + label), effet à la collecte.
func _spawn_powerup() -> void:
	if _powerup_defs.is_empty():
		return
	var def: Dictionary = _pick_weighted(_powerup_defs, _powerup_weight_total)
	if def.is_empty():
		return
	if str(def.get("id", "")) == _last_powerup_id and _powerup_defs.size() > 1:
		var others: Array = _powerup_defs.filter(func(d: Dictionary) -> bool: return str(d.get("id", "")) != _last_powerup_id)
		def = others[randi() % others.size()] as Dictionary
	_last_powerup_id = str(def.get("id", ""))
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(20.0, float(_get_conf("pickup_side_margin_px", 60.0)))
	_spawn_queue.append({
		"pos": Vector2(randf_range(margin, viewport_size.x - margin),
			minf(-20.0, float(_get_conf("spawn_y", -140.0)))),
		"tier": {},
		"powerup": def
	})

## Queued spawns instantiate a few per frame so a burst never costs a full
## multi-sprite hit on one frame (perf guide anti-hitch guard).
func _drain_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		return
	var cap: int = maxi(1, int(_get_conf("max_active_pickups", 40)))
	var budget: int = MAX_PICKUP_SPAWNS_PER_FRAME
	while budget > 0 and not _spawn_queue.is_empty():
		if _pickups.size() >= cap:
			_spawn_queue.clear()
			return
		var pending: Dictionary = _spawn_queue.pop_front() as Dictionary
		_spawn_pickup(pending.get("pos", Vector2.ZERO) as Vector2,
			pending.get("tier", {}) as Dictionary,
			pending.get("powerup", {}) as Dictionary)
		budget -= 1

func _spawn_pickup(at_pos: Vector2, tier: Dictionary, powerup: Dictionary = {}) -> void:
	var is_powerup: bool = not powerup.is_empty()
	if tier.is_empty() and not is_powerup:
		return
	var size_px: float = maxf(20.0, float(_get_conf("powerup_size_px", 46.0))) if is_powerup \
		else float(tier.get("size_px", 40.0))
	var tint: Color = (powerup.get("tint_color", Color.WHITE) as Color) if is_powerup \
		else (tier.get("tint", Color.WHITE) as Color)
	var resources: Array = (powerup.get("resources", []) as Array) if is_powerup \
		else (tier.get("resources", []) as Array)
	var node: Node2D = _build_asset_visual(resources, size_px, tint)
	if is_powerup and resources.is_empty():
		# PH powerup : cercle teinté + initiale du label localisé.
		node = Node2D.new()
		node.add_child(_build_circle_polygon(size_px * 0.5, Color(tint.r, tint.g, tint.b, 0.9)))
		var glyph := Label.new()
		var word: String = _translate_or("sd_lbl_%s" % str(powerup.get("id", "")), str(powerup.get("id", "?")).to_upper())
		glyph.text = word.substr(0, 1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(size_px * 0.55))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(size_px, size_px)
		glyph.position = -Vector2(size_px, size_px) * 0.5
		node.add_child(glyph)
	node.name = "StarDriftPowerup" if is_powerup else "StarDriftPickup"
	node.z_as_relative = false
	node.z_index = 13 if is_powerup else 12
	node.position = at_pos
	add_child(node)
	if is_powerup:
		# Halo additif + label d'effet (béquille lisibilité).
		var halo := Line2D.new()
		halo.closed = true
		halo.width = 4.0
		halo.default_color = Color(tint.r, tint.g, tint.b, 0.7)
		halo.material = _add_material
		var pts := PackedVector2Array()
		for k in range(18):
			var a: float = TAU * float(k) / 18.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.72)
		halo.points = pts
		node.add_child(halo)
		if _effect_labels_enabled():
			_attach_effect_label(node,
				_translate_or("sd_lbl_%s" % str(powerup.get("id", "")), str(powerup.get("id", "?")).to_upper()),
				size_px, tint)
	var entry: Dictionary = {
		"node": node,
		"tier": tier,
		"base_scale": node.scale.x,
		"pulse": randf() * TAU,
		"base_x": at_pos.x,
		"vx": randf_range(-1.0, 1.0) * maxf(0.0, float(_get_conf("pickup_vx_max_px_sec", 60.0))),
		"vy_extra": 0.0,
		"sway_phase": randf() * TAU
	}
	if is_powerup:
		entry["powerup"] = powerup
	_pickups.append(entry)

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
	# L'événement « alignement de quasars » a besoin de 2 colonnes simultanées.
	if float(_get_conf("quasar_align_weight", 0.0)) > 0.0:
		slot_count = maxi(slot_count, 2)
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

## x_forced/telegraph_override : utilisés par l'alignement de quasars [E16].
func _try_trigger_quasar(x_forced: float = NAN, telegraph_override: float = -1.0) -> bool:
	for i in range(_quasar_slots.size()):
		var slot: Dictionary = _quasar_slots[i]
		if int(slot.get("state", QuasarState.IDLE)) != QuasarState.IDLE:
			continue
		var viewport_size: Vector2 = get_viewport_rect().size
		var margin: float = maxf(20.0, float(_get_conf("quasar_side_margin_px", 90.0)))
		var x: float = x_forced if not is_nan(x_forced) \
			else randf_range(margin, maxf(margin + 1.0, viewport_size.x - margin))
		var pts := PackedVector2Array([Vector2(x, -40.0), Vector2(x, viewport_size.y + 40.0)])
		var telegraph: Line2D = slot.get("telegraph") as Line2D
		telegraph.points = pts
		telegraph.visible = true
		(slot.get("glow") as Line2D).points = pts
		(slot.get("core") as Line2D).points = pts
		slot["state"] = QuasarState.TELEGRAPH
		slot["timer"] = telegraph_override if telegraph_override > 0.0 \
			else maxf(0.2, float(_get_conf("quasar_telegraph_sec", 1.1)))
		slot["x"] = x
		_quasar_slots[i] = slot
		return true
	return false

func _any_quasar_busy() -> bool:
	for slot in _quasar_slots:
		if int((slot as Dictionary).get("state", QuasarState.IDLE)) != QuasarState.IDLE:
			return true
	return false

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
			if not _any_invuln() and _player and is_instance_valid(_player) \
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
	_trail_glow_base_color = _trail_glow.default_color

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
	_tick_buffs(dt)

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
				_pickup_timer -= dt
				if _pickup_timer <= 0.0:
					_pickup_timer = _current_pickup_interval()
					_spawn_pickup_burst()
					_try_start_snake()
				_powerup_timer -= dt
				if _powerup_timer <= 0.0:
					_powerup_timer = randf_range(
						maxf(3.0, float(_get_conf("powerup_interval_sec_min", 14.0))),
						maxf(3.0, float(_get_conf("powerup_interval_sec_max", 22.0))))
					_spawn_powerup()
				if bool(_get_conf("mines_enabled", true)):
					_mine_timer -= dt
					if _mine_timer <= 0.0:
						_mine_timer = _current_mine_interval()
						_spawn_mine_cluster()
				# Le quasar normal est suspendu pendant l'alignement [E16].
				if not _quasar_slots.is_empty() and _event_active != "quasar_align":
					_quasar_timer -= dt
					if _quasar_timer <= 0.0:
						_quasar_timer = _current_quasar_interval()
						_try_trigger_quasar()
				_tick_event_scheduler(dt)
			_tick_snake(dt)

	_tick_active_event(dt)
	_drain_spawn_queue()
	var speed: float = _current_scroll_speed()
	_update_hazards(dt, speed)
	_update_pickups(dt, speed)
	_update_quasars(dt)
	_update_ship_trail()
	_animate_mine_rings()
	_update_buff_icons()
	_update_shield_halo()

	if _elapsed >= _duration:
		_finish()

# =============================================================================
# BUFFS (powerups actifs) + INVULNÉRABILITÉ UNIFIÉE
# =============================================================================

func _any_invuln() -> bool:
	return _hit_invuln_timer > 0.0 or _star_invuln_timer > 0.0 \
		or _dash_iframe_timer > 0.0 or _shield_grace_timer > 0.0

## Une seule source de vérité pour set_invincible : le max des 4 timers.
func _sync_player_invuln() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_invincible"):
		_player.call("set_invincible", _any_invuln())

func _tick_buffs(dt: float) -> void:
	var was_star: bool = _star_invuln_timer > 0.0
	_hit_invuln_timer = maxf(0.0, _hit_invuln_timer - dt)
	_star_invuln_timer = maxf(0.0, _star_invuln_timer - dt)
	_dash_iframe_timer = maxf(0.0, _dash_iframe_timer - dt)
	_shield_grace_timer = maxf(0.0, _shield_grace_timer - dt)
	_magnet_timer = maxf(0.0, _magnet_timer - dt)
	# Étoile filante : traînée dorée le temps de l'effet.
	if was_star and _star_invuln_timer <= 0.0 and _trail_glow and is_instance_valid(_trail_glow):
		_trail_glow.default_color = _trail_glow_base_color
	# Dash actif : déplacement étalé sur time_sec via le canal externe du Player.
	if _dash_active_timer > 0.0:
		_dash_active_timer = maxf(0.0, _dash_active_timer - dt)
		if _player and is_instance_valid(_player) and _player.has_method("apply_external_displacement"):
			_player.call("apply_external_displacement", _dash_dir * _dash_speed_px_sec * dt)
	_sync_player_invuln()

## Double-tap = dash (lecture passive : l'event n'est jamais consommé, le
## finger-follow de Player.gd reste intact).
func _input(event: InputEvent) -> void:
	if _state != State.RUN or _dash_charges <= 0:
		return
	var tap_pos := Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		tap_pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		tap_pos = (event as InputEventMouseButton).position
	if tap_pos == Vector2.INF:
		return
	var def: Dictionary = _find_powerup_def("dash")
	var now: int = Time.get_ticks_msec()
	var window_msec: int = int(maxf(0.05, float(def.get("double_tap_sec", 0.3))) * 1000.0)
	var max_dist: float = maxf(10.0, float(def.get("double_tap_dist_px", 60.0)))
	if now - _last_tap_msec <= window_msec and _last_tap_pos.distance_to(tap_pos) <= max_dist:
		_last_tap_msec = -100000
		_do_dash(def, tap_pos)
	else:
		_last_tap_msec = now
		_last_tap_pos = tap_pos

func _find_powerup_def(id: String) -> Dictionary:
	for def_v in _powerup_defs:
		if str((def_v as Dictionary).get("id", "")) == id:
			return def_v as Dictionary
	return {}

func _do_dash(def: Dictionary, tap_pos: Vector2) -> void:
	if _dash_charges <= 0 or _player == null or not is_instance_valid(_player):
		return
	_dash_charges -= 1
	var dist: float = maxf(60.0, float(def.get("distance_px", 260.0)))
	var time_sec: float = maxf(0.05, float(def.get("time_sec", 0.12)))
	# Direction : vers le tap (intuitif écran tactile), fallback vers le haut.
	var dir: Vector2 = (tap_pos - _player.global_position)
	_dash_dir = dir.normalized() if dir.length() > 8.0 else Vector2.UP
	_dash_speed_px_sec = dist / time_sec
	_dash_active_timer = time_sec
	_dash_iframe_timer = maxf(time_sec, float(def.get("iframes_sec", 0.35)))
	_sync_player_invuln()
	if VFXManager:
		VFXManager.flash_sprite(_player, Color(0.7, 1.0, 1.0), 0.15)
		VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -50.0),
			_translate_or("sd_pw_dash", "DASH!"), Color("#9AF6FF"), self)

func _apply_powerup(def: Dictionary, at_pos: Vector2) -> void:
	var id: String = str(def.get("id", ""))
	match id:
		"shooting_star":
			_star_invuln_timer = maxf(0.5, float(def.get("invuln_sec", 3.0)))
			if _trail_glow and is_instance_valid(_trail_glow):
				_trail_glow.default_color = Color("#FFD866D0")
		"dash":
			_dash_charges = mini(_dash_charges + 1, maxi(1, int(def.get("charges_max", 1))))
		"magnet":
			_magnet_timer = maxf(1.0, float(def.get("duration_sec", 16.0)))
		"shield":
			_shield_charges = mini(_shield_charges + 1, maxi(1, int(def.get("charges_max", 1))))
	_sync_player_invuln()
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos + Vector2(0.0, -40.0),
			_translate_or("sd_pw_%s" % id, id.to_upper()),
			def.get("tint_color", Color.WHITE) as Color, self)
		if _player and is_instance_valid(_player):
			VFXManager.flash_sprite(_player, Color(1.0, 1.0, 1.0), 0.15)

## Halo du bouclier stellaire : cercle qui suit le vaisseau tant qu'une charge
## est disponible.
func _update_shield_halo() -> void:
	var want: bool = _shield_charges > 0 and _player != null and is_instance_valid(_player)
	if not want:
		if _shield_halo and is_instance_valid(_shield_halo):
			_shield_halo.queue_free()
		_shield_halo = null
		return
	if _shield_halo == null or not is_instance_valid(_shield_halo):
		_shield_halo = Node2D.new()
		_shield_halo.z_as_relative = false
		_shield_halo.z_index = 57
		var def: Dictionary = _find_powerup_def("shield")
		var ring := Line2D.new()
		ring.closed = true
		ring.width = 4.0
		ring.default_color = Color(str(def.get("halo_color", "#7FE58CB4")))
		ring.material = _add_material
		var pts := PackedVector2Array()
		for k in range(22):
			var a: float = TAU * float(k) / 22.0
			pts.append(Vector2(cos(a), sin(a)) * (PLAYER_HALF_SIZE_PX + 16.0))
		ring.points = pts
		_shield_halo.add_child(ring)
		add_child(_shield_halo)
	_shield_halo.position = to_local(_player.global_position)
	_shield_halo.scale = Vector2.ONE * (1.0 + 0.08 * sin(_time * 5.0))

# =============================================================================
# HUD BAS-DROITE : icônes des buffs actifs (temps restant / charges)
# =============================================================================

func _ensure_buff_bar() -> void:
	if _buff_bar and is_instance_valid(_buff_bar):
		return
	_buff_bar = Node2D.new()
	_buff_bar.name = "StarDriftBuffBar"
	_buff_bar.z_as_relative = false
	_buff_bar.z_index = 61
	add_child(_buff_bar)

func _build_buff_icon(def: Dictionary) -> Dictionary:
	var radius: float = maxf(16.0, float(_get_conf("buff_icon_radius_px", 34.0)))
	var tint: Color = def.get("tint_color", Color.WHITE) as Color
	var root := Node2D.new()
	var resources: Array = def.get("resources", []) as Array
	if not resources.is_empty():
		root.add_child(_build_asset_visual(resources, radius * 2.0, Color.WHITE))
	else:
		root.add_child(_build_circle_polygon(radius, Color(tint.r, tint.g, tint.b, 0.85)))
		var glyph := Label.new()
		var word: String = _translate_or("sd_lbl_%s" % str(def.get("id", "")), str(def.get("id", "?")).to_upper())
		glyph.text = word.substr(0, 1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(radius))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(radius, radius) * 2.0
		glyph.position = -Vector2(radius, radius)
		root.add_child(glyph)
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("buff_icon_font_size", 20))))
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 5)
	badge.size = Vector2(radius * 2.0, 24.0)
	badge.position = Vector2(-radius, radius + 2.0)
	root.add_child(badge)
	_buff_bar.add_child(root)
	return {"root": root, "badge": badge}

## Icônes = état courant des buffs : timés (temps restant) et charges (×N).
## Reconstruction légère : ajout/retrait au changement, badges chaque frame.
func _update_buff_icons() -> void:
	var active: Dictionary = {} # id -> badge text
	if _star_invuln_timer > 0.0:
		active["shooting_star"] = str(int(ceil(_star_invuln_timer)))
	if _magnet_timer > 0.0:
		active["magnet"] = str(int(ceil(_magnet_timer)))
	if _dash_charges > 0:
		active["dash"] = "×%d" % _dash_charges
	if _shield_charges > 0:
		active["shield"] = "×%d" % _shield_charges
	# Retraits.
	for id in _buff_icons.keys().duplicate():
		if not active.has(id):
			var icon: Dictionary = _buff_icons[id]
			var root_v: Variant = icon.get("root", null)
			if root_v is Node2D and is_instance_valid(root_v):
				(root_v as Node2D).queue_free()
			_buff_icons.erase(id)
	if active.is_empty():
		return
	_ensure_buff_bar()
	# Ajouts.
	for id in active:
		if not _buff_icons.has(id):
			var def: Dictionary = _find_powerup_def(str(id))
			if def.is_empty():
				continue
			_buff_icons[id] = _build_buff_icon(def)
	# Placement bas-droite (empilés vers la gauche) + badge.
	var viewport_size: Vector2 = get_viewport_rect().size
	var gap: float = maxf(40.0, float(_get_conf("buff_icon_gap_px", 78.0)))
	var margin: float = maxf(8.0, float(_get_conf("buff_icon_margin_px", 24.0)))
	var bottom_off: float = maxf(40.0, float(_get_conf("buff_icon_bottom_offset_px", 150.0)))
	var radius: float = maxf(16.0, float(_get_conf("buff_icon_radius_px", 34.0)))
	var slot: int = 0
	for id in active:
		if not _buff_icons.has(id):
			continue
		var icon: Dictionary = _buff_icons[id]
		var root_v: Variant = icon.get("root", null)
		if root_v is Node2D and is_instance_valid(root_v):
			(root_v as Node2D).position = Vector2(
				viewport_size.x - margin - radius - gap * float(slot),
				viewport_size.y - bottom_off)
		var badge_v: Variant = icon.get("badge", null)
		if badge_v is Label and is_instance_valid(badge_v):
			(badge_v as Label).text = str(active[id])
		slot += 1

# =============================================================================
# ÉVÉNEMENTS (toasts centraux, un seul actif à la fois)
# =============================================================================

func _tick_event_scheduler(dt: float) -> void:
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(
		maxf(5.0, float(_get_conf("event_interval_sec_min", 18.0))),
		maxf(5.0, float(_get_conf("event_interval_sec_max", 28.0))))
	if _event_active != "" or _elapsed < maxf(0.0, float(_get_conf("event_first_delay_sec", 12.0))):
		return
	var weights: Dictionary = {
		"meteor_rain": float(_get_conf("meteor_rain_weight", 25.0)),
		"supernova": float(_get_conf("supernova_weight", 20.0)),
		"quasar_align": float(_get_conf("quasar_align_weight", 20.0)),
		"guide_comet": float(_get_conf("guide_comet_weight", 20.0)),
		"constellation": float(_get_conf("constellation_weight", 15.0))
	}
	# L'alignement exige 2 slots quasar libres.
	if _quasar_slots.size() < 2 or _any_quasar_busy():
		weights.erase("quasar_align")
	for key in weights.keys().duplicate():
		if float(weights[key]) <= 0.0:
			weights.erase(key)
	if weights.size() > 1:
		weights.erase(_last_event_id)
	if weights.is_empty():
		return
	var total: float = 0.0
	for key in weights:
		total += float(weights[key])
	var roll: float = randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			_last_event_id = str(key)
			_start_event(str(key))
			return

func _start_event(event_id: String) -> void:
	_event_active = event_id
	_event = {}
	match event_id:
		"meteor_rain":
			_toast("sd_evt_meteor_rain", "METEOR RAIN!", "#FF8A5A")
			var viewport_size: Vector2 = get_viewport_rect().size
			var left_half: bool = randf() < 0.5
			var rect := Polygon2D.new()
			var x0: float = 0.0 if left_half else viewport_size.x * 0.5
			rect.polygon = PackedVector2Array([
				Vector2(x0, 0.0), Vector2(x0 + viewport_size.x * 0.5, 0.0),
				Vector2(x0 + viewport_size.x * 0.5, viewport_size.y), Vector2(x0, viewport_size.y)])
			rect.color = Color(str(_get_conf("meteor_rain_telegraph_color", "#FF5A5A2E")))
			rect.z_as_relative = false
			rect.z_index = 50
			add_child(rect)
			_event = {
				"phase": "telegraph",
				"timer": maxf(0.3, float(_get_conf("meteor_rain_telegraph_sec", 1.5))),
				"rect": rect,
				"half_min": 0.0 if left_half else 0.5,
				"half_max": 0.5 if left_half else 1.0,
				"remaining": maxi(4, int(_get_conf("meteor_rain_count", 12))),
				"drop_timer": 0.0
			}
		"supernova":
			var target_idx: int = _find_supernova_target()
			if target_idx < 0:
				_event_active = "" # aucun météore éligible : on repassera
				return
			_toast("sd_evt_supernova", "SUPERNOVA!", "#FFD866")
			var entry: Dictionary = _hazards[target_idx]
			var node: Node2D = entry.get("node") as Node2D
			var ring := Line2D.new()
			ring.closed = true
			ring.width = 6.0
			ring.default_color = Color("#FFD866C8")
			ring.material = _add_material
			var pts := PackedVector2Array()
			for k in range(20):
				var a: float = TAU * float(k) / 20.0
				pts.append(Vector2(cos(a), sin(a)) * float(entry.get("size_px", 90.0)) * 0.7)
			ring.points = pts
			node.add_child(ring)
			entry["nova_ring"] = ring
			_hazards[target_idx] = entry
			_event = {
				"timer": maxf(0.5, float(_get_conf("supernova_telegraph_sec", 2.2))),
				"node": node
			}
		"quasar_align":
			_toast("sd_evt_quasar_align", "QUASAR ALIGNMENT!", "#B455E8")
			var viewport_size2: Vector2 = get_viewport_rect().size
			var gap: float = maxf(120.0, float(_get_conf("quasar_align_gap_px", 240.0)))
			var width: float = maxf(12.0, float(_get_conf("quasar_width_px", 90.0)))
			var center_x: float = randf_range(viewport_size2.x * 0.35, viewport_size2.x * 0.65)
			var telegraph: float = maxf(0.5, float(_get_conf("quasar_align_telegraph_sec", 1.8)))
			var offset: float = gap * 0.5 + width * 0.5
			_try_trigger_quasar(clampf(center_x - offset, width * 0.5, viewport_size2.x - width * 0.5), telegraph)
			_try_trigger_quasar(clampf(center_x + offset, width * 0.5, viewport_size2.x - width * 0.5), telegraph)
			_event = {"phase": "watch"}
		"guide_comet":
			_toast("sd_evt_guide_comet", "GUIDE COMET!", "#FFD866")
			var viewport_size3: Vector2 = get_viewport_rect().size
			var comet_type: Dictionary = _find_hazard_type_by_behavior("comet")
			var node2 := Node2D.new()
			node2.z_as_relative = false
			node2.z_index = 14
			var visual: Node2D = _build_asset_visual(
				(comet_type.get("resources", []) as Array) if not comet_type.is_empty() else [],
				70.0, Color("#FFD866"))
			node2.add_child(visual)
			node2.position = Vector2(randf_range(viewport_size3.x * 0.25, viewport_size3.x * 0.75), -60.0)
			add_child(node2)
			_event = {
				"node": node2,
				"t": 0.0,
				"x0": node2.position.x,
				"crystal_timer": 0.0
			}
		"constellation":
			_toast("sd_evt_constellation", "CONSTELLATION!", "#9AF6FF")
			_build_constellation()

func _find_supernova_target() -> int:
	var min_size: float = maxf(40.0, float(_get_conf("supernova_min_size_px", 90.0)))
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(_hazards.size()):
		var entry: Dictionary = _hazards[i]
		if str((entry.get("type", {}) as Dictionary).get("behavior", "")) != "meteor":
			continue
		if float(entry.get("size_px", 0.0)) < min_size or entry.has("is_fragment"):
			continue
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v) \
			and (node_v as Node2D).position.y > 0.0 and (node_v as Node2D).position.y < viewport_size.y * 0.6:
			return i
	return -1

func _find_hazard_type_by_behavior(behavior: String) -> Dictionary:
	for type_v in _hazard_types:
		if str((type_v as Dictionary).get("behavior", "")) == behavior:
			return type_v as Dictionary
	return {}

## Constellation [V12] : étoiles numérotées reliées par un trait fin, à
## collecter DANS L'ORDRE avant qu'elles sortent de l'écran.
func _build_constellation() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var count: int = randi_range(
		maxi(2, int(_get_conf("constellation_star_count_min", 3))),
		maxi(2, int(_get_conf("constellation_star_count_max", 5))))
	var size_px: float = maxf(24.0, float(_get_conf("constellation_star_size_px", 52.0)))
	var spacing: float = maxf(80.0, float(_get_conf("constellation_spacing_px", 170.0)))
	var star_res: Array = _resolve_asset_list({"assets": [str(_get_conf("constellation_star_asset", ""))]})
	var link := Line2D.new()
	link.width = 2.0
	link.default_color = Color(str(_get_conf("constellation_link_color", "#9AF6FF80")))
	link.z_as_relative = false
	link.z_index = 11
	add_child(link)
	var stars: Array = []
	var x: float = randf_range(viewport_size.x * 0.25, viewport_size.x * 0.75)
	for i in range(count):
		var node := Node2D.new()
		node.z_as_relative = false
		node.z_index = 12
		var visual: Node2D = _build_asset_visual(star_res, size_px, Color("#9AF6FF"))
		node.add_child(visual)
		var number := Label.new()
		number.text = str(i + 1)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.add_theme_font_size_override("font_size", int(size_px * 0.6))
		number.add_theme_color_override("font_color", Color.WHITE)
		number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		number.add_theme_constant_override("outline_size", 5)
		number.size = Vector2(size_px, size_px)
		number.position = -Vector2(size_px, size_px) * 0.5
		node.add_child(number)
		x = clampf(x + randf_range(-160.0, 160.0), 60.0, viewport_size.x - 60.0)
		node.position = Vector2(x, minf(-20.0, float(_get_conf("spawn_y", -140.0))) - spacing * float(i))
		add_child(node)
		stars.append({"node": node, "index": i, "done": false})
	_event = {"stars": stars, "link": link, "next": 0}

## Fin d'événement : purge les nodes de travail restants.
func _end_event() -> void:
	var rect_v: Variant = _event.get("rect", null)
	if rect_v is Node2D and is_instance_valid(rect_v):
		(rect_v as Node2D).queue_free()
	var node_v: Variant = _event.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v) and _event_active == "guide_comet":
		(node_v as Node2D).queue_free()
	var link_v: Variant = _event.get("link", null)
	if link_v is Line2D and is_instance_valid(link_v):
		(link_v as Line2D).queue_free()
	var stars_v: Variant = _event.get("stars", null)
	if stars_v is Array:
		for star_v in (stars_v as Array):
			var star_node_v: Variant = (star_v as Dictionary).get("node", null)
			if star_node_v is Node2D and is_instance_valid(star_node_v):
				(star_node_v as Node2D).queue_free()
	_event_active = ""
	_event = {}

func _tick_active_event(dt: float) -> void:
	if _event_active == "":
		return
	match _event_active:
		"meteor_rain":
			_tick_meteor_rain(dt)
		"supernova":
			_tick_supernova(dt)
		"quasar_align":
			if not _any_quasar_busy():
				_end_event()
		"guide_comet":
			_tick_guide_comet(dt)
		"constellation":
			_tick_constellation(dt)

func _tick_meteor_rain(dt: float) -> void:
	if str(_event.get("phase", "")) == "telegraph":
		var rect_v: Variant = _event.get("rect", null)
		if rect_v is Polygon2D and is_instance_valid(rect_v):
			(rect_v as Polygon2D).modulate.a = 0.6 + 0.4 * sin(_time * TAU * 3.0)
		_event["timer"] = float(_event.get("timer", 0.0)) - dt
		if float(_event["timer"]) <= 0.0:
			if rect_v is Polygon2D and is_instance_valid(rect_v):
				(rect_v as Polygon2D).queue_free()
			_event.erase("rect")
			_event["phase"] = "rain"
			_event["drop_timer"] = 0.0
		return
	# Pluie : les météores tombent UNIQUEMENT sur la moitié télégraphée.
	_event["drop_timer"] = float(_event.get("drop_timer", 0.0)) - dt
	if float(_event["drop_timer"]) > 0.0:
		return
	var remaining: int = int(_event.get("remaining", 0))
	if remaining <= 0:
		_end_event()
		return
	var spread: float = maxf(0.5, float(_get_conf("meteor_rain_spread_sec", 2.0)))
	_event["drop_timer"] = spread / maxf(1.0, float(_get_conf("meteor_rain_count", 12)))
	_event["remaining"] = remaining - 1
	_spawn_hazard(float(_event.get("half_min", 0.0)), float(_event.get("half_max", 1.0)), "meteor")

func _tick_supernova(dt: float) -> void:
	var node_v: Variant = _event.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		_end_event() # la cible est sortie de l'écran avant d'exploser
		return
	var node: Node2D = node_v as Node2D
	_event["timer"] = float(_event.get("timer", 0.0)) - dt
	if float(_event["timer"]) > 0.0:
		return
	# Explosion : la cible disparaît, cercle de projectiles lents.
	var at: Vector2 = node.global_position
	for i in range(_hazards.size() - 1, -1, -1):
		if (_hazards[i] as Dictionary).get("node", null) == node:
			node.queue_free()
			_hazards.remove_at(i)
			break
	if VFXManager:
		VFXManager.spawn_explosion(at, 110.0, Color(1.0, 0.85, 0.4), self,
			"", "res://assets/vfx/boss_explosion.tres", -1.0, 0.3, 0.5, false)
		VFXManager.screen_shake(6.0, 0.3)
	var count: int = maxi(4, int(_get_conf("supernova_projectile_count", 10)))
	var speed: float = maxf(40.0, float(_get_conf("supernova_projectile_speed_px_sec", 150.0)))
	var proj_size: float = maxf(10.0, float(_get_conf("supernova_projectile_size_px", 20.0)))
	var proj_type: Dictionary = {
		"behavior": "projectile",
		"collision_ratio": 0.42,
		"tint": Color("#FFB84D"),
		"speed_multiplier": 0.0,
		"damage_percent": clampf(float(_get_conf("supernova_projectile_damage_percent", 0.08)), 0.0, 1.0),
		"near_miss_mult": 1.0,
		"resources": []
	}
	for i in range(count):
		var dir: Vector2 = Vector2.from_angle(TAU * float(i) / float(count))
		var entry: Dictionary = _add_hazard_entry(proj_type, at + dir * 20.0, proj_size, 0.0, false)
		entry["pvel"] = dir * speed
	_end_event()

func _tick_guide_comet(dt: float) -> void:
	var node_v: Variant = _event.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		_end_event()
		return
	var node: Node2D = node_v as Node2D
	var t: float = float(_event.get("t", 0.0)) + dt
	_event["t"] = t
	var viewport_size: Vector2 = get_viewport_rect().size
	node.position.y += maxf(60.0, float(_get_conf("guide_comet_speed_px_sec", 240.0))) * dt
	node.position.x = clampf(
		float(_event.get("x0", viewport_size.x * 0.5))
			+ sin(t * TAU * maxf(0.05, float(_get_conf("guide_comet_sway_freq_hz", 0.3))))
			* maxf(0.0, float(_get_conf("guide_comet_sway_amp_px", 160.0))),
		40.0, viewport_size.x - 40.0)
	# Sème un cristal aimanté à intervalle : le rail volontaire à suivre.
	_event["crystal_timer"] = float(_event.get("crystal_timer", 0.0)) - dt
	if float(_event["crystal_timer"]) <= 0.0:
		_event["crystal_timer"] = maxf(0.15, float(_get_conf("guide_comet_crystal_interval_sec", 0.4)))
		if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", node.global_position, {"force_magnet_after_sec": 2.5})
	if t >= maxf(1.0, float(_get_conf("guide_comet_sec", 5.0))) or node.position.y > viewport_size.y + 80.0:
		_end_event()

func _tick_constellation(dt: float) -> void:
	var stars_v: Variant = _event.get("stars", null)
	if not (stars_v is Array) or (stars_v as Array).is_empty():
		_end_event()
		return
	var stars: Array = stars_v as Array
	var viewport_size: Vector2 = get_viewport_rect().size
	var speed: float = _current_scroll_speed()
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 52.0))) + 10.0
	var player_pos: Vector2 = _player.global_position
	var next: int = int(_event.get("next", 0))
	var link_pts := PackedVector2Array()
	var any_alive: bool = false
	for star_v in stars:
		var star: Dictionary = star_v as Dictionary
		if bool(star.get("done", false)):
			continue
		var node_v: Variant = star.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var node: Node2D = node_v as Node2D
		node.position.y += speed * dt
		if node.position.y > viewport_size.y + 40.0:
			_end_event() # une étoile est sortie : constellation ratée (sans malus)
			return
		any_alive = true
		link_pts.append(node.position)
		# Pulse plus marqué sur la PROCHAINE étoile à relier.
		node.scale = Vector2.ONE * (1.0 + (0.22 if int(star.get("index", 0)) == next else 0.06) * sin(_time * TAU * 1.8))
		if node.global_position.distance_to(player_pos) <= pickup_radius:
			if int(star.get("index", 0)) == next:
				star["done"] = true
				node.visible = false
				_event["next"] = next + 1
				if VFXManager:
					VFXManager.spawn_impact(node.global_position, 20.0, self)
				if int(_event["next"]) >= stars.size():
					_toast("sd_evt_constellation_done", "CONSTELLATION LINKED!", "#7CFC9A")
					if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
						_game.call("spawn_reward_crystals_from_top", maxi(1, int(_get_conf("constellation_crystals", 6))))
					_end_event()
					return
			else:
				# Mauvais ordre : simple score, la constellation s'éteint (jamais punitif).
				if _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
					_game.call("add_wave_bonus_score", int(round(15.0 * _reward_multiplier)), node.global_position)
				_end_event()
				return
	var link_v: Variant = _event.get("link", null)
	if link_v is Line2D and is_instance_valid(link_v):
		(link_v as Line2D).points = link_pts
	if not any_alive:
		_end_event()

# =============================================================================
# UPDATES — HAZARDS / PICKUPS
# =============================================================================

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
		var behavior: String = str(type.get("behavior", "meteor"))

		if behavior == "projectile":
			# Projectile supernova : ligne droite lente, despawn hors écran.
			node.position += (entry.get("pvel", Vector2.ZERO) as Vector2) * dt
		elif behavior == "comet":
			# Comète traversante : diagonale rapide, pas de rebond de bord.
			node.position.x += float(entry.get("vx", 0.0)) * dt
			node.position.y += float(type.get("comet_fall_px_sec", 120.0)) * dt
		else:
			node.position.y += speed * float(type.get("speed_multiplier", 1.0)) * dt
			# Horizontal drift + sine wobble; soft bounce on the screen edges.
			var vx: float = float(entry.get("vx", 0.0))
			var base_x: float = float(entry.get("base_x", node.position.x)) + vx * dt
			if base_x < 20.0 or base_x > viewport_size.x - 20.0:
				vx = -vx
				entry["vx"] = vx
				base_x = clampf(base_x, 20.0, viewport_size.x - 20.0)
				# Fragmentation [V9] : le gros météore se scinde au rebond.
				if behavior == "meteor" and not entry.has("is_fragment") \
					and float(entry.get("size_px", 0.0)) >= float(type.get("split_min_size_px", 100.0)) \
					and randf() <= float(type.get("split_on_edge_chance", 0.0)):
					_split_hazard(entry, node)
					node.queue_free()
					_hazards.remove_at(i)
					continue
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

		# Attraction trou noir / répulsion trou BLANC [V7] — toujours échappable.
		var pull_radius: float = float(type.get("pull_radius_px", 0.0))
		if pull_radius > 0.0 and dist < pull_radius and dist > 1.0:
			var pull: float = float(type.get("pull_strength_px_sec", 0.0)) * (1.0 - dist / pull_radius) * dt
			if pull > 0.0 and _player.has_method("apply_external_displacement"):
				var pull_dir: Vector2 = (node.global_position - player_pos).normalized()
				if behavior == "white_hole":
					pull_dir = -pull_dir
				_player.call("apply_external_displacement", pull_dir * pull)

		# Contact: manual distance check against the ship (radius rolled at spawn).
		var radius: float = float(entry.get("radius", 36.0))
		if not bool(entry.get("hit", false)) and not _any_invuln() \
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
				_check_near_miss(float(entry.get("min_dist", INF)), node.global_position,
					float(type.get("near_miss_mult", 1.0)))

		_hazards[i] = entry
		# Despawn : bas d'écran, ou sortie latérale (comètes/projectiles).
		var out_margin: float = float(entry.get("size_px", 88.0)) + 60.0
		if node.position.y > viewport_size.y + out_margin \
			or node.position.x < -out_margin or node.position.x > viewport_size.x + out_margin \
			or node.position.y < -out_margin - 400.0:
			if behavior == "comet" and not bool(entry.get("hit", false)) and not bool(entry.get("passed", false)):
				_check_near_miss(float(entry.get("min_dist", INF)), node.global_position,
					float(type.get("near_miss_mult", 1.0)))
			node.queue_free()
			_hazards.remove_at(i)

## Damage: % of max HP through the standard pipeline (shield first). Ordre de
## résolution : invuln (étoile/dash/grace/hit) > charge de bouclier stellaire >
## dégâts + fenêtre d'invuln partagée.
func _damage_player(damage_percent: float) -> void:
	if _any_invuln():
		return
	if _shield_charges > 0:
		_shield_charges -= 1
		_shield_grace_timer = maxf(0.2, float(_find_powerup_def("shield").get("grace_sec", 0.6)))
		_sync_player_invuln()
		if VFXManager and _player and is_instance_valid(_player):
			VFXManager.flash_sprite(_player, Color(0.6, 1.0, 0.7), 0.25)
			VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -60.0),
				_translate_or("sd_shield_used", "ABSORBED!"), Color("#7FE58C"), self)
		return
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * clampf(damage_percent, 0.0, 1.0)))))
	if _player == null or not is_instance_valid(_player):
		return # the hit was lethal
	_hit_invuln_timer = maxf(0.2, float(_get_conf("hit_invuln_sec", 1.0)))
	_sync_player_invuln()
	if VFXManager:
		VFXManager.screen_shake(6, 0.2)

## Near-miss: the hazard brushed past the ship without touching it -> crystal
## chance (skill reward; les comètes traversantes paient double).
func _check_near_miss(min_dist: float, at_pos: Vector2, chance_mult: float = 1.0) -> void:
	if min_dist > maxf(0.0, float(_get_conf("near_miss_distance_px", 70.0))) + PLAYER_HALF_SIZE_PX:
		return
	var chance: float = clampf(float(_get_conf("near_miss_crystal_chance", 0.3)) * maxf(0.1, chance_mult), 0.0, 1.0)
	if randf() > chance:
		return
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", Vector2(at_pos.x, _player.global_position.y))

## Pickups en CHUTE LIBRE : suivent le scroll + gravité légère (toujours vers
## le bas), sway sinueux + dérive X avec rebond doux — ils « volent » dans le
## décor au lieu de former un chemin.
func _update_pickups(dt: float, speed: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_pos: Vector2 = _player.global_position
	var pickup_radius: float = maxf(16.0, float(_get_conf("pickup_radius_px", 52.0)))
	var pulse_hz: float = maxf(0.1, float(_get_conf("pickup_pulse_hz", 1.6)))
	var fall_mult: float = maxf(0.1, float(_get_conf("pickup_fall_speed_mult", 0.85)))
	var gravity: float = maxf(0.0, float(_get_conf("pickup_gravity_px_sec2", 55.0)))
	var extra_cap: float = maxf(0.0, float(_get_conf("pickup_fall_extra_max_px_sec", 160.0)))
	var sway_amp: float = maxf(0.0, float(_get_conf("pickup_sway_amp_px", 50.0)))
	var sway_hz: float = maxf(0.0, float(_get_conf("pickup_sway_freq_hz", 0.4)))
	var magnet_def: Dictionary = _find_powerup_def("magnet") if _magnet_timer > 0.0 else {}
	var magnet_radius: float = maxf(40.0, float(magnet_def.get("radius_px", 340.0))) if not magnet_def.is_empty() else 0.0
	var magnet_pull: float = maxf(100.0, float(magnet_def.get("pull_px_sec", 900.0))) if not magnet_def.is_empty() else 0.0
	# Étoile filante : la traînée dorée collecte au passage.
	var star_collect_radius: float = 0.0
	if _star_invuln_timer > 0.0:
		star_collect_radius = maxf(20.0, float(_find_powerup_def("shooting_star").get("trail_collect_radius_px", 70.0)))
	for i in range(_pickups.size() - 1, -1, -1):
		var entry: Dictionary = _pickups[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		# Chute : scroll x mult + accélération gravitaire capée (jamais vers le haut).
		var vy_extra: float = minf(extra_cap, float(entry.get("vy_extra", 0.0)) + gravity * dt)
		entry["vy_extra"] = vy_extra
		node.position.y += (speed * fall_mult + vy_extra) * dt
		# Dérive X + rebond doux, sway sinusoïdal par-dessus.
		var vx: float = float(entry.get("vx", 0.0))
		var base_x: float = float(entry.get("base_x", node.position.x)) + vx * dt
		if base_x < 24.0 or base_x > viewport_size.x - 24.0:
			vx = -vx
			entry["vx"] = vx
			base_x = clampf(base_x, 24.0, viewport_size.x - 24.0)
		entry["base_x"] = base_x
		node.position.x = base_x + (sin(_time * TAU * sway_hz + float(entry.get("sway_phase", 0.0))) * sway_amp if sway_amp > 0.0 and sway_hz > 0.0 else 0.0)
		# Aimant global : attraction franche vers le vaisseau.
		var dist: float = node.global_position.distance_to(player_pos)
		if magnet_radius > 0.0 and dist <= magnet_radius and dist > 1.0:
			node.global_position = node.global_position.move_toward(player_pos, magnet_pull * dt)
			dist = node.global_position.distance_to(player_pos)
		# Gentle pulse so the collectible reads as "to grab".
		var pulse: float = 1.0 + sin(_time * TAU * pulse_hz + float(entry.get("pulse", 0.0))) * 0.12
		node.scale = Vector2.ONE * float(entry.get("base_scale", 1.0)) * pulse

		var collected: bool = dist <= pickup_radius
		# Traînée d'étoile filante : collecte tout ce qu'elle frôle.
		if not collected and star_collect_radius > 0.0 and not _trail_points.is_empty():
			@warning_ignore("integer_division")
			var stride: int = maxi(1, _trail_points.size() / 8)
			for p_idx in range(0, _trail_points.size(), stride):
				var p: Vector2 = (_trail_points[p_idx] as Dictionary).get("pos", Vector2.ZERO)
				if node.global_position.distance_to(p) <= star_collect_radius:
					collected = true
					break
		if collected:
			var at_pos: Vector2 = node.global_position
			var tier: Dictionary = entry.get("tier", {}) as Dictionary
			var powerup: Dictionary = entry.get("powerup", {}) as Dictionary
			node.queue_free()
			_pickups.remove_at(i)
			if powerup.is_empty():
				_collect(tier, at_pos)
			else:
				_apply_powerup(powerup, at_pos)
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
	queue_free() # hazards, pickups, beams, buff bar and trail are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
