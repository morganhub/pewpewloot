extends Control

signal loading_completed(packed_scene: PackedScene)

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const DEBUG_LOADING_RESOURCES_LOG := false
const RUNTIME_WARMUP_SCENE_PATHS: PackedStringArray = [
	"res://scenes/obstacles/ObstacleExplosive.tscn",
	"res://scenes/obstacles/ObstaclePusher.tscn",
	"res://scenes/objects/Mine.tscn",
	"res://scenes/objects/ArcaneOrb.tscn",
	"res://scenes/objects/GravityWell.tscn",
	"res://scenes/objects/SuppressorShield.tscn",
	"res://scenes/effects/ToxicPool.tscn",
	"res://scenes/effects/Singularity.tscn",
	"res://scenes/effects/IceAura.tscn",
	"res://scenes/effects/IceShards.tscn",
	"res://scenes/effects/VacuumRadius.tscn",
	"res://scenes/abilities/objects/Wall.tscn",
	"res://scenes/abilities/WallSpawner.gd",
	"res://scenes/effects/BossVoidZone.gd",
	"res://scenes/effects/BossLaserZone.gd"
]
const RUNTIME_WARMUP_PREFIXES: PackedStringArray = [
	"res://scenes/abilities/",
	"res://scenes/effects/",
	"res://scenes/objects/",
	"res://scenes/obstacles/"
]
const DEFAULT_LOADING_SCREEN_CONFIG: Dictionary = {
	"show_label": false,
	"show_spinner": false,
	"overlay_color": "#000000",
	"overlay_alpha": 0.5,
	"progress_bar": {
		"width_ratio": 0.62,
		"min_width": 300.0,
		"max_width": 980.0,
		"height": 34.0,
		"anchor_y": 0.84,
		"show_percentage": false,
		"background_color": "#1A1F2A",
		"fill_color": "#6FD7FF",
		"border_color": "#FFFFFF",
		"fill_border_color": "#B9F0FF",
		"border_width": 2,
		"corner_radius": 12,
		"fill_corner_radius": 11
	}
}

@onready var bg: ColorRect = $Background
@onready var loading_label: Label = $Label
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var spinner: TextureRect = $Spinner

var _target_scene_path: String = ""
var _packed_scene: PackedScene = null
var _loading_screen_config: Dictionary = {}
var _show_loading_label: bool = false
var _level_preview: TextureRect = null

func _ready() -> void:
	modulate.a = 0.0 # Start invisible
	_refresh_loading_screen_look()
	
func start_loading(scene_path: String) -> void:
	_target_scene_path = scene_path
	_refresh_loading_screen_look()
	
	# Fade In
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	await tw.finished
	
	# Wait a frame to ensure UI is drawn
	await get_tree().process_frame
	
	# Start Loading logic
	_perform_loading()

func _refresh_loading_screen_look() -> void:
	_loading_screen_config = _resolve_loading_screen_config()
	_setup_level_preview_node()
	_apply_loading_visual_config()
	_apply_level_preview_from_current_level()

func _resolve_loading_screen_config() -> Dictionary:
	var result: Dictionary = DEFAULT_LOADING_SCREEN_CONFIG.duplicate(true)
	var raw_cfg_variant: Variant = DataManager.get_game_config().get("loading_screen", {})
	if not (raw_cfg_variant is Dictionary):
		return result

	var raw_cfg: Dictionary = raw_cfg_variant as Dictionary
	for key_variant in raw_cfg.keys():
		var key: String = str(key_variant)
		if key == "progress_bar":
			continue
		result[key] = raw_cfg[key_variant]

	var default_pb_cfg: Dictionary = {}
	var default_pb_variant: Variant = result.get("progress_bar", {})
	if default_pb_variant is Dictionary:
		default_pb_cfg = (default_pb_variant as Dictionary).duplicate(true)
	var raw_pb_variant: Variant = raw_cfg.get("progress_bar", {})
	if raw_pb_variant is Dictionary:
		default_pb_cfg.merge(raw_pb_variant as Dictionary, true)
	result["progress_bar"] = default_pb_cfg
	return result

func _setup_level_preview_node() -> void:
	if _level_preview != null and is_instance_valid(_level_preview):
		return
	var existing: Node = get_node_or_null("LevelPreview")
	if existing is TextureRect:
		_level_preview = existing as TextureRect
	else:
		_level_preview = TextureRect.new()
		_level_preview.name = "LevelPreview"
		_level_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_level_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_level_preview)
	move_child(_level_preview, 0)
	_level_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_level_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _apply_loading_visual_config() -> void:
	if bg:
		var overlay_color: Color = Color(str(_loading_screen_config.get("overlay_color", "#000000")))
		overlay_color.a = clampf(float(_loading_screen_config.get("overlay_alpha", 0.5)), 0.0, 1.0)
		bg.color = overlay_color

	_show_loading_label = bool(_loading_screen_config.get("show_label", false))
	if loading_label:
		loading_label.visible = _show_loading_label
	if spinner:
		spinner.visible = bool(_loading_screen_config.get("show_spinner", false))

	if progress_bar == null:
		return

	var pb_cfg: Dictionary = {}
	var pb_variant: Variant = _loading_screen_config.get("progress_bar", {})
	if pb_variant is Dictionary:
		pb_cfg = pb_variant as Dictionary

	var viewport_size: Vector2 = get_viewport_rect().size
	var width_ratio: float = clampf(float(pb_cfg.get("width_ratio", 0.62)), 0.2, 0.95)
	var min_width: float = maxf(120.0, float(pb_cfg.get("min_width", 300.0)))
	var max_width: float = maxf(min_width, float(pb_cfg.get("max_width", 980.0)))
	var target_width: float = clampf(viewport_size.x * width_ratio, min_width, max_width)
	var target_height: float = maxf(8.0, float(pb_cfg.get("height", 34.0)))
	var anchor_y: float = clampf(float(pb_cfg.get("anchor_y", 0.84)), 0.0, 1.0)
	var half_w: float = target_width * 0.5
	var half_h: float = target_height * 0.5

	progress_bar.anchor_left = 0.5
	progress_bar.anchor_right = 0.5
	progress_bar.anchor_top = anchor_y
	progress_bar.anchor_bottom = anchor_y
	progress_bar.offset_left = -half_w
	progress_bar.offset_right = half_w
	progress_bar.offset_top = -half_h
	progress_bar.offset_bottom = half_h
	progress_bar.custom_minimum_size = Vector2(target_width, target_height)
	progress_bar.show_percentage = bool(pb_cfg.get("show_percentage", false))

	var corner_radius: int = maxi(0, int(pb_cfg.get("corner_radius", 12)))
	var fill_corner_radius: int = maxi(0, int(pb_cfg.get("fill_corner_radius", corner_radius)))
	var border_width: int = maxi(0, int(pb_cfg.get("border_width", 2)))

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(str(pb_cfg.get("background_color", "#1A1F2A")))
	bg_style.border_color = Color(str(pb_cfg.get("border_color", "#FFFFFF")))
	bg_style.border_width_left = border_width
	bg_style.border_width_top = border_width
	bg_style.border_width_right = border_width
	bg_style.border_width_bottom = border_width
	bg_style.corner_radius_top_left = corner_radius
	bg_style.corner_radius_top_right = corner_radius
	bg_style.corner_radius_bottom_left = corner_radius
	bg_style.corner_radius_bottom_right = corner_radius
	progress_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(str(pb_cfg.get("fill_color", "#6FD7FF")))
	fill_style.border_color = Color(str(pb_cfg.get("fill_border_color", "#B9F0FF")))
	fill_style.border_width_left = border_width
	fill_style.border_width_top = border_width
	fill_style.border_width_right = border_width
	fill_style.border_width_bottom = border_width
	fill_style.corner_radius_top_left = fill_corner_radius
	fill_style.corner_radius_top_right = fill_corner_radius
	fill_style.corner_radius_bottom_left = fill_corner_radius
	fill_style.corner_radius_bottom_right = fill_corner_radius
	progress_bar.add_theme_stylebox_override("fill", fill_style)

func _apply_level_preview_from_current_level() -> void:
	if _level_preview == null:
		return
	var bg_path: String = _resolve_current_level_background_path()
	if bg_path == "":
		_level_preview.visible = false
		_level_preview.texture = null
		return

	var loaded: Resource = ResourceLoader.load(bg_path, "", ResourceLoader.CACHE_MODE_REUSE)
	var texture: Texture2D = _extract_texture_from_resource(loaded)
	if texture == null:
		_level_preview.visible = false
		_level_preview.texture = null
		return

	_level_preview.texture = texture
	_level_preview.visible = true

func _resolve_current_level_background_path() -> String:
	var level_id: String = App.current_world_id + "_lvl_" + str(App.current_level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return ""

	var backgrounds: Dictionary = level_data.get("backgrounds", {})
	var candidates: Array = []
	candidates.append(str(backgrounds.get("far_layer", "")))
	candidates.append(str(backgrounds.get("card", "")))
	candidates.append_array(_flatten_layer_entries(backgrounds.get("mid_layer", [])))
	candidates.append_array(_flatten_layer_entries(backgrounds.get("near_layer", [])))

	for candidate_variant in candidates:
		var candidate: String = str(candidate_variant).strip_edges()
		if candidate != "" and ResourceLoader.exists(candidate):
			return candidate
	return ""

func _extract_texture_from_resource(resource: Resource) -> Texture2D:
	if resource is Texture2D:
		return resource as Texture2D
	if resource is SpriteFrames:
		var frames: SpriteFrames = resource as SpriteFrames
		var animations: PackedStringArray = frames.get_animation_names()
		for animation in animations:
			if frames.get_frame_count(animation) > 0:
				return frames.get_frame_texture(animation, 0)
	return null

func _set_loading_label_text(text: String) -> void:
	if loading_label and _show_loading_label:
		loading_label.text = text

func _perform_loading() -> void:
	_set_loading_label_text("LOADING...")
	if progress_bar:
		progress_bar.value = 0.0

	var plan: Array = _build_loading_plan(_target_scene_path)
	var loaded_resources: Dictionary = {}

	var total_steps: int = max(1, plan.size() + 1)
	var done_steps: int = 0

	for path_variant in plan:
		var path: String = str(path_variant)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var was_cached: bool = ResourceLoader.has_cached(path)
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if resource != null:
			loaded_resources[path] = resource
			if DEBUG_LOADING_RESOURCES_LOG:
				print("[Loading] ", ("reused " if was_cached else "loaded "), path)
		done_steps += 1
		_update_progress(done_steps, total_steps, "Loading assets")
		if (done_steps % 4) == 0:
			await get_tree().process_frame

	var warmup_textures: Array[Texture2D] = _collect_warmup_textures(loaded_resources)
	total_steps = max(total_steps, done_steps + warmup_textures.size() + 1)
	if not warmup_textures.is_empty():
		_set_loading_label_text("LOADING...")
		await _warmup_textures(warmup_textures, done_steps, total_steps)
		done_steps += warmup_textures.size()

	var is_game_scene: bool = _target_scene_path.to_lower().contains("game.tscn")
	if is_game_scene:
		var enemy_warmup_payloads: Array = _collect_enemy_warmup_payloads()
		total_steps = max(total_steps, done_steps + enemy_warmup_payloads.size() + 1)
		if not enemy_warmup_payloads.is_empty():
			_set_loading_label_text("LOADING...")
			done_steps = await _warmup_enemy_instances(enemy_warmup_payloads, done_steps, total_steps)

		var runtime_node_paths: Array = _collect_runtime_node_paths_for_warmup(loaded_resources)
		total_steps = max(total_steps, done_steps + runtime_node_paths.size() + 1)
		if not runtime_node_paths.is_empty():
			_set_loading_label_text("LOADING...")
			done_steps = await _warmup_runtime_nodes(runtime_node_paths, loaded_resources, done_steps, total_steps)

	var loaded_scene: Variant = loaded_resources.get(_target_scene_path, null)
	if loaded_scene is PackedScene:
		_packed_scene = loaded_scene as PackedScene
	elif ResourceLoader.exists(_target_scene_path):
		var scene_res: Resource = ResourceLoader.load(_target_scene_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if scene_res is PackedScene:
			_packed_scene = scene_res as PackedScene
	else:
		push_error("Scene not found: " + _target_scene_path)

	done_steps = total_steps
	_update_progress(done_steps, total_steps, "Done")
	await get_tree().process_frame
	loading_completed.emit(_packed_scene)

func fade_out() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	await tw.finished
	queue_free()

func _update_progress(done_steps: int, total_steps: int, _phase: String) -> void:
	var clamped_total: int = max(1, total_steps)
	var pct: float = clampf((float(done_steps) / float(clamped_total)) * 100.0, 0.0, 100.0)
	if progress_bar:
		progress_bar.value = pct
	if loading_label and _show_loading_label:
		loading_label.text = str(int(round(pct))) + "%"

func _build_loading_plan(scene_path: String) -> Array:
	var ordered_paths: Array = []
	var seen: Dictionary = {}

	_add_plan_path(ordered_paths, seen, scene_path)
	_add_plan_path(ordered_paths, seen, "res://scenes/Game.tscn")
	_add_plan_path(ordered_paths, seen, "res://scenes/Enemy.tscn")
	_add_plan_path(ordered_paths, seen, "res://scenes/Boss.tscn")
	_add_plan_path(ordered_paths, seen, "res://scenes/Projectile.tscn")
	for runtime_path in RUNTIME_WARMUP_SCENE_PATHS:
		_add_plan_path(ordered_paths, seen, str(runtime_path))

	var is_game_scene: bool = scene_path.to_lower().contains("game.tscn")
	if is_game_scene:
		_collect_level_assets(ordered_paths, seen)
		_collect_runtime_support_assets(ordered_paths, seen)

	return ordered_paths

func _collect_level_assets(ordered_paths: Array, seen: Dictionary) -> void:
	var world_id: String = App.current_world_id
	var level_index: int = App.current_level_index
	var level_id: String = world_id + "_lvl_" + str(level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return

	var bgs: Dictionary = level_data.get("backgrounds", {})
	_add_plan_path(ordered_paths, seen, str(bgs.get("far_layer", "")))
	for entry in _flatten_layer_entries(bgs.get("mid_layer", [])):
		_add_plan_path(ordered_paths, seen, str(entry))
	for entry in _flatten_layer_entries(bgs.get("near_layer", [])):
		_add_plan_path(ordered_paths, seen, str(entry))

	var world_skin_overrides: Dictionary = DataManager.get_world_skin_overrides(world_id)
	var enemy_overrides: Dictionary = {}
	var boss_overrides: Dictionary = {}
	var raw_enemy_overrides: Variant = world_skin_overrides.get("enemies", {})
	var raw_boss_overrides: Variant = world_skin_overrides.get("bosses", {})
	if raw_enemy_overrides is Dictionary:
		enemy_overrides = raw_enemy_overrides as Dictionary
	if raw_boss_overrides is Dictionary:
		boss_overrides = raw_boss_overrides as Dictionary

	var waves_variant: Variant = level_data.get("waves", [])
	if waves_variant is Array:
		for wave_variant in (waves_variant as Array):
			if not (wave_variant is Dictionary):
				continue
			var wave: Dictionary = wave_variant as Dictionary
			if str(wave.get("type", "enemy")) == "obstacle":
				_collect_resource_paths_recursive(wave, ordered_paths, seen)
				continue

			var enemy_id: String = str(wave.get("enemy_id", ""))
			if enemy_id == "":
				continue
			_collect_enemy_assets(enemy_id, ordered_paths, seen)

			var override_skin: String = str(enemy_overrides.get(enemy_id, ""))
			if override_skin != "":
				_add_plan_path(ordered_paths, seen, override_skin)
			else:
				_add_plan_path(ordered_paths, seen, str(wave.get("enemy_skin", "")))

	var boss_id: String = str(level_data.get("boss_id", ""))
	if boss_id != "":
		_collect_boss_assets(boss_id, ordered_paths, seen)
		var boss_skin: String = str(boss_overrides.get(boss_id, ""))
		_add_plan_path(ordered_paths, seen, boss_skin)

	var all_move_patterns: Array = DataManager.get_all_move_patterns()
	for pattern_variant in all_move_patterns:
		if not (pattern_variant is Dictionary):
			continue
		var pattern: Dictionary = pattern_variant as Dictionary
		_add_plan_path(ordered_paths, seen, str(pattern.get("path", pattern.get("resource", ""))))

func _collect_runtime_support_assets(ordered_paths: Array, seen: Dictionary) -> void:
	_collect_enemy_modifier_assets(ordered_paths, seen)
	_collect_obstacle_assets(ordered_paths, seen)
	_collect_power_assets_from_file("res://data/missiles/super_powers.json", ordered_paths, seen)
	_collect_power_assets_from_file("res://data/missiles/unique_powers.json", ordered_paths, seen)
	_collect_power_assets_from_file("res://data/missiles/boss_powers.json", ordered_paths, seen)
	_collect_resource_paths_recursive(DataManager.get_skills_config(), ordered_paths, seen)
	_collect_resource_paths_recursive(DataManager.get_game_config().get("gameplay", {}), ordered_paths, seen)

func _collect_enemy_modifier_assets(ordered_paths: Array, seen: Dictionary) -> void:
	var data_variant: Variant = _load_json_file("res://data/enemy_modifiers.json")
	if not (data_variant is Dictionary):
		return
	var modifiers: Dictionary = data_variant as Dictionary
	for modifier_variant in modifiers.values():
		_collect_resource_paths_recursive(modifier_variant, ordered_paths, seen)

func _collect_obstacle_assets(ordered_paths: Array, seen: Dictionary) -> void:
	var obstacles: Dictionary = DataManager.get_all_obstacles()
	for obstacle_variant in obstacles.values():
		_collect_resource_paths_recursive(obstacle_variant, ordered_paths, seen)

func _collect_power_assets_from_file(path: String, ordered_paths: Array, seen: Dictionary) -> void:
	var data_variant: Variant = _load_json_file(path)
	if not (data_variant is Dictionary):
		return
	var powers_variant: Variant = (data_variant as Dictionary).get("powers", [])
	if not (powers_variant is Array):
		return
	for power_variant in (powers_variant as Array):
		_collect_resource_paths_recursive(power_variant, ordered_paths, seen)

func _load_json_file(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data

func _collect_resource_paths_recursive(value: Variant, ordered_paths: Array, seen: Dictionary) -> void:
	if value is Dictionary:
		for entry_value in (value as Dictionary).values():
			_collect_resource_paths_recursive(entry_value, ordered_paths, seen)
		return

	if value is Array:
		for entry in (value as Array):
			_collect_resource_paths_recursive(entry, ordered_paths, seen)
		return

	if value is String:
		var path: String = str(value).strip_edges()
		if path.begins_with("res://"):
			_add_plan_path(ordered_paths, seen, path)

func _collect_enemy_assets(enemy_id: String, ordered_paths: Array, seen: Dictionary) -> void:
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	if enemy_data.is_empty():
		return

	var visual_variant: Variant = enemy_data.get("visual", {})
	if visual_variant is Dictionary:
		var visual: Dictionary = visual_variant as Dictionary
		_add_plan_path(ordered_paths, seen, str(visual.get("asset", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("asset_anim", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("on_death_asset", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("on_death_asset_anim", "")))

	var missile_id: String = str(enemy_data.get("missile_id", ""))
	if missile_id == "":
		return
	var missile_data: Dictionary = DataManager.get_missile(missile_id)
	if missile_data.is_empty():
		return

	var missile_visual_variant: Variant = missile_data.get("visual", {})
	if missile_visual_variant is Dictionary:
		var missile_visual: Dictionary = missile_visual_variant as Dictionary
		_add_plan_path(ordered_paths, seen, str(missile_visual.get("asset", "")))
		_add_plan_path(ordered_paths, seen, str(missile_visual.get("asset_anim", "")))

	_add_plan_path(ordered_paths, seen, str(missile_data.get("sound", "")))

	var explosion_variant: Variant = missile_data.get("explosion", {})
	var explosion_data: Dictionary = {}
	if explosion_variant is Dictionary and not (explosion_variant as Dictionary).is_empty():
		explosion_data = explosion_variant as Dictionary
	else:
		explosion_data = DataManager.get_default_explosion()
	_add_plan_path(ordered_paths, seen, str(explosion_data.get("asset", "")))
	_add_plan_path(ordered_paths, seen, str(explosion_data.get("asset_anim", "")))

func _collect_boss_assets(boss_id: String, ordered_paths: Array, seen: Dictionary) -> void:
	var boss_data: Dictionary = DataManager.get_boss(boss_id)
	if boss_data.is_empty():
		return

	var visual_variant: Variant = boss_data.get("visual", {})
	if visual_variant is Dictionary:
		var visual: Dictionary = visual_variant as Dictionary
		_add_plan_path(ordered_paths, seen, str(visual.get("asset", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("asset_anim", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("on_death_asset", "")))
		_add_plan_path(ordered_paths, seen, str(visual.get("on_death_asset_anim", "")))

func _add_plan_path(ordered_paths: Array, seen: Dictionary, path: String) -> void:
	if path == "":
		return
	if seen.has(path):
		return
	seen[path] = true
	ordered_paths.append(path)

func _flatten_layer_entries(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item in data:
			result.append_array(_flatten_layer_entries(item))
	elif data is String:
		var path := str(data)
		if path != "":
			result.append(path)
	elif data is Dictionary:
		var entry := data as Dictionary
		var path: String = str(entry.get("asset", entry.get("path", "")))
		if path != "":
			result.append(path)
	return result

func _collect_warmup_textures(loaded_resources: Dictionary) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var seen: Dictionary = {}
	for value in loaded_resources.values():
		if value is Texture2D:
			_add_warmup_texture(result, seen, value as Texture2D)
		elif value is SpriteFrames:
			var frames: SpriteFrames = value as SpriteFrames
			var names: PackedStringArray = frames.get_animation_names()
			for anim_name in names:
				var frame_count: int = frames.get_frame_count(anim_name)
				for frame_idx in range(frame_count):
					var frame_tex: Texture2D = frames.get_frame_texture(anim_name, frame_idx)
					_add_warmup_frame_texture(result, seen, frame_tex)
	return result

func _add_warmup_frame_texture(result: Array[Texture2D], seen: Dictionary, frame_tex: Texture2D) -> void:
	if frame_tex == null:
		return
	if frame_tex is AtlasTexture:
		var atlas: Texture2D = (frame_tex as AtlasTexture).atlas
		_add_warmup_texture(result, seen, atlas)
	else:
		_add_warmup_texture(result, seen, frame_tex)

func _add_warmup_texture(result: Array[Texture2D], seen: Dictionary, texture: Texture2D) -> void:
	if texture == null:
		return
	var key: String = texture.resource_path
	if key == "":
		key = "rid:" + str(texture.get_rid().get_id())
	if seen.has(key):
		return
	seen[key] = true
	result.append(texture)

func _warmup_textures(textures: Array[Texture2D], done_steps_start: int, total_steps: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	var root := Node2D.new()
	viewport.add_child(root)

	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.position = Vector2(32.0, 32.0)
	root.add_child(sprite)

	var done_steps: int = done_steps_start
	for tex in textures:
		if tex == null:
			continue
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		var max_dim: float = maxf(tex_size.x, tex_size.y)
		if max_dim > 0.0:
			sprite.scale = Vector2.ONE * (48.0 / max_dim)
		else:
			sprite.scale = Vector2.ONE

		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		done_steps += 1
		_update_progress(done_steps, total_steps, "Warming textures")

	viewport.queue_free()

func _collect_enemy_warmup_payloads() -> Array:
	var result: Array = []
	var seen: Dictionary = {}

	var world_id: String = App.current_world_id
	var level_index: int = App.current_level_index
	var level_id: String = world_id + "_lvl_" + str(level_index)
	var level_data: Dictionary = DataManager.get_level_data(level_id)
	if level_data.is_empty():
		return result

	var world_skin_overrides: Dictionary = DataManager.get_world_skin_overrides(world_id)
	var enemy_overrides: Dictionary = {}
	var raw_enemy_overrides: Variant = world_skin_overrides.get("enemies", {})
	if raw_enemy_overrides is Dictionary:
		enemy_overrides = raw_enemy_overrides as Dictionary

	var waves_variant: Variant = level_data.get("waves", [])
	if not (waves_variant is Array):
		return result

	for wave_variant in (waves_variant as Array):
		if not (wave_variant is Dictionary):
			continue
		var wave: Dictionary = wave_variant as Dictionary
		if str(wave.get("type", "enemy")) == "obstacle":
			continue

		var enemy_id: String = str(wave.get("enemy_id", ""))
		if enemy_id == "":
			continue

		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
		if enemy_data.is_empty():
			continue

		var enemy_skin: String = str(enemy_overrides.get(enemy_id, ""))
		if enemy_skin == "":
			enemy_skin = str(wave.get("enemy_skin", ""))

		var warmup_key: String = enemy_id + "|" + enemy_skin
		if seen.has(warmup_key):
			continue
		seen[warmup_key] = true

		var payload: Dictionary = enemy_data.duplicate(true)
		_apply_enemy_skin_override(payload, enemy_skin)
		result.append(payload)

	return result

func _apply_enemy_skin_override(enemy_data: Dictionary, enemy_skin: String) -> void:
	if enemy_skin == "":
		return
	if not ResourceLoader.exists(enemy_skin):
		return

	var visual: Dictionary = {}
	var visual_variant: Variant = enemy_data.get("visual", {})
	if visual_variant is Dictionary:
		visual = (visual_variant as Dictionary).duplicate(true)

	var skin_res: Resource = ResourceLoader.load(enemy_skin, "", ResourceLoader.CACHE_MODE_REUSE)
	var ext: String = enemy_skin.get_extension().to_lower()
	var is_frames: bool = (skin_res is SpriteFrames) or ext == "tres" or ext == "res"
	if is_frames:
		visual["asset_anim"] = enemy_skin
		visual["asset"] = ""
	else:
		visual["asset"] = enemy_skin
		visual["asset_anim"] = ""

	enemy_data["visual"] = visual

func _warmup_enemy_instances(payloads: Array, done_steps_start: int, total_steps: int) -> int:
	if payloads.is_empty() or ENEMY_SCENE == null:
		return done_steps_start

	var host := Node2D.new()
	host.visible = true
	add_child(host)

	var done_steps: int = done_steps_start
	var patterns_warmed: bool = false
	for payload_variant in payloads:
		if not (payload_variant is Dictionary):
			continue
		var payload: Dictionary = payload_variant as Dictionary
		var enemy: Node = ENEMY_SCENE.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		host.add_child(enemy)
		if enemy is Node2D:
			(enemy as Node2D).global_position = Vector2(360.0, 640.0)
		if enemy.has_method("setup"):
			enemy.call("setup", payload)
		if not patterns_warmed and enemy.has_method("setup_movement"):
			var all_patterns: Array = DataManager.get_all_move_patterns()
			for pattern_variant in all_patterns:
				if pattern_variant is Dictionary:
					enemy.call("setup_movement", pattern_variant as Dictionary)
			patterns_warmed = true
		enemy.queue_free()

		done_steps += 1
		_update_progress(done_steps, total_steps, "Warming enemies")
		await get_tree().process_frame

	host.queue_free()
	return done_steps

func _collect_runtime_node_paths_for_warmup(loaded_resources: Dictionary) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for path_variant in loaded_resources.keys():
		var path: String = str(path_variant)
		if not _is_runtime_warmup_path(path):
			continue
		if seen.has(path):
			continue
		var resource: Variant = loaded_resources[path]
		if resource is PackedScene or resource is Script:
			seen[path] = true
			result.append(path)
	return result

func _is_runtime_warmup_path(path: String) -> bool:
	if path == "":
		return false
	for prefix_variant in RUNTIME_WARMUP_PREFIXES:
		var prefix: String = str(prefix_variant)
		if path.begins_with(prefix):
			return true
	return false

func _warmup_runtime_nodes(
	node_paths: Array,
	loaded_resources: Dictionary,
	done_steps_start: int,
	total_steps: int
) -> int:
	if node_paths.is_empty():
		return done_steps_start

	var host := Node2D.new()
	host.visible = true
	add_child(host)

	var done_steps: int = done_steps_start
	for path_variant in node_paths:
		var path: String = str(path_variant)
		var resource: Variant = loaded_resources.get(path, null)
		var instance: Node = null
		if resource is PackedScene:
			instance = (resource as PackedScene).instantiate()
		elif resource is Script:
			var script_resource: Script = resource as Script
			if script_resource != null and script_resource.can_instantiate():
				var created: Variant = script_resource.new()
				if created is Node:
					instance = created as Node

		if instance != null:
			instance.process_mode = Node.PROCESS_MODE_DISABLED
			if instance is CanvasItem:
				(instance as CanvasItem).visible = true
			if instance is Node2D:
				(instance as Node2D).global_position = Vector2(400.0, 400.0)
			host.add_child(instance)
			await get_tree().process_frame
			instance.queue_free()

		done_steps += 1
		_update_progress(done_steps, total_steps, "Warming runtime")
		await get_tree().process_frame

	host.queue_free()
	return done_steps
