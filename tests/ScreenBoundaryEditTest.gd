extends Node
## TDD guard for the screen BOUNDARY edit (ADR-0087, screen lane) — a boundary drag re-times
## a screen tween by dragging the shared edge between it and its lane-neighbour. Screen is
## length-encoded exactly like palette (cumulative starts, no stored end; the SAME
## ColorLowering time_value grid), so moving one absolute boundary is the same SUM-PRESERVING
## trade: the dragged span grows/shrinks and the neighbour absorbs it, keeping the far edge
## (everything downstream) PINNED. It is a SINGLE synthetic `boundary_end` scalar field
## through the normal choke point, so it rides the drag-scoped coalesce (one drag = one undo)
## and scalar undo. Drags snap to 8-frame steps; the neighbour never drops below 1 frame.
## Screen's address is 1-D (phase context only — no channel_name).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScreenBoundaryEditTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const ScreenDataClass = ExMateriaEffects.ScreenData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_boundary_grow_is_a_sum_preserving_trade()
	_test_boundary_is_read_live_and_undoes()
	_test_over_drag_clamps_and_keeps_the_neighbour()
	_test_a_whole_drag_coalesces_to_one_undo()
	_test_tail_boundary_extends_with_no_neighbour()
	_test_typed_duration_is_the_same_boundary_trade()
	_test_typed_duration_quantizes_to_the_snap_grid()
	_test_typed_duration_extends_the_tail()
	_test_typed_duration_undoes_in_duration_units()
	_test_ripple_boundary_shifts_downstream_instead_of_trading()
	_test_ripple_typed_duration_shifts_downstream()

	print("\n=== ScreenBoundaryEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScreenBoundaryEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenBoundaryEditTest")
		get_tree().quit(0)


## Growing span 0's right edge from 16 → 24 grows its duration to 24 (tv 3) and SHRINKS the
## neighbour (span 1) to 8 (tv 1), keeping their far edge pinned at 32. Downstream (span 2)
## is untouched.
func _test_boundary_grow_is_a_sum_preserving_trade() -> void:
	var data := _fake_data([2, 2, 2])   # durations 16/16/16, starts 0/16/32
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_boundary_ref(0), 24)
	_assert_eq(int(ch.get_keyframe(0).time_value), 3, "span 0 grows to tv 3 (24 frames)")
	_assert_eq(int(ch.get_keyframe(1).time_value), 1, "the neighbour absorbs it → tv 1 (8 frames)")
	_assert_eq(int(ch.get_keyframe(2).time_value), 2, "downstream span 2 is untouched (still tv 2)")
	_assert_eq(int(ch.get_keyframe(0).duration_frames) + int(ch.get_keyframe(1).duration_frames), 32,
		"the two traded durations still sum to the pinned far edge (32)")
	_assert_eq(res.get("before_raw", -1), 16, "the pre-edit boundary (16) is recorded for undo")


## A boundary edit is read-live (no re-seek) and relayouts (the ruler reprojects), and undoes
## through the same scalar path.
func _test_boundary_is_read_live_and_undoes() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_boundary_ref(0), 8)
	_assert_eq(res.get("invalidates_sim", true), false, "a screen boundary edit is read-live")
	_assert_eq(res.get("invalidates_layout", false), true, "a screen boundary edit reprojects the ruler")
	_assert_eq(int(ch.get_keyframe(0).time_value), 1, "span 0 shrank to tv 1")
	_assert_eq(int(ch.get_keyframe(1).time_value), 3, "the neighbour grew to tv 3")

	_assert_true(session.undo(), "the boundary edit is undoable")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "undo restores span 0 to tv 2")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "undo restores the neighbour to tv 2")


## Over-dragging past the neighbour CLAMPS so the neighbour keeps ≥ 1 frame — never a
## zero-width span, never an implicit delete.
func _test_over_drag_clamps_and_keeps_the_neighbour() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(0), 100)   # far past the far edge (32)
	_assert_true(int(ch.get_keyframe(1).duration_frames) >= 1, "the neighbour keeps at least 1 frame")
	_assert_true(int(ch.get_keyframe(0).duration_frames) < 32, "the dragged span never swallows the whole span")


## A whole drag (many per-frame boundary edits under one coalesce bracket) collapses to ONE
## undo that restores the pristine boundary.
func _test_a_whole_drag_coalesces_to_one_undo() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _boundary_ref(0)
	session.begin_coalesce(ref)
	session.apply_edit(ref, 8)
	session.apply_edit(ref, 24)
	session.apply_edit(ref, 16)
	session.end_coalesce()

	_assert_true(session.undo(), "the coalesced drag is one undo")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "one undo restores span 0")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "one undo restores the neighbour")
	_assert_true(not session.undo(), "there is nothing more to undo — the whole drag was one entry")


## The lane tail (a boundary with no next keyframe to trade against) just extends the span —
## there is nothing downstream to pin.
func _test_tail_boundary_extends_with_no_neighbour() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(2), 80)   # span 2 is the last array keyframe
	_assert_eq(int(ch.get_keyframe(2).duration_frames), 48, "the tail span extends to the snapped length (48)")


## The TYPED Duration row (ADR-0087 dec. 9) is the SAME edit as the edge drag: a
## `duration` pseudo-field delegating to the boundary trade — screen mirrors palette exactly
## (its address is just 1-D). Typing 24 into span 0 of 16/16/16 trades with the neighbour.
func _test_typed_duration_is_the_same_boundary_trade() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_duration_ref(0), 24)
	_assert_eq(int(ch.get_keyframe(0).time_value), 3, "span 0 grows to tv 3 (24 frames)")
	_assert_eq(int(ch.get_keyframe(1).time_value), 1, "the neighbour absorbs it → tv 1 (8 frames)")
	_assert_eq(int(ch.get_keyframe(2).time_value), 2, "downstream span 2 is untouched")
	_assert_eq(res.get("before_raw", -1), 16, "the pre-edit DURATION (16) is recorded for undo")
	_assert_eq(res.get("after_raw", -1), 24, "the applied duration comes back in duration units")
	_assert_eq(res.get("invalidates_sim", true), false, "a typed duration is read-live")
	_assert_eq(res.get("relayout", false), true,
		"a typed duration takes the full-refresh path so the cell re-seeds with the snapped number")


## A typed value off the 8-grid quantizes to the nearest snap step and reports the SNAPPED
## number (the camera human-units honest tell).
func _test_typed_duration_quantizes_to_the_snap_grid() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_duration_ref(0), 20)
	_assert_eq(int(ch.get_keyframe(0).time_value), 3, "20 quantizes to 24 (tv 3)")
	_assert_eq(res.get("after_raw", -1), 24, "after_raw reports the SNAPPED duration, not the typed one")


## Typing a duration on the lane TAIL extends the span — no neighbour to trade against.
func _test_typed_duration_extends_the_tail() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_duration_ref(2), 48)
	_assert_eq(int(ch.get_keyframe(2).duration_frames), 48, "the tail span extends to 48")
	_assert_eq(int(ch.get_keyframe(1).duration_frames), 16, "the previous span is untouched")


## Undo of a typed duration replays the pre-edit duration through the same pseudo-field.
func _test_typed_duration_undoes_in_duration_units() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_duration_ref(0), 8)
	_assert_true(session.undo(), "the typed duration is undoable")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "undo restores span 0 to tv 2")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "undo restores the neighbour to tv 2")


## RIPPLE mode (ADR-0087 dec. 10): a field_ref carrying `ripple: true` skips the
## sum-preserving trade — the mid-lane span takes the tail-extend path and downstream shifts.
func _test_ripple_boundary_shifts_downstream_instead_of_trading() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _boundary_ref(0)
	ref["ripple"] = true
	session.apply_edit(ref, 24)
	_assert_eq(int(ch.get_keyframe(0).time_value), 3, "the resized span grows to tv 3 (24 frames)")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "the neighbour KEEPS its duration (no trade)")
	_assert_eq(int(ch.get_keyframe(2).time_value), 2, "downstream keeps its duration too — it shifts, not shrinks")

	_assert_true(session.undo(), "the ripple resize is undoable")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "undo restores the resized span")


## The typed Duration row rides the same flag — the two affordances never diverge (§2).
func _test_ripple_typed_duration_shifts_downstream() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _duration_ref(1)
	ref["ripple"] = true
	var res: Dictionary = session.apply_edit(ref, 8)
	_assert_eq(int(ch.get_keyframe(1).time_value), 1, "the mid-lane span resizes to tv 1")
	_assert_eq(int(ch.get_keyframe(2).time_value), 2, "downstream keeps its duration (shifted, not traded)")
	_assert_eq(res.get("after_raw", -1), 8, "after_raw stays in duration units")


# --- fixtures -------------------------------------------------------------

func _duration_ref(index: int) -> Dictionary:
	return {"channel": "screen", "context": "for_each",
		"event_index": index, "field": "duration"}


func _boundary_ref(index: int) -> Dictionary:
	return {"channel": "screen", "context": "for_each",
		"event_index": index, "field": "boundary_end"}


func _chan(data):
	return data.screen.get_channel("for_each")


## Build a screen channel from a list of time_values (durations = tv×8). Alternating
## Blend/Gradient kinds so the trade is proven variant-agnostic (timing only).
func _fake_data(time_values: Array) -> RefCounted:
	var kfs: Array = []
	for i in range(time_values.size()):
		var tv: int = int(time_values[i])
		var blend: bool = (i % 2) == 0
		kfs.append({"index": i, "time_value": tv,
			"duration_frames": Lowering.duration_for_time_value(tv),
			"start_r": 10, "start_g": 20, "start_b": 30,
			"end_r": 10, "end_g": 20, "end_b": 30,
			"ctrl": (0x85 if blend else 0x00), "mode": ("TINT" if blend else "FADE"),
			"blend_mode": (5 if blend else 0)})
	var sd = ScreenDataClass.from_json({
		"for_each": {"context": "for_each",
			"max_keyframe": time_values.size() + 1, "keyframes": kfs},
	})
	var data := _FakeData.new()
	data.screen = sd
	return data


class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var camera = null


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
