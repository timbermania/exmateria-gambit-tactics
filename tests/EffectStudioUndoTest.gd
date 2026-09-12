extends Node
## HEADFUL acceptance guard for Ctrl+Z undo end-to-end (wires the undo machinery to a
## keybinding). Drives the REAL EffectViewer scene → EffectStudioPage._unhandled_key_input
## → host EffectViewerScene.studio_undo → EffectEditSession.undo, on real E317.
##
## A camera Source edit SPLITS a coalesced keyframe (structural). Feeding a Ctrl+Z key
## event to the page must unwind it: the angle event's Source reverts (which re-coalesces
## it with its position sibling) and the author's selection survives the re-project. A
## non-shortcut key must NOT undo.
##
## Run: <GODOT> --path . --quit-after 120 res://tests/EffectStudioUndoTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")

const SRC_MAP := 0x0C0
const SRC_CASTER := 0x140      # E317 for_each angle@10's source before the edit

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_ctrl_z_reverts_a_camera_split_on_real_E317()

	print("\n=== EffectStudioUndoTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioUndoTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioUndoTest")
		get_tree().quit(0)


func _test_ctrl_z_reverts_a_camera_split_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		# E317 is gitignored ROM-derived content — skip cleanly in CI (KindSelector precedent).
		print("[SKIP] E317 extract absent — undo acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	var span := _coalesced_camera_angle_span(page)
	if span.is_empty():
		_fail("found a coalesced camera angle span")
		return
	var span_id := String(span.get("id", ""))
	var phase = span.get("phase", "")

	page._timeline.select_span(span_id)
	page._on_span_selected(span_id)
	await _frames(2)

	# Edit Source (CASTER → MAP): splits the coalesced keyframe.
	var source_ref := _source_field_ref(page, span)
	if source_ref.is_empty():
		_fail("resolved the Source cell's field_ref")
		return
	page._apply_edit(source_ref, SRC_MAP)
	await _frames(4)
	var after_edit := CameraLowering.parse(page._effect_data.camera.get_table(phase))
	_assert_eq(int(after_edit["angle"][0]["source_bits"]), SRC_MAP, "the edit changed angle Source to MAP")

	# A non-shortcut key must NOT undo.
	page._unhandled_key_input(_key(KEY_X, true))
	await _frames(2)
	var after_noise := CameraLowering.parse(page._effect_data.camera.get_table(phase))
	_assert_eq(int(after_noise["angle"][0]["source_bits"]), SRC_MAP, "Ctrl+X does not undo")

	# Ctrl+Z unwinds the split: angle Source reverts to CASTER and re-coalesces with position.
	page._unhandled_key_input(_key(KEY_Z, true))
	await _frames(4)
	var after_undo := CameraLowering.parse(page._effect_data.camera.get_table(phase))
	_assert_eq(int(after_undo["angle"][0]["source_bits"]), SRC_CASTER,
		"Ctrl+Z reverted the angle Source to CASTER")
	_assert_eq(int(after_undo["position"][0]["source_bits"]), SRC_CASTER,
		"the position sibling is unchanged (the split unwound)")
	_assert_eq(page._timeline.selected_span_id(), span_id,
		"the selection survives the undo re-project")


# --- helpers ----------------------------------------------------------------

func _coalesced_camera_angle_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if lane.get("kind", "") != "camera":
			continue
		if not String(lane.get("id", "")).ends_with(":angle"):
			continue
		for sp in lane.get("spans", []):
			var mask := int(sp.get("fields", {}).get("channel_mask", 0))
			if mask & ~1 != 0 and mask & 1 != 0:
				return sp
	return {}


func _source_field_ref(page, span: Dictionary) -> Dictionary:
	for sec in Model.span_sections(span, page._effect_data):
		for f in sec.get("fields", []):
			if String(f.get("name", "")) == "Source":
				return f.get("field_ref", {})
	return {}


func _key(keycode: int, ctrl: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.ctrl_pressed = ctrl
	e.pressed = true
	return e


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _fail(label: String) -> void:
	_failed += 1
	print("[FAIL] %s" % label)
