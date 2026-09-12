# `LOGICAL_ACTIVITY_REACTING` is the `PREEMPTIVE_COUNTER` gateway; flinch lives on the ROM-faithful trigger pathways

The GPU's `LOGICAL_ACTIVITY_REACTING` is renamed `LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER` and
narrowed to its real meaning: a one-tick queued-counter-strike gateway
written by Hamedo (`REACT_FIRST_STRIKE`). It carries no rendering side and
fires no flinch overlay. The hit-flinch visual that the YAML row's
`react_overlay` routing previously sprayed onto this Logical state was a
spurious third pathway — the two ROM-faithful triggers
([SEQ opcode 0xffde](../context/20-animation-react.md),
[effect keyframe `action_flags` 0x40](../context/20-animation-react.md))
already own the flinch correctly, converging on
`Unit.play_reaction_animation`. The translator's
`_translate_react_overlay` is deleted, and the new state takes a no-op
routing (the defender shows IDLE for the one gateway tick, then ATTACKING
under `LOGICAL_ACTIVITY_ACTING` via the existing `attack_handler` routing on the
next tick).

## Status

accepted — extends [ADR-0021](0021-animation-resolution-is-per-state-one-atlas.md)
and [ADR-0025](0025-react-playback-is-a-parallel-set.md), which already
named the React playback set as a parallel-rendering concern; this ADR
fixes the YAML/translator layer that was crossing that line.

## Context

`tools/activity_taxonomy.yaml`'s `REACTING` row was modelling two unrelated things at once.

**Concept A — hit-flinch visual.** Every damaged unit gets
`U_REACTION_TIMER = TICKS_PER_REACTION` (`stage_damage.glsl:79`, `:98`,
`:129`) and the timer is decremented as "cosmetic" in
`stage_compute.glsl:880-882`. Nothing reads the timer; it is GPU dead
code. The real flinch is fired by **two ROM-faithful trigger pathways
that already exist in the codebase**:

- **SEQ-opcode pathway** — attacker's BODY SEQ reaches opcode `0xffde`
  (`POST_GENERIC_ATTACK`); `AnimationPlayback.gd` emits
  `side_effect.POST_GENERIC_ATTACK`; `CombatLoop._on_unit_type1_side_effect`
  calls `_trigger_physical_reaction(attacker_idx)`, which reads the GPU
  `evade_type` and calls `target_unit.play_reaction_animation(...)` with
  the right overlay (`taking_damage` / `evade` / `shield_block_mid` /
  `receive_heal` for blade-grasp).
- **Effect-keyframe pathway** — effect script reaches a keyframe with
  `action_flags` bit `0x40` (`ACTION_FLAG_ABILITY_REACT`);
  `EffectInstance` emits `ability_react_triggered`;
  `CombatLoop._initialize_managers` routes it to `_on_ability_react`,
  which reads the ability's `target_reaction_type` and plays the matching
  overlay.

Both pathways converge on `Unit.play_reaction_animation`, mirror the
PSX `execute_unit_reaction_pose` (0x80083a40) and match
`research/wiki_articles/target_reaction_animations.txt`. Neither needs
the YAML's `LOGICAL_ACTIVITY_REACTING` to fire.

**Concept B — Hamedo's queued counter-strike.** The shader writes
`LOGICAL_ACTIVITY_REACTING` in **exactly one place** —
`stage_compute.glsl:625-636`, `check_pre_damage_reactions` — and **only**
when the defender has `REACT_FIRST_STRIKE` (Hamedo). The
`LOGICAL_ACTIVITY_REACTING`-state handler at `stage_compute.glsl:985-995`
reads `U_TARGET` (the queued original attacker) and calls
`setup_attack_animation`, which writes `LOGICAL_ACTIVITY_ACTING` and the
attack SEQ fields. So the state lives **exactly one tick**: gateway →
ACTING (counter-strike as a normal attack animation) → IDLE.

**The buggy conflation.** The YAML row's `routing: react_overlay` made
`ActivityTranslator._translate_react_overlay` call
`unit.play_reaction_animation(..., TAKING_DAMAGE)` whenever the GPU
wrote `LOGICAL_ACTIVITY_REACTING`. Net effect: only Hamedo defenders
flinched, and they flinched **coincidentally** with the right look
(they were about to take damage). Every other damaged unit got nothing
from this pathway; they relied on the SEQ opcode + effect keyframe
pathways above (which were already wired). The `react_overlay` routing
was therefore both spurious *and* incomplete — it neither owned the
flinch for non-Hamedo damage nor coexisted cleanly with the pathways
that did.

The 2026-06-09 grill (see CONTEXT.md's
[Combat-event resolution](../context/21-combat-event-resolution.md)
cluster) crystallised the six resolution pathways and the three
reaction-ability families; this ADR is the formal landing of the YAML
+ translator changes that follow.

## Decision

- **Rename `LOGICAL_ACTIVITY_REACTING` → `LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER`,**
  keeping `value=3` to preserve the GPU buffer contract. The
  generator (`tools/gen_activity_taxonomy.py`) emits the new constant
  into `combat_common.glslinc` and `GPUConstants.gd`; the lone shader
  reference in `check_pre_damage_reactions` updates to write the new
  constant; the state-handler at `stage_compute.glsl:985` matches the
  new constant. No GPU behavior change.
- **Replace `routing: react_overlay` with a new `transient` routing**
  in the YAML — semantically "logical-only state, translator no-ops."
  The generator emits a no-op `_translate_transient` static method,
  same shape as `_translate_visualizer`. The defender shows the IDLE
  pose for the gateway tick (no `unit.activity` mutation), then the
  next-tick state transition to `LOGICAL_ACTIVITY_ACTING` swaps in the ATTACKING
  display via the existing `attack_handler` routing.
- **Delete `ActivityTranslator._translate_react_overlay`** entirely.
  No call site remains after the YAML reroute.
- **Keep the two ROM-faithful flinch pathways unchanged.** They are
  already correct: `CombatLoop._trigger_physical_reaction` for
  physical attacks (driven by SEQ opcode `0xffde`),
  `CombatLoop._on_ability_react` for spell effects (driven by
  `action_flags 0x40`). They render through the parallel
  [React playback set](../context/19-animation-playback.md) per
  ADR-0025.
- **`U_REACTION_TIMER` stays in place** as a per-damage cosmetic
  marker. Today nothing reads it; that is a known dead-code observation
  the grill noted but did not resolve here. A future ADR may either
  promote it (give it a consumer) or retire it; this ADR does not.

## Considered options

- **B — Inline the counter into `LOGICAL_ACTIVITY_ACTING` (rejected).**
  At Hamedo trigger time, call `setup_attack_animation` inline so the
  defender enters `LOGICAL_ACTIVITY_ACTING` the same tick instead of after a one-tick
  gateway. Rejected: `check_pre_damage_reactions` runs during the
  *attacker's* tick resolution (called from `apply_attack_damage`); a
  mid-resolution mutation of the defender's full attack-state risks
  reading-the-attacker-after-the-attacker-died races and tightens the
  coupling between `stage_compute` and `stage_damage`. The one-tick
  gateway preserves the per-unit-per-tick state-machine invariant.
- **C — Drop the YAML row entirely; keep the shader constant
  out-of-band (rejected).** The shader would carry a hand-written
  `LOGICAL_ACTIVITY_REACTING` constant outside the generated block, and the
  Logical-activity table would have no row for the state. Rejected:
  breaks the
  [YAML-is-single-source-of-truth](../context/18-sprite-layers.md)
  rule for `LOGICAL_ACTIVITY_*` values; future readers of the
  activity-taxonomy table would have no entry to find when grepping for
  the state.
- **D — Keep the `REACTING` name; only swap routing to no-op
  (rejected).** Smaller blast radius (no GPU constant rename, no
  shader edit beyond the routing change). Rejected: the name
  "REACTING" overlaps the React rendering cluster
  ([Animation react](../context/20-animation-react.md)) and the
  [Reaction ability](../context/21-combat-event-resolution.md) family
  of ability data; every future reader hits the collision. The rename
  cost is one generator regen + a handful of references to update,
  which the activity-taxonomy refactor (PRs #45/#46/#47) demonstrated
  is mechanical and low-risk.

## Implementation queue

Filed as separate atomic tasks on `import-godot-game`:

1. Generator change: add a `transient` routing to
   `tools/gen_activity_taxonomy.py` (no-op dispatch entry, same shape
   as `visualizer`).
2. YAML edit: rename the row to `PREEMPTIVE_COUNTER`, change
   `routing: react_overlay` → `routing: transient`, regen
   `CONTEXT.md`'s generated table.
3. GLSL edit: rename the constant in `combat_common.glslinc` and the
   two references in `stage_compute.glsl`
   (`check_pre_damage_reactions`, state-handler at `:985`).
4. Translator edit: delete `_translate_react_overlay` from
   `src/gpu/ActivityTranslator.gd`. (The generated dispatch shell
   already routes through the new `_translate_transient`.)
5. Test pass: run the full GPU test suite; baseline failures
   (`GPUThrashTest`, `GPUTeleportTest`) pre-date this work and stay as
   they were.

## Out-of-scope follow-ups (filed separately)

- **Counter (`REACT_COUNTER`) plays no animation today.**
  `stage_damage.glsl:102-130` stuffs counter damage straight into
  `U_PENDING_DAMAGE` as a symmetric HP exchange. ROM plays a full
  counter-attack animation. Faithful implementation would reuse the
  `PREEMPTIVE_COUNTER` gateway shape (same one-tick → ACTING).
- **Hamedo's IDLE-gate is too restrictive.** Today's
  `check_pre_damage_reactions` checks `defender_state ==
  LOGICAL_ACTIVITY_IDLE`. Units are rarely IDLE in active combat, so Hamedo
  almost never triggers. ROM's gate is closer to "can the defender act?"
  (excluding Sleep/Stop/Petrify/Charging/Dying); promoting the gate
  is its own change.
- **Reaction routing on `CombatLoop` hardcodes `sprite_type = "type1"`**
  in three sites (`_trigger_physical_reaction`,
  `_trigger_projectile_reaction`, `_on_ability_react`). TYPE2 / chocobo /
  monster targets resolve the wrong React slot. Independent bug from this
  ADR. (#50; the routing was folded onto `CombatLoop` from
  `tests/managers/ReactionManager.gd` per #52.)
