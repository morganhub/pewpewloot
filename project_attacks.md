# Bilan Attaques / Missiles / Projectiles / Powers / Skills

Date d'analyse: 2026-02-18
Périmètre: `data/*.json`, `data/missiles/*.json`, `data/patterns/*.json`, `autoload/*.gd`, `scenes/*.gd` liés au combat.

## 1. Pipeline global (comment les attaques sont construites)

1. Les JSON sont chargés par `autoload/DataManager.gd`.
2. Les entités (`Player`, `Enemy`, `Boss`) récupèrent patterns + missiles via `DataManager`.
3. Le spawn réel passe par `autoload/ProjectileManager.gd` (pooling player/enemy).
4. Le comportement projectile est exécuté dans `scenes/Projectile.gd` (trajectoire, collision, on-hit skills).
5. Les pouvoirs passent par `autoload/PowerManager.gd` (mouvement cinématique + vagues de projectiles).

Exemple:
- `ship_car` (`data/ships/ships.json`) -> `missile_pattern_id = single_straight` + `missile_id = missile_car`.
- `Player._fire()` injecte le visuel/accélération du missile, puis `ProjectileManager.spawn_player_projectile(...)`.

## 2. Bloc JSON: missiles (`data/missiles/missiles.json`)

Mécanique:
- Définit l'identité visuelle, type, acceleration, son, explosion.
- Les stats de trajectoire viennent surtout des missile patterns, mais `missile.speed` peut override la vitesse dans `Player` et `Enemy`.

Etat:
- Implémenté côté runtime (visuel, acceleration, explosion, son).

Exemple:
- `missile_poison`: visuel animé `missile_poison.tres`, explosion verte, utilisé via `missile_id` puis injecté dans `pattern_data["visual_data"]`.

## 3. Bloc JSON: patterns missiles player (`data/patterns/missile_patterns_player.json`)

Mécanique:
- Définit cadence/structure du tir joueur: `projectile_count`, `spread_angle`, `spawn_width`, `burst_count`, `cooldown`, `trajectory`.
- Gère des stratégies de spawn (`shooter`, `screen_bottom`, `screen_top`).

Etat:
- Implémenté dans `Player._fire()`, `_execute_burst_sequence()`, `_spawn_salvo()`.

Exemple:
- `burst_5`: 5 salves séquentielles (`burst_count=5`, `burst_interval=0.15`) puis reload via `cooldown`.

## 4. Bloc JSON: patterns missiles enemy (`data/patterns/missile_patterns_enemy.json`)

Mécanique:
- Définit les patterns ennemis/boss: radial, aimed, spiral, homing, waves, spawn edge/corners/flanking.

Etat:
- Implémenté dans `Enemy._fire_single_wave()` et `Boss._fire()`.

Exemple:
- `encircle_attack`: spawn en cercle autour du joueur (`spawn_strategy=target_circle`) puis convergence (`aim_target=true`).

## 5. Bloc JSON: ennemis (`data/enemies.json`)

Mécanique:
- Chaque ennemi configure HP, pattern de mouvement, pattern missile, missile visuel, cadence.
- Supporte modifier élite injecté à la vague (`enemy_modifier_id` via `WaveManager`).

Etat:
- Tir: implémenté.
- Mouvement: partiellement implémenté (écarts IDs, voir section bilan).

Exemple:
- `interceptor_diagonal`: pattern missile `homing_barrage` + `missile_homing`.

## 6. Bloc JSON: boss (`data/bosses.json` + `data/missiles/boss_powers.json`)

Mécanique:
- Boss par phases: seuil HP, pattern tir, fire_rate, power spécial périodique.
- Power spécial exécuté via `PowerManager.execute_power(...)`.

Etat:
- Phases + tirs: implémentés.
- Plusieurs incohérences de données/runtime (voir bilan).

Exemple:
- `power_boss_storm`: 3 vagues radiales, 30 projectiles, safe zones.

## 7. Bloc JSON: powers player (super + unique)

Fichiers:
- `data/missiles/super_powers.json`
- `data/missiles/unique_powers.json`

Mécanique:
- Un power combine `duration`, `invincibility`, `ship_movement`, `projectile`.
- Le runtime lit les powers via `DataManager.get_power()` et exécute dans `PowerManager`.

Etat:
- Super powers: majoritairement implémentés.
- Unique powers: partiellement implémentés (un cas beam non géré).

Exemples:
- `power_witch_circle`: déplacement `spin_center` + projectiles `spiral`.
- `unique_meteor_storm`: trajectoire `rain_down` (implémentée).
- `unique_laser_beam`: trajectoire `beam` (non implémentée explicitement, fallback burst).

## 8. Bloc JSON: skills (`data/skills.json`)

Mécanique:
- `magic`: modifie projectile joueur + effets au hit (chill, poison, void pull, singularity, etc.).
- `utility`: bonus loot/powerups/réflexion/choc d'urgence.
- `pew_pew`: bonus stats par rang (Paragon).

Etat:
- Implémentation riche et active dans `SkillManager`, `Projectile`, `IceAura`, `ToxicPool`, `Singularity`, `Player`.

Exemple:
- `frozen_4`: sur cible gelée, shatter -> spawn de shards radiaux via `ProjectileManager.spawn_player_projectile(...)`.

## 9. Bloc JSON: modificateurs d'ennemis (attaques spéciales élites)

Fichier:
- `data/enemy_modifiers.json`

Mécanique:
- Enrichit ennemi avec stats/visuels + capacités: `mine_spawner`, `arcane_spawner`, `gravity_spawner`, `wall_spawner`, `suppressor_shield`.
- Régulation globale via `EnemyAbilityManager` (cooldown partagé, max écran, spacing).

Etat:
- Implémenté.

Exemples:
- `minefreak`: pose des mines descendantes avec collision player/projectile.
- `arcane_enchanted`: spawn orb + laser rotatif avec tick de dégâts.
- `graviton`: puit qui attire le joueur dans un rayon.
- `suppressor`: bouclier absorbant les projectiles player jusqu'à rupture.

## 10. Systèmes de gestion (runtime)

### `ProjectileManager`
- Pool fixe (`player=100`, `enemy=200`), activation deferred en frame physique, recyclage propre.

Exemple:
- Lors d'un tir boss radial, chaque projectile ennemi vient du pool enemy, puis est rendu au pool via signal `projectile_deactivated`.

### `Projectile`
- Gère trajectoires (`straight`, `sine_wave`, `spiral`, `homing`), acceleration, collision, explosion, effets skills on-hit.

Exemple:
- Projectile joueur critique -> dégâts x2 + effets skills (poison/chill/void) sur `Enemy.apply_status_effect()`.

### `PowerManager`
- Exécute invincibilité, tween de mouvement, vagues de projectiles spéciaux.

Exemple:
- `dash_forward` (boss/player): tween Y avant/arrière + salves pendant la durée du power.

### `EnemyAbilityManager`
- Anti-spam d'objets d'attaque élite avec cooldown + limites par groupe.

Exemple:
- Deux élites `minefreak` ne peuvent pas saturer instantanément l'écran au-delà du `max_per_screen`.

## 11. Bilan actuel (points clés)

### Fonctionnel
- Pooling projectiles solide.
- Tir joueur + tir ennemi + tir boss opérationnels.
- Skills magic (frozen/poison/void) réellement connectés au combat.
- Capacités élites (mine/arcane/gravity/suppressor/wall) effectivement spawnées.
- Powers boss/player déclenchés et visibles.

### Partiel / incohérent
1. `DataManager` fusionne patterns player puis enemy dans un seul dictionnaire: 6 IDs du player sont écrasés par la version enemy (`single_straight`, `triple_spread`, `burst_5`, `rapid_burst`, `screen_bottom_wave`, `rain_top`).
2. `Boss._apply_phase()` ne charge pas `_move_pattern_data` après changement de phase.
3. IDs de mouvement boss invalides dans JSON (`circle_clockwise`, `bounce_horizontal`) absents de `move_patterns.json`.
4. `missile_id` boss invalide: `missile_boss_heavy` absent de `data/missiles/missiles.json`.
5. `PowerManager` ignore les valeurs `damage/speed` des JSON power (hardcodé 50/20 et speed 400).
6. `unique_laser_beam` (`trajectory=beam`) n'a pas de branche dédiée dans `PowerManager`.
7. `Player.use_unique()` force `unique_meteor_storm` (placeholder), donc ne respecte pas toujours le unique équipé/actif.
8. `data/enemies/enemies.json` est un dataset legacy non consommé (le runtime lit `data/enemies.json`).
9. Tous les `move_pattern_id` de `data/enemies.json` sont absents de `move_patterns.json`; le système retombe sur un fallback de trajectoire.

### Impact gameplay actuel
- Les tirs/projections et effets de statut fonctionnent globalement.
- La variabilité de déplacement ennemi/boss ne reflète pas les intentions JSON actuelles.
- Les powers spéciaux existent mais une partie des paramètres data-driven est neutralisée par du hardcode runtime.

## 12. Résumé rapide

Le socle technique est bon (pooling, collisions, effets, pouvoirs, élites), mais la couche "data-driven" est partiellement cassée par des divergences d'IDs JSON et quelques hardcodes runtime. Les mécaniques d'attaque sont présentes, mais pas toujours exécutées comme décrites dans les `.json`.
