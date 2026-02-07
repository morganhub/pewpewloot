extends Node2D

## ScrollingLayer
## Gère le défilement infini d'une texture (ou d'un groupe d'objets)
## Correspond à une "couche" de background.

var _speed: float = 0.0
var _texture_height: float = 0.0
var _offset_y: float = 0.0

func setup(texture: Texture2D, scroll_speed: float, viewport_size: Vector2) -> void:
	_speed = scroll_speed
	
	if texture:
		_texture_height = texture.get_height()
		
		# Calculer combien de tuiles sont nécessaires pour couvrir l'écran + buffer
		# On a besoin de couvrir de -_texture_height jusqu'à viewport_size.y
		# car l'offset va faire bouger le tout.
		
		var needed_height = viewport_size.y + _texture_height * 2
		var current_y = -_texture_height # Commencer un cran au-dessus
		
		while current_y < needed_height:
			var s := Sprite2D.new()
			s.texture = texture
			s.centered = false
			s.position.y = current_y
			add_child(s)
			current_y += _texture_height
		
		# Position initiale (offset 0)
		position.y = 0.0

func _process(delta: float) -> void:
	# Algorithme de défilement demandé :
	# offset_y += (vitesse) * delta
	# Wrap : si offset_y > hauteur alors offset_y = 0
	
	_offset_y += _speed * delta
	
	if _texture_height > 0:
		if _offset_y >= _texture_height:
			_offset_y -= _texture_height
	
	# Appliquer le décalage localement
	position.y = _offset_y
