extends PanelContainer
const UIStyle = preload("res://scripts/ui/UIStyle.gd")

signal close_requested
signal upgrade_requested(item_id: String)
signal recycle_requested(item_id: String)
signal equip_requested(item_id: String, slot_id: String)
signal unequip_requested(item_id: String, slot_id: String)

@onready var icon_rect = %Icon 
@onready var name_label = %NameLabel
@onready var rarity_label = %RarityLabel
@onready var stats_box = %StatsBox
@onready var upgrade_btn = %UpgradeBtn
@onready var recycle_btn = %RecycleBtn
@onready var equip_btn = %EquipBtn
@onready var close_btn = %CloseBtn
@onready var actions_grid: GridContainer = %Actions
@onready var margin_root: MarginContainer = $Margin

var current_item_id: String = ""
var current_slot_id: String = ""
var is_equipped: bool = false
var config: Dictionary = {}
var _action_profile: String = "full"
var _show_upgrade_recycle: bool = true
var _first_open_layout_pending: bool = true
var _setup_serial: int = 0

func _ensure_nodes() -> void:
	if not icon_rect: icon_rect = %Icon
	if not name_label: name_label = %NameLabel
	if not rarity_label: rarity_label = %RarityLabel
	if not stats_box: stats_box = %StatsBox
	if not upgrade_btn: upgrade_btn = %UpgradeBtn
	if not recycle_btn: recycle_btn = %RecycleBtn
	if not equip_btn: equip_btn = %EquipBtn
	if not close_btn: close_btn = %CloseBtn
	if not actions_grid: actions_grid = %Actions
	if not margin_root: margin_root = $Margin

func _ready() -> void:
	_ensure_nodes()
	close_btn.pressed.connect(_on_close_pressed)
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	recycle_btn.pressed.connect(_on_recycle_pressed)
	equip_btn.pressed.connect(_on_equip_pressed)

func setup(
	item_id: String,
	slot_id: String,
	equipped: bool,
	p_config: Dictionary = {},
	show_upgrade_recycle: bool = true,
	item_data_override: Dictionary = {}
) -> void:
	_setup_serial += 1
	var setup_serial_snapshot: int = _setup_serial
	current_item_id = item_id
	current_slot_id = slot_id
	is_equipped = equipped
	config = p_config
	_show_upgrade_recycle = show_upgrade_recycle
	
	var item = ProfileManager.get_item_by_id(item_id)
	if item.is_empty() and not item_data_override.is_empty():
		item = item_data_override.duplicate(true)
		if current_item_id == "":
			current_item_id = str(item.get("id", ""))
		if current_slot_id == "":
			current_slot_id = str(item.get("slot", ""))
		if current_slot_id != "":
			var active_ship_id := ProfileManager.get_active_ship_id()
			var equipped_item_id := ProfileManager.get_equipped_item_id(active_ship_id, current_slot_id)
			is_equipped = (equipped_item_id != "" and equipped_item_id == current_item_id)
	if item.is_empty():
		visible = false
		return
	var effective_slot_id: String = current_slot_id if current_slot_id != "" else slot_id
	
	# Fetch Global Config for styles
	var game_cfg = DataManager.get_game_config()
	var popup_cfg = game_cfg.get("popups", {})
	var details_cfg = game_cfg.get("ship_menu", {}).get("ship_details", {}).get("buttons", {})
	var rarity_params = game_cfg.get("rarity_colors", {})
	
	# Apply Popup Background
	var popup_bg_cfg: Dictionary = popup_cfg.get("background", {}) if popup_cfg.get("background") is Dictionary else {}
	var popup_bg = str(popup_bg_cfg.get("asset", ""))
	var m = int(popup_cfg.get("margin", 30))
	var style := UIStyle.build_texture_stylebox(popup_bg, popup_bg_cfg, m)
	if style:
		add_theme_stylebox_override("panel", style)
	
	var rarity = str(item.get("rarity", "common"))
	var level = int(item.get("level", int(item.get("upgrade", 0)) + 1))
	var asset = str(item.get("asset", ""))
	
	# Icon
	var final_path = asset
	
	# Try DataManager lookup if asset missing
	if final_path == "" or not ResourceLoader.exists(final_path):
		var s_data = DataManager.get_slot(effective_slot_id)
		var icon_def = s_data.get("icon")
		if icon_def is Dictionary:
			final_path = str(icon_def.get(rarity, icon_def.get("common", "")))
		elif icon_def is String:
			final_path = icon_def
			
	# Fallback to placeholder
	if final_path == "" or not ResourceLoader.exists(final_path):
		var placeholders = config.get("placeholders", {})
		final_path = str(placeholders.get(effective_slot_id, ""))
	
	_update_icon(final_path)
	
	# Name & Rarity
	var slot_data = DataManager.get_slot(effective_slot_id)
	var base_name = str(slot_data.get("name", effective_slot_id))
	name_label.text = base_name.capitalize()
	
	# Name Styling (Title Font Size + Rarity Color)
	var title_cfg = popup_cfg.get("background", {})
	var title_fs = int(title_cfg.get("font_size", 24))
	name_label.add_theme_font_size_override("font_size", title_fs)
	
	var r_col_hex = str(rarity_params.get(rarity, "#FFFFFF"))
	name_label.add_theme_color_override("font_color", Color.html(r_col_hex))
	
	rarity_label.text = rarity.capitalize() + " - Lvl " + str(level)
	var ship_menu_cfg = game_cfg.get("ship_menu", {})
	var default_fs = int(ship_menu_cfg.get("default_font_size", 16))
	rarity_label.add_theme_font_size_override("font_size", default_fs)
	rarity_label.modulate = Color(1, 1, 1, 0.7)
	
	var generic_btn_cfg = popup_cfg.get("button", {})
	if generic_btn_cfg.is_empty():
		generic_btn_cfg = UIStyle.get_default_button_style()
	_apply_btn_style(upgrade_btn, details_cfg.get("upgrade", {}), generic_btn_cfg)
	_apply_btn_style(recycle_btn, details_cfg.get("recycle", {}), generic_btn_cfg)
	_apply_btn_style(close_btn, details_cfg.get("close", {}), generic_btn_cfg)
	_apply_btn_style(equip_btn, details_cfg.get("equip", {}), generic_btn_cfg)
	
	# Stats
	for child in stats_box.get_children():
		stats_box.remove_child(child)
		child.free()
	
	var stats = item.get("stats", {})
	for key in stats:
		_add_stat_row(key, float(stats[key]))
		
	# Buttons State
	if is_equipped:
		equip_btn.text = LocaleManager.translate("item_popup_unequip")
		equip_btn.visible = true
	else:
		equip_btn.text = LocaleManager.translate("item_popup_equip")
		equip_btn.visible = true
	
	var r_val = ProfileManager.calculate_recycle_value(item)
	recycle_btn.text = "+%d" % r_val
	
	close_btn.text = LocaleManager.translate("item_popup_close")
	
	var upgrade_data = DataManager.get_level_upgrade_data(level)
	var next_data = upgrade_data.get("upgrade_to_next", {})
	var cost = int(next_data.get("cost", 999999))
	
	if level >= 10:
		upgrade_btn.text = "MAX"
		upgrade_btn.disabled = true
	else:
		upgrade_btn.text = str(cost)
		upgrade_btn.disabled = false
		if ProfileManager.get_crystals() < cost:
			upgrade_btn.disabled = true

	for btn in [equip_btn, recycle_btn, close_btn, upgrade_btn]:
		if btn and not btn.text.is_empty():
			UIStyle.apply_button_shadow(btn, "medium")

	if _show_upgrade_recycle:
		_action_profile = "full"
	else:
		_action_profile = "equip_close"
	_apply_action_profile()
	if _first_open_layout_pending:
		modulate.a = 0.0
		call_deferred("_finalize_first_open_layout", setup_serial_snapshot)
	else:
		modulate.a = 1.0
		_fit_popup_to_content()
		call_deferred("_fit_popup_to_content")

func _finalize_first_open_layout(serial: int) -> void:
	if serial != _setup_serial:
		return
	await get_tree().process_frame
	if serial != _setup_serial:
		return
	_fit_popup_to_content()
	await get_tree().process_frame
	if serial != _setup_serial:
		return
	_fit_popup_to_content()
	modulate.a = 1.0
	_first_open_layout_pending = false

func _fit_popup_to_content() -> void:
	# Fit popup size to content (without keeping stale oversized height).
	# Reset vertical minimum to avoid locking an oversized height across openings.
	custom_minimum_size = Vector2(480.0, 0.0)
	update_minimum_size()
	if margin_root:
		margin_root.update_minimum_size()
	var content_min: Vector2 = margin_root.get_combined_minimum_size() if margin_root else Vector2.ZERO
	var panel_style: StyleBox = get_theme_stylebox("panel")
	var panel_left: float = panel_style.get_content_margin(SIDE_LEFT)
	var panel_right: float = panel_style.get_content_margin(SIDE_RIGHT)
	var panel_top: float = panel_style.get_content_margin(SIDE_TOP)
	var panel_bottom: float = panel_style.get_content_margin(SIDE_BOTTOM)
	var min_size: Vector2 = Vector2(content_min.x + panel_left + panel_right, content_min.y + panel_top + panel_bottom)
	var viewport_size: Vector2 = get_viewport_rect().size
	var desired_w: float = clampf(maxf(480.0, min_size.x), 360.0, maxf(360.0, viewport_size.x - 40.0))
	var desired_h: float = clampf(min_size.y, 0.0, maxf(180.0, viewport_size.y - 40.0))
	# Keep flexible height; actual popup rect is controlled via offsets.
	custom_minimum_size = Vector2(480.0, 0.0)
	size = Vector2(desired_w, desired_h)
	offset_left = -desired_w / 2.0
	offset_right = desired_w / 2.0
	offset_top = -desired_h / 2.0
	offset_bottom = desired_h / 2.0

func set_actions_visible(p_visible: bool) -> void:
	_ensure_nodes()
	if upgrade_btn: upgrade_btn.visible = p_visible
	if recycle_btn: recycle_btn.visible = p_visible
	if equip_btn: equip_btn.visible = p_visible

func set_action_profile(profile: String) -> void:
	_action_profile = profile.strip_edges().to_lower()
	_apply_action_profile()

func _apply_action_profile() -> void:
	_ensure_nodes()
	if _action_profile == "equip_close":
		if upgrade_btn: upgrade_btn.visible = false
		if recycle_btn: recycle_btn.visible = false
		if equip_btn:
			equip_btn.visible = true
			UIStyle.set_button_shadow_text(equip_btn, LocaleManager.translate("item_popup_equip"))
		if close_btn: close_btn.visible = true
		if actions_grid:
			actions_grid.columns = 2
			if equip_btn:
				actions_grid.move_child(equip_btn, 0)
			if close_btn:
				actions_grid.move_child(close_btn, 1)
			if upgrade_btn:
				actions_grid.move_child(upgrade_btn, 2)
			if recycle_btn:
				actions_grid.move_child(recycle_btn, 3)
		return

	if upgrade_btn: upgrade_btn.visible = true
	if recycle_btn: recycle_btn.visible = true
	if equip_btn: equip_btn.visible = true
	if close_btn: close_btn.visible = true
	if actions_grid:
		actions_grid.columns = 2
		if upgrade_btn:
			actions_grid.move_child(upgrade_btn, 0)
		if recycle_btn:
			actions_grid.move_child(recycle_btn, 1)
		if equip_btn:
			actions_grid.move_child(equip_btn, 2)
		if close_btn:
			actions_grid.move_child(close_btn, 3)

func _apply_btn_style(btn: Button, btn_cfg: Dictionary, global_cfg: Dictionary) -> void:
	var merged_cfg := global_cfg.duplicate(true)
	for key in btn_cfg.keys():
		merged_cfg[key] = btn_cfg[key]
	
	var w = int(merged_cfg.get("width", 140) * 1.4)
	var h = int(merged_cfg.get("height", 50) * 1.4)
	btn.custom_minimum_size = Vector2(w, h)
	
	var asset = str(merged_cfg.get("asset", ""))
	var style := UIStyle.build_texture_stylebox(asset, merged_cfg, 10)
	if style:
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("focus", style)
		# Remove any flat style if using texture
		btn.flat = false
	
	var font_preset := UIStyle.get_button_font_preset("medium")
	var f_sz = int(merged_cfg.get("font_size", font_preset.get("font_size", 18)))
	var col = Color.html(str(merged_cfg.get("text_color", "#FFFFFF")))
	btn.add_theme_font_size_override("font_size", f_sz)
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_pressed_color", col)
	btn.add_theme_color_override("font_hover_color", col)
	btn.add_theme_color_override("font_focus_color", col)
	btn.add_theme_color_override("font_disabled_color", col)
	if not btn.text.is_empty():
		UIStyle.apply_button_shadow(btn, "medium")


func _add_stat_row(stat_name: String, value: float) -> void:
	var game_cfg = DataManager.get_game_config()
	var default_fs = int(game_cfg.get("ship_menu", {}).get("default_font_size", 16))
	var hbox = HBoxContainer.new()
	var name_lbl = Label.new()
	var stat_key = "stat." + stat_name
	var trans = LocaleManager.translate(stat_key)
	if trans == stat_key:
		name_lbl.text = stat_name.capitalize().replace("_", " ")
	else:
		name_lbl.text = trans
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", default_fs)
	
	var val_lbl = Label.new()
	val_lbl.add_theme_font_size_override("font_size", default_fs)
	
	# Percent stats: values are stored in 1-100 format, display directly as X%
	var percent_stats: Array[String] = [
		"crit_chance", "crit_damage", "dodge_chance", "damage_reduction",
		"fire_rate", "missile_damage", "missile_speed_pct",
		"loot_radius", "xp_multiplier", "mark_damage_bonus"
	]
	
	var is_percent := stat_name in percent_stats
	
	if is_percent:
		if absf(value - roundf(value)) < 0.01:
			val_lbl.text = "%d%%" % int(value)
		else:
			val_lbl.text = "%.1f%%" % value
	elif stat_name == "special_cd" and value < 0:
		val_lbl.text = "%.1fs" % value
	else:
		if absf(value - roundf(value)) < 0.01:
			val_lbl.text = "%d" % int(value)
		else:
			val_lbl.text = "%.1f" % value
	
	hbox.add_child(name_lbl)
	hbox.add_child(val_lbl)
	stats_box.add_child(hbox)

func _on_equip_pressed() -> void:
	if _action_profile == "equip_close":
		equip_requested.emit(current_item_id, current_slot_id)
		return
	if is_equipped:
		unequip_requested.emit(current_item_id, current_slot_id)
	else:
		equip_requested.emit(current_item_id, current_slot_id)

func _on_upgrade_pressed() -> void:
	upgrade_requested.emit(current_item_id)

func _on_recycle_pressed() -> void:
	recycle_requested.emit(current_item_id)

func _on_close_pressed() -> void:
	close_requested.emit()

func _update_icon(path: String) -> void:
	# Clean up previous animation
	var existing = icon_rect.get_node_or_null("AnimSprite")
	if existing: existing.queue_free()
	
	if path != "" and ResourceLoader.exists(path):
		icon_rect.visible = true
		
		# Check for AnimatedSprite2D resource (SpriteFrames)
		if path.ends_with(".tres") or path.ends_with(".res"):
			var res = load(path)
			if res is SpriteFrames:
				icon_rect.texture = null
				var anim = AnimatedSprite2D.new()
				anim.name = "AnimSprite"
				anim.sprite_frames = res
				anim.play("default")
				anim.centered = true
				icon_rect.add_child(anim)
				
				anim.position = icon_rect.size / 2.0
				if not icon_rect.resized.is_connected(_on_icon_resized):
					icon_rect.resized.connect(_on_icon_resized)
				return
		
		# Fallback / Normal Texture
		if icon_rect.resized.is_connected(_on_icon_resized):
			icon_rect.resized.disconnect(_on_icon_resized)
		icon_rect.texture = load(path)
	else:
		icon_rect.visible = false

func _on_icon_resized() -> void:
	var anim = icon_rect.get_node_or_null("AnimSprite")
	if anim:
		anim.position = icon_rect.size / 2.0
