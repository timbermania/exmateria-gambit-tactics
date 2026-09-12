#!/usr/bin/env python3
"""
FFT ENTD Parser

Decodes the ENTD unit-deployment tables from `BATTLE/ENTD{1..4}.ENT`. Each
ENTD file holds 128 *records* (called "Events" in FFTPatcher), each record
holds 16 *slots*, each slot is a 40-byte unit template. A scenario's
`entd_idx` (from ATTACK.OUT — see `parse_scenarios.py`) names one such
record: the units to deploy when that scenario starts.

File layout (per FFTPatcher Datatypes/ENTD/ENTD.cs + EventUnit.cs):

    ENTD1.ENT  → records   0..127  (entd_idx 0x000..0x07F)
    ENTD2.ENT  → records 128..255  (entd_idx 0x080..0x0FF)
    ENTD3.ENT  → records 256..383  (entd_idx 0x100..0x17F)
    ENTD4.ENT  → records 384..511  (entd_idx 0x180..0x1FF)

    each file:    128 records  × 640 bytes = 81920 bytes
    each record:   16 slots    ×  40 bytes
    each slot:    EventUnit (see SLOT_LAYOUT below)

Outputs:
- assets/scenarios/entd.json: dict keyed by entd_idx (string), each value a
  record dict with the source file and a `slots` list of 16 flat slot dicts.
  Empty slots (sprite_set==0 and unit_id==0) are kept as-is so positional
  indices line up with FFTPatcher's UI.

Sanity check: scenario 1 → entd_idx 256 → ENTD3 record 0 → slot 0 is Princess
Ovelia (sprite_set=0x0C, female, unit_id=0x0C, position (8,4) facing East).

Usage:
    uv run python tools/parse_entd.py
    uv run python tools/parse_entd.py --extract /path/to/fft-extract
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass, asdict
from pathlib import Path

from _repo_paths import almanac_dir, fft_extract_root

ASSETS = Path(__file__).parent.parent / "assets"
DEFAULT_OUTPUT = ASSETS / "scenarios" / "entd.json"
SCENARIOS_JSON = almanac_dir("encounters/scenarios.json")   # ADR-0251 dec. 2
MAPS_DIR = ASSETS / "maps"

# =============================================================================
# Layout constants (authority: FFTPatcher Datatypes/ENTD/{ENTD,EventUnit}.cs)
# =============================================================================

RECORDS_PER_FILE = 0x80          # 128
SLOTS_PER_RECORD = 16
SLOT_STRIDE = 40
RECORD_STRIDE = SLOTS_PER_RECORD * SLOT_STRIDE  # 640
FILE_SIZE = RECORDS_PER_FILE * RECORD_STRIDE     # 81920

# Per-file entd_idx base (matches AllENTDs constructor in ENTD.cs).
FILES: list[tuple[int, str]] = [
    (0x000, "ENTD1.ENT"),
    (0x080, "ENTD2.ENT"),
    (0x100, "ENTD3.ENT"),
    (0x180, "ENTD4.ENT"),
]

# Bit decoding lives in the parser (see godot-learning/CLAUDE.md "Wrong bit
# order"): FFT packs flag bytes MSB-first. List index 0 corresponds to bit 7.
FLAGS1_NAMES = [
    "male", "female", "monster", "join_after_event",
    "load_formation", "zodiac_monster", "blank2", "save_formation",
]
# Flags2 (byte 24): two of the bits (5,4) are the team_color, the rest are
# real booleans. FFTPatcher CopyByteToBooleans passes dummy refs for those two
# slots, then derives team_color = (b & 0x30) >> 4. We mirror that here.
FLAGS2_NAMES = [
    "always_present", "randomly_present", None, None,
    "control", "immortal", "blank6", "blank7",
]
AI_FLAGS1_NAMES = [
    "blank8", "focus_unit", "stay_near_xy", "aggressive",
    "defensive", "blank9", "blank10", "blank11",
]
AI_FLAGS2_NAMES = [
    "blank12", "blank13", "blank14", "blank15",
    "blank16", "save_ct", "blank17", "blank18",
]

# byte[8] PreRequisiteJob enum (EventUnit.cs PreRequisiteJob). 0xA9 = unknown.
PREREQ_JOB_NAMES = {
    0x00: "Base", 0x01: "Chemist", 0x02: "Knight", 0x03: "Archer",
    0x04: "Monk", 0x05: "Priest", 0x06: "Wizard", 0x07: "TimeMage",
    0x08: "Summoner", 0x09: "Thief", 0x0A: "Mediator", 0x0B: "Oracle",
    0x0C: "Geomancer", 0x0D: "Lancer", 0x0E: "Samurai", 0x0F: "Ninja",
    0x10: "Calculator", 0x11: "Bard", 0x12: "Dancer", 0x13: "Mime",
    0xA9: "Unknown",
}

# byte[27] low 7 bits = Facing (EventUnit.cs Facing enum).
FACING_NAMES = {0: "South", 1: "West", 2: "North", 3: "East"}


# ADR-0052's 180°-about-X parse-time rotation flips PSX-derived *placements*
# (the depth tile `y` below), but NOT *facings*. Facing is a POSE, rendered
# relative to the camera — and per ADR-0052 the camera body and mesh mirror
# together at parse time, so the relative look-direction is preserved and the
# camera yaw needs no change. A unit's facing angle rides that same co-mirrored
# camera, so it is consumed raw too — exactly like the Camera opcode the ADR
# already carves out ("a pose, not a tile placement… consumed raw"). The runtime
# lifts the raw 2-bit facing to a 12-bit world angle with `Facing << 10`
# (`PsxNum.warp_facing_to_12bit`) and renders it directly.
#
# A prior revision applied a `0↔2` (South↔North) facing swap here. It was
# spurious — and invisible for two years — because every chapel-cast unit
# (the only side-by-side calibration reference) carries ENTD facing = 3 (East),
# which a `0↔2` swap leaves untouched. Scenario 4 ("Orbonne Battle") is the
# first scene with facing-0/2 units, and it rendered them 180° wrong: enemies
# faced East not West, Agrias West not East. Dropping the swap fixes them and
# leaves chapel (all facing 3) byte-identical.
def apply_chirality_fix_to_slot(slot: dict, size_z_tiles: int) -> dict:
    """In-place ADR-0052 fix on a parsed slot dict: renumber ONLY the depth-axis
    tile (y). Facing is a pose, consumed raw (see the note above), so it is left
    untouched. Unused slots (unit_id == 0xFF) are left entirely untouched."""
    if slot.get("unit_id") == 0xFF:
        return slot
    slot["y"] = size_z_tiles - 1 - slot["y"]
    return slot

# byte[24] bits 5..4 (mask 0x30) shifted >> 4 = TeamColor.
TEAM_COLOR_NAMES = {0: "Blue", 1: "Red", 2: "Green", 3: "LightBlue"}


def _decode_msb_flags(byte: int, names: list[str | None]) -> dict[str, bool]:
    """Decode an FFT flag byte. names[0] -> bit 7, names[7] -> bit 0. Skips
    name entries set to None (used for the team_color slots in flags2)."""
    out: dict[str, bool] = {}
    for i, name in enumerate(names):
        if name is None:
            continue
        out[name] = bool((byte >> (7 - i)) & 1)
    return out


@dataclass
class Slot:
    """One 40-byte EventUnit. Field order mirrors FFTPatcher EventUnit.cs."""

    # raw byte indices in parens — see EventUnit.cs ctor for authority
    sprite_set: int               # (0)
    flags1: int                   # (1) raw
    special_name: int             # (2)
    level: int                    # (3)
    month: int                    # (4)
    day: int                      # (5)
    bravery: int                  # (6)
    faith: int                    # (7)
    prereq_job: int               # (8) raw enum byte
    prereq_job_name: str          # (8) decoded
    prereq_job_level: int         # (9)
    job: int                      # (10)
    secondary_action: int         # (11) SkillSet id
    reaction: int                 # (12-13) u16 ability id
    support: int                  # (14-15) u16 ability id
    movement: int                 # (16-17) u16 ability id
    head: int                     # (18)
    body: int                     # (19)
    accessory: int                # (20)
    right_hand: int               # (21)
    left_hand: int                # (22)
    palette: int                  # (23)
    flags2: int                   # (24) raw
    team_color: int               # (24) bits 5..4 (mask 0x30) >> 4
    team_color_name: str          # (24) decoded
    x: int                        # (25)
    y: int                        # (26)
    facing_raw: int               # (27) full byte
    facing: int                   # (27) low 7 bits
    facing_name: str              # (27) decoded
    upper_level: bool             # (27) bit 7
    experience: int               # (28)
    skill_set: int                # (29)
    war_trophy: int               # (30)
    bonus_money: int              # (31)
    unit_id: int                  # (32)
    target_x: int                 # (33)
    target_y: int                 # (34)
    ai_flags1: int                # (35) raw
    target: int                   # (36)
    unknown_10: int               # (37)
    ai_flags2: int                # (38) raw
    unknown_12: int               # (39)
    # decoded flag bundles (flat names: male, female, …); included alongside the
    # raw bytes so consumers can read either form
    flags1_decoded: dict[str, bool]
    flags2_decoded: dict[str, bool]
    ai_flags1_decoded: dict[str, bool]
    ai_flags2_decoded: dict[str, bool]


def parse_slot(buf: bytes) -> Slot:
    assert len(buf) == SLOT_STRIDE, f"bad slot length {len(buf)}"
    u8 = buf.__getitem__
    u16 = lambda o: struct.unpack_from("<H", buf, o)[0]

    prereq = u8(8)
    flags2 = u8(24)
    team_color = (flags2 & 0x30) >> 4
    facing_raw = u8(27)
    facing = facing_raw & 0x7F

    return Slot(
        sprite_set=u8(0),
        flags1=u8(1),
        special_name=u8(2),
        level=u8(3),
        month=u8(4),
        day=u8(5),
        bravery=u8(6),
        faith=u8(7),
        prereq_job=prereq,
        prereq_job_name=PREREQ_JOB_NAMES.get(prereq, f"Unknown_0x{prereq:02X}"),
        prereq_job_level=u8(9),
        job=u8(10),
        secondary_action=u8(11),
        reaction=u16(12),
        support=u16(14),
        movement=u16(16),
        head=u8(18),
        body=u8(19),
        accessory=u8(20),
        right_hand=u8(21),
        left_hand=u8(22),
        palette=u8(23),
        flags2=flags2,
        team_color=team_color,
        team_color_name=TEAM_COLOR_NAMES.get(team_color, f"Unknown_{team_color}"),
        x=u8(25),
        y=u8(26),
        facing_raw=facing_raw,
        facing=facing,
        facing_name=FACING_NAMES.get(facing, f"Unknown_0x{facing:02X}"),
        upper_level=bool(facing_raw & 0x80),
        experience=u8(28),
        skill_set=u8(29),
        war_trophy=u8(30),
        bonus_money=u8(31),
        unit_id=u8(32),
        target_x=u8(33),
        target_y=u8(34),
        ai_flags1=u8(35),
        target=u8(36),
        unknown_10=u8(37),
        ai_flags2=u8(38),
        unknown_12=u8(39),
        flags1_decoded=_decode_msb_flags(u8(1), FLAGS1_NAMES),
        flags2_decoded=_decode_msb_flags(flags2, FLAGS2_NAMES),
        ai_flags1_decoded=_decode_msb_flags(u8(35), AI_FLAGS1_NAMES),
        ai_flags2_decoded=_decode_msb_flags(u8(38), AI_FLAGS2_NAMES),
    )


def parse_record(buf: bytes) -> list[Slot]:
    assert len(buf) == RECORD_STRIDE, f"bad record length {len(buf)}"
    return [
        parse_slot(buf[i * SLOT_STRIDE:(i + 1) * SLOT_STRIDE])
        for i in range(SLOTS_PER_RECORD)
    ]


def parse_entd_file(path: Path) -> list[list[Slot]]:
    data = path.read_bytes()
    if len(data) != FILE_SIZE:
        raise SystemExit(
            f"{path.name} wrong size: {len(data)} bytes, expected {FILE_SIZE}"
        )
    return [
        parse_record(data[i * RECORD_STRIDE:(i + 1) * RECORD_STRIDE])
        for i in range(RECORDS_PER_FILE)
    ]


def parse_all(battle_dir: Path) -> dict[int, dict]:
    """Returns a dict keyed by entd_idx (int 0..511) → record dict."""
    out: dict[int, dict] = {}
    for base, name in FILES:
        path = battle_dir / name
        if not path.exists():
            raise SystemExit(f"ENTD file missing: {path}")
        records = parse_entd_file(path)
        for i, slots in enumerate(records):
            out[base + i] = {
                "file": name,
                "record_in_file": i,
                "slots": [asdict(s) for s in slots],
            }
    return out


def _load_entd_to_map() -> dict[int, int]:
    """entd_idx → map_id from scenarios.json. For the one entd_idx that
    routes to multiple maps (entd_idx=0, the empty/unused record), the first
    map wins; the slots are all 0xFF so chirality fix is a no-op anyway."""
    if not SCENARIOS_JSON.exists():
        return {}
    data = json.loads(SCENARIOS_JSON.read_text())
    out: dict[int, int] = {}
    for s in data.get("scenarios", {}).values():
        out.setdefault(int(s["entd_idx"]), int(s["map_id"]))
    return out


def _load_size_z_for_map(map_id: int) -> int | None:
    """terrain.json size_z (in tiles) for `MAP{map_id:03d}`, or None if the
    map hasn't been parsed yet."""
    p = MAPS_DIR / f"MAP{map_id:03d}" / "terrain.json"
    if not p.exists():
        return None
    return int(json.loads(p.read_text())["terrain"]["size_z"])


def main() -> None:
    ap = argparse.ArgumentParser(description="Parse FFT ENTD unit-deployment tables")
    ap.add_argument("--extract", type=Path, default=None,
                    help="path to fft-extract root (default: project-assets/fft-extract)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUTPUT,
                    help="output JSON path")
    args = ap.parse_args()

    battle_dir = fft_extract_root(args.extract) / "BATTLE"
    if not battle_dir.is_dir():
        raise SystemExit(f"BATTLE/ dir not found: {battle_dir}")

    records = parse_all(battle_dir)

    # ADR-0052 chirality fix: renumber y + remap facing per slot. Looks up
    # size_z via scenarios.json → terrain.json. Records with no associated
    # scenario or with the map unparsed get left raw (logged for visibility).
    entd_to_map = _load_entd_to_map()
    missing_maps: list[int] = []
    for entd_idx, rec in records.items():
        map_id = entd_to_map.get(entd_idx)
        if map_id is None:
            continue
        size_z = _load_size_z_for_map(map_id)
        if size_z is None:
            missing_maps.append(map_id)
            continue
        for slot in rec["slots"]:
            apply_chirality_fix_to_slot(slot, size_z)

    payload = {
        "_source": "BATTLE/ENTD{1..4}.ENT (FFT unit-deployment tables)",
        "_layout": {
            "files": [name for _, name in FILES],
            "records_per_file": RECORDS_PER_FILE,
            "slots_per_record": SLOTS_PER_RECORD,
            "slot_stride": SLOT_STRIDE,
        },
        # JSON keys must be strings; consumers re-cast to int as needed.
        "records": {str(k): v for k, v in sorted(records.items())},
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent="\t") + "\n")

    # "Used" slot heuristic: FFT writes 0xFF to unit_id in unused slots
    # (verified against ENTD3 record 0 — Ovelia's record has 10 used slots
    # then 6 with unit_id=0xFF).
    used = sum(
        1 for rec in records.values() for slot in rec["slots"]
        if slot["unit_id"] != 0xFF
    )
    print(f"Parsed {len(records)} records × {SLOTS_PER_RECORD} slots from {battle_dir}")
    print(f"  used slots (unit_id != 0xFF): {used}")
    if missing_maps:
        unique = sorted(set(missing_maps))
        print(f"  WARN: {len(unique)} maps unparsed, chirality fix skipped for "
              f"their records: MAP{unique[0]:03d}..MAP{unique[-1]:03d}")
    print(f"  -> {args.out}")


if __name__ == "__main__":
    main()
