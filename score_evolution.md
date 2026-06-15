# Cahier des charges — Système de Killstreak / Score Multiplier / Cristaux bonus
## Projet: PewPewLoot (Godot 4.x, Android portrait)

Dernière révision: 2026-03-20

---

## 1. Objectif produit

Ajouter un **système de killstreak** inspiré de Diablo III et de Diablo IV Saison 12, adapté à un **shoot'em up vertical**.

Le système doit:
- valoriser les éliminations en chaîne,
- augmenter temporairement le score via un multiplicateur,
- fournir des retours visuels lisibles et satisfaisants,
- rester simple à paramétrer via `data/game.json`,
- s'intégrer proprement à l'architecture data-driven existante,
- introduire des **cristaux bonus** lâchés aléatoirement par les ennemis tués.

Le système n'a **pas** pour objectif de remplacer le scoring existant, mais de **l'enrichir**.

---

## 2. Références de design à retenir

### 2.1 Inspiration Diablo III
Référence de design retenue:
- logique de **streak / massacre**,
- récompense déclenchée par des éliminations enchaînées dans une fenêtre courte,
- sensation de montée en puissance,
- retour de fin de streak.

### 2.2 Inspiration Diablo IV Saison 12
Références retenues:
- une **popup HUD** qui commence dès la streak,
- une **barre de temps** visible qui diminue,
- la streak est maintenue si le joueur continue à tuer,
- un **gain calculé sur la totalité de la streak**,
- mise en avant explicite des paliers / multiplicateurs dans l'UI.

### 2.3 Adaptation shoot'em up
Dans PewPewLoot, le système ne donnera **pas** d'XP ni de réputation saisonnière comme Diablo IV.
À la place, il donnera:
- un **multiplicateur de score temporaire**,
- un **bonus de fin de streak** optionnel,
- des **retours visuels**,
- une opportunité de **drop de cristaux bonus** sur les ennemis tués.

---

## 3. Résultat fonctionnel attendu

Quand le joueur tue des ennemis rapidement:
1. une **killstreak** démarre,
2. un **compteur de kills** s'incrémente,
3. une **barre de timer** apparaît et se vide progressivement,
4. chaque nouveau kill réinitialise ou recharge le timer,
5. la streak monte de palier et augmente le **multiplicateur de score**,
6. si le timer tombe à 0, la streak se termine,
7. un feedback de fin de streak s'affiche,
8. le scoring redevient normal (`x1.0`),
9. certains ennemis tués peuvent faire tomber un **cristal bonus**.

---

## 4. Règles métier — Killstreak

### 4.1 Définition
Une killstreak est une séquence de kills consécutifs réalisée avant expiration d'un timer.

### 4.2 Début de streak
La streak commence:
- au **premier ennemi tué** alors qu'aucune streak n'est active.

### 4.3 Maintien de streak
La streak continue si:
- un nouvel ennemi est tué avant la fin du timer.

### 4.4 Fin de streak
La streak se termine si:
- le timer atteint 0,
- le joueur meurt,
- la run se termine,
- le niveau se termine,
- la partie est quittée ou rechargée,
- un écran bloquant de fin de session s'ouvre.

### 4.5 Pause
En pause de jeu:
- le timer visuel est figé,
- le timer logique est figé,
- aucun tick de décroissance ne doit continuer.

### 4.6 Boss
Par défaut:
- les kills du boss **comptent comme 1 kill** s'il meurt pendant une streak,
- mais le boss **n'accorde pas automatiquement un multiplicateur spécial**.

Option configurable:
- `boss_kill_count_value`
- `boss_kill_bonus_score_flat`
- `boss_can_drop_bonus_crystal`

---

## 5. Scoring attendu

### 5.1 Base
Le jeu possède déjà un système de score. Ce système reste la base.

Formule cible:
```text
score_gagné = score_base_ennemi × multiplicateur_killstreak
```

### 5.2 Multiplicateur
Le multiplicateur démarre à:
```text
x1.0
```

Il augmente par paliers configurables, avec affichage en décimales.
Exemples de multiplicateurs possibles:
- x1.1
- x1.2
- x1.3
- x1.5
- x2.0
- x2.5
- x3.0

### 5.3 Plafond
Le multiplicateur maximum doit être configurable.
Valeur cible souhaitée:
```text
x3.0 max
```

### 5.4 Arrondi
Le score final ajouté doit être:
- soit arrondi à l'entier le plus proche,
- soit floor,
- comportement paramétrable.

Clé recommandée:
- `rounding_mode = "round"` ou `"floor"`

### 5.5 Bonus de fin de streak
Optionnellement, quand une streak se termine, le jeu peut attribuer:
- un **bonus de score flat**,
- ou un **bonus calculé sur le nombre total de kills de la streak**.

Formule recommandée:
```text
bonus_fin_streak = total_kills_streak × streak_end_bonus_per_kill
```

Ou:
```text
bonus_fin_streak = palier_atteint × streak_end_bonus_by_tier
```

Ce bonus doit être activable/désactivable dans `game.json`.

---

## 6. Paliers recommandés

Le système doit être entièrement data-driven.
Structure recommandée:
- chaque palier définit un **minimum de kills requis**
- et le **multiplicateur actif**

### 6.1 Table par défaut proposée
```text
0 kill   -> x1.0
3 kills  -> x1.1
6 kills  -> x1.2
10 kills -> x1.3
15 kills -> x1.5
22 kills -> x1.7
30 kills -> x2.0
40 kills -> x2.3
55 kills -> x2.6
75 kills -> x3.0
```

### 6.2 Règle d'évaluation
À chaque kill:
- recalculer le palier courant,
- si le palier change, jouer un feedback spécifique.

### 6.3 Noms de paliers
Optionnel mais conseillé:
- `streak`
- `carnage`
- `devastation`
- `bloodbath`
- `massacre`

Dans ton jeu, tu peux utiliser des labels plus arcade:
- `Combo`
- `Fury`
- `Rampage`
- `Overdrive`
- `Massacre`

Les noms doivent être localisables.

---

## 7. Timer de streak

### 7.1 Principe
Le timer représente le délai restant avant la rupture de streak.

### 7.2 Comportement
Au premier kill:
- la jauge apparaît à 100%.

À chaque kill supplémentaire:
- le timer revient à sa valeur max,
- ou remonte partiellement selon le mode choisi.

### 7.3 Modes supportés
#### Mode A — reset complet
Chaque kill remet le timer à la durée max.

#### Mode B — refill partiel
Chaque kill ajoute une quantité de temps sans dépasser le max.

Le système doit supporter les deux modes.
Clé:
- `refresh_mode = "full_reset"` ou `"partial_refill"`

### 7.4 Valeurs recommandées
Durée de base conseillée:
```text
2.0 à 3.0 secondes
```

Pour un shmup mobile lisible, recommandation initiale:
```text
2.4 secondes
```

### 7.5 Affichage
La barre doit:
- être toujours visible pendant une streak,
- se vider de manière fluide,
- clignoter ou changer d'état visuel sous un seuil critique,
- disparaître après la fin de streak avec un court fade-out.

---

## 8. HUD / retours visuels

## 8.1 Bloc HUD killstreak
Créer un widget HUD dédié.

Contenu minimum:
- label du palier / nom de streak,
- compteur de kills,
- multiplicateur courant,
- barre de temps restante.

Exemple d'affichage:
```text
MASSACRE
24 KILLS
x1.7
[██████░░░░]
```

### 8.2 Placement
Placement recommandé:
- haut gauche sous le shield, ou
- haut centre si meilleure lisibilité.

Le placement doit être configurable.

### 8.3 États visuels
#### État normal
- barre stable
- texte lisible
- multiplicateur affiché

#### Passage de palier
- pulse / scale punch
- flash léger
- particules ou sprite d'accent optionnel
- son optionnel

#### État critique
Quand le timer descend sous un seuil:
- barre clignotante,
- vignette légère,
- shake UI léger optionnel,
- couleur ou animation d'urgence.

#### Fin de streak
Afficher brièvement:
- `STREAK OVER`
- `+ bonus score`
- `Best streak: XX` optionnel

### 8.4 Assets
Le système doit supporter:
- PNG statiques,
- `.tres` de type `SpriteFrames`,
- petits overlays animés pour:
  - montée de palier,
  - critique timer,
  - fin de streak,
  - pickup de cristal bonus.

---

## 9. Cristaux bonus

### 9.1 Objectif
Ajouter une récompense secondaire qui tombe parfois sur les ennemis vaincus.

### 9.2 Règle de drop
À la mort d'un ennemi:
- un test RNG détermine si un cristal bonus tombe.

### 9.3 Paramétrage
Le pourcentage de drop doit être dans `game.json`.

Exemples:
- ennemi normal: 12%
- ennemi élite: 25%
- boss: 100% ou table spécifique

### 9.4 Types de cristaux
Le système doit supporter au minimum:
- `score_crystal`
- `streak_time_crystal`
- `score_multiplier_crystal` (optionnel futur)

Pour le premier lot de dev, minimum requis:
- `score_crystal`

### 9.5 Effet minimal requis
#### score_crystal
Donne un bonus de score flat à la collecte.

Formule:
```text
score_bonus = crystal_score_value
```

### 9.6 Effets optionnels futurs
#### streak_time_crystal
Ajoute du temps à la jauge de streak active.

#### combo_safe_crystal
Empêche la rupture de streak une seule fois.

#### magnet_crystal
Attire temporairement les drops.

### 9.7 Collecte
Le cristal:
- spawn à la mort de l'ennemi,
- descend légèrement ou flotte,
- peut être attiré vers le joueur si système d'aimantation déjà existant ou futur,
- disparaît au bout d'une durée paramétrable si non ramassé.

### 9.8 Assets
Le cristal doit supporter:
- PNG
- ou `.tres` animés
- avec VFX de spawn et pickup optionnels.

---

## 10. Intégration gameplay détaillée

### 10.1 Sur kill ennemi
Quand un ennemi meurt:
1. récupérer son `base_score`,
2. notifier le système de killstreak,
3. recalculer le multiplicateur,
4. attribuer le score total,
5. mettre à jour le HUD,
6. lancer éventuellement le drop de cristal.

### 10.2 Ordre recommandé
Ordre recommandé:
1. enemy death resolved
2. killstreak updated
3. multiplier computed
4. score awarded
5. crystal roll executed
6. feedback displayed

### 10.3 Cas des multi-kills simultanés
Si plusieurs ennemis meurent sur la même frame:
- traiter chaque kill individuellement,
- mais éviter les spam visuels excessifs,
- agréger certains feedbacks si nécessaire.

### 10.4 Cas projectile retardé
Si un projectile tue un ennemi après la mort du joueur:
- **ne pas continuer la streak**,
- **ne pas attribuer de bonus de streak**,
- **ne pas dropper de cristal**, sauf règle contraire explicite.

Cette règle doit être cohérente avec la robustesse déjà en place côté fin de run.

---

## 11. Architecture technique proposée (Godot 4)

### 11.1 Nouveaux composants recommandés
#### `KillstreakManager.gd`
Responsabilités:
- état de streak,
- timer logique,
- calcul du palier,
- calcul du multiplicateur,
- émission des signaux,
- clôture de streak.

#### `KillstreakHUD.gd`
Responsabilités:
- affichage widget,
- barre de timer,
- texte kills/palier/multiplicateur,
- animations UI.

#### `BonusCrystal.gd`
Responsabilités:
- représentation pickup,
- mouvement,
- durée de vie,
- collecte joueur,
- application d'effet.

#### `BonusCrystalManager.gd` (optionnel)
Responsabilités:
- spawn mutualisé,
- pooling,
- lecture config,
- factorisation des drops.

### 11.2 Signaux recommandés
#### `KillstreakManager`
- `streak_started(initial_kill_count)`
- `streak_updated(kill_count, multiplier, time_left, time_ratio, tier_id, tier_label)`
- `streak_tier_changed(old_tier_id, new_tier_id, multiplier)`
- `streak_warning(time_left, time_ratio)`
- `streak_ended(final_kill_count, highest_multiplier, end_bonus_score)`
- `multiplier_changed(multiplier)`

#### `BonusCrystal`
- `collected(crystal_type, value)`
- `expired()`

### 11.3 Point d'intégration
Le système doit être branché sur l'événement de mort ennemi déjà existant.
Exemple conceptuel:
- `Enemy` ou `Game` notifie `KillstreakManager.on_enemy_killed(enemy_data)`

---

## 12. Data model recommandé dans `data/game.json`

```json
{
  "scoring": {
    "killstreak_system": {
      "enabled": true,
      "base_timer_sec": 2.4,
      "refresh_mode": "full_reset",
      "partial_refill_sec": 0.75,
      "critical_threshold_ratio": 0.25,
      "max_multiplier": 3.0,
      "rounding_mode": "round",
      "lose_streak_on_player_death": true,
      "lose_streak_on_level_end": true,
      "show_end_popup": true,
      "show_tier_name": true,
      "show_multiplier": true,
      "show_kill_count": true,
      "show_timer_bar": true,
      "enable_end_streak_bonus": true,
      "streak_end_bonus_per_kill": 5,
      "boss_kill_count_value": 1,
      "boss_kill_bonus_score_flat": 0,
      "boss_can_drop_bonus_crystal": true,
      "tiers": [
        { "id": "base", "min_kills": 0,  "label_key": "killstreak_tier_base",       "multiplier": 1.0 },
        { "id": "combo_1", "min_kills": 3,  "label_key": "killstreak_tier_combo",      "multiplier": 1.1 },
        { "id": "combo_2", "min_kills": 6,  "label_key": "killstreak_tier_fury",       "multiplier": 1.2 },
        { "id": "combo_3", "min_kills": 10, "label_key": "killstreak_tier_rampage",    "multiplier": 1.3 },
        { "id": "combo_4", "min_kills": 15, "label_key": "killstreak_tier_overdrive",  "multiplier": 1.5 },
        { "id": "combo_5", "min_kills": 22, "label_key": "killstreak_tier_slaughter",  "multiplier": 1.7 },
        { "id": "combo_6", "min_kills": 30, "label_key": "killstreak_tier_carnage",    "multiplier": 2.0 },
        { "id": "combo_7", "min_kills": 40, "label_key": "killstreak_tier_devastation","multiplier": 2.3 },
        { "id": "combo_8", "min_kills": 55, "label_key": "killstreak_tier_bloodbath",  "multiplier": 2.6 },
        { "id": "combo_9", "min_kills": 75, "label_key": "killstreak_tier_massacre",   "multiplier": 3.0 }
      ],
      "hud": {
        "anchor": "top_left",
        "offset_x": 24,
        "offset_y": 84,
        "bar_width": 220,
        "bar_height": 14,
        "use_animated_assets": true,
        "tier_up_fx_asset": "res://assets/ui/killstreak/tier_up.tres",
        "warning_fx_asset": "res://assets/ui/killstreak/warning.png",
        "end_fx_asset": "res://assets/ui/killstreak/end_popup.tres"
      }
    },
    "bonus_crystals": {
      "enabled": true,
      "despawn_time_sec": 8.0,
      "pickup_radius": 28.0,
      "magnet_speed": 420.0,
      "spawn_offset_y": 10.0,
      "use_pooling": true,
      "default_asset": "res://assets/pickups/bonus_crystal.tres",
      "drop_table": {
        "normal_enemy_drop_chance": 0.12,
        "elite_enemy_drop_chance": 0.25,
        "boss_drop_chance": 1.0
      },
      "types": [
        {
          "id": "score_crystal_small",
          "type": "score_crystal",
          "weight": 70,
          "score_value": 100,
          "asset": "res://assets/pickups/crystal_small.png"
        },
        {
          "id": "score_crystal_big",
          "type": "score_crystal",
          "weight": 25,
          "score_value": 300,
          "asset": "res://assets/pickups/crystal_big.tres"
        },
        {
          "id": "streak_time_crystal",
          "type": "streak_time_crystal",
          "weight": 5,
          "time_bonus_sec": 0.5,
          "asset": "res://assets/pickups/crystal_time.tres"
        }
      ]
    }
  }
}
```

---

## 13. Localisation

Ajouter des clés dans les fichiers de locale.

Exemples:
```json
{
  "killstreak_tier_base": "Streak",
  "killstreak_tier_combo": "Combo",
  "killstreak_tier_fury": "Fury",
  "killstreak_tier_rampage": "Rampage",
  "killstreak_tier_overdrive": "Overdrive",
  "killstreak_tier_slaughter": "Slaughter",
  "killstreak_tier_carnage": "Carnage",
  "killstreak_tier_devastation": "Devastation",
  "killstreak_tier_bloodbath": "Bloodbath",
  "killstreak_tier_massacre": "Massacre",
  "killstreak_over": "Streak Over",
  "killstreak_bonus_score": "Bonus Score",
  "bonus_crystal_pickup": "Crystal Bonus"
}
```

---

## 14. Règles UX / lisibilité mobile

Le système doit rester lisible sur écran portrait Android.

Contraintes:
- ne pas masquer la zone de jeu centrale,
- éviter un widget trop haut,
- limiter les animations agressives,
- conserver une lecture instantanée du multiplicateur.

Règles:
- taille de police lisible sans surcharge,
- un seul point focal principal: le multiplicateur,
- la barre de timer doit être compréhensible en moins d'une seconde,
- les VFX doivent être brefs.

---

## 15. Performance / robustesse

### 15.1 Performance
Le système doit être compatible 60 FPS stables.
Éviter:
- instanciation excessive de nodes UI,
- spam de tweens non recyclés,
- trop d'AnimatedSprite2D simultanés.

Recommandations:
- pooling pour cristaux,
- pooling ou mutualisation des VFX de tier up,
- une seule source de vérité pour le timer.

### 15.2 Robustesse
Cas à couvrir:
- kill simultané de plusieurs ennemis,
- fin de niveau pendant streak,
- mort joueur pendant streak,
- boss tué après mort joueur,
- pause/reprise,
- restart run,
- changement d'écran,
- streak active alors que HUD est masqué,
- cristal encore vivant alors que la run se termine.

---

## 16. Critères d'acceptation

Le système sera considéré comme validé si:

1. tuer un ennemi démarre une streak et affiche le HUD;
2. tuer un autre ennemi avant expiration recharge le timer;
3. le multiplicateur change correctement selon les paliers JSON;
4. le score attribué utilise bien le multiplicateur actif;
5. le timer se vide correctement et termine la streak à 0;
6. la streak s'interrompt à la mort du joueur;
7. la popup de fin de streak apparaît sans doublon;
8. les cristaux tombent selon le taux configuré;
9. les cristaux sont collectables et appliquent leur effet;
10. aucun double comptage n'apparaît sur morts tardives après game over;
11. le système reste stable à forte densité d'ennemis;
12. la totalité du paramétrage principal est modifiable via `data/game.json`.

---

## 17. Plan de livraison recommandé

### Phase 1 — noyau logique
- `KillstreakManager`
- timer
- tiers
- multiplicateur
- score branché

### Phase 2 — HUD
- widget
- barre
- labels
- warning
- fin de streak

### Phase 3 — cristaux bonus
- drop RNG
- pickup
- score crystal
- pooling

### Phase 4 — polish
- VFX
- assets `.png` / `.tres`
- sons
- localisation
- équilibrage

---

## 18. Consignes à destination de l'IA de développement

L'IA doit respecter les règles suivantes:
- ne pas hardcoder les paliers;
- lire les paramètres depuis `data/game.json`;
- séparer logique, HUD et pickups;
- privilégier des scripts courts et testables;
- utiliser des signaux plutôt que des couplages forts;
- être compatible Godot 4.x;
- ne pas casser le scoring actuel;
- conserver un comportement déterministe et robuste;
- prévoir des fallbacks si asset ou clé JSON manquant;
- journaliser proprement en debug si config invalide.

---

## 19. Décision design recommandée

Version recommandée pour V1:
- streak basée uniquement sur les kills,
- timer de 2.4 s,
- reset complet à chaque kill,
- multiplicateur de x1.0 à x3.0,
- bonus de fin de streak activé,
- cristaux score + petits cristaux temps,
- HUD compact haut gauche.

C'est la version la plus lisible, la plus simple à équilibrer, et la plus cohérente avec ton shmup mobile.

---

## 20. Notes d'implémentation finales

Ce système doit produire trois sensations:
1. **pression**: ne pas casser la streak,
2. **montée en puissance**: voir le multiplicateur progresser,
3. **récompense**: score gonflé + cristaux bonus + feedback clair.

Le système doit favoriser:
- l'agressivité,
- le déplacement intelligent,
- la prise de risque contrôlée,
- la satisfaction immédiate à l'écran.
