#[compute]
#version 450

// =============================================================================
// stage_resolve.glsl — PASS_RESOLVE: movement-conflict resolution
//
// One thread per battle. After stage_compute writes each unit's proposed move
// to U_PROPOSED_X/Z/LEVEL, this pass walks the units of each battle and resolves
// conflicts deterministically: closer-to-target wins, ties broken by lower
// unit ID. Blocked units revert their proposed position and re-evaluate next
// tick; accepted moves commit U_POS_X/Z and U_LEVEL immediately.
//
// 🔴 THIS IS THE COMMIT SITE, so it is where a level actually MOVES (ADR-0224
// dec. 5). Every comparison below is a CELL comparison, not a column one: two
// units proposing the same (x, z) at different levels are not in conflict, and a
// unit standing under a bridge does not block one stepping onto the deck. That
// is dec. 6's occupancy rule applied to the one place occupancy is enforced.
//
// Dispatch: ceil(num_battles / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"

void resolve_conflicts(int battle_id) {
    // Lower unit ID wins ties (deterministic).
    for (int u = 0; u < config.units_per_battle; u++) {
        if (is_unit_dead(battle_id, u)) continue;

        int proposed_x = read_unit_next(battle_id, u, U_PROPOSED_X);
        int proposed_z = read_unit_next(battle_id, u, U_PROPOSED_Z);
        int proposed_level = read_unit_next(battle_id, u, U_PROPOSED_LEVEL);
        int current_x = read_unit(battle_id, u, U_POS_X);
        int current_z = read_unit(battle_id, u, U_POS_Z);
        int current_level = read_unit(battle_id, u, U_LEVEL);

        // If not moving, skip.
        if (proposed_x == current_x && proposed_z == current_z
                && proposed_level == current_level) {
            write_unit(battle_id, u, U_POS_X, current_x);
            write_unit(battle_id, u, U_POS_Z, current_z);
            write_unit(battle_id, u, U_LEVEL, current_level);
            continue;
        }

        bool blocked = false;
        int blocker_id = -1;
        int my_dist = manhattan_distance(current_x, current_z, proposed_x, proposed_z);

        // Closer unit wins; on tie lower ID wins.
        for (int other = 0; other < config.units_per_battle; other++) {
            if (other == u) continue;
            if (is_unit_dead(battle_id, other)) continue;

            int other_proposed_x = read_unit_next(battle_id, other, U_PROPOSED_X);
            int other_proposed_z = read_unit_next(battle_id, other, U_PROPOSED_Z);
            int other_proposed_level = read_unit_next(battle_id, other, U_PROPOSED_LEVEL);

            if (other_proposed_x == proposed_x && other_proposed_z == proposed_z
                    && other_proposed_level == proposed_level) {
                int other_current_x = read_unit(battle_id, other, U_POS_X);
                int other_current_z = read_unit(battle_id, other, U_POS_Z);
                int other_dist = manhattan_distance(other_current_x, other_current_z, proposed_x, proposed_z);

                if (other_dist < my_dist) {
                    blocked = true;
                    blocker_id = other;
                    break;
                }
                if (other_dist == my_dist && other < u) {
                    blocked = true;
                    blocker_id = other;
                    break;
                }
            }
        }

        // Stationary occupant of our target tile also blocks.
        if (!blocked) {
            for (int other = 0; other < config.units_per_battle; other++) {
                if (other == u) continue;
                if (is_unit_dead(battle_id, other)) continue;

                int other_x = read_unit(battle_id, other, U_POS_X);
                int other_z = read_unit(battle_id, other, U_POS_Z);
                int other_level = read_unit(battle_id, other, U_LEVEL);
                int other_proposed_x = read_unit_next(battle_id, other, U_PROPOSED_X);
                int other_proposed_z = read_unit_next(battle_id, other, U_PROPOSED_Z);
                int other_proposed_level = read_unit_next(battle_id, other, U_PROPOSED_LEVEL);

                if (other_x == proposed_x && other_z == proposed_z && other_level == proposed_level &&
                    other_proposed_x == other_x && other_proposed_z == other_z &&
                    other_proposed_level == other_level) {
                    blocked = true;
                    blocker_id = other;
                    break;
                }
            }
        }

        if (blocked) {
            write_unit(battle_id, u, U_PROPOSED_X, current_x);
            write_unit(battle_id, u, U_PROPOSED_Z, current_z);
            write_unit(battle_id, u, U_PROPOSED_LEVEL, current_level);
            write_unit(battle_id, u, U_POS_X, current_x);
            write_unit(battle_id, u, U_POS_Z, current_z);
            write_unit(battle_id, u, U_LEVEL, current_level);
            // Retry every frame for fastest re-routing.
            write_unit(battle_id, u, U_TIMER, 1);
            write_unit(battle_id, u, U_DBG_CONFLICT_BLOCKED, 1);
            write_unit(battle_id, u, U_DBG_CONFLICT_BLOCKER, blocker_id);
            write_unit(battle_id, u, U_DBG_PROPOSED_ACCEPTED, 0);
            write_unit(battle_id, u, U_DBG_STATE_REASON, REASON_CONFLICT_BLOCKED);
        } else {
            // CPU updates position at START of movement, not END.
            write_unit(battle_id, u, U_POS_X, proposed_x);
            write_unit(battle_id, u, U_POS_Z, proposed_z);
            write_unit(battle_id, u, U_LEVEL, proposed_level);
            write_unit(battle_id, u, U_DBG_PROPOSED_ACCEPTED, 1);
        }
    }
}

void main() {
    uint battle_id = gl_GlobalInvocationID.x;
    if (battle_id >= uint(config.num_battles)) return;

    int result = get_battle_result(int(battle_id));
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    resolve_conflicts(int(battle_id));
}
