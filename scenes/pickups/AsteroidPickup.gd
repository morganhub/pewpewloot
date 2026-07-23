extends Node2D
## Pickup tombant des vagues `asteroid_split` (Lot 1 — plan wave_types_improvements.md).
## Calqué sur `scenes/pickups/BonusCrystal.gd` : chute verticale + aimantation de
## proximité vers le vaisseau + collecte par distance. 100 % code (pas de .tscn) :
## il construit son Sprite2D enfant (ou un cercle de secours si l'asset manque).
## L'effet est appliqué côté Game via le signal `collected(pickup_id)`.

signal collected(pickup_id: String)
signal expired

# Cache statique partagé (même pattern que BonusCrystal / Enemy / LootDrop).
static var _resource_cache: Dictionary = {}
static var _missing_paths: Dictionary = {}

static func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _resource_cache.has(path):
		return _resource_cache[path] as Resource
	if _missing_paths.has(path):
		return null
	if not ResourceLoader.exists(path):
		_missing_paths[path] = true
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res != null:
		_resource_cache[path] = res
	else:
		_missing_paths[path] = true
	return res

var pickup_id: String = ""
var _player: Node2D = null
var _fall_speed: float = 300.0
var _magnet_radius: float = 44.0
var _magnet_speed: float = 470.0
var _size_px: float = 48.0
var _ttl: float = 9.0
var _age: float = 0.0
var _float_freq: float = 4.0
var _float_amplitude: float = 6.0
var _fallback_color: Color = Color(1, 1, 1, 0.9)
var _use_fallback: bool = false

func setup(data: Dictionary, player_ref: Node2D) -> void:
	pickup_id = str(data.get("id", ""))
	_player = player_ref
	_fall_speed = maxf(40.0, float(data.get("fall_speed_px_sec", 300.0)))
	_magnet_radius = maxf(8.0, float(data.get("magnet_radius_px", 44.0)))
	_magnet_speed = maxf(10.0, float(data.get("magnet_speed_px_sec", 470.0)))
	_size_px = maxf(8.0, float(data.get("size_px", 48.0)))
	_ttl = maxf(0.5, float(data.get("ttl_sec", 9.0)))
	_fallback_color = _parse_color(str(data.get("tint", "#FFFFFF")))
	_build_visual(str(data.get("asset", "")))

func _parse_color(hex: String) -> Color:
	var s: String = hex.strip_edges()
	if s == "" or not s.begins_with("#"):
		return Color(1, 1, 1, 0.9)
	return Color.from_string(s, Color(1, 1, 1, 0.9))

func _build_visual(asset_path: String) -> void:
	var res: Resource = _load_cached_resource(asset_path)
	if res is Texture2D:
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = res as Texture2D
		var tex_size: Vector2 = (res as Texture2D).get_size()
		var max_dim: float = maxf(tex_size.x, tex_size.y)
		if max_dim > 0.0:
			spr.scale = Vector2.ONE * (_size_px / max_dim)
		add_child(spr)
	else:
		# Cercle de secours dessiné dans _draw (asset introuvable).
		_use_fallback = true
		queue_redraw()

func _draw() -> void:
	if _use_fallback:
		draw_circle(Vector2.ZERO, _size_px * 0.5, _fallback_color)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _ttl:
		expired.emit()
		queue_free()
		return

	# Chute + léger balancement horizontal (mêmes constantes que BonusCrystal).
	global_position.y += _fall_speed * delta
	global_position.x += sin(_age * _float_freq) * _float_amplitude * delta

	# Nettoyage hors écran (bas).
	var vh: float = get_viewport_rect().size.y
	if global_position.y > vh + 120.0:
		expired.emit()
		queue_free()
		return

	if _player and is_instance_valid(_player):
		var dist: float = global_position.distance_to(_player.global_position)
		if dist <= _magnet_radius:
			collected.emit(pickup_id)
			queue_free()
			return
		var to_player: Vector2 = _player.global_position - global_position
		if dist <= _magnet_radius * 6.0 and to_player != Vector2.ZERO:
			global_position += to_player.normalized() * _magnet_speed * delta
