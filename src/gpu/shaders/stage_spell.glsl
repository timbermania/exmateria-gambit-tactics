#[compute]
#version 450

// =============================================================================
// stage_spell.glsl — PASS_SPELL: execute spell/ability/item pending actions
//
// One thread per unit. Runs immediately after stage_attack. Reads
// U_PENDING_ACTION_TYPE from NEXT (set by stage_compute's
// record_action_carriers, or by stage_compute's LOGICAL_ACTIVITY_SPELL_CHARGING handler
// when the cast timer hits 0). Dispatches:
//
//   ACTION_SPELL / ACTION_ABILITY / ACTION_ITEM (with valid target) →
//                  start_spell() — MP / LOS / find_cast_position → charge
//                  or transition to LOGICAL_ACTIVITY_WALKING_TO_CAST
//   ACTION_COMPLETE_SPELL → complete_spell_cast() — LOGICAL_ACTIVITY_SPELL_CHARGING
//                  finished, route to projectile / adjacent-item / instant
//
// Every other pending value short-circuits.
//
// Stage 2b Phase 4 — second of four sub-stage extractions. The
// pathfinding helpers below (trace_stitched_path / scan_adjacent_moves /
// find_cast_position / get_next_step / write_movement_step) are
// duplicated from stage_compute and will be promoted to stage_pathfind
// in Phase 5; the copies here then #include from there.
//
// Dispatch: ceil(num_battles * units_per_battle / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"
#include "res://src/gpu/shaders/combat_combat.glslinc"

// -----------------------------------------------------------------------------
// DUPLICATED PATHFINDING HELPERS — verbatim copies from stage_compute.glsl.
// Source of truth stays in stage_compute until Phase 5 lifts them into
// stage_pathfind.glsl. Keep in sync with stage_compute.glsl until then.
// -----------------------------------------------------------------------------

// The greedy DFS over the precomputed field, now over CELLS (ADR-0224 dec. 5).
//
// ⚠️ `visited` IS 512 BITS, NOT 256. It is a bitset over node ids, and a node id
// is `level * total_tiles + z * width + x`, so two planes need twice the bits.
// MAP125 is 16x16 = exactly 256 columns, which filled the old `visited[8]` to
// its last bit -- there was no slack to grow into. ADR-0224 dec. 1 names this as
// the one place the widening is genuinely not free, and P7 names the ~40 ints of
// added private storage (this plus `stack_l`) as the suspect if
// `GPUPerfBenchmark` regresses.
//
// The bounds guard below is not decorative: a map with more than 256 columns
// would index past `visited` entirely, and the pre-ADR-0224 code had the same
// exposure with half the room. ADR-0224's Consequences keep the bounds checks
// for exactly this reason -- a wider index space needs them more, not less.
int trace_stitched_path(int battle_id, int unit_id,
                        int from_x, int from_z, int from_level,
                        int to_x, int to_z, int to_level, int target_id) {
    if (from_x == to_x && from_z == to_z && from_level == to_level) return 0;

    int visited[PATH_VISITED_INTS];
    for (int i = 0; i < PATH_VISITED_INTS; i++) visited[i] = 0;

    int stack_x[32];
    int stack_z[32];
    int stack_l[32];
    int top = 0;
    int backtracks = 0;
    int jump = read_unit(battle_id, unit_id, U_JUMP);
    int map_w = config.map_width;
    int map_h = config.map_height;

    stack_x[0] = from_x;
    stack_z[0] = from_z;
    stack_l[0] = from_level;
    int start_idx = map_node_index(from_x, from_z, from_level);
    if (start_idx < 0 || start_idx >= PATH_VISITED_BITS) return -1;
    visited[start_idx / 32] |= (1 << (start_idx % 32));

    ivec2 dirs[4] = ivec2[4](
        ivec2(0,1), ivec2(1,0), ivec2(0,-1), ivec2(-1,0));

    int max_steps = map_w * map_h * MAP_LEVEL_COUNT;
    for (int iter = 0; iter < max_steps; iter++) {
        if (top < 0) return -1;

        int cx = stack_x[top];
        int cz = stack_z[top];
        int cl = stack_l[top];

        int best_nx = -1, best_nz = -1, best_nl = -1;
        int best_dist = MAX_DISTANCE;

        // FOUR COLUMNS x EVERY ADMISSIBLE CELL OF EACH, low to high. ADR-0224
        // dec. 5 adopts ADR-0219 dec. 6 verbatim: the level is never picked,
        // both candidates are offered and the climb gate plus the field resolve
        // it. There is no fifth or sixth move and no in-place level change --
        // a unit under a bridge walks to the ramp like everything else.
        for (int d = 0; d < 4; d++) {
            int nx = cx + dirs[d].x;
            int nz = cz + dirs[d].y;

            if (nx < 0 || nx >= map_w || nz < 0 || nz >= map_h) continue;

            for (int nl = 0; nl < MAP_LEVEL_COUNT; nl++) {
                int idx = map_node_index(nx, nz, nl);
                if (idx < 0 || idx >= PATH_VISITED_BITS) continue;
                if ((visited[idx / 32] & (1 << (idx % 32))) != 0) continue;

                if (!is_tile_traversable(nx, nz, nl)) continue;
                int fh = get_tile_height(cx, cz, cl);
                int th = get_tile_height(nx, nz, nl);
                if (abs(th - fh) > jump) continue;

                int occupant = get_tile_occupant(battle_id, nx, nz, nl, unit_id);
                if (occupant == target_id && target_id >= 0) occupant = -1;
                if (occupant >= 0) continue;

                int dist = get_distance(nx, nz, nl, to_x, to_z, to_level);
                if (dist >= 0 && dist < best_dist) {
                    best_dist = dist;
                    best_nx = nx;
                    best_nz = nz;
                    best_nl = nl;
                }
            }
        }

        if (best_nx >= 0) {
            if (best_nx == to_x && best_nz == to_z && best_nl == to_level) return top + 1;
            if (top < 31) {
                top++;
                stack_x[top] = best_nx;
                stack_z[top] = best_nz;
                stack_l[top] = best_nl;
                int idx = map_node_index(best_nx, best_nz, best_nl);
                visited[idx / 32] |= (1 << (idx % 32));
            } else {
                return -1;
            }
        } else {
            top--;
            backtracks++;
            if (backtracks > MAX_BACKTRACKS) return -1;
        }
    }
    return -1;
}

// ⚠️ A STRAIGHT-LINE WALK CANNOT BRANCH, so this is the one place dec. 5's "offer
// both and let the search resolve it" has no search to hand the choice to. It
// takes the first admissible cell of each column in dec. 5's own enqueue order,
// low to high -- the same order `EventPathfinder` floods `cells_at` in and the
// same order `DistanceFieldGenerator._compute_neighbors` appends in. Picking by
// smallest height delta instead would read as more physical and would be a rule
// no decision states.
//
// Returns `ivec3(x, z, level)`; `.x < 0` is the failure value, as before.
ivec3 find_passthrough_destination(int battle_id, int unit_id, int start_x, int start_z, int start_level, int dir_x, int dir_z) {
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    int jump = read_unit(battle_id, unit_id, U_JUMP);
    int prev_h = get_tile_height(start_x, start_z, start_level);

    int x = start_x + dir_x;
    int z = start_z + dir_z;

    for (int i = 0; i < PASSTHROUGH_MAX_TILES; i++) {
        // `walkable_step_cell` (combat_common) IS the loop that used to stand here,
        // verbatim -- first admissible cell of the column, low to high, gated
        // against the height being stepped from. It moved so that `get_move_ticks`
        // can price this same line by the same rule; the comment above is its rule
        // and it is written out in full at the definition.
        ivec2 step = walkable_step_cell(x, z, prev_h, jump);
        if (step.x < 0) {
            return ivec3(-1, -1, -1);
        }
        int step_level = step.x;
        prev_h = step.y;

        int occupant = get_tile_occupant(battle_id, x, z, step_level, unit_id);
        if (occupant < 0) {
            return ivec3(x, z, step_level);
        }

        int occupant_team = read_unit(battle_id, occupant, U_TEAM);
        if (occupant_team != my_team) {
            return ivec3(-1, -1, -1);
        }

        x += dir_x;
        z += dir_z;
    }

    return ivec3(-1, -1, -1);
}

// THE MOVER EXPANDS 4 x 2 AND TAKES THE MINIMUM `get_distance` (ADR-0224 dec. 5).
//
// Four column-to-column neighbours, every admissible cell of each, low to high;
// the climb gate rejects the rest and the field decides which survivor is
// closest. That is ADR-0219 dec. 6's candidate set, adopted rather than
// restated -- `EventPathfinder` floods `nav.cells_at(x, z)` and this enumerates
// the same two cells, so the two movers cannot come to disagree about MAP009's
// bridge (ADR-0224 P6).
//
// `best` and `fallback` are `ivec3(x, z, level)`.
void scan_adjacent_moves(int battle_id, int unit_id, int from_x, int from_z, int from_level,
                          int to_x, int to_z, int to_level, int target_id,
                          int current_dist, int jump, int my_team,
                          int prev_x, int prev_z,
                          out ivec3 best, out ivec3 fallback,
                          out int best_dist, out int fallback_dist,
                          out bool found_any_valid) {
    best = ivec3(from_x, from_z, from_level);
    fallback = ivec3(from_x, from_z, from_level);
    best_dist = current_dist;
    fallback_dist = MAX_DISTANCE;
    found_any_valid = false;

    ivec2 dirs[4] = ivec2[4](
        ivec2(0, 1), ivec2(1, 0), ivec2(0, -1), ivec2(-1, 0)
    );

    for (int d = 0; d < 4; d++) {
        int nx = from_x + dirs[d].x;
        int nz = from_z + dirs[d].y;

        for (int nl = 0; nl < MAP_LEVEL_COUNT; nl++) {
            if (!is_tile_traversable(nx, nz, nl)) continue;

            int from_h = get_tile_height(from_x, from_z, from_level);
            int to_h = get_tile_height(nx, nz, nl);
            if (abs(to_h - from_h) > jump) continue;

            int occupant = get_tile_occupant(battle_id, nx, nz, nl, unit_id);
            if (occupant == target_id) occupant = -1;

            if (occupant < 0) {
                // The anti-oscillation memory is a COLUMN, not a cell, and
                // `U_PREV_MOVE_POS` keeps its two-field packing. A unit cannot
                // change level in place (dec. 5), so the two cells of one column
                // are never both reachable in one step and there is no
                // level-flavoured oscillation for a third field to catch.
                if (nx == prev_x && nz == prev_z && !(nx == to_x && nz == to_z)) continue;
                int dist = get_distance(nx, nz, nl, to_x, to_z, to_level);
                if (dist >= 0) {
                    found_any_valid = true;
                    if (dist < best_dist) {
                        best_dist = dist;
                        best = ivec3(nx, nz, nl);
                    }
                    if (dist < fallback_dist) {
                        fallback_dist = dist;
                        fallback = ivec3(nx, nz, nl);
                    }
                }
            } else {
                int occupant_team = read_unit(battle_id, occupant, U_TEAM);
                if (occupant_team == my_team) {
                    ivec3 passthrough_dest = find_passthrough_destination(
                        battle_id, unit_id, from_x, from_z, from_level, dirs[d].x, dirs[d].y
                    );
                    if (passthrough_dest.x >= 0) {
                        int dist = get_distance(passthrough_dest.x, passthrough_dest.y,
                                                passthrough_dest.z, to_x, to_z, to_level);
                        if (dist >= 0) {
                            found_any_valid = true;
                            if (dist < best_dist) {
                                best_dist = dist;
                                best = passthrough_dest;
                            }
                            if (dist < fallback_dist) {
                                fallback_dist = dist;
                                fallback = passthrough_dest;
                            }
                        }
                    }
                }
            }
        }
    }
}

ivec3 get_next_step(int battle_id, int unit_id, int from_x, int from_z, int from_level,
                    int to_x, int to_z, int to_level, int target_id) {
    if (from_x == to_x && from_z == to_z && from_level == to_level) {
        return ivec3(from_x, from_z, from_level);
    }

    int current_dist = get_distance(from_x, from_z, from_level, to_x, to_z, to_level);
    int jump = read_unit(battle_id, unit_id, U_JUMP);
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    int prev_packed = read_unit(battle_id, unit_id, U_PREV_MOVE_POS);
    int prev_x = (prev_packed >> 16) & 0xFFFF;
    int prev_z = prev_packed & 0xFFFF;

    ivec3 best, fallback;
    int best_dist, fallback_dist;
    bool found_any_valid;
    scan_adjacent_moves(battle_id, unit_id, from_x, from_z, from_level,
                         to_x, to_z, to_level, target_id,
                         current_dist, jump, my_team, prev_x, prev_z,
                         best, fallback, best_dist, fallback_dist, found_any_valid);

    if (best.x == from_x && best.y == from_z && best.z == from_level && found_any_valid) {
        best = fallback;
        best_dist = fallback_dist;
    }

    if (config.test_mode != 0) {
        // `U_DBG_NEXT_X/Z` gain no level field -- ADR-0224 dec. 4 keeps the debug
        // pair as it is because it is debug output, not state.
        write_unit(battle_id, unit_id, U_DBG_BEST_DIST, best_dist);
        write_unit(battle_id, unit_id, U_DBG_NEXT_X, best.x);
        write_unit(battle_id, unit_id, U_DBG_NEXT_Z, best.y);
    }

    return best;
}

// Casting stances are CELLS now: a column inside the spell's range offers up to
// two of them and both are candidates, ranked by the same field. Returns
// `ivec3(x, z, level)` with `.x < 0` for "nowhere to stand", as before.
ivec3 find_cast_position(int battle_id, int unit_id,
                         int tx, int tz, int spell_range,
                         int target_height, int vert_tolerance) {
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);

    ivec3 top_pos[3];
    int top_dist[3];
    for (int i = 0; i < REACHABILITY_CANDIDATES; i++) {
        top_pos[i] = ivec3(-1, -1, -1);
        top_dist[i] = MAX_DISTANCE;
    }

    int x_min = max(0, tx - spell_range);
    int x_max = min(config.map_width - 1, tx + spell_range);
    int z_min = max(0, tz - spell_range);
    int z_max = min(config.map_height - 1, tz + spell_range);

    for (int cx = x_min; cx <= x_max; cx++) {
        for (int cz = z_min; cz <= z_max; cz++) {
            if (manhattan_distance(cx, cz, tx, tz) > spell_range) continue;

            for (int cl = 0; cl < MAP_LEVEL_COUNT; cl++) {
                if (!is_tile_traversable(cx, cz, cl)) continue;
                if (is_tile_occupied(battle_id, cx, cz, cl, unit_id)) continue;

                int h = get_tile_height(cx, cz, cl);
                if (abs(h - target_height) > vert_tolerance) continue;

                int d = get_distance(my_x, my_z, my_level, cx, cz, cl);
                if (d < 0) continue;

                for (int i = 0; i < REACHABILITY_CANDIDATES; i++) {
                    if (d < top_dist[i]) {
                        for (int j = REACHABILITY_CANDIDATES - 1; j > i; j--) {
                            top_pos[j] = top_pos[j - 1];
                            top_dist[j] = top_dist[j - 1];
                        }
                        top_pos[i] = ivec3(cx, cz, cl);
                        top_dist[i] = d;
                        break;
                    }
                }
            }
        }
    }

    for (int i = 0; i < REACHABILITY_CANDIDATES; i++) {
        if (top_pos[i].x < 0) break;
        int path = trace_stitched_path(battle_id, unit_id,
            my_x, my_z, my_level, top_pos[i].x, top_pos[i].y, top_pos[i].z, -1);
        if (path >= 0) return top_pos[i];
    }
    return ivec3(-1, -1, -1);
}

// `U_PROPOSED_LEVEL` is written beside `U_PROPOSED_X/Z` (ADR-0224 dec. 4): the
// proposed position is an independent position that persists across ticks and
// can legitimately sit at a different level from the current one, so it carries
// its own level rather than having one derived at read time.
//
// `U_PREV_MOVE_POS` keeps its two-field packing -- see `scan_adjacent_moves` for
// why the oscillation memory is a column and not a cell.
void write_movement_step(int battle_id, int unit_id,
                         int from_x, int from_z, int from_level,
                         int next_x, int next_z, int next_level) {
    write_unit(battle_id, unit_id, U_PREV_MOVE_POS, (from_x << 16) | from_z);
    write_unit(battle_id, unit_id, U_PROPOSED_X, next_x);
    write_unit(battle_id, unit_id, U_PROPOSED_Z, next_z);
    write_unit(battle_id, unit_id, U_PROPOSED_LEVEL, next_level);
    // The jump is an ARGUMENT because a step can span several tiles: pricing the
    // line needs the cells BETWEEN, and which cell of a two-cell column the unit
    // crossed is a question only its jump answers.
    int move_ticks = get_move_ticks(from_x, from_z, from_level, next_x, next_z, next_level,
                                    read_unit(battle_id, unit_id, U_JUMP));
    if (has_status(battle_id, unit_id, STATUS_HASTE))
        move_ticks = max(1, move_ticks / 2);
    else if (has_status(battle_id, unit_id, STATUS_SLOW))
        move_ticks = move_ticks * 2;
    write_unit(battle_id, unit_id, U_TIMER, move_ticks);
    write_unit(battle_id, unit_id, U_MOVE_TOTAL_TICKS, move_ticks);
    int step_id = read_unit(battle_id, unit_id, U_MOVE_STEP_ID);
    write_unit(battle_id, unit_id, U_MOVE_STEP_ID, step_id + 1);
}

// -----------------------------------------------------------------------------
// SPELL HELPERS — verbatim from stage_compute.glsl, removed there by Phase 4.
// -----------------------------------------------------------------------------

bool is_projectile_ability(int ability_id) {
    if (is_item_ability(ability_id)) return true;
    int effect_anim_id = get_ability_effect_anim_id(ability_id);
    return effect_anim_id == 76;
}

void start_spell(int battle_id, int unit_id, int target_id, int ability_id) {
    int mp_cost = get_ability_mp_cost(ability_id);
    int current_mp = get_mp(battle_id, unit_id);

    if (current_mp < mp_cost) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_SPELL_FAILED);
        return;
    }

    int spell_range = get_effective_ability_range(battle_id, unit_id, ability_id);
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);
    int tx = read_unit(battle_id, target_id, U_POS_X);
    int tz = read_unit(battle_id, target_id, U_POS_Z);
    // ADR-0224 dec. 6 -- the target's level is the target's own.
    int t_level = read_unit(battle_id, target_id, U_LEVEL);
    int ab_flags = get_ability_flags(ability_id);
    int target_height = get_tile_height(tx, tz, t_level);

    // THE GATE IS `ability_in_reach`, shared with `COND_IN_RANGE` (ADR-0268 dec. 11). The
    // range-and-vertical arithmetic used to be spelled out here; the screen now asks the same
    // question, and two copies of it is how the row's readout and the unit's behaviour drift.
    // Behaviour is unchanged: the predicate is the old `distance <= spell_range &&
    // !need_reposition`, with the vertical half gated on the same flag and the same distance.
    if (ability_in_reach(battle_id, unit_id, target_id, ability_id)) {
        if (is_projectile_ability(ability_id)) {
            if (!has_line_of_sight_arc(my_x, my_z, my_level, tx, tz, t_level)) {
                write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, ability_id);
                write_unit(battle_id, unit_id, U_CAST_TARGET, target_id);
                write_unit(battle_id, unit_id, U_DEST_X, tx);
                write_unit(battle_id, unit_id, U_DEST_Z, tz);
                write_unit(battle_id, unit_id, U_DEST_LEVEL, t_level);
                write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_WALKING_TO_CAST);
                ivec3 next_los = get_next_step(battle_id, unit_id, my_x, my_z, my_level,
                                               tx, tz, t_level, target_id);
                if (next_los.x != my_x || next_los.y != my_z || next_los.z != my_level) {
                    write_movement_step(battle_id, unit_id, my_x, my_z, my_level,
                                        next_los.x, next_los.y, next_los.z);
                } else {
                    write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, -1);
                    write_unit(battle_id, unit_id, U_CAST_TARGET, -1);
                    write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
                    write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
                    write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_SPELL_FAILED);
                }
                return;
            }
        }
        spend_mp(battle_id, unit_id, mp_cost);
        write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, ability_id);
        write_unit(battle_id, unit_id, U_CAST_TARGET, target_id);
        write_unit(battle_id, unit_id, U_CAST_TIMER, get_ability_charge_time(ability_id));
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_SPELL_CHARGING);
        set_status(battle_id, unit_id, STATUS_CHARGING);
    } else {
        // 255 == "height does not bound this ability", which is what an ability without the
        // tolerance flag means. Unconditional now: the old two-step (0, then recomputed if
        // still 0) could only ever land on this same value — the first step ran only when the
        // target was already in horizontal range, and then either left the tolerance itself or
        // left 0, which the recompute turned back into the tolerance.
        int vert_tolerance = ((ab_flags & ABFLAG_VERTICAL_TOLERANCE) != 0)
            ? get_ability_vertical(ability_id) : 255;
        ivec3 dest = find_cast_position(battle_id, unit_id,
            tx, tz, spell_range, target_height, vert_tolerance);
        if (dest.x < 0) {
            write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
            write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
            write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_SPELL_FAILED);
            return;
        }
        write_unit(battle_id, unit_id, U_CASTING_ABILITY_ID, ability_id);
        write_unit(battle_id, unit_id, U_CAST_TARGET, target_id);
        write_unit(battle_id, unit_id, U_DEST_X, dest.x);
        write_unit(battle_id, unit_id, U_DEST_Z, dest.y);
        write_unit(battle_id, unit_id, U_DEST_LEVEL, dest.z);
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_WALKING_TO_CAST);
        ivec3 next_cast = get_next_step(battle_id, unit_id, my_x, my_z, my_level,
                                        dest.x, dest.y, dest.z, target_id);
        if (next_cast.x != my_x || next_cast.y != my_z || next_cast.z != my_level) {
            write_movement_step(battle_id, unit_id, my_x, my_z, my_level,
                                next_cast.x, next_cast.y, next_cast.z);
        }
    }
}

void cast_projectile_spell(int battle_id, int unit_id, int target_id,
                           int cast_duration, int projectile_frame, int dist) {
    int flight_ticks = max(dist * FLIGHT_TICKS_PER_TILE, MIN_FLIGHT_TICKS);
    int damage_frame = projectile_frame + flight_ticks;
    int scaled_cast_duration = int(float(cast_duration) * GLOBAL_SPEED_DIVISOR) / ABILITY_SEQ_SPEED;
    // Per ADR-0032: LOGICAL_ACTIVITY_ACTING covers SEQ playback only. The flight tail
    // (when damage_frame > anim_frame) is handled by LOGICAL_ACTIVITY_AWAITING_IMPACT,
    // entered from LOGICAL_ACTIVITY_ACTING's exit branch in compute_unit_state.
    int total_action_time = scaled_cast_duration;

    write_unit(battle_id, unit_id, U_CAST_STEP_ID,
               read_unit(battle_id, unit_id, U_CAST_STEP_ID) + 1);
    write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_ACTING);
    write_unit(battle_id, unit_id, U_TARGET, target_id);
    write_unit(battle_id, unit_id, U_ANIM_FRAME, 0);
    write_unit(battle_id, unit_id, U_PROJECTILE_FRAME, projectile_frame);
    write_unit(battle_id, unit_id, U_DAMAGE_FRAME, damage_frame);
    write_unit(battle_id, unit_id, U_TOTAL_FRAMES, cast_duration);
    write_unit(battle_id, unit_id, U_ANIM_FLAGS, 0);
    write_unit(battle_id, unit_id, U_TIMER, total_action_time);
    write_unit(battle_id, unit_id, U_CAST_TIMER, 0);
}

void cast_adjacent_item(int battle_id, int unit_id, int target_id,
                        int cast_duration, int proj_frame_seq, int total_frames_seq) {
    int item_damage_frame = (total_frames_seq > 0)
        ? (proj_frame_seq * cast_duration) / total_frames_seq
        : cast_duration / 2;
    int scaled_cast_duration = int(float(cast_duration) * GLOBAL_SPEED_DIVISOR) / ABILITY_SEQ_SPEED;
    int total_action_time = max(scaled_cast_duration, item_damage_frame);

    write_unit(battle_id, unit_id, U_CAST_STEP_ID,
               read_unit(battle_id, unit_id, U_CAST_STEP_ID) + 1);
    write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_ACTING);
    write_unit(battle_id, unit_id, U_TARGET, target_id);
    write_unit(battle_id, unit_id, U_ANIM_FRAME, 0);
    write_unit(battle_id, unit_id, U_PROJECTILE_FRAME, -1);
    write_unit(battle_id, unit_id, U_DAMAGE_FRAME, item_damage_frame);
    write_unit(battle_id, unit_id, U_TOTAL_FRAMES, cast_duration);
    write_unit(battle_id, unit_id, U_ANIM_FLAGS, 0);
    write_unit(battle_id, unit_id, U_TIMER, total_action_time);
    write_unit(battle_id, unit_id, U_CAST_TIMER, 0);
}

void cast_instant_spell(int battle_id, int unit_id, int target_id,
                        int ability_id, int cast_duration) {
    int formula_id = get_ability_formula_id(ability_id);
    int effect_area = get_ability_effect_area(ability_id);

    if (effect_area > 0) {
        int center_x = read_unit(battle_id, target_id, U_POS_X);
        int center_z = read_unit(battle_id, target_id, U_POS_Z);
        write_unit(battle_id, unit_id, U_AOE_CENTER_X, center_x);
        write_unit(battle_id, unit_id, U_AOE_CENTER_Z, center_z);
        write_unit(battle_id, unit_id, U_AOE_ABILITY_ID, ability_id);
    } else {
        // #1113 — the charge_time == 0 landing. There is no `is_unit_dead` gate
        // on this branch and never was; what stopped a revive here was the fork
        // itself, which routed Revive (107) / Oink (312) — cancel-Dead but NOT
        // ABFLAG_HEALING — into the damage arm, where stage_damage Phase 2 then
        // dropped the write for being aimed at a corpse. Taking the revive
        // FIRST is the fix, and it leaves every living-target path untouched.
        if (is_unit_dead(battle_id, target_id) && ability_revives(ability_id)) {
            revive_unit(battle_id, target_id,
                        calculate_spell_damage(battle_id, unit_id, target_id, ability_id));
        } else if (formula_id == 43 || formula_id == 44 || formula_id == 37
            || formula_id == 10 || formula_id == 11 || formula_id == 56
            || formula_id == 42 || formula_id == 80) {
            int tick = get_battle_tick(battle_id);
            apply_break_effect(battle_id, unit_id, target_id, ability_id, tick);
        } else if (is_ability_healing(ability_id)) {
            int heal_amount = calculate_spell_damage(battle_id, unit_id, target_id, ability_id);
            // Tier 2 #10 — Undead inverts heals into damage via pending_damage.
            if (has_status(battle_id, target_id, STATUS_UNDEAD)) {
                int pending = read_unit(battle_id, target_id, U_PENDING_DAMAGE);
                write_unit(battle_id, target_id, U_PENDING_DAMAGE, pending + heal_amount);
            } else {
                int current_hp = get_hp(battle_id, target_id);
                int max_hp = get_max_hp(battle_id, target_id);
                write_unit(battle_id, target_id, U_HP, min(max_hp, current_hp + heal_amount));
            }
        } else {
            int damage = calculate_spell_damage(battle_id, unit_id, target_id, ability_id);
            // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) at the
            // queue site, BEFORE the target-side defense. Mirrors ROM order:
            // FUN_80185FFC runs from the formula handler prior to
            // FUN_80186FF8's status overlay + FUN_80184E98 equipment matrix.
            int element_id = get_ability_field(ability_id, AB_ELEMENT);
            damage = apply_strengthen_elem(battle_id, unit_id, element_id, damage);
            // Issue #110 -- scale by target's element defense at queue time so
            // the Phase 2 single-target apply in stage_damage doesn't need the
            // ability id (it isn't carried alongside U_DAMAGE_AMOUNT).
            damage = apply_element_defense(battle_id, target_id, ability_id, damage);
            write_unit(battle_id, unit_id, U_DAMAGE_TARGET, target_id);
            write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, damage);
        }
    }

    write_unit(battle_id, unit_id, U_CAST_TIMER, 0);
    write_unit(battle_id, unit_id, U_CAST_STEP_ID,
               read_unit(battle_id, unit_id, U_CAST_STEP_ID) + 1);
    write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_ACTING);
    write_unit(battle_id, unit_id, U_ANIM_FRAME, 0);
    write_unit(battle_id, unit_id, U_DAMAGE_FRAME, -1);
    write_unit(battle_id, unit_id, U_TOTAL_FRAMES, cast_duration);
    write_unit(battle_id, unit_id, U_ANIM_FLAGS, 0);
    write_unit(battle_id, unit_id, U_TIMER, cast_duration);
}

// Cinematic-spell entry point (issue #53; per-caster timer in #118). Parallel
// to cast_instant_spell / cast_projectile_spell / cast_adjacent_item; called
// from complete_spell_cast when the ability's charge_time > 0. Stamps each
// AoE/single target with U_AOE_PENDING_CASTER + U_AOE_PENDING_FIRE_FRAME so the
// caster's per-tick orchestrator loop can fire damage at the right beat, sets
// the caster's per-unit U_CINEMATIC_TIMER = 0, drives the caster into
// LOGICAL_ACTIVITY_ACTING with U_TIMER = the effect's cinematic total_frames,
// and increments U_PAUSED on every other unit (ref-count, so concurrent
// cinematics don't trample each other -- see #118).
void cast_cinematic_spell(int battle_id, int unit_id, int target_id, int ability_id) {
    int effect_id = get_ability_effect_id(ability_id);
    int first_hit_frame = get_effect_first_hit_frame(effect_id);
    int for_each_delay = get_effect_for_each_delay(effect_id);
    int total_frames = get_effect_total_frames(effect_id);
    int effect_area = get_ability_effect_area(ability_id);
    int caster_team = read_unit(battle_id, unit_id, U_TEAM);
    int cast_anim_id = get_ability_effect_anim_id(ability_id) * 2;
    int cast_duration = get_cast_animation_duration(ability_id);

    // Stamp per-target fire frames. AoE: walk units in radius using the
    // ADR-0049 hit policy (same predicate as stage_damage Phase 1), striding
    // by for_each_delay in unit-id order. Single-target: just the chosen target.
    if (effect_area > 0 && target_id >= 0) {
        int center_x = read_unit(battle_id, target_id, U_POS_X);
        int center_z = read_unit(battle_id, target_id, U_POS_Z);
        int target_count = 0;
        for (int t = 0; t < config.units_per_battle; t++) {
            if (is_unit_dead(battle_id, t)) continue;
            int tx = read_unit(battle_id, t, U_POS_X);
            int tz = read_unit(battle_id, t, U_POS_Z);
            int dist = abs(tx - center_x) + abs(tz - center_z);
            if (dist > effect_area) continue;
            int t_team = read_unit(battle_id, t, U_TEAM);
            if (!hit_policy_allows(ability_id, unit_id, caster_team, t, t_team))
                continue;
            int fire_frame = first_hit_frame + target_count * for_each_delay;
            write_unit(battle_id, t, U_AOE_PENDING_CASTER, unit_id);
            write_unit(battle_id, t, U_AOE_PENDING_FIRE_FRAME, fire_frame);
            target_count++;
        }
    } else if (target_id >= 0) {
        write_unit(battle_id, target_id, U_AOE_PENDING_CASTER, unit_id);
        write_unit(battle_id, target_id, U_AOE_PENDING_FIRE_FRAME, first_hit_frame);
    }

    // Open this caster's cinematic frame counter. Per-unit (issue #118) so two
    // casters finishing charge on the same tick each get their own slot.
    write_unit(battle_id, unit_id, U_CINEMATIC_TIMER, 0);

    // Caster enters ACTING with cast anim + cinematic-length timer.
    write_unit(battle_id, unit_id, U_ANIM_ID, cast_anim_id);
    write_unit(battle_id, unit_id, U_ANIM_FRAME, 0);
    write_unit(battle_id, unit_id, U_DAMAGE_FRAME, -1);
    write_unit(battle_id, unit_id, U_TOTAL_FRAMES, cast_duration);
    write_unit(battle_id, unit_id, U_ANIM_FLAGS, 0);
    write_unit(battle_id, unit_id, U_TIMER, total_frames);
    write_unit(battle_id, unit_id, U_CAST_TIMER, 0);
    write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_ACTING);
    write_unit(battle_id, unit_id, U_CAST_STEP_ID,
               read_unit(battle_id, unit_id, U_CAST_STEP_ID) + 1);

    // Increment the ref-count on every other unit (issue #118). With two
    // concurrent cinematics A and B, B sees A's pause and adds its own; A's
    // teardown only decrements once, so B's pause survives until B tears down.
    // The caster's own U_PAUSED is left untouched — if another cinematic is
    // already running, our caster is already paused by that one, and stage_spell
    // explicitly runs the orchestrator regardless of paused state via the
    // U_CINEMATIC_TIMER >= 0 carve-out. AoE targets stay paused too so they
    // can't cast back or attack mid-cinematic. CombatLoop._get_unit_anim_speed
    // still advances react_playback so the hit-flinch plays.
    for (int u = 0; u < config.units_per_battle; u++) {
        if (u == unit_id) continue;
        int pcount = read_unit(battle_id, u, U_PAUSED);
        write_unit(battle_id, u, U_PAUSED, pcount + 1);
    }
}

void complete_spell_cast(int battle_id, int unit_id) {
    int ability_id = read_unit(battle_id, unit_id, U_CASTING_ABILITY_ID);
    int target_id = read_unit(battle_id, unit_id, U_CAST_TARGET);

    if (ability_id < 0 || target_id < 0) {
        write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
        write_unit(battle_id, unit_id, U_TIMER, TICKS_GAMBIT_REEVAL);
        write_unit(battle_id, unit_id, U_DBG_STATE_REASON, REASON_SPELL_FAILED);
        return;
    }

    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int tx = read_unit(battle_id, target_id, U_POS_X);
    int tz = read_unit(battle_id, target_id, U_POS_Z);
    int dist = manhattan_distance(my_x, my_z, tx, tz);

    int cast_anim_id;
    bool is_adjacent_item = is_item_ability(ability_id) && dist <= 1;
    if (is_item_ability(ability_id)) {
        cast_anim_id = is_adjacent_item ? TYPE1_ITEM_USE : TYPE1_THROW_WEAPON;
    } else {
        int effect_anim_id = get_ability_effect_anim_id(ability_id);
        cast_anim_id = effect_anim_id * 2;
    }

    int total_frames_seq = get_anim_total_frames(cast_anim_id);
    int cast_duration = (total_frames_seq > 0) ? max(MIN_ATTACK_DURATION, (total_frames_seq * 4 + 2) / 3) : DEFAULT_CAST_DURATION;
    int proj_frame_seq = get_anim_damage_frame(cast_anim_id);
    int projectile_frame = (total_frames_seq > 0)
        ? (proj_frame_seq * cast_duration) / total_frames_seq
        : cast_duration / 2;

    clear_status(battle_id, unit_id, STATUS_CHARGING);

    // Cinematic-spell path (issue #53). charge_time > 0 abilities flip to
    // the per-target orchestrator that fires damage at first_hit_frame +
    // N * for_each_delay. cast_cinematic_spell writes U_ANIM_ID + U_TIMER
    // + cinematic header itself, so the instant/projectile prelude and
    // routing below stay reserved for charge_time == 0.
    if (get_ability_charge_time(ability_id) > 0) {
        cast_cinematic_spell(battle_id, unit_id, target_id, ability_id);
        return;
    }

    write_unit(battle_id, unit_id, U_ANIM_ID, cast_anim_id);

    bool uses_projectile = is_projectile_ability(ability_id) && !is_adjacent_item;

    if (uses_projectile) {
        cast_projectile_spell(battle_id, unit_id, target_id, cast_duration, projectile_frame, dist);
    } else if (is_adjacent_item) {
        cast_adjacent_item(battle_id, unit_id, target_id, cast_duration, proj_frame_seq, total_frames_seq);
    } else {
        cast_instant_spell(battle_id, unit_id, target_id, ability_id, cast_duration);
    }
}

// -----------------------------------------------------------------------------
// CINEMATIC ORCHESTRATOR HELPERS — verbatim copies from stage_compute.glsl
// (apply_damage_to_target / apply_heal_to_target / roll_evasion). The
// orchestrator runs in the caster's stage_spell thread, so the helpers
// authoritative-in stage_compute (gated PASS_COMPUTE) aren't visible from
// here without duplication. Same idiom the pathfinding helpers up top use.
// Keep in sync with stage_compute.glsl until a future pass promotes them.
// -----------------------------------------------------------------------------

bool roll_evasion(int battle_id, int attacker, int defender, int tick, bool is_magic) {
    int c_ev = read_unit(battle_id, defender, U_C_EV);
    int s_ev = is_magic
        ? read_unit(battle_id, defender, U_S_EV_MAG)
        : read_unit(battle_id, defender, U_S_EV);
    int w_ev = is_magic ? 0 : read_unit(battle_id, defender, U_W_EV);
    int total_evade = min(c_ev + s_ev + w_ev, 99);
    int roll = rand_int(battle_id, attacker, tick, 100) + 1;

    if (roll > total_evade) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 0);
        return true;
    }

    if (roll <= c_ev) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 1);
    } else if (roll <= c_ev + s_ev) {
        write_unit(battle_id, defender, U_EVADE_TYPE, 2);
    } else {
        write_unit(battle_id, defender, U_EVADE_TYPE, 3);
    }
    return false;
}

void apply_heal_to_target(int battle_id, int caster, int target, int ability_id, int tick) {
    int amount = calculate_spell_damage(battle_id, caster, target, ability_id);
    int proj_frame = read_unit(battle_id, caster, U_PROJECTILE_FRAME);
    if (proj_frame >= 0) {
        write_unit(battle_id, caster, U_PENDING_HEAL_TARGET, target);
        write_unit(battle_id, caster, U_PENDING_HEAL_AMOUNT, amount);
    } else {
        if (has_status(battle_id, target, STATUS_UNDEAD)) {
            int pending = read_unit(battle_id, target, U_PENDING_DAMAGE);
            write_unit(battle_id, target, U_PENDING_DAMAGE, pending + amount);
        } else {
            int current_hp = get_hp(battle_id, target);
            int max_hp = get_max_hp(battle_id, target);
            write_unit(battle_id, target, U_HP, min(max_hp, current_hp + amount));
        }
    }
    // Issue #100: mirror stage_compute.glsl's apply_heal_to_target so cinematic
    // heals also flow inflict (e.g. cleanse-on-ally if/when it's wired here).
    apply_inflict_all(battle_id, caster, target,
                      get_ability_inflict_mask(ability_id),
                      get_ability_inflict_mode(ability_id), tick);
}

void apply_damage_to_target(int battle_id, int caster, int target, int ability_id, int tick) {
    int amount = calculate_spell_damage(battle_id, caster, target, ability_id);
    // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) at the queue
    // site, BEFORE the target-side defense. Mirrors ROM FUN_80185FFC ordering.
    int element_id = get_ability_field(ability_id, AB_ELEMENT);
    amount = apply_strengthen_elem(battle_id, caster, element_id, amount);
    // Issue #110 -- scale by target's element defense at queue time, same
    // shape as cast_instant_spell above.
    amount = apply_element_defense(battle_id, target, ability_id, amount);
    int ab_flags = get_ability_flags(ability_id);
    bool evadeable = (ab_flags & ABFLAG_EVADEABLE) != 0;
    bool hit = !evadeable || roll_evasion(battle_id, caster, target, tick, true);
    if (hit) {
        write_unit(battle_id, caster, U_DAMAGE_TARGET, target);
        write_unit(battle_id, caster, U_DAMAGE_AMOUNT, amount);
        // Issue #98 tracer -- damage-and-status abilities (e.g. magic with
        // damage + inflict) OR their resolved mask onto the target on a
        // confirmed hit. Faith-scaled hit% lands in #103.
        apply_inflict_all(battle_id, caster, target,
                          get_ability_inflict_mask(ability_id),
                          get_ability_inflict_mode(ability_id), tick);
    }
}

// Tear down the cinematic owned by `caster_id`. Resets the caster's per-unit
// frame counter, decrements the U_PAUSED ref-count on every other unit, clears
// any AoE-pending stamps the caster placed (other casters' stamps are
// untouched -- issue #118), and transitions the caster from
// LOGICAL_ACTIVITY_ACTING to IDLE so its next-tick stage_compute picks gambits
// back up. Issued from the orchestrator below when U_CINEMATIC_TIMER has
// reached the effect's total_frames, or from the safety-net branch when the
// caster's casting state was already cleared upstream.
void cinematic_teardown(int battle_id, int caster_id) {
    write_unit(battle_id, caster_id, U_CINEMATIC_TIMER, -1);

    for (int u = 0; u < config.units_per_battle; u++) {
        if (u != caster_id) {
            // Ref-count decrement (issue #118). Concurrent cinematics each
            // bumped this once; only drop our own contribution, clamped at 0
            // for defense in depth.
            int pcount = read_unit(battle_id, u, U_PAUSED);
            write_unit(battle_id, u, U_PAUSED, max(0, pcount - 1));
        }
        // Only clear pending-fire stamps OUR caster placed -- a concurrent
        // cinematic's stamps must survive so its orchestrator can still fire.
        if (read_unit(battle_id, u, U_AOE_PENDING_CASTER) == caster_id) {
            write_unit(battle_id, u, U_AOE_PENDING_CASTER, -1);
            write_unit(battle_id, u, U_AOE_PENDING_FIRE_FRAME, -1);
        }
    }

    write_unit(battle_id, caster_id, U_STATE, LOGICAL_ACTIVITY_IDLE);
    write_unit(battle_id, caster_id, U_TIMER, TICKS_GAMBIT_REEVAL);
    write_unit(battle_id, caster_id, U_CASTING_ABILITY_ID, -1);
    write_unit(battle_id, caster_id, U_CAST_TARGET, -1);
}

// Reraise cinematic constants. Plays the Raise spell's E005 effect rather
// than E007 (Reraise's sparkle indicator) -- E005 includes the get-up pose
// cues in its particle channel flags, which is what makes the carrier
// visibly rise; E007 is just the status-sparkle and leaves the corpse
// lying flat. See issue #108. Ability id 5 (Raise) -> effect_file E005.BIN.
const int RERAISE_EFFECT_ID = 5;

// Reraise Stage B kickoff. Opens a self-targeted E007 cinematic on the
// dead carrier of STATUS_RERAISE once the U_TIMER deadline stamped by
// Stage A has elapsed. Identified downstream from a normal spell cinematic
// by U_CASTING_ABILITY_ID == -1 on the caster (normal cinematics keep the
// ability id set until cinematic_teardown). Sets the carrier's per-unit
// U_CINEMATIC_TIMER = 0 so its stage_spell thread runs the reraise
// orchestrator each tick (issue #118: per-unit timer replaces the shared
// battle-header pair); every other unit's U_PAUSED is incremented to
// freeze gambit + movement. CombatLoop's react-playback exception still
// advances HIT_REACT-like frames at speed 1 so visual flinches play out.
void start_reraise_cinematic(int battle_id, int unit_id) {
    write_unit(battle_id, unit_id, U_CINEMATIC_TIMER, 0);
    for (int u = 0; u < config.units_per_battle; u++) {
        if (u == unit_id) continue;
        int pcount = read_unit(battle_id, u, U_PAUSED);
        write_unit(battle_id, u, U_PAUSED, pcount + 1);
    }
}

// Reraise Stage B orchestrator. Runs every tick on the carrier's own
// thread while the reraise cinematic is active. Ticks the carrier's
// per-unit U_CINEMATIC_TIMER (issue #118), fires the revive at
// first_hit_frame (HP back, FLAG_DEAD cleared, state returned to IDLE),
// and tears the cinematic down at total_frames (the shared
// cinematic_teardown decrements U_PAUSED on every other unit, clears any
// U_AOE_PENDING_* stamps the carrier placed, and routes the caster to
// IDLE). STATUS_RERAISE + its timer slot stay set until teardown -- they
// double as the predicate that distinguishes this orchestrator from a
// normal-spell cinematic and as the "this is a reraise cinematic" gate
// for the pre-revive U_PAUSED carve-out below; clearing them at first_hit_frame
// would leave a window where the unit is alive with U_CASTING_ABILITY_ID
// == -1, indistinguishable from a freshly-spawned unit. cinematic_teardown
// itself is the safe point to drop the bit because every other unit is
// still paused.
void run_reraise_cinematic_orchestrator(int battle_id, int unit_id) {
    int new_timer = read_unit(battle_id, unit_id, U_CINEMATIC_TIMER) + 1;
    write_unit(battle_id, unit_id, U_CINEMATIC_TIMER, new_timer);

    // Drive the heal beat + teardown off the same E005 timing the normal
    // cinematic orchestrator consumes. GPUEffectTimingLoader uploads these
    // in host-tick units (30 -> 60 Hz scaled), so new_timer (per-dispatch)
    // is the right comparand. See issue #109 for the parser + clock-rate
    // alignment that retired the prior hardcoded overrides.
    int first_hit_frame = get_effect_first_hit_frame(RERAISE_EFFECT_ID);
    int total_frames = get_effect_total_frames(RERAISE_EFFECT_ID);

    if (new_timer == first_hit_frame) {
        // #1113 — this used to be four writes spelled out here. They are now
        // `revive_unit` in combat_common.glslinc, shared verbatim with the CAST
        // revive, so FLAG_DEAD is cleared in exactly one place in the kernel.
        // The HP is still RERAISE's own: a lethal-damage capture has no ability
        // whose formula could supply one.
        int max_hp = read_unit(battle_id, unit_id, U_MAX_HP);
        revive_unit(battle_id, unit_id, max_hp / RERAISE_HP_DIVISOR);
    }

    if (new_timer >= total_frames) {
        // cinematic_teardown clears U_PAUSED, U_AOE_PENDING_* on every unit
        // and routes the caster to IDLE. Drop STATUS_RERAISE + its timer
        // slot here, mirroring the pre-#107 try_consume_reraise consume
        // semantic but deferred to the teardown beat so the orchestrator
        // gate above stays load-bearing through the whole cinematic.
        int flags_lo = read_unit(battle_id, unit_id, U_STATUS_FLAGS_LO);
        write_unit(battle_id, unit_id, U_STATUS_FLAGS_LO,
                   flags_lo & ~(1 << STATUS_RERAISE));
        for (int slot = 0; slot < 8; slot++) {
            int packed = read_unit(battle_id, unit_id, U_STATUS_TIMER_0 + slot);
            if (packed != 0 && ((packed >> 24) & 0xFF) == STATUS_RERAISE) {
                write_unit(battle_id, unit_id, U_STATUS_TIMER_0 + slot, 0);
                break;
            }
        }
        cinematic_teardown(battle_id, unit_id);
    }
}

// Caster-side cinematic orchestrator (issue #53; per-caster timer in #118).
// Runs every tick the cinematic is active. Ticks this caster's per-unit
// U_CINEMATIC_TIMER, then walks every unit looking for any whose
// U_AOE_PENDING_FIRE_FRAME matches the new timer (and U_AOE_PENDING_CASTER
// points back at this caster). For each matching target, fires damage/heal
// via the verbatim helpers above, then consumes the stamp. After the
// per-target sweep, if U_CINEMATIC_TIMER has reached the effect's
// total_frames (or the caster's ability state was already cleared
// upstream), tears the cinematic down.
void run_cinematic_orchestrator(int battle_id, int unit_id) {
    int new_timer = read_unit(battle_id, unit_id, U_CINEMATIC_TIMER) + 1;
    write_unit(battle_id, unit_id, U_CINEMATIC_TIMER, new_timer);

    // Clear last tick's damage queue (issue #118). stage_compute normally
    // resets these each tick before stage_spell runs, but when a concurrent
    // cinematic has incremented this caster's U_PAUSED ref-count, our own
    // stage_compute early-returns under the U_PAUSED gate and the prior
    // tick's apply_damage_to_target write would persist. stage_damage Phase 2
    // would then re-apply it every tick, multiplying the cinematic's damage
    // by its frame count. Reset here, then any per-beat fire below rewrites
    // the slot in-tick.
    write_unit(battle_id, unit_id, U_DAMAGE_TARGET, -1);
    write_unit(battle_id, unit_id, U_DAMAGE_AMOUNT, 0);

    int ability_id = read_unit(battle_id, unit_id, U_CASTING_ABILITY_ID);
    int formula_id = (ability_id >= 0) ? get_ability_formula_id(ability_id) : -1;
    // Mirrors stage_damage.glsl's is_break_formula / cast_instant_spell's
    // status-formula branch. Routes to apply_break_effect for status-only
    // formulas instead of dealing HP damage.
    bool is_break = formula_id == 43 || formula_id == 44 || formula_id == 37
                 || formula_id == 10 || formula_id == 11 || formula_id == 56
                 || formula_id == 42 || formula_id == 80;
    bool healing = (ability_id >= 0) && is_ability_healing(ability_id);
    // #1113 — DEAD-FILTER 2 OF 4 ON THE REVIVE PATH, and the one Raise / Raise2
    // actually die on: both carry charge_time > 0, so a cast at a corpse lands
    // here and nowhere else. A cancel-Dead ability is admitted past the filter;
    // every other ability keeps the unconditional skip it has always had.
    bool revives = ability_revives(ability_id);
    int tick = get_battle_tick(battle_id);

    for (int t = 0; t < config.units_per_battle; t++) {
        bool t_dead = is_unit_dead(battle_id, t);
        if (t_dead && !revives) continue;
        if (read_unit(battle_id, t, U_AOE_PENDING_CASTER) != unit_id) continue;
        if (read_unit(battle_id, t, U_AOE_PENDING_FIRE_FRAME) != new_timer) continue;

        if (ability_id >= 0) {
            if (t_dead) {
                // The revive takes precedence over the break/heal/damage fork,
                // which is what lets the two cancel-Dead abilities that are NOT
                // flagged healing (Revive 107, Oink 312 — `taking_damage`
                // reaction category) reach a corpse without being routed into
                // the damage branch. On a LIVING target nothing changes: the
                // fork below runs exactly as before.
                revive_unit(battle_id, t,
                            calculate_spell_damage(battle_id, unit_id, t, ability_id));
            } else if (is_break) {
                apply_break_effect(battle_id, unit_id, t, ability_id, tick);
            } else if (healing) {
                apply_heal_to_target(battle_id, unit_id, t, ability_id, tick);
            } else {
                apply_damage_to_target(battle_id, unit_id, t, ability_id, tick);
            }
        }
        write_unit(battle_id, t, U_AOE_PENDING_CASTER, -1);
        write_unit(battle_id, t, U_AOE_PENDING_FIRE_FRAME, -1);
        // Target stays paused until cinematic_teardown clears U_PAUSED
        // for everyone. Earlier versions cleared U_PAUSED here so the
        // react animation could advance, but that left the target free
        // to run their own gambits (cast Dash, attack, etc.) during the
        // rest of the cinematic — breaking the spotlight intent. The
        // CPU side (CombatLoop tick loop) advances the React-set
        // playbacks at speed 1 when U_PAUSED && _react_active, so the
        // visual flinch plays without releasing the unit's state machine.
    }

    // Cinematic-end. Two paths: the effect's total_frames have elapsed
    // (the normal case), or stage_compute already cleared U_CASTING_ABILITY_ID
    // because ACTING's U_TIMER countdown hit 0 on this same tick. Either
    // way the cinematic is over.
    int effect_id = (ability_id >= 0) ? get_ability_effect_id(ability_id) : -1;
    int total_frames = get_effect_total_frames(effect_id);
    if (ability_id < 0 || new_timer >= total_frames) {
        cinematic_teardown(battle_id, unit_id);
    }
}

// -----------------------------------------------------------------------------
// Stage entry point.
// -----------------------------------------------------------------------------

void main() {
    uint global_id = gl_GlobalInvocationID.x;
    int battle_id = int(global_id / uint(config.units_per_battle));
    int unit_id = int(global_id % uint(config.units_per_battle));

    if (battle_id >= config.num_battles) return;

    int result = get_battle_result(battle_id);
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    int my_cin_timer = read_unit(battle_id, unit_id, U_CINEMATIC_TIMER);

    // Reraise Stage B kickoff (issue #107). A dead carrier whose
    // STATUS_RERAISE bit survives Stage A and whose stamped revive deadline
    // (U_TIMER) has elapsed opens a self-targeted E007 cinematic. Runs on
    // the dead unit's own thread BEFORE the dead-caster teardown or dead-
    // unit early-return branches below would otherwise swallow it.
    // Per #118 the kickoff is gated on THIS unit not already running its
    // own cinematic; concurrent cinematics on other units no longer block
    // it (CinematicManager picks one spotlight CPU-side).
    if (my_cin_timer == -1
        && is_unit_dead(battle_id, unit_id)
        && has_status(battle_id, unit_id, STATUS_RERAISE)
        && get_battle_tick(battle_id) >= read_unit(battle_id, unit_id, U_TIMER)) {
        start_reraise_cinematic(battle_id, unit_id);
        return;
    }

    // Reraise Stage B orchestrator. The caster of an active reraise
    // cinematic has U_CASTING_ABILITY_ID == -1 throughout (Stage A cleared
    // it); normal-spell cinematics keep their ability id set until
    // cinematic_teardown. Routing here skips the dead-caster teardown +
    // dead-unit early-return below so the pre-revive frames advance the
    // per-unit cinematic timer, fire the revive at first_hit_frame, and
    // tear down at total_frames.
    if (my_cin_timer >= 0
        && read_unit(battle_id, unit_id, U_CASTING_ABILITY_ID) == -1) {
        run_reraise_cinematic_orchestrator(battle_id, unit_id);
        return;
    }

    // If the cinematic caster died mid-cinematic (counter, reaction,
    // adjacent AoE, etc.) the per-tick orchestrator below would never run
    // and every paused unit would stay frozen forever. Detect the dead
    // caster here, fire teardown, return -- the teardown resets the
    // caster's U_CINEMATIC_TIMER to -1 and decrements U_PAUSED on every
    // other unit.
    if (my_cin_timer >= 0 && is_unit_dead(battle_id, unit_id)) {
        cinematic_teardown(battle_id, unit_id);
        return;
    }

    if (is_unit_dead(battle_id, unit_id)) return;

    // Caster runs the orchestrator each tick its cinematic is active. The
    // per-unit U_CINEMATIC_TIMER is set by cast_cinematic_spell on
    // cinematic-enter (tick T), so this branch first fires at tick T+1 --
    // the cinematic-enter tick goes through the COMPLETE_SPELL pending
    // dispatch below as usual. NOTE the carve-out: caster runs the
    // orchestrator BEFORE the generic U_PAUSED gate, because under
    // concurrent cinematics (#118) caster A is pause-incremented by
    // caster B and vice-versa; each still has to drive its own
    // orchestrator.
    if (my_cin_timer >= 0) {
        run_cinematic_orchestrator(battle_id, unit_id);
        return;
    }

    // Cinematic-spell pause (issue #53; ref-count in #118). Any non-zero
    // U_PAUSED means at least one cinematic on another unit is asking this
    // unit to freeze. Read sites already use `!= 0`, so the boolean and
    // ref-count semantics collapse here.
    if (read_unit(battle_id, unit_id, U_PAUSED) != 0) {
        return;
    }

    int pending = read_unit_next(battle_id, unit_id, U_PENDING_ACTION_TYPE);

    if (pending == ACTION_SPELL || pending == ACTION_ABILITY) {
        int target = read_unit_next(battle_id, unit_id, U_CAST_TARGET);
        int ability_id = read_unit_next(battle_id, unit_id, U_CASTING_ABILITY_ID);
        start_spell(battle_id, unit_id, target, ability_id);
        return;
    }
    if (pending == ACTION_ITEM) {
        int target = read_unit_next(battle_id, unit_id, U_CAST_TARGET);
        int ability_id = read_unit_next(battle_id, unit_id, U_CASTING_ABILITY_ID);
        if (target >= 0) {
            start_spell(battle_id, unit_id, target, ability_id);
        }
        return;
    }
    if (pending == ACTION_COMPLETE_SPELL) {
        complete_spell_cast(battle_id, unit_id);
        return;
    }
}
