extends Control

signal loading_completed(packed_scene: PackedScene)

@onready var bg: ColorRect = $Background
@onready var loading_label: Label = $Label
@onready var spinner: TextureRect = $Spinner

var _target_scene_path: String = ""
var _packed_scene: PackedScene = null

func _ready() -> void:
	modulate.a = 0.0 # Start invisible
	
func start_loading(scene_path: String) -> void:
	_target_scene_path = scene_path
	
	# Fade In
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	await tw.finished
	
	# Wait a frame to ensure UI is drawn
	await get_tree().process_frame
	
	# Start Loading logic
	_perform_loading()

func _perform_loading() -> void:
	loading_label.text = "LOADING..."
	
	# Simulate loading time or actually load
	# In Godot 4, load() is blocking but fast for small projects.
	# For "warming up" shaders/cache, we can instantiate some things or just wait.
	
	await get_tree().create_timer(0.1).timeout
	
	# Preload critical assets here?
	# E.g. common projectiles
	var common_stuff = [
		"res://scenes/Projectile.tscn",
		"res://assets/missiles/sacred_missile.tres"
	]
	for path in common_stuff:
		if ResourceLoader.exists(path):
			ResourceLoader.load(path)
			
	# Load Target Scene
	if ResourceLoader.exists(_target_scene_path):
		_packed_scene = ResourceLoader.load(_target_scene_path)
	else:
		push_error("Scene not found: " + _target_scene_path)
		
	# Artificial delay to ensure visuals are ready (user mentioned "first 2 missiles invisible")
	await get_tree().create_timer(0.2).timeout
	
	loading_completed.emit(_packed_scene)

func fade_out() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	await tw.finished
	queue_free()
