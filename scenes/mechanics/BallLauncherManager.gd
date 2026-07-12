extends Node2D

## BallLauncherManager — Orchestre une vague "ball_launcher" (Holedown /
## Brick Breaker Journey) : le vaisseau se verrouille en bas (Y fixe, X libre =
## point de tir) et lance des volees de balles vers une grille de blocs
## numerotes (numero = coups restants). Tour par tour : visee (geste unique,
## drag vers le haut arme le laser predictif — rebonds sur murs ET blocs/boss)
## -> volee -> descente d'un cran + nouvelle rangee en haut (generation
## infinie, HP croissants). Jetons "+1 balle" dans les cases vides = armada
## permanente. Rangee qui franchit la ligne de danger = degats en % des HP max
## (shield d'abord), blocs detruits sans score.
##
## Structure façon Holedown : les blocs "tiennent" par le plafond (row 0) —
## couper le lien fait exploser en cascade tout ce qui pendait (récompense
## normale). Blocs spéciaux data-driven : sticky (reste en place, ancre
## locale), explosif (rase N cellules autour), chest (loot cristaux/équipement),
## et un BOSS 3×4 (HP massifs croissants, rebond selon sa shape
## round/square/star, défaite immédiate s'il atteint la ligne de danger).
##
## BLOCS BONUS/MALUS (2026-07-12, chances data + assets <type>_block_asset) :
## - BONUS (buff de volée à la destruction — cooldown global
##   bonus_block_cooldown_sec entre deux spawns, anti-répétition) :
##   lightning (prochaine volée perçante), bomb_charge (1re balle de la
##   prochaine volée explose au 1er impact), aim_plus (+1 rebond du laser
##   prédictif 3 tours), giant_ball (rayon ×2 prochaine volée), healer
##   (rend healer_heal_percent des HP max).
## - COMPORTEMENT : portal_in/portal_out (paire téléportante — la balle ressort
##   du jumeau, aucun dégât ; inoffensifs à la danger line), cursed (sa
##   destruction fait descendre la grille d'un cran ; inoffensif à la danger
##   line), mover (glisse d'une colonne par tour), armored (1 dégât max par
##   impact, HP fixes armored_hp).
## PATTERN_ROWS[] : rangées scriptées par vague (liste de colonnes pleines),
## consommées séquentiellement puis retour à l'aléatoire.
## ÉVÉNEMENTS AUTOMATIQUES (MODE LIBRE uniquement — countdown_hidden ; cooldown
## global event_cooldown_sec 180 s, anti-répétition, bandeau télégraphié) :
## fog (numéros masqués au-delà de fog_visible_rows), bonus_row (prochaine
## rangée = jetons), quake (la grille remonte d'un cran, fallback rase la
## rangée basse), double_boss (2 mini-boss 2×2), frenzy (volées en continu
## sans descente pendant frenzy_duration_sec).
## Les balles vivent tant qu'elles travaillent : 4 s sans toucher un bloc ->
## fade-out de 2 s (pas de recall au timer).
## Collisions balle/bloc en manuel (cercle vs AABB, normales de coin) comme le
## breakout — pas de physics engine.

signal finished

enum State { INTRO, AIM, VOLLEY, STEP, DONE }

const MOUSE_CAPTURE_ID: int = -2
const BRICK_SHADER: Shader = preload("res://scenes/mechanics/brick_rounded.gdshader")

# PH des nouveaux blocs spéciaux tant que les assets dédiés manquent : teinte
# du visuel + glyphe (lettre sûre, la police par défaut ne couvre pas tous les
# symboles) + glow additif pulsant (pattern sticky/explosive).
const SPECIAL_TINTS: Dictionary = {
	"lightning": "#FFE066", "bomb_charge": "#FF7A4A", "aim_plus": "#5CE8FF",
	"giant_ball": "#5BB8FF", "healer": "#7FE58C", "cursed": "#B455E8",
	"mover": "#C8D2E0", "armored": "#6E7686",
	"portal_in": "#FF8A2A", "portal_out": "#4AA8FF"
}
const SPECIAL_GLYPHS: Dictionary = {
	"lightning": "Z", "bomb_charge": "B", "aim_plus": "A", "giant_ball": "G",
	"healer": "+", "cursed": "X", "mover": "<>", "armored": "#",
	"portal_in": "O", "portal_out": "O"
}
const SPECIAL_GLOWS: Dictionary = {
	"lightning": "#FFE066B4", "bomb_charge": "#FF7A4AB4", "aim_plus": "#5CE8FFB4",
	"giant_ball": "#5BB8FFB4", "healer": "#7FE58CB4", "cursed": "#B455E8B4",
	"mover": "#C8D2E0B4", "armored": "#8A93A6B4",
	"portal_in": "#FF8A2AB4", "portal_out": "#4AA8FFB4"
}
# Types de la famille "bonus" (buffs de volée) — cooldown global partagé.
const BONUS_BLOCK_TYPES: Array = ["lightning", "bomb_charge", "aim_plus", "giant_ball", "healer"]

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 60.0
var _elapsed: float = 0.0
var _turn: int = 0

# Grid geometry (computed once at setup).
var _grid_cols: int = 7
var _block_size: Vector2 = Vector2(96.0, 44.0)
var _block_spacing: float = 5.0
var _grid_side_margin: float = 26.0
var _grid_top_y: float = 0.0
var _descend_step: float = 49.0
var _danger_y: float = 0.0
var _brick_material: ShaderMaterial = null
var _grid_root: Node2D = null

# Blocks: { "node": Node2D, "label": Label, "rect": Rect2, "hp": int,
# "max_hp": int, "col": int, "row": int, "type": String }.
# type ∈ normal|sticky|explosive|chest. row 0 = rangée du plafond (ancrage) ;
# col/row logiques (jamais dérivés de rect.y — les visuels sont tweenés).
# Tokens: { "node": Node2D, "rect": Rect2 }.
var _blocks: Array = []
var _tokens: Array = []

# Destructions différées (explosions échelonnées : blocs explosifs, chutes en
# chaîne, recouvrement boss) : { "at": float (_elapsed), "block": Dictionary,
# "rewarded": bool }. Un bloc enfilé est retiré de _blocks immédiatement
# (plus de collision balle ni danger line) — son node reste visible jusqu'à
# l'explosion planifiée.
var _pending_destructions: Array = []
# Explosions visuelles pures différées (mort du boss) : { "at", "pos", "size" }.
var _pending_explosions: Array = []

# Balls: { "node": Node2D, "pos": Vector2, "vel": Vector2, "idle": float,
# "speed_mult": float }. idle = secondes sans toucher un bloc/boss ; au-delà de
# _ball_idle_timeout la balle fade sur _ball_fade_out puis despawn (une balle
# "stuck" finit toujours par sortir). Toucher un bloc annule le fade.
var _balls: Array = []
var _ball_count: int = 3
var _ball_count_max: int = 30
# Puissance : dégâts infligés par impact de balle (bonus "+1 power", cap data).
var _ball_power: int = 1
var _ball_power_max: int = 20
var _ball_radius: float = 10.0
var _ball_speed: float = 950.0
var _ball_launch_interval: float = 0.06
var _balls_to_launch: int = 0
var _launch_timer: float = 0.0
var _launch_dir: Vector2 = Vector2.UP
var _ball_idle_timeout: float = 4.0
var _ball_fade_out: float = 2.0
var _ball_accel_pct: float = 0.0
var _ball_speed_max_mult: float = 1.6
# Boost "balle vieille" : une balle en jeu depuis ball_boost_after_sec passe à
# ball_boost_speed_mult (×3 = +200 %) en ball_boost_ramp_sec — liquide les
# balles coincées en haut qui rebondissent longtemps. after_sec <= 0 = off.
var _ball_boost_after: float = 10.0
var _ball_boost_mult: float = 3.0
var _ball_boost_ramp: float = 1.0
var _min_vy_ratio: float = 0.18
var _ball_textures: Array = []

# Aim gesture (single gesture: finger follows -> drag up past threshold arms).
var _touch_id: int = -1
var _gesture_start_world: Vector2 = Vector2.ZERO
var _aim_armed: bool = false
var _aim_point_world: Vector2 = Vector2.ZERO
var _aim_arm_threshold: float = 48.0
var _aim_min_angle_deg: float = 14.0
var _aim_line: Node2D = null
var _aim_line_points: PackedVector2Array = PackedVector2Array()
# Rendu "laser" core+glow (Line2D additive, pattern SliceRush) — plus de dash.
var _aim_laser_core: Line2D = null
var _aim_laser_glow: Line2D = null
var _aim_add_material: CanvasItemMaterial = null

# Aim zone hint: a translucent framed band at the bottom third telling the
# player where to press to aim. Shown during AIM until the first press lands
# inside it; a press OUTSIDE the zone re-shows it as a reminder.
var _aim_zone_top_y: float = 0.0
var _aim_zone_panel: Panel = null
var _aim_hint_label: Label = null
var _aim_hint_dismissed: bool = false

# Rewards / damage.
var _damage_percent_row: float = 0.15
var _block_score_base: int = 10
var _block_score_per_hp: int = 4
var _block_crystal_chance: float = 0.1
var _reward_multiplier: float = 1.0

# Explosions de blocs (asset .tres dans wave_types.json > block_explosion) +
# échelonnage temporel des destructions groupées.
var _block_explosion_cfg: Dictionary = {}
var _danger_destroy_explosion: bool = true
var _destruction_stagger: float = 0.04
var _chain_fall_stagger: float = 0.05

# Types de blocs spéciaux (fréquences data ; scalées en mode libre).
var _sticky_chance: float = 0.05
var _explosive_chance: float = 0.05
var _chest_chance: float = 0.02
var _explosive_radius_cells: int = 2
var _chest_loot_cfg: Dictionary = {}
var _sticky_tint: Color = Color("#7FE58C")
var _sticky_overlay_texture: Texture2D = null
var _explosive_texture: Texture2D = null
var _chest_texture: Texture2D = null

# Nouveaux blocs spéciaux (2026-07-12) : chances individuelles + assets dédiés
# (fallback PH tint+glyphe+glow). La famille bonus partage un cooldown global
# d'espacement + anti-répétition (jamais deux fois de suite le même).
var _lightning_chance: float = 0.02
var _bomb_block_chance: float = 0.02
var _aim_block_chance: float = 0.015
var _giant_block_chance: float = 0.015
var _healer_chance: float = 0.012
var _cursed_chance: float = 0.015
var _mover_chance: float = 0.02
var _armored_chance: float = 0.02
var _armored_hp: int = 6
var _portal_chance: float = 0.05
var _portal_max_pairs: int = 1
var _portal_next_id: int = 0
var _healer_heal_percent: float = 0.08
var _bonus_block_cooldown_sec: float = 25.0
var _bonus_block_cooldown: float = 0.0
var _last_bonus_type: String = ""
var _special_textures: Dictionary = {} # type -> Texture2D (assets dédiés)
# Buffs de volée (octroyés par les blocs bonus, consommés par _fire_volley).
var _pierce_volley_pending: bool = false
var _pierce_volley_active: bool = false
var _bomb_volley_pending: bool = false
var _bomb_ball_armed: bool = false # la 1re balle de la volée en cours explose
var _giant_volley_pending: bool = false
var _ball_radius_base: float = 10.0
var _aim_bonus_turns: int = 0

# Rangées scriptées (clé de vague pattern_rows[] : listes de colonnes pleines,
# consommées séquentiellement puis retour à l'aléatoire).
var _pattern_rows: Array = []
var _pattern_row_index: int = 0

# Événements automatiques (MODE LIBRE uniquement — countdown_hidden).
var _events_enabled: bool = false
var _event_timer: float = 0.0
var _last_event: String = ""
var _pending_event: String = ""
var _pending_event_delay: float = 0.0
var _fog_time: float = 0.0
var _frenzy_time: float = 0.0
var _bonus_row_pending: bool = false
var _event_banner_label: Label = null
var _event_banner_time: float = 0.0

# Boss : blocs géants (3×4 par défaut, data), dicts SÉPARÉS de _blocks —
# collision, descente et danger line traitées à part ; non soumis à la
# connectivité et n'ancrent pas les voisins. { "node", "sprite", "label",
# "rect": Rect2, "hp", "max_hp", "shape": "round"|"square"|"star", "col_start",
# "row_top", "cols", "rows" }. Boss à la danger line = défaite immédiate
# (die()). Liste : normalement 0-1 boss ; l'événement double_boss (mode libre)
# en spawn 2 mini 2×2 simultanés.
var _bosses: Array = []
var _boss_defs: Array = []
var _boss_frames: Array = [] # SpriteFrames résolus, index aligné sur _boss_defs
var _boss_hp_row_equiv: float = 6.0
var _boss_trigger_at: float = 0.0
var _boss_spawn_max_wait: float = 60.0
var _boss_respawn_interval: float = 90.0
var _boss_star_dev_deg: float = 18.0
var _boss_score: int = 500
var _boss_crystal_count: int = 5
var _boss_equipment_chance: float = 0.5

# Row generation.
var _row_fill_min: float = 0.45
var _row_fill_max: float = 0.75
var _row_hp_base: float = 2.0
var _row_hp_growth: float = 0.8
var _row_hp_max: int = 60
var _token_chance: float = 0.22
# Jeton "+1 power" : plus rare que le "+1 balle" (fréquence data).
var _power_token_chance: float = 0.08
var _block_textures: Array = []
var _token_texture: Texture2D = null
var _power_token_texture: Texture2D = null

var _danger_line: Line2D = null
var _danger_pulse_sec: float = 0.9
# Encadrés HUD bas-droite : nombre de balles + puissance (frames PNG data).
var _counter_ball_label: Label = null
var _counter_power_label: Label = null
var _counter_ball_frame_tex: Texture2D = null
var _counter_power_frame_tex: Texture2D = null
# Bandeau "DANGER" (bloc/boss à ≤ danger_warning_rows lignes de la limite).
var _danger_warning_rect: ColorRect = null
var _danger_warning_rows: int = 3
# Rayon de coin des blocs/boss : le rebond au coin suit l'arc (normale
# radiale) au lieu de l'angle droit — cohérent avec le visuel arrondi.
var _block_corner_radius: float = 8.0
var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("ball_launcher") if DataManager else {}

	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 60.0))))
	_grid_cols = clampi(int(_get_conf("grid_cols", 7)), 3, 12)
	_block_spacing = clampf(float(_get_conf("block_spacing_px", 5.0)), 0.0, 24.0)
	_grid_side_margin = maxf(4.0, float(_get_conf("grid_side_margin_px", 26.0)))
	_ball_count = clampi(int(_get_conf("ball_count_start", 3)), 1, 200)
	_ball_count_max = clampi(int(_get_conf("ball_count_max", 30)), _ball_count, 200)
	_ball_power = 1
	_ball_power_max = clampi(int(_get_conf("ball_power_max", 20)), 1, 200)
	_ball_radius = maxf(4.0, float(_get_conf("ball_radius_px", 10.0)))
	_ball_speed = maxf(120.0, float(_get_conf("ball_speed_px_sec", 950.0)))
	_ball_launch_interval = maxf(0.01, float(_get_conf("ball_launch_interval_sec", 0.06)))
	_ball_idle_timeout = maxf(0.5, float(_get_conf("ball_idle_timeout_sec", 4.0)))
	_ball_fade_out = maxf(0.2, float(_get_conf("ball_fade_out_sec", 2.0)))
	_ball_accel_pct = maxf(0.0, float(_get_conf("ball_speed_accel_pct_per_sec", 0.0)))
	_ball_speed_max_mult = maxf(1.0, float(_get_conf("ball_speed_max_mult", 1.6)))
	_ball_boost_after = float(_get_conf("ball_boost_after_sec", 10.0))
	_ball_boost_mult = maxf(1.0, float(_get_conf("ball_boost_speed_mult", 3.0)))
	_ball_boost_ramp = maxf(0.05, float(_get_conf("ball_boost_ramp_sec", 1.0)))
	_min_vy_ratio = clampf(float(_get_conf("ball_min_vy_ratio", 0.18)), 0.02, 0.9)
	_aim_arm_threshold = maxf(12.0, float(_get_conf("aim_arm_threshold_px", 48.0)))
	_aim_min_angle_deg = clampf(float(_get_conf("aim_min_angle_deg", 14.0)), 2.0, 45.0)
	_damage_percent_row = clampf(float(_get_conf("damage_percent_per_row_crossed", 0.15)), 0.0, 1.0)
	_block_score_base = maxi(0, int(_get_conf("block_score_base", 10)))
	_block_score_per_hp = maxi(0, int(_get_conf("block_score_per_hp", 4)))
	_block_crystal_chance = clampf(float(_get_conf("block_crystal_chance", 0.1)), 0.0, 1.0)
	_reward_multiplier = maxf(0.0, float(_config.get("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))
	_row_fill_min = clampf(float(_get_conf("row_fill_ratio_min", 0.45)), 0.1, 1.0)
	_row_fill_max = clampf(float(_get_conf("row_fill_ratio_max", 0.75)), _row_fill_min, 1.0)
	_row_hp_base = maxf(1.0, float(_get_conf("row_hp_base", 2)))
	_row_hp_growth = maxf(0.0, float(_get_conf("row_hp_growth_per_turn", 0.8)))
	_row_hp_max = maxi(1, int(_get_conf("row_hp_max", 60)))
	_token_chance = clampf(float(_get_conf("token_chance", 0.22)), 0.0, 1.0)
	_power_token_chance = clampf(float(_get_conf("power_token_chance", 0.08)), 0.0, 1.0)
	_danger_pulse_sec = maxf(0.1, float(_get_conf("danger_line_pulse_sec", 0.9)))

	# Explosions + types spéciaux (défauts wave_types.json, overrides par vague).
	var explosion_v: Variant = _get_conf("block_explosion", {})
	_block_explosion_cfg = explosion_v if explosion_v is Dictionary else {}
	_danger_destroy_explosion = bool(_get_conf("danger_destroy_explosion", true))
	_destruction_stagger = clampf(float(_get_conf("destruction_stagger_sec", 0.04)), 0.0, 0.5)
	_chain_fall_stagger = clampf(float(_get_conf("chain_fall_stagger_sec", 0.05)), 0.0, 0.5)
	_sticky_chance = clampf(float(_get_conf("sticky_chance", 0.05)), 0.0, 1.0)
	_explosive_chance = clampf(float(_get_conf("explosive_chance", 0.05)), 0.0, 1.0)
	_chest_chance = clampf(float(_get_conf("chest_chance", 0.02)), 0.0, 1.0)
	_explosive_radius_cells = clampi(int(_get_conf("explosive_radius_cells", 2)), 1, 4)
	var chest_loot_v: Variant = _get_conf("chest_loot", {})
	_chest_loot_cfg = chest_loot_v if chest_loot_v is Dictionary else {}
	_sticky_tint = Color(str(_get_conf("sticky_tint", "#7FE58C")))

	# Nouveaux blocs spéciaux : chances + cooldown de la famille bonus.
	_lightning_chance = clampf(float(_get_conf("lightning_chance", 0.02)), 0.0, 1.0)
	_bomb_block_chance = clampf(float(_get_conf("bomb_block_chance", 0.02)), 0.0, 1.0)
	_aim_block_chance = clampf(float(_get_conf("aim_block_chance", 0.015)), 0.0, 1.0)
	_giant_block_chance = clampf(float(_get_conf("giant_block_chance", 0.015)), 0.0, 1.0)
	_healer_chance = clampf(float(_get_conf("healer_chance", 0.012)), 0.0, 1.0)
	_cursed_chance = clampf(float(_get_conf("cursed_chance", 0.015)), 0.0, 1.0)
	_mover_chance = clampf(float(_get_conf("mover_chance", 0.02)), 0.0, 1.0)
	_armored_chance = clampf(float(_get_conf("armored_chance", 0.02)), 0.0, 1.0)
	_armored_hp = maxi(1, int(_get_conf("armored_hp", 6)))
	_portal_chance = clampf(float(_get_conf("portal_chance", 0.05)), 0.0, 1.0)
	_portal_max_pairs = maxi(0, int(_get_conf("portal_max_pairs", 1)))
	_healer_heal_percent = clampf(float(_get_conf("healer_heal_percent", 0.08)), 0.0, 1.0)
	_bonus_block_cooldown_sec = maxf(0.0, float(_get_conf("bonus_block_cooldown_sec", 25.0)))
	_ball_radius_base = _ball_radius

	# Rangées scriptées (clé de vague uniquement).
	var pattern_rows_v: Variant = _config.get("pattern_rows", [])
	_pattern_rows = (pattern_rows_v as Array) if pattern_rows_v is Array else []
	_pattern_row_index = 0

	# Événements automatiques : MODE LIBRE uniquement (countdown_hidden est
	# posé par build_free_mode_wave ; false en story ET en fiesta).
	_events_enabled = bool(_config.get("countdown_hidden", false))
	_event_timer = maxf(5.0, float(_get_conf("event_first_delay_sec", 90.0)))

	# Boss : premier spawn borné par max_wait (en mode libre continuous la
	# durée est quasi infinie, ratio × duration ne se déclencherait jamais).
	_boss_hp_row_equiv = maxf(0.5, float(_get_conf("boss_hp_row_equivalent", 6.0)))
	_boss_spawn_max_wait = maxf(1.0, float(_get_conf("boss_spawn_max_wait_sec", 60.0)))
	_boss_trigger_at = minf(clampf(float(_get_conf("boss_spawn_elapsed_ratio", 0.3)), 0.0, 1.0) * _duration, _boss_spawn_max_wait)
	_boss_respawn_interval = maxf(5.0, float(_get_conf("boss_respawn_interval_sec", 90.0)))
	_boss_star_dev_deg = clampf(float(_get_conf("boss_star_deviation_deg", 18.0)), 0.0, 60.0)
	_boss_score = maxi(0, int(_get_conf("boss_score", 500)))
	_boss_crystal_count = maxi(0, int(_get_conf("boss_crystal_count", 5)))
	_boss_equipment_chance = clampf(float(_get_conf("boss_equipment_chance", 0.5)), 0.0, 1.0)

	_danger_warning_rows = maxi(1, int(_get_conf("danger_warning_rows", 3)))

	_prepare_assets()
	_compute_geometry()
	_begin_player_mode()
	_begin_hud_mode()
	_build_danger_line()
	_build_danger_warning()
	_build_aim_line()
	_build_aim_zone_hint()
	_build_initial_grid()
	_ensure_countdown_label()
	_build_counter_boxes()

	_elapsed = 0.0
	_turn = 0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_get_conf("intro_tween_sec", 0.6)))
	set_process(true)

## Per-wave override (world_X.json) > type defaults (wave_types.json).
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — grille, tour et compte de balles préservés. Les
## nouvelles valeurs s'appliquent aux prochaines rangées spawnnées.
func update_free_mode_config(cfg: Dictionary) -> void:
	_row_hp_base = maxf(1.0, float(cfg.get("row_hp_base", _row_hp_base)))
	_row_hp_growth = maxf(0.0, float(cfg.get("row_hp_growth_per_turn", _row_hp_growth)))
	_row_fill_max = clampf(float(cfg.get("row_fill_ratio_max", _row_fill_max)), _row_fill_min, 1.0)
	_damage_percent_row = clampf(float(cfg.get("damage_percent_per_row_crossed", _damage_percent_row)), 0.0, 1.0)
	# Effet différé : prochaines rangées (chances de blocs spéciaux) / prochain
	# boss (intervalle de respawn) — cohérent avec le contrat continuous.
	_sticky_chance = clampf(float(cfg.get("sticky_chance", _sticky_chance)), 0.0, 1.0)
	_explosive_chance = clampf(float(cfg.get("explosive_chance", _explosive_chance)), 0.0, 1.0)
	_chest_chance = clampf(float(cfg.get("chest_chance", _chest_chance)), 0.0, 1.0)
	_lightning_chance = clampf(float(cfg.get("lightning_chance", _lightning_chance)), 0.0, 1.0)
	_bomb_block_chance = clampf(float(cfg.get("bomb_block_chance", _bomb_block_chance)), 0.0, 1.0)
	_aim_block_chance = clampf(float(cfg.get("aim_block_chance", _aim_block_chance)), 0.0, 1.0)
	_giant_block_chance = clampf(float(cfg.get("giant_block_chance", _giant_block_chance)), 0.0, 1.0)
	_healer_chance = clampf(float(cfg.get("healer_chance", _healer_chance)), 0.0, 1.0)
	_cursed_chance = clampf(float(cfg.get("cursed_chance", _cursed_chance)), 0.0, 1.0)
	_mover_chance = clampf(float(cfg.get("mover_chance", _mover_chance)), 0.0, 1.0)
	_armored_chance = clampf(float(cfg.get("armored_chance", _armored_chance)), 0.0, 1.0)
	_portal_chance = clampf(float(cfg.get("portal_chance", _portal_chance)), 0.0, 1.0)
	_boss_spawn_max_wait = maxf(1.0, float(cfg.get("boss_spawn_max_wait_sec", _boss_spawn_max_wait)))
	_boss_respawn_interval = maxf(5.0, float(cfg.get("boss_respawn_interval_sec", _boss_respawn_interval)))

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_ball_launcher"):
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_ball_launcher", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_ball_launcher"):
		_player.call("end_ball_launcher")

## The aim drag covers the whole screen: power buttons would swallow touches
## and are useless here (no shooting); the joystick circles are noise.
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

# =============================================================================
# ASSETS (resolved once at setup — never load() in a gameplay frame)
# =============================================================================

func _prepare_assets() -> void:
	_block_textures.clear()
	var block_assets_v: Variant = _config.get("block_assets", _cfg.get("block_assets", []))
	if block_assets_v is Array:
		for asset_v in (block_assets_v as Array):
			var tex: Texture2D = _texture_from_path(str(asset_v))
			if tex != null:
				_block_textures.append(tex)
	_token_texture = null
	var token_assets_v: Variant = _config.get("token_assets", _cfg.get("token_assets", []))
	if token_assets_v is Array:
		for token_v in (token_assets_v as Array):
			_token_texture = _texture_from_path(str(token_v))
			if _token_texture != null:
				break
	_power_token_texture = null
	var power_assets_v: Variant = _config.get("power_token_assets", _cfg.get("power_token_assets", []))
	if power_assets_v is Array:
		for power_v in (power_assets_v as Array):
			_power_token_texture = _texture_from_path(str(power_v))
			if _power_token_texture != null:
				break
	if _power_token_texture == null:
		_power_token_texture = _token_texture # fallback : même asset, tint dédié
	# Frames PNG des encadrés HUD (fallback = panel uni).
	_counter_ball_frame_tex = _texture_from_path(str(_get_conf("counter_frame_ball_asset", "")))
	_counter_power_frame_tex = _texture_from_path(str(_get_conf("counter_frame_power_asset", "")))
	_ball_textures.clear()
	var ball_tex: Texture2D = _texture_from_path(str(_config.get("ball_asset", _cfg.get("ball_asset", ""))))
	if ball_tex != null:
		_ball_textures.append(ball_tex)
	# Blocs spéciaux : texture dédiée (fallback = pool block_assets) ; sticky =
	# layer hachuré par-dessus l'asset normal (fallback = teinte sticky_tint).
	_sticky_overlay_texture = _texture_from_path(str(_get_conf("sticky_overlay_asset", "")))
	_explosive_texture = _texture_from_path(str(_get_conf("explosive_block_asset", "")))
	_chest_texture = _texture_from_path(str(_get_conf("chest_block_asset", "")))
	# Assets dédiés des nouveaux blocs (clés <type>_block_asset ; vide = PH).
	_special_textures.clear()
	for special_type in SPECIAL_TINTS.keys():
		var special_tex: Texture2D = _texture_from_path(str(_get_conf(str(special_type) + "_block_asset", "")))
		if special_tex != null:
			_special_textures[special_type] = special_tex
	# Boss : SpriteFrames animés (.tres) — un par définition de bosses[].
	_boss_defs.clear()
	_boss_frames.clear()
	var bosses_v: Variant = _config.get("bosses", _cfg.get("bosses", []))
	if bosses_v is Array:
		for def_v in (bosses_v as Array):
			if def_v is Dictionary:
				_boss_defs.append(def_v)
				_boss_frames.append(_frames_from_path(str((def_v as Dictionary).get("asset_anim", ""))))

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
# GRID
# =============================================================================

func _compute_geometry() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable_w: float = viewport_size.x - _grid_side_margin * 2.0
	var block_w: float = maxf(16.0, (usable_w - float(_grid_cols - 1) * _block_spacing) / float(_grid_cols))
	var block_h: float = maxf(12.0, float(_get_conf("block_height_px", 44.0)))
	_block_size = Vector2(block_w, block_h)
	_descend_step = block_h + _block_spacing
	_grid_top_y = viewport_size.y * clampf(float(_get_conf("grid_top_ratio", 0.06)), 0.02, 0.4)
	_danger_y = viewport_size.y * clampf(float(_get_conf("danger_line_ratio", 0.76)), 0.4, 0.92)
	_aim_zone_top_y = viewport_size.y * clampf(float(_get_conf("aim_zone_top_ratio", 0.66)), 0.3, 0.95)

	# Rayon de coin partagé visuel + collision (rebond en arc au coin).
	_block_corner_radius = clampf(float(_get_conf("block_corner_radius_px", 8.0)), 0.0, minf(block_w, block_h) * 0.5)

	# One shared shader material for every block (single batch, like breakout).
	_brick_material = ShaderMaterial.new()
	_brick_material.shader = BRICK_SHADER
	_brick_material.set_shader_parameter("rect_size", _block_size)
	_brick_material.set_shader_parameter("radius_px", _block_corner_radius)

	_grid_root = Node2D.new()
	_grid_root.name = "BlockGrid"
	_grid_root.z_as_relative = false
	_grid_root.z_index = 10
	add_child(_grid_root)

## Initial wall: `initial_rows` rows stacked from the top, weakest at the
## bottom (HP grows with the virtual turn index, like the live generation).
func _build_initial_grid() -> void:
	var initial_rows: int = clampi(int(_get_conf("initial_rows", 3)), 1, 8)
	for i in range(initial_rows):
		# Oldest row (highest virtual turn) sits the lowest, like in real play.
		var row_y: float = _grid_top_y + float(i) * _descend_step
		_spawn_row(row_y, initial_rows - 1 - i, i)

func _row_hp_for_turn(turn: int) -> int:
	return clampi(int(round(_row_hp_base + float(turn) * _row_hp_growth)), 1, _row_hp_max)

func _cell_center_x(col: int) -> float:
	return _grid_side_margin + (_block_size.x + _block_spacing) * float(col) + _block_size.x * 0.5

## Spawns one row at `row_y` (top edge of the row). Guarantees at least one
## block and at least one hole; empty cells can host "+1 ball" tokens (max 2).
## `row_index` = row logique de la rangée (0 = plafond en génération live).
## Les colonnes occupées par le boss (quand il chevauche la row 0) sont
## laissées vides — ni bloc ni token.
func _spawn_row(row_y: float, hp_turn: int, row_index: int = 0, animate_from_top: bool = false) -> void:
	var free_cols: Array = []
	for c in range(_grid_cols):
		if not _boss_blocks_col_row0(c):
			free_cols.append(c)
	if free_cols.is_empty():
		return
	# Événement "rangée bonus" : la prochaine rangée = jetons, aucun bloc.
	if _bonus_row_pending:
		_bonus_row_pending = false
		var power_ratio: float = clampf(float(_get_conf("bonus_row_power_ratio", 0.25)), 0.0, 1.0)
		for c in free_cols:
			var bonus_center := Vector2(_cell_center_x(c), row_y + _block_size.y * 0.5)
			_spawn_token(bonus_center, "power" if randf() < power_ratio else "ball", animate_from_top)
		return
	var fill_ratio: float = randf_range(_row_fill_min, _row_fill_max)
	var hp: int = _row_hp_for_turn(hp_turn)
	var filled: Dictionary = {}
	# Rangée scriptée (pattern_rows[]) : colonnes pleines listées ; épuisées ->
	# retour au remplissage aléatoire. Les garanties ci-dessous s'appliquent
	# dans les deux cas (garde-fou).
	var scripted_set: Dictionary = {}
	var use_scripted: bool = false
	if _pattern_row_index < _pattern_rows.size():
		var scripted_v: Variant = _pattern_rows[_pattern_row_index]
		_pattern_row_index += 1
		if scripted_v is Array:
			use_scripted = true
			for col_v in (scripted_v as Array):
				scripted_set[int(col_v)] = true
	for c in free_cols:
		filled[c] = scripted_set.has(c) if use_scripted else (randf() <= fill_ratio)
	# At least one block, at least one hole (a full wall would be unfair).
	var block_count: int = 0
	for c in free_cols:
		if filled[c]:
			block_count += 1
	if block_count == 0:
		filled[free_cols[randi() % free_cols.size()]] = true
		block_count = 1
	if block_count == free_cols.size():
		filled[free_cols[randi() % free_cols.size()]] = false
		block_count -= 1

	# Paire de portails : roulée PAR RANGÉE (2 cases pleines requises), jamais
	# plus de portal_max_pairs paires vivantes à l'écran.
	var portal_cols: Array = []
	if _portal_chance > 0.0 and randf() < _portal_chance and _count_portal_pairs() < _portal_max_pairs:
		var filled_cols: Array = []
		for c in free_cols:
			if filled[c]:
				filled_cols.append(c)
		if filled_cols.size() >= 2:
			filled_cols.shuffle()
			portal_cols = [int(filled_cols[0]), int(filled_cols[1])]

	var tokens_in_row: int = 0
	for c in free_cols:
		var center := Vector2(_cell_center_x(c), row_y + _block_size.y * 0.5)
		if filled[c]:
			if portal_cols.has(c):
				_spawn_block(center, hp, c, row_index,
					"portal_in" if c == int(portal_cols[0]) else "portal_out", animate_from_top)
			else:
				_spawn_block(center, hp, c, row_index, _roll_block_type(), animate_from_top)
		elif tokens_in_row < 2:
			# "+1 power" (plus rare) prioritaire sur "+1 balle".
			if randf() <= _power_token_chance:
				_spawn_token(center, "power", animate_from_top)
				tokens_in_row += 1
			elif randf() <= _token_chance:
				_spawn_token(center, "ball", animate_from_top)
				tokens_in_row += 1
	if portal_cols.size() == 2:
		_link_portal_twins(row_index, portal_cols)

## Tirage du type de bloc (fréquences basses, data-driven ; sticky/chest
## montent avec le level en mode libre via update_free_mode_config).
func _roll_block_type() -> String:
	var r: float = randf()
	if r < _chest_chance:
		return "chest"
	r -= _chest_chance
	if r < _explosive_chance:
		return "explosive"
	r -= _explosive_chance
	if r < _sticky_chance:
		return "sticky"
	r -= _sticky_chance
	# Blocs comportement (toujours éligibles).
	if r < _armored_chance:
		return "armored"
	r -= _armored_chance
	if r < _mover_chance:
		return "mover"
	r -= _mover_chance
	if r < _cursed_chance:
		return "cursed"
	r -= _cursed_chance
	# Famille bonus : cooldown global d'espacement + anti-répétition (le
	# dernier type bonus tiré est exclu du tirage suivant).
	if _bonus_block_cooldown <= 0.0:
		var pool: Dictionary = {
			"lightning": _lightning_chance,
			"bomb_charge": _bomb_block_chance,
			"aim_plus": _aim_block_chance,
			"giant_ball": _giant_block_chance,
			"healer": _healer_chance
		}
		pool.erase(_last_bonus_type)
		for bonus_type in pool.keys():
			var chance: float = maxf(0.0, float(pool[bonus_type]))
			if r < chance:
				_last_bonus_type = str(bonus_type)
				_bonus_block_cooldown = _bonus_block_cooldown_sec
				return str(bonus_type)
			r -= chance
	return "normal"

func _count_portal_pairs() -> int:
	var count: int = 0
	for block_v in _blocks:
		if str((block_v as Dictionary).get("type", "normal")).begins_with("portal_"):
			count += 1
	return int(ceil(float(count) / 2.0))

## Lie les deux blocs portail d'une rangée par un id partagé (pas de référence
## croisée de dicts : le jumeau se retrouve par scan sur "pid").
func _link_portal_twins(row_index: int, portal_cols: Array) -> void:
	_portal_next_id += 1
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		if int(block.get("row", -1)) == row_index and portal_cols.has(int(block.get("col", -1))) \
			and str(block.get("type", "normal")).begins_with("portal_"):
			block["pid"] = _portal_next_id

func _find_portal_twin(block: Dictionary) -> Dictionary:
	var pid: int = int(block.get("pid", -1))
	if pid < 0:
		return {}
	for other_v in _blocks:
		var other: Dictionary = other_v as Dictionary
		# Même pid, type opposé (in <-> out) : jamais de comparaison d'identité
		# de dicts (GDScript compare par contenu).
		if int(other.get("pid", -2)) == pid \
			and str(other.get("type", "")) != str(block.get("type", "")):
			return other
	return {}

func _spawn_block(center: Vector2, hp: int, col: int, row: int, block_type: String = "normal", animate_from_top: bool = false) -> void:
	# Blindé : HP fixes modérés (1 dégât max par impact — cf. _damage_block).
	if block_type == "armored":
		hp = _armored_hp
	var block_node := Node2D.new()
	block_node.position = center
	var tex: Texture2D = null
	match block_type:
		"explosive":
			tex = _explosive_texture
		"chest":
			tex = _chest_texture
		_:
			if _special_textures.has(block_type):
				tex = _special_textures[block_type]
	var has_dedicated_tex: bool = tex != null
	if tex == null and not _block_textures.is_empty():
		tex = _block_textures[randi() % _block_textures.size()]
	# Halo "glow" AVANT le visuel (dessiné derrière) : identifie les blocs
	# spéciaux tant que les assets dédiés manquent (activable par type).
	if block_type == "sticky" and bool(_get_conf("sticky_glow_enabled", true)):
		block_node.add_child(_make_block_glow(
			Color(str(_get_conf("sticky_glow_color", "#7FE58CB4"))),
			maxf(1.0, float(_get_conf("sticky_glow_size_px", 6.0)))))
	elif block_type == "explosive" and bool(_get_conf("explosive_glow_enabled", true)):
		block_node.add_child(_make_block_glow(
			Color(str(_get_conf("explosive_glow_color", "#FF5A5AB4"))),
			maxf(1.0, float(_get_conf("explosive_glow_size_px", 6.0)))))
	elif SPECIAL_GLOWS.has(block_type):
		block_node.add_child(_make_block_glow(Color(str(SPECIAL_GLOWS[block_type])), 6.0))
	var visual: Node2D = _make_block_visual(tex)
	block_node.add_child(visual)
	if block_type == "sticky":
		# Layer hachuré par-dessus l'asset ; fallback = teinte du visuel.
		if _sticky_overlay_texture != null:
			block_node.add_child(_make_block_overlay(_sticky_overlay_texture))
		else:
			visual.self_modulate = _sticky_tint
	elif not has_dedicated_tex and SPECIAL_TINTS.has(block_type):
		# PH des nouveaux types : teinte + glyphe (l'asset dédié porte l'emblème).
		visual.self_modulate = Color(str(SPECIAL_TINTS[block_type]))
		var glyph := Label.new()
		glyph.text = str(SPECIAL_GLYPHS.get(block_type, "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		glyph.add_theme_font_size_override("font_size", maxi(6, int(float(_get_conf("number_font_size", 20)) * 0.7)))
		glyph.add_theme_color_override("font_color", Color.WHITE)
		glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		glyph.add_theme_constant_override("outline_size", 3)
		glyph.size = _block_size
		glyph.position = -_block_size * 0.5 + Vector2(4.0, 1.0)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block_node.add_child(glyph)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(8, int(_get_conf("number_font_size", 20))))
	label.add_theme_color_override("font_color", Color(str(_get_conf("number_color", "#FFFFFF"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = _block_size
	label.position = -_block_size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_node.add_child(label)
	_grid_root.add_child(block_node)
	var entry: Dictionary = {
		"node": block_node,
		"label": label,
		"rect": Rect2(center - _block_size * 0.5, _block_size),
		"hp": hp,
		"max_hp": hp,
		"col": col,
		"row": row,
		"type": block_type
	}
	if block_type == "mover":
		entry["dir"] = 1 if randf() < 0.5 else -1
	_blocks.append(entry)
	_refresh_block_visual(entry)
	# Brouillard en cours : les numéros au-delà des premières rangées naissent
	# masqués.
	if _fog_time > 0.0 and row >= maxi(0, int(_get_conf("fog_visible_rows", 2))):
		label.visible = false
	if animate_from_top:
		_animate_entry_from_top(block_node, center.y)

## Entrée en jeu : le node translate depuis l'extérieur de l'écran (pas de
## "pop") — le rect logique, lui, est déjà à sa position finale.
func _animate_entry_from_top(node: Node2D, final_y: float) -> void:
	node.position.y = -_block_size.y * 0.5 - _block_spacing
	var tween: Tween = create_tween()
	tween.tween_property(node, "position:y", final_y, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Overlay plein-bloc (hachures sticky) : cover + coins arrondis partagés.
func _make_block_overlay(tex: Texture2D) -> Node2D:
	var overlay: Node2D = _make_block_visual(tex)
	overlay.z_index = 1
	return overlay

## Halo additif pulsant derrière un bloc spécial (sticky vert, explosif rouge).
func _make_block_glow(color: Color, margin: float) -> Node2D:
	var glow := Polygon2D.new()
	var half: Vector2 = _block_size * 0.5 + Vector2.ONE * margin
	glow.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	glow.color = color
	if _aim_add_material != null:
		glow.material = _aim_add_material # blend additif partagé (laser de visée)
	var tween: Tween = glow.create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	return glow

## "Cover" fill like the breakout bricks: centered crop to the block aspect
## ratio then exact scale — never stretched; shared shader rounds the corners.
func _make_block_visual(tex: Texture2D) -> Node2D:
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var block_aspect: float = _block_size.x / _block_size.y
			var tex_aspect: float = tex_size.x / tex_size.y
			var region_size: Vector2
			if tex_aspect > block_aspect:
				region_size = Vector2(tex_size.y * block_aspect, tex_size.y)
			else:
				region_size = Vector2(tex_size.x, tex_size.x / block_aspect)
			sprite.region_enabled = true
			sprite.region_rect = Rect2((tex_size - region_size) * 0.5, region_size)
			sprite.scale = _block_size / region_size
		sprite.material = _brick_material
		return sprite
	var poly := Polygon2D.new()
	var half: Vector2 = _block_size * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	poly.color = Color("#8A93A6")
	return poly

func _refresh_block_visual(block: Dictionary) -> void:
	var node_v: Variant = block.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	var hp: int = int(block.get("hp", 1))
	var max_hp: int = maxi(1, int(block.get("max_hp", 1)))
	# Damaged blocks darken progressively; the counter is the true readout.
	var darken_max: float = clampf(float(_get_conf("block_darken_max", 0.45)), 0.0, 0.9)
	var brightness: float = lerpf(1.0 - darken_max, 1.0, float(hp) / float(max_hp))
	(node_v as Node2D).modulate = Color(brightness, brightness, brightness, 1.0)
	var label_v: Variant = block.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).text = str(hp)

## kind = "ball" ("+1 balle") ou "power" ("+1 puissance", plus rare).
func _spawn_token(center: Vector2, kind: String = "ball", animate_from_top: bool = false) -> void:
	var token_node := Node2D.new()
	token_node.position = center
	var token_size: float = _block_size.y * 0.62
	var tint := Color(str(_get_conf("power_token_tint", "#FF8A5C"))) if kind == "power" \
		else Color(str(_get_conf("token_tint", "#FFD966")))
	var tex: Texture2D = _power_token_texture if kind == "power" else _token_texture
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * token_size) / maxf(tex_size.x, tex_size.y)
		sprite.modulate = tint
		token_node.add_child(sprite)
	var label := Label.new()
	label.text = "+1"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(8, int(int(_get_conf("number_font_size", 20)) * 0.8)))
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = _block_size
	label.position = Vector2(-_block_size.x * 0.5, -_block_size.y * 0.5 - token_size * 0.55)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token_node.add_child(label)
	_grid_root.add_child(token_node)
	_tokens.append({
		"node": token_node,
		"rect": Rect2(center - Vector2.ONE * token_size * 0.5, Vector2.ONE * token_size),
		"kind": kind
	})
	if animate_from_top:
		_animate_entry_from_top(token_node, center.y)

# =============================================================================
# DANGER LINE / AIM LINE
# =============================================================================

func _build_danger_line() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_danger_line = Line2D.new()
	_danger_line.name = "DangerLine"
	_danger_line.points = PackedVector2Array([
		Vector2(_grid_side_margin * 0.5, _danger_y),
		Vector2(viewport_size.x - _grid_side_margin * 0.5, _danger_y)
	])
	_danger_line.width = 3.0
	_danger_line.default_color = Color(str(_get_conf("danger_line_color", "#FF5A5AC8")))
	_danger_line.z_as_relative = false
	_danger_line.z_index = 9
	add_child(_danger_line)

## Bandeau "DANGER" translucide (30 px, centré sur la ligne limite) : affiché
## dès qu'un bloc ou le boss est à ≤ danger_warning_rows lignes de la limite,
## masqué quand la zone se vide. On voit toujours le jeu derrière.
func _build_danger_warning() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var height: float = maxf(8.0, float(_get_conf("danger_warning_height_px", 30.0)))
	_danger_warning_rect = ColorRect.new()
	_danger_warning_rect.name = "DangerWarning"
	_danger_warning_rect.color = Color(str(_get_conf("danger_warning_bg_color", "#FF3B3B4D")))
	_danger_warning_rect.size = Vector2(viewport_size.x, height)
	_danger_warning_rect.position = Vector2(0.0, _danger_y - height * 0.5)
	_danger_warning_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_warning_rect.z_as_relative = false
	_danger_warning_rect.z_index = 58
	_danger_warning_rect.visible = false
	add_child(_danger_warning_rect)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("danger_warning_font_size", 22))))
	label.add_theme_color_override("font_color", Color(str(_get_conf("danger_warning_text_color", "#FFFFFF"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.size = _danger_warning_rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = _resolve_danger_warning_text()
	_danger_warning_rect.add_child(label)

func _resolve_danger_warning_text() -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate("ball_launcher_danger")
		if translated != "" and translated != "ball_launcher_danger":
			return translated.to_upper()
	return "DANGER"

func _update_danger_warning() -> void:
	if _danger_warning_rect == null or not is_instance_valid(_danger_warning_rect):
		return
	var threshold_y: float = _danger_y - float(_danger_warning_rows) * _descend_step
	var shown: bool = false
	for boss_v in _bosses:
		if ((boss_v as Dictionary).get("rect", Rect2()) as Rect2).end.y >= threshold_y:
			shown = true
			break
	if not shown:
		for block_v in _blocks:
			if ((block_v as Dictionary).get("rect", Rect2()) as Rect2).end.y >= threshold_y:
				shown = true
				break
	_danger_warning_rect.visible = shown

## Trait "laser" core+glow (2 Line2D, glow en blend additif — même pattern que
## le laser du vaisseau slice_rush). Couleurs/largeurs data (aim_laser_*).
func _build_aim_line() -> void:
	_aim_line = Node2D.new()
	_aim_line.name = "AimLine"
	_aim_line.z_as_relative = false
	_aim_line.z_index = 12
	_aim_line.visible = false
	add_child(_aim_line)
	_aim_add_material = CanvasItemMaterial.new()
	_aim_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_aim_laser_glow = _make_laser_line(
		maxf(1.0, float(_get_conf("aim_laser_glow_width_px", 12.0))),
		Color(str(_get_conf("aim_laser_glow_color", "#8FD3FF66"))), true)
	_aim_laser_core = _make_laser_line(
		maxf(1.0, float(_get_conf("aim_laser_core_width_px", 3.0))),
		Color(str(_get_conf("aim_laser_core_color", "#FFFFFFE0"))), false)

func _make_laser_line(width: float, color: Color, additive: bool) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	if additive:
		line.material = _aim_add_material
	_aim_line.add_child(line)
	return line

## Translucent framed band covering the bottom third + a centered localized
## label. mouse_filter IGNORE so it never eats the raw touches read in _input.
func _build_aim_zone_hint() -> void:
	_aim_zone_panel = Panel.new()
	_aim_zone_panel.name = "AimZoneHint"
	_aim_zone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_zone_panel.z_as_relative = false
	_aim_zone_panel.z_index = 58
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(_get_conf("aim_zone_bg_color", "#8FD3FF20")))
	sb.border_color = Color(str(_get_conf("aim_zone_border_color", "#8FD3FFC0")))
	var bw: int = int(maxf(0.0, float(_get_conf("aim_zone_border_width_px", 3.0))))
	sb.border_width_left = bw
	sb.border_width_top = bw
	sb.border_width_right = bw
	sb.border_width_bottom = bw
	var cr: int = int(maxf(0.0, float(_get_conf("aim_zone_corner_radius_px", 18.0))))
	sb.corner_radius_top_left = cr
	sb.corner_radius_top_right = cr
	sb.corner_radius_bottom_left = cr
	sb.corner_radius_bottom_right = cr
	_aim_zone_panel.add_theme_stylebox_override("panel", sb)
	add_child(_aim_zone_panel)

	_aim_hint_label = Label.new()
	_aim_hint_label.name = "AimHintLabel"
	_aim_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aim_hint_label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("aim_hint_font_size", 30))))
	_aim_hint_label.add_theme_color_override("font_color", Color(str(_get_conf("aim_hint_color", "#FFFFFF"))))
	_aim_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aim_hint_label.add_theme_constant_override("outline_size", 6)
	_aim_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_hint_label.z_as_relative = false
	_aim_hint_label.z_index = 59
	_aim_hint_label.text = _resolve_aim_hint_text()
	add_child(_aim_hint_label)

	_layout_aim_zone_hint()
	_set_aim_hint_shown(false)

func _resolve_aim_hint_text() -> String:
	var fallback: String = "Appuie ici pour viser !"
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate("ball_launcher_aim_hint")
		if translated != "" and translated != "ball_launcher_aim_hint":
			return translated
	return fallback

func _layout_aim_zone_hint() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.position = Vector2(0.0, _aim_zone_top_y)
		_aim_zone_panel.size = Vector2(viewport_size.x, maxf(1.0, viewport_size.y - _aim_zone_top_y))
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.size = Vector2(viewport_size.x, 54.0)
		# Sits near the top of the zone so it never overlaps the ship at the bottom.
		_aim_hint_label.position = Vector2(0.0, _aim_zone_top_y + 22.0)

func _set_aim_hint_shown(shown: bool) -> void:
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.visible = shown
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.visible = shown

## Shown only while aiming and not yet dismissed; gentle alpha pulse to draw
## the eye without stealing focus from the grid.
func _update_aim_zone_hint() -> void:
	var shown: bool = (_state == State.AIM) and not _aim_hint_dismissed
	_set_aim_hint_shown(shown)
	if not shown:
		return
	_layout_aim_zone_hint()
	var pulse_sec: float = maxf(0.1, float(_get_conf("aim_hint_pulse_sec", 1.2)))
	var a: float = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(TAU * _elapsed / pulse_sec))
	if _aim_zone_panel and is_instance_valid(_aim_zone_panel):
		_aim_zone_panel.modulate.a = a
	if _aim_hint_label and is_instance_valid(_aim_hint_label):
		_aim_hint_label.modulate.a = a

## True when a screen press falls inside the bottom aim band (world space,
## same axis as _danger_y so it lines up with the ship's launch area).
func _is_in_aim_zone(screen_pos: Vector2) -> bool:
	return _to_world(screen_pos).y >= _aim_zone_top_y

## Predictive trajectory: reflects on walls, blocks AND the boss — the player
## sees where the shot goes after collision. Stops after aim_line_max_bounces
## (2) rebounds: past that, reading the trajectory is the skill.
func _update_aim_line() -> void:
	if _aim_line == null or not is_instance_valid(_aim_line):
		return
	if not _aim_armed or _player == null or not is_instance_valid(_player):
		_aim_line.visible = false
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var origin: Vector2 = _launch_origin()
	var dir: Vector2 = _resolve_aim_dir(origin)
	# Buff "visée+" (bloc aim_plus) : +1 rebond pendant _aim_bonus_turns tours.
	var bounce_bonus: int = 1 if _aim_bonus_turns > 0 else 0
	var max_bounces: int = clampi(int(_get_conf("aim_line_max_bounces", 2)) + bounce_bonus, 0, 6)
	var total_budget: float = viewport_size.y * 1.5
	var points := PackedVector2Array([origin])
	var pos: Vector2 = origin
	for _bounce in range(max_bounces + 1):
		if total_budget <= 0.0:
			break
		var hit: Dictionary = _cast_aim_ray(pos, dir, total_budget, viewport_size)
		var t: float = float(hit.get("t", total_budget))
		pos += dir * t
		total_budget -= t
		points.append(pos)
		if not hit.has("normal"):
			break
		dir = dir.bounce(hit.get("normal", Vector2.UP) as Vector2)
	_aim_line_points = points
	if _aim_laser_core and is_instance_valid(_aim_laser_core):
		_aim_laser_core.points = points
	if _aim_laser_glow and is_instance_valid(_aim_laser_glow):
		_aim_laser_glow.points = points
	_aim_line.visible = true

## Premier obstacle le long de `dir` (normalisé) : murs G/D/haut, blocs
## (AABB élargie du rayon de balle), boss (cercle inscrit si round, AABB
## sinon). Retourne {t, normal} — {} = budget épuisé sans impact.
func _cast_aim_ray(origin: Vector2, dir: Vector2, budget: float, viewport_size: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var t_best: float = budget
	# Walls.
	if dir.x < -0.0001:
		var t_left: float = (_ball_radius - origin.x) / dir.x
		if t_left > 0.0 and t_left < t_best:
			t_best = t_left
			best = {"t": t_left, "normal": Vector2(1.0, 0.0)}
	elif dir.x > 0.0001:
		var t_right: float = (viewport_size.x - _ball_radius - origin.x) / dir.x
		if t_right > 0.0 and t_right < t_best:
			t_best = t_right
			best = {"t": t_right, "normal": Vector2(-1.0, 0.0)}
	if dir.y < -0.0001:
		var t_top: float = (_ball_radius - origin.y) / dir.y
		if t_top > 0.0 and t_top < t_best:
			t_best = t_top
			best = {"t": t_top, "normal": Vector2(0.0, 1.0)}
	# Blocks.
	for block_v in _blocks:
		var rect: Rect2 = (block_v as Dictionary).get("rect", Rect2())
		var hit: Dictionary = _ray_vs_rect(origin, dir, rect.grow(_ball_radius))
		if not hit.is_empty() and float(hit["t"]) < t_best:
			t_best = float(hit["t"])
			best = hit
	# Boss (0-2 simultanés).
	for boss_v in _bosses:
		var boss: Dictionary = boss_v as Dictionary
		var b_rect: Rect2 = boss.get("rect", Rect2())
		var b_hit: Dictionary = {}
		if str(boss.get("shape", "square")) == "round":
			var b_radius: float = minf(b_rect.size.x, b_rect.size.y) * 0.5
			b_hit = _ray_vs_circle(origin, dir, b_rect.get_center(), b_radius + _ball_radius)
		else:
			b_hit = _ray_vs_rect(origin, dir, b_rect.grow(_ball_radius))
		if not b_hit.is_empty() and float(b_hit["t"]) < t_best:
			t_best = float(b_hit["t"])
			best = b_hit
	return best

## Ray vs AABB (méthode des slabs). {} si pas d'impact devant l'origine.
func _ray_vs_rect(origin: Vector2, dir: Vector2, rect: Rect2) -> Dictionary:
	var t_min: float = -INF
	var t_max: float = INF
	var normal := Vector2.ZERO
	if absf(dir.x) < 0.000001:
		if origin.x < rect.position.x or origin.x > rect.end.x:
			return {}
	else:
		var inv_x: float = 1.0 / dir.x
		var tx1: float = (rect.position.x - origin.x) * inv_x
		var tx2: float = (rect.end.x - origin.x) * inv_x
		var nx: float = -signf(dir.x)
		if tx1 > tx2:
			var tmp_x: float = tx1
			tx1 = tx2
			tx2 = tmp_x
		if tx1 > t_min:
			t_min = tx1
			normal = Vector2(nx, 0.0)
		t_max = minf(t_max, tx2)
	if absf(dir.y) < 0.000001:
		if origin.y < rect.position.y or origin.y > rect.end.y:
			return {}
	else:
		var inv_y: float = 1.0 / dir.y
		var ty1: float = (rect.position.y - origin.y) * inv_y
		var ty2: float = (rect.end.y - origin.y) * inv_y
		var ny: float = -signf(dir.y)
		if ty1 > ty2:
			var tmp_y: float = ty1
			ty1 = ty2
			ty2 = tmp_y
		if ty1 > t_min:
			t_min = ty1
			normal = Vector2(0.0, ny)
		t_max = minf(t_max, ty2)
	if t_max < maxf(t_min, 0.0) or t_min <= 0.0:
		return {}
	return {"t": t_min, "normal": normal}

## Ray vs cercle (boss "round"). {} si pas d'impact devant l'origine.
func _ray_vs_circle(origin: Vector2, dir: Vector2, center: Vector2, radius: float) -> Dictionary:
	var oc: Vector2 = origin - center
	var b: float = oc.dot(dir)
	var c: float = oc.length_squared() - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		return {}
	var t: float = -b - sqrt(disc)
	if t <= 0.0:
		return {}
	return {"t": t, "normal": (origin + dir * t - center).normalized()}

func _launch_origin() -> Vector2:
	if _player and is_instance_valid(_player):
		return _player.global_position + Vector2(0.0, -_ball_radius * 2.5)
	return Vector2.ZERO

## Aim direction = ship -> finger, clamped to at least `aim_min_angle_deg`
## above the horizontal (no flat shots that would ping-pong forever).
func _resolve_aim_dir(origin: Vector2) -> Vector2:
	var raw: Vector2 = _aim_point_world - origin
	if raw.length_squared() < 1.0:
		return Vector2.UP
	# Angle from straight up: 0 = up, +/-PI/2 = horizontal.
	var ang: float = atan2(raw.x, -raw.y)
	var max_ang: float = PI * 0.5 - deg_to_rad(_aim_min_angle_deg)
	if raw.y >= 0.0:
		# Finger below the ship: clamp to the nearest side limit.
		ang = max_ang * (1.0 if raw.x >= 0.0 else -1.0)
	else:
		ang = clampf(ang, -max_ang, max_ang)
	return Vector2(sin(ang), -cos(ang))

# =============================================================================
# INPUT (single gesture: follow X -> drag up past threshold arms the aim ->
# release fires; dropping back below the threshold cancels. Same raw-touch
# reading + mouse cross-guards as SliceRushManager/lane_runner.)
# =============================================================================

func _input(event: InputEvent) -> void:
	# Releases are ALWAYS processed (even outside AIM/VOLLEY): a finger lifted
	# during STEP/INTRO must free the capture or every next press is ignored.
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch.pressed:
			if touch.index == _touch_id:
				_gesture_end()
			return
		if (_state == State.AIM or _state == State.VOLLEY) and _touch_id == -1:
			_try_begin_gesture(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id and (_state == State.AIM or _state == State.VOLLEY):
			_gesture_feed(drag.position)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mouse_btn.pressed:
			if _touch_id == MOUSE_CAPTURE_ID:
				_gesture_end()
			return
		if (_state == State.AIM or _state == State.VOLLEY) and _touch_id == -1:
			_try_begin_gesture(MOUSE_CAPTURE_ID, mouse_btn.position)
	elif event is InputEventMouseMotion and _touch_id == MOUSE_CAPTURE_ID:
		if _state == State.AIM or _state == State.VOLLEY:
			_gesture_feed((event as InputEventMouseMotion).position)

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

## Aiming only starts inside the bottom band. A press outside is ignored for
## aiming and re-shows the hint; a press inside dismisses it and captures.
func _try_begin_gesture(capture_id: int, screen_pos: Vector2) -> void:
	if not _is_in_aim_zone(screen_pos):
		_aim_hint_dismissed = false
		return
	_aim_hint_dismissed = true
	_gesture_begin(capture_id, screen_pos)

func _gesture_begin(capture_id: int, screen_pos: Vector2) -> void:
	_touch_id = capture_id
	_gesture_start_world = _to_world(screen_pos)
	_aim_armed = false
	_set_ship_target_x(_gesture_start_world.x)

func _gesture_feed(screen_pos: Vector2) -> void:
	var world: Vector2 = _to_world(screen_pos)
	if _state != State.AIM:
		# During the volley the finger only repositions the launch ship.
		_set_ship_target_x(world.x)
		return
	var rise: float = _gesture_start_world.y - world.y
	if _aim_armed:
		if rise < _aim_arm_threshold:
			# Dropped back below the threshold: cancel, resume the X follow.
			_aim_armed = false
			_update_aim_line()
			return
		_aim_point_world = world
	else:
		if rise >= _aim_arm_threshold:
			# Armed: the ship X freezes, the finger now steers the angle.
			_aim_armed = true
			_aim_point_world = world
		else:
			_set_ship_target_x(world.x)

func _gesture_end() -> void:
	_touch_id = -1
	if _state == State.AIM and _aim_armed:
		_aim_armed = false
		_fire_volley()
	_update_aim_line()

func _set_ship_target_x(x: float) -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_ball_launcher_x"):
		_player.call("set_ball_launcher_x", x)

# =============================================================================
# VOLLEY
# =============================================================================

func _fire_volley() -> void:
	_launch_dir = _resolve_aim_dir(_launch_origin())
	_balls_to_launch = _ball_count
	_launch_timer = 0.0
	_turn += 1
	# Buffs de volée (blocs bonus) : consommés au tir.
	_pierce_volley_active = _pierce_volley_pending
	_pierce_volley_pending = false
	_bomb_ball_armed = _bomb_volley_pending
	_bomb_volley_pending = false
	if _giant_volley_pending:
		_giant_volley_pending = false
		_ball_radius = _ball_radius_base * maxf(1.0, float(_get_conf("giant_ball_radius_mult", 2.0)))
	else:
		_ball_radius = _ball_radius_base
	if _aim_bonus_turns > 0:
		_aim_bonus_turns -= 1
	_state = State.VOLLEY
	if _aim_line and is_instance_valid(_aim_line):
		_aim_line.visible = false

func _spawn_ball_node() -> Node2D:
	var ball := Node2D.new()
	ball.z_as_relative = false
	ball.z_index = 11
	if not _ball_textures.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = _ball_textures[0]
		var tex_size: Vector2 = (_ball_textures[0] as Texture2D).get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * _ball_radius * 2.0) / tex_size
		ball.add_child(sprite)
	else:
		var circle := Polygon2D.new()
		var points := PackedVector2Array()
		var segments: int = 16
		for i in range(segments):
			var a: float = TAU * float(i) / float(segments)
			points.append(Vector2(cos(a), sin(a)) * _ball_radius)
		circle.polygon = points
		circle.color = Color(str(_get_conf("ball_color", "#8FD3FF")))
		ball.add_child(circle)
	add_child(ball)
	return ball

func _update_volley(delta: float) -> void:
	# Staggered launches from the ship's current position.
	if _balls_to_launch > 0:
		_launch_timer -= delta
		if _launch_timer <= 0.0:
			_launch_timer = _ball_launch_interval
			_balls_to_launch -= 1
			var node: Node2D = _spawn_ball_node()
			var origin: Vector2 = _launch_origin()
			node.global_position = origin
			var ball_entry: Dictionary = {
				"node": node,
				"pos": origin,
				"vel": _launch_dir * _ball_speed,
				"idle": 0.0,
				"age": 0.0,
				"accel_mult": 1.0,
				"speed_mult": 1.0,
				"portal_cd": 0.0,
				"pierce_left": 1 if _pierce_volley_active else 0,
				"bomb": false
			}
			# Charge de bombe : portée par la PREMIÈRE balle de la volée.
			if _bomb_ball_armed:
				_bomb_ball_armed = false
				ball_entry["bomb"] = true
			_balls.append(ball_entry)

	# Vitesse effective = _ball_speed × max(accélération continue optionnelle,
	# boost "balle vieille" : +200 % après ball_boost_after_sec, rampe douce).
	for ball_v in _balls:
		var speed_ball: Dictionary = ball_v as Dictionary
		speed_ball["age"] = float(speed_ball.get("age", 0.0)) + delta
		speed_ball["portal_cd"] = maxf(0.0, float(speed_ball.get("portal_cd", 0.0)) - delta)
		var accel_mult: float = float(speed_ball.get("accel_mult", 1.0))
		if _ball_accel_pct > 0.0:
			accel_mult = minf(accel_mult + _ball_accel_pct * delta, _ball_speed_max_mult)
			speed_ball["accel_mult"] = accel_mult
		var boost_mult: float = 1.0
		if _ball_boost_after > 0.0:
			var over: float = float(speed_ball["age"]) - _ball_boost_after
			if over > 0.0:
				boost_mult = lerpf(1.0, _ball_boost_mult, clampf(over / _ball_boost_ramp, 0.0, 1.0))
		var mult: float = maxf(accel_mult, boost_mult)
		speed_ball["speed_mult"] = mult
		var vel: Vector2 = speed_ball.get("vel", Vector2.UP)
		if vel.length_squared() > 0.0001:
			speed_ball["vel"] = vel.normalized() * _ball_speed * mult

	# Anti-tunneling: cap each integration step so a ball can never cross a
	# block in one move (fast balls -> several substeps per frame). Calé sur la
	# vitesse max possible (accélération et boost compris).
	var viewport_size: Vector2 = get_viewport_rect().size
	var top_mult: float = 1.0
	if _ball_accel_pct > 0.0:
		top_mult = maxf(top_mult, _ball_speed_max_mult)
	if _ball_boost_after > 0.0:
		top_mult = maxf(top_mult, _ball_boost_mult)
	var top_speed: float = _ball_speed * top_mult
	var max_step: float = maxf(0.002, (_ball_radius * 0.9) / top_speed)
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.0:
		var step: float = minf(remaining, max_step)
		remaining -= step
		for i in range(_balls.size() - 1, -1, -1):
			if not _step_ball(_balls[i], step, viewport_size):
				var node_v: Variant = (_balls[i] as Dictionary).get("node", null)
				if node_v is Node2D and is_instance_valid(node_v):
					(node_v as Node2D).queue_free()
				_balls.remove_at(i)

	# Vie des balles : une balle qui ne touche plus de bloc depuis
	# _ball_idle_timeout entame un fade de _ball_fade_out puis despawn (elle
	# peut être "stuck" — on ne la coupe jamais tant qu'elle travaille).
	for i in range(_balls.size() - 1, -1, -1):
		var life_ball: Dictionary = _balls[i]
		life_ball["idle"] = float(life_ball.get("idle", 0.0)) + delta
		if _update_ball_alpha(life_ball, viewport_size):
			var life_node_v: Variant = life_ball.get("node", null)
			if life_node_v is Node2D and is_instance_valid(life_node_v):
				(life_node_v as Node2D).queue_free()
			_balls.remove_at(i)

	# Turn ends when every ball has exited AND every queued destruction has
	# resolved (the grid must not descend mid-cascade).
	if _balls_to_launch <= 0 and _balls.is_empty() and _pending_destructions.is_empty():
		if _frenzy_time > 0.0:
			# Frénésie : la volée repart aussitôt (même direction, X courant du
			# vaisseau) — la grille ne descend pas pendant l'événement.
			_balls_to_launch = _ball_count
			_launch_timer = 0.0
		else:
			_begin_step()

## Alpha combiné de la balle ; true = despawn.
## - Fade d'inactivité : idle > timeout -> fondu sur _ball_fade_out (un hit
##   remet idle à 0 et annule tout).
## - Fade de retour : sous la barre limite (danger line, au-dessus de la zone
##   vaisseau), la balle s'éteint progressivement jusqu'au bas de l'écran.
func _update_ball_alpha(ball: Dictionary, viewport_size: Vector2) -> bool:
	var alpha: float = 1.0
	var idle: float = float(ball.get("idle", 0.0))
	if idle >= _ball_idle_timeout:
		var fade_t: float = idle - _ball_idle_timeout
		if fade_t >= _ball_fade_out:
			return true
		alpha = 1.0 - fade_t / _ball_fade_out
	var pos: Vector2 = ball.get("pos", Vector2.ZERO)
	if pos.y > _danger_y:
		var zone_alpha: float = 1.0 - (pos.y - _danger_y) / maxf(1.0, viewport_size.y - _danger_y)
		alpha = minf(alpha, clampf(zone_alpha, 0.0, 1.0))
	var node_v: Variant = ball.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).modulate.a = alpha
	return false

## Cercle vs rect à coins arrondis (rayon `corner_r`) : somme de Minkowski —
## le rect "dur" est réduit de corner_r puis regonflé d'un rayon corner_r. Au
## coin, la normale suit l'arc (rebond angulaire) au lieu de l'angle droit.
## Retourne {} si pas de contact, sinon {"normal", "pos"} (pos = balle
## repoussée hors du bloc).
func _circle_vs_rounded_rect(pos: Vector2, ball_r: float, rect: Rect2, corner_r: float) -> Dictionary:
	corner_r = clampf(corner_r, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var inner: Rect2 = rect.grow(-corner_r)
	var closest := Vector2(
		clampf(pos.x, inner.position.x, inner.end.x),
		clampf(pos.y, inner.position.y, inner.end.y)
	)
	var delta_v: Vector2 = pos - closest
	var dist_sq: float = delta_v.length_squared()
	var reach: float = ball_r + corner_r
	if dist_sq > reach * reach:
		return {}
	var normal: Vector2
	if dist_sq > 0.0001:
		normal = delta_v.normalized()
	else:
		# Centre de balle dans le rect interne : normale par l'axe dominant.
		var center_delta: Vector2 = pos - rect.get_center()
		if absf(center_delta.x) / maxf(1.0, rect.size.x) > absf(center_delta.y) / maxf(1.0, rect.size.y):
			normal = Vector2(signf(center_delta.x), 0.0)
		else:
			normal = Vector2(0.0, signf(center_delta.y))
	return {"normal": normal, "pos": closest + normal * (reach + 0.5)}

## Moves one ball one substep. Returns false when the ball exits at the bottom.
func _step_ball(ball: Dictionary, step: float, viewport_size: Vector2) -> bool:
	var pos: Vector2 = ball.get("pos", Vector2.ZERO)
	var vel: Vector2 = ball.get("vel", Vector2.UP * _ball_speed)
	pos += vel * step

	var left_x: float = _ball_radius
	var right_x: float = viewport_size.x - _ball_radius
	var top_y: float = _ball_radius
	var bounced: bool = false
	if pos.x <= left_x and vel.x < 0.0:
		pos.x = left_x
		vel.x = -vel.x
		bounced = true
	elif pos.x >= right_x and vel.x > 0.0:
		pos.x = right_x
		vel.x = -vel.x
		bounced = true
	if pos.y <= top_y and vel.y < 0.0:
		pos.y = top_y
		vel.y = -vel.y
		bounced = true

	# Boss first (bigger, in front of the rows): shape-specific bounce.
	var hit_boss: bool = false
	for boss_v in _bosses:
		var boss: Dictionary = boss_v as Dictionary
		var b_rect: Rect2 = boss.get("rect", Rect2())
		var shape: String = str(boss.get("shape", "square"))
		if shape == "round":
			# Cercle inscrit : normale radiale depuis le centre.
			var b_center: Vector2 = b_rect.get_center()
			var b_radius: float = minf(b_rect.size.x, b_rect.size.y) * 0.5
			var d: Vector2 = pos - b_center
			var reach: float = b_radius + _ball_radius
			if d.length_squared() <= reach * reach:
				var b_normal: Vector2 = d.normalized() if d.length_squared() > 0.0001 else Vector2.UP
				if vel.dot(b_normal) < 0.0:
					vel = vel.bounce(b_normal)
				pos = b_center + b_normal * (reach + 0.5)
				hit_boss = true
		else:
			# Rect à coins arrondis (rebond en arc au coin, comme les blocs) ;
			# "star" ajoute une déviation aléatoire au rebond.
			var b_hit: Dictionary = _circle_vs_rounded_rect(pos, _ball_radius, b_rect, _block_corner_radius)
			if not b_hit.is_empty():
				var b_normal: Vector2 = b_hit["normal"]
				if vel.dot(b_normal) < 0.0:
					vel = vel.bounce(b_normal)
				if shape == "star":
					vel = vel.rotated(deg_to_rad(randf_range(-_boss_star_dev_deg, _boss_star_dev_deg)))
				pos = b_hit["pos"]
				hit_boss = true
		if hit_boss:
			bounced = true
			ball["idle"] = 0.0
			_damage_boss(boss)
			break

	# Blocks: circle vs rounded rect (arc bounce on corners); one per substep.
	if not hit_boss:
		for i in range(_blocks.size() - 1, -1, -1):
			if i >= _blocks.size():
				continue # la grille a pu être vidée par une cascade (pierce/bombe)
			var block: Dictionary = _blocks[i]
			var rect: Rect2 = block.get("rect", Rect2())
			var hit: Dictionary = _circle_vs_rounded_rect(pos, _ball_radius, rect, _block_corner_radius)
			if hit.is_empty():
				continue
			var b_type: String = str(block.get("type", "normal"))
			# Portails : la balle ressort du jumeau (vélocité conservée), aucun
			# dégât au bloc ; sans jumeau/cooldown -> rebond neutre.
			if b_type.begins_with("portal_"):
				if float(ball.get("portal_cd", 0.0)) <= 0.0:
					var twin: Dictionary = _find_portal_twin(block)
					if not twin.is_empty():
						var t_rect: Rect2 = twin.get("rect", Rect2())
						var dir_n: Vector2 = vel.normalized() if vel.length_squared() > 1.0 else Vector2.UP
						pos = t_rect.get_center() + dir_n * (maxf(t_rect.size.x, t_rect.size.y) * 0.5 + _ball_radius + 2.0)
						ball["portal_cd"] = 0.2
						ball["idle"] = 0.0
						if VFXManager:
							VFXManager.spawn_impact(rect.get_center(), 12.0, self)
							VFXManager.spawn_impact(t_rect.get_center(), 12.0, self)
						break
				var p_normal: Vector2 = hit["normal"]
				if vel.dot(p_normal) < 0.0:
					vel = vel.bounce(p_normal)
				pos = hit["pos"]
				bounced = true
				break
			# Charge de bombe (1re balle de la volée) : explosion de zone au
			# 1er impact, pipeline explosif standard.
			if bool(ball.get("bomb", false)):
				ball["bomb"] = false
				_spawn_block_explosion(rect.get_center(), maxf(float(_block_explosion_cfg.get("size", 26.0)), float(_get_conf("explosive_explosion_size_px", 46.0))))
				_explode_around_cell(int(block.get("col", 0)), int(block.get("row", 0)), true)
				ball["idle"] = 0.0
				bounced = true
				break
			# Volée perçante : traverse le 1er bloc touché (dégât sans rebond).
			if _pierce_volley_active and int(ball.get("pierce_left", 0)) > 0 and b_type != "armored":
				ball["pierce_left"] = int(ball.get("pierce_left", 0)) - 1
				ball["idle"] = 0.0
				_damage_block(i)
				continue
			var normal: Vector2 = hit["normal"]
			if vel.dot(normal) < 0.0:
				vel = vel.bounce(normal)
			pos = hit["pos"]
			bounced = true
			ball["idle"] = 0.0
			_damage_block(i)
			break

	# "+1 ball" tokens: collected on contact, no bounce.
	for i in range(_tokens.size() - 1, -1, -1):
		var token: Dictionary = _tokens[i]
		var t_rect: Rect2 = token.get("rect", Rect2())
		if t_rect.grow(_ball_radius * 0.5).has_point(pos):
			_collect_token(i)

	# Anti-loop: never let the trajectory go quasi-horizontal forever.
	if bounced:
		var ball_speed: float = _ball_speed * maxf(0.1, float(ball.get("speed_mult", 1.0)))
		var min_vy: float = ball_speed * _min_vy_ratio
		if absf(vel.y) < min_vy:
			var sign_y: float = -1.0 if vel.y <= 0.0 else 1.0
			vel.y = sign_y * min_vy
			var target_vx: float = sqrt(maxf(0.0, ball_speed * ball_speed - min_vy * min_vy))
			vel.x = target_vx * (1.0 if vel.x >= 0.0 else -1.0)
		vel = vel.normalized() * ball_speed

	ball["pos"] = pos
	ball["vel"] = vel
	var node_v: Variant = ball.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).global_position = pos
	# Ball exits below the screen: collected for the next volley.
	return pos.y - _ball_radius <= viewport_size.y

## Fin de vague uniquement : les balles restantes font un fondu sur place.
## (En jeu, une balle vit tant qu'elle touche des blocs — cf. _update_ball_fade.)
func _recall_balls() -> void:
	var fade_sec: float = maxf(0.05, float(_get_conf("recall_fade_sec", 0.25)))
	for ball_v in _balls:
		var node_v: Variant = (ball_v as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			var tween: Tween = create_tween()
			tween.tween_property(node, "modulate:a", 0.0, fade_sec)
			tween.tween_callback(node.queue_free)
	_balls.clear()
	_balls_to_launch = 0

func _damage_block(index: int) -> void:
	var block: Dictionary = _blocks[index]
	# Blindé : 1 dégât max par impact, quel que soit le power de l'armada.
	var dmg: int = 1 if str(block.get("type", "normal")) == "armored" else _ball_power
	block["hp"] = int(block.get("hp", 1)) - dmg
	var node_v: Variant = block.get("node", null)
	if int(block["hp"]) <= 0:
		_blocks.remove_at(index)
		_destroy_block_immediate(block, true)
		_recompute_connectivity([Vector2i(int(block.get("col", 0)), int(block.get("row", 0)))])
		return
	_refresh_block_visual(block)
	if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
		VFXManager.flash_sprite(node_v, Color(1.6, 1.6, 1.6), maxf(0.02, float(_get_conf("block_hp_flash_sec", 0.1))))

## Résout la destruction d'un bloc DÉJÀ retiré de _blocks : explosion,
## récompenses, effets spéciaux (explosif/chest), libération du node.
## with_vfx=false pour le flush synchrone de _finish (récompenses seules).
func _destroy_block_immediate(block: Dictionary, rewarded: bool, with_vfx: bool = true) -> void:
	if block.is_empty():
		return
	var rect: Rect2 = block.get("rect", Rect2())
	var center: Vector2 = rect.get_center()
	if with_vfx:
		var size: float = float(_block_explosion_cfg.get("size", 26.0))
		if str(block.get("type", "normal")) == "explosive":
			size = maxf(size, float(_get_conf("explosive_explosion_size_px", 46.0)))
		_spawn_block_explosion(center, size)
	if rewarded:
		_award_block_rewards(center, maxi(1, int(block.get("max_hp", 1))))
	_on_block_destroyed_effects(block, rewarded)
	var node_v: Variant = block.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()

## Explosion de bloc : asset .tres data (block_explosion, défaut = l'explosion
## enemy_death du jeu) via VFXManager — même pipeline que les ennemis.
func _spawn_block_explosion(pos: Vector2, size: float) -> void:
	if VFXManager == null:
		return
	var asset: String = str(_block_explosion_cfg.get("asset", ""))
	var anim: String = str(_block_explosion_cfg.get("asset_anim", "res://assets/vfx/boss_explosion.tres"))
	var duration: float = maxf(0.05, float(_block_explosion_cfg.get("duration", 0.26)))
	var color := Color(str(_block_explosion_cfg.get("color", "#FFAA00")))
	VFXManager.spawn_explosion(pos, size, color, self, asset, anim, -1.0, 0.12, duration, false)

## Effets à la destruction selon le type : explosif = détruit les blocs dans
## un rayon Chebyshev de N cellules (explosions échelonnées, le plus proche en
## premier) ; chest = loot aléatoire (cristaux ou équipement vaisseau).
func _on_block_destroyed_effects(block: Dictionary, rewarded: bool) -> void:
	var center: Vector2 = (block.get("rect", Rect2()) as Rect2).get_center()
	match str(block.get("type", "normal")):
		"explosive":
			_explode_around_cell(int(block.get("col", 0)), int(block.get("row", 0)), rewarded)
		"chest":
			if rewarded:
				_award_chest_loot(center)
		"lightning":
			_pierce_volley_pending = true
			_show_buff_float("ball_launcher_buff_pierce", "PIERCING VOLLEY!", Color("#FFE066"), center)
		"bomb_charge":
			_bomb_volley_pending = true
			_show_buff_float("ball_launcher_buff_bomb", "BOMB LOADED!", Color("#FF7A4A"), center)
		"aim_plus":
			_aim_bonus_turns = maxi(_aim_bonus_turns, 3)
			_show_buff_float("ball_launcher_buff_aim", "+1 BOUNCE", Color("#5CE8FF"), center)
		"giant_ball":
			_giant_volley_pending = true
			_show_buff_float("ball_launcher_buff_giant", "GIANT VOLLEY!", Color("#5BB8FF"), center)
		"healer":
			if _player and is_instance_valid(_player) and _player.has_method("heal"):
				var max_hp_v: Variant = _player.get("max_hp")
				var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
				_player.call("heal", maxi(1, int(ceil(float(max_hp) * _healer_heal_percent))))
		"cursed":
			# Malus : toute la grille descend d'un cran immédiatement.
			_show_buff_float("ball_launcher_buff_cursed", "CURSED!", Color("#B455E8"), center)
			_shift_grid(_descend_step, 1)
			_apply_danger_line_crossings()
		"portal_in", "portal_out":
			# Le jumeau meurt avec (sans récompense double).
			var twin: Dictionary = _find_portal_twin(block)
			if not twin.is_empty():
				_queue_block_destruction(twin, _destruction_stagger, false)
		_:
			pass

## Explosion de zone (rayon Chebyshev explosive_radius_cells) autour d'une
## cellule : partagée par les blocs explosifs ET la charge de bombe (buff).
func _explode_around_cell(col: int, row: int, rewarded: bool) -> void:
	var targets: Array = []
	for other_v in _blocks:
		var other: Dictionary = other_v as Dictionary
		var dc: int = absi(int(other.get("col", 0)) - col)
		var dr: int = absi(int(other.get("row", 0)) - row)
		if maxi(dc, dr) <= _explosive_radius_cells:
			targets.append({"block": other, "dist": sqrt(float(dc * dc + dr * dr))})
	targets.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	for target_v in targets:
		var target: Dictionary = target_v as Dictionary
		_queue_block_destruction(target["block"], float(target["dist"]) * _destruction_stagger, rewarded)

## Floating text localisé des buffs de blocs (fallback EN).
func _show_buff_float(locale_key: String, fallback: String, color: Color, at_pos: Vector2) -> void:
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos, _translate_or(locale_key, fallback), color, self)

func _translate_or(key: String, fallback: String) -> String:
	if typeof(LocaleManager) != TYPE_NIL and LocaleManager:
		var translated: String = LocaleManager.translate(key)
		if translated != "" and translated != key:
			return translated
	return fallback

## Auto-pickup : tout loot qui franchit la barre limite en bas file vers le
## vaisseau et est absorbé (clés opt-in de BonusCrystal / LootDrop).
func _crystal_pickup_extra() -> Dictionary:
	return {"force_magnet_below_y": _danger_y}

func _equipment_pickup_extra() -> Dictionary:
	return {"auto_collect_below_y": _danger_y}

## Loot du chest : équipement garanti (spawn_reward_equipment_at contourne le
## cap de drop par vague) OU pluie de cristaux, pondération data (chest_loot).
func _award_chest_loot(at_pos: Vector2) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var equip_chance: float = clampf(float(_chest_loot_cfg.get("equipment_chance", 0.35)), 0.0, 1.0)
	if randf() <= equip_chance and _game.has_method("spawn_reward_equipment_at"):
		_game.call("spawn_reward_equipment_at", at_pos, maxf(0.1, float(_chest_loot_cfg.get("equipment_quality_mult", 1.0))), _equipment_pickup_extra())
		return
	if _game.has_method("spawn_reward_crystal_at"):
		var count_min: int = maxi(1, int(_chest_loot_cfg.get("crystal_count_min", 3)))
		var count_max: int = maxi(count_min, int(_chest_loot_cfg.get("crystal_count_max", 6)))
		for _i in range(randi_range(count_min, count_max)):
			_game.call("spawn_reward_crystal_at", at_pos, _crystal_pickup_extra())

func _award_block_rewards(at_pos: Vector2, max_hp: int) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var points: int = int(round(float(_block_score_base + max_hp * _block_score_per_hp) * _reward_multiplier))
	if points > 0 and _game.has_method("add_wave_bonus_score"):
		_game.call("add_wave_bonus_score", points, at_pos)
	if randf() <= _block_crystal_chance and _game.has_method("spawn_reward_crystal_at"):
		_game.call("spawn_reward_crystal_at", at_pos, _crystal_pickup_extra())

# =============================================================================
# DESTRUCTIONS DIFFÉRÉES + CONNECTIVITÉ (chutes en chaîne façon Holedown)
# =============================================================================

## Condamne un bloc : retiré de _blocks IMMÉDIATEMENT (plus de collision balle
## ni de danger line), explose à _elapsed + delay_sec. Idempotent (un bloc
## déjà condamné/détruit est ignoré).
func _queue_block_destruction(block: Dictionary, delay_sec: float, rewarded: bool) -> void:
	var idx: int = _blocks.find(block)
	if idx < 0:
		return
	_blocks.remove_at(idx)
	_pending_destructions.append({
		"at": _elapsed + maxf(0.0, delay_sec),
		"block": block,
		"rewarded": rewarded
	})

## Drainé chaque frame (pas de Timer : pausable, zéro alloc). Après chaque
## batch résolu, la connectivité est recalculée — les explosions peuvent
## déclencher de nouvelles chutes (cascades).
func _process_pending_destructions() -> void:
	if _pending_destructions.is_empty():
		return
	var resolved_cells: Array = []
	var i: int = 0
	while i < _pending_destructions.size():
		var entry: Dictionary = _pending_destructions[i]
		if _elapsed >= float(entry.get("at", 0.0)):
			_pending_destructions.remove_at(i)
			var block: Dictionary = entry.get("block", {}) as Dictionary
			_destroy_block_immediate(block, bool(entry.get("rewarded", false)))
			resolved_cells.append(Vector2i(int(block.get("col", 0)), int(block.get("row", 0))))
		else:
			i += 1
	if not resolved_cells.is_empty():
		_recompute_connectivity(resolved_cells)

## Explosions visuelles pures différées (mort du boss).
func _process_pending_explosions() -> void:
	var i: int = 0
	while i < _pending_explosions.size():
		var entry: Dictionary = _pending_explosions[i]
		if _elapsed >= float(entry.get("at", 0.0)):
			_pending_explosions.remove_at(i)
			_spawn_block_explosion(entry.get("pos", Vector2.ZERO) as Vector2, float(entry.get("size", 26.0)))
		else:
			i += 1

## Les blocs "tiennent" par le plafond : BFS 4-adjacence (arêtes uniquement,
## jamais en diagonale) depuis les ancres (rangée 0 + blocs sticky — ancre
## locale). Les blocs sans chemin vers une ancre se décrochent et explosent en
## cascade avec récompense normale. `origin_cells` = cellules des blocs qui
## VIENNENT d'être détruits : la vague d'explosion se propage par adjacence
## depuis la rupture — d'abord les voisins directs du bloc explosé, puis de
## proche en proche (jamais un bloc "au hasard" à l'autre bout de la grille).
## Le boss n'est ni ancré ni ancre. Grille ≤ ~12×15 cellules : coût négligeable.
func _recompute_connectivity(origin_cells: Array = []) -> void:
	if _blocks.is_empty():
		return
	var offsets: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var by_cell: Dictionary = {}
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		by_cell[Vector2i(int(block.get("col", 0)), int(block.get("row", 0)))] = block
	# 1) Ancrage : BFS depuis rangée 0 + sticky.
	var anchored: Dictionary = {}
	var queue: Array = []
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		if int(block.get("row", 0)) == 0 or str(block.get("type", "normal")) == "sticky":
			var cell := Vector2i(int(block.get("col", 0)), int(block.get("row", 0)))
			if not anchored.has(cell):
				anchored[cell] = true
				queue.append(cell)
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for offset_v in offsets:
			var next: Vector2i = cell + (offset_v as Vector2i)
			if by_cell.has(next) and not anchored.has(next):
				anchored[next] = true
				queue.append(next)
	# 2) Décrochés = blocs sans chemin vers une ancre.
	var falling_cells: Dictionary = {}
	for cell_v in by_cell.keys():
		if not anchored.has(cell_v):
			falling_cells[cell_v] = by_cell[cell_v]
	if falling_cells.is_empty():
		return
	# 3) Ordre de la vague : BFS DANS le groupe décroché, amorcé par les
	# voisins directs de la rupture (origin_cells) — profondeur = rang.
	var depth: Dictionary = {}
	var wave: Array = []
	for origin_v in origin_cells:
		if not (origin_v is Vector2i):
			continue
		for offset_v in offsets:
			var seed_cell: Vector2i = (origin_v as Vector2i) + (offset_v as Vector2i)
			if falling_cells.has(seed_cell) and not depth.has(seed_cell):
				depth[seed_cell] = 0
				wave.append(seed_cell)
	head = 0
	var max_depth: int = 0
	while head < wave.size():
		var wave_cell: Vector2i = wave[head]
		head += 1
		for offset_v in offsets:
			var next_cell: Vector2i = wave_cell + (offset_v as Vector2i)
			if falling_cells.has(next_cell) and not depth.has(next_cell):
				depth[next_cell] = int(depth[wave_cell]) + 1
				max_depth = maxi(max_depth, int(depth[next_cell]))
				wave.append(next_cell)
	# 4) Poches décrochées non atteintes depuis la rupture (ou pas d'origine,
	# ex. danger line) : après la vague principale, du haut vers le bas.
	var leftovers: Array = []
	for cell_v in falling_cells.keys():
		if not depth.has(cell_v):
			leftovers.append(cell_v)
	leftovers.sort_custom(func(a, b) -> bool:
		var cell_a: Vector2i = a
		var cell_b: Vector2i = b
		if cell_a.y != cell_b.y:
			return cell_a.y < cell_b.y
		return cell_a.x < cell_b.x)
	for i in range(leftovers.size()):
		depth[leftovers[i]] = max_depth + 1 + i
	# 5) Mise en file avec délais échelonnés par rang.
	for cell_v in depth.keys():
		_queue_block_destruction(falling_cells[cell_v], float(depth[cell_v]) * _chain_fall_stagger, true)

# =============================================================================
# BOSS
# =============================================================================

func _damage_boss(boss: Dictionary) -> void:
	if boss.is_empty():
		return
	boss["hp"] = int(boss.get("hp", 1)) - _ball_power
	if int(boss["hp"]) <= 0:
		_destroy_boss(boss)
		return
	var label_v: Variant = boss.get("label", null)
	if label_v is Label and is_instance_valid(label_v):
		(label_v as Label).text = str(int(boss["hp"]))
	var node_v: Variant = boss.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		# Assombrissement progressif comme les blocs.
		var darken_max: float = clampf(float(_get_conf("block_darken_max", 0.45)), 0.0, 0.9)
		var brightness: float = lerpf(1.0 - darken_max, 1.0, float(int(boss["hp"])) / float(maxi(1, int(boss.get("max_hp", 1)))))
		(node_v as Node2D).modulate = Color(brightness, brightness, brightness, 1.0)
		if VFXManager:
			VFXManager.flash_sprite(node_v, Color(1.6, 1.6, 1.6), maxf(0.02, float(_get_conf("block_hp_flash_sec", 0.1))))

## Mort du boss : multi-explosions échelonnées sur sa surface, gros score,
## pluie de cristaux, chance d'équipement. Le prochain boss est réarmé à
## _elapsed + boss_respawn_interval.
func _destroy_boss(boss: Dictionary) -> void:
	if boss.is_empty():
		return
	var rect: Rect2 = boss.get("rect", Rect2())
	var node_v: Variant = boss.get("node", null)
	_bosses.erase(boss)
	_boss_trigger_at = _elapsed + _boss_respawn_interval
	var center: Vector2 = rect.get_center()
	var explosion_size: float = maxf(float(_block_explosion_cfg.get("size", 26.0)) * 1.6, 40.0)
	var explosion_count: int = 6
	_spawn_block_explosion(center, explosion_size * 1.4)
	for i in range(explosion_count):
		_pending_explosions.append({
			"at": _elapsed + float(i + 1) * _destruction_stagger * 2.0,
			"pos": Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y)),
			"size": explosion_size
		})
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(10, 0.4)
	if _game and is_instance_valid(_game):
		var points: int = int(round(float(_boss_score) * _reward_multiplier))
		if points > 0 and _game.has_method("add_wave_bonus_score"):
			_game.call("add_wave_bonus_score", points, center)
		if _game.has_method("spawn_reward_crystal_at"):
			for _i in range(_boss_crystal_count):
				_game.call("spawn_reward_crystal_at", center, _crystal_pickup_extra())
		if randf() <= _boss_equipment_chance and _game.has_method("spawn_reward_equipment_at"):
			_game.call("spawn_reward_equipment_at", center, 1.0, _equipment_pickup_extra())
	if node_v is Node2D and is_instance_valid(node_v):
		var node: Node2D = node_v as Node2D
		var tween: Tween = create_tween()
		tween.tween_property(node, "modulate:a", 0.0, 0.35)
		tween.tween_callback(node.queue_free)

## Appelé à chaque STEP (avant _spawn_row). Premier spawn borné par
## boss_spawn_max_wait_sec (indispensable en mode libre continuous où la
## durée est quasi infinie) — garantit AU MOINS un boss dans le temps imparti
## en mode histoire.
func _try_spawn_boss() -> void:
	if not _bosses.is_empty() or _boss_defs.is_empty():
		return
	if _elapsed < _boss_trigger_at:
		return
	_spawn_boss(randi() % _boss_defs.size())

## override_cols/rows > 0 et hp_mult/forced_col_start : utilisés par
## l'événement double_boss (mini-boss 2×2, HP réduits, colonnes imposées).
func _spawn_boss(def_index: int, override_cols: int = 0, override_rows: int = 0, hp_mult: float = 1.0, forced_col_start: int = -1) -> void:
	var def: Dictionary = _boss_defs[def_index] as Dictionary
	var cols: int = clampi(override_cols if override_cols > 0 else int(def.get("cols", 3)), 1, _grid_cols)
	var rows: int = clampi(override_rows if override_rows > 0 else int(def.get("rows", 4)), 1, 8)
	var col_start: int = forced_col_start if forced_col_start >= 0 else randi_range(0, _grid_cols - cols)
	col_start = clampi(col_start, 0, _grid_cols - cols)
	var width: float = float(cols) * _block_size.x + float(cols - 1) * _block_spacing
	var height: float = float(rows) * _block_size.y + float(rows - 1) * _block_spacing
	var x_left: float = _grid_side_margin + (_block_size.x + _block_spacing) * float(col_start)
	var rect := Rect2(Vector2(x_left, _grid_top_y), Vector2(width, height))
	var center: Vector2 = rect.get_center()

	# Blocs recouverts : détruits AVEC récompense, explosions échelonnées.
	var overlapped: Array = []
	for block_v in _blocks:
		if rect.intersects((block_v as Dictionary).get("rect", Rect2()) as Rect2):
			overlapped.append(block_v)
	for i in range(overlapped.size()):
		_queue_block_destruction(overlapped[i], float(i) * _destruction_stagger, true)
	for i in range(_tokens.size() - 1, -1, -1):
		var token: Dictionary = _tokens[i]
		if rect.intersects(token.get("rect", Rect2()) as Rect2):
			var t_node_v: Variant = token.get("node", null)
			if t_node_v is Node2D and is_instance_valid(t_node_v):
				(t_node_v as Node2D).queue_free()
			_tokens.remove_at(i)

	# HP massif : équivalent de boss_hp_row_equivalent rangées PLEINES au tour
	# courant — le budget de points du boss croît donc avec le temps.
	var hp: int = maxi(1, int(ceil(_row_hp_for_turn(_turn) * float(_grid_cols) * _boss_hp_row_equiv * maxf(0.05, hp_mult))))

	var boss_node := Node2D.new()
	boss_node.name = "BallLauncherBoss"
	boss_node.position = center
	# Hitbox visible : fond très léger épousant la forme de rebond réelle
	# (cercle inscrit si round, rect arrondi sinon) — couleur/opacité data.
	boss_node.add_child(_make_boss_hitbox_visual(str(def.get("shape", "square")), rect.size))
	var sprite: AnimatedSprite2D = null
	var frames: SpriteFrames = _boss_frames[def_index] if def_index < _boss_frames.size() else null
	if frames != null:
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		var anim_names: PackedStringArray = frames.get_animation_names()
		if anim_names.size() > 0:
			sprite.animation = anim_names[0]
			var first: Texture2D = frames.get_frame_texture(anim_names[0], 0)
			if first != null and first.get_size().x > 0.0 and first.get_size().y > 0.0:
				# boss_asset_fill_type (data) : "cover" (défaut — remplit tout
				# le rect, recadré par clip : la hitbox se lit clairement) ou
				# "contain" (le sprite tient entier dans le rect).
				var fill_type: String = str(_get_conf("boss_asset_fill_type", "cover")).to_lower()
				var fit: float
				if fill_type == "contain":
					fit = minf(width / first.get_size().x, height / first.get_size().y)
				else:
					fit = maxf(width / first.get_size().x, height / first.get_size().y)
				sprite.scale = Vector2.ONE * fit
			sprite.play()
		# Clip au rect du boss : indispensable en cover (recadrage), inoffensif
		# en contain.
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.size = rect.size
		clip.position = -rect.size * 0.5
		sprite.position = rect.size * 0.5
		clip.add_child(sprite)
		boss_node.add_child(clip)
	else:
		# Fallback sans asset : polygone coloré selon la shape.
		var poly := Polygon2D.new()
		var shape: String = str(def.get("shape", "square"))
		if shape == "round":
			var pts := PackedVector2Array()
			var poly_radius: float = minf(width, height) * 0.5
			for i in range(24):
				var a: float = TAU * float(i) / 24.0
				pts.append(Vector2(cos(a), sin(a)) * poly_radius)
			poly.polygon = pts
		else:
			poly.polygon = PackedVector2Array([
				Vector2(-width * 0.5, -height * 0.5), Vector2(width * 0.5, -height * 0.5),
				Vector2(width * 0.5, height * 0.5), Vector2(-width * 0.5, height * 0.5)
			])
		poly.color = Color("#B06AD4")
		boss_node.add_child(poly)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(12, int(float(_get_conf("number_font_size", 20)) * 1.8)))
	label.add_theme_color_override("font_color", Color(str(_get_conf("number_color", "#FFFFFF"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.size = rect.size
	label.position = -rect.size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(hp)
	boss_node.add_child(label)
	_grid_root.add_child(boss_node)
	# Entrée : translation depuis l'extérieur de l'écran (le boss est grand,
	# on ne le voit que partiellement au début) — pas de "pop".
	boss_node.position.y = -height * 0.5
	var intro_tween: Tween = create_tween()
	intro_tween.tween_property(boss_node, "position:y", center.y, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_bosses.append({
		"node": boss_node,
		"sprite": sprite,
		"label": label,
		"rect": rect,
		"hp": hp,
		"max_hp": hp,
		"shape": str(def.get("shape", "square")),
		"col_start": col_start,
		"row_top": 0,
		"cols": cols,
		"rows": rows
	})
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(6, 0.25)

## Fond translucide de la hitbox du boss (boss_hitbox_color/opacity) : cercle
## inscrit pour "round", rect aux coins arrondis (_block_corner_radius) pour
## "square"/"star" — la forme affichée EST la forme de rebond.
func _make_boss_hitbox_visual(shape: String, size: Vector2) -> Node2D:
	var poly := Polygon2D.new()
	var color := Color(str(_get_conf("boss_hitbox_color", "#FF5A5A")))
	color.a = clampf(float(_get_conf("boss_hitbox_opacity", 0.1)), 0.0, 1.0)
	poly.color = color
	poly.z_index = -1
	var points := PackedVector2Array()
	if shape == "round":
		var radius: float = minf(size.x, size.y) * 0.5
		for i in range(48):
			var a: float = TAU * float(i) / 48.0
			points.append(Vector2(cos(a), sin(a)) * radius)
	else:
		# Rect arrondi : 4 arcs de _block_corner_radius reliés.
		var half: Vector2 = size * 0.5
		var r: float = clampf(_block_corner_radius, 0.0, minf(half.x, half.y))
		var corners: Array = [
			[Vector2(half.x - r, -half.y + r), -PI * 0.5],  # haut-droit
			[Vector2(half.x - r, half.y - r), 0.0],         # bas-droit
			[Vector2(-half.x + r, half.y - r), PI * 0.5],   # bas-gauche
			[Vector2(-half.x + r, -half.y + r), PI]         # haut-gauche
		]
		for corner_v in corners:
			var corner_center: Vector2 = (corner_v as Array)[0]
			var start_angle: float = float((corner_v as Array)[1])
			for i in range(7):
				var a: float = start_angle + (PI * 0.5) * float(i) / 6.0
				points.append(corner_center + Vector2(cos(a), sin(a)) * r)
	poly.polygon = points
	return poly

## Boss à la ligne de danger : défaite immédiate — game over en mode histoire,
## fin de run en mode libre (même chemin Game._on_player_died). die() direct :
## take_damage serait masqué par dodge/shield/invincibilité.
func _trigger_boss_game_over() -> void:
	if VFXManager:
		VFXManager.screen_shake(14, 0.5)
	if _player and is_instance_valid(_player):
		if _player.has_method("die"):
			_player.call("die")
		elif _player.has_method("take_damage"):
			_player.call("take_damage", 999999)

func _collect_token(index: int) -> void:
	var token: Dictionary = _tokens[index]
	_tokens.remove_at(index)
	var node_v: Variant = token.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		var node: Node2D = node_v as Node2D
		var tween: Tween = create_tween()
		tween.tween_property(node, "scale", Vector2.ONE * 1.6, 0.12)
		tween.parallel().tween_property(node, "modulate:a", 0.0, 0.12)
		tween.tween_callback(node.queue_free)
	if str(token.get("kind", "ball")) == "power":
		_ball_power = mini(_ball_power + 1, _ball_power_max)
	else:
		_ball_count = mini(_ball_count + 1, _ball_count_max)
	_refresh_counter_labels()

# =============================================================================
# GRID STEP (descend + new row + danger line check)
# =============================================================================

func _begin_step() -> void:
	_state = State.STEP
	_state_timer = 0.25
	# Fin de volée : les buffs "prochaine volée" sont consommés, restaure.
	_pierce_volley_active = false
	_ball_radius = _ball_radius_base
	# Blocs mouvants : glissent d'une colonne AVANT la descente et le BFS.
	_step_movers()
	# Logical rects move instantly (no collisions during STEP), visuals tween.
	# Les rows logiques s'incrémentent en même temps (row 0 = plafond).
	_shift_grid(_descend_step, 1)
	_try_spawn_boss()
	_spawn_row(_grid_top_y, _turn, 0, true) # slide-in depuis le haut hors écran
	# Brouillard en cours : ré-applique le masque (les rows ont changé).
	if _fog_time > 0.0:
		_set_fog_enabled(true)
	_apply_danger_line_crossings()

## Décale toute la grille (blocs, jetons, boss) verticalement : rects
## instantanés, visuels tweenés, rows logiques ajustées. step_y > 0 = descente
## (_begin_step, bloc maudit), step_y < 0 = remontée (événement séisme).
func _shift_grid(step_y: float, row_delta: int) -> void:
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		var rect: Rect2 = block.get("rect", Rect2())
		rect.position.y += step_y
		block["rect"] = rect
		block["row"] = int(block.get("row", 0)) + row_delta
		_tween_node_shift_y(block.get("node", null), step_y)
	for token_v in _tokens:
		var token: Dictionary = token_v as Dictionary
		var t_rect: Rect2 = token.get("rect", Rect2())
		t_rect.position.y += step_y
		token["rect"] = t_rect
		_tween_node_shift_y(token.get("node", null), step_y)
	for boss_v in _bosses:
		var boss: Dictionary = boss_v as Dictionary
		var b_rect: Rect2 = boss.get("rect", Rect2())
		b_rect.position.y += step_y
		boss["rect"] = b_rect
		boss["row_top"] = int(boss.get("row_top", 0)) + row_delta
		_tween_node_shift_y(boss.get("node", null), step_y)

func _tween_node_shift_y(node_v: Variant, step_y: float) -> void:
	if node_v is Node2D and is_instance_valid(node_v):
		var node: Node2D = node_v as Node2D
		var tween: Tween = create_tween()
		tween.tween_property(node, "position:y", node.position.y + step_y, 0.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Blocs mouvants : glissent d'une colonne par tour (direction propre,
## inversée aux bords / cellule occupée / boss). col + rect + node cohérents,
## puis re-contrôle de connectivité (un mover peut se déconnecter en glissant).
func _step_movers() -> void:
	var moved_any: bool = false
	var occupied: Dictionary = {}
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		occupied[Vector2i(int(block.get("col", 0)), int(block.get("row", 0)))] = true
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		if str(block.get("type", "normal")) != "mover":
			continue
		var col: int = int(block.get("col", 0))
		var row: int = int(block.get("row", 0))
		var dir: int = 1 if int(block.get("dir", 1)) >= 0 else -1
		var target: int = col + dir
		if target < 0 or target >= _grid_cols or occupied.has(Vector2i(target, row)) or _cell_covered_by_boss(target, row):
			dir = -dir
			block["dir"] = dir
			target = col + dir
			if target < 0 or target >= _grid_cols or occupied.has(Vector2i(target, row)) or _cell_covered_by_boss(target, row):
				continue # coincé ce tour
		occupied.erase(Vector2i(col, row))
		occupied[Vector2i(target, row)] = true
		block["col"] = target
		var rect: Rect2 = block.get("rect", Rect2())
		var shift: float = (_block_size.x + _block_spacing) * float(dir)
		rect.position.x += shift
		block["rect"] = rect
		moved_any = true
		var node_v: Variant = block.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			var tween: Tween = create_tween()
			tween.tween_property(node, "position:x", node.position.x + shift, 0.2) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if moved_any:
		_recompute_connectivity([])

func _cell_covered_by_boss(col: int, row: int) -> bool:
	for boss_v in _bosses:
		var boss: Dictionary = boss_v as Dictionary
		var c0: int = int(boss.get("col_start", 0))
		var r0: int = int(boss.get("row_top", 0))
		if col >= c0 and col < c0 + int(boss.get("cols", 0)) \
			and row >= r0 and row < r0 + int(boss.get("rows", 0)):
			return true
	return false

## Vrai si un boss chevauchant la rangée 0 couvre cette colonne (spawn de
## rangée : ni bloc ni token sous le boss).
func _boss_blocks_col_row0(c: int) -> bool:
	for boss_v in _bosses:
		var boss: Dictionary = boss_v as Dictionary
		if int(boss.get("row_top", 99)) <= 0:
			var c0: int = int(boss.get("col_start", 0))
			if c >= c0 and c < c0 + int(boss.get("cols", 0)):
				return true
	return false

## Rows past the danger line: % max HP damage each (shield first), blocks and
## tokens destroyed without any reward (explosion visuelle seule). Boss qui
## atteint la ligne = défaite immédiate.
func _apply_danger_line_crossings() -> void:
	for boss_v in _bosses:
		var boss_rect: Rect2 = (boss_v as Dictionary).get("rect", Rect2())
		if boss_rect.end.y >= _danger_y:
			_trigger_boss_game_over()
			return
	var crossed_rows: Dictionary = {}
	var crossed_cells: Array = []
	var destroyed_index: int = 0
	for i in range(_blocks.size() - 1, -1, -1):
		var block: Dictionary = _blocks[i]
		var rect: Rect2 = block.get("rect", Rect2())
		if rect.end.y >= _danger_y:
			# Maudit et portails : franchissent SANS blesser le joueur (détruits
			# quand même, connectivité re-contrôlée, explosion visuelle seule).
			var b_type: String = str(block.get("type", "normal"))
			if b_type != "cursed" and not b_type.begins_with("portal_"):
				crossed_rows[int(round(rect.position.y))] = true
			crossed_cells.append(Vector2i(int(block.get("col", 0)), int(block.get("row", 0))))
			if _danger_destroy_explosion:
				_pending_explosions.append({
					"at": _elapsed + float(destroyed_index) * _destruction_stagger,
					"pos": rect.get_center(),
					"size": float(_block_explosion_cfg.get("size", 26.0))
				})
				destroyed_index += 1
			var node_v: Variant = block.get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_blocks.remove_at(i)
	for i in range(_tokens.size() - 1, -1, -1):
		var t_rect: Rect2 = (_tokens[i] as Dictionary).get("rect", Rect2())
		if t_rect.end.y >= _danger_y:
			var t_node_v: Variant = (_tokens[i] as Dictionary).get("node", null)
			if t_node_v is Node2D and is_instance_valid(t_node_v):
				(t_node_v as Node2D).queue_free()
			_tokens.remove_at(i)
	var rows_crossed: int = crossed_rows.size()
	if rows_crossed <= 0:
		return
	# TOUTE destruction impose un re-contrôle du lien plafond/sticky : un
	# sticky rasé par la danger line laisserait sinon ses blocs "ancrés"
	# flotter sans exploser jusqu'à la prochaine destruction par balle.
	_recompute_connectivity(crossed_cells)
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent_row))) * rows_crossed
		_player.call("take_damage", dmg)
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(8, 0.3)

# =============================================================================
# MAIN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# A dead player means the game-over flow took over: freeze the wave
	# without emitting finished.
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_bonus_block_cooldown = maxf(0.0, _bonus_block_cooldown - delta)
	_update_countdown_label()
	_update_danger_pulse()
	_update_danger_warning()
	_update_aim_zone_hint()
	_update_events(delta)
	_process_pending_destructions()
	_process_pending_explosions()
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.AIM
				_refresh_counter_labels()
		State.AIM:
			_handle_keyboard_aim(delta)
			if _aim_armed:
				_update_aim_line()
		State.VOLLEY:
			_update_volley(delta)
		State.STEP:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.AIM
	if _elapsed >= _duration:
		_finish()

## Desktop comfort: arrows reposition the ship between volleys.
func _handle_keyboard_aim(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var move: float = 0.0
	if Input.is_action_pressed("ui_left"):
		move -= 1.0
	if Input.is_action_pressed("ui_right"):
		move += 1.0
	if move != 0.0 and _touch_id == -1:
		_set_ship_target_x(_player.global_position.x + move * 620.0 * delta)

func _update_danger_pulse() -> void:
	if _danger_line == null or not is_instance_valid(_danger_line):
		return
	var base_a: float = Color(str(_get_conf("danger_line_color", "#FF5A5AC8"))).a
	_danger_line.modulate.a = lerpf(0.55, 1.0, 0.5 + 0.5 * sin(TAU * _elapsed / _danger_pulse_sec)) * base_a

# =============================================================================
# ÉVÉNEMENTS AUTOMATIQUES (MODE LIBRE uniquement — cooldown global 3 min)
# =============================================================================

## Scheduler : cooldown global event_cooldown_sec entre deux événements,
## tirage pondéré (events_weights) avec anti-répétition, déclenchement en état
## AIM seulement, télégraphie 1.5 s par bandeau puis exécution.
func _update_events(delta: float) -> void:
	# Timers d'effets en cours (tournent dans tous les états).
	if _fog_time > 0.0:
		_fog_time -= delta
		if _fog_time <= 0.0:
			_set_fog_enabled(false)
	if _frenzy_time > 0.0:
		_frenzy_time -= delta
	if _event_banner_time > 0.0:
		_event_banner_time -= delta
		if _event_banner_label and is_instance_valid(_event_banner_label):
			_event_banner_label.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 8.0))
			if _event_banner_time <= 0.0:
				_event_banner_label.visible = false
	# Télégraphe en cours -> exécution.
	if _pending_event != "":
		_pending_event_delay -= delta
		if _pending_event_delay <= 0.0:
			var event_id: String = _pending_event
			_pending_event = ""
			_execute_event(event_id)
		return
	if not _events_enabled:
		return
	_event_timer -= delta
	if _event_timer > 0.0 or _state != State.AIM:
		return
	_event_timer = maxf(10.0, float(_get_conf("event_cooldown_sec", 180.0)))
	var picked: String = _pick_event()
	if picked == "":
		return
	_last_event = picked
	_pending_event = picked
	_pending_event_delay = 1.5
	_show_event_banner(picked)

## Tirage pondéré avec anti-répétition (jamais deux fois de suite le même) ;
## double_boss retiré si un boss est déjà vivant.
func _pick_event() -> String:
	var weights_v: Variant = _get_conf("events_weights", {})
	var weights: Dictionary = (weights_v as Dictionary).duplicate() if weights_v is Dictionary else {}
	if weights.is_empty():
		weights = {"fog": 20, "bonus_row": 25, "quake": 20, "double_boss": 15, "frenzy": 20}
	weights.erase(_last_event)
	if not _bosses.is_empty() or _boss_defs.is_empty():
		weights.erase("double_boss")
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

func _execute_event(event_id: String) -> void:
	match event_id:
		"fog":
			_fog_time = maxf(2.0, float(_get_conf("fog_duration_sec", 12.0)))
			_set_fog_enabled(true)
		"bonus_row":
			_bonus_row_pending = true
		"quake":
			_do_quake()
		"double_boss":
			_spawn_event_bosses()
		"frenzy":
			_frenzy_time = maxf(2.0, float(_get_conf("frenzy_duration_sec", 10.0)))
		_:
			pass

## Brouillard : masque les numéros HP des blocs au-delà de fog_visible_rows
## (chaque bloc porte sa réf Label ; ré-appliqué à chaque descente et aux
## nouveaux spawns, tout rétabli à expiration).
func _set_fog_enabled(enabled: bool) -> void:
	var visible_rows: int = maxi(0, int(_get_conf("fog_visible_rows", 2)))
	for block_v in _blocks:
		var block: Dictionary = block_v as Dictionary
		var label_v: Variant = block.get("label", null)
		if label_v is Label and is_instance_valid(label_v):
			(label_v as Label).visible = not enabled or int(block.get("row", 0)) < visible_rows

## Séisme : la grille remonte d'un cran si la rangée 0 est libre (blocs ET
## boss) ; sinon fallback équivalent : la rangée occupée la plus basse est
## rasée AVEC récompenses. Répit dans les deux cas.
func _do_quake() -> void:
	if VFXManager and bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(10, 0.4)
	var row0_free: bool = true
	for block_v in _blocks:
		if int((block_v as Dictionary).get("row", 0)) <= 0:
			row0_free = false
			break
	if row0_free:
		for boss_v in _bosses:
			if int((boss_v as Dictionary).get("row_top", 0)) <= 0:
				row0_free = false
				break
	if row0_free and not (_blocks.is_empty() and _bosses.is_empty()):
		_shift_grid(-_descend_step, -1)
		return
	var max_row: int = -1
	for block_v in _blocks:
		max_row = maxi(max_row, int((block_v as Dictionary).get("row", 0)))
	if max_row < 0:
		return
	var order: int = 0
	for block_v in _blocks.duplicate():
		var block: Dictionary = block_v as Dictionary
		if int(block.get("row", 0)) == max_row:
			_queue_block_destruction(block, float(order) * _destruction_stagger, true)
			order += 1

## Double boss : 2 mini-boss (event_boss_cols × event_boss_rows, HP réduits)
## sur des moitiés de grille disjointes.
func _spawn_event_bosses() -> void:
	if _boss_defs.is_empty() or not _bosses.is_empty():
		return
	var cols: int = clampi(int(_get_conf("event_boss_cols", 2)), 1, maxi(1, _grid_cols / 2))
	var rows: int = clampi(int(_get_conf("event_boss_rows", 2)), 1, 8)
	var hp_mult: float = clampf(float(_get_conf("event_boss_hp_mult", 0.5)), 0.05, 2.0)
	var half: int = _grid_cols / 2
	var col_a: int = randi_range(0, maxi(0, half - cols))
	var col_b: int = randi_range(half, maxi(half, _grid_cols - cols))
	_spawn_boss(randi() % _boss_defs.size(), cols, rows, hp_mult, col_a)
	_spawn_boss(randi() % _boss_defs.size(), cols, rows, hp_mult, col_b)

## Bandeau d'annonce d'événement (texte localisé ball_launcher_event_<id>).
func _show_event_banner(event_id: String) -> void:
	if _event_banner_label == null or not is_instance_valid(_event_banner_label):
		var viewport_size: Vector2 = get_viewport_rect().size
		_event_banner_label = Label.new()
		_event_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_event_banner_label.add_theme_font_size_override("font_size", 38)
		_event_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_event_banner_label.add_theme_constant_override("outline_size", 5)
		_event_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event_banner_label.z_as_relative = false
		_event_banner_label.z_index = 59
		_event_banner_label.size = Vector2(viewport_size.x, 46.0)
		_event_banner_label.position = Vector2(0.0, viewport_size.y * 0.3)
		add_child(_event_banner_label)
	_event_banner_label.text = _translate_or("ball_launcher_event_" + event_id, event_id.to_upper())
	_event_banner_label.add_theme_color_override("font_color", Color("#FFD56B"))
	_event_banner_label.visible = true
	_event_banner_time = 2.0

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "BallLauncherCountdownLabel"
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

## Deux encadrés fixes en bas à droite : nombre de balles (armada) et
## puissance par balle. Frames PNG data (counter_frame_*_asset — cadre à fond
## uni), fallback panel coloré ; nombre en gros par-dessus.
func _build_counter_boxes() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var box_w: float = maxf(32.0, float(_get_conf("counter_width_px", 84.0)))
	var box_h: float = maxf(24.0, float(_get_conf("counter_height_px", 56.0)))
	var margin: float = maxf(0.0, float(_get_conf("counter_margin_px", 12.0)))
	var y: float = viewport_size.y - box_h - margin
	# Power à l'extrême droite, balles juste à gauche.
	var power_x: float = viewport_size.x - box_w - margin
	var ball_x: float = power_x - box_w - margin * 0.5
	_counter_ball_label = _make_counter_box(Vector2(ball_x, y), Vector2(box_w, box_h),
		_counter_ball_frame_tex, Color(str(_get_conf("counter_ball_bg_color", "#1C2B3AE0"))),
		Color(str(_get_conf("ball_color", "#8FD3FF"))))
	_counter_power_label = _make_counter_box(Vector2(power_x, y), Vector2(box_w, box_h),
		_counter_power_frame_tex, Color(str(_get_conf("counter_power_bg_color", "#3A1C1CE0"))),
		Color(str(_get_conf("power_token_tint", "#FF8A5C"))))
	_refresh_counter_labels()

## Construit un encadré (frame PNG étirée ou panel uni) + label ; retourne le label.
func _make_counter_box(pos: Vector2, size: Vector2, frame_tex: Texture2D, bg_color: Color, text_color: Color) -> Label:
	var box: Control
	if frame_tex != null:
		var texture_rect := TextureRect.new()
		texture_rect.texture = frame_tex
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		box = texture_rect
	else:
		var panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg_color
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 10
		sb.corner_radius_bottom_right = 10
		panel.add_theme_stylebox_override("panel", sb)
		box = panel
	box.position = pos
	box.size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_as_relative = false
	box.z_index = 60
	add_child(box)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(10, int(_get_conf("counter_font_size", 30))))
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return label

func _refresh_counter_labels() -> void:
	if _counter_ball_label and is_instance_valid(_counter_ball_label):
		_counter_ball_label.text = str(_ball_count)
	if _counter_power_label and is_instance_valid(_counter_power_label):
		_counter_power_label.text = str(_ball_power)

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Flush synchrone des destructions en attente : récompenses accordées, sans
	# VFX (le score d'une cascade en cours ne doit pas être perdu). Les effets
	# explosifs peuvent ré-enfiler pendant le flush -> boucle while.
	while not _pending_destructions.is_empty():
		var entry: Dictionary = _pending_destructions.pop_back() as Dictionary
		_destroy_block_immediate(entry.get("block", {}) as Dictionary, bool(entry.get("rewarded", false)), false)
	_pending_explosions.clear()
	_recall_balls()
	# Restore the player and the HUD BEFORE notifying the wave chain.
	_restore_player_mode()
	_restore_hud_mode()
	finished.emit()
	queue_free() # grid, balls, lines and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player/HUD if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
		_restore_hud_mode()
