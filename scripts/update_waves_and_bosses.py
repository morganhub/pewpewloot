import json
import os
import random

BASE_DIR = "c:/Tafor/Projet/pewpewloot/data/worlds"

def get_boss_id_for_level(level_index):
    # Mapping level index (0-5) to boss IDs
    # Level 0 -> boss_forest_1
    # ...
    # Level 4 -> boss_forest_5
    # Level 5 -> boss_forest_final
    if level_index < 5:
        return f"boss_forest_{level_index + 1}"
    else:
        return "boss_forest_final"

def update_world_file(file_path):
    if not os.path.exists(file_path):
        print(f"Skipping {file_path}")
        return

    print(f"Processing {file_path}...")
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    levels = data.get("levels", [])
    if isinstance(levels, list):
        for lvl in levels:
            if not isinstance(lvl, dict):
                continue
            
            # 1. Update boss_id for EVERY level
            idx = lvl.get("index", 0)
            new_boss = get_boss_id_for_level(idx)
            lvl["boss_id"] = new_boss
            
            # 2. Update wave counts (min 10, max 16) for enemy waves
            waves = lvl.get("waves", [])
            if isinstance(waves, list):
                for wave in waves:
                    if not isinstance(wave, dict):
                        continue
                    
                    # Check if it's an enemy wave (has enemy_id)
                    if "enemy_id" in wave:
                        # Random count 10-16
                        start_count = wave.get("count", 1)
                        # Only increase if it's currently low (safety check? No user said "Mets tout à jour")
                        # User said "ajouter des ennemis... min 10 max 16".
                        wave["count"] = random.randint(10, 16)

    # Save
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent='\t', ensure_ascii=False)
    print(f"  Updated {file_path}")

# Process all worlds 1-9
for i in range(1, 10):
    path = os.path.join(BASE_DIR, f"world_{i}.json")
    update_world_file(path)

print("Batch update of boss IDs and wave counts complete.")
