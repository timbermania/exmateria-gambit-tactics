#!/usr/bin/env python3
"""Extract the FFT battlefield range-overlay tile graphic (blue move / red
attack / yellow target panels) + the floating tile-cursor sprite from the
ISO into a Godot-ready indexed texture + palette LUT.

This is an ISO-derived asset (see godot-learning/CONTEXT.md "Battle
range-overlay tile"): pure-derived, reproducible, host-agnostic. The PSX
emulator was only the discovery/verification oracle; nothing here reads it.

Two sources (both in the ISO extract):
  - TEXELS: the shared 4bpp indexed bitmap the panels sample. NOT in
    BATTLE.BIN — it is a raw-sector disc asset at LBA 0xE68 (read by the
    battle-init loader FUN_80045154 / LoadImage @0x80045178 into VRAM page
    (960,256), tpage 0x3F). Asset layout: texels at +0x1000 (256x256 4bpp,
    0x8000 B); the in-game tile is the 14x14 sub-rect at U[0..13] V[160..173];
    the tile cursor (floating dagger arrow) is U[66..78] V[128..151] (13x24).
  - PALETTES: the runtime CLUTs live as BGR555 rodata in BATTLE.BIN at
    0x2DAE4..0x2DC23 — 9 consecutive 32-byte palettes (slots 0..8). The
    parser emits all 9 so palette_row N maps 1:1 to BATTLE.BIN slot N
    (== VRAM clut_y offset from 496). The shimmer of blue/red is a 15-phase
    barber-pole rotation of colors 1..15 (idx 0 pinned transparent),
    reproduced in the Godot shader; the gold cursor palette (slot 4) is
    static.

RE references: research/CONTEXT.md "Battlefield range-overlay tile palettes".

Outputs (regenerable bulk, gitignored):
  assets/sprites/textures/RANGETILE.tga          256x256 8bpp grayscale, value = index*17
  assets/sprites/textures/RANGETILE.palette.tga  16x9 RGBA (rows = BATTLE.BIN slot N)
  assets/sprites/textures/RANGETILE.json          tile + cursor UV rects + palette names
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _repo_paths  # noqa: E402
from fft_exporter.exporters.tga import write_grayscale_tga, write_rgba_tga  # noqa: E402

# --- disc / asset geometry (all from static RE, cross-verified live + raw-ISO) ---
TEXTURE_LBA = 0xE68            # raw sector of the battle texture asset
ASSET_SECTORS = 19            # 19 * 2048 = 0x9800 bytes
SECTOR_SIZE = 2352            # Mode 2/2352 (see fft_iso_patcher/iso_sectors.py)
USER_DATA_OFFSET = 0x18      # 2048-byte payload starts here in each raw sector
USER_DATA_SIZE = 2048
TEXELS_OFFSET = 0x1000        # texels within the loaded asset
TEX_W, TEX_H = 256, 256      # 4bpp -> 128 bytes/row
TEXELS_SIZE = TEX_W * TEX_H // 2  # 0x8000

# in-game tile sub-rect (cursor path; the 4-tile panel stitches four of these).
# U[0..13] V[160..173] inclusive => 14x14 texels.
TILE_UV = {"x": 0, "y": 160, "w": 14, "h": 14}

# Floating tile-cursor sprite (the downward-pointing dagger). Visually derived
# from the texels (not from a disassembly prim-build site — the cursor's UVs are
# runtime-assembled, not baked into a SPRT template in BATTLE.BIN/SCUS rodata).
CURSOR_UV = {"x": 66, "y": 128, "w": 13, "h": 24}

# --- BATTLE.BIN palette rodata (file offsets; RAM = file + 0x80066FFE) ---
# 9 consecutive 32-byte CLUTs at 0x2DAE4 (RAM 0x80094AE4); slots 9..15 are zero.
# Index = BATTLE.BIN slot # = VRAM clut_y offset from 496 = "palette_row" uniform.
PAL_BASE = 0x2DAE4
PAL_BYTES = 32  # 16 colors * 2 bytes (BGR555)
PAL_COUNT = 9   # non-zero entries; 10..15 are all-zero padding
PALETTE_NAMES = [
    "blue",      # slot 0 — move range, barber-pole
    "red",       # slot 1 — attack range, barber-pole
    "slot2",     # slot 2 — unnamed (idx15=#e7ce73 gold tail)
    "yellow_a",  # slot 3 — target family A
    "cursor",    # slot 4 — TILE CURSOR (dark→gold, idx15=#efce7b)
    "slot5",     # slot 5 — unnamed
    "slot6",     # slot 6 — duplicate of slot 2 bytes
    "slot7",     # slot 7 — unnamed
    "yellow_b",  # slot 8 — target family B
]
assert len(PALETTE_NAMES) == PAL_COUNT

ANIMATION = {"phases": 15, "speed": 2, "idx0_fixed_transparent": True,
             "kind": "barber_pole_rotation"}

# Reproducibility fixtures (live-RAM + raw-ISO verified — fail loud if the
# source bytes ever drift, e.g. wrong ISO region / endianness).
BLUE_PALETTE_HEX = ("0000 26e1 47d9 68d1 89cd aac5 cbc1 ecbd "
                    "eeb9 ecbd cbc1 aac5 89cd 68d1 47d9 26e1").replace(" ", "")
TILE_FIRST_ROW = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14]  # row 160, cols 0..12


# --- feedback-HUD digit strip (issue #88) ----------------------------------
# The damage/HP digit sprites '0'..'9' and '/' live in RANGETILE.tga as a
# fixed-pitch strip. The x-pitch (8 from origin 168) is ROM-confirmed (decoding
# the live label primitives + atlas render, 2026-06-17 provenance pass). The
# y-extent was CORRECTED this pass: the old cell (y52, h11) clipped the tops of
# '6'/'8' (which reach y49) and the descenders to y62 — the "6 cut off" bug.
# Full glyph span is y49..62, so the cell is now 8x14 from y49.
DIGIT_GLYPHS = "0123456789/"
DIGIT_ORIGIN = (168, 49)      # top-left of glyph '0' in RANGETILE.tga texels
DIGIT_PITCH_X = 8             # 11 glyphs * 8 = 88 -> origin 168..256 (atlas edge)
DIGIT_CELL_W, DIGIT_CELL_H = 8, 14   # y49..62 full glyph height (was 8x11@y52,
                                     # which clipped 6/8 tops + descenders)

# The damage/status number renders as a SINGLE textured pass: the RANGETILE
# digit glyph — whose own indices encode the shape (index 1 = the dark outline
# ring, index 2 = the white fill, indices 3/5/6 = cool-grey anti-alias edges) —
# through ONE CLUT, VRAM id 0x7d7c. Read from live VRAM at the
# `battle_wizard_melee_777_number_onscreen` save state (2026-07-25, via the
# pcsx rig + savestate-vram-patching methodology): EVERY colour in the
# dmg_steady.png framebuffer capture maps to an entry here (idx2 white fill,
# idx1 dark outline, idx5/6 = the (120,136,152)/(176,184,192) cool edges the
# capture shows). This CORRECTS the earlier issue-#88 note that called this a
# two-layer shadow(0x7d7c)+fill(0x7c3c) render: 0x7c3c is an unrelated tan UI
# label palette, and there is NO separate shadow sprite for the popup. The
# same white glyph art is what the vitals panel draws (through its own menu
# CLUT 0x7cbc) — which is why the two "look almost identical".
DIGIT_CLUT = 0x7d7c
# Raw BGR555 LE words of CLUT 0x7d7c (VRAM (960,501)), idx0 transparent. Kept
# raw so the reproducibility fixture below fails loud if the palette ever drifts.
DIGIT_CLUT_BGR555 = [
    0x0000, 0x10a5, 0x77bd, 0x2928, 0x39ac, 0x4e2f, 0x62f6, 0x18ee,
    0x10d2, 0x1516, 0x157c, 0x0cec, 0x1174, 0x19f7, 0x227a, 0x3b3c,
]
assert len(DIGIT_CLUT_BGR555) == 16 and DIGIT_CLUT_BGR555[0] == 0x0000, \
    "number CLUT must be 16 entries with a transparent idx0"
assert DIGIT_CLUT_BGR555[2] == 0x77bd and DIGIT_CLUT_BGR555[1] == 0x10a5, \
    "number CLUT drifted (idx2 white fill / idx1 dark outline) — re-read VRAM 0x7d7c"
MENU_CLUT = None  # status-icon palette: applied by the over-unit renderer

# Reproducibility fixture — glyph '0' (an oval) at DIGIT_ORIGIN, 8x14 indices
# (3 blank rows y49..51 above the oval body, which lives y52..59). Fails loud
# during extraction if the digit strip ever drifts (wrong atlas / origin / cell).
DIGIT_ZERO_FIXTURE = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 1, 5, 2, 2, 5, 1, 0],
    [1, 5, 2, 3, 3, 2, 5, 1],
    [1, 2, 5, 1, 1, 5, 2, 1],
    [1, 2, 5, 1, 1, 5, 2, 1],
    [1, 5, 2, 3, 3, 2, 5, 1],
    [0, 1, 5, 2, 2, 5, 1, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
]


# --- formation zodiac-sign glyphs (FORMATION_SCREEN.md §14.3) ---------------
# The unit-info panel draws the unit's zodiac symbol as a RANGETILE sprite. The
# 13 signs live in TWO fixed-pitch rows of the atlas (user-supplied source,
# re-verified this pass by extracting both strips from the committed
# RANGETILE.tga — see /tmp/band/zodiac_cells.png):
#   Row 1: (0,42), 7 signs Aries..Libra          — strip ends at x=168 (=7*24)
#   Row 2: (0,62), 6 signs Scorpio..Serpentarius — strip ends at x=144 (~6*24)
# Each cell is 24x20 at a 24px pitch (168/7 = 24; 6*24 = 144 ≈ the doc's 143).
# The glyph art is a dithered indexed pattern (the shape emerges through a menu
# CLUT, NOT the battle range-overlay palettes) — same class as the digit strip.
#
# CLUT/colors: the panel renders the sign as a desaturated dark-brown ink on the
# tan window (oracle: /tmp/band/oracle_panel_zoom.png bottom-left Capricorn). The
# true palette is a menu/window CLUT (same family as the word-label CLUT 0x7cbc),
# which is NOT in RANGETILE.palette.tga (that file only carries the 9 battle
# range/cursor CLUTs from BATTLE.BIN 0x2DAE4). Until that exact menu CLUT is
# read from VRAM, we reuse the digit CLUT (0x7d7c) colours as a documented
# default — the port can override the tint (mirror `digit_palette_colors`).
ZODIAC_NAMES = [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra",       # row 1
    "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",          # row 2
    "Serpentarius",
]
ZODIAC_ROW1_ORIGIN = (0, 42)   # top-left of Aries; 7 signs across
ZODIAC_ROW2_ORIGIN = (0, 62)   # top-left of Scorpio; 6 signs across
ZODIAC_ROW1_COUNT = 7
ZODIAC_ROW2_COUNT = 6
ZODIAC_CELL_W, ZODIAC_CELL_H = 24, 20
ZODIAC_PITCH_X = 24
ZODIAC_CLUT = DIGIT_CLUT        # documented fallback (see section header)


def zodiac_set() -> dict:
    """The 13 formation zodiac-sign glyphs (Aries..Serpentarius), one cell per
    sign in reading order across two fixed-pitch atlas rows (§14.3). Emitted the
    same way as the digit strip: `cells` (24x20 at a 24px pitch), the render
    `clut`, and its 16 RGBA `colors` (reused from the number CLUT as a documented
    default — the panel's true menu CLUT is not in RANGETILE.palette.tga)."""
    cells = fixed_pitch_cells(ZODIAC_ROW1_ORIGIN[0], ZODIAC_ROW1_ORIGIN[1],
                              ZODIAC_CELL_W, ZODIAC_CELL_H, ZODIAC_PITCH_X,
                              ZODIAC_ROW1_COUNT)
    cells += fixed_pitch_cells(ZODIAC_ROW2_ORIGIN[0], ZODIAC_ROW2_ORIGIN[1],
                               ZODIAC_CELL_W, ZODIAC_CELL_H, ZODIAC_PITCH_X,
                               ZODIAC_ROW2_COUNT)
    colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
              for i, w in enumerate(DIGIT_CLUT_BGR555)]
    return {"names": list(ZODIAC_NAMES), "clut": ZODIAC_CLUT, "colors": colors,
            "cells": cells}


# --- feedback-HUD status-bubble icons (issue #88) --------------------------
# BATTLE.BIN holds two parallel byte arrays giving each status type's icon
# position: Status_Bubble_Icon_X (RAM 0x800949dc) and _Y just after it. There
# are 20 icons across 3 rows. BOTH bytes are already atlas texels — Y a row
# (0xb0/0xbc/0xc8 = 176/188/200), X a COLUMN — so the mapping is the identity.
# Cells are read from the table (faithful: status_type -> cell), not eyeballed.
#
# This used to remap X onto a synthetic 14px grid at origin x=16, which shifted
# every cell one column right and made every over-unit status bubble in the port
# render its right-hand NEIGHBOUR's glyph (AT_MARKER_RENDERING.md §8.2). The
# falsifying evidence: the live GPU packet for the "AT" marker draws u=114, and
# 114 is exactly the ROM's table byte for entry 8 — under the old remap that
# entry emitted 128, which is the flare icon. The strip's first cell is 16 wide
# and the rest are 14, so there is no single pitch to snap to in the first place.
# `test_entry_eight_is_the_at_glyph` is the guard; non-blankness alone cannot
# catch this class, because a shifted cell still lands on a glyph.
# File offset = RAM - 0x80067000 (same base as the palette rodata above).
STATUS_ICON_X_OFF = 0x2D9DC
STATUS_ICON_Y_OFF = 0x2D9F4
STATUS_ICON_COUNT = 20
ICON_CELL_W, ICON_CELL_H = 14, 12


def icon_cells_from_arrays(xs, ys) -> list[dict]:
    """Map parallel table (X, Y) bytes to atlas cells (one per status type).
    Both bytes are atlas texels already; this is the identity plus the cell size."""
    return [{"x": x, "y": y, "w": ICON_CELL_W, "h": ICON_CELL_H}
            for x, y in zip(xs, ys)]


def status_icon_set(battle_bin: bytes) -> dict:
    """The status-bubble icon set, read from BATTLE.BIN's parallel X/Y arrays."""
    xs = battle_bin[STATUS_ICON_X_OFF:STATUS_ICON_X_OFF + STATUS_ICON_COUNT]
    ys = battle_bin[STATUS_ICON_Y_OFF:STATUS_ICON_Y_OFF + STATUS_ICON_COUNT]
    return {"clut": MENU_CLUT, "count": STATUS_ICON_COUNT,
            "cells": icon_cells_from_arrays(xs, ys)}


# --- the "AT" active-turn marker (AT_MARKER_RENDERING.md) -------------------
# The bobbing gold "AT" over the acting unit. It is slot 21 of the same 22-slot
# over-head carousel the status icons above are slots 0..19 of — but it is the
# only slot whose cell is a CODE LITERAL rather than a table entry: the tables'
# own entries 20 and 21 are (0,0xB0) and (0,0), and the renderer instead writes
# u=114 / v=0xB0 at 0x8007EF10/0x8007EF18 and v=0xB0+0x0C at 0x8007EF2C. So it
# cannot come out of `status_icon_set` and is emitted here as a named cell pair
# instead — the port must NOT hard-code the rect (root ADR-0001: the extractor
# is the source of the truth on disk).
#
# Animation is one bit: phase = (per-unit 60Hz counter >> 4) & 1 picks the frame
# AND subtracts 1 from the screen Y (§6.2). 16 frames per phase, 32-frame period.
AT_MARKER_U = 114            # 0x8007EF10 — literal, not a table read
AT_MARKER_V = 0xB0           # 0x8007EF18 — 176, the strip's first row
AT_MARKER_FRAME_DV = 0x0C    # 0x8007EF2C — frame B is one 12px row down
AT_MARKER_PHASE_FRAMES = 16  # bit 4 of the tick counter -> 16 frames per phase
AT_MARKER_BOB_PX = 1         # `addiu v0, v1, -0x1` on screen Y (0x8007F134)
AT_MARKER_CLUT = DIGIT_CLUT  # 0x7887's 16 colours are byte-identical to 0x7d7c (§3.3)


# The per-sprite-type marker offset switch (`FUN_8007eb8c` tail, 0x8007ECE4 …
# 0x8007EE7C), transcribed from the disassembly. Unlike the icon strip this is NOT a
# ROM data table — it is a jump table over hard-coded `addiu` immediates — so it is
# carried here as data with its addresses cited, exactly as the marker's cells are.
#
# The switch key is `sprite_attr_table[unit[+6] * 4]`, byte 0 of BATTLE.BIN 0x2D748:
# the **SHP type**, which `tools/parse_sprite_types.py` already extracts. The jump
# table at 0x80067810 maps the eight SHP types onto five distinct rows; any key >= 8
# (WEP1/WEP2/EFF1/EFF2) takes the default row. Verified against the extraction:
# OTHER is exactly sprite ids 155-158, ARUTE is 65, KANZEN is 73, and RUKA is empty —
# all four as the switch's own case comments imply.
#
# Two conditions select within a row:
#   * `slope` — `tile[+3] & 0xE0` on the tile under the unit's feet, read via
#     `tile_height_lookup(unit[+0x7C], [+0x7D], [+0x7E])`. This is NOT "is the tile
#     sloped": the byte is a slope-TYPE code, and two of the twelve codes
#     (ConvexSoutheast 0x11, ConvexSouthwest 0x14) have nothing in the top three
#     bits, so they take the FLAT branch. Applying the mask to the same byte is
#     therefore exact and needs no further decode.
#   * `anim` — `unit[+0x1DC] >> 1`, compared against 0x1A / 0x24 / 0x34. ⚠️ THE GAP:
#     these three ids are unnamed in the ROM (AT_MARKER_RENDERING.md §9) and our rig
#     addresses animations by NAME, so nothing in the port can currently answer
#     "is this unit in pose 0x1A". Every `anim_else` row below is reachable; no other
#     row is. Note the consequence: with no special anim the `slope` branch cannot
#     change the answer either — human-scale is -40 raised AND flat — so decoding the
#     anim ids is the single thing that unlocks the rest of this table.
#
# Each row value is `[screen_x_px, world_y_fft_units]` — `unit[+0x2DE]` and
# `unit[+0x2DF]`. X is SCREEN pixels (a post-projection nudge, not a world offset);
# Y is FFT world units, negative because world -Y is up.
AT_MARKER_SLOPE_MASK = 0xE0
AT_MARKER_ANIM_IDS = {"a": 0x1A, "b": 0x24, "c": 0x34}   # unnamed poses — the gap
AT_MARKER_SHP_CASE = {          # jump table @ 0x80067810, index = SHP type byte
    "TYPE1": "human", "TYPE2": "human",          # -> 0x8007ED6C
    "CYOKO": "default", "MON": "default", "RUKA": "default",   # -> 0x8007EE44
    "OTHER": "other",                            # -> 0x8007ED34
    "ARUTE": "arute",                            # -> 0x8007ED24
    "KANZEN": "kanzen",                          # -> 0x8007ED2C
}
AT_MARKER_OFFSET_ROWS = {
    # 0x8007ED94 (raised) / 0x8007EDEC (flat) — the only row the slope test reaches.
    "human": {
        "raised":    {"anim_a": [-5, -35], "anim_b": [0, -30], "anim_c": [-5, -35],
                      "anim_else": [0, -40]},
        "flat":      {"anim_a": [-5, -25], "anim_b": [0, -30], "anim_c": [-5, -25],
                      "anim_else": [0, -40]},
    },
    # 0x8007EE44 — also the fall-through for any SHP key >= 8.
    "default": {"any": {"anim_a": [-5, -30], "anim_c": [-5, -30], "anim_else": [0, -50]}},
    "other":   {"any": {"anim_a": [-5, -25], "anim_c": [-5, -25], "anim_else": [0, -25]}},
    "arute":   {"any": {"anim_else": [0, -70]}},    # no anim test at all
    "kanzen":  {"any": {"anim_else": [0, -120]}},   # no anim test at all
}
AT_MARKER_FALLBACK_CASE = "default"   # SHP key >= 8, or a sprite id with no row


def active_turn_offsets() -> dict:
    """The marker's per-sprite-type screen-X / world-Y offset switch (see above)."""
    return {"slope_mask": AT_MARKER_SLOPE_MASK,
            "anim_ids": dict(AT_MARKER_ANIM_IDS),
            "fallback_case": AT_MARKER_FALLBACK_CASE,
            "shp_case": dict(AT_MARKER_SHP_CASE),
            "rows": {k: {kk: dict(vv) for kk, vv in v.items()}
                     for k, v in AT_MARKER_OFFSET_ROWS.items()}}


def active_turn_set() -> dict:
    """The "AT" active-turn marker's two atlas frames + its CLUT.

    Two 14x12 cells one row apart at the ROM's literal (114,176); `phase_frames`
    and `bob_px` carry the animation the renderer drives them with, so the port
    reads the period from the extraction rather than restating it in GDScript."""
    colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
              for i, w in enumerate(DIGIT_CLUT_BGR555)]
    return {"clut": AT_MARKER_CLUT, "colors": colors,
            "phase_frames": AT_MARKER_PHASE_FRAMES, "bob_px": AT_MARKER_BOB_PX,
            "offsets": active_turn_offsets(),
            "frames": [
                {"x": AT_MARKER_U, "y": AT_MARKER_V,
                 "w": ICON_CELL_W, "h": ICON_CELL_H},
                {"x": AT_MARKER_U, "y": AT_MARKER_V + AT_MARKER_FRAME_DV,
                 "w": ICON_CELL_W, "h": ICON_CELL_H},
            ]}


# --- feedback-HUD word-labels (ROM-authoritative — 2026-06-17 provenance pass) -
# The vitals readout draws "Hp" "Mp" "Ct" "Lv." "Exp." as RANGETILE sprites. The
# draw fn (0x801352BC) lives in a `??` gap of the static export, so these cells
# were recovered by DECODING THE LIVE GPU PRIMITIVES it builds (fork PCSX,
# sstate1) — each cell is the actual textured-quad UV rect into RANGETILE.tga.
# This REPLACES the earlier atlas band-segmentation (which derived the same
# origins to within ~1px — cross-validated — but guessed the sizes). Primitive
# kinds confirmed via the GPU "disable textures for sprites" toggle: Hp/Mp/Ct are
# SPRT (vanish), Lv./Exp. are POLY_FT4 (remain). All share the text CLUT 0x7cbc =
# VRAM(960,498). Provenance: docs/battle-hud-faithful-spec.md "AUTHORITATIVE
# primitives recovered" + "Hp/Mp/Ct labels + bars are SPRT".
LABEL_CLUT = 0x7cbc  # text/label CLUT (VRAM 960,498)
WORD_LABELS = [
    {"name": "Lv.",  "x": 48,  "y": 16, "w": 14, "h": 8,  "prim": "POLY_FT4"},
    {"name": "Exp.", "x": 146, "y": 32, "w": 20, "h": 10, "prim": "POLY_FT4"},
    {"name": "Hp",   "x": 168, "y": 32, "w": 16, "h": 9,  "prim": "SPRT"},
    {"name": "Mp",   "x": 184, "y": 32, "w": 16, "h": 9,  "prim": "SPRT"},
    {"name": "Ct",   "x": 200, "y": 32, "w": 16, "h": 8,  "prim": "SPRT"},
    # Formation sort-tab header extras (#174, FORMATION_SCREEN.md §12.3.1). The
    # roster header samples THIS SAME atlas (VRAM 960,256 = tpage 0x3F/0x5F) — its
    # sort labels are Hp/Mp/Ct/Lv./Exp. (above) plus "Br.Fa". "Br" is the discrete
    # glyph two cells past Ct (216,32); "Fa" is the head of the "Faith" word cell
    # (26,16) — the header abbreviates Brave/Faith as "Br.Fa", so we carry the two
    # parts separately and let the scene compose them.
    {"name": "Br",   "x": 216, "y": 32, "w": 10, "h": 9,  "prim": "SPRT"},
    {"name": "Fa",   "x": 24,  "y": 16, "w": 10, "h": 8,  "prim": "POLY_FT4"},  # x24 (not 25): the F's left stem is at atlas u24 — a w9@u25 cell clipped it
    # FORMATION right unit-info panel (#176, §14.6): the "Brave"/"Faith" stat labels
    # are NOT drawn from FONT.BIN — they are WHOLE-WORD baked textures on THIS sheet
    # (FRAME.BIN / RANGETILE.tga), one row above the "Br"/"Fa" abbreviations. That is
    # why they read smaller than the FONT.BIN name/job. Cells measured off the sheet
    # (index scheme = the digit scheme: bg index 4, ink 1/2/3). h≈6 matches the
    # oracle's rendered label height (~6px), vs FONT.BIN's ~8-10px caps.
    {"name": "Brave", "x": 24, "y": 9,  "w": 23, "h": 7, "prim": "POLY_FT4"},
    {"name": "Faith", "x": 24, "y": 16, "w": 20, "h": 7, "prim": "POLY_FT4"},
]

# Reproducibility fixture — the "Hp" label at its ROM cell (168,32) 16x9 indices.
# Fails loud during extraction if the atlas drifts (wrong atlas / region).
HP_LABEL_FIXTURE = [
    [4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0],
    [4, 2, 1, 2, 4, 2, 1, 2, 4, 4, 4, 4, 0, 0, 0, 0],
    [4, 4, 1, 4, 4, 4, 1, 4, 2, 1, 1, 3, 4, 0, 0, 0],
    [0, 4, 1, 1, 1, 1, 1, 4, 4, 1, 3, 1, 4, 0, 0, 0],
    [0, 4, 1, 4, 4, 4, 1, 4, 4, 1, 4, 1, 4, 0, 0, 0],
    [4, 4, 1, 4, 4, 4, 1, 4, 4, 1, 1, 3, 4, 0, 0, 0],
    [4, 2, 1, 2, 4, 2, 1, 2, 4, 1, 4, 4, 0, 0, 0, 0],
    [4, 4, 4, 4, 4, 4, 4, 4, 2, 1, 2, 4, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 0, 0, 0, 0],
]

# Reproducibility fixtures — the two "AT" active-turn marker frames at (114,176)
# and (114,188), 14x12 indices each (AT_MARKER_RENDERING.md §0/§3.2). These are the
# ONLY cell-identity anchors on the status-icon strip, and they are what makes the
# strip's X mapping falsifiable: the icons sit on a 14px grid, so a cell shifted by
# one column still lands on a neighbouring glyph and still reads "non-blank". The
# two frames differ only in shading (the ROM's 16-frame flip), so a fixture that
# matched both would not be discriminating either — they are carried separately.
AT_MARKER_FIXTURE_A = [
    [0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 4, 4, 4, 1, 1, 5, 5, 4, 4, 4, 4, 1],
    [1, 4, 14, 13, 14, 4, 1, 2, 2, 15, 14, 14, 13, 1],
    [1, 14, 13, 14, 15, 15, 1, 2, 15, 14, 14, 13, 13, 1],
    [1, 13, 14, 1, 15, 2, 1, 1, 1, 14, 13, 1, 1, 1],
    [1, 14, 15, 1, 2, 2, 1, 0, 1, 13, 13, 1, 0, 0],
    [1, 15, 15, 4, 2, 15, 1, 0, 1, 13, 14, 1, 0, 0],
    [1, 15, 2, 2, 15, 14, 1, 0, 1, 14, 15, 1, 0, 0],
    [1, 2, 2, 15, 14, 14, 1, 0, 1, 15, 2, 1, 0, 0],
    [1, 2, 15, 1, 14, 13, 1, 0, 1, 2, 2, 1, 0, 0],
    [1, 15, 14, 1, 13, 13, 1, 0, 1, 2, 15, 1, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0],
]
AT_MARKER_FIXTURE_B = [
    [0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 5, 5, 4, 1, 1, 4, 4, 4, 4, 5, 5, 1],
    [1, 5, 2, 2, 15, 4, 1, 13, 13, 14, 15, 2, 2, 1],
    [1, 2, 2, 15, 14, 14, 1, 13, 14, 15, 2, 2, 15, 1],
    [1, 2, 15, 1, 14, 13, 1, 1, 1, 2, 2, 1, 1, 1],
    [1, 15, 14, 1, 13, 13, 1, 0, 1, 2, 15, 1, 0, 0],
    [1, 14, 14, 4, 13, 14, 1, 0, 1, 15, 15, 1, 0, 0],
    [1, 14, 13, 13, 14, 15, 1, 0, 1, 15, 14, 1, 0, 0],
    [1, 13, 13, 14, 15, 2, 1, 0, 1, 14, 13, 1, 0, 0],
    [1, 13, 14, 1, 2, 2, 1, 0, 1, 13, 14, 1, 0, 0],
    [1, 14, 15, 1, 2, 15, 1, 0, 1, 14, 15, 1, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0],
]

# Reproducibility fixture for the formation-header "Br" cell (216,32) 10x9.
BR_LABEL_FIXTURE = [
    [4, 4, 4, 4, 4, 0, 0, 0, 0, 0],
    [4, 1, 1, 1, 2, 4, 4, 4, 4, 4],
    [4, 4, 1, 4, 1, 4, 1, 2, 1, 2],
    [0, 4, 1, 1, 2, 6, 4, 1, 3, 1],
    [0, 4, 1, 4, 4, 1, 4, 1, 4, 4],
    [4, 4, 1, 4, 3, 1, 4, 1, 4, 0],
    [4, 1, 1, 1, 2, 3, 4, 1, 4, 0],
    [4, 4, 4, 4, 4, 4, 4, 4, 4, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]


def word_label_set() -> dict:
    """The vitals-readout word-labels as ROM-authoritative RANGETILE sprite cells
    (decoded from the live GPU primitives — see section header). Each label
    carries its UV rect, primitive kind (SPRT/POLY_FT4) and the shared CLUT."""
    return {"clut": LABEL_CLUT, "labels": [dict(l) for l in WORD_LABELS]}


# --- dialogue page-turn "more" icon (scenario pagination) ------------------
# The animated page-corner-curl shown at a boxed-dialogue's bottom-right while a
# NEXT PAGE is pending (research/working_documents/scenario_1_captures/
# dialogue_pagination_and_page_icon_decode.md §3). It is a 4-frame loop that
# lives in THIS atlas (RANGETILE == ShiShi's shared FRAME sheet, LBA 0xE68,
# tpage 0x3F) — NOT in EVENT/FRAME.BIN, whose (176,24) neighbourhood is item
# icons. The four cells are a fixed 16px pitch just above the Hp/Mp/Ct labels:
# frame 0 (172,19)-(181,30), frame 1 (188,19)-(197,30), then +16, +16. Each cell
# is 10x12 (an 8x10 page body of outline idx5 + idx8/9/12 dither, with a 1-2px
# idx14/15 drop-shadow on the right & bottom); the bottom-left corner folds up
# progressively across the frames, then resets.
#
# Draw site: the UVs are NOT baked as literal SPRT constants in BATTLE.BIN/SCUS
# rodata (same as the tile cursor + Hp/Mp/Ct labels above — runtime-assembled on
# the per-frame OT path). The animation phase selector is battle DAT_8016dafc,
# written at 0x8012f8c4 from the dialogue frame counter DAT_8016dad4 masked
# `andi t3,v0,0x3` (0x8012f81c) => 4 phases; its READER sits on the OT-build
# path the Ghidra export leaves un-cross-referenced (0x8016dafc is write-only in
# the export), so there is no rodata table to cite — the faithful path is to
# parse the cells out of the ISO atlas by rect, which is what this does.
PAGE_ICON_ORIGIN = (172, 19)   # top-left of frame 0 in RANGETILE.tga texels
PAGE_ICON_CELL_W, PAGE_ICON_CELL_H = 10, 12
PAGE_ICON_PITCH_X = 16
PAGE_ICON_FRAMES = 4
PAGE_ICON_PHASE_MASK = 0x3     # battle 0x8012f81c: andi t3, frame_counter, 0x3

# Reproducibility fixture — frame 0's 10x12 indices (page body + drop-shadow).
# Fails loud during extraction if the atlas drifts (wrong LBA/offset/ISO).
PAGE_ICON_FRAME0_FIXTURE = [
    [5,  5,  5,  5,  5,  5,  5,  5,  0,  0],
    [5, 12, 12, 12, 12, 12, 12,  5, 15,  0],
    [5,  8, 12, 12, 12,  8, 12,  5, 14,  0],
    [5, 12,  8, 12,  8, 12,  8,  5, 14, 15],
    [5,  8, 12,  8, 12,  8, 12,  5, 14, 15],
    [5,  8,  8,  8,  8,  8,  8,  5, 14, 15],
    [5,  8,  9,  8,  9,  8,  9,  5, 14, 15],
    [5,  9,  8,  9,  8,  9,  8,  5, 14, 15],
    [5,  9,  9,  9,  9,  9,  9,  5, 14, 15],
    [5,  5,  5,  5,  5,  5,  5,  5, 14, 15],
    [0, 15, 14, 14, 14, 14, 14, 14, 14, 15],
    [0,  0, 15, 15, 15, 15, 15, 15, 15, 15],
]


def page_turn_icon_set() -> dict:
    """The dialogue page-turn "more" icon: a 4-frame page-corner-curl loop, one
    fixed-pitch RANGETILE cell per phase (see section header). The phase index
    is `frame_counter & PAGE_ICON_PHASE_MASK` in-game; the shader/renderer picks
    the cell. CLUT is runtime-assigned (window sheet), left null like the
    status-icon set."""
    cells = fixed_pitch_cells(PAGE_ICON_ORIGIN[0], PAGE_ICON_ORIGIN[1],
                              PAGE_ICON_CELL_W, PAGE_ICON_CELL_H,
                              PAGE_ICON_PITCH_X, PAGE_ICON_FRAMES)
    return {"clut": None, "frames": PAGE_ICON_FRAMES, "cells": cells,
            "phase_mask": PAGE_ICON_PHASE_MASK,
            "kind": "page_corner_curl_loop"}


# --- feedback-HUD HP/MP/CT bars (ROM-authoritative — 2026-06-17 provenance) ----
# The vitals bars are SPRT textured sprites (confirmed via the GPU "disable
# textures for sprites" toggle — they vanish, unlike the POLY_FT4 numbers). All
# three sample ONE bar-shaped swatch in RANGETILE.tga (a rounded 3-shade body,
# indices 1..3) and are colored by a per-stat CLUT; the drawn SPRT width is the
# value/max fraction of the full swatch (the `cur*32/max` calc in the draw fn).
# The per-stat CLUTs live at VRAM rows 507/508/509 (ids 0x7efc/0x7f3c/0x7f7c).
# They are NOT in BATTLE.BIN's 0x2DAE4 block; dynamic analysis (VRAM->ISO trace)
# located them in the SAME LBA 0xE68 asset as the texels, in the palette tail
# right after the 0x8000-byte texel block (asset payload +0x9160, 3x 32-byte
# CLUTs). So the bar colours are ISO-derived too. Provenance:
# docs/battle-hud-faithful-spec.md "Hp/Mp/Ct labels + bars are SPRT".
BAR_SWATCH = {"x": 216, "y": 202, "w": 38, "h": 6}
BAR_CLUT_OFFSET = 0x9160     # asset payload offset of the first (HP) bar CLUT
BAR_CLUT_STRIDE = 32         # 16 colours * 2 bytes (BGR555)
BAR_STATS = [
    {"name": "HP", "clut": 0x7efc},   # VRAM row 507 — teal / grey-green
    {"name": "MP", "clut": 0x7f3c},   # VRAM row 508 — brown / maroon
    {"name": "CT", "clut": 0x7f7c},   # VRAM row 509 — olive
]
BAR_FILL = "value/max"   # drawn SPRT width = round(value / max * swatch.w)

# Reproducibility fixture — top-left 6x6 of the swatch (the rounded end, idx 2/3
# body over an idx-1 base). Fails loud if the atlas drifts.
BAR_SWATCH_FIXTURE = [
    [0, 0, 0, 2, 2, 2],
    [0, 0, 2, 3, 3, 3],
    [0, 2, 3, 3, 3, 3],
    [2, 3, 3, 3, 3, 3],
    [2, 2, 2, 2, 2, 2],
    [0, 0, 1, 1, 1, 1],
]
# Reproducibility fixture — the HP bar CLUT bytes at BAR_CLUT_OFFSET in the asset
# (idx0 transparent, idx1..5 the body shades, idx6..15 the magenta unused tail).
BAR_HP_CLUT_HEX = ("0000 6408 a410 c518 0000 ef31 1f7c 1f7c "
                   "1f7c 1f7c 1f7c 1f7c 1f7c 1f7c 1f7c 1f7c").replace(" ", "")


def bar_set(asset: bytes) -> dict:
    """The HP/MP/CT vitals bars: one shared RANGETILE swatch + a per-stat CLUT
    (read from the LBA 0xE68 asset palette tail), drawn value/max-width SPRT.
    Each stat carries its VRAM CLUT id and the decoded 16-colour RGBA palette."""
    stats = []
    for n, s in enumerate(BAR_STATS):
        off = BAR_CLUT_OFFSET + n * BAR_CLUT_STRIDE
        colors = [bgr555_to_rgba(asset[off + i * 2], asset[off + i * 2 + 1],
                                 index_is_zero=(i == 0)) for i in range(16)]
        stats.append({"name": s["name"], "clut": s["clut"], "colors": colors})
    return {"swatch": dict(BAR_SWATCH), "fill": BAR_FILL, "stats": stats}


# --- formation sort-tab HEADER (#174 v2, FORMATION_SCREEN.md §12.3.2) ---------
# The roster header (tan sort-bar + six labels + ◄L2/R2► buttons) was RE-DERIVED
# from the VRAM oracle (2026-07-18 v2): loaded the roster live, dumped VRAM, read
# the TOP display framebuffer, and hooked `menu_sprite_setter @0x8012c8bc` to log
# every built POLY_FT4 descriptor. Findings (all cross-verified byte-exact vs the
# ISO here — the emulator was only the discovery oracle):
#   * Labels + buttons all sample THIS atlas page (VRAM 960,256 == RANGETILE),
#     tpage 0x1F (4bpp, abr=0 NORMAL/opaque — NOT the 0x5F subtractive shadows use).
#   * The four header CLUTs live in the LBA 0xE68 asset's palette TAIL, mapped
#     `asset + 0x9000 + (vram_clut_row - 496)*32` (same asset as texels + bars):
#       inactive_label 0x7c3c=+0x9000  active_label 0x7cbc=+0x9040
#       button 0x7d7c=+0x90a0          button_pressed 0x7e7c=+0x9120
#     inactive_label[1]=(48,40,32) dark ink, [4]=(152,144,120) = the bar's own tan
#     (so a glyph's fill blends into the bar, strokes read dark — a real 2-tone
#     emboss, NOT the flat single-ink the first pass faked). active_label[1]=white,
#     [4]=(32,24,16) → the highlighted "Hp" (white strokes on dark fill).
#   * The six sort-label cells ARE the WORD_LABELS above: Hp/Mp/Ct/Lv./Exp. + Br/Fa.
#   * Each button is a 3-slice window frame (left-cap/body/right-cap) + a caption,
#     all textured atlas cells (the captions "◄L2"/"R2►" ARE baked in the atlas at
#     V88-93 — reconstructed pixel-perfect). Pressed state swaps CLUT 0x7d7c->0x7e7c.
HEADER_CLUTS = [
    {"name": "inactive_label", "clut": 0x7c3c, "off": 0x9000},
    {"name": "active_label",   "clut": 0x7cbc, "off": 0x9040},
    {"name": "button",         "clut": 0x7d7c, "off": 0x90a0},
    {"name": "button_pressed", "clut": 0x7e7c, "off": 0x9120},
]
# Byte-exact CLUT fixtures (BGR555 LE) — fail loud if the asset/offset ever drifts.
HEADER_CLUT_HEX = {
    "inactive_label": "0000a6104a21f035533e6c25ae2d113a7442ad082f1df13595466408ae293a57",
    "active_label":   "0000bd73734a4a2564084b25ef39113a7442533eae2df13595466408a5944288",
    "button":         "0000a510bd772829ac392f4ef662ee18d21016157c15ec0c7411f7197a223c3b",
    "button_pressed": "00000815ff77103ab5423947de5b2280448066848888ec0c7411f7197a223c3b",
}
# The equip stat-DELTA colour palette (EQUIP_STAT_PREVIEW.md §5): VRAM CLUT 0x7FFC = asset
# palette tail +0x91E0 = FRAME.BIN palette 15 (byte-identical VRAM↔FRAME.BIN, dumped + traced).
# The compare panel colours a signed delta by an index-BIAS into this ONE palette (software
# blitter FUN_800FEFF0): positive +0xC selects the blue sub-ramp ([13] primary), negative +0x8
# the red sub-ramp ([9]); [1]=tan is the plain/base ink. Same asset + mechanism as the header
# CLUTs above — just one more offset. Fail loud if the asset/offset ever drifts.
DELTA_PALETTE_CLUT = 0x7ffc
DELTA_PALETTE_OFF = 0x91e0
DELTA_PALETTE_HEX = "0000a6104a21f035533e6c25ae2d113a7442ad082f1df13595464241a83d0f3e"
# The six sort labels, in header order — PRINCIPLED placement recovered from the
# live header prims (settled roster `ram_settled.bin`, the output of the ROM's
# label_glyph_emitter @0x80115d6c; §12.3.3). Each label carries its OWN atlas cell
# `[u, v, w, h]` + screen-left `x` (all at screen y = HEADER_LABEL_Y). The header
# cells DIFFER from the vitals `WORD_LABELS` and must NOT be borrowed by name:
#   * "Exp." here draws the NARROW (145,32,16) cell — "Exp" with NO trailing period
#     (WORD_LABELS' "Exp." is the wider 20px cell that INCLUDES a period).
#   * "Fa" is the (144,120,12) cell, NOT WORD_LABELS' (25,16).
#   * The Brave/Faith tab is "Br" + a real 3x3 PERIOD GLYPH at (59,21) + "Fa": the
#     period is a textured atlas cell through the label CLUT (dark ink on the tan
#     field), NOT a hand-placed solid quad. Its own x/y (`dot`) come from the prim.
HEADER_LABEL_Y = 18
HEADER_SORT_LABELS = [
    {"name": "Hp",  "x": 69,  "cell": [168, 32, 13, 9]},
    {"name": "Mp",  "x": 88,  "cell": [184, 32, 13, 9]},
    {"name": "Ct",  "x": 107, "cell": [200, 32, 14, 8]},
    {"name": "Lv.", "x": 127, "cell": [49, 16, 13, 8]},   # keeps its trailing period
    {"name": "Exp.", "x": 140, "cell": [145, 32, 17, 9]},  # cell = "Exp", NO period; w17 clears the "p" bowl (u146..161), h9 clears the "p" descender (row v40); abuts Lv. → "Lv.Exp"
    {"name": "Br",  "x": 162, "cell": [216, 32, 11, 8],
     "x2_name": "Fa", "x2": 174, "x2_cell": [144, 120, 12, 8],
     "dot": {"x": 171, "y": 23, "cell": [59, 21, 3, 3]}},  # real "Br.Fa" period glyph
]
# The two L2/R2 buttons, EXACTLY as captured from `menu_sprite_setter` descriptors.
# Each piece = [dx, dy, u, v, w, h] relative to the button origin; screen origin
# (origin_x, y). tpage 0x1F (abr=0), CLUT "button" (pressed -> "button_pressed",
# whole button shifts y+1). frame body/caps are shared; captions differ.
HEADER_BUTTONS = {
    "tpage": 0x1F,
    "left": {"origin_x": 38, "y": 15, "pieces": [
        [0, 0, 176, 128, 4, 14], [4, 0, 184, 128, 16, 14], [20, 0, 180, 128, 4, 14],
        [4, 5, 218, 93, 16, 5], [17, 5, 233, 88, 4, 5]]},
    "right": {"origin_x": 194, "y": 15, "pieces": [
        [0, 0, 176, 128, 4, 14], [4, 0, 184, 128, 16, 14], [20, 0, 180, 128, 4, 14],
        [4, 5, 218, 88, 8, 5], [11, 5, 233, 88, 4, 5], [15, 5, 227, 88, 6, 5]]},
}
# The active-tab highlight box + tan-window geometry (framebuffer-measured, y at
# screen row). The window is drawn opaque; label ink is opaque over it.
HEADER_TAN_RECT = {"x": 60, "y": 14, "w": 132, "h": 16}   # tan bar bounds
HEADER_BOX = {"dx": -2, "y": 16, "w": 20, "h": 11}        # dark highlight box (rel active label x)
HEADER_COLORS = {                                          # framebuffer sRGB
    "tan_fill": [152, 144, 120], "tan_bevel": [208, 200, 168],
    "tan_edge": [48, 40, 32], "box_bg": [40, 40, 32],
}


def header_clut_colors(asset: bytes, off: int) -> list:
    """One 16-entry header CLUT (RGBA) from the asset palette tail at `off`."""
    return [list(bgr555_to_rgba(asset[off + i * 2], asset[off + i * 2 + 1],
                                index_is_zero=(i == 0))) for i in range(16)]


def sort_header_set(asset: bytes) -> dict:
    """The formation sort-tab header: the four ROM CLUTs, the six sort labels
    (each with its OWN atlas cell + live-prim x, §12.3.3), the two textured L2/R2
    buttons, and the framebuffer-measured window geometry. ROM-authoritative."""
    cluts = {}
    for c in HEADER_CLUTS:
        cluts[c["name"]] = {"clut": c["clut"], "colors": header_clut_colors(asset, c["off"])}
    return {"page": "rangetile", "tpage": HEADER_BUTTONS["tpage"],
            "cluts": cluts, "labels": [dict(l) for l in HEADER_SORT_LABELS],
            "buttons": HEADER_BUTTONS, "tan_rect": HEADER_TAN_RECT,
            "box": HEADER_BOX, "colors": HEADER_COLORS}


# --- Status/detail-screen unit-pager buttons ◄L1 / R1► (FORMATION_SCREEN.md §15.22) ---
# The Status (unit-detail) screen replaces the formation sort-header with its own two
# corner buttons: ◄L1 (top-left) and R1► (top-right), the previous/next-unit pager.
# Live-captured from sstate6's OT (§15.22): SAME RANGETILE page + button CLUT (0x7D7C,
# §15.21 bg twin 0x7DFC) as the L2/R2 buttons, SAME 3-slice frame cells (176/184/180 @
# v=128) — only the screen origins (hard into the corners after the draw-env +0x80 X
# bias) and the single-cell captions differ. The 1-vs-2 digit is a compositing
# difference in the ROM (formation L2 = this L1 base cell + an overlay piece), so each
# detail caption is ONE cell: ◄L1 = (218,93,16x5), R1► = (218,88,15x5).
DETAIL_PAGER_BUTTONS = {
    "tpage": 0x1F,
    "clut": 0x7D7C,        # foreground button CLUT (== HEADER "button")
    "clut_bg": 0x7DFC,     # §15.21 backgrounded twin (blue) — blues on start-menu open
    "left": {"origin_x": 12, "y": 14, "pieces": [
        [0, 0, 176, 128, 4, 14], [4, 0, 184, 128, 16, 14], [20, 0, 180, 128, 4, 14],
        [4, 5, 218, 93, 16, 5]]},                            # caption ◄L1
    "right": {"origin_x": 224, "y": 14, "pieces": [
        [0, 0, 176, 128, 4, 14], [4, 0, 184, 128, 16, 14], [20, 0, 180, 128, 4, 14],
        [5, 5, 218, 88, 15, 5]]},                            # caption R1►
}


def detail_pager_set() -> dict:
    """The Status/detail-screen ◄L1 / R1► unit-pager buttons (§15.22): the RANGETILE
    page, the foreground + backgrounded button CLUTs, and the two textured buttons
    (3-slice frame + single-cell caption each) at the Status corners. ROM-authoritative
    (live OT capture). The atlas cells + CLUT colours are the header's — reused here."""
    return {"page": "rangetile", "tpage": DETAIL_PAGER_BUTTONS["tpage"],
            "clut": DETAIL_PAGER_BUTTONS["clut"], "clut_bg": DETAIL_PAGER_BUTTONS["clut_bg"],
            "left": dict(DETAIL_PAGER_BUTTONS["left"]),
            "right": dict(DETAIL_PAGER_BUTTONS["right"])}


# --- detail/Status-screen ability-window icons (FORMATION_SCREEN.md §15.15) ---
# The unit-detail (Status) screen's Ability window shows FIVE fixed row icons —
# NOT per-ability art: the icon per row is a baked descriptor constant (only the
# ability NAME text varies per unit; there is no skillset->icon table). All five
# are RANGETILE(960,256) sprites in the (136,0)-(168,32) block, drawn through the
# shared menu icon CLUT 0x7D7C (== DIGIT_CLUT / the header "button" palette).
# Traced statically from the detail builder FUN_800eaf3c's 19-element descriptor
# array (records 7-11 @0x80155f88) and live-confirmed byte-exact against the
# sstate4 OT. Rows 0/1 share the same (136,0) blade cell (the ROM authored two
# rows on one cell); rows 2/3/4 are fist / diamond / boot.
ABILITY_ICON_CLUT = DIGIT_CLUT   # 0x7d7c — shared menu icon/number CLUT
ABILITY_ICON_CELLS = [
    {"name": "blade0",  "x": 136, "y": 0,  "w": 12, "h": 16},  # rec7 (row 0)
    {"name": "blade1",  "x": 136, "y": 0,  "w": 12, "h": 16},  # rec8 (row 1, same cell)
    {"name": "fist",    "x": 148, "y": 0,  "w": 12, "h": 16},  # rec9 (row 2)
    {"name": "diamond", "x": 136, "y": 16, "w": 16, "h": 16},  # rec10 (row 3)
    {"name": "boot",    "x": 152, "y": 16, "w": 16, "h": 16},  # rec11 (row 4)
]

# Reproducibility fixture — the blade cell (136,0) 12x16 indices (the row-0/1
# Ability glyph). Fails loud during extraction if the atlas drifts.
ABILITY_BLADE_FIXTURE = [
    [0, 0, 0, 0, 11, 11, 11, 11, 11, 0, 0, 0],
    [0, 0, 0, 11, 13, 2, 2, 15, 11, 0, 0, 0],
    [0, 0, 0, 11, 15, 2, 15, 11, 0, 0, 0, 0],
    [0, 0, 11, 13, 2, 15, 11, 0, 0, 0, 0, 0],
    [0, 0, 11, 15, 15, 11, 0, 0, 0, 0, 0, 0],
    [0, 11, 13, 2, 11, 11, 11, 11, 11, 0, 0, 0],
    [0, 11, 15, 2, 2, 2, 2, 15, 11, 0, 0, 0],
    [0, 11, 11, 11, 11, 13, 2, 11, 0, 0, 0, 0],
    [0, 0, 11, 11, 13, 15, 11, 0, 0, 0, 0, 0],
    [0, 11, 15, 12, 15, 11, 0, 0, 0, 0, 0, 0],
    [0, 11, 2, 14, 11, 0, 0, 0, 0, 0, 0, 0],
    [11, 13, 2, 2, 15, 11, 0, 0, 0, 0, 0, 0],
    [11, 15, 13, 12, 11, 11, 0, 0, 0, 0, 0, 0],
    [11, 11, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]


def ability_icon_set() -> dict:
    """The five FIXED Ability-window row icons (§15.15), one RANGETILE cell each,
    drawn through the shared menu icon CLUT 0x7D7C. `colors` is that CLUT's 16
    RGBA entries (idx0 transparent), same as the digit set — the row icon is a
    baked per-slot constant, so no per-unit selection is needed."""
    colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
              for i, w in enumerate(DIGIT_CLUT_BGR555)]
    return {"clut": ABILITY_ICON_CLUT, "colors": colors,
            "cells": [dict(c) for c in ABILITY_ICON_CELLS]}


# --- detail/Status-screen Eqp slot-category icons (§15.16) -------------------
# The Eqp window's five slot-category markers (R.Hand / L.Hand / Head / Body /
# Accessory) that sit LEFT of the per-item ITEM.BIN icons. Like the ability
# icons they are RANGETILE(960,256) sprites drawn by the same detail builder from
# the same 19-element descriptor array — but each is a TWO-LAYER emboss: a dark
# backing (v=128 block, CLUT 0x7C3C = inactive_label palette) under a lit icon
# (v=140 block, CLUT 0x7D7C). Both overlaid at the same screen cell. There is a
# runtime 2H-collapse variant (rows R/L.Hand replaced by one (48,144,16,16)
# combined-slot icon, L.Hand hidden) for two-handed weapons.
SLOT_ICON_LIT_CLUT = ABILITY_ICON_CLUT   # 0x7d7c
SLOT_ICON_DARK_CLUT = 0x7c3c             # inactive_label palette (asset +0x9000)
SLOT_ICON_DARK_OFF = 0x9000              # asset-tail offset of CLUT 0x7C3C
SLOT_ICONS = [
    {"name": "r_hand",    "lit": [0, 140, 8, 12],  "dark": [0, 128, 8, 12]},
    {"name": "l_hand",    "lit": [8, 140, 8, 12],  "dark": [8, 128, 8, 12]},
    {"name": "head",      "lit": [16, 140, 8, 12], "dark": [16, 128, 12, 12]},
    {"name": "body",      "lit": [36, 140, 12, 10], "dark": [36, 128, 12, 12]},
    {"name": "accessory", "lit": [24, 140, 12, 10], "dark": [26, 128, 12, 12]},
]
SLOT_ICON_2H = {"lit": [48, 144, 16, 16]}   # two-handed collapse variant

# Reproducibility fixture — the R.Hand lit cell (0,140) 8x12 (a gauntleted hand).
SLOT_RHAND_LIT_FIXTURE = [
    [0, 0, 1, 1, 1, 0, 0, 0],
    [0, 1, 6, 6, 5, 1, 0, 0],
    [0, 1, 3, 5, 2, 5, 1, 0],
    [1, 6, 1, 5, 2, 6, 1, 0],
    [1, 5, 6, 2, 6, 6, 1, 0],
    [0, 1, 5, 6, 6, 4, 1, 0],
    [0, 0, 1, 5, 5, 1, 0, 0],
    [0, 1, 5, 6, 6, 5, 1, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
]


def _cell_dict(rect: list) -> dict:
    return {"x": rect[0], "y": rect[1], "w": rect[2], "h": rect[3]}


def slot_icon_set(asset: bytes) -> dict:
    """The five Eqp slot-category icons (§15.16), each a two-layer emboss (dark
    backing CLUT 0x7C3C under a lit icon CLUT 0x7D7C), plus the two-handed collapse
    variant. Carries both 16-RGBA CLUTs (lit reused from the number CLUT, dark read
    from the asset palette tail at +0x9000) so the scene can bind them directly."""
    lit_colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
                  for i, w in enumerate(DIGIT_CLUT_BGR555)]
    dark_colors = header_clut_colors(asset, SLOT_ICON_DARK_OFF)
    slots = [{"name": s["name"], "lit": _cell_dict(s["lit"]), "dark": _cell_dict(s["dark"])}
             for s in SLOT_ICONS]
    return {"lit_clut": SLOT_ICON_LIT_CLUT, "dark_clut": SLOT_ICON_DARK_CLUT,
            "lit_colors": lit_colors, "dark_colors": dark_colors,
            "slots": slots, "two_handed": {"lit": _cell_dict(SLOT_ICON_2H["lit"])}}


# --- detail/Status-screen weapon-type legend icons (§15.18 handoff) -----------
# The Weap.Power band's two decorative weapon-type markers — a silver dagger over
# a red-tipped rod — that sit LEFT of the R/L "weapon-AT" rows. NOT ITEM.BIN (this
# CORRECTS the §15.13 manifest row 16 + the DetailScene "ITEM.BIN weapon ICONS"
# TODO, both of which guessed ITEM.BIN): it is ONE fixed decorative pair (physical-
# weapon / magic-weapon legend), the SAME two-layer RANGETILE emboss mechanism as the
# Eqp slot icons (§15.16) — it does NOT vary with the unit's equipped weapons.
#   lit  : RANGETILE (64,0) 12x24, CLUT 0x7D7C — the colourful menu icon palette
#          (idx2-6 silver/blue blade, idx7-10 red/orange, idx11-15 gold/wood) so the
#          cell renders as the oracle's silver dagger (top) over a red-tipped rod (bottom).
#   dark : RANGETILE (80,0) 12x24, CLUT 0x7C3C — the dark-ink backing (== slot dark /
#          stat-label palette, asset tail +0x9000), drawn UNDER the lit layer.
# Static root: records 10 & 17 of the band builder's descriptor table 0x80155D88
# (rec10 {u=64,v=0,w=12,h=24}, rec17 {u=80,v=0,w=12,h=24}, both x=118,y=15 → same
# cell, two layers). Dynamic confirm: the sstate4 OT carries exactly SPRTt uv=(64,0)
# 12x24 clut=0x7D7C + SPRTt uv=(80,0) 12x24 clut=0x7C3C at xy0=(258,103), and NO
# ITEM.BIN prim exists in the band. display = (258,103) − 0x80 X-bias = (130,103).
WEAPON_ICON_LIT_CLUT = DIGIT_CLUT          # 0x7d7c — colourful menu icon palette
WEAPON_ICON_DARK_CLUT = SLOT_ICON_DARK_CLUT  # 0x7c3c — dark-ink backing
WEAPON_ICON_DARK_OFF = SLOT_ICON_DARK_OFF    # asset tail +0x9000 (CLUT 0x7C3C bytes)
WEAPON_ICON_LIT = {"x": 64, "y": 0, "w": 12, "h": 24}
WEAPON_ICON_DARK = {"x": 80, "y": 0, "w": 12, "h": 24}

# Reproducibility fixtures — the lit dagger/rod cell (64,0) and its dark backing
# (80,0), both 12x24. Fail loud during extraction if the atlas drifts.
WEAPON_ICON_LIT_FIXTURE = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0],
    [0, 1, 5, 2, 6, 1, 0, 0, 0, 0, 0, 0],
    [0, 0, 1, 6, 2, 5, 1, 0, 0, 0, 0, 0],
    [0, 0, 0, 1, 5, 5, 5, 1, 0, 0, 0, 0],
    [0, 0, 0, 0, 1, 4, 6, 6, 1, 1, 0, 0],
    [0, 0, 0, 0, 0, 1, 3, 3, 14, 13, 1, 0],
    [0, 0, 0, 0, 0, 1, 13, 14, 11, 11, 1, 0],
    [0, 0, 0, 0, 0, 1, 13, 1, 12, 13, 11, 1],
    [0, 0, 0, 0, 0, 0, 1, 0, 1, 12, 14, 1],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0],
    [0, 0, 7, 7, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 7, 14, 10, 7, 0, 0, 0, 0, 0, 0, 0],
    [0, 7, 10, 10, 7, 12, 1, 0, 0, 0, 0, 0],
    [0, 0, 7, 7, 11, 14, 1, 0, 0, 0, 0, 0],
    [0, 0, 1, 12, 14, 12, 11, 1, 0, 0, 0, 0],
    [0, 0, 0, 1, 1, 11, 13, 11, 1, 0, 0, 0],
    [0, 0, 0, 0, 0, 1, 1, 13, 12, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 1, 14, 13, 1, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 1, 14, 1, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]
WEAPON_ICON_DARK_FIXTURE = [
    [0, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [4, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0],
    [4, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0],
    [4, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0],
    [4, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0],
    [0, 6, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0],
    [0, 0, 6, 0, 0, 0, 0, 0, 4, 0, 0, 0],
    [0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 4, 0],
    [0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 4, 0, 6, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 4, 4, 6, 0, 0, 6],
    [0, 4, 0, 0, 4, 0, 0, 0, 4, 6, 6, 4],
    [0, 0, 0, 0, 0, 6, 0, 0, 0, 4, 4, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 4, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0],
    [0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 4, 6, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 4, 6, 0, 0, 0, 0, 4],
    [0, 0, 0, 0, 0, 0, 4, 6, 0, 0, 0, 6],
    [0, 0, 0, 0, 0, 0, 0, 4, 6, 0, 6, 4],
    [0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 0],
]


def weapon_icon_set(asset: bytes) -> dict:
    """The Weap.Power band's two-layer weapon-type legend icon (§15.18): a dark
    backing (CLUT 0x7C3C) under a lit dagger/rod (colourful CLUT 0x7D7C), one fixed
    decorative pair (NOT ITEM.BIN, does not vary per unit). Carries both cells + both
    16-RGBA CLUTs (lit reused from the number CLUT, dark read from the asset tail
    +0x9000) so the scene can bind them directly, like `slot_icon_set`."""
    lit_colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
                  for i, w in enumerate(DIGIT_CLUT_BGR555)]
    dark_colors = header_clut_colors(asset, WEAPON_ICON_DARK_OFF)
    return {"lit_clut": WEAPON_ICON_LIT_CLUT, "dark_clut": WEAPON_ICON_DARK_CLUT,
            "lit_colors": lit_colors, "dark_colors": dark_colors,
            "lit": dict(WEAPON_ICON_LIT), "dark": dict(WEAPON_ICON_DARK)}


# --- equip-picker per-TYPE class glyphs (§15.28 round 47) ---------------------
# The item-picker's left column (§15.26 a) is NOT one fixed sword: WORLD.BIN holds
# a type→(U,V) LUT the glyph provider chain reads per row —
#   world_equip_row_renderer 0x80128CE0 → opcode-6 cell (template 0x8018C9A0+,
#   provider slot 2) → provider FUN_8011AA34 → FUN_80124FD0 (item class byte =
#   itemRecord[1], records 12B at 0x80062EBC) → FUN_80124FF4:
#     U = byte[0x8018D7FC + type*2], V = byte[0x8018D7FD + type*2], W = H = 0xC
#   (the 12×12 size is the WORLD literal 0xc at 0x80125018).
# The LUT is static WORLD.BIN data: RAM 0x8018D7FC − base 0x800E0000 = file 0xAD7FC.
# Page V maps 1:1 onto tga rows here (verified by rendering the picker VRAM dump
# cell (104,128) vs this tga — the "tga y = v − 32" guess put the cells on
# coincidental ink at y=96; the true sword/knife art sits at tga y=128).
# CLUT: the provider overwrites descriptor+8 with DAT_801CD1BC, which the palette
# swapper FUN_801298C0 loads from the WORLD constant bank — idle 0x7C3C
# (@0x8018DF8C == asset tail +0x9000, the inactive_label palette already parsed
# here), highlight 0x7D3C (@0x8018DF8E, +0x9080). The picker renders every row
# idle (live prim scan: all rows 0x7C3C; row emphasis is the glove cursor).
# Live-proven: Broad Sword (type 3) → page (104,128); Mythril Knife/Dagger
# (type 1) → (80,128); prims 12×12 at screen x=80.
TYPE_GLYPH_LUT_WORLD_OFF = 0xAD7FC   # RAM 0x8018D7FC (WORLD.BIN base 0x800E0000)
TYPE_GLYPH_TYPES = 35                # types 0..34; (0,0) entries have no glyph
TYPE_GLYPH_SIZE = 12                 # WORLD literal 0xc (FUN_80124FF4 @0x80125018)
TYPE_GLYPH_V_TGA_OFF = 0             # page v == tga y (verified vs the VRAM dump)
TYPE_GLYPH_CLUT = SLOT_ICON_DARK_CLUT      # 0x7c3c idle bank (FUN_801298C0)
TYPE_GLYPH_CLUT_OFF = SLOT_ICON_DARK_OFF   # asset tail +0x9000


def type_glyph_set(world: bytes, asset: bytes) -> dict:
    """Per-item-type equip-picker class-glyph cells (§15.28): the WORLD.BIN
    type→UV LUT at 0x8018D7FC (page v == tga y), through the idle dark menu
    CLUT 0x7C3C (asset tail +0x9000). Keyed by the item class byte
    (itemRecord[1]: 1=Knife, 3=Sword, …)."""
    cells = {}
    for t in range(TYPE_GLYPH_TYPES):
        u = world[TYPE_GLYPH_LUT_WORLD_OFF + t * 2]
        v = world[TYPE_GLYPH_LUT_WORLD_OFF + t * 2 + 1]
        if u == 0 and v == 0:
            continue  # type 0 / unused: no glyph
        cells[str(t)] = {"x": u, "y": v - TYPE_GLYPH_V_TGA_OFF,
                         "w": TYPE_GLYPH_SIZE, "h": TYPE_GLYPH_SIZE}
    # Reproducibility fixtures — the live-prim-proven picker rows (§15.28), at
    # the VRAM-dump-verified tga rows (v 1:1).
    if cells.get("3") != {"x": 104, "y": 128, "w": 12, "h": 12}:
        raise SystemExit(f"type_glyph LUT drift: Sword(3) = {cells.get('3')}")
    if cells.get("1") != {"x": 80, "y": 128, "w": 12, "h": 12}:
        raise SystemExit(f"type_glyph LUT drift: Knife(1) = {cells.get('1')}")
    return {"clut": TYPE_GLYPH_CLUT,
            "colors": header_clut_colors(asset, TYPE_GLYPH_CLUT_OFF),
            "cells": cells,
            "source": {"world_bin_offset": TYPE_GLYPH_LUT_WORLD_OFF,
                       "ram": 0x8018D7FC, "clut_asset_offset": TYPE_GLYPH_CLUT_OFF}}


# --- Formation START sub-menu glove cursor (FORMATION_SCREEN.md §15.20) --------
# The START action-menu's bobbing "glove" (hand) cursor — the FIRST glove consumer
# (gh #73). It is a TWO-LAYER 16×16 emboss on THIS RANGETILE sheet (VRAM(960,256)),
# the two cells the shared menu-window builder (world_menu_window_builder FUN_800ec108)
# installs as elem+0x38 (u=168, lit) and elem+0x4c (u=184, shadow):
#   lit    : RANGETILE (168,0) 16x16, CLUT 0x7D7C — the white FFT swirl/glove.
#   shadow : RANGETILE (184,0) 16x16, CLUT 0x7DBC — drawn UNDER the lit, offset +2/+2.
# (CLUTs from world_menu_cursor_set_clut FUN_800ec484: the normal-state pair is
# 0x7d7c lit / 0x7dbc shadow.) The lit CLUT reuses the number CLUT (0x7D7C == DIGIT_CLUT
# == the header "button" palette); the shadow CLUT 0x7DBC lives in the same LBA 0xE68
# asset palette tail as the other menu CLUTs, at +0x90C0 (= 0x9000 + (502−496)*32; VRAM
# CLUT row 0x7dbc>>6 = 502).
MENU_GLOVE_LIT_CLUT = DIGIT_CLUT          # 0x7d7c — shared menu icon/number palette
MENU_GLOVE_SHADOW_CLUT = 0x7dbc           # shadow palette
MENU_GLOVE_SHADOW_OFF = 0x90c0            # asset tail offset of CLUT 0x7DBC
MENU_GLOVE_LIT = {"x": 168, "y": 0, "w": 16, "h": 16}
MENU_GLOVE_SHADOW = {"x": 184, "y": 0, "w": 16, "h": 16}


def menu_glove_cursor_set(asset: bytes) -> dict:
    """The Formation START sub-menu glove cursor (§15.20): a two-layer 16×16 emboss —
    a lit swirl (CLUT 0x7D7C) over a shadow (CLUT 0x7DBC, offset +2/+2). Carries both
    cells + both 16-RGBA CLUTs (lit reused from the number CLUT, shadow read from the
    asset tail +0x90C0) so the menu scene can bind them directly, like the slot icons."""
    lit_colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
                  for i, w in enumerate(DIGIT_CLUT_BGR555)]
    shadow_colors = header_clut_colors(asset, MENU_GLOVE_SHADOW_OFF)
    return {"lit_clut": MENU_GLOVE_LIT_CLUT, "shadow_clut": MENU_GLOVE_SHADOW_CLUT,
            "lit_colors": lit_colors, "shadow_colors": shadow_colors,
            "lit": dict(MENU_GLOVE_LIT), "shadow": dict(MENU_GLOVE_SHADOW)}


# --- detail/Status-screen stats-band LABELS (FORMATION_SCREEN.md §15.14 rows 14) ----
# The stats-band text LABELS — Move / Jump / Speed / Weap.Power / AT / C-EV / S-EV /
# A-EV and the R / L hand-row markers — are NOT FONT.BIN glyphs. They are baked
# whole-word/token sprite cells on THIS RANGETILE sheet (VRAM(960,256)), drawn by the
# detail builder (world_detail_screen_builder FUN_800eaf3c, §15.15) as SPRTt through
# the dark-ink-on-tan menu label CLUT 0x7C3C (== the slot-icon dark / header
# "inactive_label" palette, asset tail +0x9000). The evade prefixes bake their own
# dash: "C-"/"S-"/"A-" are single cells (dash inside), and a SHARED "EV" cell draws
# after each, so "C-EV" == cell "C-" + cell "EV" (there is no FONT.BIN '-' here).
#
# Sourced from the live OT at the settled Status screen (sstate4): each label is a
# SPRTt whose (u,v,w,h) is the cell below, screen X = rectB.x(140) + descr − 0x80
# menu bias. The UVs were then cross-verified byte-exact against this ISO atlas (the
# fixtures below) — same triangulation (static builder + live OT + ISO bytes) the
# §15.15/§15.16 icon cells used. "Speed" lives apart from the y24 header row, in the
# menu-word block at (176,144) (next to "Guest"/"Enemy"); the rest cluster at v0/v8/v24.
STAT_LABEL_CLUT = SLOT_ICON_DARK_CLUT   # 0x7c3c — dark-ink-on-tan menu label palette
STAT_LABEL_DARK_OFF = SLOT_ICON_DARK_OFF  # asset tail +0x9000 (CLUT 0x7C3C bytes)
STAT_LABELS = [
    {"name": "Move",       "x": 0,   "y": 0,   "w": 24, "h": 8},
    {"name": "Jump",       "x": 0,   "y": 8,   "w": 24, "h": 8},
    {"name": "Speed",      "x": 176, "y": 144, "w": 26, "h": 10},
    {"name": "Weap.Power", "x": 0,   "y": 24,  "w": 48, "h": 8},
    {"name": "AT",         "x": 48,  "y": 24,  "w": 14, "h": 8},
    {"name": "C-",         "x": 64,  "y": 24,  "w": 12, "h": 8},
    {"name": "S-",         "x": 76,  "y": 24,  "w": 12, "h": 8},
    {"name": "A-",         "x": 88,  "y": 24,  "w": 12, "h": 8},
    {"name": "EV",         "x": 100, "y": 24,  "w": 16, "h": 8},
    {"name": "R",          "x": 120, "y": 24,  "w": 8,  "h": 8},
    {"name": "L",          "x": 128, "y": 24,  "w": 8,  "h": 8},
]

# Reproducibility fixtures — fail loud during extraction if the atlas drifts. "Move"
# (the header-row left label), "C-" (proves the baked dash — the whole point: the '-'
# is INSIDE the cell, not a FONT glyph), and "Speed" (the off-row menu-word cell).
MOVE_LABEL_FIXTURE = [
    [2, 1, 3, 4, 3, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [3, 1, 1, 3, 1, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [4, 1, 2, 2, 2, 1, 4, 3, 1, 1, 3, 1, 1, 4, 1, 1, 3, 1, 1, 3, 0, 0, 0, 0],
    [4, 1, 3, 1, 3, 1, 4, 1, 4, 4, 1, 3, 1, 3, 1, 3, 1, 4, 2, 1, 0, 0, 0, 4],
    [4, 1, 4, 6, 4, 1, 4, 1, 4, 4, 1, 4, 2, 2, 2, 4, 1, 2, 3, 4, 0, 0, 0, 4],
    [2, 1, 2, 4, 2, 1, 2, 3, 1, 1, 3, 0, 4, 1, 4, 4, 3, 1, 1, 3, 0, 0, 0, 4],
    [4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 0, 0, 0, 4, 0, 0, 0, 4, 4, 0, 0, 0, 0, 4],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]
CDASH_LABEL_FIXTURE = [
    [0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0],
    [0, 4, 6, 1, 2, 3, 1, 4, 0, 0, 0, 0],
    [4, 6, 2, 4, 4, 1, 1, 4, 0, 0, 0, 0],
    [4, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0],   # <- the baked '-' (idx1 stroke, cols 8..9)
    [4, 1, 4, 4, 4, 4, 4, 4, 1, 1, 4, 0],
    [4, 6, 2, 4, 4, 6, 1, 4, 4, 4, 4, 0],
    [0, 4, 6, 1, 1, 2, 4, 4, 0, 0, 0, 0],
    [0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0],
]
SPEED_LABEL_FIXTURE = [
    [0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 4, 2, 1, 1, 2, 1, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4],
    [0, 4, 1, 4, 4, 3, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 4, 1, 4],
    [0, 4, 2, 1, 2, 3, 4, 4, 1, 1, 3, 4, 3, 1, 1, 3, 4, 3, 1, 1, 3, 4, 2, 1, 1, 4],
    [0, 4, 4, 4, 2, 1, 3, 4, 1, 3, 1, 4, 1, 4, 2, 1, 4, 1, 4, 2, 1, 4, 1, 4, 1, 4],
    [0, 4, 1, 3, 4, 4, 1, 4, 1, 4, 1, 4, 1, 2, 3, 4, 4, 1, 2, 3, 4, 4, 1, 4, 1, 4],
    [0, 4, 1, 2, 1, 1, 2, 4, 1, 1, 3, 4, 3, 1, 1, 3, 4, 3, 1, 1, 3, 4, 2, 1, 1, 4],
    [0, 4, 4, 4, 4, 4, 4, 4, 1, 4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 0, 4, 4, 4, 4],
    [0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]


def stat_label_set(asset: bytes) -> dict:
    """The stats-band text labels (§15.14 row 14): baked RANGETILE word/token cells
    drawn through the dark-ink-on-tan menu label CLUT 0x7C3C. Carries the 16-RGBA
    palette (read from the asset tail +0x9000, same bytes as the slot dark layer /
    header inactive_label) so the scene can bind it directly — the label is rendered
    exactly like the ability/slot icons (one index->CLUT sprite), NOT as FONT.BIN."""
    colors = header_clut_colors(asset, STAT_LABEL_DARK_OFF)
    return {"clut": STAT_LABEL_CLUT, "colors": colors,
            "labels": [dict(l) for l in STAT_LABELS]}


# --- detail/Status-screen Eqp/Ability window TITLE TABS (§15.19) -------------
# The monolithic lower window carries two cream, black-bordered title tabs — "Eqp"
# and "Ability" — one at the top of each icon column. Live-decoded from the settled
# OT arena (ram_ss4, offsets 0x1C3xxx): both are SPRTt cells on THIS RANGETILE page
# (VRAM 960,256) through the WHITE-ink-on-dark active-label CLUT 0x7CBC (asset tail
# +0x9040 — the SAME palette the formation active sort-tab uses), drawn like the
# word labels (one index->CLUT sprite). "Eqp" = cell (28,32) 18x10, "Ability" =
# (0,32) 26x10; each cell bakes its own tan fill (idx4) + dark outline (idx1), so no
# separate box is needed. Screen (live −0x80 X-bias): Eqp (29,131), Ability (131,131).
WINDOW_TAB_CLUT = 0x7cbc          # active_label CLUT (VRAM 960,498), asset tail +0x9040
WINDOW_TAB_OFF = 0x9040
WINDOW_TABS = [
    {"name": "Eqp",     "x": 28, "y": 32, "w": 18, "h": 10},
    {"name": "Ability", "x": 0,  "y": 32, "w": 26, "h": 10},
    # The START sub-menu's "Menu" title (§15.20): a baked word cell drawn through the
    # SAME active-label CLUT 0x7CBC, live prim `SPRTt uv=(120,120) wh=(24x8)` at display
    # (175,119) — outside the body box-open scissor (the §15.19 title-tab pattern).
    {"name": "Menu",    "x": 120, "y": 120, "w": 24, "h": 8},
    # The §15.26 equip-picker header's "ALL" word (right of the reused "Eqp" tab): the SAME
    # cream cell on THIS RANGETILE page, in the "Total Next ALL Check Effect Menu" word row
    # (y120) alongside "Menu" — drawn through the SAME active-label CLUT 0x7CBC. User-provided
    # cell (2026-08-09): the "ALL" glyphs span (45,120)-(61,127) on this sheet. No new asset.
    {"name": "ALL",     "x": 45,  "y": 120, "w": 16, "h": 8},
]
# Reproducibility fixture — the "Eqp" tab at its ROM cell (28,32) 18x10 indices
# (idx4 tan fill / idx1 dark ink; 0 = transparent). Fails loud on atlas drift.
EQP_TAB_FIXTURE = [
    [4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [4, 1, 1, 1, 1, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0],
    [4, 4, 1, 3, 4, 1, 4, 3, 1, 1, 3, 4, 2, 1, 1, 3, 4, 0],
    [0, 4, 1, 1, 1, 4, 4, 1, 4, 4, 1, 4, 4, 1, 3, 1, 4, 0],
    [0, 4, 1, 3, 4, 4, 4, 1, 4, 4, 1, 4, 4, 1, 4, 1, 4, 0],
    [4, 3, 1, 4, 3, 1, 4, 1, 4, 3, 2, 4, 4, 1, 1, 3, 4, 4],
    [4, 1, 1, 1, 1, 1, 4, 3, 1, 2, 4, 4, 4, 1, 4, 4, 1, 4],
    [4, 4, 4, 4, 4, 4, 4, 4, 3, 2, 1, 4, 2, 1, 2, 4, 4, 4],
    [0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]


def window_tabs_set(asset: bytes) -> dict:
    """The two lower-window title tabs (§15.19): baked RANGETILE word cells drawn
    through the active-label CLUT 0x7CBC (cream ink on dark), each carrying its own
    tan fill + dark outline. Same sheet/mechanism as the word labels; no new asset."""
    colors = header_clut_colors(asset, WINDOW_TAB_OFF)
    return {"clut": WINDOW_TAB_CLUT, "colors": colors,
            "labels": [dict(l) for l in WINDOW_TABS]}


def atlas_block(texels: bytes, x0: int, y0: int, w: int, h: int) -> list[list[int]]:
    """The h x w grid of 4bpp indices at (x0, y0) in the 256x256 atlas."""
    return [[nibble(texels, x, y) for x in range(x0, x0 + w)]
            for y in range(y0, y0 + h)]


def digit_set() -> dict:
    """The damage/status number digit strip: one cell per glyph in `DIGIT_GLYPHS`,
    drawn as a single textured pass through the number CLUT (`DIGIT_CLUT`, VRAM
    0x7d7c). `colors` is that CLUT's 16 RGBA entries (idx0 transparent) — the
    renderer looks the glyph index up in it instead of flat-tinting, so the
    outline/fill/AA shading come out faithfully in one pass."""
    cells = fixed_pitch_cells(DIGIT_ORIGIN[0], DIGIT_ORIGIN[1],
                              DIGIT_CELL_W, DIGIT_CELL_H, DIGIT_PITCH_X,
                              len(DIGIT_GLYPHS))
    colors = [list(bgr555_to_rgba(w & 0xFF, w >> 8, i == 0))
              for i, w in enumerate(DIGIT_CLUT_BGR555)]
    return {"glyphs": DIGIT_GLYPHS, "clut": DIGIT_CLUT, "colors": colors,
            "cells": cells}


def fixed_pitch_cells(origin_x: int, origin_y: int, cell_w: int, cell_h: int,
                      pitch_x: int, count: int) -> list[dict]:
    """A single row of `count` equal cells laid out at `pitch_x` from an origin.

    The digit strip glyphs nearly touch, so they are measured as fixed pitch
    from an origin rather than split by inter-glyph gaps (spec §8.2)."""
    return [{"x": origin_x + i * pitch_x, "y": origin_y, "w": cell_w, "h": cell_h}
            for i in range(count)]


def iso_path(cli_value: str | None) -> Path:
    """Resolve the raw ISO .bin — see `_repo_paths.iso`, the one resolver."""
    return _repo_paths.iso(cli_value)


def read_lba(bin_path: Path, lba: int, nsectors: int) -> bytes:
    """Read the 2048-byte user payload of nsectors Mode-2 sectors from lba."""
    out = bytearray()
    with bin_path.open("rb") as f:
        for i in range(nsectors):
            f.seek((lba + i) * SECTOR_SIZE + USER_DATA_OFFSET)
            chunk = f.read(USER_DATA_SIZE)
            if len(chunk) != USER_DATA_SIZE:
                raise IOError(f"short read at LBA {lba + i:#x} in {bin_path}")
            out += chunk
    return bytes(out)


def nibble(texels: bytes, x: int, y: int) -> int:
    """4bpp pixel (low nibble = even x, high nibble = odd x)."""
    byte = texels[y * (TEX_W // 2) + (x >> 1)]
    return (byte & 0x0F) if (x & 1) == 0 else (byte >> 4)


def bgr555_to_rgba(lo: int, hi: int, index_is_zero: bool) -> tuple[int, int, int, int]:
    """PSX BGR555 -> RGBA8. Bit 15 of the source word is the STP
    (semi-transparency) flag — pixels with STP=1 participate in the tpage's
    ABR blend; STP=0 pixels are always opaque, even when ABE is on. We encode
    STP in the destination alpha channel so a single palette TGA carries both
    the color and the per-index blend gate:

      idx 0  (transparent slot)  -> a=0    (discarded by the shader)
      STP=1                      -> a=128  (semi-transparent — blends)
      STP=0                      -> a=255  (opaque)

    The existing range-overlay shaders (tile_overlay.gdshaderinc) treat idx=0
    as transparent via the index check and ignore the palette alpha for non-
    zero indices, so this encoding is backward-compatible — it just adds a
    signal the cursor shader can read.
    """
    v = lo | (hi << 8)
    stp = (v >> 15) & 1
    r5, g5, b5 = v & 0x1F, (v >> 5) & 0x1F, (v >> 10) & 0x1F
    expand = lambda c: (c << 3) | (c >> 2)
    if index_is_zero:
        a = 0
    else:
        a = 128 if stp else 255
    return expand(r5), expand(g5), expand(b5), a


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--iso", help="raw FFT ISO .bin (default: project-assets)")
    ap.add_argument("--fft-extract", help="FFT extract root (for BATTLE.BIN)")
    ap.add_argument("--out", help="output dir (default: assets/sprites/textures)")
    args = ap.parse_args()

    bin_path = iso_path(args.iso)
    battle_bin = _repo_paths.battle_bin(args.fft_extract)
    world_bin = _repo_paths.world_bin(args.fft_extract)
    out_dir = Path(args.out) if args.out else _repo_paths.assets_dir("sprites/textures")
    out_dir.mkdir(parents=True, exist_ok=True)

    if not bin_path.exists():
        print(f"ERROR: ISO not found: {bin_path}", file=sys.stderr); return 1
    if not battle_bin.exists():
        print(f"ERROR: BATTLE.BIN not found: {battle_bin}", file=sys.stderr); return 1
    if not world_bin.exists():
        print(f"ERROR: WORLD.BIN not found: {world_bin}", file=sys.stderr); return 1

    # --- texels from the ISO ---
    asset = read_lba(bin_path, TEXTURE_LBA, ASSET_SECTORS)
    texels = asset[TEXELS_OFFSET:TEXELS_OFFSET + TEXELS_SIZE]
    if len(texels) != TEXELS_SIZE:
        print("ERROR: asset shorter than expected", file=sys.stderr); return 1

    # verify the tile band reproduces (fail loud on a wrong region/offset).
    # Validate the fixtured columns only (cols 0..12); col 13 of the 14-wide
    # crop has no recorded expected value, so don't gate on it.
    got_row = [nibble(texels, x, TILE_UV["y"]) for x in range(len(TILE_FIRST_ROW))]
    if got_row != TILE_FIRST_ROW:
        print(f"ERROR: tile fixture mismatch at V{TILE_UV['y']}: {got_row} "
              f"!= {TILE_FIRST_ROW} (wrong LBA/offset or ISO?)", file=sys.stderr)
        return 1

    # verify the damage-digit strip reproduces (glyph '0' at DIGIT_ORIGIN).
    dz = atlas_block(texels, DIGIT_ORIGIN[0], DIGIT_ORIGIN[1],
                     DIGIT_CELL_W, DIGIT_CELL_H)
    if dz != DIGIT_ZERO_FIXTURE:
        print(f"ERROR: digit fixture mismatch at {DIGIT_ORIGIN}: {dz} "
              f"(wrong atlas/origin/pitch?)", file=sys.stderr)
        return 1

    # verify the "Hp" word-label reproduces (ROM cell hits the glyph).
    hp = next(l for l in word_label_set()["labels"] if l["name"] == "Hp")
    hpb = atlas_block(texels, hp["x"], hp["y"], hp["w"], hp["h"])
    if hpb != HP_LABEL_FIXTURE:
        print(f"ERROR: Hp label fixture mismatch at ({hp['x']},{hp['y']}): {hpb} "
              f"(wrong atlas/label origin?)", file=sys.stderr)
        return 1

    # verify both "AT" active-turn marker frames reproduce. This is also the strip's
    # cell-identity anchor: frame A is table entry 8's cell, so a status-icon strip
    # remapped off its true columns fails HERE rather than shipping a silently
    # neighbour-shifted RANGETILE.json (AT_MARKER_RENDERING.md §8.2).
    at_frames = active_turn_set()["frames"]
    for f, want in zip(at_frames, [AT_MARKER_FIXTURE_A, AT_MARKER_FIXTURE_B]):
        atb = atlas_block(texels, f["x"], f["y"], f["w"], f["h"])
        if atb != want:
            print(f"ERROR: AT marker fixture mismatch at ({f['x']},{f['y']}): {atb} "
                  f"(wrong atlas/marker cell?)", file=sys.stderr)
            return 1

    # verify the "Br" formation-header label reproduces (guards the #174 header
    # cells added above against atlas drift, same as Hp).
    br = next(l for l in word_label_set()["labels"] if l["name"] == "Br")
    brb = atlas_block(texels, br["x"], br["y"], br["w"], br["h"])
    if brb != BR_LABEL_FIXTURE:
        print(f"ERROR: Br label fixture mismatch at ({br['x']},{br['y']}): {brb} "
              f"(wrong atlas/label origin?)", file=sys.stderr)
        return 1

    # verify the dialogue page-turn icon reproduces (frame 0's page + shadow).
    pib = atlas_block(texels, PAGE_ICON_ORIGIN[0], PAGE_ICON_ORIGIN[1],
                      PAGE_ICON_CELL_W, PAGE_ICON_CELL_H)
    if pib != PAGE_ICON_FRAME0_FIXTURE:
        print(f"ERROR: page-icon fixture mismatch at {PAGE_ICON_ORIGIN}: {pib} "
              f"(wrong atlas/origin?)", file=sys.stderr)
        return 1

    # verify the detail-screen Ability-window blade icon reproduces (§15.15).
    ab = atlas_block(texels, ABILITY_ICON_CELLS[0]["x"], ABILITY_ICON_CELLS[0]["y"],
                     ABILITY_ICON_CELLS[0]["w"], ABILITY_ICON_CELLS[0]["h"])
    if ab != ABILITY_BLADE_FIXTURE:
        print(f"ERROR: ability blade fixture mismatch at "
              f"({ABILITY_ICON_CELLS[0]['x']},{ABILITY_ICON_CELLS[0]['y']}): {ab} "
              f"(wrong atlas/origin?)", file=sys.stderr)
        return 1

    # verify the detail-screen Eqp R.Hand slot icon reproduces (§15.16).
    rh = SLOT_ICONS[0]["lit"]
    rhb = atlas_block(texels, rh[0], rh[1], rh[2], rh[3])
    if rhb != SLOT_RHAND_LIT_FIXTURE:
        print(f"ERROR: slot R.Hand lit fixture mismatch at ({rh[0]},{rh[1]}): {rhb} "
              f"(wrong atlas/origin?)", file=sys.stderr)
        return 1

    # verify the detail-screen weapon-type legend icons reproduce (§15.18): the lit
    # dagger/rod cell (64,0) and its dark backing (80,0), both 12x24. Fail loud.
    for cell, fx, tag in ((WEAPON_ICON_LIT, WEAPON_ICON_LIT_FIXTURE, "lit"),
                          (WEAPON_ICON_DARK, WEAPON_ICON_DARK_FIXTURE, "dark")):
        got = atlas_block(texels, cell["x"], cell["y"], cell["w"], cell["h"])
        if got != fx:
            print(f"ERROR: weapon-icon {tag} fixture mismatch at "
                  f"({cell['x']},{cell['y']}): {got} (wrong atlas/origin?)", file=sys.stderr)
            return 1

    # verify the lower-window "Eqp" title tab reproduces (§15.19).
    et = next(l for l in WINDOW_TABS if l["name"] == "Eqp")
    etb = atlas_block(texels, et["x"], et["y"], et["w"], et["h"])
    if etb != EQP_TAB_FIXTURE:
        print(f"ERROR: window tab 'Eqp' fixture mismatch at ({et['x']},{et['y']}): "
              f"{etb} (wrong atlas/origin?)", file=sys.stderr)
        return 1

    # verify the stats-band labels reproduce (§15.14 row 14): "Move" (header-row
    # label), "C-" (the baked dash — proves '-' is inside the cell, not a FONT glyph),
    # and "Speed" (the off-row menu-word cell). Fail loud on atlas drift.
    for lbl, fx in (("Move", MOVE_LABEL_FIXTURE), ("C-", CDASH_LABEL_FIXTURE),
                    ("Speed", SPEED_LABEL_FIXTURE)):
        d = next(l for l in STAT_LABELS if l["name"] == lbl)
        got = atlas_block(texels, d["x"], d["y"], d["w"], d["h"])
        if got != fx:
            print(f"ERROR: stat label '{lbl}' fixture mismatch at ({d['x']},{d['y']}): "
                  f"{got} (wrong atlas/origin?)", file=sys.stderr)
            return 1

    # verify the HP/MP/CT bar swatch reproduces (the rounded bar end).
    swb = atlas_block(texels, BAR_SWATCH["x"], BAR_SWATCH["y"], 6, 6)
    if swb != BAR_SWATCH_FIXTURE:
        print(f"ERROR: bar swatch fixture mismatch at "
              f"({BAR_SWATCH['x']},{BAR_SWATCH['y']}): {swb} (wrong atlas?)",
              file=sys.stderr)
        return 1

    # verify the HP bar CLUT reproduces (asset palette tail, +0x9160).
    hp_clut = asset[BAR_CLUT_OFFSET:BAR_CLUT_OFFSET + BAR_CLUT_STRIDE]
    if hp_clut.hex() != BAR_HP_CLUT_HEX:
        print(f"ERROR: HP bar CLUT mismatch at asset +{BAR_CLUT_OFFSET:#x}: "
              f"{hp_clut.hex()} (wrong asset/offset?)", file=sys.stderr)
        return 1

    # verify the four formation-header CLUTs reproduce (asset palette tail — the
    # dark-ink/tan/white/button palettes the header samples; #174 v2, §12.3.2).
    for hc in HEADER_CLUTS:
        got = asset[hc["off"]:hc["off"] + PAL_BYTES].hex()
        if got != HEADER_CLUT_HEX[hc["name"]]:
            print(f"ERROR: header CLUT '{hc['name']}' (0x{hc['clut']:x}) mismatch at "
                  f"asset +{hc['off']:#x}: {got} (wrong asset/offset?)", file=sys.stderr)
            return 1

    # verify the equip stat-DELTA palette reproduces (asset palette tail, +0x91E0 = FRAME
    # palette 15 = CLUT 0x7FFC — the blue/red delta sub-ramps). Fail loud on drift.
    delta_clut = asset[DELTA_PALETTE_OFF:DELTA_PALETTE_OFF + PAL_BYTES]
    if delta_clut.hex() != DELTA_PALETTE_HEX:
        print(f"ERROR: delta palette (0x{DELTA_PALETTE_CLUT:x}) mismatch at asset "
              f"+{DELTA_PALETTE_OFF:#x}: {delta_clut.hex()} (wrong asset/offset?)", file=sys.stderr)
        return 1

    # 8bpp grayscale, value = index*17 (16 indices -> 0..255), top-to-bottom
    gray = bytes(nibble(texels, x, y) * 17
                 for y in range(TEX_H) for x in range(TEX_W))
    tex_out = out_dir / "RANGETILE.tga"
    write_grayscale_tga(tex_out, TEX_W, TEX_H, gray)

    # --- palettes from BATTLE.BIN: 9 consecutive 32-byte slots at 0x2DAE4 ---
    bb = battle_bin.read_bytes()
    world = world_bin.read_bytes()
    blue = bb[PAL_BASE:PAL_BASE + PAL_BYTES]
    if blue.hex() != BLUE_PALETTE_HEX:
        print(f"ERROR: blue palette fixture mismatch at 0x{PAL_BASE:X}: "
              f"{blue.hex()} (wrong BATTLE.BIN/offset?)", file=sys.stderr)
        return 1

    pal_pixels: list[tuple[int, int, int, int]] = []
    for slot in range(PAL_COUNT):
        off = PAL_BASE + slot * PAL_BYTES
        row = bb[off:off + PAL_BYTES]
        for idx in range(16):
            lo, hi = row[idx * 2], row[idx * 2 + 1]
            pal_pixels.append(bgr555_to_rgba(lo, hi, index_is_zero=(idx == 0)))
    pal_out = out_dir / "RANGETILE.palette.tga"
    write_rgba_tga(pal_out, 16, PAL_COUNT, pal_pixels)

    # --- manifest ---
    manifest = {
        "texture": tex_out.name,
        "palette": pal_out.name,
        "texture_size": [TEX_W, TEX_H],
        "index_scale": 17,
        "tile_uv": TILE_UV,
        "cursor_uv": CURSOR_UV,
        # feedback-HUD sprite sets: digits (two-layer shadow+fill) and the
        # ROM-authoritative word-label cells (decoded from live GPU primitives),
        # each carrying its own CLUT — separate palettes from `palette_rows`.
        "digits": digit_set(),
        # Formation zodiac-sign glyphs (§14.3): 13 signs across two fixed-pitch
        # atlas rows, one cell per sign, reusing the number CLUT as a default tint.
        "zodiac": zodiac_set(),
        # Unit-detail/Status-screen icon sets (§15.15/§15.16): the five FIXED
        # Ability-window row icons (one CLUT) and the five Eqp slot-category icons
        # (two-layer lit+dark emboss + 2H-collapse variant). Same sheet, no new asset.
        "ability_icons": ability_icon_set(),
        "slot_icons": slot_icon_set(asset),
        # Weap.Power band weapon-type legend (§15.18): one FIXED two-layer emboss
        # (dark 0x7C3C under a colourful dagger/rod 0x7D7C) — NOT ITEM.BIN, same sheet.
        "weapon_icons": weapon_icon_set(asset),
        # Equip-picker per-TYPE class glyphs (§15.28): the WORLD.BIN type→UV LUT
        # (0x8018D7FC), 12×12 cells through the idle dark CLUT 0x7C3C — one cell per
        # item class byte (1=Knife, 3=Sword, …), NOT one fixed sword.
        "type_glyphs": type_glyph_set(world, asset),
        # Formation START sub-menu glove cursor (§15.20): two-layer 16×16 emboss (lit
        # 0x7D7C swirl over a 0x7DBC shadow +2/+2) — the first glove consumer, same sheet.
        "menu_glove_cursor": menu_glove_cursor_set(asset),
        # Stats-band text labels (§15.14 row 14): baked RANGETILE word/token cells
        # (Move/Jump/Speed/Weap.Power/AT/C-EV/S-EV/A-EV/R/L) drawn through CLUT 0x7C3C
        # — the faithful source (NOT FONT.BIN), sourced from the live OT + this atlas.
        "stat_labels": stat_label_set(asset),
        # Lower-window title tabs (§15.19): "Eqp"/"Ability" cream word cells through
        # the active-label CLUT 0x7CBC, one at the top of each icon column of the
        # monolithic Eqp+Ability panel. Same sheet/mechanism as the word labels.
        "window_tabs": window_tabs_set(asset),
        "word_labels": word_label_set(),
        "page_turn_icon": page_turn_icon_set(),
        "bars": bar_set(asset),
        # Formation sort-tab header (#174 v2, §12.3.2): ROM CLUTs + textured
        # button cells + label layout, re-derived from the VRAM oracle.
        "sort_header": sort_header_set(asset),
        # Status/detail-screen ◄L1 / R1► unit-pager buttons (§15.22): same page +
        # button CLUT as the sort-header, at the Status corners, single-cell captions.
        "detail_pager": detail_pager_set(),
        "status_icons": status_icon_set(bb),
        # The "AT" active-turn marker (AT_MARKER_RENDERING.md): carousel slot 21's
        # two 14x12 frames + the menu CLUT. A code literal in the ROM, so it is NOT
        # reachable through `status_icons` above — emitted as its own named cell pair
        # so the port never has to write Rect2(114,176,14,12) by hand (root ADR-0001).
        "active_turn": active_turn_set(),
        # Equip stat-DELTA colour palette (§15.26 / EQUIP_STAT_PREVIEW.md §5): FRAME palette 15
        # (CLUT 0x7FFC), the ONE palette the compare panel index-biases to colour a signed delta
        # blue([13], positive) / red([9], negative) / tan([1], plain). Same asset tail as the
        # header CLUTs. The port builds the biased number CLUTs from these 16 entries.
        "delta_palette": {"clut": DELTA_PALETTE_CLUT,
                          "colors": header_clut_colors(asset, DELTA_PALETTE_OFF)},
        "palette_rows": PALETTE_NAMES,
        "animation": ANIMATION,
        "source": {"texels_lba": TEXTURE_LBA, "texels_asset_offset": TEXELS_OFFSET,
                   "palette_battle_bin_base": PAL_BASE,
                   "palette_battle_bin_stride": PAL_BYTES,
                   "palette_count": PAL_COUNT,
                   "status_icon_x_off": STATUS_ICON_X_OFF,
                   "status_icon_y_off": STATUS_ICON_Y_OFF},
    }
    json_out = out_dir / "RANGETILE.json"
    json_out.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"wrote {tex_out}  ({TEX_W}x{TEX_H} 8bpp)")
    print(f"wrote {pal_out}  (16x{PAL_COUNT} RGBA — rows: {', '.join(PALETTE_NAMES)})")
    print(f"wrote {json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
