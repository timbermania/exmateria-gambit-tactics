extends Node
## HEADFUL acceptance for the palette BYTE-COVERAGE completions (ADR-0087): the Enabled toggle
## and the signed-Δ "No tint" no-op, end-to-end through the REAL EffectViewer → EffectStudioPage
## → host EffectViewerScene.studio_apply_edit → EffectEditSession → PaletteChannel, on real E317.
## Confirms the two byte-coverage gaps the author hit are closed:
##   * Enabled (ctrl bit-7) is authorable: disabling clears the bit AND the keyframe STAYS a
##     visible/selectable span on its lane (a spacer — inert hatch, third amendment) — not dropped — so it can be
##     re-enabled; re-enabling restores the bit.
##   * "No tint" writes Δ = (0,0,0), which in an additive mode is a genuine NO-OP: the folded
##     result equals the reference (no colour shift) — the "do nothing" the mid-grey picker
##     couldn't surface.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectPaletteByteCoverageAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_byte_coverage_on_real_E317()

	print("\n=== EffectPaletteByteCoverageAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteByteCoverageAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteByteCoverageAcceptanceTest")
		get_tree().quit(0)


func _test_byte_coverage_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — byte-coverage acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	var found := _first_enabled_palette_span(page)
	if found.is_empty():
		print("[SKIP] no enabled palette span on E317 — byte-coverage acceptance skipped")
		return
	var span: Dictionary = found
	var sid := String(span.get("id", ""))
	var phase := String(span.get("phase", ""))
	var channel_name := String(span.get("fields", {}).get("channel", ""))
	var index := int(span.get("keyframe_index", -1))
	var ch = scn._current_effect.effect_data.palette.get_channel(phase, channel_name)
	var kf = ch.get_keyframe(index)

	# --- Enabled toggle: disable, confirm the span survives as a SPACER (ADR-0087 third
	# amendment: the null tween renders as the inert hatch; dashed = Gradient only) ----------
	page._apply_edit(_ref(phase, channel_name, index, "enabled"), 0)
	await _frames(4)
	_assert_true(not kf.enabled, "disabling clears the enabled flag")
	var still: Dictionary = Model.find_span(page._timeline._score, sid)
	_assert_true(not still.is_empty(), "the disabled keyframe STAYS a span (selectable, not dropped)")
	_assert_true(bool(still.get("fields", {}).get("spacer", false)), "…drawn as a spacer (inert hatch, not dashed)")

	page._apply_edit(_ref(phase, channel_name, index, "enabled"), 1)
	await _frames(4)
	_assert_true(kf.enabled, "re-enabling restores the enabled flag")

	# --- No tint: additive mode + Δ=(0,0,0) is a genuine no-op ------------------------------
	page._apply_edit(_ref(phase, channel_name, index, "blend_mode"), 0)   # additive
	page._apply_edit(_ref(phase, channel_name, index, "r"), 0)
	page._apply_edit(_ref(phase, channel_name, index, "g"), 0)
	page._apply_edit(_ref(phase, channel_name, index, "b"), 0)
	await _frames(4)
	_assert_eq(kf.rgb, Vector3i.ZERO, "No tint writes Δ = (0,0,0)")
	var folded: Color = TintSolver.result(0, 0, 0, 0)
	_assert_true(folded.is_equal_approx(Color(TintSolver.REFERENCE.x, TintSolver.REFERENCE.y, TintSolver.REFERENCE.z, 1.0)),
		"Δ=0 in an additive mode is a NO-OP (the reference is unchanged)")

	# --- The +/- deltas are the source of truth: a real picker pick MATERIALIZES into them, and
	# the real No-tint button zeroes them + moves the picker to the no-tint colour ------------
	page._timeline.select_span(sid)
	page._on_span_selected(sid)
	await _frames(4)
	var insp = page._inspector
	var boxes: Array = insp.signed_rgb_widgets()
	var pickers: Array = insp.pick_widgets()
	if boxes.size() == 3 and not pickers.is_empty():
		pickers[0].color = Color(0.95, 0.05, 0.05)
		pickers[0].color_changed.emit(Color(0.95, 0.05, 0.05))
		await _frames(4)
		var materialized: bool = int(boxes[0].value) != 0 or int(boxes[1].value) != 0 or int(boxes[2].value) != 0
		_assert_true(materialized, "a picker pick MATERIALIZES into the +/- delta boxes (source of truth)")
		_assert_eq(int(boxes[0].value), _sb(int(kf.rgb.x)), "the R box shows the stored signed delta")

		insp.signed_rgb_reset_button().pressed.emit()
		await _frames(4)
		_assert_eq(int(boxes[0].value), 0, "No tint zeroes the R delta box")
		_assert_eq(int(boxes[1].value), 0, "…G box")
		_assert_eq(int(boxes[2].value), 0, "…B box")
		_assert_true(pickers[0].color.is_equal_approx(TintSolver.result(int(kf.blend_mode), 0, 0, 0)),
			"…and the picker colour goes to 'whatever no tint is'")


func _sb(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


# --- helpers ----------------------------------------------------------------

func _first_enabled_palette_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "palette":
			continue
		for sp in lane.get("spans", []):
			if bool(sp.get("fields", {}).get("enabled", false)):
				return sp
	return {}


func _ref(phase: String, channel_name: String, index: int, field: String) -> Dictionary:
	return {"channel": "palette", "context": phase, "channel_name": channel_name,
		"event_index": index, "field": field}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
		print("[FAIL] %s" % label)
