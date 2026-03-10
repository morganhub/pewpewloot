extends Control
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

## ShopMenu — Achat de cristaux (simulation store).

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var back_button: TextureButton = %BackButton
@onready var packs_grid: GridContainer = %PacksGrid
@onready var confirm_popup: PanelContainer = %ConfirmPopup
@onready var confirm_title: Label = %ConfirmTitle
@onready var confirm_message: Label = %ConfirmMessage
@onready var confirm_buy_btn: Button = %ConfirmBuyBtn
@onready var cancel_btn: Button = %CancelBtn
@onready var background: TextureRect = $Background
@onready var margin_container: MarginContainer = $MarginContainer

# =============================================================================
# ÉTAT
# =============================================================================

var _game_config: Dictionary = {}
var _selected_pack: Dictionary = {}

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Load config
	_game_config = DataManager.get_game_config()
	_apply_menu_header_offset()
	var mh: Control = get_node_or_null("MenuHeader")
	if mh and mh.has_signal("crystals_pressed") and not mh.crystals_pressed.is_connected(_on_header_crystals_pressed):
		mh.crystals_pressed.connect(_on_header_crystals_pressed)
	
	# Connexions
	if back_button: back_button.pressed.connect(_on_back_pressed)
	if confirm_buy_btn: confirm_buy_btn.pressed.connect(_on_confirm_buy_pressed)
	if cancel_btn: cancel_btn.pressed.connect(func(): confirm_popup.visible = false)
	
	confirm_popup.visible = false
	
	_setup_visuals()
	_populate_packs()

func _apply_menu_header_offset() -> void:
	if margin_container == null:
		return
	var h: Variant = _game_config.get("menu_header", {})
	if h is Dictionary:
		var height_px: int = int((h as Dictionary).get("height_px", 72))
		var margin_t: int = int((h as Dictionary).get("margin_top", 8))
		margin_container.add_theme_constant_override("margin_top", height_px + margin_t + 45)

# =============================================================================
# VISUALS
# =============================================================================

func _setup_visuals() -> void:
	var shop_cfg: Dictionary = _game_config.get("shop_menu", {})
	var main_cfg: Dictionary = _game_config.get("main_menu", {})
	
	# Background
	var bg_path: String = str(shop_cfg.get("background", main_cfg.get("background", "")))
	if bg_path != "" and ResourceLoader.exists(bg_path) and background:
		background.texture = load(bg_path)
	
	# Popup Styling
	var popups_cfg: Dictionary = _game_config.get("popups", {})
	var popup_bg_cfg: Dictionary = popups_cfg.get("background", {}) if popups_cfg.get("background") is Dictionary else {}
	var popup_bg_asset: String = str(popup_bg_cfg.get("asset", ""))
	var margin: int = int(popups_cfg.get("margin", 20))
	
	var style := UIStyle.build_texture_stylebox(popup_bg_asset, popup_bg_cfg, margin)
	if style:
		confirm_popup.add_theme_stylebox_override("panel", style)

	if confirm_buy_btn:
		UIStyle.apply_default_button_style(confirm_buy_btn, "medium")
	if cancel_btn:
		UIStyle.apply_default_button_style(cancel_btn, "medium")
	
	# Footer : clique sur le bouton retour du bas
	var footer: Node = get_node_or_null("MenuFooter")
	if footer and footer.has_signal("back_pressed") and not footer.back_pressed.is_connected(_on_back_pressed):
		footer.back_pressed.connect(_on_back_pressed)
	if back_button:
		back_button.visible = false

# =============================================================================
# PACKS
# =============================================================================

func _populate_packs() -> void:
	for child in packs_grid.get_children():
		child.queue_free()
	
	var shop_cfg: Dictionary = _game_config.get("shop_menu", {})
	var packs: Array = shop_cfg.get("packs", [])
	var btn_cfg: Dictionary = shop_cfg.get("button", {}) if shop_cfg.get("button") is Dictionary else {}
	var btn_asset: String = str(btn_cfg.get("asset", ""))
	var btn_text_color: Color = Color(btn_cfg.get("text_color", "#000000"))
	var btn_font_size: int = int(btn_cfg.get("font_size", 18))
	var crystal_cfg := _get_shared_crystal_icon_cfg()
	var crystal_icon_path := str(crystal_cfg.get("asset", "")).strip_edges()
	var crystal_icon_texture: Texture2D = null
	var crystal_icon_frames: SpriteFrames = null
	if DataManager and DataManager.has_method("get_texture_from_resource_path"):
		crystal_icon_texture = DataManager.get_texture_from_resource_path(crystal_icon_path)
	if crystal_icon_texture == null and crystal_icon_path != "" and ResourceLoader.exists(crystal_icon_path):
		var icon_res: Resource = ResourceLoader.load(crystal_icon_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if icon_res is Texture2D:
			crystal_icon_texture = icon_res as Texture2D
		elif icon_res is SpriteFrames:
			crystal_icon_frames = icon_res as SpriteFrames
	if crystal_icon_frames == null and crystal_icon_path != "" and ResourceLoader.exists(crystal_icon_path):
		var frames_res: Resource = ResourceLoader.load(crystal_icon_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if frames_res is SpriteFrames:
			crystal_icon_frames = frames_res as SpriteFrames
	
	for pack in packs:
		if not pack is Dictionary:
			continue
		var p: Dictionary = pack as Dictionary
		var crystals: int = int(p.get("crystals", 0))
		var price: float = float(p.get("price_usd", 0.0))
		
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 100)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.text = str(crystals) + "\n$" + str(price)
		if crystal_icon_texture:
			btn.icon = crystal_icon_texture
		if crystal_icon_frames:
			_attach_shop_crystal_anim(btn, crystal_icon_frames, crystal_cfg)
		btn.add_theme_font_size_override("font_size", btn_font_size)
		btn.add_theme_color_override("font_color", btn_text_color)
		
		# Style
		var style := UIStyle.build_texture_stylebox(btn_asset, btn_cfg, 10)
		if style:
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
			btn.add_theme_stylebox_override("focus", style)
		
		btn.pressed.connect(func(): _on_pack_pressed(p))
		packs_grid.add_child(btn)
		UIStyle.apply_button_shadow(btn, "medium")

func _get_shared_crystal_icon_cfg() -> Dictionary:
	if DataManager and DataManager.has_method("get_shared_crystal_icon_config"):
		return DataManager.get_shared_crystal_icon_config()
	var fallback_path := "res://assets/ui/icons/crystal.png"
	if DataManager and DataManager.has_method("get_shared_crystal_icon_path"):
		fallback_path = str(DataManager.get_shared_crystal_icon_path())
	return {
		"asset": fallback_path,
		"animation_repeat_seconds": 0.0,
		"animation_type": "loop",
		"animation_duration": 2.0
	}

func _attach_shop_crystal_anim(btn: Button, frames: SpriteFrames, cfg: Dictionary) -> void:
	if btn == null or frames == null:
		return

	var existing := btn.get_node_or_null("CrystalAnim")
	if existing:
		existing.queue_free()

	var anim := AnimatedSprite2D.new()
	anim.name = "CrystalAnim"
	anim.centered = true
	anim.z_index = 0
	btn.add_child(anim)
	anim.sprite_frames = frames

	call_deferred("_layout_shop_crystal_anim", btn, anim)
	_play_shop_crystal_anim(anim, cfg)

func _layout_shop_crystal_anim(btn: Button, anim: AnimatedSprite2D) -> void:
	if btn == null or anim == null or not is_instance_valid(anim):
		return
	anim.position = Vector2(30.0, btn.size.y * 0.5)

	var frames: SpriteFrames = anim.sprite_frames
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
	var fit_scale := minf(30.0 / frame_size.x, 30.0 / frame_size.y)
	anim.scale = Vector2(fit_scale, fit_scale)

func _play_shop_crystal_anim(anim: AnimatedSprite2D, cfg: Dictionary) -> void:
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
		_repeat_shop_crystal_anim(anim, anim_name, repeat_seconds, play_duration, play_loop)

func _repeat_shop_crystal_anim(
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

func _stop_shop_crystal_for_transition() -> void:
	for child in packs_grid.get_children():
		if not (child is Button):
			continue
		var btn := child as Button
		btn.icon = null
		var anim_node := btn.get_node_or_null("CrystalAnim")
		if anim_node is AnimatedSprite2D:
			var anim := anim_node as AnimatedSprite2D
			anim.stop()
			anim.visible = false
			anim.queue_free()

func prepare_for_transition() -> void:
	_stop_shop_crystal_for_transition()

func _exit_tree() -> void:
	_stop_shop_crystal_for_transition()

# =============================================================================
# ACTIONS
# =============================================================================

func _on_pack_pressed(pack: Dictionary) -> void:
	_selected_pack = pack
	var crystals: int = int(pack.get("crystals", 0))
	var price: float = float(pack.get("price_usd", 0.0))
	
	confirm_title.text = LocaleManager.translate("shop_confirm_title") if LocaleManager.has_method("translate") else "Confirm Purchase"
	confirm_message.text = "Buy " + str(crystals) + " crystals for $" + str(price) + "?"
	confirm_popup.visible = true

func _on_confirm_buy_pressed() -> void:
	if _selected_pack.is_empty():
		return
	
	var crystals: int = int(_selected_pack.get("crystals", 0))
	
	# Simulate store purchase
	print("[ShopMenu] Simulating store purchase of ", crystals, " crystals...")
	
	# Add crystals to profile
	ProfileManager.add_crystals(crystals)
	print("[ShopMenu] Added ", crystals, " crystals. New total: ", ProfileManager.get_crystals())
	
	confirm_popup.visible = false
	_selected_pack = {}
	
	# Optional: Show success message or update UI
	# For now, just print to console

func _on_back_pressed() -> void:
	var switcher = get_tree().current_scene
	if switcher == null:
		return
	var prev_path: String = ""
	if switcher.has_method("get_screen_before_shop"):
		prev_path = switcher.get_screen_before_shop()
	if prev_path != "":
		if switcher.has_method("goto_screen"):
			switcher.goto_screen(prev_path)
	else:
		if switcher.has_method("goto_screen"):
			switcher.goto_screen("res://scenes/HomeScreen.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/HomeScreen.tscn")

func _on_header_crystals_pressed() -> void:
	# Already on shop; no-op or could refresh
	pass
