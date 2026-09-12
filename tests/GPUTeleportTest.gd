extends "res://src/scenes/GPUArena.gd"

## GPU Teleport Test
##
## Uses seed 3601067600983631927 which previously caused a visual teleportation
## mid-battle. Tracks visual positions per-frame and flags any jump greater than
## TELEPORT_THRESHOLD that isn't explained by a DEAD/VICTORIOUS transition.
## PASS: Combat resolves (or reaches max ticks) with zero teleport events.
## FAIL: Any unit teleports visually during combat.

const TELEPORT_SEED: int = 3601067600983631927
const CHECK_TICKS: int = 2000
const TELEPORT_DIST_THRESHOLD: float = 0.4

var _test_done: bool = false
var _prev_visual_pos: Dictionary = {}   # unit_idx -> Vector3
var _teleport_events: Array = []        # {unit_idx, unit_name, tick, distance, from_pos, to_pos}


func _ready():
	DebugConfig.combat_seed = TELEPORT_SEED
	DebugConfig.combat_autostart = true
	regression_logging = false
	max_ticks = CHECK_TICKS

	super._ready()


func get_test_name() -> String:
	return "GPU Teleport Test"


func _process(delta):
	super._process(delta)

	if _test_done:
		return

	# Check for visual teleports every frame while combat is running
	if combat_active and _all_states.size() > 0:
		_check_visual_teleports()

	# Victory or timeout — report results
	if victory_achieved or current_tick >= CHECK_TICKS:
		_finish_test()


func _check_visual_teleports():
	for i in range(mini(_all_states.size(), units.size())):
		var visual_pos: Vector3 = _visual_bridge.visual_positions.get(i, Vector3.ZERO)

		# Skip if no previous position yet
		if not _prev_visual_pos.has(i):
			_prev_visual_pos[i] = visual_pos
			continue

		var prev_pos: Vector3 = _prev_visual_pos[i]
		_prev_visual_pos[i] = visual_pos

		# Compute horizontal jump distance (ignore Y — height changes are normal)
		var jump_dist: float = Vector2(visual_pos.x - prev_pos.x, visual_pos.z - prev_pos.z).length()

		if jump_dist <= TELEPORT_DIST_THRESHOLD:
			continue

		# Skip teleport detection for units transitioning to DEAD or VICTORIOUS
		var state: int = _all_states[i].get("state", 0)
		if state == GPUConstants.LOGICAL_ACTIVITY_DYING or state == GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
			continue

		var unit_name: String = units[i].name if i < units.size() else "Unit%d" % i
		var event := {
			"unit_idx": i,
			"unit_name": unit_name,
			"tick": current_tick,
			"distance": jump_dist,
			"from_pos": prev_pos,
			"to_pos": visual_pos,
		}
		_teleport_events.append(event)


func _finish_test():
	_test_done = true
	var passed: bool = _teleport_events.size() == 0

	if passed:
		print("\n[PASS] No visual teleports detected in %d ticks (seed %d)" % [current_tick, TELEPORT_SEED])
	else:
		print("\n[FAIL] %d visual teleport(s) detected (seed %d):" % [_teleport_events.size(), TELEPORT_SEED])
		for event in _teleport_events:
			print("  T%d: %s jumped %.2f units (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)" % [
				event["tick"], event["unit_name"], event["distance"],
				event["from_pos"].x, event["from_pos"].y, event["from_pos"].z,
				event["to_pos"].x, event["to_pos"].y, event["to_pos"].z])

	DebugConfig.combat_seed = 0
	DebugConfig.combat_autostart = false

	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
