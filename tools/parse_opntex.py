#!/usr/bin/env python3
"""
FFT OPNTEX.BIN Parser — title-menu glyphs as indexed + CLUT.

OPNTEX.BIN holds every paletted texture used by the opening sequence:
title-menu items, sound-config options, the © 1997/1998 SQUARE line, the
"Warning!" memory-card dialog, decorative icons, etc. See Shishi's
PSXImages.xml section "OPNTEX.BIN" for the full layout (22 entries).

This tool extracts the first section (OPNTEX1 — 256x256 4bpp, 16 palettes)
and emits the title-menu strip as:

    opntex1_index.png     — 256x256 grayscale, R = idx * 17 (8bpp index encoded
                            for filter_nearest CLUT lookup, same pattern the
                            vitals_sprite.gdshader uses for RANGETILE)
    opntex1_clut_pNN.png  — 16x1 RGBA per CLUT (08 acting, 09 non-acting)
    opntex1_cells.json    — source rects (atlas px) per menu item

## Rendering model (parsed from disassembly + live BP capture, verified)

The OPEN.BIN menu draw emits TWO sub-rects per item. Each sub-rect's
blend/tpage flags come from a 32-bit ctrl word inside the per-cell
descriptor (cell_desc table base = `[0x800707FC] + 0x74 = 0x800709E0`,
28-byte stride, menu_item.field_4 is the index; sub-rect ctrl words
at cell_desc offsets +0x10 and +0x18).

The CLUT-pick code at PC `0x800690E0..0x80069128` decompiles to:

    uint32_t sel  = menu_item.field_20;        // 0 = unselected, ≥1 = selected
    uint32_t ctrl = cell_desc[sub_rect].ctrl;
    if (sel == 0 || (ctrl & (1u << 27))) {
        clut_offset = (ctrl >> 12) & 0xF0;     // PATH A:  bits 16-19 of ctrl,
                                                //          left-shifted by 4
    } else {
        clut_offset = (sel - 1) << 4;          // PATH B:  (field_20 - 1) × 16
    }
    // ... later: GetClut(s8 + clut_offset, sp+0x30)
    // where s8 = 0 and sp+0x30 = 480 for the title menu

The mask `& 0xF0` (not `& 0xF`) extracts bits 16-19 of ctrl scaled by
16 — i.e., `clut_index = (ctrl >> 16) & 0xF`. **This corrects a prior
error that read bits 12-15.** Empirically verified by capturing 60
GetClut fires from the committed reference state
(`reference-assets/title_menu_idle.sstate`):

    item    ctrl         sel  path   clut_index  v0
    ---     ---          ---  ---    ---         ---
    title   0x00087444     0   A         8        128
    NEW G   0x40098080     9   B         8        128
    CONT    0x40098080     0   A         9        144
    TUTOR   0x40098080     0   A         9        144
    SOUND   0x40098080     0   A         9        144

The menu uses **CLUT 8** for the active item / title text (cream
palette) and **CLUT 9** for unselected items (dim palette).
`menu_item.field_20 = 0x09` (NEW GAME selected in the reference
state) routes through PATH B and gives `(9 - 1) << 4 = 128` = CLUT 8.

Index 0 in every CLUT is the alpha-key (transparent gap between
letters that lets the parchment show through); indices 1..15 are
opaque colours.

## VRAM layout (live menu uses the lower-left STP-bit copy)

There are TWO copies of the OPNTEX1 16-CLUT block in VRAM:

  (960, 496, 16×16)  — uploaded by SCUS `FUN_80045154` (no STP bits)
  (  0, 480, 256×1)  — uploaded by OPEN.BIN @ ra 0x80069DF8,
                       same colors but with STP bit (0x8000) set on
                       every color, packed as 16 CLUTs at clut_x=0..15.

The menu draw uses the lower-left copy (clut_y = 480, clut_x = N*16),
NOT the (960, 496) copy. Confirmed by GetClut BP capture: every fire
passes `a1 = 480`. So CLUT N for the menu lives at pixel (N×16, 480).

There's also a semi-trans overlay sub-rect emitted per acting item.
The actual bit position the OPEN.BIN code passes for `abe` is bit 26
(not 30 as a prior guess); the bit position for `abr` (28-29) was
correct. The semi-trans overlay lives in `OpeningMenu.gd` as a
separate Plane3D for the acting item only — colour parsed from CLUT 8
idx 5 (= (0, 0, 8), the near-black tint visible behind NEW GAME).

Source rectangles (column-scan of opaque pixels in OPNTEX1):

    Row y=0..9       (top menu items)
        NEW GAME    x=  0..53
        CONTINUE    x= 56..107
        TUTORIAL    x=112..164
        SOUND       x=168..202
    Row y=22..36     (copyright — 15 rows tall, not 10)
        © 1997/1998 SQUARE   x=111..228
        Original height = 10 was too tight: column-scan shows real
        glyph activity in rows 24..36 with strong rows 26..33; y=31
        cut off the bottom halves of the © circle, the 1/9 digits
        and the bottom strokes of SQUARE.
"""

import argparse
import json
import struct
from pathlib import Path

from PIL import Image


# OPNTEX1 layout — the first chunk of OPNTEX.BIN is a standard PSX TIM image:
#   bytes  0..7   : TIM header  (ID=0x10, Flag=0x08 = 4bpp + CLUT)
#   bytes  8..19  : CLUT block header
#       +0  u32 bnum     = block length incl. header (= 524)
#       +4  s16 dx, dy   = VRAM destination (0, 480)
#       +8  u16 w, h     = CLUT dimensions (16 entries × 16 rows)
#   bytes 20..531 : CLUT pixel data (16 CLUTs × 32 bytes each, 512 bytes total)
#   bytes 532..543: image block header (same shape; dims 64 × 256 for 4bpp)
#   bytes 544..  : 4bpp packed pixel data (256 × 256 = 32768 bytes)
#
# Verified by byte-comparing offset-20 vs the runtime VRAM upload captured
# at PCSX BP 0x800248FC (`ra=0x80069DF8 rect=(0,480 256x1)`): identical.
OPNTEX1_PIXEL_OFFSET = 544
OPNTEX1_PIXEL_LEN = 32768
OPNTEX1_W = 256
OPNTEX1_H = 256
PALETTE_BASE = 20      # was 24 — an off-by-4 that decoded every CLUT shifted
                       # by 2 colors, making CLUT 8 idx 0 read as cream instead
                       # of the actual alpha-key 0x0000 → white menu backgrounds.
PALETTE_STRIDE = 32    # 16 colours × 2 bytes

# Which CLUTs power the title menu — verified empirically by capturing
# 60 GetClut fires from the committed reference savestate
# (reference-assets/title_menu_idle.sstate; BP at 0x80069128, see
# pcsx-agent/docs/linux-verified-methods.md §"Patterns that paid off").
# Title text + selected item route through PATH B / PATH A both giving
# clut_index = 8. Every unselected item has cell_desc.ctrl bits 16-19 = 9,
# giving clut_index = 9.
CLUT_SELECTED = 8
CLUT_UNSELECTED = 9

# Glyph rectangles (x0, y0, x1_inclusive, y1_inclusive)
MENU_ITEMS = [
    ("new_game",  (  0, 0,  53, 9)),
    ("continue",  ( 56, 0, 107, 9)),
    ("tutorial",  (112, 0, 164, 9)),
    ("sound",     (168, 0, 202, 9)),
]
COPYRIGHT = ("copyright", (111, 22, 228, 36))


def _load_clut_rgba(data: bytes, clut_idx: int) -> list:
    """Decode a 16-entry CLUT to RGBA using the project-standard STP
    convention (matches `parse_frame.py` / `extract_spr.py` /
    `extract_item_sprites.py` / `extract_trap_palettes.py`):

        BGR555 + bit 15 STP
        STP = 1  → a = 128   (semi-transparent — PSX abe-blend candidate)
        STP = 0  → a = 255   (opaque)
        RGB = (0,0,0) → a = 0 (true alpha-key gap pixel)

    Empirical sanity-check from CLUT 8 (the selected/cream palette):
    idx 0 = (232,232,232) STP=0 — the cream BODY color, opaque.
    A prior version hardcoded `i == 0 → a = 0` ("alpha-key idx") which
    happened to give the right look for the unselected CLUT 7 only
    because CLUT 7 idx 0 is STP=1 (semi-trans navy) and the blend over
    parchment passably approximated a transparent gap. Don't do that
    — use STP everywhere.
    """
    pal = []
    for i in range(16):
        v = struct.unpack_from(
            "<H", data, PALETTE_BASE + clut_idx * PALETTE_STRIDE + i * 2
        )[0]
        r = (v & 0x1F) << 3
        g = ((v >> 5) & 0x1F) << 3
        b = ((v >> 10) & 0x1F) << 3
        stp = (v >> 15) & 1
        if r == 0 and g == 0 and b == 0:
            a = 0
        else:
            a = 128 if stp else 255
        pal.append((r, g, b, a))
    return pal


def _build_index_atlas(data: bytes) -> Image.Image:
    """Emit OPNTEX1 as 256x256 RGBA where R = idx*17, A=255 (transparency
    is fully delegated to the CLUT alpha)."""
    img = Image.new("RGBA", (OPNTEX1_W, OPNTEX1_H))
    px = img.load()
    pixdata = data[OPNTEX1_PIXEL_OFFSET : OPNTEX1_PIXEL_OFFSET + OPNTEX1_PIXEL_LEN]
    for y in range(OPNTEX1_H):
        for x in range(OPNTEX1_W):
            byte = pixdata[y * (OPNTEX1_W // 2) + x // 2]
            idx = byte & 0x0F if (x & 1) == 0 else byte >> 4
            v = idx * 17  # 0..15 → 0..255 (15*17=255)
            px[x, y] = (v, v, v, 255)
    return img


def _build_clut_image(palette: list) -> Image.Image:
    img = Image.new("RGBA", (16, 1))
    px = img.load()
    for i, c in enumerate(palette):
        px[i, 0] = c
    return img


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        default=str(repo_root / "project-assets/fft-extract/OPEN/OPNTEX.BIN"),
        help="Path to OPNTEX.BIN",
    )
    parser.add_argument(
        "--out-dir",
        default=str(repo_root / "godot-learning/assets/ui/opntex"),
        help="Output directory",
    )
    args = parser.parse_args()

    data = Path(args.input).read_bytes()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Index atlas
    atlas = _build_index_atlas(data)
    atlas_path = out_dir / "opntex1_index.png"
    atlas.save(atlas_path)
    print(f"wrote {atlas_path}  ({atlas.size[0]}x{atlas.size[1]})")

    # CLUTs. Label is "p<NN>" where NN is the CLUT index (matches Shishi).
    for clut_idx, label in (
        (CLUT_SELECTED, f"p{CLUT_SELECTED:02d}"),
        (CLUT_UNSELECTED, f"p{CLUT_UNSELECTED:02d}"),
    ):
        pal = _load_clut_rgba(data, clut_idx)
        clut_img = _build_clut_image(pal)
        clut_path = out_dir / f"opntex1_clut_{label}.png"
        clut_img.save(clut_path)
        print(f"wrote {clut_path}")
        for i, c in enumerate(pal):
            tag = "  ← ALPHA-KEY" if c[3] == 0 else ""
            print(f"  idx {i:2d}: rgb=({c[0]:3d},{c[1]:3d},{c[2]:3d}) a={c[3]:3d}{tag}")

    # Cell rectangles
    cells = {}
    for name, (x0, y0, x1, y1) in MENU_ITEMS:
        cells[name] = {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}
    name, (x0, y0, x1, y1) = COPYRIGHT
    cells[name] = {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}
    cells_path = out_dir / "opntex1_cells.json"
    cells_path.write_text(json.dumps(cells, indent=2))
    print(f"wrote {cells_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
