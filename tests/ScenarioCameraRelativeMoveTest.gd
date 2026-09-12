extends Node
## Tests for the {73} Camera Move (relative) pre-patcher and the {63} Camera Speed
## Curve ease. RE (100% done, byte-exact static + dynamic):
## research/working_documents/CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md.
##
## {73} is the scenario-6 PC 386 "teleport to a nonsense wide shot" fix: on PSX it
## overwrites the FOLLOWING {19} Camera's first 7 operands with `live_pose + delta`
## (Time untouched, sentinel 0x2710 = keep), so the authored `Zoom=0` becomes
## `live(4096)+0` = 4096 instead of the ortho blow-up. We mirror it with the same
## stash/consume seam {1F} Focus uses: {73} stashes deltas, the next {19} consumes.
##
## {63} arms a per-op ease curve `prog = (16−I)/16·t + I/16·easeQuad(t)` (§4.7,
## bit-exact to hardware for 0xAA, ±1/1024).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCameraRelativeMoveTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


# --- minimal PlayerCamera stub (same shape as ScenarioFocusTest) ------------
class StubCamera extends Node3D:
	var focus_point: Node3D
	var camera: Camera3D
	var last_pos: Vector3 = Vector3.ZERO
	var last_rot: Vector3 = Vector3.ZERO
	var last_ortho: float = 0.0
	var takeover_requested: bool = false

	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		add_child(camera)

	func request_takeover(_who) -> void:
		takeover_requested = true

	func apply_takeover(pos: Vector3, rot: Vector3, ortho: float) -> void:
		last_pos = pos
		last_rot = rot
		last_ortho = ortho
		global_position = pos


func _ready() -> void:
	_test_decode_deltas()
	_test_prepatch_byte_exact()
	_test_keep_sentinel()
	_test_no_prior_camera_keeps_authored()
	_test_speed_curve_nibbles()
	_test_curve63_fixture()
	_test_curve63_linear_when_a0()
	_test_speed_curve_wired_into_ease()
	_test_handlers_registered_not_skip()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioCameraRelativeMoveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCameraRelativeMoveTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCameraRelativeMoveTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraRelativeMoveTest")
		get_tree().quit(0)


# --- {73} decode ------------------------------------------------------------

func _test_decode_deltas() -> void:
	# PC 387 (scenario 6): 7 s16 deltas [X,Z,Y,Angle,MapRot,CamRot,Zoom].
	var d := ScenarioDecode.camera_move_relative(
		_deltas_reader([0, 128, 0, 128, 1024, 0, 0]))
	_assert_eq(d, [0, 128, 0, 128, 1024, 0, 0], "{73} PC387 deltas decode")

	# PC 428 cross-validation: Z delta 0xF810 sign-extends to −2032; 0x2710 (10000)
	# is the "keep" sentinel and decodes as its literal value (honored at patch time).
	var d2 := ScenarioDecode.camera_move_relative(
		_deltas_reader([10000, 0xF810, 10000, 128, 10000, 10000, 0]))
	_assert_eq(d2, [10000, -2032, 10000, 128, 10000, 10000, 0], "{73} PC428 signed deltas decode")


# --- {73} pre-patch (the teleport fix) --------------------------------------

func _test_prepatch_byte_exact() -> void:
	# Byte-exact dynamic proof (§4.4). Seed the director with the PC 218 live pose,
	# stash the PC 387 {73} deltas, then run the PC 388 {19} Camera (whose authored
	# operands are don't-care filler). The pre-patch must turn the operands into
	# `live + delta`, which _op_camera stores into _last_camera_params — so that
	# dict is the observable patched-operand set. Crucially Zoom 0 → live(4096)+0 =
	# 4096 (no ortho blow-up) and Time is left = the {19}'s own 64.
	var vm := _make_vm()
	_attach_camera(vm)
	var cd := vm.camera_director
	# PC 218 {19} Camera pose = the live scratch {73} reads (byte-exact, §4.6).
	cd._last_camera_params = {"x": 776, "y": 1432, "z": -316, "angle": 270,
		"map_rot": 1536, "cam_rot": 0, "zoom": 4096, "time": 60}
	cd._has_last_camera = true

	cd._op_camera_move_relative(_inst("Camera Move Relative",
		_deltas_params([0, 128, 0, 128, 1024, 0, 0]), 0x73))
	_assert_true(not cd._pending_camera_delta.is_empty(), "{73} stashes a pending delta")

	# PC 388 {19}: authored operands are filler (overwritten by {73}); Zoom=0.
	cd._op_camera(_inst("Camera",
		{"X": 0, "Z": 128, "Y": 0, "Angle": 128, "Map Rotation": 1024,
			"Camera Rotation": 0, "Zoom": 0, "Time": 64}))

	_assert_true(cd._pending_camera_delta.is_empty(), "pending delta cleared after Camera")
	var p: Dictionary = cd._last_camera_params
	_assert_eq(p.get("x"), 776, "patched X = 776+0")
	_assert_eq(p.get("z"), -188, "patched Z = -316+128")
	_assert_eq(p.get("y"), 1432, "patched Y = 1432+0")
	_assert_eq(p.get("angle"), 398, "patched Angle = 270+128")
	_assert_eq(p.get("map_rot"), 2560, "patched MapRot = 1536+1024")
	_assert_eq(p.get("cam_rot"), 0, "patched CamRot = 0+0")
	_assert_eq(p.get("zoom"), 4096, "patched Zoom = live 4096 (not the authored 0)")
	_assert_eq(p.get("time"), 64, "Time untouched = the {19}'s own 64")


func _test_keep_sentinel() -> void:
	# A delta of 0x2710 (10000) means "keep this field at its live value" — the
	# rest of the fields still take live+delta. (Not exercised at PC 386, but other
	# scenes use it; §5.3.)
	var vm := _make_vm()
	_attach_camera(vm)
	var cd := vm.camera_director
	cd._last_camera_params = {"x": 776, "y": 1432, "z": -316, "angle": 270,
		"map_rot": 1536, "cam_rot": 0, "zoom": 4096, "time": 60}
	cd._has_last_camera = true
	# Keep X and Zoom; add to the rest.
	cd._op_camera_move_relative(_inst("Camera Move Relative",
		_deltas_params([10000, 100, 0, 0, 0, 0, 10000]), 0x73))
	cd._op_camera(_inst("Camera",
		{"X": 0, "Z": 0, "Y": 0, "Angle": 0, "Map Rotation": 0,
			"Camera Rotation": 0, "Zoom": 0, "Time": 8}))
	var p: Dictionary = cd._last_camera_params
	_assert_eq(p.get("x"), 776, "0x2710 keeps X at live 776")
	_assert_eq(p.get("z"), -216, "Z = live -316 + 100")
	_assert_eq(p.get("zoom"), 4096, "0x2710 keeps Zoom at live 4096")


func _test_no_prior_camera_keeps_authored() -> void:
	# {73} with no prior Camera this run (no live pose to key off) → the authored
	# operands stand (mirrors the Focus absent-unit abort). Defensive: scenario 6
	# always seeds a Camera first (PC 218).
	var vm := _make_vm()
	_attach_camera(vm)
	var cd := vm.camera_director
	_assert_true(not cd._has_last_camera, "no prior Camera at start")
	cd._op_camera_move_relative(_inst("Camera Move Relative",
		_deltas_params([500, 500, 500, 500, 500, 500, 500]), 0x73))
	cd._op_camera(_inst("Camera",
		{"X": 560, "Z": 0, "Y": 336, "Angle": 12, "Map Rotation": 34,
			"Camera Rotation": 0, "Zoom": 4096, "Time": 1}))
	_assert_true(cd._pending_camera_delta.is_empty(), "pending delta cleared even on fallback")
	var p: Dictionary = cd._last_camera_params
	_assert_eq(p.get("x"), 560, "no-seed → authored X stands (delta ignored)")
	_assert_eq(p.get("angle"), 12, "no-seed → authored Angle stands")
	_assert_eq(p.get("zoom"), 4096, "no-seed → authored Zoom stands")


# --- {63} Camera Speed Curve ------------------------------------------------

# §4.7 regression fixture: 0xAA ease-in-out, yaw 1536→2560 over Time=64 frames,
# indexed by frame (65 samples). The closed form must reproduce these to ±1.
const _CURVE63_AA_YAW := [
	1536, 1543, 1550, 1557, 1566, 1574, 1584, 1594, 1604, 1616, 1628,
	1640, 1654, 1667, 1682, 1696, 1712, 1728, 1746, 1763, 1782,
	1800, 1820, 1840, 1860, 1882, 1904, 1926, 1950, 1973, 1998,
	2023, 2048, 2074, 2099, 2124, 2148, 2171, 2193, 2215, 2236,
	2257, 2277, 2296, 2316, 2334, 2351, 2368, 2384, 2400, 2415,
	2430, 2444, 2456, 2469, 2481, 2492, 2503, 2513, 2523, 2532,
	2540, 2547, 2554, 2560]


func _test_speed_curve_nibbles() -> void:
	# 0xAA (the only {63} byte in scenario 6): intensity 10, A=2 (ease-in-out),
	# B=2 (all fields eased). Plus two game-wide bytes for coverage.
	var aa := ScenarioDecode.camera_speed_curve(0xAA)
	_assert_eq(aa.intensity, 10, "0xAA intensity = 10")
	_assert_eq(aa.accel_shape, 2, "0xAA A = 2 (ease-in-out)")
	_assert_eq(aa.field_gate, 2, "0xAA B = 2 (all fields)")
	var b41 := ScenarioDecode.camera_speed_curve(0x41)
	_assert_eq(b41.intensity, 4, "0x41 intensity = 4")
	_assert_eq(b41.accel_shape, 1, "0x41 A = 1 (ease-in)")
	_assert_eq(b41.field_gate, 0, "0x41 B = 0 (position-only)")


func _test_curve63_fixture() -> void:
	# Reproduce the live per-vblank yaw curve to ±1 unit (§4.7 claim: max 1/1024).
	var cd := _make_vm().camera_director
	var worst := 0
	for frame in range(_CURVE63_AA_YAW.size()):
		var prog: float = cd._curve63(float(frame) / 64.0, 0xAA)
		var yaw := int(round(1536.0 + 1024.0 * prog))
		var err: int = abs(yaw - _CURVE63_AA_YAW[frame])
		worst = maxi(worst, err)
	_assert_true(worst <= 1, "_curve63(0xAA) reproduces the fixture to <=1 (worst=%d)" % worst)


func _test_curve63_linear_when_a0() -> void:
	# A (low 2 bits) == 0 → pure linear regardless of intensity nibble.
	var cd := _make_vm().camera_director
	_assert_true(absf(cd._curve63(0.3, 0x40) - 0.3) < 1e-6, "A=0 → linear at 0.3")
	_assert_true(absf(cd._curve63(0.75, 0xF0) - 0.75) < 1e-6, "A=0 → linear at 0.75 (any intensity)")


func _test_speed_curve_wired_into_ease() -> void:
	# {63} arms the per-op ease that the following Camera's lerp uses (via _curve).
	# A plain Camera with no {63} stays on the global (LINEAR) curve.
	var vm := _make_vm()
	_attach_camera(vm)
	var cd := vm.camera_director
	cd._op_camera_speed_curve(_inst("Camera Speed Curve", {"Curve": 0xAA}, 0x63))
	_assert_eq(cd._pending_speed_curve, 0xAA, "{63} stashes the curve byte")
	cd._op_camera(_inst("Camera",
		{"X": 0, "Z": 0, "Y": 0, "Angle": 0, "Map Rotation": 0,
			"Camera Rotation": 0, "Zoom": 4096, "Time": 64}))
	_assert_eq(cd._pending_speed_curve, 0, "curve consumed by the Camera")
	# _curve now follows the 0xAA ease-in-out, not linear (done=0.25 → ~0.1719).
	_assert_true(absf(cd._curve(0.25) - cd._curve63(0.25, 0xAA)) < 1e-6,
		"armed Camera eases via _curve63")
	_assert_true(absf(cd._curve(0.25) - 0.25) > 0.01, "0xAA ease != linear at 0.25")
	# A subsequent plain Camera (no {63}) reverts to the global LINEAR curve.
	cd._op_camera(_inst("Camera",
		{"X": 0, "Z": 0, "Y": 0, "Angle": 0, "Map Rotation": 0,
			"Camera Rotation": 0, "Zoom": 4096, "Time": 64}))
	_assert_true(absf(cd._curve(0.25) - 0.25) < 1e-6, "plain Camera → linear again")


# --- dispatch wiring --------------------------------------------------------

func _test_handlers_registered_not_skip() -> void:
	# {73}/{63} must dispatch to the real director handlers — NOT be clobbered by
	# the registrar's auto-skip loop for "Unknown" catalog opcodes (which only
	# excludes them once the catalog names them). Regression guard for the rename.
	var vm := _make_vm()
	_assert_handler(vm, EventInstruction.CAMERA_MOVE_RELATIVE, "_op_camera_move_relative")
	_assert_handler(vm, EventInstruction.CAMERA_SPEED_CURVE, "_op_camera_speed_curve")


func _assert_handler(vm, op: int, method: String) -> void:
	var op_name := EventInstructionSet.name_of(op)
	var h = vm._handlers.get(op, null)
	_assert_true(h != null, "%s handler registered" % op_name)
	if h != null:
		_assert_eq((h as Callable).get_method(), method,
			"%s -> %s (not skip/halt)" % [op_name, method])


# --- fixtures ---------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	vm.map_size_z = 0  # disable depth-flip + vertical datum for exact round-trips
	_nodes.append(vm)
	return vm


func _attach_camera(vm: ScenarioVMClass) -> StubCamera:
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	_nodes.append(cam)
	return cam


func _inst(name: String, params: Dictionary, opcode: int = -1) -> Dictionary:
	var plist: Array = []
	for k in params:
		plist.append({"name": k, "value": params[k]})
	return {"name": name, "opcode": opcode, "params": plist}


# Build a {73}'s params array (7 s16 delta operands) for _inst.
func _deltas_params(vals: Array) -> Dictionary:
	# _inst keys off a dict; use a stable positional order (dup names collapse in a
	# dict, so give each a distinct positional name — decode reads positionally).
	var out: Dictionary = {}
	for i in range(vals.size()):
		out["d%d" % i] = int(vals[i]) & 0xFFFF
	return out


# Mint a reader for a {73}'s 7 s16 delta operands (all 2-byte signed).
func _deltas_reader(vals: Array) -> EventInstructionArgs:
	var arr: Array = []
	for v in vals:
		arr.append({"name": "Delta", "value": int(v) & 0xFFFF, "bytes": 2})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


# --- assert helpers ---------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
