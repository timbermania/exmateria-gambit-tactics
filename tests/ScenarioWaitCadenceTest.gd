extends Node
# test-kind: logic
# seeded-break: ScenarioVM._tick_once's wait gate — the fall-through that dispatches on the tick the counter reaches zero is replaced by an unconditional `continue` (restores the pre-fix N+1 cadence); all five 'next opcode dispatches EXACTLY N ticks later' arms red (got=N+1), marker-A arms stay green; GREEN unbroken on the reverted tree
## Regression guard for the {29} `Wait` opcode's frame cadence: `Wait N` must
## delay the NEXT opcode by EXACTLY N VM ticks — no more, no less.
##
## Ground truth (scenario 6 carry, 2026-07-07): parking the PSX event VM and
## polling each unit's anim-id field (`+0x1DC`) every vsync shows `Wait T=6`
## spans exactly 6 vsyncs between successive anim onsets. Godot originally
## blocked the tick `wait_ticks` hit zero, so `Wait N` spanned N+1 ticks — a
## +1-frame-per-Wait error that accumulated to ~+8% pace drift over the carry
## cinematic (tools/record_carry_timeline.gd). The fix (ScenarioVM `_tick_once`
## wait gate) resumes dispatch on the tick the counter reaches zero.
##
## Harness mirrors ScenarioVarWaitValueTest: a tree-less VM driven by direct
## `_tick_once()` calls, with a Rotate Unit as the observable marker (its
## `_rotate_state` becomes non-empty on the tick it dispatches).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWaitCadenceTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const FacingDirection = ExMateriaSchema.Facing.Direction
var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _units: Array = []


func _ready() -> void:
	for n in [1, 2, 6, 16, 30]:
		_test_wait_spans_exactly_n(n)

	for u in _units:
		if is_instance_valid(u):
			u.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioWaitCadenceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWaitCadenceTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWaitCadenceTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWaitCadenceTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _make_unit(start_facing: int) -> Unit:
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = start_facing
	_units.append(unit)
	return unit


func _wait_inst(t: int) -> Dictionary:
	# {F1} Wait — opcode 0xF1 (NOT 0x29, which is Wait Walk).
	return {"name": "Wait", "opcode": EventInstruction.WAIT, "offset": 0,
		"params": [{"name": "Time", "value": t}]}


func _rotate_unit_inst(chunk_unit_id: int, facing: int) -> Dictionary:
	return {"name": "Rotate Unit", "opcode": 0x2D, "offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": (chunk_unit_id >> 8) & 0xFF},
			{"name": "Facing", "value": facing},
			{"name": "Direction", "value": 0},
			{"name": "Speed", "value": 0},
			{"name": "Delay", "value": 0},
		]}


# Run [Rotate(A); Wait(N); Rotate(B)] on a fresh VM, driving _tick_once directly.
# A dispatches on tick 1; assert B dispatches on tick 1+N (exactly N ticks later).
func _test_wait_spans_exactly_n(n: int) -> void:
	var vm := _make_vm()
	var unit_a := _make_unit(FacingDirection.SOUTH)
	var unit_b := _make_unit(FacingDirection.SOUTH)
	vm.units_by_id = {1: unit_a, 2: unit_b}
	vm._insts = [
		_rotate_unit_inst(1, 0x08),   # marker A (rotate to a NEW facing so it arms)
		_wait_inst(n),
		_rotate_unit_inst(2, 0x08),   # marker B — should fire N ticks after A
	]
	vm.start()

	var t_a := -1
	var t_b := -1
	for t in range(1, n + 20):
		vm._tick_once()
		if t_a < 0 and not unit_a._rotate_state.is_empty():
			t_a = t
		if t_b < 0 and not unit_b._rotate_state.is_empty():
			t_b = t
		if t_a >= 0 and t_b >= 0:
			break

	_assert_eq(t_a, 1, "Wait(%d): marker A dispatches on tick 1" % n)
	_assert_eq(t_b - t_a if (t_a >= 0 and t_b >= 0) else -999, n,
		"Wait(%d): next opcode dispatches EXACTLY %d ticks later (PSX = N, not N+1)" % [n, n])
