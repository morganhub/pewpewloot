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
	if hp_bar:
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
	var config = DataManager.get_game_data().get("gameplay", {}).get("bars", {})
	var height = float(config.get("height", 40.0))
	
	hp_bar.custom_minimum_size.y = height
	
	# Add internal label
	var lbl = Label.new()
	lbl.name = "ValueLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(lbl)
	
	# Style Text
	var txt_color = Color(str(config.get("text_color", "#FFFFFF")))
	var txt_size = int(config.get("text_size", 24))
	lbl.add_theme_color_override("font_color", txt_color)
	lbl.add_theme_font_size_override("font_size", txt_size)
	
	# Background Asset for HP ?
	var asset = str(config.get("hp", {}).get("asset", ""))
	if asset != "" and ResourceLoader.exists(asset):
		# If we want an image background, we need a StyleBoxTexture
		var sb_bg = StyleBoxTexture.new()
		sb_bg.texture = load(asset)
		hp_bar.add_theme_stylebox_override("background", sb_bg)

func _setup_shield_bar() -> void:
	var top_left = $TopLeft
	if not top_left: return
	
	var config = DataManager.get_game_data().get("gameplay", {}).get("bars", {})
	var height = float(config.get("height", 40.0))
	
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
	var txt_color = Color(str(config.get("text_color", "#FFFFFF")))
	var txt_size = int(config.get("text_size", 24))
	lbl.add_theme_color_override("font_color", txt_color)
	lbl.add_theme_font_size_override("font_size", txt_size)
	
	# Style Bar
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.0, 0.6, 1.0) # Blue
	sb_fill.corner_radius_top_left = 5
	sb_fill.corner_radius_top_right = 5
	sb_fill.corner_radius_bottom_left = 5
	sb_fill.corner_radius_bottom_right = 5
	
	var sb_bg = StyleBoxFlat.new() # Default fallback
	sb_bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	
	# Background Asset for Shield
	var asset = str(config.get("shield", {}).get("asset", ""))
	if asset != "" and ResourceLoader.exists(asset):
		sb_bg = StyleBoxTexture.new()
		sb_bg.texture = load(asset)
	
	shield_bar.add_theme_stylebox_override("fill", sb_fill)
	shield_bar.add_theme_stylebox_override("background", sb_bg)
	
	# Add below HP Bar
	top_left.add_child(shield_bar)
	if hp_bar:
		var idx = hp_bar.get_index()
		top_left.move_child(shield_bar, idx + 1)
	
	shield_bar.visible = true # ALWAYS VISIBLE

func _on_shield_changed(current: float, max_val: float) -> void:
	if not shield_bar: return
	
	shield_bar.visible = true # Always visible
	shield_bar.max_value = max_val
	shield_bar.value = current
	
	var lbl = shield_bar.get_node_or_null("ValueLabel")
	if lbl:
		lbl.text = "%d / %d" % [current, max_val]

# =============================================================================
# SCORE
# =============================================================================

func add_score(points: int) -> void:
	_score += points
	_update_score()

func _update_score() -> void:
	if score_label:
		score_label.text = "Score: " + str(_score)

func get_score() -> int:
	return _score
