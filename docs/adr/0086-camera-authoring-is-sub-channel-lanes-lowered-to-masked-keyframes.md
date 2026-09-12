# Camera authoring is three independent sub-channel lanes lowered to masked keyframes

**Status:** accepted. **Relates to:**
[ADR-0071](0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md)
(per-archetype projection) and
[ADR-0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
(inspection-target registry). Supersedes an in-progress "`channel_mask` as an editable
membership control" direction (#267 shipped it; this ADR removes it), and supersedes
[ADR-0095](0095-a-timeline-boundary-is-one-number-grabbable-from-either-side-and-a-drag-consumes-empty-space.md)
(a two-sided grip band, designed and **not** built — see `## Considered and rejected`).
The write-side vocabulary lives in
[CONTEXT.md → Sub-channel lane](../context/16-effect-studio-authoring-tool.md).

Verified 2026-08-28 — decisions 1–26 all built. Decision 26 was recorded as designed-only;
it has since shipped (`EffectEditSession._restore_coalesce_pristine`, guarded by
`ColourDragPristineTest`).

## Context

The camera channel stores a flat array of keyframes, each a single packed command word.
One keyframe carries a `channel_mask` (bits for angle / position / zoom), one
`source_mode`, one `interpolation`, one `end_frame`, plus `param`/`flags`, and drives
**every** sub-channel the mask selects with that one shared word. The runtime consumes
this by searching each sub-channel **independently** — `CameraSubsystem` calls
`_find_active_keyframe` once per `CHANNEL_ANGLE/POSITION/ZOOM` and skips any keyframe
whose mask bit is clear. Because the engine reads three tracks, `EffectScoreModel`
projects the one keyframe array into three per-sub-channel **lanes**, drawing a tile in
each lane whose mask bit is set.

The camera build (#267) exposed `channel_mask` as an editable **Channels** bitflags in
the inspector, reachable from any one of a keyframe's sub-channel tiles. That produced
the "backwards" bug: unchecking a sub-channel from inside its own tile clears the bit
that put the tile there, so the event **vanishes** from that lane; clearing the last bit
(`channel_mask == 0`) leaves a live keyframe that projects into **no** lane — an
un-reselectable **orphan**, still in the data, drawable by nothing.

The root cause is a **model** error, not a UI slip: the editable identity was the
per-sub-channel *span* (a projection), and `channel_mask` — which decides *how many
projections a keyframe has* — was exposed as if it were per-span content. The entity was
being defined by a projection of itself. The fix is to stop authoring the packed form at
all.

## Decision

**Camera has two models, and the author only ever touches the first.**

1. **The authoring model is three independent sub-channel lanes.** Angle, position and
   zoom are each an ordinary
   [fully-tiled lane](../context/16-effect-studio-authoring-tool.md) of ordinary lane
   events, edited in place. Each event owns its own `source_mode`, `interpolation`,
   `end_frame`, `param`, `flags` and its scalar value(s). Camera is **lane-event-atomic**
   like the other four channels: one event = one tile. There is no "membership", no
   cross-lane fan-out, and no `channel_mask` in the author's vocabulary.
2. **The storage model is packed masked keyframes**, a *compiled* form produced by
   [lowering](../context/16-effect-studio-authoring-tool.md). Parsing is the inverse: one
   masked keyframe expands to one event per set bit.
3. **Lowering is a coalescing compiler**, owned by `CameraChannel` / the E###.BIN encoder
   which already owns "lowering to bytes". It folds sub-channel events that **coincide
   and agree** — same `frame` + `source_mode` + `interpolation` + `param` + `flags` —
   into one masked keyframe, and **splits** them into separate keyframes when they
   disagree.
4. **Faithful guarantees semantic equivalence, not byte-identity.** A camera edit
   recompiles the whole camera section and patches that entire region into E###.BIN — not
   a surgical per-field byte diff. Faithful still validates
   [capacity](../context/16-effect-studio-authoring-tool.md) and quantization against the
   *compiled* keyframes; it does not promise that an irregular ROM packing survives an
   untouched round-trip.

### Addressing

5. **A camera sub-channel event is addressed by its ordinal within its lane** — the Nth
   angle / position / zoom event in `CameraLowering.parse(table)` order, never by the
   storage keyframe index it currently occupies. Because a structural edit re-runs `lower`
   and re-packs the array, a raw index goes stale after every split, merge or pad-drop; an
   ordinal does not, because `parse ↔ lower` preserve per-sub-channel order (`lower`
   canonicalizes to `end_frame` ascending, ties by lane-append order, and `parse` reads
   them back in that order and skips `mask == 0` slots). `parse` is the **single
   enumerator**: the ordinal is the event's index in `parse(table)[sub-channel]`, the
   score counts it over every mask-set keyframe so it matches even where a zero-width
   no-op emits no visible span, and the write path (`EffectScoreModel._camera_spans` →
   `CameraChannel`) resolves `(sub-channel, ordinal)` back to a keyframe via `origin_index` — which stays what it always was, *provenance for one
   lower pass*, never the address. Selection survives re-project and undo replays onto the
   right keyframe, so a structural camera edit **re-projects** rather than reloading the
   score. **Scope: camera only.** The other four channels are 1:1 with storage and keep
   `field_ref.event_index`; the `camera_compiled` lane is a read-only storage view and is raw-index
   by nature.
6. **Every address surface — `EffectScoreModel.keyframe_address` included — prints the
   token the span id carries**, so `<lane_id>#<N>`
   always reconstructs the id: the ordinal where a kind defines one, `keyframe_index`
   (which for the lane-event-atomic kinds *is* the ordinal) otherwise. A raw slot may be
   shown as `slot N` — it is what the compiled lane and a byte dump show, useful
   provenance, never an address. This is not cosmetic: an address printing the raw slot
   reconstructs to a **real span, the wrong one**, so a pasted address resolves silently
   instead of failing.

### Lane editing

7. **`insert_event` and `delete_event` are lane-editing verbs on the same
   `EffectEditSession` choke point** as `apply_edit` (#255). The author changes the lane's
   event *set*; `lower` decides packing — coalesce vs split — automatically, as it already
   does. One gesture serves five channels: right-click a lane row at a frame for a small
   context menu (Add here / Delete / Duplicate), matching Godot's own `AnimationTrackEdit`.
   Right-click **on** an existing event marker targets that event; on empty span or gap it
   Adds. The read-only `camera_compiled` lane is **inert** — it has no `field_ref`, so it
   authors nothing.
8. **Two lane shapes, one verb.** *Span lanes* — camera sub-channels, screen, palette —
   are fully-tiled `[prev_end, end)` from frame 0, so "add at frame F inside a span"
   **inserts a time boundary**, cutting the covering span in two. *Point lanes* — sound
   triggers — are instant markers with real gaps, so "add" **drops a new marker** in a
   gap. A fully unused sub-channel is an empty lane, and "add" **creates its first event**.
   Call the boundary cut **insert-waypoint** and reserve **de-coalesce** for the unrelated
   split in decision 3 (a sub-channel stops sharing a masked keyframe because a shared
   field diverged). They share the `parse → mutate lanes → lower` machinery but are
   different author intents and must read distinctly in code and tests.
9. **An inserted waypoint's seed is a visual no-op**: value = the camera state
   interpolated at F along the existing transition, command word inherited from the span
   being cut. The insert is invisible until the author drags the new waypoint. (Copying
   the *next* event's value instead would create a hold-then-jump.) Point-lane and
   empty-lane adds seed from lane defaults. Because an inserted boundary is a *new*
   `end_frame` *between* existing ones, it can only auto-coalesce when F exactly equals a
   sibling's `end_frame` — which is the correct packing. Never assert an add worked by a
   "keyframe count grew" check; assert **semantically**, by parsing the lane and
   confirming the new event at its expected ordinal.
10. **Structural undo is snapshot-based.** `apply_edit`'s undo replays a scalar
    `before_raw`; insert/delete have no scalar inverse, so the choke point records a
    lane/table snapshot (or the explicit inverse verb) on the same stack Ctrl+Z drives.
    After an add, selection lands on the **new** event; after a delete, on its neighbour.
    Delete is the inverse of insert: removing a waypoint merges the adjacent spans,
    removing a point marker leaves a gap, removing the sole event empties the lane.
    Capacity is unchanged — an insert feeds `capacity_faithful` like any other lowering.

### The boundary drag

11. **A boundary drag is a single `end_frame` edit, and there is one grip per span, on
    the right edge only.** A span's start is *derived* from the previous event's
    `end_frame`, so the boundary between event *i* and *i+1* **is** a single stored
    number — event *i*'s `end_frame`. Dragging it is one `apply_edit`; the neighbour's
    start moves for free. A "left edge" is always the neighbour's right edge or the pinned
    frame-0 origin, so a left grip never exists; the **first** span's left edge is
    un-draggable, and the **last** span's right grip has no successor to trade against, so
    it resizes the lane tail and re-derives the score end marker
    (`EffectEndModel.derived_end_frame`). This is deliberately **not** the sound fire-drag:
    sound triggers are point events whose duration is only a next-fire gate, so a fire-drag
    trades two neighbouring gaps via `SoundGapMath` and lowers as a *compound* edit, while
    camera stores endpoints and the arithmetic collapses to one field. Reuse only the seam
    (report-don't-mutate intent → host applies → `relayout` reproject) and the
    handle-draw / hit-rect infrastructure — **do not** unify the two drag paths onto
    `SoundGapMath`.
12. **Clamp, never delete.** A drag is clamped strictly to `(prev_end, next_end)`, minimum
    one frame, so it never opens a gap (the fully-tiled law forbids one), never overlaps,
    and never manufactures a zero-width span (invisible, and it burns a keyframe slot).
    Over-dragging onto a neighbour is not an implicit delete; deletion stays the
    `delete_event` verb. Snap via `TimelineAxis.snap`.
13. **A drag is strictly per-sub-channel-lane.** Dragging the angle boundary moves only
    angle, even when a position or zoom boundary sits at the same frame because they were
    coalesced into one masked keyframe. `lower` re-splits or re-coalesces on save. Coupling
    coincident boundaries across lanes would resurrect the `channel_mask` cross-lane
    surprise this ADR exists to dissolve.
14. **One drag is one undo, and at most one apply per rendered frame.** While a drag is
    active, an `apply_edit` whose `field_ref` matches the top undo entry **replaces** that
    entry's `after_raw` (keeping the pristine `before_raw`) instead of pushing a new one,
    so a gesture crossing *K* frames leaves a single `baseline → final` entry. Because a
    camera edit recompiles the whole section and refolds, the host applies the drag at most
    once per rendered frame — the same expensive-op drain the coalesced scrub-seek uses,
    not once per raw motion event.

### Spacers — a hold renders as nothing

15. **A camera spacer is a `MAP` source with a zero value**, zoom tested on `.x` only, and
    the verdict is per **span**, never per keyframe. The runtime computes `MAP` as
    *current + keyframe* on every sub-channel, so a zero value gives `to == from` and the
    pose never moves. Zero *alone* is not the tell — every for-each camera keyframe in
    E317 stores `[0,0,0]`, including the `CASTER` pan and the `TARGET` framing — the
    source mode does the work. Only `MAP` is locally decidable: the other modes resolve
    against an external anchor or the saved slot, and under an absolute mode a stored zero
    is the *opposite* of inert. Unlike colour, this needs **no leave-one-out fold** (colour's `SpacerVerdicts`), because
    `CameraSubsystem.advance` searches for a new keyframe only on an *idle* channel, so a
    camera keyframe can never preempt a running tween and there is no stream context to
    fold — which matters, because the colour fold is the most expensive thing in the studio
    and camera adds an O(spans) integer test instead of a third one. The predicate lives in
    `CameraValueSemantics` beside `is_inert()`, the file that declares itself the one mirror
    of the runtime's match statements. Storage packs coincident sub-channel events into one
    masked keyframe sharing one command word while their *values* stay separate, so one
    stored keyframe can be a spacer on one mask bit and a real move on another.
16. **A camera spacer renders as empty space and is not selectable**, with clicks falling
    through to seek — in **both** of `hit_test`'s passes. The exact `_span_rects` pass and
    the loose "difficult to select" tolerance pass (`_loose_select`) must both skip it via
    `EffectScoreTimeline.is_hidden_spacer`: a hidden span's rect stays in the list because
    the gap right-click needs it, and the loose pass measures distance to the nearest edge,
    so `d == 0` for any point *inside* it and it hands back the very span the exact pass
    refused.
17. **`is_hidden_spacer`'s `enabled` clause defaults to `true`** — hidden unless
    *explicitly* disabled. Camera has no enable bit and no Solo/Mute; colour stamps
    `enabled` on every span, so its "muted, not gone" carve-out is untouched.
18. **The boundary grip survives a spacer.** A spacer's right edge is the *next drawn
    event's visible left edge*, so resizing a hold reads as dragging that event's start.
    Grips are a separate hit list (`_edge_rects`) that never consulted the drawn-verdict;
    that is intentional, and it holds on colour lanes too.
19. **Right-click → "Add waypoint here" reaches empty space**, the colour gap gesture in
    camera's vocabulary: `EffectStudioPage._lane_context_actions`'s whitelist includes
    `camera`, and it lowers to the same `CameraChannel.insert_event` a drawn span's verb
    uses — only the entry point differs. There is no Delete (empty space has no addressable
    event) and no `spacer_stub` (colour's born-disabled seed has no camera analogue).
    Decision 9's seed rule is unchanged, so an Add inside a hold is *itself* a spacer —
    visible while selected, gone on deselect unless given a real Source or a non-zero
    value. The rule "a no-op is invisible" holds with no exceptions.
20. **The selected span always draws, and a value edit must be able to wake it.** `_apply_vec`
    takes the fast in-place path with no reproject, so it flags `relayout` when an edit
    **crosses the zero boundary** (all-zero ↔ not) — targeted rather than ADR-0087's
    unconditional `invalidates_layout`, because the score build is already over budget.
    Source and interpolation edits already flag it.
21. **The compiled lane hides nothing.** It stays the faithful mirror of the packed store,
    which incidentally leaves every hidden hold a permanent read-only home: a selectable
    diamond showing Source / Interp / command word. That is what keeps a shot's pacing
    legible once ~29% of camera spans render as nothing.

### The grip's two owners

22. **A grip carries two span identities and they are allowed to differ.** Its **write
    owner** is whose `end_frame` (camera) or `time_value` (colour) the drag stores — the
    boundary *is* that number, there is nothing else to write, and it is **never
    re-attributed**. Its **select identity** is who the drag selects, roots the inspector
    on, and draws a handle for. They coincide on a drawn span and come apart at a hold.
    There is no left handle anywhere: what sits at a drawn span's visible left edge is the
    right grip of the hidden hold in front of it, and grabbing it must not reveal that
    hold.
23. **The identity rule has three cases and no special case.** A drawn span's grip selects
    itself. A hidden hold followed by a **drawn** span hands its grip to that successor —
    the neighbour's `Length` is derived from this very boundary, so it ticks live during
    the drag. A hidden hold followed by another hold (a *blind* boundary) **or** by nothing
    (the lane tail) keeps its grip but carries **no identity**, so no selection moves and
    the hold can never reveal. The API is
    `EffectScoreTimeline.edge_grip_identity(span, next_span, selected_id) -> String`, pure
    and static, `""` meaning "leave the selection alone" — one decision, one call site, one
    return value. The accepted cost is that hovering blank lane can pop a handle with
    nothing attached.
24. **A drawn span shows both its handles.** `edge_grip_drawn` draws the hovered edge plus
    every edge whose *identity* is the selection, so selecting a span lights its own right
    grip and the left grip a hold in front of it owns. The author's "left resize handle"
    becomes real on screen without a second grip ever existing, and an all-drawn lane is
    unchanged.
25. **One rule, one call site, across kinds.** Colour lanes are not a separate case — the
    registration is kind-agnostic and ADR-0087 shares this seam. `_next_tile` skips point
    markers, since a marker owns no stretch of the timeline and can never be a boundary's
    other side. **Particle lanes are excluded structurally, not by a special case:** the
    rule keys off `fields.spacer`, which particle never stamps, because ADR-0089 makes a
    particle *gap* an addressable **null span** — the currency its verbs spend — rather
    than an inert event that happens to be invisible. Its grip genuinely speaks for itself.
    Do not unify the two.
26. **An edge drag restores-then-reapplies, like Move.** Snapshot at grab; each motion
    restores the pristine keyframes and re-plans the whole boundary from the *original*
    state plus the current cursor delta, so the gesture is idempotent by construction
    rather than by an emergent property of the trade's arithmetic. The restore is gated on
    the bracket's own key, so an unrelated edit slipping into the bracket cannot rewind the
    channel. Every channel's `restore` — `PaletteChannel.restore`, `ScreenChannel.restore`,
    `ParticleTimelineChannel.restore` — must deep-copy out: handing the live channel the
    snapshot's own array makes a snapshot survive exactly one restore and corrupt silently
    on the next.

## Considered and rejected

- **Keep `channel_mask` editable, make the keyframe the inspection target, and home the
  orphan in a keyframe browser.** It keeps "membership" in the author's vocabulary and
  keeps camera a structural special case (one event → N lanes), managing the footgun
  instead of removing it — more studio machinery for a worse model.
- **Forbid clearing the last mask bit.** `channel_mask == 0` is a *legal* ROM-representable
  no-op, so forbidding it prohibits a valid state and breaks "free authoring subsumes
  faithful re-authoring".
- **Byte-exact partial patching of the packed form.** To survive an untouched round-trip
  byte-for-byte, lowering would need each event's original slot as provenance and would
  have to reproduce irregular packings — machinery that buys nothing an author can
  perceive.
- **Author on one merged "camera keyframe" lane**, with membership as tri-state marks on a
  single tile. It collapses the per-sub-channel view the *runtime* demands, losing the
  "when does position hold vs. move" reading the three lanes give.
- **Splitting the boundary band so the same number is grabbable from either side** —
  *(ADR-0095, 2026-08-18; built and then removed when this branch merged down: the
  two-sided grip layout, the `side` parameter on the drag signals, and three whole suites.
  Two handles on one byte is the trap decision 11 names.)* The reach problem ADR-0095 was
  opened for is real — on a colour lane the tile to the left is often an invisible spacer
  that owns no grip — and decisions 22–24 answer it by giving the one grip two identities
  instead of adding a second handle.
- **Suppressing the grip on a blind boundary** — *(shipped 2026-08-18, reversed 2026-08-19
  once measured: the justification was that the keyframe keeps a read-only home on the
  compiled lane, and there is **no compiled lane on colour**. `EffectScoreModel` emits no
  `palette_compiled` and no `screen_compiled`, "Hide inert" is an inspector-row toggle
  rather than a timeline one, and both hit-test passes skip a hidden spacer by
  construction — so a blind colour hold was unpaintable, unselectable and ungrippable with
  no fallback surface at all. Corpus-wide the suppression cost more boundaries than it
  re-attributed. Decision 23 gives a blind boundary the lane-tail treatment instead.)*
- **Widening the spacer predicate to every inert camera configuration.** Five other ways a
  keyframe occupies its span and moves nothing were found — `UNKNOWN_*` interpolation,
  zoom under `OFFSET`/`CURSOR`, span width 1 with a non-`IMMEDIATE` interp, and `SHAKE_*`
  with zero amplitude — and all stay drawn. Width-1 spans are **authoring accidents, not
  configuration**: they state a real intent the runtime drops, and hiding them would strand
  a bug the author would want to fix. Keeping the predicate exactly the author's hypothesis
  means widening it later is additive rather than a reversal.

## Consequences

- **The orphan bug dies by construction**, not by handling. With no membership to clear
  and no `channel_mask == 0` to author, neither the orphan nor the "unchecking hides the
  event" gesture can occur, and no keyframe-level inspection target or orphan browser is
  needed.
- **The write model is uniform across all five channels.** Camera stops being the
  exception; one event = one tile holds everywhere, and the inspector edits a sub-channel
  event in place like any other lane event.
- **Lowering is the single place all camera packing lives.** Parse (expand) and lower
  (coalesce) are inverses and are the natural unit-test surface.
- **A camera edit rewrites the whole camera section** on patch-in, so downstream patch
  tooling must accept a section-sized write.
- **Capacity is a post-compile property.** Free authoring can produce more non-mergeable
  coincident events than the native slots; Faithful reports that after coalescing.
- **An inert event is invisible**, so the at-a-glance "there's a no-op lurking here" is
  gone, compensated by Add-into-empty-space and by the compiled lane. Camera raises the
  stakes over colour: `MAP`+0 is the ROM's *hold* primitive rather than an encoding
  accident, so what disappears is the shot's pacing, not just clutter.

## Verification

- `CameraLoweringTest` covers decisions 2–4 (parse/lower as inverses, semantic rather than
  byte equivalence); `EffectCameraDecoupleTest` covers decision 1, and `CameraTweenProjector`
  emits no Channels row at all;
  `EffectCameraSaverAdapterTest` and `EffectCameraSaveRoundTripTest` cover decision 4's
  capacity and round-trip.
- `EffectCameraOrdinalAddressTest` covers decision 5, with `CameraTweenProjectorTest` and
  `EffectCameraEditTest` asserting the address from their own ends; decision 6 is
  `EffectScoreModelTest._test_keyframe_address_camera`, which also asserts the
  reconstruction identity across every span in a lane.
- `EffectCameraInsertDeleteTest`, `EffectCameraStructuralUndoTest` and
  `EffectStudioLaneContextMenuTest` cover decisions 7–10, with a headful
  `EffectCameraInsertDeleteAcceptanceTest` on real E317;
  `PaletteInsertDeleteTest`, `ScreenInsertDeleteTest` and `EffectSoundInsertDeleteTest`
  cover the same verbs generalised to the other span lanes.
- `EffectScoreTimelineTest` pins decision 11's one-grip-per-span layout,
  `EffectEditSessionTest` pins decision 14's one-drag-one-undo, and
  `EffectStudioEdgeDragWiringTest` plus the headful `EffectCameraEdgeDragAcceptanceTest`
  cover the drag end-to-end.
- `EffectCameraSpacerTest` covers decisions 15–21 end-to-end through the real control
  rather than against the predicate alone — testing the predicate is what let decision 16's
  loose-select hole survive, since the predicate was correct the whole time and only one of
  its two consumers asked.
- `EffectSpacerEdgeGripTest` covers decisions 22–25 (the rule, the layout it produces, and
  the reveal that must not happen) with its assertion count pinned so a mid-test abort
  shows as a short count; `ColourDragPristineTest` covers decision 26 against a
  **fold-derived** colour fixture that stamps nothing, closing the gap left by fixtures
  that stamp `fields.spacer` because the real fold is expensive.
- No `tools/check_*.py` guard names this ADR. The decisions it would most repay are the
  cross-kind invariants — that `edge_grip_identity` is the only answer to grip ownership,
  and that no lane kind other than particle stamps a grip rule of its own.
