#[compute]
#version 450

// =============================================================================
// stage_post_conflict.glsl — PASS_POST_CONFLICT: opportunistic attacks
//
// One thread per battle. After stage_resolve commits resolved positions, this
// pass checks BLOCKED-moving units (timer == 1) to see if a neighbor is now an
// adjacent enemy — if so, switch them to LOGICAL_ACTIVITY_ACTING and stamp attack
// animation timing. Matches CPU behavior where late-processed units can see
// earlier-processed units' updated positions and attack on the same tick.
//
// Dispatch: ceil(num_battles / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"
#include "res://src/gpu/shaders/combat_combat.glslinc"

void post_conflict_attacks(int battle_id) {
    if (config.movement_only != 0) return;

    for (int u = 0; u < config.units_per_battle; u++) {
        // Read from NEXT buffer (where resolved positions live).
        int flags = read_unit_next(battle_id, u, U_FLAGS);
        if ((flags & FLAG_DEAD) != 0) continue;

        int state = read_unit_next(battle_id, u, U_STATE);
        if (state != LOGICAL_ACTIVITY_WALKING) continue;

        // Only BLOCKED units (timer==1) can re-attack this tick. Units that
        // successfully started moving (timer > 1) must finish movement first.
        int timer = read_unit_next(battle_id, u, U_TIMER);
        if (timer > 1) continue;

        int my_x = read_unit_next(battle_id, u, U_POS_X);
        int my_z = read_unit_next(battle_id, u, U_POS_Z);
        int my_team = read_unit_next(battle_id, u, U_TEAM);

        int best_enemy = -1;
        for (int e = 0; e < config.units_per_battle; e++) {
            if (e == u) continue;

            int e_flags = read_unit_next(battle_id, e, U_FLAGS);
            if ((e_flags & FLAG_DEAD) != 0) continue;

            int e_team = read_unit_next(battle_id, e, U_TEAM);
            if (e_team == my_team) continue;
            // TRANSPARENT filter — blocked-move opportunistic attacks skip the
            // carrier (status_system.md §2). Mirrors the enemy-side filter in
            // find_unit_by_criteria / find_nearest_attackable_enemy.
            if (has_status_next(battle_id, e, STATUS_TRANSPARENT)) continue;

            int e_x = read_unit_next(battle_id, e, U_POS_X);
            int e_z = read_unit_next(battle_id, e, U_POS_Z);

            if (abs(e_x - my_x) + abs(e_z - my_z) == 1) {
                best_enemy = e;
                break;
            }
        }

        if (best_enemy >= 0 && can_attack_target(battle_id, u, best_enemy)) {
            int weapon_type = read_unit(battle_id, u, U_WEAPON_TYPE);
            write_unit(battle_id, u, U_TARGET, best_enemy);
            setup_attack_animation(battle_id, u, best_enemy, weapon_type);
            write_unit(battle_id, u, U_DBG_STATE_REASON, REASON_CAN_ATTACK);
        }
    }
}

void main() {
    uint battle_id = gl_GlobalInvocationID.x;
    if (battle_id >= uint(config.num_battles)) return;

    int result = get_battle_result(int(battle_id));
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    post_conflict_attacks(int(battle_id));
}
