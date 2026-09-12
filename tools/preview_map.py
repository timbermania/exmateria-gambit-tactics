#!/usr/bin/env python3
"""Print an ASCII walkability + height preview of a parsed FFT map.

Used by gambit-scenario authors to pick spawn coordinates without launching
Godot. Reads `assets/maps/<MAP_ID>/terrain.json` (level_0 only — the runtime
ignores level_1; see DynamicTerrainBuilder.gd) and prints:

  - a walkability grid: `.` = walkable, `#` = impassable
  - a height grid: `0`-`9` per tile, with `+` denoting tiles clamped from
    a true height > 9 (footer reports the true max)

Tile coordinates match the scenario authoring convention used in
`tests/gambit_scenarios/`: `tile: [x, z]`. Rows are printed top-to-bottom in
ascending z (z=0 at top); columns left-to-right in ascending x. A column
ruler is printed above each grid to make picking [x, z] coordinates direct.

Usage:
    uv run python tools/preview_map.py MAP042
    uv run python tools/preview_map.py MAP075
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MAPS_DIR = Path(__file__).resolve().parent.parent / "assets" / "maps"


def load_terrain(map_id: str) -> dict:
    map_dir = MAPS_DIR / map_id
    terrain_path = map_dir / "terrain.json"
    if not terrain_path.is_file():
        if not map_dir.is_dir():
            raise FileNotFoundError(f"no such map: {map_id} (looked under {MAPS_DIR})")
        raise FileNotFoundError(f"{map_id}/terrain.json is missing — re-run tools/parse_all_maps.py")
    with terrain_path.open() as f:
        return json.load(f)


def build_grids(terrain: dict) -> tuple[list[list[str]], list[list[str]], int]:
    """Return (walk_grid, height_grid, true_max_height).

    Each grid is a list of rows in ascending z, each row a list of single-char
    cells in ascending x. Walkability is read directly from the `impassable`
    field — the same field DynamicTerrainBuilder.gd surfaces to Tile.gd.
    Heights are clamped to 0-9 for display; cells where the true height
    exceeded 9 use `+` so the clamp is visible per-tile.
    """
    info = terrain["terrain"]
    size_x = int(info["size_x"])
    size_z = int(info["size_z"])
    level_0 = info["level_0"]

    walk_grid: list[list[str]] = []
    height_grid: list[list[str]] = []
    true_max = 0
    for z in range(size_z):
        row = level_0[z]
        walk_row: list[str] = []
        height_row: list[str] = []
        for x in range(size_x):
            tile = row[x]
            walk_row.append("#" if tile.get("impassable", False) else ".")
            h = int(tile.get("height", 0))
            true_max = max(true_max, h)
            if h > 9:
                height_row.append("+")
            else:
                height_row.append(str(h))
        walk_grid.append(walk_row)
        height_grid.append(height_row)
    return walk_grid, height_grid, true_max


def format_grid(title: str, grid: list[list[str]], size_x: int) -> str:
    """Render one grid with an x-ruler header and z-column row labels."""
    lines: list[str] = [title]
    # Column ruler: tens digit then ones digit, suppressed below 10 if narrow.
    if size_x >= 10:
        tens = "    " + "".join(str(x // 10) if x >= 10 else " " for x in range(size_x))
        lines.append(tens)
    ones = "  x:" + "".join(str(x % 10) for x in range(size_x))
    lines.append(ones)
    for z, row in enumerate(grid):
        lines.append(f"{z:>3} {''.join(row)}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
            description="ASCII walkability + height preview of a parsed FFT map.",
            formatter_class=argparse.RawDescriptionHelpFormatter,
            epilog="Reads assets/maps/<MAP_ID>/terrain.json (level_0 only).")
    parser.add_argument("map_id", help="map id, e.g. MAP042")
    args = parser.parse_args(argv)

    try:
        terrain = load_terrain(args.map_id)
    except FileNotFoundError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    info = terrain["terrain"]
    size_x = int(info["size_x"])
    size_z = int(info["size_z"])
    walk, heights, true_max = build_grids(terrain)

    impassable_count = sum(row.count("#") for row in walk)
    total_tiles = size_x * size_z

    print(f"{args.map_id} — {size_x} x {size_z} tiles ({total_tiles} total)")
    print()
    print(format_grid("Walkability (. = walkable, # = impassable):", walk, size_x))
    print()
    print(format_grid("Heights (0-9 raw, + = clamped above 9):", heights, size_x))
    print()
    footer_bits = [f"impassable: {impassable_count}/{total_tiles}",
                   f"height range: 0-{true_max}"]
    if true_max > 9:
        footer_bits.append(f"clamped {sum(1 for row in heights for c in row if c == '+')} tile(s) (shown as +)")
    print("Summary: " + ", ".join(footer_bits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
