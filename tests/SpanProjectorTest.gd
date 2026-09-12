extends Node
## TDD guard for the SPAN target-kind projector (ADR-0073) — the behavior-preserving
## refactor of the pre-0073 `inspector_header`/`inspector_sections` onto the generic
## target seam. Asserts a span TARGET, routed through the registry, still yields the
## archetype-independent header (Kind/Phase/Frames/Authored) and the particle span's
## Event section + shared emitter groups (ADR-0071 behavior, now reached via {kind:"span"}).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SpanProjectorTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const SpanProjector = preload("res://src/effects/studio/SpanProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_span_header_rows()
	_test_span_sections_event_then_emitter_groups()
	_test_registry_dispatch_matches_direct()
	_test_missing_span_is_inert()

	print("\n=== SpanProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpanProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpanProjectorTest")
		get_tree().quit(0)


func _test_span_header_rows() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var rows := SpanProjector.header(target, ed, score)
	var labels: Array = []
	for r in rows:
		labels.append(r.get("label", ""))
	_assert_eq(labels, ["Kind", "Phase", "Frames", "Authored"],
		"span header keeps the four archetype-independent rows")


func _test_span_sections_event_then_emitter_groups() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var secs := SpanProjector.sections(target, ed, score)
	# 5 emitter groups since ADR-0089: Emitter / Particle · born-with / Particle · over-life /
	# Config / Advanced (raw). The Event section still LEADS — that is the ADR-0071 contract
	# this guards; the group count moves as the emitter surface grows.
	_assert_eq(secs.size(), 6, "Event section + 5 emitter groups (ADR-0071 order, ADR-0089 groups)")
	_assert_eq(secs[0].get("title", ""), "Event", "particle span leads with the Event section")


## The model's target dispatcher (inspector_header/sections via the registry) must
## produce EXACTLY what the projector produces directly — the seam adds no divergence.
func _test_registry_dispatch_matches_direct() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	_assert_eq(Model.inspector_header(target, ed, score), SpanProjector.header(target, ed, score),
		"registry header == projector header")
	_assert_eq(Model.inspector_sections(target, ed, score).size(),
		SpanProjector.sections(target, ed, score).size(),
		"registry sections == projector sections")


func _test_missing_span_is_inert() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var target := Target.span("no-such-span")
	_assert_eq(SpanProjector.header(target, ed, score), [], "absent span → empty header")
	_assert_eq(SpanProjector.sections(target, ed, score), [], "absent span → empty sections")


# --- fixtures -------------------------------------------------------------

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
