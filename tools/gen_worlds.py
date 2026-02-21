#!/usr/bin/env python3
"""Generate all 9 world JSON files for pewpewloot."""
import json, os, random

WORLDS_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "worlds")

WAVE_COUNTS = [6, 8, 10, 12, 14, 16]
DURATIONS   = [60, 80, 100, 120, 140, 160]

# Obstacle pool — different difficulty tiers
OBSTACLE_POOL_EASY = [
    {"obstacle_id": "asteroid_small",  "pattern": "rain",   "speed": 180, "gap_width": 160, "row_interval": 1.0, "drift_speed": 15, "drift_directions": ["S", "SW", "SE"]},
    {"obstacle_id": "debris_small",    "pattern": "rain",   "speed": 200, "gap_width": 150, "row_interval": 0.8, "drift_speed": 20, "drift_directions": ["S", "SW", "SE"]},
    {"obstacle_id": "planet_small",    "pattern": "slalom", "speed": 110, "gap_width": 220, "row_interval": 2.0, "drift_speed": 12, "drift_directions": ["S", "SW", "SE"]},
]

OBSTACLE_POOL_MEDIUM = [
    {"obstacle_id": "asteroid_medium", "pattern": "slalom", "speed": 170, "gap_width": 190, "row_interval": 1.2, "drift_speed": 10, "drift_directions": ["SW", "S", "SE"]},
    {"obstacle_id": "metal_wall",      "pattern": "slalom", "speed": 150, "gap_width": 200, "row_interval": 1.5},
    {"obstacle_id": "metal_wall_destructible", "pattern": "gates", "speed": 160, "gap_width": 180, "row_interval": 1.8},
    {"obstacle_id": "energy_barrier",  "pattern": "gates",  "speed": 150, "gap_width": 200, "row_interval": 2.0},
    {"obstacle_id": "planet_medium",   "pattern": "slalom", "speed": 90,  "gap_width": 260, "row_interval": 2.5},
]

OBSTACLE_POOL_HARD = [
    {"obstacle_id": "asteroid_large",  "pattern": "rain",   "speed": 130, "gap_width": 200, "row_interval": 2.0, "drift_speed": 8, "drift_directions": ["SW", "S", "SE"]},
    {"obstacle_id": "planet_large",    "pattern": "slalom", "speed": 70,  "gap_width": 300, "row_interval": 3.0, "drift_speed": 5, "drift_directions": ["SW", "S", "SE"]},
    {"obstacle_id": "asteroid_small",  "pattern": "rain",   "speed": 250, "gap_width": 130, "row_interval": 0.6, "drift_speed": 25, "drift_directions": ["SW", "S", "SE"]},
    {"obstacle_id": "metal_wall",      "pattern": "gates",  "speed": 180, "gap_width": 160, "row_interval": 1.5},
]

biomes = [
    {
        "id": "world_1", "order": 1,
        "name": "Forêt Primordiale",
        "description": "Une forêt ancienne aux canopées denses, où la lumière perce à peine à travers le feuillage.",
        "folder": "forest",
        "far_files": [f"world_forest_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_clouds_{i}.png" for i in range(6)],
        "music": "acceleration.ogg",
        "color": "#2d5a27",
        "mult": {"hp": 1.0, "damage": 1.0, "speed": 1.0},
        "unlock": {"type": "initial"}
    },
    {
        "id": "world_2", "order": 2,
        "name": "Atlantis",
        "description": "Les profondeurs sous-marines où d'anciennes ruines dorment dans l'obscurité abyssale.",
        "folder": "atlantis",
        "far_files": [f"world_water_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_water_{i}.png" for i in range(1, 5)],
        "music": "neon.ogg",
        "color": "#1a5276",
        "mult": {"hp": 1.5, "damage": 1.3, "speed": 1.1},
        "unlock": {"type": "world_clear", "world_id": "world_1"}
    },
    {
        "id": "world_3", "order": 3,
        "name": "Complexe Industriel",
        "description": "Une gigantesque station industrielle aux mécanismes encore actifs et aux corridors labyrinthiques.",
        "folder": "industrial",
        "far_files": [f"world_industrial_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_industrial_{i}.png" for i in range(3, 7)] + ["layer_2_techno_1.png"],
        "music": "starlight.ogg",
        "color": "#5d5d5d",
        "mult": {"hp": 2.5, "damage": 2.0, "speed": 1.2},
        "unlock": {"type": "world_clear", "world_id": "world_2"}
    },
    {
        "id": "world_4", "order": 4,
        "name": "Fournaise",
        "description": "Un monde volcanique en perpétuelle éruption où la lave coule sans fin entre les roches ardentes.",
        "folder": "lava",
        "far_files": [f"world_lava_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_lava_{i}.png" for i in range(2, 6)],
        "music": "acceleration.ogg",
        "color": "#8b2500",
        "mult": {"hp": 4.0, "damage": 3.0, "speed": 1.3},
        "unlock": {"type": "world_clear", "world_id": "world_3"}
    },
    {
        "id": "world_5", "order": 5,
        "name": "Mines Oubliées",
        "description": "Des galeries abandonnées creusées dans la roche, parsemées de cristaux luminescents et de veines minérales.",
        "folder": "mine",
        "far_files": [f"world_mine_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_mine_{i}.png" for i in range(1, 5)] + ["layer_2_crystals.png"],
        "music": "neon.ogg",
        "color": "#4a3728",
        "mult": {"hp": 6.0, "damage": 4.0, "speed": 1.4},
        "unlock": {"type": "world_clear", "world_id": "world_4"}
    },
    {
        "id": "world_6", "order": 6,
        "name": "Nécropole",
        "description": "Une cité morte hantée par les ombres d'un empire déchu, où les murs murmurent encore.",
        "folder": "necropolis",
        "far_files": [f"world_necro_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_necro_{i}.png" for i in range(4)],
        "music": "starlight.ogg",
        "color": "#2c1e3f",
        "mult": {"hp": 8.5, "damage": 5.5, "speed": 1.5},
        "unlock": {"type": "world_clear", "world_id": "world_5"}
    },
    {
        "id": "world_7", "order": 7,
        "name": "Domaine des Titans",
        "description": "Les vestiges colossaux d'êtres titanesques flottent parmi les nuages cosmiques et la poussière d'étoiles.",
        "folder": "titans",
        "far_files": [f"titan_world_{i}.png" for i in range(6)],
        "mid_files": (
            [f"layer_2_titans_{i}.png" for i in range(3)]
            + [f"layer_2_clouds_{i}.png" for i in range(3, 6)]
            + ["layer_2_cosmicdust_1.png", "layer_2_cosmisdust_2.png"]
        ),
        "music": "acceleration.ogg",
        "color": "#c0a060",
        "mult": {"hp": 11.0, "damage": 7.0, "speed": 1.6},
        "unlock": {"type": "world_clear", "world_id": "world_6"}
    },
    {
        "id": "world_8", "order": 8,
        "name": "Ruche Alien",
        "description": "Un organisme vivant géant dont les parois pulsent d'une énergie biologique extraterrestre.",
        "folder": "alien",
        "far_files": [f"world_bio_{i}.png" for i in range(6)],
        "mid_files": [f"layer_2_alien_{i}.png" for i in range(1, 5)],
        "music": "neon.ogg",
        "color": "#1a4d1a",
        "mult": {"hp": 15.0, "damage": 10.0, "speed": 1.8},
        "unlock": {"type": "world_clear", "world_id": "world_7"}
    },
    {
        "id": "world_9", "order": 9,
        "name": "Royaume Magique",
        "description": "Un plan dimensionnel éthéré où la magie pure façonne la réalité et défie les lois de la physique.",
        "folder": "magical",
        "far_files": ["magical_1.png"] * 6,
        "mid_files": ["layer_2_feathers_1.png", "layer_2_magical.png"],
        "music": "starlight.ogg",
        "color": "#7b2d8e",
        "mult": {"hp": 20.0, "damage": 14.0, "speed": 2.0},
        "unlock": {"type": "world_clear", "world_id": "world_8"}
    },
]

level_names = [
    # 1 - forest
    ["Lisière", "Sous-bois", "Clairière", "Marécage", "Cœur de la Forêt", "Le Gardien Sylvestre"],
    # 2 - atlantis
    ["Récifs", "Grottes Marines", "Ruines Immergées", "Abysses", "Palais Englouti", "Le Léviathan"],
    # 3 - industrial
    ["Dock d'Amarrage", "Couloirs de Maintenance", "Salle des Machines", "Réacteur Central", "Zone Interdite", "L'Automate"],
    # 4 - lava
    ["Coulée de Lave", "Cratère Fumant", "Cavernes Ardentes", "Forge Éternelle", "Cœur du Volcan", "L'Élémentaire"],
    # 5 - mine
    ["Entrée de la Mine", "Galeries Effondrées", "Veine de Cristaux", "Lac Souterrain", "Noyau Minéral", "Le Golem"],
    # 6 - necropolis
    ["Portail des Morts", "Catacombes", "Crypte Royale", "Salle du Trône", "Autel des Ombres", "Le Nécromancien"],
    # 7 - titans
    ["Pieds des Colosses", "Épaules de Géants", "Passerelles Célestes", "Nuages d'Éther", "Sommet du Titan", "Le Colosse"],
    # 8 - alien
    ["Membrane Externe", "Canaux Organiques", "Chambre d'Incubation", "Réseau Neural", "Noyau Vital", "La Reine"],
    # 9 - magical
    ["Orée Enchantée", "Cascade de Mana", "Jardins Cristallins", "Bibliothèque Astrale", "Nexus de Pouvoir", "L'Archimage"],
]


def pick_obstacle(world_order: int, level_index: int, obs_index: int) -> dict:
    """Pick an obstacle from pools based on world + level difficulty."""
    random.seed(world_order * 1000 + level_index * 100 + obs_index)

    # Early worlds = easy obstacles, later = harder mix
    if world_order <= 2:
        pool = OBSTACLE_POOL_EASY + OBSTACLE_POOL_MEDIUM[:2]
    elif world_order <= 5:
        pool = OBSTACLE_POOL_EASY + OBSTACLE_POOL_MEDIUM + OBSTACLE_POOL_HARD[:1]
    else:
        pool = OBSTACLE_POOL_MEDIUM + OBSTACLE_POOL_HARD

    # Higher level_index within a world -> bias towards harder
    if level_index >= 3 and world_order >= 3:
        pool = pool + OBSTACLE_POOL_HARD

    return random.choice(pool)


def build_waves(wave_count, duration, level_index, world_order):
    """Build interleaved enemy + obstacle waves.
    
    Every 3 enemy waves, insert 1 obstacle wave.
    Pattern: E E E O E E E O ...
    """
    total_wave_slots = wave_count  # total enemy waves requested
    
    # Calculate how many obstacle waves we'll insert
    obstacle_count = max(0, (total_wave_slots - 1) // 3)
    total_entries = total_wave_slots + obstacle_count
    
    # Time spacing based on total entries
    spacing = (duration - 6.0) / max(total_entries, 1)
    
    waves = []
    enemy_idx = 0
    obs_idx = 0
    
    for slot in range(total_entries):
        t = round(3.0 + slot * spacing, 1)
        
        # Every 4th slot (index 3, 7, 11...) is an obstacle
        if slot > 0 and slot % 4 == 3:
            # Obstacle wave
            obs_template = pick_obstacle(world_order, level_index, obs_idx)
            obs_wave = {
                "time": t,
                "type": "obstacle",
                "obstacle_id": obs_template["obstacle_id"],
                "pattern": obs_template["pattern"],
                "duration": round(min(spacing * 2.5, 15.0), 1),
                "speed": obs_template["speed"],
                "gap_width": obs_template["gap_width"],
                "row_interval": obs_template["row_interval"],
                "sprite_path": ""
            }
            # Add drift if defined
            if "drift_speed" in obs_template:
                obs_wave["drift_speed"] = obs_template["drift_speed"]
            if "drift_directions" in obs_template:
                obs_wave["drift_directions"] = obs_template["drift_directions"]
            
            waves.append(obs_wave)
            obs_idx += 1
        else:
            # Enemy wave
            count = 3 + level_index + (enemy_idx // 3)
            waves.append({
                "time": t,
                "enemy_id": "scout_basic",
                "enemy_skin": "",
                "count": count,
                "interval": 0.7,
                "enemy_modifier_id": ""
            })
            enemy_idx += 1
    
    return waves


def main():
    os.makedirs(WORLDS_DIR, exist_ok=True)

    for idx, biome in enumerate(biomes):
        base_bg = f"res://assets/backgrounds/worlds/{biome['folder']}/"

        world = {
            "id": biome["id"],
            "name": biome["name"],
            "description": biome["description"],
            "order": biome["order"],
            "multipliers": biome["mult"],
            "theme": {
                "background": "",
                "music": f"res://assets/music/{biome['music']}",
                "color_palette": biome["color"]
            },
            "levels": [],
            "unlock_condition": biome["unlock"]
        }

        for lvl_idx in range(6):
            wave_count = WAVE_COUNTS[lvl_idx]
            duration  = DURATIONS[lvl_idx]
            is_boss   = (lvl_idx == 5)

            far_file = biome["far_files"][lvl_idx]
            mid_file = biome["mid_files"][lvl_idx % len(biome["mid_files"])]

            waves = build_waves(wave_count, duration, lvl_idx, biome["order"])

            level = {
                "index": lvl_idx,
                "id": f"{biome['id']}_lvl_{lvl_idx}",
                "name": level_names[idx][lvl_idx],
                "type": "boss" if is_boss else "normal",
                "duration_sec": duration,
                "backgrounds": {
                    "card": base_bg + far_file,
                    "far_layer": base_bg + far_file,
                    "mid_layer": [
                        [
                            {
                                "asset": base_bg + mid_file,
                                "opacity": 1.0
                            }
                        ]
                    ],
                    "near_layer": []
                },
                "waves": waves,
                "events": []
            }

            if is_boss:
                level["boss_id"] = "boss_world1"

            world["levels"].append(level)

        filepath = os.path.join(WORLDS_DIR, f"{biome['id']}.json")
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(world, f, indent="\t", ensure_ascii=False)
        print(f"Created {os.path.basename(filepath)}")

    print(f"\nDone! {len(biomes)} world files created in {WORLDS_DIR}")


if __name__ == "__main__":
    main()
