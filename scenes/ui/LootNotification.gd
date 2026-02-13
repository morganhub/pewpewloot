class_name LootNotification
extends Control

@onready var mover: Control = $Mover
@onready var item_card: PanelContainer = $Mover/ItemCard

var _data: Dictionary = {}

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
	# Keep item info active if needed, mainly visualize
	# Mover initial state: offscreen right relative to slot
	# LootNotification has width 200. Mover anchors right.
	# We want Mover to start at position.x = +200 relative to anchor?
	# Anchor Right (1.0). If we offset +200, it goes right.
	
	mover.position.x += 300 # Start off-screen
	modulate.a = 0.0
	
	var tween = create_tween()
	# Slide In
	tween.tween_property(mover, "position:x", mover.position.x - 300.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.3)
	
	# Wait
	tween.tween_interval(3.0)
	
	# Slide Out
	tween.tween_property(mover, "position:x", mover.position.x + 300.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	
	tween.tween_callback(queue_free)
