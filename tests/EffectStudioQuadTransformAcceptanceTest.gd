extends Node
## ACCEPTANCE (headful, real E019): turning a QUAD TRANSFORM knob in the live studio reaches
## the frame's stored corner bytes, as ONE undo entry, through the #255 choke point.
##
## `EffectStudioFrameQuadTransformTest` proves the maths against the whole corpus and
## `EffectStudioFramesetEditTest` proves the projector emits the rows. Neither can see the
## thing most likely to be wrong: `frameset_quad` is not a channel, so a knob turn is
## intercepted in `EffectStudioPage._apply_edit` and lowered as a compound instead of
## dispatched. If that interception were missing, the projector would still emit perfect
## rows, every pure test would still pass, and turning a knob would do NOTHING — silently,
## because an unknown channel returns an empty dictionary rather than raising.
##
## So this file asserts the three things only the live page can answer:
##   1. the row exists in the built inspector as a real editable widget, not just in the
##      projector's return value;
##   2. driving it writes the corners the transform implies;
##   3. ONE undo puts all of them back — not eight presses, and not none.
##
## Skips when E019 assets are absent (gitignored/ROM-derived).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioQuadTransformAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Quad = preload("res://src/effects/studio/FrameQuadTransform.gd")

var _passed: int = 0
var _failed: int = 0
var _reached_end := false


func _ready() -> void:
	await _run()
	# A coroutine that hits a runtime error unwinds SILENTLY, so a clean summary with no
	# assertions is a FAILING run wearing a passing one's clothes.
	if not _reached_end:
		_failed += 1
		print("[FAIL] the run never reached its end — a runtime error unwound it silently")
	print("\n=== EffectStudioQuadTransformAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioQuadTransformAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioQuadTransformAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		_reached_end = true
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	DebugOverlay.show_overlay()
	await _frames(30)

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	# Land on a real frame the same way a click does.
	page._on_frameset_browsed(1)
	await _frames(8)
	var target: Dictionary = page._nav.back()
	_assert_eq(str(target.get("kind", "")), "frame", "the inspection root is a frame target")
	var ref: Dictionary = target.get("ref", {})
	var fs_idx := int(ref.get("frameset_index", -1))
	var fr_idx := int(ref.get("frame_index", -1))
	var frame: Dictionary = page._effect_data.framesets[fs_idx]["frames"][fr_idx]

	# --- (1) The Width row is a real widget in the BUILT inspector. -------------------
	var rows := _rows(page, fs_idx, fr_idx)
	for name in ["Width", "Height", "Rotation", "Shear", "Position X", "Position Y"]:
		_assert_true(rows.has(name), "the built inspector carries a '%s' row" % name)
	if not rows.has("Width"):
		_reached_end = true
		return
	_assert_eq(str(rows["Width"].get("editor", "")), "float",
		"…as a float cell, not a rounded byte")

	# --- (2) Driving it writes the corners the transform implies. --------------------
	var before := _corners(frame)
	var t: Dictionary = Quad.decompose(frame)
	_assert_true(bool(t.get("ok", false)), "the frame's quad decomposes")
	var base: Vector2i = t.get("base", Vector2i.ONE)
	var was_w: float = float(t["scale"].x) * float(base.x)
	var want_w: float = was_w * 2.0
	var expected: Dictionary = Quad.compose(Quad.with_term(t, "width", want_w))

	# The SAME call the ScrubField's `value_changed` makes — the page's mutate entry point,
	# not the commit helper, so the interception itself is what is under test.
	page._apply_edit(rows["Width"]["field_ref"], want_w)
	await _frames(6)

	var after := _corners(frame)
	_assert_true(after != before, "turning the Width knob CHANGED the stored corners")
	for corner in Quad.CORNERS:
		_assert_eq(after.get(corner), expected.get(corner),
			"the '%s' corner is where the transform puts it" % corner)
	var t2: Dictionary = Quad.decompose(frame)
	_assert_true(absf(float(t2["scale"].x) * float(base.x) - want_w) < 1.0,
		"and reading it back gives the width that was typed (%.1f)" % want_w)
	_assert_true(absf(float(t2["rotation"]) - float(t["rotation"])) < 0.01,
		"…with the rotation untouched — one knob moved one term")

	# --- (3) ONE undo puts every corner back. ----------------------------------------
	# The live session the host built for THIS effect — the same object `studio_apply_compound`
	# pushed the entry onto, reached the way the host itself holds it.
	var session = page._host._edit_session
	_assert_true(session != null, "the host has a live edit session")
	_assert_true(session.undo(), "there is an undo entry for the knob turn")
	_assert_true(not session.undo(),
		"…and exactly ONE — a second undo finds nothing, so the eight component writes were "
		+ "recorded as one compound and not as eight scalars")
	await _frames(4)
	_assert_eq(_corners(frame), before,
		"ONE undo restores EVERY corner the knob moved — the turn is one compound, not eight edits")

	_reached_end = true


## The frame's rows as the BUILT inspector has them — read back off the live projector the
## page fed it, keyed by name.
func _rows(page, fs_idx: int, fr_idx: int) -> Dictionary:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	var Registry = load("res://src/effects/studio/InspectorProjectorRegistry.gd")
	var out: Dictionary = {}
	for sec in Registry.sections(Target.frame(fs_idx, fr_idx), page._effect_data, {}):
		for f in sec.get("fields", []):
			out[str(f.get("name", ""))] = f
	return out


func _corners(frame: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for corner in Quad.CORNERS:
		var pair: Array = frame.get("vertices", {}).get(corner, [])
		out[corner] = [int(pair[0]), int(pair[1])] if pair.size() >= 2 else [0, 0]
	return out


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
		print("[FAIL] %s — expected true" % label)
