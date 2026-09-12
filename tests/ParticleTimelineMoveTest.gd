extends Node
## TDD guard for the particle-timeline MOVE verb (ADR-0089 particle_timeline amendment,
## slice 6 — built last). A body-drag slides a whole span through the gaps around it: BOTH
## boundaries shift by one clamped delta, width preserved. Because time is absolute, the shift
## is absorbed by the two immediate neighbours, so BOTH must be gaps (or the phase edge) — a
## burst wedged between two drawn bursts is pinned, and the first span (its left edge is the
## pinned origin) never slides. Lowers to two boundary_raw shifts as ONE apply_compound.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleTimelineMoveTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_move_slides_both_boundaries_width_preserved()
	_test_move_right_clamps_to_the_right_gap()
	_test_move_left_clamps_to_the_left_gap()
	_test_a_wedged_span_is_pinned()
	_test_the_first_span_is_pinned_to_the_origin()
	_test_a_tail_span_slides_into_open_space()
	_test_a_move_is_one_compound_undo()

	print("\n=== ParticleTimelineMoveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleTimelineMoveTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleTimelineMoveTest")
		get_tree().quit(0)


## Span 2 (drawn [10,20)) sits between two gaps. Moving it +5 slides both boundaries: the
## span becomes [15,25) (width kept), the left gap grows, the right gap shrinks — no drawn
## span disturbed.
func _test_move_slides_both_boundaries_width_preserved() -> void:
	var data := _fake_data([[0, 0], [10, 0], [20, 3], [30, 0], [40, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.move_span(_move_ref(2), 5)
	_assert_true(not res.is_empty(), "the move applies")
	_assert_eq(int(ch.keyframes[1].time), 15, "the left boundary slid +5")
	_assert_eq(int(ch.keyframes[2].time), 25, "the right boundary slid +5 (width preserved)")
	_assert_eq(int(ch.keyframes[3].time), 30, "the downstream drawn span stays pinned")


## Moving right clamps to the right gap's room — the span can't push into the downstream drawn
## span (right gap [20,30) is 10 wide → +20 clamps to +10).
func _test_move_right_clamps_to_the_right_gap() -> void:
	var data := _fake_data([[0, 0], [10, 0], [20, 3], [30, 0], [40, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.move_span(_move_ref(2), 20)
	_assert_eq(int(ch.keyframes[2].time), 30, "the right boundary clamps at the downstream wall")
	_assert_eq(int(ch.keyframes[1].time), 20, "…and the left boundary followed by the same clamped delta")


## Moving left clamps to the left gap's room (left gap [0,10) is 10 wide → −20 clamps to −10).
func _test_move_left_clamps_to_the_left_gap() -> void:
	var data := _fake_data([[0, 0], [10, 0], [20, 3], [30, 0], [40, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.move_span(_move_ref(2), -20)
	_assert_eq(int(ch.keyframes[1].time), 0, "the left boundary clamps at the previous boundary")
	_assert_eq(int(ch.keyframes[2].time), 10, "…the span kept its width sliding left")


## A burst wedged between two DRAWN bursts cannot slide — the move is refused.
func _test_a_wedged_span_is_pinned() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2], [30, 3]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.move_span(_move_ref(2), 3)
	_assert_true(res.is_empty(), "a wedged span is pinned (move refused)")
	_assert_eq(int(ch.keyframes[2].time), 20, "…nothing moved")


## The first span's left edge is the pinned origin — it never slides.
func _test_the_first_span_is_pinned_to_the_origin() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.move_span(_move_ref(1), 3)
	_assert_true(res.is_empty(), "the first span is pinned to the origin (move refused)")
	_assert_eq(int(ch.keyframes[1].time), 10, "…nothing moved")


## A tail span (no right neighbour) slides right into open phase space.
func _test_a_tail_span_slides_into_open_space() -> void:
	var data := _fake_data([[0, 0], [10, 0], [20, 1]])   # span 2 drawn, at the tail
	var session = Session.new(data)
	var ch = _chan(data)

	session.move_span(_move_ref(2), 50)
	_assert_eq(int(ch.keyframes[1].time), 60, "the left boundary slid +50 into the open tail")
	_assert_eq(int(ch.keyframes[2].time), 70, "…the span kept its width")


## A whole move is ONE compound undo restoring both boundaries.
func _test_a_move_is_one_compound_undo() -> void:
	var data := _fake_data([[0, 0], [10, 0], [20, 3], [30, 0], [40, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.move_span(_move_ref(2), 5)
	_assert_true(session.undo(), "the move is undoable")
	_assert_eq(int(ch.keyframes[1].time), 10, "one undo restores the left boundary")
	_assert_eq(int(ch.keyframes[2].time), 20, "…and the right boundary")
	_assert_true(not session.undo(), "…in a single step (one compound entry)")


# --- fixtures -------------------------------------------------------------

func _move_ref(index: int) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0, "event_index": index}


func _chan(data):
	return data.timeline.get_channels("for_each")[0]


func _fake_data(kfs: Array) -> RefCounted:
	var kf_dicts: Array = []
	for pair in kfs:
		kf_dicts.append({"time": int(pair[0]), "emitter_id": int(pair[1]), "action_flags": 0})
	var tl = TimelineDataClass.from_json({
		"header": {"phase1_duration": 0},
		"particle_channels": [{
			"context": "for_each", "channel_index": 0,
			"max_keyframe": kfs.size() - 1, "keyframes": kf_dicts,
		}],
	})
	var data := _FakeData.new()
	data.timeline = tl
	return data


class _FakeData extends RefCounted:
	var timeline = null
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
