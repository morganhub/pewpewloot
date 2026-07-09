extends Node2D

## ClawBossManager — Orchestre une vague "claw_boss" (Dungeon Clawler adapté
## vertical). Le boss occupe le tiers haut (barre de vie SANS chiffre, HUD
## standard), le vaisseau est verrouillé au centre (tir coupé) et une pince
## accrochée à son dos plonge dans une cuve d'objets (2/3 bas de l'écran).
##
## Cycle : AIM (le joueur ne règle que le X de la pince pendant un countdown
## "PRISE DANS N" ; relâcher/espace = lancer, timeout = auto) -> DROP (descente
## auto, pince ouverte, aimant éventuel) -> CLOSE (fermeture au fond seulement,
## sélection des captures : rayon + grab_score + caps poids/nombre) -> RAISE
## (remontée vers le vaisseau, wobble, pertes possibles) -> FEED (résolution
## échelonnée : claw_upgrade > hazard > shield > crystal > attack > neutral) ->
## COOLDOWN (ouverture = fermeture inversée) -> AIM.
##
## Le boss ne tire jamais : il alimente la cuve (largage initial + feed
## runtime). Les objets "attack" déclenchent un tir VISUEL du vaisseau vers le
## boss (impact garanti, barre -%). Bombe = dégâts joueur, shield = recharge
## complète du bouclier, crystal = score/cristal bonus, claw_upgrade = modifie
## la pince N grabs (une seule active), junk = rien. Boss mort avant le timer =
## fin anticipée + kill_score/cristaux/loot uncommon+ ; timer écoulé = le boss
## s'enfuit sans bonus. Les deux fins émettent `finished` (en mode libre
## "restart", la vague est régénérée au level courant : nouveau boss).
##
## Physique de cuve 100 % arcade (cercles, Euler, 2 passes de séparation) —
## pas de moteur physique. Config PLATE dans wave_types.json > claw_boss ;
## structures : items[], claw_upgrades{}, bosses[], item_pool_overrides{}.

signal finished

enum State { INTRO, AIM, DROP, CLOSE, RAISE, FEED, COOLDOWN, BOSS_DEATH, BOSS_ESCAPE, DONE }

const MOUSE_CAPTURE_ID: int = -2
const PIT_ITEM_HARD_CAP: int = 120
const FEED_RESOLVE_ORDER: Array = ["claw_upgrade", "hazard", "shield", "crystal", "attack", "neutral"]

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 60.0
var _elapsed: float = 0.0
var _finished_emitted: bool = false
var _reward_multiplier: float = 1.0

# Layout (calculé une fois).
var _viewport_size: Vector2 = Vector2.ZERO
var _boss_area_rect: Rect2 = Rect2()
var _pit_rect: Rect2 = Rect2()
var _pit_floor_y: float = 0.0
var _ship_lock_pos: Vector2 = Vector2.ZERO
var _claw_rest_y: float = 0.0
var _claw_bottom_y: float = 0.0

# Boss : décoratif (PAS Boss.tscn) — barre normalisée 1.0 -> 0.0, sans chiffre.
var _boss_node: Node2D = null
var _boss_sprite: Node2D = null
var _boss_def: Dictionary = {}
var _boss_health: float = 1.0
var _boss_center: Vector2 = Vector2.ZERO
var _boss_visual_size: Vector2 = Vector2.ZERO

# Items de la cuve : { "node": Node2D, "sprite": Node2D, "pos": Vector2,
# "vel": Vector2, "radius": float, "def": Dictionary, "grabbed": bool,
# "pulse_time": float, "asleep": bool, "rest_timer": float }.
# Sommeil physique : un objet au repos est skippé (intégration + paires) et
# réveillé au contact — indispensable à ~100 objets sur mobile.
var _items: Array = []
# Objets tenus par la pince : { "item": Dictionary, "slot": Vector2 (position
# packée DANS le volume intérieur, relative au hub), "vel": Vector2,
# "stress": float }. Les objets tenus sont de vrais corps : ressort vers le
# slot, collisions entre eux (hitbox exclusive), lâchers physiques.
var _held: Array = []
# Upgrade active (UNE seule, la nouvelle remplace) : { "id", "grabs_left", "def" }.
var _upgrade: Dictionary = {}
# Tirs visuels vaisseau -> boss : { "node", "from", "to", "t", "duration",
# "def", "single" }.
var _shots: Array = []

# Pince (fallback procédural : câble + hub + 2 doigts sur pivots).
var _claw_root: Node2D = null
var _cable_line: Line2D = null
var _claw_hub: Node2D = null
var _finger_left: Node2D = null
var _finger_right: Node2D = null
var _claw_anim_sprite: AnimatedSprite2D = null # si claw_frames_asset fourni
var _claw_x: float = 0.0
var _claw_y: float = 0.0
var _claw_target_x: float = 0.0
var _claw_open_angle: float = 35.0
var _claw_closed_angle: float = 6.0
var _raise_start_y: float = 0.0
var _wobble_time: float = 0.0
# Fermeture effective du grab courant (1 = doigts complètement fermés). Les
# objets larges BLOQUENT la fermeture : grip réduit + ouverture en bas.
var _closure: float = 1.0

# Intro : arrivée du boss puis largage initial échelonné.
var _intro_phase: int = 0 # 0 = arrivée, 1 = largage, 2 = settle
var _intro_drops_left: int = 0
var _intro_drop_timer: float = 0.0

# Grab countdown.
var _grab_countdown: float = 5.0
var _auto_grab_flash: float = 0.0

# Feed : file d'objets à résoudre.
var _feed_queue: Array = []
var _feed_timer: float = 0.0
var _feed_attack_count: int = 0

# Runtime feed de la cuve.
var _feed_interval_timer: float = 0.0

# Input.
var _touch_id: int = -1

# Paramètres (résolus au setup, clés PLATES).
var _grab_countdown_sec: float = 5.0
var _grab_countdown_min_sec: float = 2.5
var _claw_move_speed: float = 620.0
var _claw_drop_speed: float = 760.0
var _claw_raise_speed: float = 620.0
var _close_anim_sec: float = 0.25
var _cooldown_sec: float = 0.4
# Volume intérieur de la pince (ce que les doigts enserrent RÉELLEMENT) :
# hitbox de capture = visuel de la pince (dessinée à partir de ces dimensions).
var _claw_inner_halfw: float = 56.0
var _claw_inner_h: float = 92.0
var _overfill_tolerance: float = 10.0
var _held_spring: float = 9.0
var _held_wobble_accel: float = 300.0
var _claw_max_weight: float = 5.0
var _max_grabbed_items: int = 5
var _grab_strength: float = 1.0
var _grab_threshold: float = 0.45
var _weight_penalty: float = 0.22
var _center_bonus_factor: float = 0.35
var _carry_wobble_strength: float = 0.25
var _drop_chance_base: float = 0.08
var _feed_item_interval: float = 0.35
var _target_items: int = 30
var _max_items: int = 36
var _initial_drop_count: int = 24
var _pit_gravity: float = 920.0
var _floor_damping: float = 0.25
var _item_friction: float = 0.88
var _runtime_feed_interval: float = 1.2
var _runtime_feed_batch_min: int = 1
var _runtime_feed_batch_max: int = 3
var _attack_pickups_to_kill: float = 10.0
var _bomb_pool_bonus: float = 0.0
var _junk_pool_bonus: float = 0.0
var _kill_score: int = 5000
var _kill_crystals: int = 8
var _kill_loot_quality_mult: float = 8.0
var _kill_loot_min_rarity: String = "uncommon"
var _boss_death_anim_sec: float = 1.6
var _boss_escape_anim_sec: float = 1.0
var _item_defs: Array = []
var _claw_upgrade_defs: Dictionary = {}
var _boss_defs: Array = []
var _item_pool_overrides: Dictionary = {}

# Assets résolus (jamais de load() en frame gameplay).
var _item_textures: Dictionary = {} # id -> Texture2D
var _item_frames: Dictionary = {} # id -> SpriteFrames
var _boss_frames_by_index: Array = []
var _claw_frames: SpriteFrames = null
var _cable_texture: Texture2D = null

# UI.
var _grab_label: Label = null
var _countdown_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("claw_boss") if DataManager else {}

	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("duration_sec_default", 60.0))))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_grab_countdown_min_sec = maxf(0.5, float(_get_conf("grab_countdown_min_sec", 2.5)))
	_grab_countdown_sec = maxf(_grab_countdown_min_sec, float(_get_conf("grab_countdown_sec", 5.0)))
	_claw_move_speed = maxf(60.0, float(_get_conf("claw_move_speed_px_sec", 620.0)))
	_claw_drop_speed = maxf(120.0, float(_get_conf("claw_drop_speed_px_sec", 760.0)))
	_claw_raise_speed = maxf(120.0, float(_get_conf("claw_raise_speed_px_sec", 620.0)))
	_claw_open_angle = clampf(float(_get_conf("claw_open_angle_deg", 35.0)), 5.0, 80.0)
	_claw_closed_angle = clampf(float(_get_conf("claw_closed_angle_deg", 6.0)), 0.0, _claw_open_angle)
	_close_anim_sec = maxf(0.05, float(_get_conf("close_anim_sec", 0.25)))
	_cooldown_sec = maxf(0.05, float(_get_conf("cooldown_sec", 0.4)))
	_claw_inner_halfw = maxf(20.0, float(_get_conf("claw_inner_width_px", 112.0)) * 0.5)
	_claw_inner_h = maxf(30.0, float(_get_conf("claw_inner_height_px", 92.0)))
	_overfill_tolerance = maxf(0.0, float(_get_conf("claw_overfill_tolerance_px", 10.0)))
	_held_spring = maxf(1.0, float(_get_conf("held_spring_per_sec", 9.0)))
	_held_wobble_accel = maxf(0.0, float(_get_conf("held_wobble_accel_px_sec2", 300.0)))
	_claw_max_weight = maxf(0.1, float(_get_conf("claw_max_weight", 5.0)))
	_max_grabbed_items = clampi(int(_get_conf("max_grabbed_items", 5)), 1, 12)
	_grab_strength = maxf(0.05, float(_get_conf("grab_strength", 1.0)))
	_grab_threshold = float(_get_conf("grab_threshold", 0.45))
	_weight_penalty = maxf(0.0, float(_get_conf("weight_penalty", 0.22)))
	_center_bonus_factor = maxf(0.0, float(_get_conf("center_bonus_factor", 0.35)))
	_carry_wobble_strength = clampf(float(_get_conf("carry_wobble_strength", 0.25)), 0.0, 2.0)
	_drop_chance_base = clampf(float(_get_conf("drop_chance_on_raise_base", 0.08)), 0.0, 0.9)
	_feed_item_interval = maxf(0.05, float(_get_conf("feed_item_interval_sec", 0.35)))
	_target_items = clampi(int(_get_conf("target_items_in_pit", 30)), 4, PIT_ITEM_HARD_CAP)
	_max_items = clampi(int(_get_conf("max_items_in_pit", 36)), _target_items, PIT_ITEM_HARD_CAP)
	_initial_drop_count = clampi(int(_get_conf("initial_drop_count", 24)), 1, _max_items)
	_pit_gravity = maxf(100.0, float(_get_conf("pit_gravity_px_sec2", 920.0)))
	_floor_damping = clampf(float(_get_conf("floor_bounce_damping", 0.25)), 0.0, 0.9)
	_item_friction = clampf(float(_get_conf("item_friction", 0.88)), 0.5, 1.0)
	_runtime_feed_interval = maxf(0.2, float(_get_conf("runtime_feed_interval_sec", 1.2)))
	_runtime_feed_batch_min = clampi(int(_get_conf("runtime_feed_batch_min", 1)), 1, 8)
	_runtime_feed_batch_max = clampi(int(_get_conf("runtime_feed_batch_max", 3)), _runtime_feed_batch_min, 8)
	_attack_pickups_to_kill = maxf(1.0, float(_get_conf("attack_pickups_to_kill", 10.0)))
	_bomb_pool_bonus = maxf(0.0, float(_get_conf("bomb_pool_weight_bonus", 0.0)))
	_junk_pool_bonus = maxf(0.0, float(_get_conf("junk_pool_weight_bonus", 0.0)))
	_kill_score = maxi(0, int(_get_conf("kill_score", 5000)))
	_kill_crystals = maxi(0, int(_get_conf("kill_crystals", 8)))
	_kill_loot_quality_mult = maxf(0.0, float(_get_conf("kill_loot_quality_mult", 8.0)))
	_kill_loot_min_rarity = str(_get_conf("kill_loot_min_rarity", "uncommon"))
	_boss_death_anim_sec = maxf(0.3, float(_get_conf("boss_death_anim_sec", 1.6)))
	_boss_escape_anim_sec = maxf(0.2, float(_get_conf("boss_escape_anim_sec", 1.0)))
	var items_v: Variant = _get_conf("items", [])
	_item_defs = (items_v as Array).duplicate(true) if items_v is Array else []
	var upgrades_v: Variant = _get_conf("claw_upgrades", {})
	_claw_upgrade_defs = (upgrades_v as Dictionary).duplicate(true) if upgrades_v is Dictionary else {}
	var bosses_v: Variant = _get_conf("bosses", [])
	_boss_defs = (bosses_v as Array).duplicate(true) if bosses_v is Array else []
	var overrides_v: Variant = _get_conf("item_pool_overrides", {})
	_item_pool_overrides = (overrides_v as Dictionary) if overrides_v is Dictionary else {}

	_prepare_assets()
	_compute_layout()
	_begin_player_mode()
	_begin_hud_mode()
	_build_pit_frame()
	_build_boss(_pick_boss_def())
	_build_claw()
	_ensure_countdown_label()
	_ensure_grab_label()

	_elapsed = 0.0
	_boss_health = 1.0
	_intro_phase = 0
	_intro_drops_left = _initial_drop_count
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_arrival_sec", 1.0)))
	set_process(true)

## Per-wave override (world_X.json / freemode) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

# =============================================================================
# PLAYER / HUD MODES
# =============================================================================

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_claw_boss"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_claw_boss", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_claw_boss"):
		_player.call("end_claw_boss")

func _begin_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", true)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", false)
	if _hud.has_method("show_boss_health"):
		_hud.call("show_boss_health", _boss_display_name(), 1000)

func _restore_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", false)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", true)
	if _hud.has_method("hide_boss_health"):
		_hud.call("hide_boss_health")

# =============================================================================
# ASSETS (résolus une fois au setup)
# =============================================================================

func _prepare_assets() -> void:
	_item_textures.clear()
	_item_frames.clear()
	for def_v in _item_defs:
		if not (def_v is Dictionary):
			continue
		var def: Dictionary = def_v as Dictionary
		var id: String = str(def.get("id", ""))
		var assets_v: Variant = def.get("assets", [])
		if assets_v is Array:
			for asset_v in (assets_v as Array):
				var tex: Texture2D = _texture_from_path(str(asset_v))
				if tex != null:
					_item_textures[id] = tex
					break
		var frames: SpriteFrames = _frames_from_path(str(def.get("asset_anim", "")))
		if frames != null:
			_item_frames[id] = frames
	_boss_frames_by_index.clear()
	for boss_v in _boss_defs:
		var anim_path: String = str((boss_v as Dictionary).get("asset_anim", "")) if boss_v is Dictionary else ""
		_boss_frames_by_index.append(_frames_from_path(anim_path))
	_claw_frames = _frames_from_path(str(_get_conf("claw_frames_asset", "")))
	_cable_texture = _texture_from_path(str(_get_conf("cable_asset", "")))

func _frames_from_path(path: String) -> SpriteFrames:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return res as SpriteFrames

func _texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		return res as Texture2D
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			return frames.get_frame_texture(names[0], 0)
	return null

# =============================================================================
# LAYOUT / BUILD
# =============================================================================

func _compute_layout() -> void:
	_viewport_size = get_viewport_rect().size
	var boss_h: float = _viewport_size.y * clampf(float(_get_conf("boss_area_height_ratio", 0.33)), 0.15, 0.5)
	_boss_area_rect = Rect2(Vector2.ZERO, Vector2(_viewport_size.x, boss_h))
	var margin: float = maxf(2.0, float(_get_conf("pit_side_margin_px", 18.0)))
	var pit_top: float = _viewport_size.y * clampf(float(_get_conf("pit_top_ratio", 0.48)), 0.3, 0.8)
	var pit_bottom: float = _viewport_size.y * clampf(float(_get_conf("pit_bottom_ratio", 0.96)), 0.6, 1.0)
	_pit_rect = Rect2(Vector2(margin, pit_top), Vector2(_viewport_size.x - margin * 2.0, maxf(40.0, pit_bottom - pit_top)))
	_pit_floor_y = _pit_rect.end.y
	_ship_lock_pos = Vector2(
		_viewport_size.x * clampf(float(_get_conf("ship_lock_x_ratio", 0.5)), 0.1, 0.9),
		_viewport_size.y * clampf(float(_get_conf("ship_lock_y_ratio", 0.42)), 0.2, 0.7))
	_claw_rest_y = _pit_rect.position.y + 14.0
	# Le hub s'arrête pour que les DOIGTS (longueur inner_h + 16) atteignent le
	# fond : le volume de capture couvre les objets posés au sol (avant : hub à
	# 26 px du sol -> volume à moitié SOUS le plancher, pickup quasi mort).
	_claw_bottom_y = _pit_floor_y - (_claw_inner_h + 16.0) + 6.0
	_claw_x = _ship_lock_pos.x
	_claw_target_x = _claw_x
	_claw_y = _claw_rest_y
	_boss_center = Vector2(_viewport_size.x * 0.5, boss_h * 0.55)

## Cadre visuel de la cuve (Line2D, couleur data).
func _build_pit_frame() -> void:
	var frame := Line2D.new()
	frame.name = "PitFrame"
	frame.width = 3.0
	frame.default_color = Color(str(_get_conf("pit_frame_color", "#3A4A5AC0")))
	frame.points = PackedVector2Array([
		Vector2(_pit_rect.position.x, _pit_rect.position.y),
		Vector2(_pit_rect.position.x, _pit_rect.end.y),
		Vector2(_pit_rect.end.x, _pit_rect.end.y),
		Vector2(_pit_rect.end.x, _pit_rect.position.y)
	])
	frame.z_as_relative = false
	frame.z_index = 8
	add_child(frame)

## Boss tiré : story force via wave "boss_id", sinon aléatoire dans bosses[].
func _pick_boss_def() -> Dictionary:
	if _boss_defs.is_empty():
		return {}
	var forced_id: String = str(_config.get("boss_id", ""))
	if forced_id != "":
		for boss_v in _boss_defs:
			if boss_v is Dictionary and str((boss_v as Dictionary).get("id", "")) == forced_id:
				return boss_v as Dictionary
		push_warning("[ClawBoss] boss_id inconnu '%s' — premier boss de la liste utilisé." % forced_id)
		return _boss_defs[0] as Dictionary
	return _boss_defs[randi() % _boss_defs.size()] as Dictionary

func _boss_display_name() -> String:
	var key: String = str(_boss_def.get("name_key", ""))
	if key != "" and typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return str(_boss_def.get("id", "BOSS")).capitalize()

## Boss décoratif : AnimatedSprite2D fit (aspect préservé) — PAS Boss.tscn.
func _build_boss(def: Dictionary) -> void:
	_boss_def = def
	_boss_node = Node2D.new()
	_boss_node.name = "ClawBoss"
	_boss_node.z_as_relative = false
	_boss_node.z_index = 9
	var fit: float = maxf(60.0, float(_get_conf("boss_fit_px", 240.0)))
	var def_index: int = _boss_defs.find(def)
	var frames: SpriteFrames = null
	if def_index >= 0 and def_index < _boss_frames_by_index.size():
		frames = _boss_frames_by_index[def_index]
	if frames != null:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		if VFXManager:
			VFXManager.play_sprite_frames(sprite, frames, &"default", true, 0.0)
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			var first: Texture2D = frames.get_frame_texture(names[0], 0)
			if first != null and first.get_size().x > 0.0 and first.get_size().y > 0.0:
				var scale_factor: float = minf(fit / first.get_size().x, fit / first.get_size().y)
				sprite.scale = Vector2.ONE * scale_factor
				_boss_visual_size = first.get_size() * scale_factor
		_boss_sprite = sprite
	else:
		# Fallback : hexagone coloré.
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 - PI * 0.5
			pts.append(Vector2(cos(a), sin(a)) * fit * 0.5)
		poly.polygon = pts
		poly.color = Color("#7C4A9C")
		_boss_sprite = poly
		_boss_visual_size = Vector2.ONE * fit
	_boss_node.add_child(_boss_sprite)
	add_child(_boss_node)
	# Arrivée : translation depuis l'extérieur du haut de l'écran.
	_boss_node.position = Vector2(_boss_center.x, -_boss_visual_size.y)
	var tween: Tween = create_tween()
	tween.tween_property(_boss_node, "position", _boss_center, maxf(0.05, float(_get_conf("intro_arrival_sec", 1.0)))) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Pince procédurale : câble Line2D vaisseau -> hub, hub trapèze, 2 doigts
## coudés sur pivots. Fermeture = tween des rotations ; ouverture = inversé.
## Si claw_frames_asset (.tres) est fourni : AnimatedSprite2D play/play_backwards.
func _build_claw() -> void:
	_claw_root = Node2D.new()
	_claw_root.name = "ClawRoot"
	_claw_root.z_as_relative = false
	_claw_root.z_index = 14
	add_child(_claw_root)
	_cable_line = Line2D.new()
	_cable_line.width = 3.0
	_cable_line.default_color = Color(str(_get_conf("cable_color", "#B8C4D0")))
	if _cable_texture != null:
		_cable_line.texture = _cable_texture
		_cable_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	_cable_line.z_as_relative = false
	_cable_line.z_index = 13
	add_child(_cable_line)
	_claw_hub = Node2D.new()
	_claw_root.add_child(_claw_hub)
	if _claw_frames != null:
		_claw_anim_sprite = AnimatedSprite2D.new()
		_claw_anim_sprite.sprite_frames = _claw_frames
		_claw_hub.add_child(_claw_anim_sprite)
	else:
		# Le visuel est DIMENSIONNÉ sur le volume de capture (claw_inner_*) :
		# ce que les doigts enserrent à l'écran = la hitbox de grab.
		var claw_color := Color(str(_get_conf("claw_color", "#D8E0E8")))
		var hub_halfw: float = _claw_inner_halfw + 8.0
		var hub_poly := Polygon2D.new()
		hub_poly.polygon = PackedVector2Array([
			Vector2(-hub_halfw, -10.0), Vector2(hub_halfw, -10.0),
			Vector2(hub_halfw * 0.8, 10.0), Vector2(-hub_halfw * 0.8, 10.0)
		])
		hub_poly.color = claw_color
		_claw_hub.add_child(hub_poly)
		_finger_left = _make_finger(claw_color, -1.0)
		_finger_right = _make_finger(claw_color, 1.0)
		_set_finger_angles(_claw_open_angle)

func _make_finger(color: Color, side: float) -> Node2D:
	var pivot := Node2D.new()
	pivot.position = Vector2(_claw_inner_halfw * side, 8.0)
	var finger_len: float = _claw_inner_h + 16.0
	var poly := Polygon2D.new()
	# Doigt coudé (2 segments) long comme le volume intérieur, pointe rentrée.
	poly.polygon = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(7.0 * side, 4.0),
		Vector2(10.0 * side, finger_len * 0.55),
		Vector2(2.0 * side, finger_len),
		Vector2(-4.0 * side, finger_len * 0.94),
		Vector2(2.0 * side, finger_len * 0.52),
		Vector2(-3.0 * side, 6.0)
	])
	poly.color = color
	pivot.add_child(poly)
	_claw_hub.add_child(pivot)
	return pivot

func _set_finger_angles(angle_deg: float) -> void:
	if _finger_left and is_instance_valid(_finger_left):
		_finger_left.rotation = deg_to_rad(angle_deg)
	if _finger_right and is_instance_valid(_finger_right):
		_finger_right.rotation = deg_to_rad(-angle_deg)

## Angle (deg) de fermeture COMPLÈTE : rotation vers l'INTÉRIEUR qui amène les
## pointes des doigts (pivots à ±inner_halfw, longueur inner_h+16) à se
## rejoindre au centre — et même à SE CROISER (claw_close_overshoot_ratio > 1 :
## le bas de la pince se referme "avec puissance", prise bien fermée).
func _full_close_angle_deg() -> float:
	var overshoot: float = maxf(1.0, float(_get_conf("claw_close_overshoot_ratio", 1.3)))
	return rad_to_deg(atan2(_claw_inner_halfw * overshoot, _claw_inner_h + 16.0))

## Fermeture (close = true) ou ouverture (= fermeture inversée). La fermeture
## est BLOQUÉE par les objets enserrés (_closure < 1 = doigts entrouverts).
## Convention d'angle : positif = écarté, négatif = replié vers le centre ;
## claw_closed_angle_deg = écart RÉSIDUEL des pointes une fois fermée.
func _animate_claw(close: bool) -> void:
	if _claw_anim_sprite != null and is_instance_valid(_claw_anim_sprite):
		if close:
			_claw_anim_sprite.play(&"close")
		else:
			_claw_anim_sprite.play_backwards(&"close")
		return
	var target: float = _claw_open_angle
	if close:
		var full_close: float = -(_full_close_angle_deg() - _claw_closed_angle)
		target = lerpf(_claw_open_angle, full_close, clampf(_closure, 0.0, 1.0))
	if _finger_left and is_instance_valid(_finger_left):
		var tween_l: Tween = create_tween()
		tween_l.tween_property(_finger_left, "rotation", deg_to_rad(target), _close_anim_sec) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _finger_right and is_instance_valid(_finger_right):
		var tween_r: Tween = create_tween()
		tween_r.tween_property(_finger_right, "rotation", deg_to_rad(-target), _close_anim_sec) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# =============================================================================
# UI (countdown de vague + countdown de grab)
# =============================================================================

func _ensure_countdown_label() -> void:
	# Le round claw_boss a une vraie échéance (fuite du boss à 60 s) : le timer
	# reste visible MÊME en mode libre (countdown_always_visible, data) — le
	# joueur doit savoir quand la vague se termine.
	if bool(_config.get("countdown_hidden", false)) and not bool(_get_conf("countdown_always_visible", false)):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "ClawBossCountdownLabel"
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
	_countdown_label.size = Vector2(_viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, _viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

## "PRISE DANS N" / "PRISE AUTO" — toujours visible (gameplay), même en libre.
func _ensure_grab_label() -> void:
	_grab_label = Label.new()
	_grab_label.name = "GrabCountdownLabel"
	_grab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grab_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("grab_countdown_font_size", 34))))
	_grab_label.add_theme_color_override("font_color", Color(str(_get_conf("grab_countdown_color", "#FFD966"))))
	_grab_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_grab_label.add_theme_constant_override("outline_size", 5)
	_grab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grab_label.z_as_relative = false
	_grab_label.z_index = 60
	_grab_label.visible = false
	_grab_label.size = Vector2(_viewport_size.x, 44.0)
	_grab_label.position = Vector2(0.0, _pit_rect.position.y - 52.0)
	add_child(_grab_label)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

func _update_grab_label() -> void:
	if _grab_label == null or not is_instance_valid(_grab_label):
		return
	if _state != State.AIM:
		_grab_label.visible = _auto_grab_flash > 0.0
		return
	_grab_label.visible = true
	var template: String = _translate_or("claw_boss_grab_in", "GRAB IN %d")
	_grab_label.text = template % int(ceil(maxf(0.0, _grab_countdown)))

# =============================================================================
# POOL / SPAWN D'ITEMS
# =============================================================================

## Pool pondéré : pool_weight (items[]) écrasé par item_pool_overrides{} puis
## bonus plats bomb/junk (scalables per_level en mode libre).
func _pick_item_def() -> Dictionary:
	var total: float = 0.0
	var weights: Array = []
	for def_v in _item_defs:
		if not (def_v is Dictionary):
			weights.append(0.0)
			continue
		var def: Dictionary = def_v as Dictionary
		var id: String = str(def.get("id", ""))
		var weight: float = maxf(0.0, float(_item_pool_overrides.get(id, def.get("pool_weight", 1.0))))
		if id == "bomb":
			weight += _bomb_pool_bonus
		elif id == "scrap_junk":
			weight += _junk_pool_bonus
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return {}
	var roll: float = randf() * total
	for i in range(_item_defs.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			return _item_defs[i] as Dictionary
	return _item_defs[_item_defs.size() - 1] as Dictionary

## Largue un objet depuis le boss vers la cuve (le boss "alimente" la cuve).
func _spawn_item_from_boss() -> void:
	if _items.size() >= _max_items:
		return
	var def: Dictionary = _pick_item_def()
	if def.is_empty():
		return
	var id: String = str(def.get("id", ""))
	var size_v: Variant = def.get("size_px", [30, 30])
	var size := Vector2(30.0, 30.0)
	if size_v is Array and (size_v as Array).size() >= 2:
		size = Vector2(float((size_v as Array)[0]), float((size_v as Array)[1]))
	var radius: float = maxf(size.x, size.y) * 0.5
	var item_node := Node2D.new()
	item_node.z_as_relative = false
	item_node.z_index = 10
	var sprite: Node2D = null
	var tint := Color(str(def.get("tint", "#FFFFFF")))
	if _item_frames.has(id):
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = _item_frames[id]
		if VFXManager:
			VFXManager.play_sprite_frames(anim, _item_frames[id], &"default", true, 0.0)
		var first: Texture2D = _texture_from_path(str(def.get("asset_anim", "")))
		if first != null and first.get_size().x > 0.0:
			anim.scale = Vector2.ONE * (maxf(size.x, size.y) / maxf(first.get_size().x, first.get_size().y))
		anim.modulate = tint
		sprite = anim
	elif _item_textures.has(id):
		var spr := Sprite2D.new()
		spr.texture = _item_textures[id]
		var tex_size: Vector2 = (_item_textures[id] as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			spr.scale = size / tex_size
		spr.modulate = tint
		sprite = spr
	else:
		# Fallback : rectangle teinté (junk gris terne, etc.).
		var poly := Polygon2D.new()
		var half: Vector2 = size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		poly.color = tint
		sprite = poly
	sprite.rotation = randf_range(-0.5, 0.5) # rotation visuelle fixe (pas de simu)
	item_node.add_child(sprite)
	add_child(item_node)
	# Largage par les CÔTÉS gauche/droit (bandes latérales, feed_side_band_ratio)
	# avec dérive vers le centre : les objets ne tombent plus à travers la
	# pince qui pend au milieu (aucune collision avec elle — purement visuel).
	var band_w: float = _pit_rect.size.x * clampf(float(_get_conf("feed_side_band_ratio", 0.25)), 0.05, 0.45)
	var drop_x: float
	var inward_sign: float
	if randf() < 0.5:
		drop_x = randf_range(_pit_rect.position.x + radius, _pit_rect.position.x + band_w)
		inward_sign = 1.0
	else:
		drop_x = randf_range(_pit_rect.end.x - band_w, _pit_rect.end.x - radius)
		inward_sign = -1.0
	var drop_pos := Vector2(drop_x, _boss_area_rect.end.y)
	item_node.position = drop_pos
	_items.append({
		"node": item_node,
		"sprite": sprite,
		"pos": drop_pos,
		"vel": Vector2(inward_sign * randf_range(30.0, 120.0), 150.0),
		"radius": radius,
		"def": def,
		"grabbed": false,
		"asleep": false,
		"rest_timer": 0.0,
		"pulse_time": randf() * TAU
	})
	if VFXManager and _boss_node and is_instance_valid(_boss_node):
		VFXManager.spawn_impact(_boss_node.position + Vector2(0.0, _boss_visual_size.y * 0.4), 10.0, self)

## Feed runtime : maintient ~target_items_in_pit objets dans la cuve.
func _runtime_feed(delta: float) -> void:
	_feed_interval_timer -= delta
	if _feed_interval_timer > 0.0:
		return
	_feed_interval_timer = _runtime_feed_interval
	if _items.size() >= _target_items:
		return
	var batch: int = randi_range(_runtime_feed_batch_min, _runtime_feed_batch_max)
	for _i in range(batch):
		_spawn_item_from_boss()

# =============================================================================
# PHYSIQUE DE LA CUVE (arcade : cercles + Euler + séparation positionnelle)
# =============================================================================

func _update_pit_physics(delta: float) -> void:
	var dt: float = minf(delta, 1.0 / 30.0) # un hitch ne traverse pas le sol
	var floor_y: float = _pit_floor_y
	var left_x: float = _pit_rect.position.x
	var right_x: float = _pit_rect.end.x
	for item_v in _items:
		var item: Dictionary = item_v as Dictionary
		if bool(item.get("grabbed", false)) or bool(item.get("asleep", false)):
			continue
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		var vel: Vector2 = item.get("vel", Vector2.ZERO)
		var radius: float = float(item.get("radius", 15.0))
		vel.y += _pit_gravity * dt
		pos += vel * dt
		# Sol : rebond amorti + friction.
		if pos.y > floor_y - radius:
			pos.y = floor_y - radius
			if vel.y > 0.0:
				vel.y = -vel.y * _floor_damping
			if absf(vel.y) < 40.0:
				vel.y = 0.0
			vel.x *= _item_friction
		# Murs.
		if pos.x < left_x + radius:
			pos.x = left_x + radius
			vel.x = -vel.x * 0.3
		elif pos.x > right_x - radius:
			pos.x = right_x - radius
			vel.x = -vel.x * 0.3
		item["pos"] = pos
		item["vel"] = vel
		# Endormissement : au repos depuis ~0,45 s -> plus d'intégration ni de
		# paires (avec ~100 objets, l'essentiel du tas dort — coût maîtrisé).
		if vel.length_squared() < 250.0:
			item["rest_timer"] = float(item.get("rest_timer", 0.0)) + dt
			if float(item["rest_timer"]) > 0.45:
				item["asleep"] = true
				item["vel"] = Vector2.ZERO
		else:
			item["rest_timer"] = 0.0
	# Séparation positionnelle (2 passes) — les paires entièrement endormies
	# sont skippées ; un contact avec un objet éveillé réveille l'endormi.
	for _pass in range(2):
		for i in range(_items.size()):
			var item_a: Dictionary = _items[i]
			if bool(item_a.get("grabbed", false)):
				continue
			var a_asleep: bool = bool(item_a.get("asleep", false))
			for j in range(i + 1, _items.size()):
				var item_b: Dictionary = _items[j]
				if bool(item_b.get("grabbed", false)):
					continue
				if a_asleep and bool(item_b.get("asleep", false)):
					continue
				var pos_a: Vector2 = item_a.get("pos", Vector2.ZERO)
				var pos_b: Vector2 = item_b.get("pos", Vector2.ZERO)
				var min_dist: float = float(item_a.get("radius", 15.0)) + float(item_b.get("radius", 15.0))
				var d: Vector2 = pos_b - pos_a
				var dist_sq: float = d.length_squared()
				if dist_sq >= min_dist * min_dist:
					continue
				var normal: Vector2
				var dist: float = sqrt(dist_sq)
				if dist > 0.001:
					normal = d / dist
				else:
					normal = Vector2(randf_range(-1.0, 1.0), 0.0).normalized()
					dist = 0.001
				var push: float = (min_dist - dist) * 0.5
				pos_a -= normal * push
				pos_b += normal * push
				item_a["pos"] = pos_a
				item_b["pos"] = pos_b
				item_a["vel"] = (item_a.get("vel", Vector2.ZERO) as Vector2) * 0.9
				item_b["vel"] = (item_b.get("vel", Vector2.ZERO) as Vector2) * 0.9
				_wake_item(item_a)
				_wake_item(item_b)
				a_asleep = false
		# Re-clamp sol/murs en fin de passe.
		for item_v in _items:
			var item: Dictionary = item_v as Dictionary
			if bool(item.get("grabbed", false)) or bool(item.get("asleep", false)):
				continue
			var pos: Vector2 = item.get("pos", Vector2.ZERO)
			var radius: float = float(item.get("radius", 15.0))
			pos.y = minf(pos.y, _pit_floor_y - radius)
			pos.x = clampf(pos.x, _pit_rect.position.x + radius, _pit_rect.end.x - radius)
			item["pos"] = pos
	# Applique aux nodes + pulse des bombes.
	for item_v in _items:
		var item: Dictionary = item_v as Dictionary
		var node_v: Variant = item.get("node", null)
		if bool(item.get("grabbed", false)):
			continue
		if node_v is Node2D and is_instance_valid(node_v) and not bool(item.get("asleep", false)):
			(node_v as Node2D).position = item.get("pos", Vector2.ZERO)
		if bool((item.get("def", {}) as Dictionary).get("pulse", false)):
			item["pulse_time"] = float(item.get("pulse_time", 0.0)) + delta * 6.0
			var sprite_v: Variant = item.get("sprite", null)
			if sprite_v is Node2D and is_instance_valid(sprite_v):
				var pulse: float = 0.75 + 0.25 * (0.5 + 0.5 * sin(float(item["pulse_time"])))
				(sprite_v as Node2D).modulate.a = pulse

func _wake_item(item: Dictionary) -> void:
	if bool(item.get("asleep", false)):
		item["asleep"] = false
	item["rest_timer"] = 0.0

## Réveille les objets autour d'un point (prise, lâcher, impact) : le tas se
## réarrange au lieu de rester figé en l'air.
func _wake_items_near(center: Vector2, radius: float) -> void:
	var radius_sq: float = radius * radius
	for item_v in _items:
		var item: Dictionary = item_v as Dictionary
		if bool(item.get("grabbed", false)):
			continue
		if (item.get("pos", Vector2.ZERO) as Vector2).distance_squared_to(center) <= radius_sq:
			_wake_item(item)

# =============================================================================
# CYCLE DE GRAB
# =============================================================================

func _enter_aim() -> void:
	_state = State.AIM
	_grab_countdown = _grab_countdown_sec
	_touch_id = -1

func _launch_grab() -> void:
	_touch_id = -1
	_closure = 1.0
	_state = State.DROP

## Fermeture au fond : capture VOLUMÉTRIQUE (le volume intérieur entre les
## doigts = la hitbox, alignée sur le visuel) + PACKING EXCLUSIF (les objets
## tenus ne se chevauchent jamais ; un objet qui ne tient pas dans le volume
## n'est pas pris) + fermeture bloquée par la largeur occupée (_closure).
func _select_captures() -> void:
	_held.clear()
	_closure = 1.0
	var halfw: float = _claw_inner_halfw * _claw_mult("grab_radius_multiplier")
	var zone_center := Vector2(_claw_x, _claw_y + _claw_inner_h * 0.55)
	var max_weight: float = _claw_max_weight * _claw_mult("max_weight_multiplier")
	var max_items: int = _max_grabbed_items + _claw_bonus_int("max_grabbed_items_bonus")
	# Candidats : le cercle de l'objet doit être DANS le volume intérieur
	# (léger débord toléré : la pince mord un peu autour de ses doigts).
	var candidates: Array = []
	for item_v in _items:
		var item: Dictionary = item_v as Dictionary
		if bool(item.get("grabbed", false)):
			continue
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		var radius: float = float(item.get("radius", 15.0))
		var dx: float = pos.x - zone_center.x
		var dy: float = pos.y - zone_center.y
		if absf(dx) > halfw + radius * 0.35:
			continue
		if absf(dy) > _claw_inner_h * 0.5 + radius * 0.5:
			continue
		var def: Dictionary = item.get("def", {}) as Dictionary
		var center_bonus: float = (1.0 - clampf(absf(dx) / maxf(halfw, 1.0), 0.0, 1.0)) * _center_bonus_factor
		var grab_score: float = _grab_strength * _claw_mult("grab_strength_multiplier") \
			- float(def.get("weight", 1.0)) * _weight_penalty \
			- float(def.get("grip_difficulty", 0.1)) + center_bonus
		if grab_score < _grab_threshold:
			continue
		candidates.append({"item": item, "dx": absf(dx)})
	candidates.sort_custom(func(a, b) -> bool: return float(a["dx"]) < float(b["dx"]))
	# Packing glouton du centre vers l'extérieur, 2 rangées dans le volume.
	var packed: Array = [] # { "item", "slot": Vector2, "r": float }
	var total_weight: float = 0.0
	for cand_v in candidates:
		if packed.size() >= max_items:
			break
		var item: Dictionary = (cand_v as Dictionary)["item"]
		var def: Dictionary = item.get("def", {}) as Dictionary
		var weight: float = float(def.get("weight", 1.0))
		if total_weight + weight > max_weight:
			continue
		var radius: float = float(item.get("radius", 15.0))
		var slot_v: Variant = _find_claw_slot(packed, radius, halfw)
		if slot_v == null:
			continue # volume plein : hitbox exclusive, l'objet reste en fosse
		total_weight += weight
		item["grabbed"] = true
		item["asleep"] = false
		packed.append({"item": item, "slot": slot_v, "r": radius})
	# Fermeture bloquée par l'occupation horizontale de la prise : au-delà de
	# ~55 % de la demi-largeur, les doigts ne peuvent plus se refermer à fond.
	var packed_extent: float = 0.0
	for packed_v in packed:
		var entry: Dictionary = packed_v as Dictionary
		packed_extent = maxf(packed_extent, absf((entry["slot"] as Vector2).x) + float(entry["r"]))
	if packed_extent > halfw * 0.55:
		_closure = clampf(1.0 - (packed_extent - halfw * 0.55) / maxf(halfw * 0.65, 1.0), 0.25, 1.0)
	for packed_v in packed:
		var entry: Dictionary = packed_v as Dictionary
		_held.append({"item": entry["item"], "slot": entry["slot"], "vel": Vector2.ZERO, "stress": 0.0})
	# Le tas se réarrange sous la prise : réveiller les voisins.
	_wake_items_near(zone_center, halfw + _claw_inner_h)

## Cherche une place SANS chevauchement dans le volume intérieur (2 rangées,
## du centre vers l'extérieur). null = ne rentre pas.
func _find_claw_slot(packed: Array, radius: float, halfw: float) -> Variant:
	var rows_y: Array = [_claw_inner_h * 0.62, _claw_inner_h * 0.3]
	var max_x: float = halfw + _overfill_tolerance - radius
	if max_x < 0.0:
		return null
	for row_y_v in rows_y:
		var row_y: float = float(row_y_v)
		var x: float = 0.0
		while x <= max_x:
			for side in [1.0, -1.0]:
				var slot := Vector2(x * side, row_y)
				if _slot_free(packed, slot, radius):
					return slot
				if x == 0.0:
					break # ±0 identiques
			x += 6.0
	return null

func _slot_free(packed: Array, slot: Vector2, radius: float) -> bool:
	for packed_v in packed:
		var entry: Dictionary = packed_v as Dictionary
		if slot.distance_to(entry["slot"] as Vector2) < radius + float(entry["r"]) - 1.0:
			return false
	return true

## Remontée : la pince monte + wobble ; les lâchers sont gérés par la physique
## des objets tenus (_update_held_items).
func _update_raise(delta: float) -> void:
	var raise_speed: float = _claw_raise_speed * _claw_mult("raise_speed_multiplier")
	_claw_y = maxf(_claw_y - raise_speed * delta, _claw_rest_y)
	_wobble_time += delta
	var wobble_x: float = sin(_wobble_time * 9.0) * 14.0 * _carry_wobble_strength
	_claw_x = clampf(_claw_target_x + wobble_x, _pit_rect.position.x + 20.0, _pit_rect.end.x - 20.0)
	if _claw_y <= _claw_rest_y + 0.5:
		_start_feed()

## Objet perdu : il tombe de la pince et réintègre la simulation de la cuve.
func _release_held(index: int) -> void:
	var held: Dictionary = _held[index]
	_held.remove_at(index)
	var item: Dictionary = held.get("item", {}) as Dictionary
	item["grabbed"] = false
	item["asleep"] = false
	item["rest_timer"] = 0.0
	var held_vel: Vector2 = held.get("vel", Vector2.ZERO)
	item["vel"] = Vector2(clampf(held_vel.x, -120.0, 120.0) + randf_range(-40.0, 40.0), maxf(held_vel.y, 0.0))
	_wake_items_near(item.get("pos", Vector2.ZERO) as Vector2, float(item.get("radius", 15.0)) * 4.0)

## Physique des objets tenus : chaque objet est un vrai corps — ressort vers
## son slot DANS le volume de la pince, wobble = accélération réelle,
## collisions entre objets tenus (hitbox exclusive). Les chocs + une fermeture
## incomplète (_closure < 1) augmentent la probabilité de LÂCHER en remontée ;
## un objet plus petit que l'ouverture laissée en bas glisse plus facilement.
func _update_held_items(delta: float) -> void:
	if _held.is_empty():
		return
	var raising: bool = _state == State.RAISE
	var halfw: float = _claw_inner_halfw * _claw_mult("grab_radius_multiplier")
	var hub := Vector2(_claw_x, _claw_y)
	# Intégration : ressort critique + wobble latéral (pendant la remontée).
	for held_v in _held:
		var held: Dictionary = held_v as Dictionary
		var item: Dictionary = held.get("item", {}) as Dictionary
		var target: Vector2 = hub + (held.get("slot", Vector2.ZERO) as Vector2)
		var pos: Vector2 = item.get("pos", target)
		var vel: Vector2 = held.get("vel", Vector2.ZERO)
		vel += (target - pos) * _held_spring * 12.0 * delta
		if raising:
			vel.x += sin(_wobble_time * 9.0) * _held_wobble_accel * _carry_wobble_strength * delta * 60.0 * 0.2
		vel *= pow(0.02, delta) # fort amortissement (prise ferme)
		pos += vel * delta
		item["pos"] = pos
		held["vel"] = vel
		held["stress"] = maxf(0.0, float(held.get("stress", 0.0)) - delta * 1.5)
	# Collisions entre objets tenus : exclusifs, les chocs génèrent du stress.
	for i in range(_held.size()):
		var held_a: Dictionary = _held[i]
		var item_a: Dictionary = held_a.get("item", {}) as Dictionary
		for j in range(i + 1, _held.size()):
			var held_b: Dictionary = _held[j]
			var item_b: Dictionary = held_b.get("item", {}) as Dictionary
			var pos_a: Vector2 = item_a.get("pos", Vector2.ZERO)
			var pos_b: Vector2 = item_b.get("pos", Vector2.ZERO)
			var min_dist: float = float(item_a.get("radius", 15.0)) + float(item_b.get("radius", 15.0))
			var d: Vector2 = pos_b - pos_a
			var dist_sq: float = d.length_squared()
			if dist_sq >= min_dist * min_dist:
				continue
			var dist: float = maxf(sqrt(dist_sq), 0.001)
			var normal: Vector2 = d / dist
			var push: float = (min_dist - dist) * 0.5
			item_a["pos"] = pos_a - normal * push
			item_b["pos"] = pos_b + normal * push
			held_a["stress"] = float(held_a.get("stress", 0.0)) + push * 0.08
			held_b["stress"] = float(held_b.get("stress", 0.0)) + push * 0.08
	# Confinement dans le volume + lâchers physiques (remontée uniquement).
	var slip_gap: float = (1.0 - _closure) * halfw # ouverture laissée en bas
	var sticky_mult: float = _claw_mult("drop_chance_on_raise_multiplier")
	for i in range(_held.size() - 1, -1, -1):
		var held: Dictionary = _held[i]
		var item: Dictionary = held.get("item", {}) as Dictionary
		var radius: float = float(item.get("radius", 15.0))
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		# Tant qu'il est tenu, l'objet reste DANS la pince (sinon il tombe).
		pos.x = clampf(pos.x, hub.x - halfw - _overfill_tolerance + radius * 0.4, hub.x + halfw + _overfill_tolerance - radius * 0.4)
		pos.y = clampf(pos.y, hub.y + radius * 0.4, hub.y + _claw_inner_h + radius * 0.4)
		item["pos"] = pos
		var node_v: Variant = item.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).position = pos
		if not raising:
			continue
		var def: Dictionary = item.get("def", {}) as Dictionary
		# Probabilité de lâcher par seconde : base × grip de l'objet × sticky ×
		# fermeture incomplète × stress des chocs ; bonus si l'objet est plus
		# petit que l'ouverture du bas (il glisse entre les doigts).
		var p_per_sec: float = _drop_chance_base \
			* (1.0 + float(def.get("grip_difficulty", 0.1)) * 2.0) \
			* sticky_mult \
			* (0.4 + 1.8 * (1.0 - _closure)) \
			* (1.0 + float(held.get("stress", 0.0)) * 2.0)
		if radius * 2.0 < slip_gap:
			p_per_sec *= 2.5
		if randf() < clampf(p_per_sec, 0.0, 6.0) * delta:
			_release_held(i)

# =============================================================================
# FEED (résolution des objets ramenés au vaisseau)
# =============================================================================

func _start_feed() -> void:
	_state = State.FEED
	_feed_queue.clear()
	_feed_timer = 0.0
	# Ordre de résolution : upgrade d'abord (active pour les PROCHAINS grabs),
	# bombe avant le shield fraîchement attrapé (version arcade assumée).
	_feed_attack_count = 0
	for held_v in _held:
		var def: Dictionary = ((held_v as Dictionary).get("item", {}) as Dictionary).get("def", {}) as Dictionary
		if str(def.get("type", "")) == "attack":
			_feed_attack_count += 1
	var ordered: Array = []
	for type_name in FEED_RESOLVE_ORDER:
		for held_v in _held:
			var item: Dictionary = (held_v as Dictionary).get("item", {}) as Dictionary
			var def: Dictionary = item.get("def", {}) as Dictionary
			if str(def.get("type", "neutral")) == str(type_name):
				ordered.append(item)
	_feed_queue = ordered
	_held.clear()

func _update_feed(delta: float) -> void:
	_feed_timer -= delta
	if _feed_timer > 0.0:
		return
	if _feed_queue.is_empty():
		_start_cooldown()
		return
	_feed_timer = _feed_item_interval
	var item: Dictionary = _feed_queue.pop_front() as Dictionary
	_consume_item_visual(item)
	_resolve_item(item.get("def", {}) as Dictionary)

## L'objet file dans le vaisseau (tween court) puis est libéré.
func _consume_item_visual(item: Dictionary) -> void:
	_items.erase(item)
	var node_v: Variant = item.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var node: Node2D = node_v as Node2D
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(node, "position", _ship_lock_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(node, "scale", Vector2.ONE * 0.3, 0.18)
		tween.tween_property(node, "modulate:a", 0.0, 0.18)
		tween.chain().tween_callback(node.queue_free)

func _feed_label(key: String, fallback: String, color: Color) -> void:
	if VFXManager:
		VFXManager.spawn_floating_text(_ship_lock_pos + Vector2(0.0, -40.0), _translate_or(key, fallback), color, self)

func _resolve_item(def: Dictionary) -> void:
	var item_type: String = str(def.get("type", "neutral"))
	var score: int = int(round(float(def.get("score", 0)) * _reward_multiplier))
	match item_type:
		"claw_upgrade":
			_apply_upgrade(def)
			_feed_label("claw_boss_label_upgrade", "CLAW UPGRADE!", Color("#7FE58C"))
		"hazard":
			var pct: float = clampf(float(def.get("player_damage_percent", 0.18)), 0.0, 1.0)
			if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
				var max_hp_v: Variant = _player.get("max_hp")
				var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
				_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
			if VFXManager:
				VFXManager.spawn_explosion(_ship_lock_pos, 40.0, Color("#FF3B3B"), self, "", "res://assets/vfx/mine_explosion.tres", -1.0, 0.15, 0.2, false)
				if bool(ProfileManager.get_setting("screenshake_enabled", true)):
					VFXManager.screen_shake(8, 0.3)
			_feed_label("claw_boss_label_hazard", "BOMB!", Color("#FF3B3B"))
		"shield":
			# Pas d'API de shield incrémental : recharge complète (pickup standard).
			if _player and is_instance_valid(_player) and _player.has_method("activate_shield"):
				_player.call("activate_shield")
			_feed_label("claw_boss_label_shield", "SHIELD!", Color("#5CE8FF"))
		"crystal":
			if _game and is_instance_valid(_game):
				if randf() <= clampf(float(def.get("bonus_crystal_chance", 1.0)), 0.0, 1.0) and _game.has_method("spawn_reward_crystal_at"):
					_game.call("spawn_reward_crystal_at", _ship_lock_pos, {"force_magnet_below_y": _ship_lock_pos.y - 60.0})
			_feed_label("claw_boss_label_crystal", "CRYSTAL!", Color("#C77CFF"))
		"attack":
			_fire_attack(def, _feed_attack_count == 1)
			_feed_label("claw_boss_label_attack", "MISSILE!", Color("#FF8A5C"))
		_:
			pass
	if score > 0 and _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", score, _ship_lock_pos)

func _start_cooldown() -> void:
	_state = State.COOLDOWN
	_state_timer = _cooldown_sec
	_animate_claw(false) # ouverture = fermeture inversée
	# L'upgrade active s'use d'un grab à chaque cycle complet.
	if not _upgrade.is_empty():
		_upgrade["grabs_left"] = int(_upgrade.get("grabs_left", 1)) - 1
		if int(_upgrade["grabs_left"]) <= 0:
			_upgrade = {}

# =============================================================================
# UPGRADES DE PINCE
# =============================================================================

## Une seule upgrade active : la nouvelle remplace l'ancienne.
func _apply_upgrade(def: Dictionary) -> void:
	var upgrade_id: String = str(def.get("claw_upgrade_id", ""))
	var upgrade_def_v: Variant = _claw_upgrade_defs.get(upgrade_id, {})
	if not (upgrade_def_v is Dictionary) or (upgrade_def_v as Dictionary).is_empty():
		return
	_upgrade = {
		"id": upgrade_id,
		"grabs_left": maxi(1, int(def.get("duration_grabs", 3))),
		"def": upgrade_def_v
	}

func _claw_mult(key: String) -> float:
	if _upgrade.is_empty():
		return 1.0
	return maxf(0.05, float((_upgrade.get("def", {}) as Dictionary).get(key, 1.0)))

func _claw_bonus_int(key: String) -> int:
	if _upgrade.is_empty():
		return 0
	return int((_upgrade.get("def", {}) as Dictionary).get(key, 0))

## Aimant (upgrade magnet) : attire les objets "métalliques" (attack + hazard,
## bombes incluses — c'est le malus assumé) vers le X de la pince en descente.
func _apply_magnet(delta: float) -> void:
	var radius: float = _claw_mult("metal_attraction_radius_px")
	if _upgrade.is_empty() or radius <= 1.0:
		return
	for item_v in _items:
		var item: Dictionary = item_v as Dictionary
		if bool(item.get("grabbed", false)):
			continue
		var item_type: String = str((item.get("def", {}) as Dictionary).get("type", ""))
		if item_type != "attack" and item_type != "hazard":
			continue
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		if absf(pos.x - _claw_x) <= radius:
			_wake_item(item)
			var vel: Vector2 = item.get("vel", Vector2.ZERO)
			vel.x += signf(_claw_x - pos.x) * 260.0 * delta
			item["vel"] = vel

# =============================================================================
# ATTAQUES VISUELLES VAISSEAU -> BOSS
# =============================================================================

## Projectile visuel maison : impact garanti (le boss est décoratif, pas de
## vraie collision). Variantes data par item (durée/échelle/taille d'impact).
func _fire_attack(def: Dictionary, single_attack: bool) -> void:
	var shot := Node2D.new()
	shot.z_as_relative = false
	shot.z_index = 15
	var id: String = str(def.get("id", ""))
	if _item_textures.has(id):
		var spr := Sprite2D.new()
		spr.texture = _item_textures[id]
		var tex_size: Vector2 = (_item_textures[id] as Texture2D).get_size()
		if tex_size.x > 0.0:
			spr.scale = Vector2.ONE * (26.0 / maxf(tex_size.x, tex_size.y)) * maxf(0.3, float(def.get("attack_shot_scale", 1.0)))
		spr.modulate = Color(str(def.get("tint", _get_conf("attack_color", "#FF8A5C"))))
		shot.add_child(spr)
	else:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(0.0, -12.0), Vector2(7.0, 10.0), Vector2(-7.0, 10.0)])
		poly.color = Color(str(_get_conf("attack_color", "#FF8A5C")))
		shot.add_child(poly)
	add_child(shot)
	var from: Vector2 = _ship_lock_pos + Vector2(0.0, -30.0)
	var target: Vector2 = _boss_center + Vector2(
		randf_range(-_boss_visual_size.x * 0.3, _boss_visual_size.x * 0.3),
		randf_range(-_boss_visual_size.y * 0.25, _boss_visual_size.y * 0.25))
	shot.global_position = from
	_shots.append({
		"node": shot,
		"from": from,
		"to": target,
		"t": 0.0,
		"duration": maxf(0.1, float(def.get("attack_shot_duration_sec", 0.35))),
		"def": def,
		"single": single_attack
	})

func _update_shots(delta: float) -> void:
	for i in range(_shots.size() - 1, -1, -1):
		var shot: Dictionary = _shots[i]
		var t: float = float(shot.get("t", 0.0)) + delta / float(shot.get("duration", 0.35))
		shot["t"] = t
		var from: Vector2 = shot.get("from", Vector2.ZERO)
		var to: Vector2 = shot.get("to", Vector2.ZERO)
		var node_v: Variant = shot.get("node", null)
		if t >= 1.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_shots.remove_at(i)
			_on_shot_impact(shot.get("def", {}) as Dictionary, bool(shot.get("single", false)), to)
			continue
		var eased: float = ease(clampf(t, 0.0, 1.0), 0.6)
		var pos: Vector2 = from.lerp(to, eased)
		# Arc léger perpendiculaire à la trajectoire.
		var perp: Vector2 = (to - from).orthogonal().normalized()
		pos += perp * sin(t * PI) * 30.0
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			node.rotation = (to - node.global_position).angle() + PI * 0.5
			node.global_position = pos

func _on_shot_impact(def: Dictionary, single_attack: bool, at_pos: Vector2) -> void:
	var impact_cfg_v: Variant = _get_conf("boss_hit_explosion", {})
	var impact_cfg: Dictionary = impact_cfg_v if impact_cfg_v is Dictionary else {}
	if VFXManager:
		VFXManager.spawn_explosion(
			at_pos,
			maxf(8.0, float(def.get("attack_impact_size", impact_cfg.get("size", 56.0)))),
			Color("#FFAA00"), self,
			str(impact_cfg.get("asset", "")),
			str(impact_cfg.get("asset_anim", "res://assets/vfx/mine_explosion.tres")),
			-1.0, 0.12, maxf(0.05, float(impact_cfg.get("duration", 0.2))), false)
		if _boss_sprite and is_instance_valid(_boss_sprite):
			VFXManager.flash_sprite(_boss_node, Color(1.6, 1.6, 1.6), 0.08)
		if bool(ProfileManager.get_setting("screenshake_enabled", true)):
			VFXManager.screen_shake(3 if float(def.get("attack_shot_scale", 1.0)) < 1.3 else 6, 0.2)
	var precision_mult: float = 1.0
	if single_attack and not _upgrade.is_empty():
		precision_mult = _claw_mult("single_attack_damage_multiplier")
	# 10 attaques standard (0.10) tuent un boss à attack_pickups_to_kill = 10 ;
	# la clé plate attack_pickups_to_kill est LE knob de difficulté (per_level).
	_damage_boss(clampf(float(def.get("boss_damage_percent", 0.10)), 0.0, 1.0) * (10.0 / _attack_pickups_to_kill) * precision_mult)

func _damage_boss(pct: float) -> void:
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	_boss_health = clampf(_boss_health - pct, 0.0, 1.0)
	if _hud and is_instance_valid(_hud) and _hud.has_method("update_boss_health"):
		_hud.call("update_boss_health", int(round(_boss_health * 1000.0)), 1000)
	if _boss_health <= 0.0:
		_start_boss_death()

# =============================================================================
# FINS (mort / fuite du boss)
# =============================================================================

func _start_boss_death() -> void:
	if _state == State.BOSS_DEATH or _state == State.DONE:
		return
	_state = State.BOSS_DEATH
	_state_timer = _boss_death_anim_sec
	_grab_label_hide()
	_grant_kill_rewards()
	var death_cfg_v: Variant = _get_conf("boss_death_explosion", {})
	var death_cfg: Dictionary = death_cfg_v if death_cfg_v is Dictionary else {}
	if VFXManager and _boss_node and is_instance_valid(_boss_node):
		VFXManager.spawn_explosion(
			_boss_node.position,
			maxf(20.0, float(death_cfg.get("size", 140.0))),
			Color("#FFAA00"), self,
			str(death_cfg.get("asset", "")),
			str(death_cfg.get("asset_anim", "res://assets/vfx/boss_explosion.tres")),
			-1.0, 0.3, maxf(0.1, float(death_cfg.get("duration", 0.4))), false)
		if bool(ProfileManager.get_setting("screenshake_enabled", true)):
			VFXManager.screen_shake(12, 0.5)
	if _boss_node and is_instance_valid(_boss_node):
		var tween: Tween = create_tween()
		tween.tween_property(_boss_node, "modulate:a", 0.0, _boss_death_anim_sec * 0.7)

## Timer écoulé : le boss s'en va (pas de bonus de kill). Déclenché uniquement
## depuis AIM/COOLDOWN — un grab en cours se termine toujours.
func _start_boss_escape() -> void:
	if _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	_state = State.BOSS_ESCAPE
	_state_timer = _boss_escape_anim_sec
	_grab_label_hide()
	if _boss_node and is_instance_valid(_boss_node):
		var tween: Tween = create_tween()
		tween.tween_property(_boss_node, "position:y", -_boss_visual_size.y, _boss_escape_anim_sec) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _grab_label_hide() -> void:
	if _grab_label and is_instance_valid(_grab_label):
		_grab_label.visible = false

## Boss tué : gros score + cristaux + loot "uncommon ou +" (rareté tirée sur
## une table pondérée au-dessus du plancher data kill_loot_min_rarity).
func _grant_kill_rewards() -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var center: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
	var points: int = int(round(float(_kill_score) * _reward_multiplier))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, center)
	if _game.has_method("spawn_reward_crystal_at"):
		for _i in range(_kill_crystals):
			_game.call("spawn_reward_crystal_at", center, {"force_magnet_below_y": _ship_lock_pos.y - 60.0})
	if _game.has_method("spawn_reward_equipment_at"):
		var extra: Dictionary = {"auto_collect_below_y": _ship_lock_pos.y + 40.0}
		var rarity: String = _roll_kill_rarity()
		if rarity != "":
			_game.call("spawn_reward_equipment_at", center, 1.0, extra, rarity)
		else:
			_game.call("spawn_reward_equipment_at", center, _kill_loot_quality_mult, extra)

## Table pondérée au-dessus du plancher (min_rarity vide = fallback quality_mult).
func _roll_kill_rarity() -> String:
	if _kill_loot_min_rarity == "":
		return ""
	var order: Array = ["common", "uncommon", "rare", "epic", "legendary"]
	var weights: Dictionary = {"common": 0.0, "uncommon": 70.0, "rare": 24.0, "epic": 5.0, "legendary": 1.0}
	var min_index: int = maxi(0, order.find(_kill_loot_min_rarity))
	var total: float = 0.0
	for i in range(min_index, order.size()):
		total += float(weights.get(order[i], 0.0))
	if total <= 0.0:
		return _kill_loot_min_rarity
	var roll: float = randf() * total
	for i in range(min_index, order.size()):
		roll -= float(weights.get(order[i], 0.0))
		if roll <= 0.0:
			return order[i]
	return _kill_loot_min_rarity

# =============================================================================
# INPUT (AIM uniquement : drag X + release/tap = lancer ; clavier en debug)
# =============================================================================

func _input(event: InputEvent) -> void:
	if _state != State.AIM:
		# Libération défensive : un doigt levé hors AIM libère la capture.
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed \
			and (event as InputEventScreenTouch).index == _touch_id:
			_touch_id = -1
		elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and _touch_id == MOUSE_CAPTURE_ID:
			_touch_id = -1
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			if _touch_id == -1:
				_touch_id = touch.index
				_set_claw_target_from_screen(touch.position)
		elif touch.index == _touch_id:
			_touch_id = -1
			_launch_grab() # release = lancer (tap sec = lancer sur place)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_set_claw_target_from_screen(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed:
			if _touch_id == -1:
				_touch_id = MOUSE_CAPTURE_ID
				_set_claw_target_from_screen(mouse_btn.position)
		elif _touch_id == MOUSE_CAPTURE_ID:
			_touch_id = -1
			_launch_grab()
	elif event is InputEventMouseMotion and _touch_id == MOUSE_CAPTURE_ID:
		_set_claw_target_from_screen((event as InputEventMouseMotion).position)

func _set_claw_target_from_screen(screen_pos: Vector2) -> void:
	var world: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	_claw_target_x = clampf(world.x, _pit_rect.position.x + 20.0, _pit_rect.end.x - 20.0)

## Desktop : flèches pour déplacer, espace/entrée pour lancer.
func _handle_keyboard_aim(delta: float) -> void:
	var move: float = 0.0
	if Input.is_action_pressed("ui_left"):
		move -= 1.0
	if Input.is_action_pressed("ui_right"):
		move += 1.0
	if move != 0.0 and _touch_id == -1:
		_claw_target_x = clampf(_claw_target_x + move * _claw_move_speed * delta, _pit_rect.position.x + 20.0, _pit_rect.end.x - 20.0)
	if Input.is_action_just_pressed("ui_accept"):
		_launch_grab()

# =============================================================================
# MAIN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# Joueur mort : le flux game-over a pris la main — geler sans émettre.
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	_update_grab_label()
	_update_pit_physics(delta)
	_update_shots(delta)
	_update_held_items(delta)
	_update_claw_visual()
	if _auto_grab_flash > 0.0:
		_auto_grab_flash = maxf(0.0, _auto_grab_flash - delta)
	match _state:
		State.INTRO:
			_update_intro(delta)
		State.AIM:
			_runtime_feed(delta)
			_handle_keyboard_aim(delta)
			_claw_x = move_toward(_claw_x, _claw_target_x, _claw_move_speed * delta)
			_grab_countdown -= delta
			if _grab_countdown <= 0.0:
				# "AUTO GRAB" affiché brièvement puis descente auto.
				if _grab_label and is_instance_valid(_grab_label):
					_grab_label.text = _translate_or("claw_boss_auto_grab", "AUTO GRAB")
				_auto_grab_flash = 0.4
				_launch_grab()
			elif _elapsed >= _duration:
				_start_boss_escape()
		State.DROP:
			_runtime_feed(delta)
			_apply_magnet(delta)
			_claw_y += _claw_drop_speed * delta
			if _claw_y >= _claw_bottom_y:
				_claw_y = _claw_bottom_y
				# Sélection AVANT l'anim : le packing calcule _closure (objets
				# larges = fermeture bloquée), l'anim se ferme jusqu'au blocage.
				_select_captures()
				_state = State.CLOSE
				_state_timer = _close_anim_sec
				_animate_claw(true)
		State.CLOSE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_raise_start_y = _claw_y
				_wobble_time = 0.0
				_state = State.RAISE
		State.RAISE:
			_runtime_feed(delta)
			_update_raise(delta)
		State.FEED:
			_update_feed(delta)
		State.COOLDOWN:
			_runtime_feed(delta)
			_state_timer -= delta
			if _state_timer <= 0.0:
				if _elapsed >= _duration:
					_start_boss_escape()
				else:
					_enter_aim()
		State.BOSS_DEATH:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()
		State.BOSS_ESCAPE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()

func _update_intro(delta: float) -> void:
	match _intro_phase:
		0: # Arrivée du boss.
			_state_timer -= delta
			if _state_timer <= 0.0:
				_intro_phase = 1
				_intro_drop_timer = 0.0
		1: # Largage initial échelonné.
			_intro_drop_timer -= delta
			if _intro_drop_timer <= 0.0:
				_intro_drop_timer = 0.06
				_spawn_item_from_boss()
				_intro_drops_left -= 1
				if _intro_drops_left <= 0:
					_intro_phase = 2
					_state_timer = maxf(0.05, float(_get_conf("intro_settle_sec", 1.2)))
		2: # Les objets se calent, puis premier countdown de grab.
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_aim()

## Position de la pince + câble (attaché au dos du vaisseau).
func _update_claw_visual() -> void:
	if _claw_root == null or not is_instance_valid(_claw_root):
		return
	if _state == State.AIM or _state == State.INTRO or _state == State.COOLDOWN or _state == State.FEED:
		_claw_y = _claw_rest_y
		if _state != State.AIM:
			_claw_x = move_toward(_claw_x, _claw_target_x, _claw_move_speed * 0.016)
	_claw_root.position = Vector2(_claw_x, _claw_y)
	if _cable_line and is_instance_valid(_cable_line):
		var anchor: Vector2 = _ship_lock_pos + Vector2(0.0, 14.0)
		if _player and is_instance_valid(_player):
			anchor = _player.global_position + Vector2(0.0, 14.0)
		_cable_line.points = PackedVector2Array([anchor, Vector2(_claw_x, _claw_y - 8.0)])

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Restaure le joueur/HUD (barre boss comprise) AVANT de notifier la chaîne.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # items, pince, boss, labels sont enfants -> libérés ensemble

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Défensif : restaure toujours joueur/HUD si le manager est libéré autrement.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
