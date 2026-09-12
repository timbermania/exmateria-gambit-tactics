# GPU AI System Architecture

> **Note (2026-05-30):** This document still describes the system as it lived
> in the monolithic `combat_batch.glsl`. The architecture is unchanged; the
> code has been split into per-stage files under `src/gpu/shaders/`. For the
> current file layout and per-stage line refs, see
> [`compute_shader_status.md`](compute_shader_status.md) §3. The Stage 2b
> plan for further decomposition lives in
> [`stage_2b_implementation_plan.md`](stage_2b_implementation_plan.md).

The entire combat AI runs inside a GLSL compute shader pipeline
(`src/gpu/shaders/stage_*.glsl`, ~2,580 lines total across 5 stages). There
is no CPU-side game loop for combat logic — the shader IS the game.
GDScript uploads unit stats and gambit rules, dispatches the per-tick
compute passes, and reads back results for rendering.

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [The Gambit System](#2-the-gambit-system)
3. [Target Selection](#3-target-selection)
4. [Condition System](#4-condition-system)
5. [Action Execution](#5-action-execution)
6. [State Machine](#6-state-machine)
7. [Attack System](#7-attack-system)
8. [Spell & Ability System](#8-spell--ability-system)
9. [Pathfinding](#9-pathfinding)
10. [Line of Sight](#10-line-of-sight)
11. [Conflict Resolution & Movement](#11-conflict-resolution--movement)
12. [Damage System](#12-damage-system)
13. [Status Effects & Reactions](#13-status-effects--reactions)
14. [Timing & Animation](#14-timing--animation)
15. [CPU-GPU Data Flow](#15-cpu-gpu-data-flow)

---

## 1. Design Philosophy

### Why GPU?

The system batch-simulates hundreds of battles in parallel to evaluate roster compositions and balance. A single compute dispatch processes every unit across every battle simultaneously. This turns what would be minutes of sequential CPU simulation into milliseconds of GPU work.

### Double-Buffer Ping-Pong

All unit state lives in a single SSBO (binding 3) split into two halves. Each tick, every unit reads from `current_buffer` and writes to `1 - current_buffer`. After all passes complete, the buffers swap. This guarantees true simultaneity — no unit sees partially-updated state from the current tick.

```
Buffer 0: [Battle0: header unit0..unit7] [Battle1: header unit0..unit7] ...
Buffer 1: [Battle0: header unit0..unit7] [Battle1: header unit0..unit7] ...

Tick N:   Read from Buffer 0, Write to Buffer 1
Tick N+1: Read from Buffer 1, Write to Buffer 0
```

### 5-Pass Multi-Dispatch Model

Each tick requires 5 sequential compute dispatches with barriers between them:

| Pass | Constant | Threads | Purpose |
|------|----------|---------|---------|
| 0 | `PASS_COMPUTE_STATE` | 1 per unit | Each unit decides its next action |
| 1 | `PASS_RESOLVE_CONFLICTS` | 1 per battle | Resolve movement collisions |
| 2 | `PASS_POST_CONFLICT_ATTACKS` | 1 per battle | Check attacks after positions finalize |
| 3 | `PASS_APPLY_DAMAGE` | 1 per battle | Apply all queued damage atomically |
| 4 | `PASS_CHECK_VICTORY` | 1 per battle | Determine win/loss/draw |

Pass 0 is massively parallel (one thread per unit across all battles). Passes 1-4 are one thread per battle, iterating units sequentially within each battle to avoid write conflicts.

---

## 2. The Gambit System

Gambits are FFXII-inspired priority-ordered if-then rules. Each unit has 5 slots evaluated top-to-bottom. The first gambit whose conditions pass gets executed.

### Data Layout

Gambit data lives in a dedicated SSBO (binding 6). Each gambit is 16 ints, 5 gambits per unit = 80 ints per unit.

**Offset formula**: `global_unit_id * 80 + slot * 16 + field`

| Offset | Field | Purpose |
|--------|-------|---------|
| 0 | `GM_ENABLED` | 1 = active, 0 = skip |
| 1 | `GM_COND_TARGET_TYPE` | Who to evaluate conditions against |
| 2 | `GM_COND_COUNT` | Number of conditions (0-4) |
| 3-6 | `GM_COND_TYPE_0..3` | Condition type enums |
| 7-10 | `GM_COND_VAL_0..3` | Condition threshold values |
| 11 | `GM_ACTION_TYPE` | What to do (attack, spell, item, wait, move) |
| 12 | `GM_ACTION_ID` | Ability/item ID (or packed coords for move) |
| 13 | `GM_ACTION_TARGET_TYPE` | Who to perform the action on |
| 14-15 | Reserved | |

### Evaluation Flow

```
evaluate_gambits(battle_id, unit_id)          [line 2267]
  for slot in 0..4:
    if !gambit_enabled(slot): continue

    candidate = select_target(cond_target_type)   // Who to check
    if candidate < 0: continue

    for each condition (AND-ed):
      if !evaluate_condition(candidate, type, value): break

    if all_pass:
      if execute_gambit_action(slot, candidate):   // Try the action
        return true                                // Success — stop
      // Action failed → FALLTHROUGH to next gambit

  return false  // No gambit matched
```

### Fallthrough

If a gambit's conditions pass but the action fails (e.g., spell out of range, no MP, blocked LOS), execution falls through to the next gambit slot. This allows backup strategies — e.g., slot 0 tries a spell, slot 1 falls back to melee attack.

The fallthrough mechanism works by checking the return value of `execute_gambit_action()`. For spells/abilities, the function reads back the unit's state after calling `start_spell()` — if the state is still `STATE_IDLE`, the spell failed and `false` is returned.

### Preemption

Units in `STATE_MOVING` re-evaluate gambits each time their movement timer expires (line 2481). If a higher-priority gambit now applies (e.g., an ally dropped to low HP triggering a heal gambit), the unit can abandon its current movement and switch actions.

---

## 3. Target Selection

`select_target()` (line 1117) maps a target type enum to a finder function:

| Type | Value | Behavior |
|------|-------|----------|
| `TARGET_SELF` | 0 | Returns self |
| `TARGET_NEAREST_ENEMY` | 1 | Closest enemy by BFS distance |
| `TARGET_NEAREST_ALLY` | 2 | Closest ally by BFS distance |
| `TARGET_LOWEST_HP_ALLY` | 3 | Ally with lowest HP% |
| `TARGET_HIGHEST_HP_ENEMY` | 4 | Enemy with highest HP% |
| `TARGET_LOWEST_HP_ENEMY` | 5 | Enemy with lowest HP% |
| `TARGET_HIGHEST_HP_ALLY` | 6 | Ally with highest HP% |
| `TARGET_THEM` | 7 | Use the condition's target as the action's target |

Each finder iterates all units in the battle, filters by team and alive status, computes its metric (distance or HP%), and returns the best match. Distance-based finders (`find_nearest_enemy`, `find_nearest_ally`, `find_nearest_attackable_enemy`) use BFS distance from the pre-computed distance field, not Manhattan distance. Unreachable targets (BFS distance = -1) are skipped. `TARGET_THEM` is special — it tells `execute_gambit_action()` to reuse the target that was selected for condition evaluation, enabling patterns like "if nearest enemy HP < 25% → attack THEM."

---

## 4. Condition System

`evaluate_condition()` (line 926) checks a single condition against a target unit:

| Type | Value | Check |
|------|-------|-------|
| `COND_ALWAYS` | 0 | Always true |
| `COND_HP_BELOW` | 1 | Target HP% < value |
| `COND_HP_ABOVE` | 2 | Target HP% > value |
| `COND_DISTANCE_LESS` | 3 | Manhattan distance < value |
| `COND_DISTANCE_GREATER` | 4 | Manhattan distance > value |
| `COND_HAS_STATUS` | 5 | Target has status bit set |
| `COND_NOT_STATUS` | 6 | Target lacks status bit |
| `COND_IS_DEAD` | 7 | Target is dead |
| `COND_IS_ALIVE` | 8 | Target is alive |
| `COND_MP_ABOVE` | 9 | Self MP% > value |
| `COND_MP_BELOW` | 10 | Self MP% < value |
| `COND_TEAM_ALLY` | 11 | Target is on same team |
| `COND_TEAM_ENEMY` | 12 | Target is on different team |

All conditions within a gambit are AND-ed with short-circuit evaluation — the first failure skips remaining conditions. HP/MP conditions use percentage (0-100), distance uses Manhattan tiles.

---

## 5. Action Execution

`execute_gambit_action()` (line 2210) resolves the final target and dispatches:

| Action | Value | Handler |
|--------|-------|---------|
| `ACTION_ATTACK` | 0 | `execute_attack_gambit()` |
| `ACTION_SPELL` | 1 | `start_spell()` |
| `ACTION_ITEM` | 2 | `start_spell()` (items are abilities) |
| `ACTION_WAIT` | 3 | Set `STATE_IDLE`, timer = `TICKS_PATH_RETRY` (47) |
| `ACTION_ABILITY` | 4 | `start_spell()` |
| `ACTION_MOVE_TO` | 5 | `execute_move_to_gambit()` — coords packed as `x * 256 + z` |

### ACTION_ATTACK Flow

`execute_attack_gambit()` (line 2143):

1. **Can attack now?** `can_attack_target()` checks range, height, and LOS
2. **Yes →** `setup_attack_animation()` immediately
3. **No →** `find_nearest_attack_position()` for the target
4. **No position →** `find_nearest_attackable_enemy()` finds an alternative enemy
5. **Found →** `get_next_step()` toward the position, set `STATE_MOVING`
6. **Nothing →** `STATE_IDLE` with retry timer

### ACTION_SPELL Flow

`start_spell()` (line 1913):

1. Check MP cost — fail if insufficient
2. Calculate effective range (`get_effective_ability_range()`)
3. Check vertical tolerance (if ability has `ABFLAG_VERTICAL_TOLERANCE`)
4. If in range: check LOS for projectile abilities
5. **In range + LOS OK →** Spend MP, set `STATE_CHARGING`, timer = charge_time
6. **Out of range or LOS blocked →** Set `STATE_MOVING_TO_CAST` with destination

---

## 6. State Machine

Each unit has one of 8 states. State transitions are timer-driven — each state sets a timer, and the handler fires when the timer reaches 0.

```
STATE_IDLE (0)           — Evaluate gambits, check for victory
STATE_MOVING (1)         — Walking toward destination tile-by-tile
STATE_ACTING (2)         — Playing attack/cast animation, trigger damage at damage_frame
STATE_REACTING (3)       — Playing reaction ability (counter-attack, etc.)
STATE_CHARGING (4)       — Charging a spell (countdown to cast)
STATE_MOVING_TO_CAST (5) — Moving to get in range for a spell
STATE_DEAD (6)           — Permanent, skip all processing
STATE_VICTORIOUS (7)     — Permanent, skip all processing
```

### Main Dispatcher

`compute_unit_state()` (line 2644) runs for every unit each tick:

1. **Copy** entire unit state from read buffer to write buffer
2. **Skip** if dead or victorious
3. **Decrement timer** — if timer > 0 after decrement, return (not ready yet)
4. **Check damage frame** — if in `STATE_ACTING` and animation reached damage_frame, trigger damage
5. **Dispatch** to state handler when timer reaches 0

### State Handlers

**STATE_IDLE** (line 2749): Check if enemy team is dead → `STATE_VICTORIOUS`. Otherwise call `evaluate_gambits()`. If no gambit matches, set retry timer.

**STATE_MOVING** (`handle_moving_state()`, line 2475): Re-evaluate higher-priority gambits. Check if target is now attackable. Find attack position and pathfind. If no path, fall back to IDLE with retry.

**STATE_ACTING** (line 2713): When animation timer expires, clear ability fields, return to `STATE_IDLE`.

**STATE_CHARGING** (line 2721): Decrement `U_CAST_TIMER`. When it reaches 0, call `complete_spell_cast()`.

**STATE_MOVING_TO_CAST** (`handle_moving_to_cast_state()`, line 2544): Check spell range and LOS. If ready, spend MP and transition to `STATE_CHARGING`. Otherwise keep moving.

**STATE_REACTING** (line 2736): Validate target is still alive and in range, then `setup_attack_animation()`.

---

## 7. Attack System

### Attack Types

Determined by weapon flags and range via `get_attack_type()` (line 1151):

| Type | Value | Description | Range | Height Limit | LOS |
|------|-------|-------------|-------|--------------|-----|
| `ATTACK_STRIKING` | 0 | Adjacent melee | 1 | Up 2 / Down 3 | None |
| `ATTACK_LUNGING` | 1 | Line melee | 1-weapon_range, cardinal only | Up 2 / Down 3 | Direct |
| `ATTACK_DIRECT` | 2 | Ranged, flat trajectory | 1-weapon_range | None | Direct |
| `ATTACK_ARCING` | 3 | Bows, parabolic | min 3, bonus from elevation | Up 2 / Down 3 | Arc |

For arcing attacks, effective range gets a bonus from elevation: `effective_range = weapon_range + (-height_diff / 2)`, clamped to `[3, weapon_range]`.

### Position Finding

`find_nearest_attack_position()` (line 1493): Checks all 4 tiles adjacent to the target. For each tile, validates traversability, jump height, attack validity from that position, and occupancy. Returns the closest valid unoccupied tile.

`find_nearest_attackable_enemy()` (line 1616): Fallback when the primary target has no reachable attack position. Iterates all enemies, checks if any attack position exists, returns the closest one by Manhattan distance.

### Evasion

`roll_evasion()` determines if an attack hits. Physical and magic attacks use different evasion pools:

| Attack Type | C_EV | S_EV | W_EV | Cap |
|-------------|------|------|------|-----|
| Physical | Class evade | Physical shield block (`U_S_EV`) | Weapon evade | 99% |
| Magic | Class evade | Magic shield block (`U_S_EV_MAG`) | None | 99% |

Formula: `total_evade = min(c_ev + s_ev + w_ev, 99)`. Roll 1-100; hit if roll > total_evade.

Non-evadeable abilities (`ABFLAG_EVADEABLE` not set) skip the evasion roll entirely. Weapon attacks always use physical evasion.

### Animation Timing

Attack animations use lookup tables from `anim_timings` (binding 5). Two tables: TYPE1 (character animations) and WEP1 (weapon animations, offset by `WEP1_TIMING_OFFSET = 768`). Each entry provides `damage_frame`, `projectile_frame`, and `total_frames`.

---

## 8. Spell & Ability System

### Ability Data

512 abilities x 16 ints in the `ability_data` SSBO (binding 7):

| Offset | Field | Description |
|--------|-------|-------------|
| 0 | `AB_MP_COST` | MP cost to cast |
| 1 | `AB_CHARGE_TIME` | Charge ticks (CT * 30 from CPU) |
| 2 | `AB_RANGE` | Fixed range (0 = use weapon range) |
| 3 | `AB_FORMULA_ID` | Damage formula type |
| 4 | `AB_FORMULA_Y` | Y coefficient (multiplier/healing amount) |
| 5 | `AB_EFFECT_AREA` | AOE radius (Manhattan distance) |
| 6 | `AB_FORMULA_X` | X coefficient (stat reduction amount) |
| 7 | `AB_ELEMENT` | Element (0=none, 1=fire, 2=ice, ..., 8=dark) |
| 8 | `AB_FLAGS` | Bit flags (see below) |
| 9 | `AB_EFFECT_ANIM_ID` | Animation ID (cast anim = id * 2) |
| 10 | `AB_VERTICAL` | Vertical tolerance in half-steps |

### Ability Flags

| Flag | Bit | Effect |
|------|-----|--------|
| `ABFLAG_REFLECTABLE` | 1 | Can be reflected |
| `ABFLAG_EVADEABLE` | 2 | Can be evaded |
| `ABFLAG_HEALING` | 4 | Heals instead of damages |
| `ABFLAG_MP_DAMAGE` | 8 | Damages MP instead of HP |
| `ABFLAG_WEAPON_RANGE` | 16 | Use weapon range instead of fixed |
| `ABFLAG_THROW_RANGE` | 32 | Range = Speed / 2 + 1 (Ninja Throw) |
| `ABFLAG_VERTICAL_TOLERANCE` | 64 | Enforce vertical height check |

### Range Calculation

`get_effective_ability_range()` (line 768):

1. **base_range = 0** → return unit's weapon range
2. **ABFLAG_THROW_RANGE set** → return `speed / 2 + 1`
3. **Otherwise** → return base_range as-is

### Charge-to-Cast Flow

```
STATE_IDLE
  → evaluate_gambits() → start_spell()
  → MP check, range check, vertical check, LOS check
  → Spend MP
  → STATE_CHARGING (timer = charge_time, set STATUS_CHARGING)
    → Decrement U_CAST_TIMER each tick
    → When timer = 0 → complete_spell_cast()
      → Select animation (spell anim or item throw)
      → Dispatch to cast function:
        → cast_projectile_spell()  — projectiles with flight time
        → cast_adjacent_item()     — items used at close range
        → cast_instant_spell()     — instant damage/heal/AOE
      → STATE_ACTING (timer = animation duration)
```

### Projectile Spells

`cast_projectile_spell()` (line 1998):
- `flight_ticks = max(distance * FLIGHT_TICKS_PER_TILE, MIN_FLIGHT_TICKS)` (10 ticks/tile, min 15)
- `damage_frame = projectile_frame + flight_ticks`
- Total timer ensures animation completes after damage: `max(scaled_duration, damage_frame)` (the `ANIM_SAFETY_MARGIN` pad was retired — see ADR-0028)

### AOE

AOE abilities store their center position and ability ID on the caster (`U_AOE_CENTER_X/Z`, `U_AOE_ABILITY_ID`). Resolution happens in Pass 3 (`PASS_APPLY_DAMAGE`), which iterates all units within Manhattan distance of the AOE center. Smart targeting applies: healing abilities only affect allies, damage/break abilities only affect enemies.

---

## 9. Pathfinding

### Target Ranking by BFS Distance

Target selection functions (`find_nearest_enemy`, `find_nearest_ally`, `find_nearest_attackable_enemy`) rank candidates by BFS distance from the pre-computed distance field, not Manhattan distance. This ensures units prefer targets that are actually reachable over targets that are geometrically close but behind walls or impassable terrain. Targets with no valid path (BFS distance = -1) are skipped entirely.

### Greedy Single-Step BFS

`get_next_step()` decides one tile at a time — there is no multi-tile path planning.

**Algorithm:**
1. Check 4 orthogonal neighbors
2. For each: validate traversability, jump height (`abs(height_diff) <= jump`), occupancy
3. **Greedy pass**: prefer tiles that reduce Manhattan distance to goal
4. **Fallback pass**: if all greedy moves blocked, accept lateral or even backwards moves
5. Returns the chosen neighbor, or `(-1, -1)` if completely stuck

### Ally Pass-Through

`find_passthrough_destination()` (line 1327): When a unit is blocked by a friendly unit, it can "slide through" up to `PASSTHROUGH_MAX_TILES = 8` tiles in the same direction. The scan stops at the first unoccupied tile, or fails if it hits an enemy, a non-traversable tile, or an impassable height change.

### Tile Validation

- **Traversability**: `is_tile_traversable()` checks bounds and walkability flag from map data
- **Jump height**: `abs(destination_height - source_height) > unit_jump` blocks movement
- **Occupancy**: `get_tile_occupant()` returns the unit on a tile (-1 if empty). The pathfinder treats the movement target's tile as empty (so units can path toward their attack target).

---

## 10. Line of Sight

### Direct LOS

`has_line_of_sight_direct()` (line 1200): DDA (Digital Differential Analyzer) line trace along the longest axis, max 8 iterations. For each intermediate tile, linearly interpolates the expected height between source and target. If any intermediate tile's height exceeds the interpolated height, LOS is blocked. Adjacent tiles (distance <= 1) auto-pass.

Used by: `ATTACK_LUNGING`, `ATTACK_DIRECT`

### Arc LOS

`has_line_of_sight_arc()` (line 1225): Parabolic trajectory check. The arc peaks at `distance * ARC_LOS_HEIGHT_PER_TILE` (0.5 half-steps per tile of distance). Height at each point follows `arc_peak * (1 - (2t - 1)^2)` where t is progress 0..1. Intermediate tiles must not exceed the interpolated base height plus arc offset.

Used by: `ATTACK_ARCING`, projectile abilities (Ninja Throw, Chemist items)

Key insight: shorter distance = higher relative arc clearance, so moving closer to a target improves LOS. This drives the `STATE_MOVING_TO_CAST` behavior when arc LOS fails.

---

## 11. Conflict Resolution & Movement

### Pass 1: PASS_RESOLVE_CONFLICTS

`resolve_conflicts()` (line 2765): One thread per battle, iterates all units sequentially.

**Two units proposing the same tile:**
- The closer unit (by Manhattan distance from current position) wins
- Tie-breaker: lower unit ID wins (deterministic, allows progress)

**Moving into an occupied tile:**
- If the occupant is staying put, the mover is blocked

**Blocked units:**
- Proposed position reverted to current position
- Timer set to 1 (immediate retry next tick)
- State remains `STATE_MOVING`

### Pass 2: PASS_POST_CONFLICT_ATTACKS

`post_conflict_attacks()` (line 2874): After positions are finalized, checks if any `STATE_MOVING` unit with `timer == 1` (blocked) is now adjacent to an enemy. If so, that unit can immediately attack instead of waiting. This simulates the sequential processing on CPU where a later-processed unit sees an earlier unit's updated position.

---

## 12. Damage System

### Pass 3: PASS_APPLY_DAMAGE

`apply_damage()` (line 2946) runs three phases:

**Phase 1 — AOE Resolution** (line 2949): For each unit with a queued AOE (`U_AOE_ABILITY_ID >= 0`), find all targets within `effect_area` Manhattan distance of `U_AOE_CENTER_X/Z`. Apply smart targeting (damage→enemies, heal→allies). Accumulate to each target's `U_PENDING_DAMAGE`.

**Phase 2 — Single-Target Damage** (line 3002): For each unit with `U_DAMAGE_TARGET >= 0`, add `U_DAMAGE_AMOUNT` to the target's `U_PENDING_DAMAGE`.

**Phase 3 — Apply All Pending** (line 3019): For each unit with `U_PENDING_DAMAGE > 0`, subtract from HP. If HP <= 0, set `FLAG_DEAD`. Clear pending damage.

This three-phase approach ensures deterministic, simultaneous damage application regardless of unit processing order.

### Damage Formulas

`calculate_damage()` — Physical attacks: `PA * WP` (minimum 1). If the defender has **Protect** status, damage is halved (minimum 1).

`calculate_spell_damage()` — Formula-based dispatch. If the defender has **Shell** status and the formula is magic-based (formulas 8, 12, 32, 78, 36), damage is halved (minimum 1). Shell does NOT affect percentage formulas (13) or item formulas (72).

| Formula ID | Name | Calculation |
|------------|------|-------------|
| 0x01 | Weapon | `PA * WP` |
| 0x08 | Magic (faith) | `MA * Y * caster_faith * target_faith / 10000` |
| 0x0C | Heal (faith) | Same as 0x08 |
| 0x0D | Raise | `max_hp * Y / 100` |
| 0x20 | Summon | `MA * Y` |
| 0x24 | Holy Sword (hybrid) | `(PA + Y) / 2 * MA` |
| 0x25 | Equipment Break | Hit chance: `PA + WP + Y` %, breaks weapon/shield |
| 0x2B | Stat Break | Hit chance: `PA + Y` %, reduces stat by X |
| 0x2C | MP Damage | Hit chance: `PA + Y` %, drains `max_mp * Y / 100` |
| 0x31 | PA Hybrid | `(PA + Y) / 2 * PA` |
| 0x37 | Ranged Physical | `PA * Y` (ThrowStone) |
| 0x48 | Item | `Y * 10` |
| 0x4E | Monster Magic | `MA * Y` |

---

## 13. Status Effects & Reactions

### Status Bits

64 status effects across two 32-bit fields (`U_STATUS_FLAGS_LO` and `U_STATUS_FLAGS_HI`):

| Bit | Status | Bit | Status |
|-----|--------|-----|--------|
| 0 | Dead | 16 | Regen |
| 1 | Undead | 17 | Protect |
| 2 | Charging | 18 | Shell |
| 3 | Jump | 19 | Haste |
| 4 | Defending | 20 | Slow |
| 5 | Performing | 21 | Float |
| 6 | Petrify | 22 | Reraise |
| 7 | Stop | 23 | Transparent |
| 8 | Sleep | 24 | Confusion |
| 9 | Immobilize | 25 | Silence |
| 10 | Disable | 26 | Blood Suck |
| 11 | Blind | 27 | Curse |
| 12 | Berserk | 28 | Invite |
| 13 | Chicken | 29 | Darkness |
| 14 | Frog | 30 | Oil |
| 15 | Poison | 31 | Faith |

Helpers: `has_status()`, `set_status()`, `clear_status()` operate on the appropriate LO/HI field using `status_bit % 32` for the shift amount.

**Active gameplay statuses:**

| Status | Effect |
|--------|--------|
| Protect (17) | Physical damage halved in `calculate_damage()` |
| Shell (18) | Magic damage halved in `calculate_spell_damage()` |
| Haste (19) | Movement ticks halved in `write_movement_step()` |
| Slow (20) | Movement ticks doubled in `write_movement_step()` |
| Charging (2) | Set during spell charge phase |

### Reaction Abilities

Each unit has one equipped reaction ability (`U_REACTION_ABILITY`):

| Reaction | ID | Trigger | Effect |
|----------|----|---------|--------|
| `REACT_COUNTER` | 0 | After taking melee damage | Counter-attack if attacker within distance 1 |
| `REACT_FIRST_STRIKE` | 1 | Before being attacked | If in STATE_IDLE, attack attacker first (STATE_REACTING) |
| `REACT_ABSORB_MP` | 2 | After taking damage | Gain MP equal to damage / 4 |
| `REACT_AUTO_POTION` | 3 | After damage drops HP low | If HP < max_hp / 4, heal 50 HP |
| `REACT_BLADE_GRASP` | 4 | Physical attack incoming | High physical evasion |
| `REACT_ARROW_GUARD` | 5 | Projectile attack incoming | Block arrows |
| `REACT_MANA_SHIELD` | 6 | Any damage | Convert damage to MP loss; overflow hits HP |

Reactions are checked at two points:
- **Pre-damage**: `check_pre_damage_reactions()` (line 2310) — triggers `REACT_FIRST_STRIKE`
- **Post-damage**: `apply_damage_with_reactions()` (line 2325) — triggers all others, accumulates to `U_PENDING_DAMAGE`

---

## 14. Timing & Animation

### Core Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `GPU_TICKS_PER_SECOND` | 60.0 | Tick rate |
| `GLOBAL_SPEED_DIVISOR` | 1.0 | Global speed multiplier |
| `TICKS_PATH_RETRY` | 47 | Wait before retrying blocked actions |
| `TICKS_PER_REACTION` | 80 | Reaction ability cooldown |
| `TICKS_PER_SEQ_FRAME` | 2 | GPU ticks per animation frame |
| `FLIGHT_TICKS_PER_TILE` | 10 | Projectile flight speed |
| `MIN_FLIGHT_TICKS` | 15 | Minimum projectile flight duration |
| `MIN_ATTACK_DURATION` | 30 | Minimum attack/cast ticks (~0.5s) |
| `DEFAULT_CAST_DURATION` | 60 | Fallback cast duration (~1s) |
| `AUTO_POTION_HEAL_AMOUNT` | 50 | HP restored by auto-potion |
| `PASSTHROUGH_MAX_TILES` | 8 | Max tiles for ally pass-through scan |

### Movement Speeds

| Constant | Value | Purpose |
|----------|-------|---------|
| `HORIZONTAL_MOVE_SEQ_SPEED` | 1 | Flat walking speed multiplier |
| `VERTICAL_MOVE_SEQ_SPEED` | 2 | Cliff jump speed (2x faster) |
| `CHARGE_SEQ_SPEED` | 1 | Spell charge tick rate |
| `ABILITY_SEQ_SPEED` | 1 | Cast animation speed |

### Haste/Slow Movement Speed

`write_movement_step()` scales the movement timer based on status effects:
- **Haste**: `move_ticks = max(1, move_ticks / 2)` — units move twice as fast
- **Slow**: `move_ticks = move_ticks * 2` — units move at half speed
- **Normal**: no scaling

This only affects movement. Retry delays, attack animations, and charge times are unaffected.

### Timer-Driven States

Every state sets a timer. The main dispatcher decrements the timer each tick and only calls the state handler when it reaches 0. This means:
- Movement: timer = ticks to cross one tile (varies by terrain, scaled by Haste/Slow)
- Attacking: timer = animation duration in ticks
- Charging: separate `U_CAST_TIMER` decremented by `CHARGE_SEQ_SPEED` per tick
- Blocked: timer = 1 (retry immediately next tick)

---

## 15. CPU-GPU Data Flow

### Upload Pipeline

```
CPU (GDScript)                              GPU (GLSL)
─────────────────                           ──────────────
Unit node (.gd)
  ↓ _extract_unit_config()
  ↓ Dictionary{pos, hp, stats, weapon...}
  ↓ set_battle_units()
  └──→ Battle Buffer (binding 3)     ──→    read_unit(field)

GambitList (4 visible + 1 fallback)
  ↓ Gambit objects
  ↓ GambitEncoder.encode_gambits()
  ↓ PackedInt32Array (80 ints/unit)
  ↓ set_unit_gambits()
  └──→ Gambit Buffer (binding 6)     ──→    gambit_data.gambits[]

AbilityDatabase.ABILITIES
  ↓ _build_ability_database()
  ↓ PackedInt32Array (8192 ints)
  └──→ Ability Buffer (binding 7)    ──→    ability_data.abilities[]

Map heightmap + traversability
  ↓ _create_buffers()
  └──→ Map Buffer (binding 1)        ──→    map_data.tile_data[]
```

### GambitEncoder Translation

`GambitEncoder.gd` translates high-level Gambit objects to flat int arrays:

- `TargetSelector` → `TargetType` int (SELF=0, NEAREST_ENEMY=1, etc.)
- `GambitCondition` → condition type + value ints
- Action name (`StringName`) → action type + ability ID via `AbilityDatabase.get_ability_by_name()`
- Items and throw abilities resolve to their ability IDs in the 512-entry ability table

### Readback

`get_battle_unit_states()` reads the current buffer and returns `Array[Dictionary]` with per-unit state. The CPU uses this to sync shadow units for rendering (animation frames, positions, health bars).

### SSBO Bindings Summary

| Binding | Buffer | Size | Access |
|---------|--------|------|--------|
| 0 | SimConfig | 9 ints | Read-only, per-pass config |
| 1 | MapData | tiles * 3 sections | Read-only, shared |
| 2 | DistanceField | pre-computed distances | Read-only, shared |
| 3 | BattleData | 2x (battles * (4 + units * 80)) ints | Read/Write, ping-pong |
| 4 | Results | battles * 4 ints | Write (pass 4 only) |
| 5 | AnimTimings | animation lookup table | Read-only |
| 6 | GambitData | global_units * 80 ints | Read-only |
| 7 | AbilityData | 512 * 16 ints | Read-only |

---

## Key Files

| File | Role |
|------|------|
| `src/gpu/combat_batch.glsl` | The entire AI + combat simulation (~3,170 lines) |
| `src/gpu/GPUBatchSimulator.gd` | Buffer management, 5-pass dispatch, CPU-GPU bridge |
| `src/gpu/GambitEncoder.gd` | Translates Gambit objects to GPU int arrays |
| `src/ai/gambit/Gambit.gd` | Single gambit rule (condition target, conditions, action) |
| `src/ai/gambit/GambitList.gd` | Ordered list of 4 visible + 1 fallback gambit per unit |
| `src/ai/gambit/GambitCondition.gd` | Condition types, comparators, and evaluation |
| `src/ai/gambit/TargetSelector.gd` | Target pool types and resolution strategies |
