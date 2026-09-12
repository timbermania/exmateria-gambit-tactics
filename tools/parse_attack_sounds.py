#!/usr/bin/env python3
"""
Parse the battle attack-SFX mapping: unit sprite/job -> sound-class -> the
global-SFX-bank sounds for its swing / hit / block, paired with the wiki
semantic names from sfx_bank_names.json.

This is the *correct* melee attack-sound path, reverse-engineered + verified
live in PCSX (see research/effect_sound/working_documents/BATTLE_SFX_ATTACK_SOUNDS.md).
It SUPERSEDES parse_weapon_attack_sounds.py, which reads DAT_800943c4 (the
FUN_800689a4 weapon-type table) — a SEQ-animation path that does NOT fire for
a basic attack.

Chain (all confirmed):
  sprite_id (unit+0x1ab)
     --> sound-class s2   = SCUS_942.21 @ RAM 0x80062eb8, stride 0xC, byte +5
                            (clamped <0x20 by the engine)
  dispatcher FUN_80082620 picks a table by phase + action-entry type:
     swing  = DAT_80093d40[s2]   (BATTLE.BIN file 0x2CD40)   ; phase-0 windup
     hit    = DAT_80093d60[s2]   (BATTLE.BIN file 0x2CD60)   ; impact (cases 9/c)
     block  = DAT_80093d80[s2]   (BATTLE.BIN file 0x2CD80)   ; block/alt (cases 2/3/a)
     (+ hardcoded 0x30 "Blade Grasp", conditional 0x72 "Cinematic Impaling Hit")
  each value is a SYSTEM-bank sound id -> sfx_bank_names.json gives its meaning.

Verified: knight sprite 0x13 -> s2 3 -> swing 0x1A "Medium Weapon Swing",
hit 0x13 "Slash", block 0x2E "Shield Block Light".

Usage:
    uv run python tools/parse_attack_sounds.py
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

from _repo_paths import assets_dir, battle_bin, fft_extract_root, godot_root

# sprite_id -> sound-class s2 : SCUS_942.21, RAM 0x80062eb8, stride 0xC, byte +5
SOUNDCLASS_RAM = 0x80062EB8
SOUNDCLASS_STRIDE = 0xC
SOUNDCLASS_FIELD = 5
PSX_EXE_HEADER = 0x800  # PS-X EXE header precedes the loaded image

# s2 -> sound id : three tables in BATTLE.BIN (RAM base 0x80067000), 0x20 bytes
BATTLE_RAM_BASE = 0x80067000
SWING_TABLE_RAM = 0x80093D40  # phase-0 swing windup
HIT_TABLE_RAM = 0x80093D60    # impact
BLOCK_TABLE_RAM = 0x80093D80  # block / alt
TABLE_LEN = 0x20

NUM_SPRITES = 0xA0  # jobs + monsters; trailing/unused ids read as class 0

DEFAULT_OUTPUT = godot_root() / "assets" / "audio" / "sfx_banks" / "attack_sounds.json"


def _scus_file_offset(scus: bytes, ram: int) -> int:
    t_addr = struct.unpack_from("<I", scus, 0x18)[0]  # PS-X EXE t_addr
    return PSX_EXE_HEADER + (ram - t_addr)


def _load_catalog() -> dict[int, dict]:
    p = assets_dir("audio/sfx_banks/sfx_bank_names.json")
    system = json.loads(Path(p).read_text())["system"]
    return {int(k): v for k, v in system.items()}


def parse() -> dict:
    scus = (fft_extract_root() / "SCUS_942.21").read_bytes()
    battle = battle_bin().read_bytes()
    catalog = _load_catalog()

    def entry(idx: int) -> dict:
        meta = catalog.get(idx, {})
        return {
            "id": idx,
            "hex": f"0x{idx:02X}",
            "name": meta.get("name"),
            "slug": meta.get("slug"),
        }

    swing = battle[SWING_TABLE_RAM - BATTLE_RAM_BASE:][:TABLE_LEN]
    hit = battle[HIT_TABLE_RAM - BATTLE_RAM_BASE:][:TABLE_LEN]
    block = battle[BLOCK_TABLE_RAM - BATTLE_RAM_BASE:][:TABLE_LEN]

    # Compact authoritative form: one row per sound-class.
    by_class = {
        str(s2): {"swing": entry(swing[s2]), "hit": entry(hit[s2]), "block": entry(block[s2])}
        for s2 in range(TABLE_LEN)
    }

    # Expanded: every WEAPON GRAPHIC -> its class -> its sounds.
    #
    # CORRECTION (verified live in PCSX 2026-06-11): the dispatcher's index
    # `unit+0x1ab` is the EQUIPPED WEAPON's `graphic` id, NOT the unit sprite.
    # The 0x80062eb8 table is a weapon-graphic -> sound-class map. Ground truth:
    # a Ninja's Dagger (graphic 1) and Mythril Knife (graphic 2) each fed their
    # own graphic in as the key -> both class 1; a Rune Blade (graphic 0x13) ->
    # class 3. So the basic-attack sound follows the WEAPON, not the sprite/job.
    so = _scus_file_offset(scus, SOUNDCLASS_RAM)
    by_weapon_graphic = {}
    for graphic in range(NUM_SPRITES):
        s2 = scus[so + graphic * SOUNDCLASS_STRIDE + SOUNDCLASS_FIELD]
        if s2 >= TABLE_LEN:
            s2 = 1  # engine clamp
        by_weapon_graphic[str(graphic)] = {"sound_class": s2, **by_class[str(s2)]}

    return {
        "_comment": (
            "Battle basic-attack SFX, keyed by EQUIPPED WEAPON GRAPHIC. "
            "weapon graphic (unit+0x1ab) -> sound_class s2 (SCUS_942.21 @ 0x80062eb8 "
            "+5, stride 0xC) -> swing/hit/block sound ids (BATTLE.BIN tables "
            "0x2CD40/0x2CD60/0x2CD80), paired with system-bank names from "
            "sfx_bank_names.json. Dispatcher FUN_80082620; verified live in PCSX "
            "(Dagger graphic 1 / Mythril Knife graphic 2 -> class 1; Rune Blade "
            "graphic 0x13 -> class 3 Medium Weapon Swing/Slash). The sound follows "
            "the WEAPON, not the unit sprite. graphic comes from items.json `graphic`. "
            "Specials: 0x30 Blade Grasp (hardcoded), 0x72 Cinematic Impaling Hit "
            "(conditional). See research/effect_sound/working_documents/BATTLE_SFX_ATTACK_SOUNDS.md."
        ),
        "specials": {"blade_grasp": entry(0x30), "cinematic_impaling_hit": entry(0x72)},
        "by_sound_class": by_class,
        "by_weapon_graphic": by_weapon_graphic,
    }


def main() -> int:
    data = parse()
    DEFAULT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_OUTPUT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {DEFAULT_OUTPUT}")

    bc = data["by_sound_class"]
    print(f"  sound classes: {len(bc)}  (only the low ones are populated)")
    print("  per-class swing / hit / block:")
    for s2, row in bc.items():
        used = row["swing"]["name"] or row["hit"]["name"] or row["block"]["name"]
        if not used:
            continue
        print(f"    class {int(s2):2d}: "
              f"swing {row['swing']['hex']} {row['swing']['name']!s:<22} | "
              f"hit {row['hit']['hex']} {row['hit']['name']!s:<22} | "
              f"block {row['block']['hex']} {row['block']['name']}")

    # distinct sounds we map through this path
    ids = set()
    for row in bc.values():
        for k in ("swing", "hit", "block"):
            if row[k]["name"]:
                ids.add(row[k]["id"])
    ids.update({0x30, 0x72})
    print(f"  distinct system-bank sounds reached by the attack path: {len(ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
