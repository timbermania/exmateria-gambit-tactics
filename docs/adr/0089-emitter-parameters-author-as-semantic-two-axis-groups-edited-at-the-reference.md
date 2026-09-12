# Emitter parameters author as semantic two-axis groups, edited at the reference

Status: accepted

## Context

The Effect Studio shows every emitter parameter read-only (`EmitterProjector`
const rows) — emitters are the manifest's largest editability gap (~27.4 KB:
14 emitters × 196 bytes, ~90 fields each). The raw model is RE technobabble
(`weight_min_start`, nibble-packed curve indices, packed flag bytes, opaque
callback params), and the fields hide a real structure: most parameters vary
along a **randomness** axis (each particle rolls a value between min and max at
spawn) and an **evolution** axis (the min–max range slides start→end over the
emitter's active window, shaped by that parameter's assigned curve). The edit
architecture is settled by camera/screen/palette/sound (channel encoder →
`EffectEditSession` choke point → projector cells → unit descriptors →
byte-exact writer → `studio_save`); the question is how emitters ride it
without exporting the technobabble into the authoring UI.

## Decision

**Scope tier.** This build makes **emitter parameters** editable. Explicitly
deferred follow-ons: `particle_timeline` keyframe/action-flag editing, the
particle system header, add/delete-emitter structural verbs (fixed 14-slot
table, count derived in header), and curve **contents** editing (the shared
curve table is its own authoring surface).

**Edit at the reference.** Emitter fields become editable where they are
already shown — the span inspector's shared emitter sections and the emitter
browser (both resolve to the same `Target.emitter(index)`, ADR-0073). The UI is
honest about shared-ness (section header: "Emitter N — shared, fired by K
events") instead of inventing a separate editor screen. Same shape as the
SoundContainer precedent.

**Two-axis presentation.** Each parameter is one labeled group with **At
start / At end** rows × **min / max** cells (a single cell where the parameter
has no randomness axis). min == max never collapses to one cell — collapsing
hides the randomness axis and makes it undiscoverable. A group tooltip explains
the axes once. Each group carries its **Curve** assignment row (a thumbnail
picker over the effect's distinct curve **shapes**; choice 0 = "none", which
holds the **start** values — the sim reads no end value and does no ramp).

> **Corrected 2026-08-20** by the curve-ownership amendment below, and by its
> build. This paragraph originally read *"enum over the effect's shared curve
> table; choice 0 = `none (linear start→end)`; the curve itself is shared and
> not editable here"*. Two things in that were wrong. The **linear ramp does not
> exist** — `ParticlePhysics.interpolate_range` returns the start range when the
> curve is null (which is what makes an all-zero curve an exact no-op, decision
> 5); the picker's `none` glyph and label carried the same error and are fixed.
> And the **table is not shared at authoring time**: every use site owns a
> private curve, editable right here through the painter — sharing is what the
> compiler produces on PSX export.

**Naming and units.** Every field gets a semantic display name; the raw RE
name + byte offset are preserved in the tooltip (e.g. "raw: `weight_min_start`
@0x54") so RE cross-referencing survives the rename. Values author in human
units **only where the `EffectEmitter.gd` runtime conversion is proven** —
positions/spreads/offsets in tiles (camera's `POS_TILES` convention), angles in
degrees, lifetimes/intervals in frames, inertia as a × multiplier (raw 4096 =
×1.0) — via a symmetric `ParticleUnits.gd` descriptor (the `CameraUnits`
pattern: `to_raw`/`to_display`/`quantize`, storage stays raw). No speculative
conversions: an unproven field stays a raw int with a tooltip saying so.

Canonical parameter vocabulary (raw → display):

| Raw parameter | Display name |
| --- | --- |
| `anim_index` | Animation set |
| `motion_type_flag` (bit 1) | Sprite faces its velocity |
| `motion_type_flag` (bits 5–7) | Target anchor mode |
| `animation_target_flag` (bit 0) | Spread mode |
| `animation_target_flag` (bits 1–3) | Emitter anchor mode |
| `anim_param` | Frameset group |
| `emitter_flags` bits | Named toggles (e.g. "Sprite faces its velocity", "Pull velocity inward") |
| `start_position` / `end_position` | Position |
| `spread_*` | Spawn scatter |
| `velocity_base_angle_*` | Launch direction |
| `velocity_direction_spread_*` | Direction scatter |
| `inertia_*` | Inertia (×1 = keep velocity) |
| `weight_*` | Gravity scale |
| `radial_velocity_*` | Outward speed |
| `acceleration_*` | Acceleration |
| `drag_*` | Drag |
| `lifetime_*` | Lifetime (−1 = dies with its animation) |
| `target_offset_*` | Target offset |
| `particle_count_*` | Particles per burst |
| `spawn_interval_*` | Spawn every N frames |
| `homing_strength_*` | Homing strength |
| `child_emitter_on_death` | Spawn on death |
| `child_emitter_mid_life` | Spawn mid-life |
| `callback_param_0..7` | Callback param 0–7 (Advanced) |

**Three-tier honesty for the awkward bytes.**
1. *Understood packed bytes* decompose like the camera command word: named
   checkboxes/enums per sub-field, single-byte-diff writes.
2. *Real-but-opaque* — callback params 0–7 are read by the effect's native
   MIPS callback (not inert, unlike camera Param/Flags) but their meaning is
   per-callback: **editable raw ints** in an "Advanced (raw)" section with an
   honest tooltip ("passed to this effect's native callback routine; meaning
   varies per effect").
3. *Reserved/always-zero* (`byte_00`, `byte_05`, `unknown_12/13`,
   `reserved_C2/C3`): **const rows**, byte-preserved by the writer.

Child-emitter wiring (`child_emitter_on_death` / `child_emitter_mid_life`) is
editable as emitter pickers ("Spawn on death: none / Emitter N") — rewiring the
child graph is a headline capability and the score re-projects the graph on
edit.

**Mechanics.** New `EmitterChannel` (the name "particle" stays reserved for the
timeline follow-on): every edit is **scalar** (fast `before_raw` undo — all
fields land in existing bytes, including curve nibbles and child wiring);
`invalidates_sim = true` on every edit (particles are born from emitter params
at spawn time, so a parked frame must re-fold to be honest — read-live is not
available here); `invalidates_layout` where the child graph or labels
re-project. Out-of-range raw from a typed human value is a **refusal**, not a
clamp; quantization hints where the unit conversion can't land exactly.

**Persistence, bridged now.** `tools/write_effect_emitters.py` (byte-exact
partial patch of the emitter block, registered in `effect_writer_registry.py`,
round-trip guard: parse real E### → re-serialize unedited → byte-identical) +
`EffectEmitterSaver.gd`, layered into `studio_save` **in this build** — palette
and sound both shipped save-unbridged and it lingered as debt; an authoring
surface that can't save is a demo.

**Acceptance.** E019 (Fire 4, the emitter-rich tracker baseline) headful: edit
a visually loud parameter → live re-fold at the parked frame → save → reload
the saved BIN → the edit survived. The manifest flips `emitters` from `display`
to per-field `editable`/`na` (reserved bytes `na`); `particle_timeline` and
`particle_system_header` stay `display`.

### Amendment (build, 2026-08-11): master_parser corrections

The build checked every packed-byte row against the master_parser disassembly
notes (the handoff's "trust master_parser over memory" rule) and corrected two
speculative table rows:

- `motion_type_flag` low bits are **not read by the engine** (bits 0 and 2–4,
  per the disassembly) — there is no "Motion type" enum. The byte's only
  engine-read sub-fields are bit 1 (align-to-velocity → "Sprite faces its
  velocity") and bits 5–7 (target anchor mode). Unread bits are never exposed
  and are byte-preserved by the writer.
- The child-enable flags (`emitter_flags_lo` bits 0–1 / 2–3) are 2-bit
  **modes** (disabled / spawn / spawn-alt / disabled), not booleans — they
  author as "Child death mode" / "Child mid-life mode" enums.

Also settled in-build: **lifetime authors signed** (s16) so the −1
"dies with its animation" sentinel (0xFFFF on disk) is typeable; the writer
writes 16-bit fields masked-unsigned, so both encodings round-trip. And
`callback_param_0..3` (@0x4C–0x53) remain an **open manifest gap**: the parser
surfaces only the low bytes of params 0/1 (u8), so full s16 authoring waits on
a parser+asset regeneration; params 4–7 (@0xA8–0xAE) are editable now.

### Amendment (design, 2026-08-11): inspector presentation — collapsible single-column groups

The user reviewed the built surface and accepted the model/edit/save layers but
rejected the presentation: the inspector's width-based two-per-line reflow is
group-blind, so consecutive rows pair horizontally and a parameter's rows
interleave with the next parameter's across columns; the right column clips;
cells don't align vertically; and the enum-only Curve rows dropped the
sparkline, leaving curve choice opaque with no hint of which samples the
emitter actually consumes. This amendment settles the view layer (grilled
2026-08-11; channel/writer/saver untouched):

1. **Single column, inspector-wide.** The two-per-line width reflow is
   removed for *every* section (camera/screen/palette/sound included), not
   just emitters — the clipping and alignment complaints live in the shared
   mechanism. Vertical scroll does the work.
2. **One fold per parameter group.** Each parameter group becomes a nested
   fold inside the emitter section, reusing the inspector's existing accordion
   idiom (header toggle, ▾/▸). Fresh inspect = all groups collapsed; an
   **Expand all / Collapse all** control sits on the emitter section; fold
   state is remembered per (emitter, group) for the session so re-selection
   and live-reproject rebuilds don't reset it.
3. **Collapsed header summary.** `Name  (0,4,0) → (0,0,0)  ▁▂▄█` — start→end
   values (min–max form where the randomness axis has spread), a mini
   sparkline iff a curve is assigned, full values in the tooltip; inert groups
   (all fields zero, no curve) render dimmed; the summary hides when the group
   expands. *Law clarification:* the "min == max never collapses" rule governs
   the **editing cells**; a read-only summary may collapse `40–40` to `40`
   because expanding always reveals both axes.
4. **Curve row regains its sparkline.** The Curve assignment row is a
   `[enum, sparkline]` cells strip; clicking the sparkline opens the curve
   painter (existing `on_open` seam).
5. **Used-window sparkline.** Sparklines always draw the shared curve's full
   160 samples (agreeing with the painter), with the used window `0..N`
   bright and the unused tail dimmed; the tooltip states the window in
   frames. N follows the verified sampling clocks: evolution parameters
   sample by **emitter-elapsed frame** → N = the firing span's duration;
   over-life rows (colour R/G/B, homing blend) sample by **particle age** →
   N = the max authored lifetime. N ≥ 160 renders fully bright (the curve
   genuinely wraps); lifetime −1 renders fully bright with an
   "animation-driven window" tooltip. The span inspector dims by *that
   firing's* window; the emitter browser (no span selected) uses the **max
   window across all firing spans**, tooltip noting it is the widest firing.
6. **Alignment by fixed column widths.** The row-name label and each cell
   type get fixed widths so columns align across the whole inspector; cells
   strips stay HBoxes.
7. **Explicit group identity.** The projector emits group identity on its
   rows (replacing the implicit "Position · …" name-prefix convention) so
   both consumers — span inspector and emitter browser — hang the same folds
   on a real boundary.

View guards (`EmitterProjectorTest`, `EffectStudioEditorKitTest`,
`EffectEditabilityManifestTest`) may legitimately move; model/writer/saver
guards must not. Acceptance is headful screenshots of the real window on
E019 — field dumps don't count (the FedsPairStrip lesson).

## Amendment — field-relevance salience (grilled 2026-08-11)

An emitter opens as "a billion fields," most of which are provably doing
nothing. This amendment adds a **relevance verdict** to every field so the
inspector reads top-to-bottom as *what is actually in effect*. It settles the
model and view; the channel/writer/saver are untouched. Scope is **field-level
salience** (per-inspector); an emitter-level rollup and child-emitter linking
are explicitly deferred.

**The three-state model.** Every field is exactly one of:

1. **Live** — read by the sim and its value changes output. Rendered normally.
2. **Inactive** — read every frame, but its value is the group's **neutral
   value**, so its term drops out of the sim entirely. Fully wired; an author
   edits it to wake it. **Neutral is not always zero** — it is 0 for the
   additive terms but the **identity divisor 4096 for inertia**. Shown
   **collapsed and marked**, never hidden.
3. **Dead** — the sim provably never reads it. Hidden behind a per-section
   reveal.

**Gates and the annihilation graph.** A **gate** is a field whose value deads
another. The proven edges:
- `curve == none` ⇒ that group's **end axis** is Dead — `interpolate_vec3/
  range/simple` return `start` unread when `curve == null`
  (`ParticlePhysics.gd`).
- `homing_strength == 0` (the whole min/max·start/end block) ⇒ **target offset**
  and **homing blend** are Dead (`ActiveEmitter.gd` gates the target read;
  `ParticlePhysics.gd` skips the homing path). Sign matters: non-zero *either
  way* is Live (negative = repel), so the gate is `!= 0`, never `> 0`.
- `color enable` (flags_lo bit 6) off ⇒ **color R/G/B** Dead.
- a disabled **child mode** (flags_lo bits 0–1 / 2–3, a 2-bit mode) ⇒ its
  child-emitter index Dead.
Two asymmetries: **Position** is never Inactive (offset 0 = spawn *at* the
anchor, a real place); **particle count 0** escalates to "this emitter emits
nothing," not a mild Inactive. **A gate is never hidden** — it is the switch
the author throws.

**The oracle is derived from a Field Dependency Inventory, not hand-waved.** A
bounded one-field-at-a-time pass over the sim formulas (consumers live in
~4 files: `ParticlePhysics`, `ActiveEmitter`, `ParticleAnimator`,
`EffectParticleRenderer`) produces a table — *consumed-by* (`file:line`),
*neutral value*, *gated-by*, *gates*, *why-string*. The oracle is generated
from it. **Each Dead edge is guarded against the real sim** (set the gate,
assert the gated field cannot affect output) per the project's static-rooted /
dynamically-validated rule. This pass is expected to surface edges we currently
only guess (e.g. does `align_to_velocity` dead the launch angle? does
`velocity_inward` go moot when radial = 0?).

**Presentation** (decisions, grilled in order):
- **Default visibility = Live + Inactive shown, Dead hidden-revealable.** Not
  "only Live" (you must *see* Inactive to wake it) and not "show everything
  dimmed" (that never cuts the field count, which is the complaint).
- **A marker icon (`!`-style), not inline prose.** Glanceable — scan for marked
  rows; **hover gives the why-string / the edge**. Markers stay few because
  Dead is hidden and Inactive collapses to one line.
- **Bidirectional markers.** The suppressed/Inactive field's hover says *why
  it's off*; the **gate field also carries a marker** whose hover says *what it
  is suppressing* — same edge data read the other way, so the dependency is
  navigable from either end and the author sees the consequence *at the switch*
  where they act.
- **End-axis Dead collapses the end column in place** (group stays), with an
  `end unused — no curve` note beside the curve control.

**This supersedes** decision 3's ad-hoc "inert groups (all fields zero, no
curve) render dimmed": that heuristic conflates Dead and Inactive and misses
neutral-non-zero cases (inertia = 4096). The oracle replaces it.

### Amendment (build, 2026-08-11): field-relevance salience — inventory findings

The oracle (`EmitterFieldRelevance.gd`) was built test-first with a real-sim
guard behind every Dead edge (`EmitterFieldRelevanceSimGuardTest`, the
static-rooted / dynamically-validated rule). The bounded one-field pass proved
the four annihilation edges (curve==none ⇒ end axis Dead; homing==0 ⇒ target
offset + homing blend Dead; colour-enable off ⇒ colour R/G/B Dead; disabled
child mode ⇒ child index Dead) and **refuted three guesses**, which the
inventory now records as sim truth:

- **Inertia's neutral is NOT 4096.** The design guessed 4096 (the ×1.0
  divisor). The real integrator
  `new_vel = (max(0, inertia − threshold)·old + accel·4096) / inertia` is
  identity only when the particle-header `inertia_threshold` is 0; at the
  default 512, inertia 4096 decays velocity ×0.875. Neutrality depends on a
  header field the (per-emitter) oracle does not model ⇒ **inertia is never
  merely Inactive** — always shown Live. Inventory neutral = the named
  sentinel `"momentum"`.
- **`align_to_velocity` does not dead the launch-direction angle.** It is a
  renderer billboard rotation and never touches the spawned velocity; the
  launch angle drives velocity in `ActiveEmitter` regardless. Refuted.
- **`velocity_inward` is not moot when radial == 0.** With `align_to_facing`
  on, `is_unit_oriented` rotates the spawn *position* by the caster facing
  even at radial 0, so toggling `velocity_inward` still moves output. Not a
  clean gate — refuted.

Also fixed in-build: `EmitterChannel.read_raw("color_curve_enable")` matched
the `color_curve_` prefix branch (returning `color_curves["enable"]` ≡ 0)
instead of routing to the packed flags_lo bit like `apply_raw` — the Config
"Colour curves" toggle's seeded value was silently always-off. `read_raw` now
guards the prefix with `in _COLOR_CURVE`, symmetric with `apply_raw`.

Presentation (superseding decision 3's "dim all-zero groups"): the inspector
shows Live + Inactive (Inactive marked with a `!` glyph + why-hover, dimmed,
never hidden), gathers Dead groups under a per-section
`▸ N hidden (not in effect)` reveal, drops the "at end" row of a curve-less
Live group (end-axis collapse), and puts a bidirectional `!` on gate switches
(hover = "Suppressing: …"). A curve-less group also summarises as its **constant
start** with a **flat** header glyph — with no curve the value is pinned to
start and the end is inert, so the #291 start→end slope glyph (which implied a
glide that never happens) is superseded. Assigning/clearing a curve is a
**relayout** edit (`EmitterChannel._apply_curve`), so the end row + curve
sparkline appear/disappear live as the author toggles the curve. New guards: `EmitterFieldRelevanceTest`,
`EmitterFieldRelevanceSimGuardTest`, `EmitterRelevanceViewTest`; headful
acceptance `EmitterRelevanceAcceptanceTest` (E317 emitter 6) +
`EffectEmitterInspectorUxAcceptanceTest` (E019).

## Amendment (design, 2026-08-12): curve authoring UX — sparkline reversal, painter active-region, picker thumbnails, preview-only contents

A curve-focused pass (grilled 2026-08-12) settles the three curve affordances
that decision 5 + the field-relevance amendment left unwieldy. It **reverses
decision 5's presentation** and adds two new surfaces; the model/writer/saver
are untouched. First, the vocabulary the complaints conflated is pinned to
three distinct concepts:

- **Curve assignment** — the per-param nibble (`raw 0 = none, N = curve N−1`)
  choosing *which* shared curve shapes this parameter. Per-param, per-emitter.
- **Curve contents** — the shared 160 samples themselves. **Shared**: editing
  curve N's contents restyles *every* param in *every* emitter that assigns N.
- **Curve sparkline** — the read-only render of the *assigned* curve's contents
  on the param row (and, tiny, in the collapsed group header).

**1. Sparkline: trim + normalize (reverses decision 5).** Decision 5 mandated
"always draw the full 160 samples … unused tail dimmed." That dim-tail cue was
too subtle — the sparkline read as the whole curve, not the active part. New
rule, driven by the same `used_n` datum:
- **Normal (`0 < N < 160`):** draw **only** samples `0..N`, X-stretched to fill
  the sparkline width, with **Y re-fit to the trimmed window's** min/max (a
  post-window spike no longer squashes the visible part). A short window is a
  full-width shape, not a sliver. The `COL_TAIL` dim-tail colour is deleted —
  trimming removes the concept of a visible unused tail; absolute duration lives
  in the existing frames tooltip.
- **Fallback (`N ≥ 160` wraps, or `lifetime −1` animation-driven):** the active
  window is undefined ⇒ fall back to **whole, un-normalized, fully bright** with
  the existing "curve wraps" / "animation-driven" tooltips.
- Applies to **both** the inline row sparkline and the 52 px collapsed-header
  mini-sparkline (one widget, one rule, single source = the samples). The
  `set_linear` no-curve glyph is untouched — it is not a curve.

**2. Painter: mark the active region (the inverse of the sparkline).** The
painter keeps **all 160 frames** editable (the window can grow later, so the
"inactive" tail must stay paintable), but visibly marks what the sim consumes,
using the *same* `used_n` (threaded in via `bind_curve`): a **veil over the
inactive tail `(N..160]`** plus a **1 px boundary line at frame N** with an `N`
label. No full X ruler (clutter on a 540 px canvas). Fallbacks (`N ≥ 160` /
`−1`): no veil; `−1` gets a small "animation-driven — full curve used" note.
Sparkline **trims** the tail; painter **dims** it — opposite presentation, one
datum.

**3. Curve picker: thumbnails (replaces the opaque assignment enum).** The
assignment cell's plain `OptionButton` (`none`, `Curve 0`, `Curve 1`, … — pick
blind) becomes a **thumbnail picker**: a button whose face shows the assigned
curve as a mini-sparkline + label, opening a **popup grid of curve thumbnails**
(each = a small sparkline + index; `none` = the linear glyph). Picker thumbnails
show the **whole curve, un-trimmed, fully bright** — browsing compares curve
*shapes*, and the used-window is a property of the param (identical for every
candidate), so trimming there would mislead. The chosen value flows through the
**same `field_ref` edit path** (`EmitterChannel._apply_curve` → session →
relayout): assignment stays byte-identical and undoable; only the widget
changes. The row's sparkline (which opens the painter — the glossary-protected
"sparkline IS the click target" affordance) is untouched.

**4. Live curve-contents editing is preview-only here.** `EffectCurvePainter`
already mutates the shared `EffectCurve` on mouse-up and emits `curve_changed`,
but the signal was **connected to nothing** — so the samples changed in memory
while the preview and sparkline went stale (the "editing a curve doesn't update
the curve" bug). The fix wires `curve_changed` → the existing edit fan-out
(rebuild score + re-render inspector + re-seek/re-fold at the parked frame).
This is **ephemeral and un-undoable by construction**: the edit does **not**
route through the `EffectEditSession` choke point, and there is **no writer** —
curve contents were deferred by this ADR's scope as "its own authoring surface."
The painter carries a **"Preview only — curve edits aren't saved yet"** note so
the ephemerality (and the shared-table blast radius) is honest, not a silent
"authoring surface that can't save is a demo" trap.

**Deferred (its own follow-up):** the curve-contents **save bridge** — a
byte-exact `write_effect_curves.py` + registry entry + `EffectCurveSaver` +
`studio_save` layering + round-trip guard — bundled with **session-routing +
undo** and, critically, the **shared-ownership design** (one edit, N referrers ⇒
the real home is a global curve-table authoring surface, not a per-param side
effect). Session-routing, undo, and save form one coherent package; building any
half now is infrastructure ahead of its design.

View guards may move (`EmitterProjectorTest`, sparkline/inspector view tests);
model/writer/saver guards must not. Acceptance is **headful screenshots** on
E317 emitter 6 (curves + short windows) and E019 (emitter-rich) — field dumps
don't count.

## Amendment — particle-timeline event editing (grilled 2026-08-12)

This lifts the `particle_timeline` deferral named in the Scope tier: emitter
**events** (the particle spans on the timeline — *when* an emitter fires and
*which* one) become editable, alongside the already-shipped emitter
**parameters**. The channel claims the reserved name "particle"
(`ParticleTimelineChannel.gd`). Add/delete-emitter of the fixed 14-slot *emitter
table*, `particle_system_header`, keyframe `action_flags`, and curve contents
remain deferred — this is timeline **events** only.

**Storage model (verified against the runtime).** A particle channel is a fixed
**25-slot, structure-of-arrays** struct (`parse_effect.parse_particle_channel`):
`time[i]` (s16), `emitter_id[i]` (u8, `0` = skip, `N` = spawn emitter `N−1`),
`action_flags[i]` (u16), and `max_keyframe` (last valid index, ≤ 24). `time` is
**cumulative-absolute** within the phase — `PhaseBlock` derives a keyframe's
period as `kf[N].time − kf[N−1].time`, and reads `keyframes[1].time` directly as
the first period, so **`kf[0].time` is pinned at 0 and never editable**. A
**span** is derived, not stored: `kf[N]` owns `[kf[N−1].time, kf[N].time)`; a
skip or zero-width keyframe draws no span (a **gap / null span**). One stored
`time` is the shared boundary between two windows.

**Precedent split.** The *boundary* insight (one stored number = one shared
edge) is camera-like, but the *addressing/undo* model is **palette/screen**, not
camera: particle channels are **flat — no sub-channels, no coalescing**, so
keyframes are 1:1 with storage and the stable address is a **raw keyframe
index** (phase + channel_index + index), not camera's split-surviving ordinal.
And because `time` is absolute (not length-encoded like palette's duration),
delete/merge leaves everything downstream auto-pinned — no length-fold.

**The invariant.** *An edit only ever consumes or creates gap (null-span) space;
it never changes another **drawn** span's extent.* Gaps are the currency; drawn
bursts are walls. This governs every verb:

- **Resize** — a right-edge grip per span edits one `kf[N].time` (every internal
  boundary is exactly one span's right edge; the origin has no grip). **Grow**
  consumes the adjacent gap and clamps at a drawn wall — to grow past a flush
  drawn neighbour the author **inserts a null span first** (Add). **Shrink**
  always works and **auto-opens a null span** in the vacated space (structural
  when the neighbour is drawn), never stretching the neighbour. A gap consumed
  to zero width is **auto-reclaimed** (its slot freed). Grow is a scalar
  drag-coalesced edit; shrink-against-a-wall and gap-reclaim go structural.

  > **Extended by [ADR-0095](0095-a-timeline-boundary-is-one-number-grabbable-from-either-side-and-a-drag-consumes-empty-space.md)
  > (2026-08-18)**, in two ways. (1) **Grips are now two-sided**: the grab band splits at the
  > boundary line, so `kf[N].time` is reachable from the span on either side of it. "The origin has
  > no grip" becomes the explicit floor `k ≥ 2` for a *left* grip (`_apply_boundary` refuses
  > `n ≤ 0`), and a **gap owns no grip at all** — its boundaries are grabbed from the drawn span
  > across the line. (2) A consuming drag becomes **self-inverse while held**: the session restores
  > the drag's first snapshot before each re-dispatch, so dragging back past a consumed gap
  > **restores it**. That is a behaviour change to this shipped gesture — today a consume is
  > irreversible within the gesture — taken so colour and particle drags do not become two dialects.
  > The invariant above (*gaps are the currency; drawn bursts are walls*) is unchanged, and ADR-0095
  > **generalizes it to colour-lane spacers**.
- **Move** *(built last)* — a body-drag shifts **both** boundaries by one delta
  (width preserved). Since times are absolute, the shift is absorbed by the two
  immediate neighbours, so **both must be gaps** (or a phase edge) — a burst
  between two gaps slides freely; a burst wedged between two drawn bursts is
  pinned. One compound undo (the sound fire-drag precedent).
- **Add** — insert a keyframe **born disabled** (`emitter_id 0` — a real gap, so
  Add never perturbs visible output), drawn dimmed, carrying a session-seeded
  remembered emitter (nearest previous drawn, else emitter 1). The author enables
  and/or retargets it. Refuse when the channel is full (25) — raise, never
  truncate (the camera writer's rule, applied at the verb).
- **Delete** — remove the keyframe; the next span closes up over the freed window
  (merge, downstream pinned); slot reclaimed. Snapshot undo.
- **Enabled + Emitter** — two scalar controls on the span inspector. **Enabled**
  toggles `emitter_id ↔ 0`, stashing the remembered `N` on a transient
  keyframe field (the screen/palette "kf-object stash"); a disabled span stays
  **drawn dimmed and selectable** via a session overlay the score consults.
  **Emitter** is a picker (`0…13`) editable even while disabled — it sets the
  remembered `N` and delivers **retargeting** (point a span at a different
  emitter) for free.

**Disable cannot persist — and why it differs from colour.** Screen/palette
disable survives save because those lanes have an enable field *separate* from
their value (ctrl bit-7 vs the RGB bytes). Particle `emitter_id` **conflates
enable and value in one field**, and the engine leaves no spare bit:
`PhaseBlock` spawns on `emitter_id != 0` (any non-zero fires `emitter_id − 1`;
a high bit spawns garbage) and fires a game-event on `action_flags != 0` (so
action_flags can't stash either). The only ROM-faithful "off" is exactly `0`,
which loses the emitter identity. So disable-with-memory is **session-only by
construction** — a saved-disabled span reloads as an ordinary gap. This is a
deliberate tier below colour's persistent disable; do not "fix" it with a spare
bit (there is none) or a sidecar file.

**Persistence.** New byte-exact `tools/write_effect_particle_timeline.py`
(section `particle_timeline` in `effect_writer_registry`) partial-patches all 15
channels (5 for_each + 5 phase1 + 5 phase2), writing all 25 slots + `max_keyframe`
verbatim so an unedited channel round-trips byte-identical (parse real E### →
re-serialize → identical — the gate). `EffectParticleTimelineSaver.gd` layers it
into `studio_save`; the manifest flips `particle_timeline` display→editable with
`projector_channel: "particle"`. **Build risk to clear first:** the SoA field
offsets (`time@0x00…`, `emitter_id@0x31…`, `action_flags@0x4A…`) sit close enough
to interleave — verify the exact on-disk layout via the parser and let the
round-trip guard gate the writer before trusting it.

**Every edit `invalidates_sim = true`** (particles are born during the sim; a
parked frame must re-fold — read-live is not available), with `relayout` /
`structural` wherever span geometry changes.

## Consequences

- The vocabulary table above is the naming source of truth for the projector;
  renames go through this ADR, not ad-hoc in code.
- Editing an emitter changes every span that fires it, in every phase — the
  shared-ness cue is load-bearing, not decoration.
- Deferred follow-ons (timeline events, add/delete emitters, curve contents)
  each get their own ticket; nothing in this design blocks them.
- The relevance oracle is only as honest as the Field Dependency Inventory
  behind it; an unguarded edge is a lie the inspector will tell confidently.
  The inventory + its sim guards are the deliverable; the markers are
  downstream.

## Amendment (design, 2026-08-12): velocity-family annihilation gate + formula view

Grilled 2026-08-12. Editing *Launch direction* on E317 emitter 6 does nothing,
because the engine computes spawn velocity as **direction × magnitude** and the
magnitude (*Outward speed* = `radial_velocity`) is 0 on that emitter → `velocity
= dir × 0 = 0`. The field is **read** every spawn; its value simply cannot move
the output. The relevance oracle did not model this, so a provably-inert family
still rendered as Live. This amendment adds the velocity-family gate and, with
it, sharpens the **Dead** definition and adds a **formula view** for the
annihilation mechanism.

**Static root (unambiguous), `ActiveEmitter.gd:95–145`** — the 4-mode dispatch on
`velocity_inward` (flags_lo bit 4) and `align_to_facing` (flags_hi bit 2):

| Mode (flags) | Launch direction / Direction scatter | Outward speed | cited gate |
|---|---|---|---|
| **Outward** (neither) | Dead **iff radial provably 0** | Live · Inactive@0 | `radial_velocity`==0 |
| **Unit-oriented** (both) | Dead **iff radial provably 0** | Live · Inactive@0 | `radial_velocity`==0 |
| **Inward** (inward only) | **Dead always** (omitted from `toCenter × speed`) | Live · Inactive@0 | `velocity_inward` |
| **Skip** (facing only) | **Dead always** (`velocity = 0`) | **Dead always** | `align_to_facing` |

Outward and Unit-oriented collapse to one rule (both do `dir × radial`), so the
oracle branches three ways, not four. Corpus note: across the 4 available emitter
corpora (52 emitters) `align_to_facing` is **never set** — Inward is common and
Outward-radial-0 is the motivating bug; **Unit-oriented and Skip are
correctness-completeness, not workhorses** (modelled and guarded, not given
bespoke UX).

### Decision 1 — Dead means "provably cannot change output", not "never read"

The prior Dead edges were all *literally never read* (behind an `if`, or
end-axis when `curve == none`). Radial-0 is the **read-then-annihilated**
mechanism: `angle_to_direction(base_angle)` **is** computed, then multiplied by
0. Both mean "editing it does nothing," and the **sim guard already tests exactly
this** ("set the gate, assert the field cannot move output"). So we **broaden
Dead** to cover both mechanisms rather than add a 4th state — the distinction is
mechanistic, not actionable, and the three-state model (with its opposite UI
treatments) is the whole point. (Glossary `Dead` updated.) The radial-0 gate is a
**structural copy of the homing gate**: `radial_velocity == 0` makes radial
itself *Inactive* (neutral 0) **and** the gate deading the direction fields —
exactly as `homing_strength == 0` is Inactive *and* deads target offset + homing
blend. Reuse `_all_read_values_equal(em, "radial_velocity", 0)` (curve-aware: a
radial that ramps 0→nonzero keeps the direction fields **Live**, conservatively).

### Decision 2 — the formula view with all-applicable marked culprits

For a Dead field killed by annihilation, the honest "why" is the **active
formula with the killing factor(s) marked** — the annihilation graph made
visible. An **annihilator** is a *zero factor in a product*. The view marks
**all applicable** culprits (a *set*, not one), under a guard-rail: **mark a zero
factor as annihilating a field only when that field is a live factor in the
active formula; when the mode instead omits the field, mark the mode switch as
the culprit, not the zero sibling.** In the velocity family this resolves to one
mark per Dead field; the set machinery is for honesty and for later compound
expressions (`pos = pos0 + v·t + ½a·t²`, where `v` and `a` can both drop).

Rendered **once per velocity Dead-reveal section** (not per row), **only when
something in the family is Dead** (a fully-Live Outward emitter shows nothing),
with an imperative fix line and **flag *labels*, not mode-name jargon**:

```
Outward / Unit-oriented, radial 0:
    velocity = direction × speed(0 ✕)
    ⇒ Launch direction, Direction scatter unused — speed annihilates them
    → set Outward speed > 0
Inward ("Pull velocity inward" on):
    velocity = (toward center) × speed
    ⇒ Launch direction, Direction scatter unused — not in this formula
    → turn off "Pull velocity inward" to aim them
Skip ("Align to unit facing" on, inward off):
    velocity = 0
    ⇒ Launch direction, Direction scatter, Outward speed unused — no motion
    → turn off "Align to unit facing"
```

**Scope:** velocity family only this pass. The other Dead families are
branch-omission, not multiplicative annihilation, so their one-line why-string
already suffices — the formula view is not retrofitted onto them.

### Precedence & reverse edges

Dead **overwrites** the group's own Inactive/Live; the end-axis-collapse +
sparkline logic only ever matters in the surviving Live case (Outward, radial >
0). `velocity_inward` and `align_to_facing` join the gate-slot loop (mirroring
`color_curve_enable`) so `_link_reverse_edges` attaches their "Suppressing: …"
markers to the existing "Pull velocity inward" / "Align to unit facing" config
rows; `radial_velocity` is already a group and carries its reverse edge like
`homing_strength`.

### Guards (static-rooted AND real-sim validated)

`EmitterFieldRelevanceSimGuardTest` (source of truth over this ADR): Outward
radial-0 varies base_angle → spawn velocity stays ZERO (positive control at
radial≠0 already exists — `_guard_align_to_velocity_does_not_dead_launch_angle`);
Inward varies base_angle → velocity unchanged; Skip varies base_angle **and**
radial → velocity ZERO. Must stay consistent with the two REFUTED edges already
encoded (`…_does_not_dead_launch_angle`, `…_velocity_inward_not_moot_when_radial_zero`
— the gate is on velocity **direction** fields, never position). Plus per-mode
oracle-verdict cases in `EmitterFieldRelevanceTest`, a `render_signature` case
(radial 0→nonzero un-deads base_angle), and headful acceptance on **E317 emitter
6** (`EmitterRelevanceAcceptanceTest`).

## Amendment (2026-08-12) — authoring presents game units; raw stays authoritative in storage

**What changes.** The original build is **raw-authoritative at the surface**: the
human types raw PSX s16 values into cells and game-units are only a computed
display cache. The mandate is that game-side work speaks the game's units and
coordinate system — and that extends to the **authoring surface**: the human
should read and edit **game units** (position→tiles, angle→degrees,
velocity/accel/weight→game scale), never bare PSX fixed-point.

**Decision.** Move the units conversion boundary to the **cell**, not the storage:

- **Presentation + input become game units.** Unit-bearing cells display game
  units and accept game-unit *input*; the cell converts game→raw on commit via
  the single conversion home ([`PsxUnits`](0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md)),
  and raw→game for display. `EmitterChannel`'s inline divisors are deleted in
  favour of `PsxUnits`.
- **Storage, undo, and byte-exact save stay raw** — untouched. This is an
  **amendment, not a reversal**: byte-exactness (ADR-0089's actual point) is
  preserved. Raw stays authoritative *in storage*; game-units become
  authoritative *in presentation*. Out-of-range game input maps to an
  out-of-range raw and is **refused** (no clamp), exactly as raw input was.
- **Round-trip display is honest.** After a commit the cell re-derives its
  shown value from the stored raw, so what the human sees is what was actually
  stored (game→raw→game), not the un-rounded keystroke.

**North star (committed, sequenced later).** "No bare integers reach the human"
generalises past units: enum→named options, flag→checkbox, id→named picker. That
humanization is the same principle applied to non-numeric fields and lands
incrementally after the numeric boundary is consolidated.

**Sequencing.** This amendment **rests on ADR-0091**: the game-unit authoring
flip needs `PsxUnits` to exist as the both-directions home first. The units/coord
*consolidation* (single home, guard, ad-hoc converts pulled to the seam) lands as
its own pass; the studio cell input-flip is the immediate follow-on.

## Amendment (design, 2026-08-12): span-anchored playhead marker on emitter-elapsed curves

Grilled 2026-08-12. The complaint: *"authoring curves is difficult because it's
hard to map the curve to the playhead — at what frame are we at which part of the
curve?"* Grilling surfaced the root cause and scoped the fix to the tractable half.

**Root cause — curves clock in three different domains, and the surface never said which.**
An emitter parameter's curve is not read on one clock:

| Clock | Sampled at | Which curves | Playhead map |
|---|---|---|---|
| **Emitter-elapsed** | `ActiveEmitter.elapsed_frames` (at spawn) | Emitter group (position, spread, particle count, spawn interval) + Particle · born-with (velocity angle/spread, radial velocity, weight, drag, acceleration, inertia, lifetime, homing strength, target offset) | **single-valued** |
| **Particle-age** | `particle.age` | Particle · over-life: colour R/G/B (`EffectParticleRenderer:252`), homing blend (`ParticlePhysics:108`) | **per-particle** (many alive at one playhead, each at a different age) |
| **Callback frame** | callback `_frame_counter` | callback mesh/colour curves | direct (out of scope here) |

The felt ambiguity is *specifically* the particle-age case — there is no single
"the curve is here now." But the user's actual authoring target is the
**emitter-elapsed** family, and *that* map is clean: at playhead `P`, a firing
that started at `span.start` is at `elapsed = P − span.start`, and the curve is
read at index `elapsed % 160` — one frame, one point. This amendment builds the
marker for the emitter-elapsed family only. The particle-age family (colour /
homing blend) is **explicitly deferred to its own mechanism** (a
[particle-age cloud / reference-particle marker], not this one) — those
sparklines get **no** emitter marker.

**Decision — a read-only, span-anchored playhead marker.**

- **The mapping is pure geometry, not a live-cast read.** `elapsed = P −
  span.start`; curve index `= elapsed % 160`. No particle enumeration — unlike
  the age case, an emitter-elapsed curve's read site depends only on the playhead
  and the firing's start. This is the one non-negotiable: **the marker sits
  exactly where `EffectCurve.sample_by_frame(elapsed)` reads**, so it can never
  lie about what the sim samples.
- **Surfaces: both.** The [curve painter](../context/16-effect-studio-authoring-tool.md) (primary —
  where authoring happens) and the inspector [curve sparklines](../context/16-effect-studio-authoring-tool.md),
  one shared computation. Only emitter-elapsed-clocked curves draw it; the
  projector must **tag each curve's clock domain** so the over-life sparklines
  (age-clocked) opt out.
- **Read-only.** The marker tracks the playhead; there is no click-to-seek
  (curve → playhead) and no reserved gesture for it — the painter canvas stays
  paint-only. Bidirectional coupling is a possible later increment, not a seam
  threaded now.
- **Out of span** (`P < start` or `P > end`): clamp the marker to the nearest
  curve edge, **dim** it, and show a one-word *before / after firing* tell — a
  marker that silently vanishes reads as a bug; the emitter isn't sampling there.
- **Label:** on the painter, a two-ended tag `elapsed N · fF` (the bridge is the
  feature — naming both the emitter-elapsed coordinate and the absolute effect
  frame is what teaches the map). On sparklines, a **bare line only** (up to ~14
  stacked; per-line text is noise, and they share one vertical reading).
- **Wrap** (firing duration > 160): position is **always** `elapsed % 160`
  (correctness); the painter adds a `×N` lap tag when `elapsed ≥ 160` so a marker
  jumping back to x=0 isn't mistaken for a glitch; sparklines show the wrapped
  position only.
- **Target policy:** the marker requires a **span** target (a concrete firing
  start). A browsed or drilled emitter (no governing firing — a child emitter
  fires at times the origin span doesn't define) draws **no marker + a one-line
  hint** ("select this emitter's span"). Auto-resolving "whichever firing is
  active at the playhead" is deferred (ambiguous under overlap; needs a
  spawn-schedule lookup).
- **Cadence:** **continuous** — the marker redraws each transport tick during Play
  (page-driven, [ADR-0090](0090-effect-studio-region-loop-is-a-session-span-driven-by-a-page-side-bounce-transport.md))
  and on every scrub, so it sweeps across the curve over a looped region.

**Semantic note (docs / tooltip, not a build knob).** An emitter-elapsed curve is
read *once at spawn*, so the marker shows *the value being assigned to particles
spawned **this** frame* — not the state of the particles currently on screen
(those were born earlier, at earlier curve points). This is exactly the emitter's
authoring model ("how does the emission evolve over the burst"); the over-life
map, when it lands, answers the other question ("what does one particle do over
*its* life").

**Guard (static-rooted, dynamic-validated — the repo rule).** The correctness
anchor is not an eyeball: fold to a scrubbed playhead `P`, read the live
`ActiveEmitter.elapsed_frames` for the selected span's firing, and assert the
marker's curve index `== elapsed_frames % 160`. That pins the marker to the sim's
actual read site and resolves the authored-vs-compiled `start` offset (ghost
frames et al.) empirically rather than by guessing.

**Sequencing.** Design doc first (this amendment + CONTEXT vocab), then `/tdd`:
pure `elapsed`→index mapper (with clamp + wrap) → the marker view on painter and
sparkline → headful acceptance with the fold-and-compare-`elapsed_frames` guard.
Deferred: the particle-age marker (its own mechanism), bidirectional click-to-seek,
callback-frame curves, and auto-resolving the active firing for non-span targets.

## Amendment (design, 2026-08-12): colour-keyframe authoring — author the muxed colour, invert to curves, stay inside the reachable box

Grilled 2026-08-12. The complaint, in the user's words: *"the biggest problem is
some colours are not even attainable."* The prior handoff framed the work as
"add keyframes + interpolation so authoring the dense 160-sample colour curves
isn't unwieldy." Grilling reframed it: the keyframe UX is the *lesser* half. The
felt problem is a **gamut** problem, and it is orthogonal to keyframe ergonomics
— a slicker RGB picker on the current model would let you pick pure red on a
green sprite and silently render **black**, a worse feature, not a better one.

**Root cause — colour is a multiply, so the curve can only attenuate the sprite.**
The render is `ALBEDO = sprite_texel.rgb * colour_curve.rgb`
(`assets/shaders/effect_particle_opaque.gdshader:27`), and the curve is a plain
`byte/255` in `[0,1]` (`EffectData.gd:70`) — **no** PSX-style `0x80`-neutral 2×
headroom in this pipeline. So for a sprite texel `S`, the *entire* set of colours
the three curves can produce is the box `[0,S.r]×[0,S.g]×[0,S.b]`. A green texel
`(0,1,0)` makes red and blue **dead** — no curve value lights a channel the sprite
lacks. The author authors the *inputs* (`cr/cg/cb`) but cares about the *output*
(what renders), and the mux between them is exactly what makes "0–255 in every
channel = every colour" an illusion: the input cube is full, the output is squashed
into that box. This is issue #293 (dead-channel salience) generalised from "this
channel is dead" to "here is the whole box this emitter can and cannot make."

**Decision — author in muxed (output) space; the tool inverts to curves and never
offers an unreachable colour.**

1. **Faithful multiply stays.** The multiply *is* the effect (faithful PSX
   reimplementation); we author **within** the gamut, not by augmenting the shader.
   Rejected alternative (B): a lerp/replace term or per-frame sprite re-tint to
   reach arbitrary colours — that renders differently from the game and makes the
   studio a superset the game can't reproduce.
2. **Author the muxed colour.** The author picks the **[muxed colour](../context/16-effect-studio-authoring-tool.md)**
   `T` (what renders); the tool applies the **[inverse mux](../context/16-effect-studio-authoring-tool.md)**
   `curve = T ⊘ S` (per channel) to get the curve values. The author never touches
   `cr/cg/cb` directly.
3. **Reference `S` = the emitter's one peak-luma representative texel** — the same
   `EmitterSpriteColor.representative()` the [colour ribbon](../context/16-effect-studio-authoring-tool.md)
   already shows, so picker and ribbon can never disagree. Chosen over a per-frame
   reference (the texel changes as the animation advances): one gamut box per
   emitter; the picked colour is hit exactly on the peak-luma pixel and every other
   pixel rides along proportionally (a tint that preserves the sprite's internal
   luminance). Per-frame gamut is deferred (#293-adjacent).
4. **The picker is a normal RGB/HSV picker clamped to the [reachable box](../context/16-effect-studio-authoring-tool.md)**,
   seeded from the current ribbon colour. A **dead channel** (`S.k = 0`) is a
   disabled slider locked at 0; colours outside the box are simply not selectable.
   This is the direct answer to "how do you even select a muxed colour" — there is
   no regress, you pick in output space inside a bounded region.
5. **A [colour keyframe](../context/16-effect-studio-authoring-tool.md) is a joint colour-at-a-frame** —
   one colour sets `cr/cg/cb` at frame F together; there are no independent
   per-channel keyframe times. Keyframes are the authoring layer; the dense
   160-sample curves stay the compiled artifact (`c[f] = T[f] ⊘ S`). Because `S`
   is constant per reference, interpolating the target colour and interpolating the
   curve are the **same** math — no reconciliation drift.
6. **Interpolation = linear RGB lerp only.** The box is **convex**, so a linear
   segment between two in-box keyframes stays inside the box — every in-between
   frame is attainable, no clamping. HSV/eased/hold-segments are deferred *because*
   they can bulge outside the box between two legal endpoints (needs `T ⊘ S > 1` →
   clamp) and would require the honest-quantization tell used for units.
7. **Ownership = per-emitter copy-on-write.** Colour curves are a **shared table**
   — real effects share pervasively: `E019` em1 and em2 both reference `(0,2,2)`,
   curve `0` is the red channel of ~10 of 14 emitters, and many emitters **alias
   channels within themselves** (`E019` em0 `(0,0,0)`, `E317` em0 `(3,3,3)`) so
   `cr=cg=cb` — those can only ride the brightness ray `k·S`, not the full box.
   First colour-edit **forks the emitter's channels into 3 independent curves**;
   the un-alias is what unlocks the box. Allocate an unused curve index, else
   append — **the game curves array is unbounded**; the 4-bit `& 0x0F` nibble cap
   (max 16 colour-addressable slots) is a **BIN-pack constraint only**
   (`parse_effect.py` masks on *read from* BIN; the game loads `curves.json` and
   references by full index). If the author only moves brightness, the pack step
   dedups the three equal curves back to one shared slot.
8. **Enter = import, not replace.** Keyframing an emitter that already has a ROM
   colour curve **fits keyframes to its 160 samples** (breakpoint detection) — no
   visual jump, and exact for the common piecewise-linear ROM curves; genuinely
   curvy segments approximate with the honest-quantization tell. Rejected: seeding
   a single flat keyframe (snaps an existing animated fade to flat the moment you
   click "edit colour").
9. **Save = the game-JSON half now.** Append the forked curves to `curves.json`
   and repoint `emitters.json` by full index — this persists and **works in-game**
   (the game loads JSON). The **byte-exact BIN half** (the `write_effect_*.py`
   two-half saver pattern) needs the ≤16-slot reconciliation + alias-dedup, which
   is the hard, growable-count problem the fixed-slot savers don't have — deferred
   to #292/pack. Undo rides the studio's existing snapshot-undo, same as the other
   channels.

**Parked, separately (not this feature) — a possible fidelity bug.** `byte/255`
maps PSX-neutral `0x80` to `0.502`, so a "neutral" modulation renders at half
brightness and only `0xFF` reaches full; the static-modulation path corroborates
neutral = `128` (`emitters.json rgb_modulation: [128,128,128]`). If the ROM
colour bytes are genuine PSX texture-modulation semantics, the game may render
effects dimmer than PSX, which *compounds* attainability. This is a render-parity
question logged on its own, not part of colour authoring — and it doesn't rescue a
dead channel either way (`k · 0 = 0`).

**Deferred:** the BIN pack/≤16-slot reconciliation + alias-dedup (#292); HSV/eased/
hold interpolation; per-frame reference gamut (#293-adjacent); and the real answer
to reaching a colour *outside* the box — *"this sprite can't make red; switch to a
sprite/animation that has red texels"* guidance (sprite/animation reassignment).

**Sequencing.** This design doc + CONTEXT vocab first, then `/tdd` in parity-guarded
slices: pure `inverse mux` + box clamp (a keyframe compile-down must reproduce a
known dense curve, and the ribbon read path stays byte-identical) → curve→keyframe
**import** (breakpoint fit, exact-for-piecewise-linear guard) → the box-clamped
picker + dead-channel lock → keyframe place/move/delete on the ribbon/sparkline
scaffolding → game-JSON save → headful verify on a colourful effect (E317/E019).

### Amendment (design, 2026-08-13): colour-keyframe editing UX — author on the band, not in a popup

The muxed-colour model above shipped, then landed a follow-up (the particle-**age**
keyframe track + a compact grid picker, commit `0de188c11`). Using it surfaced UX
friction; grilled 2026-08-13 and settled the following. This is authoring ergonomics —
the gamut/inverse-mux model is unchanged.

1. **Picker = inline, in a collapsible fold (default expanded), not a popup.** The
   swatch-button-opens-a-popup was annoying (a click every edit). The full colour grid
   lives inline in a collapsible section: expand once, it stays.
2. **The colour band itself is the click target; keyframe handles ride a lane ABOVE it.**
   The ribbon stays a **pure renderer**; a transparent interactive overlay on top owns the
   clicks (so the band *feels* clickable without breaking the ribbon's pure-view contract).
   The small on-band dots were hard to see against the colours, so handles move to a
   high-contrast lane above the band.
3. **Real-vs-interpolated must be unmistakable.** A **solid handle = a real (deletable)
   keyframe**, with a thin tick to its column on the band; an **empty lane = interpolated**;
   a **ghost handle under the cursor** on an empty spot telegraphs that a click will *add*
   one. Selected handle is highlighted. This also removes the accidental-add worry (the
   ghost shows intent before committing).
4. **Sparse authoring is by DELETE; interpolation already exists.** Between keyframes the
   colour already lerps — you author only what you place. The felt problem was that **import
   fits several keyframes to the ROM curve** (to avoid a jump), so you *see* many. Resolution:
   thin them out — select a handle → **Del** (or right-click → Remove); the curve interps
   across the gap; re-adding is trivial. Import stays as-is (no jump). Rejected for now: a
   non-destructive per-keyframe **disable** toggle (delete + easy re-add covers it; the flag
   would thread through the model + save for marginal gain).
5. **Live R/G/B rows (a bug, not a design change).** The three `Color (R/G/B) · curve`
   sparklines + dropdowns are **snapshots** rebuilt only on a full reproject; the recolour
   path did a light in-place refresh of the ribbon + track but not these, so they went stale
   ("the curves on the left aren't updating"). Fix: the recolour refresh also re-feeds the
   three colour sparklines + dropdown labels. Verified the **fork is NOT the cause** — E019
   emitter 0 starts fully aliased (`r=g=b=curve 0`) and a recolour correctly un-aliases into
   3 fresh appended curves (`15/16/17`). Also fix the cosmetic label (an appended forked
   curve shows as raw "16/17" instead of "Curve N" because it's past the original list).

**Not in this round (still parked):** "**adjust the colour space of the picker**" (remap the
grid onto the reachable gamut vs an OKHSL model) — current behaviour stands (full grid, pick
anything, author the nearest reachable colour, ribbon shows the truth); and a separately-
reported **phantom "second emitter"** (own diagnosis, untouched here).

**Sequencing** (`/tdd`, parity-guarded): live sparkline/dropdown refresh (the bug) → inline
collapsible picker → band overlay + handle lane (solid/empty/ghost, select/add) → delete UX
(Del + right-click Remove) → headful verify on E019.

### Amendment (build, 2026-08-19): the track's domain is the ribbon's window, and the band is a FIXED width

Reported as a regression: *"the key frames are either too far out, or the ribbon is too
short — but to be honest it's too wide anyway."* Two separate faults, one of them years old.

**1. The track and the ribbon were on different domains.** Decision 2 above put the handles
in a lane over the band and said they share the ribbon's particle-age axis. They did not.
The ribbon paints `life_n` bands — the particle's lifetime. The keyframes come from
`ColourKeyframeFit.import_from_curves`, a Douglas-Peucker fit over **all 160 curve samples**,
and DP always keeps the terminal point — so **every colour emitter in the corpus carries a
keyframe at frame 159**. `x_of_frame` does not clamp and the track does not clip, so those
handles painted **outside the control**. Measured on E317 emitter 3, a 432px track with a
16-band window:

| keyframe | drawn at | relative to the 432px track |
|---|---|---|
| frame 20 | x = 540 | 108px outside |
| frame 26 | x = 702 | 270px outside |
| frame 159 | x = 4293 | 3861px outside (off-screen) |

All 27 colour emitters sampled did it, and some are mostly dead zone — E241 emitter 2 has a
**2-frame** window and 23 of its 24 keyframes beyond it.

**`life_n` is `life.max()`, the UPPER bound of what the renderer ever reads**, so a keyframe
past it edits samples the game never looks at. The track's domain is therefore the ribbon's
window: out-of-window keyframes are neither drawn nor hit (`in_window`), and the count is
**stated in the hint line** — *"· 3 past this particle's life, not shown"* — because
dropping data silently is the other way to be wrong. Rejected: widening the window to cover
the keyframes (every emitter has one at 159, so that is just "no trim at all"), and re-fitting
the import to `[0, life_n)` (it would compile the dead-zone samples flat, rewriting file bytes
to fix a drawing bug).

> The count was first drawn in the handle lane at the band's right edge. It landed **on top
> of the last two handles** — which is exactly where handles crowd on a short window. Prose
> belongs in the prose line; the lane is for handles.

**2. The band is a FIXED width — `ColourKeyframeTrack.band_width`, an ADR-0068 static-var
home.** It used to take half the section body through `EXPAND_FILL` (commit `20193f5f1`), so
each band's width was a function of the window and of whatever else shared the row: 432px on
a 903px inspector, 567 on an 1187px one. The same emitter read differently at two window
sizes and two emitters were never comparable. Fixed, `width / n` is a pure function of the
life window — the author's rule verbatim, *"the distance between frames is a function of
total frames"* — so a 2-frame life gets fat bands and a 40-frame life thin ones, and that
difference now **means** something.

**260 was chosen against the corpus**, not picked: 2621 colour emitters across 400 effects
have a median life window of **16** bands (p25 11, p75 21, p90 32, p95 40, p99 65; only 0.2%
paint the full 160). At 260 the median frame is 16.2px — comfortably wider than a 7px
handle — and 93.7% of emitters clear 7px/frame. The tail pays: at p95 (40 bands) a frame is
6.5px and adjacent handles touch. `nearest_keyframe` still resolves those clicks, and the
static var moves the number without a rebuild.

**Measured non-effect on the inspector row:** the track's declared minimum went 52 → 260, and
`content_width()` is what ADR-0100's column arithmetic reads. E019 emitter 0 declares **812
before and after**, and the sequence player's column stays **276** — the sections' own
minimum (555) was already the binding term. Guards: `ColourKeyframeTrackTest` 50.

## Amendment (design, 2026-08-13): directional Y authors game-up — the chirality half of the game-unit flip

Grilled 2026-08-13. The complaint, recurring for months: *"we've tried multiple
times to remove this -Y is up contention but for some reason it persists. For the
emitter start/end position [it] has this backwards convention."* An author dials
**Position Y = +2** and the particle goes **down**. Every prior attempt deleted the
wrong `-Y`; this amendment names why, and fixes the actual gap. The gamut / units
model is unchanged — this is the **chirality half** of the game-unit amendment
above (which did *magnitude* only).

**The trap — there are two `-Y` sites doing different jobs; removal kept hitting
the wrong one.**

- The **runtime / parser negation** (`parse_effect.py:74` `convert_position`,
  `EmitterChannel._convert:373`, `ParticlePhysics`'s `Vector3.DOWN` base) is the
  **honest, correct, test-locked** conversion of PSX `-Y = up` → Godot `+Y = up`,
  so the game renders right. It is proven empirically (only a `+π` half-turn
  reproduces the cloud — *not* a sign flip; the [PSX-units cleanup]
  (0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md)
  §Consequences deviation 2) and locked by `ParticleEmissionDirectionTest` /
  `EmitterChannelTest`. **Deleting it flips every effect's vertical motion and
  breaks byte-exactness** — which is exactly what got tried and reverted. *This is
  not the contention.*
- The **authoring cell** (`EmitterParamRows._read_vec3`/`_fmt_raw` →
  `ParticleUnits.POS_TILES`) shows `read_raw ÷ 28` — **magnitude only, no
  chirality**. `PsxUnits.tile_to_game` even says *"the caller applies any
  Y-flip"* — and no caller does, on the authoring path. So the author edits raw
  PSX `-Y = up` while the screen renders `+Y = up`. **That is the contention.**
  The 2026-08-12 game-unit amendment converted magnitude into the editor but never
  the chirality axis (ADR-0057), so this half was left open.

**Decision — flip the directional Y cells to game-up.**

1. **Scope = directional fields only.** The flip applies to the Y cell of
   **position** start/end, **target-offset** start/end, **acceleration**, and
   **drag** — every field whose Y sign is *visible on screen*. It does **not**
   apply to **spread**: spread is a symmetric **extent** (`_apply_spread` samples
   `randf(-s, s)` box/sphere; `_rotate_y` never touches the Y component), so its
   Y sign is **provably inert** and a negative-looking "extent" would mislead.
   This pins a domain distinction *within* the pos-scale fields: **directional
   placement** (Y sign meaningful) vs **extent / scatter** (Y sign inert). See
   the CONTEXT.md *Directional field vs Extent field* term.
2. **Mechanic = show what the sim already caches.** A directional Y cell displays
   `−raw / 28` and commits `raw = −typed · 28`. This makes the cell show **exactly
   the Godot-unit value the sim reads** (`EffectEmitter.position_start.y`, in
   tiles): **author-sees == author-uses**, byte-for-byte reversible — the same
   honest-round-trip invariant the units amendment set. Storage, undo, byte-exact
   save, and the runtime negation are **untouched** (an amendment, not a
   reversal).
3. **Predicate home = a separate, authoring-only `directional` rule.** `_convert`
   (the sim cache) is **left alone** — it keeps flipping spread inertly. The
   authoring path gets its own `directional` predicate (the four field families
   above, excluding spread), so the smallest-blast-radius change can never disturb
   the test-locked cloud. A guard test asserts the two predicates **agree on all
   directional fields** (they differ only on spread).
4. **RE honesty.** A directional Y row's tooltip surfaces the **signed raw value +
   a "shown game-up" note** (e.g. `raw: position_start_y @0x54 = -56 (Y shown
   game-up)`), so cross-referencing a cell reading `+2` against a `-56` byte in a
   RAM dump still reconciles.

**Not an ADR-0052 inconsistency (retires the red herring).** The felt "backwards"
is *not* the half-applied 180°-about-X rotation (Y-only vs the map's Y-and-Z).
**Effect-local coordinates are their own spatial subsystem** (`parse_effect.py`),
empirically Y-only; ADR-0052's map rotation — and especially its `size_z`
depth-mirror — governs **map / scenario** geometry, **not** effect emitter offsets.
Applying the map Placement rule to an effect offset is itself a category error.

**Build note (not a decision).** The added negation is the **chirality** axis
(ADR-0057), distinct from the `tools/check_no_raw_psx_units.py` **magnitude**
guard; it routes through the named `directional` predicate and keeps the banned
`-Y=UP` *reasoning* token out, so the guard stays green.

**Sequencing** (`/tdd`, parity-guarded, follow-on session): pure `directional`
predicate + display/commit flip at the cell → guard test (authoring predicate
agrees with `_convert` on directional fields; a directional Y round-trips
`game→raw→game`) → tooltip signed-raw note → **headful verify on E019**: pick an
emitter with nonzero position Y, dial **+Y**, confirm the particle moves **up** on
screen while the stored byte moves the opposite way. Storage / save / runtime
guards must not move.

## Amendment (2026-08-19): Move is not particle-only — colour and camera arm the same gesture

**Status:** accepted (grilled with the author 2026-08-19). **NOT YET BUILT.**
The colour half — slot budget, 1-frame padding, coarse/fine degradation — is
specified in **[ADR-0101](0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md)**;
this amendment records only that the gesture generalizes and on what terms.

The `particle_timeline` amendment above built Move as a general mechanism —
`span_body_drag_started/dragged/ended`, the single-snapshot undo bracket, the
per-`_process` pending flush, the deferred refold — and then armed it behind a
single hard gate:

```gdscript
if String(hit["span_id"]).begins_with("particle:"):
```

Everything above that line is kind-agnostic; only the arming is not. **Palette,
screen and camera now arm it too.** The semantics are `plan_move`'s, unchanged
and deliberately not re-derived per kind:

- one clamped delta shifts **both** of the span's boundaries; its **width is
  preserved**;
- the shift is absorbed by the **two immediate neighbours**, which must both be
  holds — a span **wedged** between two drawn spans is **refused**, in the
  existing `{ok: false, reason: "wedged: …"}` vocabulary;
- everything **outside** those two neighbours stays pinned at its absolute frame;
- the first span, having no movable left boundary, cannot slide.

What differs per kind is only what a "hold" is and what a boundary write costs.
Camera is the cheap case: absolute `end_frame`, no quantization, no padding, no
budget — Move there is literally the two-boundary write, and its hold predicate
(`CameraValueSemantics.is_spacer`, `MAP`+0) is decidable locally. Colour is the
expensive case: length-encoded `time_value`s, a fold-derived hold predicate, and
a finite supply of keyframe slots — all of which ADR-0101 owns.

`plan_move` stays the one place the *rule* lives; the per-kind channel supplies
the edits it plans over. Particle's own behaviour is unchanged.

## Amendment (2026-08-20): a STRUCTURAL Move touches no structure until release

**Status:** accepted, **BUILT**. Supersedes the per-motion apply for every kind
whose Move is structural — the two colour kinds and camera. Particle keeps the
per-motion apply: its Move is two scalar `boundary_raw` writes, with no insert,
no delete and no renumber, so there is no structure to be free of.

*(Written first for the colour kinds and extended to camera the same day, for
the reason the camera section at the end records: camera's fault was never the
clock, it was the churn.)*

The amendment above armed Move for palette, screen and camera. It armed them on
the **apply-per-motion** path the particle drag already used: every motion
restored the grab snapshot, re-planned, and executed the splice. For particle
that is two scalar boundary writes and for camera a small table relower, so
neither notices. For the colour kinds the splice is **structural** — padding
keyframes are minted, an emptied hold run is deleted, and the whole lane is
renumbered — and the reprojection behind it re-runs the fold-derived spacer
oracle.

Measured on E317 through the author's own repro
(`palette:for_each:affected_units` `#1`, the real page drag handlers, an
18-motion cursor sweep): **82.9 ms mean per motion, 108 ms worst** — about
10 fps, so the span stopped tracking the cursor for a tenth of a second at a
time. The lane's edge-grip count **oscillated 64 ↔ 71** as padding appeared and
vanished with each frame of cursor travel: real hit geometry moving under the
cursor between grabs.

None of that work survived. `move_preview` restores the pristine snapshot and
re-applies the **absolute** delta from grab, so the model was already stateless
with respect to the gesture's path — every motion threw the previous motion's
splice away and re-planned from the same frozen context. The per-motion answer
was always a pure function of (grab context, absolute delta).

**Decision.** For `palette` and `screen`, a motion **plans and stops**:

- `ColourMovePlan.preview(ctx, n, delta)` — the existing pure planner, returning
  the clamped delta and its granularity, splicing nothing;
- `EffectEditSession.move_preview` writes **no keyframe** and reports that delta;
- the page hands it to `EffectScoreTimeline.set_move_preview(span_id, dx)`, which
  draws **that one span** at `start + dx` and leaves every other rect alone;
- `end_move` performs the splice **once**, at the last previewed delta, against
  data no motion touched — so it is byte-for-byte the discrete verb's own result;
- release then reprojects **once** and drops the offset onto the committed lane.

Measured after: **0.04–0.06 ms mean per motion**, grip count **pinned**, and the
mid-drag preview is **pixel-identical** to the committed lane (0 of ~1.4M pixels
differ over the lane row). The whole gesture's structural cost is one 180 ms
release.

**The offset drawn is the planner's, never the cursor's.** The motion still
plans precisely so the preview cannot promise a landing release refuses — over-
drag past the room the two hold runs can trade and the preview pins at the clamp.

**A refused motion answers `delta: 0`, not `{}`.** `{}` stays reserved for "there
is no live gesture to address". The page must tell *draw it at home* apart from
*no answer*, because the motion before it may have previewed a slide the author
has since dragged back off — with the data untouched all gesture, that zero is
the only thing that un-moves the span.

**Grips are silent during a preview.** The dragged span is the selection, so its
grips are drawn, and they sit on the boundaries the score still reports — which
the bar has just slid away from. A resize handle where there is no longer an edge
is a lie; they return on release, against the committed lane.

### What this does not fix

The author also reports a Move that "gets frozen and can't move". Four mechanisms
were measured and ruled out (planner refusing the return trip; the 9 px boundary
grip stealing the grab; ADR-0101 decision 4's slot-budget trap; painter and
planner disagreeing mid-drag). Lag was the leading remaining explanation and is
now gone. One **unsignalled** refusal remains genuine and is not addressed here:
a span with a hold in front and a drawn tween hard behind can only ever move one
way, and refusing the other direction looks identical to a freeze.


### The camera arm — the same change, for a different reason

Camera was left on the per-motion path in the first pass because it is not slow:
**2.98 ms mean per motion** on E317's `for_each` angle lane, against colour's
82.9 ms. It tracks the cursor exactly, lands where asked, and round-trips. Four
further suspicions were measured and ruled out before touching it:

| theory | measurement | verdict |
|---|---|---|
| a Move on one sub-channel disturbs the others | every camera lane compared either side of an angle Move on E317/E043 — only the dragged lane and its read-only compiled view change | **not it** |
| a round trip silently destroys the table | 21 keyframes → 3 looked alarming; indices 4–20 are `end=0 cmd=0x0000` **null padding**, and all 12 camera lanes are byte-identical after the trip | **not it** |
| the manufactured hold's grip steals the grab back | pixel-scanned `hit_test` along the landed span's row: 147 of 156 px still resolve to `select` — **94 % grabbable** | **not it** |
| the span fails to track the cursor | 18-motion sweep, asked → got, exact at every step | **not it** |

What is real is the **churn**. Camera's apply manufactures a lead hold, deletes
an emptied one, and RENUMBERS the lane — so on E317 the drag id went `#0` → `#1`
on the **first motion**, and the page then chased the selection across the lane
underneath the cursor (`_follow_structural_move`, every motion) while the stored
table was rewritten sixty times a second for a preview that is one rectangle
moving. Structure-free, the gesture renumbers exactly **once**, on release.

  per-motion   2.98 ms  ->  0.10 ms
  table        rewritten every motion  ->  byte-identical to the grab
  drag id      #0 -> #1 on motion 1    ->  #0 for the whole gesture

`CameraChannel.plan_move` was already pure — it parses the table into fresh lanes
and computes over those — so the preview is that planner called on its own, with
no context to capture (camera's hold predicate is local: `MAP` + zero). The
session routes it in `_preview_move`, mirroring `_perform_move` so the two cannot
answer differently about the same gesture.

Guarded by `EffectCameraMoveTest` (the model seam) and a page-level guard in
`EffectStudioEdgeDragWiringTest` that pins the **drag id never renumbering**;
both go RED by dropping `camera` from `_is_structure_free_move`.

### Still open, and now the leading candidate for "it won't move"

**108 of 367** drawn camera spans across the sampled corpus (29 %) refuse to move
at all — wedged between two drawn events, which is the rule working — and the
refusal is **completely unsignalled**. The author drags and nothing happens. That
is the same fault the colour section above flags for the one-way span, and on
camera it is nearly a third of the lane population. Nothing here addresses it.


## Amendment (grilled, 2026-08-20): a curve belongs to its USE SITE; the shared ≤15 table is an EXPORT FORMAT

Decision 7's **conclusion** stands and is now the load-bearing premise of everything
below: *the game curves array is unbounded; the 4-bit `& 0x0F` nibble cap is a BIN-pack
constraint only.* What this amendment replaces is decision 7's **mechanism** — the
per-emitter copy-on-write fork — and it dissolves the third leg of #292 ("a global
curve-table authoring surface"), which was the honest answer to a shared table that no
longer exists at authoring time.

The one-line statement: **authoring has N private curves; compiling to PSX is what
produces the shared, indexed, ≤15 table.** Sharing is an output format, not a model.

### Why now — the blast radius is the common case, not the tail

Measured over all 401 corpus effects, per curve slot that anything references:

| references to one curve slot | slots | share |
|---|---|---|
| 1 (safe to edit in place) | 994 | 29.2% |
| 2–3 | 1483 | 43.6% |
| 4–7 | 699 | 20.6% |
| 8–15 | 191 | 5.6% |
| 16–30 | 34 | 1.0% |

**70.8% of curve slots are shared**, so `EffectCurvePainter`'s edit-in-place restyles
something the author is not looking at *most of the time*. Worst case is `E009` curve 0,
ridden by **30 params**. The census is complete: every curve reference resolves through
`emitter_config.curves` or `.color_curves` (the callbacks included —
`WarpedGridCallback`'s `emitter+0x08` nibbles are lerp *parameters*, not table indices),
so **use site = (emitter, slot)** where slot is a param name or one of colour r/g/b.
Nothing references a curve effect-globally except the pacing curves, which are already
private (`_open_pacing_painter` mints its own `EffectCurve` from `time_scale[field]` and
saves it undoably — the existing, working proof of this amendment's model).

### Decision 1 — a curve is a private detail of its use site

Rejected: *a curve is a shared library asset*, edited knowingly on a global surface that
shows its fan-out first (#292 item 3 as filed). That model is defensible only while
curves are scarce, and decision 7 already removed the scarcity. Keeping it would also
have meant **reversing** decision 7 for colour rather than extending it, leaving two
ownership models in one codebase.

Intentional linkage ("these ten emitters fade together") is the real cost and is
accepted: it is not expressible, and editing one no longer moves the others. No link or
instance concept is introduced — that would reimport most of the rejected model's
complexity for a use case the corpus gives no evidence of (the ROM shares curves because
it has 15 slots, not because a designer asked for linked fades).

### Decision 2 — the de-share is EAGER, at load

`EffectData.load` explodes the 15-slot table into **one private curve per use site**,
repointing each emitter field at its own new index. Rejected: copy-on-write at first
edit (decision 7's mechanism, generalized), which preserves untouched data verbatim but
leaves the model in two states and lets any future write path forget to fork — which is
precisely the bug class this amendment exists to end. Eager makes privacy structural:
after load, no two use sites share an index, so there is nothing to forget.

**The array grows; the read path does not change.** Because each use site gets its own
*index* rather than its own accessor, all **29 `get_curve()` call sites across 10 source
files** (plus 14 more in 8 test files) are untouched. The change is two functions — an explode at load, a dedup at
compile.

Two conditions make eager safe, and both are part of the decision:

* **Provenance.** The exploded copy remembers its origin slot (`EffectCurve.index`
  already carries one). The compiler assigns indices by provenance first and value-dedup
  second, so an effect nobody edited compiles back to exactly its original 15 indices.
  Without this, round-trip fidelity would rest on the dedup being order-stable — a
  correctness property resting on an optimization.
* **Orphans are residue, not use sites.** Explode-then-dedup would otherwise silently
  drop every curve nothing references: **6.5 slots per effect on average, of which 71.9%
  are all-zero padding but 28.0% (726 slots corpus-wide) are distinct real shapes.** They
  are unreachable, so nothing renders them, but a byte-exact export would notice them
  missing. They never enter the authoring model; the compiler carries them back to their
  original slots.

Accepted cost, stated so it is not rediscovered as a bug: **every effect's `curves.json`
grows from 15 entries to ~22 (median use-site count) the first time it is saved, even
untouched.** Provenance keeps the *compiled* output identical, so this is diff noise on
an intermediate artifact, not a fidelity loss.

### Decision 3 — the picker COPIES a shape; it never references a curve

Under decision 1 there is no slot to point at, so `EffectCurvePicker`'s verb changes from
*reference* to *copy*: picking a thumbnail writes that shape into this use site's own
curve, and nothing links afterward. The widget, its grid and its thumbnails survive
unchanged. Rejected: deleting the picker (throws away a working affordance and leaves
every curve painted from scratch), and scoping privacy to colour only (keeps two
ownership models, the thing decision 1 exists to stop).

### Decision 4 — the picker deduplicates by SHAPE, and its tile count is the compile gauge

Explode produces one entry per use site — **median 22 per effect, max 67** — but those
carry only **median 8 distinct shapes, max 15**. A post-explode grid of 22 tiles showing
8 shapes is worse than what shipped, so the picker is fed the **distinct shape set**, not
the array. For an untouched effect that is a median of 8 tiles, which is the grid
`EffectCurvePicker` already lays out at `GRID_COLS = 4`.

This is the same dedup the compiler runs, which yields the gauge for free: **distinct
shapes = curves the compiler must emit = consumption against 15.** An untouched effect
shows ≤15 by construction. The moment authoring reaches 16 the picker shows 16, and the
overrun is visible before export rather than after. One number, two purposes, no second
mechanism to keep in sync.

**Shapes are generated, not browsed.** A global library was rejected on measurement:
2443 distinct shapes across the corpus with weak reuse (only 421 appear in more than one
effect), which is a browsing problem that would swamp this issue. The source is instead
the 16 parametric generators already written in `effect-editor/ui/curve_generators.lua`
— `linear`, `ease_in`, `ease_out`, `s_curve`, `exponential_in/out`, `sine_wave`,
`triangle_wave`, `sawtooth`, `pulse`, `constant`, plus `invert`, `reverse`, `scale`,
`shift`, `copy`. They are pure functions over a 160-element 0–255 array, which is exactly
`EffectCurve`'s domain and `CurvePaintModel`'s range, so they port directly.

### Decision 5 — a use site with no curve mints `constant(0)`, a true no-op

Adding a curve to a param that had none must change nothing until it is painted, and
that is exactly achievable rather than approximately: `ParticlePhysics.interpolate_range`
returns `_srange(min_start, max_start)` when the curve is null, and an **all-zero curve**
gives `lerpf(min_start, min_end, 0.0) = min_start` at every frame. Bit-identical. The
corroboration is in the orphan census above — **71.9% of unreferenced ROM curve slots are
all-zero**; FFT's dead padding *is* the identity curve.

**This corrects a factual error in this ADR.** Line 40 describes curve choice 0 as
`"none (linear start→end)"` and `EffectCurvePicker` draws `none` as a **linear glyph**.
The sim does no such ramp — no curve **holds the start values** and never reads the end
values. Both the sentence and the glyph are wrong and are fixed as part of this work.

### Decision 6 — more than 15 distinct shapes is a COMPILE ERROR on PSX export

Export refuses, names the count and itemises the overrun; the author decides what to
merge. Rejected: auto-consolidating near-identical shapes with a numeric tell. This repo
has form for "approximate with an honest tell" (decision 8 fits keyframes to a ROM
curve's 160 samples that way), but decision 8 approximates a curve the author is *looking
at*, whereas a compile-time merge silently changes an emitter they may not have opened in
weeks — and a merged colour curve is a **visual** regression that a log line cannot
convey. Also rejected as the primary answer, but retained as a legitimate fallback:
JSON-only export for effects the author does not care to ship on hardware.

Refusal is only fair because decision 4's gauge makes the limit watchable. The headroom
being spent is real:

| spare shape slots (15 − distinct in use) | effects | share |
|---|---|---|
| 0 — any new shape overruns | 29 | 7.3% |
| ≤2 — cannot fully author even one colour emitter | 78 | 19.5% |
| ≤5 | 157 | 39.3% |
| median spare | ~7 | ≈2 colour emitters |

A colour edit costs up to 3 shapes (r, g, b un-aliased), so the median effect affords
about two emitters before export stops fitting. This is the same arithmetic that
defeated an earlier "reserve 3 curve slots for colour" proposal — 3 is the per-emitter
ceiling, but N emitters want N×3 against 15 — except it now lives in the compiler, where
it belongs, and bites once at export instead of gating every edit.

### Corrections this forces elsewhere

* `EmitterChannel._apply_color_curve` hard-refuses curve indices outside `0..15`. That is
  a PSX packing rule enforced in the authoring layer; under decision 2 indices routinely
  exceed 15, so it must move to the compiler or it blocks legal edits.
* `ColourKeyframeSaver`'s copy-on-write forking becomes dead code — the explode at load
  has already done it — and must be removed rather than left to fork an already-private
  curve.

### Scope of this pass

**Built now:** the explode at load, private curves, the painter's commit routed through
`EffectEditSession` (undo), JSON save, the ported generators, and the live shape gauge.
Every one is verifiable without a byte-exact writer: privacy (painting emitter 3 leaves
every other emitter's samples untouched), no-op minting (`constant(0)` changes no pixel),
generator correctness (16 pure functions), and gauge arithmetic are all unit-testable.

**Deferred to its own pass:** the compiler — byte-exact BIN writer, value dedup,
provenance index restoration, decision 6's overrun error, and a round-trip guard across
all 401 effects. Known cost of splitting here: **provenance is exercised only by the
compiler, so it ships untested until that pass lands.** It is carried deliberately rather
than discovered.

### What the build changed (2026-08-20)

Six decisions survived contact; the mechanism moved in five places the design did not
name. Recorded here rather than in a new ADR, per local precedent.

1. **The painter stopped writing the bound curve.** It wrote in place and then emitted,
   which was fine while a curve edit was ephemeral. Routed through `EffectEditSession`,
   the choke point must see the PRE-edit samples to snapshot them for undo — and cannot
   if the painter has already overwritten them, so undo would have restored the post-edit
   value. `curve_changed` now carries the finished stroke and `CurveChannel` writes.

2. **The param nibble is a second copy of the same packing rule.** Decision 2's
   "corrections this forces elsewhere" named `_apply_color_curve`'s `0..15` refusal but
   not `_apply_curve`, which wrote the 4-bit `curve_indices_raw` nibble and derived the
   decoded index FROM it. Post-explode a private index does not fit a nibble, so the
   decoded `em.curves` dict becomes the authoring truth and the nibble is left untouched
   as ROM **provenance** — which is the same answer decision 2 already gives for colour,
   arrived at from the other side. The 2-bit homing pair capped the picker's OFFER at 3
   curves for the same reason and lost the cap for the same reason: its packing
   constraint is real, and it is the compiler's.

3. **The JSON saver repointed only `color_curves`.** Correct while colour was the only
   kind that forked; wrong the moment the explode repoints every use site. An exploded
   `curves.json` saved beside param addresses still naming ROM slots would reload every
   param curve as some other use site's shape. `patch_color_curves` becomes
   `patch_curve_addresses` and writes both dicts.

4. **A curve row could no longer find its relevance verdict.** The oracle keys on
   `field_ref.field`; a use-site address has no such field, so every colour and homing
   verdict silently went blank. The row names its `relevance_key` explicitly — the escape
   hatch the child-navigation link rows already used.

5. **60 references in the corpus do not resolve** — all in `E509`/`E510`, whose 7
   emitters apiece point into a `curves.json` with ZERO entries. They read as "no curve"
   today because `get_curve` range-checks; an exploded array that happens to be LONGER
   would have let a stale index start resolving to another use site's private curve. The
   explode makes them an explicit `-1`.

One honest limit the gauge carries: **residue occupies ROM slots too.** An effect whose
15 slots are mostly unreferenced padding has less byte-exact headroom than
`15 − distinct-in-use` suggests. Spending a residue slot costs byte-exactness, not
correctness, and the call is the compiler's — decision 6's own spare-slot table counts
distinct-in-use, and the gauge follows it.

## Amendment (grilled + built, 2026-08-20): the colour surface MOVES to the player column, on the particle's LIFE axis, with two entry points

The author's ask, verbatim:

> I get the sense that the whole keyframes + color ribbon should move to the player
> section. And the color picker should only appear when a keyframe is selected. So you go
> in here and you say ok — at each of these frames — what do I want the color to be — are
> you following? It would free up a lot of vertical space on the left side, and the
> conditional color picker appearance would save a lot of space as well.

Measured on E317, an emitter target, before the move:

| thing | size | note |
|---|---|---|
| `ColourBoxPicker` | **298 x 439** | **always visible** — the fold defaulted expanded |
| `ColourKeyframeTrack` (+ hosted ribbon) | 260 x 38 | |
| "Particle · over-life" section body | 668 x **610** | of which **477 (78%) is picker + track** |
| whole inspector `content_height()` | **2108** | in a 268px row |

So the picker alone was 21% of the entire inspector scroll, spent on every colour-enabled
emitter permanently. The section goes 610 → ~133; what stays is the three
`Color (R/G/B) · curve` rows and Homing blend.

### The complication the ask did not know about, and the measurement that resolved it

**The player column already drew a ribbon**, on a different axis: the player's window was
`get_animation_display_length` (so a position along the bar mapped to a film-strip row),
the inspector's was `life_n` (the particle's own lifetime). "Move the ribbon there" was
really "make *that* ribbon the editable one", which forces a choice of axis.

Re-measured over all 401 corpus effects, 2622 colour-enabled emitters:

| | emitters | share |
|---|---|---|
| `life_n == animation display length` | 1412 | 53.9% |
| **`life_n != animation display length`** | **1204** | **45.9%** |
| window unresolvable (no FRAME opcode) | 6 | 0.2% |

**The flat 45.9% is not the finding; the split underneath it is.**

| lifetime kind | emitters | agree | disagree |
|---|---|---|---|
| **animation-driven** (`Life = −1`) | 1370 | **1370 (100%)** | 0 |
| **authored lifetime** | 1246 | 42 (3.4%) | **1204 (96.6%)** |

They are identical BY CONSTRUCTION for animation-driven emitters — `life_n` is *defined*
as the animation's display length for exactly those — and they essentially never agree for
authored-lifetime ones. And the divergence is not off-by-one noise: **698 emitters (26.6%
of all colour-enabled ones) differ by more than 8 frames.** A wrong axis does not nudge a
keyframe, it relocates it.

That reframing is what let the author answer, and their answer was a model rather than a
pick:

> every entry on the opcode level axis has a map on the frame level axis — right? So the
> frame level one is a superset. So maybe you can pick a colour keyframe in the frameset
> panel and then that will add a keyframe onto the frame level axis. But then you could
> also do a non-frameset-level one directly on the frame level axis. But either way it's
> 1 ribbon at the frame level with 2 entry points.

Which settles the axis: if the strip PROJECTS onto the ribbon rather than sharing its
ruler, the ribbon's axis is free to be the honest one. **The superset claim was then
measured, and it holds for 84% and breaks in one nameable way** (`SequenceLifeMap`, and
`ParticleAnimator.gd:105`-`:141` is the ground truth — the animation LOOPS over life unless
a `duration = 0` terminal frame parks it):

| lifetime shape | emitters | share | does every opcode land on a life frame? |
|---|---|---|---|
| animation-driven | 1370 | 52.3% | yes, exact 1:1 — life IS the animation |
| authored, exactly one pass | 41 | 1.6% | yes, exact 1:1 |
| parks on a terminal frame for the tail | 769 | 29.3% | yes, once — the last opcode owns a long tail (median 9 frames held, max 110) |
| animation LOOPS over life | 112 | 4.3% | yes, but many times (median 6 repeats, max 26) |
| **the particle DIES mid-animation** | **324** | **12.4%** | **NO** — the tail opcodes never play (median 9 frames of animation never seen, p90 41, max 128) |
| no animation | 6 | 0.2% | — |

### Decision 1 — ONE ribbon, on the particle's LIFE axis, in the player column

`EmitterLifeWindow` is the single derivation of that window, extracted from
`EffectScoreModel`'s inline copy. Two copies would decide the same emitter's axis twice and
the disagreement would be invisible — both windows are plausible integers that draw
plausible bars. Guarded against the rule as written, over 61 real emitters
(`EmitterLifeWindowTest`).

What this COSTS is the strip's 1:1 alignment, and it is paid deliberately: for 1204
emitters a cell no longer sits under its own colour. The strip stopped being a ruler and
became an entry point, which is the next decision.

### Decision 2 — the film strip is the SECOND entry point, and it PROJECTS

`SequenceLifeMap` maps a trace cell to the life frame its dwell begins at.

* It projects the **trace**, not the opcodes. `SequenceTimeline.trace` has already walked
  them and carries `tick_start` + `is_terminal` per cell, so the projection cannot disagree
  with the strip about where a cell begins. A second walk would be a fourth copy of the
  `maxi(1, (d + 1) >> 1)` halving the corpus has already caught being wrong once.
* **A looped opcode resolves to its FIRST occurrence** (author's decision). One click, one
  keyframe, at a position that does not depend on where the player happens to be parked.
  The other repeats stay reachable through the ribbon — which is what a second entry point
  is *for*.
* **An unreachable cell answers -1, never a clamp.** A clamp would pile all 324 emitters'
  dead cells onto their last live frame and look like a working feature. Those cells are
  **dimmed with a tooltip naming the reason**, which is strictly more than the strip knew
  before: "this particle dies before reaching this opcode".
* The gesture is **right-click**, not click. A left click PARKS, and an author parks
  constantly while browsing; folding "add a keyframe" onto it would mint an undo entry
  every time they looked at a frame. Right-click-means-edit-this-cell is also the track's
  own idiom one row up (right-click a handle removes it).
* It is **select-or-add**, never add-and-overwrite: two handles stacked at one age cannot
  be told apart.

### Decision 3 — the picker is a THIRD STACKED PANEL, and it APPEARS ON A SELECTION

This **amends the 2026-08-13 editing-UX amendment's decision 1** (the inline
always-expanded fold), it does not fix a bug in it. The fold is gone.

`_canvas_chrome_h` and `_canvas_floor_w` both SKIP INVISIBLE CHILDREN, so a picker inside
the player panel that hid itself would swing the panel's measured chrome by 439px and
re-size the canvas square on every keyframe click — ADR-0102/0103's reserved-slot lesson at
eleven times the amplitude. **So it is not in that panel at all.** As a sibling laid out
explicitly by `_relayout` it is invisible to that measurement, and the panel's title names
the frame being authored — "Colour · frame 8 of 17".

**It is conditional on a real keyframe being selected**, which is the author's ask verbatim.

> **THE FIRST BUILD GOT THIS WRONG AND SHIPPED IT.** The author had been offered a
> genuinely-collapsing two-state height against a constant one and chose the constant, on
> the strength of the chrome-swing argument above — so the panel was built always-present,
> with a dimmed "pick a frame" plate. **But that argument does not survive the placement
> that answered it.** The chrome swing is a property of living INSIDE the player panel; a
> sibling panel can appear and disappear all day and the square never hears about it. The
> premise the decision rested on had been dissolved by the fix for the same problem, and
> nobody noticed until the cost showed up.
>
> The cost was the ADR-0102 frameset block, and it is the whole of it: at a 1069px body the
> row is 799 and the column's slack under the player is 327, so a permanent 439px picker
> left `focus_stack_height` **16px** — under its 64px collapse floor. The block a film-strip
> click retargets **never appeared at all**. Reported as *"when I click on a thumbnail I
> don't see the frameset controls now"*, and isolated by setting `picker_panel_h` to 0,
> which brought the block back at 358px.
>
> | | frameset block | picker | canvas square |
> |---|---|---|---|
> | no selection | **visible, 358px** | hidden | 260 x 280 |
> | keyframe selected | yields | visible | **260 x 280 — unmoved** |
>
> The square being unmoved across that transition is the invariant the sibling placement
> exists for, and it is asserted rather than argued (`EffectStudioColourColumnTest`).
>
> **The WIDTH bid stays unconditional** while the column is up, and that asymmetry is not
> an oversight: `column_width` feeds the square, so bidding on the selection would make the
> box a function of whether a keyframe happens to be selected — the exact complaint ADR-0100
> dec. 2's amendment made the box a constant to answer. Height is safe to make conditional
> here; width is not.

**The residue, stated:** while a keyframe IS selected the frameset block still yields — 327px
of slack cannot hold a 439px picker and a 120px block together. Deselecting brings it back.
The alternative was the block never appearing, which is what shipped for one commit.

**THE PRICE IS STATED, NOT HIDDEN.** Godot's `ColorPicker` reports a hard **298 x 439**
combined minimum and returns the same 298 after being assigned 200 — measured; it is the
theme's, and `sliders_visible = false` + `hex_visible = false` takes 175px off the HEIGHT
and not one pixel off the width. Two consequences:

1. **The column is 314 wide where the player alone wanted 276.** A Container cannot shrink
   below its minimum, so a narrower column would not narrow the picker, it would make the
   picker overhang onto the inspector — the failure ADR-0100 dec. 2's clamp exists to make
   unrepresentable. It is a bid, so the leftover clamp still wins on a narrow body.
2. **The ADR-0102 frameset block yields to the picker while a keyframe is selected.**
   `focus_stack_height` has always returned 0 when the column's slack runs out, which is
   why the block never appeared on the developer dashboard's 268px row — but a PERMANENT
   picker turned "runs out on a short row" into "runs out always", which is a new failure
   mode and not a moved threshold. See decision 3's correction. `picker_panel_h` is an
   ADR-0068 static var so the number is movable without a rebuild.

The picker is bid and shown for the SEQUENCE occupant only. A `frame` target parks the
frameset canvas in that column and there is no particle, no life axis and nothing to
colour.

### Decision 4 — the freehand curve painter does NOT move, and the R/G/B rows stay with it

The move looked like it created a three-way collision — keyframe track + picker, the
per-channel painter, and the ribbon. It did not, and the reason is worth recording because
the handoff that raised it had it wrong: **the painter is not a colour tool.**
`_open_param_curve(curve_index, param_name, used_n)` opens from ANY emitter param's
sparkline — position, spread, velocity, inertia, weight, drag, lifetime, homing, R/G/B —
and there is a second mode entirely (`_open_pacing_painter`, the ADR-0093 time-scale
curves, which are not in the curve table at all). Colour is 3 clients of ~18 plus pacing.

So it keeps its door, and its door is the three `Color (R/G/B) · curve` rows — which is why
they stay in the inspector rather than following the ribbon. The row carries the painter's
sparkline AND the `curve_pick` shape cell; moving it would have meant building a second
door in the player column for a panel that was never about colour. The ~133px it costs is
what buys "leave the painter alone" as a genuine no-op.

Rejected: a right-click-the-ribbon door for the painter. The ribbon is one bar of
*resolved, muxed* colour — there is no per-channel thing on it to click, so it would have
needed a "which channel did you mean?" sub-menu, an ambiguity the sparkline row does not
have.

### What the build changed elsewhere

* **The `inspector BUILDS / page FILLS` split survived the move** — only the column
  changed. The signals are now connected ONCE at build rather than re-checked per bind,
  because the widgets live for the page's lifetime instead of being rebuilt on every
  reproject; every `is_connected` guard in the old wiring existed for that rebuild.
* **`_sequence_colour_emitter` and `_sequence_colour_window` are STAMPED**, never
  re-derived, for the same reason `_sequence_bound` is (ADR-0100 dec. 1's amendment): every
  wrong answer here is also a real emitter with real curves.
* **The band is still a FIXED 260 wide** (the 2026-08-19 amendment). The first build
  anchored the track full-rect in its slot, which handed the band the COLUMN's width — 276
  with the player alone in it, 436 once the frameset block bids — re-introducing the exact
  "the same emitter reads differently at two window sizes" fault one column to the right of
  where it was fixed. **Every number in the test suite was still correct; only a screenshot
  caught it.** It is now asserted (`EffectStudioColourColumnTest`).
* **`ColourAuthorEditorTest` is retired.** Its subject — the inspector-built inline picker
  in a collapsible fold — was deleted by this amendment. What survives from it (the track
  HOSTS the ribbon, so the coloured band is the click target) moves into
  `EffectStudioColourColumnTest`.
* **`EffectStudioSequenceViewportTest`'s axis assertion was superseded and did not fail.**
  It read `used_n() == total_ticks(trace)` and it passed after the axis changed, because
  E019 sequence 0's emitter is animation-driven and for those two the windows are equal by
  construction. The test agreed with both answers and could not tell them apart. It is now
  pinned to `EmitterLifeWindow`, with the equality to the strip asserted as a CONSEQUENCE
  of that emitter's kind rather than as the rule.

### Still open

**ADR-0103 dec. 6's off-by-one is filed, not fixed** — `ColourRibbon.frame_colors` samples
at `f`; the render pairs baked frame *k* with sample *k+1*, so the strip and the ribbon
legitimately disagree by one cell. It was predicted to become more visible the moment the
ribbon was the editable surface. It has not been touched here, and now that the strip
PROJECTS onto the ribbon rather than sharing its ruler, the projection is a second place
that off-by-one could land.

### Guards

`EffectStudioColourColumnTest` 34 · `EmitterLifeWindowTest` 21 · `SequenceLifeMapTest` 45 ·
`EffectStudioColourRibbonWiringTest` 23 · `EffectStudioColourKeyframeAcceptanceTest` 21 ·
`EffectStudioColourRibbonAcceptanceTest` 12 · `EffectStudioSpriteMuxAcceptanceTest` 4 ·
`ColourKeyframeTrackTest` 54.

---

## CORRECTION (2026-08-20, same day): the life window was reading two fields nothing reads

**This corrects the amendment directly above it, including one of its headline tables.** It
is written as a correction rather than an edit because three commit messages
(`b2b2e609a`, `8a6d4316a`, `dee6c4bad`) quote the number it moves, and because the way the
number was wrong is the reusable lesson.

### What prompted it

The author, using the built surface:

> Showing all 160 doesn't make sense it should only go to the MAX(life, lifetime_start,
> lifetime_end) are you following.

and immediately after:

> or sorry - max (SEQ derived life (-1))

Their instinct — *the window is too big* — was right. Their specific rule would have been
wrong, in a way worth writing down, and chasing it found that the SHIPPED rule was wrong
too, in the same direction.

### The primary source

`ActiveEmitter._create_particle` draws a particle's lifetime through
`ParticlePhysics.interpolate_range(min_start, max_start, min_end, max_end, curve, …)`.
That function's first line is:

```gdscript
if curve == null:
    return _srange(min_start, max_start)
```

**With no lifetime curve the END PAIR is never sampled.** It is inert bytes on the emitter.

The ROM branches identically. `emitter_control_routine` (`0x801A634C`) reads the packed
curve nibble for each parameter and, when it is 0 (index −1), takes the `_start` pair
straight — only the other branch calls `lerp_u8(start, end, factor)`
(`research/working_documents/CURVE_ANALYSIS.md`, the radial-velocity block, which is the
unambiguous instance of the pattern). So this is the format's design, not an artifact of the
reimplementation.

**9 of 3227 corpus emitters carry a lifetime curve** (8 of the 2622 colour-enabled ones).
For the other 99.7%, `lifetime_min_end` / `lifetime_max_end` do nothing at all.

### What that makes wrong

The rule `EmitterLifeWindow` shipped with was
`min(all four) >= 0 ? max(all four) : the animation's display length`. Both halves consult
the end pair. Measured by `tools/census_life_window.gd` over all 401 effects, 2622
colour-enabled emitters:

| | emitters | share | median | p90 | max |
|---|---|---|---|---|---|
| **window was TOO LARGE** (dead zone drawn as live) | **309** | 11.8% | 6 | 12 | **32** |
| window was too small (live ages hidden) | 4 | 0.2% | 9 | 9 | 9 |
| unchanged | 2309 | 88.1% | — | — | — |

The 309 are the serious ones: a bar claiming ages the renderer never samples, on the
surface an author now places keyframes with. That is the exact fault
`ColourKeyframeTrack.in_window` exists to prevent one level up — the dead zone had simply
been drawn into the window instead of past it.

The 2309 agreed **by luck**. The start pair is all-or-nothing in this corpus (1363 colour
emitters have both start fields at −1, 1258 have both real, exactly **1** is split), so
"is any of the four −1" usually answers the same question as "is the START pair −1".

### The corrected rule

* **no lifetime curve** → `max(min_start, max_start)`. `max` of the *pair*, not `max_start`
  alone: `_srange` is `randf_range`, which honours whichever endpoint is larger, and
  reversed ranges like `(36, 32)` are common in the corpus.
* **a lifetime curve** → `max` of all four. `min_val` and `max_val` are each a lerp from
  their own start to their own end, so over t ∈ [0,1] the largest reachable draw is the
  largest of the four corners. **This is the old rule, and for those 9 emitters it was
  right.**
* **a negative bound** → animation-driven, window = `get_animation_display_length`.

### The table above that this corrects

The amendment's second table reads:

| lifetime kind | emitters | agree | disagree |
|---|---|---|---|
| **animation-driven** (`Life = −1`) | 1370 | **1370 (100%)** | 0 |
| **authored lifetime** | 1246 | 42 (3.4%) | **1204 (96.6%)** |

The counts are now **1363 animation-driven / 1259 authored**. That is a 7-emitter move and
it is the least of it. **The argument the table was making was circular.** Animation-driven
emitters agree with the animation's display length because `EmitterLifeWindow` *defines*
that class as the animation's display length. A rule cannot be evidence for itself. The
row was true and it was never support for the life axis.

It was also nearly a much worse error. 1361 of those "animation-driven" emitters carry
REAL values in their end pair, which reads exactly like a rule discarding authored data —
and that reading is what the correction started from. It is wrong: for 1348 of them the
−1 sits in the **start** pair, the only pair read, so they genuinely are animation-driven
and the real-looking numbers beside them are inert. **The classification was right; the
reason given for it was not.**

**Decision 1 stands.** The axis is the particle's life because the axis an author edits has
to be the one the renderer reads — that argument never depended on the table, and the
correction strengthens it: the window is now actually the thing the renderer reads.

### Why the author's own rule is not adopted

`max(the real fields, SEQ-derived life where a field is −1)` reads the end pair, so it
would put a lifetime on 1348 emitters that the spawner never draws. It also only ever
GROWS the window (median +6, max +19 across the corpus), which is the opposite of the "it
should only go to MAX(…)" the ask opens with. The corrected rule shrinks 309 and grows 4 —
the direction asked for, by the fields that are actually live.

**Still open from the same message:** *"showing all 160 doesn't make sense"* is not
explained by this. Only 6 emitters resolve to −1 and fall back to the 160-sample curve. The
likelier candidates remain the page-wide `Fit W: win/all` toggle (`all` shows the untrimmed
160 on every curve surface, this ribbon included) and the inspector's R/G/B sparklines and
freehand painter, which are 160-sample surfaces **by design**. Needs the author to say
which surface before anything is changed.

### The guard that had to be replaced, not adjusted

`EmitterLifeWindowTest`'s corpus-parity test compared this module against a hand
transcription of the copy `EffectScoreModel` used to hold inline. **That copy is gone** —
the model calls this module — so the transcription had become a duplicate of the thing
under test, agreeing with whatever the module said, *including while the module was wrong
for 313 emitters*. **A guard that agrees with both answers is not a guard**, which is the
second time this ADR has had to say that (see `EffectStudioSequenceViewportTest`'s axis
assertion, above).

It now drives `ParticlePhysics.interpolate_range` itself over every colour-enabled emitter
on disk — sweeping all 160 frames for the curved ones, one frame for the rest (the function
ignores the frame without a curve) — and asserts both directions:

* no lifetime the spawner can draw escapes the window (the upper-bound claim);
* every window is *reachable* — a window nothing draws up to is dead zone by another name,
  which is precisely what the old rule produced.

Four unit assertions changed sides and should have. `EffectStudioSequenceViewportTest`'s
band assertion now states `ColourRibbon`'s 2-band floor explicitly: **154 corpus colour
emitters have a 1-frame particle life**, and the old assertion held only by never meeting
one.

Verified headful on E342 emitter 0 — lifetime `(20, 19, 30, 52)`, no curve: the ribbon
draws 20 bands and the slot says "20 frames", where the old rule said 52.

### Also fixed the same day: the picker had no way to close

Decision 3 made the picker appear on a selection. Nothing cleared the selection.
`_colour_selected_frame` was set in two places and cleared in one (`_delete_colour_keyframe`,
and only when the deleted frame *was* the selected one); `_deselect()` did not touch it, so
Esc tore down the whole screen and left the picker up on a target that no longer existed.

Three ways out now, one implementation (`_clear_colour_selection`), because a picker that
half-closes — state cleared, handle still lit in the lane — is the same bug smaller:

1. **a second click on the selected handle**, carried by `keyframe_selected(-1)`. The only
   gesture this control had spare: clicking empty space already ADDS a keyframe, so "click
   off to deselect" was never available here. Only the *selected* handle toggles — a toggle
   on any handle would make moving between keyframes a two-click gesture.
2. **Esc, as a third stage.** The contract was two-stage (a focused value cell eats the
   first Esc, the next deselects); the keyframe is a sub-selection *inside* the target and
   is what the picker is bound to, so it sits between them. Innermost first, which is what
   Esc means everywhere else in the studio.
3. **deselecting the target**, which now drops it unconditionally.

Guards: `ColourKeyframeTrackTest` 54, `EffectStudioColourColumnTest` 34 (a `picker_closes`
arm, placed BEFORE that suite's slack-dependent skip — none of the three ways out depend on
the column having room for the panel, and after the skip they would go unmeasured on
exactly the short windows the harness usually runs at).

### Still open, from the author's same message

Two items are **placement questions, not defects**, and are not decided here:

* *"I should be entering the keyframe data ON that frameset control"* — a placement
  reversal. It would move colour authoring onto the ADR-0102 frameset focus block and
  dissolve the picker-vs-block slack fight that `dee6c4bad` patches (327px of column slack,
  a 439px picker, a 120px block). Note that decision 2's strip entry point already exists,
  via right-click, and the author appears not to have found it — which is itself a finding.
* *"it looks like the thumbnails should align to the color ribbon but they don't"* — the
  known, deliberate cost of decision 1, now felt rather than predicted. The complaint is
  about visual adjacency implying an alignment that does not exist. **Not to be answered by
  reverting to the animation axis**, which was measured, argued and chosen.

---

## Amendment (built, 2026-08-20): the ribbon runs VERTICAL, down the side of the thumbnails

**This answers the second open question above, and the author answered it with a shape
neither of the three options offered.** Asked how the divergence should be shown — draw the
projection, break the adjacency, or add a second muted axis — they replied:

> the ribbon should run vertical down the side of the thumbnails. yeah, it won't be linear
> with frames but that's ok. it shows how colors lerp between thumbnails

and, when asked how a thumbnail that holds several life frames should be drawn:

> are you suggesting we go down the side, but each column within each row, Is a color. so if
> i held a keyframe for 3 frames i would get 3 columns in the row?

Yes — and discrete columns are better than the gradient that was proposed, because each
column stays an individually clickable target.

### Decision 1 — ONE ROW PER THUMBNAIL, EQUAL HEIGHT; ONE COLUMN PER LIFE FRAME INSIDE IT

The misalignment is **unrepresentable now, not explained**. Row *i* of the ribbon IS
thumbnail *i*, both laid out from one projection, so the two cannot disagree. Everything the
three rejected options were trying to do — make the divergence visible, break a false
adjacency, draw two clocks — is dissolved by removing the disagreement instead of
annotating it.

**The axis is deliberately not linear in time**, and that is the point rather than a
concession. The horizontal ribbon was linear (`width / n` per frame) and that is *precisely*
why it could not line up with a strip laid out by opcode. Time moves horizontally now,
inside a row: a 6-frame hold is six columns, a 1-frame cell is one.

Measured over 2615 colour emitters (`tools/census_life_column.gd`): **81.8% of rows are a
single full-width column.** That is why the author's *"i think its one color per frame set
right?"* felt right — and the other 18.2% are exactly where it breaks, now drawn rather than
averaged away.

**What it costs, stated:** two rows are the same height whether the picture held for 1 frame
or 128, so this column is **not a clock** and must not be read as one.
`ColourKeyframeTrack.band_width`'s "a fixed width so `width / n` is a pure function of the
life window and two emitters are comparable" (the 2026-08-19 amendment) **does not carry
over** — that was an argument about a linear axis, and it dissolves with the axis.

Every life frame stays individually addressable: `SequenceLifeMap.life_rows` partitions
`[0, life_n)`, so each age is exactly one (row, column) cell — clickable, keyframe-able,
deletable. A 3-frame hold is three targets, not one.

### Decision 2 — the strip is the particle's LIFE, not the opcode list

One thumbnail per life row. This is what *lets* decision 1 be true, and it changes what the
strip means. `ParticleAnimator.tick` is the ground truth and it has three shapes:

| how the animation covers the life | emitters | share | what the column does |
|---|---|---|---|
| one clean pass | 1410 | 53.9% | one row per cell |
| PARKS on a `duration = 0` terminal frame | 726 | 27.8% | ONE row, many columns — the tail is inside it |
| LOOPS (`anim_time = 0` at the end) | 105 | 4.0% | one row PER PASS |
| particle DIES mid-animation | 374 | 14.3% | the tail cells get no row |

Two of these were previously inexpressible. `life_frames` has one number per cell, so it
could not say that a parked terminal owns the rest of the life; and repeats were resolved to
their first occurrence by decision (2026-08-20), which left **every later pass of a looped
animation unauthorable**. Both are addressable now.

A ZERO-DWELL cell (LOOP, SET_OFFSET) holds no age and gets no row. It keeps its trace cell
and the inspector's opcode rows still show it — it is simply not part of any life frame, and
a thumbnail beside a colour it never displays would be a lie in the one place this surface
exists to tell the truth.

**The column is SHORTER than the strip it replaces** — median 9 rows against 12 trace cells,
max 75 against 98 — which was the open worry when the shape was chosen and is now measured.
Row count is bounded by `life_n` (every row consumes at least one life frame), so a 26-pass
loop cannot instantiate 26 × 36 thumbnails.

### Decision 3 — cells the particle never reaches are KEPT and MARKED

Author's call, verbatim: *"show both, marked."* The 374 emitters whose particles die
mid-animation have tail opcodes with no life row. Dropping them would misrepresent the
ANIMATION in order to say something about the particle, so they follow the life rows,
dimmed, with no ribbon beside them — which is what "no colour to author here" looks like
when the ribbon is a column.

**A correction to what was put in front of the author when they made that call.** They were
told 31.5% of emitters have colour frames with no thumbnail under them. That number came
from a throwaway model that walked opcodes once and ignored both parking and looping; the
life column covers every age by construction and **there is no uncovered tail**. The only
real asymmetry is the 14.3% above. The decision stands on the half that was real.

### Decision 4 — the panel's body is a ROW, and two measurements had to grow a walk

The ribbon and the strip stacked under the player ate 108px of a 268px panel, so the canvas
— whose box is a CONSTANT 260 square (ADR-0100 dec. 2) — was starved to **260×84** at the
developer's window. They moved to the right of the square, into space that was already dead:
the square is centred, so a 558px panel had ~149px unused on each side. After:
`chrome_h` 204 → 88, canvas **260×84 → 260×280**.

That forced `_canvas_chrome_h` and `_canvas_floor_w` to stop looking at
`canvas.get_parent()` and stopping. The canvas's parent is an HBox now whose sibling costs
WIDTH, while the title and transport that cost HEIGHT are one level up — a single-level walk
reported the life column's whole height as chrome and starved the canvas to nothing. Both
walk to the panel now, applying each container's own axis: a VBox's siblings add height, an
HBox's add width. `EffectStudioEmitterColumnTest`'s title-width assertion carried the
identical single-level bug.

The slot still declares itself once at build for the reason it always did — both
measurements skip invisible children — but it declares a **WIDTH** now.

### Decision 6 (added same day) — THE STRIP WRAPS, and the ribbon wraps with it

> I don't want to have to scroll to see all the thumb nails. I just want them to form
> another row on the right.

**This reverses a reasoned assertion, and the REASONING is what was wrong.** The
supersedes-block below argued *"a column beside a ribbon cannot wrap: a second column of
thumbnails would have no ribbon next to it."* The author dissolved it in one sentence — **the
ribbon wraps too.** Each column of thumbnails gets its own ribbon strip beside it, so the
pairing survives per column and the alignment claim was never at stake. That argument was not
a fact about wrapping; it was a fact about a design that happened to have exactly one ribbon
in it, written down as a constraint on layouts. **It is the same error the strip's previous
wrap rule made** — that one asserted the strip WAS an `HFlowContainer`, which was equally a
property of the then-current layout. Twice now this surface has frozen a layout's incidental
shape into a rule; both are recorded in `EffectStudioSequenceViewportTest` rather than
deleted.

**WRAPPING DOES NOT REMOVE SCROLLING, and the author priced that before choosing.** Rows per
emitter are median 9, p90 22, p99 35, max 75 (`tools/census_life_column.gd`); a column shows
about a dozen. Offered a cap at 2, a cap at 3, no cap at all, and smaller thumbnails, they
chose **three columns then scroll** — the 99th percentile covered, the last 1% scrolls. They
were also shown the uncapped form, which never scrolls at any length, and rejected it for
what it costs: the player column's width, and so the inspector's right edge, would move on
every click. That is ADR-0100 dec. 2's *"the animation box is changing in size all the time"*
complaint one level out. **So the extra columns are bid CONSTANTLY, whatever the open emitter
shows.**

The split is *use as many columns as it takes to avoid scrolling, up to the limit, then
BALANCE them* — 22 rows is two columns of 11, not one of 12 beside one of 10. Both avoid the
scroll; only one looks like it meant to.

**The slot's declared minimum stays ONE column.** Raising it to three would raise the player
panel's hard floor by ~128px, and a Container cannot shrink below its minimum, so a narrow
row would push the panel onto the inspector — the failure ADR-0100 dec. 2's clamp exists to
make unrepresentable. The extra columns are a BID in `_relayout`, taken only if the leftover
clamp leaves room. Three columns cost **198px, not 3×70**: the scrollbar is paid once for the
whole scroller, and all three pairs live in that one `ScrollContainer`, which is what keeps
their offsets in step — there is only one offset to slide.

**`ColourLifeColumn` needed no change at all.** It has been frame-addressed rather than
index-addressed since dec. 5, so a slice is already a legal configuration of it and a column
draws no mark for an age outside its own — which is what makes broadcasting the selection to
every column safe.

**Two bugs no picture could have shown.** Interleaving the remove and the add dropped cells:
a thumbnail moving from column 2 to column 0 was still parented to column 2 when column 0
asked for it, `add_child` refused, and that cell vanished — built, alive, holding its four
canvas subscriptions, just not on screen. Nothing looked broken; the sequence merely had
fewer frames than it has. Found by a new "every one of them is in a column" count (5 parented
of 8 built). And an early `return` in the picker's degraded-panel arm skipped every remaining
assertion in the suite while reporting `0 failed` — the completion flags caught that, and
nothing else would have. **That is the fifth guard-that-could-not-fail on this ADR.**

### Decision 7 (added same day) — COLOUR ON/OFF is in the player's transport, and it MINTS

> I want to be able to toggle color on and off near where all the "color" stuff is - which
> is that panel.

The control already existed — `EmitterParamRows`' "Colour curves" enum row on
`emitter_flags_lo` bit 6, buried in the inspector's flag section. This is a relocation.

**Not into the picker panel the author pointed at**, for a reason the ask cannot see from
outside: that panel only exists while an age is SELECTED, and there is no age to select while
colour is off — a toggle living there could turn colour off and never turn it back on. The
transport row is the nearest thing always up whenever the player column is.

**It is also the answer to "why is there no column?"** With colour off the column is simply
absent with nothing explaining why, which is what sent the author hunting for a ⬥ button that
was not there to find. Reading "Colour: off" in the player's own transport closes that loop,
so this is a label as much as a control.

**TURNING COLOUR ON MUST PRODUCE A COLUMN.** Of the 605 corpus emitters with colour off, 591
have indices that already resolve and light up on the flip alone; **14 point at nothing**, and
`SequenceCellColour._curves` is deliberately all-or-nothing. On those the flag would flip, no
column would appear, and the toggle would read as broken. Offered *"refuse on those 14 and say
why"*, the author chose to MINT, so the toggle means the same thing on all 605. The mint is
flat at the identity — the render is `ALBEDO = S ⊙ curve` and a disabled emitter modulates by
white, so 1.0 is exactly the untinted picture and nothing changes until authored. All 14 are
in E509 and E510, the two effects whose `curves.json` has zero entries — the pair
`CurveExplode._repoint` already records as the corpus's only unresolvable references.

**A latent bug found by building on it.** `EffectEditSession.apply_compound` could not carry a
`curve_assign` member: it read `res["before_raw"]` unconditionally, and a snapshot-style
member has none. In a coroutine that throw unwinds SILENTLY — the flag applied, the first mint
applied, the second and third never dispatched, and no undo entry was pushed at all. Half the
gesture landed and nothing said so. `apply_edit` had always known this; compound never
learned. It captures the same structural stash now, and a member with no `before_raw` is
treated as "not undoable" rather than as a crash.

**And a fix that turned out to be solving nothing, recorded so it is not re-proposed.** The
raw `emitters.json` for E509/E510 names slot 0 for r, g AND b, which would make
`mint_identity` hand the second and third channels the first one's curve. A
clear-the-address-first step was written and tested against that story — and the arm passed
identically without it, because `CurveExplode` normalises an unresolvable reference to -1 at
load. **The JSON's story was true of the disk and false of the data.**

### What this supersedes

* **Decision 3 of the amendment above (the picker as a third stacked panel) is unchanged**,
  but the slack fight it manages is much smaller: the ribbon and strip no longer bid for the
  column's height at all.
* ~~**The strip's WRAP is reversed.** … A column beside a ribbon cannot wrap: a second
  column of thumbnails would have no ribbon next to it.~~ **Reversed again, same day, by
  decision 6 above** — the ribbon wraps too, so this was never a fact about wrapping. The
  strip is not an `HFlowContainer` either: the wrap lives one level up, between (ribbon,
  thumbnails) PAIRS. The assertion is still on the geometry rather than the class.
* **`ColourKeyframeTrack` and its horizontal band are out of the player column.**
  `ColourRibbon` survives as a HEADLESS resolver — it owns the sprite mux, the `Fit W` trim
  and the `colors()` array, which is the shared resolve the particle renderer paints with,
  and a second sampler in the new widget is the drift ADR-0103 dec. 1 forbids.

### A guard that was reporting green while doing nothing

`EffectStudioColourKeyframeAcceptanceTest` printed **`[PASS] 2 passed, 0 failed`** after
aborting on its ninth line against a removed member. A GDScript coroutine that hits a
runtime error unwinds silently, and this suite — unlike its siblings — had no
did-it-reach-the-end flag. It has one now. This is the third time this ADR has recorded a
guard that could not fail; the other two were assertions that agreed with both answers.

The rewritten `EffectStudioColourColumnTest` avoids the same shape deliberately: its central
assertion is **not** "the counts match" (two lists of the same length can still be one row
out of step, which is exactly the failure this placement was chosen to prevent) but the
pixel *y* of every ribbon row against the thumbnail beside it.

### Guards

`ColourLifeColumnTest` 50 (including a 1242-cell round-trip proving `frame_at` and
`rect_of_frame` are inverses, and that a 0.17px column on a 128-frame hold is still
clickable) · `SequenceLifeMapTest` 148 · `EffectStudioColourColumnTest` 43 ·
`EffectStudioColourKeyframeAcceptanceTest` 22 · `EffectStudioColourRibbonAcceptanceTest` 13
· `EffectStudioSequenceViewportTest` 75 (5 failures pre-existing, frameset-occupant, stale
against `f9301b829`) · `EffectStudioEmitterColumnTest` 35 · and the wider studio sweep
unchanged.

### Still open

* **ADR-0103 dec. 6's off-by-one is now more visible, not less.** The thumbnail is tinted at
  `cut_start + t + 1` (the render's pairing) while `SequenceLifeMap` projects to
  `tick_start`, so **the colour a thumbnail is painted with is one life frame off from the
  ribbon row beside it**. That gap used to be a cell's width along a shared band; it is now
  a direct neighbour comparison, which is the strongest case yet for settling it. The ADR
  says the ribbon is the wrong one and filed the fix pending a ROM read.
* *"Showing all 160 doesn't make sense"* is still unexplained — see the correction block
  above. Only 6 emitters fall back to the 160-sample curve.
* *"I should be entering the keyframe data ON that frameset control"* is not answered by
  this. It may be largely dissolved — colour authoring now sits directly against the
  thumbnails — but that is for the author to say.

### Decision 5 (added same day) — SELECTING an age is not KEYING it; ⬥ is the second step

Using the column, the author:

> selecting frames is good but adding them by clicking them is not. there needs be a second
> step to lock it into being a keyframe instead of just a frame

The fault was worse than untidy. A click into an empty column called `studio_colour_add`,
so **browsing the colour of an age you were merely curious about permanently altered the
curve** and minted an undo entry. There was no way to look without writing. The strip's
right-click carried the same select-or-ADD rule and falls with it.

**The state this creates is one that could not previously exist: an age that is SELECTED and
is NOT a keyframe.** Everything else follows from making it representable — the column's
selection becomes frame-addressed rather than an index into the keyframe array (an index
cannot name an interpolated age), and the single "selected" mark splits into two orthogonal
ones: an OUTLINE for *selected*, a BAR for *is a real keyframe*.

**Offered four ways to spend the second step; the author chose the strictest.** The options
were: an explicit ⬥ button plus keying on a colour pick; the button only; the pick only; or
a double-click. They chose **the button only — nothing keys implicitly** — having been shown
the cost in as many words, that dragging the picker on an interpolated age then changes
nothing on screen. Recorded because it is a deliberate trade, not an oversight: `pick` now
returns without authoring unless the selected age is a real keyframe, and ⬥ reads the
picker's current `achieved()` colour when it commits, so nothing the author was dragging is
lost.

⬥ is one control carrying a state and an action — enabled and labelled "Set keyframe" on an
interpolated age, disabled and labelled "keyframe" on one that already is. A separate
indicator would be a second thing to keep in sync with the same fact. The picker's title
states the same thing in words, because the panel otherwise looks identical either way.

Two things fell out with the click-to-add rule, both worth losing: the
`_colour_selected_frame < 0 → author age 0` fallback (the one path that could write a
keyframe the author had never pointed at, left over from a permanently-open picker), and
`_clear_colour_selection`'s test for "is the selected frame a keyframe" — the same question
while only keyframes could be selected, and one that would have reported "nothing to clear"
with the picker plainly up, sending Esc straight through to tear down the screen.

**A bug the screenshot caught and the numbers could not.** The strip's right-click reaches
the page *without* going through the column, so the column never learned the selection: the
page state and the picker were both correct and only the ribbon showed nothing selected.
Every assertion passed. This is the same failure mode as the band-width regression recorded
above — *"every number in the test suite was still correct; only a screenshot caught it"* —
and the same answer: it is asserted now.

**And a fourth guard that agreed with both answers.**
`EffectStudioColourKeyframeAcceptanceTest` passed on the first run after this change
*without pressing ⬥ at all*, because its age is 60% into the window and already carried a
keyframe on that emitter. The round trip worked by coincidence and would have kept working
while the two-step gesture was entirely broken. It now seeks an age that is definitely not a
keyframe and drives the button explicitly.

### Amendment (build, 2026-08-21): the keyframe budget is PER REGION, so the dead zone cannot starve the live window

Reported as: *"when I turn color on the keyframes don't get added."*

The colour toggle was not at fault, and neither was the mint that the
2026-08-20 amendment added for the 14 emitters that point at nothing. Driven in
the running studio, every step of that chain measured correct: the flag flips,
the compound edit lands (flag plus up to three `curve_assign` members), the
per-emitter session is dropped and re-imports, the column appears with rows in
it, and the two-step ⬥ gesture adds a keyframe at every age it is offered. The
keyframes *were* being made. They were being spent where the author cannot see
them.

**One budget, two regions, and only one of them renders.**
`ColourKeyframeFit.import_from_curves` fitted with a single `MAX_KEYFRAMES` = 24
Douglas-Peucker budget spanning all 160 curve samples. The 2026-08-19 amendment
above established that the track's domain is `life_n` and that everything past
it is the dead zone — *"a keyframe past it edits samples the game never looks
at."* What that amendment fixed was the **drawing**: out-of-window handles are
no longer painted outside the control. What it left standing is that those
handles are still **bought**, out of a budget the live window shares with them.

A ROM colour curve typically deviates from its chord far more across its long
tail than across a short life, so DP spends the budget there. `_douglas_peucker`
compounds it: the stack is popped from the back, so it descends into the RIGHT
half of every split first and exhausts the tail before it ever returns to the
head. E001 emitter 0 — a 10-frame life, 24 keyframes fitted, 22 of them on ages
116-159, **one** inside the life. The author flips the toggle and gets a 22px
band with a single bar at the top of it.

Measured over the 605 corpus emitters with colour off
(`tools/census_colour_enable_keyframes.gd`): **291, or 48.1%, had one keyframe
or none inside the life.** That is the report, and it is not a minority case.

**Decision: `MAX_KEYFRAMES` is a per-region bound, not a shared pool.** The
polyline is fitted twice — `[0, life_n-1]` and `[life_n-1, 159]`, sharing the
boundary sample so there is no seam — each bounded by the same 24. That is what
the constant always meant: it exists so a genuinely curvy stretch cannot
degenerate to one keyframe per sample, and each region still honours it. A
shared budget was never the guarantee; it was the thing that let one region
starve the other.

**This is not the repair the 2026-08-19 amendment rejected, and the distinction
is the whole design.** That amendment rejected *re-fitting the import to
`[0, life_n)`*, because `compile_to_curves` writes all 160 samples back from the
keyframes, so a fit that stopped at `life_n` would flatten the tail's real bytes
to fix what was then a drawing bug. That objection is correct and still binds.
It is an objection to **truncating** the fit — not to bounding what each region
may spend. Nothing is dropped here. Measured over 2995 colour emitters
(`tools/census_colour_fit_window.gd`), the split matches the truncating fit
exactly where the picture comes from and the old fit exactly where it does not:

| max residual | global (was) | truncated (rejected) | split (built) |
|---|---|---|---|
| inside the life — *the only error that renders* | **0.7739** | 0.1329 | **0.1329** |
| …p90 | 0.0036 | 0.0019 | **0.0019** |
| in the dead zone — *what `apply()` rewrites* | 0.9725 | flattened | **0.9725** |

Result: emitters showing ≤1 keyframe inside the life fall from 291 (48.1%) to
**58 (9.6%)**, and those remaining are emitters whose curve is genuinely flat
across their life — including the 14 whose three curves the toggle mints flat at
the identity, where one control point is the honest answer. Median keyframes in
the column 2 → 3. The cost is a longer worst-case list, 47 against 24, paid in
the region where nothing draws it.

**It was also a fidelity bug, not only a visibility one.** The 0.774 is the
number that settles it: the keyframes the author edits were, at worst, three
quarters of full scale away from what the curve actually does *in the region the
picture comes from* — and the first ⬥ press recompiles all 160 samples from that
fit. The surface was not merely showing too few control points; the ones it
showed did not describe the rendered colour.

`life_n` is passed from `ColourKeyframeSession`, the layer that has an emitter to
resolve one from, keeping `EmitterLifeWindow` the one derivation of the axis.
Omitting the parameter is the pre-amendment global fit exactly, which is guarded,
so the three callers with no emitter to ask are untouched.

**And the guard that was green through all of it.**
`EffectStudioColourEnableTest` asserted that the flag flipped, that a column
appeared, and that the column had rows. It never asserted the column had
**keyframes** — which is the entire feature; "a surface to author on" was read as
"a surface". This is the fourth time on this family that a fully green suite
shipped a wrong picture, and the same lesson each time: the assertion has to name
the thing the author came for. It does now, with a floor that differs per arm,
because a minted flat curve honestly has one control point over its life while a
real ROM curve that shows one is the starvation itself. Reverting the single call
site fails it with *"1 of 24 are inside the life, wanted >= 2"*.

Separately, `EffectStudioColourRibbonAcceptanceTest`'s assertion-count pin was
left at 12 when `cbee913d7` added a 13th, so it had printed *"[FAIL] ran 13
assertions, expected 12 — the test aborted early"* on every run since, at 13
passed and 0 failed. Bumped. A pin that cries wolf is the guard that gets ignored
right before it catches something.


### Amendment (build, 2026-08-21): an age has a MINIMUM WIDTH, and the band grows into the width a wrap leaves on the floor

Author, on a sprite that is one frame held for its whole life: *"sometimes for
sprites which are just one frame and held things get crazy on the keyframes — can
we maybe do a minimum width keyframes?"*

**The number under it.** The vertical column splits the band into one sub-column
per life frame (decision 1 above), so a row owning `t` ages draws each at
`band / t`. E088 em1 is **one row of 128 ages in 22px — 0.17px an age**. Censused
over 3,214 colour emitters (`tools/census_colour_column_width.gd`) the 10th
percentile column is **1.83px** and the 1st is **0.50px**, under a pixel. And the
consequence is not only cosmetic: an age is selectable only if some *integer*
pixel floors to it, and `⬥` acts on the selection, so an age no pixel resolves to
cannot be keyframed at all. **3.8% of emitters have at least one such age; E088
em1 has 106 of its 128** (`tools/census_colour_column_reach.gd`).

#### Decision 1 — `min_col_w` (5px), and the band asks for `min_col_w × widest row`

Five because that is the keyframe mark's own footprint — `KF_W` plus its keyline
either side. Below it the thing that says *this age is a keyframe* cannot fit
inside the age it is the mark for.

The band is **one width per column, set by its widest row**, never per row: `_draw`
divides `size.x`, so a per-row width is a number the picture cannot express, and
the alignment claim (row *i* IS thumbnail *i*) is about the vertical axis alone.

#### Decision 2 — the width comes from the pairs the strip does NOT use

This is what makes it affordable rather than a trade against the player's square,
and it is arithmetic, not taste.

`EffectStudioPage`'s life slot is `sequence_life_slot_w(3)` = **198px**. Take the
scrollbar and the two gaps between pairs, divide by three, and each pair gets 58 —
of which 34 is the thumbnail and 2 its gap. **The remainder is 22, which is
`band_width`.** So the constant was never a judgement about how wide a ribbon
should be; it is what *three* pairs can afford. Solve the same expression for one
pair and the answer is **150**; for two, 54.

And the strip reaches for three pairs only when it has the rows to fill them —
while `rows × ticks ≈ life_n`, so **a row is wide exactly when there are few rows,
which is exactly when there are spare pairs.** The width a wide row needs is
sitting unused in the same slot.

| pairs the strip uses | band each may take |
|---|---|
| 1 | 150px |
| 2 | 54px |
| 3 | 22px — `band_width`, the floor |

`ColourLifeColumn.band_max` caps it at 150 for the same reason the floor exists.
Without a cap a 128-age row takes every spare pixel the panel has (measured: 374
on a wide row), and while that moves nothing the author has complained about, a
ribbon five times the width of the thumbnails it annotates is a different picture
rather than a bigger one.

#### Decision 3 — the host's slot never moves, and the growth happens INSIDE it

The slot's declared minimum stays **one pair**, exactly as the wrap amendment left
it. A per-emitter bid would make the inspector's right edge a function of which
emitter is open — *"the animation box is changing in size all the time"*, already
answered twice on this surface — and `_canvas_floor_w` reads declared minimums, so
a column that raised its own would shrink the player's square per target. It does
not: `_sequence_life_slot` is a plain `Control`, so its combined minimum is its own
`custom_minimum_size` and nothing inside it can reach the floor walk. The ceiling
is read off the slot's **live** width (`life_band_ceiling`), which is the leftover
`_relayout` already computes, so the grown pair lands in space the panel was
already holding.

#### Decision 4 — the keyframe mark never outgrows the age it marks

Not a consequence of the width — a *second*, independent half of the same report,
and no band fixes it alone. The mark was a flat 3px bar with a 1px keyline grown
around it: **5px of footprint on a column 1.4px wide**, so a keyframe painted over
its two neighbours and a *run* of adjacent keyframes read as one white block
instead of three separate ages. It is clamped to its own column now, and the
keyline is drawn only where the age has room for it — below that the keyline is
the thing bleeding into the neighbour, which is the defect and not the cure.

#### What it buys

Censused over the same 3,214 emitters: the 10th-percentile column goes
**1.83px → 5.00px**, and emitters where every age is reachable by some click go
**96.7% → 99.9%**. The median emitter is unchanged — 81.8% of rows are a single
full-width column and ask for nothing.

Two emitters still cannot be satisfied (26 and 25 ages against a 27- and 28-row
strip, which uses all three pairs and so has no slack). Said rather than rounded
away: the cap is the slot, and the slot is constant on purpose.

**Verified by looking**, E088 em1 at the same window and emitter, driven through
`band_max` so the two shots differ in one value: before, a 22px smear where the
16 keyframe marks cover essentially the whole band and no colour is legible;
after, a 150px band where the teal, the olive, the long magenta ramp and each
keyframe bar are separately readable. Rig kept at `tests/ColourColumnWidthShot.gd`.

---

## Amendment (built, 2026-08-21): the picker authors the CURVE, and the sprite's bound is REPORTED rather than imposed

Reported as: *"the color picker to get the keyframe color really just isn't
working. I am not able to reach every [0,0,0] to [255,255,255] because I can get
more extreme colors changing the curves directly than picking the colors in the
color pickers. So I don't know maybe we just resort to a regular color picker with
no muxing stuff"* — and, in the same breath, *"and we just rely on keyframes."*

This amends **decision 4** of the colour-keyframe amendment for the second time. The
first (SHOW-ALL-COLOURS, 2026-08-13) un-restricted the picker's *display*; this one
changes what a pick **means**.

### The two faults, and only one of them had a name

**THE RANGE.** The picker authored in MUXED space: you picked the OUTPUT colour `T`,
the tool stored `clamp_to_box(T, S)` against the emitter's representative sprite texel
and compiled `curve = T ⊘ S`. Both ends are 8-bit, so a channel's byte slider could
only ever hold `round(S.k × 255)`. Censused over **3,213 corpus colour emitters**
(`tools/census_colour_picker_reach.gd`):

| | |
|---|---|
| `S` resolves to exactly white (full 0..255 on every slider) | 80 = **2.5%** |
| **NO channel's slider can hold 255** | 3,133 = **97.5%** |
| at least one DEAD channel (`S.k == 0`) | 136 = 4.2% |
| authorable byte levels, worst channel (of 256) | min 1 · p10 57 · **median 217** · p90 249 |

*"I am not able to reach every [0,0,0] to [255,255,255]"* was a literally true
statement about this control, for essentially every effect in the corpus.

**THE FIGHT**, which is the half nobody had named and is probably the larger share of
*"really just isn't working"*. `EffectStudioPage._update_colour_picker_panel` re-seeds
the grid **on every drag frame** — its own comment says so — and the seed was the
box-clamped colour. So each mouse-move toward a bright colour was immediately
overwritten with the darker achieved one and the HSV square crawled back under the
cursor. The control disagreed with the hand holding it.

### The author's counter-evidence, settled before anything was designed

*"I can get more extreme colors changing the curves directly"* contradicts the render:
`ALBEDO = texel × curve` with `curve ∈ [0,1]` (`effect_particle_opaque.gdshader:27`,
`CurvePaintModel.grid_to_curve`), so the output per texel **cannot exceed that texel**
and `curve = 1` — the box's top corner — already is the brightest achievable ALBEDO.
Editing curves directly cannot beat it. Three candidates were on the table; the
measurement picks between them:

1. **ADD blending — yes, and it is why the swatch felt dishonest.** 94.6% of these
   emitters visit an ADD frame, so the composited pixel is background **+** ALBEDO
   while the picker's swatch showed ALBEDO alone, opaque. The picker was accurate
   about a quantity the author never sees in isolation.
2. **A wrong `S` from the flat RGBA bake on 4bpp effects — NO, and this mattered to
   check first**, because it would have made the whole thing a one-line bug fix rather
   than an amendment. Only **12.2%** of colour emitters visit a 4bpp frame, and
   `effect_particle_opaque` samples that same flat `texture.tga` anyway, so `S` is the
   texel the shader reads.
3. **One texel standing for a whole sprite** — real, unchanged by this amendment, and
   the reason `renders_as` is a swatch rather than a promise.

So the claim is true of the **control's range**, not of the render's maximum. That is
the thing being fixed.

### Decision 4 (amended) — the picked RGB IS the curve triple

`0..255 → 0..1` per channel, and `S` is out of the write path entirely.
`ColourKeyframeFit` stops muxing on import and inverse-muxing on compile; `place()`
clamps to the unit cube; `seed_curve` clamps to nothing else. Picking white writes
curve `(1,1,1)` — the sprite unmodified, the brightest ALBEDO the multiply can produce
— and picking black writes black.

**This does not contradict decision 1 of the amendment it lives in.** Decision 1
refused to reach arbitrary colours by augmenting the shader, because *"that renders
differently from the game and makes the studio a superset the game can't reproduce."*
A curve picker never asks the shader for anything it cannot do: every value it can
express is a byte the packer already writes. You still cannot make a green-only sprite
red, and that is physics rather than UI.

### Decision 8 (new) — the bound is STATED, on the surface that used to apply it

`S` has not stopped mattering; it stopped being applied silently. A multiply can scale
a channel and never add one, so the render is still bounded by the sprite. The picker
panel now carries a **renders-as row** — a swatch of `S ⊙ curve`, the same multiply the
shader and the ribbon do, beside the grid — and names the dead channels when the sprite
has any.

That report is `dead_channels()` finally having a caller. It was written as
*"informational … callers use it to explain the limit"* and had **none** for the whole
life of the muxed picker: the explanation was built and never wired, which is this
family's recurring shape. A pick that is not honoured now says so.

The row is **header, not grid** — it degrades with the ⬥ button rather than with the
colour square, because a bound nobody can see is the fault it exists to remove.
`picker_head_h` grows 64 → 88 for it. It does not wrap: an autowrap `Label`'s minimum
height is a function of the width it is given, and in this 298px column that put the
panel's header minimum at **228px** against a declared floor of 88 — which is not
cosmetic, since everything past the floor overflows off the bottom of the display and
takes ⬥ with it. `EffectStudioColourColumnTest` caught it, which is the guard working.

### What is NOT changed: the ribbon still muxes

Dropping the clamp and dropping the ribbon's mux are two different decisions and only
the first was asked for. The ribbon shows **what renders** — that is why a green-only
sprite (E138 idx0: R=0/B=0) reads correctly there instead of showing the raw curve's
red/orange. The author's *"we just rely on keyframes"* reads as accepting that the
picker no longer previews the render, which does not require the ribbon to change.

The consequence is that the picker and the ribbon now deliberately **differ**: the
swatch is the value being authored, the ribbon cell is the colour it makes. The
renders-as row is the one place they are shown to agree, which is why it is not
optional. The seed followed: an interpolated age used to open on
`ColourRibbon.colors()[frame]` so the swatch and the cell under the cursor agreed by
construction; it opens on `ColourKeyframeFit.curve_at` now, which IS the interpolation
`compile_to_curves` performs, so the grid shows exactly the value a commit would write.

### No migration, and this was a measurement rather than a judgement call

The open question was whether existing keyframes storing the muxed target `T` would
need a conversion on load or a format change. **Neither: keyframes never persist.**
`ColourKeyframeSaver` writes the dense 160-sample curves (`curves.json`) and the
repointed emitter addresses; `ColourKeyframeSession.begin` re-derives keyframes from
those curves through `import_from_curves` every time. Changing the space is therefore a
pure in-memory re-interpretation, and the same `curves.json` round-trips unchanged.

### The 83 line-gamut emitters

Two dead channels leave a box that is a *line*, and under the old model that was a
picker with one usable axis. In curve space all three channels are independently
authorable and independently saved; two of them multiply by zero. That is reported by
the renders-as row and named by the dead-channel tag, and it is deliberately **not**
a disabled slider: disabling would resume deciding for the author in the channel where
the old design's silent rewrite was least defensible.

### Guards

`ColourMuxTest` 33 → **52** · `ColourBoxPickerTest` 15 → **24** ·
`ColourKeyframeFitTest` 48 → **55** · `ColourKeyframeSessionTest` 35 → **40** ·
`EffectStudioColourKeyframeAcceptanceTest` 29 → **31** ·
`EffectStudioColourColumnTest` **83** · `EffectStudioColourEnableTest` **30** ·
`EffectStudioColourRibbonAcceptanceTest` **13** · `ColourLifeColumnTest` **89** — all
0 failed. The new assertions are the ask stated as tests: `clamp_unit` admits every
corner of the cube for a sprite that would have crushed it; a placed keyframe writes
the pick verbatim; a dead channel is authored and reported rather than locked; and the
acceptance path drives a real `(0.95, 0.6, 0.15)` pick — outside the old reachable box
in almost every channel — through the UI to the renderer's modulate.

### Still open

* Whether the renders-as swatch should show the **ADD composite** (background + ALBEDO)
  rather than ALBEDO alone. It is the more honest preview for 94.6% of emitters and it
  needs a background to composite against, which the panel does not have.
* The `MAX_KEYFRAMES` residual is now quoted in curve space rather than muxed space.
  For a dark sprite the same fit reports a *larger* `max_error` than it used to — the
  same error, in the units the packer writes. Nothing reads it yet.
