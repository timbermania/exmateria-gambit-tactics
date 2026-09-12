#!/usr/bin/env python3
"""Extract the 13 zodiac-sign glyphs for the FORMATION info panel from the ROM.

The selected unit's info panel shows a small zodiac symbol next to the job name
(t04.png: the gold Capricorn beside "Squire"). The 13 signs live in the shared
FRAME / range sheet (`RANGETILE.tga`, LBA 0xE68 +0x1000, 256x256 4bpp -- the
same asset orb/box/background come from), in two 24x20 rows:

    signs 0-6  (Aries..Libra)          sheet (0,42)-(167,61)   7 cells
    signs 7-12 (Scorpio..Serpentarius) sheet (0,62)-(142,81)   6 cells

(FORMATION_SCREEN.md §14.3.) The glyph *indices* are byte-exact ROM; the CLUT is
**slot 0** of the sheet's palette tail (payload 0x9000, the tail base) -- a
sprite CLUT (index 0 transparent) rendering the muted tan/olive icons, matched
per-pixel against the Capricorn beside "Squire" in t04.png (the tan (144,144,112)
ramp; the saturated-gold, magenta, and blue tail slots are clearly wrong). The
exact slot is not disasm-pinned (the roster overlay marks its CLUT "elsewhere"),
but the tan@0 render is a confirmed pixel match. Slot 15 is byte-equivalent here
(the two differ only in indices 13-15, which no zodiac glyph uses).

The 13 glyphs are packed into a 7x2 grid atlas (168x40); sign i sits at
(col=i%7, row=i//7). The unused 14th grid cell (sheet x144..167,y62..81 holds
foreign art) is left transparent, not baked.

Output (assets/ui/formation/, ADR-0022):
    ZODIAC.tga          168x40 grayscale-indexed atlas (pixel = index*17)
    ZODIAC.palette.tga  16x1 RGBA (slot-10 CLUT; index 0 transparent)
    ZODIAC.json         source rects + per-sign atlas rects + CLUT provenance

Usage:
    uv run python tools/parse_formation_zodiac.py [--iso PATH]
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

CELL_W = 24
CELL_H = 20
NUM_SIGNS = 13
SIGNS_PER_ROW = 7

# Source rows within the 256x256 sheet: signs 0-6 at y42, signs 7-12 at y62.
ROW0_Y = 42
ROW1_Y = 62

SIGN_NAMES = [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra",
    "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces", "Serpentarius",
]
assert len(SIGN_NAMES) == NUM_SIGNS

# Slot 0 of the sheet's palette tail (0x9000, the tail base). Sprite CLUT:
# index 0 transparent. Muted tan/olive, pixel-matched vs t04.png.
ZODIAC_CLUT_SLOT = 0
ZODIAC_CLUT_OFFSET = prt.TEXELS_OFFSET + prt.TEXELS_SIZE + ZODIAC_CLUT_SLOT * 32

ATLAS_W = SIGNS_PER_ROW * CELL_W   # 168
ATLAS_H = 2 * CELL_H               # 40


def sign_source_rect(sign: int) -> tuple[int, int, int, int]:
    """Sheet texel rect (x, y, w, h) of a sign's glyph."""
    col = sign % SIGNS_PER_ROW
    row = sign // SIGNS_PER_ROW
    y = ROW0_Y if row == 0 else ROW1_Y
    return (col * CELL_W, y, CELL_W, CELL_H)


def sign_atlas_rect(sign: int) -> tuple[int, int, int, int]:
    """Rect (x, y, w, h) of a sign within the emitted 7x2 grid atlas."""
    col = sign % SIGNS_PER_ROW
    row = sign // SIGNS_PER_ROW
    return (col * CELL_W, row * CELL_H, CELL_W, CELL_H)


def _texels(asset: bytes) -> bytes:
    return asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]


def decode_atlas_indices(asset: bytes) -> np.ndarray:
    """(ATLAS_H, ATLAS_W) uint8 palette indices: the 13 glyphs packed 7x2.

    Only the 13 sign cells are copied; the unused 14th grid cell stays index 0
    (the sheet holds foreign art there, which we must not bake in)."""
    texels = _texels(asset)
    out = np.zeros((ATLAS_H, ATLAS_W), np.uint8)
    for sign in range(NUM_SIGNS):
        sx, sy, w, h = sign_source_rect(sign)
        ax, ay, _, _ = sign_atlas_rect(sign)
        for ty in range(h):
            for tx in range(w):
                out[ay + ty, ax + tx] = prt.nibble(texels, sx + tx, sy + ty)
    return out


def read_zodiac_clut(asset: bytes) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for the zodiac palette."""
    return list(struct.unpack_from("<16H", asset, ZODIAC_CLUT_OFFSET))


def _clut_rgba(asset: bytes) -> np.ndarray:
    """(16, 4) uint8 RGBA. Sprite CLUT: index 0 punched to alpha 0."""
    rgba = np.zeros((16, 4), np.uint8)
    for i, w in enumerate(read_zodiac_clut(asset)):
        rgba[i] = prt.bgr555_to_rgba(w & 0xFF, (w >> 8) & 0xFF,
                                     index_is_zero=(i == 0))
    return rgba


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

    idx = decode_atlas_indices(asset)
    g = (idx.astype(np.uint16) * 17).astype(np.uint8)
    indexed = np.zeros((ATLAS_H, ATLAS_W, 4), np.uint8)
    indexed[..., 0] = indexed[..., 1] = indexed[..., 2] = g
    indexed[..., 3] = 255
    _write_tga(out_dir / "ZODIAC.tga", ATLAS_W, ATLAS_H, indexed)

    pal = _clut_rgba(asset).reshape(1, 16, 4)
    _write_tga(out_dir / "ZODIAC.palette.tga", 16, 1, pal)

    signs = [
        {"index": s, "name": SIGN_NAMES[s],
         "atlas_rect": list(sign_atlas_rect(s)),
         "source_rect": list(sign_source_rect(s))}
        for s in range(NUM_SIGNS)
    ]
    manifest = {
        "_comment": (
            "FORMATION info-panel zodiac glyphs. 13 signs from the shared "
            "FRAME/range sheet (RANGETILE.tga), packed 7x2 into a 168x40 "
            "indexed atlas (pixel = index*17; recover via int(r/17) and sample "
            "ZODIAC.palette.tga, index 0 transparent). Pick a sign via "
            "signs[i].atlas_rect. CLUT slot 10 = gold, visually confirmed vs "
            "t04.png. See FORMATION_SCREEN.md §14.3."
        ),
        "source": {
            "asset": "raw-sector LBA 0xE68 (ShiShi RANGETILE.TGA / FRAME sheet)",
            "texels_lba": prt.TEXTURE_LBA,
            "sheet_size": [prt.TEX_W, prt.TEX_H],
            "row0": [0, ROW0_Y, SIGNS_PER_ROW * CELL_W, CELL_H],
            "row1": [0, ROW1_Y, (NUM_SIGNS - SIGNS_PER_ROW) * CELL_W, CELL_H],
            "cell": [CELL_W, CELL_H],
            "clut_asset_offset": ZODIAC_CLUT_OFFSET,
            "clut_slot": ZODIAC_CLUT_SLOT,
            "clut_note": "tan/olive; pixel-matched vs t04.png, not disasm-pinned",
        },
        "atlas_size": [ATLAS_W, ATLAS_H],
        "signs": signs,
        "indexed_texture": "ZODIAC.tga",
        "palette_texture": "ZODIAC.palette.tga",
    }
    with open(out_dir / "ZODIAC.json", "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract the FFT formation-screen "
                                 "zodiac-sign glyphs + CLUT")
    ap.add_argument("--iso", help="raw FFT ISO .bin (default: project-assets)")
    args = ap.parse_args()

    bin_path = prt.iso_path(args.iso)
    if not bin_path.exists():
        print(f"Error: ISO not found at {bin_path}", file=sys.stderr)
        return 1
    asset = prt.read_lba(bin_path, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    out_dir = assets_dir() / "ui" / "formation"
    parse(asset, out_dir)
    print(f"Extracting: {NUM_SIGNS} zodiac glyphs (LBA {prt.TEXTURE_LBA:#x} "
          f"rows y{ROW0_Y}/{ROW1_Y}, {CELL_W}x{CELL_H}, CLUT slot "
          f"{ZODIAC_CLUT_SLOT}) -> {ATLAS_W}x{ATLAS_H} atlas")
    print(f"  -> {out_dir / 'ZODIAC.tga'} + ZODIAC.palette.tga + .json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
