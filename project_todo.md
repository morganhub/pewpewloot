# PewPewLoot — Project TODO (Major Steps & Milestones)

Ce document liste les **prochaines étapes majeures** à partir de l’état actuel du projet (UI/progression validées), avec un focus **Android perf + Godot workflow**.

---

## 0) Baseline (déjà en place)
- SceneSwitcher (navigation + fade) comme Main Scene
- Autoloads: SaveManager (JSON), ProfileManager (profiles + progress), App (world defs + session meta)
- UI: MainMenu, ProfileSelect, WorldSelect, LevelSelect, GamePlaceholder
- Progression: monde 1 / niveau 1 initial, unlock niveaux + mondes par completion

---

## 1) Milestone A — Loadout (sélection vaisseau + slots) ✅ COMPLÉTÉ
### A1 — Données vaisseaux (mock puis data-driven)
- [x] Définir une liste `SHIPS` (dans App ou fichier data)
- [x] Définir les 8 slots

### A2 — Étendre la structure du profil (migration + nouveaux profils)
- [x] Ajouter au profil: ships_unlocked, active_ship_id, inventory, loadouts
- [x] Ajouter une **migration** dans `ProfileManager.load_from_disk()`

### A3 — UI Loadout (devenu ShipMenu)
- [x] Écran ShipMenu placé dans le flux (via HomeScreen)
- [x] UI: ShipOption, SlotsGrid, InventoryList (Grid), Equip/Unequip (Popup)
- [x] Navigation: HomeScreen -> ShipMenu

### A4 — Logique ShipMenu
- [x] Charger profil actif
- [x] Sélection vaisseau
- [x] Equip/Unequip avec persistence
- [ ] Launch: (intégré via HomeScreen -> Play)

### A5 — Démo loot rapide (sans gameplay)
- [x] Ajouter bouton debug “Générer item”
- [x] Crée un item aléatoire et l’ajoute à inventory

---

## 2) Milestone B — Data model loot (rarity/affixes) 🔄 PARTIEL
### B1 — Définir format item
- [x] item: id, slot, rarity, name, stats (dict)
- [ ] standardiser les clés stats (damage, firerate, crit, speed…)

### B2 — Tables d’affixes par slot
- [x] Définir pour chaque slot une table (JSON)
- [x] Générateur d’item (basic implémenté pour debug)

### B3 — Uniques
- [ ] Définir 2–4 uniques par boss (monde)

---

## 3) Milestone C — Vertical slice gameplay (proto perf) 🚀 PROCHAIN
### C1 — Player controller
- Déplacement tactile (drag) ou virtual joystick (choisir UX)
- Tir automatique (cadence)
- Stats réelles issues du Loadout (vitesse, PV)

### C2 — Projectiles (pooling obligatoire)
- ProjectileManager (pools player/enemy)
- Patterns simples

### C3 — Enemy basics
- 2–3 ennemis types
- Spawner simple

### C4 — FX & explosions (pool)
- Explosions spritesheet

### C5 — Perf tests
- Stress test 800 projectiles

---

## 4) Milestone D — Intégration loop “loot réel”
### D1 — Fin de mission → loot screen
- Résumé mission
- Loot list + “salvage” rapide

### D2 — Boss farming
- Accès direct boss

---

## 5) Milestone E — Monde 1 complet (content)
- Niveau 1–5 (vagues + événements)
- Boss (multi-phases)

---

## Next immediate actions (ordre conseillé)
1) [x] Créer `ShipMenu.tscn` (UI) + `ShipMenu.gd`
2) [x] Ajouter migration profil
3) [x] Ajouter bouton debug “générer item”
4) **Créer la scène `Game.tscn` et le `Player.gd` (Milestone C1)**
5) Implémenter le tir (Projectiles) et un ennemi cible (Milestone C2/C3)
