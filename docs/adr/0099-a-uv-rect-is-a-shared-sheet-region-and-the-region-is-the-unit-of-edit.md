# A UV rect is a shared sheet region, and the region is the unit of edit

## Status

accepted

## Context

`FramesetCanvas` (#278/#279, ADR-0098) lets an author drag one frame's UV rect
over the [sheet](../context/16-effect-studio-authoring-tool.md). The unit of that edit is **one frame**, and the
corpus says that is the wrong unit.

**Frames do not own their UV rects; they share them, heavily.**

| effect | framesets | frames | distinct rects | frames in a shared group | biggest group |
|---|---|---|---|---|---|
| E019 | 100 | 184 | **14** | 184 (100%) | **30 frames across 15 framesets** |
| E173 | 55 | 114 | 32 | 104 (91%) | 15 frames / 15 framesets |
| E005 | 65 | 87 | 44 | 50 (57%) | 16 / 16 |
| E317 | 24 | 25 | 10 | 20 (80%) | 6 / 6 |
| E000 | 10 | 10 | 3 | 9 (90%) | 7 / 7 |

E019 has 184 frames and **fourteen** distinct rects. Editing a sprite there is 30
identical drags, and missing one leaves a frame pointing at the old art with no
diagnostic. Corpus-wide there are **6,605** distinct rects across 399 effects and
**3,253** groups of two or more frames.

> **Amended 2026-08-18, while building.** The per-effect table above counts **raw**
> rects — before decision 1's flip fold — while the corpus figures beside it
> (6,605 / 3,253) count **folded** ones. The table therefore *understates* the
> sharing its own decision creates. Folded: E005 has **34** regions holding **68**
> of its 87 frames (78%), not 44 rects holding 50 (57%); E317 has **9** regions
> holding **21** of 25 (84%), not 10 holding 20. E019, E173 and E000 are unchanged
> — they have no flip that folds onto a twin. The corpus totals were already
> folded and reproduce exactly.

Four further facts, all measured over all 399 effects, shape what the shared thing
can be.

**1. A flip is encoded in the UV coordinates, not in a flag.** 2,628 of 22,920
frames (11%), across **179 effects**, carry a negative `uv.width` or `uv.height`.
A negative width means the stored `x` is the block's **last** column: E005's
`(8,40,32,32)` and `(39,40,−32,32)` address the identical 32×32 block
(39 − 32 + 1 = 8), one drawn mirrored. The convention was decided by measurement,
not assumption — folding negatives under *"stored `x` is the last column"* merges
**851** raw tuples onto blocks that already exist elsewhere in the same effect;
folding under *"stored `x` is one past the block"* merges **zero**.

> **Amended 2026-08-18, while building.** Re-measured as **847**, not 851, under the
> definition *"a distinct negative raw tuple whose folded block equals some positive
> raw tuple in the same effect"*. The count is definition-sensitive across a narrow
> band — folding onto *any* other tuple's block rather than only a positive one gives
> 855 — and 851 is not reproducible from either. The off-by-one reading gives **0**
> under every variant, so the convention itself is settled beyond argument; only the
> headline figure moves. Independently, `block_to_uv(normalised_block(uv)) == uv`
> holds for all **22,920** corpus frames, which pins the fold and its inverse exactly.

Consequently the stored `(x,y)` names a **different corner** per frame:

| `width` | `height` | `(x,y)` names | frames |
|---|---|---|---|
| + | + | top-left | 20,292 |
| − | + | top-right | 1,498 |
| + | − | bottom-left | 633 |
| − | − | bottom-right | 497 |

**2. A rotation is encoded in the vertices, not in the UV.** Classifying every
frame's quad by its edge directions:

| quad orientation | frames |
|---|---|
| normal (top edge runs right, left edge runs down) | 19,962 |
| 90° rotated (top edge runs vertically) | 1,703 |
| 90° rotated *and* flipped | 443 |
| 180° | 412 |
| other rotated / degenerate | ~400 |

**165 of 399 effects** contain a rotated frame, and its UV rect is an ordinary
positive rect. Of the 3,253 shared-rect groups, **330 have members that disagree
on orientation** — the same texels, drawn turned.

> **Amended 2026-08-18, while building.** The four-row histogram above is **not
> reproducible** and should be read as indicative. Its 1,703 quarter-turns reproduce
> *exactly*, but no classifier that also yields 1,703 produces its 412 / 443 / ~400
> split; the shipped classifier (`FramesetCanvas.quad_orientation`, which tests edge
> directions) measures **19,120 upright**, **1,735 turned** (an axis-aligned quarter
> or half turn), **2,064 rotated** (no edge axis-aligned) and 1 degenerate, over
> **188** effects holding a non-upright quad. Groups whose members disagree on
> orientation: **387**, not 330.
>
> Nothing downstream depends on the split. Orientation is a *facet* of decision 5's
> member list, never part of identity, and decision 3 forbids a region edit from
> touching vertices whatever the orientation is.

**3. Scale is also in the vertices, and varying it over one shared rect is the
majority case.** E019's biggest group — 30 frames on `(104,176,23×23)` — draws at
**10 distinct quad sizes** (7×7, 13×13, 24×24, 36×36, 42×42, 56×56, …); its
`(8,8,63×63)` group runs 33×33 → 198×198, a 6× growth ramp. That is one fireball
replicated at many scales from one source block. Corpus-wide, **2,030 of 3,253
shared-rect groups (62%) draw at more than one quad size**; the median group's
largest-to-smallest ratio is 2.4×, p90 10.3×.

> **Amended 2026-08-18, while building.** Re-measured as **1,944 of 3,253 (60%)**,
> taking a quad's size as the bounding box of its four vertices. Same magnitude, same
> conclusion: varying scale over one shared block is the majority case, which is why
> decision 3 is what makes decision 1 safe.

**4. Overlap is not sameness.** E173 holds five rects at one origin —
`(56,48,40×32 / 40×56 / 40×80 / 40×104 / 40×136)`, a beam drawn at five lengths —
plus a `(64,48,24×16)` sprite nested inside their footprint. All six overlap; no
single rect can represent them. Containment is likewise not a duplication signal:
101 effects hold 372 containment pairs, and the examples are small sprites merely
*positioned inside* a larger one's area (an 8×8 inside a 72×80).

Finally, the candidates for a "tidy up duplicate rects" pass were measured and are
thin once flips are folded: near-duplicates within 4px exist in **13 of 399**
effects, and rects holding pixel-identical art at different sheet positions in
**21 of 400** (almost always a single group of 8×8/16×16 blocks).

## Decision

**1. A sheet region is a normalised texel block, and its identity is derived, never
stored.** The region key is `(x, y, width, height)` with the flip folded out —
`x_left = x + width + 1, w = −width` when `width < 0`, likewise for height. There
is no region id, no region table, and no region file. Membership is recomputed
from the frame bytes on read, exactly as `coverage_mask` is.

**2. Two frames are in the same region iff their normalised blocks are exactly
equal.** Not overlapping, not containing, not near. Overlap remains worth *drawing*
as a readout ("3 other regions touch this one"); it is never identity.

**3. The region owns the UV rect and nothing else.** `palette_id`, `is_8bpp`,
`semi_trans_mode`, `semi_trans_on` and all eight vertex components stay per-frame
and are never written by a region edit. Because scale and rotation are vertex
data, **a region edit cannot change how big or how turned any member is drawn** —
which is what makes decision 1 safe for the 62% of groups that deliberately vary
scale.

   **3a. AMENDED 2026-08-21 — one vertex write is admitted: a MULTIPLICATIVE
   scale.** A region edit may multiply every selected member's four corners by a
   factor, about the sprite origin. Nothing else about decision 3 changes: the
   four appearance fields and every *additive* vertex write stay forbidden, and no
   region edit may still set a member's size, rotation or shear to a value.

   *What was actually wrong.* Decision 3's letter forbids the whole class; its
   reasoning objects to one member of it. The objection is that a region write
   would destroy what a varying-scale group exists to express — and that is true of
   a **uniform delta**, which over E019's biggest group (30 frames drawn at 7×7
   through 56×56) would flatten a 6× growth ramp into a constant offset. A
   **multiplicative factor has no such failure**: it preserves every ratio the
   group encodes, so the ramp stays a ramp and the 62% of groups the original
   sentence was protecting are protected by the operation itself rather than by its
   absence. The constraint that dissolved is "a region edit cannot change how big
   any member is drawn"; what survives is "a region edit cannot change how big any
   member is drawn *relative to the others*."

   *Why the author's own words are the reason this was reopened.* Reported as
   *"I don't think its like UVs where things move identically — I do think there
   should be some sort of — all frames at this UV get a scaled adjustment"*. The
   contrast drawn there — against the UV move, where members move **identically** —
   is exactly the distinction above, arrived at independently and from the picture
   rather than from the corpus.

   *About the sprite origin, not about each quad's own centre.* This is a region
   decision, not a taste one. `(0,0)` in vertex space is the particle's world
   position: `EffectParticleRenderer` packs the corners into `transform.basis` and
   the position into `transform.origin`, and `align_to_velocity` already rotates
   about it. Scaling about it is **one similarity applied to the whole set**, so no
   member moves relative to any other — measured at 0px across all 2,030 multi-size
   regions. Scaling about each member's own centre uses a different pivot per
   member and slides them apart: >4px in 29% of those regions, worst case 247px.
   E408 shares one region across 13 frames of a beam whose base sits at exactly
   `y=0` at every size; centre-scaling at 2× walks that base from `+7` to `+56`
   over its own animation, which is decision 3's original objection reappearing in
   a new form. (Where the corpus is decisive at all it agrees: of the 681
   multi-size groups where the two models predict positions >2px apart, the ROM's
   own ramps are origin-proportional in 470 of them, 69%.)

   *"Set every member to 1.50×" is NOT admitted*, and is now expressible for the
   first time — scale is read against a shared base (see 3b) — which is precisely
   why it has to be refused explicitly. It is the flattening decision 3 rejected,
   wearing the amendment's clothes. Multiply, never set.

   *Every member is asked before any is written*, per 4a, and for the same reason:
   a component can leave signed 16-bit (the corpus already reaches 198×198), and a
   small member can round to no area at all, which is invisible and not recoverable
   by scaling back up. Both are refusals of the whole gesture, not per-member
   clamps — a clamp discovered halfway through 30 members is a partial edit with no
   diagnostic anywhere.

   *The verb sits on the scope control, not on the frame's size rows.* Decision 5
   requires the blast radius to be stated **before** the gesture, and a row that
   looks per-frame silently moving 30 frames is the exact failure that control
   exists to prevent — and it cannot show a count from the screen it lives on. The
   per-frame `Width`/`Height` rows stay this frame's alone.

   **3b. The frame quad is read as a transform over the region, and that is what
   makes 3a expressible.** The identity is the sheet region's own dimensions
   centred on the sprite origin; a stored quad is that base under translate,
   rotate, scale and shear (`FrameQuadTransform`). This is a *lossless* reading,
   not a convenience: 22,800 of 22,920 corpus quads are exact parallelograms, every
   one of the 120 exceptions is off by at most one unit, and decompose→recompose
   reproduces the stored integers for 99.47% of the corpus with a worst error of
   2.8×10⁻¹⁴. Six terms, not eight — the two degrees of freedom given up are the
   projective ones that make a trapezoid, which the ROM never uses. It also settles
   what "scale" means for the 2,064 rotated frames: the factor multiplies along the
   quad's **own edges**, so it cannot shear one, which a per-axis scale in screen
   space would.

   The identity is not invented. **41.8% of all 22,920 corpus frames are drawn at
   exactly 1.00× on both axes** — the sheet region's native texel size — and 1.0 is
   the most common scale factor by a factor of ten.

**4. Flip is a per-frame draw property that the region folds out, and region
writes are sign-preserving.** A region move computes the new block once, then
writes each member's `(x, y)` from *that member's own signs*: `x_left` for a
positive width, `x_left + w − 1` for a negative one. A mirrored member stays
mirrored. Rotated members need no special handling at all — the region never
touches vertices.

   **4a. A member can refuse the block, and is asked before release.** The
   encodable range of `uv.width`/`uv.height` is **per-frame and per-axis**, so a
   block one member stores comfortably may be unstorable for another.

   > **Added 2026-08-18, while building.** Decision 4 was pinned on 851 corpus
   > *foldings* — evidence about how the extractor **reads** flips, which says
   > nothing about whether the writer can put one back. So the round trip was run
   > for real (extractor → region move → `write_effect_frames.py` → re-parse) over
   > every flip-bearing region of all 401 `E###.BIN` files, moving and growing each:
   > **5,420 of 5,444 member writes reproduced the block exactly.** `x_left + w − 1`
   > is confirmed.
   >
   > The 24 that failed are one E027 region stored at width **−128**, the signed
   > byte's extreme, grown by 8. The writer masks −136 to byte 120; the sign flag is
   > still set, so the parser reads back **+120**. The block and the flip are both
   > lost, silently. It is a *representability overflow*, not an off-by-one.
   >
   > The sign is not in the value. It is a per-frame, per-axis **flag bit**
   > (`E###.BIN` byte1 bits 4/5) that `parse_frame` applies on read, the writer
   > deliberately never authors, and **`frames.json` does not carry**. Census over
   > the real BINs: 13,614 frames flag-clear with a positive width, 996 flag-set with
   > a negative one, and **16 flag-SET but POSITIVE** — so *"is negative"* and *"is
   > flag-set"* are different questions.
   >
   > | the frame's extracted value | what it proves | the byte's range |
   > |---|---|---|
   > | negative | the flag is **set** | −128…127 |
   > | above 127 | the flag is **clear** (the parser would have negated it) | 0…255 |
   > | 0…127 | nothing — either flag state produces it | 0…127 (the intersection) |
   >
   > The studio infers the range from the value rather than guessing wider
   > (`FramesetCanvas.encodable_uv_range`), and `region_write_verdict` asks it of
   > every member **before release**, beside the merge announcement. Validated as
   > necessary *and* sufficient over the same corpus sweep: of 5,444 member writes it
   > refused all 24 that corrupt and allowed 5,414 that survive — **0 misses**, 6
   > false alarms (0.1%, all in the provably ambiguous band, erring toward refusing).
   >
   > This also falsified a comment in `FramesetChannel.gd`, which held that the
   > writer *"always encodes correctly regardless (masks to the low byte either way);
   > this is advisory-only imprecision, not a round-trip bug."* The mask is correct
   > only **inside** the frame's real range. Its flat −128…127 advisory additionally
   > mis-flagged the **219** corpus frames whose dimension exceeds 127 (E022 stores
   > height 176) although those round-trip perfectly. The bound now reads the frame's
   > own extracted value.
   >
   > **Follow-up worth taking:** the extractor could emit `width_signed`/
   > `height_signed` into `frames.json`, which would collapse the ambiguous 0…127
   > band and remove the 6 false alarms. That changes a committed extracted artifact,
   > so it is deliberately not bundled here.

**5. Move and resize both act on the region, under one visible scope control.**
The control is a radio, the member count is stated **before** the drag, not after,
and the scope survives a re-bind unless the region's *membership* changed (5e —
the original "resets whenever a different region is opened" is superseded).

   **5a. The vocabulary is *effect wide / frameset wide / a manual subset of
   framesets*, and it keys on the FRAMESET (amended 2026-08-21).** The original
   reading — *all N frames* / *this frame only* / *k selected*, with facet filters
   on upright / mirrored / rotated / this frameset / palette — is superseded. It
   was never built: `set_scope` and `set_facet` shipped with pure statics, tests
   and **no production caller**, so every region drag moved all N members for the
   whole life of the feature. The author, on finding the half that did ship: *"how
   do we control the set of what we are changing at the same time. it looks like
   this presents it, but what filters it?"*

   *Why the frameset and not the frame.* Censused over all 398 effects with
   framesets (`tools/census_region_framesets.gd`): of the **3,251** regions with
   more than one member, **91.5%** have members in more than one frameset, and a
   region spans a median of **3** framesets (p75 6, p90 11, p95 15, max 71)
   against a median of **4** members (p90 12, max 107). The frameset is both the
   smaller list and the only one with a picture — the strip draws framesets, the
   viewport plays framesets, and `frameset 17 / frame 0` is an address the author
   cannot see. *This frame only* is also not expressible as a picture at all:
   E019 puts two members of one region in the **same** frameset, so it differs
   from *this frameset* with nothing on screen saying which of the two you got.

   *Why the facet filters are dropped.* They enumerate the ways members can
   **differ** — mirrored, rotated, palette — which is a fact about the data and
   not a task anyone has. Two members sampling one rect draw the same texels
   whether or not one is mirrored, so there is no art reason to move one and not
   the other. (The facets survive as *row labels*, where the differences are the
   only thing worth printing; see `FramesetRegionScope.varying_facets`.)

   *The subset is ticked on a rail of thumbnails, along the bottom of the texture
   viewfinder.* The author's own shape: *"subset of framesets (manual toggle,
   thumbnail order)"* … *"actual thumbnails along the bottom of the texture
   viewfinder"*. It is a picture because the thing it selects has no other
   address, and it is in **thumbnail order** — the framesets the sequence on
   screen reaches first, in that order, then the ones it never plays. That tail is
   the point: on E317 a region spans framesets 15/17/18/19/20/21 while the
   emitter's sequence plays only 15, 16 and 22, which is the author's earlier
   report *"only thumbnail 1 changed. I thought the change was effect wide?"*

   **5b. A narrowed scope is a SPLIT, and it must be labelled one.** This is the
   sentence the control exists to get right. `region_edits` writes each member's
   own `uv_*` bytes and a region is **recomputed** from those bytes on every read
   (decision 1) — there is no region table — so leaving a member out does not make
   a smaller edit: it gives the moved frames a new rect and leaves the rest behind
   as their own region. "2 of 6 frames will move" is true and useless, because it
   hides that the group the author has been treating as one thing stops being one
   thing. This is decision 7 ("splitting a frame off its region is *moving it to a
   different block*") arriving as a **UI obligation** rather than a data fact:
   the mechanism was always there and the surface never said so, while
   `region_merge_preview` had announced the reverse from the start.

   **5c. Un-ticking the last frameset is refused.** An empty selection is a drag
   that moves nothing, and a gesture that silently does nothing is worse than a
   refused click — the author would release the mouse and read a status line about
   zero frames. *Effect wide* is one press away.

   **5d. Widening seeds from what was showing.** Pressing *Pick* ticks everything
   the previous mode selected, so the author un-ticks from a full selection rather
   than building one from nothing. This is decision 5's own "the count is made
   visible instead of the default made timid", applied to the one mode whose whole
   job is partial selection.

   **5e. The mode persists; a hand-built subset does not (amended 2026-08-21).**
   dec. 5's original letter — *it resets to the widest scope whenever a different
   region is opened* — was enforced by `FramesetRegionScope.bind`, which has **four
   callers and only one of them is "a different region was opened"**: the panel
   re-binding (thumbnail change, playhead move, target change), the pointer
   crossing to another live box, a click pinning one, and **the author's own drag
   committing** (`EffectStudioPage:2778`). Reported as *"whenever you change the
   selection scope (effect, frameset, individual) — if you then change the
   thumbnail, it flips back to effect. the scope should persist."*

   This is the same shape as the 3a amendment: the letter over-reached past its own
   reasoning. Two things make persistence the **safer** reading rather than the
   laxer one.

   *The reset is itself a silent failure, in the worse direction.* dec. 5 was
   written so the count could not be wrong at the moment of the drag. Resetting
   prevents the **under**-edit (a narrow scope carried somewhere unrelated) and
   mints the **over**-edit: an author who narrows the scope, looks at another
   sprite and comes back drags believing they are still narrow and moves thirty
   frames. Between the two, the one that rewrites data the author did not intend to
   touch is the one to prevent.

   *The control is visible and states the count for whatever region it is now bound
   to*, which is what dec. 5 actually requires. A persisted mode is **announced**,
   not silent — the radio shows which mode is pressed and the label states the blast
   radius and its split (5b).

   *`SCOPE_SUBSET` is the exception, and not as a compromise.* The other two modes
   are **rules** — *effect wide* and *frameset wide* — which every region can honour
   and which re-evaluate against the new members by themselves. A subset is a
   hand-built **list** of one region's framesets; carried into a different region it
   either names framesets that region has no members in (an empty selection, which
   5c refuses outright) or happens to name all of them (a subset that silently means
   *all*, which is the failure dec. 5 exists to prevent). It degrades to *frameset
   wide* — the narrowest scope expressible without inventing a choice the author
   never made — and the radio says so.

   *A region's identity is its MEMBERSHIP, not its block.* The region's `Rect2i`
   moves on every commit, so identity read off the block would report "a different
   region" on the one caller whose whole meaning is *the author's edit landed*.
   `FramesetRegionScope.member_key` is the sorted `frameset/frame` addresses, and
   `bind` compares against the members the current scope was chosen for.

   *And no region in context is not a region change.* The resting bind on a
   multi-region frameset (`frame_index = -1`) and the pointer leaving every box both
   resolve nothing, and both sit on a **mouse-move** path — so treating them as a
   change would put the reset back on exactly the path ADR-0130 dec. 12f had to pin
   a region to escape. The scope keeps what it had and is intact when a box is
   entered again.

   > The guard that held the old letter never tested what it claimed. Its "a
   > DIFFERENT region on the same sheet" re-bound to a frame whose uv is the *same
   > block*, stored mirrored — it passed only because `bind` reset unconditionally,
   > so no bind could tell the two apart.

**6. Scope is a visible control, never a modifier.** The studio's existing chords
are already spoken for: `Shift`+left-drag is pan on `EffectScoreTimeline`,
`EffectFramesBar` and `FedsPairLanePanel`; `Alt`+left-drag draws the loop region
on the frames bar; right-click opens context menus on `EffectScoreTimeline` and
`ColourKeyframeTrack`. `FramesetCanvas` is the outlier that binds **pan to
right-drag** — it moves to **middle-drag + `Shift`+left-drag** to match the other
three, freeing right-click for a context menu. The `Shift` branch must be tested
*before* the UV-box hit-test, as `EffectFramesBar:111` already notes for its own
`Alt` branch, or a `Shift`-drag starting inside the box would move the box.

**7. There is no detachment state and no consolidate verb.** Splitting a frame off
its region is *moving it to a different block*; rejoining is *landing exactly on
an existing block*. Both are consequences of decision 1, not features. A
persistent "detached" flag is rejected: `E###.BIN` has no field for it and
`frames.json` is a committed extracted artifact that must reproduce from
{ISO + extractor}, so the state could only be session-local — meaning a frame
detached-but-not-moved would silently rejoin its group on reload, which is a worse
failure than the one this ADR prevents.

**8. The anchor corner is drawn.** The canvas colours the corner that *this
frame's* `uv_x`/`uv_y` refer to (decision 1's table), because for 2,628 frames it
is not the top-left and the fields would otherwise contradict the box on screen.
Every member of a region has the identical block, so there is exactly **one**
rectangle to draw; the anchor colour is the only per-member difference.

**9. A region edit is one compound edit and one undo.** It lowers to
`EffectEditSession.apply_compound` over the selected members × their changed uv
fields, through the #255 choke point, exactly as the existing single-frame drag
already does at `EffectStudioPage._on_frameset_uv_changed`.

## Consequences

- **Three flip-blind defects in `FramesetCanvas` become prerequisites, not
  follow-ups.** `coverage_mask:472` computes `x1 = x + width`, so a negative width
  yields an empty range and the frame contributes **no coverage** (the E019/E317
  oracle numbers survive only because every flipped rect there has an unflipped
  twin covering the same block — confirmed on the fix: both are unchanged by it).
  **Measured on building: this got the overlay wrong on 61 of the 179 flip-bearing
  effects, dimming 182,000 addressed texels as dead sheet** — E244 read 12,096
  covered against a true 39,552. Since decision 5 of ADR-0098 tells authors that
  dead sheet is exactly where they may paint freely, the defect was actively
  inviting them to paint over live art. `uv_to_canvas_rect:585` multiplies the signed
  width through, producing a negative-size `Rect2`, so `hit_test`'s `has_point`
  fails and a flipped frame's box cannot be grabbed by its body. `resize_uv:638`
  normalises through `min`/`max`, so the first corner drag on a flipped frame
  **silently unflips it**. All three predate this ADR; all three make it
  unimplementable.
- **A region resize changes what is sampled, not what is drawn.** Vertices are
  untouched, so growing a block makes every member sample more texels into the
  same quad — the sprite stretches rather than revealing more, and it stretches
  differently per member because their quads differ (7×7 to 56×56 in E019's
  largest group). This is accepted, not fixed here: making a sprite *bigger* is a
  vertex-scale edit, and no such verb exists in the studio yet (`FramesetChannel`
  exposes the eight vertex components individually). That verb is deliberately
  out of scope.
- **Resize merges regions mid-gesture, often.** Blocks frequently share an origin
  (E173's five beam lengths), so dragging a corner lands on a neighbouring
  region's block routinely. The chrome must announce it before release — *"lands
  on region (56,48) 40×56 — 3 more frames will join this group"* — because the
  merge is silent otherwise and is only visible three framesets later.
- **This is not [Ripple](../context/16-effect-studio-authoring-tool.md).** Ripple is the time-axis resize mode of
  ADR-0087: a sticky toolbar toggle that shifts downstream keyframes within a
  lane. This is a spatial, entity-scoped edit with a visible scope that persists
  across re-binds and re-evaluates against whatever region is bound (5e). The vocabulary must not merge them, and the UI must not put a second
  sticky toggle called anything like "ripple" in the same window.
- **Nothing new persists.** No file format changes, no session state beyond the
  scope control's current setting, and the same effect reloaded yields the same
  regions. That is the direct pay-off of derived identity, and it is why the
  rejected alternatives (stored region ids, a detachment set, a consolidate pass
  that rewrites rects) were all rejected on the same ground.
- **Consolidation is the identity rule, not a button.** Folding flips alone merges
  851 raw tuples corpus-wide, for free, on read. What remains — 13 effects with a
  ≤4px near-duplicate pair, 21 with pixel-identical art at two positions — does not
  justify a global sweep whose tolerance the data cannot justify. If a merge verb
  is ever wanted, it should be the two-selection *"merge onto…"* (the inverse of a
  break-off), never a blind sweep.
