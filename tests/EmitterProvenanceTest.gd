extends Node
## TDD guard for incoming-edge provenance (ADR-0073) — the INVERSE of a link, shown in the
## bare-emitter header. Asserts every edge that reaches an emitter is enumerated as a
## clickable reverse-nav row: keyframe refs (→ span target), on-death/mid-life parents
## (→ emitter target); and that an emitter with NO static edge shows a flagged, NON-link
## note ("may spawn via callback at runtime") rather than a fabricated link OR the old
## misleading "shared by 0". Callback edges are not statically derivable (documented limit).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterProvenanceTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Projector = preload("res://src/effects/studio/EmitterTargetProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_all_incoming_edges_enumerated_as_links()
	_test_orphan_emitter_shows_flagged_non_link_note()
	_test_header_carries_provenance_and_no_frames()

	print("\n=== EmitterProvenanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterProvenanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterProvenanceTest")
		get_tree().quit(0)


## Emitter 2 is reached by two keyframes (emitter_id 3), an on-death parent (emitter 0),
## and a mid-life parent (emitter 1). All four edges appear as clickable rows.
func _test_all_incoming_edges_enumerated_as_links() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var rows := Model.emitter_provenance(ed, score, 2)

	var kf_links: Array = []
	var death_links: Array = []
	var mid_links: Array = []
	for r in rows:
		if not r.has("link"):
			continue
		match r.get("label", ""):
			"Spawned by kf": kf_links.append(r["link"]["target"])
			"Death-child of": death_links.append(r["link"]["target"])
			"Mid-life-child of": mid_links.append(r["link"]["target"])

	_assert_eq(kf_links.size(), 2, "two keyframe edges → two span links")
	for t in kf_links:
		_assert_eq(Target.kind(t), "span", "a keyframe edge links to a span target")
	_assert_eq(death_links.size(), 1, "one on-death parent edge")
	_assert_true(death_links.size() == 1 and Target.equals(death_links[0], Target.emitter(0)),
		"the death-parent edge links to emitter 0")
	_assert_eq(mid_links.size(), 1, "one mid-life parent edge")
	_assert_true(mid_links.size() == 1 and Target.equals(mid_links[0], Target.emitter(1)),
		"the mid-life-parent edge links to emitter 1")


## Emitter 1 spawns a child but is itself reached by nothing static → the honest note,
## NOT "shared by 0 events" and NOT a fabricated link.
func _test_orphan_emitter_shows_flagged_non_link_note() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var rows := Model.emitter_provenance(ed, score, 1)
	_assert_eq(rows.size(), 1, "an emitter with no static incoming edge shows one note row")
	_assert_true(not rows[0].has("link"), "the note is NOT a link")
	_assert_true(str(rows[0].get("value", "")).contains("callback"),
		"the note flags possible runtime callback spawn")


func _test_header_carries_provenance_and_no_frames() -> void:
	var ed = _effect()
	var score := Model.build(ed)
	var rows := Projector.header(Target.emitter(2), ed, score)
	var labels: Array = []
	for r in rows:
		labels.append(r.get("label", ""))
	_assert_true("Emitter" in labels, "header identifies the emitter")
	_assert_true("Spawned by kf" in labels, "header carries the keyframe provenance")
	_assert_true(not ("Frames" in labels), "emitter header still has NO Frames (keyframe-owned)")


# --- fixtures -------------------------------------------------------------

## Two keyframes spawn emitter_id 3 (→ index 2); emitter 0 spawns index 2 on death,
## emitter 1 spawns index 2 at mid-life.
func _effect():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 3}, {"time": 20, "emitter_id": 3}]},
		],
	})
	var em0 = EffectEmitter.new()
	em0.child_emitter_on_death = 2
	var em1 = EffectEmitter.new()
	em1.child_emitter_mid_life = 2
	var em2 = EffectEmitter.new()
	ed.emitters.append(em0)
	ed.emitters.append(em1)
	ed.emitters.append(em2)
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
