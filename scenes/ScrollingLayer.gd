extends Node2D

## ScrollingLayer
## Gère le défilement infini d'une texture (ou d'un groupe d'objets)
## Correspond à une "couche" de background.

var _speed: float = 0.0
var _texture_height: float = 0.0
var _offset_y: float = 0.0

func setup(texture: Texture2D, scroll_speed: float, _viewport_size: Vector2) -> void:
	_speed = scroll_speed
	
	if texture:
		_texture_height = texture.get_height()
		
		# Créer 2 sprites pour le tiling vertical infini
		# Instance 1 : Position de base
		var s1 := Sprite2D.new()
		s1.texture = texture
		s1.centered = false
		add_child(s1)
		
		# Instance 2 : Juste au-dessus (pour scroller vers le bas)
		var s2 := Sprite2D.new()
		s2.texture = texture
		s2.centered = false
		s2.position.y = -_texture_height
		add_child(s2)

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
