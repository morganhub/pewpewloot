# PathTrial - Etat actuel du projet

## 1) Objectif gameplay
PathTrial est une mecanique de "safe path" sur fond de danger plein ecran:
- Le joueur doit rester dans la zone de chemin securisee.
- Hors chemin, il prend des degats par ticks.
- Le systeme est data-driven et utilisable:
  - en vague de niveau (WaveManager),
  - en hazard de boss (PowerManager).

## 2) Donnees JSON en production

### A. `data/game.json` -> `path_trial_defaults`
Ce bloc centralise les valeurs par defaut:

```json
"path_trial_defaults": {
  "default_tick_damage": 10,
  "default_tick_interval_sec": 0.5,
  "default_hazard_start_asset": "res://assets/hazards/lava_bg.tres",
  "default_hazard_asset": "res://assets/hazards/lava_bg.tres",
  "default_path_asset": "",
  "force_default_path_asset": true,
  "default_path_asset_scale": 3.0,
  "path_width": 120.0,
  "start_delay_sec": 1.5,
  "warmup_sec": 1.5,
  "head_length_px": 260.0,
  "tail_length_px": 180.0
}
```

Notes:
- `start_delay_sec` est prioritaire, `warmup_sec` reste supporte en fallback.
- `force_default_path_asset = true` force l'usage de `default_path_asset` meme si une vague specifie `path_asset_override`.

### B. `data/worlds/world_X.json` -> vague `type: "path_trial"`
Exemple d'override par vague:

```json
{
  "type": "path_trial",
  "pattern_id": "dna_helix",
  "speed": 190.0,
  "tick_damage": 12,
  "tick_interval_sec": 0.35,
  "path_width": 120.0,
  "warmup_sec": 1.0,
  "head_length_px": 280.0,
  "tail_length_px": 180.0,
  "hazard_asset_override": "res://assets/missiles/",
  "path_asset_override": "res://assets/missiles/blue_energy.tres"
}
```

### C. Boss hazards
Le meme schema est supporte via le systeme hazard de boss (`type: "path_trial"`).

## 3) Cycle runtime PathTrial

1. **Phase start (pre-damage)**  
   Duree `start_delay_sec` (ou fallback `warmup_sec`): visuel `hazard_start`, pas de degats.

2. **Phase active**  
   Le chemin avance a `speed`, les ticks de degats s'appliquent uniquement hors safe zone.

3. **Fin**  
   La scene emet `finished` puis se supprime.

## 4) Duree et scheduler des vagues

- Le projet utilise maintenant un scheduler de vagues sequentiel (plus de `time` dans les waves).
- Pour une vague `path_trial`, la duree active du pattern suit la duree de vague configuree (ex: `force_duration_sec`).
- La vague inclut le delai de start, donc runtime: `duree_totale_wave = duree_pattern + start_delay_sec`.

## 5) Geometrie / mouvement du path

- Le path est genere en runtime pour etre suffisamment long (`speed * duration` + marge) et eviter la disparition prematuree.
- Trajectoire random contrainte:
  - dans les 2/3 bas de l'ecran,
  - marge de 20 px,
  - virage borne a 90 degres max par segment,
  - steering naturel proche des bords pour revenir en zone jouable.
- Safe zone dynamique construite via `Geometry2D.offset_polyline()`.

## 6) Integration code

- `scenes/mechanics/PathTrial.tscn` + `PathTrial.gd`: logique complete (setup, visuels, collision, degats, cleanup).
- `scenes/WaveManager.gd`:
  - support `type: "path_trial"`,
  - injection de `start_delay_sec` et `duration`,
  - prewarm des assets hazard/path/hazard_start.
- `autoload/PowerManager.gd`:
  - support hazard boss `path_trial`.
- `scenes/Game.gd`:
  - spawn/track/cleanup des PathTrial de wave.

## 7) Necessite des 3 types d'assets (important)

Pour un rendu propre et lisible, PathTrial doit utiliser 3 assets visuels distincts:

1. **Hazard Start Asset** (`default_hazard_start_asset` / `hazard_start_asset_override`)  
   Affiche l'etat "alerte / preparation" pendant `start_delay_sec`.
   - Conception: plein ecran, lisible, signal clair de "prepare-to-move".
   - Format accepte: `Texture2D` ou `SpriteFrames`.

2. **Hazard Active Asset** (`default_hazard_asset` / `hazard_asset_override`)  
   Affiche l'etat de danger actif.
   - Conception: contraste suffisant avec le path pour que la zone sure reste evidente.
   - Format accepte: `Texture2D` ou `SpriteFrames`.

3. **Path Asset** (`default_path_asset` / `path_asset_override`)  
   Texture du chemin securise (Line2D en mode tile).
   - Conception recommandee: texture horizontale **seamless/repeatable** (bord gauche/droit raccord), alpha propre, style uniforme.
   - Pourquoi repeatable: le path est dessine par segments et tuilage (`LINE_TEXTURE_TILE`), une texture non seamless produit des ruptures visuelles.
   - Format accepte: `Texture2D` (recommande pour un rendu uniforme), ou `SpriteFrames` si animation voulue.