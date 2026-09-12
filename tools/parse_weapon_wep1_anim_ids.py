#!/usr/bin/env python3
"""Parse per-(item_type, height) WEP1 anim ids from TYPE1.SEQ.

The PSX engine drives the WEP1 layer for each weapon attack via a
`QueueSpriteAnim` opcode embedded in the TYPE1.SEQ slot that
`weapon_animation_ids.json` (BATTLE.BIN 0x2d364) points at. So the
ground truth for "which WEP1 slot does a Knife High swing play?" lives
in two places that must agree:

  1. `weapon_animation_ids.json[item_type].high` = TYPE1.SEQ BODY slot
  2. That slot's first `QueueSpriteAnim(layer=1, ...)` opcode's anim id

This tool walks (1), reads (2), and emits the joined table:

  weapon_wep1_anim_ids.json:
    {
      "1": {"high": 0, "mid": 2, "low": 4, "name": "Knife"},
      "10": {"high": 6, "mid": 8, "low": 10, "name": "Gun"},
      ...
    }

The WEP1 anim id stored is the FRONT-facing variant. The back-facing
variant is `front + 1` by WEP1.SEQ slot convention; callers add 1 at
paint time based on the camera quadrant.

This retires the hand-authored `WeaponAnimationSelector.CATEGORY_BASE` +
`HAS_HEIGHT_VARIANTS` + `get_category_from_item_type` chain. The
mapping is now ROM-derived end to end (input table is ROM, opcode
stream is ROM, output table is the join).

Item types NOT covered by this output (intentionally — they take a
different path through the runtime):
  - 0 (Unarmed): no WEP1 layer; the BODY pose holds the fist
  - 19 (Shield): no attack animation; SHIELD WEP1 slots fire from
    REACT BODY data, not from a forward selector lookup
  - 32-34 (Shuriken, Ball, ChemistItem): not in
    weapon_animation_ids.json — thrown items use a separate phase-
    structured animation flow (Start/Wait/Finish) not yet modeled
"""
import argparse
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
# moved into the addon by #744 alongside the output below; LOUD when run
# (`read_text()` raises) but nothing in the pre-flight runs this tool.
DEFAULT_BODY_TABLE = REPO_ROOT / "addons" / "exmateria_sprite_rig" / "resources" / "weapon_animation_ids.json"
DEFAULT_TYPE1_SEQ = REPO_ROOT / "assets" / "sprites" / "animations" / "type1_seq.json"
DEFAULT_OUTPUT = REPO_ROOT / "addons" / "exmateria_sprite_rig" / "resources" / "weapon_wep1_anim_ids.json"

WEP1_LAYER = 1  # ExMateriaSchema.SpriteLayer.Kind.WEP1 (ADR-0217 dec. 7)


def extract_first_wep1_anim(slot_ops: list) -> int | None:
    """Return the anim id of the first QueueSpriteAnim(layer=WEP1) op, or None."""
    for op in slot_ops:
        if op.get("op_code_name") != "QueueSpriteAnim":
            continue
        if op.get("op_code_param_0") != WEP1_LAYER:
            continue
        return int(op.get("op_code_param_1", 0))
    return None


def parse(body_table_path: Path, type1_seq_path: Path) -> dict:
    body_table = json.loads(body_table_path.read_text())
    type1_seq = json.loads(type1_seq_path.read_text())
    out = {}
    for type_id_str, entry in body_table.items():
        item_type_id = int(type_id_str)
        wep1_per_height = {}
        for height in ("high", "mid", "low"):
            body_slot = int(entry.get(height, 0))
            if body_slot == 0:
                continue  # no attack (e.g. Unarmed reads as 122/124/126 which DO have
                          # body slots but no WEP1 ops; Shield reads as 0/0/0 — both
                          # produce nothing here, which is correct).
            slot_ops = type1_seq.get(str(body_slot), [])
            anim_id = extract_first_wep1_anim(slot_ops)
            if anim_id is None:
                continue
            wep1_per_height[height] = anim_id
        if not wep1_per_height:
            continue  # skip Unarmed / Shield — no WEP1 layer
        wep1_per_height["name"] = entry.get("name", "?")
        out[type_id_str] = wep1_per_height
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--body-table", type=Path, default=DEFAULT_BODY_TABLE,
                    help="weapon_animation_ids.json (BATTLE.BIN 0x2d364 parsed)")
    ap.add_argument("--type1-seq", type=Path, default=DEFAULT_TYPE1_SEQ,
                    help="type1_seq.json (parsed TYPE1.SEQ)")
    ap.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT)
    args = ap.parse_args()
    out = parse(args.body_table, args.type1_seq)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        json.dump(out, f, indent="\t")
        f.write("\n")
    print(f"Wrote {args.output} ({len(out)} item_type entries)")


if __name__ == "__main__":
    main()
