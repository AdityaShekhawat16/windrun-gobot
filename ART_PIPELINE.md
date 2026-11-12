# WINDRUN 2.0 — Hero Valley art pipeline

**Mission**: Upgrade art without changing the feel of the playable v1.2 game.

## First vertical slice
1. Import a single premium stylized tree asset to Godot as `.glb`, test scale, shadows, and framerate.
2. Import one grass mesh/material variant and compare in a 100 m × 100 m preview patch.
3. Import one skinned humanoid (`Skeleton3D` + animations), test run/jump blend with existing runner controller.
4. Evaluate Mobile renderer versus GL Compatibility on actual Intel integrated graphics before committing to either.
5. Assemble a hero valley scene, with deliberate composition and painterly sky, preserving 30 FPS minimum.

## Acceptance checks
- No change to `scripts/runner.gd` movement constants unless intentionally justified and separately tested.
- No sudden foliage pop-in during 160–220 km/h traversal.
- No missing textures, silhouettes, or broken imports.
- Consistent shading and shadow softness.
- Record FPS at 1280×720 and 160 km/h traversal with F3.

## Recommended asset packs
- Quaternius Stylized Nature MegaKit — https://quaternius.com/packs/stylizednaturemegakit.html
- Quaternius Universal Base Characters — https://quaternius.com/packs/universalbasecharacters.html
- Quaternius Universal Animation Library — https://quaternius.itch.io/universal-animation-library

Check the actual downloaded license text and keep it alongside any imported assets.
