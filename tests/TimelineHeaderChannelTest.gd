extends Node
## TDD guard (#271) for TimelineHeaderChannel — the write-side encoder for the three GLOBAL
## timeline-header phase durations (phase1_duration @+0x04, spawn_delay @+0x06,
## phase2_delay @+0x0A). Unlike the per-keyframe channels, these live on `data.timeline`
## (a TimelineData), so the encoder writes the field directly and keeps the `header` dict —
## the saver's JSON source — in sync. Every edit re-flows the whole score (phase offsets
## shift), so it always declares invalidates_sim + invalidates_layout. Faithful is the
## honest "fits the positive 16-bit frame slot" advisory (parser reads s16).
##
## Run: <GODOT> --path . --quit-after 3 res://tests/TimelineHeaderChannelTest.tscn

const TimelineHeaderChannel = preload("res://src/effects/studio/TimelineHeaderChannel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_phase1_edit_writes_var_and_returns_before_after()
	_test_edit_syncs_header_dict_for_saver()
	_test_spawn_delay_and_phase2_delay_write()
	_test_every_edit_invalidates_sim_and_layout()
	_test_faithful_in_range_ok()
	_test_faithful_over_s16_positive_is_free_only()
	_test_unknown_field_is_empty()
	_test_read_raw_mirrors_storage()

	print("\n=== TimelineHeaderChannelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TimelineHeaderChannelTest")
		get_tree().quit(1)
	else:
		print("[PASS] TimelineHeaderChannelTest")
		get_tree().quit(0)


func _effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.new()
	ed.timeline.phase1_duration = 96
	ed.timeline.spawn_delay = 10
	ed.timeline.phase2_delay = 8
	ed.timeline.header = {
		"unknown_00": 3, "unknown_02": 20,
		"phase1_duration": 96, "spawn_delay": 10, "unknown_08": 3, "phase2_delay": 8,
	}
	return ed


func _ref(field: String) -> Dictionary:
	return {"channel": "timeline_header", "field": field}


func _test_phase1_edit_writes_var_and_returns_before_after() -> void:
	var ed = _effect()
	var res: Dictionary = TimelineHeaderChannel.apply_raw(ed, _ref("phase1_duration"), 120)
	_assert_eq(res.get("before_raw"), 96, "before_raw is the pre-edit duration")
	_assert_eq(res.get("after_raw"), 120, "after_raw is the new duration")
	_assert_eq(ed.timeline.phase1_duration, 120, "the sim-read var is updated (phase_offset source)")


func _test_edit_syncs_header_dict_for_saver() -> void:
	var ed = _effect()
	TimelineHeaderChannel.apply_raw(ed, _ref("phase1_duration"), 200)
	_assert_eq(ed.timeline.header.get("phase1_duration"), 200,
		"the header dict (saver JSON source) tracks the edit")
	_assert_eq(ed.timeline.header.get("unknown_00"), 3, "untouched header bytes are preserved")


func _test_spawn_delay_and_phase2_delay_write() -> void:
	var ed = _effect()
	TimelineHeaderChannel.apply_raw(ed, _ref("spawn_delay"), 15)
	TimelineHeaderChannel.apply_raw(ed, _ref("phase2_delay"), 4)
	_assert_eq(ed.timeline.spawn_delay, 15, "spawn_delay writes")
	_assert_eq(ed.timeline.phase2_delay, 4, "phase2_delay writes")


func _test_every_edit_invalidates_sim_and_layout() -> void:
	var ed = _effect()
	var res: Dictionary = TimelineHeaderChannel.apply_raw(ed, _ref("phase1_duration"), 100)
	_assert_true(bool(res.get("invalidates_sim", false)), "duration edit re-folds the sim")
	_assert_true(bool(res.get("invalidates_layout", false)), "duration edit re-flows the score bands")


func _test_faithful_in_range_ok() -> void:
	var ed = _effect()
	var res: Dictionary = TimelineHeaderChannel.apply_raw(ed, _ref("phase1_duration"), 500)
	_assert_true(bool(res.get("faithful", {}).get("ok", false)), "an in-range duration is faithful")


func _test_faithful_over_s16_positive_is_free_only() -> void:
	var ed = _effect()
	var res: Dictionary = TimelineHeaderChannel.apply_raw(ed, _ref("phase1_duration"), 40000)
	_assert_true(not bool(res.get("faithful", {}).get("ok", true)),
		"a value past 32767 does not fit the positive 16-bit frame slot (Free-only)")


func _test_unknown_field_is_empty() -> void:
	var ed = _effect()
	var res: Dictionary = TimelineHeaderChannel.apply_raw(ed, _ref("nonsense"), 1)
	_assert_true(res.is_empty(), "an unknown field is refused (empty result)")


func _test_read_raw_mirrors_storage() -> void:
	var ed = _effect()
	_assert_eq(TimelineHeaderChannel.read_raw(ed, _ref("spawn_delay")), 10,
		"read_raw returns the live stored value (inspector seed)")


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
