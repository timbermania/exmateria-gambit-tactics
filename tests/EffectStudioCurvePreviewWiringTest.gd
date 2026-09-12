extends Node
## TDD guard for the Effect Studio CURVE-CONTENTS commit wiring. It started as the
## ADR-0089 curve-UX bug #4 guard — `curve_changed` was connected to NOTHING, so the
## samples changed in memory while the preview and sparkline went stale ("editing a
## curve doesn't update the curve") — and the fan-out half (rebuild score + re-render
## inspector + re-seek/re-fold at the parked frame) is still guarded below.
##
## What INVERTED with the ADR-0089 curve-ownership amendment: a committed stroke is a
## REAL edit. It used to be ephemeral on purpose — no session, no undo, no writer —
## because the painter mutated a SHARED curve, and a shared edit that saved would have
## restyled every referring param. Now every use site owns its curve, so the commit
## lowers through the EffectEditSession choke point like any other edit, and the
## "Preview only — curve edits aren't saved yet" note is gone with the model that made
## it true. The test that asserted the ephemerality is the one that had to flip.
##
## Pure logic: the page is new()'d WITHOUT add_child (so _ready never runs); we inject
## a real timeline + camera data + a recording fake host, then build the painter
## overlay and fire the signal directly.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioCurvePreviewWiringTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_curve_changed_is_wired_after_build()
	_test_curve_changed_reseeks_at_the_parked_frame()
	_test_a_committed_stroke_is_a_session_edit()
	_test_a_stroke_outside_a_use_site_records_nothing()
	_test_painter_panel_says_the_edit_is_saved()
	_test_fit_toggles_flip_the_sparkline_globals()

	print("\n=== EffectStudioCurvePreviewWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioCurvePreviewWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioCurvePreviewWiringTest")
		get_tree().quit(0)


## The regression itself: after building the painter overlay, `curve_changed` is
## connected to the page's live-refresh handler (was connected to nothing).
func _test_curve_changed_is_wired_after_build() -> void:
	var page = _page()
	page._build_curve_painter_overlay()
	_assert_true(page._painter != null, "the overlay builds a painter")
	if page._painter == null:
		page.free()
		return
	_assert_true(page._painter.curve_changed.is_connected(Callable(page, "_on_curve_changed")),
		"curve_changed is wired to the live-refresh handler (not connected to nothing)")
	page.free()


## Firing curve_changed re-seeks at the PARKED frame — the preview re-folds the sim
## where the author left the playhead, so fresh curve samples flow into the render.
func _test_curve_changed_reseeks_at_the_parked_frame() -> void:
	var page = _page()
	page._build_curve_painter_overlay()
	page._timeline.set_playhead(5)
	page._host.seeks.clear()
	page._painter.curve_changed.emit(_stroke())
	_assert_true(page._host.seeks.size() >= 1, "a curve edit re-seeks the preview")
	if not page._host.seeks.is_empty():
		_assert_eq(page._host.seeks.back(), 5, "…at the parked frame (re-fold in place)")
	page.free()


## The inversion: a committed stroke on a USE SITE's curve routes through the choke
## point, addressed by that private curve's index, carrying the whole painted array as
## the raw. That is what buys undo and the JSON save — and it is only safe to do because
## the curve is private now, so the write moves one param on one emitter.
func _test_a_committed_stroke_is_a_session_edit() -> void:
	var page = _page()
	page._build_curve_painter_overlay()
	page._open_param_curve(0, "Spread · curve")
	page._host.applies.clear()
	var stroke: Array = _stroke()
	page._painter.curve_changed.emit(stroke)
	_assert_eq(page._host.applies.size(), 1, "one stroke is ONE session edit (one undo entry)")
	if page._host.applies.is_empty():
		page.free()
		return
	var rec: Dictionary = page._host.applies[0]
	_assert_eq(String(rec["field_ref"].get("channel", "")), "curve",
		"…on the curve channel")
	_assert_eq(int(rec["field_ref"].get("curve_index", -1)), 0,
		"…addressed by the use site's own private curve index")
	_assert_eq(Array(rec["new_raw"]).size(), 160, "…carrying the whole painted curve")
	_assert_eq(int(Array(rec["new_raw"])[7]), int(stroke[7]), "…exactly as painted")
	page.free()


## A stroke with no bound use site (the painter panel built but never opened on a param)
## records NOTHING rather than writing to some arbitrary index — an unaddressed edit is a
## bug, and the honest response is to refresh the preview and stop.
func _test_a_stroke_outside_a_use_site_records_nothing() -> void:
	var page = _page()
	page._build_curve_painter_overlay()
	page._host.applies.clear()
	page._painter.curve_changed.emit(_stroke())
	_assert_eq(page._host.applies.size(), 0, "an unaddressed stroke records no edit")
	page.free()


## The panel says the edit is real. The old note read "Preview only — curve edits aren't
## saved yet"; leaving it up after the commit path landed would be a lie in the direction
## that costs an author work they think they are throwing away.
func _test_painter_panel_says_the_edit_is_saved() -> void:
	var page = _page()
	page._build_curve_painter_overlay()
	_assert_true(not _has_label_containing(page._painter_panel, "Preview only"),
		"the Preview-only note is gone")
	_assert_true(_has_label_containing(page._painter_panel, "saved to the effect"),
		"the painter panel says the stroke is saved (undoable)")
	page.free()


## The studio transport "Fit H" / "Fit W" buttons flip the global sparkline display
## toggles (height re-fit vs absolute; width trim vs whole) and reflect state in their
## labels. Global so every sparkline shares one scale — comparable across rows.
func _test_fit_toggles_flip_the_sparkline_globals() -> void:
	var Sparkline = load("res://src/effects/studio/EffectCurveSparkline.gd")
	var h0: bool = Sparkline.display_normalize_height
	var w0: bool = Sparkline.display_trim_width
	var page = _page()
	page._build_transport()

	page._toggle_fit_height()
	_assert_true(Sparkline.display_normalize_height == (not h0), "Fit H flips the height global")
	_assert_true("Fit H" in String(page._fit_h_btn.text), "the Fit H button labels its state")
	page._toggle_fit_width()
	_assert_true(Sparkline.display_trim_width == (not w0), "Fit W flips the width global")
	_assert_true("Fit W" in String(page._fit_w_btn.text), "the Fit W button labels its state")

	# Restore the globals so later tests / the app start from the default.
	Sparkline.display_normalize_height = h0
	Sparkline.display_trim_width = w0
	page.free()


# --- helpers --------------------------------------------------------------

## A painted 160-sample stroke in the painter's 0-255 grid alphabet.
func _stroke() -> Array:
	var out: Array = []
	for i in range(160):
		out.append((i * 255) / 159)
	return out


func _has_label_containing(node: Node, needle: String) -> bool:
	if node == null:
		return false
	if node is Label and needle in String((node as Label).text):
		return true
	for c in node.get_children():
		if _has_label_containing(c, needle):
			return true
	return false


func _page():
	var page = Page.new()
	var ed = _effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	page._host = host
	return page


func _effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	# One curve so a use site has something to open the painter on. Post-explode an index
	# is a private array position, so index 0 here is "the first (only) use site's curve".
	var zeros: Array[float] = []
	zeros.resize(160)
	zeros.fill(0.0)
	ed.curves.append(EffectCurve.from_array(zeros, 0))
	return ed


class _FakeHost extends RefCounted:
	var seeks: Array = []
	var applies: Array = []
	func studio_seek(f: int) -> void:
		seeks.append(f)
	func studio_apply_edit(field_ref: Dictionary, new_raw, defer_refold = false) -> Dictionary:
		applies.append({"field_ref": field_ref, "new_raw": new_raw})
		return {}


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
