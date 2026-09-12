extends Node
## HEADFUL acceptance guard for camera selection survival across a split (ADR-0086
## amendment, #286). Drives the REAL EffectViewer scene → EffectStudioPage → host
## EffectViewerScene choke point, on the REAL E317 camera table (whose for_each has
## coalesced keyframes).
##
## A camera Source edit on a coalesced sub-channel event SPLITS the packed keyframe
## (structural), which re-lowers and RENUMBERS the storage array. Before #286 the page
## reloaded the score (load_score) and the span id embedded the raw index, so the
## author's selection was dropped. Now the span id is keyed on the stable sub-channel
## ordinal and structural edits RE-PROJECT (preserve transport), so the selection — and
## the inspector target — survive the split.
##
## Seam: page._on_span_selected + timeline.select_span (author selects) → page._apply_edit
## (the exact callback the inspector cell fans to) → host.studio_apply_edit → reproject.
## We assert the timeline's selected id is unchanged AND still resolves to a live span,
## and that the split actually happened (the compiled keyframe count grew).
##
## Run: <GODOT> --path . --quit-after 120 res://tests/EffectStudioCameraSplitSelectionTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")

const SRC_MAP := 0x0C0        # a source distinct from E317 angle@10's CASTER (0x140)
const SRC_CASTER := 0x140

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_camera_split_preserves_selection_on_real_E317()

	print("\n=== EffectStudioCameraSplitSelectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioCameraSplitSelectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioCameraSplitSelectionTest")
		get_tree().quit(0)


func _test_camera_split_preserves_selection_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		# E317 is gitignored ROM-derived content — skip cleanly where it is absent (CI),
		# same precedent as EffectStudioKindSelectorTest. The synthetic-fixture unit guard
		# EffectCameraOrdinalAddressTest carries the CI contract.
		print("[SKIP] E317 extract absent — camera split selection acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# The angle lane's ordinal-0 event is E317 for_each's coalesced mask=3 keyframe
	# (angle+position share one word) — editing its Source forces a split.
	var span := _coalesced_camera_angle_span(page)
	_assert_true(not span.is_empty(), "found a coalesced camera angle span to select")
	if span.is_empty():
		return
	var span_id := String(span.get("id", ""))

	# The author selects it (both the inspection root and the timeline highlight).
	page._timeline.select_span(span_id)
	page._on_span_selected(span_id)
	await _frames(2)
	_assert_eq(page._timeline.selected_span_id(), span_id, "the span is selected before the edit")

	# Edit Source (CASTER → MAP) through the SAME callback the inspector cell fans to.
	var source_ref := _source_field_ref(page, span)
	_assert_true(not source_ref.is_empty(), "resolved the Source cell's write-side field_ref")
	if source_ref.is_empty():
		return
	page._apply_edit(source_ref, SRC_MAP)
	await _frames(4)

	# The split happened AND spared the sibling: the angle event took MAP while the
	# coincident position event kept CASTER (they no longer share one packed keyframe).
	var lanes: Dictionary = CameraLowering.parse(page._effect_data.camera.get_table(span.get("phase", "")))
	_assert_eq(int(lanes["angle"][0]["source_bits"]), SRC_MAP,
		"the angle event's Source was changed to MAP")
	_assert_eq(int(lanes["position"][0]["source_bits"]), SRC_CASTER,
		"the coincident position sibling was spared (still CASTER) — a real split")

	# The whole point of #286: selection survives the structural re-project.
	_assert_eq(page._timeline.selected_span_id(), span_id,
		"the camera selection survives the structural split")
	_assert_true(_span_exists(page, span_id),
		"the selected span still resolves in the re-projected score")


# --- helpers ----------------------------------------------------------------

func _coalesced_camera_angle_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "camera":
			continue
		if not String(lane.get("id", "")).ends_with(":angle"):
			continue
		for sp in lane.get("spans", []):
			# channel_mask carrying more than the angle bit == coalesced with a sibling.
			var mask := int(sp.get("fields", {}).get("channel_mask", 0))
			if mask & ~1 != 0 and mask & 1 != 0:
				return sp
	return {}


## The Source cell's field_ref, pulled from the live projector sections (faithful to
## exactly what the inspector cell would carry into the choke point).
func _source_field_ref(page, span: Dictionary) -> Dictionary:
	for sec in Model.span_sections(span, page._effect_data):
		for f in sec.get("fields", []):
			if String(f.get("name", "")) == "Source":
				return f.get("field_ref", {})
	return {}


func _span_exists(page, span_id: String) -> bool:
	for lane in page._timeline._score.get("lanes", []):
		for sp in lane.get("spans", []):
			if String(sp.get("id", "")) == span_id:
				return true
	return false


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
