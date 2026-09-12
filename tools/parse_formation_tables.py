#!/usr/bin/env python3
"""
Formation-screen ROM data tables — parsed from WORLD.BIN, not hand-transcribed.

Following ADR-0046 (a ROM step-table is the truth — parse it, don't invent it):
the formation/roster ("sort list") overlay ships small constant tables the screen
reads verbatim. This parser lifts them straight from the disc so the Godot port
consumes the bytes instead of a transcription that can silently drift.

Tables (WORLD.BIN world overlay; offset = VA − base, base 0x800E0000 per ADR-0046):

- **box_trail_fade** — the gold selection-box glide TRAIL fade ramp
  (`0x8018C88C`, FORMATION_SCREEN.md §11.5.3). The box leaves an 8-slot
  position-history trail as it eases to a new unit; each slot's box is drawn at a
  per-slot GREY brightness MULTIPLY (NOT a CLUT ramp — the CLUT stays 0x7F65).
  8 × uint8, slot0 (oldest / dimmest) → slot7 (newest / full = 128 = PSX gouraud
  identity): {20,35,50,65,80,90,100,128}. Consumed by
  FormationScene._update_box_trail as ramp[slot]/128 × the box level.

Output: assets/ui/formation/formation_tables.json — each table kept in its native
shape (a flat uint8 array here) with its source VA so faithfulness stays provable
against the disassembly.

Usage (uv is mandatory — deps live in tools/pyproject.toml):
    uv run python tools/parse_formation_tables.py
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

from _repo_paths import world_bin as _world_bin

# =============================================================================
# Memory layout — WORLD.BIN world overlay base + table virtual addresses.
# VA 0x800E0000 maps to file offset 0 (ADR-0046 / cursor_bob glove tables).
# =============================================================================
WORLD_BASE = 0x800E0000

# Gold-box glide TRAIL fade ramp: 8 × uint8, per-slot grey MULT (§11.5.3).
BOX_TRAIL_FADE_VA = 0x8018C88C
BOX_TRAIL_FADE_COUNT = 8

DEFAULT_WORLD_PATH = _world_bin()
DEFAULT_OUTPUT = Path(__file__).parent.parent / "assets" / "ui" / "formation" / "formation_tables.json"


def _file_off(va: int, base: int = WORLD_BASE) -> int:
    return va - base


def parse_box_trail_fade(world: bytes) -> dict:
    """The 8-entry box-trail fade ramp — a flat uint8 array (grey multiply / 128)."""
    at = _file_off(BOX_TRAIL_FADE_VA)
    ramp = list(struct.unpack_from("<%dB" % BOX_TRAIL_FADE_COUNT, world, at))
    return {
        "format": "uint8_ramp",
        "source": {
            "binary": "WORLD.BIN",
            "table_va": "0x%08X" % BOX_TRAIL_FADE_VA,
            "reference": "FORMATION_SCREEN.md §11.5.3",
        },
        "identity": 128,   # slot7 = full brightness (PSX gouraud identity); divide by this
        "ramp": ramp,      # slot0 (oldest/dimmest) .. slot7 (newest/full)
    }


def parse_formation_tables(world_path: Path) -> dict:
    with open(world_path, "rb") as f:
        world = f.read()
    return {
        "box_trail_fade": parse_box_trail_fade(world),
    }


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="Parse FFT formation-screen data tables from WORLD.BIN (ADR-0046)",
    )
    parser.add_argument("--world", type=Path, default=DEFAULT_WORLD_PATH,
                        help=f"Path to WORLD.BIN (default: {DEFAULT_WORLD_PATH})")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help=f"Output JSON (default: {DEFAULT_OUTPUT})")
    args = parser.parse_args()

    if not args.world.exists():
        print(f"Error: WORLD.BIN not found: {args.world}")
        return 1

    data = parse_formation_tables(args.world)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"Wrote {args.output}")
    print(f"  box_trail_fade: ramp={data['box_trail_fade']['ramp']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
