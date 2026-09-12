#!/usr/bin/env python3
"""Extract the FORMATION-screen gold selection BOX (¼ texel + CLUT) from the ROM.

On the party/formation "sort list" screen the SELECTED unit gets a gold
isometric diamond frame at its feet (the battle move/target tile-cursor reused
on the roster; FORMATION_SCREEN.md §11 for the full static+dynamic RE). Only a
QUARTER of the diamond is stored on disc -- one gold diagonal edge on a
transparent field -- which the builder (`FUN_8011712c`) mirrors x / y / xy into
the four quadrants, each drawn twice (additive tpage 0x3F + subtractive 0x5F)
for the classic FFT gold shimmer.

Two ROM sources (both ADR-0001-clean; never a savestate/VRAM dump):

  * TEXEL -- the ¼ diamond at rect (216,216)-(247,231) (32x16, 4bpp) of the
    shared "FRAME sheet" / range-overlay texture (ShiShi RANGEFILE.TGA), the
    raw-sector disc asset parse_range_tiles.py reads at LBA 0xE68 +0x1000. This
    is the SAME sheet parse_formation_orb.py pulls the orb from.

  * CLUT -- the 16-colour gold gradient (VRAM clut-id 0x7F65). It is NOT in the
    range sheet's palette tail (unlike the orb's 0x9280); it lives in the roster
    world-map overlay WORLD/WORLD.BIN at 0x8018B9A4 (file offset 0xAB9A4), right
    beside the §13 sprite-selection tables parse_roster_selection.py reads -- the
    same overlay whose code builds the box. idx0=(0,0,0) is the transparent slot;
    idx1=(255,222,123) brightest gold; idx15=(8,0,0) the near-black interior fill.
    (The exact LoadImage upload offset is still unpinned -- §11.5 B3 -- but these
    bytes are byte-identical in the overlay that renders the box, so it is a
    faithful static source.)

Output (assets/ui/formation/):
    BOX.tga          32x16 grayscale-indexed ¼ texel (pixel = index*17)
    BOX.palette.tga  16x1 RGBA (the gold CLUT; index 0 transparent)
    BOX.json         source LBA/offsets + texel rect + the 4-quadrant mirror /
                     dual-pass draw note the Godot scene reimplements.

Usage:
    uv run python tools/parse_formation_box.py [--iso PATH]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

import parse_range_tiles as prt
from _repo_paths import assets_dir, world_bin

# The ¼-diamond texel within the 256x256 FRAME/range sheet (32x16). One gold
# diagonal edge on transparent field; the scene mirrors it 4 ways (§11.2).
BOX_X = 216
BOX_Y = 216
BOX_W = 32
BOX_H = 16

# The gold CLUT (clut-id 0x7F65) inside the roster overlay WORLD/WORLD.BIN.
# 0x8018B9A4 in overlay space (base 0x800E0000) -> file offset 0xAB9A4.
WORLD_OVERLAY_BASE = 0x800E0000
BOX_CLUT_ADDR = 0x8018B9A4
BOX_CLUT_OFFSET = BOX_CLUT_ADDR - WORLD_OVERLAY_BASE  # 0xAB9A4
BOX_CLUT_VRAM_ID = "0x7F65"


def _texels(asset: bytes) -> bytes:
    return asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]


def decode_box_indices(asset: bytes) -> np.ndarray:
    """(BOX_H, BOX_W) uint8 palette indices for the ¼-diamond sub-rect."""
    texels = _texels(asset)
    out = np.empty((BOX_H, BOX_W), np.uint8)
    for ty in range(BOX_H):
        for tx in range(BOX_W):
            out[ty, tx] = prt.nibble(texels, BOX_X + tx, BOX_Y + ty)
    return out


def read_box_clut(world: bytes) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for the gold box palette,
    read from WORLD.BIN at BOX_CLUT_OFFSET."""
    return list(struct.unpack_from("<16H", world, BOX_CLUT_OFFSET))


def _clut_rgba(world: bytes) -> np.ndarray:
    """(16, 4) uint8 RGBA for the gold box CLUT. Sprite CLUT: index 0 is the
    transparent slot (the diamond's exterior corners) punched to alpha 0. The
    idx15 interior fill stays opaque (§11.3)."""
    words = read_box_clut(world)
    rgba = np.zeros((16, 4), np.uint8)
    for i, w in enumerate(words):
        lo, hi = w & 0xFF, (w >> 8) & 0xFF
        rgba[i] = prt.bgr555_to_rgba(lo, hi, index_is_zero=(i == 0))
    return rgba


def decode_box_rgba(asset: bytes, world: bytes) -> np.ndarray:
    """(BOX_H, BOX_W, 4) uint8 RGBA of the ¼ texel under its CLUT (verification)."""
    return _clut_rgba(world)[decode_box_indices(asset)]


def _write_tga(path: Path, width: int, height: int, rgba: np.ndarray) -> None:
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0])
    header += struct.pack("<HHHH", 0, 0, width, height)
    header += bytes([32, 0x28])  # top-left origin, 8 alpha bits
    bgra = rgba[..., [2, 1, 0, 3]].astype(np.uint8)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())


def parse(asset: bytes, world: bytes, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)

    idx = decode_box_indices(asset)
    g = (idx.astype(np.uint16) * 17).astype(np.uint8)
    indexed = np.zeros((BOX_H, BOX_W, 4), np.uint8)
    indexed[..., 0] = indexed[..., 1] = indexed[..., 2] = g
    indexed[..., 3] = 255
    _write_tga(out_dir / "BOX.tga", BOX_W, BOX_H, indexed)

    pal = _clut_rgba(world).reshape(1, 16, 4)
    _write_tga(out_dir / "BOX.palette.tga", 16, 1, pal)

    manifest = {
        "_comment": (
            "FORMATION-screen gold selection box. A 32x16 QUARTER diamond from "
            "the shared FRAME/range sheet (ShiShi RANGEFILE.TGA); the scene "
            "mirrors it x/y/xy into 4 quadrants, each drawn twice (additive tpage "
            "0x3F + subtractive 0x5F). Drawn on the SELECTED cell only. BOX.tga is "
            "indexed (pixel = index*17); recover via int(r/17) and sample "
            "BOX.palette.tga (index 0 = transparent). See FORMATION_SCREEN.md §11."
        ),
        "texel_source": {
            "asset": "raw-sector LBA 0xE68 (ShiShi RANGEFILE.TGA / FRAME sheet)",
            "texels_lba": prt.TEXTURE_LBA,
            "texels_asset_offset": prt.TEXELS_OFFSET,
            "sheet_size": [prt.TEX_W, prt.TEX_H],
            "texel_rect": [BOX_X, BOX_Y, BOX_W, BOX_H],
        },
        "clut_source": {
            "asset": "WORLD/WORLD.BIN (roster overlay @0x800E0000)",
            "overlay_addr": BOX_CLUT_ADDR,
            "file_offset": BOX_CLUT_OFFSET,
            "clut_vram_id": BOX_CLUT_VRAM_ID,
            "note": ("Beside the §13 selection tables; exact LoadImage upload "
                     "offset unpinned (§11.5 B3) but byte-identical here."),
        },
        "on_screen": {
            "quadrants": "4 (x/y/xy mirror of the ¼ texel), meeting at centre",
            "passes": ["additive GetTPage(0,1,960,256)=0x3F",
                       "subtractive GetTPage(0,2,960,256)=0x5F"],
            "selected_only": True,
            "code": "FUN_8011712c (box builder), called by orb_cell_generator "
                    "@0x80116264",
        },
        "indexed_texture": "BOX.tga",
        "palette_texture": "BOX.palette.tga",
    }
    with open(out_dir / "BOX.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract the FFT formation-screen "
                                 "gold selection box ¼ texel + CLUT")
    ap.add_argument("--iso", help="raw FFT ISO .bin (default: project-assets)")
    args = ap.parse_args()

    bin_path = prt.iso_path(args.iso)
    if not bin_path.exists():
        print(f"Error: ISO not found at {bin_path}", file=sys.stderr)
        return 1
    world_path = world_bin(None)
    if not world_path.exists():
        print(f"Error: WORLD.BIN not found at {world_path}", file=sys.stderr)
        return 1

    asset = prt.read_lba(bin_path, prt.TEXTURE_LBA, prt.ASSET_SECTORS)
    world = world_path.read_bytes()

    out_dir = assets_dir() / "ui" / "formation"
    parse(asset, world, out_dir)
    print(f"Extracting: formation gold box (texel LBA {prt.TEXTURE_LBA:#x} "
          f"{BOX_X},{BOX_Y} {BOX_W}x{BOX_H}; CLUT WORLD.BIN {BOX_CLUT_ADDR:#010x})")
    print(f"  -> {out_dir / 'BOX.tga'} + BOX.palette.tga + .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
