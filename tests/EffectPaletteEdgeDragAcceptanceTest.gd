extends Node
## HEADFUL acceptance guard for the palette BOUNDARY edge-drag end-to-end (ADR-0087). Drives
## the REAL EffectViewer scene → EffectStudioPage edge-drag handlers → host studio_begin_coalesce
## / studio_apply_edit / studio_end_coalesce → EffectEditSession → PaletteChannel boundary trade,
## on real E317. Confirms the whole path an author's palette edge-drag drives:
##   * dragging an internal boundary is a stay-local sum-preserving trade — the dragged span's
##     end moves AND the array-adjacent neighbour's derived start follows, downstream pinned,
##   * the boundary snaps to an 8-frame step,
##   * the effect re-folds (read-live palette) without dying,
##   * the whole gesture is ONE undo (begin/end_coalesce), restoring the original boundary.
## The pure lowering / channel trade / page wiring are guarded headless (ColorLoweringTest /
## PaletteBoundaryEditTest / EffectStudioEdgeDragWiringTest); this is the live wiring on real bytes.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectPaletteEdgeDragAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_palette_edge_drag_on_real_E317()

	print("\n=== EffectPaletteEdgeDragAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteEdgeDragAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteEdgeDragAcceptanceTest")
		get_tree().quit(0)


func _test_palette_edge_drag_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — palette edge-drag acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	# An internal palette boundary: a span whose next lane sibling is the NEXT array keyframe
	# (keyframe_index + 1) so the sum-preserving trade is exact and observable.
	var pick := _internal_palette_boundary(page)
	if pick.is_empty():
		print("[SKIP] no internal palette boundary on E317 — acceptance skipped")
		return
	var span: Dictionary = pick["span"]
	var nxt: Dictionary = pick["next"]
	var sid := String(span.get("id", ""))
	var offset: int = int(span.get("start", 0)) - int(span.get("authored_start", 0))
	var e0: int = int(span.get("authored_end", 0))          # original boundary (phase-local)
	var next_end: int = int(nxt.get("authored_end", 0))

	page._timeline.select_span(sid)
	page._on_span_selected(sid)
	await _frames(2)

	# Move the boundary by one 8-frame step in whichever direction has headroom (grow if the
	# neighbour has room above, else shrink if this span has room below).
	var a0: int = int(span.get("authored_start", 0))
	var target_local: int = -1
	if e0 + 8 < next_end:
		target_local = e0 + 8                                # grow into the neighbour
	elif e0 - 8 > a0:
		target_local = e0 - 8                                # shrink (neighbour grows)
	if target_local < 0:
		print("[SKIP] palette boundary has no 8-frame headroom on E317 — acceptance skipped")
		return

	await _drag_edge(page, sid, target_local + offset)

	_assert_eq(is_instance_valid(scn._current_effect), true, "the effect re-folded without dying")
	var moved: Dictionary = Model.find_span(page._timeline._score, sid)
	var neighbour: Dictionary = Model.find_span(page._timeline._score, String(nxt.get("id", "")))
	_assert_eq(int(moved.get("authored_end", -1)), target_local, "the dragged span's end moved to the snapped target")
	_assert_eq(int(neighbour.get("authored_start", -1)), target_local,
		"the neighbour's start followed for free (sum-preserving boundary trade)")
	_assert_eq(int(neighbour.get("authored_end", -1)), next_end, "downstream stays pinned (neighbour's end unchanged)")

	# One undo restores the original boundary — the whole gesture was a single coalesced entry.
	page._undo()
	await _frames(4)
	var reverted: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(int(reverted.get("authored_end", -1)), e0, "one undo restores the original boundary")


# --- helpers ----------------------------------------------------------------

func _drag_edge(page, sid: String, abs_target: int) -> void:
	page._on_edge_drag_started(sid)
	page._on_edge_dragged(sid, abs_target)
	await _frames(3)                 # let _process drain the once-per-frame apply + reproject
	page._on_edge_drag_ended(sid)
	await _frames(3)


## The palette span with an array-adjacent next sibling (keyframe_index + 1) and the MOST
## combined room (so a ±8-frame boundary move fits with the neighbour kept ≥ 1 frame). An
## internal boundary whose sum-preserving trade keeps the far edge exactly pinned.
func _internal_palette_boundary(page) -> Dictionary:
	var best := {}
	var best_room := 0
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "palette":
			continue
		var spans: Array = lane.get("spans", [])
		for sp in spans:
			var want: int = int(sp.get("keyframe_index", -1)) + 1
			for nx in spans:
				if int(nx.get("keyframe_index", -1)) != want:
					continue
				var room: int = int(nx.get("authored_end", 0)) - int(sp.get("authored_start", 0))
				if room > best_room:
					best_room = room
					best = {"span": sp, "next": nx}
	return best


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
