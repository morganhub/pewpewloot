extends Node2D

## FluidSimulation — Simulation de fluide 2D Eulerienne sur GPU (mobile).
## Architecture :
##   - 1 EmitterViewport (CLEAR_MODE_ALWAYS) : reçoit les cercles d'emission, clearé chaque frame
##   - 2 SimViewports A/B (CLEAR_MODE_NEVER, ping-pong) : chaque frame, un lit l'autre
##     + la texture emitter, et écrit le résultat (advection + diffusion + decay)
##   - 1 RenderSprite : upscale le résultat en blend additif au-dessus de la scène

# --- Résolution de simulation (basse résolution pour performance mobile) ---
const SIM_WIDTH: int = 256
const SIM_HEIGHT: int = 512

# --- Limite d'emitters par frame pour la performance ---
const MAX_EMITTERS_PER_FRAME: int = 30

# --- Références aux noeuds (construits en code) ---
var _emitter_viewport: SubViewport = null
var _emitter_canvas: Node2D = null

var _viewport_a: SubViewport = null
var _viewport_b: SubViewport = null
var _sim_sprite_a: Sprite2D = null
var _sim_sprite_b: Sprite2D = null
var _render_sprite: Sprite2D = null

# --- Matériaux shader ---
var _sim_material_a: ShaderMaterial = null
var _sim_material_b: ShaderMaterial = null
var _render_material: ShaderMaterial = null

# --- État ping-pong ---
var _ping: bool = true  # true = écrire dans A (lire B), false = inverse
var _global_time: float = 0.0

# --- File d'attente d'emitters ---
var _emitter_queue: Array = []

# --- Taille du viewport de jeu (pour convertir world → UV) ---
var _game_viewport_size: Vector2 = Vector2(720, 1280)

# --- EmitterBrush : noeud interne pour dessiner les cercles ---
class EmitterBrush extends Node2D:
	var brushes: Array = []

	func _draw() -> void:
		for b in brushes:
			draw_circle(b.pos, b.radius, b.color)
		brushes.clear()

func _ready() -> void:
	_game_viewport_size = get_viewport().get_visible_rect().size
	_build_simulation_tree()

func _build_simulation_tree() -> void:
	var sim_shader: Shader = load("res://scenes/fluid/fluid_sim.gdshader")
	var render_shader: Shader = load("res://scenes/fluid/fluid_render.gdshader")

	# --- Emitter Viewport (clearé chaque frame, cercles frais uniquement) ---
	_emitter_viewport = SubViewport.new()
	_emitter_viewport.name = "EmitterViewport"
	_emitter_viewport.size = Vector2i(SIM_WIDTH, SIM_HEIGHT)
	_emitter_viewport.transparent_bg = true
	_emitter_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_emitter_viewport.world_2d = World2D.new()
	_emitter_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_emitter_viewport)

	_emitter_canvas = EmitterBrush.new()
	_emitter_canvas.name = "EmitterCanvas"
	_emitter_viewport.add_child(_emitter_canvas)

	# --- Sim Viewport A (ping-pong, ne clear jamais → persiste) ---
	_viewport_a = SubViewport.new()
	_viewport_a.name = "SimViewportA"
	_viewport_a.size = Vector2i(SIM_WIDTH, SIM_HEIGHT)
	_viewport_a.transparent_bg = true
	_viewport_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_a.world_2d = World2D.new()
	_viewport_a.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_viewport_a)

	_sim_sprite_a = Sprite2D.new()
	_sim_sprite_a.name = "SimSpriteA"
	_sim_sprite_a.centered = false
	_sim_material_a = ShaderMaterial.new()
	_sim_material_a.shader = sim_shader
	_sim_sprite_a.material = _sim_material_a
	_viewport_a.add_child(_sim_sprite_a)

	# --- Sim Viewport B (ping-pong, ne clear jamais → persiste) ---
	_viewport_b = SubViewport.new()
	_viewport_b.name = "SimViewportB"
	_viewport_b.size = Vector2i(SIM_WIDTH, SIM_HEIGHT)
	_viewport_b.transparent_bg = true
	_viewport_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_b.world_2d = World2D.new()
	_viewport_b.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_viewport_b)

	_sim_sprite_b = Sprite2D.new()
	_sim_sprite_b.name = "SimSpriteB"
	_sim_sprite_b.centered = false
	_sim_material_b = ShaderMaterial.new()
	_sim_material_b.shader = sim_shader
	_sim_sprite_b.material = _sim_material_b
	_viewport_b.add_child(_sim_sprite_b)

	# --- Connecter les textures ---
	await get_tree().process_frame

	var tex_a := _viewport_a.get_texture()
	var tex_b := _viewport_b.get_texture()
	var tex_emitter := _emitter_viewport.get_texture()

	# Sprite A lit B comme previous_frame (et emitter comme source d'émission)
	_sim_sprite_a.texture = tex_b
	_sim_material_a.set_shader_parameter("previous_frame", tex_b)
	_sim_material_a.set_shader_parameter("emitter_texture", tex_emitter)

	# Sprite B lit A comme previous_frame (et emitter comme source d'émission)
	_sim_sprite_b.texture = tex_a
	_sim_material_b.set_shader_parameter("previous_frame", tex_a)
	_sim_material_b.set_shader_parameter("emitter_texture", tex_emitter)

	# --- Sprite de rendu final ---
	_render_sprite = Sprite2D.new()
	_render_sprite.name = "FluidRenderSprite"
	_render_sprite.centered = false
	_render_sprite.z_index = 5
	_render_sprite.position = Vector2.ZERO

	_render_material = ShaderMaterial.new()
	_render_material.shader = render_shader
	_render_sprite.material = _render_material

	_render_sprite.texture = tex_a
	_render_sprite.scale = _game_viewport_size / Vector2(SIM_WIDTH, SIM_HEIGHT)

	add_child(_render_sprite)

func _process(delta: float) -> void:
	_global_time += delta

	# Traiter la file d'emitters (max par frame)
	var emitters_this_frame: Array = _emitter_queue.slice(0, MAX_EMITTERS_PER_FRAME)
	_emitter_queue = _emitter_queue.slice(MAX_EMITTERS_PER_FRAME)

	# Dessiner les emitters dans le viewport dédié (clearé automatiquement chaque frame)
	if _emitter_canvas:
		_emitter_canvas.brushes.clear()
		for e in emitters_this_frame:
			var sim_pos: Vector2 = _world_to_sim(e.pos)
			var sim_radius: float = e.radius * (float(SIM_WIDTH) / _game_viewport_size.x)
			_emitter_canvas.brushes.append({
				"pos": sim_pos,
				"color": e.color,
				"radius": maxf(sim_radius, 1.0)
			})
		_emitter_canvas.queue_redraw()

	# Ping-pong : activer UNIQUEMENT le viewport d'écriture pour cette frame
	if _ping:
		_viewport_a.render_target_update_mode = SubViewport.UPDATE_ONCE
		_viewport_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_viewport_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport_b.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Mettre à jour les uniforms du shader de simulation
	var write_material: ShaderMaterial = _sim_material_a if _ping else _sim_material_b
	if write_material:
		write_material.set_shader_parameter("delta_time", delta)
		write_material.set_shader_parameter("global_time", _global_time)

	# Mettre à jour le sprite de rendu pour lire le viewport d'écriture
	if _render_sprite:
		if _ping and _viewport_a:
			_render_sprite.texture = _viewport_a.get_texture()
			_render_material.set_shader_parameter("fluid_texture", _viewport_a.get_texture())
		elif _viewport_b:
			_render_sprite.texture = _viewport_b.get_texture()
			_render_material.set_shader_parameter("fluid_texture", _viewport_b.get_texture())

	# Alterner le ping-pong
	_ping = not _ping

## Convertit une position monde en position dans le viewport de simulation
func _world_to_sim(world_pos: Vector2) -> Vector2:
	return Vector2(
		world_pos.x / _game_viewport_size.x * float(SIM_WIDTH),
		world_pos.y / _game_viewport_size.y * float(SIM_HEIGHT)
	)

## API publique : ajouter un emitter à la file d'attente
func queue_emitter(world_pos: Vector2, color: Color, radius: float, intensity: float) -> void:
	var emit_color := color
	emit_color.a = clampf(intensity, 0.0, 1.0)
	_emitter_queue.append({
		"pos": world_pos,
		"color": emit_color,
		"radius": radius
	})

## Appliquer les paramètres d'un preset de fluide au shader de simulation
func apply_preset_params(preset: Dictionary) -> void:
	var decay: float = float(preset.get("decay", 0.97))
	var diffusion: float = float(preset.get("diffusion", 0.02))
	for mat in [_sim_material_a, _sim_material_b]:
		if mat:
			mat.set_shader_parameter("decay_rate", decay)
			mat.set_shader_parameter("diffusion_rate", diffusion)

## Nettoyage propre
func cleanup() -> void:
	queue_free()
