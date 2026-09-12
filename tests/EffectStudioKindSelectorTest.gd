extends Node
## TDD guard for the screen tween KIND selector (Blend ↔ Gradient variant, CONTEXT §Variant).
## The "one event, selectable subtype" model: a `choice` editor in the event section flips the
## variant and the fields reshape. Two seams here (the encoder is guarded in EffectEditSessionTest,
## the projector cell in ScreenTweenProjectorTest):
##
##   (1) EffectKeyframeInspector renders an "edit"/"choice" cell as an OptionButton seeded to the
##       current index; selecting an item fans to on_mutate(field_ref, index). Exposed via a new
##       choice_widgets() seam (distinct from pick_widgets(), the target-colour picker).
##   (2) ACCEPTANCE (headful): flipping the Kind on a real live effect RESHAPES the inspector
##       (Blend's RGB gives way to Gradient's Top/Bottom stops) AND updates the timeline span's
##       kind — the structural re-project. Skipped if the ROM extract is absent.
##
## Run: <GODOT> --path . --quit-after 40 res://tests/EffectStudioKindSelectorTest.tscn

const ScreenData = ExMateriaEffects.ScreenData

const Projector = preload("res://src/effects/studio/ScreenTweenProjector.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_inspector_renders_kind_choice_and_fans_to_on_mutate()
	await _test_flipping_kind_reshapes_inspector_and_timeline()

	print("\n=== EffectStudioKindSelectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioKindSelectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioKindSelectorTest")
		get_tree().quit(0)


# --- Seam 1: inspector choice editor --------------------------------------

func _test_inspector_renders_kind_choice_and_fans_to_on_mutate() -> void:
	var secs := Projector.sections(_blend_kf(), {"context": "for_each", "event_index": 0})
	var insp = Inspector.new()
	add_child(insp)

	var calls: Array = []
	insp.show_target(Target.span("screen:for_each#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, val): calls.append([ref, val]))

	var choices: Array = insp.choice_widgets()
	# Two choice widgets since ADR-0087 dec. 11: the Kind selector plus the harmonized Enabled
	# toggle. The Kind cell is emitted first; the fan assertion below pins its field_ref.
	_assert_eq(choices.size(), 2, "the section renders the Kind + Enabled choice widgets")
	if choices.is_empty():
		return

	var ob = choices[0]
	_assert_eq(ob.item_count, 2, "the Kind selector has two choices")
	_assert_eq(ob.selected, ScreenData.ScreenMode.BLEND, "seeded to the current kind (Blend = index 1)")

	# Choosing Gradient (index 0) fans to the mutate callback once, with the kind field_ref.
	ob.selected = 0
	ob.item_selected.emit(0)
	_assert_eq(calls.size(), 1, "selecting a kind fans to on_mutate once")
	if calls.is_empty():
		return
	_assert_true(calls[0][0].get("field", "") == "kind" and int(calls[0][1]) == ScreenData.ScreenMode.GRADIENT,
		"commits the chosen kind index to the kind field_ref")


# --- Seam 2: ACCEPTANCE — flip reshapes inspector + timeline (headful) -----

## Selecting a real Blend screen span shows the RGB editor; flipping the Kind selector to
## Gradient RESHAPES the inspector (RGB editors gone) and updates the timeline span's kind —
## the structural re-project through the live page → host → choke point.
func _test_flipping_kind_reshapes_inspector_and_timeline() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			dir = d
	page._load_effect(dir)
	await _frames(20)

	var span_id := _first_screen_span_of_kind(page, "Blend")
	_assert_true(span_id != "", "E001 has a Blend screen span")
	if span_id == "":
		return
	page._on_span_selected(span_id)
	await _frames(2)

	# Park the playhead mid-effect BEFORE the structural edit. The reported bug: flipping
	# Kind resets the play mode (playhead jumps back to 0, selection lost). It must survive.
	var parked := 12
	page._seek(parked)
	await _frames(2)
	_assert_eq(page._timeline.get_playhead(), parked, "playhead parked before the flip")

	_assert_eq(page._inspector.pick_widgets().size(), 1, "Blend shows the target-colour picker")
	var kind_sel: Array = page._inspector.choice_widgets()
	_assert_true(kind_sel.size() >= 1, "the Kind selector is present")
	if kind_sel.is_empty():
		return

	# Flip Blend → Gradient via the real selector widget.
	var ob = kind_sel[0]
	ob.selected = ScreenData.ScreenMode.GRADIENT
	ob.item_selected.emit(ScreenData.ScreenMode.GRADIENT)
	await _frames(4)

	_assert_eq(page._inspector.pick_widgets().size(), 0,
		"after flip to Gradient the target-colour picker is gone (fields reshaped)")
	_assert_true(page._inspector.choice_widgets().size() >= 1, "the Kind selector remains")
	_assert_eq(_span_kind(page, span_id), "Grad",
		"the timeline span's kind updated to Gradient (structural refresh)")
	# The structural refresh must PRESERVE the author's place, not reload as a fresh doc.
	_assert_eq(page._timeline.get_playhead(), parked,
		"flipping Kind PRESERVES the parked playhead (not reset to 0)")
	_assert_eq(page._timeline.selected_span_id(), span_id,
		"flipping Kind keeps the same span selected")
	if page._host and page._host.has_method("studio_current_frame"):
		_assert_eq(page._host.studio_current_frame(), parked,
			"the host instance is re-seeked to the parked frame (UI↔host agree)")


# --- fixtures -------------------------------------------------------------

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _first_screen_span_of_kind(page, kind: String) -> String:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			if str(sp.get("fields", {}).get("screen_kind", "")) == kind:
				return str(sp.get("id", ""))
	return ""


func _span_kind(page, span_id: String) -> String:
	for lane in page._timeline._score.get("lanes", []):
		for sp in lane.get("spans", []):
			if str(sp.get("id", "")) == span_id:
				return str(sp.get("fields", {}).get("screen_kind", ""))
	return ""


func _blend_kf():
	var kf = ScreenData.Keyframe.new()
	kf.mode = ScreenData.ScreenMode.BLEND
	kf.blend_mode = 5
	kf.duration_frames = 8
	kf.ctrl = 133
	kf.start_r_raw = 26; kf.start_g_raw = 31; kf.start_b_raw = 36
	kf.start_color = Color(26 / 255.0, 31 / 255.0, 36 / 255.0)
	return kf


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
