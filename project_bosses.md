# Système des Boss – PewPewLoot

## Objectif
Ce document décrit le système boss data-driven du projet, comment il est exécuté en runtime, et comment équilibrer/étendre les combats sans casser la lisibilité.

---

## Vue d’ensemble
Le système boss repose sur 3 couches :

1. **Données de boss** (`data/bosses.json`)
   - Définit les stats, visuel, loot, et phases de comportement.
2. **Références de progression monde** (`data/worlds/world_*.json`)
   - Chaque niveau mappe un `boss_id` spécifique au monde.
3. **Runtime gameplay**
   - `scenes/Boss.gd` : exécution des phases (move, tir, modulation cadence/rotation).
   - `autoload/PowerManager.gd` : exécution des pouvoirs spéciaux et hazards.

---

## Schéma de `data/bosses.json`
Chaque entrée de `bosses` contient notamment :

- `id`, `name`
- `hp`, `score`
- `size`, `visual`, `sounds`
- `missile_id`
- `phases` (array)

### Structure d’une phase
- `hp_threshold` : seuil de PV (%) qui active la phase.
- `move_pattern_id` : pattern de déplacement boss.
- `missile_pattern_id` : pattern de tir projectiles.
- `fire_rate` : cadence de base (intervalle en secondes).
- `special_power_id` : id optionnel de pouvoir déclenchable.
- `fire_profile` (optionnel) : variation intra-phase de cadence.
  - `rates`: ex. `[1.0, 0.8, 0.6]`
  - `step_interval`: durée avant changement d’étape
  - `loop`: boucle ou non
- `rotation_profile` (optionnel) : modulation visuelle/rythmique de rotation.

---

## Runtime – `scenes/Boss.gd`
Le boss exécute un cycle phase-driven :

1. Sélection de phase selon `hp_threshold`.
2. Application des modulateurs phase :
   - configuration `fire_profile`
   - configuration `rotation_profile`
   - résolution du `move_pattern_id` (avec fallback legacy).
3. Tick gameplay :
   - déplacement selon pattern,
   - tir selon `missile_pattern_id` + cadence effective,
   - déclenchement de `special_power_id` via `PowerManager`.

### Points importants
- **`figure_eight`** est supporté côté boss runtime.
- Les IDs anciens peuvent être remappés via fallback pour compatibilité.
- Le timer de tir prend en compte la cadence dynamique issue du `fire_profile`.

---

## Powers & Hazards – `autoload/PowerManager.gd`
Les pouvoirs boss (`data/missiles/boss_powers.json`) supportent :

- Patterns projectile (waves/radial/safe-zones, etc.)
- Hazards persistants/télégraphiés via :
  - `hazard` (single)
  - `hazards` (array)

Types de hazard implémentés :

1. **`void_zone`**
   - Script : `scenes/effects/BossVoidZone.gd`
   - Télégraphe puis zone active, dégâts périodiques au joueur.
2. **`laser_line` / `laser_cone`**
   - Script : `scenes/effects/BossLaserZone.gd`
   - Télégraphe, activation, sweep optionnel, lock optionnel.

---

## Organisation des 54 boss
Le projet cible **9 mondes × 6 boss = 54 combats**.

Familles d’IDs :
- `boss_forest_*`
- `boss_atlantis_*`
- `boss_industrial_*`
- `boss_lava_*`
- `boss_mine_*`
- `boss_necro_*`
- `boss_titan_*`
- `boss_alien_*`
- `boss_magic_*`

Les fichiers `data/worlds/world_2.json` à `world_9.json` référencent leurs boss dédiés (plus de placeholder forest).

---

## Règles de tuning recommandées
Objectif gameplay : **dodge lisible d’abord**, pression ensuite.

### 1) Lisibilité
- Garder des fenêtres de respiration entre salves.
- Préférer télégraphes clairs pour hazards (laser/zone).
- Introduire les mécaniques denses progressivement entre phases.

### 2) Cadence de tir
- Éviter les extrêmes constants.
- Passe globale actuelle :
  - clamp profil de tir autour d’un minimum lisible,
  - suppression des pointes extrêmes les plus abruptes.

### 3) Variété
- Mixer déplacement (latéral, orbite, figure-eight, dash courts).
- Alterner patterns : suivi, balayage, zones de contrôle, safe gaps.
- Limiter la répétition stricte de patterns entre boss finaux.

### 4) Progression monde
- Monde bas : patterns plus propres, plus lents.
- Monde haut : layering progressif (mouvement + projectile + hazard), pas de chaos instantané.

---

## Ajouter un nouveau boss (workflow court)
1. Créer entrée dans `data/bosses.json` avec 2–3 phases minimum.
2. Vérifier que tous les IDs référencés existent :
   - `move_pattern_id`
   - `missile_pattern_id`
   - `special_power_id` (si utilisé)
3. Ajouter/adapter pouvoir dans `data/missiles/boss_powers.json`.
4. Mapper le `boss_id` dans `data/worlds/world_X.json`.
5. Vérifier en jeu :
   - lisibilité des télégraphes,
   - difficulté par phase,
   - absence de phase “mur impossible”.

---

## Checklist QA rapide
- JSON valide (`bosses.json`, `boss_powers.json`, `world_*.json`).
- IDs cohérents entre data et runtime.
- Aucun `special_power_id` orphelin.
- Cadences non extrêmes sur une phase entière.
- Combat final lisible mais exigeant (apprentissage + exécution).

---

## Notes de maintenance
- Favoriser les extensions data-first, runtime minimal.
- Si nouvelle mécanique boss récurrente : implémenter une fois dans `PowerManager` + effet dédié.
- Préserver la compat legacy lors d’évolutions de schéma (`fallback` côté `Boss.gd`).

---

## Conventions assets VFX boss

### 1) Point central de config
- Les attaques spéciales boss sont définies de façon centralisée dans `data/missiles/boss_powers.json`.
- Les bosses ne stockent qu’un `special_power_id` par phase dans `data/bosses.json`.
- Le runtime lit/exécute les effets via `autoload/PowerManager.gd`.

### 2) Emplacement et nommage
- Dossier recommandé : `assets/missiles/boss/{power_id}/`
- Nommage source conseillé :
   - `proj_{power_id}_{variant}.png`
   - `proj_{power_id}_{variant}.tres` (SpriteFrames)
- Garder 1 dossier par pouvoir pour éviter la dispersion et simplifier les itérations.

### 3) Règles d’intégration JSON
- Préférer `projectile.asset_anim` (SpriteFrames `.tres`) pour les attaques spéciales boss.
- `projectile.asset` (PNG direct) est supporté mais secondaire.
- Le champ `projectile.size` est interprété comme taille visuelle de base (mode legacy).
- Option avancée possible dans le moteur : `width_pct` / `height_pct` dans `visual_data` (si exposé côté data).

### 4) Dimensions et formes recommandées (px)
Le pipeline actuel utilise majoritairement un rendu carré pour les projectiles (collision circulaire moyenne). Utiliser des sprites avec transparence.

- **Rapid burst / flanking (tirs rapides)**
   - Canvas: `64x64`
   - Forme: pointe, aiguille, petit losange
   - `size` conseillé: `10–14`

- **Aimed / radial / spiral (tir standard)**
   - Canvas: `96x96`
   - Forme: orbe, losange doux, noyau énergétique
   - `size` conseillé: `14–18`

- **Encircle / burst dense (tir lourd)**
   - Canvas: `128x128`
   - Forme: noyau large, impact, cœur dense
   - `size` conseillé: `18–24`

- **Rain top (pluie / traits verticaux)**
   - Canvas: `64x96` ou `64x128`
   - Forme: goutte allongée, trait énergétique
   - `size` conseillé: `12–16`

### 5) Hazards (void/laser)
- Les hazards actuels sont procéduraux (pas d’asset image obligatoire).
- Références de tuning:
   - `void_zone.radius`: `100–170`
   - `laser_line.width`: `70–110`
   - `laser_line.length`: `850–1100`
   - `laser_cone.cone_angle_deg`: `28–55`

### 6) Raccourci production
1. Créer le dossier `assets/missiles/boss/{power_id}/`.
2. Produire sprite source PNG (ou spritesheet), puis exporter `.tres` SpriteFrames.
3. Renseigner `asset_anim` dans `data/missiles/boss_powers.json`.
4. Ajuster `size` en jeu selon lisibilité (dodge-first).
