extends Node
## TDD guard for CurvePlayheadMarker — the PURE emitter-elapsed playhead → curve-index
## mapper (ADR-0089 amendment: "span-anchored playhead marker on emitter-elapsed curves").
## An emitter-elapsed curve is read at `EffectCurve.sample_by_frame(elapsed)` where
## `elapsed = playhead − span.start`, so the marker's index MUST equal `elapsed % 160` —
## exactly the sim's read site. Out of the firing the marker clamps to the nearest curve
## edge and reports before/after; a long firing (> 160 frames) wraps and counts laps.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CurvePlayheadMarkerTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const Marker = preload("res://src/effects/studio/CurvePlayheadMarker.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_in_firing_index_is_elapsed()
	_test_marker_matches_sample_by_frame()
	_test_before_firing_clamps_to_left_edge()
	_test_after_firing_clamps_to_right_edge()
	_test_wrap_past_160_wraps_index_and_counts_laps()
	_test_start_and_end_frames_are_in_firing()
	_test_absent_has_no_marker()

	print("\n=== CurvePlayheadMarkerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CurvePlayheadMarkerTest")
		get_tree().quit(1)
	else:
		print("[PASS] CurvePlayheadMarkerTest")
		get_tree().quit(0)


## Inside the firing the curve index is the elapsed frame count (playhead − start).
func _test_in_firing_index_is_elapsed() -> void:
	var m := Marker.resolve(70, 50, 200)   # firing 50..200, playhead 70 → elapsed 20
	_assert_true(m["present"], "a span target resolves a marker")
	_assert_eq(m["elapsed"], 20, "elapsed = playhead − start")
	_assert_eq(m["index"], 20, "index = elapsed (no wrap under 160)")
	_assert_eq(m["lap"], 0, "no lap on the first pass")
	_assert_eq(m["state"], "in", "inside the firing")


## The non-negotiable invariant: the marker index equals what the sim samples.
## Independent oracle = an actual EffectCurve.sample_by_frame call at the same elapsed.
func _test_marker_matches_sample_by_frame() -> void:
	var samples: Array = []
	for i in range(160):
		samples.append(float(i) / 160.0)   # a curve where sample value == index/160
	var curve = EffectCurve.from_array(samples, 0)
	var m := Marker.resolve(90, 40, 300)   # elapsed 50
	var sampled: float = curve.sample_by_frame(m["elapsed"])
	_assert_true(absf(sampled - float(m["index"]) / 160.0) < 0.0001,
		"marker index lands where sample_by_frame reads (elapsed 50 → sample 50)")


## Before the firing (playhead < start): clamp to the left curve edge, tell "before".
func _test_before_firing_clamps_to_left_edge() -> void:
	var m := Marker.resolve(30, 50, 200)   # playhead before start
	_assert_eq(m["index"], 0, "clamped to the first sample")
	_assert_eq(m["elapsed"], 0, "elapsed clamped to 0")
	_assert_eq(m["state"], "before", "before the firing")
	_assert_eq(m["raw_elapsed"], -20, "raw (unclamped) elapsed is negative")


## After the firing (playhead > end): clamp to the right curve edge (duration), tell "after".
func _test_after_firing_clamps_to_right_edge() -> void:
	var m := Marker.resolve(260, 50, 200)   # duration 150, playhead past end
	_assert_eq(m["elapsed"], 150, "elapsed clamped to the firing duration")
	_assert_eq(m["index"], 150, "index at the last curve sample it reaches")
	_assert_eq(m["state"], "after", "after the firing")


## A firing longer than 160 frames wraps the index (elapsed % 160) and counts laps.
func _test_wrap_past_160_wraps_index_and_counts_laps() -> void:
	var m := Marker.resolve(250, 0, 400)   # elapsed 250 → 250 % 160 = 90, lap 1
	_assert_eq(m["elapsed"], 250, "elapsed within a long firing")
	_assert_eq(m["index"], 90, "index wraps at 160 (250 − 160)")
	_assert_eq(m["lap"], 1, "on the second lap")
	_assert_eq(m["state"], "in", "still inside the long firing")


## The firing's own start and end frames both count as inside (inclusive boundaries).
func _test_start_and_end_frames_are_in_firing() -> void:
	var at_start := Marker.resolve(50, 50, 200)
	_assert_eq(at_start["state"], "in", "playhead on start is in-firing")
	_assert_eq(at_start["index"], 0, "…at the first sample")
	var at_end := Marker.resolve(200, 50, 200)
	_assert_eq(at_end["state"], "in", "playhead on end is in-firing")
	_assert_eq(at_end["elapsed"], 150, "…at the last elapsed frame")


## No governing span (a browsed/drilled emitter) → an explicitly absent marker.
func _test_absent_has_no_marker() -> void:
	var m := Marker.absent()
	_assert_true(not m["present"], "absent marker is not present")


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
