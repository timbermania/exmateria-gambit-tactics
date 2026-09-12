#!/usr/bin/env python3
"""
FFT world-map extractor — WLDTEX.TM2 pixels + WLDCORE.BIN model.

    uv run python tools/parse_world_map.py [fft-extract-path]

Output (both gitignored, regenerable):
    assets/world_map/vram.bin      1024x512 x u16 little-endian, the TM2 replayed,
                                   plus EVENT/FRAME.BIN's band at (960,256) -- see below
    assets/world_map/model.json    node table, cel bank, frame lists, routes, layout

WHAT THIS IS A PORT OF
  Every number here is derived in research/working_documents/WORLD_MAP_SCREEN.md and
  mechanised in its five check suites (126 rows). The authority for each piece:

    vram.bin      sec 18   `world_map_captures/wldtex_replay.py` -- ADR-0001 names it
                           "the parser a Godot-side extractor should be built from".
                           134 sectors, 386 blocks, verified 126416/126416 halfwords
                           bit-exact against the console.
    nodes         sec 30.1 the DISC source at 0x80094DFC (file 0x2DDFC), 43 x 8 bytes.
                           NOT the BSS table -- sec 19.2/24.5/25.1 all read that one
                           and all say a savestate is required. It is not.
    marker shape  sec 30.5 `106 + (tier_a == 2)`, computed by the initialiser.
    cels/frames   sec 19.5 + sec 24, via `world_map_captures/celbank.py`.
    routes        sec 12.4 + sec 27.1, the polyline table -- PAIRS of edge vertices.
    projection    sec 25.3 the GTE parks at identity, so screen = map + (128, 12).

WHY vram.bin AND NOT A PNG
  The screen samples VRAM as 4bpp and 8bpp INDICES through CLUTs that also live in
  VRAM, and one CLUT is overridden at runtime (the "you are here" pin, sec 24.2). A
  pre-resolved RGBA sheet cannot express that. Raw halfwords + an in-shader unpack is
  the faithful shape, and it dodges the importer's sRGB conversion entirely -- the
  consumer builds an Image.FORMAT_RG8 texture at load and no colour math touches it.

THE SHARED UI SHEET -- WLDTEX.TM2 DOES NOT CARRY IT (sec 15 #9)
  sec 18.1 records that the cursor, the map pins and the war-funds digits come from a
  shared FFT UI sheet at VRAM (960,256) which is NOT in WLDTEX.TM2, and leaves
  "finding that sheet's disc source" open. Replaying the TM2 alone therefore draws a
  world map with no cursor, no pins and no war funds -- which is exactly what the first
  run of the Godot scaffold showed, and how this was found.

  It is `EVENT/FRAME.BIN`, and the mapping is a straight row shift:

      VRAM (960, 256 + r)  ==  FRAME.BIN pixel row (r + 32),  128 bytes each

  Both are 4bpp 256 texels wide, so a row is 128 bytes on either side and no repacking
  is needed. **240 of the 256 page rows are byte-identical** to the console's VRAM; the
  last 16 (page rows 240-255) differ and are left alone, because nothing the world map
  draws reaches them -- the cursor is at v 0..16, the pins at v 0..28, the funds digits
  at v 40..64 and its label at v 120..128.

  FRAME.BIN is already in this tree's hands: `tools/parse_frame.py` decodes it to
  `assets/ui/frame.tga` and `src/ui3/elements/FrameCellAtlas.gd` inverts that back to
  4bpp indices for exactly this reason. That is the port list's R2 row showing up as a
  fact rather than as a prediction.

THE ONE THING NOT SOURCED FROM DISC
  `BG_GRID` below is the 17x13 background vertex grid at RAM 0x800C7320. It is BSS --
  the disc bytes at WLDCORE file offset 0x60320 are ALL ZERO -- so it is baked here
  from a savestate and flagged. Open question sec 15 #17. Its POSITIONS are closed
  form (`map = cumulative sum of the per-entry w/h from (-256,-192)`, and
  `screen = map + (128,12)`); only the uv/tpage slab packing is authored data. It is
  byte-identical across all three captures the repo holds. Regenerate with:

      cd <repo> && python3 - <<'EOF'
      import sys; sys.path.insert(0, 'research/working_documents/world_map_captures')
      import travel as T, struct
      ram = T._ram('reference-assets/world_map_ss1_settled_dialog_closed.sstate')
      for i in range(17*13):
          print(struct.unpack_from('<IIiiii', ram, (0x800C7320 + 0x18*i) & 0x7FFFFF))
      EOF
"""

import argparse
import json
import struct
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _repo_paths import fft_extract_root

VRAM_W, VRAM_H = 1024, 512
SECTOR = 2048

WLDCORE_BASE = 0x80067000
NODE_SRC = 0x80094DFC          # sec 30.1 -- the node table's DISC source
NODE_COUNT = 43

# ---------------------------------------------------------------------------
# THE TOWN SCREEN -- sec 35 (round 18).  O with the cursor on the node the party
# is already standing on.
#
# TWO node tables, and they are NOT the same table.  NODE_SRC above is the 8-byte
# DRAWING record (x, tier a, tier b, y) sec 30.1 reads.  The picture id and the node
# KIND live in a SECOND, 4-byte-per-node table -- `*(0x80094DF8)`, which resolves to
# 0x80094F54 and is itself in WLDCORE, so it needs no savestate.  Reading byte 2 of
# the 8-byte record instead yields 0/1/2 for every node in the game, which is a
# plausible-looking "kind" and is not one.  sec 35.2 / sec 35.10, and
# `dispatch.py pics` is the research-side reader of the same bytes.
NODE_PIC_TBL = 0x80094F54      # 4 bytes per node: byte 2 = picture id, byte 3 = kind
NODE_PIC_STRIDE = 4
KIND_TOWN = 1                  # sec 35.10's `node_record[node].byte3 != 1` town gate
DEEP_DUNGEON_NODE = 22         # ...which FUN_8008D2C8 special-cases BEFORE that gate

# The drop shadow's ramp texture is NOT in WLDPIC.BIN -- it is a second PSX TIM
# embedded in WLDCORE.BIN itself, reachable from exactly one word in the overlay
# (0x80092B34).  sec 35.7.
SHADOW_TIM = 0x800944B4        # flags = 8: 4bpp with a CLUT
SHADOW_RAMP_DEPTH = 11         # entries 0..10 are the ramp; 11..15 are a sentinel

# The picture rect and the shadow ring, screen-centred.  sec 35.6 / sec 35.7, and
# both are asserted against the round-18 savestate pair by `dispatch.py town`.
PICTURE_XY = [-64, -76]
PICTURE_WH = [120, 80]
PICTURE_TPAGE = 0x0298         # VRAM (512,256), 8bpp, abr 0
PICTURE_CLUT = 0x7900          # VRAM (0,484)
SHADOW_FRAME = 11              # frame list 11 -> cel 15, the 28-part nine-patch ring
SHADOW_XY = [-8, 16]           # see `town` for how this is MEASURED, not chosen

# The list panel. sec 35.8: a nine-patch of `0x66` rects on CLUT 0x7C3C spanning
# x -42..34, y 8..84, whose CONTENT is one `0x66` blitted from the scratch page at
# VRAM (576,256) -- sec 34.9's "rasterised into a scratch band and blitted as ONE
# rect", which is why the port draws its own labels (see WorldMapTownPage).
#
# ROW PITCH IS MEASURED, not borrowed. The repo holds a savestate PAIR from one
# driven run with the cursor on row 0 and on row 2, and the glove's lit quad moves
# (-51,22) -> (-52,54): 32 px over two rows, so the pitch is 16 -- and the 1 px of x
# is the glove BOB (sec 33.2's `slide`), not a second unknown.
TOWN_BOX_XY = [-42, 8]
TOWN_BOX_WH = [76, 76]
TOWN_CONTENT_XY = [-34, 20]
TOWN_CONTENT_WH = [66, 50]
TOWN_ROW_PITCH = 16
TOWN_CURSOR_XY = [-51, 22]     # the glove's LIT top-left on row 0, bob excluded

DD_MSG_BASE = 0xB8ED           # Deep Dungeon floor 0 ("Nogias")
DD_FLOOR_MAX = 16              # a ceiling for the scan; the archive stops it at 10

# ---------------------------------------------------------------------------
# WHERE THE 19 PICTURES GO -- the one place this port DIVERGES from the console,
# deliberately.  ADR: godot-learning/docs/adr/0178-the-town-picture-gets-an-address-of-its-own.md.
#
# On the console all 92 pictures land at the SAME address, VRAM (512,256), swapped
# in place per node by a `LoadImage` on the O press (sec 35.1 / sec 35.5).  `vram.bin`
# is a single static bake and cannot hold a region that changes, so the port gives
# each of the 19 node-reachable pictures its OWN address instead and emits the rect
# with that slot's tpage/CLUT.  The picture still goes through the same VRAM/CLUT
# sampler as every other primitive on the screen; only its ADDRESS differs, which is
# the one thing the console varies anyway.
#
# The arithmetic, and why it is forced rather than chosen:
#   * a picture is 120x80 TEXELS at 8bpp = 60x80 HALFWORDS;
#   * a uv is 8-bit, so a primitive can only reach 256x256 texels = 128x256 halfwords
#     from its tpage origin -- that is one PAGE, and it holds 2 across x 3 down = 6;
#   * a tpage origin is a multiple of (64, 256) halfwords, so a page starts at x = 128p;
#   * 19 pictures therefore need ceil(19/6) = 4 pages, x = 0, 128, 256, 384 at y = 0.
# WLDTEX.TM2 + FRAME.BIN leave x 0..767 / y 0..255 completely empty (every halfword
# zero), which is checked at extract time rather than assumed -- see `place_pictures`.
PIC_PAGE_W = 128               # halfwords a uv can reach from a tpage origin
PIC_PAGE_ORIGIN_Y = 0
PIC_PER_ROW = 2                # 60 halfwords each, so two fit in the 128
PIC_ROWS_PER_PAGE = 3          # 80 rows each, so three fit in the 256
PIC_SLOT_W = 60                # halfwords
PIC_SLOT_H = 80                # rows
# The CLUTs: 256 entries each, x must be a multiple of 16 for the CLUT word to
# round-trip. One per row at x = 512 keeps them clear of the picture pages and of
# everything WLDTEX/FRAME.BIN write.
PIC_CLUT_X = 512
PIC_CLUT_Y0 = 0
PIC_SECTOR_TBL = 0x8009E0EC   # u32 fencepost: picture i is sectors [t[i], t[i+1])
PIC_COUNT = 92                # ...and t[92] * 2048 == WLDPIC.BIN, exactly
FRAME_TABLE = 0x80092B38
CEL_TABLE = 0x8009324C
WAYPOINT_TABLE_PTR = 0x80095000
POLYLINE_TABLE_PTR = 0x80095004
ROUTE_COUNT = 48
PROJ = (128, 12)               # sec 25.3

# Screen anchors, all measured and asserted by `wldgen.py check` against three captures.
APERTURE_SUB = {"frame": 5, "xy": [0, 8]}      # cel 8, 24 parts, abr 2 (subtractive)
APERTURE_ADD = {"frame": 6, "xy": [-4, 8]}     # cel 9, 16 parts, abr 1 (additive)
NAME_FRAME_BASE = 0x36
MONTH_FRAME_BASE = 0x1F
DIGIT_FRAME_BASE = 0x2C
CURSOR_FRAME = 0
DATE_XY = [-120, -100]
DATE_STEP = [0x1A, -4]
FUNDS_XY = [48, 84]
DRAW_AREA = [0, 8, 252, 228]   # sec 22.2 / sec 28.5 -- three instruments agree

# ---------------------------------------------------------------------------
# THE START MENU -- sec 33, and sec 34 for the three rows retail cannot reach.
#
# Every number below is READ, not retyped. sec 33.10 point 1: "the menu is data --
# a port should read it, not retype it", and `world_map_captures/dispatch.py menu`
# is the research-side instrument that prints the same table from the same bytes.
# Two independent readers of one disc is the whole point; a third hand-typed copy
# would throw that away.
#
#   geometry / row count / entry table / label id / help topic
#       WORLD.BIN window record 4, stride 0x3C, at 0x8016E90C.  All static -- the
#       BSS-vs-disc trap sec 30.1 records for the node table does NOT apply here.
#   the six labels
#       message 0xA010, decoded out of EVENT/WORLD.LZW.  The section POINTER table
#       at 0x801CD8A4 is BSS (zeroes on disc, built at load), which is why
#       dispatch.py needs a savestate for this -- but the archive carries its own
#       32 x u32 section table at file offset 0, whose entries are exactly the
#       relative bases that pointer table ends up holding, so the disc alone
#       closes it.  Verified entry for entry against a savestate's built table.
# ---------------------------------------------------------------------------
WORLD_BIN_BASE = 0x800E0000
WIN_ARRAY = 0x8016E90C         # sec 33.2 -- 18 window records, stride 0x3C
WIN_STRIDE = 0x3C
MENU_WIN = 4                   # the record FUN_8006E0FC opens
PLACE_WIN = 6                  # ...and the record its row 0 opens: the Move place list
PLACE_PICK_WIN = 13            # every row of record 6's table opens THIS one
ENTRY_PRESENTATION = 0x1000    # FUN_800EBB08 strips it before using the entry as a window
PLACE_LIST_FN = 0x80105E04     # sec 33.3: walks n = 0..0x2A, keeps var[0x200+n] != 0
PLACE_PICK_FN = 0x80105F7C     # ...and refuses a row flagged 4, else var[0x33] = node
VAR_NODE_KNOWN = 0x200         # var[0x200 + n] != 0  -> node n is on the Move list
VAR_PARTY_NODE = 0x31          # the node the marker stands on -- its row is REFUSED
VAR_MOVE_DEST = 0x33           # what the pick writes
MENU_ROW_PITCH = 0x10          # FUN_800EC5B8: sll v1,row,4
MENU_CURSOR_DX = -12           # ...its x = rec.x - 12 + slide
MENU_CURSOR_DY = 10            # ...its y = rec.y + 16r + 10  (addiu v1,v1,10)
LZW_SECTIONS = 32              # EVENT/WORLD.LZW's own header: 32 x u32
LZW_TEXT_BASE = 4 * LZW_SECTIONS

# Window record field offsets, exactly FUN_80108388's.
WIN_FIELDS = {'x': 8, 'y': 10, 'w': 12, 'h': 14, 'msg': 0x1C, 'last': 0x1E,
              'close': 0x20, 'tbl': 0x24, 'fn': 0x28, 'row': 0x38, 'help': 0x3A}
WIN_SIGNED = ('x', 'y', 'w', 'h', 'last', 'row', 'help')

# sec 9 / sec 27.5: cel 67 + i is node i's name, in this order.
NAMES = [
    "Lesalia Imperial Capital", "Riovanes Castle", "Igros Castle", "Lionel Castle",
    "Limberry Castle", "Zeltennia Castle", "Gariland Magic City", "Yardow Fort City",
    "Goland Coal City", "Dorter Trade City", "Zaland Fort City", "Goug Machine City",
    "Warjilis Trade City", "Bervenia Free City", "Zarghidas Trade City", "Fort Zeakden",
    "Murond Holy Place", "Thieves Fort", "Orbonne Monastery", "Golgorand Execution Site",
    "Murond Death City", "Bethla Garrison", "Deep Dungeon", "Nelveska Temple",
    "Mandalia Plains", "Fovoham Plains", "Sweegy Woods", "Bervenia Volcano",
    "Zeklaus Desert", "Lenalia Plateau", "Zigolis Swamp", "Yuguo Woods",
    "Araguay Woods", "Grog Hill", "Bed Desert", "Zirekile Falls", "Dolbodar Swamp",
    "Barius Hill", "Doguola Pass", "Barius Valley", "Finath River", "Poeskas Lake",
    "Germinas Peak",
]

# ---------------------------------------------------------------------------
# BG_GRID -- SAVESTATE-SOURCED, see the module docstring. sec 15 #17.
# (tpage, cull, h, w, v, u, map_x, map_y) x 221, row-major 17 wide x 13 tall.
# ---------------------------------------------------------------------------
BG_GRID = [
    (0x18C,1,32,32,0,0,-256,-192), (0x18C,1,32,32,0,32,-224,-192), (0x18C,1,32,32,0,64,-192,-192), (0x18C,1,32,32,0,96,-160,-192), (0x18C,1,32,32,0,128,-128,-192), (0x18C,1,32,32,0,160,-96,-192), (0x18C,1,32,32,0,192,-64,-192), (0x18C,1,32,16,0,224,-32,-192), (0x18E,1,32,32,0,0,-16,-192), (0x18E,1,32,32,0,32,16,-192), (0x18E,1,32,32,0,64,48,-192), (0x18E,1,32,32,0,96,80,-192), (0x18E,1,32,32,0,128,112,-192), (0x18E,1,32,32,0,160,144,-192), (0x18E,1,32,32,0,192,176,-192), (0x18E,1,32,32,0,224,208,-192), (0x200,1,0,0,0,0,240,-192),
    (0x08C,0,32,32,32,0,-256,-160), (0x08C,0,32,32,32,32,-224,-160), (0x08C,0,32,32,32,64,-192,-160), (0x08C,0,32,32,32,96,-160,-160), (0x08C,0,32,32,32,128,-128,-160), (0x08C,0,32,32,32,160,-96,-160), (0x08C,0,32,32,32,192,-64,-160), (0x08C,0,32,16,32,224,-32,-160), (0x08E,0,32,32,32,0,-16,-160), (0x18E,1,32,32,32,32,16,-160), (0x18E,1,32,32,32,64,48,-160), (0x18E,1,32,32,32,96,80,-160), (0x18E,1,32,32,32,128,112,-160), (0x18E,1,32,32,32,160,144,-160), (0x18E,1,32,32,32,192,176,-160), (0x18E,1,32,32,32,224,208,-160), (0x200,1,0,0,0,0,240,-160),
    (0x08C,0,32,32,64,0,-256,-128), (0x08C,0,32,32,64,32,-224,-128), (0x08C,0,32,32,64,64,-192,-128), (0x08C,0,32,32,64,96,-160,-128), (0x08C,0,32,32,64,128,-128,-128), (0x08C,0,32,32,64,160,-96,-128), (0x08C,0,32,32,64,192,-64,-128), (0x08C,0,32,16,64,224,-32,-128), (0x08E,0,32,32,64,0,-16,-128), (0x18E,1,32,32,64,32,16,-128), (0x18E,1,32,32,64,64,48,-128), (0x18E,1,32,32,64,96,80,-128), (0x18E,1,32,32,64,128,112,-128), (0x18E,1,32,32,64,160,144,-128), (0x18E,1,32,32,64,192,176,-128), (0x18E,1,32,32,64,224,208,-128), (0x200,1,0,0,0,0,240,-128),
    (0x08C,0,32,32,96,0,-256,-96), (0x08C,0,32,32,96,32,-224,-96), (0x08C,0,32,32,96,64,-192,-96), (0x08C,0,32,32,96,96,-160,-96), (0x08C,0,32,32,96,128,-128,-96), (0x08C,0,32,32,96,160,-96,-96), (0x08C,0,32,32,96,192,-64,-96), (0x08C,0,32,16,96,224,-32,-96), (0x08E,0,32,32,96,0,-16,-96), (0x18E,1,32,32,96,32,16,-96), (0x18E,1,32,32,96,64,48,-96), (0x18E,1,32,32,96,96,80,-96), (0x18E,1,32,32,96,128,112,-96), (0x18E,1,32,32,96,160,144,-96), (0x18E,1,32,32,96,192,176,-96), (0x18E,1,32,32,96,224,208,-96), (0x200,1,0,0,0,0,240,-96),
    (0x08C,0,32,32,128,0,-256,-64), (0x08C,0,32,32,128,32,-224,-64), (0x08C,0,32,32,128,64,-192,-64), (0x08C,0,32,32,128,96,-160,-64), (0x08C,0,32,32,128,128,-128,-64), (0x08C,0,32,32,128,160,-96,-64), (0x08C,0,32,32,128,192,-64,-64), (0x08C,0,32,16,128,224,-32,-64), (0x08E,0,32,32,128,0,-16,-64), (0x18E,1,32,32,128,32,16,-64), (0x18E,1,32,32,128,64,48,-64), (0x18E,1,32,32,128,96,80,-64), (0x18E,1,32,32,128,128,112,-64), (0x18E,1,32,32,128,160,144,-64), (0x18E,1,32,32,128,192,176,-64), (0x18E,1,32,32,128,224,208,-64), (0x200,1,0,0,0,0,240,-64),
    (0x08C,0,32,32,160,0,-256,-32), (0x08C,0,32,32,160,32,-224,-32), (0x08C,0,32,32,160,64,-192,-32), (0x08C,0,32,32,160,96,-160,-32), (0x08C,0,32,32,160,128,-128,-32), (0x08C,0,32,32,160,160,-96,-32), (0x08C,0,32,32,160,192,-64,-32), (0x08C,0,32,16,160,224,-32,-32), (0x08E,0,32,32,160,0,-16,-32), (0x18E,1,32,32,160,32,16,-32), (0x18E,1,32,32,160,64,48,-32), (0x18E,1,32,32,160,96,80,-32), (0x18E,1,32,32,160,128,112,-32), (0x18E,1,32,32,160,160,144,-32), (0x18E,1,32,32,160,192,176,-32), (0x18E,1,32,32,160,224,208,-32), (0x200,1,0,0,0,0,240,-32),
    (0x08C,0,32,32,192,0,-256,0), (0x08C,0,32,32,192,32,-224,0), (0x08C,0,32,32,192,64,-192,0), (0x08C,0,32,32,192,96,-160,0), (0x08C,0,32,32,192,128,-128,0), (0x08C,0,32,32,192,160,-96,0), (0x08C,0,32,32,192,192,-64,0), (0x08C,0,32,16,192,224,-32,0), (0x08E,0,32,32,192,0,-16,0), (0x18E,1,32,32,192,32,16,0), (0x18E,1,32,32,192,64,48,0), (0x18E,1,32,32,192,96,80,0), (0x18E,1,32,32,192,128,112,0), (0x18E,1,32,32,192,160,144,0), (0x18E,1,32,32,192,192,176,0), (0x18E,1,32,32,192,224,208,0), (0x200,1,0,0,0,0,240,0),
    (0x08C,0,16,32,224,0,-256,32), (0x08C,0,16,32,224,32,-224,32), (0x08C,0,16,32,224,64,-192,32), (0x08C,0,16,32,224,96,-160,32), (0x08C,0,16,32,224,128,-128,32), (0x08C,0,16,32,224,160,-96,32), (0x08C,0,16,32,224,192,-64,32), (0x08C,0,16,16,224,224,-32,32), (0x08E,0,16,32,224,0,-16,32), (0x18E,1,16,32,224,32,16,32), (0x18E,1,16,32,224,64,48,32), (0x18E,1,16,32,224,96,80,32), (0x18E,1,16,32,224,128,112,32), (0x18E,1,16,32,224,160,144,32), (0x18E,1,16,32,224,192,176,32), (0x18E,1,16,32,224,224,208,32), (0x200,1,0,0,0,0,240,32),
    (0x094,0,32,32,0,0,-256,48), (0x094,0,32,32,0,32,-224,48), (0x094,0,32,32,0,64,-192,48), (0x094,0,32,32,0,96,-160,48), (0x094,0,32,32,0,128,-128,48), (0x094,0,32,32,0,160,-96,48), (0x094,0,32,32,0,192,-64,48), (0x094,0,32,16,0,224,-32,48), (0x094,0,32,32,128,0,-16,48), (0x194,1,32,32,128,32,16,48), (0x194,1,32,32,128,64,48,48), (0x194,1,32,32,128,96,80,48), (0x194,1,32,32,128,128,112,48), (0x194,1,32,32,128,160,144,48), (0x194,1,32,32,128,192,176,48), (0x194,1,32,32,128,224,208,48), (0x200,1,0,0,0,0,240,48),
    (0x094,0,32,32,32,0,-256,80), (0x094,0,32,32,32,32,-224,80), (0x094,0,32,32,32,64,-192,80), (0x094,0,32,32,32,96,-160,80), (0x094,0,32,32,32,128,-128,80), (0x094,0,32,32,32,160,-96,80), (0x094,0,32,32,32,192,-64,80), (0x094,0,32,16,32,224,-32,80), (0x094,0,32,32,160,0,-16,80), (0x194,1,32,32,160,32,16,80), (0x194,1,32,32,160,64,48,80), (0x194,1,32,32,160,96,80,80), (0x194,1,32,32,160,128,112,80), (0x194,1,32,32,160,160,144,80), (0x194,1,32,32,160,192,176,80), (0x194,1,32,32,160,224,208,80), (0x200,1,0,0,0,0,240,80),
    (0x194,1,32,32,64,0,-256,112), (0x194,1,32,32,64,32,-224,112), (0x194,1,32,32,64,64,-192,112), (0x194,1,32,32,64,96,-160,112), (0x194,1,32,32,64,128,-128,112), (0x194,1,32,32,64,160,-96,112), (0x194,1,32,32,64,192,-64,112), (0x194,1,32,16,64,224,-32,112), (0x194,1,32,32,192,0,-16,112), (0x194,1,32,32,192,32,16,112), (0x194,1,32,32,192,64,48,112), (0x194,1,32,32,192,96,80,112), (0x194,1,32,32,192,128,112,112), (0x194,1,32,32,192,160,144,112), (0x194,1,32,32,192,192,176,112), (0x194,1,32,32,192,224,208,112), (0x200,1,0,0,0,0,240,112),
    (0x194,1,32,32,96,0,-256,144), (0x194,1,32,32,96,32,-224,144), (0x194,1,32,32,96,64,-192,144), (0x194,1,32,32,96,96,-160,144), (0x194,1,32,32,96,128,-128,144), (0x194,1,32,32,96,160,-96,144), (0x194,1,32,32,96,192,-64,144), (0x194,1,32,16,96,224,-32,144), (0x194,1,32,32,224,0,-16,144), (0x194,1,32,32,224,32,16,144), (0x194,1,32,32,224,64,48,144), (0x194,1,32,32,224,96,80,144), (0x194,1,32,32,224,128,112,144), (0x194,1,32,32,224,160,144,144), (0x194,1,32,32,224,192,176,144), (0x194,1,32,32,224,224,208,144), (0x200,1,0,0,0,0,240,144),
    (0x200,1,0,0,0,0,-256,176), (0x200,1,0,0,0,0,-224,176), (0x200,1,0,0,0,0,-192,176), (0x200,1,0,0,0,0,-160,176), (0x200,1,0,0,0,0,-128,176), (0x200,1,0,0,0,0,-96,176), (0x200,1,0,0,0,0,-64,176), (0x200,1,0,0,0,0,-32,176), (0x200,1,0,0,0,0,-16,176), (0x200,1,0,0,0,0,16,176), (0x200,1,0,0,0,0,48,176), (0x200,1,0,0,0,0,80,176), (0x200,1,0,0,0,0,112,176), (0x200,1,0,0,0,0,144,176), (0x200,1,0,0,0,0,176,176), (0x200,1,0,0,0,0,208,176), (0x200,1,0,0,0,0,240,176),
]


# ---------------------------------------------------------------- WLDTEX.TM2

def replay_tm2(data: bytes) -> bytearray:
    """sec 18: a sector-packed stream of LoadImage calls into a blank 1024x512 VRAM.

    Per 2048-byte sector: u32 count, then count x { u16 x, y, w, h; u16 px[w*h] }.
    Blocks never straddle a sector, which is why an image wider than the space left
    is split into partial-row `w x 1` entries.
    """
    vram = bytearray(VRAM_W * VRAM_H * 2)
    blocks = 0
    for s in range(0, len(data), SECTOR):
        (count,) = struct.unpack_from('<I', data, s)
        o = s + 4
        for _ in range(count):
            if o + 8 > s + SECTOR:
                break
            x, y, w, h = struct.unpack_from('<4H', data, o)
            o += 8
            for r in range(h):
                dst = ((y + r) * VRAM_W + x) * 2
                src = o + r * w * 2
                vram[dst:dst + w * 2] = data[src:src + w * 2]
            o += w * h * 2
            blocks += 1
    return vram, blocks


UI_SHEET_VRAM = (960, 256)     # the shared FFT UI sheet, 4bpp -- sec 15 #9
UI_SHEET_ROW_SHIFT = 32        # VRAM page row r == FRAME.BIN pixel row r + 32
UI_SHEET_ROWS = 240            # the 240 pixel rows; the CLUT tail follows, see below

# EVENT/FRAME.BIN's CLUT TAIL. FRAME.BIN is not one flat band — it uploads as THREE
# VRAM rects, and the third is a run of sixteen 16-entry CLUTs at file offset 0x9000:
# `0x9000 + N * 0x20` -> VRAM (960, 496 + N).  That is NOT the pixel band's row shift,
# which would put VRAM row 496 at file row 272 — where FRAME.BIN holds a `0500 0005`
# pixel checker.  So extending UI_SHEET_ROWS would have copied garbage OVER the
# palettes rather than supplying them.
#
# VERIFIED byte-identical, all 16 rows, against the live console VRAM of both world-map
# savestates that carry a settled map (`world_map_ss1_settled_dialog_closed.sstate` and
# `world_map_ss0_scenario_end_prequicksave.sstate`).  Row 496 is CLUT 0x7C3C; 498 is
# 0x7CBC, the cream active-label CLUT the "Menu" title tab draws through (sec 33.9a
# primitive 5); 501/502 are the menu glove's lit/shadow pair; 503 is 0x7DFC, the
# blue-grey deactivated twin (sec 15.21's mechanism, and the map cursor's own
# backgrounded ramp is a copy of it at (144,481) — see WorldMapPrimitives.PAL_DEACTIVATED).
CLUT_TAIL_FILE = 0x9000        # FRAME.BIN offset of the first CLUT
CLUT_TAIL_VRAM = (960, 496)    # where CLUT N lands
CLUT_TAIL_COUNT = 16           # 496..511 is the rest of VRAM; the file's own tail is longer


def overlay_ui_sheet(vram: bytearray, frame_bin: Path):
    """Blit EVENT/FRAME.BIN's band into the VRAM page WLDTEX.TM2 leaves empty.

    Returns (pixel rows copied, CLUT rows copied).
    """
    if not frame_bin.exists():
        print(f'warning: {frame_bin} missing — no cursor, pins or war funds',
              file=sys.stderr)
        return 0, 0
    data = frame_bin.read_bytes()
    x0, y0 = UI_SHEET_VRAM
    rows = UI_SHEET_ROWS
    for r in range(UI_SHEET_ROWS):
        src = (r + UI_SHEET_ROW_SHIFT) * 128
        if src + 128 > len(data):
            rows = r
            break
        dst = ((y0 + r) * VRAM_W + x0) * 2
        vram[dst:dst + 128] = data[src:src + 128]

    cx, cy = CLUT_TAIL_VRAM
    cluts = 0
    for n in range(CLUT_TAIL_COUNT):
        src = CLUT_TAIL_FILE + n * 0x20
        if src + 0x20 > len(data):
            break
        dst = ((cy + n) * VRAM_W + cx) * 2
        vram[dst:dst + 0x20] = data[src:src + 0x20]
        cluts += 1
    return rows, cluts


def tim_at(data: bytes, off: int):
    """Parse a PSX TIM header at `off`.

    -> (flags, (cx, cy, cw, ch), (ix, iy, iw, ih), img_off) or None.
    A port of `world_map_captures/dispatch.py`'s `tim_at`, which sec 35.1 verified
    against all 92 WLDPIC entries and sec 35.7 against the shadow ramp. `iw` counts
    HALFWORDS, not texels -- at 4bpp one halfword is four texels, at 8bpp two.
    """
    magic, flags = struct.unpack_from('<2I', data, off)
    if magic != 0x10:
        return None
    o = off + 8
    clut = (0, 0, 0, 0)
    if flags & 8:
        cb, cx, cy, cw, ch = struct.unpack_from('<I4H', data, o)
        clut = (cx, cy, cw, ch)
        o += cb
    ib, ix, iy, iw, ih = struct.unpack_from('<I4H', data, o)
    return flags, clut, (ix, iy, iw, ih), o + 12


def blit_tim(vram: bytearray, data: bytes, off: int) -> tuple:
    """Upload a TIM to the two VRAM rects its OWN HEADER names -- the console's
    `LoadImage`, and the reason no destination is passed in.

    Returns (clut_rect, image_rect) so the caller can report what moved.
    """
    t = tim_at(data, off)
    if t is None:
        raise ValueError(f'no TIM magic at {off:#x}')
    _flags, (cx, cy, cw, ch), (ix, iy, iw, ih), ioff = t
    if cw:
        for r in range(ch):
            src = off + 20 + r * cw * 2
            dst = ((cy + r) * VRAM_W + cx) * 2
            vram[dst:dst + cw * 2] = data[src:src + cw * 2]
    for r in range(ih):
        src = ioff + r * iw * 2
        dst = ((iy + r) * VRAM_W + ix) * 2
        vram[dst:dst + iw * 2] = data[src:src + iw * 2]
    return (cx, cy, cw, ch), (ix, iy, iw, ih)


def shadow_ramp(core: bytes) -> dict:
    """The drop shadow's 11-step subtractive ramp, read out of its own CLUT.

    sec 35.7: `entry k = 5-bit (k, k-1, k-2) clamped at 0, for k = 0..10`, and
    entries 11..15 are 0x801F, an unused sentinel. Emitted so the port can SAY the
    ramp is eleven deep rather than assume sixteen -- and so a day the disc says
    otherwise is a diff rather than a picture that is subtly wrong.
    """
    o = SHADOW_TIM - WLDCORE_BASE
    pal = struct.unpack_from('<16H', core, o + 20)
    levels = [[p & 31, (p >> 5) & 31, (p >> 10) & 31] for p in pal]
    depth = 0
    while depth < 16 and levels[depth] == [max(0, depth - k) for k in range(3)]:
        depth += 1
    return {"clut": [int(p) for p in pal], "levels": levels, "depth": depth,
            "sentinel": sorted({int(p) for p in pal[depth:]})}


# ---------------------------------------------------------------- WLDCORE.BIN

class Core:
    def __init__(self, data: bytes):
        self.d = data

    def resident(self, a: int) -> bool:
        return WLDCORE_BASE <= a < WLDCORE_BASE + len(self.d) - 4

    def u32(self, a): return struct.unpack_from('<I', self.d, a - WLDCORE_BASE)[0]
    def u16(self, a): return struct.unpack_from('<H', self.d, a - WLDCORE_BASE)[0]
    def s16(self, a): return struct.unpack_from('<h', self.d, a - WLDCORE_BASE)[0]

    # --- nodes (sec 30.1, and sec 35.2 for the second table) ----------------
    def nodes(self):
        out = []
        for i in range(NODE_COUNT):
            x, ta, tb, y = struct.unpack_from(
                '<hBBh', self.d, NODE_SRC - WLDCORE_BASE + 8 * i)
            # The OTHER table -- see NODE_PIC_TBL. `picture` is 1-based and 0 means
            # "this node has no picture"; `kind` is the town gate.
            _b0, _b1, pic, kind = self.d[
                NODE_PIC_TBL - WLDCORE_BASE + NODE_PIC_STRIDE * i:
                NODE_PIC_TBL - WLDCORE_BASE + NODE_PIC_STRIDE * (i + 1)]
            out.append({
                "i": i,
                "name": NAMES[i],
                "map": [x, y],
                "screen": [x + PROJ[0], y + PROJ[1]],
                "tier": [ta, tb],
                # sec 30.5: the initialiser computes this, it is not tabled.
                "marker_frame": 106 + (1 if ta == 2 else 0),
                "name_frame": i + 1 + NAME_FRAME_BASE,
                "picture": pic,
                "kind": kind,
                # A PICTURE IS NOT A MENU (sec 35.10, and the port handoff's trap 2).
                # 19 nodes carry a picture; only 16 open a list -- the 15 towns plus
                # the Deep Dungeon, which FUN_8008D2C8 tests BEFORE the kind gate.
                # Murond Holy Place, Orbonne Monastery and Bethla Garrison have a
                # picture and NO menu, and a port that gates the list on `picture`
                # gives all three a menu the console does not.
                "opens_menu": kind == KIND_TOWN or i == DEEP_DUNGEON_NODE,
            })
        return out

    # --- the cel bank (sec 19.5, sec 24) -----------------------------------
    def cel(self, cid):
        slot = CEL_TABLE + 4 * cid
        if not self.resident(slot):
            return None
        ptr = self.u32(slot)
        if not self.resident(ptr):
            return None
        n = self.u32(ptr)
        if not 0 < n <= 64:
            return None
        parts = []
        for k in range(n):
            b = ptr + 12 + 8 * k
            if not self.resident(b + 8):
                return None
            w0, w1 = self.u32(b), self.u32(b + 4)
            parts.append({
                # part w0: byte0 = x+0x80, byte1 = y+0x80, byte2 = CLUT selector,
                #          byte3 = blend -- bit0 flip v, bit1 flip u (sec 30.6 note),
                #          bit2 8bpp (sec 30.3), bit3 vetoes the palette override
                #          (sec 24.2), bits 4-5 abr, bit 6 semi-transparent.
                "x": (w0 & 0xFF) - 0x80, "y": ((w0 >> 8) & 0xFF) - 0x80,
                "clut_sel": (w0 >> 16) & 0xFF, "blend": (w0 >> 24) & 0xFF,
                # part w1: byte0 = h, byte1 = w, byte2 = v, byte3 = u
                "h": w1 & 0xFF, "w": (w1 >> 8) & 0xFF,
                "u": (w1 >> 24) & 0xFF, "v": (w1 >> 16) & 0xFF,
            })
        tp, cl = self.u32(ptr + 4), self.u32(ptr + 8)
        return {
            "tpage_xy": [tp & 0xFFFF, tp >> 16],     # packed (Y << 16) | X, texel coords
            "clut_xy": [cl & 0xFFFF, cl >> 16],
            "parts": parts,
        }

    def frame(self, fid):
        slot = FRAME_TABLE + 4 * fid
        if not self.resident(slot):
            return None
        ptr = self.u32(slot)
        if not self.resident(ptr):
            return None
        n = self.u32(ptr)
        if not 0 < n <= 256:
            return None
        return [[self.u16(ptr + 4 + 4 * k), self.u16(ptr + 6 + 4 * k)] for k in range(n)]

    # --- routes (sec 12.4, sec 27.1) ---------------------------------------
    def routes(self):
        out = []
        for r in range(ROUTE_COUNT):
            wp = self.u32(self.u32(WAYPOINT_TABLE_PTR) + 4 * r)
            o = wp - WLDCORE_BASE
            a, b = self.d[o + 1], self.d[o + 2]
            pp = self.u32(self.u32(POLYLINE_TABLE_PTR) + 4 * r)
            n = self.s16(pp)
            # The polyline stores PAIRS of edge vertices -- the ribbon's cross-section.
            # A quad is two consecutive pairs, i.e. four shorts (sec 30 / sec 12.4's
            # "every 4th vertex", read as data rather than as a stride).
            poly = [[self.s16(pp + 2 + 4 * k), self.s16(pp + 4 + 4 * k)] for k in range(n)]
            out.append({"r": r, "a": a, "b": b, "length": self.d[o + 3],
                        "waypoints": self.waypoints(wp), "polyline": poly})
        return out

    def waypoints(self, wp):
        """The TRAVEL path -- a different table from the ribbon's (sec 27.1).

            waypoint list: { u8 n; u8 node_from; u8 node_to; u8 length }
                           then n x { s16 x, y, z(=0), heading; u32 d }

        `heading` is a 12-bit angle, 4096 to the turn, measured as `ratan2(-dx, dy)`:
        0 = +y (south), 1024 = -x (west), 2048 = -y (north), 3072 = +x (east). The
        marker's frame list is `(fast ? 24 : 16) + (((heading + 256) >> 9) & 7)` --
        FUN_8008F434, sec 27.3.

        `d` is the leg's duration: the console spends **2*d + 1** vsyncs on a leg, one of
        them held at the endpoint. The twelve legs of sec 29.6's watched traversal sum to
        exactly its 94 vsyncs, and no other reading of `d` ends the walk on its v321.

        These are the ribbon polyline's SIBLING, not the ribbon: that table stores PAIRS
        of edge vertices for drawing a strip, while these are single points the marker
        actually walks.
        """
        o = wp - WLDCORE_BASE
        n = self.d[o]
        out = []
        for k in range(n):
            x, y, _z, h, d = struct.unpack_from('<4hI', self.d, o + 4 + 12 * k)
            out.append({"xy": [x, y], "heading": h & 0xFFF, "d": d})
        return out


def win_field(world: bytes, rec: int, field: str) -> int:
    """One field of WORLD.BIN window record `rec`. sec 33.2's table, read from disc."""
    o = WIN_ARRAY + WIN_STRIDE * rec + WIN_FIELDS[field] - WORLD_BIN_BASE
    if field in ('tbl', 'fn'):
        return struct.unpack_from('<I', world, o)[0]
    v = struct.unpack_from('<H', world, o)[0]
    return v - 0x10000 if (field in WIN_SIGNED and v & 0x8000) else v


def menu_entries(world: bytes, table: int, rows: int) -> list:
    """rec+0x24 -> one signed short per row: the WINDOW ID that row opens (sec 33.2)."""
    o = table - WORLD_BIN_BASE
    return [struct.unpack_from('<h', world, o + 2 * i)[0] for i in range(rows)]


def lzw_message(lzw: bytes, msgid: int) -> str:
    """Message `msgid` out of EVENT/WORLD.LZW, without a savestate.

    FUN_800E6EDC's addressing, sourced from the archive instead of from RAM:
    section = (id & 0xF800) >> 11 indexes the file's own 32 x u32 header, and within
    a section a string is found by walking forward over (byte & 0xFE) == 0xFE
    terminators `id & 0x7FF` times. The header's entries ARE the relative bases the
    game's BSS pointer table holds at 0x801CD8A4 once WORLD.BIN has loaded.
    """
    from decode_fft_text import decode_bytes
    section = (msgid & 0xF800) >> 11
    if section >= LZW_SECTIONS:
        raise ValueError(f'message {msgid:#06x}: section {section} is past the archive')
    base = struct.unpack_from('<I', lzw, 4 * section)[0]
    p = LZW_TEXT_BASE + base
    n = 0
    while n != (msgid & 0x7FF):
        if (lzw[p] & 0xFE) == 0xFE:
            n += 1
        p += 1
    e = p
    while (lzw[e] & 0xFE) != 0xFE:
        e += 1
    return decode_bytes(lzw[p:e])


def start_menu(world: bytes, lzw: bytes) -> dict:
    """WORLD.BIN window record 4 -- the whole START menu, sec 33.

    `rows` is `rec+0x1E + 1` and nothing else: FUN_800EBDCC wraps the cursor on that
    halfword, so six rows is ARITHMETIC ON A DISC BYTE rather than a remembered count.
    The entry table is nine long and the label string 0xA00F carries nine names, but
    `last` is 5, so rows 6..8 (Debug / Flag / Party) are unreachable in retail -- sec 34
    reached them by poking that one halfword to 8. They are emitted here as
    `unreachable_entries` so the port can say WHY the table is longer than the menu,
    without ever being able to show them.
    """
    last = win_field(world, MENU_WIN, 'last')
    rows = last + 1
    table = win_field(world, MENU_WIN, 'tbl')
    msg = win_field(world, MENU_WIN, 'msg')
    raw = lzw_message(lzw, msg)
    labels = [s.strip() for s in raw.replace('{NP}', '\x00').replace('\n', '').split('\x00')]
    if len(labels) < rows:
        raise ValueError(f'message {msg:#06x} decoded {len(labels)} labels for {rows} rows')
    windows = menu_entries(world, table, rows)
    extra = menu_entries(world, table, 9)[rows:]
    return {
        "window_record": MENU_WIN,
        "x": win_field(world, MENU_WIN, 'x'), "y": win_field(world, MENU_WIN, 'y'),
        "w": win_field(world, MENU_WIN, 'w'), "h": win_field(world, MENU_WIN, 'h'),
        "rows": rows, "last_row": last,
        "row_pitch": MENU_ROW_PITCH,
        "cursor_dx": MENU_CURSOR_DX, "cursor_dy": MENU_CURSOR_DY,
        "label_msg": msg, "entry_table": table,
        "close_levels": win_field(world, MENU_WIN, 'close'),
        "help_topic": win_field(world, MENU_WIN, 'help'),
        "entries": [{"row": i, "window": windows[i], "label": labels[i]}
                    for i in range(rows)],
        "unreachable_entries": extra,
        "_source": "WORLD.BIN window record 4 + EVENT/WORLD.LZW msg %#06x; "
                   "WORLD_MAP_SCREEN.md sec 33.2/33.3, sec 34.0-34.2" % msg,
    }


def place_list(world: bytes) -> dict:
    """WORLD.BIN window record 6 — the Move place list (sec 33.3 row 0).

    Its `h` is 0 on disc: the generic list driver sizes it from the row count, which is
    built at RUNTIME by FUN_80105E04 walking all 43 nodes and keeping `var[0x200+n] != 0`.
    `last` is 6, so seven rows are visible at a time and a longer list scrolls.

    Its entry table is SEVEN copies of `0x100D`, and FUN_800EBB08 strips `0x1000` as a
    presentation flag before using the rest as a window id — so every row of the place
    list opens window 13, whose handler (FUN_80105F7C) is the one that refuses the row
    flagged 4 and otherwise writes `var[0x33]`. That is emitted here rather than
    described, because it is the fact that decides which of the two records is the LIST
    and which is the PICK, and sec 33.3 names only the handlers.
    """
    table = win_field(world, PLACE_WIN, 'tbl')
    rows = win_field(world, PLACE_WIN, 'last') + 1
    entries = menu_entries(world, table, rows)
    return {
        "window_record": PLACE_WIN,
        "x": win_field(world, PLACE_WIN, 'x'), "y": win_field(world, PLACE_WIN, 'y'),
        "w": win_field(world, PLACE_WIN, 'w'), "h": win_field(world, PLACE_WIN, 'h'),
        "visible_rows": rows, "last_row": rows - 1,
        "row_pitch": MENU_ROW_PITCH,
        "cursor_dx": MENU_CURSOR_DX, "cursor_dy": MENU_CURSOR_DY,
        "entry_table": table,
        "close_levels": win_field(world, PLACE_WIN, 'close'),
        "help_topic": win_field(world, PLACE_WIN, 'help'),
        "opens": [e - ENTRY_PRESENTATION if e & ENTRY_PRESENTATION else e
                  for e in entries],
        "pick_window": PLACE_PICK_WIN,
        "node_known_var": VAR_NODE_KNOWN,
        "party_node_var": VAR_PARTY_NODE,
        "dest_var": VAR_MOVE_DEST,
        "_source": "WORLD.BIN window record %d (handler %#010x) + record %d "
                   "(handler %#010x); WORLD_MAP_SCREEN.md sec 33.3 row 0"
                   % (PLACE_WIN, PLACE_LIST_FN, PLACE_PICK_WIN, PLACE_PICK_FN),
    }


def pic_offsets(core: bytes) -> list:
    """Byte offset of every WLDPIC entry, from WLDCORE's own fencepost table.

    sec 35.2: `FUN_80068AB4(pic - 1)` reads sectors `[t[i], t[i+1])` with
    `t = 0x8009E0EC`. The table is 93 entries for 92 pictures, and `t[92] * 2048`
    is WLDPIC.BIN's exact size -- which is the check that it is a fencepost table and
    not 92 (start, length) pairs.
    """
    o = PIC_SECTOR_TBL - WLDCORE_BASE
    t = [struct.unpack_from('<I', core, o + 4 * i)[0] for i in range(PIC_COUNT + 1)]
    return [x * SECTOR for x in t]


def picture_slot(k: int) -> dict:
    """Slot `k` of the port's picture atlas -> the packet fields that reach it.

    Returns tpage/clut WORDS (what a primitive carries) alongside the VRAM halfword
    address (what the blit needs), because the two are different encodings of one
    placement and computing them apart is how they drift.
    """
    page, slot = divmod(k, PIC_PER_ROW * PIC_ROWS_PER_PAGE)
    col, row = slot % PIC_PER_ROW, slot // PIC_PER_ROW
    tx = page * PIC_PAGE_W
    ty = PIC_ROWS_PER_PAGE * 0 + PIC_PAGE_ORIGIN_Y
    vx = tx + col * PIC_SLOT_W
    vy = ty + row * PIC_SLOT_H
    cy = PIC_CLUT_Y0 + k
    return {
        # 8bpp, abr 0 -- the console's own 0x0298 with a different origin.
        "tpage": ((ty // 256) << 4) | ((tx // 64) & 0xF) | (1 << 7),
        "clut": ((cy & 0x1FF) << 6) | ((PIC_CLUT_X >> 4) & 0x3F),
        # uv is in TEXELS; at 8bpp one halfword is two texels, hence the doubling.
        "uv": [col * PIC_SLOT_W * 2, row * PIC_SLOT_H],
        "vram": [vx, vy],
        "clut_vram": [PIC_CLUT_X, cy],
    }


def place_pictures(vram: bytearray, wldpic: bytes, core: bytes,
                   nodes: list) -> list:
    """Decode every node-reachable WLDPIC entry and blit it into a slot of its own.

    The TIM parse is confirmed twice over: this reader against the file's own headers,
    and ShiShi's `PSXImages.xml`, which declares all 92 entries with hand-authored
    offsets (`palette at +20, 512 bytes; pixels at +544`) and agrees with the headers on
    palette offset, image offset, width and height for 92 of 92.
    """
    offsets = pic_offsets(core)
    if offsets[PIC_COUNT] != len(wldpic):
        raise ValueError(f'the fencepost table ends at {offsets[PIC_COUNT]} but '
                         f'WLDPIC.BIN is {len(wldpic)} bytes')
    order = sorted({int(n["picture"]) for n in nodes if n["picture"]})
    if len(order) > PIC_PER_ROW * PIC_ROWS_PER_PAGE * 8:
        raise ValueError(f'{len(order)} pictures do not fit the slot scheme')
    slots = {}
    for k, pid in enumerate(order):
        slot = picture_slot(k)
        vx, vy = slot["vram"]
        # REFUSE to overwrite. Every slot must be untouched by WLDTEX.TM2 and
        # FRAME.BIN -- if a future extractor change makes one of them land here, this
        # says so instead of silently painting over it.
        for r in range(PIC_SLOT_H):
            o = ((vy + r) * VRAM_W + vx) * 2
            if any(vram[o:o + PIC_SLOT_W * 2]):
                raise ValueError(f'picture slot {k} at ({vx},{vy}) is not empty')
        cx, cy = slot["clut_vram"]
        co = (cy * VRAM_W + cx) * 2
        if any(vram[co:co + 256 * 2]):
            raise ValueError(f'picture CLUT {k} at ({cx},{cy}) is not empty')

        base = offsets[pid - 1]
        t = tim_at(wldpic, base)
        if t is None:
            raise ValueError(f'WLDPIC entry {pid} carries no TIM magic')
        _flags, (_ccx, _ccy, cw, _cch), (_ix, _iy, iw, ih), ioff = t
        if (cw, iw * 2, ih) != (256, PICTURE_WH[0], PICTURE_WH[1]):
            raise ValueError(f'picture {pid} is {iw * 2}x{ih} / {cw}-entry, '
                             f'expected {PICTURE_WH[0]}x{PICTURE_WH[1]} / 256')
        vram[co:co + 512] = wldpic[base + 20: base + 20 + 512]
        for r in range(ih):
            src = ioff + r * iw * 2
            o = ((vy + r) * VRAM_W + vx) * 2
            vram[o:o + iw * 2] = wldpic[src:src + iw * 2]
        # READ IT BACK THROUGH THE PACKET. The blit above addressed VRAM in halfwords;
        # a primitive addresses it through `tpage` + a TEXEL uv, and `picture_slot`
        # computes those two encodings apart. This is the one check that they agree —
        # an off-by-one in the uv doubling, or a page/slot mix-up, survives everything
        # else here and surfaces as a picture that is subtly the wrong one.
        tx = (slot["tpage"] & 0xF) * 64
        ty = ((slot["tpage"] >> 4) & 1) * 256
        u0, v0 = slot["uv"]
        for r in range(ih):
            for c in range(iw * 2):
                o = ((ty + v0 + r) * VRAM_W + tx + ((u0 + c) >> 1)) * 2
                got = (vram[o] | (vram[o + 1] << 8)) >> (((u0 + c) & 1) * 8) & 0xFF
                if got != wldpic[ioff + r * iw * 2 + c]:
                    raise ValueError(
                        f'picture {pid} slot {k}: texel ({c},{r}) reads {got} through '
                        f'tpage {slot["tpage"]:#06x} uv {u0 + c},{v0 + r} but the disc '
                        f'says {wldpic[ioff + r * iw * 2 + c]}')
        slots[pid] = slot
    for n in nodes:
        pid = int(n["picture"])
        if pid:
            n["picture_slot"] = slots[pid]
    return order


def town(core: bytes, lzw: bytes) -> dict:
    """The town page — sec 35, the O-into-a-location screen.

    THE ROWS ARE FUN_8008D2C8's, as RULES rather than as a list. sec 35.10:

        if node == 22:                      /* Deep Dungeon, tested FIRST */
            n = var[101] + 1                /* a word: the floor counter */
            rows = [0xB8ED + i for i in range(n)]
        if node_record[node].byte3 != 1: return []      /* not a town */
        rows = [0xB85D, 0xB85E, 0xB85F]                 /* Bar, Shop, Soldier office */
        if var[144] and node in (9, 12, 14): rows.append(0xB860)   /* Fur shop */

    The two gates differ IN KIND and sec 27.4's variable-store regions say so without
    knowing what either gates: `101` is in the 0..127 word region, so it is a counter;
    `144` is in the 128..863 BIT region, so it is a flag. That is emitted here as
    `var_kind` so the port cannot quietly treat one as the other.

    WHAT EACH ROW LEADS TO is read (sec 35.9) and deliberately NOT built: the Bar
    pushes WLDCORE page mode 5, and the other three are one blocking call into
    WORLD.BIN with a different selector — `FUN_80133478(0 / 0x65 / 0x64)`, which sec 36
    then read as ONE 28-state machine entered at three different states, sharing a
    single teardown. Three more screens; three more rounds. The `leads_to` field says
    where, so the page can surface the choice and stop.
    """
    ramp = shadow_ramp(core)
    rows = [
        {"msg": 0xB85D, "leads_to": {"kind": "wldcore_page_mode", "arg": 5}},
        {"msg": 0xB85E, "leads_to": {"kind": "world_bin_screen", "arg": 0x00}},
        {"msg": 0xB85F, "leads_to": {"kind": "world_bin_screen", "arg": 0x65}},
        {"msg": 0xB860, "leads_to": {"kind": "world_bin_screen", "arg": 0x64},
         "gate": {"var": 144, "var_kind": "bit", "nodes": [9, 12, 14]}},
    ]
    for r in rows:
        r["label"] = lzw_message(lzw, r["msg"])
    # Section 23 index 247 is EMPTY, which is what bounds the floor list at ten
    # (sec 35.10) — so this loop is the disc saying how many floors there are.
    floors = []
    for i in range(DD_FLOOR_MAX):
        try:
            name = lzw_message(lzw, DD_MSG_BASE + i)
        except (IndexError, ValueError):
            break
        if not name:
            break
        floors.append({"msg": DD_MSG_BASE + i, "label": name})
    return {
        "picture": {"xy": PICTURE_XY, "wh": PICTURE_WH,
                    "tpage": PICTURE_TPAGE, "clut": PICTURE_CLUT},
        # The shadow is a CEL, not 28 hand-authored quads. Frame list 11 -> cel 15,
        # whose 28 parts reproduce the console's 28 packets — xy, wh AND uv, all
        # 28 — when drawn at SHADOW_XY. That anchor is the unique (dx, dy) in
        # -128..128 that does so, solved against `world_map_ss4_town_menu_open`'s
        # ordering table; it is a measurement, not a fit. So the port draws this
        # through `cel_quads` like every other sprite on the screen.
        "shadow": {"frame": SHADOW_FRAME, "xy": SHADOW_XY, "ramp": ramp},
        "box": {"xy": TOWN_BOX_XY, "wh": TOWN_BOX_WH,
                "content_xy": TOWN_CONTENT_XY, "content_wh": TOWN_CONTENT_WH,
                "row_pitch": TOWN_ROW_PITCH, "cursor_xy": TOWN_CURSOR_XY},
        "kind_town": KIND_TOWN,
        "deep_dungeon": {"node": DEEP_DUNGEON_NODE, "count_var": 101,
                         "var_kind": "word", "floors": floors},
        "rows": rows,
        "_source": "WORLD_MAP_SCREEN.md sec 35.6-35.10; the box, the row pitch and the "
                   "glove anchor are measured on the reference-assets savestate PAIR "
                   "world_map_ss{4_town_menu_open,5_town_row2}",
    }


def background_grid():
    """sec 15 #17: savestate-sourced. Positions are closed form, the packing is not."""
    out = []
    for i, (tp, cull, h, w, v, u, mx, my) in enumerate(BG_GRID):
        out.append({
            "row": i // 17, "col": i % 17, "tpage": tp, "cull": bool(cull),
            "w": w, "h": h, "u": u, "v": v,
            "map": [mx, my], "screen": [mx + PROJ[0], my + PROJ[1]],
        })
    return out


# ---------------------------------------------------------------------------
# THE NODE SCRIPT TABLE -- sec 29 (round 12).  What O on a node actually asks.
#
# `FUN_80091238(node, mask)` is a tiny BYTECODE INTERPRETER, not a lookup. Its program
# store is a flat blob in WLDCORE at `*(0x800D4674)` = 0x80097234:
#
#     u16 index[44]        byte offset of node i's SCRIPT LIST, from the blob base
#     u16 list[..], 0      byte offset of each script, 0-terminated
#     u16 program[..]      opcode / operand halfwords
#
# A **node script** is a run of CONDITIONS followed by exactly one EMIT. A failed
# condition abandons that script; an emit sets bit 0 of the result word plus one TYPE
# bit and stops. The caller's `mask` selects which emit kind it cares about, so one
# node's list serves several unrelated questions -- which is why "the node's scenario"
# is the wrong model. See CONTEXT.md -> Campaign spine, and sec 29.1 / 29.3.
#
# PORTED, not imported: `research/working_documents/world_map_captures/wldevent.py` is
# the authority for every number here and `wldevent.py check` is its suite. This module
# re-derives from the same disc bytes, the way every other block in this file does.
SCRIPT_BLOB = 0x80097234       # *(0x800D4674) in all three world-map captures
SCRIPT_BLOB_PTR = 0x800D4674
SCRIPT_DISPATCH = 0x8009EE50   # the 41-entry handler table the VM jumps through

# opcode -> (operand halfwords consumed, emit TYPE bits or None, what it does)
SCRIPT_OPS = {
    0x00: (0, None, 'nop'),
    0x01: (2, None, 'var[a] == b'),
    0x02: (2, None, 'var[a] >= b'),
    0x03: (2, None, 'var[a] <= b'),
    0x04: (1, None, 'party has job a'),
    0x05: (2, None, 'reserved2'), 0x06: (2, None, 'reserved2'),
    0x07: (2, None, 'reserved2'), 0x08: (2, None, 'reserved2'),
    0x09: (2, None, 'reserved2'), 0x0A: (2, None, 'reserved2'),
    0x0B: (2, None, 'reserved2'),
    0x0C: (1, None, 'reserved1'), 0x0D: (1, None, 'reserved1'),
    0x0E: (1, None, 'var[0x2C] >= a'),   # war funds, sec 32.6
    0x0F: (1, None, 'var[0x2C] <= a'),
    0x10: (2, None, 'date >= (a,b)'), 0x11: (2, None, 'date <= (a,b)'),
    0x12: (1, None, 'var[0x62] >= a'), 0x13: (1, None, 'var[0x62] <= a'),
    0x14: (1, None, 'reserved1'), 0x15: (1, None, 'reserved1'),
    0x16: (0, None, 'nop'),
    0x17: (3, None, 'reserved3'), 0x18: (4, None, 'reserved4'),
    0x19: (2, 0x008, 'EMIT8  a,b'),      # var[0x27] = a, FUN_8008047C(b)
    0x1A: (8, 0x004, 'EMIT4  a..h'),
    0x1B: (2, None, 'reserved2'),
    0x1C: (2, None, 'var[a] = b'),
    0x1D: (1, 0x010, 'EMIT10 a'),
    0x1E: (3, 0x020, 'EMIT20 a,b,c'),
    0x1F: (2, 0x040, 'EMIT40 a,b'),
    0x20: (2, 0x080, 'EMIT80 a,b'),
    0x21: (2, 0x100, 'EMIT100 a,b'),
    0x22: (1, 0x400, 'EMIT400 a'),
    0x23: (1, 0x800, 'EMIT800 a'),
    0x24: (1, 0x200, 'EMIT200 a'),
    0x25: (1, None, 'unit stat a'), 0x26: (1, None, 'unit stat a'),
    0x27: (1, None, 'unit stat a'), 0x28: (1, None, 'unit stat a'),
}

# TYPE bit -> the name the port uses. Only `enter`, `reveal_node` and `reveal_route`
# are modelled; the other six are NAMED rather than guessed (sec 29.3 -- the O handler
# asks for 0x008 then 0x040, and the map's own reveal runner asks for 0xF80).
SCRIPT_EMIT_KIND = {
    0x004: 'multi',
    0x008: 'enter',          # 0x19 -- (scenario_id, transition_mode); the hand-off
    0x010: 'unary10',        # the world-map message box (FUN_800683FC, msg 0x5800+a)
    0x020: 'triple20',
    0x040: 'setvar40',
    0x080: 'reveal_route',   # 0x20 -- (from_node, to_node) -> var[556 + route] = 1
    0x100: 'pair100',
    0x200: 'here200',
    0x400: 'reveal_node',    # 0x22 -- (node) -> var[512 + node] = 1
    0x800: 'unary800',
}

# Conditions the interpreter cannot decide offline: they read the party roster.
SCRIPT_ROSTER_OPS = {0x04, 0x25, 0x26, 0x27, 0x28}


def script_index(core: Core) -> list:
    """Byte offset of each node's script list, from the blob base. 44 slots -- the
    44th is the terminator, which is what bounds node 42's list."""
    n = core.u16(SCRIPT_BLOB) // 2
    return [core.u16(SCRIPT_BLOB + 2 * i) for i in range(n)]


def node_script_offsets(core: Core, node: int) -> list:
    """Byte offsets of node `node`'s scripts, in evaluation order."""
    lst = SCRIPT_BLOB + (script_index(core)[node] & 0xFFFE)
    out, k = [], 0
    while True:
        e = core.u16(lst + 2 * k)
        if e == 0:
            return out
        out.append(e & 0xFFFE)
        k += 1


def decode_script(core: Core, off: int) -> tuple:
    """Disassemble one script. -> (halfword_length, [(opcode, [operands])]).

    A script ends at its first EMIT, which is what makes the length checkable against
    the next entry in the node's list."""
    p, ins = off // 2, []
    while True:
        op = core.u16(SCRIPT_BLOB + 2 * p)
        if op not in SCRIPT_OPS:
            ins.append((op, []))
            return p + 1 - off // 2, ins
        n, emit, _ = SCRIPT_OPS[op]
        ins.append((op, [core.u16(SCRIPT_BLOB + 2 * (p + 1 + i)) for i in range(n)]))
        p += 1 + n
        if emit is not None:
            return p - off // 2, ins


def node_scripts(core: Core) -> dict:
    """The whole node script table as plain data -- `assets/world_map/events.json`.

    Campaign loads this, NOT the map: sec 32.9 point 1 is explicit that the map reports
    `node_entered` and Campaign asks the table. Keeping it out of `model.json` (which
    `WorldMapAssets` loads) makes that structural rather than a matter of discipline."""
    by_node, total = [], 0
    for i in range(NODE_COUNT):
        scripts = []
        for off in node_script_offsets(core, i):
            length, ins = decode_script(core, off)
            emit_op, emit_operands = ins[-1]
            mask = SCRIPT_OPS[emit_op][1]
            scripts.append({
                "offset": off,
                "halfwords": length,
                "conditions": [
                    {"op": op, "kind": SCRIPT_OPS[op][2], "operands": a,
                     "roster": op in SCRIPT_ROSTER_OPS}
                    for op, a in ins[:-1]
                ],
                "emit": {
                    "op": emit_op,
                    "mask": mask,
                    "kind": SCRIPT_EMIT_KIND.get(mask, "unknown"),
                    "operands": emit_operands,
                },
            })
        total += len(scripts)
        by_node.append({"node": i, "name": NAMES[i], "scripts": scripts})
    return {
        "_source": "WLDCORE.BIN node script table; see WORLD_MAP_SCREEN.md sec 29",
        "blob": "0x%08X" % SCRIPT_BLOB,
        "blob_pointer": "0x%08X" % SCRIPT_BLOB_PTR,
        "dispatch_table": "0x%08X" % SCRIPT_DISPATCH,
        "entry_point": "FUN_80091238(node, mask)",
        "semantics": ("a node script is conditions then one emit; a failed condition "
                      "abandons the script, an emit sets bit 0 plus one TYPE bit and "
                      "stops. the caller's mask selects which emit kind it wants."),
        "emit_kinds": {"0x%03X" % k: v for k, v in sorted(SCRIPT_EMIT_KIND.items())},
        "script_count": total,
        "by_node": by_node,
    }


def main():
    ap = argparse.ArgumentParser(description='Extract the FFT world map for Godot')
    default = fft_extract_root()
    ap.add_argument('fft_path', nargs='?', default=str(default),
                    help=f'FFT extract dir (default: {default})')
    args = ap.parse_args()

    world = Path(args.fft_path) / 'WORLD'
    tm2, core_bin = world / 'WLDTEX.TM2', world / 'WLDCORE.BIN'
    world_bin = world / 'WORLD.BIN'
    wldpic_bin = world / 'WLDPIC.BIN'
    lzw_bin = Path(args.fft_path) / 'EVENT' / 'WORLD.LZW'
    for p in (tm2, core_bin, world_bin, wldpic_bin, lzw_bin):
        if not p.exists():
            print(f'error: {p} not found', file=sys.stderr)
            return 1

    out_dir = Path(__file__).resolve().parent.parent / 'assets' / 'world_map'
    out_dir.mkdir(parents=True, exist_ok=True)

    core_bytes = core_bin.read_bytes()
    vram, blocks = replay_tm2(tm2.read_bytes())
    rows, cluts = overlay_ui_sheet(vram, (Path(args.fft_path) / 'EVENT' / 'FRAME.BIN'))
    # The town page's drop-shadow ramp, uploaded to the two rects its own TIM header
    # names -- (0,487) for the 16-entry CLUT and (512,464) for the 96x48 texels.
    # WLDTEX.TM2 leaves both empty, which is why cel 15 has drawn nothing until now.
    sh_clut, sh_img = blit_tim(vram, core_bytes, SHADOW_TIM - WLDCORE_BASE)

    core = Core(core_bytes)
    node_list = core.nodes()
    # The 19 town backgrounds, each into a slot of its own. This MUTATES `vram`, so it
    # has to happen before the file is written -- see the block below.
    pic_order = place_pictures(vram, wldpic_bin.read_bytes(), core_bytes, node_list)

    (out_dir / 'vram.bin').write_bytes(bytes(vram))
    print(f'vram.bin      {VRAM_W}x{VRAM_H} u16  ({blocks} TM2 blocks '
          f'+ {rows} FRAME.BIN rows at (960,256) '
          f'+ {cluts} FRAME.BIN CLUTs at (960,496) '
          f'+ {len(pic_order)} WLDPIC town backgrounds)')
    print(f'shadow ramp   WLDCORE TIM {SHADOW_TIM:#010x}: '
          f'{sh_clut[2]}x{sh_clut[3]} CLUT at {sh_clut[:2]}, '
          f'{sh_img[2]}x{sh_img[3]} halfwords at {sh_img[:2]}')

    world_bytes = world_bin.read_bytes()
    lzw_bytes = lzw_bin.read_bytes()
    menu = start_menu(world_bytes, lzw_bytes)
    places = place_list(world_bytes)
    town_page = town(core_bytes, lzw_bytes)
    cels = {str(c): core.cel(c) for c in range(512) if core.cel(c)}
    frames = {str(f): core.frame(f) for f in range(512) if core.frame(f)}
    model = {
        "_source": "WLDCORE.BIN + WLDTEX.TM2; see WORLD_MAP_SCREEN.md sec 30",
        "projection": list(PROJ),
        "draw_area": DRAW_AREA,
        "nodes": node_list,
        "routes": core.routes(),
        "cels": cels,
        "frames": frames,
        "layout": {
            "aperture_sub": APERTURE_SUB, "aperture_add": APERTURE_ADD,
            "cursor_frame": CURSOR_FRAME,
            "month_frame_base": MONTH_FRAME_BASE, "digit_frame_base": DIGIT_FRAME_BASE,
            "date_xy": DATE_XY, "date_step": DATE_STEP, "funds_xy": FUNDS_XY,
        },
        "background_grid": background_grid(),
        "background_grid_source": "SAVESTATE, not disc -- WORLD_MAP_SCREEN.md sec 15 #17",
        "start_menu": menu,
        "place_list": places,
        "town": town_page,
    }
    (out_dir / 'model.json').write_text(json.dumps(model, separators=(',', ':')))
    print(f'model.json    {len(model["nodes"])} nodes, {len(model["routes"])} routes, '
          f'{len(cels)} cels, {len(frames)} frame lists')

    # The node script table goes in its OWN file, loaded by Campaign rather than by
    # `WorldMapAssets` -- sec 32.9 point 1. Anything in model.json is reachable from
    # WorldMapScene by construction, and this table is not the map's business.
    events = node_scripts(core)
    (out_dir / 'events.json').write_text(json.dumps(events, separators=(',', ':')))
    kinds = Counter(s['emit']['kind']
                    for n in events['by_node'] for s in n['scripts'])
    print(f'events.json   {len(events["by_node"])} nodes, '
          f'{events["script_count"]} node scripts: '
          + ' | '.join(f'{k} {v}' for k, v in kinds.most_common()))
    print(f'start menu    ({menu["x"]}, {menu["y"]}) {menu["w"]}x{menu["h"]}, '
          f'{menu["rows"]} rows @ {menu["row_pitch"]}: '
          + ' / '.join(e["label"] for e in menu["entries"]))
    print(f'place list   ({places["x"]}, {places["y"]}) w {places["w"]}, '
          f'{places["visible_rows"]} rows visible, every row opens window '
          f'{sorted(set(places["opens"]))}')

    nodes = model["nodes"]
    pics = [n for n in nodes if n["picture"]]
    menus = [n for n in nodes if n["opens_menu"]]
    silent = [n["name"] for n in pics if not n["opens_menu"]]
    print(f'town page     {len(pics)} nodes carry a picture, {len(menus)} open a menu; '
          f'picture but NO menu: {", ".join(silent)}')
    print(f'              rows {" / ".join(r["label"] for r in town_page["rows"])}; '
          f'{len(town_page["deep_dungeon"]["floors"])} Deep Dungeon floors; '
          f'shadow ramp {town_page["shadow"]["ramp"]["depth"]} deep')
    # ADR-0001's "one idempotent script" only helps if a bad extract is LOUD. These
    # three are sec 35's own counts and each has a distinct failure behind it: the
    # wrong node table (19/16 collapse to 43 or 0), a mis-sized ramp (a shadow that
    # is subtly the wrong depth), and the trap that gives Murond, Orbonne and Bethla
    # a menu the console does not give them.
    bad = []
    if len(pics) != 19:
        bad.append(f'{len(pics)} nodes carry a picture, expected 19 (sec 35.10)')
    if len(menus) != 16:
        bad.append(f'{len(menus)} nodes open a menu, expected 16 (sec 35.10)')
    if town_page["shadow"]["ramp"]["depth"] != SHADOW_RAMP_DEPTH:
        bad.append(f'shadow ramp is {town_page["shadow"]["ramp"]["depth"]} deep, '
                   f'expected {SHADOW_RAMP_DEPTH} (sec 35.7)')
    if bad:
        for b in bad:
            print(f'error: {b}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
