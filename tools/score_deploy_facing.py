#!/usr/bin/env python3
"""Score the deployment-zone START-FACING rule against every battle the game ships.

`parse_placement.start_facing_12bit` says the squad's start facing is BOTH nibbles
of the deployment record's byte 0x07 composed — `((1 - unit_facing - zone_facing) &
3) << 10`. That rule is rooted in the ROM (see the derivation above the function).
This is the OTHER half of the evidence: a corpus arm that asks whether the rule
actually points the squad at the enemy across all 72 battles, not just the one it
was first checked on.

WHY IT EXISTS AS A COMMITTED INSTRUMENT. The rule it replaced was calibrated on a
single zone (Gariland, 256) and shipped wrong for every zone whose `zone_facing`
differs from that one — a whole-corpus question answered from one sample. A number
quoted in a commit message cannot be re-run when the artifacts move; this can.

THREE ARMS, NOT ONE. A lone score is unfalsifiable — "56 of 61" means nothing
without knowing what a WRONG rule scores on the same 61. So it scores:

    shipped    ((1 - uf - zf) & 3) << 10   what parse_placement emits
    mirrored   ((uf + zf - 1) & 3) << 10   the same composition, opposite sense
    nibble     {0:0x800,1:0x400,2:0x000,3:0xC00}[uf]   the pre-2026-09 table

The mirror arm is the one that matters: it agrees with the shipped rule on exactly
the half of the (uf, zf) space where `(uf + zf - 1)` is even, so it is the closest
wrong answer available and the only arm that can catch a sign error.

THE ORACLE IS A HEURISTIC AND IS NOT SILENT ABOUT IT. "The squad should face the
Red ENTD centroid" is true of most FFT battles and not all of them — a rule scoring
100% would be the surprise. Pairs whose centroid is diagonal (neither axis clearly
dominant) are DROPPED rather than guessed, and the count dropped is printed. So
read the arms against EACH OTHER; the absolute number is the weaker signal.

Exit status: 0 if the shipped rule strictly beats both other arms, 1 otherwise
(including 1 if no pair could be scored at all — an empty register means nothing
was examined, not that everything passed).

Usage:
    uv run python tools/score_deploy_facing.py
    uv run python tools/score_deploy_facing.py --verbose   # per-pair table
"""

from __future__ import annotations

import argparse
import json
import sys

import _repo_paths as rp

ENCOUNTERS = rp.almanac_dir("encounters")
ENTD_JSON = rp.assets_dir("scenarios/entd.json")

# The render wheel, in the Godot-native (post-ADR-0052 flip) frame the artifacts
# are already in: 0x000 = +tile-y (+Z), 0x400 = -tile-x, 0x800 = -tile-y,
# 0xC00 = +tile-x. Inverse of `AnimationStateController.angle_12bit_to_facing`;
# matches `Unit._CARDINAL_TO_12BIT` and `TileTraversalUtils` (+X=NORTH, +Z=EAST).
ANGLE_NAMES = {0x000: "+Z", 0x400: "-X", 0x800: "-Z", 0xC00: "+X"}

# A centroid this close to axis-aligned is a coin flip, not an oracle. Drop it.
DIAGONAL_SLACK = 1.25


def dominant_angle(dx: float, dy: float) -> int | None:
    """The 12-bit angle pointing from the zone at (dx, dy), or None if the
    direction is too diagonal for the heuristic to name one honestly."""
    if abs(abs(dx) - abs(dy)) < DIAGONAL_SLACK:
        return None
    if abs(dy) > abs(dx):
        return 0x000 if dy > 0 else 0x800
    return 0xC00 if dx > 0 else 0x400


def shipped(uf: int, zf: int) -> int:
    return ((1 - uf - zf) & 0x03) << 10


def mirrored(uf: int, zf: int) -> int:
    return ((uf + zf - 1) & 0x03) << 10


def nibble_only(uf: int, zf: int) -> int:
    return {0: 0x800, 1: 0x400, 2: 0x000, 3: 0xC00}[uf & 0x03]


ARMS = {"shipped": shipped, "mirrored": mirrored, "nibble": nibble_only}


def load() -> tuple[dict, dict, dict]:
    scenarios = json.loads((ENCOUNTERS / "scenarios.json").read_text())["scenarios"]
    zones = json.loads((ENCOUNTERS / "deployment_zones.json").read_text())["zones"]
    entd = json.loads(ENTD_JSON.read_text())["records"]
    return scenarios, zones, entd


def pairs(scenarios: dict, zones: dict, entd: dict) -> list[dict]:
    """Every distinct (deployment zone, ENTD record) the game ships, with the
    direction its Red cast sits in. Both squad slots count; a zone whose map_id
    disagrees with its scenario's is skipped (the index is not for this battle)."""
    seen: set[tuple[int, int]] = set()
    out: list[dict] = []
    for scenario in scenarios.values():
        for idx in (
            scenario["first_squad_deployment_idx"],
            scenario["second_squad_deployment_idx"],
        ):
            if not idx or str(idx) not in zones:
                continue
            zone = zones[str(idx)]
            if zone["map_id"] != scenario["map_id"]:
                continue
            key = (idx, scenario["entd_idx"])
            if key in seen:
                continue
            seen.add(key)
            record = entd.get(str(scenario["entd_idx"]))
            if record is None:
                continue
            reds = [
                s for s in record["slots"]
                if s.get("unit_id", 0xFF) != 0xFF and s["team_color"] == 1
            ]
            tiles = zone["tiles"]
            if not reds or not tiles:
                continue
            # Zone tile centroid, not `center_x/center_y`: the record's centre can
            # sit off the footprint once the 5x5 is rotated and clipped, and it is
            # the tiles the squad actually stands on.
            zx = sum(t[0] for t in tiles) / len(tiles)
            zy = sum(t[1] for t in tiles) / len(tiles)
            rx = sum(s["x"] for s in reds) / len(reds)
            ry = sum(s["y"] for s in reds) / len(reds)
            out.append({
                "zone": idx,
                "name": scenario["scenario_name"],
                "unit_facing": zone["unit_facing"],
                "zone_facing": zone["zone_facing"],
                "dx": rx - zx,
                "dy": ry - zy,
                "want": dominant_angle(rx - zx, ry - zy),
            })
    return sorted(out, key=lambda p: p["zone"])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--verbose", action="store_true", help="print the per-pair table")
    args = ap.parse_args()

    scenarios, zones, entd = load()
    all_pairs = pairs(scenarios, zones, entd)
    scored = [p for p in all_pairs if p["want"] is not None]

    # PRINT THE SUBJECT. A score over an empty corpus reads exactly like a pass.
    print(f"deployment_zones.json: {len(zones)} zones")
    print(f"(zone, ENTD) pairs on a matching map: {len(all_pairs)}")
    print(f"  scored: {len(scored)}   dropped as diagonal: {len(all_pairs) - len(scored)}")
    if not scored:
        print("NOTHING SCORED — the oracle examined no battle. Not a pass.")
        return 1

    hits = {name: 0 for name in ARMS}
    for pair in scored:
        for name, arm in ARMS.items():
            if arm(pair["unit_facing"], pair["zone_facing"]) == pair["want"]:
                hits[name] += 1

    if args.verbose:
        print()
        print(f"{'zone':>5} {'uf':>3} {'zf':>3} {'want':>5}  "
              f"{'shipped':>8} {'mirrored':>9} {'nibble':>7}   {'dx':>6} {'dy':>6}  scenario")
        for pair in scored:
            cells = []
            for name, arm in ARMS.items():
                got = arm(pair["unit_facing"], pair["zone_facing"])
                cells.append(f"{ANGLE_NAMES[got]}{'  ' if got == pair['want'] else ' x'}")
            print(f"{pair['zone']:>5} {pair['unit_facing']:>3} {pair['zone_facing']:>3} "
                  f"{ANGLE_NAMES[pair['want']]:>5}  {cells[0]:>8} {cells[1]:>9} {cells[2]:>7}   "
                  f"{pair['dx']:>6.1f} {pair['dy']:>6.1f}  {pair['name'][:34]}")

    print()
    for name in ARMS:
        print(f"  {name:<9} {hits[name]:>3}/{len(scored)}  "
              f"({100.0 * hits[name] / len(scored):.0f}%)")

    best = max(hits.values())
    if hits["shipped"] < best or list(hits.values()).count(best) > 1:
        print("\nFAIL: the shipped rule does not strictly beat both control arms.")
        return 1
    print("\nOK: the shipped rule strictly beats its mirror and the nibble-only table.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
