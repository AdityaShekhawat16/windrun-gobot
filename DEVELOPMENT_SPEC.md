# v1.2 technical design notes

## Constraints
- Preserve all motion constants and input code from v1.1 (`runner.gd` unchanged).
- Terrain heights are deterministic and continuous across streamed tile edges.
- Keep tiled grass patches streaming in a wide area with look-ahead at speed.
- Use MultiMesh instances so foliage does not imply tens of thousands of nodes.
- Maintain a low-density mode (V) and a 30 FPS performance target.

## Runtime resources
- `shaders/meadow_ground.gdshader`: world-space noise with valley/ridge colors.
- `shaders/grass_cards.gdshader`, `assets/grass_painterly.png`: two crossed cards
  with alpha scissor and animated wind.
- `shaders/flower_cards.gdshader`, `assets/wildflowers_painterly.png`: flower cards.
- `shaders/leaf_crowns.gdshader`: textured-looking lit leaves, no custom textures.
- `assets/cloud_banks.png`: billboard sprites beneath existing panoramic sky.
- `assets/sky_day.jpg` and `sky_golden.jpg`: updated 2:1 equirectangular assets.

## Known risks
- Shader compilation and performance cannot be verified without running Godot.
- Transparency cutouts can show jagged edges on some GPUs; multisampling or
  painterly foliage quality can be adjusted in the Godot project.
- No landscape screenshot in this package is an in-engine benchmark.
- The player is not a skinned professional character rig yet.
