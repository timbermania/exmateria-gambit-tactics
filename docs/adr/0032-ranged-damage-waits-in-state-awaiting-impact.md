# Ranged damage waits in `LOGICAL_ACTIVITY_AWAITING_IMPACT`, not in `LOGICAL_ACTIVITY_ACTING`

Ranged weapon attacks and projectile spells split the firer's lifecycle
into two GPU states: `LOGICAL_ACTIVITY_ACTING` covers the BODY SEQ playback (raise,
fire, sheath, recover), and a new `LOGICAL_ACTIVITY_AWAITING_IMPACT` covers the
flight tail — the period between SEQ end and damage application at
projectile landing. The firer's [activity](../context/18-sprite-layers.md)
is `ATTACKING` during the first and a new parameterless `AWAITING_IMPACT`
during the second; both follow the
[ADR-0026](0026-gpu-combat-states-map-to-activities-never-directly-to-a-seq.md)
state-to-activity resolver path. Damage is rolled and written by the GPU
at `LOGICAL_ACTIVITY_AWAITING_IMPACT`'s timer-zero edge — same code, same wall-clock
tick as today, just gated on a different state-machine edge.

## Status

accepted — supersedes [ADR-0028](0028-decouple-damage-application-from-state-acting.md).

## Context

`LOGICAL_ACTIVITY_ACTING` was overloaded for ranged attacks. Its timer was
`max(scaled_attack_duration, scaled_damage_frame)`, so for a chemist firing
a gun 4 tiles away the state covered three distinct phases:

1. Playing the attack SEQ (frames 0–44).
2. Holding the SEQ's last-frame recoil pose while the bullet was in flight
   (~16 ticks of `PauseAnimation` paint-lock — the "frozen mid-shot"
   complaint).
3. (retired) A safety pad of ~10 ticks for the damage write — the
   `ANIM_BUFFER_MULTIPLIER` / `ANIM_SAFETY_MARGIN` constants deleted in
   commit `a62be945`.

Phase 3 went away with the constant removal and melee snapped to clean
SEQ-end. Phase 2 was load-bearing: the GPU's damage write lives in
`tick_acting_animation` (`stage_compute.glsl:704-817`), gated on
`state == LOGICAL_ACTIVITY_ACTING && timer > 0`. Shortening the timer would drop
damage entirely. So ranged attacks still held the recoil pose for ~270 ms
after SEQ end while the bullet crossed the field.

The first remediation attempt ([ADR-0028]) decoupled damage application
from `LOGICAL_ACTIVITY_ACTING` by moving the damage write to a CPU-side
`projectile_manager` landing callback. That violated [ADR-0031] — battle
state must live in the GPU — and is retired here.

## Decision

- **`LOGICAL_ACTIVITY_ACTING` ends at SEQ end.** `setup_attack_animation`'s timer
  collapses from `max(scaled_attack_duration, scaled_damage_frame)` to
  just `scaled_attack_duration`. The state covers SEQ playback only.
- **`LOGICAL_ACTIVITY_AWAITING_IMPACT` covers the flight tail.** A new GPU state
  and a new sibling `DisplayActivity.Activity`, registered like `IDLE` / `CELEBRATING`.
  Entered from `LOGICAL_ACTIVITY_ACTING` when the timer hits zero **and** damage
  hasn't fired yet (the projectile is still in flight). The activity
  resolves via the standard ADR-0026 `map.tres` path; today every
  sprite-type row points at the same SEQ pair as the unit's `IDLE` row,
  so the firer visually returns to neutral while the bullet crosses.
- **No new persistent unit-struct fields.** The damage write needs
  `U_TARGET`, `U_CASTING_ABILITY_ID`, `U_DAMAGE_FRAME`, and a countdown
  — all already alive in `LOGICAL_ACTIVITY_ACTING` and held through the transition.
  `U_TIMER` is repurposed across the transition: in `LOGICAL_ACTIVITY_ACTING` it
  counts SEQ frames, in `LOGICAL_ACTIVITY_AWAITING_IMPACT` it counts flight ticks
  (set to `damage_frame - anim_frame` at entry).
- **Damage logic factors out.** The damage-frame branch of
  `tick_acting_animation` (`stage_compute.glsl:728-816` — evasion roll,
  Blade Grasp / Arrow Guard, AOE / healing / damage write) becomes a
  helper `apply_attack_damage(battle_id, unit_id, tick)` called from
  two sites: the existing in-SEQ damage-frame crossing for melee /
  instant, and the new `LOGICAL_ACTIVITY_AWAITING_IMPACT` timer-zero edge for
  projectile attacks.
- **Gambit re-evaluation is blocked during the flight tail.** The
  shader's re-evaluation guard (`compute_unit_state:896`) already gates
  on `LOGICAL_ACTIVITY_WALKING / LOGICAL_ACTIVITY_WALKING_TO_CAST / LOGICAL_ACTIVITY_APPROACHING`. The
  firer's state is `LOGICAL_ACTIVITY_AWAITING_IMPACT`, not in that set, so
  re-evaluation is structurally blocked — no extra guard needed. FFT
  itself blocks; our system would technically allow re-eval, but
  waiting is correct on engine-design grounds (visual confusion + race
  between mid-flight relocation and pending damage).
- **`projectile_manager` becomes a pure visualiser.** It draws the
  bullet by reading the firer's snapshot every frame: while the firer
  is in `LOGICAL_ACTIVITY_AWAITING_IMPACT`, position is
  `lerp(firer_pos, target_pos, 1 - U_TIMER / flight_ticks_total)`; when
  the firer transitions out, the bullet despawns. Its
  `projectile_landed` signal survives for hit VFX / sound, but it does
  not write damage. (ADR-0031.) **(Superseded by
  [ADR-0038](0038-projectile-is-a-freezing-combat-visual-driven-by-geometry.md)
  — see Addendum.)**
- **Scope: ranged weapons + projectile spells.** Both call shapes today
  — `setup_attack_animation` (ranged weapon) and `cast_projectile_spell`
  (projectile spell) — apply the timer fix and route through
  `LOGICAL_ACTIVITY_AWAITING_IMPACT`. `cast_adjacent_item` and `cast_instant_spell`
  are unaffected — they have no projectile flight
  (`U_PROJECTILE_FRAME = -1`), so damage continues to fire inside
  `LOGICAL_ACTIVITY_ACTING` at the in-SEQ damage frame.
- **Idempotency is structural.** Damage fires once at
  `LOGICAL_ACTIVITY_AWAITING_IMPACT` timer-zero and the unit transitions to
  `LOGICAL_ACTIVITY_IDLE` in the same tick. Re-entry requires another
  `LOGICAL_ACTIVITY_ACTING`, which requires gambit eval, which requires
  `LOGICAL_ACTIVITY_IDLE`. No `CAST_STEP_ID`-style guard needed.

## Considered options

- **B2 — Separate projectile-entity track in the GPU buffer
  (rejected).** A new struct, SSBO slice, and `stage_projectile`
  shader pass tick alongside `stage_compute`; firer drops to `IDLE` at
  SEQ end, the projectile entity carries flight time + payload +
  idempotency. Cleaner conceptually and supports multiple in-flight
  projectiles per firer. Rejected: FFT can't multi-shoot per firer (a
  unit's gambit re-evaluation is gated on `LOGICAL_ACTIVITY_IDLE`), so B1's
  per-firer cap is the source material's constraint, not an
  ours-to-outgrow limitation. B2's costs (new dispatch axis, new
  shader pass, ADR-0001 buffer-layout extension) buy nothing real.
- **B1 with pre-rolled pending fields (rejected).** Persistent
  `U_PENDING_DAMAGE_TARGET / AMOUNT / TIMER` fields stamped at the
  projectile frame, applied at the timer-zero edge. Loses the "rolled
  at landing" semantic — damage is rolled at `damage_frame` crossing
  today (the bullet's arrival tick), so a target buffed mid-flight is
  rolled against the buffed state. Pre-rolling locks fire-time stats,
  changing combat outcomes. Also adds 3 fields to the unit struct for
  no gain.
- **The original ADR-0028 — CPU-side landing callback writes damage
  (rejected, retired).** Violates [ADR-0031]; was the proximate cause
  of this ADR being written.
- **Stretch the SEQ to fill the timer (rejected — held over from
  ADR-0028).** A 44-frame SEQ played over 70 ticks runs at 0.63× speed
  — the chemist would fire in slow motion.
- **Split `LOGICAL_ACTIVITY_ACTING` into `LOGICAL_ACTIVITY_ACTING` + `STATE_FOLLOW_THROUGH`
  (rejected — held over from ADR-0028).** Same shape as this ADR but
  framed as "follow-through is what the unit is doing." It isn't; the
  unit is idle. The *projectile* is doing something. The naming retired
  here ("follow-through") reflected attention on the firer;
  `AWAITING_IMPACT` reflects attention on the blocked event.

## Consequences

- `tick_acting_animation` keeps only its projectile-fired-bit branch
  (line 717-723); its damage branch (728-816) extracts into
  `apply_attack_damage`. The state-machine dispatch in
  `compute_unit_state` gains a `LOGICAL_ACTIVITY_AWAITING_IMPACT` branch and a
  fork in the `LOGICAL_ACTIVITY_ACTING` exit.
- Damage timing on the wall-clock is **identical** to today. Reaction
  rolls (evasion, Blade Grasp / Arrow Guard) fire at the same tick.
  Post-damage reactions (Counter, Auto-Potion — `LOGICAL_ACTIVITY_REACTING` on
  the target) trigger on the same `U_HP` delta tick. The only visible
  change is the firer's pose during the flight tail: from held recoil
  to idle.
- A target buffed mid-flight is rolled against the buffed state.
  Already true today (rolls happen at `damage_frame` crossing); the
  ADR makes it explicit so a future proposer doesn't suggest
  "pre-roll at fire time" without realising the semantic regression.
- `MIN_FLIGHT_TICKS = 15` continues to live in the shader as a GPU
  concern (it floors `flight_ticks` in `setup_attack_animation` and
  `cast_projectile_spell`). Retunable without touching
  `projectile_manager`.
- `GPUCombatTestBase` gains an `on_awaiting_impact` hook for symmetry
  with the other state-edge hooks; the standard assertion shape from
  ADR-0026 applies (`activity == AWAITING_IMPACT`,
  `current_animation_front == resolved slot`,
  `last_resolution.source == "atlas"`).
- `LOGICAL_ACTIVITY_AWAITING_IMPACT` lives in
  `tools/activity_taxonomy.yaml` as row 11 (value 9); the generator
  regenerates the GLSL constant, `LOGICAL_ACTIVITY_NAMES`, the
  `DisplayActivity.Activity` enum entry, and the
  `ActivityTranslator.translate(...)` dispatch arm. Post-PR2 the
  `DisplayActivity` enum is its own top-level class -- it no longer lives
  inside `AnimationStateController.gd`.

## References

- ADR-0001 — buffer layout, regenerated for the new state constant
- ADR-0018 — combat-step interpreter (unchanged; it diffs `U_HP` for
  damage events the same way today and after)
- ADR-0026 — state-to-activity binding (extended: `AWAITING_IMPACT`
  is the new sibling)
- ADR-0031 — the project-wide invariant that retired ADR-0028's
  CPU-callback shape
- `tools/activity_taxonomy.yaml` — the row that pins this Logical activity
  (`AWAITING_IMPACT`, value 9, routing `direct`, `clear_ability_id: true`)
  and drives the generator outputs.
- CONTEXT.md — [Unit activity (Logical + Display)](../context/18-sprite-layers.md)
  (the activity-taxonomy table embeds this row in context);
  [Awaiting impact](../context/18-sprite-layers.md),
  [Battle-state authority](../context/02-combat-buffer-layout.md)

## Addendum: `projectile_manager` visualiser model superseded

The `projectile_manager` bullet above ("pure visualiser driven by the firer's
snapshot every frame; despawn on firer transition") was a real reversal in
production: the despawn rule implemented as a teleport-to-target on firer
death, and a parallel "sits-in-the-air" failure on target death — both
discontinuities the eye notices. The cinematic-freeze axis (ADR-0037) didn't
halt the projectile's spin either; the snapshot-poll model had no group
membership to ride.
[ADR-0038](0038-projectile-is-a-freezing-combat-visual-driven-by-geometry.md)
supersedes that visualiser model: flight position advances from a per-GPU-tick
`advance_tick()` (called inside `CombatLoop`'s while loop, so flight stays
tick-locked at any `Engine.time_scale`) rather than a per-frame firer-snapshot
poll, target Node death snapshots `end_pos` and the local countdown carries
flight to completion regardless of firer state, and `Projectile3D` joins the
[`combat_visuals` group](0037-combat-pause-is-domain-scoped-via-process-mode-group.md)
so spin/tumble halt under the freeze predicate (position freezes naturally
when the while loop short-circuits on `combat_active = false`).

**Flight duration stays SEQ-authored, same value this ADR specified.** What
changes is the *driver* (a local countdown advanced one tick at a time by
the projectile itself) and the *freeze axes* (combat-visuals for spin,
`combat_active` for position). An ADR-0038 draft proposed
distance-driven family-speed constants; that draft was retired during
implementation because `_trigger_projectile_reaction`'s 2-tick hit window
depends on visual landing aligning with the GPU damage tick. The retired
BULLET `/3` divider and the throw/item `flight_speed_mult` knob were the
real source of perceived speed inconsistency; their removal gives uniform
SEQ-derived timing across every family.

**This ADR's state-machine half is unaffected.** `LOGICAL_ACTIVITY_ACTING`
ending at SEQ end, the `LOGICAL_ACTIVITY_AWAITING_IMPACT` flight-tail state,
timer-zero damage write, in-shader gambit re-eval block, and the
mid-flight-rolled-against-buffed-state semantic all stand. ADR-0038 changes
only how the projectile is *drawn*, not when damage applies.
