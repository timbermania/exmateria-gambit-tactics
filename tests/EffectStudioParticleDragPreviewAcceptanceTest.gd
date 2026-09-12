extends Node
## ADR-0089 Drag preview ACCEPTANCE (headful, real E019 — the emitter-rich particle
## baseline): a live particle EDGE drag through the REAL Studio page → REAL host →
## REAL EffectInstance must DEFER the expensive sim rescrub across the whole gesture and
## fold exactly ONCE on release — the fix for the laggy drag the user hit driving the
## particle timeline. Unit guards prove the page contract (EffectStudioEdgeDragWiringTest)
## and the host branch (EffectViewerRefoldTest) in isolation; this proves the WIRING holds
## end-to-end on a real, particle-dense effect: several drag motions leave the host's
## deferred-refold flag ARMED (no per-motion rescrub), and release commits + clears it with
## the parked instance surviving.
##
## Run: <GODOT> --path . --quit-after 240 res://tests/EffectStudioParticleDragPreviewAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 19
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E019.BIN"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_particle_edge_drag_defers_refold_until_release()

	print("\n=== EffectStudioParticleDragPreviewAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioParticleDragPreviewAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioParticleDragPreviewAcceptanceTest")
		get_tree().quit(0)


func _test_particle_edge_drag_defers_refold_until_release() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E019.BIN not available (ROM extract absent) — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(EFFECT_ID)   # parked at frame 0, Studio owns the clock
	await _frames(20)

	var page = scn._studio_page
	_assert_true(page != null, "the Studio page is mounted")
	if page == null:
		return
	_assert_true(page._host == scn, "the page's host is the live viewer scene")

	# A drawn particle span with an edge grip — the surface a Resize drag grabs.
	var span_id := _first_particle_span_id(page)
	_assert_true(span_id != "", "E019 has a drawn particle span to drag")
	if span_id == "":
		return
	var span := _span(page, span_id)
	var end_abs: int = int(span.get("end", 0))

	# Several mid-drag motions, each drained by a _process frame — the real per-motion path.
	page._on_edge_drag_started(span_id)
	page._on_edge_dragged(span_id, end_abs - 1)
	page._process(0.0)
	page._on_edge_dragged(span_id, end_abs - 2)
	page._process(0.0)
	# The host armed the deferred refold: a sim-invalidating edit was applied but NOT folded
	# per motion (the whole point of the preview — geometry tracks the cursor, sim waits).
	_assert_true(scn._deferred_refold_pending,
		"mid-drag: the sim rescrub is DEFERRED (armed, not folded per motion)")

	# Release: fold ONCE and clear the flag, with the parked instance surviving the rescrub.
	page._on_edge_drag_ended(span_id)
	_assert_true(not scn._deferred_refold_pending,
		"release COMMITTED the deferred refold (flag cleared — one fold for the whole drag)")
	_assert_true(is_instance_valid(scn._current_effect),
		"the parked effect survived the single release refold")

	# Gap Add-in-a-gap resolution on real E019 data (ADR-0089 particle_timeline): the page
	# resolves a particle lane id to its phase + channel and offset-corrects the score-absolute
	# cursor to phase-local — the composition _on_lane_context runs before it pops the menu.
	var lane_id: String = String(_span(page, span_id).get("lane_id", ""))
	var lane: Dictionary = page._find_lane(page._timeline._score, lane_id)
	_assert_true(not lane.is_empty(), "the dragged span's particle lane resolves off the live score")
	if not lane.is_empty():
		var phase: String = String(lane.get("phase", ""))
		var offset: int = page._phase_start(phase)
		var actions: Array = page._lane_gap_context_actions(
			phase, int(lane.get("channel_index", -1)), (offset + 7) - offset)
		_assert_eq(actions.size(), 1, "a particle gap offers exactly one verb on real data")
		if actions.size() == 1:
			_assert_eq(String(actions[0].get("label", "")), "Add span here", "…labelled Add span here")
			var ref: Dictionary = actions[0].get("field_ref", {})
			_assert_eq(String(ref.get("channel", "")), "particle", "…targeting the particle channel")
			_assert_eq(String(ref.get("context", "")), phase, "…carrying the real lane's phase")
			_assert_eq(int(ref.get("frame", -1)), 7, "…the cursor offset-corrected to phase-local")


# --- helpers ---------------------------------------------------------------

func _first_particle_span_id(page) -> String:
	if page._timeline == null:
		return ""
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("kind", "")) == "particle":
			for span in lane.get("spans", []):
				# A resizable span: has a right-edge grip and at least 2 frames of width.
				if int(span.get("end", 0)) - int(span.get("start", 0)) >= 2:
					return String(span.get("id", ""))
	return ""


func _span(page, span_id: String) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		for span in lane.get("spans", []):
			if String(span.get("id", "")) == span_id:
				return span
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
