# Scenario render-clock vs event-clock unification

**Living doc.** Owns one axis: the divergence between Godot's *event dispatch*
clock and its *render* (motion / camera / animation) clock during scenario
playback, and its elimination. The architectural decision this produces is
[ADR-0065](adr/0065-scenario-time-advances-on-one-vblank-quantized-tick.md).

Sibling scn6 docs (pose, facing, camera, coord fidelity — **not** re-derived here):
`../research/working_documents/SCENARIO6_PUNCH_PICKUP_THROW.md`,
`SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`, `SCENARIO6_RIDE_OFF_CHOCOBO.md`,
`SCENARIO6_CARRY_COMPOSITION_DEPTH.md`, `SCENARIO6_CHASE_WALK_TIMING.md`, and
`PSX_TO_GODOT_SPRITE_PIPELINE.md`.

Status: **confirmed + fixed.** Exp #2 falsified the two-clock split mechanically
(§4); the unify landed in `ScenarioVM` and is guarded by
`ScenarioClockUnificationTest`. ADR-0065 is Accepted. Remaining: the PSX
continuous trace-diff re-measure (§6) as outcome validation.

---

## 1. The symptom (what "beat matching" exposed)

Method: load `scenario6_letgo_full_base.sstate` in the pcsx-redux
scenario-event-debugger, pick a PC; double-click the same instruction in Godot's
scenario player; compare Delita's sprite side-by-side at that "frame."

Observed on the Delita/Ovelia carry:

| Godot PC | matching PSX PC | Godot lead |
|---------:|----------------:|-----------:|
| 155      | 155             | 0          |
| 160      | 160             | 0          |
| 163      | 164             | +1         |
| 164      | 166             | +2         |
| 168      | 174             | +6         |

Godot runs **visually ahead** of its own event PC relative to PSX, and the lead
**grows within the run**.

## 2. The reframe (what we are actually explaining)

The drift is **bounded and self-resetting, not cumulative from scenario start.**

- 155 and 160 match because they are **resync points** (wait-boundaries). The lead
  is zero there.
- Inside the non-blocking run that follows, the lead opens (1 → 2 → 6) and would
  **snap back to 0** at the next wait-boundary.
- So the quantity to reduce is **intra-run variance** — the spread that opens
  *between* two resync points — not a global clock offset.

Corollary: **PC is the wrong ruler inside a run.** A non-blocking run drains many
opcodes in (we expect) a single vsync, so "PC 163 vs 164" compares two points
inside the same drain; the visible frame is just whichever render the tool froze.
The correct intra-run axis is **frames-since-the-opening-wait-boundary**, which is
*clean inside a run* (no dialogue `Wait` there to inject an indeterminate number of
paints — that confound lives only across boundaries, where the run resyncs anyway).

## 3. Suspect ledger

1. **Two-clock split — PRIMARY.** Event dispatch is quantized to 60 Hz
   (`ScenarioVM._tick_once` via `_tick_accumulator`); motion (`_advance_motions`),
   camera (`camera_director.tick`), and the unit anim clock
   (`Unit._process → display.anim_clock.tick(delta)`, delta mode) run on **host
   render-delta**. The rendered sprite leads the event clock by the fractional-tick
   residual, proportional to motion integrated since the last resync → the exact
   symptom. PSX drives all of it off one vblank. See ADR-0065 "forcing bug."
   *Prediction:* the lead scales with host `delta` departure from 1/60 — a clean
   60 fps vsync lock should collapse it (Exp #2).
2. **SEQ per-frame duration parity — SECONDARY.** Our trace uses
   *phase = frames-since-anim-onset* as a proxy for the drawn frame; that proxy is
   only valid if Godot's SEQ per-frame durations match PSX's. If a residual
   survives the clock fix, a walk-cycle advancing at a slightly different per-frame
   cadence is the next suspect — caught by the spot recolor adjudication (§6), not
   the trace.
3. **Within-tick ordering — POST-FIX RE.** Does motion/anim advance before or after
   opcode dispatch in a tick? Current order (`_advance_motions` at ~1076 before
   `_tick_once` at ~1081) bakes a 1-frame motion lag. Re-evaluate *after* the unify;
   expected immaterial. Pin against the PSX vblank handler's event-vs-movement order
   (Ghidra / Hacktics) only if a residual points here.

## 4. Experiment log

### Exp #1 — PSX per-vsync dispatch granularity  *(status: TODO)*
Cool exec BP on the run's opcodes; log `(vsync_count, main_pc)` across one pass.
Godot side: the equivalent `_vm_tick → main_pc` trace (`tools/record_carry_timeline.gd`).
**Hypothesis:** both drain the whole non-blocking run within one vsync → confirms
PC has no frame-meaning mid-run and we match on frames-since-boundary instead.
Watch BP hotness (see the pcsx-agent BP gotchas note — keep BPs cool).
**Result:** _pending._

### Exp #2 — vsync-lock falsification  *(status: DONE 2026-07-08 — CONFIRMED)*
Rather than the noisy manual PSX eyeball (lock the display to 60 fps and re-run
the beat-match by hand), the falsification was **mechanized** as
`ScenarioClockUnificationTest`: drive `ScenarioVM._advance_frame` with a
deterministic *jittery* delta stream (per-frame deltas that are never 1/60 —
some fire zero ticks, some fire two) and compare the render state to a clean-60
stream **at equal VM-tick counts**. This isolates the exact thing a vsync lock
tests (does `delta ≠ 1/60` open a gap?) without the pcsx rig, and turns the
answer into a permanent guard.

- **Result (two-clock code): RED.** Worst-case `|motion.elapsed_s − vm_tick/60|`
  under jitter = **0.016667 s = exactly one 60 Hz tick** — the fractional-tick
  residual the ADR predicts. Clean-60 and jitter streams disagreed on the motion
  offset at equal ticks by the same one tick. The anim clock was never
  VM-driven (0 calls). ⇒ **two-clock split confirmed as the mechanism**, and it
  is host-rate-dependent (collapses at clean 60, opens under jitter) — exactly
  Exp #2's "drift collapses under vsync lock" prediction.
- **Result (after the unify): GREEN, 5/0.** Motion offset is now a pure function
  of tick count (`elapsed_s == vm_tick/60` to 1e-5) on *both* streams; the anim
  clock advances exactly once per tick; scenario units flip to `tick_based` on
  entry.

Since the symptom signature (bounded, self-resetting, snaps to 0 at
wait-boundaries) already excludes suspect #2 (SEQ durations — those would
accumulate, not self-reset), no fall-through to #2/#3 was needed. Suspect #2
remains the thing to check if the PSX re-measure (§6) shows a residual *after*
this fix.

## 5. The fix (IMPLEMENTED 2026-07-08)

Unify all three subsystems at a fixed 1/60 step, **scenario-scoped**. Landed in
`ScenarioVM`:

- **Flip on entry.** `start()` sets `tick_based = true` on every unit in
  `units_by_id` (ghost units flip on first sight in `_advance_scenario_anim`).
  `Unit._process`'s `anim_clock.tick(delta)` then no-ops (ADR-0025's existing
  `tick_based` mode); `_advance_scenario_anim` calls `unit.advance_frame()` once
  per tick — the entry point already existed (`Unit.gd` "drive this unit's
  animation clock in tick mode"). Scenario-scoped by construction: units are
  spawned fresh per scenario and freed on exit, so the flip never leaks into
  combat / free-roam.
- **One tick, one step.** A new `_advance_tick_visuals()` advances the anim
  clock, camera (`camera_director.tick(_TICK_DT)`), and motion
  (`_advance_motions(_TICK_DT)`) at a fixed `_TICK_DT = 1/60`, driven from the
  `_advance_frame` accumulator loop **alongside** `_tick_once` — one visuals step
  then one dispatch step per tick. Crucially `_tick_once` **stays pure dispatch**
  (tests and debug tooling drive it directly to step dispatch *without* moving
  the camera/slides — e.g. `ScenarioWaitForInstructionTest` sets camera state by
  hand and asserts a barrier holds), so the visuals live in the sibling, not in
  `_tick_once`.
- **Pause / halt / fast-play semantics preserved.** Anim is ungated by `paused`
  (per-unit body clocks animated during a park before, via `Unit._process`);
  camera + motion are `paused`-gated (a debug park is a true freeze-frame — no
  slide past the parked PC). Both run during a halt (`_running` false) and during
  fast-play (`paused` false), matching the old `_advance_frame` placement.

Reuses the combat `CombatLoop` tick-driver mechanism — no new clock invented.
Combat and free-roam are untouched. See ADR-0065 for the decision + rejected
options.

## 6. Done criterion (two-tier)

**Continuous (acceptance) — mechanical trace-diff.** Across every run spanning
beats ~155–231, both engines agree each vsync on: `anim_id` (unit `+0x1DC`),
`frames-since-onset` (±1), `octant`, and `offset triple` (`+0x60/62/64`, sub-tile).
Camera-**independent** — compares game state, not pixels, so it sidesteps the
camera-framing confound flagged as the residual gap in the carry docs. This is the
pass/fail the clock-unify must clear.

**Spot (final adjudication) — recolor superimpose.** At the 2–3 money beats (the
lift; the shoulder-carry settle), recolor Delita all-green / Ovelia all-magenta and
superimpose PSX-framebuffer vs Godot-render to confirm the **actual drawn sprite
frame** matches. This is what catches a SEQ-duration mismatch the frames-since-onset
proxy would hide. **Demoted and deferred:** it is not the thing we optimize against
(pixel compare re-imports the PAR/cam.size/OFX-OFY projection confounds); built only
after clock-unify, run at a handful of beats as the closing proof.
- Rig-only knob: `unit_forward` **.1 → .13** keeps Ovelia's outline off the wall so
  the superimpose is readable. **F3-gated, never shipped as gameplay** (it perturbs
  depth/projection — the very confound the carry docs isolate).

## 7. Regression guard

**`ScenarioClockUnificationTest`** — drive the VM with jittery / non-1/60 deltas and
assert motion offset + anim frame-index advance **exactly once per VM tick,
identical to a clean-60 run** (host-rate-independent). Sits with
`ScenarioWaitCadenceTest` / `ScenarioWaitRotateTest`; blocks a future "re-add delta
interpolation for smoothness" from silently regressing pace.

## 8. Open items / next actions

- [x] Exp #2 (vsync-lock falsification) — DONE 2026-07-08, mechanized as
      `ScenarioClockUnificationTest`; two-clock split confirmed (§4).
- [x] Implement the unify (§5) behind the scenario-scoped `tick_based` flip.
- [x] Land `ScenarioClockUnificationTest` (§7) — 5/0 GREEN; wired into
      `run_all_tests.sh`.
- [ ] Exp #1 (PSX dispatch granularity) — confirm drain-all on both engines
      (now lower priority; the mechanized Exp #2 already settled the mechanism).
- [ ] Re-run continuous trace bar (§6) across 155–231 against PSX; record
      residual (outcome validation — needs the pcsx rig + headful).
- [ ] Recolor spot-adjudication at the money beats; if it fails while trace is
      green → open suspect #2 (SEQ per-frame duration parity).
- [ ] Post-fix: re-evaluate within-tick ordering (§3.3) against the measured
      residual.
