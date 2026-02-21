extends Area2D

## SuppressorShield
## Wrapper 2D autour du shield 3D Nojoule:
## - hitbox/collision des projectiles joueurs
## - HP du bouclier
## - lifecycle (impact/collapse)

signal shield_broken

const DEFAULT_SHIELD_SCENE := "res://addons/nojoule-energy-shield/shield_sphere.tscn"
const COLLAPSE_DURATION_SEC := 1.0
const BASE_VISUAL_DIAMETER := 140.0
const STRONG_RESOURCE_CACHE_MAX: int = 64
static var _strong_resource_cache: Dictionary = {} # path -> Resource

@export var max_hp: int = 800
var current_hp: int = 800

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual_container: Node2D = $VisualContainer

var _shield_scene_path: String = DEFAULT_SHIELD_SCENE
var _shield_diameter: float = BASE_VISUAL_DIAMETER
var _deflect_sfx_path: String = ""
var _color_tint: String = "#0088FF"

var _shield_visual: Node = null
var _is_collapsing: bool = false
var _is_active: bool = true

func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_apply_collision_radius(_shield_diameter * 0.5)

func setup(config: Dictionary) -> void:
	if not is_node_ready():
		await ready
	
	max_hp = int(config.get("shield_hp", max_hp))
	current_hp = max_hp
	_shield_scene_path = str(config.get("shield_scene_path", DEFAULT_SHIELD_SCENE))
	_shield_diameter = maxf(20.0, float(config.get("shield_diameter", BASE_VISUAL_DIAMETER)))
	_deflect_sfx_path = str(config.get("deflect_sfx", ""))
	_color_tint = str(config.get("color_tint", "#0088FF"))
	_is_collapsing = false
	_is_active = true
	monitoring = true
	monitorable = true
	_apply_collision_radius(_shield_diameter * 0.5)
	_build_visual()

func is_active() -> bool:
	return _is_active and not _is_collapsing and current_hp > 0

func take_damage(amount: int, hit_pos: Vector2) -> void:
	if amount <= 0 or not is_active():
		return
	
	current_hp = maxi(0, current_hp - amount)
	_play_deflect_sfx()
	_emit_visual_impact(hit_pos)
	
	if current_hp <= 0:
		_break_shield()

func _on_area_entered(area: Area2D) -> void:
	if not is_active():
		return
	if not bool(area.get("is_player_projectile")):
		return
	
	var dmg := 0
	var dmg_var: Variant = area.get("damage")
	if dmg_var != null:
		dmg = int(dmg_var)
	take_damage(maxi(1, dmg), area.global_position)
	if area.has_method("deactivate"):
		area.call("deactivate", "hit_suppressor_shield")

func _apply_collision_radius(radius: float) -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle

func _build_visual() -> void:
	for child in visual_container.get_children():
		child.queue_free()
	_shield_visual = null
	
	if not ResourceLoader.exists(_shield_scene_path):
		push_warning("[SuppressorShield] Missing shield scene: " + _shield_scene_path)
		return
	
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "ShieldViewportContainer"
	viewport_container.stretch = true
	viewport_container.custom_minimum_size = Vector2(_shield_diameter, _shield_diameter)
	viewport_container.size = Vector2(_shield_diameter, _shield_diameter)
	viewport_container.position = Vector2(-_shield_diameter * 0.5, -_shield_diameter * 0.5)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_container.add_child(viewport_container)
	
	var viewport := SubViewport.new()
	viewport.name = "ShieldSubViewport"
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(int(round(_shield_diameter)), int(round(_shield_diameter)))
	viewport_container.add_child(viewport)
	
	var camera := Camera3D.new()
	camera.name = "ShieldCamera"
	camera.position = Vector3(0.0, 0.0, 2.0)
	camera.current = true
	viewport.add_child(camera)
	
	var shield_res: Resource = _load_cached_resource(_shield_scene_path)
	var shield_scene: PackedScene = shield_res as PackedScene
	if shield_scene == null:
		return
	
	var shield_instance: Node = shield_scene.instantiate()
	if shield_instance == null:
		return
	
	viewport.add_child(shield_instance)
	_shield_visual = shield_instance
	
	if _shield_visual.has_method("update_material"):
		_shield_visual.call("update_material", "_color_shield", Color(_color_tint))
	if _shield_visual.has_method("generate"):
		_shield_visual.call("generate")

func _emit_visual_impact(hit_pos: Vector2) -> void:
	if _shield_visual == null:
		return
	if not _shield_visual.has_method("impact"):
		return
	
	var rel_pos := hit_pos - global_position
	var scale_factor := 2.0 / maxf(1.0, _shield_diameter)
	var impact_3d := Vector3(rel_pos.x * scale_factor, -rel_pos.y * scale_factor, 0.5)
	_shield_visual.call("impact", impact_3d)

func _break_shield() -> void:
	if _is_collapsing:
		return
	_is_collapsing = true
	_is_active = false
	monitoring = false
	monitorable = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	shield_broken.emit()
	
	if _shield_visual and _shield_visual.has_method("collapse"):
		_shield_visual.call("collapse")
	
	await get_tree().create_timer(COLLAPSE_DURATION_SEC).timeout
	queue_free()

func _play_deflect_sfx() -> void:
	if _deflect_sfx_path == "":
		return
	if not ResourceLoader.exists(_deflect_sfx_path):
		return
	AudioManager.play_sfx(_deflect_sfx_path, 0.05)

func _load_cached_resource(path: String) -> Resource:
	if path == "":
		return null
	if _strong_resource_cache.has(path):
		var cached: Variant = _strong_resource_cache[path]
		if cached is Resource:
			return cached as Resource
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource != null:
		if _strong_resource_cache.size() >= STRONG_RESOURCE_CACHE_MAX:
			_strong_resource_cache.clear()
		_strong_resource_cache[path] = resource
	return resource
