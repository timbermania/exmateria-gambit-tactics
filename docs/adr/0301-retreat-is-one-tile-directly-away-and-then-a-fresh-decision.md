# Retreat is one tile directly away, and then a fresh decision

[ADR-0062](0062-gambit-movement-is-one-move-command-flavor-emergent-from-target.md)
deleted `RETREAT` from `Gambit.ActionKind` and gave a reason that was true when it
was written:

> "retreat" has no single referent — a corner, a near ally, a far ally, away from
> the nearest enemy are all different behaviors — so it cannot be one command.

It has a single referent now.
[#1103](https://github.com/timbermania/fft-monorepo/issues/1103) asked the
question as a `wayfinder:grilling` ticket and the answer is the user's own, in two
sittings, recorded verbatim on the ticket:

> Retreat means 1) find the nearest enemy 2) pick the direction opposite the
> vector to them 3) move there 4) once at logical position, reevaluate gambits
> (like normal)

and, when the implementer asked how far "move there" goes:

> retreat is one tile then reevaluate.

That is a command. This ADR is what it means in the kernel.

## Status

accepted

## Context

Three facts about the tree decided the shape, and all three were read rather than
assumed.

**The distance field ADR-0062 said did not exist, exists.** ADR-0062 rejected
"retreat as a relational tile selector (farthest-from-enemy)" on the grounds that
it *"needs a battlefield/distance-field scan that does not exist."*
`DistanceFieldGenerator` now precomputes an **all-pairs** path field and
`combat_common.glslinc`'s `get_distance(from_cell, to_cell)` reads it in one
indexed load. "How much further from that unit does this tile put me" is a lookup,
not a scan. The half of ADR-0062's rejection that was about *cost* is simply spent.

**There is no move budget to spend.** #1103's second answer left two questions for
the implementer, and one of them — *"whether the step costs the unit's whole move
budget or one tile of it"* — dissolves on inspection: `U_MOVE` is declared in
`combat_common.glslinc` and **read by no shader**. Movement in this kernel is
priced per STEP (`write_movement_step` → `get_move_ticks` → `U_TIMER`), and a unit
walks tile by tile with no per-turn allowance to draw down. A retreat step costs
what any other step of the same tile costs and nothing else.

**The other left-open question was already answered by the answer.** *"One tile
away from WHAT — the nearest foe, the aggressor that just hit, or a threat
centroid"* — step 1 of the user's own definition is "find the nearest enemy". This
ADR generalises that by one notch only, to *the unit the retreat is aimed at*,
because the aim is a column the gambit surface already has and `Nearest Foe` is
what it will hold.

## Decision

- **`ActionKind.RETREAT` is a verb again**, and it is the only movement verb
  besides `MOVE`. `APPROACH` stays deleted for exactly ADR-0062's original reason:
  an approach IS `MOVE` aimed at the thing approached. Only the away-facing half
  of that pair needed a word, because every target `MOVE` can take is somewhere to
  move *toward* — **the sign is the verb, and a target cannot carry it**.

- **Retreat is a DESTINATION, not a target type.** `TargetSelector` gains no
  `FURTHEST` resolution. The retreat's `action_target` is the unit to move away
  from, resolved by the same `_target_selector_to_gpu(action_target)` block every
  other action uses, so `RETREAT` inherits the same supported / `UNSUPPORTED`
  target set for free. Whether `FURTHEST` earns its place on its own merits
  (#1103 Q3) is untouched by this and stays a separate, smaller call.

- **`ACTION_RETREAT_STEP` is a new GPU primitive**, not `ACTION_MOVE_TO` with a
  near destination and not `ACTION_MOVE_TO_UNIT` with the field inverted. Both of
  those enter a walking state that OUTLIVES the step, and each fails a different
  way: `handle_moving_state` opens with *"is anyone attackable? then stop and
  swing"*, so a retreat in `LOGICAL_ACTIVITY_WALKING` breaks off into an attack on
  the very unit it is fleeing; and `execute_move_to_unit_gambit` re-paths toward
  its anchor every tick, which is a committed flee. **Both are measured, not
  argued** — `GPURetreatStepTest`'s seeded break is precisely the WALKING
  substitution, and it reds four of the five arms, one of them by walking the
  fleeing unit back toward the threat.

- **`LOGICAL_ACTIVITY_RETREATING` is a new Logical activity** (value 10, appended;
  `tools/activity_taxonomy.yaml` is the source of truth). Display is `WALKING` and
  routing is `visualizer`, identical to the other three moves — the split is
  entirely about what the SIMULATION may do next, which is the same reason
  `APPROACHING` exists alongside `WALKING`.

- **The rule, in full.** Given an actor and the unit it is fleeing, let `here` be
  the path distance between their cells:

  1. If the two are the same unit, or `here < 0` (no walk connects them), there is
     **no retreat**. See the fall-through below.
  2. Take the **preferred direction**: the dominant component of the vector *from*
     the threat *to* the actor, ties on `|dx| == |dz|` going to x. If a cell of
     that neighbouring column is traversable, within jump, unoccupied, and its
     path distance from the threat is **strictly greater than `here`**, step
     there.
  3. Otherwise scan all four neighbours and take the cell that opens the MOST
     distance, still requiring strictly greater than `here`. Scan order (+X, +Z,
     -X, -Z) breaks ties, lower level first.
  4. If nothing qualifies, there is **no retreat**.

  Then the unit re-decides. Nothing is committed.

- **The preferred direction wins even when a perpendicular step would open more
  distance.** The answer says "pick the direction opposite the vector to them", not
  "maximise the field", and a retreat has to READ as fleeing. Maximising is what a
  `FURTHEST` selector would do and it is a different, unbuilt thing.

- **"Strictly greater" is also the anti-oscillation rule.** Ordinary movement
  carries `U_PREV_MOVE_POS` so a committed path cannot ping-pong; a retreat needs
  no such memory, because a strictly monotone sequence cannot step back onto a
  cell it left while the threat stays put.

- **A cell the threat cannot path to at all (`get_distance < 0`) is EXCLUDED, not
  treated as infinitely far.** From the field alone the kernel cannot tell perfect
  cover from an isolated ledge the unit can never leave, and stranding a unit for
  the rest of the battle is the worse of the two errors.

- **A retreat that cannot be taken FALLS THROUGH to the next gambit slot**, and
  this is why the cell is picked in the DECIDE stage rather than in the pathfind
  body. `execute_gambit_action` runs `retreat_step_cell` before it commits the
  slot and returns `false` with `VERDICT_NO_RETREAT` when there is no cell, so the
  walk continues to the slots below — which is how a cornered unit still reaches
  its `Attack` row. Deferring the pick to `stage_pathfind` the way every other
  movement action does would leave the unit committed to a retreat it cannot take,
  re-deciding into the same wall every `TICKS_GAMBIT_REEVAL` and never seeing
  another slot.

- **`VERDICT_NO_RETREAT` (12) joins the verdict vocabulary**, taking
  `GambitVerdictReader.EXPECTED_CODE_COUNT` to 13. It is the first code that
  reports a failure the kernel can only find by reading the MAP; every other one
  reads a status bit, a pool, or an ability record.

- **The prose says "Retreat from".** `GambitProse.action_line` juxtaposes verb and
  target because every other verb takes its target as the thing acted ON. Retreat
  does not, and "Retreat Nearest Foe" reads as retreating *toward* them.

- **#1103's Q4 — "what stops a retreat loop?" — is dissolved rather than
  answered.** It was called *"probably the hardest one here"* and it presumed a
  committed multi-tile flee to bound. There is none: the unit re-decides after
  every tile, so the gambit's own condition holds or releases it. No cooldown, no
  turn boundary, nothing new.

- **A retreat aimed at the actor is refused in the KERNEL**, not only on the
  surface. `get_distance` from a cell to itself is 0, every neighbour beats 0, and
  the strictness test would wave through an arbitrary direction forever — a random
  walk, not a no-op. `GambitOptions.aim_verdict` marks the aim `AIM_FORBIDDEN`, but
  the surface is not the only way a gambit reaches the buffer (the rollout fleet
  and the raw command path both bypass it), so `retreat_step_cell` refuses it too.

## Considered options

- **Compose retreat from `MOVE` plus a repulsive target** (the shape ADR-0062
  implies). Rejected: there is no such target. `MOVE`'s `action_target` names a
  unit to path toward, and the only way to make it mean "away" is a flag on the
  action — which is a verb wearing a costume.

- **Retreat as a destination computed on the CPU and handed to the existing
  `ACTION_MOVE_TO`.** Rejected on the walking state, as above: `ACTION_MOVE_TO`
  enters `LOGICAL_ACTIVITY_WALKING` and `handle_moving_state`'s opportunistic
  attack turns the flee into a swing at the thing being fled. Measured as the
  seeded break in `GPURetreatStepTest`.

- **Invert the sign inside `stage_pathfind`'s existing scorer.** Rejected against
  the GambitBattle map's standing bar — *"a retreat that alters how
  `stage_pathfind` scores tiles for ordinary movement would fail that bar"*.
  `scan_adjacent_moves` is shared by every move in the game.

- **Add `FURTHEST` to `TargetSelector.ResolutionStrategy` and build retreat on
  it.** Rejected as the wrong axis: a resolution strategy picks WHICH UNIT, and
  retreat's problem is which TILE. It may still earn its place independently
  (#1103 Q3) and this ADR does not spend that question.

- **Retreat as a multi-tile flee with a bound** (a cooldown, a "flee until out of
  threat range", a turn boundary). Rejected by the answer itself. It is also what
  made Q4 hard; one tile at a time makes the bound the gambit's own condition,
  which the player already writes.

- **Let a cornered retreat fail in the pathfind body like a failed path does.**
  Rejected: a movement body's failure costs a tick and re-decides, and for a
  cornered unit that re-decision hits the same wall forever with the slots below
  the retreat never reached. A unit backed into a corner has to be able to fight.

## Consequences

- **`GambitEncoder.UNSUPPORTED_ACTION_KINDS` stays empty.** `RETREAT` maps, so
  ADR-0023's faithful-or-explicit completeness test covers it like the rest.

- **Legacy saves that stored the name `"Retreat"` finally round-trip.** ADR-0062
  degraded them to `WAIT` because the name resolved to nothing;
  `Gambit.action_from_name` consults `VERB_TO_KIND` first, so the word now
  resolves to the verb it always meant. `"Approach"` keeps its alias to `MOVE`.

- **The retreat's terrain fallback is covered by reading, not by running.**
  `GPURetreatStepTest` runs on `MapComposer`'s open procedural map, where the
  preferred cell is always available — MEASURED: dropping the strictness test
  leaves all five arms green. Reaching the four-neighbour scan needs authored
  terrain that blocks the away-direction, which is #795's fixture work.

- **`LOGICAL_ACTIVITY_RETREATING` is a movement state everywhere, and it gets
  there by DERIVATION rather than by being listed.** It is a state a unit can
  start something from and a state the picture is mid-step in, so it belongs to
  the kernel's turn brake, its settle brake and `settle_awaited_state`, and
  equally to the host's turn gate, `GPUMovementInterpreter` and
  `GPUVisualBridge`. 🔴 THIS ADR'S FIRST CUT SWEPT THE KERNEL'S THREE AND NONE OF
  THE HOST'S, AND THE SYMMETRY IS WHAT HID IT: all six sites hand-listed the same
  states and each said in its docstring that it agreed with the others, which was
  true right up until a fourth state existed. The host kept classifying every
  retreat as no-move, so `GPUVisualBridge` dropped the visualizer and snapped —
  the sprite teleported, held the facing `update_facing_toward_target` gave it
  (facing the unit it was fleeing), and slid in whatever pose it was already in,
  because on a `visualizer` row the translator no-ops and the visualizer that was
  supposed to author the pose never existed. One omission, three symptoms. The
  host's set is now generated from this row's own `routing: visualizer` into
  `GPUConstants.is_movement_state`, so a fifth move state joins every host
  consumer by being a YAML row. **The kernel's three lists stay hand-written**,
  and the reason is ADR-0299's compile-time race rather than anything about the
  code: a shared GLSL `is_movement_state()` made the pipeline cache miss, and
  `warm_pipelines_async()` then outlived a short test's `quit()` and read a freed
  autoload. MEASURED, interleaved 3 rounds — `All 8 stages ready in` 30/31/30 ms
  without it against 3504/3528/3361 ms with it, and
  `NavigatorWorldMapFormationTest`'s freed-autoload errors went 4-of-9 runs to
  9-of-9, isolated by reverting the shaders alone while holding every GDScript
  change. A macro would not help — the cost is not the call, it is that the SPIR-V
  changed. So the kernel half is a copy, and the comment above
  `settle_awaited_state` says so.

- **This supersedes ADR-0062's retreat clause and nothing else of it.** One
  movement command became two; the *flavour-from-target* principle still holds for
  everything `MOVE` does, and the absolute-tile `ACTION_MOVE_TO` back door is
  untouched.

- **#1104's retreat half is unblocked**, which is the head of the
  #1103 → #1104 → #1110 → #1111 chain on
  [#1101](https://github.com/timbermania/fft-monorepo/issues/1101). Until this
  landed, every balance number was tuned against an AI that could not disengage.

## See also

- [ADR-0062](0062-gambit-movement-is-one-move-command-flavor-emergent-from-target.md)
  — the decision this amends, and still the right answer for `MOVE`.
- [ADR-0024](0024-unit-owns-the-resolution-map-call.md) — `ACTION_MOVE_TO_UNIT`
  and `LOGICAL_ACTIVITY_APPROACHING`, the reposition-without-attack contract this
  copies.
- [ADR-0275](0275-the-gambit-lab-is-a-cell-a-mirror-and-a-verdict-the-kernel-writes.md)
  — the verdict vocabulary `VERDICT_NO_RETREAT` joins.
- [ADR-0224](0224-the-gpu-battle-mover-addresses-a-cell-so-the-map-is-two-planes-and-the-unit-carries-its-level.md) — why the packed retreat
  destination carries a level field.
