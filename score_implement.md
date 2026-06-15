# Cahier des Charges : Systeme de Score Local et Evaluation par Etoiles

## 1. Vue d'ensemble et Objectifs
Ce document definit les specifications pour l'integration d'un systeme de scoring local avec evaluation par etoiles (1 a 3 etoiles) pour chaque niveau des differents mondes du jeu. Le systeme doit prendre en compte la gestion multi-profils existante, inclure des interfaces de selection de niveaux et de resultats (LootResultScreen) mises a jour, et etre entierement parametrable via les fichiers de donnees JSON. Le systeme doit egalement respecter le systeme de localisation actuel du projet.

---

## 2. Modification des Structures de Donnees (Fichiers JSON)

### 2.1. Seuils de score dans les mondes (data/worlds/world_x.json)
Pour permettre l'obtention d'etoiles, chaque niveau de chaque monde doit inclure des paliers de score.
Action IA : Ajouter les cles suivantes pour chaque niveau dans tous les fichiers world_x.json (avec des valeurs placeholders) :

{
  "id": "level_1",
  "name": "Niveau 1",
  "score_1star": 3000,
  "score_2stars": 6500,
  "score_3stars": 12000
}
Tu évalueras les placeholders en fonction des niveaux / waves / nombre d'ennemis

### 2.2. Configuration visuelle globale (data/game.json)
Creation d'un objet score_parameters pour centraliser la configuration de l'UI liee aux scores et aux etoiles, rendant le systeme facilement modifiable sans toucher au code.
Action IA : Ajouter dans game.json :

"score_parameters": {
  "font_color_normal": "#FFFFFF",
  "font_color_record": "#FFD700",
  "font_size_score": 24,
  "star_empty_asset": "res://assets/ui/stars/star_empty.png",
  "star_filled_asset": "res://assets/ui/stars/star_filled.tres", 
  "star_size": {"x": 64, "y": 64}
}

(Note : star_filled_asset peut pointer vers une texture statique ou une ressource animee .tres SpriteFrames/Texture).

---

## 3. Gestion des Sauvegardes et Profils (SaveManager.gd / ProfileManager.gd)

Le systeme doit enregistrer les scores de maniere persistante pour chaque profil.

### 3.1. Structure de sauvegarde du profil
Le dictionnaire de sauvegarde d'un profil doit integrer une nouvelle section level_scores :

"level_scores": {
  "world_1": {
    "level_1": {"best_score": 3200, "stars": 2},
    "level_2": {"best_score": 0, "stars": 0}
  }
}

### 3.2. Fonctions requises dans le Backend
L'IA devra implementer ou mettre a jour les methodes suivantes (probablement dans DataManager.gd ou ProfileManager.gd) :
* save_level_score(world_id, level_id, score) : Met a jour le score du profil actif si le nouveau score est strictement superieur au best_score actuel. Calcule et sauvegarde egalement le nombre d'etoiles debloquees.
* get_level_best_score(world_id, level_id) : Retourne le meilleur score du profil actif.
* get_global_best_score(world_id, level_id) : Parcourt TOUS les profils locaux enregistres et retourne le score le plus eleve absolu ainsi que le nom du profil detenteur.
* get_profile_count() : Retourne le nombre total de profils crees.

---

## 4. Interface Utilisateur (UI)

### 4.1. Ecran de Selection des Niveaux (LevelSelect.tscn / WorldSelect.tscn)
Lorsqu'un monde est selectionne, la liste des niveaux (6 au total) affiche la description du monde et les informations de score.

Regles d'affichage par niveau :
1. Score du joueur actif : Afficher "Meilleur Score : [Score]" sous la description du niveau.
2. Affichage Etoiles : Afficher visuellement les 3 etoiles (pleines/vides) correspondant au record du joueur actif.
3. Comparaison multi-profils (Logique conditionnelle) :
    * Condition A : S'il n'y a QU'UN SEUL profil enregistre dans le jeu -> Ne rien afficher de plus.
    * Condition B : S'il y a PLUSIEURS profils -> 
        * Si le joueur actif a le record global : Afficher une mention du type "[Couronne] Vous detenez le record absolu !"
        * Si un autre profil a le record : Afficher "Record absolu : [Score] par [Nom_Profil]".

### 4.2. Ecran de Resultat (LootResultScreen.tscn / .gd)
Cet ecran de fin de niveau doit etre mis a jour pour integrer la presentation du score :
1. Calcul du Score Total : Recuperer le score de la partie qui vient de s'achever.
2. Animation des Etoiles : Instancier 3 noeuds (ex: TextureRect ou AnimatedSprite2D). Par defaut, charger star_empty_asset. Selon le score final compare aux seuils (score_1star, etc.), remplacer par star_filled_asset (avec un leger delai/animation si possible). La taille doit utiliser score_parameters.star_size.
3. Indication "Nouveau Record" :
    * Comparer le score actuel avec l'ancien best_score du joueur.
    * Si superieur, afficher une mention "NOUVEAU RECORD !" en utilisant la couleur font_color_record de game.json. Sinon, utiliser font_color_normal.

---

## 5. Localisation (Systeme de Traduction)

Le projet dispose deja d'un systeme de locales (en.json, fr.json). L'IA devra rajouter les cles de traduction suivantes :

Fichier fr.json (Exemples) :
{
  "SCORE_BEST_PERSONAL": "Meilleur Score : {score}",
  "SCORE_GLOBAL_RECORD_HOLDER": "Record absolu : {score} par {profile_name}",
  "SCORE_GLOBAL_RECORD_YOURS": "[Couronne] Vous detenez le record absolu !",
  "SCORE_NEW_RECORD_ALERT": "NOUVEAU RECORD !",
  "SCORE_TOTAL": "Score Total : {score}"
}

Fichier en.json (Exemples) :
{
  "SCORE_BEST_PERSONAL": "Best Score: {score}",
  "SCORE_GLOBAL_RECORD_HOLDER": "Global Record: {score} by {profile_name}",
  "SCORE_GLOBAL_RECORD_YOURS": "[Crown] You hold the global record!",
  "SCORE_NEW_RECORD_ALERT": "NEW RECORD!",
  "SCORE_TOTAL": "Total Score: {score}"
}

(L'IA devra utiliser le LocaleManager.gd ou la fonction tr() pour formater ces chaines).

---

## 6. Etapes d'Implementation Recommandees pour l'IA

1. Etape 1 : Fichiers JSON
    * Mettre a jour game.json avec la section score_parameters.
    * Creer un script Python/GDScript rapide ou modifier manuellement les world_X.json pour ajouter score_1star, score_2stars, score_3stars sur tous les niveaux existants.
2. Etape 2 : Core Backend
    * Modifier le gestionnaire de profil/sauvegarde pour supporter la lecture/ecriture de level_scores.
    * Creer les methodes de recherche du "Best Global Score" parmi tous les profils.
3. Etape 3 : Scene de Fin de Niveau (LootResultScreen)
    * Ajouter les conteneurs UI (ex: HBoxContainer) pour les etoiles et les TextLabels pour le score.
    * Scripter l'application dynamique des assets (star_empty_asset / star_filled_asset) selon les donnees du world_x.json.
4. Etape 4 : Scene de Selection (LevelSelect)
    * Integrer les TextLabels localises.
    * Scripter la logique conditionnelle verifiant le nombre de profils et l'appartenance du record.
5. Etape 5 : Polissage
    * Appliquer les couleurs/polices depuis score_parameters.
    * S'assurer que toutes les nouvelles chaines utilisent le systeme de localisation.