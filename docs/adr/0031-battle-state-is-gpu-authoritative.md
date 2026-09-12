# Battle state is GPU-authoritative; CPU is a snapshot consumer

Every mutation to **battle state** — HP / MP / status, position, the unit
state machine, gambit evaluation, damage rolls, ability resolution — lives
in the GPU compute pipeline. The CPU reads battle state via
`get_battle_unit_states()` snapshots, derives **presentation state** from
those reads (animations, sound, projectile visuals, VFX), and never mutates
battle state back through any path — no buffer writebacks, no parallel
mutable mirror, no "just this one field" side channel. This generalises the
read rule from [ADR-0018](0018-gpu-combat-interpretation-is-a-pure-module-the-loop-composes.md),
which named it as a cluster invariant on the
[combat-step interpreter](../context/02-combat-buffer-layout.md), to every
CPU consumer of GPU state.

## Status

accepted

## Context

The rule has been the codebase's *de facto* shape since the GPU port: the
buffer is shader-authoritative (ADR-0001), the movement and combat
interpreters derive CPU presentation state from GPU snapshots (ADR-0017,
ADR-0018), and CPU systems read but never write the unit struct. It was
never an explicit project-wide invariant. ADR-0018's read rule named it as
a cluster concern for the combat-step interpreter; ADR-0001's
"shader-authoritative" named it for the buffer offsets. Neither said "the
same rule applies whenever you're tempted to push a battle-state decision
onto the CPU."

The original [ADR-0028] demonstrated the gap. Its "Decision" moved damage
application from the GPU's `tick_acting_animation` into a CPU-side
`projectile_manager.projectile_landed` callback. That decision was
reviewed, filed, and partially shipped (the constant deletion sub-step
landed in commit `a62be945`) before the invariant violation was noticed.
The remediation in [ADR-0032] — which keeps damage timing in the GPU —
depends on this rule being authoritative and pinned project-wide.

## Decision

- **Battle state is GPU-owned.** Every mutation to a unit's `U_*` fields,
  the battle header, or any field that affects the outcome of combat
  happens inside a compute shader pass. The shader is the only writer.
- **CPU reads, derives, presents.** The CPU consumes battle state via
  `get_battle_unit_states()` snapshots. It may derive presentation state
  (`Unit.activity`, animation slot ids, projectile positions, VFX
  schedules, audio cues) from the snapshot and apply it to scene nodes.
  It may **not** hold a mutable mirror of any battle field, and may **not**
  write back to the GPU buffer between ticks.
- **Immutable reference data is shared, not mirrored.** The CPU may read
  the same immutable inputs the GPU loaders pack into the GPU buffers
  (`AbilityDatabase` weapon-range / formula constants, sprite-type
  mappings, the layout's offset constants). This is not a competing source
  of truth — it's the same constant read from two places.
- **The interpreter pattern is the template.** When a CPU consumer needs
  to detect a *change* in battle state (a HP delta, a cast edge), it diffs
  consecutive snapshots or keys off a monotonic GPU counter
  (`MOVE_STEP_ID`, `CAST_STEP_ID`) — never a CPU latch maintained
  alongside the GPU. The movement and combat interpreters (ADR-0017,
  ADR-0018) are the worked examples.
- **When in doubt, the field goes in the unit struct.** A new field that
  affects combat outcome belongs in the unit struct (and the ADR-0001
  layout generator picks it up), not on a CPU manager. Buffer-size growth
  is cheap and bounded; CPU mutable mirrors are corrupting.

## Considered options

- **Selective CPU mutation for "obviously simple" cases (rejected).** The
  shape ADR-0028's original Decision took — "the projectile callback is on
  the CPU anyway, so let it write the HP delta." This is the failure mode
  this ADR exists to retire: every such case looks local, and the project
  ends up with N CPU writers competing with the GPU as the source of
  truth.
- **CPU mutable mirror for performance (rejected).** A cache of
  battle-state fields on the CPU side, marked dirty when the GPU writes
  them. Recognised as a known anti-pattern by the combat-step interpreter
  cluster invariant — the cache races the snapshot, and the snapshot is
  already cheap enough.
- **Keep the rule a cluster invariant of ADR-0018 (rejected).** That is
  what the codebase had until this ADR. The ADR-0028 failure shows it
  isn't enforceable when its only home is inside another ADR's body.

## Consequences

- A new battle-affecting field is **always** a unit-struct extension —
  shader change, `UNIT_SIZE` bump, `SHADER_VERSION` bump, ADR-0001
  regenerate. This is the cost the rule imposes; previously it was
  unstated and occasionally bypassed.
- CPU managers that today own visuals (`projectile_manager`, the effect
  managers, the animation apply pump) are constrained to read-only
  consumers of GPU state. Their visual timers may exist, but must be
  **synthesised from** GPU fields (e.g., interpolating a projectile's
  position from the firer's `U_TIMER` while in `STATE_AWAITING_IMPACT`
  — ADR-0032) rather than running in parallel to them.
- A future ADR that proposes a CPU mutation of battle state must
  explicitly cite this ADR and explain why it's an exception. The default
  review answer is "no — extend the unit struct instead."

## References

- ADR-0001 — buffer layout authority (narrower: offsets and struct sizes)
- ADR-0017 — movement interpreter (same shape, one slice)
- ADR-0018 — combat interpreter cluster invariant (generalised here)
- ADR-0032 — worked application: damage timing stays in the GPU via
  `STATE_AWAITING_IMPACT`
- CONTEXT.md — [Battle-state authority](../context/02-combat-buffer-layout.md)
