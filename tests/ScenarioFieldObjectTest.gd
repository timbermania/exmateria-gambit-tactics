extends Node
## Tests for ScenarioVM's {55} Use Field Object / {57} Wait Field Object (and the
## {54}/{56} 3D-object pair) — the map textured-animation object opcodes that
## previously halted the VM at chapel PC 231.
##
## FFT decode (see `research/working_documents/scenario_1_captures/
## use_field_object_decode.md` + `HANDOFF_field_object_implementation.md`):
## {55} latches a one-shot "play textured-animation #ID on the map mesh" request
## (consumer FUN_80143418 -> FUN_800f0be0 cmd 0x83); {57} barriers on the single
## active slot (flag 0x80166070) until the consumer's completion poll clears it
## (~50 frames live). Stage 1 models the duration so the barrier resolves with
## plausible timing without rendering the real map animation yet.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioFieldObjectTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const CHUNK_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_handlers_registered()
	_test_real_chunk_pc231_does_not_halt()
	_test_use_field_object_is_nonblocking()
	_test_wait_field_object_holds_then_releases()
	_test_wait_field_object_no_active_does_not_block()
	_test_use_3d_object_and_wait_barrier()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioFieldObjectTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioFieldObjectTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioFieldObjectTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioFieldObjectTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


# --- Fixture builders --------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


# The real chunk's Use Field Object record (chapel PC 231, ID=1, Unknown=0). Pull
# it from the committed scenario JSON rather than hand-rolling a shim (project
# rule: prefer real inputs). Falls back to a faithful synthetic copy if the
# asset is missing so the barrier-timing tests still run.
func _real_use_field_object_inst() -> Dictionary:
	var f := FileAccess.open(CHUNK_PATH, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed != null and parsed.has("instructions"):
			var ins: Array = parsed["instructions"]
			if ins.size() > 231 and str(ins[231].get("name", "")) == "Use Field Object":
				return ins[231]
	return {
		"name": "Use Field Object", "opcode": 0x55, "offset": 0x4FF,
		"params": [
			{"name": "ID", "value": 1},
			{"name": "Unknown", "value": 0},
		],
	}


func _wait_field_object_inst() -> Dictionary:
	return {"name": "Wait Field Object", "opcode": 0x57, "offset": 0, "params": []}


func _use_3d_object_inst(id: int, state: int) -> Dictionary:
	return {
		"name": "Use 3D Object", "opcode": 0x54, "offset": 0,
		"params": [{"name": "ID", "value": id}, {"name": "State", "value": state}],
	}


func _wait_3d_object_inst() -> Dictionary:
	return {"name": "Wait 3D Object", "opcode": 0x56, "offset": 0, "params": []}


func _noop_inst() -> Dictionary:
	return {"name": "No-op", "opcode": 0xF2, "offset": 0, "params": []}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handlers_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.USE_FIELD_OBJECT),
		"_handlers has 'Use Field Object'")
	_assert_true(vm._handlers.has(EventInstruction.WAIT_FIELD_OBJECT),
		"_handlers has 'Wait Field Object'")
	_assert_true(vm._handlers.has(EventInstruction.USE_3D_OBJECT),
		"_handlers has 'Use 3D Object'")
	_assert_true(vm._handlers.has(EventInstruction.WAIT_3D_OBJECT),
		"_handlers has 'Wait 3D Object'")


# --- Cycle 2: the real chapel chunk no longer halts at PC 231 ----------------

func _test_real_chunk_pc231_does_not_halt() -> void:
	# Load the committed scenario-1 chunk and run the real Sound/Color/Wait/Use
	# Field Object/Wait sequence that brackets PC 231 (the moment the priest hands
	# the item to Ovelia). Before this opcode was implemented the VM set
	# _running = false on the unhandled 'Use Field Object' here. Now it must sail
	# through: _running stays true and the main context advances past 231.
	var vm := _make_vm()
	var ok := vm.load_chunk_json(CHUNK_PATH)
	_assert_true(ok, "loaded real scenario_1_chunk.json")
	if not ok:
		return
	vm.start()
	# Jump the main context to just before PC 231 to exercise the real surrounding
	# opcodes (226 Sound .. 235 Wait) without first driving the entire 226-opcode
	# choreography (dialogs/walks/camera) that precedes it.
	vm._contexts[0].pc = 226

	var crossed_231 := false
	var halted := false
	for _t in range(200):
		vm._tick_once()
		if not vm._running:
			halted = true
			break
		if vm._contexts[0].pc > 231:
			crossed_231 = true
			break

	_assert_true(not halted, "VM did NOT halt at the Use Field Object opcode")
	_assert_true(crossed_231, "main context advanced past PC 231")
	_assert_true(vm._running, "VM still running after PC 231")
	# {55} ID=1 was latched; with only the ~4 Wait ticks elapsed since, the 50-tick
	# modeled record is still active.
	_assert_true(vm._field_objects.has(1),
		"Use Field Object latched the ID=1 textured-animation record")


# --- Cycle 3: {55} Use Field Object is non-blocking --------------------------

func _test_use_field_object_is_nonblocking() -> void:
	# {55} latches + yields once on PSX, but the next opcode is a plain Wait, so a
	# return is the faithful shape: dispatch must NOT arm a barrier on the {55}
	# itself. The context sails straight to the following opcode in the same tick.
	var vm := _make_vm()
	vm._insts = [_real_use_field_object_inst(), _noop_inst()]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Use Field Object armed NO barrier (non-blocking)")
	_assert_true(vm._field_objects.has(1),
		"Use Field Object latched record for ID=1")
	# The per-tick pump runs BEFORE dispatch, so the record latched during this
	# tick's dispatch hasn't drained yet — it reads the full default and starts
	# counting down next tick.
	_assert_eq(int(vm._field_objects[1]["ticks_left"]),
		vm._FIELD_OBJ_DEFAULT_TICKS,
		"record seeded with the default modeled duration")


# --- Cycle 4: {57} Wait Field Object holds, then releases on completion -------

func _test_wait_field_object_holds_then_releases() -> void:
	# {55} starts the field animation (modeled 50 ticks); {57} must hold the
	# calling context until the record drains, then resume. A post-barrier marker
	# opcode must not run while the barrier holds.
	var vm := _make_vm()
	vm._insts = [
		_real_use_field_object_inst(),  # latch ID=1, 50 ticks
		_wait_field_object_inst(),      # barrier
		_noop_inst(),                   # post-barrier marker
	]
	vm.start()

	# Tick 1: {55} latches, {57} arms the barrier, dispatch yields.
	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"after tick 1: Wait Field Object armed a barrier")
	_assert_true(vm._field_objects.has(1),
		"after tick 1: field-object record still active")

	# Drive ticks until the barrier releases (the record drains to 0). It must
	# hold for multiple ticks (close to the 50-tick model) before releasing.
	var release_tick := -1
	for t in range(2, 200):
		vm._tick_once()
		if not vm._contexts[0].wait_until.is_valid():
			release_tick = t
			break

	_assert_true(release_tick >= 0, "barrier eventually released")
	_assert_true(release_tick > 40 and release_tick < 70,
		"barrier held ~50 ticks (released @tick %d)" % release_tick)
	_assert_true(vm._field_objects.is_empty(),
		"field-object record cleared once the animation finished")
	_assert_true(vm._running, "VM still running after the barrier released")


# --- Cycle 5: {57} with no active field object does not block -----------------

func _test_wait_field_object_no_active_does_not_block() -> void:
	# A {57} with no field animation in flight must fall straight through (PSX's
	# active flag would already read 0). No barrier armed; the next opcode runs.
	var vm := _make_vm()
	vm._insts = [_wait_field_object_inst(), _noop_inst()]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Wait Field Object with no active object armed NO barrier")
	_assert_true(vm._contexts[0].pc >= 2,
		"Wait Field Object fell through to the next opcode")


# --- Cycle 6: {54} Use 3D Object + {56} Wait 3D Object barrier ----------------

func _test_use_3d_object_and_wait_barrier() -> void:
	# The 3D-object pair mirrors the field pair (cmd 0x80/0x81, flag 0x8016606e).
	# {54} latches with its State operand; {56} barriers until the record drains.
	var vm := _make_vm()
	vm._insts = [
		_use_3d_object_inst(7, 3),
		_wait_3d_object_inst(),
		_noop_inst(),
	]
	vm.start()
	vm._tick_once()
	_assert_true(vm._threed_objects.has(7),
		"Use 3D Object latched record for ID=7")
	_assert_eq(int(vm._threed_objects[7]["state"]), 3,
		"Use 3D Object stashed the State operand")
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Wait 3D Object armed a barrier while the object animates")

	var release_tick := -1
	for t in range(2, 200):
		vm._tick_once()
		if not vm._contexts[0].wait_until.is_valid():
			release_tick = t
			break
	_assert_true(release_tick > 40 and release_tick < 70,
		"3D-object barrier held ~50 ticks (released @tick %d)" % release_tick)
	_assert_true(vm._threed_objects.is_empty(),
		"3D-object record cleared once finished")
