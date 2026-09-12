#[compute]
#version 450

// =============================================================================
// stage_attack.glsl — PASS_ATTACK: execute ACTION_ATTACK pending actions
//
// One thread per unit. Runs immediately after stage_compute. Reads
// U_PENDING_ACTION_TYPE from NEXT (stage_compute committed it via
// record_action_carriers); if ACTION_ATTACK, runs execute_attack_gambit which
// either swings on an in-range target or sets up movement toward an attack
// position. Every other PENDING value short-circuits.
//
// Stage 2b Phase 3 — the smallest of the four sub-stage extractions. The
// pathfinding helpers below (trace_stitched_path / scan_adjacent_moves /
// find_nearest_attack_position / etc.) are duplicated from stage_compute.
// They'll be promoted to stage_pathfind.glsl in Phase 5 and the copies here
// will then #include from there.
//
// Dispatch: ceil(num_battles * units_per_battle / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"
#include "res://src/gpu/shaders/combat_combat.glslinc"

// -----------------------------------------------------------------------------
// DUPLICATED HELPERS — verbatim copies from stage_compute.glsl. Source of
// truth for these stays in stage_compute until Phase 5 lifts them into
// stage_pathfind. Keep in sync with stage_compute.glsl until then.
// -----------------------------------------------------------------------------

// Trace a stitched path using BFS-guided DFS with backtracking.
// Returns path length to destination, or -1 if unreachable.
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

// Attack stances are CELLS too. Returns `ivec3(x, z, level)`.
ivec3 find_nearest_attack_position(int battle_id, int unit_id,
                                   int target_x, int target_z, int target_level) {
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);
    int jump = read_unit(battle_id, unit_id, U_JUMP);
    int weapon_range = read_unit(battle_id, unit_id, U_WEAPON_RANGE);
    int attack_type = get_attack_type(battle_id, unit_id);

    ivec2 dirs[4] = ivec2[4](
        ivec2(0, 1),
        ivec2(1, 0),
        ivec2(0, -1),
        ivec2(-1, 0)
    );

    ivec3 best_pos = ivec3(-1, -1, -1);
    int best_dist = MAX_DISTANCE;
    ivec3 candidate_pos[3];
    int candidate_count = 0;

    for (int d = 0; d < 4; d++) {
        int ax = target_x + dirs[d].x;
        int az = target_z + dirs[d].y;

        for (int al = 0; al < MAP_LEVEL_COUNT; al++) {
            if (!is_tile_traversable(ax, az, al)) continue;

            int target_h = get_tile_height(target_x, target_z, target_level);
            int attack_h = get_tile_height(ax, az, al);

            if (abs(attack_h - target_h) > jump) continue;

            int height_diff = target_h - attack_h;
            if (!can_attack_from_adjacent(ax, az, al, target_x, target_z, target_level,
                                           height_diff, attack_type, weapon_range)) continue;

            if (ax == my_x && az == my_z && al == my_level) {
                return ivec3(ax, az, al);
            }

            int occupant = get_tile_occupant(battle_id, ax, az, al, unit_id);
            if (occupant >= 0) continue;

            int dist = get_distance(my_x, my_z, my_level, ax, az, al);
            if (dist >= 0 && dist < best_dist) {
                if (best_pos.x >= 0 && candidate_count < REACHABILITY_CANDIDATES) {
                    candidate_pos[candidate_count] = best_pos;
                    candidate_count++;
                }
                best_dist = dist;
                best_pos = ivec3(ax, az, al);
            } else if (dist >= 0 && candidate_count < REACHABILITY_CANDIDATES) {
                candidate_pos[candidate_count] = ivec3(ax, az, al);
                candidate_count++;
            }
        }
    }

    if (best_pos.x >= 0) {
        int path = trace_stitched_path(battle_id, unit_id,
            my_x, my_z, my_level, best_pos.x, best_pos.y, best_pos.z, -1);
        if (path >= 0) return best_pos;
    }
    for (int i = 0; i < candidate_count; i++) {
        int path = trace_stitched_path(battle_id, unit_id,
            my_x, my_z, my_level, candidate_pos[i].x, candidate_pos[i].y, candidate_pos[i].z, -1);
        if (path >= 0) return candidate_pos[i];
    }
    return ivec3(-1, -1, -1);
}

bool has_attack_position(int battle_id, int unit_id,
                         int target_x, int target_z, int target_level) {
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);
    int jump = read_unit(battle_id, unit_id, U_JUMP);
    int weapon_range = read_unit(battle_id, unit_id, U_WEAPON_RANGE);
    int attack_type = get_attack_type(battle_id, unit_id);

    ivec2 dirs[4] = ivec2[4](
        ivec2(0, 1), ivec2(1, 0), ivec2(0, -1), ivec2(-1, 0)
    );

    for (int d = 0; d < 4; d++) {
        int ax = target_x + dirs[d].x;
        int az = target_z + dirs[d].y;

        for (int al = 0; al < MAP_LEVEL_COUNT; al++) {
            if (!is_tile_traversable(ax, az, al)) continue;

            int target_h = get_tile_height(target_x, target_z, target_level);
            int attack_h = get_tile_height(ax, az, al);
            if (abs(attack_h - target_h) > jump) continue;

            int height_diff = target_h - attack_h;
            if (!can_attack_from_adjacent(ax, az, al, target_x, target_z, target_level,
                                           height_diff, attack_type, weapon_range)) continue;

            if (ax == my_x && az == my_z && al == my_level) return true;

            if (get_tile_occupant(battle_id, ax, az, al, unit_id) >= 0) continue;

            return true;
        }
    }
    return false;
}

int find_nearest_attackable_enemy(int battle_id, int unit_id) {
    int my_team = read_unit(battle_id, unit_id, U_TEAM);
    int my_x = read_unit(battle_id, unit_id, U_POS_X);
    int my_z = read_unit(battle_id, unit_id, U_POS_Z);
    int my_level = read_unit(battle_id, unit_id, U_LEVEL);

    int best_enemy = -1;
    int best_dist = MAX_DISTANCE;

    for (int u = 0; u < config.units_per_battle; u++) {
        if (u == unit_id) continue;
        if (is_unit_dead(battle_id, u)) continue;
        if (read_unit(battle_id, u, U_TEAM) == my_team) continue;
        // TRANSPARENT filter — enemy-side only (status_system.md §2).
        if (has_status_next(battle_id, u, STATUS_TRANSPARENT)) continue;

        int ex = read_unit(battle_id, u, U_POS_X);
        int ez = read_unit(battle_id, u, U_POS_Z);
        // ADR-0224 dec. 6: the enemy's level is the enemy's own, read off its
        // record rather than resolved from the column it stands in.
        int el = read_unit(battle_id, u, U_LEVEL);
        int dist = get_distance(my_x, my_z, my_level, ex, ez, el);
        if (dist < 0) continue;

        if (dist >= best_dist) continue;

        if (can_attack_target(battle_id, unit_id, u)) {
            best_dist = dist;
            best_enemy = u;
            continue;
        }

        if (has_attack_position(battle_id, unit_id, ex, ez, el)) {
            best_dist = dist;
            best_enemy = u;
        }
    }

    return best_enemy;
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

    write_idx = (write_idx + 1) % 6;
    meta = (write_idx & 0x7) | (meta & 0xF8);
    write_unit(battle_id, unit_id, U_DECISION_META, meta);
}

// -----------------------------------------------------------------------------
// EXECUTE_ATTACK_GAMBIT — verbatim from stage_compute.glsl. Will eventually
// be the sole copy (Phase 5 removes the stage_compute version).
// -----------------------------------------------------------------------------

void execute_attack_gambit(int battle_id, int unit_id, int target) {
    if (can_attack_target(battle_id, unit_id, target)) {
        write_unit(battle_id, unit_id, U_TARGET, target);
        int weapon_type = read_unit(battle_id, unit_id, U_WEAPON_TYPE);
        setup_attack_animation(battle_id, unit_id, target, weapon_type);
        record_decision(battle_id, unit_id, REASON_START_ATTACKING, LOGICAL_ACTIVITY_ACTING, target);
    } else {
        write_unit(battle_id, unit_id, U_TARGET, target);
        int tx = read_unit(battle_id, target, U_POS_X);
        int tz = read_unit(battle_id, target, U_POS_Z);
        // ADR-0224 dec. 6 -- the target's level is the TARGET's, off its record.
        int t_level = read_unit(battle_id, target, U_LEVEL);
        int my_x = read_unit(battle_id, unit_id, U_POS_X);
        int my_z = read_unit(battle_id, unit_id, U_POS_Z);
        int my_level = read_unit(battle_id, unit_id, U_LEVEL);

        ivec3 attack_pos = find_nearest_attack_position(battle_id, unit_id, tx, tz, t_level);

        if (attack_pos.x < 0) {
            int alt = find_nearest_attackable_enemy(battle_id, unit_id);
            if (alt >= 0 && alt != target) {
                target = alt;
                write_unit(battle_id, unit_id, U_TARGET, target);
                if (can_attack_target(battle_id, unit_id, target)) {
                    int weapon_type = read_unit(battle_id, unit_id, U_WEAPON_TYPE);
                    setup_attack_animation(battle_id, unit_id, target, weapon_type);
                    record_decision(battle_id, unit_id, REASON_START_ATTACKING, LOGICAL_ACTIVITY_ACTING, target);
                    return;
                }
                tx = read_unit(battle_id, target, U_POS_X);
                tz = read_unit(battle_id, target, U_POS_Z);
                t_level = read_unit(battle_id, target, U_LEVEL);
                attack_pos = find_nearest_attack_position(battle_id, unit_id, tx, tz, t_level);
            }
        }

        // All three fall back together -- `attack_pos` is `(-1, -1, -1)` or a
        // whole cell, never half of one. The pre-ADR-0224 code tested `.y` for
        // the Z fallback, which was the same condition; with a third component
        // in play, testing `.x` for all three says so.
        int dest_x = (attack_pos.x >= 0) ? attack_pos.x : tx;
        int dest_z = (attack_pos.x >= 0) ? attack_pos.y : tz;
        int dest_level = (attack_pos.x >= 0) ? attack_pos.z : t_level;

        ivec3 next = get_next_step(battle_id, unit_id, my_x, my_z, my_level,
                                   dest_x, dest_z, dest_level, target);
        if (next.x != my_x || next.y != my_z || next.z != my_level) {
            write_unit(battle_id, unit_id, U_STATE, LOGICAL_ACTIVITY_WALKING);
            write_unit(battle_id, unit_id, U_DEST_X, dest_x);
            write_unit(battle_id, unit_id, U_DEST_Z, dest_z);
            write_unit(battle_id, unit_id, U_DEST_LEVEL, dest_level);
            write_movement_step(battle_id, unit_id, my_x, my_z, my_level, next.x, next.y, next.z);
            record_decision(battle_id, unit_id, REASON_START_MOVING, LOGICAL_ACTIVITY_WALKING, target);
        } else {
            write_unit(battle_id, unit_id, U_TIMER, TICKS_PATH_RETRY);
            record_decision(battle_id, unit_id, REASON_NO_PATH, LOGICAL_ACTIVITY_IDLE, target);
        }
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

    if (is_unit_dead(battle_id, unit_id)) return;

    // Cinematic-spell pause (issue #53; ref-count in #118). Mirrors the
    // stage_compute / stage_pathfind gates so paused units don't attack
    // during a cinematic. See cast_cinematic_spell / cinematic_teardown
    // for the ref-count contract.
    if (read_unit(battle_id, unit_id, U_PAUSED) != 0) {
        return;
    }

    // Read pending action from NEXT — stage_compute wrote it earlier this tick
    // via record_action_carriers() inside execute_gambit_action().
    int pending = read_unit_next(battle_id, unit_id, U_PENDING_ACTION_TYPE);
    if (pending != ACTION_ATTACK) return;

    int target = read_unit_next(battle_id, unit_id, U_TARGET);
    execute_attack_gambit(battle_id, unit_id, target);
}
