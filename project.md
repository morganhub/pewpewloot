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
   - high power (base 80 damage), mid special attack cooldown (20s), low missile speed (40% max speed), mid crit chance (7%), low dodge chance (2%)
   - spécial: paint attack      
2) **Plane**  
   - mid power (base 50 damage), low special attack cooldown (10s), high missile speed (100% max speed), low crit chance (10%), high dodge chance (10%)
   - spécial: extreme looping (autocontrol full screen damage) 
3) **Witch**  
   - mid power (base 50 damage), high special attack cooldown (30s), mid missile speed (80% max speed), high crit chance (10%), mid dodge chance (5%)
   - spécial: front cone burst full screen
4) **Supercar**  
   - low power (base 20 damage), low special attack cooldown (10s), very high missile speed (150% max speed), high crit chance (10%), low dodge chance (2%)
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

### 5.2 Raretés (6)
- **Common** (fr : commun)
- **Uncommon** (fr : peu commun)
- **Rare** (fr : rare)
- **Epic** (fr : épique)
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

### 6.1 Écrans existants (implémentés)
- **SceneSwitcher**: root navigation + fade
- **ProfileSelect**: créer/supprimer/sélectionner + sauvegarde
- **HomeScreen**: hub principal (jouer, vaisseaux, options, profils)
- **ShipMenu**: équipement, inventaire, upgrade, recycle, choix pouvoirs
- **WorldSelect**: mondes débloqués uniquement
- **LevelSelect**: niveaux débloqués uniquement
- **Game**: gameplay réel (waves, boss, loot/session recap)
- **PauseMenu**, **LootResultScreen**, **OptionsMenu**, **ShopMenu**, **LoadingScreen**
- **GamePlaceholder**: legacy pour simulation de déverrouillage

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
- Écrans: `ProfileSelect`, `HomeScreen`, `ShipMenu`, `WorldSelect`, `LevelSelect`, `Game`, etc.

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

## 9) État actuel du projet (implémentation réelle)
✅ Gameplay jouable sur `Game.tscn`:
- Spawn joueur, waves data-driven (`WaveManager`), boss, HUD, pause, game over, recap de session
- Projectiles poolés (`ProjectileManager`: 100 joueur / 200 ennemi)
- Patterns missiles/mouvements variés + trajectoires (`straight`, `sine`, `spiral`, `homing`, radial, spawn bords/coins/cercle)
✅ Combat enrichi:
- Stats finales calculées via `StatsCalculator` (vaisseau + équipements)
- Crit, esquive, dégâts de contact, super pouvoir, pouvoir unique
- Power-ups en run: **shield** (absorption énergie) + **rapid fire**
- Ennemis élites avec modificateurs (`EnemyModifiers`) et abilités (ex: `wall_spawner`)
- Boss multi-phases avec pouvoirs spéciaux (`PowerManager`)
✅ Boucle méta ARPG active:
- Profils persistants (inventaire, loadouts par ship, progression, cristaux, settings)
- `ShipMenu` complet: equip/unequip, filtres slot/rareté, pagination, multi-recycle, upgrade d’item, sélection de pouvoir unique
- `LootResultScreen` en fin de run, notifications de loot en combat, popup détail item
- Économie cristaux + `ShopMenu` (simulation d’achat)
✅ UX:
- Navigation moderne `ProfileSelect -> HomeScreen -> World/Level -> Game`
- Options langue/audio, loading screen dédiée au chargement de la scène de jeu

---

## 10) Mécaniques qui ont évolué depuis le concept initial
1) **Loadout/Inventaire**: n’est plus “à venir”, il est déjà au cœur du jeu via `ShipMenu`.
2) **Raretés**: passage de 5 à **6** raretés avec ajout de **Epic**.
3) **Vaisseaux**: le roster conceptuel a évolué (5 entrées dans `data/ships/ships.json`, déblocage par cristaux).
4) **Pouvoirs actifs**: super pouvoirs + pouvoirs uniques exécutés en runtime (mouvement cinématique, salves spéciales).
5) **Bouclier & boosts en run**: système de shield énergétique et boost cadence via pickups.
6) **Système élite**: modificateurs statistiques/visuels + compétences d’ennemis (obstacles muraux).
7) **Loot loop**: loot procédural + upgrade/recycle/équipement directement depuis les écrans de session et de ship.
8) **Architecture data-driven**: patterns, missiles, pouvoirs, niveaux et loot majoritairement pilotés par JSON.

---

## 11) Écarts/points à aligner (audit technique)
1) **Progression post-mission**: la progression monde/niveau est correctement codée dans `ProfileManager`, mais l’appel est encore branché surtout dans `GamePlaceholder`; la victoire dans `Game.gd` doit persister le `complete_level`/`unlock_next_world_if_needed`.
2) **Contenu mondes 2–5**: les JSON existent, mais le runtime actuel est surtout aligné sur le schéma de `world_1` (waves avec `time`, `interval`, `pattern_id`, etc.). Plusieurs entrées monde 2–5 utilisent un format `delay` non consommé par `WaveManager`.
3) **Boss/loot ciblé**: le concept vise un farm de boss avec uniques signature; l’implémentation actuelle génère surtout un item de récompense générique en fin de run et le TODO unique boss reste à finaliser.
4) **Données ships par défaut**: clé `default_unlocked` côté JSON vs attente `default_unlocked_ships` côté `DataManager` à harmoniser.

---

## 12) Conventions & bonnes pratiques (projet)
- Scripts attachés **au root** des scènes (sauf exceptions).
- Éviter les `get_parent().get_parent()`; préférer `get_tree().current_scene` (SceneSwitcher).
- Pour les chemins nodes:
  - soit `Copy Node Path` et `$...`
  - soit `Unique Name` et `%...` (quand stable)
- GDScript 4:
  - pas d’opérateur `? :` (utiliser `a if cond else b`)
  - attention aux retours `Variant` (JSON, metadata) → typer `Variant` explicitement si warnings stricts.

---

## 13) Roadmap révisée (priorisée)
1) Persister la progression directement depuis `Game.gd` (victoire/défaite, unlock niveau/monde).  
2) Normaliser le schéma des mondes 2–5 pour `WaveManager` et compléter les données ennemis/boss associées.  
3) Finaliser le loot boss ciblé (tables dédiées + uniques signature réellement dropables).  
4) Équilibrer économie cristaux / coûts d’upgrade / taux de loot par rareté.  
5) Pass perf mobile: caps FX, stress test patterns denses, profiling device mid-range.  
6) QA gameplay + export Android (AAB/APK) + préparation store.
