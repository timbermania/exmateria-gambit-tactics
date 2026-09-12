# The palette tint is a signed blend delta, authored as a result-pick against a reference

**Status:** accepted. **Relates to:** [ADR-0067](0067-color-modes-are-one-model.md) (the one
colour model both lanes share), [ADR-0071](0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md)
(per-archetype projection), [ADR-0086](0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)
(the two-model authoring/lowering split, the span-lane edit verbs, and the boundary-grip rule
this inherits), and [ADR-0101](0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md)
(the frame-granular Move that owns sub-8 positioning). The authoring vocabulary lives in
[CONTEXT.md → Palette tint](../context/16-effect-studio-authoring-tool.md). Fixes the palette
side of the effect-studio authoring gaps (#262 subsystem work, following #266's initial
palette build).

Verified 2026-08-28 — decisions 1–30 all built and guarded.

## Context

The palette / field-tint channel (`affected_units` / `caster` / `target`) was first built
(#266) with its RGB tint exposed as an **absolute unsigned colour** — the same
`gradient_color` picker screen uses for its Gradient stops, on the stated premise
`colour = raw/255`. That premise is **false**, and it is the root of the reported
"seek-color renders the wrong hue" bug.

The render path proves it: `PaletteSubsystem._push_phase_ops` → `ColorStack.push_op` →
`ColorRecipe.from_mode`, and `from_mode` sign-extends every r/g/b byte (`_sb`) and normalises
it as a **signed delta** (`Vector3(d5)/param_max`) which is then *added* to the colour-so-far
or the committed base through one of **11 shared blend modes**. Real data agrees: the one
checked-in palette file stores `rgb: [-31,-31,-31]` ("add -31 to existing +31 shift = 0"). So
the palette tint is structurally the **same family as the screen Blend** (a signed
additive/luma delta through a mode) — **not** the screen Gradient (absolute unsigned stops).
#266 reused the wrong screen editor: it shows the byte as `raw/255` while the engine
sign-extends the same byte and adds it as a bidirectional delta, so a picked "red" (255)
stores as −1, a near-invisible darken.

Screen's own fix for exactly this shape was the WYSIWYG `target_color` picker +
`BlendTargetSolver`. But screen solves against **one** known colour (the backdrop's top stop);
palette recolours a **whole surface** of many CLUT entries, with no live unit/map base in the
editor preview — so "what colour should it become" has no single answer, and `target_color`
does not transplant naively either.

## Decision

**The palette tint is authored as a result-pick against a fixed reference base, reusing the
screen Blend solver against the *palette* forward fold.** Resize, add and delete reuse
ADR-0086's authoring/lowering split, applied to a length-encoded channel; both colour lanes
then share one harmonized row set, one ripple mode, and one spacer oracle.

### The tint value

**1. The colour value is a signed Δ through a mode, never an absolute colour.** The
`gradient_color` reuse is retired on the palette lane. The 11 modes get **human labels shared
with screen** (one `ColorModeLabels` map, since the op table is `ColorStack`, shared): *Add* /
*Dim ½ + Add* / *Desaturate (strong|subtle)* / their *over base* idempotent variants
(4/5/6/7/9) / *Reset to base* (8) / *Reset* (10). All 11 stay exposed (byte-faithfulness —
9≡4 is a real byte, restores are genuinely authored), and the over-current vs over-base
**source** distinction is in the label because its idempotency is load-bearing (the #164 fix).

**2. The tint editor is a result-picker against a mid-grey reference.** The author picks "what
colour this should become"; the host wires `BlendTargetSolver.solve` to the **palette** fold
(`ColorStack.fold`, `param_max = 31`, `quantize = true`) at the parked frame for the
keyframe's current mode, and it back-solves the signed Δ. Reference base is **mid-grey
(15/31)** — for the affine modes "grey becomes X" makes Δ = X − grey, so the control reads as
*"pick the tint"* directly. Unreachable targets snap to the **nearest** achievable and show in
a read-only "actual" swatch; the live preview (the real recoloured surface) is the other
honest feedback.

**3. The existing per-channel brute-force solver is valid across all 11 modes, unchanged.** In
every palette mode the Δ enters **per-channel, additively, after** any luma mix, and the mix
reads the *base* (the fixed reference), never the delta candidate — so `result_ch = f(base) +
Δ_ch` is a pure function of one delta byte. The luma modes (2/3/6/7) therefore do **not** need
a 3-D search or a per-mode inversion.

**4. Restores (modes 8/10) carry no colour.** The Δ is ignored, so the tint cell is **absent**
for those two modes — a mode-shaped field set (the CONTEXT *Variant* capability), not a greyed
control.

### Resize, add and delete

**5. Palette gets ADR-0086's two-model split.** The author manipulates absolute `[start, end)`
intervals; a palette **lowering** step re-derives the on-disk `time_value`s on save. This is
necessary because palette is **length-encoded** (one `time_value` per keyframe,
`duration_frames = time_value × 8`, start cumulative — no stored `end_frame`), so a naive
duration edit would ripple the whole downstream tail. Authoring absolutely makes the move
**stay-local** (downstream pinned) and hands the ripple to the encoder, exactly as the
*Authoring-time / Lowering* glossary prescribes.

**6. A boundary drag is one absolute-boundary edit on the shared camera seam** — the same
report-don't-mutate → host-applies → reproject seam and grip/hit-rect infra as camera's
boundary drag, **not** the sound `SoundGapMath` two-gap trade. Palette differs from camera
only in the lowering target (`time_value × 8` vs `end_frame`), so drags **snap to 8-frame
steps** (a Faithful constraint) and re-time the DDA ramp (length and ramp are the same on-disk
field — one knob). Clamp to a minimum `time_value = 0` snap (1-frame tween); never zero-width,
never an implicit delete.

**7. Add/delete are the ADR-0086 span-lane verbs, generalised** from camera-only to palette
(`EffectEditSession._dispatch_structural` + `_lane_context_actions`). The one
palette-specific choice: an inserted waypoint is seeded as a **disabled null tween**, not by
inheriting the neighbour's Δ. A Δ-inherit is a visual no-op *only* for the idempotent
base-source modes — for current-source additive it doubles the tint at the cut, and a Δ=0 seed
*erases* the tint under a base-source neighbour. A disabled tween holds the prior keyframe's
still-live `ColorStack` layer, so it is invisible by construction in **any** mode; the author
then enables it and picks a tint.

**8. Palette keeps its raw `event_index`; no ordinal addressing.** Unlike camera, palette is
lane-event-atomic 1:1 with storage and its lowering never reorders, so scalar edits address by
raw slot; only insert/delete renumber, and those already ride snapshot undo + reproject +
select-by-position.

### One harmonized row set across both colour lanes

**9. The Duration row is the boundary edit, typed.** Both colour lanes (all three palette
channels + screen) carry an **editable Duration int cell** that is the *same edit* as the edge
drag: a `duration` pseudo-field on each channel that internally delegates to `_apply_boundary`
(`boundary_end = start + new_duration` — the channel knows the cumulative start; the inspector
does not). Snap-8, min-width clamp, `invalidates_layout` → reproject, and the drag-scoped undo
coalesce all come free. Typed values **quantize to the nearest snap step and the cell shows
the snapped number** (the camera human-units honest-tell pattern). Tail keyframe = extend the
lane, no trade — matching the drag.

**10. Ripple is an explicit mode, not a side-effect.** A **Ripple toggle on the timeline
toolbar** (off by default, session-local, never persisted into the effect file) governs
**both** the edge drag and the typed Duration row, so the two affordances never diverge. While
on, a resize **skips the sum-preserving trade**: mid-lane behaves like the tail-extend path,
so every downstream keyframe **in that lane** shifts by the delta. The flag travels on the
`field_ref` as data, not as ambient state, so the undo record replays ripple semantics after
the toggle flips. **Lane-local only** — every lane with a resize affordance joins (decisions 15
and 16), other subsystems stay parked, and cross-lane alignment is the author's
responsibility while the toggle is on.

**11. Screen Enabled is a byte-swap with a session stash.** Screen has **no enable bit**
(`ctrl` bit-7 is the Kind); on disk, "disabled" and "identity no-op Blend" (mode 0, zero param
— the insert-seed convention) are the same bytes. So **disable** overwrites the keyframe to
the identity no-op, stashing the prior bytes in an **authoring-only, session-scoped sidecar**
(the ADR-0085 `anchor_offset` pattern); disabling a **Gradient** rewrites it to a Blend no-op
(a disabled keyframe always presents the Blend variant) and re-enable restores the stashed
Gradient losslessly. A **cold** no-op (after save/reload — the stash does not persist) shows
Disabled with nothing to restore; enabling it means "author a tint", never a fabricated byte
restore. **Disabled state is derived**: identity-no-op bytes OR a stash present, so the live
raw bytes always equal what plays *and* what saves. The stash is keyed by event address, so
the structural verbs **remap or drop** stashes on renumber, and effect load clears them.

**12. The screen Tint Δ row shows the stored byte.** Screen Blend carries palette's signed Δ
row + "No tint" reset, **Blend variant only** (Gradient stops are absolute — a Δ row is
meaningless there, a mode-shaped Variant absence like palette's restores). The engine applies
the screen byte **doubled** (`double_param`, `<<1`): the row shows the **raw stored byte** with
the doubling told in the label — *Tint Δ (applied ×2)*. The Δ row's job is precise raw control
and an unambiguous zero; cross-lane WYSIWYG comparison lives in the tint picker, which already
solves through each lane's real fold.

**13. One harmonized row set, and screen's mode row is editable.** Context (Channel/Kind) ·
Enabled · Tint · Tint Δ · Blend mode · Duration — same order and labels across the three
palette channels and screen. **Screen's Blend-mode row is an editable 11-choice
`ColorModeLabels` enum** (same op table as palette; the picker re-solves against the current
mode). Variant absences stay: Gradient has no Δ/mode rows, palette restores (8/10) no tint
cells.

**14. The two colour projectors converge on a shared row builder.** `ColorTweenRows` builds the
harmonized rows from a small, closed per-lane descriptor — solver + fold, `param_max`, ×2 flag,
address shape (palette 2-D channel vs screen 1-D), enable mechanism (bit RMW vs byte-swap +
stash) — and the two projectors are thin adapters (variant dispatch + address). The palette
tint materialize loop generalises to one lane-parameterized tint-refresh seam
(`EffectKeyframeInspector.refresh_palette_tint`). **Apply paths stay per-channel**
(`_apply_enabled` genuinely differs).

### Ripple on the endpoint-encoded and instant-based lanes

**15. Camera ripple shifts the lane's downstream `end_frame`s, splitting coalesced hosts.**
Camera is endpoint-encoded, so a rippled resize is not one field write: the channel writes the
edited event's `end_frame` and adds the delta to every **downstream** `end_frame` in the
**same sub-channel lane**. A downstream keyframe that also drives other sub-channels is
**split out** through the existing coalescing lowerer before shifting, so sibling lanes never
move — decision 10's lane-local contract holds *inside* the camera subsystem too. Undo is the
**structural table-object stash** (the insert/delete-verb shape), not a scalar record, and the
drag-scoped coalesce keeps the *first* stash across a drag bracket: one drag, one undo. **No
saturation, ever**: with ripple on, the page's upper drag clamp stops being `next_end − 1` (the
neighbour bound ripple exists to drop) and becomes tail headroom, `CAMERA_END_MAX −
(lane_last_end − this_end)`, so a drag physically cannot overflow; the channel additionally
**refuses** (error, no-op) a typed edit that would push any downstream `end_frame` past s16.
The typed **End frame** cell rides the same widened injection gate as the drag
(`channel == camera`, `field == end_frame`).

**16. Sound: the typed Gap is natively ripple; the fire-drag gains a ripple branch.** The typed
**Gap** (`duration_frames`) edit is ripple **by nature** — the gap *is* the offset to the next
trigger, so editing it already shifts every later fire, toggle or no toggle. **No change**, and
the guard asserts this so nobody "fixes" it. The **fire-drag** with ripple on skips the
`SoundGapMath` compensating write: it edits **only the grabbed trigger's prior gap**, clamped
to `[0, 32767]`, so every later fire shifts by the delta — a plain scalar `duration_frames`
edit through the choke point, drag-coalesced to one undo, first trigger still pinned (no prior
gap). Dragging left bottoms out at gap 0 (fires coincide, same as typing Gap = 0).

### What counts as a spacer

**17. The spacer predicate is disable-equivalence** over the authored stream: fold the
channel's stream with the event vs. without it (timing kept — which is *exactly* the runtime's
disabled semantics: a disabled keyframe advances timing only, `PaletteSubsystem._each_keyframe`;
screen's disable byte-swap is the provably-transparent identity Blend) and compare. A spacer is
an event whose **Disable would change nothing**. This subsumes any bytes-only predicate (a
disabled keyframe and a mode-0 Δ0 satisfy it trivially). Its meaning is *inert as authored right
now*, not *inert in any context*: verdicts recompute on every score rebuild (decision 19), so an
edit that wakes a spacer visibly drops its verdict at that moment — the timeline renders the
dependency.

**18. Transform equality, any base — never preview-relative.** The two folds must be equal **as
colour transforms**, for every base colour at every frame, because the map/unit base varies per
battle and a verdict must survive a map change. Checked by folding both variants at the ramp
breakpoints over a small probe-base set including the 0/1 clamp extremes (affine layers exact
by two probes; luma covered by the spread), plus **the midpoint of each adjacent pair** — two
part-done ramps compose non-linearly, so with-/without-folds can agree at every layer start and
ramp end yet differ strictly between them. Consequences on real data, all pinned by the guards:
mode-1/5 Δ0 events that *do* the darkening stay real, but an **idempotent re-assert** of a
settled base-source op is disable-equivalent by construction (`ColorRecipe.merge`:
above-reads-base ⇒ the merge IS above); a *leading* Gradient stays real forever while a
Gradient after an **equal** Gradient is inert; and each channel folds ONE continuous stream
**across phases** (`build_stream`; the PSX colour engine has no phase concept), so a
phase2-opening restore after live for_each tints is real cleanup and is inert only when
everything was already restored.

**19. Restyle: every palette/screen VALUE edit flags `invalidates_layout` unconditionally** —
rgb bytes, blend mode, ctrl, enabled, gradient stops. The rebuild recomputes verdicts lane-wide
and cross-phase, so an edit to keyframe A that wakes keyframe B — same channel, any phase —
restyles B immediately without re-selecting. Timing and structural edits already rebuild.

**20. Verdicts ignore Solo/Mute.** They fold the authored stream. Mute is a listening tool; a
verdict that flickered with solo state would conflate "what is this data" with "what am I
previewing".

**21. The verdict computes in the score projection** (build-time) via a pure fold-equivalence
helper (`SpacerVerdicts`), projected as a plain `fields.spacer` boolean; the channels'
bytes-only `is_spacer` is not the projection predicate. `EffectScoreTimeline` stays a dumb
renderer switching on the flag — the ADR-0071 `border` display-hint pattern, not a `role` enum.

**22. The studio folds the single-pass for_each stream**, as every lane already models it (the
runtime repeats for_each per target).

### A spacer renders as empty space

**23. A spacer renders as empty space** — no fill, border, label or hatch — and is **neither
selectable nor editable**. A colour lane is fully tiled, so every earlier treatment assumed a
spacer had to be *drawn* because it owns time; an **emitter** lane already renders an
absent keyframe as an invisible **gap** you build into (ADR-0089's Add-in-a-gap), and a colour spacer is the same thing
(time owned, nothing to say). The way in is Add, not convert.

**24. No toggle.** Spacers are unconditionally empty, matching emitter gaps (there is no "show
gaps" button). A reveal toggle is chrome for an editing capability deliberately removed.

**25. Right-click → Add event is a spacer's only affordance.** A fresh **1-frame disabled
stub** is born at the clicked frame (colour durations encode `time_value × 8`, but `0` decodes
to exactly 1 frame — `ColorLowering`), with **spacer on either side** (one spacer keyframe →
three; structural, one undo). You resize, enable and colour it into a live event. Insert seeds
a **disabled** null tween (decision 7), which is precisely what keeps the new stub visible
instead of instantly re-hiding.

**26. The hide predicate is verdict-inert AND enabled; the hatch means deliberately disabled.**
A **human-disabled** event is *not* hidden: it stays drawn — its colour, dimmed, under
**diagonal stripes** (the `_hatch_segments` painter, unchanged), keeping its solid/dashed *kind* border — and **selectable**, so its
Enabled knob is reachable. "Muted, not gone," mirroring a disabled emitter. The stripe's
meaning is therefore *a human chose off*, never *auto-detected inertness*. **Border = kind**
(solid Blend / dashed Gradient) and **hue = produced colour** stay orthogonal to it; dashed
means Gradient everywhere, which is why "off" could not reuse it.

**27. The selected event always draws**, even if its bytes make it a spacer — so a just-added
or just-enabled-not-yet-coloured stub never blinks out mid-edit, and it labels itself
**"Spacer"** when wide enough. This is the *only* way a spacer is ever on screen; an unselected
one cannot be left-clicked.

**28. No intrinsic-vs-contextual note.** It was only ever reachable by selecting a spacer,
which no longer happens. The oracle still computes the verdict (to decide what to hide) and
stays **live**, but it no longer narrates a flavour. Scope is the two colour lanes (palette,
screen) only.

### The boundary grip and the trade

**29. A colour hold's boundary grip speaks for its neighbour.** Colour inherits, unchanged, the
rule settled on the camera seam — see **ADR-0086 decs. 22-25**, as revised by **ADR-0086 dec.
23** (a blind boundary keeps its grip, with no identity). The reversal there was driven *by
colour*: suppressing the blind grip cost camera 0.9% of its boundaries but colour **12-18%**,
and a colour hold has no compiled lane to fall back to. The mechanism is identical — a hidden
colour hold's right grip is the next drawn tween's visible **left** edge, so grabbing it used
to force-select the hold, and a selected span is never a hidden spacer (decision 27), so the
hold painted itself and read as "the drag created a spacer". The registration is kind-agnostic
(`EffectScoreTimeline.edge_grip_identity` / `edge_grip_drawn`) precisely so there is one rule
and one call site rather than a camera copy and a colour copy.

**30. The boundary trade freezes the far edge.** `total` is an exact invariant of the trade:
both halves must be storable lengths, so the drag offers only positions where they are, and the
handle visibly skips the rest. `ColorLowering.trade_durations` is that chooser — never
`total − new_dur_n` handed to `_set_duration`, whose silent re-snap is what slid the
neighbour's far edge ±1 frame in ~13% of drag positions (always where a span landed on the
1-frame minimum and the residual was one away from a multiple of 8). Palette and screen carry
the identical three lines; camera is immune, writing an absolute `end_frame` with no
quantization. The consequence is ratified, not regretted: on a total that is a clean multiple
of 8 the 1-frame squeeze is no longer reachable by dragging (`8+24` offers `{8, 16, 24}`), so
**colour trades are strictly 8-grained**, and sub-8 positioning is the Move gesture's job
(ADR-0101). This turns "downstream stays pinned" from an intent into an invariant and removes
the per-motion compounding the in-place drag had; the edge drag takes Move's
restore-then-reapply bracket from ADR-0086 dec. 26.

## Considered and rejected

- **Keep the #266 absolute unsigned `raw/255` picker** — it mislabels a signed delta as a
  colour and *is* the "seek-color" bug.
- **Bipolar signed-delta sliders** (`signed_rgb`, the editor screen retired) — correct but it
  is the "dial ±N" UX the result-picker exists to escape. Still the natural fallback if a
  mid-grey reference ever proves too surprising; sampling a real surface pixel as the reference
  is the other.
- **Reuse the sound fire-drag `SoundGapMath` two-gap trade for resize** — mechanically apt
  (palette is length-encoded like sound) but it exposes durations and trades to the author,
  whereas absolute-interval authoring gives the identical byte result with the cleaner camera
  UX and no new gap arithmetic.
- **Edit `time_value` directly and let the tail ripple** — rejected as a *default or implicit*
  semantic; the glossary forbids a visible ripple. A deliberate, author-chosen ripple is a
  different thing and is decision 10.
- **Cross-lane ripple** (shifting *other* lanes to keep alignment) — a real feature but a
  separate, much larger design. Deferred; decision 10 is lane-local.
- **Making the sound Gap a stay-local two-gap trade when ripple is off** — declined: it would
  change shipped behaviour. A possible follow-up.
- **Shifting a shared coalesced camera keyframe in place** (dragging siblings along) — a
  cross-lane leak. **Refusing ripple on coalesced tails** — real data is heavily coalesced, so
  ripple would almost never fire. **Saturating downstream `end_frame`s at s16** — silently
  destroys spacing and makes redo diverge from the recorded bytes.
- **A skip-aware sound ripple that consumes earlier gaps** — re-creates the compound machinery
  for a case the author covers by dragging the earlier trigger instead.
- **A preview-only mute sidecar for screen disable** (the studio fold would lie relative to the
  saved file) and a **toggle-less "No-op badge + clear action"** (loses the harmonized row).
- **Parallel colour projectors sharing only vocabulary** — that is the arrangement that drifted
  into the asymmetry decision 14 kills.
- **A bytes-only spacer predicate** — *(shipped 2026-08-11, superseded: pristine E317/E015
  played windows contain zero intrinsic spacers — the ROM spaces its colour lanes with mode-4/5
  Δ0 over-base ops and mode-8 restores, exactly the contextually-invisible class it excluded.)*
- **Spacers drawn as a hatched inert block, selectable so you could wake one into a real
  event** — *(shipped 2026-08-11, reversed 2026-08-12: the author judged the hatch pure
  clutter. `_hatch_segments` survives verbatim under decision 26's narrower "disabled" meaning.)*
- **Low-alpha ghosting** (collides with the past-derived-end wash — two meanings of "faded"), a
  **third border style** (dotted vs dashed is illegible at 1 px and grows the border vocabulary
  instead of repairing it), a **two-way disabled-vs-identity visual** (cannot exist on screen
  lanes, where the two are the same bytes), a **"Make active…" verb** (any seeded default is a
  value the author overwrites anyway), and **lane-header counts / a toolbar legend** (chrome
  paying rent for a one-time learning moment).

## Consequences

- **The mode-label set is shared** — screen and palette read one `ColorModeLabels`; they cannot
  drift to different words for the same op.
- **The palette editor is mode-shaped** (a Variant): colour cell for the 9 delta modes, absent
  for the 2 restores.
- **Palette gains a lowering step + a Faithful ×8 quantization** on durations, and its Save path
  recomputes `time_value`s from absolute intervals (`EffectPaletteSaver` → the byte-exact
  `write_effect_palette.py`).
- **The enable toggle is a scalar `ctrl` bit-7 edit, not structural.** A disabled palette tween
  keeps its tile and holds the prior tint (fully-tiled + null-tween), so toggling enable never
  adds or removes a lane span.
- **The declutter costs discoverability.** An inert event is invisible, so the author loses the
  at-a-glance "there's a no-op lurking here". That is the accepted trade, with Add-into-empty-
  space (proven on emitter lanes) as the compensating affordance.
- **Colour trades are strictly 8-grained** (decision 30). Frame-granular positioning exists, but
  it is ADR-0101's Move, not this ADR's resize.

## Verification

- `PaletteTintSolverTest` and `BlendTargetSolverTest` cover decisions 2–3 (the fold against the
  mid-grey reference and the per-channel scan's validity in the luma modes);
  `ColorModeLabelsTest` covers decision 1's one shared label map, read by both lanes;
  `EffectPaletteTintPickAcceptanceTest` covers the pick end-to-end on real data.
- `ColorLoweringTest` covers decisions 5–6's interval ↔ `time_value` mapping and, separately,
  decision 30's `trade_durations`; `PaletteBoundaryEditTest` and `ScreenBoundaryEditTest` cover
  the boundary edit per lane, with `EffectPaletteEdgeDragAcceptanceTest` and
  `EffectScreenEdgeDragAcceptanceTest` headful.
- `PaletteInsertDeleteTest`, `ScreenInsertDeleteTest`, `EffectPaletteInsertPositionTest` and
  `EffectScreenInsertPositionTest` cover decision 7's verbs and its disabled-null-tween seed,
  with `EffectPaletteInsertDeleteAcceptanceTest` and `EffectScreenInsertDeleteAcceptanceTest`
  headful; `EffectPaletteSaverAdapterTest`, `EffectScreenSaverAdapterTest` and
  `EffectPaletteSaveRoundTripTest` cover decision 8's addressing surviving the save round-trip,
  and `EffectPaletteByteCoverageAcceptanceTest` pins byte-exactness.
- `ColorTweenRowsTest` covers decisions 9 and 12–14 (the one builder, the ×2-told Δ row, the
  row order both lanes share); `EffectStudioKindSelectorTest` and `EffectStudioColorEditTest`
  assert the harmonized rows from the inspector's end; `ScreenEnabledToggleTest` covers
  decision 11's byte-swap, stash, cold no-op and renumber remap.
- `EffectStudioEdgeDragWiringTest` and `EffectStudioFireDragWiringTest` cover decision 10's
  flag travelling on the `field_ref` and decision 16's two sound paths (including the assertion
  that the typed Gap needs no flag and no branch); `EffectCameraRippleTest` and the headful
  `EffectCameraEdgeDragAcceptanceTest` cover decision 15's downstream shift, coalesce split,
  structural undo and s16 refusal.
- `SpacerVerdictsTest` covers decisions 17–18 and 22 with the breakpoint sampling
  mutation-tested; `SpacerVerdictShortcutParityTest` re-derives every corpus verdict with the
  no-fold shortcuts forced off, so "same answer, cheaper" is measured rather than argued, and
  `SpacerVerdictsPerfTest` guards the fold's cost. `EffectSpacerProjectionTest` covers decision
  21's projection, `EffectSpacerRestyleAcceptanceTest` decision 19's cross-keyframe restyle.
- `EffectSpacerVisibilityTest` covers decisions 23–24 and 26–27 (the hide predicate, the hatch's
  disabled meaning, the selected carve-out) with `EffectSpacerEmptySpaceAcceptanceTest` headful
  and `EffectStudioLaneContextMenuTest` on decision 25's Add; `EffectScoreTimelineTest` pins the
  stripe geometry and the "Spacer" label. `EffectCameraSpacerTest` covers the camera lane
  joining the same `is_hidden_spacer` flag (ADR-0086 dec. 15).
- `EffectSpacerEdgeGripTest` covers decision 29 for palette — the rule, the layout it produces,
  and the reveal that must not happen — with its assertion count pinned;
  `ColourBoundaryFarEdgeTest` (48 assertions, count pinned) and `ColourBoundaryCorpusSweepTest`
  (401 effects, 12,530 boundaries, 87,710 trades) cover decision 30, both A/B'd red against the
  genuine pre-fix channels.
- No `tools/check_*.py` guard names this ADR. The decision that would most repay one is 13's
  harmonized row order, which is asserted per-lane today and could drift between the two.
