extends Node

signal streak_started(initial_kill_count: int)
signal streak_updated(kill_count: int, multiplier: float, time_left: float, time_ratio: float, tier_id: String, tier_label: String)
signal streak_tier_changed(old_tier_id: String, new_tier_id: String, multiplier: float)
signal streak_warning(time_left: float, time_ratio: float)
signal streak_ended(final_kill_count: int, highest_multiplier: float, end_bonus_score: int)
signal multiplier_changed(multiplier: float)

var _enabled: bool = true
var _base_timer_sec: float = 2.4
var _refresh_mode: String = "full_reset"
var _partial_refill_sec: float = 0.75
var _critical_threshold_ratio: float = 0.25
var _max_multiplier: float = 3.0
var _rounding_mode: String = "round"
var _enable_end_streak_bonus: bool = true
var _streak_end_bonus_per_kill: int = 0
var _boss_kill_count_value: int = 1
var _boss_kill_bonus_score_flat: int = 0
var _boss_can_drop_bonus_crystal: bool = true
var _lose_streak_on_player_death: bool = true
var _lose_streak_on_level_end: bool = true

var _tiers: Array[Dictionary] = []

var _active: bool = false
var _kill_count: int = 0
var _timer_left: float = 0.0
var _current_multiplier: float = 1.0
var _highest_multiplier: float = 1.0
var _current_tier_id: String = "base"
var _current_tier_label: String = "killstreak_tier_base"
var _warning_emitted: bool = false

func configure(config: Dictionary) -> void:
	_enabled = bool(config.get("enabled", true))
	_base_timer_sec = maxf(0.1, float(config.get("base_timer_sec", 2.4)))
	_refresh_mode = str(config.get("refresh_mode", "full_reset"))
	_partial_refill_sec = maxf(0.0, float(config.get("partial_refill_sec", 0.75)))
	_critical_threshold_ratio = clampf(float(config.get("critical_threshold_ratio", 0.25)), 0.01, 0.99)
	_max_multiplier = maxf(1.0, float(config.get("max_multiplier", 3.0)))
	_rounding_mode = str(config.get("rounding_mode", "round")).to_lower()
	_enable_end_streak_bonus = bool(config.get("enable_end_streak_bonus", true))
	_streak_end_bonus_per_kill = maxi(0, int(config.get("streak_end_bonus_per_kill", 0)))
	_boss_kill_count_value = maxi(0, int(config.get("boss_kill_count_value", 1)))
	_boss_kill_bonus_score_flat = maxi(0, int(config.get("boss_kill_bonus_score_flat", 0)))
	_boss_can_drop_bonus_crystal = bool(config.get("boss_can_drop_bonus_crystal", true))
	_lose_streak_on_player_death = bool(config.get("lose_streak_on_player_death", true))
	_lose_streak_on_level_end = bool(config.get("lose_streak_on_level_end", true))
	_parse_tiers(config.get("tiers", []))
	reset_run(false)

func _parse_tiers(raw_tiers: Variant) -> void:
	_tiers.clear()
	if raw_tiers is Array:
		for tier_variant in (raw_tiers as Array):
			if not (tier_variant is Dictionary):
				continue
			var tier: Dictionary = tier_variant as Dictionary
			_tiers.append({
				"id": str(tier.get("id", "base")),
				"label_key": str(tier.get("label_key", "killstreak_tier_base")),
				"min_kills": maxi(0, int(tier.get("min_kills", 0))),
				"multiplier": clampf(float(tier.get("multiplier", 1.0)), 1.0, _max_multiplier)
			})
	_tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("min_kills", 0)) < int(b.get("min_kills", 0))
	)
	if _tiers.is_empty():
		_tiers.append({
			"id": "base",
			"label_key": "killstreak_tier_base",
			"min_kills": 0,
			"multiplier": 1.0
		})

func reset_run(emit_end_if_active: bool = true) -> void:
	if emit_end_if_active and _active:
		end_streak("reset_run")
		return
	_active = false
	_kill_count = 0
	_timer_left = 0.0
	_current_multiplier = 1.0
	_highest_multiplier = 1.0
	_current_tier_id = "base"
	_current_tier_label = "killstreak_tier_base"
	_warning_emitted = false

func update(delta: float) -> void:
	if not _enabled or not _active:
		return
	_timer_left = maxf(0.0, _timer_left - maxf(0.0, delta))
	var ratio: float = get_time_ratio()
	if ratio <= _critical_threshold_ratio and not _warning_emitted:
		_warning_emitted = true
		streak_warning.emit(_timer_left, ratio)
	if _timer_left <= 0.0:
		end_streak("timeout")

func on_enemy_killed(kill_value: int = 1) -> Dictionary:
	if not _enabled:
		return _state_dict()
	var add_kills: int = maxi(1, kill_value)
	if not _active:
		_active = true
		_kill_count = add_kills
		_apply_timer_refresh()
		_update_tier_and_multiplier()
		streak_started.emit(_kill_count)
		streak_updated.emit(_kill_count, _current_multiplier, _timer_left, get_time_ratio(), _current_tier_id, _current_tier_label)
		return _state_dict()

	_kill_count += add_kills
	_apply_timer_refresh()
	_update_tier_and_multiplier()
	streak_updated.emit(_kill_count, _current_multiplier, _timer_left, get_time_ratio(), _current_tier_id, _current_tier_label)
	return _state_dict()

func _apply_timer_refresh() -> void:
	if _refresh_mode == "partial_refill":
		_timer_left = minf(_base_timer_sec, _timer_left + _partial_refill_sec)
	else:
		_timer_left = _base_timer_sec
	_warning_emitted = false

func _resolve_tier(kills: int) -> Dictionary:
	var resolved: Dictionary = _tiers[0]
	for tier in _tiers:
		if int(tier.get("min_kills", 0)) <= kills:
			resolved = tier
		else:
			break
	return resolved

func _update_tier_and_multiplier() -> void:
	var old_tier: String = _current_tier_id
	var old_mult: float = _current_multiplier
	var tier: Dictionary = _resolve_tier(_kill_count)
	_current_tier_id = str(tier.get("id", "base"))
	_current_tier_label = str(tier.get("label_key", "killstreak_tier_base"))
	_current_multiplier = minf(_max_multiplier, maxf(1.0, float(tier.get("multiplier", 1.0))))
	_highest_multiplier = maxf(_highest_multiplier, _current_multiplier)

	if old_tier != _current_tier_id:
		streak_tier_changed.emit(old_tier, _current_tier_id, _current_multiplier)
	if old_mult != _current_multiplier:
		multiplier_changed.emit(_current_multiplier)

func end_streak(_reason: String = "manual") -> int:
	if not _active:
		return 0
	var final_kills: int = _kill_count
	var highest: float = _highest_multiplier
	var end_bonus: int = 0
	if _enable_end_streak_bonus:
		end_bonus = maxi(0, final_kills * _streak_end_bonus_per_kill)

	reset_run(false)
	streak_ended.emit(final_kills, highest, end_bonus)
	return end_bonus

func on_player_died() -> int:
	if _lose_streak_on_player_death:
		return end_streak("player_died")
	return 0

func on_level_end() -> int:
	if _lose_streak_on_level_end:
		return end_streak("level_end")
	return 0

func add_time_bonus(seconds: float) -> void:
	if not _active or seconds <= 0.0:
		return
	_timer_left = minf(_base_timer_sec, _timer_left + seconds)
	_warning_emitted = false
	streak_updated.emit(_kill_count, _current_multiplier, _timer_left, get_time_ratio(), _current_tier_id, _current_tier_label)

func compute_score(base_score: int) -> int:
	var raw: float = float(maxi(0, base_score)) * _current_multiplier
	if _rounding_mode == "floor":
		return maxi(0, int(floor(raw)))
	return maxi(0, int(round(raw)))

func get_time_ratio() -> float:
	if _base_timer_sec <= 0.0:
		return 0.0
	return clampf(_timer_left / _base_timer_sec, 0.0, 1.0)

func get_multiplier() -> float:
	return _current_multiplier

func get_kill_count() -> int:
	return _kill_count

func get_tier_id() -> String:
	return _current_tier_id

func get_tier_label_key() -> String:
	return _current_tier_label

func is_active() -> bool:
	return _active

func get_timer_left() -> float:
	return _timer_left

func get_boss_kill_count_value() -> int:
	return _boss_kill_count_value

func get_boss_kill_bonus_score_flat() -> int:
	return _boss_kill_bonus_score_flat

func boss_can_drop_bonus_crystal() -> bool:
	return _boss_can_drop_bonus_crystal

func _state_dict() -> Dictionary:
	return {
		"active": _active,
		"kill_count": _kill_count,
		"multiplier": _current_multiplier,
		"timer_left": _timer_left,
		"time_ratio": get_time_ratio(),
		"tier_id": _current_tier_id,
		"tier_label_key": _current_tier_label
	}

