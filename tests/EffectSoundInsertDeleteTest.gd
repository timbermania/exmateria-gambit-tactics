extends Node
## TDD guard for the ADD / DELETE sound trigger-event verbs (the third instance of the
## ADR-0086/0087 span-lane verbs; sound usability follow-up to #289b). Sound is
## LENGTH-encoded — a keyframe's `duration_frames` is the GAP to the next trigger, so a
## trigger's fire frame is the prefix sum. The verbs keep that arithmetic byte-faithful:
##
##   • insert at frame F = split the CONTAINING gap in TIME — two gaps summing to the
##     original, so every OTHER trigger's fire frame is untouched. Seed `sound_id = 0`
##     (the honest silent no-op — 0/1 = skip); the author picks the sound after.
##   • delete event j = merge its gap into the PREDECESSOR's (the inverse), so every
##     later fire frame is untouched. Deleting the FIRST event has no predecessor: the
##     successor absorbs the gap (everything from the second-next fire onward is pinned).
##
## Capacity is the channel's NATIVE slot budget = its keyframes array length (the
## byte-exact writer serializes exactly that many slots: 9 outer / 17 for-each). The
## verbs REPLACE `data.sound[phase][ci]` with a new channel dict (never mutate the old
## one) so the EffectEditSession snapshot undo can stash the pre-edit object (slice 3).
##
## Seam: SoundChannel.insert_event / delete_event — the sound encoder statics, which
## the #255 EffectEditSession choke point delegates to.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectSoundInsertDeleteTest.tscn

const SoundChannel = preload("res://src/effects/studio/SoundChannel.gd")
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_insert_splits_the_containing_gap_pinning_every_other_fire()
	_test_insert_replaces_the_channel_dict_for_snapshot_undo()
	_test_insert_clamps_a_frame_past_the_terminator_into_the_last_gap()
	_test_insert_refuses_when_the_native_slots_are_full()
	_test_delete_merges_the_gap_into_the_predecessor()
	_test_delete_the_first_event_lets_the_successor_absorb_its_gap()
	_test_delete_the_sole_event_empties_the_channel()
	_test_delete_refuses_the_terminator_and_out_of_window_indices()
	_test_session_routes_sound_verbs_and_undo_restores_the_exact_channel()
	_test_session_records_nothing_for_a_refused_verb()

	print("\n=== EffectSoundInsertDeleteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSoundInsertDeleteTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSoundInsertDeleteTest")
		get_tree().quit(0)


# --- Insert -----------------------------------------------------------------

## Fixture: gaps 14/11/16 (events fire at LOCAL 0, 14, 25; terminator at 41), one free
## padding slot. Insert at local frame 20 — inside event #1's gap [14, 25) — must split
## it 6 + 5 (sum 11, worked by hand: 20−14 / 25−20): event #1 keeps its fire at 14, the
## new silent event fires at 20, the old event #2 still fires at 25 and the terminator
## still caps at 41. Selection lands on the new event (ordinal 2).
func _test_insert_splits_the_containing_gap_pinning_every_other_fire() -> void:
	var data = _data_with_three_events()

	var res: Dictionary = SoundChannel.insert_event(data, _ref({"frame": 20}))

	_assert_eq(res.get("structural", false), true, "an insert restructures (host re-projects)")
	_assert_eq(res.get("ordinal", -1), 2, "selection lands on the new event (index 2)")

	var ch: Dictionary = data.sound["for_each"][0]
	_assert_eq(int(ch["max_keyframe"]), 4, "the live window grew by one")
	_assert_eq(ch["keyframes"].size(), 5, "the native slot count is unchanged (padding absorbed)")
	_assert_eq(_gaps(ch, 5), [14, 6, 5, 16, 544], "the split gaps 6+5 sum to the original 11")
	_assert_eq(int(ch["keyframes"][2]["sound_id"]), 0, "the seed is the honest silent no-op (0 = skip)")
	_assert_eq(_fires(ch), [0, 14, 20, 25], "every pre-existing fire frame is pinned; the new one at 20")


## The verbs REPLACE the channel dict (never mutate in place) — the pre-edit object is
## the EffectEditSession's snapshot, so it must survive the edit untouched.
func _test_insert_replaces_the_channel_dict_for_snapshot_undo() -> void:
	var data = _data_with_three_events()
	var before = data.sound["for_each"][0]

	SoundChannel.insert_event(data, _ref({"frame": 20}))

	_assert_eq(int(before["max_keyframe"]), 3, "the pre-edit channel dict is untouched (the undo snapshot)")
	_assert_eq(before["keyframes"].size(), 5, "…including its keyframes array")
	_assert_eq(int(before["keyframes"][1]["duration_frames"]), 11, "…and its gap bytes")
	_assert_true(not is_same(before, data.sound["for_each"][0]),
		"the live slot now holds a NEW channel dict")


## A frame at/past the terminator (or before 0) has no containing gap — clamp it into
## the nearest end of the live window. Frame 100 clamps to terminator−1 = 40, splitting
## event #2's gap [25, 41) into 15 + 1.
func _test_insert_clamps_a_frame_past_the_terminator_into_the_last_gap() -> void:
	var data = _data_with_three_events()

	var res: Dictionary = SoundChannel.insert_event(data, _ref({"frame": 100}))

	_assert_eq(res.get("ordinal", -1), 3, "the clamped insert lands in the last gap (index 3)")
	var ch: Dictionary = data.sound["for_each"][0]
	_assert_eq(_gaps(ch, 5), [14, 11, 15, 1, 544], "the last gap splits 15+1 at the clamped frame 40")
	_assert_eq(_fires(ch), [0, 14, 25, 40], "the new event fires at the clamped frame")


## With the terminator already in the LAST native slot there is no free padding to
## absorb — the insert must refuse (mirror the camera writer's raise-over-cap: never
## silently drop a byte) and leave the channel untouched.
func _test_insert_refuses_when_the_native_slots_are_full() -> void:
	var data = _data_at_capacity()
	var before = data.sound["for_each"][0]

	var res: Dictionary = SoundChannel.insert_event(data, _ref({"frame": 5}))

	_assert_eq(res.is_empty(), true, "a full channel refuses the insert")
	_assert_true(is_same(before, data.sound["for_each"][0]), "…and the channel is untouched")


# --- Delete -----------------------------------------------------------------

## Delete event #1 (gap 11): its gap merges into event #0's (14+11 = 25), so the old
## event #2 (now #1) still fires at 25 and the terminator still caps at 41. Selection
## falls to the previous neighbour (ordinal 0). The freed slot returns as padding.
func _test_delete_merges_the_gap_into_the_predecessor() -> void:
	var data = _data_with_three_events()

	var res: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": 1}))

	_assert_eq(res.get("structural", false), true, "a delete restructures (host re-projects)")
	_assert_eq(res.get("ordinal", -1), 0, "selection falls to the previous neighbour")
	var ch: Dictionary = data.sound["for_each"][0]
	_assert_eq(int(ch["max_keyframe"]), 2, "the live window shrank by one")
	_assert_eq(ch["keyframes"].size(), 5, "the native slot count is unchanged (padding restored)")
	_assert_eq(_gaps(ch, 3), [25, 16, 544], "the deleted gap merged into the predecessor (14+11)")
	_assert_eq(_fires(ch), [0, 25], "every later fire frame is pinned")


## Deleting the FIRST event has no predecessor gap to merge into: the successor absorbs
## it (its own gap grows by the deleted one), so everything from the second-next fire
## onward stays pinned — the successor necessarily takes over the channel start.
func _test_delete_the_first_event_lets_the_successor_absorb_its_gap() -> void:
	var data = _data_with_three_events()

	var res: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": 0}))

	_assert_eq(res.get("ordinal", -1), 0, "selection lands on the new first event")
	var ch: Dictionary = data.sound["for_each"][0]
	_assert_eq(_gaps(ch, 3), [25, 16, 544], "the successor absorbed the deleted gap (11+14)")
	_assert_eq(_fires(ch), [0, 25], "the second-next fire (25) and the terminator (41) stay pinned")


## Deleting the only event empties the channel: max_keyframe 0 projects no spans (and
## no lone terminator). Selection has nowhere to land (ordinal −1).
func _test_delete_the_sole_event_empties_the_channel() -> void:
	var data = _data_with_one_event()

	var res: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": 0}))

	_assert_eq(res.get("ordinal", -1), -1, "no neighbour to select in an emptied channel")
	var ch: Dictionary = data.sound["for_each"][0]
	_assert_eq(int(ch["max_keyframe"]), 0, "the channel is empty")
	_assert_eq(ch["keyframes"].size(), 3, "the native slot count is unchanged")


## The terminator end-cap is NOT an event — its slot's bytes are the last event's gap;
## deleting it would be two-verbs-one-byte. Out-of-window indices refuse too, leaving
## the channel untouched.
func _test_delete_refuses_the_terminator_and_out_of_window_indices() -> void:
	var data = _data_with_three_events()
	var before = data.sound["for_each"][0]

	var at_term: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": 3}))
	_assert_eq(at_term.is_empty(), true, "the terminator (index == max_keyframe) refuses delete")
	var past: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": 9}))
	_assert_eq(past.is_empty(), true, "an out-of-window index refuses delete")
	var neg: Dictionary = SoundChannel.delete_event(data, _ref({"event_index": -1}))
	_assert_eq(neg.is_empty(), true, "a negative index refuses delete")
	_assert_true(is_same(before, data.sound["for_each"][0]), "…and the channel is untouched")


# --- The choke point (slice 3): session dispatch + snapshot undo ------------

## The #255 choke point routes the sound structural verbs and unwinds them with the
## stashed pre-edit channel object — undo restores the EXACT bytes (it IS the pre-edit
## dict, not a replay). Insert then delete then two undos walks back to the origin.
func _test_session_routes_sound_verbs_and_undo_restores_the_exact_channel() -> void:
	var data = _data_with_three_events()
	var origin = data.sound["for_each"][0]
	var session = EffectEditSession.new(data)

	var ins: Dictionary = session.insert_event(_ref({"frame": 20}))
	_assert_eq(ins.get("structural", false), true, "the session routes a sound insert")
	var del: Dictionary = session.delete_event(_ref({"event_index": 0}))
	_assert_eq(del.get("structural", false), true, "the session routes a sound delete")

	_assert_eq(session.undo(), true, "the delete unwinds")
	_assert_eq(_gaps(data.sound["for_each"][0], 5), [14, 6, 5, 16, 544],
		"…restoring the post-insert channel")
	_assert_eq(session.undo(), true, "the insert unwinds")
	_assert_true(is_same(origin, data.sound["for_each"][0]),
		"…restoring the ORIGINAL pre-edit channel object (byte-exact by identity)")
	_assert_eq(session.undo(), false, "nothing left to undo")


## A refused verb (here: at native capacity) records NO undo entry — undoing after it
## must report nothing to undo, not corrupt the stack.
func _test_session_records_nothing_for_a_refused_verb() -> void:
	var data = _data_at_capacity()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.insert_event(_ref({"frame": 5}))

	_assert_eq(res.is_empty(), true, "the refused insert returns empty through the session")
	_assert_eq(session.undo(), false, "…and records no undo entry")


# --- Fixtures ---------------------------------------------------------------

## The shared address: for_each channel 0. Extra keys (frame / event_index) merge in.
func _ref(extra: Dictionary) -> Dictionary:
	var ref := {"channel": "sound", "phase": "for_each", "channel_index": 0}
	ref.merge(extra)
	return ref


## Three events, gaps 14/11/16 (fires at local 0/14/25, terminator at 41), sound_ids
## 2/3/4, one free padding slot after the terminator — 5 native slots, max_keyframe 3.
func _data_with_three_events():
	return _effect_data({
		"for_each": [
			{"channel_index": 0, "max_keyframe": 3, "keyframes": [
				{"duration_frames": 14, "sound_id": 2},
				{"duration_frames": 11, "sound_id": 3},
				{"duration_frames": 16, "sound_id": 4},
				{"duration_frames": 544, "sound_id": 0},
				{"duration_frames": 0, "sound_id": 0}]},
		],
	})


## The terminator occupies the LAST native slot — no padding, insert must refuse.
func _data_at_capacity():
	return _effect_data({
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 10, "sound_id": 2},
				{"duration_frames": 10, "sound_id": 3},
				{"duration_frames": 0, "sound_id": 0}]},
		],
	})


## A single event and its terminator (plus one padding slot) — the sole-event fixture.
func _data_with_one_event():
	return _effect_data({
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 0, "sound_id": 7},
				{"duration_frames": 0, "sound_id": 0}]},
		],
	})


func _effect_data(sound: Dictionary):
	var ed = ExMateriaEffects.EffectData.new()
	ed.sound = sound
	return ed


## The first `n` gaps (duration_frames) of the channel, as a plain Array for _assert_eq.
func _gaps(ch: Dictionary, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(int(ch["keyframes"][i]["duration_frames"]))
	return out


## The LOCAL fire frames of the live events (indices 0..max_keyframe-1) — the prefix sums.
func _fires(ch: Dictionary) -> Array:
	var out: Array = []
	var local := 0
	for i in range(int(ch["max_keyframe"])):
		out.append(local)
		local += int(ch["keyframes"][i]["duration_frames"])
	return out


# --- Assert helpers ---------------------------------------------------------

func _assert_eq(got, expected, msg: String) -> void:
	if typeof(got) == typeof(expected) and got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [msg, str(expected), str(got)])


func _assert_true(cond: bool, msg: String) -> void:
	_assert_eq(cond, true, msg)
