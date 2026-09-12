#!/usr/bin/env python3
"""Bake the `{28} Walk To` ROUTE captures into Godot test fixtures.

The sibling of `gen_rom_walk_fixtures.py`, which does this for the RENDER half.
`research/scenario29_walk_vs_jump/evidence/rom_event_flood.py` is the executable
transcription of the ROM's route planner, scored **224 of 224 flood tiles** and
**9 of 9 live PCSX captures byte-for-byte**; `EventPathfinder.gd` is that same
planner in GDScript, and the only honest way to say it is correct is to score it
against the same wire.

    uv run python godot-learning/tools/gen_rom_event_route_fixtures.py

TWO TIERS, AND THE TEST SAYS WHICH IS WHICH.

  * **WIRE.** Ten arms out of `evidence/psx_arm*.txt`.  Each patched the ROM's live
    tile array at `0x8018F8CC` and let the ROM re-plan scenario 29 PC 148 (unit
    `0x30`, PSX (2,11,0) -> (0,3,0)).  Two independent wire measurements come out of
    those logs and this bakes BOTH:
      - `cells`, the tile sequence the unit actually visited, off the per-frame
        `tile=` column.  Available for eight arms — including B, C and F, whose logs
        predate the route-byte column, so `rom_event_flood_arms.py` can only score
        them from prose;
      - `route`, the ROM's own emitted bytes, off the per-frame `rb=` column (five
        arms) or the run's `-> route:` line (V1, V3).  Seven arms.
    A port that reproduces these is scored against HARDWARE.  Scoring it against
    `rom_event_flood.py` instead would pass a shared misreading, which is the failure
    mode the whole research document exists to avoid.

  * **CROSS-CHECK.**  Routes the arms cannot reach at all, replayed out of the
    shipped `{28}` corpus and predicted by the PYTHON transcription — the level bit
    (no live capture has ever set route bit 5, and twelve corpus routes do), the
    destination gate's refusal, and the flattened cost row.  These score two
    independent transcriptions against each other, which is a weaker claim, and the
    fixture says so in its own `tier` field so the test can print it.

Every fixture carries its own post-patch tile array, so the test needs no
`res://assets/maps` — that is an ASSET SYMLINK, absent from a bare worktree — and
no patch machinery on the GDScript side.  It also carries `route_source`, naming
the wire column the expectation came out of, because "the ROM does this" and "the
Python thinks the ROM does this" must never be readable as the same row.
"""
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))
_EVIDENCE = os.path.join(_ROOT, "research", "scenario29_walk_vs_jump", "evidence")
sys.path.insert(0, _EVIDENCE)

import rom_event_flood_arms as A                                     # noqa: E402
from rom_event_flood import Planner, load_map, cost_row              # noqa: E402

OUT_DIR = os.path.join(_HERE, "..", "addons", "exmateria_battlefield", "tests",
                       "fixtures", "rom_event_route")

#: The HOST also needs one of these, and it may not reach into the addon to get it.
#: `ScenarioPathMotionTest`'s end-to-end arm (#819 item 5) plans the control route and
#: walks it through `ScenarioPathMotion`'s coordinate map, which is host code and cannot
#: move into the addon — but a `tests/` file naming an `res://addons/<addon>/` path is
#: `check_lattice_scene` criterion 4's whole subject, and this one cannot claim the
#: ORACLE channel either: that channel's condition 2 requires the file to name a HOST
#: `res://` path, and `ScenarioPathMotionTest` names none.
#:
#: So the generator writes the control case to BOTH roots. Two files, ONE source, minted
#: in the same run from the same dict — they cannot drift, which is the only thing that
#: makes a second copy acceptable here (contrast `RomTerrain`'s enum tables, where the
#: two copies are hand-written and therefore need `check_rom_terrain_tables.py`).
HOST_OUT_DIR = os.path.join(_HERE, "..", "tests", "fixtures", "rom_event_route")

#: Which cases the host copy carries. Only what a host arm actually reads — the control
#: is the one the end-to-end arm walks.
HOST_CASES = ("control",)

TILE_FIELDS = ("surface", "height", "depth", "slope_h", "slope_t",
               "thickness", "impassable", "unselectable")

#: arm label prefix -> (trace file, how its cells parse, how its route parses).
#: `named` is the `tile=x,y,z rb=NN` column layout; `positional` is the older log
#: whose 8th field is the tile and which has no route column at all.
ARM_TRACES = {
    "control": ("psx_control_walk_trace.txt", "named", "rb"),
    "B ": ("psx_armB_depth_zero.txt", "positional", None),
    "C ": ("psx_armC_level_tiles.txt", "positional", None),
    "F ": ("psx_armF_surface_grass.txt", "positional", None),
    "I ": ("psx_armI_obstacle_tile.txt", "named", "rb"),
    "J ": ("psx_armJ_two_water_tiles.txt", "named", "rb"),
    "K ": ("psx_armK_wide_moat.txt", "named", "rb"),
    "L ": ("psx_armL_leap_would_climb.txt", "named", "rb"),
    "V1": ("psx_arm_V.txt", None, "line:V1"),
    "V3": ("psx_arm_V.txt", None, "line:V3"),
}

_NAMED = re.compile(
    r"\bi=(\d+) tile=(\d+),(\d+),(\d+) rb=([0-9A-Fa-f]{2}) c11c=([0-9A-Fa-f]{2})")
_ROUTE_LINE = re.compile(r"^ARM (V\d) -> route:\s*((?:[0-9A-Fa-f]{2}\s*)+)")


def wire_named(path):
    """`cells` and `route` off a `tile=`/`rb=` log. The route index `i=` is the key:
    the byte logged while the unit is at index `n` IS route byte `n`.

    ⚠ GATE ON `c11c` FIRST.  `unit+0x11C` is the ROM's live route pointer and it
    reads `00` for the whole idle lead-in the capture starts on -- during which `i`
    is also 0 and `rb` is `00`.  Taking the first `rb` per index without the gate
    prepends a phantom `00` step, and `00` is a LEGAL route byte (+X, span 0, no
    bits), so nothing downstream can tell it from a real one."""
    cells, route, seen, armed = [], [], None, False
    for line in open(path):
        m = _NAMED.search(line)
        if not m:
            continue
        i = int(m.group(1))
        cell = [int(m.group(2)), int(m.group(3)), int(m.group(4))]
        if not cells or cells[-1] != cell:
            cells.append(cell)
        if not armed:
            if int(m.group(6), 16) == 0:
                continue
            armed = True
        if i != seen:
            route.append(int(m.group(5), 16))
            seen = i
    return cells, route


def wire_positional(path):
    """`cells` off the older log, whose 8th whitespace field is `x,y,level`.
    No route column exists in this format -- these arms are cell-scored only."""
    cells = []
    for line in open(path):
        f = line.split()
        if len(f) < 8 or not f[0].isdigit():
            continue
        try:
            cell = [int(v) for v in f[7].split(",")]
        except ValueError:
            continue
        if len(cell) == 3 and (not cells or cells[-1] != cell):
            cells.append(cell)
    return cells, []


def wire_route_line(path, arm):
    """The `ARM V1 -> route: 08 40 84 ...` summary line, INCLUDING its count byte."""
    for line in open(path):
        m = _ROUTE_LINE.match(line.strip())
        if m and m.group(1) == arm:
            return [int(b, 16) for b in m.group(2).split()]
    raise SystemExit("no `-> route:` line for %s in %s" % (arm, path))


def tile_array(patch):
    """MAP009 post-patch, `[level][psx_y][x] -> the eight bytes the planner reads`."""
    tiles, nx, ny = load_map("MAP009")
    if patch is not None:
        patch(tiles)
    packed = [[[[int(getattr(tiles[lvl][y][x], f)) for f in TILE_FIELDS]
                for x in range(nx)]
               for y in range(ny)]
              for lvl in (0, 1)]
    return packed, nx, ny


def model(patch, start, dest, cost, tiles_nx_ny=None):
    """What the PYTHON transcription plans for this arm: (route bytes, cells)."""
    tiles, nx, ny = load_map("MAP009") if tiles_nx_ny is None else tiles_nx_ny
    if tiles_nx_ny is None:
        patch(tiles)
    p = Planner(tiles, nx, ny, cost)
    p.flood_from(list(start), list(dest))
    if not p.destination_reachable(dest):
        return None, None
    chain = p.walk_back(list(start), list(dest))
    if chain is None:
        return None, None
    cells = [list(start)] + [[c[0], c[1], c[2]] for c in reversed(chain)]
    return p.route_bytes(chain), cells


def build_wire():
    out = []
    for label, patch, _expect in A.ARMS:
        key = next((k for k in ARM_TRACES if label.startswith(k)), None)
        if key is None:
            raise SystemExit("arm %r has no trace mapping" % label[:20])
        trace_file, cell_mode, route_mode = ARM_TRACES[key]
        path = os.path.join(_EVIDENCE, trace_file)
        cells, route = [], []
        if cell_mode == "named":
            cells, route = wire_named(path)
        elif cell_mode == "positional":
            cells, route = wire_positional(path)
        if route_mode and route_mode.startswith("line:"):
            route = wire_route_line(path, route_mode.split(":")[1])[1:]
        packed, nx, ny = tile_array(patch)
        got_route, got_cells = model(patch, A.START, A.DEST, cost_row(1))
        if got_route is None:
            raise SystemExit("%s: the transcription emits no route -- refusing to bake"
                             % label[:20])
        # A fixture is never written from a capture the scored transcription does not
        # reproduce. Both wire measurements are checked, each only where it exists.
        if route and list(got_route[1:]) != list(route):
            raise SystemExit("%s: model %s != wire %s -- refusing to bake"
                             % (label[:20], list(got_route[1:]), route))
        if cells and got_cells != cells:
            raise SystemExit("%s: model cells %s != wire %s -- refusing to bake"
                             % (label[:20], got_cells, cells))
        out.append({
            "name": key.strip() or "control",
            "tier": "WIRE",
            "label": label.split("\n")[0].strip(),
            "map": "MAP009",
            "trace": trace_file,
            "size": [nx, ny],
            "start": list(A.START),
            "dest": list(A.DEST),
            "weather_cost": 1,
            "tile_fields": list(TILE_FIELDS),
            "tiles": packed,
            # Present only when the wire states it. An empty list means "this log
            # cannot answer", NOT "the answer is nothing" -- the test skips the arm
            # rather than asserting an empty route, and counts the skip out loud.
            "cells": cells,
            "route": ([len(route)] + list(route)) if route else [],
            "refused": False,
            "cells_source": ("per-frame `tile=` column" if cell_mode == "named"
                             else "per-frame positional tile field" if cell_mode
                             else ""),
            "route_source": ("per-frame `rb=` column" if route_mode == "rb"
                             else "the run's `-> route:` line" if route_mode
                             else ""),
        })
    out.extend(build_wire_extra())
    return out


def build_wire_extra():
    """The eight arms out of `psx_arms_MNOPQR.txt`.

    Their logs are a written run report, not a per-frame trace, so there are no
    `cells` here — the route bytes (or the REFUSAL) are what that rig recorded, and
    a refusal is a first-class expectation: arm P watched the route buffer stay
    empty for 3338 frames."""
    out = []
    for name, patch, expect, flatten, why in WIRE_EXTRA:
        packed, nx, ny = tile_array(patch)
        cost = [1] * 64 if flatten else cost_row(1)
        tiles, tnx, tny = load_map("MAP009")
        if patch is not None:
            patch(tiles)
        got_route, _cells = model(None, A.START, A.DEST, cost, (tiles, tnx, tny))
        if expect is None:
            if got_route is not None:
                raise SystemExit("arm %s: the wire saw a REFUSAL and the "
                                 "transcription emits %s -- refusing to bake"
                                 % (name, list(got_route)))
        else:
            if got_route is None or list(got_route[1:]) != list(expect):
                raise SystemExit("arm %s: model %s != wire %s -- refusing to bake"
                                 % (name, None if got_route is None
                                    else list(got_route[1:]), list(expect)))
        out.append({
            "name": name,
            "tier": "WIRE",
            "label": why,
            "map": "MAP009",
            "trace": "psx_arms_MNOPQR.txt",
            "size": [nx, ny],
            "start": list(A.START),
            "dest": list(A.DEST),
            "weather_cost": 1,
            "flat_cost": flatten,
            "tile_fields": list(TILE_FIELDS),
            "tiles": packed,
            "cells": [],
            "route": [] if expect is None else [len(expect)] + list(expect),
            "refused": expect is None,
            "cells_source": "",
            "route_source": "the run report's OBSERVED line",
        })
    return out


#: Eight further WIRE arms, out of `evidence/psx_arms_MNOPQR.txt`. Same rig, same
#: instruction (scenario 29 PC 148), each patch and each OBSERVED route stated in
#: that file. `rom_event_flood_arms.py` does not carry them — its `ARMS` table
#: predates them — but they are live captures exactly as much as the others, and
#: three of them are the ONLY wire evidence for rules the rest cannot reach: arm O
#: is the only capture that ever set route bit 5, and arms P/R1/R2 are the only
#: ones that ever saw the destination gate REFUSE a walk outright.
#:   (name, patch, observed route bytes or None = REFUSED, flatten, why)
def _set(t, **kw):
    for k, v in kw.items():
        setattr(t, k, v)


WIRE_EXTRA = [
    ("M", lambda T: _set(T[1][10][1], surface=3, height=6, depth=0, slope_h=0,
                         slope_t=0, thickness=0, impassable=True,
                         unselectable=False),
     [0x80, 0x80, 0x40, 0x81, 0x80, 0x81, 0x80, 0x40], False,
     "the CEILING: an impassable L1 tile whose underside sits 12 half-levels up "
     "leaves no headroom at (1,10), so the route detours around column 1 (sec 21.3)"),

    ("N", lambda T: _set(T[0][8][1], height=5),
     [0x40, 0x80, 0x80, 0x80, 0x80, 0x80, 0x81, 0x80, 0x40], False,
     "the LEAP CLEARANCE, a swept-volume overlap: raising the flown-over tile "
     "blocks the first leap and the unit wades. Cost still favours the leap, so "
     "only clearance can explain the change (sec 21.4)"),

    ("O", lambda T: [_set(T[0][10][1], impassable=True),
                     _set(T[1][10][1], surface=3, height=6, depth=0, slope_h=0,
                          slope_t=0, thickness=0, impassable=False,
                          unselectable=False)],
     [0x80, 0x60, 0x80, 0x81, 0x80, 0x81, 0x80, 0x40], False,
     "A LEVEL CHANGE IS FREE, and 0x60 is route bit 5 — the LEVEL bit. The only "
     "capture in the whole investigation that ever set it (sec 21.7)"),

    ("P", lambda T: _set(T[0][3][0], depth=3),
     None, False,
     "the DESTINATION GATE: the route buffer stayed EMPTY for 3338 frames and the "
     "unit never left its warp tile. A refused Walk To is a NO-OP, not a partial "
     "walk (sec 21.8)"),

    ("R1", lambda T: _set(T[0][3][0], depth=1),
     None, False,
     "the same gate at depth 1 — and the PREDICTION here was WRONG (it said "
     "unchanged). `stateB+0x14` is inherited non-zero, so ANY depth > 0 target is "
     "refused; arm L had the unit STAND on a depth-1 tile at this very instruction, "
     "which is what rules out standability as the cause"),

    ("R2", lambda T: _set(T[0][3][0], depth=2),
     None, False,
     "the same gate at depth 2 — refused"),

    ("R0", lambda T: _set(T[0][3][0], depth=0,
                          height=T[0][3][0].height + 1),
     [0x40, 0x80, 0x80, 0x81, 0x80, 0x81, 0x80, 0x40], False,
     "the NEGATIVE CONTROL for R1/R2: depth 0 and the height raised instead. Route "
     "unchanged, which is what rules the height change out as the cause"),

    ("Q", lambda T: None,
     [0x40, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x40], True,
     "the `{28}` COST-TABLE SWITCH: operand `+8 == 0` flattens the whole cost row, "
     "the span-1 leap ties with the two walk steps it replaces, and the walk-back's "
     "span tie-break takes the WALK. 10 of 282 shipped instructions do this (sec 20.1)"),
]


#: The CROSS-CHECK tier: shipped corpus routes on maps and shapes no arm covers.
#: The expectation is the PYTHON transcription's — a second implementation, not a
#: measurement — and the fixture says so.
#:   (name, map, start, dest, weather, flatten, why)
CROSS = [
    ("scen29_pc152", "MAP009", (4, 12, 0), (1, 4, 0), 1, False,
     "scenario 29 pc 152 — a second two-leap route, from a different start"),
    ("scen29_pc261", "MAP009", (1, 4, 0), (1, 6, 0), 1, False,
     "scenario 29 pc 261 — the shortest leaping route in the corpus: ONE step, "
     "route `01 C1`"),
    ("scen29_pc324", "MAP009", (1, 6, 0), (2, 13, 0), 1, False,
     "scenario 29 pc 324 — a leap in the +Y direction, the other sign"),
    ("scen29_pc034", "MAP009", (7, 1, 0), (4, 2, 1), 1, False,
     "scenario 29 pc 34 — a shipped route that ENDS on level 1 and sets the level "
     "bit, `04 C0 40 40 60`"),
    ("scen192_pc017", "MAP012", (0, 12, 0), (5, 8, 1), 1, False,
     "scenario 192 pc 17 on MAP012 — a 9x15 map, nine steps, TWO level bits. The "
     "only fixture here that exercises the reader on a map other than MAP009/57"),
    ("scen233_pc070", "MAP057", (4, 11, 0), (4, 10, 1), 1, False,
     "scenario 233 pc 70 on MAP057 — one step straight onto level 1, route `01 A0`"),
]


def build_cross():
    out = []
    for name, map_name, start, dest, weather, flatten, why in CROSS:
        tiles, nx, ny = load_map(map_name)
        cost = [1] * 64 if flatten else cost_row(weather)
        route, cells = model(None, start, dest, cost, (tiles, nx, ny))
        packed = [[[[int(getattr(tiles[lvl][y][x], f)) for f in TILE_FIELDS]
                    for x in range(nx)]
                   for y in range(ny)]
                  for lvl in (0, 1)]
        out.append({
            "name": name,
            "tier": "CROSS-CHECK",
            "label": why,
            "map": map_name,
            "trace": "",
            "size": [nx, ny],
            "start": list(start),
            "dest": list(dest),
            "weather_cost": weather,
            "flat_cost": flatten,
            "tile_fields": list(TILE_FIELDS),
            "tiles": packed,
            "cells": cells if cells else [],
            "route": list(route) if route else [],
            "refused": route is None,
            "cells_source": "rom_event_flood.py (a SECOND transcription, not the wire)",
            "route_source": "rom_event_flood.py (a SECOND transcription, not the wire)",
        })
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(HOST_OUT_DIR, exist_ok=True)
    cases = build_wire() + build_cross()
    for fx in cases:
        with open(os.path.join(OUT_DIR, "%s.json" % fx["name"]), "w") as fh:
            json.dump(fx, fh, separators=(",", ":"))
        if fx["name"] in HOST_CASES:
            with open(os.path.join(HOST_OUT_DIR, "%s.json" % fx["name"]), "w") as fh:
                json.dump(fx, fh, separators=(",", ":"))
        print("%-14s %-11s cells %2d  route %2d  %s"
              % (fx["name"], fx["tier"], len(fx["cells"]), len(fx["route"]),
                 fx["route_source"] or "(no route on this log)"))
    index = {
        "cases": [c["name"] for c in cases],
        "wire": [c["name"] for c in cases if c["tier"] == "WIRE"],
        "cross_check": [c["name"] for c in cases if c["tier"] == "CROSS-CHECK"],
        "wire_route_scored": [c["name"] for c in cases
                              if c["tier"] == "WIRE" and c["route"]],
        "wire_cells_scored": [c["name"] for c in cases
                              if c["tier"] == "WIRE" and c["cells"]],
    }
    with open(os.path.join(OUT_DIR, "index.json"), "w") as fh:
        json.dump(index, fh, indent=1)
    print("\n%d fixtures -> %s" % (len(cases), os.path.normpath(OUT_DIR)))
    print("   WIRE  %d arms: %d route-scored, %d cell-scored"
          % (len(index["wire"]), len(index["wire_route_scored"]),
             len(index["wire_cells_scored"])))
    print("   CROSS-CHECK  %d" % len(index["cross_check"]))
    print("   host copy    %s -> %s" % (", ".join(HOST_CASES),
                                        os.path.normpath(HOST_OUT_DIR)))


if __name__ == "__main__":
    main()
