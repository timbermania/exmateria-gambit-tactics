#!/usr/bin/env python3
"""Extract the FORMATION-screen glowing blue ORB sprite + CLUT from the ROM.

Every unit cell on the party/formation "sort list" screen carries a small
glowing blue orb; the SELECTED cell's orb pulses (see FORMATION_SCREEN.md
sec 10 for the full static+dynamic RE). The orb is a 12x12 radially-symmetric
sprite (transparent corners, dark-blue rim, bright-cyan core) in the shared
"FRAME sheet" / range-overlay texture that ShiShi exports as RANGEFILE.TGA --
the raw-sector disc asset at LBA 0xE68 +0x1000 (256x256 4bpp) that
parse_range_tiles.py already reads. The orb texel is sub-rect (243,73)-(254,84);
its CLUT is slot 20 of that asset's palette tail (payload offset 0x9280,
byte-verified against the live VRAM CLUT id 0x7F27) -- two slots past the stone
background CLUT parse_formation_background.py reads.

Unlike the opaque background palette, this is a SPRITE CLUT: index 0 is the
transparent slot (the orb's corners), so index 0 is punched out to alpha 0.

On screen the orb is drawn as an ADDITIVE POLY_FT4 (tpage GetTPage(0,1,960,256)
= 0x3F, VRAM (960,256)) whose gouraud colour R=G=B modulates the brightness:
  - non-selected cell: static  clamp(200 - sqrt(dx^2+4*dy^2)/64, 80, 128)
  - selected cell:     that base + a triangle-wave phase in [-40, +41] (+-2/frame)
(from orb_cell_generator @0x80116264 / orb_spatial_falloff @0x80116DD0; the Godot
Formation scene reimplements this, ADR-0001.)

This reuses parse_range_tiles' disc-read helpers so it stays pinned to the same
asset as the background + range tiles.

Output (assets/ui/formation/):
    ORB.tga          12x12 grayscale-indexed sprite (pixel = index*17)
    ORB.palette.tga  16x1 RGBA (the slot-20 orb CLUT; index 0 transparent)
    ORB.json         source LBA/offsets + texel rect + draw/animation note

Usage:
    uv run python tools/parse_formation_orb.py [--iso PATH]
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

# The orb sprite within the 256x256 FRAME/range sheet (12x12).
ORB_X = 243
ORB_Y = 73
ORB_W = 12
ORB_H = 12

# Slot 20 of the asset's palette tail (0x9000 + 20*32 == 0x9280). The stone bg
# is slot 14 (0x91C0); the orb is 6 slots past it. Byte-verified against the
# runtime VRAM CLUT id 0x7F27 (FORMATION_SCREEN.md sec 10.1).
ORB_CLUT_OFFSET = prt.TEXELS_OFFSET + prt.TEXELS_SIZE + 20 * 32  # 0x9280
ORB_CLUT_SLOT = 20


def _texels(asset: bytes) -> bytes:
    return asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]


def decode_orb_indices(asset: bytes) -> np.ndarray:
    """(ORB_H, ORB_W) uint8 palette indices for the orb sub-rect."""
    texels = _texels(asset)
    out = np.empty((ORB_H, ORB_W), np.uint8)
    for ty in range(ORB_H):
        for tx in range(ORB_W):
            out[ty, tx] = prt.nibble(texels, ORB_X + tx, ORB_Y + ty)
    return out


def read_orb_clut(asset: bytes) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for the orb palette."""
    return list(struct.unpack_from("<16H", asset, ORB_CLUT_OFFSET))


def _clut_rgba(asset: bytes) -> np.ndarray:
    """(16, 4) uint8 RGBA for the orb CLUT. Sprite CLUT: index 0 is the
    transparent slot (punched to alpha 0)."""
    words = read_orb_clut(asset)
    rgba = np.zeros((16, 4), np.uint8)
    for i, w in enumerate(words):
        lo, hi = w & 0xFF, (w >> 8) & 0xFF
        rgba[i] = prt.bgr555_to_rgba(lo, hi, index_is_zero=(i == 0))
    return rgba


def decode_orb_rgba(asset: bytes) -> np.ndarray:
    """(ORB_H, ORB_W, 4) uint8 RGBA of the orb under its CLUT (verification)."""
    return _clut_rgba(asset)[decode_orb_indices(asset)]


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

    idx = decode_orb_indices(asset)
    g = (idx.astype(np.uint16) * 17).astype(np.uint8)
    indexed = np.zeros((ORB_H, ORB_W, 4), np.uint8)
    indexed[..., 0] = indexed[..., 1] = indexed[..., 2] = g
    indexed[..., 3] = 255
    _write_tga(out_dir / "ORB.tga", ORB_W, ORB_H, indexed)

    pal = _clut_rgba(asset).reshape(1, 16, 4)
    _write_tga(out_dir / "ORB.palette.tga", 16, 1, pal)

    manifest = {
        "_comment": (
            "FORMATION-screen glowing blue orb. A 12x12 sprite from the shared "
            "FRAME/range sheet (ShiShi RANGEFILE.TGA), drawn additive (tpage "
            "0x3F) over each unit cell. ORB.tga is indexed (pixel = index*17); "
            "recover via int(r/17) and sample ORB.palette.tga (index 0 = "
            "transparent). See FORMATION_SCREEN.md sec 10."
        ),
        "source": {
            "asset": "raw-sector LBA 0xE68 (ShiShi RANGEFILE.TGA / FRAME sheet)",
            "texels_lba": prt.TEXTURE_LBA,
            "texels_asset_offset": prt.TEXELS_OFFSET,
            "sheet_size": [prt.TEX_W, prt.TEX_H],
            "texel_rect": [ORB_X, ORB_Y, ORB_W, ORB_H],
            "clut_asset_offset": ORB_CLUT_OFFSET,
            "clut_slot": ORB_CLUT_SLOT,
            "clut_vram_id": "0x7F27",
        },
        "on_screen": {
            "blend": "additive POLY_FT4, tpage GetTPage(0,1,960,256)=0x3F",
            "vram_tpage": [960, 256],
            "brightness_non_selected": "clamp(200 - sqrt(dx^2+4*dy^2)/64, 80, 128)",
            "brightness_selected": "base + triangle(phase in [-40,+41], +-2/frame)",
            "code": "orb_cell_generator @0x80116264, orb_spatial_falloff @0x80116DD0",
        },
        "indexed_texture": "ORB.tga",
        "palette_texture": "ORB.palette.tga",
    }
    with open(out_dir / "ORB.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract the FFT formation-screen "
                                 "glowing blue orb sprite + CLUT")
    ap.add_argument("--iso", help="raw FFT ISO .bin (default: project-assets)")
    args = ap.parse_args()

    bin_path = prt.iso_path(args.iso)
    if not bin_path.exists():
        print(f"Error: ISO not found at {bin_path}", file=sys.stderr)
        return 1
    asset = prt.read_lba(bin_path, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    out_dir = assets_dir() / "ui" / "formation"
    parse(asset, out_dir)
    print(f"Extracting: formation orb (LBA {prt.TEXTURE_LBA:#x} "
          f"texel {ORB_X},{ORB_Y} {ORB_W}x{ORB_H}, CLUT slot {ORB_CLUT_SLOT})")
    print(f"  -> {out_dir / 'ORB.tga'} + ORB.palette.tga + .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
