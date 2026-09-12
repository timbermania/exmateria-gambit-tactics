#!/usr/bin/env python3
"""
DEPRECATED (2026-06-11): this reads DAT_800943c4 via FUN_800689a4, a
SEQ-animation sound path that does NOT fire for a basic attack (verified live
in PCSX). The real melee attack SFX is sprite -> sound-class s2 -> swing/hit/
block — see tools/parse_attack_sounds.py and
research/effect_sound/working_documents/BATTLE_SFX_ATTACK_SOUNDS.md. Kept for
reference only.

Parse the weapon attack-sound table from BATTLE.BIN — the per-weapon-type
byte table the FFT engine reads to pick the sound a unit plays during its
attack animation.

Table location: BATTLE.BIN file offset 0x2D3C4 (RAM 0x800943C4, with
BATTLE_BIN_RAM_BASE = 0x80067000). It is the immediate neighbour of the
weapon *motion* table at 0x2D364 (RAM 0x80094364, parsed by
parse_weapon_animation_ids.py) and is followed by a weapon palette/CLUT
table at 0x2D3E4 (RAM 0x800943E4) — so the sound table is exactly the 32
bytes 0x2D3C4..0x2D3E3.

Who reads it (battle decompilation, the SEQ sound-opcode handler
FUN_800689a4 @ ram:800689A4):

    sound = 0x10;                                 # default swing sound
    if (anim_id != 0x17e && (anim_id - 0x170) > 0x19)
        sound = (&DAT_800943C4)[ unit->weapon_type ];   # +0x13B, clamped 0..0x1F
    ...
    play_sound(sound, descriptor)                 # FUN_801ade7c

So the table is indexed by the unit's weapon-type byte (unit+0x13B), the
same index the adjacent motion table uses. It is consulted only when the
current animation id (unit+0x138) is *outside* the 0x170..0x189 "normal
swing" band; inside that band the handler uses the fixed default 0x10
(and anim_id 0x94 forces sound 6). The weapon-type byte is clamped to
0..0x1F with a fallback of 0x15 in the equip path (FUN_…+0x13B = bVar3),
which is why this table has 32 entries even though only item_types 0..19
are named weapons.

IMPORTANT — value semantics are NOT yet pinned: the raw byte is whatever
numbering FUN_801ade7c's first argument uses. We do NOT assume it equals a
{21} system-bank sound id. This parser extracts the raw bytes faithfully;
decoding raw byte -> concrete SFX is the follow-up (decode FUN_801ade7c /
FUN_800687e0, or instrument it live in PCSX-Redux).

Output JSON shape (string-keyed for JSON compatibility):
  {
    "_comment": "...provenance...",
    "table": {
      "0":  {"raw": 0,  "hex": "0x00", "name": "Unarmed"},
      "11": {"raw": 3,  "hex": "0x03", "name": "Crossbow"},
      "12": {"raw": 1,  "hex": "0x01", "name": "Bow"},
      ...
    }
  }

Usage:
    uv run python tools/parse_weapon_attack_sounds.py
    uv run python tools/parse_weapon_attack_sounds.py /path/to/BATTLE.BIN
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from _repo_paths import battle_bin as _battle_bin
from _repo_paths import godot_root as _godot_root


WEAPON_ATTACK_SOUNDS_OFFSET = 0x2D3C4  # BATTLE.BIN file offset (RAM 0x800943C4)
ENTRY_SIZE = 1   # one byte per weapon-type entry (the raw sound selector)
NUM_ENTRIES = 32  # weapon-type index is clamped 0..0x1F at unit+0x13B

# Names for the first 20 indices mirror the weapon *motion* table's
# item-type enumeration (parse_weapon_animation_ids.py). Indices 20..31 are
# reachable via the clamp/fallback (e.g. 0x15) but have no named weapon —
# left as Unknown_N until the index semantics are confirmed.
ITEM_TYPE_NAMES = {
    0:  "Unarmed",     1: "Knife",         2: "NinjaBlade",  3: "Sword",
    4:  "KnightSword", 5: "Katana",        6: "Axe",         7: "Rod",
    8:  "Staff",       9: "Flail",         10: "Gun",        11: "Crossbow",
    12: "Bow",         13: "Instrument",   14: "Book",       15: "Polearm",
    16: "Pole",        17: "Bag",          18: "Cloth",      19: "Shield",
}

_COMMENT = (
    "Weapon attack-sound table from BATTLE.BIN @ 0x2D3C4 (RAM 0x800943C4), "
    "32 x 1 byte, indexed by the unit weapon-type byte (unit+0x13B) — the "
    "neighbour of the weapon motion table at 0x2D364. Read by SEQ sound-opcode "
    "handler FUN_800689a4: used only when anim_id (unit+0x138) is outside the "
    "0x170..0x189 swing band, else the fixed default 0x10 is played (anim 0x94 "
    "-> 6). `raw` is the unmapped selector byte passed to FUN_801ade7c; it is "
    "NOT confirmed to be a {21} system-bank id — value semantics are TBD."
)

DEFAULT_BATTLE_PATH = _battle_bin()
DEFAULT_OUTPUT_PATH = _godot_root() / "assets" / "sprites" / "weapon_attack_sounds.json"


def parse(battle_bin_path: Path) -> dict[str, dict]:
    with open(battle_bin_path, "rb") as f:
        f.seek(WEAPON_ATTACK_SOUNDS_OFFSET)
        data = f.read(NUM_ENTRIES * ENTRY_SIZE)

    if len(data) < NUM_ENTRIES * ENTRY_SIZE:
        raise ValueError(
            f"BATTLE.BIN too short: read {len(data)} bytes at offset "
            f"0x{WEAPON_ATTACK_SOUNDS_OFFSET:X}, expected {NUM_ENTRIES * ENTRY_SIZE}"
        )

    out: dict[str, dict] = {}
    for idx in range(NUM_ENTRIES):
        raw = data[idx]
        out[str(idx)] = {
            "raw": raw,
            "hex": f"0x{raw:02X}",
            "name": ITEM_TYPE_NAMES.get(idx, f"Unknown_{idx}"),
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
        json.dump({"_comment": _COMMENT, "table": table}, f, indent=2)
        f.write("\n")

    print(f"Wrote {DEFAULT_OUTPUT_PATH}")
    print(f"  source: {battle_bin_path}  (offset 0x{WEAPON_ATTACK_SOUNDS_OFFSET:X})")
    print(f"  entries: {len(table)}")
    for idx, entry in table.items():
        flag = "  <-- nonzero" if entry["raw"] != 0 else ""
        print(f"    {int(idx):3d}  {entry['name']:<14s}  raw={entry['raw']:3d}  {entry['hex']}{flag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
