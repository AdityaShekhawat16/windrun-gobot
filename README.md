# WINDRUN — 3D momentum game

A third-person momentum-based exploration game built in Godot 4. The current playable baseline is **v1.2**; the next major milestone is **WINDRUN 2.0 — Hero Valley**, a playable art-quality vertical slice.

## Play
1. Install Godot 4.4+ standard edition.
2. Import `project.godot`.
3. Press F5 and Enter.
4. WASD move · Shift sprint · Space jump · mouse look · Esc pause · F3 diagnostics · G daylight/golden hour.

## Source layout
- `scripts/`: player, world, landmarks and game state.
- `scenes/`: Godot scenes.
- `shaders/`: grass, leaves, terrain and flower materials.
- `assets/`: original textures and audio used by baseline.
- `blender/`: new art source location.
- `docs/HERO_VALLEY_PLAN.md`: new project roadmap and acceptance criteria.
- `docs/GITHUB_FIRST_PUSH.md`: instructions for committing this baseline to GitHub.

**Performance target:** 30 FPS minimum at 1280×720 on Windows with Intel integrated graphics. This starter is based on the user's playable v1.2, not a Godot runtime-tested 2.0 game.

Preserve the original movement physics and endless world while developing the new art pipeline on a separate `windrun-2.0` branch after the first baseline commit.
