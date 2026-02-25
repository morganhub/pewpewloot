extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## HomeScreen — Écran d'accueil après sélection/chargement du profil.
## Layout: Top 40% for title/info, Bottom 60% for buttons.
## Buttons are 75% screen width.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var top_section: VBoxContainer = $TopSection
@onready var bottom_section: VBoxContainer = $BottomSection

@onready var title_label: Label = $TopSection/TitleLabel
@onready var logo_texture: TextureRect = $TopSection/LogoTexture
@onready var logo_anim_container: Control = $TopSection/LogoAnimContainer
@onready var logo_anim: AnimatedSprite2D = $TopSection/LogoAnimContainer/LogoAnim
@onready var profile_info_panel: PanelContainer = $TopSection/ProfileInfoPanel
@onready var profile_info: HBoxContainer = $TopSection/ProfileInfoPanel/Margin/ProfileInfo
@onready var crystal_icon: TextureRect = $TopSection/ProfileInfoPanel/Margin/ProfileInfo/CrystalIcon
@onready var crystal_label: Label = $TopSection/ProfileInfoPanel/Margin/ProfileInfo/CrystalLabel
@onready var level_label: Label = $TopSection/ProfileInfoPanel/Margin/ProfileInfo/LevelLabel
@onready var ship_preview: HBoxContainer = $TopSection/ProfileInfoPanel/Margin/ProfileInfo/ShipPreview

@onready var play_button: Button = $BottomSection/PlayButton
@onready var ship_button: Button = $BottomSection/ShipButton
@onready var skills_button: Button = $BottomSection/SkillsButton
@onready var options_button: Button = $BottomSection/OptionsButton
@onready var quit_button: Button = $BottomSection/QuitButton
@onready var change_profile_button: Button = $BottomSection/ChangeProfileButton
@onready var unlock_all_button: Button = $BottomSection/UnlockAllButton

var _game_config: Dictionary = {}
var _crystal_anim: AnimatedSprite2D = null
static var _logo_first_visit: bool = true

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	App.play_menu_music()
	_setup_layout()
	_setup_background()
	_setup_logo()
	_setup_buttons()
	_setup_profile_info_bar()
	_apply_translations()
	_update_info()
	_request_menu_prewarm()
	
	# Connect signals
	play_button.pressed.connect(_on_play_pressed)
	ship_button.pressed.connect(_on_ship_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	change_profile_button.pressed.connect(_on_change_profile_pressed)
	
	# Temporary dev button (editor only): regenerate movement curve resources.
	if unlock_all_button:
		unlock_all_button.visible = OS.has_feature("editor")
		if unlock_all_button.visible:
			unlock_all_button.pressed.connect(_on_unlock_all_pressed)

func _load_game_config() -> void:
	if DataManager:
		_game_config = DataManager.get_game_config()
	else:
		_game_config = {}

func _setup_layout() -> void:
	# Layout is handled by anchors
	pass

func _setup_profile_info_bar() -> void:
	if profile_info_panel == null:
		return

	var target_width: float = 540.0
	if play_button and play_button.custom_minimum_size.x > 0.0:
		target_width = play_button.custom_minimum_size.x

	var target_height: float = 70.0
	if play_button and play_button.custom_minimum_size.y > 0.0:
		target_height = play_button.custom_minimum_size.y
	profile_info_panel.custom_minimum_size = Vector2(target_width, target_height)

	var buttons_config: Dictionary = _game_config.get("buttons", {})
	var shared_cfg := _extract_shared_button_cfg(buttons_config)
	var play_cfg := _merge_button_cfg(shared_cfg, buttons_config.get("play", {}))
	var play_asset: String = str(play_cfg.get("asset", ""))

	var style: StyleBox = null
	if play_asset != "" and ResourceLoader.exists(play_asset):
		style = UIStyle.build_texture_stylebox(play_asset, play_cfg, 10)
	if style == null:
		var fallback_style := StyleBoxFlat.new()
		fallback_style.bg_color = Color(0.04, 0.07, 0.15, 0.8)
		fallback_style.set_corner_radius_all(10)
		style = fallback_style
	profile_info_panel.add_theme_stylebox_override("panel", style)

	var crystal_icon_path := _get_shared_crystal_icon_path()
	_setup_crystal_icon(crystal_icon_path)

func _get_shared_crystal_icon_path() -> String:
	if DataManager and DataManager.has_method("get_shared_crystal_icon_path"):
		return str(DataManager.get_shared_crystal_icon_path())
	return "res://assets/ui/icons/crystal.png"

func _load_texture_from_resource_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if DataManager and DataManager.has_method("get_texture_from_resource_path"):
		return DataManager.get_texture_from_resource_path(path)
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource is Texture2D:
		return resource as Texture2D
	if resource is SpriteFrames:
		var frames := resource as SpriteFrames
		var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
		if anim_name != &"" and frames.get_frame_count(anim_name) > 0:
			return frames.get_frame_texture(anim_name, 0)
	return null

func _get_shared_crystal_icon_cfg() -> Dictionary:
	if DataManager and DataManager.has_method("get_shared_crystal_icon_config"):
		return DataManager.get_shared_crystal_icon_config()
	var path := _get_shared_crystal_icon_path()
	return {
		"asset": path,
		"animation_repeat_seconds": 0.0,
		"animation_type": "loop",
		"animation_duration": 2.0
	}

func _setup_crystal_icon(path: String) -> void:
	if crystal_icon == null:
		return

	var cfg: Dictionary = _get_shared_crystal_icon_cfg()
	var resolved_path := str(cfg.get("asset", path)).strip_edges()
	if resolved_path == "" or not ResourceLoader.exists(resolved_path):
		resolved_path = path

	if resolved_path == "" or not ResourceLoader.exists(resolved_path):
		crystal_icon.texture = null
		crystal_icon.visible = false
		_clear_home_crystal_anim()
		return

	var res: Resource = ResourceLoader.load(resolved_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is SpriteFrames:
		var frames := res as SpriteFrames
		var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
		if anim_name != &"" and frames.get_frame_count(anim_name) > 0:
			var first_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
			crystal_icon.texture = first_tex
			crystal_icon.visible = true
			_ensure_home_crystal_anim(frames, cfg)
			return

	var crystal_texture := _load_texture_from_resource_path(resolved_path)
	crystal_icon.texture = crystal_texture
	crystal_icon.visible = crystal_texture != null
	_clear_home_crystal_anim()

func _ensure_home_crystal_anim(frames: SpriteFrames, cfg: Dictionary) -> void:
	if crystal_icon == null:
		return
	if _crystal_anim == null or not is_instance_valid(_crystal_anim):
		_crystal_anim = AnimatedSprite2D.new()
		_crystal_anim.name = "CrystalAnim"
		_crystal_anim.centered = true
		_crystal_anim.z_index = 0
		crystal_icon.add_child(_crystal_anim)
		if not crystal_icon.resized.is_connected(_on_home_crystal_icon_resized):
			crystal_icon.resized.connect(_on_home_crystal_icon_resized)

	_crystal_anim.sprite_frames = frames
	_on_home_crystal_icon_resized()
	_play_home_shared_icon(_crystal_anim, cfg)

func _clear_home_crystal_anim() -> void:
	if _crystal_anim != null and is_instance_valid(_crystal_anim):
		_crystal_anim.stop()
		_crystal_anim.visible = false
		_crystal_anim.queue_free()
	_crystal_anim = null

func _stop_home_crystal_for_transition() -> void:
	if crystal_icon:
		crystal_icon.visible = false
		crystal_icon.texture = null
	_clear_home_crystal_anim()

func prepare_for_transition() -> void:
	_stop_home_crystal_for_transition()

func _on_home_crystal_icon_resized() -> void:
	if crystal_icon == null or _crystal_anim == null or not is_instance_valid(_crystal_anim):
		return

	_crystal_anim.position = crystal_icon.size * 0.5
	var frames: SpriteFrames = _crystal_anim.sprite_frames
	if frames == null:
		return
	var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
	if anim_name == &"" or frames.get_frame_count(anim_name) <= 0:
		return
	var frame_tex: Texture2D = frames.get_frame_texture(anim_name, 0)
	if frame_tex == null:
		return
	var frame_size := frame_tex.get_size()
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return
	var fit_scale := minf(crystal_icon.size.x / frame_size.x, crystal_icon.size.y / frame_size.y)
	_crystal_anim.scale = Vector2(fit_scale, fit_scale)

func _play_home_shared_icon(anim: AnimatedSprite2D, cfg: Dictionary) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	var frames: SpriteFrames = anim.sprite_frames
	if frames == null:
		return
	var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
	if anim_name == &"":
		return

	var repeat_seconds: float = maxf(0.0, float(cfg.get("animation_repeat_seconds", 0.0)))
	var play_duration: float = maxf(0.0, float(cfg.get("animation_duration", 0.0)))
	var anim_type: String = str(cfg.get("animation_type", "")).strip_edges().to_lower()
	var play_loop := repeat_seconds <= 0.0
	if anim_type == "loop":
		play_loop = true
	elif anim_type in ["once", "one_shot", "oneshot", "single"]:
		play_loop = false
	if repeat_seconds > 0.0:
		play_loop = false

	VFXManager.play_sprite_frames(anim, frames, anim_name, play_loop, play_duration)
	if repeat_seconds > 0.0:
		_repeat_home_shared_icon(anim, anim_name, repeat_seconds, play_duration, play_loop)

func _repeat_home_shared_icon(
	anim: AnimatedSprite2D,
	anim_name: StringName,
	repeat_seconds: float,
	play_duration: float,
	play_loop: bool
) -> void:
	while is_instance_valid(anim):
		var tree := anim.get_tree()
		if tree == null:
			return
		await tree.create_timer(repeat_seconds).timeout
		if not is_instance_valid(anim):
			return
		var frames: SpriteFrames = anim.sprite_frames
		if frames == null:
			return
		VFXManager.play_sprite_frames(anim, frames, anim_name, play_loop, play_duration)

func _setup_background() -> void:
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	var bg_path: String = str(menu_config.get("background", ""))
	var bg_anim_path: String = str(menu_config.get("background_anim", ""))
	
	# Priority: anim > static > fallback color
	if bg_anim_path != "" and ResourceLoader.exists(bg_anim_path):
		# TODO: Handle animated background
		pass
	elif bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and background_rect:
			background_rect.texture = tex
			background_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# Fallback: dark gradient
		if background_rect:
			background_rect.visible = false

func _setup_logo() -> void:
	var menu_config: Dictionary = _game_config.get("main_menu", {})
	var logo_path: String = str(menu_config.get("logo", ""))
	var logo_anim_path: String = str(menu_config.get("logo_anim", ""))
	var logo_anim_duration: float = maxf(0.0, float(menu_config.get("logo_anim_duration", 2.0)))
	var logo_anim_loop: bool = bool(menu_config.get("logo_anim_loop", false))
	var width_pct: float = float(menu_config.get("logo_width_pct", 0.5))
	var height_pct: float = float(menu_config.get("logo_height_pct", 0.2))
	
	var viewport_size := get_viewport_rect().size
	var target_size := Vector2(viewport_size.x * width_pct, viewport_size.y * height_pct)
	
	# Apply sizing and 'contain' behavior
	if logo_texture:
		logo_texture.custom_minimum_size = target_size
		logo_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	if logo_anim_container:
		logo_anim_container.custom_minimum_size = target_size
	
	# Reset visibility (default to text)
	title_label.visible = true
	if logo_texture: logo_texture.visible = false
	if logo_anim_container: logo_anim_container.visible = false
	
	# Au premier passage dans la session : logo animé. Retours au menu : logo statique (main_menu.logo)
	var was_first_visit: bool = _logo_first_visit
	if _logo_first_visit:
		_logo_first_visit = false
	var use_animated_logo: bool = was_first_visit and (logo_anim_path != "" and ResourceLoader.exists(logo_anim_path))
	
	# Logo animé : uniquement au démarrage du jeu
	if use_animated_logo:
		var frames: Resource = load(logo_anim_path)
		if frames is SpriteFrames and logo_anim:
			VFXManager.play_sprite_frames(
				logo_anim,
				frames as SpriteFrames,
				&"default",
				logo_anim_loop,
				logo_anim_duration
			)
			
			if not logo_anim_container.resized.is_connected(_center_logo_anim):
				logo_anim_container.resized.connect(_center_logo_anim)
			_center_logo_anim()
			
			logo_anim_container.scale = Vector2.ZERO
			logo_anim_container.modulate.a = 0.0
			logo_anim_container.pivot_offset = target_size / 2
			
			var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(logo_anim_container, "scale", Vector2.ONE, 3.0)
			tween.tween_property(logo_anim_container, "modulate:a", 1.0, 3.0)
			
			if logo_anim_container: logo_anim_container.visible = true
			title_label.visible = false
			return

	# Logo statique (retours au menu ou si pas d'anim) : main_menu.logo
	if logo_path != "" and ResourceLoader.exists(logo_path):
		var tex = load(logo_path)
		if tex and logo_texture:
			logo_texture.texture = tex
			logo_texture.visible = true
			title_label.visible = false
			logo_texture.pivot_offset = target_size / 2
			if was_first_visit:
				logo_texture.scale = Vector2.ZERO
				logo_texture.modulate.a = 0.0
				var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tween.tween_property(logo_texture, "scale", Vector2.ONE, 3.0)
				tween.tween_property(logo_texture, "modulate:a", 1.0, 3.0)
			else:
				logo_texture.scale = Vector2.ONE
				logo_texture.modulate.a = 1.0
			return

func _center_logo_anim() -> void:
	if logo_anim and logo_anim_container:
		var container_size = logo_anim_container.size
		logo_anim.position = container_size / 2
		
		# Containment logic for AnimatedSprite2D
		var frames = logo_anim.sprite_frames
		if frames:
			var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
			var frame_tex: Texture2D = null
			if anim_name != &"":
				frame_tex = frames.get_frame_texture(anim_name, 0)
			if frame_tex:
				var tex_size = frame_tex.get_size()
				if tex_size.x > 0 and tex_size.y > 0:
					var scale_factor = min(container_size.x / tex_size.x, container_size.y / tex_size.y)
					logo_anim.scale = Vector2(scale_factor, scale_factor)

func _setup_buttons() -> void:
	var buttons_config: Dictionary = _game_config.get("buttons", {})
	var shared_cfg := _extract_shared_button_cfg(buttons_config)
	
	_setup_single_button(play_button, _merge_button_cfg(shared_cfg, buttons_config.get("play", {})), "home_play")
	_setup_single_button(ship_button, _merge_button_cfg(shared_cfg, buttons_config.get("ship", {})), "home_ship_menu")
	_setup_single_button(options_button, _merge_button_cfg(shared_cfg, buttons_config.get("options", {})), "home_options")
	_setup_single_button(quit_button, _merge_button_cfg(shared_cfg, buttons_config.get("quit", {})), "home_quit")
	_setup_single_button(skills_button, _merge_button_cfg(shared_cfg, buttons_config.get("skills", {})), "home_skills")
	_setup_single_button(change_profile_button, _merge_button_cfg(shared_cfg, buttons_config.get("change_profile", {})), "home_change_profile_short")

func _extract_shared_button_cfg(buttons_config: Dictionary) -> Dictionary:
	var shared := {}
	if buttons_config.has("default_nine_slice"):
		shared["nine_slice"] = buttons_config.get("default_nine_slice", {})
	if buttons_config.has("default_content_margin"):
		shared["content_margin"] = buttons_config.get("default_content_margin", {})
	if buttons_config.has("default_stretch_horizontal"):
		shared["stretch_horizontal"] = buttons_config.get("default_stretch_horizontal", "stretch")
	if buttons_config.has("default_stretch_vertical"):
		shared["stretch_vertical"] = buttons_config.get("default_stretch_vertical", "stretch")
	if buttons_config.has("default_draw_center"):
		shared["draw_center"] = buttons_config.get("default_draw_center", true)
	return shared

func _merge_button_cfg(shared_cfg: Dictionary, per_button_cfg: Variant) -> Dictionary:
	var merged := shared_cfg.duplicate(true)
	if per_button_cfg is Dictionary:
		for key in (per_button_cfg as Dictionary).keys():
			merged[key] = (per_button_cfg as Dictionary)[key]
	return merged

func _setup_single_button(button: Button, config: Dictionary, translation_key: String) -> void:
	var asset_path: String = str(config.get("asset", ""))
	var asset_anim: String = str(config.get("asset_anim", ""))
	var asset_anim_duration: float = maxf(0.0, float(config.get("asset_anim_duration", 0.0)))
	var asset_anim_loop: bool = bool(config.get("asset_anim_loop", true))
	var show_text: bool = bool(config.get("show_text", true))
	var text_color_hex: String = str(config.get("text_color", "#FFFFFF"))
	
	var letter_spacing: int = int(config.get("letter_spacing", 0))
	
	# Reset state
	button.icon = null
	# Clear existing children that might be anims (if reused) or specific nodes
	for child in button.get_children():
		if child.name == "BgAnim": child.queue_free()
	
	var has_visual_bg: bool = false
	
	# 1. GESTION ASSET ANIMÉ (Priorité 1)
	if asset_anim != "" and ResourceLoader.exists(asset_anim):
		var frames: Resource = load(asset_anim)
		if frames is SpriteFrames:
			has_visual_bg = true
			# Style transparent pour le bouton (plus de cadre gris)
			var style_empty = StyleBoxEmpty.new()
			_apply_style_override(button, style_empty)
			
			# Ajouter AnimatedSprite2D
			var anim = AnimatedSprite2D.new()
			anim.name = "BgAnim"
			VFXManager.play_sprite_frames(
				anim,
				frames as SpriteFrames,
				&"default",
				asset_anim_loop,
				asset_anim_duration
			)
			anim.show_behind_parent = true 
			button.add_child(anim)
			
			# Centrage initial et connexion signal
			_center_child_sprite(button, anim)
			if not button.resized.is_connected(_center_child_sprite.bind(button, anim)):
				button.resized.connect(_center_child_sprite.bind(button, anim))
				
			# Scale logic (simple fit)
			var tex = frames.get_frame_texture("default", 0)
			if tex:
				# anim.scale can be computed here if needed in the future.
				# Current behavior keeps native animation scale.
				pass
	
	# 2. GESTION ASSET STATIQUE (Priorité 2)
	elif asset_path != "" and ResourceLoader.exists(asset_path):
		var style := UIStyle.build_texture_stylebox(asset_path, config, 10)
		if style:
			has_visual_bg = true
			_apply_style_override(button, style)
	
	# 3. TEXTE
	if show_text:
		button.text = LocaleManager.t(translation_key)
		
		# Appliquer la couleur personnalisée
		var col := Color(text_color_hex)
		button.add_theme_color_override("font_color", col)
		button.add_theme_color_override("font_pressed_color", col)
		button.add_theme_color_override("font_hover_color", col)
		button.add_theme_color_override("font_focus_color", col)
		
		# Appliquer l'espacement des lettres (letter_spacing)
		if letter_spacing != 0:
			var current_font = button.get_theme_font("font")
			if current_font:
				var fv = FontVariation.new()
				fv.base_font = current_font
				fv.spacing_glyph = letter_spacing
				button.add_theme_font_override("font", fv)
		
		if has_visual_bg:
			# Améliorer la lisibilité du texte sur une image
			button.add_theme_constant_override("outline_size", 4)
			button.add_theme_color_override("font_outline_color", Color.BLACK)
	else:
		button.text = ""

func _apply_style_override(btn: Button, style: StyleBox) -> void:
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)
	# btn.add_theme_stylebox_override("disabled", style) 

func _center_child_sprite(btn: Control, sprite: Node2D) -> void:
	sprite.position = btn.size / 2

func _apply_translations() -> void:
	title_label.text = LocaleManager.t("app_title")

func _update_info() -> void:
	var _profile := ProfileManager.get_active_profile()
	
	# Cristaux
	var crystals: int = ProfileManager.get_crystals()
	if crystal_label:
		crystal_label.text = str(crystals)
	
	# Player Level
	var player_level := ProfileManager.get_player_level()
	if level_label:
		level_label.text = "Nv." + str(player_level) + "  " + str(ProfileManager.get_levels_cleared_with_max_override()) + "/" + str(ProfileManager.get_max_levels_override())
	
	# Ship preview (visual)
	_update_ship_preview()

func _update_ship_preview() -> void:
	var ship_id := ProfileManager.get_active_ship_id()
	var ship := DataManager.get_ship(ship_id)
	var ship_name := str(ship.get("name", ship_id))
	
	# Clear existing preview
	for child in ship_preview.get_children():
		child.queue_free()
	
	var visual_data: Dictionary = ship.get("visual", {})
	var asset_path: String = str(visual_data.get("asset", ""))
	var asset_anim: String = str(visual_data.get("asset_anim", ""))

	var ship_tex: Texture2D = _load_texture_from_resource_path(asset_path)
	if ship_tex == null:
		ship_tex = _load_texture_from_resource_path(asset_anim)

	if ship_tex:
		var ship_icon := TextureRect.new()
		ship_icon.texture = ship_tex
		ship_icon.custom_minimum_size = Vector2(56, 56)
		ship_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ship_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ship_preview.add_child(ship_icon)
		return

	var ship_label := Label.new()
	ship_label.text = ship_name
	ship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ship_label.add_theme_font_size_override("font_size", 20)
	ship_preview.add_child(ship_label)

func _request_menu_prewarm() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("request_menu_prewarm"):
		switcher.call_deferred("request_menu_prewarm")

func _goto_from_home(scene_path: String) -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen(scene_path)

func _exit_tree() -> void:
	_stop_home_crystal_for_transition()

# =============================================================================
# NAVIGATION
# =============================================================================

func _on_play_pressed() -> void:
	_goto_from_home("res://scenes/WorldSelect.tscn")

func _on_ship_pressed() -> void:
	_goto_from_home("res://scenes/ShipMenu.tscn")

func _on_skills_pressed() -> void:
	_goto_from_home("res://scenes/SkillsMenu.tscn")

func _on_options_pressed() -> void:
	_goto_from_home("res://scenes/OptionsMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_change_profile_pressed() -> void:
	_goto_from_home("res://scenes/ProfileSelect.tscn")

func _on_unlock_all_pressed() -> void:
	if not OS.has_feature("editor"):
		return
	if unlock_all_button == null:
		return

	var profile := ProfileManager.get_active_profile()
	if profile.is_empty():
		return

	for world_variant in App.get_worlds():
		if not (world_variant is Dictionary):
			continue
		var world_id: String = str((world_variant as Dictionary).get("id", ""))
		if world_id == "":
			continue

		var levels_per_world: int = max(1, App.get_world_level_count(world_id))
		ProfileManager.complete_level(world_id, levels_per_world - 1, levels_per_world)

	ProfileManager.save_to_disk()

	unlock_all_button.disabled = true
	unlock_all_button.text = "Unlocked!"
	await get_tree().create_timer(1.0).timeout
	unlock_all_button.disabled = false
	unlock_all_button.text = "Unlock All Worlds"
