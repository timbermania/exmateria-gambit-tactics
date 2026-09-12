extends Node
## TDD guard for the particle-timeline ENABLE / RETARGET verbs (ADR-0089 particle_timeline
## amendment, slice 3) — the span inspector's two scalar controls, plus the score's dimmed
## drawing of a disabled span.
##
## Enabled toggles emitter_id ↔ 0, stashing the remembered N on a transient keyframe field
## (session-only — a saved-disabled span reloads as a gap). Emitter retargets which emitter a
## span fires, editable even while disabled (it sets the remembered N). The score still emits a
## DISABLED span (dimmed + dashed + selectable), consulting the stash — a genuine gap draws
## nothing. The inspector's Event section carries an Enabled checkbox + a Fires-emitter picker.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleTimelineEnableRetargetTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Projector = preload("res://src/effects/studio/EmitterProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_retarget_a_live_span_sets_the_emitter_id()
	_test_disable_stashes_the_id_and_zeroes_emitter()
	_test_enable_restores_the_stashed_id()
	_test_retarget_while_disabled_sets_the_remembered_id()
	_test_enable_a_cold_gap_is_a_noop()
	_test_disable_undoes_to_enabled()
	_test_retarget_undoes_to_the_prior_emitter()
	_test_score_draws_a_disabled_span_dimmed_and_selectable()
	_test_score_omits_a_genuine_gap()
	_test_inspector_has_enabled_and_retarget_rows()
	_test_inspector_enabled_row_reflects_a_disabled_span()

	print("\n=== ParticleTimelineEnableRetargetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleTimelineEnableRetargetTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleTimelineEnableRetargetTest")
		get_tree().quit(0)


## Retarget a LIVE span from emitter index 0 (id 1) to index 2 (id 3).
func _test_retarget_a_live_span_sets_the_emitter_id() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	var res: Dictionary = session.apply_edit(_ref(1, "emitter_index"), 2)
	_assert_eq(int(kf.emitter_id), 3, "retarget writes emitter_id = index + 1")
	_assert_eq(res.get("before_raw", -9), 0, "the prior 0-based index is recorded for undo")
	_assert_eq(res.get("after_raw", -9), 2, "the applied index comes back")
	_assert_eq(res.get("invalidates_sim", false), true, "a retarget changes what spawns → re-fold")


## Disable moves emitter_id → 0 (the ROM's only off) and stashes the prior id.
func _test_disable_stashes_the_id_and_zeroes_emitter() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	var res: Dictionary = session.apply_edit(_ref(1, "enabled"), 0)
	_assert_eq(int(kf.emitter_id), 0, "disable zeroes emitter_id (a real gap in the ROM)")
	_assert_eq(int(kf.remembered_emitter_id), 1, "…remembering the prior id on the transient stash")
	_assert_eq(res.get("before_raw", -9), 1, "the pre-edit enabled state (1) is recorded")


## Enable after a disable restores the stashed id losslessly and clears the stash.
func _test_enable_restores_the_stashed_id() -> void:
	var data := _fake_data([[0, 0], [10, 2]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	session.apply_edit(_ref(1, "enabled"), 0)
	session.apply_edit(_ref(1, "enabled"), 1)
	_assert_eq(int(kf.emitter_id), 2, "enable restores the remembered id")
	_assert_eq(int(kf.remembered_emitter_id), 0, "…and clears the stash")


## Retarget while DISABLED sets the remembered id; re-enabling then fires the new emitter.
func _test_retarget_while_disabled_sets_the_remembered_id() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	session.apply_edit(_ref(1, "enabled"), 0)     # disable (remembered = 1)
	session.apply_edit(_ref(1, "emitter_index"), 4)   # retarget while off → remembered = 5
	_assert_eq(int(kf.emitter_id), 0, "the span stays disabled through a retarget")
	_assert_eq(int(kf.remembered_emitter_id), 5, "…but its remembered target moved to id 5")
	session.apply_edit(_ref(1, "enabled"), 1)
	_assert_eq(int(kf.emitter_id), 5, "re-enabling fires the retargeted emitter")


## Enabling a cold gap (no remembered id) restores nothing and records no undo.
func _test_enable_a_cold_gap_is_a_noop() -> void:
	var data := _fake_data([[0, 0], [10, 0]])
	var session = Session.new(data)

	var res: Dictionary = session.apply_edit(_ref(1, "enabled"), 1)
	_assert_true(res.get("no_edit", false), "enabling a cold gap is a no-op")
	_assert_true(not session.undo(), "…and records nothing on the undo stack")


func _test_disable_undoes_to_enabled() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	session.apply_edit(_ref(1, "enabled"), 0)
	_assert_true(session.undo(), "the disable is undoable")
	_assert_eq(int(kf.emitter_id), 1, "undo re-enables — the stashed id comes back")


func _test_retarget_undoes_to_the_prior_emitter() -> void:
	var data := _fake_data([[0, 0], [10, 1]])
	var session = Session.new(data)
	var kf = _chan(data).keyframes[1]

	session.apply_edit(_ref(1, "emitter_index"), 5)
	_assert_true(session.undo(), "the retarget is undoable")
	_assert_eq(int(kf.emitter_id), 1, "undo restores the prior emitter (id 1)")


## A disabled span is STILL projected — dimmed, dashed, and selectable — so the author can
## re-enable/retarget it. Its color differs from the live emitter colour.
func _test_score_draws_a_disabled_span_dimmed_and_selectable() -> void:
	var data = _effect([[0, 0], [10, 1]])
	var session = Session.new(data)
	var live_span: Dictionary = _first_span(data)
	session.apply_edit(_ref(1, "enabled"), 0)   # disable it
	var span: Dictionary = _first_span(data)

	_assert_true(not span.is_empty(), "a disabled span is still emitted (not dropped like a gap)")
	_assert_eq(bool(span.get("disabled", false)), true, "…flagged disabled")
	_assert_eq(int(span.get("emitter_index", -9)), 0, "…keeping its remembered emitter identity")
	_assert_eq(String(span.get("fields", {}).get("border", "")), "dashed", "…drawn with a null-span dashed outline")
	_assert_true(Color(span.get("color", Color.WHITE)) != Color(live_span.get("color", Color.BLACK)),
		"…dimmed to a different colour than the live span")


## A genuine gap (emitter_id 0, nothing remembered) projects NO span.
func _test_score_omits_a_genuine_gap() -> void:
	var data = _effect([[0, 0], [10, 0]])
	_assert_true(_first_span(data).is_empty(), "a cold gap draws nothing")


## The span inspector's Event section carries the Enabled checkbox + the Fires-emitter picker,
## both addressing the particle channel at the span's flat address.
func _test_inspector_has_enabled_and_retarget_rows() -> void:
	var data = _effect([[0, 0], [10, 1]])
	var fields := _event_fields(data)

	var enabled := _row(fields, "Enabled")
	_assert_eq(enabled.get("editor", ""), "enum", "Enabled is an editable checkbox (enum)")
	_assert_eq(int(enabled.get("value", -9)), 1, "…seeded on for a live span")
	_assert_eq(String(enabled.get("field_ref", {}).get("channel", "")), "particle", "…lowering through the particle channel")
	_assert_eq(String(enabled.get("field_ref", {}).get("field", "")), "enabled", "…the enabled field")
	_assert_eq(int(enabled.get("field_ref", {}).get("event_index", -9)), 1, "…at the span's raw keyframe index")

	var fires := _row(fields, "Fires emitter")
	_assert_eq(fires.get("editor", ""), "enum", "Fires emitter is a retarget picker (enum)")
	_assert_eq(int(fires.get("value", -9)), 0, "…seeded with the current 0-based emitter index")
	_assert_eq(String(fires.get("field_ref", {}).get("field", "")), "emitter_index", "…editing emitter_index")
	_assert_eq(fires.get("choices", []).size(), 2, "…one choice per defined emitter")


## For a disabled span the Enabled checkbox reads off; the picker still shows the remembered id.
func _test_inspector_enabled_row_reflects_a_disabled_span() -> void:
	var data = _effect([[0, 0], [10, 1]])
	var session = Session.new(data)
	session.apply_edit(_ref(1, "enabled"), 0)
	var fields := _event_fields(data)
	_assert_eq(int(_row(fields, "Enabled").get("value", -9)), 0, "Enabled reads OFF for a disabled span")
	_assert_eq(int(_row(fields, "Fires emitter").get("value", -9)), 0, "…the picker still shows the remembered emitter")


# --- fixtures -------------------------------------------------------------

func _ref(index: int, field: String) -> Dictionary:
	return {"channel": "particle", "context": "for_each", "channel_index": 0,
		"event_index": index, "field": field}


func _chan(data):
	return data.timeline.get_channels("for_each")[0]


## Bare timeline data (no emitters) — enough for the channel-level enable/retarget tests.
func _fake_data(kfs: Array) -> RefCounted:
	var data := _FakeData.new()
	data.timeline = _timeline(kfs)
	return data


func _timeline(kfs: Array):
	var kf_dicts: Array = []
	for pair in kfs:
		kf_dicts.append({"time": int(pair[0]), "emitter_id": int(pair[1]), "action_flags": 0})
	return TimelineDataClass.from_json({
		"header": {"phase1_duration": 0},
		"particle_channels": [{
			"context": "for_each", "channel_index": 0,
			"max_keyframe": kfs.size() - 1, "keyframes": kf_dicts,
		}],
	})


## A real EffectData with two emitters (for the score + projector tests, which read emitters).
func _effect(kfs: Array):
	var ed = EffectDataClass.new()
	ed.timeline = _timeline(kfs)
	for i in range(2):
		var em = EffectEmitter.new()
		em.curves = {"position": 0}
		em.color_curves = {"r": 0}
		ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _first_span(data) -> Dictionary:
	for lane in Model.build(data)["lanes"]:
		if lane.get("kind", "") == "particle":
			for s in lane.get("spans", []):
				return s
	return {}


func _event_fields(data) -> Array:
	var span := _first_span(data)
	for sec in Projector.sections(span, data):
		if sec.get("title", "") == "Event":
			return sec.get("fields", [])
	return []


func _row(fields: Array, name: String) -> Dictionary:
	for f in fields:
		if f.get("name", "") == name:
			return f
	return {}


class _FakeData extends RefCounted:
	var timeline = null
	var screen = null
	var palette = null
	var camera = null


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
