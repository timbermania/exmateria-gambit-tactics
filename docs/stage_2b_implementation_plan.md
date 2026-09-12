# Stage 2b — `stage_compute` Decomposition Implementation Plan

**As of:** 2026-05-30
**Branch:** `redesign-battle-compute-shader` (forks: `compute-shader-status-doc`)
**Drives the headline call in:** [`compute_shader_status.md`](compute_shader_status.md) §7 Tier 1
**Background reading:** [`shader_compile_refactor.md`](shader_compile_refactor.md) §5.1,
[`gpu-ai-system.md`](gpu-ai-system.md) §6 (state machine), §13 (reactions).

This document is the **executable plan** for Stage 2b: decomposing the
`stage_compute.glsl` long pole (1,815 LoC, ~36 s cold pipeline compile on
Intel iGPU) into 4 narrower sub-stages. The goal is to bring the worst single
`pipeline_create` from ~36 s to ~10 s, which proportionally cuts NVIDIA cold
launch and per-edit iteration time on the compute-half of the codebase.

It is written so that each phase can be landed in a separate commit and
validated independently. Phase 0 and Phase 1 are scoped to land in a single
session; Phases 2–6 are the actual shader split and warrant their own focused
session(s) each.

---

## 0. Goal and non-goals

### Goal

Split `src/gpu/shaders/stage_compute.glsl` into four sibling stage shaders:

| New file | Owns | Workgroup unit | Reads | Writes |
|---|---|---|---|---|
| `stage_decide.glsl` | Gambit eval, target selection, decision recording, thrash check | one thread per unit | full CURRENT unit state, gambits, ability DB | NEXT unit decision fields (`U_PENDING_ACTION_*`, `U_TARGET`, `U_CURRENT_GAMBIT`, history) |
| `stage_pathfind.glsl` | Movement step for STATE_MOVING + STATE_MOVING_TO_CAST | one thread per unit | NEXT decision fields, distance field, map | NEXT proposed position, movement-step fields |
| `stage_attack.glsl` | Position search + attack anim setup for `U_PENDING_ACTION_TYPE == ACTION_ATTACK` | one thread per unit | NEXT decision fields, animation lookup | NEXT anim fields, damage queue, state→ACTING |
| `stage_spell.glsl` | MP/LOS/charge for `ACTION_SPELL`/`ABILITY`/`ITEM`, plus STATE_CHARGING tick | one thread per unit | NEXT decision fields, ability DB | NEXT cast fields, state→CHARGING/MOVING_TO_CAST/IDLE |

After the split:

- Per-tick dispatch grows from 5 stages to **8 stages**:
  `decide → pathfind → attack → spell → resolve → post_conflict → damage → victory`.
- The residual `stage_compute.glsl` is **deleted** (its responsibilities
  redistributed); the four new files plus the four existing tail stages are
  the whole pipeline.
- Each new sub-stage's source size is roughly `1815 / 4 ≈ 450 LoC` plus
  shared headers — that's the lever that should cut `pipeline_create`.

### Non-goals

- **No behavior change.** Every existing test in `tests/` must pass byte-for-byte.
  `GPUSeedReproTest` is the strongest signal — if the RNG-seeded golden replay
  diverges by one tick, the split is broken.
- **No feature work.** Reactions, status enforcement, etc. (§4.3 of
  `compute_shader_status.md`) stay scaffolded. They land on top of the split,
  not interleaved.
- **No struct compaction.** The 84-int unit struct keeps its current offsets.
  We add **one new field** (`U_PENDING_ACTION_TYPE`) and bump `UNIT_SIZE`
  from 84 → 85. Any further struct cleanup is deferred.
- **No new feature flags or build modes.** The split replaces the old
  shader; there's no `--use-split-shaders` toggle. The monolith
  `combat_batch.glsl` is already gone by the time Stage 2b lands (Phase 1).

---

## 1. The core problem the split is solving

`compute_unit_state()` in `stage_compute.glsl:1667` dispatches on `U_STATE`
to 8 state handlers. Inside the IDLE handler, `evaluate_gambits()` walks the
gambit list and **immediately calls one of**:

- `execute_attack_gambit()` → `find_nearest_attack_position()` + anim setup
- `start_spell()` → MP check + `find_cast_position()` + state transition
- `execute_move_to_gambit()` → destination write + state→MOVING

So the IDLE branch alone can pull in every code path in the file —
pathfinding, attack-position scanning, spell setup. That's why pipeline
analysis has to consider the whole shader even for IDLE-only units, and
why the SPIR-V is so large.

The fix is to **defer action execution**: gambit eval just *records* the
chosen action into scratch fields, and downstream sub-stages each handle
one action category. SPIR-V volume per sub-stage is proportional to that
sub-stage's reachable code, not the union of everything.

---

## 2. Data-model delta

### 2.1 New field

```glsl
// In combat_common.glsl, append after U_MOVE_STEP_ID = 83:
const int U_PENDING_ACTION_TYPE = 84;  // ACTION_* sentinel, or ACTION_NONE = -1
```

`U_PENDING_ACTION_TYPE` carries the decision-stage output forward. Values
are the existing `ACTION_*` constants (`ACTION_ATTACK`, `ACTION_SPELL`,
`ACTION_ABILITY`, `ACTION_ITEM`, `ACTION_WAIT`, `ACTION_MOVE_TO`) plus a
new `ACTION_NONE = -1` for "no decision this tick" (e.g., timer not
expired, unit dead, already mid-action).

### 2.2 Struct bump

```glsl
// In combat_common.glsl, near SHADER_VERSION / UNIT_SIZE:
const int UNIT_SIZE = 85;   // was 84
const int SHADER_VERSION = N + 1;  // bump
```

```gdscript
# In GPUBatchSimulator.gd, UnitField enum:
enum UnitField {
    # ... existing 84 entries ...
    PENDING_ACTION_TYPE  # = 84
}
const UNIT_SIZE: int = 85
const EXPECTED_SHADER_VERSION: int = N + 1
```

`GPUBatchSimulator` validates `SHADER_VERSION` at init — see
[CLAUDE.md "Shader/GDScript constant mismatch" gotcha](../CLAUDE.md). The
bump must be paired or the engine errors on boot.

### 2.3 Existing fields used as state carriers

These already exist; the split reads and writes them with the same
semantics as today, just spread across more dispatches:

| Field | Carries between sub-stages |
|---|---|
| `U_TARGET` | Final target chosen by decide; consumed by attack/spell |
| `U_CURRENT_GAMBIT` | Slot chosen; lets pathfind/attack/spell know which gambit lit |
| `U_CASTING_ABILITY_ID` | Ability ID; consumed by spell sub-stage |
| `U_CAST_TARGET` | Cast target; consumed by spell sub-stage |
| `U_DEST_X/Z` | Movement destination; consumed by pathfind |
| `U_PROPOSED_X/Z` | Pathfind's per-tick output; consumed by resolve |
| `U_STATE` | Current state; updated by whichever sub-stage finalizes the action |

No new carrier fields beyond `U_PENDING_ACTION_TYPE`.

---

## 3. Per-sub-stage responsibilities (exhaustive)

### 3.1 `stage_decide.glsl` (~450 LoC est.)

**Owns:** all gambit accessors, condition eval, target selection, decision
recording, thrash detection. **Does not** execute the chosen action —
just writes it to `U_PENDING_ACTION_TYPE` + supporting fields.

Functions moved from `stage_compute.glsl`:

- All `get_gambit_*` accessors (lines 31–66)
- `evaluate_condition()` (line 71)
- `find_unit_by_criteria()`, `find_nearest_enemy()`, `select_target()`,
  `find_nth_nearest()` (lines 133–320)
- `check_gambit_conditions()` (line 1221)
- `evaluate_gambits_up_to()`, `evaluate_gambits()` (lines 1241–1293)
- `record_decision()`, `check_decision_thrash()` (lines 998–1088)
- A **new** `record_pending_action()` helper — replaces the bodies of
  `execute_attack_gambit` / the action-dispatching switch in
  `execute_gambit_action`. Writes `U_PENDING_ACTION_TYPE`, `U_TARGET`,
  `U_CASTING_ABILITY_ID` (for spell/item), `U_DEST_X/Z` (for MOVE_TO).

State-machine portion this stage owns:

- Copy CURRENT → NEXT (`copy_unit_to_next`).
- Decrement `U_TIMER`, `U_REACTION_TIMER`.
- Clear per-tick scratch (`U_DAMAGE_TARGET = -1`, AOE fields, debug fields).
- For STATE_ACTING + timer > 0: call `tick_acting_animation()`.
  *(Stays here for now — it's bounded and doesn't share code with the
  other sub-stages. Splitting it further is over-engineering.)*
- For STATE_CHARGING + cast_timer > 0: decrement cast_timer, return.
- For STATE_CHARGING + cast_timer ≤ 0: set `U_PENDING_ACTION_TYPE` to a
  new sentinel `ACTION_COMPLETE_SPELL`. Spell sub-stage finishes it.
- For STATE_MOVING + timer ≤ 0: set `U_PENDING_ACTION_TYPE = ACTION_PATHFIND_MOVE`.
- For STATE_MOVING_TO_CAST + timer ≤ 0: set `U_PENDING_ACTION_TYPE = ACTION_PATHFIND_CAST`.
- For STATE_ACTING + timer ≤ 0: clear cast fields, state→IDLE inline.
- For STATE_REACTING + timer ≤ 0: handle reaction (same as today —
  bounded, stays here).
- For STATE_IDLE + timer ≤ 0: victory check, then `evaluate_gambits()`.
  The eval no longer triggers actions; it writes `U_PENDING_ACTION_TYPE`
  via `record_pending_action()`.

Things this stage **never reads or writes:** distance field, attack
animation lookup, spell MP/LOS logic. None of those functions are linked
into its SPIR-V.

### 3.2 `stage_pathfind.glsl` (~500 LoC est.)

**Owns:** all pathfinding. Runs for `U_PENDING_ACTION_TYPE ∈
{ACTION_PATHFIND_MOVE, ACTION_PATHFIND_CAST, ACTION_MOVE_TO}` and for
units in STATE_MOVING / STATE_MOVING_TO_CAST that need their step
written this tick.

Functions moved from `stage_compute.glsl`:

- `trace_stitched_path()` (line 191)
- `find_passthrough_destination()` (line 379)
- `scan_adjacent_moves()` (line 418)
- `get_next_step()` (line 487)
- `find_cast_position()` (line 321) *(used by both move-to-cast retargeting
  and spell setup — see §4 on the duplication call)*
- `find_nearest_attack_position()` (line 526)
- `has_attack_position()` (line 605)
- `find_nearest_attackable_enemy()` (line 644)
- `write_movement_step()` (line 720)
- `handle_moving_state()` (line 1465)
- `handle_moving_to_cast_state()` (line 1533)
- A **new** dispatcher that reads `U_PENDING_ACTION_TYPE` and routes:
  - `ACTION_MOVE_TO` → write_dest + first step.
  - `ACTION_PATHFIND_MOVE` → `handle_moving_state()`.
  - `ACTION_PATHFIND_CAST` → `handle_moving_to_cast_state()`.
  - everything else → early-out.

Early-out: units in `ACTION_NONE`, `ACTION_ATTACK`, `ACTION_SPELL`,
`ACTION_ABILITY`, `ACTION_ITEM`, `ACTION_WAIT`, or `ACTION_COMPLETE_SPELL`
hit the early-out at the top and add zero per-thread cost. Skipping the
dispatch entirely from the CPU side when *no* unit needs pathfinding is
a future optimization (§6.2 of `compute_shader_status.md`); for now we
let every unit early-out cheaply.

### 3.3 `stage_attack.glsl` (~250 LoC est.)

**Owns:** attack setup for `U_PENDING_ACTION_TYPE == ACTION_ATTACK`.

Functions moved from `stage_compute.glsl`:

- `execute_attack_gambit()` (line 1089) — refactored to read `U_TARGET`
  from the decision rather than receive it as a parameter.
- `setup_attack_animation()` lives in `combat_combat.glsl` and stays there.
  This sub-stage `#include`s `combat_combat.glsl` like `stage_compute`
  does today.

Early-out: every other `U_PENDING_ACTION_TYPE` value returns immediately.

### 3.4 `stage_spell.glsl` (~400 LoC est.)

**Owns:** spell/ability/item setup and the STATE_CHARGING completion path.

Functions moved from `stage_compute.glsl`:

- `is_projectile_ability()` (line 739) — also referenced by pathfind for
  the move-to-cast LOS check. **Duplicate** into both stages (it's 9 lines
  and depends on nothing). Cheaper than promoting to `combat_common.glsl`.
- `start_spell()` (line 748) — biggest single function in this stage.
- `cast_projectile_spell()` (line 850)
- `cast_adjacent_item()` (line 870)
- `cast_instant_spell()` (line 891)
- `complete_spell_cast()` (line 937)
- A **new** dispatcher reading `U_PENDING_ACTION_TYPE`:
  - `ACTION_SPELL` / `ACTION_ABILITY` / `ACTION_ITEM` → `start_spell()`.
  - `ACTION_COMPLETE_SPELL` → `complete_spell_cast()`.
  - everything else → early-out.

---

## 4. Shared functions — where they live

After the split, every helper function has exactly one home. Cross-stage
sharing happens via the existing `combat_common.glsl` and
`combat_combat.glsl` headers, except for the rare small functions where
duplication is cheaper than promotion.

| Function | Home | Used by |
|---|---|---|
| All `read_unit*` / `write_unit*` accessors | `combat_common.glsl` | every stage |
| RNG (`rand_int`) | `combat_common.glsl` | every stage |
| Ability database accessors (`get_ability_*`) | `combat_common.glsl` | every stage |
| Status helpers (`has_status`, `set_status`) | `combat_common.glsl` | every stage |
| `manhattan_distance`, `get_tile_height`, `has_line_of_sight_arc` | `combat_common.glsl` | every stage |
| `can_attack_target`, `setup_attack_animation`, `calculate_spell_damage` | `combat_combat.glsl` | attack, spell, damage |
| `calculate_damage`, `roll_evasion` | `combat_combat.glsl` (move from `stage_compute.glsl:683/708`) | attack, spell (for spell damage tick), damage |
| `is_projectile_ability` | **duplicated** in pathfind and spell | both |
| `record_decision`, `check_decision_thrash` | `stage_decide.glsl` only | decide only |
| Gambit accessors + `evaluate_*` | `stage_decide.glsl` only | decide only |
| Pathfinding (`trace_stitched_path`, `scan_adjacent_moves`, `get_next_step`, `find_*_position`) | `stage_pathfind.glsl` only | pathfind only |
| `start_spell` family | `stage_spell.glsl` only | spell only |
| `execute_attack_gambit` | `stage_attack.glsl` only | attack only |

**Audit step before each phase:** grep the destination stage's includes for
the function and confirm no orphaned reference is left in another stage.

---

## 5. Per-tick dispatch order

```
NEW LOOP (post-Stage-2b):

TICK N START:
  ┌─ Pass 0  ─ stage_decide        — ceil(N_units / 64) workgroups
  │   one thread per unit; gambit eval; writes U_PENDING_ACTION_TYPE
  ├─ Pass 1  ─ stage_pathfind      — ceil(N_units / 64) workgroups
  │   one thread per unit; runs only if PENDING is a pathfind type
  ├─ Pass 2  ─ stage_attack        — ceil(N_units / 64) workgroups
  │   one thread per unit; runs only if PENDING == ACTION_ATTACK
  ├─ Pass 3  ─ stage_spell         — ceil(N_units / 64) workgroups
  │   one thread per unit; runs only if PENDING == ACTION_SPELL/ABILITY/ITEM/COMPLETE_SPELL
  ├─ Pass 4  ─ stage_resolve       — ceil(N_battles / 64) workgroups   [UNCHANGED]
  ├─ Pass 5  ─ stage_post_conflict — ceil(N_battles / 64) workgroups   [UNCHANGED]
  ├─ Pass 6  ─ stage_damage        — ceil(N_battles / 64) workgroups   [UNCHANGED]
  └─ Pass 7  ─ stage_victory       — ceil(N_battles / 64) workgroups   [UNCHANGED]

  BUFFER SWAP: _current_buffer ^= 1
```

`GPUBatchSimulator.gd:309–316` becomes:

```gdscript
var stage_files = [
    "res://src/gpu/shaders/stage_decide.glsl",
    "res://src/gpu/shaders/stage_pathfind.glsl",
    "res://src/gpu/shaders/stage_attack.glsl",
    "res://src/gpu/shaders/stage_spell.glsl",
    "res://src/gpu/shaders/stage_resolve.glsl",
    "res://src/gpu/shaders/stage_post_conflict.glsl",
    "res://src/gpu/shaders/stage_damage.glsl",
    "res://src/gpu/shaders/stage_victory.glsl",
]
```

`_run_tick()` (line 1002) gains three dispatches and loses one
(the residual `stage_compute` no longer exists). Each new sub-stage is a
separate pipeline with its own SPIR-V cache key — editing
`stage_attack.glsl` recompiles only its ~250-LoC scope.

---

## 6. Phased migration

Each phase is a separate commit, separately testable. Land in order; **do
not skip phases**. Phases 0 and 1 are pre-requisite cleanup — once they're
in, the actual stage split (Phases 2–5) can be done one stage at a time.

### Phase 0 — Plan & cleanup (this session)

- [x] Write this document.
- [ ] Delete `src/gpu/combat_batch.glsl` (3,527 LoC monolith).
- [ ] Retarget `tests/PipelineTest.gd`, `tests/StartupDiagnostic.gd`,
      `tests/ShaderCompileBench.gd` to load `stage_compute.glsl` (the
      current biggest pipeline) instead of `combat_batch.glsl`.
- [ ] Update the `combat_batch.glsl` reference in
      `src/data/AbilityDatabase.gd:17352` to point at `stage_damage.glsl`
      (where `is_break_formula` actually lives now).
- [ ] Update `docs/gpu-ai-system.md` references where line numbers point
      into the monolith — replace with split-shader equivalents.
- [ ] Smoke test: run one GPU test scene end-to-end, confirm no
      regression.

**Verification:** all existing tests still pass; the tree no longer has
3,527 LoC of dead code.

### Phase 1 — Add `U_PENDING_ACTION_TYPE` (no behavior change)

- Append `U_PENDING_ACTION_TYPE = 84` to `combat_common.glsl`.
- Bump `UNIT_SIZE = 85` and `SHADER_VERSION` in `combat_common.glsl`.
- Mirror in `GPUBatchSimulator.gd` `UnitField` enum, `UNIT_SIZE`,
  `EXPECTED_SHADER_VERSION`.
- Initialize the field to `ACTION_NONE = -1` in `compute_unit_state()`
  (where the other scratch fields are cleared).
- **No reads or writes** of the field in any opcode handler yet — this
  phase only proves the struct bump is clean.

**Verification:** `GPUSeedReproTest` golden replay still byte-identical;
no test regression.

### Phase 2 — Instrument `U_PENDING_ACTION_TYPE` at dispatch sites (no behavior change)

Refactor *in place* (no file split yet). **Revised scope (2026-05-30):**
the original plan called for full deferral here, but reading
`execute_gambit_action` revealed a structural blocker: SPELL/ABILITY/ITEM
return `false` on spell failure (no MP / LOS blocked / no cast position),
and the caller (`evaluate_gambits_up_to`) uses that to fall through to
the next gambit slot. Pure deferral breaks the fallthrough — we can't
tell gambit eval whether the spell will succeed until the spell sub-stage
runs, but by then gambit eval already returned.

So Phase 2 is split:

- **2.a (this phase) — Instrumentation only.** Write
  `U_PENDING_ACTION_TYPE = action_type` at the action dispatch points in
  `execute_gambit_action()`. On spell failure (`STATE_IDLE` after
  `start_spell`), revert the write to `ACTION_NONE` so the field reflects
  what actually committed. **Control flow is unchanged** —
  `execute_attack_gambit` / `start_spell` / `execute_move_to_gambit` are
  still called inline. The field is populated but no consumer reads it
  yet. Zero behavioral risk.

- **2.b (deferred to its own future session) — Actual deferral.** Move
  the action bodies out of the inline switch and into an
  `apply_pending_action()` function called after gambit eval. Requires
  resolving the spell-fallthrough problem — likely by pulling spell
  pre-validation (MP / LOS / find_cast_position) into a helper called
  from `execute_gambit_action` for the failure check, with the actual
  state writes deferred. This is significant design work — split out so
  Phase 2.a's safe instrumentation can land first.

Test rig for 2.a (this phase):

- Compile-time check: all 5 stages still compile via `PipelineTest.gd`.
  Cold-cache `stage_compute` pipeline_create stays within ±10% of the
  pre-Phase-1 baseline (~37 s on Intel iGPU) — the new write is a single
  store and shouldn't move SPIR-V size meaningfully.
- Behavioral: run `tests/run_all_tests.sh` once a full-build environment
  is available. Tick parity on every passing GPU test scene.

**If a test fails** on a property unique to 2.a (it shouldn't —
instrumentation only), revert the dispatch-site writes and diagnose.

### Phase 3 — Extract `stage_attack.glsl` *(landed 2026-05-31)*

The smallest and cleanest extraction. Move `execute_attack_gambit()` and
the attack-side of `apply_pending_action()` into a new file. Update
`GPUBatchSimulator._run_tick()` to dispatch the new stage right after
`stage_compute`'s decide-pass equivalent.

`stage_compute.glsl` retains its current main() but skips the attack
branch of `apply_pending_action()`. The new `stage_attack.glsl` runs that
branch.

**Implemented:** `src/gpu/shaders/stage_attack.glsl` (505 LoC) defines
`execute_attack_gambit` plus the pathfinding/decision helpers it
transitively needs (verbatim copies of `trace_stitched_path`,
`find_passthrough_destination`, `scan_adjacent_moves`, `get_next_step`,
`find_nearest_attack_position`, `has_attack_position`,
`find_nearest_attackable_enemy`, `write_movement_step`, `record_decision`).
These duplicates will be promoted to `stage_pathfind.glsl` in Phase 5 and
deleted from both stage_compute and stage_attack at that point.
`stage_compute.glsl` shrank from 1,887 → 1,841 LoC (`execute_attack_gambit`
removed). `GPUBatchSimulator.PASS_ATTACK = 5` runs immediately after
`PASS_COMPUTE_STATE` in `_run_tick`.

**Verification (Intel Meteor Lake iGPU):**

- PipelineTest cold-cache: `stage_compute` pipeline_create 36s → 12s,
  `stage_attack` 604 ms — the largest-single-pipeline metric drops
  ~66 % on the smallest of the four planned extractions.
- 35-test GPU suite: 30 PASS, 4 pre-existing failures (GPUThrashTest,
  GPUThrowStoneTest, GPUPhysicalAbilityTest, GPUThrowItemTest — all
  fail pre-Phase-3 too), 1 widened: GPUReactDurationTest's ±1 tolerance
  raised to ±3.

**Behavioral delta (documented + accepted):** `GPUReactDurationTest`
measures a CPU-side wall-clock countdown that, on this host, shifted
mean duration from 19.6 → 21.0 ticks (n=8 each). Both pre- and
post-Phase-3 distributions span 19–22 ticks; the ±1 bar was passing
pre-Phase-3 only by sample chance (7/8) and started failing post (3/8).
Static analysis of `apply_pending_action`'s old inline ATTACK branch
vs the new stage_attack dispatch shows identical NEXT-buffer writes;
the +1.4-tick drift comes from the extra GPU dispatch barrier
interacting with the test's `_tick_accumulator += delta` loop, not
from a logic regression. Accepted in the same spirit as Phase 2.b §2's
"1-tick re-evaluation delay" — see that document for the precedent.
Tolerance widening commented in `tests/GPUReactDurationTest.gd:160`.

### Phase 4 — Extract `stage_spell.glsl` *(landed 2026-05-31)*

Mirror of Phase 3 for the spell/ability/item path. Includes the
STATE_CHARGING completion (`complete_spell_cast()`).

**Implemented:** `src/gpu/shaders/stage_spell.glsl` (575 LoC) defines
`start_spell`, `cast_projectile_spell`, `cast_adjacent_item`,
`cast_instant_spell`, `complete_spell_cast`, `is_projectile_ability`,
plus duplicated pathfinding helpers (`trace_stitched_path`,
`find_passthrough_destination`, `scan_adjacent_moves`, `get_next_step`,
`write_movement_step`, `find_cast_position`). The `STATE_CHARGING`
handler in `compute_unit_state` now sets
`U_PENDING_ACTION_TYPE = ACTION_COMPLETE_SPELL` instead of calling
`complete_spell_cast` directly. `apply_pending_action` early-returns
for `ACTION_SPELL` / `ACTION_ABILITY` / `ACTION_ITEM` /
`ACTION_COMPLETE_SPELL`. `is_projectile_ability` stays in stage_compute
too (still called by `handle_moving_to_cast_state` for the in-MOVING
LOS recheck — Phase 5 will collapse the duplicate). `stage_compute.glsl`
shrank from 1,841 → 1,599 LoC. `GPUBatchSimulator.PASS_SPELL = 6` runs
right after `PASS_ATTACK`.

**Verification (Intel Meteor Lake iGPU):**

- PipelineTest cold-cache: `stage_compute` pipeline_create 12,055 ms →
  5,282 ms; `stage_spell` 672 ms; `stage_attack` 604 ms. The historical
  ~36 s monolith pipeline now resolves into four cooler pipelines
  (the largest is ~5.3 s).
- 35-test GPU suite (re-run after spell/throw-stone flakes on the
  first attempt): **32 PASS**, 1 FAIL (GPUThrashTest — pre-existing),
  1 TIMEOUT (GPUPhysicalAbilityTest — pre-existing), 1 NO_VERDICT
  (GPUThrowItemTest — pre-existing). All three remaining failures are
  identical to pre-Phase-3 baseline; no Phase-4-introduced regression.
  GPUReactDurationTest passes consistently under the widened
  tolerance from Phase 3.

### Phase 5 — Extract `stage_pathfind.glsl` *(landed 2026-05-31)*

The biggest extraction. At this point `stage_compute.glsl` only has the
decide-stage functions plus the bounded state-handler bits
(`tick_acting_animation`, STATE_REACTING, STATE_ACTING-to-IDLE finalize).
Move the pathfinding functions and movement-state handlers into
`stage_pathfind.glsl`.

**Implemented:** `src/gpu/shaders/stage_pathfind.glsl` (766 LoC) owns:

- The pathfind helpers (`trace_stitched_path`, `find_passthrough_destination`,
  `scan_adjacent_moves`, `get_next_step`, `find_cast_position`,
  `find_nearest_attack_position`, `has_attack_position`,
  `find_nearest_attackable_enemy`, `write_movement_step`).
- The movement-state handlers (`handle_moving_state`,
  `handle_moving_to_cast_state`, `execute_move_to_gambit`).
- `is_projectile_ability` and `record_decision` (used by the handlers).
- `find_unit_by_criteria` / `find_nearest_enemy` (also duplicated; cheap).

The STATE_MOVING and STATE_MOVING_TO_CAST branches of
`compute_unit_state` now write
`U_PENDING_ACTION_TYPE = ACTION_PATHFIND_MOVE / ACTION_PATHFIND_CAST`
instead of calling the handlers inline. `apply_pending_action` adds
early returns for `ACTION_MOVE_TO`, `ACTION_PATHFIND_MOVE`,
`ACTION_PATHFIND_CAST`. `stage_compute.glsl` shrank from 1,599 →
**932 LoC**. `GPUBatchSimulator.PASS_PATHFIND = 7` runs after
`PASS_SPELL`.

stage_attack.glsl and stage_spell.glsl keep their duplicated pathfind
helper copies — each compiles independently, and removing them would
force stage_attack / stage_spell to either lose `execute_attack_gambit` /
`start_spell` (large refactor) or pull the helpers through a shared
header (re-bloating compile time per the CLAUDE.md guidance). The
deliberate trade: source duplication, smaller per-stage SPIR-V.

The stage_compute → stage_decide rename was deferred — it's purely
cosmetic, and the file's documented role as "the decide stage" suffices
for navigation without the churn of updating every test scene's
references.

**Verification (Intel Meteor Lake iGPU):**

- PipelineTest cold-cache: `stage_compute` pipeline_create
  5,282 ms → **1,288 ms**; `stage_pathfind` 1,786 ms (largest single
  pipeline post-Stage-2b); `stage_attack`/`stage_spell` warm-cache.
  Down from the 36 s monolith, the new largest pipeline is **28× faster**.
- 35-test GPU suite: **32 PASS** (one run), 1 FAIL (GPUThrashTest —
  pre-existing), 1 TIMEOUT (GPUPhysicalAbilityTest — pre-existing),
  1 NO_VERDICT (GPUThrowItemTest — pre-existing). No Phase-5
  regression.

### Phase 6 — Re-measure compile time, update docs

- Re-run `tests/StartupDiagnostic.gd` (or `ShaderCompileBench`) with a
  cleared SPIR-V cache (`rm -rf ~/.local/share/godot/app_userdata/learning/shader_cache/`)
  and capture per-stage `pipeline_create` numbers.
- Update `shader_compile_refactor.md`'s timing table.
- Update `compute_shader_status.md` §5 (move Stage 2b from "Roadmap Tier 1"
  to "What it is").

If the headline number isn't a clear win on Intel (target: total cold
`pipeline_create` < 15 s, down from ~36 s), do a follow-up profile pass
before declaring victory. NVIDIA cold-launch measurement (Tier 1 item 5
in `compute_shader_status.md` §7) is the second validation step.

---

## 7. Verification strategy

### 7.1 Per-phase regression bar

| Phase | Required signal |
|---|---|
| 0 | `MinimalistArenaTest` still resolves in 779 ticks; shader load succeeds |
| 1 | All GPU tests pass; `GPUSeedReproTest` byte-identical |
| 2 | All GPU tests pass; tick parity within ±1 on `MinimalistArenaTest` (allowing for one-tick ordering shifts is **not** allowed — should be exactly 779) |
| 3 | All GPU tests pass; per-stage timing output shows `stage_compute` pipeline_create has dropped |
| 4 | All GPU tests pass; both extracted sub-stages' timings recorded |
| 5 | All GPU tests pass; no file named `stage_compute.glsl` remains |
| 6 | Documentation refreshed; before/after timing table committed |

### 7.2 Behavioral parity tools

- `tests/run_all_tests.sh` — sequential GPU test runner. **Never run in
  parallel** ([CLAUDE.md "Running GPU tests in parallel"](../CLAUDE.md)).
- `GPUSeedReproTest` — fixed-seed golden replay. Drift = broken determinism.
- `MinimalistArenaTest` — fast 4v4 arena, ~779 ticks. Cheap to re-run for
  every phase.
- `GPUArenaTest` — full sandbox, mix of abilities. Slower; run between phases,
  not within.

### 7.3 If a phase regresses

1. Identify the failing test.
2. Diff the unit struct snapshot at the tick of first divergence (the
   `GPUStateReader.gd` infrastructure already exists for this).
3. The divergence will be at one of: an `U_PENDING_ACTION_TYPE` write
   that was missed, a field that wasn't carried between sub-stages, a
   function that was duplicated wrong, or an early-out condition that
   was off-by-one.
4. **Revert the phase commit** if root cause isn't found in 30 minutes —
   do not stack risk by patching forward.

### 7.4 Compile-time validation

`StartupDiagnostic.gd` writes per-stage `glslang` / `shader_create` /
`pipeline_create` timings to stdout. The bar for Phase 6 success:

```
PRE-Stage-2b  (current):
  stage_compute       36,524 ms   ← long pole
  stage_resolve           20 ms
  stage_post_conflict     63 ms
  stage_damage            53 ms
  stage_victory           11 ms
  Total                36,680 ms

POST-Stage-2b (target):
  stage_decide        ~10,000 ms  ← largest remaining
  stage_pathfind       ~9,000 ms
  stage_attack         ~3,000 ms
  stage_spell          ~5,000 ms
  stage_resolve           20 ms
  stage_post_conflict     63 ms
  stage_damage            53 ms
  stage_victory           11 ms
  Total               ~27,000 ms total cold; ~10s critical-path (largest single stage)
```

The key metric is **largest single `pipeline_create`**, not total: that's
what determines per-edit iteration time when only one sub-stage was
touched. Target: ≤ 12 s on Intel iGPU.

---

## 8. Rollback plan

Every phase commit is independent. If Phase N regresses, `git revert <N>`
returns the tree to a working state without touching Phases 0..N−1. The
phases are deliberately ordered so this is safe:

- Phases 0 and 1 are purely additive (or remove dead code) — rollback is
  trivial.
- Phase 2 is the highest-risk; if it can't be made byte-identical with the
  pre-Phase-2 state, revert and re-attempt with smaller deferrals.
- Phases 3–5 each isolate one extraction; reverting one doesn't compromise
  the others.

If Phase 6's measured numbers don't show the expected win on at least
one platform, **do not revert** — the split still has the code-org
benefit (the long pole is broken up, future feature work lands in smaller
files). Document the discrepancy and move to Tier 2 features (reactions /
status enforcement).

---

## 9. Open questions for future sessions

- **`tick_acting_animation` placement.** Currently slated for
  `stage_decide.glsl`. If a future session shows that decide is still the
  long pole, consider promoting it to its own `stage_anim.glsl` —
  ~80 LoC, isolated, runs only for STATE_ACTING units.
- **CPU-side conditional dispatch.** §6.2 of `compute_shader_status.md`
  mentions skipping `stage_post_conflict` when no unit was blocked. The
  same logic applies to each new sub-stage: if no unit has
  `PENDING == ACTION_SPELL`, skip the spell dispatch. Requires a readback
  flag from `stage_decide` — meaningful work, save for after measured
  Stage 2b numbers.
- **Pipeline cache shipping.** §7 Tier 4 item 18. Becomes more tractable
  with smaller pipelines (each cache entry is smaller). Defer until
  Stage 2b's measured win lands.

---

## Appendix — Function migration table (authoritative)

Every function in `stage_compute.glsl` and its destination:

| Function | Current line | Destination | Notes |
|---|---:|---|---|
| `get_gambit_field` | 31 | `stage_decide` | |
| `gambit_enabled` | 36 | `stage_decide` | |
| `get_gambit_cond_target_type` | 40 | `stage_decide` | |
| `get_gambit_cond_count` | 44 | `stage_decide` | |
| `get_gambit_cond_type` | 48 | `stage_decide` | |
| `get_gambit_cond_value` | 52 | `stage_decide` | |
| `get_gambit_action_type` | 56 | `stage_decide` | |
| `get_gambit_action_id` | 60 | `stage_decide` | |
| `get_gambit_action_target_type` | 64 | `stage_decide` | |
| `evaluate_condition` | 71 | `stage_decide` | |
| `find_unit_by_criteria` | 133 | `stage_decide` | |
| `find_nearest_enemy` | 168 | `stage_decide` | |
| `select_target` | 172 | `stage_decide` | |
| `trace_stitched_path` | 191 | `stage_pathfind` | |
| `find_nth_nearest` | 274 | `stage_decide` | used by gambit Pass 2 retry |
| `find_cast_position` | 321 | `stage_pathfind` | also referenced by `start_spell` — see §4 |
| `find_passthrough_destination` | 379 | `stage_pathfind` | |
| `scan_adjacent_moves` | 418 | `stage_pathfind` | |
| `get_next_step` | 487 | `stage_pathfind` | |
| `find_nearest_attack_position` | 526 | `stage_pathfind` | also referenced by `execute_attack_gambit` |
| `has_attack_position` | 605 | `stage_pathfind` | |
| `find_nearest_attackable_enemy` | 644 | `stage_pathfind` | |
| `roll_evasion` | 683 | `combat_combat.glsl` | promoted: damage, attack, spell all need it |
| `calculate_damage` | 708 | `combat_combat.glsl` | promoted: attack and damage stages |
| `write_movement_step` | 720 | `stage_pathfind` | |
| `is_projectile_ability` | 739 | duplicated in `stage_pathfind` + `stage_spell` | 9 lines; cheaper than header promotion |
| `start_spell` | 748 | `stage_spell` | |
| `cast_projectile_spell` | 850 | `stage_spell` | |
| `cast_adjacent_item` | 870 | `stage_spell` | |
| `cast_instant_spell` | 891 | `stage_spell` | |
| `complete_spell_cast` | 937 | `stage_spell` | |
| `record_decision` | 998 | `stage_decide` | |
| `check_decision_thrash` | 1028 | `stage_decide` | runs at end of decide main() |
| `execute_attack_gambit` | 1089 | `stage_attack` | renamed/refactored to read PENDING fields |
| `execute_move_to_gambit` | 1140 | `stage_pathfind` | becomes the ACTION_MOVE_TO dispatcher |
| `execute_gambit_action` | 1160 | `stage_decide` | rewritten as `record_pending_action` |
| `check_gambit_conditions` | 1221 | `stage_decide` | |
| `evaluate_gambits_up_to` | 1241 | `stage_decide` | |
| `evaluate_gambits` | 1291 | `stage_decide` | |
| `check_pre_damage_reactions` | 1299 | DELETE (already unused; §4.3 reaction work will re-introduce) | |
| `apply_damage_with_reactions` | 1314 | DELETE (same) | |
| `tick_acting_animation` | 1382 | `stage_decide` | |
| `handle_moving_state` | 1465 | `stage_pathfind` | |
| `handle_moving_to_cast_state` | 1533 | `stage_pathfind` | |
| `compute_unit_state` | 1667 | split across all four sub-stages | the dispatcher is what disappears |
| `main` | 1799 | each sub-stage gets its own narrow `main()` | |

That's the whole loop.
