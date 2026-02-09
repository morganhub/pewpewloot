extends Control

## ShopMenu — Achat de cristaux (simulation store).

# =============================================================================
# RÉFÉRENCES UI
# =============================================================================

@onready var back_button: Button = %BackButton
@onready var packs_grid: GridContainer = %PacksGrid
@onready var confirm_popup: PanelContainer = %ConfirmPopup
@onready var confirm_title: Label = %ConfirmTitle
@onready var confirm_message: Label = %ConfirmMessage
@onready var confirm_buy_btn: Button = %ConfirmBuyBtn
@onready var cancel_btn: Button = %CancelBtn
@onready var background: TextureRect = $Background

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
	
	# Connexions
	if back_button: back_button.pressed.connect(_on_back_pressed)
	if confirm_buy_btn: confirm_buy_btn.pressed.connect(_on_confirm_buy_pressed)
	if cancel_btn: cancel_btn.pressed.connect(func(): confirm_popup.visible = false)
	
	confirm_popup.visible = false
	
	_setup_visuals()
	_populate_packs()

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
	var popup_bg_asset: String = str(popups_cfg.get("background", {}).get("asset", ""))
	var margin: int = int(popups_cfg.get("margin", 20))
	
	if popup_bg_asset != "" and ResourceLoader.exists(popup_bg_asset):
		var style = StyleBoxTexture.new()
		style.texture = load(popup_bg_asset)
		style.content_margin_top = margin
		style.content_margin_bottom = margin
		style.content_margin_left = margin
		style.content_margin_right = margin
		confirm_popup.add_theme_stylebox_override("panel", style)
	
	# Back Button
	var ui_icons: Dictionary = _game_config.get("ui_icons", {})
	var back_icon_path: String = str(ui_icons.get("back_button", ""))
	if back_icon_path != "" and ResourceLoader.exists(back_icon_path) and back_button:
		back_button.icon = load(back_icon_path)
		back_button.text = ""
		back_button.flat = true
		back_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		back_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

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
	
	for pack in packs:
		if not pack is Dictionary:
			continue
		var p: Dictionary = pack as Dictionary
		var crystals: int = int(p.get("crystals", 0))
		var price: float = float(p.get("price_usd", 0.0))
		var pack_id: String = str(p.get("id", ""))
		
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 100)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.text = "💎 " + str(crystals) + "\n$" + str(price)
		btn.add_theme_font_size_override("font_size", btn_font_size)
		btn.add_theme_color_override("font_color", btn_text_color)
		
		# Style
		if btn_asset != "" and ResourceLoader.exists(btn_asset):
			var style = StyleBoxTexture.new()
			style.texture = load(btn_asset)
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
			btn.add_theme_stylebox_override("focus", style)
		
		btn.pressed.connect(func(): _on_pack_pressed(p))
		packs_grid.add_child(btn)

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
	# Return to ShipMenu via Switcher
	var switcher := get_tree().current_scene
	if switcher.has_method("goto_screen"):
		switcher.goto_screen("res://scenes/ShipMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ShipMenu.tscn")
