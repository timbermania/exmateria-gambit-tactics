extends Node
## TDD guard for EmitterTargetProjector (ADR-0073) — the BARE emitter view reached from a
## child-ref link / provenance edge / browser. Asserts it shows ONLY the four emitter_view
## groups (NO Event section) under an emitter header with NO Phase/Frames (those are
## keyframe-owned), that the groups mirror emitter_view, and that an out-of-range index is
## inert. Contrast EmitterProjectorTest, which guards the particle-SPAN view (Event first).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterProjectorBareTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Projector = preload("res://src/effects/studio/EmitterTargetProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_bare_view_is_the_four_groups_no_event()
	_test_groups_mirror_emitter_view()
	_test_header_has_no_phase_or_frames()
	_test_out_of_range_is_inert()
	_test_curve_sparkline_dims_by_the_widest_firing()

	print("\n=== EmitterProjectorBareTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterProjectorBareTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterProjectorBareTest")
		get_tree().quit(0)


func _test_bare_view_is_the_four_groups_no_event() -> void:
	var ed = _effect()
	var secs := Projector.sections(Target.emitter(0), ed, {})
	_assert_eq(secs.size(), 5, "bare emitter view is the five groups incl. Advanced (raw) (no Event section)")
	var titles: Array = []
	for s in secs:
		titles.append(s.get("title", ""))
	_assert_true(not ("Event" in titles), "bare emitter view has NO Event section")


func _test_groups_mirror_emitter_view() -> void:
	var ed = _effect()
	var secs := Projector.sections(Target.emitter(0), ed, {})
	var got: Array = []
	for s in secs:
		got.append(s.get("title", ""))
		_assert_true(s.has("fields"), "section '%s' exposes rows under 'fields'" % s.get("title", ""))
	var want: Array = []
	for g in Model.emitter_view(ed, 0):
		want.append(g.get("title", ""))
	_assert_eq(got, want, "bare emitter sections mirror emitter_view titles/order")


func _test_header_has_no_phase_or_frames() -> void:
	var ed = _effect()
	var rows := Projector.header(Target.emitter(0), ed, {})
	var labels: Array = []
	for r in rows:
		labels.append(r.get("label", ""))
	_assert_true(not ("Phase" in labels), "emitter header carries NO Phase (keyframe-owned)")
	_assert_true(not ("Frames" in labels), "emitter header carries NO Frames (keyframe-owned)")
	_assert_true("Emitter" in labels, "emitter header identifies the emitter")


func _test_out_of_range_is_inert() -> void:
	var ed = _effect()
	_assert_eq(Projector.sections(Target.emitter(99), ed, {}), [], "out-of-range index → empty sections")
	_assert_eq(Projector.header(Target.emitter(99), ed, {}), [], "out-of-range index → empty header")


## Decision 5, browser surface: with no span selected, the bare emitter view
## dims evolution sparklines by the WIDEST firing span's duration (tooltip says
## so). The projector receives the score, so the window comes from real spans.
func _test_curve_sparkline_dims_by_the_widest_firing() -> void:
	var ed = _effect_editable_two_firings()
	var score: Dictionary = Model.build(ed)
	var widest := 0
	for lane in score["lanes"]:
		if lane.get("kind", "") != "particle":
			continue
		for span in lane["spans"]:
			if int(span.get("emitter_index", -1)) == 0:
				widest = maxi(widest, int(span["end"]) - int(span["start"]))
	_assert_true(widest > 0, "fixture has firing spans of real duration")

	var secs := Projector.sections(Target.emitter(0), ed, score)
	var row := _row_in(secs, "Emitter", "Position · curve")
	var spark: Dictionary = row.get("cells", [{}, {}])[1]
	_assert_eq(spark.get("editor", ""), "curve", "curve row carries its sparkline cell")
	_assert_eq(int(spark.get("used_n", -9)), widest, "browser window = the widest firing span")
	_assert_true("widest" in str(spark.get("tooltip", "")), "tooltip notes it is the widest firing")


# --- fixtures -------------------------------------------------------------

## _effect() plus editable raw storage and TWO keyframes firing emitter 0 with
## different durations (times 10 and 20 in an 8-frame phase → unequal spans).
func _effect_editable_two_firings():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1},
				{"time": 20, "emitter_id": 1}]},
		],
	})
	var em = EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	em.raw_data = {
		"position_start": [28, -28, 0], "position_end": [0, 0, 0],
		"curve_indices_raw": [1, 0, 0, 0, 0, 0, 0, 0],
	}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


## The row named `name` inside the section titled `title`, or {}.
func _row_in(secs: Array, title: String, name: String) -> Dictionary:
	for s in secs:
		if s.get("title", "") != title:
			continue
		for f in s.get("fields", []):
			if f.get("name", "") == name:
				return f
	return {}

func _effect():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em = EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


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
