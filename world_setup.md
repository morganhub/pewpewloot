# World Setup — Structure des Mondes

Ce document décrit la structure des fichiers de données pour les mondes, niveaux, vagues, ennemis, boss et obstacles.

---

## Arborescence des assets

```
assets/
├── enemies/
│   └── {WORLD_NAME}/         # ex: forest/
│       ├── {world}_swarmer.tres    (.tres = animated, .png = static)
│       ├── {world}_fighter.tres
│       ├── {world}_tank.tres
│       ├── {world}_artillery.tres
│       └── {world}_elite.tres
├── bosses/
│   └── {WORLD_NAME}/
│       ├── {world}_boss_1.tres
│       ├── {world}_boss_2.tres
│       ├── ...
│       └── {world}_boss_final.tres
├── obstacles/
│   └── {WORLD_NAME}/
│       ├── {world}_obstacle_circle_1.png   (forme circulaire)
│       ├── {world}_obstacle_circle_2.png
│       ├── {world}_obstacle_rectangle_1.png (forme rectangulaire)
│       └── ...
├── music/
│   └── {WORLD_NAME}/
│       └── {world}_music.ogg
└── backgrounds/
    └── worlds/{WORLD_NAME}/
        ├── world_{name}_0.png    (far layer / card)
        ├── layer_2_{name}_1.png  (mid layer)
        └── ...
```

---

## Structure d'un `world_x.json`

```json
{
  "id": "world_1",
  "name": "Forêt Primordiale",
  "description": "...",
  "order": 1,
  "story_id": "story_world_1_intro",

  "skin_overrides": {
    "enemies": {
      "swarmer": "res://assets/enemies/forest/forest_swarmer.tres",
      "fighter": "res://assets/enemies/forest/forest_fighter.tres",
      "tank":    "res://assets/enemies/forest/forest_tank.tres",
      "artillery": "res://assets/enemies/forest/forest_artillery.tres",
      "elite":   "res://assets/enemies/forest/forest_elite.tres"
    },
    "bosses": {
      "boss_forest_final": "res://assets/bosses/forest/forest_boss_final.tres"
    },
    "obstacles": {
      "circle": [
        "res://assets/obstacles/forest/forest_obstacle_circle_1.png",
        "res://assets/obstacles/forest/forest_obstacle_circle_2.png"
      ],
      "rectangle": [
        "res://assets/obstacles/forest/forest_obstacle_rectangle_1.png"
      ]
    }
  },

  "multipliers": { "hp": 1.0, "damage": 1.0, "speed": 1.0 },
  "theme": {
    "background": "",
    "sphere_texture": "res://assets/backgrounds/worlds/forest/level_0.jpg",
    "music": "res://assets/music/forest/forest_music.ogg",
    "color_palette": "#2d5a27"
  },

  "levels": [ ... ]
}
```

---

## Skin Overrides — Comment ça marche

### Priorité de résolution

1. **`skin_overrides` du monde** (dans `world_x.json`) — priorité haute
2. **`enemy_skin` par wave** (legacy, dans les données de wave) — fallback
3. **Asset par défaut** (dans `enemies.json`, `bosses.json`, `obstacles.json`) — dernier recours

### Enemies

Le bloc `skin_overrides.enemies` mappe chaque `enemy_id` vers son asset visuel pour ce monde.

```json
"skin_overrides": {
  "enemies": {
    "swarmer": "res://assets/enemies/forest/forest_swarmer.tres"
  }
}
```

- Le `WaveManager` résout automatiquement le skin depuis ce bloc.
- Les assets peuvent être `.tres` (SpriteFrames animé) ou `.png` (statique).

### Bosses

Le bloc `skin_overrides.bosses` mappe chaque `boss_id` vers son asset visuel.

```json
"skin_overrides": {
  "bosses": {
    "boss_forest_final": "res://assets/bosses/forest/forest_boss_final.tres"
  }
}
```

- Appliqué par `Game.gd` avant `boss.setup()`.

### Obstacles

Le bloc `skin_overrides.obstacles` mappe des clés vers des arrays de sprites. Un sprite est choisi aléatoirement par obstacle.

- **Obstacles explosifs** (`type: "explosive"` dans `obstacles.json`) : utilisent la clé **`explosives`** si elle est définie. Sinon, fallback sur le `sprite_path` par défaut de l'obstacle.
- **Autres obstacles** (ex. pusher) : utilisent la **shape** (`circle`, `rectangle`) comme clé. Si le monde n'a pas d'override pour cette shape, le `sprite_path` par défaut de `obstacles.json` est utilisé.

```json
"skin_overrides": {
  "obstacles": {
    "circle": ["res://assets/obstacles/forest/forest_obstacle_circle_1.png", "..."],
    "rectangle": ["res://assets/obstacles/forest/forest_obstacle_rectangle_1.png"],
    "explosives": ["res://assets/obstacles/forest/forest_obstacle_explosive_1.png", "..."]
  }
}
```

---

## Types d'ennemis

Définis dans `data/enemies.json`. Chaque ennemi a un ID unique réutilisé dans tous les mondes.

| ID | Rôle | Caractéristiques |
|:---|:-----|:-----------------|
| `swarmer` | Léger, rapide, en nombre | HP faible, vitesse élevée |
| `fighter` | Polyvalent | HP/dégâts moyens |
| `tank` | Résistant, lent | HP très élevé, vitesse faible |
| `artillery` | Tireur à distance | HP moyen, tir puissant |
| `elite` | Redoutable | HP élevé, vitesse/dégâts forts |

---

## Structure d'un niveau (`levels[]`)

```json
{
  "index": 0,
  "id": "world_1_lvl_0",
  "name": "Lisière",
  "type": "normal",
  "duration_sec": 60,
  "backgrounds": {
    "card": "res://...",
    "sphere_texture": "res://...",
    "far_layer": "res://...",
    "mid_layer": [ [{ "asset": "res://...", "opacity": 1.0 }] ],
    "near_layer": []
  },
  "waves": [ ... ],
  "events": [],
  "boss_id": ""
}
```

- Chaque niveau a un `boss_id` non vide (ex: `"boss_forest_1"` ou `"boss_forest_final"`).
- `type` : `"normal"` ou `"boss"`.
- **`sphere_texture`** : texture affichée sur la sphère 3D en sélection de niveau (sinon fallback sur `card`).

---

## Sphère 3D (World Select / Level Select)

L’élément central des écrans **Sélection du monde** et **Sélection du niveau** est une **sphère 3D** qui tourne lentement sur l’axe pôle nord / pôle sud.

- **Monde** : la texture de la sphère vient de `theme.sphere_texture` (ou `theme.background` en fallback).
- **Niveau** : la texture vient de `backgrounds.sphere_texture` (ou `backgrounds.card` en fallback).

Format de texture recommandé : **équirectangulaire** (latitude/longitude), ratio 2:1 (largeur = 2 × hauteur), pour un habillage correct sur la sphère.

### Bonne texture sphère avec Midjourney

Pour obtenir une texture qui s’enroule bien autour de la sphère :

1. **Demander une projection équirectangulaire**  
   Par exemple : *“equirectangular panorama of [ton sujet], 360 degree, seamless, 2:1 ratio”* ou *“planet texture, seamless tileable, equirectangular projection”*.

2. **Sujets adaptés**  
   Paysages, planètes, atmosphères, cartes, motifs répétables. Éviter un cadrage “photo” centré (ça déforme mal sur la sphère).

3. **Seamless / tileable**  
   Les bords gauche et droite de l’image doivent se raccorder (mot-clé *seamless* ou *tileable*).

4. **Ratio 2:1**  
   Indiquer *“2:1 aspect ratio”* ou exporter en 4096×2048 (ou 2048×1024) pour un bon compromis qualité/performance.

5. **Variantes utiles**  
   - *“stylized planet surface, equirectangular, seamless”*  
   - *“fantasy forest canopy view from above, 360 panorama, 2:1”*  
   - *“underwater coral reef, panoramic, seamless texture”*

Tu peux ensuite utiliser l’image telle quelle comme `sphere_texture` (ou `card`) dans les JSON.

**Réglages globaux** (`game.json` → `world_select.sphere`) : `rotation_speed`, `radius`, `light_energy`, `uv_scale`, `uv_overlap`, `uv_offset_u`/`uv_offset_v`. **Caméra** : `camera_distance` (z, sinon auto), `camera_fov` (degrés, défaut 75), `camera_offset_x`, `camera_offset_y`.

---

## Structure d'une wave

### Wave ennemi

```json
{
  "time": 3.0,
  "enemy_id": "swarmer",
  "count": 3,
  "interval": 0.7,
  "enemy_modifier_id": ""
}
```

- `time` : secondes depuis le début du niveau.
- `enemy_id` : référence un ennemi dans `enemies.json`.
- `count` : nombre d'ennemis à spawn.
- `interval` : délai entre chaque spawn.
- `enemy_modifier_id` : modificateur optionnel.

### Wave obstacle

```json
{
  "time": 26.1,
  "type": "obstacle",
  "obstacle_id": "asteroid_medium",
  "pattern": "slalom",
  "duration": 15.0,
  "speed": 170,
  "gap_width": 190,
  "row_interval": 1.2,
  "drift_speed": 10,
  "drift_directions": ["SW", "S", "SE"]
}
```

- `obstacle_id` : référence un obstacle dans `obstacles.json`.
- Le sprite est résolu via `skin_overrides.obstacles` : **explosives** pour les obstacles de type explosif, **circle** / **rectangle** pour les autres, puis `sprite_path` de `obstacles.json` en fallback.
- `pattern` : disposition des obstacles (`"slalom"`, etc.).

---

## Bosses (`data/bosses.json`)

Chaque boss a :
- Un `id` unique (ex: `boss_forest_1`).
- Des `phases` avec seuils HP, patterns de mouvement/tir, et `special_power_id`.
- Un `visual` avec `asset` (statique) et `asset_anim` (animé).
- Un `loot_table` pour les récompenses uniques.

---

## Checklist pour ajouter un nouveau monde

1. **Créer les assets** dans les dossiers correspondants :
   - `assets/enemies/{WORLD_NAME}/` — 5 sprites (swarmer, fighter, tank, artillery, elite)
   - `assets/bosses/{WORLD_NAME}/` — sprites pour chaque boss
   - `assets/obstacles/{WORLD_NAME}/` — sprites circle, rectangle et explosives (obstacles explosifs)
   - `assets/music/{WORLD_NAME}/` — musique(s)
   - `assets/backgrounds/worlds/{WORLD_NAME}/` — far/mid/near layers

2. **Ajouter les bosses** dans `data/bosses.json`.

3. **Créer `world_x.json`** dans `data/worlds/` avec :
   - Bloc `skin_overrides` rempli avec les chemins des assets
   - `theme.music` vers le fichier audio
   - `levels[]` avec les vagues variées
   - `boss_id` sur chaque niveau (bosses intermédiaires et final)

4. **Tester** le monde dans le jeu.
