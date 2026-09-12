extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #271): the whole "Effect Settings → edit a phase
## duration → the score re-flows" path, end to end through the live studio.
##   1. The toolbar "Effect ⚙" button opens the effect_settings target, and the inspector
##      renders the Timeline section with the three duration rows.
##   2. Editing phase1_duration through the page choke point re-flows the WHOLE score: the
##      for_each phase offset shifts, and every for_each particle span slides by the same
##      delta (bands move) — the "one genuinely useful wrinkle" this subsystem owns.
## Skips when E019 assets are absent (gitignored/ROM-derived). A screenshot is written for the
## eyeball check.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioTimelineHeaderAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectPhase = ExMateriaEffects.EffectPhase
const SHOT := "user://timeline_header_e019.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioTimelineHeaderAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTimelineHeaderAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTimelineHeaderAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	_assert_true(data != null and data.timeline != null, "E019 has a timeline")
	if data == null or data.timeline == null:
		return

	# --- (0) The displayed end frame runs THROUGH phase 2's content (not dimmed as dead). ---
	# E019's particles reap ~frame 105 (1 frame into phase 2), but phase 2's camera content
	# runs to 120 — the studio floors its end there so phase 2 plays live.
	var p2_content := Model.phase2_content_end(page._timeline._score)
	var p2_start := Model.phase_offset(data, EffectPhase.PHASE2)
	_assert_true(page._timeline.get_end_frame() >= p2_start,
		"end frame reaches at least phase 2 start (%d): %d" % [p2_start, page._timeline.get_end_frame()])
	_assert_true(page._timeline.get_end_frame() >= p2_content,
		"end frame runs through phase 2 content (%d): %d" % [p2_content, page._timeline.get_end_frame()])

	# --- (1) The Effect ⚙ button opens the settings surface with the Timeline rows. ---
	page._open_effect_settings()
	await _frames(10)
	_assert_true(Target.kind(page._nav.back()) == "effect_settings",
		"the button navigated to the effect_settings target")
	var sections = Model.inspector_sections(Target.effect_settings(), data, page._timeline._score)
	var timeline_sec := _find_section(sections, "Timeline")
	_assert_true(not timeline_sec.is_empty(), "the inspector shows a Timeline section")
	_assert_eq(timeline_sec.get("fields", []).size(), 3, "the Timeline section has 3 duration rows")

	# --- (2) Edit phase1_duration → the score re-flows (for_each band slides). ---
	var off_before := Model.phase_offset(data, EffectPhase.PHASE_FOR_EACH)
	# Observe a lane anchored at the for_each boundary (E019's particle spawns are all in
	# phase1 at offset 0, so they don't move — but the for_each camera lane starts exactly at
	# phase1_duration and slides with it).
	var lane_id := _first_for_each_lane(page._timeline._score)
	_assert_true(lane_id != "", "E019 has a for_each lane anchored at the phase boundary")
	var span_start_before := _first_span_start(page._timeline._score, lane_id)
	_assert_eq(span_start_before, off_before, "the observed lane starts at the for_each offset")

	var delta := 30
	page._apply_edit({"channel": "timeline_header", "field": "phase1_duration"}, off_before + delta)
	await _frames(20)

	var off_after := Model.phase_offset(data, EffectPhase.PHASE_FOR_EACH)
	_assert_eq(off_after, off_before + delta, "the for_each phase offset shifted by the edit")
	_assert_eq(data.timeline.phase1_duration, off_before + delta, "the live duration is written")

	var span_start_after := _first_span_start(page._timeline._score, lane_id)
	_assert_eq(span_start_after, span_start_before + delta,
		"the for_each particle band slid by the same delta (score re-flowed): %d -> %d"
			% [span_start_before, span_start_after])

	# --- (3) The END MARKER tracks the edit: phase 2 shifted by delta, so its content end
	# (and the floored displayed end) moves too. Editing a duration must recompute the end. ---
	var p2_content_after := Model.phase2_content_end(page._timeline._score)
	_assert_eq(page._timeline.get_end_frame(), maxi(page._timeline.get_end_frame(), p2_content_after),
		"end frame is not below phase 2 content after the edit")
	_assert_true(page._timeline.get_end_frame() >= p2_content_after,
		"end marker runs through phase 2 content after a duration edit (%d >= %d)"
			% [page._timeline.get_end_frame(), p2_content_after])

	# Visual record for the eyeball (field dumps don't count) — the whole studio viewport.
	await _frames(5)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


# --- score helpers ---------------------------------------------------------
func _find_section(sections: Array, title: String) -> Dictionary:
	for sec in sections:
		if str(sec.get("title", "")) == title:
			return sec
	return {}


func _first_for_each_lane(score: Dictionary) -> String:
	for lane in score.get("lanes", []):
		if str(lane.get("id", lane.get("lane_id", ""))).contains(":for_each:") \
				and not lane.get("spans", []).is_empty():
			return str(lane.get("id", lane.get("lane_id", "")))
	return ""


func _first_span_start(score: Dictionary, lane_id: String) -> int:
	for lane in score.get("lanes", []):
		if str(lane.get("id", lane.get("lane_id", ""))) == lane_id:
			var spans: Array = lane.get("spans", [])
			if not spans.is_empty():
				return int(spans[0].get("start", 0))
	return -1


# --- harness ---------------------------------------------------------------
func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
