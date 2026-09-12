extends Node
## Regression guard for the stepping-consistency invariant:
##
##   Parking at PC N and stepping once == selecting PC N+1.
##
## "Select N+1" (`set_rewind_target(N+1)`) resets to a fresh main context at PC 0
## and REPLAYS the whole script at high speed. "N + step" (`set_rewind_target(N)`
## then `step(1)`) CONTINUES from the live paused state, advancing one opcode.
## Both share `_begin_fast_play` and the `_process` fast-play park predicate, so
## they land at the SAME main PC by construction (the `_drain_context` target-halt
## guard pins PC at the target). The open question is whether the OBSERVABLE RENDER
## STATE at that PC — the in-flight motion offset and the unit anim clock — is the
## same down both paths. It is the precondition for trustworthy beat-matching: if
## replay-from-zero and continue-from-live disagree, every A/B is built on sand.
##
## The suspected divergence (HANDOFF_scn6_stepping_consistency.md, suspect #1 +
## #4): a fast-play host frame drains a whole BATCH of ticks in one
## `_advance_frame`. Once the main PC is pinned at the target mid-batch, the
## REMAINING ticks of that batch still pump motion + the anim clock (they are not
## gated on the main PC). So a park OVER-RUNS the target by a partial batch, and
## that over-run differs depending on where you stop — making "N + step" and
## "select N+1" settle the in-flight slide at different offsets.
##
## Harness: a tree-less VM driven by direct `_process(_DT)` calls (the real
## per-host-frame fast-play entry point) until `_ff_active` clears, mirroring
## ScenarioClockUnificationTest. The oracle is the same one the beat-match uses:
## main PC + in-flight motion offset (elapsed_s) + anim-clock advance count.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioSteppingConsistencyTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _frees: Array = []

const _DT := 1.0 / 60.0
const _EPS := 1e-4
# Safety cap on fast-play host frames per drive (a real park settles in well
# under this; the loop is bounded so a stuck barrier can't hang the test).
const _MAX_FF_FRAMES := 4000


# Duck-typed Unit stand-in (as in ScenarioClockUnificationTest): the anim-drive
# contract is just `tick_based` + `advance_frame()` pumped once per tick.
class FakeAnimUnit extends Node3D:
	# Mirror the real Unit (ADR-0083): owner is settable, tick_based is derived.
	var clock_owner: ClockOwner = ClockOwner.SELF
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var advance_calls: int = 0
	func advance_frame(_normal_reps: int = 1, _react_reps: int = 1) -> void:
		advance_calls += 1


func _ready() -> void:
	_test_step_equals_select_across_pcs()
	_test_repeated_stepping_does_not_drift()

	for n in _frees:
		if is_instance_valid(n):
			n.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioSteppingConsistencyTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioSteppingConsistencyTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioSteppingConsistencyTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioSteppingConsistencyTest")
		get_tree().quit(0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# --- Instruction-list building ------------------------------------------------

func _wait_inst(t: int) -> Dictionary:
	return {"name": "Wait", "opcode": EventInstruction.WAIT, "offset": 0,
		"params": [{"name": "Time", "value": t}]}


func _nop_inst(op: int) -> Dictionary:
	# A non-blocking opcode: unbound, so during a fast-play (which forces
	# `play_through_skip_unknown` on) it clean-skips (pc += 1) without arming a
	# wait. A run of these is a non-blocking run — the case where "PC is the wrong
	# ruler" and a park can over-run the target.
	return {"name": "Nop", "opcode": op, "offset": 0, "params": []}


# A script that interleaves blocking Waits with non-blocking runs, so the tested
# PCs cover both wait-boundary PCs and mid-run PCs.
func _build_insts(nop: int) -> Array:
	return [
		_wait_inst(3),   # 0
		_nop_inst(nop),  # 1
		_nop_inst(nop),  # 2
		_wait_inst(4),   # 3
		_nop_inst(nop),  # 4
		_nop_inst(nop),  # 5
		_nop_inst(nop),  # 6
		_wait_inst(2),   # 7
		_nop_inst(nop),  # 8
		_wait_inst(5),   # 9
		_nop_inst(nop),  # 10
		_nop_inst(nop),  # 11
		_wait_inst(3),   # 12
		_nop_inst(nop),  # 13
	]


func _find_unbound_op(vm) -> int:
	# Pick an opcode byte with no registered handler so it clean-skips under
	# fast-play. Scan downward from 0xFF to dodge the low, densely-bound bytes.
	for op in range(255, -1, -1):
		if not vm._handlers.has(op):
			return op
	return -1


# --- VM harness ---------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)   # _ready wires camera_director + box_pool + binds handlers
	_vms.append(vm)
	return vm


# Fresh, fully-set-up VM: insts loaded, started, with a tick-driven anim unit
# attached (after start(), so reset_all doesn't wipe it). The anim clock advances
# once per VM tick — including the ticks a fast-play batch runs AFTER pinning the
# main PC at its target — so its cumulative count is a faithful proxy for the
# in-flight render state (motion offset, pose index) at the park. A manual
# ScenarioMotion can't be used here: `set_rewind_target` calls `reset_all`, which
# clears `actors`, and nothing re-arms a hand-attached slide on replay.
func _make_scene(nop: int) -> ScenarioVMClass:
	var vm := _make_vm()
	vm._insts = _build_insts(nop)
	vm.start()

	var au := FakeAnimUnit.new()
	add_child(au)
	_frees.append(au)
	vm.units_by_id[7] = au
	return vm


# Drive a fast-play (rewind or step) to completion: call the real per-host-frame
# entry point until it re-pauses (`_ff_active` clears). Returns true if it settled
# before the safety cap.
func _drive_ff(vm) -> bool:
	var i := 0
	while vm._ff_active and i < _MAX_FF_FRAMES:
		vm._process(_DT)
		i += 1
	return not vm._ff_active


# The beat-match oracle: main PC + anim-clock advance count (render-state proxy).
func _snapshot(vm) -> Dictionary:
	var au: FakeAnimUnit = vm.units_by_id[7]
	return {
		"pc": vm.get_pc(),
		"anim": au.advance_calls,
		"vm_tick": vm._vm_tick,
	}


func _fmt(s: Dictionary) -> String:
	return "pc=%d anim=%d tick=%d" % [s.pc, s.anim, s.vm_tick]


# --- The invariant ------------------------------------------------------------

func _test_step_equals_select_across_pcs() -> void:
	var probe := _make_vm()
	var nop := _find_unbound_op(probe)
	_ok(nop >= 0, "found an unbound opcode byte to use as a NOP (%d)" % nop)
	if nop < 0:
		return

	var last := _build_insts(nop).size()   # 14
	for n in range(1, last - 1):           # N = 1..12 → N+1 = 2..13
		# Path A — "select N+1": replay from zero to N+1.
		var a_vm := _make_scene(nop)
		a_vm.set_rewind_target(n + 1)
		var a_ok := _drive_ff(a_vm)

		# Path B — "N + step": rewind to N, then one step to N+1.
		var b_vm := _make_scene(nop)
		b_vm.set_rewind_target(n)
		var b1_ok := _drive_ff(b_vm)
		b_vm.step(1)
		var b2_ok := _drive_ff(b_vm)

		var a := _snapshot(a_vm)
		var b := _snapshot(b_vm)
		var settled := a_ok and b1_ok and b2_ok
		_ok(settled, "N=%d: both fast-plays settled before the cap" % n)

		var pc_same: bool = a.pc == b.pc
		var anim_same: bool = a.anim == b.anim
		_ok(pc_same and anim_same,
			"N=%d: (park N + step) == (select N+1)   A[%s]  B[%s]" %
				[n, _fmt(a), _fmt(b)])


# Compounding guard: rewind once to PC 1, then walk forward one `step(1)` at a
# time. At EVERY landing PC the running (continue-from-live) state must still equal
# a FRESH select of that PC. This catches a fix that only cancels the off-by-one
# for a single step but lets it re-accrue across a run — stepping through a K-opcode
# non-blocking run must not drift K ticks ahead of selecting its end.
func _test_repeated_stepping_does_not_drift() -> void:
	var probe := _make_vm()
	var nop := _find_unbound_op(probe)
	if nop < 0:
		return

	var last := _build_insts(nop).size()
	var walker := _make_scene(nop)
	walker.set_rewind_target(1)
	if not _drive_ff(walker):
		_ok(false, "walk: initial rewind to PC 1 settled")
		return

	for target in range(2, last):
		walker.step(1)
		var stepped_ok := _drive_ff(walker)

		var fresh := _make_scene(nop)
		fresh.set_rewind_target(target)
		var fresh_ok := _drive_ff(fresh)

		var w := _snapshot(walker)
		var f := _snapshot(fresh)
		_ok(stepped_ok and fresh_ok, "walk→%d: both settled" % target)
		_ok(w.pc == f.pc and w.anim == f.anim,
			"walk→%d: repeated-step state == fresh select   step[%s]  select[%s]" %
				[target, _fmt(w), _fmt(f)])
