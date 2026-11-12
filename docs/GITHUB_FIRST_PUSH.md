# One-time GitHub Desktop setup

Repository: https://github.com/AdityaShekhawat16/windrun-gobot

The GitHub connection can read the repository but returned **403 Resource not accessible by integration** on writes in this session. This one-time push is therefore performed on Windows.

1. Install/open GitHub Desktop: https://desktop.github.com/
2. Sign in to GitHub.
3. File → Clone repository → choose `AdityaShekhawat16/windrun-gobot` → choose local folder.
4. Open that folder in Windows File Explorer.
5. **Copy the contents of this starter project** into the cloned folder, placing `project.godot` in the repository root. Do not nest the game in a second subfolder.
6. Overwrite the auto-generated `README.md` if prompted; the game starter README has setup instructions. Do not copy a `.godot/` cache.
7. Back in GitHub Desktop, verify new/changed files are listed. Summary: `Baseline: WINDRUN v1.2 and Hero Valley plan`.
8. Click `Commit to main`, then `Push origin`.
9. Check that `project.godot`, `scripts/`, `assets/` and `docs/HERO_VALLEY_PLAN.md` are visible on the GitHub website.

After step 9 we can create `windrun-2.0` from `main`, and safely start using Blender models in the branch.

Note: The starter pack includes WAV/PNG/JPG assets. If any are larger than GitHub's repository guidance allows, ask for Git LFS, but the current individual files are small enough for an ordinary push.
