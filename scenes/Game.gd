extends Node2D

## Game — Scène principale du gameplay.
## Spawn le joueur, ennemis, gère le background animé.

# =============================================================================
# REFERENCES
# =============================================================================

@onready var background: TextureRect = $Background
@onready var game_layer: Node2D = $GameLayer
@onready var hud_container: Control = $UI/HUD
@onready var camera: Camera2D = $Camera2D

const SCROLLING_LAYER_SCRIPT: Script = preload("res://scenes/ScrollingLayer.gd")
const ENEMY_SCRIPT: Script = preload("res://scenes/Enemy.gd")
const WAVE_MANAGER_SCRIPT: Script = preload("res://scenes/WaveManager.gd")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/Boss.tscn")
const TOXIC_POOL_SCENE: PackedScene = preload("res://scenes/effects/ToxicPool.tscn")
const KILLSTREAK_MANAGER_SCRIPT: Script = preload("res://autoload/KillstreakManager.gd")
const BONUS_CRYSTAL_SCENE: PackedScene = preload("res://scenes/pickups/BonusCrystal.tscn")
const FIRE_PATTERN_DROP_SCENE: PackedScene = preload("res://scenes/pickups/FirePatternDrop.tscn")
const LOOT_DROP_SCENE: PackedScene = preload("res://scenes/LootDrop.tscn")
const SNAKE_SCENE: PackedScene = preload("res://scenes/mechanics/SnakeManager.tscn")
const GATE_RUNNER_SCENE: PackedScene = preload("res://scenes/mechanics/GateRunnerManager.tscn")
const PONG_SCENE: PackedScene = preload("res://scenes/mechanics/PongManager.tscn")
const BREAKOUT_SCENE: PackedScene = preload("res://scenes/mechanics/BreakoutManager.tscn")
const BALL_LAUNCHER_SCENE: PackedScene = preload("res://scenes/mechanics/BallLauncherManager.tscn")
const VERTICAL_CLIMB_SCENE: PackedScene = preload("res://scenes/mechanics/VerticalClimbManager.tscn")
const ABSORB_SCENE: PackedScene = preload("res://scenes/mechanics/AbsorbManager.tscn")
const LANE_RUNNER_SCENE: PackedScene = preload("res://scenes/mechanics/LaneRunnerManager.tscn")
const SLICE_RUSH_SCENE: PackedScene = preload("res://scenes/mechanics/SliceRushManager.tscn")
const MATCH3_SCENE: PackedScene = preload("res://scenes/mechanics/Match3Manager.tscn")
const GRAVITY_HOLE_SCENE: PackedScene = preload("res://scenes/mechanics/GravityHoleManager.tscn")
const STAR_DRIFT_SCENE: PackedScene = preload("res://scenes/mechanics/StarDriftManager.tscn")
const SUIKA_UP_SCENE: PackedScene = preload("res://scenes/mechanics/SuikaUpManager.tscn")
const SURVIVOR_SCENE: PackedScene = preload("res://scenes/mechanics/SurvivorManager.tscn")
const RUNTIME_WARMUP_PATHS: PackedStringArray = [
	"res://scenes/mechanics/SurvivorManager.tscn",
	"res://scenes/obstacles/ObstacleExplosive.tscn",
	"res://scenes/obstacles/ObstaclePusher.tscn",
	"res://scenes/objects/Mine.tscn",
	"res://scenes/objects/ArcaneOrb.tscn",
	"res://scenes/objects/GravityWell.tscn",
	"res://scenes/objects/SuppressorShield.tscn",
	"res://scenes/LootDrop.tscn",
	"res://scenes/effects/ToxicPool.tscn",
	"res://scenes/effects/Singularity.tscn",
	"res://scenes/effects/IceAura.tscn",
	"res://scenes/effects/IceShards.tscn",
	"res://scenes/effects/VacuumRadius.tscn",
	"res://scenes/pickups/BonusCrystal.tscn",
	"res://scenes/pickups/FirePatternDrop.tscn",
	"res://scenes/mechanics/PathTrial.tscn",
	"res://scenes/mechanics/SnakeManager.tscn",
	"res://scenes/mechanics/GateRunnerManager.tscn",
	"res://scenes/mechanics/MathGate.tscn",
	"res://scenes/mechanics/PongManager.tscn",
	"res://scenes/mechanics/BreakoutManager.tscn",
	"res://scenes/mechanics/BallLauncherManager.tscn",
	"res://scenes/mechanics/VerticalClimbManager.tscn",
	"res://scenes/mechanics/AbsorbManager.tscn",
	"res://scenes/mechanics/LaneRunnerManager.tscn",
	"res://scenes/mechanics/SliceRushManager.tscn",
	"res://scenes/mechanics/Match3Manager.tscn",
	"res://scenes/mechanics/GravityHoleManager.tscn",
	"res://scenes/mechanics/StarDriftManager.tscn",
	"res://scenes/mechanics/SuikaUpManager.tscn",
	"res://scenes/Projectile.tscn",
	"res://scenes/abilities/objects/Wall.tscn",
	"res://scenes/abilities/WallSpawner.gd",
	"res://scenes/effects/BossVoidZone.gd",
	"res://scenes/effects/BossLaserZone.gd"
]
const RUNTIME_WARMUP_PREFIXES: PackedStringArray = [
	"res://scenes/abilities/",
	"res://scenes/effects/",
	"res://scenes/mechanics/",
	"res://scenes/objects/",
	"res://scenes/pickups/",
	"res://scenes/LootDrop",
	"res://scenes/Projectile",
	"res://scenes/obstacles/"
]
const DEBUG_PERF_HITCH_LOG := true
const DEBUG_PERF_HITCH_THRESHOLD_MS := 22.0
const DEBUG_PERF_HITCH_COOLDOWN_MS := 250
const DEBUG_LEVEL_WARMUP_LOG := true
const DEBUG_RUNTIME_ENEMY_PREWARM_LOG := true
const DEBUG_SPAWN_PIPELINE_LOG := false
const DEBUG_SPAWN_PIPELINE_THRESHOLD_MS := 4.0
const OVERRIDE_STRONG_RESOURCE_CACHE_MAX: int = 128

var player: CharacterBody2D = null
var hud: CanvasLayer = null
var boss_hud: Control = null
var pause_menu: CanvasLayer = null

var enemies_killed: int = 0
var boss_spawned: bool = false
var session_loot: Array = [] # Track items collected in this session
var active_boss: CharacterBody2D = null
var _end_session_started: bool = false
var _player_death_registered: bool = false
var _wave_total_with_boss: int = 0
var _boss_sequence_ids: Array[String] = []
var _boss_sequence_index: int = -1
var _boss_sequence_active: bool = false
var session_score: int = 0 # Single source of truth for run score.
var session_crystals_gained: int = 0 # Cristaux MONNAIE gagnés cette session (pickups, chest, overrides) — affiché en fin de run.
var session_xp: int = 0  # Kept in sync with session_score for XP/crystal formulas.
var _end_screen_delay_seconds: float = 1.5
var _boss_spawn_top_margin_px: float = 28.0
var _boss_spawn_entry_duration_sec: float = 0.55
var _end_screen_context_action: String = "level_select"

const END_SCREEN_ACTION_LEVEL_SELECT := "level_select"
const END_SCREEN_ACTION_NEXT_LEVEL := "next_level"
const END_SCREEN_ACTION_WORLD_SELECT := "world_select"
const END_SCREEN_ACTION_FREE_MODE_SELECT := "free_mode_select"

# Mode libre : un wave_type en boucle infinie (App.free_mode_active). Le niveau
# joué est synthétique (index réservé, injecté dans DataManager._levels).
const FREE_MODE_LEVEL_INDEX: int = 99
var _free_mode_session: bool = false
var _free_mode_wave_type: String = ""
var _free_mode_splash_shown: bool = false

var current_level_index: int = 0 # Défini par LevelSelect ou WorldSelect
var current_world_id: String = "world_1" # Par défaut, peut être change par WorldSelect
var _world_multipliers: Dictionary = {"hp": 1.0, "damage": 1.0, "speed": 1.0}
var _world_skin_overrides: Dictionary = {} # Centralized skin overrides from world JSON
var _last_hitch_log_ms: int = -10000
var _loot_drop_rules: Dictionary = {}
var _wave_powerup_drop_counts: Dictionary = {"shield": 0, "fire_rate": 0}
var _wave_equipment_drop_count: int = 0
var _active_override_protocol_ids: Array = []
var _active_override_protocol_map: Dictionary = {}
var _override_protocol_settings_map: Dictionary = {}
var _override_ui_settings: Dictionary = {}
var _override_enemy_move_multiplier: float = 1.0
var _override_enemy_hp_multiplier: float = 1.0
var _override_enemy_projectile_speed_multiplier: float = 1.0
var _override_enemy_elite_replacement_chance: float = 0.0
var _override_player_heal_multiplier: float = 1.0
var _override_player_start_hp: int = -1
var _override_reward_multiplier: float = 1.0
var _override_crystal_multiplier: float = 1.0
var _override_crystal_reward_per_score: float = 0.0
var _override_crystal_reward_victory_only: bool = true
var _override_force_one_hp: bool = false
var _override_enable_toxic_pools: bool = false
var _override_enable_volatile_reactors: bool = false
var _override_enable_boss_overdrive: bool = false
var _override_emp_vignette_enabled: bool = false
var _override_toxic_pool_timer: float = 0.0
var _override_toxic_pool_nodes: Array[Node] = []
var _override_vignette_rect: ColorRect = null
var _override_strong_resource_cache: Dictionary = {}
var _override_toxic_pool_spawn_interval_sec: float = 6.0
var _override_toxic_pool_radius: float = 82.0
var _override_toxic_pool_duration_sec: float = 4.5
var _override_toxic_pool_dps: float = 16.0
var _override_toxic_pool_max_active: int = 3
var _override_toxic_pool_visual_data: Dictionary = {}
var _override_toxic_pool_behavior_data: Dictionary = {}
var _override_volatile_trigger_chance: float = 0.3
var _override_volatile_explosion_mode_chance: float = 0.5
var _override_volatile_explosion_radius: float = 92.0
var _override_volatile_explosion_damage: int = 14
var _override_volatile_projectile_speed: float = 290.0
var _override_volatile_projectile_damage: int = 12
var _override_volatile_projectile_count: int = 3
var _override_volatile_projectile_spread_rad: float = 0.35
var _override_volatile_explosion_asset: String = ""
var _override_volatile_explosion_asset_anim: String = ""
var _override_volatile_explosion_asset_anim_duration: float = 0.0
var _override_volatile_explosion_asset_anim_loop: bool = false
var _override_volatile_explosion_size_multiplier: float = 0.45
var _override_volatile_explosion_lifetime: float = -1.0
var _override_volatile_explosion_fade_out_duration: float = 0.3
var _override_volatile_explosion_color: Color = Color(1.0, 0.35, 0.1, 0.75)
var _override_boss_overdrive_fire_rate: float = 0.05
var _override_emp_vignette_strength: float = 0.72
var _override_emp_vignette_radius: float = 0.58
var _override_emp_vignette_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var _overlay_rect: ColorRect = null

# Temporary wave background override (gravity_hole "dimension" swap): a second
# scrolling container above the base one, alpha-faded in/out. Game-owned so it
# survives any manager failure mode and dies with the scene.
var _wave_bg_container: Node2D = null
var _wave_bg_tween: Tween = null
var _wave_bg_active: bool = false
var _wave_bg_path: String = ""
var _killstreak_manager: Node = null
var _killstreak_cfg: Dictionary = {}
var _bonus_crystals_cfg: Dictionary = {}
var _killstreak_warning_active: bool = false
var _active_bonus_crystals: Array[Node] = []
var _fire_pattern_drops_cfg: Dictionary = {}
var _active_fire_pattern_drops: Array[Node] = []
var _fire_pattern_drop_count: int = 0
var _active_snake_managers: Array[Node] = []
var _snake_wave_active: bool = false
var _active_gate_runners: Array[Node] = []
# True while a gate_runner wave is running: the player does not fire, so fire
# pattern drops and power-ups (shield/rapid fire) are suppressed.
var _gate_runner_wave_active: bool = false
var _active_pong_managers: Array[Node] = []
# True while a pong wave is running: same drop suppression as gate_runner.
var _pong_wave_active: bool = false
var _active_breakout_managers: Array[Node] = []
# True while a breakout wave is running: same drop suppression as gate_runner.
var _breakout_wave_active: bool = false
var _active_ball_launcher_managers: Array[Node] = []
# True while a ball_launcher wave is running: same drop suppression.
var _ball_launcher_wave_active: bool = false
var _active_climb_managers: Array[Node] = []
# True while a vertical_climb wave is running: same drop suppression.
var _climb_wave_active: bool = false
var _active_absorb_managers: Array[Node] = []
# True while an absorb wave is running: same drop suppression.
var _absorb_wave_active: bool = false
var _active_lane_runner_managers: Array[Node] = []
# True while a lane_runner wave is running: same drop suppression.
var _lane_runner_wave_active: bool = false
var _active_slice_rush_managers: Array[Node] = []
# True while a slice_rush wave is running: same drop suppression.
var _slice_rush_wave_active: bool = false
var _active_match3_managers: Array[Node] = []
# True while a match3 wave is running: same drop suppression.
var _match3_wave_active: bool = false
var _active_gravity_hole_managers: Array[Node] = []
# True while a gravity_hole wave is running: same drop suppression.
var _gravity_hole_wave_active: bool = false
var _active_star_drift_managers: Array[Node] = []
# True while a star_drift wave is running: same drop suppression.
var _star_drift_wave_active: bool = false
var _active_suika_up_managers: Array[Node] = []
# True while a suika_up wave is running: same drop suppression.
var _suika_up_wave_active: bool = false
var _active_survivor_managers: Array[Node] = []
# True while a survivor wave is running: same drop suppression (les récompenses
# passent par gemmes XP + coffres du manager).
var _survivor_wave_active: bool = false
# Asteroid_split wave state: config cached at wave start (split handling reads
# it on every asteroid kill), plus a hard cap counter (mobile perf).
var _asteroid_field_cfg: Dictionary = {}
var _asteroid_field_wave: Dictionary = {}
var _asteroid_field_base_speed: float = 120.0
var _active_asteroid_count: int = 0
var _wave_splash_cfg: Dictionary = {
	"enabled": true,
	"color": "#FFFFFF",
	"font_size": 92,
	"zoom_start": 0.0,
	"zoom_end": 1.0,
	"animation_duration_sec": 0.65,
	"warning_duration_sec": 1.4,
	"warning_delay_sec": 0.4,
	"warning_margin_top": 30.0
}
var _wave_splash_label: Label = null
var _wave_splash_sub_label: Label = null
var _wave_splash_tween: Tween = null
var _wave_splash_warning_tween: Tween = null
var _run_bootstrap_done: bool = false
var _performance_cfg: Dictionary = {}
var _dev_runtime_tuning_reload: bool = false
var _warmup_runtime_support_enabled: bool = true
var _warmup_runtime_nodes_enabled: bool = true
var _warmup_collect_external_json_enabled: bool = true
var _log_hitches_enabled: bool = false
var _log_level_warmup_enabled: bool = false
var _log_runtime_enemy_prewarm_enabled: bool = false

func track_loot(item: Dictionary) -> void:
	session_loot.append(item)

# =============================================================================
# BACKGROUND
# =============================================================================

func _ready() -> void:
	# Load session data
	current_world_id = App.current_world_id
	current_level_index = App.current_level_index
	_free_mode_session = App.free_mode_active and str(App.free_mode_wave_type) != ""
	if _free_mode_session:
		_free_mode_wave_type = str(App.free_mode_wave_type)
		# Registered BEFORE any get_level_data read (background, wave counter,
		# prewarm, end screen) so the whole pipeline sees a coherent level.
		_register_free_mode_level()
		current_level_index = FREE_MODE_LEVEL_INDEX
		App.current_level_index = FREE_MODE_LEVEL_INDEX
		# Historique du mode : une run lancée = une partie jouée.
		if ProfileManager and ProfileManager.has_method("increment_free_mode_plays"):
			ProfileManager.increment_free_mode_plays(_free_mode_wave_type)
	print("[Game] Ready. Level: ", current_world_id, " | Index: ", current_level_index)
	_load_gameplay_config()
	_setup_scoring_system()
	_load_override_protocol_state()
	
	add_to_group("game_controller")
	
	# Reset Managers
	EnemyAbilityManager.reset()
	ENEMY_SCRIPT._logged_patterns.clear()
	
	# Music
	var world = App.get_world(current_world_id)
	_world_multipliers = world.get("multipliers", {"hp": 1.0, "damage": 1.0, "speed": 1.0})
	_world_skin_overrides = DataManager.get_world_skin_overrides(current_world_id)
	print("[Game] World multipliers: ", _world_multipliers)
	print("[Game] World skin overrides keys: ", _world_skin_overrides.keys())
	var world_theme = world.get("theme", {})
	var music = str(world_theme.get("music", ""))
	if music != "":
		App.play_music(music)
	else:
		App.play_menu_music() # Enforce menu music if no override
	
	_setup_camera()
	_setup_background()
	_setup_hud()
	_spawn_player()
	_setup_projectile_manager()
	_setup_fluid_simulation()
	_preload_override_visual_resources()
	_setup_emp_vignette()
	# Keep heavy runtime warmup inside scene init so it happens behind the loading layer.
	_start_enemy_spawner()
	# Gameplay bootstrap (story gate + first combat start) is handled in run_post_loading_story().
	# Keep player disarmed until that sequence explicitly unlocks combat.
	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		player.set_can_shoot(false)

## Niveau synthétique du mode libre : nom localisé du mode, background = tuile
## du mode, une vague placeholder (WaveManager régénère la vraie vague scalée
## dans setup()/à chaque boucle), aucun seuil d'étoiles.
func _register_free_mode_level() -> void:
	var mode_cfg: Dictionary = DataManager.get_freemode_mode_config(_free_mode_wave_type)
	# Fiesta : pas de bloc modes.<type> — config racine freemode.json > fiesta.
	if _free_mode_wave_type == "fiesta":
		var fiesta_v: Variant = DataManager.get_freemode_config().get("fiesta", {})
		if fiesta_v is Dictionary:
			mode_cfg = fiesta_v as Dictionary
	# Fond du niveau : pioché au hasard dans wave_types.json > <type> >
	# level_backgrounds[] (plusieurs fonds possibles par type) ; fallback =
	# tile_background du mode (freemode.json).
	var bg_path: String = str(mode_cfg.get("tile_background", ""))
	var type_cfg: Dictionary = DataManager.get_wave_type_config(_free_mode_wave_type)
	var bgs_v: Variant = type_cfg.get("level_backgrounds", [])
	if bgs_v is Array and not (bgs_v as Array).is_empty():
		var bgs: Array = bgs_v as Array
		var picked: String = str(bgs[randi() % bgs.size()])
		if picked != "":
			bg_path = picked
	var level_id: String = current_world_id + "_lvl_" + str(FREE_MODE_LEVEL_INDEX)
	DataManager.register_synthetic_level(level_id, {
		"index": FREE_MODE_LEVEL_INDEX,
		"id": level_id,
		"name": LocaleManager.translate("game_wave_" + _free_mode_wave_type),
		"type": "normal",
		"backgrounds": {"far_layer": bg_path, "near_layer": []},
		"waves": [{"type": _free_mode_wave_type}],
		"score_1star": 0,
		"score_2stars": 0,
		"score_3stars": 0
	})

func _update_free_mode_level_label(level: int) -> void:
	if hud and hud.has_method("set_wave_label_override"):
		hud.call("set_wave_label_override", LocaleManager.translate("free_mode_level", {"level": str(level)}))

func _on_free_mode_level_changed(level: int) -> void:
	_update_free_mode_level_label(level)
	# Récompense de palier (mode libre uniquement, jamais en story) : soin de
	# level_up_heal_percent des HP max (0.4 = 40 %) à chaque montée de level
	# (freemode.json > leveling). Fallback legacy : full_heal_on_level_up
	# (bool) = 100 %. Set direct : ignore volontairement le multiplicateur de
	# soin.
	var leveling_v: Variant = DataManager.get_freemode_config().get("leveling", {})
	if leveling_v is Dictionary:
		var leveling: Dictionary = leveling_v as Dictionary
		var heal_pct: float = clampf(float(leveling.get("level_up_heal_percent",
			1.0 if bool(leveling.get("full_heal_on_level_up", true)) else 0.0)), 0.0, 1.0)
		if heal_pct > 0.0 and is_instance_valid(player) and player.current_hp < player.max_hp:
			player.current_hp = mini(player.max_hp,
				player.current_hp + maxi(1, int(ceil(float(player.max_hp) * heal_pct))))
			# Gate runner : le set direct ne rafraîchit ni le gros label HP ni
			# l'essaim de clones — opération arithmétique no-op pour resynchroniser
			# (early-return dans Player si le mode gate_runner n'est pas actif).
			if player.has_method("apply_gate_operation"):
				player.call("apply_gate_operation", "add", 0.0)
			if VFXManager and hud_container:
				VFXManager.spawn_floating_text(
					player.global_position + Vector2(0.0, -50.0),
					LocaleManager.translate("free_mode_full_heal"),
					Color("#7FE58C"), hud_container)
	# Modes "continuous" (ex. pong) : la difficulté du manager en place est
	# re-scalée sans le recréer (pas de réengagement de balle/état).
	if wave_manager and is_instance_valid(wave_manager) and wave_manager.has_method("build_free_mode_wave"):
		var scaled_wave: Dictionary = wave_manager.call("build_free_mode_wave", level)
		for node in get_tree().get_nodes_in_group("runtime_hazards"):
			if is_instance_valid(node) and node.has_method("update_free_mode_config"):
				node.call("update_free_mode_config", scaled_wave)

func run_post_loading_story() -> void:
	if _run_bootstrap_done:
		return
	_run_bootstrap_done = true

	_clean_start_of_run_state()

	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		player.set_can_shoot(false)

	await _play_level_story_if_needed()
	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		player.set_can_shoot(true)
	# Waves only start now: setup() ran behind the loading screen and queuing
	# wave 1 earlier made it play hidden (enemy waves) or get cleared/skipped
	# by _clean_start_of_run_state (manager waves).
	if wave_manager and is_instance_valid(wave_manager) and wave_manager.has_method("start_waves"):
		wave_manager.call("start_waves")

func _clean_start_of_run_state() -> void:
	# Hard cleanup so the level always starts from a clean visual/combat state.
	if ProjectileManager:
		ProjectileManager.clear_all_projectiles()
	_clear_bonus_crystals()
	_clear_fire_pattern_drops()
	_clear_gate_runners()
	_clear_pong_managers()
	_clear_breakout_managers()
	_clear_ball_launcher_managers()
	_clear_climb_managers()
	_clear_absorb_managers()
	_clear_lane_runner_managers()
	_clear_slice_rush_managers()
	_clear_match3_managers()
	_clear_gravity_hole_managers()
	_clear_suika_up_managers()
	_clear_survivor_managers()

func _play_level_story_if_needed() -> bool:
	var stories: Array = DataManager.get_stories_for_trigger_start(current_world_id, current_level_index)
	var played_any: bool = false
	for story in stories:
		if not (story is Dictionary):
			continue
		var story_id: String = str((story as Dictionary).get("id", ""))
		if story_id == "" or ProfileManager.has_viewed_story(story_id):
			continue
		get_tree().paused = true
		await StoryManager.play_story(story_id, true)
		ProfileManager.mark_story_viewed(story_id)
		played_any = true
		get_tree().paused = false
	return played_any

func _load_gameplay_config() -> void:
	var game_cfg: Dictionary = DataManager.get_game_config()
	_load_performance_config(game_cfg)
	# Prefer fresh disk read so tuning in game.json is reflected without full app restart.
	if _dev_runtime_tuning_reload and FileAccess.file_exists("res://data/game.json"):
		var f := FileAccess.open("res://data/game.json", FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				game_cfg = json.data as Dictionary
				_load_performance_config(game_cfg)
			f.close()
	var gameplay_cfg: Variant = game_cfg.get("gameplay", {})
	if not (gameplay_cfg is Dictionary):
		_loot_drop_rules = _build_default_loot_drop_rules()
		return

	_loot_drop_rules = _build_default_loot_drop_rules()
	var loot_cfg: Variant = (gameplay_cfg as Dictionary).get("loot_drops", {})
	if loot_cfg is Dictionary:
		_loot_drop_rules.merge((loot_cfg as Dictionary), true)

	var end_session_cfg: Variant = (gameplay_cfg as Dictionary).get("end_session", {})
	if end_session_cfg is Dictionary:
		_end_screen_delay_seconds = maxf(0.0, float((end_session_cfg as Dictionary).get("post_battle_delay_seconds", 1.5)))

	var boss_spawn_cfg: Variant = (gameplay_cfg as Dictionary).get("boss_spawn", {})
	if boss_spawn_cfg is Dictionary:
		_boss_spawn_top_margin_px = maxf(0.0, float((boss_spawn_cfg as Dictionary).get("top_margin_px", 28.0)))
		_boss_spawn_entry_duration_sec = maxf(0.0, float((boss_spawn_cfg as Dictionary).get("entry_duration_sec", 0.55)))

	var wave_splash_cfg_v: Variant = (gameplay_cfg as Dictionary).get("wave_splash", {})
	if wave_splash_cfg_v is Dictionary:
		_wave_splash_cfg.merge(wave_splash_cfg_v as Dictionary, true)

func _load_performance_config(game_cfg: Dictionary) -> void:
	var perf_v: Variant = game_cfg.get("performance", {})
	_performance_cfg = (perf_v as Dictionary).duplicate(true) if perf_v is Dictionary else {}
	var debug_build: bool = OS.is_debug_build()
	_dev_runtime_tuning_reload = debug_build and bool(_performance_cfg.get("dev_runtime_tuning_reload", false))
	_warmup_runtime_support_enabled = bool(_performance_cfg.get("warmup_runtime_support", true))
	_warmup_runtime_nodes_enabled = bool(_performance_cfg.get("warmup_runtime_nodes", true))
	_warmup_collect_external_json_enabled = debug_build and bool(_performance_cfg.get("warmup_collect_external_json", false))
	_log_hitches_enabled = debug_build and bool(_performance_cfg.get("log_hitches", false))
	_log_level_warmup_enabled = debug_build and bool(_performance_cfg.get("log_level_warmup", false))
	_log_runtime_enemy_prewarm_enabled = debug_build and bool(_performance_cfg.get("log_runtime_enemy_prewarm", false))

func _setup_scoring_system() -> void:
	_killstreak_cfg = DataManager.get_killstreak_config()
	_bonus_crystals_cfg = DataManager.get_bonus_crystals_config()
	_fire_pattern_drops_cfg = DataManager.get_fire_pattern_drops_config()
	_killstreak_warning_active = false

	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		_killstreak_manager.queue_free()
	_killstreak_manager = KILLSTREAK_MANAGER_SCRIPT.new()
	add_child(_killstreak_manager)
	_killstreak_manager.call("configure", _killstreak_cfg)

	if _killstreak_manager.has_signal("streak_warning") and not _killstreak_manager.streak_warning.is_connected(_on_killstreak_warning):
		_killstreak_manager.streak_warning.connect(_on_killstreak_warning)
	if _killstreak_manager.has_signal("streak_updated") and not _killstreak_manager.streak_updated.is_connected(_on_killstreak_updated):
		_killstreak_manager.streak_updated.connect(_on_killstreak_updated)
	if _killstreak_manager.has_signal("streak_ended") and not _killstreak_manager.streak_ended.is_connected(_on_killstreak_ended):
		_killstreak_manager.streak_ended.connect(_on_killstreak_ended)

func _on_killstreak_warning(_time_left: float, _ratio: float) -> void:
	_killstreak_warning_active = true

func _on_killstreak_updated(
	_kill_count: int,
	_multiplier: float,
	_time_left: float,
	_time_ratio: float,
	_tier_id: String,
	_tier_label: String
) -> void:
	_killstreak_warning_active = false

func _on_killstreak_ended(final_kill_count: int, _highest_multiplier: float, end_bonus_score: int) -> void:
	_killstreak_warning_active = false
	if end_bonus_score > 0:
		_add_run_score(end_bonus_score)
	if hud and hud.has_method("show_killstreak_end"):
		hud.show_killstreak_end(end_bonus_score, final_kill_count)

func _add_run_score(points: int) -> void:
	var delta: int = maxi(0, points)
	if delta <= 0:
		return
	session_score += delta
	session_xp = session_score
	if hud:
		hud.add_score(delta)

func _update_killstreak_hud() -> void:
	if not hud or not hud.has_method("set_killstreak_state"):
		return
	if _killstreak_manager == null or not is_instance_valid(_killstreak_manager):
		hud.call("set_killstreak_state", {"active": false})
		return
	hud.call("set_killstreak_state", {
		"active": bool(_killstreak_manager.call("is_active")),
		"kill_count": int(_killstreak_manager.call("get_kill_count")),
		"multiplier": float(_killstreak_manager.call("get_multiplier")),
		"time_ratio": float(_killstreak_manager.call("get_time_ratio")),
		"tier_label_key": str(_killstreak_manager.call("get_tier_label_key")),
		"warning": _killstreak_warning_active
	})

func _award_scaled_score(base_score: int, bonus_flat: int = 0) -> int:
	var awarded: int = maxi(0, base_score)
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		awarded = int(_killstreak_manager.call("compute_score", awarded))
	awarded += maxi(0, bonus_flat)
	_add_run_score(awarded)
	return awarded

func _is_enemy_elite(enemy: CharacterBody2D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if enemy.is_in_group("elite"):
		return true
	var enemy_id: String = str(enemy.get("enemy_id"))
	return enemy_id.findn("elite") >= 0

func _pick_bonus_crystal_type() -> Dictionary:
	var types_v: Variant = _bonus_crystals_cfg.get("types", [])
	if not (types_v is Array):
		return {}
	var types: Array = types_v as Array
	if types.is_empty():
		return {}
	var total_weight: float = 0.0
	for entry in types:
		if entry is Dictionary:
			total_weight += maxf(0.0, float((entry as Dictionary).get("weight", 0.0)))
	if total_weight <= 0.0:
		return {}
	var roll: float = randf() * total_weight
	var acc: float = 0.0
	for entry in types:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		acc += maxf(0.0, float(d.get("weight", 0.0)))
		if roll <= acc:
			return d.duplicate(true)
	var last_variant: Variant = types[types.size() - 1]
	return (last_variant as Dictionary).duplicate(true) if (last_variant is Dictionary) else {}

func _try_spawn_bonus_crystal(at_pos: Vector2, is_boss: bool, is_elite: bool) -> void:
	if _bonus_crystals_cfg.is_empty() or not bool(_bonus_crystals_cfg.get("enabled", false)):
		return
	if is_boss and _killstreak_manager and is_instance_valid(_killstreak_manager):
		if not bool(_killstreak_manager.call("boss_can_drop_bonus_crystal")):
			return

	var drop_table: Dictionary = _bonus_crystals_cfg.get("drop_table", {}) if _bonus_crystals_cfg.get("drop_table") is Dictionary else {}
	var chance: float = float(drop_table.get("normal_enemy_drop_chance", 0.12))
	if is_elite:
		chance = float(drop_table.get("elite_enemy_drop_chance", chance))
	if is_boss:
		chance = float(drop_table.get("boss_drop_chance", chance))
	chance = clampf(chance, 0.0, 1.0)
	if randf() > chance:
		return

	_spawn_bonus_crystal_at(at_pos)

## Spawns a bonus crystal (chosen by weighted type) at a position, no chance roll.
func _spawn_bonus_crystal_at(at_pos: Vector2, extra: Dictionary = {}) -> void:
	if _bonus_crystals_cfg.is_empty() or not bool(_bonus_crystals_cfg.get("enabled", false)):
		return
	var crystal_type: Dictionary = _pick_bonus_crystal_type()
	if crystal_type.is_empty():
		return
	var crystal_node: Node = BONUS_CRYSTAL_SCENE.instantiate()
	if crystal_node == null:
		return
	var spawn_data: Dictionary = crystal_type.duplicate(true)
	spawn_data["despawn_time_sec"] = float(_bonus_crystals_cfg.get("despawn_time_sec", 8.0))
	spawn_data["pickup_radius"] = float(_bonus_crystals_cfg.get("pickup_radius", 28.0))
	spawn_data["magnet_speed"] = float(_bonus_crystals_cfg.get("magnet_speed", 420.0))
	spawn_data["size_px"] = float(_bonus_crystals_cfg.get("size_px", 28.0))
	spawn_data["fall_speed_px_sec"] = float(_bonus_crystals_cfg.get("fall_speed_px_sec", 420.0))
	var default_asset: String = str(_bonus_crystals_cfg.get("default_asset", ""))
	if str(spawn_data.get("asset", "")).strip_edges() == "" and default_asset != "":
		spawn_data["asset"] = default_asset
	# Per-call overrides (e.g. slice_rush forced magnet toward the locked ship).
	for extra_key in extra.keys():
		spawn_data[extra_key] = extra[extra_key]

	var crystal_area: Area2D = crystal_node as Area2D
	if crystal_area:
		crystal_area.global_position = at_pos + Vector2(0.0, float(_bonus_crystals_cfg.get("spawn_offset_y", 10.0)))
		game_layer.add_child(crystal_area)
		_active_bonus_crystals.append(crystal_area)
		if crystal_area.has_signal("collected"):
			crystal_area.collected.connect(_on_bonus_crystal_collected)
		crystal_area.tree_exiting.connect(func() -> void:
			_active_bonus_crystals.erase(crystal_area)
		)
		if crystal_area.has_method("setup"):
			crystal_area.call("setup", spawn_data, player)

## Boosted crystal reward for gate_runner waves (called by GateRunnerManager when
## a swarm drone is dodged). Uses the gate_runner config drop chance.
func spawn_gate_runner_crystal(at_pos: Vector2) -> void:
	if _bonus_crystals_cfg.is_empty() or not bool(_bonus_crystals_cfg.get("enabled", false)):
		return
	var gr_cfg: Dictionary = DataManager.get_gate_runner_config() if DataManager else {}
	var chance: float = clampf(float(gr_cfg.get("dodge_crystal_chance", 0.3)), 0.0, 1.0)
	if chance <= 0.0 or randf() > chance:
		return
	_spawn_bonus_crystal_at(at_pos)

## Guaranteed reward crystals raining from the top of the screen at random X
## (pong points, breakout wall cleared...).
func spawn_reward_crystals_from_top(count: int) -> void:
	if _bonus_crystals_cfg.is_empty() or not bool(_bonus_crystals_cfg.get("enabled", false)):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(maxi(0, count)):
		var x: float = randf_range(viewport_size.x * 0.1, viewport_size.x * 0.9)
		var y: float = -30.0 - randf_range(0.0, 80.0)
		_spawn_bonus_crystal_at(Vector2(x, y))

## Guaranteed single reward crystal at a specific position (breakout bricks...).
## `extra` merges per-call overrides into the crystal spawn data (optional).
func spawn_reward_crystal_at(at_pos: Vector2, extra: Dictionary = {}) -> void:
	if _bonus_crystals_cfg.is_empty() or not bool(_bonus_crystals_cfg.get("enabled", false)):
		return
	_spawn_bonus_crystal_at(at_pos, extra)

## Kept for compatibility: pong points delegate to the generic top rain.
func spawn_pong_reward_crystals(count: int) -> void:
	spawn_reward_crystals_from_top(count)

## Guaranteed equipment drop at a position (slice_rush cuts...). Bypasses the
## per-wave kill-drop cap on purpose: mechanic waves budget their own drops.
## quality_mult > 10 forbids common/uncommon rarities (LootGenerator weights).
## `extra_item_fields` merges into the item dict (e.g. auto_collect_delay_sec).
## `force_rarity` (optionnel) force la rareté à la GÉNÉRATION (suika_up :
## rareté tirée par le manager au-dessus d'un plancher "uncommon ou +").
func spawn_reward_equipment_at(at_pos: Vector2, quality_mult: float, extra_item_fields: Dictionary = {}, force_rarity: String = "") -> void:
	var item: LootItem = LootGenerator.generate_loot(current_level_index + 1, "", force_rarity, quality_mult)
	if item == null:
		return
	var item_data: Dictionary = item.to_dict()
	for key in extra_item_fields.keys():
		item_data[key] = extra_item_fields[key]
	var drop: Node = LOOT_DROP_SCENE.instantiate()
	if drop == null:
		return
	game_layer.add_child(drop)
	if drop.has_method("setup"):
		drop.call("setup", item_data, at_pos)

## Public score entry for the mechanic waves (lane_runner collectibles...):
## adds run score and shows the floating "+N" at the pickup position.
func add_wave_bonus_score(points: int, at_pos: Vector2) -> void:
	var delta: int = maxi(0, points)
	if delta <= 0:
		return
	_add_run_score(delta)
	VFXManager.spawn_floating_text(at_pos, "+%d" % delta, Color(1.0, 0.87, 0.45), hud_container)

func _on_bonus_crystal_collected(data: Dictionary) -> void:
	# Chaque cristal ramassé crédite aussi la MONNAIE (currency_per_pickup,
	# surchargeable par type via currency_value) — total affiché en fin de run.
	var currency: int = maxi(0, int(data.get("currency_value", _bonus_crystals_cfg.get("currency_per_pickup", 1))))
	if currency > 0 and ProfileManager:
		ProfileManager.add_crystals(currency)
		session_crystals_gained += currency
	var crystal_type: String = str(data.get("type", ""))
	if crystal_type == "score_crystal":
		var score_value: int = maxi(0, int(data.get("score_value", 0)))
		if score_value > 0:
			_add_run_score(score_value)
			VFXManager.spawn_floating_text(
				player.global_position if is_instance_valid(player) else Vector2.ZERO,
				"+%d" % score_value,
				Color(0.5, 0.9, 1.0),
				hud_container
			)
	elif crystal_type == "streak_time_crystal":
		var time_bonus: float = maxf(0.0, float(data.get("time_bonus_sec", 0.0)))
		if time_bonus > 0.0 and _killstreak_manager and is_instance_valid(_killstreak_manager):
			_killstreak_manager.call("add_time_bonus", time_bonus)

func _clear_bonus_crystals() -> void:
	for i in range(_active_bonus_crystals.size() - 1, -1, -1):
		var node: Node = _active_bonus_crystals[i]
		if node == null or not is_instance_valid(node):
			_active_bonus_crystals.remove_at(i)
			continue
		node.queue_free()
	_active_bonus_crystals.clear()

func _try_spawn_fire_pattern_drop(at_pos: Vector2) -> void:
	# No shooting during the mechanic waves: a fire-pattern drop would be useless.
	if _gate_runner_wave_active or _pong_wave_active or _breakout_wave_active \
		or _ball_launcher_wave_active \
		or _climb_wave_active or _absorb_wave_active or _lane_runner_wave_active \
		or _slice_rush_wave_active or _match3_wave_active or _gravity_hole_wave_active \
		or _star_drift_wave_active or _suika_up_wave_active or _snake_wave_active \
		or _survivor_wave_active:
		return
	if _fire_pattern_drops_cfg.is_empty() or not bool(_fire_pattern_drops_cfg.get("enabled", false)):
		return
	# Per-level drop cap (0 or negative means unlimited).
	var max_drops: int = int(_fire_pattern_drops_cfg.get("max_drops_per_level", 1))
	if max_drops > 0 and _fire_pattern_drop_count >= max_drops:
		return

	# Eligible patterns: unlocked-only when require_rank_one_unlocked is true.
	var require_rank_one: bool = bool(_fire_pattern_drops_cfg.get("require_rank_one_unlocked", true))
	var eligible: Array = SkillManager.get_eligible_fire_pattern_drops(require_rank_one)
	if eligible.is_empty():
		return

	var chance: float = clampf(float(_fire_pattern_drops_cfg.get("drop_chance", 0.05)), 0.0, 1.0)
	if randf() > chance:
		return

	var pattern_id: String = str(eligible[randi() % eligible.size()])
	var patterns_cfg: Dictionary = _fire_pattern_drops_cfg.get("patterns", {}) if _fire_pattern_drops_cfg.get("patterns") is Dictionary else {}
	var pattern_entry: Dictionary = patterns_cfg.get(pattern_id, {}) if patterns_cfg.get(pattern_id) is Dictionary else {}

	var drop_node: Node = FIRE_PATTERN_DROP_SCENE.instantiate()
	if drop_node == null:
		return
	var spawn_data: Dictionary = {
		"pattern_id": pattern_id,
		"asset": str(pattern_entry.get("asset", "")),
		"despawn_time_sec": float(_fire_pattern_drops_cfg.get("despawn_time_sec", 8.0)),
		"pickup_radius": float(_fire_pattern_drops_cfg.get("pickup_radius", 28.0)),
		"magnet_speed": float(_fire_pattern_drops_cfg.get("magnet_speed", 420.0)),
		"size_px": float(_fire_pattern_drops_cfg.get("size_px", 56.0)),
		"fall_speed_px_sec": float(_fire_pattern_drops_cfg.get("fall_speed_px_sec", 220.0))
	}

	var drop_area: Area2D = drop_node as Area2D
	if drop_area:
		drop_area.global_position = at_pos + Vector2(0.0, float(_fire_pattern_drops_cfg.get("spawn_offset_y", 10.0)))
		game_layer.add_child(drop_area)
		_active_fire_pattern_drops.append(drop_area)
		_fire_pattern_drop_count += 1
		if drop_area.has_signal("collected"):
			drop_area.collected.connect(_on_fire_pattern_drop_collected)
		drop_area.tree_exiting.connect(func() -> void:
			_active_fire_pattern_drops.erase(drop_area)
		)
		if drop_area.has_method("setup"):
			drop_area.call("setup", spawn_data, player)

func _on_fire_pattern_drop_collected(pattern_id: String) -> void:
	if pattern_id == "" or not is_instance_valid(player):
		return
	if player.has_method("set_active_fire_pattern"):
		player.call("set_active_fire_pattern", pattern_id)
	var label: String = LocaleManager.translate("skills.skill." + pattern_id + ".title")
	if label == "skills.skill." + pattern_id + ".title":
		label = pattern_id
	VFXManager.spawn_floating_text(
		player.global_position,
		"%s: %s" % [LocaleManager.translate("fire_drop_picked"), label],
		Color(1.0, 0.55, 0.35),
		hud_container
	)

func _clear_fire_pattern_drops() -> void:
	for i in range(_active_fire_pattern_drops.size() - 1, -1, -1):
		var node: Node = _active_fire_pattern_drops[i]
		if node == null or not is_instance_valid(node):
			_active_fire_pattern_drops.remove_at(i)
			continue
		node.queue_free()
	_active_fire_pattern_drops.clear()

func _clear_snake_managers() -> void:
	_snake_wave_active = false
	for i in range(_active_snake_managers.size() - 1, -1, -1):
		var node: Node = _active_snake_managers[i]
		if node == null or not is_instance_valid(node):
			_active_snake_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_snake_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_snake"):
		player.call("end_snake")

func _build_default_loot_drop_rules() -> Dictionary:
	return {
		"enabled": true,
		"allow_equipment": true,
		"allow_powerups": true,
		"global_chance_scale": 0.7,
		"equipment_chance_scale": 0.45,
		"powerup_chance_scale": 0.55,
		"max_shield_per_wave": 1,
		"max_rapid_fire_per_wave": 1,
		"max_equipment_per_wave": 1,
		"shield_weight": 1.0,
		"rapid_fire_weight": 1.0
	}

func _load_override_protocol_state() -> void:
	_active_override_protocol_ids.clear()
	_active_override_protocol_map.clear()
	_override_protocol_settings_map.clear()
	_override_ui_settings = DataManager.get_override_protocols_ui_settings()

	var selected_protocols_v: Variant = App.active_override_protocol_ids
	if selected_protocols_v is Array:
		for raw_id in (selected_protocols_v as Array):
			var protocol_id: String = str(raw_id).strip_edges()
			if protocol_id == "" or _active_override_protocol_map.has(protocol_id):
				continue
			_active_override_protocol_ids.append(protocol_id)
			_active_override_protocol_map[protocol_id] = true
			_override_protocol_settings_map[protocol_id] = DataManager.get_override_protocol_settings(protocol_id)

	_override_enemy_move_multiplier = 1.0
	_override_enemy_hp_multiplier = 1.0
	_override_enemy_projectile_speed_multiplier = 1.0
	_override_enemy_elite_replacement_chance = 0.0
	_override_player_heal_multiplier = 1.0
	_override_player_start_hp = -1
	_override_reward_multiplier = 1.0
	_override_crystal_multiplier = 1.0
	_override_crystal_reward_per_score = maxf(0.0, float(_override_ui_settings.get("crystal_reward_per_score", 0.0)))
	_override_crystal_reward_victory_only = bool(_override_ui_settings.get("crystal_reward_victory_only", true))
	_override_force_one_hp = false
	_override_enable_toxic_pools = false
	_override_enable_volatile_reactors = false
	_override_enable_boss_overdrive = false
	_override_emp_vignette_enabled = false
	_override_toxic_pool_spawn_interval_sec = maxf(0.1, float(_override_ui_settings.get("system_corruption_spawn_interval_sec", 6.0)))
	_override_toxic_pool_radius = maxf(12.0, float(_override_ui_settings.get("system_corruption_pool_radius", 82.0)))
	_override_toxic_pool_duration_sec = maxf(0.1, float(_override_ui_settings.get("system_corruption_pool_duration_sec", 4.5)))
	_override_toxic_pool_dps = maxf(0.1, float(_override_ui_settings.get("system_corruption_pool_dps", 16.0)))
	_override_toxic_pool_max_active = maxi(1, int(_override_ui_settings.get("system_corruption_max_active_pools", 3)))
	_override_toxic_pool_visual_data = {}
	_override_toxic_pool_behavior_data = {
		"affects_enemies": false,
		"affects_player": true,
		"apply_poison_to_enemies": false
	}
	_override_volatile_trigger_chance = clampf(float(_override_ui_settings.get("volatile_reactors_trigger_chance", 0.3)), 0.0, 1.0)
	_override_volatile_explosion_mode_chance = 0.5
	_override_volatile_explosion_radius = maxf(12.0, float(_override_ui_settings.get("volatile_reactors_explosion_radius", 92.0)))
	_override_volatile_explosion_damage = maxi(1, int(_override_ui_settings.get("volatile_reactors_explosion_damage", 14)))
	_override_volatile_projectile_speed = maxf(40.0, float(_override_ui_settings.get("volatile_reactors_projectile_speed", 290.0)))
	_override_volatile_projectile_damage = maxi(1, int(_override_ui_settings.get("volatile_reactors_projectile_damage", 12)))
	_override_volatile_projectile_count = 3
	_override_volatile_projectile_spread_rad = 0.35
	_override_volatile_explosion_asset = ""
	_override_volatile_explosion_asset_anim = ""
	_override_volatile_explosion_asset_anim_duration = 0.0
	_override_volatile_explosion_asset_anim_loop = false
	_override_volatile_explosion_size_multiplier = 0.45
	_override_volatile_explosion_lifetime = -1.0
	_override_volatile_explosion_fade_out_duration = 0.3
	_override_volatile_explosion_color = Color(1.0, 0.35, 0.1, 0.75)
	_override_boss_overdrive_fire_rate = maxf(0.0, float(_override_ui_settings.get("boss_overdrive_fire_rate", 0.05)))
	_override_emp_vignette_strength = clampf(float(_override_ui_settings.get("emp_vignette_strength", 0.72)), 0.0, 1.5)
	_override_emp_vignette_radius = clampf(float(_override_ui_settings.get("emp_vignette_radius", 0.58)), 0.0, 1.0)
	_override_emp_vignette_color = Color(0.0, 0.0, 0.0, 1.0)

	var active_count: int = _active_override_protocol_ids.size()
	_override_reward_multiplier = DataManager.get_override_reward_multiplier(active_count)
	_override_crystal_multiplier = DataManager.get_override_crystal_multiplier(active_count)

	if _has_override_protocol("overclocked_thrusters"):
		var thruster_cfg: Dictionary = _get_override_protocol_settings("overclocked_thrusters")
		_override_enemy_move_multiplier *= maxf(0.01, float(thruster_cfg.get("enemy_move_speed_multiplier", 1.4)))
	if _has_override_protocol("hyper_ballistics"):
		var ballistic_cfg: Dictionary = _get_override_protocol_settings("hyper_ballistics")
		_override_enemy_projectile_speed_multiplier *= maxf(0.01, float(ballistic_cfg.get("projectile_speed_multiplier", 1.5)))
	if _has_override_protocol("ablative_armor"):
		var armor_cfg: Dictionary = _get_override_protocol_settings("ablative_armor")
		_override_enemy_hp_multiplier *= maxf(0.01, float(armor_cfg.get("enemy_hp_multiplier", 1.3)))
	if _has_override_protocol("nanite_suppression"):
		var nanite_cfg: Dictionary = _get_override_protocol_settings("nanite_suppression")
		_override_player_heal_multiplier = clampf(float(nanite_cfg.get("heal_multiplier", _override_ui_settings.get("nanite_heal_multiplier", 0.5))), 0.0, 1.0)
		var disable_repairs: bool = bool(nanite_cfg.get("disable_repair_drops", true))
		if disable_repairs:
			_loot_drop_rules["max_shield_per_wave"] = 0
			_loot_drop_rules["shield_weight"] = 0.0
	if _has_override_protocol("system_corruption"):
		var corruption_cfg: Dictionary = _get_override_protocol_settings("system_corruption")
		_override_enable_toxic_pools = true
		_override_toxic_pool_spawn_interval_sec = maxf(0.1, float(corruption_cfg.get("spawn_interval_sec", _override_toxic_pool_spawn_interval_sec)))
		_override_toxic_pool_radius = maxf(12.0, float(corruption_cfg.get("pool_radius", _override_toxic_pool_radius)))
		_override_toxic_pool_duration_sec = maxf(0.1, float(corruption_cfg.get("pool_duration_sec", _override_toxic_pool_duration_sec)))
		_override_toxic_pool_dps = maxf(0.1, float(corruption_cfg.get("pool_dps", _override_toxic_pool_dps)))
		_override_toxic_pool_max_active = maxi(1, int(corruption_cfg.get("max_active_pools", _override_toxic_pool_max_active)))
		var pool_visual_v: Variant = corruption_cfg.get("pool_visual", {})
		if pool_visual_v is Dictionary:
			_override_toxic_pool_visual_data = _normalize_override_visual_settings(
				pool_visual_v as Dictionary,
				_override_toxic_pool_radius * 2.0
			)
		var pool_behavior_v: Variant = corruption_cfg.get("pool_behavior", {})
		if pool_behavior_v is Dictionary:
			var pool_behavior := pool_behavior_v as Dictionary
			_override_toxic_pool_behavior_data["affects_enemies"] = bool(
				pool_behavior.get("affects_enemies", _override_toxic_pool_behavior_data.get("affects_enemies", false))
			)
			_override_toxic_pool_behavior_data["affects_player"] = bool(
				pool_behavior.get("affects_player", _override_toxic_pool_behavior_data.get("affects_player", true))
			)
			_override_toxic_pool_behavior_data["apply_poison_to_enemies"] = bool(
				pool_behavior.get("apply_poison_to_enemies", _override_toxic_pool_behavior_data.get("apply_poison_to_enemies", false))
			)
		_override_toxic_pool_timer = _override_toxic_pool_spawn_interval_sec
	if _has_override_protocol("volatile_reactors"):
		_override_enable_volatile_reactors = true
		var volatile_cfg: Dictionary = _get_override_protocol_settings("volatile_reactors")
		_override_volatile_trigger_chance = clampf(float(volatile_cfg.get("trigger_chance", _override_volatile_trigger_chance)), 0.0, 1.0)
		_override_volatile_explosion_mode_chance = clampf(float(volatile_cfg.get("explosion_mode_chance", _override_volatile_explosion_mode_chance)), 0.0, 1.0)
		_override_volatile_explosion_radius = maxf(12.0, float(volatile_cfg.get("explosion_radius", _override_volatile_explosion_radius)))
		_override_volatile_explosion_damage = maxi(1, int(volatile_cfg.get("explosion_damage", _override_volatile_explosion_damage)))
		_override_volatile_projectile_speed = maxf(40.0, float(volatile_cfg.get("projectile_speed", _override_volatile_projectile_speed)))
		_override_volatile_projectile_damage = maxi(1, int(volatile_cfg.get("projectile_damage", _override_volatile_projectile_damage)))
		_override_volatile_projectile_count = maxi(1, int(volatile_cfg.get("projectile_count", _override_volatile_projectile_count)))
		_override_volatile_projectile_spread_rad = maxf(0.0, float(volatile_cfg.get("projectile_spread_rad", _override_volatile_projectile_spread_rad)))
		var explosion_visual_v: Variant = volatile_cfg.get("explosion_visual", {})
		if explosion_visual_v is Dictionary:
			var explosion_visual: Dictionary = _normalize_override_visual_settings(
				explosion_visual_v as Dictionary,
				_override_volatile_explosion_radius * 0.45
			)
			_override_volatile_explosion_asset = str(explosion_visual.get("asset", ""))
			_override_volatile_explosion_asset_anim = str(explosion_visual.get("asset_anim", ""))
			_override_volatile_explosion_asset_anim_duration = maxf(0.0, float(explosion_visual.get("asset_anim_duration", 0.0)))
			_override_volatile_explosion_asset_anim_loop = bool(explosion_visual.get("asset_anim_loop", false))
			_override_volatile_explosion_size_multiplier = maxf(0.1, float(explosion_visual.get("size_multiplier", _override_volatile_explosion_size_multiplier)))
			_override_volatile_explosion_lifetime = float(explosion_visual.get("lifetime", _override_volatile_explosion_lifetime))
			_override_volatile_explosion_fade_out_duration = maxf(0.05, float(explosion_visual.get("fade_out_duration", _override_volatile_explosion_fade_out_duration)))
			_override_volatile_explosion_color = Color.from_string(
				str(explosion_visual.get("color", "#ff5929bf")),
				_override_volatile_explosion_color
			)
	if _has_override_protocol("elite_vanguard"):
		var elite_cfg: Dictionary = _get_override_protocol_settings("elite_vanguard")
		var base_elite_chance: float = clampf(
			float(elite_cfg.get("elite_replacement_base_chance", _override_ui_settings.get("elite_base_replacement_chance", 0.08))),
			0.0,
			1.0
		)
		var replacement_mult: float = maxf(1.0, float(elite_cfg.get("replacement_multiplier", 3.0)))
		_override_enemy_elite_replacement_chance = clampf(base_elite_chance * replacement_mult, 0.0, 1.0)
	if _has_override_protocol("emp_interference"):
		_override_emp_vignette_enabled = true
		var emp_cfg: Dictionary = _get_override_protocol_settings("emp_interference")
		_override_emp_vignette_strength = clampf(float(emp_cfg.get("strength", _override_emp_vignette_strength)), 0.0, 1.5)
		_override_emp_vignette_radius = clampf(float(emp_cfg.get("radius", _override_emp_vignette_radius)), 0.0, 1.0)
		_override_emp_vignette_color = Color.from_string(str(emp_cfg.get("color", "#000000ff")), _override_emp_vignette_color)
	if _has_override_protocol("boss_overdrive"):
		_override_enable_boss_overdrive = true
		var overdrive_cfg: Dictionary = _get_override_protocol_settings("boss_overdrive")
		_override_boss_overdrive_fire_rate = maxf(0.0, float(overdrive_cfg.get("fire_rate", _override_boss_overdrive_fire_rate)))

	_apply_world_damage_multipliers_to_override_protocols()

	print(
		"[Game] Active override protocols: ",
		_active_override_protocol_ids,
		" | xp_x",
		_override_reward_multiplier,
		" | crystal_x",
		_override_crystal_multiplier
	)

func _has_override_protocol(protocol_id: String) -> bool:
	return _active_override_protocol_map.has(protocol_id.strip_edges())

func _get_override_protocol_settings(protocol_id: String) -> Dictionary:
	if _override_protocol_settings_map.has(protocol_id):
		var settings_v: Variant = _override_protocol_settings_map.get(protocol_id, {})
		if settings_v is Dictionary:
			return (settings_v as Dictionary).duplicate(true)

	var settings: Dictionary = DataManager.get_override_protocol_settings(protocol_id)
	_override_protocol_settings_map[protocol_id] = settings.duplicate(true)
	return settings

func _get_world_damage_multiplier() -> float:
	var level_bonus: float = current_level_index * 0.05
	return float(_world_multipliers.get("damage", 1.0)) + level_bonus

func _apply_world_damage_multipliers_to_override_protocols() -> void:
	var world_damage_mult: float = _get_world_damage_multiplier()
	if _override_enable_toxic_pools:
		_override_toxic_pool_dps = maxf(0.0, _override_toxic_pool_dps * world_damage_mult)
	if _override_enable_volatile_reactors:
		_override_volatile_explosion_damage = maxi(1, int(float(_override_volatile_explosion_damage) * world_damage_mult))
		_override_volatile_projectile_damage = maxi(1, int(float(_override_volatile_projectile_damage) * world_damage_mult))

func _resolve_override_resource_path(raw_path: String) -> String:
	var clean_path: String = raw_path.strip_edges()
	if clean_path.begins_with("shared:"):
		var shared_id := clean_path.trim_prefix("shared:")
		clean_path = DataManager.get_shared_asset_path(shared_id, "")
	return clean_path

func _normalize_override_visual_settings(raw_visual: Dictionary, default_size: float = 0.0) -> Dictionary:
	var normalized := raw_visual.duplicate(true)
	normalized["asset"] = _resolve_override_resource_path(str(raw_visual.get("asset", raw_visual.get("path", ""))))
	normalized["asset_anim"] = _resolve_override_resource_path(str(raw_visual.get("asset_anim", "")))
	normalized["asset_anim_duration"] = maxf(0.0, float(raw_visual.get("asset_anim_duration", raw_visual.get("anim_duration", 0.0))))
	normalized["asset_anim_loop"] = bool(raw_visual.get("asset_anim_loop", raw_visual.get("anim_loop", true)))
	if default_size > 0.0:
		normalized["size"] = maxf(1.0, float(raw_visual.get("size", default_size)))
	return normalized

func _preload_override_visual_resources() -> void:
	_override_strong_resource_cache.clear()
	if _active_override_protocol_ids.is_empty():
		return

	var preload_paths: Dictionary = {}
	for protocol_id_v in _active_override_protocol_ids:
		var protocol_id: String = str(protocol_id_v).strip_edges()
		if protocol_id == "":
			continue
		var settings: Dictionary = _get_override_protocol_settings(protocol_id)
		_collect_resource_paths_recursive(settings, preload_paths)

	for path_variant in preload_paths.keys():
		_cache_override_resource_path(str(path_variant))

func _cache_override_resource_path(path: String) -> void:
	var resolved_path: String = _resolve_override_resource_path(path)
	if resolved_path == "" or not ResourceLoader.exists(resolved_path):
		return
	if _override_strong_resource_cache.has(resolved_path):
		return
	var resource: Resource = ResourceLoader.load(resolved_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource == null:
		return
	if _override_strong_resource_cache.size() >= OVERRIDE_STRONG_RESOURCE_CACHE_MAX:
		_override_strong_resource_cache.clear()
	_override_strong_resource_cache[resolved_path] = resource

func _setup_background() -> void:
	# Nettoyer le placeholder existant
	if background:
		background.queue_free()
		background = null
	
	# Créer un conteneur pour les layers
	var bg_container := Node2D.new()
	bg_container.name = "BackgroundContainer"
	bg_container.z_index = -100 # Ensure behind walls and entities
	add_child(bg_container)
	move_child(bg_container, 0)
	
	# Récupérer les données du niveau
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	var level_data := DataManager.get_level_data(level_id)
	
	if level_data.is_empty():
		push_warning("[Game] No data found for level: " + level_id)
		return
	
	var bgs: Dictionary = level_data.get("backgrounds", {})
	var viewport_size := get_viewport_rect().size
	var game_cfg: Dictionary = DataManager.get_game_config()
	var gameplay_cfg: Dictionary = game_cfg.get("gameplay", {}) if game_cfg.get("gameplay") is Dictionary else {}
	var bg_scroll_cfg: Dictionary = gameplay_cfg.get("background_scroll", {}) if gameplay_cfg.get("background_scroll") is Dictionary else {}
	var far_speed: float = float(bg_scroll_cfg.get("far_speed", 10.0))
	var mid_speed: float = float(bg_scroll_cfg.get("mid_speed", 50.0))
	var near_speed: float = float(bg_scroll_cfg.get("near_speed", 125.0))
	var tile_height_viewport_multiplier: float = maxf(0.01, float(bg_scroll_cfg.get("tile_height_viewport_multiplier", 1.5)))
	
	print("[Game] Loading background for ", level_id)

	# 1. FAR LAYER (0.2x)
	var far_path: String = str(bgs.get("far_layer", ""))
	if far_path != "":
		_create_layer(bg_container, far_path, far_speed, viewport_size, false, 1.0, tile_height_viewport_multiplier)
	
	# 2. MID LAYER (1.0x, PNG Alpha, Random/Tiling)
	var mid_layers := _flatten_layer_entries(bgs.get("mid_layer", []), 1.0)
	for mid_entry in mid_layers:
		var mid_path: String = str(mid_entry.get("path", ""))
		var mid_opacity: float = float(mid_entry.get("opacity", 1.0))
		_create_layer(bg_container, mid_path, mid_speed, viewport_size, true, mid_opacity, tile_height_viewport_multiplier)
	
	# 3. NEAR LAYER (2.5x, PNG Alpha, Fast/Blur)
	var near_layers := _flatten_layer_entries(bgs.get("near_layer", []), 1.0)
	for near_entry in near_layers:
		var near_path: String = str(near_entry.get("path", ""))
		var near_opacity: float = float(near_entry.get("opacity", 1.0))
		_create_layer(bg_container, near_path, near_speed, viewport_size, true, near_opacity, tile_height_viewport_multiplier)

	# 4. OVERLAY — full rect color layer on top of backgrounds (improves ship visibility)
	# Taille basée sur le viewport RÉEL (runtime) pour couvrir tout l'écran sur mobile (design_size fixe laissait 5–8% en haut/bas).
	var overlay_cfg: Variant = bg_scroll_cfg.get("overlay", {})
	if overlay_cfg is Dictionary and not (overlay_cfg as Dictionary).is_empty():
		var overlay_dict: Dictionary = overlay_cfg as Dictionary
		var overlay_color: Color = Color.from_string(str(overlay_dict.get("color", "#000000")), Color.BLACK)
		overlay_color.a = clampf(float(overlay_dict.get("opacity", 0.5)), 0.0, 1.0)
		var overlay_rect := ColorRect.new()
		overlay_rect.name = "BackgroundOverlay"
		overlay_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var viewport_actual: Vector2 = get_viewport_rect().size
		var zoom_vec: Vector2 = camera.zoom
		var overlay_size: Vector2 = viewport_actual / zoom_vec
		var center: Vector2 = camera.get_screen_center_position()
		overlay_rect.position = center - overlay_size / 2.0
		overlay_rect.size = overlay_size
		overlay_rect.color = overlay_color
		overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_container.add_child(overlay_rect)
		overlay_rect.z_index = 100
		_overlay_rect = overlay_rect
		print("[Game] BackgroundOverlay at level load: viewport=", viewport_actual, " zoom=", zoom_vec, " overlay_size=", overlay_size, " center=", center)

func _create_layer(
	parent: Node,
	path: String,
	speed: float,
	viewport_size: Vector2,
	use_add_blend: bool,
	opacity: float = 1.0,
	tile_height_viewport_multiplier: float = 1.0
) -> void:
	if path == "": return
	
	# Preload resource to prevent "popping" during gameplay.
	# Supports Texture2D (.png, .jpg, AnimatedTexture .tres) and SpriteFrames (.tres).
	if not ResourceLoader.exists(path):
		push_warning("[Game] Background resource does not exist: " + path)
		return
		
	var layer_resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	
	if layer_resource:
		var layer: Node = SCROLLING_LAYER_SCRIPT.new()
		parent.add_child(layer)
		layer.call("setup", layer_resource, speed, viewport_size, use_add_blend, tile_height_viewport_multiplier)
		if layer is CanvasItem:
			(layer as CanvasItem).modulate.a = clampf(opacity, 0.0, 1.0)
	else:
		push_warning("[Game] Could not load background resource: " + path)

func _flatten_layer_entries(data: Variant, default_opacity: float = 1.0) -> Array:
	var result: Array = []
	if data is Array:
		for item in data:
			result.append_array(_flatten_layer_entries(item, default_opacity))
	elif data is String:
		var path := str(data)
		if path != "":
			result.append({
				"path": path,
				"opacity": clampf(default_opacity, 0.0, 1.0)
			})
	elif data is Dictionary:
		var entry := data as Dictionary
		var path: String = str(entry.get("asset", entry.get("path", "")))
		if path != "":
			var opacity: float = clampf(float(entry.get("opacity", default_opacity)), 0.0, 1.0)
			result.append({
				"path": path,
				"opacity": opacity
			})
	return result

# =============================================================================
# WAVE BACKGROUND OVERRIDE (temporary dimension swap, e.g. gravity_hole)
# =============================================================================

## Fades a temporary background above the level one. z = -90: above the base
## layers (-100) but below _overlay_rect (effective z ~0, which keeps tinting
## the wave background too) and below all gameplay. The base container keeps
## scrolling underneath — hiding it is forbidden (it owns _overlay_rect).
## Idempotent: same path re-tweens the alpha only; a new path rebuilds.
func begin_wave_background_override(bg_path: String, fade_sec: float, scroll_speed: float = 14.0) -> void:
	if bg_path == "" or not ResourceLoader.exists(bg_path):
		push_warning("[Game] wave background override missing asset: " + bg_path)
		return
	if _wave_bg_tween and _wave_bg_tween.is_valid():
		_wave_bg_tween.kill()
	_wave_bg_tween = null
	if _wave_bg_container != null and is_instance_valid(_wave_bg_container) and _wave_bg_path != bg_path:
		_wave_bg_container.queue_free()
		_wave_bg_container = null
	if _wave_bg_container == null or not is_instance_valid(_wave_bg_container):
		_wave_bg_container = Node2D.new()
		_wave_bg_container.name = "WaveBackgroundContainer"
		_wave_bg_container.z_index = -90
		add_child(_wave_bg_container)
		move_child(_wave_bg_container, 1) # right after BackgroundContainer
		var bg_scroll_cfg: Dictionary = {}
		var gameplay_v: Variant = DataManager.get_game_config().get("gameplay", {}) if DataManager else {}
		if gameplay_v is Dictionary:
			var scroll_v: Variant = (gameplay_v as Dictionary).get("background_scroll", {})
			if scroll_v is Dictionary:
				bg_scroll_cfg = scroll_v as Dictionary
		var tile_mult: float = maxf(0.01, float(bg_scroll_cfg.get("tile_height_viewport_multiplier", 1.5)))
		_create_layer(_wave_bg_container, bg_path, scroll_speed, _get_design_viewport_size(), false, 1.0, tile_mult)
		_wave_bg_container.modulate.a = 0.0
	_wave_bg_path = bg_path
	_wave_bg_active = true
	if fade_sec <= 0.0:
		_wave_bg_container.modulate.a = 1.0
		return
	_wave_bg_tween = create_tween()
	_wave_bg_tween.tween_property(_wave_bg_container, "modulate:a", 1.0, fade_sec)

## Fades the override out and frees it. Safe to call twice / while fading in.
func end_wave_background_override(fade_sec: float) -> void:
	if not _wave_bg_active:
		return
	_wave_bg_active = false
	_wave_bg_path = ""
	if _wave_bg_tween and _wave_bg_tween.is_valid():
		_wave_bg_tween.kill()
	_wave_bg_tween = null
	var container: Node2D = _wave_bg_container
	_wave_bg_container = null
	if container == null or not is_instance_valid(container):
		return
	if fade_sec <= 0.0:
		container.queue_free()
		return
	# Bound to the container (NOT _wave_bg_tween): a later begin() kills
	# _wave_bg_tween and must not be able to strand a half-faded container.
	var out_tween: Tween = container.create_tween()
	out_tween.tween_property(container, "modulate:a", 0.0, fade_sec)
	out_tween.tween_callback(container.queue_free)

func is_wave_background_override_active() -> bool:
	return _wave_bg_active

func _get_design_viewport_size() -> Vector2:
	var w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 720))
	var h: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 1280))
	if w <= 0 or h <= 0:
		return get_viewport_rect().size
	return Vector2(w, h)

func _process(delta: float) -> void:
	if _overlay_rect != null and is_instance_valid(_overlay_rect) and camera != null:
		var viewport_actual: Vector2 = get_viewport_rect().size
		var zoom_vec: Vector2 = camera.zoom
		var overlay_size: Vector2 = viewport_actual / zoom_vec
		var center: Vector2 = camera.get_screen_center_position()
		_overlay_rect.size = overlay_size
		_overlay_rect.position = center - overlay_size / 2.0
	# Le background se gère tout seul via ScrollingLayer._process
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		_killstreak_manager.call("update", delta)
		_update_killstreak_hud()
	_debug_log_frame_hitch(delta)
	_update_hud()
	_update_boss_debug_hud()
	_update_override_runtime_effects(delta)

# func _update_background(delta: float) -> void: ... DELETED

func _debug_log_frame_hitch(delta: float) -> void:
	if not DEBUG_PERF_HITCH_LOG or not _log_hitches_enabled:
		return

	var delta_ms: float = delta * 1000.0
	if delta_ms < DEBUG_PERF_HITCH_THRESHOLD_MS:
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_hitch_log_ms < DEBUG_PERF_HITCH_COOLDOWN_MS:
		return
	_last_hitch_log_ms = now_ms

	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var pending_spawns: int = -1
	if wave_manager and wave_manager.has_method("get_pending_spawn_count"):
		pending_spawns = int(wave_manager.call("get_pending_spawn_count"))

	var enemy_projectiles: int = -1
	if ProjectileManager and ProjectileManager.has_method("get_active_enemy_projectile_count"):
		enemy_projectiles = int(ProjectileManager.call("get_active_enemy_projectile_count"))

	var camera_offset: Vector2 = Vector2.ZERO
	if camera:
		camera_offset = camera.offset

	print(
		"[Perf] Hitch dt=", snappedf(delta_ms, 0.1), "ms",
		" enemies=", enemy_count,
		" pending_spawns=", pending_spawns,
		" enemy_projectiles=", enemy_projectiles,
		" cam_offset=", camera_offset
	)

func _update_override_runtime_effects(delta: float) -> void:
	if not _override_enable_toxic_pools:
		return
	_cleanup_override_toxic_pools()
	_override_toxic_pool_timer -= delta
	if _override_toxic_pool_timer > 0.0:
		return
	_override_toxic_pool_timer = _override_toxic_pool_spawn_interval_sec
	_spawn_override_toxic_pool()

func _cleanup_override_toxic_pools() -> void:
	for i in range(_override_toxic_pool_nodes.size() - 1, -1, -1):
		var pool_node_v: Variant = _override_toxic_pool_nodes[i]
		if pool_node_v == null or not is_instance_valid(pool_node_v):
			_override_toxic_pool_nodes.remove_at(i)

func _spawn_override_toxic_pool() -> void:
	if TOXIC_POOL_SCENE == null:
		return
	var max_active: int = maxi(1, _override_toxic_pool_max_active)
	if _override_toxic_pool_nodes.size() >= max_active:
		return

	var spawn_pos: Vector2
	if player != null and is_instance_valid(player):
		# system_corruption : spawn centré sur le joueur pour l'inciter à bouger
		spawn_pos = player.global_position
	else:
		var viewport_size := get_viewport_rect().size
		var margin: float = 80.0
		spawn_pos = Vector2(
			randf_range(margin, maxf(margin, viewport_size.x - margin)),
			randf_range(margin, maxf(margin, viewport_size.y - margin))
		)

	var pool := TOXIC_POOL_SCENE.instantiate()
	if not (pool is Area2D):
		return
	game_layer.add_child(pool)
	(pool as Area2D).global_position = spawn_pos
	if pool.has_method("setup"):
		var visual_payload: Dictionary = _override_toxic_pool_visual_data.duplicate(true)
		if not visual_payload.has("size"):
			visual_payload["size"] = _override_toxic_pool_radius * 2.0
		pool.call(
			"setup",
			_override_toxic_pool_radius,
			_override_toxic_pool_duration_sec,
			_override_toxic_pool_dps,
			visual_payload,
			_override_toxic_pool_behavior_data.duplicate(true)
		)
	_override_toxic_pool_nodes.append(pool)

func _setup_emp_vignette() -> void:
	if not _override_emp_vignette_enabled:
		return
	var ui_layer := get_node_or_null("UI") as CanvasLayer
	if ui_layer == null:
		return

	_override_vignette_rect = ColorRect.new()
	_override_vignette_rect.name = "OverrideVignette"
	_override_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_override_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_override_vignette_rect.color = Color.WHITE
	_override_vignette_rect.z_index = 20

	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float strength = 0.72;\nuniform float radius = 0.58;\nuniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);\nvoid fragment() {\n\tvec2 uv = UV * 2.0 - vec2(1.0);\n\tfloat dist = length(uv);\n\tfloat vignette = smoothstep(radius, 1.0, dist);\n\tfloat alpha = vignette * strength * vignette_color.a;\n\tCOLOR = vec4(vignette_color.rgb, alpha);\n}\n"
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("strength", _override_emp_vignette_strength)
	shader_material.set_shader_parameter("radius", _override_emp_vignette_radius)
	shader_material.set_shader_parameter("vignette_color", _override_emp_vignette_color)
	_override_vignette_rect.material = shader_material

	ui_layer.add_child(_override_vignette_rect)
	# Fade-in rapide au lieu d'affichage instantané
	_override_vignette_rect.modulate.a = 0.0
	var tween := _override_vignette_rect.create_tween()
	tween.tween_property(_override_vignette_rect, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# =============================================================================
# CAMERA
# =============================================================================

func _setup_camera() -> void:
	# Top-left anchor + position (0,0) so the visible area is exactly [0,0]..[viewport_width, viewport_height].
	# This matches background/scrolling coordinates and keeps the overlay full-screen.
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.position = Vector2.ZERO
	VFXManager.set_camera(camera)

# =============================================================================
# HUD
# =============================================================================

func _setup_hud() -> void:
	var hud_scene := load("res://scenes/GameHUD.tscn")
	hud = hud_scene.instantiate()
	hud_container.add_child(hud)
	
	# Connect pause signal
	hud.pause_requested.connect(_show_pause_menu)
	hud.next_boss_requested.connect(_skip_to_next_debug_boss)
	
	# Load and setup PauseMenu
	var pause_scene := load("res://scenes/PauseMenu.tscn")
	pause_menu = pause_scene.instantiate()
	hud_container.add_child(pause_menu)
	pause_menu.restart_requested.connect(_on_restart_requested)
	pause_menu.level_select_requested.connect(_on_level_select_requested)
	pause_menu.quit_requested.connect(_on_quit_requested)
	
	# Initialiser la barre de vie
	if player:
		hud.set_player_max_hp(player.max_hp)
	
	hud.special_requested.connect(func(): if player: player.use_special())
	hud.unique_requested.connect(func(): if player: player.use_unique())

func _update_hud() -> void:
	if hud:
		if is_instance_valid(player):
			hud.update_player_hp(player.current_hp, player.max_hp)
		else:
			# Player may be null because it was queue_free'd on death
			# We force 0 to ensure the HUD shows death state
			hud.update_player_hp(0, 100)

# =============================================================================
# PLAYER
# =============================================================================

func _spawn_player() -> void:
	var player_scene := load("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.input_provider = hud # Assigner le joystick provider
	
	# Initial Position (20% from bottom = 80% of height)
	var viewport_size := get_viewport_rect().size
	player.position = Vector2(viewport_size.x / 2, viewport_size.y * 0.8)
	
	game_layer.add_child(player)
	print("[Game] Player spawned")

	if player and player.has_method("set_healing_multiplier"):
		player.call("set_healing_multiplier", _override_player_heal_multiplier)
	if _override_force_one_hp and player:
		player.max_hp = 1
		player.current_hp = 1
	elif _override_player_start_hp > 0 and player:
		player.current_hp = clampi(_override_player_start_hp, 1, player.max_hp)
	
	if hud:
		hud.set_player_reference(player)
		hud.set_player_max_hp(player.max_hp)
	
	# Connecter les signaux
	player.tree_exiting.connect(_on_player_died)

func _on_player_died() -> void:
	if _end_session_started or _player_death_registered:
		return
	
	_player_death_registered = true
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		_killstreak_manager.call("on_player_died")
	print("[Game] Player died! Game Over.")
	
	# Empêche le boss d'être tué après la mort du joueur (ex: projectile déjà en vol).
	if is_instance_valid(active_boss):
		if active_boss.has_method("set_invincible"):
			active_boss.call("set_invincible", true)
	
	# Show Game Over Overlay
	var overlay_scene := load("res://scenes/ui/GameOverOverlay.tscn")
	var overlay: Control = overlay_scene.instantiate()
	if overlay.has_method("set_display_duration"):
		overlay.call("set_display_duration", _end_screen_delay_seconds)
	hud_container.add_child(overlay)
	
	# After animation, show session report (Loot/Inventory)
	overlay.animation_finished.connect(func():
		if is_instance_valid(overlay):
			overlay.queue_free()
		_show_end_session_screen(false, true)
	)
	
	# Ensure overlay is at the bottom for layering
	hud_container.move_child(overlay, 0)

# =============================================================================
# PROJECTILES
# =============================================================================

func _setup_projectile_manager() -> void:
	ProjectileManager.set_container(game_layer)
	if ProjectileManager.has_method("set_enemy_projectile_speed_multiplier"):
		ProjectileManager.call("set_enemy_projectile_speed_multiplier", _override_enemy_projectile_speed_multiplier)

func _setup_fluid_simulation() -> void:
	FluidManager.setup(game_layer)

# =============================================================================
# ENEMIES
# =============================================================================

# =============================================================================
# ENEMIES (WAVE SYSTEM)
# =============================================================================

var wave_manager: Node = null

func _start_enemy_spawner() -> void:
	if wave_manager and is_instance_valid(wave_manager):
		return
	# Instancier le WaveManager
	wave_manager = WAVE_MANAGER_SCRIPT.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	
	wave_manager.spawn_enemy.connect(_on_wave_enemy_spawn)
	wave_manager.spawn_obstacle.connect(_on_wave_obstacle_spawn)
	if wave_manager.has_signal("spawn_snake"):
		wave_manager.spawn_snake.connect(_on_wave_snake_spawn)
	if wave_manager.has_signal("spawn_gate_runner"):
		wave_manager.spawn_gate_runner.connect(_on_wave_gate_runner_spawn)
	if wave_manager.has_signal("spawn_pong"):
		wave_manager.spawn_pong.connect(_on_wave_pong_spawn)
	if wave_manager.has_signal("spawn_breakout"):
		wave_manager.spawn_breakout.connect(_on_wave_breakout_spawn)
	if wave_manager.has_signal("spawn_ball_launcher"):
		wave_manager.spawn_ball_launcher.connect(_on_wave_ball_launcher_spawn)
	if wave_manager.has_signal("spawn_vertical_climb"):
		wave_manager.spawn_vertical_climb.connect(_on_wave_vertical_climb_spawn)
	if wave_manager.has_signal("spawn_absorb"):
		wave_manager.spawn_absorb.connect(_on_wave_absorb_spawn)
	if wave_manager.has_signal("spawn_lane_runner"):
		wave_manager.spawn_lane_runner.connect(_on_wave_lane_runner_spawn)
	if wave_manager.has_signal("spawn_slice_rush"):
		wave_manager.spawn_slice_rush.connect(_on_wave_slice_rush_spawn)
	if wave_manager.has_signal("spawn_match3"):
		wave_manager.spawn_match3.connect(_on_wave_match3_spawn)
	if wave_manager.has_signal("spawn_gravity_hole"):
		wave_manager.spawn_gravity_hole.connect(_on_wave_gravity_hole_spawn)
	if wave_manager.has_signal("spawn_star_drift"):
		wave_manager.spawn_star_drift.connect(_on_wave_star_drift_spawn)
	if wave_manager.has_signal("spawn_suika_up"):
		wave_manager.spawn_suika_up.connect(_on_wave_suika_up_spawn)
		wave_manager.spawn_survivor.connect(_on_wave_survivor_spawn)
	if wave_manager.has_signal("spawn_asteroid_field"):
		wave_manager.spawn_asteroid_field.connect(_on_wave_asteroid_field_spawn)
	wave_manager.level_completed.connect(_on_level_completed)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.story_check_before_wave.connect(_on_story_check_before_wave)
	if wave_manager.has_method("set_performance_config"):
		wave_manager.call("set_performance_config", _performance_cfg)
	# Mode libre : à armer AVANT setup() pour que la première vague soit déjà
	# la vague régénérée du level 1 (et non le placeholder du niveau synthétique).
	if _free_mode_session:
		if wave_manager.has_method("set_free_mode"):
			wave_manager.call("set_free_mode", _free_mode_wave_type, DataManager.get_freemode_config())
		if wave_manager.has_signal("free_mode_level_changed"):
			wave_manager.free_mode_level_changed.connect(_on_free_mode_level_changed)

	# Démarrer le niveau actuel
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	_prime_runtime_enemy_spawn_costs(level_id)
	_prewarm_level_spawn_assets(level_id)
	if _warmup_runtime_support_enabled:
		_prewarm_runtime_support_assets()
	_configure_wave_counter(level_id)
	_reset_wave_powerup_drop_counters()
	wave_manager.setup(level_id, current_world_id)
	if wave_manager and wave_manager.has_method("set_override_elite_replacement_chance"):
		wave_manager.call("set_override_elite_replacement_chance", _override_enemy_elite_replacement_chance)
	_maybe_start_boss_sequence_immediately(level_id)

func _prime_runtime_enemy_spawn_costs(level_id: String) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var payloads: Array = _build_runtime_enemy_warmup_payloads(level_data)
	if payloads.is_empty():
		return

	var host := Node2D.new()
	host.name = "RuntimeEnemyWarmupHost"
	host.visible = false
	game_layer.add_child(host)

	var patterns_warmed: bool = false
	for payload_variant in payloads:
		if not (payload_variant is Dictionary):
			continue
		var payload: Dictionary = payload_variant as Dictionary
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.visible = false
		host.add_child(enemy)
		enemy.global_position = Vector2(360.0, -280.0)
		enemy.setup(payload)

		# Warm all movement patterns in a real in-scene Enemy instance.
		# This avoids first-use curve fitting/path bake hitch when wave starts.
		if not patterns_warmed:
			var all_patterns: Array = DataManager.get_all_move_patterns()
			for pattern_variant in all_patterns:
				if pattern_variant is Dictionary:
					enemy.call("setup_movement", pattern_variant as Dictionary)
			patterns_warmed = true

		enemy.queue_free()

	host.queue_free()

	if DEBUG_RUNTIME_ENEMY_PREWARM_LOG and _log_runtime_enemy_prewarm_enabled:
		var elapsed_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		print(
			"[Game] Runtime enemy warmup done in ",
			snappedf(elapsed_ms, 0.1),
			"ms payloads=",
			payloads.size()
		)

func _build_runtime_enemy_warmup_payloads(level_data: Dictionary) -> Array:
	var result: Array = []
	var seen: Dictionary = {}

	var world_skin_overrides: Dictionary = DataManager.get_world_skin_overrides(current_world_id)
	var enemy_overrides: Dictionary = {}
	var raw_enemy_overrides: Variant = world_skin_overrides.get("enemies", {})
	if raw_enemy_overrides is Dictionary:
		enemy_overrides = raw_enemy_overrides as Dictionary

	var waves_variant: Variant = level_data.get("waves", [])
	if not (waves_variant is Array):
		return result

	for wave_variant in (waves_variant as Array):
		if not (wave_variant is Dictionary):
			continue
		var wave: Dictionary = wave_variant as Dictionary
		if str(wave.get("type", "enemy")) == "obstacle":
			continue

		var enemy_id: String = str(wave.get("enemy_id", ""))
		if enemy_id == "":
			continue

		var enemy_skin: String = str(enemy_overrides.get(enemy_id, ""))
		if enemy_skin == "":
			enemy_skin = str(wave.get("enemy_skin", ""))

		var key: String = enemy_id + "|" + enemy_skin
		if seen.has(key):
			continue
		seen[key] = true

		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id).duplicate(true)
		if enemy_data.is_empty():
			continue
		_apply_runtime_enemy_skin_override(enemy_data, enemy_skin)
		result.append(enemy_data)

	return result

func _apply_runtime_enemy_skin_override(enemy_data: Dictionary, enemy_skin: String) -> void:
	if enemy_skin == "":
		return
	if not ResourceLoader.exists(enemy_skin):
		return

	var visual: Dictionary = {}
	var visual_variant: Variant = enemy_data.get("visual", {})
	if visual_variant is Dictionary:
		visual = (visual_variant as Dictionary).duplicate(true)

	var skin_res: Resource = ResourceLoader.load(enemy_skin, "", ResourceLoader.CACHE_MODE_REUSE)
	var ext: String = enemy_skin.get_extension().to_lower()
	var is_frames: bool = (skin_res is SpriteFrames) or ext == "tres" or ext == "res"
	if is_frames:
		visual["asset_anim"] = enemy_skin
		visual["asset"] = ""
	else:
		visual["asset"] = enemy_skin
		visual["asset_anim"] = ""

	enemy_data["visual"] = visual

func _prewarm_level_spawn_assets(level_id: String) -> void:
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var boss_id: String = str(level_data.get("boss_id", ""))
	if boss_id == "":
		return

	var boss_data: Dictionary = DataManager.get_boss(boss_id)
	if boss_data.is_empty():
		return

	var visual_variant: Variant = boss_data.get("visual", {})
	if visual_variant is Dictionary:
		var visual: Dictionary = visual_variant as Dictionary
		_warmup_resource_path(str(visual.get("asset", "")))
		_warmup_resource_path(str(visual.get("asset_anim", "")))
		_warmup_resource_path(str(visual.get("on_death_asset", "")))
		_warmup_resource_path(str(visual.get("on_death_asset_anim", "")))

	var boss_overrides: Variant = _world_skin_overrides.get("bosses", {})
	if boss_overrides is Dictionary:
		_warmup_resource_path(str((boss_overrides as Dictionary).get(boss_id, "")))

func _prewarm_runtime_support_assets() -> void:
	if not _warmup_runtime_support_enabled:
		return
	var runtime_paths: Dictionary = {}
	for path_variant in RUNTIME_WARMUP_PATHS:
		var path: String = str(path_variant)
		if path != "":
			runtime_paths[path] = true

	_collect_runtime_support_paths(runtime_paths)
	for path_variant in runtime_paths.keys():
		_warmup_resource_path(str(path_variant))
	if _warmup_runtime_nodes_enabled:
		_warmup_runtime_support_nodes(runtime_paths)
		_prewarm_runtime_pickup_nodes()
		_prewarm_runtime_explosion_nodes()

func _warmup_runtime_support_nodes(runtime_paths: Dictionary) -> void:
	if runtime_paths.is_empty():
		return

	var host := Node2D.new()
	host.name = "RuntimeSupportWarmupHost"
	host.visible = true
	game_layer.add_child(host)

	for path_variant in runtime_paths.keys():
		var path: String = str(path_variant)
		if not _is_runtime_warmup_path(path):
			continue
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		var instance: Node = null
		if resource is PackedScene:
			instance = (resource as PackedScene).instantiate()
		elif resource is Script:
			var script_resource: Script = resource as Script
			if script_resource != null and script_resource.can_instantiate():
				var created: Variant = script_resource.new()
				if created is Node:
					instance = created as Node
		if instance == null:
			continue

		instance.process_mode = Node.PROCESS_MODE_DISABLED
		if instance is CanvasItem:
			(instance as CanvasItem).visible = true
		if instance is Node2D:
			(instance as Node2D).global_position = Vector2(360.0, 360.0)
		host.add_child(instance)
		instance.queue_free()

	host.queue_free()

func _is_runtime_warmup_path(path: String) -> bool:
	if path == "":
		return false
	for prefix_variant in RUNTIME_WARMUP_PREFIXES:
		var prefix: String = str(prefix_variant)
		if path.begins_with(prefix):
			return true
	return false

func _collect_runtime_support_paths(target: Dictionary) -> void:
	_collect_current_level_wave_assets(target)
	_collect_resource_paths_recursive(DataManager.get_skills_config(), target)
	_collect_resource_paths_recursive(DataManager.get_game_config(), target)
	_collect_resource_paths_recursive(DataManager.get_game_config().get("gameplay", {}), target)
	_collect_resource_paths_recursive(DataManager.get_bonus_crystals_config(), target)
	_collect_resource_paths_recursive(DataManager.get_ships(), target)
	_collect_resource_paths_recursive(DataManager.get_all_player_missile_patterns(), target)
	_collect_resource_paths_recursive(DataManager.get_all_enemy_missile_patterns(), target)
	_collect_resource_paths_recursive(_world_skin_overrides, target)
	_collect_resource_paths_recursive(DataManager.get_override_protocols_config(), target)
	_collect_resource_paths_recursive(DataManager.get_all_obstacles(), target)

	if not _warmup_collect_external_json_enabled:
		return

	var modifiers_data: Variant = _load_json_file("res://data/enemy_modifiers.json")
	_collect_resource_paths_recursive(modifiers_data, target)
	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/missiles.json"), target)

	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/super_powers.json"), target)
	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/unique_powers.json"), target)
	_collect_resource_paths_recursive(_load_json_file("res://data/missiles/boss_powers.json"), target)

func _prewarm_runtime_pickup_nodes() -> void:
	var host := Node2D.new()
	host.name = "RuntimePickupWarmupHost"
	host.visible = true
	game_layer.add_child(host)

	var gameplay_cfg: Dictionary = DataManager.get_game_data().get("gameplay", {})
	var powerups_cfg: Dictionary = gameplay_cfg.get("power_ups", {})
	var loot_cfg: Dictionary = gameplay_cfg.get("loot", {})

	# Warm powerup drop visuals + loot highlight aura path.
	var shield_cfg: Dictionary = powerups_cfg.get("shield", {})
	var shield_drop: Dictionary = {
		"type": "powerup",
		"visual_asset": str(shield_cfg.get("asset", "")),
		"asset_anim_duration": float(shield_cfg.get("asset_anim_duration", shield_cfg.get("asset_duration", 0.0))),
		"asset_anim_loop": bool(shield_cfg.get("asset_anim_loop", shield_cfg.get("asset_loop", true))),
		"width": float(shield_cfg.get("width", 70.0)),
		"height": float(shield_cfg.get("height", 70.0))
	}
	_warmup_lootdrop_instance(host, shield_drop, Vector2(180.0, 280.0))

	# Warm generic equipment drop visuals + highlight aura path.
	var generic_drop: Dictionary = {
		"type": "equipment",
		"asset": str(loot_cfg.get("asset", "")),
		"asset_anim_duration": float(loot_cfg.get("asset_anim_duration", loot_cfg.get("asset_duration", 0.0))),
		"asset_anim_loop": bool(loot_cfg.get("asset_anim_loop", loot_cfg.get("asset_loop", true))),
		"width": float(loot_cfg.get("width", 48.0)),
		"height": float(loot_cfg.get("height", 48.0))
	}
	_warmup_lootdrop_instance(host, generic_drop, Vector2(360.0, 280.0))

	# Warm bonus crystal visual + shared highlight setup.
	var crystals_cfg: Dictionary = DataManager.get_bonus_crystals_config()
	var crystal_data: Dictionary = {}
	var crystal_types_v: Variant = crystals_cfg.get("types", [])
	if crystal_types_v is Array:
		for type_entry in (crystal_types_v as Array):
			if type_entry is Dictionary:
				crystal_data = (type_entry as Dictionary).duplicate(true)
				break
	crystal_data["despawn_time_sec"] = float(crystals_cfg.get("despawn_time_sec", 8.0))
	crystal_data["pickup_radius"] = float(crystals_cfg.get("pickup_radius", 28.0))
	crystal_data["magnet_speed"] = float(crystals_cfg.get("magnet_speed", 420.0))
	crystal_data["size_px"] = float(crystals_cfg.get("size_px", 28.0))
	crystal_data["fall_speed_px_sec"] = float(crystals_cfg.get("fall_speed_px_sec", 420.0))
	if str(crystal_data.get("asset", "")) == "":
		crystal_data["asset"] = str(crystals_cfg.get("default_asset", ""))
	_warmup_bonus_crystal_instance(host, crystal_data, Vector2(540.0, 280.0))

	host.queue_free()

func _warmup_lootdrop_instance(host: Node2D, item_data: Dictionary, spawn_pos: Vector2) -> void:
	if LOOT_DROP_SCENE == null:
		return
	if item_data.is_empty():
		return
	var node: Node = LOOT_DROP_SCENE.instantiate()
	if not (node is Area2D):
		return
	var drop: Area2D = node as Area2D
	host.add_child(drop)
	drop.process_mode = Node.PROCESS_MODE_DISABLED
	if drop.has_method("setup"):
		drop.call("setup", item_data, spawn_pos)
	drop.queue_free()

func _warmup_bonus_crystal_instance(host: Node2D, crystal_data: Dictionary, spawn_pos: Vector2) -> void:
	if BONUS_CRYSTAL_SCENE == null:
		return
	if crystal_data.is_empty():
		return
	var node: Node = BONUS_CRYSTAL_SCENE.instantiate()
	if not (node is Area2D):
		return
	var crystal: Area2D = node as Area2D
	host.add_child(crystal)
	crystal.process_mode = Node.PROCESS_MODE_DISABLED
	crystal.global_position = spawn_pos
	if crystal.has_method("setup"):
		crystal.call("setup", crystal_data, player)
	crystal.queue_free()

func _prewarm_runtime_explosion_nodes() -> void:
	var explosions_cfg: Dictionary = DataManager.get_explosions_config()
	if explosions_cfg.is_empty():
		return

	var host := Node2D.new()
	host.name = "RuntimeExplosionWarmupHost"
	host.visible = false
	game_layer.add_child(host)

	for key in ["player_missile_impact", "enemy_death", "boss_death"]:
		var cfg_v: Variant = explosions_cfg.get(key, {})
		if not (cfg_v is Dictionary):
			continue
		var cfg: Dictionary = cfg_v as Dictionary
		VFXManager.spawn_explosion(
			Vector2(0.0, 0.0),
			float(cfg.get("size", 24.0)),
			Color(str(cfg.get("color", "#FFFFFF"))),
			host,
			str(cfg.get("asset", "")),
			str(cfg.get("asset_anim", "")),
			0.01,
			maxf(0.05, float(cfg.get("fade_out_duration", 0.05))),
			maxf(0.0, float(cfg.get("asset_anim_duration", 0.1))),
			bool(cfg.get("asset_anim_loop", false)),
			maxf(0.0, float(cfg.get("fade_in_duration", 0.0))),
			maxf(0.01, float(cfg.get("scale_start", 1.0))),
			maxf(0.01, float(cfg.get("scale_middle", 1.0))),
			maxf(0.01, float(cfg.get("scale_end", 1.0))),
			clampf(float(cfg.get("scale_middle_ratio", 0.45)), 0.05, 0.95),
			float(cfg.get("width", -1.0)),
			float(cfg.get("height", -1.0))
		)

	host.queue_free()

func _collect_current_level_wave_assets(target: Dictionary) -> void:
	var level_id: String = current_world_id + "_lvl_" + str(current_level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var waves_variant: Variant = level_data.get("waves", [])
	if waves_variant is Array:
		for wave_variant in (waves_variant as Array):
			_collect_resource_paths_recursive(wave_variant, target)

func _load_json_file(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func _collect_resource_paths_recursive(value: Variant, target: Dictionary) -> void:
	if value is Dictionary:
		for nested in (value as Dictionary).values():
			_collect_resource_paths_recursive(nested, target)
		return
	if value is Array:
		for nested in (value as Array):
			_collect_resource_paths_recursive(nested, target)
		return
	if value is String:
		var path: String = str(value).strip_edges()
		if path.begins_with("res://"):
			target[path] = true
		elif path.begins_with("shared:"):
			var shared_id := path.trim_prefix("shared:")
			var shared_path: String = DataManager.get_shared_asset_path(shared_id, "")
			if shared_path.begins_with("res://"):
				target[shared_path] = true

func _warmup_resource_path(path: String) -> void:
	if path == "":
		return
	var was_cached: bool = ResourceLoader.has_cached(path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if DEBUG_LEVEL_WARMUP_LOG and _log_level_warmup_enabled:
		if loaded:
			print("[Game] Warmup ", ("reused " if was_cached else "loaded "), path)
		else:
			print("[Game] Warmup failed ", path)

func _configure_wave_counter(level_id: String) -> void:
	# Mode libre : pas de compteur "X / Y" (boucle infinie) — le label affiche
	# le "Niveau N" de difficulté à la place.
	if _free_mode_session:
		_wave_total_with_boss = 0
		if hud and hud.has_method("configure_wave_counter"):
			hud.call("configure_wave_counter", 0)
		# Pas de bouclier récoltable en mode libre : barre masquée pour la run.
		if hud and hud.has_method("set_shield_bar_hidden"):
			hud.call("set_shield_bar_hidden", true)
		# Aucun mini-jeu ne tire : les 2 boutons de powers sont inapplicables —
		# masqués pour TOUTE la run (le flag gagne sur les restaurations des
		# managers en fin de vague).
		if hud and hud.has_method("set_power_buttons_force_hidden"):
			hud.call("set_power_buttons_force_hidden", true)
		_update_free_mode_level_label(1)
		return
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	var waves_count: int = _get_level_wave_count(level_data)
	var boss_count: int = _extract_boss_sequence_ids(level_data).size()
	if boss_count <= 0 and str(level_data.get("boss_id", "")) != "":
		boss_count = 1
	_wave_total_with_boss = waves_count + boss_count

	if hud and hud.has_method("configure_wave_counter"):
		hud.call("configure_wave_counter", _wave_total_with_boss)

func _get_current_level_id() -> String:
	return current_world_id + "_lvl_" + str(current_level_index)

func _get_current_level_data() -> Dictionary:
	return DataManager.get_level_data(_get_current_level_id())

func _get_level_wave_count(level_data: Dictionary) -> int:
	var waves_variant: Variant = level_data.get("waves", [])
	if waves_variant is Array:
		return (waves_variant as Array).size()
	return 0

func _extract_boss_sequence_ids(level_data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var sequence_variant: Variant = level_data.get("boss_sequence", [])
	if sequence_variant is Array:
		for boss_id_variant in (sequence_variant as Array):
			var boss_id: String = str(boss_id_variant).strip_edges()
			if boss_id != "":
				result.append(boss_id)
	return result

func _maybe_start_boss_sequence_immediately(level_id: String) -> void:
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if _get_level_wave_count(level_data) > 0:
		return
	if _extract_boss_sequence_ids(level_data).is_empty():
		return
	if wave_manager:
		wave_manager.stop()
	call_deferred("_begin_boss_sequence", level_data)

func _begin_boss_sequence(level_data: Dictionary) -> void:
	_boss_sequence_ids = _extract_boss_sequence_ids(level_data)
	_boss_sequence_index = -1
	_boss_sequence_active = not _boss_sequence_ids.is_empty()
	_set_boss_debug_mode(_boss_sequence_active)
	if _boss_sequence_active:
		_spawn_next_boss_in_sequence()

func _spawn_next_boss_in_sequence() -> void:
	if _boss_sequence_ids.is_empty():
		return
	_boss_sequence_index += 1
	if _boss_sequence_index >= _boss_sequence_ids.size():
		_set_boss_debug_mode(false)
		await _play_end_story_if_needed()
		_show_end_session_screen(true)
		return
	_spawn_boss(_boss_sequence_ids[_boss_sequence_index])

func _set_boss_debug_mode(active: bool) -> void:
	if hud and hud.has_method("set_boss_debug_visible"):
		hud.call("set_boss_debug_visible", active)

func _update_boss_debug_hud() -> void:
	if not hud or not hud.has_method("update_boss_debug_info"):
		return
	if not _boss_sequence_active or not is_instance_valid(active_boss):
		return
	hud.call(
		"update_boss_debug_info",
		str(active_boss.boss_name),
		str(active_boss.boss_id),
		str(active_boss.special_power_id),
		str(active_boss.missile_id)
	)

func _clear_runtime_boss_effects() -> void:
	if ProjectileManager and ProjectileManager.has_method("clear_all_projectiles"):
		ProjectileManager.call("clear_all_projectiles")
	for hazard_node in get_tree().get_nodes_in_group("runtime_hazards"):
		if is_instance_valid(hazard_node):
			hazard_node.queue_free()
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy_node):
			enemy_node.queue_free()

func _skip_to_next_debug_boss() -> void:
	if not _boss_sequence_active or _end_session_started:
		return
	if is_instance_valid(active_boss):
		if active_boss.boss_died.is_connected(_on_boss_died):
			active_boss.boss_died.disconnect(_on_boss_died)
		if active_boss.health_changed.is_connected(_on_boss_health_changed):
			active_boss.health_changed.disconnect(_on_boss_health_changed)
		active_boss.queue_free()
	active_boss = null
	boss_spawned = false
	_clear_runtime_boss_effects()
	if _boss_sequence_index >= _boss_sequence_ids.size() - 1:
		_set_boss_debug_mode(false)
		_show_end_session_screen(true, true)
		return
	_spawn_next_boss_in_sequence()

func _on_wave_started(wave_index: int) -> void:
	_reset_wave_powerup_drop_counters()
	_clear_snake_managers()
	# Clearing gate runners also restores the ship (HP clamp + scale reset) when
	# leaving a gate_runner wave for the next one.
	_clear_gate_runners()
	# Same for pong/breakout/ball_launcher/climb/absorb/lane_runner/slice_rush:
	# restores the ship (shape + free X/Y).
	_clear_pong_managers()
	_clear_breakout_managers()
	_clear_ball_launcher_managers()
	_clear_climb_managers()
	_clear_absorb_managers()
	_clear_lane_runner_managers()
	_clear_slice_rush_managers()
	_clear_match3_managers()
	_clear_gravity_hole_managers()
	_clear_star_drift_managers()
	_clear_suika_up_managers()
	_clear_survivor_managers()
	var wave_type: String = _get_wave_type_at_index(wave_index)
	# Mode libre : le niveau synthétique ne porte qu'un placeholder — le type
	# réel du round vient du WaveManager (indispensable en fiesta, où le
	# mini-jeu change à chaque round : tir coupé + splash du bon type).
	if _free_mode_session and wave_manager and is_instance_valid(wave_manager) \
		and wave_manager.has_method("get_current_wave_type"):
		var live_type: String = str(wave_manager.call("get_current_wave_type"))
		if live_type != "":
			wave_type = live_type
	# Déblocage mode libre : tout type rencontré en mode Histoire est marqué
	# sur le profil (jamais pendant une run libre).
	if not _free_mode_session and ProfileManager and ProfileManager.has_method("mark_wave_type_encountered"):
		ProfileManager.mark_wave_type_encountered(wave_type)
	# Skin de vaisseau par type de vague (ships.json > visual.wave_visuals) :
	# appliqué AVANT le setup des mécaniques pour que les begin_* mesurent le
	# bon sprite. Fallback générique + anim de transition gérés côté Player.
	if is_instance_valid(player) and player.has_method("apply_wave_visual"):
		player.apply_wave_visual(wave_type)
	var disable_shooting: bool = wave_type == "snake" or wave_type == "gate_runner" \
		or wave_type == "pong" or wave_type == "breakout" or wave_type == "ball_launcher" \
		or wave_type == "vertical_climb" \
		or wave_type == "absorb" or wave_type == "lane_runner" or wave_type == "slice_rush" \
		or wave_type == "match3" or wave_type == "gravity_hole" or wave_type == "star_drift" \
		or wave_type == "suika_up" or wave_type == "survivor"
	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		# Disable shooting for the paddle/pilotage mechanics; re-enable otherwise.
		player.set_can_shoot(not disable_shooting)
	var current_wave: int = wave_index + 1
	# Mode libre : le splash n'est joué qu'à la toute première itération (les
	# boucles suivantes doivent être invisibles pour le joueur). Exception
	# FIESTA : le mini-jeu change à chaque round — le splash annonce le suivant.
	if not _free_mode_session or not _free_mode_splash_shown or _free_mode_wave_type == "fiesta":
		_free_mode_splash_shown = true
		_show_wave_start_splash(current_wave, wave_type)
	if hud and hud.has_method("update_wave_counter"):
		hud.call("update_wave_counter", current_wave)

func _get_wave_type_at_index(wave_index: int) -> String:
	var level_id := current_world_id + "_lvl_" + str(current_level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	var waves_v: Variant = level_data.get("waves", [])
	if not (waves_v is Array):
		return "enemy"
	var waves: Array = waves_v as Array
	if wave_index < 0 or wave_index >= waves.size():
		return "enemy"
	var wave_v: Variant = waves[wave_index]
	if not (wave_v is Dictionary):
		return "enemy"
	return str((wave_v as Dictionary).get("type", "enemy"))

func _ensure_wave_splash_label() -> void:
	if _wave_splash_label and is_instance_valid(_wave_splash_label):
		return
	_wave_splash_label = Label.new()
	_wave_splash_label.name = "WaveSplashLabel"
	_wave_splash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_splash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_splash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_splash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_splash_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave_splash_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wave_splash_label.position = Vector2.ZERO
	_wave_splash_label.modulate.a = 0.0
	hud_container.add_child(_wave_splash_label)

	_wave_splash_sub_label = Label.new()
	_wave_splash_sub_label.name = "WaveSplashSubLabel"
	_wave_splash_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_splash_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_splash_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_splash_sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_splash_sub_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave_splash_sub_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wave_splash_sub_label.position = Vector2.ZERO
	_wave_splash_sub_label.modulate.a = 0.0
	hud_container.add_child(_wave_splash_sub_label)

# Wave-type sub-title shown below the "Wave X" toast. Fallback texts are used
# when the "game_wave_<type>" locale key is missing; plain enemy waves
# (empty/unknown type) show no sub-title at all.
const WAVE_TYPE_SPLASH_FALLBACKS: Dictionary = {
	"snake": "Snake",
	"gate_runner": "GATE RUNNER",
	"pong": "PONG",
	"breakout": "Breakout",
	"ball_launcher": "Ball Launcher",
	"vertical_climb": "Engine Failure",
	"absorb": "Absorption",
	"lane_runner": "Lane Runner",
	"slice_rush": "Slice Rush",
	"match3": "Match 3",
	"gravity_hole": "Gravity Field",
	"star_drift": "Star Drift",
	"suika_up": "Suika Reactor",
	"obstacle": "Asteroid Field",
	"asteroid_split": "Splitting Asteroids",
	"survivor": "Survivor",
	"swarm": "Swarm",
	"tank": "Heavy Armor",
	"artillery": "Artillery Barrage"
}
const WAVE_TYPE_SPLASH_COLORS: Dictionary = {
	"snake": "#7FE58C",
	"gate_runner": "#3FBF6A",
	"pong": "#8FD3FF",
	"breakout": "#FFB56B",
	"ball_launcher": "#5BB8FF",
	"vertical_climb": "#FF8C42",
	"absorb": "#7BE0A3",
	"lane_runner": "#F2E45B",
	"slice_rush": "#FF6BD5",
	"match3": "#C77DFF",
	"gravity_hole": "#9A7BFF",
	"star_drift": "#9AF6FF",
	"suika_up": "#7FE8C8",
	"asteroid_split": "#C9A66B",
	"survivor": "#B4FF6B"
}
const WAVE_TYPE_SPLASH_DEFAULT_COLOR: String = "#FFD56B"

func _show_wave_start_splash(wave_number: int, wave_type: String = "") -> void:
	if not bool(_wave_splash_cfg.get("enabled", true)):
		return
	if wave_type == "gate_runner":
		_show_gate_runner_splash_asset()
	_ensure_wave_splash_label()
	if _wave_splash_label == null or not is_instance_valid(_wave_splash_label):
		return

	var template: String = LocaleManager.translate("game_wave_splash")
	if template == "" or template == "game_wave_splash":
		template = "Wave {current}"
	_wave_splash_label.text = template.replace("{current}", str(wave_number))
	_wave_splash_label.add_theme_font_size_override("font_size", maxi(12, int(_wave_splash_cfg.get("font_size", 92))))
	_wave_splash_label.add_theme_color_override("font_color", Color(str(_wave_splash_cfg.get("color", "#FFFFFF"))))
	# Scale around exact center of screen so the zoom never drifts.
	_wave_splash_label.pivot_offset = _wave_splash_label.size * 0.5

	var show_sub_label: bool = WAVE_TYPE_SPLASH_FALLBACKS.has(wave_type)
	if _wave_splash_sub_label and is_instance_valid(_wave_splash_sub_label):
		var sub_text: String = ""
		var sub_color: Color = Color(str(WAVE_TYPE_SPLASH_COLORS.get(wave_type, WAVE_TYPE_SPLASH_DEFAULT_COLOR)))
		if show_sub_label:
			var sub_key: String = "game_wave_" + wave_type
			sub_text = LocaleManager.translate(sub_key)
			if sub_text == "" or sub_text == sub_key:
				sub_text = str(WAVE_TYPE_SPLASH_FALLBACKS.get(wave_type, ""))
		_wave_splash_sub_label.visible = show_sub_label
		_wave_splash_sub_label.text = sub_text
		_wave_splash_sub_label.add_theme_font_size_override("font_size", maxi(10, int(_wave_splash_cfg.get("font_size", 92) * 0.42)))
		_wave_splash_sub_label.add_theme_color_override("font_color", sub_color)
		_wave_splash_sub_label.position = Vector2(
			0.0,
			float(_wave_splash_cfg.get("font_size", 92) * 0.52) + maxf(0.0, float(_wave_splash_cfg.get("warning_margin_top", 30.0)))
		)
		_wave_splash_sub_label.pivot_offset = _wave_splash_sub_label.size * 0.5

	_animate_wave_splash(show_sub_label)

## Anime les labels du splash (titre + sous-titre optionnel) — partagé entre
## le toast "Vague X" et les splashs custom des managers (show_center_splash).
func _animate_wave_splash(show_sub_label: bool) -> void:
	var start_scale: float = clampf(float(_wave_splash_cfg.get("zoom_start", 0.0)), 0.0, 4.0)
	var end_scale: float = clampf(float(_wave_splash_cfg.get("zoom_end", 1.0)), 0.1, 4.0)
	var total_duration: float = maxf(0.15, float(_wave_splash_cfg.get("animation_duration_sec", 0.65)))
	var warning_duration: float = maxf(total_duration, float(_wave_splash_cfg.get("warning_duration_sec", 1.4)))
	var first_leg: float = total_duration * 0.6
	var second_leg: float = total_duration - first_leg
	var warning_first_leg: float = warning_duration * 0.55
	var warning_second_leg: float = warning_duration - warning_first_leg
	var peak_scale: float = maxf(end_scale, end_scale * 1.15)

	if _wave_splash_tween and _wave_splash_tween.is_running():
		_wave_splash_tween.kill()
	if _wave_splash_warning_tween and _wave_splash_warning_tween.is_running():
		_wave_splash_warning_tween.kill()

	_wave_splash_label.scale = Vector2.ONE * start_scale
	_wave_splash_label.modulate.a = 1.0
	if _wave_splash_sub_label and is_instance_valid(_wave_splash_sub_label):
		_wave_splash_sub_label.scale = Vector2.ONE * start_scale
		_wave_splash_sub_label.modulate.a = 0.0
	_wave_splash_tween = create_tween()
	_wave_splash_tween.tween_property(_wave_splash_label, "scale", Vector2.ONE * peak_scale, first_leg).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wave_splash_tween.tween_property(_wave_splash_label, "scale", Vector2.ONE * end_scale, second_leg).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wave_splash_tween.parallel().tween_property(_wave_splash_label, "modulate:a", 0.0, total_duration + 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if show_sub_label and _wave_splash_sub_label and is_instance_valid(_wave_splash_sub_label):
		var warning_delay: float = maxf(0.0, float(_wave_splash_cfg.get("warning_delay_sec", 0.4)))
		_wave_splash_warning_tween = create_tween()
		_wave_splash_warning_tween.tween_interval(warning_delay)
		_wave_splash_warning_tween.tween_property(_wave_splash_sub_label, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_wave_splash_warning_tween.parallel().tween_property(_wave_splash_sub_label, "scale", Vector2.ONE * peak_scale, warning_first_leg).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_wave_splash_warning_tween.tween_property(_wave_splash_sub_label, "scale", Vector2.ONE * end_scale, warning_second_leg).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_wave_splash_warning_tween.parallel().tween_property(_wave_splash_sub_label, "modulate:a", 0.0, warning_duration + 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Splash central générique façon "Vague X" — appelé par les managers de vague
## (ex : tie-break du pong). sub_text vide = titre seul.
func show_center_splash(title_text: String, sub_text: String = "", sub_color_html: String = "") -> void:
	if not bool(_wave_splash_cfg.get("enabled", true)):
		return
	_ensure_wave_splash_label()
	if _wave_splash_label == null or not is_instance_valid(_wave_splash_label):
		return
	_wave_splash_label.text = title_text
	_wave_splash_label.add_theme_font_size_override("font_size", maxi(12, int(_wave_splash_cfg.get("font_size", 92))))
	_wave_splash_label.add_theme_color_override("font_color", Color(str(_wave_splash_cfg.get("color", "#FFFFFF"))))
	_wave_splash_label.pivot_offset = _wave_splash_label.size * 0.5
	var show_sub: bool = sub_text != ""
	if _wave_splash_sub_label and is_instance_valid(_wave_splash_sub_label):
		var sub_color: Color = Color.from_string(sub_color_html, Color(WAVE_TYPE_SPLASH_DEFAULT_COLOR))
		_wave_splash_sub_label.visible = show_sub
		_wave_splash_sub_label.text = sub_text
		_wave_splash_sub_label.add_theme_font_size_override("font_size", maxi(10, int(_wave_splash_cfg.get("font_size", 92) * 0.42)))
		_wave_splash_sub_label.add_theme_color_override("font_color", sub_color)
		_wave_splash_sub_label.position = Vector2(
			0.0,
			float(_wave_splash_cfg.get("font_size", 92) * 0.52) + maxf(0.0, float(_wave_splash_cfg.get("warning_margin_top", 30.0)))
		)
		_wave_splash_sub_label.pivot_offset = _wave_splash_sub_label.size * 0.5
	_animate_wave_splash(show_sub)

func _show_gate_runner_splash_asset() -> void:
	var gr_cfg: Dictionary = DataManager.get_gate_runner_config() if DataManager else {}
	var asset_path: String = str(gr_cfg.get("splash_asset_path", "")).strip_edges()
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return
	var res: Resource = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		return

	var holder := Control.new()
	holder.name = "GateRunnerSplashAsset"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_container.add_child(holder)

	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5

	var visual: Node2D = null
	if res is SpriteFrames:
		var anim := AnimatedSprite2D.new()
		VFXManager.play_sprite_frames(anim, res as SpriteFrames, &"default", true, 0.0)
		visual = anim
	elif res is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = res as Texture2D
		visual = sprite
	if visual == null:
		holder.queue_free()
		return
	visual.position = center
	holder.add_child(visual)

	holder.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(holder, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.1)
	tween.tween_property(holder, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		if is_instance_valid(holder):
			holder.queue_free()
	)

func _on_story_check_before_wave(wave_index: int) -> void:
	var wave_one_based: int = wave_index + 1
	var story := DataManager.get_story_for_trigger(current_world_id, current_level_index, wave_one_based)
	if story.is_empty():
		if wave_manager and wave_manager.has_method("continue_after_story"):
			wave_manager.continue_after_story()
		return
	var story_id: String = str(story.get("id", ""))
	if story_id == "" or ProfileManager.has_viewed_story(story_id):
		if wave_manager and wave_manager.has_method("continue_after_story"):
			wave_manager.continue_after_story()
		return
	get_tree().paused = true
	await StoryManager.play_story(story_id, true)
	ProfileManager.mark_story_viewed(story_id)
	get_tree().paused = false
	if wave_manager and wave_manager.has_method("continue_after_story"):
		wave_manager.continue_after_story()

func _play_end_story_if_needed() -> void:
	var story := DataManager.get_story_for_trigger(current_world_id, current_level_index, "end")
	if story.is_empty():
		return
	var story_id: String = str(story.get("id", ""))
	if story_id == "" or ProfileManager.has_viewed_story(story_id):
		return
	get_tree().paused = true
	await StoryManager.play_story(story_id, true)
	ProfileManager.mark_story_viewed(story_id)
	get_tree().paused = false

func _reset_wave_powerup_drop_counters() -> void:
	_wave_powerup_drop_counts["shield"] = 0
	_wave_powerup_drop_counts["fire_rate"] = 0
	_wave_equipment_drop_count = 0
	_fire_pattern_drop_count = 0

func get_loot_drop_rules() -> Dictionary:
	return _loot_drop_rules.duplicate(true)

func can_spawn_powerup_drop(effect: String) -> bool:
	# During the no-shoot mechanic waves, shield / rapid fire power-ups make
	# no sense and are suppressed.
	if _gate_runner_wave_active or _pong_wave_active or _breakout_wave_active \
		or _ball_launcher_wave_active \
		or _climb_wave_active or _absorb_wave_active or _lane_runner_wave_active \
		or _slice_rush_wave_active or _match3_wave_active or _gravity_hole_wave_active \
		or _star_drift_wave_active or _suika_up_wave_active or _snake_wave_active \
		or _survivor_wave_active:
		return false
	var normalized: String = effect.strip_edges().to_lower()
	if not bool(_loot_drop_rules.get("allow_powerups", true)):
		return false

	match normalized:
		"shield":
			return int(_wave_powerup_drop_counts.get("shield", 0)) < maxi(0, int(_loot_drop_rules.get("max_shield_per_wave", 1)))
		"fire_rate", "rapid_fire":
			return int(_wave_powerup_drop_counts.get("fire_rate", 0)) < maxi(0, int(_loot_drop_rules.get("max_rapid_fire_per_wave", 1)))
		_:
			return true

func try_reserve_powerup_drop(effect: String) -> bool:
	var normalized: String = effect.strip_edges().to_lower()
	if not can_spawn_powerup_drop(normalized):
		return false

	match normalized:
		"shield":
			_wave_powerup_drop_counts["shield"] = int(_wave_powerup_drop_counts.get("shield", 0)) + 1
		"fire_rate", "rapid_fire":
			_wave_powerup_drop_counts["fire_rate"] = int(_wave_powerup_drop_counts.get("fire_rate", 0)) + 1
		_:
			pass
	return true

func can_spawn_equipment_drop() -> bool:
	if not bool(_loot_drop_rules.get("allow_equipment", true)):
		return false
	return _wave_equipment_drop_count < maxi(0, int(_loot_drop_rules.get("max_equipment_per_wave", 1)))

func try_reserve_equipment_drop() -> bool:
	if not can_spawn_equipment_drop():
		return false
	_wave_equipment_drop_count += 1
	return true

func _on_wave_enemy_spawn(enemy_data: Dictionary, spawn_pos: Vector2) -> void:
	var t0_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t0_usec = Time.get_ticks_usec()

	# Instancier l'ennemi
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
	var t_instantiate_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_instantiate_usec = Time.get_ticks_usec()
	
	# Scaling basé sur les multipliers du world + progression dans le world
	var level_bonus: float = current_level_index * 0.05
	var hp_mult: float = float(_world_multipliers.get("hp", 1.0)) + level_bonus
	var dmg_mult: float = _get_world_damage_multiplier()
	var spd_mult: float = float(_world_multipliers.get("speed", 1.0))
	hp_mult *= _override_enemy_hp_multiplier
	spd_mult *= _override_enemy_move_multiplier
	
	game_layer.add_child(enemy)
	enemy.global_position = spawn_pos
	var t_added_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_added_usec = Time.get_ticks_usec()
	enemy.setup(enemy_data)
	var t_setup_usec: int = 0
	if DEBUG_SPAWN_PIPELINE_LOG:
		t_setup_usec = Time.get_ticks_usec()
	enemy.apply_stat_multipliers({"hp_mult": hp_mult, "damage_mult": dmg_mult, "speed_mult": spd_mult})
	
	# Connecter le signal de mort
	enemy.enemy_died.connect(_on_enemy_died)
	if wave_manager and wave_manager.has_method("track_enemy_node"):
		wave_manager.call("track_enemy_node", enemy)

	if DEBUG_SPAWN_PIPELINE_LOG:
		var t_end_usec: int = Time.get_ticks_usec()
		var total_ms: float = float(t_end_usec - t0_usec) / 1000.0
		if total_ms >= DEBUG_SPAWN_PIPELINE_THRESHOLD_MS:
			var instantiate_ms: float = float(t_instantiate_usec - t0_usec) / 1000.0
			var add_ms: float = float(t_added_usec - t_instantiate_usec) / 1000.0
			var setup_ms: float = float(t_setup_usec - t_added_usec) / 1000.0
			var stats_ms: float = float(t_end_usec - t_setup_usec) / 1000.0
			print(
				"[GameSpawn] total=", snappedf(total_ms, 0.1), "ms",
				" instantiate=", snappedf(instantiate_ms, 0.1), "ms",
				" add=", snappedf(add_ms, 0.1), "ms",
				" setup=", snappedf(setup_ms, 0.1), "ms",
				" stats+signals=", snappedf(stats_ms, 0.1), "ms",
				" enemy=", str(enemy_data.get("id", "?")),
				" pattern=", str(enemy_data.get("move_pattern_id", ""))
			)
	# print("[Game] Wave Spawn: ", enemy_data.get("name", "?"))

# =============================================================================
# OBSTACLES (WAVE SYSTEM)
# =============================================================================

const OBSTACLE_EXPLOSIVE_SCENE := preload("res://scenes/obstacles/ObstacleExplosive.tscn")
const OBSTACLE_PUSHER_SCENE := preload("res://scenes/obstacles/ObstaclePusher.tscn")

func _on_wave_obstacle_spawn(obstacle_data: Dictionary, positions: Array, speed: float) -> void:
	var obs_type: String = str(obstacle_data.get("type", "explosive"))
	var drift_dirs: Array = obstacle_data.get("_drift_directions_per_obstacle", [])
	
	for i in range(positions.size()):
		var pos: Variant = positions[i]
		if pos is Vector2:
			var obstacle: Node2D = null
			
			match obs_type:
				"pusher":
					obstacle = OBSTACLE_PUSHER_SCENE.instantiate()
				_:
					obstacle = OBSTACLE_EXPLOSIVE_SCENE.instantiate()
			
			# Injecter la direction de drift individuelle
			var per_obstacle_data: Dictionary = obstacle_data.duplicate()
			if i < drift_dirs.size() and str(drift_dirs[i]) != "":
				per_obstacle_data["_drift_direction"] = str(drift_dirs[i])
			
			# Randomiser les dimensions par obstacle
			_randomize_obstacle_dimensions(per_obstacle_data)
			# Choisir un sprite aléatoire dans l'array
			_pick_random_sprite(per_obstacle_data)
			
			obstacle.global_position = pos as Vector2
			game_layer.add_child(obstacle)
			obstacle.setup(per_obstacle_data, speed)
			if wave_manager and wave_manager.has_method("track_obstacle_node"):
				wave_manager.call("track_obstacle_node", obstacle)
			
			# Connecter le signal de destruction si destructible
			if obstacle.has_signal("obstacle_destroyed"):
				obstacle.obstacle_destroyed.connect(_on_obstacle_destroyed)

func _on_wave_snake_spawn(config: Dictionary) -> void:
	if SNAKE_SCENE == null:
		return
	var node: Node = SNAKE_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_snake_wave_active = true
	game_layer.add_child(manager)
	_active_snake_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_snake_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_snake_finished"):
				wave_manager.call("notify_snake_finished")
		)
	# Les astéroïdes [E] réutilisent les skins d'obstacles explosifs du monde.
	var payload: Dictionary = config.duplicate(true)
	var sn_obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if sn_obs_overrides_v is Dictionary:
		var sn_explosives_v: Variant = (sn_obs_overrides_v as Dictionary).get("explosives", [])
		if sn_explosives_v is Array and not (sn_explosives_v as Array).is_empty():
			payload["_obstacle_skins"] = (sn_explosives_v as Array).duplicate()
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _on_wave_gate_runner_spawn(config: Dictionary) -> void:
	if GATE_RUNNER_SCENE == null:
		return
	var node: Node = GATE_RUNNER_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_gate_runner_wave_active = true
	game_layer.add_child(manager)
	_active_gate_runners.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_gate_runners.erase(manager)
	)
	# End the wave as soon as the scripted content is over and no drone remains,
	# so there is no idle period before the next wave.
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_gate_runner_finished"):
				wave_manager.call("notify_gate_runner_finished")
		)
	# Inject the world-level enemy skin overrides so swarm drones use the
	# correct world skin instead of the default placeholder visual.
	var payload: Dictionary = config.duplicate(true)
	var enemy_skins_v: Variant = _world_skin_overrides.get("enemies", {})
	payload["_enemy_skins"] = (enemy_skins_v as Dictionary).duplicate(true) if enemy_skins_v is Dictionary else {}
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_gate_runners() -> void:
	_gate_runner_wave_active = false
	for i in range(_active_gate_runners.size() - 1, -1, -1):
		var node: Node = _active_gate_runners[i]
		if node == null or not is_instance_valid(node):
			_active_gate_runners.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_gate_runners.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_gate_runner"):
		player.call("end_gate_runner")
	if hud and hud.has_method("set_hp_bar_hidden"):
		hud.call("set_hp_bar_hidden", false)

func _on_wave_pong_spawn(config: Dictionary) -> void:
	if PONG_SCENE == null:
		return
	var node: Node = PONG_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_pong_wave_active = true
	game_layer.add_child(manager)
	_active_pong_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_pong_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_pong_finished"):
				wave_manager.call("notify_pong_finished")
		)
	# Inject the world-level enemy skin overrides so the enemy paddle uses the
	# correct world visual instead of the default one.
	var payload: Dictionary = config.duplicate(true)
	var enemy_skins_v: Variant = _world_skin_overrides.get("enemies", {})
	payload["_enemy_skins"] = (enemy_skins_v as Dictionary).duplicate(true) if enemy_skins_v is Dictionary else {}
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_pong_managers() -> void:
	_pong_wave_active = false
	for i in range(_active_pong_managers.size() - 1, -1, -1):
		var node: Node = _active_pong_managers[i]
		if node == null or not is_instance_valid(node):
			_active_pong_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_pong_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_pong"):
		player.call("end_pong")

func _on_wave_breakout_spawn(config: Dictionary) -> void:
	if BREAKOUT_SCENE == null:
		return
	var node: Node = BREAKOUT_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_breakout_wave_active = true
	game_layer.add_child(manager)
	_active_breakout_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_breakout_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_breakout_finished"):
				wave_manager.call("notify_breakout_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _clear_breakout_managers() -> void:
	_breakout_wave_active = false
	for i in range(_active_breakout_managers.size() - 1, -1, -1):
		var node: Node = _active_breakout_managers[i]
		if node == null or not is_instance_valid(node):
			_active_breakout_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_breakout_managers.clear()
	# Defensive restore: breakout reuses the pong paddle mode.
	if is_instance_valid(player) and player.has_method("end_pong"):
		player.call("end_pong")

func _on_wave_ball_launcher_spawn(config: Dictionary) -> void:
	if BALL_LAUNCHER_SCENE == null:
		return
	var node: Node = BALL_LAUNCHER_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_ball_launcher_wave_active = true
	game_layer.add_child(manager)
	_active_ball_launcher_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_ball_launcher_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_ball_launcher_finished"):
				wave_manager.call("notify_ball_launcher_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _clear_ball_launcher_managers() -> void:
	_ball_launcher_wave_active = false
	for i in range(_active_ball_launcher_managers.size() - 1, -1, -1):
		var node: Node = _active_ball_launcher_managers[i]
		if node == null or not is_instance_valid(node):
			_active_ball_launcher_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_ball_launcher_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_ball_launcher"):
		player.call("end_ball_launcher")
	if hud and is_instance_valid(hud):
		if hud.has_method("set_power_buttons_suppressed"):
			hud.call("set_power_buttons_suppressed", false)
		if hud.has_method("set_joystick_visual_enabled"):
			hud.call("set_joystick_visual_enabled", true)

func _on_wave_vertical_climb_spawn(config: Dictionary) -> void:
	if VERTICAL_CLIMB_SCENE == null:
		return
	var node: Node = VERTICAL_CLIMB_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_climb_wave_active = true
	game_layer.add_child(manager)
	_active_climb_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_climb_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_vertical_climb_finished"):
				wave_manager.call("notify_vertical_climb_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _clear_climb_managers() -> void:
	_climb_wave_active = false
	for i in range(_active_climb_managers.size() - 1, -1, -1):
		var node: Node = _active_climb_managers[i]
		if node == null or not is_instance_valid(node):
			_active_climb_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_climb_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_climb"):
		player.call("end_climb")

func _on_wave_absorb_spawn(config: Dictionary) -> void:
	if ABSORB_SCENE == null:
		return
	var node: Node = ABSORB_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_absorb_wave_active = true
	game_layer.add_child(manager)
	_active_absorb_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_absorb_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_absorb_finished"):
				wave_manager.call("notify_absorb_finished")
		)
	# Inject the world-level enemy skin overrides so prey ships use the
	# correct world visual.
	var payload: Dictionary = config.duplicate(true)
	var enemy_skins_v: Variant = _world_skin_overrides.get("enemies", {})
	payload["_enemy_skins"] = (enemy_skins_v as Dictionary).duplicate(true) if enemy_skins_v is Dictionary else {}
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_absorb_managers() -> void:
	_absorb_wave_active = false
	for i in range(_active_absorb_managers.size() - 1, -1, -1):
		var node: Node = _active_absorb_managers[i]
		if node == null or not is_instance_valid(node):
			_active_absorb_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_absorb_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_absorb"):
		player.call("end_absorb")

func _on_wave_lane_runner_spawn(config: Dictionary) -> void:
	if LANE_RUNNER_SCENE == null:
		return
	var node: Node = LANE_RUNNER_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_lane_runner_wave_active = true
	game_layer.add_child(manager)
	_active_lane_runner_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_lane_runner_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_lane_runner_finished"):
				wave_manager.call("notify_lane_runner_finished")
		)
	# Inject the world-level obstacle skins so the walls can use the world's
	# explosive obstacle visuals when the wave declares no wall_assets.
	var payload: Dictionary = config.duplicate(true)
	var obstacle_skins: Array = []
	var obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides_v is Dictionary:
		var explosives_v: Variant = (obs_overrides_v as Dictionary).get("explosives", [])
		if explosives_v is Array:
			obstacle_skins = (explosives_v as Array).duplicate()
	payload["_obstacle_skins"] = obstacle_skins
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_lane_runner_managers() -> void:
	_lane_runner_wave_active = false
	for i in range(_active_lane_runner_managers.size() - 1, -1, -1):
		var node: Node = _active_lane_runner_managers[i]
		if node == null or not is_instance_valid(node):
			_active_lane_runner_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_lane_runner_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_lane_runner"):
		player.call("end_lane_runner")

func _on_wave_slice_rush_spawn(config: Dictionary) -> void:
	if SLICE_RUSH_SCENE == null:
		return
	var node: Node = SLICE_RUSH_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_slice_rush_wave_active = true
	game_layer.add_child(manager)
	_active_slice_rush_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_slice_rush_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_slice_rush_finished"):
				wave_manager.call("notify_slice_rush_finished")
		)
	# Inject the world-level obstacle skins so sliceable objects can use the
	# world's explosive obstacle visuals when a type declares no assets.
	var payload: Dictionary = config.duplicate(true)
	var obstacle_skins: Array = []
	var obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides_v is Dictionary:
		var explosives_v: Variant = (obs_overrides_v as Dictionary).get("explosives", [])
		if explosives_v is Array:
			obstacle_skins = (explosives_v as Array).duplicate()
	payload["_obstacle_skins"] = obstacle_skins
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_slice_rush_managers() -> void:
	_slice_rush_wave_active = false
	for i in range(_active_slice_rush_managers.size() - 1, -1, -1):
		var node: Node = _active_slice_rush_managers[i]
		if node == null or not is_instance_valid(node):
			_active_slice_rush_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_slice_rush_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_slice_rush"):
		player.call("end_slice_rush")
	if hud and is_instance_valid(hud):
		if hud.has_method("set_power_buttons_suppressed"):
			hud.call("set_power_buttons_suppressed", false)
		if hud.has_method("set_joystick_visual_enabled"):
			hud.call("set_joystick_visual_enabled", true)

func _on_wave_match3_spawn(config: Dictionary) -> void:
	if MATCH3_SCENE == null:
		return
	var node: Node = MATCH3_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_match3_wave_active = true
	game_layer.add_child(manager)
	_active_match3_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_match3_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_match3_finished"):
				wave_manager.call("notify_match3_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _clear_match3_managers() -> void:
	_match3_wave_active = false
	for i in range(_active_match3_managers.size() - 1, -1, -1):
		var node: Node = _active_match3_managers[i]
		if node == null or not is_instance_valid(node):
			_active_match3_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_match3_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_match3"):
		player.call("end_match3")
	if hud and is_instance_valid(hud):
		if hud.has_method("set_power_buttons_suppressed"):
			hud.call("set_power_buttons_suppressed", false)
		if hud.has_method("set_joystick_visual_enabled"):
			hud.call("set_joystick_visual_enabled", true)

func _on_wave_gravity_hole_spawn(config: Dictionary) -> void:
	if GRAVITY_HOLE_SCENE == null:
		return
	var node: Node = GRAVITY_HOLE_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_gravity_hole_wave_active = true
	game_layer.add_child(manager)
	_active_gravity_hole_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_gravity_hole_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_gravity_hole_finished"):
				wave_manager.call("notify_gravity_hole_finished")
		)
	# Inject the world-level obstacle skins so props can use the world's
	# explosive obstacle visuals when a prop type declares no assets.
	var payload: Dictionary = config.duplicate(true)
	var obstacle_skins: Array = []
	var obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides_v is Dictionary:
		var explosives_v: Variant = (obs_overrides_v as Dictionary).get("explosives", [])
		if explosives_v is Array:
			obstacle_skins = (explosives_v as Array).duplicate()
	payload["_obstacle_skins"] = obstacle_skins
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_gravity_hole_managers() -> void:
	_gravity_hole_wave_active = false
	for i in range(_active_gravity_hole_managers.size() - 1, -1, -1):
		var node: Node = _active_gravity_hole_managers[i]
		if node == null or not is_instance_valid(node):
			_active_gravity_hole_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_gravity_hole_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_gravity_hole"):
		player.call("end_gravity_hole")
	end_wave_background_override(0.0)

func _on_wave_star_drift_spawn(config: Dictionary) -> void:
	if STAR_DRIFT_SCENE == null:
		return
	var node: Node = STAR_DRIFT_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_star_drift_wave_active = true
	game_layer.add_child(manager)
	_active_star_drift_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_star_drift_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_star_drift_finished"):
				wave_manager.call("notify_star_drift_finished")
		)
	# Inject the world-level obstacle skins so the meteors can use the world's
	# explosive obstacle visuals when a hazard type declares no assets.
	var payload: Dictionary = config.duplicate(true)
	var obstacle_skins: Array = []
	var obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides_v is Dictionary:
		var explosives_v: Variant = (obs_overrides_v as Dictionary).get("explosives", [])
		if explosives_v is Array:
			obstacle_skins = (explosives_v as Array).duplicate()
	payload["_obstacle_skins"] = obstacle_skins
	if manager.has_method("setup"):
		manager.call("setup", payload, player, hud)

func _clear_star_drift_managers() -> void:
	_star_drift_wave_active = false
	for i in range(_active_star_drift_managers.size() - 1, -1, -1):
		var node: Node = _active_star_drift_managers[i]
		if node == null or not is_instance_valid(node):
			_active_star_drift_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_star_drift_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_star_drift"):
		player.call("end_star_drift")

func _on_wave_suika_up_spawn(config: Dictionary) -> void:
	if SUIKA_UP_SCENE == null:
		return
	var node: Node = SUIKA_UP_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_suika_up_wave_active = true
	game_layer.add_child(manager)
	_active_suika_up_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_suika_up_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_suika_up_finished"):
				wave_manager.call("notify_suika_up_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _on_wave_survivor_spawn(config: Dictionary) -> void:
	if SURVIVOR_SCENE == null:
		return
	var node: Node = SURVIVOR_SCENE.instantiate()
	if not (node is Node2D):
		return
	var manager: Node2D = node as Node2D
	manager.z_as_relative = false
	manager.z_index = -5
	manager.add_to_group("runtime_hazards")
	_survivor_wave_active = true
	game_layer.add_child(manager)
	_active_survivor_managers.append(manager)
	manager.tree_exiting.connect(func() -> void:
		_active_survivor_managers.erase(manager)
	)
	if manager.has_signal("finished"):
		manager.finished.connect(func() -> void:
			if is_instance_valid(wave_manager) and wave_manager.has_method("notify_survivor_finished"):
				wave_manager.call("notify_survivor_finished")
		)
	if manager.has_method("setup"):
		manager.call("setup", config.duplicate(true), player, hud)

func _clear_survivor_managers() -> void:
	_survivor_wave_active = false
	for i in range(_active_survivor_managers.size() - 1, -1, -1):
		var node: Node = _active_survivor_managers[i]
		if node == null or not is_instance_valid(node):
			_active_survivor_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_survivor_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_survivor"):
		player.call("end_survivor")
	if hud and is_instance_valid(hud) and hud.has_method("set_survivor_xp_visible"):
		hud.call("set_survivor_xp_visible", false)

func _clear_suika_up_managers() -> void:
	_suika_up_wave_active = false
	for i in range(_active_suika_up_managers.size() - 1, -1, -1):
		var node: Node = _active_suika_up_managers[i]
		if node == null or not is_instance_valid(node):
			_active_suika_up_managers.remove_at(i)
			continue
		if node.has_method("finish_now"):
			node.call("finish_now")
		else:
			node.queue_free()
	_active_suika_up_managers.clear()
	# Defensive restore in case a manager was already gone.
	if is_instance_valid(player) and player.has_method("end_suika_up"):
		player.call("end_suika_up")
	if hud and is_instance_valid(hud):
		if hud.has_method("set_power_buttons_suppressed"):
			hud.call("set_power_buttons_suppressed", false)
		if hud.has_method("set_joystick_visual_enabled"):
			hud.call("set_joystick_visual_enabled", true)
		if hud.has_method("hide_boss_health"):
			hud.call("hide_boss_health")

func _randomize_obstacle_dimensions(data: Dictionary) -> void:
	var shape: String = str(data.get("shape", "rectangle"))
	if shape == "circle":
		var r_min: float = float(data.get("radius_min", data.get("radius", 20)))
		var r_max: float = float(data.get("radius_max", data.get("radius", 20)))
		data["radius"] = randf_range(r_min, r_max)
	else:
		var w_min: float = float(data.get("width_min", data.get("width", 200)))
		var w_max: float = float(data.get("width_max", data.get("width", 200)))
		var base_w: float = float(data.get("width", 200))
		var base_h: float = float(data.get("height", 30))
		var ratio: float = base_h / maxf(base_w, 1.0)
		var rand_w: float = randf_range(w_min, w_max)
		data["width"] = rand_w
		data["height"] = rand_w * ratio

func _pick_random_sprite(data: Dictionary) -> void:
	# Check world-level obstacle skin overrides first
	var obs_type: String = str(data.get("type", ""))
	var obs_overrides: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides is Dictionary:
		var obs_dict: Dictionary = obs_overrides as Dictionary
		# Explosive obstacles use dedicated "explosives" visuals when defined
		if obs_type == "explosive":
			var explosives_sprites: Variant = obs_dict.get("explosives", [])
			if explosives_sprites is Array:
				var arr: Array = explosives_sprites as Array
				if arr.size() > 0:
					data["sprite_path"] = str(arr[randi() % arr.size()])
					return
	# Fallback to default sprite_path from obstacles.json
	var sprite_paths: Variant = data.get("sprite_path", "")
	if sprite_paths is Array:
		var arr: Array = sprite_paths as Array
		if arr.size() > 0:
			data["sprite_path"] = str(arr[randi() % arr.size()])
		else:
			data["sprite_path"] = ""
	# Si c'est déjà un String, on le laisse tel quel (compatibilité)

func _on_obstacle_destroyed(obstacle: Node2D) -> void:
	if obstacle != null and is_instance_valid(obstacle) and obstacle.has_meta("asteroid_tier"):
		_on_asteroid_destroyed(obstacle)
		return
	# Score bonus pour destruction d'obstacles
	_add_run_score(5)

# =============================================================================
# ASTEROID SPLIT WAVE
# =============================================================================

## Spawns the whole asteroid field at once, staggered vertically above the
## screen: rocks enter progressively with zero per-frame scheduling cost, and
## the standard obstacle tracking ends the wave when everything is cleared.
func _on_wave_asteroid_field_spawn(config: Dictionary) -> void:
	_asteroid_field_cfg = DataManager.get_wave_type_config("asteroid_split") if DataManager else {}
	_asteroid_field_wave = config.duplicate(true)
	_asteroid_field_base_speed = maxf(20.0, float(config.get("speed", _asteroid_field_cfg.get("fall_speed_px_sec_default", 120.0))))
	var count: int = maxi(1, int(config.get("count", _asteroid_field_cfg.get("initial_count_default", 5))))
	var stagger: float = maxf(60.0, float(config.get("spawn_stagger_px", _asteroid_field_cfg.get("spawn_stagger_px_default", 240.0))))
	var viewport_size: Vector2 = get_viewport_rect().size
	for i in range(count):
		var x: float = randf_range(viewport_size.x * 0.12, viewport_size.x * 0.88)
		var y: float = -80.0 - float(i) * stagger - randf_range(0.0, stagger * 0.35)
		_spawn_asteroid(0, Vector2(x, y), _asteroid_field_base_speed, randf_range(-14.0, 14.0))

## Spawns one asteroid of the given tier through the standard destructible
## obstacle pipeline (projectile damage, wave-clear tracking, cached visuals).
func _spawn_asteroid(tier_idx: int, pos: Vector2, vertical_speed: float, drift_x: float) -> void:
	var tiers_v: Variant = _asteroid_field_cfg.get("tiers", [])
	if not (tiers_v is Array):
		return
	var tiers: Array = tiers_v as Array
	if tier_idx < 0 or tier_idx >= tiers.size() or not (tiers[tier_idx] is Dictionary):
		return
	var max_active: int = maxi(4, int(_asteroid_field_cfg.get("max_active_asteroids", 26)))
	if _active_asteroid_count >= max_active:
		return
	var tier: Dictionary = tiers[tier_idx] as Dictionary
	var hp_mult: float = maxf(0.1, float(_asteroid_field_wave.get("hp_multiplier", 1.0)))
	var radius: float = maxf(8.0, float(tier.get("size_px", 80.0)) * 0.5 * randf_range(0.88, 1.12))
	var data: Dictionary = {
		"id": "asteroid_split_t" + str(tier_idx),
		"type": "explosive",
		"shape": "circle",
		"radius": radius,
		"sprite_path": _pick_asteroid_sprite(),
		"damage": maxi(1, int(tier.get("damage", 20))),
		"is_destructible": true,
		"hp": maxi(1, int(ceil(float(tier.get("hp", 20)) * hp_mult))),
		"_drift_vector": [drift_x, 0.0]
	}
	var node: Node = OBSTACLE_EXPLOSIVE_SCENE.instantiate()
	if not (node is Node2D):
		return
	var asteroid: Node2D = node as Node2D
	asteroid.global_position = pos
	game_layer.add_child(asteroid)
	if asteroid.has_method("setup"):
		asteroid.call("setup", data, maxf(20.0, vertical_speed))
	asteroid.set_meta("asteroid_tier", tier_idx)
	_active_asteroid_count += 1
	asteroid.tree_exiting.connect(_on_asteroid_tree_exiting, CONNECT_ONE_SHOT)
	if wave_manager and wave_manager.has_method("track_obstacle_node"):
		wave_manager.call("track_obstacle_node", asteroid)
	if asteroid.has_signal("obstacle_destroyed"):
		asteroid.obstacle_destroyed.connect(_on_obstacle_destroyed)

func _on_asteroid_tree_exiting() -> void:
	_active_asteroid_count = maxi(0, _active_asteroid_count - 1)

## Asset priority: per-wave "assets" override > world obstacle explosives skin
## > wave-type default assets (wave_types.json) > obstacles.json asteroid.
func _pick_asteroid_sprite() -> String:
	var wave_assets_v: Variant = _asteroid_field_wave.get("assets", [])
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		var wave_arr: Array = wave_assets_v as Array
		return str(wave_arr[randi() % wave_arr.size()])
	var obs_overrides_v: Variant = _world_skin_overrides.get("obstacles", {})
	if obs_overrides_v is Dictionary:
		var explosives_v: Variant = (obs_overrides_v as Dictionary).get("explosives", [])
		if explosives_v is Array and not (explosives_v as Array).is_empty():
			var skin_arr: Array = explosives_v as Array
			return str(skin_arr[randi() % skin_arr.size()])
	var cfg_assets_v: Variant = _asteroid_field_cfg.get("assets", [])
	if cfg_assets_v is Array and not (cfg_assets_v as Array).is_empty():
		var cfg_arr: Array = cfg_assets_v as Array
		return str(cfg_arr[randi() % cfg_arr.size()])
	var fallback_obstacle: Dictionary = DataManager.get_obstacle("asteroid_medium") if DataManager else {}
	var fb_v: Variant = fallback_obstacle.get("sprite_path", "")
	if fb_v is Array and not (fb_v as Array).is_empty():
		return str((fb_v as Array)[0])
	return str(fb_v) if fb_v is String else ""

## Asteroid kill: award the tier score, then split into smaller/faster chunks
## on divergent cone trajectories; the final tier can drop a bonus crystal.
func _on_asteroid_destroyed(asteroid: Node2D) -> void:
	var tier_idx: int = int(asteroid.get_meta("asteroid_tier"))
	var tiers_v: Variant = _asteroid_field_cfg.get("tiers", [])
	var tiers: Array = (tiers_v as Array) if tiers_v is Array else []
	var tier: Dictionary = {}
	if tier_idx >= 0 and tier_idx < tiers.size() and tiers[tier_idx] is Dictionary:
		tier = tiers[tier_idx] as Dictionary
	_add_run_score(maxi(1, int(tier.get("score", 5))))
	var split_count: int = maxi(0, int(tier.get("split_count", 0)))
	var next_idx: int = tier_idx + 1
	if split_count > 0 and next_idx < tiers.size() and tiers[next_idx] is Dictionary:
		var next_tier: Dictionary = tiers[next_idx] as Dictionary
		var cone: float = deg_to_rad(clampf(float(_asteroid_field_cfg.get("split_cone_deg", 70.0)), 10.0, 160.0))
		var speed_jitter: float = clampf(float(_asteroid_field_cfg.get("child_speed_jitter", 0.15)), 0.0, 0.6)
		var child_base_speed: float = _asteroid_field_base_speed * maxf(0.1, float(next_tier.get("speed_multiplier", 1.0)))
		var origin: Vector2 = asteroid.global_position
		for i in range(split_count):
			# Children spread evenly across the cone (centered on straight down);
			# the speed splits into scroll (vertical) + free drift (horizontal).
			var t_norm: float = ((float(i) + 0.5) / float(split_count)) - 0.5
			var angle: float = t_norm * cone + randf_range(-0.08, 0.08)
			var child_speed: float = child_base_speed * (1.0 + randf_range(-speed_jitter, speed_jitter))
			var offset: Vector2 = Vector2(sin(angle), 0.0) * 14.0
			_spawn_asteroid(next_idx, origin + offset, child_speed * cos(angle), child_speed * sin(angle))
	elif randf() <= clampf(float(_asteroid_field_cfg.get("crystal_chance_final_tier", 0.25)), 0.0, 1.0):
		_spawn_bonus_crystal_at(asteroid.global_position)

func _on_level_completed() -> void:
	_clear_gate_runners()
	_clear_pong_managers()
	_clear_breakout_managers()
	_clear_ball_launcher_managers()
	_clear_climb_managers()
	_clear_absorb_managers()
	_clear_lane_runner_managers()
	_clear_slice_rush_managers()
	_clear_match3_managers()
	_clear_gravity_hole_managers()
	_clear_suika_up_managers()
	_clear_survivor_managers()
	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		# Ensure boss phase is never blocked by prior no-shoot wave gating.
		player.set_can_shoot(true)
	var level_data := _get_current_level_data()
	var boss_sequence: Array[String] = _extract_boss_sequence_ids(level_data)
	if not boss_sequence.is_empty():
		print("[Game] Level completed. Starting boss sequence: ", boss_sequence)
		_begin_boss_sequence(level_data)
		return

	var boss_id: String = str(level_data.get("boss_id", ""))
	
	if boss_id != "":
		print("[Game] Level Waves Completed! Spawning Boss: ", boss_id)
		_spawn_boss(boss_id)
	else:
		print("[Game] Level Waves Completed! No Boss defined, triggering victory.")
		await _play_end_story_if_needed()
		_show_end_session_screen(true)

func _on_enemy_died(enemy: CharacterBody2D) -> void:
	if _end_session_started or _player_death_registered:
		return
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		_killstreak_manager.call("on_enemy_killed", 1)
	_award_scaled_score(int(enemy.score))
	_try_spawn_bonus_crystal(enemy.global_position, false, _is_enemy_elite(enemy))
	_try_spawn_fire_pattern_drop(enemy.global_position)

	if _override_enable_volatile_reactors:
		_try_trigger_volatile_reactor(enemy)
	
	enemies_killed += 1
	
	# Note: Le boss spawn est maintenant géré par WaveManager -> _on_level_completed

func _try_trigger_volatile_reactor(enemy: CharacterBody2D) -> void:
	if not is_instance_valid(enemy):
		return
	if randf() > _override_volatile_trigger_chance:
		return

	var source_pos: Vector2 = enemy.global_position
	if randf() < _override_volatile_explosion_mode_chance:
		var explosion_radius: float = _override_volatile_explosion_radius
		var explosion_damage: int = _override_volatile_explosion_damage
		if player and is_instance_valid(player):
			if player.global_position.distance_to(source_pos) <= explosion_radius and player.has_method("take_damage"):
				player.call("take_damage", explosion_damage)
		VFXManager.spawn_explosion(
			source_pos,
			explosion_radius * _override_volatile_explosion_size_multiplier,
			_override_volatile_explosion_color,
			game_layer,
			_override_volatile_explosion_asset,
			_override_volatile_explosion_asset_anim,
			_override_volatile_explosion_lifetime,
			_override_volatile_explosion_fade_out_duration,
			_override_volatile_explosion_asset_anim_duration,
			_override_volatile_explosion_asset_anim_loop
		)
		return

	var projectile_speed: float = _override_volatile_projectile_speed
	var projectile_damage: int = _override_volatile_projectile_damage
	var base_direction := Vector2.DOWN
	if player and is_instance_valid(player):
		base_direction = (player.global_position - source_pos).normalized()
		if base_direction == Vector2.ZERO:
			base_direction = Vector2.DOWN
	var projectile_count: int = maxi(1, _override_volatile_projectile_count)
	var half_count: float = float(projectile_count - 1) * 0.5
	for i in range(projectile_count):
		var angle: float = 0.0
		if projectile_count > 1:
			var normalized_index: float = (float(i) - half_count) / maxf(half_count, 1.0)
			angle = normalized_index * _override_volatile_projectile_spread_rad
		ProjectileManager.spawn_enemy_projectile(
			source_pos,
			base_direction.rotated(angle),
			projectile_speed,
			projectile_damage,
			{}
		)

func _spawn_boss(boss_id: String) -> void:
	boss_spawned = true
	print("[Game] BOSS INCOMING: ", boss_id)
	if is_instance_valid(player) and player.has_method("set_can_shoot"):
		player.set_can_shoot(true)
	if hud and hud.has_method("update_wave_counter"):
		var boss_wave_index: int = _wave_total_with_boss
		if _boss_sequence_active and _boss_sequence_index >= 0:
			boss_wave_index = _get_level_wave_count(_get_current_level_data()) + _boss_sequence_index + 1
		hud.call("update_wave_counter", boss_wave_index)
	
	# Arrêter le spawn d'ennemis normaux
	_stop_all_timers()
	if wave_manager:
		wave_manager.stop()
	
	# Spawn le boss
	var boss_data := DataManager.get_boss(boss_id)
	if boss_data.is_empty():
		print("[Game] Boss data not found!")
		return
	
	var boss: CharacterBody2D = BOSS_SCENE.instantiate()
	
	var target_spawn_pos := _compute_boss_spawn_position(boss_data)
	var entry_spawn_pos := _compute_boss_entry_start_position(boss_data)
	
	game_layer.add_child(boss)
	boss.global_position = entry_spawn_pos
	
	# Apply world-level boss skin override. En mode boss_sequence (debug arena), chaque boss
	# utilise les overrides de son propre monde (forest -> world_1, magic -> world_9, etc.).
	var overrides_for_boss: Dictionary = _world_skin_overrides
	if _boss_sequence_active:
		var boss_world_id: String = _get_world_id_for_boss(boss_id)
		overrides_for_boss = DataManager.get_world_skin_overrides(boss_world_id)
	var boss_overrides: Variant = overrides_for_boss.get("bosses", {})
	if boss_overrides is Dictionary:
		var visual: Dictionary = boss_data.get("visual", {}).duplicate(true)
		var changed := false
		var b_dict := boss_overrides as Dictionary
		
		var boss_skin: String = str(b_dict.get(boss_id, ""))
		if boss_skin != "" and ResourceLoader.exists(boss_skin):
			var ext: String = boss_skin.get_extension().to_lower()
			if ext == "tres" or ext == "res":
				visual["asset_anim"] = boss_skin
				visual["asset"] = ""
			else:
				visual["asset"] = boss_skin
				visual["asset_anim"] = ""
			changed = true
		
		var dur_key := boss_id + "_animation_duration"
		var freq_key := boss_id + "_animation_frequency"
		if b_dict.has(dur_key):
			visual["asset_anim_duration"] = float(b_dict[dur_key])
			changed = true
		if b_dict.has(freq_key):
			visual["asset_anim_frequency"] = float(b_dict[freq_key])
			changed = true
			
		if changed:
			boss_data["visual"] = visual
	
	boss.setup(boss_data)

	# Ensure visuals are loaded immediately (off-screen), then play entrance motion.
	boss.set_process(false)
	if _boss_spawn_entry_duration_sec > 0.0:
		var entry_tween := create_tween()
		entry_tween.set_trans(Tween.TRANS_CUBIC)
		entry_tween.set_ease(Tween.EASE_OUT)
		entry_tween.tween_property(boss, "global_position", target_spawn_pos, _boss_spawn_entry_duration_sec)
		await entry_tween.finished
	else:
		boss.global_position = target_spawn_pos
	if boss.has_method("set_spawn_anchor_to_current_position"):
		boss.call("set_spawn_anchor_to_current_position")
	boss.set_process(true)
	
	# Appliquer les multipliers du world au boss
	var boss_hp_mult: float = float(_world_multipliers.get("hp", 1.0)) * _override_enemy_hp_multiplier
	if boss_hp_mult != 1.0:
		boss.max_hp = int(boss.max_hp * boss_hp_mult)
		boss.current_hp = boss.max_hp
	if boss.has_method("set_damage_multiplier"):
		boss.call("set_damage_multiplier", _get_world_damage_multiplier())
	if _override_enable_boss_overdrive and boss.has_method("set_overdrive_enabled"):
		boss.call(
			"set_overdrive_enabled",
			true,
			_override_boss_overdrive_fire_rate
		)
	
	active_boss = boss
	
	# Afficher la barre de vie du boss dans le HUD existant
	if hud:
		hud.show_boss_health(boss_data.get("name", "Boss"), boss.max_hp)
		
	# Connecter signaux
	boss.boss_died.connect(_on_boss_died)
	boss.health_changed.connect(_on_boss_health_changed)
	
	if bool(ProfileManager.get_setting("screenshake_enabled", true)):
		VFXManager.screen_shake(15, 0.8)

func _compute_boss_spawn_position(boss_data: Dictionary) -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var boss_size_raw: Variant = boss_data.get("size", {})
	var boss_h: float = 100.0
	if boss_size_raw is Dictionary:
		boss_h = maxf(1.0, float((boss_size_raw as Dictionary).get("height", 100.0)))
	var spawn_y: float = (boss_h * 0.5) + _boss_spawn_top_margin_px
	return Vector2(viewport_size.x * 0.5, spawn_y)

func _compute_boss_entry_start_position(boss_data: Dictionary) -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var boss_size_raw: Variant = boss_data.get("size", {})
	var boss_h: float = 100.0
	if boss_size_raw is Dictionary:
		boss_h = maxf(1.0, float((boss_size_raw as Dictionary).get("height", 100.0)))
	var start_y: float = -((boss_h * 0.5) + _boss_spawn_top_margin_px)
	return Vector2(viewport_size.x * 0.5, start_y)

## En mode boss_sequence (debug arena), retourne le world_id associé au préfixe du boss_id.
func _get_world_id_for_boss(boss_id: String) -> String:
	var id_lower := boss_id.to_lower()
	if id_lower.begins_with("boss_forest_"): return "world_1"
	if id_lower.begins_with("boss_atlantis_"): return "world_2"
	if id_lower.begins_with("boss_industrial_"): return "world_3"
	if id_lower.begins_with("boss_lava_"): return "world_4"
	if id_lower.begins_with("boss_mine_"): return "world_5"
	if id_lower.begins_with("boss_necro_"): return "world_6"
	if id_lower.begins_with("boss_titan_"): return "world_7"
	if id_lower.begins_with("boss_alien_"): return "world_8"
	if id_lower.begins_with("boss_magic_"): return "world_9"
	return current_world_id

func _on_boss_health_changed(new_hp: int, max_hp: int) -> void:
	if hud:
		hud.update_boss_health(new_hp, max_hp)

func _on_boss_died(boss: CharacterBody2D) -> void:
	if _player_death_registered:
		print("[Game] Boss died after player death; ignoring victory flow.")
		return
	
	if _end_session_started:
		return
	
	print("[Game] BOSS DEFEATED!")
	var boss_kill_value: int = 1
	var boss_bonus_flat: int = 0
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		boss_kill_value = int(_killstreak_manager.call("get_boss_kill_count_value"))
		boss_bonus_flat = int(_killstreak_manager.call("get_boss_kill_bonus_score_flat"))
		_killstreak_manager.call("on_enemy_killed", boss_kill_value)
	_award_scaled_score(int(boss.score), boss_bonus_flat)
	_try_spawn_bonus_crystal(boss.global_position, true, false)

	active_boss = null
	if _boss_sequence_active and _boss_sequence_index < _boss_sequence_ids.size() - 1:
		_clear_runtime_boss_effects()
		_spawn_next_boss_in_sequence()
		return

	_set_boss_debug_mode(false)

	# Rendre le joueur invincible pour éviter de mourir pendant le popup de loot
	if player:
		player.is_invincible = true
		if player.has_method("set_can_shoot"):
			player.set_can_shoot(false)

	await _play_end_story_if_needed()
	await _play_victory_player_exit_animation()
	_show_end_session_screen(true, true)

func _play_victory_player_exit_animation() -> void:
	if not is_instance_valid(player):
		return

	if player.has_method("set_can_shoot"):
		player.set_can_shoot(false)
	player.is_invincible = true
	player.set_process(false)

	# Short pause before dash to make the "charge then leave" feel.
	await get_tree().create_timer(0.18).timeout
	if not is_instance_valid(player):
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var start_pos: Vector2 = player.global_position
	var target_pos := Vector2(start_pos.x, -maxf(160.0, viewport_size.y * 0.30))
	var travel_distance: float = maxf(1.0, start_pos.distance_to(target_pos))
	var dash_duration: float = clampf(travel_distance / 2200.0, 0.22, 0.55)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(player, "global_position", target_pos, dash_duration)
	await tween.finished

func _show_end_session_screen(is_victory: bool = true, skip_delay: bool = false) -> void:
	if _end_session_started:
		return
	_end_session_started = true
	_clear_bonus_crystals()
	_clear_snake_managers()
	if _killstreak_manager and is_instance_valid(_killstreak_manager):
		_killstreak_manager.call("on_level_end")
	_set_boss_debug_mode(false)
	
	# Disable spawning/shooting immediately
	if player and player.has_method("set_can_shoot"):
		player.set_can_shoot(false)
	if wave_manager:
		wave_manager.stop()
	if FluidManager.is_active():
		FluidManager.cleanup()
		
	# 1. Feedback
	if hud:
		var txt = "VICTOIRE !" if is_victory else "DÉFAITE..."
		var color = Color.GREEN if is_victory else Color.RED
		VFXManager.spawn_floating_text(player.global_position if is_instance_valid(player) else Vector2(get_viewport_rect().size.x/2, get_viewport_rect().size.y/2), txt, color, hud_container)
	
	if not skip_delay and _end_screen_delay_seconds > 0.0:
		await get_tree().create_timer(_end_screen_delay_seconds).timeout
	
	# --- Skill Tree: Grant session XP ---
	var xp_before := ProfileManager.get_player_xp()
	var level_before := ProfileManager.get_player_level()
	var level_key: String = _get_current_level_id()
	var score_best_before: int = 0
	var score_best_after: int = 0
	var score_stars_after: int = 0
	var level_score_thresholds: Dictionary = {}
	var level_cfg: Dictionary = DataManager.get_level_data(level_key)
	if not level_cfg.is_empty():
		level_score_thresholds = {
			"score_1star": int(level_cfg.get("score_1star", 0)),
			"score_2stars": int(level_cfg.get("score_2stars", 0)),
			"score_3stars": int(level_cfg.get("score_3stars", 0))
		}
	if ProfileManager:
		if _free_mode_session:
			# Mode libre : le record du mode se valide TOUJOURS (mort comprise),
			# stocké par wave_type et non par niveau ; pas d'étoiles.
			score_best_before = int(ProfileManager.get_free_mode_best_score(_free_mode_wave_type))
			var free_save: Dictionary = ProfileManager.save_free_mode_score(_free_mode_wave_type, session_score)
			score_best_after = int(free_save.get("best_score", score_best_before))
			level_score_thresholds = {}
		else:
			if ProfileManager.has_method("get_level_best_score"):
				score_best_before = int(ProfileManager.call("get_level_best_score", current_world_id, level_key))
			if is_victory and ProfileManager.has_method("save_level_score") and session_score > 0:
				var save_result: Variant = ProfileManager.call("save_level_score", current_world_id, level_key, session_score)
				if save_result is Dictionary:
					score_best_after = int((save_result as Dictionary).get("best_score", score_best_before))
					score_stars_after = int((save_result as Dictionary).get("stars", 0))
			else:
				score_best_after = score_best_before
				if ProfileManager.has_method("get_level_stars"):
					score_stars_after = int(ProfileManager.call("get_level_stars", current_world_id, level_key))
	var xp_mult: float = _resolve_session_xp_multiplier()
	var xp_per_score: float = DataManager.get_xp_per_score_ratio()
	var world_xp_mult: float = DataManager.get_world_xp_multiplier(current_world_id)
	var effective_session_xp: int = int(round(float(session_score) * xp_per_score * world_xp_mult * xp_mult * _override_reward_multiplier))
	# Mode libre : la run se termine presque toujours par la mort — l'XP du
	# score est accordée quand même (c'est l'issue normale du mode).
	var grant_session_rewards: bool = is_victory or _free_mode_session
	if grant_session_rewards and session_score > 0:
		ProfileManager.gain_xp(effective_session_xp)
	var xp_after := ProfileManager.get_player_xp()
	var level_after := ProfileManager.get_player_level()
	var xp_gained := effective_session_xp if grant_session_rewards else 0
	var _levels_gained := level_after - level_before
	var crystals_gained: int = _compute_override_crystal_reward(is_victory)
	if crystals_gained > 0:
		ProfileManager.add_crystals(crystals_gained)
		session_crystals_gained += crystals_gained
		if hud:
			var reward_pos := player.global_position if is_instance_valid(player) else Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.65)
			VFXManager.spawn_floating_text(
				reward_pos,
				"+%s CR" % str(crystals_gained),
				Color(0.5, 1.0, 0.95, 1.0),
				hud_container
			)
	
	# 2. Main Reward (Boss Loot) - Only on Victory
	var item := {}
	if is_victory:
		_apply_victory_progress()

		# Use universal boss loot pipeline:
		# - rarity rates from data/loot_table.json
		# - boss unique pool from data/bosses.json -> loot_table
		var target_level: int = max(1, current_level_index + 1)
		
		var level_id := current_world_id + "_lvl_" + str(current_level_index)
		var level_data := DataManager.get_level_data(level_id)
		var boss_id: String = str(level_data.get("boss_id", ""))
		
		var generated_item: LootItem = LootGenerator.generate_boss_loot(target_level, boss_id)
		if generated_item:
			item = generated_item.to_dict()
		else:
			push_warning("[Game] Boss reward generation failed, result screen will show no item.")

		var utility_bonuses: Dictionary = SkillManager.get_utility_bonuses()
		var extra_loot_chance: float = clampf(float(utility_bonuses.get("boss_extra_loot_chance", 0.0)), 0.0, 1.0)
		if extra_loot_chance > 0.0 and randf() <= extra_loot_chance:
			var bonus_item: LootItem = LootGenerator.generate_boss_loot(target_level, boss_id)
			if bonus_item:
				var bonus_dict: Dictionary = bonus_item.to_dict()
				ProfileManager.add_item_to_inventory(bonus_dict)
				session_loot.append(bonus_dict)
				print("[Game] Bonus boss loot granted by Jackpot skill: ", bonus_dict.get("id", "unknown"))
	
	
	# 3. Setup and show Result Screen
	var nav_context: Dictionary = _resolve_end_screen_navigation(is_victory)
	_end_screen_context_action = str(nav_context.get("action", END_SCREEN_ACTION_LEVEL_SELECT))
	var secondary_label: String = str(nav_context.get("label", "Sélection niveau"))

	var loot_screen_scene := load("res://scenes/LootResultScreen.tscn")
	if loot_screen_scene:
		var loot_screen: CanvasLayer = loot_screen_scene.instantiate()
		hud_container.add_child(loot_screen)
		loot_screen.setup(item, session_loot, is_victory)
		if loot_screen.has_method("set_navigation_labels"):
			loot_screen.set_navigation_labels(secondary_label, "Menu")
		# Pass XP data for display
		if loot_screen.has_method("set_xp_data"):
			loot_screen.set_xp_data(xp_gained, xp_before, xp_after, level_before, level_after)
		if loot_screen.has_method("set_crystals_data"):
			loot_screen.set_crystals_data(session_crystals_gained)
		if (is_victory or _free_mode_session) and loot_screen.has_method("set_score_data"):
			loot_screen.set_score_data(session_score, score_best_before, score_best_after, score_stars_after, level_score_thresholds)
		loot_screen.finished.connect(_return_to_home)
		loot_screen.restart_requested.connect(_on_restart_requested)
		loot_screen.exit_requested.connect(_on_end_screen_context_requested)
		if loot_screen.has_signal("menu_requested"):
			loot_screen.menu_requested.connect(_return_to_home)
		if loot_screen.has_signal("skills_menu_requested"):
			loot_screen.skills_menu_requested.connect(_on_skills_menu_requested)

func _resolve_session_xp_multiplier() -> float:
	if is_instance_valid(player) and player.has_method("get_xp_gain_multiplier"):
		return maxf(1.0, float(player.call("get_xp_gain_multiplier")))

	var active_ship_id := ProfileManager.get_active_ship_id()
	if active_ship_id != "" and StatsCalculator and StatsCalculator.has_method("calculate_ship_stats"):
		var stats: Dictionary = StatsCalculator.calculate_ship_stats(active_ship_id)
		var bonus_pct: float = float(stats.get("xp_multiplier", 0.0))
		return maxf(1.0, 1.0 + (bonus_pct / 100.0))

	return 1.0

func _compute_override_crystal_reward(is_victory: bool) -> int:
	if _override_crystal_reward_per_score <= 0.0:
		return 0
	if _override_crystal_reward_victory_only and not is_victory:
		return 0
	if session_score <= 0:
		return 0
	var raw_reward: float = float(session_score) * _override_crystal_reward_per_score * _override_crystal_multiplier
	return maxi(0, int(round(raw_reward)))

func _apply_victory_progress() -> void:
	var levels_per_world: int = max(1, App.get_world_level_count(current_world_id))
	ProfileManager.complete_level(current_world_id, current_level_index, levels_per_world, _active_override_protocol_ids.size())

	var is_final_level_in_world: bool = current_level_index >= levels_per_world - 1
	if is_final_level_in_world and _has_next_world(current_world_id):
		ProfileManager.unlock_next_world_if_needed(current_world_id)

func _has_next_world(world_id: String) -> bool:
	var worlds: Array = App.get_worlds()
	for i in range(worlds.size()):
		var entry: Variant = worlds[i]
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == world_id:
			return (i + 1) < worlds.size()
	return false

func _resolve_end_screen_navigation(is_victory: bool) -> Dictionary:
	if _free_mode_session:
		return {
			"action": END_SCREEN_ACTION_FREE_MODE_SELECT,
			"label": LocaleManager.translate("free_mode_title")
		}
	if not is_victory:
		return {
			"action": END_SCREEN_ACTION_LEVEL_SELECT,
			"label": "Sélection niveau"
		}

	var level_count: int = max(1, App.get_world_level_count(current_world_id))
	var has_next_level: bool = (current_level_index + 1) < level_count
	if has_next_level:
		return {
			"action": END_SCREEN_ACTION_NEXT_LEVEL,
			"label": "Niveau suivant"
		}

	return {
		"action": END_SCREEN_ACTION_WORLD_SELECT,
		"label": "Sélection monde"
	}

func _on_end_screen_context_requested() -> void:
	match _end_screen_context_action:
		END_SCREEN_ACTION_NEXT_LEVEL:
			_on_next_level_requested()
		END_SCREEN_ACTION_WORLD_SELECT:
			_on_world_select_requested()
		END_SCREEN_ACTION_FREE_MODE_SELECT:
			_on_free_mode_select_requested()
		_:
			_on_level_select_requested()

func _on_free_mode_select_requested() -> void:
	App.play_menu_music()
	get_tree().paused = false
	App.free_mode_active = false
	App.free_mode_wave_type = ""
	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/FreeModeSelect.tscn")

func _return_to_home() -> void:
	App.play_menu_music()
	get_tree().paused = false
	
	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()
	
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/HomeScreen.tscn")

# =============================================================================
# PAUSE MENU
# =============================================================================

func _show_pause_menu() -> void:
	if pause_menu:
		pause_menu.show_menu()

func _on_restart_requested() -> void:
	print("[Game] Restart requested for Level: ", current_world_id, " | Index: ", current_level_index)
	_save_free_mode_score_on_exit()
	get_tree().paused = false
	
	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()
	
	# Recharger la scène de jeu avec les paramètres actuels
	# On passe par le SceneSwitcher s'il est disponible pour faire propre
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		# App.current_level_index est déjà set
		switcher.goto_screen("res://scenes/Game.tscn")
	else:
		# Fallback classique
		get_tree().reload_current_scene()

## Quitter en cours de run (pause) = fin de run valide en mode libre : le
## record est sauvé même sans mort — indispensable pour les modes sans vecteur
## de mort (ex. match3).
func _save_free_mode_score_on_exit() -> void:
	if not _free_mode_session or _end_session_started:
		return
	if session_score > 0:
		ProfileManager.save_free_mode_score(_free_mode_wave_type, session_score)

func _on_level_select_requested() -> void:
	if _free_mode_session:
		_save_free_mode_score_on_exit()
		_on_free_mode_select_requested()
		return
	App.play_menu_music()
	get_tree().paused = false

	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()
	
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/LevelSelect.tscn")

func _on_skills_menu_requested() -> void:
	App.play_menu_music()
	get_tree().paused = false
	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/SkillsMenu.tscn")

func _on_next_level_requested() -> void:
	get_tree().paused = false

	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()

	var world_level_count: int = max(1, App.get_world_level_count(current_world_id))
	var next_level_index: int = min(current_level_index + 1, world_level_count - 1)
	App.current_world_id = current_world_id
	App.current_level_index = next_level_index
	current_level_index = next_level_index

	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/Game.tscn")

func _on_world_select_requested() -> void:
	App.play_menu_music()
	get_tree().paused = false

	ProjectileManager.clear_all_projectiles()
	_clear_snake_managers()

	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_quit_requested() -> void:
	_save_free_mode_score_on_exit()
	_return_to_home()

func _stop_all_timers() -> void:
	for child in get_children():
		if child is Timer:
			child.stop()
