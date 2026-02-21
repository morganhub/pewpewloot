import json
import os

BASE_DIR = "c:/Tafor/Projet/pewpewloot/data/worlds"

# World 1 = Forest theme with full overrides
FOREST_OVERRIDES = {
    "enemies": {
        "swarmer": "res://assets/enemies/forest/forest_swarmer.tres",
        "fighter": "res://assets/enemies/forest/forest_fighter.tres",
        "tank": "res://assets/enemies/forest/forest_tank.tres",
        "artillery": "res://assets/enemies/forest/forest_artillery.tres",
        "elite": "res://assets/enemies/forest/forest_elite.tres"
    },
    "bosses": {
        "boss_forest_final": "res://assets/bosses/forest/forest_boss_final.tres"
    },
    "obstacles": {
        "circle": [
            "res://assets/obstacles/forest/forest_obstacle_circle_1.png",
            "res://assets/obstacles/forest/forest_obstacle_circle_2.png",
            "res://assets/obstacles/forest/forest_obstacle_circle_3.png",
            "res://assets/obstacles/forest/forest_obstacle_circle_4.png"
        ],
        "rectangle": [
            "res://assets/obstacles/forest/forest_obstacle_rectangle_1.png",
            "res://assets/obstacles/forest/forest_obstacle_rectangle_2.png",
            "res://assets/obstacles/forest/forest_obstacle_rectangle_3.png"
        ]
    }
}

# Empty overrides for other worlds (will use defaults from enemies.json/obstacles.json)
EMPTY_OVERRIDES = {
    "enemies": {},
    "bosses": {},
    "obstacles": {}
}

def clean_waves(levels):
    """Remove enemy_skin and sprite_path from individual waves."""
    if not isinstance(levels, list):
        return
    for level in levels:
        if not isinstance(level, dict):
            continue
        waves = level.get("waves", [])
        if not isinstance(waves, list):
            continue
        for wave in waves:
            if not isinstance(wave, dict):
                continue
            # Remove enemy_skin from enemy waves
            if "enemy_skin" in wave:
                del wave["enemy_skin"]
            # Remove sprite_path from obstacle waves (will be resolved from world overrides or obstacles.json)
            if "sprite_path" in wave:
                del wave["sprite_path"]

def process_world(file_path, overrides):
    if not os.path.exists(file_path):
        print(f"Skipping {file_path}, not found.")
        return
    
    print(f"Processing {file_path}...")
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Add skin_overrides at root level
    data["skin_overrides"] = overrides
    
    # Clean waves
    clean_waves(data.get("levels", []))
    
    # Reorder keys: id, name, description, order, story_id, skin_overrides, multipliers, theme, levels, unlock_condition
    ordered = {}
    key_order = ["id", "name", "description", "order", "story_id", "skin_overrides", "multipliers", "theme", "levels", "unlock_condition"]
    for k in key_order:
        if k in data:
            ordered[k] = data[k]
    # Add any remaining keys
    for k in data:
        if k not in ordered:
            ordered[k] = data[k]
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(ordered, f, indent='\t', ensure_ascii=False)
    print(f"  Done: {file_path}")

# Process World 1 with Forest overrides
process_world(os.path.join(BASE_DIR, "world_1.json"), FOREST_OVERRIDES)

# Process Worlds 2-9 with empty overrides
for i in range(2, 10):
    process_world(os.path.join(BASE_DIR, f"world_{i}.json"), EMPTY_OVERRIDES)

print("\nAll world files updated.")
