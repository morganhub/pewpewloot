extends Node

## ProjectileManager — Gère le pooling des projectiles pour optimiser les perfs.
## Sépare les projectiles joueur et ennemis.

# =============================================================================
# POOLS
# =============================================================================

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

var _player_pool: Array = []
var _enemy_pool: Array = []

var _active_player_projectiles: Array = []
var _active_enemy_projectiles: Array = []

var _projectile_container: Node2D = null
var _last_enemy_pool_warning_ms: int = -10000
var _enemy_projectile_speed_multiplier: float = 1.0

# Pool expansion is spread over frames: instantiating a full expand_step in the
# middle of a gameplay frame is a visible hitch (cf. performance_improvements.md).
const POOL_EXPAND_IMMEDIATE: int = 8
const POOL_EXPAND_PER_FRAME: int = 4
var _enemy_pool_expand_remaining: int = 0

# =============================================================================
# INIT
# =============================================================================

func _ready() -> void:
	set_process(false)
	call_deferred("_init_pools")

func _process(_delta: float) -> void:
	# Background top-up of the enemy pool, a few instances per frame.
	if _enemy_pool_expand_remaining <= 0:
		set_process(false)
		return
	var batch: int = mini(POOL_EXPAND_PER_FRAME, _enemy_pool_expand_remaining)
	_enemy_pool_expand_remaining -= batch
	_expand_enemy_pool(batch)

func set_container(container: Node2D) -> void:
	_projectile_container = container

func _init_pools() -> void:
	var cfg: Dictionary = {}
	if DataManager:
		cfg = DataManager.get_game_config().get("projectile_pools", {})
	var pool_player: int = int(cfg.get("pool_size_player", 200))
	var pool_enemy: int = int(cfg.get("pool_size_enemy", 200))
	pool_player = maxi(1, pool_player)
	pool_enemy = maxi(1, pool_enemy)

	# Pool joueur
	for i in range(pool_player):
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.is_player_projectile = true
		projectile.set_meta("pooled", true)
		projectile.projectile_deactivated.connect(_on_projectile_deactivated)
		_player_pool.append(projectile)

	# Pool ennemis
	for i in range(pool_enemy):
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.is_player_projectile = false
		projectile.set_meta("pooled", true)
		projectile.projectile_deactivated.connect(_on_projectile_deactivated)
		_enemy_pool.append(projectile)

func set_enemy_projectile_speed_multiplier(multiplier: float) -> void:
	_enemy_projectile_speed_multiplier = maxf(0.0, multiplier)

# =============================================================================
# SPAWN
# =============================================================================

func spawn_player_projectile(pos: Vector2, direction: Vector2, speed: float, damage: int, pattern_data: Dictionary = {}, is_critical: bool = false, p_skill_modifiers: Dictionary = {}) -> void:
	if _player_pool.is_empty():
		push_warning("[ProjectileManager] Player pool empty!")
		return

	var projectile: Area2D = _player_pool.pop_back() # Cast explicite
	projectile.set_meta("pooled", false)
	_active_player_projectiles.append(projectile)
	
	var vp_size = get_viewport().get_visible_rect().size
	if _projectile_container and Engine.is_in_physics_frame():
		# Important: avoid physics query flush errors when called from collision callbacks.
		_projectile_container.call_deferred("add_child", projectile)
		call_deferred(
			"_activate_projectile_deferred",
			projectile,
			pos,
			direction,
			speed,
			damage,
			pattern_data,
			is_critical,
			vp_size,
			p_skill_modifiers
		)
		return
	
	if _projectile_container:
		# Note: Le parent est retiré dans _return_to_pool, donc c'est safe ici
		_projectile_container.add_child(projectile)
	
	projectile.activate(pos, direction, speed, damage, pattern_data, is_critical, vp_size, p_skill_modifiers)

func spawn_enemy_projectile(pos: Vector2, direction: Vector2, speed: float, damage: int, pattern_data: Dictionary = {}) -> void:
	if _enemy_pool.is_empty():
		var cfg: Dictionary = DataManager.get_game_config().get("projectile_pools", {}) if DataManager else {}
		var expand_step: int = maxi(1, int(cfg.get("enemy_pool_expand_step", 64)))
		# Instantiate just enough to serve the current volley; the rest of the
		# step is topped up a few per frame in _process (no one-frame spike).
		_expand_enemy_pool(mini(POOL_EXPAND_IMMEDIATE, expand_step))
		_enemy_pool_expand_remaining += maxi(0, expand_step - POOL_EXPAND_IMMEDIATE)
		if _enemy_pool_expand_remaining > 0:
			set_process(true)
		if _enemy_pool.is_empty():
			var now_ms: int = Time.get_ticks_msec()
			if now_ms - _last_enemy_pool_warning_ms > 1000:
				push_warning("[ProjectileManager] Enemy pool empty!")
				_last_enemy_pool_warning_ms = now_ms
			return

	var projectile: Area2D = _enemy_pool.pop_back() # Cast explicite
	projectile.set_meta("pooled", false)
	_active_enemy_projectiles.append(projectile)
	var final_speed: float = speed * _enemy_projectile_speed_multiplier
	
	var vp_size = get_viewport().get_visible_rect().size
	if _projectile_container and Engine.is_in_physics_frame():
		_projectile_container.call_deferred("add_child", projectile)
		call_deferred(
			"_activate_projectile_deferred",
			projectile,
			pos,
			direction,
			final_speed,
			damage,
			pattern_data,
			false,
			vp_size,
			{}
		)
		return
	
	if _projectile_container:
		_projectile_container.add_child(projectile)
	
	projectile.activate(pos, direction, final_speed, damage, pattern_data, false, vp_size)

func _expand_enemy_pool(count: int) -> void:
	if count <= 0:
		return
	for i in range(count):
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.is_player_projectile = false
		projectile.set_meta("pooled", true)
		projectile.projectile_deactivated.connect(_on_projectile_deactivated)
		_enemy_pool.append(projectile)

func _activate_projectile_deferred(
	projectile: Area2D,
	pos: Vector2,
	direction: Vector2,
	speed: float,
	damage: int,
	pattern_data: Dictionary,
	is_critical: bool,
	vp_size: Vector2,
	p_skill_modifiers: Dictionary
) -> void:
	if not is_instance_valid(projectile):
		return
	projectile.activate(pos, direction, speed, damage, pattern_data, is_critical, vp_size, p_skill_modifiers)

# =============================================================================
# DEACTIVATE
# =============================================================================

func _on_projectile_deactivated(projectile: Area2D) -> void:
	# Retirer de la liste active immédiatement
	if projectile.is_player_projectile:
		_active_player_projectiles.erase(projectile)
	else:
		_active_enemy_projectiles.erase(projectile)
		
	# Retirer de la scène de manière différée (obligatoire lors d'un callback physique)
	if projectile.get_parent():
		projectile.get_parent().call_deferred("remove_child", projectile)
	
	# Remettre dans le pool DE MANIÈRE DIFFÉRÉE également
	# Cela garantit qu'on ne réutilise pas le projectile avant qu'il ne soit retiré de l'arbre
	call_deferred("_return_to_pool", projectile)

func _return_to_pool(projectile: Area2D) -> void:
	if not is_instance_valid(projectile):
		return
		
	# Sécurité : Si le projectile a encore un parent ici (rare mais possible si race condition), on force le retrait
	if projectile.get_parent():
		projectile.get_parent().remove_child(projectile)
		
	# O(1) double-insert guard: a linear "in pool" scan over hundreds of
	# entries on every deactivation adds up on busy frames.
	if projectile.get_meta("pooled", false):
		return
	projectile.set_meta("pooled", true)
	if projectile.is_player_projectile:
		_player_pool.append(projectile)
	else:
		_enemy_pool.append(projectile)

func clear_all_projectiles() -> void:
	# Désactive tous les projectiles actifs
	for projectile in _active_player_projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.deactivate()
	
	for projectile in _active_enemy_projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.deactivate()
	
	print("[ProjectileManager] All projectiles cleared")

func get_active_player_projectile_count() -> int:
	return _active_player_projectiles.size()

func get_active_enemy_projectile_count() -> int:
	return _active_enemy_projectiles.size()
