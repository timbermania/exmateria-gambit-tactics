#!/usr/bin/env python3
"""Enforce the unified Ordering-Table depth seam (ADR-0009).

Every battle .gdshader that writes the DEPTH builtin must do so through the
shared seam: it must `#include` ot_depth.gdshaderinc and write only
`DEPTH = ot_computed_depth;` — never an inline NDC epsilon or an ad-hoc
projection. This is the cheap text net (mirrors gen_gpu_layout / ability_db
preflights); the DepthDebugScene is the visual/calibration regression.

A shader may opt out with an explicit, greppable marker comment:
    // psx-ot-depth-exempt: <reason>
Use this only for genuine non-OT depth writes (e.g. a screen-space/post pass).

Both `.gdshader` entry points and `.gdshaderinc` fragments are scanned, mirroring
check_par_shaders.py, so a DEPTH write placed in a shared include can't slip past.
Raw RenderingDevice `.glsl` shaders are scanned too: they can't `#include` the
Godot-shader-lang seam (different language), so a `.glsl` that computes OT depth
MUST carry the `psx-ot-depth-exempt: <reason>` marker AND single-source its
calibration from DepthMode. (The raw-RD fold that motivated this rule,
combat_displayspace_composite.glsl, was retired in #228 Phase 3; the check stays
so any future depth-writing `.glsl` is still covered.) Without the
marker, any literal `DEPTH = ...;` in a `.glsl` is flagged like a .gdshader.
Exit 0 if clean, 1 if any violation. Pure stdlib; no Godot needed.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
SHADER_DIR = PROJECT_DIR / "assets" / "shaders"
# ADR-0147 / extraction #1: the scan root is `classify_blueprint.WALK_ROOTS`, not a
# hard-coded directory. A guard root that does not follow the refactor's output loses
# coverage SILENTLY — see tools/_walk_roots.py for the reproduction.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()
INCLUDE = "ot_depth.gdshaderinc"
# Where the seam LIVES, res://-relative. SHADER_DIR above is where its CONSUMERS
# live and the two stopped being the same directory in prologue pass 6, when the
# kernel's two GPU halves moved into addons/exmateria_schema/ (ADR-0146).
SEAM_RES = "addons/exmateria_schema/compositing_key/" + INCLUDE
EXEMPT = "psx-ot-depth-exempt:"
ALLOWED_RHS = "ot_computed_depth"

# A DEPTH write statement anywhere on a code line: `DEPTH = ...;`. `=(?!=)`
# excludes the `DEPTH ==` comparison; comments are stripped before matching.
DEPTH_WRITE = re.compile(r"\bDEPTH\s*=(?!=)\s*(.+?);")
# A Godot shader include: #include "res://...".
INCLUDE_LINE = re.compile(r'#include\s+"res://([^"]+)"')


def _res_to_path(res_rel: str) -> Path:
    return PROJECT_DIR / res_rel


# The seam is matched by BASENAME, so an `#include` naming a path that no longer
# exists used to satisfy this guard while compiling to nothing. That was academic
# while the seam had lived at one path forever; prologue pass 6 moved it into
# addons/exmateria_schema/ and made a stale path a live way to lose the seam
# silently. The resolved file must exist (ADR-0146 dec. 8).
def includes_seam(path: Path, _seen: set[Path] | None = None) -> bool:
    """True if `path` reaches ot_depth.gdshaderinc through any #include chain."""
    if _seen is None:
        _seen = set()
    path = path.resolve()
    if path in _seen or not path.is_file():
        return False
    _seen.add(path)
    for res_rel in INCLUDE_LINE.findall(path.read_text(encoding="utf-8")):
        if res_rel.endswith(INCLUDE) and _res_to_path(res_rel).is_file():
            return True
        if includes_seam(_res_to_path(res_rel), _seen):
            return True
    return False


def check_shader(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    if EXEMPT in text:
        return []  # explicit opt-out

    writes = []
    for line in text.splitlines():
        # strip a trailing line comment before matching the statement
        code = line.split("//", 1)[0]
        m = DEPTH_WRITE.search(code)
        if m:
            writes.append(m.group(1).strip())

    if not writes:
        return []  # shader doesn't write DEPTH — not our concern

    problems = []
    if not includes_seam(path):
        problems.append(f"writes DEPTH but does not #include {INCLUDE} (directly or transitively)")
    for rhs in writes:
        if rhs != ALLOWED_RHS:
            problems.append(
                f"DEPTH = {rhs!r}; must be 'DEPTH = {ALLOWED_RHS};' "
                f"(route depth + bias through ot_depth(), no inline epsilon)"
            )
    return problems



# The burn-down, and it RATCHETS BOTH WAYS — the shape check_compositor_routing.py
# and check_no_pow_in_fold.py already use here.
#
# ADR-0147 / extraction #1 widened this guard from `assets/shaders` to the whole
# walk, and `src/ui3/shaders/` turned out never to have been scanned: 6 of the
# Formation/Changejob shaders write DEPTH without routing through ot_depth. That is UI's debt, not the extraction's, and
# fixing it inside a Render pass would be scope creep that changes UI's rendering.
# Narrowing the guard back would hide it again, so it is listed instead: a NEW
# violation anywhere fails, and an entry here that no longer violates ALSO fails,
# forcing its removal. The list shrinking to empty is the chart.
#
# Tracked at issue #363.
BURN_DOWN = {
    "src/ui3/shaders/changejob_cylinder_fold.gdshader",
    "src/ui3/shaders/formation_band_fold.gdshader",
    "src/ui3/shaders/formation_box_fold.gdshader",
    "src/ui3/shaders/formation_box_sub_fold.gdshader",
    "src/ui3/shaders/formation_orb_rim_fold.gdshader",
    "src/ui3/shaders/formation_shadow_fold.gdshader",
}


def main() -> int:
    if not SHADER_DIR.is_dir():
        print(f"ERROR: shader dir not found: {SHADER_DIR}", file=sys.stderr)
        return 1

    violations = {}
    shader_files = []
    for base in SCAN_DIRS:
        for suf in ("*.gdshader", "*.gdshaderinc", "*.glsl"):
            shader_files += sorted(base.rglob(suf))
    listed = set()
    for path in shader_files:
        rel = path.relative_to(PROJECT_DIR).as_posix()
        problems = check_shader(path)
        # A basename key collided the moment the walk widened past one flat
        # directory (formation_box_fold exists as BOTH .gdshader and .gdshaderinc,
        # and an addon may re-use a name). Key by the repo-relative path.
        if not problems:
            continue
        # Mark the entry listed only when the file STILL violates. Marking it on
        # existence looked sufficient and was not: the stale arm then only fired
        # when a listed path left the walk entirely, so a BURN_DOWN entry for a
        # clean file sat there forever reading as debt. Direction-tested both ways.
        if rel in BURN_DOWN:
            listed.add(rel)
            continue
        violations[rel] = problems
    for rel in sorted(BURN_DOWN - listed):
        violations[rel] = ["STALE BURN_DOWN entry — it no longer violates, or the "
                           "walk no longer reaches it. Remove it from BURN_DOWN."]

    if violations:
        print("ADR-0009 depth-seam violations:")
        for name, problems in violations.items():
            for p in problems:
                print(f"  {name}: {p}")
        print(
            f"\nFix: #include \"res://{SEAM_RES}\", set "
            "ot_computed_depth = ot_depth(point, PROJECTION_MATRIX, to_view, mode) "
            "in vertex(), and write `DEPTH = ot_computed_depth;` in fragment(). "
            f"For a genuine non-OT depth write, add a `// {EXEMPT} <reason>` comment."
        )
        return 1

    print("OK: all DEPTH-writing shaders use the ot_depth seam (ADR-0009) — "
          "%d walked, %d on the BURN_DOWN list." % (len(shader_files), len(BURN_DOWN)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
