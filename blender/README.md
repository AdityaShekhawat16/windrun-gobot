# Blender source assets
Store editable `.blend` files here.

Asset conventions for WINDRUN:
- Build in meters; 1 Blender unit = 1 meter.
- Use +Y up in Godot after import; review orientation on test import.
- Apply scale and rotation before export (`Ctrl+A` > Rotation & Scale).
- Use modest polygon counts, texture atlases and LODs for integrated graphics.
- Export as `.glb` / glTF 2.0 into `assets/models/`.
- Maintain naming such as `tree_oak_a.glb`, `runner_base.glb`, and `grass_clump_a.glb`.
- Verify render and animation in Godot before populating the world.
