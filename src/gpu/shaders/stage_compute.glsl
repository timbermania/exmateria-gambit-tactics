#[compute]
#version 450

// =============================================================================
// stage_compute.glsl — PASS_COMPUTE: per-unit decision + action setup
//
// One thread per unit. Walks the gambit list, runs the unit's state-machine
// step (compute_unit_state), and stamps the next-state writes into the NEXT
// buffer (proposed move, attack target, animation timing, spell setup, etc.).
// The downstream stages (resolve → post_conflict → damage → victory) then
// finalize positions, apply damage, and check for end-of-battle.
//
// This is the long pole — currently the single biggest pipeline_create cost
// in the system. Stage 2b is the planned decomposition into
// decide / pathfind / attack / spell sub-stages — see
// docs/stage_2b_implementation_plan.md.
//
// Dispatch: ceil(num_battles * units_per_battle / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"
#include "res://src/gpu/shaders/combat_combat.glslinc"

// All extracted blocks below are gated `#ifdef PASS_COMPUTE` (or
// `#if defined(PASS_COMPUTE) || ...`). Defining PASS_COMPUTE here keeps every
// extracted block live; the multi-stage blocks moved to combat_combat.glslinc
// and are NOT in the extracted ranges, so there are no duplicate definitions.
#define PASS_COMPUTE 1

#ifdef PASS_COMPUTE

int gambit_field_offset(int unit_id, int gambit_slot, int field) {
    return unit_id * GAMBITS_PER_UNIT + gambit_slot * GAMBIT_SIZE + field;
}

int get_gambit_field(int unit_id, int gambit_slot, int field) {
    return gambit_data.gambits[gambit_field_offset(unit_id, gambit_slot, field)];
}

// --- The per-slot verdict (ADR-0275 dec. 4) ---------------------------------
// `unit_id` here is the GLOBAL unit id, so the address is `(battle, unit, slot)`
// by construction and the rollout fleet is covered without a second layout.
// Layout and rationale: "THE PER-SLOT GAMBIT VERDICT" in combat_common.glslinc.

// Pass 1 writes the full stamp, and is the only writer of the payload.
void write_verdict_pass1(int unit_id, int gambit_slot, int verdict,
                         int cond_index, int cond_opcode, int eval_mask, int payload) {
    gambit_data.gambits[gambit_field_offset(unit_id, gambit_slot, GM_RESERVED_14)] =
          ((verdict & 0xF) << VERDICT_A_P1_SHIFT)
        | ((cond_index & 0x3) << VERDICT_A_P1_CI_SHIFT)
        | ((cond_opcode & 0x3F) << VERDICT_A_P1_OP_SHIFT)
        | ((eval_mask & 0xF) << VERDICT_A_P1_MASK_SHIFT);
    gambit_data.gambits[gambit_field_offset(unit_id, gambit_slot, GM_RESERVED_15)] = payload;
}

// Clearing only needs int A: `VERDICT_NONE` in the pass-1 nibble makes the payload
// meaningless, so writing int B too would be a second store bought for nothing.
void clear_verdict(int unit_id, int gambit_slot) {
    gambit_data.gambits[gambit_field_offset(unit_id, gambit_slot, GM_RESERVED_14)] = 0;
}

// Pass 2 MERGES rather than overwrites. Clobbering pass 1's reason is precisely
// the defect this instrument exists to remove, and pass 2 revisits every slot.
void write_verdict_pass2(int unit_id, int gambit_slot, int verdict,
                         int cond_index, int cond_opcode, int rank) {
    int off = gambit_field_offset(unit_id, gambit_slot, GM_RESERVED_14);
    gambit_data.gambits[off] = (gambit_data.gambits[off] & ~VERDICT_A_P2_FIELDS)
        | ((verdict & 0xF) << VERDICT_A_P2_SHIFT)
        | ((cond_index & 0x3) << VERDICT_A_P2_CI_SHIFT)
        | ((cond_opcode & 0x3F) << VERDICT_A_P2_OP_SHIFT)
        | (min(rank, 7) << VERDICT_A_P2_RANK_SHIFT);
}

bool gambit_enabled(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_ENABLED) != 0;
}

int get_gambit_cond_target_type(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_COND_TARGET_TYPE);
}

int get_gambit_cond_count(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_COND_COUNT);
}

int get_gambit_cond_type(int unit_id, int gambit_slot, int cond_idx) {
    return get_gambit_field(unit_id, gambit_slot, GM_COND_TYPE_0 + cond_idx);
}

int get_gambit_cond_value(int unit_id, int gambit_slot, int cond_idx) {
    return get_gambit_field(unit_id, gambit_slot, GM_COND_VAL_0 + cond_idx);
}

int get_gambit_action_type(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_ACTION_TYPE);
}

int get_gambit_action_id(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_ACTION_ID);
}

int get_gambit_action_target_type(int unit_id, int gambit_slot) {
    return get_gambit_field(unit_id, gambit_slot, GM_ACTION_TARGET_TYPE);
}

#endif // PASS_COMPUTE — gambit accessors
#ifdef PASS_COMPUTE

// `action_type` / `action_id` are the SLOT'S OWN action, because one condition asks about it:
// `COND_IN_RANGE` means "would what this row does land on the candidate from here" (ADR-0268
// Amendment 2). Passed in rather than read from the gambit buffer here, so this stays a
// predicate over values and the buffer walk stays in `check_gambit_conditions`.
//
// `measured` is ADR-0275 dec. 4's PAYLOAD -- the number that lost. It is the half of
// the verdict that ends an investigation (`actual 62, threshold 50`), and it is why the
// verdict vocabulary can stay coarse instead of growing a per-opcode failure enum that
// would have to track the condition table forever.
//
// Where the losing number is already in a register it is assigned unconditionally (free);
// where reporting it costs extra loads it is fetched ON THE FAILING BRANCH ONLY, so the
// passing path -- the common one -- pays nothing.
bool evaluate_condition(int battle_id, int unit_id, int target_id,
                        int condition_type, int condition_value,
                        int action_type, int action_id, out int measured) {
    measured = 0;
    switch (condition_type) {
        case COND_ALWAYS:
            return true;

        case COND_HP_BELOW:
            measured = get_hp_percent(battle_id, target_id);
            return measured < condition_value;

        case COND_HP_ABOVE:
            measured = get_hp_percent(battle_id, target_id);
            return measured > condition_value;

        case COND_DISTANCE_LESS: {
            int ux = read_unit(battle_id, unit_id, U_POS_X);
            int uz = read_unit(battle_id, unit_id, U_POS_Z);
            int tx = read_unit(battle_id, target_id, U_POS_X);
            int tz = read_unit(battle_id, target_id, U_POS_Z);
            measured = manhattan_distance(ux, uz, tx, tz);
            return measured < condition_value;
        }

        case COND_DISTANCE_GREATER: {
            int ux = read_unit(battle_id, unit_id, U_POS_X);
            int uz = read_unit(battle_id, unit_id, U_POS_Z);
            int tx = read_unit(battle_id, target_id, U_POS_X);
            int tz = read_unit(battle_id, target_id, U_POS_Z);
            measured = manhattan_distance(ux, uz, tx, tz);
            return measured > condition_value;
        }

        case COND_IN_RANGE: {
            // `condition_value` is deliberately unread — the reach is the ACTION'S, and a
            // value word carrying a range would be a second answer to a question the action
            // already answers (and a stale one, since throw range is `speed / 2 + 1` and
            // moves with a Speed Break).
            bool in_range = target_in_action_range(battle_id, unit_id, target_id,
                                                   action_type, action_id);
            if (!in_range) {
                // The reach itself is the action's and varies by weapon/ability/Speed; the
                // SEPARATION is the number the reader needs to see against it.
                measured = manhattan_distance(read_unit(battle_id, unit_id, U_POS_X),
                                              read_unit(battle_id, unit_id, U_POS_Z),
                                              read_unit(battle_id, target_id, U_POS_X),
                                              read_unit(battle_id, target_id, U_POS_Z));
            }
            return in_range;
        }

        case COND_HAS_STATUS: {
            bool held = has_status(battle_id, target_id, condition_value);
            // The whole low word, not the one bit asked about: "it has Sleep, not Petrify"
            // is the answer, and the asked-for bit is already in the opcode's value field.
            if (!held) measured = read_unit(battle_id, target_id, U_STATUS_FLAGS_LO);
            return held;
        }

        case COND_NOT_STATUS: {
            bool held = has_status(battle_id, target_id, condition_value);
            if (held) measured = read_unit(battle_id, target_id, U_STATUS_FLAGS_LO);
            return !held;
        }

        case COND_IS_DEAD: {
            bool dead = is_unit_dead(battle_id, target_id);
            if (!dead) measured = read_unit(battle_id, target_id, U_HP);
            return dead;
        }

        case COND_IS_ALIVE: {
            bool dead = is_unit_dead(battle_id, target_id);
            if (dead) measured = read_unit(battle_id, target_id, U_HP);
            return !dead;
        }

        case COND_MP_ABOVE:
            measured = get_mp_percent(battle_id, unit_id);
            return measured > condition_value;

        case COND_MP_BELOW:
            measured = get_mp_percent(battle_id, unit_id);
            return measured < condition_value;

        case COND_TEAM_ALLY:
            measured = get_team(battle_id, target_id);
            return get_team(battle_id, unit_id) == measured;

        case COND_TEAM_ENEMY:
            measured = get_team(battle_id, target_id);
            return get_team(battle_id, unit_id) != measured;
    }
    return false;
}

// =============================================================================
// TARGET SELECTION
// =============================================================================

// Unified target finder. Replaces 6 separate functions to reduce GLSL inlining bloat.
// want_ally: true = same team, false = different team
// mode: 0 = nearest (by distance), 1 = lowest HP%, 2 = highest HP%
//
// TRANSPARENT filter (status_system.md §2 "Target filter" row): cross-team
// searches skip candidates holding STATUS_TRANSPARENT. Ally-side searches
// (want_ally=true) are unaffected — a Priest still cures their invisible
// Knight. has_status_next reads the NEXT buffer so we observe same-tick
// applies from upstream stages without clobbering writes downstream.
//
// KO filter (#1102): `include_ko` false — every pool but TARGET_NEAREST_ALLY_OR_KO — drops
// `is_unit_dead` candidates before anything else looks at them. That filter is why
// `COND_IS_DEAD` existed for so long without ever being able to return true: the corpse never
// reached `evaluate_condition`. Passing true admits it, and the SLOT'S CONDITIONS then decide.
int find_unit_by_criteria(int battle_id, int unit_id, bool want_ally, int mode, bool include_ko) {
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);

    int best = -1;
    int best_val = (mode == 2) ? -1 : ((mode == 1) ? HP_PERCENT_SENTINEL : MAX_DISTANCE);

    for (int u = 0; u < config.units_per_battle; u++) {
        if (mode == 0 && u == unit_id) continue;  // Nearest excludes self
        if (!include_ko && is_unit_dead(battle_id, u)) continue;
        // #1113 — the cost of `include_ko` is paid here and only here. A KO-blind pool
        // already drops the battle's unfilled slots as part of dropping the dead; a
        // KO-inclusive one has to say out loud that an empty slot is not a corpse.
        if (include_ko && !is_unit_slot_filled(battle_id, u)) continue;
        bool same_team = (read_unit(battle_id, u, U_TEAM) == my_team);
        if (want_ally != same_team) continue;
        if (!want_ally && has_status_next(battle_id, u, STATUS_TRANSPARENT)) continue;

        int val;
        if (mode == 0) {
            val = get_distance(my_x, my_z, my_level,
                               read_unit(battle_id, u, U_POS_X),
                               read_unit(battle_id, u, U_POS_Z),
                               read_unit(battle_id, u, U_LEVEL));
            if (val < 0) continue;  // Unreachable
        } else {
            val = get_hp_percent(battle_id, u);
        }

        bool is_better = (mode == 2) ? (val > best_val) : (val < best_val);
        if (is_better) {
            best_val = val;
            best = u;
        }
    }

    return best;
}

// Convenience wrappers (thin, no extra inlining cost)
int find_nearest_enemy(int battle_id, int unit_id) {
    return find_unit_by_criteria(battle_id, unit_id, false, 0, false);
}

int select_target(int battle_id, int unit_id, int target_type) {
    switch (target_type) {
        case TARGET_SELF:           return unit_id;
        case TARGET_NEAREST_ENEMY:  return find_unit_by_criteria(battle_id, unit_id, false, 0, false);
        case TARGET_NEAREST_ALLY:   return find_unit_by_criteria(battle_id, unit_id, true,  0, false);
        case TARGET_LOWEST_HP_ALLY: return find_unit_by_criteria(battle_id, unit_id, true,  1, false);
        case TARGET_HIGHEST_HP_ENEMY: return find_unit_by_criteria(battle_id, unit_id, false, 2, false);
        case TARGET_LOWEST_HP_ENEMY:  return find_unit_by_criteria(battle_id, unit_id, false, 1, false);
        case TARGET_HIGHEST_HP_ALLY:  return find_unit_by_criteria(battle_id, unit_id, true,  2, false);
        // The one KO-inclusive pool (#1102). Nearest by the same path metric as
        // TARGET_NEAREST_ALLY; a corpse keeps its tile, so it ranks normally.
        case TARGET_NEAREST_ALLY_OR_KO: return find_unit_by_criteria(battle_id, unit_id, true, 0, true);
        // Strict depth (ADR-0285): the SAME search as the two above, and the difference
        // is entirely in Pass 2, which does not list these in its retryable set.
        case TARGET_NEAREST_ALLY_ONLY:  return find_unit_by_criteria(battle_id, unit_id, true,  0, false);
        case TARGET_NEAREST_ENEMY_ONLY: return find_unit_by_criteria(battle_id, unit_id, false, 0, false);
        case TARGET_THEM:           return -1;  // Set by caller
    }
    return -1;
}

#endif // PASS_COMPUTE -gambit evaluators
#ifdef PASS_COMPUTE
// Trace a stitched path using BFS-guided DFS with backtracking.
// Returns path length to destination, or -1 if unreachable.
// Uses visited bitmask to prevent cycles. No buffer writes.

// Find Nth nearest unit by BFS distance (0-indexed: rank 0 = nearest).
// want_same_team=true finds allies, want_same_team=false finds enemies.
int find_nth_nearest(int battle_id, int unit_id, int rank, bool want_same_team, bool include_ko) {
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);

    int unit_ids[8];
    int unit_dists[8];
    int count = 0;

    for (int u = 0; u < config.units_per_battle; u++) {
        // The two scratch arrays are 8 long and `units_per_battle` is not bounded by 8. The
        // guard is new with #1102 because `include_ko` ADMITS candidates this walk used to
        // drop, so the KO-inclusive pool is the first caller that can push `count` past the
        // array on a roster the KO-blind one fit.
        if (count >= 8) break;
        if (u == unit_id) continue;
        if (!include_ko && is_unit_dead(battle_id, u)) continue;
        // #1113 — same clause as find_unit_by_criteria's, and it matters MORE here: the
        // phantoms all stand at (0, 0), so they do not merely join the rank walk, they
        // cluster at one distance and can fill the 8-entry scratch array ahead of the
        // real corpse the slot was authored for.
        if (include_ko && !is_unit_slot_filled(battle_id, u)) continue;
        bool same_team = (read_unit(battle_id, u, U_TEAM) == my_team);
        if (same_team != want_same_team) continue;
        // TRANSPARENT filter: enemy-side rank-N searches skip the carrier.
        // Ally-side passes through (matches find_unit_by_criteria semantics).
        if (!want_same_team && has_status_next(battle_id, u, STATUS_TRANSPARENT)) continue;

        int ux = read_unit(battle_id, u, U_POS_X);
        int uz = read_unit(battle_id, u, U_POS_Z);
        int ul = read_unit(battle_id, u, U_LEVEL);
        int dist = get_distance(my_x, my_z, my_level, ux, uz, ul);
        if (dist < 0) continue;

        unit_ids[count] = u;
        unit_dists[count] = dist;
        count++;
    }

    if (rank >= count) return -1;

    for (int r = 0; r <= rank; r++) {
        int min_idx = -1;
        int min_dist = MAX_DISTANCE;
        for (int i = 0; i < count; i++) {
            if (unit_dists[i] < min_dist) {
                min_dist = unit_dists[i];
                min_idx = i;
            }
        }
        if (min_idx < 0) return -1;
        if (r == rank) return unit_ids[min_idx];
        unit_dists[min_idx] = MAX_DISTANCE;
    }
    return -1;
}

// Find a tile within ability range of (tx,tz) where the caster can stand and
// satisfy the vertical tolerance.  Returns the tile closest to the caster.
// Ranks candidates by BFS distance, then validates top N with stitched DFS.
// Result: ivec2(-1,-1) if no valid tile exists.

// Find first empty tile in a direction (for pass-through)

// Scan 4 adjacent tiles for best move toward (to_x, to_z).
// Returns best move via out params. Handles greedy/fallback, anti-backtrack,
// occupancy, passthrough. Extracted from get_next_step to reduce inlining.


#endif // PASS_COMPUTE -pathfinding
#ifdef PASS_COMPUTE // attack position finding
// Find the nearest tile from which we can attack a target
// Returns the best attack position, or (-1,-1) if none found

// Lightweight check: returns true if ANY valid attack position exists around
// (target_x, target_z) for this unit.  Short-circuits on first hit.

// Like find_nearest_enemy() but skips enemies that have no valid attack
// position (unreachable due to terrain, height, or fully blocked tiles).
// An enemy we can already attack from our current position is always valid.
#endif // PASS_COMPUTE -attack position finding

#ifdef PASS_COMPUTE // evasion + melee damage only used in state machine
bool roll_evasion(int battle_id, int attacker, int defender, int tick, bool is_magic) {
    int c_ev = read_unit(battle_id, defender, U_C_EV);
    int s_ev = is_magic
        ? read_unit(battle_id, defender, U_S_EV_MAG)
        : read_unit(battle_id, defender, U_S_EV);
    int w_ev = is_magic ? 0 : read_unit(battle_id, defender, U_W_EV);
    int total_evade = min(c_ev + s_ev + w_ev, 99);
    int roll = rand_int(battle_id, attacker, tick, 100) + 1;

    if (roll > total_evade) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 0);  // hit
        return true;
    }

    // Miss -determine which evasion type triggered (checked in order: C-EV, S-EV, W-EV)
    if (roll <= c_ev) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 1);  // class evade
    } else if (roll <= c_ev + s_ev) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 2);  // shield block
    } else {
        write_unit(battle_id, defender, U_EVADE_TYPE, 3);  // weapon parry
    }
    return false;
}

int calculate_damage(int battle_id, int attacker, int defender) {
    int pa = read_unit(battle_id, attacker, U_PA);
    int wp = read_unit(battle_id, attacker, U_WP);
    int damage = max(1, pa * wp);
    if (has_status(battle_id, defender, STATUS_PROTECT))
        damage = max(1, damage / 2);
    return damage;
}
#endif // PASS_COMPUTE — evasion + melee damage
#ifdef PASS_COMPUTE

// =============================================================================
// DECISION HISTORY RING BUFFER (thrash detection)
// =============================================================================
// Each entry = 16 bits: [reason:4][state:3][target:4][pos_hash:5]
// 6 entries stored in 3 ints (2 per int, lo/hi 16 bits)

// Record a decision entry to the ring buffer. Lightweight -called from 18+ sites.
// Thrash detection runs separately via check_decision_thrash() once per tick.
void record_decision(int battle_id, int unit_id, int reason, int dec_state, int target) {
    int pos_x = read_unit(battle_id, unit_id, U_POS_X);
    int pos_z = read_unit(battle_id, unit_id, U_POS_Z);
    int pos_hash = (pos_x * 7 + pos_z) & 0x1F;
    int entry = ((reason & 0xF) << 12) | ((dec_state & 0x7) << 9) | ((max(target, 0) & 0xF) << 5) | (pos_hash & 0x1F);

    int meta = read_unit(battle_id, unit_id, U_DECISION_META);
    int write_idx = meta & 0x7;
    int slot_idx = write_idx / 2;
    int lo_hi = write_idx % 2;

    int field = U_DECISION_HIST_0 + slot_idx;
    int cur = read_unit(battle_id, unit_id, field);

    if (lo_hi == 0) {
        cur = ((cur >> 16) << 16) | (entry & 0xFFFF);
    } else {
        cur = (cur & 0xFFFF) | (entry << 16);
    }
    write_unit(battle_id, unit_id, field, cur);

    // Advance write index, preserve thrash bits
    write_idx = (write_idx + 1) % 6;
    meta = (write_idx & 0x7) | (meta & 0xF8);  // keep thrash_flag + thrash_count
    write_unit(battle_id, unit_id, U_DECISION_META, meta);
}

// Thrash detection: runs once per tick after state machine dispatch.
// Checks for position oscillation (A→B→A→B) or stuck-in-place patterns.
// Uses read_unit_next since record_decision writes to the next buffer.
void check_decision_thrash(int battle_id, int unit_id) {
    int meta = read_unit_next(battle_id, unit_id, U_DECISION_META);
    int write_idx = meta & 0x7;

    // Read all 6 entries from ring buffer (next buffer -written by record_decision)
    int entries[6];
    for (int i = 0; i < 6; i++) {
        int idx = (write_idx + i) % 6;  // oldest to newest
        int s = idx / 2;
        int h = idx % 2;
        int v = read_unit_next(battle_id, unit_id, U_DECISION_HIST_0 + s);
        entries[i] = (h == 0) ? (v & 0xFFFF) : ((v >> 16) & 0xFFFF);
    }

    // Check last 4 entries for oscillation or stuck-in-place patterns.
    // Entry bits: [reason:4][state:3][target:4][pos_hash:5]
    int thrash_flag = 0;
    int newest = entries[5];
    if (newest != 0) {
        int newest_upper = (newest >> 5) & 0x7FF;
        int pos_a = newest & 0x1F;
        int pos_b = entries[4] & 0x1F;
        // Oscillation: A→B→A→B with same reason+state+target
        if (pos_a != pos_b && ((entries[4] >> 5) & 0x7FF) == newest_upper) {
            int e3_upper = (entries[3] >> 5) & 0x7FF;
            int e2_upper = (entries[2] >> 5) & 0x7FF;
            int pos3 = entries[3] & 0x1F;
            int pos2 = entries[2] & 0x1F;
            if (e3_upper == newest_upper && e2_upper == newest_upper
                && pos3 == pos_a && pos2 == pos_b) {
                thrash_flag = 1;
            }
        }
        // Stuck-in-place: same reason+state+target+pos for 4+ entries
        if (thrash_flag == 0) {
            int stuck_count = 0;
            for (int i = 4; i >= 0; i--) {
                if (entries[i] != 0 && ((entries[i] >> 5) & 0x7FF) == newest_upper
                    && (entries[i] & 0x1F) == pos_a) {
                    stuck_count++;
                } else {
                    break;
                }
            }
            if (stuck_count >= 3) thrash_flag = 1;
        }
    }
    int prev_thrash = (meta >> 3) & 0x1;
    int thrash_count = (meta >> 4) & 0xF;
    if (thrash_flag == 1 && prev_thrash == 0) {
        thrash_count = min(thrash_count + 1, 15);
    }
    meta = (write_idx & 0x7) | ((thrash_flag & 0x1) << 3) | ((thrash_count & 0xF) << 4);
    write_unit(battle_id, unit_id, U_DECISION_META, meta);
}

// =============================================================================
// GAMBIT EVALUATION
// =============================================================================

// Action bodies have moved out (Phases 3–5):
//   execute_attack_gambit            → stage_attack.glsl
//   start_spell + cast_*             → stage_spell.glsl
//   handle_moving_state /
//   handle_moving_to_cast_state /
//   execute_move_to_gambit +
//   trace_stitched_path / etc.       → stage_pathfind.glsl
// This file is the "decide" stage: gambit eval, target selection,
// decision recording, state-machine timer/IDLE/ACTING/REACTING/CHARGING
// edges that don't pathfind themselves.

// Stage 2b Phase 2.b — cheap pre-check for spell-like actions. Returns
// true if the action could plausibly succeed; gambit eval uses this to
// preserve sync fallthrough on MP shortage. Expensive failures (LOS
// blocked / no cast position) take a 1-tick delay instead — see
// docs/stage_2b_phase_2b_plan.md §2.
bool spell_pre_validate(int battle_id, int unit_id, int target_id,
                        int ability_id, int action_type) {
    if (target_id < 0 && action_type != ACTION_WAIT) return false;
    int mp_cost = get_ability_mp_cost(ability_id);
    if (get_mp(battle_id, unit_id) < mp_cost) return false;
    return true;
}

// ADR-0047 — real-time per-(unit, ability) cooldown floor. Parallels
// spell_pre_validate (B3): false short-circuits the gambit slot, sending
// evaluation to the next one (B8 fall-through). cooldown_ticks <= 0 disables
// the floor; ability_id out of range falls through as a no-op so attack /
// move slots aren't gated. cooldown_ready_at is per-ability_id, so the same
// ability in two gambit slots shares one timer (the desired semantics).
bool cooldown_pre_validate(int battle_id, int unit_id, int ability_id) {
    // Out-of-range ability_id falls through as a no-op. Since #1108 the range
    // is the WHOLE ability table, so this is now only the attack / move guard
    // the doc comment above describes — no real ability escapes the floor by
    // id any more. (It used to end at 128, which let 240 ordinary `Normal`
    // abilities through.)
    if (ability_id < 0 || ability_id >= MAX_COOLDOWN_ABILITIES) return true;
    int cooldown_ticks = get_ability_cooldown_ticks(ability_id);
    if (cooldown_ticks <= 0) return true;
    // Single-buffered cooldown SSBO (issue #85): any earlier commit this
    // same tick (e.g. our own write below for a previous slot iteration)
    // is visible immediately. Without that visibility, two slots both
    // targeting the same ability id in the same tick could both commit.
    int ready_at = get_cooldown_ready_at(battle_id, unit_id, ability_id);
    return get_battle_tick(battle_id) >= ready_at;
}

// -----------------------------------------------------------------------------
// THE RETREAT STEP PICKER (ADR-0301)
// -----------------------------------------------------------------------------

// Is this cell one the unit could stand on NEXT TICK, ignoring where it wants to
// go? Terrain, jump and occupancy -- the same three tests `scan_adjacent_moves`
// applies, minus everything about a destination.
//
// The ally PASS-THROUGH is deliberately absent. `find_passthrough_destination`
// walks a LINE past a friendly body, which is a multi-tile move; a retreat is
// one tile by definition, so an ally standing in the way is simply a direction
// the retreat cannot take and the fallback below has to find another.
bool retreat_cell_steppable(int battle_id, int unit_id,
                            int from_x, int from_z, int from_level,
                            int nx, int nz, int nl, int jump) {
    if (!is_tile_traversable(nx, nz, nl)) return false;
    if (abs(get_tile_height(nx, nz, nl) - get_tile_height(from_x, from_z, from_level)) > jump) {
        return false;
    }
    return get_tile_occupant(battle_id, nx, nz, nl, unit_id) < 0;
}

// ONE TILE AWAY FROM `flee_from`. Returns the cell to step to, or `.x < 0` for
// "there isn't one" -- which the caller turns into VERDICT_NO_RETREAT and a
// fall-through to the next gambit slot, NOT into a unit standing still with a
// committed retreat. A cornered unit has to be able to reach its `Attack` slot.
//
// 🔴 THE PREFERRED DIRECTION IS TRIED FIRST AND IT IS NOT THE FARTHEST ONE.
// #1103's answer is "pick the direction opposite the vector to them", so the
// dominant component of (me - them) wins whenever it is usable, even when a
// perpendicular step would open MORE distance. Retreat has to READ as fleeing;
// maximising the field is what a `FURTHEST` target selector would do and that is
// a different, still-unbuilt thing (#1103 Q3).
//
// Every candidate must STRICTLY increase path distance from `flee_from`. That is
// the rule, and it is also why a retreat needs no `U_PREV_MOVE_POS` oscillation
// memory the way a committed path does: a strictly monotone sequence cannot step
// back onto a cell it left while the threat stays put.
//
// `get_distance` is the precomputed all-pairs path field, so "away" is measured
// in TRAVEL, not in line of sight -- stepping to the far side of a wall counts
// only if walking around the wall is genuinely longer.
ivec3 retreat_step_cell(int battle_id, int unit_id, int flee_from) {
    // A RETREAT AIMED AT YOURSELF IS NOT A NO-OP, IT IS A RANDOM WALK, so it is
    // refused here rather than left to the surface. `here` would be the distance
    // from the unit's cell to itself -- zero -- and every neighbour beats zero, so
    // the strictness test below would wave through an arbitrary direction, every
    // evaluation, forever. `GambitOptions.aim_verdict` marks the aim FORBIDDEN for
    // the same reason, but the surface is not the only way a gambit reaches the
    // buffer (the rollout fleet and the raw command path both bypass it).
    if (flee_from == unit_id) return ivec3(-1, 0, 0);

    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);
    int fx = read_unit(battle_id, flee_from, U_POS_X);
    int fz = read_unit(battle_id, flee_from, U_POS_Z);
    int f_level = read_unit(battle_id, flee_from, U_LEVEL);

    // ALREADY DISENGAGED. `here < 0` is the field saying no walk connects the two
    // cells at all, and then "further away" has no meaning to compare against --
    // every candidate would trivially beat -1 and the unit would flee forever from
    // something that cannot follow. Report no retreat and let the list fall through.
    int here = get_distance(my_x, my_z, my_level, fx, fz, f_level);
    if (here < 0) return ivec3(-1, 0, 0);

    int jump = read_unit(battle_id, unit_id, U_JUMP);

    ivec2 dirs[4] = ivec2[4](
        ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0), ivec2(0, -1)
    );

    // The dominant component of the vector FROM the threat TO us. Ties on |dx|
    // == |dz| go to x, which is arbitrary but fixed -- the kernel is
    // deterministic and a coin flip here would be a second source of divergence
    // between two identical rollouts. Both components zero means the two units
    // share a column at different levels; there is no opposite direction then,
    // so the preferred pass is skipped and the fallback decides.
    int dx = my_x - fx;
    int dz = my_z - fz;
    ivec2 pref = ivec2(0, 0);
    if (dx != 0 && abs(dx) >= abs(dz)) pref = ivec2(sign(dx), 0);
    else if (dz != 0) pref = ivec2(0, sign(dz));

    if (pref.x != 0 || pref.y != 0) {
        int px = my_x + pref.x;
        int pz = my_z + pref.y;
        for (int l = 0; l < MAP_LEVEL_COUNT; l++) {
            if (!retreat_cell_steppable(battle_id, unit_id, my_x, my_z, my_level, px, pz, l, jump)) {
                continue;
            }
            int d = get_distance(px, pz, l, fx, fz, f_level);
            if (d > here) return ivec3(px, pz, l);
        }
    }

    // FALLBACK -- the preferred direction is off-map, blocked, too tall, or does
    // not actually open distance (walking "away" around the outside of a pillar
    // can leave the path length unchanged). Take the neighbour that opens the
    // MOST distance; scan order breaks ties, lower level first, so the pick is
    // reproducible.
    ivec3 best = ivec3(-1, 0, 0);
    int best_dist = here;
    for (int d = 0; d < 4; d++) {
        int nx = my_x + dirs[d].x;
        int nz = my_z + dirs[d].y;
        for (int l = 0; l < MAP_LEVEL_COUNT; l++) {
            if (!retreat_cell_steppable(battle_id, unit_id, my_x, my_z, my_level, nx, nz, l, jump)) {
                continue;
            }
            int cand = get_distance(nx, nz, l, fx, fz, f_level);
            // `cand < 0` is a cell the threat cannot path to AT ALL. It is
            // excluded rather than treated as infinitely far: it is as likely to
            // be an isolated ledge the unit can never leave as it is to be cover,
            // and the kernel cannot tell the two apart from the field alone.
            if (cand > best_dist) {
                best_dist = cand;
                best = ivec3(nx, nz, l);
            }
        }
    }
    return best;
}

// Stage 2b Phase 2.b — write scratch fields that apply_pending_action()
// will consume. Carriers mirror what the original inline action bodies
// would have read from local parameters.
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
            // action_id encodes packed dest coords (dest_x*256 + dest_z).
            // Decoded back inside apply_pending_action's MOVE_TO case.
            write_unit(battle_id, unit_id, U_DEST_X, action_id / 256);
            write_unit(battle_id, unit_id, U_DEST_Z, action_id % 256);
            break;
        case ACTION_MOVE_TO_UNIT:
            // Unit-anchored reposition (ADR-0024): the resolved target unit is the
            // anchor; stage_pathfind re-reads its live position each tick. action_id
            // is unused.
            write_unit(battle_id, unit_id, U_TARGET, final_target);
            break;
        case ACTION_RETREAT_STEP:
            // ADR-0301. Unlike every other carrier here, the DESTINATION is already
            // decided -- `execute_gambit_action` ran `retreat_step_cell` before it
            // committed the slot, because a cornered retreat has to fall THROUGH to
            // the next gambit and only the decide stage can still do that. So this
            // carries a validated adjacent cell, not an anchor to path toward, and
            // stage_pathfind never re-picks it.
            write_unit(battle_id, unit_id, U_TARGET, final_target);
            write_unit(battle_id, unit_id, U_DEST_X, action_id / 4096);
            write_unit(battle_id, unit_id, U_DEST_Z, (action_id / 16) % 256);
            write_unit(battle_id, unit_id, U_DEST_LEVEL, action_id % 16);
            break;
        // ACTION_WAIT — no carriers needed.
    }
}

// Stage 2b Phase 2.b — deferred-execution dispatcher. Called from
// compute_unit_state after a gambit committed. Reads U_PENDING_ACTION_TYPE
// + carriers and runs the action body. This is the structural pivot that
// lets Phases 3–5 move individual cases out into their own sub-stages.
void apply_pending_action(int battle_id, int unit_id) {
    int pending = read_unit_next(battle_id, unit_id, U_PENDING_ACTION_TYPE);
    if (pending == ACTION_NONE) return;

    // ACTION_ATTACK → stage_attack.glsl (Phase 3).
    // ACTION_SPELL / ACTION_ABILITY / ACTION_ITEM / ACTION_COMPLETE_SPELL →
    //   stage_spell.glsl (Phase 4).
    // ACTION_MOVE_TO / ACTION_PATHFIND_MOVE / ACTION_PATHFIND_CAST →
    //   stage_pathfind.glsl (Phase 5).
    // All deferred branches early-return here; their respective stages run
    // as separate dispatches after this one and read NEXT-buffer carriers.
    if (pending == ACTION_ATTACK) return;
    if (pending == ACTION_SPELL || pending == ACTION_ABILITY) return;
    if (pending == ACTION_ITEM) return;
    if (pending == ACTION_COMPLETE_SPELL) return;
    if (pending == ACTION_MOVE_TO) return;
    if (pending == ACTION_MOVE_TO_UNIT) return;
    if (pending == ACTION_RETREAT_STEP) return;
    if (pending == ACTION_PATHFIND_MOVE || pending == ACTION_PATHFIND_CAST) return;

    if (pending == ACTION_WAIT) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        return;
    }
}

// Dispatcher: record the action specified by a gambit into U_PENDING_ACTION_TYPE
// + scratch carriers. apply_pending_action() runs the body separately.
// Returns true if action was committed, false on cheap failure (gambit
// fallthrough). LOS/cast-position failure no longer falls through here —
// see docs/stage_2b_phase_2b_plan.md §2 for the 1-tick delay rationale.
// `verdict` is ADR-0275 dec. 4's stamp for the five failure points that live in HERE
// rather than in the slot walk. It is an `out` rather than a return-type change so the
// caller's `if (execute_gambit_action(...))` fall-through reads exactly as it did.
bool execute_gambit_action(int battle_id, int unit_id, int gambit_slot, int condition_target,
                           int override_target, out int verdict) {
    verdict = VERDICT_FIRED;
    int global_unit_id = battle_id * config.units_per_battle + unit_id;
    int action_type = get_gambit_action_type(global_unit_id, gambit_slot);
    int action_id = get_gambit_action_id(global_unit_id, gambit_slot);
    int action_target_type = get_gambit_action_target_type(global_unit_id, gambit_slot);

    // Resolve final target
    int final_target;
    if (override_target >= 0) {
        final_target = override_target;
    } else if (action_target_type == TARGET_THEM) {
        final_target = condition_target;
    } else {
        final_target = select_target(battle_id, unit_id, action_target_type);
    }

    if (final_target < 0 && action_type != ACTION_WAIT) {
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_GAMBIT_FAILED);
        record_decision(battle_id, unit_id, REASON_GAMBIT_FAILED, LOGICAL_ACTIVITY_IDLE, -1);
        verdict = VERDICT_NO_FINAL_TARGET;
        return false;
    }

    // Tier 2 #8 — status gates that veto an otherwise-valid gambit so the
    // gambit list can fall through to the next slot.
    //   Silence    → blocks SPELL / ABILITY (items still pass).
    //   Immobilize → blocks MOVE_TO.
    if ((action_type == ACTION_SPELL || action_type == ACTION_ABILITY)
        && has_status(battle_id, unit_id, STATUS_SILENCE)) {
        verdict = VERDICT_SILENCED;
        return false;
    }
    if ((action_type == ACTION_MOVE_TO || action_type == ACTION_MOVE_TO_UNIT
            || action_type == ACTION_RETREAT_STEP)
        && has_status(battle_id, unit_id, STATUS_IMMOBILIZE)) {
        verdict = VERDICT_IMMOBILIZED;
        return false;
    }

    // Cheap pre-validation for spell-like actions. MP shortage = sync
    // fallthrough (matches pre-2.b). Other failure modes (LOS, no cast
    // position) accept a 1-tick re-evaluation delay.
    if (action_type == ACTION_SPELL || action_type == ACTION_ABILITY
        || (action_type == ACTION_ITEM && final_target >= 0)) {
        if (!spell_pre_validate(battle_id, unit_id, final_target, action_id, action_type)) {
            verdict = VERDICT_MP_SHORT;
            return false;
        }
        // ADR-0047 B8 cooldown veto. Independent of the MP veto: either
        // short-circuits the slot. action_id is the ability_id for these
        // action types.
        if (!cooldown_pre_validate(battle_id, unit_id, action_id)) {
            verdict = VERDICT_ON_COOLDOWN;
            return false;
        }
    }

    // ADR-0301 -- THE ONE PRE-VALIDATION THAT LOOKS AT THE MAP. Every other cheap
    // failure above reads a status bit, a pool or an ability record; this one asks
    // the distance field whether a step away from `final_target` exists at all, and
    // it has to ask HERE rather than in the pathfind body for the same reason MP
    // shortage does: a cornered unit must fall through to the slots BELOW its
    // retreat (its `Attack`, usually) in this same evaluation. Deferring the pick
    // would leave it committed to a retreat it cannot take, re-deciding into the
    // same wall every TICKS_GAMBIT_REEVAL and never reaching another slot.
    //
    // The picked cell rides out on `action_id`, which a RETREAT gambit does not
    // otherwise use (the encoder writes 0), packed the way ACTION_MOVE_TO already
    // packs its destination -- with a level field, because ADR-0224 made a
    // destination a CELL and the two cells of one column are different tiles.
    if (action_type == ACTION_RETREAT_STEP) {
        ivec3 cell = retreat_step_cell(battle_id, unit_id, final_target);
        if (cell.x < 0) {
            verdict = VERDICT_NO_RETREAT;
            return false;
        }
        action_id = cell.x * 4096 + cell.y * 16 + cell.z;
    }

    write_unit(battle_id, unit_id, U_CURRENT_GAMBIT, gambit_slot);
    // Clear previous move position -new gambit = fresh path
    write_unit(battle_id, unit_id, U_PREV_MOVE_POS, -1);

    // Record the action choice; apply_pending_action() runs the body later
    // in this tick (or in a sub-stage dispatch after Phases 3–5 land).
    write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, action_type);
    record_action_carriers(battle_id, unit_id, action_type, final_target, action_id);

    // ADR-0047 — start the per-(unit, ability) cooldown timer at commit
    // time, same beat MP would be deducted at (fire-and-forget; an
    // interrupted action does NOT refund the timer, matching the MP model).
    // SPELL/ABILITY/ITEM only — ATTACK and MOVE carry no ability_id, so
    // their cooldown is implicit (animation duration / movement timing).
    if (action_type == ACTION_SPELL || action_type == ACTION_ABILITY
            || action_type == ACTION_ITEM) {
        if (action_id >= 0 && action_id < MAX_COOLDOWN_ABILITIES) {
            int cooldown_ticks = get_ability_cooldown_ticks(action_id);
            if (cooldown_ticks > 0) {
                int tick = get_battle_tick(battle_id);
                set_cooldown_ready_at(battle_id, unit_id, action_id,
                                      tick + cooldown_ticks);
            }
        }
    }

    // TRANSPARENT outgoing-action consume (status_system.md §2 "Target filter").
    // Committing to ATTACK / SPELL / ABILITY / ITEM reveals the carrier; the
    // bit + its timer slot clear this tick, so enemies see them on next gambit
    // eval. MOVE_TO / MOVE_TO_UNIT / WAIT preserve the bit (FFT canon — you
    // can sneak around invisible). NEXT-buffer reads + inline bit AND-NOT so
    // we compose with same-tick decay from tick_status_timers without using
    // clear_status() / clear_status_timer() (which read CURRENT).
    if ((action_type == ACTION_ATTACK || action_type == ACTION_SPELL
            || action_type == ACTION_ABILITY || action_type == ACTION_ITEM)
            && has_status_next(battle_id, unit_id, STATUS_TRANSPARENT)) {
        int flags_lo = read_unit_next(battle_id, unit_id, U_STATUS_FLAGS_LO);
        write_unit(battle_id, unit_id, U_STATUS_FLAGS_LO,
                   flags_lo & ~(1 << STATUS_TRANSPARENT));
        for (int slot = 0; slot < 8; slot++) {
            int packed = read_unit_next(battle_id, unit_id, U_STATUS_TIMER_0 + slot);
            if (packed != 0 && ((packed >> 24) & 0xFF) == STATUS_TRANSPARENT) {
                write_unit(battle_id, unit_id, U_STATUS_TIMER_0 + slot, 0);
                break;
            }
        }
    }
    return true;
}

// Check whether all conditions for a gambit slot pass against a candidate target.
//
// The four `out` params are ADR-0275 dec. 4's verdict detail. `eval_mask` carries one bit
// per condition this call actually RAN, and it is what stops the readout misleading:
// "condition 2 failed" without it reads as if 2 were the only one checked. Only the FIRST
// failure is reported, because the kernel genuinely stops there -- the conditions after it
// have no answer to give.
bool check_gambit_conditions(int battle_id, int unit_id, int global_unit_id,
                             int slot, int candidate,
                             out int fail_index, out int fail_opcode,
                             out int eval_mask, out int payload) {
    fail_index = 0;
    fail_opcode = 0;
    eval_mask = 0;
    payload = 0;
    int cond_count = get_gambit_cond_count(global_unit_id, slot);
    // Read ONCE, outside the loop: the slot's action is the same for all four conditions, and
    // only `COND_IN_RANGE` looks at it.
    int action_type = get_gambit_action_type(global_unit_id, slot);
    int action_id = get_gambit_action_id(global_unit_id, slot);
    for (int c = 0; c < cond_count && c < MAX_GAMBIT_CONDITIONS; c++) {
        int ctype = get_gambit_cond_type(global_unit_id, slot, c);
        int cval = get_gambit_cond_value(global_unit_id, slot, c);
        eval_mask |= (1 << c);
        int measured;
        if (!evaluate_condition(battle_id, unit_id, candidate, ctype, cval,
                                action_type, action_id, measured)) {
            fail_index = c;
            fail_opcode = ctype;
            payload = measured;
            return false;
        }
    }
    return true;
}

// Evaluate all gambits for a unit and execute the first matching one.
// Two-pass: Pass 1 tries primary targets. Pass 2 retries "nearest" type
// gambits with alternate targets when all slots failed in Pass 1.
// Returns true if a gambit was triggered.
// Evaluate gambits up to (but not including) max_slot.
// Pass MAX_GAMBITS to evaluate all slots (normal evaluation).
// Pass current_gambit to only check higher-priority slots (re-evaluation during movement).
bool evaluate_gambits_up_to(int battle_id, int unit_id, int max_slot) {
    int global_unit_id = battle_id * config.units_per_battle + unit_id;

    // ADR-0275 dec. 4/18 — CLEAR BEFORE THE WALK. A verdict left over from an earlier
    // evaluation is indistinguishable from "this slot never declined", which is the one
    // failure mode a debugging instrument must not have. Only the slots this call will
    // actually walk are cleared: the movement re-evaluation path passes `current_gambit`
    // as `max_slot`, and the executing slot's verdict is not this call's to erase.
    for (int slot = 0; slot < MAX_GAMBITS; slot++) {
        if (slot >= max_slot) break;
        clear_verdict(global_unit_id, slot);
    }

    // --- Pass 1: try primary targets ---
    for (int slot = 0; slot < MAX_GAMBITS; slot++) {
        if (slot >= max_slot) break;
        if (!gambit_enabled(global_unit_id, slot)) {
            write_verdict_pass1(global_unit_id, slot, VERDICT_DISABLED, 0, 0, 0, 0);
            continue;
        }

        int target_type = get_gambit_cond_target_type(global_unit_id, slot);
        int candidate = select_target(battle_id, unit_id, target_type);
        if (candidate < 0) {
            write_verdict_pass1(global_unit_id, slot, VERDICT_NO_CANDIDATE,
                                0, 0, 0, target_type);
            continue;
        }

        int fail_index;
        int fail_opcode;
        int eval_mask;
        int payload;
        if (check_gambit_conditions(battle_id, unit_id, global_unit_id, slot, candidate,
                                    fail_index, fail_opcode, eval_mask, payload)) {
            int verdict;
            bool fired = execute_gambit_action(battle_id, unit_id, slot, candidate, -1, verdict);
            write_verdict_pass1(global_unit_id, slot, verdict, 0, 0, eval_mask, candidate);
            if (fired) {
                return true;
            }
        } else {
            write_verdict_pass1(global_unit_id, slot, VERDICT_CONDITION_FALSE,
                                fail_index, fail_opcode, eval_mask, payload);
        }
    }

    // --- Pass 2: retry "nearest" gambits with alternate targets ---
    for (int slot = 0; slot < MAX_GAMBITS; slot++) {
        if (slot >= max_slot) break;
        if (!gambit_enabled(global_unit_id, slot)) continue;

        int target_type = get_gambit_cond_target_type(global_unit_id, slot);
        // Only retry nearest-type targets that have alternates.
        // TARGET_NEAREST_ALLY_OR_KO belongs here and the whole design leans on it (#1102):
        // the nearest ally is usually STANDING, so a `KO'd?` slot fails at rank 0 and would
        // never be seen again without the rank walk. Omitting it would leave the revive
        // gambit working only when the corpse happened to be the closest ally.
        //
        // 🔴 TARGET_NEAREST_ALLY_ONLY / TARGET_NEAREST_ENEMY_ONLY ARE ABSENT ON PURPOSE, AND
        // THE ABSENCE IS THE WHOLE FEATURE (ADR-0285). They run the same rank-0 search as the
        // two listed above; not listing them here is what makes them STRICT, and it routes
        // them into the VERDICT_NOT_RETRYABLE stamp below with no clause of their own. Adding
        // either to this condition silently re-means the surface's `Nearest Ally` row back
        // into the pool search it was built to stop being.
        if (target_type != TARGET_NEAREST_ENEMY && target_type != TARGET_NEAREST_ALLY
                && target_type != TARGET_NEAREST_ALLY_OR_KO) {
            write_verdict_pass2(global_unit_id, slot, VERDICT_NOT_RETRYABLE, 0, 0, 0);
            continue;
        }

        // Try rank 1, 2, 3... (rank 0 was tried in Pass 1)
        int last_rank = 0;
        int p2_verdict = VERDICT_RANKS_EXHAUSTED;
        int p2_index = 0;
        int p2_opcode = 0;
        for (int rank = 1; rank < config.units_per_battle; rank++) {
            bool want_ally = (target_type != TARGET_NEAREST_ENEMY);
            bool include_ko = (target_type == TARGET_NEAREST_ALLY_OR_KO);
            int candidate = find_nth_nearest(battle_id, unit_id, rank, want_ally, include_ko);
            if (candidate < 0) break;  // No more candidates
            last_rank = rank;

            int fail_index;
            int fail_opcode;
            int eval_mask;
            int payload;
            if (check_gambit_conditions(battle_id, unit_id, global_unit_id, slot, candidate,
                                        fail_index, fail_opcode, eval_mask, payload)) {
                int verdict;
                bool fired = execute_gambit_action(battle_id, unit_id, slot, candidate,
                                                   candidate, verdict);
                p2_verdict = verdict;
                p2_index = 0;
                p2_opcode = 0;
                if (fired) {
                    write_verdict_pass2(global_unit_id, slot, verdict, 0, 0, rank);
                    return true;
                }
            } else {
                p2_verdict = VERDICT_CONDITION_FALSE;
                p2_index = fail_index;
                p2_opcode = fail_opcode;
            }
        }
        // One stamp for the whole rank walk. A fixed-width field cannot hold a verdict per
        // rank, so it holds the LAST one and the rank it came from; int B still carries
        // pass 1's payload, which for a nearest-type slot IS rank 0's.
        write_verdict_pass2(global_unit_id, slot, p2_verdict, p2_index, p2_opcode, last_rank);
    }

    // No gambit triggered -don't clear current_gambit when re-evaluating during movement,
    // since the unit should continue executing its current gambit.
    if (max_slot >= MAX_GAMBITS) {
        write_unit(battle_id, unit_id, U_CURRENT_GAMBIT, -1);
    }
    return false;
}

bool evaluate_gambits(int battle_id, int unit_id) {
    return evaluate_gambits_up_to(battle_id, unit_id, MAX_GAMBITS);
}

#endif // PASS_COMPUTE -spell casting, gambit system
#ifdef PASS_COMPUTE

// Check pre-damage reactions (called before damage is applied)
void check_pre_damage_reactions(int battle_id, int attacker, int defender) {
    int reaction = read_unit(battle_id, defender, U_REACTION_ABILITY);

    if (reaction == REACT_FIRST_STRIKE) {
        // Defender attacks first if they haven't acted this tick
        int defender_state = read_unit(battle_id, defender, U_STATE);
        if (defender_state == LOGICAL_ACTIVITY_IDLE) {
            // Queue counter-attack
            write_unit(battle_id, defender, U_TARGET, attacker);
            write_unit(battle_id, defender, U_STATE, LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER);
        }
    }
}

// Apply damage with reaction checks
void apply_damage_with_reactions(int battle_id, int attacker, int defender, int damage) {
    int reaction = read_unit(battle_id, defender, U_REACTION_ABILITY);

    // Handle different reaction abilities
    switch (reaction) {
        case REACT_COUNTER:
            // Queue counter-attack if attacker is in melee range
            {
                int dx = read_unit(battle_id, defender, U_POS_X);
                int dz = read_unit(battle_id, defender, U_POS_Z);
                int ax = read_unit(battle_id, attacker, U_POS_X);
                int az = read_unit(battle_id, attacker, U_POS_Z);
                if (manhattan_distance(dx, dz, ax, az) <= 1) {
                    // Mark for counter-attack (handled in next tick)
                    write_unit(battle_id, defender, U_TARGET, attacker);
                }
            }
            break;

        case REACT_ABSORB_MP:
            // Convert portion of damage to MP
            {
                int mp_gain = damage / 4;
                add_mp(battle_id, defender, mp_gain);
            }
            break;

        case REACT_AUTO_POTION:
            // Use potion if HP will be critical
            {
                int new_hp = get_hp(battle_id, defender) - damage;
                int max_hp = get_max_hp(battle_id, defender);
                if (new_hp < max_hp / 4) {
                    // Auto-heal (simplified: just add HP)
                    write_unit(battle_id, defender, U_HP, new_hp + AUTO_POTION_HEAL_AMOUNT);
                    return;  // Skip normal damage application
                }
            }
            break;

        case REACT_MANA_SHIELD:
            // Convert damage to MP loss instead
            {
                int mp = get_mp(battle_id, defender);
                int mp_damage = damage;
                if (mp >= mp_damage) {
                    spend_mp(battle_id, defender, mp_damage);
                    return;  // No HP damage
                } else {
                    // Partial absorption
                    int remaining = mp_damage - mp;
                    spend_mp(battle_id, defender, mp);
                    damage = remaining;
                }
            }
            break;
    }

    // Apply the damage to pending (will be processed in damage pass)
    int pending = read_unit(battle_id, defender, U_PENDING_DAMAGE);
    write_unit(battle_id, defender, U_PENDING_DAMAGE, pending + damage);
}
#endif // PASS_COMPUTE — unused reactions
#ifdef PASS_COMPUTE

// Apply single-target spell healing to one (caster, target, ability) tuple.
// Two paths, distinguished by U_PROJECTILE_FRAME:
// - Projectile-deferred: stamp U_PENDING_HEAL_TARGET / U_PENDING_HEAL_AMOUNT
//   on the caster so the in-flight projectile's landing applies the heal.
// - Immediate: apply HP up directly (Undead inverts to damage via
//   U_PENDING_DAMAGE per Tier 2 #10).
// In both paths the caster's U_CASTING_ABILITY_ID / U_CAST_TARGET clears
// stay at the call site -- the cinematic orchestrator (issue #53) keeps
// them open across many per-target applications.
// `tick` is unused today but kept for signature parity with
// apply_damage_to_target so the orchestrator can call either uniformly.
void apply_heal_to_target(int battle_id, int caster, int target, int ability_id, int tick) {
    int amount = calculate_spell_damage(battle_id, caster, target, ability_id);
    int proj_frame = read_unit(battle_id, caster, U_PROJECTILE_FRAME);
    if (proj_frame >= 0) {
        // Has projectile - defer healing to CPU for visual sync
        write_unit(battle_id, caster, U_PENDING_HEAL_TARGET, target);
        write_unit(battle_id, caster, U_PENDING_HEAL_AMOUNT, amount);
    } else {
        // No projectile - apply healing directly. Undead inverts to damage
        // via pending_damage (Tier 2 #10).
        if (has_status(battle_id, target, STATUS_UNDEAD)) {
            int pending = read_unit(battle_id, target, U_PENDING_DAMAGE);
            write_unit(battle_id, target, U_PENDING_DAMAGE, pending + amount);
        } else {
            int current_hp = get_hp(battle_id, target);
            int max_hp = get_max_hp(battle_id, target);
            write_unit(battle_id, target, U_HP, min(max_hp, current_hp + amount));
        }
    }
    // Issue #100: healing-classified abilities that also carry a cancel mask
    // (Antidote, Eye Drop, Echo Grass, Maiden's Kiss, Soft, Remedy, Phoenix
    // Down) need the same inflict-apply seam as the damage path. INFLICT_MODE_
    // NONE / mask==0 no-ops keep this free for plain heals.
    apply_inflict_all(battle_id, caster, target,
                      get_ability_inflict_mask(ability_id),
                      get_ability_inflict_mode(ability_id), tick);
}

// Apply single-target spell damage to one (caster, target, ability) tuple.
// Rolls evasion when the ability flag set requires it, computes damage,
// and writes U_DAMAGE_TARGET / U_DAMAGE_AMOUNT on the caster -- the
// stage_damage pass reads those to apply the HP delta. Extracted from
// apply_attack_damage so the cinematic-spell orchestrator (issue #53)
// can fire damage per-target on its own beat without touching the
// caster's cast state.
void apply_damage_to_target(int battle_id, int caster, int target, int ability_id, int tick) {
    int amount = calculate_spell_damage(battle_id, caster, target, ability_id);
    // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) at the queue
    // site, BEFORE the target-side defense. Mirrors ROM FUN_80185FFC ordering.
    int element_id = get_ability_field(ability_id, AB_ELEMENT);
    amount = apply_strengthen_elem(battle_id, caster, element_id, amount);
    // Issue #110 -- scale by target's element defense at queue time, same
    // shape as stage_spell.glsl's apply_damage_to_target. Reached by
    // single-target damage spells with projectile (cast_projectile_spell)
    // and adjacent damage items (cast_adjacent_item) -- both stamp
    // DAMAGE_FRAME >= 0 with ability_id > 0, then apply_attack_damage routes
    // here when the damage frame crosses in tick_acting_animation or the
    // AWAITING_IMPACT timer expires.
    amount = apply_element_defense(battle_id, target, ability_id, amount);
    int ab_flags = get_ability_flags(ability_id);
    bool evadeable = (ab_flags & ABFLAG_EVADEABLE) != 0;
    bool hit = !evadeable || roll_evasion(battle_id, caster, target, tick, true);
    if (hit) {
        write_unit(battle_id, caster, U_DAMAGE_TARGET, target);
        write_unit(battle_id, caster, U_DAMAGE_AMOUNT, amount);
        // Issue #98/#100: mirror the apply_damage_to_target in stage_spell.glsl.
        // Single-target item / instant abilities (e.g. Antidote, Eye Drop)
        // resolve through this path; without the inflict-apply they have no
        // way to set or clear status bits. INFLICT_MODE_NONE / mask==0 no-ops.
        apply_inflict_all(battle_id, caster, target,
                          get_ability_inflict_mask(ability_id),
                          get_ability_inflict_mode(ability_id), tick);
    }
}

// Apply the attack/spell damage write at the visual hit moment.
// Rolls evasion / Blade Grasp / Arrow Guard, computes damage or healing,
// writes U_DAMAGE_TARGET/U_DAMAGE_AMOUNT (or U_PENDING_HEAL_*, AOE fields),
// and clears U_CASTING_ABILITY_ID / U_CAST_TARGET on resolved branches.
// Called from two sites (ADR-0032): the in-SEQ damage-frame crossing in
// tick_acting_animation (melee / instant / adjacent-item) and the
// LOGICAL_ACTIVITY_AWAITING_IMPACT timer-zero edge (ranged weapon + projectile spell).
void apply_attack_damage(int battle_id, int unit_id, int tick) {
    int target = read_unit(battle_id, unit_id, U_TARGET);
    // #1113 — DEAD-FILTER 3 OF 4, and the one PhoenixDown dies on: an ITEM
    // ability is always "projectile" (is_projectile_ability), so it lands here
    // rather than in cast_instant_spell, whether thrown or handed over at
    // range 1. A cancel-Dead ability revives the corpse and clears its own cast
    // state; anything else — including a plain weapon swing, which has no
    // ability id at all — keeps the unconditional return it has always had.
    //
    // Taking the revive HERE, ahead of the branch below, is also what keeps
    // stage_damage's Phase-4 projectile-deferred heal out of the revive path:
    // apply_heal_to_target would have queued U_PENDING_HEAL_* on the caster for
    // a NEXT-tick apply, and that apply reads the NEXT buffer — which would
    // have made revive_unit a second write site in a second buffer. One site,
    // one buffer, one tick.
    if (target >= 0 && is_unit_dead(battle_id, target)) {
        int revive_ability = read_unit(battle_id, unit_id, U_CASTING_ABILITY_ID);
        if (revive_ability > 0 && ability_revives(revive_ability)) {
            revive_unit(battle_id, target,
                        calculate_spell_damage(battle_id, unit_id, target, revive_ability));
            write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
            write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
        }
        return;
    }
    if (target >= 0 && !is_unit_dead(battle_id, target)) {
        int ability_id = read_unit(battle_id, unit_id, U_CASTING_ABILITY_ID);

        if (ability_id > 0) {
            int effect_area = get_ability_effect_area(ability_id);

            if (effect_area > 0) {
                // AOE ability: store center position for Pass 4 resolution
                int center_x = read_unit(battle_id, target, U_POS_X);
                int center_z = read_unit(battle_id, target, U_POS_Z);
                write_unit(battle_id, unit_id, U_AOE_CENTER_X, center_x);
                write_unit(battle_id, unit_id, U_AOE_CENTER_Z, center_z);
                write_unit(battle_id, unit_id, U_AOE_ABILITY_ID, ability_id);
                write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
                write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
            } else if (is_ability_healing(ability_id)) {
                // Single-target healing. apply_heal_to_target dispatches the
                // projectile-defer vs immediate branch internally; the cast
                // state clear happens only on the immediate path (the
                // projectile-defer branch hands the clear to whoever applies
                // U_PENDING_HEAL_* later).
                int proj_frame = read_unit(battle_id, unit_id, U_PROJECTILE_FRAME);
                apply_heal_to_target(battle_id, unit_id, target, ability_id, tick);
                if (proj_frame < 0) {
                    write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
                    write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
                }
            } else {
                // Single-target damage. Delegates the damage math + write to
                // apply_damage_to_target; the cast-state clear stays here
                // because the cinematic orchestrator (issue #53) holds the
                // cast state open across many per-target damage applications.
                apply_damage_to_target(battle_id, unit_id, target, ability_id, tick);
                write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
                write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
            }
        } else {
            // Weapon-based damage (physical evasion)
            bool hit = roll_evasion(battle_id, unit_id, target, tick, false);

            // Tier 2 #7 part 3 — Blade Grasp (melee) / Arrow Guard (ranged):
            // a second evasion check tied to the matching attack type.
            // Trigger chance = min(target.PA * 5, 95)%. On success the
            // hit is treated as evaded; we don't re-roll the SPU evasion
            // flavour and keep the weapon-parry evade_type for consistency
            // with the existing miss visualization.
            if (hit) {
                int defender_react = read_unit(battle_id, target, U_REACTION_ABILITY);
                bool attacker_ranged = read_unit(battle_id, unit_id, U_PROJECTILE_FRAME) >= 0;
                bool react_active =
                    (attacker_ranged && defender_react == REACT_ARROW_GUARD)
                    || (!attacker_ranged && defender_react == REACT_BLADE_GRASP);
                if (react_active) {
                    int t_pa = read_unit(battle_id, target, U_PA);
                    int chance = min(max(0, t_pa) * 5, 95);
                    int roll = rand_int(battle_id, target, tick + 1, 100) + 1;
                    if (roll <= chance) {
                        hit = false;
                        write_unit(battle_id, target, U_EVADE_TYPE, 3);  // weapon parry-like
                    }
                }
            }

            if (hit) {
                int damage = calculate_damage(battle_id, unit_id, target);
                int w_element = read_unit(battle_id, unit_id, U_WEAPON_ELEMENT);
                // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) on
                // the weapon-element basic attack. FUN_80185FFC fires from
                // every per-formula handler including 02_SpellWeapon, so a
                // Flame-Rod swinger with Black Robe-strengthen-Fire gets the
                // 1.25x pre-mitigation before the weapon-element matrix.
                damage = apply_strengthen_elem(battle_id, unit_id, w_element, damage);
                // Issue #116 -- weapon-element defense at the queue site (same
                // shape as #110's spell-side apply_element_defense). Mirrors
                // ROM FUN_80186FD0 at ram:80186FD0 (called from the basic-
                // attack post-process chain FUN_80188E38 at ram:80188E38,
                // downstream of 01_Weapon at ram:80188B14 / 02_SpellWeapon at
                // ram:80188BAC -- the formula handlers reached via
                // AbilityFormulaCodePtrs[0,1]): equipment matrix only, no
                // status overlay, so an Oiled Fire-weapon target does NOT
                // take x2 here. Element 0 (non-elemental weapon / unarmed) is
                // a clean pass-through.
                damage = apply_weapon_element_defense(battle_id, target, w_element, damage);
                write_unit(battle_id, unit_id, U_DAMAGE_TARGET, target);
                write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, damage);
                // Issue #98 tracer -- equipped-weapon on-hit inflict (e.g.
                // Blind Knife -> Darkness). _extract_unit_config encoded the
                // weapon's inflict_statuses + inflict_mode into these slots
                // via StatusEncoder. INFLICT_MODE_NONE / mask==0 no-ops.
                int w_mask = read_unit(battle_id, unit_id, U_WEAPON_INFLICT_MASK);
                int w_mode = read_unit(battle_id, unit_id, U_WEAPON_INFLICT_MODE);
                apply_inflict_all(battle_id, unit_id, target, w_mask, w_mode, tick);
            }
        }
    }
}

// Tick animation frame and check for damage/projectile triggers during LOGICAL_ACTIVITY_ACTING.
// Advances anim_frame, checks projectile spawn frame, and applies damage at
// the PostGenericAttack frame (where visual hit connects).
void tick_acting_animation(int battle_id, int unit_id, int tick) {
    int anim_frame = read_unit(battle_id, unit_id, U_ANIM_FRAME);
    int damage_frame = read_unit(battle_id, unit_id, U_DAMAGE_FRAME);
    int projectile_frame = read_unit(battle_id, unit_id, U_PROJECTILE_FRAME);
    int anim_flags = read_unit(battle_id, unit_id, U_ANIM_FLAGS);

    // Advance animation frame (ABILITY_SEQ_SPEED frames per tick)
    int new_anim_frame = anim_frame + ABILITY_SEQ_SPEED;
    write_unit(battle_id, unit_id, U_ANIM_FRAME, new_anim_frame);

    // Check if we crossed the projectile frame (QueueSpriteAnim point for ranged weapons)
    // Bit 1 of anim_flags = projectile_triggered
    bool projectile_not_triggered = (anim_flags & 2) == 0;
    if (projectile_not_triggered && projectile_frame >= 0 && anim_frame < projectile_frame && new_anim_frame >= projectile_frame) {
        anim_flags = anim_flags | 2;
        write_unit(battle_id, unit_id, U_ANIM_FLAGS, anim_flags);
    }

    // Check if we crossed the damage frame (PostGenericAttack point)
    // Bit 0 of anim_flags = damage_triggered
    bool damage_not_triggered = (anim_flags & 1) == 0;
    if (damage_not_triggered && damage_frame >= 0 && anim_frame < damage_frame && new_anim_frame >= damage_frame) {
        apply_attack_damage(battle_id, unit_id, tick);
        // Set damage_triggered flag to prevent re-triggering
        write_unit(battle_id, unit_id, U_ANIM_FLAGS, anim_flags | 1);
    }
}


void compute_unit_state(int battle_id, int unit_id, int tick) {
    if (unit_id == 0) {
        copy_header_to_next(battle_id);
    }
    copy_unit_to_next(battle_id, unit_id);

    // Turn meter (ADR-0236). BEFORE the pause gate and outside every activity
    // branch below: the meter is the CLOCK, not an activity, and the only state
    // that stops it is death. A unit mid-cast still gets its turn (design S3),
    // and a cinematic pauses everyone EXCEPT its caster -- gating here on
    // U_PAUSED would hand that caster free meter. A ready unit (>= FULL) stops
    // accumulating rather than wrapping, so the host sees the overshoot and can
    // carry it; `max(1, ...)` keeps a Speed-0 unit from never acting, which
    // would make the turn-queue forecast non-terminating.
    if (!is_unit_dead(battle_id, unit_id)) {
        int turn_meter = read_unit(battle_id, unit_id, U_TURN_METER);
        if (turn_meter < TURN_METER_FULL) {
            int gain = max(1, read_unit(battle_id, unit_id, U_SPEED));
            write_unit(battle_id, unit_id, U_TURN_METER, turn_meter + gain);
        }
    }

    // Cinematic-spell pause (issue #53; ref-count in #118). A paused unit's
    // next-buffer state stays in sync via the copy above, then per-tick state
    // work is skipped. Ref-count semantics (every cast_cinematic_spell /
    // start_reraise_cinematic increment is paired with a cinematic_teardown
    // decrement, clamped at 0) make a stale U_PAUSED impossible by
    // construction, so the prior battle-header safety belt is gone.
    if (read_unit(battle_id, unit_id, U_PAUSED) != 0) {
        return;
    }

    // Initialize debug fields
    write_unit(battle_id, unit_id, U_DBG_CONFLICT_BLOCKED, 0);
    write_unit(battle_id, unit_id, U_DBG_CONFLICT_BLOCKER, -1);
    write_unit(battle_id, unit_id, U_DBG_PROPOSED_ACCEPTED, 1);
    write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_NONE);

    if (is_unit_dead(battle_id, unit_id)) {
        write_unit(battle_id, unit_id, U_DAMAGE_TARGET, -1);
        write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, 0);
        return;
    }

    int state = read_unit(battle_id, unit_id, U_STATE);

    // Victorious units stay victorious -no further state processing
    if (state == LOGICAL_ACTIVITY_CELEBRATING) {
        write_unit(battle_id, unit_id, U_DAMAGE_TARGET, -1);
        write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, 0);
        return;
    }

    int timer = read_unit(battle_id, unit_id, U_TIMER);

    // Clear damage queuing (will set if we attack)
    write_unit(battle_id, unit_id, U_DAMAGE_TARGET, -1);
    write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, 0);

    // Clear AOE fields (will set if AOE ability is cast)
    write_unit(battle_id, unit_id, U_AOE_CENTER_X, -1);
    write_unit(battle_id, unit_id, U_AOE_CENTER_Z, -1);
    write_unit(battle_id, unit_id, U_AOE_ABILITY_ID, -1);

    // Stage 2b scaffold — cleared every tick. No consumer yet.
    write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_NONE);

    // THE FIGHT IS OVER, SO NOTHING A UNIT WAS MID-WAY THROUGH MATTERS (#897).
    //
    // This check used to live at the bottom, in the IDLE fall-through, which meant
    // a unit had to REACH idle to notice it had won. A unit with a live "attack the
    // nearest enemy" gambit and no living enemy never does: the gambit re-evaluates,
    // the unit re-enters WALKING toward a target that no longer resolves, and its
    // timer restarts every tick. MEASURED at Gariland with the rollout AI driving
    // (#897): team 1 annihilated, one survivor CELEBRATING and one stuck WALKING with
    // `target` pointing at itself and `timer` moving 48 -> 47 across 800 frames.
    // `stage_victory` reports a win only when every survivor is celebrating, so the
    // battle ran to the rig's 12,000-frame bound with the fight long since decided.
    //
    // It is not an AI defect and the AI is only what exposed it — any authored attack
    // gambit reaches the same loop. Gariland ended before this because a
    // scenario-booted cast has EMPTY gambit lists (ADR-0242), so its survivors sat in
    // IDLE and fell through to the old check.
    //
    // 🔴 IT HAS TO SIT AFTER THE PER-TICK CLEARS, NOT BEFORE THEM. Returning above
    // `U_PENDING_ACTION_TYPE = ACTION_NONE` leaves last tick's ACTION_PATHFIND_MOVE
    // standing, `stage_pathfind` runs it, and `handle_moving_state()` writes WALKING
    // straight back over the CELEBRATING this just set — every tick, invisibly. The
    // first cut did exactly that and `GPURolloutDriverTest`'s arm 5 is what caught it.
    // The proposed position is reset here too, because the reset above deliberately
    // skips the walking states and this unit has just stopped being one.
    //
    // DYING is exempt: a unit playing out its death as the last enemy falls is still
    // dying, and celebrating it would skip the animation stage_victory is waiting on.
    //
    // 🔴 AND THE SETTLE BRAKE EXTENDS THAT EXEMPTION TO EVERYONE STILL MOVING OR
    // SWINGING (`config.settle_brake_battle`). "Nothing a unit was mid-way through
    // matters" is true of the SIMULATION and false of the PICTURE: logical position
    // is the DESTINATION for the whole of a step, so writing CELEBRATING over a
    // walker makes `GPUVisualBridge` drop its visualizer and snap the sprite the
    // rest of the way -- MEASURED at Gariland as a 0.967 and a 1.300 world-unit
    // teleport, one tick before the host is told the battle ended at all. The flip
    // being what `stage_victory` counts is what makes skipping it here enough: the
    // win is simply not reported until the last awaited unit has drained into IDLE
    // and been caught here, standing on its own tile. Off by default, so a battle
    // that does not arm it flips exactly as it always did.
    if (state != LOGICAL_ACTIVITY_DYING
            && !(config.settle_brake_battle == battle_id && settle_awaited_state(state))
            && is_enemy_team_dead(battle_id, unit_id)) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_CELEBRATING);
        write_unit(battle_id, unit_id, U_TIMER, 0);
        int cx = read_unit(battle_id, unit_id, U_POS_X);
        int cz = read_unit(battle_id, unit_id, U_POS_Z);
        write_unit(battle_id, unit_id, U_PROPOSED_X, cx);
        write_unit(battle_id, unit_id, U_PROPOSED_Z, cz);
        write_unit(battle_id, unit_id, U_PROPOSED_LEVEL, read_unit(battle_id, unit_id, U_LEVEL));
        return;
    }

    // Reset proposed position for non-moving units
    if (state != LOGICAL_ACTIVITY_WALKING && state != LOGICAL_ACTIVITY_WALKING_TO_CAST) {
        int my_x = read_unit(battle_id, unit_id, U_POS_X);
        int my_z = read_unit(battle_id, unit_id, U_POS_Z);
        write_unit(battle_id, unit_id, U_PROPOSED_X, my_x);
        write_unit(battle_id, unit_id, U_PROPOSED_Z, my_z);
        // The level rides with the pair it aliases (ADR-0224 dec. 4). Leaving it
        // stale here would let `stage_resolve`'s "not moving" test see a level
        // change where the unit proposed none, and commit it.
        write_unit(battle_id, unit_id, U_PROPOSED_LEVEL, read_unit(battle_id, unit_id, U_LEVEL));
    }

    // Tick reaction timer (cosmetic)
    int reaction_timer = read_unit(battle_id, unit_id, U_REACTION_TIMER);
    if (reaction_timer > 0) {
        write_unit(battle_id, unit_id, U_REACTION_TIMER, reaction_timer - 1);
    }

    // Tier 2 #6 — decay any timed status flags. Clears the status bit when
    // its slot's counter hits zero. Permanent statuses (Undead, etc.)
    // and statuses without a registered timer slot are unaffected.
    tick_status_timers(battle_id, unit_id);

    // Advance animation and check damage/projectile triggers while acting
    if (state == LOGICAL_ACTIVITY_ACTING && timer > 0) {
        tick_acting_animation(battle_id, unit_id, tick);
    }

    // Timer countdown - all state handlers below only run when timer reaches 0
    if (timer > 0) {
        write_unit(battle_id, unit_id, U_TIMER, timer - 1);
        return;
    }

    // --- State machine dispatch (timer expired) ---

    // THE TURN BRAKE (config.turn_brake_battle). A ready unit in a battle that
    // stops for turns starts NOTHING new: it settles into IDLE and waits to be
    // handed its turn.
    //
    // Why it has to exist at all — the naive "freeze only when the taker is
    // aligned" gate HANGS without it. Logical position is the DESTINATION for a
    // whole step (`write_movement_step` sets U_TIMER = U_MOVE_TOTAL_TICKS and the
    // countdown above returns early until it drains), so a continuously walking
    // unit is never aligned; and on the tick its timer hits 0 the dispatch below
    // can write the next step in the SAME tick, so the post-tick columns the gate
    // reads may never show a settled walker. The brake is what makes "settled"
    // reachable, and the gate is what makes the brake worth having. They ship
    // together or neither works.
    //
    // The U_TIMER countdown above is deliberately untouched: the unit FINISHES the
    // step it is on — which is what leaves the sprite exactly on its logical tile,
    // `GPUMovementVisualizer.calculate_position(0)` returning `end_pos` on both the
    // linear and cliff paths — and simply never starts another.
    //
    // 🔴 SAME HAZARD AS THE CELEBRATING CHECK ABOVE: this sits AFTER the per-tick
    // clears. Returning above `U_PENDING_ACTION_TYPE = ACTION_NONE` would leave
    // last tick's ACTION_PATHFIND_MOVE standing and `stage_pathfind` would write
    // WALKING straight back over the IDLE this sets, every tick, invisibly.
    //
    // Scoped to the states a unit can start something FROM. ACTING,
    // SPELL_CHARGING, AWAITING_IMPACT, PREEMPTIVE_COUNTER and DYING are mid-action
    // and are left to finish — design S3 is that a mid-cast unit still GETS its
    // turn, not that its cast is cancelled — and they all drain into IDLE, where
    // this catches them. So the brake still terminates.
    if (config.turn_brake_battle == battle_id
            && (state == LOGICAL_ACTIVITY_IDLE
                || state == LOGICAL_ACTIVITY_WALKING
                || state == LOGICAL_ACTIVITY_WALKING_TO_CAST
                || state == LOGICAL_ACTIVITY_APPROACHING
                || state == LOGICAL_ACTIVITY_RETREATING)
            && read_unit(battle_id, unit_id, U_TURN_METER) >= TURN_METER_FULL) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        int bx = read_unit(battle_id, unit_id, U_POS_X);
        int bz = read_unit(battle_id, unit_id, U_POS_Z);
        write_unit(battle_id, unit_id, U_PROPOSED_X, bx);
        write_unit(battle_id, unit_id, U_PROPOSED_Z, bz);
        // The level rides with the pair it aliases (ADR-0224 dec. 4) — the reset
        // above skips the walking states and this unit has just stopped being one.
        write_unit(battle_id, unit_id, U_PROPOSED_LEVEL, read_unit(battle_id, unit_id, U_LEVEL));
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_TURN_PENDING);
        return;
    }

    // THE SETTLE BRAKE (config.turn_brake_battle's twin, config.settle_brake_battle).
    // In a battle that settles before it declares a winner, a unit whose step has
    // just drained starts NOTHING new: it settles into IDLE, where the victory flip
    // above catches it on the very next tick.
    //
    // 🔴 IT IS NOT THE TURN BRAKE AND CANNOT REUSE IT. That one is gated on
    // `U_TURN_METER >= TURN_METER_FULL`, so only a READY unit brakes -- quiescence
    // needs everyone, and the units that snap are exactly the ones still walking off
    // a meter they already spent.
    //
    // WITHOUT IT THE EXEMPTION ABOVE HANGS, and #897's own note is the proof: a unit
    // with a live "attack the nearest enemy" gambit and no living enemy re-enters
    // WALKING toward a target that no longer resolves, and its timer restarts every
    // tick. The flip is what used to cut that loop short. Take the flip away for a
    // walker and the loop comes back — so the brake has to take its place. The
    // exemption is what makes the picture right and the brake is what makes it
    // TERMINATE. They ship together or neither works.
    //
    // 🔴 SAME HAZARD AS THE TWO CHECKS ABOVE: this sits AFTER the per-tick clears.
    // Returning above `U_PENDING_ACTION_TYPE = ACTION_NONE` would leave last tick's
    // ACTION_PATHFIND_MOVE standing and `stage_pathfind` would write WALKING straight
    // back over the IDLE this sets, every tick, invisibly.
    //
    // The U_TIMER countdown above is untouched, exactly as the turn brake leaves it:
    // the unit FINISHES the step it is on -- which is what leaves the sprite on its
    // logical tile, `GPUMovementVisualizer.calculate_position(0)` returning `end_pos`
    // on both the linear and cliff paths -- and simply never starts another.
    //
    // Scoped to the three EXEMPTED states that can start something -- and to no
    // others. IDLE is absent where the turn brake lists it, because here IDLE is
    // unreachable: it is not settle-awaited, so the flip above has already caught it
    // and returned. ACTING is absent too, even though it IS settle-awaited: an acting
    // unit is mid-animation, not choosing, and its own dispatch below drains it into
    // IDLE where the flip catches it next tick. Same for SPELL_CHARGING /
    // AWAITING_IMPACT / PREEMPTIVE_COUNTER / DYING.
    if (config.settle_brake_battle == battle_id
            && (state == LOGICAL_ACTIVITY_WALKING
                || state == LOGICAL_ACTIVITY_WALKING_TO_CAST
                || state == LOGICAL_ACTIVITY_APPROACHING
                || state == LOGICAL_ACTIVITY_RETREATING)
            && is_enemy_team_dead(battle_id, unit_id)) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        int sx = read_unit(battle_id, unit_id, U_POS_X);
        int sz = read_unit(battle_id, unit_id, U_POS_Z);
        write_unit(battle_id, unit_id, U_PROPOSED_X, sx);
        write_unit(battle_id, unit_id, U_PROPOSED_Z, sz);
        // The level rides with the pair it aliases (ADR-0224 dec. 4) -- the reset
        // above skips the walking states and this unit has just stopped being one.
        write_unit(battle_id, unit_id, U_PROPOSED_LEVEL, read_unit(battle_id, unit_id, U_LEVEL));
        return;
    }

    // Re-evaluate gambits for movement states -only check HIGHER-PRIORITY
    // (lower-numbered) slots than the currently executing gambit.  This prevents
    // the same gambit from re-triggering start_spell every tick (which would
    // set MOVING_TO_CAST + timer=0 in a tight loop, freezing the unit).
    if (state == LOGICAL_ACTIVITY_WALKING || state == LOGICAL_ACTIVITY_WALKING_TO_CAST || state == LOGICAL_ACTIVITY_APPROACHING) {
        int current_gambit = read_unit(battle_id, unit_id, U_CURRENT_GAMBIT);
        if (current_gambit > 0 && evaluate_gambits_up_to(battle_id, unit_id, current_gambit)) {
            apply_pending_action(battle_id, unit_id);
            return;  // Higher-priority gambit took over
        }
    }

    if (state == LOGICAL_ACTIVITY_WALKING) {
        // Defer to stage_pathfind — it owns handle_moving_state().
        write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_PATHFIND_MOVE);
        return;
    }

    if (state == LOGICAL_ACTIVITY_APPROACHING) {
        // Continue the unit-anchored reposition (ADR-0024). Re-runs the same
        // ACTION_MOVE_TO_UNIT body, which re-reads the target's live position;
        // stage_pathfind owns execute_move_to_unit_gambit().
        write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_MOVE_TO_UNIT);
        return;
    }

    // THE RETREAT IS OVER THE MOMENT ITS TILE IS PAID FOR (ADR-0301), AND THE
    // ABSENCE OF A `return` HERE IS THE DIFFERENCE FROM THE TWO BLOCKS ABOVE.
    // WALKING and APPROACHING re-arm their action and hand the tick to
    // stage_pathfind, which is what makes them a committed path; a retreat commits
    // nothing. It drops to IDLE and FALLS THROUGH to the gambit walk at the bottom
    // of this function, in this same tick, so the next tile is a fresh decision by
    // the full list -- including the slots BELOW the retreat, which is how a unit
    // that has opened enough distance stops fleeing and turns to fight.
    //
    // That is also why #1103's Q4 ("what stops a retreat loop?") has no mechanism
    // here: there is no multi-tile flee to bound. The gambit's own condition holds
    // or releases it, one tile at a time.
    //
    // 🔴 WHAT THIS BLOCK IS ACTUALLY FOR IS THE WRITE-BACK, NOT THE FALL-THROUGH,
    // AND THAT IS MEASURED RATHER THAN ARGUED. Delete the whole block and the unit
    // still re-decides correctly: RETREATING matches none of the `state ==` tests
    // below, so it reaches the evaluation at the bottom either way, and
    // GPURetreatStepTest's arms 1-4 all stay GREEN. What is lost is U_STATE ever
    // being written back -- so a unit whose retreat stops firing and whose next
    // slot writes no state of its own (`evaluate_gambits` returning false is the
    // reachable case) keeps wearing RETREATING for the rest of the battle: the
    // sprite walks in place, and `settle_awaited_state` keeps the settle brake
    // waiting on a unit that has stopped. That is the #897 hazard class, arm 5 is
    // the guard, and the block is the fix.
    //
    // Reassigning the LOCAL `state` is what skips the state blocks below -- every
    // one of them is a `state ==` test, so an IDLE local walks past all of them
    // into the evaluation. The buffer write is the one the next tick reads.
    if (state == LOGICAL_ACTIVITY_RETREATING) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_ARRIVED);
        state = LOGICAL_ACTIVITY_IDLE;
    }

    if (state == LOGICAL_ACTIVITY_ACTING) {
        // Per ADR-0032: if damage hasn't fired yet (projectile still in flight),
        // transition to LOGICAL_ACTIVITY_AWAITING_IMPACT so the firer's SEQ can end while
        // the bullet finishes its crossing. damage_frame > anim_frame means the
        // damage-frame crossing hasn't happened inside tick_acting_animation.
        // U_TIMER is repurposed: count flight ticks until landing.
        int anim_flags = read_unit(battle_id, unit_id, U_ANIM_FLAGS);
        bool damage_pending = (anim_flags & 1) == 0;
        int damage_frame = read_unit(battle_id, unit_id, U_DAMAGE_FRAME);
        int anim_frame = read_unit(battle_id, unit_id, U_ANIM_FRAME);
        if (damage_pending && damage_frame > anim_frame) {
            int flight_remaining = damage_frame - anim_frame;
            write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_AWAITING_IMPACT);
            write_unit(battle_id, unit_id, U_TIMER, flight_remaining);
            return;
        }
        write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
        write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        // #1107 — the melee / no-flight exit. `consume_attack_recovery` is 0 for
        // every un-levered unit, so this is the pre-#1107 fallthrough unchanged.
        consume_attack_recovery(battle_id, unit_id);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_ATTACK_ENDED);
        return;
    }

    if (state == LOGICAL_ACTIVITY_AWAITING_IMPACT) {
        // Per ADR-0032: timer-zero edge means the projectile has landed. Run
        // apply_attack_damage (same helper called from the in-SEQ damage-frame
        // crossing in tick_acting_animation) and transition to LOGICAL_ACTIVITY_IDLE.
        apply_attack_damage(battle_id, unit_id, tick);
        write_unit(battle_id, unit_id, U_ANIM_FLAGS,
                   read_unit(battle_id, unit_id, U_ANIM_FLAGS) | 1);
        write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
        write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        // #1107 — the ranged exit. Recovery is owed AFTER the flight tail, not
        // instead of it: the tail is time the projectile takes, the recovery is
        // time the firer takes, and a bow already pays both.
        consume_attack_recovery(battle_id, unit_id);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_ATTACK_ENDED);
        return;
    }

    if (state == LOGICAL_ACTIVITY_SPELL_CHARGING) {
        int cast_timer = read_unit(battle_id, unit_id, U_CAST_TIMER);
        if (cast_timer > 0) {
            write_unit(battle_id, unit_id, U_CAST_TIMER, max(0, cast_timer - CHARGE_SEQ_SPEED));
            return;
        }
        // Cast timer expired — defer the spell finalization to stage_spell.
        // stage_spell reads U_PENDING_ACTION_TYPE = ACTION_COMPLETE_SPELL and
        // calls complete_spell_cast() in this same tick.
        write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_COMPLETE_SPELL);
        return;
    }

    if (state == LOGICAL_ACTIVITY_WALKING_TO_CAST) {
        // Defer to stage_pathfind — it owns handle_moving_to_cast_state().
        write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_PATHFIND_CAST);
        return;
    }

    if (state == LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER) {
        int target = read_unit(battle_id, unit_id, U_TARGET);
        if (target >= 0 && !is_unit_dead(battle_id, target) && can_attack_target(battle_id, unit_id, target)) {
            int weapon_type = read_unit(battle_id, unit_id, U_WEAPON_TYPE);
            setup_attack_animation(battle_id, unit_id, target, weapon_type);
        } else {
            write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
            write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        }
        return;
    }


    // Tier 2 #8 — stunning statuses: skip gambit eval, recheck later.
    // These cleanly map to "the unit is unable to make decisions this tick"
    // (Sleep / Stop / Petrify / Disable). Here we just block the decision.
    // 🔴 This comment used to say the status timer decays these on its own
    // cadence. It does not: `set_status_with_timer` has NO call sites, so a
    // Sleep / Stop / Petrify landed in battle is PERMANENT and removes the unit
    // for good. See docs/status-conformance.md (#1105) finding 1.
    if (has_status(battle_id, unit_id, STATUS_SLEEP)
        || has_status(battle_id, unit_id, STATUS_STOP)
        || has_status(battle_id, unit_id, STATUS_PETRIFY)
        || has_status(battle_id, unit_id, STATUS_DISABLE)) {
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_NO_GAMBIT);
        return;
    }

    // Tier 2 #8 — Berserk: ignore the gambit list, force an ATTACK on the
    // nearest reachable enemy. stage_attack runs immediately after and
    // handles the swing (or kicks off a move-toward-target if out of range)
    // via execute_attack_gambit. If no enemy is reachable, fall through to
    // the regular idle/retry path.
    if (has_status(battle_id, unit_id, STATUS_BERSERK)) {
        int berserk_target = find_nearest_enemy(battle_id, unit_id);
        if (berserk_target >= 0) {
            write_unit(battle_id, unit_id, U_PENDING_ACTION_TYPE, ACTION_ATTACK);
            write_unit(battle_id, unit_id, U_TARGET, berserk_target);
            write_unit(battle_id, unit_id, U_CURRENT_GAMBIT, -1);
            write_unit(battle_id, unit_id, U_PREV_MOVE_POS, -1);
            return;
        }
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_NO_GAMBIT);
        return;
    }

    // LOGICAL_ACTIVITY_IDLE - evaluate gambits, retry after delay if none triggers
    if (!evaluate_gambits(battle_id, unit_id)) {
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_NO_GAMBIT);
        int target = read_unit(battle_id, unit_id, U_TARGET);
        record_decision(battle_id, unit_id, REASON_NO_GAMBIT, LOGICAL_ACTIVITY_IDLE, target);
    } else {
        apply_pending_action(battle_id, unit_id);
    }
}

#endif // PASS_COMPUTE -state machine

void main() {
    uint global_id = gl_GlobalInvocationID.x;
    int battle_id = int(global_id / uint(config.units_per_battle));
    int unit_id = int(global_id % uint(config.units_per_battle));

    if (battle_id >= config.num_battles) return;

    int result = get_battle_result(battle_id);
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    int tick = get_battle_tick(battle_id);
    compute_unit_state(battle_id, unit_id, tick);
    // Thrash detection runs once per tick, after state machine dispatch.
    if (!is_unit_dead(battle_id, unit_id)) {
        check_decision_thrash(battle_id, unit_id);
    }
}
