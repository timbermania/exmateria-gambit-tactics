#!/usr/bin/env python3
"""Enforce the unified colour-mode seam (ADR-0067).

A shader that recolours the final pixel through the 11-mode stack does it via ONE
shared seam: it `#include`s color_stack.gdshaderinc and folds via `color_apply(
base, surface_id)`. This is NOT every shader — only the colour consumers that fold
CLUT colour over time (5 today: unit, indexed_color, screen_background, formation_unit,
color_stack_gpu_probe). This is the colour analog of check_depth_shaders.py (ADR-0009):
a cheap text net that keeps the two engines from re-forking. The ColorStack /
ColorRecipe unit tests + the ColorStackGpuParityTest are the value/byte-exactness
regressions; this net keeps the *routing* honest.

Two rules:
  1. No shader may reintroduce a deleted legacy per-uniform tint path. The scenario
     {32}/{33} tint (unit_tint_scale/bias, unit_luma_*, field_tint_*, field_luma_*)
     and the combat screen tint (tint_color), plus the transition flag
     (use_color_stack), were folded into the stack and removed — a shader declaring
     any of them again is drifting back toward a second engine. The combat additive
     unit_tint / map_tint uniforms were retired too (issue #164) — combat palette
     effects now fold through the stack (TintedSurfaces/MapTintOverlay).
  2. Any shader that calls color_apply must reach the include through its
     #include chain (mirrors "writes DEPTH -> must include ot_depth").

Plus a positive check: the known colour consumers must still route through
color_apply, so the model can't be silently dropped from one of them.

A shader may opt out of rule 1 with an explicit, greppable marker:
    // psx-color-exempt: <reason>
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
INCLUDE = "color_stack.gdshaderinc"
# Where the seam LIVES, res://-relative. SHADER_DIR above is where its CONSUMERS
# live and the two stopped being the same directory in prologue pass 6, when the
# kernel's two GPU halves moved into addons/exmateria_schema/ (ADR-0146).
SEAM_RES = "addons/exmateria_schema/colour_model/" + INCLUDE
EXEMPT = "psx-color-exempt:"
APPLY = "color_apply"

# Legacy per-uniform tint paths that were folded into the stack and deleted (ADR-0067).
# Reintroducing any is a drift back to a second engine. The combat additive unit_tint /
# map_tint uniforms were retired too (issue #164): combat palette effects now fold
# through the stack (TintedSurfaces/MapTintOverlay push color_layer_*), so a shader
# re-declaring them is drifting back to the delta-domain path that couldn't express the
# base-dependent luma / absolute-base modes.
BANNED_UNIFORMS = (
    "unit_tint_scale", "unit_tint_bias",
    "unit_luma_div", "unit_luma_delta5", "unit_luma_from_current", "unit_luma_mix",
    "field_tint_scale", "field_tint_bias",
    "field_luma_div", "field_luma_delta5", "field_luma_from_current", "field_luma_mix",
    "tint_color", "use_color_stack",
    "unit_tint", "map_tint",
)
# Shaders that must keep routing their colour transform through the seam, as FULL
# project-relative paths. They were bare basenames resolved against `SHADER_DIR`
# until extraction #3's loop pass 6, when two of the three moved into
# `addons/exmateria_battlefield/` and this positive arm went red — correctly, and
# for the wrong reason. "Missing" and "moved" are different facts, and a basename
# hung off one hardcoded directory cannot tell them apart. This is the same rule
# ADR-0146 dec. 8 states for the negative arm (`endswith` must be paired with
# `.is_file()`), applied to the positive one: name the FILE, not its last segment.
#
# FIVE entry shaders reach color_apply, not three: `unit_additive` and the flat
# formation variant were both unnamed (ADR-0189 dec. 7). Under the old basename form
# `unit_flat` was additionally UNADDRESSABLE while it lived in src/ui3/shaders/,
# because the loop below resolved names under one directory only — listing it would
# have been a line that could never match. Full paths retire that hazard for good,
# which is why the two fixes belong together.
REQUIRED_CONSUMERS = (
    "addons/exmateria_sprite_rig/render/unit.gdshader",
    "addons/exmateria_sprite_rig/render/unit_additive.gdshader",
    "addons/exmateria_sprite_rig/render/unit_flat.gdshader",
    "addons/exmateria_battlefield/texturing/indexed_color.gdshader",
    "addons/exmateria_battlefield/camera/screen_background.gdshader",
)

INCLUDE_LINE = re.compile(r'#include\s+"res://([^"]+)"')
UNIFORM_DECL = re.compile(r"^\s*(?:global\s+)?uniform\s+\w+\s+(\w+)\b")


def _res_to_path(res_rel: str) -> Path:
    return PROJECT_DIR / res_rel


# The seam is matched by BASENAME, so an `#include` naming a path that no longer
# exists used to satisfy this guard while compiling to nothing. That was academic
# while the seam had lived at one path forever; prologue pass 6 moved it into
# addons/exmateria_schema/ and made a stale path a live way to lose the seam
# silently. The resolved file must exist (ADR-0146 dec. 8).
def includes_seam(path: Path, _seen: set[Path] | None = None) -> bool:
    """True if `path` reaches color_stack.gdshaderinc through any #include chain.

    The seam file IS the seam — it defines color_apply, so it trivially satisfies
    the rule (it needn't, and can't sensibly, include itself). Only real `#include`
    directives count: a directive that appears solely inside a `//` comment (e.g. the
    usage example in the include's own header) is ignored, so removing that doc comment
    can never flip a file's seam status.
    """
    if _seen is None:
        _seen = set()
    path = path.resolve()
    # existence FIRST: a `#include` naming a stale path resolves to a file whose
    # NAME is still the seam's, and answering on the name alone let a dangling
    # include pass (ADR-0146 dec. 8 — caught by that decision's own second
    # direction test, one round after the first fix looked sufficient).
    if path in _seen or not path.is_file():
        return False
    if path.name == INCLUDE:
        return True
    _seen.add(path)
    for line in path.read_text(encoding="utf-8").splitlines():
        for m in INCLUDE_LINE.finditer(line):
            # A `//` before the `#include` token comments the directive out. Note the
            # `res://` in the path also holds `//`, but that always follows `#include`,
            # so comparing against the match start distinguishes the two cleanly.
            comment = line.find("//")
            if comment != -1 and comment < m.start():
                continue
            res_rel = m.group(1)
            if ((res_rel.endswith(INCLUDE) and _res_to_path(res_rel).is_file())
                    or includes_seam(_res_to_path(res_rel), _seen)):
                return True
    return False


def calls_apply_transitively(path: Path, _seen: set[Path] | None = None) -> bool:
    """True if `path` — or any file it `#include`s (transitively) — calls color_apply.

    The positive consumer check must accept a consumer that routes its colour through
    the seam from within a shared include: unit.gdshader folds via color_apply()
    inside unit_sprite_body.gdshaderinc, not in its own body. Grepping only the file's
    own text would falsely flag it. Mirrors includes_seam's include-walk; only real
    (non-commented) #include directives count.
    """
    if _seen is None:
        _seen = set()
    path = path.resolve()
    if path in _seen or not path.is_file():
        return False
    _seen.add(path)
    lines = path.read_text(encoding="utf-8").splitlines()
    if any(APPLY in ln.split("//", 1)[0] for ln in lines):
        return True
    for line in lines:
        for m in INCLUDE_LINE.finditer(line):
            comment = line.find("//")
            if comment != -1 and comment < m.start():
                continue
            if calls_apply_transitively(_res_to_path(m.group(1)), _seen):
                return True
    return False


def check_shader(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    exempt = EXEMPT in text
    problems = []

    if not exempt:
        for line in text.splitlines():
            code = line.split("//", 1)[0]
            m = UNIFORM_DECL.match(code)
            if m and m.group(1) in BANNED_UNIFORMS:
                problems.append(
                    f"declares deleted legacy tint uniform '{m.group(1)}' — fold it into "
                    f"the color stack ({APPLY}) instead of a per-uniform path"
                )

    # Any shader that folds through color_apply must reach the include.
    calls_apply = any(APPLY in ln.split("//", 1)[0] for ln in text.splitlines())
    if calls_apply and not includes_seam(path):
        problems.append(f"calls {APPLY}() but does not #include {INCLUDE} (directly or transitively)")
    return problems


def main() -> int:
    if not SHADER_DIR.is_dir():
        print(f"ERROR: shader dir not found: {SHADER_DIR}", file=sys.stderr)
        return 1

    violations = {}
    shader_files = []
    for base in SCAN_DIRS:
        for suf in ("*.gdshader", "*.gdshaderinc"):
            shader_files += sorted(base.rglob(suf))
    for path in shader_files:
        problems = check_shader(path)
        if problems:
            violations[path.name] = problems

    # Positive check: the known consumers must still route through the seam.
    for name in REQUIRED_CONSUMERS:
        path = PROJECT_DIR / name
        if not path.is_file():
            violations.setdefault(name, []).append("expected colour consumer is missing")
            continue
        if not calls_apply_transitively(path):
            violations.setdefault(name, []).append(
                f"must fold its colour through {APPLY}() (ADR-0067 consumer)"
            )

    if violations:
        print("ADR-0067 colour-seam violations:")
        for name, problems in sorted(violations.items()):
            for p in problems:
                print(f"  {name}: {p}")
        print(
            f"\nFix: #include \"res://{SEAM_RES}\" and recolour via "
            f"`{APPLY}(base, surface_id)` instead of ad-hoc tint uniforms. For a genuine "
            f"non-stack colour path, add a `// {EXEMPT} <reason>` comment."
        )
        return 1

    print(f"OK: all colour-transforming shaders route through the {APPLY} seam (ADR-0067).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
