#!/usr/bin/env python3
"""Enforce that battle meshes don't opt out of the OT depth model (ADR-0009).

`check_depth_shaders.py` guards the shader side: any .gdshader that writes DEPTH
must route through the ot_depth seam. But a mesh can also escape the one
Ordering-Table model the *other* way — by using a stock `StandardMaterial3D`,
whose true per-fragment depth mis-sorts against flat-CUSTOM0 terrain. That is
exactly how projectiles slipped the original migration (their vertex-color
models rendered through StandardMaterial3D), unseen by the shader net because
they wrote no DEPTH at all.

This is the complementary text net: every `StandardMaterial3D.new(` in src/ must
carry an explicit, greppable opt-out marker — the same token the shader net uses:
    // psx-ot-depth-exempt: <reason>   (or a `#` comment in GDScript)
on the constructor line or the line directly above it. Use it only for genuine
non-OT meshes (debug markers, screen-space UI gizmos) — never for battle render
geometry, which must use a ShaderMaterial reaching the seam.

Scope/limits: this catches the StandardMaterial3D escape hatch (the one that bit
us). It does NOT catch a battle mesh wearing a custom ShaderMaterial whose shader
simply never writes DEPTH — distinguishing "battle mesh" from UI/debug statically
is unreliable. The shader net + this net together close the StandardMaterial3D
hole; a no-DEPTH custom shader on a battle mesh remains a review concern.

Exit 0 if clean, 1 if any unmarked constructor. Pure stdlib; no Godot needed.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()
MARKER = "psx-ot-depth-exempt:"
# Match the constructor specifically (not type hints, docstrings, or prose).
CTOR = re.compile(r"\bStandardMaterial3D\s*\.\s*new\s*\(")


def check_file(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    problems = []
    prev = ""
    for i, line in enumerate(lines, start=1):
        code = line.split("#", 1)[0]  # strip GDScript line comment for ctor match
        if CTOR.search(code):
            if MARKER not in line and MARKER not in prev:
                rel = path.relative_to(PROJECT_DIR)
                problems.append(
                    f"{rel}:{i}: StandardMaterial3D.new() without a "
                    f"`# {MARKER} <reason>` marker (on this line or the line above)"
                )
        prev = line
    return problems


def main() -> int:
    missing = [d for d in SCAN_DIRS if not d.is_dir()]
    if missing:
        print(f"ERROR: scan dir not found: {missing[0]}", file=sys.stderr)
        return 1

    violations = []
    for path in sorted(p for d in SCAN_DIRS for p in d.rglob("*.gd")):
        violations.extend(check_file(path))

    if violations:
        print("ADR-0009 battle-material violations (StandardMaterial3D opt-out):")
        for v in violations:
            print(f"  {v}")
        print(
            f"\nFix: a battle mesh must use a ShaderMaterial whose shader reaches "
            f"ot_depth.gdshaderinc. For a genuine non-OT mesh (debug marker, "
            f"screen-space gizmo), add a `# {MARKER} <reason>` comment on the "
            f"constructor line or the line directly above it."
        )
        return 1

    print("OK: no unmarked StandardMaterial3D in the walk — no battle mesh escapes OT depth (ADR-0009).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
