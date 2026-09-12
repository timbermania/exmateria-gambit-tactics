# A colour span moves at frame granularity by spending keyframe slots

## Status

Accepted.

Verified 2026-08-28 — decs. 1–9 built and guarded. `ColorLowering.trade_durations`
is the trade's own chooser and `clamp_boundary_duration` is gone from the tree;
`ColourMovePlan.plan(durations, holds, n, delta, free_slots)` carries no
`manufacture_*` licence and no `lead_growable` / `trail_growable`;
`_new_identity_keyframe` is the padding where a hold run is empty; the Move arms on
all three lane kinds, and the four surviving mentions of the deleted
`_manufactured_hold_is_inert` are prose recording why it went. Ten test files carry
it — see **Verification**.

## Context

An author reported two faults on the palette / screen lanes, both absent on
camera. Diagnosing them turned up one shared cause and one shared currency.

### The encoding: a colour span's length is 1, or a multiple of 8

Each colour keyframe stores one `time_value` (s16), decoded by the runtime as
`duration_frames = time_value × 8`, with `time_value == 0` meaning **1 frame**
(`ColorLowering`, and independently `research/tools/build_trap_effect.py:533` —
*"Duration = time_value << 3 (time_value=0 -> duration=1)"*). So the storable
lengths are

```
F = { 1, 8, 16, 24, 32, … }
```

and nothing between 2 and 7, or 9 and 15, exists. Camera stores an absolute
`end_frame` and is subject to none of this — which is why every symptom below is
colour-only.

### Fault 1 — the sum-preserving trade did not preserve the sum

`PaletteChannel._apply_boundary` (and `ScreenChannel._apply_boundary`) handed the
neighbour `total - new_dur_n` **as if it were storable**. It frequently is not, and
`_set_duration` silently re-snapped it:

| A (hold) | B (drawn) | desired | → A′ | B asked | B′ | far-edge drift |
|---|---|---|---|---|---|---|
| 8 | 24 | 0 | 1 | 31 | 32 | **+1** |
| 8 | 8 | 0 | 1 | 15 | 16 | **+1** |
| 16 | 32 | 0 | 1 | 47 | 48 | **+1** |

Swept over every pair in `{1, 8…64}` × every drag position, the far edge drifted
by ±1 frame in **~13%** of positions. It fired exactly when either span landed on
the 1-frame minimum, because then the residual is one away from a multiple of 8
and **no storable length can absorb it**. The author saw *"drag the left side to
the first frame snap and both the left AND right sides move"* — and worse than the
table suggests, because the drag mutated in place, so `total` was recomputed from
already-edited durations and the error re-entered on every mouse motion.

### Fault 2 — Move was never wired on colour

The body-drag machinery existed in full (ADR-0089 particle Move: the signals, the
single-snapshot undo bracket, the per-frame pending flush, the deferred refold),
but arming was hard-gated on `begins_with("particle:")`. Colour and camera never
armed it, so a colour span could only be repositioned by trading its boundaries one
at a time.

### The currency: 33 slots, and real data is against the ceiling

A colour track is a **fixed-size** on-disk structure. The track stride confirms it
exactly: `0x04B4 − 0x03EC = 200 = 33×2 (time_values) + 33×3 (rgb) + 33 (ctrl) +
2 (max_keyframe)`. Thirty-three slots, always present, mostly dead.
`EffectScoreModel` mirrors the PSX stepper, which breaks at `max_keyframe − 1`:

```
played spans = max_keyframe − 1        free slots = 33 − max_keyframe
```

`keyframes.size()` is **always 33** on loaded data (the parser hands back the whole
fixed slot array), so the budget is `33 − max_keyframe` and never anything derived
from the array's length. Measured over all **4812** palette + screen channels in
the corpus:

| free slots | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| channels | 28 | 8 | 15 | 5 | 6 | 4 | 24 | 4 | 10 | 27 | 13 |

**90 channels (1.9%) have fewer than 8 free slots.** Twenty-eight have exactly one.
The ceiling is real and reached by shipped ROM data.

### The arithmetic that makes frame granularity possible at all

The author's insight — *"spacers can be reduced to just a series of 1 frame gaps"* —
is correct, and it is the only thing that makes sub-8 positioning representable. Its
cost is **forced, not chosen**: any sum of multiples of 8 is a multiple of 8, so a
hold region of length `L` with `L mod 8 = b` needs **exactly `b` one-frame
keyframes**, plus one carrying the `8a` remainder. No cleverer encoding exists.

> **A non-multiple-of-8 slide costs at most 8 keyframe slots. Whatever the delta.**
> Less when the hold region already spans several keyframes that can be re-lengthed
> instead of inserted — and nothing at all when it re-merges padding an earlier
> slide inserted.

## Decision

1. **The boundary trade freezes the far edge.** A colour boundary drag preserves
   `total = dur_n + dur_{n+1}` *exactly*. Both halves must be storable lengths, so
   the drag offers only boundary positions where they are — the rest are **not
   offered**, and the handle visibly skips them. An exact pair **always exists**, so
   the freeze never needs a drifting fallback: a trade's `total` is by construction
   the sum of two storable lengths, the current pair being its own witness, and of
   every total so reachable, **zero** lack an exact pair. The trade therefore gets
   its own chooser, `ColorLowering.trade_durations`, rather than borrowing
   `split_durations` — that verb cuts a **single** stored span, where 1 and 8
   genuinely have no faithful pair. A tie between two offered positions goes to the
   **longer** first span, matching `time_value_for_duration`'s round-half-up, so the
   typed Duration row and the drag agree and a typed `20` on a `16+16` pair still
   reads `24`. Only the far edge changes; the quantization convention does not.
2. **Trades are therefore 8-grained, and that is accepted.** On a total that is a
   clean multiple of 8 the 1-frame squeeze is not reachable by dragging: `8+24`
   offers `{8, 16, 24}`, not `{1, 8, 16, 24, 32}`. Fine positioning is not the
   trade's job — it is decisions 3–5. Two gestures, two granularities, each honest
   about what it can represent.
3. **Move on a colour lane is slide-in-place**, mirroring ADR-0089's `plan_move`:
   one clamped delta shifts **both** of the span's boundaries, its width is
   preserved, the hold in front gives up `d` frames and the hold behind takes them,
   and everything outside the two immediate neighbours stays pinned at its absolute
   frame. Armed on **palette, screen and camera**.

   A colour lane has no gaps — it is **fully tiled**, and its only empty space is a
   hold run — so the refusal is the decision's literal one: a span **wedged between
   two drawn tweens**, with a hold on *neither* side, has no frames to trade and is
   refused. **One hold is enough.** The span slides toward it and the side that must
   grow is grown from nothing, which is decision 6's job. Requiring a hold on *both*
   sides would reach 50 of the 2637 drawn palette + screen spans in the corpus
   (1.9%) — see Considered options.

   **Camera manufactures its own holds and pays nothing.** `MAP` + a zero value is a
   hold by the local predicate (ADR-0086 dec. 15): it resolves
   `to == from` under every interpolation, so it is invisible by construction with no
   fold to ask. A camera span next to a drawn tween — including **event 0**, whose
   neighbour is the phase origin — slides by inserting a `MAP`+0 event that owns the
   vacated space. Left is still a wall for event 0: there is nothing before frame 0
   to give up.
4. **A fine move is priced, and degrades when broke.** `free_slots ≥ 8` is a
   **worst-case bound**, not a price, and it is not a gate: every rung is priced,
   exact delta first, and the affordability check decides. Where the exact delta is
   affordable the drag is frame-granular; where it is not, the drag **falls back to
   multiple-of-8 deltas** (which cost nothing) rather than refusing. The author
   always gets a move — sometimes a coarser one.

   Pricing rather than gating is what makes Move two-way. A fine slide spends the
   slots that licensed it, and `EffectEditSession.begin_move` recomputes the budget
   at **every grab**, so a gate on the bound made the return trip re-read a budget
   now under 8 and refuse to offer the frame the span came from. The return's own
   cost is **negative** — it re-merges exactly the padding the out trip inserted —
   so it is always affordable. **6.6% of the 1725 shipped colour channels with more
   than one played tile sit in the trap band** (8–15 free slots): fine now, broke the
   moment they are used.
5. **The tell is the handle's own motion.** No new chrome. In fine mode the span
   tracks the cursor frame by frame; in coarse mode it visibly snaps in eights. The
   distinction is unmissable on the first mouse move and cannot go stale. The exact
   number stays where it already lives, on the inspector's Duration row.
6. **Padding is a copy of the adjacent hold, or a minted identity where there is
   none.** Where the run has a real adjacent hold, padding is a **copy** of it:
   byte-shaped like the shipped data it extends, verdict-preserving by construction,
   and free. Where the run is **empty** there is nothing to copy, and the pad is a
   minted `_new_identity_keyframe` — an **enabled Δ0 identity** (rgb 0, blend mode 0,
   ctrl `0x80`) that lowers to "current + 0", a per-frame visual no-op whatever it
   sits next to. This is the shape the screen arm's padding and `insert_event`'s
   null-tween seed already used.

   Never `_new_disabled_keyframe`. The disabled shape is **already spoken for**:
   `insert_event` and `_insert_spacer_stub` seed the author's born-disabled Add stub
   with exactly those bytes, so hiding disabled zero keyframes would make every
   freshly-Added colour event vanish the moment it lost selection — the precise
   failure ADR-0087 dec. 27 exists to prevent. (`is_hidden_spacer`
   requires **both** `spacer` and not-`enabled`, so disabled padding draws as hatched
   tiles — "muted, not gone", ADR-0087 dec. 26.) An enabled Δ0
   needs no new predicate at all: the painter already hides it and `_hold_flags`
   already calls it a hold, so painter and planner agree without a carve-out to keep
   in sync.

   Minting is also what lets the planner stop reading a lane its own edit is about to
   invalidate: a minted pad is inert by construction, so there is no licence to
   measure and no trial insert to run.
7. **Dragging into a hold run collapses it and deletes the emptied keyframes**,
   freeing their slots (which helps fund decision 4). A hold's 1-frame floor bounds a
   *keyframe*, not a *region*: a run of `k` holds may shrink to `k` frames and then
   vanish entirely, letting the span butt against the previous drawn tween. Index 0
   is not special — a minted Δ0 identity carries no claim about when the tint
   arrives, so a span there grows a lead like anywhere else.
8. **`insert_event` enforces the 33-slot cap.** The budget is a first-class
   quantity, so the cap is a precondition the verbs check rather than a fact the
   writer discovers downstream.
9. **The gesture is structure-free: the splice runs once, on release.** A colour
   motion **plans and stops**. Decisions 6 and 7 — minting a pad, deleting an emptied
   run — fire once, into the lane the author releases onto, not on every frame of
   cursor travel. Mid-drag the model is byte-identical across motions: nothing is
   minted or deleted, the lane is not renumbered, and the fold is not re-run. The
   pristine grab address (`_body_drag_ref`) stays — it is what makes the frozen
   context correct — but `EffectStudioPage._follow_structural_move` now has one
   renumber to chase instead of a moving target, and runs once on the hint `end_move`
   returns. The discrete verb is unchanged: one release-time splice equals
   `move_span`'s own result. Full rationale, measurements and the seam are in
   **[ADR-0089](0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)**'s
   2026-08-20 amendment.

## Considered options

**Ripple move (only the preceding hold changes, everything downstream slides).**
Never refuses, never wedged, and costs at most one side's padding instead of two.
Rejected: it re-times the whole rest of the lane, the exact opposite of the
far-edge-freeze invariant decision 1 establishes. Two gestures in the same subsystem
should not disagree about whether downstream is pinned.

**Slide-in-place that manufactures holds out of drawn neighbours.** A span is never
stuck, at the price of a Move silently shortening a visible tween next to the thing
being moved. Rejected: a move must not change what is rendered.

**Never auto-spend slots (Move is strictly 8-grained everywhere).** Predictable and
cheap, and it does not deliver the drag-at-one-frame feel that motivated the work.

**Spend freely but refuse when broke.** Consistent with `plan_move`'s wedged-refusal
vocabulary, but it makes 1.9% of channels reject an ordinary gesture with an
explanation about storage the author should not have to hold in their head.
Coarsening degrades; refusing blocks.

**Accept the ±1 drift and merely surface it** (fault 1). Cheapest, and rejected
outright: the right edge still moves, which is the reported symptom.

**The strict reading of decision 3 — a hold on BOTH sides, mirroring particle
exactly.** One predicate away (`ColourMovePlan.plan`'s growability becomes
`left_count > 0` / `right_count > 0`). Rejected on reach: only 50 of 2637 drawn
colour spans (1.9%) qualify, and a sampled sweep of 505 drawn spans yields **2**
movable under it against **88 (17%)** under the shipped reading — of which **86**
need a manufactured pad. It would make Move a gesture for content this Studio
authored rather than for shipped ROM data.

**A DISABLED null pad.** Built first, and reversed the same day. It is inert at the
*hardware* level (`PaletteSubsystem._each_keyframe` makes no apply call at all),
which is stronger — but those bytes are the Add stub's, so teaching the painter to
hide them made every freshly-Added colour event vanish on deselect. Caught by
`EffectSpacerProjectionTest`, **not** by the corpus census that preceded it: of
10664 played palette keyframes, 287 are disabled and only **15** (0.14%, all
`ctrl == 0`) are zero-tint. The population that mattered was the one this Studio
mints itself.

**A copy of the keyframe at the insertion point, where the run is empty.** Shipped,
then replaced by minting on 2026-08-19. Such a copy is inert only ~92% of the time
(**368 of 400** probed palette keyframes), so it needed a fold-measured licence and
a trial insert per grab — a planner reading, once per gesture, a lane its own edit
was about to invalidate. Worse, the licence probed one 8-frame copy while the splice
writes as many one-frame copies as the residual needs, so the padding could read
back **drawn** and the Move changed what is rendered. Minting removed the question
instead of repairing the probe, and retired the index-0 exclusion with it: the only
padding that ever had to be refused before span 0 was "a copy of itself placed
before it".

## Consequences

- The colour boundary trade has an exact invariant — `total` is conserved — which
  also removes the per-motion compounding the in-place drag had.
- Colour boundary drags are coarser and more truthful: fewer reachable positions,
  every one of them exactly what it shows.
- Move is the fine-positioning gesture across three lane kinds, with one semantics
  inherited from particle.
- Colour authoring has a **budget**. Repositioning can fail for a reason that is
  neither geometric nor semantic but *storage*, on 1.9% of real channels. Decision
  5's tell and decision 7's slot recovery are what keep that from being mysterious.
- The corpus figures in this ADR (drift %, free-slot histogram, the 8-slot bound)
  are the regression targets, re-measured by the sweeps rather than quoted.
- `clamp_boundary_duration` is **retired** by decision 1 — it existed only to snap a
  residual the trade must no longer compute, and its two callers were the two colour
  trades.
- Decision 9 makes the mid-drag preview pixel-identical to the committed lane, and
  removes the mid-gesture renumber that made a minted record's own edge grip steal
  the grab back. Insert and delete are separate verbs and still renumber mid-gesture.

## Verification

- `ColorLoweringTest` and `ColourBoundaryCorpusSweepTest` — decision 1's chooser on
  fixtures and over shipped data; `ColourBoundaryFarEdgeTest` and
  `ColourDragPristineTest` cover the far edge and the trade's idempotence.
- `ColourMoveTest` — decisions 3–7 on fixtures, including
  `_test_a_fine_slide_can_be_slid_straight_back` (decision 4's two-way pricing).
- `ColourMoveCorpusSweepTest` — five invariants asserted directly over shipped data
  (width preserved, everything outside the two runs pinned, the block's length
  conserved, every written length storable, the budget never exceeded), plus
  invariant 6 (the round trip) and the movability census, so the 17% figure is
  re-measured on every run.
- `ColourMovePadShapeTest` — decision 6's minted pad: its inertness in every length
  shape `_seq_for` can emit, the painter's verdict, and the Add stub's separateness
  end-to-end through the real verbs.
- `EffectColourMovePadAcceptanceTest` — headful, real E043, the real body-drag, with
  screenshots, because the author reports this by eye and a mechanized guard is
  necessary but never sufficient.
- `ColourStructureFreeDragTest` and `EffectStudioEdgeDragWiringTest` — decision 9:
  byte-identical keyframes across every motion, one release-time splice equal to the
  discrete verb's result, the cancelled-slide-is-a-click rule, and that the timeline
  still holds the **same score object** it held at grab. Both go red against pre-fix
  code by reverting `EffectEditSession._is_structure_free_move`.
- `EffectCameraMoveTest` and `CameraHoldClosureCorpusSweepTest` — the camera arm of
  decisions 3 and 7, including that an emptied lead hold is deleted rather than left
  at zero width.
- `ScoreReprojectReuseParityTest` compares the **axis** first: `rebuild_kind_lanes`
  and `build` share `_content_max_frame`, so a live drag can no longer stretch the
  ruler by counting a sound TERMINATOR (ADR-0085's 2026-08-10 amendment).

The sweep's ONE-WAY census is the ADR's own open-fault counter and prints on every
run. It stands at **3**, all one shape — see the register.

See ADR-0085 (the score model), ADR-0086 (camera lanes), ADR-0087 (colour tint as a
signed delta) and ADR-0089 (the Move gesture this one generalizes).
