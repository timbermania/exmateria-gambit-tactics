extends Node
## TDD guard for EffectFramesBar — the score timeline's ruler, detached into its own
## floating strip so the resizable inspector can't shove it around. It shares the
## bound timeline's axis and owns the seek / scrub / zoom / pan surface the ruler
## used to. Exercises that input seam directly (no paint). See CONTEXT.md
## "Effect Studio" / "Playhead / scrub".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectFramesBarTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_click_seeks()
	_test_drag_scrubs()
	_test_ctrl_wheel_zooms_shared_axis()
	_test_plain_wheel_does_not_zoom()
	_test_middle_drag_pans_shared_axis()
	_test_axis_change_redraws_bar()

	print("\n=== EffectFramesBarTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectFramesBarTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectFramesBarTest")
		get_tree().quit(0)


func _test_click_seeks() -> void:
	# A press in the bar emits seek_requested for the frame under the cursor — the
	# ruler's job, now owned here. (The bar leaves the playhead to the page handler.)
	var rig := _rig()
	var bar = rig["bar"]
	var seen := {"frame": -1}
	bar.seek_requested.connect(func(f): seen["frame"] = f)
	_press(rig, 12.0)
	_assert_eq(seen["frame"], 12, "a press on the frames bar seeks to the frame under it")


func _test_drag_scrubs() -> void:
	# Press then hold+drag: every motion re-emits the seek for the frame under x.
	var rig := _rig()
	var bar = rig["bar"]
	var seen := {"frame": -1, "count": 0}
	bar.seek_requested.connect(func(f):
		seen["frame"] = f
		seen["count"] += 1)
	_press(rig, 5.0)
	_assert_eq(seen["frame"], 5, "initial press seeks under the cursor")
	for target in [10.0, 24.0, 41.0]:
		_move(rig, target)
		_assert_eq(seen["frame"], int(target), "drag seeks to frame %d" % int(target))
	# Release ends the scrub; later motion is inert.
	_release(rig, 41.0)
	var before: int = seen["count"]
	_move(rig, 50.0)
	_assert_eq(seen["count"], before, "motion after release does not seek")


func _test_ctrl_wheel_zooms_shared_axis() -> void:
	# Ctrl+wheel zooms the SHARED axis, so the lanes under the bar zoom with it.
	var rig := _rig()
	var tl = rig["tl"]
	var before: float = tl.axis.pixels_per_frame
	_wheel(rig, true, true)   # ctrl, up
	_assert_true(tl.axis.pixels_per_frame > before, "ctrl+wheel-up zooms the shared axis in")


func _test_plain_wheel_does_not_zoom() -> void:
	var rig := _rig()
	var tl = rig["tl"]
	var before: float = tl.axis.pixels_per_frame
	_wheel(rig, false, true)   # no ctrl, up
	_assert_true(is_equal_approx(tl.axis.pixels_per_frame, before),
		"a plain wheel on the bar does not zoom")


func _test_middle_drag_pans_shared_axis() -> void:
	var rig := _rig()
	var bar = rig["bar"]
	var tl = rig["tl"]
	var before: float = tl.axis.scroll_x
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(500.0, 15.0)
	bar._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(560.0, 15.0)   # drag right 60px
	bar._gui_input(move)
	_assert_true(tl.axis.scroll_x < before, "middle-drag right pans the shared axis (scroll_x drops)")


func _test_axis_change_redraws_bar() -> void:
	# The bar connects to the timeline's axis_changed / playhead_changed so it stays
	# in lock-step. Verify the connections exist (the redraw is a paint side effect).
	var rig := _rig()
	var bar = rig["bar"]
	var tl = rig["tl"]
	_assert_true(tl.axis_changed.is_connected(bar.queue_redraw),
		"the bar redraws when the shared axis pans/zooms")
	_assert_true(tl.playhead_changed.is_connected(bar.queue_redraw),
		"the bar redraws when the playhead moves")


# --- input synthesis ------------------------------------------------------

func _press(rig: Dictionary, frame: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(rig["tl"].axis.frame_to_x(frame), 15.0)
	rig["bar"]._gui_input(ev)


func _release(rig: Dictionary, frame: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(rig["tl"].axis.frame_to_x(frame), 15.0)
	rig["bar"]._gui_input(ev)


func _move(rig: Dictionary, frame: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(rig["tl"].axis.frame_to_x(frame), 15.0)
	rig["bar"]._gui_input(ev)


func _wheel(rig: Dictionary, ctrl: bool, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.position = Vector2(400.0, 15.0)
	rig["bar"]._gui_input(ev)


# --- fixtures -------------------------------------------------------------

func _rig() -> Dictionary:
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 40, "emitter_id": 2}]},
		],
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	var bar = FramesBar.new()
	bar.size = Vector2(900.0, FramesBar.BAR_H)
	bar.bind_timeline(tl)
	return {"tl": tl, "bar": bar}


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
