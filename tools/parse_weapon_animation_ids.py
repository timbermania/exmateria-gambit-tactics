#!/usr/bin/env python3
"""
Parse the weapon_animation_ids table from BATTLE.BIN — the per-item-type
BODY-layer attack animation slot table that the FFT engine reads to pick
the attacker's swing/shoot/poke/etc. animation.

Table location: BATTLE.BIN file offset 0x2D364 (RAM 0x80094364, with
BATTLE_BIN_RAM_BASE = 0x80067000).

Structure: one 3-byte entry per item_type. The three bytes are the slot
index for HIGH / MID / LOW attack heights respectively, each divided by 2
(the in-game runtime multiplies by 2 and adds 1 for back-facing). Per
TacticsEngineG's notes ("3 bytes per entry, 1 entry per item type") and
the FFHacktics wiki BATTLE.BIN_Data_Tables reference, observed slots are
sequential — Swing High=128, Mid=130, Low=132 → bytes 64/65/66 — but the
parser decodes each byte independently in case any item type breaks the
sequential pattern.

We read item_types 0..19 (Unarmed through Shield — the basic weapon range
the game equips); thrown items (32-34) use a separate animation flow not
in this table.

Output JSON shape (string-keyed for JSON compatibility):
  {
    "0":  {"high": 122, "mid": 124, "low": 126, "name": "Unarmed"},
    "1":  {"high": 128, "mid": 130, "low": 132, "name": "Knife"},
    ...
  }

`addons/exmateria_sprite_rig/layers/WeaponAnimationSelector.gd` consumes this
for the humanoid BODY slot. (This line used to name `src/animation/AnimationAtlas.gd`
-- a file that has never existed in this tree, so nothing could ever have gone red
about it: the SILENTLY-DEAD reference #744 was sent to find. Repointed 2026-09-01.)
Re-run any
time BATTLE.BIN changes (it doesn't on patches — this is a one-shot for
PSX FFT, but the converter is idempotent).

Usage:
    uv run python tools/parse_weapon_animation_ids.py
    uv run python tools/parse_weapon_animation_ids.py /path/to/BATTLE.BIN
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from _repo_paths import battle_bin as _battle_bin
from _repo_paths import godot_root as _godot_root


WEAPON_ANIMATION_IDS_OFFSET = 0x2D364  # BATTLE.BIN file offset
ENTRY_SIZE = 3  # bytes per item_type entry: [high_idx, mid_idx, low_idx]
NUM_ENTRIES = 20  # item_types 0..19; covers all basic weapons + shield

# Item type names for the JSON output's `name` field — the 20 item-type
# ids the ROM enumerates here (0..19, weapons + Shield).
ITEM_TYPE_NAMES = {
    0:  "Unarmed",     1: "Knife",         2: "NinjaBlade",  3: "Sword",
    4:  "KnightSword", 5: "Katana",        6: "Axe",         7: "Rod",
    8:  "Staff",       9: "Flail",         10: "Gun",        11: "Crossbow",
    12: "Bow",         13: "Instrument",   14: "Book",       15: "Polearm",
    16: "Pole",        17: "Bag",          18: "Cloth",      19: "Shield",
}

DEFAULT_BATTLE_PATH = _battle_bin()
# 🔴 THE SILENT ONE (#744, 2026-09-01). This is an OUTPUT path with no `--check`
# arm and nothing in the pre-flight that runs the tool, so when the table moved into
# the addon nothing could go red: a re-run would have written a fresh JSON to the dead
# `assets/sprites/` address and the addon's committed copy would have drifted, quietly.
# `tools/check_tool_paths.py` arm 2 is the arm that can now say so.
DEFAULT_OUTPUT_PATH = _godot_root() / "addons" / "exmateria_sprite_rig" / "resources" / "weapon_animation_ids.json"


def parse(battle_bin_path: Path) -> dict[str, dict]:
    with open(battle_bin_path, "rb") as f:
        f.seek(WEAPON_ANIMATION_IDS_OFFSET)
        data = f.read(NUM_ENTRIES * ENTRY_SIZE)

    if len(data) < NUM_ENTRIES * ENTRY_SIZE:
        raise ValueError(
            f"BATTLE.BIN too short: read {len(data)} bytes at offset "
            f"0x{WEAPON_ANIMATION_IDS_OFFSET:X}, expected {NUM_ENTRIES * ENTRY_SIZE}"
        )

    out: dict[str, dict] = {}
    for item_type in range(NUM_ENTRIES):
        base = item_type * ENTRY_SIZE
        out[str(item_type)] = {
            "high": data[base + 0] * 2,
            "mid":  data[base + 1] * 2,
            "low":  data[base + 2] * 2,
            "name": ITEM_TYPE_NAMES.get(item_type, f"Unknown_{item_type}"),
        }
    return out


def main() -> int:
    if len(sys.argv) > 1:
        battle_bin_path = Path(sys.argv[1])
    else:
        battle_bin_path = DEFAULT_BATTLE_PATH

    if not battle_bin_path.exists():
        print(f"ERROR: BATTLE.BIN not found at {battle_bin_path}")
        return 1

    table = parse(battle_bin_path)

    DEFAULT_OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DEFAULT_OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(table, f, indent=2)
        f.write("\n")

    print(f"Wrote {DEFAULT_OUTPUT_PATH}")
    print(f"  source: {battle_bin_path}  (offset 0x{WEAPON_ANIMATION_IDS_OFFSET:X})")
    print(f"  entries: {len(table)}")
    for item_type, entry in table.items():
        print(f"    {int(item_type):3d}  {entry['name']:<14s}  high={entry['high']:3d}  mid={entry['mid']:3d}  low={entry['low']:3d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
