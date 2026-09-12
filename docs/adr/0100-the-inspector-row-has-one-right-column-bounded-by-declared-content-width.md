# The inspector row has one right column, bounded by declared content width

## Status

accepted

## Context

The Effect Studio's inspector row is one horizontal band under the transport,
above the frames bar and the channel lanes. Two surfaces want to live beside the
inspector in it:

* the **frameset canvas** (ADR-0098/0099), open on a `frame` target;
* the **sequence player** (#247), open on an `animation` target.

The frameset canvas has been a right-hand column since #278. The sequence player
was built as a column too, in `0306ae37c`, **measured to overlap the inspector by
108px, and reverted to a full-width band under it**. That commit gave two reasons,
and the next reader who finds it will reasonably assume this ADR ignored them.
It did not — both have since expired:

| `0306ae37c`'s objection | what changed |
|---|---|
| "one row per opcode **with a LINK on each** → inspector minimum 1083 of a 1241px body; a Container cannot shrink below its minimum" | those rows are deleted (below) |
| "a film strip is a RIBBON; the frameset canvas wants a SQUARE — sharing a column shapes both like whichever got there first" | the film strip **left the panel** in `de36a115d`; what remains is one assembled sprite, which wants a square, exactly like the frameset canvas |

The measurements, all on the same 1261x688 dashboard (`_body` 1241x507) so they
are comparable to `0306ae37c`'s:

| inspector, sequence target open | E317 | E019 |
|---|---|---|
| combined minimum width, header link rows present | 1068 | 1203 |
| — of which the header `_grid` | 1044 | 1179 |
| — of which `_groups_box` (the sections) | 653 | 653 |
| combined minimum width, link rows deleted | **605** | **623** |
| — of which the header `_grid` | 581 | 599 |
| declared content width (`content_width()`) | **677** | **677** |

The blocker was never the sections. It was a **second, read-only copy of the
opcode list** sitting in the header above the editable one, and it alone was
holding the row open.

> The prior design note asserted that deleting those rows would **not** shrink
> `_grid`, on the reasoning that a `GridContainer`'s minimum follows its COLUMN
> COUNT (`GRID_COLUMNS = 6`), and that reducing the column count was therefore the
> lever. That is wrong, and the measurement above is why the build stopped to take
> it before going any further. A `GridContainer`'s minimum is the **sum of
> per-column maxima**, and an empty column contributes 0; the count only decides
> where cells wrap. `GRID_COLUMNS` is untouched by this ADR.

## Decision

**1. The inspector row has exactly ONE right-hand column slot, with two possible
occupants chosen by target kind.** A `frame` target parks the frameset canvas
there; an `animation` target parks the sequence player. They are mutually
exclusive by construction — `_update_frameset_canvas` and `_update_sequence_canvas`
each show one and hide the other — so the slot is never contended, and `_relayout`
sizes it once against whichever panel occupies it.

> **Amended 2026-08-19 — "when I click on an emitter event I get a very tall pane with
> tons of empty space on the right. I think we need to make use of this space."**
>
> There were two occupants and FOUR target kinds that could be looking at a sequence. The
> two that were left out are the ones an author spends the most time in. Measured on E019
> at a 1187x507 body, before:
>
> | target | inspector rect | `content_width()` | `content_height()` | right column | unused width |
> |---|---|---|---|---|---|
> | `span` (`particle:phase1:0#2`) | 1187 x 268 | 675 | 2257 | **none** | **512** |
> | `emitter` (bare) | 1187 x 268 | 675 | 2027 | **none** | **512** |
> | `animation` (0, group 0) | 450 x 268 | 450 | 1723 | player + focus | 0 |
>
> **The width was unclaimed for want of an ADDRESS, not for want of a reason.** `_relayout`
> picks the column from `_frameset_panel.visible` or `_sequence_panel.visible`, and
> `_update_sequence_canvas` returned early on `kind != "animation"` — so `canvas_w` was 0
> and `editor_w` took the whole body while the rows only ever drew `content_width()` of it.
> An emitter has an address perfectly good enough: `anim_index` is the sequence its
> particles play and `anim_param` is the LENS those FRAME opcodes resolve against. A
> particle `span` reaches the same pair through the emitter it fires.
>
> **So a third kind joins the slot, and the player is its occupant** — chosen by the author
> over three alternatives (docking the curve painter, a two-column section flow, widening
> the colour ribbon). It is the cheapest and, since ADR-0103, the one with the most to say:
> the sprite is tinted by *this* emitter's own colour curves, so the emitter screen shows
> "the particle this emitter spawns, playing, while you edit its physics" rather than a
> generic sprite preview. Provenance rung `origin` by construction.
>
> After, same body, same effect:
>
> | target | inspector rect | declares | right column | unused width |
> |---|---|---|---|---|
> | `span` (`particle:phase1:0#2`) | 903 x 268 | 675 | **276** (seq 7) | **8** (the gutter) |
> | `emitter` 0 | 903 x 268 | 812 | **276** (seq 1) | **8** |
> | `animation` (0, group 0) | 450 x 268 | 450 | 276 + focus | unchanged |
>
> **THE HEIGHT IS DELIBERATELY UNTOUCHED**, and the author was asked. The pane is tall
> because the content is 2257px in a 268px row — `inspector_row_height` hands the row the
> whole budget when nothing floors it, and the timeline is squeezed to `MIN_CHANNELS_H`.
> Halving that scroll means a two-column section flow, which changes what `content_width()`
> means to `_relayout` AND what ADR-0089 dec. 6's per-panel name-column alignment claims.
> That is its own ADR, and the complaint was the width.
>
> **Two residues, both measured rather than assumed.** The row's floor becomes
> `_CANVAS_SIDE + chrome` (374) where it was 0 for these kinds — inert here, because
> `inspector_row_height` maxes it against a `natural_h` of 2000+; it would only bind on a
> target whose fields are shorter than the box, which no emitter has. And the panel's title
> now reads `Sequence N` off the BOUND address rather than a constant, so it bids for
> `_canvas_floor_w`: measured at **89px against the transport row's 202**, i.e. under the
> incumbent widest and costing the column nothing (guarded, `EffectStudioEmitterColumnTest`).
>
> **The bound address is now STORED, not re-derived, and that is the load-bearing half.**
> `_sequence_thumbnail_for` and `_refresh_sequence_preview` both read the open target's
> `ref.index` as an animation index — correct while only an `animation` target could open
> the column, and silently wrong the moment an `emitter` one can, since an emitter ref's
> `index` is an emitter index. `animations[3]` for emitter 3 decodes a real sequence and
> draws real sprites; **nothing on screen says it is the wrong one.** `_update_sequence_canvas`
> stamps `_sequence_bound` and both surfaces read that. The one derivation of the address
> is `EmitterSequenceSubject.resolve`, pure and guarded for the same reason `column_width`
> is: what goes wrong here is invisible, so it has to be assertable off-screen.

> **Amended 2026-08-20 — a THIRD panel stacks in this column: the colour picker**
> (ADR-0089's colour-move amendment). The column's occupants are now the player or the
> frameset canvas (mutually exclusive, unchanged), plus — under the PLAYER only — the
> colour picker and then the ADR-0102 frameset block, stacked in that order.
>
> It is a sibling panel rather than a row inside the player's, and that is the whole
> placement argument. `_canvas_chrome_h` and `_canvas_floor_w` both SKIP INVISIBLE
> CHILDREN, so a picker inside the player panel that hid itself on "no keyframe selected"
> would swing the measured chrome by its own height and re-size the canvas square on every
> click. Laid out explicitly by `_relayout`, it is invisible to that measurement — which is
> also what lets it be conditional at all without breaking dec. 2's constant box.
>
> **It is expensive and the cost is measured, not estimated.** Godot's `ColorPicker`
> reports a hard **298 x 439** combined minimum and returns the same 298 after being
> assigned 200; hiding its sliders and hex field takes 175px off the height and nothing off
> the width. So:
>
> | | before | after |
> |---|---|---|
> | column width under the player | 276 | **314** (bid; the leftover clamp still wins) |
> | column height claimed while authoring | ~448 | **~900** |
> | column height claimed while browsing | ~448 | ~448 (picker hidden) |
>
> **So the picker's HEIGHT is claimed only while a colour keyframe is selected.** The first
> build claimed it permanently and the block stopped appearing entirely — at a 1069px body
> the slack is 327 and a 439px picker left `focus_stack_height` 16px, under its 64px collapse
> floor. That is a new failure mode, not the documented "no slack on a short row", and it is
> what the correction in ADR-0089 dec. 3 is about. `picker_panel_h` / `picker_panel_w` are
> ADR-0068 static vars so the numbers move without a rebuild.
>
> **The WIDTH bid stays unconditional**, and the asymmetry is deliberate: `column_width`
> feeds the canvas square, so bidding on a selection would make the box a function of
> whether a keyframe is selected — dec. 2's amendment made that box a constant precisely to
> stop it. A sibling panel's height can come and go without the square hearing about it
> (asserted, `EffectStudioColourColumnTest`); its width cannot.
>
> The picker is bid and shown for the SEQUENCE occupant only. A `frame` target parks the
> frameset canvas here and there is no particle, no life axis and nothing to colour, so a
> 439px picker under it would be offering to author something that is not on screen.

**2. The column's width is `column_width(row_w, canvas_h, content_w)`, a pure
static.** Square by construction (the row's height is the binding dimension, being
capped by the timeline below), capped at half the row so the content column beside
it never collapses, and then — the load-bearing term — **clamped to
`row_w - content_w - gutter`**. Overlap is thereby *unrepresentable* rather than an
empirical question re-answered by each layout test.

It is pure because the invariant has to be testable at sizes where the terms
actually contend, and the developer's dashboard is not one: there the square wants
218 against 556px of room, so a broken clamp measures perfectly clean. The guard
sweeps 120 row/content/height combinations
(`EffectStudioFramesetLayoutTest` [E]).

> **Amended 2026-08-19 — "the animation box is changing in size all the time as clicking
> through keyframes. It should have fixed dimensions."** It was, by construction, and this
> decision is where. The canvas is square off the ROW's height and the row's height was
> `clampf(content_height(), 0, budget)` — so the box was a function of whatever target
> happened to be open. Worse, of its FOLD STATE: `content_height()` reads a container
> minimum and Godot's container minimums skip invisible children (decision 3 says so, one
> axis over), so opening a single section grew the row and with it the box. On a frame
> target at a 661px budget, 400px of fields make a 311px box and one fold makes it 411.
>
> **The first fix kept the derivation and changed its term, and that was wrong.** The row
> took the whole `budget` — a function of the window alone — so the box stopped resizing per
> click. On a TALL window it then grew to half the row, took every pixel of the width the
> ADR-0102 focus column is claimed from, and the author photographed a sequence page with no
> block on it at all. A derivation with a moving term is precisely what the requirement was
> refusing; a better term is not a fix.
>
> **So the box is a CONSTANT.** `_CANVAS_SIDE` (260) is the canvas's square side whatever
> the window does, and the panel around it is that plus its own measured chrome. The row is
> FLOORED at the box and otherwise still fits its content, capped by `budget` — so a tall
> window hands its surplus back to the timeline rather than to the sprite preview, and an
> emitter with four rows still does not push the lanes off the bottom.
>
> 260 is the largest side that leaves the three-column row working at the narrow end: at a
> 1205px body it is 677 (the strip's declared width) + 276 (the box plus 16 of panel chrome)
> + 16 of gutters, leaving 236 for the focus column. Raise it and the block is what pays.
>
> Two residues, stated rather than hidden. The chrome is MEASURED per occupant (the sequence
> panel's transport is 88px, the frameset panel's readout and scope 105), so the two panels
> differ by 17px in height — they are never on screen together and each is constant for its
> own screen, and the canvas inside them is the same square. And on a window too short to
> hold the box whole the panel is clamped back to the row, which is unavoidable: a container
> cannot be given more height than the band above the timeline has.
>
> The rule is extracted as
> `inspector_row_height(natural_h, budget, panel_h, column_floor_h)`, pure, for exactly the
> reason `column_width` is: at the dev body the budget is 268 against 1723 of content, so
> every variant agrees and a live measurement sees nothing
> (`EffectStudioFramesetLayoutTest` [G], which now guards BOTH failures — the row must not
> read content height for the box, and must not take the whole budget either).
>
> **A third claim joined the row the same day** (ADR-0102's second amendment): the frameset
> focus block took a column of its own between the inspector and the player. Its width is
> `focus_column_width(row_w, strip_w, player_w)` — the row's SLACK, claimed only after both
> neighbours have what they cannot give up, because a Container cannot shrink below its
> minimum and width taken from either of them overflows onto this column instead. Guard
> [F], same file, same reason it is static.

> **Amended again 2026-08-19 — "I think we can fit the thumbnails under the sequence which
> is playing."** The panel gains a FILM STRIP: one thumbnail per opcode, under the Colour
> ribbon and directly above the transport it is the visual twin of (⏮ op / op ⏭ step through
> the same opcodes a cell click parks on).
>
> It does **not** re-open decision 4's question. The strip that left this panel in `de36a115d`
> was the *only* view of the sequence and took the whole width as a 1225x62 letterbox; this
> one is 34px cells in the 276px column, and on an `emitter` or `span` target — where the
> inspector renders the emitter's physics and has no opcode rows at all — it is the only
> opcode picker there is. That target kind did not exist when decision 4 was written.
>
> **It WRAPS rather than scrolling sideways** (author, same session: *"can we have the
> keyframes just wrap if they go to the end of the frame?"*). One line of 34px cells shows 7
> of E019's 35 opcodes and hides 28 behind a horizontal bar; wrapped into a flow it is a
> contact sheet of the whole particle life — measured, 35 cells over 5 rows of 7 — and the
> same height budget shows two or three times as many. **The row count is a constant**
> (`strip_rows`, default 2, an ADR-0068 static var), never fitted to the sequence: a strip
> that grew to five rows for a 35-opcode sequence and one for a 4-opcode one would swing the
> measured chrome on every browse. Overflow scrolls VERTICALLY, and the parked cell's ROW is
> scrolled into view on every bind and every `selection_changed`.
>
> > The first cut reserved 12px of slot height for a scrollbar. The bar is **vertical** — it
> > costs width, not height — and all that 12px bought was a half-clipped third row peeking
> > under the second, which reads as a layout bug. The slot is exactly `strip_rows` cells now.
>
> Its **slot is RESERVED with a declared height**, for the third time in this panel and for the same reason:
> `_canvas_chrome_h` and `_canvas_floor_w` skip invisible children, so a strip that hid on a
> short sequence — or a scrollbar that appeared only on a long one — would swing the measured
> chrome as the author browsed and re-size the canvas square under them. A plain
> (non-Container) wrapper declares the height once and does not propagate the row's 1258px
> minimum into the column's width bid.
>
> **The cost is the player's height, and it is real.** Chrome goes **114 → 188** at the
> default two rows, so the panel's floor goes 374 → 448 and on a window too short to hold
> that the canvas pays the whole 74px: at a 1241x507 body the canvas measured **100px**
> against 174 with no strip at all. Each extra row of `strip_rows` is another 36px off the
> player. On a tall window nothing contends. This is the first thing in the panel that
> makes the short-window clamp materially worse, and if it bites, the lever is
> `_SEQUENCE_STRIP_H` or hiding the strip below a threshold — the latter costing exactly the
> chrome-swing this ADR keeps paying to avoid.
>
> Guards: `EffectStudioSequenceViewportTest` [film_strip] — one cell per opcode, the declared
> slot height, chrome unchanged across sequences of different lengths, the parked cell
> scrolled into view, and a cell click parking the player.

> **Amended again 2026-08-19 — "shift the right panel with the sequence animation to the
> right and then fit the frameset controls underneath it", then "I thought the plan was to
> put them on this screen…because we had space".** The row has TWO columns now, not three.
>
> The ADR-0102 frameset block was the MIDDLE column, claiming the row's leftover WIDTH
> (`focus_column_width`). It is now STACKED under the player inside the player's own column,
> bounded by that column's leftover HEIGHT (`focus_stack_height`) — the same rule turned
> ninety degrees, with the same "take the slack, never encroach on the neighbour that cannot
> give" ordering. Measured on E019 at an 830px row: strip **450 → 1988**, player 276x448 at
> the row's top, block 276x374 directly beneath it. The width the block used to hold goes
> back to the inspector, which is the point.
>
> **The slack comes from the COLUMN, never from the player.** A rule that shrank the box to
> make room would make it a function of whether the open target happens to carry a block —
> exactly the "the animation box is changing in size all the time as clicking through
> keyframes" complaint that made the box a constant in dec. 2's amendment.
>
> **And the block follows the PLAYER, not the open target.** It was gated on
> `kind == "animation"` — identical while only an animation target could bind the player, and
> wrong the moment an `emitter` or particle `span` can, which is the screen the author is
> actually in. It is fed `_sequence_bound`, never the target's `ref`:
> `SequenceFocusBlock.section` reads `ref.index` as an animation index and `ref.group` as the
> frameset lens, and on an emitter target `ref.index` is an emitter index — so fed the target
> it would name and EDIT a real frameset from an unrelated sequence, silently. Third surface
> to need this stamp, after the thumbnails and the in-place refresh.
>
> **A short row drops the block, and that is a real consequence.** `box_shown_h` clamps to the
> row, so on a 268px row the box fills it and there is no slack at any chrome — dropping the
> film strip does NOT buy it back. The block needs roughly a 510px row (about an 840px body).
> Below that the page keeps `_focus_wanted` set, so it returns when the window does.
>
> Guards: `EffectStudioFramesetLayoutTest` [F] rewritten for the stacked rule (112
> combinations, box never encroached), `EffectStudioEmitterColumnTest` [frameset_stack] for
> the emitter screen, and `EffectStudioUnifiedAnimationAcceptanceTest` for the animation one —
> both skipping with the numbers on a row too short to express it.

> **Amended once more 2026-08-19 — "the left side of the panel which contains the player
> needs to come left so that we don't need to horizontal scroll there."** The column has two
> occupants with different width appetites now, and it was sized for only one of them.
>
> The player's box wants **276** (`_CANVAS_SIDE` + chrome). The stacked frameset block
> declares **710** — eight vertex spinboxes, a sheet-region link and a shared-UV warning — so
> at a 276 column it scrolled sideways by **434px**. The column takes the LARGER appetite now,
> still clamped by what the inspector declares, which is the same leftover rule that has
> always kept it off the strip: at a 1241px body the column is **527** and the inspector still
> gets exactly its declared 706, so no scrollbar is traded for another. Where the body is wide
> enough the block gets all 710 and the deficit is 0.
>
> **The box stays a CONSTANT SQUARE inside the wider column**, which is dec. 2's amendment in
> the one direction this could have broken it. Sizing the canvas to the column would make the
> player's width a function of whether the open target happens to carry a block — the exact
> "the animation box is changing in size all the time as clicking through keyframes" failure
> that made it a constant. The canvas is capped at `_CANVAS_SIDE` and set `SHRINK_CENTER`, so
> only the block below spends the surplus.
>
> **The residue is the block's own width, not the row's.** 706 + 710 + a gutter is 1424
> against a 1241px body, so the block still gives up ~213px there. The next lever is not this
> clamp — it is what the two panels DECLARE. The inspector's 706 is dominated by the emitter
> provenance header (14 `Death-child of emitter N` rows across a six-column grid) while its
> editable param rows use under half the width; that is the same shape as dec. 4's finding,
> where "the blocker was never the sections, it was a second read-only copy of the opcode list
> holding the row open."

**3. The bound is `EffectKeyframeInspector.content_width()` — a DECLARED width
recorded at build — not the live `get_combined_minimum_size().x`.** A collapsed
section's body is `visible = false`, and Godot's container minimum **skips
invisible children**: on the sequence view the live minimum is 311 with the
sections shut and 653 with them open. Capping a column on that would resize the
player every time an author opened a section. `content_width()` is taken once at
the end of `show_target`, over every body at both accordion levels whether shown or
not, plus the panel's own measured overhead (the stylebox margins *and* the
ScrollContainer's reserved scrollbar — forgetting the latter put the first draft
8px **under** the live minimum, i.e. under-reporting, the one thing this number may
never do).

This is the exact peer of `content_height()`, which exists for the same reason one
axis over: a ScrollContainer hides vertical growth from min-size.

**4. The header's per-opcode LINK rows are deleted.** They duplicated the section
list below them, which is the editable one. Nothing they showed is lost: the
section title is now the full `SequenceProjector.opcode_label`
(`"1: FRAME fs=3 dur=8 depth=1"`, the Lua sequences tab's instruction label
verbatim in form), and the thumbnail moved onto the section's title row.

**5. Opcode sections default COLLAPSED, and the thumbnail rides the TITLE row so a
shut section still shows it.** A column of shut sections therefore reads top to
bottom as the sequence's film strip. Section fold state is remembered for the
session under a projector-supplied `fold_id` — `"seq:<anim>:<opcode>"`, keyed by
position rather than title, because an edit to `duration` rewrites the title and a
key that moved with the value would shut the section being typed into.

**6. A section-level Expand all / Collapse all sits above the list, for ANY target
with more than one section** — not sequence-gated. A fifteen-section emitter is as
tedious to shut by hand as a thirty-six-opcode sequence, and it is the same act one
level up from the per-section param-fold control (ADR-0089).

**7. `sequence_op` navigation is dropped from the UI.** The kind stays valid — the
registry, the projector and their tests are untouched — but nothing produces it.
*(Superseded 2026-08-19: the kind itself is now **deleted**. See the consequence
below.)*
`_opcode_sections()` returns *exactly* the section the animation view already
renders inline, so drilling in showed strictly less than staying; its one unique
effect was `select_op()`, and **clicking a thumbnail now parks the player
directly**, without the inspector rebuild a navigation costs. That rebuild is how
an author loses the folds and the scroll position they just set up.

**8. The sequence player carries its own transport: a speed field (0.1–4.00x,
default 1.00x) and prev/next-opcode step buttons. No tick-level scrubber.**
`SequenceTimeline.trace` is one cell per opcode and the image is constant across
that cell's whole `ticks` dwell, so there is no sub-opcode visual state to scrub
to — a scrubber would slide through eight ticks of an identical picture. "Pick a
frame" and "pick an opcode" are the same act here, and decision 7's click already
makes it. What was actually missing is **pace**: at `TRANSPORT_HZ = 30` a six-tick
sequence loops five times a second.

The rate is the PLAYER's, page-session state (like Ripple and Hide inert), and
deliberately **not** the page transport's `_speed_value`. `SequenceCanvas` already
argues why the two clocks are separate — a sequence is a reusable asset played by
whichever particle references it, not a position on the effect timeline — and the
same reasoning covers their speeds.

**9. `_SEQ_BAND_WANT`, `_SEQ_BAND_MAX_SHARE` and the whole band branch are
deleted.** The FEDS pair lane panel is the only remaining full-width band under the
inspector row.

## Consequences

- **The player is a ~200px square instead of a 1225x62 letterbox** at the
  developer's dashboard, and on a short sequence (E317, 4 opcodes) the timeline
  gets the band's 150px back outright. On a long one (E019, 36 opcodes) the
  inspector absorbs that height instead and shows four opcode sections where it
  showed two — the budget that keeps `MIN_CHANNELS_H` of lanes below the ruler is
  unchanged either way, so the timeline can never be starved by this.
- **The column is bounded by the SQUARE, not by the room**, at any usual window
  size: 218 wanted against 556 available. Widening the dashboard makes the row
  taller only via the timeline budget, so the player grows with the row, not with
  the window. If a bigger preview is ever wanted, the lever is the row's height
  cap, not this clamp.
- **`_canvas_chrome_h(canvas)` is now load-bearing for two panels.** The frameset
  panel stacks a hover readout and the region scope under its canvas (105px
  measured); the sequence panel stacks a transport row (88px). A shared constant
  would make one of them un-square — which is exactly the failure that retired the
  constant this function replaced.
- **Section fold state is keyed per (sequence, opcode) and not per effect**, so
  opening opcode 0 of sequence 1 in one effect leaves the same-numbered section
  open in the next effect loaded. This matches `_fold_state`'s existing behaviour
  for param folds (keyed emitter:group, likewise effect-blind) and is accepted for
  consistency rather than defended as ideal.
- **An effect with no `frames.json` still gets the column.** E509/E510 reference up
  to 14 framesets without one; the trace, the tick readout and the transport are
  all real even when no cell has a sprite. No special case is written.
- **`sequence_op` is now dead UI surface with live code.** It is kept because the
  target kind is part of ADR-0073's provenance model and a link may want to point
  at one opcode again; `EffectStudioSequenceEditTest` still exercises it end to end
  through the projector. If it is still unreachable a year from now, delete it —
  do not re-add a link row to justify it.
  > **Deleted 2026-08-19**, three weeks rather than a year, because ADR-0102 removed
  > the last thing drilling into one opcode still bought: the unified block now
  > retargets the frameset's own rows when the player parks, so a focused opcode shows
  > strictly less than the sequence view in every respect. Gone with it: the registry
  > entry, `SequenceProjector._opcode_header` / `_opcode_sections`, the
  > `_update_sequence_canvas` kind branch and its `select_op` special case, and the
  > `ref.get("index", ref.get("animation_index", -1))` dual reads that existed only to
  > serve two ref shapes. Its tests are deleted rather than rewritten — a test for a
  > kind nothing can produce measures nothing. **The standing instruction survives the
  > deletion**: if a future feature needs to address one instruction, mint the kind
  > again; do not re-add an opcode LINK ROW to justify it. Those rows are what held the
  > inspector at 1068px of a 1241px body and cost the player its column the first time.
> **Amended 2026-08-19, on the user's first real use.** An opcode edit did not reach
> the player. `SequenceTimeline.trace` **flattens the opcode stream once at bind**, and a
> `sequence` channel edit returns only `invalidates_sim` — which re-folds the particle
> preview but takes no `_apply_edit` branch that re-binds the studio's own player. Change
> a duration from 2 to 10, or point a FRAME at another frameset, and the animation, its
> thumbnails and its labels all kept the old values.
>
> The fix is an **in-place re-decode**, deliberately not `_render_current()`: every
> inspector edit arrives with `defer_refold` false (only a timeline edge drag defers), so
> a full render would `queue_free` the ScrubField being dragged and the drag would die
> after one pixel — the same reason the plain-value branch does not render.
>
> Four surfaces were stale, in four places, and the split follows who owns each:
> `SequenceCanvas.refresh_sequence()` re-decodes and keeps the transport where it is (the
> playhead, the park and play/pause all survive — an author lengthening a frame while
> watching the loop is not asking to be sent back to tick 0); each **thumbnail re-pulls
> its own cell** off a new `decode_changed` signal, so there is still no host-held list of
> them to go stale (decision 7's reasoning one layer down); and the inspector grew
> `refresh_section_titles` / `refresh_header_values` / `refresh_follows`, which rewrite
> text and destinations into the existing widgets and rebuild nothing.
>
> `refresh_follows` fixes a **pre-existing** defect this made visible: a `follow` is
> derived from the editor beside it (`frameset + group offset`) and captured its target by
> value, so after retargeting an opcode to frameset 3 the button beside it still opened
> frameset 1 — a wrong destination, not merely a wrong label. The destination now lives in
> a mutable cell the lambda closes over.

- **The reel is not auto-scrolled** to follow the playhead. The list stays where
  the author put it; the white playhead mark tells them where the player is
  without moving the surface they are reading.
