# Effect playback is one timeline orchestrating uniform tracks; the clock owner is not the particle manager

## Status

Accepted (2026-06-03)

## Context (before this decision)

A spell/ability **effect cast** plays back several subsystems over the same
frame clock and phase schedule (`phase1` → `animate_tick`/for-each →
`phase2`): screen background color, map/unit palette tinting, camera
animation, particles, and effect sound. See the new
[Effect orchestration](../context/15-effect-orchestration.md) glossary
cluster for the vocabulary.

Today that orchestration is **split across two owners and has no shared track
interface**:

- `EmitterManager` owns the master clock (`effect_frame`), the phase flags
  (`phase1_finished` / `phase2_started`), **time modulation**
  (`time_scale_*`, a per-frame pacing *curve* that scales `delta`), **and**
  the particle timeline — plus the bulk of its ~814 lines of emitter/particle
  pool management.
- `EffectInstance._process` separately pumps the color/camera/sound
  processors off `manager.effect_frame`.

The non-particle processors duplicate scaffolding instead of sharing it.
`ScreenTrackController` and `PaletteTrackController` both re-implement the
once-per-frame guard, the frame→phase block, the per-cursor keyframe
bookkeeping, overlay-ownership (`owner_id`), and the from→to lerp — and both
carry **dead `phase1_finished` / `phase2_started` parameters** they ignore in
favour of recomputing the phase from the frame. `CameraTrackController`
mirrors a *different* PSX routine (`advance_camera_tracks` 0x801AD198 /
`find_active_camera_keyframe` 0x801ACB08) with a re-search advancement model
and five interpolation modes, and is genuinely not the same shape.

A fourth processor, the exmateria-sound addon's `SoundTrackController`, already
documents its intent to "migrate into godot-learning as a sibling to
PaletteTrackController / CameraTrackController … subscribes to an external
30 Hz tick instead of owning one." It lives in a **released-in-isolation
package** and cannot import godot-learning types — so any shared interface
must be satisfiable by a foreign class given only a *tick + phase*.

## Decision

Model effect playback as **one orchestrator pumping uniform tracks**, and
separate the orchestrator from particle management.

1. **The `Track` contract is minimal and uniform:** `advance(frame: int,
   phase: String) -> void` (the orchestrator owns the clock *and* the phase
   and passes both in), `reset() -> void`, and an optional `is_finished() ->
   bool` (default `false`). **Output stays type-specific and never crosses
   the interface** — color via `get_delta()`/`get_tint()` + overlay
   registration, camera by mutating its pose fields, particles/sound via
   signals. The orchestrator pumps *time*; it never learns what a track
   produces. `phase` is the existing `EffectPhase` string set, not a new int
   enum.

2. **The end-state orchestrator is a dedicated `EffectTimeline`** that owns
   the frame clock, the phase state, and **time modulation** (which scales
   the clock, so it is a clock concern — *not* a track; it has no keyframes).
   It pumps `[ColorTrack, CameraTrack, ParticleTrack, SoundTrack]`. The
   particle timeline becomes a **peer `Track`**; `EmitterManager` shrinks to
   that track's emitter/particle host and thereby regains its honest name.

3. **The color tracks share a scaffolding base, not a shared inner loop.**
   `ColorTrackController` owns the N-channel cursor bookkeeping, the
   once-per-frame guard, `owner_id`, the transition state, and a reusable
   `_run_transition()` lerp helper. `ScreenTrackController` (one channel) and
   `PaletteTrackController` (three channels: `affected_units` / `caster` /
   `target`) extend it and override `_evaluate(channel, phase)` with their own
   ROM-faithful blend math. Screen is the degenerate one-channel case of the
   N-channel model.

4. **Vocabulary is fixed first.** A **track** is one subsystem's keyframe
   stream; a **channel** is a parallel keyframe lane within a track. The
   palette processor's three lanes were misnamed "tracks" and are renamed to
   **channels**, matching the particle/sound usage. "Track"/"channel" of the
   *music* SMD/SPU path are a separate timeline and are explicitly *not*
   unified (see CONTEXT.md "not to be confused with").

5. **Delivery is incremental, behaviour-preserving.** Pass 1 extracts
   `ColorTrackController` and re-bases screen + palette behind the `Track`
   contract, dropping the dead phase params; the pump stays in
   `EffectInstance`. Camera, particles, and sound migrate onto the contract in
   later, separately-verified passes. The `EffectTimeline` collapse — moving
   the clock/phase/time-mod off `EmitterManager` and re-homing particles as a
   track — is the **capstone**, after all tracks conform.

## Considered options

- **`EffectTimeline` owns the clock; particle is a peer track (chosen, "B").**
  Cleanest object model and 1:1 with the glossary: the orchestrator owns only
  what every track shares (clock, phase, time-mod), and particle stops being
  special. It also fixes the naming **without a forced rename** —
  `EmitterManager` becomes accurately scoped to emitters.
- **`EmitterManager` becomes the orchestrator ("A").** Rejected: it fuses two
  jobs with no shared state forcing the fusion (the clock is read by every
  track; the emitter pool is touched by nothing else). The fusion *is* the
  bad name, and A would require renaming `EmitterManager → EffectTimeline`
  while leaving the residual particle-host coupling inside the orchestrator.
  Crucially, choosing B over A costs **nothing in pass 1** — the extra churn
  all lands in the already-deferred capstone.
- **Color base owns a shared inner evaluate loop, config-driven (Q5 "B").**
  Rejected: the base would have to model the *union* of screen and palette
  behaviours (instant-keyframe chaining, fade curves, mode-10, disabled) with
  screen opting out, turning the base into "palette's loop with screen as a
  degenerate config." This project's ADRs repeatedly value keeping each PSX
  reimplementation faithful to its named routine; the scaffolding-only base
  removes the genuine duplication without putting that fidelity at risk.
- **Fold camera into the same base as color.** Rejected: camera mirrors a
  different ROM routine (re-search advancement, five interpolation modes, no
  overlay/compositing concept). It conforms to the `Track` *interface* but
  shares no *implementation* with color — one adapter behind the seam, not a
  subtype of the color base.
- **A new int `Phase` enum.** Rejected: the codebase pervasively keys on the
  `EffectPhase` string constants; an int enum is churn for no safety here.

## Consequences

- The `Track` interface is the test surface: a color track is testable by
  feeding `advance(frame, phase)` and asserting `get_delta()` over fixtures —
  no `RenderingDevice`, no overlays, no scene.
- The dead `phase1_finished` / `phase2_started` parameters disappear; the
  frame→phase mapping lives once (in the orchestrator, exposed as the phase it
  passes to `advance`).
- Because `EmitterManager.update()` sets the phase flags from `effect_frame`
  *before* incrementing it, the orchestrator's phase at `current_frame` equals
  what the color controllers computed internally — so pass 1 is
  behaviour-preserving with no off-by-one.
- The foreign `SoundTrackController` can satisfy the `Track` contract
  unchanged in spirit (it already takes an external tick); the migration wraps
  it, it does not fork it.
- **No-clock invariant (the separability rule).** A track owns no clock — no
  `Timer`, no `_process`, no scene-tree handle — and is driven by whatever
  pump calls `advance()`: the orchestrator in gameplay, or a standalone
  harness (a `Timer`, a test rig) a la carte. The sound track already proves
  this: its processor is clock-free, and the `Timer` lives in a separate
  exmateria-sound wrapper, so the *same* controller is pumped by the exmateria-sound
  `Timer` and by godot-learning's effect frame today. Because no track owns
  time, the capstone collapse is *gathering the scattered `advance()` calls
  into one `EffectTimeline.tick()`*, not a redesign of any track. Recorded in
  CONTEXT.md's `track` entry.
- **Pump granularity — RESOLVED: sub-tick-aware pump on a fixed-rate
  accumulator.** Three clock planes, each decoupled from the one above by a
  buffer: (1) **render** — variable, "as fast as the game runs" (Godot
  `_process(delta)`); (2) **effect logic** — a *fixed* 30 Hz tick subdivided
  into **sub-ticks**, produced by a fixed-timestep accumulator
  (`while acc >= 1/30: tick()`, already in `EmitterManager.update`); (3)
  **audio** — the SPU (`libfftspu`) synthesizing at 44.1 kHz in the audio
  thread, autonomous. The orchestrator is a **control-plane** pump only: it
  owns the accumulator (variable render `delta` → fixed 30 Hz ticks) and pumps
  each track once per fixed frame with integer `(frame, phase)` — tracks never
  see render `delta`. It does **not** pump the SPU; the sound track merely
  *fires a key-on* that the autonomous SPU picks up downstream.

  **The pump is frame-granular — `advance(frame, phase)`, no `sub_tick`.**
  (Refined during implementation, reversing an earlier "sub-tick-aware pump"
  draft.) The sub-tick is **internal to the sound track**, not a pump concern:
  there is exactly *one* fire sub-tick per frame (`SoundTrackController`'s gate
  `if sub_tick != fire_sub_tick: return`), and the gold a-la-carte driver
  fires it with `update(frame, controller.fire_sub_tick)` once per frame
  (`effect_audition_player.gd`). So the `SoundTrack` adapter passes the
  controller's own `fire_sub_tick` per frame — which **still closes the
  `fire_sub_tick != 0` gap** (today's bug is godot passing the *default*
  `sub_tick = 0` instead of the fire moment). The 8-sub-ticks-per-outer-tick
  detail (≈240 Hz; `runtime.gd`) is real *inside* the effect VM and is iterated
  only by the PCSX-diff harness (`render_effect_sound.gd`) — it is irrelevant
  to playback, so it stays out of the pump. Sound thus self-handles its
  sub-tick the same way camera self-handles its for_each windowing. Pass-1
  color tracks keep `advance(frame, phase)` unchanged; only `phase`'s meaning
  widens (enum → open-set, below).
- Not part of `bootstrap_assets.sh` — this is hand-authored runtime code, not
  an ISO-derived asset.

## Addendum (2026-06-04): runtime-class rename — Track→Subsystem

Issue #31 landed the rename from `*TrackController` to `*Subsystem` for every
runtime that consumes effect keyframe data: `ColorTrackController` →
`ColorSubsystem`, `PaletteTrackController` → `PaletteSubsystem`,
`ScreenTrackController` → `ScreenSubsystem`, `CameraTrackController` →
`CameraSubsystem`, `SoundTrack` → `SoundSubsystem`. Plus `EmitterManager` →
`ParticleSubsystem` (#30). The duck-typed contract is `src/effects/Subsystem.gd`.

`EffectTimeline.set_tracks` is now `set_subsystems`; the internal `_tracks`
field is `_subsystems`. Vocabulary in CONTEXT.md's "Effect orchestration"
cluster now reads **Subsystem → Phase block → Channel → Keyframe**; "track"
no longer names a runtime concept.

The decisions this ADR records — one timeline orchestrating uniform pumped
units, the no-clock invariant, self-delivered outputs — are unchanged. Only
the words used to refer to the runtime objects.
