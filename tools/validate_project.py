#!/usr/bin/env python3
"""Lightweight static asset/reference preflight (not a substitute for a Godot playtest)."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
required = [
    "project.godot", "scenes/main.tscn", "scripts/game.gd",
    "scripts/world.gd", "scripts/runner.gd", "scripts/landmarks.gd",
    "assets/meadow_theme.wav", "assets/sky_day.jpg", "assets/sky_golden.jpg"
]
missing = [x for x in required if not (root / x).is_file()]
unresolved = set()
for folder in ("project.godot", "scenes", "scripts", "shaders"):
    files = [root / folder] if (root / folder).is_file() else (root / folder).rglob("*")
    for f in files:
        if not f.is_file() or f.suffix not in {".gd", ".tscn", ".gdshader", ".godot"}:
            continue
        try: text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError: continue
        for ref in re.findall(r'res://([^"\'\s)]+)', text):
            rel = ref.split("::",1)[0]
            if rel and not (root / rel).exists() and not rel.endswith("/"):
                unresolved.add((f.relative_to(root).as_posix(),rel))
print("WINDRUN project root:", root)
print("Required files:", "OK" if not missing else "MISSING " + ", ".join(missing))
print("Literal res:// references:", "OK" if not unresolved else "CHECK")
for f,rel in sorted(unresolved): print(" ",f,"->",rel)
raise SystemExit(1 if missing or unresolved else 0)
