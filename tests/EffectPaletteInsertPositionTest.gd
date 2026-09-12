extends Node
## HEADFUL acceptance guard: "Add tween here" splits a palette span at the STORABLE boundary
## NEAREST the right-clicked frame (ADR-0087 + ColorLowering.split_durations). Regression for
## the report "it doesn't split where I right click": the click frame was threaded correctly,
## but the old chooser rounded first-half-only and could sliver+drift when a clean split
## existed. Drives the real page path (_lane_context_actions → _run_lane_verb) on real E317:
##   * roomy spans: the split lands within the ÷8 snap radius (Δ ≤ 4) of the click,
##   * an 8-frame span (no clean faithful split) drifts the lane end by AT MOST 1 frame,
##     slivering toward the click,
##   * input layer: a synthesized right-click reports the frame under the cursor (Δ ≤ 2).
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectPaletteInsertPositionTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _passed: int = 0
var _failed: int = 0
var _ctx_frames: Array = []


func _ready() -> void:
	await _run()
	print("\n=== EffectPaletteInsertPositionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteInsertPositionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteInsertPositionTest")
		get_tree().quit(0)


func _run() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent")
		return
	page._load_effect(dir)
	await _frames(20)

	var spans := _roomy_palette_spans(page, 3)
	if spans.is_empty():
		print("[SKIP] no roomy palette span on E317")
		return

	for span in spans:
		for frac in [0.25, 0.75]:
			await _probe_split(scn, page, span, frac)

	# An 8-frame span has no clean faithful split — assert the drift stays at the minimum.
	var short_span := _span_of_width(page, 8)
	if not short_span.is_empty():
		await _probe_short_split(scn, page, short_span)

	# Input layer: synthesize the right-click, check the frame the timeline reports.
	var tl = page._timeline
	tl.span_context_requested.connect(func(_id, f): _ctx_frames.append(f))
	var span0: Dictionary = spans[0]
	await _probe_click_frame(page, tl, span0, 0.25)
	await _probe_click_frame(page, tl, span0, 0.75)


func _probe_split(scn, page, span: Dictionary, frac: float) -> void:
	var phase: String = String(span.get("phase", ""))
	var channel_name: String = String(span.get("fields", {}).get("channel", ""))
	var ch = scn._current_effect.effect_data.palette.get_channel(phase, channel_name)
	var s: int = int(span.get("start", 0))
	var e: int = int(span.get("end", 0))
	var kf_index: int = int(span.get("keyframe_index", -1))
	var click_abs: int = s + int(round(frac * float(e - s)))
	var label := "%s/%s kf%d [%d,%d) click@%d" % [phase, channel_name, kf_index, s, e, click_abs]

	var actions: Array = page._lane_context_actions(span, click_abs)
	if actions.is_empty():
		_fail("%s — no context actions" % label)
		return
	page._run_lane_verb(actions[0])
	await _frames(4)

	# The new (disabled) keyframe is kf_index+1; its span start on the rebuilt score is the cut.
	var new_id := "palette:%s:%s#%d" % [phase, channel_name, kf_index + 1]
	var new_span := _find_span(page, new_id)
	if new_span.is_empty():
		_fail("%s — no new span %s after insert" % [label, new_id])
	else:
		var landed: int = int(new_span.get("start", 0))
		var diff: int = absi(landed - click_abs)
		_check(diff <= 4, "%s — split at %d, Δ=%d ≤ 4" % [label, landed, diff])

	page._undo()
	await _frames(4)
	_check(ch.keyframes.size() > 0, "%s — undo left the channel intact" % label)


## Split an 8-frame span near its END: the sliver must land on the click's side (the cut at
## the old far edge) and the lane end may drift by at most the minimum 1 frame.
func _probe_short_split(scn, page, span: Dictionary) -> void:
	var phase: String = String(span.get("phase", ""))
	var channel_name: String = String(span.get("fields", {}).get("channel", ""))
	var s: int = int(span.get("start", 0))
	var e: int = int(span.get("end", 0))
	var kf_index: int = int(span.get("keyframe_index", -1))
	var click_abs: int = e - 1
	var lane_end_before := _lane_end(page, String(span.get("lane_id", "")))
	var label := "SHORT %s/%s kf%d [%d,%d) click@%d" % [phase, channel_name, kf_index, s, e, click_abs]

	var actions: Array = page._lane_context_actions(span, click_abs)
	page._run_lane_verb(actions[0])
	await _frames(4)
	var new_id := "palette:%s:%s#%d" % [phase, channel_name, kf_index + 1]
	var new_span := _find_span(page, new_id)
	var landed: int = int(new_span.get("start", -1))
	var lane_end_after := _lane_end(page, String(span.get("lane_id", "")))
	_check(absi(landed - click_abs) <= 1, "%s — sliver cut at %d lands beside the click" % [label, landed])
	_check(absi(lane_end_after - lane_end_before) <= 1,
		"%s — lane end drifts at most 1 (%d→%d)" % [label, lane_end_before, lane_end_after])
	page._undo()
	await _frames(4)


## Synthesize a right-click at the pixel for `frac` along the span, on the span's own lane
## row, and check the frame the timeline reports against the frame under that pixel.
func _probe_click_frame(page, tl, span: Dictionary, frac: float) -> void:
	var s: int = int(span.get("start", 0))
	var e: int = int(span.get("end", 0))
	var want: int = s + int(round(frac * float(e - s)))
	var x: float = tl.axis.frame_to_x(float(want))
	var row_y: float = _span_row_y(tl, String(span.get("id", "")))
	if row_y < 0.0:
		_fail("input-layer: span row for %s not found" % span.get("id", ""))
		return
	_ctx_frames.clear()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(x, row_y)
	tl._gui_input(ev)
	await _frames(2)
	if _ctx_frames.is_empty():
		_fail("input-layer: right-click at x=%.1f emitted no span_context_requested" % x)
		return
	var got: int = int(_ctx_frames[0])
	_check(absi(got - want) <= 2, "input-layer frame under cursor: want %d got %d" % [want, got])


# --- helpers ----------------------------------------------------------------

func _roomy_palette_spans(page, n: int) -> Array:
	var out: Array = []
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "palette":
			continue
		for sp in lane.get("spans", []):
			if int(sp.get("end", 0)) - int(sp.get("start", 0)) >= 16:
				out.append(sp)
				if out.size() >= n:
					return out
	return out


func _span_of_width(page, w: int) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "palette":
			continue
		var spans: Array = lane.get("spans", [])
		for i in range(spans.size()):
			var sp: Dictionary = spans[i]
			# Want a short span with downstream neighbours so drift is observable.
			if int(sp.get("end", 0)) - int(sp.get("start", 0)) == w and i < spans.size() - 2:
				return sp
	return {}


func _lane_end(page, lane_id: String) -> int:
	var best: int = -1
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("id", "")) != lane_id:
			continue
		for sp in lane.get("spans", []):
			best = maxi(best, int(sp.get("end", 0)))
	return best


func _find_span(page, span_id: String) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		for sp in lane.get("spans", []):
			if String(sp.get("id", "")) == span_id:
				return sp
	return {}


## Centre y of the lane row holding `span_id`, from the timeline's layout rects.
func _span_row_y(tl, span_id: String) -> float:
	tl.rebuild_layout()
	for r in tl._span_rects:
		if String(r.get("span", {}).get("id", "")) == span_id:
			var rect: Rect2 = r.get("rect", Rect2())
			return rect.position.y + rect.size.y * 0.5
	return -1.0


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	print("[FAIL] %s" % label)
