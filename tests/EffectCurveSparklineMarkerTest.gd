extends Node
## TDD guard for the emitter-elapsed playhead marker on the inspector curve sparkline
## (ADR-0089 amendment). A bare vertical line at the curve index the sim reads
## (`elapsed % 160`), mapped into the SAME windowed/trimmed X the sparkline plots — so
## the marker lines up with the sample it points at. Read-only; per-line text is noise on
## a stack of sparklines (the painter carries the labels), so this is line geometry only.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCurveSparklineMarkerTest.tscn

const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_no_marker_by_default()
	_test_set_marker_records_index()
	_test_clear_marker()
	_test_marker_x_maps_index_into_drawn_window()
	_test_marker_x_clamps_to_drawn_range()

	print("\n=== EffectCurveSparklineMarkerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCurveSparklineMarkerTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCurveSparklineMarkerTest")
		get_tree().quit(0)


## A fresh sparkline draws no marker — the marker is opt-in (only emitter-clocked curves).
func _test_no_marker_by_default() -> void:
	var s = Sparkline.new()
	_assert_true(not s.has_marker(), "no marker until one is set")


## set_marker records the curve index the line sits at (and that it's present).
func _test_set_marker_records_index() -> void:
	var s = Sparkline.new()
	s.set_marker({"present": true, "index": 42, "lap": 0, "state": "in"})
	_assert_true(s.has_marker(), "a set marker is present")
	_assert_eq(s.marker_index(), 42, "the marker sits at the sampled index")


## An absent marker (browsed emitter, no span) clears the line.
func _test_clear_marker() -> void:
	var s = Sparkline.new()
	s.set_marker({"present": true, "index": 10, "lap": 0, "state": "in"})
	s.set_marker({"present": false})
	_assert_true(not s.has_marker(), "an absent marker draws nothing")


## The pure index → X map mirrors the polyline plot (x = width · i/(n−1)): sample i of n
## drawn samples sits at that fraction of the width, so the line points at its sample.
func _test_marker_x_maps_index_into_drawn_window() -> void:
	# 11 drawn samples, 100px wide: sample 5 sits at 100·5/10 = 50 (the plot's own mapping).
	_assert_true(absf(Sparkline.marker_x(5, 11, 100.0) - 50.0) < 0.001,
		"index 5 of 11 drawn samples maps to mid-width")
	_assert_true(absf(Sparkline.marker_x(0, 11, 100.0) - 0.0) < 0.001,
		"index 0 maps to the left edge")
	_assert_true(absf(Sparkline.marker_x(10, 11, 100.0) - 100.0) < 0.001,
		"the last drawn sample maps to the right edge")


## An index past the drawn window (the after-firing clamp lands one past a trimmed window)
## clamps to the last drawn sample — the nearest curve edge, never off-canvas.
func _test_marker_x_clamps_to_drawn_range() -> void:
	_assert_true(absf(Sparkline.marker_x(20, 11, 100.0) - 100.0) < 0.001,
		"an index beyond the drawn samples clamps to the right edge")


# --- helpers --------------------------------------------------------------

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
