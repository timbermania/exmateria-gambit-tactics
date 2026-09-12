extends Node
## Tests for the cinematic Unit Anim bytecode walker
## (`ScenarioVM.CinematicWalkState`). The walker tracks one unit's
## `cinematic_seq.json` opcode list per VM tick — honoring LoadFrameWait
## timing, terminating on PauseAnimation / EndAnimation, and routing frame
## bytes < 0xD2 through the TYPE1 SHP path vs ≥ 0xD2 through EVTCHR.
##
## Pins down:
##   * LoadFrameWait sequence: first frame renders immediately, then
##     subsequent advance() calls count `wait` ticks down before the next
##     frame is popped + rendered.
##   * Low-byte routing: fb < 0xD2 calls `load_frame_by_id(TYPE1, fb)`.
##   * High-byte routing: fb ≥ 0xD2 calls `enter_cinematic_mode(seg_id)` +
##     `load_cinematic_frame(seg_id, fb)` — V14 (2026-06-27): no palette_row
##     arg; palette comes from the unit's body_palette_row uniform.
##   * PauseAnimation terminates the walker; further advance() are no-ops.
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/ScenarioCinematicWalkerTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


# Records every shader-write call so the test can assert which routing path
# fired and in what order. Mirrors the surface ScenarioVM.CinematicWalkState
# touches on `unit.sprite_layers`: enter_cinematic_mode + load_cinematic_frame
# (high byte) and load_frame_by_id (low byte).
class MockSpriteLayers extends RefCounted:
	# Ordered list of (call_name, args...) tuples — one entry per shader write.
	# Tests pop / scan this to verify exact behavior.
	var calls: Array = []

	func enter_cinematic_mode(segment_id: int) -> bool:
		calls.append(["enter_cinematic_mode", segment_id])
		return true

	func load_cinematic_frame(segment_id: int, frame_id: int, atlas_y_offset: int = 0) -> bool:
		calls.append(["load_cinematic_frame", segment_id, frame_id, atlas_y_offset])
		return true

	func load_frame_by_id(layer: int, frame_id: int, is_first_frame: bool = false) -> void:
		calls.append(["load_frame_by_id", layer, frame_id, is_first_frame])


# Minimal unit-shaped object; the walker only touches `sprite_layers`.
class MockUnit extends RefCounted:
	var sprite_layers


func _make_walker(opcodes: Array, seg_id: int = 0):
	var slm := MockSpriteLayers.new()
	var unit := MockUnit.new()
	unit.sprite_layers = slm
	var walker = ScenarioVMClass.CinematicWalkState.new()
	walker.unit = unit
	walker.seg_id = seg_id
	walker.opcodes = opcodes
	return [walker, slm]


func _ready() -> void:
	_test_walker_renders_all_loadframewait_in_sequence()
	_test_walker_routes_low_byte_to_type1()
	_test_walker_routes_high_byte_to_evtchr()
	_test_walker_pauseanimation_holds_last_frame()
	_test_walker_passes_atlas_y_offset_to_load_cinematic_frame()
	_test_walker_incrementloop_loops_forever()

	print("\n=== ScenarioCinematicWalkerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioCinematicWalkerTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCinematicWalkerTest")
		get_tree().quit(0)


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _last_high_render(slm) -> int:
	# Returns the most recent `load_cinematic_frame` frame_id, or -1.
	for i in range(slm.calls.size() - 1, -1, -1):
		var c = slm.calls[i]
		if c[0] == "load_cinematic_frame":
			return int(c[2])
	return -1


func _last_low_render(slm) -> int:
	# Returns the most recent `load_frame_by_id` frame_id, or -1.
	for i in range(slm.calls.size() - 1, -1, -1):
		var c = slm.calls[i]
		if c[0] == "load_frame_by_id":
			return int(c[2])
	return -1


# --- Tests -------------------------------------------------------------------

func _test_walker_renders_all_loadframewait_in_sequence() -> void:
	# Bytecode: F3 t6, F4 t2, Pause — Ovelia's nod (anim 0x263). Per the
	# decrement-first advance() design:
	#   advance #1  → pops F3, renders 0xF3, ticks_left = 6
	#   advance #2..#6  → ticks_left decrements 5,4,3,2,1
	#   advance #7  → ticks_left 1→0, pops F4, renders 0xF4, ticks_left = 2
	#   advance #8  → ticks_left → 1
	#   advance #9  → ticks_left 1→0, pops Pause → done = true
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xF3, "op_code_param_1": 6},
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xF4, "op_code_param_1": 2},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes)
	var walker = pair[0]
	var slm = pair[1]

	walker.advance()
	_assert_eq(_last_high_render(slm), 0xF3, "advance #1: 0xF3 rendered first")

	# 6 more advances should land us on F4 render.
	for i in range(6):
		walker.advance()
	_assert_eq(_last_high_render(slm), 0xF4, "advance #7 (6 after F3): 0xF4 rendered")
	_assert_true(not walker.done, "walker still active after F4 render")

	# 2 more advances → Pause → done.
	walker.advance()
	_assert_true(not walker.done, "advance #8: still active (1 tick remaining)")
	walker.advance()
	_assert_true(walker.done, "advance #9: Pause consumed, walker done")


func _test_walker_routes_low_byte_to_type1() -> void:
	# Bytecode: low byte 0x10 followed by Pause. fb < 0xD2 must go through the
	# TYPE1 SHP path, NOT enter_cinematic_mode + load_cinematic_frame.
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0x10, "op_code_param_1": 2},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes)
	var walker = pair[0]
	var slm = pair[1]

	walker.advance()

	# load_frame_by_id fired with the right frame.
	_assert_eq(_last_low_render(slm), 0x10, "TYPE1 route: load_frame_by_id(0x10) called")
	# No cinematic-path calls leaked.
	var had_cinematic := false
	for c in slm.calls:
		if c[0] == "enter_cinematic_mode" or c[0] == "load_cinematic_frame":
			had_cinematic = true
			break
	_assert_true(not had_cinematic,
		"TYPE1 route: neither enter_cinematic_mode nor load_cinematic_frame called")


func _test_walker_routes_high_byte_to_evtchr() -> void:
	# Bytecode: high byte 0xF3 + Pause. fb >= 0xD2 routes through EVTCHR,
	# entering cinematic mode and loading the frame on the BODY layer.
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xF3, "op_code_param_1": 1},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes, 0)
	var walker = pair[0]
	var slm = pair[1]

	walker.advance()

	# Both calls fired in the expected order with the expected args.
	var saw_enter := false
	var saw_frame := false
	for c in slm.calls:
		if c[0] == "enter_cinematic_mode":
			_assert_eq(int(c[1]), 0, "enter_cinematic_mode: seg_id == 0")
			saw_enter = true
		elif c[0] == "load_cinematic_frame":
			_assert_eq(int(c[1]), 0, "load_cinematic_frame: seg_id == 0")
			_assert_eq(int(c[2]), 0xF3, "load_cinematic_frame: frame_id == 0xF3")
			saw_frame = true
	_assert_true(saw_enter, "EVTCHR route: enter_cinematic_mode called")
	_assert_true(saw_frame, "EVTCHR route: load_cinematic_frame called")
	# And it did NOT fall through to load_frame_by_id.
	_assert_eq(_last_low_render(slm), -1,
		"EVTCHR route: load_frame_by_id NOT called for high byte")


func _test_walker_passes_atlas_y_offset_to_load_cinematic_frame() -> void:
	# A non-zero atlas_y_offset on the walker must flow through to every
	# load_cinematic_frame call so the BODY shader samples the right atlas
	# row. Mirrors the per-uid +0x7a fix; without this plumbing the
	# "Agrias morphs into Ovelia" bug persists even after the offset map
	# is set.
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xE7, "op_code_param_1": 1},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes, 0)
	var walker = pair[0]
	var slm = pair[1]
	walker.atlas_y_offset = -120  # would shift row 120 → row 0 for a "head bowed" pose

	walker.advance()

	var saw_with_offset := false
	for c in slm.calls:
		if c[0] == "load_cinematic_frame":
			_assert_eq(int(c[3]), -120,
				"load_cinematic_frame: atlas_y_offset == -120")
			saw_with_offset = true
	_assert_true(saw_with_offset, "atlas_y_offset path: load_cinematic_frame called with the offset")


func _test_walker_incrementloop_loops_forever() -> void:
	# The female-knight wounded walk (anim 0x26A): six frames, IncrementLoop,
	# PauseAnimation. IncrementLoop (0xFFD5) must loop the sequence back to frame
	# 0 — the unit keeps walking while a Sprite Move slides it into place — and the
	# trailing PauseAnimation stays unreachable. Before the fix the walker skipped
	# IncrementLoop, hit PauseAnimation after one cycle, and froze mid-walk.
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xDB, "op_code_param_1": 2},
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xDC, "op_code_param_1": 2},
		{"op_code_name": "IncrementLoop"},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes, 0)
	var walker = pair[0]
	var slm = pair[1]

	# advance #1 → 0xDB, ticks_left=2 ; #2 → 1 ; #3 → 0xDC, ticks_left=2 ; #4 → 1 ;
	# #5 → IncrementLoop resets, 0xDB rendered again. Drive 5 ticks and assert we
	# wrapped back to 0xDB rather than terminating.
	walker.advance()
	_assert_eq(_last_high_render(slm), 0xDB, "loop: first frame 0xDB")
	walker.advance(); walker.advance()
	_assert_eq(_last_high_render(slm), 0xDC, "loop: second frame 0xDC")
	walker.advance(); walker.advance()
	_assert_eq(_last_high_render(slm), 0xDB, "loop: wrapped back to 0xDB (did not Pause)")
	_assert_true(not walker.done, "loop: walker still active after one full cycle")

	# Drive many more cycles — it must never set done (PauseAnimation unreachable).
	for i in range(200):
		walker.advance()
	_assert_true(not walker.done, "loop: walker never terminates across 200+ ticks")


func _test_walker_pauseanimation_holds_last_frame() -> void:
	# After PauseAnimation marks done = true, subsequent advance() calls are
	# no-ops: no new shader writes, no opcodes consumed, done stays true.
	var opcodes: Array = [
		{"op_code_name": "LoadFrameWait", "op_code_param_0": 0xF3, "op_code_param_1": 1},
		{"op_code_name": "PauseAnimation"},
	]
	var pair = _make_walker(opcodes)
	var walker = pair[0]
	var slm = pair[1]

	# Drive the walker through F3 → tick → Pause to reach done.
	walker.advance()  # render F3, ticks_left=1
	walker.advance()  # ticks_left → 0
	walker.advance()  # Pause consumed → done
	_assert_true(walker.done, "Pause consumed: walker.done == true")
	var call_count_at_done: int = slm.calls.size()

	# Three more advances should not modify shader state or done flag.
	for i in range(3):
		walker.advance()
	_assert_eq(slm.calls.size(), call_count_at_done,
		"post-Pause advance() calls: no new shader writes")
	_assert_true(walker.done, "post-Pause advance() calls: walker.done stays true")
