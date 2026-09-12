# EffectTimeline capstone: one clock pumps a uniform, ordered subsystem list; subsystems own their meaning

## Status

Accepted (2026-06-03)

Verified 2026-08-28 — every decision below is built (`src/effects/EffectTimeline.gd`,
`Subsystem.gd`, `ParticleSubsystem.gd`, `SoundSubsystem.gd`; roster order asserted by
`tests/EffectTimelineTest.gd`). Two things moved after: [ADR-0014](0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md)
supersedes this ADR's time-modulation split and its "`EffectInstance` wires every
output" rule, and the runtime `*TrackController` classes were renamed `*Subsystem`
(#31). The defensive `has_timeline == false` warning asked for below is **not**
built — see `AUDIT.tsv`.

## Context (before this decision)

[ADR-0011](0011-effect-timeline-orchestrates-uniform-tracks.md) established the
effect-orchestration model and delivered its first two passes (the color-subsystem
base; camera conformed to `advance`). It deferred the **capstone**: collapsing the
split orchestration — where `EmitterManager` owned the clock/phase/time-mod/particle
timeline and `EffectInstance._process` separately pumped color/camera/sound — into
one real `EffectTimeline`, with particle re-homed as a peer subsystem. This ADR is
that capstone. It builds on ADR-0011's `EffectTimeline`-is-the-owner ("option B"),
the no-clock invariant, and the **resolved** pump-granularity decision (frame-granular
pump on a fixed-rate accumulator; three clock planes; sound self-handles its one fire
sub-tick internally).

## Decision

**`EffectTimeline`** (owned by `EffectInstance`) is an output-agnostic control-plane
pump. It owns the fixed-timestep accumulator, the `effect_frame` clock, the phase
state, and time-modulation, and it holds an **opaque, ordered list of subsystems**
that it pumps. It never learns what a subsystem produces. `EffectInstance` registers
the ordered list once, through `set_subsystems`.

### The `Subsystem` contract

`advance(frame: int, phase: Array) -> void`, plus `reset()` and `is_done()`
(`src/effects/Subsystem.gd`). Outputs stay type-specific and never cross the
interface (color → overlays, camera → pose, particle → pool/signals, sound →
key-on). Each subsystem **self-delivers** its own output — ADR-0014 supersedes this
ADR's original rule that `EffectInstance` wires every output.

The contract is documented, not enforced, and satisfied entirely duck-style: no
file extends `Subsystem` (see ADR-0014's vocabulary section, and issue #675 for the
docstring that says otherwise).

### Phase is the set of open authored-window labels (phase model "C")

Phase is **not** a one-of-three enum and **not** a clean linear sequence. Effect data
is split into three authored sub-tables (`phase1`, `for_each`, `phase2` — the channel
`context` values `tools/parse_effect.py` emits), each with a `[start, stop)` **window**,
and the windows **overlap** (`phase2` runs parallel with `for_each`). So the
orchestrator computes, once per frame, the **set of currently-open windows**
(`{phase1}` → `{for_each}` → `{for_each, phase2}`) and passes it to every subsystem
(`EffectPhase.open_phases`). Subsystems consume it **by arity**:

- **Single-valued** subsystems (color: one background, one tint) **reduce** the set to
  the dominant window (`phase2 > for_each > phase1` — `EffectPhase.dominant`).
- **Multi-valued** subsystems (particle, sound: many emitters/channels) play **all**
  open windows in parallel — this is the only reason the overlap matters; collapsing
  to an exclusive value would wrongly cut `for_each` off when `phase2` starts.

The overlap is irrelevant to single-valued subsystems. There is **no 4th phase** and
no global "the effect is in phase X" — enumerating window combinations as segments
re-describes the overlap and doesn't map to the three source tables; the set does,
with no enumeration.

### Subsystem roster, fixed order

`EffectTimeline` pumps in a fixed registration order for determinism (the four
outputs are independent within a tick, so order can't change correctness — it serves
reproducibility + behavior-preservation):

`particle → sound → color (screen, palette) → camera`

- **`ParticleSubsystem`** — the re-scoped `EmitterManager`: it sheds the clock,
  accumulators, phase flags, and time-mod to `EffectTimeline`, and keeps the emitter
  pool, spawn fulfillment, **physics step**, and cleanup. Its `advance(frame, phase)`
  runs the open phases' channels (multi-valued: all open) + one physics step +
  cleanup. The two former 30 Hz accumulators (timeline + physics) consolidate into
  the one `EffectTimeline` accumulator — equivalent, since they already fired in
  lockstep at 1/30.
- **`SoundSubsystem`** — a thin adapter in `src/effects/` wrapping the
  exmateria-sound addon's `EffectSoundController` (`advance(frame, phase)` →
  `update(frame, controller.fire_sub_tick)`; sound self-derives both phase and its
  one fire sub-tick internally, so it ignores the passed set). Passing the
  controller's own `fire_sub_tick` once per frame matches the gold a-la-carte driver
  (`exmateria-sound/workspace/harness_lib/effect_audition_player.gd`) and closes the
  `fire_sub_tick != 0` gap. The released addon stays untouched — the `Subsystem`
  contract is godot-learning's orchestration vocabulary, not the sound package's
  domain.
- **Color** (`ColorSubsystem` and its `ScreenSubsystem` / `PaletteSubsystem`
  subtypes) and **camera** (`CameraSubsystem`) keep the pass-1
  `advance(frame, phase)` signature **unchanged** — only `phase`'s value widens
  (a single phase string → the open-set array). Color consumes the set (reduced to dominant — the same "phase2
  wins" result). Camera and particle self-derive their finer routing from `frame` +
  boundaries they hold.

The clock quantities re-homed with the pump: `effect_frame` (read by child-emitter
spawns and `ParticleSubsystem.get_last_active_effect_frame`) is the passed `frame`,
and the `phase1_duration` / `phase2_start` boundaries live on `EffectTimeline`, which
both the open-set computation and `get_last_active_effect_frame` read from the same
`effect_data.timeline` source — not drift.

### Stepping is unified (a deliberate, noted behavior change)

The pre-capstone pump was inconsistent on multi-frame catch-up: sound and camera
stepped each intermediate frame (`for f in range(current_frame, effect_frame)`),
particle stepped via its own accumulator, but **color advanced once with the
pre-update `current_frame`** — so on a render hitch where `effect_frame` jumped by
>1, color *skipped* the intermediate frame while the others caught up.
`EffectTimeline` unifies this: the accumulator runs N fixed steps, and **each step
pumps every subsystem for that frame**. Under steady framerate (the common case, and
the CB91 oracle) the accumulator runs exactly one step per logic frame, so behavior
is identical; the change manifests only on multi-frame jumps, where catching color up
is the correct behavior.

### There is no manual mode — every real effect is timeline-driven

Of the 512 effect slots, **401** have a for-each timeline (both real script
patterns — **3-phase** = opcode 41 outer phase-1/phase-2 + opcode 40 for-each, and
**1-phase** = opcode 40 for-each only — have one). The other **111** have no
`timeline.json`, and **all 111 are 0-byte `.BIN` files** (empty/unused slots in the
FFT effect table; verified against the ISO extract — E037/E038/E042/… = 0 bytes, vs
19.8K–105K for the 401 real ones). They have no timeline, no emitters, nothing.

So the old `else: start_emitter(0, 120)` manual-emitter fallback was **dead** — reached
only by empty slots, never spawning a particle — and is removed; removal is
behavior-equivalent. `ParticleSubsystem` does **not** model manual mode; the only
distinction it honors is **1-phase vs 3-phase** = whether the outer phase-1/phase-2
blocks exist. A future timeline-less-but-emitter-bearing effect must surface
**loudly** rather than silently spawning nothing — `EffectInstance` computes
`has_timeline` and gates `EffectTimeline.start()` on it, but does not yet warn.

## Considered options

(The forks were grilled individually; see ADR-0011 for the model-level choice of
`EffectTimeline`-owns-the-clock over `EmitterManager`-as-orchestrator.)

- **Pump granularity** — frame-granular `advance(frame, phase)` on a fixed
  accumulator (chosen), with sound self-handling its one fire sub-tick (it passes its
  own `fire_sub_tick` per frame, per the gold audition driver). Rejected: threading
  `sub_tick` through the pump (only the PCSX-diff harness needs full 8-sub-tick
  iteration; playback fires one sub-tick per frame) and a separate sub-pump for sound
  (violates "sound from the same source"). Frame-granular still closes the
  `fire_sub_tick != 0` gap, because sound passes its fire moment rather than the
  `sub_tick = 0` default that gates it out.
- **Phase representation** — the open-window **set** (chosen) over a collapsed enum
  (wrong for parallel `phase2`) and over a 4-phase linear segmentation (re-describes
  the overlap, doesn't map to the 3 tables).
- **Phase computation location** — computed **once** in the orchestrator and passed
  (chosen, DRY: all subsystems share the same phase) over each subsystem recomputing
  the frame→phase mapping (duplicates the mapping 4×, the drift class the project's
  ADRs fight). Camera/particle still self-derive their *finer* routing (for-each
  windowing, parallel ticking) — genuinely richer than the shared set, not a
  duplicate of it.
- **`EffectTimeline` knows outputs** — rejected: re-fuses the orchestrator with
  output wiring, the same fusion rejected for `EmitterManager`. The timeline pumps
  time; Godot-side I/O (overlays, camera, renderer, SPU) stays out of it.
- **Sound conformance** — adapter (chosen) over a native `advance()` on the addon:
  the `Subsystem`/`phase` vocabulary is godot orchestration, foreign to the sound
  package's domain; the addon is already externally pumpable, so the adapter is the
  whole job and keeps both packages clean.
- **Split time-modulation** — the particle subsystem computes `time_scale_factor`
  (it holds the phase controllers the pacing curve is indexed by) and the timeline
  reads it back and applies it — *(shipped 2026-06-03, superseded by ADR-0014: once
  the capstone relocated the clock, those cursors are derivable from state the
  timeline already owns, so the reach-back was residual coupling, not necessity)*.
- **`"animate_tick"` as the for-each phase's string value**, kept for ROM linkage
  with the Ghidra label of the opcode-40 handler — *(shipped, reversed 2026-06-04:
  the ROM has no inherent names; Ghidra labels are our own annotations. The value is
  now `"for_each"`, matching the const, with parser, regenerated JSON keys,
  `src/effects/`, and the addon's `effect_json_loader.gd` /
  `effect_sound/play_sound.gd` updated in lockstep)*.
- **`*TrackController` runtime class names** — *(shipped, renamed to `*Subsystem`
  2026-06-04 per issue #31; the `class Track` inner containers in `PaletteData` /
  `ScreenData` became `class Channel`)*.

## Consequences

- `EffectTimeline` is unit-testable with stub subsystems: register fakes, call
  `tick(delta)`, assert each got `advance(frame, phase)` in order at the right
  cadence — no overlays, no SPU, no `RenderingDevice`. `tests/EffectTimelineTest.gd`
  is that test.
- `ParticleSubsystem` loses the clock/phase/time-mod/accumulator block and gains an
  `advance(frame, phase)`; its name is now accurate (emitter/particle host only). Its
  `emitter_started` / `emitter_stopped` / `action_flags_triggered` signals are
  unchanged; `EffectInstance` still subscribes.
- `current_phase()` (added in pass 1) is generalized from the collapsed enum to the
  open-window set; the pass-1 `advance(frame, phase)` color signature is
  **unchanged** — only `phase`'s value type widens (string → open-set array).
- The latent `fire_sub_tick != 0` gap closes: the `SoundSubsystem` adapter passes the
  controller's own `fire_sub_tick` per frame (not the `sub_tick = 0` default), so
  calibrated sub-tick effects (ice=5, …) fire.
- Behavior-preserving under steady framerate; the one intentional change is color
  frame-jump catch-up (above). Verify headful: CB91 (`tests/CB91TimingTest.gd` —
  color + palette value sequence + particle/callback frames), `tests/CameraSpinTest.gd`,
  and a sound-bearing effect.
- **Nomenclature follows `research/NOMENCLATURE_UPDATE_PLAN.md`**, the canonical
  authority. It standardized the conceptual/display/wiki terms (its Phases A & B are
  complete): the middle phase is **for-each**, patterns are **3-phase / 1-phase**,
  opcodes are `for_each_phase_timeline_tick` (40) / `outer_phases_timeline_tick`
  (41). Its Phase C (code identifiers) is **done for godot-learning and the
  `exmateria_sound` addon** — the const is `PHASE_FOR_EACH` and its value is
  `"for_each"` (`src/effects/EffectPhase.gd`) — and still open for the effect-editor
  lua. `phase1` / `phase2` keep their identifiers.
- **The `child_emitter_*` fields keep the "child" name** (NOMENCLATURE plan §1.7):
  they are *particle hierarchy* (a particle spawning another emitter's particles on
  death / mid-life), explicitly **separate** from effect phase terminology. The
  "child → for-each" rename applies only to the *phase* / *spawned-instance* sense,
  not these fields. So `ParticleSubsystem`'s child-emitter one-shots stay "child
  emitter."
- The word "track" survives only on the data side: ROM `.BIN` filenames, the
  FFT-faithful `Keyframe.track_enable` field
  (`research/key_documents/STRUCTURE_DEFINITIONS.md`), and internal sound-parser
  helpers. There is no runtime "track".
- Not part of `bootstrap_assets.sh` — hand-authored runtime code.
