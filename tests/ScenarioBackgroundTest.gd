extends Node
## Tests for ScenarioVM's {2E} Background — the full-screen Gouraud gradient
## backdrop and the Orbonne pre-battle lightning flash. RE is complete + live
## byte-exact (research/working_documents/LIGHTNING_FLASH_OPCODE_2E_BACKGROUND.md);
## this is the port.
##
## Pure-logic asserts (no headful needed): the 8 operands decode, {2E} dispatches
## to a real handler (not the old skip stub), and the ScenarioBackground ramp
## model reproduces the live-captured convergence EXACTLY — the flash rises to
## peak over Time*8=8 frames then the decay falls over Time*8=32 frames, both
## linear, landing on target. The trace values below are the live PSX capture
## (living doc §4): top R 48→65→82→…→184 over 8 frames, botB 96→61 in lockstep.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioBackgroundTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


func _ready() -> void:
	_test_decode_operands()
	_test_handler_registered_not_skip()
	_test_snap_sets_corners_instantly()
	_test_flash1_ramp_matches_live_trace()
	_test_decay_ramp_frame_count()
	_test_ramp_frames_for_time()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioBackgroundTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioBackgroundTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioBackgroundTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioBackgroundTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _bg_reader(rt: int, gt: int, bt: int, rb: int, gb: int, bb: int, time: int, unk: int) -> EventInstructionArgs:
	return _reader({
		"Red (Top)": rt, "Green (Top)": gt, "Blue (Top)": bt,
		"Red (Bottom)": rb, "Green (Bottom)": gb, "Blue (Bottom)": bb,
		"Time": time, "Unknown": unk,
	})


func _test_decode_operands() -> void:
	# Live scenario-4 FLASH 1 (chunk inst 27): Top(184,188,119) Bot(16,29,61)
	# Time=1 Unk=1.
	var f := ScenarioDecode.background(_bg_reader(184, 188, 119, 16, 29, 61, 1, 1))
	_assert_eq(f.top, Vector3(184, 188, 119), "flash1 top decoded (0..255)")
	_assert_eq(f.bottom, Vector3(16, 29, 61), "flash1 bottom decoded (0..255)")
	_assert_eq(f.time, 1, "flash1 Time decoded")
	_assert_true(not f.snap, "flash1 Time=1 is a ramp, not snap")

	# Rest set (inst 11): Time=0 → snap. Unk ignored (path selector only).
	var r := ScenarioDecode.background(_bg_reader(48, 56, 48, 48, 56, 96, 0, 0))
	_assert_eq(r.top, Vector3(48, 56, 48), "rest top decoded")
	_assert_eq(r.bottom, Vector3(48, 56, 96), "rest bottom decoded (blue storm floor)")
	_assert_true(r.snap, "rest Time=0 snaps instantly")


func _test_handler_registered_not_skip() -> void:
	var vm := _make_vm()
	var h = vm._handlers.get(EventInstruction.BACKGROUND, null)
	_assert_true(h != null, "{2E} Background handler registered")
	if h != null:
		_assert_eq((h as Callable).get_method(), "_op_background",
			"{2E} -> _op_background (not the old skip stub)")


# --- ramp model -------------------------------------------------------------

func _test_snap_sets_corners_instantly() -> void:
	var bg := ScenarioBackground.new()
	bg.apply(Vector3(48, 56, 48), Vector3(48, 56, 96), 0)
	_assert_true(not bg.is_ramping(), "Time=0 leaves no ramp in flight")
	_assert_vec_near(bg.top * 255.0, Vector3(48, 56, 48), "snap top lands immediately")
	_assert_vec_near(bg.bottom * 255.0, Vector3(48, 56, 96), "snap bottom lands immediately")
	# A snapped model does not tick.
	_assert_true(not bg.tick(), "snapped model reports no in-flight ramp")


func _test_flash1_ramp_matches_live_trace() -> void:
	# Live PSX top-R convergence for FLASH 1 (living doc §4): from rest 48 to 184
	# over Time*8 = 8 frames, +17/frame. Bottom-B: 96 -> 61 in lockstep.
	var bg := ScenarioBackground.new()
	bg.apply(Vector3(48, 56, 48), Vector3(48, 56, 96), 0)  # start at rest (snap)
	bg.apply(Vector3(184, 188, 119), Vector3(16, 29, 61), 1)  # arm flash (Time=1)

	# The live trace logged the PSX high-16-bits (>>16 = floor), so compare the
	# floor of our (more precise, fractionally-exact) internal value to the trace.
	var expected_topR := [65, 82, 99, 116, 133, 150, 167, 184]
	var expected_botB := [91, 87, 82, 78, 74, 69, 65, 61]
	for i in expected_topR.size():
		var live := bg.tick()
		_assert_true(live, "flash frame %d is still ramping" % (i + 1))
		_assert_eq(int(floor(bg.top.x * 255.0)), expected_topR[i],
			"flash top-R frame %d == %d (live trace)" % [i + 1, expected_topR[i]])
		_assert_eq(int(floor(bg.bottom.z * 255.0)), expected_botB[i],
			"flash bot-B frame %d == %d (live trace)" % [i + 1, expected_botB[i]])
	# Landed exactly on target; no further ramp.
	_assert_true(not bg.is_ramping(), "flash ramp done after exactly 8 frames")
	_assert_true(not bg.tick(), "no 9th ramp frame")
	_assert_vec_near(bg.top * 255.0, Vector3(184, 188, 119), "flash top lands on target")
	_assert_vec_near(bg.bottom * 255.0, Vector3(16, 29, 61), "flash bottom lands on target")


func _test_decay_ramp_frame_count() -> void:
	# Decay (inst 30): Time=4 → 32 frames, -4.25/frame on top-R (184 -> 48).
	var bg := ScenarioBackground.new()
	bg.apply(Vector3(184, 188, 119), Vector3(16, 29, 61), 0)  # start at flash peak
	bg.apply(Vector3(48, 56, 48), Vector3(48, 56, 96), 4)     # decay Time=4
	_assert_eq(bg._ramp_total, 32, "Time=4 ramps over 32 frames")
	# After 1 frame: 184 - 4.25 = 179.75.
	bg.tick()
	_assert_near(bg.top.x * 255.0, 179.75, 0.6, "decay top-R after 1 frame ~= 179.75")
	# Run out the remaining 31 frames; must land exactly on rest.
	for _f in 31:
		bg.tick()
	_assert_true(not bg.is_ramping(), "decay done after exactly 32 frames")
	_assert_vec_near(bg.top * 255.0, Vector3(48, 56, 48), "decay top lands on rest")
	_assert_vec_near(bg.bottom * 255.0, Vector3(48, 56, 96), "decay bottom lands on rest")


func _test_ramp_frames_for_time() -> void:
	_assert_eq(ScenarioBackground.ramp_frames_for_time(0), 0, "Time=0 -> 0 frames (snap)")
	_assert_eq(ScenarioBackground.ramp_frames_for_time(1), 8, "Time=1 -> 8 frames")
	_assert_eq(ScenarioBackground.ramp_frames_for_time(4), 32, "Time=4 -> 32 frames")
	# scenario_003 uses large Time bytes (generic handler must cover them).
	_assert_eq(ScenarioBackground.ramp_frames_for_time(254), 2032, "Time=254 -> 2032 frames")


# --- fixtures + asserts -----------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_nodes.append(vm)
	return vm


func _assert_vec_near(got: Vector3, want: Vector3, name: String) -> void:
	_assert_true(got.distance_to(want) < 1.0, name)


func _assert_near(got: float, want: float, tol: float, name: String) -> void:
	if absf(got - want) <= tol:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%.3f want=%.3f tol=%.3f" % [name, got, want, tol])


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
