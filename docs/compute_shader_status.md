# Combat Compute Shader — System Status

**As of:** 2026-05-30
**Branch:** `redesign-battle-compute-shader`
**Companion docs:** [`gpu-ai-system.md`](gpu-ai-system.md) (architectural reference),
[`gpu-ai-improvements.md`](gpu-ai-improvements.md) (improvement tier list),
[`shader_compile_refactor.md`](shader_compile_refactor.md) (compile-time deep dive).

This document is the single-page status of the GPU combat compute shader: where it
came from, what it is today, what its measurable limits are, what we'd change if we
had unlimited time, and what we should change in what order. The three companion
docs are deeper on their respective slices; this one consolidates.

---

## Table of contents

1. [TL;DR](#1-tldr)
2. [What it was](#2-what-it-was)
3. [What it is](#3-what-it-is)
   - 3.1 [File layout](#31-file-layout)
   - 3.2 [Per-tick dispatch loop](#32-per-tick-dispatch-loop)
   - 3.3 [Data model — the 84-int unit struct + 8 SSBOs](#33-data-model)
   - 3.4 [State machine](#34-state-machine)
   - 3.5 [What each stage actually does](#35-what-each-stage-actually-does)
4. [Capability matrix](#4-capability-matrix)
   - 4.1 [Implemented and tested](#41-implemented-and-tested)
   - 4.2 [Implemented but untested](#42-implemented-but-untested)
   - 4.3 [Scaffolded but not wired up](#43-scaffolded-but-not-wired-up)
   - 4.4 [Outright missing](#44-outright-missing)
5. [Measured performance characteristics](#5-measured-performance-characteristics)
6. [What could be optimized](#6-what-could-be-optimized)
   - 6.1 [Compile time](#61-compile-time)
   - 6.2 [Runtime](#62-runtime)
   - 6.3 [Code organization](#63-code-organization)
7. [Roadmap](#7-roadmap)
8. [Appendix A — File map and authoritative line refs](#appendix-a--file-map-and-authoritative-line-refs)
9. [Appendix B — How to extend it without breaking things](#appendix-b--how-to-extend-it-without-breaking-things)

---

## 1. TL;DR

- The compute shader **IS the combat engine**. There is no CPU-side combat loop.
  The CPU spawns units, uploads gambit tables, dispatches the per-tick passes, and
  reads back state for rendering.
- **Architecture is sound.** 5-pass per-tick pipeline, double-buffered unit state,
  deterministic conflict resolution, seed-reproducible RNG. Battles complete in
  milliseconds. The Minimalist Arena 4v4 test resolves in ~780 ticks across all
  5 passes per tick with no measurable hitches.
- **The 2026-05-29 refactor split the 3,527-line `combat_batch.glsl` monolith into
  7 GLSL files**, gated by per-stage SPIR-V cache keys. Editing one stage no
  longer recompiles the others. Behavioral equivalence is verified via
  byte-identical SPIR-V for the heavy stage plus end-to-end A/B testing.
- **Cold compile is no longer the dominant pain.** Stage 2b decomposition
  (Phases 3-5, landed 2026-05-31) split `stage_compute` into four narrower
  sub-stages; largest single pipeline_create dropped from 36,473 ms to
  1,786 ms on Intel Meteor Lake iGPU. NVIDIA still unmeasured on the
  post-Stage-2b branch.
- **Status data-plumbing layer landed 2026-06-15** — `StatusRegistry` mirrors
  the `STATUS_*` constants from `combat_common.glslinc` as a `StringName→bit`
  map with a runtime drift assertion, and `GambitEncoder` consults it for
  `HAS_STATUS` / `MISSING_STATUS`. The plug-in convention for per-status
  combat semantics lives in [`status_system.md`](status_system.md). Remaining
  gaps are per-status combat semantics (POISON HP delta, REFLECT, full
  CONFUSION / FROG action overrides) — the slot is in §4.4 below.
- **The roadmap below is ordered**: §7 is the prioritized plan. With Stage 2b
  landed, the next headline call is "activate reactions and statuses (Tier 2)."

---

## 2. What it was

Three eras, briefly:

### Era 1 — CPU AI per unit (early)

Before the GPU port, combat ran in GDScript. One async coroutine per unit,
sequential `await` chain, ~30 FPS at 8 units. Sequential targeting decisions
made gambit interactions easy to reason about but impossible to scale beyond
toy battles. Battle-replay determinism was per-machine because the coroutine
scheduling pulled from a JS-engine-style microtask queue. Pathfinding ran on
the CPU's recursive BFS, which was easy to debug and impossible to vectorize.

### Era 2 — Monolithic `combat_batch.glsl` (the bulk of the work)

The combat loop moved to a single compute shader, `src/gpu/combat_batch.glsl`,
3,527 lines. The CPU's role shrunk to:

- Upload static data once (map, distance field, ability database, gambits).
- Each tick: dispatch the same compiled compute shader 5 times with a
  `#define PASS_X` on the front to select which pass to run.
- Read back the results buffer to drive rendering and end-of-battle detection.

This was the design that unlocked massively-parallel battle batching (hundreds
of battles simulated simultaneously to evaluate roster compositions). It's
documented end-to-end in [`gpu-ai-system.md`](gpu-ai-system.md) — that document
still describes the system architecturally accurately; only the file layout has
moved underneath it.

The architectural tax: a single 3,500-line shader compiled into **five** Vulkan
pipelines, each variant a full driver compile from scratch. The SPIR-V cache
key was MD5 of the modified source, so changing a single character anywhere
invalidated all five caches. On a cold cache, NVIDIA users reported ~10-minute
launch times. Editing the shader during development was ~10 minutes per
iteration.

`CLAUDE.md:358` documented the standing advice — "guard functions with the
narrowest set of passes" — but every reachable function was already guarded
fairly tightly, so there wasn't much left to wring out by that route. Multiple
prior sessions tried preprocessor tricks without measurable improvement.

### Era 3 — Per-stage split (now)

The 2026-05-29 refactor on `redesign-battle-compute-shader` split the monolith
into 5 stage shaders + 2 shared headers. Per-stage SPIR-V cache keys mean
editing `stage_resolve.glsl` no longer rebuilds `stage_compute.glsl`'s 36-second
pipeline. The 5-pass dispatch loop is unchanged — same passes, same order,
byte-identical compiled SPIR-V for the heavy stage. See
[`shader_compile_refactor.md`](shader_compile_refactor.md) for the
post-mortem with measured numbers, behavioral equivalence proofs, and the
extension plan.

The monolith was kept as `src/gpu/combat_batch.glsl` for one revision as an
offline SPIR-V parity reference; it has since been deleted (2026-05-30, Tier 0
cleanup). The split shaders are the only source of truth.

---

## 3. What it is

### 3.1 File layout

```
godot-learning/src/gpu/
├── GPUBatchSimulator.gd          # 1,398 lines — CPU driver: shader compile, dispatch, buffer mgmt
├── GambitEncoder.gd              # Gambit object → 16-int GPU schema
├── GPUConstants.gd               # Shared constants visible from both CPU and shader
└── shaders/
    ├── combat_common.glsl        # 793 lines — base header (every stage includes)
    ├── combat_combat.glsl        # 367 lines — combat helpers (compute/post_conflict/damage)
    ├── stage_compute.glsl        # 925 lines — the decide stage (gambit eval, target selection, state-machine edges)
    ├── stage_attack.glsl         # 505 lines — Phase 3: ACTION_ATTACK body
    ├── stage_spell.glsl          # 575 lines — Phase 4: ACTION_SPELL / ABILITY / ITEM + STATE_CHARGING completion
    ├── stage_pathfind.glsl       # 766 lines — Phase 5: ACTION_MOVE_TO + STATE_MOVING / MOVING_TO_CAST handlers
    ├── stage_resolve.glsl        # 113 lines  — movement conflict resolution
    ├── stage_post_conflict.glsl  # 75 lines   — opportunistic attacks after move
    ├── stage_damage.glsl         # 120 lines  — AOE + single-target damage
    └── stage_victory.glsl        # 89 lines   — end-of-battle detection
```

Stage 2b decomposition landed in three phases (3, 4, 5) on 2026-05-31:
`stage_attack`, `stage_spell`, `stage_pathfind`. `stage_compute` shrank
from 1,887 → 925 LoC and serves as the "decide" stage (gambit eval +
state-machine edges that don't require pathfinding). The
stage_compute → stage_decide rename was deferred as cosmetic. Pathfind
helpers are duplicated across `stage_pathfind` (canonical),
`stage_attack`, and `stage_spell` — each stage's SPIR-V cache is
independent, and the source duplication is the deliberate trade for the
~28× cold-compile win on the single largest pipeline (36 s → 1.8 s).

Each `stage_X.glsl` starts with `#[compute]` + `#version 450`, then a runtime
`#include "res://src/gpu/shaders/combat_common.glsl"` (and `combat_combat.glsl`
where needed). The `#include` is processed by
`GPUBatchSimulator._load_shader_with_includes()` before glslang ever sees the
source, because Godot's runtime `shader_compile_spirv_from_source()` doesn't
process `#include` itself (only the import-time `RDShaderFile` path does).

### 3.2 Per-tick dispatch loop

`GPUBatchSimulator._run_tick()` (around line 1002):

```
TICK N START:
  ┌─ Pass 0  ─ stage_compute       — ceil(N_units / 64) workgroups
  │   one thread per unit; gambit eval, decision recording, state-machine
  │   edges; commits pending action to U_PENDING_ACTION_TYPE
  ├─ Pass 1  ─ stage_attack        — ceil(N_units / 64) workgroups
  │   one thread per unit; runs ACTION_ATTACK body
  ├─ Pass 2  ─ stage_spell         — ceil(N_units / 64) workgroups
  │   one thread per unit; runs ACTION_SPELL / ABILITY / ITEM /
  │   COMPLETE_SPELL bodies
  ├─ Pass 3  ─ stage_pathfind      — ceil(N_units / 64) workgroups
  │   one thread per unit; runs ACTION_MOVE_TO + STATE_MOVING /
  │   MOVING_TO_CAST handlers
  ├─ Pass 4  ─ stage_resolve       — ceil(N_battles / 64) workgroups
  │   one thread per battle; sequential per-unit conflict resolution
  ├─ Pass 5  ─ stage_post_conflict — ceil(N_battles / 64) workgroups
  │   blocked units that ended adjacent to enemies attack now
  ├─ Pass 6  ─ stage_damage        — ceil(N_battles / 64) workgroups
  │   AOE resolution, queued damage application, kill detection
  └─ Pass 7  ─ stage_victory       — ceil(N_battles / 64) workgroups
      survivor count, victory flag write to results buffer

  BUFFER SWAP: _current_buffer ^= 1   (NEXT becomes CURRENT for tick N+1)

TICK N+1: repeat with swapped buffers
```

Each pass is a separate `RenderingDevice.compute_pipeline_create()` (compiled
once per launch), dispatched via `RenderingDevice.compute_list_dispatch()`. The
RenderingDevice API guarantees implicit pipeline synchronization between
dispatches — every pass sees the completed writes of the previous pass.

The double buffer means **every unit reads from the same snapshot
within a tick**: pass N reads from `CURRENT` and writes to `NEXT`. After all
5 passes complete, the buffers swap. This gives the game-side guarantee of
"all unit decisions are simultaneous within a tick" without explicit
read/write barriers per-cell.

Conditional dispatch: every pass checks `result == RESULT_ONGOING || test_mode == 1`
at the top of its main function. If the battle is over (and test_mode is off),
the threads early-out cheaply.

### 3.3 Data model

**8 SSBO bindings** declared in `combat_common.glsl:299–348`:

| Binding | Buffer | RW | Purpose |
|---|---|---|---|
| 0 | `SimConfig` | RW | num_battles, units_per_battle, map dims, pass_mode, current buffer toggle |
| 1 | `MapData` | RO | heights + traversability + cliff-edge flags per tile |
| 2 | `DistanceField` | RO | precomputed all-pairs BFS, `distances[from * W*H + to]` |
| 3 | `BattleData` | RW | **the ping-pong double buffer** — 2 copies of all unit state |
| 4 | `Results` | WO | per-battle output: result, tick count, team HP totals |
| 5 | `AnimTimings` | RO | animation lookup: damage frame + total frames per anim ID |
| 6 | `GambitData` | RO | 5 gambits × 16 ints per unit |
| 7 | `AbilityData` | RO | 512 abilities × 16 ints (database baked at boot) |

The double buffer at binding 3 is the key data-flow primitive. Per-tick
size = `2 × num_battles × (4 + units × 84)` ints. For an 8-unit single-battle
test, that's 2 × (4 + 672) = 1,352 ints = 5.4 KB. For 100 battles of 8 units
each, 540 KB. Comfortably fits in GPU memory.

**The 84-int unit struct** (full `U_*` enum in `combat_common.glsl:36–119`). Grouped:

- **Identity & position** (6 fields): `U_POS_X/Z`, `U_TEAM`, `U_HEIGHT`,
  `U_FLAGS` (bit 0 = `FLAG_DEAD`)
- **Core combat stats** (10): HP, MAX_HP, PA, MA, WP, BRAVE, FAITH, SPEED,
  MOVE, JUMP
- **State machine** (5): `U_STATE`, `U_TARGET`, `U_TIMER`, `U_CAST_TIMER`,
  `U_REACTION_TIMER`
- **Movement & navigation** (8): `U_DEST_X/Z`, `U_PROPOSED_X/Z`,
  `U_PREV_MOVE_POS`, `U_MOVE_TOTAL_TICKS`, `U_MOVE_STEP_ID`, `U_DBG_NEXT_X/Z`
- **Equipment & weapon** (8): `U_WEAPON_RANGE/FLAGS/TYPE`, `U_ANIM_ID/FRAME`,
  `U_DAMAGE_FRAME`, `U_TOTAL_FRAMES`, `U_ANIM_FLAGS`, `U_PROJECTILE_FRAME`
- **HP & MP** (6): `U_MP`, `U_MAX_MP`, `U_PENDING_DAMAGE`,
  `U_PENDING_HEAL_TARGET`, `U_PENDING_HEAL_AMOUNT`
- **Evasion & defenses** (5): `U_C_EV`, `U_S_EV`, `U_S_EV_MAG`, `U_W_EV`,
  `U_EVADE_TYPE`
- **Status effects** (10): `U_STATUS_FLAGS_LO/HI` (64 bits total),
  `U_STATUS_TIMER_0..7`
- **Spell state** (4): `U_CASTING_ABILITY_ID`, `U_CAST_TARGET`,
  `U_CAST_TIMER`, `U_AOE_*`
- **Reactions / passives** (4): `U_REACTION_ABILITY`,
  `U_SUPPORT_ABILITY` (unused), `U_MOVEMENT_ABILITY` (unused),
  `U_ABILITY_FLAGS`
- **Gambit eval scratch** (3): `U_CURRENT_GAMBIT`, `U_GAMBIT_COOLDOWN`,
  `U_DAMAGE_TARGET/AMOUNT`
- **Debug-only** (11): `U_DBG_*` fields (only written when `test_mode == 1`)
- **Decision history ring buffer** (4): `U_DECISION_HIST_0/1/2`,
  `U_DECISION_META` — fields exist; no code populates them

Of 84 fields, ~73 are actively read/written. The remaining 11 are either
debug-only (cheap to keep), or scaffold for unimplemented features
(see §4.4 below). Field bloat is not currently a performance concern;
removing fields would change SSBO offsets across the entire shader and is
not worth the churn until/unless the struct grows much larger.

### 3.4 State machine

8 states defined in `combat_common.glsl:122–129`:

| State | Constant | Set by | Reads as |
|---|---|---|---|
| Idle | `STATE_IDLE = 0` | initial; ACTING→IDLE on anim end | "awaiting next decision" |
| Moving | `STATE_MOVING = 1` | gambit chose MOVE_TO | "walking toward dest" |
| Acting | `STATE_ACTING = 2` | gambit chose attack/cast | "playing action animation" |
| Reacting | `STATE_REACTING = 3` | reaction triggered *(not yet wired up)* | "playing reaction anim" |
| Charging | `STATE_CHARGING = 4` | spell chosen, in range + LOS | "counting down CT" |
| Moving to cast | `STATE_MOVING_TO_CAST = 5` | spell chosen, out of range | "walking to spell range" |
| Dead | `STATE_DEAD = 6` | HP ≤ 0 in stage_damage | permanent terminal |
| Victorious | `STATE_VICTORIOUS = 7` | enemy team eliminated | permanent terminal |

The 14 transitions are all driven from `stage_compute.glsl`'s 8 state handlers
(`handle_idle_state`, `handle_moving_state`, etc., around lines 2475–2749).
Section 6 of [`gpu-ai-system.md`](gpu-ai-system.md) has the full transition
graph.

Timer semantics:

- `U_TIMER` is the **state countdown**. Decremented at the top of
  `compute_unit_state()`. When ≤ 0, the matching state handler fires.
- `U_CAST_TIMER` is **separate** because spell charging needs its own clock
  that doesn't interfere with the state timer. Decremented by
  `CHARGE_SEQ_SPEED` (= 1 default).
- Movement timer = ticks-per-tile, scaled by Haste (÷2) / Slow (×2).
- Animation timer = `max(attack_duration, damage_frame)` — the SEQ length,
  or the projectile-arrival frame if that's later (ranged). Damage fires the
  tick `U_ANIM_FRAME >= U_DAMAGE_FRAME`. (Padding constants
  `ANIM_BUFFER_MULTIPLIER` / `ANIM_SAFETY_MARGIN` retired; see ADR-0028 for
  the planned next step on the ranged-hold-pose follow-up.)
- Blocked units (conflict-resolution didn't accept their proposed move) get
  `U_TIMER = 1` and re-evaluate next tick.

### 3.5 What each stage actually does

#### `stage_compute.glsl` — the long pole (1,815 lines)

**One thread per unit across all battles.** The widest dispatch in the system
and the only one that's `ceil(num_units / 64)` workgroups — the other four
passes are `ceil(num_battles / 64)`. Roughly:

1. Copy unit state from CURRENT to NEXT.
2. Decrement timer; check damage-frame trigger if mid-anim.
3. Dispatch to one of 8 state handlers based on `U_STATE`.
4. Handler may: evaluate gambits, find target, pathfind, set action,
   transition state, or do nothing.

All the heavy lifting lives here: gambit condition evaluation (62-case
switch), target selection (`select_target`, `find_unit_by_criteria`),
pathfinding (`trace_stitched_path` BFS+DFS, `scan_adjacent_moves`,
`find_cast_position`), attack/spell setup, FFT damage formula dispatch.

#### `stage_resolve.glsl` — movement conflict resolution (113 lines)

**One thread per battle**, sequential iteration over units. The shader
serializes within a battle so multiple movers don't race to the same tile.
Two checks per moving unit: another mover with a closer-or-equal distance
wins ties by lower unit ID; a stationary occupant of the target tile blocks
the mover unconditionally. Blocked units get `U_TIMER = 1`. Deterministic
tie-breaking is the source-of-truth for replay reproducibility.

#### `stage_post_conflict.glsl` — opportunistic attacks (75 lines)

**One thread per battle.** If a unit was blocked during the move and ends
up adjacent to an enemy with attack range, it gets to swing this tick rather
than waiting. This is the "simulating CPU-side sequential decisions on the
GPU" trick — units that move first see units that already moved.

#### `stage_damage.glsl` — apply queued damage (120 lines)

**One thread per battle.** Three phases:
1. **AOE resolution**: for each unit with `U_AOE_ABILITY_ID >= 0`, find
   targets within Manhattan `effect_area`, queue damage/heal/break per target.
2. **Single-target**: melee damage queued by `stage_compute` is moved from
   `U_DAMAGE_TARGET/AMOUNT` into the target's `U_PENDING_DAMAGE`.
3. **Finalize**: subtract pending from HP, mark dead if HP ≤ 0.

Break effects (weapon-break, shield-break, stat-break, MP-drain) are
probabilistic — rolled via `rand_int()` seeded on caster + target + tick.
Currently 3 of 8 break formula IDs are actually handled; see §4.4.

#### `stage_victory.glsl` — end-of-battle detection (89 lines)

**One thread per battle.** Counts living units and victorious units per
team. Conditions:
- DRAW if both teams have 0 living units, **or** if battle tick ≥ MAX_TICKS.
- TEAM_X_WINS if opposite team has 0 living units **and** all survivors are
  in STATE_VICTORIOUS (the "celebration condition" prevents a premature win
  before the killing-blow animation finishes).

Increments battle tick. Sums HP per team and writes to results buffer.

---

## 4. Capability matrix

### 4.1 Implemented and tested

| Capability | Tests |
|---|---|
| Melee combat (sword/dagger/spear) | `GPUMeleeCombatTest`, `MinimalistArenaTest` |
| Ranged combat (bow/gun, projectile flight) | `GPURangedCombatTest`, `GPUEvasionRanged*Test` |
| Spell casting (CT, MP cost, LOS) | `GPUSpellCombatTest`, `GPUSpellTrackingTest` |
| Charge then cast (multi-tick) | `GPUSpellCombatTest`, `IfritTest` |
| Throw stone (speed-scaled range) | `GPUThrowStoneTest` |
| Items in battle | `GPUItemCombatTest`, `GPUItemFallthroughTest` |
| AOE damage | `GPUAOECombatTest`, `MeteorCallbackTest` |
| AOE healing (allies-only) | `GPUAOEHealTest` |
| AOE center tracking | `GPUAOETrackingTest` |
| Damage formulas (11 specific formulas) | `GPUFormula01..78Test` |
| Equipment break | `GPUKnightBreakTest` |
| Stat-break traps (PA/MA/Speed reduction) | `GPUBreakTrapTest` |
| Protect (½ physical damage) | `GPUProtectTest` |
| Shell (½ magic damage) | `GPUShellTest` |
| Haste / Slow (movement speed scaling) | `GPUHasteSlowTest` |
| Pathfinding with terrain + cliffs | `GPUDistanceFieldTest`, `GPUDashMovementTest` |
| Vertical tolerance (jump height) | `GPUVerticalToleranceTest` |
| Teleport (instant movement) | `GPUTeleportTest` |
| Seed-reproducible battles | `GPUSeedReproTest` |
| Movement-only choreography mode | `GPUSEQMovementTest` |
| Reaction cooldown timing | `GPUReactDurationTest` |
| Effect callbacks (particle/anim cue timing) | `GPUCallbackE005/E065/E317Test` |

### 4.2 Implemented but untested

| Capability | Risk |
|---|---|
| Multi-target abilities (4+ targets at once) | AOE radius works; explicit 4+ target test absent |
| Vertical range variance (arcing spells with height bonus) | Code path exists; no test exercises elevation edge cases |
| Most damage formulas not in the curated 11 | Formulas not in `GPUFormula01..78Test` are exercised by Arena-style tests, but unit-level coverage is absent |

### 4.3 Wired up

What's already implemented and tested. For the **plug-in convention** (which
stage owns which status category + how to add a new status), see
[`status_system.md`](status_system.md).

**Wired up 2026-05-31 (Tier 2 batch):**

| Capability | Where it landed |
|---|---|
| **Status duration decay** (`U_STATUS_TIMER_0..7`) | `tick_status_timers()` in `combat_common.glsl`, called from `compute_unit_state`. Slot packs `(status_bit << 24) | ticks_remaining`. New `set_status_with_timer()` / `clear_status_timer()` helpers. Test: `GPUStatusDecayTest`. |
| **REACT_MANA_SHIELD / REACT_ABSORB_MP / REACT_AUTO_POTION** | `stage_damage.glsl` Phase 3 — defender-side reactions; no attacker context needed. Test: `GPUReactionDefenderTest`. |
| **REACT_COUNTER** | `stage_damage.glsl` Phase 2.5 — queues retaliation on adjacent attacker. Test: `GPUReactionCounterTest`. |
| **REACT_BLADE_GRASP / REACT_ARROW_GUARD** | `tick_acting_animation` weapon-damage branch — extra evasion roll keyed on attacker's `U_PROJECTILE_FRAME`. Test: `GPUBladeGraspTest`. |
| **Sleep / Stop / Petrify / Disable (no-action gates)** | `compute_unit_state` STATE_IDLE entry. Test: `GPUStatusEnforceTest`. |
| **Silence (blocks spell gambits)** | `execute_gambit_action` — SPELL/ABILITY actions fall through on Silence. Test: `GPUStatusEnforceTest`. |
| **Immobilize (blocks MOVE_TO)** | Same site, MOVE_TO falls through. Test: `GPUStatusEnforceTest`. |
| **Berserk (forces ATTACK)** | `compute_unit_state` STATE_IDLE entry, overrides gambit list with `ACTION_ATTACK` on nearest enemy. Test: `GPUBerserkTest`. |
| **Undead damage inversion** | Damage routes via `pending_damage` → heals undead; heal sites route via `pending_damage` → damages undead. Phase 3 has the central invert. Test: `GPUUndeadInvertTest`. |
| **Projectile-deferred healing** (`U_PENDING_HEAL_TARGET/AMOUNT`) | `stage_damage.glsl` Phase 4 — same-tick resolution with undead inversion. Test: `GPUDeferredHealTest`. |

**Wired up 2026-06-15 (per-tick HP delta category — first per-status plug-in convention use):**

| Capability | Where it landed |
|---|---|
| **POISON + REGEN per-tick HP delta** (`STATUS_POISON = 15`, `STATUS_REGEN = 16`) | `stage_damage.glsl` Phase 1.5 — every `POISON_TICK_INTERVAL` (=30) ticks each living unit with either bit queues `max_hp / POISON_HP_DIVISOR` (=max_hp/8) into its own `U_PENDING_DAMAGE`: POISON as positive (damage), REGEN as negative (heal). Phase 3 resolves both together; the existing STATUS_UNDEAD invert (`hp + pending`) flips signs for free — positive heals undead (poison-undead = heal), negative damages undead (regen-undead = damage), and undead can now die from regen overdraw. Phase 3 also grew a negative-pending heal-only branch that skips reactions (you can't mana-shield a heal) and caps at `max_hp`. Status duration is owned by `tick_status_timers` in stage_compute. Plug-in slot picked per [`status_system.md`](status_system.md) §2 "Per-tick HP delta" row. Tests: `GPUPoisonTest`, `GPURegenTest`. Gambit-side witnesses (HAS_STATUS(&"poison"/&"regen") compose through encoder + shader): `tests/gambit_scenarios/scenarios_D_conditions.gd::has_status_self_poison_fires_self_cure` + `::has_status_self_regen_fires_self_cure`. |

**Wired up earlier but missing from §4.3 until 2026-06-15:**

| Capability | Where it landed |
|---|---|
| **PROTECT + SHELL damage modifier** (`STATUS_PROTECT = 17`, `STATUS_SHELL = 18`) | "Damage modifier" row in [`status_system.md`](status_system.md) §2. PROTECT halves incoming physical damage at `stage_compute.glsl:293` (the per-attack damage finalize), and `stage_damage.glsl:152` halves REACT_COUNTER damage on a Protect-bearing attacker. SHELL halves incoming magic damage at `combat_combat.glslinc:368`, gated by `is_magic_formula`. Tests: `GPUProtectTest`, `GPUShellTest`. |
| **HASTE + SLOW timer multiplier** (`STATUS_HASTE = 19`, `STATUS_SLOW = 20`) | "Timer multiplier" row in [`status_system.md`](status_system.md) §2 — three call sites scale `U_TIMER` / CT at the timer-set call: `stage_attack.glsl:392-394` (ACTING-state attack duration), `stage_pathfind.glsl:487-489` (per-tile movement timing), `stage_spell.glsl:313-315` (charge time). Halved under HASTE, doubled under SLOW; the two cancel cleanly when both bits are set. Test: `GPUHasteSlowTest`. Gambit-side witness: `tests/gambit_scenarios/scenarios_D_conditions.gd::has_status_self_haste_fires_slot_zero` proves the registry lookup for &"haste". |
| **RERAISE re-targeting** (`STATUS_RERAISE = 22`) | "Re-targeting" row in [`status_system.md`](status_system.md) §2. `stage_damage.glsl` Phase 3 — `try_consume_reraise` helper gates both kill sites (non-undead and undead-overdraw). On lethal damage, if the unit holds RERAISE, restore HP to `max_hp / RERAISE_HP_DIVISOR` (= max_hp/10, FFT canon "small revive amount"), clear the bit, and clear the bit's timer slot — the carrier survives that one lethal hit. Subsequent lethal damage kills normally; RERAISE is one-shot per apply. Reads/writes go through the NEXT buffer to compose with same-tick status decay from `tick_status_timers`. Test: `GPUReraiseTest`. Gambit-side witness: `tests/gambit_scenarios/scenarios_D_conditions.gd::has_status_self_reraise_fires_self_cure`. |
| **TRANSPARENT target filter** (`STATUS_TRANSPARENT = 23`) | "Target filter" row in [`status_system.md`](status_system.md) §2 (first consumer; INVITE/Charm deferred). Five target-selection sites get a `has_status_next(t, STATUS_TRANSPARENT)` skip when the candidate is on the other team — `find_unit_by_criteria` and `find_nth_nearest` in `stage_compute.glsl`, `find_unit_by_criteria` and `find_nearest_attackable_enemy` in `stage_pathfind.glsl`, and `find_nearest_attackable_enemy` in `stage_attack.glsl`. `stage_post_conflict.glsl` also filters its adjacent-enemy opportunistic-attack scan so blocked-walker re-targeting can't slip through. Ally-side searches (`want_ally=true`) are unchanged — a Priest still cures their invisible Knight. Two consume sites: (1) `stage_compute.glsl` `execute_gambit_action` clears the bit + timer slot on commit to ACTION_ATTACK / ACTION_SPELL / ACTION_ABILITY / ACTION_ITEM (MOVE_TO / MOVE_TO_UNIT / WAIT preserve the bit, FFT canon — you can sneak around invisible); (2) `stage_damage.glsl` Phase 3 `try_consume_transparent_on_aoe` clears the bit + timer when `pending_damage > 0` and the carrier is not undead (AOE bleed reveals; healing and undead-overdraw don't break it). Both consume sites use `read_unit_next` + inline bit AND-NOT to compose with same-tick decay from `tick_status_timers` without going through CURRENT-buffer `clear_status()`. Test: `GPUTransparentTest`. Gambit-side witness: `tests/gambit_scenarios/scenarios_D_conditions.gd::has_status_self_transparent_fires_self_cure`. |

### 4.4 Scaffolded but not wired up

Things where the **data model has the slot** but **no shader code reads it**:

| Capability | Where the slot lives | What's missing |
|---|---|---|
| **REACT_FIRST_STRIKE** | `U_REACTION_ABILITY` + `REACT_FIRST_STRIKE = 1` | Needs state-machine surgery in stage_compute: intercept the attacker's ACTING phase before damage queues and swap the swing onto the defender (the rest of the reaction infra is in place after #7 part 3). |
| **Support abilities** (passive auras) | `U_SUPPORT_ABILITY` field | No reads anywhere. Intended for permanent stat buffs (Move +1, etc.) that should be evaluated at battle start. |
| **Movement abilities** (Teleport variants, Move-MP-Up) | `U_MOVEMENT_ABILITY` field | No reads. Hardcoded teleport works because it's a special ability ID, not a movement ability per se. |
| **Confusion** (`STATUS_CONFUSION = 24`) | bit in status flags | Random target choice would conflict with `GPUSeedReproTest`'s determinism — needs a deliberate RNG-stream design first. |
| **Frog** (`STATUS_FROG = 14`) | bit in status flags | Would replace the unit's action set; bigger than a one-conditional gate. |
| **Reflect** (bounce spell back) | `ABFLAG_REFLECTABLE = 1` | Flag exists on ability data; the matching status bit for "currently reflecting" doesn't. Needs a `STATUS_REFLECT` allocation plus a check in `start_spell` / `cast_projectile_spell`. |
| **Decision history ring buffer / thrash detection** | `U_DECISION_HIST_0/1/2`, `U_DECISION_META` (bits for thrash_flag and thrash_count), `REASON_THRASH_ABORT = 13` | Fields and constants all in place. **No code populates the ring buffer or increments the thrash counter.** Detecting and breaking infinite gambit loops is the goal; without it, a misconfigured gambit set can stall until `MAX_TICKS` timeout. (GPUThrashTest fails on this.) |
| **Break formulas 10, 11, 42, 56, 80** | listed in `is_break_formula()` at `stage_damage.glsl:22` | The function recognises them as breaks. `apply_break_effect()` in `combat_combat.glsl:176` only handles 37 (equipment), 43 (stat), 44 (MP-drain). Others return `false`. Wiring them requires populating each ability's inflict-status bit into the ability buffer (needs an FFT-data → STATUS_* bit table in `AbilityDatabase.gd`). |
| **Element-based affinity** | `AB_ELEMENT` on ability data, status bits for absorb / null / weak / half by element | Element field exists on abilities; status bits for element interactions need to be allocated; damage calc doesn't read them. Fire, Ice, Bolt etc. all do flat damage. |

These are **not bugs**. The architecture intentionally laid scaffolding before
writing the consumer code. Wiring them up is straightforward but
mechanically large — each one is a 20–100 line patch in 1–3 shader files plus a
test scene.

### 4.5 Outright missing

Things with **no data model and no code**:

- Turn-based mode (the original FFT semantic — units take turns by CT, not real-time)
- Save-state-style mid-battle persistence (battle state currently exists only in SSBOs)
- Multi-cast / multi-hit per-action (single damage event per action)
- Mounted units / chocobos (no rider concept)
- Job-change mid-battle (jobs are baked at unit spawn)

These are larger product decisions, not gaps in the current system. The system
deliberately implements real-time tick-based simulation, not turn-based — they
are different games.

---

## 5. Measured performance characteristics

### Compile time

From `tests/PipelineTest.gd`, on an Intel Meteor Lake iGPU with `vulkan-intel`,
**cold cache** (cleared `~/.local/share/godot/app_userdata/learning/shader_cache/`):

**Pre-Stage-2b (monolithic `stage_compute`, 5 stages):**

| Stage | Total | pipeline_create |
|---|---:|---:|
| `stage_compute`       | 36,524 ms | **36,473 ms** |
| `stage_resolve`       | 20 ms     | 14.6 ms |
| `stage_post_conflict` | 63 ms     | 54.7 ms |
| `stage_damage`        | 53 ms     | 45.5 ms |
| `stage_victory`       | 11 ms     | 6.6 ms |
| **Total**             | **36,680 ms** | |

**Post-Stage-2b (decide + attack + spell + pathfind, 8 stages, 2026-05-31):**

| Stage | Total | pipeline_create |
|---|---:|---:|
| `stage_compute` (decide) | 1,381 ms | **1,288 ms** |
| `stage_attack`           | ~600 ms  | ~600 ms |
| `stage_spell`            | ~670 ms  | ~670 ms |
| `stage_pathfind`         | 1,805 ms | **1,786 ms** |
| `stage_resolve`          | 5 ms     | 0 ms |
| `stage_post_conflict`    | 8 ms     | 0 ms |
| `stage_damage`           | 8 ms     | 0 ms |
| `stage_victory`          | 5 ms     | 0 ms |
| **Total**                | **~4.5 s** | |

**Largest single pipeline_create: 36,473 ms → 1,786 ms (~20× faster).**
**Total cold launch: 36,680 ms → ~4,500 ms (~8× faster).** The dispatch
loop grew from 5 to 8 passes; the per-stage SPIR-V volumes are now
roughly balanced rather than dominated by one monolith.

Warm cache (same machine, subsequent launch): each stage <5 ms; total ~30 ms.

NVIDIA cold-launch numbers haven't been measured on the post-Stage-2b
branch. The user's original "~10 minutes" report was on NVIDIA; with the
largest single pipeline_create now ~1.8 s on Intel, even a 10×
NVIDIA-vs-Intel multiplier would land the worst stage in the ~20-second
range — well below the prior 10-minute cold-launch ceiling. Worth a real
measurement before declaring victory.

### Runtime per tick

The Minimalist Arena 4v4 test (8 units, 16×16 map, single battle) runs all 5
passes per tick in **single-digit milliseconds total** on warm cache. 779
ticks to resolution = ~5 s of GPU work for an 8-unit battle. Headroom for
scale:

- 100-battle batch at 8 units each: ~5 ms / pass × 5 passes × 1× scale = ~25 ms / tick
- 1000-battle batch: still GPU-bound at the per-stage dispatches, not the
  per-thread work. Untested.

The system has comfortable headroom for what it's designed to do (parallel
battle batching for AI evaluation / roster ranking). It is not designed for
real-time 60-FPS game-loop integration where every frame is one tick —
animations and rendering run on a separate CPU clock and read GPU state at
their own cadence.

### Throughput hotspots

From the per-stage code inspection:

| Hotspot | Where | Complexity | Notes |
|---|---|---|---|
| Movement conflict resolution | `stage_resolve.glsl:18–103` | O(N²) per battle per tick | N=8 → ~64 comparisons. Acceptable. N=100+ starts to matter. |
| Pathfinding BFS+DFS | `trace_stitched_path` in `stage_compute.glsl:191–270` | O(map_area) per call | Map_area = W×H = 256 on 16×16. Usually terminates in <30 steps. Worst-case (genuinely stuck) is the full 256. |
| Gambit evaluation | `evaluate_gambits` in `stage_compute.glsl:71–124` | O(5 × 4 × N) per unit per tick | 5 gambits × 4 conditions × N units. ~160 ops on 8 units, ~2000 on 100. |
| AOE damage | `apply_damage` in `stage_damage.glsl:28–110` | O(M × N) per battle | M = casters, N = units. Worst-case M = N → O(N²). |
| Target selection | `select_target` / `find_unit_by_criteria` | O(N) per call, ~25× per unit per tick | Per unit: 5 gambits × (4 cond targets + 1 action target). |

No O(N³) patterns. The dominant cost on small battles is the per-stage
fixed overhead (compute dispatch, SSBO binding setup), not the per-unit
arithmetic. On larger battles, `stage_resolve` and `stage_damage`'s O(N²)
become the bottleneck.

---

## 6. What could be optimized

### 6.1 Compile time

| Optimization | Effort | Headline win |
|---|---|---|
| **Stage 2b — decompose `stage_compute` into 4 sub-stages** (`stage_decide`, `stage_pathfind`, `stage_attack`, `stage_spell`) | **Large.** ~2–3 days of careful shader-splitting + verification. Each sub-stage early-outs for irrelevant units; state flows through existing scratch fields. | Cuts the **single worst pipeline_create from 36 s to ~10 s** (estimated; each piece is ~1/4 the SPIR-V volume). Per-edit recompile time on COMPUTE logic drops the same amount. **The single highest-leverage remaining piece of work.** Plan in [`shader_compile_refactor.md`](shader_compile_refactor.md) §5.1. |
| Ship serialized `VkPipelineCache` per platform/driver in exported builds | Large + per-platform-driver bake step | Skips the cold pipeline_create for end users entirely. Premature without Stage 2b first — and tightly coupled to driver versions, so brittle. |
| Strip debug-only fields from shader when `test_mode == 0` is the compile-time default | Small | Marginal. ~5 % SPIR-V reduction at best. Probably not worth the build-config complexity. |

### 6.2 Runtime

| Optimization | Effort | Headline win |
|---|---|---|
| **Replace O(N²) conflict resolution with grid-bucketed adjacency** | Medium. Move `stage_resolve` from "for-each-unit / for-each-other-unit" to a per-tile bucket pass that only compares units proposing the same tile. | At N=8 the constant factor matters more than the asymptote — likely no improvement. **Wins start at N ≥ 32.** |
| **Distance field memory layout** — interleave by tile rather than by source | Medium. Recompute the layout of binding 2 to cache-line-align reads. | Modest. Distance field is read-only, so GPU caches help, but the strides (W×H) are larger than typical cache lines. Profile-driven; do it only after measuring it as a real bottleneck. |
| **Gambit evaluation early-out** — if first gambit unconditionally triggers (Always condition), skip the other four. | Trivial. One conditional at the top of `evaluate_gambits`. | Modest. Helps the "minimalist 1-gambit" cases by 5×. Real strategy gambits usually have 3+ slots and gain less. |
| **Stop running `stage_post_conflict` if no unit was blocked** | Small. CPU-side flag from `stage_resolve` (would require a readback or another SSBO field). | One full dispatch saved per tick on uncongested ticks. Likely 1–3 % at the tick level. |
| **Batched victory check** — only run `stage_victory` every N ticks, not every tick | Small. CPU-side cadence tweak. | Reduces 1/5 of the per-tick GPU dispatch cost. Quality-of-results unchanged for N ≤ 4 (battles never resolve in fewer than a few ticks after the killing blow because of celebration condition). |

### 6.3 Code organization

| Optimization | Effort | Headline win |
|---|---|---|
| **Update `gpu-ai-system.md`** to reference the per-stage files (currently references the monolith and its line numbers) | Small. Mechanical pass. | The doc is the canonical entry-point for the system. Stale line refs cost every new contributor an hour of "where is this actually?" |
| ~~**Delete `combat_batch.glsl` (the monolith)**~~ | Done 2026-05-30. The three timing tests now iterate over the per-stage shaders. |
| **Move debug-only `U_DBG_*` fields out of the main unit struct** into a parallel debug SSBO | Medium. Touches every shader and `GPUBatchSimulator.gd`'s unit layout. | Cleaner separation; smaller hot unit struct. Probably only worth doing if §4.3 expansion grows the struct above 96 ints (current GPU alignment sweet spot). |
| **Decouple `combat_combat.glsl` further** — it's currently included by 3 stages but contains code only one of them needs (e.g., damage formulas are only used by `stage_damage`) | Medium. Audit each function in `combat_combat.glsl` for which stages actually need it. | Reduces preprocessed-source size for `stage_compute` and `stage_post_conflict`, which tightens their SPIR-V slightly. Likely marginal until Stage 2b. |

---

## 7. Roadmap

Ordered by leverage. Items higher up have larger payoff per hour invested.

### Tier 0 — close out what's open on this branch

These are open work items on `redesign-battle-compute-shader` before it merges
to main:

1. **Land the Minimalist Arena 4v4 baseline test** (`worktree-minimalist-arena-roster`).
   Already pushed to origin as a separate branch — open as a PR.
2. **Update `gpu-ai-system.md`** to reference per-stage file paths and call out the
   "section 13 reactions" caveat. ~1 hour mechanical edit.
3. ~~**Decide the fate of `combat_batch.glsl`**~~. Done 2026-05-30: deleted,
   tests retargeted at the per-stage shaders.

### Tier 1 — Stage 2b *(landed 2026-05-31)*

~~This is the single highest-leverage item in the entire roadmap.~~

4. ~~**Stage 2b — decompose `stage_compute` into 4 sub-stages.**~~ Landed
   2026-05-31 across three commits (Phases 3, 4, 5). The plan in
   [`stage_2b_implementation_plan.md`](stage_2b_implementation_plan.md)
   was followed; the stage_compute → stage_decide rename was deferred as
   cosmetic. Result on Intel Meteor Lake iGPU: largest single
   pipeline_create dropped from **36,473 ms → 1,786 ms**. See §5.

5. **Measure NVIDIA cold-compile time** on the post-Stage-2b branch (one user
   needs to clone, clear cache, launch GPUArena, copy the TIMING lines). The
   "~10 minute" anecdote predates the split — we should have a current number
   before estimating Stage 2b's payoff.

### Tier 2 — activate scaffolded features (game feel)

These are the gameplay features that go from "scaffolded" to "shipping". Each
is a contained shader patch + 1–2 test scenes. Estimated effort:
0.5–2 days each, in this order:

6. **Status duration decay loop.** Single new function in `stage_compute.glsl`
   that decrements `U_STATUS_TIMER_0..7` once per tick and clears the
   corresponding status bit when a timer hits zero. Unblocks every other
   status-effect feature below.
7. **Reaction ability triggers in damage path.** Resurrect the
   `check_pre_damage_reactions()` and `apply_damage_with_reactions()`
   functions described in [`gpu-ai-system.md`](gpu-ai-system.md) §13, port
   them into `stage_damage.glsl`. Counter, First Strike, Auto-Potion,
   Mana Shield, Absorb MP, Arrow Guard, Blade Grasp. Test scene per reaction
   type.
8. **Status enforcement in eligibility checks.** Read `U_STATUS_FLAGS_LO/HI`
   in `handle_idle_state` and gate attack/cast attempts:
   - Disable / Stop / Petrify / Sleep / Frog (no actions at all)
   - Silence (no spells)
   - Berserk (force ATTACK on nearest enemy, ignore gambit target)
   - Confusion (random target among all units)
   - Immobilize (no movement)
9. **Element-based damage modifiers.** Read `AB_ELEMENT` on ability data,
   read element absorb/null/weak/half bits on target status. Multiplier
   applied at the very end of `calculate_spell_damage`. Test scene per
   element interaction.
10. **Undead damage inversion.** Single check at the top of damage application:
    if target has `STATUS_UNDEAD`, swap damage and heal signs.
11. **Projectile-deferred healing.** `apply_damage` reads
    `U_PENDING_HEAL_TARGET/AMOUNT` and applies to target. Mirrors damage path.
12. **Reflect.** `cast_projectile_spell` / `start_spell` checks if target has
    a reflect-aura ability; bounce the spell back to caster instead of impact.
13. **Break formulas 10, 11, 42, 56, 80.** Add cases to `apply_break_effect`
    in `combat_combat.glsl`. Quote ability database for what each formula
    actually does.

### Tier 3 — decision-quality and tooling

14. **Decision history ring buffer + thrash detection.** Populate
    `U_DECISION_HIST_0/1/2` in `evaluate_gambits`; check for thrash patterns
    (same gambit fired N times within K ticks); set `REASON_THRASH_ABORT`
    and force the unit to STATE_IDLE for a cooldown. Solves the
    "misconfigured gambit hangs the battle until `MAX_TICKS`" problem.
15. **CPU-side gambit linter.** Static analysis of a gambit table before
    upload: warn on always-true conditions paired with no target, on
    cycles where gambit A's action triggers gambit B's condition and
    vice versa.
16. **Per-tick replay capture.** Optional `RecordingBuffer` SSBO that captures
    one row per unit per tick (state, position, target, action). Already
    half-implemented via `U_DBG_*` fields — formalize it into a tooling-grade
    output that the existing `GPUSeedReproTest` can validate against.

### Tier 4 — research / capability-class changes

These are larger items where the scope is unclear:

17. **Multi-tile pathfinding from cache.** Currently each unit re-runs path
    BFS from scratch every tick when moving. A per-battle "navmesh cache"
    SSBO (computed once when units enter STATE_MOVING and invalidated when
    the unit's destination changes) would replace ~80 % of pathfinding work.
18. **NVIDIA pipeline-cache shipping.** After Stage 2b, see if shipping a
    pre-warmed `VkPipelineCache` per (platform, driver) cuts cold-launch on
    end-user machines to milliseconds. Build/release tooling complexity is
    real; only do this if Stage 2b doesn't get us where we need to be.
19. **External GPU sidecar** for AI iteration. Compile a native binary that
    can run the same compute shader headless without booting Godot.
    Decouples AI training/tuning workflows from the game's startup.
    Documented in [`shader_compile_refactor.md`](shader_compile_refactor.md)
    §5.3 as "Track C." Not a compile-time fix; a workflow fix.
20. **Turn-based mode** (CT-driven action ordering). A different game.
    Requires a separate per-tick scheduler stage and a different victory
    model. Out of scope for this codebase; document if/when serious.

---

## Appendix A — File map and authoritative line refs

```
godot-learning/
├── src/gpu/
│   ├── GPUBatchSimulator.gd                  ← shader compile + dispatch loop (~1,400 LoC)
│   │   ├── _load_shader_with_includes()      ← runtime #include preprocessor
│   │   ├── _compile_stage_shader_cached()    ← per-stage SPIR-V cache + timing
│   │   └── _run_tick()                       ← the 5-pass dispatch
│   ├── GambitEncoder.gd                      ← Gambit → 16-int GPU schema
│   ├── GPUConstants.gd                       ← shared constants
│   └── shaders/                              ← the live shader code
│       ├── combat_common.glsl                ← base header — U_* offsets, SSBO decls, accessors, RNG, ability helpers
│       ├── combat_combat.glsl                ← combat helpers — LOS, weapon range, attack-anim setup, formula dispatch
│       ├── stage_compute.glsl                ← Pass 0: per-unit decision + action setup (THE LONG POLE)
│       ├── stage_resolve.glsl                ← Pass 1: movement conflict resolution
│       ├── stage_post_conflict.glsl          ← Pass 2: opportunistic attacks after move
│       ├── stage_damage.glsl                 ← Pass 3: AOE + single-target damage
│       └── stage_victory.glsl                ← Pass 4: end-of-battle detection
├── docs/
│   ├── compute_shader_status.md              ← THIS DOCUMENT
│   ├── shader_compile_refactor.md            ← compile-time refactor post-mortem
│   ├── gpu-ai-system.md                      ← architectural reference (written for monolith; mostly still valid)
│   └── gpu-ai-improvements.md                ← tiered improvement opportunities (overlaps §6 above)
└── tests/                                    ← 56 .tscn files; 44 extend GPUCombatTestBase
    ├── GPUArenaTest.tscn                     ← 4v4 sandbox with mixed ability types
    ├── MinimalistArenaTest.tscn              ← 4v4 baseline: all units attack-nearest-enemy
    ├── PipelineTest.gd / ShaderCompileBench.gd / StartupDiagnostic.gd
    │                                         ← compile-time benches; iterate over the per-stage files
    ├── GPUFormula01..78Test.tscn             ← 11 damage-formula validation tests
    └── GPU{Spell,AOE,Status,Evasion}*Test    ← feature-specific tests
```

## Appendix B — How to extend it without breaking things

The system has a small set of invariants that, if respected, mean changes
won't silently break combat behavior:

1. **Never change the `U_*` field offsets.** They're hardcoded into both the
   shader and `GPUBatchSimulator.gd` (`UnitField` enum, `UNIT_SIZE`). Adding
   a new field means appending to the enum + bumping `UNIT_SIZE` + bumping
   `EXPECTED_SHADER_VERSION`. `CLAUDE.md:351` documents the failure mode if
   you forget.
2. **Increment `SHADER_VERSION`** in `combat_common.glsl` for any structural
   change. `GPUBatchSimulator` validates this at init.
3. **Touch only one stage file at a time when iterating**. Stage 2a's win is
   that editing `stage_resolve.glsl` doesn't recompile `stage_compute.glsl`.
   Editing `combat_common.glsl` invalidates every stage's cache — save those
   edits for batches.
4. **Verify GLSL function ordering**. GLSL requires definitions before callers.
   If you add a helper, place it above its first call site. `CLAUDE.md:357`
   documents the silent-fail mode.
5. **Reserve GLSL keywords.** `half`, `input`, `output`, `sampler`, `filter`,
   `fixed`. Compile errors show up in the Godot log at
   `app_userdata/learning/logs/godot.log`. `CLAUDE.md:358`.
6. **Test mode flag.** `test_mode == 1` is the "debug fields populated, no
   early-out on victory" path used by `tests/`. Production code (`GPUArena`)
   runs with `test_mode == 0`. Most new debug fields should be guarded by
   this.
7. **Determinism.** Any randomness must flow through `rand_int()` with a seed
   derived from (caster_id, target_id, tick). This is what makes
   `GPUSeedReproTest` work. Direct PCG calls without this seeding break
   replay.

If you're adding a Tier 2 capability (§7), the smallest viable patch is:

1. One new field or two on the unit struct (or repurpose an existing
   `U_DBG_*` if test-mode-only).
2. One new helper function in `combat_common.glsl` or `combat_combat.glsl`.
3. One call site in the relevant stage (`stage_compute.glsl` for decision,
   `stage_damage.glsl` for resolution).
4. One test scene in `tests/` modeled on the existing `GPUStatusNoDamageTest`
   or `GPUProtectTest` pattern.
5. (Optional) one paragraph appended to §4 of this document moving the
   capability from "Scaffolded" to "Implemented and tested."

That's the whole loop.
