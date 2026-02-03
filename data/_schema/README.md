# PewPewLoot — Data Schema Documentation

Ce document décrit les formats JSON utilisés pour la configuration du jeu.
Modifier ces fichiers permet d'ajouter/modifier du contenu sans toucher au code.

---

## Structure des dossiers

```
data/
├── worlds/           # Un fichier JSON par monde
│   ├── world_1.json
│   └── ...
├── ships/
│   └── ships.json    # Tous les vaisseaux jouables
├── enemies/
│   └── enemies.json  # Tous les ennemis (normaux, élites, boss)
├── loot/
│   ├── affixes.json      # Slots, raretés, et affixes
│   ├── loot_tables.json  # Tables de drop par boss
│   └── uniques.json      # Items uniques
└── _schema/
    └── README.md     # Ce fichier
```

---

## Monde (`worlds/world_X.json`)

```json
{
  "id": "world_1",                           // Identifiant unique (string)
  "name": "Nom du monde",                    // Nom affiché
  "description": "Description du monde",     // Texte descriptif
  "order": 1,                                // Ordre d'affichage
  "theme": {
    "background": "res://...",               // Chemin vers asset background
    "music": "res://...",                    // Chemin vers musique
    "color_palette": "#XXXXXX"               // Couleur dominante
  },
  "levels": [ ... ],                         // Tableau de niveaux (voir ci-dessous)
  "unlock_condition": {
    "type": "initial" | "boss_kill",         // Condition de déverrouillage
    "boss_id": "..."                         // (si boss_kill) ID du boss à tuer
  }
}
```

### Niveau (dans `levels[]`)

```json
{
  "index": 0,                                // Index du niveau (0-5, 5 = boss)
  "name": "Nom du niveau",
  "type": "normal" | "boss",
  
  // Pour type = "normal":
  "duration_sec": 120,                       // Durée en secondes
  "waves": [
    { "enemy_id": "scout", "count": 5, "delay": 2.0 }
  ],
  "events": [
    { "type": "minefield", "trigger_time": 60 }
  ],
  
  // Pour type = "boss":
  "boss_id": "asteroid_guardian",
  "phases": [
    { "hp_percent": 100, "pattern": "phase_1" }
  ],
  "loot_table": "boss_world_1"
}
```

---

## Vaisseaux (`ships/ships.json`)

```json
{
  "ships": [
    {
      "id": "ship_car",                      // Identifiant unique
      "name": "Car",                         // Nom affiché
      "description": "...",                  // Description
      "sprite": "res://...",                 // Chemin vers sprite
      "stats": {
        "power": 10,                         // Puissance de base
        "special_cdr": 5,                    // Réduction cooldown spécial
        "missile_speed": 3,                  // Vitesse missiles
        "max_hp": 100,                       // Points de vie max
        "move_speed": 200                    // Vitesse de déplacement
      },
      "special": {
        "id": "paint_attack",
        "name": "Paint Attack",
        "description": "...",
        "cooldown": 8.0,
        "damage": 25                         // + autres paramètres spécifiques
      },
      "passive": {
        "id": "road_rage",
        "name": "Road Rage",
        "description": "+15% dégâts quand HP < 30%"
      },
      "unlock_condition": {
        "type": "initial" | "boss_kill",
        "boss_id": "..."                     // (si boss_kill)
      }
    }
  ],
  "default_unlocked": ["ship_car", "ship_plane"]   // Vaisseaux débloqués par défaut
}
```

---

## Ennemis (`enemies/enemies.json`)

```json
{
  "enemies": [
    {
      "id": "scout",                         // Identifiant unique
      "name": "Éclaireur",
      "description": "...",
      "sprite": "res://...",
      "type": "normal" | "elite" | "boss",
      "stats": {
        "hp": 10,
        "power": 2,
        "speed": 80
      },
      "pattern": "straight_down",            // Pattern de déplacement
      "fire_rate": 1.5,                      // Tirs par seconde
      "projectile_type": "enemy_basic",      // Type de projectile
      "loot_chance": 0.05,                   // Chance de drop (0-1)
      
      // Boss uniquement:
      "phases": [
        { "hp_percent": 100, "pattern": "phase_1", "attacks": ["spread_shot"] }
      ],
      "loot_table": "boss_world_1"
    }
  ]
}
```

---

## Affixes (`loot/affixes.json`)

### Slots

```json
{
  "slots": [
    { 
      "id": "reactor", 
      "name": "Réacteur", 
      "icon": "res://...",
      "description": "..." 
    }
  ]
}
```

### Raretés

```json
{
  "rarities": [
    { 
      "id": "common", 
      "name": "Commun", 
      "color": "#AAAAAA",    // Couleur pour l'UI
      "affix_count": 1,      // Nombre d'affixes générés
      "weight": 60           // Poids pour le RNG (plus haut = plus fréquent)
    }
  ]
}
```

### Affixes

```json
{
  "affixes": {
    "global": [              // Affixes disponibles pour TOUS les slots
      {
        "id": "flat_damage",
        "name": "Dégâts",
        "stat": "damage",
        "type": "flat" | "percent",
        "range": {
          "common": [1, 3],      // [min, max] par rareté
          "legendary": [8, 15]
        }
      }
    ],
    "reactor": [ ... ],      // Affixes spécifiques au slot reactor
    "engine": [ ... ]
  }
}
```

---

## Loot Tables (`loot/loot_tables.json`)

```json
{
  "boss_world_1": {
    "name": "Gardien d'Astéroïdes",
    "guaranteed_drops": 2,               // Nombre d'items garantis
    "bonus_drops": {
      "chance": 0.25,                    // Chance de drop bonus
      "count": 1                         // Nombre de drops bonus
    },
    "rarity_weights": {
      "common": 20,
      "uncommon": 40,
      "rare": 30,
      "legendary": 8,
      "unique": 2
    },
    "unique_pool": ["unique_asteroid_core", "unique_guardian_shield"],
    "material_drops": [
      { "id": "asteroid_fragment", "count_min": 2, "count_max": 5 }
    ]
  }
}
```

---

## Uniques (`loot/uniques.json`)

```json
{
  "uniques": [
    {
      "id": "unique_asteroid_core",
      "name": "Cœur d'Astéroïde",
      "slot": "reactor",
      "source_boss": "asteroid_guardian",
      "sprite": "res://...",
      "description": "...",
      "stats": {
        "energy_regen": 5,
        "cooldown_reduction": 10
      },
      "unique_effect": {
        "id": "core_pulse",
        "name": "Pulse du Noyau",
        "description": "Quand vous subissez des dégâts, récupérez 15% de votre énergie max.",
        "trigger": "on_hit_received" | "on_enemy_kill" | "passive" | "on_dash" | ...
      }
    }
  ]
}
```

---

## Ajouter du contenu

### Nouveau monde
1. Créer `data/worlds/world_6.json`
2. Suivre le format ci-dessus
3. Définir `unlock_condition` avec le boss du monde précédent

### Nouveau vaisseau
1. Éditer `data/ships/ships.json`
2. Ajouter une entrée dans le tableau `ships`
3. Définir `unlock_condition`

### Nouveau boss
1. Ajouter l'ennemi dans `data/enemies/enemies.json` avec `"type": "boss"`
2. Créer sa loot table dans `data/loot/loot_tables.json`
3. (Optionnel) Ajouter ses uniques dans `data/loot/uniques.json`

### Nouvel affix
1. Éditer `data/loot/affixes.json`
2. Ajouter dans `global` (tous slots) ou dans un slot spécifique
