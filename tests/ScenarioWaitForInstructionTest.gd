extends Node
# test-kind: logic
# seeded-break: the kind-4 camera liveness predicate in ScenarioVM._task_liveness is inverted (`not camera_director.is_idle()` -> `camera_director.is_idle()`, live-while-idle) — all eight Task=4 arms red (both the lerp/spline hold arms and the no-camera fall-through arm flip), Task=1/8/11 + registry arms stay green; GREEN unbroken on the reverted tree
## Tests for ScenarioVM's Wait For Instruction(Task=N) — a cooperative-task
## barrier — and its per-kind `wait_until` predicate dispatch.
##
## `Task` names a KIND of async activity; the opcode holds the calling script
## until no activity of that kind is still running, then resumes. Per kind:
## Task=4 → camera motion settled (lerp/chain/queue idle); Task=8 → spawned child
## cutscene-block coroutines drained; Task=1 → dialog box / on-map text overlay
## clear; Task=56 -> the {78} Display Conditions screen finished. The one kind with
## no modeled activity (52 EVTCHR load, synchronous in Godot) falls straight through.
## PSX provenance:
## research/working_documents/scenario_1_captures/wait_for_instruction_halt_decode.md.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWaitForInstructionTest.tscn

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
var _stubs: Array = []


## Minimal DialogueOverlay stand-in: the kind-1 predicate calls `is_active()`, and
## `ScenarioVM._tick_once` pumps the overlay via `advance_frames` while it's active
## (the 60 Hz typewriter reveal) — the stub no-ops that so the tick doesn't error.
class StubOverlay extends Node:
	var active: bool = false
	# When true, each pumped `advance_frames` bumps `_progress` — simulating a
	# typewriter that keeps revealing glyphs (a legitimately-long narration). The
	# VM's Task=1 progress probe reads `overlay_progress()`.
	var progressing: bool = false
	var _progress: int = 0
	func is_active() -> bool:
		return active
	func advance_frames(_n: int) -> void:
		if progressing:
			_progress += 1
	func overlay_progress() -> int:
		return _progress


func _ready() -> void:
	_test_handler_registered()
	_test_task_registry_populated()
	_test_task4_holds_while_camera_active_then_resumes()
	_test_task4_holds_through_fusion_spline()
	_test_task4_no_camera_falls_through()
	_test_task1_overlay_holds_then_resumes()
	_test_task1_overlay_progress_holds_past_watchdog()
	_test_task1_overlay_stall_force_releases()
	_test_task1_no_overlay_falls_through()
	_test_task8_holds_while_child_block_alive()
	_test_task52_evtchr_falls_through()
	_test_task56_no_task_falls_through()
	_test_task11_holds_while_motion_live_then_resumes()
	_test_task11_no_motion_falls_through()
	_test_task11_no_unit_filter_holds_on_any_actor()
	_test_unknown_kind_warns_and_falls_through()
	_test_instant_kinds_do_not_warn()

	for u in _units:
		if is_instance_valid(u):
			u.free()
	for s in _stubs:
		if is_instance_valid(s):
			s.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioWaitForInstructionTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWaitForInstructionTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWaitForInstructionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWaitForInstructionTest")
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


func _make_unit(start_facing: int) -> Unit:
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = start_facing
	_units.append(unit)
	return unit


func _make_overlay() -> StubOverlay:
	var ov := StubOverlay.new()
	add_child(ov)
	_stubs.append(ov)
	return ov


func _wfi_inst(task: int) -> Dictionary:
	return {
		"name": "Wait For Instruction", "opcode": 0xE5, "offset": 0,
		"params": [{"name": "Task", "value": task}],
	}


# Rotate Unit as a post-barrier MARKER: it leaves an observable `_rotate_state`
# on its target the moment it runs. While a barrier holds, the marker must stay
# untouched. Facing=0x04 → target 0x400 (byte 0x4 = SOUTH, per Unit's
# `_CARDINAL_TO_12BIT`), so the marker unit is spawned facing NORTH (0xC00) — a
# DIFFERENT byte — otherwise `scenario_rotate` hits its already-aligned fast path,
# snaps, and leaves `_rotate_state` EMPTY (the marker would read as "never ran").
func _rotate_marker_inst(chunk_unit_id: int) -> Dictionary:
	return {
		"name": "Rotate Unit", "opcode": 0x2D, "offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": 0},
			{"name": "Facing", "value": 0x04},  # → target 0x400 (SOUTH)
			{"name": "Direction", "value": 0},
			{"name": "Speed", "value": 0},
			{"name": "Delay", "value": 0},
		],
	}


func _wait_inst(ticks: int) -> Dictionary:
	return {
		"name": "Wait", "opcode": 0xF1, "offset": 0,
		"params": [{"name": "Time", "value": ticks}],
	}


func _block_end_inst() -> Dictionary:
	return {"name": "Block End", "opcode": 0x2B, "offset": 0, "params": []}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handler_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.WAIT_FOR_INSTRUCTION),
		"_handlers has 'Wait For Instruction'")


# The cooperative-task registry is the generic barrier model: kind→liveness table
# populated once, one predicate per modeled kind. The modeled kinds must be present;
# the deliberately-unmodeled one (52 EVTCHR load, synchronous here) must be ABSENT so
# its barrier falls straight through, matching PSX.
#
# 🔴 56 (0x38) MOVED FROM THE SECOND LIST TO THE FIRST. It was booked "no PSX task
# exists" and fell through silently; it is {78} Display Conditions' OWN kind —
# `0x801CAFD4`'s first act is `0x80149D48(0x38)`, and every {78} in all 500 events is
# followed by `{E5} 38 00` (BATTLE_RESULTS_SCREEN.md §13). What it holds on is asserted
# behaviourally in ScenarioDarkScreenTest, beside the {76}/{77} pair every {78} runs
# between; this arm only pins that the registration exists.
func _test_task_registry_populated() -> void:
	var vm := _make_vm()
	for kind in [vm.TASK_DIALOG, vm.TASK_CAMERA, vm.TASK_BLOCK, vm.TASK_DARKSCREEN,
			vm.TASK_SHOWGRAPHIC, vm.TASK_CONDITIONS]:
		_assert_true(vm._task_liveness.has(kind),
			"registry has modeled kind %d" % kind)
	_assert_true(not vm._task_liveness.has(52),
		"registry omits unmodeled kind 52 (falls through)")
	# kind 0x0B (11) = the sprite-move cooperative task — the generic, unit-filter-
	# free sibling of {6F} Wait Sprite Move (SPRITE_MOVE_INVESTIGATION.md). scn6's
	# carry-down uses {E5} Task=11 as its per-step barrier.
	_assert_true(vm._task_liveness.has(11),
		"registry has modeled kind 11 (sprite-move)")


# --- Cycle 2: Task=4 (camera) holds while a camera move is in flight ----------

func _test_task4_holds_while_camera_active_then_resumes() -> void:
	# Simulate an in-flight camera lerp (the kind-4 predicate `_camera_idle`
	# reads `_cam_lerp_active` directly — the rotate test's analogue for driving
	# the real per-frame lerp, which `_tick_once` does not advance).
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [
		_wfi_inst(4),              # barrier on camera kind 4
		_rotate_marker_inst(2),    # post-barrier marker
	]
	vm.start()
	vm.camera_director._cam_lerp_active = true     # camera glide in flight

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=4: barrier armed while camera lerp active")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=4: marker NOT run while barrier holds")

	# Hold across several ticks while the camera is still moving.
	for _t in range(5):
		vm._tick_once()
	_assert_true(marker._rotate_state.is_empty(),
		"Task=4: marker still untouched after 5 held ticks")

	# Camera settles → barrier releases → marker runs.
	vm.camera_director._cam_lerp_active = false
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=4: barrier released once camera idle")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=4: marker ran after camera settled")


# The load-bearing prayer case: the Task=4 barrier must hold through the whole
# fusion-chain swoop, not just a per-frame lerp. PSX ground truth
# (probe_prayer_interp_hold.py): the interpreter sat on Task=4 for ~135f while the
# kind-4 camera task was alive across the 6-waypoint fusion swoop. In Godot the
# swoop is owned by `_chain_spline`, so `_camera_idle` (hence the kind-4 predicate)
# must stay false while the spline is non-null.
func _test_task4_holds_through_fusion_spline() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(4), _rotate_marker_inst(2)]
	vm.start()
	vm.camera_director._chain_spline = RefCounted.new()  # fusion swoop owns the camera

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=4: barrier armed while fusion spline owns the camera")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=4: marker NOT run while fusion swoop in flight")

	for _t in range(5):
		vm._tick_once()
	_assert_true(marker._rotate_state.is_empty(),
		"Task=4: marker still untouched through the swoop")

	# Spline drains → camera idle → barrier releases → marker runs.
	vm.camera_director._chain_spline = null
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=4: barrier released once the fusion spline drained")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=4: marker ran after the swoop finished")


# --- Cycle 3: Task=4 with no camera in flight short-circuits ------------------

func _test_task4_no_camera_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(4), _rotate_marker_inst(2)]
	vm.start()
	# _cam_lerp_active false, _chain_spline null, _camera_queue empty by default.
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=4 (no camera): no barrier armed")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=4 (no camera): fell through to marker same tick")


# --- Cycle 4: Task=1 (overlay) holds until the typewriter clears ---------------

func _test_task1_overlay_holds_then_resumes() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	var overlay := _make_overlay()
	vm.units_by_id = {2: marker}
	vm.dialogue_overlay = overlay
	vm._insts = [_wfi_inst(1), _rotate_marker_inst(2)]
	vm.start()
	overlay.active = true          # prayer typewriter still running

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=1: barrier armed while overlay active")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=1: marker NOT run while overlay types")

	overlay.active = false         # typewriter finished
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=1: barrier released once overlay done")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=1: marker ran after overlay cleared")


# --- Cycle 4b: Task=1 overlay hold survives past the fixed watchdog while the ---
# typewriter keeps making progress. The scenario-8 Gariland narration is a
# multi-page block that types for 30-40 s — longer than _OVERLAY_TYPEWRITER_
# WATCHDOG_TICKS (1800 = 30 s). A fixed deadline force-released it mid-narration,
# so {33} Color Field dispatched while the text was still up (screen-colour
# divergence, Part Z §Z.5). The progress-aware watchdog must hold the barrier for
# the WHOLE narration as long as glyphs keep revealing.
func _test_task1_overlay_progress_holds_past_watchdog() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	var overlay := _make_overlay()
	vm.units_by_id = {2: marker}
	vm.dialogue_overlay = overlay
	vm._insts = [_wfi_inst(1), _rotate_marker_inst(2)]
	vm.start()
	overlay.active = true
	overlay.progressing = true      # typewriter keeps revealing glyphs each tick

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=1 progress: barrier armed while overlay active")
	_assert_true(vm._contexts[0].wait_until_progress.is_valid(),
		"Task=1 progress: a progress probe is attached to the overlay hold")

	# Tick well past the 1800-tick overlay watchdog while progress advances.
	for _t in range(vm._OVERLAY_TYPEWRITER_WATCHDOG_TICKS + 400):
		vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=1 progress: barrier STILL held past the watchdog while glyphs reveal")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=1 progress: colour-changer stays gated through the long narration")

	# Narration finishes → overlay inactive → barrier releases → marker runs.
	overlay.active = false
	vm._tick_once()
	_assert_true(vm._contexts.is_empty() or not vm._contexts[0].wait_until.is_valid(),
		"Task=1 progress: barrier released once the narration completed")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=1 progress: marker ran after the narration cleared")


# --- Cycle 4c: a STUCK overlay (active but no progress) still force-releases, ---
# so the deadlock backstop survives the progress-aware change.
func _test_task1_overlay_stall_force_releases() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	var overlay := _make_overlay()
	vm.units_by_id = {2: marker}
	vm.dialogue_overlay = overlay
	vm._insts = [_wfi_inst(1), _rotate_marker_inst(2)]
	vm.start()
	overlay.active = true
	overlay.progressing = false     # overlay wedged — never advances

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=1 stall: barrier armed on the wedged overlay")

	# No progress for a full watchdog window → deadlock backstop fires. Once it
	# does, the main context runs the marker and terminates (reaped), so guard the
	# `_contexts[0]` access — an empty list is itself proof the barrier released.
	for _t in range(vm._OVERLAY_TYPEWRITER_WATCHDOG_TICKS + 5):
		vm._tick_once()
	_assert_true(vm._contexts.is_empty() or not vm._contexts[0].wait_until.is_valid(),
		"Task=1 stall: wedged overlay force-releases (deadlock backstop intact)")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=1 stall: marker ran after the force-release")


# --- Cycle 5: Task=1 with no overlay falls through (dialog gate path unchanged)-

func _test_task1_no_overlay_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	# No dialogue_overlay, no pending dialog gate → kind-1 predicate is already
	# true and _consume_dialog_gate is a no-op.
	vm._insts = [_wfi_inst(1), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=1 (no overlay): no barrier armed")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=1 (no overlay): fell through to marker same tick")


# --- Cycle 6: Task=8 holds while a spawned child block coroutine is alive ------

func _test_task8_holds_while_child_block_alive() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [
		_wfi_inst(8),              # pc 0: main barrier on child blocks
		_rotate_marker_inst(2),    # pc 1: main post-barrier marker
		_wait_inst(5),             # pc 2: child sits on a 5-tick wait
		_block_end_inst(),         # pc 3: child terminates here
	]
	vm.start()
	# Spawn a child coroutine (as Block Start would) parked on the Wait at pc 2.
	var child = ScenarioVMClass.ScriptContext.new()
	child.pc = 2
	child.label = "block@2"
	vm._contexts.append(child)

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=8: barrier armed while child block alive")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=8: marker NOT run while child runs")

	var marker_tick := -1
	var held_ticks := 0
	for t in range(2, 200):
		vm._tick_once()
		if not marker._rotate_state.is_empty():
			marker_tick = t
			break
		held_ticks = t
	_assert_true(marker_tick >= 0,
		"Task=8: barrier eventually released (marker ran @tick %d)" % marker_tick)
	_assert_true(held_ticks > 1,
		"Task=8: barrier held multiple ticks for the child (held %d)" % held_ticks)
	# Once released, only the main context survives (child reaped).
	_assert_eq(vm._contexts.size(), 1,
		"Task=8: child reaped after it drained")


# --- Cycle 7: Task=52 (cutscene sprite load — synchronous here) falls through --

func _test_task52_evtchr_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(52), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=52: no barrier (sprite load is synchronous here)")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=52: fell through to marker same tick")


# --- Cycle 8: Task=56 ({78} Display Conditions) falls through with no screen up -
# It used to fall through unconditionally because the kind was booked as having no
# PSX task at all. It is {78}'s own kind, so the release is CONDITIONAL now: nothing
# to wait for when no {78} has run, and a real barrier while a screen is on its clock
# (asserted in ScenarioDarkScreenTest). A script that emits `{E5} 38 00` without a
# preceding {78} must still not deadlock — which is this arm.

func _test_task56_no_task_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(56), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=56: no barrier when no {78} screen has run")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=56: fell through to marker same tick")


# --- Cycle 9: Task=11 (0x0B sprite-move) — the generic, unit-filter-free wait ---
# scn6's carry-down uses {E5} Task=11 between Sprite-Move steps. Before kind-0x0B
# was registered, the barrier no-op'd → the six steps armed in one tick and each
# `arm_motion` clobbered the prior in-flight slide → the descent collapsed to one
# step (too fast). These lock the fix: the barrier holds while a slide plays.

func _make_motion() -> ScenarioMotion:
	# dur_s long so the slide stays live across held ticks; `_tick_once` does NOT
	# advance motions (that's `_advance_frame` → `_advance_motions`), so liveness is
	# driven deterministically here via `snap_to_end`.
	var m := ScenarioMotion.new()
	m.start = Vector3.ZERO
	m.target = Vector3(1, 0, 0)
	m.dur_s = 100.0
	m.elapsed_s = 0.0
	return m


func _test_task11_holds_while_motion_live_then_resumes() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(11), _rotate_marker_inst(2)]
	vm.start()
	var m := _make_motion()
	vm.actor(2).motion = m          # a sprite-move in flight

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=11: barrier armed while a sprite-move is in flight")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=11: marker NOT run while the slide plays")

	for _t in range(5):
		vm._tick_once()
	_assert_true(marker._rotate_state.is_empty(),
		"Task=11: marker still untouched after 5 held ticks")

	m.snap_to_end()                 # slide finished
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=11: barrier released once the slide finished")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=11: marker ran after the slide finished")


func _test_task11_no_motion_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(11), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=11 (no slide): no barrier armed")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=11 (no slide): fell through to marker same tick")


func _test_task11_no_unit_filter_holds_on_any_actor() -> void:
	# {E5} Task=11 has NO +0x50 unit filter — it holds while ANY unit's slide is in
	# flight. scn6 walks Delita (5) + Ovelia (12) in lockstep; the barrier must wait
	# for both. Here the script's marker is unit 2 but the live slide is on unit 5.
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(11), _rotate_marker_inst(2)]
	vm.start()
	var m := _make_motion()
	vm.actor(5).motion = m          # a DIFFERENT unit is sliding

	vm._tick_once()
	_assert_true(vm._contexts[0].wait_until.is_valid(),
		"Task=11: barrier holds on ANOTHER unit's slide (no unit filter)")
	_assert_true(marker._rotate_state.is_empty(),
		"Task=11: marker held while unit 5 slides")

	m.snap_to_end()
	vm._tick_once()
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=11: marker ran once unit 5's slide finished")


# --- Cycle 10: registry drift stops failing silently --------------------------
# The scn6 carry-down bug was silent because an unregistered kind that DID have a
# modeled activity (0x0B) looked identical to a deliberately-unmodeled one. An
# unknown, non-instant kind now still falls through (never deadlocks) but is
# WARNED once; the known-instant kind (52) and every registered kind stay silent.

func _test_unknown_kind_warns_and_falls_through() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	vm._insts = [_wfi_inst(99), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	# No deadlock — an unknown kind must still fall through to keep play-through alive.
	_assert_true(not vm._contexts[0].wait_until.is_valid(),
		"Task=99 (unknown): no barrier armed — falls through, never deadlocks")
	_assert_true(not marker._rotate_state.is_empty(),
		"Task=99 (unknown): fell through to marker same tick")
	# ...but it is RECORDED, so a missing registration surfaces instead of hiding.
	_assert_true(vm._warned_task_kinds.has(99),
		"Task=99 (unknown): recorded as an unmodeled-kind warning")


func _test_instant_kinds_do_not_warn() -> void:
	var vm := _make_vm()
	var marker := _make_unit(FacingDirection.NORTH)
	vm.units_by_id = {2: marker}
	# 52 (EVTCHR load, synchronous) is KNOWN-instant: it falls through WITHOUT a
	# warning — deliberately unmodeled, not forgotten. 56 is silent for the OTHER
	# reason, and the two must not be confused: it is REGISTERED now, so the warn-once
	# path is never reached for it at all.
	vm._insts = [_wfi_inst(52), _wfi_inst(56), _rotate_marker_inst(2)]
	vm.start()
	vm._tick_once()
	_assert_true(not vm._warned_task_kinds.has(52),
		"Task=52 (known-instant): no warning")
	_assert_true(not vm._warned_task_kinds.has(56),
		"Task=56 (registered): no warning, and for a different reason than 52")
	_assert_true(vm._task_liveness.has(56),
		"Task=56 is silent because it is MODELED, not because it is unmodeled")
