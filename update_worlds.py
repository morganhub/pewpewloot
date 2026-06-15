import json
import glob
import os

files = glob.glob(r"c:\Tafor\Projet\pewpewloot\data\worlds\world_*.json")

for file in files:
    with open(file, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    dirty = False
    if "skin_overrides" in data and "bosses" in data["skin_overrides"]:
        bosses = data["skin_overrides"]["bosses"]
        new_bosses = {}
        # Keep original order while adding
        for k, v in list(bosses.items()):
            new_bosses[k] = v
            if not k.endswith("_animation_duration") and not k.endswith("_animation_frequency"):
                dur_key = f"{k}_animation_duration"
                freq_key = f"{k}_animation_frequency"
                if dur_key not in bosses:
                    new_bosses[dur_key] = 2.0
                    dirty = True
                if freq_key not in bosses:
                    new_bosses[freq_key] = 8.0
                    dirty = True
        
        data["skin_overrides"]["bosses"] = new_bosses
    
    if dirty:
        with open(file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent='\t', ensure_ascii=False)
