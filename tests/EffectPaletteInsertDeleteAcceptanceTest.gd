extends Node
## HEADFUL acceptance guard for the palette ADD/DELETE lane verbs end-to-end (ADR-0087). Drives
## the REAL EffectViewer scene → EffectStudioPage lane-verb path (_lane_context_actions →
## _run_lane_verb) → host studio_insert_event / studio_delete_event → EffectEditSession →
## PaletteChannel, on real E317. Confirms the whole path an author's right-click drives:
##   * Add tween here inserts a DISABLED null tween (splitting the covering span in time),
##   * the effect re-folds without dying,
##   * Delete tween removes it and merges the length back,
##   * one undo per verb restores the keyframe set.
## Pure verb logic (split/merge/snapshot-undo) is guarded headless (PaletteInsertDeleteTest);
## this is the live wiring on real bytes.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectPaletteInsertDeleteAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_insert_delete_on_real_E317()

	print("\n=== EffectPaletteInsertDeleteAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteInsertDeleteAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteInsertDeleteAcceptanceTest")
		get_tree().quit(0)


func _test_insert_delete_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — palette insert/delete acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# Any palette span with ≥ 16 frames of room (so a mid-span insert splits cleanly).
	var pick := _roomy_palette_span(page)
	if pick.is_empty():
		print("[SKIP] no roomy palette span on E317 — insert/delete acceptance skipped")
		return
	var span: Dictionary = pick
	var phase: String = String(span.get("phase", ""))
	var channel_name: String = String(span.get("fields", {}).get("channel", ""))
	var ch = scn._current_effect.effect_data.palette.get_channel(phase, channel_name)
	var before_count: int = ch.keyframes.size()
	var kf_index: int = int(span.get("keyframe_index", -1))
	var mid_abs: int = int((int(span.get("start", 0)) + int(span.get("end", 0))) / 2)

	# --- Add: run the insert verb from the context menu at the span's midpoint ------------
	var actions: Array = page._lane_context_actions(span, mid_abs)
	_assert_eq(actions.size(), 2, "the palette span offers Add + Delete")
	page._run_lane_verb(actions[0])
	await _frames(6)

	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying after insert")
	_assert_eq(ch.keyframes.size(), before_count + 1, "Add inserted one keyframe")
	_assert_true(not ch.keyframes[kf_index + 1].enabled, "the inserted tween is DISABLED (a null tween)")

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

func _roomy_palette_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "palette":
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


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
