extends Node
## TDD guard for CurvePaintModel — the pure freehand-painting core the Effect
## Studio curve painter draws through. FFT curves are DENSE LUTs (no control
## points): 0-255 over 160 frames (lerp curves) or 1-9 over 600 frames (time-slow).
## The gesture is "drag across the grid; each frame-column takes the value under
## the cursor, snapped to the Y-range; interpolate skipped columns on a fast
## sweep." ONE model parameterized by Y-range handles both variants. See the
## Effect Studio curve-painter handoff.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CurvePaintModelTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const CurvePaintModel = preload("res://src/effects/studio/CurvePaintModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_single_column_paint()
	_test_fast_sweep_interpolates_skipped_columns()
	_test_reverse_sweep()
	_test_clamps_to_y_range()
	_test_pixel_to_cell_maps_x_and_inverted_y()
	_test_curve_roundtrip_grid()

	print("\n=== CurvePaintModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CurvePaintModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] CurvePaintModelTest")
		get_tree().quit(0)


## A stroke that starts and ends on the same column writes just that column.
func _test_single_column_paint() -> void:
	var v := _zeros(8)
	CurvePaintModel.stroke_segment(v, 3, 100, 3, 100, 0, 255)
	_assert_eq(v[3], 100, "the touched column takes the value")
	_assert_eq(v[2], 0, "neighbours are untouched")


## A fast drag skips columns between samples; the model fills every intermediate
## column by linear interpolation so the dense LUT has no holes.
func _test_fast_sweep_interpolates_skipped_columns() -> void:
	var v := _zeros(11)
	CurvePaintModel.stroke_segment(v, 0, 0, 10, 100, 0, 255)
	_assert_eq(v[0], 0, "start column")
	_assert_eq(v[5], 50, "midpoint is interpolated, not left at 0")
	_assert_eq(v[10], 100, "end column")


## Dragging right-to-left fills the same columns (order-independent).
func _test_reverse_sweep() -> void:
	var v := _zeros(11)
	CurvePaintModel.stroke_segment(v, 10, 100, 0, 0, 0, 255)
	_assert_eq(v[5], 50, "reverse sweep still interpolates the midpoint")
	_assert_eq(v[0], 0, "reverse sweep reaches the far column")


## Values are clamped to the parameterized Y-range — 0-255 for lerp curves,
## 1-9 for time-slow — so the painter can't write an out-of-domain sample.
func _test_clamps_to_y_range() -> void:
	var v := _zeros(4)
	CurvePaintModel.stroke_segment(v, 0, 999, 3, -5, 1, 9)
	for i in range(4):
		_assert_true(v[i] >= 1 and v[i] <= 9, "column %d clamped into [1,9]" % i)
	_assert_eq(v[0], 9, "over-max clamps to 9")
	_assert_eq(v[3], 1, "under-min clamps to 1")


## A pixel in the grid maps to a column (x) and a value (y, INVERTED — top of the
## grid is the max value), snapped into the Y-range.
func _test_pixel_to_cell_maps_x_and_inverted_y() -> void:
	var rect := Rect2(0, 0, 160, 100)   # 160 cols wide, 100 tall
	var top := CurvePaintModel.pixel_to_cell(Vector2(80, 0), rect, 160, 0, 255)
	_assert_eq(top["col"], 80, "x maps to the column under the cursor")
	_assert_eq(top["val"], 255, "the top of the grid is the max value")
	var bottom := CurvePaintModel.pixel_to_cell(Vector2(80, 100), rect, 160, 0, 255)
	_assert_eq(bottom["val"], 0, "the bottom of the grid is the min value")


## The grid ↔ normalized-curve bridge: reading an EffectCurve into an integer grid
## and writing it back round-trips the sample values (within integer rounding).
func _test_curve_roundtrip_grid() -> void:
	var curve = EffectCurve.from_array([0.0, 0.5019607843, 1.0], 0)  # ≈ 0,128,255 / 255
	var grid := CurvePaintModel.curve_to_grid(curve, 255)
	_assert_eq(grid, [0, 128, 255], "curve samples read into 0-255 grid values")
	grid[1] = 64
	CurvePaintModel.grid_to_curve(curve, grid, 255)
	_assert_true(absf(curve.samples[1] - 64.0 / 255.0) < 0.001, "edited grid written back normalized")


# --- helpers --------------------------------------------------------------

func _zeros(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0)
	return a


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
