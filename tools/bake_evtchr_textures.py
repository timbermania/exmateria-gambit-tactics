"""Bake EVTCHR.BIN segments to indexed-grayscale TGA + 16-row palette TGA.

The Godot side renders cinematic sprites through the same paletted shader the
normal unit BODY layer uses (ADR-0022): `type1_tex` is an indexed-grayscale
TGA where each pixel value = palette index × 17 (R = G = B = index*17), and
`type1_palette` is a 16x16 RGBA TGA with one palette row per Y. This baker
converts each EVTCHR segment to that pair so `SpriteLayerManager` can swap
the unit's BODY texture to the cinematic atlas mid-cinematic.

Output (one pair per segment):
    assets/sprites/textures/evtchr/segment_{NNN}.tga          # 256x200 indexed
    assets/sprites/textures/evtchr/segment_{NNN}.palette.tga  # 16x16 RGBA

Authority for the index*17 / 16x16 palette convention: `extract_spr.py`'s
`extract_spr_indexed` (BODY-sprite path). EVTCHR layouts (pixel + palette
offsets) come from `parse_evtchr.py`.

Usage:
    uv run python tools/bake_evtchr_textures.py            # bake all 137
    uv run python tools/bake_evtchr_textures.py --segment 0  # just segment 0
"""

from __future__ import annotations

import argparse
from pathlib import Path

from _repo_paths import event_dir, assets_dir
from extract_spr import write_tga
import parse_evtchr as pev


DEFAULT_EVTCHR_PATH = event_dir() / "EVTCHR.BIN"
DEFAULT_OUTPUT_DIR = assets_dir("sprites/textures") / "evtchr"

# EVTCHR pixel-page dimensions (per parse_evtchr.PIXEL_BYTES = 25_600 = 256x200/2).
WIDTH = 256
HEIGHT = 200


def bake_segment(segment: pev.Segment, seg_id: int, out_dir: Path) -> tuple[Path, Path]:
    """Write a (segment_NNN.tga, segment_NNN.palette.tga) pair for one segment.

    Returns the (indexed_path, palette_path) pair that was written.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    indexed_path = out_dir / f"segment_{seg_id:03d}.tga"
    palette_path = out_dir / f"segment_{seg_id:03d}.palette.tga"

    # Indexed pixels: each EVTCHR pixel is a 4-bit palette index. The shader
    # decodes as `int(pixel.r * 15.0)`, so we encode index N as R=G=B=N*17.
    indices = list(pev.decode_pixels(segment.pixels))

    # Sentinel bottom row: the ROM page's very last row (y=HEIGHT-1) is a solid
    # index-15 filler line in EVERY segment (verified at the ROM level: row 199 =
    # index 15 across all 256 columns; row 198 is content/transparent). It is not
    # character art — an otherwise-empty segment still carries it. Frame rects that
    # reach the page bottom (the only chapel example is Ramza's kneel, rect_y=160
    # h=40 → rows 160..199) would sample it as a bright tan line along the sprite's
    # bottom edge. Neutralize it to index 0, which the unit shader treats as the
    # transparent color (add_tile_paletted: "index 0 is the transparent color").
    last_row = WIDTH * (HEIGHT - 1)
    for i in range(last_row, WIDTH * HEIGHT):
        indices[i] = 0

    indexed_pixels = [(idx * 17, idx * 17, idx * 17, 255) for idx in indices]
    write_tga(str(indexed_path), WIDTH, HEIGHT, indexed_pixels)

    # 16x16 palette TGA — one row per palette, 16 colors each. Row Y =
    # palette index Y, column X = color index X. The shader samples via
    # vec2(index/15.0, body_palette_row/15.0) under filter_nearest, so empty
    # cells just need to be opaque-zero (a transparent default would leak
    # through into legitimate palette-0 samples).
    palette_pixels = []
    for row in range(16):
        rgb_palette = pev.decode_palette(segment.palettes[row])
        for col in range(16):
            r, g, b = rgb_palette[col]
            palette_pixels.append((r, g, b, 255))
    write_tga(str(palette_path), 16, 16, palette_pixels)

    return indexed_path, palette_path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--input", type=Path, default=DEFAULT_EVTCHR_PATH)
    ap.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    ap.add_argument(
        "--segment", type=int, default=None,
        help="Bake only this segment id (default: all 137).",
    )
    args = ap.parse_args()

    atlas = pev.parse_evtchr(args.input)
    ids = [args.segment] if args.segment is not None else range(len(atlas.segments))

    for seg_id in ids:
        idx_path, pal_path = bake_segment(atlas.segments[seg_id], seg_id, args.output_dir)
        print(f"  wrote {idx_path.name} + {pal_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
