extends Node
## Integration guard (real Control, bare tree): EffectKeyframeInspector renders a
## selected span through ONE path (ADR-0071) — the header rows
## (EffectScoreModel.inspector_header) plus the projector `[Section]` list
## (inspector_sections) — into aligned grids, and clear() returns to the empty state.
## Thin-glue guard; section CONTENT is locked in the model + projector tests. See
## CONTEXT.md "Keyframe inspector".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectKeyframeInspectorTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_header_rows_rendered()
	_test_clear_returns_to_empty()
	_test_particle_sections_and_sparkline_open()
	_test_action_field_renders_a_button_that_fires_on_action()
	_test_radio_field_renders_a_group_and_fans_value_on_pick()
	_test_preview_action_renders_a_play_button_beside_the_editor()
	_test_long_const_value_wraps_instead_of_stretching()

	print("\n=== EffectKeyframeInspectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectKeyframeInspectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectKeyframeInspectorTest")
		get_tree().quit(0)


func _test_header_rows_rendered() -> void:
	var ed = _effect_with_emitter()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var insp = _inspector()
	insp.show_target(target, Model.inspector_header(target, ed, score), Model.inspector_sections(target, ed, score),
		_curve_provider(ed), func(_a, _b): pass)
	_assert_eq(insp.row_count(), Model.inspector_header(target, ed, score).size(),
		"one grid row per model header row")
	_assert_true(insp.row_count() > 0, "a span yields header rows")


func _test_clear_returns_to_empty() -> void:
	var ed = _effect_with_emitter()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var insp = _inspector()
	insp.show_target(target, Model.inspector_header(target, ed, score), Model.inspector_sections(target, ed, score),
		_curve_provider(ed), func(_a, _b): pass)
	insp.clear()
	_assert_eq(insp.row_count(), 0, "clear() empties the grid")


## A particle span renders the Event section PLUS the shared emitter's four groups
## (five accordion sections), a row per field, and a per-param curve sparkline.
## Pressing an enabled sparkline fires the open callback with THAT param's curve index
## — the seam that launches the painter off a specific param (never the keyframe).
func _test_particle_sections_and_sparkline_open() -> void:
	var insp = _inspector()
	var ed = _effect_with_emitter()
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var opened := {"idx": -1, "name": ""}
	insp.show_target(target, Model.inspector_header(target, ed, score), Model.inspector_sections(target, ed, score),
		_curve_provider(ed),
		func(ci, nm): opened["idx"] = ci; opened["name"] = nm)

	_assert_eq(insp.group_count(), 6, "Event section + five emitter groups (incl. Advanced (raw))")
	_assert_true(insp.param_row_count() > 10, "a row per field across the sections")
	_assert_true(insp.row_count() > 0, "the header rows show above the sections")

	var fired := false
	for s in insp.sparklines():
		if s.is_enabled():
			s.pressed.emit()
			fired = true
			break
	_assert_true(fired, "at least one enabled (curve-driven) sparkline")
	_assert_true(opened["idx"] >= 0, "clicking a sparkline opens that param's curve")
	_assert_eq(opened["name"], "Position", "the open callback carries the param it hangs off")

	insp.clear()
	_assert_eq(insp.group_count(), 0, "clear() drops the sections")
	_assert_eq(insp.param_row_count(), 0, "clear() resets the param-row count")


# --- fixtures -------------------------------------------------------------

## An `action` field (a button, not an edit) renders a Button in its section; pressing it
## fires the host's on_action callback with the field's `action` dict — the seam the
## SoundContainer "Audition sequence" affordance rides. A generic capability, so it lives
## in this thin-glue guard, exercised with a synthetic section (no projector dependency).
func _test_action_field_renders_a_button_that_fires_on_action() -> void:
	var insp = _inspector()
	var captured := {}
	var on_action := func(a): captured.merge(a, true)
	var sections := [{"title": "Sound selection", "fields": [
		{"name": "Audition", "shape": "action", "label": "▶ Audition sequence",
			"action": {"kind": "audition_container", "index": 3}}]}]
	insp.show_target(Target.container(3), [], sections, _null_curves(), func(_a, _b): pass,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass, func(_refs, _col): return Color.BLACK, false, {}, on_action)
	var btns: Array = insp.action_buttons()
	_assert_eq(btns.size(), 1, "the action field rendered one button")
	btns[0].emit_signal("pressed")
	_assert_eq(int(captured.get("index", -1)), 3, "pressing fires on_action with the action's index")
	_assert_eq(str(captured.get("kind", "")), "audition_container", "on_action carries the action kind")


## A `radio` edit field (#289 Pick mode) renders EVERY choice at once as one ButtonGroup
## of CheckBoxes, seeded to the current value WITHOUT fanning an edit; picking another
## row fans that choice's VALUE through the mutate callback with the field's ref.
func _test_radio_field_renders_a_group_and_fans_value_on_pick() -> void:
	var insp = _inspector()
	var edits := []
	var on_mutate := func(ref, raw): edits.append([ref, raw])
	var sections := [{"title": "Sound selection", "fields": [
		{"name": "Pick mode", "shape": "edit", "editor": "radio", "value": 1,
			"choices": [
				{"value": 0, "label": "Always Sound A", "detail": "plays 5, 5, 5…"},
				{"value": 1, "label": "Alternate A / B", "detail": "plays 5, 9, 5, 9…"},
				{"value": 4, "label": "Cycle A / B / C", "detail": "plays 5, 9, 13…"}],
			"field_ref": {"channel": "sound_container", "index": 2, "field": "mode"}}]}]
	insp.show_target(Target.container(2), [], sections, _null_curves(), func(_a, _b): pass,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		on_mutate, func(_refs, _col): return Color.BLACK, false, {}, func(_a): pass)
	var groups: Array = insp.radio_groups()
	_assert_eq(groups.size(), 1, "the radio field rendered one group")
	var group: Array = groups[0]
	_assert_eq(group.size(), 3, "every choice is visible at once")
	_assert_true(not group[0].button_pressed and group[1].button_pressed,
		"seeded to the current value's row")
	_assert_eq(edits.size(), 0, "seeding fans no edit")
	group[2].button_pressed = true   # the author picks Cycle A / B / C
	_assert_eq(edits.size(), 1, "picking a row fans exactly one edit")
	_assert_eq(int(edits[0][1]), 4, "the fanned raw is the choice's VALUE (not its position)")
	_assert_eq(str(edits[0][0].get("field", "")), "mode", "the edit carries the field's ref")


## An edit field carrying a `preview_action` (#289: hear one Sound slot alone) gains a ▶
## button beside its editor; pressing it fires on_action with the preview dict.
func _test_preview_action_renders_a_play_button_beside_the_editor() -> void:
	var insp = _inspector()
	var captured := {}
	var on_action := func(a): captured.merge(a, true)
	var sections := [{"title": "Sound selection", "fields": [
		{"name": "Sound A", "shape": "edit", "editor": "enum", "value": 5,
			"choices": [{"value": 5, "label": "Sound bank entry 4"}],
			"preview_action": {"kind": "audition_sound", "id": 5},
			"field_ref": {"channel": "sound_container", "index": 0, "field": "id_a"}}]}]
	insp.show_target(Target.container(0), [], sections, _null_curves(), func(_a, _b): pass,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass, func(_refs, _col): return Color.BLACK, false, {}, on_action)
	_assert_eq(insp.enum_widgets().size(), 1, "the editor itself still renders")
	var btns: Array = insp.action_buttons()
	_assert_eq(btns.size(), 1, "the preview rendered one ▶ button")
	btns[0].emit_signal("pressed")
	_assert_eq(str(captured.get("kind", "")), "audition_sound", "pressing fires the preview action")
	_assert_eq(int(captured.get("id", -1)), 5, "the preview names the slot's current id")


## A LONG const value wraps inside its column instead of stretching the grid off-screen
## (the defect that shoved the Audition button out of the visible area).
func _test_long_const_value_wraps_instead_of_stretching() -> void:
	var insp = _inspector()
	var long_text := "Modes differ only from the 2nd fire; the studio resets the counter each play, so a single-fire effect always plays Sound A."
	var sections := [{"title": "Sound selection", "fields": [
		{"name": "Note", "shape": "const", "value": long_text}]}]
	insp.show_target(Target.container(0), [], sections, _null_curves(), func(_a, _b): pass)
	var lbl := _find_label_with_text(insp, long_text)
	_assert_true(lbl != null, "the long const value rendered")
	if lbl != null:
		_assert_true(lbl.autowrap_mode != TextServer.AUTOWRAP_OFF, "a long value autowraps")
		_assert_true(lbl.custom_minimum_size.x > 0.0, "a long value has a bounded wrap column")


func _find_label_with_text(node: Node, text: String) -> Label:
	if node is Label and (node as Label).text == text:
		return node
	for c in node.get_children():
		var got := _find_label_with_text(c, text)
		if got != null:
			return got
	return null


func _null_curves() -> Callable:
	return func(_i): return []


func _inspector():
	var insp = Inspector.new()
	add_child(insp)   # triggers _ready → builds the grid
	return insp


## Effect whose particle channel spawns emitter 1 (→ emitter_index 0), with that
## emitter carrying a curve-driven position + color so the sparkline seam is live.
func _effect_with_emitter():
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
	# ADR-0089 reads curve assignment from the RAW nibble storage (raw 1 = curve 0),
	# so the editable projection needs parser-shaped raw_data for a live sparkline.
	em.raw_data = {
		"position_start": [28, -28, 0], "position_end": [0, 0, 0],
		"curve_indices_raw": [1, 0, 0, 0, 0, 0, 0, 0],
	}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _span(ed) -> Dictionary:
	return Model.build(ed)["lanes"][0]["spans"][0]


func _curve_provider(ed) -> Callable:
	return func(i): return ed.get_curve(i).samples if ed.get_curve(i) != null else []


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
