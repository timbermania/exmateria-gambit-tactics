# FRAME.BIN HUD Number Font — revisiting all priors (living doc)

**Started:** 2026-06-18. **Status:** ACTIVE investigation + cleanup.
**Why this doc exists:** the HUD `cur/max`/`Lv.`/`Exp.` numbers have been a
repeated struggle. The user called a hard stop to re-validate every prior from
scratch against (a) a real screenshot and (b) the actual `EVENT/FRAME.BIN`
bytes, before touching the parser again. This doc supersedes the relevant parts
of `docs/hud-number-font.md` and is kept continuously updated.

Reference screenshot: `/mnt/c/Users/acurr/Desktop/ss1_ui_ss.png` (1020×776).
Source file: `EVENT/FRAME.BIN` (37 568 bytes, 4bpp, 256 px wide → 293 rows;
ShiShi shows it 256×288 under **Other images → FRAME.BIN**).

---

## User's stated priors and their validation status

| # | Claim | Verdict | Evidence |
|---|-------|---------|----------|
| 1 | HP/MP/CT numbers come from `FRAME.BIN`; image 256×288 | ✅ TRUE | File is 256-wide 4bpp; renders the digit font cleanly. 293 rows (704-byte tail past 256×288 — TBD: trailing CLUT/padding). |
| 2 | `RANGETILE.tga` appears to be a subset of this image | ⏳ investigating | (below) |
| 3 | In ShiShi "Other images" tab under FRAME.BIN | ✅ TRUE | matches; it's an "Other image", not a BATTLE sprite. |
| 4 | small `0` at (120,17)→(125,23) | ✅ EXACT | 6 wide (120–125), 7 tall (17–23), dark-outline insets top/bottom. |
| 5 | small `1` at (126,17)→(131,23) | ✅ EXACT | pitch-6 contact sheet frames a clean `1`. |
| 6 | small `2` at (132,17)→(137,23) | ✅ EXACT | parser had drifted to 131 — **user's 132 is right**. |
| 7 | digits use the **same CLUT as HP/MP/CT text** (`0x7cbc`) | ✅ TRUE | matches the menu/text CLUT proven on the labels. |
| 8 | adjacent digits show **1 dark column between** → overlap 1px on screen | ✅ TRUE | source cells are 6 px wide (incl. L/R dark outline); the screen advance is 5 (overlap 1) so the two outline columns merge to one. |

### Two authored sizes exist — but the VITALS use only the small one
FRAME.BIN holds two authored digit sizes (BIG row y≈0, 8×16 cells; SMALL row
y≈16, 6×10 cells). **The HP/MP/CT readout uses the SMALL set for EVERYTHING** —
cur, the bridging `/`, and max are all one size; the max is just **staggered a
baseline lower-right**, which reads as a fraction. (The earlier "big cur + small
max" model was an illusion from that stagger — corrected by the user 2026-06-18
and confirmed both visually in the reference and in the disasm: the HUD builder
`FUN_801363dc` calls ONLY the small routine `FUN_8014aec0`.) The BIG set is
FFT's larger number font for other displays; we still extract it for reuse.

The user's "they all start around the same row (16/17)" is then exactly right
for the vitals — the whole readout is the y≈16/17 small set.

---

## Ground-truth geometry (re-measured 2026-06-18 from FRAME.BIN bytes)

### SMALL set (max / denominator, + bridging `/`)
- Row **y = 17**, cell **6 × 7** (y17–23).
- **Fixed pitch 6** in the sheet — origins:
  `120 126 132 138 144 150 156 162 168 174 180` for `0 1 2 3 4 5 6 7 8 9 /`.
- Contact sheet at these origins reads `0 1 2 3 4 5 6 7 8 9 /` cleanly.
- The cell's leftmost & rightmost columns are the dark outline (idx 4); placing
  cells at on-screen advance **5** merges neighbours' outlines into one dark
  column (user prior #8).

### BIG set (cur / numerator, + bridging `/`)
- Row **y ≈ 3**, cell ~**8 × 11**.
- Glyphs are **gap-separated** (a zero-ink column between each), so origins are
  found by gaps, not a fixed pitch. Current measured origins:
  `120 129 137 145 153 161 168 176 185 193 201`.
- Vertical strong band y4–11 with descenders/`/` to ~y14. (Exact cell height
  being re-confirmed.)

### Palette
Both sets render through **menu CLUT `0x7cbc`** = VRAM (960,498); idx1 = cream
`(239,239,231)` body, idx4 = dark `(33,24,16)` outline (idx2/3 AA). Same CLUT as
the `Hp`/`Mp`/`Ct` labels (user prior #7).

---

## ✅ RESOLVED: "RANGETILE is a subset of FRAME.BIN" (prior #2)

Confirmed with **mathematical certainty** by pixel diff:

> **`RANGETILE.tga` == `FRAME.BIN[rows 32 .. 288]`, 100% pixel-exact.**

- `RANGETILE.tga` is 256×256 (extracted from BATTLE.BIN, LBA 0xE68 → VRAM
  960,256). `FRAME.BIN` is 256×293 (EVENT file).
- Aligning `FRAME[y+32] == RANGETILE[y]` gives a perfect match across all 256
  shared rows. FFT ships the **same UI atlas twice**: once in BATTLE.BIN (256
  rows, battle VRAM) and once in EVENT/FRAME.BIN (with **32 extra top rows that
  hold the number font**).
- So the BATTLE range-tile/menu page and the EVENT frame page are the same
  graphic; ShiShi shows them as two "Other images" but they are siblings.

**Where is the HUD number font, then?** It is ONLY in FRAME.BIN's top 32 rows.
A pixel-exact template scan finds the small `0` glyph at **(120,17) and nowhere
else**, and the big `0` at **(120,3) and nowhere else** — the blocky digit font
is NOT duplicated inside the shared (battle-atlas) region. The greenish digit
strip visible lower in the atlas is a *different* font (different glyph shapes).

Implication: extracting the HUD number font from `EVENT/FRAME.BIN` (top rows) is
correct and byte-faithful; the BATTLE atlas (`RANGETILE.tga`) does not contain
these glyphs. (Provenance of how battle gets them into VRAM — runtime
composition into scratch tpage 0x07 per prior RE — is the disasm question below;
it does not change the source pixels.)

## ✅ RESOLVED: disassembly UV provenance (user asks 4 & 5) — FULL REFERENCES

The glyph UVs are **not a stored UV table** — they are **computed in code** as
`U = base + digit*pitch`, exactly the user's hypothesis (constant V, U stepping
by the pitch). The font is a 4bpp bitmap drawn by a software blitter, not GPU
primitives. All addresses are in **BATTLE.BIN** (load base `0x80067000`).

### Disassembly references (cite these, not line numbers)

| Symbol | RAM addr | Role |
|---|---|---|
| `FUN_8014aec0` | `ram:8014aec0` | **SMALL digit routine** — `U = digit*6 + 0x78`. Descriptor `0x80169780`: **V=0x10 (16), W=6, H=0x0a (10)**, stride `0x100`=256. `0x78` immediate at `ram:8014b0dc`, `ram:8014b1a0`. |
| `FUN_8014ac30` | `ram:8014ac30` | BIG digit routine — `U = digit*8 + 0x78`. Raw MIPS `sll v0,v0,0x3; addiu v0,v0,0x78` at `ram:8014ae08`–`8014ae38`. Descriptor `0x80169770`: W=8, H=0x10. |
| `FUN_801363dc` | `ram:801363dc` | **HUD vitals builder** — calls the SMALL routine `FUN_8014aec0` per stat on the unit vital fields (`DAT_8014d084`=unit+0x24, `DAT_8014d086`=unit+0x26, …). **This proves HP/MP/CT use the small set, one size.** |
| `FUN_8014bae4` | `ram:8014bae4` | the software blitter the digit routines feed the descriptor to. |
| font bitmap | `ram:8014d5d4` | the 4bpp HUD font, **file offset `0xe65d4`** (set via `DAT_80173f5c = &DAT_8014d5d4` in `FUN_8013eff4` @ `ram:8013eff4`). **Byte-identical to FRAME.BIN's top rows** (FRAME small row y19 found verbatim in BATTLE.BIN at `0xe6f90`). |
| `FUN_8014ab58` | `ram:8014ab58` | a THIRD number font (`digit*0x23`, pitch 35) — damage/large numbers, NOT the vitals. |
| alt-glyph | `DAT_80166044` | when `unit[+6] & 4`, switches to a masked-stat glyph (small U=`0xd0`). |

Exports used: `project-assets/fft-rom/battle_bin_disassembly.txt` (106 MB),
`battle_bin_decompilation.txt.c`, `hacktics_disassembly.txt` (471 MB, named) +
`hacktics_symbols.tsv`. Decompiled formula lines: SMALL @ ~line 67176, BIG @
~67076, HUD caller @ ~55640.

### What the disasm settles
- **base U = `0x78` = 120**, small pitch **6**, big pitch **8** — hard-coded,
  matching the user's measured small origins exactly.
- The HP/MP/CT readout is **one size (the small set)** — only `FUN_8014aec0` is
  called from the HUD builder; the big routine is for a different display.
- V is into the in-RAM font bitmap (small V=16), not a sheet coord — that is why
  no literal `17`/`3` UV immediates exist to grep.

---

## ✅ Parser fix — DONE (2026-06-18)

`tools/parse_frame_font.py` now generates origins straight from the disasm
formula `U = 120 + digit*pitch` (no more hand-measured drift):
- **SMALL**: `BASE_U=120`, `SMALL_PITCH=6` → `[120,126,132,…,180]`, cell 6×10 @
  V=16. (Fixes the old drift: digit 2 was 131, now 132.)
- **BIG**: `BASE_U=120`, `BIG_PITCH=8` → `[120,128,…,200]`, cell 8×16 @ V=0.
- **Advance = cell_width − 1** (overlap-1, the user's "1 dark column"): SMALL 5,
  BIG 7. (Was 7/9.)
- Manifest `cur_size/slash_size/max_size = "small"` → `NumberFont.place_pair`
  composes the whole vitals fraction in the small set. Panel `num_row_y` nudged
  +3 (small cur cell sits 3px higher than the old big cell).
- New regression test `GeometryMatchesDisassembly` pins base/pitch/cell so it
  can't drift back. 19 py tests + Godot `NumberFontTest` [PASS]. Panel headful-
  verified vs `sstate1_left_panel.png`: cur==max size, staggered, bar-aligned.

## Cleanup done
- `build_hud_digits.py` / `HUDDIGITS.*` — confirmed gone (no references remain).
- `docs/hud-number-font.md` — superseded; banner added pointing here.
- `tools/parse_frame_font.py`, `NumberFont.gd`, `UIUnitInfoWindow.gd`,
  `NumberFontTest.gd` comments all corrected to the all-small model.
