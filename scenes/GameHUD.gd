extends CanvasLayer

## GameHUD — Interface de jeu avec barre de vie, score, pouvoirs et pause.

signal pause_requested
signal special_requested
signal unique_requested

# References UI - TopLeft
@onready var profile_label: Label = $TopLeft/ProfileLabel
@onready var hp_bar: ProgressBar = $TopLeft/HPBar
@onready var hp_label: Label = $TopLeft/HPLabel
# Shield Bar (Dynamic)
var shield_bar: ProgressBar = null
var wave_label: Label = null

# TopRight
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var burger_btn: TextureButton = %BurgerButton

# Boss Health
@onready var boss_container: Control = $BossHealthContainer
@onready var boss_hp_bar: ProgressBar = $BossHealthContainer/BossHPBar
@onready var boss_name_label: Label = $BossHealthContainer/BossNameLabel

# Special Power Button
@onready var sp_icon: TextureRect = $BottomRight/SpecialBtnControl/Icon
@onready var sp_bar: TextureProgressBar = $BottomRight/SpecialBtnControl/CooldownBar
@onready var sp_btn: TextureButton = $BottomRight/SpecialBtnControl/Button
@onready var sp_timer_lbl: Label = $BottomRight/SpecialBtnControl/TimerLabel

# Unique Power Button
@onready var up_icon: TextureRect = $BottomRight/UniqueBtnControl/Icon
@onready var up_bar: TextureProgressBar = $BottomRight/UniqueBtnControl/CooldownBar
@onready var up_btn: TextureButton = $BottomRight/UniqueBtnControl/Button
@onready var up_timer_lbl: Label = $BottomRight/UniqueBtnControl/TimerLabel

# State
var _score: int = 0
var _player: Node2D = null
var _wave_current: int = 0
var _wave_total: int = 0
var _hp_has_custom_fill: bool = false
var _show_health_bar_values: bool = true
var _hp_fill_reveal_enabled: bool = false
var _hp_fill_reveal_material: ShaderMaterial = null
var _shield_fill_reveal_enabled: bool = false
var _shield_fill_reveal_material: ShaderMaterial = null
var _inventory_warning_label: Label = null
var _inventory_warning_timer: float = 0.0
var _inventory_warning_was_full: bool = false
var _inventory_warning_tween: Tween = null
const INVENTORY_WARNING_INTERVAL: float = 10.0
const HP_FILL_REVEAL_SHADER_CODE: String = """
shader_type canvas_item;
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (UV.x > fill_ratio) {
		c.a = 0.0;
	}
	COLOR = c;
}
"""

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_load_assets()
	_update_profile_info()
	
	# Connecter les boutons
	if burger_btn:
		if not burger_btn.pressed.is_connected(_on_burger_pressed):
			burger_btn.pressed.connect(_on_burger_pressed)
	if sp_btn:
		sp_btn.pressed.connect(func(): special_requested.emit())
	if up_btn:
		up_btn.pressed.connect(func(): unique_requested.emit())
	
	# Style pour le boss (fond noir, arrondi)
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color.BLACK
	sb_bg.corner_radius_top_left = 5
	sb_bg.corner_radius_top_right = 5
	sb_bg.corner_radius_bottom_left = 5
	sb_bg.corner_radius_bottom_right = 5
	if boss_hp_bar:
		boss_hp_bar.add_theme_stylebox_override("background", sb_bg)
	
	if boss_hp_bar:
		boss_hp_bar.add_theme_stylebox_override("background", sb_bg)
	
	_setup_hp_bar_style()
	_setup_shield_bar()
	_setup_virtual_joystick()
	_setup_notification_area()
	_setup_inventory_full_warning_ui()
	_setup_xp_display()
	_refresh_health_bar_value_visibility()
	
	add_to_group("game_hud")

var notification_area: VBoxContainer = null

func _setup_notification_area() -> void:
	notification_area = VBoxContainer.new()
	notification_area.name = "NotificationArea"
	notification_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Setup Layout (Top Right, below score)
	notification_area.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	notification_area.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	notification_area.anchor_left = 1.0
	notification_area.anchor_right = 1.0
	notification_area.offset_left = -130 # card 110 + 20 margin
	notification_area.offset_right = -20
	notification_area.offset_top = 100
	notification_area.offset_bottom = 600
	
	add_child(notification_area)

func show_loot_notification(item_data: Dictionary) -> void:
	if notification_area:
		var scene = load("res://scenes/ui/LootNotification.tscn")
		if scene:
			var notif = scene.instantiate()
			notification_area.add_child(notif)
			notif.setup(item_data)

func _load_assets() -> void:
	var game_config: Dictionary = {}
	var file := FileAccess.open("res://data/game.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			game_config = json.data
	
	var ui_icons: Dictionary = game_config.get("ui_icons", {})
	
	# Burger Icon
	var burger_path = str(ui_icons.get("burger_menu", ""))
	if burger_path != "" and ResourceLoader.exists(burger_path) and burger_btn:
		burger_btn.texture_normal = load(burger_path)
	
	# Score styling
	var score_config: Dictionary = game_config.get("score", {})
	if score_label and not score_config.is_empty():
		var s_size := int(score_config.get("text_size", 20))
		var s_color := str(score_config.get("text_color", "#FFFFFF"))
		score_label.add_theme_font_size_override("font_size", s_size)
		score_label.add_theme_color_override("font_color", Color.html(s_color))
		var s_asset := str(score_config.get("asset", ""))
		if s_asset != "" and ResourceLoader.exists(s_asset):
			var top_right := score_label.get_parent()
			if top_right:
				var score_bg := TextureRect.new()
				score_bg.name = "ScoreBg"
				score_bg.texture = load(s_asset)
				score_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				score_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				score_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
				score_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				score_label.add_child(score_bg)
				score_label.move_child(score_bg, 0)
				score_label.clip_contents = true

	# SP Icon
	var sp_path = str(ui_icons.get("super_power_placeholder", ""))
	if sp_path != "" and ResourceLoader.exists(sp_path) and sp_icon:
		sp_icon.texture = load(sp_path)
	
	# UP Icon
	var up_path = str(ui_icons.get("unique_power_placeholder", ""))
	if up_path != "" and ResourceLoader.exists(up_path) and up_icon:
		up_icon.texture = load(up_path)

func _on_burger_pressed() -> void:
	pause_requested.emit()

func _update_profile_info() -> void:
	if profile_label:
		profile_label.visible = false

func _refresh_health_bar_value_visibility() -> void:
	_show_health_bar_values = bool(ProfileManager.get_setting("show_health_bar_values", true))
	
	if hp_bar:
		var hp_value_label: Label = hp_bar.get_node_or_null("ValueLabel") as Label
		if hp_value_label:
			hp_value_label.visible = _show_health_bar_values
	
	if shield_bar:
		var shield_value_label: Label = shield_bar.get_node_or_null("ValueLabel") as Label
		if shield_value_label:
			shield_value_label.visible = _show_health_bar_values

# =============================================================================
# PLAYER REFERENCE (for cooldown tracking)
# =============================================================================

func set_player_reference(player: Node2D) -> void:
	_player = player
	if _player.has_signal("shield_changed"):
		if not _player.shield_changed.is_connected(_on_shield_changed):
			_player.shield_changed.connect(_on_shield_changed)
			
	# Init Shield UI state
	if _player.get("shield_active") == true:
		var s_curr = _player.get("shield_energy")
		var s_max = _player.get("shield_max_energy")
		_on_shield_changed(s_curr, s_max)
	else:
		_on_shield_changed(0, 100)

func _process(_delta: float) -> void:
	_update_inventory_full_warning(_delta)
	
	if not is_instance_valid(_player):
		return
	
	# Polling Special Cooldown
	if "special_cd_current" in _player and "special_cd_max" in _player:
		var current = float(_player.special_cd_current)
		var max_cd = float(_player.special_cd_max)
		_update_power_button(sp_bar, sp_btn, sp_timer_lbl, sp_icon, current, max_cd)
	
	# Polling Unique Cooldown
	if "unique_cd_current" in _player and "unique_cd_max" in _player:
		# Visibility Check
		if "unique_power_id" in _player:
			var has_up: bool = str(_player.unique_power_id) != ""
			if up_btn and up_btn.get_parent():
				up_btn.get_parent().visible = has_up
				if not has_up:
					return # Skip update
		
		var current = float(_player.unique_cd_current)
		var max_cd = float(_player.unique_cd_max)
		_update_power_button(up_bar, up_btn, up_timer_lbl, up_icon, current, max_cd)

func _setup_inventory_full_warning_ui() -> void:
	var warning_label := Label.new()
	warning_label.name = "InventoryFullWarning"
	warning_label.visible = false
	warning_label.modulate.a = 0.82
	warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label.add_theme_font_size_override("font_size", 16)
	warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25, 1.0))
	warning_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	warning_label.add_theme_constant_override("outline_size", 3)
	warning_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	warning_label.offset_left = -360.0
	warning_label.offset_right = 360.0
	warning_label.offset_top = -48.0
	warning_label.offset_bottom = -18.0
	add_child(warning_label)
	_inventory_warning_label = warning_label

func _update_inventory_full_warning(delta: float) -> void:
	if not _inventory_warning_label:
		return
	
	var current_size: int = ProfileManager.get_unequipped_inventory_count()
	var max_size: int = ProfileManager.get_max_inventory_size()
	var is_full: bool = current_size >= max_size
	if not is_full:
		_inventory_warning_was_full = false
		_inventory_warning_timer = 0.0
		if _inventory_warning_tween and _inventory_warning_tween.is_valid():
			_inventory_warning_tween.kill()
		_inventory_warning_label.visible = false
		return
	
	_inventory_warning_label.text = LocaleManager.translate(
		"inventory_full_warning_in_game",
		{
			"current": str(current_size),
			"max": str(max_size)
		}
	)
	_inventory_warning_label.visible = true
	
	if not _inventory_warning_was_full:
		_inventory_warning_was_full = true
		_inventory_warning_timer = INVENTORY_WARNING_INTERVAL
		_flash_inventory_full_warning()
		return
	
	_inventory_warning_timer -= delta
	if _inventory_warning_timer <= 0.0:
		_inventory_warning_timer = INVENTORY_WARNING_INTERVAL
		_flash_inventory_full_warning()

func _flash_inventory_full_warning() -> void:
	if not _inventory_warning_label:
		return
	if _inventory_warning_tween and _inventory_warning_tween.is_valid():
		_inventory_warning_tween.kill()
	
	_inventory_warning_label.visible = true
	_inventory_warning_label.modulate.a = 0.82
	
	_inventory_warning_tween = create_tween()
	_inventory_warning_tween.tween_property(_inventory_warning_label, "modulate:a", 1.0, 0.16)
	_inventory_warning_tween.tween_property(_inventory_warning_label, "modulate:a", 0.5, 0.16)
	_inventory_warning_tween.tween_property(_inventory_warning_label, "modulate:a", 1.0, 0.16)
	_inventory_warning_tween.tween_property(_inventory_warning_label, "modulate:a", 0.82, 0.20)
	_inventory_warning_tween.tween_callback(func():
		if _inventory_warning_label:
			_inventory_warning_label.visible = true
			_inventory_warning_label.modulate.a = 0.82
	)

func _update_power_button(bar: TextureProgressBar, btn: TextureButton, lbl: Label, icon: TextureRect, current: float, max_cd: float) -> void:
	if max_cd <= 0 or not bar or not btn or not lbl or not icon:
		return
	
	var progress_pct = (1.0 - (current / max_cd)) * 100.0
	bar.value = progress_pct
	
	if current > 0:
		btn.disabled = true
		icon.modulate = Color(0.3, 0.3, 0.3, 1)
		lbl.visible = true
		lbl.text = "%.1f" % current if current < 10 else "%d" % int(current)
		bar.tint_progress = Color(0, 0.8, 0)
	else:
		btn.disabled = false
		icon.modulate = Color.WHITE
		lbl.visible = false
		bar.tint_progress = Color(0, 1, 0)
		bar.value = 100

# =============================================================================
# VIRTUAL JOYSTICK
# =============================================================================

var virtual_joystick: Control = null

func _setup_virtual_joystick() -> void:
	var joystick_script = load("res://scenes/ui/VirtualJoystick.gd")
	if joystick_script:
		virtual_joystick = joystick_script.new()
		virtual_joystick.name = "VirtualJoystick"
		virtual_joystick.set_anchors_preset(Control.PRESET_FULL_RECT)
		virtual_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(virtual_joystick)
		move_child(virtual_joystick, get_child_count() - 1)

func get_joystick_output() -> Vector2:
	if virtual_joystick and virtual_joystick.has_method("get_output"):
		return virtual_joystick.get_output()
	return Vector2.ZERO

func get_joystick_drag_delta() -> Vector2:
	if virtual_joystick and virtual_joystick.has_method("get_drag_delta"):
		return virtual_joystick.get_drag_delta()
	return Vector2.ZERO

func is_joystick_active() -> bool:
	if virtual_joystick and virtual_joystick.has_method("is_active"):
		return virtual_joystick.is_active()
	return false

func is_on_mobile() -> bool:
	if virtual_joystick and virtual_joystick.has_method("is_mobile"):
		return virtual_joystick.is_mobile()
	return OS.has_feature("mobile")

# =============================================================================
# BOSS HEALTH
# =============================================================================

func show_boss_health(boss_name: String, max_hp: int) -> void:
	if boss_container: boss_container.visible = true
	if boss_name_label: boss_name_label.text = boss_name.to_upper()
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = max_hp
	_update_boss_bar_color(1.0)

func update_boss_health(current_hp: int, max_hp: int) -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = current_hp
	var percent := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	_update_boss_bar_color(percent)
	if current_hp <= 0 and boss_container:
		boss_container.visible = false

func _update_boss_bar_color(percent: float) -> void:
	var sb_fill := StyleBoxFlat.new()
	sb_fill.corner_radius_top_left = 5
	sb_fill.corner_radius_top_right = 5
	sb_fill.corner_radius_bottom_left = 5
	sb_fill.corner_radius_bottom_right = 5
	if percent > 0.6:
		sb_fill.bg_color = Color.GREEN
	elif percent > 0.3:
		sb_fill.bg_color = Color.YELLOW
	else:
		sb_fill.bg_color = Color.RED
	if boss_hp_bar:
		boss_hp_bar.add_theme_stylebox_override("fill", sb_fill)

# =============================================================================
# PLAYER HP
# =============================================================================

func update_player_hp(p_current_hp: int, max_hp: int) -> void:
	var current_hp = max(0, p_current_hp)
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
		
		# Update Label Text inside bar if it exists
		var lbl = hp_bar.get_node_or_null("ValueLabel")
		if lbl:
			lbl.text = "%d / %d" % [current_hp, max_hp]
			
	if hp_label:
		# Keep original label if needed, or hide it if we moved it inside
		hp_label.visible = false # We moved text inside bar
		
	var hp_percent := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	if _hp_fill_reveal_enabled and _hp_fill_reveal_material:
		_hp_fill_reveal_material.set_shader_parameter("fill_ratio", clampf(hp_percent, 0.0, 1.0))

	if hp_bar:
		if _hp_has_custom_fill:
			hp_bar.modulate = Color.WHITE
			return
		# Use Stylebox update if using flat color, or Modulate if texture
		# Keep simple modulate for now or enhance later
		if hp_percent > 0.5:
			hp_bar.modulate = Color.GREEN
		elif hp_percent > 0.25:
			hp_bar.modulate = Color.YELLOW
		else:
			hp_bar.modulate = Color.RED

func set_player_max_hp(max_hp: int) -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = max_hp
		var lbl = hp_bar.get_node_or_null("ValueLabel")
		if lbl:
			lbl.text = "%d / %d" % [max_hp, max_hp]
	if hp_label:
		hp_label.text = str(max_hp) + " / " + str(max_hp)

# =============================================================================
# SHIELD BAR
# =============================================================================

func _setup_hp_bar_style() -> void:
	if not hp_bar: return
	var config: Dictionary = DataManager.get_game_data().get("gameplay", {}).get("bars", {})
	var height: float = float(config.get("height", 40.0))
	var hp_cfg: Dictionary = config.get("hp", {}) if config.get("hp") is Dictionary else {}
	
	hp_bar.custom_minimum_size.y = height
	
	# Add internal label
	var lbl = Label.new()
	lbl.name = "ValueLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(lbl)
	
	# Style Text
	var txt_color: Color = Color(str(config.get("text_color", "#FFFFFF")))
	var txt_size: int = int(config.get("text_size", 24))
	lbl.add_theme_color_override("font_color", txt_color)
	lbl.add_theme_font_size_override("font_size", txt_size)
	
	# Background Asset for HP (frame backplate)
	var bg_asset: String = str(hp_cfg.get("background_asset", hp_cfg.get("asset", "")))
	var bg_loop: bool = bool(hp_cfg.get("background_asset_loop", true))
	var bg_duration: float = maxf(0.0, float(hp_cfg.get("background_asset_duration", 0.0)))
	var sb_bg: StyleBoxTexture = _build_stylebox_texture_from_asset(bg_asset, bg_loop, bg_duration, hp_cfg, "background_")
	if sb_bg:
		hp_bar.add_theme_stylebox_override("background", sb_bg)
	
	# Fill texture for HP
	_hp_has_custom_fill = false
	_clear_hp_fill_reveal()
	var fill_asset: String = str(hp_cfg.get("fill_asset", ""))
	var fill_render_mode: String = str(hp_cfg.get("fill_render_mode", "progressbar")).strip_edges().to_lower()
	if fill_asset != "":
		var fill_loop: bool = bool(hp_cfg.get("fill_asset_loop", true))
		var fill_duration: float = maxf(0.0, float(hp_cfg.get("fill_asset_duration", 0.0)))
		if fill_render_mode == "reveal_mask":
			var reveal_tex: Texture2D = _build_texture2d_from_asset(fill_asset, fill_loop, fill_duration)
			if reveal_tex:
				var transparent_fill := StyleBoxFlat.new()
				transparent_fill.bg_color = Color(1.0, 1.0, 1.0, 0.0)
				hp_bar.add_theme_stylebox_override("fill", transparent_fill)
				_setup_hp_fill_reveal(reveal_tex)
				_hp_has_custom_fill = true
		else:
			var sb_fill: StyleBoxTexture = _build_stylebox_texture_from_asset(fill_asset, fill_loop, fill_duration, hp_cfg, "fill_")
			if sb_fill:
				hp_bar.add_theme_stylebox_override("fill", sb_fill)
				_hp_has_custom_fill = true
	
	_apply_bar_frame_overlay(hp_bar, hp_cfg)
	_refresh_health_bar_value_visibility()

func _clear_hp_fill_reveal() -> void:
	if not hp_bar:
		return
	var existing_reveal: TextureRect = hp_bar.get_node_or_null("HPFillReveal") as TextureRect
	if existing_reveal:
		existing_reveal.queue_free()
	_hp_fill_reveal_enabled = false
	_hp_fill_reveal_material = null

func _setup_hp_fill_reveal(fill_tex: Texture2D) -> void:
	if not hp_bar or fill_tex == null:
		return

	_clear_hp_fill_reveal()
	hp_bar.clip_contents = true

	var reveal_rect := TextureRect.new()
	reveal_rect.name = "HPFillReveal"
	reveal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	reveal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reveal_rect.stretch_mode = TextureRect.STRETCH_SCALE
	reveal_rect.texture = fill_tex

	var shader := Shader.new()
	shader.code = HP_FILL_REVEAL_SHADER_CODE
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("fill_ratio", 1.0)
	reveal_rect.material = shader_mat

	hp_bar.add_child(reveal_rect)
	hp_bar.move_child(reveal_rect, 0)

	_hp_fill_reveal_enabled = true
	_hp_fill_reveal_material = shader_mat

func _setup_shield_bar() -> void:
	var top_left: VBoxContainer = $TopLeft
	if not top_left: return
	
	var config: Dictionary = DataManager.get_game_data().get("gameplay", {}).get("bars", {})
	var shield_cfg: Dictionary = config.get("shield", {}) if config.get("shield") is Dictionary else {}
	var height: float = float(config.get("height", 40.0))
	
	shield_bar = ProgressBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.show_percentage = false
	shield_bar.custom_minimum_size = Vector2(200, height) # Thick bar
	shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Internal Label
	var lbl = Label.new()
	lbl.name = "ValueLabel"
	lbl.text = "0 / 0"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	shield_bar.add_child(lbl)
	
	# Style Text
	var txt_color: Color = Color(str(config.get("text_color", "#FFFFFF")))
	var txt_size: int = int(config.get("text_size", 24))
	lbl.add_theme_color_override("font_color", txt_color)
	lbl.add_theme_font_size_override("font_size", txt_size)
	
	# Style Bar
	var sb_fill_flat := StyleBoxFlat.new()
	sb_fill_flat.bg_color = Color(0.0, 0.6, 1.0) # Blue
	sb_fill_flat.corner_radius_top_left = 5
	sb_fill_flat.corner_radius_top_right = 5
	sb_fill_flat.corner_radius_bottom_left = 5
	sb_fill_flat.corner_radius_bottom_right = 5
	var sb_fill: StyleBox = sb_fill_flat
	
	var sb_bg_flat := StyleBoxFlat.new() # Default fallback
	sb_bg_flat.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	var sb_bg: StyleBox = sb_bg_flat
	
	# Background Asset for Shield
	var bg_asset: String = str(shield_cfg.get("background_asset", shield_cfg.get("asset", "")))
	var bg_loop: bool = bool(shield_cfg.get("background_asset_loop", true))
	var bg_duration: float = maxf(0.0, float(shield_cfg.get("background_asset_duration", 0.0)))
	var bg_style: StyleBoxTexture = _build_stylebox_texture_from_asset(bg_asset, bg_loop, bg_duration, shield_cfg, "background_")
	if bg_style:
		sb_bg = bg_style
	
	# Fill Asset for Shield
	_clear_shield_fill_reveal()
	var fill_asset: String = str(shield_cfg.get("fill_asset", ""))
	var fill_render_mode: String = str(shield_cfg.get("fill_render_mode", "progressbar")).strip_edges().to_lower()
	if fill_asset != "":
		var fill_loop: bool = bool(shield_cfg.get("fill_asset_loop", true))
		var fill_duration: float = maxf(0.0, float(shield_cfg.get("fill_asset_duration", 0.0)))
		if fill_render_mode == "reveal_mask":
			var reveal_tex: Texture2D = _build_texture2d_from_asset(fill_asset, fill_loop, fill_duration)
			if reveal_tex:
				var transparent_fill := StyleBoxFlat.new()
				transparent_fill.bg_color = Color(1.0, 1.0, 1.0, 0.0)
				sb_fill = transparent_fill
		else:
			var fill_style: StyleBoxTexture = _build_stylebox_texture_from_asset(fill_asset, fill_loop, fill_duration, shield_cfg, "fill_")
			if fill_style:
				sb_fill = fill_style
	
	shield_bar.add_theme_stylebox_override("fill", sb_fill)
	shield_bar.add_theme_stylebox_override("background", sb_bg)
	
	# Add below HP Bar
	top_left.add_child(shield_bar)
	if hp_bar:
		var idx = hp_bar.get_index()
		top_left.move_child(shield_bar, idx + 1)
	
	shield_bar.visible = true # ALWAYS VISIBLE
	if fill_render_mode == "reveal_mask":
		var reveal_fill_tex: Texture2D = _build_texture2d_from_asset(
			fill_asset,
			bool(shield_cfg.get("fill_asset_loop", true)),
			maxf(0.0, float(shield_cfg.get("fill_asset_duration", 0.0)))
		)
		if reveal_fill_tex:
			_setup_shield_fill_reveal(reveal_fill_tex)

	_apply_bar_frame_overlay(shield_bar, shield_cfg)
	_setup_wave_label(top_left, shield_bar)
	_refresh_health_bar_value_visibility()

func _clear_shield_fill_reveal() -> void:
	if not shield_bar:
		return
	var existing_reveal: TextureRect = shield_bar.get_node_or_null("ShieldFillReveal") as TextureRect
	if existing_reveal:
		existing_reveal.queue_free()
	_shield_fill_reveal_enabled = false
	_shield_fill_reveal_material = null

func _setup_shield_fill_reveal(fill_tex: Texture2D) -> void:
	if not shield_bar or fill_tex == null:
		return

	_clear_shield_fill_reveal()
	shield_bar.clip_contents = true

	var reveal_rect := TextureRect.new()
	reveal_rect.name = "ShieldFillReveal"
	reveal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	reveal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reveal_rect.stretch_mode = TextureRect.STRETCH_SCALE
	reveal_rect.texture = fill_tex

	var shader := Shader.new()
	shader.code = HP_FILL_REVEAL_SHADER_CODE
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("fill_ratio", 1.0)
	reveal_rect.material = shader_mat

	shield_bar.add_child(reveal_rect)
	shield_bar.move_child(reveal_rect, 0)

	_shield_fill_reveal_enabled = true
	_shield_fill_reveal_material = shader_mat

func _apply_bar_frame_overlay(bar: ProgressBar, bar_cfg: Dictionary) -> void:
	var existing_overlay: TextureRect = bar.get_node_or_null("FrameOverlay") as TextureRect
	if existing_overlay:
		existing_overlay.queue_free()
	
	var frame_asset: String = str(bar_cfg.get("frame_asset", ""))
	if frame_asset == "":
		return
	
	var frame_loop: bool = bool(bar_cfg.get("frame_asset_loop", true))
	var frame_duration: float = maxf(0.0, float(bar_cfg.get("frame_asset_duration", 0.0)))
	var frame_tex: Texture2D = _build_texture2d_from_asset(frame_asset, frame_loop, frame_duration)
	if not frame_tex:
		return
	
	var overlay := TextureRect.new()
	overlay.name = "FrameOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	overlay.texture = frame_tex
	bar.add_child(overlay)
	bar.move_child(overlay, bar.get_child_count() - 1)
	
	var value_label: Label = bar.get_node_or_null("ValueLabel") as Label
	if value_label:
		bar.move_child(value_label, bar.get_child_count() - 1)

func _build_texture2d_from_asset(asset_path: String, loop: bool = true, duration: float = 0.0) -> Texture2D:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null
	var res: Resource = load(asset_path)
	if res is Texture2D:
		return res as Texture2D
	if not (res is SpriteFrames):
		return null
	
	var frames: SpriteFrames = res as SpriteFrames
	var anim_name: StringName = VFXManager.get_first_animation_name(frames, &"default")
	if anim_name == &"":
		return null
	
	var frame_count: int = frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return null
	
	var animated_obj: Object = ClassDB.instantiate("AnimatedTexture")
	if animated_obj == null:
		return frames.get_frame_texture(anim_name, 0)
	
	if _object_has_property(animated_obj, "frames"):
		animated_obj.set("frames", frame_count)
	
	var fps: float = maxf(frames.get_animation_speed(anim_name), 0.01)
	if duration > 0.0:
		fps = float(frame_count) / duration
	if _object_has_property(animated_obj, "fps"):
		animated_obj.set("fps", fps)
	if _object_has_property(animated_obj, "one_shot"):
		animated_obj.set("one_shot", not loop)
	
	for i in range(frame_count):
		var frame_tex: Texture2D = frames.get_frame_texture(anim_name, i)
		if frame_tex and animated_obj.has_method("set_frame_texture"):
			animated_obj.call("set_frame_texture", i, frame_tex)
		if animated_obj.has_method("set_frame_duration"):
			var frame_dur_value: float = maxf(0.001, frames.get_frame_duration(anim_name, i))
			animated_obj.call("set_frame_duration", i, frame_dur_value)
	
	if animated_obj is Texture2D:
		return animated_obj as Texture2D
	return frames.get_frame_texture(anim_name, 0)

func _build_stylebox_texture_from_asset(
	asset_path: String,
	loop: bool,
	duration: float,
	bar_cfg: Dictionary,
	prefix: String
) -> StyleBoxTexture:
	var tex: Texture2D = _build_texture2d_from_asset(asset_path, loop, duration)
	if tex == null:
		return null
	
	var style := StyleBoxTexture.new()
	style.texture = tex
	_apply_stylebox_texture_config(style, bar_cfg, prefix)
	return style

func _apply_stylebox_texture_config(style: StyleBoxTexture, bar_cfg: Dictionary, prefix: String) -> void:
	if style == null:
		return
	
	var mode_h: int = _parse_axis_stretch_mode(str(bar_cfg.get(prefix + "mode", "stretch")))
	var mode_v: int = _parse_axis_stretch_mode(str(bar_cfg.get(prefix + "mode_vertical", "stretch")))
	
	if _object_has_property(style, "axis_stretch_horizontal"):
		style.set("axis_stretch_horizontal", mode_h)
	if _object_has_property(style, "axis_stretch_vertical"):
		style.set("axis_stretch_vertical", mode_v)
	
	# 9-slice style margins: keep caps intact, stretch/tile center area only.
	var margin_left: float = maxf(0.0, float(bar_cfg.get(prefix + "margin_left", 0.0)))
	var margin_right: float = maxf(0.0, float(bar_cfg.get(prefix + "margin_right", 0.0)))
	var margin_top: float = maxf(0.0, float(bar_cfg.get(prefix + "margin_top", 0.0)))
	var margin_bottom: float = maxf(0.0, float(bar_cfg.get(prefix + "margin_bottom", 0.0)))
	
	if _object_has_property(style, "texture_margin_left"):
		style.set("texture_margin_left", margin_left)
	if _object_has_property(style, "texture_margin_right"):
		style.set("texture_margin_right", margin_right)
	if _object_has_property(style, "texture_margin_top"):
		style.set("texture_margin_top", margin_top)
	if _object_has_property(style, "texture_margin_bottom"):
		style.set("texture_margin_bottom", margin_bottom)

func _parse_axis_stretch_mode(mode_name: String) -> int:
	var normalized: String = mode_name.strip_edges().to_lower()
	match normalized:
		"tile":
			return 1
		"tile_fit", "tilefit":
			return 2
		_:
			return 0

func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	for info in obj.get_property_list():
		if info is Dictionary and str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false

func _setup_wave_label(top_left: Control, bar_ref: Control) -> void:
	if wave_label and is_instance_valid(wave_label):
		return
	
	wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wave_label.text = ""
	wave_label.visible = false
	top_left.add_child(wave_label)
	
	if bar_ref:
		var idx: int = bar_ref.get_index()
		top_left.move_child(wave_label, idx + 1)
	
	wave_label.add_theme_font_size_override("font_size", 18)
	wave_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))

func configure_wave_counter(total_waves: int) -> void:
	_wave_total = maxi(0, total_waves)
	_wave_current = 0
	_refresh_wave_label()

func update_wave_counter(current_wave: int) -> void:
	_wave_current = maxi(0, current_wave)
	_refresh_wave_label()

func _refresh_wave_label() -> void:
	if not wave_label:
		return
	if _wave_total <= 0:
		wave_label.visible = false
		return
	
	var clamped_current: int = clampi(_wave_current, 0, _wave_total)
	wave_label.visible = true
	wave_label.text = LocaleManager.translate(
		"game_wave_progress",
		{"current": str(clamped_current), "total": str(_wave_total)}
	)

func _on_shield_changed(current: float, max_val: float) -> void:
	if not shield_bar: return
	
	shield_bar.visible = true # Always visible
	shield_bar.max_value = max_val
	shield_bar.value = current
	var shield_percent: float = float(current) / float(max_val) if max_val > 0.0 else 0.0
	if _shield_fill_reveal_enabled and _shield_fill_reveal_material:
		_shield_fill_reveal_material.set_shader_parameter("fill_ratio", clampf(shield_percent, 0.0, 1.0))
	
	var lbl = shield_bar.get_node_or_null("ValueLabel")
	if lbl:
		lbl.text = "%d / %d" % [current, max_val]

# =============================================================================
# SCORE
# =============================================================================

func add_score(points: int) -> void:
	_score += points
	_update_score()
	_update_xp_display()

func _update_score() -> void:
	if score_label:
		score_label.text = str(_score)

func get_score() -> int:
	return _score

# =============================================================================
# XP / LEVEL DISPLAY
# =============================================================================

func _setup_xp_display() -> void:
	pass

func _update_xp_display() -> void:
	pass
