# The render clock is not the tick clock: interpolate the remainder, BEHIND and never ahead

## Status

Accepted (2026-09-11)

Constrains ADR-0239 (which owns `playback_scale` and the turn gate's mid-drain
break) and ADR-0018 (the presentation seam). Neither is superseded: the
accumulator's behaviour is untouched and this ADR only adds a **read** of it.

## The question this answers

> *"The whole game jitters - include unit walking animations - so it isn't the
> camera specifically. its an overall performance issue"*

It is not a performance issue, and the second half of that sentence is the part
that matters: it is not the camera, it is **everything**, because the defect is
in the clock every visual hangs off. PR #1196 fixed a frame-counted camera ease
sampled against a variable clock — a real instance of this disease, and one
symptom of it. This is the cause.

## Context: the sim ticks at 60 Hz and the display does not

`CombatLoop.tick()` runs a textbook fixed-timestep accumulator:

```gdscript
const TICK_INTERVAL: float = 1.0 / 60.0
_tick_accumulator += capped_delta * playback_scale
while _tick_accumulator >= TICK_INTERVAL:
    _tick_accumulator -= TICK_INTERVAL
    gpu_simulator.step_tick(1)
    current_tick += 1
```

Everything the player sees hung off that **integer** tick.
`update_visual_positions` runs after the drain, once per FRAME — and then
recomputed from `timer: int`, so it returned the same answer for every frame
inside one tick. `GPUMovementVisualizer.calculate_position(timer: int)` and
`_resolve_leg(timer: int)` derived `elapsed := total - timer` in integers all the
way down before lerping.

So a rendered frame that banked less than one tick redrew every walking unit at a
**bit-identical** position, and the next frame stepped twice as far.

🔴 **THE REMAINDER WAS ALREADY BEING KEPT — it was only the renderer that could
not see it.** `_tick_accumulator` survives across frames by design: `tick()`'s own
comment records that the ADR-0239 turn gate "breaks out mid-drain and KEEPS the
accumulator remainder on purpose". The information needed to draw between two
ticks was sitting in the loop the whole time.

## The severity is set by the monitor, and it is not a small number

This is the fact that reframes the bug from "an occasional beat" to "constant":

| refresh | ms/frame | ticks/frame | frames draining **zero** ticks |
|---|---|---|---|
| 60 Hz | 16.67 | 1.000 | ~4 % |
| **144 Hz** (`DP-1`, Dell S2417DG) | 6.944 | **0.4167** | **58.3 %** |

At the box's real refresh rate, seven of every twelve rendered frames advanced
nothing — a permanent 60 Hz strobe under a 144 Hz presentation, on every unit and
every animation, forever. That is why it was reported as *the whole game* rather
than as a movement bug.

⚠️ **AND IT GETS WORSE AS THE GAME GETS FASTER.** Cheaper frames raise the share
that bank less than a tick. Any session that reads this as a cost problem and
optimises will measure the judder increasing and conclude its optimisation
failed.

## Decisions

### 1. `CombatLoop.tick_alpha` is the remainder as a share of one tick, and it is a READ

Refreshed once per FRAME at the visual seam, immediately before
`update_visual_positions`:

```gdscript
tick_alpha = clampf(_tick_accumulator / TICK_INTERVAL, 0.0, 1.0)
```

**Never a write, never a reset.** A post-loop "throw the excess away" would
silently destroy ADR-0239's seamless resume — the accumulator's own comment says
so. `tick_alpha` is a *view* of the accumulator, not a second copy.

**Clamped rather than assumed in range**, because the turn gate can break out
mid-drain and leave more than a whole tick banked; an alpha above 1 would run a
unit past the tick the sim is on, which is exactly what dec. 2 forbids.

`playback_scale` already multiplied the delta going IN (ADR-0239), so the
fraction is in the same scaled time the visuals want. The `victory_achieved`
branch has its own drain, deliberately in REAL time, and does not reach here.

### 2. INTERPOLATE BEHIND. Do not extrapolate ahead

`GPUVisualBridge._render_timer(timer, alpha) -> float(timer) + (1.0 - alpha)`.

`timer` counts DOWN, so carrying the render *back* means ADDING `1 - alpha`. The
property that makes it work is a cancellation: at alpha 0 it resolves to the
previous tick's value, slides continuously onto the current one as alpha
approaches 1, and at that moment the next tick fires and alpha resets — the two
changes cancel exactly. **That is why the result is continuous across the tick
boundary rather than merely finer-grained**, and it is what dec. 4 arm 1 asserts.

It costs one tick — ~16.7 ms — of latency on rendered movement. That is the
price, and it is worth it: the GPU sim is authoritative, `vis_states` is the
CURRENT tick, and sampling at `timer - alpha` would draw a unit where the sim has
not yet put it.

**The usual argument for this is OVERSHOOT, and that argument is weaker here than
it looks — it is not the reason.** Every path in `calculate_position` /
`_resolve_leg` already clamps to the move's own span, so a forward-sampled unit
could not have overshot its destination tile; and at `NEW_STEP` the visualizer
already knows `start_pos`, `end_pos` and `total_ticks`, so a fractional sample
ahead would be *evaluating a committed trajectory*, not predicting one. The real
reason is narrower and survives that: **a step can be cancelled mid-flight**
(`dbg_conflict_blocked`, and the retry/wait path), and ahead-sampling would have
drawn up to one tick of travel the unit never made. Behind can never draw a
position the simulation did not authorise. Recorded this way so a later session
grilling "but it clamps, so why not ahead?" finds the question already answered
rather than re-deriving it.

### 3. The timer becomes a FLOAT at the leaf, and every caller keeps working

`calculate_position`, `get_activity` and `_resolve_leg` take `timer: float`.
`get_activity` takes the *same* fractional timer as `calculate_position` so the
POSE a frame draws belongs to the POSITION it draws; the phase boundary simply
lands on whichever side of the sub-tick it falls.

`MovementLeg` **is** `GPUMovementVisualizer` (`const MovementLeg = preload(<self>)`),
so one signature change covers both levels of a pass-through.

`update_visual_positions(..., tick_alpha: float = 0.0)` defaults the parameter, so
every caller that has no accumulator — every test driving the bridge directly —
keeps the exact per-tick behaviour it asserts.

### 4. The guard goes in `GPUVisualBridgeInterpolationTest`, not in a new scene

The charter prices a test in **processes**, and that scene already boots the
seeded battle these arms need. Three arms, all deterministic:

1. `_render_timer` is CONTINUOUS across the tick boundary — alpha 1 at timer *t*
   must land exactly where alpha 0 at timer *t−1* lands.
2. `_render_timer` interpolates BEHIND — it never returns a timer below the sim's
   own, and never lags more than one tick. **Dec. 2 is mechanised, not merely
   written down.**
3. A live visualizer asked for the same move at two points INSIDE one tick must
   answer differently.

Arms 1–3 hold the sim STILL and move only the render clock, so they say the same
thing under suite load as they do idle.

**The run's real zero-tick frames are PRINTED as diagnosis and never gate PASS.**
At ~60 fps against a 60 Hz tick only ~4 % of frames bank none, and under suite
load fewer still; gating on them would be a flake whose failure mode is "the box
was busy".

### 5. Arm 3 samples only the plain adjacent walk, and that is not a dodge

A cliff move's JUMPING phase holds `start_pos` and its LANDING phase holds
`end_pos` — those plateaus are **still by design**, and `_scale_phase`'s own
comment records budgets where one phase swallows the whole move. A pass-through's
legs inherit the same shapes. Measured: an indiscriminate sampler found 3998 of
4359 samples moving, and all 361 others were legitimate plateaus.

So arm 3 asks the one shape with no licence to stand still — `_legs` empty and
not a cliff, i.e. `calculate_position` reduced to a pure lerp between two
distinct points — and demands **every** such sample respond (1655/1655). The
plateaued shapes are counted and printed, never gated.

### 6. `AnimationClock.advance_frame()` is deliberately NOT touched

`advance_frame()` is used whenever `owner != SELF`, i.e. every unit in COMBAT and
every unit in a SCENARIO, and it has the same integer-tick shape. FFT sprite
frames are authored at a discrete cadence and are **meant** to step, not to be
blended; their timing wobbles by one tick, which is far less visible than a
position freeze. Position was the dominant symptom. Re-measure before deciding
whether animation stepping needs its own answer — this ADR does not decide it.

## Evidence

`tools/probe_tick_jitter.gd` (new) drives Gariland into live combat and splits
in-motion unit-frames by whether a tick drained. It scores SHAPE, not wall clock.

| arm | before | after |
|---|---|---|
| **zero-tick frames** duplicate | **66/66 — 100.0 %** | **5/60 — 8.3 %** |
| ticked frames duplicate | 227/1552 — 14.6 % | 230/1598 — 14.4 % |

The arms now **agree**: whether a tick drained no longer decides whether a unit
redraws. The residual ~14 % present in BOTH arms is dec. 5's plateaus.
`ALPHA: min 0.003 mean 0.510 max 0.997` — the remainder was fully populated, so
the discarded information was real.

⚠️ The probe's own window runs at ~63 Hz (Hyprland's `render_unfocused`), so only
~4 % of ITS frames bank zero ticks. **The probe establishes the CORRELATION; the
refresh-rate table above establishes the SEVERITY.** Neither substitutes for the
other, and a session that runs the probe and reads 4 % as the impact has read the
wrong number.

## Proved by mutation, in three directions

| seed | breaks | caught by |
|---|---|---|
| A — `_render_timer` returns `float(timer)` | alpha never reaches the visualizer | arm 1, 4 failures |
| B — `calculate_position` does `floorf(timer)` | visualizer ignores the fraction | arm 3, 0/1653 |
| C — `_render_timer` returns `timer - alpha` | extrapolates ahead (dec. 2) | arm 2, 16 failures |

🔴 **B WAS NOT CAUGHT ON THE FIRST ATTEMPT, AND THAT IS THE MOST USEFUL LINE IN
THIS DOCUMENT.** Arm 3 originally sampled `mid` and `mid - 0.5`, which STRADDLE an
integer: `floorf(8.0)` and `floorf(7.5)` are 8 and 7, so a fully re-quantised
visualizer still answered them differently and the arm passed **1644 of 1644**
while the same run's diagnosis line read *"movers redrew 0 of 240 (0.0 %)"*
directly beside it. The arm was asserting "a half-tick change moves the unit",
which integer truncation satisfies. It now samples `floor(mid)+0.25` and `+0.75`
— both inside ONE tick — which only a fractional timer can answer.

Seed A also serves as a positive control on the diagnosis itself: with it armed,
the run's real zero-tick frames went to **0 of 191 redrawn**, reproducing the
original defect end-to-end.

## Rejected alternatives

- **Extrapolate ahead** (`timer - alpha`) — dec. 2. Zero added latency and
  continuous at both boundaries, and the clamps make overshoot structurally
  impossible; rejected on the cancelled-step case and on "never draw a position
  the sim did not authorise", not on the overshoot argument usually cited.
- **Double-buffer the previous tick's state and lerp between snapshots** — the
  textbook shape. Unnecessary here: position is an ANALYTIC function of the
  timer, not an opaque state blob, so evaluating at a fractional timer *is* the
  interpolation. A second snapshot would add a per-frame copy of every unit's
  visual state to buy nothing.
- **Raise the tick rate to match the display** — changes every timing constant in
  the GPU sim, breaks ROM parity (FFT ticks at a fixed rate), and only moves the
  beat rather than removing it: no integer tick rate is phase-locked to an
  arbitrary refresh.
- **Make frames cheaper** — the reading the symptom invites, and it is
  backwards; see the warning above.
- **Reset or drain `_tick_accumulator` after the loop** — destroys ADR-0239's
  mid-drain resume, which the accumulator's own comment already forbids.
- **A new test scene for the sub-tick arms** — dec. 4. A ~2.3 s Godot boot,
  forever, for assertions that share an existing fixture's setup.
- **Gating PASS on the run's observed zero-tick frames** — dec. 4. The end-to-end
  quantity, but its sample size is set by the box's load.

## Soft spots

- **S1** `AnimationClock.advance_frame()` still steps on the integer tick
  (dec. 6). Animation timing wobbles by one tick; deliberately deferred, not
  fixed.
- **S2** The 144 Hz severity number is ARITHMETIC from the panel's mode, not a
  measurement taken on that panel. The correlation is measured; the share is
  derived. A run on a real 144 Hz presentation would close this.
- **S3** Arm 3 has no positive control for the cliff/pass-through branch — those
  samples are skipped by construction (dec. 5), so a regression confined to the
  legged path would not redden it. `GPUPassthroughLegTest` and
  `GPUBridgeDescentTest` cover the shapes, but on integer timers.
- **S4** The one-tick latency dec. 2 buys is asserted as a BOUND (arm 2), never
  measured as a perception. Nobody has reported it; nobody has looked for it
  either.
