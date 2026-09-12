# A timeline boundary is one stored number grabbed from either side, and a drag consumes empty space but never authored work

**Status: SUPERSEDED (2026-08-21) by [ADR-0086](0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)
decs. 22-23 — a hold's boundary grip has two owners: what it WRITES and what it SPEAKS FOR.**

Both ADRs answer the same reported bug: a boundary you cannot reach because a hidden
[spacer](../context/16-effect-studio-authoring-tool.md) owns it. They were designed independently, about 22 hours apart
(this one 2026-08-18, ADR-0086 decs. 22-23 on 2026-08-19), on two branches, and the
mechanisms are alternatives rather than layers:

| | this ADR | ADR-0086 decs. 22-23 |
|---|---|---|
| grips per span | two — left and right | one, the right edge |
| reaching a hidden hold's boundary | the band SPLITS at the line; grab either side | the grip carries TWO identities — its **write owner** and who it **speaks for** |

ADR-0086's rule is the one that shipped on the integration branch and is the one the code
implements. This document is kept rather than deleted because its **consume law** — that a
drag may absorb empty space but never authored work — is the part both designs share, and
because a reader who finds the two-sided vocabulary in an old commit deserves to land here
and be told which way it went. Its build (`BoundaryDragPlan`, the two-sided grip layout and
their three suites) was removed when this branch merged down.

*Original status: accepted (design settled via `/grill-with-docs` 2026-08-18; `/tdd` build
pending).*

## Context

Every editable lane in the Effect Studio score — camera, palette, screen, particle — ships a
**boundary grip**: a 9 px grab band centred on a span's **right** edge that re-times it
(`EffectScoreTimeline._edge_rects`, `EffectStudioPage._edge_field_ref`). ADR-0086 dec. 11 fixed
"one grip per span, right edge only" with a correct argument: *a left edge is always the
neighbour's right edge or the pinned frame-0 origin, so a left grip would be a second handle on
one byte.*

That argument is about **storage**, and it stays true. But the author reports it as a missing
capability, and they are right:

> "There are only resize handles on the right of events. There should be handles on both sides so
> I can grow an event leftward into the empty space beside it."

The gap is not storage, it is **reach**. On a colour lane the space to the left of an event is
usually a **spacer** (ADR-0087 decs. 23-28) — invisible empty space that is *not selectable*.
So the boundary between the spacer and the event you want to grow **exists**, and is stored as the
spacer's `boundary_end`, but there is **no way to grab it**: the only tile carrying a grip there is
the spacer, and a spacer is unclickable by design. The author sees an event with empty space beside
it and no handle on the side facing the space.

A second, sharper limitation surfaced while settling this: **two events can never be made
adjacent.** Colour durations lower to `time_value × 8` with a 1-frame floor
(`ColorLowering` — zero-length is not encodable), and a boundary drag *clamps* against its
neighbour at that 1-frame minimum. So an author closing a gap between two events always leaves a
1-frame spacer behind, and there is no verb that removes it (a spacer is not selectable, so there
is nothing to delete). "Close this gap" is simply not expressible today.

ADR-0089 already solved the same problem on the particle lane, and named the law:
*"An edit only ever consumes or creates gap (null-span) space; it never changes another **drawn**
span's extent. Gaps are the currency; drawn bursts are walls."* A particle grow **consumes** the
adjacent gap and reclaims its slot. Colour lanes never got that generalization, because their
"gaps" are spacers — real keyframes that merely render as nothing.

## Decision

**A boundary is one stored number, grabbable from either side, and a drag consumes empty space but
never authored work.** Three parts.

### 1. The grip band splits at the boundary; both halves address the same field

The existing 9 px band stays **centred on the boundary line**. It is split down the middle (the
DAW convention): grabbing **left of the line** makes the **left** tile the selection/inspection
root; grabbing **right of the line** makes the **right** tile the root. **Either grab writes the
same field** — the *left* tile's right-edge address (palette/screen `boundary_end` at
`event_index = k−1`; camera the previous span's `end_frame`; particle `kf[n−1].time`). There is
still exactly one stored number per boundary; ADR-0086 dec. 11's "two-handles-one-byte" objection is
honoured. What changed is that the number is now **reachable from the tile on either side of it**.

A synthetic `boundary_start` field per encoder was **rejected** — that *is* the second handle
ADR-0086 dec. 13 forbade, and it would fork every channel's clamp math.

The band is **not** inset inside the tiles. At low zoom a 1-frame stub is a couple of pixels wide;
insetting would swallow its entire interior and kill click-to-select. Centred also means the two
halves are symmetric, so "which side did I grab" is decided by the cursor, not by tile widths.

When the grabbed side is **invisible** (a hidden spacer, a particle gap) the grip falls back to
the other side as the inspection root — see 2.

### 2. Grips belong only to visible tiles

Today `_edge_rects` is built for **every** span with no visibility filter, so hovering over empty
space already paints a phantom grip in the void. That goes away: a hidden spacer and a particle gap
**own no grips**. Their boundaries are still fully reachable — from the visible tile on the other
side, which is the whole point of the split band.

Editable-boundary floors are mirrored from the encoders into layout, so a grip is never drawn on a
boundary the encoder will refuse:

| lane | left grip exists for |
|---|---|
| palette / screen | `k ≥ 1` (`k = 0`'s left edge is the phase origin) |
| particle | `k ≥ 2` (`ParticleTimelineChannel._apply_boundary` refuses `n ≤ 0` — `kf[0]` is the pinned phase origin) |
| camera | sub-channel ordinal `≥ 1` |

Selection draws **both** of the selected span's grips; hover draws only the grip under the cursor.
The glyph is identical on both sides. (ADR-0086 dec. 24 already rejected always-draw-all: it "would pepper
every fully-tiled tile".) `_hover_edge_id` therefore becomes a `(span_id, side)` pair.

### 3. A drag CONSUMES invisible tiles and CLAMPS against visible ones

This is the law ADR-0089 wrote for particle gaps, generalized to colour-lane spacers:

- **Invisible tiles are consumed.** A drag that crosses a hidden spacer (colour) or an
  `emitter_id 0` gap (particle) **absorbs it**, and the keyframe slot is reclaimed. It cascades:
  the clamp bound is the far edge of the whole **run** of consecutive invisible tiles — i.e. the
  nearest **visible** tile.
- **Visible tiles are walls.** A drag clamps against a real event, against a
  **deliberately-disabled / hatched** event (authored, *"muted, not gone"* — ADR-0087 fifth
  amendment decision 4), and against every camera span (camera is fully tiled with no invisible
  tiles, so its behaviour is **unchanged**).
- The shipped colour trade still **shrinks a visible neighbour to its 1-frame minimum** — colour
  lanes have no "wall" concept in ADR-0089's sense. What this decision adds is that the resulting
  1-frame *spacer* can now be swallowed. A visible tile can be shrunk; it cannot be deleted by a
  drag.

The principle in one line: **empty space isn't data.** Consuming it is a re-timing, not a
deletion — which is exactly why "clamp, never delete" (ADR-0086 dec. 12) is not violated.

**Consume is symmetric.** Right-edge drags consume too. This is a behaviour change to a shipped
gesture, taken deliberately: otherwise "can I close this gap?" would depend on which of the two
events the author happened to grab.

**Ripple is honoured on both sides.** Same pixel = same edit; only the inspected tile differs.
Ripple is default-off, so the reported use case gets the sum-preserving trade out of the box.
Stripping ripple from left drags was rejected — it would make the two halves of one band behave
differently.

### 4. A consuming drag is one undo, and is self-inverse while held

Two properties, both required for direct manipulation to feel honest:

1. **One drag = one undo**, restoring consumed spacers byte-exact. Already delivered by the
   shipped machinery: `EffectEditSession.apply_edit` captures a **channel snapshot before dispatch**
   for structural-capable boundary edits, and the drag coalesce *"keeps the FIRST stash: one drag
   bracket = one undo entry whose restore is the pre-DRAG table."* Colour boundary edits join
   particle in taking that snapshot path, because a consume is now structural there too.

2. **Drag past a spacer, drag back, the spacer returns.** The mechanism is **pristine re-plan per
   motion**: while a coalesce bracket is active, `EffectEditSession` **restores the drag's first
   snapshot before each re-dispatch**, so every motion is planned against the pre-drag state
   instead of compounding on the previous motion's structural side effects. (~5 lines, gated on an
   active coalesce; the same shape `move_preview` already uses for the particle body-drag.)

**This rule applies uniformly** to any coalesced drag on a channel that already snapshots — so
today's **particle** resize becomes self-inverse too. That is a deliberate behaviour change to
shipped code: today a particle grow that consumes a gap cannot be undone by dragging back within
the gesture; the only recovery is abandoning the whole drag. Making it uniform is what stops colour
and particle drifting into two dialects of the same gesture.

The rejected alternative was **mirroring particle exactly** — consume/reclaim incrementally inside
each encoder, zero session changes. Cheaper, but a consume would be irreversible within the
gesture, and it would have locked the studio into "the encoder decides how a drag remembers,"
which is the wrong owner.

## Consequences

- **`edge_drag_started` / `edge_dragged` / `edge_drag_ended` gain a `side` argument.** The page's
  `_edge_field_ref` subtracts 1 from the index when the side is left. Storage knowledge (raw index
  vs camera ordinal, pinned-origin floors) stays in the **page**; the timeline reports **pixels +
  side** and nothing else. Three signal signatures change, so the wiring and acceptance guards move
  with them.
- **The consume/clamp decision is a pure plan**, computed off the keyframe array with no scene —
  which is what makes the run-cascade, the disabled-event wall, and the pinned-origin floors
  guardable without a paint.
- **`_span_rects` keeps hidden spacers** (the right-click → *Add event here* gap context depends on
  it). Only the **painter**, the **select hit-test**, and now the **grip layout** skip them. Do not
  "clean that up."
- **ADR-0086 dec. 11's "one grip per span, right edge only"** is superseded on the reach question and
  upheld on the storage question. ADR-0089's *"gaps are the currency; drawn bursts are walls"*
  is **generalized to colour-lane spacers**, and its Resize bullet's "the origin has no grip"
  becomes the `k ≥ 2` floor rather than a right-edge-only rule.
- **Particle drags change behaviour** (self-inverse within the gesture). The existing particle
  drag-preview guards must be re-read with that in mind — a test that asserts a consumed gap stays
  consumed after dragging back is now asserting the old dialect.
- **The residual honesty case is left alone** (no new chrome): an event whose bytes are a *genuine*
  no-op still correctly vanishes on deselect. The law stands as ratified in ADR-0087's fifth
  amendment; see its sixth amendment for why that used to look like a bug.
