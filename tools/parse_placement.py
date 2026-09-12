#!/usr/bin/env python3
"""
FFT Strategy-phase placement parser.

Emits the two scenario-sourced placement tables the strategy phase consumes
(ADR-0043), as committed extracted artifacts (the ADR-0013 boundary —
pure-derived, reproducible, never hand-maintained):

  - deployment_zones.json : the deployment-zone table (ATTACK.OUT 0xBBD4, 768 x
    12-byte records). Each record is a u32 5x5 footprint bitmap + center (x, y)
    + facing nibbles + max_squad_size, decoded to a set of real tile coords. A
    scenario's first_squad_deployment_idx / second_squad_deployment_idx point
    here. These are the player's deployment START tiles. Keyed by deployment_idx.

  - entd_positions.json : enemy START positions from the ENTD unit-deployment
    table (BATTLE/ENTD{1..4}.ENT, flat entd_idx 0..511). Per record, the
    positions of the non-player-controlled units. Keyed by entd_idx.

The runtime joins both to a scenario via the indices already carried in
scenarios.json (first_squad_deployment_idx / second_squad_deployment_idx /
entd_idx).

Layout authority: ffhacktics.com/wiki/ATTACK.OUT + /wiki/ENTD, cross-checked
against TacticsTemplateG (attack_out_data.gd, fft_entd.gd, fft_entd_unit.gd).
NOTE: TacticsTemplateG's deployment bitmap loop reads `idx**2` where the format
means `1 << idx` — this parser fixes that (see decode_deployment_zone).

Usage:
    uv run python tools/parse_placement.py
    uv run python tools/parse_placement.py --attack-out /path/to/ATTACK.OUT \
        --battle-dir /path/to/BATTLE
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass, field
from pathlib import Path

import _repo_paths as rp

ASSETS = Path(__file__).parent.parent / "assets"
DEFAULT_OUTPUT_DIR = rp.almanac_dir("encounters")   # ADR-0251 dec. 2
MAPS_DIR = ASSETS / "maps"

# =============================================================================
# Deployment-zone table (ATTACK.OUT 0xBBD4)
# =============================================================================

DEPLOY_OFFSET = 0xBBD4   # file offset of the first deployment-zone record
DEPLOY_COUNT = 0x300     # 768 records
DEPLOY_STRIDE = 12       # bytes per record


def rotate_quarter(x: int, y: int, k: int) -> tuple[int, int]:
    """Rotate (x, y) by k * 90 degrees, matching Godot's
    Vector2.rotated(k*PI/2).round() for integer coordinates.

    Godot: rotated(t) = (x*cos t - y*sin t, x*sin t + y*cos t). For the four
    quarter turns this is exact integer arithmetic (no rounding needed):
        k=0: ( x,  y)
        k=1: (-y,  x)
        k=2: (-x, -y)
        k=3: ( y, -x)
    """
    k &= 0x03
    if k == 0:
        return (x, y)
    if k == 1:
        return (-y, x)
    if k == 2:
        return (-x, -y)
    return (y, -x)


# The deployment record's facing byte (0x07) -> the 12-bit world facing angle the
# placed squad starts on, in the wheel the runtime renders (0x000=East/+Z,
# 0x400=South/-X, 0x800=West/-Z, 0xC00=North/+X — the inverse of
# `AnimationStateController.angle_12bit_to_facing`).
#
# BOTH NIBBLES, NOT ONE. The byte holds `unit_facing` (high) and `zone_facing`
# (low), and the engine ADDS them: at ATTACK.OUT overlay 0x801C5580 (file 0x65580,
# the routine that walks the 5x5 placement grid into per-unit deploy records) —
#
#     lbu  v0,7(rec)          ; the facing byte
#     andi v1,v0,0xf          ; zone_facing
#     addiu v1,v1,-1          ; ... - 1
#     srl  v0,v0,4            ; unit_facing
#     addu v1,v1,v0           ; R = zone_facing + unit_facing - 1
#     bgez/addiu v1,v1,4 ; andi v1,v1,3      ; R &= 3
#
# R then selects one of four unrolled copies of the placement loop, and each copy
# ORs a HARD-CODED 2-bit facing into the deploy record's byte 3 (bits 1..0) —
# R=0 -> 0 (`andi 0xe0`, 0x801C5654), R=1 -> 3 (`ori 3`, 0x801C5734), R=2 -> 2
# (`ori 2`, 0x801C5818), R=3 -> 1 (`ori 1`, 0x801C58F8). That table is exactly
# `(-R) & 3`: the four copies rotate the grid by +R quarters, so the pose inside it
# rotates by -R (the same frame-vs-vector sign `rotate_quarter` already carries —
# rotate_quarter(k) == an angle step of -k*0x400).
#
#     facing_code = (1 - unit_facing - zone_facing) & 3     angle = code << 10
#
# CONVENTION + CHIRALITY (unchanged): facing is an Orientation *pose*, consumed raw
# and NOT chirality-flipped, exactly like the ENTD facing. ADR-0052's 180°-about-X
# parse-time flip renumbers the depth axis of *placements* (the tiles, above), but
# the camera body + mesh co-mirror, so a pose rides that mirror unchanged.
#
# Cross-checked against the shipping battles by `tools/score_deploy_facing.py`, which
# scores this rule, its mirror, and the `unit_facing`-alone table it replaces against
# "the squad should face the Red ENTD centroid" over every (zone, ENTD) pair the game
# ships. RUN THE SCORER, don't quote a number from here: its verdict moves with the
# artifacts. The old table was calibrated on Gariland (zone 256) and is right for every
# zone_facing==3 zone and wrong for the rest, which is why one battle validated it.
# Gariland still lifts to 0x000 East; Mandalia Plains (zone 257, zone_facing=2,
# unit_facing=1) moves from 0x400 (-X, sideways past the enemy) to 0x800 (-Z, at them).
def start_facing_12bit(unit_facing: int, zone_facing: int) -> int:
    """The 12-bit world angle a squad deployed on this zone starts facing.

    Takes BOTH nibbles of the record's byte 0x07 because the engine adds them —
    see the ROM derivation above. Named for what it returns (the zone's absolute
    start facing), not for either nibble it reads."""
    return ((1 - (unit_facing & 0x03) - (zone_facing & 0x03)) & 0x03) << 10


@dataclass
class DeploymentZone:
    """One decoded deployment-zone record (12 bytes). `tiles` are real map
    coordinates the player may start units on."""

    deployment_idx: int
    center_x: int
    center_y: int
    zone_facing: int      # 0=West 1=South 2=East 3=North (rotation of the zone)
    unit_facing: int      # the squad's start facing, RELATIVE to the zone: absolute
                          # only once composed with zone_facing, as
                          # `start_facing_12bit` does (see the derivation above)
    max_squad_size: int
    map_id: int
    tiles: list[tuple[int, int]] = field(default_factory=list)


def decode_deployment_zone(rec: bytes, idx: int) -> DeploymentZone:
    """Decode one 12-byte deployment-zone record into real tile coordinates.

    Footprint bitmap is a 5x5 grid (0x01ffffff = full). For each set bit i, the
    base offset is (i%5 - 2, i//5 - 2) centred on the 5x5; rotate by
    zone_facing*90 degrees, then translate by the record's center (x, y).
    """
    assert len(rec) == DEPLOY_STRIDE, f"bad deployment record length {len(rec)}"
    bitmap = struct.unpack_from("<I", rec, 0)[0]
    center_x = rec[4]
    center_y = rec[5]
    facing_byte = rec[7]
    unit_facing = (facing_byte & 0xF0) >> 4
    zone_facing = facing_byte & 0x0F
    max_squad_size = rec[8]
    map_id = rec[9]

    tiles: list[tuple[int, int]] = []
    for i in range(25):
        if bitmap & (1 << i):                      # <-- 1<<i, NOT i**2
            base_x = (i % 5) - 2
            base_y = (i // 5) - 2
            rx, ry = rotate_quarter(base_x, base_y, zone_facing)
            tiles.append((rx + center_x, ry + center_y))

    return DeploymentZone(
        deployment_idx=idx,
        center_x=center_x,
        center_y=center_y,
        zone_facing=zone_facing,
        unit_facing=unit_facing,
        max_squad_size=max_squad_size,
        map_id=map_id,
        tiles=tiles,
    )


# A deployment tile is a "Placement" quantity (ADR-0057): it names a square the
# player's owned units start on, in the same map grid the ENTD enemy positions
# use. So it gets the identical ADR-0052 chirality fix the ENTD parser applies —
# the 180°-about-X rotation that, on the depth axis, renumbers `y -> size_z-1-y`.
# Without it the owned units deploy on the MIRROR side of the map (the enemies,
# already flipped in entd.json, land right; only the friendlies are wrong).
#
# center_y is the zone's depth-axis centre, so it's flipped too, keeping the
# center metadata consistent with the tiles it summarises. center_x (the width
# axis) is untouched — a single Y-negate reflects chirality (ADR-0052). Facing
# (zone_facing / unit_facing) is an Orientation pose, consumed raw, never
# chirality-flipped — mirroring `parse_entd.apply_chirality_fix_to_slot`.
def apply_chirality_fix_to_zone(zone: DeploymentZone, size_z_tiles: int) -> DeploymentZone:
    """In-place ADR-0052 depth flip on a decoded zone: renumber the depth-axis
    (y) of every tile and of center_y. x and facing are left untouched."""
    zone.tiles = [(x, size_z_tiles - 1 - y) for (x, y) in zone.tiles]
    zone.center_y = size_z_tiles - 1 - zone.center_y
    return zone


def _load_size_z_for_map(map_id: int) -> int | None:
    """terrain.json size_z (in tiles) for `MAP{map_id:03d}`, or None if the map
    hasn't been parsed yet. Mirrors parse_entd._load_size_z_for_map."""
    path = MAPS_DIR / f"MAP{map_id:03d}" / "terrain.json"
    if not path.exists():
        return None
    return int(json.loads(path.read_text())["terrain"]["size_z"])


def parse_all_deployment_zones(attack_out: bytes) -> list[DeploymentZone]:
    """Decode every deployment record that has at least one footprint tile.

    Empty records (bitmap == 0, including the idx-0 'no zone' sentinel) are
    dropped — a scenario with first_squad_deployment_idx == 0 falls back to the
    procedural generator (ADR-0043), so it never needs a row here.
    """
    end = DEPLOY_OFFSET + DEPLOY_COUNT * DEPLOY_STRIDE
    if len(attack_out) < end:
        raise SystemExit(
            f"ATTACK.OUT too small: {len(attack_out)} bytes, need >= {end}"
        )
    zones: list[DeploymentZone] = []
    for i in range(DEPLOY_COUNT):
        start = DEPLOY_OFFSET + i * DEPLOY_STRIDE
        zone = decode_deployment_zone(attack_out[start:start + DEPLOY_STRIDE], i)
        if zone.tiles:
            zones.append(zone)
    return zones


# =============================================================================
# ENTD unit-deployment table (BATTLE/ENTD{1..4}.ENT)
# =============================================================================

ENTD_FILES = 4
ENTD_RECORDS_PER_FILE = 128     # 81920 bytes / 640 bytes-per-record
ENTD_RECORD_STRIDE = 640        # 16 units * 40 bytes
ENTD_UNIT_STRIDE = 40
ENTD_UNITS_PER_RECORD = 16


def entd_file_and_record(entd_idx: int) -> tuple[int, int]:
    """Resolve a flat entd_idx (0..511) to a 1-based file number (ENTD1..4) and
    the record index within that file."""
    return (entd_idx // ENTD_RECORDS_PER_FILE) + 1, \
        entd_idx % ENTD_RECORDS_PER_FILE


@dataclass
class EntdEnemy:
    """A single non-player-controlled unit's START position."""

    x: int
    y: int
    upper_level: int
    facing: int          # initial_direction: 0=South 1=East 2=North 3=West
    team_color: int      # 0=blue 1=red 2=green 3=light-blue


@dataclass
class EntdRecord:
    """The enemy START positions of one ENTD record."""

    entd_idx: int
    enemies: list[EntdEnemy] = field(default_factory=list)


def decode_entd_record(rec: bytes, idx: int) -> EntdRecord:
    """Decode one 640-byte ENTD record, keeping only non-player-controlled
    units' positions (empty slots — sprite byte 0 — are skipped)."""
    assert len(rec) == ENTD_RECORD_STRIDE, f"bad ENTD record length {len(rec)}"
    enemies: list[EntdEnemy] = []
    for slot in range(ENTD_UNITS_PER_RECORD):
        base = slot * ENTD_UNIT_STRIDE
        unit = rec[base:base + ENTD_UNIT_STRIDE]
        if unit[0] == 0:                       # empty slot
            continue
        flags2 = unit[0x18]
        is_player_controlled = bool(flags2 & 0x08)
        if is_player_controlled:               # player/guest — not an enemy tile
            continue
        flags3 = unit[0x1B]
        enemies.append(EntdEnemy(
            x=unit[0x19],
            y=unit[0x1A],
            upper_level=(flags3 & 0x80) >> 7,
            facing=flags3 & 0x03,
            team_color=(flags2 & 0x30) >> 4,
        ))
    return EntdRecord(entd_idx=idx, enemies=enemies)


def parse_all_entds(battle_dir: Path) -> list[EntdRecord]:
    """Decode every ENTD record across ENTD1..4.ENT that has at least one unit.

    A record with units but no enemies (all player-controlled) is still emitted
    with an empty `enemies` list, so the runtime can tell 'exists, no enemies'
    (fall back to procedural) from 'missing index'.
    """
    records: list[EntdRecord] = []
    for fnum in range(1, ENTD_FILES + 1):
        path = battle_dir / f"ENTD{fnum}.ENT"
        if not path.exists():
            raise SystemExit(f"ENTD file not found: {path}")
        data = path.read_bytes()
        for r in range(ENTD_RECORDS_PER_FILE):
            start = r * ENTD_RECORD_STRIDE
            rec = data[start:start + ENTD_RECORD_STRIDE]
            if len(rec) < ENTD_RECORD_STRIDE:
                break
            # Skip wholly-empty records (every slot's sprite byte is 0).
            if not any(rec[s * ENTD_UNIT_STRIDE] for s in range(ENTD_UNITS_PER_RECORD)):
                continue
            entd_idx = (fnum - 1) * ENTD_RECORDS_PER_FILE + r
            records.append(decode_entd_record(rec, entd_idx))
    return records


# =============================================================================
# Emit
# =============================================================================

def _deployment_payload(zones: list[DeploymentZone]) -> dict:
    return {
        "_source": "EVENT/ATTACK.OUT deployment-zone table",
        "_layout": {
            "offset": DEPLOY_OFFSET,
            "count": DEPLOY_COUNT,
            "stride": DEPLOY_STRIDE,
        },
        "zones": {
            str(z.deployment_idx): {
                "deployment_idx": z.deployment_idx,
                "center_x": z.center_x,
                "center_y": z.center_y,
                "zone_facing": z.zone_facing,
                "unit_facing": z.unit_facing,
                # KEY NAME IS FROZEN, the function's is not: `unit_facing_12bit` is
                # what `DeploymentZoneDatabase` + `NavigatorMain._deploy_owned_units`
                # read. It carries BOTH nibbles composed, despite the name.
                "unit_facing_12bit": start_facing_12bit(z.unit_facing, z.zone_facing),
                "max_squad_size": z.max_squad_size,
                "map_id": z.map_id,
                "tiles": [list(t) for t in z.tiles],
            }
            for z in zones
        },
    }


def _entd_payload(records: list[EntdRecord]) -> dict:
    return {
        "_source": "BATTLE/ENTD{1..4}.ENT enemy positions",
        "_layout": {
            "files": ENTD_FILES,
            "records_per_file": ENTD_RECORDS_PER_FILE,
            "record_stride": ENTD_RECORD_STRIDE,
            "unit_stride": ENTD_UNIT_STRIDE,
            "units_per_record": ENTD_UNITS_PER_RECORD,
        },
        "entds": {
            str(r.entd_idx): {
                "entd_idx": r.entd_idx,
                "enemies": [
                    {
                        "x": e.x,
                        "y": e.y,
                        "upper_level": e.upper_level,
                        "facing": e.facing,
                        "team_color": e.team_color,
                    }
                    for e in r.enemies
                ],
            }
            for r in records
        },
    }


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Parse FFT strategy-phase placement tables "
                    "(deployment zones + ENTD enemy positions)")
    ap.add_argument("--attack-out", type=Path, default=None,
                    help="path to EVENT/ATTACK.OUT (default: project-assets extract)")
    ap.add_argument("--battle-dir", type=Path, default=None,
                    help="path to BATTLE/ (holds ENTD1..4.ENT)")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                    help="output directory for the two JSON artifacts")
    args = ap.parse_args()

    attack_out = args.attack_out or rp.attack_out()
    battle_dir = args.battle_dir or rp.battle_dir()
    if not attack_out.exists():
        raise SystemExit(f"ATTACK.OUT not found: {attack_out}")
    if not battle_dir.exists():
        raise SystemExit(f"BATTLE dir not found: {battle_dir}")

    zones = parse_all_deployment_zones(attack_out.read_bytes())
    records = parse_all_entds(battle_dir)

    # ADR-0052/0057 chirality fix: a deployment tile is a Placement quantity, so
    # renumber its depth axis at parse time (y -> size_z-1-y). Each zone carries
    # its own map_id (record byte 9), so size_z resolves directly — no scenario
    # join needed. Zones whose map isn't parsed yet are left raw (logged), same
    # as parse_entd does for unparsed maps.
    missing_maps: set[int] = set()
    for zone in zones:
        size_z = _load_size_z_for_map(zone.map_id)
        if size_z is None:
            missing_maps.add(zone.map_id)
            continue
        apply_chirality_fix_to_zone(zone, size_z)
    if missing_maps:
        print(f"  WARNING: {len([z for z in zones if z.map_id in missing_maps])} "
              f"zone(s) left un-flipped — no terrain.json for maps "
              f"{sorted(missing_maps)}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    dep_out = args.out_dir / "deployment_zones.json"
    entd_out = args.out_dir / "entd_positions.json"
    dep_out.write_text(json.dumps(_deployment_payload(zones), indent="\t") + "\n")
    entd_out.write_text(json.dumps(_entd_payload(records), indent="\t") + "\n")

    enemy_total = sum(len(r.enemies) for r in records)
    print(f"Parsed {len(zones)} non-empty deployment zones from {attack_out}")
    print(f"  -> {dep_out}")
    print(f"Parsed {len(records)} ENTD records ({enemy_total} enemy positions) "
          f"from {battle_dir}")
    print(f"  -> {entd_out}")


if __name__ == "__main__":
    main()
