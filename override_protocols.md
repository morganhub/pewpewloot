# GDD & Technical Plan : Override Protocols (Mutateurs) & Achievements

## 1. Concept Global et Intégration UX
**Nom du système :** Override Protocols (Protocoles de Surcharge).
**Principe :** Une fois qu'un monde est terminé (boss final vaincu), le joueur débloque la capacité d'activer des malus (les protocoles) pour ce monde. Chaque protocole activé augmente le multiplicateur de "Bravoure" (ou "Data Cores"), ressource servant à débloquer des cosmétiques, des upgrades ultimes ou des achievements.

**UX dans LevelSelect :**
* **Bouton d'accès :** Situé juste au-dessus du bouton "PLAY" ou "ENTER" du niveau.
* **État Bloqué :** Tant que le monde n'est pas "Cleared", le bouton affiche "OVERRIDE PENDING..." (grisé, icône de cadenas). Si le joueur clique, un petit tooltip indique : "Complétez ce monde pour débloquer les Protocoles de Surcharge."
* **État Débloqué :** Le bouton devient lumineux/rouge ("OVERRIDE PROTOCOLS"). Cliquer dessus ouvre le **Popup Override**.

## 2. Structure des Données (JSON)

Toutes les configurations visuelles et data du système seront centralisées dans un nouveau fichier : `data/override_protocols.json`.

```json
{
  "ui_settings": {
    "popup_bg": "res://assets/ui/override_popup_bg.png",
    "button_active_bg": "res://assets/ui/btn_override_active.png",
    "button_inactive_bg": "res://assets/ui/btn_override_inactive.png",
    "header_font_size": 32,
    "header_text_color": "#ff3333",
    "item_title_size": 20,
    "item_title_color": "#ffffff",
    "item_desc_size": 16,
    "item_desc_color": "#cccccc",
    "checkbox_checked": "res://assets/ui/checkbox_on.png",
    "checkbox_unchecked": "res://assets/ui/checkbox_off.png"
  },
  "protocols": [
    // Liste détaillée dans la section 3
  ]
}
```

## 3. Design des 10 Override Protocols

Voici les 10 modificateurs conçus pour impacter différemment le core loop (mouvement, tir, survie). Ils sont à intégrer dans le tableau "protocols" du JSON ci-dessus.

1. **System Corruption (La Corruption) :**
   * *Description :* Des fuites de données corrompues apparaissent sur le terrain.
   * *Effet technique :* Fait spawner aléatoirement des flaques toxiques dans l'arène. Ces flaques infligent des dégâts sur la durée (ticks) si le joueur les survole.
2. **Overclocked Thrusters (Propulseurs Surchargés) :**
   * *Description :* Les moteurs ennemis tournent à plein régime.
   * *Effet technique :* Multiplicateur de vitesse de déplacement des ennemis de base : +40%.
3. **Hyper-Ballistics (Hyper-Balistique) :**
   * *Description :* Les projectiles ennemis brisent le mur du son.
   * *Effet technique :* Vitesse de tous les projectiles ennemis augmentée de 50%.
4. **Ablative Armor (Blindage Ablatif) :**
   * *Description :* Les ennemis sont lourdement blindés.
   * *Effet technique :* Points de vie (HP) max de tous les ennemis et boss augmentés de 30%.
5. **Critical Malfunction (Avarie Critique) :**
   * *Description :* Les systèmes de survie de votre vaisseau sont HS.
   * *Effet technique :* Le joueur commence avec **1 seul HP** (mode "One-Hit KO"). Tension maximale.
6. **Nanite Suppression (Suppression de Nanites) :**
   * *Description :* Les réparations d'urgence sont désactivées.
   * *Effet technique :* Le taux de drop (Drop Rate) des objets de soin/réparation tombe à 0%. Les compétences de soin sont réduites de 50%.
7. **Volatile Reactors (Réacteurs Volatils) :**
   * *Description :* La destruction d'un ennemi provoque une instabilité.
   * *Effet technique :* À leur mort, 30% des ennemis explosent (petite zone d'effet AoE ou relâchent 3 projectiles en arc).
8. **Elite Vanguard (Avant-garde d'Élite) :**
   * *Description :* Les escadrons d'élite sont déployés en masse.
   * *Effet technique :* Le taux de remplacement d'un ennemi normal par un ennemi Élite est multiplié par 3.
9. **EMP Interference (Interférence IEM) :**
   * *Description :* Les capteurs longue portée sont brouillés.
   * *Effet technique :* Applique un shader de vignettage ou un brouillard qui réduit le champ de vision du joueur (bords de l'écran assombris), rendant l'anticipation des tirs plus difficile.
10. **Boss Overdrive (Surcharge du Boss) :**
    * *Description :* Les protocoles de sécurité des boss sont désactivés.
    * *Effet technique :* Le Boss enchaîne ses patterns d'attaque avec 0 seconde de temps mort (cooldown = 0) entre chaque phase.

## 4. Système d'Achievements Interne (Store-Ready)

Ce système comportera plusieurs paliers de progression, assurant un engagement à long terme.

**A. Structure et Progression des Succès (data/achievements.json) :**
L'arborescence des succès sera divisée en catégories allant du mode normal jusqu'à la complétion absolue du meta-game (soit plusieurs dizaines de paliers).

1. **Niveau 1 : Les Fondations (Sans Override)**
   * `ach_world_1_clear` : Terminer le Monde 1.
   * `ach_world_2_clear` : Terminer le Monde 2... etc.
2. **Niveau 2 : L'Initiation aux Protocoles (Par niveau)**
   * `ach_level_override_1` : Terminer 1 niveau avec 1 Protocole actif.
   * `ach_level_override_2` : Terminer 1 niveau avec 2 Protocoles actifs... jusqu'à 10.
3. **Niveau 3 : La Maîtrise Régionale (Par monde entier)**
   * `ach_world_override_1` : Terminer un monde entier avec au moins 1 Protocole actif.
   * `ach_world_override_2` : Terminer un monde entier avec au moins 2 Protocoles actifs... jusqu'à 10.
4. **Niveau 4 : L'Absolu (Le Graal)**
   * `ach_omni_override_10` : Terminer TOUS les mondes du jeu avec les 10 Protocoles actifs.

*Exemple de structure JSON :*
```json
{
  "ach_world_1_clear": {
    "title_fr": "Premier Pas",
    "desc_fr": "Terminez le monde 1.",
    "condition_type": "world_cleared",
    "target_value": "world_1",
    "store_id_android": "CgkIxxxxxx",
    "store_id_ios": "grp.ach_01"
  },
  "ach_world_override_10": {
    "title_fr": "Hacker Divin",
    "desc_fr": "Terminez un monde entier avec 10 Override Protocols actifs.",
    "condition_type": "world_cleared_with_protocols",
    "target_value": 10
  }
}
```

**B. Intégration UI : Menu des Succès (HomeScreen)**
* **Bouton d'accès :** Sur la scène `HomeScreen.tscn` (page d'accueil), un petit bouton dédié aux succès (icône de coupe ou médaille) sera ajouté dans le premier espace disponible, **juste au-dessus du bouton principal "Jouer"** qui indiquera le total d'override réussi avec un icone override a droite des cristaux et niveau en cours.
* **Page Liste :** En cliquant dessus, une nouvelle scène/overlay s'ouvre, listant tous les succès débloqués et grisant ceux qui sont encore verrouillés. On prend le modèle de skillsMenu en terme de présentation (backbutton, background et bouton personnalisables, fond dédié...).)

**C. Implémentation via l'Autoload DataManager / SaveManager :**
1. **Dictionnaire local :** Maintenir un dictionnaire des achievements débloqués dans la sauvegarde du joueur.
2. **Écouteur d'événements (Event Bus) :** À la fin d'un niveau, le jeu émet un signal `level_completed` contenant l'ID du monde, du niveau et le nombre de protocoles actifs.
3. **Vérification :** Un script `AchievementManager.gd` (Autoload) écoute ce signal. Si les conditions d'un succès non débloqué sont remplies :
   * Il affiche une notification en jeu (UI locale).
   * Il marque l'achievement comme "fait" dans la sauvegarde.
   * *Future proofing :* Il appelle une fonction vide `_sync_to_stores()` qui contiendra plus tard le code de l'API Google/Apple pour débloquer le succès sur le compte en ligne du joueur.