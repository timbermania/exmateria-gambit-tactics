#!/usr/bin/env python3
"""Bake the thirteen scored `{28} Walk To` PSX captures into Godot test fixtures.

`research/scenario29_walk_vs_jump/evidence/rom_walk_render.py` is the executable
transcription of the ROM's walk RENDER side, scored **43 510 of 43 510
field-frames over 13 captures** against the wire.  `RomWalkStepper.gd` is that
same state machine in GDScript, and the only honest way to say it is correct is
to score it against the same wire.

So this writes ONE self-contained fixture per capture:

  * the LIVE per-frame rows off the PSX log -- not the Python simulation's.  The
    fixture is a wire measurement; a GDScript port that reproduces it is scored
    against hardware, not against its own sibling transcription.
  * the post-patch MAP009 tile array, so the fixture needs no `res://assets/maps`
    (an ASSET SYMLINK, absent from a bare worktree) and no patch machinery
    on the GDScript side.
  * `compare_frames`, the frame count the Python scorer compared.  Without it a
    stepper that halts after three frames scores "0 differ" over three frames
    and reads as a pass.

    uv run python godot-learning/tools/gen_rom_walk_fixtures.py

Regenerate whenever `rom_walk_render.py`'s `CASES` gains a capture.  The
fixtures are the test's input; `RomWalkStepperStepperTest` never re-derives them.
"""
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))
_EVIDENCE = os.path.join(_ROOT, "research", "scenario29_walk_vs_jump", "evidence")
sys.path.insert(0, _EVIDENCE)

import rom_walk_render as R          # noqa: E402
from rom_event_flood import load_map  # noqa: E402

OUT_DIR = os.path.join(_HERE, "..", "addons", "exmateria_battlefield", "tests",
                       "fixtures", "rom_walk")

#: The live-trace column name for each field, and the fixture's own column order.
#: Mirrors `rom_walk_render.FIELDS`; `altmag` is appended only for the captures
#: whose log carries the `v3c=` column (`load_trace` sets it to None otherwise).
BASE_FIELDS = [lk for lk, _sk in R.FIELDS]

TILE_FIELDS = ("surface", "height", "depth", "slope_h", "slope_t")


def tile_array(map_name, patch):
    """The post-patch tile array, `[level][psx_y][x] -> [surface, h, depth, sh, st]`."""
    tiles, nx, ny = load_map(map_name)
    for px, py, plevel, field, value in patch:
        setattr(tiles[plevel][py][px], field, value)
    packed = [[[[getattr(tiles[lvl][y][x], f) for f in TILE_FIELDS]
                for x in range(nx)]
               for y in range(ny)]
              for lvl in (0, 1)]
    return packed, nx, ny


def build(name):
    case = R.CASES[name]
    trace_file, route, patch = case[:3]
    speed = case[3] if len(case) > 3 else 10
    trace = R.load_trace(os.path.join(_EVIDENCE, trace_file))
    # The walk has not armed until the route byte is on the wire -- `score()`'s
    # own start index.  Everything before it is the idle the capture led in on.
    first = next(i for i, r in enumerate(trace) if r["c11c"] != 0)
    live = trace[first:]
    # Score it here too, so a fixture can never be written from a capture the
    # transcription does not reproduce.
    ok, total, _prefix, n = R.score(name, verbose=False)
    if ok != total:
        raise SystemExit("%s: %d of %d field-frames -- refusing to bake" % (name, ok, total))

    fields = list(BASE_FIELDS)
    if live[0]["v3c"] is not None:
        fields.append("v3c")
    packed, nx, ny = tile_array("MAP009", patch)
    return {
        "name": name,
        "map": "MAP009",
        "trace": trace_file,
        "speed": speed,
        "start": [2, 11, 0],
        "route": list(route),
        "anim0": live[0]["anim"],
        "landing_frames": 18,
        "size": [nx, ny],
        "tile_fields": list(TILE_FIELDS),
        "tiles": packed,
        "fields": fields,
        "compare_frames": n,
        "frames": [[r[f] for f in fields] for r in live],
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    index = []
    for name in R.CASES:
        fx = build(name)
        path = os.path.join(OUT_DIR, "%s.json" % name)
        with open(path, "w") as fh:
            json.dump(fx, fh, separators=(",", ":"))
        index.append(name)
        print("%-10s %5d live frames, compare %4d, %6.1f KB"
              % (name, len(fx["frames"]), fx["compare_frames"],
                 os.path.getsize(path) / 1024.0))
    with open(os.path.join(OUT_DIR, "index.json"), "w") as fh:
        json.dump({"cases": index}, fh, indent=1)
    print("%d fixtures -> %s" % (len(index), os.path.normpath(OUT_DIR)))


if __name__ == "__main__":
    main()
