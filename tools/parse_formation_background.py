#!/usr/bin/env python3
"""Extract the FORMATION-screen dark cobblestone BACKGROUND tile from the ROM.

The party/formation "sort list" screen fills its backdrop with a single 128x32
stone tile, tiled to 256x240 and darkened by a vertical gouraud gradient (which
is why an on-screen framebuffer patch shows hundreds of colours even though the
source is a 16-colour 4bpp tile). The tile is NOT in FRAME.BIN -- it lives in
the shared "FRAME sheet" / range-overlay texture that ShiShi exports as
RANGEFILE.TGA: the raw-sector disc asset at LBA 0xE68 +0x1000 (256x256 4bpp)
that parse_range_tiles.py already reads. The cobblestone is the sub-rect
(88,216)-(215,247); its CLUT is slot 14 of that asset's palette tail (payload
offset 0x91C0, immediately after the HP/MP/CT bar CLUTs at 0x9160).

This reuses parse_range_tiles' disc-read helpers so the two stay pinned to the
same asset. Output mirrors the ADR-0022 indexed convention (indexed .tga where
pixel = index*17, plus a palette .tga) so the Godot Formation scene tiles the
sheet and recolours it in-shader.

Full RE + provenance: research/working_documents/FORMATION_SCREEN.md sec 0 / 9.

Output (assets/ui/formation/):
    BACKGROUND.tga          128x32 grayscale-indexed tile (pixel = index*17)
    BACKGROUND.palette.tga  16x1 RGBA (the slot-14 stone CLUT; fully opaque --
                            index 0 is real stone, not a transparent slot)
    BACKGROUND.json         source LBA/offsets + tile rect + tiling/gouraud note

Usage:
    uv run python tools/parse_formation_background.py [--iso PATH]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

import parse_range_tiles as prt
from _repo_paths import assets_dir

# The cobblestone tile within the 256x256 FRAME/range sheet.
TILE_X = 88
TILE_Y = 216
TILE_W = 128
TILE_H = 32

# Slot 14 of the asset's palette tail (which starts at TEXELS_OFFSET+TEXELS_SIZE
# = 0x9000; bar CLUTs occupy slots 11-13 @0x9160). == 0x91C0.
STONE_CLUT_OFFSET = prt.TEXELS_OFFSET + prt.TEXELS_SIZE + 14 * 32


def _texels(asset: bytes) -> bytes:
    return asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]


def decode_tile_indices(asset: bytes) -> np.ndarray:
    """(TILE_H, TILE_W) uint8 palette indices for the cobblestone sub-rect."""
    texels = _texels(asset)
    out = np.empty((TILE_H, TILE_W), np.uint8)
    for ty in range(TILE_H):
        for tx in range(TILE_W):
            out[ty, tx] = prt.nibble(texels, TILE_X + tx, TILE_Y + ty)
    return out


def read_stone_clut(asset: bytes) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for the stone palette."""
    return list(struct.unpack_from("<16H", asset, STONE_CLUT_OFFSET))


def _clut_rgba(asset: bytes) -> np.ndarray:
    """(16, 4) uint8 RGBA for the stone CLUT. Unlike a sprite CLUT this is an
    OPAQUE background palette -- index 0 (0x7465) is real stone, not a
    transparent slot -- so every entry keeps its STP-derived alpha (all opaque
    here) and index 0 is NOT punched out."""
    words = read_stone_clut(asset)
    rgba = np.zeros((16, 4), np.uint8)
    for i, w in enumerate(words):
        lo, hi = w & 0xFF, (w >> 8) & 0xFF
        rgba[i] = prt.bgr555_to_rgba(lo, hi, index_is_zero=False)
    return rgba


def decode_tile_rgb(asset: bytes) -> np.ndarray:
    """(TILE_H, TILE_W, 3) uint8 RGB of the tile under its (opaque) stone CLUT.
    Used for grounding/verification, not the emitted asset."""
    return _clut_rgba(asset)[decode_tile_indices(asset)][..., :3]


def _write_tga(path: Path, width: int, height: int, rgba: np.ndarray) -> None:
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0])
    header += struct.pack("<HHHH", 0, 0, width, height)
    header += bytes([32, 0x28])  # top-left origin, 8 alpha bits
    bgra = rgba[..., [2, 1, 0, 3]].astype(np.uint8)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())


def parse(asset: bytes, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)

    idx = decode_tile_indices(asset)
    g = (idx.astype(np.uint16) * 17).astype(np.uint8)
    indexed = np.zeros((TILE_H, TILE_W, 4), np.uint8)
    indexed[..., 0] = indexed[..., 1] = indexed[..., 2] = g
    indexed[..., 3] = 255
    _write_tga(out_dir / "BACKGROUND.tga", TILE_W, TILE_H, indexed)

    pal = _clut_rgba(asset).reshape(1, 16, 4)
    _write_tga(out_dir / "BACKGROUND.palette.tga", 16, 1, pal)

    manifest = {
        "_comment": (
            "FORMATION-screen cobblestone background. A 128x32 tile from the "
            "shared FRAME/range sheet (ShiShi RANGEFILE.TGA), tiled to 256x240 "
            "with a vertical gouraud darkening on screen. BACKGROUND.tga is "
            "indexed (pixel = index*17); recover via int(r*15) and sample "
            "BACKGROUND.palette.tga. See FORMATION_SCREEN.md."
        ),
        "source": {
            "asset": "raw-sector LBA 0xE68 (ShiShi RANGEFILE.TGA / FRAME sheet)",
            "texels_lba": prt.TEXTURE_LBA,
            "texels_asset_offset": prt.TEXELS_OFFSET,
            "sheet_size": [prt.TEX_W, prt.TEX_H],
            "tile_rect": [TILE_X, TILE_Y, TILE_W, TILE_H],
            "clut_asset_offset": STONE_CLUT_OFFSET,
            "clut_slot": 14,
        },
        "on_screen": {
            "tiled_to": [256, 240],
            "shading": "vertical gouraud darken (top brighter)",
        },
        "indexed_texture": "BACKGROUND.tga",
        "palette_texture": "BACKGROUND.palette.tga",
    }
    with open(out_dir / "BACKGROUND.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract the FFT formation-screen "
                                 "cobblestone background tile + CLUT")
    ap.add_argument("--iso", help="raw FFT ISO .bin (default: project-assets)")
    args = ap.parse_args()

    bin_path = prt.iso_path(args.iso)
    if not bin_path.exists():
        print(f"Error: ISO not found at {bin_path}", file=sys.stderr)
        return 1
    asset = prt.read_lba(bin_path, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    out_dir = assets_dir() / "ui" / "formation"
    parse(asset, out_dir)
    print(f"Extracting: formation background (LBA {prt.TEXTURE_LBA:#x} "
          f"tile {TILE_X},{TILE_Y} {TILE_W}x{TILE_H}, CLUT slot 14)")
    print(f"  -> {out_dir / 'BACKGROUND.tga'} + BACKGROUND.palette.tga + .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
