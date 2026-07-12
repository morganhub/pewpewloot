extends Node2D

## VerticalClimbManager — Orchestre une vague "vertical_climb" :
## avarie moteur, le vaisseau ne vole plus et doit rebondir d'accelerateur en
## accelerateur (plateformes) pour rester au-dessus d'une nappe de lave
## mortelle qui monte. Chaque plateforme TOMBE apres le rebond (usage unique).
## Le monde defile vers le bas quand le vaisseau depasse la ligne d'ascension
## (illusion de montee infinie). Cristaux a ramasser sur la route ; tomber
## dans la lave = mort (tous les HP). Duree limitee, compte a rebours au HUD.
## Y du vaisseau pilote par ce manager (Player.set_climb_y), X reste au joueur.
##
## AMÉLIORATIONS 2026-07-12 :
## - Types de plateformes (champ "kind", asset dédié <kind>_platform_asset) :
##   boost (câble platform_boost.png), conveyor (pousse latéralement au
##   rebond), multi (2-3 rebonds affichés en label), spring (impulsion ×3 +
##   invulnérabilité lave pendant l'envol), elevator (monte, multi-rebonds,
##   sème des cristaux pendant elevator_lifetime_sec).
## - Chances des plateformes spéciales PROGRESSIVES : chance data ×
##   lerp(special_chance_start_ratio, 1, progression) — level en Libre
##   (_free_level_progress), temps écoulé en story.
## - ÉVÉNEMENTS à cooldown aléatoire randf(event_cd_min_sec 15,
##   event_cd_max_sec 30), tirage pondéré climb_events_weights avec
##   anti-répétition : spring/elevator (prochaine plateforme), jetpack/
##   parachute (pickup flottant sur la prochaine plateforme), star_zone
##   (anneau bonus à traverser = pluie de cristaux).
## - Jetpack : 5 s d'ascension continue (plateformes traversées, lave
##   inoffensive). Parachute : 1 charge TOUJOURS VISIBLE (icône sur le
##   vaisseau) — ouverture auto près de la lave : chute lente + lave gelée et
##   inoffensive pendant parachute_duration_sec.
## - Wrap-around horizontal optionnel (wrap_horizontal, côté Player).

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

# --- Événements (cooldown aléatoire 15-30 s, anti-répétition) ---
var _event_timer: float = 0.0
var _last_event: String = ""
var _pending_platform_event: String = "" # "spring"/"elevator" -> prochaine plateforme
var _pending_pickup_event: String = ""   # "jetpack"/"parachute" -> pickup flottant
# Zones étoile : { "node": Node2D, "x": float, "y": float, "radius": float }.
var _star_zones: Array = []
# --- Effets actifs ---
var _jetpack_time: float = 0.0
var _jetpack_flame: Node2D = null
var _parachute_armed: bool = false
var _parachute_time: float = 0.0
var _parachute_icon: Node2D = null
var _parachute_canopy: Node2D = null
var _spring_invuln: bool = false
var _conveyor_push_time: float = 0.0
var _conveyor_push_dir: float = 1.0

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
	_event_timer = randf_range(maxf(1.0, _conf_f("event_cd_min_sec", 15.0)),
		maxf(1.0, _conf_f("event_cd_max_sec", 30.0)))

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
	# Clés relues à la génération/au scheduler : poussées dans _config (dont la
	# progression de level qui pilote les chances progressives en continuous).
	for live_key in ["conveyor_platform_chance", "multi_platform_chance", "event_cd_max_sec", "_free_level_progress"]:
		if cfg.has(live_key):
			_config[live_key] = cfg[live_key]

## Per-wave override (world_X.json / freemode base_wave) > défauts du type.
func _conf_f(key: String, fallback: float) -> float:
	return float(_config.get(key, _cfg.get(key, fallback)))

## Progression 0->1 : level du mode libre (continuous) sinon temps écoulé.
func _progress() -> float:
	if _config.has("_free_level_progress"):
		return clampf(float(_config.get("_free_level_progress", 0.0)), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

## Multiplicateur PROGRESSIF des chances de plateformes spéciales : elles
## démarrent basses (special_chance_start_ratio) et atteignent leur valeur
## data en fin de rampe — jamais constantes.
func _special_chance_mult() -> float:
	return lerpf(clampf(_conf_f("special_chance_start_ratio", 0.3), 0.0, 1.0), 1.0, _progress())

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_climb"):
		_player.call("begin_climb", { "wrap_horizontal": bool(_config.get("wrap_horizontal", _cfg.get("wrap_horizontal", false))) })
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
	# Type de plateforme : les événements en attente (spring/elevator) gagnent,
	# sinon tirage progressif (chances × _special_chance_mult).
	var kind: String = "normal"
	var moving: bool = false
	if not force_static:
		if _pending_platform_event != "":
			kind = _pending_platform_event
			_pending_platform_event = ""
		else:
			var mult: float = _special_chance_mult()
			var roll: float = randf()
			if roll < clampf(_conf_f("boost_platform_chance", 0.12) * mult, 0.0, 1.0):
				kind = "boost"
			elif roll < clampf((_conf_f("boost_platform_chance", 0.12) + _conf_f("conveyor_platform_chance", 0.08)) * mult, 0.0, 1.0):
				kind = "conveyor"
			elif roll < clampf((_conf_f("boost_platform_chance", 0.12) + _conf_f("conveyor_platform_chance", 0.08) + _conf_f("multi_platform_chance", 0.08)) * mult, 0.0, 1.0):
				kind = "multi"
		if kind == "normal":
			moving = randf() <= clampf(_conf_f("moving_platform_chance", 0.22) * _special_chance_mult(), 0.0, 1.0)
	var visual: Node2D = _make_platform_visual(kind)
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
		"kind": kind,
		"crystal": null,
		"pickup": null,
		"pickup_kind": ""
	}
	match kind:
		"conveyor":
			entry["dir"] = 1.0 if randf() < 0.5 else -1.0
			_add_platform_glyph(node, entry, ">>" if float(entry["dir"]) > 0.0 else "<<")
		"multi":
			entry["bounces"] = randi_range(
				maxi(1, int(_conf_f("multi_platform_bounces_min", 2.0))),
				maxi(1, int(_conf_f("multi_platform_bounces_max", 3.0))))
			_add_platform_glyph(node, entry, str(int(entry["bounces"])))
		"elevator":
			entry["lifetime"] = maxf(1.0, _conf_f("elevator_lifetime_sec", 5.0))
			entry["crystal_timer"] = maxf(0.1, _conf_f("elevator_crystal_interval_sec", 0.8))
		_:
			pass
	# Pickup d'événement (jetpack/parachute) : flotte au-dessus de la plateforme.
	if not force_static and _pending_pickup_event != "":
		var pickup: Node2D = _make_pickup_marker(_pending_pickup_event)
		pickup.position = Vector2(0.0, -(_platform_size.y * 0.5 + 40.0))
		node.add_child(pickup)
		entry["pickup"] = pickup
		entry["pickup_kind"] = _pending_pickup_event
		_pending_pickup_event = ""
	# Some accelerators carry a crystal to grab on the way up.
	elif not force_static and randf() <= clampf(_conf_f("crystal_platform_chance", 0.25), 0.0, 1.0):
		var crystal: Node2D = _make_crystal_marker()
		if crystal:
			crystal.position = Vector2(0.0, -(_platform_size.y * 0.5 + 34.0))
			node.add_child(crystal)
			entry["crystal"] = crystal
	_platforms.append(entry)

## Petit glyphe PH sur la plateforme (flèches convoyeur, compte multi) — stocké
## dans l'entry pour mise à jour (multi).
func _add_platform_glyph(node: Node2D, entry: Dictionary, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = _platform_size
	label.position = -_platform_size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	entry["glyph"] = label

## "Cover" fill: the platform asset is cropped to the platform aspect ratio
## then scaled to the exact platform size. Asset dédié par TYPE
## (<kind>_platform_asset — le boost câble enfin platform_boost.png), fallback
## pool platform_assets + teinte PH par type.
func _make_platform_visual(kind: String = "normal") -> Node2D:
	var tex: Texture2D = null
	if kind != "normal":
		tex = _texture_from_path(str(_config.get(kind + "_platform_asset", _cfg.get(kind + "_platform_asset", ""))))
	var dedicated: bool = tex != null
	if tex == null:
		tex = _texture_from_path(_pick_platform_asset())
	var visual: Node2D
	if tex == null:
		var poly := Polygon2D.new()
		var half: Vector2 = _platform_size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		poly.color = Color("#7FA8C9")
		visual = poly
	else:
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
		visual = sprite
	# PH : teinte par type tant que l'asset dédié manque.
	if not dedicated:
		match kind:
			"boost":
				visual.modulate = Color(str(_cfg.get("boost_tint", "#FFD56B")))
			"spring":
				visual.modulate = Color("#7FE58C")
			"conveyor":
				visual.modulate = Color("#9AD8FF")
			"elevator":
				visual.modulate = Color("#C77CFF")
			"multi":
				visual.modulate = Color("#E0C8A0")
			_:
				pass
	return visual

## Pickup flottant (jetpack/parachute) : asset dédié sinon PH cercle + lettre.
func _make_pickup_marker(kind: String) -> Node2D:
	var root := Node2D.new()
	root.name = "ClimbPickup"
	var tex: Texture2D = _texture_from_path(str(_cfg.get(kind + "_pickup_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * 44.0) / maxf(tex_size.x, tex_size.y)
		root.add_child(sprite)
		return root
	var circle := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 20.0)
	circle.polygon = pts
	circle.color = Color("#FF8A5C") if kind == "jetpack" else Color("#8FD3FF")
	root.add_child(circle)
	var label := Label.new()
	label.text = "J" if kind == "jetpack" else "P"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(40, 40)
	label.position = Vector2(-20, -20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return root

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
			_update_events(dt)
			_step_climb(dt)
			_update_star_zones(dt)
			_update_effect_visuals()
	_update_lava_position()
	if _elapsed >= _duration:
		_finish()

func _step_climb(dt: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var prev_bottom: float = _ship_y + _ship_half_h
	# Jetpack : ascension continue, gravité coupée, plateformes traversées.
	if _jetpack_time > 0.0:
		_jetpack_time -= dt
		_ship_vy = -maxf(120.0, _conf_f("jetpack_speed_px_sec", 700.0))
	else:
		_ship_vy += _gravity * dt
	# Ressort : l'invulnérabilité lave dure tant que l'envol monte.
	if _spring_invuln and _ship_vy >= 0.0:
		_spring_invuln = false
	# Parachute armé : ouverture AUTO quand la chute approche la lave.
	if _parachute_armed and _parachute_time <= 0.0 and _ship_vy > 0.0 \
		and _ship_y + _ship_half_h >= _lava_top_y - maxf(20.0, _conf_f("parachute_trigger_above_lava_px", 100.0)):
		_parachute_armed = false
		_parachute_time = maxf(0.5, _conf_f("parachute_duration_sec", 2.5))
		if _parachute_canopy and is_instance_valid(_parachute_canopy):
			_parachute_canopy.visible = true
		if VFXManager and _player and is_instance_valid(_player):
			VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -70.0),
				_translate_or("climb_parachute", "PARACHUTE!"), Color("#8FD3FF"), self)
	# Parachute ouvert : chute clampée lente (le temps de viser une plateforme).
	if _parachute_time > 0.0:
		_parachute_time -= dt
		_ship_vy = minf(_ship_vy, maxf(40.0, _conf_f("parachute_fall_speed_px_sec", 130.0)))
		if _parachute_time <= 0.0 and _parachute_canopy and is_instance_valid(_parachute_canopy):
			_parachute_canopy.visible = false
	# Convoyeur : poussée latérale brève après le rebond.
	if _conveyor_push_time > 0.0:
		_conveyor_push_time -= dt
		if _player.has_method("apply_external_displacement"):
			_player.call("apply_external_displacement",
				Vector2(_conveyor_push_dir * maxf(0.0, _conf_f("conveyor_push_px_sec", 260.0)) * dt, 0.0))
	var new_y: float = _ship_y + _ship_vy * dt
	var new_bottom: float = new_y + _ship_half_h
	var ship_x: float = _player.global_position.x

	# Platform contacts: only while falling, only crossing the platform top.
	# (Jetpack : on traverse tout sans consommer les accélérateurs.)
	if _ship_vy > 0.0 and _jetpack_time <= 0.0:
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
					_ship_vy = -_bounce_speed_for(entry)
					_consume_platform_bounce(entry)
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

	# Lava: slow rise, deadly on contact (full HP loss = level lost). Gelée
	# pendant l'ouverture du parachute ; inoffensive pendant jetpack/ressort/
	# parachute (leur raison d'être).
	if _parachute_time <= 0.0:
		_lava_top_y = clampf(_lava_top_y - _lava_rise * dt, _lava_top_min_y, _lava_top_max_y)
	var lava_immune: bool = _jetpack_time > 0.0 or _spring_invuln or _parachute_time > 0.0
	if not lava_immune and (_ship_y + _ship_half_h >= _lava_top_y or _ship_y > viewport_size.y + 60.0):
		if _player.has_method("take_damage"):
			_player.call("take_damage", 99999)

## Vitesse de rebond selon le type de plateforme.
func _bounce_speed_for(entry: Dictionary) -> float:
	match str(entry.get("kind", "normal")):
		"boost":
			return _boost_bounce_speed
		"spring":
			_spring_invuln = true
			return _bounce_speed * maxf(1.0, _conf_f("spring_bounce_mult", 3.0))
		_:
			return _bounce_speed

## Après rebond : convoyeur pousse, multi décrémente, elevator/multi survivent,
## les autres tombent (usage unique).
func _consume_platform_bounce(entry: Dictionary) -> void:
	var kind: String = str(entry.get("kind", "normal"))
	match kind:
		"conveyor":
			_conveyor_push_time = maxf(0.05, _conf_f("conveyor_push_duration_sec", 0.35))
			_conveyor_push_dir = float(entry.get("dir", 1.0))
			_drop_platform(entry)
		"multi":
			var left: int = int(entry.get("bounces", 1)) - 1
			entry["bounces"] = left
			var glyph_v: Variant = entry.get("glyph", null)
			if glyph_v is Label and is_instance_valid(glyph_v):
				(glyph_v as Label).text = str(maxi(0, left))
			if left <= 0:
				_drop_platform(entry)
			elif VFXManager:
				var m_node: Variant = entry.get("node", null)
				if m_node is Node2D and is_instance_valid(m_node):
					VFXManager.flash_sprite(m_node, Color(1.5, 1.5, 1.5), 0.08)
		"elevator":
			# Multi-rebonds : l'ascenseur ne tombe qu'à la fin de sa vie.
			if VFXManager:
				var e_node: Variant = entry.get("node", null)
				if e_node is Node2D and is_instance_valid(e_node):
					VFXManager.flash_sprite(e_node, Color(1.4, 1.4, 1.4), 0.08)
		_:
			_drop_platform(entry)

func _scroll_world(amount: float) -> void:
	for entry in _platforms:
		entry["y"] = float(entry.get("y", 0.0)) + amount
	for zone in _star_zones:
		zone["y"] = float(zone.get("y", 0.0)) + amount
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
		elif str(entry.get("kind", "normal")) == "elevator":
			# Ascenseur : monte, sème des cristaux, tombe en fin de vie.
			entry["y"] = float(entry.get("y", 0.0)) - maxf(10.0, _conf_f("elevator_rise_px_sec", 70.0)) * dt
			entry["lifetime"] = float(entry.get("lifetime", 5.0)) - dt
			entry["crystal_timer"] = float(entry.get("crystal_timer", 0.8)) - dt
			if float(entry["crystal_timer"]) <= 0.0:
				entry["crystal_timer"] = maxf(0.1, _conf_f("elevator_crystal_interval_sec", 0.8))
				if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
					_game.call("spawn_reward_crystal_at", node.global_position + Vector2(0.0, 26.0))
			if float(entry["lifetime"]) <= 0.0 or float(entry.get("y", 0.0)) < -80.0:
				_drop_platform(entry)
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
		if crystal_v is Node2D and is_instance_valid(crystal_v):
			var crystal: Node2D = crystal_v as Node2D
			if crystal.global_position.distance_to(player_pos) <= _crystal_pickup_radius:
				entry["crystal"] = null
				crystal.queue_free()
				# The real reward spawns on the ship and is magnet-collected
				# instantly by the standard bonus-crystal flow (score, VFX).
				if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
					_game.call("spawn_reward_crystal_at", player_pos)
		# Pickups d'événements (jetpack / parachute) : même pattern de collecte.
		var pickup_v: Variant = entry.get("pickup", null)
		if pickup_v is Node2D and is_instance_valid(pickup_v):
			var pickup: Node2D = pickup_v as Node2D
			if pickup.global_position.distance_to(player_pos) <= _crystal_pickup_radius + 10.0:
				var pickup_kind: String = str(entry.get("pickup_kind", ""))
				entry["pickup"] = null
				entry["pickup_kind"] = ""
				pickup.queue_free()
				_activate_pickup(pickup_kind)

func _activate_pickup(kind: String) -> void:
	match kind:
		"jetpack":
			_jetpack_time = maxf(1.0, _conf_f("jetpack_duration_sec", 5.0))
			if VFXManager and _player and is_instance_valid(_player):
				VFXManager.spawn_floating_text(_player.global_position + Vector2(0.0, -70.0),
					_translate_or("climb_jetpack", "JETPACK!"), Color("#FF8A5C"), self)
		"parachute":
			_parachute_armed = true
			_ensure_parachute_visuals()
		_:
			pass

# =============================================================================
# ÉVÉNEMENTS (cooldown aléatoire 15-30 s, anti-répétition) + ZONES ÉTOILE
# =============================================================================

func _update_events(dt: float) -> void:
	# Un événement en attente de matérialisation retient le scheduler.
	if _pending_platform_event != "" or _pending_pickup_event != "":
		return
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(maxf(1.0, _conf_f("event_cd_min_sec", 15.0)),
		maxf(maxf(1.0, _conf_f("event_cd_min_sec", 15.0)), _conf_f("event_cd_max_sec", 30.0)))
	var picked: String = _pick_climb_event()
	if picked == "":
		return
	_last_event = picked
	match picked:
		"spring", "elevator":
			_pending_platform_event = picked
		"jetpack", "parachute":
			_pending_pickup_event = picked
		"star_zone":
			_spawn_star_zone()
		_:
			pass

## Tirage pondéré (climb_events_weights) avec anti-répétition ; parachute
## retiré si déjà armé/ouvert, jetpack retiré si actif.
func _pick_climb_event() -> String:
	var weights_v: Variant = _config.get("climb_events_weights", _cfg.get("climb_events_weights", {}))
	var weights: Dictionary = (weights_v as Dictionary).duplicate() if weights_v is Dictionary else {}
	if weights.is_empty():
		weights = {"spring": 25, "elevator": 20, "star_zone": 20, "jetpack": 20, "parachute": 15}
	weights.erase(_last_event)
	if _parachute_armed or _parachute_time > 0.0:
		weights.erase("parachute")
	if _jetpack_time > 0.0:
		weights.erase("jetpack")
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

## Zone étoile : anneau balisé posé au-dessus de l'écran — la traverser en
## grimpant = pluie de cristaux.
func _spawn_star_zone() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var radius: float = maxf(30.0, _conf_f("star_zone_radius_px", 90.0))
	var node := Node2D.new()
	node.name = "StarZone"
	node.z_as_relative = false
	node.z_index = 8
	var tex: Texture2D = _texture_from_path(str(_cfg.get("star_zone_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * radius * 2.0) / maxf(tex_size.x, tex_size.y)
		node.add_child(sprite)
	else:
		# PH : anneau doré (Line2D circulaire).
		var ring := Line2D.new()
		ring.width = 6.0
		ring.default_color = Color("#FFD866")
		var pts := PackedVector2Array()
		for i in range(33):
			var a: float = TAU * float(i) / 32.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		ring.points = pts
		node.add_child(ring)
	var x: float = randf_range(_side_margin + radius, viewport_size.x - _side_margin - radius)
	node.position = Vector2(x, -radius - 60.0)
	add_child(node)
	_star_zones.append({ "node": node, "x": x, "y": node.position.y, "radius": radius })

func _update_star_zones(dt: float) -> void:
	if _star_zones.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var player_pos: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else Vector2(-9999, -9999)
	for i in range(_star_zones.size() - 1, -1, -1):
		var zone: Dictionary = _star_zones[i]
		var node_v: Variant = zone.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_star_zones.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position = Vector2(float(zone.get("x", 0.0)), float(zone.get("y", 0.0)))
		node.modulate.a = 0.6 + 0.4 * absf(sin(_time * 4.0))
		# Traversée : pluie de cristaux garantie.
		if node.position.distance_to(player_pos) <= float(zone.get("radius", 90.0)):
			if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
				_game.call("spawn_reward_crystals_from_top", maxi(1, int(_conf_f("star_zone_crystals", 6.0))))
			if VFXManager:
				VFXManager.spawn_impact(node.position, 26.0, self)
				VFXManager.spawn_floating_text(player_pos + Vector2(0.0, -70.0),
					_translate_or("climb_star_zone", "STAR ZONE!"), Color("#FFD866"), self)
			node.queue_free()
			_star_zones.remove_at(i)
			continue
		if float(zone.get("y", 0.0)) > viewport_size.y + 120.0:
			node.queue_free()
			_star_zones.remove_at(i)

## Visuels d'effets attachés au vaisseau : flamme jetpack, icône parachute
## armé (TOUJOURS visible tant qu'il est porté), canopy pendant l'ouverture.
func _update_effect_visuals() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	# Flamme jetpack (PH triangle orange sous le vaisseau).
	if _jetpack_time > 0.0:
		if _jetpack_flame == null or not is_instance_valid(_jetpack_flame):
			_jetpack_flame = Node2D.new()
			var tri := Polygon2D.new()
			tri.polygon = PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(0, 30)])
			tri.color = Color("#FF8A5C")
			_jetpack_flame.add_child(tri)
			_jetpack_flame.z_as_relative = false
			_jetpack_flame.z_index = 12
			add_child(_jetpack_flame)
		_jetpack_flame.position = player_pos + Vector2(0.0, _ship_half_h + 6.0)
		_jetpack_flame.scale = Vector2.ONE * (0.8 + 0.3 * absf(sin(_time * 18.0)))
	elif _jetpack_flame and is_instance_valid(_jetpack_flame):
		_jetpack_flame.queue_free()
		_jetpack_flame = null
	# Parachute : icône armée / canopy déployée suivent le vaisseau.
	if _parachute_icon and is_instance_valid(_parachute_icon):
		_parachute_icon.visible = _parachute_armed
		_parachute_icon.position = player_pos + Vector2(0.0, -(_ship_half_h + 26.0))
	if _parachute_canopy and is_instance_valid(_parachute_canopy):
		_parachute_canopy.visible = _parachute_time > 0.0
		_parachute_canopy.position = player_pos + Vector2(0.0, -(_ship_half_h + 40.0))

func _ensure_parachute_visuals() -> void:
	if _parachute_icon == null or not is_instance_valid(_parachute_icon):
		_parachute_icon = _make_pickup_marker("parachute")
		_parachute_icon.scale = Vector2.ONE * 0.6
		_parachute_icon.z_as_relative = false
		_parachute_icon.z_index = 12
		add_child(_parachute_icon)
	if _parachute_canopy == null or not is_instance_valid(_parachute_canopy):
		_parachute_canopy = Node2D.new()
		_parachute_canopy.z_as_relative = false
		_parachute_canopy.z_index = 12
		var tex: Texture2D = _texture_from_path(str(_cfg.get("parachute_canopy_asset", "")))
		if tex != null:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			var tex_size: Vector2 = tex.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = (Vector2.ONE * 90.0) / maxf(tex_size.x, tex_size.y)
			_parachute_canopy.add_child(sprite)
		else:
			# PH : demi-disque bleu clair.
			var canopy := Polygon2D.new()
			var pts := PackedVector2Array()
			for i in range(17):
				var a: float = PI * float(i) / 16.0
				pts.append(Vector2(-cos(a), -sin(a)) * 46.0)
			canopy.polygon = pts
			canopy.color = Color("#8FD3FFC8")
			_parachute_canopy.add_child(canopy)
		_parachute_canopy.visible = false
		add_child(_parachute_canopy)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

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
