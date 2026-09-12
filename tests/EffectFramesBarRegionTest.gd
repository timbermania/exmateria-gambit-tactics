extends Node
## TDD guard for the EffectFramesBar's Alt+left-drag LOOP-REGION gesture (ADR-0090).
## Alt+left creates the region (emits region_changed); plain left still scrubs
## (seek_requested). The two gestures must never fight over one press. Frame values
## are read back through the shared axis at snap_step=1 (identity), so the asserted
## endpoints are literal, independent frames.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectFramesBarRegionTest.tscn

const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0

var _regions: Array = []
var _seeks: Array = []


func _ready() -> void:
	_test_alt_left_drag_creates_ordered_region()
	_test_plain_left_still_scrubs_not_region()
	_test_alt_left_click_makes_min_length_region()

	print("\n=== EffectFramesBarRegionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectFramesBarRegionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectFramesBarRegionTest")
		get_tree().quit(0)


func _test_alt_left_drag_creates_ordered_region() -> void:
	var bar = _bar()
	# Drag right-to-left: press at frame 10, move to frame 3, release.
	_press(bar, 10, true)
	_motion(bar, 3, true)
	_release(bar)
	_assert_true(_seeks.is_empty(), "alt-drag does NOT scrub")
	_assert_true(not _regions.is_empty(), "alt-drag emits a region")
	var last = _regions[-1]
	_assert_eq(last[0], 3, "region start = leftmost dragged frame")
	_assert_eq(last[1], 10, "region end = rightmost dragged frame")


func _test_plain_left_still_scrubs_not_region() -> void:
	var bar = _bar()
	_press(bar, 7, false)
	_assert_true(_regions.is_empty(), "plain-left press makes no region")
	_assert_true(not _seeks.is_empty(), "plain-left press scrubs")
	_assert_eq(_seeks[-1], 7, "plain-left seeks the pressed frame")


func _test_alt_left_click_makes_min_length_region() -> void:
	var bar = _bar()
	# Press + release with no motion → smallest legal 2-frame span.
	_press(bar, 5, true)
	_release(bar)
	_assert_true(not _regions.is_empty(), "alt-left click still makes a region")
	var last = _regions[-1]
	_assert_eq(last[0], 5, "click region start = pressed frame")
	_assert_eq(last[1], 6, "click region end = frame+1 (min length 2)")


# --- harness -------------------------------------------------------------

func _bar():
	_regions = []
	_seeks = []
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"for_each": {"max_keyframe": 0, "keyframes": [
			{"index": 0, "end_frame": 40, "channel_mask": 1, "command_raw": 0x0141,
				"source_mode": "CASTER", "interpolation": "IMMEDIATE", "angle": [1, 2, 3]}]},
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	var bar = FramesBar.new()
	bar.size = Vector2(900.0, FramesBar.BAR_H)
	bar.bind_timeline(tl)
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
