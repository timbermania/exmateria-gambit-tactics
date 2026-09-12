extends Node
## TDD guard (#271 follow-up): the timeline's phase-boundary markers. Where phase 1 /
## for-each / phase 2 begin was barely visible (a 5%-alpha strip on the 20px header row only);
## now each phase start is a vertical boundary line + label across the whole timeline. This
## guards the pure seam the draw consumes: phase_boundaries() reads the projected score's
## phase sections into {frame, label} in phase order, so the lines land at the right frames.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectScoreTimelinePhaseBoundaryTest.tscn

const TimelineScene := preload("res://src/effects/studio/EffectScoreTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_boundaries_from_phase_sections()
	_test_empty_when_no_phases()

	print("\n=== EffectScoreTimelinePhaseBoundaryTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScoreTimelinePhaseBoundaryTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScoreTimelinePhaseBoundaryTest")
		get_tree().quit(0)


func _timeline() -> Node:
	var t = TimelineScene.new()
	add_child(t)
	return t


## Each phase section becomes one {frame,label} boundary at its absolute start, in order.
func _test_boundaries_from_phase_sections() -> void:
	var t = _timeline()
	t._score = {"phases": [
		{"name": "phase1", "label": "Phase 1", "start": 0, "end": 60},
		{"name": "for_each", "label": "For-each", "start": 96, "end": 100},
		{"name": "phase2", "label": "Phase 2", "start": 104, "end": 120},
	]}
	var b: Array = t.phase_boundaries()
	_assert_eq(b.size(), 3, "one boundary per phase section")
	_assert_eq(b[0].get("frame"), 0, "phase1 boundary at 0")
	_assert_eq(b[1].get("frame"), 96, "for-each boundary at phase1_duration")
	_assert_eq(b[1].get("label"), "For-each", "for-each label carried")
	_assert_eq(b[2].get("frame"), 104, "phase2 boundary at phase1_duration+phase2_delay")
	t.queue_free()


func _test_empty_when_no_phases() -> void:
	var t = _timeline()
	t._score = {"phases": []}
	_assert_eq(t.phase_boundaries().size(), 0, "no phases → no boundaries")
	t.queue_free()


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])
