extends Node
## HEADFUL acceptance guard for the ADD / DELETE camera lane gesture end-to-end (ADR-0086
## second amendment). Drives the REAL EffectViewer scene → EffectStudioPage._run_lane_verb →
## host EffectViewerScene.studio_insert_event / studio_delete_event → EffectEditSession →
## CameraChannel, on real E317. Confirms the whole path an author's right-click drives:
##   * the resolver's Add action lands a new camera keyframe at the phase-local cursor frame,
##   * the host re-folds the sim without error and the selection lands on the new event,
##   * the inverse Delete restores the lane.
## The pure resolver + verbs + undo are guarded headless (EffectStudioLaneContextMenuTest /
## EffectCameraInsertDeleteTest / EffectCameraStructuralUndoTest); this is the live wiring.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; KindSelector precedent).
## Run: <GODOT> --path . --quit-after 120 res://tests/EffectCameraInsertDeleteAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_add_then_delete_a_camera_waypoint_on_real_E317()

	print("\n=== EffectCameraInsertDeleteAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraInsertDeleteAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraInsertDeleteAcceptanceTest")
		get_tree().quit(0)


func _test_add_then_delete_a_camera_waypoint_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — insert/delete acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# A camera angle span with interior room to cut (authored width ≥ 2 frames).
	var span := _cuttable_camera_angle_span(page)
	if span.is_empty():
		_fail("found a cuttable camera angle span on E317")
		return
	var phase = String(span.get("phase", ""))
	page._timeline.select_span(String(span.get("id", "")))
	page._on_span_selected(String(span.get("id", "")))
	await _frames(2)

	var before_events: int = CameraLowering.parse(page._effect_data.camera.get_table(phase))["angle"].size()

	# The gesture: right-click mid-span → the resolver's Add action → run it through the host.
	var cursor_abs: int = int((float(span["start"]) + float(span["end"])) * 0.5)
	var offset: int = int(span["start"]) - int(span["authored_start"])
	var local_frame: int = cursor_abs - offset
	var add := _verb(page._lane_context_actions(span, cursor_abs), "insert")
	if add.is_empty():
		_fail("resolver offered an Add action")
		return
	page._run_lane_verb(add)
	await _frames(6)

	# The keyframe landed at the phase-local cursor frame, the effect is still folding, and
	# the selection moved to the new event.
	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying")
	var after_add: Array = CameraLowering.parse(page._effect_data.camera.get_table(phase))["angle"]
	_assert_eq(after_add.size(), before_events + 1, "Add grew the angle lane by one event")
	_assert_true(_lane_has_frame(after_add, local_frame),
		"a new angle event exists at the phase-local cursor frame %d" % local_frame)
	_assert_true(page._timeline.selected_span_id().begins_with("camera:%s:angle#" % phase),
		"the selection landed on the new angle event")

	# The inverse: right-click the new waypoint → Delete → the lane is restored.
	var new_span := Model.find_span(page._timeline._score, page._timeline.selected_span_id())
	if new_span.is_empty():
		_fail("re-found the new waypoint span for deletion")
		return
	var del := _verb(page._lane_context_actions(new_span, cursor_abs), "delete")
	page._run_lane_verb(del)
	await _frames(6)

	var after_delete: Array = CameraLowering.parse(page._effect_data.camera.get_table(phase))["angle"]
	_assert_eq(after_delete.size(), before_events, "Delete restored the original angle lane count")
	_assert_true(not _lane_has_frame(after_delete, local_frame),
		"the added waypoint is gone after Delete")


# --- helpers ----------------------------------------------------------------

## First camera angle span with ≥2 authored frames of width — room for an interior cut.
func _cuttable_camera_angle_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "camera":
			continue
		if not String(lane.get("id", "")).ends_with(":angle"):
			continue
		for sp in lane.get("spans", []):
			if int(sp.get("authored_end", 0)) - int(sp.get("authored_start", 0)) >= 2:
				return sp
	return {}


func _lane_has_frame(events: Array, frame: int) -> bool:
	for e in events:
		if int(e["end_frame"]) == frame:
			return true
	return false


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
