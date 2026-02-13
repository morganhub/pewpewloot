extends AnimatableBody2D

@export var speed: float = 100.0
@export var contact_sfx_path: String = ""

@onready var detection_area: Area2D = $DetectionArea

func _ready() -> void:
	# Add Area to group "walls" so projectiles can detect us
	detection_area.add_to_group("walls")
	
	# Body is layer 1, collides player (2)
	z_index = -10 # Behind enemies (0), above background (-100)
	
	# Detect Player contact for SFX (via Area)
	detection_area.body_entered.connect(_on_body_entered_area)

func _physics_process(delta: float) -> void:
	# Move downward physically
	var velocity = Vector2(0, speed)
	global_position += velocity * delta
	
	if global_position.y > get_viewport_rect().size.y + 100:
		queue_free()

func _on_body_entered_area(body: Node2D) -> void:
	# Check Player contact for SFX
	if body.is_in_group("player"):
		# print("[Wall] Player Contact! Playing SFX: ", contact_sfx_path)
		if contact_sfx_path != "" and ResourceLoader.exists(contact_sfx_path):
			AudioManager.play_sfx(contact_sfx_path)
			
		# Optional: Apply small push/damage? No, physics handles push.
		# User requested 99999 ONLY if pushed off-screen.
