> ⚠️ **SUPERSEDED (2026-06-18) by [`frame-bin-number-font.md`](frame-bin-number-font.md).**
> That doc is the authoritative, disassembly-confirmed account. Two corrections
> this file gets wrong: (1) the HP/MP/CT readout uses the **small set for cur AND
> max** (one size; the "big cur / small max" framing below is an illusion from the
> max's baseline stagger), and (2) the glyph geometry is **code-confirmed**
> (`U = 120 + digit*pitch`, pitch 6 small / 8 big; disasm `FUN_8014aec0` /
> `FUN_8014ac30`), not hand-measured. The provenance/recipe notes below remain
> useful background.

# The HUD Number Font — FRAME.BIN source + dynamic-analysis faithfulness check

**Status:** design / RE note (pre-implementation). Written before the pull so the
extraction is grounded in verified provenance, not guesswork.
**Scope:** the `cur/max`, `Lv.`, and `Exp.` digits in the bottom-left vitals
readout (`src/ui3/UIUnitInfoWindow.gd`). Companion to
`docs/battle-hud-faithful-spec.md` (§8 ASSEMBLED) and memory
`project_battle_hud_re.md`.

---

## TL;DR

- FFT has **two different UI number fonts**, in **two different ISO files**:
  - a **soft, antialiased damage font** in the BATTLE.BIN range-tile atlas
    (our `RANGETILE.tga`), and
  - a **blocky, two-tone menu/number font** in `EVENT/FRAME.BIN`.
- **The HUD `cur/max`/`Lv.`/`Exp.` digits are the FRAME.BIN font**, not the
  range-tile font. They were previously confused for one another because ShiShi
  Sprite Editor shows both UI assets together.
- At runtime the game does **not** blit a static digit cell. It **rasterises the
  FRAME.BIN glyphs into a scratch VRAM page** (tpage 0x07) with tight kerning,
  then draws that composed strip as a single quad.
- Plan: extract the glyphs **statically** from `FRAME.BIN` (ISO-reproducible,
  byte-faithful), colour them through the menu CLUT, and derive **kerning** from
  the runtime scratch composition. Validate the static extraction against a
  **dynamic capture** of what the emulator actually drew.

This replaces the current fragile method (per-savestate byte-capture of the
composed scratch page + a destructive morphological "un-overlap" pass that
damaged the `8`).

---

## Background: two number fonts, one confusion

When you look at the bottom-left vitals panel the numbers *look* like the
range-tile digits — but at the pixel level they are a different font. The
confusion is understandable: ShiShi presents FFT's UI graphics together, and both
files are "UI art". They are nevertheless distinct assets backing distinct fonts.

| | `RANGETILE.tga` (our atlas) | `EVENT/FRAME.BIN` |
|---|---|---|
| **ISO source** | `BATTLE.BIN`, raw-sector asset at **LBA 0xE68** → loaded to VRAM **(960,256)**, tpage 0x3F (loader `FUN_80045154`) | `EVENT/FRAME.BIN` (its own file) |
| **Contents** | range tiles, cursor, status bubbles, `Hp`/`Mp`/`Ct` labels, bars, **soft damage-digit strip** | window frames + **blocky number/menu font** |
| **Digit palette indices** | 1, 2, 3, **5** (antialiased) | 1, 2, 3, **4** (two-tone + light shading) |
| **Digit `0` height** | ~6 px, rounded oval | ~8 px, blocky oval |
| **Used by** | floating damage numbers over units | **the HUD `cur/max` + `Lv.`/`Exp.` digits** |

The single line in `battle-hud-faithful-spec.md` §8 that says the digits come
"from the (168,49) strip" is the early hypothesis; it is **superseded** by this
document. The strip is the wrong font.

---

## Where the digits come from (runtime composition)

The vitals draw function does not have a static "999/999" texture. It:

1. takes the numeric value (e.g. `cur`, `max`),
2. for each decimal digit, **rasterises the FRAME.BIN glyph into a scratch VRAM
   page** — **tpage 0x07 = VRAM halfword (448,0) = pixel x≈1792, y0** — packing
   the glyphs together with **tight, overlapping kerning**,
3. draws that composed region as **one POLY_FT4 quad** (per the §8 ASSEMBLED
   table: `cur/max` quad screen (218,188) 40×40; `Lv/Exp` quad (166,170) 96×16),
4. colours it through the **menu CLUT `0x7cbc` = VRAM (960,498)**.

So in VRAM the **only** rasterised copy of these digits is the *composed* scratch
strip — which is why the previous RE captured from there, and why the glyphs
overlap (the routine kerns them tight during step 2). The **clean source bitmap**
is the FRAME.BIN font (step 2's input).

---

## The source: `EVENT/FRAME.BIN`

- **Format:** 4 bpp, 256 px wide (128 bytes/row), low-nibble-first. Size 37 568
  bytes; the image decodes cleanly at 128 B/row and there is a 64-byte tail
  (likely a trailing CLUT / padding — confirm during the pull).
- **Window frames** occupy the bulk of the top-left (the repeating
  `1c8c84…2dd` bordered-box texture).
- **The blocky number font sits in the top band**, to the right of and below the
  frame art. Rendering the file through the menu CLUT reveals **two complete,
  separately-authored digit sets** stacked vertically, beginning near **x≈120**:
  - **Row 1 (y≈4–14): the BIG set** — `0 1 2 3 4 5 6 7 8 9 /` (a second `/`
    follows).
  - **Row 2 (y≈17–25): the SMALL set** — `0 1 2 3 4 5 6 7 8 9 / - = x +`.

  This is the crux: the HUD's two number sizes are **not a scale factor** — they
  are these two authored fonts. **`cur` (big) → row 1; `max` (small) → row 2.**
  The same band also holds `+ - = x`, the `1/2` glyph, `GIL`, and `Exp.`/`Hp`/
  `Mp` labels (the labels are *also* recoverable here, though the panel currently
  sources them from RANGETILE — out of scope for the NumberFont).
- The font is **proportional** and FFT stores the glyphs nearly **touching**.
  Measured origins (top-left x of each glyph `0-9 /`), baked in
  `tools/parse_frame_font.py`:
  - **BIG** (y=3, cell 8×11): `120 129 137 145 153 161 168 176 185 193 201`
  - **SMALL** (y=16, cell 6×10): `120 126 131 137 143 149 155 161 167 173 179`

  ⚠️ The SMALL origins were **re-measured 2026-06-18**. The earlier set stepped
  too wide (~7 px) and accumulated drift over the 11 glyphs, pushing the late
  cells off their glyphs — small `9` had landed on the `/`, and small `/` on the
  `=` operator. The weak idx-4-fraction guard didn't catch it (a slash and an `=`
  both have a strong outline), so `test_parse_frame_font.py` now asserts the
  *shape* of those two tell-tales. The SMALL cell is also trimmed to 6 px wide
  (from 7) so it no longer carries the next glyph's left stroke as a 1px sliver
  to the right of the last `max` digit.
- **Known limitation** (tracked, low impact): because the font is proportional but
  the cells are fixed-width, a few cells carry a 1px sliver of a touching
  neighbour's outline. The glyphs read correctly; a future refinement is a
  per-glyph **width** table (or a detached-edge trim) for pixel-clean isolation.
  The runtime renders by per-glyph advance, so slivers fall in the inter-glyph
  gap and are largely invisible.

### Evidence the FRAME.BIN font *is* the HUD font

Glyph `0` extracted from FRAME.BIN vs. glyph `0` captured from the live scratch
composition (sstate1), as raw 4 bpp palette indices:

```
FRAME.BIN '0' (static)     scratch '0' (dynamic, sstate1)
   ..4444..                   .4444444
   .421124.                   43113421
   42133124                   41341444
   41244214                   41441443
   41244214                   41431431
   42133124                   43113411
   .421124.                   .4444444
```

Same font: 8-px blocky oval, **index-4 outline, index-1/2/3 body**. They are
**not byte-identical**, and the difference is the whole point of the next
section: the dynamic capture carries the runtime **kerning / neighbour-bleed**
(note the extra ink in the scratch top row — that is the adjacent digit's emboss
leaking in), while the static FRAME.BIN glyph is clean.

---

## The `NumberFont` recipe

A reusable resource (HUD now; floating damage / menu counters later):

1. **Glyph bitmaps** ← extracted statically from `FRAME.BIN` (clean, no overlap,
   ISO-reproducible). **Two size variants**: a `big` strip (row 1, for `cur`) and
   a `small` strip (row 2, for `max`), each `0-9 /`. Stored as 4 bpp indices
   (grayscale = index×17), exactly like `RANGETILE.tga`, so they render through
   the same shader. (`+ - = x` are available if a future display needs them.)
2. **Palette** ← `MENU_CLUT 0x7cbc`. Already proven on the panel's labels and
   current digits: index 1 = `(239,239,231)` cream body, index 4 = `(33,24,16)`
   dark outline. (This CLUT only renders *this* font's indices correctly —
   feeding it the range-tile indices 1/2/3/5 would wash out, another reason the
   strip is the wrong source.)
3. **Metrics / kerning** ← measured from the runtime scratch composition (below).
   Per-glyph advance, the `cur` vs `max` size relationship, baseline stagger,
   and `/` placement.

`NumberFont.draw_number(value, …)` then replaces the bespoke `_render_number*`
code currently in `UIUnitInfoWindow.gd`.

---

## Kerning method

The one thing the **static** file does *not* tell us is how the runtime packs the
glyphs — that lives only in the **dynamic** composition. Method:

1. Capture the scratch page (tpage 0x07) for a known multi-digit number (e.g.
   `999/999`, `100/100`).
2. Locate each digit's left edge in the composed strip and compute the
   **inter-digit advance** (pitch). Compare to the glyph's own width to get the
   **overlap** (how far neighbours' emboss borders intrude — the "border
   overlap" effect).
3. Read the **two sizes**: the reference crop shows big `cur`, small `max`.
   Determine whether `max` is a second authored size or a scaled `cur`, and
   record the size ratio + baseline offset.
4. Record `/` placement (it bridges `cur`→`max`, set lower-right).

Output: a small **metric table** (per-size advance, baseline stagger, slash/max
offsets) baked into the `NumberFont` resource / `FRAMEFONT.json`.

### What we actually found (2026-06-18)

The composition is a **fixed advance, not pairwise side-bearing kerning**:
repeated digits (`999`, `100`) compose at one uniform pitch regardless of which
digits are adjacent. But there are **two gotchas** the implementation had to
resolve:

1. **The scratch page is a tighter intermediate than the display.** Its
   horizontal pitch (≈5 px for both sizes) is NOT what reaches the screen — at
   that pitch the 8 px-wide big glyphs would merge. The framebuffer reference
   (`project-assets/fft-rom/hud-capture/sstate1_left_panel.png`) shows the big
   `cur` digits clearly *separated*. So the on-screen advance is read off the
   **framebuffer**, not the scratch: `ADVANCE_BIG = 9`, `ADVANCE_SMALL = 7`
   (each ≈ glyph-width + 1 px gap). The scratch still pins two *scale-stable*
   facts (uniform advance; the cur→max vertical stagger `MAX_BASELINE_DY = 4`).
2. **`cur` and `max` advance differently** because they are different sizes
   (big 8 px cells, small 6 px cells). A single advance can't serve both — at the
   big advance the small `max` digits splay apart. Hence per-size advance.

`NumberFont.place_pair()` composes the block: big `cur` right-aligned to the
divider at `ADVANCE_BIG`, the big bridging `/`, then small `max` staggered
`(+5, +MAX_BASELINE_DY)` down-right at `ADVANCE_SMALL`. The slash/max offsets are
panel `@export` tunables for a final headful nudge.

---

## Dynamic-analysis faithfulness check

This is the key request: **prove the static FRAME.BIN extraction is faithful to
what the game actually draws**, using dynamic analysis as the oracle.

**Static artefact:** the `0-9 /` glyphs extracted offline from `FRAME.BIN`.

**Dynamic oracle:** the scratch-page VRAM captures pulled from fork-PCSX-Redux
(`tools/hud_digit_captures/scratchpad_sstate{1,3,5,6}.bin.gz`) — the actual pixels
the PSX renderer composed at runtime. These already exist; we can capture more
(other HP values) to cover every glyph and to measure kerning.

**The test (per glyph):**

1. Take the FRAME.BIN glyph for digit `d`.
2. Find an instance of `d` in a scratch capture where it is **flanked by spaces
   or sits at the number's edge** (so no neighbour overlaps it — e.g. the last
   digit of `403`/`528`, the technique the current captures already use).
3. Assert the FRAME.BIN glyph **matches the isolated scratch glyph's core**,
   pixel-for-pixel. Where they differ, the difference must be **only** at the
   columns/rows a neighbour's emboss reaches — i.e. attributable to kerning, not
   to a different bitmap.

If every digit's clean instance matches its FRAME.BIN glyph, we have **proven**:
the HUD composes its numbers from the FRAME.BIN font, and our static extraction
*is* the runtime font. Faithfulness is then ISO-reproducible — no committed
savestate captures needed in the shipping path (the dynamic captures remain only
as the test oracle / provenance).

**Optional deeper dynamic confirmation** (if we want belt-and-suspenders):

- Read the inline digit code in the vitals fn and the `DR_TPAGE`/`GetTPage` set
  before the digit run to confirm the **blit source** address resolves to the
  FRAME.BIN load region (closes "is it *really* FRAME.BIN and not a copy" at the
  code level, not just the pixel level).
- Capture fresh scratch pages for single-digit HP values to get every glyph
  isolated in one pass.

Drive PCSX via `cmd.exe curl.exe` POST Lua to `:8080/api/v1/lua/exec`; VRAM via
`GET /api/v1/gpu/vram/raw` (see `feedback_pcsx_fork_launch_config` +
`feedback_pcsx_drive_with_curl`). The scratch page only recomposes on cursor
re-select, so capture from purpose-made savestates.

---

## Plan / workflow

1. **Spike + parser — DONE (`/tdd`).** `tools/parse_frame_font.py` extracts both
   `0-9 /` strips from `FRAME.BIN` → `assets/sprites/textures/FRAMEFONT.tga` +
   `.json` (clut 0x7cbc, two size sets). Guarded by `tools/test_parse_frame_font.py`
   (12 tests): geometry, the **dynamic-analysis faithfulness check** (big `0`
   shares the live scratch capture's palette signature {1,2,3,4}+idx-4 outline,
   distinct from RANGETILE's {1,2,3,5}), an all-22-origins drift guard, the
   big-`0` reproducibility fixture, and the packed-atlas round-trip.
2. **DONE — kerning + `NumberFont`:** measured the per-size advance + cur/max
   baseline stagger + `/` placement (advance off the framebuffer, stagger off the
   scratch — see "What we actually found"); built `src/ui3/elements/NumberFont.gd`
   (loads `FRAMEFONT.tga`/`.json`, `place_number()`/`place_pair()`). Guarded by
   `tests/NumberFontTest.gd` (two sizes, per-size advance, right-aligned cur, big
   bridging slash, small staggered max).
3. **DONE — verify headful** in `UnitInfoWindowViewer.tscn` against
   `sstate1_left_panel.png`: the panel composes big `cur` / big `/` / small
   staggered `max` matching the reference. `UIUnitInfoWindow.gd` now renders
   `NumberFont` placements (the bespoke `_render_number*` is gone).
4. **DONE — retired** the byte-capture path (`build_hud_digits.py`,
   `HUDDIGITS.tga`/`.json`/`.import`, the morphological cleanup). The `.bin.gz`
   captures remain as the test oracle.

---

## Source-of-truth references

- Scratch page: tpage **0x07** = VRAM halfword **(448,0)** = px ≈1792.
- Menu CLUT: **0x7cbc** = VRAM **(960,498)**, index 1 cream / index 4 dark.
- Range-tile atlas: `BATTLE.BIN` LBA **0xE68** → VRAM **(960,256)**, tpage 0x3F
  (`tools/parse_range_tiles.py`).
- FRAME.BIN: `EVENT/FRAME.BIN`, 4 bpp, 256 px wide.
- Layout / panel: `docs/battle-hud-faithful-spec.md` §8; panel script
  `src/ui3/UIUnitInfoWindow.gd`.
