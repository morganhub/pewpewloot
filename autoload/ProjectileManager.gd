extends Node

## ProjectileManager — Gère le pooling des projectiles pour optimiser les perfs.
## Sépare les projectiles joueur et ennemis.

# =============================================================================
# POOLS
# =============================================================================

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

const POOL_SIZE_PLAYER: int = 100
const POOL_SIZE_ENEMY: int = 200

var _player_pool: Array = []
var _enemy_pool: Array = []

var _active_player_projectiles: Array = []
var _active_enemy_projectiles: Array = []

var _projectile_container: Node2D = null

# =============================================================================
# INIT
# =============================================================================

func _ready() -> void:
	_init_pools()

func set_container(container: Node2D) -> void:
	_projectile_container = container

func _init_pools() -> void:
	# Pool joueur
	for i in range(POOL_SIZE_PLAYER):
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.is_player_projectile = true
		projectile.projectile_deactivated.connect(_on_projectile_deactivated)
		_player_pool.append(projectile)
	
	# Pool ennemis
	for i in range(POOL_SIZE_ENEMY):
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.is_player_projectile = false
		projectile.projectile_deactivated.connect(_on_projectile_deactivated)
		_enemy_pool.append(projectile)
	
	print("[ProjectileManager] Pools created: Player=", POOL_SIZE_PLAYER, ", Enemy=", POOL_SIZE_ENEMY)

# =============================================================================
# SPAWN
# =============================================================================

func spawn_player_projectile(pos: Vector2, direction: Vector2, speed: float, damage: int, pattern_data: Dictionary = {}, is_critical: bool = false) -> void:
	if _player_pool.is_empty():
		push_warning("[ProjectileManager] Player pool empty!")
		return
	
	if _player_pool.size() < 10:
		print("[ProjectileManager] ⚠️ Player pool low: ", _player_pool.size(), " remaining")
	
	var projectile: Area2D = _player_pool.pop_back() # Cast explicite
	_active_player_projectiles.append(projectile)
	
	if _projectile_container:
		# Note: Le parent est retiré dans _return_to_pool, donc c'est safe ici
		_projectile_container.add_child(projectile)
	
	var vp_size = get_viewport().get_visible_rect().size
	projectile.activate(pos, direction, speed, damage, pattern_data, is_critical, vp_size)

func spawn_enemy_projectile(pos: Vector2, direction: Vector2, speed: float, damage: int, pattern_data: Dictionary = {}) -> void:
	if _enemy_pool.is_empty():
		push_warning("[ProjectileManager] Enemy pool empty!")
		return
	
	var projectile: Area2D = _enemy_pool.pop_back() # Cast explicite
	_active_enemy_projectiles.append(projectile)
	
	if _projectile_container:
		_projectile_container.add_child(projectile)
	
	var vp_size = get_viewport().get_visible_rect().size
	projectile.activate(pos, direction, speed, damage, pattern_data, false, vp_size)

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
		
	if projectile.is_player_projectile:
		if projectile not in _player_pool:
			_player_pool.append(projectile)
	else:
		if projectile not in _enemy_pool:
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
