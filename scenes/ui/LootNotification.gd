class_name LootNotification
extends Control

@onready var item_card: PanelContainer = $Mover/ItemCard
@onready var mover: Control = $Mover

var _data: Dictionary = {}
const SLIDE_IN_DURATION: float = 0.22
const VISIBLE_DURATION: float = 3.0
const FADE_OUT_DURATION: float = 0.16
const OFFSCREEN_MARGIN: float = 24.0

func setup(data: Dictionary) -> void:
	_data = data
	# Fetch config for ItemCard
	var config = {}
	if DataManager:
		var game_data = DataManager.get_game_data()
		config = {
			"rarity_frames": game_data.get("rarity_frames", {}),
			"level_assets": game_data.get("ship_options", {}).get("level_indicator_assets", {}),
			"slot_icons": game_data.get("ship_options", {}).get("slot_icons", {}),
			"placeholders": game_data.get("ship_options", {}).get("item_placeholders", {})
		}
	
	# Handle missing 'asset' key for powerups (though now filtered, good to have)
	if not _data.has("asset") and _data.has("visual_asset"):
		_data["asset"] = _data["visual_asset"]
		
	# Call ItemCard setup
	if item_card:
		var slot_id = str(_data.get("slot", ""))
		item_card.setup_item(_data, slot_id, config)

func _ready() -> void:
	modulate.a = 1.0

	# Slide in from right offscreen.
	var final_left: float = 0.0
	var final_right: float = 0.0
	if mover:
		final_left = mover.offset_left
		final_right = mover.offset_right
		var notif_width := maxf(110.0, custom_minimum_size.x)
		var slide_distance := notif_width + OFFSCREEN_MARGIN
		mover.offset_left = final_left + slide_distance
		mover.offset_right = final_right + slide_distance

	var tween = create_tween()
	if mover:
		tween.set_parallel(true)
		tween.tween_property(mover, "offset_left", final_left, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(mover, "offset_right", final_right, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.set_parallel(false)

	# Keep visible for 3 seconds, then disappear.
	tween.tween_interval(VISIBLE_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_callback(queue_free)
