extends Node
## Tests for ScenarioVM's event **variable system** — BOTH reader families:
## the Wait Value path (writers `Zero` 0xBE / `Add` 0xB0, reader `Wait Value`
## 0x7E, plus the var-87 frame-counter incrementer that makes the prayer-scene
## barrier release) and the compare-then-branch path (`0xB0`-`0xBD` arithmetic,
## `0xA0`-`0xA5` comparisons, `0xD0`/`0xD1`/`0xD3` jumps + `0xD2`/`0xD4`/`0xD5`
## anchors).
##
## [b]The second family is not decoration.[/b] `Returning to Igros` (scn 27, the
## last member of group 26) ends on
## `Zero(0); Zero(1); Add Variable(0,508); Add(1,0); Variable ==; Jump Forward If
## Zero(1)` — and with `0xB1` unbound the VM HALTED there, never reached the
## trailing `Event End`, never emitted `group_finished`, and the campaign walk sat
## on group 26 forever instead of chaining to group 28 (Family Meeting). Every
## sibling of `0xB1` was the same halt waiting for a different scenario, which is
## why the whole family is bound and the whole family is pinned here.
##
## FFT decode (see `research/wiki_articles/event_instruction_a0_d5_variable_
## readers.md` §1 + `event_instruction_b0_be_variable_math.md`): the Orbonne
## prayer scene resets a free-running frame counter (var 87) with
## `Zero(87); Add(87, 0)`, then a parallel Block coroutine fires two altar
## rotations when the counter reaches frames 28 and 30 via `Wait Value(87, 28)` /
## `(87, 30)`. `Wait Value` is a SIGNED `>=` predicate barrier (ROM FUN_8014a3f8
## `slt; beq` then fiber-yield + re-poll), NOT `==`. The exact ROM per-frame
## producer of var 87 isn't statically isolable, so ScenarioVM models it as a
## +1/VM-tick incrementer in `_tick_once`.
##
## This is the comprehensive test of the real, executed fixture (scenario_1
## offsets 1863–1896 = VM pc 319–326): the block coroutine holds while the main
## thread races on, and the two rotations dispatch ~28 and ~30 ticks after the
## reset, ~2 ticks apart, with NO unhandled-opcode halt.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioVarWaitValueTest.tscn

# test-kind: logic
# seeded-break: invert the `cond != 0` early-out in ScenarioVM._op_jump_forward_if_zero — the two Igros-tail arms swap and both go red.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const FacingDirection = ExMateriaSchema.Facing.Direction

# A GDScript runtime error — `Invalid access to property or key` — aborts the
# ENCLOSING function and lets `_ready` carry on with the next one. Every
# assertion after the error is silently never reached, and the file still reports
# `0 failed`. That is exactly what happened here: `vm._vars[5] = 0` addressed a
# member `ScenarioVM` no longer has (the store moved behind `vars_store`), the
# five assertions of `_test_wait_value_is_ge_not_eq` never ran, and this file
# printed `17 passed, 0 failed` / `[PASS]` while `run_tests_parallel.py` graded it
# THREW off the stderr trace (#709). The old floor — `_passed == 0 and
# _failed == 0` — cannot see a partial run, only a total one. Pin the TOTAL.
const EXPECTED_ASSERTIONS := 50

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _units: Array = []


func _ready() -> void:
	_test_handlers_registered()
	_test_writers_zero_and_add()
	_test_wait_value_is_ge_not_eq()
	_test_prayer_block_releases_at_28_and_30()
	_test_variable_operand_writers()
	_test_comparisons_write_their_boolean_into_var0()
	_test_jump_forward_if_zero_is_the_igros_tail()
	_test_unconditional_jumps_find_their_anchors()

	for u in _units:
		if is_instance_valid(u):
			u.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioVarWaitValueTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed + _failed != EXPECTED_ASSERTIONS:
		print("[FAIL] ScenarioVarWaitValueTest: ran %d assertions, expected %d — a test function aborted part-way (look for SCRIPT ERROR above)" %
			[_passed + _failed, EXPECTED_ASSERTIONS])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioVarWaitValueTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioVarWaitValueTest")
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


# Tree-less Unit + AnimationStateController — mirrors ScenarioWaitRotateTest. The
# scenario_rotate / _tick_rotate path only touches `anim_state`, `facing_angle`,
# and `_rotate_state`, so this is a faithful stand-in for the rotation stepper.
func _make_unit(start_facing: int) -> Unit:
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = start_facing
	_units.append(unit)
	return unit


func _zero_inst(var_id: int) -> Dictionary:
	return {
		"name": "Zero", "opcode": 0xBE, "offset": 0,
		"params": [{"name": "Variable", "value": var_id}],
	}


func _add_inst(var_id: int, value: int) -> Dictionary:
	return {
		"name": "Add", "opcode": 0xB0, "offset": 0,
		"params": [
			{"name": "Variable", "value": var_id},
			{"name": "Value", "value": value},
		],
	}


func _wait_value_inst(var_id: int, value: int) -> Dictionary:
	return {
		"name": "Wait Value", "opcode": 0x7E, "offset": 0,
		"params": [
			{"name": "Variable", "value": var_id},
			{"name": "Value", "value": value},
		],
	}


func _rotate_unit_inst(chunk_unit_id: int, facing: int) -> Dictionary:
	return {
		"name": "Rotate Unit", "opcode": 0x2D, "offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": (chunk_unit_id >> 8) & 0xFF},
			{"name": "Facing", "value": facing},
			{"name": "Direction", "value": 0},
			{"name": "Speed", "value": 0},
			{"name": "Delay", "value": 0},
		],
	}


func _block_start_inst() -> Dictionary:
	return {"name": "Block Start", "opcode": 0x2A, "offset": 0, "params": []}


func _block_end_inst() -> Dictionary:
	return {"name": "Block End", "opcode": 0x2B, "offset": 0, "params": []}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handlers_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.ZERO), "_handlers has 'Zero'")
	_assert_true(vm._handlers.has(EventInstruction.ADD), "_handlers has 'Add'")
	_assert_true(vm._handlers.has(EventInstruction.WAIT_VALUE), "_handlers has 'Wait Value'")
	# The families, not the two opcodes the prayer scene happens to reach. An
	# unbound member of any of these halts the VM mid-scenario (see the header).
	_assert_true(_all_bound(vm, ScenarioVMClass._VAR_MATH_OPCODES),
		"_handlers has all 14 of the 0xB0-0xBD arithmetic writers")
	_assert_true(_all_bound(vm, ScenarioVMClass._VAR_COMPARE_OPS.keys()),
		"_handlers has all 6 of the 0xA0-0xA5 comparisons")
	_assert_true(_all_bound(vm, [
			EventInstruction.JUMP_FORWARD_IF_ZERO, EventInstruction.JUMP_FORWARD,
			EventInstruction.JUMP_BACK, EventInstruction.FORWARD_TARGET,
			EventInstruction.FORWARD_IF_ZERO_TARGET, EventInstruction.BACK_TARGET]),
		"_handlers has the 3 jumps and their 3 label anchors")


func _all_bound(vm: ScenarioVMClass, opcodes) -> bool:
	for op in opcodes:
		if not vm._handlers.has(int(op)):
			print("  [note] opcode 0x%X is unbound" % int(op))
			return false
	return true


# --- Cycle 2: writers Zero / Add store + accumulate --------------------------

func _test_writers_zero_and_add() -> void:
	# `Zero(5)` then `Add(5, 7)` → var[5] == 7; a second `Add(5, 3)` → 10. The
	# `Add` operand accumulates (it is not a set). var 5 (not 87) so the per-tick
	# var-87 incrementer doesn't perturb the assertion.
	var vm := _make_vm()
	vm._insts = [_zero_inst(5), _add_inst(5, 7), _add_inst(5, 3)]
	vm.start()
	vm._tick_once()
	_assert_eq(vm._var_get(5), 10, "Zero(5);Add(5,7);Add(5,3) -> var[5]==10")
	_assert_true(vm._running, "writer-only run did not halt")


# --- Cycle 3: Wait Value is a SIGNED >= barrier (overshoot still releases) ----

func _test_wait_value_is_ge_not_eq() -> void:
	# Arm a Wait Value(5, 3) barrier by hand on a fresh context, then drive the
	# variable. Below target → holds; AT/ABOVE target → releases. Crucially an
	# OVERSHOOT (var jumps straight to 5) releases too — proving `>=`, not `==`.
	var vm := _make_vm()
	vm._insts = []
	vm.start()
	var ctx = vm._contexts[0]
	vm.vars_store.set_var(5, 0)
	vm._op_wait_value.call(_wait_value_inst(5, 3))
	_assert_true(ctx.wait_until.is_valid(), "Wait Value armed a barrier")
	_assert_true(vm._hold_wait_until(ctx), "var 0 < 3 → barrier holds")
	vm.vars_store.set_var(5, 2)
	_assert_true(vm._hold_wait_until(ctx), "var 2 < 3 → barrier still holds")
	# Overshoot past the exact threshold — an `==` predicate would never release.
	vm.vars_store.set_var(5, 5)
	_assert_true(not vm._hold_wait_until(ctx), "var 5 >= 3 (overshoot) → releases")
	_assert_true(not ctx.wait_until.is_valid(), "barrier cleared on release")


# --- Cycle 4: the real prayer block (pc 319–326) -----------------------------

func _test_prayer_block_releases_at_28_and_30() -> void:
	# scenario_1 pc 319–326, faithfully reconstructed:
	#   Zero(87); Add(87,0); Block Start; Wait Value(87,28); Rotate Unit(2);
	#   Wait Value(87,30); Rotate Unit(23); Block End; <main-thread marker>
	# The block coroutine holds on each Wait Value while the var-87 incrementer
	# climbs; the two rotations fire ~28 and ~30 ticks after the reset, ~2 apart.
	# The main thread races PAST Block End in the SAME tick the block spawns and
	# dispatches its marker opcode (here a Rotate Unit standing in for the real
	# Display Message) — proving the barrier holds only the block, not the VM.
	var vm := _make_vm()
	# Units 2 / 23 = the two altar units; unit 99 = the main-thread marker. Each
	# starts at SOUTH and targets a different facing so its rotate genuinely arms
	# (the exact target facing is irrelevant to this barrier test).
	#
	# "A DIFFERENT facing" is load-bearing and was silently FALSE for unit 23. The probe
	# below is `not _rotate_state.is_empty()`, and `Unit.scenario_rotate` clears
	# `_rotate_state` outright when `start_byte == target_byte` (already aligned → snap, no
	# stepper). Unit 23's facing byte was 0x04, and `facing_byte_to_12bit` makes that 0x400
	# — which is exactly `_CARDINAL_TO_12BIT[SOUTH]`, its start. So the barrier released and
	# `Rotate Unit 0x17` dispatched on time (visible in the log), but the probe read an empty
	# `_rotate_state` and the test reported the release as a no-show. 0x0C → 0xC00 (NORTH)
	# genuinely differs from SOUTH, so the stepper actually arms.
	var unit2 := _make_unit(FacingDirection.SOUTH)
	var unit23 := _make_unit(FacingDirection.SOUTH)
	var unit_main := _make_unit(FacingDirection.SOUTH)
	vm.units_by_id = {2: unit2, 23: unit23, 99: unit_main}
	vm._insts = [
		_zero_inst(87),               # pc 0  (scenario pc 319)
		_add_inst(87, 0),             # pc 1  (scenario pc 320)
		_block_start_inst(),          # pc 2  (scenario pc 321)
		_wait_value_inst(87, 28),     # pc 3  (scenario pc 322)
		_rotate_unit_inst(2, 0x08),   # pc 4  (scenario pc 323)
		_wait_value_inst(87, 30),     # pc 5  (scenario pc 324)
		_rotate_unit_inst(23, 0x0C),  # pc 6  (scenario pc 325) — 0xC00 NORTH ≠ SOUTH start
		_block_end_inst(),            # pc 7  (scenario pc 326)
		_rotate_unit_inst(99, 0x08),  # pc 8  main marker (real: Display Message)
	]
	vm.start()

	# Tick 1: reset runs, block spawns + arms Wait Value(28), main races to the
	# marker IN PARALLEL. Nothing has rotated on the altar yet.
	vm._tick_once()
	_assert_eq(vm._var_get(87), 0, "after reset tick: var[87] == 0")
	_assert_true(vm._running, "no halt on Zero/Add/Block Start/Wait Value")
	_assert_true(not unit_main._rotate_state.is_empty(),
		"main thread raced past the block (marker dispatched in parallel)")
	_assert_true(unit2._rotate_state.is_empty(),
		"altar unit 2 NOT yet rotated (block holds on Wait Value 28)")

	# Drive ticks; record when each altar unit first rotates + the var-87 value
	# at that moment.
	var t2 := -1
	var t23 := -1
	var var_at_t2 := -1
	var var_at_t23 := -1
	var prev_var := vm._var_get(87)
	var climbed := false
	for t in range(2, 120):
		vm._tick_once()
		var v := vm._var_get(87)
		if v > prev_var:
			climbed = true
		prev_var = v
		if t2 < 0 and not unit2._rotate_state.is_empty():
			t2 = t
			var_at_t2 = v
		if t23 < 0 and not unit23._rotate_state.is_empty():
			t23 = t
			var_at_t23 = v
		# Invariant: unit 23 must NEVER rotate before unit 2 (Wait Value 30 > 28).
		if t23 >= 0 and t2 < 0:
			_assert_true(false, "unit 23 rotated before unit 2 (ordering violated)")
		if t2 >= 0 and t23 >= 0:
			break

	_assert_true(climbed, "var[87] climbed each tick (frame-counter incrementer)")
	_assert_true(t2 >= 0, "altar unit 2 eventually rotated (Wait Value 28 released)")
	_assert_true(t23 >= 0, "altar unit 23 eventually rotated (Wait Value 30 released)")
	# Reset landed on tick 1, so var[87] == N-1 on tick N; the >=28 barrier
	# releases when var first reaches 28, ~28 ticks after the reset.
	_assert_true(var_at_t2 >= 28,
		"var[87] >= 28 when unit 2 rotated (got %d @tick %d)" % [var_at_t2, t2])
	_assert_true(var_at_t23 >= 30,
		"var[87] >= 30 when unit 23 rotated (got %d @tick %d)" % [var_at_t23, t23])
	# The two barriers differ by exactly 2 frames → the two rotations fire 2
	# ticks apart.
	_assert_eq(t23 - t2, 2, "altar rotations fire 2 ticks apart (28 then 30)")
	_assert_true(t2 >= 27 and t2 <= 31,
		"unit 2 rotated ~28 ticks after reset (got tick %d)" % t2)
	_assert_true(vm._running, "VM never halted through the whole prayer block")


# --- Fixture builders for the compare-then-branch family ---------------------

# `0xB1`/`0xB3`/… — the ODD sibling of an arithmetic opcode takes a VARIABLE id
# as its second operand. The catalog names BOTH operands "Variable", which is
# exactly why the handler reads them positionally.
func _math_inst(opcode: int, name: String, dst: int, operand: int) -> Dictionary:
	return {
		"name": name, "opcode": opcode, "offset": 0,
		"params": [
			{"name": "Variable", "value": dst},
			{"name": "Variable", "value": operand},
		],
	}


# `0xA0`–`0xA5` read NO operand bytes: the operands are the fixed var[0]/var[1]
# scratch pair (readers doc §2).
func _compare_inst(opcode: int, name: String) -> Dictionary:
	return {"name": name, "opcode": opcode, "offset": 0, "params": []}


# `0xD0`–`0xD5` carry a LABEL ID, never a byte distance (readers doc §3).
func _label_inst(opcode: int, name: String, target: int) -> Dictionary:
	return {
		"name": name, "opcode": opcode, "offset": 0,
		"params": [{"name": "Target", "value": target}],
	}


func _event_end_inst() -> Dictionary:
	return {"name": "Event End", "opcode": EventInstruction.EVENT_END, "offset": 0, "params": []}


# --- Cycle 5: the odd (variable-operand) arithmetic siblings -----------------

func _test_variable_operand_writers() -> void:
	# `Add Variable(6, 5)` adds var[5]'s VALUE, not the id 5 — the even/odd
	# operand-mode test (writers doc §0, ROM `andi op, 1` at 0x8014a050). Getting
	# it backwards would still "work" here numerically if id and value matched,
	# so var[5] is set to 7 (≠ 5) deliberately.
	var vm := _make_vm()
	vm._insts = [
		_zero_inst(5), _add_inst(5, 7),                                     # var[5] = 7
		_zero_inst(6), _math_inst(EventInstruction.ADD_VARIABLE, "Add Variable", 6, 5),
	]
	vm.start()
	vm._tick_once()
	_assert_eq(vm._var_get(6), 7, "Add Variable(6,5) added var[5]'s VALUE (7), not the id")

	# The store masks a word var to u32, so a subtraction below zero reads back as
	# ~4 billion unless the VM re-widens it. ROM arithmetic is signed.
	var vm2 := _make_vm()
	vm2._insts = [
		_zero_inst(5), _add_inst(5, 7),
		_zero_inst(6), _add_inst(6, 10),
		_math_inst(EventInstruction.SUBTRACT_VARIABLE, "Subtract Variable", 5, 6),
	]
	vm2.start()
	vm2._tick_once()
	_assert_eq(vm2._var_signed(5), -3, "Subtract Variable(5,6): 7 - 10 reads back as -3, not 2^32-3")
	_assert_true(vm2._running, "the arithmetic family never halts the VM")

	# Divide by zero ABORTS the fiber in ROM (0x8014a170's guard jumps to
	# event_fiber_mark_complete) — it must not write and must not fall through.
	var vm3 := _make_vm()
	vm3._insts = [
		_zero_inst(6),
		_math_inst(EventInstruction.DIVIDE_VARIABLE, "Divide Variable", 5, 6),
		_add_inst(9, 1),
	]
	vm3.vars_store.set_var(5, 12)
	vm3.start()
	vm3._tick_once()
	_assert_eq(vm3._var_get(9), 0, "divide-by-zero ended the fiber (the trailing Add never ran)")
	_assert_eq(vm3._var_get(5), 12, "divide-by-zero wrote nothing")


# --- Cycle 6: the 0xA0–0xA5 comparison ALU -----------------------------------

func _test_comparisons_write_their_boolean_into_var0() -> void:
	# A = var[0] = 3, B = var[1] = 5. Each comparison is run on its own VM so the
	# writeback into var[0] cannot leak between cases — which is itself the point:
	# the boolean OVERWRITES operand A (ROM `sw v1, 0x0(v0)` at 0x8014a00c).
	var cases := [
		[EventInstruction.VARIABLE_LE, "Variable <=", 1],
		[EventInstruction.VARIABLE_GE, "Variable >=", 0],
		[EventInstruction.VARIABLE_EQ, "Variable ==", 0],
		[EventInstruction.VARIABLE_NE, "Variable !=", 1],
		[EventInstruction.VARIABLE_LT, "Variable <", 1],
		[EventInstruction.VARIABLE_GT, "Variable >", 0],
	]
	for c in cases:
		var vm := _make_vm()
		vm._insts = [_compare_inst(int(c[0]), String(c[1]))]
		vm.start()
		vm.vars_store.set_var(ScenarioVMClass.VAR_COMPARE_A, 3)
		vm.vars_store.set_var(ScenarioVMClass.VAR_COMPARE_B, 5)
		vm._tick_once()
		_assert_eq(vm._var_get(ScenarioVMClass.VAR_COMPARE_A), int(c[2]),
			"%s : 3 ? 5 -> var[0]==%d" % [String(c[1]), int(c[2])])

	# Signed, not unsigned: -1 <= 5 (ROM `slt`). An unsigned read makes -1 huge
	# and inverts every ordering comparison.
	var vm_signed := _make_vm()
	vm_signed._insts = [_compare_inst(EventInstruction.VARIABLE_LT, "Variable <")]
	vm_signed.start()
	vm_signed.vars_store.set_var(ScenarioVMClass.VAR_COMPARE_A, -1)
	vm_signed.vars_store.set_var(ScenarioVMClass.VAR_COMPARE_B, 5)
	vm_signed._tick_once()
	_assert_eq(vm_signed._var_get(ScenarioVMClass.VAR_COMPARE_A), 1,
		"Variable < is SIGNED: -1 < 5")


# --- Cycle 7: the scn-27 tail, both arms -------------------------------------

# The instruction shape of `Returning to Igros` (scn 27) pc 121–132, with the
# guarded block reduced to one observable write (the real one is `Wait 20;
# Switch Track 1`). `Add Variable(0, flag)` stages the flag into the comparison
# scratch pair; `Add(1, 0)` stages the constant 0; `Variable ==` leaves the
# boolean in var[0]; `Jump Forward If Zero` skips to `Forward Target 1` when that
# boolean is ZERO — i.e. when the comparison was FALSE.
func _igros_tail_insts(flag_var: int) -> Array:
	return [
		_zero_inst(ScenarioVMClass.VAR_COMPARE_A),
		_zero_inst(ScenarioVMClass.VAR_COMPARE_B),
		_math_inst(EventInstruction.ADD_VARIABLE, "Add Variable",
			ScenarioVMClass.VAR_COMPARE_A, flag_var),
		_add_inst(ScenarioVMClass.VAR_COMPARE_B, 0),
		_compare_inst(EventInstruction.VARIABLE_EQ, "Variable =="),
		_label_inst(EventInstruction.JUMP_FORWARD_IF_ZERO, "Jump Forward If Zero", 1),
		_add_inst(9, 1),                                                   # the guarded block
		_label_inst(EventInstruction.FORWARD_TARGET, "Forward Target", 1),
		_add_inst(10, 1),                                                  # after the label
		_event_end_inst(),
	]


func _test_jump_forward_if_zero_is_the_igros_tail() -> void:
	# flag == 0 → `0 == 0` is TRUE → var[0]==1 → the jump does NOT fire and the
	# guarded block runs. This is the arm the live walk takes.
	var vm := _make_vm()
	vm._insts = _igros_tail_insts(508)
	vm.start()
	vm.vars_store.set_var(508, 0)
	vm._tick_once()
	_assert_eq(vm._var_get(9), 1, "flag==0 → compare TRUE → the guarded block ran")
	_assert_eq(vm._var_get(10), 1, "…and the script continued past the label")
	_assert_true(not vm._contexts[0].alive, "…and reached Event End")

	# flag == 1 → `1 == 0` is FALSE → var[0]==0 → the jump fires and the guarded
	# block is skipped. `if (cond) { block }` compiles to "false jumps past it".
	var vm2 := _make_vm()
	vm2._insts = _igros_tail_insts(508)
	vm2.start()
	vm2.vars_store.set_var(508, 1)
	vm2._tick_once()
	_assert_eq(vm2._var_get(9), 0, "flag==1 → compare FALSE → the guarded block was SKIPPED")
	_assert_eq(vm2._var_get(10), 1, "…the jump landed AFTER the Forward Target anchor")
	_assert_true(not vm2._contexts[0].alive, "…and reached Event End")


# --- Cycle 8: the unconditional jumps ----------------------------------------

func _test_unconditional_jumps_find_their_anchors() -> void:
	# `0xD1 Jump Forward` always jumps, and matches `0xD2` anchors BY ID — a scan
	# that took the first anchor it saw would land on id 1 here instead of id 2.
	var vm := _make_vm()
	vm._insts = [
		_label_inst(EventInstruction.JUMP_FORWARD, "Jump Forward", 2),
		_add_inst(9, 1),
		_label_inst(EventInstruction.FORWARD_TARGET, "Forward Target", 1),
		_add_inst(10, 1),
		_label_inst(EventInstruction.FORWARD_TARGET, "Forward Target", 2),
		_add_inst(11, 1),
		_event_end_inst(),
	]
	vm.start()
	vm._tick_once()
	_assert_eq(vm._var_get(9), 0, "Jump Forward skipped the instruction after it")
	_assert_eq(vm._var_get(10), 0, "Jump Forward matched the anchor BY ID, not the first one")
	_assert_eq(vm._var_get(11), 1, "Jump Forward landed after Forward Target id=2")

	# A forward scan STOPS at Event End, and a jump that finds no anchor ends the
	# fiber rather than falling through — falling through would run the very block
	# the jump exists to skip.
	var vm2 := _make_vm()
	vm2._insts = [
		_label_inst(EventInstruction.JUMP_FORWARD, "Jump Forward", 7),
		_add_inst(9, 1),
		_event_end_inst(),
	]
	vm2.start()
	vm2._tick_once()
	_assert_eq(vm2._var_get(9), 0, "an unmatched Jump Forward did not fall through")
	_assert_true(not vm2._contexts[0].alive, "an unmatched Jump Forward ended the fiber")

	# `0xD3 Jump Back` scans BACKWARD for a `0xD5 Back Target`. One pass only —
	# the second time through, the flag makes the compare false and the jump is
	# skipped, so the loop terminates instead of spinning the drain forever.
	var vm3 := _make_vm()
	vm3._insts = [
		_label_inst(EventInstruction.BACK_TARGET, "Back Target", 1),
		_add_inst(9, 1),
		_zero_inst(ScenarioVMClass.VAR_COMPARE_A),
		_zero_inst(ScenarioVMClass.VAR_COMPARE_B),
		_math_inst(EventInstruction.ADD_VARIABLE, "Add Variable",
			ScenarioVMClass.VAR_COMPARE_A, 9),
		_add_inst(ScenarioVMClass.VAR_COMPARE_B, 2),
		_compare_inst(EventInstruction.VARIABLE_LT, "Variable <"),
		_label_inst(EventInstruction.JUMP_FORWARD_IF_ZERO, "Jump Forward If Zero", 1),
		_label_inst(EventInstruction.JUMP_BACK, "Jump Back", 1),
		_label_inst(EventInstruction.FORWARD_TARGET, "Forward Target", 1),
		_event_end_inst(),
	]
	vm3.start()
	vm3._tick_once()
	_assert_eq(vm3._var_get(9), 2, "Jump Back re-ran the body once (var[9] climbed 1 -> 2)")
	_assert_true(not vm3._contexts[0].alive, "the loop terminated at Event End")
