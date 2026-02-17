extends Control

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
@onready var profile_info: HBoxContainer = $TopSection/ProfileInfo
@onready var crystal_label: Label = $TopSection/ProfileInfo/CrystalLabel
@onready var ship_preview: Control = $TopSection/ProfileInfo/ShipPreview

@onready var play_button: Button = $BottomSection/PlayButton
@onready var ship_button: Button = $BottomSection/ShipButton
@onready var skills_button: Button = $BottomSection/SkillsButton
@onready var options_button: Button = $BottomSection/OptionsButton
@onready var quit_button: Button = $BottomSection/QuitButton
@onready var change_profile_button: Button = $BottomSection/ChangeProfileButton
@onready var generate_patterns_button: Button = $BottomSection/GeneratePatternsButton

const PATTERN_GENERATOR_SCRIPT = preload("res://tools/PatternGenerator.gd")
var _generator_default_text: String = "Generate Move Paths"

var _game_config: Dictionary = {}

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
	_apply_translations()
	_update_info()
	
	# Connect signals
	play_button.pressed.connect(_on_play_pressed)
	ship_button.pressed.connect(_on_ship_pressed)
	skills_button.pressed.connect(_on_skills_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	change_profile_button.pressed.connect(_on_change_profile_pressed)
	
	# Temporary dev button (editor only): regenerate movement curve resources.
	if generate_patterns_button:
		generate_patterns_button.visible = OS.has_feature("editor")
		if generate_patterns_button.visible:
			_generator_default_text = generate_patterns_button.text
			generate_patterns_button.pressed.connect(_on_generate_patterns_pressed)

func _load_game_config() -> void:
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			_game_config = json.data

func _setup_layout() -> void:
	# Layout is handled by anchors
	pass

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
	var logo_anim_duration: float = maxf(0.0, float(menu_config.get("logo_anim_duration", 0.0)))
	var logo_anim_loop: bool = bool(menu_config.get("logo_anim_loop", true))
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
	
	# Priority 1: Animated Logo
	if logo_anim_path != "" and ResourceLoader.exists(logo_anim_path):
		var frames: Resource = load(logo_anim_path)
		if frames is SpriteFrames and logo_anim:
			VFXManager.play_sprite_frames(
				logo_anim,
				frames as SpriteFrames,
				&"default",
				logo_anim_loop,
				logo_anim_duration
			)
			
			# Center and scale (contain) animation in container
			if not logo_anim_container.resized.is_connected(_center_logo_anim):
				logo_anim_container.resized.connect(_center_logo_anim)
			_center_logo_anim()
			
			# Start animation (scale from 0 to 1, fade in)
			logo_anim_container.scale = Vector2.ZERO
			logo_anim_container.modulate.a = 0.0
			logo_anim_container.pivot_offset = target_size / 2
			
			var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(logo_anim_container, "scale", Vector2.ONE, 3.0)
			tween.tween_property(logo_anim_container, "modulate:a", 1.0, 3.0)
			
			if logo_anim_container: logo_anim_container.visible = true
			title_label.visible = false
			return

	# Priority 2: Static Logo
	if logo_path != "" and ResourceLoader.exists(logo_path):
		var tex = load(logo_path)
		if tex and logo_texture:
			logo_texture.texture = tex
			logo_texture.visible = true
			title_label.visible = false
			
			# Start animation (scale from 0 to 1, fade in)
			logo_texture.pivot_offset = target_size / 2
			logo_texture.scale = Vector2.ZERO
			logo_texture.modulate.a = 0.0
			
			var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(logo_texture, "scale", Vector2.ONE, 3.0)
			tween.tween_property(logo_texture, "modulate:a", 1.0, 3.0)
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
	
	_setup_single_button(play_button, buttons_config.get("play", {}), "home_play")
	_setup_single_button(ship_button, buttons_config.get("ship", {}), "home_ship_menu")
	_setup_single_button(options_button, buttons_config.get("options", {}), "home_options")
	_setup_single_button(quit_button, buttons_config.get("quit", {}), "home_quit")
	_setup_single_button(skills_button, buttons_config.get("skills", {}), "home_skills")
	_setup_single_button(change_profile_button, buttons_config.get("change_profile", {}), "home_change_profile_short")

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
		var tex = load(asset_path)
		if tex:
			has_visual_bg = true
			var style = StyleBoxTexture.new()
			style.texture = tex
			# On garde la couleur originale
			
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
		crystal_label.text = "💎 " + str(crystals)
	
	# Total Power
	var ship_id := ProfileManager.get_active_ship_id()
	var total_power := StatsCalculator.calculate_total_power(ship_id)
	# Display in crystal_label for now (or add a new label)
	if crystal_label:
		crystal_label.text += "  ⚡ " + str(total_power)
	
	# Player Level
	var player_level := ProfileManager.get_player_level()
	if crystal_label:
		crystal_label.text += "  🌟 Nv." + str(player_level)
	
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
	var _asset_path: String = str(visual_data.get("asset", ""))
	var _asset_anim: String = str(visual_data.get("asset_anim", ""))
	
	# Create ship label
	var ship_label := Label.new()
	ship_label.text = "🚀 " + ship_name
	ship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ship_label.add_theme_font_size_override("font_size", 24)  # +50% from default ~16
	ship_preview.add_child(ship_label)

# =============================================================================
# NAVIGATION
# =============================================================================

func _on_play_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/WorldSelect.tscn")

func _on_ship_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/ShipMenu.tscn")

func _on_skills_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/SkillsMenu.tscn")

func _on_options_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/OptionsMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_change_profile_pressed() -> void:
	var switcher := get_tree().current_scene
	switcher.goto_screen("res://scenes/ProfileSelect.tscn")

func _on_generate_patterns_pressed() -> void:
	if not OS.has_feature("editor"):
		return
	if generate_patterns_button == null:
		return

	generate_patterns_button.disabled = true
	generate_patterns_button.text = "Generating..."

	var generator: PatternGenerator = PATTERN_GENERATOR_SCRIPT.new() as PatternGenerator
	if generator != null:
		generator.generate_all_curves()
		if DataManager and DataManager.has_method("reload_all"):
			DataManager.reload_all()
		generate_patterns_button.text = "Generated"
	else:
		generate_patterns_button.text = "Generation Failed"

	await get_tree().create_timer(1.0).timeout
	generate_patterns_button.disabled = false
	generate_patterns_button.text = _generator_default_text
