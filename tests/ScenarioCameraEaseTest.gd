extends Node
## Pure tests for the scenario-camera ease curve + lerp envelope landed in
## commit 1dcccb1f. PSX dynamic capture (2026-06-24) verified the chapel
## cinematic uses LINEAR interpolation — the prior cosine ease introduced
## "go-stop-go" stutter at every Camera-opcode boundary.
##
## Pins down:
##   * `_curve(done)` endpoints + monotonicity across all modes.
##   * Per-mode shape: LINEAR identity, COSINE_A symmetric, COSINE_B asymmetric.
##   * `_advance_camera_lerp` envelope: LINEAR constant per-tick Δ, COSINE_A
##     peaking mid-segment.
##   * `time_ticks <= 1` snap path leaves `_cam_lerp_active == false`.
##   * Mid-lerp `camera_ease_mode` swap takes effect on the next advance
##     (no curve caching).
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/ScenarioCameraEaseTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


# StubCamera mirrors the minimal surface ScenarioVM touches on `player_camera`:
# `apply_takeover(pos, rot, ortho)` for the snap path, plus Node3D's
# `global_position` + nested `focus_point.global_rotation` + `camera.size`
# for the lerp setup in `_apply_camera_pose`. Records every apply_takeover()
# call so per-tick deltas can be sampled.
class CameraStub extends RefCounted:
	var size: float = 8.0

class StubCamera extends Node3D:
	var captured_positions: Array[Vector3] = []
	var captured_rotations: Array[Vector3] = []
	var captured_orthos: Array[float] = []
	var focus_point: Node3D
	var camera  # untyped — holds a CameraStub (or any object exposing `.size`)

	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = CameraStub.new()

	func apply_takeover(pos: Vector3, rot: Vector3, ortho: float) -> void:
		captured_positions.append(pos)
		captured_rotations.append(rot)
		captured_orthos.append(ortho)


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	return vm


func _ready() -> void:
	# Mode-independent curve invariants
	_test_curve_endpoints_all_modes()
	_test_curve_monotonic_all_modes()

	# Per-mode shape
	_test_linear_is_identity()
	_test_cosine_a_symmetric_at_quarter_points()
	_test_cosine_a_midpoint_half()
	_test_cosine_b_midpoint_value()
	_test_cosine_b_asymmetric_at_quarter_points()

	# Lerp envelope (integration)
	_test_linear_lerp_constant_per_tick_delta()
	_test_cosine_a_lerp_peaks_in_the_middle()
	_test_snap_path_leaves_lerp_inactive()
	_test_mid_lerp_mode_swap_takes_effect()

	print("\n=== ScenarioCameraEaseTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioCameraEaseTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraEaseTest")
		get_tree().quit(0)


func _assert_almost_equal(got: float, want: float, name: String, eps: float = 0.0001) -> void:
	if absf(got - want) < eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f (eps=%f)" % [name, got, want, eps])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# --- _curve invariants -------------------------------------------------------

func _test_curve_endpoints_all_modes() -> void:
	var vm := _make_vm()
	for mode in [ScenarioCameraDirector.EaseMode.LINEAR,
			ScenarioCameraDirector.EaseMode.COSINE_A,
			ScenarioCameraDirector.EaseMode.COSINE_B]:
		vm.camera_director.camera_ease_mode = mode
		_assert_almost_equal(vm.camera_director._curve(0.0), 0.0,
			"mode=%d _curve(0)==0" % mode)
		_assert_almost_equal(vm.camera_director._curve(1.0), 1.0,
			"mode=%d _curve(1)==1" % mode)
	vm.queue_free()


func _test_curve_monotonic_all_modes() -> void:
	var vm := _make_vm()
	for mode in [ScenarioCameraDirector.EaseMode.LINEAR,
			ScenarioCameraDirector.EaseMode.COSINE_A,
			ScenarioCameraDirector.EaseMode.COSINE_B]:
		vm.camera_director.camera_ease_mode = mode
		var prev := -1.0
		var ok := true
		for i in range(0, 21):
			var done := float(i) / 20.0
			var c := vm.camera_director._curve(done)
			if c < prev - 0.0001:
				ok = false
				print("  monotonic fail mode=%d at done=%f c=%f prev=%f" %
					[mode, done, c, prev])
				break
			prev = c
		_assert_true(ok, "mode=%d _curve monotonic non-decreasing" % mode)
	vm.queue_free()


# --- Per-mode shape ----------------------------------------------------------

func _test_linear_is_identity() -> void:
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.LINEAR
	for done in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		_assert_almost_equal(vm.camera_director._curve(done), done,
			"LINEAR _curve(%f)==%f" % [done, done])
	vm.queue_free()


func _test_cosine_a_symmetric_at_quarter_points() -> void:
	# Symmetric cosine ease: _curve(0.25) + _curve(0.75) == 1.0.
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_A
	var c25 := vm.camera_director._curve(0.25)
	var c75 := vm.camera_director._curve(0.75)
	_assert_almost_equal(c25 + c75, 1.0,
		"COSINE_A _curve(0.25)+_curve(0.75)==1")
	# Closed-form: 0.5 - 0.5*cos(pi*0.25) = (1 - cos(pi/4))/2
	_assert_almost_equal(c25, (1.0 - cos(PI * 0.25)) / 2.0,
		"COSINE_A _curve(0.25) closed-form")
	vm.queue_free()


func _test_cosine_a_midpoint_half() -> void:
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_A
	# 0.5 - 0.5*cos(pi*0.5) = 0.5 - 0 = 0.5
	_assert_almost_equal(vm.camera_director._curve(0.5), 0.5, "COSINE_A _curve(0.5)==0.5")
	vm.queue_free()


func _test_cosine_b_midpoint_value() -> void:
	# COSINE_B: 1 - cos(0.5*pi*done). At done=0.5 -> 1 - cos(pi/4) ≈ 0.2929.
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_B
	_assert_almost_equal(vm.camera_director._curve(0.5), 1.0 - cos(0.25 * PI),
		"COSINE_B _curve(0.5)==1-cos(pi/4)")
	_assert_almost_equal(vm.camera_director._curve(1.0), 1.0,
		"COSINE_B _curve(1.0)==1.0")
	vm.queue_free()


func _test_cosine_b_asymmetric_at_quarter_points() -> void:
	# COSINE_B fast ramp-in: _curve(0.25) + _curve(0.75) != 1.0.
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_B
	var sum := vm.camera_director._curve(0.25) + vm.camera_director._curve(0.75)
	_assert_true(absf(sum - 1.0) > 0.05,
		"COSINE_B asymmetric: |_curve(0.25)+_curve(0.75) - 1| > 0.05 (got sum=%f)" % sum)
	vm.queue_free()


# --- _advance_camera_lerp envelope ------------------------------------------

func _drive_lerp_and_collect_positions(vm: ScenarioVMClass, cam: StubCamera,
		steps: int) -> Array[Vector3]:
	# Advance time by 1/60s per step, calling _advance_camera_lerp after each
	# bump. Clamps elapsed at duration so the final sample lands at done=1.0.
	var step_s := 1.0 / 60.0
	var out: Array[Vector3] = []
	for i in range(steps):
		vm.camera_director._cam_lerp_elapsed_s = clampf(vm.camera_director._cam_lerp_elapsed_s + step_s,
			0.0, vm.camera_director._cam_lerp_duration_s)
		vm.camera_director._advance_camera_lerp()
		out.append(cam.captured_positions[cam.captured_positions.size() - 1])
	return out


func _test_linear_lerp_constant_per_tick_delta() -> void:
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.LINEAR
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	# Hand-set lerp state — bypasses _apply_camera_pose's player_camera reads
	# so this test exercises ONLY the curve+interp logic.
	vm.camera_director._cam_start_pos = Vector3(0.0, 0.0, 0.0)
	vm.camera_director._cam_target_pos = Vector3(60.0, 0.0, 0.0)  # 1.0 unit per 1/60s tick
	vm.camera_director._cam_start_rot = Vector3.ZERO
	vm.camera_director._cam_target_rot = Vector3.ZERO
	vm.camera_director._cam_start_ortho = 8.0
	vm.camera_director._cam_target_ortho = 8.0
	vm.camera_director._cam_lerp_duration_s = 1.0  # 60 ticks @ 60 Hz
	vm.camera_director._cam_lerp_elapsed_s = 0.0
	vm.camera_director._cam_lerp_active = true

	var positions := _drive_lerp_and_collect_positions(vm, cam, 60)
	# Per-tick delta should be a constant 1.0 on X.
	var ok := true
	for i in range(1, positions.size()):
		var dx := positions[i].x - positions[i - 1].x
		if absf(dx - 1.0) > 0.001:
			ok = false
			print("  LINEAR Δx fail at tick %d: dx=%f" % [i, dx])
			break
	_assert_true(ok, "LINEAR lerp: constant per-tick Δx == 1.0")
	# End must land on target.
	_assert_almost_equal(positions[positions.size() - 1].x, 60.0,
		"LINEAR lerp: final position == target")
	cam.queue_free()
	vm.queue_free()


func _test_cosine_a_lerp_peaks_in_the_middle() -> void:
	var vm := _make_vm()
	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_A
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	vm.camera_director._cam_start_pos = Vector3(0.0, 0.0, 0.0)
	vm.camera_director._cam_target_pos = Vector3(60.0, 0.0, 0.0)
	vm.camera_director._cam_start_rot = Vector3.ZERO
	vm.camera_director._cam_target_rot = Vector3.ZERO
	vm.camera_director._cam_start_ortho = 8.0
	vm.camera_director._cam_target_ortho = 8.0
	vm.camera_director._cam_lerp_duration_s = 1.0
	vm.camera_director._cam_lerp_elapsed_s = 0.0
	vm.camera_director._cam_lerp_active = true

	var positions := _drive_lerp_and_collect_positions(vm, cam, 60)
	# Per-tick deltas should be smallest near the endpoints and largest near
	# the middle for the symmetric cosine. Compare a near-endpoint tick (#3)
	# against a mid tick (#30) — mid must be substantially larger.
	var early := positions[2].x - positions[1].x  # tick 2 -> 3, near start
	var mid := positions[30].x - positions[29].x   # tick 29 -> 30, near middle
	var late := positions[58].x - positions[57].x  # tick 57 -> 58, near end
	_assert_true(mid > early * 1.5,
		"COSINE_A: mid-segment Δx (%.3f) > 1.5x early-segment Δx (%.3f)" % [mid, early])
	_assert_true(mid > late * 1.5,
		"COSINE_A: mid-segment Δx (%.3f) > 1.5x late-segment Δx (%.3f)" % [mid, late])
	# Closed-form sanity at the midpoint: ct(0.5)=0.5 → position 30.0 at tick 30.
	_assert_almost_equal(positions[29].x, 30.0,
		"COSINE_A: position at done=0.5 == 30.0", 0.01)
	cam.queue_free()
	vm.queue_free()


func _test_snap_path_leaves_lerp_inactive() -> void:
	# Drive the snap branch of _apply_camera_pose (time_ticks=1) and assert
	# _cam_lerp_active flips false. Uses a real-ish stub camera so the
	# apply_takeover call lands cleanly.
	var vm := _make_vm()
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	# Pre-arm to true so the snap path's `_cam_lerp_active = false` is observable.
	vm.camera_director._cam_lerp_active = true
	vm.camera_director._apply_camera_pose(0, 0, 0, 0, 0, 0, 4096, 1)
	_assert_true(not vm.camera_director._cam_lerp_active,
		"snap path (time_ticks=1): _cam_lerp_active flips false")
	_assert_true(cam.captured_positions.size() == 1,
		"snap path: apply_takeover called exactly once")
	cam.queue_free()
	vm.queue_free()


func _test_mid_lerp_mode_swap_takes_effect() -> void:
	# At done=0.5, LINEAR returns 0.5 and COSINE_A also returns 0.5 — same
	# midpoint. Sample at done=0.25 where they diverge: LINEAR→0.25 (position
	# 15.0 of 60.0), COSINE_A→0.1464 (position ~8.79). Set the mode mid-lerp
	# and assert _advance_camera_lerp picks up the new curve immediately.
	var vm := _make_vm()
	var cam := StubCamera.new()
	add_child(cam)
	vm.player_camera = cam
	vm.camera_director._cam_start_pos = Vector3(0.0, 0.0, 0.0)
	vm.camera_director._cam_target_pos = Vector3(60.0, 0.0, 0.0)
	vm.camera_director._cam_start_rot = Vector3.ZERO
	vm.camera_director._cam_target_rot = Vector3.ZERO
	vm.camera_director._cam_start_ortho = 8.0
	vm.camera_director._cam_target_ortho = 8.0
	vm.camera_director._cam_lerp_duration_s = 1.0
	vm.camera_director._cam_lerp_elapsed_s = 0.25  # done = 0.25
	vm.camera_director._cam_lerp_active = true

	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.LINEAR
	vm.camera_director._advance_camera_lerp()
	var p_linear: Vector3 = cam.captured_positions[cam.captured_positions.size() - 1]

	vm.camera_director.camera_ease_mode = ScenarioCameraDirector.EaseMode.COSINE_A
	vm.camera_director._advance_camera_lerp()
	var p_cosine: Vector3 = cam.captured_positions[cam.captured_positions.size() - 1]

	# done=0.25 expected positions: LINEAR=15.0, COSINE_A=60*(1-cos(pi/4))/2 ≈ 8.787
	_assert_almost_equal(p_linear.x, 15.0,
		"mid-lerp LINEAR at done=0.25 → x=15.0", 0.01)
	_assert_almost_equal(p_cosine.x, 60.0 * (1.0 - cos(PI * 0.25)) / 2.0,
		"mid-lerp COSINE_A at done=0.25 → x≈8.79", 0.01)
	_assert_true(absf(p_linear.x - p_cosine.x) > 1.0,
		"mid-lerp mode swap actually changes _advance output (no curve caching)")
	cam.queue_free()
	vm.queue_free()
