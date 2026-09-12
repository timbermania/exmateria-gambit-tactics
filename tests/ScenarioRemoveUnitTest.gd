extends Node
## Tests for ScenarioVM's {3D} Remove Unit (opcode 0x3D) — the opcode that
## previously halted the VM at scenario-1 PC 382 ("unhandled opcode 'Remove
## Unit'").
##
## FFT decode (research/working_documents/scenario_1_captures/
## remove_unit_decode.md, dynamically validated at both scenario-1 sites 0x83 /
## 0x13): {3D} tears a unit fully off the field AND out of memory — clears its
## combat-roster slot (active word 1->0, synchronously in the handler), clears
## its per-ID registry byte, and frees its sprite slot. Instant, no fade, no War
## Trophy (that's {44} Blue Remove Unit). Distinct from {46} Erase Unit, which
## only hides the sprite and leaves the registry intact.
##
## In our engine that collapses to: erase the id from `units_by_id` (so later
## references no-op and a following {45} Add Unit can reuse the slot), tear down
## every per-unit ScenarioVM bookkeeping entry keyed on the node (`_forget_unit`),
## and `queue_free` the sprite node. The Masked-Data 2nd operand is ignored.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioRemoveUnitTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const CHUNK_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_handler_registered()
	_test_removes_unit_and_frees_node()
	_test_missing_unit_is_noop()
	_test_forget_unit_clears_bookkeeping()
	_test_real_chunk_pc382_does_not_halt()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioRemoveUnitTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioRemoveUnitTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioRemoveUnitTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioRemoveUnitTest")
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
	vm.set_process(false)  # drive timing deterministically, no auto _process
	_vms.append(vm)
	return vm


func _add_unit(vm: ScenarioVMClass, uid: int) -> Node3D:
	var u := Node3D.new()
	add_child(u)
	vm.units_by_id[uid] = u
	return u


func _remove_unit_inst(uid: int) -> Dictionary:
	# The parser folds ID + Masked-Data into a single 2-byte `Unit` field
	# (event_instructions.json). The handler reads only `Unit`.
	return {
		"name": "Remove Unit", "opcode": 0x3D, "offset": 0x897,
		"params": [{"name": "Unit", "value": uid}],
	}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handler_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.REMOVE_UNIT),
		"_handlers has 'Remove Unit'")


# --- Cycle 2: removal erases the id AND frees the node -----------------------

func _test_removes_unit_and_frees_node() -> void:
	var vm := _make_vm()
	var unit := _add_unit(vm, 0x83)
	_assert_true(vm.units_by_id.has(0x83), "unit 0x83 present before removal")

	vm._op_remove_unit(_remove_unit_inst(0x83))

	_assert_true(not vm.units_by_id.has(0x83),
		"units_by_id no longer has 0x83 after Remove Unit")
	# queue_free is deferred; the node is marked for deletion this frame.
	_assert_true(unit.is_queued_for_deletion(),
		"removed unit node is queued for deletion")


# --- Cycle 3: removing a not-live unit is a clean no-op ----------------------

func _test_missing_unit_is_noop() -> void:
	var vm := _make_vm()
	# No unit spawned for 0x99 — must not crash, must not halt anything.
	vm._op_remove_unit(_remove_unit_inst(0x99))
	_assert_true(not vm.units_by_id.has(0x99),
		"missing-unit Remove Unit is a no-op (still absent)")


# --- Cycle 4: per-unit bookkeeping is torn down (the _forget_unit helper) -----

func _test_forget_unit_clears_bookkeeping() -> void:
	var vm := _make_vm()
	var unit := _add_unit(vm, 0x83)
	# Arm every per-unit structure the actor now holds (ADR-0064): tint, motion,
	# walker, atlas offset, and the captured home.
	var a := vm.actor(0x83)
	a.tint = ScenarioColorTint.new()
	a.motion = ScenarioMotion.new()
	a.atlas_y = 7
	a.capture_home(unit)

	vm._op_remove_unit(_remove_unit_inst(0x83))

	# Remove Unit routes through forget → the whole actor entry is erased, so all
	# five per-unit structures go with it (no Unit-field touch — that's reset_all).
	_assert_true(vm.peek_actor(0x83) == null,
		"forget erased the actor entry (tint/motion/walker/atlas/home)")


# --- Cycle 5: the real chapel chunk no longer halts at PC 382 ----------------

func _test_real_chunk_pc382_does_not_halt() -> void:
	# Load the committed scenario-1 chunk and run the real Remove Unit at PC 382
	# (removes field actor 0x83), which immediately precedes the {45} Add Unit
	# 0x82 that reuses its freed slot. Before this opcode was implemented the VM
	# set _running = false on the unhandled 'Remove Unit' here. Now it must sail
	# through: _running stays true, the unit is gone, and the context advances.
	var vm := _make_vm()
	var ok := vm.load_chunk_json(CHUNK_PATH)
	_assert_true(ok, "loaded real scenario_1_chunk.json")
	if not ok:
		return
	# Both {3D} sites need a live unit to remove. Spawn stubs for 0x83 / 0x13.
	vm.start()
	_add_unit(vm, 0x83)
	_add_unit(vm, 0x13)
	# Jump the main context to the Remove Unit opcode itself (PC 382), skipping
	# the 382-opcode choreography that precedes it.
	vm._contexts[0].pc = 382

	var crossed := false
	var halted := false
	for _t in range(50):
		vm._tick_once()
		if not vm._running:
			halted = true
			break
		if vm._contexts[0].pc > 382:
			crossed = true
			break

	_assert_true(not halted, "VM did NOT halt at the Remove Unit opcode")
	_assert_true(crossed, "main context advanced past PC 382")
	_assert_true(vm._running, "VM still running after PC 382")
	_assert_true(not vm.units_by_id.has(0x83),
		"real-chunk Remove Unit erased actor 0x83 from the roster")
