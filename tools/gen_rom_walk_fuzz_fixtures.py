#!/usr/bin/env python3
"""Differential fixtures: the GDScript port against the Python spec, on RANDOM input.

🔴 **THESE ARE NOT SCORED AGAINST HARDWARE.** `gen_rom_walk_fixtures.py` bakes the
thirteen live PSX captures and those say what the ROM does. This file says
something narrower and still worth having: that `RomWalkStepper.gd` and
`rom_walk_render.py` are the SAME state machine, on inputs neither has ever seen.

Why it is needed. The thirteen captures score 43 510 field-frames and every one of
them is an ordinary `{28} Walk To` on MAP009, so whole arms of the machine are
never entered by them:

    the LEAP            `FUN_8006A538`   — route `extra >= 1`
    the BIG JUMP        `FUN_8006A7C0`   — a >= 4-level climb, unreachable from `{28}`
    the WIND-UP         `_WINDUP` states — a leap with `extra >= 2`
    HARD LANDING + recover  `FUN_8006C3D8`
    the landing SOUND and PUFF tables    — 46 surfaces, `FUN_8006B994`/`8006BA38`
    the FAR-FALL pose swap               — 42 render units above ground
    the WADING animation band            — `depth >= 2` under the unit

A transcription slip in any of those is invisible to the capture fixtures. It is
NOT invisible to a second implementation fed the same random terrain: the two were
written from the same reading, so this cannot catch a misreading, but it catches a
mistyped constant, an inverted comparison, a missed sign, a wrong table index —
which is the whole population of errors a port introduces.

So: capture fixtures test the READING. These test the TRANSCRIPTION. Neither
substitutes for the other, and a green run here says nothing about the ROM.

The RNG is seeded, so the corpus is reproducible and reviewable.

    uv run python godot-learning/tools/gen_rom_walk_fuzz_fixtures.py
"""
import json
import os
import random
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))
_EVIDENCE = os.path.join(_ROOT, "research", "scenario29_walk_vs_jump", "evidence")
sys.path.insert(0, _EVIDENCE)

import rom_walk_render as R          # noqa: E402
from rom_event_flood import Tile     # noqa: E402

OUT_DIR = os.path.join(_HERE, "..", "addons", "exmateria_battlefield", "tests",
                       "fixtures", "rom_walk_fuzz")

SEED = 8032026
CASES = 48
NX = NY = 6
MAX_FRAMES = 900

#: The twelve draping shapes plus Flat. Anything else is flat by `FUN_8007C80C`.
SLOPES = [0x00, 0x52, 0x85, 0x25, 0x58, 0x41, 0x96, 0x14, 0x69, 0x11, 0x44, 0x66, 0x99]
#: One surface from each landing-table class, so `landing_sound` / `landing_puff`
#: are driven down every branch rather than down the grassland one 46 times.
SURFACES = [0x03, 0x1D,              # -> sound 0x28
            0x0E, 0x0F, 0x11, 0x2D,  # -> sound 0x23, puff 0x0F (the splash)
            0x14, 0x1E, 0x1F,        # -> sound 0x3A
            0x01, 0x08, 0x23, 0x2E,  # -> sound 0x29, puff 0x09
            0x00, 0x05, 0x18]        # -> sound 0x29, NO puff

FIELDS = ["st", "x", "y", "z", "vx", "vy", "vz", "dstx", "dsty", "dstlevel",
          "tilex", "tiley", "level", "idx", "rb", "anim", "facing", "altmag"]

TILE_FIELDS = ("surface", "height", "depth", "slope_h", "slope_t")


def random_tiles(rng):
    tiles = [[[None] * NX for _ in range(NY)] for _ in range(2)]
    for lvl in (0, 1):
        for y in range(NY):
            for x in range(NX):
                tiles[lvl][y][x] = Tile(
                    surface=rng.choice(SURFACES),
                    # A range wide enough that a >= 4-level climb — the BIG JUMP,
                    # which `{28}` itself can never reach — actually occurs.
                    height=rng.randint(0, 7),
                    depth=rng.randint(0, 3),
                    slope_h=rng.randint(0, 3),
                    slope_t=rng.choice(SLOPES))
    return tiles


def random_route(rng):
    n = rng.randint(3, 6)
    out = [n]
    for _ in range(n):
        d = rng.randint(0, 3)
        rb = d << 6
        rb |= rng.choice([0, 0, 1, 2])      # extra: leap span, and the wind-up at >= 2
        if rng.random() < 0.30:
            rb |= 0x04                      # bit 2 — leaving a steep tile: the GAIT
        if rng.random() < 0.30:
            rb |= 0x08                      # bit 3 — the gait at the launch gate
        if rng.random() < 0.15:
            rb |= 0x10                      # bit 4 — landing on another unit's head
        if rng.random() < 0.25:
            rb |= 0x20                      # bit 5 — the destination's LEVEL
        out.append(rb)
    return out


def build(rng, i):
    tiles = random_tiles(rng)
    T = R.Terrain(tiles, NX, NY)
    route = random_route(rng)
    speed = rng.choice([3.5, 4.0, 4.296875, 8.0, 10.0, 16.0, 23.0, 24.0, 32.0])
    sx, sy = rng.randint(1, NX - 2), rng.randint(1, NY - 2)
    level = rng.randint(0, 1)
    anim0 = rng.choice([0, 12, 14, 0x30])

    u = R.Unit(sx, sy, level, route, speed,
               T.ground_at(sx * R.TILE + 14, sy * R.TILE + 14, level))
    u.anim = anim0
    rows = []
    while len(rows) < MAX_FRAMES and R.frame(u, T):
        rows.append([u.state, u.renderx, u.rendery, u.renderz,
                     u.velx, u.vely, u.velz, u.dstx, u.dsty, u.dstlevel,
                     u.tilex, u.tiley, u.level, u.idx, u.rb, u.anim,
                     u.facing, u.altmag])
    packed = [[[[getattr(tiles[lvl][y][x], f) for f in TILE_FIELDS]
                for x in range(NX)] for y in range(NY)] for lvl in (0, 1)]
    return {
        "name": "fuzz%02d" % i,
        "speed": speed,
        "start": [sx, sy, level],
        "route": route,
        "anim0": anim0,
        "landing_frames": 18,
        "size": [NX, NY],
        "tile_fields": list(TILE_FIELDS),
        "tiles": packed,
        "fields": FIELDS,
        "frames": rows,
        "sounds": list(u.sounds),
        "puffs": list(u.puffs),
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = random.Random(SEED)
    index, skipped = [], 0
    # What the corpus actually exercises, printed so a reader can see it is not 48
    # repeats of a flat walk.
    seen_states, total_frames, sounds, puffs = set(), 0, 0, 0
    for i in range(CASES):
        try:
            fx = build(rng, i)
        except Exception as exc:                      # noqa: BLE001
            # A configuration the SPEC itself cannot run is not a port defect, and
            # baking it would assert an exception the GDScript has no way to raise.
            #
            # ⚠️ ONE known cause, and it is a real (narrow) finding rather than a
            # generator wart: `SquareRoot0` is UNDEFINED for a negative argument —
            # `SQRT[mant - 0x40]` indexes before the LUT, and on hardware that reads
            # whatever precedes `0x8002B8B8`. `arm_hop` can hand it one, because the
            # gate that chose the hop (`cur_h + 1 < dst_h`, via `_tile_half_levels`)
            # and the rise it then measures (`_rise_half_levels`, via the unit's LIVE
            # render Y) read DIFFERENT things, so a route byte whose level bit sends
            # the destination to the other terrain plane can satisfy the first and
            # produce a negative rise for the second. `{28}` cannot reach it: its
            # planner never emits such a step. Python raises here; GDScript would
            # index from the END of the array and return a plausible number, which is
            # exactly why these cases are excluded rather than baked.
            print("  skip fuzz%02d — the spec raised: %s" % (i, exc))
            skipped += 1
            continue
        if not fx["frames"]:
            print("  skip fuzz%02d — zero frames (route refused at once)" % i)
            skipped += 1
            continue
        with open(os.path.join(OUT_DIR, "%s.json" % fx["name"]), "w") as fh:
            json.dump(fx, fh, separators=(",", ":"))
        index.append(fx["name"])
        total_frames += len(fx["frames"])
        sounds += len(fx["sounds"])
        puffs += len(fx["puffs"])
        for r in fx["frames"]:
            seen_states.add(r[0])
    with open(os.path.join(OUT_DIR, "index.json"), "w") as fh:
        json.dump({"cases": index, "seed": SEED}, fh, indent=1)
    print("%d fixtures, %d frames, %d distinct `unit+0x7f` states, "
          "%d landing sound(s), %d puff(s); %d skipped"
          % (len(index), total_frames, len(seen_states), sounds, puffs, skipped))
    print("states reached: %s" % sorted("0x%02X" % s for s in seen_states))


if __name__ == "__main__":
    main()
