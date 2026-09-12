# GPU AI System — Improvement Analysis

> **Note (2026-05-30):** Line references in this document point into the
> deleted monolith `src/gpu/combat_batch.glsl`. The corresponding code now
> lives in `src/gpu/shaders/stage_*.glsl` — see
> [`compute_shader_status.md`](compute_shader_status.md) §3 for the current
> layout. The opportunities themselves are still valid; only the file paths
> and line numbers below are stale.

Concrete improvement opportunities for the GPU combat AI (now distributed
across `src/gpu/shaders/stage_*.glsl`, ~2,580 lines total), organized by
effort and impact. Based on the architecture documented in
[gpu-ai-system.md](gpu-ai-system.md).

## Table of Contents

- [Findings Summary](#findings-summary)
- [Tier 1: Activate Existing Systems](#tier-1-activate-existing-systems-low-effort-code-already-exists)
- [Tier 2: Extend Gambit Expressiveness](#tier-2-extend-gambit-expressiveness-medium-effort-no-architecture-change)
- [Tier 3: Fix Pathfinding](#tier-3-fix-pathfinding-medium-effort-high-impact)
- [Tier 4: Deeper AI](#tier-4-deeper-ai-larger-effort-new-capabilities)
- [Recommended Sequence](#recommended-sequence)
- [Key Files](#key-files)

---

## Findings Summary

### Dead Code / Disabled Systems

| System | Location | Status |
|--------|----------|--------|
| **Evasion** | `roll_evasion()` line 1652 | `return true;` — always hits. Full implementation commented out below (lines 1657-1662). |
| **Reactions** | `check_pre_damage_reactions()` line 2310, `apply_damage_with_reactions()` line 2325 | Fully implemented but **never called anywhere**. |
| **Status timers** | `U_STATUS_TIMER_0..7` (lines 112-119) | 8 timer slots declared, never decremented. No ability inflicts status effects except hardcoded `STATUS_CHARGING`. |
| **Elements** | `AB_ELEMENT` (line 415) | Exists on abilities, never read in damage calculation. |
| **Support/Movement abilities** | `U_SUPPORT_ABILITY` line 127, `U_MOVEMENT_ABILITY` line 128 | Fields declared, never read. |
| **Speed stat** | `U_SPEED` (line 54) | Only used for throw range (`speed/2+1` at line 775). No effect on action frequency or turn order. |

### Pathfinding Limitations

- **Greedy single-step only** — `get_next_step()` (line 1363) picks the one neighbor that reduces BFS distance. No A*, no multi-step planning.
- **`find_nearest_attack_position()` only checks 4 adjacent tiles** (line 1493) — Ranged/lunging weapons (range 2+) never search positions beyond distance 1 from the target. Ranged units walk adjacent instead of stopping at range.
- **`find_nearest_attackable_enemy()` uses Manhattan distance** (line 1631) — Should use `get_distance()` (BFS pathfinding distance) which already exists. Units chase targets that look close but require long detours.
- **No anti-oscillation** — Blocked units retry the same move next tick via `timer=1`. No memory of what was just blocked.

### AI Decision Quality Gaps

- **Target selection is single-metric** — Either distance or HP%. No threat assessment, no damage potential.
- **No positioning intelligence** — No height advantage preference, no kiting, no defensive positioning.
- **No coordination** — Units are fully independent. No focus fire, no healing priority.
- **Missing gambit conditions** — Can't express: "I'm low HP" (self-HP, not target-HP), "target is charging", "N enemies nearby", "ability will kill target".
- **Protect/Shell ignored in damage** — `STATUS_PROTECT` (line 204) and `STATUS_SHELL` (line 205) defined but damage formulas don't check them.

---

## Tier 1: Activate Existing Systems (Low effort, code already exists)

### 1.1 Enable Evasion

**File**: `combat_batch.glsl` line 1652

Delete `return true;` at line 1654 and uncomment the evasion logic below it (lines 1657-1662):

```glsl
// Current (disabled):
bool roll_evasion(int battle_id, int attacker, int defender, int tick) {
    return true;  // <-- delete this

    // Original evasion logic:       <-- uncomment these
    // int c_ev = read_unit(battle_id, defender, U_C_EV);
    // int s_ev = read_unit(battle_id, defender, U_S_EV);
    // int w_ev = read_unit(battle_id, defender, U_W_EV);
    // int total_evade = min(c_ev + s_ev + w_ev, 99);
    // int roll = rand_int(battle_id, attacker, tick, 100) + 1;
    // return roll > total_evade;
}
```

No data layout change. Evasion values (`U_C_EV`, `U_S_EV`, `U_W_EV`) already initialized in `_write_unit_data()`.

**Impact**: Misses become possible; evasion gear matters.

### 1.2 Wire Up Reactions

**Files**: `combat_batch.glsl` lines 2310-2370, 3002-3016

`check_pre_damage_reactions()` and `apply_damage_with_reactions()` are complete but uncalled. In `apply_damage()` Phase 2 (line 3002): call `apply_damage_with_reactions()` instead of directly adding to `U_PENDING_DAMAGE`.

**Complication**: Need attacker ID in the damage pipeline. Currently Phase 2 only has defender + amount. Options:
- Store attacker on the damage fields (add `U_DAMAGE_ATTACKER` or repurpose a reserved field)
- Call reactions during `STATE_ACTING` damage trigger instead of in `apply_damage()`

**Impact**: Counter-attacks, auto-potions, mana shields become active.

### 1.3 Protect/Shell Damage Reduction

**File**: `combat_batch.glsl`

In `calculate_damage()` (line 1670): check `has_status(defender, STATUS_PROTECT)`, halve physical damage:

```glsl
int calculate_damage(int battle_id, int attacker, int defender) {
    int pa = read_unit(battle_id, attacker, U_PA);
    int wp = read_unit(battle_id, attacker, U_WP);
    int damage = max(1, pa * wp);
    if (has_status(battle_id, defender, STATUS_PROTECT)) {
        damage = max(1, damage / 2);
    }
    return damage;
}
```

In `calculate_spell_damage()` (line 1843): after computing damage for magic formulas (0x08, 0x0C, 0x20, 0x4E), check `has_status(defender, STATUS_SHELL)` and halve.

No data layout change. `has_status()` already works.

**Impact**: Defensive buffs matter. Requires abilities that grant these statuses to be fully visible.

### 1.4 Haste/Slow Timer Scaling

When setting `U_TIMER` for idle retry (the many `TICKS_PATH_RETRY` writes scattered across lines 1921-2756): halve for `STATUS_HASTE`, double for `STATUS_SLOW`.

Add a helper:

```glsl
int get_adjusted_timer(int battle_id, int unit_id, int base_timer) {
    if (has_status(battle_id, unit_id, STATUS_HASTE))
        return max(1, base_timer / 2);
    if (has_status(battle_id, unit_id, STATUS_SLOW))
        return base_timer * 2;
    return base_timer;
}
```

Replace `write_unit(..., U_TIMER, TICKS_PATH_RETRY)` calls with `write_unit(..., U_TIMER, get_adjusted_timer(..., TICKS_PATH_RETRY))`.

**Impact**: Hasted units act faster, slowed units are sluggish.

### 1.5 Speed-Based Action Delay

Replace fixed `TICKS_PATH_RETRY` (47) for idle-to-gambit timing with a speed-derived value:

```glsl
int get_idle_delay(int battle_id, int unit_id) {
    int speed = read_unit(battle_id, unit_id, U_SPEED);
    return max(10, 60 - speed);  // Fast units: ~10 ticks, slow units: ~50 ticks
}
```

Apply this only to the "no gambit matched, retry later" case (line 2756), keeping `TICKS_PATH_RETRY` for actual pathfinding failures.

**Impact**: Speed stat affects gameplay beyond throw range.

---

## Tier 2: Extend Gambit Expressiveness (Medium effort, no architecture change)

### 2.1 New Condition Types

Add cases to `evaluate_condition()` (line 926) and mirror in `GambitEncoder.gd`:

| Condition | Description | Implementation |
|-----------|-------------|----------------|
| `COND_SELF_HP_BELOW` | Own HP% < value | `get_hp_percent(battle_id, unit_id) < value` |
| `COND_SELF_HP_ABOVE` | Own HP% > value | `get_hp_percent(battle_id, unit_id) > value` |
| `COND_TARGET_CHARGING` | Target is charging | `read_unit(battle_id, target_id, U_STATE) == STATE_CHARGING` |
| `COND_ENEMY_COUNT_WITHIN` | N+ enemies within X tiles | Count enemies within Manhattan distance X of self; compare against N (pack as `N * 256 + X`) |
| `COND_ALLY_COUNT_WITHIN` | N+ allies within X tiles | Same, but count allies |
| `COND_CAN_ATTACK_TARGET` | Already in attack range | `can_attack_target(battle_id, unit_id, target_id)` |

These enable gambits like:
- "If self HP < 25%, use potion on self" (currently impossible — `COND_HP_BELOW` checks target, not self)
- "If 3+ enemies within 3 tiles, cast AOE"
- "If can attack target, attack; else cast spell"

**Files to change**: `combat_batch.glsl` (`evaluate_condition`), `GambitEncoder.gd`, `GPUConstants.gd`

### 2.2 New Target Types

Add to `select_target()` (line 1117) and mirror in `GambitEncoder.gd`:

| Target Type | Description | Implementation |
|-------------|-------------|----------------|
| `TARGET_WEAKEST_ENEMY` | Lowest effective HP | `min(HP - U_PENDING_DAMAGE)` across enemies |
| `TARGET_NEAREST_ALLY_LOW_HP` | Nearest ally below 50% HP | Filter allies by HP%, rank by distance |
| `TARGET_MOST_DANGEROUS_ENEMY` | Highest threat score | Score by `(PA * WP + MA * 3) / max(1, distance)` |

**Files to change**: `combat_batch.glsl` (`select_target`, new finder functions), `GambitEncoder.gd`, `GPUConstants.gd`

### 2.3 Retreat/Kite Action

New `ACTION_RETREAT`: move away from nearest enemy.

```glsl
// In execute_gambit_action():
case ACTION_RETREAT: {
    int nearest = find_nearest_enemy(battle_id, unit_id);
    if (nearest < 0) return false;
    // Pick neighbor tile that maximizes distance from nearest enemy
    int ex = read_unit(battle_id, nearest, U_POS_X);
    int ez = read_unit(battle_id, nearest, U_POS_Z);
    // ... find best direction away from (ex, ez)
}
```

Enables kiting gambits: "if enemy distance < 3, retreat; else attack".

**Files to change**: `combat_batch.glsl` (new handler in `execute_gambit_action`), `GambitEncoder.gd`, `GPUConstants.gd`

---

## Tier 3: Fix Pathfinding (Medium effort, high impact)

### 3.1 Expand Attack Position Search for Ranged

**File**: `combat_batch.glsl` line 1493

`find_nearest_attack_position()` only checks 4 adjacent tiles. Ranged units (weapon_range >= 2) should search a box of `weapon_range` around the target, similar to how `find_cast_position()` (line 1293) already does:

```glsl
ivec2 find_nearest_attack_position(int battle_id, int unit_id, int target_x, int target_z) {
    int weapon_range = read_unit(battle_id, unit_id, U_WEAPON_RANGE);
    int attack_type = get_attack_type(battle_id, unit_id);

    // For melee (range 1), keep the current 4-adjacent check
    if (weapon_range <= 1 && attack_type == ATTACK_STRIKING) {
        // ... existing 4-direction logic ...
    }

    // For ranged: search box around target bounded by weapon_range
    int x_min = max(0, target_x - weapon_range);
    int x_max = min(config.map_width - 1, target_x + weapon_range);
    int z_min = max(0, target_z - weapon_range);
    int z_max = min(config.map_height - 1, target_z + weapon_range);

    for (int cx = x_min; cx <= x_max; cx++) {
        for (int cz = z_min; cz <= z_max; cz++) {
            // Check traversable, unoccupied, can_attack from (cx,cz)
            // Pick closest by get_distance() from unit
        }
    }
}
```

**Impact**: Ranged units find shooting positions at range instead of walking adjacent.

### 3.2 Use Pathfinding Distance for Target Ranking

**File**: `combat_batch.glsl`

Three functions use `manhattan_distance()` for target selection but should use `get_distance()` (BFS distance, already exists):

| Function | Line | Current | Fix |
|----------|------|---------|-----|
| `find_nearest_enemy()` | 1000 | `manhattan_distance()` | `get_distance()`, skip if -1 (unreachable) |
| `find_nearest_ally()` | 1026 | `manhattan_distance()` | `get_distance()`, skip if -1 |
| `find_nearest_attackable_enemy()` | 1631 | `manhattan_distance()` | `get_distance()`, skip if -1 |

Handle `-1` return (unreachable) by skipping that target entirely.

**Impact**: Units pick reachable targets on complex maps instead of chasing targets that look close but require long detours.

### 3.3 Anti-Oscillation

Repurpose `U_RESERVED_75` (line 137) as `U_LAST_BLOCKED_DIR`:

1. When conflict resolution blocks a unit, record the direction (0-3) that was blocked
2. In `get_next_step()`, deprioritize that direction on next evaluation (try other directions first)
3. Clear when a successful move completes

```glsl
// In resolve_conflicts(), when blocking a unit:
int dir = encode_direction(proposed_x - current_x, proposed_z - current_z);
write_unit(battle_id, unit_id, U_LAST_BLOCKED_DIR, dir);

// In get_next_step(), reorder direction check:
int last_blocked = read_unit(battle_id, unit_id, U_LAST_BLOCKED_DIR);
// Try non-blocked directions first, blocked direction last
```

**Impact**: Smoother movement, less stuttering at choke points.

---

## Tier 4: Deeper AI (Larger effort, new capabilities)

### 4.1 Focus-Fire Target Type

New `TARGET_FOCUS_FIRE_ENEMY`: select enemy targeted by most allies.

```glsl
int find_focus_fire_target(int battle_id, int unit_id) {
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    // Count how many allies have U_TARGET == each enemy
    // Pick enemy with highest count, break ties by distance
}
```

Emergent coordination without explicit planning — units converge on the same target naturally.

**Files to change**: `combat_batch.glsl`, `GambitEncoder.gd`, `GPUConstants.gd`

### 4.2 Status Effect Ticks (Poison/Regen)

Add `tick_status_effects()` at start of `compute_unit_state()` (line 2644):

```glsl
void tick_status_effects(int battle_id, int unit_id) {
    // Decrement all active status timers
    for (int i = 0; i < 8; i++) {
        int timer = read_unit(battle_id, unit_id, U_STATUS_TIMER_0 + i);
        if (timer > 0) {
            timer--;
            write_unit(battle_id, unit_id, U_STATUS_TIMER_0 + i, timer);
            if (timer == 0) {
                // Clear the associated status bit
            }
        }
    }

    // Poison: damage over time
    if (has_status(battle_id, unit_id, STATUS_POISON)) {
        int max_hp = get_max_hp(battle_id, unit_id);
        int poison_dmg = max(1, max_hp / 8 / 60);  // 12.5% per second at 60 ticks/sec
        // Apply via pending damage
    }

    // Regen: heal over time
    if (has_status(battle_id, unit_id, STATUS_REGEN)) {
        int max_hp = get_max_hp(battle_id, unit_id);
        int regen_heal = max(1, max_hp / 8 / 60);
        // Apply healing
    }
}
```

**Prerequisite**: Abilities that inflict statuses (currently none do beyond hardcoded `STATUS_CHARGING`).

### 4.3 Elemental Damage

Read `AB_ELEMENT` in `calculate_spell_damage()` (line 1843). Repurpose `U_RESERVED_76`/`U_RESERVED_77` as element weakness/resistance bitmasks:

```glsl
int apply_element_modifier(int battle_id, int target_id, int ability_id, int damage) {
    int element = get_ability_field(ability_id, AB_ELEMENT);
    if (element == 0) return damage;  // Non-elemental

    int weakness = read_unit(battle_id, target_id, U_ELEMENT_WEAK);   // U_RESERVED_76
    int resist = read_unit(battle_id, target_id, U_ELEMENT_RESIST);   // U_RESERVED_77

    if ((weakness >> element) & 1) return damage * 2;    // 2x
    if ((resist >> element) & 1) return damage / 2;      // 0.5x
    return damage;
}
```

**Prerequisite**: CPU-side changes to initialize element fields in `_write_unit_data()`.

---

## Recommended Sequence

### Phase A — Quick wins, no data layout changes

| # | Task | Section | Risk |
|---|------|---------|------|
| 1 | Enable evasion | 1.1 | Low — uncomment existing code |
| 2 | Protect/Shell reduction | 1.3 | Low — add 2 conditionals |
| 3 | Use pathfinding distance for target ranking | 3.2 | Low — swap function call, handle -1 |
| 4 | Speed-based action delay | 1.5 | Low — one formula change |
| 5 | Haste/Slow scaling | 1.4 | Low — add helper, replace timer writes |

### Phase B — Core improvements

| # | Task | Section | Risk |
|---|------|---------|------|
| 6 | Expand ranged attack position search | 3.1 | Medium — refactor search loop, test with ranged units |
| 7 | New gambit conditions | 2.1 | Medium — extend switch + mirror in GDScript |
| 8 | New target types | 2.2 | Medium — new finder functions |

### Phase C — Systems needing more care

| # | Task | Section | Risk |
|---|------|---------|------|
| 9 | Wire up reactions | 1.2 | Medium — needs attacker ID in damage pipeline |
| 10 | Anti-oscillation tracking | 3.3 | Medium — uses reserved field, needs careful testing |
| 11 | Retreat/kite action | 2.3 | Medium — new action type, mirror in encoder |

### Phase D — Deeper features

| # | Task | Section | Risk |
|---|------|---------|------|
| 12 | Focus-fire coordination | 4.1 | Medium — O(N^2) unit scan per target query |
| 13 | Status effect ticks | 4.2 | High — needs status-inflicting abilities first |
| 14 | Elemental damage | 4.3 | High — needs CPU-side element data initialization |

---

## Key Files

| File | Role |
|------|------|
| `src/gpu/combat_batch.glsl` | All gameplay logic (3172 lines) |
| `src/gpu/GPUBatchSimulator.gd` | Buffer management, CPU-GPU bridge |
| `src/gpu/GambitEncoder.gd` | Gambit authoring, must mirror new conditions/targets/actions |
| `src/gpu/GPUConstants.gd` | Shared constants, must stay synced with shader |
| `src/gpu/GPUStateReader.gd` | State change detection |
