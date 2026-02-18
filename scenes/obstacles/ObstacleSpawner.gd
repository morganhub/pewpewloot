extends Node

## ObstacleSpawner — Génère des lignes d'obstacles selon un pattern.
## Garantit toujours un chemin valide pour le joueur.
## Patterns supportés : "slalom", "gates", "rain".
## Supporte les shapes "rectangle" (width/height) et "circle" (radius).
## Supporte le drift : chaque obstacle reçoit une direction parmi 8 cardinales.

signal obstacle_spawn_request(obstacle_data: Dictionary, positions: Array, speed: float)
signal finished

var _wave_data: Dictionary = {}
var _obstacle_data: Dictionary = {}
var _pattern: String = "slalom"
var _speed: float = 200.0
var _gap_width: float = 180.0
var _row_interval: float = 1.2
var _duration: float = 15.0

var _elapsed: float = 0.0
var _row_timer: float = 0.0
var _is_active: bool = false

# Slalom state
var _current_gap_center_x: float = 0.0
var _viewport_width: float = 0.0

# Dimensions effectives de l'obstacle (calculées à partir de shape/radius ou width/height)
var _obs_footprint_w: float = 40.0
var _obs_footprint_h: float = 40.0
var _shape_type: String = "rectangle"

# Drift config (read from wave or obstacle data)
var _drift_speed: float = 0.0
var _drift_directions: Array = []  # Allowed drift directions (strings)

const MIN_EDGE_MARGIN: float = 30.0
const SLALOM_MAX_SHIFT: float = 120.0

# Les 8 directions cardinales + intercardiales, normalisées
const DRIFT_DIR_VECTORS: Dictionary = {
	"N":  Vector2(0, -1),
	"NE": Vector2(0.7071, -0.7071),
	"E":  Vector2(1, 0),
	"SE": Vector2(0.7071, 0.7071),
	"S":  Vector2(0, 1),
	"SW": Vector2(-0.7071, 0.7071),
	"W":  Vector2(-1, 0),
	"NW": Vector2(-0.7071, -0.7071)
}

const ALL_DRIFT_DIRECTIONS: Array = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

func setup(wave_data: Dictionary) -> void:
	_wave_data = wave_data
	_pattern = str(wave_data.get("pattern", "slalom"))
	_speed = float(wave_data.get("speed", 200))
	_gap_width = float(wave_data.get("gap_width", 180))
	_row_interval = float(wave_data.get("row_interval", 1.2))
	_duration = float(wave_data.get("duration", 15.0))
	
	# Charger les données de l'obstacle depuis DataManager
	var obstacle_id: String = str(wave_data.get("obstacle_id", ""))
	_obstacle_data = DataManager.get_obstacle(obstacle_id)
	if _obstacle_data.is_empty():
		push_warning("[ObstacleSpawner] Unknown obstacle_id: " + obstacle_id)
		return
	
	# Calculer l'empreinte de l'obstacle (bounding box)
	_shape_type = str(_obstacle_data.get("shape", "rectangle"))
	if _shape_type == "circle":
		var radius: float = float(_obstacle_data.get("radius", 20))
		_obs_footprint_w = radius * 2.0
		_obs_footprint_h = radius * 2.0
	else:
		_obs_footprint_w = float(_obstacle_data.get("width", 40))
		_obs_footprint_h = float(_obstacle_data.get("height", 40))
	
	# Drift config : wave override > obstacle data > 0
	_drift_speed = float(wave_data.get("drift_speed", _obstacle_data.get("drift_speed", 0.0)))
	
	# Directions autorisées (wave override, sinon toutes les 8)
	var dirs_raw: Variant = wave_data.get("drift_directions", [])
	if dirs_raw is Array and (dirs_raw as Array).size() > 0:
		_drift_directions = dirs_raw as Array
	else:
		_drift_directions = ALL_DRIFT_DIRECTIONS.duplicate()
	
	_viewport_width = get_viewport().get_visible_rect().size.x
	_current_gap_center_x = _viewport_width / 2.0
	
	_elapsed = 0.0
	_row_timer = 0.0
	_is_active = true
	
	print("[ObstacleSpawner] Started: pattern=", _pattern, " obstacle=", obstacle_id,
		" shape=", _shape_type, " footprint=", Vector2(_obs_footprint_w, _obs_footprint_h),
		" speed=", _speed, " gap=", _gap_width, " drift=", _drift_speed)

func stop() -> void:
	_is_active = false

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_elapsed += delta
	_row_timer += delta
	
	# Vérifier si la durée est écoulée
	if _elapsed >= _duration:
		_is_active = false
		finished.emit()
		return
	
	# Spawn une ligne à chaque intervalle
	if _row_timer >= _row_interval:
		_row_timer -= _row_interval
		_spawn_row()

func _spawn_row() -> void:
	var positions: Array = []
	
	match _pattern:
		"slalom":
			positions = _generate_slalom_positions()
		"gates":
			positions = _generate_gates_positions()
		"rain":
			positions = _generate_rain_positions()
		_:
			push_warning("[ObstacleSpawner] Unknown pattern: " + _pattern)
			positions = _generate_slalom_positions()
	
	if not positions.is_empty():
		# Injecter les infos de drift dans les données de l'obstacle
		var enriched_data: Dictionary = _obstacle_data.duplicate()
		enriched_data["_drift_speed"] = _drift_speed
		# Assigner une direction aléatoire à chaque obstacle via un array
		var drift_dirs_for_row: Array = []
		for _i in range(positions.size()):
			if _drift_speed > 0.0 and _drift_directions.size() > 0:
				var dir_name: String = _drift_directions[randi() % _drift_directions.size()]
				drift_dirs_for_row.append(dir_name)
			else:
				drift_dirs_for_row.append("")
		enriched_data["_drift_directions_per_obstacle"] = drift_dirs_for_row
		obstacle_spawn_request.emit(enriched_data, positions, _speed)


# =============================================================================
# PATTERN : SLALOM (ZigZag)
# =============================================================================
# Garde en mémoire la position du trou précédent.
# Le décale aléatoirement, puis spawn un obstacle à gauche et un à droite.

func _generate_slalom_positions() -> Array:
	var half_gap := _gap_width / 2.0
	var obs_width := _obs_footprint_w
	
	# Décalage aléatoire borné
	var shift := randf_range(-SLALOM_MAX_SHIFT, SLALOM_MAX_SHIFT)
	_current_gap_center_x += shift
	
	# Clamper pour que le gap reste dans l'écran
	var min_center := half_gap + MIN_EDGE_MARGIN
	var max_center := _viewport_width - half_gap - MIN_EDGE_MARGIN
	_current_gap_center_x = clampf(_current_gap_center_x, min_center, max_center)
	
	var positions: Array = []
	var spawn_y: float = -50.0
	
	# Obstacle à gauche du trou
	var left_edge := _current_gap_center_x - half_gap
	if left_edge > obs_width / 2.0 + MIN_EDGE_MARGIN:
		var left_x := left_edge / 2.0 # Centre de l'obstacle gauche
		positions.append(Vector2(left_x, spawn_y))
	
	# Obstacle à droite du trou
	var right_edge := _current_gap_center_x + half_gap
	var right_space := _viewport_width - right_edge
	if right_space > obs_width / 2.0 + MIN_EDGE_MARGIN:
		var right_x := right_edge + right_space / 2.0
		positions.append(Vector2(right_x, spawn_y))
	
	return positions


# =============================================================================
# PATTERN : GATES (Portes)
# =============================================================================
# Position X aléatoire pour le trou.
# Spawn des murs couvrant tout l'écran sauf ce trou.

func _generate_gates_positions() -> Array:
	var half_gap := _gap_width / 2.0
	var obs_height := _obs_footprint_h
	
	# Position du trou aléatoire
	var min_center := half_gap + MIN_EDGE_MARGIN
	var max_center := _viewport_width - half_gap - MIN_EDGE_MARGIN
	var gap_center := randf_range(min_center, max_center)
	
	var positions: Array = []
	var spawn_y: float = -obs_height
	
	# Mur à gauche : de 0 à gap_center - half_gap
	var left_wall_right := gap_center - half_gap
	if left_wall_right > MIN_EDGE_MARGIN:
		var left_wall_center_x := left_wall_right / 2.0
		# On override la width dans les position data (le spawner utilisera ça)
		positions.append(Vector2(left_wall_center_x, spawn_y))
	
	# Mur à droite : de gap_center + half_gap à viewport_width
	var right_wall_left := gap_center + half_gap
	var right_wall_space := _viewport_width - right_wall_left
	if right_wall_space > MIN_EDGE_MARGIN:
		var right_wall_center_x := right_wall_left + right_wall_space / 2.0
		positions.append(Vector2(right_wall_center_x, spawn_y))
	
	return positions


# =============================================================================
# PATTERN : RAIN (Pluie)
# =============================================================================
# Spawn des obstacles à des positions aléatoires.
# Pour les cercles (planètes), étale sur un large Y en plus du X.
# Vérifie algorithmiquement qu'il existe un espace suffisant pour le joueur.

func _generate_rain_positions() -> Array:
	var obs_width := _obs_footprint_w
	var obs_height := _obs_footprint_h
	var base_spawn_y: float = -(obs_height / 2.0) - 10.0
	
	# Y spread : les cercles (planètes) occupent beaucoup de place,
	# on les étale sur un large Y pour éviter un mur infranchissable.
	var y_spread: float = 0.0
	if _shape_type == "circle":
		y_spread = obs_height * 2.0  # étalement vertical = 2x la hauteur
	
	# Nombre d'obstacles par ligne (proportionnel à la largeur de l'écran)
	var max_obstacles := int((_viewport_width - _gap_width) / (obs_width + 20.0))
	max_obstacles = clampi(max_obstacles, 1, 8)
	var count := randi_range(1, max_obstacles)
	
	# Générer des positions 2D candidates
	var candidates: Array[Vector2] = []
	var attempts := 0
	
	while candidates.size() < count and attempts < 50:
		attempts += 1
		var x := randf_range(obs_width / 2.0 + MIN_EDGE_MARGIN,
			_viewport_width - obs_width / 2.0 - MIN_EDGE_MARGIN)
		var y := base_spawn_y - randf_range(0.0, y_spread)
		
		# Vérifier espacement 2D (bounding box) avec les autres candidats
		var too_close := false
		for existing in candidates:
			var dx := absf(x - existing.x)
			var dy := absf(y - existing.y)
			# Les obstacles ne doivent pas se chevaucher + marge de passage
			if dx < obs_width + _gap_width * 0.3 and dy < obs_height + 10.0:
				too_close = true
				break
		
		if not too_close:
			candidates.append(Vector2(x, y))
	
	# Vérifier qu'un gap X suffisant existe (projection conservative sur X)
	var x_positions: Array[float] = []
	for c in candidates:
		x_positions.append(c.x)
	
	if not _validate_rain_gap(x_positions, obs_width):
		# Retirer un obstacle aléatoire pour ouvrir un passage
		if candidates.size() > 1:
			candidates.remove_at(randi() % candidates.size())
	
	# Retourner directement les Vector2
	var positions: Array = []
	for c in candidates:
		positions.append(c)
	
	return positions

func _validate_rain_gap(x_positions: Array[float], obs_width: float) -> bool:
	"""Vérifie qu'il existe au moins un espace >= gap_width entre les obstacles ou les bords."""
	if x_positions.is_empty():
		return true
	
	# Trier par X
	var sorted_x := x_positions.duplicate()
	sorted_x.sort()
	
	var half_obs := obs_width / 2.0
	
	# Vérifier le gap entre le bord gauche et le premier obstacle
	var first_left_edge: float = float(sorted_x[0]) - half_obs
	if first_left_edge >= _gap_width:
		return true
	
	# Vérifier les gaps entre obstacles consécutifs
	for i in range(sorted_x.size() - 1):
		var right_of_current: float = float(sorted_x[i]) + half_obs
		var left_of_next: float = float(sorted_x[i + 1]) - half_obs
		var gap: float = left_of_next - right_of_current
		if gap >= _gap_width:
			return true
	
	# Vérifier le gap entre le dernier obstacle et le bord droit
	var last_right_edge: float = float(sorted_x.back()) + half_obs
	var right_gap: float = _viewport_width - last_right_edge
	if right_gap >= _gap_width:
		return true
	
	return false
