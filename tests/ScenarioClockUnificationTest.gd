extends Node
## Regression guard for ADR-0065 — scenario playback advances every time-driven
## system (opcode dispatch, unit motion, camera, unit anim clock) off the SINGLE
## 60 Hz VM tick, so a beat is a pure function of *tick count since a resync*,
## host-rate-independent.
##
## The forcing bug (SCENARIO6_RENDER_CLOCK_UNIFICATION.md): `ScenarioVM` used to
## run TWO clocks — event dispatch quantized to 60 Hz via `_tick_accumulator`,
## but motion / camera / the unit anim clock advanced on raw host render-delta.
## So the rendered sprite led the event PC by the fractional-tick residual, a
## bounded lead that grew within a non-blocking run and snapped to zero at each
## wait-boundary (the scn6 carry "beat-match" drift). PSX drives all of it off
## one vblank.
##
## This test is also the mechanized form of the ADR's Exp #2 (vsync-lock
## falsification): drive the VM with jittery, non-1/60 deltas and assert the
## render state (motion offset, anim frame index) is identical to a clean-60 run
## at equal tick counts. It goes RED on the two-clock code (motion tracks
## wall-clock, not the tick) and GREEN once the systems unify under `_tick_once`.
##
## Harness: a tree-less VM driven by direct `_advance_frame(delta)` calls (the
## real per-host-frame entry point), with a long-lived `Wait` keeping dispatch
## alive so `_vm_tick` counts every processed tick.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioClockUnificationTest.tscn

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
const _EPS := 1e-5


# A minimal duck-typed stand-in for Unit: the anim-drive contract the VM uses is
# just `tick_based` (settable) + `advance_frame()` (pumped once per tick). Not a
# real Unit so the test needs no atlas / animation-set / scene boot.
class FakeAnimUnit extends Node3D:
	# Mirror the real Unit (ADR-0083): owner is settable, tick_based is derived.
	var clock_owner: ClockOwner = ClockOwner.SELF
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var advance_calls: int = 0
	func advance_frame(_normal_reps: int = 1, _react_reps: int = 1) -> void:
		advance_calls += 1


func _ready() -> void:
	_test_motion_tracks_tick_clock_under_jitter()
	_test_motion_matches_between_clean_and_jitter()
	_test_anim_advances_once_per_tick()
	_test_units_flip_tick_based_on_start()

	for n in _frees:
		if is_instance_valid(n):
			n.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioClockUnificationTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioClockUnificationTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioClockUnificationTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioClockUnificationTest")
		get_tree().quit(0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _wait_inst(t: int) -> Dictionary:
	# {F1} Wait — parks the main context for `t` ticks, keeping dispatch alive
	# (so `_vm_tick` keeps counting) without any further opcodes firing.
	return {"name": "Wait", "opcode": EventInstruction.WAIT, "offset": 0,
		"params": [{"name": "Time", "value": t}]}


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)   # _ready wires camera_director + box_pool
	_vms.append(vm)
	return vm


# Register a long-lived slide on `vm` and return its ScenarioMotion. Actor +
# unit are added AFTER start() so reset_all doesn't wipe them.
func _attach_slide(vm: ScenarioVMClass, uid: int) -> ScenarioMotion:
	var unit := Node3D.new()
	add_child(unit)
	_frees.append(unit)
	vm.units_by_id[uid] = unit

	var m := ScenarioMotion.new()
	m.start = Vector3.ZERO
	m.target = Vector3(10000.0, 0.0, 0.0)   # far enough it never completes here
	m.dur_s = 10000.0
	m.elapsed_s = 0.0
	m.easing = 0
	m.weight = 1

	var actor := ScenarioActor.new()
	actor.motion = m
	vm.actors[uid] = actor
	return m


# Jitter stream: deterministic per-frame deltas that are never 1/60 — some fire
# zero ticks (sub-frame), some fire two (super-frame). This is what opens the
# two-clock gap; a clean 1/60 stream hides it.
func _jitter_deltas(count: int) -> Array:
	var mult := [0.3, 1.7, 0.4, 2.3, 0.9, 0.5, 1.9, 0.2]
	var out: Array = []
	for i in range(count):
		out.append(_DT * mult[i % mult.size()])
	return out


# --- Tests --------------------------------------------------------------------

# THE falsification: under a jittery host rate, the motion offset must remain a
# pure function of the VM tick count — `elapsed_s == _vm_tick / 60` every frame.
# Two-clock code advances motion on raw delta, so this diverges immediately.
func _test_motion_tracks_tick_clock_under_jitter() -> void:
	var vm := _make_vm()
	vm._insts = [_wait_inst(10_000_000)]
	vm.start()
	var m := _attach_slide(vm, 1)

	var worst := 0.0
	for d in _jitter_deltas(180):
		vm._advance_frame(d)
		worst = maxf(worst, absf(m.elapsed_s - float(vm._vm_tick) * _DT))
	_ok(worst < _EPS,
		"motion elapsed tracks tick clock under jitter (worst |elapsed - tick/60| = %.6f)" % worst)


# The same run driven clean-60 vs jittery must land the motion on the SAME offset
# at the SAME tick count (host-rate-independence, stated directly).
func _test_motion_matches_between_clean_and_jitter() -> void:
	var clean := _run_motion_samples(_const_deltas(180, _DT))
	var jitter := _run_motion_samples(_jitter_deltas(400))
	var worst := 0.0
	var compared := 0
	for tick in clean:
		if jitter.has(tick):
			worst = maxf(worst, absf(clean[tick] - jitter[tick]))
			compared += 1
	_ok(compared > 30, "clean/jitter share enough tick samples to compare (%d)" % compared)
	_ok(worst < _EPS,
		"motion offset identical clean-60 vs jitter at equal ticks (worst = %.6f)" % worst)


# Drive a fresh slide with `deltas`, returning {vm_tick -> elapsed_s} (first
# sample wins for a tick reached across multiple frames).
func _run_motion_samples(deltas: Array) -> Dictionary:
	var vm := _make_vm()
	vm._insts = [_wait_inst(10_000_000)]
	vm.start()
	var m := _attach_slide(vm, 1)
	var by_tick: Dictionary = {}
	for d in deltas:
		vm._advance_frame(d)
		if not by_tick.has(vm._vm_tick):
			by_tick[vm._vm_tick] = m.elapsed_s
	return by_tick


func _const_deltas(count: int, d: float) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(d)
	return out


# The anim clock must advance exactly once per VM tick — driven by the VM, not by
# Unit._process on host delta. A tick_based scenario unit gets `advance_frame()`
# pumped once per `_tick_once`.
func _test_anim_advances_once_per_tick() -> void:
	var vm := _make_vm()
	var u := FakeAnimUnit.new()
	add_child(u)
	_frees.append(u)
	vm.units_by_id[7] = u
	vm._insts = [_wait_inst(10_000_000)]
	vm.start()

	for d in _jitter_deltas(120):
		vm._advance_frame(d)
	_ok(u.advance_calls == vm._vm_tick,
		"tick_based unit advance_frame called once per tick (calls=%d, ticks=%d)"
			% [u.advance_calls, vm._vm_tick])


# Scenario entry flips every registered unit to tick_based mode (so Unit._process's
# delta-mode anim pump no-ops and the VM owns the clock). Restored on exit.
func _test_units_flip_tick_based_on_start() -> void:
	var vm := _make_vm()
	var u := FakeAnimUnit.new()
	add_child(u)
	_frees.append(u)
	vm.units_by_id[3] = u
	vm._insts = [_wait_inst(10_000_000)]
	vm.start()
	_ok(u.tick_based == true, "unit registered at scenario start is flipped to tick_based")
