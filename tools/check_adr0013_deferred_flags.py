#!/usr/bin/env python3
"""Lock ADR-0013's two raw-int ability fields in their raw state.

ADR-0013 decodes FFT bit-packed data at the parser boundary into semantic
structure (named-bool dicts / name arrays), so runtime never sees a bitmask.
Two ability fields in `assets/abilities/effects.json` stay raw `int` instead —
`anim_flags` and `rsm_other_id` — but for DIFFERENT reasons, and neither is the
`weapon_flags` / elements case (whose bit meanings FFTPatcher already names):

  * `anim_flags` — bit semantics **not yet reverse-engineered**; there is
    nothing faithful to decode *into* yet. Raw pending an RE session.
  * `rsm_other_id` — RE **complete** (2026-07-04): this byte is not flags at
    all. It is the R/S/M ability's passive-effect *routine index* (FFTPatcher
    `OtherID` / FFHacktics `ID`), sequential 0–87 in vanilla and redundant with
    the ability's ordinal. An `int` routine-id is its faithful final shape —
    there is nothing to decode, and it has no place in gameplay reads.

Both therefore stay raw `int` and out of the AbilityView whitelist (see ADR-0013
"Deferred / resolved-raw sub-fields").

Gotcha this guard exists to survive: there is an unrelated per-unit GPU runtime
field ALSO named `anim_flags` (`U_ANIM_FLAGS`, written by the shader as
damage/projectile animation latches, surfaced in `SNAPSHOT_FIELDS`). It shares
the name by coincidence; a naive "no raw reader" grep can't tell the legitimate
`state.get("anim_flags")` from a banned ROM read. So this guard enforces the
*actual* boundary that keeps the ROM bytes out of display/gameplay instead:

  (1) `anim_flags` / `rsm_other_id` stay raw `int` in effects.json (not decoded
      to a dict/array behind the ADR's back — decoding is an RE outcome that must
      update the ADR + this guard together), and
  (2) neither field is in `generate_ability_database.py`'s `INCLUDED_FIELDS`
      whitelist, so neither can surface into `AbilityView` / gameplay reads.

When the RE lands and the fields are genuinely decoded, this guard is meant to
fail — that failure is the reminder to amend ADR-0013 and retire/rewrite it.
Exit 0 if the deferral holds, 1 on violation. Pure stdlib; no Godot needed.
"""
import ast
import json
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
EFFECTS_JSON = PROJECT_DIR / "assets/abilities/effects.json"
GENERATOR = PROJECT_DIR / "tools/generate_ability_database.py"

DEFERRED_FIELDS = ("anim_flags", "rsm_other_id")


def _load_effects() -> dict:
    with EFFECTS_JSON.open() as f:
        data = json.load(f)
    # effects.json is keyed by effect id -> record dict.
    if not isinstance(data, dict):
        raise SystemExit(f"unexpected effects.json shape: {type(data).__name__}")
    return data


def _included_fields() -> list:
    """Extract the INCLUDED_FIELDS list literal without importing the module."""
    tree = ast.parse(GENERATOR.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "INCLUDED_FIELDS":
                    return [ast.literal_eval(elt) for elt in node.value.elts]
    raise SystemExit("could not find INCLUDED_FIELDS in generate_ability_database.py")


def main() -> int:
    violations: list[str] = []

    # (1) The fields must stay raw int in every effects.json record that carries them.
    effects = _load_effects()
    for eid, record in effects.items():
        if not isinstance(record, dict):
            continue
        for field in DEFERRED_FIELDS:
            if field in record and not isinstance(record[field], int):
                violations.append(
                    f"effects.json[{eid}].{field} is {type(record[field]).__name__}, "
                    f"expected raw int (ADR-0013 deferral — decoding must amend the ADR)"
                )

    # (2) Neither field may surface into the generated AbilityView.
    included = _included_fields()
    for field in DEFERRED_FIELDS:
        if field in included:
            violations.append(
                f"'{field}' is in generate_ability_database.py INCLUDED_FIELDS — "
                f"ADR-0013 defers it (semantics not yet RE'd); it must not reach AbilityView"
            )

    if violations:
        print("ADR-0013 deferred-flags guard FAILED:")
        for v in violations:
            print(f"  - {v}")
        print(
            "\nIf you intentionally decoded these fields, that is an ADR change: "
            "update docs/adr/0013-*.md and this guard together."
        )
        return 1

    print(
        "ADR-0013 deferred-flags guard OK: anim_flags/rsm_other_id raw int in "
        "effects.json and absent from AbilityView whitelist."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
