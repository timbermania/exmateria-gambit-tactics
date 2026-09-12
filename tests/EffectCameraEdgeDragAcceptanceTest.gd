extends Node
## HEADFUL acceptance guard for the camera EDGE-DRAG (boundary resize) end-to-end (ADR-0086
## boundary-drag amendment). Drives the REAL EffectViewer scene → EffectStudioPage edge-drag
## handlers → host EffectViewerScene.studio_begin_coalesce / studio_apply_edit /
## studio_end_coalesce → EffectEditSession → CameraChannel, on real E317. Confirms the whole
## path an author's edge-drag drives:
##   * dragging an internal boundary is a stay-local trade — the dragged span's end moves AND
##     the neighbour's derived start follows, while everything downstream stays pinned,
##   * the effect re-folds without dying,
##   * over-dragging past the neighbour CLAMPS (never collapses it),
##   * the whole gesture is ONE undo (begin/end_coalesce), restoring the original boundary,
##   * with RIPPLE on (ADR-0087 decs. 15-16): the drag SHIFTS every downstream end in
##     the lane (widths kept, sibling lanes untouched), ONE undo restores them all, and
##     toggling ripple back off leaves the stay-local trade intact.
## The pure timeline emit / session coalesce / page clamp+convert+drain are guarded headless
## (EffectScoreTimelineTest / EffectEditSessionTest / EffectStudioEdgeDragWiringTest); this is
## the live wiring on real bytes.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectCameraEdgeDragAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_edge_drag_on_real_E317()
	await _test_move_then_drag_back_reaches_the_origin_on_real_E001()

	print("\n=== EffectCameraEdgeDragAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraEdgeDragAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraEdgeDragAcceptanceTest")
		get_tree().quit(0)


func _test_edge_drag_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — edge-drag acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# An INTERNAL angle boundary: a span with a successor in its lane, and enough combined
	# room that a grown boundary differs from the original (so the trade is observable).
	var pick := _internal_angle_boundary(page)
	if pick.is_empty():
		print("[SKIP] no internal camera angle boundary on E317 — edge-drag acceptance skipped")
		return
	var span: Dictionary = pick["span"]
	var next_span: Dictionary = pick["next"]
	var phase := String(span.get("phase", ""))
	var sid := String(span.get("id", ""))
	var offset: int = int(span.get("start", 0)) - int(span.get("authored_start", 0))
	var e0: int = int(span.get("authored_end", 0))          # the original boundary (phase-local)
	var next_end: int = int(next_span.get("authored_end", 0))

	page._timeline.select_span(sid)
	page._on_span_selected(sid)
	await _frames(2)

	# --- Gesture 1: grow the boundary a couple frames → stay-local trade, one undo ---------
	var lo: int = int(span.get("authored_start", 0)) + 1
	var target_local: int = clampi(e0 + 2, lo, next_end - 1)
	if target_local == e0:
		target_local = clampi(e0 - 1, lo, next_end - 1)   # no headroom above → nudge down
	_assert_true(target_local != e0, "the picked boundary has room to move")

	await _drag_edge(page, sid, target_local + offset)

	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying")
	var moved: Dictionary = Model.find_span(page._timeline._score, sid)
	var neighbour: Dictionary = Model.find_span(page._timeline._score, String(next_span.get("id", "")))
	_assert_eq(int(moved.get("authored_end", -1)), target_local, "the dragged span's end moved to the target")
	_assert_eq(int(neighbour.get("authored_start", -1)), target_local,
		"the neighbour's start followed for free (stay-local boundary trade)")
	_assert_eq(int(neighbour.get("authored_end", -1)), next_end, "downstream stays pinned (neighbour's end unchanged)")

	# One undo restores the original boundary — the whole gesture was a single coalesced entry.
	page._undo()
	await _frames(4)
	var reverted: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(int(reverted.get("authored_end", -1)), e0, "one undo restores the original boundary")

	# --- Gesture 2: over-drag past the neighbour → CLAMP, never collapse it ----------------
	await _drag_edge(page, sid, next_end + 10_000 + offset)
	var clamped: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(int(clamped.get("authored_end", -1)), next_end - 1,
		"over-dragging clamps to next_end − 1 (the neighbour keeps ≥ 1 frame, never deleted)")
	page._undo()
	await _frames(4)

	# --- Gesture 3: RIPPLE drag (ADR-0087 decs. 15-16) — downstream SHIFTS, one undo --
	page._toggle_ripple()
	var live: Dictionary = Model.find_span(page._timeline._score, sid)
	var lane_id := String(live.get("lane_id", ""))
	var this_ord: int = int(live.get("ordinal", -1))
	var all_before: Dictionary = _camera_lane_ends(page)
	var r0: int = int(live.get("authored_end", 0))
	var r_target: int = r0 + 2

	await _drag_edge(page, sid, r_target + offset)

	_assert_eq(is_instance_valid(scn._current_effect), true, "the rippled effect re-folded without dying")
	var rmoved: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(int(rmoved.get("authored_end", -1)), r_target,
		"the rippled span's end moved (the old neighbour bound no longer clamps)")
	var all_after: Dictionary = _camera_lane_ends(page)
	var lane_ok := true
	for o in all_before.get(lane_id, {}):
		var want: int = int(all_before[lane_id][o]) + (2 if int(o) >= this_ord else 0)
		if int(all_after.get(lane_id, {}).get(o, -99999)) != want:
			lane_ok = false
			print("  %s ordinal %s: expected %d got %s"
				% [lane_id, str(o), want, str(all_after.get(lane_id, {}).get(o))])
	_assert_true(lane_ok,
		"every downstream end in the lane shifted by the delta (widths kept), upstream pinned")
	var siblings_ok := true
	for lid in all_before:
		if String(lid) != lane_id and all_after.get(lid, {}) != all_before[lid]:
			siblings_ok = false
			print("  sibling lane %s moved: %s → %s" % [lid, str(all_before[lid]), str(all_after.get(lid))])
	_assert_true(siblings_ok, "sibling camera lanes never moved (ripple is lane-local, splits not drags)")

	page._undo()
	await _frames(4)
	_assert_eq(_camera_lane_ends(page), all_before,
		"ONE undo restores every shifted end across the lane (structural table stash)")

	# --- Gesture 4: toggle ripple OFF → the old stay-local clamp is intact ------------------
	page._toggle_ripple()
	await _drag_edge(page, sid, next_end + 10_000 + offset)
	var back: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(int(back.get("authored_end", -1)), next_end - 1,
		"with ripple back off the neighbour clamp (stay-local trade) is intact")
	page._undo()
	await _frames(4)


## THE REPORTED ROUND TRIP, on real bytes through the real scene. Drag the leftmost camera
## event of a for_each lane RIGHT, then reach for its left edge and drag it back: it must reach
## the phase origin again, with no residual gap.
##
## The two verbs meet in this gesture. Sliding the first event right MANUFACTURES a hold to own
## the space it vacated, and that hidden hold's RIGHT edge IS the moved span's visible LEFT edge
## (the grip-identity rule) — so "drag it back" is an EDGE drag on the hold, and its min-one-frame
## clamp used to stop one frame short, whatever the distance. E001's for_each angle lane is the
## shipped shape the report starts from: a drawn event owning [0,4) followed by a hold out to 38.
func _test_move_then_drag_back_reaches_the_origin_on_real_E001() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			dir = d
	if dir == "":
		print("[SKIP] E001 extract absent — Move round-trip acceptance skipped")
		scn.queue_free()
		return
	page._load_effect(dir)
	await _frames(20)

	var lane_id := "camera:for_each:angle"
	var first := _first_drawn_span(page, lane_id)
	if first.is_empty() or int(first.get("authored_start", -1)) != 0:
		print("[SKIP] E001's for_each angle lane is not the reported shape — skipped")
		scn.queue_free()
		return
	var sid := String(first.get("id", ""))
	var width: int = int(first.get("authored_end", 0)) - int(first.get("authored_start", 0))
	var offset: int = int(first.get("start", 0)) - int(first.get("authored_start", 0))
	var lane_before: Dictionary = _camera_lane_ends(page)

	# 1. Slide it right. The Move manufactures the origin hold and the event takes ordinal 1.
	page._on_span_body_drag_started(sid)
	page._on_span_body_dragged(sid, 6)
	await _frames(3)
	page._on_span_body_drag_ended(sid)
	await _frames(4)
	var moved := _first_drawn_span(page, lane_id)
	_assert_eq(int(moved.get("authored_start", -1)), 6, "the first event slid right by 6")
	_assert_eq(int(moved.get("authored_end", -1)) - int(moved.get("authored_start", -1)), width,
		"…width preserved")
	_assert_eq(is_instance_valid(scn._current_effect), true, "the moved effect re-folded without dying")

	# 2. Reach for its left edge — the manufactured hold's grip — and drag past the origin.
	var hold_id := "%s#0" % lane_id
	_assert_true(int(Model.find_span(page._timeline._score, hold_id).get("authored_end", -1)) == 6,
		"the manufactured hold owns the space in front of it")
	await _drag_edge(page, hold_id, offset - 10_000)
	var home := _first_drawn_span(page, lane_id)
	_assert_eq(int(home.get("authored_start", -1)), 0,
		"the event owns the phase origin again — no residual 1-frame gap")
	_assert_eq(int(home.get("ordinal", -1)), 0,
		"…and the emptied hold is DELETED, not parked at zero width holding ordinal 0")
	_assert_eq(is_instance_valid(scn._current_effect), true, "…and the effect still folds")

	# 3. Three undos put the lane back. The edge gesture records TWO entries — the coalesced
	#    resize, then the release-time DELETE of the hold it emptied (ADR-0101 dec. 7) — and the
	#    Move records one. That extra step is the known cost of dropping the orphan from the
	#    boundary drag: Move keeps a single entry because it re-plans from its grab snapshot,
	#    while the boundary drag cannot delete mid-gesture without renumbering the lane under
	#    the cursor.
	for i in range(3):
		page._undo()
		await _frames(4)
	_assert_eq(_camera_lane_ends(page), lane_before,
		"undo restores every end in every camera lane")
	scn.queue_free()
	await _frames(2)


# --- helpers ----------------------------------------------------------------

## The first DRAWN (non-spacer) span in a lane — addressed by content, because a structural
## Move renumbers the lane and `#0` can name the manufactured hold by the time we look again.
func _first_drawn_span(page, lane_id: String) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("id", "")) != lane_id:
			continue
		for sp in lane.get("spans", []):
			if not bool(sp.get("fields", {}).get("spacer", false)):
				return sp
	return {}


## Every camera lane's authored ends by ordinal — {lane_id: {ordinal: authored_end}} — the
## observable the ripple gestures compare (shifted lane vs untouched siblings vs restored).
func _camera_lane_ends(page) -> Dictionary:
	var out: Dictionary = {}
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "camera":
			continue
		var ends: Dictionary = {}
		for sp in lane.get("spans", []):
			ends[int(sp.get("ordinal", -1))] = int(sp.get("authored_end", 0))
		out[String(lane.get("id", ""))] = ends
	return out

## Drive one edge-drag gesture through the real page handlers + the live _process drain.
func _drag_edge(page, sid: String, abs_target: int) -> void:
	page._on_edge_drag_started(sid)
	page._on_edge_dragged(sid, abs_target)
	await _frames(3)                 # let _process drain the once-per-frame apply + reproject
	page._on_edge_drag_ended(sid)
	await _frames(3)


## The first angle span that has a next sibling (ordinal+1) in the same lane, with combined
## room (next_end − authored_start ≥ 3) so a grown boundary is observably different.
func _internal_angle_boundary(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "camera":
			continue
		if not String(lane.get("id", "")).ends_with(":angle"):
			continue
		var spans: Array = lane.get("spans", [])
		for i in range(spans.size()):
			var sp: Dictionary = spans[i]
			var want: int = int(sp.get("ordinal", -1)) + 1
			for nx in spans:
				if int(nx.get("ordinal", -1)) == want \
						and int(nx.get("authored_end", 0)) - int(sp.get("authored_start", 0)) >= 3:
					return {"span": sp, "next": nx}
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
