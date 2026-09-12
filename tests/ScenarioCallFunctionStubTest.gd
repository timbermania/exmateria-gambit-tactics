extends Node
## Regression guard for the two 2026-07-05 Delita-render fixes (handoff:
## /tmp/handoff-delita-callfunction-2026-07-05.md, issue #155):
##
##  1. {43} Call Function (0x43) has a LOUD but NON-HALTING stub. On PSX it
##     dispatches an unemulated engine subroutine; we can't reproduce it, so the
##     handler screams via push_error on every call — but must NOT set
##     `_running=false`, so the scene keeps rendering (unlike {92} Inflict
##     Status, which halts on an unmodelled status). This was the scn6 blocker:
##     it hard-halted at pc=7, before Delita's Draw at pc=88.
##
##  2. The `play_through_skip_unknown` setter RE-ARMS `_running` on a genuine
##     OFF->ON edge, so ticking the debug panel's "Play-through" checkbox
##     resumes a VM that already halted. Before the fix the setter only stored
##     the flag, so flipping it after a halt did nothing.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCallFunctionStubTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var vm: ScenarioVM = ScenarioVMClass.new()
	add_child(vm)  # triggers _ready -> handler registration

	_test_call_function_bound(vm)
	_test_call_function_does_not_halt(vm)
	_test_playthrough_setter_rearms(vm)

	vm.queue_free()

	print("\n=== ScenarioCallFunctionStubTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCallFunctionStubTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCallFunctionStubTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCallFunctionStubTest")
		get_tree().quit(0)


# {43} is bound (present in _handlers) so byte-keyed dispatch reaches the stub
# instead of the null-handler halt path.
func _test_call_function_bound(vm: ScenarioVM) -> void:
	_assert_true(vm._handlers.has(EventInstruction.CALL_FUNCTION),
		"Call Function (0x43) is bound")


# The stub continues the VM: dispatching an UNIMPLEMENTED Call Function must leave
# `_running` true. Contrast with {92} Inflict Status, which halts on an unmodelled
# status. Function=1 is still an unemulated engine subroutine (Function=4, the
# dead-unit fade, is decoded now — see ScenarioDeadUnitFadeTest — so it would no
# longer exercise the loud-stub path).
func _test_call_function_does_not_halt(vm: ScenarioVM) -> void:
	var ctx := ScenarioVMClass.ScriptContext.new()
	ctx.label = "main"
	ctx.pc = 8  # handler reads `_current_ctx.pc - 1` for the log; pc already advanced
	vm._current_ctx = ctx
	vm._running = true
	var inst := {
		"name": "Call Function",
		"opcode": EventInstruction.CALL_FUNCTION,
		"offset": 0,
		"params": [{"name": "Function", "value": 1, "bytes": 1}],
	}
	# Fires a push_error (loud) — expected; the test asserts it does NOT halt.
	vm._op_call_function(inst)
	_assert_true(vm._running, "Call Function stub does NOT halt the VM (_running stays true)")


# The setter re-arms `_running` on OFF->ON, and only on that edge.
func _test_playthrough_setter_rearms(vm: ScenarioVM) -> void:
	# OFF->ON after a halt resumes the VM.
	vm.play_through_skip_unknown = false
	vm._running = false
	vm.play_through_skip_unknown = true
	_assert_true(vm._running, "setter OFF->ON re-arms _running after a halt")

	# ON->ON (no edge) must NOT spuriously re-arm a re-halted VM.
	vm._running = false
	vm.play_through_skip_unknown = true
	_assert_true(not vm._running, "setter ON->ON does not re-arm (no edge)")

	# Turning it OFF must never re-arm.
	vm._running = false
	vm.play_through_skip_unknown = false
	_assert_true(not vm._running, "setter ->OFF does not re-arm")


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)
