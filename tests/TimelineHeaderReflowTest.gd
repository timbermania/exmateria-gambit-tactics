extends Node
## TDD guard (#271): a timeline-header duration edit routes through the EffectEditSession
## choke point AND re-flows the whole score. The score's phase offsets are a pure function of
## the durations (EffectScoreModel.phase_offset: for_each = phase1_duration; phase2 =
## phase1_duration + phase2_delay), so editing phase1_duration must shift BOTH the for_each
## band and phase2 — the "one genuinely useful wrinkle" this subsystem solves once. Scalar
## undo replays the raw byte and the score reconstructs exactly.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/TimelineHeaderReflowTest.tscn

const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectScoreModel = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectPhase = ExMateriaEffects.EffectPhase
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_session_routes_timeline_header_channel()
	_test_phase1_edit_reflows_for_each_and_phase2_offsets()
	_test_phase2_delay_edit_shifts_only_phase2()
	_test_undo_restores_offsets()

	print("\n=== TimelineHeaderReflowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TimelineHeaderReflowTest")
		get_tree().quit(1)
	else:
		print("[PASS] TimelineHeaderReflowTest")
		get_tree().quit(0)


func _effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.new()
	ed.timeline.phase1_duration = 96
	ed.timeline.spawn_delay = 10
	ed.timeline.phase2_delay = 8
	ed.timeline.header = {
		"phase1_duration": 96, "spawn_delay": 10, "phase2_delay": 8,
	}
	return ed


func _ref(field: String) -> Dictionary:
	return {"channel": "timeline_header", "field": field}


## The choke point recognizes the channel and reports the edit re-folds the sim.
func _test_session_routes_timeline_header_channel() -> void:
	var ed = _effect()
	var session = EffectEditSession.new(ed)
	var res: Dictionary = session.apply_edit(_ref("phase1_duration"), 120)
	_assert_true(not res.is_empty(), "session dispatches the timeline_header channel")
	_assert_true(bool(res.get("invalidates_sim", false)), "edit invalidates the sim")
	_assert_eq(ed.timeline.phase1_duration, 120, "the live duration is written")


## Editing phase1_duration shifts BOTH derived phase offsets (for_each and phase2).
func _test_phase1_edit_reflows_for_each_and_phase2_offsets() -> void:
	var ed = _effect()
	var session = EffectEditSession.new(ed)
	session.apply_edit(_ref("phase1_duration"), 120)
	_assert_eq(EffectScoreModel.phase_offset(ed, EffectPhase.PHASE_FOR_EACH), 120,
		"for_each band now starts at the new phase1_duration")
	_assert_eq(EffectScoreModel.phase_offset(ed, EffectPhase.PHASE2), 120 + 8,
		"phase2 shifts with phase1_duration (phase1_duration + phase2_delay)")


## phase2_delay moves ONLY the phase2 offset; for_each stays pinned at phase1_duration.
func _test_phase2_delay_edit_shifts_only_phase2() -> void:
	var ed = _effect()
	var session = EffectEditSession.new(ed)
	session.apply_edit(_ref("phase2_delay"), 20)
	_assert_eq(EffectScoreModel.phase_offset(ed, EffectPhase.PHASE_FOR_EACH), 96,
		"for_each is unaffected by phase2_delay")
	_assert_eq(EffectScoreModel.phase_offset(ed, EffectPhase.PHASE2), 96 + 20,
		"phase2 absorbs the new delay")


## Scalar undo replays the pre-edit raw; the score reconstructs exactly.
func _test_undo_restores_offsets() -> void:
	var ed = _effect()
	var session = EffectEditSession.new(ed)
	session.apply_edit(_ref("phase1_duration"), 120)
	session.undo()
	_assert_eq(ed.timeline.phase1_duration, 96, "undo restores the pre-edit duration")
	_assert_eq(EffectScoreModel.phase_offset(ed, EffectPhase.PHASE_FOR_EACH), 96,
		"the for_each offset reconstructs after undo")


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
