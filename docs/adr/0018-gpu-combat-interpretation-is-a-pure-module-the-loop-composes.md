# GPU combat interpretation is a pure module; the per-tick loop composes, not inherits

## Status

Accepted

Verified 2026-08-28 — the shape is built and standing (`src/gpu/GPUCombatInterpreter.gd`,
`src/gpu/CombatLoop.gd`, `src/gpu/CombatHost.gd`, `tests/GPUCombatInterpreterTest.gd`).
Two decisions ship differently from the shape this ADR first landed: dec. 1's event
vocabulary is not the enum that shipped, and dec. 11 (originally "no shared base")
was superseded through its own escape clause. Both stand below as they ship, with
the originals under **Considered options**. Dec. 6 — a staging plan — is deleted
rather than restated; its number is retired. See `AUDIT.tsv` and `audit-notes/0018.md`.

## Context

ADR-0017 carved one slice — movement — out of the per-frame "GPU snapshot → game
reaction" loop into a pure `GPUMovementInterpreter`, leaving `GPUVisualBridge` to
*apply* the result. The rest of that loop stayed where it was:
`GPUCombatTestBase._check_state_changes`, a nine-step sequence (`_process_death`,
`_process_spell_cast`, `_process_projectile_trigger`, `_process_hp_change`,
`_process_mp_change`, `_process_stat_changes`, …) where each step both **detects** a
change (pure: `current_hp != prev_hp`, `CHARGING → ACTING`) and **applies** it
(impure: `unit_stats.die()`, `hp_changed.emit()`, `effect_manager.stop_charge_vfx()`,
`_rlog.log_*`). None of it could be exercised without a `RenderingDevice`, live `Unit`
nodes, and a scene tree — and it all lived in a class named `GPUCombatTestBase` that
the production `GPUArena` scene `extends`.

This ADR generalises ADR-0017's split to the whole loop, and fixes the misplacement
that made production inherit a test base.

## Decision

1. **`GPUCombatInterpreter` owns the interpretation.** A pure `RefCounted`, sibling to
   `GPUMovementInterpreter`. It reads a unit's per-frame snapshot and returns the
   frame's **ordered list of typed `CombatEvent`s**. The shipped vocabulary is
   `EventKind`: `DIED`, `HP_CHANGED{delta, was_heal, killed}`, `MP_CHANGED`,
   `CAST_BEGAN{ability_id, target, defers_trap}`, `ACTION_COMMITTED`,
   `STATE_CHANGED`, `POSITION_CHANGED`, `PROJECTILE_FIRED`, `STAT_CHANGED`. Events
   carry the payload appliers need, so the pump never re-reads the snapshot.
   `ACTION_COMMITTED` is the commit witness for a pure attack as well as an ability,
   independent of host-frame state sampling (#93). There is deliberately no
   `CastEnded` and no `ChargeBegan`/`ChargeEnded`: charge VFX is driven from
   `CombatLoop` off `STATE_CHANGED`.

2. **One frame-diff, not N independent interpreters.** The steps are *not*
   independent — `_process_spell_cast` produced a `spell_cast_triggered` flag that
   `_process_state_transition` consumed, and `_process_death` short-circuited the rest
   of the unit's frame. The interpreter therefore sees the whole frame and **owns the
   precedence**: `DIED` suppresses the unit's other events, and `STATE_CHANGED`
   carries `cast_began_this_frame` so the transition knows a cast opened it. Those
   cross-slice rules — the part most likely to carry bugs — move onto the test surface
   instead of staying as loop control.

3. **The read rule: battle state lives only in the GPU.** The interpreter may read the
   snapshot (the sole battle-state interface — never a CPU-side mutable mirror) and
   **immutable reference data that is itself mirrored into the GPU**
   (`AbilityDatabase` weapon-range / formula, the same constants `GPUAbilityLoader`
   packs into the ability buffer). It may **not** touch live `Unit` nodes, terrain, or
   `RenderingDevice` — those belong to the apply pump. So `CAST_BEGAN` carries a
   `defers_trap` flag derived from the immutable ability record; the pump reads world
   positions to build the TRAP payload. Generalised project-wide by ADR-0031.

4. **No invented decision-state in the interpreter — `CAST_STEP_ID` lives on the
   GPU.** The `_spell_cast_active` boolean latch served two roles: a *detection* dedup
   ("have I already fired CastBegan for this cast") and *animation-playback
   coordination* ("a cast animation is on screen"). The detection role was a second CPU
   source of truth for whether a cast was live; that role is retired by the monotonic
   `U_CAST_STEP_ID` unit field (twin of `MOVE_STEP_ID`, offset 85 in
   `combat_common.glslinc`), incremented by the shader on each `→ACTING` transition,
   which the interpreter dedups against (`cast_step_id` in the snapshot) exactly as
   the movement interpreter dedups against `move_step_id`. The interpreter therefore holds only **sample buffers**
   (`_prev_hp`, …, last frame's GPU values for edge detection), never a latch. The
   latch itself **survives in the pump** for its second role — a live Dictionary on
   `CombatLoop`, read around `_update_unit_animation` and the effect manager's
   `spawn_charge_vfx` / `stop_charge_vfx` — because "is a cast animation playing" is
   CPU *presentation* state the GPU neither has nor should track. It is not battle
   state, so it does not violate the read rule. Adding the field cost one int
   (`UNIT_SIZE` 85 → 86 at the time; the struct has kept growing since and now
   declares 98) plus a `SHADER_VERSION` bump with the GDScript layout regenerated —
   see ADR-0001 and the combat-buffer-layout parity check.

5. **`CombatLoop` composes; it is not inherited.** The per-tick pump (`step_tick` →
   interpret both interpreters → apply → projectiles → victory), the GPU simulator,
   the state reader, and the managers live in a `CombatLoop` node that emits
   high-level signals. Both `GPUArena` and `GPUCombatTestBase` *hold* a `CombatLoop`;
   production `GPUArena` does not `extends GPUCombatTestBase`. The test base keeps its
   config / assertion hooks (`get_team0_unit_configs`, `on_hp_changed`, …)
   **byte-identical**, implemented by feeding the loop units and subscribing to its
   signals — which is why the 74 test files that `extends GPUCombatTestBase` did not
   change.

7. **`GPUMovementInterpreter` is unchanged.** Its `MoveStep` is applied by
   `GPUVisualBridge` against terrain/tiles, which no other slice touches; merging it
   in would drag the tile concern into the diff. `CombatLoop` composes both
   interpreters side by side. ADR-0017 stands; ADR-0002 (string-keyed snapshot) is not
   re-opened — combat events are derived values, not a typed snapshot view.

8. **`CombatLoop` is fat: it owns the whole game-visible battle.** GPU simulator /
   state reader / distance field, battle setup, both interpreters + `GPUVisualBridge`,
   the **effect manager** (`src/effects/EffectManager.gd` — per-unit charge VFX,
   per-caster deferred TRAP, awaited cleanup) and the **projectile manager**
   (`src/projectiles/ProjectileManager.gd` — ADR-0032's pure visualizer), the per-tick
   pump, the **animation apply** (`_update_unit_animation`, `_start_attack_animation`,
   cast-complete / effect-spawn), the **reaction routing**
   (`_trigger_physical_reaction` from the `POST_GENERIC_ATTACK` SEQ side-effect,
   `_trigger_projectile_reaction` from `projectile_landed`, `_on_ability_react` /
   `_on_refresh_tile` from the effect-keyframe signals), and victory. Reaction routing
   is *inline* — it carries no state and reads every input from the loop
   (`_last_damage_tick`, `_last_evade_type`, `_combat_interp`), so it is methods, not a
   manager. The other two earn their names and stay composed classes next to their
   dependencies: `EffectManager` owns real lifecycle (`_pending_trap`,
   `_active_charge_effects`, awaited cleanup), `ProjectileManager` owns the in-flight
   list and the ADR-0032 visualizer math.

9. **Per-event signals.** `CombatLoop` emits one signal per semantic event
   (`unit_died`, `hp_changed`, `state_changed`, `mp_changed`, `stat_changed`,
   `cast_began`, `projectile_fired`, `victory`, and since then `action_committed` and
   `timed_out`) rather than one generic `combat_event`. A host connects to the ones it
   needs instead of subscribing to a firehose and re-matching on kind.

10. **Test-config translation stays host-side.** `_build_gpu_config` (test `cfg` dict →
    GPU battle params) lives in the host, so `CombatLoop.start_battle` speaks `Unit`
    nodes + a battle spec, never test dict shapes — which is what lets the
    roster-driven `GPUArena` reuse the same interface as the config-driven test base.

11. **The two hosts share a mechanics-only base.** `src/gpu/CombatHost.gd` is a
    `Node3D` that both `GPUArena` (production) and `GPUCombatTestBase` (test)
    `extends`. It holds **only** the accessor/sync mechanics and the shared data
    holders (the composed `CombatLoop`, the terrain index, the unit array) — the
    duplication that appeared once tests began subclassing *each* host, so each host
    had to re-expose the loop's battle state to its own subclasses verbatim. It
    carries **no policy**: loop creation and wiring, `_rlog`, the `on_*` assertion
    hooks, victory/quit behaviour, and the production UI all stay in the two hosts,
    which diverge sharply. The base must not grow past mechanics; a policy-bearing
    `CombatHost` re-introduces exactly the coupling dec. 5 removed.

## Considered options

- **`CastEnded`, `ChargeBegan`, `ChargeEnded` as interpreter events** — named by the
  original dec. 1, never built. Charge VFX is presentation that the pump drives off
  `STATE_CHANGED`, which is the same information without a second event pair to keep
  in sync. `MpSpent` was likewise generalised to `MP_CHANGED`, because the diff
  reports any MP difference, not only spending. A citation of "ADR-0018's event list"
  is a citation of dec. 1 as it now reads, not of the original nine names.

- **Independent sibling hosts, no shared base** — shipped, then superseded by dec. 11.
  The original decision named the very class that now exists and rejected it: "a
  `CombatHost` base would just re-introduce the shared-base coupling C8 removes." It
  also carried its own escape clause — "extract one later only if real duplication
  appears" — and the duplication appeared: both hosts exposed the loop's battle state
  to their own subclasses, so that accessor surface plus the host-owned unit/terrain
  holders was duplicated verbatim. Dec. 11 is that clause being exercised, under the
  mechanics/policy constraint the original rejection was really protecting.

- **A thin `CombatLoop` that only pumps, leaving the apply in the base.** Rejected: it
  would leave the host-coupled apply tangle in the test base, so repointing `GPUArena`
  off the inheritance would not actually decouple production.

- **A `ReactionManager` composed alongside the other two, under `tests/managers/`.**
  Shipped in the original C7/C8 landing, then folded into `CombatLoop` as inline
  routing methods — it carried no state and read every input from the loop. The other
  two managers moved out of `tests/managers/` to `src/effects/` and `src/projectiles/`
  at the same time.

- **A unified "Combat action queue" over the three managers.** Rejected: a per-caster
  slot, a per-unit `Node` lifecycle, and a per-tick visualizer do not share an
  ordered-side-effects shape. A future review that re-derives the queue from the apply
  pump's surface should treat this rejection as load-bearing.

- **Folding movement into the combat interpreter.** Rejected: the terrain-apply
  asymmetry (dec. 7) is why they stay siblings.

## Consequences

- The reaction rules — death-suppression, cast→transition ordering, damage-vs-heal
  attribution, the cast dedup — are unit-tested by feeding `(prev, current)` snapshots
  and asserting the event list, with no GPU, no scene, no tiles. The failure modes
  CLAUDE.md warns about (stale GPU fields, a reaction firing twice) get regression
  coverage that needs no `RenderingDevice`.
- The emitted event stream is a deterministic function of the snapshot, so the
  regression log (`_rlog`) is a projection of the events rather than a parallel
  hand-written trace — the event list *is* the regression artifact the GPU tests
  assert against.
- Production does not inherit a test base; the combat loop is reusable and
  independently testable because it is composed behind a `Node` interface, not
  reachable only by subclassing one.
- A future review should not re-flag the `CombatLoop` / `GPUCombatTestBase` split as
  duplication: the deletion test keeps `CombatLoop` — delete it and the pump + manager
  wiring reappear in both `GPUArena` and the test base.

## Verification

- `tests/GPUCombatInterpreterTest.gd` — pure GDScript, no `RenderingDevice`: death
  precedence, one-frame event order, and three arms on `CAST_BEGAN` (once per cast
  step, none without an ability, none on a charge with no step bump).
- The 74 test files that `extends GPUCombatTestBase` are the standing evidence for
  dec. 5's unchanged-hook-surface promise.
- Nothing asserts dec. 11's mechanics/policy split — that `CombatHost` carries no
  policy is the file's own claim. See `AUDIT.tsv`.
