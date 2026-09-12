extends "res://src/scenes/GPUArena.gd"

## GPU Thrash Test
##
## Uses seed 5089282674110889937 which previously caused Marcus (unit 0)
## to oscillate between (2,3) and (3,3) indefinitely.
## PASS: Marcus engages in combat (attacks or moves toward target) without
##       getting stuck in NO_GAMBIT idle loop.
## FAIL: Marcus stuck in IDLE with NO_GAMBIT for extended period.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase



const THRASH_SEED: int = 5089282674110889937
const CHECK_TICKS: int = 2000
const STUCK_THRESHOLD: int = 200  # Ticks of IDLE = stuck

var _test_done: bool = false
var _marcus_idle_ticks: int = 0
var _marcus_ever_acted: bool = false  # Did Marcus ever attack or move?
var _debug_printed: bool = false

# Debug tracking state
var _prev_gambit: Dictionary = {}     # unit_idx -> previous current_gambit
var _prev_timer: Dictionary = {}      # unit_idx -> previous timer
var _stuck_counter: Dictionary = {}   # unit_idx -> ticks stuck in same state+timer
var _kill_tracker: Dictionary = {}    # killer_idx -> { victim, tick, logged_ticks }
var _dead_units: Dictionary = {}      # unit_idx -> tick when died
var _prev_stuck_state: Dictionary = {}  # unit_idx -> previous state for stuck detection


func _ready():
	DebugConfig.combat_seed = THRASH_SEED
	DebugConfig.combat_autostart = true
	regression_logging = false
	max_ticks = CHECK_TICKS

	super._ready()


func get_test_name() -> String:
	return "GPU Thrash Test"


func _get_unit_name(idx: int) -> String:
	if idx >= 0 and idx < units.size():
		return units[idx].name
	if idx < 0:
		return "none"
	return "Unit%d" % idx


func _get_state_name(state: int) -> String:
	if state >= 0 and state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size():
		return GPUConstants.LOGICAL_ACTIVITY_NAMES[state]
	return str(state)


func _get_reason_name(reason: int) -> String:
	if reason >= 0 and reason < GPUConstants.REASON_NAMES.size():
		return GPUConstants.REASON_NAMES[reason]
	return str(reason)


func _get_ability_str(ability_id: int) -> String:
	if ability_id < 0:
		return ""
	var name = AbilityDatabase.get_ability_view(ability_id).name
	return "%s(%d)" % [name, ability_id]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	# Marcus acted tracking (test logic)
	if unit_idx == 0:
		if new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING or new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
			_marcus_ever_acted = true
			_marcus_idle_ticks = 0
		if new_state != GPUConstants.LOGICAL_ACTIVITY_IDLE:
			_marcus_idle_ticks = 0

	# Rich transition logging
	# Full snapshot, not `_all_states`: this logs `current_gambit` and
	# `dbg_state_reason`, which W1's SNAPSHOT_HOT_UNION does not carry, so off
	# `_all_states` they would print `.get()` defaults instead of real values.
	if DebugConfig.iteration_debug_enabled and gpu_state_reader != null \
			and gpu_state_reader.get_all_unit_states().size() > unit_idx:
		var s = gpu_state_reader.get_all_unit_states()[unit_idx]
		var name = _get_unit_name(unit_idx)
		var old_name = _get_state_name(old_state)
		var new_name = _get_state_name(new_state)
		var reason = _get_reason_name(s.get("dbg_state_reason", 0))
		var tgt = _get_unit_name(s.get("target", -1))
		var gam = s.get("current_gambit", -1)
		var timer = s.get("timer", 0)
		var ability_str = _get_ability_str(s.get("casting_ability_id", -1))
		var extra = ""
		if ability_str != "":
			extra = " ability=%s" % ability_str
		var cast_tgt = s.get("cast_target", -1)
		if cast_tgt >= 0:
			extra += " cast_tgt=%s" % _get_unit_name(cast_tgt)
		print("[T%d] [STATE] %s: %s -> %s  rsn=%s tgt=%s gam=%d t=%d%s" % [
			current_tick, name, old_name, new_name, reason, tgt, gam, timer, extra])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta_hp: int):
	if not DebugConfig.iteration_debug_enabled:
		return

	var name = _get_unit_name(unit_idx)
	if delta_hp < 0:
		print("[T%d] [HP] %s took %d damage (hp: %d -> %d)" % [
			current_tick, name, -delta_hp, old_hp, new_hp])
	else:
		print("[T%d] [HP] %s healed %d (hp: %d -> %d)" % [
			current_tick, name, delta_hp, old_hp, new_hp])

	# Kill detection
	if new_hp <= 0 and old_hp > 0:
		_dead_units[unit_idx] = current_tick
		var killer_idx = _find_killer(unit_idx)
		var killer_name = _get_unit_name(killer_idx)
		print("[T%d] [KILL] %s KILLED by %s (hp: %d -> %d)" % [
			current_tick, name, killer_name, old_hp, new_hp])
		if killer_idx >= 0:
			_kill_tracker[killer_idx] = {
				"victim": name,
				"tick": current_tick,
				"logged_ticks": 0
			}


func _find_killer(victim_idx: int) -> int:
	"""Find who killed the victim by checking who's ACTING with target=victim."""
	for i in range(_all_states.size()):
		if i == victim_idx:
			continue
		var s = _all_states[i]
		var state = s.get("state", 0)
		if state == GPUConstants.LOGICAL_ACTIVITY_ACTING and s.get("target", -1) == victim_idx:
			return i
	# Fallback: check damage_target
	for i in range(_all_states.size()):
		if i == victim_idx:
			continue
		if _all_states[i].get("damage_target", -1) == victim_idx:
			return i
	return -1


func on_victory(winning_team: int):
	if not _test_done:
		if _marcus_ever_acted:
			_finish_test(true, "Combat resolved (team %d won), Marcus engaged" % winning_team)
		else:
			_finish_test(false, "Combat resolved but Marcus never acted (stuck in NO_GAMBIT)")


func _process(delta):
	super._process(delta)

	if _test_done:
		return

	# Use _all_states populated by super._process() — no extra GPU readback
	var states = _all_states

	# Comprehensive debug logging (all gated behind iteration_debug_enabled)
	if DebugConfig.iteration_debug_enabled and combat_active and states.size() > 0:
		_log_all_units_tick(states)
		_detect_gambit_changes(states)
		_detect_anomalies(states)
		_track_post_kill_behavior(states)

	# Track Marcus idle time
	if combat_active and states.size() > 0:
		var marcus = states[0]
		var marcus_state = marcus.get("state", 0)
		var marcus_hp = marcus.get("hp", 0)

		if marcus_hp <= 0:
			if _marcus_ever_acted:
				_finish_test(true, "Marcus died but engaged in combat before death")
			else:
				_finish_test(false, "Marcus died without ever acting (stuck in NO_GAMBIT)")
			return

		if marcus_state == GPUConstants.LOGICAL_ACTIVITY_IDLE:
			_marcus_idle_ticks += 1
		else:
			_marcus_idle_ticks = 0

		# Debug: print Marcus's situation periodically
		if _marcus_idle_ticks > 0 and _marcus_idle_ticks % 100 == 0:
			_print_marcus_debug(states)

		# Detect stuck
		if _marcus_idle_ticks >= STUCK_THRESHOLD and not _marcus_ever_acted:
			_print_marcus_debug(states)
			_finish_test(false, "Marcus stuck IDLE for %d ticks (NO_GAMBIT)" % _marcus_idle_ticks)
			return

	# Victory detected by GPUArena._check_victory() (sets victory_achieved, no quit)
	if victory_achieved:
		if _marcus_ever_acted:
			_finish_test(true, "Combat resolved (team won), Marcus engaged")
		else:
			_finish_test(false, "Combat resolved but Marcus never acted (stuck in NO_GAMBIT)")
		return

	if current_tick >= CHECK_TICKS and combat_active:
		if _marcus_ever_acted:
			_finish_test(true, "No thrashing in %d ticks, Marcus engaged" % CHECK_TICKS)
		else:
			_finish_test(false, "Marcus never acted in %d ticks" % CHECK_TICKS)


func _log_all_units_tick(states: Array):
	"""Compact one-line-per-alive-unit every tick."""
	for i in range(mini(states.size(), units.size())):
		var s = states[i]
		var hp = s.get("hp", 0)
		var dead = _is_unit_dead(s)
		if dead or hp <= 0:
			continue

		var name = _get_unit_name(i)
		var state = _get_state_name(s.get("state", 0))
		var timer = s.get("timer", 0)
		var gam = s.get("current_gambit", -1)
		var gcd = s.get("gambit_cooldown", 0)
		var tgt = _get_unit_name(s.get("target", -1))
		var px = s.get("pos_x", -1)
		var pz = s.get("pos_z", -1)
		var dx = s.get("dest_x", -1)
		var dz = s.get("dest_z", -1)
		var reason = _get_reason_name(s.get("dbg_state_reason", 0))
		var blocked = s.get("dbg_conflict_blocked", 0)

		# Check visual drift
		var visual_pos = _visual_bridge.visual_positions.get(i, Vector3.ZERO)
		# Typed local for the inherited `CombatHost.lattice` — the register infers a
		# receiver's type per FILE, so a call on a base class's field reads as
		# "undeclared in this file" (ADR-0192's amendment names this blind spot).
		var lat: Lattice = lattice
		var cell_present := lat != null and lat.terrain_at(TerrainCell.ground(px, pz)) != null
		var drift_flag = ""
		if cell_present:
			var tile_pos := lat.world_position_at(TerrainCell.ground(px, pz))
			var dist = Vector2(visual_pos.x - tile_pos.x, visual_pos.z - tile_pos.z).length()
			if dist > 1.5:
				drift_flag = " DRIFT=%.1f" % dist

		var blocked_str = ""
		if blocked == 1:
			blocked_str = " BLOCKED"

		print("[T%d] %-8s %-15s t=%-3d gam=%-2d gcd=%-2d tgt=%-8s pos=(%d,%d) dst=(%d,%d) hp=%-4d rsn=%s%s%s" % [
			current_tick, name, state, timer, gam, gcd, tgt, px, pz, dx, dz, hp, reason, blocked_str, drift_flag])


func _detect_gambit_changes(states: Array):
	"""Log when any unit's current_gambit changes."""
	for i in range(mini(states.size(), units.size())):
		var s = states[i]
		var gam = s.get("current_gambit", -1)
		var prev = _prev_gambit.get(i, -1)
		_prev_gambit[i] = gam
		if gam != prev:
			var name = _get_unit_name(i)
			var tgt = _get_unit_name(s.get("target", -1))
			var ability_str = _get_ability_str(s.get("casting_ability_id", -1))
			if ability_str == "":
				ability_str = "none"
			print("[T%d] [GAMBIT] %s gambit %d -> %d  tgt=%s ability=%s" % [
				current_tick, name, prev, gam, tgt, ability_str])


func _detect_anomalies(states: Array):
	"""Auto-detect and prominently flag potential issues."""
	for i in range(mini(states.size(), units.size())):
		var s = states[i]
		var hp = s.get("hp", 0)
		var dead = _is_unit_dead(s)
		if dead or hp <= 0:
			continue

		var name = _get_unit_name(i)
		var state = s.get("state", 0)
		var timer = s.get("timer", 0)
		var reason = s.get("dbg_state_reason", 0)

		# Visual drift
		var visual_pos = _visual_bridge.visual_positions.get(i, Vector3.ZERO)
		var px = s.get("pos_x", -1)
		var pz = s.get("pos_z", -1)
		var lat: Lattice = lattice
		var cell_present := lat != null and lat.terrain_at(TerrainCell.ground(px, pz)) != null
		if cell_present:
			var tile_pos := lat.world_position_at(TerrainCell.ground(px, pz))
			var dist = Vector2(visual_pos.x - tile_pos.x, visual_pos.z - tile_pos.z).length()
			if dist > 1.5:
				print("[T%d] [ANOMALY] %s visual drift %.1f units from grid tile (%d,%d)" % [
					current_tick, name, dist, px, pz])

		# Stuck timer (same state+timer for >50 ticks, non-IDLE non-DEAD non-VICTORIOUS)
		var prev_state = _prev_stuck_state.get(i, -1)
		var prev_t = _prev_timer.get(i, -1)
		_prev_timer[i] = timer
		_prev_stuck_state[i] = state
		if state != GPUConstants.LOGICAL_ACTIVITY_IDLE and state != GPUConstants.LOGICAL_ACTIVITY_DYING and state != GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
			if state == prev_state and timer == prev_t:
				_stuck_counter[i] = _stuck_counter.get(i, 0) + 1
				if _stuck_counter[i] == 50:
					print("[T%d] [ANOMALY] %s stuck in %s for 50 ticks (timer=%d)" % [
						current_tick, name, _get_state_name(state), timer])
			else:
				_stuck_counter[i] = 0
		else:
			_stuck_counter[i] = 0

		# Targeting dead unit
		var tgt_idx = s.get("target", -1)
		if tgt_idx >= 0 and tgt_idx in _dead_units:
			if state != GPUConstants.LOGICAL_ACTIVITY_IDLE and state != GPUConstants.LOGICAL_ACTIVITY_DYING and state != GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
				print("[T%d] [ANOMALY] %s targeting dead %s while in %s" % [
					current_tick, name, _get_unit_name(tgt_idx), _get_state_name(state)])

		# Conflict blocked
		if s.get("dbg_conflict_blocked", 0) == 1:
			var blocker_idx = s.get("dbg_conflict_blocker", -1)
			var blocker_name = _get_unit_name(blocker_idx)
			print("[T%d] [ANOMALY] %s CONFLICT BLOCKED by %s at (%d,%d)" % [
				current_tick, name, blocker_name, px, pz])


func _track_post_kill_behavior(states: Array):
	"""For 20 ticks after a kill, log what the killer is doing."""
	var to_remove = []
	for killer_idx in _kill_tracker:
		var info = _kill_tracker[killer_idx]
		var ticks_since = current_tick - info["tick"]
		if ticks_since > 20:
			to_remove.append(killer_idx)
			continue
		if ticks_since <= 0:
			continue
		if killer_idx >= states.size():
			continue
		var s = states[killer_idx]
		var name = _get_unit_name(killer_idx)
		var victim = info["victim"]
		var state_name = _get_state_name(s.get("state", 0))
		var reason = _get_reason_name(s.get("dbg_state_reason", 0))
		var tgt = _get_unit_name(s.get("target", -1))
		var timer = s.get("timer", 0)
		var gam = s.get("current_gambit", -1)
		print("[T%d] [POST-KILL] %s (killed %s +%dt): %s rsn=%s tgt=%s timer=%d gam=%d" % [
			current_tick, name, victim, ticks_since, state_name, reason, tgt, timer, gam])
	for idx in to_remove:
		_kill_tracker.erase(idx)


func _print_marcus_debug(states: Array):
	if states.size() < 1:
		return
	var marcus = states[0]
	var mx = marcus.get("pos_x", -1)
	var mz = marcus.get("pos_z", -1)
	var marcus_height = marcus.get("height", -1)
	var marcus_unit = units[0] if units.size() > 0 else null
	var marcus_jump = marcus_unit.jump if marcus_unit else -1
	print("\n[DEBUG] Marcus at (%d,%d) tick=%d idle_ticks=%d jump=%d tile_h=%d" % [mx, mz, current_tick, _marcus_idle_ticks, marcus_jump, marcus_height])

	# Get map dimensions from distance field stats
	var df_stats = distance_field.get_stats() if distance_field else {}
	var df_min_x = df_stats.get("bounds", {}).get("min_x", 0)
	var df_min_z = df_stats.get("bounds", {}).get("min_z", 0)
	var df_max_x = df_stats.get("bounds", {}).get("max_x", 0)
	var df_max_z = df_stats.get("bounds", {}).get("max_z", 0)
	print("  DF bounds: min=(%d,%d) max=(%d,%d)" % [df_min_x, df_min_z, df_max_x, df_max_z])
	var map_w = df_max_x - df_min_x + 1
	var map_h = df_max_z - df_min_z + 1
	var total_tiles = map_w * map_h

	var flat: PackedInt32Array
	if distance_field:
		flat = distance_field.get_flat_distances()

	# Print all enemy positions with BFS distances and heights
	for i in range(states.size()):
		var s = states[i]
		var team = s.get("team", -1)
		var hp = s.get("hp", 0)
		if team != 0 and hp > 0:
			var ex = s.get("pos_x", -1)
			var ez = s.get("pos_z", -1)
			var eh = s.get("height", -1)
			var unit_name = units[i].name if i < units.size() else "Unit %d" % i
			var bfs_dist = -99
			if flat.size() > 0:
				var from_idx = (mz - df_min_z) * map_w + (mx - df_min_x)
				var to_idx = (ez - df_min_z) * map_w + (ex - df_min_x)
				var flat_idx = from_idx * total_tiles + to_idx
				if flat_idx >= 0 and flat_idx < flat.size():
					bfs_dist = flat[flat_idx]
			print("  Enemy %s at (%d,%d) h=%d HP=%d bfs_dist=%d" % [unit_name, ex, ez, eh, hp, bfs_dist])

	# Print adjacent tile heights and occupants
	var dirs = [Vector2i(0,1), Vector2i(1,0), Vector2i(0,-1), Vector2i(-1,0)]
	var dir_names = ["E(+z)", "N(+x)", "W(-z)", "S(-x)"]
	var lat: Lattice = lattice
	for d_idx in range(4):
		var nx = mx + dirs[d_idx].x
		var nz = mz + dirs[d_idx].y
		var cell := lat.terrain_at(TerrainCell.ground(nx, nz)) if lat != null else null
		var tile_h = cell.height if cell else -1
		var impassable = cell.impassable if cell else true
		var occupant = "empty"
		for j in range(states.size()):
			if j == 0:
				continue
			if states[j].get("pos_x", -1) == nx and states[j].get("pos_z", -1) == nz and states[j].get("hp", 0) > 0:
				occupant = units[j].name if j < units.size() else "Unit %d" % j
				break
		var bfs_to_tile = -99
		if flat.size() > 0 and not impassable:
			var from_idx = (mz - df_min_z) * map_w + (mx - df_min_x)
			var to_idx = (nz - df_min_z) * map_w + (nx - df_min_x)
			var flat_idx = from_idx * total_tiles + to_idx
			if flat_idx >= 0 and flat_idx < flat.size():
				bfs_to_tile = flat[flat_idx]
		print("  %s (%d,%d): h=%d impass=%s bfs=%d %s" % [dir_names[d_idx], nx, nz, tile_h, str(impassable), bfs_to_tile, occupant])


func _find_unit_pos_by_name(states: Array, target_name: String) -> Vector2i:
	for i in range(mini(units.size(), states.size())):
		if units[i].name == target_name:
			return Vector2i(states[i].get("pos_x", -1), states[i].get("pos_z", -1))
	return Vector2i(-1, -1)


func _finish_test(passed: bool, message: String):
	_test_done = true
	if passed:
		print("\n[PASS] %s" % message)
	else:
		print("\n[FAIL] %s" % message)

	DebugConfig.combat_seed = 0
	DebugConfig.combat_autostart = false
	get_tree().quit(0 if passed else 1)
