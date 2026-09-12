#!/usr/bin/env python3
"""Stop the unit-sprite compositor fork from regrowing (ADR-0189 decision 8).

`Sprite Rig` publishes a VARIANT. `UnitMaterial.for_variant(OPAQUE|ADDITIVE|FLAT)`
is the door, and no `.gd` outside `Sprite Rig` names a unit shader path.

WHAT THIS TREATS. Not "a path appears somewhere" — the DUPLICATION that a path
enables. `SpriteLayerManager.initialize(anim_set, shader_material)` takes its
material from the caller, so any consumer can reach in and overwrite `.shader`.
Two did: `FormationScene` and `ScenarioVM`, one `load()` call each. One of them
then grew a 1,018-line hand-synced fork of the compositor to have a path worth
naming, whose own header asked a human to "re-sync this fork" when it drifted.
ADR-0189 removed both the fork and the paths; this keeps them removed. The
precedent is `check_no_raw_psx_units.py`, written the same way for ADR-0091 —
a de-duplication that had just landed and had nothing holding it.

THE NET NAMES THREE FILES, IT DOES NOT GLOB `unit*.gdshader`. Decision 8 was
written as a glob and the glob is wrong here, measured:

  * `assets/shaders/unit_portrait_3d.gdshader` matches it and is NOT a variant —
    it is booked `UI`, draws EVTFACE dialogue portraits from fully-resolved RGBA
    (not the SPR's indexed, 90°-rotated landscape), and `UIPortrait.gd` naming it
    is correct. A glob would red a correct file and the fix would be an exemption
    apologising for the rule.
  * `addons/exmateria_sprite_rig/render/unit_sprite_body.gdshaderinc` is the shared include, not an
    entry point. Nothing mounts it; naming it is not the disease.

A named list also fails LOUDLY when a variant is renamed or moved, instead of a
glob quietly matching nothing (#424: an exclusion rule that is a FILTER rather
than a NAMED LIST manufactured a tenth debt file, and a filter has the specific
failure mode that what stops matching silently leaves the required set).

COMMENTS ARE STRIPPED, AND THAT IS NOT A CONVENIENCE. Ten `.gd` files mention a
unit shader path in prose — SpriteLayerManager, Unit, ScenarioDialogueBoxPool
(three sites), UI3OwnerColorMap, ScenarioVM, FormationScene — every one a
legitimate cross-reference explaining where a behaviour lives. A text scan reds
all of them, and the "fix" would be deleting accurate documentation. Only CODE
can mount a shader, so only code is scanned.

ONE ALLOWANCE IS A TEST, ON PURPOSE. `tests/ScenarioDeadUnitFadeTest.gd`
preloads the opaque and additive shaders and asserts
`enemy.material.shader == AdditiveShader`. Routing it through
`UnitMaterial.shader_for(ADDITIVE)` would satisfy this guard and destroy the
test: it would compare the module's answer to the module's answer, and could no
longer disagree with the code. An independent oracle has to name the thing
independently. Allowed, with that reason on the row.

Run: uv run python tools/check_unit_shader_paths.py
"""
from __future__ import annotations

import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# The three entry shaders `ExMateriaSchema.UnitMaterialVariant.Kind` selects between.
# The VALUE SET is the kernel's (ADR-0217 dec. 7); the TABLE mapping a variant to a
# path is `UnitMaterial.gd`'s, which is why this list still points there. Named, not
# globbed.
VARIANT_PATHS = (
    "res://addons/exmateria_sprite_rig/render/unit.gdshader",
    "res://addons/exmateria_sprite_rig/render/unit_additive.gdshader",
    "res://addons/exmateria_sprite_rig/render/unit_flat.gdshader",
)

# `.gd` files permitted to name one. Each row carries WHY, because an allowance
# without a reason is indistinguishable from an oversight.
ALLOWED = {
    "addons/exmateria_sprite_rig/render/UnitMaterial.gd":
        "Sprite Rig's variant module — it publishes the table; this is the one home",
    "tests/UnitMaterialVariantTest.gd":
        "the variant contract's own guard: it must name the files it pins",
    "tests/ScenarioDeadUnitFadeTest.gd":
        "the INDEPENDENT oracle for the additive swap — routing it through "
        "UnitMaterial.shader_for() would make it compare the module to itself",
}

WALK_ROOTS = ("src", "tests", "addons", "assets")

_STR = re.compile(r'"[^"\n]*"|\'[^\'\n]*\'')


def strip_comments(src: str) -> str:
    """Blank out `#`-to-end-of-line comments, but never inside a string literal.

    A `res://…` path IS a string literal, so a naive `split("#")` would be fine
    for finding paths but would also swallow a path preceded by a `#` earlier on
    the line. Masking string spans first keeps both halves honest.
    """
    out = []
    for line in src.split("\n"):
        masked = _STR.sub(lambda m: "\x00" * len(m.group()), line)
        cut = masked.find("#")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def main() -> int:
    fail: list[str] = []

    # POSITIVE ARM FIRST. A guard whose subjects have moved passes vacuously, and
    # that is the failure mode this whole family has paid for (a stale scan root
    # shipped 14 green guards in extraction #1). If a variant is renamed, this
    # rule is out of date and says so instead of going quiet.
    for res_path in VARIANT_PATHS:
        rel = res_path.removeprefix("res://")
        if not (PROJECT_DIR / rel).is_file():
            fail.append(
                f"VARIANT_PATHS names a file that does not exist: {res_path} — "
                f"a variant moved and this rule went blind. Repath it."
            )

    gd_files = []
    for root in WALK_ROOTS:
        base = PROJECT_DIR / root
        if not base.is_dir():
            fail.append(f"walk root missing: {root}/ — the scan lost a root")
            continue
        gd_files.extend(p for p in base.rglob("*.gd") if ".godot" not in p.parts)

    if len(gd_files) < 200:
        fail.append(f"walk found only {len(gd_files)} .gd files — the scan looks truncated")

    hits_by_allowed: dict[str, int] = {k: 0 for k in ALLOWED}
    for path in sorted(gd_files):
        rel = path.relative_to(PROJECT_DIR).as_posix()
        code = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for lineno, line in enumerate(code.split("\n"), 1):
            for res_path in VARIANT_PATHS:
                if res_path not in line:
                    continue
                if rel in ALLOWED:
                    hits_by_allowed[rel] += 1
                    continue
                fail.append(
                    f"{rel}:{lineno} names {res_path} — ask Sprite Rig for a variant "
                    f"instead: UnitMaterial.for_variant(...) / .shader_for(...)"
                )

    # A STALE ALLOWANCE FAILS TOO. An entry that no longer names a path is an
    # exemption nobody is using, and the next real violation in that file would
    # inherit it silently. Same rule the BURN_DOWN lists use.
    for rel, why in ALLOWED.items():
        if not (PROJECT_DIR / rel).is_file():
            fail.append(f"ALLOWED names a file that does not exist: {rel} ({why})")
        elif hits_by_allowed[rel] == 0:
            fail.append(
                f"ALLOWED entry is STALE — {rel} no longer names a variant path, "
                f"so its allowance ({why}) is unused. Remove the row."
            )

    if fail:
        print("ADR-0189 dec. 8 — unit shader paths outside Sprite Rig:", file=sys.stderr)
        for f in fail:
            print(f"  {f}", file=sys.stderr)
        print(
            "\nFix: a consumer asks for a BLEND, not a file. "
            "UnitMaterial.for_variant(OPAQUE|ADDITIVE|FLAT) returns a configured "
            "material; UnitMaterial.shader_for(v) returns the shader alone for a "
            "consumer that already owns a live material.",
            file=sys.stderr,
        )
        return 1

    allowed_desc = ", ".join(f"{k} ({v} ref)" for k, v in sorted(hits_by_allowed.items()))
    print(
        f"OK: no .gd outside Sprite Rig names a unit shader path (ADR-0189 dec. 8) — "
        f"{len(gd_files)} .gd walked, 3 variants named, allowed: {allowed_desc}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
