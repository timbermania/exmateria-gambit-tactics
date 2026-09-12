# Stage 2b — Phase 2.b Implementation Plan

**As of:** 2026-05-30
**Branch:** `compute-shader-status-doc`
**Prerequisite:** Phase 2.a (instrumentation only) already landed.
**Parent plan:** [`stage_2b_implementation_plan.md`](stage_2b_implementation_plan.md)

This document specifies how to convert the inline action execution inside
`execute_gambit_action()` into a deferred-execution model where the
"decide" code only records the chosen action and a downstream
`apply_pending_action()` runs the bodies. After this phase lands, Phases
3–5 can extract `stage_attack` / `stage_spell` / `stage_pathfind` cleanly
by moving the `apply_pending_action()` branches into their own files,
each gated by `U_PENDING_ACTION_TYPE`.

---

## 1. The blocker, restated

`execute_gambit_action()` returns `bool` to its caller
`evaluate_gambits_up_to()`. On `false`, the caller tries the next gambit
slot (the "gambit fallthrough"). Three things can produce `false`:

1. `final_target < 0 && action_type != ACTION_WAIT` — checked **before**
   any action execution. **Cheap to keep sync.**
2. `start_spell()` resets state to STATE_IDLE after `read_unit_next`
   shows it. Failure modes:
   - **MP < cost.** Cheap to pre-check.
   - **Projectile LOS blocked AND unit can't move closer.** Expensive
     (involves `has_line_of_sight_arc` + `get_next_step`).
   - **`find_cast_position()` returns `-1`** when out of range.
     Expensive (tile scan around target).
3. The same chain on `ACTION_ITEM` when `final_target >= 0` and the item
   acts like a projectile spell.

The expensive failure detection is what blocks pure deferral. We can
**preserve gambit fallthrough for the cheap failure mode (MP)** and
**accept a 1-tick re-evaluation delay for the expensive ones (LOS, no
cast position).** This is the only behavioral concession in Phase 2.b.

---

## 2. Behavioral delta (documented and accepted)

**Before Phase 2.b:** if gambit-0 chose a spell that fails because the
caster has LOS blocked and can't move closer, the caster immediately
tries gambit-1 the same tick.

**After Phase 2.b:** in that same scenario, the caster commits to
STATE_MOVING_TO_CAST or STATE_IDLE for the current tick. On the next
tick (TICKS_GAMBIT_REEVAL or TICKS_PATH_RETRY later), it re-evaluates
and may pick gambit-1.

The MP-failure case is unchanged — immediate fallthrough.

**Quantifying the cost:** the delayed scenarios are rare (require a
target out of LOS / unreachable cast position). For the common cases
(MP shortage, no target, target dead) gambit fallthrough is identical.
Determinism is preserved — same seed produces same result, just one
tick of latency on the affected branch.

`GPUSeedReproTest` golden snapshots will need a one-time refresh after
this lands. That's expected. Document it in the test's preamble.

---

## 3. The new control flow

### 3.1 `execute_gambit_action()` — synchronous decision only

```glsl
bool execute_gambit_action(int battle_id, int unit_id, int gambit_slot,
                            int condition_target, int override_target) {
    // (existing) Resolve final_target, action_type, action_id, action_target_type.
    // (existing) Bail on final_target < 0 && action_type != ACTION_WAIT.
    // (existing) Write U_CURRENT_GAMBIT, clear U_PREV_MOVE_POS.

    // NEW: for SPELL/ABILITY/ITEM, run the cheap pre-validation only.
    // Returns false on MP shortage — gambit fallthrough preserves today.
    if (action_type == ACTION_SPELL || action_type == ACTION_ABILITY
        || (action_type == ACTION_ITEM && final_target >= 0)) {
        if (!spell_pre_validate(battle_id, unit_id, final_target,
                                action_id, action_type)) {
            // Cheap failure (MP) — gambit fallthrough as before.
            write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_NONE);
            return false;
        }
    }

    // Record the chosen action; carriers (U_TARGET, U_CASTING_ABILITY_ID,
    // U_CAST_TARGET) are written here so apply_pending_action sees them.
    write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, action_type);
    record_action_carriers(battle_id, unit_id, action_type,
                           final_target, action_id);
    return true;
}
```

### 3.2 `spell_pre_validate()` — cheap MP check only

```glsl
// Returns true if spell COULD start (MP available + target valid).
// Does NOT call find_cast_position or has_line_of_sight_arc — those are
// expensive and deferred to apply_pending_action. False positives (spell
// starts then fails on cast position) cause a 1-tick re-evaluation delay
// — accepted in Phase 2.b. False negatives are not possible.
bool spell_pre_validate(int battle_id, int unit_id, int target_id,
                        int ability_id, int action_type) {
    int mp_cost = get_ability_mp_cost(ability_id);
    if (get_mp(battle_id, unit_id) < mp_cost) return false;
    if (target_id < 0 && action_type != ACTION_WAIT) return false;
    return true;
}
```

### 3.3 `record_action_carriers()` — write the scratch fields

Carriers are written *before* the action executes so
`apply_pending_action` can read them later in the same tick (Phase 2.b)
or in a separate sub-stage (Phase 3+).

```glsl
void record_action_carriers(int battle_id, int unit_id, int action_type,
                            int final_target, int action_id) {
    switch (action_type) {
        case ACTION_ATTACK:
            write_unit(battle_id, unit_id, U_TARGET, final_target);
            break;
        case ACTION_SPELL:
        case ACTION_ABILITY:
        case ACTION_ITEM:
            write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, action_id);
            write_unit(battle_id, unit_id, U_CAST_TARGET, final_target);
            break;
        case ACTION_MOVE_TO:
            // action_id encodes packed dest coords (dest_x*256 + dest_z)
            // Decoded inside apply_pending_action -> commit_move_to.
            write_unit(battle_id, unit_id, U_DEST_X, action_id / 256);
            write_unit(battle_id, unit_id, U_DEST_Z, action_id % 256);
            break;
        case ACTION_WAIT:
            // No carriers needed.
            break;
    }
}
```

### 3.4 `apply_pending_action()` — the deferred dispatcher

Called once near the bottom of `compute_unit_state()`, after gambit eval
returns. Reads `U_PENDING_ACTION_TYPE` and runs the original action body.

```glsl
void apply_pending_action(int battle_id, int unit_id) {
    int pending = read_unit_next(battle_id, unit_id, U_PENDING_ACTION_TYPE);
    if (pending == ACTION_NONE) return;

    switch (pending) {
        case ACTION_ATTACK: {
            int target = read_unit_next(battle_id, unit_id, U_TARGET);
            execute_attack_gambit(battle_id, unit_id, target);
            break;
        }
        case ACTION_SPELL:
        case ACTION_ABILITY: {
            int target = read_unit_next(battle_id, unit_id, U_CAST_TARGET);
            int ability_id = read_unit_next(battle_id, unit_id, U_CASTING_ABILITY_ID);
            start_spell(battle_id, unit_id, target, ability_id);
            // No `if state == STATE_IDLE` check here — start_spell handles
            // its own failure paths inline. Unit re-evaluates next tick.
            break;
        }
        case ACTION_ITEM: {
            int target = read_unit_next(battle_id, unit_id, U_CAST_TARGET);
            int ability_id = read_unit_next(battle_id, unit_id, U_CASTING_ABILITY_ID);
            if (target >= 0) {
                start_spell(battle_id, unit_id, target, ability_id);
            }
            break;
        }
        case ACTION_WAIT:
            write_unit(battle_id, unit_id, U_STATE, STATE_IDLE);
            write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
            break;
        case ACTION_MOVE_TO: {
            // Reconstruct packed action_id from decoded carriers.
            int dest_x = read_unit_next(battle_id, unit_id, U_DEST_X);
            int dest_z = read_unit_next(battle_id, unit_id, U_DEST_Z);
            execute_move_to_gambit(battle_id, unit_id, dest_x * 256 + dest_z);
            break;
        }
    }
}
```

### 3.5 `compute_unit_state()` — call site

```glsl
// Existing tail:
if (!evaluate_gambits(battle_id, unit_id)) {
    write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
    write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_NO_GAMBIT);
    int target = read_unit(battle_id, unit_id, U_TARGET);
    record_decision(battle_id, unit_id, REASON_NO_GAMBIT, STATE_IDLE, target);
} else {
    // NEW: gambit committed an action — apply it.
    apply_pending_action(battle_id, unit_id);
}
```

Note: `apply_pending_action` only fires on the IDLE-state gambit eval.
The mid-movement higher-priority re-eval (`STATE_MOVING` /
`STATE_MOVING_TO_CAST` with `evaluate_gambits_up_to`) also needs it.

```glsl
// State-machine dispatch — add apply_pending_action on success here too:
if (state == STATE_MOVING || state == STATE_MOVING_TO_CAST) {
    int current_gambit = read_unit(battle_id, unit_id, U_CURRENT_GAMBIT);
    if (current_gambit > 0 && evaluate_gambits_up_to(battle_id, unit_id, current_gambit)) {
        apply_pending_action(battle_id, unit_id);  // NEW
        return;
    }
}
```

---

## 4. Removing the inline calls

After `apply_pending_action()` is wired up:

- The `switch (action_type)` inside `execute_gambit_action()` is **deleted**.
- `execute_gambit_action()` ends after writing the carriers + PENDING.
- `execute_attack_gambit()`, `start_spell()`, `execute_move_to_gambit()`
  stay where they are — only their *call site* moves.

`start_spell`'s existing failure handling (STATE_IDLE + REASON_SPELL_FAILED
writes) is unchanged. It now produces a "spell failed silently this tick;
re-evaluate next tick" outcome, which is the documented 1-tick delay.

---

## 5. Reads/writes audit — the 84-int struct

| Field | Pre-Phase-2b writer | Post-Phase-2b writer |
|---|---|---|
| `U_PENDING_ACTION_TYPE` | (cleared in compute_unit_state, set by Phase 2.a in execute_gambit_action's switch) | Same. Now consumed by `apply_pending_action`. |
| `U_TARGET` | `execute_attack_gambit` and elsewhere | Pre-written by `record_action_carriers` for ATTACK; `execute_attack_gambit` may overwrite during apply. |
| `U_CASTING_ABILITY_ID` | `start_spell` | Pre-written by `record_action_carriers` for SPELL/ABILITY/ITEM. `start_spell` re-writes (no-op for the same value). |
| `U_CAST_TARGET` | `start_spell` | Same as above. |
| `U_DEST_X/Z` | `start_spell`, `execute_move_to_gambit`, `execute_attack_gambit` | `record_action_carriers` writes for MOVE_TO. Other writers unchanged. |
| `U_CURRENT_GAMBIT` | `execute_gambit_action` | Unchanged. |
| `U_PREV_MOVE_POS` | `execute_gambit_action` | Unchanged. |

Pre-writing carriers is **safe** because Phase 2.a already established that
write order in `execute_gambit_action` is decided before the action body
runs. The action body (now in `apply_pending_action`) reads the same
fields the inline body read.

**One subtlety:** `execute_gambit_action`'s pre-existing bail-out for
`final_target < 0 && action_type != ACTION_WAIT` runs **before** the
carriers are written. That stays — `record_action_carriers` is only
called on the success path.

---

## 6. Migration steps

### 6.0 Snapshot baseline

Cold-cache `PipelineTest.gd` and `ShaderCompileBench.gd`. Record
`stage_compute` pipeline_create time. This is the baseline against
which Phase 2.b's overhead is measured.

### 6.1 Add `spell_pre_validate()` and `record_action_carriers()`

Insert near `start_spell`'s definition site in `stage_compute.glsl`
(GLSL requires definitions before callers — both will be called by
`execute_gambit_action` later in the file).

### 6.2 Add `apply_pending_action()`

Insert near `complete_spell_cast` so it's defined before
`compute_unit_state` calls it. Implementation per §3.4.

### 6.3 Rewrite `execute_gambit_action()`

Replace the entire `switch (action_type)` body (lines 1187–1216 in the
current shader) with the pre-validate + carrier-write + return-true
sequence per §3.1.

### 6.4 Wire `apply_pending_action()` into `compute_unit_state()`

Two call sites per §3.5: after the success branch of
`evaluate_gambits()` (IDLE path), and after the success branch of
`evaluate_gambits_up_to()` (movement re-eval path).

### 6.5 Re-run PipelineTest

Confirm all 5 stages compile cleanly. Cold-cache stage_compute
pipeline_create should be within ±10% of the Phase 2.a baseline (we
haven't reduced SPIR-V volume yet — that comes in Phases 3–5 when the
file actually splits).

### 6.6 Re-run smoke combat tests

`GPUFormula01Test` (simplest), `GPUMeleeCombatTest`, `GPUSpellCombatTest`.
Document any test that diverged from its pre-2.b result; expected
divergences are golden-snapshot tests (`GPUSeedReproTest`) and tests that
exercise the LOS-blocked-spell-fallthrough scenario.

---

## 7. Rollback plan

If Phase 2.b regresses a test that did NOT exercise the documented
1-tick-delay scenario, revert is straightforward — the changes are
localized to two new functions + the rewritten `execute_gambit_action`
+ two call sites in `compute_unit_state`. `git revert` of the single
commit returns the tree to Phase 2.a.

If `GPUSeedReproTest` is the only regression, refresh its golden
snapshot rather than reverting (the delay is intentional behavior).

---

## 8. What this unlocks

After Phase 2.b:

- `execute_gambit_action()` no longer needs `execute_attack_gambit`,
  `start_spell`, or `execute_move_to_gambit` in its SPIR-V — those are
  reachable only via `apply_pending_action()`.
- `apply_pending_action()` is a small dispatcher (~30 lines) that calls
  one of ~5 action bodies. Phase 3 can move the ATTACK branch +
  `execute_attack_gambit` into `stage_attack.glsl` by:
  1. Copy `apply_pending_action()`'s ATTACK case into `stage_attack`'s
     `main()`, gated by `U_PENDING_ACTION_TYPE == ACTION_ATTACK`.
  2. Delete the ATTACK case from `apply_pending_action()` in stage_compute.
  3. Wire `stage_attack.glsl` into the dispatch loop in
     `GPUBatchSimulator._run_tick()`.
- Same pattern for SPELL/ABILITY/ITEM → `stage_spell`, and MOVE_TO +
  pathfinding → `stage_pathfind`.

The deferral itself doesn't reduce compile time. The follow-on
extractions do — each sub-stage compiles only the action bodies it
actually executes.
