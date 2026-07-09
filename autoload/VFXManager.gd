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
const _SPRITEFRAMES_VARIANT_CACHE_MAX: int = 128
const STRONG_RESOURCE_CACHE_MAX: int = 256
var _spriteframes_variant_cache: Dictionary = {}
var _strong_resource_cache: Dictionary = {}
var _first_frame_texture_cache: Dictionary = {}

func set_camera(camera: Camera2D) -> void:
	_camera = camera

func screen_shake(intensity: float, duration: float) -> void:
	if not bool(ProfileManager.get_setting("screenshake_enabled", true)):
		_shake_amount = 0.0
		_shake_duration = 0.0
		if _camera:
			_camera.offset = Vector2.ZERO
		return
	_shake_amount = intensity
	_shake_duration = duration

func _process(delta: float) -> void:
	if not bool(ProfileManager.get_setting("screenshake_enabled", true)):
		_shake_amount = 0.0
		_shake_duration = 0.0
		if _camera:
			_camera.offset = Vector2.ZERO
		return

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

	var playback_frames: SpriteFrames = _resolve_playback_frames(source_frames, anim_name, loop)
	if playback_frames == null:
		return &""

	anim_sprite.sprite_frames = playback_frames
	anim_sprite.animation = anim_name
	anim_sprite.speed_scale = 1.0
	anim_sprite.frame = 0
	anim_sprite.modulate.a = 1.0

	if duration > 0.0:
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
			var sprite_ref: WeakRef = weakref(anim_sprite)
			var captured_seq := seq
			var captured_anim := anim_name
			get_tree().create_timer(duration).timeout.connect(func():
				var s: AnimatedSprite2D = sprite_ref.get_ref() as AnimatedSprite2D
				if s == null or not is_instance_valid(s):
					return
				var current_seq: int = int(s.get_meta(_ANIM_META_SEQ_KEY, -1))
				if current_seq != captured_seq:
					return
				freeze_last_frame(s, captured_anim)
			)

	return anim_name

func _resolve_playback_frames(source_frames: SpriteFrames, anim_name: StringName, loop: bool) -> SpriteFrames:
	if source_frames == null:
		return null
	if anim_name == &"" or not source_frames.has_animation(anim_name):
		return source_frames

	# Fast path: no mutation needed, so no duplicate/allocation.
	if source_frames.get_animation_loop(anim_name) == loop:
		return source_frames

	var cache_key: String = _build_spriteframes_variant_key(source_frames, anim_name, loop)
	if _spriteframes_variant_cache.has(cache_key):
		var cached_variant: Variant = _spriteframes_variant_cache[cache_key]
		if cached_variant is SpriteFrames:
			return cached_variant as SpriteFrames

	# Duplicate only the SpriteFrames resource metadata (no deep subresources copy).
	var duplicated_res: Resource = source_frames.duplicate(false)
	if not (duplicated_res is SpriteFrames):
		return source_frames

	var duplicated_frames: SpriteFrames = duplicated_res as SpriteFrames
	duplicated_frames.set_animation_loop(anim_name, loop)

	if _spriteframes_variant_cache.size() >= _SPRITEFRAMES_VARIANT_CACHE_MAX:
		_spriteframes_variant_cache.clear()
	_spriteframes_variant_cache[cache_key] = duplicated_frames
	return duplicated_frames

func _build_spriteframes_variant_key(source_frames: SpriteFrames, anim_name: StringName, loop: bool) -> String:
	var path: String = source_frames.resource_path
	if path == "":
		path = "rid:" + str(source_frames.get_rid().get_id())
	return path + "|" + String(anim_name) + "|" + ("1" if loop else "0")

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
	asset_anim_loop: bool = true,
	fade_in_duration: float = 0.0,
	scale_start: float = 1.0,
	scale_middle: float = 1.0,
	scale_end: float = 1.0,
	scale_middle_ratio: float = 0.45,
	target_width: float = -1.0,
	target_height: float = -1.0
) -> void:
	var explosion := Node2D.new()
	explosion.global_position = pos
	container.add_child(explosion)
	var life: float = lifetime
	var fade_time: float = maxf(0.05, fade_out_duration)
	
	# Priority 1: Animated Asset
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames: Resource = _load_cached_resource(asset_anim)
		if frames is SpriteFrames:
			var anim_sprite := AnimatedSprite2D.new()
			anim_sprite.name = "ExplosionAnim"
			explosion.add_child(anim_sprite)
			_prepare_fade_in(anim_sprite, fade_in_duration)
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
				tex = _get_cached_first_frame_texture(frames_data, played_anim)
			if tex:
				anim_sprite.scale = _compute_explosion_scale(tex.get_size(), size, 4.0, target_width, target_height)
			var anim_total_duration: float = asset_anim_duration if asset_anim_duration > 0.0 else 0.2
			_apply_explosion_scale_profile(
				anim_sprite,
				anim_sprite.scale,
				scale_start,
				scale_middle,
				scale_end,
				scale_middle_ratio,
				anim_total_duration
			)

			if life > 0.0:
				var ex_ref: WeakRef = weakref(explosion)
				var timer_tween := create_tween()
				timer_tween.tween_interval(life)
				timer_tween.tween_property(anim_sprite, "modulate:a", 0.0, fade_time)
				timer_tween.tween_callback(func():
					var ex: Node2D = ex_ref.get_ref() as Node2D
					if ex != null and is_instance_valid(ex):
						ex.queue_free()
				)
			else:
				var cleanup_state: Array = [false]
				var sprite_wr: WeakRef = weakref(anim_sprite)
				var explosion_wr: WeakRef = weakref(explosion)
				var captured_played_anim := played_anim
				var cleanup: Callable = func():
					if cleanup_state[0]:
						return
					cleanup_state[0] = true
					var sp: AnimatedSprite2D = sprite_wr.get_ref() as AnimatedSprite2D
					var ex: Node2D = explosion_wr.get_ref() as Node2D
					if sp != null and is_instance_valid(sp) and not asset_anim_loop:
						freeze_last_frame(sp, captured_played_anim)
					if sp != null and is_instance_valid(sp):
						var fade_tween := create_tween()
						fade_tween.tween_property(sp, "modulate:a", 0.0, fade_time)
						if ex != null and is_instance_valid(ex):
							fade_tween.tween_callback(ex.queue_free)
					elif ex != null and is_instance_valid(ex):
						ex.queue_free()
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
		var texture_res: Resource = _load_cached_resource(asset_path)
		if texture_res is Texture2D:
			var texture: Texture2D = texture_res as Texture2D
			var sprite := Sprite2D.new()
			sprite.texture = texture
			explosion.add_child(sprite)
			_prepare_fade_in(sprite, fade_in_duration)
			
			# Scale
			sprite.scale = _compute_explosion_scale(texture.get_size(), size, 3.0, target_width, target_height)
			var static_total_duration: float = life if life > 0.0 else 0.18
			_apply_explosion_scale_profile(
				sprite,
				sprite.scale,
				scale_start,
				scale_middle,
				scale_end,
				scale_middle_ratio,
				static_total_duration
			)
			
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
	_prepare_fade_in(circle, fade_in_duration)
	var circle_total_duration: float = life if life > 0.0 else 0.3
	_apply_explosion_scale_profile(
		circle,
		circle.scale,
		scale_start,
		scale_middle,
		scale_end,
		scale_middle_ratio,
		circle_total_duration
	)
	
	if life > 0.0:
		var fade_tween := create_tween()
		fade_tween.tween_interval(life)
		fade_tween.tween_property(circle, "modulate:a", 0.0, fade_time)
		fade_tween.tween_callback(explosion.queue_free)
	else:
		var fade_tween := create_tween()
		fade_tween.tween_property(circle, "modulate:a", 0.0, 0.3)
		fade_tween.tween_callback(explosion.queue_free)
	
	# Particles placeholder (points qui s'éloignent)
	for i in range(8):
		_spawn_particle(pos, size, color, container)

func _prepare_fade_in(node: CanvasItem, fade_in_duration: float) -> void:
	if node == null:
		return
	var fade_in: float = maxf(0.0, fade_in_duration)
	if fade_in <= 0.0:
		node.modulate.a = 1.0
		return
	var col: Color = node.modulate
	col.a = 0.0
	node.modulate = col
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, fade_in)

func _apply_explosion_scale_profile(
	node: Node2D,
	base_scale: Vector2,
	scale_start: float,
	scale_middle: float,
	scale_end: float,
	scale_middle_ratio: float,
	total_duration: float
) -> void:
	if node == null:
		return
	var start_mul: float = maxf(0.01, scale_start)
	var middle_mul: float = maxf(0.01, scale_middle)
	var end_mul: float = maxf(0.01, scale_end)
	var duration: float = maxf(0.05, total_duration)
	var middle_ratio_clamped: float = clampf(scale_middle_ratio, 0.05, 0.95)
	var t1: float = duration * middle_ratio_clamped
	var t2: float = maxf(0.02, duration - t1)

	node.scale = base_scale * start_mul
	var scale_tween := create_tween()
	scale_tween.tween_property(node, "scale", base_scale * middle_mul, t1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(node, "scale", base_scale * end_mul, t2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _compute_explosion_scale(
	tex_size: Vector2,
	size: float,
	base_factor: float,
	target_width: float,
	target_height: float
) -> Vector2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Vector2.ONE

	var w: float = target_width
	var h: float = target_height
	if w > 0.0 or h > 0.0:
		if w <= 0.0:
			w = tex_size.x
		if h <= 0.0:
			h = tex_size.y
		var contain_factor: float = minf(w / tex_size.x, h / tex_size.y)
		return Vector2.ONE * contain_factor

	return Vector2((size * base_factor) / tex_size.x, (size * base_factor) / tex_size.y)

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

# Floating texts are pooled: dense play (crystal rains, killstreaks) would
# otherwise allocate a Label + theme override per event on gameplay frames.
const FLOATING_LABEL_POOL_MAX: int = 24
var _floating_label_pool: Array[Label] = []
var _floating_text_font_size: int = -1 # lazy: résolu depuis game.json au 1er spawn

## game.json racine > floating_text.font_size (réglage global, tous modes).
func _resolve_floating_text_font_size() -> int:
	if _floating_text_font_size > 0:
		return _floating_text_font_size
	var size: int = 32
	if typeof(DataManager) != TYPE_NIL and DataManager:
		var ft_v: Variant = DataManager.get_game_data().get("floating_text", {})
		if ft_v is Dictionary:
			size = maxi(8, int((ft_v as Dictionary).get("font_size", 32)))
	_floating_text_font_size = size
	return size

func spawn_floating_text(pos: Vector2, text: String, color: Color, container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	var label: Label = null
	while label == null and not _floating_label_pool.is_empty():
		# is_instance_valid FIRST: pooled labels can be freed instances from a
		# previous run (their HUD parent was freed on scene change) and even the
		# 'is' operator raises on a freed instance.
		var candidate: Variant = _floating_label_pool.pop_back()
		if is_instance_valid(candidate) and candidate is Label:
			label = candidate as Label
	if label == null:
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font_size: int = _resolve_floating_text_font_size()
	# Ré-appliqué à chaque spawn (labels poolés, taille configurable).
	label.add_theme_font_size_override("font_size", font_size)
	label.text = text
	label.modulate = color
	if label.get_parent() != container:
		if label.get_parent():
			label.get_parent().remove_child(label)
		container.add_child(label)
	label.visible = true
	# Centrage approximatif proportionnel à la taille de police.
	label.global_position = pos + Vector2(-1.25, -1.25) * float(font_size)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y - 40, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(_release_floating_label.bind(label))

func _release_floating_label(label_v: Variant) -> void:
	# Variant signature + is_instance_valid FIRST: the tween lives on this
	# autoload and can outlive the label (scene change mid-animation) — both a
	# typed Label param and the 'is' operator raise on a freed instance.
	if not is_instance_valid(label_v) or not (label_v is Label):
		return
	var label: Label = label_v as Label
	label.visible = false
	if _floating_label_pool.size() < FLOATING_LABEL_POOL_MAX:
		_floating_label_pool.append(label)
	else:
		label.queue_free()

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
			_first_frame_texture_cache.clear()
		_strong_resource_cache[path] = resource
	return resource

func _get_cached_first_frame_texture(frames: SpriteFrames, anim_name: StringName) -> Texture2D:
	if frames == null or anim_name == &"":
		return null
	var frame_key: String = _build_frame_cache_key(frames, anim_name)
	if _first_frame_texture_cache.has(frame_key):
		var cached: Variant = _first_frame_texture_cache[frame_key]
		if cached is Texture2D:
			return cached as Texture2D

	var texture: Texture2D = frames.get_frame_texture(anim_name, 0)
	if texture != null:
		_first_frame_texture_cache[frame_key] = texture
	return texture

func _build_frame_cache_key(frames: SpriteFrames, anim_name: StringName) -> String:
	var path: String = frames.resource_path
	if path == "":
		path = "rid:" + str(frames.get_rid().get_id())
	return path + "|" + String(anim_name)
