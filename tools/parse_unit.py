"""Decode EVENT/UNIT.BIN -> the FORMATION-screen unit sprite atlas + palettes.

UNIT.BIN is the sprite sheet the party/formation "sort list" screen blits its
small unit poses from (one pose per class + monsters, plus a handful of UI
strings and panel bits packed into the sheet). It is NOT a per-unit metadata
struct, and the poses are NOT assembled at runtime from the full battle .SPR
sheets -- they are this single, pre-authored, self-contained atlas. See
FORMATION_SCREEN.md for how this corrects the earlier dynamic-only reading.

Layout (byte-verified vs the real UNIT.BIN; the palette table is located by the
0x0000 transparent-index-0 word every FFT sprite CLUT starts with):

    pixels   0x0000 .. 0xF000   256 x 480, 4bpp, low-nibble-first  (61440 B)
    palettes 0xF000 .. 0x10000  128 x (16 x BGR555 LE)             ( 4096 B)

Each of the 128 CLUTs recolours the shared shapes for a class/team; 122 carry
real colour (6 are empty tail slots). The pose->palette mapping and the per-cell
grid within the atlas are game-logic driven and tracked as open follow-ups in
the living doc -- this extractor emits the faithful indexed atlas + full palette
bank and leaves palette selection to the consumer (mirrors the ADR-0022 body
SPR convention: indexed .tga where pixel = index*17, plus a palette .tga).

Output (assets/ui/formation/):
    UNIT.tga          256x480 grayscale-indexed atlas (pixel = index*17;
                      shader recovers index via int(r * 15.0))
    UNIT.palette.tga  16 x 128 RGBA -- col = index 0-15, row = palette 0-127
                      (shader samples vec2(index/15.0, row/127.0), nearest)
    UNIT.json         format constants + palette-populated flags manifest

Usage:
    uv run python tools/parse_unit.py [fft-extract-path]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

from _repo_paths import assets_dir, event_dir

FILE_SIZE = 0x10000        # 65536

WIDTH = 256
HEIGHT = 480
PIXEL_BYTES = WIDTH * HEIGHT // 2   # 0xF000, 61440

PALETTE_BASE = PIXEL_BYTES          # 0xF000
NUM_PALETTES = 128
PALETTE_COLORS = 16
PALETTE_BYTES = PALETTE_COLORS * 2  # 32


def palette_offset(index: int) -> int:
    """Byte offset of CLUT `index` (0-127) in UNIT.BIN."""
    return PALETTE_BASE + index * PALETTE_BYTES


def read_clut(data: bytes, index: int) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for palette `index`."""
    return list(struct.unpack_from("<16H", data, palette_offset(index)))


def decode_indices(data: bytes) -> np.ndarray:
    """Decode the 4bpp pixel region to a (HEIGHT, WIDTH) uint8 index array.

    Low nibble = left pixel, high nibble = right pixel."""
    flat = np.frombuffer(data[:PIXEL_BYTES], np.uint8)
    inter = np.empty(flat.size * 2, np.uint8)
    inter[0::2] = flat & 0x0F
    inter[1::2] = (flat >> 4) & 0x0F
    return inter.reshape(HEIGHT, WIDTH)


def bgr555_to_rgba(color16: int) -> tuple[int, int, int, int]:
    """BGR555 (bit15=STP, 0-4=R, 5-9=G, 10-14=B) -> RGBA. Index-0 handling is
    the caller's job; here a raw 0x0000 word decodes to opaque black."""
    r = (color16 & 0x1F) * 8
    g = ((color16 >> 5) & 0x1F) * 8
    b = ((color16 >> 10) & 0x1F) * 8
    a = 128 if (color16 >> 15) & 1 else 255
    return (r, g, b, a)


def _write_tga(path: Path, width: int, height: int, rgba: np.ndarray) -> None:
    """Write a 32-bit top-left-origin RGBA TGA (BGRA on disc)."""
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0])
    header += struct.pack("<HHHH", 0, 0, width, height)
    header += bytes([32, 0x28])
    bgra = rgba[..., [2, 1, 0, 3]].astype(np.uint8)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())


def build_indexed_tga(idx: np.ndarray) -> np.ndarray:
    """Grayscale-indexed atlas: pixel = index*17 in RGB, opaque alpha (the
    shader recovers the index; transparency is decided by CLUT index 0)."""
    g = (idx.astype(np.uint16) * 17).astype(np.uint8)
    out = np.zeros((HEIGHT, WIDTH, 4), np.uint8)
    out[..., 0] = out[..., 1] = out[..., 2] = g
    out[..., 3] = 255
    return out


def build_palette_tga(data: bytes) -> np.ndarray:
    """16 x 128 RGBA palette bank: col = index 0-15, row = palette 0-127. Index
    0 is written fully transparent (the FFT transparent-index convention)."""
    out = np.zeros((NUM_PALETTES, PALETTE_COLORS, 4), np.uint8)
    for p in range(NUM_PALETTES):
        for i, word in enumerate(read_clut(data, p)):
            r, g, b, a = bgr555_to_rgba(word)
            out[p, i] = (r, g, b, 0 if i == 0 else a)
    return out


def parse(input_path: Path, out_dir: Path) -> dict:
    data = input_path.read_bytes()
    if len(data) != FILE_SIZE:
        raise ValueError(f"UNIT.BIN is {len(data)} bytes, expected {FILE_SIZE}")

    out_dir.mkdir(parents=True, exist_ok=True)
    idx = decode_indices(data)
    _write_tga(out_dir / "UNIT.tga", WIDTH, HEIGHT, build_indexed_tga(idx))
    pal_rgba = build_palette_tga(data)
    _write_tga(out_dir / "UNIT.palette.tga", PALETTE_COLORS, NUM_PALETTES, pal_rgba)

    populated = [
        p for p in range(NUM_PALETTES)
        if any(w != 0 for w in read_clut(data, p)[1:])
    ]
    manifest = {
        "_comment": (
            "FORMATION-screen sprite atlas from EVENT/UNIT.BIN. UNIT.tga is a "
            "256x480 indexed atlas (pixel = index*17); UNIT.palette.tga is a "
            "16x128 RGBA palette bank (row = palette 0-127). Pose->palette and "
            "per-cell grid are open follow-ups -- see FORMATION_SCREEN.md."
        ),
        "source": "EVENT/UNIT.BIN",
        "width": WIDTH,
        "height": HEIGHT,
        "bpp": 4,
        "pixel_bytes": PIXEL_BYTES,
        "num_palettes": NUM_PALETTES,
        "palette_colors": PALETTE_COLORS,
        "populated_palettes": populated,
        "indexed_texture": "UNIT.tga",
        "palette_texture": "UNIT.palette.tga",
    }
    with open(out_dir / "UNIT.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> None:
    from _repo_paths import fft_extract_root as _fft_extract_root
    parser = argparse.ArgumentParser(description="Extract FFT EVENT/UNIT.BIN "
                                     "formation sprite atlas + palettes")
    default = _fft_extract_root()
    parser.add_argument("fft_path", nargs="?", default=str(default),
                        help=f"FFT extract directory (default: {default})")
    args = parser.parse_args()

    input_path = Path(args.fft_path) / "EVENT" / "UNIT.BIN"
    if not input_path.exists():
        # Allow the default-resolved event_dir() too.
        input_path = event_dir() / "UNIT.BIN"
    if not input_path.exists():
        print(f"Error: UNIT.BIN not found at {input_path}")
        sys.exit(1)

    out_dir = assets_dir() / "ui" / "formation"
    manifest = parse(input_path, out_dir)
    print(f"Extracting: {input_path.name} ({FILE_SIZE} bytes)")
    print(f"  {WIDTH}x{HEIGHT} 4bpp atlas -> {out_dir / 'UNIT.tga'}")
    print(f"  {NUM_PALETTES} palettes ({len(manifest['populated_palettes'])} "
          f"populated) -> {out_dir / 'UNIT.palette.tga'}")
    print(f"  manifest -> {out_dir / 'UNIT.json'}")


if __name__ == "__main__":
    main()
