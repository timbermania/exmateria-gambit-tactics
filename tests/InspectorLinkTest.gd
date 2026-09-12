extends Node
## TDD guard for the `link` field + navigate callback (ADR-0073) — the mechanism that
## turns a reference (child-on-death, the span's Emitter row) into a followable handle.
## Asserts: (1) the model emits `link`-shaped fields for the child-emitter Config rows and
## the span Event's Emitter row, with the right InspectionTarget; (2) the inspector renders
## them as clickable buttons that fire the navigate callback with that exact target;
## (3) a "none" child stays a plain const (not a link).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/InspectorLinkTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_child_ref_is_a_link_to_the_child_emitter()
	_test_none_child_stays_a_const()
	_test_span_event_emitter_row_is_a_link()
	_test_inspector_link_button_fires_navigate()
	_test_live_child_edge_renders_suppress_checkbox()
	_test_suppress_checkbox_seeded_from_provider()
	_test_authored_off_edge_has_no_checkbox()

	print("\n=== InspectorLinkTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] InspectorLinkTest")
		get_tree().quit(1)
	else:
		print("[PASS] InspectorLinkTest")
		get_tree().quit(0)


## Emitter 0 spawns emitter 2 on death → its Config "Child on death" row is a link to
## InspectionTarget.emitter(2), the fix for the dead-end "Child on death: 5" integer.
func _test_child_ref_is_a_link_to_the_child_emitter() -> void:
	var ed = _effect_with_child(2, -1)
	var field := _config_field(ed, 0, "Child on death")
	_assert_eq(field.get("shape", ""), "link", "a spawned child ref is a link")
	_assert_true(Target.equals(field.get("target", {}), Target.emitter(2)),
		"the link targets the child emitter's bare view")


func _test_none_child_stays_a_const() -> void:
	var ed = _effect_with_child(2, -1)
	var field := _config_field(ed, 0, "Child mid-life")
	_assert_eq(field.get("shape", ""), "const", "a 'none' child is a plain const, not a link")
	_assert_eq(str(field.get("value", "")), "none", "'none' child reads 'none'")


## From a keyframe span, the Event's Emitter row is a link into the shared emitter, so
## you can drill from the timeline into the emitter's full params (not just read its id).
func _test_span_event_emitter_row_is_a_link() -> void:
	var ed = _effect_with_child(-1, -1)
	var score := Model.build(ed)
	var target := Target.span(score["lanes"][0]["spans"][0]["id"])
	var secs := Model.inspector_sections(target, ed, score)
	var emitter_field := {}
	for f in secs[0].get("fields", []):
		if f.get("name", "") == "Emitter":
			emitter_field = f
	_assert_eq(emitter_field.get("shape", ""), "link", "the Event Emitter row is a link")
	_assert_true(Target.equals(emitter_field.get("target", {}), Target.emitter(0)),
		"the Event link targets the referenced emitter (index 0)")


## The rendered link button fires the navigate callback with its target when pressed.
func _test_inspector_link_button_fires_navigate() -> void:
	var ed = _effect_with_child(2, -1)
	var insp = Inspector.new()
	add_child(insp)
	var got := {"target": {}}
	# Inspect emitter 0 (the bare view) so the Config child-on-death link is present.
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}), Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass, func(t): got["target"] = t)
	var found := false
	for b in insp.link_buttons():
		if b.text.begins_with("emitter 2"):
			b.pressed.emit()
			found = true
			break
	_assert_true(found, "the child-on-death link renders a button")
	_assert_true(Target.equals(got["target"], Target.emitter(2)),
		"pressing the link navigates to the child emitter target")


## ADR-0075: a LIVE child edge (index set AND authored flag on) renders a suppression
## checkbox beside the link. Checked (provider says not-suppressed) → unchecking fires the
## toggle callback with (parent_index, edge, suppressed=true).
func _test_live_child_edge_renders_suppress_checkbox() -> void:
	var ed = _effect_with_child(2, -1)
	ed.emitters[0].flags = {"child_death_enabled": true}
	var insp = Inspector.new()
	add_child(insp)
	var got := {"calls": []}
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}), Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false,
		func(p, e, s): got["calls"].append([p, e, s]))
	var toggles: Array = insp.child_toggles()
	_assert_eq(toggles.size(), 1, "a live child edge renders exactly one suppress checkbox")
	if toggles.is_empty():
		return
	var cb = toggles[0]
	_assert_true(cb.button_pressed, "checkbox starts CHECKED (spawning) when not suppressed")
	# Simulate the user unchecking it.
	cb.button_pressed = false
	_assert_eq(got["calls"].size(), 1, "unchecking fires the toggle callback once")
	_assert_true(got["calls"][0] == [0, "death", true],
		"toggle carries (parent index 0, edge 'death', suppressed true)")


## The checkbox's initial state is seeded from the suppressed-state provider: a suppressed
## edge shows UNCHECKED.
func _test_suppress_checkbox_seeded_from_provider() -> void:
	var ed = _effect_with_child(2, -1)
	ed.emitters[0].flags = {"child_death_enabled": true}
	var insp = Inspector.new()
	add_child(insp)
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}), Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return true,   # provider: this edge IS suppressed
		func(_p, _e, _s): pass)
	var toggles: Array = insp.child_toggles()
	_assert_eq(toggles.size(), 1, "still one checkbox on the live edge")
	if not toggles.is_empty():
		_assert_true(not toggles[0].button_pressed, "a suppressed edge shows the checkbox UNCHECKED")


## An authored-OFF edge (index set, flag off) is a plain link with no checkbox (D1).
func _test_authored_off_edge_has_no_checkbox() -> void:
	var ed = _effect_with_child(2, -1)  # flags default empty → child_death_enabled false
	var insp = Inspector.new()
	add_child(insp)
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}), Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass)
	_assert_eq(insp.child_toggles().size(), 0, "an authored-off child edge renders no checkbox")


# --- fixtures -------------------------------------------------------------

## Emitter 0 spawns children per the given on-death / mid-life indices; a curve-driven
## position/color so the group projection is fully populated.
func _effect_with_child(on_death: int, mid_life: int):
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
	em.child_emitter_on_death = on_death
	em.child_emitter_mid_life = mid_life
	ed.emitters.append(em)
	# Pad emitters so a child index like 2 resolves in range for the bare view.
	ed.emitters.append(EffectEmitter.new())
	ed.emitters.append(EffectEmitter.new())
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _config_field(ed, emitter_index: int, name: String) -> Dictionary:
	for group in Model.emitter_view(ed, emitter_index):
		if group.get("title", "") == "Config":
			for f in group.get("params", []):
				if f.get("name", "") == name:
					return f
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
