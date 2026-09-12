extends Node
## TDD guard for the loop-region VIEW (ADR-0090): the frames-bar shading + edge-handle
## adjust, and the timeline's full-height band across the lanes. Both read the shared
## TimelineAxis, so the region draws pixel-aligned with the playhead and lanes.
## Asserts:
##   - the timeline's band rect spans [start,end]×full-height, aligned to the axis,
##   - grabbing a frames-bar edge handle (plain-drag) ADJUSTS that edge (region_changed),
##     and does NOT scrub,
##   - a plain press well inside the region (not on an edge) still SCRUBS.
## Axis at snap_step=1 (identity) so asserted frames are literal.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectLoopRegionViewTest.tscn

const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0

var _regions: Array = []
var _seeks: Array = []


func _ready() -> void:
	_test_timeline_band_rect_aligns_to_axis()
	_test_timeline_no_region_no_band()
	_test_frames_bar_edge_handle_adjusts_start()
	_test_frames_bar_edge_handle_adjusts_end()
	_test_frames_bar_interior_press_still_scrubs()

	print("\n=== EffectLoopRegionViewTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectLoopRegionViewTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectLoopRegionViewTest")
		get_tree().quit(0)


func _test_timeline_band_rect_aligns_to_axis() -> void:
	var tl = _timeline()
	tl.set_loop_region({"start": 10, "end": 20})
	var r: Rect2 = tl.loop_region_rect()
	_assert_true(is_equal_approx(r.position.x, tl.axis.frame_to_x(10.0)), "band left = frame 10 x")
	_assert_true(is_equal_approx(r.end.x, tl.axis.frame_to_x(20.0)), "band right = frame 20 x")
	_assert_true(r.position.y <= 0.0 and r.size.y >= tl.size.y, "band spans full lane height")


func _test_timeline_no_region_no_band() -> void:
	var tl = _timeline()
	tl.set_loop_region({})
	_assert_true(tl.loop_region_rect().size == Vector2.ZERO, "no region → empty band rect")


func _test_frames_bar_edge_handle_adjusts_start() -> void:
	var bar = _bar({"start": 10, "end": 20})
	_press(bar, 10, false)      # plain press ON the start edge
	_motion(bar, 13, false)
	_release(bar)
	_assert_true(_seeks.is_empty(), "grabbing an edge does not scrub")
	_assert_true(not _regions.is_empty(), "edge drag emits region")
	_assert_eq(_regions[-1], [13, 20], "start edge moved to 13, end kept")


func _test_frames_bar_edge_handle_adjusts_end() -> void:
	var bar = _bar({"start": 10, "end": 20})
	_press(bar, 20, false)      # plain press ON the end edge
	_motion(bar, 17, false)
	_release(bar)
	_assert_eq(_regions[-1], [10, 17], "end edge moved to 17, start kept")


func _test_frames_bar_interior_press_still_scrubs() -> void:
	var bar = _bar({"start": 10, "end": 20})
	_press(bar, 15, false)      # interior, away from both edges
	_assert_true(_regions.is_empty(), "interior press does not adjust the region")
	_assert_true(not _seeks.is_empty(), "interior press scrubs")
	_assert_eq(_seeks[-1], 15, "interior press seeks the pressed frame")


# --- harness -------------------------------------------------------------

func _timeline():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


func _bar(region: Dictionary):
	_regions = []
	_seeks = []
	var tl = _timeline()
	var bar = FramesBar.new()
	bar.size = Vector2(900.0, FramesBar.BAR_H)
	bar.bind_timeline(tl)
	bar.set_loop_region(region)
	bar.region_changed.connect(func(s, e): _regions.append([s, e]))
	bar.seek_requested.connect(func(f): _seeks.append(f))
	return bar


func _x_of(bar, frame: int) -> float:
	return bar._tl.axis.frame_to_x(float(frame))


func _press(bar, frame: int, alt: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.alt_pressed = alt
	ev.position = Vector2(_x_of(bar, frame), FramesBar.BAR_H * 0.5)
	bar._gui_input(ev)


func _motion(bar, frame: int, alt: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.alt_pressed = alt
	ev.position = Vector2(_x_of(bar, frame), FramesBar.BAR_H * 0.5)
	bar._gui_input(ev)


func _release(bar) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(0.0, 0.0)
	bar._gui_input(ev)


func _assert_eq(got, want, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
