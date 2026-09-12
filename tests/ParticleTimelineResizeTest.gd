extends Node
## TDD guard for the particle-timeline RESIZE verb (ADR-0089 particle_timeline amendment,
## slice 2) — dragging a span's RIGHT edge re-times ONE stored `kf[N].time`. Unlike palette
## (length-encoded, sum-preserving trade), particle `time` is CUMULATIVE-ABSOLUTE, so a
## boundary edit is a single direct write clamped by the invariant: *an edit only ever
## consumes or creates gap (null-span) space — it never changes a drawn span's extent.*
##
## Scalar slice (this guard): GROW consumes the adjacent gap up to the next boundary and
## clamps at a DRAWN wall; SHRINK widens the adjacent gap (or the tail) down to a 1-frame
## floor. A span flush against a DRAWN neighbour is FROZEN here — the structural auto-open /
## reclaim paths land in slice 4. Rides the normal scalar choke point: drag-coalesce (one
## drag = one undo) + scalar undo replay.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleTimelineResizeTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_grow_consumes_the_adjacent_gap_up_to_the_next_boundary()
	_test_grow_reports_the_boundary_for_undo_and_invalidates_sim()
	_test_shrink_widens_the_adjacent_gap()
	_test_shrink_clamps_to_a_one_frame_floor_above_prev()
	_test_grow_against_a_drawn_wall_is_frozen()
	_test_shrink_against_a_drawn_neighbour_auto_opens_a_gap()
	_test_tail_span_grows_freely()
	_test_origin_boundary_is_refused()
	_test_a_whole_drag_coalesces_to_one_undo()

	print("\n=== ParticleTimelineResizeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleTimelineResizeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleTimelineResizeTest")
		get_tree().quit(0)


## GROW: span 1 ends at 10; span 2 [10,20) is a GAP (emitter 0). Dragging the edge to 25
## consumes the whole gap and clamps at the next stored boundary (20) — the gap shrinks to
## zero, the downstream drawn span 3 keeps its extent.
func _test_grow_consumes_the_adjacent_gap_up_to_the_next_boundary() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(1), 25)
	_assert_eq(int(ch.keyframes[1].time), 20, "grow clamps at the next boundary (gap fully consumed)")
	_assert_eq(int(ch.keyframes[3].time), 30, "the downstream drawn span keeps its far edge")


func _test_grow_reports_the_boundary_for_undo_and_invalidates_sim() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)

	var res: Dictionary = session.apply_edit(_boundary_ref(1), 15)
	_assert_eq(res.get("before_raw", -1), 10, "the pristine boundary (10) is recorded for undo")
	_assert_eq(res.get("after_raw", -1), 15, "the applied boundary comes back")
	_assert_eq(res.get("invalidates_sim", false), true, "particles are born during the sim → re-fold")
	_assert_eq(res.get("relayout", false), true, "a boundary move reshapes the lane → relayout")


## SHRINK: dragging span 1's edge from 10 down to 4 widens the adjacent gap [4,20).
func _test_shrink_widens_the_adjacent_gap() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(1), 4)
	_assert_eq(int(ch.keyframes[1].time), 4, "span 1 shrank; the gap absorbed the vacated space")
	_assert_eq(int(ch.keyframes[2].time), 20, "the gap's far edge is untouched — nothing downstream moved")


## SHRINK floor: the span keeps at least 1 frame — dragging to/past the previous boundary
## clamps to prev+1, never to zero-width and never an implicit delete.
func _test_shrink_clamps_to_a_one_frame_floor_above_prev() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(1), 0)   # onto the previous boundary
	_assert_eq(int(ch.keyframes[1].time), 1, "shrink clamps to a 1-frame floor above the previous boundary")


## GROW against a DRAWN wall: span 2 [10,20) is drawn and flush after span 1. There is no gap
## to consume, so the edge cannot grow (structural insert lands in slice 4).
func _test_grow_against_a_drawn_wall_is_frozen() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2]])   # max_kf 2, span 2 drawn+flush
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(1), 18)
	_assert_eq(int(ch.keyframes[1].time), 10, "grow is frozen — no gap, a drawn neighbour is a wall")


## SHRINK against a DRAWN neighbour: shrinking span 1 would WIDEN the drawn span 2, which the
## invariant forbids — so it AUTO-OPENS a null span in the vacated space (slice 4 structural),
## leaving the neighbour's extent untouched. (Full structural coverage: ParticleTimelineStructuralTest.)
func _test_shrink_against_a_drawn_neighbour_auto_opens_a_gap() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(1), 4)
	_assert_eq(int(ch.keyframes[1].time), 4, "span 1 shrinks — the vacated space becomes a null span")
	_assert_eq(int(ch.keyframes[3].time), 20, "the drawn neighbour keeps its extent (never stretched)")


## The TAIL span (n == max_keyframe) has nothing downstream to pin, so it grows freely.
func _test_tail_span_grows_freely() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_boundary_ref(3), 100)   # span 3 is the last keyframe
	_assert_eq(int(ch.keyframes[3].time), 100, "the tail span extends freely")


## The first span's start is the phase origin (kf[0]), pinned at 0 — its boundary is never
## editable, so an edit addressed at index 0 is refused (no keyframe write).
func _test_origin_boundary_is_refused() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_boundary_ref(0), 5)
	_assert_true(res.is_empty(), "the pinned origin boundary is refused")
	_assert_eq(int(ch.keyframes[0].time), 0, "kf[0].time stays pinned at 0")


## A whole drag (many per-frame boundary edits under one coalesce bracket) collapses to ONE
## undo that restores the pristine boundary.
func _test_a_whole_drag_coalesces_to_one_undo() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _boundary_ref(1)
	session.begin_coalesce(ref)
	session.apply_edit(ref, 6)
	session.apply_edit(ref, 15)
	session.apply_edit(ref, 12)
	session.end_coalesce()

	_assert_true(session.undo(), "the coalesced drag is one undo")
	_assert_eq(int(ch.keyframes[1].time), 10, "one undo restores the pristine boundary")
	_assert_true(not session.undo(), "there is nothing more to undo — the whole drag was one entry")


# --- fixtures -------------------------------------------------------------

func _boundary_ref(index: int) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0,
		"event_index": index, "field": "boundary_end"}


func _chan(data):
	return data.timeline.get_channels("for_each")[0]


## Build a one-channel timeline from a list of [time, emitter_id] pairs.
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
