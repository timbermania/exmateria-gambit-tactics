extends Node
## HEADFUL acceptance guard for the screen ADD/DELETE lane verbs end-to-end (ADR-0087, screen
## lane). Drives the REAL EffectViewer scene → EffectStudioPage lane-verb path
## (_lane_context_actions → _run_lane_verb) → host studio_insert_event / studio_delete_event →
## EffectEditSession → ScreenChannel, on real E015 (the screen-authoring pilot effect).
## Confirms the whole path an author's right-click drives:
##   * Add tween here inserts an ACTIVE IDENTITY no-op tween (Blend mode 0, zero param —
##     screen has no enable bit) splitting the covering span in time,
##   * the effect re-folds without dying,
##   * Delete tween removes it and merges the length back,
##   * one undo per verb restores the keyframe set.
## Pure verb logic (split/merge/snapshot-undo) is guarded headless (ScreenInsertDeleteTest);
## this is the live wiring on real bytes.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E015 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectScreenInsertDeleteAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_insert_delete_on_real_E015()

	print("\n=== EffectScreenInsertDeleteAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScreenInsertDeleteAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScreenInsertDeleteAcceptanceTest")
		get_tree().quit(0)


func _test_insert_delete_on_real_E015() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E015"):
			dir = d
	if dir == "":
		print("[SKIP] E015 extract absent — screen insert/delete acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# Any screen span with ≥ 16 frames of room (so a mid-span insert splits cleanly).
	var span := _roomy_screen_span(page)
	if span.is_empty():
		print("[SKIP] no roomy screen span on E015 — insert/delete acceptance skipped")
		return
	var phase: String = String(span.get("phase", ""))
	var ch = scn._current_effect.effect_data.screen.get_channel(phase)
	var before_count: int = ch.keyframes.size()
	var kf_index: int = int(span.get("keyframe_index", -1))
	var mid_abs: int = int((int(span.get("start", 0)) + int(span.get("end", 0))) / 2)

	# --- Add: run the insert verb from the context menu at the span's midpoint ------------
	var actions: Array = page._lane_context_actions(span, mid_abs)
	_assert_eq(actions.size(), 2, "the screen span offers Add + Delete")
	page._run_lane_verb(actions[0])
	await _frames(6)

	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying after insert")
	_assert_eq(ch.keyframes.size(), before_count + 1, "Add inserted one keyframe")
	var seed = ch.keyframes[kf_index + 1]
	_assert_eq(int(seed.ctrl), 0x80, "the inserted tween is the ACTIVE identity no-op (Blend mode 0)")
	_assert_eq([int(seed.start_r_raw), int(seed.start_g_raw), int(seed.start_b_raw)], [0, 0, 0],
		"…with a zero param (current + 0)")

	# Save round-trips the COUNT CHANGE: the live channel now has 34 keyframes; the shape
	# bridge (EffectScreenSaver.to_screen_json) must pad/truncate to the writer's fixed 33
	# slots — before it, the writer silently truncated on 34 and crashed on 32.
	var save_res: Dictionary = scn.studio_save()
	_assert_eq(save_res.get("ok", false), true,
		"Save succeeds after the insert (34 live keyframes bridged to the 33-slot writer): %s"
			% String(save_res.get("error", "")))

	# One undo restores the pre-insert keyframe set.
	page._undo()
	await _frames(4)
	_assert_eq(ch.keyframes.size(), before_count, "one undo removes the inserted tween")

	# --- Delete: run the delete verb on the picked keyframe -------------------------------
	var del_actions: Array = page._lane_context_actions(span, mid_abs)
	page._run_lane_verb(del_actions[1])
	await _frames(6)
	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying after delete")
	_assert_eq(ch.keyframes.size(), before_count - 1, "Delete removed the keyframe")

	page._undo()
	await _frames(4)
	_assert_eq(ch.keyframes.size(), before_count, "one undo restores the deleted keyframe")


# --- helpers ----------------------------------------------------------------

func _roomy_screen_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			if int(sp.get("end", 0)) - int(sp.get("start", 0)) >= 16:
				return sp
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
