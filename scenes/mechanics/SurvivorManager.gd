extends Node2D
## SURVIVOR (Vampire Survivors / Brotato-like) — vagues perpétuelles d'ennemis
## convergents (vrais Enemy.gd en mode seek_player), gemmes d'XP à aimant,
## level-up en pause (3 gros choix verticaux : nouvelle arme / upgrade /
## passif), 6 armes automatiques data-driven, coffres (cristaux + item).
## Story : survie chronométrée (duration) ; Libre : continuous infini, la
## difficulté rampe sur _free_level_progress.
## Config : wave_types.json > survivor. Le déplacement du vaisseau réutilise
## l'inertie star_drift (Player.begin_survivor) + orientation vers la
## direction du doigt (set_survivor_facing).

signal finished

enum State { RUN, DONE }

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const LEVELUP_PANEL_SCRIPT := preload("res://scenes/ui/SurvivorLevelUpPanel.gd")

var _state: State = State.RUN
var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null
var _duration: float = 80.0
var _elapsed: float = 0.0
var _finished_emitted: bool = false
var _resolved_textures: Dictionary = {} # path -> Texture2D (cache fort local)
var _fx_add_material: CanvasItemMaterial = null

# --- Director de spawn ---
var _enemies: Array = [] # refs Enemy vivants
var _spawn_timer: float = 0.0
var _spawn_queue: int = 0 # spawns en attente (étalés par frame)
var _separation_timer: float = 0.0

# --- Facing ---
var _facing: float = 0.0

# --- Contact ---
var _contact_invuln: float = 0.0

# --- XP / gemmes ---
var _gems: Array = [] # { "node", "pos": Vector2, "xp": int, "ttl": float, "pulled": bool }
var _xp: int = 0
var _level: int = 1
var _pending_level_ups: int = 0

# --- Level-up / choix ---
var _panel: CanvasLayer = null
var _weapons: Array = [] # { "def": Dictionary, "level": int, "cd": float, ... état par behavior }
var _passive_stacks: Dictionary = {} # passive_id -> int

# --- Visuels d'armes ---
var _chain_arcs: Array = [] # { "line": Line2D, "time": float, "max": float }
var _tesla_ring: Line2D = null
var _tesla_tick: float = 0.0
var _orb_root: Node2D = null
var _orb_nodes: Array = []
var _orb_angle: float = 0.0
var _orb_hit_cd: Dictionary = {} # enemy instance_id -> msec dernier hit
var _nova_rings: Array = [] # { "line": Line2D, "time": float, "max": float, "radius": float }
var _laser_beams: Array = [] # Line2D
var _laser_angle: float = 0.0
var _laser_tick: float = 0.0

# --- Coffres ---
var _chests: Array = [] # { "node", "pos": Vector2, "ttl": float }
var _chest_timer: float = 0.0
var _chests_spawned: int = 0


func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config if config is Dictionary else {}
	_cfg = DataManager.get_wave_type_config("survivor") if DataManager else {}
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_duration = maxf(5.0, float(_config.get("duration", _get_conf("duration_sec_default", 80.0))))
	_spawn_timer = 0.6 # première pression rapide mais pas immédiate
	_chest_timer = maxf(1.0, float(_get_conf("chest_first_delay_sec", 18.0)))
	if _player and is_instance_valid(_player) and _player.has_method("begin_survivor"):
		_player.call("begin_survivor", _control_cfg())
	if _hud and is_instance_valid(_hud) and _hud.has_method("set_survivor_xp_visible"):
		_hud.call("set_survivor_xp_visible", true)
	_ensure_panel()
	# Arme(s) de départ.
	for weapon_v in _weapon_defs():
		if weapon_v is Dictionary and bool((weapon_v as Dictionary).get("starting", false)):
			_add_weapon(weapon_v as Dictionary)
	_push_xp_to_hud()

func _control_cfg() -> Dictionary:
	var speed_mult: float = 1.0 + _passive_total("move_speed_mult")
	return {
		"control_follow_gain": float(_get_conf("control_follow_gain", 7.0)),
		"control_max_speed_px_sec": float(_get_conf("control_max_speed_px_sec", 620.0)) * speed_mult,
		"control_inertia_response": float(_get_conf("control_inertia_response", 6.0)),
		"control_finger_offset_y": float(_get_conf("control_finger_offset_y", -110.0)),
		"control_deadzone_px": float(_get_conf("control_deadzone_px", 4.0))
	}

func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre continuous : merge des clés de rampe autorisées (jamais l'état
## XP/armes — la progression du joueur persiste entre les levels).
func update_free_mode_config(cfg: Dictionary) -> void:
	if not (cfg is Dictionary):
		return
	for key in ["spawn_interval_sec_start", "spawn_interval_sec_end", "enemies_per_spawn_start",
		"enemies_per_spawn_end", "max_active_enemies", "enemy_hp_mult_start", "enemy_hp_mult_end",
		"seek_speed_px_sec_start", "seek_speed_px_sec_end", "contact_damage_percent",
		"_free_level_progress"]:
		if cfg.has(key):
			_config[key] = cfg[key]

## Rampe de difficulté : progression du mode libre si dispo, sinon temporelle.
func _ramp_t() -> float:
	if _config.has("_free_level_progress"):
		return clampf(float(_config.get("_free_level_progress", 0.0)), 0.0, 1.0)
	return clampf(_elapsed / maxf(1.0, _duration), 0.0, 1.0)

func _ramp(key_start: String, key_end: String, fb_start: float, fb_end: float) -> float:
	return lerpf(float(_get_conf(key_start, fb_start)), float(_get_conf(key_end, fb_end)), _ramp_t())


func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	var dt: float = minf(delta, 0.1)
	_elapsed += dt
	_prune_enemies()
	_tick_spawning(dt)
	_tick_separation(dt)
	_tick_facing(dt)
	_tick_contact_damage(dt)
	_tick_gems(dt)
	_tick_chests(dt)
	_tick_weapons(dt)
	_tick_weapon_visuals(dt)
	# Fin story au timer (en libre la durée est quasi infinie).
	if _elapsed >= _duration:
		_finish()
		return
	# Level-up en attente : ouvre le panel (jamais pendant qu'il est déjà ouvert).
	if _pending_level_ups > 0 and _panel != null and not _panel.visible:
		_open_level_up_panel()

# =============================================================================
# DIRECTOR DE SPAWN
# =============================================================================

func _prune_enemies() -> void:
	for i in range(_enemies.size() - 1, -1, -1):
		var enemy: Variant = _enemies[i]
		if not (enemy is Node) or not is_instance_valid(enemy):
			_enemies.remove_at(i)

func _tick_spawning(dt: float) -> void:
	# Stop avant la fin (story) pour finir sur un écran qui se vide.
	if _duration - _elapsed <= maxf(0.0, float(_get_conf("spawn_stop_before_end_sec", 3.0))):
		return
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		var interval: float = maxf(float(_get_conf("spawn_interval_floor_sec", 0.45)),
			_ramp("spawn_interval_sec_start", "spawn_interval_sec_end", 1.7, 0.6))
		_spawn_timer = interval
		var burst: int = maxi(1, int(round(_ramp("enemies_per_spawn_start", "enemies_per_spawn_end", 1.0, 3.0))))
		_spawn_queue += burst
	# Étalement : jamais plus de N instanciations par frame, cap d'actifs.
	var per_frame: int = maxi(1, int(_get_conf("max_enemy_spawns_per_frame", 4)))
	var cap: int = maxi(1, int(_get_conf("max_active_enemies", 40)))
	while _spawn_queue > 0 and per_frame > 0 and _enemies.size() < cap:
		_spawn_queue -= 1
		per_frame -= 1
		_spawn_enemy(_pick_pool_entry())

## Position sur le périmètre hors écran, côtés pondérés par leur longueur,
## jamais trop près du joueur.
func _pick_spawn_pos() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = maxf(20.0, float(_get_conf("spawn_margin_px", 90.0)))
	var min_dist: float = maxf(0.0, float(_get_conf("spawn_min_dist_from_player_px", 420.0)))
	var p: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else viewport_size * 0.5
	for attempt in range(6):
		var pos: Vector2
		# Pondération : haut/bas = largeur, gauche/droite = hauteur.
		var total: float = viewport_size.x * 2.0 + viewport_size.y * 2.0
		var roll: float = randf() * total
		if roll < viewport_size.x:
			pos = Vector2(randf_range(0.0, viewport_size.x), -margin)
		elif roll < viewport_size.x * 2.0:
			pos = Vector2(randf_range(0.0, viewport_size.x), viewport_size.y + margin)
		elif roll < viewport_size.x * 2.0 + viewport_size.y:
			pos = Vector2(-margin, randf_range(0.0, viewport_size.y))
		else:
			pos = Vector2(viewport_size.x + margin, randf_range(0.0, viewport_size.y))
		if pos.distance_to(p) >= min_dist or attempt == 5:
			return pos
	return Vector2(viewport_size.x * 0.5, -margin)

## Phase courante (par temps écoulé) puis tirage pondéré dans son pool.
func _pick_pool_entry() -> Dictionary:
	var phases_v: Variant = _get_conf("enemy_phases", [])
	var pool: Array = []
	if phases_v is Array:
		for phase_v in (phases_v as Array):
			if phase_v is Dictionary and _elapsed <= float((phase_v as Dictionary).get("until_sec", 99999.0)):
				var pool_v: Variant = (phase_v as Dictionary).get("pool", [])
				if pool_v is Array:
					pool = pool_v as Array
				break
	if pool.is_empty():
		return { "id": "swarmer", "xp": 1 }
	var total: float = 0.0
	for entry_v in pool:
		if entry_v is Dictionary:
			total += maxf(0.0, float((entry_v as Dictionary).get("weight", 0.0)))
	var roll: float = randf() * maxf(0.001, total)
	for entry_v in pool:
		if not (entry_v is Dictionary):
			continue
		roll -= maxf(0.0, float((entry_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			return entry_v as Dictionary
	return pool[0] as Dictionary

func _spawn_enemy(entry: Dictionary) -> void:
	var enemy_id: String = str(entry.get("id", "swarmer"))
	var data: Dictionary = DataManager.get_enemy(enemy_id) if DataManager else {}
	if data.is_empty():
		return
	data = data.duplicate(true)
	data["_movement_mode"] = "seek_player"
	data["_seek_speed_px_sec"] = _ramp("seek_speed_px_sec_start", "seek_speed_px_sec_end", 110.0, 190.0)
	data["_seek_turn_lerp"] = float(_get_conf("seek_turn_lerp", 3.0))
	data["_seek_target_offset_px"] = float(_get_conf("seek_target_offset_px", 60.0))
	# Les récompenses passent par les gemmes XP + coffres : pas de loot direct.
	data["loot_chance"] = 0.0
	var enemy: Node = ENEMY_SCENE.instantiate()
	if not (enemy is CharacterBody2D):
		return
	enemy.add_to_group("enemies")
	add_child(enemy)
	(enemy as Node2D).global_position = _pick_spawn_pos()
	if enemy.has_method("setup"):
		enemy.call("setup", data)
	if enemy.has_method("apply_stat_multipliers"):
		enemy.call("apply_stat_multipliers", {
			"hp_mult": _ramp("enemy_hp_mult_start", "enemy_hp_mult_end", 0.35, 0.85)
		})
	var xp: int = maxi(1, int(entry.get("xp", 1)))
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(func(dead: Node) -> void:
			_on_survivor_enemy_died(dead, xp)
		)
		# Score/killstreak/cristaux standards via Game (drops déjà coupés par
		# _survivor_wave_active côté Game).
		if _game and is_instance_valid(_game) and _game.has_method("_on_enemy_died"):
			enemy.enemy_died.connect(_game._on_enemy_died)
	_enemies.append(enemy)

func _on_survivor_enemy_died(enemy: Node, xp: int) -> void:
	_enemies.erase(enemy)
	if _state == State.DONE:
		return
	if enemy is Node2D and is_instance_valid(enemy):
		_spawn_xp_gem((enemy as Node2D).global_position, xp)

## Anti-empilement : pousse les paires trop proches (throttlé, O(n²) borné).
func _tick_separation(dt: float) -> void:
	_separation_timer -= dt
	if _separation_timer > 0.0:
		return
	_separation_timer = maxf(0.05, float(_get_conf("separation_tick_sec", 0.15)))
	var min_dist: float = maxf(8.0, float(_get_conf("separation_px", 46.0)))
	var push: float = maxf(0.0, float(_get_conf("separation_push_px_sec", 90.0))) * _separation_timer
	var min_dist_sq: float = min_dist * min_dist
	for i in range(_enemies.size()):
		var a: Node2D = _enemies[i] as Node2D
		if a == null or not is_instance_valid(a):
			continue
		for j in range(i + 1, _enemies.size()):
			var b: Node2D = _enemies[j] as Node2D
			if b == null or not is_instance_valid(b):
				continue
			var delta_pos: Vector2 = b.global_position - a.global_position
			if delta_pos.length_squared() < min_dist_sq:
				var dir: Vector2 = delta_pos.normalized() if delta_pos.length_squared() > 0.01 \
					else Vector2.from_angle(randf() * TAU)
				a.global_position -= dir * push * 0.5
				b.global_position += dir * push * 0.5

# =============================================================================
# JOUEUR : FACING + CONTACT
# =============================================================================

func _tick_facing(dt: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("get_survivor_velocity"):
		return
	var vel: Vector2 = _player.call("get_survivor_velocity")
	if vel.length() > maxf(1.0, float(_get_conf("facing_min_speed_px_sec", 30.0))):
		var target_angle: float = vel.angle() + PI * 0.5
		_facing = lerp_angle(_facing, target_angle, clampf(float(_get_conf("facing_turn_lerp", 10.0)) * dt, 0.0, 1.0))
	if _player.has_method("set_survivor_facing"):
		_player.call("set_survivor_facing", _facing)

func _tick_contact_damage(dt: float) -> void:
	if _contact_invuln > 0.0:
		_contact_invuln -= dt
		return
	if _player == null or not is_instance_valid(_player):
		return
	var p: Vector2 = _player.global_position
	var radius: float = maxf(8.0, float(_get_conf("contact_radius_px", 42.0)))
	var radius_sq: float = radius * radius
	for enemy_v in _enemies:
		var enemy: Node2D = enemy_v as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_squared_to(p) <= radius_sq:
			_contact_invuln = maxf(0.1, float(_get_conf("hit_invuln_sec", 0.8)))
			if _player.has_method("take_damage"):
				var max_hp_v: Variant = _player.get("max_hp")
				var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
				var pct: float = clampf(float(_get_conf("contact_damage_percent", 0.08)), 0.0, 1.0)
				_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
			return

# =============================================================================
# XP / GEMMES (contacts manuels par distance, pas de physics)
# =============================================================================

func _spawn_xp_gem(pos: Vector2, xp: int) -> void:
	# Au cap : fusionne dans la gemme existante la plus proche (rien de perdu).
	if _gems.size() >= maxi(4, int(_get_conf("max_active_gems", 60))):
		var best: Dictionary = {}
		var best_dist: float = INF
		for gem_v in _gems:
			var dist: float = ((gem_v as Dictionary).get("pos", Vector2.ZERO) as Vector2).distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best = gem_v as Dictionary
		if not best.is_empty():
			best["xp"] = int(best.get("xp", 1)) + xp
		return
	var tier: Dictionary = _gem_tier_for(xp)
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 6
	var size: float = maxf(8.0, float(tier.get("size_px", 24.0)))
	var tex: Texture2D = _texture_from_path(str(tier.get("asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		# Asset partage (petit cristal) : la teinte par tier distingue small/medium/large.
		sprite.modulate = Color(str(tier.get("tint", "#6BFF9E")))
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (size / maxf(tex_size.x, tex_size.y))
		node.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var s: float = size * 0.5
		poly.polygon = PackedVector2Array([Vector2(-s, 0), Vector2(0, -s), Vector2(s, 0), Vector2(0, s)])
		poly.color = Color(str(tier.get("tint", "#6BFF9E")))
		node.add_child(poly)
	node.global_position = pos
	add_child(node)
	_gems.append({ "node": node, "pos": pos, "xp": xp, "ttl": maxf(4.0, float(_get_conf("gem_ttl_sec", 25.0))) })

func _gem_tier_for(xp: int) -> Dictionary:
	var tiers_v: Variant = _get_conf("gem_tiers", [])
	if tiers_v is Array:
		for tier_v in (tiers_v as Array):
			if tier_v is Dictionary and xp <= int((tier_v as Dictionary).get("xp_max", 9999)):
				return tier_v as Dictionary
	return {}

func _tick_gems(dt: float) -> void:
	if _gems.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		return
	var p: Vector2 = _player.global_position
	var magnet: float = maxf(0.0, float(_get_conf("magnet_radius_px_base", 130.0))) + _passive_total("magnet_radius_px")
	var collect: float = maxf(8.0, float(_get_conf("gem_collect_radius_px", 46.0)))
	var pull: float = maxf(60.0, float(_get_conf("gem_pull_px_sec", 820.0)))
	for i in range(_gems.size() - 1, -1, -1):
		var gem: Dictionary = _gems[i]
		var node_v: Variant = gem.get("node", null)
		var pos: Vector2 = gem.get("pos", Vector2.ZERO)
		var dist: float = pos.distance_to(p)
		if bool(gem.get("pulled", false)) or dist <= magnet:
			gem["pulled"] = true # une gemme accrochée ne lâche plus l'aimant
			pos = pos.move_toward(p, pull * dt)
			gem["pos"] = pos
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).global_position = pos
		gem["ttl"] = float(gem.get("ttl", 10.0)) - dt
		var expired: bool = float(gem["ttl"]) <= 0.0
		if expired and node_v is Node2D and is_instance_valid(node_v) and float(gem["ttl"]) > -1.0:
			(node_v as Node2D).modulate.a = maxf(0.0, 1.0 + float(gem["ttl"]))
		if dist <= collect:
			_grant_xp(int(gem.get("xp", 1)))
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_gems.remove_at(i)
		elif float(gem["ttl"]) <= -1.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_gems.remove_at(i)

func _grant_xp(amount: int) -> void:
	_xp += maxi(0, amount)
	var queue_cap: int = maxi(1, int(_get_conf("level_up_max_queue", 3)))
	while _xp >= _xp_needed_for(_level):
		_xp -= _xp_needed_for(_level)
		_level += 1
		if _state != State.DONE:
			_pending_level_ups = mini(_pending_level_ups + 1, queue_cap)
	_push_xp_to_hud()

func _xp_needed_for(level: int) -> int:
	var curve_v: Variant = _get_conf("xp_curve", [5, 9, 14, 20, 27, 35, 44, 54, 65, 77])
	var curve: Array = (curve_v as Array) if curve_v is Array else [5]
	if curve.is_empty():
		curve = [5]
	var idx: int = level - 1
	if idx < curve.size():
		return maxi(1, int(curve[idx]))
	var growth: float = maxf(1.0, float(_get_conf("xp_curve_growth_after", 1.16)))
	return maxi(1, int(round(float(curve[curve.size() - 1]) * pow(growth, float(idx - curve.size() + 1)))))

func _push_xp_to_hud() -> void:
	if _hud and is_instance_valid(_hud) and _hud.has_method("set_survivor_xp"):
		_hud.call("set_survivor_xp", float(_xp), float(_xp_needed_for(_level)), _level)

# =============================================================================
# LEVEL-UP : ROLL DES CHOIX + PANEL
# =============================================================================

func _ensure_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	_panel = LEVELUP_PANEL_SCRIPT.new()
	if _panel.has_method("setup"):
		_panel.call("setup", {
			"button_min_height_px": int(_get_conf("levelup_button_min_height_px", 150))
		})
	_panel.choice_made.connect(_on_level_up_choice)
	add_child(_panel)

func _open_level_up_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var choices: Array = _roll_choices()
	if choices.is_empty():
		# Tout est au max : compensation en cristaux, pas de pause.
		_pending_level_ups = 0
		if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
			_game.call("spawn_reward_crystals_from_top", 4)
		return
	_pending_level_ups -= 1
	_panel.call("present", choices, _level)

func _weapon_defs() -> Array:
	var v: Variant = _get_conf("weapons", [])
	return (v as Array) if v is Array else []

func _passive_defs() -> Array:
	var v: Variant = _get_conf("passives", [])
	return (v as Array) if v is Array else []

func _owned_weapon(weapon_id: String) -> Dictionary:
	for w_v in _weapons:
		if str(((w_v as Dictionary).get("def", {}) as Dictionary).get("id", "")) == weapon_id:
			return w_v as Dictionary
	return {}

## 3 choix pondérés (choice_weights) sans doublon d'id, avec exclusions :
## nouvelle arme (si slot libre), upgrade (si arme pas au max), passif (si pas
## au max_stacks). Retourne des dicts { kind, def, ... } pour le panel.
func _roll_choices() -> Array:
	var weights: Dictionary = _get_conf("choice_weights", { "new_weapon": 30.0, "weapon_upgrade": 45.0, "passive": 25.0 })
	var max_weapons: int = maxi(1, int(_get_conf("max_weapons", 4)))
	var new_candidates: Array = []
	for def_v in _weapon_defs():
		if def_v is Dictionary and _owned_weapon(str((def_v as Dictionary).get("id", ""))).is_empty():
			new_candidates.append(def_v)
	var upgrade_candidates: Array = []
	for w_v in _weapons:
		var w: Dictionary = w_v as Dictionary
		if int(w.get("level", 1)) < int((w.get("def", {}) as Dictionary).get("max_level", 5)):
			upgrade_candidates.append(w)
	var passive_candidates: Array = []
	for def_v in _passive_defs():
		if not (def_v is Dictionary):
			continue
		var pid: String = str((def_v as Dictionary).get("id", ""))
		if int(_passive_stacks.get(pid, 0)) < int((def_v as Dictionary).get("max_stacks", 3)):
			passive_candidates.append(def_v)
	new_candidates.shuffle()
	upgrade_candidates.shuffle()
	passive_candidates.shuffle()
	var choices: Array = []
	for i in range(3):
		var w_new: float = float(weights.get("new_weapon", 30.0)) \
			if (not new_candidates.is_empty() and _weapons.size() < max_weapons) else 0.0
		var w_up: float = float(weights.get("weapon_upgrade", 45.0)) if not upgrade_candidates.is_empty() else 0.0
		var w_pass: float = float(weights.get("passive", 25.0)) if not passive_candidates.is_empty() else 0.0
		var total: float = w_new + w_up + w_pass
		if total <= 0.0:
			break
		var roll: float = randf() * total
		if roll < w_new:
			choices.append({ "kind": "new_weapon", "def": new_candidates.pop_back() })
		elif roll < w_new + w_up:
			var w: Dictionary = upgrade_candidates.pop_back()
			choices.append({ "kind": "weapon_upgrade", "def": w.get("def", {}), "weapon": w,
				"next_level": int(w.get("level", 1)) + 1 })
		else:
			choices.append({ "kind": "passive", "def": passive_candidates.pop_back() })
	return choices

func _on_level_up_choice(choice: Dictionary) -> void:
	match str(choice.get("kind", "")):
		"new_weapon":
			_add_weapon(choice.get("def", {}) as Dictionary)
		"weapon_upgrade":
			var w: Dictionary = choice.get("weapon", {}) as Dictionary
			if not w.is_empty():
				w["level"] = int(w.get("level", 1)) + 1
				_refresh_weapon_visuals(w)
		"passive":
			var def: Dictionary = choice.get("def", {}) as Dictionary
			var pid: String = str(def.get("id", ""))
			_passive_stacks[pid] = int(_passive_stacks.get(pid, 0)) + 1
			if pid == "move_speed" and _player and is_instance_valid(_player) \
				and _player.has_method("begin_survivor"):
				_player.call("begin_survivor", _control_cfg())
		_:
			pass
	# D'autres level-ups en attente ? Le _process rouvrira le panel.

## Somme d'un champ per_stack sur tous les passifs possédés.
func _passive_total(field: String) -> float:
	var total: float = 0.0
	for def_v in _passive_defs():
		if not (def_v is Dictionary):
			continue
		var def: Dictionary = def_v as Dictionary
		var stacks: int = int(_passive_stacks.get(str(def.get("id", "")), 0))
		if stacks > 0:
			var per_v: Variant = def.get("per_stack", {})
			if per_v is Dictionary:
				total += float((per_v as Dictionary).get(field, 0.0)) * float(stacks)
	return total

func _damage_mult() -> float:
	return maxf(0.1, 1.0 + _passive_total("damage_mult"))

func _cooldown_mult() -> float:
	return maxf(0.3, 1.0 + _passive_total("cooldown_mult"))

# =============================================================================
# ARMES
# =============================================================================

func _add_weapon(def: Dictionary) -> void:
	if def.is_empty() or not _owned_weapon(str(def.get("id", ""))).is_empty():
		return
	var w: Dictionary = { "def": def, "level": 1, "cd": 0.3 }
	_weapons.append(w)
	_refresh_weapon_visuals(w)

## Stat effective : base <- levels[0..level-1] mergés (chaque niveau écrase).
func _weapon_stat(w: Dictionary, key: String, fallback: float) -> float:
	var def: Dictionary = w.get("def", {}) as Dictionary
	var base_v: Variant = def.get("base", {})
	var value: float = float((base_v as Dictionary).get(key, fallback)) if base_v is Dictionary else fallback
	var levels_v: Variant = def.get("levels", [])
	if levels_v is Array:
		var levels: Array = levels_v as Array
		for i in range(mini(int(w.get("level", 1)), levels.size())):
			if levels[i] is Dictionary and (levels[i] as Dictionary).has(key):
				value = float((levels[i] as Dictionary)[key])
	return value

func _weapon_damage(w: Dictionary, key: String = "damage", fallback: float = 100.0) -> int:
	return maxi(1, int(round(_weapon_stat(w, key, fallback) * _damage_mult())))

func _weapon_cooldown(w: Dictionary, fallback: float = 1.0) -> float:
	return maxf(0.1, _weapon_stat(w, "cooldown_sec", fallback) * _cooldown_mult())

## Ennemi vivant le plus proche d'un point (option : dans une portée max, en
## excluant une liste de refs).
func _closest_enemy(from: Vector2, range_px: float = INF, exclude: Array = []) -> Node2D:
	var best: Node2D = null
	var best_dist: float = range_px
	for enemy_v in _enemies:
		var enemy: Node2D = enemy_v as Node2D
		if enemy == null or not is_instance_valid(enemy) or exclude.has(enemy):
			continue
		var dist: float = enemy.global_position.distance_to(from)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best

func _tick_weapons(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for w_v in _weapons:
		var w: Dictionary = w_v as Dictionary
		var behavior: String = str((w.get("def", {}) as Dictionary).get("behavior", ""))
		match behavior:
			"auto_shot", "chain", "nova":
				w["cd"] = float(w.get("cd", 0.0)) - dt
				if float(w["cd"]) <= 0.0:
					var fired: bool = false
					match behavior:
						"auto_shot":
							fired = _fire_auto_shot(w)
						"chain":
							fired = _fire_chain_lightning(w)
						"nova":
							fired = _fire_nova(w)
					# Sans cible, on re-essaie vite (pas de cooldown gâché).
					w["cd"] = _weapon_cooldown(w) if fired else 0.2
			"zone":
				_tick_tesla_field(w, dt)
			"orbital":
				_tick_orbitals(w, dt)
			"laser":
				_tick_laser(w, dt)
			_:
				pass

## 1. Tir automatique vers l'ennemi le plus proche (pipeline projectile
## standard : pool, layer joueur, crit non geré ici — dégâts data).
func _fire_auto_shot(w: Dictionary) -> bool:
	var target: Node2D = _closest_enemy(_player.global_position, _weapon_stat(w, "range_px", 640.0))
	if target == null:
		return false
	var damage: int = _weapon_damage(w)
	var speed: float = _weapon_stat(w, "speed_px_sec", 900.0)
	var count: int = maxi(1, int(_weapon_stat(w, "projectiles", 1.0)))
	var spread: float = deg_to_rad(_weapon_stat(w, "spread_deg", 8.0))
	var base_dir: Vector2 = (target.global_position - _player.global_position).normalized()
	for i in range(count):
		var offset: float = 0.0 if count == 1 else lerpf(-spread, spread, float(i) / float(count - 1))
		ProjectileManager.spawn_player_projectile(
			_player.global_position, base_dir.rotated(offset), speed, damage,
			{
				"trajectory": "straight",
				"max_lifetime": 2.5,
				"despawn_after_sec": 2.5,
				"visual_data": { "size": 14.0, "color": "#B4FF6B", "shape": "circle" }
			})
	return true

## 2. Foudre en chaîne : frappe le plus proche puis saute (recette breakout).
func _fire_chain_lightning(w: Dictionary) -> bool:
	var from: Vector2 = _player.global_position
	var first: Node2D = _closest_enemy(from, _weapon_stat(w, "range_px", 460.0))
	if first == null:
		return false
	var damage: int = _weapon_damage(w)
	var chain_range: float = _weapon_stat(w, "chain_range_px", 260.0)
	var max_chains: int = maxi(1, int(_weapon_stat(w, "max_chains", 3.0)))
	var color: Color = Color(str(_weapon_stat_str(w, "arc_color", "#9AF6FF")))
	var hit: Array = []
	var current: Node2D = first
	for i in range(max_chains + 1):
		if current == null:
			break
		_spawn_chain_arc(from, current.global_position, color)
		from = current.global_position
		hit.append(current)
		if current.has_method("take_damage"):
			current.call("take_damage", damage)
		current = _closest_enemy(from, chain_range, hit)
	return true

func _weapon_stat_str(w: Dictionary, key: String, fallback: String) -> String:
	var def: Dictionary = w.get("def", {}) as Dictionary
	var base_v: Variant = def.get("base", {})
	var value: String = str((base_v as Dictionary).get(key, fallback)) if base_v is Dictionary else fallback
	var levels_v: Variant = def.get("levels", [])
	if levels_v is Array:
		var levels: Array = levels_v as Array
		for i in range(mini(int(w.get("level", 1)), levels.size())):
			if levels[i] is Dictionary and (levels[i] as Dictionary).has(key):
				value = str((levels[i] as Dictionary)[key])
	return value

func _weapon_stat_arr(w: Dictionary, key: String, fallback: Array) -> Array:
	var def: Dictionary = w.get("def", {}) as Dictionary
	var base_v: Variant = def.get("base", {})
	var value: Array = fallback
	if base_v is Dictionary and (base_v as Dictionary).get(key, null) is Array:
		value = (base_v as Dictionary)[key] as Array
	var levels_v: Variant = def.get("levels", [])
	if levels_v is Array:
		var levels: Array = levels_v as Array
		for i in range(mini(int(w.get("level", 1)), levels.size())):
			if levels[i] is Dictionary and (levels[i] as Dictionary).get(key, null) is Array:
				value = (levels[i] as Dictionary)[key] as Array
	return value

## Arc Line2D en sinusoïde bruitée, additif, extrémités ancrées (recette
## breakout chain), fade rapide via _chain_arcs.
func _spawn_chain_arc(from: Vector2, to: Vector2, color: Color) -> void:
	_ensure_fx_add_material()
	var dir: Vector2 = to - from
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	for layer in range(2):
		var line := Line2D.new()
		line.width = 5.0 if layer == 0 else 2.0
		line.default_color = color if layer == 0 else Color.WHITE
		line.material = _fx_add_material
		line.z_as_relative = false
		line.z_index = 13
		var phase: float = randf() * TAU
		var points := PackedVector2Array()
		for i in range(10):
			var t: float = float(i) / 9.0
			var wobble: float = sin(t * PI * 3.0 + phase) * 12.0 * randf_range(0.4, 1.0) * sin(t * PI)
			points.append(from + dir * t + perp * wobble)
		line.points = points
		add_child(line)
		_chain_arcs.append({ "line": line, "time": 0.25, "max": 0.25 })

## 3. Zone électrique suiveuse (tick manuel par distance, anneau Line2D).
func _tick_tesla_field(w: Dictionary, dt: float) -> void:
	var radius: float = _weapon_stat(w, "radius_px", 150.0)
	if _tesla_ring == null or not is_instance_valid(_tesla_ring):
		_ensure_fx_add_material()
		_tesla_ring = Line2D.new()
		_tesla_ring.width = 3.0
		_tesla_ring.default_color = Color(str(_weapon_stat_str(w, "ring_color", "#7FD8FF")))
		_tesla_ring.material = _fx_add_material
		_tesla_ring.z_as_relative = false
		_tesla_ring.z_index = 5
		_tesla_ring.closed = true
		add_child(_tesla_ring)
	var points := PackedVector2Array()
	for i in range(28):
		var a: float = TAU * float(i) / 28.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	_tesla_ring.points = points
	_tesla_ring.position = _player.global_position
	_tesla_ring.modulate.a = 0.55 + 0.25 * sin(_elapsed * 5.0)
	_tesla_tick -= dt
	if _tesla_tick > 0.0:
		return
	_tesla_tick = maxf(0.1, _weapon_stat(w, "tick_sec", 0.5) * _cooldown_mult())
	var damage: int = _weapon_damage(w, "damage_per_tick", 45.0)
	var radius_sq: float = radius * radius
	for enemy_v in _enemies:
		var enemy: Node2D = enemy_v as Node2D
		if enemy and is_instance_valid(enemy) \
			and enemy.global_position.distance_squared_to(_player.global_position) <= radius_sq \
			and enemy.has_method("take_damage"):
			enemy.call("take_damage", damage)

## 4. Orbes orbitales (patron companion gravity_hole) : dégâts au contact avec
## cooldown par ennemi.
func _tick_orbitals(w: Dictionary, dt: float) -> void:
	var count: int = maxi(1, int(_weapon_stat(w, "orb_count", 1.0)))
	if _orb_root == null or not is_instance_valid(_orb_root):
		_orb_root = Node2D.new()
		_orb_root.z_as_relative = false
		_orb_root.z_index = 12
		add_child(_orb_root)
		_orb_nodes.clear()
	if _orb_nodes.size() != count:
		for node_v in _orb_nodes:
			if node_v is Node and is_instance_valid(node_v):
				(node_v as Node).queue_free()
		_orb_nodes.clear()
		var size: float = _weapon_stat(w, "orb_size_px", 34.0)
		var tex: Texture2D = _texture_from_path(str(_weapon_stat_str(w, "orb_asset", "")))
		for i in range(count):
			var orb := Node2D.new()
			if tex != null:
				var sprite := Sprite2D.new()
				sprite.texture = tex
				var tex_size: Vector2 = tex.get_size()
				if tex_size.x > 0.0 and tex_size.y > 0.0:
					sprite.scale = Vector2.ONE * (size / maxf(tex_size.x, tex_size.y))
				orb.add_child(sprite)
			else:
				var poly := Polygon2D.new()
				var pts := PackedVector2Array()
				for k in range(12):
					var a: float = TAU * float(k) / 12.0
					pts.append(Vector2(cos(a), sin(a)) * size * 0.5)
				poly.polygon = pts
				poly.color = Color("#9AF6FF")
				orb.add_child(poly)
			_orb_root.add_child(orb)
			_orb_nodes.append(orb)
	_orb_angle += dt * TAU / maxf(0.4, _weapon_stat(w, "orbit_sec", 2.2))
	var orbit_radius: float = _weapon_stat(w, "orbit_radius_px", 120.0)
	_orb_root.global_position = _player.global_position
	var damage: int = _weapon_damage(w)
	var hit_cd_msec: int = int(_weapon_stat(w, "hit_cooldown_sec", 0.5) * 1000.0)
	var hit_radius: float = _weapon_stat(w, "orb_size_px", 34.0) * 0.75
	var hit_radius_sq: float = hit_radius * hit_radius
	var now: int = Time.get_ticks_msec()
	for i in range(_orb_nodes.size()):
		var orb: Node2D = _orb_nodes[i] as Node2D
		if orb == null or not is_instance_valid(orb):
			continue
		var angle: float = _orb_angle + TAU * float(i) / float(maxi(1, _orb_nodes.size()))
		orb.position = Vector2.from_angle(angle) * orbit_radius
		for enemy_v in _enemies:
			var enemy: Node2D = enemy_v as Node2D
			if enemy == null or not is_instance_valid(enemy):
				continue
			if enemy.global_position.distance_squared_to(orb.global_position) <= hit_radius_sq:
				var eid: int = enemy.get_instance_id()
				if now - int(_orb_hit_cd.get(eid, 0)) >= hit_cd_msec:
					_orb_hit_cd[eid] = now
					if enemy.has_method("take_damage"):
						enemy.call("take_damage", damage)

## 5. Nova périodique : dégâts + knockback avec falloff, anneau en expansion.
func _fire_nova(w: Dictionary) -> bool:
	if _enemies.is_empty():
		return false
	var radius: float = _weapon_stat(w, "radius_px", 260.0)
	var damage_base: int = _weapon_damage(w)
	var knockback: float = _weapon_stat(w, "knockback_px", 140.0)
	var falloff: float = clampf(_weapon_stat(w, "falloff", 0.5), 0.0, 1.0)
	var center: Vector2 = _player.global_position
	var touched: bool = false
	for enemy_v in _enemies:
		var enemy: Node2D = enemy_v as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var dist: float = enemy.global_position.distance_to(center)
		if dist > radius:
			continue
		touched = true
		var factor: float = 1.0 - falloff * (dist / radius)
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", maxi(1, int(round(float(damage_base) * factor))))
		if enemy.has_method("apply_seek_knockback"):
			var dir: Vector2 = (enemy.global_position - center).normalized()
			enemy.call("apply_seek_knockback", dir * knockback * factor * 3.0)
	if not touched:
		return false
	# Anneau en expansion (fade via _nova_rings).
	_ensure_fx_add_material()
	var ring := Line2D.new()
	ring.width = 6.0
	ring.default_color = Color(str(_weapon_stat_str(w, "ring_color", "#FFD866")))
	ring.material = _fx_add_material
	ring.z_as_relative = false
	ring.z_index = 13
	ring.closed = true
	ring.position = center
	add_child(ring)
	_nova_rings.append({ "line": ring, "time": 0.4, "max": 0.4, "radius": radius })
	if VFXManager:
		VFXManager.screen_shake(3.0, 0.15)
	return true

## 6. Laser(s) rotatif(s) transperçant(s) : chaque faisceau est matérialisé par
## ~30 brins sinusoïdaux désynchronisés (violet/rouge/blanc). Dégâts inchangés :
## distance point-segment sur l'axe central de chaque faisceau.
func _tick_laser(w: Dictionary, dt: float) -> void:
	var beam_count: int = maxi(1, int(_weapon_stat(w, "beam_count", 1.0)))
	var strands: int = maxi(3, int(_weapon_stat(w, "strand_count", 30.0)))
	var length: float = _weapon_stat(w, "length_px", 420.0)
	var width: float = _weapon_stat(w, "width_px", 14.0)
	var amp: float = _weapon_stat(w, "wave_amplitude_px", 26.0)
	var freq: float = _weapon_stat(w, "wave_freq", 5.0)
	var wave_speed: float = _weapon_stat(w, "wave_speed", 9.0)
	var seg: int = maxi(6, int(_weapon_stat(w, "wave_segments", 22.0)))
	var strand_w: float = maxf(1.0, _weapon_stat(w, "strand_width_px", 3.0))
	var colors: Array = _weapon_stat_arr(w, "strand_colors", ["#B24BFF", "#FF3B3B", "#FFFFFF"])
	if colors.is_empty():
		colors = ["#FFFFFF"]
	var total: int = beam_count * strands
	if _laser_beams.size() != total:
		for beam_v in _laser_beams:
			if beam_v is Node and is_instance_valid(beam_v):
				(beam_v as Node).queue_free()
		_laser_beams.clear()
		_ensure_fx_add_material()
		for i in range(total):
			var strand := Line2D.new()
			strand.width = strand_w
			strand.default_color = Color(str(colors[i % colors.size()]))
			strand.material = _fx_add_material
			strand.z_as_relative = false
			strand.z_index = 12
			strand.joint_mode = Line2D.LINE_JOINT_ROUND
			strand.begin_cap_mode = Line2D.LINE_CAP_ROUND
			strand.end_cap_mode = Line2D.LINE_CAP_ROUND
			add_child(strand)
			_laser_beams.append(strand)
	_laser_angle += dt * deg_to_rad(_weapon_stat(w, "rot_deg_sec", 90.0))
	var center: Vector2 = _player.global_position
	for b in range(beam_count):
		var base_angle: float = _laser_angle + TAU * float(b) / float(beam_count)
		var axis: Vector2 = Vector2.from_angle(base_angle)
		var perp := Vector2(-axis.y, axis.x)
		for s in range(strands):
			var idx: int = b * strands + s
			if idx >= _laser_beams.size():
				break
			var strand: Line2D = _laser_beams[idx] as Line2D
			if strand == null or not is_instance_valid(strand):
				continue
			# Désynchronisation : phase propre, amplitude et fréquence variées par brin.
			var phase: float = TAU * float(s) / float(strands)
			var s_amp: float = amp * (0.30 + 0.70 * float(s % 7) / 6.0)
			var s_freq: float = freq * (0.75 + 0.5 * float((s * 3) % 5) / 4.0)
			var pts := PackedVector2Array()
			for k in range(seg + 1):
				var t: float = float(k) / float(seg)
				# Enveloppe (0 aux extrémités) pour un faisceau resserré au canon et à la pointe.
				var envelope: float = sin(t * PI)
				var off: float = sin(t * s_freq * TAU + phase + _elapsed * wave_speed) * s_amp * envelope
				pts.append(center + axis * (t * length) + perp * off)
			strand.points = pts
			strand.modulate.a = 0.35 + 0.4 * absf(sin(_elapsed * 6.0 + phase))
	_laser_tick -= dt
	if _laser_tick > 0.0:
		return
	_laser_tick = maxf(0.1, _weapon_stat(w, "tick_sec", 0.25) * _cooldown_mult())
	var damage: int = _weapon_damage(w, "damage_per_tick", 35.0)
	var half_width: float = width * 0.5 + amp
	for b in range(beam_count):
		var angle: float = _laser_angle + TAU * float(b) / float(beam_count)
		var tip: Vector2 = center + Vector2.from_angle(angle) * length
		for enemy_v in _enemies:
			var enemy: Node2D = enemy_v as Node2D
			if enemy == null or not is_instance_valid(enemy):
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(enemy.global_position, center, tip)
			if enemy.global_position.distance_to(closest) <= half_width and enemy.has_method("take_damage"):
				enemy.call("take_damage", damage)

## Reconstruit les visuels dépendant du niveau (orbes en plus, laser en plus).
func _refresh_weapon_visuals(w: Dictionary) -> void:
	var behavior: String = str((w.get("def", {}) as Dictionary).get("behavior", ""))
	if behavior == "orbital":
		# Le rebuild se fait au prochain tick (compte comparé).
		pass
	elif behavior == "laser":
		pass

## Fade des visuels éphémères (arcs de foudre, anneaux de nova).
func _tick_weapon_visuals(dt: float) -> void:
	for i in range(_chain_arcs.size() - 1, -1, -1):
		var arc: Dictionary = _chain_arcs[i]
		arc["time"] = float(arc.get("time", 0.0)) - dt
		var line_v: Variant = arc.get("line", null)
		if float(arc["time"]) <= 0.0:
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
			_chain_arcs.remove_at(i)
		elif line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).modulate.a = float(arc["time"]) / maxf(0.01, float(arc.get("max", 0.25)))
	for i in range(_nova_rings.size() - 1, -1, -1):
		var ring: Dictionary = _nova_rings[i]
		ring["time"] = float(ring.get("time", 0.0)) - dt
		var line_v: Variant = ring.get("line", null)
		if float(ring["time"]) <= 0.0:
			if line_v is Line2D and is_instance_valid(line_v):
				(line_v as Line2D).queue_free()
			_nova_rings.remove_at(i)
		elif line_v is Line2D and is_instance_valid(line_v):
			var line: Line2D = line_v as Line2D
			var progress: float = 1.0 - float(ring["time"]) / maxf(0.01, float(ring.get("max", 0.4)))
			var radius: float = float(ring.get("radius", 260.0)) * progress
			var points := PackedVector2Array()
			for k in range(24):
				var a: float = TAU * float(k) / 24.0
				points.append(Vector2(cos(a), sin(a)) * radius)
			line.points = points
			line.modulate.a = 1.0 - progress

# =============================================================================
# COFFRES
# =============================================================================

func _tick_chests(dt: float) -> void:
	if not bool(_get_conf("chest_enabled", true)):
		return
	# TTL + collecte par distance.
	if _player and is_instance_valid(_player):
		var collect: float = maxf(10.0, float(_get_conf("chest_collect_radius_px", 52.0)))
		var collect_sq: float = collect * collect
		for i in range(_chests.size() - 1, -1, -1):
			var chest: Dictionary = _chests[i]
			chest["ttl"] = float(chest.get("ttl", 10.0)) - dt
			var node_v: Variant = chest.get("node", null)
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).scale = Vector2.ONE * (1.0 + 0.08 * sin(_elapsed * 4.0))
			var pos: Vector2 = chest.get("pos", Vector2.ZERO)
			if pos.distance_squared_to(_player.global_position) <= collect_sq:
				_collect_chest(chest)
				if node_v is Node2D and is_instance_valid(node_v):
					(node_v as Node2D).queue_free()
				_chests.remove_at(i)
			elif float(chest["ttl"]) <= 0.0:
				if node_v is Node2D and is_instance_valid(node_v):
					(node_v as Node2D).queue_free()
				_chests.remove_at(i)
	# Spawn périodique (cap par vague en story ; en libre le cap se recharge
	# implicitement car la vague ne finit jamais — acceptable).
	if _chests_spawned >= maxi(0, int(_get_conf("chest_max_per_wave", 3))):
		return
	_chest_timer -= dt
	if _chest_timer <= 0.0:
		_chest_timer = randf_range(maxf(4.0, float(_get_conf("chest_interval_sec_min", 20.0))),
			maxf(5.0, float(_get_conf("chest_interval_sec_max", 34.0))))
		_spawn_chest()

func _spawn_chest() -> void:
	_chests_spawned += 1
	var viewport_size: Vector2 = get_viewport_rect().size
	var pos := Vector2(randf_range(viewport_size.x * 0.15, viewport_size.x * 0.85),
		randf_range(viewport_size.y * 0.2, viewport_size.y * 0.75))
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 7
	var size: float = maxf(20.0, float(_get_conf("chest_size_px", 56.0)))
	var tex: Texture2D = _texture_from_path(str(_get_conf("chest_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2.ONE * (size / maxf(tex_size.x, tex_size.y))
		node.add_child(sprite)
	else:
		var poly := Polygon2D.new()
		var s: float = size * 0.5
		poly.polygon = PackedVector2Array([Vector2(-s, -s * 0.7), Vector2(s, -s * 0.7), Vector2(s, s * 0.7), Vector2(-s, s * 0.7)])
		poly.color = Color("#FFD866")
		node.add_child(poly)
	node.global_position = pos
	add_child(node)
	_chests.append({ "node": node, "pos": pos, "ttl": maxf(5.0, float(_get_conf("chest_ttl_sec", 30.0))) })

## Cristaux garantis + item (toast haut-droite automatique via LootDrop).
func _collect_chest(chest: Dictionary) -> void:
	var pos: Vector2 = chest.get("pos", Vector2.ZERO)
	if _game == null or not is_instance_valid(_game):
		return
	var crystals: int = randi_range(maxi(0, int(_get_conf("chest_crystal_count_min", 6))),
		maxi(1, int(_get_conf("chest_crystal_count_max", 10))))
	if _game.has_method("spawn_reward_crystal_at"):
		for i in range(crystals):
			_game.call("spawn_reward_crystal_at", pos + Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0)))
	if randf() < clampf(float(_get_conf("chest_equipment_chance", 1.0)), 0.0, 1.0) \
		and _game.has_method("spawn_reward_equipment_at"):
		_game.call("spawn_reward_equipment_at", pos,
			maxf(1.0, float(_get_conf("chest_equipment_quality_mult", 1.4))),
			{ "auto_collect_delay_sec": 1.2 }, _pick_chest_rarity())
	if VFXManager:
		VFXManager.spawn_impact(pos, 24.0, self)

func _pick_chest_rarity() -> String:
	var weights_v: Variant = _get_conf("chest_rarity_weights", { "rare": 60.0, "epic": 32.0, "legendary": 8.0 })
	if not (weights_v is Dictionary):
		return "rare"
	var weights: Dictionary = weights_v as Dictionary
	var total: float = 0.0
	for key in weights.keys():
		total += maxf(0.0, float(weights[key]))
	var roll: float = randf() * maxf(0.001, total)
	for key in weights.keys():
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return str(key)
	return "rare"

# =============================================================================
# UTILITAIRES / FIN
# =============================================================================

func _ensure_fx_add_material() -> void:
	if _fx_add_material == null:
		_fx_add_material = CanvasItemMaterial.new()
		_fx_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

## Texture2D depuis un chemin (accepte les .tres SpriteFrames : 1re frame),
## cache fort local — jamais de load() répété en frame.
func _texture_from_path(path: String) -> Texture2D:
	if path == "":
		return null
	if _resolved_textures.has(path):
		return _resolved_textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			tex = res
		elif res is SpriteFrames:
			var frames: SpriteFrames = res as SpriteFrames
			var anims: PackedStringArray = frames.get_animation_names()
			if anims.size() > 0 and frames.get_frame_count(anims[0]) > 0:
				tex = frames.get_frame_texture(anims[0], 0)
	_resolved_textures[path] = tex
	return tex

func _finish() -> void:
	if _state == State.DONE:
		return
	_state = State.DONE
	# Collecte automatique des gemmes restantes (rien de perdu au gong).
	for gem_v in _gems:
		var gem: Dictionary = gem_v as Dictionary
		_xp += int(gem.get("xp", 0))
		var node_v: Variant = gem.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_gems.clear()
	_push_xp_to_hud()
	# Envol gracieux des ennemis restants.
	for enemy_v in _enemies:
		var enemy: Node = enemy_v as Node
		if enemy and is_instance_valid(enemy) and enemy.has_method("start_wave_end_flyoff"):
			enemy.call("start_wave_end_flyoff", Vector2.UP, 900.0)
	_enemies.clear()
	_restore_player()
	if not _finished_emitted:
		_finished_emitted = true
		finished.emit()

func finish_now() -> void:
	_finish()

func _restore_player() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_survivor"):
		_player.call("end_survivor")
	if _hud and is_instance_valid(_hud) and _hud.has_method("set_survivor_xp_visible"):
		_hud.call("set_survivor_xp_visible", false)
	if _panel and is_instance_valid(_panel) and _panel.has_method("force_close"):
		_panel.call("force_close")

func _exit_tree() -> void:
	# Défensif : restaure toujours le joueur/HUD et dé-pause si le panel était
	# ouvert, même si le manager est libéré de l'extérieur.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player()
