extends Node
## TDD guard for the inspector threading the emitter-elapsed playhead marker to the RIGHT
## sparklines (ADR-0089 amendment). Only sparklines in an "emitter"-clocked section (Emitter
## / Particle · born-with) carry the span-anchored marker; an "age"-clocked section's
## sparklines (Particle · over-life colour/homing) must opt OUT — they sample per-particle
## and get their own mechanism later. `update_marker` is the cheap continuous-refresh path
## (the playhead sweeps every transport tick) — it re-sets the line without a full rebuild.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectKeyframeInspectorMarkerTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_marker_lands_on_emitter_clocked_only()
	_test_age_clocked_sparkline_has_no_marker()
	_test_update_marker_refreshes_without_rebuild()

	print("\n=== EffectKeyframeInspectorMarkerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectKeyframeInspectorMarkerTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectKeyframeInspectorMarkerTest")
		get_tree().quit(0)


func _test_marker_lands_on_emitter_clocked_only() -> void:
	var insp = _shown({"present": true, "index": 25, "lap": 0, "state": "in"})
	var marked: Array = insp.marker_sparklines()
	_assert_eq(marked.size(), 1, "exactly the one emitter-clocked curve sparkline is marked")
	if marked.size() == 1:
		_assert_true(marked[0].has_marker(), "the emitter-clocked sparkline carries the marker")
		_assert_eq(marked[0].marker_index(), 25, "…at the sampled index")
	insp.queue_free()


func _test_age_clocked_sparkline_has_no_marker() -> void:
	var insp = _shown({"present": true, "index": 25, "lap": 0, "state": "in"})
	# The over-life (age) colour sparkline is in the full list but NOT among the marked ones.
	var age_unmarked := false
	for s in insp._sparklines:
		if not (s in insp.marker_sparklines()) and not s.has_marker():
			age_unmarked = true
	_assert_true(age_unmarked, "an age-clocked sparkline draws no emitter marker")
	insp.queue_free()


func _test_update_marker_refreshes_without_rebuild() -> void:
	var insp = _shown({"present": true, "index": 25, "lap": 0, "state": "in"})
	var before: Array = insp.marker_sparklines().duplicate()
	insp.update_marker({"present": true, "index": 77, "lap": 0, "state": "in"})
	_assert_eq(insp.marker_sparklines(), before, "same sparkline instances (no rebuild)")
	if insp.marker_sparklines().size() == 1:
		_assert_eq(insp.marker_sparklines()[0].marker_index(), 77, "the swept marker moved to the new index")
	insp.queue_free()


# --- fixture --------------------------------------------------------------

## Show one emitter-clocked curve section + one age-clocked colour section, with `marker`.
func _shown(marker: Dictionary):
	var insp = Inspector.new()
	add_child(insp)
	var sections := [
		{"title": "Emitter", "clock": "emitter", "fields": [
			{"name": "Position · curve", "shape": "curve_only", "curve_index": 0, "used_n": -1, "enabled": true}]},
		{"title": "Particle · over-life", "clock": "age", "fields": [
			{"name": "Color (R) · curve", "shape": "curve_only", "curve_index": 0, "used_n": -1, "enabled": true}]},
	]
	var provider := func(_i): return [0.0, 0.25, 0.5, 0.75, 1.0]
	var on_open := func(_ci, _n): pass
	insp.show_target(Target.span("x"), [], sections, provider, on_open,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass, func(_refs, _c): return Color.BLACK, false, marker)
	return insp


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
