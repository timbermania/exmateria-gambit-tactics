extends Node
## TDD guard for the particle-timeline STRUCTURAL verbs (ADR-0089 particle_timeline amendment,
## slice 4) — Add / Delete, plus the structural completions of Resize (shrink-auto-gap and
## grow-reclaim). All go through the choke point with SNAPSHOT undo (the channel deep-copy),
## so a boundary edit that turns structural mid-drag still unwinds cleanly.
##
## Add: split the covering window, new keyframe born disabled + remembered (drawn dimmed).
## Refuse at 25 slots. Delete: remove a keyframe; the next span merges over the freed window
## (downstream pinned). Shrink against a DRAWN wall auto-opens a null span (neighbour keeps its
## extent). Grow consuming a gap to zero width reclaims the slot.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleTimelineStructuralTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_add_splits_a_gap_into_a_born_disabled_span()
	_test_add_seeds_the_nearest_previous_drawn_emitter()
	_test_add_at_the_tail_appends_a_disabled_span()
	_test_add_refuses_a_full_channel()
	_test_delete_merges_the_window_downstream_pinned()
	_test_delete_refuses_the_origin()
	_test_shrink_against_a_drawn_wall_auto_opens_a_null_span()
	_test_grow_consuming_a_gap_to_zero_reclaims_the_slot()
	_test_structural_boundary_edit_undoes_by_snapshot()
	_test_add_and_delete_undo_by_snapshot()
	_test_a_drag_mixing_scalar_and_structural_is_one_undo()

	print("\n=== ParticleTimelineStructuralTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleTimelineStructuralTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleTimelineStructuralTest")
		get_tree().quit(0)


## Add at frame 20 inside the gap [10,30) splits it: a new BORN-DISABLED keyframe takes the
## second half, the gap keeps the first — sim output is unchanged (both gaps/disabled).
func _test_add_splits_a_gap_into_a_born_disabled_span() -> void:
	var data := _fake_data([[0, 0], [10, 1], [30, 0]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.insert_event(_add_ref(20))
	_assert_eq(res.get("structural", false), true, "Add is structural")
	_assert_eq(int(res.get("event_index", -1)), 3, "the new keyframe lands after the split")
	_assert_eq(ch.keyframes.size(), 4, "the keyframe array grew by one")
	_assert_eq(int(ch.max_keyframe), 3, "the watermark advanced")
	_assert_eq(int(ch.keyframes[2].time), 20, "the covering gap keeps the first half [10,20)")
	_assert_eq(int(ch.keyframes[3].emitter_id), 0, "the new keyframe is born disabled (a real gap)")
	_assert_eq(int(ch.keyframes[3].time), 30, "…owning the second half up to the old boundary")


## The born-disabled keyframe REMEMBERS the nearest previous drawn emitter, so it draws dimmed
## and re-enables to a sensible target.
func _test_add_seeds_the_nearest_previous_drawn_emitter() -> void:
	var data := _fake_data([[0, 0], [10, 3], [30, 0]])   # nearest previous drawn is emitter id 3
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_add_ref(20))
	_assert_eq(int(ch.keyframes[3].remembered_emitter_id), 3, "the new span remembers the nearest previous drawn emitter")


## Add past the last keyframe appends a disabled span at the tail.
func _test_add_at_the_tail_appends_a_disabled_span() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.insert_event(_add_ref(50))
	_assert_eq(ch.keyframes.size(), 3, "a tail Add appends a keyframe")
	_assert_eq(int(ch.keyframes[2].time), 50, "…at the requested frame")
	_assert_eq(int(ch.keyframes[2].emitter_id), 0, "…born disabled")
	_assert_eq(int(res.get("event_index", -1)), 2, "…selected by its new index")


## A full channel (25 used slots) refuses Add — raise, never truncate.
func _test_add_refuses_a_full_channel() -> void:
	var pairs: Array = []
	for i in range(25):
		pairs.append([i * 10, (i % 2)])   # 25 keyframes → max_keyframe 24, used = 25
	var data := _fake_data(pairs)
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.insert_event(_add_ref(5))
	_assert_true(res.is_empty(), "Add on a full channel is refused")
	_assert_eq(ch.keyframes.size(), 25, "…the array is untouched")


## Delete removes a span; because time is absolute, the NEXT span merges over the freed window
## and everything downstream stays pinned at its frame.
func _test_delete_merges_the_window_downstream_pinned() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2], [30, 3]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.delete_event(_del_ref(2))   # delete the middle drawn span
	_assert_eq(res.get("structural", false), true, "Delete is structural")
	_assert_eq(ch.keyframes.size(), 3, "the array shrank by one")
	_assert_eq(int(ch.max_keyframe), 2, "the watermark dropped")
	_assert_eq(int(ch.keyframes[2].time), 30, "the downstream boundary stays pinned at 30")
	_assert_eq(int(ch.keyframes[2].emitter_id), 3, "…and the next span (id 3) merged over the freed window")


func _test_delete_refuses_the_origin() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.delete_event(_del_ref(0))
	_assert_true(res.is_empty(), "deleting the pinned origin is refused")
	_assert_eq(ch.keyframes.size(), 2, "…the array is untouched")


## SHRINK against a DRAWN neighbour auto-opens a null span filling the vacated space — the
## neighbour keeps its extent, never stretched.
func _test_shrink_against_a_drawn_wall_auto_opens_a_null_span() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2]])   # span 2 drawn + flush
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_bnd_ref(1), 4)
	_assert_eq(res.get("structural", false), true, "shrink-against-a-wall is structural")
	_assert_eq(ch.keyframes.size(), 4, "a null span was inserted")
	_assert_eq(int(ch.keyframes[1].time), 4, "span 1 shrank to 4")
	_assert_eq(int(ch.keyframes[2].emitter_id), 0, "…an auto-opened gap fills [4,10)")
	_assert_eq(int(ch.keyframes[2].remembered_emitter_id), 0, "…a PURE gap (nothing remembered)")
	_assert_eq(int(ch.keyframes[3].time), 20, "the drawn neighbour keeps its extent [10,20)")
	_assert_eq(int(ch.keyframes[3].emitter_id), 2, "…undisturbed")


## GROW consuming a gap to zero width reclaims the freed slot.
func _test_grow_consuming_a_gap_to_zero_reclaims_the_slot() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 0], [30, 2]])   # gap [10,20)
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.apply_edit(_bnd_ref(1), 25)   # grow past the gap's far edge
	_assert_eq(res.get("structural", false), true, "grow-to-zero reclaim is structural")
	_assert_eq(ch.keyframes.size(), 3, "the zero-width gap slot was reclaimed")
	_assert_eq(int(ch.keyframes[1].time), 20, "span 1 grew to the reclaimed boundary")
	_assert_eq(int(ch.keyframes[2].time), 30, "the downstream drawn span stays pinned")
	_assert_eq(int(ch.keyframes[2].emitter_id), 2, "…undisturbed")


## A boundary edit that turns structural still undoes by snapshot — the whole channel comes back.
func _test_structural_boundary_edit_undoes_by_snapshot() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.apply_edit(_bnd_ref(1), 4)   # shrink-auto-gap (structural)
	_assert_true(session.undo(), "the structural boundary edit is undoable")
	_assert_eq(ch.keyframes.size(), 3, "undo restores the array length")
	_assert_eq(int(ch.keyframes[1].time), 10, "…span 1's boundary")
	_assert_eq(int(ch.max_keyframe), 2, "…and the watermark")


func _test_add_and_delete_undo_by_snapshot() -> void:
	var data := _fake_data([[0, 0], [10, 1], [30, 0]])
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_add_ref(20))
	_assert_true(session.undo(), "Add is undoable")
	_assert_eq(ch.keyframes.size(), 3, "undo removes the added keyframe")
	_assert_eq(int(ch.max_keyframe), 2, "…and restores the watermark")

	session.delete_event(_del_ref(1))
	_assert_true(session.undo(), "Delete is undoable")
	_assert_eq(ch.keyframes.size(), 3, "undo restores the deleted keyframe")


## A single drag that starts scalar and turns structural (shrink into a wall) is ONE undo.
func _test_a_drag_mixing_scalar_and_structural_is_one_undo() -> void:
	var data := _fake_data([[0, 0], [10, 1], [20, 2]])
	var session = Session.new(data)
	var ch = _chan(data)

	var ref := _bnd_ref(1)
	session.begin_coalesce(ref)
	session.apply_edit(ref, 4)   # shrink-auto-gap (structural) — captures the pristine snapshot
	session.apply_edit(ref, 3)   # further shrink into the now-gap neighbour (scalar)
	session.end_coalesce()

	_assert_true(session.undo(), "the whole drag is one undo")
	_assert_eq(ch.keyframes.size(), 3, "one undo restores the pristine array")
	_assert_eq(int(ch.keyframes[1].time), 10, "…and the boundary")
	_assert_true(not session.undo(), "there is nothing more to undo")


# --- fixtures -------------------------------------------------------------

func _add_ref(frame: int) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0, "frame": frame}


func _del_ref(index: int) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0, "event_index": index}


func _bnd_ref(index: int) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0,
		"event_index": index, "field": "boundary_end"}


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
