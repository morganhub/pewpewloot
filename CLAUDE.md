# PewPewLoot — Guide projet (CLAUDE.md)

Shoot'em up vertical 2D solo avec boucle ARPG/loot. Cible : Android portrait, Godot 4.6, 60 FPS. Sa signature : **certaines vagues changent à 100 % la façon de jouer** (mini-jeux : lane runner, pong, casse-briques, champ gravitationnel…), sur un fil conducteur commun (vaisseau, HP/shield, cristaux/score).

## Documentation : dossier `markdown/`

Toute la doc de travail vit dans **`markdown/`** — un dossier **local, gitignoré (non synchronisé sur GitHub)**. Cet index (`CLAUDE.md`) et `README.md` restent à la racine et sont versionnés.

**Règle de navigation** : avant de modifier une mécanique, lire d'abord le document dédié ci-dessous, puis les JSON/scripts qu'il référence. `markdown/project.md` est l'orientation détaillée (arborescence, managers, points d'entrée data-driven, où chercher selon la tâche, **procédure de test de compilation Godot en CLI**).

### En-tête des docs

Chaque `.md` de `markdown/` commence par un frontmatter YAML pour le triage IA. Le conserver et le tenir à jour lors des modifs :

```yaml
---
titre: <titre lisible>
domaine: <domaine gameplay/technique>
type: index | spec | backlog | archive | reference
statut: à jour | partiel | livré | archive
maj: <date, si connue>
resume: >
  <1-3 lignes de résumé>
liens: [slug_doc_lié, ...]   # nom de fichier sans .md
---
```

### Index des documents

| Doc | Type | Statut | Sujet |
|-----|------|--------|-------|
| [project.md](markdown/project.md) | index | à jour | Index projet : arborescence, managers, points d'entrée data-driven, test Godot CLI |
| [project_standby.md](markdown/project_standby.md) | backlog | à jour | Chantiers ouverts, TODOs code, priorités (audit mai 2026) |
| [world_setup.md](markdown/world_setup.md) | spec | à jour | Structure mondes/niveaux/vagues, skin_overrides, backgrounds, checklist d'ajout |
| [wave_types.md](markdown/wave_types.md) | spec | à jour | Tous les types de vagues — fiches uniformes (Principe / Bonus / Événements / Dangers / Câblage) + pipeline d'intégration + TODO |
| [wave_types_improvements.md](markdown/wave_types_improvements.md) | backlog | à jour | Banque d'idées : 13 types livrés et retirés ✅ ; reste asteroid_split (20 propositions) + idées transverses |
| [gateRunner.md](markdown/gateRunner.md) | spec | à jour | Spec dédiée du type de vague gate_runner (portes math, essaim de clones, générateur mode libre) |
| [snake.md](markdown/snake.md) | spec | à jour | Spec du type de vague snake (serpent contre boss — refonte totale de l'ex path_trial, 13 juillet 2026) |
| [wave_type_suika_up](markdown/wave_type_suika_up) | spec | livré | Spec d'origine du type suika_up (Suika inversé) — implémenté, source de vérité = wave_types.md |
| [pathtrial.md](markdown/pathtrial.md) | reference | archive partielle | Ex-vague PathTrial — ne survit que comme hazard de boss PowerManager (le type de vague est devenu snake) |
| [freemode.md](markdown/freemode.md) | spec | à jour | Mode Libre : mini-jeux en boucle infinie, levels 1→20, déblocage/achat, freemode.json |
| [project_attacks.md](markdown/project_attacks.md) | spec | à jour | Attaques, missiles, projectiles, powers, skills ; incohérences connues |
| [project_bosses.md](markdown/project_bosses.md) | spec | à jour | Système boss data-driven : phases, powers/hazards, tuning |
| [boss_powers_summary.md](markdown/boss_powers_summary.md) | reference | à jour | Assets missiles & powers des boss (arène debug) |
| [elites_project.md](markdown/elites_project.md) | spec | partiel | Ennemis élites par affixes (logique livrée ; assets standby) |
| [override_protocols.md](markdown/override_protocols.md) | spec | partiel | Override Protocols (mutateurs) ; achievements à faire |
| [score_implement.md](markdown/score_implement.md) | spec | partiel | Score local & étoiles (quasi livré ; finitions record global) |
| [score_evolution.md](markdown/score_evolution.md) | spec | partiel | Killstreak / multiplicateur / cristaux (logique livrée ; polish standby) |
| [performance_improvements.md](markdown/performance_improvements.md) | reference | à jour | Guide d'optimisation : caching, prewarming, budgets par frame, assets, debug perf, checklist |
| [skillsAssets.md](markdown/skillsAssets.md) | reference | à jour | Assets SkillsMenu + prompts Ludo.ai |
| [missing_assets.md](markdown/missing_assets.md) | reference | à jour | Rapport assets manquants + prompts Ludo.ai |
| [ludoAI_ImageGeneration.md](markdown/ludoAI_ImageGeneration.md) | reference | à jour | Pipeline local génération d'assets Ludo.ai : tools/ludo_generate.py, conversion/trim, table de câblage JSON — contient la clé API |
| [worldlevel_select.md](markdown/worldlevel_select.md) | archive | archive | Refonte carrousel World/Level select — ABANDONNÉE, ne pas suivre |

## Principes de maintenance

- Data-first quand la mécanique existe déjà ; ne pas hardcoder une valeur déjà présente dans `data/game.json` ou les JSON dédiés.
- Vérifier la cohérence des IDs entre JSON et runtime avant de toucher au code.
- Garder chaque doc de `markdown/` comme source de vérité de son domaine.
- Mettre à jour `markdown/project_standby.md` quand un chantier s'ouvre/se termine ; mettre à jour cet index (`CLAUDE.md`) si un doc est ajouté/supprimé/renommé, et `markdown/project.md` si l'arborescence ou les points d'entrée changent.

## Tester la compilation Godot

Godot est installé et le même `.exe` fait office de CLI. Procédure complète (binaire, pièges autoloads) dans `markdown/project.md` > « Tester la compilation Godot (CLI headless) ». Raccourci — outil committé `tools/verify_compile.gd` :

```powershell
$godot = "C:\Program Files (x86)\Godot\Godot_v4.6-stable_win64_console.exe"
& $godot --headless --path "c:\Tafor\Projet\pewpewloot" --script "res://tools/verify_compile.gd" ++ "res://scenes/Player.gd"
```


# Mode concis strict

Réponds court. Substance complète. Blabla supprimé.

Supprime :
- politesse ;
- intro ;
- répétition ;
- filler ;
- hedging ;
- narration d’outil ;
- longs logs non demandés.

Garde exact :
- code ;
- commandes ;
- APIs ;
- erreurs ;
- noms de fichiers ;
- noms de fonctions ;
- termes techniques.

Pattern :
- Bug : problème → cause → fix.
- Implémentation : fichier → changement → raison.
- Review : ligne → risque → correction.
- Question simple : réponse directe → détail utile seulement.

Langue :
- Réponds dans la langue de l’utilisateur.
- Ne force pas l’anglais.

Exceptions :
- Sécurité, suppression, migration DB, données sensibles, action irréversible : clarté > brièveté.
- Si compression crée ambiguïté, écris plus normalement.