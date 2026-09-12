# The turn meter is a GPU unit field, and it is not called CT

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §3 opens "**CT is a GPU unit
field**, advanced `CT += Speed` per tick by the shader". The mechanism is right
and this file builds it. The *name* cannot be taken, because this kernel already
spends `CT` on a different quantity.

FFT calls two unrelated things CT: a unit's turn counter, and an ability's charge
time. The reimplementation inherited the second one everywhere —
`AB_CHARGE_TIME`, `U_CAST_TIMER`, `get_ability_charge_time()`, `AbilityView.ct`,
`GPUAbilityLoader`'s `charge_time = ability.ct * 30`, and the `"ct"` key on all
512 rows of the ability data. It also inherited the *first* one, in the UI only:
`UnitInfoPresenter`'s `ct` bar row is the 0..100 turn counter, and it has never
had a producer — `FormationScene` passes `has_ct: false` and every other caller
hard-codes a number. So the collision is real in both directions, and the field
being added here is the thing that finally fills that bar.

A second `CT` packed into the same unit block would propagate the ambiguity into
the generated layout, `SNAPSHOT_FIELDS`, the field table and every citation, in a
kernel where `U_CAST_TIMER` sits 49 offsets away.

## Status

accepted

## Decisions

**1. The name is `turn_meter` — `U_TURN_METER` in the shader,
`UnitField.TURN_METER` and the `"turn_meter"` snapshot key in GDScript.** It
counts UP and fills, which is what a meter does; it is drawn as a bar; and
`turn` is already this effort's word for the thing it grants
(`GambitTurnDirector`, the turn queue, the turn forecast). The on-screen label
stays **CT**, because that is what the game prints and this decision is about
identifiers, not about lying to the player.

**2. The clock is a GPU field the kernel never READS.** `compute_unit_state`
adds `max(1, U_SPEED)` to it every tick and nothing branches on it, so a
GambitBattle turn cannot change what a `GPUArena` battle does — the "rules kernel
does not change" constraint holds by construction rather than by review. It lives
on the GPU anyway because that is the only place it round-trips inside a
[battle snapshot](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md)
for free, is correct inside every rollout battle, and is visible to the value
function: "who is about to act" is a real feature of a position. A CPU
accumulator would be a second copy with a drift surface and no answer for
rollouts.

**3. Ready is a VALUE, not a flag: the kernel clamps at `TURN_METER_FULL`, and
the host carries the overshoot when the turn is taken.** A unit at or above 100
stops accumulating, so `turn_meter >= TURN_METER_FULL` *is* readiness — there is
no companion bit that can disagree with it. The subtraction is
`GPUBatchSimulator.consume_turn`, which subtracts 100 and keeps the remainder;
resetting to zero would quantize turn spacing to whole tick counts and drift fast
units off their true Speed ratio, and `TurnQueueTest` measures that drift on the
rejected variant rather than asserting the chosen one back at itself.

The clamp is what makes the overshoot survive to be carried, and it is also why
`consume_turn` **refuses a unit that is not ready** and returns -1: without the
refusal the meter goes negative and the unit waits longer than its Speed earns.

**4. The seeded start is computed CPU-side, by a GDScript mirror of the kernel's
own PCG.** `GPUCombatPacker.initial_turn_meter(battle_seed, unit_index)` is
exactly `rand_int(battle, unit_index, tick=0, TURN_METER_FULL)` as
`combat_common.glslinc` would compute it, so the battle has one definition of
randomness rather than two. It is a **parameter of `_write_unit_data`**, in the
same position and for the same reason as `team`: a per-slot value the caller
knows and a live `Unit` cannot supply. Mirrored rather than dispatched to the GPU
because the forecast is asked for at deployment, before the first tick — a
kernel-side init would make the opening turn order a post-dispatch value.

All-zero starts lock every equal-Speed unit into lockstep, which is both the
least interesting opening and the one that maximises simultaneous readiness.

**5. Only DEATH stops the clock.** Not `U_PAUSED`, not casting, not any activity.
The advance sits before the cinematic-pause gate in `compute_unit_state`, because
a cinematic increments `U_PAUSED` on every unit *except its caster* — gating
there would hand the caster free meter on every spell it casts. Not gating on
casting is the design's own requirement (§3, "a unit mid-cast still gets its
turn"): the turn *is* the reconfiguration, and mid-cast is exactly when you want
to re-tune what happens next. It is also the only way the queue stays computable,
which decision 6 depends on.

**6. The turn queue is a closed-form projection, in `TurnQueue`, one full
round-robin deep.** Pure statics over plain ints, no `RenderingDevice` and no
simulation: because every unit gains a fixed amount per tick and stops at a fixed
ceiling, the whole queue follows from the current meters. `forecast()` jumps
straight to the next tick on which somebody is ready rather than stepping, and
extends until every living unit has appeared at least once — self-scaling, so a
slow unit's long wait is visible as the pile of faster turns in front of it.

Order is **meter descending, then team, then unit index**. The design fixes the
tie-break (team, then index) and fixes it because nothing here may be random: the
enemy AI replays these positions inside its rollouts, and a queue that reshuffled
would make two runs of the same candidate disagree. Meter-descending is the
primary key because a larger overshoot means the unit crossed the line earlier
and has waited longer; "tie" is then exactly "equal meter", which is what the
design's sentence is about.

**7. `max(1, speed)`, in the kernel and in `TurnQueue`, is load-bearing.** A
Speed-0 unit is not a slow unit — it is a unit that never acts, a forecast that
never terminates, and a division by zero in `ticks_until_ready`. The schema's
`speed` default is 100 so production never sees zero, but the value is
config-supplied and a test config that omits it would hang the queue.
`forecast()`'s budget therefore counts **iterations, not emitted entries**: a rule
change that made some unit gain nothing per tick spins while emitting nothing, so
an entry-counted belt would never fire, and a hang is a worse verdict than a
short queue because nothing names it.

**8. Two test layers, split the same way ADR-0235 split its own.**
`TurnQueueTest` is pure and exhaustive over cases a battle cannot reach (Speed 0,
all-dead, a 1-vs-47 Speed spread), and it checks the closed-form jump against a
deliberately dumb one-tick-at-a-time oracle that does not share its arithmetic.
`GPUTurnMeterTest` runs the real kernel and asserts the two halves are the same
arithmetic, tick by tick.

## Considered options

- **`U_CT`, rejected** — the collision this file exists to avoid.
- **`turn_charge`, rejected.** `charge` *is* the cast-time word in this kernel
  (`AB_CHARGE_TIME`, `get_ability_charge_time`), so it reads as the collision
  with an adjective bolted on.
- **`turn_timer`, rejected.** Every `*_TIMER` in the unit block — `U_TIMER`,
  `U_CAST_TIMER`, `U_REACTION_TIMER`, `U_CINEMATIC_TIMER` — counts DOWN. This
  counts up.
- **`initiative`, rejected.** Accurate about the ordering and silent about the
  accumulator, and it imports a vocabulary the project does not otherwise use.
- **A CPU accumulator, rejected** (decision 2). It is not in a snapshot, not in a
  rollout, and not visible to the value function; three separate reasons before
  drift is even counted.
- **Wrapping in the shader (`if (m >= FULL) m -= FULL`), rejected** (decision 3).
  The host reads back at frame granularity over many ticks, so it cannot catch
  the edge; the clamp turns a momentary event into a durable state.
- **A separate `U_TURN_READY` flag, rejected** (decision 3). Two writers for one
  fact, and the field is one comparison away from the flag's whole content.
- **Initialising the meter on the GPU at tick 0, rejected** (decision 4). It puts
  a boot-only branch in the per-tick hot path and makes the opening forecast
  unavailable until after a dispatch.
- **A `UNIT_CONFIG_SCHEMA` row for it, rejected.** It is live state the shader
  writes, so ADR-0235's `overlay_behaviour_problems()` would reject the only
  behaviour a config-derived field could plausibly want; membership in the schema
  *is* the classification, and this field is not config-derived.
- **Reusing `rand_int`'s tick argument as a salt, rejected as unnecessary.** The
  initial draw is `tick=0`, which aliases a hypothetical tick-0 damage roll for
  the same unit; a tick-0 break roll cannot happen (nothing has attacked yet) and
  the two draws take different moduli, so a distinct salt would buy nothing and
  cost a second convention.

## Consequences

- `UNIT_SIZE` goes 101 → 102 and `SHADER_VERSION` 30 → 31, both regenerated by
  `tools/gen_gpu_layout.py` from the shader. `TURN_METER_FULL` joins the
  generated const list, so the threshold has one definition on both sides.
- **The live-state count is 57, not 56.** `UNIT_CONFIG_SCHEMA` still holds 45
  rows; the complement `unit_buffer_coverage_problems()` proves it partitions is
  one wider. ADR-0235's prose counts 56 and was correct when written.
- `GPUBatchSimulator` gains `consume_turn`; `GPUCombatPacker` gains
  `initial_turn_meter` and `_pcg_hash`, and `_write_unit_data` gains a fifth
  parameter. `src/gpu/TurnQueue.gd` is new.
- **The tick-to-turn RATE is not set here and is the next thing to feel.**
  `atb_speed` carries FFT Speed (`UnitProgression.get_effective_speed()`), so a
  Speed-8 unit is ready every 13 ticks — under half a second at 30 ticks/sec.
  §3 says "manageable speed is set by CT rates, not wall clock" and provides the
  between-turn playback rate as the lever; which lever moves, and to what, is a
  judgement that needs the host from
  [#891](https://github.com/timbermania/fft-monorepo/issues/891) and
  [#892](https://github.com/timbermania/fft-monorepo/issues/892) to exist before
  anyone can answer it. Recorded here so it is not discovered as a surprise.
- **`UnitInfoPresenter`'s `ct` view key is now an alias with a producer.** It is
  a display row name, not the domain term, and it keeps the FFT spelling; the
  wiring belongs to the HUD ticket
  ([#893](https://github.com/timbermania/fft-monorepo/issues/893)), not here.
- `MAX_UNITS_PER_BATTLE` remains vestigial (one reference, its own declaration);
  the boot-dead spare slots `GPUTurnMeterTest` relies on come from
  `set_battle_units` filling unused slots, not from that constant.
