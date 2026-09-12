extends Node
## HEADFUL acceptance guard for the palette TINT result-picker end-to-end (ADR-0087 slice 2).
## Drives the REAL EffectViewer scene → host EffectViewerScene.studio_pick_target → the palette
## branch (PaletteTintSolver) → EffectEditSession choke point → PaletteChannel, on real E317.
## Proves THE FIX: an author who picks a bright colour under a palette tint gets a keyframe whose
## stored bytes fold to that colour — NOT the #266 "seek-color renders the wrong hue" dark shift.
##
## The palette preview surface is a whole CLUT (no single pixel to sample), so the acceptance
## asserts the honest, checkable facts: (1) the returned ACHIEVED colour reads bright red (not a
## near-black darken), and (2) the keyframe's newly-stored bytes forward-fold to that same
## achieved colour — the WYSIWYG contract. A non-additive keyframe mode is coerced to additive
## (mode 0) first so red is reachable and the assertion is deterministic across effects.
##
## Kept OUT of run_all_tests.sh (needs the gitignored E317 extract; acceptance precedent).
## Run: <GODOT> --path . --quit-after 200 res://tests/EffectPaletteTintPickAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const TintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_pick_red_reads_red_on_real_E317()

	print("\n=== EffectPaletteTintPickAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteTintPickAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteTintPickAcceptanceTest")
		get_tree().quit(0)


func _test_pick_red_reads_red_on_real_E317() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 extract absent — palette tint pick acceptance skipped")
		return
	page._load_effect(dir)
	await _frames(20)

	var found := _first_palette_keyframe(scn._current_effect.effect_data)
	if found.is_empty():
		print("[SKIP] no palette keyframe on E317 — palette tint pick acceptance skipped")
		return
	var phase: String = found["phase"]
	var channel_name: String = found["channel_name"]
	var index: int = found["index"]
	var kf = found["kf"]

	# Coerce to an additive mode so bright red is reachable and the check is deterministic.
	kf.blend_mode = 0
	kf.ctrl = (int(kf.ctrl) & 0x80) | 0
	kf.enabled = true
	kf.ctrl = int(kf.ctrl) | 0x80

	var refs := {
		"r": _ref(phase, channel_name, index, "r"),
		"g": _ref(phase, channel_name, index, "g"),
		"b": _ref(phase, channel_name, index, "b"),
	}

	var achieved: Color = scn.studio_pick_target(refs, Color(1.0, 0.0, 0.0))
	await _frames(2)

	# (1) The surface reaches bright red — the #266 dark shift is gone.
	_assert_true(achieved.r > 0.9, "picked red reads BRIGHT red (achieved.r=%.3f)" % achieved.r)
	_assert_true(achieved.g < 0.1, "green reads near-black (achieved.g=%.3f)" % achieved.g)
	_assert_true(achieved.b < 0.1, "blue reads near-black (achieved.b=%.3f)" % achieved.b)

	# (2) The keyframe's STORED bytes forward-fold to exactly that achieved colour (WYSIWYG).
	var refold: Color = TintSolver.result(int(kf.blend_mode), int(kf.rgb.x), int(kf.rgb.y), int(kf.rgb.z))
	_assert_true(refold.is_equal_approx(achieved),
		"the stored bytes forward-fold to the achieved colour (%s vs %s)" % [str(refold), str(achieved)])

	# And the honest tell: the stored RED byte is a POSITIVE (lightening) signed delta, not the
	# raw 255 the #266 gradient picker fanned (which sign-extends to −1, a darken).
	_assert_true(_sb(int(kf.rgb.x)) > 0, "the stored red byte is a positive lightening delta, not raw-255→−1")


# --- helpers ----------------------------------------------------------------

func _first_palette_keyframe(data) -> Dictionary:
	if data == null or data.palette == null:
		return {}
	for phase in data.palette.channels.keys():
		for channel_name in PaletteDataClass.ALL_CHANNELS:
			var ch = data.palette.get_channel(phase, channel_name)
			if ch == null:
				continue
			for i in range(ch.keyframes.size()):
				return {"phase": phase, "channel_name": channel_name, "index": i, "kf": ch.keyframes[i]}
	return {}


func _ref(phase: String, channel_name: String, index: int, field: String) -> Dictionary:
	return {"channel": "palette", "context": phase, "channel_name": channel_name,
		"event_index": index, "field": field}


func _sb(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
