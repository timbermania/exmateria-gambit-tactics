extends Node
## Pins the Camera Fusion Start (0x1d) / Camera Fusion End (0x1e) atomic-queue
## behavior verified by `probe_camera_vs_dialog_timing.py` on 2026-06-26:
##
## PSX dynamic capture (chapel cinematic, ATTACK.OUT chunk):
##   vsync=41 cyc=3628178805  PC=121 op=0x1d (Camera Fusion Start)
##   vsync=41 cyc=3628179524  PC=225 op=0x49 (Add Unit Start — NEXT opcode after
##                            the fusion bracket; PCs 122..224 SKIPPED)
##   vsync=41 cyc=3628183054  FUN_8013db9c queue-construction fiber fires
##   vsync=41 cyc=3628180517  PC=247 op=0xf1 (Wait 180 ticks)
##
## The PSX dispatcher (FUN_80143bd8) jumped PC=121 -> PC=225 in 719 cycles
## (one vsync), eating the entire 0x1d..0x1e bracket atomically. The 6
## Cameras' lerps drain through a background fiber while the VM races on.
##
## Godot mirror: `_op_camera_fusion_start` opens queue mode, every Camera
## inside the bracket appends to `_camera_queue`, `_op_camera_fusion_end`
## starts the chain. The VM never sets `_wait_ticks` for fusion-queued
## Cameras, so opcodes after the bracket (Wait, Display Message) fire
## immediately — exactly the parallelism the user observed on PSX.
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/ScenarioCameraFusionTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


class CameraStub extends RefCounted:
	var size: float = 8.0


class StubCamera extends Node3D:
	var takeover_count: int = 0
	var focus_point: Node3D
	var camera  # CameraStub

	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = CameraStub.new()

	func request_takeover(_owner) -> void:
		pass

	func apply_takeover(_pos: Vector3, _rot: Vector3, _ortho: float) -> void:
		takeover_count += 1


func _make_vm_with_camera() -> Dictionary:
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	return {"vm": vm, "cam": cam}


func _make_camera_inst(x: int, y: int, z: int, time_ticks: int) -> Dictionary:
	# Mirror the chunk JSON shape that `_params_dict` consumes.
	return {
		"name": "Camera", "opcode": 0x19,
		"offset": 0,
		"params": [
			{"name": "X", "value": x, "bytes": 2},
			{"name": "Z", "value": z, "bytes": 2},
			{"name": "Y", "value": y, "bytes": 2},
			{"name": "Angle", "value": 0, "bytes": 2},
			{"name": "Map Rotation", "value": 0, "bytes": 2},
			{"name": "Camera Rotation", "value": 0, "bytes": 2},
			{"name": "Zoom", "value": 4096, "bytes": 2},
			{"name": "Time", "value": time_ticks, "bytes": 2},
		]
	}


func _ready() -> void:
	_test_fusion_start_opens_queue_mode()
	_test_camera_in_fusion_appends_without_lerping()
	_test_fusion_end_starts_first_lerp_only()
	_test_camera_outside_fusion_is_non_blocking()
	_test_chain_advances_through_all_queued_items()
	_test_chain_handoff_uses_prev_target_as_new_start()
	_test_chain_handoff_carries_overshoot()
	_test_nonfusion_camera_cancels_in_flight_chain()

	print("\n=== ScenarioCameraFusionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioCameraFusionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraFusionTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# --- the tests ---------------------------------------------------------------

func _test_fusion_start_opens_queue_mode() -> void:
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	_assert_eq(vm.camera_director._in_camera_fusion, true, "fusion start sets _in_camera_fusion")
	_assert_eq(vm.camera_director._camera_queue.size(), 0, "fusion start clears the queue")
	vm.queue_free()
	rig.cam.queue_free()


func _test_camera_in_fusion_appends_without_lerping() -> void:
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	for i in range(6):
		vm.camera_director._op_camera(_make_camera_inst(100 * (i + 1), 0, 0, 60))
	_assert_eq(vm.camera_director._camera_queue.size(), 6, "all 6 cameras queued (no lerp started)")
	_assert_eq(vm.camera_director._cam_lerp_active, false, "no lerp started inside fusion")
	_assert_eq(vm.get_wait_ticks(), 0, "VM not blocked inside fusion — main wait_ticks stays 0")
	vm.queue_free()
	rig.cam.queue_free()


func _test_fusion_end_starts_first_lerp_only() -> void:
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 60))
	vm.camera_director._op_camera(_make_camera_inst(200, 0, 0, 30))
	vm.camera_director._op_camera(_make_camera_inst(300, 0, 0, 90))
	_assert_eq(vm.camera_director._camera_queue.size(), 3, "pre-fusion-end: 3 queued")
	vm.camera_director._op_camera_fusion_end({})
	_assert_eq(vm.camera_director._in_camera_fusion, false, "fusion end clears mode flag")
	_assert_eq(vm.camera_director._camera_queue.size(), 2, "fusion end pops + starts first; 2 remain")
	_assert_eq(vm.camera_director._cam_lerp_active, true, "first chain item lerp is active")
	# Crucially: VM is NOT blocked. The chain runs in `_process` while opcodes
	# after the fusion bracket (Wait, Display Message) dispatch immediately.
	_assert_eq(vm.get_wait_ticks(), 0, "VM not blocked after fusion end — main wait_ticks stays 0")
	vm.queue_free()
	rig.cam.queue_free()


func _test_camera_outside_fusion_is_non_blocking() -> void:
	# Standalone Camera (no fusion bracket) is NON-BLOCKING on the calling
	# context: PSX opcode 0x19 handler `FUN_801474a4` writes the lerp targets
	# and returns without calling `FUN_8014ca80` (the cooperative yield), so
	# the scenario VM races past Camera in the same vsync it dispatches it.
	# This is what lets the chapel parallel-block spawns at PC 100/114/127
	# run during the camera swoop at PC 99 — see BLOCK_EXECUTION_INVESTIGATION.md.
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 30))
	_assert_eq(vm.camera_director._cam_lerp_active, true, "standalone Camera starts lerp")
	_assert_eq(vm.get_wait_ticks(), 0, "standalone Camera does NOT arm main wait_ticks — lerp ticks in _process")
	vm.queue_free()
	rig.cam.queue_free()


func _test_chain_advances_through_all_queued_items() -> void:
	# Drive `_process(delta)` past each lerp's completion time and assert the
	# chain pops the next queued item until the queue drains. This is the
	# integration of `_op_camera_fusion_end` + `_process` + `_start_next_queued_camera`.
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	# 3 short lerps: 6 ticks each = 0.1s @ 60Hz
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 6))
	vm.camera_director._op_camera(_make_camera_inst(200, 0, 0, 6))
	vm.camera_director._op_camera(_make_camera_inst(300, 0, 0, 6))
	vm.camera_director._op_camera_fusion_end({})
	# After fusion end: 1 lerp active, 2 left in queue.
	_assert_eq(vm.camera_director._camera_queue.size(), 2, "post-end: 2 left in queue")
	_assert_eq(vm.camera_director._cam_lerp_active, true, "post-end: lerp active")

	# Drive 0.11s — enough to overshoot the first lerp's 0.1s duration.
	vm._process(0.11)
	_assert_eq(vm.camera_director._camera_queue.size(), 1, "after first lerp done: 1 left")
	_assert_eq(vm.camera_director._cam_lerp_active, true, "second lerp active")

	# Second pass — overshoot the second lerp.
	vm._process(0.11)
	_assert_eq(vm.camera_director._camera_queue.size(), 0, "after second lerp done: queue drained")
	_assert_eq(vm.camera_director._cam_lerp_active, true, "third (last) lerp active")

	# Third pass — overshoot the third lerp. Queue is empty so chain stops.
	vm._process(0.11)
	_assert_eq(vm.camera_director._camera_queue.size(), 0, "still drained")
	_assert_eq(vm.camera_director._cam_lerp_active, false, "third lerp complete, chain idle")

	vm.queue_free()
	rig.cam.queue_free()


func _approx_eq(a: Vector3, b: Vector3, eps: float = 1e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps


func _test_chain_handoff_uses_prev_target_as_new_start() -> void:
	# Pins the hypothesis-4 fix: at a chain boundary the new segment's
	# `_cam_start_pos` must equal the previous segment's `_cam_target_pos`,
	# not whatever the StubCamera reports as its live transform. This makes
	# the chain math independent of Godot's transform-flush timing.
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 6))   # → target_1
	vm.camera_director._op_camera(_make_camera_inst(2000, 0, 0, 6))  # → target_2
	vm.camera_director._op_camera_fusion_end({})
	# Capture seg-1's target before _process overwrites _cam_target_pos.
	var prev_target := vm.camera_director._cam_target_pos
	# Cross 0.1s boundary so seg 1 completes and seg 2 starts in the same frame.
	vm._process(0.11)
	# After handoff: seg 2's _cam_start_pos should equal seg 1's _cam_target_pos.
	# StubCamera doesn't move on apply_takeover (it just bumps a counter), so
	# pre-fix this assertion would catch _cam_start_pos = Vector3.ZERO (live
	# StubCamera position), not the seg-1 target.
	_assert_true(_approx_eq(vm.camera_director._cam_start_pos, prev_target),
		"chain handoff: seg2 _cam_start_pos == seg1 _cam_target_pos")
	vm.queue_free()
	rig.cam.queue_free()


func _test_chain_handoff_carries_overshoot() -> void:
	# Pins the hypothesis-1 fix: at a chain boundary the residual
	# (elapsed - duration) carries into the new segment as its initial
	# elapsed, instead of being discarded — eliminates the one-frame stall
	# at every chain boundary.
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 6))   # 0.1s
	vm.camera_director._op_camera(_make_camera_inst(200, 0, 0, 60))  # 1.0s — long enough to see overshoot
	vm.camera_director._op_camera_fusion_end({})
	# 0.105s = 0.1s seg1 + 0.005s overshoot. After the chain handoff, seg2's
	# elapsed should be ~0.005s, not 0.0.
	vm._process(0.105)
	_assert_eq(vm.camera_director._cam_lerp_active, true, "overshoot test: seg 2 lerp active")
	_assert_true(vm.camera_director._cam_lerp_elapsed_s > 0.004 and vm.camera_director._cam_lerp_elapsed_s < 0.006,
		"chain handoff carries overshoot (~0.005s into seg2)")
	vm.queue_free()
	rig.cam.queue_free()


func _test_nonfusion_camera_cancels_in_flight_chain() -> void:
	# Pins the chapel-cleanup fix: a non-fusion Camera opcode (e.g. PC=48 in
	# scenario 1) supersedes any chained-but-not-yet-applied poses from a
	# prior fusion bracket. Without this, `_start_next_queued_camera` would
	# pop the stale items when the override's own lerp completes and jerk
	# the camera back through the tail of the cancelled swoop.
	var rig := _make_vm_with_camera()
	var vm: ScenarioVMClass = rig.vm
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(100, 0, 0, 60))   # → 6 segments
	vm.camera_director._op_camera(_make_camera_inst(200, 0, 0, 60))
	vm.camera_director._op_camera(_make_camera_inst(300, 0, 0, 60))
	vm.camera_director._op_camera(_make_camera_inst(400, 0, 0, 60))
	vm.camera_director._op_camera(_make_camera_inst(500, 0, 0, 60))
	vm.camera_director._op_camera(_make_camera_inst(600, 0, 0, 60))
	vm.camera_director._op_camera_fusion_end({})
	_assert_eq(vm.camera_director._camera_queue.size(), 5, "pre-override: 5 left in queue (seg 1 running)")
	# Mid-chain non-fusion override (chapel PC=48 equivalent).
	vm.camera_director._op_camera(_make_camera_inst(840, 504, -220, 4))
	_assert_eq(vm.camera_director._camera_queue.size(), 0, "override drops the stale chain queue")
	_assert_eq(vm.camera_director._cam_lerp_active, true, "override starts its own lerp")
	# Drive past the override's completion — the chain must NOT restart.
	vm._process(0.10)  # 4 ticks / 60Hz = 0.067s, comfortably exceeded
	_assert_eq(vm.camera_director._camera_queue.size(), 0, "post-override completion: chain still empty")
	_assert_eq(vm.camera_director._cam_lerp_active, false, "no chain restart after override completes")
	vm.queue_free()
	rig.cam.queue_free()
