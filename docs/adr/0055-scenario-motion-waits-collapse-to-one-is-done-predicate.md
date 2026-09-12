# Scenario motion is one self-ticking predicate, not per-type wait dicts

## Status

Accepted (2026-07-02)

Scripted unit motion — Sprite Move (`{3B}`/`{6E}`) and Walk To (`{28}`) — becomes
a pure, scene-free [ScenarioMotion](../context/09-event-script-interpreter.md)
value object (`start`/`target`/`dur_s`/`elapsed_s`/`easing`/`weight` +
`advance`/`is_done`/`snap_to_end`/`position`) in a VM-owned
`motions:{uid → ScenarioMotion}` registry. Every motion **wait barrier** — the
`{6F}` Wait Sprite Move, `{29}` Wait Walk, **and** the `{64}`/`{65}` Wait Rotate
predicates — collapses to one question, `_arm_wait_until(ctx, () → motion_done(uid))`,
where `motion_done` reads the registry and falls back to the Unit-owned rotate
stepper. Rotate stays on the Unit; the effect timers stay separate.

## Decision

Numbered 2026-08-28 so `ADR-0055 dec. N` resolves. Items 1–6 restate the rules
the paragraph above already carries; item 7 is lifted from **Consequences**
because it is a design choice a citation needs to be able to address. No prose
was removed or reworded.

1. **Motion is a pure, scene-free value object.** `ScenarioMotion` holds
   `start`/`target`/`dur_s`/`elapsed_s`/`easing`/`weight` and answers
   `advance`/`is_done`/`snap_to_end`/`position` — testable with no scene boot.
2. **The motion holds no node reference.** It lives in a VM-owned
   `motions:{uid → ScenarioMotion}` registry; the node is resolved via
   `units_by_id` at **apply**, where the `global_position` write happens.
3. **Every motion wait barrier collapses to one question.** `{6F}` Wait Sprite
   Move, `{29}` Wait Walk and the `{64}`/`{65}` Wait Rotate predicates all become
   `_arm_wait_until(ctx, () → motion_done(uid))`.
4. **`motion_done` is that question.** It reads the registry and falls back to
   the Unit-owned rotate stepper for a uid with no registered motion.
5. **Rotate stays on the Unit.** It is a 16-direction notch stepper, not a
   positional lerp; its per-vsync consumer mirrors PSX `FUN_8013f20c` over all 21
   handles and its output drives `facing_direction`.
6. **The effect timers stay separate.** They are not migrated, and may adopt the
   same contract later only if the halt-gate axis is modeled as an explicit
   property of the task — never by folding them into this registry.
7. **Sprite Move and Walk To are one class** (Walk constructs with `easing = 0`,
   the linear curve branch); their real differences stay in the `_op_*` apply
   handlers, not in the motion.

## Considered options

- **Status quo — three ad-hoc motion dicts + four wait flavors.** `_sprite_moves`,
  `_walks`, and the Unit's `_rotate_state` are three untyped record shapes, each with
  its own advance loop, restart-clear, and bespoke Wait opcode (tick-countdown ×2,
  predicate ×2). Adding a motion type meant a new dict + advance loop + clear + Wait.
  Knowledge of one motion was smeared across ~5 sites; nothing could answer "is this
  unit's motion done?" Rejected — this is the friction the change exists to remove.

- **One `ScenarioMotion` covering all three, Rotate included.** Fold the notch-stepper
  into a `RotateMotion` subclass in the same registry. Rejected: Rotate is not a
  positional lerp — it is a 16-direction notch stepper whose per-vsync consumer
  (`_tick_unit_rotations`) deliberately mirrors PSX `FUN_8013f20c` looping all 21 unit
  handles, and whose output drives the Unit's `facing_direction` (sprite-quadrant
  render). Moving it off the Unit fights that all-handles consumer and the facing
  coupling for no representational win — the largest blast radius of the options.

- **A shared self-ticking-task base across motions AND the effect timers now.**
  `ScenarioColorTint`/`ScenarioBgSound`/`ScenarioDarkScreen`/`ScenarioWeather`/
  `CinematicWalkState` already independently approximate `advance`/`tick` + a done
  signal, so one base looks tempting. Rejected **now** on a hard semantic fault line:
  the effect timers tick **outside** the `_running` halt gate (a tint or BG-sound ramp
  armed right before a `{10}` Display Message wall must still converge while opcode
  dispatch is parked), whereas motions tick **inside** the gate and exist precisely to
  **gate script contexts**. Forcing both under one pump conflates "runs during halt"
  with "blocks a context" — reopening the effect-Subsystem / No-clock-invariant seams
  (ADR-0011/0012/0014) the review was told to leave settled.

- **Motion-only `ScenarioMotion` + `motion_done` predicate (chosen).** A pure
  Sprite+Walk motion class in a VM registry; the node resolved via `units_by_id` at
  apply so the motion holds no node ref (the [decode/apply
  seam](../context/09-event-script-interpreter.md) again — `position()` is pure, the
  `global_position` write is apply). Rotate keeps its Unit home and answers the *same*
  `motion_done(uid)`, so every wait unifies without moving the rotate stepper. The
  latent self-ticking-task shape is *named* for a future review, not built.

## Consequences

The contract surface is just `advance`/`is_done`/`snap_to_end`/`position`, so motion
joins [PsxNum](../context/09-event-script-interpreter.md) /
[ScenarioDecode](../context/09-event-script-interpreter.md) as pure RE logic testable
with **no scene boot** (`ScenarioMotionTest`) — previously motion was reachable only
through a full-scene 60 Hz boot. Sprite Move and Walk To are **one class** (Walk
constructs with `easing = 0`, the linear curve branch); their real differences —
facing via `heading_facing_dir`, the movement-walk anim, the event pathfinder, the
tile-home reset — stay in the `_op_*` **apply** handlers, not the motion.

Two behavior notes a reader would otherwise trip on: (1) the predicate wait inherits
the `_arm_wait_until` **600-tick (10 s) watchdog**, which the countdown waits did not
have, so the wait passes a **duration-derived** watchdog budget to avoid clipping a
legitimately long motion. (2) The unified burn-through drain
(`_drain_motions_to_target`) now snaps **Sprite Move** too — previously only Walk and
Rotate were drained, so the chapel-trace sampled slides mid-flight; snapping all
motions matches the end-of-slide state PSX renders after the cinematic Wait, and is
blessed by the `ScenarioChapelChain*Test` + choreography parity nets.

The effect timers are **not** migrated. They may adopt the same
`advance`/`is_done`/`snap_to_end` contract in a later, separate change — but only if
the halt-gate axis is modeled as an explicit property of the task, never by folding
them into this motion registry.

## Amendment (2026-08-28) — the predicate held and outgrew its own scope; the "one class" consequence was reversed without an ADR, and the halt-gate fault line the rejection rests on has since collapsed

*Audited 2026-08-28 against `src/scenarios/`, `src/units/` and `tests/`.
Decision items numbered the same day.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | pure scene-free value object, six fields + four methods | **yes, exactly** | `ScenarioMotion.gd` carries those six fields and those four methods and nothing else but `frac`/`curve`; `ScenarioMotionTest` boots no scene |
| 2 | no node ref; VM-owned `motions:{uid → ScenarioMotion}` | **rule yes, registry MOVED** | still no node ref, but the registry is now `actors[uid].motion` — ADR-0064 folded it into `ScenarioActor` |
| 3 | `{6F}`/`{29}`/`{64}`/`{65}` all collapse to `motion_done(uid)` | **three of four** | `{6F}`, `{29}`, `{64}` each call `_arm_motion_wait`; `{65}` does not — see below |
| 4 | `motion_done` reads the registry, falls back to rotate | **yes** | `ScenarioVM.motion_done:3410` → `_actor_motion_live` else `_rotate_done` |
| 5 | rotate stays on the Unit | **yes** | `Unit._rotate_state` at `:315`, still the only owner; `_sprite_moves`/`_walks` have **zero** occurrences |
| 6 | effect timers not migrated | **yes, a live deferral** | none of `ScenarioColorTint`/`ScenarioBgSound`/`ScenarioDarkScreen`/`ScenarioWeather` has an `advance`/`is_done`/`snap_to_end` |
| 7 | Sprite Move and Walk To are **one class** | **NO — reversed** | `ScenarioPathMotion` is a second class, and no ADR records the split |

### Dec. 7 was reversed, and nothing in the corpus says so

`ScenarioPathMotion.gd` exists and is explicitly "a SIBLING of `ScenarioMotion`,
**NOT a subclass**". Its reason is good and is a fact about the ROM, not about
our code: Sprite Move (`FUN_80146940`) is a single straight `+0x60`-offset lerp,
while Walk To (`FUN_8006af7c`) walks the BFS route tile-by-tile with a **per-tile
gravity arc** (`DAT_80096128 = 0x925` per frame) and re-projects velocity onto
each route step's cardinal direction. A linear lerp with `easing = 0` cannot
express that, so this ADR's "Walk constructs with `easing = 0`" was a claim about
a stepper we had not yet traced.

What is missing is the record. `ScenarioPathMotion` appears in **no ADR and no
`docs/context/` file** — it cites *this* ADR as its authority while contradicting
this ADR's stated consequence. A reader arriving at dec. 7 today is told
something false by the only document that speaks.

**The contract, though, survived the split intact** — and that is the part worth
keeping. `ScenarioPathMotion` answers the same `advance`/`position`/`is_done`/
`snap_to_end`, carries its own `dur_s`, holds no node ref, and is scene-free
(`ScenarioPathMotionTest`). Both `_advance_motions:3450` and
`_drain_motions_to_target:3781` read `a.motion` **duck-typed**, commenting
"`ScenarioMotion` (slide) or `ScenarioPathMotion` (walk)". So dec. 1's contract
absorbed a second implementation without a single call-site change — the
strongest evidence for this ADR that the audit found, delivered by the decision
it broke.

### `{65}` asks a different question — and the source says so twice, differently

`{65}` Wait Rotate All does **not** go through `_arm_motion_wait`. It arms
`_arm_wait_until(ctx, _all_rotations_done)`, a loop of `_rotate_done` over every
deployed unit, which never consults the motion registry. It could not use
`motion_done(uid)`: `{65}` has no uid (PSX passes `a0 = -1`, looping all 21
handles). That is faithful — `{65}` is Wait Rotate *All*, rotation only — so the
behaviour is right and this ADR's sentence is what overstates.

The source is already ambivalent about it in two adjacent docstrings:
`motion_done` (`:3404`) lists "`{6F}`/`{29}`/`{64}`/`{65}`", while
`_arm_motion_wait` seventeen lines later (`:3420`) lists only "`{6F}`, `{29}`, and
`{64}`". The second one is the accurate one. The collapse that genuinely
happened is three barriers into one, plus a fourth that shares the outer
`_arm_wait_until` predicate form but not the predicate.

### The predicate outgrew the four wait opcodes

A consumer this ADR did not foresee now reads the same primitive: the
unit-filter-**free** `{E5}` Task=11 kind-`0x0B` liveness check
(`_task_liveness[TASK_SPRITEMOVE]`) folds over every actor calling
`_actor_motion_live` — the same function `motion_done` calls. Its docstring
records why: "the split-model bug that let scn6's carry-down race ahead of its
per-step barriers". So a second liveness *view* was pulled onto the same
primitive after this ADR, for exactly the reason this ADR gives for having one.

### Both behaviour notes hold, and one is guarded to the number

The duration-derived watchdog is real and pinned: `_motion_watchdog:3437` returns
`maxi(600, ceil(dur_s·60) + 60)` for a registered motion and the bare 600-tick
default otherwise, and `ScenarioSpriteMoveTest._test_motion_watchdog_is_duration_derived`
asserts **both** arms (`== 600` with no motion, `> 600` for a 20 s motion). The
unified drain also holds: `_drain_motions_to_target` iterates **all** actors and
snaps whatever `a.motion` is, so Sprite Move is drained alongside Walk. Note
`{65}` passes no watchdog and so inherits the plain 600-tick default — consistent
with note (1), which is about motions with a duration.

### The fault line the option-3 rejection stands on has collapsed

This is the finding with the longest reach. The shared-task-base option was
rejected "on a hard semantic fault line: the effect timers tick **outside** the
`_running` halt gate … whereas motions tick **inside** the gate".

That is no longer true, and it stopped being true in this repo's own work.
ADR-0065 hoisted motion onto a fixed 1/60 render-clock tick: motions now advance
in `_advance_tick_visuals` (`:1392`), called from `_advance_frame` **before**
`_tick_once`, whose own docstring states "Both run during a halt (`_running`
false) — matching the old placement outside the tick loop". The effect ramps
advance at the top of `_tick_once` (`:1587`), also before its halt return, under
`if not paused`. Measured, the two now share **identical** gating: both outside
`_running`, both frozen by `paused`. The `_running` axis no longer separates
them at all — the separator is `paused`, which freezes camera + motion + every
effect ramp together and deliberately not the anim clock.

ADR-0065 never mentions the halt gate, `_running`, `paused`, or ADR-0055.

The rejection's *other* leg is untouched: motions "exist precisely to gate script
contexts" and effect ramps block nothing. That distinction is as sharp as it ever
was — `motion_done` gates a context; no tint does. So the conclusion very
probably still stands. But two later ADRs lean on the collapsed leg by name —
ADR-0058 ("the halt gate (ADR-0055's fault line)") and ADR-0064 ("it reopens the
ADR-0055 halt-gate fault line and is a separate axis") — and a reader who checks
that citation against the code today will find the premise false.

### Recorded question — does the option-3 rejection still hold on one leg?

Two readings, and this audit does not choose:

- **(a) It holds; only the wording is stale.** The load-bearing distinction was
  always "blocks a script context" vs "does not", and "runs during halt" was an
  illustration of it that ADR-0065 happened to invalidate. Under this reading the
  fix is one sentence here plus a pointer from ADR-0065, and ADR-0058/0064's
  citations keep their meaning.
- **(b) The rejection is now unevidenced and must be re-argued.** The ADR calls
  it a *hard semantic fault line* and cites the gate as the thing that makes it
  hard; with both classes of task on identical gating, "conflates runs-during-halt
  with blocks-a-context" no longer describes a conflation the code would suffer.
  Under this reading the shared self-ticking-task base is open again and should
  be re-decided on its merits rather than declined by citation.

### On mechanizing this ADR

Dec. 1 and dec. 4 are already covered (`ScenarioMotionTest`,
`ScenarioPathMotionTest`, `ScenarioSpriteMoveTest`). Three arms are absent and
each is cheap:

- **Dec. 5 as a negative:** assert `_sprite_moves` / `_walks` have zero
  occurrences in `src/` and `_rotate_state` occurs only in `src/units/Unit.gd` —
  the "rotate stays on the Unit, the other two dicts are gone" invariant, which
  is exactly the shape a later refactor would silently undo.
- **Dec. 6 as a negative:** assert no `ScenarioColorTint`/`ScenarioBgSound`/
  `ScenarioDarkScreen`/`ScenarioWeather` declares `advance`/`is_done`/
  `snap_to_end`. That is the *entire* content of "not migrated", and it would
  fire the day someone folds them in without modelling the halt-gate axis.
- **Dec. 1 as a contract, across implementations:** assert that every class
  stored in `ScenarioActor.motion` answers all four methods. Today that is two
  classes reached only by duck typing; the guard is what makes a third safe.

Dec. 3 is the one arm **not** worth mechanizing as written, because the ADR's
own text is what would have to be asserted, and `{65}` refutes it.
