# WINDRUN 2.0 — Hero Valley design and acceptance plan

## Goal
Build **one excellent 400–600 m playable valley**, retaining the WINDRUN v1.2 movement physics while upgrading the environment from primitive procedural assets to cohesive, well-designed 3D models, vegetation materials, and lighting.

## Non-negotiables
- Keep the original v1.2 as a known-good playable baseline on `main`.
- Implement Hero Valley on the `windrun-2.0` branch, **only after** the baseline has been pushed.
- Do not rewrite the movement controller while improving graphics.
- Target at least **30 FPS at 1280×720** on the Intel-integrated-graphics Windows laptop.
- Measure FPS at rest and at 160–220 km/h, including after 2 km of running.

## First playable art test — 100 × 100 m
1. Import one striking broadleaf tree as a `.glb`.
2. Import two properly modeled grass varieties, with modest wind animation.
3. Build a shaded meadow ground material with gentle variation, no neon glow.
4. Add a composited sky, cloud shapes and directional daylight.
5. Add a focal rock or arch; test shadow quality and level of detail.
6. Capture one screenshot and record the FPS. Compare with v1.2.

## Then: Hero Valley — 400–600 m
- Construct one intentionally composed space with broad hills, an overlook, solitary trees, small flower patches, and a landmark visible from a distance.
- Place detailed assets manually in the playable showcase while preserving procedural terrain for travel beyond its boundary later.
- Allow smooth high-speed running and long jumps with correct ground collision.
- Keep the runner readable at speed, and avoid sudden dense grass pop-in.
- Provide day and golden-hour options, adjusting atmosphere and shadows.

## Character pipeline
- Import a rigged humanoid with a Godot `Skeleton3D`.
- Check humanoid scale, root axis, animations, and glTF export settings.
- Test idle/walk/run/jump/fall/land on the existing runner controller.
- Upgrade to a cream coat, dark trousers, gold scarf after the first character runs.

## Scope
No new collectibles, quests, inventory, combat, or traversal powers until the valley passes the visual and performance acceptance checks.

## Definition of done
- [ ] User can open `project.godot` and press F5 without missing resources.
- [ ] One viewpoint is markedly more beautiful than the v1.2 screenshots.
- [ ] Hills and a clear skyline remain readable in motion.
- [ ] Jump/landing response remains unchanged from v1.2.
- [ ] Minimum 30 FPS reported by F3 at 1280×720 on target laptop.
- [ ] Asset sources and licenses recorded.
