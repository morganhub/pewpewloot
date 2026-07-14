extends Node2D

## GravityHoleManager — Vague "gravity_hole" refondue façon AGAR.IO (12 juillet
## 2026) : le vaisseau-vortex est verrouillé au CENTRE de l'écran et c'est le
## MONDE qui bouge autour de lui (conteneur _world_root translaté/scalé). Le
## deplacement est omnidirectionnel (doigt = direction + magnitude, pattern
## slice_rush), le vaisseau S'ORIENTE en douceur vers sa direction
## (lerp_angle -> Player.set_gravity_hole_facing). En grossissant, un ZOOM-OUT
## simulé rétrécit le monde (props, fond, distances) pendant que le vaisseau
## garde sa taille écran — principe Agar.io — et la vitesse décroît avec la
## masse. Fond = grille de tuiles du bg choisi repositionnées modulo (défilement
## infini), installée sous le cover signature (aura noire constellation,
## chorégraphie intro/outro conservée).
## Écosystème : MONDE SEEDÉ PERSISTANT — le monde est découpé en chunks dont le
## contenu (props, pickups, zones électrifiées) est généré déterministiquement
## depuis un seed roulé au chargement (hash(cx, cy, seed)) : quitter une zone et
## y revenir = retrouver les mêmes objets (les absorbés restent absorbés, les
## positions dérivées sont écrites dans le record au despawn). Props
## mangeables/oversize (couleurs par taille relative), CHASSEURS (les gros
## poursuivent le joueur 6-12 s random puis abandonnent), GÉANTS aux hautes
## masses, garde-fou de solvabilité (toujours un mangeable à portée, spawns
## éphémères hors seed) + FLÈCHE omnidirectionnelle vers le mangeable le plus
## proche quand l'écran est vide. Labels d'effets optionnels sur les objets
## (toggle racine wave_types.json > effect_labels_enabled — béquille lisibilité
## tant que les assets ne sont pas explicites). Fin par OBJECTIF DE TAILLE (story : cible
## facile en ~60 s ; Libre restart : cible par round croissante) — avec chance
## de finale en NOYAU FRAGMENTÉ (3 fragments à absorber en ordre).
## Pickups (magnet, compass, surcharge, mini-trou compagnon, stabilisateur),
## variantes (props fuyants, zones électrifiées, props explosifs, gigognes,
## masse fondante) et événements en TOASTS centraux (champ d'astéroïdes, trou
## rival, comète dorée, inversion, dimension bonus, clear screen, tempête).
## Tir coupé, contacts par distance en UNITÉS MONDE, pas de physics engine ;
## pas de drops d'équipement (score/cristaux only).

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
var _run_duration: float = 60.0
var _run_elapsed: float = 0.0
var _reward_mult: float = 1.0

# Vortex mass/radius (owned here, pushed to Player for label + aura scale).
var _mass: float = 10.0
var _start_mass: float = 10.0
var _radius: float = 42.0 # rayon d'absorption en UNITÉS MONDE

# Monde mobile (Agar.io) : le joueur est un point du monde, le conteneur est
# translaté/scalé pour le garder au centre écran.
var _world_root: Node2D = null
var _world_pos: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _move_vel: Vector2 = Vector2.ZERO
var _facing: float = 0.0 # 0 = sprite vers le haut (rotation du visual_container)
var _touch_active: bool = false
var _touch_id: int = -1
var _finger_screen: Vector2 = Vector2.ZERO
const MOUSE_CAPTURE_ID: int = -2

# Fond tuilé infini (pool de Sprite2D repositionnés modulo).
var _bg_texture: Texture2D = null
var _bg_normal_texture: Texture2D = null
var _bg_tiles: Array = []
const BG_TILE_POOL_MAX: int = 30

# Drift field. Entries: { "node": Node2D, "label": Label|null,
# "required_mass": float, "mass_gain": float, "radius_px": float,
# "velocity": Vector2, "rot_speed": float, "state": PropState,
# "absorb_t": float, "absorb_sec": float, "start_scale": Vector2,
# "type_tint": Color, "score_base": int, "crystal_chance": float,
# "near": bool } + optionnels : "chaser"/"chasing"/"chase_until"/
# "chase_cd_until"/"chase_speed_ratio", "giant", "flee", "nested",
# "explosive", "comet", "fragment_index", "record" (props seedés).
var _props: Array = []
var _oversize_cooldown: float = 0.0
var _solvability_timer: float = 0.0
var _no_target_timer: float = 0.0
var _explosive_check_timer: float = 0.0

# Monde seedé persistant : chunks générés déterministiquement depuis
# _world_seed. Records { pos, type, required_mass (ABSOLUE, figée à la
# découverte de la zone), mass_gain, velocity, rot_speed, consumed, live,
# flags variantes }. consumed = mangé pour de bon ; live = node instancié.
var _world_seed: int = 0
var _chunks: Dictionary = {} # Vector2i -> { "props": [rec], "pickups": [rec], "zones": [rec] }
var _chunk_stream_timer: float = 0.0
var _zone_chunk_chance: float = 0.0
var _storm_spawn_timer: float = 0.0

# Objectif de taille + noyau fragmenté.
var _target_mass: float = 50.0
var _fragment_roll_done: bool = false
var _next_fragment: int = 0
var _fragments_total: int = 0
var _target_reached: bool = false

# Pickups (orbes monde, seedés par chunk) + effets temporels.
var _pickups: Array = [] # { "node", "id", "pulse", "record" }
var _magnet_left: float = 0.0
var _compass_left: float = 0.0
var _overdrive_left: float = 0.0
var _companion_left: float = 0.0
var _companion_node: Node2D = null
var _companion_angle: float = 0.0
var _stabilizer_charges: int = 0
var _stabilizer_node: Node2D = null

# Zones électrifiées (poches fixes en monde).
var _zones: Array = [] # { "node", "pos", "radius", "tick_timer" }

# Événements (toasts centraux) : scheduler + fenêtres exclusives.
var _event_timer: float = 0.0
var _last_event_id: String = ""
var _rival_left: float = 0.0
var _rival_node: Node2D = null
var _inversion_left: float = 0.0
var _storm_left: float = 0.0
var _dimension_left: float = 0.0
var _last_clear_screen: float = -100.0
var _clear_screen_peak: int = 0

# Flèche omnidirectionnelle vers le mangeable le plus proche hors écran.
var _arrow_root: Node2D = null

# Transition (intro/outro cover) state.
var _chosen_bg: String = ""
var _transition_sprite: AnimatedSprite2D = null
var _transition_tween: Tween = null
var _transition_follow: bool = false
var _outro_started: bool = false

var _countdown_label: Label = null
var _progress_label: Label = null
var _finished_emitted: bool = false

const PICKUP_TINTS: Dictionary = {
	"magnet": "#FF5C8A", "compass": "#FFD866", "overdrive": "#C77CFF",
	"companion": "#5CE8FF", "stabilizer": "#7FE58C", "chest": "#FFD866"
}
const PICKUP_GLYPHS: Dictionary = {
	"magnet": "M", "compass": "C", "overdrive": "G", "companion": "V", "stabilizer": "S", "chest": "$"
}

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

	_run_duration = maxf(10.0, float(_get_conf("duration", _get_conf("duration_sec_default", 60.0))))
	_start_mass = maxf(1.0, float(_get_conf("start_mass", 10.0)))
	_mass = _start_mass
	_radius = _compute_radius()
	_target_mass = maxf(_start_mass * 1.5, round(_start_mass * maxf(1.2, float(_get_conf("target_mass_mult", 5.0)))))
	_reward_mult = maxf(0.05, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	var bgs_v: Variant = _get_conf("bg_assets", [])
	if bgs_v is Array and not (bgs_v as Array).is_empty():
		var bgs: Array = bgs_v as Array
		_chosen_bg = str(bgs[randi() % bgs.size()])

	# Seed du monde : 0 = roulé au chargement (partagé par tous les chunks —
	# le joueur retrouve toujours les mêmes objets aux mêmes endroits).
	_world_seed = int(_get_conf("world_seed", 0))
	if _world_seed == 0:
		_world_seed = int(randi()) | 1
	# electric_zone_count = zones attendues dans la vue de départ, converti en
	# chance par chunk (les zones s'étalent sur tout le monde parcouru).
	var chunk_size: float = maxf(200.0, float(_get_conf("chunk_size_px", 640.0)))
	var ring_r: float = get_viewport_rect().size.length() * 0.5 \
		* maxf(0.4, float(_get_conf("spawn_ring_ratio", 1.15)))
	var chunks_in_view: float = maxf(1.0, PI * ring_r * ring_r / (chunk_size * chunk_size))
	_zone_chunk_chance = clampf(maxf(0.0, float(_get_conf("electric_zone_count", 0.0))) / chunks_in_view, 0.0, 1.0)

	_event_timer = randf_range(
		maxf(5.0, float(_get_conf("event_interval_sec_min", 20.0))),
		maxf(5.0, float(_get_conf("event_interval_sec_max", 35.0))))

	_ensure_countdown_label()
	# countdown_hidden (mode libre) : le label n'est jamais créé — guard.
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = false
	_begin_intro()
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

func _screen_center() -> Vector2:
	return get_viewport_rect().size * 0.5

## Rayon (unités monde) du disque visible : demi-diagonale écran dézoomée.
func _view_radius() -> float:
	return get_viewport_rect().size.length() * 0.5 / maxf(0.05, _zoom)

func _world_to_screen(world_p: Vector2) -> Vector2:
	if _world_root and is_instance_valid(_world_root):
		return world_p * _zoom + _world_root.position
	return world_p

func _is_on_screen(world_p: Vector2, margin: float = 0.0) -> bool:
	var sp: Vector2 = _world_to_screen(world_p)
	var viewport_size: Vector2 = get_viewport_rect().size
	return sp.x >= -margin and sp.y >= -margin \
		and sp.x <= viewport_size.x + margin and sp.y <= viewport_size.y + margin

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_gravity_hole"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_gravity_hole", merged)
		# Refonte Agar.io : vaisseau au CENTRE, le monde bouge (sous cover).
		if _player.has_method("set_gravity_hole_center_lock"):
			_player.call("set_gravity_hole_center_lock", _screen_center())
		_push_player_state()
	if _hud and is_instance_valid(_hud):
		if _hud.has_method("set_power_buttons_suppressed"):
			_hud.call("set_power_buttons_suppressed", true)
		if _hud.has_method("set_joystick_visual_enabled"):
			_hud.call("set_joystick_visual_enabled", false)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_gravity_hole"):
		_player.call("end_gravity_hole")
	if _hud and is_instance_valid(_hud):
		if _hud.has_method("set_power_buttons_suppressed"):
			_hud.call("set_power_buttons_suppressed", false)
		if _hud.has_method("set_joystick_visual_enabled"):
			_hud.call("set_joystick_visual_enabled", true)

## Le rayon écran de l'aura suit le zoom (rayon monde x zoom).
func _push_player_state() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_gravity_hole_mass"):
		_player.call("set_gravity_hole_mass", _mass)
	if _player.has_method("set_gravity_hole_radius"):
		_player.call("set_gravity_hole_radius", _radius * _zoom)

func _compute_radius() -> float:
	var base: float = maxf(10.0, float(_get_conf("absorption_radius_base_px", 42.0)))
	var growth: float = maxf(0.0, float(_get_conf("absorption_radius_growth", 6.0)))
	var cap: float = maxf(base, float(_get_conf("absorption_radius_max_px", 460.0)))
	return minf(base + sqrt(maxf(0.0, _mass)) * growth, cap)

## Zoom cible Agar.io : inversement proportionnel à la masse (exposant doux).
func _target_zoom() -> float:
	var exponent: float = clampf(float(_get_conf("zoom_exponent", 0.28)), 0.05, 1.0)
	return clampf(pow(_start_mass / maxf(_start_mass, _mass), exponent),
		clampf(float(_get_conf("zoom_min", 0.35)), 0.1, 1.0), 1.0)

## Vitesse joueur (unités monde) : les gros sont lents (Agar.io).
func _current_speed() -> float:
	var base: float = maxf(60.0, float(_get_conf("move_speed_base_px_sec", 340.0)))
	var exponent: float = clampf(float(_get_conf("speed_mass_exponent", 0.18)), 0.0, 1.0)
	return base * pow(_start_mass / maxf(_start_mass, _mass), exponent)

func _gain_mass(amount: float) -> void:
	_mass += maxf(0.0, amount)
	_radius = _compute_radius()
	_push_player_state()
	_retint_all_props()

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
	return _radius * _zoom * 2.0 * maxf(0.2, float(_get_conf("aura_visual_ratio", 1.08)))

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

## Under full cover: build the moving world (tiled bg container), center-lock
## the ship and enter the player mode (aura still hidden — the cover sprite IS
## the vortex for now).
func _on_intro_cover() -> void:
	_build_world_root()
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
	_chunk_stream_timer = 0.0
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = true

func _begin_outro() -> void:
	if _outro_started or _state == State.DONE:
		return
	_outro_started = true
	_state = State.OUTRO
	_touch_active = false
	if _countdown_label and is_instance_valid(_countdown_label):
		_countdown_label.visible = false
	if _progress_label and is_instance_valid(_progress_label):
		_progress_label.visible = false
	if _arrow_root and is_instance_valid(_arrow_root):
		_arrow_root.visible = false
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

## Under full cover: tear down the moving world and restore the player while
## nobody can see it.
func _on_outro_cover() -> void:
	_transition_follow = false
	_restore_player_mode()
	if _world_root and is_instance_valid(_world_root):
		_world_root.queue_free()
	_world_root = null
	_bg_tiles.clear() # les tuiles sont enfants de _world_root : libérées avec lui
	_props.clear()
	_pickups.clear()
	_zones.clear()
	_rival_node = null
	_companion_node = null

# =============================================================================
# MONDE MOBILE (conteneur + fond tuilé infini + input)
# =============================================================================

func _build_world_root() -> void:
	if _world_root and is_instance_valid(_world_root):
		return
	_world_root = Node2D.new()
	_world_root.name = "GravityWorld"
	add_child(_world_root)
	_world_pos = Vector2.ZERO
	_zoom = 1.0
	var bg_res: Resource = _load_cached_resource(_chosen_bg)
	_bg_texture = bg_res as Texture2D if bg_res is Texture2D else null
	_bg_normal_texture = _bg_texture
	_update_world_transform()
	_update_bg_tiles()

func _update_world_transform() -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	_world_root.scale = Vector2.ONE * _zoom
	_world_root.position = _screen_center() - _world_pos * _zoom

## Grille de tuiles du bg repositionnées modulo autour du joueur — défilement
## infini omnidirectionnel, quel que soit le zoom (pool borné).
func _update_bg_tiles() -> void:
	if _world_root == null or not is_instance_valid(_world_root) or _bg_texture == null:
		for tile_v in _bg_tiles:
			if is_instance_valid(tile_v) and tile_v is Sprite2D:
				(tile_v as Sprite2D).visible = false
		return
	var tex_size: Vector2 = _bg_texture.get_size()
	if tex_size.x < 2.0 or tex_size.y < 2.0:
		return
	var view_half: Vector2 = get_viewport_rect().size / maxf(0.05, _zoom) * 0.5
	var min_cx: int = int(floor((_world_pos.x - view_half.x) / tex_size.x))
	var max_cx: int = int(floor((_world_pos.x + view_half.x) / tex_size.x))
	var min_cy: int = int(floor((_world_pos.y - view_half.y) / tex_size.y))
	var max_cy: int = int(floor((_world_pos.y + view_half.y) / tex_size.y))
	var used: int = 0
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			if used >= BG_TILE_POOL_MAX:
				break
			var tile: Sprite2D
			if used < _bg_tiles.size():
				tile = _bg_tiles[used]
			else:
				tile = Sprite2D.new()
				tile.z_as_relative = false
				tile.z_index = -60 # au-dessus du bg de niveau (-90), sous le gameplay
				_world_root.add_child(tile)
				_bg_tiles.append(tile)
			tile.texture = _bg_texture
			tile.visible = true
			tile.position = Vector2((float(cx) + 0.5) * tex_size.x, (float(cy) + 0.5) * tex_size.y)
			used += 1
	for i in range(used, _bg_tiles.size()):
		var extra_v: Variant = _bg_tiles[i]
		if is_instance_valid(extra_v) and extra_v is Sprite2D:
			(extra_v as Sprite2D).visible = false

## Input direction (pattern slice_rush) : doigt posé = direction depuis le
## centre écran + magnitude ; relâché = décélération douce.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _touch_id == -1:
			_touch_id = touch.index
			_touch_active = true
			_finger_screen = touch.position
		elif not touch.pressed and touch.index == _touch_id:
			_touch_id = -1
			_touch_active = false
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_finger_screen = drag.position
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed and _touch_id == -1:
			_touch_id = MOUSE_CAPTURE_ID
			_touch_active = true
			_finger_screen = mouse_btn.position
		elif not mouse_btn.pressed and _touch_id == MOUSE_CAPTURE_ID:
			_touch_id = -1
			_touch_active = false
	elif event is InputEventMouseMotion:
		if _touch_id == MOUSE_CAPTURE_ID:
			_finger_screen = (event as InputEventMouseMotion).position

## Déplace le MONDE (le vaisseau reste au centre) + oriente le vaisseau en
## douceur vers sa direction (rapide mais visible).
func _tick_movement(dt: float) -> void:
	var move_input := Vector2.ZERO
	if _touch_active:
		var d: Vector2 = _finger_screen - _screen_center()
		var deadzone: float = maxf(2.0, float(_get_conf("move_deadzone_px", 24.0)))
		if d.length() > deadzone:
			var full: float = maxf(20.0, float(_get_conf("move_full_speed_radius_px", 130.0)))
			move_input = d.normalized() * clampf((d.length() - deadzone) / full, 0.0, 1.0)
	var speed: float = _current_speed()
	var response: float = speed / maxf(0.05, float(_get_conf("move_accel_sec", 0.22)))
	_move_vel = _move_vel.move_toward(move_input * speed, response * dt)
	_world_pos += _move_vel * dt
	# Rotation smooth : lerp_angle vers la direction (sprite pointe vers le haut).
	if _move_vel.length() > speed * 0.08:
		var target_angle: float = _move_vel.angle() + PI * 0.5
		_facing = lerp_angle(_facing, target_angle,
			clampf(maxf(1.0, float(_get_conf("facing_turn_speed_rad", 9.0))) * dt, 0.0, 1.0))
		if _player and is_instance_valid(_player) and _player.has_method("set_gravity_hole_facing"):
			_player.call("set_gravity_hole_facing", _facing)
	# Zoom-out Agar.io lissé.
	_zoom = lerpf(_zoom, _target_zoom(),
		clampf(maxf(0.2, float(_get_conf("zoom_lerp_speed", 3.0))) * dt, 0.0, 1.0))

# =============================================================================
# PROPS (drift field en unités monde)
# =============================================================================

## rng fourni = tirage déterministe (génération de chunk seedé).
func _pick_prop_type(rng: RandomNumberGenerator = null) -> Dictionary:
	var types: Array = []
	var types_v: Variant = _get_conf("props", [])
	if types_v is Array:
		types = (types_v as Array).duplicate()
	# Géants : rejoignent le pool quand le joueur a suffisamment grossi.
	if _mass >= _start_mass * maxf(1.0, float(_get_conf("giant_spawn_min_mass_mult", 2.5))):
		var giants_v: Variant = _get_conf("giants", [])
		if giants_v is Array:
			for g_v in (giants_v as Array):
				types.append(g_v)
	if types.is_empty():
		return {}
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
	var roll: float = (rng.randf() if rng != null else randf()) * total
	for i in range(types.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			return types[i] as Dictionary
	return types[types.size() - 1] as Dictionary

## Position de spawn sur un anneau autour du joueur (hors écran, monde).
func _ring_spawn_pos(ratio: float = -1.0, forced_angle: float = NAN) -> Vector2:
	var ring: float = _view_radius() * (maxf(0.4, float(_get_conf("spawn_ring_ratio", 1.15))) if ratio <= 0.0 else ratio)
	var angle: float = forced_angle if not is_nan(forced_angle) else randf() * TAU
	return _world_pos + Vector2.from_angle(angle) * ring

## Génère les records d'un chunk (déterministe : hash(cx, cy, seed)). Les
## masses sont figées en ABSOLU à la génération — relatives à la masse du
## joueur au moment où il découvre la zone : revenir plus tard = retrouver les
## mêmes objets (devenus faciles si on a grossi, comme en Agar.io).
func _ensure_chunk(coords: Vector2i) -> Dictionary:
	if _chunks.has(coords):
		return _chunks[coords]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coords.x, coords.y, _world_seed))
	var chunk_size: float = maxf(200.0, float(_get_conf("chunk_size_px", 640.0)))
	var origin: Vector2 = Vector2(coords) * chunk_size
	var chunk: Dictionary = { "props": [], "pickups": [], "zones": [] }
	var count: int = rng.randi_range(
		maxi(0, int(_get_conf("chunk_props_min", 1))),
		maxi(0, int(_get_conf("chunk_props_max", 3))))
	for i in range(count):
		var type: Dictionary = _pick_prop_type(rng)
		if type.is_empty():
			continue
		var required: float = maxf(1.0, round(_mass * rng.randf_range(
			float(type.get("mass_ratio_min", 0.3)), float(type.get("mass_ratio_max", 0.6)))))
		var record: Dictionary = {
			"pos": origin + Vector2(rng.randf(), rng.randf()) * chunk_size,
			"type": type,
			"required_mass": required,
			"mass_gain": maxf(1.0, round(required * maxf(0.05, float(type.get("mass_gain_ratio", 0.2))))),
			"velocity": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(
				maxf(5.0, float(_get_conf("drift_speed_min_px_sec", 28.0))),
				maxf(6.0, float(_get_conf("drift_speed_max_px_sec", 70.0)))),
			"rot_speed": deg_to_rad(rng.randf_range(-1.0, 1.0) * maxf(0.0, float(_get_conf("rotation_speed_deg_max", 25.0)))),
			"consumed": false,
			"live": false
		}
		# Variantes par prop : chasseur (oversize), fuyant (mangeable), gigogne
		# (moyen), explosif (marqué au seed — labelable).
		if required > _mass and rng.randf() <= clampf(float(_get_conf("chaser_chance", 0.0)), 0.0, 1.0):
			record["chaser"] = true
			record["chase_speed_ratio"] = rng.randf_range(
				maxf(0.3, float(_get_conf("chase_speed_ratio_min", 0.92))),
				maxf(0.4, float(_get_conf("chase_speed_ratio_max", 1.06))))
		elif required <= _mass and rng.randf() <= clampf(float(_get_conf("flee_chance", 0.0)), 0.0, 1.0):
			record["flee"] = true
		if str(type.get("id", "")) == "wreck_medium" \
			and rng.randf() <= clampf(float(_get_conf("nested_chance", 0.0)), 0.0, 1.0):
			record["nested"] = true
		if rng.randf() <= clampf(float(_get_conf("explosive_pair_chance", 0.0)), 0.0, 1.0):
			record["explosive"] = true
		(chunk["props"] as Array).append(record)
	# Pickup seedé (0-1 par chunk) : type pondéré par les <id>_pickup_chance.
	if rng.randf() <= clampf(float(_get_conf("chunk_pickup_chance", 0.22)), 0.0, 1.0):
		var total: float = 0.0
		var weights: Dictionary = {}
		for id_v in PICKUP_TINTS.keys():
			var w: float = maxf(0.0, float(_get_conf("%s_pickup_chance" % str(id_v), 0.0)))
			weights[id_v] = w
			total += w
		if total > 0.0:
			var roll: float = rng.randf() * total
			for id_v in weights:
				roll -= float(weights[id_v])
				if roll <= 0.0:
					(chunk["pickups"] as Array).append({
						"pos": origin + Vector2(rng.randf(), rng.randf()) * chunk_size,
						"id": str(id_v), "consumed": false, "live": false
					})
					break
	# Chest rare (very low chance/chunk) : équipement rare+ ou pluie de cristaux.
	if rng.randf() <= clampf(float(_get_conf("chest_chunk_chance", 0.0)), 0.0, 1.0):
		(chunk["pickups"] as Array).append({
			"pos": origin + Vector2(rng.randf(), rng.randf()) * chunk_size,
			"id": "chest", "consumed": false, "live": false
		})
	# Zone électrifiée [V8] seedée (poche fixe en monde).
	if rng.randf() <= _zone_chunk_chance:
		(chunk["zones"] as Array).append({
			"pos": origin + Vector2(rng.randf(), rng.randf()) * chunk_size,
			"radius": maxf(60.0, float(_get_conf("electric_zone_radius_px", 150.0))),
			"live": false
		})
	_chunks[coords] = chunk
	return chunk

## Streaming : instancie les records (props/pickups/zones) entrant dans l'anneau
## de spawn, dans la limite des caps. Le despawn (writeback des positions dans
## le record) est géré par les updates respectifs — rien n'est perdu.
func _tick_chunk_stream(dt: float) -> void:
	_chunk_stream_timer -= dt
	if _chunk_stream_timer > 0.0:
		return
	_chunk_stream_timer = 0.2
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var chunk_size: float = maxf(200.0, float(_get_conf("chunk_size_px", 640.0)))
	var stream_r: float = _view_radius() * maxf(0.4, float(_get_conf("spawn_ring_ratio", 1.15)))
	var cap: int = clampi(int(_get_conf("max_active_props", 20)), 1, 42)
	var min_cx: int = int(floor((_world_pos.x - stream_r) / chunk_size))
	var max_cx: int = int(floor((_world_pos.x + stream_r) / chunk_size))
	var min_cy: int = int(floor((_world_pos.y - stream_r) / chunk_size))
	var max_cy: int = int(floor((_world_pos.y + stream_r) / chunk_size))
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var chunk: Dictionary = _ensure_chunk(Vector2i(cx, cy))
			for rec_v in (chunk["props"] as Array):
				var rec: Dictionary = rec_v as Dictionary
				if bool(rec.get("consumed", false)) or bool(rec.get("live", false)) or _props.size() >= cap:
					continue
				if (rec.get("pos", Vector2.ZERO) as Vector2).distance_to(_world_pos) <= stream_r:
					_instantiate_prop_record(rec)
			for prec_v in (chunk["pickups"] as Array):
				var prec: Dictionary = prec_v as Dictionary
				if bool(prec.get("consumed", false)) or bool(prec.get("live", false)) or _pickups.size() >= 3:
					continue
				if (prec.get("pos", Vector2.ZERO) as Vector2).distance_to(_world_pos) <= stream_r:
					_instantiate_pickup_record(prec)
			for zrec_v in (chunk["zones"] as Array):
				var zrec: Dictionary = zrec_v as Dictionary
				if bool(zrec.get("live", false)):
					continue
				if (zrec.get("pos", Vector2.ZERO) as Vector2).distance_to(_world_pos) <= stream_r + float(zrec.get("radius", 150.0)):
					_instantiate_zone_record(zrec)

## Instancie un record de prop (seedé ou éphémère) en node + entry runtime.
func _instantiate_prop_record(record: Dictionary) -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var type: Dictionary = record.get("type", {})
	var size_px: float = maxf(16.0, float(type.get("size_px", 56.0)))
	var node := Node2D.new()
	node.name = "GravityProp"
	node.z_as_relative = false
	node.z_index = 10
	node.position = record.get("pos", Vector2.ZERO)
	var type_tint := Color(str(type.get("tint", "#FFFFFF")))
	node.add_child(_build_prop_visual(type, size_px))
	_world_root.add_child(node)
	var entry: Dictionary = {
		"node": node,
		"label": null,
		"record": record,
		"required_mass": float(record.get("required_mass", 1.0)),
		"mass_gain": float(record.get("mass_gain", 1.0)),
		"radius_px": size_px * 0.5,
		"velocity": record.get("velocity", Vector2.ZERO),
		"rot_speed": float(record.get("rot_speed", 0.0)),
		"state": PropState.DRIFT,
		"absorb_t": 0.0,
		"absorb_sec": 0.2,
		"start_scale": node.scale,
		"type_tint": type_tint,
		"score_base": int(type.get("score_base", 15)),
		"crystal_chance": clampf(float(type.get("crystal_chance", 0.1)), 0.0, 1.0),
		"near": false
	}
	if bool(type.get("giant", false)):
		entry["giant"] = true
	for flag in ["chaser", "flee", "nested", "explosive"]:
		if bool(record.get(flag, false)):
			entry[flag] = true
	if entry.has("chaser"):
		entry["chase_speed_ratio"] = float(record.get("chase_speed_ratio", 1.0))
		entry["chase_cd_until"] = 0.0
	if entry.has("nested"):
		_attach_nested_rim(node, size_px)
	if bool(_get_conf("prop_labels_enabled", false)):
		entry["label"] = _attach_value_label(node, float(entry["required_mass"]), size_px, int(_get_conf("value_label_font_size", 20)))
	_attach_effect_labels(entry, node, size_px)
	record["live"] = true
	_props.append(entry)
	_apply_prop_tint(entry)

## Spawn éphémère HORS SEED (garde-fou de solvabilité, tempête) : anneau autour
## du joueur, trajectoire qui traverse la zone de jeu, pas de variantes.
func _spawn_ephemeral_prop(force_absorbable: bool = false, forced_angle: float = NAN) -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var type: Dictionary = _pick_prop_type()
	if type.is_empty():
		return
	var required: float = maxf(1.0, round(_mass * randf_range(
		float(type.get("mass_ratio_min", 0.3)), float(type.get("mass_ratio_max", 0.6)))))
	if force_absorbable:
		required = maxf(1.0, round(_mass * clampf(float(_get_conf("eatable_rescue_ratio", 0.55)), 0.1, 0.9)))
	var pos: Vector2 = _ring_spawn_pos(-1.0, forced_angle)
	# Vise un point proche du joueur pour traverser la zone de jeu.
	var aim: Vector2 = _world_pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _view_radius() * 0.4
	var speed: float = randf_range(
		maxf(5.0, float(_get_conf("drift_speed_min_px_sec", 28.0))),
		maxf(6.0, float(_get_conf("drift_speed_max_px_sec", 70.0))))
	_instantiate_prop_record({
		"pos": pos,
		"type": type,
		"required_mass": required,
		"mass_gain": maxf(1.0, round(required * maxf(0.05, float(type.get("mass_gain_ratio", 0.2))))),
		"velocity": (aim - pos).normalized() * speed,
		"rot_speed": deg_to_rad(randf_range(-1.0, 1.0) * maxf(0.0, float(_get_conf("rotation_speed_deg_max", 25.0)))),
		"consumed": false,
		"live": false
	})

## Liseré doré des props gigognes (bonus interne à l'absorption).
func _attach_nested_rim(node: Node2D, size_px: float) -> void:
	var rim := Line2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(Vector2(cos(a), sin(a)) * size_px * 0.58)
	rim.points = pts
	rim.closed = true
	rim.width = 4.0
	rim.default_color = Color("#FFD866")
	node.add_child(rim)

## Comète dorée (événement) : toujours mangeable, traverse vite près du joueur.
func _spawn_comet() -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var size_px: float = maxf(30.0, float(_get_conf("comet_size_px", 90.0)))
	var angle: float = randf() * TAU
	var pos: Vector2 = _ring_spawn_pos(1.2, angle)
	var aim: Vector2 = _world_pos + Vector2.from_angle(angle + PI + randf_range(-0.4, 0.4)) * _view_radius() * 0.3
	var node := Node2D.new()
	node.name = "GravityComet"
	node.z_as_relative = false
	node.z_index = 12
	node.position = pos
	var comet_type: Dictionary = {
		"assets": _get_conf("comet_assets", []),
		"tint": "#FFD866"
	}
	node.add_child(_build_prop_visual(comet_type, size_px))
	_world_root.add_child(node)
	_props.append({
		"node": node, "label": null,
		"required_mass": 1.0,
		"mass_gain": maxf(2.0, round(_mass * maxf(0.05, float(_get_conf("comet_mass_gain_ratio", 0.35))))),
		"radius_px": size_px * 0.5,
		"velocity": (aim - pos).normalized() * maxf(120.0, float(_get_conf("comet_speed_px_sec", 420.0))),
		"rot_speed": deg_to_rad(60.0),
		"state": PropState.DRIFT, "absorb_t": 0.0, "absorb_sec": 0.2,
		"start_scale": node.scale, "type_tint": Color("#FFD866"),
		"score_base": maxi(0, int(_get_conf("comet_score", 120))),
		"crystal_chance": 0.0, "near": false, "comet": true
	})

## Noyau fragmenté (finale, chance à 80 % de l'objectif) : 3 fragments à
## absorber en ORDRE CROISSANT de taille — seul le prochain est mangeable.
func _spawn_fragments() -> void:
	_state = State.FINAL
	_next_fragment = 0
	_fragments_total = 3
	_toast("gh_fragmented_core", "FRAGMENTED CORE!", "#B455E8")
	var base_size: float = maxf(60.0, float(_get_conf("final_core_size_px", 200.0)))
	var base_angle: float = randf() * TAU
	for i in range(3):
		var size_px: float = base_size * (0.55 + 0.25 * float(i))
		var pos: Vector2 = _ring_spawn_pos(0.85, base_angle + TAU * float(i) / 3.0)
		var node := Node2D.new()
		node.name = "GravityFragment"
		node.z_as_relative = false
		node.z_index = 12
		node.position = pos
		var core_type: Dictionary = {
			"assets": _get_conf("final_core_assets", []),
			"tint": str(_get_conf("final_core_tint", "#B455E8"))
		}
		node.add_child(_build_prop_visual(core_type, size_px))
		_world_root.add_child(node)
		_props.append({
			"node": node, "label": null,
			"required_mass": 1.0 if i == 0 else 1e12, # seul le premier est mangeable
			"mass_gain": maxf(2.0, round(_mass * 0.12)),
			"radius_px": size_px * 0.5,
			"velocity": Vector2.from_angle(randf() * TAU) * 22.0,
			"rot_speed": deg_to_rad(10.0),
			"state": PropState.DRIFT, "absorb_t": 0.0, "absorb_sec": 0.35,
			"start_scale": node.scale, "type_tint": Color(str(_get_conf("final_core_tint", "#B455E8"))),
			"score_base": 60, "crystal_chance": 0.0, "near": false,
			"fragment_index": i
		})
	_retint_all_props()

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

# =============================================================================
# LABELS D'EFFETS — béquille lisibilité tant que les assets ne sont pas
# explicites : un mot ("EXPLOSIF", "FUYANT"...) affiché sur l'objet. Toggle
# GLOBAL à la racine de wave_types.json (effect_labels_enabled, applicable à
# tous les types), surchargeable par bloc de type ou par vague. À terme : off,
# le visuel de l'asset doit suffire.
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

## Un mot par variante portée par le prop (cumulables : « EXPLOSIF · CHASSEUR »).
func _attach_effect_labels(entry: Dictionary, node: Node2D, size_px: float) -> void:
	if not _effect_labels_enabled():
		return
	var texts: PackedStringArray = []
	if bool(entry.get("explosive", false)):
		texts.append(_translate_or("gh_effect_explosive", "EXPLOSIVE"))
	if bool(entry.get("flee", false)):
		texts.append(_translate_or("gh_effect_flee", "FLEEING"))
	if bool(entry.get("nested", false)):
		texts.append(_translate_or("gh_effect_nested", "NESTED"))
	if entry.has("chaser"):
		texts.append(_translate_or("gh_effect_chaser", "CHASER"))
	if texts.is_empty():
		return
	_attach_effect_label(node, " · ".join(texts), size_px, Color("#FFFFFF"))

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
	var absorbable: bool = required <= _mass or _dimension_left > 0.0
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
	_tick_effect_timers(dt)

	if _transition_follow and _transition_sprite and is_instance_valid(_transition_sprite):
		_transition_sprite.global_position = _player.global_position

	match _state:
		State.INTRO, State.OUTRO:
			pass
		State.RUN:
			_run_elapsed += minf(delta, 0.25)
			_tick_movement(dt)
			_tick_mass_decay(dt)
			_tick_chunk_stream(dt)
			_tick_storm_spawner(dt)
			_tick_solvability(dt)
			_tick_event_scheduler(dt)
			_tick_objective()
			if _run_elapsed >= _run_duration:
				_begin_outro()
		State.FINAL:
			_run_elapsed += minf(delta, 0.25)
			_tick_movement(dt)
			_tick_chunk_stream(dt)
			_tick_solvability(dt)
			if _run_elapsed >= _run_duration:
				_begin_outro()

	_update_world_transform()
	_update_bg_tiles()
	_update_countdown_label()
	_update_progress_label()
	_update_props(dt)
	_update_pickups(dt)
	_update_zones(dt)
	_update_rival(dt)
	_update_companion(dt)
	_update_stabilizer_visual(dt)
	if _state == State.RUN or _state == State.FINAL:
		_check_contacts()
		_check_explosive_pairs(dt)
	_update_arrow()

func _tick_effect_timers(dt: float) -> void:
	_magnet_left = maxf(0.0, _magnet_left - dt)
	_compass_left = maxf(0.0, _compass_left - dt)
	_overdrive_left = maxf(0.0, _overdrive_left - dt)
	_inversion_left = maxf(0.0, _inversion_left - dt)
	_storm_left = maxf(0.0, _storm_left - dt)
	if _companion_left > 0.0:
		_companion_left -= dt
		if _companion_left <= 0.0 and _companion_node and is_instance_valid(_companion_node):
			_companion_node.queue_free()
			_companion_node = null
	if _rival_left > 0.0:
		_rival_left -= dt
		if _rival_left <= 0.0 and _rival_node and is_instance_valid(_rival_node):
			var fade: Tween = _rival_node.create_tween()
			fade.tween_property(_rival_node, "modulate:a", 0.0, 0.4)
			fade.tween_callback(_rival_node.queue_free)
			_rival_node = null
	if _dimension_left > 0.0:
		_dimension_left -= dt
		if _dimension_left <= 0.0:
			_end_bonus_dimension()

## Masse fondante [V11] : décroissance passive (Agar.io ~0.2 %/s), jamais sous
## la masse de départ.
func _tick_mass_decay(dt: float) -> void:
	var decay: float = maxf(0.0, float(_get_conf("mass_decay_percent_per_sec", 0.0)))
	if decay <= 0.0 or _mass <= _start_mass:
		return
	_mass = maxf(_start_mass, _mass * (1.0 - decay * 0.01 * dt))
	_radius = _compute_radius()
	_push_player_state()

## Tempête dérivante [E20] : en plus du drift x2, saupoudre des props éphémères
## (le monde seedé n'a pas de spawner continu — la tempête en réintroduit un
## temporaire, cadence resserrée par storm_spawn_mult).
func _tick_storm_spawner(dt: float) -> void:
	if _storm_left <= 0.0:
		return
	_storm_spawn_timer -= dt
	if _storm_spawn_timer > 0.0:
		return
	_storm_spawn_timer = maxf(0.3, float(_get_conf("storm_ephemeral_interval_sec", 1.5)) \
		/ maxf(1.0, float(_get_conf("storm_spawn_mult", 1.5))))
	var cap: int = clampi(int(_get_conf("max_active_props", 20)), 1, 42)
	if _props.size() < cap:
		_spawn_ephemeral_prop()

## Garde-fou de solvabilité (en monde) : si aucun prop absorbable n'est VISIBLE
## pendant no_target_grace_sec, convertir le plus petit visible ; écran vide →
## deux spawns absorbables forcés de directions opposées. La flèche (§arrow)
## prend le relais pour guider vers les mangeables lointains.
func _tick_solvability(dt: float) -> void:
	_solvability_timer -= dt
	if _solvability_timer > 0.0:
		return
	_solvability_timer = 0.25
	var visible_count: int = 0
	var has_target: bool = false
	var smallest: Dictionary = {}
	var smallest_required: float = INF
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT or entry.has("fragment_index"):
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		if not _is_on_screen((node_v as Node2D).position):
			continue
		visible_count += 1
		var required: float = float(entry.get("required_mass", 0.0))
		if required <= _mass:
			has_target = true
			continue
		if required < smallest_required:
			smallest_required = required
			smallest = entry
	_clear_screen_peak = maxi(_clear_screen_peak, visible_count)
	if has_target or _state == State.FINAL:
		_no_target_timer = 0.0
		return
	_no_target_timer += 0.25
	if _no_target_timer < maxf(0.25, float(_get_conf("no_target_grace_sec", 1.2))):
		return
	_no_target_timer = 0.0
	if visible_count == 0:
		var a: float = randf() * TAU
		_spawn_ephemeral_prop(true, a)
		_spawn_ephemeral_prop(true, a + PI)
		return
	# Rescue: shrink the smallest visible prop below the current mass.
	if not smallest.is_empty():
		var rescued: float = maxf(1.0, round(_mass * clampf(float(_get_conf("eatable_rescue_ratio", 0.55)), 0.1, 0.9)))
		smallest["required_mass"] = rescued
		smallest["mass_gain"] = maxf(1.0, round(rescued * maxf(0.05, float(_get_conf("eatable_rescue_gain_ratio", 0.25)))))
		smallest.erase("chaser")
		smallest["chasing"] = false
		_apply_prop_tint(smallest)
		var node_v: Variant = smallest.get("node", null)
		if VFXManager and node_v is Node2D and is_instance_valid(node_v):
			VFXManager.flash_sprite(node_v as Node2D, Color(1.0, 1.0, 1.0), 0.18)

## Objectif de taille : fragments à 80 % (chance, une fois), sinon fin simple.
func _tick_objective() -> void:
	if _target_reached:
		return
	if not _fragment_roll_done and _mass >= _target_mass * 0.8:
		_fragment_roll_done = true
		if randf() <= clampf(float(_get_conf("fragmented_core_chance", 0.35)), 0.0, 1.0):
			_spawn_fragments()
			return
	if _mass >= _target_mass:
		_on_target_reached(1.0)

func _on_target_reached(jackpot_mult: float) -> void:
	if _target_reached:
		return
	_target_reached = true
	_toast("gh_target_reached", "TARGET REACHED!", "#7CFC9A")
	if _game and is_instance_valid(_game):
		if _game.has_method("spawn_reward_crystals_from_top"):
			_game.call("spawn_reward_crystals_from_top",
				maxi(1, int(round(float(_get_conf("target_crystals", 8)) * jackpot_mult))))
		var score: int = int(round(float(_get_conf("target_score", 1500)) * _reward_mult * jackpot_mult))
		if score > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", score, _screen_center())
	if VFXManager:
		VFXManager.screen_shake(7.0, 0.3)
	_begin_outro()

func _update_props(dt: float) -> void:
	var pull: float = maxf(0.0, float(_get_conf("attract_pull_px_sec", 150.0)))
	if _magnet_left > 0.0:
		pull *= maxf(1.0, float(_get_conf("magnet_pull_mult", 2.0)))
	var pull_radius: float = _radius * (maxf(1.0, float(_get_conf("overdrive_radius_mult", 2.0))) if _overdrive_left > 0.0 else 1.0)
	var near_hz: float = maxf(0.05, float(_get_conf("near_pulse_hz", 1.6)))
	var spin: float = deg_to_rad(maxf(0.0, float(_get_conf("absorb_spin_deg_sec", 320.0))))
	var storm_mult: float = maxf(1.0, float(_get_conf("storm_drift_mult", 2.0))) if _storm_left > 0.0 else 1.0
	var despawn_dist: float = _view_radius() * maxf(1.3, float(_get_conf("despawn_ring_ratio", 2.2)))
	var chase_detect: float = maxf(50.0, float(_get_conf("chase_detect_radius_px", 520.0)))
	var flee_detect: float = maxf(30.0, float(_get_conf("flee_detect_radius_px", 300.0)))
	var player_speed: float = _current_speed()
	var chasers_active: int = 0
	for entry in _props:
		if bool(entry.get("chasing", false)):
			chasers_active += 1
	var max_chasers: int = maxi(0, int(_get_conf("max_concurrent_chasers", 2)))
	for i in range(_props.size() - 1, -1, -1):
		var entry: Dictionary = _props[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_props.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D

		if int(entry.get("state", PropState.DRIFT)) == PropState.ABSORBING:
			# Suction animation toward the live ship WORLD position, then gone.
			var t: float = float(entry.get("absorb_t", 0.0)) + dt / maxf(0.05, float(entry.get("absorb_sec", 0.2)))
			entry["absorb_t"] = t
			if t >= 1.0:
				node.queue_free()
				_props.remove_at(i)
				continue
			node.position = node.position.lerp(_world_pos, clampf(t * t + dt * 6.0, 0.0, 1.0))
			node.scale = (entry.get("start_scale", Vector2.ONE) as Vector2) * (1.0 - t)
			node.rotation += spin * dt
			continue

		var required: float = float(entry.get("required_mass", 0.0))
		var dist: float = node.position.distance_to(_world_pos)
		var absorbable: bool = required <= _mass or _dimension_left > 0.0

		# Chasseur : les gros poursuivent 6-12 s puis lâchent l'affaire.
		if entry.has("chaser") and not absorbable and _inversion_left <= 0.0 and _dimension_left <= 0.0:
			if bool(entry.get("chasing", false)):
				if _time >= float(entry.get("chase_until", 0.0)):
					entry["chasing"] = false
					entry["chase_cd_until"] = _time + maxf(1.0, float(_get_conf("chase_cooldown_sec", 8.0)))
					entry["velocity"] = (node.position - _world_pos).normalized() \
						* maxf(20.0, float(_get_conf("drift_speed_min_px_sec", 28.0)))
				else:
					entry["velocity"] = (_world_pos - node.position).normalized() \
						* player_speed * float(entry.get("chase_speed_ratio", 1.0))
			elif chasers_active < max_chasers and dist < chase_detect \
				and _time >= float(entry.get("chase_cd_until", 0.0)):
				entry["chasing"] = true
				chasers_active += 1
				entry["chase_until"] = _time + randf_range(
					maxf(1.0, float(_get_conf("chase_min_sec", 6.0))),
					maxf(2.0, float(_get_conf("chase_max_sec", 12.0))))
				if VFXManager:
					VFXManager.spawn_floating_text(_world_to_screen(node.position) + Vector2(0.0, -40.0),
						_translate_or("gh_chase", "CHASE!"), Color("#E8553B"), self)
		# Fuyant : le mangeable accélère en s'éloignant du vaisseau proche.
		elif bool(entry.get("flee", false)) and absorbable and dist < flee_detect and dist > 1.0:
			var away: Vector2 = (node.position - _world_pos).normalized()
			var flee_speed: float = maxf(20.0, float(_get_conf("drift_speed_max_px_sec", 70.0))) \
				* maxf(1.0, float(_get_conf("flee_boost_mult", 1.8)))
			entry["velocity"] = (entry.get("velocity", Vector2.ZERO) as Vector2).lerp(away * flee_speed, clampf(dt * 4.0, 0.0, 1.0))

		node.position += (entry.get("velocity", Vector2.ZERO) as Vector2) * storm_mult * dt
		node.rotation += float(entry.get("rot_speed", 0.0)) * dt
		# Attraction visible (ou répulsion pendant l'inversion).
		if _inversion_left > 0.0 and dist < pull_radius * 2.0 and dist > 1.0:
			node.position += (node.position - _world_pos).normalized() * pull * dt
		elif absorbable and dist < pull_radius and dist > 1.0:
			var strength: float = pull * (1.0 - dist / pull_radius)
			node.position += (_world_pos - node.position).normalized() * strength * dt
		# Near-absorbable tension pulse (no tween: cheap sine on modulate).
		if bool(entry.get("near", false)):
			var factor: float = 0.35 + 0.35 * (0.5 + 0.5 * sin(_time * TAU * near_hz))
			var type_tint: Color = entry.get("type_tint", Color.WHITE)
			node.modulate = type_tint * Color.WHITE.lerp(Color(str(_get_conf("color_near", "#F2E45B"))), factor)
		# Highlight compass : le plus petit mangeable pulse doré.
		if _compass_left > 0.0 and absorbable and entry == _find_arrow_target():
			node.modulate = Color("#FFD866")

		# Despawn en monde : trop loin du joueur (les fragments ne despawnent
		# pas). Writeback du record seedé : l'objet reste LÀ où il a dérivé et
		# sera retrouvé si le joueur revient dans la zone (persistance).
		if dist > despawn_dist and not entry.has("fragment_index"):
			var rec_v: Variant = entry.get("record", null)
			if rec_v is Dictionary:
				(rec_v as Dictionary)["pos"] = node.position
				(rec_v as Dictionary)["velocity"] = entry.get("velocity", Vector2.ZERO)
				(rec_v as Dictionary)["live"] = false
			node.queue_free()
			_props.remove_at(i)

func _check_contacts() -> void:
	var capture_ratio: float = clampf(float(_get_conf("capture_ratio", 0.82)), 0.3, 1.0)
	for i in range(_props.size() - 1, -1, -1):
		var entry: Dictionary = _props[i]
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT:
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var dist: float = (node_v as Node2D).position.distance_to(_world_pos)
		# Fragments : seul le prochain (ordre croissant) est tangible.
		if entry.has("fragment_index"):
			if int(entry.get("fragment_index", 0)) != _next_fragment:
				continue
			if dist <= _radius * capture_ratio + float(entry.get("radius_px", 30.0)) * 0.4:
				_begin_absorb_prop(entry)
			continue
		var absorbable: bool = float(entry.get("required_mass", 0.0)) <= _mass or _dimension_left > 0.0
		if absorbable:
			if dist <= _radius * capture_ratio:
				_begin_absorb_prop(entry)
		else:
			if dist <= _radius * capture_ratio + float(entry.get("radius_px", 30.0)) * 0.4:
				_oversize_contact(entry, node_v as Node2D)

## Props explosifs [V9] : marqués au SEED (labelables) — un prop explosif qui
## touche un autre oversize part en grappe de petits mangeables (scan espacé).
func _check_explosive_pairs(dt: float) -> void:
	_explosive_check_timer -= dt
	if _explosive_check_timer > 0.0:
		return
	_explosive_check_timer = 0.4
	var oversize: Array = []
	var any_explosive: bool = false
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT or entry.has("fragment_index"):
			continue
		if float(entry.get("required_mass", 0.0)) > _mass:
			var node_v: Variant = entry.get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				oversize.append(entry)
				any_explosive = any_explosive or bool(entry.get("explosive", false))
	if not any_explosive:
		return
	for a_idx in range(oversize.size()):
		for b_idx in range(a_idx + 1, oversize.size()):
			var ea: Dictionary = oversize[a_idx]
			var eb: Dictionary = oversize[b_idx]
			if not (bool(ea.get("explosive", false)) or bool(eb.get("explosive", false))):
				continue
			var na: Node2D = ea.get("node")
			var nb: Node2D = eb.get("node")
			if na.position.distance_to(nb.position) > float(ea.get("radius_px", 30.0)) + float(eb.get("radius_px", 30.0)):
				continue
			var center: Vector2 = (na.position + nb.position) * 0.5
			if VFXManager:
				VFXManager.spawn_explosion(_world_to_screen(center), 90.0, Color(1.0, 0.6, 0.3), self,
					"", "res://assets/vfx/boss_explosion.tres", -1.0, 0.3, 0.5, false)
			_remove_prop_entry(ea)
			_remove_prop_entry(eb)
			var shards: int = maxi(2, int(_get_conf("explosive_shard_count", 5)))
			for s in range(shards):
				_spawn_shard(center + Vector2.from_angle(TAU * float(s) / float(shards)) * 40.0)
			return # une seule paire par scan

func _remove_prop_entry(entry: Dictionary) -> void:
	var rec_v: Variant = entry.get("record", null)
	if rec_v is Dictionary:
		(rec_v as Dictionary)["consumed"] = true # détruit = ne réapparaît jamais
	var node_v: Variant = entry.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	_props.erase(entry)

## Petit mangeable issu d'une explosion ou du champ d'astéroïdes.
func _spawn_shard(world_pos: Vector2) -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var size_px: float = 40.0
	var required: float = maxf(1.0, round(_mass * randf_range(0.25, 0.5)))
	var node := Node2D.new()
	node.name = "GravityShard"
	node.z_as_relative = false
	node.z_index = 10
	node.position = world_pos
	var shard_type: Dictionary = {}
	var props_v: Variant = _get_conf("props", [])
	if props_v is Array and not (props_v as Array).is_empty():
		shard_type = (props_v as Array)[0] as Dictionary
	node.add_child(_build_prop_visual(shard_type, size_px))
	_world_root.add_child(node)
	var entry: Dictionary = {
		"node": node, "label": null,
		"required_mass": required,
		"mass_gain": maxf(1.0, round(required * maxf(0.05, float(shard_type.get("mass_gain_ratio", 0.22))))),
		"radius_px": size_px * 0.5,
		"velocity": Vector2.from_angle(randf() * TAU) * randf_range(20.0, 60.0),
		"rot_speed": deg_to_rad(randf_range(-25.0, 25.0)),
		"state": PropState.DRIFT, "absorb_t": 0.0, "absorb_sec": 0.15,
		"start_scale": node.scale, "type_tint": Color(str(shard_type.get("tint", "#FFFFFF"))),
		"score_base": int(shard_type.get("score_base", 15)),
		"crystal_chance": clampf(float(shard_type.get("crystal_chance", 0.08)), 0.0, 1.0),
		"near": false
	}
	_props.append(entry)
	_apply_prop_tint(entry)

## Rewards apply at animation START (no double trigger); the entry then plays
## its suction animation in _update_props and frees itself.
func _begin_absorb_prop(entry: Dictionary) -> void:
	entry["state"] = PropState.ABSORBING
	entry["absorb_t"] = 0.0
	var rec_v: Variant = entry.get("record", null)
	if rec_v is Dictionary:
		(rec_v as Dictionary)["consumed"] = true # mangé = mangé pour toujours
	var size_px: float = float(entry.get("radius_px", 28.0)) * 2.0
	entry["absorb_sec"] = remap(clampf(size_px, 40.0, 200.0), 40.0, 200.0,
		maxf(0.05, float(_get_conf("absorb_min_sec", 0.12))),
		maxf(0.06, float(_get_conf("absorb_max_sec", 0.35))))
	var node_v: Variant = entry.get("node", null)
	var at_screen: Vector2 = _screen_center()
	if node_v is Node2D and is_instance_valid(node_v):
		at_screen = _world_to_screen((node_v as Node2D).position)
		entry["start_scale"] = (node_v as Node2D).scale
	var label_v: Variant = entry.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).visible = false

	var gain: float = float(entry.get("mass_gain", 1.0))
	# Gigogne [V10] : bonus interne — cristal garanti OU gain de masse x2.
	if bool(entry.get("nested", false)):
		if randf() < 0.5:
			gain *= maxf(1.0, float(_get_conf("nested_mass_mult", 2.0)))
			if VFXManager:
				VFXManager.spawn_floating_text(at_screen + Vector2(0.0, -40.0), "x2", Color("#FFD866"), self)
		elif _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_screen,
				{"force_magnet_after_sec": maxf(0.2, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))})
	_gain_mass(gain)
	if _player.has_method("pulse_gravity_hole_aura"):
		_player.call("pulse_gravity_hole_aura")

	if _game and is_instance_valid(_game):
		var score: int = int(round(float(entry.get("score_base", 0)) * _reward_mult))
		if score > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", score, at_screen)
		if bool(entry.get("comet", false)):
			if _game.has_method("spawn_reward_crystal_at"):
				for c in range(maxi(1, int(_get_conf("comet_crystals", 4)))):
					_game.call("spawn_reward_crystal_at",
						at_screen + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0)),
						{"force_magnet_after_sec": 1.0})
		elif randf() <= float(entry.get("crystal_chance", 0.0)) and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", at_screen,
				{"force_magnet_after_sec": maxf(0.2, float(_get_conf("crystal_force_magnet_after_sec", 2.0)))})

	# Noyau fragmenté : ordre croissant, le suivant devient mangeable.
	if entry.has("fragment_index"):
		_next_fragment += 1
		if VFXManager:
			VFXManager.spawn_floating_text(at_screen + Vector2(0.0, -50.0),
				_translate_or("gh_fragment", "FRAGMENT!"), Color("#B455E8"), self)
		if _next_fragment >= _fragments_total:
			_on_target_reached(1.5)
		else:
			for other in _props:
				if int((other as Dictionary).get("fragment_index", -1)) == _next_fragment:
					other["required_mass"] = 1.0
					_apply_prop_tint(other)
		return

	_check_clear_screen()

## Clear screen [E19] : absorber 100 % des props visibles à un instant (après
## un écran raisonnablement peuplé) = pluie de cristaux.
func _check_clear_screen() -> void:
	if _time - _last_clear_screen < 12.0 or _clear_screen_peak < 3:
		return
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT:
			continue
		var node_v: Variant = entry.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v) and _is_on_screen((node_v as Node2D).position):
			return
	_last_clear_screen = _time
	_clear_screen_peak = 0
	_toast("gh_clear_screen", "CLEAR SCREEN!", "#7CFC9A")
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", maxi(1, int(_get_conf("clear_screen_crystals", 4))))

## Touching a too-big structure hurts (shield first, never lethal by default),
## sheds flat mass, knocks the WORLD position back and deflects the prop away.
## Le stabilisateur (pickup) annule un contact.
func _oversize_contact(entry: Dictionary, node: Node2D) -> void:
	if _oversize_cooldown > 0.0:
		return
	_oversize_cooldown = maxf(0.2, float(_get_conf("oversize_contact_cooldown_sec", 1.0)))
	var dir_away: Vector2 = (_world_pos - node.position).normalized()
	if dir_away == Vector2.ZERO:
		dir_away = Vector2.DOWN
	# Stabilisateur : annule ce contact (dégâts + perte de masse), défléchit.
	if _stabilizer_charges > 0:
		_stabilizer_charges -= 1
		_update_stabilizer_node()
		entry["velocity"] = -dir_away * maxf((entry.get("velocity", Vector2.ZERO) as Vector2).length(), 40.0)
		if VFXManager:
			VFXManager.spawn_impact(_screen_center(), 30.0, self)
			VFXManager.spawn_floating_text(_screen_center() + Vector2(0.0, -70.0),
				_translate_or("gh_stabilizer_used", "STABILIZED!"), Color("#7FE58C"), self)
		return
	var dmg_mult: float = maxf(1.0, float(_get_conf("giant_damage_mult", 2.0))) if bool(entry.get("giant", false)) else 1.0
	if _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		var pct: float = clampf(float(_get_conf("oversize_contact_damage_percent", 0.12)) * dmg_mult, 0.0, 1.0)
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
	# Knockback : c'est le MONDE qui encaisse (le vaisseau reste au centre).
	_world_pos += dir_away * maxf(0.0, float(_get_conf("oversize_knockback_px", 80.0)))
	# Deflect the prop so it leaves the contact zone instead of grinding.
	var vel: Vector2 = entry.get("velocity", Vector2.ZERO)
	entry["velocity"] = -dir_away * maxf(vel.length(), 20.0)
	entry["chasing"] = false
	entry["chase_cd_until"] = _time + maxf(1.0, float(_get_conf("chase_cooldown_sec", 8.0)))
	if VFXManager:
		VFXManager.flash_sprite(_player, Color(1.0, 0.35, 0.3), 0.25)
		VFXManager.screen_shake(6.0, 0.25)
	_retint_all_props()

# =============================================================================
# PICKUPS (magnet / compass / surcharge / compagnon / stabilisateur) — seedés
# par chunk, instanciés par le streaming.
# =============================================================================

func _instantiate_pickup_record(record: Dictionary) -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var pickup_id: String = str(record.get("id", ""))
	var size_px: float = maxf(24.0, float(_get_conf("pickup_size_px", 64.0)))
	if pickup_id == "chest":
		size_px = maxf(24.0, float(_get_conf("chest_size_px", 84.0)))
	var node := Node2D.new()
	node.name = "GravityPickup"
	node.z_as_relative = false
	node.z_index = 13
	node.position = record.get("pos", Vector2.ZERO)
	var tint := Color(str(PICKUP_TINTS.get(pickup_id, "#FFFFFF")))
	var asset_visual: Node2D = _build_sprite_fit(str(_get_conf("%s_pickup_asset" % pickup_id, "")), size_px)
	if asset_visual != null:
		node.add_child(asset_visual)
	else:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		circle.polygon = pts
		circle.color = Color(tint.r, tint.g, tint.b, 0.9)
		node.add_child(circle)
		var glyph := Label.new()
		glyph.text = str(PICKUP_GLYPHS.get(pickup_id, "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(size_px * 0.5))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(size_px, size_px)
		glyph.position = -Vector2(size_px, size_px) * 0.5
		node.add_child(glyph)
	if _effect_labels_enabled():
		_attach_effect_label(node, _translate_or("gh_pickup_%s" % pickup_id, pickup_id.to_upper()), size_px, tint)
	_world_root.add_child(node)
	record["live"] = true
	_pickups.append({ "node": node, "id": pickup_id, "pulse": randf() * TAU, "record": record })

func _update_pickups(_dt: float) -> void:
	if _pickups.is_empty():
		return
	# Contre-zoom : les pickups/chest gardent une TAILLE ÉCRAN constante quand
	# le monde dézoome (sinon invisibles à haute masse) — grab aligné dessus.
	var counter: float = (1.0 / maxf(0.05, _zoom)) if bool(_get_conf("pickup_counter_zoom", true)) else 1.0
	var reach: float = _radius + maxf(20.0, float(_get_conf("pickup_grab_radius_px", 70.0))) * counter
	var despawn_dist: float = _view_radius() * maxf(1.3, float(_get_conf("despawn_ring_ratio", 2.2)))
	for i in range(_pickups.size() - 1, -1, -1):
		var entry: Dictionary = _pickups[i]
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.scale = Vector2.ONE * counter * (1.0 + sin(_time * TAU * 1.4 + float(entry.get("pulse", 0.0))) * 0.12)
		var dist: float = node.position.distance_to(_world_pos)
		if dist <= reach and (_state == State.RUN or _state == State.FINAL):
			var rec_v: Variant = entry.get("record", null)
			if rec_v is Dictionary:
				(rec_v as Dictionary)["consumed"] = true
			_apply_pickup(str(entry.get("id", "")), _world_to_screen(node.position))
			node.queue_free()
			_pickups.remove_at(i)
		elif dist > despawn_dist:
			# Writeback : le pickup reste dans le monde, retrouvable au retour.
			var rec2_v: Variant = entry.get("record", null)
			if rec2_v is Dictionary:
				(rec2_v as Dictionary)["live"] = false
			node.queue_free()
			_pickups.remove_at(i)

func _apply_pickup(pickup_id: String, at_screen: Vector2) -> void:
	match pickup_id:
		"magnet":
			_magnet_left = maxf(1.0, float(_get_conf("magnet_duration_sec", 6.0)))
		"compass":
			_compass_left = maxf(1.0, float(_get_conf("compass_duration_sec", 8.0)))
		"overdrive":
			_overdrive_left = maxf(1.0, float(_get_conf("overdrive_duration_sec", 8.0)))
		"companion":
			_companion_left = maxf(1.0, float(_get_conf("companion_duration_sec", 10.0)))
			_spawn_companion()
		"stabilizer":
			_stabilizer_charges = mini(_stabilizer_charges + 1, 2)
			_update_stabilizer_node()
		"chest":
			_open_chest(at_screen)
	if VFXManager:
		VFXManager.spawn_floating_text(at_screen + Vector2(0.0, -40.0),
			_translate_or("gh_pickup_%s" % pickup_id, pickup_id.to_upper()),
			Color(str(PICKUP_TINTS.get(pickup_id, "#FFFFFF"))), self)
		VFXManager.flash_sprite(_player, Color(1.0, 1.0, 1.0), 0.15)

## Chest rare [13 juillet 2026] : toast central + score, puis soit un
## ÉQUIPEMENT rare+ (pipeline LootDrop de Game → inventaire + toast haut-droite
## du HUD, comme en story), soit une pluie de cristaux. Seule exception au
## « pas de drops d'équipement » du mode.
func _open_chest(at_screen: Vector2) -> void:
	_toast("gh_chest_found", "CHEST FOUND!", "#FFD866")
	if _game == null or not is_instance_valid(_game):
		return
	var score: int = int(round(float(_get_conf("chest_score", 250)) * _reward_mult))
	if score > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", score, at_screen)
	if randf() <= clampf(float(_get_conf("chest_item_chance", 0.5)), 0.0, 1.0) \
		and _game.has_method("spawn_reward_equipment_at"):
		_game.call("spawn_reward_equipment_at", at_screen,
			maxf(0.1, float(_get_conf("chest_quality_mult", 1.0))), {
				"auto_collect_delay_sec": 1.2,
				"auto_collect_speed_px_sec": 950.0
			}, _pick_chest_rarity())
	elif _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", maxi(1, int(_get_conf("chest_crystals", 10))))

func _pick_chest_rarity() -> String:
	var weights_v: Variant = _get_conf("chest_rarity_weights", {})
	var weights: Dictionary = (weights_v as Dictionary) if weights_v is Dictionary else {}
	if weights.is_empty():
		weights = { "rare": 70.0, "epic": 22.0, "legendary": 7.0, "unique": 1.0 }
	var total: float = 0.0
	for key in weights:
		total += maxf(0.0, float(weights[key]))
	if total <= 0.0:
		return "rare"
	var roll: float = randf() * total
	for key in weights:
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return str(key)
	return "rare"

## Mini-trou compagnon : vortex autonome qui orbite le joueur et mange les
## props minuscules (gains reversés au joueur, ÷2).
func _spawn_companion() -> void:
	if _companion_node and is_instance_valid(_companion_node):
		return
	if _world_root == null or not is_instance_valid(_world_root):
		return
	_companion_node = Node2D.new()
	_companion_node.name = "GravityCompanion"
	_companion_node.z_as_relative = false
	_companion_node.z_index = 12
	var size_px: float = maxf(24.0, float(_get_conf("companion_size_px", 70.0)))
	var visual: Node2D = _build_sprite_fit(str(_get_conf("companion_asset", str(_get_conf("aura_asset", "")))), size_px)
	if visual == null:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		circle.polygon = pts
		circle.color = Color("#2A1848C8")
		visual = circle
	_companion_node.add_child(visual)
	_world_root.add_child(_companion_node)

func _update_companion(dt: float) -> void:
	if _companion_node == null or not is_instance_valid(_companion_node):
		return
	_companion_angle += dt * TAU / maxf(1.0, float(_get_conf("companion_orbit_sec", 5.0)))
	var orbit: float = maxf(60.0, float(_get_conf("companion_orbit_radius_px", 200.0)))
	_companion_node.position = _world_pos + Vector2.from_angle(_companion_angle) * orbit
	var eat_radius: float = maxf(20.0, float(_get_conf("companion_eat_radius_px", 70.0)))
	var max_ratio: float = clampf(float(_get_conf("companion_max_mass_ratio", 0.3)), 0.05, 1.0)
	for i in range(_props.size() - 1, -1, -1):
		var entry: Dictionary = _props[i]
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT or entry.has("fragment_index"):
			continue
		if float(entry.get("required_mass", 0.0)) > _mass * max_ratio:
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		if (node_v as Node2D).position.distance_to(_companion_node.position) <= eat_radius:
			if VFXManager:
				VFXManager.spawn_impact(_world_to_screen((node_v as Node2D).position), 14.0, self)
			_gain_mass(float(entry.get("mass_gain", 1.0)) * 0.5)
			_remove_prop_entry(entry)

## Orbe stabilisateur en orbite ÉCRAN autour du vaisseau (indication de charge).
func _update_stabilizer_node() -> void:
	if _stabilizer_charges <= 0:
		if _stabilizer_node and is_instance_valid(_stabilizer_node):
			_stabilizer_node.queue_free()
		_stabilizer_node = null
		return
	if _stabilizer_node and is_instance_valid(_stabilizer_node):
		return
	_stabilizer_node = Node2D.new()
	_stabilizer_node.name = "GravityStabilizer"
	_stabilizer_node.z_as_relative = false
	_stabilizer_node.z_index = 40
	var orb := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(14):
		var a: float = TAU * float(k) / 14.0
		pts.append(Vector2(cos(a), sin(a)) * 12.0)
	orb.polygon = pts
	orb.color = Color("#7FE58C")
	_stabilizer_node.add_child(orb)
	add_child(_stabilizer_node)

func _update_stabilizer_visual(_dt: float) -> void:
	if _stabilizer_node == null or not is_instance_valid(_stabilizer_node):
		return
	_stabilizer_node.position = _screen_center() \
		+ Vector2.from_angle(_time * TAU / 2.6) * maxf(30.0, float(_get_conf("stabilizer_orbit_px", 70.0)))

# =============================================================================
# ZONES ÉLECTRIFIÉES [V8] (poches fixes en monde, seedées par chunk)
# =============================================================================

func _instantiate_zone_record(record: Dictionary) -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	var pos: Vector2 = record.get("pos", Vector2.ZERO)
	var zone_radius: float = maxf(60.0, float(record.get("radius", 150.0)))
	var node := Node2D.new()
	node.name = "GravityElectricZone"
	node.z_as_relative = false
	node.z_index = 8
	node.position = pos
	var asset_visual: Node2D = _build_sprite_fit(str(_get_conf("electric_zone_asset", "")), zone_radius * 2.0)
	if asset_visual != null:
		node.add_child(asset_visual)
	else:
		var fill := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(24):
			var a: float = TAU * float(k) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * zone_radius)
		fill.polygon = pts
		fill.color = Color("#5CE8FF22")
		node.add_child(fill)
		var ring := Line2D.new()
		ring.points = pts
		ring.closed = true
		ring.width = 4.0
		ring.default_color = Color("#5CE8FFAA")
		node.add_child(ring)
	if _effect_labels_enabled():
		_attach_effect_label(node, _translate_or("gh_effect_electric", "ELECTRIFIED"), 0.0, Color("#5CE8FF"))
	_world_root.add_child(node)
	record["live"] = true
	_zones.append({ "node": node, "pos": pos, "radius": zone_radius, "tick_timer": 0.0, "record": record })

func _update_zones(dt: float) -> void:
	if _zones.is_empty() or not (_state == State.RUN or _state == State.FINAL):
		return
	var tick_interval: float = maxf(0.2, float(_get_conf("electric_tick_interval_sec", 0.5)))
	var despawn_dist: float = _view_radius() * maxf(1.3, float(_get_conf("despawn_ring_ratio", 2.2)))
	# Contre-zoom : la zone garde une TAILLE ÉCRAN constante (visuel ET rayon de
	# danger, cohérents) — sinon elle devient invisible/inutile à haute masse.
	var counter: float = (1.0 / maxf(0.05, _zoom)) if bool(_get_conf("zone_counter_zoom", true)) else 1.0
	for i in range(_zones.size() - 1, -1, -1):
		var zone: Dictionary = _zones[i]
		var zone_radius: float = float(zone.get("radius", 150.0)) * counter
		var node_v: Variant = zone.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).modulate.a = 0.7 + 0.3 * sin(_time * TAU * 1.2)
			(node_v as Node2D).scale = Vector2.ONE * counter
		var zone_dist: float = _world_pos.distance_to(zone.get("pos", Vector2.ZERO))
		# Despawn/writeback : la zone (fixe) sera retrouvée au retour.
		if zone_dist > despawn_dist + zone_radius:
			var rec_v: Variant = zone.get("record", null)
			if rec_v is Dictionary:
				(rec_v as Dictionary)["live"] = false
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_zones.remove_at(i)
			continue
		if zone_dist > zone_radius:
			zone["tick_timer"] = 0.0
			continue
		zone["tick_timer"] = float(zone.get("tick_timer", 0.0)) - dt
		if float(zone["tick_timer"]) > 0.0:
			continue
		zone["tick_timer"] = tick_interval
		if _player.has_method("take_damage"):
			var max_hp_v: Variant = _player.get("max_hp")
			var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
			var pct: float = clampf(float(_get_conf("electric_tick_damage_percent", 0.04)), 0.0, 1.0)
			var dmg: int = maxi(1, int(ceil(float(max_hp) * pct)))
			if bool(_get_conf("oversize_never_lethal", true)):
				var hp_v: Variant = _player.get("current_hp")
				var current_hp: int = int(hp_v) if (hp_v is int or hp_v is float) else max_hp
				dmg = mini(dmg, maxi(0, current_hp - 1))
			if dmg > 0:
				_player.call("take_damage", dmg)
				if VFXManager:
					VFXManager.flash_sprite(_player, Color(0.5, 0.9, 1.0), 0.15)

# =============================================================================
# ÉVÉNEMENTS (toasts centraux)
# =============================================================================

func _any_event_active() -> bool:
	return _rival_left > 0.0 or _inversion_left > 0.0 or _storm_left > 0.0 or _dimension_left > 0.0

func _tick_event_scheduler(dt: float) -> void:
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(
		maxf(5.0, float(_get_conf("event_interval_sec_min", 20.0))),
		maxf(5.0, float(_get_conf("event_interval_sec_max", 35.0))))
	if _any_event_active() or _state != State.RUN:
		return
	var weights: Dictionary = {
		"asteroids": float(_get_conf("asteroid_field_weight", 25.0)),
		"rival": float(_get_conf("rival_weight", 15.0)),
		"comet": float(_get_conf("comet_weight", 20.0)),
		"inversion": float(_get_conf("inversion_weight", 15.0)),
		"dimension": float(_get_conf("bonus_dimension_weight", 10.0)),
		"storm": float(_get_conf("storm_weight", 15.0))
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
	var picked: String = ""
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			picked = str(key)
			break
	if picked == "":
		return
	_last_event_id = picked
	_trigger_event(picked)

func _trigger_event(event_id: String) -> void:
	match event_id:
		"asteroids":
			_toast("gh_event_asteroids", "ASTEROID FIELD!", "#8FD3FF")
			var sector: float = randf() * TAU
			var count: int = randi_range(10, maxi(10, int(_get_conf("asteroid_field_count", 14))))
			for i in range(count):
				_spawn_shard(_world_pos + Vector2.from_angle(sector + randf_range(-0.5, 0.5)) \
					* _view_radius() * randf_range(0.5, 1.1))
		"rival":
			_toast("gh_event_rival", "RIVAL HOLE!", "#E8553B")
			_rival_left = maxf(3.0, float(_get_conf("rival_duration_sec", 15.0)))
			_spawn_rival()
		"comet":
			_toast("gh_event_comet", "GOLDEN COMET!", "#FFD866")
			_spawn_comet()
		"inversion":
			_toast("gh_event_inversion", "INVERSION!", "#C77CFF")
			_inversion_left = maxf(1.0, float(_get_conf("inversion_duration_sec", 5.0)))
		"dimension":
			_begin_bonus_dimension()
		"storm":
			_toast("gh_event_storm", "DRIFT STORM!", "#9AD8FF")
			_storm_left = maxf(2.0, float(_get_conf("storm_duration_sec", 8.0)))

## Trou rival [E15] : vortex IA qui patrouille et mange les props (sans
## récompense pour le joueur) — course à la masse.
func _spawn_rival() -> void:
	if _world_root == null or not is_instance_valid(_world_root):
		return
	if _rival_node and is_instance_valid(_rival_node):
		return
	_rival_node = Node2D.new()
	_rival_node.name = "GravityRival"
	_rival_node.z_as_relative = false
	_rival_node.z_index = 12
	_rival_node.position = _ring_spawn_pos(1.0)
	var size_px: float = maxf(40.0, float(_get_conf("rival_size_px", 120.0)))
	var visual: Node2D = _build_sprite_fit(str(_get_conf("rival_vortex_asset", str(_get_conf("aura_asset", "")))), size_px)
	if visual == null:
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(20):
			var a: float = TAU * float(k) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * size_px * 0.5)
		circle.polygon = pts
		circle.color = Color("#7A1830C8")
		visual = circle
	visual.modulate = Color(str(_get_conf("rival_tint", "#FF5C5C")))
	_rival_node.add_child(visual)
	_world_root.add_child(_rival_node)

func _update_rival(dt: float) -> void:
	if _rival_node == null or not is_instance_valid(_rival_node) or _rival_left <= 0.0:
		return
	# Cible : le prop dérivant le plus proche du rival.
	var best: Dictionary = {}
	var best_dist: float = INF
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT or entry.has("fragment_index"):
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var d: float = (node_v as Node2D).position.distance_to(_rival_node.position)
		if d < best_dist:
			best_dist = d
			best = entry
	var speed: float = maxf(60.0, float(_get_conf("rival_speed_px_sec", 210.0)))
	if not best.is_empty():
		var target: Node2D = best.get("node")
		_rival_node.position += (target.position - _rival_node.position).normalized() * speed * dt
		if best_dist <= maxf(30.0, float(_get_conf("rival_eat_radius_px", 90.0))):
			if VFXManager:
				VFXManager.spawn_impact(_world_to_screen(target.position), 18.0, self)
			_remove_prop_entry(best)

## Dimension bonus [E18] : mini-cover signature → 3e bg où TOUT est mangeable.
func _begin_bonus_dimension() -> void:
	_toast("gh_event_dimension", "BONUS DIMENSION!", "#FFD866")
	_dimension_left = maxf(2.0, float(_get_conf("bonus_dimension_duration_sec", 6.0)))
	var bonus_res: Resource = _load_cached_resource(str(_get_conf("bonus_bg_asset", "")))
	if bonus_res is Texture2D:
		_bg_texture = bonus_res as Texture2D
	_retint_all_props()
	if VFXManager:
		VFXManager.screen_shake(4.0, 0.25)

func _end_bonus_dimension() -> void:
	_bg_texture = _bg_normal_texture
	_retint_all_props()

# =============================================================================
# FLÈCHE OMNIDIRECTIONNELLE (mangeable le plus proche hors écran)
# =============================================================================

## Cible : compass actif = plus PETIT mangeable partout ; sinon plus proche.
func _find_arrow_target() -> Dictionary:
	var best: Dictionary = {}
	var best_metric: float = INF
	for entry in _props:
		if int(entry.get("state", PropState.DRIFT)) != PropState.DRIFT:
			continue
		if entry.has("fragment_index"):
			if int(entry.get("fragment_index", 0)) != _next_fragment:
				continue
		elif float(entry.get("required_mass", 0.0)) > _mass and _dimension_left <= 0.0:
			continue
		var node_v: Variant = entry.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			continue
		var metric: float = float(entry.get("required_mass", 0.0)) if _compass_left > 0.0 \
			else (node_v as Node2D).position.distance_to(_world_pos)
		if metric < best_metric:
			best_metric = metric
			best = entry
	return best

func _ensure_arrow() -> void:
	if _arrow_root and is_instance_valid(_arrow_root):
		return
	_arrow_root = Node2D.new()
	_arrow_root.name = "GravityTargetArrow"
	_arrow_root.z_as_relative = false
	_arrow_root.z_index = 62
	var size_px: float = maxf(20.0, float(_get_conf("arrow_size_px", 52.0)))
	var asset_visual: Node2D = _build_sprite_fit(str(_get_conf("target_arrow_asset", "")), size_px)
	if asset_visual != null:
		_arrow_root.add_child(asset_visual)
	else:
		var tri := Polygon2D.new()
		tri.polygon = PackedVector2Array([
			Vector2(0.0, -size_px * 0.5),
			Vector2(size_px * 0.4, size_px * 0.35),
			Vector2(0.0, size_px * 0.12),
			Vector2(-size_px * 0.4, size_px * 0.35)
		])
		tri.color = Color(str(_get_conf("arrow_color", "#4FD8C8")))
		_arrow_root.add_child(tri)
	add_child(_arrow_root)

## Visible seulement quand AUCUN mangeable n'est à l'écran (ou compass actif) :
## clampée sur un rectangle intérieur, orientée vers la cible en monde.
func _update_arrow() -> void:
	_ensure_arrow()
	if _arrow_root == null or not is_instance_valid(_arrow_root):
		return
	if not (_state == State.RUN or _state == State.FINAL):
		_arrow_root.visible = false
		return
	var target: Dictionary = _find_arrow_target()
	if target.is_empty():
		_arrow_root.visible = false
		return
	var target_node: Node2D = target.get("node")
	var on_screen: bool = _is_on_screen(target_node.position, -40.0)
	if on_screen and _compass_left <= 0.0:
		_arrow_root.visible = false
		return
	var dir: Vector2 = (target_node.position - _world_pos)
	if dir.length() < 1.0:
		_arrow_root.visible = false
		return
	dir = dir.normalized()
	var viewport_size: Vector2 = get_viewport_rect().size
	var inset: float = maxf(30.0, float(_get_conf("arrow_edge_inset_px", 72.0)))
	var center: Vector2 = _screen_center()
	# Clamp du point sur le rectangle intérieur, dans la direction de la cible.
	var half: Vector2 = viewport_size * 0.5 - Vector2.ONE * inset
	var scale_x: float = INF if absf(dir.x) < 0.001 else half.x / absf(dir.x)
	var scale_y: float = INF if absf(dir.y) < 0.001 else half.y / absf(dir.y)
	_arrow_root.position = center + dir * minf(scale_x, scale_y)
	_arrow_root.rotation = dir.angle() + PI * 0.5
	_arrow_root.visible = true
	_arrow_root.modulate.a = 0.65 + 0.35 * (0.5 + 0.5 * sin(_time * TAU * 1.3))

# =============================================================================
# HUD (countdown + progression de masse)
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

## Progression vers l'objectif de taille : « masse / cible » (story ET Libre).
func _update_progress_label() -> void:
	if _progress_label == null or not is_instance_valid(_progress_label):
		_progress_label = Label.new()
		_progress_label.name = "GravityHoleProgressLabel"
		_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_progress_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("mass_progress_font_size", 26))))
		_progress_label.add_theme_color_override("font_color", Color("#7CFC9A"))
		_progress_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_progress_label.add_theme_constant_override("outline_size", 5)
		_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress_label.z_as_relative = false
		_progress_label.z_index = 60
		add_child(_progress_label)
	if not (_state == State.RUN or _state == State.FINAL):
		_progress_label.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_progress_label.visible = true
	_progress_label.size = Vector2(viewport_size.x, 34.0)
	_progress_label.position = Vector2(0.0, viewport_size.y * clampf(float(_get_conf("mass_progress_y_ratio", 0.21)), 0.02, 0.9))
	if _state == State.FINAL:
		_progress_label.text = "%d / %d" % [_next_fragment, _fragments_total]
	else:
		_progress_label.text = "%d / %d" % [int(round(_mass)), int(round(_target_mass))]

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
	queue_free() # monde, props, labels et transition sprite sont enfants -> freed together

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
