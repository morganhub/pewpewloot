extends Node

## FluidManager — Autoload singleton pour le système de simulation de fluide 2D.
## Charge les presets depuis DataManager, instancie FluidSimulation.tscn
## au démarrage du niveau, et fournit l'API publique emit_fluid().

const FLUID_SIM_SCENE: PackedScene = preload("res://scenes/fluid/FluidSimulation.tscn")

var _presets: Dictionary = {}

# Référence à la simulation active (une par niveau)
var _fluid_sim: Node2D = null

# Activation globale (peut être désactivé dans les options)
var enabled: bool = true

# Pools actifs (zones persistantes)
var _active_pools: Dictionary = {}
var _next_pool_id: int = 0

# --- Throttle pour les émissions trail (1 frame sur N) ---
const TRAIL_EMIT_INTERVAL: int = 3  # Émettre 1 frame toutes les N frames
var _frame_counter: int = 0

# --- Throttle explosions (max par seconde) ---
const MAX_EXPLOSIONS_PER_SEC: float = 4.0
var _explosion_budget: float = 0.0

func _ready() -> void:
	# Les presets seront chargés dès que DataManager est prêt
	# DataManager est chargé avant FluidManager dans l'ordre des autoloads
	call_deferred("_load_presets")

func _load_presets() -> void:
	_presets = DataManager.get_all_fluid_presets()
	if _presets.is_empty():
		push_warning("[FluidManager] Aucun fluid preset chargé.")



func _process(delta: float) -> void:
	if not enabled or _fluid_sim == null:
		return
	_frame_counter += 1
	_explosion_budget = minf(_explosion_budget + delta * MAX_EXPLOSIONS_PER_SEC, MAX_EXPLOSIONS_PER_SEC)
	_tick_pools(delta)

func _tick_pools(delta: float) -> void:
	var to_remove: Array[int] = []
	for pool_id in _active_pools:
		var pool: Dictionary = _active_pools[pool_id]
		pool["elapsed"] = pool["elapsed"] + delta
		var preset: Dictionary = pool["preset"]
		var pos: Vector2 = pool["position"]
		var pool_radius: float = pool["radius"]
		var base_intensity: float = float(preset.get("intensity", 0.6))
		var brush_radius: float = float(preset.get("radius", 8.0))
		var color := Color(str(preset.get("color", "#44ff22")))

		# Fading out ?
		if pool["elapsed"] >= pool["duration"]:
			pool["fading"] = true

		if pool["fading"]:
			pool["fade_elapsed"] = pool["fade_elapsed"] + delta
			var fade_t: float = clampf(pool["fade_elapsed"] / pool["fade_duration"], 0.0, 1.0)
			base_intensity *= (1.0 - fade_t)
			if fade_t >= 1.0:
				to_remove.append(pool_id)
				continue

		# Émettre des brushes pour remplir le cercle de manière dense
		if (_frame_counter % 2) != 0:
			continue
		_fluid_sim.apply_preset_params(preset)
		# Utiliser pool_radius comme taille de brush pour un cercle plein et épais
		var effective_brush_radius: float = maxf(brush_radius, pool_radius * 0.7)
		# Centre : gros brush couvrant la majorité de la zone
		_fluid_sim.queue_emitter(pos, color, effective_brush_radius, base_intensity)
		# Brushes supplémentaires pour remplir les bords
		var emit_count: int = 4
		for i in range(emit_count):
			var angle: float = randf() * TAU
			var dist: float = randf_range(pool_radius * 0.3, pool_radius * 0.8)
			var offset := Vector2(cos(angle), sin(angle)) * dist
			_fluid_sim.queue_emitter(pos + offset, color, effective_brush_radius * 0.5, base_intensity * 0.8)

	for pid in to_remove:
		_active_pools.erase(pid)

## Instancie la simulation de fluide et l'ajoute au game_layer.
## Appelé par Game.gd au démarrage d'un niveau.
func setup(game_layer: Node2D) -> void:
	cleanup()  # Nettoyer une éventuelle simulation précédente

	if not enabled:
		return

	_fluid_sim = FLUID_SIM_SCENE.instantiate()
	game_layer.add_child(_fluid_sim)

	# Appliquer les paramètres par défaut (on utilise les paramètres du premier preset
	# comme baseline, les emitters individuels surchargeront via leur preset)


## API publique : émet du fluide à une position monde.
## Appelé par les entités (Player, Enemy, Projectile, Obstacle) dans leur _process/_physics_process.
func emit_fluid(world_position: Vector2, fluid_id: String, _velocity: Vector2 = Vector2.ZERO) -> void:
	if not enabled or _fluid_sim == null:
		return

	var preset: Dictionary = _presets.get(fluid_id, {})
	if preset.is_empty():
		return

	# Throttle : les trails n'émettent que 1 frame sur TRAIL_EMIT_INTERVAL
	# Les bursts (explosions) passent toujours immédiatement
	var is_burst: bool = preset.get("burst", false)
	if not is_burst and (_frame_counter % TRAIL_EMIT_INTERVAL) != 0:
		return

	var color := Color(str(preset.get("color", "#ffffff")))
	var intensity: float = float(preset.get("intensity", 1.0))
	var radius: float = float(preset.get("radius", 15.0))
	# Appliquer les paramètres de decay/diffusion du preset au shader
	_fluid_sim.apply_preset_params(preset)

	# Burst mode : émission radiale pour explosions
	if is_burst:
		var burst_count: int = int(preset.get("burst_count", 8))
		var burst_spread: float = float(preset.get("burst_spread", 30.0))
		var color_inner := Color(str(preset.get("color_inner", preset.get("color", "#ffffff"))))
		var color_fade := Color(str(preset.get("color_fade", "#888888")))
		# Centre : couleur vive (inner)
		_fluid_sim.queue_emitter(world_position, color_inner, radius * 0.6, clampf(intensity * 1.5, 0.0, 1.0))
		# Anneau radial : couleur principale
		for i in range(burst_count):
			var angle: float = (float(i) / float(burst_count)) * TAU + randf() * 0.3
			var offset := Vector2(cos(angle), sin(angle)) * burst_spread * randf_range(0.5, 1.2)
			_fluid_sim.queue_emitter(world_position + offset, color, radius * 0.5, intensity)
		# Nuage extérieur : gris fumée
		var smoke_count: int = int(burst_count / 2.0)
		for i in range(smoke_count):
			var angle: float = randf() * TAU
			var offset := Vector2(cos(angle), sin(angle)) * burst_spread * randf_range(1.0, 2.0)
			_fluid_sim.queue_emitter(world_position + offset, color_fade, radius * 0.7, clampf(intensity * 0.4, 0.0, 1.0))
		return

	# Enqueuer le brush dans la simulation
	_fluid_sim.queue_emitter(world_position, color, radius, intensity)

## API publique : émission "burst" d'explosion à une position.
## Utilise le fluid_id de l'explosion (depuis les données missile ou game.json).
## Rate-limitée pour éviter la saturation.
func emit_explosion(world_position: Vector2, fluid_id: String = "") -> void:
	if _explosion_budget < 1.0:
		return  # Budget épuisé, on skip cette explosion
	if fluid_id == "":
		fluid_id = DataManager.get_default_explosion_fluid_id()
	if fluid_id == "":
		return
	_explosion_budget -= 1.0
	emit_fluid(world_position, fluid_id)

## API publique : démarrer une émission continue à une position fixe (pools/zones).
## Retourne un ID de pool pour pouvoir l'arrêter plus tard.
## Le pool émet `emit_count` brushes/frame dans un cercle de `pool_radius` autour de `world_position`.
func start_pool(world_position: Vector2, fluid_id: String, pool_radius: float, duration: float) -> int:
	if not enabled or _fluid_sim == null:
		return -1
	var preset: Dictionary = _presets.get(fluid_id, {})
	if preset.is_empty():
		return -1
	var pool_id := _next_pool_id
	_next_pool_id += 1
	_active_pools[pool_id] = {
		"position": world_position,
		"fluid_id": fluid_id,
		"preset": preset,
		"radius": pool_radius,
		"duration": duration,
		"elapsed": 0.0,
		"fading": false,
		"fade_elapsed": 0.0,
		"fade_duration": 0.5
	}
	return pool_id

## Arrêter un pool avant sa fin naturelle
func stop_pool(pool_id: int) -> void:
	_active_pools.erase(pool_id)

## Nettoyer la simulation (fin de niveau).
func cleanup() -> void:
	_active_pools.clear()
	_next_pool_id = 0
	if _fluid_sim and is_instance_valid(_fluid_sim):
		_fluid_sim.cleanup()
		_fluid_sim = null

## Retourne true si la simulation est active et prête.
func is_active() -> bool:
	return enabled and _fluid_sim != null and is_instance_valid(_fluid_sim)
