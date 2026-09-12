#!/usr/bin/env python3
"""Extract FFT's HUD number font from EVENT/FRAME.BIN into a Godot-ready indexed
texture + metadata.

The bottom-left vitals `cur/max` (and `Lv.`/`Exp.`) digits are FFT's blocky
two-tone menu/number font, drawn through the menu CLUT 0x7cbc (same CLUT as the
`Hp`/`Mp`/`Ct` labels). The clean, ISO-reproducible source is EVENT/FRAME.BIN —
its top 32 rows hold TWO authored digit sets:

  - BIG  set (row V=0):  the `cur` size,  `0123456789/`  (8x16 cells)
  - SMALL set (row V=16): the `max` size, `0123456789/`  (6x10 cells)

These geometries are NOT guesses — they are CODE-CONFIRMED from the FFT
disassembly (see docs/frame-bin-number-font.md). The per-digit drawing routines
in BATTLE.BIN compute each glyph's source U as `base + digit*pitch`:

  - BIG   `FUN_8014ac30` @ ram:8014ac30  ->  U = digit*8 + 0x78  (pitch 8)
  - SMALL `FUN_8014aec0` @ ram:8014aec0  ->  U = digit*6 + 0x78  (pitch 6)
    (descriptor at 0x80169780: V=0x10=16, W=6, H=0x0a=10, stride 0x100=256)
  - HUD path: the unit-info builder `FUN_801363dc` calls the SMALL routine 3x
    on the unit vital fields (HP/MP/CT) -> this IS the bottom-left readout.
  - Font bitmap is embedded in BATTLE.BIN @ ram:8014d5d4 (file 0xe65d4, load
    base 0x80067000); its glyphs are byte-IDENTICAL to FRAME.BIN's top rows
    (verified: FRAME small row y19 found verbatim in BATTLE.BIN at 0xe6f90), so
    extracting from FRAME.BIN is faithful to what the battle HUD draws.

Note: RANGETILE.tga (the BATTLE range-tile/menu atlas) == FRAME.BIN[rows 32:288]
pixel-exact; the number font lives ONLY in FRAME.BIN's extra top 32 rows and is
NOT present in RANGETILE.tga.

Run from tools/:
    uv run python parse_frame_font.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _repo_paths  # noqa: E402
from fft_exporter.exporters.tga import write_grayscale_tga  # noqa: E402

# Per-set glyph lists. FFT's HUD number routine draws each glyph at U = 0x78 + index*pitch.
# Both sets carry 0-9 and '/'. The SMALL (max-size) set ALSO carries '-' at index 11
# (U = 120 + 11*6 = 186) — the roster CT "no value" dash (a horizontal cream bar, verified
# in FRAME.BIN + the oracle "Ct ---/---"). The BIG set does NOT: its index-11 cell (U=208)
# is a fragment of a different glyph, and the vitals draw everything in the SMALL set anyway.
BIG_GLYPHS = "0123456789/"
# The SMALL set continues past '-' (index 11, U=186) with '%' at index 12 (U=192):
# the Status/detail screen's stats-band value routine (WORLD `world_render_number_small`
# FUN_800fe37c) draws the percent sign from THIS font at U=0xC0=192 (flag 0x2000), NOT
# from FONT.BIN — FFT's '%' is a compact dots+slash glyph, not the FONT.BIN circles+slash.
SMALL_GLYPHS = "0123456789/-%"

# --- the '+' plus marker (equip stat-DELTA preview) -----------------------------
# The equip compare panel prefixes a POSITIVE delta with '+' (Weap.Power +4 / +5).
# The WORLD flag->glyph emitter (world_equip_stat_glyph FUN_80111BC0, EQUIP_STAT_PREVIEW.md
# §5) selects the plus via descriptor DAT_8018b660 = 0xC8 -> U=200 — OFF the pitch-6 digit
# grid (index 13 = U=198 is a different fragment), so '+' is a special cell like the leader,
# NOT an extra strip index. Same 6x10 SMALL cell so it kerns level with the digits.
PLUS_GLYPH = "+"
PLUS_CELL = {"x": 200, "y": 16, "w": 6, "h": 10}  # 0xC8, dumped: vertical+horizontal cross

# --- the dot-LEADER "…" cell (§15.29 round 48) ----------------------------------
# The stats-band value renderer `world_render_number_small` (FUN_800fe37c) draws a
# 3-dot leader before every Move/Jump/Speed and R/L value (fmt flag 0x100,
# @0x800fe554-0x800fe5b8): descriptor U=0x78, V=0x1A, H=4, drawn at the value row
# +3px and advanced 7px (the value's first digit lands at leader_x + 7). The art is
# three 2px-wide dots at FRAME.BIN texels (120,28)-(125,29) inside the 6x4 blit —
# the SAME "…" the Status screen bakes into its value strip (§15.18 rec 14). It
# rides the SMALL set in the atlas; its 7px advance is a MOUNT-site fact (the set
# advance stays 5 — callers place the lone leader glyph explicitly).
LEADER_GLYPH = "…"
LEADER_CELL = {"x": 120, "y": 26, "w": 6, "h": 4}
# Drift fixture: the two ink rows of the leader cell (4bpp indices). If FRAME.BIN
# ever reads differently here, the extract is misaligned — fail loudly.
LEADER_INK_ROWS = {28: [1, 4, 1, 4, 1, 4], 29: [4, 3, 4, 3, 4, 3]}

# --- FRAME.BIN raster ----------------------------------------------------------
FRAME_W = 256  # the file is a 256px-wide 4bpp image (128 bytes/row)

# --- glyph cell geometry [CODE-CONFIRMED, disasm formula U = base + digit*pitch]
# The runtime draws each digit from a fixed grid: base U = 0x78 = 120, with pitch
# 8 (big) / 6 (small). The cells are uniform per set (NOT proportional) — the
# earlier "measured/gap-split" origins drifted (small '2'+ landed off-glyph). We
# now generate origins straight from the disasm formula.
BASE_U = 120         # 0x78 — base source U for digit 0 in both sets (FUN_8014ac30/8014aec0)
BIG_PITCH = 8        # `digit*8` in FUN_8014ac30 (ram:8014ae08 sll v0,v0,0x3)
SMALL_PITCH = 6      # `digit*6` in FUN_8014aec0

# --- runtime composition metrics -----------------------------------------------
# Each glyph blits at a FIXED per-size advance (not pairwise kerning). Each cell
# carries a dark-outline column on BOTH edges; FFT places the next glyph so its
# left outline column lands ON the previous glyph's right outline column — they
# merge into the single "1 column of dark pixels between digits" the user
# observed. So the on-screen advance is OVERLAP-1: advance = cell_width - 1
#   - BIG   8px cell -> advance 7  (matches the clearly-separated cur digits)
#   - SMALL 6px cell -> advance 5  (user-validated: 1 dark column between max digits)
# `max` staggers a baseline lower-right. These are panel @export tunables for a
# final headful nudge.
ADVANCE_BIG = 7      # = BIG_CELL width 8 - 1 (overlap 1)
ADVANCE_SMALL = 5    # = SMALL_CELL width 6 - 1 (overlap 1)
MAX_BASELINE_DY = 4  # small `max` top sits this many px below big `cur` top

# --- BIG (cur-size) digit set --------------------------------------------------
# Descriptor (FUN_8014ac30): V=0, W=8, H=16, U = 120 + digit*8. The 8x16 cell
# carries transparent top/bottom padding around the ~6px-wide glyph (that padding
# is why the on-screen advance is 5, not 8 — neighbours overlap the padding).
BIG_Y = 0
BIG_CELL = (8, 16)
BIG_ORIGINS = [BASE_U + BIG_PITCH * i for i in range(len(BIG_GLYPHS))]

# --- SMALL (max-size) digit set ------------------------------------------------
# Descriptor (FUN_8014aec0 @ 0x80169780): V=16, W=6, H=10, U = 120 + digit*6.
# User-validated exactly: small '0' at (120,17)->(125,23), '1' at 126, '2' at 132.
SMALL_Y = 16
SMALL_CELL = (6, 10)
SMALL_ORIGINS = [BASE_U + SMALL_PITCH * i for i in range(len(SMALL_GLYPHS))]


def read_frame_indices(path) -> list[list[int]]:
    """EVENT/FRAME.BIN as a grid of 4bpp palette indices (256 px wide,
    low-nibble-first, 128 bytes/row)."""
    data = Path(path).read_bytes()
    rows = len(data) // (FRAME_W // 2)
    grid: list[list[int]] = []
    for y in range(rows):
        base = y * (FRAME_W // 2)
        row = []
        for x in range(FRAME_W):
            b = data[base + (x >> 1)]
            row.append(b & 0xF if (x & 1) == 0 else b >> 4)
        grid.append(row)
    return grid


def cell_block(grid: list[list[int]], cell: dict) -> list[list[int]]:
    """The grid of indices under a `{x,y,w,h}` cell."""
    x0, y0, w, h = cell["x"], cell["y"], cell["w"], cell["h"]
    return [[grid[y0 + y][x0 + x] for x in range(w)] for y in range(h)]


def _digit_set(glyphs: str, origins: list[int], y: int, cell: tuple[int, int],
        size: str, advance: int) -> dict:
    w, h = cell
    cells = [{"x": ox, "y": y, "w": w, "h": h} for ox in origins]
    return {"glyphs": glyphs, "size": size, "advance": advance, "cells": cells}


def big_digit_set() -> dict:
    """The BIG (`cur`-size) digit set: 0-9 and '/' at the measured FRAME.BIN
    origins."""
    return _digit_set(BIG_GLYPHS, BIG_ORIGINS, BIG_Y, BIG_CELL, "big", ADVANCE_BIG)


def small_digit_set() -> dict:
    """The SMALL (`max`-size) digit set: 0-9, '/', the roster CT dash '-', '%', the
    equip-delta '+' marker (its own off-grid 6x10 cell at U=200 — see PLUS_CELL), and
    the stats-band dot-leader '…' (its own 6x4 cell — see LEADER_CELL)."""
    s = _digit_set(SMALL_GLYPHS, SMALL_ORIGINS, SMALL_Y, SMALL_CELL, "small", ADVANCE_SMALL)
    s["glyphs"] += PLUS_GLYPH
    s["cells"].append(dict(PLUS_CELL))
    s["glyphs"] += LEADER_GLYPH
    s["cells"].append(dict(LEADER_CELL))
    return s


# --- packed atlas --------------------------------------------------------------
MENU_CLUT = 0x7CBC   # the text/number CLUT the HUD renders this font through
GAP = 1              # 1px transparent gutter between packed glyphs


def build_font_atlas(grid: list[list[int]]):
    """Pack both digit sets into one grayscale (index×17) atlas. Returns
    `(width, height, gray_bytes, manifest)`. The manifest gives, per size, the
    packed atlas cells the runtime samples — rendered through `MENU_CLUT`."""
    sets = [big_digit_set(), small_digit_set()]
    width = max(len(s["cells"]) * (s["cells"][0]["w"] + GAP) for s in sets)
    height = sum(s["cells"][0]["h"] for s in sets) + GAP * (len(sets) - 1)
    gray = bytearray(width * height)

    out_sets = []
    row_y = 0
    for s in sets:
        packed = []
        x = 0
        for glyph, src in zip(s["glyphs"], s["cells"]):
            block = cell_block(grid, src)
            for dy in range(src["h"]):
                for dx in range(src["w"]):
                    gray[(row_y + dy) * width + x + dx] = block[dy][dx] * 17
            packed.append({"glyph": glyph, "x": x, "y": row_y,
                           "w": src["w"], "h": src["h"]})
            x += src["w"] + GAP
        out_sets.append({"size": s["size"], "glyphs": s["glyphs"],
                         "advance": s["advance"], "cells": packed})
        row_y += s["cells"][0]["h"] + GAP

    manifest = {
        "texture": "FRAMEFONT.tga",
        "clut": MENU_CLUT,
        # runtime composition metrics. IMPORTANT: the HP/MP/CT vitals readout
        # draws cur AND max in the SAME size — the SMALL set (confirmed by the
        # user and by the disasm: the HUD builder FUN_801363dc @0x801363dc calls
        # ONLY the small digit routine FUN_8014aec0, once per stat, drawing the
        # whole cur/max fraction in small). The BIG set is FFT's larger number
        # font used ELSEWHERE (not the vitals); we still extract it for reuse.
        # So: cur + '/' + max are all `small`; `max` staggers `max_baseline_dy`
        # px lower-right; each glyph advances its set's `advance` px (overlap-1).
        "max_baseline_dy": MAX_BASELINE_DY,
        "cur_size": "small",
        "max_size": "small",
        "slash_size": "small",
        "sets": out_sets,
    }
    return width, height, bytes(gray), manifest


def extract(frame_path, out_dir) -> dict:
    """Read FRAME.BIN, build the atlas, and write FRAMEFONT.tga + FRAMEFONT.json
    into `out_dir`. Returns the manifest."""
    grid = read_frame_indices(frame_path)
    for v, expect in LEADER_INK_ROWS.items():
        got = [grid[v][LEADER_CELL["x"] + dx] for dx in range(LEADER_CELL["w"])]
        if got != expect:
            raise SystemExit(f"FRAME.BIN drift: leader-dot row v={v} reads {got}, expected {expect}")
    w, h, gray, manifest = build_font_atlas(grid)
    out_dir = Path(out_dir)
    write_grayscale_tga(out_dir / "FRAMEFONT.tga", w, h, gray)
    (out_dir / "FRAMEFONT.json").write_text(json.dumps(manifest, indent=1))
    return manifest


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Extract the HUD number font from EVENT/FRAME.BIN")
    ap.add_argument("--fft-extract", help="FFT extract root (for EVENT/FRAME.BIN)")
    ap.add_argument("--out", help="output dir (default: assets/sprites/textures)")
    args = ap.parse_args(argv)

    frame = _repo_paths.fft_extract_root(args.fft_extract) / "EVENT" / "FRAME.BIN"
    out_dir = Path(args.out) if args.out else _repo_paths.assets_dir("sprites/textures")
    if not frame.exists():
        print(f"ERROR: FRAME.BIN not found: {frame}", file=sys.stderr)
        return 1
    m = extract(frame, out_dir)
    n = sum(len(s["cells"]) for s in m["sets"])
    print(f"wrote FRAMEFONT.tga + FRAMEFONT.json ({n} glyphs, sets: "
          f"{', '.join(s['size'] for s in m['sets'])})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
