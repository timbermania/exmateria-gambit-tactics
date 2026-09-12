extends Node
## TDD guard (#270, ADR-0093) for TimeScaleChannel — the write-side encoder for the effect's
## two PACING curves (`outer_phases` = "Phase 1 pacing", `for_each` = "For-each pacing"), each
## 600 ints on disk. Unlike the per-keyframe channels, a pacing edit is a WHOLE-CURVE paint
## stroke: the painter commits the full 600-int array on mouse-up, so the channel takes the new
## array as `new_raw`, snapshots the pre-edit array as `before_raw`, and writes it onto
## `data.time_scale[<field>]`. Curve edits `invalidates_sim` (pacing feeds `tl.setup` →
## EffectEndModel, so a re-fold recomputes the end marker). Undo is the scalar replay: the
## stored `before_raw` array re-applies through the same path.
##
## The two enable BITS are NOT here — they physically live in the effect_flags byte and edit via
## EffectFlagsChannel (bits 5/6); this channel owns only the curve samples.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/TimeScaleChannelTest.tscn

const TimeScaleChannel = preload("res://src/effects/studio/TimeScaleChannel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_edit_writes_curve_and_returns_before_after()
	_test_other_curve_untouched()
	_test_invalidates_sim()
	_test_before_raw_is_independent_copy()
	_test_scalar_undo_replay_restores()
	_test_for_each_curve_addressed_by_field()
	_test_faithful_in_range_ok()
	_test_faithful_out_of_range_not_ok()
	_test_unknown_field_refused()
	_test_absent_time_scale_refused()

	print("\n=== TimeScaleChannelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TimeScaleChannelTest")
		get_tree().quit(1)
	else:
		print("[PASS] TimeScaleChannelTest")
		get_tree().quit(0)


# A 600-int pacing curve in the real 2..10 range, seed-shifted.
func _ramp(seed: int) -> Array:
	var out: Array = []
	for i in range(600):
		out.append(2 + ((i + seed) % 9))
	return out


func _effect(with_time_scale: bool = true):
	var ed = EffectDataClass.new()
	if with_time_scale:
		ed.time_scale = {
			"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
			"outer_phases": _ramp(0),
			"for_each": _ramp(4),
		}
	return ed


func _ref(field: String = "outer_phases") -> Dictionary:
	return {"channel": "time_scale", "field": field}


func _test_edit_writes_curve_and_returns_before_after() -> void:
	var ed = _effect()
	var before_snap: Array = ed.time_scale["outer_phases"].duplicate()
	var new_curve: Array = _ramp(2)
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref("outer_phases"), new_curve)
	_assert_eq(res.get("before_raw"), before_snap, "before_raw is the pre-edit 600-int curve")
	_assert_eq(res.get("after_raw"), new_curve, "after_raw is the new 600-int curve")
	_assert_eq(ed.time_scale["outer_phases"], new_curve, "the stored outer_phases curve is updated")


func _test_other_curve_untouched() -> void:
	var ed = _effect()
	var foreach_snap: Array = ed.time_scale["for_each"].duplicate()
	TimeScaleChannel.apply_raw(ed, _ref("outer_phases"), _ramp(7))
	_assert_eq(ed.time_scale["for_each"], foreach_snap, "editing outer_phases leaves for_each untouched")


func _test_invalidates_sim() -> void:
	var ed = _effect()
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), _ramp(1))
	_assert_true(bool(res.get("invalidates_sim", false)),
		"a pacing edit re-folds the sim (feeds tl.setup / EffectEndModel)")


func _test_before_raw_is_independent_copy() -> void:
	# before_raw must be a snapshot, not an alias — a later write to data must not corrupt the
	# recorded undo value.
	var ed = _effect()
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), _ramp(1))
	var before: Array = res["before_raw"]
	var first = before[0]
	TimeScaleChannel.apply_raw(ed, _ref(), _ramp(5))  # a second edit
	_assert_eq(before[0], first, "the first edit's before_raw is unaffected by a later edit")


func _test_scalar_undo_replay_restores() -> void:
	# The session's scalar undo replays before_raw through the same apply path.
	var ed = _effect()
	var original: Array = ed.time_scale["outer_phases"].duplicate()
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), _ramp(3))
	TimeScaleChannel.apply_raw(ed, _ref(), res["before_raw"])  # replay before
	_assert_eq(ed.time_scale["outer_phases"], original, "replaying before_raw restores the curve exactly")


func _test_for_each_curve_addressed_by_field() -> void:
	var ed = _effect()
	var new_curve: Array = _ramp(8)
	TimeScaleChannel.apply_raw(ed, _ref("for_each"), new_curve)
	_assert_eq(ed.time_scale["for_each"], new_curve, "the field selects the for_each curve")


func _test_faithful_in_range_ok() -> void:
	var ed = _effect()
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), _ramp(0))  # values 2..10
	var f: Dictionary = res.get("faithful", {})
	_assert_true(bool(f.get("ok", false)), "a 0..15 (nibble) curve is faithfully encodable")


func _test_faithful_out_of_range_not_ok() -> void:
	var ed = _effect()
	var bad: Array = _ramp(0)
	bad[10] = 42  # past the nibble alphabet
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), bad)
	var f: Dictionary = res.get("faithful", {})
	_assert_true(not bool(f.get("ok", true)), "a value past 15 does not fit the nibble encoding")


func _test_unknown_field_refused() -> void:
	var ed = _effect()
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref("bogus"), _ramp(0))
	_assert_true(res.is_empty(), "an unknown curve field is refused (empty result)")


func _test_absent_time_scale_refused() -> void:
	var ed = _effect(false)  # no time_scale block
	var res: Dictionary = TimeScaleChannel.apply_raw(ed, _ref(), _ramp(0))
	_assert_true(res.is_empty(), "an effect with no time_scale block is refused (empty result)")


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
