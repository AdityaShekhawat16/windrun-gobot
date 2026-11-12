# WINDRUN GitHub baseline

This folder is a clean copy of the **playtested WINDRUN v1.2 project**, prepared for version control. Do not replace or delete your working v1.2 installation.

## First upload (recommended: GitHub Desktop)
1. Install GitHub Desktop (https://desktop.github.com/) and sign in.
2. `File > Clone repository` and select your new private WINDRUN repository.
3. Copy **the contents of this folder** (not the containing folder) into the local clone. Keep the repository's existing README if GitHub Desktop reports a conflict, or replace its contents deliberately.
4. In GitHub Desktop, enter commit message: `Baseline: WINDRUN v1.2 playable prototype`.
5. Click `Commit to main`, then `Push origin`.
6. Confirm `project.godot`, `scripts/`, `scenes/`, `shaders/`, `assets/` show in your repository on GitHub.

## Test locally
- Open Godot 4.4+ and import `project.godot`.
- Press F5, then Enter.
- Test WASD/Shift/Space and F3; target at least 30 FPS on your Intel-integrated-graphics laptop.

## Game-asset migration (upcoming)
- Put artist source files in `blender/`.
- Export `.glb` files to `assets/models/`.
- Keep third-party asset pack licenses/source notes in `assets/third_party/`.
- Add new objects **on a separate branch** so our physics baseline stays intact.

## GitHub ChatGPT connector
If ChatGPT doesn't list this newly created repository, open GitHub > Settings > Applications > Installed GitHub Apps, find the ChatGPT GitHub integration, click Configure and allow the repo. Reconnect or refresh the ChatGPT app if necessary.
