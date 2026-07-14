extends Node2D

## SnakeManager — Vague "snake" (refonte totale de l'ex path_trial, 13 juillet
## 2026) : layout façon match3/suika — 1/3 HAUT = boss décoratif avec barre de
## vie (pattern Match3Manager), 2/3 BAS = zone de jeu bordée où le VAISSEAU
## JOUEUR est la TÊTE du serpent. Steering à VITESSE CONSTANTE : la tête avance
## toujours et tourne vers le doigt (taux de virage plafonné), pas de doigt =
## tout droit. WRAP-AROUND aux 4 bords de la zone (sortir à droite = rentrer à
## gauche...). Le corps = segments qui suivent la trace de la tête (buffer de
## samples avec coutures de wrap — jamais d'interpolation à travers). Manger un
## item fait GRANDIR le serpent ET inflige des dégâts en % au boss (base de
## l'item + bonus par segment, ÷ boss_toughness_mult) ; se MORDRE = dégâts %
## HP (jamais létal en story) + queue coupée au segment mordu. Items
## data-driven (nourriture/dorée/cristal + powerups temporaires slow, virage+,
## fantôme, aimant — icônes bas-droite avec temps restant, labels d'effets).
## Boss mort : récompenses + self-finish anticipé en story ; respawn en Libre
## (continuous — la vague ne finit jamais par le timer). Contacts par distance
## (pas de physics), pool de segments pré-alloué, assets résolus au setup.

signal finished

enum State { INTRO, PLAY, BOSS_DEATH, BOSS_ESCAPE, DONE }

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 45.0
var _elapsed: float = 0.0
var _time: float = 0.0
var _reward_multiplier: float = 1.0

# Géométrie : zone de jeu (2/3 bas) + bordure.
var _play_rect: Rect2 = Rect2()
var _border_line: Line2D = null

# Tête : position/cap pilotés ici, poussés au Player chaque frame.
var _head_pos: Vector2 = Vector2.ZERO
var _head_angle: float = -PI * 0.5 # vers le haut
var _head_d: float = 0.0 # distance cumulée parcourue (les sauts de wrap ne comptent pas)

# Buffer de trace : samples { "pos": Vector2, "d": float, "seam": bool }.
# Une COUTURE (seam) = point d'entrée après un wrap, à distance cumulée
# inchangée — les segments ne s'interpolent jamais à travers.
var _trail: Array = []

# Segments : pool pré-alloué, seuls les _segment_count premiers sont visibles.
var _segment_pool: Array = [] # Node2D
var _segment_count: int = 0

# Items au sol. Entries: { "node": Node2D, "def": Dictionary }.
var _items: Array = []
var _item_defs: Array = []
var _item_weight_total: float = 0.0
var _item_timer: float = 0.0

# Effets temporaires (powerups) : effect_id -> time_left.
var _effects: Dictionary = {}
var _bite_invuln: float = 0.0

# HUD bas-droite : icônes des effets actifs (temps restant).
var _buff_bar: Node2D = null
var _buff_icons: Dictionary = {} # effect_id -> { "root": Node2D, "badge": Label }

# Événements [E] (13 juillet 2026) : scheduler anti-répétition, UN SEUL actif,
# toasts centraux. Les obstacles portés par l'événement vivent dans des listes
# dédiées (le fruit bombe interagit avec) et sont purgés à _end_event.
var _event_timer: float = 0.0
var _last_event_id: String = ""
var _event_active: String = ""
var _event: Dictionary = {}
var _asteroids: Array = [] # { "node", "vel", "age", "size" }
var _walls: Array = [] # { "node", "rect": Rect2 }
var _zones: Array = [] # { "node", "pos", "radius", "tick_timer" }
var _pests: Array = [] # { "node" }
var _meteor_marks: Array = [] # télégraphes { "node", "pos", "timer" }
var _arena_inset: float = 0.0 # rétrécissement d'arène (px, animé)
var _time_bonus_total: float = 0.0 # cap cumulé des chronos (marge WaveManager)
var _asteroid_resources: Array = []
var _obstacle_skins: Array = [] # world skin_overrides.obstacles.explosives
var _add_material: CanvasItemMaterial = null

# Boss (pattern Match3Manager).
var _boss_defs: Array = []
var _boss_def: Dictionary = {}
var _boss_node: Node2D = null
var _boss_sprite: Node2D = null
var _boss_health: float = 1.0
var _boss_center: Vector2 = Vector2.ZERO
var _boss_visual_size: Vector2 = Vector2(200, 200)
var _boss_respawn_timer: float = 0.0

# Input steering (pattern slice_rush/gravity_hole : lecture passive).
var _touch_active: bool = false
var _touch_id: int = -1
var _finger: Vector2 = Vector2.ZERO
const MOUSE_CAPTURE_ID: int = -2

var _countdown_label: Label = null
var _finished_emitted: bool = false

static var _resource_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("snake") if DataManager else {}
	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("round_duration_sec", 45.0))))
	_reward_multiplier = maxf(0.05, float(_config.get("reward_multiplier", 1.0)))
	var skins_v: Variant = _config.get("_obstacle_skins", [])
	_obstacle_skins = (skins_v as Array) if skins_v is Array else []
	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_resolve_asteroid_resources()
	_event_timer = maxf(2.0, float(_get_conf("event_first_delay_sec", 10.0)))

	_compute_geometry()
	_build_border()
	_parse_items()
	_build_segment_pool()
	_seed_snake()
	_begin_player_mode()
	_begin_hud_mode()
	_ensure_countdown_label()
	if bool(_get_conf("boss_enabled", true)):
		_spawn_boss()

	_item_timer = 0.6 # premier item rapide
	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("warmup_sec", 1.0)))
	set_process(true)

## Mode libre "continuous" (marqueur countdown_hidden) : la boucle ne finit
## jamais par le timer — le boss respawne au lieu de conclure la vague.
func _is_free_mode() -> bool:
	return bool(_config.get("countdown_hidden", false))

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — serpent et boss préservés, valeurs relues live.
func update_free_mode_config(cfg: Dictionary) -> void:
	for key in ["boss_toughness_mult", "base_speed_px_sec", "turn_rate_deg_sec",
		"item_spawn_interval_sec", "bite_damage_percent", "bite_never_lethal",
		"event_interval_sec_min", "event_interval_sec_max",
		"_free_level_progress"]:
		if cfg.has(key):
			_config[key] = cfg[key]

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_snake"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_snake", merged)
		_push_head_to_player()

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_snake"):
		_player.call("end_snake")

## Les boutons de pouvoir chevauchent la zone basse ; inutiles ici (tir coupé).
func _begin_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", true)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", false)

func _restore_hud_mode() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("set_power_buttons_suppressed"):
		_hud.call("set_power_buttons_suppressed", false)
	if _hud.has_method("set_joystick_visual_enabled"):
		_hud.call("set_joystick_visual_enabled", true)
	if _hud.has_method("hide_boss_health"):
		_hud.call("hide_boss_health")

func _translate_or(key: String, fallback: String) -> String:
	if key != "" and typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Toast central (pipeline splash « Vague X » du jeu).
func _toast(key: String, fallback: String, color_html: String = "") -> void:
	if _game and is_instance_valid(_game) and _game.has_method("show_center_splash"):
		_game.call("show_center_splash", _translate_or(key, fallback), "", color_html)

# =============================================================================
# LABELS D'EFFETS (toggle global wave_types.json > effect_labels_enabled)
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
	label.position = Vector2(-120.0, size_px * 0.5 + 4.0)
	node.add_child(label)

# =============================================================================
# ASSETS (resolved once at setup — never load() in a gameplay frame)
# =============================================================================

static func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _resource_cache.has(path):
		return _resource_cache[path] as Resource
	if not ResourceLoader.exists(path):
		_resource_cache[path] = null
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	_resource_cache[path] = res
	return res

## AnimatedSprite2D (.tres) / Sprite2D (.png) fit à size_px, sinon null.
func _build_sprite_fit(res: Resource, size_px: float) -> Node2D:
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name) and names.size() > 0:
			anim_name = StringName(names[0])
		if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
			var anim := AnimatedSprite2D.new()
			anim.sprite_frames = frames
			anim.play(anim_name)
			var tex: Texture2D = frames.get_frame_texture(anim_name, 0)
			if tex:
				var t_size: Vector2 = tex.get_size()
				if t_size.x > 0.0 and t_size.y > 0.0:
					anim.scale = Vector2.ONE * (size_px / maxf(t_size.x, t_size.y))
			return anim
		return null
	if res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = res as Texture2D
		var tex_size: Vector2 = (res as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (size_px / maxf(tex_size.x, tex_size.y))
		return sprite
	return null

func _build_circle(radius: float, color: Color, points: int = 18) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(points):
		var a: float = TAU * float(k) / float(points)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = color
	return poly

# =============================================================================
# GÉOMÉTRIE + BORDURE
# =============================================================================

func _compute_geometry() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var play_top: float = viewport_size.y * clampf(float(_get_conf("boss_area_height_ratio", 0.3)), 0.1, 0.5) \
		+ maxf(0.0, float(_get_conf("play_margin_top", 16.0)))
	var left: float = maxf(0.0, float(_get_conf("play_margin_left", 24.0)))
	var right: float = maxf(0.0, float(_get_conf("play_margin_right", 24.0)))
	var bottom: float = maxf(0.0, float(_get_conf("play_margin_bottom", 96.0)))
	_play_rect = Rect2(Vector2(left, play_top),
		Vector2(viewport_size.x - left - right, viewport_size.y - bottom - play_top))

## Rect de jeu EFFECTIF : le rétrécissement d'arène [E] applique un inset animé.
## Toute la logique (wrap, spawns, événements) passe par ici.
func _current_play_rect() -> Rect2:
	if _arena_inset <= 0.0:
		return _play_rect
	return Rect2(_play_rect.position + Vector2.ONE * _arena_inset,
		_play_rect.size - Vector2.ONE * _arena_inset * 2.0)

func _build_border() -> void:
	_border_line = Line2D.new()
	_border_line.closed = true
	_border_line.width = maxf(1.0, float(_get_conf("border_width_px", 4.0)))
	_border_line.default_color = Color(str(_get_conf("border_color", "#7FE58C80")))
	_border_line.z_as_relative = false
	_border_line.z_index = 6
	add_child(_border_line)
	_update_border_points()

func _update_border_points() -> void:
	if _border_line == null or not is_instance_valid(_border_line):
		return
	var rect: Rect2 = _current_play_rect()
	_border_line.points = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	])

## Assets des astéroïdes [E] : asteroid_assets[] sinon skins d'obstacles du monde.
func _resolve_asteroid_resources() -> void:
	_asteroid_resources.clear()
	var paths: Array = []
	var assets_v: Variant = _get_conf("asteroid_assets", [])
	if assets_v is Array:
		for asset_v in (assets_v as Array):
			if str(asset_v) != "":
				paths.append(str(asset_v))
	if paths.is_empty() and bool(_get_conf("asteroid_use_world_obstacles", true)):
		for skin_v in _obstacle_skins:
			if str(skin_v) != "":
				paths.append(str(skin_v))
	for path in paths:
		var res: Resource = _load_cached_resource(str(path))
		if res is SpriteFrames or res is Texture2D:
			_asteroid_resources.append(res)

# =============================================================================
# SERPENT : trace, segments, wrap
# =============================================================================

## Tête au centre de la zone, cap vers le haut ; la trace est pré-remplie en
## ligne droite SOUS la tête pour que les segments initiaux aient une position.
func _seed_snake() -> void:
	_head_pos = _play_rect.get_center()
	_head_angle = -PI * 0.5
	var spacing: float = maxf(8.0, float(_get_conf("segment_spacing_px", 34.0)))
	_segment_count = clampi(int(_get_conf("initial_segments", 4)), 0, _segment_pool.size())
	var seed_len: float = (float(_segment_count) + 2.0) * spacing
	_trail.clear()
	var step: float = maxf(2.0, float(_get_conf("sample_min_px", 5.0)))
	var n: int = int(ceil(seed_len / step))
	for k in range(n + 1):
		var d: float = seed_len * float(k) / float(n)
		_trail.append({
			"pos": _head_pos + Vector2.DOWN * (seed_len - d),
			"d": d,
			"seam": false
		})
	_head_d = seed_len
	_refresh_segment_visibility()

## Visuels des segments ENTIÈREMENT paramétrables : segment_assets[] (motif
## "cycle" répété le long du corps ou "random" par segment, fallback
## segment_asset unique puis cercle procédural) + tail_asset dédié au BOUT DE
## QUEUE (les deux visuels cohabitent sur chaque node du pool, on toggle selon
## l'index — le "dernier" segment change quand le serpent grandit/raccourcit).
func _build_segment_pool() -> void:
	var count: int = clampi(int(_get_conf("max_segments", 40)), 4, 80)
	var size_px: float = maxf(12.0, float(_get_conf("segment_px", 40.0)))
	var body_resources: Array = []
	var assets_v: Variant = _get_conf("segment_assets", [])
	if assets_v is Array:
		for asset_v in (assets_v as Array):
			var res: Resource = _load_cached_resource(str(asset_v))
			if res is SpriteFrames or res is Texture2D:
				body_resources.append(res)
	if body_resources.is_empty():
		var single: Resource = _load_cached_resource(str(_get_conf("segment_asset", "")))
		if single is SpriteFrames or single is Texture2D:
			body_resources.append(single)
	var tail_res: Resource = _load_cached_resource(str(_get_conf("tail_asset", "")))
	var random_mode: bool = str(_get_conf("segment_asset_mode", "cycle")) == "random"
	for i in range(count):
		var node := Node2D.new()
		node.name = "SnakeSegment%d" % i
		node.z_as_relative = false
		node.z_index = 7
		var body_res: Resource = null
		if not body_resources.is_empty():
			body_res = (body_resources[randi() % body_resources.size()] if random_mode \
				else body_resources[i % body_resources.size()]) as Resource
		var visual: Node2D = _build_sprite_fit(body_res, size_px)
		if visual == null:
			visual = _build_circle(size_px * 0.5, Color.WHITE)
		node.add_child(visual)
		node.set_meta("body", visual)
		var tail_visual: Node2D = _build_sprite_fit(tail_res, size_px)
		if tail_visual != null:
			tail_visual.visible = false
			node.add_child(tail_visual)
			node.set_meta("tail", tail_visual)
		node.visible = false
		add_child(node)
		_segment_pool.append(node)

## Dégradé tête→queue optionnel (segment_gradient_enabled — false pour des
## assets déjà colorés) + swap du visuel de bout de queue sur le dernier actif.
func _refresh_segment_visibility() -> void:
	var gradient: bool = bool(_get_conf("segment_gradient_enabled", true))
	var head_color := Color(str(_get_conf("segment_fallback_color", "#57C7FF")))
	var tail_color := Color(str(_get_conf("segment_tail_tint", "#2E86C1")))
	for i in range(_segment_pool.size()):
		var node: Node2D = _segment_pool[i]
		var active: bool = i < _segment_count
		node.visible = active
		if node.has_meta("tail"):
			var tail_visual: Node2D = node.get_meta("tail") as Node2D
			var body_visual: Node2D = null
			if node.has_meta("body"):
				body_visual = node.get_meta("body") as Node2D
			var is_tail: bool = active and i == _segment_count - 1
			if tail_visual and is_instance_valid(tail_visual):
				tail_visual.visible = is_tail
			if body_visual and is_instance_valid(body_visual):
				body_visual.visible = not is_tail
		if active:
			if gradient:
				var t: float = float(i) / maxf(1.0, float(_segment_count - 1))
				node.modulate = head_color.lerp(tail_color, t)
			else:
				node.modulate = Color.WHITE

## Un sample par sample_min_px parcourus ; les coutures de wrap gèlent la
## distance cumulée (le saut ne compte pas comme longueur de corps).
func _push_sample(pos: Vector2, seam: bool = false) -> void:
	_trail.append({"pos": pos, "d": _head_d, "seam": seam})

func _trim_trail() -> void:
	var spacing: float = maxf(8.0, float(_get_conf("segment_spacing_px", 34.0)))
	var keep: float = (float(_segment_count) + 2.0) * spacing
	while _trail.size() > 2 and _head_d - float((_trail[1] as Dictionary).get("d", 0.0)) > keep:
		_trail.pop_front()

## Place les segments à i × spacing derrière la tête en un SEUL parcours
## arrière du buffer (les cibles décroissent). Aucune interpolation à travers
## une couture : les spans de wrap sont de longueur nulle (snap propre).
func _place_segments() -> void:
	if _segment_count <= 0 or _trail.size() < 2:
		return
	var spacing: float = maxf(8.0, float(_get_conf("segment_spacing_px", 34.0)))
	var orient: bool = bool(_get_conf("segment_orient", false))
	var idx: int = _trail.size() - 1
	var newer: Dictionary = _trail[idx]
	var newer_pos: Vector2 = _head_pos
	var newer_d: float = _head_d
	for i in range(_segment_count):
		var target_d: float = _head_d - float(i + 1) * spacing
		while idx > 0 and float((_trail[idx] as Dictionary).get("d", 0.0)) > target_d:
			newer = _trail[idx]
			newer_pos = newer.get("pos", Vector2.ZERO)
			newer_d = float(newer.get("d", 0.0))
			idx -= 1
		var older: Dictionary = _trail[idx]
		var older_pos: Vector2 = older.get("pos", Vector2.ZERO)
		var older_d: float = float(older.get("d", 0.0))
		var span: float = newer_d - older_d
		var seg_pos: Vector2
		if span <= 0.01 or bool(newer.get("seam", false)):
			seg_pos = newer_pos if target_d >= newer_d else older_pos
		else:
			seg_pos = older_pos.lerp(newer_pos, clampf((target_d - older_d) / span, 0.0, 1.0))
		var node: Node2D = _segment_pool[i]
		if is_instance_valid(node):
			node.position = seg_pos
			# Orientation optionnelle (assets à écailles/flèches) : vers le
			# segment précédent (la tête pour le premier). Un saut de wrap
			# donnerait une direction plein écran : on garde alors la rotation
			# précédente (le segment se réoriente au frame suivant).
			if orient:
				var toward: Vector2 = _head_pos if i == 0 else (_segment_pool[i - 1] as Node2D).position
				var dir: Vector2 = toward - seg_pos
				if dir.length_squared() > 1.0 and dir.length() <= spacing * 3.0:
					node.rotation = dir.angle() + PI * 0.5

func _push_head_to_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_snake_lock_pos"):
		_player.call("set_snake_lock_pos", _head_pos)
	if _player.has_method("set_snake_facing"):
		# Le sprite pointe vers le haut : correction +90°.
		_player.call("set_snake_facing", _head_angle + PI * 0.5)

# =============================================================================
# INPUT (lecture passive : le doigt donne la direction visée)
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _touch_id == -1:
			_touch_id = touch.index
			_touch_active = true
			_finger = touch.position
		elif not touch.pressed and touch.index == _touch_id:
			_touch_id = -1
			_touch_active = false
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_finger = drag.position
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed and _touch_id == -1:
			_touch_id = MOUSE_CAPTURE_ID
			_touch_active = true
			_finger = mouse_btn.position
		elif not mouse_btn.pressed and _touch_id == MOUSE_CAPTURE_ID:
			_touch_id = -1
			_touch_active = false
	elif event is InputEventMouseMotion:
		if _touch_id == MOUSE_CAPTURE_ID:
			_finger = (event as InputEventMouseMotion).position

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
	_elapsed += minf(delta, 0.25)
	_bite_invuln = maxf(0.0, _bite_invuln - dt)
	_update_countdown_label()

	match _state:
		State.INTRO:
			_state_timer -= delta
			_push_head_to_player()
			if _state_timer <= 0.0:
				_state = State.PLAY
		State.PLAY:
			if _elapsed >= _duration and not _is_free_mode():
				_start_boss_escape()
			_tick_movement(dt)
			_tick_items(dt)
			_tick_effects(dt)
			_tick_event_scheduler(dt)
			_check_bite()
		State.BOSS_DEATH, State.BOSS_ESCAPE:
			# Le serpent continue de glisser pendant l'anim du boss.
			_tick_movement(dt)
			_tick_effects(dt)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()

	_tick_active_event(dt)
	_tick_obstacles(dt)

	# Respawn du boss en Libre (la boucle continue après un kill).
	if _boss_respawn_timer > 0.0 and _state != State.DONE:
		_boss_respawn_timer -= delta
		if _boss_respawn_timer <= 0.0:
			_spawn_boss()

	_update_buff_icons()

# =============================================================================
# MOUVEMENT : steering à vitesse constante + wrap-around
# =============================================================================

func _current_speed() -> float:
	var speed: float = maxf(40.0, float(_get_conf("base_speed_px_sec", 220.0))) \
		+ maxf(0.0, float(_get_conf("speed_per_segment_px_sec", 4.0))) * float(_segment_count)
	speed = minf(speed, maxf(60.0, float(_get_conf("max_speed_px_sec", 420.0))))
	if _effects.has("slow"):
		speed *= clampf(float(_effect_value("slow", 0.65)), 0.2, 1.0)
	return speed

func _current_turn_rate() -> float:
	var rate: float = maxf(
		maxf(30.0, float(_get_conf("min_turn_rate_deg_sec", 160.0))),
		float(_get_conf("turn_rate_deg_sec", 240.0)))
	if _effects.has("turn_boost"):
		rate *= maxf(1.0, float(_effect_value("turn_boost", 1.8)))
	return deg_to_rad(rate)

func _effect_value(effect_id: String, fallback: float) -> float:
	for def_v in _item_defs:
		if str((def_v as Dictionary).get("effect", "")) == effect_id:
			return float((def_v as Dictionary).get("effect_value", fallback))
	return fallback

func _tick_movement(dt: float) -> void:
	# Cap : rotation plafonnée vers le doigt (plus courte différence angulaire).
	if _touch_active:
		var to_finger: Vector2 = _finger - _head_pos
		if to_finger.length() > 12.0:
			var diff: float = wrapf(to_finger.angle() - _head_angle, -PI, PI)
			var max_turn: float = _current_turn_rate() * dt
			_head_angle += clampf(diff, -max_turn, max_turn)
	# Avance constante : la distance parcourue alimente la trace.
	var step_vec: Vector2 = Vector2.from_angle(_head_angle) * _current_speed() * dt
	# Vent solaire [E] : dérive constante télégraphée appliquée à la tête.
	if _event_active == "wind" and str(_event.get("phase", "")) == "blow":
		step_vec += (_event.get("dir", Vector2.ZERO) as Vector2) \
			* maxf(0.0, float(_get_conf("wind_px_sec", 90.0))) * dt
	_head_pos += step_vec
	_head_d += step_vec.length()
	var sample_min: float = maxf(2.0, float(_get_conf("sample_min_px", 5.0)))
	var last: Dictionary = _trail[_trail.size() - 1]
	# Wrap-around : sortie d'un bord = entrée par le bord opposé, couture dans
	# la trace (le saut ne compte pas comme distance — pas de segment étiré).
	var rect: Rect2 = _current_play_rect()
	var wrapped: bool = false
	var wrapped_pos: Vector2 = _head_pos
	if _head_pos.x < rect.position.x:
		wrapped_pos.x += rect.size.x
		wrapped = true
	elif _head_pos.x > rect.end.x:
		wrapped_pos.x -= rect.size.x
		wrapped = true
	if _head_pos.y < rect.position.y:
		wrapped_pos.y += rect.size.y
		wrapped = true
	elif _head_pos.y > rect.end.y:
		wrapped_pos.y -= rect.size.y
		wrapped = true
	if wrapped:
		_push_sample(_head_pos) # point de sortie (hors zone, fin du tronçon)
		_head_pos = wrapped_pos
		_push_sample(_head_pos, true) # point d'entrée (couture, d inchangée)
	elif (last.get("pos", Vector2.ZERO) as Vector2).distance_to(_head_pos) >= sample_min:
		_push_sample(_head_pos)
	_trim_trail()
	_place_segments()
	_push_head_to_player()

# =============================================================================
# MORSURE : dégâts + queue coupée
# =============================================================================

func _check_bite() -> void:
	if _bite_invuln > 0.0 or _effects.has("ghost") or _segment_count <= 0:
		return
	var grace: int = maxi(0, int(_get_conf("grace_segments", 6)))
	if _segment_count <= grace:
		return
	var bite_radius: float = maxf(6.0, float(_get_conf("bite_radius_px", 20.0)))
	var bite_sq: float = bite_radius * bite_radius
	for j in range(grace, _segment_count):
		var node: Node2D = _segment_pool[j]
		if not is_instance_valid(node):
			continue
		if _head_pos.distance_squared_to(node.position) <= bite_sq:
			_on_bitten(j)
			return

func _on_bitten(segment_index: int) -> void:
	_bite_invuln = maxf(0.2, float(_get_conf("bite_invuln_sec", 1.2)))
	# Dégâts % HP max (voie standard, shield d'abord ; jamais létal en story).
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("bite_damage_percent", 0.08)), 0.0, 1.0)
		var dmg: int = maxi(1, int(ceil(float(max_hp) * pct)))
		if bool(_get_conf("bite_never_lethal", true)):
			var hp_v: Variant = _player.get("current_hp")
			var current_hp: int = int(hp_v) if (hp_v is int or hp_v is float) else max_hp
			dmg = mini(dmg, maxi(0, current_hp - 1))
		if dmg > 0:
			_player.call("take_damage", dmg)
	if _player == null or not is_instance_valid(_player):
		return
	# Queue coupée à partir du segment mordu (VFX plafonnés).
	var removed: int = _segment_count - segment_index
	for k in range(segment_index, mini(_segment_count, segment_index + 4)):
		var node: Node2D = _segment_pool[k]
		if is_instance_valid(node) and VFXManager:
			VFXManager.spawn_impact(node.global_position, 14.0, self)
	_segment_count = segment_index
	_refresh_segment_visibility()
	var crystal_per: int = maxi(0, int(_get_conf("bite_cut_crystal_per_segments", 0)))
	if crystal_per > 0 and _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		@warning_ignore("integer_division")
		var crystal_count: int = removed / crystal_per
		for c in range(crystal_count):
			_game.call("spawn_reward_crystal_at", _head_pos)
	if VFXManager:
		VFXManager.flash_sprite(_player, Color(1.0, 0.35, 0.3), 0.25)
		VFXManager.screen_shake(6.0, 0.25)
		VFXManager.spawn_floating_text(_head_pos + Vector2(0.0, -50.0),
			_translate_or("snake_toast_bite", "OUCH! TAIL CUT!"), Color("#FF5A5A"), self)

# =============================================================================
# ITEMS : spawn, collecte, croissance, effets
# =============================================================================

func _parse_items() -> void:
	_item_defs.clear()
	_item_weight_total = 0.0
	var defs_v: Variant = _get_conf("items", [])
	if defs_v is Array:
		for def_v in (defs_v as Array):
			if not (def_v is Dictionary):
				continue
			var src: Dictionary = (def_v as Dictionary).duplicate(true)
			src["weight"] = maxf(0.0, float(src.get("weight", 1.0)))
			src["resource"] = _load_cached_resource(str(src.get("asset", "")))
			_item_defs.append(src)
			_item_weight_total += float(src["weight"])

## Tirage pondéré avec gate générique only_below_hp_ratio (ex. cœur réparateur
## éligible seulement sous 50 % de HP) : liste d'éligibles recalculée au tirage.
func _pick_item_def() -> Dictionary:
	if _item_defs.is_empty():
		return {}
	var hp_ratio: float = 1.0
	if _player and is_instance_valid(_player):
		var max_hp_v: Variant = _player.get("max_hp")
		var hp_v: Variant = _player.get("current_hp")
		if (max_hp_v is int or max_hp_v is float) and (hp_v is int or hp_v is float) and float(max_hp_v) > 0.0:
			hp_ratio = clampf(float(hp_v) / float(max_hp_v), 0.0, 1.0)
	var eligible: Array = []
	var total: float = 0.0
	for def_v in _item_defs:
		var def: Dictionary = def_v as Dictionary
		if def.has("only_below_hp_ratio") and hp_ratio >= float(def.get("only_below_hp_ratio", 1.0)):
			continue
		eligible.append(def)
		total += float(def.get("weight", 1.0))
	if eligible.is_empty():
		return {}
	var roll: float = randf() * maxf(0.001, total)
	for def_v in eligible:
		roll -= float((def_v as Dictionary).get("weight", 1.0))
		if roll <= 0.0:
			return def_v as Dictionary
	return eligible[eligible.size() - 1] as Dictionary

func _tick_items(dt: float) -> void:
	_item_timer -= dt
	if _item_timer <= 0.0:
		var interval: float = maxf(
			maxf(0.2, float(_get_conf("min_item_spawn_interval_sec", 0.7))),
			float(_get_conf("item_spawn_interval_sec", 1.6)))
		# Frénésie [B] : le spawn accélère pendant l'effet.
		if _effects.has("frenzy"):
			interval /= maxf(1.0, float(_find_item_def_value("frenzy", "frenzy_spawn_mult", 2.0)))
		_item_timer = maxf(0.2, interval)
		if _items.size() < maxi(1, int(_get_conf("max_items_on_field", 3))):
			_spawn_item()
	# Aimant : les items dérivent vers la tête ; collecte par distance.
	var eat_radius: float = maxf(10.0, float(_get_conf("eat_radius_px", 34.0)))
	var magnet_speed: float = float(_effect_value("magnet", 260.0)) if _effects.has("magnet") else 0.0
	for i in range(_items.size() - 1, -1, -1):
		var entry: Dictionary = _items[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_items.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		# TTL (fruit d'or géant [E]) : l'item disparaît s'il n'est pas mangé à temps.
		if entry.has("ttl"):
			entry["ttl"] = float(entry["ttl"]) - dt
			if float(entry["ttl"]) <= 0.0:
				node.queue_free()
				_items.remove_at(i)
				continue
		if magnet_speed > 0.0:
			node.position = node.position.move_toward(_head_pos, magnet_speed * dt)
		var scale_mult: float = float(entry.get("scale_mult", 1.0))
		node.scale = Vector2.ONE * scale_mult * (1.0 + 0.1 * sin(_time * TAU * 1.5 + float(entry.get("pulse", 0.0))))
		if _head_pos.distance_to(node.position) <= eat_radius * scale_mult:
			var def: Dictionary = entry.get("def", {}) as Dictionary
			var at: Vector2 = node.position
			node.queue_free()
			_items.remove_at(i)
			_eat_item(def, at)

## Rejection sampling : loin de la tête et du corps (jamais collé au serpent).
func _spawn_item() -> void:
	var def: Dictionary = _pick_item_def()
	if def.is_empty():
		return
	var min_dist: float = maxf(30.0, float(_get_conf("item_min_spawn_dist_px", 90.0)))
	var min_dist_sq: float = min_dist * min_dist
	var body_dist_sq: float = (min_dist * 0.6) * (min_dist * 0.6)
	var margin: float = 30.0
	var rect: Rect2 = _current_play_rect()
	var pos: Vector2 = rect.get_center()
	for attempt in range(14):
		var candidate := Vector2(
			randf_range(rect.position.x + margin, rect.end.x - margin),
			randf_range(rect.position.y + margin, rect.end.y - margin))
		if candidate.distance_squared_to(_head_pos) < min_dist_sq:
			continue
		var clear: bool = true
		for j in range(_segment_count):
			var seg: Node2D = _segment_pool[j]
			if is_instance_valid(seg) and candidate.distance_squared_to(seg.position) < body_dist_sq:
				clear = false
				break
		if clear:
			pos = candidate
			break
	var size_px: float = maxf(16.0, float(_get_conf("item_px", 44.0)))
	var node := Node2D.new()
	node.name = "SnakeItem"
	node.z_as_relative = false
	node.z_index = 8
	node.position = pos
	var tint := Color(str(def.get("fallback_color", "#FFD166")))
	var visual: Node2D = _build_sprite_fit(def.get("resource", null) as Resource, size_px)
	if visual == null:
		node.add_child(_build_circle(size_px * 0.5, Color(tint.r, tint.g, tint.b, 0.92)))
		var glyph := Label.new()
		glyph.text = str(def.get("fallback_glyph", "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(size_px * 0.55))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(size_px, size_px)
		glyph.position = -Vector2(size_px, size_px) * 0.5
		node.add_child(glyph)
	else:
		node.add_child(visual)
	var label_key: String = str(def.get("label_key", ""))
	if label_key != "" and _effect_labels_enabled():
		_attach_effect_label(node, _translate_or(label_key, str(def.get("id", "")).to_upper()), size_px, tint)
	add_child(node)
	node.scale = Vector2.ONE * 0.2
	var pop: Tween = node.create_tween()
	pop.tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_items.append({"node": node, "def": def, "pulse": randf() * TAU})

## Manger : score + cristaux + CROISSANCE + dégâts boss (base + bonus par
## segment) + effet temporaire éventuel.
func _eat_item(def: Dictionary, at: Vector2) -> void:
	var points: int = int(round(float(int(def.get("score", 60))) * _reward_multiplier))
	if _game and is_instance_valid(_game):
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, at)
		var crystals: int = maxi(0, int(def.get("crystals", 0)))
		if crystals > 0 and _game.has_method("spawn_reward_crystal_at"):
			for c in range(crystals):
				_game.call("spawn_reward_crystal_at",
					at + Vector2(randf_range(-24.0, 24.0), randf_range(-16.0, 16.0)),
					{"force_magnet_after_sec": maxf(0.2, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))})
	# Cœur réparateur [B] : soin direct en % des HP max.
	# Cap dur 20% : un item de soin ne rend jamais plus de 20% des HP max.
	var heal_percent: float = clampf(float(def.get("heal_percent", 0.0)), 0.0, 0.2)
	if heal_percent > 0.0 and _player and is_instance_valid(_player):
		var max_hp_v: Variant = _player.get("max_hp")
		var hp_v: Variant = _player.get("current_hp")
		if (max_hp_v is int or max_hp_v is float) and (hp_v is int or hp_v is float):
			_player.set("current_hp", mini(int(max_hp_v), int(hp_v) + maxi(1, int(ceil(float(max_hp_v) * heal_percent)))))
			if VFXManager:
				VFXManager.spawn_floating_text(at + Vector2(0.0, -60.0),
					"+%d%%" % int(round(heal_percent * 100.0)), Color("#7FE58C"), self)
	# Fruit bombe [B] : détruit les obstacles d'événements dans le rayon.
	var bomb_radius: float = maxf(0.0, float(def.get("bomb_radius_px", 0.0)))
	if bomb_radius > 0.0:
		_detonate_bomb(at, bomb_radius, maxi(0, int(def.get("bomb_score", 0))))
	# Chrono [B] : +temps en story (cap cumulé — la marge WaveManager n'est que
	# de +6 s, au-delà le hard timeout couperait la vague sans outro) ; en
	# Libre (pas de timer) : score à la place.
	var time_bonus: float = maxf(0.0, float(def.get("time_bonus_sec", 0.0)))
	if time_bonus > 0.0:
		if _is_free_mode():
			var bonus_score: int = int(round(float(int(def.get("time_bonus_score", 250))) * _reward_multiplier))
			if bonus_score > 0 and _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
				_game.call("add_wave_bonus_score", bonus_score, at)
		else:
			var cap: float = maxf(0.0, float(_get_conf("time_bonus_max_total_sec", 5.0)))
			var granted: float = minf(time_bonus, cap - _time_bonus_total)
			if granted > 0.0:
				_time_bonus_total += granted
				_duration += granted
				if VFXManager:
					VFXManager.spawn_floating_text(at + Vector2(0.0, -60.0),
						"+%ds" % int(round(granted)), Color("#9AF6FF"), self)
	_grow(maxi(0, int(def.get("grow_segments", 1))))
	var boss_damage: float = maxf(0.0, float(def.get("boss_damage_pct", 0.02))) \
		+ maxf(0.0, float(_get_conf("per_segment_boss_damage", 0.0008))) * float(_segment_count)
	# Frénésie [B] : dégâts boss amplifiés pendant l'effet.
	if _effects.has("frenzy"):
		boss_damage *= maxf(1.0, float(_find_item_def_value("frenzy", "frenzy_damage_mult", 1.5)))
	_damage_boss(boss_damage)
	var effect: String = str(def.get("effect", ""))
	if effect != "":
		_effects[effect] = maxf(1.0, float(def.get("effect_duration_sec", 6.0)))
		if VFXManager:
			VFXManager.spawn_floating_text(at + Vector2(0.0, -40.0),
				_translate_or(str(def.get("label_key", "")), effect.to_upper()),
				Color(str(def.get("fallback_color", "#FFFFFF"))), self)
	if VFXManager and _player and is_instance_valid(_player):
		VFXManager.flash_sprite(_player, Color(str(def.get("fallback_color", "#FFD166"))), 0.12)

func _grow(count: int) -> void:
	if count <= 0:
		return
	var new_count: int = mini(_segment_count + count, _segment_pool.size())
	for i in range(_segment_count, new_count):
		var node: Node2D = _segment_pool[i]
		if is_instance_valid(node):
			# Les nouveaux apparaissent sur la queue et se déploient au spacing.
			var anchor: Node2D = _segment_pool[maxi(0, _segment_count - 1)]
			node.position = anchor.position if is_instance_valid(anchor) and _segment_count > 0 else _head_pos
			node.scale = Vector2.ONE * 0.2
			var pop: Tween = node.create_tween()
			pop.tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_segment_count = new_count
	_refresh_segment_visibility()

func _tick_effects(dt: float) -> void:
	for key in _effects.keys().duplicate():
		_effects[key] = float(_effects[key]) - dt
		if float(_effects[key]) <= 0.0:
			_effects.erase(key)

# =============================================================================
# HUD BAS-DROITE : icônes des effets actifs (temps restant)
# =============================================================================

func _ensure_buff_bar() -> void:
	if _buff_bar and is_instance_valid(_buff_bar):
		return
	_buff_bar = Node2D.new()
	_buff_bar.name = "SnakeBuffBar"
	_buff_bar.z_as_relative = false
	_buff_bar.z_index = 61
	add_child(_buff_bar)

func _find_item_def_by_effect(effect_id: String) -> Dictionary:
	for def_v in _item_defs:
		if str((def_v as Dictionary).get("effect", "")) == effect_id:
			return def_v as Dictionary
	return {}

func _find_item_def_value(effect_id: String, key: String, fallback: float) -> float:
	var def: Dictionary = _find_item_def_by_effect(effect_id)
	return float(def.get(key, fallback)) if not def.is_empty() else fallback

func _build_buff_icon(def: Dictionary) -> Dictionary:
	var radius: float = maxf(14.0, float(_get_conf("buff_icon_radius_px", 28.0)))
	var tint := Color(str(def.get("fallback_color", "#FFFFFF")))
	var root := Node2D.new()
	var visual: Node2D = _build_sprite_fit(def.get("resource", null) as Resource, radius * 2.0)
	if visual == null:
		root.add_child(_build_circle(radius, Color(tint.r, tint.g, tint.b, 0.85)))
		var glyph := Label.new()
		glyph.text = str(def.get("fallback_glyph", "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(radius))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(radius, radius) * 2.0
		glyph.position = -Vector2(radius, radius)
		root.add_child(glyph)
	else:
		root.add_child(visual)
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("buff_icon_font_size", 18))))
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 5)
	badge.size = Vector2(radius * 2.0, 22.0)
	badge.position = Vector2(-radius, radius + 2.0)
	root.add_child(badge)
	_buff_bar.add_child(root)
	return {"root": root, "badge": badge}

func _update_buff_icons() -> void:
	for id in _buff_icons.keys().duplicate():
		if not _effects.has(id):
			var icon: Dictionary = _buff_icons[id]
			var root_v: Variant = icon.get("root", null)
			if root_v is Node2D and is_instance_valid(root_v):
				(root_v as Node2D).queue_free()
			_buff_icons.erase(id)
	if _effects.is_empty():
		return
	_ensure_buff_bar()
	for id in _effects:
		if not _buff_icons.has(id):
			var def: Dictionary = _find_item_def_by_effect(str(id))
			if def.is_empty():
				continue
			_buff_icons[id] = _build_buff_icon(def)
	var viewport_size: Vector2 = get_viewport_rect().size
	var gap: float = maxf(36.0, float(_get_conf("buff_icon_gap_px", 66.0)))
	var margin: float = maxf(8.0, float(_get_conf("buff_icon_margin_px", 16.0)))
	var bottom_off: float = maxf(24.0, float(_get_conf("buff_icon_bottom_offset_px", 46.0)))
	var radius: float = maxf(14.0, float(_get_conf("buff_icon_radius_px", 28.0)))
	var slot: int = 0
	for id in _effects:
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
			(badge_v as Label).text = str(int(ceil(float(_effects[id]))))
		slot += 1

# =============================================================================
# ÉVÉNEMENTS [E] (13 juillet 2026) — scheduler anti-répétition, UN SEUL actif,
# toasts centraux, obstacles/zones télégraphiés pour casser la monotonie.
# =============================================================================

## Dégâts « environnement » sur la tête : mêmes règles que la morsure (jamais
## létal en story, invuln partagée _bite_invuln) mais SANS coupe de queue.
func _hurt_head(pct: float) -> void:
	if _bite_invuln > 0.0 or _player == null or not is_instance_valid(_player):
		return
	_bite_invuln = maxf(0.2, float(_get_conf("bite_invuln_sec", 1.2)))
	_apply_percent_damage(pct)
	if _player and is_instance_valid(_player) and VFXManager:
		VFXManager.flash_sprite(_player, Color(1.0, 0.35, 0.3), 0.25)
		VFXManager.screen_shake(5.0, 0.2)

func _apply_percent_damage(pct: float) -> void:
	if not _player.has_method("take_damage"):
		return
	var max_hp_v: Variant = _player.get("max_hp")
	var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
	var dmg: int = maxi(1, int(ceil(float(max_hp) * clampf(pct, 0.0, 1.0))))
	if bool(_get_conf("bite_never_lethal", true)):
		var hp_v: Variant = _player.get("current_hp")
		var current_hp: int = int(hp_v) if (hp_v is int or hp_v is float) else max_hp
		dmg = mini(dmg, maxi(0, current_hp - 1))
	if dmg > 0:
		_player.call("take_damage", dmg)

func _tick_event_scheduler(dt: float) -> void:
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(
		maxf(5.0, float(_get_conf("event_interval_sec_min", 18.0))),
		maxf(5.0, float(_get_conf("event_interval_sec_max", 28.0))))
	if _event_active != "":
		return
	# Story : pas d'événement dans les dernières secondes (fuite du boss imminente).
	if not _is_free_mode() and _elapsed > _duration - 8.0:
		return
	var weights: Dictionary = {
		"asteroids": float(_get_conf("asteroid_weight", 20.0)),
		"walls": float(_get_conf("wall_weight", 15.0)),
		"zones": float(_get_conf("zone_weight", 15.0)),
		"meteors": float(_get_conf("meteor_weight", 15.0)),
		"sweep": float(_get_conf("sweep_weight", 10.0)),
		"shrink": float(_get_conf("shrink_weight", 10.0)),
		"wind": float(_get_conf("wind_weight", 10.0)),
		"pests": float(_get_conf("pest_weight", 12.0)),
		"golden_giant": float(_get_conf("golden_giant_weight", 12.0))
	}
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
	var rect: Rect2 = _current_play_rect()
	match event_id:
		"asteroids":
			_toast("snake_evt_asteroids", "ASTEROIDS!", "#FF8A5C")
			var count: int = randi_range(
				maxi(1, int(_get_conf("asteroid_count_min", 3))),
				maxi(1, int(_get_conf("asteroid_count_max", 5))))
			for i in range(count):
				_spawn_asteroid(rect)
			_event = {"timer": maxf(3.0, float(_get_conf("asteroid_duration_sec", 14.0)))}
		"walls":
			_toast("snake_evt_walls", "WALLS!", "#FF5A5A")
			for i in range(maxi(1, int(_get_conf("wall_count", 2)))):
				_spawn_wall(rect)
			_event = {
				"phase": "telegraph",
				"timer": maxf(0.3, float(_get_conf("wall_telegraph_sec", 1.2))),
				"hold": maxf(2.0, float(_get_conf("wall_duration_sec", 12.0)))
			}
		"zones":
			_toast("snake_evt_zones", "ELECTRIC ZONES!", "#5CE8FF")
			for i in range(maxi(1, int(_get_conf("zone_count", 2)))):
				_spawn_zone(rect)
			_event = {"timer": maxf(2.0, float(_get_conf("zone_duration_sec", 10.0)))}
		"meteors":
			_toast("snake_evt_meteors", "METEOR RAIN!", "#FF8A5C")
			_event = {
				"remaining": maxi(1, int(_get_conf("meteor_count", 6))),
				"drop_timer": 0.0
			}
		"sweep":
			_toast("snake_evt_sweep", "BOSS SWEEP!", "#B455E8")
			_start_sweep(rect)
		"shrink":
			_toast("snake_evt_shrink", "ARENA SHRUNK!", "#FF5A5A")
			var target: float = minf(_play_rect.size.x, _play_rect.size.y) \
				* (1.0 - clampf(float(_get_conf("shrink_ratio", 0.8)), 0.4, 1.0)) * 0.5
			_event = {
				"phase": "close",
				"target": target,
				"timer": maxf(0.2, float(_get_conf("shrink_anim_sec", 1.0))),
				"hold": maxf(2.0, float(_get_conf("shrink_duration_sec", 10.0)))
			}
		"wind":
			_toast("snake_evt_wind", "SOLAR WIND!", "#9AD8FF")
			var dirs: Array = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
			var dir: Vector2 = dirs[randi() % dirs.size()]
			_ensure_wind_fx()
			_wind_fx.ensure_visuals(rect)
			_wind_fx.update_arrow(true, dir, _time)
			_event = {
				"phase": "telegraph",
				"dir": dir,
				"timer": maxf(0.2, float(_get_conf("wind_telegraph_sec", 1.0))),
				"hold": maxf(2.0, float(_get_conf("wind_duration_sec", 8.0)))
			}
		"pests":
			_toast("snake_evt_pests", "PESTS!", "#C77DFF")
			for i in range(maxi(1, int(_get_conf("pest_count", 3)))):
				_spawn_pest(rect)
			_event = {"timer": maxf(3.0, float(_get_conf("pest_duration_sec", 12.0)))}
		"golden_giant":
			_toast("snake_evt_golden_giant", "GIANT GOLDEN FRUIT!", "#FFD866")
			_spawn_golden_giant(rect)

## Purge les obstacles/marqueurs de l'événement courant et restaure l'arène.
func _end_event() -> void:
	for entry in _asteroids + _walls + _zones + _pests + _meteor_marks:
		var node_v: Variant = (entry as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_asteroids.clear()
	_walls.clear()
	_zones.clear()
	_pests.clear()
	_meteor_marks.clear()
	for key in ["warn", "core", "glow"]:
		var line_v: Variant = _event.get(key, null)
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).queue_free()
	if _wind_fx != null and _wind_fx.is_active():
		_wind_fx.clear()
	if _arena_inset > 0.0:
		_arena_inset = 0.0
		_update_border_points()
	_event_active = ""
	_event = {}

func _tick_active_event(dt: float) -> void:
	if _event_active == "" or _state == State.DONE:
		return
	match _event_active:
		"asteroids", "zones", "pests":
			_event["timer"] = float(_event.get("timer", 0.0)) - dt
			if float(_event["timer"]) <= 0.0 or (_event_active == "pests" and _pests.is_empty()):
				_end_event()
		"walls":
			_tick_walls_event(dt)
		"meteors":
			_tick_meteors_event(dt)
		"sweep":
			_tick_sweep_event(dt)
		"shrink":
			_tick_shrink_event(dt)
		"wind":
			_tick_wind_event(dt)
		"golden_giant":
			# Fini quand le méga-fruit est mangé ou expiré (TTL côté _tick_items).
			var node_v: Variant = _event.get("node", null)
			if not (node_v is Node2D) or not is_instance_valid(node_v):
				_end_event()

# --- Astéroïdes [E7] ---------------------------------------------------------

func _spawn_asteroid(rect: Rect2) -> void:
	var size_px: float = maxf(24.0, float(_get_conf("asteroid_size_px", 64.0)))
	var node := Node2D.new()
	node.name = "SnakeAsteroid"
	node.z_as_relative = false
	node.z_index = 8
	var res: Resource = null
	if not _asteroid_resources.is_empty():
		res = _asteroid_resources[randi() % _asteroid_resources.size()] as Resource
	var visual: Node2D = _build_sprite_fit(res, size_px)
	if visual == null:
		visual = _build_circle(size_px * 0.5, Color("#8A93A6"))
	node.add_child(visual)
	# Spawn loin de la tête (jamais sur le joueur).
	var pos: Vector2 = rect.get_center()
	for attempt in range(10):
		var candidate := Vector2(
			randf_range(rect.position.x + 40.0, rect.end.x - 40.0),
			randf_range(rect.position.y + 40.0, rect.end.y - 40.0))
		if candidate.distance_to(_head_pos) > 220.0:
			pos = candidate
			break
	node.position = pos
	node.modulate.a = 0.0 # fade-in télégraphié (inoffensif tant que transparent)
	add_child(node)
	var speed: float = maxf(10.0, float(_get_conf("asteroid_drift_px_sec", 55.0)))
	_asteroids.append({
		"node": node,
		"vel": Vector2.from_angle(randf() * TAU) * speed,
		"age": 0.0,
		"size": size_px
	})

# --- Murs temporaires [E8] ---------------------------------------------------

## Mur H ou V laissant TOUJOURS un couloir de chaque côté (jamais bord à bord).
func _spawn_wall(rect: Rect2) -> void:
	var thickness: float = maxf(6.0, float(_get_conf("wall_thickness_px", 16.0)))
	var length_ratio: float = clampf(float(_get_conf("wall_length_ratio", 0.55)), 0.2, 0.8)
	var horizontal: bool = randf() < 0.5
	var wall_rect: Rect2
	if horizontal:
		var wall_len: float = rect.size.x * length_ratio
		var x: float = randf_range(rect.position.x + 60.0, rect.end.x - 60.0 - wall_len)
		var y: float = randf_range(rect.position.y + rect.size.y * 0.2, rect.end.y - rect.size.y * 0.2)
		wall_rect = Rect2(Vector2(x, y - thickness * 0.5), Vector2(wall_len, thickness))
	else:
		var wall_len2: float = rect.size.y * length_ratio
		var x2: float = randf_range(rect.position.x + rect.size.x * 0.2, rect.end.x - rect.size.x * 0.2)
		var y2: float = randf_range(rect.position.y + 60.0, rect.end.y - 60.0 - wall_len2)
		wall_rect = Rect2(Vector2(x2 - thickness * 0.5, y2), Vector2(thickness, wall_len2))
	var node := Polygon2D.new()
	node.name = "SnakeWall"
	node.z_as_relative = false
	node.z_index = 8
	node.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(wall_rect.size.x, 0.0), wall_rect.size, Vector2(0.0, wall_rect.size.y)])
	node.position = wall_rect.position
	node.color = Color(str(_get_conf("wall_color", "#FF5A5AC8")))
	node.modulate.a = 0.35 # télégraphe semi-transparent (inoffensif)
	add_child(node)
	_walls.append({"node": node, "rect": wall_rect})

func _tick_walls_event(dt: float) -> void:
	_event["timer"] = float(_event.get("timer", 0.0)) - dt
	if str(_event.get("phase", "")) == "telegraph":
		for wall in _walls:
			var node_v: Variant = (wall as Dictionary).get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).modulate.a = 0.25 + 0.2 * sin(_time * TAU * 3.0)
		if float(_event["timer"]) <= 0.0:
			_event["phase"] = "solid"
			_event["timer"] = float(_event.get("hold", 12.0))
			for wall in _walls:
				var node2_v: Variant = (wall as Dictionary).get("node", null)
				if node2_v is Node2D and is_instance_valid(node2_v):
					(node2_v as Node2D).modulate.a = 1.0
		return
	if float(_event["timer"]) <= 0.0:
		_end_event()

# --- Zones électrifiées [E9] -------------------------------------------------

func _spawn_zone(rect: Rect2) -> void:
	var radius: float = maxf(50.0, float(_get_conf("zone_radius_px", 140.0)))
	var node := Node2D.new()
	node.name = "SnakeElectricZone"
	node.z_as_relative = false
	node.z_index = 6
	var asset_visual: Node2D = _build_sprite_fit(
		_load_cached_resource(str(_get_conf("zone_asset", ""))), radius * 2.0)
	if asset_visual != null:
		node.add_child(asset_visual)
	else:
		node.add_child(_build_circle(radius, Color("#5CE8FF22"), 24))
		var ring := Line2D.new()
		ring.closed = true
		ring.width = 4.0
		ring.default_color = Color("#5CE8FFAA")
		var pts := PackedVector2Array()
		for k in range(24):
			var a: float = TAU * float(k) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		ring.points = pts
		node.add_child(ring)
	var pos: Vector2 = rect.get_center()
	for attempt in range(10):
		var candidate := Vector2(
			randf_range(rect.position.x + radius, rect.end.x - radius),
			randf_range(rect.position.y + radius, rect.end.y - radius))
		if candidate.distance_to(_head_pos) > radius + 120.0:
			pos = candidate
			break
	node.position = pos
	add_child(node)
	_zones.append({"node": node, "pos": pos, "radius": radius, "tick_timer": 0.0})

# --- Pluie de météores [E10] --------------------------------------------------

func _tick_meteors_event(dt: float) -> void:
	var remaining: int = int(_event.get("remaining", 0))
	if remaining > 0:
		_event["drop_timer"] = float(_event.get("drop_timer", 0.0)) - dt
		if float(_event["drop_timer"]) <= 0.0:
			_event["drop_timer"] = maxf(0.5, float(_get_conf("meteor_spread_sec", 3.0))) \
				/ maxf(1.0, float(_get_conf("meteor_count", 6)))
			_event["remaining"] = remaining - 1
			_spawn_meteor_mark(_current_play_rect())
	elif _meteor_marks.is_empty():
		_end_event()

func _spawn_meteor_mark(rect: Rect2) -> void:
	var radius: float = maxf(30.0, float(_get_conf("meteor_radius_px", 90.0)))
	var node := Node2D.new()
	node.name = "SnakeMeteorMark"
	node.z_as_relative = false
	node.z_index = 6
	node.add_child(_build_circle(radius, Color("#FF5A5A22"), 20))
	var ring := Line2D.new()
	ring.closed = true
	ring.width = 4.0
	ring.default_color = Color("#FF5A5AC8")
	var pts := PackedVector2Array()
	for k in range(20):
		var a: float = TAU * float(k) / 20.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	node.add_child(ring)
	node.position = Vector2(
		randf_range(rect.position.x + radius, rect.end.x - radius),
		randf_range(rect.position.y + radius, rect.end.y - radius))
	add_child(node)
	_meteor_marks.append({
		"node": node,
		"pos": node.position,
		"radius": radius,
		"timer": maxf(0.4, float(_get_conf("meteor_telegraph_sec", 1.5)))
	})

# --- Balayage du boss [E11] ---------------------------------------------------

## Beam vertical qui balaye horizontalement l'arène (part du côté opposé à la
## tête) — pipeline Line2D core+glow des quasars star_drift.
func _start_sweep(rect: Rect2) -> void:
	var from_left: bool = _head_pos.x > rect.get_center().x
	var start_x: float = rect.position.x + 20.0 if from_left else rect.end.x - 20.0
	var end_x: float = rect.end.x - 20.0 if from_left else rect.position.x + 20.0
	var width: float = maxf(20.0, float(_get_conf("sweep_width_px", 70.0)))
	var pts := PackedVector2Array([Vector2(start_x, rect.position.y), Vector2(start_x, rect.end.y)])
	var warn := Line2D.new()
	warn.width = 4.0
	warn.default_color = Color(str(_get_conf("sweep_warn_color", "#FF5A5A96")))
	warn.points = pts
	warn.z_as_relative = false
	warn.z_index = 8
	add_child(warn)
	var glow := Line2D.new()
	glow.width = width
	glow.default_color = Color(str(_get_conf("sweep_glow_color", "#B455E8A0")))
	glow.material = _add_material
	glow.points = pts
	glow.visible = false
	glow.z_as_relative = false
	glow.z_index = 8
	add_child(glow)
	var core := Line2D.new()
	core.width = width * 0.35
	core.default_color = Color(str(_get_conf("sweep_core_color", "#FFF3C7")))
	core.points = pts
	core.visible = false
	core.z_as_relative = false
	core.z_index = 9
	add_child(core)
	_event = {
		"phase": "telegraph",
		"timer": maxf(0.3, float(_get_conf("sweep_telegraph_sec", 1.2))),
		"x": start_x,
		"start_x": start_x,
		"end_x": end_x,
		"warn": warn,
		"glow": glow,
		"core": core
	}

func _tick_sweep_event(dt: float) -> void:
	var rect: Rect2 = _current_play_rect()
	_event["timer"] = float(_event.get("timer", 0.0)) - dt
	var warn: Line2D = _event.get("warn") as Line2D
	var glow: Line2D = _event.get("glow") as Line2D
	var core: Line2D = _event.get("core") as Line2D
	if str(_event.get("phase", "")) == "telegraph":
		if warn and is_instance_valid(warn):
			warn.modulate.a = 0.55 + 0.45 * sin(_time * TAU * 3.0)
		if float(_event["timer"]) <= 0.0:
			_event["phase"] = "active"
			_event["timer"] = maxf(0.5, float(_get_conf("sweep_duration_sec", 3.0)))
			_event["total"] = float(_event["timer"])
			if warn and is_instance_valid(warn):
				warn.visible = false
			if glow and is_instance_valid(glow):
				glow.visible = true
			if core and is_instance_valid(core):
				core.visible = true
		return
	# Balayage actif : x lerpé du départ à l'arrivée.
	var t: float = 1.0 - clampf(float(_event["timer"]) / maxf(0.1, float(_event.get("total", 3.0))), 0.0, 1.0)
	var x: float = lerpf(float(_event.get("start_x", 0.0)), float(_event.get("end_x", 0.0)), t)
	_event["x"] = x
	var pts := PackedVector2Array([Vector2(x, rect.position.y), Vector2(x, rect.end.y)])
	if glow and is_instance_valid(glow):
		glow.points = pts
	if core and is_instance_valid(core):
		core.points = pts
	if absf(_head_pos.x - x) <= maxf(20.0, float(_get_conf("sweep_width_px", 70.0))) * 0.5 \
		and _head_pos.y >= rect.position.y and _head_pos.y <= rect.end.y:
		_hurt_head(clampf(float(_get_conf("sweep_damage_percent", 0.08)), 0.0, 1.0))
	if float(_event["timer"]) <= 0.0:
		_end_event()

# --- Rétrécissement d'arène [E12] ----------------------------------------------

func _tick_shrink_event(dt: float) -> void:
	var anim_sec: float = maxf(0.2, float(_get_conf("shrink_anim_sec", 1.0)))
	var target: float = float(_event.get("target", 0.0))
	_event["timer"] = float(_event.get("timer", 0.0)) - dt
	match str(_event.get("phase", "")):
		"close":
			_arena_inset = minf(target, _arena_inset + target * dt / anim_sec)
			_update_border_points()
			if _border_line and is_instance_valid(_border_line):
				_border_line.modulate = Color(1.0, 0.5, 0.5)
			if float(_event["timer"]) <= 0.0:
				_event["phase"] = "hold"
				_event["timer"] = float(_event.get("hold", 10.0))
		"hold":
			if _border_line and is_instance_valid(_border_line):
				_border_line.modulate.a = 0.75 + 0.25 * sin(_time * TAU * 1.5)
			if float(_event["timer"]) <= 0.0:
				_event["phase"] = "open"
				_event["timer"] = anim_sec
		"open":
			_arena_inset = maxf(0.0, _arena_inset - target * dt / anim_sec)
			_update_border_points()
			if float(_event["timer"]) <= 0.0:
				if _border_line and is_instance_valid(_border_line):
					_border_line.modulate = Color.WHITE
				_end_event()

# --- Vent solaire [E13] ---------------------------------------------------------

var _wind_fx: WindFX = null

func _ensure_wind_fx() -> void:
	if _wind_fx == null:
		_wind_fx = WindFX.new(self, {
			"streak_count": int(_get_conf("wind_streak_count", 14)),
			"streak_color": str(_get_conf("wind_streak_color", "#9AD8FF66")),
			"debris_count": int(_get_conf("wind_debris_count", 6)),
			"debris_color": str(_get_conf("wind_debris_color", "#C8E8FFAA")),
		})

func _tick_wind_event(dt: float) -> void:
	_event["timer"] = float(_event.get("timer", 0.0)) - dt
	var dir: Vector2 = _event.get("dir", Vector2.RIGHT)
	var telegraphing: bool = str(_event.get("phase", "")) == "telegraph"
	if _wind_fx != null:
		# Flèche seulement pendant le telegraph ; les traits filants montrent
		# le vent (créés dès le début, wrap dans l'arène).
		_wind_fx.update_arrow(telegraphing, dir, _time)
		_wind_fx.animate(dt, dir)
	if telegraphing and float(_event["timer"]) <= 0.0:
		_event["phase"] = "blow"
		_event["timer"] = float(_event.get("hold", 8.0))
		return
	if str(_event.get("phase", "")) == "blow" and float(_event["timer"]) <= 0.0:
		_end_event()

# --- Vermine [E14] ---------------------------------------------------------------

func _spawn_pest(rect: Rect2) -> void:
	var size_px: float = maxf(20.0, float(_get_conf("pest_size_px", 44.0)))
	var node := Node2D.new()
	node.name = "SnakePest"
	node.z_as_relative = false
	node.z_index = 9
	var visual: Node2D = _build_sprite_fit(
		_load_cached_resource(str(_get_conf("pest_asset", ""))), size_px)
	if visual == null:
		var tri := Polygon2D.new()
		tri.polygon = PackedVector2Array([
			Vector2(0.0, -size_px * 0.5),
			Vector2(size_px * 0.45, size_px * 0.4),
			Vector2(-size_px * 0.45, size_px * 0.4)])
		tri.color = Color("#C77DFF")
		visual = tri
	node.add_child(visual)
	# Entre par un bord (loin de la tête).
	var from_left: bool = _head_pos.x > rect.get_center().x
	node.position = Vector2(
		rect.position.x + 20.0 if from_left else rect.end.x - 20.0,
		randf_range(rect.position.y + 40.0, rect.end.y - 40.0))
	add_child(node)
	_pests.append({"node": node, "size": size_px})

# --- Fruit d'or géant [E15] -------------------------------------------------------

## Méga-fruit à TTL injecté dans le pipeline items (déf synthétique dérivée de
## food_golden) — le manger = grosse croissance + gros dégâts boss.
func _spawn_golden_giant(rect: Rect2) -> void:
	var base_def: Dictionary = {}
	for def_v in _item_defs:
		if str((def_v as Dictionary).get("id", "")) == "food_golden":
			base_def = (def_v as Dictionary).duplicate(true)
			break
	if base_def.is_empty() and not _item_defs.is_empty():
		base_def = (_item_defs[0] as Dictionary).duplicate(true)
	var damage_mult: float = maxf(1.0, float(_get_conf("golden_giant_damage_mult", 4.0)))
	base_def["id"] = "golden_giant"
	base_def["grow_segments"] = maxi(1, int(_get_conf("golden_giant_grow", 4)))
	base_def["boss_damage_pct"] = float(base_def.get("boss_damage_pct", 0.055)) * damage_mult
	base_def["score"] = maxi(0, int(_get_conf("golden_giant_score", 400)))
	base_def.erase("effect")
	# Coin d'arène aléatoire (rush volontaire).
	var size_mult: float = maxf(1.2, float(_get_conf("golden_giant_size_mult", 2.0)))
	var size_px: float = maxf(16.0, float(_get_conf("item_px", 44.0))) * size_mult
	var corner := Vector2(
		rect.position.x + size_px if randf() < 0.5 else rect.end.x - size_px,
		rect.position.y + size_px if randf() < 0.5 else rect.end.y - size_px)
	var node := Node2D.new()
	node.name = "SnakeGoldenGiant"
	node.z_as_relative = false
	node.z_index = 8
	var visual: Node2D = _build_sprite_fit(base_def.get("resource", null) as Resource, size_px)
	if visual == null:
		node.add_child(_build_circle(size_px * 0.5, Color("#FFB300E6")))
	else:
		node.add_child(visual)
	node.position = corner
	add_child(node)
	_items.append({
		"node": node,
		"def": base_def,
		"pulse": randf() * TAU,
		"scale_mult": 1.0,
		"ttl": maxf(2.0, float(_get_conf("golden_giant_duration_sec", 6.0)))
	})
	_event = {"node": node}

# --- Updates des obstacles (contacts par distance, une passe par frame) ----------

func _tick_obstacles(dt: float) -> void:
	if _state == State.DONE:
		return
	var rect: Rect2 = _current_play_rect()
	# Astéroïdes : fade-in télégraphié, dérive + wrap, contact tête.
	for i in range(_asteroids.size() - 1, -1, -1):
		var entry: Dictionary = _asteroids[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_asteroids.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		entry["age"] = float(entry.get("age", 0.0)) + dt
		node.modulate.a = clampf(float(entry["age"]) / 0.8, 0.0, 1.0)
		node.position += (entry.get("vel", Vector2.ZERO) as Vector2) * dt
		if node.position.x < rect.position.x: node.position.x = rect.end.x
		elif node.position.x > rect.end.x: node.position.x = rect.position.x
		if node.position.y < rect.position.y: node.position.y = rect.end.y
		elif node.position.y > rect.end.y: node.position.y = rect.position.y
		if float(entry["age"]) > 0.8 and _bite_invuln <= 0.0 \
			and _head_pos.distance_to(node.position) <= float(entry.get("size", 64.0)) * 0.45 + 14.0:
			_hurt_head(clampf(float(_get_conf("asteroid_damage_percent", 0.06)), 0.0, 1.0))
			entry["vel"] = (node.position - _head_pos).normalized() \
				* maxf(10.0, float(_get_conf("asteroid_drift_px_sec", 55.0)))
	# Murs solides : distance point-rectangle.
	if _event_active == "walls" and str(_event.get("phase", "")) == "solid" and _bite_invuln <= 0.0:
		for wall in _walls:
			var wall_rect: Rect2 = (wall as Dictionary).get("rect", Rect2())
			var closest := Vector2(
				clampf(_head_pos.x, wall_rect.position.x, wall_rect.end.x),
				clampf(_head_pos.y, wall_rect.position.y, wall_rect.end.y))
			if _head_pos.distance_to(closest) <= 14.0:
				_hurt_head(clampf(float(_get_conf("wall_damage_percent", 0.06)), 0.0, 1.0))
				break
	# Zones électrifiées : ticks sur la TÊTE seule (pas d'invuln — pression continue).
	var tick_interval: float = maxf(0.2, float(_get_conf("zone_tick_interval_sec", 0.5)))
	for zone in _zones:
		var znode_v: Variant = (zone as Dictionary).get("node", null)
		if znode_v is Node2D and is_instance_valid(znode_v):
			(znode_v as Node2D).modulate.a = 0.7 + 0.3 * sin(_time * TAU * 1.2)
		if _head_pos.distance_to((zone as Dictionary).get("pos", Vector2.ZERO)) \
			> float((zone as Dictionary).get("radius", 140.0)):
			zone["tick_timer"] = 0.0
			continue
		zone["tick_timer"] = float((zone as Dictionary).get("tick_timer", 0.0)) - dt
		if float(zone["tick_timer"]) > 0.0:
			continue
		zone["tick_timer"] = tick_interval
		_apply_percent_damage(clampf(float(_get_conf("zone_tick_damage_percent", 0.03)), 0.0, 1.0))
		if VFXManager and _player and is_instance_valid(_player):
			VFXManager.flash_sprite(_player, Color(0.5, 0.9, 1.0), 0.12)
	# Télégraphes de météores : pulse puis IMPACT.
	for i in range(_meteor_marks.size() - 1, -1, -1):
		var mark: Dictionary = _meteor_marks[i]
		var mnode_v: Variant = mark.get("node", null)
		if not (mnode_v is Node2D) or not is_instance_valid(mnode_v):
			_meteor_marks.remove_at(i)
			continue
		var mnode: Node2D = mnode_v as Node2D
		mark["timer"] = float(mark.get("timer", 0.0)) - dt
		mnode.modulate.a = 0.5 + 0.5 * sin(_time * TAU * 3.5)
		if float(mark["timer"]) > 0.0:
			continue
		var pos: Vector2 = mark.get("pos", Vector2.ZERO)
		var radius: float = float(mark.get("radius", 90.0))
		if VFXManager:
			VFXManager.spawn_explosion(pos, radius * 1.1, Color(1.0, 0.55, 0.3), self,
				"", "res://assets/vfx/boss_explosion.tres", -1.0, 0.25, 0.45, false)
			VFXManager.screen_shake(4.0, 0.2)
		if _head_pos.distance_to(pos) <= radius:
			_hurt_head(clampf(float(_get_conf("meteor_damage_percent", 0.07)), 0.0, 1.0))
		mnode.queue_free()
		_meteor_marks.remove_at(i)
	# Vermine : fonce sur l'item le plus proche et le mange ; la tête l'écrase.
	var pest_speed: float = maxf(20.0, float(_get_conf("pest_speed_px_sec", 150.0)))
	for i in range(_pests.size() - 1, -1, -1):
		var pest: Dictionary = _pests[i]
		var pnode_v: Variant = pest.get("node", null)
		if not (pnode_v is Node2D) or not is_instance_valid(pnode_v):
			_pests.remove_at(i)
			continue
		var pnode: Node2D = pnode_v as Node2D
		var target: Node2D = null
		var best: float = INF
		for item_v in _items:
			var inode_v: Variant = (item_v as Dictionary).get("node", null)
			if inode_v is Node2D and is_instance_valid(inode_v):
				var d: float = pnode.position.distance_squared_to((inode_v as Node2D).position)
				if d < best:
					best = d
					target = inode_v as Node2D
		if target != null:
			pnode.position = pnode.position.move_toward(target.position, pest_speed * dt)
			pnode.rotation = (target.position - pnode.position).angle() + PI * 0.5
			if pnode.position.distance_to(target.position) <= 24.0:
				for j in range(_items.size() - 1, -1, -1):
					if (_items[j] as Dictionary).get("node", null) == target:
						target.queue_free()
						_items.remove_at(j)
						break
		# La tête écrase la vermine (+score).
		if _head_pos.distance_to(pnode.position) <= float(pest.get("size", 44.0)) * 0.5 + 14.0:
			if _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
				_game.call("add_wave_bonus_score",
					int(round(float(int(_get_conf("pest_score", 80))) * _reward_multiplier)), pnode.position)
			if VFXManager:
				VFXManager.spawn_impact(pnode.position, 18.0, self)
			pnode.queue_free()
			_pests.remove_at(i)

## Fruit bombe [B] : détruit astéroïdes/murs/vermines + annule les télégraphes
## de météores dans le rayon (VFX plafonnés).
func _detonate_bomb(at: Vector2, radius: float, bonus_score: int) -> void:
	var destroyed: int = 0
	var radius_sq: float = radius * radius
	for i in range(_asteroids.size() - 1, -1, -1):
		var node_v: Variant = (_asteroids[i] as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v) \
			and at.distance_squared_to((node_v as Node2D).position) <= radius_sq:
			if destroyed < 4 and VFXManager:
				VFXManager.spawn_impact((node_v as Node2D).position, 20.0, self)
			(node_v as Node2D).queue_free()
			_asteroids.remove_at(i)
			destroyed += 1
	for i in range(_walls.size() - 1, -1, -1):
		var wall_rect: Rect2 = (_walls[i] as Dictionary).get("rect", Rect2())
		if at.distance_squared_to(wall_rect.get_center()) <= radius_sq:
			var wnode_v: Variant = (_walls[i] as Dictionary).get("node", null)
			if wnode_v is Node2D and is_instance_valid(wnode_v):
				(wnode_v as Node2D).queue_free()
			_walls.remove_at(i)
			destroyed += 1
	for i in range(_pests.size() - 1, -1, -1):
		var pnode_v: Variant = (_pests[i] as Dictionary).get("node", null)
		if pnode_v is Node2D and is_instance_valid(pnode_v) \
			and at.distance_squared_to((pnode_v as Node2D).position) <= radius_sq:
			(pnode_v as Node2D).queue_free()
			_pests.remove_at(i)
			destroyed += 1
	for i in range(_meteor_marks.size() - 1, -1, -1):
		var mnode_v: Variant = (_meteor_marks[i] as Dictionary).get("node", null)
		if mnode_v is Node2D and is_instance_valid(mnode_v) \
			and at.distance_squared_to((mnode_v as Node2D).position) <= radius_sq:
			(mnode_v as Node2D).queue_free()
			_meteor_marks.remove_at(i)
			destroyed += 1
	if VFXManager:
		VFXManager.spawn_explosion(at, radius * 0.6, Color(1.0, 0.6, 0.3), self,
			"", "res://assets/vfx/boss_explosion.tres", -1.0, 0.3, 0.5, false)
		VFXManager.screen_shake(5.0, 0.25)
	if destroyed > 0 and bonus_score > 0 and _game and is_instance_valid(_game) \
		and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score",
			int(round(float(bonus_score * destroyed) * _reward_multiplier)), at)

# =============================================================================
# BOSS (modèle Match3Manager : pick aléatoire, barre HUD, dégâts %, fuite)
# =============================================================================

func _spawn_boss() -> void:
	_boss_defs = []
	var defs_v: Variant = _get_conf("bosses", [])
	if defs_v is Array:
		for def_v in (defs_v as Array):
			if def_v is Dictionary:
				_boss_defs.append(def_v)
	if _boss_defs.is_empty():
		return
	var forced_id: String = str(_get_conf("boss_id", ""))
	_boss_def = _boss_defs[randi() % _boss_defs.size()]
	if forced_id != "":
		for def_v in _boss_defs:
			if str((def_v as Dictionary).get("id", "")) == forced_id:
				_boss_def = def_v
				break
	_boss_health = 1.0
	_boss_respawn_timer = 0.0
	var viewport_size: Vector2 = get_viewport_rect().size
	var area_h: float = viewport_size.y * clampf(float(_get_conf("boss_area_height_ratio", 0.3)), 0.1, 0.5)
	_boss_center = Vector2(viewport_size.x * 0.5, area_h * 0.55)
	_build_boss_node()
	if _hud and is_instance_valid(_hud) and _hud.has_method("show_boss_health"):
		_hud.call("show_boss_health", _boss_display_name(), 1000)
		_hud.call("update_boss_health", 1000, 1000)

func _boss_display_name() -> String:
	return _translate_or(str(_boss_def.get("name_key", "")), str(_boss_def.get("id", "Boss")))

## AnimatedSprite2D depuis asset_anim (.tres SpriteFrames des boss du jeu),
## fallback hexagone ; arrivée en tween depuis le haut de l'écran.
func _build_boss_node() -> void:
	if _boss_node and is_instance_valid(_boss_node):
		_boss_node.queue_free()
	_boss_node = Node2D.new()
	_boss_node.name = "SnakeBoss"
	_boss_node.z_as_relative = false
	_boss_node.z_index = 9
	var fit_px: float = maxf(80.0, float(_get_conf("boss_fit_px", 210.0)))
	_boss_visual_size = Vector2(fit_px, fit_px)
	var frames_res: Resource = _load_cached_resource(str(_boss_def.get("asset_anim", "")))
	var built: bool = false
	if frames_res is SpriteFrames:
		var frames: SpriteFrames = frames_res as SpriteFrames
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		var anim_name: StringName = &"default"
		if not frames.has_animation(anim_name):
			var names: PackedStringArray = frames.get_animation_names()
			if names.size() > 0:
				anim_name = StringName(names[0])
		if frames.has_animation(anim_name):
			anim.play(anim_name)
			if frames.get_frame_count(anim_name) > 0:
				var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
				if frame_tex:
					var f_size: Vector2 = frame_tex.get_size()
					if f_size.x > 0.0 and f_size.y > 0.0:
						var s: float = fit_px / maxf(f_size.x, f_size.y)
						anim.scale = Vector2.ONE * s
						_boss_visual_size = f_size * s
		_boss_node.add_child(anim)
		_boss_sprite = anim
		built = true
	if not built:
		var hex := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 - PI * 0.5
			pts.append(Vector2(cos(a), sin(a)) * fit_px * 0.5)
		hex.polygon = pts
		hex.color = Color("#B455E8")
		_boss_node.add_child(hex)
		_boss_sprite = hex
	_boss_node.position = Vector2(_boss_center.x, -_boss_visual_size.y)
	add_child(_boss_node)
	var arrival: Tween = _boss_node.create_tween()
	arrival.tween_property(_boss_node, "position", _boss_center,
		maxf(0.2, float(_get_conf("boss_arrival_sec", 0.9)))) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## pct = dégâts bruts (avant boss_toughness_mult, croissant en Libre).
func _damage_boss(pct: float) -> void:
	if _boss_node == null or not is_instance_valid(_boss_node) or _boss_health <= 0.0 or pct <= 0.0:
		return
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	var toughness: float = maxf(0.1, float(_get_conf("boss_toughness_mult", 1.0)))
	var applied: float = pct / toughness
	_boss_health = clampf(_boss_health - applied, 0.0, 1.0)
	if _hud and is_instance_valid(_hud) and _hud.has_method("update_boss_health"):
		_hud.call("update_boss_health", int(round(_boss_health * 1000.0)), 1000)
	if VFXManager and _boss_sprite and is_instance_valid(_boss_sprite):
		VFXManager.flash_sprite(_boss_node, Color(1.0, 0.7, 0.7), 0.1)
		if applied >= 0.03:
			VFXManager.spawn_floating_text(_boss_node.position + Vector2(0.0, -_boss_visual_size.y * 0.4),
				"-%d%%" % int(round(applied * 100.0)), Color("#FF8A5C"), self)
	if _boss_health <= 0.0:
		_on_boss_killed()

func _on_boss_killed() -> void:
	_grant_boss_kill_rewards()
	if VFXManager:
		VFXManager.spawn_explosion(_boss_node.position,
			_boss_visual_size.length() * 0.8, Color(1.0, 0.6, 0.3), self,
			"", str(_get_conf("boss_death_explosion", "res://assets/vfx/boss_explosion.tres")),
			-1.0, 0.3, 0.7, false)
		VFXManager.screen_shake(8.0, 0.35)
	var death_sec: float = maxf(0.3, float(_get_conf("boss_death_anim_sec", 1.6)))
	var fade: Tween = _boss_node.create_tween()
	fade.tween_property(_boss_node, "modulate:a", 0.0, death_sec * 0.8)
	fade.tween_callback(_boss_node.queue_free)
	if _is_free_mode():
		# Libre : la boucle continue, un nouveau boss arrive (toughness relue live).
		if _hud and is_instance_valid(_hud) and _hud.has_method("hide_boss_health"):
			_hud.call("hide_boss_health")
		_boss_respawn_timer = maxf(0.5, float(_get_conf("boss_respawn_delay_sec", 2.5)))
	else:
		# Story : victoire anticipée après l'anim de mort.
		_state = State.BOSS_DEATH
		_state_timer = death_sec

func _grant_boss_kill_rewards() -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var center: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
	var points: int = maxi(0, int(round(float(int(_get_conf("boss_kill_score", 4000))) * _reward_multiplier)))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, center)
	if _game.has_method("spawn_reward_crystal_at"):
		for i in range(maxi(1, int(_get_conf("boss_kill_crystals", 8)))):
			_game.call("spawn_reward_crystal_at",
				center + Vector2(randf_range(-60.0, 60.0), randf_range(-30.0, 30.0)), {
					"force_magnet_after_sec": maxf(0.0, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))
				})
	if _game.has_method("spawn_reward_equipment_at"):
		var extra: Dictionary = {
			"auto_collect_delay_sec": maxf(0.0, float(_get_conf("auto_collect_delay_sec", 2.0))),
			"auto_collect_speed_px_sec": maxf(50.0, float(_get_conf("auto_collect_speed_px_sec", 950.0)))
		}
		var min_rarity: String = str(_get_conf("boss_kill_loot_min_rarity", "uncommon"))
		if min_rarity != "":
			_game.call("spawn_reward_equipment_at", center, 1.0, extra, min_rarity)
		else:
			_game.call("spawn_reward_equipment_at", center,
				maxf(1.0, float(_get_conf("boss_kill_loot_quality_mult", 8.0))), extra)

## Fin du timer (story) : le boss remonte hors écran, pas de bonus.
func _start_boss_escape() -> void:
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	if _boss_node == null or not is_instance_valid(_boss_node) or _boss_health <= 0.0:
		_finish()
		return
	_state = State.BOSS_ESCAPE
	_state_timer = maxf(0.2, float(_get_conf("boss_escape_anim_sec", 1.0)))
	var escape: Tween = _boss_node.create_tween()
	escape.tween_property(_boss_node, "position:y", -_boss_visual_size.y, _state_timer) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _hud and is_instance_valid(_hud) and _hud.has_method("hide_boss_health"):
		_hud.call("hide_boss_health")

# =============================================================================
# HUD countdown
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "SnakeCountdownLabel"
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
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.34)), 0.02, 0.9))
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
	# Restore the player and the HUD BEFORE notifying the wave chain.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # segments, items, bordure, boss et labels sont enfants -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
