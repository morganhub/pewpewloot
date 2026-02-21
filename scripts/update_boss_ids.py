import json
import os

BASE_DIR = "c:/Tafor/Projet/pewpewloot/data/worlds"

def update_boss_id(file_path, new_boss_id):
    if not os.path.exists(file_path):
        return
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    levels = data.get("levels", [])
    for level in levels:
        if isinstance(level, dict) and "boss_id" in level:
            old = level["boss_id"]
            level["boss_id"] = new_boss_id
            print(f"  Updated boss_id: {old} -> {new_boss_id} in level {level.get('id', '?')}")
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent='\t', ensure_ascii=False)

# World 1: use boss_forest_final
print("World 1:")
update_boss_id(os.path.join(BASE_DIR, "world_1.json"), "boss_forest_final")

# Worlds 2-9: keep boss_forest_final as placeholder until they get their own bosses
for i in range(2, 10):
    print(f"\nWorld {i}:")
    update_boss_id(os.path.join(BASE_DIR, f"world_{i}.json"), "boss_forest_final")

print("\nDone.")
