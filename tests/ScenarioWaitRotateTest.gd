extends Node
# test-kind: logic
# seeded-break: ScenarioVM._rotate_done's final line inverted (`unit._rotate_state.is_empty()` -> `not ...`, "done" while rotating) — the {64} hold arms and the {65} slow-unit arm red (barriers arm not at all; post-barrier markers run immediately), handler-registry/absent-unit/watchdog arms stay green; GREEN unbroken on the reverted tree
## Tests for ScenarioVM's {64} Wait Rotate Unit / {65} Wait Rotate All barriers
## and the generic `wait_until` predicate-hold primitive they ride on.
##
## FFT decode (see `research/working_documents/scenario_1_captures/
## HANDOFF_wait_rotate_unit.md`): {64}/{65} share handler FUN_801498fc
## (@ 0x801498fc), a coroutine yield+poll loop that blocks the event script
## while the unit's 7-byte rotate command's +4 "active" flag is nonzero. The
## consumer FUN_8013f20c clears that flag the moment current facing reaches the
## target. Godot already implements the interpolation (`Unit._rotate_state` /
## `_tick_rotate`); these tests cover the missing barrier: the VM must HOLD the
## calling context until `_rotate_state` empties, then resume.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWaitRotateTest.tscn

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
	_test_handlers_registered()
	_test_wait_rotate_unit_holds_then_resumes()
	_test_wait_rotate_unit_absent_unit_does_not_block()
	_test_wait_rotate_all_holds_until_all_done()
	_test_wait_until_watchdog_force_releases()

	for u in _units:
		if is_instance_valid(u):
			u.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioWaitRotateTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWaitRotateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWaitRotateTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWaitRotateTest")
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


# Real Unit + AnimationStateController, manually wired (no scene). Mirrors
# UnitScenarioRotateTest: the scenario_rotate / _tick_rotate path only touches
# `anim_state`, `facing_angle`, and `_rotate_state`, so a tree-less Unit is a
# faithful stand-in for the rotation stepper the barrier polls.
func _make_unit(start_facing: int) -> Unit:
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = start_facing
	_units.append(unit)
	return unit


func _rotate_unit_inst(chunk_unit_id: int, facing: int, direction: int,
		speed: int, delay: int) -> Dictionary:
	return {
		"name": "Rotate Unit", "opcode": 0x2D, "offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": (chunk_unit_id >> 8) & 0xFF},
			{"name": "Facing", "value": facing},
			{"name": "Direction", "value": direction},
			{"name": "Speed", "value": speed},
			{"name": "Delay", "value": delay},
		],
	}


func _wait_rotate_unit_inst(chunk_unit_id: int) -> Dictionary:
	return {
		"name": "Wait Rotate Unit", "opcode": 0x64, "offset": 0,
		"params": [{"name": "Unit", "value": chunk_unit_id}],
	}


func _wait_rotate_all_inst() -> Dictionary:
	return {"name": "Wait Rotate All", "opcode": 0x65, "offset": 0, "params": []}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handlers_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.WAIT_ROTATE_UNIT),
		"_handlers has 'Wait Rotate Unit'")
	_assert_true(vm._handlers.has(EventInstruction.WAIT_ROTATE_ALL),
		"_handlers has 'Wait Rotate All'")


# --- Cycle 2: {2D}+{64} barrier holds the script during rotation -------------

func _test_wait_rotate_unit_holds_then_resumes() -> void:
	# Unit A: South (0x400) → North (0xC00) is byte 0x4→0xC, shortest path 8
	# steps (tie → CW); Speed 0 → step every 4 ticks (≈32 ticks total) — a
	# clearly multi-tick rotation so the barrier hold is observable.
	# Unit B (the POST-wait opcode) rotates only once A finishes; while the
	# barrier holds, B's rotate must NOT have armed. B targets East (0x000 on the
	# canonical wheel) so byte 0x4→0x0 is a real rotation, not an aligned no-op.
	var vm := _make_vm()
	var unit_a := _make_unit(FacingDirection.SOUTH)
	var unit_b := _make_unit(FacingDirection.SOUTH)
	vm.units_by_id = {1: unit_a, 2: unit_b}
	vm._insts = [
		_rotate_unit_inst(1, 0x0C, 0, 0, 0),  # rotate A → North (slow)
		_wait_rotate_unit_inst(1),            # barrier on A
		_rotate_unit_inst(2, 0x00, 0, 0, 0),  # rotate B → East (post-wait)
	]
	vm.start()

	# First tick: A's rotate arms, the barrier arms, dispatch yields. B must be
	# untouched (post-wait opcode not reached) and A must still be rotating.
	vm._tick_once()
	_assert_true(not unit_a._rotate_state.is_empty(),
		"after tick 1: unit A rotation armed (in flight)")
	_assert_true(unit_b._rotate_state.is_empty(),
		"after tick 1: unit B NOT yet rotated (barrier holding)")
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"after tick 1: main context holds a wait_until barrier")

	# Drive ticks until A's rotation completes. B must stay untouched for EVERY
	# tick the barrier holds; B may only arm on/after the tick A finishes.
	var b_armed_tick := -1
	var a_done_tick := -1
	var held_ticks := 1
	for t in range(2, 200):
		vm._tick_once()
		if a_done_tick < 0 and unit_a._rotate_state.is_empty():
			a_done_tick = t
		if b_armed_tick < 0 and not unit_b._rotate_state.is_empty():
			b_armed_tick = t
		# Invariant: B must never arm before A's rotation has finished.
		if b_armed_tick < 0:
			held_ticks = t
			_assert_true(unit_b._rotate_state.is_empty(),
				"tick %d: barrier still holding → B untouched" % t)
		if b_armed_tick >= 0:
			break

	_assert_true(a_done_tick > 1,
		"unit A rotation was genuinely multi-tick (done @tick %d)" % a_done_tick)
	_assert_true(b_armed_tick >= 0,
		"barrier eventually released → unit B rotate ran (@tick %d)" % b_armed_tick)
	_assert_true(b_armed_tick >= a_done_tick,
		"unit B armed only after A finished (B@%d >= A@%d)" %
			[b_armed_tick, a_done_tick])
	_assert_true(held_ticks > 1,
		"barrier held for multiple ticks (held %d)" % held_ticks)


# --- Cycle 3: absent unit short-circuits (PSX 0x7d0 not-deployed) ------------

func _test_wait_rotate_unit_absent_unit_does_not_block() -> void:
	# {64} on a unit id that resolves to nothing must NOT arm a barrier (PSX's
	# FUN_80133158 returns 0x7d0 → handler returns without blocking). The script
	# should sail straight through to the next opcode.
	var vm := _make_vm()
	var unit_b := _make_unit(FacingDirection.SOUTH)
	vm.units_by_id = {2: unit_b}
	vm._insts = [
		_wait_rotate_unit_inst(99),           # no such unit → no block
		_rotate_unit_inst(2, 0x00, 0, 0, 0),  # → East; should arm same tick
	]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"absent-unit Wait Rotate Unit armed NO barrier")
	_assert_true(not unit_b._rotate_state.is_empty(),
		"absent-unit Wait Rotate Unit fell through to next opcode (B rotated)")


# --- Cycle 4: {65} Wait Rotate All holds until EVERY unit is done ------------

func _test_wait_rotate_all_holds_until_all_done() -> void:
	# Two units rotate concurrently at different speeds; {65} must hold until the
	# SLOWER one finishes (every +4 flag == 0). Unit A: 4-step CCW @ speed 0
	# (slow). Unit B: 1-step @ speed 2 (fast). The post-barrier marker (rotate
	# C) must wait for A.
	var vm := _make_vm()
	var unit_a := _make_unit(FacingDirection.SOUTH)  # → North, slow
	var unit_b := _make_unit(FacingDirection.SOUTH)  # → 0x100, fast
	var unit_c := _make_unit(FacingDirection.SOUTH)  # marker, post-barrier
	vm.units_by_id = {1: unit_a, 2: unit_b, 3: unit_c}
	vm._insts = [
		_rotate_unit_inst(1, 0x0C, 0, 0, 0),  # A → North (slow, byte 0x4→0xC, ~32 ticks)
		_rotate_unit_inst(2, 0x01, 0, 2, 0),  # B → 0x100 (fast, byte 0x4→0x1, ~3 ticks)
		_wait_rotate_all_inst(),              # barrier: all rotations
		_rotate_unit_inst(3, 0x00, 0, 0, 0),  # C → East (post-barrier marker)
	]
	vm.start()
	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Wait Rotate All armed a barrier while rotations in flight")
	_assert_true(unit_c._rotate_state.is_empty(),
		"after tick 1: marker unit C NOT yet rotated")

	var c_armed_tick := -1
	for t in range(2, 200):
		vm._tick_once()
		# C must not arm while ANY rotation (A or B) is still active.
		if c_armed_tick < 0 and not unit_c._rotate_state.is_empty():
			c_armed_tick = t
			# At the moment the barrier releases, both A and B must be done.
			_assert_true(unit_a._rotate_state.is_empty(),
				"barrier released only after A done")
			_assert_true(unit_b._rotate_state.is_empty(),
				"barrier released only after B done")
			break
	_assert_true(c_armed_tick > 2,
		"Wait Rotate All held for the SLOW unit (released @tick %d)" % c_armed_tick)


# --- Cycle 5: watchdog force-releases a never-clearing predicate -------------

func _test_wait_until_watchdog_force_releases() -> void:
	# PSX has no watchdog (it trusts the consumer to clear the flag); Godot must
	# not let a never-true predicate deadlock the VM. `_hold_wait_until` returns
	# true (keep holding) up to and including the deadline tick, then force-clears
	# past it.
	var vm := _make_vm()
	vm.start()
	var ctx = vm._contexts[0]

	# Satisfied predicate releases immediately and clears.
	ctx.wait_until = func() -> bool: return true
	_assert_true(not vm._hold_wait_until(ctx),
		"satisfied predicate releases (returns false = don't hold)")
	_assert_true(not ctx.wait_until.is_valid(),
		"wait_until cleared once predicate satisfied")

	# Never-true predicate holds until the deadline passes.
	ctx.wait_until = func() -> bool: return false
	vm._vm_tick = 500
	ctx.wait_until_deadline_tick = 500
	_assert_true(vm._hold_wait_until(ctx),
		"at deadline tick: still holds (vm_tick == deadline)")
	_assert_true(ctx.wait_until.is_valid(),
		"at deadline tick: predicate still armed")
	vm._vm_tick = 501
	_assert_true(not vm._hold_wait_until(ctx),
		"past deadline: watchdog force-releases")
	_assert_true(not ctx.wait_until.is_valid(),
		"past deadline: wait_until cleared by watchdog")
