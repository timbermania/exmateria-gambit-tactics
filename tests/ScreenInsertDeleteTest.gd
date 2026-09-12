extends Node
## TDD guard for the screen ADD/DELETE lane verbs (ADR-0087, screen lane) — the span-lane
## verbs generalised from camera (ADR-0086) and palette to the length-encoded SCREEN channel.
## INSERT-WAYPOINT cuts a covering span in TIME, seeding the new keyframe as an ACTIVE
## IDENTITY no-op tween — screen has no `enabled` bit, so the null-tween seed is the Blend
## mode-0 zero-param keyframe (ctrl 0x80, start RGB 0): ColorRecipe lowers it to
## `affine(ONE, ZERO)` = current + 0, a per-frame visual no-op over ANY covering variant
## (copying the covering Blend's param would apply its op twice — the Δ-inherit trap; a
## Gradient copy would absolute-set). DELETE merges the removed span's length into a
## neighbour so downstream stays pinned. Screen keeps its raw `event_index` (no ordinal),
## and the whole verb rides SNAPSHOT undo through the EffectEditSession choke point.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScreenInsertDeleteTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const ScreenDataClass = ExMateriaEffects.ScreenData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_insert_splits_a_span_seeding_an_identity_noop_tween()
	_test_insert_lands_the_cut_nearest_the_click_without_drift()
	_test_insert_into_an_eight_frame_span_slivers_toward_the_click()
	_test_insert_is_structural_and_undoes()
	_test_spacer_stub_brackets_a_born_disabled_stub()
	_test_spacer_stub_is_structural_and_undoes()
	_test_delete_merges_into_the_previous_neighbour()
	_test_delete_of_the_first_merges_into_the_next()
	_test_delete_is_structural_and_undoes()
	_test_lane_context_actions_offer_screen_add_and_delete()

	print("\n=== ScreenInsertDeleteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScreenInsertDeleteTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenInsertDeleteTest")
		get_tree().quit(0)


## Inserting at frame 8 inside span 0 [0,16) cuts it: span 0 becomes [0,8) and a NEW identity
## no-op tween takes [8,16). Downstream keyframes keep their lengths; the far edge is
## preserved; max_keyframe grows so the played window covers the new keyframe.
func _test_insert_splits_a_span_seeding_an_identity_noop_tween() -> void:
	var data := _fake_data([2, 2, 2])   # durations 16/16/16
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.insert_event(_insert_ref(8))
	_assert_eq(ch.keyframes.size(), 4, "insert adds one keyframe")
	_assert_eq(int(ch.keyframes[0].time_value), 1, "the cut span 0 shrinks to [0,8) (tv 1)")
	_assert_eq(int(ch.keyframes[1].time_value), 1, "the inserted tween takes [8,16) (tv 1)")
	_assert_eq(int(ch.keyframes[1].mode), ScreenDataClass.ScreenMode.BLEND,
		"the inserted tween is a Blend (ctrl bit-7 set — an ACTIVE keyframe, screen has no enable bit)")
	_assert_eq(int(ch.keyframes[1].ctrl), 0x80, "…mode 0 in ctrl bits 0-6 (the identity op)")
	_assert_eq(int(ch.keyframes[1].blend_mode), 0, "…blend mode 0 (current + delta)")
	_assert_eq([int(ch.keyframes[1].start_r_raw), int(ch.keyframes[1].start_g_raw),
		int(ch.keyframes[1].start_b_raw)], [0, 0, 0],
		"…with a ZERO param: current + 0 = a per-frame visual no-op in any covering variant")
	_assert_eq(int(ch.keyframes[2].time_value), 2, "the old neighbour is untouched downstream")
	_assert_eq(int(ch.keyframes[3].time_value), 2, "…and so is the tail")
	_assert_eq(int(ch.max_keyframe), 5, "max_keyframe grows with the insert (played window follows)")
	_assert_true(res.get("structural", false), "insert is a structural edit")
	_assert_eq(int(res.get("event_index", -1)), 1, "…selecting the newly inserted keyframe (raw index)")


## The cut must land at the nearest STORABLE boundary to the clicked frame, never trading
## closeness for far-edge drift: clicking frame 3 of a [0,24) span (tv 3) takes the clean
## 8+16 split, not a 1-frame sliver that pushes everything downstream.
func _test_insert_lands_the_cut_nearest_the_click_without_drift() -> void:
	var data := _fake_data([3, 2])   # durations 24/16
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_insert_ref(3))
	_assert_eq(int(ch.keyframes[0].time_value), 1, "the cut span shrinks to [0,8) (tv 1, nearest to the click)")
	_assert_eq(int(ch.keyframes[1].time_value), 2, "the inserted tween takes [8,24) (tv 2) — far edge pinned")
	_assert_eq(int(ch.keyframes[2].time_value), 2, "downstream is untouched")


## An 8-frame span has NO clean faithful split (1+8k pairs can't sum to 8), so the cut drifts
## by the minimum one frame, with the sliver on the side nearest the click.
func _test_insert_into_an_eight_frame_span_slivers_toward_the_click() -> void:
	var data := _fake_data([1, 1])   # durations 8/8
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_insert_ref(7))   # near the END of span 0 [0,8)
	_assert_eq(int(ch.keyframes[0].time_value), 1, "the cut span keeps its 8 frames")
	_assert_eq(int(ch.keyframes[1].time_value), 0, "the inserted tween is the 1-frame sliver at the far edge")


func _test_insert_is_structural_and_undoes() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_insert_ref(8))
	_assert_eq(ch.keyframes.size(), 4, "inserted")
	_assert_true(session.undo(), "insert is undoable (snapshot)")
	var ch2 = _chan(data)
	_assert_eq(ch2.keyframes.size(), 3, "undo restores the original keyframe count")
	_assert_eq(int(ch2.keyframes[0].time_value), 2, "…and the original durations")
	_assert_eq(int(ch2.max_keyframe), 4, "…and the original max_keyframe")


## The ADD-INTO-A-SPACER verb (ADR-0087 decs. 23-28): a `spacer_stub` insert cuts the
## covering screen spacer into THREE — [before-spacer | 1-frame BORN-DISABLED stub |
## after-spacer]. The sides KEEP the spacer's original bytes; the middle is born disabled (a
## disabled_stash is present) so it stays drawn+hatched even after deselect (screen has no
## enable bit — the stash IS "a human turned this off"). Selection lands on the stub.
func _test_spacer_stub_brackets_a_born_disabled_stub() -> void:
	var data := _fake_data([2, 2, 2])   # durations 16/16/16, covering kf 0 is a Blend rgb(10,20,30)
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.insert_event(_stub_ref(8))
	_assert_eq(ch.keyframes.size(), 5, "one spacer keyframe becomes three (net +2)")
	_assert_eq(int(ch.keyframes[0].time_value), 1, "the before-spacer takes [0,8) (tv 1)")
	_assert_eq(int(ch.keyframes[0].start_r_raw), 10, "…and KEEPS the spacer's original bytes")
	_assert_eq(int(ch.keyframes[1].time_value), 0, "the stub is a 1-frame tween (tv 0)")
	_assert_true(not ch.keyframes[1].disabled_stash.is_empty(),
		"…born DISABLED (a stash is present) so it stays visible after deselect")
	_assert_eq(int(ch.keyframes[1].start_r_raw), 0, "…its LIVE bytes are the identity no-op")
	_assert_eq(int(ch.keyframes[2].start_r_raw), 10, "the after-spacer keeps the original bytes")
	_assert_eq(int(ch.keyframes[3].time_value), 2, "the next span is untouched")
	_assert_eq(int(ch.keyframes[4].time_value), 2, "…and the tail")
	_assert_true(res.get("structural", false), "the spacer stub insert is structural")
	_assert_eq(int(res.get("event_index", -1)), 1, "…selection lands on the STUB (the middle keyframe)")


func _test_spacer_stub_is_structural_and_undoes() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.insert_event(_stub_ref(8))
	_assert_eq(ch.keyframes.size(), 5, "split into three")
	_assert_true(session.undo(), "the spacer stub insert is one snapshot undo")
	var ch2 = _chan(data)
	_assert_eq(ch2.keyframes.size(), 3, "undo restores the original keyframe count")
	_assert_eq(int(ch2.keyframes[0].time_value), 2, "…and the original durations")


## Deleting a mid keyframe folds its length into the PREVIOUS neighbour, so everything
## downstream stays pinned at its absolute frame.
func _test_delete_merges_into_the_previous_neighbour() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.delete_event(_delete_ref(1))
	_assert_eq(ch.keyframes.size(), 2, "delete removes one keyframe")
	_assert_eq(int(ch.keyframes[0].time_value), 4, "the previous neighbour absorbs the gap (16+16 → tv 4)")
	_assert_eq(int(ch.keyframes[1].time_value), 2, "the tail keeps its position (downstream pinned)")
	_assert_eq(int(ch.max_keyframe), 3, "max_keyframe shrinks with the delete")
	_assert_eq(int(res.get("event_index", -1)), 0, "selection falls to the previous neighbour")


## Deleting the FIRST keyframe (no previous) folds into the NEXT instead.
func _test_delete_of_the_first_merges_into_the_next() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	session.delete_event(_delete_ref(0))
	_assert_eq(ch.keyframes.size(), 2, "delete removes one keyframe")
	_assert_eq(int(ch.keyframes[0].time_value), 4, "the next neighbour absorbs the gap (tv 4)")


func _test_delete_is_structural_and_undoes() -> void:
	var data := _fake_data([2, 2, 2])
	var session = Session.new(data)
	var ch = _chan(data)

	var res: Dictionary = session.delete_event(_delete_ref(1))
	_assert_true(res.get("structural", false), "delete is a structural edit")
	_assert_true(session.undo(), "delete is undoable (snapshot)")
	var ch2 = _chan(data)
	_assert_eq(ch2.keyframes.size(), 3, "undo restores the removed keyframe")
	_assert_eq(int(ch2.keyframes[0].time_value), 2, "…and the neighbour's original length")


## The page context menu offers screen Add + Delete (ADR-0087 generalises the verbs to the
## third colour lane). The cursor frame is score-absolute → phase-local; screen's address is
## 1-D (context only); Delete addresses the raw keyframe index.
func _test_lane_context_actions_offer_screen_add_and_delete() -> void:
	var span := {
		"kind": "screen", "phase": "for_each", "keyframe_index": 1,
		"start": 24, "authored_start": 16,   # offset 8
		"fields": {},
	}
	var actions: Array = Page._lane_context_actions(span, 30)   # abs 30 → local 22
	_assert_eq(actions.size(), 2, "a screen span offers two verbs")
	var ins: Dictionary = actions[0]
	_assert_eq(String(ins.get("verb", "")), "insert", "the first verb inserts")
	_assert_eq(String(ins.get("field_ref", {}).get("channel", "")), "screen", "…on the screen channel")
	_assert_eq(String(ins.get("field_ref", {}).get("context", "")), "for_each", "…the phase context")
	_assert_eq(int(ins.get("field_ref", {}).get("frame", -1)), 22, "…at the offset-corrected local frame")
	var del: Dictionary = actions[1]
	_assert_eq(String(del.get("verb", "")), "delete", "the second verb deletes")
	_assert_eq(int(del.get("field_ref", {}).get("event_index", -1)), 1, "…the raw keyframe index (no ordinal)")


# --- fixtures -------------------------------------------------------------

func _insert_ref(frame: int) -> Dictionary:
	return {"channel": "screen", "context": "for_each", "frame": frame}


func _stub_ref(frame: int) -> Dictionary:
	var r := _insert_ref(frame)
	r["spacer_stub"] = true
	return r


func _delete_ref(index: int) -> Dictionary:
	return {"channel": "screen", "context": "for_each", "event_index": index}


func _chan(data):
	return data.screen.get_channel("for_each")


## Build a screen channel from a list of time_values (durations = tv×8). Alternating
## Blend/Gradient kinds so the verbs are proven variant-agnostic.
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
