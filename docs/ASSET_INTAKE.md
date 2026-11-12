# WINDRUN — Art asset intake

## Free candidate assets
- Quaternius Stylized Nature MegaKit: https://quaternius.com/packs/stylizednaturemegakit.html
- Quaternius Universal Base Characters: https://quaternius.com/packs/universalbasecharacters.html
- Quaternius Universal Animation Library: https://quaternius.itch.io/universal-animation-library

Quaternius' Nature MegaKit page currently identifies the pack as CC0, with `.glTF` formats offered. Verify the specific files and licenses included in your own download before redistribution.

## First selection
Choose **one** broadleaf tree, **two** grass clumps and **one** small rock. Do not bulk-import 100 models yet. The purpose is to get a *small beautiful scene*, not to maximize object count.

## Conventions
- `.blend` sources → `blender/`
- exported `.glb` files → `assets/models/`
- textures → `assets/textures/`
- third-party license and attribution → `assets/third_party/README.md`
- test scenes → `scenes/`

## Blender import/export for .glb
1. Start Blender and use File → Import → glTF 2.0 to import the selected model (or open the provided `.blend`).
2. Confirm correct scale, origin, outward facing normals, object naming, UVs, textures and color space.
3. Use File → Export → glTF 2.0. Select **glTF Binary (.glb)**.
4. In Godot, copy the `.glb` to `assets/models/`, let Godot import, and drag the scene into a dedicated test scene.
5. Verify the model under the game's actual daylight lighting—not Blender's studio preview.
6. Record frame rate with F3 and compare against our v1.2 prototype.

## Performance guidelines
- Prefer instanced geometry for hundreds of grass objects.
- Transparent foliage is limited by fill rate: measure it carefully on integrated graphics.
- Use separate, simpler collision shapes and low-detail distance models.
- Keep distant grass shadow casting disabled until measured safe.
