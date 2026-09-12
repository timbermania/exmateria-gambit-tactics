extends Node
## TDD guard for LoopRegion — the pure frame-space math behind the Effect Studio's
## loop region (ADR-0090): turning an Alt+left-drag's two snapped frames into an
## ordered, min-length `[start, end]` span, and resolving the EFFECTIVE loop span
## (region when set, else whole score `0 .. stop_frame`). Golden values below are
## hand-picked (independent source of truth).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/LoopRegionTest.tscn

const LoopRegion = preload("res://src/effects/studio/LoopRegion.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_from_frames_orders_endpoints()
	_test_from_frames_already_ordered()
	_test_from_frames_enforces_min_length_two()
	_test_effective_uses_region_when_set()
	_test_effective_falls_back_to_whole_score()
	_test_is_empty()

	print("\n=== LoopRegionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] LoopRegionTest")
		get_tree().quit(1)
	else:
		print("[PASS] LoopRegionTest")
		get_tree().quit(0)


func _test_from_frames_orders_endpoints() -> void:
	# Dragged right-to-left (anchor 5, cursor 2) → the same [2,5] span.
	var r := LoopRegion.from_frames(5, 2)
	_assert_eq(r["start"], 2, "from_frames orders start")
	_assert_eq(r["end"], 5, "from_frames orders end")


func _test_from_frames_already_ordered() -> void:
	var r := LoopRegion.from_frames(2, 5)
	_assert_eq(r["start"], 2, "already-ordered start kept")
	_assert_eq(r["end"], 5, "already-ordered end kept")


func _test_from_frames_enforces_min_length_two() -> void:
	# A click-without-drag (both frames equal) is grown to the smallest legal
	# 2-frame span [f, f+1] rather than a zero-length region.
	var r := LoopRegion.from_frames(4, 4)
	_assert_eq(r["start"], 4, "min-length keeps start")
	_assert_eq(r["end"], 5, "min-length grows end to start+1")


func _test_effective_uses_region_when_set() -> void:
	var eff := LoopRegion.effective({"start": 2, "end": 5}, 90)
	_assert_eq(eff["start"], 2, "effective uses region start")
	_assert_eq(eff["end"], 5, "effective uses region end")


func _test_effective_falls_back_to_whole_score() -> void:
	# No region → whole score 0..stop_frame.
	var eff := LoopRegion.effective({}, 90)
	_assert_eq(eff["start"], 0, "no region → start 0")
	_assert_eq(eff["end"], 90, "no region → end = stop_frame")


func _test_is_empty() -> void:
	_assert_true(LoopRegion.is_empty({}), "empty dict is empty region")
	_assert_true(not LoopRegion.is_empty({"start": 2, "end": 5}), "set region is not empty")


func _assert_eq(got, want, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
