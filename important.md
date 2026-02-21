# Resolution Notes: Spawn Stutter Root Cause and Fix

## Symptom observed
- The game had a reproducible micro-freeze exactly when the first enemy of a wave spawned (even offscreen).
- Background looked like it stuttered, but enemies/projectiles were mostly smooth.

## Key evidence from profiling
- `GameSpawn`: `instantiate` and `add_child` were cheap.
- `EnemySetup`: almost all cost was inside `visual`.
- Typical trace:
  - `EnemySetup total ~36ms`
  - `visual ~36ms`
  - `movement ~0ms`

This proved the bottleneck was not wave scheduling or path logic, but visual initialization at spawn time.

## What changed in the final decisive step
- In `scenes/Enemy.gd`, visual setup was optimized with a strong in-memory cache:
  - Added static strong cache for loaded resources (`_strong_resource_cache`).
  - Added static cache for first animation frame textures (`_first_frame_texture_cache`) used for scaling.
- Removed repeated expensive lookup/load behavior from hot spawn path:
  - No repeated `load()` per spawn for the same `.tres` / textures.
  - Reused onready visual nodes instead of repeated `get_node_or_null` lookups.
- Added fast path for common enemy visuals:
  - When animation is looped with no custom duration, play directly on `AnimatedSprite2D` instead of generic wrapper path.
- Warmup became effectively renderable:
  - Loading warmup host was made visible and positioned on-screen so first draw/upload occurs before gameplay.

## Why this solved it
- The stutter was caused by first-time visual resource work happening during enemy spawn on the gameplay frame.
- By forcing resources to stay strongly cached and by simplifying the per-spawn visual path, that work no longer happens at wave start.
- Result: first-wave enemy spawn no longer introduces a frame spike, and background no longer appears to hitch.

## Extended to other systems
- The same optimization pattern was applied to:
  - `scenes/Boss.gd`
  - `scenes/obstacles/ObstacleExplosive.gd`
  - `scenes/obstacles/ObstaclePusher.gd`

Goal: avoid similar first-use visual hitches for boss and obstacle spawns.

## Extra pass: loot drop hitch and drop-rate control
- A second hitch source can appear on enemy death when a loot drop is instantiated (`shield` / `rapid fire` / equipment item).
- Main fixes applied:
  - `LootDrop.tscn` is now preloaded in `Enemy.gd` (no runtime `load()` in the death frame).
  - Drop logic is now single-path: **max 1 drop per enemy death**.
  - Added configurable spawn rules in `data/game.json > gameplay > loot_drops`.
  - Added per-wave reservation caps in `Game.gd`:
    - max `shield` drops per wave
    - max `rapid_fire` drops per wave
    - counters reset on each `wave_started`.
- Resulting behavior:
  - No more double drop from one enemy.
  - No more overflow of powerups in the same wave.
  - Global loot rhythm can be tuned via JSON multipliers without code changes.
