extends Node
## Regression guard for the {11} pending-pose latch STEP BOUNDARY
## (SCENARIO_WAIT_SEMANTICS.md §8k — the H3 stepper-boundary fix).
##
## PSX RE (live single-pass `scn_step` sweep, scn6 pc210→225): the {11} Unit Anim
## latch (`unit+0x0C`) is consumed — the pose painted into `+0x1DC` — on the FIRST
## FRAME THAT ELAPSES after the latch, and a frame elapses ONLY when the main
## thread yields inside a blocking wait. So the latch PERSISTS across intervening
## non-blocking opcodes (a `{3B}` Sprite-Move arm, another `{11}`) and across a
## debug PARK, and is painted only when the next `{F1}`/`{6F}` wait spins a frame.
## Measured persistence: `{11}@220`'s latch survived pc221/222/223 and painted at
## the `{6F}@224` wait — 3 non-blocking opcodes later.
##
## Godot used to consume the latch on EVERY accumulator tick, so in the F3 stepper
## the pose leaked onto the wrong opcode boundary: it painted while genuinely
## PARKED (the paused accumulator kept ticking the consume) and on a step OVER a
## non-blocking opcode. The fix gates the consume on `_main_ctx_blocked()` — a
## wait-frame actually being spent this tick. This test mechanizes that: drive the
## real per-host-frame fast-play entry point (`_process`) and assert a manually
## seeded latch is NOT consumed while parked or while stepping over non-blocking
## opcodes, and IS consumed the moment a Wait spins.
##
## The consume mechanism itself (latch → paint → clear) is guarded separately by
## ScenarioUnitAnimLatchTest; here we seed `actor(uid).pending_anim` directly and
## observe the -1 transition, so the test is independent of sprite-pipeline setup.
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/ScenarioLatchStepBoundaryTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

const _DT := 1.0 / 60.0
const _MAX_FF_FRAMES := 4000
const UID := 7
const SEED_ANIM := 511   # a carry-pose id; value is opaque to the gate under test

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_park_does_not_consume()
	_test_non_blocking_steps_persist_then_wait_consumes()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioLatchStepBoundaryTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioLatchStepBoundaryTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioLatchStepBoundaryTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioLatchStepBoundaryTest")
		get_tree().quit(0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# --- Harness (mirrors ScenarioSteppingConsistencyTest) ------------------------

func _wait_inst(t: int) -> Dictionary:
	return {"name": "Wait", "opcode": EventInstruction.WAIT, "offset": 0,
		"params": [{"name": "Time", "value": t}]}


func _nop_inst(op: int) -> Dictionary:
	# Unbound opcode → clean-skips under fast-play (which forces
	# play_through_skip_unknown on): a non-blocking opcode, arms no wait.
	return {"name": "Nop", "opcode": op, "offset": 0, "params": []}


# Mirror of the scn6 carry shape around pc210: a latch point, a run of
# non-blocking opcodes, then a blocking Wait.
#   0 Wait(2)   — settle to a clean pre-exec park at pc1
#   1 Nop       — stand-in for the {3B} Sprite-Move arm (non-blocking)
#   2 Nop       — another non-blocking opcode
#   3 Wait(3)   — the wait that finally spins a frame → consume here
#   4 Nop
func _build_insts(nop: int) -> Array:
	return [_wait_inst(2), _nop_inst(nop), _nop_inst(nop), _wait_inst(3), _nop_inst(nop)]


func _find_unbound_op(vm) -> int:
	for op in range(255, -1, -1):
		if not vm._handlers.has(op):
			return op
	return -1


func _make_scene() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	var nop := _find_unbound_op(vm)
	vm._insts = _build_insts(nop)
	vm.start()
	return vm


func _drive_ff(vm) -> bool:
	var i := 0
	while vm._ff_active and i < _MAX_FF_FRAMES:
		vm._process(_DT)
		i += 1
	return not vm._ff_active


func _pending(vm) -> int:
	return vm.actor(UID).pending_anim


# --- Invariant 1: a genuine PARK freezes the latch ----------------------------

func _test_park_does_not_consume() -> void:
	var vm := _make_scene()
	vm.set_rewind_target(1)   # park pre-exec pc1 (main un-blocked)
	_ok(_drive_ff(vm), "park: rewind to pc1 settled")
	_ok(vm.get_pc() == 1 and vm._paused, "park: parked at pc1, paused")

	# Seed the latch as a {11} at the park would. reset_all already ran (inside
	# set_rewind_target), so this survives to the next dispatched tick.
	vm.actor(UID).pending_anim = SEED_ANIM
	_ok(_pending(vm) == SEED_ANIM, "park: latch seeded (pending=%d)" % _pending(vm))

	# Drive the paused per-host-frame pipeline: the accumulator keeps ticking but
	# no wait-frame is being spent, so the latch must NOT be consumed.
	for _i in range(30):
		vm._process(_DT)
	_ok(_pending(vm) == SEED_ANIM,
		"park: latch NOT consumed across 30 paused frames (pending=%d, want %d)" %
			[_pending(vm), SEED_ANIM])


# --- Invariant 2: non-blocking steps persist; a Wait step consumes ------------

func _test_non_blocking_steps_persist_then_wait_consumes() -> void:
	var vm := _make_scene()
	vm.set_rewind_target(1)   # park pre-exec pc1
	_ok(_drive_ff(vm), "step: rewind to pc1 settled")

	vm.actor(UID).pending_anim = SEED_ANIM

	# Step over the non-blocking Nop@1 → parked pre-exec pc2. No frame elapsed.
	vm.step(1)
	_ok(_drive_ff(vm), "step: 1→2 settled")
	_ok(vm.get_pc() == 2, "step: landed pc2")
	_ok(_pending(vm) == SEED_ANIM,
		"step over non-blocking Nop@1 does NOT consume (pending=%d)" % _pending(vm))

	# Step over the non-blocking Nop@2 → parked pre-exec pc3. Still no frame.
	vm.step(1)
	_ok(_drive_ff(vm), "step: 2→3 settled")
	_ok(vm.get_pc() == 3, "step: landed pc3")
	_ok(_pending(vm) == SEED_ANIM,
		"step over non-blocking Nop@2 does NOT consume — latch persists across the "
		+ "run (pending=%d)" % _pending(vm))

	# Step over the blocking Wait(3)@3 → its frames spin, so the latch IS consumed.
	vm.step(1)
	_ok(_drive_ff(vm), "step: 3→4 settled")
	_ok(vm.get_pc() == 4, "step: landed pc4")
	_ok(_pending(vm) == -1,
		"step over blocking Wait@3 CONSUMES the latch (pending=%d, want -1)" % _pending(vm))
