import json
import random
import os

new_enemies = ["swarmer", "fighter", "tank", "artillery", "elite"]
old_ids = ["scout_basic", "fighter_aggressive", "bomber_heavy", "spinner_circular", "sniper_precise", "tank_armored", "drone_fast", "artillery_stationary", "interceptor_diagonal", "bouncer_erratic"]

# Worlds to process
target_worlds = range(2, 10)

def get_random_enemy():
    return random.choice(new_enemies)

def process_file(file_path):
    if not os.path.exists(file_path):
        print(f"Skipping {file_path}, does not exist.")
        return

    print(f"Processing {file_path}...")
    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error decoding {file_path}: {e}")
            return

    # Helper function to modify waves
    def modify_waves(waves_list):
        if not isinstance(waves_list, list):
            return
        for wave in waves_list:
            if not isinstance(wave, dict):
                continue
            
            # Check if this wave spawns an enemy
            if "enemy_id" in wave and wave["enemy_id"] in old_ids:
                # Replace with random new ID
                wave["enemy_id"] = get_random_enemy()
                # Clear enemy_skin to use default
                if "enemy_skin" in wave:
                    wave["enemy_skin"] = ""

    # Iterate through levels
    levels = data.get("levels", [])
    if isinstance(levels, list):
        for lvl in levels:
            if isinstance(lvl, dict):
                waves = lvl.get("waves", [])
                modify_waves(waves)

    # Save back
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent='\t', ensure_ascii=False)
    print(f"Saved {file_path}")

# Run update
for idx in target_worlds:
    path = f"c:/Tafor/Projet/pewpewloot/data/worlds/world_{idx}.json"
    process_file(path)

print("Batch update complete.")
