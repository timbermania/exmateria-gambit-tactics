# A turn opens on a taker that has committed to nothing

A unit's turn came up and the camera travelled to a tile that looked empty. The sprite
was a tile short of it. That is the reported bug, and the fix for it is not a camera fix
— it is a rule about **when** a turn is allowed to open, and a kernel brake that makes
that rule reachable.

This ADR records the rule, the brake, and the two things the brake is deliberately *not*
addressed by.

## What the defect actually is

**Logical position is the DESTINATION for the whole duration of a movement step.**
`stage_resolve.glsl` says so verbatim — *"CPU updates position at START of movement, not
END."* `write_movement_step` sets `U_TIMER = U_MOVE_TOTAL_TICKS`, `compute_unit_state`
counts it down and returns early until it drains, and `GPUVisualBridge` publishes that
destination straight into `movement_component.current_cell`. So for a whole step,
`Unit.get_current_cell()`, the camera travel and `_unit_at_grid` all place the unit **one
tile ahead of its own sprite**, and only the visualizer knows better.

[TurnDirector]'s gate froze the world on whatever tick a meter crossed
`TURN_METER_FULL`. `combat_active = false` then stopped the very ticks that would have
carried the sprite in, so it sat between tiles for the whole turn.

**But alignment is the symptom, not the reason the rule has to exist.** A turn is an
EDITING WINDOW: [AdjustmentTurn.commit] rewrites the taker's gambit list through
`GambitEncoder.encode_for_unit`, and `GambitBattle`'s rollout beat rewrites it again for
an enemy taker. A unit frozen mid-action finishes the action it had already committed to.
The edit is accepted, acknowledged, and silently **not what the unit does next**. That is
a correctness defect in the one interaction the turn exists for, and it is invisible —
nothing reds, the player just watches their order be ignored.

**Why the obvious gate hangs.** "Freeze only when the taker is aligned" never fires: a
continuously walking unit is never aligned, and on the tick its timer drains the dispatch
can write the next step in that same tick, so the post-tick columns the gate reads need
never show a settled walker. `evaluate_gambits_up_to` can even go gambit A → gambit B
straight from a walking state, skipping IDLE entirely. A five-tile path shows IDLE zero
times.

## Decision

**A turn opens only on a taker that has committed to nothing, and the kernel brakes a
ready unit so that state is reachable.**

Three parts, and none of them works without the other two.

### 1. The kernel brake — `config.turn_brake_battle`

In the battle that stops for turns, a unit whose meter is at `TURN_METER_FULL` and whose
state is IDLE or one of the three movement states **starts nothing new**: it is written
IDLE, its proposed position is reset to where it stands, `U_DBG_STATE_REASON` is stamped
`REASON_TURN_PENDING`, and the dispatch returns before `evaluate_gambits`.

The `U_TIMER` countdown above it is deliberately untouched — the unit **finishes the step
it is on**, which is exactly what leaves the sprite on its logical tile
(`GPUMovementVisualizer.calculate_position(0)` returns `end_pos` on both the linear and
the cliff path) — and simply never starts another.

It is scoped to the states a unit can start something *from*. ACTING, SPELL_CHARGING,
AWAITING_IMPACT, PREEMPTIVE_COUNTER and DYING are mid-action and are left to finish; they
all drain into IDLE, where the brake catches them, so it still terminates.

It sits **after** the per-tick clears, for the same reason the CELEBRATING check above it
does: returning above `U_PENDING_ACTION_TYPE = ACTION_NONE` leaves last tick's
`ACTION_PATHFIND_MOVE` standing, and `stage_pathfind` writes WALKING straight back over
the IDLE — every tick, invisibly.

### 2. The gate is a union across two scopes

```
trip iff  ∃ a ready living unit
      AND no ready living unit is mid-step        ← term 1, _turn_gate, ALL ready units
      AND ready_now()[0] is IDLE                  ← term 2, _open_turn, the TAKER
```

**Term 1 is about POSITION; term 2 is about COMMITMENT, and neither subsumes the other.**
A bystander frozen mid-*step* is genuinely mislocated — the camera can travel past it,
`_unit_at_grid` misreads it — so term 1 quantifies over every ready unit, not just the
taker. A bystander frozen mid-*attack-animation* is not mislocated: the whole world is
frozen and it resumes on commit. So term 1 stays the three movement states and is **not**
widened to `!= IDLE`; that would buy nothing and cost cadence.

Term 2 lives in `_open_turn` and not in the gate, because the gate has the meter, flag
and state columns but **not `team`** — it cannot break a meter tie the way `_before` does,
and a second copy of `TurnQueue`'s ordering is the one thing that must not exist. Refusing
there keeps turn ORDER in one place: the head is still `TurnQueue.ready_now()[0]`, so this
makes a turn open LATER, never somebody else's open first.

### 3. Both terms are gated on `stops_the_world`, and that is load-bearing

The brake is armed by the same flag. Under the walk's default policy a ready unit walks
forever, so an ungated term 1 would mean the walk's turns are not late — they would
**never be announced at all**. One flag, no second knob: a host that does not freeze has
nothing to land well.

## Why the brake is a config uniform and not a unit field

`RolloutHarness` forks candidates with `restore_battle(k, snapshot_battle(0))`, which
copies the header and every unit block verbatim into fleet slots. **Nothing consumes turns
in a candidate battle**, so every unit in one pins at `TURN_METER_FULL` forever. A brake
carried in `U_*` or in a `BattleHeaderField` bit would ride that fork, stop the entire
rollout fleet from walking, and quietly poison the value function that scores the enemy's
move — with no test failing, because a candidate battle is only ever read as a score.

A config uniform lives in no SSBO and cannot ride a fork. It also costs no `UNIT_SIZE`
bump, no `tools/gen_gpu_layout.py` regeneration, no `_write_unit_data` coverage entry and
no ADR-0235 overlay classification.

`GPUTurnMeterTest` arm D is that claim as an arm: the brake is armed on battle 0, a
`restore_battle(1, snapshot_battle(0))` fork carries the same pinned-at-FULL meters, and
**the fork keeps walking**. The fork half is also the arm's positive control — "battle 0
stopped stepping" is what a battle where nobody was walking reports too.

## The bug the brake found on its way in

`_refresh_pacing_in_pair` compared `Vector2i(pair_data[9], pair_data[10])` — the two
pacing ints — and returned early otherwise. The batched path binds `_uniform_sets_pair`
and never calls `_update_config`, so **every field appended to `SimConfig` after those two
was dropped on every `step_tick(K > 1)`**, which is most ticks, silently, while working
perfectly on the single-tick path nobody ships. `turn_brake_battle` was the field that
found it.

It is now `_refresh_live_config_in_pair` and compares the **whole block** with
`current_buffer` normalised out (that index is baked per member, so it is the one that
legally differs). The next appended field is covered by construction. Seeded break
verified: restore the two-int comparison and `GPUTurnMeterTest` arm D's braked battle
keeps stepping.

## Considered and rejected

- **Land the visual during the freeze** (advance the visualizer to `end_pos` while the
  world is stopped). Cheapest by far. Rejected on the look: one unit walking through a
  frozen world.

- **Freeze at a step boundary and roll the step back** with `_set_unit_field`. Rejected:
  it mutates sim state to fix a presentation problem, loses a tile of progress, and
  `U_PREV_MOVE_POS` is a two-field column pack with no level (ADR-0224 dec. 5), so
  cross-level rollback is awkward.

- **Widening term 1 to `state != IDLE`** — i.e. making the gate itself demand that every
  ready unit be uncommitted. Rejected: a ready bystander mid-attack is not mislocated, the
  freeze is coherent over it, and the wait costs cadence for nothing. Term 2 already
  covers the one unit whose commitment matters.

- **A `U_TURN_PENDING` unit field or a header flag bit.** Rejected for the rollout fork
  above. This is the decision that most looks like a style choice and is not one.

- **A second flag to arm the brake independently of `stops_the_world`.** Rejected: there
  is exactly one condition under which a brake is wanted — a host that freezes on turns —
  and a second knob is a second thing to set wrong. `NavigatorMain`'s default walk is
  untouched by construction, and its opt-in `navigator.stop_on_turn` walk (ADR-0264 PR 2A)
  gets the brake for the same reason `GambitBattle` does.

## Consequences

- **Turn timing shifts by up to one movement step (~12–30 ticks).** Nothing is lost — the
  meter pins at FULL and `consume_turn` carries the overshoot — but tick-exact combat
  fixtures move.

- **A unit interrupted mid-`WALKING_TO_CAST` / `APPROACHING` collapses to IDLE and
  re-decides after the turn.** Defensible (a turn *is* the re-plan) and a real simulation
  change.

- **Side effect, and a fix:** `stage_resolve.glsl` re-arms `U_TIMER = 1` on a
  conflict-blocked unit while leaving the state WALKING, so a blocked ready unit used to
  retry forever. Under the brake it settles to IDLE.

- **`CELEBRATING` returns early above the brake**, so a ready celebrating unit never
  settles and term 2 would block on it. Masked in practice because `victory_achieved`
  stops the loop from calling the gate at all. Left as-is deliberately; if a host ever
  gates turns through a victory beat, this is where it bites.

- **A NON-ready unit mid-step still freezes between tiles.** Nothing brakes it, so no gate
  could wait for it — that is the rejected "land the visual" option, and it is still
  rejected. The union does not cover this and does not claim to.

- **Between turns, `get_current_cell()` still reports the destination tile for a walking
  unit**, so ○ on the tile you *see* a unit on misses it mid-stretch. Ruled a separate
  issue needing a different fix; explicitly not folded in here.

## Soft spot

**S1 — design S3's "a unit mid-cast still gets its turn" now needs reading as a claim
about the METER.** `stage_compute.glsl`'s meter comment cites it. Under term 2 a ready
mid-cast unit gets its turn **after** the cast resolves — `AB_CHARGE_TIME` at
`CHARGE_SEQ_SPEED = 1`/tick is tens of ticks. Read as "the meter does not stop for a cast"
S3 is still true and this ADR is consistent with it; read as "the turn opens during the
cast" it is not. The distinction is real — the second reading is the one that makes the
adjustment window a lie — but the call is the design's owner's and it is **unresolved
here**.

## Status

accepted.

⚠️ The number was claimed by scanning **all worktrees** (`godot-learning/docs/adr`
high-water 0265, held by the unmerged `feat/navigator-battle-host-surface`), **every ref**
(`git log --all --diff-filter=A` over `026*`), and the open PR list. ADR-0258 records four
collisions caused by scanning only the filesystem. The window between claiming and pushing
is still open; this is a mitigation, not a fix.
