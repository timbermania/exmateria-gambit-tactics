#!/usr/bin/env python3
"""
FFT Shop Availability Parser

Decodes *when* the game lets you buy something. Three ROM sources, one artifact:

1. **The tier byte.** Each 12-byte common item record carries a "shop
   availability" tier in `rec[10]` (`0x80062EC2 + id*12`, SCUS file
   `0x53722 + id*12`). 1..15 are real tiers; 20 means "never sold".

2. **The shop-slot mask.** A big-endian `u16` per item at WORLD.BIN
   `0x8018D844 + id*2` (file `0xAD844`, load base `0x800E0000`) says which of
   16 shop slots stock it.

3. **The unlock timeline.** The shop candidate builder `FUN_8012502C` gates on
   `rec[10] <= getvar(0x6F)`:

       801251B8  addu at,at,s7        ; s7 = id * 12
       801251BC  lbu  v0,0x2EC2(at)   ; rec[10]
       801251C8  slt  v0,t0,v0        ; t0 = getvar(0x6F)
       801251CC  bne  v0,zero,<skip>

   World variable 0x6F is a plain 32-bit word (`FUN_800FD7C4` lays indices
   < 0x80 out at `*(0x80153280) + idx*4`, i.e. `0x800578D8`), and **no engine
   code writes it** — the writers are event scripts in `EVENT/TEST.EVT`. The
   world-script setter `FUN_800EF25C` composes an assignment as `Zero` then
   `Add`, and the bytecode does the same:

       BE <lo> <hi>              Zero      var
       B0 <lo> <hi> <val u16>    Add val -> var

   Both halves are required. A bare `B0` is an *increment*, not an assignment.
   Because a TEST.EVT event index IS a `scenario_id` (see `parse_scenarios.py`
   and `export_all_scenario_chunks.py`), each pair names the scenario that
   raises the tier.

`scan_variable_assignments()` is deliberately generic — pass any variable index
to answer "which scenario turns X on?" for other story state (0x2C gil, 0x31
the world-map location that doubles as the shop slot, 0x6E the
locations-unlocked counter).

Outputs:
- addons/exmateria_almanac/items/shop_availability.json — committed extracted
  artifact, read by `items/ShopAvailabilityDatabase.gd`.

Usage:
    uv run python tools/parse_shop_availability.py
    uv run python tools/parse_shop_availability.py --check
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

from _repo_paths import almanac_dir as _almanac_dir
from _repo_paths import fft_extract_root as _fft_extract_root

# --- ROM layout --------------------------------------------------------------

SCUS_LOAD_BASE = 0x8000F800          # SCUS_942.21
WORLD_LOAD_BASE = 0x800E0000         # WORLD/WORLD.BIN

ITEM_RECORD_TABLE = 0x80062EB8       # 254 x 12 bytes
ITEM_RECORD_STRIDE = 12
ITEM_TIER_FIELD = 10                 # rec[10]
ITEM_ENEMY_LEVEL_FIELD = 2           # rec[2] — the random-equip threshold
ITEM_COUNT = 254

SHOP_MASK_TABLE = 0x8018D844         # 254 x u16, BIG-endian
SHOP_SLOTS = 16

SHOP_TIER_VAR = 0x6F                 # world-script variable
TIER_NEVER = 20                      # rec[10] value meaning "not sold, ever"

EVENT_SIZE = 8192                    # TEST.EVT: 500 events x 8192 bytes
EVENT_COUNT = 500

OP_ZERO = 0xBE                       # "Zero var"
OP_ADD = 0xB0                        # "Add value -> var"

DEFAULT_OUTPUT = _almanac_dir("items/shop_availability.json")


@dataclass(frozen=True)
class VarAssignment:
    """One `Zero; Add` pair found in an event script."""

    event_index: int                 # == scenario_id
    byte_offset: int                 # offset of the OP_ZERO byte within the event
    value: int


def scan_variable_assignments(evt: bytes, var_index: int) -> list[VarAssignment]:
    """Every `Zero var; Add n -> var` pair in TEST.EVT, in file order.

    Matching BOTH halves is what makes this an assignment scan rather than an
    increment scan — the engine's own setter emits the pair, and event scripts
    that only mean "+= n" emit the `Add` alone.
    """
    lo, hi = var_index & 0xFF, (var_index >> 8) & 0xFF
    zero = bytes((OP_ZERO, lo, hi))
    add = bytes((OP_ADD, lo, hi))
    out: list[VarAssignment] = []
    i = 0
    while True:
        i = evt.find(zero, i)
        if i < 0:
            return out
        if evt[i + 3:i + 6] == add:
            value = evt[i + 6] | (evt[i + 7] << 8)
            out.append(VarAssignment(i // EVENT_SIZE, i % EVENT_SIZE, value))
        i += 1


def item_records(scus: bytes) -> list[bytes]:
    off = ITEM_RECORD_TABLE - SCUS_LOAD_BASE
    return [scus[off + i * ITEM_RECORD_STRIDE:off + (i + 1) * ITEM_RECORD_STRIDE]
            for i in range(ITEM_COUNT)]


def shop_masks(world: bytes) -> list[int]:
    off = SHOP_MASK_TABLE - WORLD_LOAD_BASE
    return [(world[off + i * 2] << 8) | world[off + i * 2 + 1]
            for i in range(ITEM_COUNT)]


def build(extract: Path) -> dict:
    scus = (extract / "SCUS_942.21").read_bytes()
    world = (extract / "WORLD" / "WORLD.BIN").read_bytes()
    evt = (extract / "EVENT" / "TEST.EVT").read_bytes()
    if len(evt) != EVENT_COUNT * EVENT_SIZE:
        raise SystemExit(f"TEST.EVT size {len(evt)} != {EVENT_COUNT * EVENT_SIZE}")

    recs = item_records(scus)
    masks = shop_masks(world)
    assignments = scan_variable_assignments(evt, SHOP_TIER_VAR)
    if not assignments:
        raise SystemExit(f"no assignments to world variable 0x{SHOP_TIER_VAR:02X} "
                         f"in TEST.EVT — layout constants are wrong")

    scen_path = _almanac_dir("encounters/scenarios.json")
    scen = json.loads(scen_path.read_text())["scenarios"] if scen_path.exists() else {}

    # tier -> the FIRST scenario that assigns it (later ones re-pin, they do not
    # raise: the Deep Dungeon events all assign 5, which is why entering it
    # early holds the shops at tier 5).
    unlocks: dict[str, dict] = {}
    for a in assignments:
        key = str(a.value)
        if key in unlocks:
            unlocks[key]["also_assigned_by"].append(a.event_index)
            continue
        unlocks[key] = {
            "tier": a.value,
            "unlock_scenario_id": a.event_index,
            "unlock_scenario_name": scen.get(str(a.event_index), {}).get("scenario_name", ""),
            "item_ids": [],
            "also_assigned_by": [],
        }

    items: dict[str, dict] = {}
    for item_id in range(1, ITEM_COUNT):
        rec = recs[item_id]
        tier = rec[ITEM_TIER_FIELD]
        row = {
            "shop_tier": tier,
            "shop_slot_mask": masks[item_id],
            "enemy_level": rec[ITEM_ENEMY_LEVEL_FIELD],
            "unlock_scenario_id": -1,
        }
        entry = unlocks.get(str(tier))
        if entry is not None and tier != TIER_NEVER:
            entry["item_ids"].append(item_id)
            row["unlock_scenario_id"] = entry["unlock_scenario_id"]
        items[str(item_id)] = row

    # Forward-filled tier in force after each assigning scenario. Consumers can
    # binary-search or walk this to answer "what was buyable at scenario N".
    timeline = [{"scenario_id": a.event_index, "tier": a.value} for a in assignments]
    timeline.sort(key=lambda r: r["scenario_id"])

    return {
        "_source": ("SCUS_942.21 item records rec[10] + WORLD.BIN shop-slot mask"
                    " + EVENT/TEST.EVT assignments to world variable 0x6F"),
        "_layout": {
            "item_record_table": ITEM_RECORD_TABLE,
            "item_record_stride": ITEM_RECORD_STRIDE,
            "tier_field": ITEM_TIER_FIELD,
            "shop_mask_table": SHOP_MASK_TABLE,
            "shop_mask_endian": "big",
            "shop_slots": SHOP_SLOTS,
            "shop_tier_variable": SHOP_TIER_VAR,
            "shop_tier_variable_address": 0x800578D8,
            "tier_never": TIER_NEVER,
            "gate": "stocked if (mask & (0x8000 >> shop_slot)) and shop_tier >= rec[10]",
        },
        "tiers": unlocks,
        "timeline": timeline,
        "items": items,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--extract", type=Path, default=None,
                    help="fft-extract root (default: project-assets/fft-extract)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory and fail if the artifact is stale")
    args = ap.parse_args()

    payload = build(args.extract or _fft_extract_root())
    text = json.dumps(payload, indent="\t") + "\n"

    if args.check:
        if not args.out.exists():
            sys.exit(f"MISSING: {args.out} — run tools/parse_shop_availability.py")
        if args.out.read_text() != text:
            sys.exit(f"STALE: {args.out} — run tools/parse_shop_availability.py")
        print(f"OK: {args.out} matches the ROM")
        return

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text)

    tiers = sorted(int(k) for k in payload["tiers"])
    sold = sum(1 for r in payload["items"].values() if r["unlock_scenario_id"] >= 0)
    print(f"Parsed {len(payload['timeline'])} assignments to var 0x{SHOP_TIER_VAR:02X}")
    print(f"  tiers:        {tiers}")
    print(f"  items sold:   {sold} of {ITEM_COUNT - 1}")
    for t in tiers:
        e = payload["tiers"][str(t)]
        print(f"  tier {t:>2}: scenario {e['unlock_scenario_id']:>3} "
              f"{e['unlock_scenario_name']!r} (+{len(e['item_ids'])})")
    print(f"  -> {args.out}")


if __name__ == "__main__":
    main()
