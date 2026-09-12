# The texture has two surfaces: a page and a tab on the inspector row

## Status

accepted

## Context

> "it seems like there are random links to the texture everywhere. But nowhere can
> you actually view the texture. I think we should just have 2 places to
> view/export/import texture."

The complaint is correct, and an audit makes it sharper than stated. There are
**four** texture surfaces, and **none of them shows the picture**:

| # | where | what it offers | picture? |
|---|---|---|---|
| 1 | `TextureProjector` — the `texture` target kind | 6 metadata rows + Export/Import | no |
| 2 | `FramesetProjector._sheet_link` | a `Sheet → texture` link row | no |
| 3 | `FramesetProjector._sheet_actions` | a **verbatim duplicate** of #1's Export/Import pair | no |
| 4 | `SequenceFocusBlock` | *strips* Sheet/Export/Import out of the grafted rows, then mints a `Sheet region → edit on frame N/M ▸` link | no |

The sheet is drawn in exactly one place, `FramesetCanvas` (ADR-0098), and the
load-bearing line is in `EffectStudioPage._update_frameset_canvas`:

```gdscript
if Target.kind(target) != "frame" or _effect_data == null:
	_frameset_panel.visible = false
```

**The only viewer of the sheet is gated to the `frame` kind alone.** Not
`frameset`, not `texture`. So the Texture page cannot show the texture *by
construction*, and the picture is three drills deep from anywhere an author
actually works.

### Three measurements that decided the shape

**The whole-sheet view already exists and has no caller.** `FramesetCanvas._draw`
paints checkerboard → sheet → ADR-0098 dec. 5 coverage mask, and only then
`if not _frame.is_empty(): _draw_uv_overlay(...)`. Binding with an **empty frame
dictionary** therefore yields the entire sheet with coverage dimming and no
handles — a read-only whole-sheet view, already built, already guarded, never
reached. Nothing new had to be written to show the picture.

**No sheet in the corpus is larger than the box that already exists.** Measured
over all 401 `E###` TGA headers:

| sheet | effects |
|---|---|
| 128×256 | 262 |
| 256×128 | 58 |
| 256×256 | 57 |
| 128×128 | 16 |
| eight one-offs (128×88 … 256×64) | 8 |

Maximum **256×256**. `_CANVAS_SIDE` is **260**. The premise that "a whole sheet is
the largest thing anyone has asked to put in the row" is false — it is *smaller*
than the sequence player already sharing that row.

**The inspector column is wide enough to hold a sheet and its controls side by
side.** `EffectStudioEmitterColumnTest` records, on a 1187×507 body, that an
`emitter` target declares **675px of content width and 2027px of content height
into a 268px row**. A 256-wide sheet leaves **419px** beside it — enough for the
metadata rows, the round-trip buttons and the ADR-0099 scope control on one row,
which no other container in the studio can offer.

### The two shapes that were measured against each other

The author first proposed a **collapsible band** spanning both columns, above
them. It was costed and rejected on its own arithmetic. The band takes height
from `budget = h − path_bar − MIN_CHANNELS_H − frames_bar`, which at the dev body
is **268 total** — and the sequence player already wants `260 + 88 = 348` and is
being clipped to 268 today. There is no height to give:

| at the dev body (1187×507), showing a 128×256 sheet | band | tab |
|---|---|---|
| height taken from the budget | 134 (half, by the pair-panel contention rule) | **0** |
| sheet visible at 100% | 134 / 256 = **52%** | 240 / 256 = **94%** |
| sequence player | clipped 348 → 134 | **untouched** |
| on a tall body (h=1209, budget 970) | whole sheet, no pan | whole sheet, no pan |

The tab wins on the author's own criterion — *"then it wouldn't push the player
stuff down"* — and it does not cost the thing the band was for: on the Texture
tab the player is still in the right column at full size, so "see the texture
while working in the sequence player area" is satisfied. What a tab gives up is
texture and emitter *parameters* simultaneously, which was never asked for.

**The tab needs no re-parenting.** `_inspector` is a manually-positioned child of
`_body` — `_relayout` assigns it `position(0, bar_h)` and `size(editor_w,
editor_h)` directly, not through a container. A sibling panel taking the same rect
is the shape `_frameset_panel`/`_sequence_panel` already use for the right column,
and it leaves all 51 `_inspector` call sites untouched.

## Decision

**1. The texture has exactly TWO authoring surfaces.** The **Texture page** (the
`texture` target kind) is the deep surface: full metadata and the round trip. The
**Texture tab** on the inspector row is the shallow one: the picture, wherever you
are. Every other texture surface is a *door* to one of these, never a third place
to do the work.

**2. The inspector row's LEFT column has two tabs, `[Texture] [Values]`, on every
target kind.** They are mutually exclusive occupants of one rect, chosen by a tab
strip, exactly as the right column's two occupants are chosen by target kind
(ADR-0100 dec. 1). `Values` is the existing inspector, unchanged.

**3. The tab costs the row NO height, and the right column NO width.** The strip
takes its height out of the left column's own rect, never out of `budget`. The
right column continues to be claimed from `_inspector.content_width()` **whichever
tab is showing** — so switching tabs cannot resize the player. This is the
declared-width discipline of ADR-0100 dec. 3, applied to a second axis of
hiding: Godot skips invisible children in container minimums, so a width read
live off the visible tab would swing on every switch.

**4. The Texture tab binds the frame IN CONTEXT, and has an honest empty state.**
On a `frame` target it binds that frame: one UV box, live handles, scope control.
On every other kind it binds the **empty dictionary**, which is not a degraded
state — `FramesetCanvas._draw` paints the sheet and the ADR-0098 dec. 5 coverage
mask unconditionally and only then `if not _frame.is_empty()` draws the overlay.
That is the read-only whole-sheet view, and it already existed with no caller.

> **Corrected while building.** The design said the tab would bind "the frame the
> sequence player is currently showing" on an `emitter` or `animation` target, so
> the UV box would walk the sheet as the animation plays. **There is no such
> frame.** A `SequenceTimeline.trace` cell carries `frameset` — an index into the
> effect's framesets — and a frameset is a GROUP of frames drawn together, each
> with its own UV rect. E019's frameset 0 alone holds several. So the shown sprite
> names N rects, not one, and `bind_frame` takes exactly one.
>
> Binding frame 0 of that frameset would have been the tempting fix and is the
> ADR-0100 defect verbatim: it decodes a real rect and draws a real box, and
> *nothing on screen says it is the wrong one*. Rejected.

**4a. What the player's position contributes instead is COVERAGE, not a box.**
When a frameset is in context the tab dims the sheet against **that frameset
alone** (`bind_framesets` with a one-element array) rather than against the whole
effect, so the lit texels are exactly the regions the sprite now on screen draws
from. This is the honest form of "watch the sheet as it plays": it says N regions
when the answer is N regions, and it needs no new canvas capability — the mask is
already per-array.

**4b. A frameset in context draws ONE OUTLINE PER DISTINCT REGION, read-only.**
Amended 2026-08-20 after the author used it: *"I can't get the yellow boxes
showing which rect is sampling what. What do I need to interact with on the right
side… how does it know which frameset is active?"*

Dec. 4a was right that a box may not be invented for a group, and wrong about what
follows from it. "Draw one box" and "draw no boxes" were never the only options —
**N outlines were always available**, and coverage dimming was answering the
question in a representation the question is not asked in: dimming is a property
of texels, and "which rect samples what" is about rectangles.

* `FramesetCanvas.bind_group(frames)` outlines every distinct block, **deduped**.
  Members of one region have the identical block (ADR-0099), so E019's typical
  2-frame double-draw sharing a rect draws **one** outline, not two stacked — and
  the readout's region count is taken from the same array that is drawn, so the
  number and the picture cannot disagree.
* They are drawn in `GROUP_COLOR`, dimmer than `HANDLE_COLOR`, because they are
  read-only: none has drag handles, and a box that looks draggable and is not is
  worse than no box.

**4c. "Which frameset is active" now has an answer: the PLAYER'S.** On an
`emitter`, `animation` or `span` target the tab reads `_shown_frameset()` —
`_sequence_canvas.shown_op()` against the canvas's **own trace**, never re-derived
from `_nav`. `shown_op` already owns the playing-vs-parked rule ("a still that
keeps running is not a look"), and a trace cell's `frameset` is absolute because
`SequenceTimeline.trace` folds the group offset in. So scrubbing the sequence
walks the outlines around the sheet, which is what dec. 4's correction gave up and
this recovers correctly — per frameset, N boxes, rather than per frame, one lie.

**5. The yellow handles are LIVE in the tab, and the ADR-0099 scope control sits
beside them.** They ship together or not at all. A UV rect is shared — E019's 184
frames sit on 14 distinct rects, the biggest used by 30 — so a drag without the
control that states its blast radius is the ADR-0099 failure by construction. The
419px beside the sheet is what makes this expressible; it is the first layout in
the studio where the handles and their safety control fit on one row.

**6. Surface #3 dies.** `FramesetProjector._sheet_actions` was a verbatim
duplicate of the Texture page's Export/Import pair, and its docstring justified
itself on the grounds that "repainting is *why* an author is looking at a UV rect,
so making them drill in put the export a navigation step from the box it applies
to." That argument is **answered, not ignored**: the buttons are now beside the
box on every screen, which is strictly closer than the frameset row ever was.

> **Corrected while building: surface #3 was TWO call sites, not one.** The audit
> counted `_sheet_actions()` once, on the `frameset` target. It was appended to the
> **`frame`** sections as well — which is exactly why `SequenceFocusBlock` has to
> strip `"Sheet"`, `"Export"` and `"Import"` back out of the frame rows it grafts
> into its folds. So the duplicate pair rendered on two target kinds and was
> suppressed on a third by a downstream filter. Both call sites are deleted; the
> filter in `SequenceFocusBlock` stays, because `_sheet_link` still renders there.

**7. Surfaces #2 and #4 survive as doors, and neither is a place to work.**
`_sheet_link` is the only thing that MINTS the `texture` target — registering a
kind in `InspectorProjectorRegistry` does not make it reachable — so deleting it
would strand the page. `SequenceFocusBlock`'s `Sheet region ▸` link is the route
to the `frame` target and stays for the same reason.

**8. The Texture page shows the picture too.** The `frame`-only gate is widened to
admit the `texture` kind with an empty frame bind. The page keeps the six metadata
rows and the refusal path; the tab carries a summary line and links out to it.

**9. The tab keeps the ADR-0097 refusal.** A 4bpp sheet offers neither direction
of the round trip — 58 of the 60 4bpp effects render through 3–7 per-frame
sub-palettes, so a flat RGBA export is an untruthful artifact. The tab states the
refusal in place rather than showing dead buttons or deferring it to the page.

**10. A `frame` target does NOT draw the sheet twice. The right column plays the
sequence instead.** Added 2026-08-20, and it closes the question dec. 8's
consequences left open.

Once the tab carried the sheet with live handles and the scope control, a `frame`
screen showed the SAME sheet in both columns, both interactive — two places to
drag one box, and a real risk of the two disagreeing rather than merely being
untidy. The frame screen is now **the sheet on the left, the animation on the
right**. This is the same trade that made a tab beat the band: stop spending the
row on a duplicate.

`texture` KEEPS the right-column canvas. There is no sequence for a texture target
to play, and dec. 8 — the page having a picture without switching tabs — is the
complaint this ADR opened on.

**10a. Which sequence a frame screen plays, measured before it was decided.** Over
all 401 effects / **17,423 framesets**, counting animations whose FRAME opcodes
name each frameset:

| animations naming the frameset | framesets | share |
|---|---|---|
| 0 | 1,887 | **10.8%** |
| 1 | 13,319 | **76.4%** |
| 2 | 1,564 | 9.0% |
| 3 or more | 653 | 3.8% |

Each of the three cases gets its own answer rather than one guess wearing a
confident label: **one** → bind it; **several** → bind the lowest and let the
panel title name which, so the author can see they are looking at one of N;
**none** → bind nothing and let the column go unclaimed, the width returning to
the inspector as ADR-0100 says it should. Inventing an address for an orphan
frameset would be the ADR-0100 defect verbatim — a real sequence, real sprites,
and nothing on screen saying it is the wrong one.

**The lens is deliberately not applied.** A trace cell's frameset is
`op.frameset + group_offset` and the offset comes from an EMITTER's `anim_param`;
a frame target has no emitter, so the scan matches base indices at group 0. On the
18 effects with more than one group this can miss an animation that reaches the
frameset only through a shifted lens. Stated rather than hidden: the fix for that
is an emitter, and an emitter reaches the column through `EmitterSubject.resolve`
already.

**11. The facts RIDE ON THE PICTURE — a bottom-right overlay, not a column beside
it.** Amended 2026-08-21, the author's third report on this surface: *"this box was
supposed to just be some tiny box which minimally and/or doesn't cover the texture
page. Instead its a giant column with a bunch of dead space on it taking up lots of
horizontal space that should go to the texture."*

**The measurement first, because it names a different cause than the report does.**
At the dev body the page hands this tab a **1564px** slot. The canvas was capped at
`CANVAS_W` (560) while the facts `ScrollContainer` carried `SIZE_EXPAND_FILL`, so the
leftover — **1000px** — went to a column whose text is about 250px wide. The sheet drew
at 256px inside a 560px port with a thousand pixels of nothing beside it. Dec. 7's
split was neither collapsed nor binding; it was **over-generous in the wrong
direction**, and no tuning of the split fixes a cap on the thing that should be
growing.

**11a. Which constraint dissolved, and it is not the one dec. 7 was defending.**
Dec. 7 made the width a SPLIT because 560 + 300 declared a combined minimum of 864
against a row measured at 727 — a Container cannot shrink below its minimum, so the
panel overflowed right and the sequence player sliced the facts mid-word.
`FramesetCanvas` **extends `Control`, not Container**, so an anchored child contributes
nothing to an ancestor's minimum: with the facts inside the port, the row and the
column have no width left to disagree about. Measured, the tab's whole width claim went
**864 → 1**. The failure dec. 7 managed is *unreachable*, not merely *managed*, so
`set_slot_width` / `canvas_width` / `chrome_width` / `CANVAS_W` / `CANVAS_MIN_W` /
`DECLARED_SIDE_W` are deleted rather than left standing as dead reasoning — and the
panel's docstring keeps dec. 7's case verbatim, because this surface has now frozen an
incidental layout into a rule **twice** (ADR-0089 dec. 6 is the same shape one surface
over) and the record of *why* is what stops a third.

**11b. `CANVAS_W`'s own constraint dissolved the same way.** The cap existed because
letting the canvas expand was tried and photographed: *"at a 1945px panel it made a
1241px canvas that centred a 128px sheet in the middle of nowhere, with the sheet's own
metadata stranded 1100px away at the right edge. The picture and the facts about it
belong in one glance."* That is exactly right, and an overlay satisfies it the other way
round — the facts are **on** the port, so they are adjacent at every width by
construction and stranding is unrepresentable. With nothing left to defend, the canvas
takes the slot.

**Measured after:** port 560 → 1564 on a `frame` target, the sheet opens at **6x**
instead of 2x on the tall emitter row, and the overlay is **7.1% / 9.5% / 2.8%** of the
port across the three column-bearing kinds.

**11c. Three traps this shape has, each handled and each asserted.**

* **Thirty members.** E019's biggest region lists 30 frames. As a side column that is
  what the scroll was for; as an overlay it would cover the sheet completely — the same
  complaint, relocated. The scope gets a fixed `SCOPE_H` and its `ItemList` scrolls
  inside it, and the whole overlay is capped to **60% of the port's height**. Measured
  on the `frameset` row the facts wanted 247 of 263px — 94% — before the cap.
* **Reachability.** Export/Import sit at the **top** of the overlay. This is
  `cbe359478`'s ⬥ fix applied before it can bite: an overlay pinned to the bottom edge
  that grows downward puts its last row off the port, *technically visible, actually
  unreachable*. A clamp eats the bottom of the content, so what goes is a fact and never
  a button. Guarded on a probe with a deliberately short port, because the live port is
  700px tall and the case cannot redden there.
* **Mouse.** `PASS` on the overlay so hover, zoom and pan reach the picture through it
  and the sheet is not inert under its own metadata; `STOP` on the buttons and the
  member list. The body's `ScrollContainer` only *accepts* a wheel when it has somewhere
  to scroll, so a wheel over a fully-visible overlay still zooms the sheet and one over
  an overflowing overlay scrolls the facts.

**11d. It folds to the caption alone** — 36px against 316px open, measured — and the
fold survives a rebind. That is the "tiny box" the ask names, available on demand rather
than imposed: the facts are the point of the surface, so the default stays open.

**12. On a surface with no single frame in context, EVERY distinct region of the
frameset is its own LIVE box.** Amended 2026-08-21 after the author used dec. 4b:
*"we want those yellow box corners (and the one off-colored corner for
orientation) visible and editable in the 'all-in-one' emitter page."*

Dec. 4 refused to bind a box here, and its reason was: *"a `SequenceTimeline.trace`
cell carries a frameset, a frameset is a GROUP of frames each with its own UV, so
the shown sprite names N rects and `bind_frame` takes exactly one."* Every clause
of that is true. The conclusion drawn from it — draw no editable box — does not
follow, and dec. 4b already half-corrected it once by the same move: **"draw one"
and "draw none" were never the only options.** Dec. 4b took N outlines. This takes
N *boxes*.

**There is nothing to pick, so there is nothing to lie about.** The defect dec. 4
was guarding against is picking one member of a set and presenting it as the whole
— the ADR-0100 defect, "it decodes a real rect and draws a real box and nothing on
screen says it is the wrong one." N independently editable boxes make no such
claim: each box *is* its own region, and the author edits the one they point at.

**The grouping is ADR-0099 dec. 1+2, unweakened, and it is what "perfectly
overlapping frames move together" means.** Identity is the normalised block — flip
folded out, so E005's `(39,40,-32,32)` and `(8,40,32,32)` are one region — and two
frames are in one region **iff those blocks are exactly equal**, "not overlapping,
not containing, not near." So frames that coincide exactly were already folded into
a single outline by dec. 4b's dedup, and that fold is now also the unit of edit:
one box, one drag, every member written through its own signs (dec. 4). Partial
overlap and containment stay **separate boxes**, which is the only representable
answer — E173's five beam lengths at one origin plus the sprite nested inside their
footprint are six regions precisely because no one rect can stand for them.

Measured over the 399 effects that have framesets, to size what this actually
exposes:

| | |
|---|---|
| framesets sampling exactly ONE region | **15,763 / 17,423 (90.5%)** |
| framesets sampling 2+ | 1,660 (9.5%), max 9 |
| region pairs OVERLAPPING within one frameset | 118, of which 69 nested |
| ...sharing a top-left origin (handles stack exactly) | 48 |
| regions whose members DISAGREE on anchor corner | 419 / 19,518 (2.1%) |
| regions with members in MORE THAN ONE frameset | **15,891 / 19,518 (81.4%)** |

The first row is the one that retires dec. 4's premise in practice: nine times in
ten the frameset names exactly one rect, so "which of N" is not a question the
author is ever asked. The last row is the one that keeps dec. 5 mandatory.

**12a. The grab priority is CORNER over BODY, then SMALLER over LARGER.** Both
halves are forced by the 118 overlapping pairs. Corner-beats-body must hold *across*
regions, not merely within one: a nested rect's handle sits inside its neighbour's
body, so without it resizing the inner rect moves the outer one. Smaller-beats-larger
is the only tie-break that leaves every region reachable, because nesting is
asymmetric — the inner rect is grabbable nowhere else, while the outer one is
grabbable everywhere the inner one is not. Regions are also *drawn* largest-first so
the picture and the hit priority agree.

**12b. The anchor is a SET of corners, not a corner.** ADR-0099 dec. 8 colours the
corner *this frame's* stored `(x,y)` refers to, and on a `frame` target "this frame"
is unambiguous. Here a region is N members which share the block by construction but
not necessarily the winding: 419 corpus regions have members that disagree. Colouring
one member's corner would contradict the others with nothing on screen saying so —
dec. 4's own objection, re-entering by the back door. So **every corner that is some
member's anchor is coloured.** When members agree (97.9%) that is exactly one cyan
corner and the picture is identical to the single-frame case; when they disagree it
is two, which is the honest statement that this region is wound two ways.

**12c. Anchors are drawn in a SECOND PASS, after every region's plain handles.**
Found by screenshot on E066 emitter 0 with the whole suite green. Its two regions both
begin at `(216,8)`, so their `tl` handles occupy the same pixels; drawn in region
order, the smaller region's plain yellow square painted over the larger one's cyan
anchor and the winding cue simply vanished. 48 corpus pairs share an origin. Deferring
anchors means a stacked corner shows cyan whenever *any* region anchors there — showing
information that exists, rather than hiding it behind information that also exists.

**12d. Dec. 5 is unchanged and now binds harder: the scope control FOLLOWS THE
POINTER.** Handles and the control that states their blast radius still ship together
or not at all. Dec. 5 requires the member count to be stated *before* the drag, and
with N boxes the region it should describe is the one the press would take — so the
control re-binds on hover, resolved by the same `pick_region` the press uses, and the
highlight and the grab cannot disagree. It also **holds its height** whenever the
handles are live rather than appearing when the pointer enters a box: a control that
materialises on a mouse-move path would resize the overlay and make the facts jump as
the author swept the sheet. Re-binding originally **reset** the scope to ALL, on the
grounds that moving between regions is a mouse-move; ADR-0099 dec. 5e reverses that and
for the same reason read the other way — a reset on a mouse-move path is unusable, which
is what 12f (a click pins the region) had already concluded. The mode now survives every
re-bind and only a hand-built subset degrades, and only when the region's membership
actually changes.

**12e. The `frame` target is untouched.** There the one box is live already and these
are its dim siblings (dec. 4b); promoting them would give the author two competing
affordances for the frame they explicitly drilled into. `group_live` is set exactly when
there is a frameset in context and no single frame, and it is set by the panel at bind,
never inferred by the widget.

**12f. A CLICK PINS A REGION, and while pinned the pointer stops speaking (amended
2026-08-21).** 12d is right and it is not sufficient. Following the pointer makes every
control that *reads* the scope unreachable: the facts overlay sits in the port's
bottom-right corner, so the pointer travelling from a box to a button, a tick or a
scrollbar crosses the sheet — and 118 corpus region pairs overlap inside a single
frameset — so the panel re-binds and the thing being reached for is **replaced before
the hand arrives**. That was already true of Export/Import; it is fatal for the
per-frameset tick rail dec. 5a's subset mode needs.

A press-and-release with no motion between them is a click and it pins; anything else is
a drag and commits. That distinction cost nothing to make: a click *was* a zero-length
drag that travelled the whole commit path, found nothing to write and returned. Pinned,
only the pinned box takes a press and the others draw as read-only outlines with no
handles — the picture and the input rule read off the same variable, because drawing a
box live while refusing its press is the "present, visible, and not hittable" defect this
surface has shipped three separate times. Released by a press on bare sheet or by
`Escape`; dropped outright by a re-bind, since the pin is an index into the region list
and a stale one would pin box 3 of a frameset that now has two.

**12g. The overlay's ordering rule is *what may not be lost goes first*, and the SCOPE
outranks the actions.** `cbe359478` put Export/Import first because a clamped overlay
loses its last row first — written when they were the only thing in the box. Once the
scope toggle arrived, *first* became a contest neither could win: measured on a 520×150
probe (96px of port, 27 of header, and the blast-radius sentence plus its toggle row is
50), whichever went second was below the fold. The actions therefore leave the scrolling
body entirely and become a sibling of the `ScrollContainer`, pinned to the overlay's
bottom edge; the scroll carries `SIZE_EXPAND_FILL` and a ~zero minimum, so it absorbs the
whole clamp while the header and the actions keep their rows. Inside the body the scope
is first, because it is the only thing in the overlay that must be read *before* a
gesture rather than during one.


## Consequences

* **Dec. 4b's outlines were the whole feature, drawn one property short.** The regions,
  the dedup, the per-region block and the readout count all already existed and were
  correct; what shipped was `GROUP_COLOR` and no hit-test. The distance from "the author
  cannot edit this" to "the author can" was a flag, a picker and a second draw pass. Worth
  recording because dec. 4b was itself the correction of dec. 4, and the corrected version
  still stopped one step short of the thing the author asked for — twice in a row, the
  error was not a wrong answer but an unnecessarily small one.
* **A green suite shipped a wrong picture on this surface for the third time.** Dec. 12c
  was invisible to 30 passing assertions because draw ORDER is not a property of any pure
  static. The tab's own build notes record the same shape twice (31 green assertions over
  a sheet centred off-screen; the colour ribbon's band). The rig for this one is
  `EffectStudioGroupHandlesShot`, aimed at E066 frameset 59 — five regions, five
  overlapping pairs, one containing three others.
* The count of texture surfaces goes 4 → 2, and the count that show the picture
  goes **0 → 2**.
* ~~The `frame` target's right-column frameset canvas is now the *second* place the
  sheet is drawn on that screen. Whether they should merge is deferred, not
  answered.~~ **Answered by dec. 10**: it does not stay. The frame screen plays its
  sequence there instead, and `_update_frameset_canvas`'s entire per-frame branch —
  its fs/fr resolution, its `_region_scope.bind`, its title — is deleted as dead.
* **A third surface means a third thing to PARK, and nothing was parking any of
  them.** Both paths that clear `_nav` — Esc (`_deselect`) and `_load_effect` —
  leaned on `_render_current()`, which early-returns on an empty nav; both had a
  comment celebrating that as a saving. Measured on the real page, E019 → Esc →
  E317: after Esc the player was still bound to `{anim_index: 1}` of the emitter
  just deselected, and after loading E317 it was **still** bound to E019's
  animation 1 with the Texture tab **still holding E019's sheet** (instance
  …977776 against the loaded …091137). An author looking at E317 was looking at
  E019's art. Fixed with one `_park_target_surfaces()` helper and two callers;
  guarded by `EffectStudioStaleSurfaceTest`, A/B'd red per caller.
  The tab did not cause this — it inherited it, and made it worse by being a
  third surface. Same class as the #280 import staleness, except nothing re-bound
  at all rather than re-binding late.
* One duplicate survives on purpose and is worth naming: a `texture` target draws
  the sheet in the right column AND in the tab. That is dec. 8 being load-bearing,
  not an oversight — the page is the surface the complaint was about.
* ADR-0100's unanswered question — *"whether the studio's inspector should simply
  get more room"* — is still unanswered. This ADR routes around it by splitting
  the room the left column already has, rather than asking for more.
* The tab strip is constant chrome on every screen, so the left column loses its
  strip height on targets that will never look at a texture — **31px measured**, out
  of the inspector's share of the row and never out of `budget`. If it proves to
  matter the strip can become target-kind conditional, at the price of the row
  re-flowing on navigation.

### What the build revealed that the design did not

**1. `_TAB_STRIP_H` is a FLOOR, not a height.** An `HBoxContainer` of `Button`s
carries its own font/padding minimum — **31px against the 26 constant** — and a
Container cannot shrink below its minimum, so assigning the constant did not make
the strip 26 tall, it made it *overhang the rect by 5px and land on the inspector*.
`EffectStudioFramesetLayoutTest` caught it as "the inspector abuts the tab strip
exactly (strip bottom 231, inspector top 226)". The page already had this exact
pattern for `PathBar.bar_height()`, whose comment says so in as many words; this is
its second copy, and a third should become one helper.

**2. Hiding the inspector does NOT zero its content height** — the engine detail the
whole tab bets on, and it was asserted rather than assumed. `content_height()` reads
`_content.get_combined_minimum_size().y` live, and the Texture tab hides `_inspector`
outright. Godot's container minimums skip invisible CHILDREN; hiding an ANCESTOR does
not propagate. Had it propagated, the row would have collapsed the instant the tab
opened. Guarded by `content_height_survives_hiding`.

**3. The declared-width discipline is NOT observable at the dev body, and the guard
that claimed to prove it was vacuous.** Measured: body 1241, declared content width
457, the texture panel's live minimum 579. `column_width`'s leftover clamp is
`row_w - content_w - gutter` ≈ 650 against a column that only ever wants 276 — **so
the clamp does not bind, and reverting dec. 3 entirely leaves the test green.** The
A/B caught this (`[[ab-revert-of-a-shared-helper-proves-nothing]]`), and the guard
now asserts the stake on the pure function at a 700px row, where the two inputs give
**227 vs 105** — a 122px difference. The discipline is real protection for a narrow
window, not for this one, and the ADR says so rather than implying otherwise.

**4. A height floor is the same bug as a member list, rotated ninety degrees.**
The `ScrollContainer` that fixed the invisible picture was followed by a 272px
`custom_minimum_size.y` on the canvas — added so a sheet would draw in a short row,
and it re-created the identical overflow on the other axis: a floor inside the
`PanelContainer` raises its combined minimum, a Container cannot shrink below its
minimum, and at a 507px body the panel ran **59px into the timeline**. There is now
deliberately NO height floor; the canvas takes the row's height and the sheet pans,
which is ADR-0098's ruling anyway.

**5. `panel.encloses(sheet)` was the WRONG predicate** and had to be weakened to be
correct. A 256-tall sheet in a 237px row overflows *on purpose* — the viewport opens
at 100% and the author pans — so containment fails the layout working. The defect
being guarded is the sheet drawn ENTIRELY off the panel (centred at y=1079 in a row
ending at 950), so the assertion is now *overlaps* **and** *centre inside*: both hold
when it merely overflows, neither holds when it is gone. Re-A/B'd red.

**6. The audit undercounted surface #3.** See dec. 6 — it was two call sites, and a
third target kind was already filtering it back out downstream.

### Amended 2026-08-20 — the width was the same bug a THIRD time, and finding 4 named it

The author, on the shipped tab: *"when I am on the texture page a bunch of the text
is cut off […] also — can we get the texture defaulted to a reasonable size when we
open the texture page? it starts kind of small."* Two complaints, two decisions.

**7. `CANVAS_W` is a PREFERENCE, not a floor — the third instance of finding 4.**
Declaring 560 as the canvas's `custom_minimum_size.x` put this panel's combined
minimum at **864** (560 + `DECLARED_SIDE_W` 300 + 4 of chrome). `_relayout` hands
the left column the row's leftover, measured **727 / 776 / 812** across the three
column-bearing target kinds at a 1187px body — and a Container cannot shrink below
its minimum, so the panel did not narrow: it overflowed RIGHT by up to **129px**, and
`_sequence_panel`, added to `_body` later and therefore drawn on top, sliced the
facts column off mid-word.

This is finding 4's mechanism exactly, on the axis nobody had checked. The
`ScrollContainer` fixed it vertically for the member list; the height floor
re-created it vertically for the canvas; `CANVAS_W` had it horizontally all along
and shipped. The fix: `TextureTabPanel.set_slot_width(slot)`, called by `_relayout`
**before** it assigns `.size`, re-derives the canvas's minimum as
`min(CANVAS_W, max(CANVAS_MIN_W, slot − DECLARED_SIDE_W − chrome))`. The facts keep
their declared 300 and the picture absorbs the deficit, because the picture is the
one of the two that pans and zooms and can therefore honestly give width up.

The ordering is the whole fix and is easy to get wrong: `Control.size` **clamps up**
to the combined minimum, so a panel asked for 776 with an 864 minimum reports 864
and nothing anywhere records that it refused. The page has to *state* the slot; the
panel cannot infer it from a size that has already been clamped.

Below `CANVAS_MIN_W + DECLARED_SIDE_W + chrome` (~448) there is no split that fits
and the panel overflows again. That is stated rather than papered over — shrinking
the picture past the narrowest sheet in the corpus at 100% would trade away the one
thing this surface exists to show.

**8. The opening scale is a property of the SURFACE.** See ADR-0098 dec. 2's second
amendment for the ruling and its table. The tab sets `open_at_fit`; the frame screen
does not.

**9. The guard could not redden at the body the harness was given, twice over, and
the second dodge was worse than the first.** The new horizontal predicate reddens by
129/80/44px at a 1187px body — and the compositor also hands this harness **2272**,
where the leftover clears 864 outright and reverting the fix leaves every live
assertion green. Verified, not feared: that is what the first A/B did.

Narrowing the window to force the bind was tried and **reverted**. The only lever
that works on a tiling WM is `content_scale_factor`, and `DebugOverlay` persists it
to `user_settings.json` as `ui_scale` — both on shutdown *and* on every
`window_geometry_changed`, which this WM fires mid-run. Three runs compounded it far
enough to hand the page a **zero-height body**. A guard may not edit the author's
settings to make itself bind. (The same leak had been in
`EffectStudioTextureTabShot` since it was written, quietly resetting the dashboard's
UI Scale to 0.55 on every shoot; it now restores and writes back.)

What replaced it reddens at any body width: **poison the canvas's minimum, force a
flow, and assert it came back re-derived.** That asserts the call site directly,
which is the thing a wide window makes invisible. A second live pass drives the real
panel at the four slots `_relayout` actually assigns, and the pure split is asserted
over nine widths. Two different reverts redden different guards: dropping the call
site reddens only the live three; gutting the split rule reddens ten.

**10. The row's HEIGHT can be unrepresentable, and the vertical predicate now says
so.** Consecutive runs measured bodies of **163** and **514**; at 163 the inspector
row is shorter than this panel's own irreducible minimum (54px — two Labels and the
PanelContainer's padding, canvas at zero), so no layout satisfies "the panel fits the
row" and the assertion was testing the window manager. It now skips *with the
numbers*, the pattern `EffectStudioFramesetLayoutTest` already uses.

### Amended 2026-08-21 — what the overlay's own guards found

**11. `SCROLL_MODE_DISABLED` folds the CONTENT'S minimum width into the container's.**
The overlay declares `OVERLAY_W` (248) and came out **315** wide. The cause is one
un-wrapped Label built by a *different file*: `FramesetRegionScope`'s blast-radius line
("30 frames in this region — all will move") reports its whole text run as its minimum,
~250px, and a disabled horizontal scroll passes that straight up into the overlay's
minimum — where `Control.size` clamps up to it and the declared ceiling is not a ceiling
at all. `SHOW_NEVER` keeps the minimum at zero, so `OVERLAY_W` is real and no fact can
ever widen the box; the Label now autowraps as well, so nothing needs the horizontal
scroll in practice. **Caught by the new width assertion on the first run**, which is the
first time this surface's arithmetic has been caught by something other than the author.

**12. An autowrapping Label's minimum HEIGHT is a function of the width it was last
laid out at.** On a hidden or mid-flow overlay the facts measure at a narrow width and
ask for a wildly tall box — **966px against a 316px settled value**, measured on the
Texture page's shot. The next flow corrects it. The 60% height cap of dec. 11c is
therefore doing two jobs: it is the answer to the thirty-member trap *and* it bounds
this transient so the wrong value is never large enough to be seen.

**13. `overlay_rect` placed the overlay one pad off the TOP-LEFT corner at a 0x0
port** — which is not hypothetical: the tab is built before `_relayout` ever runs, so
that is its real first placement. Bottom-right arithmetic on a zero port goes negative.
Found by the pure guard's degenerate-port case, not by a window.

**14. Per-node theme overrides style only the nodes this file creates.** The overlay's
11px font was applied per-Label and missed every control built elsewhere —
`FramesetRegionScope`'s summary and member list rendered at the dashboard's full body
size inside an 11px box, and the blast-radius line was visually the loudest thing in
the overlay. A `Theme` set on the overlay propagates to every descendant, including the
ones this file never touches. **Found by screenshot with the suite green** — the fourth
time on this surface.

**15. The fold shipped reachable-in-principle and unusable in fact — dec. 11c's own
question, on a third axis.** The author: *"it seems like I can close the but can't reopen
it."* The toggle was a **17px flat chevron** beside a plain caption Label: a Button with no
border and no background, one glyph wide, sitting next to the text that looks like the
obvious place to click and was inert. `⌃`/`⌄` (U+2303/2304) are also not glyphs this
theme's font is known to carry. Every assertion was green throughout, because the fold
state round-tripped perfectly when driven through `set_folded` — **which was never the
broken half**. This is exactly what `cbe359478` found on ⬥ and what dec. 11c pre-empted for
Export/Import, arriving a third time on the one control those two did not cover.

The fix is the studio's own collapsible idiom, not a new one: `EffectKeyframeInspector`
builds a flat, left-aligned, `toggle_mode` Button whose text is `"▾  title"` / `"▸  title"`,
and `▾`/`▸` are already used in five places in this package. **The whole header is the
button**, so the target is the full 236px row in both states — measured; the old chevron
was 7% of the overlay's width and the guard reddens on it by an order of magnitude. The
header is `clip_text` for the reason that file records at its own header: a Button's TEXT
sets its minimum width, and the header is the one control NOT inside the width-absorbing
scroll of finding 11.

**A synthetic mouse click is deliberately not asserted.** `Viewport.push_input` transforms
by `get_final_transform().affine_inverse()`, the dashboard is a separate Window with its own
`content_scale_factor`, and a point read off `get_global_rect()` — pushed both raw and
pre-transformed — found **no control at all**, not even the 1564px canvas.
`gui_get_hovered_control` cannot arbitrate either: it returns null for synthetic input
because `_gui_update_mouse_over` early-returns unless `gui.mouse_in_viewport`, which only a
real OS mouse-enter sets. It is also not the open question — the author *could* fold, so the
press demonstrably reaches a Button inside this overlay through the canvas's
`MOUSE_FILTER_STOP`. The target was the defect, so the target is what is measured.

**16. The fold's height RATIO is not expressible on every port.** `shut_h <= open_h * 0.4`
reddened on working code when the compositor handed the harness a **150px** port: at that
size `OVERLAY_MAX_H_FRACTION` clamps the OPEN overlay to 90, so the ratio measures the
clamp, not the fold. Split into a port-independent claim (folding leaves the header row
plus margins — true at every port) and a ratio that skips *with the numbers* when the open
overlay is clamped. Third time this file has learned this on a compositor-chosen body.
