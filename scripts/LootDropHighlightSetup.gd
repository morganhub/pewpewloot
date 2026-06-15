extends Object
class_name LootDropHighlightSetup

## Logique partagée pour l'aura/highlight sous les loot drops et bonus cristaux (gameplay.loot_drops.highlight).

const STRONG_RESOURCE_CACHE_MAX: int = 128
static var _strong_resource_cache: Dictionary = {}
static var _first_frame_texture_cache: Dictionary = {}


static func setup_for_parent(parent: Node2D, base_width: float, base_height: float) -> void:
	var gameplay_cfg: Dictionary = DataManager.get_game_data().get("gameplay", {})
	var loot_drop_cfg_v: Variant = gameplay_cfg.get("loot_drops", {})
	if not (loot_drop_cfg_v is Dictionary):
		_clear_for_parent(parent)
		return
	var loot_drop_cfg: Dictionary = loot_drop_cfg_v as Dictionary
	var highlight_cfg_v: Variant = loot_drop_cfg.get("highlight", {})
	if not (highlight_cfg_v is Dictionary):
		_clear_for_parent(parent)
		return
	var highlight_cfg: Dictionary = highlight_cfg_v as Dictionary
	if not bool(highlight_cfg.get("enabled", false)):
		_clear_for_parent(parent)
		return

	var highlight_opacity: float = clampf(float(highlight_cfg.get("highlight_opacity", 1.0)), 0.0, 1.0)

	var target_w: float = float(highlight_cfg.get("width", -1.0))
	var target_h: float = float(highlight_cfg.get("height", -1.0))
	if target_w <= 0.0:
		target_w = base_width * maxf(1.0, float(highlight_cfg.get("width_multiplier", 1.2)))
	if target_h <= 0.0:
		target_h = base_height * maxf(1.0, float(highlight_cfg.get("height_multiplier", 1.2)))
	var offset_y: float = float(highlight_cfg.get("offset_y", 0.0))

	var asset_path: String = str(highlight_cfg.get("asset", ""))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var res: Resource = _load_cached_resource(asset_path)
		if res is SpriteFrames:
			var anim: AnimatedSprite2D = _get_or_create_highlight_anim_sprite(parent)
			anim.visible = true
			anim.position = Vector2(0.0, offset_y)
			anim.z_index = -1
			anim.modulate = Color(1.0, 1.0, 1.0, highlight_opacity)
			var played_anim: StringName = VFXManager.play_sprite_frames(
				anim,
				res as SpriteFrames,
				&"default",
				bool(highlight_cfg.get("asset_anim_loop", true)),
				maxf(0.0, float(highlight_cfg.get("asset_anim_duration", 0.8)))
			)
			if played_anim != &"" and anim.sprite_frames:
				var frame_tex: Texture2D = _get_cached_first_frame_texture(anim.sprite_frames, played_anim)
				if frame_tex:
					var s: Vector2 = frame_tex.get_size()
					if s.x > 0.0 and s.y > 0.0:
						var f: float = minf(target_w / s.x, target_h / s.y)
						anim.scale = Vector2.ONE * f
			var sp: Sprite2D = parent.get_node_or_null("HighlightSprite2D") as Sprite2D
			if sp:
				sp.visible = false
			var fb: Polygon2D = parent.get_node_or_null("HighlightFallback") as Polygon2D
			if fb:
				fb.visible = false
			_apply_highlight_pulse(anim, highlight_cfg)
			return
		if res is Texture2D:
			var sprite: Sprite2D = _get_or_create_highlight_sprite(parent)
			sprite.visible = true
			sprite.position = Vector2(0.0, offset_y)
			sprite.z_index = -1
			sprite.modulate = Color(1.0, 1.0, 1.0, highlight_opacity)
			sprite.texture = res as Texture2D
			var tex_size: Vector2 = sprite.texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				var factor: float = minf(target_w / tex_size.x, target_h / tex_size.y)
				sprite.scale = Vector2.ONE * factor
			var anim_node: AnimatedSprite2D = parent.get_node_or_null("HighlightAnimatedSprite2D") as AnimatedSprite2D
			if anim_node:
				anim_node.visible = false
			var fb2: Polygon2D = parent.get_node_or_null("HighlightFallback") as Polygon2D
			if fb2:
				fb2.visible = false
			_apply_highlight_pulse(sprite, highlight_cfg)
			return

	if not bool(highlight_cfg.get("fallback_aura_enabled", true)):
		_clear_for_parent(parent)
		return

	var aura: Polygon2D = _get_or_create_highlight_fallback(parent)
	aura.visible = true
	aura.position = Vector2(0.0, offset_y)
	aura.z_index = -1
	aura.modulate = Color(1.0, 1.0, 1.0, highlight_opacity)
	aura.color = Color(str(highlight_cfg.get("fallback_color", "#9FE8FF88")))
	aura.polygon = _create_circle_polygon(26.0)
	aura.scale = Vector2(target_w / 52.0, target_h / 52.0)

	var anim_hide: AnimatedSprite2D = parent.get_node_or_null("HighlightAnimatedSprite2D") as AnimatedSprite2D
	if anim_hide:
		anim_hide.visible = false
	var sprite_hide: Sprite2D = parent.get_node_or_null("HighlightSprite2D") as Sprite2D
	if sprite_hide:
		sprite_hide.visible = false
	_apply_highlight_pulse(aura, highlight_cfg)


static func _clear_for_parent(parent: Node) -> void:
	if parent == null:
		return
	var sp: Sprite2D = parent.get_node_or_null("HighlightSprite2D") as Sprite2D
	if sp:
		sp.visible = false
	var anim: AnimatedSprite2D = parent.get_node_or_null("HighlightAnimatedSprite2D") as AnimatedSprite2D
	if anim:
		anim.visible = false
	var fb: Polygon2D = parent.get_node_or_null("HighlightFallback") as Polygon2D
	if fb:
		fb.visible = false


static func _apply_highlight_pulse(node: Node2D, cfg: Dictionary) -> void:
	if node == null:
		return
	if not bool(cfg.get("pulse_enabled", true)):
		return
	var pulse_scale: float = maxf(1.0, float(cfg.get("pulse_scale", 1.08)))
	var pulse_duration: float = maxf(0.05, float(cfg.get("pulse_duration", 0.55)))
	var base_scale: Vector2 = node.scale
	var tw: Tween = node.create_tween()
	tw.set_loops()
	tw.tween_property(node, "scale", base_scale * pulse_scale, pulse_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "scale", base_scale, pulse_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _get_or_create_highlight_sprite(parent: Node2D) -> Sprite2D:
	var existing: Node = parent.get_node_or_null("HighlightSprite2D")
	if existing is Sprite2D:
		return existing as Sprite2D
	var s: Sprite2D = Sprite2D.new()
	s.name = "HighlightSprite2D"
	parent.add_child(s)
	parent.move_child(s, 0)
	return s


static func _get_or_create_highlight_anim_sprite(parent: Node2D) -> AnimatedSprite2D:
	var existing: Node = parent.get_node_or_null("HighlightAnimatedSprite2D")
	if existing is AnimatedSprite2D:
		return existing as AnimatedSprite2D
	var a: AnimatedSprite2D = AnimatedSprite2D.new()
	a.name = "HighlightAnimatedSprite2D"
	parent.add_child(a)
	parent.move_child(a, 0)
	return a


static func _get_or_create_highlight_fallback(parent: Node2D) -> Polygon2D:
	var existing: Node = parent.get_node_or_null("HighlightFallback")
	if existing is Polygon2D:
		return existing as Polygon2D
	var p: Polygon2D = Polygon2D.new()
	p.name = "HighlightFallback"
	parent.add_child(p)
	parent.move_child(p, 0)
	return p


static func _create_circle_polygon(radius: float, points: int = 24) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(8, points)
	for i in range(count):
		var a: float = (float(i) / float(count)) * TAU
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out


static func _load_cached_resource(path: String) -> Resource:
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


static func _get_cached_first_frame_texture(frames: SpriteFrames, anim_name: StringName) -> Texture2D:
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


static func _build_frame_cache_key(frames: SpriteFrames, anim_name: StringName) -> String:
	var path: String = frames.resource_path
	if path == "":
		path = "rid:" + str(frames.get_rid().get_id())
	return path + "|" + String(anim_name)
