# PewPewLoot - Product & Technical Status

Derniere mise a jour: 20 mars 2026  
Cible: Android (portrait), Godot 4.x, 60 FPS stables

## 1. Concept du jeu (version propre)
PewPewLoot est un shoot'em up vertical 2D solo avec une boucle ARPG/loot.

Le coeur du jeu:
- Action shmup lisible: vagues, patterns, positionnement, dodge.
- Progression metagame: profils, vaisseaux, inventaire, equipements, raretes.
- Rejouabilite: farm de niveaux/boss pour optimiser le build.

Structure cible par monde:
- 5 niveaux "normaux".
- 1 niveau boss.
- Deblocage progressif monde par monde.

## 2. Boucle de jeu actuelle
Loop principale actuelle:
1. ProfileSelect
2. HomeScreen
3. WorldSelect
4. LevelSelect
5. Game (waves + boss + loot de session)
6. LootResultScreen
7. Retour Home / restart / level select

Etat:
- Le gameplay de run est jouable de bout en bout.
- Les vagues sont data-driven.
- Le boss est integre avec barre de vie, phases et powers.
- Le recap de fin de run est actif.

## 3. Systeme de mouvement ennemi (refactor majeur termine)
Le systeme de deplacement ennemi a ete bascule vers Path2D/PathFollow2D.

Ce qui est en place:
- `Enemy.gd` cree/assure `Path2D` + `PathFollow2D`.
- Le mouvement est pilote par `path_follow.progress`.
- Les patterns viennent de `data/patterns/move_patterns.json`.
- Deux modes supportes:
- `resource`: charge un `.tres` Curve2D.
- `proc`: genere la courbe au spawn via code.
- Fallback de securite si pattern invalide.
- Option `fit_to_viewport` pour adapter la courbe au viewport.
- Gestion `loop`, `path_anchor`, `path_speed_scale`, `rotation_offset_deg`.

Important sur l'orientation actuelle:
- Les ennemis ne tournent plus avec la tangente du path.
- Orientation visuelle forcee "nez vers le bas" pour coherence tir visuel.
- Log debug de pattern actif present (`[EnemyMove] ...`) pour diagnostic.

## 4. Bibliotheque de patterns de mouvement
Etat actuel:
- 20 patterns declares dans `move_patterns.json`.
- 14 patterns bases sur ressources `.tres`.
- 6 patterns proceduraux runtime.

Patterns ressources:
- `linear_cross_fast`
- `u_turn_retreat`
- `staircase_descent`
- `loop_de_loop_center`
- `double_loop_horizontal`
- `tear_drop_attack`
- `boomerang_bottom`
- `screen_hugger_left`
- `cross_screen_dive`
- `stop_and_go_zigzag`
- `butterfly_wings`
- `square_patrol`
- `cobra_strike`
- `bouncing_dvd`

Patterns proceduraux:
- `sine_wave_vertical`
- `figure_eight_vertical`
- `impatient_circle`
- `heart_shape`
- `dna_helix`
- `spirograph_flower`

Generation des `.tres`:
- Outil `tools/PatternGenerator.gd` disponible.
- Bouton dev temporaire sur HomeScreen (`Generate Move Paths`, editor only).

## 5. Attribution des patterns aux waves (simplifiee)
Changement structurel applique:
- Les waves n'ont plus besoin de `pattern_id`, `origin_x`, `origin_y`.
- `WaveManager` choisit un pattern de deplacement aleatoire avant chaque wave.
- Le pattern choisi est applique a tous les spawns de la wave en cours.
- Position de spawn ennemie randomisee sur le haut de l'ecran.

## 6. HUD run: indicateur de vague + UI powers
Ajout recent:
- Indicateur sous la barre de shield en haut gauche.
- Format localise: `Vague X/Y` ou `Wave X/Y`.
- Le boss compte comme une vague supplementaire.

Implementation:
- `Game` calcule `Y = nb_waves + (boss ? 1 : 0)`.
- Update `X` via signal `wave_started`.
- Passage a `X=Y` au spawn du boss.

UI powers (data-driven):
- Boutons `power` et `unique power` (rayon identique configurable) + cercle de cooldown configurables via `data/game.json` (`gameplay.power_buttons`).
- Le cercle de cooldown peut etre place sur une couche au-dessus (visuel au-dessus mais interaction preservee).

Popup protocoles (mobile):
- `LevelSelect`: la selection par tap ne doit pas interrompre le scroll (tap/drag distingues au niveau de la scene, coordonnees globales).

## 7. Robustesse fin de run (bug double popup corrige + invincibilite/overlays)
Bug corrige:
- Cas ou le joueur meurt puis un tir tardif tue le boss.
- Avant: double flux defaite/victoire possible.

Correctifs en place:
- Le boss actif est reference dans `Game`.
- A la mort du joueur, boss force invincible.
- Verrou de fin de session pour eviter tout double declenchement.
- Si boss meurt apres mort joueur, la victoire est ignoree.

Invincibilite pendant powers:
- `PowerManager.execute_power()` active l'invincibilite via `Player.set_invincible()` si `invincibility` est true dans `data/missiles/super_powers.json` et `data/missiles/unique_powers.json`.

Z-index/overlays UI:
- `PauseMenu` et `LootResultScreen` sont des `CanvasLayer` (layer `20`) pour eviter les soucis de rendu au-dessus du HUD.

LootResultScreen UI (post-run):
- Taille des apercus loot (boss + session) ajustee a la hausse, et section XP simplifiee (suppression de la ligne de pourcentage + reduction des separations).

## 8. Background/parallaxe (evolution recente)
Systeme de layers de fond:
- `far_layer`, `mid_layer`, `near_layer` via JSON niveau.
- Scroll infini vertical maintenu.

Ajouts recents:
- Support des backgrounds `.png/.jpg` et `.tres` animes.
- `ScrollingLayer` accepte `Texture2D` et `SpriteFrames`.
- `mid_layer` et `near_layer` utilisent un blend mode Add.

Resultat:
- Possibilite de composer des overlays lumineux sans masquer le fond.

## 9. Projectiles (assets animes + trajectoires + pooling)
Corrections recentes:
- Support explicite des `.tres` `SpriteFrames` dans `Projectile.gd`.
- Fonctionne via `asset_anim` et aussi via `asset` quand c'est un `.tres`.
- Evite les erreurs de type `get_size()` sur ressource non texture.

Trajectoires: fire_cone par distance:
- Le pattern `fire_cone` bifurque en direction UP apres une distance parcourue (pas uniquement en temps).
- Parametres pilotés dans `data/skills.json` pour l'id `fire_cone`: `params.cone_bend_start_distance_px`.
- Fallback dans `Projectile.gd` si le parametre n'est pas present.

Pooling projectiles:
- `ProjectileManager` lit `data/game.json.projectile_pools` (pool sizes joueur/ennemis + step d'expansion ennemis).

## 10. Etat metagame (inventaire/progression/economie)
Ce qui est operationnel:
- Profils persistants (`SaveManager`, `ProfileManager`).
- Inventaire, equipement par vaisseau, pouvoirs uniques selectionnables.
- Raretes/affixes/uniques, upgrade et recycle.
- Crystal economy + shop.
- Options globales (audio, langue, screenshake).
- `StoryOverlay` (bulles de dialogue): `bubble_font_size` pilote par `data/story.json` (`global_settings`).

## 11. Architecture data-driven (resume)
Le runtime lit principalement depuis JSON:
- mondes/niveaux: `data/worlds/*.json`
- ennemis: `data/enemies.json`
- boss: `data/bosses.json`
- patterns move: `data/patterns/move_patterns.json`
- missiles/patterns missiles: `data/missiles/*.json` et `data/patterns/missile_patterns_*.json`
- override protocols: `data/override_protocols.json`
- loot: `data/loot/*.json`
- config UI/gameplay: `data/game.json`
- localisation et textes: `data/locales/*.json`
- narration: `data/story.json` (+ `data/locales/story_*.json`)

