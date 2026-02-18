extends Node

## VFXManager — Gère les effets visuels (explosions, impacts, screen shake).
## Utilise des particles/animations placeholder en attendant les vrais assets.

# =============================================================================
# CAMERA SHAKE
# =============================================================================

var _camera: Camera2D = null
var _shake_amount: float = 0.0
var _shake_duration: float = 0.0
const _ANIM_META_SEQ_KEY: String = "_anim_playback_seq"

func set_camera(camera: Camera2D) -> void:
	_camera = camera

func screen_shake(intensity: float, duration: float) -> void:
	_shake_amount = intensity
	_shake_duration = duration

func _process(delta: float) -> void:
	if _shake_duration > 0:
		_shake_duration -= delta
		
		if _camera:
			_camera.offset = Vector2(
				randf_range(-_shake_amount, _shake_amount),
				randf_range(-_shake_amount, _shake_amount)
			)
		
		# Decay
		_shake_amount = lerp(_shake_amount, 0.0, delta * 5.0)
	elif _camera:
		_camera.offset = Vector2.ZERO

# =============================================================================
# ANIMATED SPRITEFRAMES PLAYBACK
# =============================================================================

func get_first_animation_name(frames: SpriteFrames, preferred_anim: StringName = &"default") -> StringName:
	if frames == null:
		return &""
	if preferred_anim != &"" and frames.has_animation(preferred_anim):
		return preferred_anim
	var names: PackedStringArray = frames.get_animation_names()
	if names.is_empty():
		return &""
	return StringName(names[0])

func get_animation_duration(frames: SpriteFrames, anim_name: StringName) -> float:
	if frames == null:
		return 0.0
	if anim_name == &"" or not frames.has_animation(anim_name):
		return 0.0
	var frame_count: int = frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return 0.0
	var fps: float = maxf(frames.get_animation_speed(anim_name), 0.0001)
	return float(frame_count) / fps

func freeze_last_frame(anim_sprite: AnimatedSprite2D, anim_name: StringName = &"") -> void:
	if anim_sprite == null or not is_instance_valid(anim_sprite):
		return
	var frames: SpriteFrames = anim_sprite.sprite_frames
	if frames == null:
		return
	var final_anim: StringName = anim_name
	if final_anim == &"":
		final_anim = anim_sprite.animation
	if not frames.has_animation(final_anim):
		final_anim = get_first_animation_name(frames)
	if final_anim == &"":
		return
	var frame_count: int = frames.get_frame_count(final_anim)
	if frame_count <= 0:
		return
	anim_sprite.stop()
	anim_sprite.animation = final_anim
	anim_sprite.frame = frame_count - 1

func play_sprite_frames(
	anim_sprite: AnimatedSprite2D,
	source_frames: SpriteFrames,
	preferred_anim: StringName = &"default",
	loop: bool = true,
	duration: float = 0.0
) -> StringName:
	if anim_sprite == null or source_frames == null:
		return &""

	var anim_name: StringName = get_first_animation_name(source_frames, preferred_anim)
	if anim_name == &"":
		return &""

	var playback_frames: SpriteFrames = source_frames
	var duplicated: Resource = source_frames.duplicate(true)
	if duplicated is SpriteFrames:
		playback_frames = duplicated as SpriteFrames
	playback_frames.set_animation_loop(anim_name, loop)

	anim_sprite.sprite_frames = playback_frames
	anim_sprite.animation = anim_name
	anim_sprite.speed_scale = 1.0
	anim_sprite.frame = 0
	anim_sprite.modulate.a = 1.0

	if not loop and duration > 0.0:
		var natural_duration: float = get_animation_duration(playback_frames, anim_name)
		if natural_duration > 0.0:
			anim_sprite.speed_scale = natural_duration / duration

	var previous_seq: int = int(anim_sprite.get_meta(_ANIM_META_SEQ_KEY, 0))
	var seq: int = previous_seq + 1
	anim_sprite.set_meta(_ANIM_META_SEQ_KEY, seq)

	anim_sprite.play(anim_name)

	if not loop:
		var on_finished: Callable = func():
			if not is_instance_valid(anim_sprite):
				return
			var current_seq: int = int(anim_sprite.get_meta(_ANIM_META_SEQ_KEY, -1))
			if current_seq != seq:
				return
			freeze_last_frame(anim_sprite, anim_name)
		anim_sprite.animation_finished.connect(on_finished, CONNECT_ONE_SHOT)

		if duration > 0.0:
			get_tree().create_timer(duration).timeout.connect(func():
				if not is_instance_valid(anim_sprite):
					return
				var current_seq: int = int(anim_sprite.get_meta(_ANIM_META_SEQ_KEY, -1))
				if current_seq != seq:
					return
				freeze_last_frame(anim_sprite, anim_name)
			)

	return anim_name

# =============================================================================
# EXPLOSION
# =============================================================================

func spawn_explosion(
	pos: Vector2,
	size: float,
	color: Color,
	container: Node,
	asset_path: String = "",
	asset_anim: String = "",
	lifetime: float = -1.0,
	fade_out_duration: float = 0.3,
	asset_anim_duration: float = 0.0,
	asset_anim_loop: bool = true
) -> void:
	var explosion := Node2D.new()
	explosion.global_position = pos
	container.add_child(explosion)
	var life: float = lifetime
	var fade_time: float = maxf(0.05, fade_out_duration)
	
	# Priority 1: Animated Asset
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames = load(asset_anim)
		if frames is SpriteFrames:
			var anim_sprite := AnimatedSprite2D.new()
			anim_sprite.name = "ExplosionAnim"
			explosion.add_child(anim_sprite)
			var frames_data: SpriteFrames = frames as SpriteFrames
			var played_anim: StringName = play_sprite_frames(
				anim_sprite,
				frames_data,
				&"default",
				asset_anim_loop,
				maxf(0.0, asset_anim_duration)
			)
			
			# Scale based on size?
			# Assuming default frame size is ~64x64, we scale to match 'size * 2'
			var tex: Texture2D = null
			if played_anim != &"":
				tex = frames_data.get_frame_texture(played_anim, 0)
			if tex:
				var s = tex.get_size()
				anim_sprite.scale = Vector2(size * 4 / s.x, size * 4 / s.y) # Bigger explosion

			if life > 0.0:
				var timer_tween := create_tween()
				timer_tween.tween_interval(life)
				timer_tween.tween_property(anim_sprite, "modulate:a", 0.0, fade_time)
				timer_tween.tween_callback(explosion.queue_free)
			else:
				var cleanup_state: Array = [false]  # [0] = started flag (array avoids capture reassign warning)
				var cleanup: Callable = func():
					if cleanup_state[0]:
						return
					cleanup_state[0] = true
					if is_instance_valid(anim_sprite) and not asset_anim_loop:
						freeze_last_frame(anim_sprite, played_anim)
					if is_instance_valid(anim_sprite):
						var fade_tween := create_tween()
						fade_tween.tween_property(anim_sprite, "modulate:a", 0.0, fade_time)
						fade_tween.tween_callback(explosion.queue_free)
					elif is_instance_valid(explosion):
						explosion.queue_free()
				if not asset_anim_loop:
					if asset_anim_duration > 0.0:
						get_tree().create_timer(asset_anim_duration).timeout.connect(cleanup)
					else:
						anim_sprite.animation_finished.connect(cleanup, CONNECT_ONE_SHOT)
				else:
					var auto_lifetime: float = 0.8
					if asset_anim_duration > 0.0:
						auto_lifetime = asset_anim_duration
					auto_lifetime = maxf(0.2, auto_lifetime)
					get_tree().create_timer(auto_lifetime).timeout.connect(cleanup)
			return

	# Priority 2: Static Asset (Fade out)
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var texture = load(asset_path)
		if texture:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			explosion.add_child(sprite)
			
			# Scale
			var s = texture.get_size()
			sprite.scale = Vector2(size * 3 / s.x, size * 3 / s.y)
			
			var alpha_tween := create_tween()
			if life > 0.0:
				alpha_tween.tween_interval(life)
			alpha_tween.tween_property(sprite, "modulate:a", 0.0, fade_time)
			alpha_tween.tween_callback(explosion.queue_free)
			return

	# Priority 3: Geometric Fallback
	var circle := Polygon2D.new()
	circle.color = color
	circle.polygon = _create_circle(size)
	explosion.add_child(circle)
	
	# Animation
	var tween := create_tween()
	tween.set_parallel(true)
	var scale_duration: float = 0.3
	if life > 0.0:
		scale_duration = maxf(0.15, life)
	tween.tween_property(circle, "scale", Vector2(2.5, 2.5), scale_duration)
	if life > 0.0:
		var fade_tween := create_tween()
		fade_tween.tween_interval(life)
		fade_tween.tween_property(circle, "modulate:a", 0.0, fade_time)
		fade_tween.tween_callback(explosion.queue_free)
	else:
		tween.tween_property(circle, "modulate:a", 0.0, 0.3)
		tween.chain().tween_callback(explosion.queue_free)
	
	# Particles placeholder (points qui s'éloignent)
	for i in range(8):
		_spawn_particle(pos, size, color, container)

func _spawn_particle(pos: Vector2, size: float, color: Color, container: Node) -> void:
	var particle := Polygon2D.new()
	particle.global_position = pos
	particle.color = color
	particle.polygon = _create_circle(size / 3.0)
	container.add_child(particle)
	
	var direction := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance := randf_range(30, 60)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "global_position", pos + direction * distance, 0.4)
	tween.tween_property(particle, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(particle.queue_free)

# =============================================================================
# HIT FLASH
# =============================================================================

func flash_sprite(node: Node, flash_color: Color = Color.WHITE, duration: float = 0.1) -> void:
	# Trouver le Polygon2D ou Sprite2D
	var visual: Node = null
	for child in node.get_children():
		if child is Polygon2D or child is Sprite2D:
			visual = child
			break
	
	if not visual:
		return
	
	var original_color: Color = Color.WHITE
	if visual is Polygon2D:
		original_color = (visual as Polygon2D).color
		(visual as Polygon2D).color = flash_color
	elif visual is Sprite2D:
		original_color = (visual as Sprite2D).modulate
		(visual as Sprite2D).modulate = flash_color
	
	# Tween retour à la couleur originale
	var tween := create_tween()
	if visual is Polygon2D:
		tween.tween_property(visual, "color", original_color, duration)
	elif visual is Sprite2D:
		tween.tween_property(visual, "modulate", original_color, duration)

# =============================================================================
# IMPACT
# =============================================================================

func spawn_impact(pos: Vector2, size: float, container: Node) -> void:
	# Petit flash au point d'impact
	var impact := Polygon2D.new()
	impact.global_position = pos
	impact.color = Color.YELLOW
	impact.polygon = _create_circle(size)
	container.add_child(impact)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(impact, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_property(impact, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(impact.queue_free)

# =============================================================================
# FLOATING TEXT
# =============================================================================

func spawn_floating_text(pos: Vector2, text: String, color: Color, container: Node) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.global_position = pos + Vector2(-20, -20) # Centrer approximativement
	label.add_theme_font_size_override("font_size", 16)
	container.add_child(label)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 40, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)

# =============================================================================
# UTILITY
# =============================================================================

func _create_circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var num_points := 12
	for i in range(num_points):
		var angle := (i / float(num_points)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
