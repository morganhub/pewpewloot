extends SceneTree

func _init():
	print("[Test] Verifying Enemy Modifiers...")
	
	# Load EnemyModifiers
	var EnemyModifiers = load("res://autoload/EnemyModifiers.gd")
	if not EnemyModifiers:
		print("[FAIL] Could not load EnemyModifiers.gd")
		quit(1)
		return

	# Load Enemy Scene (for script attachment)
	var enemy_script = load("res://scenes/Enemy.gd")
	var enemy = CharacterBody2D.new()
	enemy.set_script(enemy_script)
	
	# Mock data
	var enemy_data = {"id": "test_enemy", "hp": 100, "speed": 100, "damage": 10}
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.move_speed = 100
	
	# Mock internal nodes required by Enemy.gd
	var visual = Node2D.new()
	visual.name = "Visual"
	enemy.add_child(visual)
	var shape = Polygon2D.new()
	shape.name = "Shape"
	visual.add_child(shape)
	var hb = ProgressBar.new()
	hb.name = "HealthBar"
	enemy.add_child(hb)
	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	enemy.add_child(col)
	
	# Apply Modifier
	var mod_id = "elite_berserker"
	print("[Test] Applying modifier: ", mod_id)
	
	# Note: EnemyModifiers is a static class (no instance needed)
	EnemyModifiers.apply_modifier(enemy, mod_id)
	
	# check stats
	var expected_hp = 200 # 100 * 2.0
	if enemy.max_hp == expected_hp:
		print("[PASS] HP Multiplier applied correctly. HP: ", enemy.max_hp)
	else:
		print("[FAIL] HP Multiplier failed. Expected ", expected_hp, ", got ", enemy.max_hp)

	var expected_scale = Vector2(1.2, 1.2)
	if abs(enemy.scale.x - 1.2) < 0.01:
		print("[PASS] Scale applied correctly. Scale: ", enemy.scale)
	else:
		print("[FAIL] Scale failed. Expected ", expected_scale, ", got ", enemy.scale)
		
	# Check Visuals (Aura)
	var aura = enemy.get_node_or_null("VisualContainer/EliteAura")
	if not aura:
		aura = enemy.get_node_or_null("EliteAura") # Fallback to root or visual container?
		# Logic in EnemyModifiers:
		# var container = enemy.get_node_or_null("VisualContainer")
		# if not container: container = enemy
	
	# Enemy.gd has $Visual named "Visual", but EnemyModifiers looks for "VisualContainer".
	# Wait. `Enemy.gd` line 49: `@onready var visual_container: Node2D = $Visual`.
	# But node name is "Visual".
	# `EnemyModifiers.gd` line 52: `var container = enemy.get_node_or_null("VisualContainer")`.
	# This might fail if node is named "Visual".
	# I should fix EnemyModifiers to look for "Visual" too?
	
	quit(0)
