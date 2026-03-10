extends Control
class_name SphereView
## Sphère 3D texturée qui tourne lentement sur l'axe pôle nord / pôle sud (Y).
## Utilisée pour World Select et Level Select comme élément central des cartes.
## Taille et vitesse de rotation lues depuis game.json → world_select.sphere

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _sphere_pivot: Node3D
var _sphere_mesh: MeshInstance3D
var _rotation_radians: float = 0.0
var _rotation_speed: float = 0.12
var _sphere_size: float = 1.0
var _light_energy: float = 0.5
var _uv_scale: float = 10.0
var _uv_offset: Vector3 = Vector3.ZERO
var _camera_distance: float = 0.0
var _camera_fov: float = 75.0
var _camera_offset: Vector2 = Vector2.ZERO
var _square_scale: float = 1.0
var _texture_rotation: float = 90.0
var _pending_texture: Texture2D = null
var _pending_texture_path: String = ""
var _pending_texture_paths: Array = []  # 6 paths for six-sector shader (world = 6 levels)
var _texture_border_width: float = 0.0
var _texture_border_color: Color = Color(0.1, 0.1, 0.18)


func _ready() -> void:
	_load_sphere_config()
	_build_3d_scene()
	# Appliquer la texture en différé pour éviter que le dernier viewport initialisé écrase les autres.
	call_deferred("_apply_pending_texture")
	_update_viewport_size()


func _load_sphere_config() -> void:
	var cfg: Dictionary = DataManager.get_game_config().get("world_select", {}).get("sphere", {})
	_rotation_speed = clampf(float(cfg.get("rotation_speed", 0.12)), 0.0, 3.0)
	# radius = rayon 3D de la planète (SphereMesh par défaut a radius 1, donc scale = radius). Fallback sur "size" pour rétrocompat.
	_sphere_size = clampf(float(cfg.get("radius", cfg.get("size", 1.0))), 0.2, 5.0)
	_light_energy = clampf(float(cfg.get("light_energy", 0.5)), 0.0, 3.0)
	_uv_scale = clampf(float(cfg.get("uv_scale", 10.0)), 0.5, 20.0)
	# Rotation de la texture en degrés (ex. 90 pour pivoter une image verticale).
	_texture_rotation = float(cfg.get("texture_rotation", 90.0))
	# Chevauchement UV : > 1 = motifs se recouvrent (réduit le gap). Plage 0.95–1.15 (0.508 était ignoré car clampé à 1.0 avant).
	var overlap: float = clampf(float(cfg.get("uv_overlap", 1.02)), 0.95, 1.15)
	_uv_scale *= overlap
	# Décalage UV (u, v en 0–1) : décale la texture pour déplacer la jointure de la sphère ou éviter le sampling pile sur les bords.
	var ou: float = clampf(float(cfg.get("uv_offset_u", 0.001)), -1.0, 1.0)
	var ov: float = clampf(float(cfg.get("uv_offset_v", 0.001)), -1.0, 1.0)
	_uv_offset = Vector3(ou, ov, 0.0)
	# Caméra : distance (z), FOV vertical en degrés, offset xy. Si camera_distance non défini, calcul auto depuis radius.
	var auto_distance: float = _sphere_size * 1.4 + 0.3
	_camera_distance = float(cfg.get("camera_distance", auto_distance))
	if _camera_distance <= 0.0:
		_camera_distance = auto_distance
	_camera_fov = clampf(float(cfg.get("camera_fov", 75.0)), 10.0, 120.0)
	var ox: float = float(cfg.get("camera_offset_x", 0.0))
	var oy: float = float(cfg.get("camera_offset_y", 0.0))
	_camera_offset = Vector2(ox, oy)
	# Taille du carré de la vue 3D : 1.0 = max (min(largeur, hauteur)), < 1 = plus petit, > 1 = carré plus grand (zoom, peut être coupé par le parent).
	_square_scale = clampf(float(cfg.get("square_scale", 1.0)), 0.1, 3.0)
	# Bande de bordure entre les 6 tranches : largeur en part 0-1 de la largeur d'une tranche (ex. 0.005 = fin), couleur hex.
	_texture_border_width = clampf(float(cfg.get("texture_border_width", 0.0)), 0.0, 0.5)
	_texture_border_color = Color.from_string(str(cfg.get("texture_border_color", "#1a1a2e")), Color(0.1, 0.1, 0.18))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_viewport_size()


func _process(delta: float) -> void:
	if _sphere_pivot == null:
		return
	_rotation_radians += delta * _rotation_speed
	_sphere_pivot.rotation.y = _rotation_radians


func _build_3d_scene() -> void:
	# Ombre portée sous la planète (dessinée en premier = derrière).
	var shadow_script: GDScript = load("res://scenes/components/PlanetShadow.gd") as GDScript
	if shadow_script != null:
		var shadow := Sprite2D.new()
		shadow.name = "PlanetShadow"
		shadow.set_script(shadow_script)
		add_child(shadow)
		shadow.set_meta("_sphere_view_shadow", true)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "SubViewportContainer"
	_viewport_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.name = "SubViewport_%s" % get_instance_id()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = true
	_viewport_container.add_child(_viewport)

	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = Vector3(_camera_offset.x, _camera_offset.y, _camera_distance)
	_camera.fov = _camera_fov
	_world.add_child(_camera)
	_camera.look_at(Vector3(_camera_offset.x, _camera_offset.y, 0.0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy = _light_energy
	_world.add_child(light)

	var sphere_node := Node3D.new()
	sphere_node.name = "SpherePivot"
	sphere_node.scale = Vector3(_sphere_size, _sphere_size, _sphere_size)
	_world.add_child(sphere_node)
	_sphere_pivot = sphere_node

	_sphere_mesh = MeshInstance3D.new()
	_sphere_mesh.name = "Sphere"
	_sphere_mesh.mesh = SphereMesh.new()
	# Rotation de la texture : pivoter le mesh sur l'axe Z (face caméra) pour que la texture verticale s'affiche en paysage.
	_sphere_mesh.rotation_degrees = Vector3(0.0, 0.0, _texture_rotation)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.uv1_scale = Vector3(_uv_scale, _uv_scale, 1.0)
	mat.uv1_offset = _uv_offset
	_sphere_mesh.material_override = mat
	_sphere_pivot.add_child(_sphere_mesh)


func _update_viewport_size() -> void:
	if _viewport == null:
		return
	var sz := size
	if sz.x < 1:
		sz.x = 1
	if sz.y < 1:
		sz.y = 1
	# Vue 3D en carré (côté = min(largeur, hauteur) * square_scale) centrée pour éviter le crop en hauteur.
	var side: float = minf(sz.x, sz.y) * _square_scale
	var x0: float = (sz.x - side) * 0.5
	var y0: float = (sz.y - side) * 0.5
	_viewport_container.position = Vector2(x0, y0)
	_viewport_container.size = Vector2(side, side)
	# Positionner et dimensionner l'ombre portée sous la planète.
	var shadow: Sprite2D = _get_shadow_child()
	if shadow != null and shadow.has_method("update_shadow"):
		shadow.update_shadow(side * 0.48, Vector2(x0 + side * 0.5, y0 + side * 0.5))


func _get_shadow_child() -> Sprite2D:
	for c in get_children():
		if c is Sprite2D and c.get_meta("_sphere_view_shadow", false):
			return c as Sprite2D
	return null


## Charge une texture et en crée une copie unique (nouvelle ImageTexture) pour éviter tout partage GPU entre sphères.
## Utilise CACHE_MODE_IGNORE pour ne pas réutiliser une ressource partagée.
func _load_texture_unique(path: String) -> Texture2D:
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is Texture2D:
		return _texture_to_unique(res as Texture2D)
	return null


## Crée une ImageTexture indépendante à partir d'une Texture2D (copie des pixels) pour éviter le partage de RID.
func _texture_to_unique(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _apply_six_sector_textures(paths: Array) -> void:
	if _sphere_mesh == null or paths.size() < 6:
		return
	var shader_res: Shader = load("res://scenes/shaders/world_sphere_six_sectors.gdshader") as Shader
	if shader_res == null:
		return
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader_res
	shader_mat.set_shader_parameter("uv_scale", _uv_scale)
	shader_mat.set_shader_parameter("uv_offset_u", _uv_offset.x)
	shader_mat.set_shader_parameter("uv_offset_v", _uv_offset.y)
	shader_mat.set_shader_parameter("texture_border_width", _texture_border_width)
	shader_mat.set_shader_parameter("texture_border_color", Vector3(_texture_border_color.r, _texture_border_color.g, _texture_border_color.b))
	var default_tex: Texture2D = _get_default_placeholder_texture()
	var names: Array[String] = ["tex1", "tex2", "tex3", "tex4", "tex5", "tex6"]
	for i in 6:
		var path: String = str(paths[i]).strip_edges()
		var tex: Texture2D = null
		if path != "" and ResourceLoader.exists(path):
			tex = _load_texture_unique(path)
		if tex == null:
			tex = default_tex
		shader_mat.set_shader_parameter(names[i], tex)
	_sphere_mesh.material_override = shader_mat


func _get_default_placeholder_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color(0.22, 0.22, 0.28))
	return ImageTexture.create_from_image(img)


func _apply_pending_texture() -> void:
	if _sphere_mesh == null:
		return
	if _pending_texture_paths.size() >= 6:
		var paths: Array = _pending_texture_paths.duplicate()
		_pending_texture_paths.clear()
		_pending_texture_path = ""
		_pending_texture = null
		_apply_six_sector_textures(paths)
		return
	var mat: Material = _sphere_mesh.material_override
	if mat is not StandardMaterial3D:
		_pending_texture = null
		_pending_texture_path = ""
		_pending_texture_paths.clear()
		return
	if _pending_texture_path != "":
		var path := _pending_texture_path
		_pending_texture_path = ""
		_pending_texture_paths.clear()
		push_warning("[SphereView] applying texture path=%s (instance_id=%s)" % [path, get_instance_id()])
		if path.is_empty() or not ResourceLoader.exists(path):
			return
		var tex: Texture2D = _load_texture_unique(path)
		if tex != null:
			(mat as StandardMaterial3D).albedo_texture = tex
		return
	if _pending_texture != null:
		var tex: Texture2D = _texture_to_unique(_pending_texture)
		_pending_texture = null
		_pending_texture_paths.clear()
		if tex != null:
			(mat as StandardMaterial3D).albedo_texture = tex


## Définit la texture de la sphère à partir d'un chemin res://
func set_texture_path(path: String) -> void:
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		return
	_pending_texture_paths.clear()
	if _sphere_mesh == null:
		_pending_texture_path = str(path)
		_pending_texture = null
		_pending_texture_paths.clear()
		push_warning("[SphereView] stored pending path=%s (instance_id=%s)" % [_pending_texture_path, get_instance_id()])
		return
	var unique_tex: Texture2D = _load_texture_unique(path)
	if unique_tex != null:
		var mat: Material = _sphere_mesh.material_override
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_texture = unique_tex


## Définit les 6 textures de la sphère (une par secteur horizontal, ex. les 6 levels du world).
## paths: Array de 6 chemins res:// (levels 0..5, boss inclus). Si moins de 6, ignoré.
func set_texture_paths(paths: Array) -> void:
	if paths.size() < 6:
		return
	_pending_texture_path = ""
	_pending_texture = null
	var six_paths: Array = []
	for i in 6:
		six_paths.append(str(paths[i]).strip_edges())
	if _sphere_mesh == null:
		_pending_texture_paths = six_paths
		return
	_apply_six_sector_textures(six_paths)


## Définit la texture de la sphère (Texture2D). Une copie unique est utilisée pour éviter le partage GPU.
func set_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	if _sphere_mesh == null:
		_pending_texture = tex
		return
	var mat: Material = _sphere_mesh.material_override
	if mat is StandardMaterial3D:
		var unique_tex: Texture2D = _texture_to_unique(tex)
		if unique_tex != null:
			(mat as StandardMaterial3D).albedo_texture = unique_tex


func get_texture() -> Texture2D:
	if _sphere_mesh == null:
		return null
	var mat: Material = _sphere_mesh.material_override
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	return null
