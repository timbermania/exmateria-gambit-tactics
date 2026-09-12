extends Node
## TDD guard for the emitter-elapsed playhead marker on the Effect Studio curve PAINTER
## (ADR-0089 amendment) — the primary authoring surface. Beyond the bare line the sparkline
## draws, the painter carries the teaching labels: a two-ended `elapsed N · fF` tag (naming
## BOTH the emitter-elapsed coordinate and the absolute effect frame — the bridge IS the
## feature), a `×N` lap tag when a long firing wraps past 160, and a before/after tell when
## the playhead sits outside the firing. A browsed emitter with no governing span shows a
## one-line hint, not a lying marker. Read-only: the paint canvas stays paint-only.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCurvePainterMarkerTest.tscn

const Painter = preload("res://src/effects/studio/EffectCurvePainter.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_no_marker_by_default()
	_test_set_marker_records_index()
	_test_absent_marker_clears_line_but_may_hint()
	_test_marker_x_maps_index_into_grid()
	_test_marker_x_clamps_to_curve_range()
	_test_tag_names_both_coordinates()
	_test_tag_adds_lap_when_wrapped()
	_test_tag_tells_before_and_after()

	print("\n=== EffectCurvePainterMarkerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCurvePainterMarkerTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCurvePainterMarkerTest")
		get_tree().quit(0)


func _test_no_marker_by_default() -> void:
	var p = Painter.new()
	_assert_true(not p.has_marker(), "no marker until one is set")


func _test_set_marker_records_index() -> void:
	var p = Painter.new()
	p.set_marker({"present": true, "index": 33, "lap": 0, "elapsed": 33, "frame": 33, "state": "in"})
	_assert_true(p.has_marker(), "a present marker draws a line")
	_assert_eq(p.marker_index(), 33, "the line sits at the sampled index")


## An absent marker draws no line; a carried hint (browsed emitter) is still shown.
func _test_absent_marker_clears_line_but_may_hint() -> void:
	var p = Painter.new()
	p.set_marker({"present": false, "hint": "select this emitter's span"})
	_assert_true(not p.has_marker(), "no marker line without a span")
	_assert_eq(Painter.marker_tag({"present": false, "hint": "select this emitter's span"}),
		"select this emitter's span", "the hint is shown in place of a tag")


## The pure index → X map mirrors _draw_curve (x = r.x + (i+0.5)/count · r.w): sample i of
## `count` sits at its band centre, so the line points at the frame it samples.
func _test_marker_x_maps_index_into_grid() -> void:
	var r := Rect2(0.0, 0.0, 160.0, 100.0)   # 160 frames across 160px → x = i + 0.5
	_assert_true(absf(Painter.marker_x(0, 160, r) - 0.5) < 0.001, "frame 0 at its band centre")
	_assert_true(absf(Painter.marker_x(50, 160, r) - 50.5) < 0.001, "frame 50 at its band centre")


## An index past the curve length clamps to the last frame (never off the grid).
func _test_marker_x_clamps_to_curve_range() -> void:
	var r := Rect2(0.0, 0.0, 160.0, 100.0)
	_assert_true(absf(Painter.marker_x(500, 160, r) - 159.5) < 0.001,
		"an over-range index clamps to the last frame's band")


## The two-ended tag names the emitter-elapsed coordinate AND the absolute effect frame.
func _test_tag_names_both_coordinates() -> void:
	_assert_eq(Painter.marker_tag({"present": true, "elapsed": 50, "frame": 90, "lap": 0, "state": "in"}),
		"elapsed 50 · f90", "tag bridges elapsed and absolute frame")


## A firing longer than 160 frames adds a lap tag so a marker jumping back to x=0 reads as
## a wrap, not a glitch — ×2 on the second pass (lap 1).
func _test_tag_adds_lap_when_wrapped() -> void:
	_assert_eq(Painter.marker_tag({"present": true, "elapsed": 250, "frame": 300, "lap": 1, "state": "in"}),
		"elapsed 250 · f300  ×2", "the second lap is tagged ×2")


## Out of the firing the tag carries the before/after tell (a silently-vanishing marker
## reads as a bug — the emitter isn't sampling there).
func _test_tag_tells_before_and_after() -> void:
	_assert_eq(Painter.marker_tag({"present": true, "elapsed": 0, "frame": 30, "lap": 0, "state": "before"}),
		"elapsed 0 · f30  (before firing)", "before-firing tell")
	_assert_eq(Painter.marker_tag({"present": true, "elapsed": 150, "frame": 260, "lap": 0, "state": "after"}),
		"elapsed 150 · f260  (after firing)", "after-firing tell")


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
