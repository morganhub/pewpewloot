extends Node

## SkillManager — Central interface for querying active skill bonuses.
## Reads data from DataManager (skills.json) and state from ProfileManager.

# =============================================================================
# STAT MODIFIERS (Paragon)
# =============================================================================

## Returns the total percentage bonus for a given stat from Paragon skills.
## e.g., get_stat_modifier("damage") -> 0.05 means +5%
func get_stat_modifier(stat_name: String) -> float:
	var unlocked := ProfileManager.get_skills_unlocked()
	var total_bonus: float = 0.0

	for skill_id in unlocked:
		var rank := int(unlocked[skill_id])
		if rank <= 0:
			continue
		var skill_data := DataManager.get_skill(skill_id)
		if skill_data.get("type", "") != "stat_modifier":
			continue
		var params: Dictionary = skill_data.get("params", {})
		var skill_stat: String = str(params.get("stat", ""))
		if _stat_matches(skill_stat, stat_name):
			total_bonus += float(params.get("bonus_per_rank", 0.0)) * rank

	return total_bonus

func _stat_matches(skill_stat: String, requested_stat: String) -> bool:
	if skill_stat == requested_stat:
		return true
	if requested_stat == "power" and skill_stat == "damage":
		return true
	if requested_stat == "damage" and skill_stat == "power":
		return true
	return false

# =============================================================================
# MAGIC TREE
# =============================================================================

## Returns the active magic branch id ("frozen", "poison", "void" or "")
func get_active_magic_tree() -> String:
	return ProfileManager.get_active_magic_branch()

## Returns all unlocked magic skills ordered by level
func get_unlocked_magic_skills() -> Array:
	var branch := get_active_magic_tree()
	if branch == "":
		return []

	var tree_data := DataManager.get_skill_tree("magic")
	var branches: Dictionary = tree_data.get("branches", {})
	var branch_data: Dictionary = branches.get(branch, {})
	var levels: Array = branch_data.get("levels", [])

	var result: Array = []
	for level in levels:
		if level is Dictionary:
			var skill_id := str(level.get("id", ""))
			if ProfileManager.is_skill_unlocked(skill_id):
				result.append(level)
	return result

## Returns the max unlocked magic skill level (1-5) or 0 if none
func get_magic_level() -> int:
	return get_unlocked_magic_skills().size()

## Returns the projectile modifier config based on active magic tree.
## { "missile_override": "missile_ice", "on_hit_effects": [...], ... }
func get_projectile_modifier() -> Dictionary:
	var branch := get_active_magic_tree()
	if branch == "":
		return {}

	var skills := get_unlocked_magic_skills()
	if skills.is_empty():
		return {}

	var result: Dictionary = {}
	result["branch"] = branch

	# The first skill always has the missile override
	var first_skill: Dictionary = skills[0]
	var first_params: Dictionary = first_skill.get("params", {})
	var missile_override: String = str(first_params.get("missile_override", ""))
	if missile_override != "":
		result["missile_override"] = missile_override

	# Collect all on-hit effect ids and params
	var on_hit_effects: Array = []
	for skill in skills:
		var params: Dictionary = skill.get("params", {})
		var effect_id: String = str(params.get("on_hit_effect", ""))
		if effect_id != "":
			on_hit_effects.append({
				"effect_id": effect_id,
				"skill_id": str(skill.get("id", "")),
				"params": params
			})

	result["on_hit_effects"] = on_hit_effects

	# Aggregate individual skill params based on branch
	match branch:
		"frozen":
			result["slow_percent"] = float(first_params.get("slow_percent", 0.15))
			result["max_stacks"] = int(first_params.get("max_stacks", 3))
			# Aura (level 2+)
			for skill in skills:
				var p: Dictionary = skill.get("params", {})
				if p.has("aura_type"):
					result["aura_type"] = str(p["aura_type"])
					result["aura_radius"] = float(p.get("aura_radius", 120))
					result["aura_slow_percent"] = float(p.get("aura_slow_percent", 0.20))
				if p.has("aura_asset"):
					result["aura_asset"] = str(p.get("aura_asset", ""))
				if p.has("aura_asset_anim"):
					result["aura_asset_anim"] = str(p.get("aura_asset_anim", ""))
				if p.has("aura_asset_anim_duration"):
					result["aura_asset_anim_duration"] = float(p.get("aura_asset_anim_duration", 0.0))
				if p.has("aura_asset_anim_loop"):
					result["aura_asset_anim_loop"] = bool(p.get("aura_asset_anim_loop", true))
				if p.has("aura_asset_size"):
					result["aura_asset_size"] = float(p.get("aura_asset_size", 220.0))
				if p.has("freeze_duration"):
					result["freeze_enabled"] = true
					result["freeze_aura_time"] = float(p.get("freeze_aura_time", 2.0))
					result["freeze_hit_count"] = int(p.get("freeze_hit_count", 10))
					result["freeze_duration"] = float(p.get("freeze_duration", 2.0))
				if p.has("freeze_mark_asset"):
					result["freeze_mark_asset"] = str(p.get("freeze_mark_asset", ""))
				if p.has("freeze_mark_asset_anim"):
					result["freeze_mark_asset_anim"] = str(p.get("freeze_mark_asset_anim", ""))
				if p.has("freeze_mark_asset_anim_duration"):
					result["freeze_mark_asset_anim_duration"] = float(p.get("freeze_mark_asset_anim_duration", 0.0))
				if p.has("freeze_mark_asset_anim_loop"):
					result["freeze_mark_asset_anim_loop"] = bool(p.get("freeze_mark_asset_anim_loop", true))
				if p.has("freeze_mark_size"):
					result["freeze_mark_size"] = float(p.get("freeze_mark_size", 52.0))
				if p.has("shatter_damage_pct"):
					result["shatter_enabled"] = true
					result["shatter_damage_pct"] = float(p.get("shatter_damage_pct", 0.5))
					result["shatter_radius"] = float(p.get("shatter_radius", 80))
					result["shatter_projectile_count"] = int(p.get("shatter_projectile_count", 6))
				if p.has("shard_asset"):
					result["shard_asset"] = str(p.get("shard_asset", ""))
				if p.has("shard_asset_anim"):
					result["shard_asset_anim"] = str(p.get("shard_asset_anim", ""))
				if p.has("shard_asset_anim_duration"):
					result["shard_asset_anim_duration"] = float(p.get("shard_asset_anim_duration", 0.0))
				if p.has("shard_asset_anim_loop"):
					result["shard_asset_anim_loop"] = bool(p.get("shard_asset_anim_loop", true))
				if p.has("shard_asset_size"):
					result["shard_asset_size"] = float(p.get("shard_asset_size", 12.0))
				if p.has("aura_radius_bonus"):
					result["aura_radius_bonus"] = float(p.get("aura_radius_bonus", 0.5))
					result["freeze_dot_dps"] = float(p.get("freeze_dot_dps", 5))

		"poison":
			result["dot_percent"] = float(first_params.get("dot_percent", 0.20))
			result["dot_duration"] = float(first_params.get("dot_duration", 3.0))
			for skill in skills:
				var p: Dictionary = skill.get("params", {})
				if p.has("pool_damage_per_sec"):
					result["pool_enabled"] = true
					result["pool_damage_per_sec"] = float(p.get("pool_damage_per_sec", 8))
					result["pool_duration"] = float(p.get("pool_duration", 3.0))
					result["pool_radius"] = float(p.get("pool_radius", 50))
				if p.has("pool_asset"):
					result["pool_asset"] = str(p.get("pool_asset", ""))
				if p.has("pool_asset_anim"):
					result["pool_asset_anim"] = str(p.get("pool_asset_anim", ""))
				if p.has("pool_asset_anim_duration"):
					result["pool_asset_anim_duration"] = float(p.get("pool_asset_anim_duration", 0.0))
				if p.has("pool_asset_anim_loop"):
					result["pool_asset_anim_loop"] = bool(p.get("pool_asset_anim_loop", true))
				if p.has("pool_asset_size"):
					result["pool_asset_size"] = float(p.get("pool_asset_size", 150.0))
				if p.has("pool_fluid_id"):
					result["pool_fluid_id"] = str(p.get("pool_fluid_id", ""))
				if p.has("contagion_radius"):
					result["contagion_enabled"] = true
					result["contagion_radius"] = float(p.get("contagion_radius", 80))
					result["contagion_dot_duration"] = float(p.get("contagion_dot_duration", 3.0))
				if p.has("contagion_asset"):
					result["contagion_asset"] = str(p.get("contagion_asset", ""))
				if p.has("contagion_asset_anim"):
					result["contagion_asset_anim"] = str(p.get("contagion_asset_anim", ""))
				if p.has("contagion_asset_anim_duration"):
					result["contagion_asset_anim_duration"] = float(p.get("contagion_asset_anim_duration", 0.0))
				if p.has("contagion_asset_anim_loop"):
					result["contagion_asset_anim_loop"] = bool(p.get("contagion_asset_anim_loop", true))
				if p.has("vulnerability_bonus"):
					result["corrosive_enabled"] = true
					result["vulnerability_bonus"] = float(p.get("vulnerability_bonus", 0.25))
				if p.has("pool_radius_bonus"):
					result["pool_radius_bonus"] = float(p.get("pool_radius_bonus", 0.5))
					result["dot_duration_bonus"] = float(p.get("dot_duration_bonus", 2.0))

		"void":
			result["pull_strength"] = float(first_params.get("pull_strength", 30.0))
			for skill in skills:
				var p: Dictionary = skill.get("params", {})
				if p.has("singularity_chance"):
					result["singularity_enabled"] = true
					result["singularity_chance"] = float(p.get("singularity_chance", 0.10))
					result["singularity_duration"] = float(p.get("singularity_duration", 1.0))
					result["singularity_radius"] = float(p.get("singularity_radius", 80))
				if p.has("singularity_asset"):
					result["singularity_asset"] = str(p.get("singularity_asset", ""))
				if p.has("singularity_asset_anim"):
					result["singularity_asset_anim"] = str(p.get("singularity_asset_anim", ""))
				if p.has("singularity_asset_anim_duration"):
					result["singularity_asset_anim_duration"] = float(p.get("singularity_asset_anim_duration", 0.0))
				if p.has("singularity_asset_anim_loop"):
					result["singularity_asset_anim_loop"] = bool(p.get("singularity_asset_anim_loop", true))
				if p.has("singularity_asset_size"):
					result["singularity_asset_size"] = float(p.get("singularity_asset_size", 180.0))
				if p.has("void_radius_bonus"):
					result["void_radius_bonus"] = float(p.get("void_radius_bonus", 0.5))
				if p.has("singularity_damage_base"):
					result["spaghettification_enabled"] = true
					result["singularity_damage_base"] = float(p.get("singularity_damage_base", 5))
					result["singularity_damage_exponent"] = float(p.get("singularity_damage_exponent", 2.0))
				if p.has("deflection_aura_radius"):
					result["deflection_enabled"] = true
					result["deflection_aura_radius"] = float(p.get("deflection_aura_radius", 100))
					result["deflection_strength"] = float(p.get("deflection_strength", 0.3))
				if p.has("deflection_aura_asset"):
					result["deflection_aura_asset"] = str(p.get("deflection_aura_asset", ""))
				if p.has("deflection_aura_asset_anim"):
					result["deflection_aura_asset_anim"] = str(p.get("deflection_aura_asset_anim", ""))
				if p.has("deflection_aura_asset_anim_duration"):
					result["deflection_aura_asset_anim_duration"] = float(p.get("deflection_aura_asset_anim_duration", 0.0))
				if p.has("deflection_aura_asset_anim_loop"):
					result["deflection_aura_asset_anim_loop"] = bool(p.get("deflection_aura_asset_anim_loop", true))
				if p.has("deflection_aura_asset_size"):
					result["deflection_aura_asset_size"] = float(p.get("deflection_aura_asset_size", 180.0))

	return result

# =============================================================================
# UTILITY BONUSES
# =============================================================================

## Returns aggregated utility bonuses from loot and powers branches.
func get_utility_bonuses() -> Dictionary:
	var result: Dictionary = {}
	var unlocked := ProfileManager.get_skills_unlocked()

	for skill_id in unlocked:
		var rank := int(unlocked[skill_id])
		if rank <= 0:
			continue
		var skill_data := DataManager.get_skill(skill_id)
		var tree_id := DataManager.get_skill_tree_for_id(skill_id)
		if tree_id != "utility":
			continue
		var params: Dictionary = skill_data.get("params", {})
		for key in params:
			# Accumulate numeric bonuses
			var val = params[key]
			if val is float or val is int:
				result[key] = float(result.get(key, 0.0)) + float(val) * rank
			else:
				result[key] = val

	return result

# =============================================================================
# SKILL TREE QUERY HELPERS
# =============================================================================

## Checks if a skill can currently be unlocked by the player.
func can_unlock_skill(skill_id: String) -> bool:
	if ProfileManager.get_skill_points() <= 0:
		return false

	var skill_data := DataManager.get_skill(skill_id)
	if skill_data.is_empty():
		return false

	var max_rank := int(skill_data.get("max_rank", 1))
	var current_rank := ProfileManager.get_skill_rank(skill_id)
	if current_rank >= max_rank:
		return false

	var prereq := str(skill_data.get("prerequisite", ""))
	if prereq != "" and not ProfileManager.is_skill_unlocked(prereq):
		return false

	var tree_id := DataManager.get_skill_tree_for_id(skill_id)
	var tree_data := DataManager.get_skill_tree(tree_id)
	var unlock_req := int(tree_data.get("unlock_requirement", 0))
	if unlock_req > 0:
		if tree_id == "pew_pew":
			var spent_other_trees := ProfileManager.get_spent_skill_points("pew_pew")
			if spent_other_trees < unlock_req:
				return false
		elif ProfileManager.get_player_level() < unlock_req:
			return false

	# Magic exclusivity
	if tree_id == "magic":
		var branch_id := DataManager.get_skill_branch_for_id(skill_id)
		var active_branch := ProfileManager.get_active_magic_branch()
		if active_branch != "" and active_branch != branch_id:
			return false

	return true
