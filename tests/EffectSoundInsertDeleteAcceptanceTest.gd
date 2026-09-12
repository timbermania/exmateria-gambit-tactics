extends Node
## HEADFUL acceptance guard for the ADD / DELETE sound trigger-event gesture end-to-end.
## Drives the REAL EffectViewer scene → EffectStudioPage._run_lane_verb → host
## EffectViewerScene.studio_insert_event / studio_delete_event → EffectEditSession →
## SoundChannel, on a real extracted effect. Confirms the whole path an author's
## right-click drives:
##   * the resolver's Add action splits the containing gap at the phase-local cursor
##     frame (a silent sound_id-0 seed) with every other fire pinned,
##   * the host survives the re-fold and the selection lands on the new event,
##   * the inverse Delete restores the channel's exact gap bytes,
##   * a LOOSE near-miss click beside the marker selects instead of scrubbing (task 1,
##     live wiring).
## The pure verbs / resolver / undo / hit-test are guarded headless
## (EffectSoundInsertDeleteTest / EffectStudioLaneContextMenuTest /
## EffectScoreTimelineTest); this is the live wiring.
##
## Kept OUT of run_all_tests.sh (needs the gitignored EFFECT extract; camera precedent).
## Run: <GODOT> --path . --quit-after 120 res://tests/EffectSoundInsertDeleteAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_add_then_delete_a_sound_event_on_a_real_effect()

	print("\n=== EffectSoundInsertDeleteAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSoundInsertDeleteAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSoundInsertDeleteAcceptanceTest")
		get_tree().quit(0)


func _test_add_then_delete_a_sound_event_on_a_real_effect() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	# The first candidate effect carrying a sound event with a splittable gap (≥2
	# frames) and a free native slot. E001 (Cure) qualifies; fall through just in case.
	var span := {}
	for suffix in ["E001", "E019", "E024", "E317"]:
		var dir := ""
		for d in page._effect_dirs:
			if String(d).ends_with(suffix):
				dir = d
		if dir == "":
			continue
		page._load_effect(dir)
		await _frames(20)
		span = _splittable_sound_event_span(page)
		if not span.is_empty():
			break
	if span.is_empty():
		print("[SKIP] no extracted effect with a splittable sound gap — acceptance skipped")
		return

	var phase := String(span.get("phase", ""))
	var ci := int(span.get("channel_index", 0))
	var idx := int(span.get("keyframe_index", 0))
	var ch: Dictionary = page._effect_data.sound[phase][ci]
	var gaps_before: Array = _gaps(ch)
	var max_before: int = int(ch["max_keyframe"])

	# Task 1 live wiring: a near-miss 6px LEFT of the marker's select rect selects the
	# trigger (any inspect intent) instead of scrubbing the playhead.
	var rect := _span_rect(page._timeline, String(span["id"]))
	if rect != Rect2():
		var near = page._timeline.hit_test(
			Vector2(rect.position.x - 6.0, rect.position.y + rect.size.y * 0.5))
		_assert_true(near.get("kind", "") != "seek",
			"a 6px near-miss beside a real marker no longer scrubs (kind %s)" % str(near.get("kind", "")))

	page._timeline.select_span(String(span["id"]))
	page._on_span_selected(String(span["id"]))
	await _frames(2)

	# The gesture: right-click the GAP one frame right of the marker (empty lane space —
	# sound's add surface) → the lane-level Add → run through the host.
	var cursor_abs: int = int(span["start"]) + 1
	var local_frame: int = int(span["authored_start"]) + 1
	var lane: Dictionary = page._find_lane(page._timeline._score, String(span["lane_id"]))
	var add := _verb(page._gap_context_actions(lane, cursor_abs), "insert")
	if add.is_empty():
		_fail("gap resolver offered an Add action on the sound lane")
		return
	page._run_lane_verb(add)
	await _frames(6)

	var live: Dictionary = page._effect_data.sound[phase][ci]
	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying")
	_assert_eq(int(live["max_keyframe"]), max_before + 1, "Add grew the live window by one")
	_assert_eq(int(live["keyframes"][idx + 1]["sound_id"]), 0,
		"the new event is the honest silent seed (sound_id 0)")
	_assert_eq(int(live["keyframes"][idx]["duration_frames"])
		+ int(live["keyframes"][idx + 1]["duration_frames"]), int(gaps_before[idx]),
		"the split gaps sum to the original (byte-faithful)")
	var expect_id := "sound:%s:%d#%d" % [phase, ci, idx + 1]
	_assert_eq(page._timeline.selected_span_id(), expect_id,
		"the selection landed on the new sound event")

	# The inverse: right-click the new event → Delete → the exact gap bytes return.
	var new_span := Model.find_span(page._timeline._score, expect_id)
	if new_span.is_empty():
		_fail("re-found the new sound event span for deletion")
		return
	var del := _verb(page._lane_context_actions(new_span, cursor_abs), "delete")
	page._run_lane_verb(del)
	await _frames(6)

	var after: Dictionary = page._effect_data.sound[phase][ci]
	_assert_eq(int(after["max_keyframe"]), max_before, "Delete restored the live window")
	_assert_eq(_gaps(after), gaps_before, "Delete restored the exact gap bytes")


# --- helpers ----------------------------------------------------------------

## First sound EVENT span whose own gap is ≥2 frames (room for a non-degenerate split)
## on a channel with a free native slot (terminator not in the last slot).
func _splittable_sound_event_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "sound":
			continue
		for sp in lane.get("spans", []):
			if String(sp.get("role", "")) != "event":
				continue
			var phase := String(sp.get("phase", ""))
			var ci := int(sp.get("channel_index", 0))
			var idx := int(sp.get("keyframe_index", 0))
			var ch: Dictionary = page._effect_data.sound[phase][ci]
			if int(ch["max_keyframe"]) + 1 >= ch["keyframes"].size():
				continue   # no free slot
			if int(ch["keyframes"][idx].get("duration_frames", 0)) >= 2:
				return sp
	return {}


func _gaps(ch: Dictionary) -> Array:
	var out: Array = []
	for kf in ch["keyframes"]:
		out.append(int(kf.get("duration_frames", 0)))
	return out


func _span_rect(tl, span_id: String) -> Rect2:
	for hit in tl._span_rects:
		if hit["span"]["id"] == span_id:
			return hit["rect"]
	return Rect2()


func _verb(actions: Array, verb: String) -> Dictionary:
	for a in actions:
		if String(a.get("verb", "")) == verb:
			return a
	return {}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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


func _fail(label: String) -> void:
	_failed += 1
	print("[FAIL] %s" % label)
