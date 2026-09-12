extends Node
## TDD guard for the palette BOUNDARY edit (ADR-0087) — a boundary drag re-times a palette
## tween by dragging the shared edge between it and its lane-neighbour. Because palette is
## length-encoded (cumulative starts, no stored end), moving one absolute boundary is a
## SUM-PRESERVING trade of the two neighbouring durations: the dragged span grows/shrinks and
## the neighbour absorbs it, so the FAR edge (everything downstream) stays PINNED. It is a
## SINGLE synthetic `boundary_end` scalar field through the normal choke point (not the sound
## gap-trade, not a compound), so it rides the existing drag-scoped coalesce (one drag = one
## undo) and scalar undo. Drags snap to 8-frame steps; the neighbour never drops below 1 frame.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/PaletteBoundaryEditTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
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
	_test_ripple_edit_undoes_through_the_recorded_ref()

	print("\n=== PaletteBoundaryEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PaletteBoundaryEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] PaletteBoundaryEditTest")
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


## A boundary edit is read-live (no re-seek) and undoes through the same scalar path.
func _test_boundary_is_read_live_and_undoes() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_boundary_ref(0), 8)
	_assert_eq(res.get("invalidates_sim", true), false, "a palette boundary edit is read-live")
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
## `duration` pseudo-field that delegates to the boundary trade (`boundary_end = start +
## new_duration` — the channel knows the cumulative start, the inspector does not). Typing 24
## into span 0 of 16/16/16 grows it to tv 3 and shrinks the neighbour to tv 1 — far edge pinned.
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
## number (the camera human-units honest tell) — 20 lands on 24, and the returned after_raw
## is what the re-rendered cell will show.
func _test_typed_duration_quantizes_to_the_snap_grid() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_duration_ref(0), 20)
	_assert_eq(int(ch.get_keyframe(0).time_value), 3, "20 quantizes to 24 (tv 3)")
	_assert_eq(res.get("after_raw", -1), 24, "after_raw reports the SNAPPED duration, not the typed one")


## Typing a duration on the lane TAIL extends the span — no neighbour to trade against,
## matching the drag's tail behaviour.
func _test_typed_duration_extends_the_tail() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_duration_ref(2), 48)
	_assert_eq(int(ch.get_keyframe(2).duration_frames), 48, "the tail span extends to 48")
	_assert_eq(int(ch.get_keyframe(1).duration_frames), 16, "the previous span is untouched")


## Undo of a typed duration replays the pre-edit duration through the same pseudo-field —
## both traded spans come back.
func _test_typed_duration_undoes_in_duration_units() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_duration_ref(0), 8)
	_assert_true(session.undo(), "the typed duration is undoable")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "undo restores span 0 to tv 2")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "undo restores the neighbour to tv 2")


## RIPPLE mode (ADR-0087 dec. 10): a field_ref carrying `ripple: true` skips the
## sum-preserving trade — the mid-lane span takes the tail-extend path, the neighbour keeps
## its own duration, and (palette being length-encoded) everything downstream shifts by the
## delta for free.
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


## Undo replays through the RECORDED ref (ripple included), so a ripple resize undoes to the
## exact prior lane even if the toggle has been flipped off since.
func _test_ripple_edit_undoes_through_the_recorded_ref() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _boundary_ref(0)
	ref["ripple"] = true
	session.apply_edit(ref, 24)
	_assert_true(session.undo(), "the ripple resize is undoable")
	_assert_eq(int(ch.get_keyframe(0).time_value), 2, "undo restores the resized span")
	_assert_eq(int(ch.get_keyframe(1).time_value), 2, "the neighbour never moved")


# --- fixtures -------------------------------------------------------------

func _duration_ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index, "field": "duration"}


func _boundary_ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index, "field": "boundary_end"}


func _chan(data):
	return data.palette.get_channel("for_each", "affected_units")


## Build a palette channel from a list of time_values (durations = tv×8).
func _fake_data(time_values: Array) -> RefCounted:
	var kfs: Array = []
	for i in range(time_values.size()):
		var tv: int = int(time_values[i])
		kfs.append({"index": i, "time_value": tv, "duration_frames": Lowering.duration_for_time_value(tv),
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	var pd = PaletteDataClass.from_json({
		"for_each": {"affected_units": {
			"context": "for_each", "channel_name": "affected_units",
			"max_keyframe": time_values.size() + 1, "keyframes": kfs,
		}},
	})
	var data := _FakeData.new()
	data.palette = pd
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
