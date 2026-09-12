extends Node
## TDD guard for TimelineAxis — the frame↔pixel transform the Effect Studio
## timeline draws and hit-tests through (ported math from the DAW piano-roll,
## fft-plugin FFTPianoDetailView.cpp:301-309). Pure, no scene: a testable deep
## module the view leans on for every coordinate. See CONTEXT.md "Effect Studio".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/TimelineAxisTest.tscn

const TimelineAxis = preload("res://src/effects/studio/TimelineAxis.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_frame_to_x_roundtrip()
	_test_x_to_frame_clamps_at_zero()
	_test_zoom_keeps_cursor_frame_stationary()
	_test_zoom_clamps_scale()
	_test_snap_rounds_to_nearest_step()

	print("\n=== TimelineAxisTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TimelineAxisTest")
		get_tree().quit(1)
	else:
		print("[PASS] TimelineAxisTest")
		get_tree().quit(0)


## frame_to_x and x_to_frame are inverses: a frame projected to a pixel and back
## returns the same frame (the invariant every hit-test relies on).
func _test_frame_to_x_roundtrip() -> void:
	var axis = TimelineAxis.new()
	axis.configure(80.0, 2.0)   # base_x (header+pad) = 80, pixels_per_frame = 2
	axis.scroll_x = 30.0
	var x := axis.frame_to_x(50.0)
	_assert_close(axis.x_to_frame(x), 50.0, "frame→x→frame is identity")
	# frame 0 sits at base_x - scroll
	_assert_close(axis.frame_to_x(0.0), 50.0, "frame 0 is at base_x - scroll_x")


## Frames are non-negative; a pixel left of frame 0 clamps to 0 rather than
## returning a negative frame (matches the JUCE inverse clamp).
func _test_x_to_frame_clamps_at_zero() -> void:
	var axis = TimelineAxis.new()
	axis.configure(80.0, 2.0)
	_assert_eq(axis.x_to_frame(0.0), 0.0, "a pixel before the axis origin clamps to frame 0")


## Cursor-anchored zoom: the frame under the cursor stays under the cursor after
## a zoom (the pro-feel gesture — you zoom into what you point at).
func _test_zoom_keeps_cursor_frame_stationary() -> void:
	var axis = TimelineAxis.new()
	axis.configure(80.0, 2.0)
	axis.scroll_x = 30.0
	var cursor_x := 300.0
	var frame_under := axis.x_to_frame(cursor_x)
	axis.zoom_at(1.5, cursor_x)
	_assert_close(axis.x_to_frame(cursor_x), frame_under,
		"the frame under the cursor is unmoved by zoom")
	_assert_close(axis.pixels_per_frame, 3.0, "scale multiplied by the zoom factor")


## Zoom is clamped to the [min,max] pixels-per-frame band so the view can't
## collapse to nothing or explode past usability.
func _test_zoom_clamps_scale() -> void:
	var axis = TimelineAxis.new()
	axis.configure(80.0, 2.0)
	axis.zoom_at(1000.0, 200.0)
	_assert_true(axis.pixels_per_frame <= TimelineAxis.MAX_PPF + 0.001, "zoom-in clamps at MAX_PPF")
	axis.zoom_at(0.00001, 200.0)
	_assert_true(axis.pixels_per_frame >= TimelineAxis.MIN_PPF - 0.001, "zoom-out clamps at MIN_PPF")


## Snap rounds a frame to the nearest multiple of the step; step 0/1 is a no-op
## (frame-exact). This is the grid the DAW's snap-mode index selects.
func _test_snap_rounds_to_nearest_step() -> void:
	_assert_eq(TimelineAxis.snap(23.0, 5), 25, "23 snaps to the nearest 5 → 25")
	_assert_eq(TimelineAxis.snap(22.0, 5), 20, "22 snaps down to 20")
	_assert_eq(TimelineAxis.snap(23.4, 1), 23, "step 1 is frame-exact rounding")
	_assert_eq(TimelineAxis.snap(23.4, 0), 23, "step 0 is a no-op (frame-exact)")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) < 0.001:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %f, got %f" % [label, expected, actual])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
