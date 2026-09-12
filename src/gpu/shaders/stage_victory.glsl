#[compute]
#version 450

// =============================================================================
// stage_victory.glsl — PASS_VICTORY: detect end-of-battle, write results
//
// One thread per battle. Counts surviving units per team in the NEXT buffer:
//   - both teams dead → DRAW
//   - team 1 wiped AND all team-0 survivors are LOGICAL_ACTIVITY_CELEBRATING → team 0 wins
//   - team 0 wiped AND all team-1 survivors are LOGICAL_ACTIVITY_CELEBRATING → team 1 wins
// Also advances the battle tick, hits MAX_TICKS → DRAW, and writes the
// per-battle RESULT RECORD (combat_common.glslinc's `R_*` / `RESULT_SIZE`):
// the verdict, the tick, and #896's value-function features.
//
// Dispatch: ceil(num_battles / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"

int check_victory(int battle_id) {
    int team0_alive = 0;
    int team1_alive = 0;
    int team0_victorious = 0;
    int team1_victorious = 0;

    for (int u = 0; u < config.units_per_battle; u++) {
        int flags = read_unit_next(battle_id, u, U_FLAGS);
        bool dead = (flags & FLAG_DEAD) != 0;
        // Issue #107: same Reraise-pending carve-out as is_enemy_team_dead.
        // A FLAG_DEAD + STATUS_RERAISE carrier counts as alive for victory
        // tallies until Stage B clears the bit at cinematic teardown.
        bool revive_pending = dead && has_status_next(battle_id, u, STATUS_RERAISE);
        if (dead && !revive_pending) continue;

        int team = read_unit_next(battle_id, u, U_TEAM);
        int unit_state = read_unit_next(battle_id, u, U_STATE);
        if (team == 0) {
            team0_alive++;
            if (unit_state == LOGICAL_ACTIVITY_CELEBRATING) team0_victorious++;
        } else {
            team1_alive++;
            if (unit_state == LOGICAL_ACTIVITY_CELEBRATING) team1_victorious++;
        }
    }

    if (team0_alive == 0 && team1_alive == 0) return RESULT_DRAW;
    // Only report win when all survivors are celebrating.
    if (team1_alive == 0 && team0_alive == team0_victorious) return RESULT_TEAM_0_WINS;
    if (team0_alive == 0 && team1_alive == team1_victorious) return RESULT_TEAM_1_WINS;
    return RESULT_ONGOING;
}

// The value function's feature vector (#896), written into the same per-battle
// record `read_all_results` already reads in bulk. ADR-0237 dec. 7 is why it
// lives here and not in a CPU-side reader: one `read_unit_column` across 1024
// battles costs as much as running an entire 300-tick horizon, for ONE feature,
// while the whole result buffer reads in 0.11 ms. This record is write-only from
// the shader's side, so every field below touches no combat rule.
//
// ALIVE here is `!FLAG_DEAD` -- deliberately NOT `check_victory`'s tally, which
// keeps a Reraise-pending carrier standing (issue #107). Such a unit adds 0 to
// the HP sums, so counting it alive would put a standing count and an HP total
// that contradict each other into one record.
void write_feature_record(int battle_id, int out_offset) {
    int team0_hp = 0;
    int team1_hp = 0;
    int team0_alive = 0;
    int team1_alive = 0;
    int team0_mp = 0;
    int team1_mp = 0;
    int team0_max_hp = 0;
    int team1_max_hp = 0;
    int team0_max_mp = 0;
    int team1_max_mp = 0;
    // Position sums over LIVING units, for the engagement centroids below.
    int team0_x = 0, team0_z = 0, team1_x = 0, team1_z = 0;

    for (int u = 0; u < config.units_per_battle; u++) {
        int team = read_unit_next(battle_id, u, U_TEAM);
        int max_hp = read_unit_next(battle_id, u, U_MAX_HP);
        int max_mp = read_unit_next(battle_id, u, U_MAX_MP);
        // The MAX-HP and MAX-MP denominators count EVERY slot, dead included --
        // see the record's declaration in combat_common.glslinc. An empty
        // padding slot carries 0 for both and so contributes nothing on its own.
        if (team == 0) {
            team0_max_hp += max_hp;
            team0_max_mp += max_mp;
        } else {
            team1_max_hp += max_hp;
            team1_max_mp += max_mp;
        }

        int flags = read_unit_next(battle_id, u, U_FLAGS);
        if ((flags & FLAG_DEAD) != 0) continue;

        int hp = read_unit_next(battle_id, u, U_HP);
        int mp = read_unit_next(battle_id, u, U_MP);
        int px = read_unit_next(battle_id, u, U_POS_X);
        int pz = read_unit_next(battle_id, u, U_POS_Z);
        if (team == 0) {
            team0_hp += hp;
            team0_mp += mp;
            team0_alive++;
            team0_x += px;
            team0_z += pz;
        } else {
            team1_hp += hp;
            team1_mp += mp;
            team1_alive++;
            team1_x += px;
            team1_z += pz;
        }
    }

    // ENGAGEMENT: how far each living unit stands from the CENTROID of the
    // living enemy team, summed PER TEAM so the pair mirrors when the value
    // function swaps perspective. R_TEAM*_ALIVE are the denominators.
    //
    // 🔴 THE CENTROID IS A COST DECISION, AND IT WAS MEASURED. The feature this
    // wants to be is distance to the NEAREST living enemy, which is strictly
    // more informative. That is an O(U^2) scan, and this function runs once per
    // battle per TICK — in the live game as well as in a rollout fleet. Benched
    // against ADR-0237's table at H=300 it cost 1.9x the run leg at U=16 fleet
    // 256 (56.3 -> 105.0 ms) and 2.2x at U=32 (209.4 -> 455.2 ms), against a
    // documented repeat spread of ~7%. ADR-0237 dec. 5 sizes the shipping beat
    // at 64.7 ms; doubling its run leg to buy one feature is not a trade the
    // budget can pay. The centroid is O(U), folds its first pass into the loop
    // above, and costs one extra distance per living unit.
    //
    // Manhattan on the grid, NOT `get_distance`'s path length, for the same
    // reason: the path distance knows about terrain a walk has to go around,
    // but each step is a scattered read into the distance field. GambitBattle
    // §8's escalation rule says which way to spend if it matters — if the
    // H-sweep shows the linear model cannot separate positions, the distance
    // term is the first thing to sharpen.
    int team0_engage = 0;
    int team1_engage = 0;
    if (team0_alive > 0 && team1_alive > 0) {
        // Rounded integer centroids. A half-tile of rounding is absorbed by the
        // fitted coefficient; what matters is that the same rounding is applied
        // at calibration time and at rollout time, and both read this field.
        int c0x = (team0_x + team0_alive / 2) / team0_alive;
        int c0z = (team0_z + team0_alive / 2) / team0_alive;
        int c1x = (team1_x + team1_alive / 2) / team1_alive;
        int c1z = (team1_z + team1_alive / 2) / team1_alive;

        for (int u = 0; u < config.units_per_battle; u++) {
            int flags = read_unit_next(battle_id, u, U_FLAGS);
            if ((flags & FLAG_DEAD) != 0) continue;
            int team = read_unit_next(battle_id, u, U_TEAM);
            int ux = read_unit_next(battle_id, u, U_POS_X);
            int uz = read_unit_next(battle_id, u, U_POS_Z);
            if (team == 0) {
                team0_engage += manhattan_distance(ux, uz, c1x, c1z);
            } else {
                team1_engage += manhattan_distance(ux, uz, c0x, c0z);
            }
        }
    }
    // With either team wiped out both fields stay 0. A unit with no living enemy
    // has no distance to one, and a sentinel would be a feature value no real
    // position ever produces. A consumer tells the two apart by the standing
    // counts: `R_TEAM1_ALIVE == 0` is "nobody left to measure against", while a
    // nonzero count with a 0 sum is "everyone is standing on the enemy".

    output_results.results[out_offset + R_TEAM0_HP] = team0_hp;
    output_results.results[out_offset + R_TEAM1_HP] = team1_hp;
    output_results.results[out_offset + R_TEAM0_ALIVE] = team0_alive;
    output_results.results[out_offset + R_TEAM1_ALIVE] = team1_alive;
    output_results.results[out_offset + R_TEAM0_MP] = team0_mp;
    output_results.results[out_offset + R_TEAM1_MP] = team1_mp;
    output_results.results[out_offset + R_TEAM0_MAX_HP] = team0_max_hp;
    output_results.results[out_offset + R_TEAM1_MAX_HP] = team1_max_hp;
    output_results.results[out_offset + R_TEAM0_ENGAGE] = team0_engage;
    output_results.results[out_offset + R_TEAM1_ENGAGE] = team1_engage;
    output_results.results[out_offset + R_TEAM0_MAX_MP] = team0_max_mp;
    output_results.results[out_offset + R_TEAM1_MAX_MP] = team1_max_mp;
}


void do_check_victory(int battle_id, int tick) {
    int result = check_victory(battle_id);

    write_battle_header(battle_id, BH_TICK, tick + 1);

    if (result == RESULT_ONGOING && tick + 1 >= MAX_TICKS) {
        result = RESULT_DRAW;
    }

    write_battle_header(battle_id, BH_RESULT, result);

    int out_offset = battle_id * RESULT_SIZE;
    output_results.results[out_offset + R_RESULT] = result;
    output_results.results[out_offset + R_TICKS] = tick + 1;

    write_feature_record(battle_id, out_offset);
}

void main() {
    uint battle_id = gl_GlobalInvocationID.x;
    if (battle_id >= uint(config.num_battles)) return;

    int result = get_battle_result(int(battle_id));
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    int tick = get_battle_tick(int(battle_id));
    do_check_victory(int(battle_id), tick);
}
