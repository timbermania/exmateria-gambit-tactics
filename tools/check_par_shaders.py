#!/usr/bin/env python3
"""Enforce the unified PSX pixel-aspect (PAR) seam (ADR-0060).

Every battle shader that writes the POSITION builtin must apply the horizontal
PAR stretch through the shared seam: it must `#include` pixel_aspect.gdshaderinc and
write POSITION from one of the two seam helpers — `pixel_aspect_full(...)` (flat,
map-attached geometry) or `pixel_aspect_anchor(...)` (anchor-tracking billboards).
This is the POSITION analogue of ADR-0009's DEPTH rule (check_depth_shaders.py):
a cheap text net that makes "silently forgot to apply PAR" impossible to ship
(the recurring unit-shadow / dialogue-box misalignment bug this seam retires).

A shader may opt out with an explicit, greppable marker comment:
    // pixel-aspect-exempt: <reason>
Use this only for genuine screen-space passes that map quad corners straight to
NDC (fullscreen overlays) — geometry with nothing in battle space to align to.

Both `.gdshader` entry points and `.gdshaderinc` fragments are scanned, because
several POSITION writes live in shared includes (tile_overlay / tile_cursor /
effect_particle_stp). Raw RenderingDevice `.glsl` shaders are scanned too: they
can't `#include` pixel_aspect.gdshaderinc (different language), so a `.glsl` that maps
geometry into clip space MUST carry the `pixel-aspect-exempt: <reason>` marker and read
its live pixel_aspect / fx_stretch from the host. (The raw-RD fold that motivated this
rule, combat_displayspace_composite.glsl, was retired in #228 Phase 3; the check
stays so any future POSITION-writing `.glsl` is still covered.)
Exit 0 if clean, 1 if any violation. Pure stdlib.
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
INCLUDE = "pixel_aspect.gdshaderinc"
# Where the seam LIVES, res://-relative. SCAN_DIRS above is where its CONSUMERS
# live; the two stopped being the same directory at extraction #3's loop pass 6,
# when `platform` took its own address (ADR-0169 dec. 1). Pinning the full path
# is ADR-0146 dec. 8, which this guard never received — dec. 6 of that same ADR
# records why it mattered here: `endswith` on a bare BASENAME means the guard
# survived the move by accident and stays blind to a mistyped path that happens
# to end in the right eleven characters. `check_color_shaders.py` is the shape.
SEAM_RES = "addons/exmateria_platform/pixel_aspect/" + INCLUDE
EXEMPT = "pixel-aspect-exempt:"
HELPERS = ("pixel_aspect_full(", "pixel_aspect_anchor(")

# A POSITION write statement anywhere on a code line: `POSITION = ...;`.
# `=(?!=)` excludes the `POSITION ==` comparison; comments are stripped first.
POSITION_WRITE = re.compile(r"\bPOSITION\s*=(?!=)\s*(.+?);")
# A Godot shader include: #include "res://...".
INCLUDE_LINE = re.compile(r'#include\s+"res://([^"]+)"')


def _res_to_path(res_rel: str) -> Path:
    return PROJECT_DIR / res_rel


def includes_seam(path: Path, _seen: set[Path] | None = None) -> bool:
    """True if `path` reaches pixel_aspect.gdshaderinc through any #include chain."""
    if _seen is None:
        _seen = set()
    path = path.resolve()
    if path in _seen or not path.is_file():
        return False
    _seen.add(path)
    for res_rel in INCLUDE_LINE.findall(path.read_text(encoding="utf-8")):
        # ADR-0146 dec. 8: the basename is not the seam — the FILE is. A path
        # ending in `pixel_aspect.gdshaderinc` that resolves to nothing is a broken
        # include, and reading it as a satisfied seam is the exact way a guard
        # goes green on a move it should have caught.
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
        m = POSITION_WRITE.search(code)
        if m:
            writes.append(m.group(1).strip())

    if not writes:
        return []  # shader doesn't write POSITION — not our concern

    problems = []
    if not includes_seam(path):
        problems.append(f"writes POSITION but does not #include {INCLUDE} (directly or transitively)")
    for rhs in writes:
        if not any(h in rhs for h in HELPERS):
            problems.append(
                f"POSITION = {rhs!r}; must apply PAR via a seam helper "
                f"(pixel_aspect_full(...) or pixel_aspect_anchor(...)); the helper call "
                f"must appear in the POSITION write itself"
            )
    return problems



# The burn-down, and it RATCHETS BOTH WAYS — the shape check_compositor_routing.py
# and check_no_pow_in_fold.py already use here.
#
# ADR-0147 / extraction #1 widened this guard from `assets/shaders` to the whole
# walk, and `src/ui3/shaders/` turned out never to have been scanned: 11 of the
# Formation/Changejob shaders write POSITION without applying PAR through the seam. That is UI's debt, not the extraction's, and
# fixing it inside a Render pass would be scope creep that changes UI's rendering.
# Narrowing the guard back would hide it again, so it is listed instead: a NEW
# violation anywhere fails, and an entry here that no longer violates ALSO fails,
# forcing its removal. The list shrinking to empty is the chart.
#
# Tracked at issue #363.
BURN_DOWN = {
    "src/ui3/shaders/changejob_cylinder.gdshader",
    "src/ui3/shaders/changejob_cylinder_fold.gdshader",
    "src/ui3/shaders/formation_band.gdshader",
    "src/ui3/shaders/formation_band_fold.gdshader",
    "src/ui3/shaders/formation_box.gdshaderinc",
    "src/ui3/shaders/formation_box_fold.gdshaderinc",
    "src/ui3/shaders/formation_orb.gdshaderinc",
    "src/ui3/shaders/formation_orb_rim_fold.gdshader",
    "src/ui3/shaders/formation_shadow.gdshader",
    "src/ui3/shaders/formation_shadow_fold.gdshader",
    "addons/exmateria_sprite_rig/render/unit_flat.gdshader",
    # 12th entry, and the first added AFTER the list was written: `202a29ac0` (#932,
    # 2026-09-06) landed a fold twin for the dialogue page-turn icon's shadow. Its
    # vertex function is character-for-character `formation_shadow_fold.gdshader`'s,
    # already three lines above — `POSITION = clip` purely so the fragment can write
    # `DEPTH = fold_depth` — so this is the SAME debt in a new file, not a new kind.
    # Listed rather than fixed here because applying the seam changes how a UI
    # element renders, which is #363's call and not a passing session's; filed so the
    # owner can rule on it. Found by #892's pre-flight, which is the first one to run
    # since #932 merged.
    "src/ui3/shaders/menu_cursor_shadow_fold.gdshader",
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
        print("ADR-0060 PAR-seam violations:")
        for name, problems in violations.items():
            for p in problems:
                print(f"  {name}: {p}")
        print(
            f"\nFix: #include \"res://{SEAM_RES}\" and write "
            "`POSITION = pixel_aspect_full(clip);` (flat map-attached geometry) or "
            "`POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, stretch);` "
            "(anchor-tracking billboards). For a genuine fullscreen/screen-space "
            f"pass, add a `// {EXEMPT} <reason>` comment."
        )
        return 1

    print("OK: all POSITION-writing shaders apply PAR through the pixel_aspect seam (ADR-0060) — "
          "%d walked, %d on the BURN_DOWN list." % (len(shader_files), len(BURN_DOWN)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
