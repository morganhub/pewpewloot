# Plan: Intégration des Ennemis Élites (Style Diablo)

Ce plan détaille l'intégration d'un système d'ennemis "Élites" reposant sur des **Affixes**. L'objectif est de transformer des ennemis existants via des modificateurs de stats, de visuels et de compétences, pilotés par les données des mondes (`world_x.json`).

## 1. Architecture des Données

### A. Définition des Modificateurs (`data/enemy_modifiers.json`)
Ce fichier centralise tous les types de bonus possibles.
*   **Structure JSON** :
    *   `id`: Identifiant unique (ex: "elite_fire").
    *   **Stats** : Multiplicateurs (`hp_mult`, `damage_mult`, `speed_mult`, `scale`).
    *   **Visuels** :
        *   `health_bar_frame`: Chemin vers l'asset graphique entourant la barre de vie.
        *   `background_effect`: Chemin vers un PNG ou `.tres` (animé) à afficher derrière l'ennemi (aura).
    *   **Abilities** : Liste de compétences spéciales (ex: "mortar_shot").

### B. Configuration des Vagues (`data/worlds/world_x.json`)
C'est ici que l'on décide quand les élites apparaissent.
*   **Propriété** : `enemy_modifier_id` (string ou liste).
*   **Fonctionnement** : Dans une définition de `wave`, on peut spécifier cet ID pour appliquer un template d'élite à tous les ennemis ou à un chef de file spécifique.

## 2. Nouveau Gestionnaire : `EnemyModifiers.gd`
Pour éviter de surcharger `Enemy.gd`, ce script servira de "Factory" et de gestionnaire de logique pour les modificateurs.

*   **Rôle** :
    *   Charger et parser `enemy_modifiers.json`.
    *   Fournir une fonction `apply_modifier(enemy: Enemy, modifier_id: String)`.
    *   Instancier les effets visuels (Background, Barre de vie) et les ajouter à l'ennemi.
    *   Calculer les stats finales (Base Stats * Modifiers) et les renvoyer à l'ennemi.

## 3. Système de Compétences (Abilities)
Gestion des comportements additionnels (Logique).

*   **Dossier** : `scenes/abilities/`
*   **Classe** : `EnemyAbility.gd` (Node2D).
    *   Exemples : Tirs additionnels, Auras, Murs.
    *   Ces compétences sont instanciées par `EnemyModifiers.gd` et ajoutées comme enfants de l'Enemy.

## 4. Modification du Noyau (`Enemy.gd`)
L'ennemi devient un réceptacle passif qui se laisse configurer.

*   **Setup (`setup(data, wave_config)`)** :
    1.  Lit `wave_config` pour voir s'il y a un `enemy_modifier_id`.
    2.  Si oui, appelle `EnemyModifiers.apply_modifier(self, modifier_id)`.
*   **Visuels** :
    *   La barre de vie par défaut est modifiée pour inclure le cadre "Elite" chargé par le modifier (asset graphique).
    *   Le sprite de l'ennemi est inchangé, mais un nœud `Sprite2D` ou `AnimatedSprite2D` est ajouté en arrière-plan (Z-Index -1) pour l'effet "Aura".

## 5. Gestionnaire de Vagues (`WaveManager.gd`)
Il fait le pont entre le JSON du monde et l'ennemi.

*   Lors de la lecture d'une vague dans `world_x.json`, il extrait la propriété `enemy_modifier_id`.
*   Il passe cette propriété lors de l'appel à `spawn_enemy()`.

## 6. Récompenses (Loot)
Connecter la difficulté accrue à de meilleures récompenses.

*   **LootGenerator.gd** :
    *   Ajout d'un paramètre `quality_multiplier` à la fonction principale `generate_loot()`.
    *   Modification de `_roll_rarity` pour prendre en compte ce boost (augmente les chances de Rare/Légendaire).
*   **LootDrop.gd** : Transmettre l'information de l'ennemi (si Élite + ses modificateurs) au moment du drop.
*   **Mise à jour** : Les ennemis ayant un modificateur actif transmettent un bonus de `quality_multiplier` au `LootGenerator`.

---

## Étapes de Développement

1.  **Données** :
    *   Créer `data/enemy_modifiers.json` avec des champs pour les assets visuels (barre, fond).
    *   Ajouter une entrée test "elite_berserker" (Vitesse++, Dégâts++, Aura rouge).
2.  **Manager** :
    *   Créer le script `autoload/EnemyModifiers.gd`.
    *   Lui faire charger le JSON au démarrage.
3.  **Intégration Graphique** :
    *   Dessiner ou récupérer un asset "Cadre Elite" pour la barre de vie.
    *   Dessiner ou récupérer un asset "Aura" (cercle magique) pour le fond.
4.  **Liaison Ennemi** :
    *   Connecter `Enemy.gd` à `EnemyModifiers.gd`.
    *   Tester l'application visuelle (Aura + Cadre).
5.  **Configuration Monde** :
    *   Modifier un `world_1.json` pour ajouter `enemy_modifier_id` sur une vague. (si enemy_modifier_id est absent, il n'y a juste pas de modifier)