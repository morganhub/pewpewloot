extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")
const HOMESCREEN_BUTTONS_SECTION := "homescreen_buttons"
const LEGACY_HOME_BUTTONS_SECTION := "home_buttons"

## HomeScreen — Écran d'accueil avec vaisseau central et boutons d'accès rapide
## (skills, équipement, jouer). Le vaisseau peut être tappé pour ouvrir le ShipMenu.

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var background_rect: TextureRect = $Background
@onready var menu_header: Control = $MenuHeader

@onready var ship_display: Control = $ShipDisplay
@onready var ship_preview_button: TextureButton = $ShipDisplay/ShipPreviewButton
@onready var ship_preview_icon: TextureRect = $ShipDisplay/ShipPreviewButton/ShipPreviewIcon
@onready var ship_preview_anim: AnimatedSprite2D = $ShipDisplay/ShipPreviewButton/ShipPreviewAnim
@onready var change_ship_label: Label = $ShipDisplay/ChangeShipLabel
@onready var skills_button: Button = $ShipDisplay/SkillsButton
@onready var equipment_button: Button = $ShipDisplay/EquipmentButton

@onready var play_button: Button = $BottomSection/PlayButton
@onready var options_button: Button = $BottomSection/SecondaryRow/OptionsButton
@onready var change_profile_button: Button = $BottomSection/SecondaryRow/ChangeProfileButton
@onready var quit_button: Button = $BottomSection/SecondaryRow/QuitButton
# "Continuer l'histoire" : créé par code (lance directement le dernier niveau
# débloqué du mode Histoire, sans passer par WorldSelect/LevelSelect).
var continue_story_button: Button = null
var _game_config: Dictionary = {}
var _button_grid: Control = null
var _skills_alert_icon: TextureRect = null
var _equipment_alert_icon: TextureRect = null
var _first_profile_layer: CanvasLayer = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_game_config()
	_ensure_continue_story_button()
	App.play_menu_music()
	_setup_background()
	_apply_home_button_styles()
	_apply_home_grid_layout()
	_setup_alert_icons()
	_apply_translations()
	_setup_ship_preview()
	_refresh_alert_icons()
	if menu_header and menu_header.has_signal("crystals_pressed"):
		if not menu_header.crystals_pressed.is_connected(_on_crystals_header_pressed):
			menu_header.crystals_pressed.connect(_on_crystals_header_pressed)
	_request_menu_prewarm()

	if ship_preview_button and not ship_preview_button.pressed.is_connected(_on_ship_pressed):
		ship_preview_button.pressed.connect(_on_ship_pressed)
	if play_button and not play_button.pressed.is_connected(_on_play_pressed):
		play_button.pressed.connect(_on_play_pressed)
	if continue_story_button and not continue_story_button.pressed.is_connected(_on_continue_story_pressed):
		continue_story_button.pressed.connect(_on_continue_story_pressed)
	if skills_button and not skills_button.pressed.is_connected(_on_skills_pressed):
		skills_button.pressed.connect(_on_skills_pressed)
	if equipment_button and not equipment_button.pressed.is_connected(_on_equipment_pressed):
		equipment_button.pressed.connect(_on_equipment_pressed)
	if options_button and not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)
	if change_profile_button and not change_profile_button.pressed.is_connected(_on_change_profile_pressed):
		change_profile_button.pressed.connect(_on_change_profile_pressed)
	if quit_button and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)

	_update_change_profile_visibility()
	_update_continue_story_visibility()
	_maybe_show_first_profile_modal()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		if not ProfileManager.has_any_profile():
			_maybe_show_first_profile_modal()
		if menu_header != null and menu_header.has_method("refresh"):
			menu_header.refresh()
		_setup_ship_preview()
		_refresh_alert_icons()
		# Réévalué à chaque retour sur l'accueil : l'histoire peut se terminer
		# (bouton retiré) ou être reset (bouton de retour).
		_update_continue_story_visibility()
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_home_grid_layout()
		_refresh_alert_icons()

func _load_game_config() -> void:
	if DataManager:
		_game_config = DataManager.get_game_config()
	else:
		_game_config = {}

func _setup_background() -> void:
	var menu_config: Dictionary = _get_home_screen_config()
	var bg_path: String = str(menu_config.get("background", ""))
	if bg_path == "":
		bg_path = str(_game_config.get("main_menu", {}).get("background", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var tex = load(bg_path)
		if tex and background_rect:
			background_rect.texture = tex
			background_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	elif background_rect:
		background_rect.visible = false

# =============================================================================
# BUTTON STYLES
# =============================================================================

func _get_home_buttons_config() -> Dictionary:
	var home_cfg: Dictionary = _get_home_screen_config()
	var buttons_v: Variant = home_cfg.get("buttons", {})
	if buttons_v is Dictionary:
		return buttons_v as Dictionary
	var section: Variant = _game_config.get(HOMESCREEN_BUTTONS_SECTION, {})
	if section is Dictionary:
		return section as Dictionary
	var legacy_section: Variant = _game_config.get(LEGACY_HOME_BUTTONS_SECTION, {})
	return legacy_section if legacy_section is Dictionary else {}

func _get_home_button_config(button_key: String) -> Dictionary:
	var section := _get_home_buttons_config()
	var cfg := {
		"text_color": str(section.get("default_text_color", "#FFFFFF")),
		"text_size": int(section.get("default_text_size", 24)),
		"letter_spacing": int(section.get("default_letter_spacing", 0)),
		"stretch_horizontal": str(section.get("default_stretch_horizontal", "stretch")),
		"stretch_vertical": str(section.get("default_stretch_vertical", "stretch")),
		"shadow_size": str(section.get("default_shadow_size", "medium"))
	}
	var default_nine_slice: Variant = section.get("default_nine_slice", {})
	if default_nine_slice is Dictionary:
		cfg["nine_slice"] = (default_nine_slice as Dictionary).duplicate(true)
	var default_content_margin: Variant = section.get("default_content_margin", {})
	if default_content_margin is Dictionary:
		cfg["content_margin"] = (default_content_margin as Dictionary).duplicate(true)

	var button_cfg: Variant = section.get(button_key, {})
	if button_cfg is Dictionary:
		for key in (button_cfg as Dictionary).keys():
			cfg[key] = (button_cfg as Dictionary)[key]
	return cfg

## Bouton "Continuer l'histoire" : même famille visuelle que "Jouer" mais avec
## son propre asset (game.json > screens.home.buttons.continue_story).
func _ensure_continue_story_button() -> void:
	if continue_story_button != null and is_instance_valid(continue_story_button):
		return
	continue_story_button = Button.new()
	continue_story_button.name = "ContinueStoryButton"
	if bottom_section_exists():
		$BottomSection.add_child(continue_story_button)
	else:
		add_child(continue_story_button)

func _apply_home_button_styles() -> void:
	_apply_home_button_style(play_button, "play")
	_apply_home_button_style(continue_story_button, "continue_story")
	_apply_home_button_style(skills_button, "skills")
	_apply_home_button_style(equipment_button, "equipment")
	_apply_home_button_style(options_button, "options")
	_apply_home_button_style(change_profile_button, "change_profile")
	_apply_home_button_style(quit_button, "quit")

func _get_home_screen_config() -> Dictionary:
	var screens_v: Variant = _game_config.get("screens", {})
	if screens_v is Dictionary:
		var home_v: Variant = (screens_v as Dictionary).get("home", {})
		if home_v is Dictionary:
			return home_v as Dictionary
	return {}

func _apply_home_grid_layout() -> void:
	var home_cfg := _get_home_screen_config()
	var layout_v: Variant = home_cfg.get("layout", {})
	if not (layout_v is Dictionary):
		return
	var grid_v: Variant = (layout_v as Dictionary).get("grid", {})
	if not (grid_v is Dictionary):
		return
	var grid_cfg := grid_v as Dictionary
	var buttons_cfg := _get_home_buttons_config()
	if buttons_cfg.is_empty():
		return

	if _button_grid == null or not is_instance_valid(_button_grid):
		_button_grid = Control.new()
		_button_grid.name = "HomeButtonGrid"
		_button_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_button_grid)
		move_child(_button_grid, get_child_count() - 1)

	var margin: float = maxf(0.0, float(grid_cfg.get("margin", 24.0)))
	var top_ratio: float = clampf(float(grid_cfg.get("top_ratio", 0.64)), 0.0, 0.95)
	var bottom_margin: float = maxf(0.0, float(grid_cfg.get("bottom_margin", 30.0)))
	var grid_rect := Rect2(
		Vector2(margin, size.y * top_ratio),
		Vector2(maxf(1.0, size.x - margin * 2.0), maxf(1.0, size.y * (1.0 - top_ratio) - bottom_margin))
	)
	_button_grid.position = grid_rect.position
	_button_grid.size = grid_rect.size

	var button_map: Dictionary = {
		"play": play_button,
		"continue_story": continue_story_button,
		"skills": skills_button,
		"equipment": equipment_button,
		"options": options_button,
		"change_profile": change_profile_button,
		"quit": quit_button
	}
	# Compaction calée en BAS de l'écran : seules les rangées contenant au
	# moins un bouton VISIBLE comptent, empilées depuis le bas de la grille.
	# Si "Continuer l'histoire" est masqué (histoire terminée), sa rangée
	# disparaît et "Jouer" descend se coller à Compétences/Équipement.
	var visible_rows: Dictionary = {}
	for button_key in button_map:
		var node_v: Variant = button_map[button_key]
		if not (node_v is Button) or not (node_v as Button).visible:
			continue
		var cfg_v: Variant = buttons_cfg.get(button_key, {})
		if not (cfg_v is Dictionary):
			continue
		var cfg := cfg_v as Dictionary
		if not cfg.has("grid_col") and not cfg.has("grid_row"):
			continue
		visible_rows[int(cfg.get("grid_row", 0))] = true
	var sorted_rows: Array = visible_rows.keys()
	sorted_rows.sort()
	var rows_from_bottom: Dictionary = {} # grid_row -> rang depuis le bas (0 = rangée du bas)
	for i in range(sorted_rows.size()):
		rows_from_bottom[sorted_rows[i]] = sorted_rows.size() - 1 - i

	for button_key in button_map:
		var node_v: Variant = button_map[button_key]
		if not (node_v is Button):
			continue
		var button := node_v as Button
		var cfg_v: Variant = buttons_cfg.get(button_key, {})
		if not (cfg_v is Dictionary):
			continue
		var cfg := cfg_v as Dictionary
		if not cfg.has("grid_col") and not cfg.has("grid_row"):
			continue
		if button.get_parent() != _button_grid:
			button.reparent(_button_grid)
		_place_button_in_grid(button, cfg, grid_cfg, rows_from_bottom)
	if bottom_section_exists():
		$BottomSection.visible = false
	_refresh_alert_icons()

func _place_button_in_grid(button: Button, cfg: Dictionary, grid_cfg: Dictionary, rows_from_bottom: Dictionary) -> void:
	var columns: int = maxi(1, int(grid_cfg.get("columns", 2)))
	var rows: int = maxi(1, int(grid_cfg.get("rows", 4)))
	var spacing_x: float = maxf(0.0, float(grid_cfg.get("spacing_x", 24.0)))
	var spacing_y: float = maxf(0.0, float(grid_cfg.get("spacing_y", 18.0)))
	var col: int = clampi(int(cfg.get("grid_col", 0)), 0, columns - 1)
	var row: int = clampi(int(cfg.get("grid_row", 0)), 0, rows - 1)
	var col_span: int = clampi(int(cfg.get("col_span", 1)), 1, columns - col)
	var row_span: int = clampi(int(cfg.get("row_span", 1)), 1, rows - row)
	var cell_w: float = (_button_grid.size.x - spacing_x * float(columns - 1)) / float(columns)
	# La hauteur de cellule reste basée sur le nombre de rangées CONFIGURÉ :
	# masquer une rangée ne dilate pas les boutons, elle libère de l'air en haut.
	var cell_h: float = (_button_grid.size.y - spacing_y * float(rows - 1)) / float(rows)
	var height: float = cell_h * float(row_span) + spacing_y * float(row_span - 1)
	# Ancrage BAS : rang 0 = collé au bas de la grille (elle-même calée au bas
	# de l'écran via bottom_margin) — robuste sur les petits écrans.
	var from_bottom: int = int(rows_from_bottom.get(row, 0))
	var y: float = _button_grid.size.y - height - float(from_bottom) * (cell_h + spacing_y)
	button.position = Vector2(float(col) * (cell_w + spacing_x), y)
	button.size = Vector2(cell_w * float(col_span) + spacing_x * float(col_span - 1), height)
	button.size_flags_horizontal = Control.SIZE_FILL
	button.size_flags_vertical = Control.SIZE_FILL

func bottom_section_exists() -> bool:
	return has_node("BottomSection")

func _get_home_alert_config() -> Dictionary:
	var home_cfg := _get_home_screen_config()
	var alert_v: Variant = home_cfg.get("alert", {})
	return alert_v if alert_v is Dictionary else {}

func _setup_alert_icons() -> void:
	_skills_alert_icon = _create_or_update_alert_icon(skills_button, "SkillsAlertIcon")
	_equipment_alert_icon = _create_or_update_alert_icon(equipment_button, "EquipmentAlertIcon")
	_refresh_alert_icons()

func _create_or_update_alert_icon(button: Button, icon_name: String) -> TextureRect:
	if button == null:
		return null
	var icon: TextureRect = button.get_node_or_null(icon_name) as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = icon_name
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button.add_child(icon)
	var cfg := _get_home_alert_config()
	var asset_path: String = str(cfg.get("asset", ""))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		icon.texture = ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	return icon

func _refresh_alert_icons() -> void:
	_update_alert_icon_layout(_skills_alert_icon, skills_button)
	_update_alert_icon_layout(_equipment_alert_icon, equipment_button)
	if _skills_alert_icon != null and is_instance_valid(_skills_alert_icon):
		_skills_alert_icon.visible = ProfileManager.get_skill_points() > 0
	if _equipment_alert_icon != null and is_instance_valid(_equipment_alert_icon):
		var has_unseen_equipment := false
		if ProfileManager.has_method("has_unseen_equipment_items"):
			has_unseen_equipment = bool(ProfileManager.call("has_unseen_equipment_items"))
		_equipment_alert_icon.visible = has_unseen_equipment

func _update_alert_icon_layout(icon: TextureRect, button: Button) -> void:
	if icon == null or button == null or not is_instance_valid(icon):
		return
	var cfg := _get_home_alert_config()
	var w: float = maxf(1.0, float(cfg.get("width", 34.0)))
	var h: float = maxf(1.0, float(cfg.get("height", 34.0)))
	var offset_x: float = float(cfg.get("offset_x", -10.0))
	var offset_y: float = float(cfg.get("offset_y", 8.0))
	icon.size = Vector2(w, h)
	icon.position = Vector2(button.size.x - w + offset_x, offset_y)

func _apply_home_button_style(button: Button, button_key: String) -> void:
	if button == null:
		return
	var cfg := _get_home_button_config(button_key)
	var min_width: float = float(cfg.get("min_width", 0.0))
	var min_height: float = float(cfg.get("min_height", 0.0))
	if min_width > 0.0 or min_height > 0.0:
		button.custom_minimum_size = Vector2(maxf(min_width, 0.0), maxf(min_height, 0.0))

	var asset_path: String = str(cfg.get("asset", ""))
	if asset_path != "":
		UIStyle.apply_validation_to_button(button, cfg, str(cfg.get("font_preset", "medium")))
	else:
		var font_cfg := UIStyle.get_button_font_preset(str(cfg.get("font_preset", "medium")))
		button.add_theme_font_size_override("font_size", int(cfg.get("text_size", font_cfg.get("font_size", 18))))

func _apply_home_button_shadow(button: Button, button_key: String) -> void:
	if button == null:
		return
	var cfg := _get_home_button_config(button_key)
	UIStyle.apply_button_shadow(button, str(cfg.get("shadow_size", "medium")))

# =============================================================================
# SHIP PREVIEW (centered, animated when possible)
# =============================================================================

func _setup_ship_preview() -> void:
	if not ship_preview_button or not is_node_ready():
		return
	var ship_id: String = ProfileManager.get_active_ship_id()
	if ship_id == "":
		return
	var ship_data: Dictionary = DataManager.get_ship(ship_id)
	if ship_data.is_empty():
		return
	_hydrate_ship_preview(ship_data)

func _hydrate_ship_preview(ship_data: Dictionary) -> void:
	var visual: Dictionary = ship_data.get("visual", {}) if ship_data.get("visual") is Dictionary else {}
	var visual_asset: String = str(visual.get("asset", ""))
	var visual_anim: String = str(visual.get("asset_anim", ""))
	var visual_anim_duration: float = maxf(0.0, float(visual.get("asset_anim_duration", 0.0)))
	var visual_anim_loop: bool = bool(visual.get("asset_anim_loop", true))

	var preview_size: Vector2 = ship_preview_button.size
	if preview_size.x <= 0.0 or preview_size.y <= 0.0:
		preview_size = Vector2(360, 360)

	if ship_preview_icon:
		ship_preview_icon.visible = true
		ship_preview_icon.texture = null

	var anim_frames: SpriteFrames = null
	if visual_anim != "" and ResourceLoader.exists(visual_anim):
		var anim_res: Resource = ResourceLoader.load(visual_anim, "", ResourceLoader.CACHE_MODE_REUSE)
		if anim_res is SpriteFrames:
			anim_frames = anim_res as SpriteFrames

	var static_tex: Texture2D = null
	if visual_asset != "" and ResourceLoader.exists(visual_asset):
		var asset_res: Resource = ResourceLoader.load(visual_asset, "", ResourceLoader.CACHE_MODE_REUSE)
		if asset_res is Texture2D:
			static_tex = asset_res as Texture2D
		elif asset_res is SpriteFrames and anim_frames == null:
			anim_frames = asset_res as SpriteFrames

	if anim_frames != null and ship_preview_anim:
		var first_anim: StringName = _first_anim_name(anim_frames)
		if first_anim != &"":
			VFXManager.play_sprite_frames(
				ship_preview_anim,
				anim_frames,
				first_anim,
				visual_anim_loop,
				visual_anim_duration
			)
			ship_preview_anim.position = preview_size * 0.5
			var first_tex: Texture2D = anim_frames.get_frame_texture(first_anim, 0)
			if first_tex:
				var f_size: Vector2 = first_tex.get_size()
				if f_size.x > 0 and f_size.y > 0:
					var fit_scale: float = minf(preview_size.x / f_size.x, preview_size.y / f_size.y) * 0.85
					ship_preview_anim.scale = Vector2(fit_scale, fit_scale)
			ship_preview_anim.visible = true
			if ship_preview_icon:
				ship_preview_icon.visible = false
			return

	if ship_preview_anim:
		ship_preview_anim.visible = false
	if static_tex and ship_preview_icon:
		ship_preview_icon.texture = static_tex
		ship_preview_icon.visible = true

func _first_anim_name(frames: SpriteFrames) -> StringName:
	if frames == null:
		return &""
	if frames.has_animation(&"default"):
		return &"default"
	var names: PackedStringArray = frames.get_animation_names()
	if names.size() > 0:
		return StringName(names[0])
	return &""

# =============================================================================
# TRANSLATIONS
# =============================================================================

func _apply_translations() -> void:
	if change_ship_label:
		change_ship_label.text = LocaleManager.translate("home_touch_to_change_ship")
		var ship_cfg := _get_home_button_config("ship")
		change_ship_label.add_theme_font_size_override("font_size", int(ship_cfg.get("text_size", 18)))
		change_ship_label.add_theme_color_override("font_color", Color.from_string(str(ship_cfg.get("text_color", "#FFFFFF")), Color.WHITE))
	if play_button:
		play_button.text = LocaleManager.translate("home_play")
		_apply_home_button_shadow(play_button, "play")
	if continue_story_button:
		continue_story_button.text = LocaleManager.translate("home_continue_story")
		_apply_home_button_shadow(continue_story_button, "continue_story")
	if skills_button:
		skills_button.text = LocaleManager.translate("home_skills_button")
		_apply_home_button_shadow(skills_button, "skills")
	if equipment_button:
		equipment_button.text = LocaleManager.translate("home_equipment_button")
		_apply_home_button_shadow(equipment_button, "equipment")
	if options_button:
		options_button.text = LocaleManager.translate("home_options")
		_apply_home_button_shadow(options_button, "options")
	if change_profile_button:
		change_profile_button.text = LocaleManager.translate("home_change_profile_short")
		_apply_home_button_shadow(change_profile_button, "change_profile")
	if quit_button:
		quit_button.text = LocaleManager.translate("home_quit")
		_apply_home_button_shadow(quit_button, "quit")

# =============================================================================
# NAVIGATION
# =============================================================================

func _request_menu_prewarm() -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("request_menu_prewarm"):
		switcher.call_deferred("request_menu_prewarm")

func _goto_from_home(scene_path: String) -> void:
	var switcher := get_tree().current_scene
	if switcher and switcher.has_method("goto_screen"):
		switcher.goto_screen(scene_path)

func _on_play_pressed() -> void:
	_goto_from_home("res://scenes/GameModeSelect.tscn")

## "Continuer l'histoire" : lance directement le dernier niveau débloqué du
## mode Histoire (dernier monde débloqué -> son max_unlocked_level), même
## chemin de lancement que LevelSelect._on_play_pressed.
func _on_continue_story_pressed() -> void:
	var target: Dictionary = _find_story_continue_target()
	if target.is_empty():
		# Aucune progression lisible : retomber sur le flux classique.
		_goto_from_home("res://scenes/GameModeSelect.tscn")
		return
	var world_id: String = str(target.get("world_id", "world_1"))
	App.free_mode_active = false
	App.free_mode_wave_type = ""
	App.current_world_id = world_id
	App.set_active_override_protocols(ProfileManager.get_world_active_override_protocols(world_id))
	App.current_level_index = int(target.get("level_index", 0))
	_goto_from_home("res://scenes/Game.tscn")

## Dernier monde débloqué (dans l'ordre des mondes) -> son niveau max débloqué.
func _find_story_continue_target() -> Dictionary:
	var target: Dictionary = {"world_id": "world_1", "level_index": 0}
	if App == null or not App.has_method("get_worlds"):
		return target
	for world_v in App.get_worlds():
		if not (world_v is Dictionary):
			continue
		var world_id: String = str((world_v as Dictionary).get("id", ""))
		if world_id == "":
			continue
		var progress: Dictionary = ProfileManager.get_world_progress(world_id)
		if not bool(progress.get("unlocked", world_id == "world_1")):
			continue
		var level_count: int = maxi(1, App.get_world_level_count(world_id))
		target = {
			"world_id": world_id,
			"level_index": clampi(int(progress.get("max_unlocked_level", 0)), 0, level_count - 1)
		}
	return target

func _on_ship_pressed() -> void:
	_goto_from_home("res://scenes/ShipMenu.tscn")

func _on_skills_pressed() -> void:
	_goto_from_home("res://scenes/SkillsMenu.tscn")

func _on_equipment_pressed() -> void:
	_goto_from_home("res://scenes/EquipmentMenu.tscn")

func _on_options_pressed() -> void:
	_goto_from_home("res://scenes/OptionsMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_crystals_header_pressed() -> void:
	_goto_from_home("res://scenes/ShopMenu.tscn")

func _on_change_profile_pressed() -> void:
	_goto_from_home("res://scenes/ProfileSelect.tscn")

func _update_change_profile_visibility() -> void:
	if change_profile_button:
		var should_show: bool = ProfileManager.has_any_profile()
		if change_profile_button.visible != should_show:
			change_profile_button.visible = should_show
			_apply_home_grid_layout()

## "Continuer l'histoire" disparaît quand l'histoire est terminée ; un reset de
## progression (profil, debug) le fait réapparaître au prochain passage ici.
## Le changement de visibilité recompacte la grille (ancrage bas).
func _update_continue_story_visibility() -> void:
	if continue_story_button == null or not is_instance_valid(continue_story_button):
		return
	var should_show: bool = not _is_story_completed()
	if continue_story_button.visible == should_show:
		return
	continue_story_button.visible = should_show
	_apply_home_grid_layout()

## Histoire terminée = boss final du DERNIER monde tué (boss_killed est posé
## par complete_level quand le dernier niveau d'un monde est terminé).
func _is_story_completed() -> bool:
	if App == null or not App.has_method("get_worlds"):
		return false
	var worlds: Array = App.get_worlds()
	if worlds.is_empty():
		return false
	var last_world_v: Variant = worlds[worlds.size() - 1]
	if not (last_world_v is Dictionary):
		return false
	var world_id: String = str((last_world_v as Dictionary).get("id", ""))
	if world_id == "":
		return false
	return ProfileManager.is_world_cleared(world_id)

func _maybe_show_first_profile_modal() -> void:
	if ProfileManager.has_any_profile():
		return
	if _first_profile_layer != null and is_instance_valid(_first_profile_layer):
		return
	call_deferred("_show_first_profile_modal")

func _get_first_profile_modal_config() -> Dictionary:
	var home := _get_home_screen_config()
	var v: Variant = home.get("first_profile_modal", {})
	return v if v is Dictionary else {}

func _deep_merge_modal_cfg(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over.keys():
		var val: Variant = over[k]
		if val is Dictionary and out.has(k) and out[k] is Dictionary:
			out[k] = _deep_merge_modal_cfg(out[k], val as Dictionary)
		else:
			out[k] = val
	return out

func _merged_first_profile_modal_cfg() -> Dictionary:
	var defaults := {
		"canvas_layer": 80,
		"dim": {"color": [0.0, 0.0, 0.0, 0.72]},
		"panel": {"min_width": 520.0, "min_height": 260.0},
		"margins": {"left": 24, "right": 24, "top": 22, "bottom": 22},
		"content_separation": 14,
		"title": {"locale_key": "profile_first_launch_title", "font_size": 22, "color": "#FFFFFF"},
		"description": {"locale_key": "profile_first_launch_hint", "font_size": 16, "color": "#DDDDDD"},
		"name_input": {"locale_key_placeholder": "profile_select_name_hint", "font_size": 18, "max_length": 32, "min_height": 48},
		"buttons": {
			"column_separation": 12,
			"validate": {"style": "validation", "locale_key": "profile_first_launch_validate", "font_preset": "medium", "min_width": 260.0, "min_height": 52.0, "shadow_size": "medium"},
			"quit": {"style": "cancellation", "locale_key": "home_quit", "font_preset": "medium", "min_width": 260.0, "min_height": 52.0, "shadow_size": "medium"}
		}
	}
	return _deep_merge_modal_cfg(defaults, _get_first_profile_modal_config())

func _modal_dim_color(cfg: Dictionary) -> Color:
	var dim_v: Variant = cfg.get("dim", {})
	var dim: Dictionary = dim_v if dim_v is Dictionary else {}
	var arr_v: Variant = dim.get("color", [0.0, 0.0, 0.0, 0.72])
	if arr_v is Array and (arr_v as Array).size() >= 4:
		var a: Array = arr_v as Array
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Color(0.0, 0.0, 0.0, 0.72)

func _modal_label_color(hex_or_empty: String) -> Color:
	var s := hex_or_empty.strip_edges()
	if s == "":
		return Color.WHITE
	return Color.from_string(s, Color.WHITE)

func _apply_modal_action_button(btn: Button, btn_cfg: Dictionary) -> void:
	var style_id := str(btn_cfg.get("style", "validation")).to_lower()
	var preset := str(btn_cfg.get("font_preset", "medium"))
	var shadow_sz := str(btn_cfg.get("shadow_size", "medium"))
	var base: Dictionary = {}
	match style_id:
		"cancellation":
			base = UIStyle.get_cancellation_config()
		"default":
			base = UIStyle.get_default_button_style()
		_:
			base = UIStyle.get_validation_config()
	var merged: Dictionary = base.duplicate(true)
	for k in btn_cfg.keys():
		if k in ["style", "locale_key", "font_preset", "shadow_size"]:
			continue
		if btn_cfg[k] != null:
			merged[k] = btn_cfg[k]
	if style_id == "default":
		UIStyle.apply_default_button_style(btn, preset)
	else:
		UIStyle.apply_validation_to_button(btn, merged, preset)
	UIStyle.apply_button_shadow(btn, shadow_sz)

func _show_first_profile_modal() -> void:
	if ProfileManager.has_any_profile():
		return
	if _first_profile_layer != null and is_instance_valid(_first_profile_layer):
		return

	var mc := _merged_first_profile_modal_cfg()

	var layer := CanvasLayer.new()
	layer.layer = int(mc.get("canvas_layer", 80))
	layer.name = "FirstProfileModalLayer"
	add_child(layer)
	_first_profile_layer = layer

	var dim := ColorRect.new()
	dim.color = _modal_dim_color(mc)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel_v: Variant = mc.get("panel", {})
	var panel_cfg: Dictionary = panel_v if panel_v is Dictionary else {}
	var pm_w: float = float(panel_cfg.get("min_width", 520.0))
	var pm_h: float = float(panel_cfg.get("min_height", 260.0))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(pm_w, pm_h)
	var popup_config: Dictionary = _game_config.get("popups", {})
	var popup_bg_cfg: Dictionary = popup_config.get("background", {}) if popup_config.get("background") is Dictionary else {}
	var popup_bg_asset: String = str(popup_bg_cfg.get("asset", ""))
	var pm: int = int(popup_config.get("margin", 20))
	var panel_style := UIStyle.build_texture_stylebox(popup_bg_asset, popup_bg_cfg, pm)
	if panel_style:
		panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var mg_v: Variant = mc.get("margins", {})
	var mg: Dictionary = mg_v if mg_v is Dictionary else {}
	var margin_root := MarginContainer.new()
	margin_root.add_theme_constant_override("margin_left", int(mg.get("left", 24)))
	margin_root.add_theme_constant_override("margin_right", int(mg.get("right", 24)))
	margin_root.add_theme_constant_override("margin_top", int(mg.get("top", 22)))
	margin_root.add_theme_constant_override("margin_bottom", int(mg.get("bottom", 22)))
	panel.add_child(margin_root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(mc.get("content_separation", 14)))
	margin_root.add_child(vbox)

	var title_cfg_v: Variant = mc.get("title", {})
	var title_cfg: Dictionary = title_cfg_v if title_cfg_v is Dictionary else {}
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(title_cfg.get("font_size", 22)))
	title.add_theme_color_override("font_color", _modal_label_color(str(title_cfg.get("color", "#FFFFFF"))))
	title.text = LocaleManager.translate(str(title_cfg.get("locale_key", "profile_first_launch_title")))
	vbox.add_child(title)

	var desc_cfg_v: Variant = mc.get("description", {})
	var desc_cfg: Dictionary = desc_cfg_v if desc_cfg_v is Dictionary else {}
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(desc_cfg.get("font_size", 16)))
	hint.add_theme_color_override("font_color", _modal_label_color(str(desc_cfg.get("color", "#DDDDDD"))))
	hint.text = LocaleManager.translate(str(desc_cfg.get("locale_key", "profile_first_launch_hint")))
	vbox.add_child(hint)

	var ni_v: Variant = mc.get("name_input", {})
	var ni: Dictionary = ni_v if ni_v is Dictionary else {}
	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(0, float(ni.get("min_height", 48)))
	name_edit.max_length = int(ni.get("max_length", 32))
	name_edit.text = ProfileManager.get_suggested_player_display_name()
	name_edit.placeholder_text = LocaleManager.translate(str(ni.get("locale_key_placeholder", "profile_select_name_hint")))
	name_edit.add_theme_font_size_override("font_size", int(ni.get("font_size", 18)))
	vbox.add_child(name_edit)

	var btn_wrap_v: Variant = mc.get("buttons", {})
	var btn_wrap: Dictionary = btn_wrap_v if btn_wrap_v is Dictionary else {}
	var col_sep: int = int(btn_wrap.get("column_separation", 12))

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", col_sep)
	btn_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn_col)

	var val_cfg_v: Variant = btn_wrap.get("validate", {})
	var val_btn_cfg: Dictionary = val_cfg_v if val_cfg_v is Dictionary else {}
	var validate_btn := Button.new()
	validate_btn.custom_minimum_size = Vector2(float(val_btn_cfg.get("min_width", 260)), float(val_btn_cfg.get("min_height", 52)))
	_apply_modal_action_button(validate_btn, val_btn_cfg)
	validate_btn.text = LocaleManager.translate(str(val_btn_cfg.get("locale_key", "profile_first_launch_validate")))
	btn_col.add_child(validate_btn)

	var quit_cfg_v: Variant = btn_wrap.get("quit", {})
	var quit_btn_cfg: Dictionary = quit_cfg_v if quit_cfg_v is Dictionary else {}
	var quit_btn := Button.new()
	quit_btn.custom_minimum_size = Vector2(float(quit_btn_cfg.get("min_width", 260)), float(quit_btn_cfg.get("min_height", 52)))
	_apply_modal_action_button(quit_btn, quit_btn_cfg)
	quit_btn.text = LocaleManager.translate(str(quit_btn_cfg.get("locale_key", "home_quit")))
	btn_col.add_child(quit_btn)

	quit_btn.pressed.connect(func(): get_tree().quit())

	var _refresh_validate_enabled := func():
		var ok: bool = name_edit.text.strip_edges().length() >= 2
		validate_btn.disabled = not ok

	name_edit.text_changed.connect(func(_t): _refresh_validate_enabled.call())
	_refresh_validate_enabled.call()

	validate_btn.pressed.connect(func():
		var raw_name := name_edit.text.strip_edges()
		if raw_name.length() < 2:
			return
		ProfileManager.create_profile(raw_name)
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
		_first_profile_layer = null
		_update_change_profile_visibility()
		_update_continue_story_visibility()
		if menu_header != null and menu_header.has_method("refresh"):
			menu_header.refresh()
		_setup_ship_preview()
		_refresh_alert_icons()
	)

func prepare_for_transition() -> void:
	if _first_profile_layer != null and is_instance_valid(_first_profile_layer):
		_first_profile_layer.queue_free()
		_first_profile_layer = null
