# The frameset viewport is a pixel-exact, texel-class view of the sheet

## Status

accepted

## Context

`FramesetCanvas` (#278/#279) shows the effect's texture sheet with the selected
frame's UV rect drawn over it. The layout question — where the panel sits and how
big it is — was settled in `db7a7c4a5`. This ADR is about the other half: **what
the panel actually draws**, which had never been examined.

Four independent fidelity defects were measured, and all four were live.

**1. The sheet was drawn through a bilinear filter.** `texture_filter` is set
nowhere — not on the canvas, not in `project.godot` — so it fell through to the
engine default, `Linear`. These are 44–256 px PSX sheets magnified past 1:1; the
result is a smear. (Ruled out as causes: `compress/mode=0` lossless,
`mipmaps/generate=false`, no VRAM compression. The *data* was always intact.)

**2. The sheet was drawn at a fractional scale, at every zoom level.** The base
fit is `min(avail/w, avail/h)` with no snapping, and `ZOOM_STEP` is `1.15`. At the
developer's 1261×688 dashboard the canvas is 297×297, so E019 (128×256) fits at
**1.098×** and E317 (128×128) at **2.195×**. At 1.098× with nearest filtering,
roughly every tenth row of texels renders 2 px tall while its neighbours render
1 px — a *different* artifact from blur, and the one that makes a per-pixel
readout untrustworthy.

**3. The STP bit was rendered as opacity.** ADR-0096 establishes that a texture's
alpha channel carries the **STP** (Semi-Transparency Processing) flag, not
opacity. `draw_texture_rect` does not know that: it alpha-blends, so every STP
texel drew at half opacity against a `PanelContainer` background — washed out, to
represent a blend-mode flag.

**4. The transparent background was rendered as opaque black — 72% of every
sheet.** This is the largest of the four and was invisible until the corpus was
classified three ways rather than by alpha alone. The PSX treats palette word
`0x0000` as fully transparent; the extractor carries it as opaque black
`RGBA(0,0,0,255)`, because RGBA has no "erased" value. Over all 401 non-empty
effects:

| texel class | corpus | share | E019 | E317 |
|---|---|---|---|---|
| **transparent** — `0x0000` | 10,563,218 | 72.11% | 15,547 | 13,145 |
| **transparent** — `0x8000` (black, STP set) | 158,778 | 1.08% | 2,776 | 0 |
| **opaque** (STP=0, real colour) | 254 | 0.0017% | 0 | 0 |
| **STP** (visible art) | 3,925,558 | 26.80% | 14,445 | 3,239 |

Both black rows are discarded by both particle passes, so **73.20% of the corpus
never draws**. `0x8000` reaching the top two rows rather than the STP row is
decision 3's rule at work: 49 effects contain such texels, and E001/E509/E510 are
each 88.1% of them.

The opaque class is empty in 397 of 401 effects (all 254 texels live in E365,
E001, E509, E510). **That is a fact about the ROM's content, not a bound on the
tool**: this is an authoring surface, STP=0 texels have been verified in-game to
render opaque, and the class is headroom an author can fill. It is kept for that
reason, not because the corpus uses it.

Two further measurements shaped what the viewport can honestly claim:

- **60 effects are shown in the wrong colours and this viewport cannot fix it.**
  `frames.json` carries `palette_id` per frame; 62 effects have 4bpp frames and 60
  use more than one sub-palette. A 4bpp sheet is not one image, but `texture.tga`
  is a flat RGBA decode through a single sub-palette. Recolouring per frame needs
  the index plane, which `TextureChannel.gd` records as existing "only in the BIN
  — the asset dir carries colours and the CLUT but no plane". ADR-0097 dec. 3
  defers that to its own ticket.
- **A colour does not identify a CLUT index**, so the index cannot be recovered
  even approximately: E019 has 67 distinct colours across 256 slots (189
  duplicates), E317 108/148. This is ADR-0097's finding, re-confirmed per-effect.

Finally, the chrome this implies had nowhere free to go. The canvas is already at
its height ceiling: `_relayout` computes `budget = h − MIN_CHANNELS_H(180) −
BAR_H(30)` and `editor_h` clamps to exactly that — **297 = budget** at the
developer's dashboard — so anything stacked below the canvas comes straight out of
the texture. But ~490×297 px of the inspector row sits empty between where the
frame fields end (~x450) and where the canvas begins (x954).

## Decision

1. **Nearest-neighbour filtering.** `texture_filter = TEXTURE_FILTER_NEAREST`.
   A PSX texel is a square of colour, not a sample to interpolate.

2. **An integer pixel ladder, everywhere, and the view opens at 100%.** Zoom
   walks `1,2,3,…,16`; zooming out walks the reciprocal rungs (`1/2`, `1/3`) as
   far as the rung where the whole sheet is visible, and no further. Every texel
   is always a whole number of screen pixels. An editor whose pixel grid is
   irregular cannot support a pixel readout, and the goal is "as raw as
   possible", not "as large as possible"; exact-fit stretching was rejected for
   the same reason.

   **Amended 2026-08-18, after building it.** This decision originally read "the
   base fit snaps *down* to the largest integer multiple that fits", costed at
   "~9% of the default view's linear size (E019 1.098×→1×, E317 2.195×→2×)".
   That estimate was width-limited and the built code disproved it: the panel is
   **297×270**, and the sheets are 128 px wide but 128–256 px *tall*, so **height
   binds**. E019's real fit is **0.992** — a hair under 1:1, exactly where
   snapping down falls to the **1/2** rung — and it opened drawing a 128×256
   sheet at **64×128**, filling 24% of the panel where the raw fit filled 98%.
   E317 (real fit **1.98**) fell from 2× to 1× the same way. The measured cost of
   fitting was therefore ~50% of the view, not ~9%.

   So the view opens at **100%** instead, whatever size the panel is. A sheet
   taller than the port overflows by a sliver and the author pans to it —
   decision 8's per-axis clamp makes that reversible — or zooms out deliberately.
   Rejected: snapping *up* within a tolerance (a magic constant nobody can
   justify) and keeping the fit (it halves the working view at the default panel
   size, and shrinks a 23×23 UV box to 12 px, smaller than the 8 px corner
   handles that are its own drag affordance — the frameset canvas's primary
   interaction stops working).

   **Amended again 2026-08-20: this is a property of the SURFACE, not of the
   renderer, and the flat 100% becomes a FLOOR on the surfaces that opt in.**

   The author, on the Texture tab (ADR-0130): *"can we get the texture defaulted
   to a reasonable size when we open the texture page? it starts kind of small."*
   Measured on their window (body 1187×1069, E019's 128×256 sheet): on a `frame`
   target the tab's port is **560×701** and the sheet drew **128×256** in the
   middle of it — 23% of the width, 37% of the height — because this decision
   said 100%, always.

   The amendment above was made against **one** port: the frame screen's 297×270,
   where fitting genuinely halves the view. It was then applied to a surface whose
   port is a different shape and whose job is not UV dragging. So the renderer
   grows a per-surface flag (`FramesetCanvas.open_at_fit`) and the opening rung
   becomes `max(1, fit)`:

   | port | fit | opens at | before |
   |---|---|---|---|
   | `frame` target, tab (423×701) | 2.00 | **2×** — 256×512, whole sheet | 128×256 |
   | `frameset` target, tab (472×263) | 0.50 | **1×** — unchanged | 128×256 |
   | frame screen (297×270) | 0.99 | **1×** — opted out entirely | 1× |

   **The floor is this decision surviving, not a hedge.** `fit_scale` snaps
   *down*, so the short `frameset` row — 263px against a 256-tall sheet — fits at
   0.96 and snaps to **0.5**: a bare fit would halve the picture to save nine
   pixels, which is the exact measurement that made this decision a flat 100% in
   the first place. Never smaller than before; bigger only where the port has the
   room. The frame screen does not opt in, so the drag-affordance argument above
   is untouched where it was made.

   Rejected: *fill the canvas* (the largest rung whose **width** fits, clipping
   the height). It gives the biggest picture — 3× on both ports — but on the short
   row it shows 32% of the sheet's height and costs the whole-sheet glance that
   100% currently gives. Costed for the author with both tables; they chose the
   floor.

   One cost, stated: the opening rung is **derived from the live port**, never
   snapshotted, for the same reason `_zoom_steps` is a rung count and not a scale
   — this port's height changes with the open target, so a scale stored at bind
   would be stale exactly when it mattered. An author who has zoomed therefore
   keeps their rung *count* across a resize that moves the base, not their
   absolute scale.

3. **A sheet is three texel classes, and the class boundaries are the game's own,
   not a palette-word taxonomy.** The whole rule, in three lines:

   > **black is discard pixel. STP is apply blend mode. no STP no black is
   > opaque.**

   The viewport classifies a texel exactly as the particle shaders route it; where
   a palette-word taxonomy and the shaders disagree, the shaders win — they are
   what the player sees. So:
   - **transparent** — `rgb == 0`, at **any** alpha (discarded). Defaults to
     **0%**, revealing a checkerboard.
   - **STP** — `rgb ≠ 0`, α<255 (routed to the blend pass).
   - **opaque** — `rgb ≠ 0`, α=255.

   Note that transparent is keyed on **colour, not on the palette word**. Both
   `0x0000` (transparent black) and `0x8000` (black with STP set — which
   `TEXTURE_AND_PALETTE_FORMAT.md` calls "opaque black") are discarded by both
   passes, unconditionally: `effect_particle_opaque.gdshader:22` and
   `effect_particle_stp.gdshaderinc:147` each test `r,g,b < 0.01` alongside their
   alpha tests. Classifying `0x8000` by its alpha instead would put **158,778
   texels (1.08% of the corpus, 3.89% of the STP class)** in with the visible art —
   and E001, E509 and E510 are each **88.1%** such texels, so their sheets would
   read as almost entirely art the game never draws. The palette word remains
   inspectable in the readout; it is simply not what the partition keys on.

   The partition needs no index plane. STP detection uses `alpha < 255`, which is
   *already* the read rule — `effect-editor/utils/bmp.lua:102-104` has always
   decoded it that way; only the writers happen to emit 128 as the marker. Nothing
   is invented and nothing needs re-exporting.

   Rejected: honouring alpha as opacity (it is a blend-mode flag, per ADR-0096);
   tinting STP texels (a lie about colour); a three-state selector (in "all" the
   classes are indistinguishable, the case that matters most); and folding the
   opaque class away as unused (see above — the corpus is the input, not the
   output space).

4. **The checkerboard is a correctness fix, not decoration.** **73.20%** of every
   sheet is never drawn by the game and was painting as solid black. The
   checkerboard is the only backdrop that can never be mistaken for content —
   which matters precisely because the never-drawn texels *are* black. The
   viewport drawing them was the one place in the codebase that rendered them at
   all; both particle passes discard them.

5. **Frame coverage is drawn.** Sheet regions no frame's UV rect addresses are
   dimmed. Corpus coverage is 48.1%; E019 is 81.3% but **E317 only 27.3%**, so
   three-quarters of that sheet is never drawn by anything. For a frameset editor
   this is the partition that answers "which part of this sheet is live", and the
   mask is a pure function of the framesets.

6. **The viewport states what it cannot show, precisely.** Where the bound frame
   reads a CLUT line or sub-palette the flat export did not decode, the readout
   names both sides — *"this frame reads CLUT line 2 / sub-palette N; the export
   decoded line X"* — rather than a generic "colours approximate" caveat, let
   alone presenting the lie silently. This is exact rather than heuristic because
   `frames.json` carries **`uses_palette_2`** per frame (the CLUT-line select,
   `flags_byte0 & 0x10`, added for #280 and guarded there) alongside `palette_id`:
   399 effects carry it, and 2,496 frames read line 2 against 20,424 on line 1.
   The CLUT swatch strip highlights **every** slot matching the colour
   under the cursor, because for most sheets several match; a single highlighted
   index would be a fabrication. Palette *index* is not offered at all.

7. **The viewport's chrome is a third area of the inspector row**, not an overlay
   and not a strip under the canvas. `_relayout` splits the row three ways — frame
   fields │ texture tools │ canvas — consuming the dead space rather than the
   canvas. The canvas keeps every pixel of `editor_h`.

8. **Pan is clamped per axis and the view is resettable.** `_pan` was previously
   unclamped, so a drag could push the sheet out of the port with no way back
   short of rebinding the effect. The slack is `(available + sheet)/2` per axis,
   and `Home` resets the view.

   > **Amended 2026-08-18, while building ADR-0099.** As first written this
   > decision read: *"Where the sheet is larger than the port on an axis, the port
   > stays inside the sheet; where it is smaller, that axis is centre-locked."*
   > Both halves were wrong once the canvas was actually used at magnification.
   >
   > Slack of `(sheet − available)/2` keeps the **port inside the sheet**, which
   > means no corner of the sheet can ever be brought to the **middle** of the
   > port — exactly where an author zoomed to rung 16 works, and where ADR-0099's
   > region chrome needs room around the box. And centre-locking a letterboxed
   > axis meant a tall sheet in a wide port could not be nudged on `x` at all.
   >
   > The slack is now `(available + sheet)/2` on **both** axes, with no letterbox
   > special case: enough for any texel to reach the port centre. This is more
   > generous than the original intent, and deliberately so — the failure this
   > decision was actually written against was a pan clamped *nowhere*, not a
   > generous one. A bounded pan is always draggable back, which is what "no way
   > back" meant. `reset_view` had been built for this decision and left with no
   > key and no button (a real gap against it); it is now bound to `Home`, which
   > the more generous clamp turns from a convenience into something load-bearing.
   >
   > `_test_pan_is_clamped_per_axis` was rewritten accordingly, and now asserts
   > the property that motivated the change: the sheet's far corner reaches the
   > port centre unclamped at rungs 1, 4 and 16.

## Consequences

- **`EffectStudioFramesetLayoutTest` assertion `[B]` must be deliberately
  rewritten.** It currently asserts the canvas never intersects `_inspector`; with
  a third area between them the invariant becomes an ordered, non-overlapping
  three-way split. `[A]` (never bleeds into the timeline), `[C]` (never occludes a
  transport control) and `[D]` (approximately square) stand unchanged — the canvas
  is still bound by the layout band, never by the bound texture's shape.
- **The default view is the same size as before decision 2, and pixel-exact.**
  Opening at 100% happens to be within 1% of the old raw-fit view for E019
  (0.992 → 1.0) and about half the size for E317 (1.98 → 1.0), which is the real
  price: a sheet the panel could have magnified now opens smaller, and the author
  zooms in. Sheets taller than the port no longer fit on screen at the default
  view. Both are deliberate — see the amendment to decision 2.
- **The swatch strip must compare colours in 5-bit space.** `parse_effect`'s
  palette export bit-replicates (`(v<<3)|(v>>2)`) while the TGA path truncates
  (`v*8`), so the same palette word is 198 in `texture_palette.json` and 192 in
  `texture.tga`. Measured on E019: only **6 of 66** colours match exactly, but
  **66 of 66** match after `>>3`. Naive colour equality would highlight nothing.
- **For 4bpp effects the swatch strip is a different palette than the image.**
  `texture_palette.json` is always palette 1 (`texture_ptr + 0x000`), but
  `extract_effect_texture.lua` decodes a 4bpp sheet from palette 2's first 16
  entries (`+0x200`) — and palette 2 is non-zero in 60/60 4bpp effects while
  palette 1 is in only 38/60. The 4bpp badge therefore has to caveat the swatch
  strip as well as the colours.
- **The 4bpp badge is an admission, not a fix**, and the fix is narrower than it
  looks. A per-frame-region index-plane export would unlock a true index readout
  and region-based authoring over covered, conflict-free regions — but **not**
  4bpp authoring in general: 30 of 60 4bpp sheets have texels read through
  *conflicting* sub-palettes (40,287 texels, 10.3% of covered area), 0 of 60 are
  fully covered, and only 39.4% of texels are referenced by any frame at all. The
  ticket is scoped to what is actually reachable.
- **Opacity is decided in two independent places, and only the narrower one is
  constrained.** *(1)* The **frame's** `semi_trans_on` flag: when it is clear,
  `effect_particle_opaque.gdshader:21` drops its discard threshold from 0.9 to
  0.01, so **every non-black texel of that sprite draws opaque regardless of its
  STP bit**, and no blend pass runs at all — `EffectParticleRenderer.gd:225`
  writes the opaque pass unconditionally and gates the blend pass on the flag at
  `:229`. That flag has been editable since #278 (`FramesetChannel.gd:28,130`).
  **Whole-sprite opacity is therefore already authorable and owes nothing to the
  palette or to #280.** *(2)* The **palette entry's** STP bit, consulted only when
  (1) is set, to route each texel to the opaque or the blend pass.

  So the palette constrains exactly one case: **mixing opaque and blended texels
  inside a single semi-trans-enabled sprite**. Because STP is a property of a CLUT
  entry, two texels sharing an index necessarily share it, and ADR-0097 dec. 1
  holds the CLUT fixed while treating alpha as a matching input, never a written
  bit. `texture_palette.json` bounds that case directly — its fourth field **is**
  the STP bit (`parse_effect.extract_palette` writes `[r8, g8, b8, stp]`):

  | CLUT holds ≥1 STP=0 entry with a non-black colour | effects |
  |---|---|
  | none | **387 of 402 (96.3%)** |
  | exactly one | 14 |
  | more than one | 1 (E365, with 11) |

  (402 palette files = the 401 `E###` effects plus `trap`, which has a CLUT but no
  32bpp sheet — hence 402 palettes against 401 TGAs elsewhere in this ADR.)
  Corroborated independently from the BIN CLUTs by #280 at a different
  denominator: **328 of 338 (97.0%)** across that ticket's in-scope 8bpp sheets.

  E019 and E317 each hold exactly one STP=0 entry and it is index 0 — black, i.e.
  transparent. Read correctly, this says the ROM's sheets are **built** to be
  routed per-sprite rather than per-texel; it is not a limit on what can be
  authored. Whole-sprite opacity is a frame flag; only per-texel *mixing* needs an
  STP=0 CLUT entry, and that alone would need a palette-side edit (clearing bit 15)
  which #280 excludes by design. Either way decision 3 stands unchanged: the
  viewport keeps the opaque texel class because the author is entitled to produce
  one, and it must not be the component that assumes they cannot.
- **The frame already carries more than the viewport uses.** `frames.json` has
  `blend_mode` (corpus: ADD 19,192 / ADD_25 2,641 / SUB 727 / BLEND_50 467) and
  `semi_trans_on` (false on 406 frames, where the STP bit is inert regardless of
  the palette). The readout surfaces both, so "why does STP matter on this frame
  and not that one" is answerable. A true in-game blend *preview* is therefore
  derivable later; it is deliberately not built here.
- **This ADR does not touch the write path.** The writers' choice of 128 as the
  STP marker, the fixed-CLUT index delta, and 4bpp authoring scope all remain
  ADR-0096/0097 and #280's. A viewport that renders each texel class at its own
  opacity is indifferent to whether the marker is 128 or 254.
