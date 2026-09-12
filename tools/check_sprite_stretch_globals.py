#!/usr/bin/env python3
"""Enforce the per-taxonomy sprite-stretch global contract (ADR-0044).

ADR-0044 adds three per-taxonomy horizontal billboard-WIDTH multipliers for
Pattern-2 sprites, each an independent channel so the buckets stretch
separately (the cursor may want a stretch units must not share). Each of the
three names must exist on all THREE surfaces, or the channel is half-wired:

  1. `PSXDisplay.gd` — a `live_*_stretch` setter that pushes the value to the
     matching `psx_*_stretch` global shader parameter.
  2. `project.godot` — a `[shader_globals]` entry (so the global exists at
     load with its default `1.0`).
  3. some shader under `assets/shaders/` — a `global uniform float
     psx_*_stretch;` that reads the channel.

A channel present in the setter but missing from `[shader_globals]` (or vice
versa) is exactly the drift this guard catches: the scrub would move a value
nothing reads, or a shader would read a global that never gets set.

Exit 0 if all three channels are wired on all three surfaces, 1 otherwise.
Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# PSXDisplay.gd left src/core/ for the render addon at extraction #1 (ADR-0147 dec. 1)
# and left THAT for the platform tier at extraction #3's loop pass 6 — ADR-0171 dec. 1
# rules it a port rather than `Render`'s subject, ADR-0184 dec. 2 moved it. Its address
# has now changed twice while this constant said it once, which is the argument for the
# `it is missing` arm below: a hardcoded path that goes stale reports the seam as
# ABSENT rather than as MOVED, and those are different facts.
PSXDISPLAY = PROJECT_DIR / "addons" / "exmateria_platform" / "display_port" / "PSXDisplay.gd"
PROJECT_GODOT = PROJECT_DIR / "project.godot"
SHADER_DIR = PROJECT_DIR / "assets" / "shaders"
# ADR-0147 / extraction #1: the scan root is `classify_blueprint.WALK_ROOTS`, not a
# hard-coded directory. A guard root that does not follow the refactor's output loses
# coverage SILENTLY — see tools/_walk_roots.py for the reproduction.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()

# taxonomy -> the global shader-parameter name (ADR-0044)
CHANNELS = {
    "cursor": "psx_cursor_stretch",
    "unit": "unit_stretch",
    "fx": "psx_fx_stretch",
}


def main() -> int:
    problems: list[str] = []

    display_src = PSXDISPLAY.read_text(encoding="utf-8") if PSXDISPLAY.is_file() else ""
    if not display_src:
        print(f"ADR-0044: expected {PSXDISPLAY.relative_to(PROJECT_DIR)} — it is missing.")
        return 1
    project_src = PROJECT_GODOT.read_text(encoding="utf-8") if PROJECT_GODOT.is_file() else ""

    # Concatenate all shader sources once; a decl in any of them satisfies the read.
    shader_src = "\n".join(
        p.read_text(encoding="utf-8")
        for base in SCAN_DIRS for p in base.rglob("*")
        if p.suffix in (".gdshader", ".gdshaderinc")
    )

    for taxonomy, gname in CHANNELS.items():
        # 1. PSXDisplay setter pushes the global.
        setter = re.compile(
            rf'global_shader_parameter_set\(\s*&"{re.escape(gname)}"'
        )
        if not setter.search(display_src):
            problems.append(
                f"PSXDisplay.gd: no live_{taxonomy}_stretch setter pushing "
                f'`{gname}` via global_shader_parameter_set(&"{gname}", ...).'
            )
        # 2. project.godot [shader_globals] entry.
        if not re.search(rf"^{re.escape(gname)}\s*=", project_src, re.M):
            problems.append(
                f"project.godot: `{gname}` missing from [shader_globals] "
                "(the global would not exist with its 1.0 default at load)."
            )
        # 3. Some shader reads it as a global uniform.
        reader = re.compile(rf"global\s+uniform\s+float\s+{re.escape(gname)}\s*;")
        if not reader.search(shader_src):
            problems.append(
                f"assets/shaders/: no `global uniform float {gname};` — nothing "
                f"reads the {taxonomy} stretch channel."
            )

    if problems:
        print("ADR-0044 sprite-stretch global-channel violations:")
        for p in problems:
            print(f"  {p}")
        print(
            "\nFix: each of psx_cursor_stretch / unit_stretch / psx_fx_stretch "
            "must be wired on all three surfaces — PSXDisplay setter, project.godot "
            "[shader_globals], and a shader `global uniform`. See ADR-0044 → Consequences."
        )
        return 1

    print("OK: all three sprite-stretch channels wired setter+globals+shader (ADR-0044).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
