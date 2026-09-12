extends Node
## Tests for ScenarioVM's {1F} Focus / {38} Focus Speed (camera-focus-on-unit) and
## the {DB}/{E3} Event End terminators. Live-validated RE:
## research/working_documents/FOCUS_OPCODE_1F_INVESTIGATION.md.
##
## Pure-logic asserts (a lightweight stub camera stands in for PlayerCamera):
##  - {1F}/{38} operands decode (FocusIntent: units + auto_map_rotation; Speed).
##  - "Focus"/"Focus Speed" dispatch to real handlers (not skip/halt).
##  - Focus stashes a pending focus; the FOLLOWING Camera re-aims onto the target
##    unit(s)' Godot-world midpoint (X=lateral·112, Z=−up·112, Y=depth·112) and
##    is_idle() goes false→true across the lerp.
##  - Focus with two units centres on their midpoint; absent units → authored pose.
##  - Focus Speed overrides the following Camera's Time.
##  - Event End / Event End 2 end the context cleanly with NO halt (VM keeps
##    _running; unhandled would flip it false).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioFocusTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


# --- minimal PlayerCamera stub ----------------------------------------------
# ScenarioCameraDirector reads: player_camera.global_position,
# .focus_point.global_rotation, .camera.size, and calls request_takeover /
# apply_takeover(pos, rot, ortho). This stub records the last applied pose.
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
	_test_decode_operands()
	_test_focus_map_rotation_picker()
	_test_focus_overrides_authored_map_rotation()
	_test_handlers_registered_not_skip()
	_test_focus_reaims_single_unit()
	_test_focus_midpoint_two_units()
	_test_focus_absent_units_keeps_authored()
	_test_focus_speed_overrides_time_and_lerps()
	_test_event_end_terminates_cleanly()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioFocusTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioFocusTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioFocusTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioFocusTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

# Mint an EventInstructionArgs reader from a name->value dict (the decoder takes
# the typed reader now, not a bare dict). Focus operands are unsigned, so the
# default byte width is fine.
func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_decode_operands() -> void:
	# Live scenario-4/11 operands: Focus(Unit(1), Unit(2), Unknown), Unknown==0 =
	# auto-MAP-ROTATION (operand slot 4), NOT auto-zoom — see ScenarioDecode.FocusIntent.
	var f := ScenarioDecode.focus(_reader({"Unit (1)": 0x17, "Unit (2)": 0x17, "Unknown": 0}))
	_assert_eq(f.unit1, 0x17, "Focus Unit(1) decoded")
	_assert_eq(f.unit2, 0x17, "Focus Unit(2) decoded")
	_assert_true(f.auto_map_rotation, "Unknown==0 → auto_map_rotation true")

	var f2 := ScenarioDecode.focus(_reader({"Unit (1)": 1, "Unit (2)": 4, "Unknown": 5}))
	_assert_eq(f2.unit1, 1, "Focus Unit(1) (distinct) decoded")
	_assert_eq(f2.unit2, 4, "Focus Unit(2) (distinct) decoded")
	_assert_true(not f2.auto_map_rotation, "Unknown!=0 → auto_map_rotation false")


# --- the auto map rotation (FUN_80147318) -----------------------------------

func _test_focus_map_rotation_picker() -> void:
	# `FUN_80147318` returns `live + shortest signed turn to the nearest quadrant of
	# {0xE00,0xA00,0x600,0x200}`. The four quadrants are fixed points; the turn is
	# SIGNED and taken the short way round the 0x1000 wheel; and the return keeps the
	# live value's accumulated turn count (0x1200 stays 0x1200, it does not wrap to
	# 0x200) because PSX reads the RAW scratch yaw and adds the delta.
	var d := _make_vm().camera_director
	for quadrant in [0xE00, 0xA00, 0x600, 0x200]:
		_assert_eq(d._focus_map_rotation(quadrant), quadrant,
			"quadrant 0x%X is its own nearest" % quadrant)
	_assert_eq(d._focus_map_rotation(0x1200), 0x1200, "accumulated turn count survives")
	_assert_eq(d._focus_map_rotation(0xB00), 0xA00, "0xB00 snaps down to 0xA00")
	_assert_eq(d._focus_map_rotation(0x700), 0x600, "0x700 snaps down to 0x600")
	# Across the 0x1000 seam: 0x1080 is 0x080 past the turn, so the nearest quadrant is
	# 0x200 ONE TURN UP (+0x180) rather than 0xE00 below it (−0x280) — the turn must
	# cross the seam upward instead of wrapping the result back into [0,0x1000).
	_assert_eq(d._focus_map_rotation(0x1080), 0x1200, "shortest turn crosses the seam upward")
	# Exactly on the turn boundary both neighbours are 0x200 away; PSX's compare is a
	# strict `slt`, so the FIRST table entry to reach that distance keeps it — 0xE00 is
	# index 0, so the tie turns DOWN through the seam.
	_assert_eq(d._focus_map_rotation(0x1000), 0xE00, "a tie goes to the earlier table entry")


func _test_focus_overrides_authored_map_rotation() -> void:
	# The Gariland victory beat in one assert: a settled camera at map rotation 0x600,
	# then Focus(Unknown=0) + a Camera authoring 0xE00. PSX holds 0x600 (the authored
	# operand is overwritten before the Camera task reads it); keeping 0xE00 whipped the
	# port 180°. Unknown!=0 leaves the authored rotation alone.
	var vm := _make_vm()
	_attach_camera(vm)
	var d := vm.camera_director
	_spawn_unit(vm, 0x17, Vector3(6.5, 3.0, 4.5))

	var settle := _camera_params(0, 0, 0, 1)
	settle["Map Rotation"] = 0x600
	d._op_camera(_inst("Camera", settle))
	_assert_eq(int(d._last_camera_params["map_rot"]), 0x600, "live pose seeded at 0x600")

	var authored := _camera_params(1000, 2000, 3000, 1)
	authored["Map Rotation"] = 0xE00
	d._op_focus(_inst("Focus", {"Unit (1)": 0x17, "Unit (2)": 0x17, "Unknown": 0}))
	d._op_camera(_inst("Camera", authored.duplicate()))
	_assert_eq(int(d._last_camera_params["map_rot"]), 0x600,
		"auto Focus keeps the live quadrant, not the authored 0xE00")

	d._op_focus(_inst("Focus", {"Unit (1)": 0x17, "Unit (2)": 0x17, "Unknown": 1}))
	d._op_camera(_inst("Camera", authored.duplicate()))
	_assert_eq(int(d._last_camera_params["map_rot"]), 0xE00,
		"Unknown!=0 Focus leaves the authored 0xE00 standing")


func _test_handlers_registered_not_skip() -> void:
	var vm := _make_vm()
	_assert_handler(vm, EventInstruction.FOCUS, "_op_focus")
	_assert_handler(vm, EventInstruction.FOCUS_SPEED, "_op_focus_speed")


# --- Focus re-aim -----------------------------------------------------------

func _test_focus_reaims_single_unit() -> void:
	# A single-unit focus (Unit(1)==Unit(2)) centres the Camera on that unit. With
	# map_size_z=0 the depth-flip + vertical datum are disabled, so the opcode→godot
	# round-trip is exact: apply_takeover pos == unit.global_position.
	var vm := _make_vm()
	var cam := _attach_camera(vm)
	var unit := _spawn_unit(vm, 0x17, Vector3(6.5, 3.0, 4.5))

	vm.camera_director._op_focus(_inst("Focus", {"Unit (1)": 0x17, "Unit (2)": 0x17, "Unknown": 0}))
	_assert_true(vm.camera_director._pending_focus != null, "Focus stashes a pending focus")

	# Camera opcode (snap: Time=1) consumes the pending focus.
	vm.camera_director._op_camera(_inst("Camera", _camera_params(1000, 2000, 3000, 1)))
	_assert_true(vm.camera_director._pending_focus == null, "pending focus cleared after Camera")
	_assert_true(cam.takeover_requested, "Camera requested takeover")
	# Authored X/Y/Z (1000/2000/3000) were overridden by the unit's position.
	_assert_vec_near(cam.last_pos, unit.global_position, 0.01, "Camera re-aimed onto the unit")


func _test_focus_midpoint_two_units() -> void:
	var vm := _make_vm()
	_attach_camera(vm)
	_spawn_unit(vm, 0x10, Vector3(4.0, 3.0, 2.0))
	_spawn_unit(vm, 0x20, Vector3(8.0, 3.0, 6.0))
	# Direct midpoint helper check.
	var mid = vm.camera_director._focus_midpoint_godot(
		ScenarioDecode.focus(_reader({"Unit (1)": 0x10, "Unit (2)": 0x20, "Unknown": 1})))
	_assert_vec_near(mid, Vector3(6.0, 3.0, 4.0), 0.001, "midpoint of two units")


func _test_focus_absent_units_keeps_authored() -> void:
	# No matching units → _focus_midpoint_godot returns null and the Camera keeps its
	# authored pose (mirrors PSX's 0x7d0 absent-unit abort).
	var vm := _make_vm()
	var cam := _attach_camera(vm)
	vm.camera_director._op_focus(_inst("Focus", {"Unit (1)": 0xAB, "Unit (2)": 0xAB, "Unknown": 0}))
	vm.camera_director._op_camera(_inst("Camera", _camera_params(560, 0, 336, 1)))
	# Authored X=560 → godot.x = 560/112 = 5.0; Z=336 → godot.z = 336/112 = 3.0.
	_assert_vec_near(cam.last_pos, Vector3(5.0, 0.0, 3.0), 0.01, "absent units → authored Camera pose")


func _test_focus_speed_overrides_time_and_lerps() -> void:
	# Focus Speed sets the following Camera's Time; a Time>1 arms a lerp so the
	# kind-4 camera barrier (is_idle) goes false, then true once it drains.
	var vm := _make_vm()
	_attach_camera(vm)
	_spawn_unit(vm, 0x17, Vector3(6.5, 3.0, 4.5))
	vm.camera_director._op_focus(_inst("Focus", {"Unit (1)": 0x17, "Unit (2)": 0x17, "Unknown": 0}))
	vm.camera_director._op_focus_speed(_inst("Focus Speed", {"Speed": 30}))
	_assert_eq(vm.camera_director._pending_focus_time, 30, "Focus Speed stashed")
	# Camera with authored Time=1 — Focus Speed should override it to 30 → lerp.
	vm.camera_director._op_camera(_inst("Camera", _camera_params(0, 0, 0, 1)))
	_assert_true(not vm.camera_director.is_idle(), "camera busy (lerp armed by Focus Speed)")
	# Drain the ~30-tick (0.5s) lerp.
	for _i in 40:
		vm.camera_director.tick(1.0 / 60.0)
	_assert_true(vm.camera_director.is_idle(), "camera idle once the focus lerp drains")


# --- Event End terminators --------------------------------------------------

func _test_event_end_terminates_cleanly() -> void:
	for term in ["Event End", "Event End 2"]:
		var vm := _make_vm()
		vm._running = true
		var term_op := 0xDB if term == "Event End" else 0xE3
		vm._insts = [{"name": "No-op", "opcode": 0xF2}, {"name": term, "opcode": term_op}]
		var ctx = ScenarioVMClass.ScriptContext.new()
		ctx.label = "main"
		ctx.pc = 0
		vm._contexts = [ctx]
		vm._current_ctx = ctx
		vm._drain_context(ctx)
		_assert_true(not ctx.alive, "%s ends the context (alive=false)" % term)
		_assert_true(vm._running, "%s does NOT halt the VM (no unhandled warning)" % term)
		# ADR-0059: the terminator is an enum-keyed handler now, so pc advances
		# past it (index 2 == _insts.size()) before the dead-context guard exits
		# the loop. The meaningful guarantee is above (context ended, no halt); the
		# handler-path pc += 1 is harmless because the context is dead.
		_assert_eq(ctx.pc, 2, "%s consumed through the terminator (dead context)" % term)


# --- fixtures ---------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	vm.map_size_z = 0  # disable the depth-flip + vertical datum for exact round-trips
	_nodes.append(vm)
	return vm


func _attach_camera(vm: ScenarioVMClass) -> StubCamera:
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	_nodes.append(cam)
	return cam


func _spawn_unit(vm: ScenarioVMClass, uid: int, pos: Vector3) -> Node3D:
	var u := Node3D.new()
	add_child(u)
	u.global_position = pos
	vm.units_by_id[uid] = u
	_nodes.append(u)
	return u


func _inst(name: String, params: Dictionary) -> Dictionary:
	var plist: Array = []
	for k in params:
		plist.append({"name": k, "value": params[k]})
	return {"name": name, "params": plist}


func _camera_params(x: int, z: int, y: int, time: int) -> Dictionary:
	return {"X": x, "Z": z, "Y": y, "Angle": 0, "Map Rotation": 0,
		"Camera Rotation": 0, "Zoom": 4096, "Time": time}


# --- assert helpers ---------------------------------------------------------

func _assert_handler(vm, op: int, method: String) -> void:
	# op is an EventInstruction member (byte); the display name is the descriptor
	# label, kept for readable assertion messages only (dispatch is byte-keyed).
	var op_name := EventInstructionSet.name_of(op)
	var h = vm._handlers.get(op, null)
	_assert_true(h != null, "%s handler registered" % op_name)
	if h != null:
		_assert_eq((h as Callable).get_method(), method, "%s -> %s (not skip/halt)" % [op_name, method])


func _assert_vec_near(got, want: Vector3, eps: float, name: String) -> void:
	if got != null and (got as Vector3).distance_to(want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
