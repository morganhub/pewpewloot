extends CanvasLayer
## Écran LEVEL UP du mode survivor : PAUSE + 3 GROS boutons empilés
## verticalement (nouvelle arme / amélioration / passif). Construit 100 % par
## code (pattern PauseMenu : PROCESS_MODE_ALWAYS obligatoire pour rester
## interactif pendant get_tree().paused).

signal choice_made(choice: Dictionary)

const UIStyle = preload("res://scripts/ui/UIStyle.gd")

var _cfg: Dictionary = {}
var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _buttons_box: VBoxContainer = null
var _choices: Array = []
var _paused_by_us: bool = false


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func setup(cfg: Dictionary) -> void:
	_cfg = cfg if cfg is Dictionary else {}


func _ready() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.custom_minimum_size = Vector2(minf(viewport_size.x - 48.0, 620.0), 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color("#B4FF6B"))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_title)

	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 14)
	vbox.add_child(_buttons_box)


## Affiche les 3 choix (dicts { kind, def, next_level? }) et met le jeu en pause.
func present(choices: Array, level: int) -> void:
	if _buttons_box == null:
		return
	_choices = choices
	_title.text = "%s  %d" % [LocaleManager.translate("survivor_level_up_title"), level] \
		if LocaleManager else "LEVEL UP  %d" % level
	for child in _buttons_box.get_children():
		child.queue_free()
	var btn_height: int = maxi(80, int(_cfg.get("button_min_height_px", 150)))
	for choice_v in choices:
		var choice: Dictionary = choice_v as Dictionary
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0.0, float(btn_height))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIStyle.apply_default_button_style(btn, "large")
		btn.add_child(_build_choice_content(choice))
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		_buttons_box.add_child(btn)
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true


## Contenu riche du bouton : [icône | tag + nom + description].
func _build_choice_content(choice: Dictionary) -> Control:
	var def: Dictionary = choice.get("def", {}) as Dictionary
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(margin)
	var icon_path: String = str(def.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(64.0, 64.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", _tag_color(str(choice.get("kind", ""))))
	tag.text = _tag_text(choice)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(tag)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.text = _translate_or(str(def.get("name_key", "")), str(def.get("id", "?")).capitalize())
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(name_label)
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 17)
	desc.modulate = Color(1, 1, 1, 0.75)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = _translate_or(str(def.get("desc_key", "")), "")
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(desc)
	return hbox

func _tag_text(choice: Dictionary) -> String:
	match str(choice.get("kind", "")):
		"new_weapon":
			return _translate_or("survivor_tag_new_weapon", "NEW WEAPON")
		"weapon_upgrade":
			return "%s %d" % [_translate_or("survivor_tag_upgrade", "UPGRADE Lv"), int(choice.get("next_level", 2))]
		"passive":
			return _translate_or("survivor_tag_passive", "PASSIVE")
	return ""

func _tag_color(kind: String) -> Color:
	match kind:
		"new_weapon":
			return Color("#FFD866")
		"weapon_upgrade":
			return Color("#8FD3FF")
		"passive":
			return Color("#C77DFF")
	return Color.WHITE

func _translate_or(key: String, fallback: String) -> String:
	if key == "" or LocaleManager == null:
		return fallback
	var text: String = LocaleManager.translate(key)
	return fallback if (text == key or text == "") else text

func _on_choice_pressed(choice: Dictionary) -> void:
	_close()
	choice_made.emit(choice)

func _close() -> void:
	visible = false
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false

## Fermeture forcée (fin de vague pendant un choix) — dé-pause toujours.
func force_close() -> void:
	_close()

func _exit_tree() -> void:
	# Défensif : ne jamais laisser le jeu gelé si le panel meurt ouvert.
	if _paused_by_us and get_tree() != null:
		get_tree().paused = false
		_paused_by_us = false
