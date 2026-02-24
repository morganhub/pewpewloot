# Contexte et Objectif
Tu es un développeur expert sur Godot Engine spécialisé dans les interfaces utilisateur (UI) mobiles. Je souhaite refondre complètement les menus `WorldSelect` et `LevelSelect` de mon projet de Shoot'em up.
L'objectif est de créer un système de sélection en carrousel horizontal fluide, manipulable au doigt, qui sera utilisé de la même manière pour les mondes et les niveaux.

# 1. Modifications des données JSON
Le code que tu vas produire doit s'appuyer sur la logique de données suivante.

**Dans `data/game.json`** :
Dans la sous-array `"world_select"` (qui contient déjà `"background"`), nous ajoutons les assets globaux :
- Navigation : `"arrow_left"`, `"arrow_right"`
- Interface : `"details_panel_bg"` (fond du panneau de texte)
- Bouton : `"button_bg"`, `"button_font_size"`, `"button_font_color"`
- Verrouillage : `"locked_asset"` (chemin vers un png de cadenas), `"locked_opacity"` (valeur float pour assombrir le monde verrouillé).

**Dans les fichiers `data/worlds/world_x.json` (et équivalents pour les levels)** :
Chaque élément inclura ses données propres : nom, chemin de l'image (png ou .tres pour AnimatedSprite2D), et les détails/story du monde.

# 2. Structure Visuelle de l'UI
L'interface doit être architecturée ainsi (de haut en bas) :
1. **Titre** : Un Label en haut ("World Select" ou "Level Select"), localisé.
2. **Carrousel central** :
   - L'image du monde au centre.
   - De grosses flèches sur les côtés (centrées verticalement par rapport à l'image) pour changer d'élément. 
   - *Condition stricte :* Masquer la flèche gauche sur le premier élément, masquer la flèche droite sur le dernier élément.
3. **Panneau de détails** : 
   - Positionné en dessous de l'image et en **légère surimpression** (overlap) sur le bas de celle-ci.
   - Il affiche le nom du monde et quelques éléments caractéristiques ou de lore (tirés des json spécifiques).
4. **Bouton d'accès** : En dessous du panneau de détails, reprenant le style défini dans `game.json`, pour lancer le monde.

# 3. Mécanique de Slide Tactile (Contrôle critique)
Je ne veux pas d'un simple `ScrollContainer` au comportement par défaut. Je veux une mécanique de "Drag & Snap" très fluide.
- **Drag ("1:1 Tracking")** : L'utilisateur doit pouvoir maintenir son doigt appuyé et scroller horizontalement. Le mouvement des images doit suivre le doigt de manière exacte et instantanée.
- **Release & Snap** : Lorsque l'utilisateur lève le doigt, l'image ne doit pas s'arrêter entre deux positions. Le script doit calculer quel est l'élément le plus proche du centre de l'écran, et utiliser un `Tween` pour faire "glisser" (snap) l'UI jusqu'à centrer parfaitement ce monde/niveau.

# 4. Système de Verrouillage (Bloqué / Débloqué)
Il y a déjà un système logique en place pour savoir si un niveau/monde est bloqué. Tu dois implémenter son rendu visuel :
- Si bloqué, l'image centrale du monde prend l'opacité définie par `"locked_opacity"`.
- On superpose et centre l'image `"locked_asset"` (cadenas) par-dessus l'image du monde.
- Le bouton pour entrer dans le niveau est logiquement désactivé.

# 5. Initialisation (Auto-Focus sur la progression)
C'est un point crucial pour l'UX : au chargement de la scène (`_ready`), le script doit s'interfacer avec la sauvegarde/progression pour trouver le **dernier monde (ou dernier niveau) débloqué** par le joueur. 
- Le carrousel doit s'initialiser *directement* centré sur cet élément (sans animation de scroll depuis le début).
- Le panneau de détails, le bouton et l'état des flèches doivent refléter instantanément ce monde/niveau actif dès l'apparition de l'écran.

# Travail demandé
Rédige le code GDScript (et suggère l'arborescence des nœuds Control) pour cette scène générique. Implémente la logique de gestion des inputs (`InputEventScreenTouch`, `InputEventScreenDrag` dans `_gui_input` ou `_input`) pour assurer le mouvement fluide et le snapping du carrousel au doigt, ainsi que la fonction d'initialisation sur le dernier niveau débloqué.