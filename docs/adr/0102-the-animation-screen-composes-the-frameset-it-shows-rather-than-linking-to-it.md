# The animation screen composes the frameset it shows, rather than linking to it

## Status

accepted

## Context

Authoring one sprite of one effect animation is three screens deep. ADR-0100 put
the sequence player beside the inspector and turned the opcode list into a film
strip you can read top to bottom — but a FRAME opcode still only *names* the
frameset it shows. To change the sprite's palette, its blend, or where its quad
sits, the author drills `sequence → frameset → frame`, edits, and drills back,
losing the sequence player and the strip's scroll position both ways. The most
common authoring loop in the studio crosses two navigation boundaries.

Two placements were offered for fixing that: promote the frameset's fields to a
collapsible at the ROOT of the sequence view, or give every opcode its own
collapsible carrying its frameset. Both were built against the real inspector and
timed, headful, on E019 sequence 0 (36 opcodes), same 1261x688 dashboard as
ADR-0100's numbers:

| shape | fields | folds | **build** | nodes | `content_width()` |
|---|---|---|---|---|---|
| the sequence view as it ships | 105 | 0 | **343 ms** | 686 | 677 |
| **root block, follows the selected opcode** | 155 | 2 | **400-428 ms** | 852 | 677 |
| per-opcode fold, headers only (a lazy floor) | 157 | 52 | 558 ms | 1014 | 677 |
| per-opcode fold, trimmed field set | 521 | 52 | 963 ms | 2262 | 677 |
| per-opcode fold, full field set | 1437 | 86 | **1867 ms** | 5028 | 677 |

**Per-opcode folds cost a second and a half of rebuild. The root block costs
60-85 ms.** Trimming the field set does not rescue that shape (963 ms), and
neither does building fold bodies lazily (558 ms floor): the cost is ~4 ms per
fold HEADER, 52 of them, before a single row exists. The two hazards that were
expected to decide this turned out to be non-issues — `content_width()` measures
**677 in every variant** (a frame's rows, 457 as a root, are narrower than the
sequence header already is), so the graft costs the player beside it exactly zero
width; and `content_height()` barely moved either, since folds started shut. (The
amendment under decision 2 opens the FIRST frame fold, which takes E019's sequence 0
from 2017px to 2452px of content — immaterial, because the row is capped at ~268px by
the budget and was already scrolling internally an order of magnitude before that.)

Two mechanisms had to be checked before any of it was worth building:

* **A grafted row's `field_ref` is absolute.** It is
  `{channel:"frameset", frameset_index, frame_index, field}`, and
  `EffectEditSession.apply_edit` routes on `field_ref.channel` alone, never on the
  open target. Verified: 832 grafted rows kept their ref intact, and a grafted row
  edits the right frame from anywhere.
* **The inspector has exactly two accordion levels** (section → fold). A fold is
  minted by stamping a field with `group = {id, label, summary}`, and `_fold_key`
  is `"%d:%s" % [emitter_index (default -1), id]`, so a non-emitter id like
  `"fr:11:0"` works. There is no third level; the design fits in two.

## Decision

**1. The unified screen is COMPOSITION, not a fourth projector.** The block calls
`FramesetProjector.sections()` and grafts the rows it returns. The registry
(ADR-0073) exists so a field is declared once; restating a frame's fields in a
second projector would mean two declarations to keep in step, and the absolute
`field_ref` is precisely what makes restating unnecessary.

**2. ONE pinned block at the top of the section list, following the selected
opcode** — the user's first option, and the measurement above is why. It carries
the frameset's own rows and one fold per member frame.

> **Amended 2026-08-19, on the user's first real use — the block was there and showed
> nothing.** The inspector row is ~268px tall against 2000+px of content, so the block's
> first four or five rows ARE the feature. Leading with the frameset's own rows (pin,
> Header flags, Sheet, Export, Import) spent that entire height on chrome: the folds
> carrying the parameters this screen exists to expose were below the cut AND shut, so the
> user navigated correctly and saw a header.
>
> It was worse for the COMMON case than the rare one, and the number was already in this
> ADR: **13,854 corpus framesets hold a single frame**, so "frame folds default shut" meant
> that for most framesets the block showed no frame at all. The measurement was recorded
> and the decision it contradicted was shipped anyway.
>
> So: **the frames LEAD, and the first fold opens.** The frameset's own rows move below
> them — the sheet round trip is a convenience reachable by a scroll; the frames are why
> the screen was opened. Folds had no way to ask to open, so `_make_fold` grew an
> `expanded` stamp hint, the exact peer of a section's existing `collapsed` hint, with the
> session fold state still winning wherever the author has touched that fold. It costs no
> build time — a fold body is built either way, only `visible` differs.
>
> The acceptance test asserted "first section, open" on RECTANGLES and passed throughout.
> Rects passing is not the same as the screen being useful; the guard now asserts the
> ORDER (frames before frameset rows) and that exactly the first fold asks to open.

> **Amended again 2026-08-19, on the user's second real use — "the thumbnails should not
> be moving as you click other things."** They were, and the mechanism is this decision's
> word *section*. A section sits in the same `VBoxContainer` as the 36 opcode sections
> below it, so its height is theirs: a two-member frameset is one whole fold taller than a
> one-member one, and **every thumbnail below the block slid 39px** each time the author
> clicked between them (E019 sequence 0, measured). The screen's own navigation moved under
> the hand that was using it.
>
> **The block leaves the section list for a COLUMN of its own** — a second
> `EffectKeyframeInspector` in a panel `_relayout` positions between the film strip and the
> player. Same measurement after: 0.0px. A block that cannot reach the strip's container
> cannot move it, and no arrangement inside that container can promise the same: a
> fixed-height section still moves everything when it is SHOWN or HIDDEN, which is what a
> spriteless opcode does (see decision 4).
>
> **A column, not a band, and both were built and photographed** at the dev body (a 268px
> row, 1241px wide). Stacked, the two halves get 131px each — and the strip spends ~100 of
> its 131 on chrome it cannot drop (its title, the "Plays for N ticks" header row, the
> Expand/Collapse bulk row), so it showed **one opcode** and the block **one parameter
> row**. Side by side, both take the row's full 268px: the strip shows ~3 thumbnails and
> the block ~5 rows.
>
> The column is the row's SLACK, claimed after both neighbours, and the ordering is forced
> rather than chosen: a Container cannot shrink below its combined minimum, so width taken
> from the strip's declared `content_width()` (677) or the player's own chrome floor (202)
> does not narrow either — it overflows onto this column. Taking the block's width off the
> row before the player's floor was applied put the sequence panel **9px past the body's
> right edge at a 1187px body**, mid-build. Below 120px of slack the column is dropped
> entirely rather than drawn as a stripe, so "the target has a block" (`_focus_wanted`) is
> now a different question from "there is room for it" (`_focus_panel.visible`).
>
> **The strip pays for the block's width, so the strip was made to cost less.** The column
> is the row's slack past `content_width()`, so every wasted pixel in the strip is a pixel
> the block does not get — and the strip was declaring 677 of which most was waste. Three
> cuts, measured: the name column (240px of house width, sized for "Position · at start",
> against a longest name of "Depth mode"); the header's run length ("N ticks before the
> terminator" — 223px, the widest cell in a 581px header grid); and LOOP's parameter row
> ("none — restarts the sequence from the beginning" — 385px, the widest cell in the whole
> view, restating what LOOP means). Both sentences moved to tooltips, which is what a
> tooltip is for. **677 → 432**, and the block went from scrolling sideways to showing every
> value.
>
> Two seams on the inspector, both because a second instance is not the first:
> `show_own_chrome` (a panel inside a panel needs no second target title and no blank header
> grid) and `allow_horizontal_scroll` with a per-panel `name_column_width` — 240px of names
> (ADR-0089 dec. 6) in a 334px column puts every VALUE off the right edge, so the focus
> panel uses 132. Dec. 6's alignment is claimed *within* a panel, and these are two panels.

**3. It follows `SequenceCanvas.selection_changed(op_index)`, and retargets
through `EffectKeyframeInspector.rebuild_section(fold_id, spec)` — never
`_render_current()`.** A thumbnail click already PARKS the player rather than
navigating (ADR-0100 dec. 7), so nothing about clicking the strip should rebuild
the panel: a full render `queue_free`s every widget, taking the folds the author
opened, the scroll position, and — for an edit rather than a click — the
ScrubField being dragged, which is how a drag dies after one pixel (`87c081b7b`).
`rebuild_section` replaces one child of `_groups_box` in its own slot and scrubs
the removed subtree from the widget registries by identity (`queue_free` does not
invalidate until end of frame, so a validity sweep would keep every stale node).
**The signal survives; `rebuild_section` does not** — see the amendment below and the
consequence at the end.

**4. The block is emitted even for an opcode that shows no frameset**
(SET_OFFSET, ADD_OFFSET, LOOP, an out-of-range index). It says so in a const row
rather than vanishing. This is not politeness: `rebuild_section` can only retarget
a section that is THERE, so a disappearing block would force the very full render
decision 3 exists to avoid — and it would re-flow the whole list on every click
through the strip.

> **Amended 2026-08-19: still always emitted, now as a TITLE AND NOTHING ELSE.** The user
> asked the obvious question — "should there even be a frameset section since set_offset and
> loop have no frameset parameter?" — and the honest answer after the amendment above is
> that there is no *section* any more. The panel's slot states which instruction the strip
> is parked on ("Opcode 0 · SET_OFFSET — no frameset") and stops. The two-column const row
> it replaces ("Frameset │ LOOP shows no sprite — click a FRAME cell in the strip") spent a
> label column on noise and a sentence on instructions for a strip the author was already
> clicking.
>
> **The slot stays RESERVED rather than collapsing**, and that half is load-bearing for the
> amendment above: the panel is a column beside the strip, so a panel that vanished would
> hand its width back and re-flow the strip — the exact movement the column exists to stop,
> just on a different click. The original reason for always emitting (that `rebuild_section`
> can only retarget a section already in the list) expired when the block left the list.

**5. The group lens is resolved through ONE derivation,
`SequenceProjector.absolute_frameset(relative, group, effect_data)`,** shared with
the follow button beside the opcode's own Frameset editor. A FRAME opcode's stored
frameset is RELATIVE to the frameset group (ADR-0073 dec. 8), so two copies of
that sum could drift and the block would silently edit a different frameset from
the one the button beside it opens. Mutation-tested: the same opcode read through
group 1 must move the block AND every one of its `field_ref`s to the shifted
frameset.

**6. UV rows are READ-ONLY in the block** (ADR-0099). A UV rect is a shared sheet
region — E019's 184 frames sit on 14 distinct rects, the biggest shared by 30
frames — and the safety against editing thirty frames believing you edited one is
the region SCOPE control, which lives under the frameset canvas. That canvas
cannot be on screen here: the inspector row's right column is ONE slot and the
sequence player is in it (ADR-0100 dec. 1). So the block states the rect, states
the fan-out, and links to the frame's own screen, where the picture and the scope
both exist. **Everything else on a frame is strictly per-frame with no fan-out** —
palette, blend, semi-trans, 8bpp, all eight vertices — and is grafted verbatim and
editable inline.

**7. A `frameset`-channel edit refreshes the sequence player.**
`SequenceCanvas._decode` computes the player's shared `_bounds` box from the
FRAMESETS, so a vertex edit made from this screen moves the box every thumbnail
and the assembled sprite are drawn in. `FramesetChannel` returns
`invalidates_sim: false` (frames are read live by the renderer), so before this
branch existed the edit reached the effect and refreshed **nothing at all**. Same
staleness as ADR-0100's amendment, same fix, same function.

**8. ~~The pin is a transient VIEW choice, not a byte.~~ WITHDRAWN 2026-08-19** — "I don't
think we even need the 'pin' button", on first real use. It was in the mockup and never in
the approved build list. What made it worth deleting rather than shrinking is the shape of
the row it cost: an `action` renders through the same two-column grid as every other row,
so the toggle spent a label column reading "Following" and a full row at the very TOP of a
block whose first screenful is the entire point — against a
compare-against-a-moving-playhead case that never came up. Deleting it took `PIN_ACTION`,
the `seq_focus_pin` branch of `_run_action`, `_set_sequence_focus_pin`, `_seq_focus_pin`,
the `pinned` parameter (three call sites) and `_sequence_bound_anim`, page state that
existed only to drop the pin on a re-bind.

**9. THE FILM STRIP IS A ROW OF TIME POSITIONS, so its first and last cells are the
animation's first and last FRAME.** Added 2026-08-20, on the author's proposal, and it
REVERSES a decision the same author locked on 2026-08-18.

The strip has one cell per opcode. Every corpus animation opens with a `SET_OFFSET`
(2,428 of 2,428, and the first `FRAME` is opcode 1 in every one of them) and 2,377 of
them close with a `LOOP`, so the first and last cells are opcodes that hold no sprite of
their own. Under the old model — *a cell is the animator state AFTER its opcode runs* —
the first cell drew an empty box with a crosshair, on the stated grounds that "a cell is
a state readout and inventing a sprite there would make it lie."

**The fencepost is the complaint.** N stretches of time have N+1 boundaries, and the
strip exposed only the interior ones: in the author's words, *"we can only keyframe in
the inter-opcode durations — never the start or end."* So:

| cell | stands for |
|---|---|
| the FIRST | the animation at **t=0** — its first frame |
| an interior one | the **END** of that opcode's duration |
| the LAST | the animation at **its end** — its last frame |

**The 2026-08-18 rationale does not carry over, because the PURPOSE changed.** A cell is
no longer a readout of one opcode's state; it is a position on the animation's clock. The
picture at t=0 is not invented — it is what the game puts on screen at t=0 — so the cells
before the first `FRAME` ADOPT that frame's whole state, offset included. Recording that
plainly is the point of this decision: the old reasoning was sound for the old question,
and a quiet contradiction would leave the next reader with two live rules.

**One expression, no special cases.** `pos_tick` is `tick_start + ticks - 1` for a cell
that occupies time and `maxi(0, tick_start - 1)` for one that does not. Three consequences
fall out of that single rule rather than being coded for:

* the leading `SET_OFFSET` lands on 0 (`maxi` floors -1) and the trailing `LOOP` on
  `total_ticks - 1`;
* the **51 animations with no trailing `LOOP`** (50 end `FRAME,FRAME`, one ends
  `ADD_OFFSET,FRAME`) need nothing added — that last `FRAME`'s end-of-duration already IS
  the animation's end;
* every position is inside `[0, total_ticks - 1]` and the sequence is monotone down the
  strip, so **a park can never seek off the end**.

**`tick_start`/`ticks` did not move.** They remain the DWELL — the per-opcode view of
`ParticleAnimator._bake_animations` — and `total_ticks` still equals that bake's array
length. `pos_tick` is a second reading of the same numbers, not a rival clock. Corpus
sweep over all 401 effects / 2,428 animations after the change: **0 bake-parity
mismatches, 0 out-of-range or non-monotone positions, and the shared `bounds` box
byte-identical to the old model's** — adoption duplicates a state already in the union,
so the coordinate box every cell draws through cannot move.

**A click parks at `pos_tick`, not at `tick_start`** (the author's call on the open
question). A cell that advertises a position it cannot seek to is the fencepost bug
again, one level up. For the 83.6% of cells that dwell a single tick the two numbers are
the same and nothing visibly moves; over the corpus **4,236 rows actually change where
they park**.

**The tail slot stays a distinct, selectable cell** (also the author's call). Measured:
the trailing `LOOP`'s position equals the last `FRAME`'s end in **all 2,377** animations
that have one — not only in E317 anim 5 where it was first noticed. The two cells
therefore always show the same picture. That is the model working, not a collision to
hide: the last frame's end IS the animation's end, and the row that says so is the one
the author asked for.

## Consequences

- **The colour hole closes as a side effect, and it was the supporting evidence.**
  `SequenceCellColour.cell_color` returned the identity white for any cell with
  `ticks <= 0`, and `SET_OFFSET`/`LOOP` both carry `ticks == 0` — so the first and last
  thumbnail of **every** corpus strip were untinted BY CONSTRUCTION ("the strip has more
  rows than ages"). Giving those slots real positions gives them real ages: **4,805 spare
  end cells** across the corpus gained a picture and a colour. ADR-0103 dec. 2 is amended
  there rather than here.
- **Every row now owns a colour piece, including the 908 mid-stream offset opcodes** (in
  86 animations). That is not a second decision, it is the same rule: a row that occupies
  no time stands for the boundary it sits on and draws that tick's colour, with
  `cut_ticks == 1`. Special-casing only the two ends would have made "the strip is a row
  of time positions" false in the middle, and would have put a branch back into
  `cell_color` that dec. 2 spent its argument removing.
- **The cut window is pinned to the position**: `cut_start + cut_ticks - 1 == pos_tick`
  for every row, which is the whole model in one assertable line. ADR-0103's per-cell
  loop is otherwise untouched — a `FRAME`'s window still OPENS at its dwell, so a long
  hold still ramps through its own ages while the player is stopped (the author's call on
  the third open question). Only where the row is ADDRESSED moved.
- **The crosshair is now unreachable in practice.** A spriteless cell requires an
  animation with no `FRAME` at all — none in the corpus — and such an animation has an
  empty `bounds` box, where `SequenceSpritePainter.fit` returns scale 0 and nothing draws,
  crosshair included. The code is left in place rather than deleted on a guess; it is
  flagged here so it is not mistaken for live behaviour.
- **A ROW IS LABELLED BY ITS OPCODE, and that is deliberate** — settled with the author
  2026-08-20, the same day, on the question this bullet used to leave open. Row 0 reads
  `0: SET_OFFSET x=0 y=0` beside a picture of the animation's first frame, and that is
  the right pair: a row is an OPCODE (it selects one, it edits one, `fold_id` is
  `seq:anim:op`) whose thumbnail shows a time position. Relabelling the two end rows
  would have made the strip disagree with the Lua editor's instruction list, which
  `SequenceProjector.opcode_label` exists to match verbatim, and would have put a name on
  a row that no longer matched the parameters underneath it. The tooltip carries the
  reconciliation instead ("Click to park the player at tick N") — this ADR's own
  precedent for a sentence that would otherwise cost width in a ~268px row.
- **The playhead mark and the parked mark can now sit one row apart, on purpose.**
  `op_at_tick` still answers the DWELL question — which frame is on screen at this tick,
  which is what the white mark means — while `pos_tick` answers which tick a row stands
  for, which is what a click means. Park on the trailing `LOOP` and the white mark shows
  on the last `FRAME`'s row, because that is the row actually rendering. Papering over
  that would require one of the two marks to start lying.
- **Eight raw vertex rows, not a derived Width/Centre pair.** A pair was proposed
  and measured against: 19,153 of 22,920 corpus frames (83.6%) are axis-aligned
  rect quads, so the pair would be exact for most of them and a lie for the rest
  (E004/E013 rotate a sprite by shearing its quad). It was **declined** — the
  measurement that justified it was about fold COUNT (2 folds, not 52), and that
  justification died with the per-opcode shape. A derived-not-stored editor is its
  own pass with its own round-trip guard; ADR-0089 and ADR-0091 are the local
  precedent for where that belongs.
- **The block opens on the PLAYHEAD's opcode when nothing is parked.** A freshly
  opened sequence has no selection — a click on the strip is what makes one — and
  a block reading "opcode -1" beside a plainly drawn sprite is a worse answer than
  naming the sprite that is drawn. The player is running, so which opcode that is
  depends on the tick the render caught; the block then holds still until a click,
  and never chases a moving playhead.
- **The fold SUMMARY (`42×42 @ -20,-20 · pal 0 · ADD`) goes stale on an edit until
  the next full render.** `refresh_section_titles` rewrites section titles, not
  fold headers, and rebuilding the block to fix that would destroy the ScrubField
  being dragged — decision 3's whole point. The value the author just typed is in
  the spinbox in front of them, and the PICTURE is not stale (each thumbnail
  re-pulls itself off `decode_changed`). Accepted, not overlooked.
- **The Texture Page rows and the per-frame Sheet link/actions are dropped from
  the folds.** TPAGE is four const bytes that belong on the frame's own screen; the
  sheet round trip is already carried once, at the frameset level, and a copy in
  each of up to 14 folds is noise. The frameset's rows are otherwise verbatim.
- **The multi-member case is the normal case, and gets no member picker.** A
  frameset holds N frames; E019's are 82× two-member (the classic PSX double-draw
  — same UV, same palette, quad offset one pixel), and the corpus tail runs to 14
  (E228 frameset 50). At 14 folds that is ~56 ms, so the block absorbs the worst
  case as a plain list. If the list ever reads badly, a `[0][1][2]…` chip row is
  the lever, not a projector.
- **`rebuild_section` is the third member of the refresh family** beside
  `refresh_section_titles` / `refresh_header_values` / `refresh_follows`, and the
  first that can change CONTENT. Its registry scrub is the price: it is the only
  path that removes widgets without going through `_clear_groups`, so every test
  seam the inspector exposes has to be kept honest there.
  **Superseded and DELETED 2026-08-19, on the author's call.** With the block in a panel of
  its own the retarget is a plain `show_target` on a one-section inspector, which touches
  nothing in the strip at all — a stronger guarantee than the in-place rebuild, not a weaker
  one, so the function lost its only caller. It was offered as a general seam and the answer
  was to delete it: a refresh path with no caller is a claim about a future nobody has, and
  its registry scrub was the most subtle code in the file. Three private helpers went with
  it (`_instance_ids`, `_scrub_registries`, `_refers_to_dead`), along with the `_curve_provider`
  / `_on_open` members held across `show_target` purely so a rebuild would not have to ask
  the host for them again, and the `node` / `rows` bookkeeping on every `_sections` entry.
  `show_target` → `_clear_groups` is once again the ONLY path that removes an inspector
  widget, which is what made the identity scrub unnecessary in the first place.
  The acceptance test's orphaned-widget assertion is kept and re-aimed: it now guards that a
  retarget never reaches the strip's registries at all, which is only true while the block
  stays out of the strip's list.
- **Three surfaces now share one 268px row, and none of them is comfortable.** The strip
  gets 677×268 (~3 thumbnails behind ~100px of its own chrome), the block 330×268 (~5 rows,
  scrolling sideways for the widest), the player 218×268. Each of the three amendments
  above is a different symptom of one constraint — the inspector row is ~268px against
  2000+px of content — and fixing them individually is what this pass did. Whether the
  studio's inspector should simply get more room (a taller default dashboard, or a row that
  can take more when the timeline is not what is being looked at) is the question none of
  these amendments answers.
- **`sequence_op` was the second consolidation in a row arguing the same thing, and
  it is now deleted** (2026-08-19, on the user's call). ADR-0100 dec. 7 had left it a
  live target kind no UI produces, on the argument that a link might want to point at
  one opcode again; this screen removed the last thing such a link would buy. The
  deletion is recorded against the decision that kept it — ADR-0100's consequences —
  because that is where a reader looking for "why is this kind gone" will go.
