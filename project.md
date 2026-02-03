# PewPewLoot — Game Design & Technical Specification (Android / Godot)

> **Genre**: Vertical Shoot’em Up (2D) + progression & loot **Diablo-like**  
> **Plateforme cible**: **Android** (solo uniquement)  
> **Moteur**: **Godot 4.x** (UI + gameplay 2D natif)  
> **Priorité absolue**: **performance stable (60 FPS) + zéro freeze** même avec missiles/explosions

---

## 1) Vision produit

### 1.1 Pitch
**PewPewLoot** est un shoot’em up vertical 2D solo où le joueur traverse des **mondes indépendants**, chacun composé de **5 niveaux + 1 boss final**. Le cœur du plaisir vient d’un mashup entre :
- l’**action shmup** (patterns, positionnement, salves, esquive),
- et une boucle **ARPG** (loot, rareté, affixes, builds, “farm” de boss, optimisation d’équipement).

Le joueur choisit un **vaisseau** (châssis) avec une identité forte (arme spéciale, passif, type de missiles), puis optimise ses performances via **8 emplacements d’équipement** et une progression de raretés allant de **Commun** à **Unique**.

### 1.2 Piliers (design)
1) **Fluidité**: pas de spikes, pas de micro-saccades (pooling, caps FX, collisions optimisées).
2) **Lisibilité**: bullets lisibles, hitboxes cohérentes, FX spectaculaires mais contrôlés.
3) **Builds**: choix de vaisseau + équipements = style de jeu distinct.
4) **Farm ciblé**: les boss finaux ont des loots signature (Uniques dédiés) → on refait pour “le bon roll”.
5) **Progression claire**: Monde 1 / Niveau 1 au départ, déverrouillage progressif.

---

## 2) Structure du jeu

### 2.1 Système de mondes & niveaux
- **N mondes** (cible initiale: 5).
- Chaque monde contient:
  - **Niveaux 1–5** (progression, mécaniques introduites)
  - **Niveau 6** = **Boss** (multi-phases, farmable)
- Les mondes sont **indépendants** et rejouables.
- Le joueur peut rejouer un niveau ou un boss déjà terminé pour loot.

### 2.2 Déverrouillage (progression initiale)
- Au départ: **Monde 1 débloqué**, et dans ce monde **Niveau 1 débloqué**.
- Terminer un niveau:
  - Débloque le **niveau suivant** dans le même monde.
- Terminer le boss (niveau 6):
  - Débloque le **monde suivant** (Monde 2), avec Niveau 1 débloqué.

---

## 3) Gameplay shmup (macro & micro)

### 3.1 Défilement & perception de mouvement
- Décor en scrolling vertical (parallax optionnel).
- Le joueur reste majoritairement dans le bas de l’écran.
- Les ennemis apparaissent principalement par le haut, mais peuvent entrer par les côtés.

### 3.2 Boucle de niveau (exemple)
- Briefing (court) → vague 1 → vague 2 (latérale) → élite → mini-event (laser / minefield) → vague 3 → fin.
- Durée cible: 2–5 minutes par niveau.
- Le boss: 1–3 minutes selon phases.

### 3.3 Lisibilité & telegraphing
- Les attaques dangereuses doivent être **annoncées** (délai minimal, trajectoire lisible).
- Les projectiles doivent être classés par famille (vitesse / couleur / dégâts).
- Les FX ne doivent pas masquer les bullets.

---

## 4) véhicule/vaisseaux (classes) & capacités

### 4.1 Concept
Chaque vaisseau = une **classe**:
- stats de base (power, special attack cooldown reduction, missile speed, critical chance, dodge chance)
- arme principale (pattern)
- missiles (type)
- attaque spéciale (cooldown)
- passif (“trait”)

### 4.2 Exemples d’archétypes initiaux
1) **Car**  
   - high power, mid special attack cooldown, low missile speed, mid crit chance (7%), low dodge chance (2%)
   - spécial: paint attack      
2) **Plane**  
   - mid power, low special attack cooldown, high missile speed, low crit chance (10%), high dodge chance (10%)
   - spécial: extreme looping (autocontrol full screen damage) 
3) **Witch**  
   - mid power, high special attack cooldown, mid missile speed, high crit chance (10%), mid dodge chance (5%)
   - spécial: front cone burst full screen
4) **Supercar**  
   - low power, low special attack cooldown, very high missile speed, high crit chance (10%), low dodge chance (2%)
   - spécial: homing multi missiles (high damage)

---

## 5) Système d’équipement (ARPG / Diablo-like)

### 5.1 Emplacements (8 slots)
1) **reactor** (énergie / regen / CDR)
2) **engine** (vitesse / dash / maniabilité)
3) **armor** (PV / réduction dégâts)
4) **shield** (bouclier / regen / résistances)
5) **primary** (modifie tirs principaux)
6) **missiles** (type missiles, lock, salves)
7) **targeting** (crit, marque, on-hit)
8) **utility** (drone, aimant loot, contre-mesures)

### 5.2 Raretés (5)
- **Common** (fr : commun)
- **Uncommon** (fr : peu commun)
- **Rare** (fr : rare)
- **Legendary** (fr : légendaire)
- **Unique** (fr : unique). Les uniques donnent une abilité spéciale.

### 5.3 Affixes (exemples)
- Global: +Damage, +FireRate, +Crit, +CritDmg, +CDR, +Luck
- Slot: Engine → +Speed, dash trails; Missiles → homing/chain/split; Utility → drone, magnet loot…

### 5.4 Boss farming & loot ciblé
- Chaque boss de monde a:
  - 2–4 **Uniques signature**
  - pool de légendaires et rares
- Les boss dropent aussi des matériaux de monde (craft/upgrade).
- Farm = refaire boss jusqu’au loot désiré.

### 5.5 Inventaire & loadout
- Chaque profil conserve:
  - inventaire d’items
  - loadout par vaisseau (slot → item_id)
  - progression monde/niveau

---

## 6) UI/UX (phase 1 à 3)

### 6.1 Écrans existants (ossature)
- **SceneSwitcher**: root navigation + fade
- **MainMenu**
- **ProfileSelect**: créer/supprimer/sélectionner + sauvegarde
- **WorldSelect**: mondes débloqués uniquement
- **LevelSelect**: niveaux débloqués uniquement
- **GamePlaceholder**: simulation de fin de niveau (déverrouillage)

### 6.2 Principes UI
- Responsive portrait (Android).
- Layout via Containers (VBox/HBox/Margin/Center).
- Thème global (Theme) appliqué au projet.
- Interactions claires, boutons suffisamment grands (mobile).

### 6.3 Profils joueurs
- Plusieurs profils: nom + portrait (placeholder actuellement).
- Chaque profil a sa progression + inventaire + vaisseaux.

---

## 7) Architecture technique (Godot) & performance

### 7.1 Scènes / navigation (actuel)
- **Main Scene**: `SceneSwitcher.tscn`
- `SceneSwitcher.gd`:
  - instancie l’écran courant dans `ScreenRoot`
  - gère fade via `Fade` (ColorRect)
- Écrans: `MainMenu`, `ProfileSelect`, `WorldSelect`, `LevelSelect`, `Loadout` (à venir), etc.

### 7.2 Autoloads (singletons)
- `SaveManager`:
  - JSON save/load dans `user://pewpewloot_save.json`
- `ProfileManager`:
  - CRUD profils
  - progression (unlock niveaux/mondes)
- `App`:
  - données mock (world definitions)
  - meta “session” (selected_world_id, selected_level_index)

### 7.3 Performance — exigences
- Interdiction d’instancier/détruire des entités “volumineuses” en gameplay:
  - projectiles, FX, pickups, texte flottant
- **Object Pooling** obligatoire
- Collisions:
  - layers/masks stricts
  - hitboxes simples
  - caps sur projectiles
- FX:
  - spritesheets prioritaires
  - limiter overdraw / alpha massive
  - cap FX simultanés
- Profilage sur device midrange.

---

## 8) Assets & pipeline (prototype)

### 8.1 Packs recommandés (prototype)
Objectif: prototypage rapide, cohérence visuelle “space shooter”.
- **Kenney** (Space Shooter Redux, Extension, UI Sci-Fi, Sci-Fi Sounds)
- **OpenGameArt / itch.io**: lasers, explosions, UI packs, portraits sci-fi

> Toujours vérifier la licence (CC0 / CC-BY etc.) avant intégration.

### 8.2 Explosions 2D (création)
Pipeline conseillé:
- **Aseprite** (ou LibreSprite) → animation frame-by-frame
- Export **spritesheet PNG**
- Import Godot via **AnimatedSprite2D / SpriteFrames**
Règles:
- 8–16 frames petites explosions, 16–32 boss
- version “lite” fallback perf.

---

## 9) État actuel du projet (implémenté)
✅ Projet Godot créé, résolution réglée  
✅ Thème UI global (base)  
✅ Autoloads: SaveManager, ProfileManager, App  
✅ Navigation SceneSwitcher + fade  
✅ MainMenu → ProfileSelect → WorldSelect → LevelSelect → GamePlaceholder  
✅ Progression:
- Monde 1 / Niveau 1 initial
- Unlock niveau suivant au “complete”
- Unlock monde suivant au boss
✅ LevelSelect liste générée (6 niveaux) + lock/unlock  
✅ Validation via “simulateur” (GamePlaceholder)

---

## 10) Prochaine grande brique: Loadout + Inventaire + Équipement
- Introduire écran **Loadout** entre LevelSelect et lancement mission
- Définir vaisseaux jouables et 8 slots
- Inventaire minimal + equip/unequip
- Sauvegarde par profil

---

## 11) Conventions & bonnes pratiques (projet)
- Scripts attachés **au root** des scènes (sauf exceptions).
- Éviter les `get_parent().get_parent()`; préférer `get_tree().current_scene` (SceneSwitcher).
- Pour les chemins nodes:
  - soit `Copy Node Path` et `$...`
  - soit `Unique Name` et `%...` (quand stable)
- GDScript 4:
  - pas d’opérateur `? :` (utiliser `a if cond else b`)
  - attention aux retours `Variant` (JSON, metadata) → typer `Variant` explicitement si warnings stricts.

---

## 12) Roadmap (haute)
1) UI progression (fait)  
2) Loadout + inventory (next)  
3) Prototypage gameplay vertical slice (player + 1 enemy + pooling projectiles)  
4) Loot drop réel (boss) + affixes + raretés  
5) Monde 1 complet (5 niveaux + boss)  
6) Optimisation & polish (FX, audio, feedback, perf)  
7) Export Android AAB + test devices + store prep
