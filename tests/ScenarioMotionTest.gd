extends Node
## Unit tests for ScenarioMotion — the pure, scene-free cutscene-motion value
## object (ADR-0055). A positional lerp from start to target shaped by the
## event-script easing curve, holding no node ref. Pure logic, so this needs no
## scene, no VM, no nodes — the point of extracting it.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioMotionTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_position_endpoints()
	_test_kinematics()
	_test_snap_to_end()
	_test_curve_easing()

	print("\n=== ScenarioMotionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioMotionTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioMotionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioMotionTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _approx(got: float, want: float, name: String) -> void:
	if is_equal_approx(got, want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _veq(got: Vector3, want: Vector3, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _make(start: Vector3, target: Vector3, dur_s: float, easing: int, weight: int) -> ScenarioMotion:
	var m := ScenarioMotion.new()
	m.start = start
	m.target = target
	m.dur_s = dur_s
	m.elapsed_s = 0.0
	m.easing = easing
	m.weight = weight
	return m


func _test_position_endpoints() -> void:
	# f=0 -> start (no motion has elapsed yet).
	var m := _make(Vector3(1, 2, 3), Vector3(4, 6, 8), 2.0, 0, 1)
	_veq(m.position(), Vector3(1, 2, 3), "position at f=0 -> start")
	# f=1 -> target (fully elapsed).
	m.elapsed_s = 2.0
	_veq(m.position(), Vector3(4, 6, 8), "position at f=1 -> target")
	# linear midpoint (easing 0): f=0.5 -> geometric midpoint.
	m.elapsed_s = 1.0
	_veq(m.position(), Vector3(2.5, 4.0, 5.5), "linear midpoint at f=0.5")


func _test_kinematics() -> void:
	var m := _make(Vector3.ZERO, Vector3(10, 0, 0), 2.0, 0, 1)
	# advance accumulates elapsed time.
	m.advance(0.5)
	_approx(m.frac(), 0.25, "advance accumulates -> frac 0.25")
	m.advance(0.5)
	_approx(m.frac(), 0.5, "advance again -> frac 0.5")
	_eq(m.is_done(), false, "not done mid-motion")
	# is_done flips exactly at elapsed == dur.
	m.advance(1.0)
	_eq(m.is_done(), true, "done at elapsed == dur")
	# frac clamps at 1.0 past the end — no overshoot.
	m.advance(5.0)
	_approx(m.frac(), 1.0, "frac clamps at 1.0 past the end")
	_veq(m.position(), Vector3(10, 0, 0), "position clamps to target past the end")


func _test_snap_to_end() -> void:
	var m := _make(Vector3.ZERO, Vector3(3, 3, 3), 4.0, 0, 1)
	m.advance(1.0)
	m.snap_to_end()
	_eq(m.is_done(), true, "snap_to_end -> is_done")
	_veq(m.position(), Vector3(3, 3, 3), "snap_to_end -> position == target")


func _test_curve_easing() -> void:
	# Every easing must pin the endpoints (f=0 -> 0, f=1 -> 1) so a motion lands
	# exactly on target regardless of the shaping curve — cw + w == 16 always.
	for e in [0, 1, 2, 3]:
		for w in [0, 1, 8, 16]:
			_approx(ScenarioMotion.curve(e, 0.0, w), 0.0, "curve(%d,0,%d) -> 0" % [e, w])
			_approx(ScenarioMotion.curve(e, 1.0, w), 1.0, "curve(%d,1,%d) -> 1" % [e, w])

	# Type 0 — linear: f, weight-independent.
	_approx(ScenarioMotion.curve(0, 0.3, 5), 0.3, "type0 linear f=0.3")
	_approx(ScenarioMotion.curve(0, 0.7, 16), 0.7, "type0 linear ignores weight")

	# Type 3 — weighted ease-in: (w·f² + cw·f)/16. weight=16 -> f², weight=0 -> f.
	_approx(ScenarioMotion.curve(3, 0.5, 16), 0.25, "type3 weight=16 -> f² at 0.5")
	_approx(ScenarioMotion.curve(3, 0.7, 16), 0.49, "type3 weight=16 -> f² at 0.7")
	_approx(ScenarioMotion.curve(3, 0.6, 0), 0.6, "type3 weight=0 -> f")

	# Type 1 — linear + symmetric bump w·f·(1-f)/16.
	_approx(ScenarioMotion.curve(1, 0.5, 8), 0.625, "type1 bump peak-ish at 0.5")
	var bump_lo := ScenarioMotion.curve(1, 0.25, 8) - 0.25
	var bump_hi := ScenarioMotion.curve(1, 0.75, 8) - 0.75
	_approx(bump_lo, bump_hi, "type1 bump symmetric about 0.5")

	# Type 2 — ease-in-out, symmetric about 0.5. Hits 0.5 at f=0.5 for any weight;
	# weight=16 is quadratic (0.125 / 0.875 mirror at f=0.25 / 0.75).
	_approx(ScenarioMotion.curve(2, 0.5, 16), 0.5, "type2 hits 0.5 at f=0.5 (w=16)")
	_approx(ScenarioMotion.curve(2, 0.5, 3), 0.5, "type2 hits 0.5 at f=0.5 (w=3)")
	_approx(ScenarioMotion.curve(2, 0.25, 16), 0.125, "type2 w=16 quadratic first half")
	_approx(ScenarioMotion.curve(2, 0.75, 16), 0.875, "type2 w=16 quadratic second half")
