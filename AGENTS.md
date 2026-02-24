# AGENTS.md

## Overview

**Pewpewloot** is a vertical 2D shoot-em-up (shmup) mobile game built with **Godot 4.6** and **GDScript**. It features wave-based enemies, boss fights, ARPG loot mechanics, and a metagame progression system. The game is fully offline/standalone with no backend services.

## Cursor Cloud specific instructions

### Engine

- Godot 4.6 (stable) is required. The binary is installed at `/usr/local/bin/godot`.
- The project uses the `gl_compatibility` (OpenGL ES) renderer, targeting Android.

### Running the editor

- Launch with: `LIBGL_ALWAYS_SOFTWARE=1 godot --editor --path /workspace --rendering-driver opengl3`
- The `LIBGL_ALWAYS_SOFTWARE=1` env var is needed because the cloud VM has no GPU; Mesa software rendering is used.
- Vulkan errors (`VK_KHR_surface not found`) in logs are harmless — the editor falls back to OpenGL.
- ALSA audio errors are expected (no audio hardware); the engine falls back to a dummy driver.

### Headless operations

- Import/validate project: `godot --headless --import` (from the `/workspace` directory)
- Open editor headlessly (validate scripts + quit): `godot --headless --editor --quit`
- Run a standalone script: `godot --headless --script <script.gd>` (note: autoloads are not available when using `--script` mode outside the editor, so scripts referencing autoload singletons like `DataManager`, `AudioManager`, etc. will fail to compile in that context)

### Missing assets

- Binary assets (images, fonts, sounds, `.tres` resources) were removed from the repository. Errors about missing files under `res://assets/` are expected and do not affect GDScript code validation or editor functionality.
- The custom theme (`ui/ui_theme.tres`) fails to load due to missing font `res://assets/fonts/Michroma-Regular.ttf` — the editor falls back to the default theme.

### Project structure (key directories)

- `autoload/` — 14 singleton/autoload scripts (game managers)
- `scenes/` — 44 `.tscn` scene files + 50+ `.gd` scripts (gameplay, UI, effects)
- `data/` — 35 JSON data files (worlds, enemies, bosses, loot, skills, locales)
- `addons/` — vendored third-party addon (energy shield shader)
- `scripts/` and `tools/` — Python utility scripts (standard library only, no pip deps)

### Testing

- There is one test script: `test_elite_logic.gd` (extends `SceneTree`). It does not work reliably in `--script` mode due to autoload dependencies.
- No automated test framework is configured. Validation is done via editor import (`godot --headless --import`) and running the game.

### Running the game (play mode)

- From the editor: press the Play button (F5) or use `godot --path /workspace --rendering-driver opengl3` to run directly.
- The game starts at the profile selection screen → home screen → world select → level select → gameplay.
