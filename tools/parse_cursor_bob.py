#!/usr/bin/env python3
"""
Cursor-bob table parser — the ROM-faithful at-rest cursor oscillation (ADR-0046).

FFT does not synthesize a cursor's bob from a curve; it reads the vertical offset
from tables the game ships. There are two distinct encodings, and they are NOT
interchangeable (see CONTEXT.md "Cursor bob"):

- **Tile cursor** (the on-grid knife/dagger), from BATTLE.BIN's battle overlay
  (`FUN_8007e304`, the tile-cursor sprite renderer). A pair of parallel 8-entry
  tables — an OFFSET table (`{0,1,2,3,5,3,2,1}`, in FFT units where 1 tile = 28)
  and a HOLD table (frames to dwell on each step, `{16,8,2,2,6,4,4,10}`). Both
  are arrays of int32 little-endian. One phase index (0..7) walks the steps; a
  per-step frame accumulator advances it. The motion is one-sided from the
  resting pose (16-frame dwell at offset 0, single excursion to 5, return).

- **Glove cursor** (the world-map / menu hand cursor), from WORLD.BIN. A different
  encoding: `[threshold, offset]` byte-pairs, 0-terminated (a threshold of 0
  ends the table), indexed by a modulo timer. Offsets are SIGNED (can go
  negative). Separate idle + select tables.

Bases (offset = VA − base):
- BATTLE.BIN overlay @ 0x80067000 → offset table @ file 0x798, hold @ 0x7b8.
- WORLD.BIN overlay @ 0x800E0000 → glove idle @ file 0x76352, select @ 0x76362.

Output: TWO files, one per consuming system, format-preserving (each table kept
in its native shape so faithfulness stays provable against the disassembly):

- `addons/exmateria_battlefield/cursor/tile_knife.json` — `tile_knife`, read by `Battlefield`
  (`TileCursorBob`, for `TileCursor`).
- `assets/sprites/glove_cursor.json` — `glove_idle` + `glove_select`, read by
  `UI` (`GloveCursorBob`, for the six `src/ui3/detail/` menus).

They were ONE file (`cursor_bob.json`) until extraction #3 pass 4. The two halves
share no code and no reader, but a single asset forced both systems to name the
same `res://` path — a duplication no instrument scores, because each system
still shows exactly one outbound reference to an unbucketed asset. Splitting the
data is what makes the seam real (ADR-0159 dec. 4 as amended). One generator
still writes both: the ROM is one source, so faithfulness stays single-sourced.

Usage (uv is mandatory — deps live in tools/pyproject.toml):
    uv run python tools/parse_cursor_bob.py
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

from _repo_paths import battle_bin as _battle_bin, world_bin as _world_bin

# =============================================================================
# Memory layout — bases and the table virtual addresses (ADR-0046)
# =============================================================================

# BATTLE.BIN battle overlay: VA 0x80067000 maps to file offset 0.
BATTLE_BASE = 0x80067000
TILE_OFFSET_VA = 0x80067798  # offset table: {0,1,2,3,5,3,2,1}
TILE_HOLD_VA = 0x800677B8    # hold   table: {16,8,2,2,6,4,4,10}
TILE_STEP_COUNT = 8          # parallel 8-entry tables
TILE_UNIT = 28               # 0x1c — one tile in FFT cursor-Y units (Godot /28)

# WORLD.BIN world overlay: VA 0x800E0000 maps to file offset 0.
WORLD_BASE = 0x800E0000
GLOVE_IDLE_VA = 0x80156352
GLOVE_SELECT_VA = 0x80156362

# Defaults resolve to project-assets/fft-extract via the shared helper.
DEFAULT_BATTLE_PATH = _battle_bin()
DEFAULT_WORLD_PATH = _world_bin()
_SPRITES = Path(__file__).parent.parent / "assets" / "sprites"
# 🔴 THE KNIFE TABLE MOVED INTO THE ADDON AND THIS DEFAULT HAD TO MOVE WITH IT
# (ADR-0202 dec. 5 Class A). `TileCursorBob.gd` reads
# `res://addons/exmateria_battlefield/cursor/tile_knife.json`; a generator still
# writing to `assets/sprites/` would leave a stale copy at the old path and a
# never-refreshed one at the new, with nothing failing to say so. The glove half
# stays put — `UI` reads it, and only `Battlefield` was extracted.
_KNIFE_HOME = (Path(__file__).parent.parent / "addons" / "exmateria_battlefield"
               / "cursor")
DEFAULT_KNIFE_OUTPUT = _KNIFE_HOME / "tile_knife.json"
DEFAULT_GLOVE_OUTPUT = _SPRITES / "glove_cursor.json"


def _file_off(va: int, base: int) -> int:
    return va - base


def parse_tile_table(battle: bytes) -> dict:
    """The tile-cursor step table — parallel int32 offset + hold arrays."""
    off_at = _file_off(TILE_OFFSET_VA, BATTLE_BASE)
    hold_at = _file_off(TILE_HOLD_VA, BATTLE_BASE)
    offsets = list(struct.unpack_from("<%di" % TILE_STEP_COUNT, battle, off_at))
    holds = list(struct.unpack_from("<%di" % TILE_STEP_COUNT, battle, hold_at))
    return {
        "format": "step_table",
        "source": {
            "binary": "BATTLE.BIN",
            "function": "FUN_8007e304",
            "offset_table_va": "0x%08X" % TILE_OFFSET_VA,
            "hold_table_va": "0x%08X" % TILE_HOLD_VA,
        },
        "tile_unit": TILE_UNIT,  # divide an offset by this for Godot world units (1 tile = 1 unit)
        "offsets": offsets,      # FFT cursor-Y units; one-sided from rest (offset 0)
        "holds": holds,          # frames to dwell on each step (parallel to offsets)
    }


def parse_glove_table(world: bytes, va: int, name: str) -> dict:
    """A glove-cursor table — `[threshold, signed offset]` pairs, 0-terminated.

    The threshold byte is a cumulative modulo-timer position; the offset byte is
    a SIGNED vertical step. A threshold of 0 terminates the table.
    """
    at = _file_off(va, WORLD_BASE)
    pairs: list[list[int]] = []
    i = at
    while True:
        threshold = world[i]
        if threshold == 0:
            break  # 0-terminated
        offset = struct.unpack_from("<b", world, i + 1)[0]  # signed int8
        pairs.append([threshold, offset])
        i += 2
    return {
        "format": "threshold_pairs",
        "source": {
            "binary": "WORLD.BIN",
            "table_va": "0x%08X" % va,
            "table": name,
        },
        "pairs": pairs,  # [threshold, signed offset]; modulo-timer indexed
    }


def parse_cursor_bob(battle_path: Path, world_path: Path) -> tuple[dict, dict]:
    """Return `(knife_doc, glove_doc)` — one document per consuming system.

    Kept as two returns rather than one dict the caller slices, so that adding a
    third table forces a decision about which file it belongs in instead of
    silently landing in both.
    """
    with open(battle_path, "rb") as f:
        battle = f.read()
    with open(world_path, "rb") as f:
        world = f.read()
    knife = {"tile_knife": parse_tile_table(battle)}
    glove = {
        "glove_idle": parse_glove_table(world, GLOVE_IDLE_VA, "idle"),
        "glove_select": parse_glove_table(world, GLOVE_SELECT_VA, "select"),
    }
    return knife, glove


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="Parse FFT cursor-bob step tables from BATTLE.BIN + WORLD.BIN (ADR-0046)",
    )
    parser.add_argument("--battle", type=Path, default=DEFAULT_BATTLE_PATH,
                        help=f"Path to BATTLE.BIN (default: {DEFAULT_BATTLE_PATH})")
    parser.add_argument("--world", type=Path, default=DEFAULT_WORLD_PATH,
                        help=f"Path to WORLD.BIN (default: {DEFAULT_WORLD_PATH})")
    parser.add_argument("--knife-output", type=Path, default=DEFAULT_KNIFE_OUTPUT,
                        help=f"Tile-knife JSON, read by Battlefield (default: {DEFAULT_KNIFE_OUTPUT})")
    parser.add_argument("--glove-output", type=Path, default=DEFAULT_GLOVE_OUTPUT,
                        help=f"Glove JSON, read by UI (default: {DEFAULT_GLOVE_OUTPUT})")
    args = parser.parse_args()

    if not args.battle.exists():
        print(f"Error: BATTLE.BIN not found: {args.battle}")
        return 1
    if not args.world.exists():
        print(f"Error: WORLD.BIN not found: {args.world}")
        return 1

    knife, glove = parse_cursor_bob(args.battle, args.world)

    for path, doc in ((args.knife_output, knife), (args.glove_output, glove)):
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(doc, f, indent=2)
            f.write("\n")
        print(f"Wrote {path}")

    tile = knife["tile_knife"]
    print(f"  tile_knife: offsets={tile['offsets']} holds={tile['holds']} "
          f"(cycle={sum(tile['holds'])} frames)")
    print(f"  glove_idle:   {len(glove['glove_idle']['pairs'])} pairs {glove['glove_idle']['pairs']}")
    print(f"  glove_select: {len(glove['glove_select']['pairs'])} pairs {glove['glove_select']['pairs']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
