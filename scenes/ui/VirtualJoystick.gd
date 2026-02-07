extends Control

## VirtualJoystick — Joystick virtuel dynamique "Follower".
## Apparaît au toucher, suit le doigt si on dépasse le rayon, disparait au relâchement.
## Ignore les entrées souris.

# =============================================================================
# EXPORTS
# =============================================================================

@export var max_radius: float = 100.0
@export var deadzone_size: float = 0.1 # 10%
@export var base_color: Color = Color(1, 1, 1, 0.2)
@export var knob_color: Color = Color(1, 1, 1, 0.5)

# =============================================================================
# VARIABLES
# =============================================================================

var _touch_id: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO
var _output: Vector2 = Vector2.ZERO
var _active: bool = false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Invisible par défaut
	hide()
	set_process_input(true)

func _input(event: InputEvent) -> void:
	# Ignorer la souris, accepter uniquement le tactile
	if event is InputEventMouse:
		return
		
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)

func _draw() -> void:
	if _active:
		# Dessiner la base (Cercle)
		draw_circle(_base_pos, max_radius, base_color)
		# Dessiner le contour de la base
		draw_arc(_base_pos, max_radius, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
		
		# Dessiner le knob (Cercle plein)
		# Le knob est visuellement à _knob_pos
		draw_circle(_knob_pos, 20.0, knob_color)

# =============================================================================
# LOGIC
# =============================================================================

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Si aucun doigt n'est actif, on prend celui-ci comme joystick
		if _touch_id == -1:
			_touch_id = event.index
			_start_joystick(event.position)
	else:
		# Si le doigt actif est relâché
		if event.index == _touch_id:
			_reset_joystick()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _touch_id:
		_update_joystick(event.position)

func _start_joystick(pos: Vector2) -> void:
	_active = true
	_base_pos = pos
	_knob_pos = pos
	_output = Vector2.ZERO
	show()
	queue_redraw()

func _reset_joystick() -> void:
	_touch_id = -1
	_active = false
	_output = Vector2.ZERO
	hide()
	queue_redraw()

func _update_joystick(finger_pos: Vector2) -> void:
	# Calculer la distance par rapport à la base
	var diff := finger_pos - _base_pos
	var dist := diff.length()
	
	# "Follower" Logic : Si on dépasse le rayon, la base suit le doigt
	if dist > max_radius:
		# Calculer la direction du doigt par rapport à la base
		var dir := diff.normalized()
		# Déplacer la base pour qu'elle soit exactement à max_radius du doigt
		_base_pos = finger_pos - (dir * max_radius)
		# Recalculer diff/dist par rapport à la nouvelle base
		diff = finger_pos - _base_pos
		dist = max_radius # Par définition
	
	_knob_pos = finger_pos
	
	# Calcul de l'output normalisé (-1 à 1)
	if dist > 0:
		var raw_output := diff / max_radius
		_output = _apply_deadzone(raw_output)
	else:
		_output = Vector2.ZERO
	
	queue_redraw()

func _apply_deadzone(value: Vector2) -> Vector2:
	if value.length() < deadzone_size:
		return Vector2.ZERO
	return value

# =============================================================================
# API
# =============================================================================

## Retourne le vecteur de direction (normalisé, avec force).
## Vector2.ZERO si inactif.
func get_output() -> Vector2:
	return _output

## Vérifie si le joystick est actif (doigt posé).
func is_active() -> bool:
	return _active

func is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.get_name() == "headless" # Headless/Mobile simulation
