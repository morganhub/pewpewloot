extends Sprite2D
class_name PlanetShadow
## Ombre portée douce sous la planète 3D.
## Génère un disque noir flou (ovale aplati) par code et le place sous/derrière la sphère.

@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var shadow_radius: float = 120.0
## Aplatissement vertical : 1.0 = cercle, < 1.0 = ovale écrasé.
@export var squash: float = 0.55
## Décalage Y en pixels (positif = ombre plus bas que le centre de la planète).
@export var offset_y: float = 20.0

const TEX_SIZE := 128
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_generer_texture_ombre()
	var facteur := (2.0 * shadow_radius) / float(TEX_SIZE)
	_base_scale = Vector2(facteur, facteur * squash)
	scale = _base_scale
	centered = true


func update_shadow(radius: float, center: Vector2) -> void:
	shadow_radius = radius
	var facteur := (2.0 * shadow_radius) / float(TEX_SIZE)
	_base_scale = Vector2(facteur, facteur * squash)
	scale = _base_scale
	position = Vector2(center.x, center.y + offset_y)


func _generer_texture_ombre() -> void:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_r := TEX_SIZE * 0.5
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var dist := Vector2(x, y).distance_to(center)
			var t := clampf(dist / max_r, 0.0, 1.0)
			var alpha := shadow_color.a * (1.0 - t) * (1.0 - t)
			img.set_pixel(x, y, Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha))
	texture = ImageTexture.create_from_image(img)
