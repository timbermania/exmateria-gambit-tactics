# Unit animation uses one clock per unit; layer playbacks are pumped

Each Unit owns **six** `AnimationPlayback` instances — two symmetric
[playback sets](../context/19-animation-playback.md) of three each:
the normal set (`type1_playback` / `wep1_playback` / `eff1_playback`,
one per [layer](../context/18-sprite-layers.md): BODY, WEAPON, EFFECT)
and the parallel React set (`react_playback` / `react_wep1_playback` /
`react_eff1_playback`, same shape; see [ADR-0025]). In the original
shape each Playback owned its own `accumulator`, its own `tick_based`
flag, and a `playback_speed_multiplier` knob — and each accumulated time
independently, so the speed multiplier on `type1_playback` desynced its
cadence from the un-multiplied WEAPON / EFFECT. `Unit._process` calls
`.process(delta)` on all six; `GPUArena` flips all six to
`tick_based=true` and tests then call `.advance_tick()` on all six in
the same loop. The cadence synchronization between layers is
**enforced at the call site**, not by the model — and the speed
multiplier is set only on `type1_playback` (Unit.gd:709), so a
fast-walking unit's BODY animation genuinely outpaces its WEAPON /
EFFECT in free-running mode (latent drift bug, masked in production
because GPUArena uses tick-locked mode).

We restructure to mirror the [effect orchestration](../context/15-effect-orchestration.md)
cluster (ADR-0011 / ADR-0012 / ADR-0014): **one `AnimationClock` per Unit
owns time; layer playbacks are pumped by it and own no clock.** Same shape
as `EffectTimeline` driving `Subsystem`s, applied to the unit's animation.

## Status

accepted

## Decision

- **`AnimationClock` owns the unit's time.** Per Unit, one instance — owns
  the `accumulator: float`, the integer `anim_frame` counter, the tick-vs-
  delta mode choice (one flag, one place), and the `playback_speed_multiplier`
  (one knob, one place). Its `tick(delta)` or `advance_tick()` advances
  the accumulator and pumps **all** of the unit's layer playbacks one
  frame each before returning. No layer playback runs without going
  through the clock.
- **Layer playbacks lose their `accumulator`, `tick_based`, and
  `playback_speed_multiplier`.** A layer playback becomes a pure
  frame-driven opcode runner: given a frame number from the clock, it
  advances its internal `anim_frame` by one, processes any opcodes in
  `(last_processed_frame, anim_frame]`, and emits its signals
  (`frame_changed`, `side_effect`, `animation_complete`,
  `animation_paused`, `distort_requested`, `move_offset_changed`). The
  signal surface stays unchanged; only the time-ownership moves.
- **The [body lead rule](../context/19-animation-playback.md) is preserved.**
  BODY's playback still restarts on state changes (the unit's state
  machine drives the BODY layer's `start()`); BODY's `QUEUE_SPRITE_ANIM`
  side-effects still trigger WEAPON / EFFECT layer `start()` calls;
  WEAPON's same opcode still triggers EFFECT. The cascade is unchanged
  data — only the clock under it changes.
- **React is a parallel set** (not a clock concern) — three playbacks
  that mirror the normal set, per [ADR-0025]. The clock pumps all six
  with **shared cadence and independent per-playback counters**;
  painting picks the active set by `_react_active`. The body-lead rule
  applies inside each set independently.

## Consequences

- The `playback_speed_multiplier` drift bug is gone by construction: one
  accumulator, one multiplier, six layer playbacks all driven from the
  same clock signal regardless of mode (their per-playback counters
  remain independent — see [ADR-0025]; the cadence is shared, not the
  counter values). The fast-walk-WEAPON-lags scenario can't happen.
- The `tick_based` / `process(delta)` mode duplication collapses to a
  single decision on the clock. `GPUArena.gd:163-166` (flipping four
  `tick_based` flags) becomes `unit.animation_clock.tick_based = true`.
  `GPUCombatTestBase.gd:173-176` (four `advance_tick()` calls per tick)
  becomes `unit.animation_clock.advance_tick()`.
- `Unit._process` calls `animation_clock.tick(delta)` once instead of
  `.process(delta)` six times. The six-playback loop moves into the
  clock's `tick` implementation, where it belongs.
- Tests that pump animation directly (the GPU combat test base, the React
  duration test) shrink — same number of frames pumped, one call per
  frame instead of four.
- The mental model for new contributors aligns with the effect side: "the
  pump owns time; the per-output runners are driven" is **one** rule that
  applies in both clusters. A reader who learned EffectTimeline already
  knows how AnimationClock works.
- The React playback's special pumping rules (its timer-bound vs untimed
  end conditions) live on the React playback itself, not on the clock —
  the clock just pumps; React still emits `animation_complete` /
  `animation_paused` on its own terms.

## Considered options

- **Keep N clocks; just fix the speed multiplier bug** (rejected).
  Closes the latent bug — extend the multiplier to all four playbacks (or
  hoist it to the Unit). But it leaves the asymmetry with the effect
  system in place: a reader who's learned ADR-0011's "no-clock invariant"
  for effects finds the unit's animation works in the opposite direction
  and has to re-learn it. The duplication is also a recurring failure
  mode (the next per-Playback knob will hit the same trap as the speed
  multiplier did).
- **One clock, but per-Playback frame indices fed by tick events**
  (rejected). Halfway design — the clock emits a per-frame "tick" signal;
  each Playback listens and advances its own `anim_frame`. Unifies time
  but keeps the drift surface (a Playback that misses a tick — say, one
  that was paused at the moment of emit — falls behind). The direct-pump
  model rejects this by construction: the clock *advances* each playback
  inside its own `tick()` body.

## Migration

Single-PR rewrite (the surface is small):
1. New `AnimationClock` class. `tick(delta)` advances accumulator and
   calls each pumped playback's new `advance_frame()` method per accumulated
   frame.
2. `AnimationPlayback`: delete `accumulator`, `tick_based`, `playback_speed_multiplier`,
   `process(delta)`. Rename `advance_tick()` → `advance_frame()` (the name
   no longer reads as a "GPU tick mode"; it's just "advance one frame").
3. `Unit`: own one `AnimationClock`, register its six layer playbacks
   (both sets per [ADR-0025]) with it, replace the six
   `.process(delta)` calls with one `animation_clock.tick(delta)`. Move
   the speed-multiplier assignment from
   `type1_playback.playback_speed_multiplier` to
   `animation_clock.playback_speed_multiplier`.
4. `GPUArena.gd`: flip the clock's mode flag once instead of four times.
5. `GPUCombatTestBase.gd`, `GPUReactDurationTest.gd`: one
   `animation_clock.advance_tick()` per tick instead of six
   `advance_tick()` calls.
6. CONTEXT.md "Animation playback" cluster: already updated alongside
   this ADR to use the new vocabulary.

[ADR-0025]: 0025-react-playback-is-a-parallel-set.md
