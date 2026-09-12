extends Node
## HEADFUL acceptance guard for the VERDICT-FRESHNESS invariant (ADR-0087 dec. 29):
## **every path that writes colour bytes must re-derive the contextual spacer verdict.**
##
## The result-picker was the one edit path that bypassed the page's edit choke point —
## `EffectKeyframeInspector._target_color_cell` → `EffectStudioPage._pick_target` →
## `EffectViewerScene.studio_pick_target` calls `host.studio_apply_edit` three times DIRECTLY,
## so `EffectStudioPage._apply_edit`'s `invalidates_layout` branch (the one that re-runs
## `SpacerVerdicts`) never ran. Result, as reported: you add an event, colour it with the
## picker, click off — and it VANISHES (`is_hidden_spacer` is still reading the pre-pick
## verdict). Nudging an RGB spinner instead "fixes" it, because the spinners route through
## `_on_mutate` → `_apply_edit` → rebuild.
##
## The guard drives the REAL EffectViewer → EffectStudioPage on real E015, which ships five
## naturally-inert screen events (the invisible empty space of the fifth amendment):
##   1. take an ENABLED spacer — on screen it is exactly the state a freshly-added, not-yet-
##      coloured event is in,
##   2. select it (decision 5: the selected span always draws, which is why the staleness is
##      invisible until deselect), park the playhead inside it, and pick a strong target colour
##      through `_pick_target` — the PICKER path, **no spinner touched**,
##   3. assert the score's verdict flipped to `spacer` false, i.e. the coloured event survives
##      deselection instead of vanishing.
## Step 3 FAILS before the fix (the score still says spacer) — this is the regression lock on
## the actual bug.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E015 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectPickerVerdictFreshnessTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_picker_refreshes_the_spacer_verdict()

	print("\n=== EffectPickerVerdictFreshnessTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPickerVerdictFreshnessTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPickerVerdictFreshnessTest")
		get_tree().quit(0)


func _test_picker_refreshes_the_spacer_verdict() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E015"):
			dir = d
	if dir == "":
		print("[SKIP] E015 extract absent — picker verdict-freshness acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	_report_screen_lane(page)

	# --- 1. an ENABLED spacer: invisible empty space, drawn only because it is selected -------
	var pick := _enabled_spacer_span(page)
	if pick.is_empty():
		print("[SKIP] no enabled screen spacer on E015 — acceptance skipped")
		return
	var sid := String(pick.get("id", ""))
	var phase := String(pick.get("phase", ""))
	var idx: int = int(pick.get("keyframe_index", -1))
	print("[INFO] candidate span %s (phase %s, kf %d)" % [sid, phase, idx])
	_assert_eq(bool(pick.get("fields", {}).get("spacer", false)), true,
		"precondition: the event reads as a spacer")
	_assert_eq(bool(pick.get("fields", {}).get("enabled", false)), true,
		"precondition: it is an ENABLED spacer — invisible empty space, not a hatched disable")

	# --- 2. colour it through the PICKER path — no spinner touched ---------------------------
	page._timeline.select_span(sid)
	page._on_span_selected(sid)
	await _frames(4)
	# Park the playhead INSIDE the span so the picker's back-solve probes a fold this event
	# actually participates in (the solver brute-forces through the live ScreenSubsystem).
	var mid: int = int(pick.get("start", 0)) + maxi(1, int(pick.get("end", 0)) - int(pick.get("start", 0))) / 2
	page._seek(mid)
	await _frames(4)
	var achieved = page._pick_target(_refs(phase, idx), _far_from(scn))
	await _frames(6)

	# The pick must have actually written bytes — otherwise step 3 proves nothing.
	var wrote := false
	for f in ["start_r", "start_g", "start_b"]:
		if _raw(scn, phase, idx, f) != 0:
			wrote = true
	_assert_eq(wrote, true, "the pick wrote a non-identity Blend param (achieved %s)" % str(achieved))

	# --- 3. the verdict must be FRESH ---------------------------------------------------------
	var after: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_eq(bool(after.get("fields", {}).get("spacer", true)), false,
		"the PICKER re-derived the spacer verdict — the coloured event survives deselection")

	# And the score agrees with a from-scratch build: no stale lane anywhere.
	var fresh: Dictionary = Model.build(page._effect_data)
	var fresh_span: Dictionary = Model.find_span(fresh, sid)
	_assert_eq(bool(after.get("fields", {}).get("spacer", true)),
		bool(fresh_span.get("fields", {}).get("spacer", true)),
		"the live score's verdict matches a from-scratch rebuild")


# --- helpers ----------------------------------------------------------------

func _ref(phase: String, idx: int, field: String) -> Dictionary:
	return {"channel": "screen", "context": phase, "event_index": idx, "field": field}


func _refs(phase: String, idx: int) -> Dictionary:
	return {
		"r": _ref(phase, idx, "start_r"),
		"g": _ref(phase, idx, "start_g"),
		"b": _ref(phase, idx, "start_b"),
	}


func _raw(scn, phase: String, idx: int, field: String) -> int:
	var ch = scn._current_effect.effect_data.screen.get_channel(phase)
	if ch == null:
		return -1
	return int(ch.get_keyframe(idx).get(field + "_raw"))


## A target colour maximally far from the backdrop's CURRENT folded top — so the back-solve
## lands on a large signed param and the event is provably no longer a visual no-op. Picking
## something near the current look could legitimately solve to ~0 and prove nothing.
func _far_from(scn) -> Color:
	var now: Color = scn.studio_screen_top_color()
	return Color(0.0 if now.r > 0.5 else 1.0, 0.0 if now.g > 0.5 else 1.0, 0.0 if now.b > 0.5 else 1.0)


## The widest ENABLED SPACER on a screen lane — a verdict-inert event the fifth amendment
## renders as nothing. This is the state a just-added, not-yet-coloured event sits in.
func _enabled_spacer_span(page) -> Dictionary:
	var best := {}
	var best_w := 0
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			var f: Dictionary = sp.get("fields", {})
			if not bool(f.get("spacer", false)) or not bool(f.get("enabled", false)):
				continue
			var w: int = int(sp.get("end", 0)) - int(sp.get("start", 0))
			if w > best_w:
				best_w = w
				best = sp
	return best


func _report_screen_lane(page) -> void:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		var bits: Array = []
		for sp in lane.get("spans", []):
			var f: Dictionary = sp.get("fields", {})
			bits.append("%d:%s%s%s" % [int(sp.get("keyframe_index", -1)),
				String(f.get("screen_kind", "?")),
				"/spacer" if bool(f.get("spacer", false)) else "",
				"" if bool(f.get("enabled", false)) else "/off"])
		print("[INFO] lane %s: %s" % [String(lane.get("id", "")), ", ".join(bits)])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
