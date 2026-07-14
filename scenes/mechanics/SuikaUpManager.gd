extends Node2D

## SuikaUpManager — Orchestre une vague "suika_up" (Suika Game inversé +
## boss). Le boss décoratif occupe le tiers haut (barre de vie SANS chiffre,
## HUD standard), le vaisseau est verrouillé à
## la frontière boss/réacteur (tir coupé) et le joueur LANCE des formes rondes
## depuis le bas dans un réacteur physique fermé.
##
## Physique : premières RigidBody2D du projet — CircleShape2D, couche 7
## (bit 64) isolée (formes + murs StaticBody2D uniquement), CCD cast shape
## (lancers à 1350 px/s), matériaux partagés. Pause automatique (process_mode
## PAUSABLE hérité par les corps).
##
## GRAVITÉ INVERSÉE : les formes "tombent" vers le HAUT et s'accumulent
## contre le plafond du réacteur. La zone démarre VIDE et se remplit depuis le
## bas (lancements du joueur + bombes du boss). La limite de remplissage est
## donc EN BAS : redline pulsante + bandeau "DANGER" (même système graphique
## que ball_launcher) quand la pile descend trop.
##
## Boucle : drag depuis N'IMPORTE OÙ dans le réacteur (origine logique =
## touch_start, origine visuelle = la forme prête) → pointillés de trajectoire
## + jauge de force oscillante → release vers le haut = lancement (la forme
## monte, percute la pile, peut faire un "strike") ; retour près de l'origine
## / geste plat ou vers le bas = annulation. Deux formes de même niveau en
## contact prolongé FUSIONNENT (N+N=N+1, barycentre, pop). Les formes niveau
## 2+ (glow paramétrable) sont CLIQUABLES : tap court = consommée → le
## vaisseau tire sur le boss (dégâts % par niveau, divisés par
## boss_toughness_mult — knob de difficulté). Overflow : une forme qui reste
## SOUS la redline > grace_sec = dégâts joueur + purge des formes les plus
## basses.
##
## BOMBES DU BOSS : toutes les ~boss_shot_interval_sec (± jitter), le boss
## largue UN projectile niveau 1 (asset .tres/.jpg paramétrable par niveau,
## PH mine.tres) qui entre par le haut et remonte dans la pile avec la
## gravité inversée. Les bombes fusionnent ENTRE elles (4 lvl1 -> 2 lvl2 ->
## 1 lvl3) ; une bombe niveau 3 arme un COMPTE À REBOURS 5 -> 0 puis explose :
## souffle radial sur les formes + boss_bomb_damage_percent (30 %) de dégâts
## au joueur. Boss patterns additionnels data : gravity_pulse, attack_beam.
## Boss mort = kill_score/cristaux/loot uncommon+ (aspirés vers le vaisseau
## quel que soit leur x) + CLEAR TOTAL de la zone (formes ET bombes) ;
## timeout = le boss s'enfuit sans bonus. Les deux fins émettent `finished`
## (mode libre "restart" : régénération au level courant = nouveau boss).
##
## Assets par niveau (`levels{}.asset`, `boss_bomb_levels{}.asset`) : .tres
## animé OU .jpg/.png, rendus en COVER dans un CERCLE (images carrées, coins
## masqués par shader — la hitbox reste le cercle).
##
## Config PLATE dans wave_types.json > suika_up ; structures : levels{},
## clickable_glow{}, power_gauge{}, trajectory_preview{}, boss_patterns[],
## next_pool[], bosses[], crystal_chance_by_fire_level{}.

signal finished

enum State { INTRO, PLAY, BOSS_DEATH, BOSS_ESCAPE, DONE }
enum Gesture { IDLE, PRESSED, AIMING }

const MOUSE_CAPTURE_ID: int = -2
const SHAPE_LAYER: int = 64 # couche 7 — réservée au réacteur suika
const TRAJECTORY_DOT_POOL: int = 26
# Masque circulaire (cover) : images carrées, coins hors du cercle inscrits
# jetés. Basé sur les coordonnées LOCALES du vertex — marche pour Sprite2D ET
# AnimatedSprite2D (atlas compris), la hitbox physique reste le CircleShape2D.
const CIRCLE_MASK_SHADER_CODE: String = """
shader_type canvas_item;
uniform float radius_px = 32.0;
varying vec2 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	if (dot(local_pos, local_pos) > radius_px * radius_px) {
		discard;
	}
}
"""

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

# Layout.
var _viewport_size: Vector2 = Vector2.ZERO
var _reactor_rect: Rect2 = Rect2()
var _redline_y: float = 0.0
var _ship_lock_pos: Vector2 = Vector2.ZERO
var _ready_spawn_pos: Vector2 = Vector2.ZERO

# Boss décoratif : barre normalisée 1.0 -> 0.0 sans chiffre.
var _boss_node: Node2D = null
var _boss_sprite: Node2D = null
var _boss_def: Dictionary = {}
var _boss_health: float = 1.0
var _boss_center: Vector2 = Vector2.ZERO
var _boss_visual_size: Vector2 = Vector2.ZERO

# Formes du réacteur : { "body": RigidBody2D, "level": int, "radius": float,
# "kind": "normal"|"junk"|"bomb", "visual": Node2D, "glow": Node2D|null,
# "merging": bool, "merge_cooldown": float, "beyond_redline_sec": float,
# "rest_timer": float, "bomb_timer": float, "bomb_label": Label|null }.
var _shapes: Array = []
# Forme prête (freeze=true, layers 0 tant qu'elle attend) : même structure.
var _ready_shape: Dictionary = {}
var _next_level: int = 1
# Paires en contact (fusion) : "idA_idB" (ids triés) -> temps de contact.
var _merge_pairs: Dictionary = {}
# Tirs visuels vaisseau -> boss : { "node", "from", "to", "t", "duration",
# "level" }.
var _shots: Array = []
var _walls: Array = []

# Matériaux physiques partagés.
var _shape_material: PhysicsMaterial = null
var _wall_material: PhysicsMaterial = null
var _floor_material: PhysicsMaterial = null

# Geste.
var _gesture: int = Gesture.IDLE
var _touch_id: int = -1
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_current: Vector2 = Vector2.ZERO
var _press_time_ms: int = 0
var _press_max_move: float = 0.0
var _tap_candidate: Dictionary = {}
var _aim_time: float = 0.0
var _launch_cooldown: float = 0.0

# Visée / jauge (fallbacks procéduraux, assets data optionnels).
var _trajectory_dots: Array = []
var _add_material: CanvasItemMaterial = null
var _gauge_root: Control = null
var _gauge_fill: ColorRect = null
var _gauge_marker: ColorRect = null
var _gauge_perfect: ColorRect = null

# Zone de visée indiquée (même principe que ball_launcher) : bande translucide
# sur le réacteur + message localisé (viser ici + contre 2+), masquée après le
# premier lancement réussi.
var _aim_zone_panel: Panel = null
var _aim_hint_label: Label = null
var _aim_hint_dismissed: bool = false

# Overflow (limite EN BAS : la pile colle au plafond et descend).
var _overflow_cooldown: float = 0.0
var _redline_line: Line2D = null
var _danger_warning_rect: ColorRect = null

# Tir de bombes du boss : TÉLÉGRAPHIÉ — compte à rebours + niveau de contre
# affichés avant chaque tir ; consommer une forme >= niveau requis ANNULE le
# tir (le joueur sait quand le tir arrive et comment l'empêcher).
var _boss_shot_timer: float = 0.0
var _shot_telegraph_active: bool = false
var _shot_telegraph_timer: float = 0.0
var _shot_required_level: int = 2
var _boss_shot_label: Label = null # compte à rebours affiché SUR le boss
var _circle_mask_shader: Shader = null

# Boss patterns.
var _pattern_timer: float = 0.0
var _beam_active: bool = false
var _beam_timer: float = 0.0
var _beam_cfg: Dictionary = {}
var _beam_line: Line2D = null

# NEXT panel.
var _next_preview: Polygon2D = null

# UI.
var _countdown_label: Label = null
var _warning_label: Label = null

# Paramètres (résolus au setup — clés PLATES).
var _intro_settle_sec: float = 0.8
var _launch_cooldown_sec: float = 0.35
var _min_launch_distance: float = 42.0
var _cancel_distance: float = 24.0
var _min_upward_drag: float = 28.0
var _aim_drag_start: float = 18.0
var _min_launch_speed: float = 420.0
var _max_launch_speed: float = 1350.0
var _max_drag_distance: float = 180.0
var _min_upward_angle_deg: float = 18.0
var _max_side_angle_deg: float = 72.0
var _strike_mult: float = 1.0
var _ready_level_default: int = 1
var _tap_max_duration_sec: float = 0.22
var _tap_max_move: float = 14.0
var _click_hit_mult: float = 1.35
var _max_level: int = 6
var _min_clickable_level: int = 2
var _initial_shape_count: int = 6
var _max_shapes_active: int = 42
var _merge_grace: float = 0.06
var _merge_cooldown_sec: float = 0.12
var _max_merges_per_frame: int = 3
var _merge_pop_impulse: float = 90.0
var _gravity_scale: float = 0.85
var _linear_damp: float = 0.45
var _angular_damp: float = 0.35
var _sleep_velocity_threshold: float = 18.0
var _overflow_enabled: bool = true
var _overflow_grace: float = 2.0
var _overflow_damage_pct: float = 0.35
var _overflow_ends_wave: bool = false
var _overflow_purge_enabled: bool = true
var _overflow_purge_max: int = 4
var _overflow_cooldown_sec: float = 3.0
var _patterns_enabled: bool = true
var _pattern_interval: float = 7.0
var _junk_radius: float = 14.0
var _junk_mass: float = 1.0
var _boss_shot_interval: float = 5.0
var _boss_shot_jitter: float = 2.0
var _boss_shot_telegraph_sec: float = 3.0
var _shot_counter_min_level: int = 2
var _shot_counter_max_level: int = 4
var _shot_counter_high_after_sec: float = 20.0
var _boss_bomb_countdown_sec: float = 5.0
var _boss_bomb_damage_pct: float = 0.3
var _boss_bomb_blast_impulse: float = 420.0
var _boss_bomb_blast_radius: float = 160.0
var _boss_bomb_max_level: int = 3
var _boss_bomb_levels: Dictionary = {}
var _boss_toughness: float = 1.0
var _kill_score: int = 5000
var _kill_crystals: int = 8
var _kill_loot_quality_mult: float = 8.0
var _kill_loot_min_rarity: String = "uncommon"
var _boss_death_anim_sec: float = 1.6
var _boss_escape_anim_sec: float = 1.0
var _attack_shot_duration: float = 0.35
var _levels_cfg: Dictionary = {}
var _glow_cfg: Dictionary = {}
var _trajectory_cfg: Dictionary = {}
var _gauge_cfg: Dictionary = {}
var _next_pool: Array = []
var _boss_patterns: Array = []
var _crystal_chance_by_level: Dictionary = {}
var _boss_defs: Array = []
var _boss_frames_by_index: Array = []
var _level_textures: Dictionary = {} # level(int) -> Texture2D
var _level_frames: Dictionary = {} # level(int) -> SpriteFrames (.tres animé)
var _bomb_textures: Dictionary = {} # level(int) -> Texture2D
var _bomb_frames: Dictionary = {} # level(int) -> SpriteFrames
var _trajectory_dot_texture: Texture2D = null

# =============================================================================
# Améliorations 13 juillet 2026 : pickups, décharge, variantes de formes,
# événements réacteur, boss enragé/support, fusion massive.
# =============================================================================
# Pénalité de score (overflow_penalty_mode "score") : Game refuse les points
# négatifs -> dette interne absorbée par les gains suivants (_award_score).
var _score_debt: int = 0
# Pickups : orbes non-physiques collectées par une forme joueur EN MOUVEMENT.
var _pickups: Array = [] # { "node", "cfg", "pos", "ttl", "phase" }
var _pickup_timer: float = 0.0
var _last_pickup_id: String = ""
# Effets de pickups.
var _perfect_boost_left: int = 0
var _perfect_window_mult: float = 2.0
var _double_shot_armed: bool = false
var _double_shot_fan_deg: float = 14.0
var _stasis_timer: float = 0.0
var _grapple_charges: int = 0
var _hold_ring: Line2D = null # anneau de progression du tap long (grappin)
# Décharge du vaisseau : jauge chargée par les fusions, bouton bas-gauche.
var _discharge_value: float = 0.0
var _discharge_root: Node2D = null
var _discharge_fill: ColorRect = null
var _discharge_halo: Node2D = null
var _discharge_pos: Vector2 = Vector2.ZERO
var _discharge_ready_announced: bool = false
# Variantes de formes.
var _sticky_material: PhysicsMaterial = null
# Événements réacteur (un seul actif, anti-répétition).
var _event_timer: float = 0.0
var _last_event_id: String = ""
var _rage_active: bool = false
var _rage_telegraph: float = 0.0
var _rage_bombs_left: int = 0
var _rage_stagger_timer: float = 0.0
var _gravity_outage_telegraph: float = 0.0
var _gravity_outage_timer: float = 0.0
var _gravity_mult: float = 1.0
var _tilt_timer: float = 0.0
var _tilt_dir: float = 0.0
# Boss enragé (< enrage_health_ratio) + fusion massive + boss support.
var _enraged: bool = false
var _massive_merge_cooldown: float = 0.0
var _support_boss_node: Node2D = null
var _support_spawned: bool = false
var _support_shot_timer: float = 0.0
# Icônes de statut bas-droite (au-dessus du NEXT panel).
var _status_icons: Dictionary = {} # id -> { "root": Node2D, "badge": Label }

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("suika_up") if DataManager else {}

	_duration = maxf(10.0, float(_config.get("duration", _cfg.get("duration_sec_default", 60.0))))
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_intro_settle_sec = maxf(0.05, float(_get_conf("intro_settle_sec", 0.8)))
	_launch_cooldown_sec = maxf(0.05, float(_get_conf("launch_cooldown_sec", 0.35)))
	_min_launch_distance = maxf(4.0, float(_get_conf("min_launch_distance_px", 42.0)))
	_cancel_distance = maxf(2.0, float(_get_conf("cancel_distance_px", 24.0)))
	_min_upward_drag = maxf(2.0, float(_get_conf("min_upward_drag_px", 28.0)))
	_aim_drag_start = maxf(2.0, float(_get_conf("aim_drag_start_px", 18.0)))
	_min_launch_speed = maxf(60.0, float(_get_conf("min_launch_speed_px_sec", 420.0)))
	_max_launch_speed = maxf(_min_launch_speed, float(_get_conf("max_launch_speed_px_sec", 1350.0)))
	_max_drag_distance = maxf(20.0, float(_get_conf("max_drag_distance_px", 180.0)))
	_min_upward_angle_deg = clampf(float(_get_conf("min_upward_angle_deg", 18.0)), 2.0, 85.0)
	_max_side_angle_deg = clampf(float(_get_conf("max_side_angle_deg", 72.0)), 5.0, 88.0)
	_strike_mult = maxf(0.1, float(_get_conf("strike_impulse_multiplier", 1.0)))
	_ready_level_default = clampi(int(_get_conf("ready_level_default", 1)), 1, 6)
	_tap_max_duration_sec = maxf(0.05, float(_get_conf("tap_max_duration_sec", 0.22)))
	_tap_max_move = maxf(2.0, float(_get_conf("tap_max_move_px", 14.0)))
	_click_hit_mult = maxf(1.0, float(_get_conf("click_hit_radius_multiplier", 1.35)))
	_max_level = clampi(int(_get_conf("max_level", 6)), 2, 12)
	_min_clickable_level = clampi(int(_get_conf("min_clickable_level", 2)), 1, _max_level)
	_initial_shape_count = clampi(int(_get_conf("initial_shape_count", 6)), 0, 30)
	_max_shapes_active = clampi(int(_get_conf("max_shapes_active", 42)), 6, 80)
	_merge_grace = maxf(0.0, float(_get_conf("merge_contact_grace_sec", 0.06)))
	_merge_cooldown_sec = maxf(0.0, float(_get_conf("merge_cooldown_sec", 0.12)))
	_max_merges_per_frame = clampi(int(_get_conf("max_merges_per_physics_frame", 3)), 1, 10)
	_merge_pop_impulse = maxf(0.0, float(_get_conf("merge_pop_impulse", 90.0)))
	_gravity_scale = clampf(float(_get_conf("gravity_scale", 0.85)), 0.1, 3.0)
	_linear_damp = maxf(0.0, float(_get_conf("linear_damp", 0.45)))
	_angular_damp = maxf(0.0, float(_get_conf("angular_damp", 0.35)))
	_sleep_velocity_threshold = maxf(1.0, float(_get_conf("sleep_velocity_threshold", 18.0)))
	_overflow_enabled = bool(_get_conf("overflow_enabled", true))
	_overflow_grace = maxf(0.8, float(_get_conf("overflow_grace_sec", 2.0))) # clamp min (freemode)
	_overflow_damage_pct = clampf(float(_get_conf("overflow_damage_percent", 0.35)), 0.0, 1.0)
	_overflow_ends_wave = bool(_get_conf("overflow_ends_wave", false))
	_overflow_purge_enabled = bool(_get_conf("overflow_purge_enabled", true))
	_overflow_purge_max = clampi(int(_get_conf("overflow_purge_max_shapes", 4)), 0, 20)
	_overflow_cooldown_sec = maxf(0.5, float(_get_conf("overflow_cooldown_sec", 3.0)))
	_patterns_enabled = bool(_get_conf("boss_patterns_enabled", true))
	_pattern_interval = maxf(3.0, float(_get_conf("boss_pattern_interval_sec", 7.0))) # clamp min (freemode)
	_junk_radius = maxf(6.0, float(_get_conf("junk_radius_px", 14.0)))
	_junk_mass = maxf(0.1, float(_get_conf("junk_mass", 1.0)))
	# Scaling freemode en POURCENTAGE : la fréquence de tir du boss et le
	# countdown des bombes se réduisent avec le level (via _free_level_progress
	# 0->1 injecté par build_free_mode_wave — 0 en story), plafonnés par des
	# seuils data. À level max : réduction de freemode_time_reduction_max_pct.
	var free_progress: float = clampf(float(_config.get("_free_level_progress", 0.0)), 0.0, 1.0)
	var time_scale: float = 1.0 - clampf(float(_get_conf("freemode_time_reduction_max_pct", 0.5)), 0.0, 0.9) * free_progress
	_boss_shot_interval = maxf(
		maxf(0.5, float(_get_conf("boss_shot_interval_min_sec", 2.5))),
		float(_get_conf("boss_shot_interval_sec", 5.0)) * time_scale)
	_boss_shot_jitter = maxf(0.0, float(_get_conf("boss_shot_interval_jitter_sec", 2.0)))
	_boss_shot_telegraph_sec = maxf(0.5, float(_get_conf("boss_shot_telegraph_sec", 3.0)))
	_shot_counter_min_level = clampi(int(_get_conf("boss_shot_counter_min_level", 2)), 1, 6)
	_shot_counter_max_level = clampi(int(_get_conf("boss_shot_counter_max_level", 2)), _shot_counter_min_level, 6)
	_shot_counter_high_after_sec = maxf(0.0, float(_get_conf("boss_shot_counter_high_after_sec", 20.0)))
	_boss_bomb_countdown_sec = maxf(
		maxf(0.3, float(_get_conf("boss_bomb_countdown_min_sec", 1.0))),
		float(_get_conf("boss_bomb_countdown_sec", 5.0)) * time_scale)
	_boss_bomb_damage_pct = clampf(float(_get_conf("boss_bomb_damage_percent", 0.3)), 0.0, 1.0)
	_boss_bomb_blast_impulse = maxf(0.0, float(_get_conf("boss_bomb_blast_impulse", 420.0)))
	_boss_bomb_blast_radius = maxf(20.0, float(_get_conf("boss_bomb_blast_radius_px", 160.0)))
	_boss_bomb_max_level = clampi(int(_get_conf("boss_bomb_max_level", 3)), 2, 6)
	var bomb_levels_v: Variant = _get_conf("boss_bomb_levels", {})
	_boss_bomb_levels = (bomb_levels_v as Dictionary).duplicate(true) if bomb_levels_v is Dictionary else {}
	_boss_toughness = maxf(0.5, float(_get_conf("boss_toughness_mult", 1.0))) # clamp min (freemode)
	_kill_score = maxi(0, int(_get_conf("kill_score", 5000)))
	_kill_crystals = maxi(0, int(_get_conf("kill_crystals", 8)))
	_kill_loot_quality_mult = maxf(0.0, float(_get_conf("kill_loot_quality_mult", 8.0)))
	_kill_loot_min_rarity = str(_get_conf("kill_loot_min_rarity", "uncommon"))
	_boss_death_anim_sec = maxf(0.3, float(_get_conf("boss_death_anim_sec", 1.6)))
	_boss_escape_anim_sec = maxf(0.2, float(_get_conf("boss_escape_anim_sec", 1.0)))
	_attack_shot_duration = maxf(0.1, float(_get_conf("attack_shot_duration_sec", 0.35)))
	var levels_v: Variant = _get_conf("levels", {})
	_levels_cfg = (levels_v as Dictionary).duplicate(true) if levels_v is Dictionary else {}
	var glow_v: Variant = _get_conf("clickable_glow", {})
	_glow_cfg = (glow_v as Dictionary) if glow_v is Dictionary else {}
	var traj_v: Variant = _get_conf("trajectory_preview", {})
	_trajectory_cfg = (traj_v as Dictionary) if traj_v is Dictionary else {}
	var gauge_v: Variant = _get_conf("power_gauge", {})
	_gauge_cfg = (gauge_v as Dictionary) if gauge_v is Dictionary else {}
	var pool_v: Variant = _get_conf("next_pool", [])
	_next_pool = (pool_v as Array) if pool_v is Array else []
	var patterns_v: Variant = _get_conf("boss_patterns", [])
	_boss_patterns = (patterns_v as Array) if patterns_v is Array else []
	var crystal_v: Variant = _get_conf("crystal_chance_by_fire_level", {})
	_crystal_chance_by_level = (crystal_v as Dictionary) if crystal_v is Dictionary else {}
	var bosses_v: Variant = _get_conf("bosses", [])
	_boss_defs = (bosses_v as Array).duplicate(true) if bosses_v is Array else []

	_prepare_assets()
	_compute_layout()
	_build_materials()
	_begin_player_mode()
	_begin_hud_mode()
	_build_reactor_walls()
	_build_reactor_background()
	_build_reactor_frame()
	_build_boss(_pick_boss_def())
	_build_trajectory_dots()
	_build_power_gauge()
	_build_next_panel()
	_build_aim_zone_hint()
	_ensure_countdown_label()
	_ensure_warning_label()

	_build_discharge_button()

	_elapsed = 0.0
	_boss_health = 1.0
	_pattern_timer = _pattern_interval
	_boss_shot_timer = _boss_shot_interval + randf_range(0.0, _boss_shot_jitter)
	_pickup_timer = maxf(1.0, float(_get_conf("pickup_first_delay_sec", 6.0)))
	_event_timer = maxf(2.0, float(_get_conf("reactor_event_first_delay_sec", 10.0)))
	_next_level = _roll_next_level()
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_arrival_sec", 1.0)))
	set_process(true)
	set_physics_process(true)

## Per-wave override (world_X.json / freemode) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Toast central (pipeline splash « Vague X » du jeu).
func _toast(key: String, fallback: String, color_html: String = "") -> void:
	if _game and is_instance_valid(_game) and _game.has_method("show_center_splash"):
		_game.call("show_center_splash", _translate_or(key, fallback), "", color_html)

## Score centralisé : absorbe la dette (overflow en mode « score ») avant de
## créditer — Game.add_wave_bonus_score refuse les points négatifs.
func _award_score(points: int, at: Vector2) -> void:
	if points <= 0:
		return
	if _score_debt > 0:
		var absorbed: int = mini(_score_debt, points)
		_score_debt -= absorbed
		points -= absorbed
	if points > 0 and _game and is_instance_valid(_game) and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at)

func _effect_labels_enabled() -> bool:
	var global_default: bool = bool(DataManager.get_wave_types_global("effect_labels_enabled", false)) if DataManager else false
	return bool(_get_conf("effect_labels_enabled", global_default))

func _attach_effect_label(node: Node2D, text: String, size_px: float, color: Color) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("effect_label_font_size", 16))))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(160.0, 24.0)
	label.position = Vector2(-80.0, size_px * 0.5 + 2.0)
	label.z_index = 2
	node.add_child(label)

func _level_cfg(level: int) -> Dictionary:
	var v: Variant = _levels_cfg.get(str(level), {})
	return (v as Dictionary) if v is Dictionary else {}

func _bomb_level_cfg(level: int) -> Dictionary:
	var v: Variant = _boss_bomb_levels.get(str(level), {})
	return (v as Dictionary) if v is Dictionary else {}

# =============================================================================
# PLAYER / HUD MODES
# =============================================================================

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_suika_up"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_suika_up", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_suika_up"):
		_player.call("end_suika_up")

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
# ASSETS
# =============================================================================

func _prepare_assets() -> void:
	_level_textures.clear()
	_level_frames.clear()
	for level in range(1, _max_level + 1):
		var asset_path: String = str(_level_cfg(level).get("asset", ""))
		var frames: SpriteFrames = _frames_from_path(asset_path)
		if frames != null:
			_level_frames[level] = frames
		else:
			var tex: Texture2D = _texture_from_path(asset_path)
			if tex != null:
				_level_textures[level] = tex
	_bomb_textures.clear()
	_bomb_frames.clear()
	for level in range(1, _boss_bomb_max_level + 1):
		var bomb_path: String = str(_bomb_level_cfg(level).get("asset", ""))
		var bomb_anim: SpriteFrames = _frames_from_path(bomb_path)
		if bomb_anim != null:
			_bomb_frames[level] = bomb_anim
		else:
			var bomb_tex: Texture2D = _texture_from_path(bomb_path)
			if bomb_tex != null:
				_bomb_textures[level] = bomb_tex
	_boss_frames_by_index.clear()
	for boss_v in _boss_defs:
		var anim_path: String = str((boss_v as Dictionary).get("asset_anim", "")) if boss_v is Dictionary else ""
		_boss_frames_by_index.append(_frames_from_path(anim_path))
	_trajectory_dot_texture = _texture_from_path(str(_get_conf("trajectory_dot_asset", "")))
	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_circle_mask_shader = Shader.new()
	_circle_mask_shader.code = CIRCLE_MASK_SHADER_CODE

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
	var margin: float = maxf(2.0, float(_get_conf("reactor_side_margin_px", 16.0)))
	var top: float = _viewport_size.y * clampf(float(_get_conf("reactor_top_ratio", 0.42)), 0.3, 0.8)
	var bottom: float = _viewport_size.y * clampf(float(_get_conf("reactor_bottom_ratio", 0.96)), 0.6, 1.0)
	_reactor_rect = Rect2(Vector2(margin, top), Vector2(_viewport_size.x - margin * 2.0, maxf(80.0, bottom - top)))
	# Gravité inversée : la pile colle au plafond, la limite de remplissage
	# (redline) est près du BAS du réacteur.
	_redline_y = bottom - maxf(4.0, float(_get_conf("redline_offset_px", 36.0)))
	_ship_lock_pos = Vector2(
		_viewport_size.x * clampf(float(_get_conf("ship_lock_x_ratio", 0.5)), 0.1, 0.9),
		_viewport_size.y * clampf(float(_get_conf("ship_lock_y_ratio", 0.36)), 0.15, 0.7))
	_ready_spawn_pos = Vector2(
		_viewport_size.x * 0.5,
		bottom - maxf(10.0, float(_get_conf("ready_projectile_y_offset_from_bottom_px", 54.0))))
	_boss_center = Vector2(_viewport_size.x * 0.5, boss_h * 0.55)

func _build_materials() -> void:
	_shape_material = PhysicsMaterial.new()
	_shape_material.bounce = clampf(float(_get_conf("bounce", 0.22)), 0.0, 1.0)
	_shape_material.friction = clampf(float(_get_conf("friction", 0.72)), 0.0, 2.0)
	_wall_material = PhysicsMaterial.new()
	_wall_material.bounce = clampf(float(_get_conf("wall_bounce", 0.28)), 0.0, 1.0)
	_wall_material.friction = clampf(float(_get_conf("friction", 0.72)), 0.0, 2.0)
	_floor_material = PhysicsMaterial.new()
	_floor_material.bounce = clampf(float(_get_conf("bounce", 0.22)) * 0.5, 0.0, 1.0)
	_floor_material.friction = clampf(float(_get_conf("floor_friction", 0.86)), 0.0, 2.0)
	# Bulles collantes [V10] : friction forte + zéro rebond (arches contre les murs).
	_sticky_material = PhysicsMaterial.new()
	_sticky_material.bounce = 0.0
	_sticky_material.friction = clampf(float(_get_conf("sticky_friction", 1.0)), 0.0, 2.0)

## Réacteur fermé : 4 StaticBody2D épais (32 px) sur la couche 64. GRAVITÉ
## INVERSÉE : le plafond est le "sol" d'accumulation (friction de sol), le
## mur bas ferme la zone de lancement ; la redline (limite de remplissage)
## est un seuil LOGIQUE près du bas.
func _build_reactor_walls() -> void:
	var thickness: float = 32.0
	var rect: Rect2 = _reactor_rect
	_walls.append(_make_wall(Vector2(rect.position.x - thickness * 0.5, rect.get_center().y), Vector2(thickness, rect.size.y + thickness * 2.0), _wall_material))
	_walls.append(_make_wall(Vector2(rect.end.x + thickness * 0.5, rect.get_center().y), Vector2(thickness, rect.size.y + thickness * 2.0), _wall_material))
	_walls.append(_make_wall(Vector2(rect.get_center().x, rect.position.y - thickness * 0.5), Vector2(rect.size.x + thickness * 2.0, thickness), _floor_material))
	_walls.append(_make_wall(Vector2(rect.get_center().x, rect.end.y + thickness * 0.5), Vector2(rect.size.x + thickness * 2.0, thickness), _wall_material))

func _make_wall(center: Vector2, size: Vector2, phys_material: PhysicsMaterial) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = SHAPE_LAYER
	wall.collision_mask = 0
	wall.physics_material_override = phys_material
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	shape.shape = rect_shape
	wall.add_child(shape)
	wall.position = center
	add_child(wall)
	return wall

## Fond de la zone de jeu : grand rectangle en COVER (recadré au rect du
## réacteur via clip) — accepte une texture .jpg/.png OU un .tres animé
## (reactor_background_asset, opacité reactor_background_opacity).
func _build_reactor_background() -> void:
	var asset_path: String = str(_get_conf("reactor_background_asset", ""))
	if asset_path == "":
		return
	var opacity: float = clampf(float(_get_conf("reactor_background_opacity", 1.0)), 0.0, 1.0)
	var clip := Control.new()
	clip.name = "ReactorBackground"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = _reactor_rect.position
	clip.size = _reactor_rect.size
	clip.z_as_relative = false
	clip.z_index = 7 # sous le cadre (8) et les formes (10)
	clip.modulate.a = opacity
	var frames: SpriteFrames = _frames_from_path(asset_path)
	if frames != null:
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		if VFXManager:
			VFXManager.play_sprite_frames(anim, frames, &"default", true, 0.0)
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			var first: Texture2D = frames.get_frame_texture(names[0], 0)
			if first != null and first.get_size().x > 0.0 and first.get_size().y > 0.0:
				# Cover : le plus grand ratio remplit le rect, le clip recadre.
				var cover: float = maxf(_reactor_rect.size.x / first.get_size().x, _reactor_rect.size.y / first.get_size().y)
				anim.scale = Vector2.ONE * cover
		anim.position = _reactor_rect.size * 0.5
		clip.add_child(anim)
	else:
		var tex: Texture2D = _texture_from_path(asset_path)
		if tex == null:
			clip.queue_free()
			return
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(rect)
	add_child(clip)

## Cadre visuel + redline pulsante (fallbacks Line2D si assets vides).
func _build_reactor_frame() -> void:
	var frame := Line2D.new()
	frame.name = "ReactorFrame"
	frame.width = 3.0
	frame.default_color = Color(str(_get_conf("reactor_frame_color", "#3A4A5AC0")))
	frame.points = PackedVector2Array([
		Vector2(_reactor_rect.position.x, _reactor_rect.position.y),
		Vector2(_reactor_rect.position.x, _reactor_rect.end.y),
		Vector2(_reactor_rect.end.x, _reactor_rect.end.y),
		Vector2(_reactor_rect.end.x, _reactor_rect.position.y),
		Vector2(_reactor_rect.position.x, _reactor_rect.position.y)
	])
	frame.z_as_relative = false
	frame.z_index = 8
	add_child(frame)
	_redline_line = Line2D.new()
	_redline_line.name = "Redline"
	_redline_line.width = 2.5
	_redline_line.default_color = Color(str(_get_conf("redline_color", "#FF4444C0")))
	_redline_line.points = PackedVector2Array([
		Vector2(_reactor_rect.position.x, _redline_y),
		Vector2(_reactor_rect.end.x, _redline_y)
	])
	_redline_line.z_as_relative = false
	_redline_line.z_index = 9
	add_child(_redline_line)
	# Bandeau "DANGER" translucide centré sur la redline (même système
	# graphique que ball_launcher) : visible quand la pile atteint la zone.
	var warning_h: float = maxf(8.0, float(_get_conf("danger_warning_height_px", 30.0)))
	_danger_warning_rect = ColorRect.new()
	_danger_warning_rect.name = "SuikaDangerWarning"
	_danger_warning_rect.color = Color(str(_get_conf("danger_warning_bg_color", "#FF3B3B4D")))
	_danger_warning_rect.size = Vector2(_viewport_size.x, warning_h)
	_danger_warning_rect.position = Vector2(0.0, _redline_y - warning_h * 0.5)
	_danger_warning_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_warning_rect.z_as_relative = false
	_danger_warning_rect.z_index = 58
	_danger_warning_rect.visible = false
	add_child(_danger_warning_rect)
	var danger_label := Label.new()
	danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	danger_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	danger_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("danger_warning_font_size", 22))))
	danger_label.add_theme_color_override("font_color", Color(str(_get_conf("danger_warning_text_color", "#FFFFFF"))))
	danger_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	danger_label.add_theme_constant_override("outline_size", 6)
	danger_label.size = _danger_warning_rect.size
	danger_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_label.text = _translate_or("ball_launcher_danger", "DANGER").to_upper()
	_danger_warning_rect.add_child(danger_label)

func _pick_boss_def() -> Dictionary:
	if _boss_defs.is_empty():
		return {}
	var forced_id: String = str(_config.get("boss_id", ""))
	if forced_id != "":
		for boss_v in _boss_defs:
			if boss_v is Dictionary and str((boss_v as Dictionary).get("id", "")) == forced_id:
				return boss_v as Dictionary
		push_warning("[SuikaUp] boss_id inconnu '%s' — premier boss de la liste utilisé." % forced_id)
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
	_boss_node.name = "SuikaBoss"
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
	# Compte à rebours du tir : affiché SUR le boss (chiffre seul — le joueur
	# est renseigné par le hint de zone, pas de phrase répétée).
	_boss_shot_label = Label.new()
	_boss_shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_shot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_shot_label.add_theme_font_size_override("font_size", maxi(16, int(_get_conf("boss_shot_label_font_size", 40))))
	_boss_shot_label.add_theme_color_override("font_color", Color(str(_get_conf("boss_shot_label_color", "#FF8844"))))
	_boss_shot_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_shot_label.add_theme_constant_override("outline_size", 7)
	_boss_shot_label.size = Vector2(120.0, 60.0)
	_boss_shot_label.position = Vector2(-60.0, -30.0)
	_boss_shot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_shot_label.z_index = 2
	_boss_shot_label.visible = false
	_boss_node.add_child(_boss_shot_label)
	add_child(_boss_node)
	# Arrivée : translation depuis l'extérieur du haut de l'écran.
	_boss_node.position = Vector2(_boss_center.x, -_boss_visual_size.y)
	var tween: Tween = create_tween()
	tween.tween_property(_boss_node, "position", _boss_center, maxf(0.05, float(_get_conf("intro_arrival_sec", 1.0)))) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# =============================================================================
# FORMES (RigidBody2D construits par code)
# =============================================================================

## Crée une forme ronde. kind : "normal" (joueur), "junk" (pattern legacy,
## inerte), "bomb" (projectile du boss — fusionne entre bombes, lvl max =
## countdown + explosion), "dark" (déchet [V9] — ne fusionne jamais, tap =
## évacuation). frozen = forme prête (layers 0, freeze).
## variant [13 juillet 2026] : "" | "prism" (wild [V7]) | "square" ([V8],
## RectangleShape2D, radius = demi-diagonale) | "sticky" ([V10], friction
## forte). GRAVITÉ INVERSÉE : gravity_scale négatif — tout "tombe" vers le
## plafond (× _gravity_mult : 0 pendant la panne de gravité).
func _create_shape_body(level: int, pos: Vector2, kind: String, frozen: bool, variant: String = "") -> Dictionary:
	var is_junk: bool = kind == "junk"
	var is_bomb: bool = kind == "bomb"
	var is_dark: bool = kind == "dark"
	var lvl_cfg: Dictionary = _bomb_level_cfg(level) if is_bomb else _level_cfg(level)
	var radius: float = maxf(6.0, float(lvl_cfg.get("radius_px", 14.0)))
	if is_junk:
		radius = _junk_radius
	elif is_dark:
		radius = maxf(8.0, float(_get_conf("dark_radius_px", 26.0)))
	var body := RigidBody2D.new()
	body.collision_layer = 0 if frozen else SHAPE_LAYER
	body.collision_mask = 0 if frozen else SHAPE_LAYER
	body.mass = _junk_mass if is_junk else maxf(0.1, float(lvl_cfg.get("mass", 1.0)))
	body.gravity_scale = -absf(_gravity_scale) * _gravity_mult # inversée : la pile colle en haut
	body.linear_damp = _linear_damp
	body.angular_damp = _angular_damp
	body.physics_material_override = _shape_material
	if variant == "sticky":
		body.physics_material_override = _sticky_material
		body.linear_damp = _linear_damp * maxf(1.0, float(_get_conf("sticky_linear_damp_mult", 2.2)))
	body.can_sleep = true
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.freeze = frozen
	# Réacteur penché [E18] en cours : les nouveaux corps subissent la même force.
	if _tilt_timer > 0.0:
		body.constant_force = Vector2(_tilt_dir * _current_tilt_force(), 0.0) * body.mass
	var collision := CollisionShape2D.new()
	if variant == "square":
		# Carrée [V8] : côté ~ aire équivalente au cercle ; le "radius" logique
		# devient la DEMI-DIAGONALE (fusion/click/overflow restent corrects).
		var side: float = radius * 1.6
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(side, side)
		collision.shape = rect_shape
		radius = side * 0.7071
	else:
		var circle := CircleShape2D.new()
		circle.radius = radius
		collision.shape = circle
	body.add_child(collision)
	# Visuel : asset du niveau (.tres animé OU texture) rendu en COVER dans un
	# cercle (masque shader — images carrées, la hitbox reste le cercle) ;
	# fallback = cercle coloré procédural. Variantes : prism/dark = assets
	# dédiés (cover cercle) ; square = texture teintée SANS masque circulaire.
	var color := Color(str(lvl_cfg.get("color", "#9BB8CC")))
	if is_junk:
		color = Color(str(_get_conf("junk_color", "#8A8A8AFF")))
	elif is_dark:
		color = Color("#3A2E4A")
	var frames_pool: Dictionary = _bomb_frames if is_bomb else _level_frames
	var textures_pool: Dictionary = _bomb_textures if is_bomb else _level_textures
	var visual: Node2D = null
	if variant == "square":
		var side: float = radius / 0.7071
		var square_tex: Texture2D = _texture_from_path(str(_get_conf("square_asset", "")))
		if square_tex != null and square_tex.get_size().x > 0.0:
			var sq_sprite := Sprite2D.new()
			sq_sprite.texture = square_tex
			sq_sprite.scale = Vector2.ONE * (side / maxf(square_tex.get_size().x, square_tex.get_size().y))
			sq_sprite.modulate = color # teinte du niveau sur la texture générique
			visual = sq_sprite
		else:
			var sq_poly := Polygon2D.new()
			var half: float = side * 0.5
			sq_poly.polygon = PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
			sq_poly.color = color
			visual = sq_poly
	elif variant == "prism":
		var prism_tex: Texture2D = _texture_from_path(str(_get_conf("prism_asset", "")))
		if prism_tex != null and prism_tex.get_size().x > 0.0:
			var pr_sprite := Sprite2D.new()
			pr_sprite.texture = prism_tex
			_apply_circle_cover(pr_sprite, prism_tex.get_size(), radius)
			visual = pr_sprite
	elif is_dark:
		var dark_tex: Texture2D = _texture_from_path(str(_get_conf("dark_asset", "")))
		if dark_tex != null and dark_tex.get_size().x > 0.0:
			var dk_sprite := Sprite2D.new()
			dk_sprite.texture = dark_tex
			_apply_circle_cover(dk_sprite, dark_tex.get_size(), radius)
			visual = dk_sprite
	if visual == null and not is_junk and not is_dark and variant != "square" and frames_pool.has(level):
		var frames: SpriteFrames = frames_pool[level]
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = frames
		if VFXManager:
			VFXManager.play_sprite_frames(anim, frames, &"default", true, 0.0)
		var first: Texture2D = null
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			first = frames.get_frame_texture(names[0], 0)
		if first != null and first.get_size().x > 0.0:
			_apply_circle_cover(anim, first.get_size(), radius)
		visual = anim
	elif visual == null and not is_junk and not is_dark and variant != "square" and textures_pool.has(level):
		var sprite := Sprite2D.new()
		sprite.texture = textures_pool[level]
		var tex_size: Vector2 = (textures_pool[level] as Texture2D).get_size()
		if tex_size.x > 0.0:
			_apply_circle_cover(sprite, tex_size, radius)
		visual = sprite
	if visual == null:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(24):
			var a: float = TAU * float(i) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		poly.polygon = pts
		poly.color = color
		visual = poly
	# Glow additif pulsant des formes cliquables (identification + niveau).
	var glow: Node2D = null
	if kind == "normal" and bool(_glow_cfg.get("enabled", true)) and level >= int(_glow_cfg.get("min_level", 2)) and level >= _min_clickable_level:
		glow = _make_shape_glow(level, radius)
		body.add_child(glow)
	body.add_child(visual)
	# Marqueurs de variante : liseré collant, anneau prismatique, label d'effet.
	if variant == "sticky":
		var ring := Line2D.new()
		ring.closed = true
		ring.width = 3.0
		ring.default_color = Color(str(_get_conf("sticky_ring_color", "#7FE58CFF")))
		var ring_pts := PackedVector2Array()
		for k in range(18):
			var a2: float = TAU * float(k) / 18.0
			ring_pts.append(Vector2(cos(a2), sin(a2)) * (radius + 3.0))
		ring.points = ring_pts
		body.add_child(ring)
	elif variant == "prism":
		var prism_ring := Line2D.new()
		prism_ring.closed = true
		prism_ring.width = 3.0
		prism_ring.default_color = Color(1.0, 1.0, 1.0, 0.85)
		prism_ring.material = _add_material
		var pr_pts := PackedVector2Array()
		for k in range(18):
			var a3: float = TAU * float(k) / 18.0
			pr_pts.append(Vector2(cos(a3), sin(a3)) * (radius + 3.0))
		prism_ring.points = pr_pts
		body.add_child(prism_ring)
		if _effect_labels_enabled():
			_attach_effect_label(body, _translate_or("suika_label_prism", "PRISM"), radius * 2.0, Color("#C0F0FF"))
	if is_dark and _effect_labels_enabled():
		_attach_effect_label(body, _translate_or("suika_label_dark", "JUNK"), radius * 2.0, Color("#B48CFF"))
	body.z_as_relative = false
	body.z_index = 10
	body.global_position = pos
	add_child(body)
	return {
		"body": body,
		"level": level,
		"radius": radius,
		"kind": kind,
		"variant": variant,
		"visual": visual,
		"glow": glow,
		"merging": false,
		"merge_cooldown": 0.0,
		"beyond_redline_sec": 0.0,
		"rest_timer": 0.0,
		"bomb_timer": -1.0,
		"bomb_label": null
	}

## COVER circulaire : le côté (min) de l'image carrée = le diamètre du cercle,
## les coins qui débordent sont jetés par le masque (coordonnées locales —
## fonctionne avec les atlas des .tres).
func _apply_circle_cover(sprite: Node2D, frame_size: Vector2, radius: float) -> void:
	var side: float = minf(frame_size.x, frame_size.y)
	if side <= 0.0:
		return
	sprite.scale = Vector2.ONE * (radius * 2.0 / side)
	var mask := ShaderMaterial.new()
	mask.shader = _circle_mask_shader
	# Rayon en pixels LOCAUX du sprite (avant le scale du node).
	mask.set_shader_parameter("radius_px", side * 0.5)
	sprite.material = mask

func _make_shape_glow(level: int, radius: float) -> Node2D:
	var glow := Polygon2D.new()
	var glow_radius: float = radius * maxf(1.0, float(_glow_cfg.get("scale_max", 1.08))) + 6.0
	if level >= _max_level:
		glow_radius = radius * maxf(1.0, float(_glow_cfg.get("ultimate_scale_max", 1.14))) + 8.0
	var pts := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(Vector2(cos(a), sin(a)) * glow_radius)
	glow.polygon = pts
	var colors_v: Variant = _glow_cfg.get("level_colors", {})
	var color_str: String = "#FFFFFF"
	if colors_v is Dictionary:
		color_str = str((colors_v as Dictionary).get(str(level), "#FFFFFF"))
	glow.color = Color(color_str)
	glow.material = _add_material
	var alpha_min: float = clampf(float(_glow_cfg.get("alpha_min", 0.35)), 0.0, 1.0)
	var alpha_max: float = clampf(float(_glow_cfg.get("alpha_max", 0.85)), alpha_min, 1.0)
	if level >= int(_glow_cfg.get("strong_level", 5)):
		alpha_max = clampf(float(_glow_cfg.get("strong_alpha_max", 1.0)), alpha_min, 1.0)
	var pulse: float = maxf(0.1, float(_glow_cfg.get("pulse_sec", 0.85)))
	glow.modulate.a = alpha_max
	var tween: Tween = glow.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", alpha_min, pulse * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", alpha_max, pulse * 0.5).set_trans(Tween.TRANS_SINE)
	return glow

## Libère une forme (le dict doit déjà être retiré de _shapes par l'appelant).
func _free_shape(entry: Dictionary, with_vfx: bool) -> void:
	var body_v: Variant = entry.get("body", null)
	if body_v is RigidBody2D and is_instance_valid(body_v):
		var body: RigidBody2D = body_v as RigidBody2D
		if with_vfx and VFXManager:
			VFXManager.spawn_explosion(body.global_position, maxf(12.0, float(entry.get("radius", 14.0))), Color("#FFAA00"), self, "", "", -1.0, 0.2)
		_wake_shapes_near(body.global_position, float(entry.get("radius", 14.0)) * 4.0)
		body.collision_layer = 0
		body.collision_mask = 0
		body.queue_free()

func _wake_shapes_near(center: Vector2, radius: float) -> void:
	var radius_sq: float = radius * radius
	for entry_v in _shapes:
		var body_v: Variant = (entry_v as Dictionary).get("body", null)
		if body_v is RigidBody2D and is_instance_valid(body_v):
			var body: RigidBody2D = body_v as RigidBody2D
			if body.global_position.distance_squared_to(center) <= radius_sq:
				body.sleeping = false

## Pool pondéré next_pool[] (défaut : niveau 1 garanti).
func _roll_next_level() -> int:
	if _next_pool.is_empty():
		return _ready_level_default
	var total: float = 0.0
	for entry_v in _next_pool:
		if entry_v is Dictionary:
			total += maxf(0.0, float((entry_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return _ready_level_default
	var roll: float = randf() * total
	for entry_v in _next_pool:
		if not (entry_v is Dictionary):
			continue
		roll -= maxf(0.0, float((entry_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			return clampi(int((entry_v as Dictionary).get("level", 1)), 1, _max_level)
	return _ready_level_default

## Forme prête : freeze + layers 0 (les formes du réacteur la traversent),
## petite anim de scale pour montrer qu'elle attend. Aucune conversion au
## lancement : freeze off + layers 64 + vélocité.
func _spawn_ready_projectile() -> void:
	if not _ready_shape.is_empty():
		return
	# Variantes [V7-10] roulées sur la munition : sombre (kind dédié, lvl 1),
	# sinon prisme > carrée > collante (exclusives, chances data).
	var kind: String = "normal"
	var variant: String = ""
	var level: int = _next_level
	if randf() <= clampf(float(_get_conf("dark_chance", 0.0)), 0.0, 0.2):
		kind = "dark"
		level = 1
	elif randf() <= clampf(float(_get_conf("prism_chance", 0.0)), 0.0, 0.2):
		variant = "prism"
	elif randf() <= clampf(float(_get_conf("square_chance", 0.0)), 0.0, 0.2):
		variant = "square"
	elif randf() <= clampf(float(_get_conf("sticky_chance", 0.0)), 0.0, 0.2):
		variant = "sticky"
	_ready_shape = _create_shape_body(level, _ready_spawn_pos, kind, true, variant)
	_next_level = _roll_next_level()
	_refresh_next_panel()
	var visual_v: Variant = _ready_shape.get("visual", null)
	if visual_v is Node2D and is_instance_valid(visual_v):
		var visual: Node2D = visual_v as Node2D
		# Le scale courant EST le cover (_apply_circle_cover) qui dimensionne
		# l'asset à radius*2 : pulser RELATIVEMENT à lui, jamais vers Vector2.ONE
		# (= taille native de l'image, ~600px → bille surdimensionnée en 1:1).
		var base_scale: Vector2 = visual.scale
		_ready_shape["base_scale"] = base_scale
		var tween: Tween = visual.create_tween().set_loops()
		tween.tween_property(visual, "scale", base_scale * 1.08, 0.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(visual, "scale", base_scale, 0.5).set_trans(Tween.TRANS_SINE)
		_ready_shape["pulse_tween"] = tween

func _launch_ready_shape(direction: Vector2, power: float) -> void:
	if _ready_shape.is_empty():
		return
	var entry: Dictionary = _ready_shape
	_ready_shape = {}
	var body_v: Variant = entry.get("body", null)
	if not (body_v is RigidBody2D) or not is_instance_valid(body_v):
		return
	var body: RigidBody2D = body_v as RigidBody2D
	var visual_v: Variant = entry.get("visual", null)
	if visual_v is Node2D and is_instance_valid(visual_v):
		# Stopper la pulsation et restaurer le scale cover (PAS Vector2.ONE, qui
		# afficherait la bille lancée à la taille native de l'image).
		var pulse_v: Variant = entry.get("pulse_tween", null)
		if pulse_v is Tween and is_instance_valid(pulse_v):
			(pulse_v as Tween).kill()
		var base_scale_v: Variant = entry.get("base_scale", null)
		if base_scale_v is Vector2:
			(visual_v as Node2D).scale = base_scale_v
	body.freeze = false
	body.collision_layer = SHAPE_LAYER
	body.collision_mask = SHAPE_LAYER
	var speed: float = lerpf(_min_launch_speed, _max_launch_speed, clampf(power, 0.0, 1.0)) * _strike_mult
	body.linear_velocity = direction.normalized() * speed
	_shapes.append(entry)
	_launch_cooldown = _launch_cooldown_sec
	# Jauge parfaite étendue [B2] : consommer un lancer du boost.
	if _perfect_boost_left > 0:
		_perfect_boost_left -= 1
		_refresh_status_icons()
	# Munition double [B3] : le lancer armé tire une 2e forme lvl 1 en éventail.
	if _double_shot_armed:
		_double_shot_armed = false
		_refresh_status_icons()
		if _shapes.size() < _max_shapes_active:
			var extra: Dictionary = _create_shape_body(1, body.global_position, "normal", false)
			var extra_body: RigidBody2D = extra.get("body") as RigidBody2D
			var fan: float = deg_to_rad(maxf(2.0, _double_shot_fan_deg)) * (1.0 if randf() < 0.5 else -1.0)
			extra_body.linear_velocity = direction.normalized().rotated(fan) * speed
			_shapes.append(extra)
	_dismiss_aim_zone_hint() # le joueur a compris : le hint disparaît

# =============================================================================
# PHYSICS SCAN (fusions + redline + sleep + garde-fous) — _physics_process :
# jamais dans un callback du serveur physique -> add/remove sûrs.
# =============================================================================

func _physics_process(delta: float) -> void:
	if _state == State.DONE:
		return
	_purge_invalid_shapes()
	_update_shape_timers(delta)
	if _state == State.PLAY or _state == State.INTRO:
		_try_merge_pass(delta)
	if _state == State.PLAY:
		if _stasis_timer <= 0.0:
			_check_overflow(delta)
		_scan_pickup_collection()
		_apply_bomb_magnets()
	_apply_out_of_bounds_guard()

func _purge_invalid_shapes() -> void:
	for i in range(_shapes.size() - 1, -1, -1):
		var body_v: Variant = (_shapes[i] as Dictionary).get("body", null)
		if not (body_v is RigidBody2D) or not is_instance_valid(body_v):
			_shapes.remove_at(i)

func _update_shape_timers(delta: float) -> void:
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		entry["merge_cooldown"] = maxf(0.0, float(entry.get("merge_cooldown", 0.0)) - delta)
		# Sleep surcouche : honorer sleep_velocity_threshold data.
		var body: RigidBody2D = entry.get("body") as RigidBody2D
		if body.sleeping:
			continue
		if body.linear_velocity.length_squared() < _sleep_velocity_threshold * _sleep_velocity_threshold:
			entry["rest_timer"] = float(entry.get("rest_timer", 0.0)) + delta
			if float(entry["rest_timer"]) > 1.0:
				body.sleeping = true
				entry["rest_timer"] = 0.0
		else:
			entry["rest_timer"] = 0.0

## Fusions par scan de paires intra-groupe (contact prolongé >= grace).
## Groupes = (kind, level) : les formes du joueur fusionnent entre elles, les
## BOMBES du boss fusionnent entre elles (jamais l'un avec l'autre), le junk
## ne fusionne jamais.
func _try_merge_pass(delta: float) -> void:
	if _stasis_timer > 0.0:
		return # stase [B4] : la pile est figée, aucune fusion
	var by_level: Dictionary = {}
	var prisms: Array = []
	var wild_candidates: Array = []
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		var kind: String = str(entry.get("kind", "normal"))
		if kind == "junk" or kind == "dark" or bool(entry.get("merging", false)):
			continue
		if float(entry.get("merge_cooldown", 0.0)) > 0.0:
			continue
		var level: int = int(entry.get("level", 1))
		# Prisme [V7] : wild — hors des groupes (kind, level), passe dédiée.
		if kind == "normal" and str(entry.get("variant", "")) == "prism":
			prisms.append(entry)
			continue
		if kind == "normal":
			wild_candidates.append(entry)
		if kind == "bomb":
			if level >= _boss_bomb_max_level:
				continue # bombe max : armée (countdown), ne fusionne plus
		elif level >= _max_level:
			continue
		var group_key: String = kind + "_" + str(level)
		if not by_level.has(group_key):
			by_level[group_key] = []
		(by_level[group_key] as Array).append(entry)
	var touched_keys: Dictionary = {}
	var ready_to_merge: Array = []
	for level_v in by_level.keys():
		var group: Array = by_level[level_v]
		for i in range(group.size()):
			var entry_a: Dictionary = group[i]
			var body_a: RigidBody2D = entry_a.get("body") as RigidBody2D
			for j in range(i + 1, group.size()):
				var entry_b: Dictionary = group[j]
				var body_b: RigidBody2D = entry_b.get("body") as RigidBody2D
				var reach: float = float(entry_a.get("radius", 14.0)) + float(entry_b.get("radius", 14.0)) + 2.0
				if body_a.global_position.distance_squared_to(body_b.global_position) > reach * reach:
					continue
				var key: String = _pair_key(body_a, body_b)
				touched_keys[key] = true
				_merge_pairs[key] = float(_merge_pairs.get(key, 0.0)) + delta
				if float(_merge_pairs[key]) >= _merge_grace:
					ready_to_merge.append([entry_a, entry_b, key, false])
	# Passe WILD [V7] : chaque prisme contre toute forme normale/prisme —
	# fusionne avec n'importe quel niveau (résultat = min des deux + 1).
	for p_idx in range(prisms.size()):
		var prism: Dictionary = prisms[p_idx]
		var prism_body: RigidBody2D = prism.get("body") as RigidBody2D
		var partners: Array = wild_candidates
		for q_idx in range(p_idx + 1, prisms.size()):
			partners = partners + [prisms[q_idx]]
		for partner_v in partners:
			var partner: Dictionary = partner_v as Dictionary
			var partner_body: RigidBody2D = partner.get("body") as RigidBody2D
			var reach2: float = float(prism.get("radius", 14.0)) + float(partner.get("radius", 14.0)) + 2.0
			if prism_body.global_position.distance_squared_to(partner_body.global_position) > reach2 * reach2:
				continue
			var key2: String = _pair_key(prism_body, partner_body)
			touched_keys[key2] = true
			_merge_pairs[key2] = float(_merge_pairs.get(key2, 0.0)) + delta
			if float(_merge_pairs[key2]) >= _merge_grace:
				ready_to_merge.append([prism, partner, key2, true])
	# Purge des paires qui ne se touchent plus.
	for key_v in _merge_pairs.keys():
		if not touched_keys.has(key_v):
			_merge_pairs.erase(key_v)
	var merges_done: int = 0
	for pair_v in ready_to_merge:
		if merges_done >= _max_merges_per_frame:
			break
		var pair: Array = pair_v as Array
		var entry_a: Dictionary = pair[0]
		var entry_b: Dictionary = pair[1]
		if bool(entry_a.get("merging", false)) or bool(entry_b.get("merging", false)):
			continue
		_merge_pairs.erase(pair[2])
		_execute_merge(entry_a, entry_b, bool(pair[3]))
		merges_done += 1

func _pair_key(a: RigidBody2D, b: RigidBody2D) -> String:
	var id_a: int = a.get_instance_id()
	var id_b: int = b.get_instance_id()
	return str(mini(id_a, id_b)) + "_" + str(maxi(id_a, id_b))

## Lvl N + Lvl N -> Lvl N+1 au barycentre pondéré, avec pop (vers le BAS :
## à l'opposé de la gravité inversée, la fusion "saute" hors de la pile).
## Deux BOMBES fusionnent en bombe N+1 ; au niveau max, la bombe s'ARME
## (compte à rebours -> explosion).
func _execute_merge(entry_a: Dictionary, entry_b: Dictionary, wild: bool = false) -> void:
	entry_a["merging"] = true
	entry_b["merging"] = true
	var kind: String = str(entry_a.get("kind", "normal"))
	var body_a: RigidBody2D = entry_a.get("body") as RigidBody2D
	var body_b: RigidBody2D = entry_b.get("body") as RigidBody2D
	var mass_total: float = maxf(0.01, body_a.mass + body_b.mass)
	var barycenter: Vector2 = (body_a.global_position * body_a.mass + body_b.global_position * body_b.mass) / mass_total
	var inherited_vel: Vector2 = (body_a.linear_velocity * body_a.mass + body_b.linear_velocity * body_b.mass) / mass_total
	# Wild [V7] : le prisme monte le PLUS BAS des deux niveaux d'un cran.
	var new_level: int = int(entry_a.get("level", 1)) + 1
	if wild:
		new_level = clampi(mini(int(entry_a.get("level", 1)), int(entry_b.get("level", 1))) + 1, 2, _max_level)
	var wake_radius: float = (float(entry_a.get("radius", 14.0)) + float(entry_b.get("radius", 14.0))) * 1.5
	_shapes.erase(entry_a)
	_shapes.erase(entry_b)
	_free_shape(entry_a, false)
	_free_shape(entry_b, false)
	var merged: Dictionary = _create_shape_body(new_level, barycenter, kind, false)
	merged["merge_cooldown"] = _merge_cooldown_sec
	var merged_body: RigidBody2D = merged.get("body") as RigidBody2D
	merged_body.linear_velocity = inherited_vel
	merged_body.apply_central_impulse(Vector2(0.0, _merge_pop_impulse) * merged_body.mass)
	_shapes.append(merged)
	_wake_shapes_near(barycenter, wake_radius)
	if kind == "bomb" and new_level >= _boss_bomb_max_level:
		_arm_bomb(merged)
	# VFX pop de fusion.
	if VFXManager:
		var merge_anim: String = str(_get_conf("merge_fx_anim", ""))
		var pop_cfg: Dictionary = _bomb_level_cfg(new_level) if kind == "bomb" else _level_cfg(new_level)
		VFXManager.spawn_explosion(barycenter, float(merged.get("radius", 20.0)) * 1.2,
			Color(str(pop_cfg.get("color", "#FFFFFF"))), self, "", merge_anim, -1.0, 0.2)
	if kind == "normal":
		var points: int = int(round(10.0 * float(new_level) * _reward_multiplier))
		_award_score(points, barycenter)
		# Décharge [B6] : chaque fusion charge la jauge du vaisseau.
		_gain_discharge(new_level)
		# Fusion massive [E19] : une fusion haut niveau compacte la pile vers le
		# PLAFOND (sens de la gravité inversée) + cristaux — célébration mécanique.
		if new_level >= maxi(2, int(_get_conf("massive_merge_min_level", 5))) and _massive_merge_cooldown <= 0.0:
			_massive_merge_cooldown = 2.0
			_trigger_massive_merge(barycenter)

## Overflow : gravité inversée -> la pile colle en haut et DESCEND en se
## remplissant. Une forme qui reste SOUS la redline (bas du réacteur) > grace
## = pénalité (dégâts joueur + purge des formes les plus basses), puis
## cooldown anti-spam. Bandeau "DANGER" (style ball_launcher) dès que la pile
## atteint la zone.
func _check_overflow(delta: float) -> void:
	if not _overflow_enabled:
		return
	if _overflow_cooldown > 0.0:
		_overflow_cooldown -= delta
		return
	var any_beyond: bool = false
	var triggered: bool = false
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		var body: RigidBody2D = entry.get("body") as RigidBody2D
		if body.global_position.y + float(entry.get("radius", 14.0)) > _redline_y:
			any_beyond = true
			entry["beyond_redline_sec"] = float(entry.get("beyond_redline_sec", 0.0)) + delta
			if float(entry["beyond_redline_sec"]) >= _overflow_grace:
				triggered = true
		else:
			entry["beyond_redline_sec"] = 0.0
	# Redline qui clignote + bandeau DANGER dès qu'une forme est dans la zone.
	if _redline_line and is_instance_valid(_redline_line):
		if any_beyond:
			_redline_line.modulate.a = lerpf(0.45, 1.0, 0.5 + 0.5 * sin(_elapsed * 12.0))
		else:
			_redline_line.modulate.a = 1.0
	if _danger_warning_rect and is_instance_valid(_danger_warning_rect):
		_danger_warning_rect.visible = any_beyond
	if triggered:
		_trigger_overflow_penalty()

func _trigger_overflow_penalty() -> void:
	_overflow_cooldown = _overflow_cooldown_sec
	for entry_v in _shapes:
		(entry_v as Dictionary)["beyond_redline_sec"] = 0.0
	# Overflow indulgent [V14] : mode "score" = pas de dégâts, la purge coûte
	# une DETTE de score (absorbée par les gains suivants — Game refuse les
	# points négatifs) ; mode "damage" (défaut) = comportement historique.
	if str(_get_conf("overflow_penalty_mode", "damage")) == "score":
		var penalty: int = maxi(0, int(_get_conf("overflow_score_penalty", 400)))
		_score_debt += penalty
		if VFXManager and penalty > 0:
			VFXManager.spawn_floating_text(
				Vector2(_reactor_rect.get_center().x, _redline_y - 40.0),
				"-%d" % penalty, Color("#FF4444"), self)
	elif _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * _overflow_damage_pct))))
	if _overflow_purge_enabled and _overflow_purge_max > 0:
		_purge_lowest_shapes(_overflow_purge_max, true)
	_show_warning(_translate_or("suika_up_overflow_warning", "OVERFLOW!"), Color("#FF4444"))
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(10, 0.4)
	if _overflow_ends_wave:
		_start_boss_escape()

## Purge des N formes les plus BASSES (la pile remonte) — overflow ET pickup
## purge [B1]. Retourne le nombre réellement purgé.
func _purge_lowest_shapes(count: int, with_vfx: bool) -> int:
	if count <= 0 or _shapes.is_empty():
		return 0
	var sorted: Array = _shapes.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		return ((a as Dictionary).get("body") as RigidBody2D).global_position.y \
			> ((b as Dictionary).get("body") as RigidBody2D).global_position.y)
	var purged: int = 0
	for i in range(mini(count, sorted.size())):
		var entry: Dictionary = sorted[i]
		_shapes.erase(entry)
		_free_shape(entry, with_vfx)
		purged += 1
	return purged

## Garde-fou : un corps éjecté hors du réacteur (explosion de solveur) est
## reposé au centre-HAUT (la pile vit contre le plafond), vélocité nulle.
func _apply_out_of_bounds_guard() -> void:
	var guard_rect: Rect2 = _reactor_rect.grow(80.0)
	for entry_v in _shapes:
		var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
		if not guard_rect.has_point(body.global_position):
			body.global_position = Vector2(_reactor_rect.get_center().x, _reactor_rect.position.y + float((entry_v as Dictionary).get("radius", 14.0)) + 4.0)
			body.linear_velocity = Vector2.ZERO

# =============================================================================
# INPUT (raw touch : tap court = clic de forme, drag = visée + lancement)
# =============================================================================

func _input(event: InputEvent) -> void:
	if _state != State.PLAY:
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed \
			and (event as InputEventScreenTouch).index == _touch_id:
			_reset_gesture()
		elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and _touch_id == MOUSE_CAPTURE_ID:
			_reset_gesture()
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			if _touch_id == -1:
				_gesture_begin(touch.index, touch.position)
		elif touch.index == _touch_id:
			_gesture_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_gesture_feed(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_btn.pressed:
			if _touch_id == -1:
				_gesture_begin(MOUSE_CAPTURE_ID, mouse_btn.position)
		elif _touch_id == MOUSE_CAPTURE_ID:
			_gesture_end()
	elif event is InputEventMouseMotion and _touch_id == MOUSE_CAPTURE_ID:
		_gesture_feed((event as InputEventMouseMotion).position)

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

func _reset_gesture() -> void:
	_touch_id = -1
	_gesture = Gesture.IDLE
	_tap_candidate = {}
	_hide_aim_visuals()

## Début du geste : DANS le réacteur uniquement. Le premier point d'appui est
## la référence de direction (le joueur n'a pas besoin de toucher la forme).
func _gesture_begin(capture_id: int, screen_pos: Vector2) -> void:
	var world: Vector2 = _to_world(screen_pos)
	if world.y < _reactor_rect.position.y:
		return
	_touch_id = capture_id
	_gesture = Gesture.PRESSED
	_aim_origin = world
	_aim_current = world
	_press_time_ms = Time.get_ticks_msec()
	_press_max_move = 0.0
	_aim_time = 0.0
	_tap_candidate = _find_clickable_at(world)

## Forme cliquable sous le doigt (hitbox élargie mobile), la plus proche.
func _find_clickable_at(world: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		var kind: String = str(entry.get("kind", "normal"))
		if bool(entry.get("merging", false)):
			continue
		# Forme sombre [V9] : évacuable par tap à TOUT niveau.
		if kind != "dark":
			if kind != "normal":
				continue
			if int(entry.get("level", 1)) < _min_clickable_level:
				continue
			var lvl_cfg: Dictionary = _level_cfg(int(entry.get("level", 1)))
			if not bool(lvl_cfg.get("clickable", true)):
				continue
		var body: RigidBody2D = entry.get("body") as RigidBody2D
		var dist: float = world.distance_to(body.global_position)
		if dist <= float(entry.get("radius", 14.0)) * _click_hit_mult and dist < best_dist:
			best = entry
			best_dist = dist
	return best

func _gesture_feed(screen_pos: Vector2) -> void:
	if _gesture == Gesture.IDLE:
		return
	_aim_current = _to_world(screen_pos)
	_press_max_move = maxf(_press_max_move, _aim_current.distance_to(_aim_origin))
	if _gesture == Gesture.PRESSED and _press_max_move > _aim_drag_start:
		# Passage en visée : le tap est définitivement annulé.
		_gesture = Gesture.AIMING
		_tap_candidate = {}

func _gesture_end() -> void:
	var gesture: int = _gesture
	var elapsed_ms: int = Time.get_ticks_msec() - _press_time_ms
	var world: Vector2 = _aim_current
	_touch_id = -1
	_gesture = Gesture.IDLE
	_hide_aim_visuals()
	if gesture == Gesture.PRESSED:
		var press_sec: float = float(elapsed_ms) / 1000.0
		# Bouton DÉCHARGE [B6] (bas-gauche) : tap court sur l'icône, jauge pleine.
		if press_sec <= _tap_max_duration_sec and _press_max_move <= _tap_max_move \
			and _discharge_hit(world):
			_tap_candidate = {}
			return
		# Grappin [B5] : tap LONG immobile sur une forme = impulsion vers le bas.
		if press_sec >= maxf(0.1, float(_get_conf("grapple_hold_min_sec", 0.45))) \
			and _press_max_move <= _tap_max_move and _grapple_charges > 0:
			_try_grapple(world)
			_tap_candidate = {}
			return
		# Tap court sur une forme cliquable = consommation + tir sur le boss.
		if press_sec <= _tap_max_duration_sec and _press_max_move <= _tap_max_move \
			and not _tap_candidate.is_empty() and _shapes.has(_tap_candidate):
			_consume_clickable_shape(_tap_candidate)
		_tap_candidate = {}
		return
	if gesture == Gesture.AIMING:
		_tap_candidate = {}
		var launch: Dictionary = _evaluate_launch(world)
		if bool(launch.get("valid", false)):
			_launch_ready_shape(launch.get("direction", Vector2.UP) as Vector2, float(launch.get("power", 0.5)))
		elif bool(launch.get("blocked", false)):
			_show_warning(_translate_or("suika_up_reactor_full", "REACTOR FULL"), Color("#FF5555"), 1.2)

## Validité + direction + puissance du lancement à partir du drag courant.
## {valid, direction, power} — invalide si safe zone / plat / vers le bas /
## trop court / cooldown / forme absente / réacteur plein.
func _evaluate_launch(world: Vector2) -> Dictionary:
	var result: Dictionary = {"valid": false, "direction": Vector2.UP, "power": 0.0, "blocked": false}
	var drag: Vector2 = world - _aim_origin
	var dist: float = drag.length()
	if _ready_shape.is_empty() or _launch_cooldown > 0.0:
		return result
	if _shapes.size() >= _max_shapes_active:
		result["blocked"] = true
		return result
	if dist < _min_launch_distance or dist < _cancel_distance:
		return result
	if drag.y >= -_min_upward_drag:
		return result
	# Angle par rapport à la verticale (0 = plein haut).
	var ang: float = atan2(drag.x, -drag.y)
	if absf(ang) > deg_to_rad(_max_side_angle_deg):
		return result
	# Clamp : jamais plus plat que min_upward_angle_deg au-dessus de l'horizontale.
	var max_from_vertical: float = PI * 0.5 - deg_to_rad(_min_upward_angle_deg)
	ang = clampf(ang, -max_from_vertical, max_from_vertical)
	var base_power: float = clampf(dist / _max_drag_distance, 0.0, 1.0)
	var power: float = base_power
	if bool(_gauge_cfg.get("enabled", true)):
		var gauge_t: float = _gauge_t()
		var gauge_value: float = lerpf(
			maxf(0.05, float(_gauge_cfg.get("min_power_multiplier", 0.65))),
			maxf(0.1, float(_gauge_cfg.get("max_power_multiplier", 1.25))), gauge_t)
		var influence: float = clampf(float(_gauge_cfg.get("gauge_influence", 0.45)), 0.0, 1.0)
		power = base_power * lerpf(1.0, gauge_value, influence)
		# Fenêtre "perfect" en haut de la jauge — ×window_mult pendant le boost [B2].
		if gauge_t >= 1.0 - _effective_perfect_ratio():
			power *= maxf(1.0, float(_gauge_cfg.get("perfect_power_multiplier", 1.1)))
	result["valid"] = true
	result["direction"] = Vector2(sin(ang), -cos(ang))
	result["power"] = clampf(power, 0.0, 1.0)
	return result

## Position 0..1 de la jauge oscillante (triangle ping-pong).
func _gauge_t() -> float:
	var osc: float = maxf(0.1, float(_gauge_cfg.get("oscillation_sec", 1.1)))
	return pingpong(_aim_time / (osc * 0.5), 1.0)

# =============================================================================
# CONSOMMATION (tap lvl 2+) + TIR VAISSEAU -> BOSS
# =============================================================================

func _consume_clickable_shape(entry: Dictionary) -> void:
	var level: int = int(entry.get("level", 1))
	var body: RigidBody2D = entry.get("body") as RigidBody2D
	var at_pos: Vector2 = body.global_position
	# Forme sombre [V9] : évacuation simple — score, pas de tir ni de contre.
	if str(entry.get("kind", "normal")) == "dark":
		_shapes.erase(entry)
		_free_shape(entry, true)
		_award_score(int(round(float(int(_get_conf("dark_evacuate_score", 40))) * _reward_multiplier)), at_pos)
		return
	_shapes.erase(entry)
	_free_shape(entry, true) # trou physique -> effondrement naturel + réveil
	var lvl_cfg: Dictionary = _level_cfg(level)
	var points: int = int(round(float(lvl_cfg.get("score_on_fire", 0)) * _reward_multiplier))
	_award_score(points, at_pos)
	var crystal_chance: float = clampf(float(_crystal_chance_by_level.get(str(level), 0.0)), 0.0, 1.0)
	if randf() <= crystal_chance and _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", at_pos, {"force_magnet_below_y": _ship_lock_pos.y - 60.0})
	# Contre du pattern attack_beam : un tir assez puissant annule l'attaque.
	if _beam_active and level >= int(_beam_cfg.get("counter_min_level", 3)):
		_cancel_beam(true)
	# Contre du tir de bombe télégraphié.
	_try_counter_boss_shot(level)
	_fire_ship_shot(level)

## Projectile visuel maison : impact garanti sur le boss (décoratif).
## damage_override [B6] : dégâts BRUTS fixés (décharge — sans toughness).
func _fire_ship_shot(level: int, damage_override: float = -1.0) -> void:
	var lvl_cfg: Dictionary = _level_cfg(level)
	var shot := Node2D.new()
	shot.z_as_relative = false
	shot.z_index = 15
	var radius: float = clampf(float(lvl_cfg.get("radius_px", 14.0)) * 0.5, 6.0, 24.0)
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = Color(str(lvl_cfg.get("color", "#FF8A5C")))
	shot.add_child(poly)
	add_child(shot)
	var from: Vector2 = _ship_lock_pos + Vector2(0.0, -24.0)
	if _player and is_instance_valid(_player):
		from = _player.global_position + Vector2(0.0, -24.0)
	var target: Vector2 = _boss_center + Vector2(
		randf_range(-_boss_visual_size.x * 0.3, _boss_visual_size.x * 0.3),
		randf_range(-_boss_visual_size.y * 0.25, _boss_visual_size.y * 0.25))
	shot.global_position = from
	_shots.append({
		"node": shot,
		"from": from,
		"to": target,
		"t": 0.0,
		"duration": _attack_shot_duration * (1.0 + float(level) * 0.06),
		"level": level,
		"damage_override": damage_override
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
			_on_shot_impact(int(shot.get("level", 2)), to, float(shot.get("damage_override", -1.0)))
			continue
		var eased: float = ease(clampf(t, 0.0, 1.0), 0.6)
		var pos: Vector2 = from.lerp(to, eased)
		var perp: Vector2 = (to - from).orthogonal().normalized()
		pos += perp * sin(t * PI) * 26.0
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).global_position = pos

func _on_shot_impact(level: int, at_pos: Vector2, damage_override: float = -1.0) -> void:
	var impact_cfg_v: Variant = _get_conf("boss_hit_explosion", {})
	var impact_cfg: Dictionary = impact_cfg_v if impact_cfg_v is Dictionary else {}
	if VFXManager:
		VFXManager.spawn_explosion(
			at_pos,
			maxf(8.0, float(impact_cfg.get("size", 56.0)) * (0.7 + float(level) * 0.12)),
			Color("#FFAA00"), self,
			str(impact_cfg.get("asset", "")),
			str(impact_cfg.get("asset_anim", "res://assets/vfx/mine_explosion.tres")),
			-1.0, 0.12, maxf(0.05, float(impact_cfg.get("duration", 0.2))), false)
		if _boss_node and is_instance_valid(_boss_node):
			VFXManager.flash_sprite(_boss_node, Color(1.6, 1.6, 1.6), 0.08)
		if bool(ProfileManager.get_setting("screenshake_enabled", true)):
			VFXManager.screen_shake(2 + mini(level, 6), 0.2)
	# Dégâts % du niveau, divisés par le knob de difficulté boss_toughness_mult.
	# Décharge [B6] : dégâts BRUTS fixés (sans toughness — récompense fixe).
	# Boss enragé [E16] : dégâts de tap amplifiés (contrepartie du sprint final).
	if damage_override > 0.0:
		_damage_boss(clampf(damage_override, 0.0, 1.0))
		return
	var pct: float = clampf(float(_level_cfg(level).get("boss_damage_percent", 0.0)), 0.0, 1.0)
	if _enraged:
		pct *= maxf(1.0, float(_get_conf("enrage_tap_damage_mult", 1.25)))
	_damage_boss(pct / _boss_toughness)

func _damage_boss(pct: float) -> void:
	if _state == State.BOSS_DEATH or _state == State.BOSS_ESCAPE or _state == State.DONE:
		return
	_boss_health = clampf(_boss_health - pct, 0.0, 1.0)
	if _hud and is_instance_valid(_hud) and _hud.has_method("update_boss_health"):
		_hud.call("update_boss_health", int(round(_boss_health * 1000.0)), 1000)
	# Boss enragé [E16] : sous le seuil, patterns/tirs ×2 mais tap ×1.25.
	if not _enraged and bool(_get_conf("enrage_enabled", true)) and _boss_health > 0.0 \
		and _boss_health <= clampf(float(_get_conf("enrage_health_ratio", 0.25)), 0.0, 1.0):
		_enraged = true
		var interval_mult: float = clampf(float(_get_conf("enrage_pattern_interval_mult", 0.5)), 0.2, 1.0)
		_pattern_interval = maxf(2.0, _pattern_interval * interval_mult)
		_boss_shot_interval = maxf(1.5, _boss_shot_interval * interval_mult)
		_toast("suika_enraged", "BOSS ENRAGED!", "#FF6666")
		if _boss_sprite and is_instance_valid(_boss_sprite):
			_boss_sprite.modulate = Color(str(_get_conf("enrage_boss_tint", "#FF6666")))
	if _boss_health <= 0.0:
		_start_boss_death()

# =============================================================================
# BOSS PATTERNS (data : drop_junk / gravity_pulse / attack_beam)
# =============================================================================

func _update_boss_patterns(delta: float) -> void:
	if not _patterns_enabled or _boss_patterns.is_empty():
		return
	if _beam_active:
		_update_beam(delta)
		return
	_pattern_timer -= delta
	if _pattern_timer <= 0.0:
		_pattern_timer = _pattern_interval
		_run_boss_pattern()

func _run_boss_pattern() -> void:
	var total: float = 0.0
	for pattern_v in _boss_patterns:
		if pattern_v is Dictionary:
			total += maxf(0.0, float((pattern_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return
	var roll: float = randf() * total
	var chosen: Dictionary = {}
	for pattern_v in _boss_patterns:
		if not (pattern_v is Dictionary):
			continue
		roll -= maxf(0.0, float((pattern_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			chosen = pattern_v as Dictionary
			break
	match str(chosen.get("id", "")):
		"drop_junk":
			_pattern_drop_junk(chosen)
		"gravity_pulse":
			_pattern_gravity_pulse(chosen)
		"attack_beam":
			_pattern_attack_beam(chosen)
		_:
			pass

## Pattern legacy (hors data par défaut — remplacé par les bombes) : le boss
## encombre la cuve avec des formes junk inertes.
func _pattern_drop_junk(cfg: Dictionary) -> void:
	var count: int = clampi(int(cfg.get("junk_count", 2)), 1, 8)
	for _i in range(count):
		if _shapes.size() >= _max_shapes_active:
			break
		var pos := Vector2(
			clampf(_boss_center.x + randf_range(-120.0, 120.0), _reactor_rect.position.x + _junk_radius, _reactor_rect.end.x - _junk_radius),
			_reactor_rect.position.y + _junk_radius + 6.0)
		var junk: Dictionary = _create_shape_body(1, pos, "junk", false)
		var body: RigidBody2D = junk.get("body") as RigidBody2D
		body.linear_velocity = Vector2(randf_range(-80.0, 80.0), 160.0)
		_shapes.append(junk)
	if VFXManager and _boss_node and is_instance_valid(_boss_node):
		VFXManager.spawn_impact(_boss_node.position + Vector2(0.0, _boss_visual_size.y * 0.4), 12.0, self)

# =============================================================================
# BOMBES DU BOSS (tir périodique, fusion entre elles, lvl max = explosion)
# =============================================================================

## Tir TÉLÉGRAPHIÉ : à l'échéance du timer, un compte à rebours
## (boss_shot_telegraph_sec) s'affiche avec le NIVEAU DE CONTRE requis
## (boss_shot_counter_min/max_level — le niveau max n'apparaît qu'après
## boss_shot_counter_high_after_sec, le joueur n'a pas encore pu le créer
## avant). Consommer une forme >= niveau requis pendant le télégraphe ANNULE
## le tir ; sinon le boss largue UNE bombe niveau 1 qui entre par le haut et
## "retombe" vers le HAUT (gravité inversée) dans la pile.
func _boss_shot_update(delta: float) -> void:
	if _rage_active or _rage_bombs_left > 0:
		return # colère du boss [E15] : le burst remplace le tir normal
	if _shot_telegraph_active:
		_update_shot_telegraph(delta)
		return
	_boss_shot_timer -= delta
	if _boss_shot_timer > 0.0:
		return
	_boss_shot_timer = _boss_shot_interval + randf_range(0.0, _boss_shot_jitter)
	# Niveau de contre : plafonné à max-1 tant que le joueur n'a pas eu le
	# temps de fabriquer le niveau max.
	var high_cap: int = _shot_counter_max_level if _elapsed >= _shot_counter_high_after_sec else maxi(_shot_counter_min_level, _shot_counter_max_level - 1)
	_shot_required_level = randi_range(_shot_counter_min_level, high_cap)
	_shot_telegraph_active = true
	_shot_telegraph_timer = _boss_shot_telegraph_sec

## Compte à rebours affiché SUR le boss : chiffre seul (le hint de zone a déjà
## expliqué le contre au joueur), léger pulse d'échelle.
func _update_shot_telegraph(delta: float) -> void:
	_shot_telegraph_timer -= delta
	if _boss_shot_label and is_instance_valid(_boss_shot_label):
		_boss_shot_label.text = str(int(ceil(maxf(0.0, _shot_telegraph_timer))))
		_boss_shot_label.visible = true
		var pulse: float = 1.0 + 0.12 * sin(_elapsed * 10.0)
		_boss_shot_label.scale = Vector2.ONE * pulse
	if _shot_telegraph_timer <= 0.0:
		_shot_telegraph_active = false
		_hide_boss_shot_label()
		_fire_boss_bomb()

func _hide_boss_shot_label() -> void:
	if _boss_shot_label and is_instance_valid(_boss_shot_label):
		_boss_shot_label.visible = false

## Contre réussi : un tir de niveau suffisant (uniformisé 2+) annule le largage.
## Colère du boss [E15] : UN contre pendant le télégraphe annule TOUT le burst.
func _try_counter_boss_shot(fired_level: int) -> void:
	if _rage_active and fired_level >= _shot_required_level:
		_rage_active = false
		_rage_bombs_left = 0
		_hide_boss_shot_label()
		if _boss_shot_label and is_instance_valid(_boss_shot_label):
			_boss_shot_label.modulate = Color.WHITE
		_show_warning(_translate_or("suika_up_beam_countered", "COUNTERED!"), Color("#7FE58C"), 1.0)
		return
	if not _shot_telegraph_active or fired_level < _shot_required_level:
		return
	_shot_telegraph_active = false
	_hide_boss_shot_label()
	_show_warning(_translate_or("suika_up_beam_countered", "COUNTERED!"), Color("#7FE58C"), 1.0)

func _fire_boss_bomb() -> void:
	if _shapes.size() >= _max_shapes_active:
		return
	var radius: float = maxf(6.0, float(_bomb_level_cfg(1).get("radius_px", 16.0)))
	var pos := Vector2(
		clampf(_boss_center.x + randf_range(-140.0, 140.0), _reactor_rect.position.x + radius, _reactor_rect.end.x - radius),
		_reactor_rect.position.y + radius + 4.0)
	var bomb: Dictionary = _create_shape_body(1, pos, "bomb", false)
	var body: RigidBody2D = bomb.get("body") as RigidBody2D
	body.linear_velocity = Vector2(randf_range(-60.0, 60.0), randf_range(220.0, 340.0))
	_shapes.append(bomb)
	if VFXManager and _boss_node and is_instance_valid(_boss_node):
		VFXManager.spawn_impact(_boss_node.position + Vector2(0.0, _boss_visual_size.y * 0.4), 12.0, self)

## Bombe au niveau max : compte à rebours affiché sur la bombe, puis explosion.
func _arm_bomb(entry: Dictionary) -> void:
	entry["bomb_timer"] = _boss_bomb_countdown_sec
	var body: RigidBody2D = entry.get("body") as RigidBody2D
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(14, int(float(entry.get("radius", 30.0)) * 0.9)))
	label.add_theme_color_override("font_color", Color("#FFFFFF"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.size = Vector2(80.0, 40.0)
	label.position = Vector2(-40.0, -20.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	body.add_child(label)
	entry["bomb_label"] = label

func _update_bombs(delta: float) -> void:
	for i in range(_shapes.size() - 1, -1, -1):
		var entry: Dictionary = _shapes[i]
		var timer: float = float(entry.get("bomb_timer", -1.0))
		if timer < 0.0:
			continue
		timer -= delta
		entry["bomb_timer"] = timer
		var label_v: Variant = entry.get("bomb_label", null)
		if label_v is Label and is_instance_valid(label_v):
			(label_v as Label).text = str(int(ceil(maxf(0.0, timer))))
		if timer <= 0.0:
			_shapes.remove_at(i)
			_explode_bomb(entry)

## Explosion de bombe : souffle radial sur toutes les formes proches (dans
## tous les sens) + gros dégâts au joueur (boss_bomb_damage_percent).
func _explode_bomb(entry: Dictionary) -> void:
	var body: RigidBody2D = entry.get("body") as RigidBody2D
	var center: Vector2 = body.global_position if is_instance_valid(body) else _reactor_rect.get_center()
	for other_v in _shapes:
		var other_body: RigidBody2D = (other_v as Dictionary).get("body") as RigidBody2D
		if not is_instance_valid(other_body):
			continue
		var d: Vector2 = other_body.global_position - center
		var dist: float = d.length()
		if dist > _boss_bomb_blast_radius:
			continue
		other_body.sleeping = false
		var dir: Vector2 = d / dist if dist > 1.0 else Vector2.UP.rotated(randf() * TAU)
		var falloff: float = 1.0 - dist / _boss_bomb_blast_radius
		other_body.apply_central_impulse(dir * _boss_bomb_blast_impulse * (0.4 + 0.6 * falloff) * other_body.mass)
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * _boss_bomb_damage_pct))))
	if VFXManager:
		VFXManager.spawn_explosion(center, _boss_bomb_blast_radius * 0.6, Color("#FF3B3B"), self,
			"", "res://assets/vfx/boss_explosion.tres", -1.0, 0.25, 0.3, false)
		if bool(ProfileManager.get_setting("screenshake_enabled", true)):
			VFXManager.screen_shake(10, 0.4)
	_free_shape(entry, false)

## Défaite du boss : la zone est entièrement vidée (formes du joueur ET
## bombes), petites explosions échelonnées visuelles.
func _clear_reactor() -> void:
	for i in range(_shapes.size() - 1, -1, -1):
		var entry: Dictionary = _shapes[i]
		_shapes.remove_at(i)
		_free_shape(entry, true)
	_merge_pairs.clear()
	# Pickups et états d'événements purgés avec la zone.
	for p_v in _pickups:
		var node_v: Variant = (p_v as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_pickups.clear()
	_stasis_timer = 0.0
	_rage_active = false
	_rage_bombs_left = 0
	_gravity_outage_telegraph = 0.0
	_gravity_outage_timer = 0.0
	_gravity_mult = 1.0
	_tilt_timer = 0.0
	if _danger_warning_rect and is_instance_valid(_danger_warning_rect):
		_danger_warning_rect.visible = false

## Secousse : impulsion radiale sur toutes les formes.
func _pattern_gravity_pulse(cfg: Dictionary) -> void:
	var strength: float = maxf(0.0, float(cfg.get("impulse_strength", 180.0)))
	var center: Vector2 = _reactor_rect.get_center()
	for entry_v in _shapes:
		var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
		body.sleeping = false
		var dir: Vector2 = (body.global_position - center)
		dir = dir.normalized() if dir.length_squared() > 1.0 else Vector2.UP
		body.apply_central_impulse(dir * strength * body.mass)
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(6, 0.3)

## Rayon télégraphié boss -> vaisseau : consommer une forme lvl >=
## counter_min_level pendant le télégraphe annule l'attaque, sinon dégâts.
func _pattern_attack_beam(cfg: Dictionary) -> void:
	_beam_active = true
	_beam_cfg = cfg
	_beam_timer = maxf(0.5, float(cfg.get("telegraph_sec", 3.0)))
	_beam_line = Line2D.new()
	_beam_line.width = 6.0
	_beam_line.default_color = Color("#FF5555AA")
	_beam_line.material = _add_material
	_beam_line.z_as_relative = false
	_beam_line.z_index = 16
	var boss_pos: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
	_beam_line.points = PackedVector2Array([boss_pos, _ship_lock_pos])
	add_child(_beam_line)
	_show_warning(_translate_or("suika_up_beam_warning", "Counter with a lvl %d+ shot!") % int(cfg.get("counter_min_level", 3)), Color("#FF8844"), _beam_timer)

func _update_beam(delta: float) -> void:
	_beam_timer -= delta
	if _beam_line and is_instance_valid(_beam_line):
		_beam_line.modulate.a = lerpf(0.35, 1.0, 0.5 + 0.5 * sin(_elapsed * 14.0))
		if _player and is_instance_valid(_player):
			var boss_pos: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
			_beam_line.points = PackedVector2Array([boss_pos, _player.global_position])
	if _beam_timer <= 0.0:
		# Non contré : l'attaque touche le vaisseau.
		var pct: float = clampf(float(_beam_cfg.get("damage_percent", 0.18)), 0.0, 1.0)
		if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
			var max_hp_v: Variant = _player.get("max_hp")
			var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
			_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
		if VFXManager:
			VFXManager.spawn_explosion(_ship_lock_pos, 46.0, Color("#FF5555"), self, "", "res://assets/vfx/mine_explosion.tres", -1.0, 0.15, 0.2, false)
			if bool(ProfileManager.get_setting("screenshake_enabled", true)):
				VFXManager.screen_shake(8, 0.3)
		_cancel_beam(false)

func _cancel_beam(countered: bool) -> void:
	_beam_active = false
	_beam_cfg = {}
	if _beam_line and is_instance_valid(_beam_line):
		_beam_line.queue_free()
	_beam_line = null
	if countered:
		_show_warning(_translate_or("suika_up_beam_countered", "COUNTERED!"), Color("#7FE58C"), 1.0)

# =============================================================================
# PICKUPS [B1-5] — orbes non-physiques dans la bande médiane du réacteur,
# collectées au contact d'une forme joueur EN MOUVEMENT (le joueur les VISE).
# =============================================================================

func _tick_pickups(delta: float) -> void:
	if not bool(_get_conf("pickups_enabled", true)):
		return
	# TTL + bob sinusoïdal.
	for i in range(_pickups.size() - 1, -1, -1):
		var p: Dictionary = _pickups[i]
		p["ttl"] = float(p.get("ttl", 0.0)) - delta
		var node_v: Variant = p.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node: Node2D = node_v as Node2D
		node.position = (p.get("pos", Vector2.ZERO) as Vector2) \
			+ Vector2(0.0, sin(_elapsed * TAU * 0.6 + float(p.get("phase", 0.0))) * 6.0)
		if float(p["ttl"]) <= 1.0:
			node.modulate.a = clampf(float(p["ttl"]), 0.0, 1.0)
		if float(p["ttl"]) <= 0.0:
			node.queue_free()
			_pickups.remove_at(i)
	# Scheduler (anti-répétition).
	_pickup_timer -= delta
	if _pickup_timer > 0.0:
		return
	_pickup_timer = randf_range(
		maxf(2.0, float(_get_conf("pickup_interval_sec_min", 9.0))),
		maxf(2.0, float(_get_conf("pickup_interval_sec_max", 15.0))))
	if _pickups.size() >= maxi(1, int(_get_conf("pickup_max_active", 1))):
		return
	var types_v: Variant = _get_conf("pickup_types", [])
	var types: Array = (types_v as Array) if types_v is Array else []
	if types.is_empty():
		return
	var total: float = 0.0
	for t_v in types:
		if t_v is Dictionary and str((t_v as Dictionary).get("id", "")) != _last_pickup_id:
			total += maxf(0.0, float((t_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		_last_pickup_id = "" # un seul type configuré : lever l'anti-répétition
		return
	var roll: float = randf() * total
	for t_v in types:
		if not (t_v is Dictionary) or str((t_v as Dictionary).get("id", "")) == _last_pickup_id:
			continue
		roll -= maxf(0.0, float((t_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			_spawn_pickup(t_v as Dictionary)
			return

func _spawn_pickup(cfg: Dictionary) -> void:
	_last_pickup_id = str(cfg.get("id", ""))
	var radius: float = maxf(10.0, float(_get_conf("pickup_radius_px", 18.0)))
	var node := Node2D.new()
	node.name = "SuikaPickup"
	node.z_as_relative = false
	node.z_index = 12
	var color := Color(str(cfg.get("color", "#FFFFFFFF")))
	var tex: Texture2D = _texture_from_path(str(cfg.get("asset", "")))
	if tex != null and tex.get_size().x > 0.0:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2.ONE * (radius * 2.0 / maxf(tex.get_size().x, tex.get_size().y))
		node.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(16):
			var a: float = TAU * float(k) / 16.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		poly.polygon = pts
		poly.color = color
		node.add_child(poly)
		var glyph := Label.new()
		glyph.text = str(cfg.get("id", "?")).substr(0, 1).to_upper()
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(radius * 1.1))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(radius, radius) * 2.0
		glyph.position = -Vector2(radius, radius)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(glyph)
	# Halo additif + label d'effet (béquille lisibilité).
	var halo := Line2D.new()
	halo.closed = true
	halo.width = 3.0
	halo.default_color = Color(color.r, color.g, color.b, 0.7)
	halo.material = _add_material
	var halo_pts := PackedVector2Array()
	for k in range(16):
		var a2: float = TAU * float(k) / 16.0
		halo_pts.append(Vector2(cos(a2), sin(a2)) * (radius + 4.0))
	halo.points = halo_pts
	node.add_child(halo)
	if _effect_labels_enabled():
		_attach_effect_label(node, _translate_or(str(cfg.get("label_key", "")), str(cfg.get("id", "")).to_upper()), radius * 2.0, color)
	# Bande médiane : traversée par les lancers, au-dessus de la redline.
	var pos := Vector2(
		randf_range(_reactor_rect.position.x + 60.0, _reactor_rect.end.x - 60.0),
		randf_range(_reactor_rect.position.y + _reactor_rect.size.y * 0.35, _redline_y - 80.0))
	node.position = pos
	add_child(node)
	_pickups.append({
		"node": node,
		"cfg": cfg,
		"pos": pos,
		"ttl": maxf(3.0, float(_get_conf("pickup_lifetime_sec", 8.0))),
		"phase": randf() * TAU
	})

## Collecte : une forme joueur EN MOUVEMENT touche l'orbe (scan physique —
## l'orbe n'est pas un body, le free est sûr).
func _scan_pickup_collection() -> void:
	if _pickups.is_empty():
		return
	var min_speed_sq: float = pow(maxf(20.0, float(_get_conf("pickup_collect_min_speed", 140.0))), 2.0)
	var pickup_radius: float = maxf(10.0, float(_get_conf("pickup_radius_px", 18.0)))
	for i in range(_pickups.size() - 1, -1, -1):
		var p: Dictionary = _pickups[i]
		var node_v: Variant = p.get("node", null)
		if not (node_v is Node2D) or not is_instance_valid(node_v):
			_pickups.remove_at(i)
			continue
		var node_pos: Vector2 = (node_v as Node2D).global_position
		for entry_v in _shapes:
			var entry: Dictionary = entry_v as Dictionary
			if str(entry.get("kind", "normal")) != "normal" or bool(entry.get("merging", false)):
				continue
			var body: RigidBody2D = entry.get("body") as RigidBody2D
			if body.freeze or body.linear_velocity.length_squared() < min_speed_sq:
				continue
			if body.global_position.distance_squared_to(node_pos) \
				<= pow(pickup_radius + float(entry.get("radius", 14.0)), 2.0):
				(node_v as Node2D).queue_free()
				_pickups.remove_at(i)
				_apply_pickup(p.get("cfg", {}) as Dictionary, node_pos)
				break

func _apply_pickup(cfg: Dictionary, at: Vector2) -> void:
	var id: String = str(cfg.get("id", ""))
	match id:
		"purge":
			_purge_lowest_shapes(maxi(1, int(cfg.get("purge_count", 3))), true)
		"perfect_boost":
			_perfect_boost_left = maxi(_perfect_boost_left, maxi(1, int(cfg.get("launches", 3))))
			_perfect_window_mult = maxf(1.0, float(cfg.get("window_mult", 2.0)))
		"double_shot":
			_double_shot_armed = true
			_double_shot_fan_deg = maxf(2.0, float(cfg.get("fan_deg", 14.0)))
		"stasis":
			_begin_stasis(maxf(0.5, float(cfg.get("duration_sec", 3.0))))
		"grapple":
			_grapple_charges += maxi(1, int(cfg.get("charges", 2)))
	_show_warning(_translate_or(str(cfg.get("label_key", "")), id.to_upper()),
		Color(str(cfg.get("color", "#FFFFFFFF"))), 1.4)
	if VFXManager:
		VFXManager.spawn_impact(at, 22.0, self)
	_refresh_status_icons()

## Stase [B4] : gèle toute la pile (freeze STATIC = toujours collidable — les
## lancers pendant la stase rebondissent dessus), réveil global à la fin.
func _begin_stasis(duration: float) -> void:
	_stasis_timer = duration
	for entry_v in _shapes:
		var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
		if is_instance_valid(body):
			body.freeze = true

func _end_stasis() -> void:
	for entry_v in _shapes:
		var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
		if is_instance_valid(body):
			body.freeze = false
			body.sleeping = false

## Grappin [B5] : tire la forme visée d'un cran vers le BAS (réarrangement).
func _try_grapple(world: Vector2) -> void:
	var best: Dictionary = {}
	var best_dist: float = INF
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		if bool(entry.get("merging", false)):
			continue
		var kind: String = str(entry.get("kind", "normal"))
		if kind != "normal" and kind != "dark":
			continue
		var body: RigidBody2D = entry.get("body") as RigidBody2D
		var dist: float = world.distance_to(body.global_position)
		if dist <= float(entry.get("radius", 14.0)) * _click_hit_mult and dist < best_dist:
			best = entry
			best_dist = dist
	if best.is_empty():
		return
	_grapple_charges -= 1
	var target_body: RigidBody2D = best.get("body") as RigidBody2D
	target_body.freeze = false
	target_body.sleeping = false
	target_body.apply_central_impulse(Vector2(0.0, maxf(100.0, float(_get_conf("grapple_impulse", 620.0)))) * target_body.mass)
	_wake_shapes_near(target_body.global_position, float(best.get("radius", 14.0)) * 4.0)
	if VFXManager:
		VFXManager.spawn_impact(target_body.global_position, 18.0, self)
	_refresh_status_icons()

## Anneau de progression du tap long (grappin) — dessiné pendant PRESSED.
func _update_hold_ring() -> void:
	var hold_min: float = maxf(0.1, float(_get_conf("grapple_hold_min_sec", 0.45)))
	var want: bool = _gesture == Gesture.PRESSED and _grapple_charges > 0 \
		and _press_max_move <= _tap_max_move \
		and float(Time.get_ticks_msec() - _press_time_ms) / 1000.0 > 0.15
	if not want:
		if _hold_ring and is_instance_valid(_hold_ring):
			_hold_ring.visible = false
		return
	if _hold_ring == null or not is_instance_valid(_hold_ring):
		_hold_ring = Line2D.new()
		_hold_ring.width = 4.0
		_hold_ring.default_color = Color("#B48CFFDD")
		_hold_ring.material = _add_material
		_hold_ring.z_as_relative = false
		_hold_ring.z_index = 14
		add_child(_hold_ring)
	var progress: float = clampf((float(Time.get_ticks_msec() - _press_time_ms) / 1000.0) / hold_min, 0.0, 1.0)
	var pts := PackedVector2Array()
	var segs: int = maxi(3, int(round(20.0 * progress)))
	for k in range(segs + 1):
		var a: float = -PI * 0.5 + TAU * progress * float(k) / float(segs)
		pts.append(_aim_origin + Vector2(cos(a), sin(a)) * 34.0)
	_hold_ring.points = pts
	_hold_ring.visible = true

# =============================================================================
# DÉCHARGE DU VAISSEAU [B6] — jauge chargée par les fusions, bouton bas-gauche.
# =============================================================================

func _build_discharge_button() -> void:
	if not bool(_get_conf("discharge_enabled", true)):
		return
	var icon_px: float = maxf(30.0, float(_get_conf("discharge_icon_px", 56.0)))
	_discharge_pos = Vector2(_reactor_rect.position.x + icon_px * 0.5 + 10.0, _viewport_size.y - icon_px * 0.5 - 12.0)
	_discharge_root = Node2D.new()
	_discharge_root.name = "DischargeButton"
	_discharge_root.z_as_relative = false
	_discharge_root.z_index = 58
	_discharge_root.position = _discharge_pos
	var tex: Texture2D = _texture_from_path(str(_get_conf("discharge_icon_asset", "")))
	if tex != null and tex.get_size().x > 0.0:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2.ONE * (icon_px / maxf(tex.get_size().x, tex.get_size().y))
		_discharge_root.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(18):
			var a: float = TAU * float(k) / 18.0
			pts.append(Vector2(cos(a), sin(a)) * icon_px * 0.5)
		poly.polygon = pts
		poly.color = Color(0.1, 0.14, 0.22, 0.9)
		_discharge_root.add_child(poly)
		var bolt := Label.new()
		bolt.text = "⚡"
		bolt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bolt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bolt.add_theme_font_size_override("font_size", int(icon_px * 0.55))
		bolt.size = Vector2(icon_px, icon_px)
		bolt.position = -Vector2(icon_px, icon_px) * 0.5
		bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_discharge_root.add_child(bolt)
	# Remplissage vertical (0 -> 1) par-dessus l'icône, semi-transparent.
	_discharge_fill = ColorRect.new()
	_discharge_fill.color = Color(0.5, 0.9, 1.0, 0.35)
	_discharge_fill.size = Vector2(icon_px, 0.0)
	_discharge_fill.position = Vector2(-icon_px * 0.5, icon_px * 0.5)
	_discharge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discharge_root.add_child(_discharge_fill)
	# Halo « prêt » pulsant.
	var halo := Line2D.new()
	halo.closed = true
	halo.width = 4.0
	halo.default_color = Color("#66E0FFCC")
	halo.material = _add_material
	var halo_pts := PackedVector2Array()
	for k in range(20):
		var a2: float = TAU * float(k) / 20.0
		halo_pts.append(Vector2(cos(a2), sin(a2)) * (icon_px * 0.5 + 5.0))
	halo.points = halo_pts
	halo.visible = false
	_discharge_root.add_child(halo)
	_discharge_halo = halo
	add_child(_discharge_root)

func _gain_discharge(merge_level: int) -> void:
	if _discharge_root == null:
		return
	var gain: float = maxf(0.0, float(_get_conf("discharge_gain_per_merge", 0.05))) \
		+ maxf(0.0, float(_get_conf("discharge_gain_per_level_bonus", 0.02))) * maxf(0.0, float(merge_level - 2))
	var before: float = _discharge_value
	_discharge_value = clampf(_discharge_value + gain, 0.0, 1.0)
	if before < 1.0 and _discharge_value >= 1.0 and not _discharge_ready_announced:
		_discharge_ready_announced = true
		_show_warning(_translate_or("suika_discharge_ready", "DISCHARGE READY!"), Color("#66E0FF"), 1.6)

func _update_discharge_button() -> void:
	if _discharge_root == null or not is_instance_valid(_discharge_root):
		return
	var icon_px: float = maxf(30.0, float(_get_conf("discharge_icon_px", 56.0)))
	if _discharge_fill and is_instance_valid(_discharge_fill):
		var h: float = icon_px * _discharge_value
		_discharge_fill.size = Vector2(icon_px, h)
		_discharge_fill.position = Vector2(-icon_px * 0.5, icon_px * 0.5 - h)
	if _discharge_halo and is_instance_valid(_discharge_halo):
		_discharge_halo.visible = _discharge_value >= 1.0
		if _discharge_halo.visible:
			_discharge_halo.modulate.a = 0.55 + 0.45 * sin(_elapsed * TAU * 1.4)

## Tap sur le bouton (jauge pleine) : tir spécial à dégâts BRUTS (sans
## toughness — récompense fixe, cf. _readme du bloc suika_up).
func _discharge_hit(world: Vector2) -> bool:
	if _discharge_root == null or not is_instance_valid(_discharge_root) or _discharge_value < 1.0:
		return false
	var icon_px: float = maxf(30.0, float(_get_conf("discharge_icon_px", 56.0)))
	if world.distance_to(_discharge_pos) > icon_px * 0.7:
		return false
	_discharge_value = 0.0
	_discharge_ready_announced = false
	_show_warning(_translate_or("suika_discharge_fired", "DISCHARGE!"), Color("#66E0FF"), 1.2)
	_fire_ship_shot(_max_level, clampf(float(_get_conf("discharge_damage_percent", 0.10)), 0.0, 1.0))
	return true

# =============================================================================
# ICÔNES DE STATUT bas-droite (au-dessus du NEXT panel) : effets de pickups.
# =============================================================================

func _refresh_status_icons() -> void:
	var active: Dictionary = {} # id -> badge
	if _perfect_boost_left > 0:
		active["perfect_boost"] = "×%d" % _perfect_boost_left
	if _double_shot_armed:
		active["double_shot"] = "1"
	if _grapple_charges > 0:
		active["grapple"] = "×%d" % _grapple_charges
	if _stasis_timer > 0.0:
		active["stasis"] = str(int(ceil(_stasis_timer)))
	for id in _status_icons.keys().duplicate():
		if not active.has(id):
			var icon: Dictionary = _status_icons[id]
			var root_v: Variant = icon.get("root", null)
			if root_v is Node2D and is_instance_valid(root_v):
				(root_v as Node2D).queue_free()
			_status_icons.erase(id)
	var slot: int = 0
	for id in active:
		if not _status_icons.has(id):
			_status_icons[id] = _build_status_icon(str(id))
		var icon2: Dictionary = _status_icons[id]
		var root2_v: Variant = icon2.get("root", null)
		if root2_v is Node2D and is_instance_valid(root2_v):
			(root2_v as Node2D).position = Vector2(_viewport_size.x - 54.0, _viewport_size.y - 108.0 - 62.0 * float(slot))
		var badge_v: Variant = icon2.get("badge", null)
		if badge_v is Label and is_instance_valid(badge_v):
			(badge_v as Label).text = str(active[id])
		slot += 1

func _build_status_icon(id: String) -> Dictionary:
	var cfg: Dictionary = {}
	var types_v: Variant = _get_conf("pickup_types", [])
	if types_v is Array:
		for t_v in (types_v as Array):
			if t_v is Dictionary and str((t_v as Dictionary).get("id", "")) == id:
				cfg = t_v as Dictionary
				break
	var radius: float = 22.0
	var color := Color(str(cfg.get("color", "#FFFFFFFF")))
	var root := Node2D.new()
	root.z_as_relative = false
	root.z_index = 61
	var tex: Texture2D = _texture_from_path(str(cfg.get("asset", "")))
	if tex != null and tex.get_size().x > 0.0:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2.ONE * (radius * 2.0 / maxf(tex.get_size().x, tex.get_size().y))
		root.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in range(16):
			var a: float = TAU * float(k) / 16.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		poly.polygon = pts
		poly.color = Color(color.r, color.g, color.b, 0.85)
		root.add_child(poly)
		var glyph := Label.new()
		glyph.text = id.substr(0, 1).to_upper()
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(radius))
		glyph.add_theme_color_override("font_color", Color(0.08, 0.08, 0.14))
		glyph.size = Vector2(radius, radius) * 2.0
		glyph.position = -Vector2(radius, radius)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(glyph)
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 4)
	badge.size = Vector2(radius * 2.0, 18.0)
	badge.position = Vector2(-radius, radius + 1.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badge)
	add_child(root)
	return {"root": root, "badge": badge}

# =============================================================================
# ÉVÉNEMENTS RÉACTEUR [E15/17/18] + BOSS SUPPORT [E20] + MAGNÉTISME [V12]
# =============================================================================

func _any_reactor_event_active() -> bool:
	return _rage_active or _rage_bombs_left > 0 or _gravity_outage_telegraph > 0.0 \
		or _gravity_outage_timer > 0.0 or _tilt_timer > 0.0

func _tick_reactor_events(delta: float) -> void:
	# Rage [E15] : télégraphe puis burst échelonné (un contre annule tout).
	if _rage_active:
		_rage_telegraph -= delta
		if _boss_shot_label and is_instance_valid(_boss_shot_label):
			_boss_shot_label.text = "×%d %d" % [maxi(1, int(_rage_cfg_value("bomb_count", 3.0))), int(ceil(maxf(0.0, _rage_telegraph)))]
			_boss_shot_label.visible = true
			_boss_shot_label.modulate = Color("#FF5555")
		if _rage_telegraph <= 0.0:
			_rage_active = false
			_hide_boss_shot_label()
			if _boss_shot_label and is_instance_valid(_boss_shot_label):
				_boss_shot_label.modulate = Color.WHITE
			_rage_bombs_left = maxi(1, int(_rage_cfg_value("bomb_count", 3.0)))
			_rage_stagger_timer = 0.0
	elif _rage_bombs_left > 0:
		_rage_stagger_timer -= delta
		if _rage_stagger_timer <= 0.0:
			_rage_stagger_timer = maxf(0.1, _rage_cfg_value("bomb_stagger_sec", 0.4))
			_rage_bombs_left -= 1
			_fire_boss_bomb()
	# Panne de gravité [E17].
	if _gravity_outage_telegraph > 0.0:
		_gravity_outage_telegraph -= delta
		if _gravity_outage_telegraph <= 0.0:
			_gravity_mult = 0.0
			_gravity_outage_timer = maxf(0.5, _event_cfg_value("gravity_outage", "duration_sec", 2.0))
			for entry_v in _shapes:
				var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
				if is_instance_valid(body) and not body.freeze:
					body.gravity_scale = 0.0
					body.sleeping = false
	elif _gravity_outage_timer > 0.0:
		_gravity_outage_timer -= delta
		if _gravity_outage_timer <= 0.0:
			_gravity_mult = 1.0
			for entry_v in _shapes:
				var body2: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
				if is_instance_valid(body2):
					body2.gravity_scale = -absf(_gravity_scale)
					body2.sleeping = false
	# Réacteur penché [E18] : constant_force posée une fois, retirée à la fin.
	if _tilt_timer > 0.0:
		_tilt_timer -= delta
		if _tilt_timer <= 0.0:
			for entry_v in _shapes:
				var body3: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
				if is_instance_valid(body3):
					body3.constant_force = Vector2.ZERO
					body3.sleeping = false
	# Scheduler : un seul événement actif, jamais pendant un télégraphe en cours.
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(
		maxf(6.0, float(_get_conf("reactor_event_interval_sec_min", 14.0))),
		maxf(6.0, float(_get_conf("reactor_event_interval_sec_max", 22.0))))
	if not bool(_get_conf("reactor_events_enabled", true)) or _any_reactor_event_active() \
		or _shot_telegraph_active or _beam_active:
		return
	var events_v: Variant = _get_conf("reactor_events", [])
	var events: Array = (events_v as Array) if events_v is Array else []
	var total: float = 0.0
	for e_v in events:
		if e_v is Dictionary and str((e_v as Dictionary).get("id", "")) != _last_event_id:
			total += maxf(0.0, float((e_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		_last_event_id = ""
		return
	var roll: float = randf() * total
	for e_v in events:
		if not (e_v is Dictionary) or str((e_v as Dictionary).get("id", "")) == _last_event_id:
			continue
		roll -= maxf(0.0, float((e_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			_start_reactor_event(e_v as Dictionary)
			return

func _event_cfg_value(event_id: String, key: String, fallback: float) -> float:
	var events_v: Variant = _get_conf("reactor_events", [])
	if events_v is Array:
		for e_v in (events_v as Array):
			if e_v is Dictionary and str((e_v as Dictionary).get("id", "")) == event_id:
				return float((e_v as Dictionary).get(key, fallback))
	return fallback

func _rage_cfg_value(key: String, fallback: float) -> float:
	return _event_cfg_value("boss_rage", key, fallback)

func _start_reactor_event(cfg: Dictionary) -> void:
	var id: String = str(cfg.get("id", ""))
	_last_event_id = id
	match id:
		"boss_rage":
			_toast("suika_event_rage", "BOSS RAGE!", "#FF5555")
			_rage_active = true
			_rage_telegraph = maxf(1.0, float(cfg.get("telegraph_sec", 4.0)))
			var high_cap: int = _shot_counter_max_level if _elapsed >= _shot_counter_high_after_sec \
				else maxi(_shot_counter_min_level, _shot_counter_max_level - 1)
			_shot_required_level = randi_range(_shot_counter_min_level, high_cap)
		"gravity_outage":
			_toast("suika_event_gravity_outage", "ZERO GRAVITY!", "#9BE8FF")
			_gravity_outage_telegraph = maxf(0.3, float(cfg.get("telegraph_sec", 1.5)))
		"tilted_reactor":
			_toast("suika_event_tilt", "TILTED REACTOR!", "#FF8844")
			_tilt_dir = 1.0 if randf() < 0.5 else -1.0
			_tilt_timer = maxf(2.0, float(cfg.get("duration_sec", 8.0)))
			var force: float = _current_tilt_force()
			for entry_v in _shapes:
				var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
				if is_instance_valid(body) and not body.freeze:
					body.constant_force = Vector2(_tilt_dir * force, 0.0) * body.mass
					body.sleeping = false

func _current_tilt_force() -> float:
	return maxf(0.0, _event_cfg_value("tilted_reactor", "tilt_force", 260.0))

## Bombes magnétiques [V12] : les bombes ARMÉES (countdown) attirent les formes
## voisines — appelé en _physics_process (forces côté physique), borné aux
## bombes armées (≤ 1-2 simultanées).
func _apply_bomb_magnets() -> void:
	if not bool(_get_conf("bomb_magnet_enabled", true)):
		return
	var radius: float = maxf(20.0, float(_get_conf("bomb_magnet_radius_px", 150.0)))
	var strength: float = maxf(0.0, float(_get_conf("bomb_magnet_strength", 240.0)))
	if strength <= 0.0:
		return
	for entry_v in _shapes:
		var entry: Dictionary = entry_v as Dictionary
		if float(entry.get("bomb_timer", -1.0)) < 0.0:
			continue # seules les bombes ARMÉES sont magnétiques
		var bomb_body: RigidBody2D = entry.get("body") as RigidBody2D
		if not is_instance_valid(bomb_body):
			continue
		var center: Vector2 = bomb_body.global_position
		for other_v in _shapes:
			var other: Dictionary = other_v as Dictionary
			if other == entry or str(other.get("kind", "normal")) == "bomb":
				continue
			var other_body: RigidBody2D = other.get("body") as RigidBody2D
			if not is_instance_valid(other_body) or other_body.freeze:
				continue
			var d: Vector2 = center - other_body.global_position
			var dist: float = d.length()
			if dist > radius or dist < 2.0:
				continue
			other_body.sleeping = false
			other_body.apply_central_force(d / dist * strength * (1.0 - dist / radius) * other_body.mass)

## Boss support [E20] : à mi-round (Libre hauts levels), un second boss mineur
## arrive et largue ses propres bombes SANS télégraphe. Décoratif (pas de HP).
func _tick_support_boss(delta: float) -> void:
	if not _support_spawned:
		if not bool(_get_conf("support_boss_enabled", true)):
			return
		var free_progress: float = clampf(float(_config.get("_free_level_progress", 0.0)), 0.0, 1.0)
		if free_progress < clampf(float(_get_conf("support_boss_min_free_progress", 0.45)), 0.0, 1.0):
			return
		if _elapsed < _duration * clampf(float(_get_conf("support_boss_at_round_ratio", 0.5)), 0.05, 0.95):
			return
		_spawn_support_boss()
		return
	if _support_boss_node == null or not is_instance_valid(_support_boss_node):
		return
	_support_shot_timer -= delta
	if _support_shot_timer <= 0.0:
		_support_shot_timer = maxf(3.0, float(_get_conf("support_boss_shot_interval_sec", 9.0)))
		if _shapes.size() < _max_shapes_active:
			var radius: float = maxf(6.0, float(_bomb_level_cfg(1).get("radius_px", 16.0)))
			var x: float = clampf(_support_boss_node.position.x + randf_range(-60.0, 60.0),
				_reactor_rect.position.x + radius, _reactor_rect.end.x - radius)
			var bomb: Dictionary = _create_shape_body(1, Vector2(x, _reactor_rect.position.y + radius + 4.0), "bomb", false)
			(bomb.get("body") as RigidBody2D).linear_velocity = Vector2(randf_range(-40.0, 40.0), randf_range(200.0, 300.0))
			_shapes.append(bomb)
			if VFXManager:
				VFXManager.spawn_impact(_support_boss_node.position + Vector2(0.0, 40.0), 10.0, self)

func _spawn_support_boss() -> void:
	_support_spawned = true
	_toast("suika_event_support", "ENEMY REINFORCEMENT!", "#FF8844")
	_support_boss_node = Node2D.new()
	_support_boss_node.name = "SuikaSupportBoss"
	_support_boss_node.z_as_relative = false
	_support_boss_node.z_index = 9
	var fit: float = maxf(40.0, float(_get_conf("support_boss_fit_px", 120.0)))
	var frames: SpriteFrames = _frames_from_path(str(_get_conf("support_boss_asset_anim", "")))
	if frames != null:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		if VFXManager:
			VFXManager.play_sprite_frames(sprite, frames, &"default", true, 0.0)
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			var first: Texture2D = frames.get_frame_texture(names[0], 0)
			if first != null and first.get_size().x > 0.0:
				sprite.scale = Vector2.ONE * minf(fit / first.get_size().x, fit / first.get_size().y)
		_support_boss_node.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 - PI * 0.5
			pts.append(Vector2(cos(a), sin(a)) * fit * 0.5)
		poly.polygon = pts
		poly.color = Color("#9C4A4A")
		_support_boss_node.add_child(poly)
	add_child(_support_boss_node)
	var side: float = _viewport_size.x * clampf(float(_get_conf("support_boss_side_offset_x_ratio", 0.28)), 0.1, 0.45)
	var target := Vector2(_boss_center.x + side, _boss_center.y + 20.0)
	_support_boss_node.position = Vector2(target.x, -fit)
	var tween: Tween = create_tween()
	tween.tween_property(_support_boss_node, "position", target, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_support_shot_timer = maxf(3.0, float(_get_conf("support_boss_shot_interval_sec", 9.0)))

func _dismiss_support_boss() -> void:
	if _support_boss_node and is_instance_valid(_support_boss_node):
		var tween: Tween = create_tween()
		tween.tween_property(_support_boss_node, "position:y", -160.0, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(_support_boss_node.queue_free)
	_support_boss_node = null

## Fusion massive [E19] : onde qui compacte la pile vers le PLAFOND + cristaux.
func _trigger_massive_merge(center: Vector2) -> void:
	var impulse: float = maxf(0.0, float(_get_conf("massive_merge_impulse", 320.0)))
	for entry_v in _shapes:
		var body: RigidBody2D = (entry_v as Dictionary).get("body") as RigidBody2D
		if not is_instance_valid(body) or body.freeze:
			continue
		body.sleeping = false
		var falloff: float = clampf(1.0 - body.global_position.distance_to(center) / (_reactor_rect.size.y * 0.9), 0.2, 1.0)
		body.apply_central_impulse(Vector2(0.0, -impulse * falloff) * body.mass)
	_toast("suika_massive_merge", "MASSIVE MERGE!", "#FFD866")
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		for _i in range(maxi(1, int(_get_conf("massive_merge_crystals", 3)))):
			_game.call("spawn_reward_crystal_at", center, {"force_magnet_below_y": _ship_lock_pos.y - 60.0})
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(7, 0.3)

# =============================================================================
# FINS (mort / fuite du boss) + RÉCOMPENSES
# =============================================================================

func _start_boss_death() -> void:
	if _state == State.BOSS_DEATH or _state == State.DONE:
		return
	_state = State.BOSS_DEATH
	_state_timer = _boss_death_anim_sec
	_cancel_beam(false)
	_shot_telegraph_active = false
	_hide_boss_shot_label()
	_hide_aim_visuals()
	_dismiss_support_boss()
	_clear_reactor() # tout est vidé, bombes du boss comprises
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

## Timer écoulé : le boss s'en va, pas de bonus de kill.
func _start_boss_escape() -> void:
	if _state == State.BOSS_ESCAPE or _state == State.BOSS_DEATH or _state == State.DONE:
		return
	_state = State.BOSS_ESCAPE
	_state_timer = _boss_escape_anim_sec
	_cancel_beam(false)
	_shot_telegraph_active = false
	_hide_boss_shot_label()
	_hide_aim_visuals()
	_dismiss_support_boss()
	if _boss_node and is_instance_valid(_boss_node):
		var tween: Tween = create_tween()
		tween.tween_property(_boss_node, "position:y", -_boss_visual_size.y, _boss_escape_anim_sec) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

## Kill : gros score + cristaux + loot "uncommon ou +" — les drops sont
## aspirés par le vaisseau au franchissement d'une ligne Y, QUEL QUE SOIT
## leur x (force_magnet_below_y / auto_collect_below_y).
func _grant_kill_rewards() -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var center: Vector2 = _boss_node.position if (_boss_node and is_instance_valid(_boss_node)) else _boss_center
	_award_score(int(round(float(_kill_score) * _reward_multiplier)), center)
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
# VISÉE (pointillés) + JAUGE + NEXT PANEL + UI
# =============================================================================

func _build_trajectory_dots() -> void:
	var dot_radius: float = maxf(2.0, float(_trajectory_cfg.get("dot_radius_px", 4.0)))
	for _i in range(TRAJECTORY_DOT_POOL):
		var dot: Node2D
		if _trajectory_dot_texture != null:
			var sprite := Sprite2D.new()
			sprite.texture = _trajectory_dot_texture
			var tex_size: Vector2 = _trajectory_dot_texture.get_size()
			if tex_size.x > 0.0:
				sprite.scale = Vector2.ONE * (dot_radius * 2.0 / maxf(tex_size.x, tex_size.y))
			dot = sprite
		else:
			var poly := Polygon2D.new()
			var pts := PackedVector2Array()
			for j in range(10):
				var a: float = TAU * float(j) / 10.0
				pts.append(Vector2(cos(a), sin(a)) * dot_radius)
			poly.polygon = pts
			poly.color = Color.WHITE
			dot = poly
		dot.visible = false
		dot.z_as_relative = false
		dot.z_index = 13
		add_child(dot)
		_trajectory_dots.append(dot)

## Pointillés : origine visuelle = la forme prête, direction = aim_origin ->
## doigt, réflexion géométrique sur le premier mur latéral.
func _update_trajectory(launch: Dictionary) -> void:
	if not bool(_trajectory_cfg.get("enabled", true)) or _ready_shape.is_empty():
		_hide_trajectory()
		return
	var drag: Vector2 = _aim_current - _aim_origin
	if drag.length_squared() < 4.0:
		_hide_trajectory()
		return
	var color := Color(str(_trajectory_cfg.get("cancel_color", "#999999AA")))
	if bool(launch.get("blocked", false)):
		color = Color(str(_trajectory_cfg.get("danger_color", "#FF5555CC")))
	elif bool(launch.get("valid", false)):
		color = Color(str(_trajectory_cfg.get("valid_color", "#66CCFFFF")))
	var dir: Vector2 = (launch.get("direction", Vector2.UP) as Vector2) if bool(launch.get("valid", false)) else drag.normalized()
	var ready_body: RigidBody2D = _ready_shape.get("body") as RigidBody2D
	var pos: Vector2 = ready_body.global_position
	var spacing: float = maxf(6.0, float(_trajectory_cfg.get("dot_spacing_px", 18.0)))
	var max_len: float = maxf(spacing, float(_trajectory_cfg.get("max_length_px", 420.0)))
	var show_bounce: bool = bool(_trajectory_cfg.get("show_first_wall_bounce", true))
	var left_x: float = _reactor_rect.position.x
	var right_x: float = _reactor_rect.end.x
	var travelled: float = 0.0
	var current_dir: Vector2 = dir
	var bounced: bool = false
	for i in range(_trajectory_dots.size()):
		var dot: Node2D = _trajectory_dots[i]
		travelled += spacing
		if travelled > max_len:
			dot.visible = false
			continue
		pos += current_dir * spacing
		# Réflexion sur le premier mur latéral (pure géométrie).
		if not bounced and show_bounce:
			if pos.x < left_x:
				pos.x = left_x + (left_x - pos.x)
				current_dir.x = -current_dir.x
				bounced = true
			elif pos.x > right_x:
				pos.x = right_x - (pos.x - right_x)
				current_dir.x = -current_dir.x
				bounced = true
		if pos.y < _reactor_rect.position.y:
			dot.visible = false
			continue
		dot.global_position = pos
		dot.modulate = color
		dot.modulate.a = color.a * (1.0 - travelled / max_len * 0.6)
		dot.visible = true

func _hide_trajectory() -> void:
	for dot_v in _trajectory_dots:
		(dot_v as Node2D).visible = false

## Jauge de force verticale maison (cadre + fill vert->rouge + zone perfect +
## marqueur oscillant). Visible uniquement en visée.
func _build_power_gauge() -> void:
	_gauge_root = Control.new()
	_gauge_root.name = "PowerGauge"
	_gauge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_root.z_as_relative = false
	_gauge_root.z_index = 58
	var gauge_w: float = 18.0
	var gauge_h: float = 160.0
	_gauge_root.position = Vector2(_reactor_rect.position.x + 8.0, _reactor_rect.end.y - gauge_h - 16.0)
	_gauge_root.size = Vector2(gauge_w, gauge_h)
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.8)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.5, 0.6, 0.7, 0.8)
	sb.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_root.add_child(frame)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = Color(0.4, 0.9, 0.4, 0.5)
	_gauge_fill.position = Vector2(3.0, 3.0)
	_gauge_fill.size = Vector2(gauge_w - 6.0, gauge_h - 6.0)
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_root.add_child(_gauge_fill)
	# Zone "perfect" en haut de la jauge.
	var perfect_ratio: float = clampf(float(_gauge_cfg.get("perfect_window_ratio", 0.12)), 0.0, 1.0)
	_gauge_perfect = ColorRect.new()
	_gauge_perfect.color = Color(1.0, 0.95, 0.5, 0.55)
	_gauge_perfect.position = Vector2(3.0, 3.0)
	_gauge_perfect.size = Vector2(gauge_w - 6.0, (gauge_h - 6.0) * perfect_ratio)
	_gauge_perfect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_root.add_child(_gauge_perfect)
	_gauge_marker = ColorRect.new()
	_gauge_marker.color = Color.WHITE
	_gauge_marker.size = Vector2(gauge_w - 2.0, 3.0)
	_gauge_marker.position = Vector2(1.0, gauge_h - 6.0)
	_gauge_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_root.add_child(_gauge_marker)
	_gauge_root.visible = false
	add_child(_gauge_root)

## Ratio effectif de la fenêtre "perfect" (×window_mult pendant le boost [B2]).
func _effective_perfect_ratio() -> float:
	var ratio: float = clampf(float(_gauge_cfg.get("perfect_window_ratio", 0.12)), 0.0, 1.0)
	if _perfect_boost_left > 0:
		ratio = clampf(ratio * maxf(1.0, _perfect_window_mult), 0.0, 1.0)
	return ratio

func _update_power_gauge() -> void:
	if _gauge_root == null or not is_instance_valid(_gauge_root):
		return
	var should_show: bool = _gesture == Gesture.AIMING and bool(_gauge_cfg.get("enabled", true))
	_gauge_root.visible = should_show
	if not should_show:
		return
	var t: float = _gauge_t() # 0 = bas, 1 = haut (perfect)
	var height: float = _gauge_root.size.y - 6.0
	_gauge_marker.position.y = 3.0 + (1.0 - t) * (height - 3.0)
	_gauge_fill.color = Color(0.4, 0.9, 0.4, 0.5).lerp(Color(1.0, 0.3, 0.2, 0.55), t)
	# Zone perfect recalculée chaque frame (le boost [B2] l'élargit ×2).
	if _gauge_perfect and is_instance_valid(_gauge_perfect):
		_gauge_perfect.size.y = height * _effective_perfect_ratio()

func _hide_aim_visuals() -> void:
	_hide_trajectory()
	if _gauge_root and is_instance_valid(_gauge_root):
		_gauge_root.visible = false

## Encart NEXT bas-droite : cadre + label localisé + aperçu de la prochaine
## forme (cercle coloré réduit).
func _build_next_panel() -> void:
	var panel_w: float = 84.0
	var panel_h: float = 72.0
	var panel := Panel.new()
	panel.name = "NextPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(_viewport_size.x - panel_w - 12.0, _viewport_size.y - panel_h - 12.0)
	panel.size = Vector2(panel_w, panel_h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_as_relative = false
	panel.z_index = 58
	add_child(panel)
	var label := Label.new()
	label.text = _translate_or("suika_up_next", "NEXT")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#B8C4D0"))
	label.position = Vector2(0.0, 4.0)
	label.size = Vector2(panel_w, 16.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_next_preview = Polygon2D.new()
	_next_preview.position = Vector2(panel_w * 0.5, panel_h * 0.62)
	panel.add_child(_next_preview)
	_refresh_next_panel()

func _refresh_next_panel() -> void:
	if _next_preview == null or not is_instance_valid(_next_preview):
		return
	var lvl_cfg: Dictionary = _level_cfg(_next_level)
	var radius: float = clampf(float(lvl_cfg.get("radius_px", 14.0)) * 0.9, 8.0, 22.0)
	var pts := PackedVector2Array()
	for i in range(18):
		var a: float = TAU * float(i) / 18.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	_next_preview.polygon = pts
	_next_preview.color = Color(str(lvl_cfg.get("color", "#9BB8CC")))

## Bande translucide encadrée sur toute la zone du réacteur + message localisé
## (viser ici + contre des missiles avec une bombe 2+). Pulse d'alpha doux ;
## masquée définitivement au premier lancement réussi.
func _build_aim_zone_hint() -> void:
	if not bool(_get_conf("aim_zone_hint_enabled", true)):
		_aim_hint_dismissed = true
		return
	_aim_zone_panel = Panel.new()
	_aim_zone_panel.name = "AimZoneHint"
	_aim_zone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_zone_panel.z_as_relative = false
	_aim_zone_panel.z_index = 57
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(_get_conf("aim_zone_bg_color", "#8FD3FF14")))
	sb.border_color = Color(str(_get_conf("aim_zone_border_color", "#8FD3FF80")))
	var border_w: int = int(maxf(0.0, float(_get_conf("aim_zone_border_width_px", 2.0))))
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(int(maxf(0.0, float(_get_conf("aim_zone_corner_radius_px", 12.0)))))
	_aim_zone_panel.add_theme_stylebox_override("panel", sb)
	_aim_zone_panel.position = _reactor_rect.position
	_aim_zone_panel.size = _reactor_rect.size
	add_child(_aim_zone_panel)
	_aim_hint_label = Label.new()
	_aim_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aim_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aim_hint_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("aim_hint_font_size", 24))))
	_aim_hint_label.add_theme_color_override("font_color", Color(str(_get_conf("aim_hint_color", "#FFFFFF"))))
	_aim_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aim_hint_label.add_theme_constant_override("outline_size", 6)
	_aim_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_hint_label.z_as_relative = false
	_aim_hint_label.z_index = 58
	_aim_hint_label.text = _translate_or("suika_up_aim_hint",
		"Aim here: drag up to launch!\nCounter boss missiles with a lvl 2+ bomb")
	_aim_hint_label.position = _reactor_rect.position + Vector2(20.0, _reactor_rect.size.y * 0.32)
	_aim_hint_label.size = Vector2(_reactor_rect.size.x - 40.0, 90.0)
	add_child(_aim_hint_label)

## Pulse doux tant que le hint est affiché ; disparaît au premier lancement.
func _update_aim_zone_hint() -> void:
	if _aim_hint_dismissed:
		return
	var shown: bool = _state == State.PLAY or _state == State.INTRO
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.visible = shown
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.visible = shown
	if not shown:
		return
	var pulse_sec: float = maxf(0.1, float(_get_conf("aim_hint_pulse_sec", 1.2)))
	var alpha: float = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(TAU * _elapsed / pulse_sec))
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.modulate.a = alpha
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.modulate.a = alpha

func _dismiss_aim_zone_hint() -> void:
	if _aim_hint_dismissed:
		return
	_aim_hint_dismissed = true
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.visible = false
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.visible = false

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

func _ensure_countdown_label() -> void:
	# Le round a une vraie échéance (fuite du boss) : timer visible même en
	# mode libre (countdown_always_visible, data).
	if bool(_config.get("countdown_hidden", false)) and not bool(_get_conf("countdown_always_visible", false)):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "SuikaUpCountdownLabel"
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

## Timer de vague (départ du boss) : SOUS la barre de vie du boss (position
## réelle du BossHealthContainer du HUD, fallback countdown_y_ratio).
func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	_countdown_label.size = Vector2(_viewport_size.x, 34.0)
	var label_y: float = _viewport_size.y * clampf(float(_get_conf("countdown_y_ratio", 0.16)), 0.02, 0.9)
	if _hud and is_instance_valid(_hud):
		var container: Control = _hud.get_node_or_null("BossHealthContainer") as Control
		if container != null and container.visible:
			label_y = container.global_position.y + container.size.y + 4.0
	_countdown_label.position = Vector2(0.0, label_y)
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

func _ensure_warning_label() -> void:
	_warning_label = Label.new()
	_warning_label.name = "SuikaWarningLabel"
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 28)
	_warning_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_warning_label.add_theme_constant_override("outline_size", 6)
	_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_label.z_as_relative = false
	_warning_label.z_index = 60
	_warning_label.visible = false
	_warning_label.size = Vector2(_viewport_size.x, 40.0)
	_warning_label.position = Vector2(0.0, _reactor_rect.position.y - 48.0)
	add_child(_warning_label)

var _warning_timer: float = 0.0

func _show_warning(text: String, color: Color, duration: float = 1.6) -> void:
	if _warning_label == null or not is_instance_valid(_warning_label):
		return
	_warning_label.text = text
	_warning_label.add_theme_color_override("font_color", color)
	_warning_label.visible = true
	_warning_timer = duration

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
	_launch_cooldown = maxf(0.0, _launch_cooldown - delta)
	if _warning_timer > 0.0:
		_warning_timer -= delta
		if _warning_timer <= 0.0 and _warning_label and is_instance_valid(_warning_label):
			_warning_label.visible = false
	_update_countdown_label()
	_update_aim_zone_hint()
	_update_shots(delta)
	match _state:
		State.INTRO:
			_update_intro(delta)
		State.PLAY:
			if _ready_shape.is_empty() and _launch_cooldown <= 0.0:
				_spawn_ready_projectile()
			if _gesture == Gesture.AIMING:
				_aim_time += delta
				var launch: Dictionary = _evaluate_launch(_aim_current)
				_update_trajectory(launch)
				_update_power_gauge()
			# Stase [B4] : le boss et les bombes sont en pause pendant le gel.
			if _stasis_timer > 0.0:
				_stasis_timer -= delta
				_refresh_status_icons()
				if _stasis_timer <= 0.0:
					_end_stasis()
			else:
				_boss_shot_update(delta)
				_update_bombs(delta)
				_update_boss_patterns(delta)
			_massive_merge_cooldown = maxf(0.0, _massive_merge_cooldown - delta)
			_tick_pickups(delta)
			_tick_reactor_events(delta)
			_tick_support_boss(delta)
			_update_discharge_button()
			_update_hold_ring()
			if _elapsed >= _duration:
				_start_boss_escape()
		State.BOSS_DEATH:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()
		State.BOSS_ESCAPE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_finish()

var _intro_spawned: int = 0
var _intro_spawn_timer: float = 0.0
var _intro_phase: int = 0

func _update_intro(delta: float) -> void:
	match _intro_phase:
		0: # Arrivée du boss.
			_state_timer -= delta
			if _state_timer <= 0.0:
				_intro_phase = 1
				_intro_spawn_timer = 0.0
		1: # Spawn échelonné optionnel (zone VIDE par défaut : initial_shape_count 0).
			# Les formes entrent par le bas et montent (gravité inversée).
			_intro_spawn_timer -= delta
			if _intro_spawn_timer <= 0.0:
				_intro_spawn_timer = 0.12
				if _intro_spawned < _initial_shape_count:
					var pos := Vector2(
						randf_range(_reactor_rect.position.x + 40.0, _reactor_rect.end.x - 40.0),
						_reactor_rect.end.y - 30.0)
					var entry: Dictionary = _create_shape_body(_roll_next_level(), pos, "normal", false)
					(entry.get("body") as RigidBody2D).linear_velocity = Vector2(randf_range(-60.0, 60.0), -120.0)
					_shapes.append(entry)
					_intro_spawned += 1
				else:
					_intro_phase = 2
					_state_timer = _intro_settle_sec
		2: # Les formes se calent, puis le jeu commence.
			_state_timer -= delta
			if _state_timer <= 0.0:
				_spawn_ready_projectile()
				_state = State.PLAY

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	set_physics_process(false)
	# Restaure le joueur/HUD (barre boss comprise) AVANT de notifier la chaîne.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # murs, formes, boss, UI sont enfants -> libérés ensemble

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Défensif : restaure toujours joueur/HUD si le manager est libéré autrement.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
