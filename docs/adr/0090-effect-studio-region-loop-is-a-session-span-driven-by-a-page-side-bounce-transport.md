# Effect Studio region loop is a session span driven by a page-side bounce transport

Status: accepted. Verified 2026-08-28 — decisions 1–4 all built, to the literal.

## Context

The Effect Studio could loop the whole score (a boolean toggle that seeks back to 0 at
the end) and scrub or park single frames, but you could not watch a parameter edit play
out **across a chosen region** in real time, and you could not play **backward**. The host
`EffectInstance` clock only advances forward (`studio_current_frame()` plus
`_advance_one_frame()`), and the page mirrored it: the whole-score loop was a boolean
`_loop_btn` that `_seek(0)`s at the end. The DAW plugin was
floated as a reference, but its `HostTransportState { ppq_position; looping }` is the
*host DAW's* transport that the VST merely reads — there is no region-loop or ping-pong
code to port. So this is new UX, borrowing only the DAW *concept*: loop in/out markers, a
loop toggle, ping-pong.

## Decision

**A session-scoped loop region, and playback driven from the page rather than the host
clock.**

1. **Loop region** — an inclusive `[start, end]` frame span held as ephemeral studio
   state: never written to `E###.BIN`, cleared on effect load. It is created by
   **Alt+left-drag** on the frames bar (plain left-drag still scrubs — ADR-0070), adjusted
   by edge handles or a body-drag, and cleared to fall back to the whole score
   (`EffectFramesBar`, gated on `event.alt_pressed`). A
   one-click "Loop life" snaps it to `[0, get_animation_display_length()]`. Frames are
   snapped and the minimum length is 2, so a click without a drag cannot make a
   zero-length region. Two snapped frames go to `LoopRegion.from_frames()`; `{}` is the
   no-region sentinel that `LoopRegion.is_empty()` reports, and `LoopRegion.effective()`
   resolves it to `0 .. stop_frame`. The region renders as a pure view — ruler shading
   plus a full-height lane band.

2. **Loop mode is Off / Forward / Ping-pong**, replacing the on/off toggle, cycled from
   the one `_loop_btn` (`_cycle_loop_mode()`). A region set means the region loops; no region means the whole
   score loops. There is one loop concept, and the region only changes *what* is looped —
   all three modes read the same `effective()` span.

3. **The page drives a pure bounce transport; the host is parked.** During Play
   `EffectStudioPage` owns a pure state machine `LoopTransport.step(start, end, mode, dir, cur)` (`MODE_OFF` / `MODE_FORWARD` /
   `MODE_PINGPONG` = 0 / 1 / 2) returning
   `{frame, dir, done}`, (`LoopTransport.gd`) and `studio_seek`s the host to the result once per accumulated frame, for
   *all* playback — there is no host-clock mirror and no second transport path. Turnaround
   is **reflect-without-repeat**: each endpoint is shown exactly once per pass (`end - 1`,
   `end`, `end - 1` …), because a repeated endpoint reads as a one-frame stutter.
   Direction resets forward on Play, and Play seeks to `start` if the playhead sits
   outside the region. Scrubbing and stepping stay unconstrained.

   The accumulator (`_transport_accum`) is `delta × TRANSPORT_HZ × _speed() × _pacing_factor_now()`, where
   `TRANSPORT_HZ` is 30 and the pacing factor is the effect's own authored Time Scale factor at the playhead
   (`EffectScoreModel.pacing_factor_at`, the curve ADR-0093 authors, mirroring the
   `_time_scale_factor` ADR-0014's timeline applies at runtime). The pacing term is not
   decoration: this decision's argument for collapsing to one transport path is that a
   seeked frame equals a free-run frame (ADR-0070), and a free-run frame is
   time-modulated, so a page tick that ignored pacing would advance at a different rate
   than the same effect playing normally — reintroducing exactly the class of bug the
   collapse removes. The accumulator drains in a bounded `while` loop of at most
   `MAX_STEPS_PER_FRAME` (4) steps per `_process`, and drops any residue rather than
   queuing catch-up, so a stall cannot dump a burst of expensive reverse steps.

4. **Speed is a continuous `0.1×–4×` scrub field on the page.** A `ScrubField` (`_speed_btn`) with
   step `0.05` and a `set_value_no_signal(1.0)` default, multiplying the page accumulator — not
   `studio_set_speed` on the host clock, which does not exist. The accumulator carries
   fractional frames, so any non-integer speed is frame-exact. The value is page state
   that persists across effect load, as loop mode does. A high maximum is harmless: on a
   heavy ping-pong reverse leg the accumulator caps at `MAX_STEPS_PER_FRAME` and degrades
   below real-time rather than breaking. `scrub_sensitivity` is plain widget config, not
   an ADR-0068 tunable.

## Considered options

- **Forward-only region loop, keeping the host free-running.** Cheaper — the existing
  seek-to-0 wrap would just target `start` — but reverse can never be retrofitted onto a
  forward-only host clock without rewriting the transport, and ping-pong is where the
  value is. Rejected: the rewrite would be paid later anyway.
- **Page-driven only when a region or ping-pong is active.** Two transport paths.
  Rejected for one uniform, testable path: a seeked frame equals a free-run frame by
  ADR-0070 (the scrub path proves it continuously), so collapsing to seeks removes a class
  of "works free-running, subtly wrong looping" bugs.
- **A second "region loop" control beside the whole-score Loop.** Rejected — two competing
  loop concepts. Whole-score is just "mode on, no region."
- **A coarse multi-step speed cycle button.** Rejected in favour of decision 4's
  continuous field: the ask was to control playback speed finely, and the transport needed
  no change to accept it.

## Consequences

- **Reverse is the one hard cost.** `EffectTimeline.seek` is asymmetric: a forward step is
  one frame advance (cheap, and identical to free-run), but a **backward** step `reset()`s and
  re-pumps from frame 0 to the target *and* re-arms the sound cast
  (`_restart_sound_cast`). Each reverse frame is
  therefore O(absolute frame index) — cost scales with the region's *end*, not its length.
  Two things follow:
  - **The ping-pong reverse leg is silent.** It takes a seek path that skips the sound
    re-arm (`studio_seek_silent`), because a sound cannot play backward and re-arming FEDS
    every backward frame would be audible garbage. Audio fires on forward legs only.
  - **Ping-pong on a long or late-in-timeline region may run below real-time**, O(end ×
    length) per reverse leg. Accepted as a known limitation of a dev authoring tool and
    validated headful. There is no frame snapshot or cache, and no recorded wall-clock
    bound — `MAX_STEPS_PER_FRAME` is what makes the degradation a stutter rather than a
    failure.
- The region and mode are **ephemeral session state**. The region clears on effect load (`_load_effect()`);
  the mode and speed persist across loads as page state, mirroring Ripple and Hide-inert.
  No writer, no manifest, no ADR-0087/0089 storage impact.

## Verification

The seam this ADR designed is the seam the tests split along: both pure classes are unit
tested in isolation, and the page behaviour is tested through the Studio.

| suite | covers |
|---|---|
| `tests/LoopRegionTest.gd` | decision 1's frame math in `LoopRegion.gd` |
| `tests/EffectFramesBarRegionTest.gd` | decision 1's Alt+left-drag gesture |
| `tests/EffectLoopRegionViewTest.gd` | decision 1's "rendered as a pure view" clause |
| `tests/LoopTransportTest.gd` | decision 3's state machine, in isolation — which is why `LoopTransport` owns no clock, host or speed |
| `tests/EffectStudioTransportTest.gd` | decision 3 at the page |
| `tests/EffectStudioRegionLoopAcceptanceTest.gd` | decisions 1–3 against the real host |
| `tests/EffectStudioSpeedFieldTest.gd` + `…AcceptanceTest.gd` | decision 4 |
| `tests/EffectScoreModelTest.gd` | `pacing_factor_at`, decision 3's pacing term |

Decision 2 has no dedicated arm; it is a three-way cycle over one button, reachable
through the acceptance test. The Consequence about running below real-time is the one
claim no suite can reach — it is a performance observation with no recorded numbers, and
this ADR accepts it as a limitation rather than asserting a bound.

## References

- [ADR-0014](0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md) — the
  timeline owns time modulation; decision 3's pacing term mirrors it
- [ADR-0070](0070-effect-replay-is-deterministic-within-an-instance-via-a-per-instance-seeded-rng.md) —
  a seeked frame equals a free-run frame, which is what lets decision 3 collapse to one path
- [ADR-0093](0093-time-scale-pacing-curves-are-freehand-painted-not-keyframed.md) — the
  authored Time Scale curve decision 3 reads
