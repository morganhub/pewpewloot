class_name StatusEffect
extends RefCounted

## StatusEffect — Represents a single status effect applied to an enemy.
## Managed by Enemy._process_status_effects(delta).

# =============================================================================
# EFFECT TYPES
# =============================================================================

enum Type {
	CHILL,       # Slows movement
	FREEZE,      # Complete immobilization
	POISON,      # Damage over time
	CORROSIVE,   # Increased damage taken
	VOID_PULL,   # Micro-pull toward a point
}

# =============================================================================
# PROPERTIES
# =============================================================================

var type: Type = Type.CHILL
var effect_id: String = ""
var source_skill_id: String = ""
var duration: float = 3.0
var remaining_time: float = 3.0
var tick_interval: float = 0.5
var tick_timer: float = 0.0
var stacks: int = 1
var max_stacks: int = 3
var params: Dictionary = {}

# =============================================================================
# FACTORY METHODS
# =============================================================================

static func create_chill(slow_pct: float, max_stacks_val: int, duration_val: float = 5.0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = Type.CHILL
	effect.effect_id = "chill_slow"
	effect.duration = duration_val
	effect.remaining_time = duration_val
	effect.max_stacks = max_stacks_val
	effect.params = { "slow_percent": slow_pct }
	return effect

static func create_freeze(freeze_duration: float = 2.0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = Type.FREEZE
	effect.effect_id = "freeze"
	effect.duration = freeze_duration
	effect.remaining_time = freeze_duration
	effect.max_stacks = 1
	return effect

static func create_poison(total_damage: float, dot_duration: float = 3.0, tick_rate: float = 0.5) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = Type.POISON
	effect.effect_id = "poison_dot"
	effect.duration = dot_duration
	effect.remaining_time = dot_duration
	effect.tick_interval = tick_rate
	effect.max_stacks = 1
	effect.params = {
		"total_damage": total_damage,
		"tick_damage": total_damage / (dot_duration / tick_rate)
	}
	return effect

static func create_corrosive(vulnerability: float, duration_val: float = 5.0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = Type.CORROSIVE
	effect.effect_id = "corrosive"
	effect.duration = duration_val
	effect.remaining_time = duration_val
	effect.max_stacks = 1
	effect.params = { "vulnerability_bonus": vulnerability }
	return effect

static func create_void_pull(pull_strength: float, pull_target: Vector2 = Vector2.ZERO) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.type = Type.VOID_PULL
	effect.effect_id = "void_pull"
	effect.duration = 0.3
	effect.remaining_time = 0.3
	effect.max_stacks = 1
	effect.params = { "pull_strength": pull_strength, "pull_target": pull_target }
	return effect

# =============================================================================
# LIFECYCLE
# =============================================================================

func is_expired() -> bool:
	return remaining_time <= 0.0

func tick(delta: float) -> Dictionary:
	remaining_time -= delta
	var result: Dictionary = { "damage": 0, "expired": false }

	if type == Type.POISON:
		tick_timer += delta
		if tick_timer >= tick_interval:
			tick_timer -= tick_interval
			result["damage"] = int(float(params.get("tick_damage", 0)))

	if remaining_time <= 0.0:
		result["expired"] = true

	return result

func add_stack() -> void:
	if stacks < max_stacks:
		stacks += 1
	# Refresh duration
	remaining_time = duration

## Returns the total slow multiplier for this effect (0.0 to 1.0)
func get_slow_factor() -> float:
	if type == Type.CHILL:
		return float(params.get("slow_percent", 0.15)) * stacks
	return 0.0

## Returns vulnerability bonus (damage amplification)
func get_vulnerability() -> float:
	if type == Type.CORROSIVE:
		return float(params.get("vulnerability_bonus", 0.0))
	return 0.0
