extends Node
## Tests for ScenarioVM.group_finished(last_scenario_id) — the SCENARIO sub-scene's
## "this scenario chunk's MAIN context ended" signal (navigator live-boot #1,
## decision #179). The persistent-world navigator yields on this to advance the walk:
## a scenario group's terminal member reaching its {DB}/{E3} Event End is what
## "group finished" means to the runner (the applier only leaves the FINAL member
## playing at normal speed — that member's Event End is the one that matters).
##
## Contract:
##   - Fires when the MAIN context (_contexts[0]) reaches Event End ({DB}) or
##     Event End 2 ({E3}), carrying the VM's `current_scenario_id`.
##   - Does NOT fire when only a CHILD (block) coroutine reaches Event End — a
##     spawned sub-fiber terminating is not the group finishing.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioGroupFinishedTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_main_event_end_fires_with_scenario_id()
	_test_main_event_end_2_fires()
	_test_child_block_event_end_does_not_fire()
	_test_fires_once_per_main_end()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioGroupFinishedTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioGroupFinishedTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioGroupFinishedTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioGroupFinishedTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


# --- Fixtures ----------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _event_end_inst() -> Dictionary:
	return {"name": "Event End", "opcode": 0xDB, "offset": 0, "params": []}


func _event_end_2_inst() -> Dictionary:
	return {"name": "Event End 2", "opcode": 0xE3, "offset": 0, "params": []}


func _wait_inst(ticks: int) -> Dictionary:
	return {"name": "Wait", "opcode": 0xF1, "offset": 0,
		"params": [{"name": "Time", "value": ticks}]}


func _block_end_inst() -> Dictionary:
	return {"name": "Block End", "opcode": 0x2B, "offset": 0, "params": []}


# Collect every group_finished payload the VM emits.
func _collect(vm: ScenarioVMClass) -> Array:
	var got: Array = []
	vm.group_finished.connect(func(id: int) -> void: got.append(id))
	return got


# --- Cycle 1: main-context Event End fires with the scenario id ---------------

func _test_main_event_end_fires_with_scenario_id() -> void:
	var vm := _make_vm()
	vm.current_scenario_id = 6
	vm._insts = [_event_end_inst()]
	var got := _collect(vm)
	vm.start()
	vm._tick_once()
	_assert_eq(got.size(), 1, "main Event End: group_finished fired once")
	if got.size() == 1:
		_assert_eq(got[0], 6, "main Event End: payload = current_scenario_id (6)")


# --- Cycle 2: {E3} Event End 2 fires it too (same terminator family) ----------

func _test_main_event_end_2_fires() -> void:
	var vm := _make_vm()
	vm.current_scenario_id = 2
	vm._insts = [_event_end_2_inst()]
	var got := _collect(vm)
	vm.start()
	vm._tick_once()
	_assert_eq(got.size(), 1, "main Event End 2: group_finished fired once")
	if got.size() == 1:
		_assert_eq(got[0], 2, "main Event End 2: payload = current_scenario_id (2)")


# --- Cycle 3: a CHILD block's Event End must NOT fire it ----------------------
# Main parks on a long Wait (never reaches its own terminator this tick); a spawned
# child coroutine reaches Event End at pc 1. Only the main context finishing is the
# group finishing, so the signal must stay silent.

func _test_child_block_event_end_does_not_fire() -> void:
	var vm := _make_vm()
	vm.current_scenario_id = 4
	vm._insts = [_wait_inst(1000), _event_end_inst()]
	var got := _collect(vm)
	vm.start()
	# Spawn a child coroutine parked at the Event End opcode (as Block Start would).
	var child = ScenarioVMClass.ScriptContext.new()
	child.pc = 1
	child.label = "block@1"
	vm._contexts.append(child)

	vm._tick_once()
	_assert_eq(got.size(), 0, "child Event End: group_finished did NOT fire (main still alive)")
	_assert_true(vm._contexts[0].alive, "child Event End: main context still alive")


# --- Cycle 4: exactly one emission per main-context end -----------------------
# A chunk with a mid-stream Wait then Event End must emit exactly once when the
# main context finally terminates — not once per tick while draining.

func _test_fires_once_per_main_end() -> void:
	var vm := _make_vm()
	vm.current_scenario_id = 8
	vm._insts = [_wait_inst(2), _event_end_inst()]
	var got := _collect(vm)
	vm.start()
	for _t in range(6):
		vm._tick_once()
	_assert_eq(got.size(), 1, "mid-Wait chunk: group_finished fired exactly once at the end")
	if got.size() == 1:
		_assert_eq(got[0], 8, "mid-Wait chunk: payload = current_scenario_id (8)")
