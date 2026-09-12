# Scenario playback advances all time-driven systems on one vblank-quantized tick

## Status

Accepted (2026-07-08)

Falsified and implemented the same day. The two-clock split was confirmed
mechanically (living doc Exp #2, `ScenarioClockUnificationTest`): under a jittery
host rate the motion offset led the VM tick by exactly one 60 Hz tick
(0.016667 s), and clean-60 hid it — the host-rate-dependent signature this ADR
predicts. The unify landed in `ScenarioVM` (`_advance_tick_visuals` +
scenario-entry `tick_based` flip); the guard test is GREEN (5/0) and wired into
`run_all_tests.sh`. Remaining work is *outcome* validation — the PSX continuous
trace-diff re-measure across scn6 beats 155–231 (living doc §6) — not the
decision, which is adopted.

During scenario (event-script) playback, **every** time-driven system —
event-opcode dispatch, unit motion (Sprite Move / Walk To), the camera director,
and the unit animation-frame clock — advances off the **single 60 Hz VM tick**
in [`ScenarioVM`](../../src/scenarios/ScenarioVM.gd), one integer step per tick,
modeling the PSX vblank interrupt. Concretely, the `_advance_frame` accumulator
loop pumps two siblings per tick: `_advance_tick_visuals()` (anim + camera +
motion at a fixed 1/60) then `_tick_once()` (dispatch — kept pure so tests can
step dispatch without moving the camera/slides). Host render-delta is **not** used to
interpolate scenario visuals: a scenario beat is a function of *tick count since a
resync*, not of wall-clock time. This refines
[ADR-0020](0020-unit-animation-uses-one-clock-per-unit.md) ("one clock per unit")
by fixing *what drives that clock* in the scenario context, and mirrors how combat
already drives it (the `CombatLoop` tick-driver + `AnimationClock` `tick_based`
mode, [ADR-0025](0025-react-playback-is-a-parallel-set.md)).

Scope is the scenario player **only**: units flip to `tick_based` on scenario
entry and restore to delta mode on exit. Combat (already tick-driven) and
free-roam (delta-driven, smooth) are untouched.

## The forcing bug

Godot runs **two clocks** during a scenario, and they disagree by a fractional
tick that grows within a non-blocking run.
[`ScenarioVM._advance_frame`](../../src/scenarios/ScenarioVM.gd) splits time:

- **Event dispatch is quantized to 60 Hz** — `_tick_accumulator += delta *
  _TICK_HZ; while _tick_accumulator >= 1.0: _tick_once()`. Integer steps,
  host-rate-independent. `_tick_once` drains opcodes, counts down `Wait`, etc.
- **Motion, camera, and the unit anim clock advance on raw host render-delta** —
  `_advance_motions(delta)` and `camera_director.tick(delta)` run once per
  `_process`, and each `Unit._process` independently pumps
  `display.anim_clock.tick(delta)` (delta-mode accumulator). The in-code comment
  states this is deliberate: *"so unit slides stay smooth independent of the 60 Hz
  VM tick."*

PSX has no such split — the FFT event engine **and** the sprite/motion/anim update
both run off the one vblank IRQ, one step per vsync, so position and pose are
locked to the event clock by construction.

The consequence is a **bounded, self-resetting visual lead**: the rendered sprite
(position + animation phase, integrated continuously on host-delta) runs ahead of
the event clock by the residual sitting in `_tick_accumulator`, and that lead is
proportional to how much motion/animation has been integrated **since the last
wait-boundary** (which re-anchors it to zero). Measured in the scn6 Delita/Ovelia
carry as a growing PC offset needed to re-match a beat (1 → 2 → 6 across one run,
snapping back at the next wait-boundary). It is **not** absolute clock drift: beats
at wait-boundaries match exactly; the variance opens *inside* a run and closes at
its edges. The split only manifests when host `delta ≠ 1/60` (uncapped >60 fps,
vsync off, or frame-time jitter) — a clean 60 fps vsync lock collapses it, which is
the falsification test (living doc Exp #2). Confirmed in the code, not
hypothetical: the three delta pumps and the quantized accumulator are all present
in `_advance_frame` / `Unit._process`.

See [SCENARIO6_RENDER_CLOCK_UNIFICATION.md](../SCENARIO6_RENDER_CLOCK_UNIFICATION.md)
for the full investigation, suspect ledger, and measurements.

## Considered options

- **Status quo — two clocks, "smooth" delta interpolation.** Keeps >60 fps-smooth
  slides but makes every scenario beat a function of wall-clock time, so
  beat-matching against PSX (and pace fidelity generally) drifts within every
  non-blocking run and can never be tight mid-run. Rejected — this is the friction
  the change exists to remove; smoothness beyond 60 Hz was never faithful, because
  PSX itself is vblank-quantized.

- **Frame-cap the host to 60 fps and keep the split.** A clean 60 fps vsync lock
  makes `delta*60 ≈ 1.0` every frame, so the residual is ~0 and the drift nearly
  vanishes — this is exactly why it's the falsification test. Rejected as the
  *fix*: it's a fragile external precondition (one frame spike, a background
  compositor, or a >60 Hz display reopens the gap) and it couples correctness to
  the user's monitor. The invariant we want is host-rate-*independence*, which only
  a quantized tick guarantees.

- **Invent a scenario-only fixed-step motion/anim clock.** A parallel accumulator
  just for scenario visuals. Rejected — `AnimationClock` **already** has a
  `tick_based` mode where `tick(delta)` no-ops and an external driver calls
  `advance_frame()` once per IRQ; combat uses it. Inventing a second mechanism
  duplicates the combat driver and re-opens the "which clock owns time" question
  ADR-0020 closed.

- **Unify motion/camera under the tick but leave the anim clock on delta.** Locks
  unit *position* to the event clock but not the *drawn pose* — the sprite frame
  (the primary beat-match oracle: "are they on the same frame") would still lead.
  Rejected: it fixes two of the three subsystems and leaves the one the user reads
  most. The anim clock is the trickiest but it is the point.

- **Unify all three on the VM tick, scenario-scoped (chosen).** Flip scenario
  units to `tick_based`, and pump `advance_frame()` + camera + motion at a fixed
  1/60 step once per tick via `_advance_tick_visuals` (driven from the
  `_advance_frame` accumulator loop, next to the untouched pure-dispatch
  `_tick_once`). One clock, PSX-vblank model, host-rate-independent. Combat and
  free-roam keep their existing drivers.

## Consequences

Scenario visuals advance in lockstep with opcode dispatch, so a beat is
reproducible from *tick count since the opening wait-boundary* regardless of host
frame rate — the precondition for tight, mechanical beat-matching against PSX.
`_advance_frame`'s three delta pumps fold into `_advance_tick_visuals` (driven
once per tick from the accumulator loop, `_tick_once` untouched); motion/camera/anim
no longer run once per `_process` but once per VM tick. `Unit._process`'s delta-mode
pump (`display.anim_clock.tick(delta)`) becomes a no-op for scenario units because
they are `tick_based`, and `ScenarioVM` calls `unit.advance_frame()` for them each
tick (the entry point already exists — see `Unit.gd` "drive this unit's animation
clock in tick mode").

Free-roam (non-scenario) units keep delta-mode smoothness; the flip is gated to
scenario entry/exit, so nothing outside the scenario player changes behavior.
Slides during scenario playback now step at 60 Hz rather than the host rate — on a
>60 fps display this is *less* visually smooth and *more* faithful; a debug-only
"smooth interpolation" escape hatch may be exposed through an F3 panel for
authoring/preview, never as the shipped default.

**Within-tick ordering** (does motion/anim advance before or after opcode dispatch
in the same tick?) is deliberately **left open** by this ADR and revisited after
the unify lands — the current order bakes a 1-frame motion lag, but its materiality
is expected to be swamped by the clock fix; pinning it against the PSX vblank
handler's event-vs-movement order is a follow-up RE item, not part of this
decision.

The invariant is guarded by **`ScenarioClockUnificationTest`**: driving the VM with
jittery / non-1/60 deltas must advance motion offset and anim frame-index **exactly
once per VM tick, identical to a clean-60 run** (host-rate-independent). This sits
alongside the existing pace guards (`ScenarioWaitCadenceTest`,
`ScenarioWaitRotateTest`) and prevents a future "re-add delta interpolation for
smoothness" from silently regressing pace fidelity.
