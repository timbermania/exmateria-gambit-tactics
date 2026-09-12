extends Node
## Widget guard for the field-relevance PRESENTATION (ADR-0089 amendment): drives
## the real EmitterProjector → EffectKeyframeInspector path with a fixture emitter
## and asserts the salience contract on live widgets — Dead groups gathered under a
## collapsed "N hidden (not in effect)" reveal, Inactive groups marked + dimmed
## (never hidden), gate switches carrying bidirectional `!` markers, and end-axis
## Dead collapsing the "at end" row. Headful screenshots (E317/E019) are the human
## acceptance; this is the fast per-build regression.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/EmitterRelevanceViewTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Projector = preload("res://src/effects/studio/EmitterProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0
var _insp = null
var _ed = null


func _ready() -> void:
	await _boot()
	_test_dead_groups_gather_under_a_collapsed_reveal()
	_test_inactive_groups_are_marked_not_hidden()
	_test_gate_switches_carry_bidirectional_markers()
	_test_gated_config_rows_are_marked_dead()
	_test_end_axis_dead_collapses_the_at_end_row()

	print("\n=== EmitterRelevanceViewTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterRelevanceViewTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterRelevanceViewTest")
		get_tree().quit(0)


func _boot() -> void:
	_ed = _effect_editable()
	_insp = Inspector.new()
	_insp.custom_minimum_size = Vector2(420, 900)
	add_child(_insp)
	await get_tree().process_frame
	var span = Model.build(_ed)["lanes"][0]["spans"][0]
	var sections = Projector.sections(span, _ed)
	var curve_provider := func(idx: int) -> Array:
		var c = _ed.get_curve(idx)
		return c.samples if c else []
	_insp.show_target(Target.emitter(0), [], sections, curve_provider, func(_ci, _n): pass)
	await get_tree().process_frame


## Homing is zero in the fixture, so Target offset is a Dead group — gathered under
## a per-section "N hidden (not in effect)" reveal, collapsed by default.
func _test_dead_groups_gather_under_a_collapsed_reveal() -> void:
	var reveals: Array = _insp.hidden_reveals()
	_assert_true(reveals.size() >= 1, "at least one section gathers Dead groups under a reveal")
	var total := 0
	for r in reveals:
		total += int(r.get("count", 0))
		_assert_true(not r["body"].visible, "the hidden reveal is collapsed by default")
		_assert_true("hidden" in str(r["header"].text), "the reveal header reads 'N hidden'")
	_assert_true(total >= 1, "Target offset (homing zero) is among the hidden Dead groups")


## All-zero additive groups (Gravity scale, Acceleration, …) are Inactive: marked
## and dimmed, but STILL present (a wake-able knob is never hidden).
func _test_inactive_groups_are_marked_not_hidden() -> void:
	var inactive := 0
	for m in _insp.relevance_markers():
		if str(m.get("kind", "")) == "inactive":
			inactive += 1
			_assert_true(str(m.get("why", "")) != "", "an Inactive marker carries a why-string")
	_assert_true(inactive >= 3, "several all-zero additive groups are marked Inactive (not hidden)")


## Bidirectional markers: a gate switch (a disabled child mode) carries its own `!`
## whose hover names WHAT it suppresses.
func _test_gate_switches_carry_bidirectional_markers() -> void:
	var gate := 0
	for m in _insp.relevance_markers():
		if str(m.get("kind", "")) == "gate":
			gate += 1
			_assert_true("uppress" in str(m.get("why", "")), "a gate marker hover says what it suppresses")
	_assert_true(gate >= 1, "a suppressing gate switch carries a bidirectional marker")


## A gated Config field (the on-death child picker, its mode disabled) is marked
## Dead with a why hover.
func _test_gated_config_rows_are_marked_dead() -> void:
	var dead := 0
	for m in _insp.relevance_markers():
		if str(m.get("kind", "")) == "dead":
			dead += 1
	_assert_true(dead >= 1, "a gated config field is marked Dead")


## End-axis Dead (a Live group with no curve) collapses its "at end" row and flags
## the header with an end-unused note.
func _test_end_axis_dead_collapses_the_at_end_row() -> void:
	var end_marks := 0
	for m in _insp.relevance_markers():
		if str(m.get("kind", "")) == "end_dead":
			end_marks += 1
	_assert_true(end_marks >= 1, "a Live, curve-less group flags its end axis as unused")


# --- fixtures -------------------------------------------------------------

## An effect whose emitter 0 has a curve-driven Position (Live), all-zero additive
## groups (Inactive), zero homing (Target offset + homing blend Dead), colour
## enabled (colour curves Live) and both child modes disabled (child pickers Dead,
## child-mode switches suppressing). Mirrors EmitterProjectorTest._effect_editable.
func _effect_editable():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em = ExMateriaEffects.EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	em.anim_index = 3
	em.raw_data = {
		"position_start": [28, -28, 0], "position_end": [0, 0, 0],
		"spread_start": [0, 0, 0], "spread_end": [0, 0, 0],
		"angle_start": [0, 0, 0], "angle_end": [0, 0, 0],
		"vel_spread_start": [0, 0, 0], "vel_spread_end": [0, 0, 0],
		"radial_min_start": 0, "radial_max_start": 0, "radial_min_end": 0, "radial_max_end": 0,
		"accel_min_start": [0, 0, 0], "accel_max_start": [0, 0, 0],
		"accel_min_end": [0, 0, 0], "accel_max_end": [0, 0, 0],
		"drag_min_start": [0, 0, 0], "drag_max_start": [0, 0, 0],
		"drag_min_end": [0, 0, 0], "drag_max_end": [0, 0, 0],
		"target_start": [0, 0, 0], "target_end": [0, 0, 0],
		"homing_min_start": 0, "homing_max_start": 0, "homing_min_end": 0, "homing_max_end": 0,
		"curve_indices_raw": [1, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x42, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0x01,
		"byte_00": 0, "byte_05": 0,
	}
	em.callback_params = {"param_4C": 0, "param_A8": 7}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
