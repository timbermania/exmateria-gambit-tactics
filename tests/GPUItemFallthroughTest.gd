extends "res://src/scenes/GPUArena.gd"

## GPU Item Fallthrough Test
##
## Uses seed 224650900948040906 which previously caused Sera (a chemist) to
## move in circles trying to throw a potion at an unreachable ally instead of
## falling through to a lower-priority gambit.
##
## PASS: no unit circles in MOVING_TO_CAST (every unit either makes progress
##       toward its cast destination or leaves the state), and combat resolves.
## FAIL: a unit sits in MOVING_TO_CAST making no net progress toward its cast
##       destination for NO_PROGRESS_LIMIT ticks (the circling signature).
##
## Detection is progress-based, NOT time-in-state: a chemist legitimately
## walking several tiles to a *reachable* ally stays in MOVING_TO_CAST for
## hundreds of ticks (one tile-step is ~30-60 ticks, with occasional path-retry
## pauses) while steadily closing the distance — that is not stuck. Circling is
## distinguished by the distance-to-destination never improving.

const FALLTHROUGH_SEED: int = 224650900948040906
const CHECK_TICKS: int = 5000
# Ticks a unit may stay in MOVING_TO_CAST without its Manhattan distance to the
# cast destination reaching a new minimum. A real circle never improves and
# trips this; a slow-but-progressing walk resets it on every tile gained. Sized
# well above the worst observed gap between gains: ~75 ticks for a slow step
# plus path-retry pause, and up to ~640 ticks while paused under a teammate's
# cinematic spell (issue #53 -- U_PAUSED freezes pathfinding for the whole
# cinematic). Exposing U_PAUSED via the snapshot would let the check skip
# paused frames; until then 1500 gives margin for back-to-back cinematics.
const NO_PROGRESS_LIMIT: int = 1500

var _test_done: bool = false
# Per-unit progress tracking while in MOVING_TO_CAST.
var _mtc_dest: Dictionary = {}        # unit_idx -> Vector2i cast destination
var _mtc_min_dist: Dictionary = {}    # unit_idx -> best (min) distance to dest seen
var _mtc_no_progress: Dictionary = {} # unit_idx -> ticks since min_dist last improved


func _ready():
	DebugConfig.combat_seed = FALLTHROUGH_SEED
	DebugConfig.combat_autostart = true
	regression_logging = false
	max_ticks = CHECK_TICKS

	super._ready()


func get_test_name() -> String:
	return "GPU Item Fallthrough Test"


func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func on_hp_changed(_unit_idx: int, _old_hp: int, _new_hp: int, _delta: int):
	pass


func on_victory(winning_team: int):
	if not _test_done:
		_finish_test(true, "Combat resolved (team %d won), no unit circling" % winning_team)


func _clear_progress(i: int) -> void:
	_mtc_dest.erase(i)
	_mtc_min_dist.erase(i)
	_mtc_no_progress.erase(i)


func _process(delta):
	super._process(delta)

	if _test_done:
		return

	# GPUArena._check_victory() sets victory_achieved + combat_active=false
	# but never calls on_victory(), so detect it here.
	if victory_achieved:
		on_victory(gpu_state_reader.get_battle_result().get("winner", -1))
		return

	var states = _all_states
	if not combat_active or states.size() == 0:
		return

	# Track every unit's progress toward its cast destination while it is in
	# MOVING_TO_CAST. Circling = the distance never reaches a new minimum.
	for i in range(mini(states.size(), units.size())):
		var s = states[i]
		if s.get("hp", 0) <= 0 or s.get("state", 0) != GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
			_clear_progress(i)
			continue

		var pos = Vector2i(s.get("pos_x", 0), s.get("pos_z", 0))
		var dest = Vector2i(s.get("dest_x", 0), s.get("dest_z", 0))
		var dist = absi(pos.x - dest.x) + absi(pos.y - dest.y)

		if not _mtc_dest.has(i) or _mtc_dest[i] != dest:
			# Entered the state, or the cast destination changed: (re)start tracking.
			_mtc_dest[i] = dest
			_mtc_min_dist[i] = dist
			_mtc_no_progress[i] = 0
		elif dist < _mtc_min_dist[i]:
			_mtc_min_dist[i] = dist
			_mtc_no_progress[i] = 0
		else:
			_mtc_no_progress[i] += 1

		if _mtc_no_progress.get(i, 0) >= NO_PROGRESS_LIMIT:
			_finish_test(false, "%s circling in MOVING_TO_CAST: no progress toward cast dest for %d ticks" % [units[i].name, NO_PROGRESS_LIMIT])
			return

	if current_tick >= CHECK_TICKS:
		_finish_test(true, "No unit circling in MOVING_TO_CAST after %d ticks" % CHECK_TICKS)


func _finish_test(passed: bool, message: String):
	_test_done = true
	if passed:
		print("\n[PASS] %s" % message)
	else:
		print("\n[FAIL] %s" % message)

	DebugConfig.combat_seed = 0
	DebugConfig.combat_autostart = false

	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
