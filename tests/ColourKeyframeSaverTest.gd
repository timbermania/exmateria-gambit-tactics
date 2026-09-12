extends Node
## Slice 5 — the game-JSON save half of colour-keyframe authoring (ADR-0089 colour-keyframe
## amendment, decision 9). The game LOADS from JSON (EffectData.load_from_directory), so
## persisting the forked curves to curves.json and repointing emitters.json by FULL INDEX makes
## an authored colour work in-game. The byte-exact BIN pack + ≤16-slot reconciliation is deferred
## to #292; this is the JSON half only, mirroring the Effect*Saver two-half pattern.
##
## This proves:
##   • to_curves_json serializes the whole (possibly forked) curve table as [{index, values}]
##     with values renormalized to 0-255 — the exact shape EffectData.load_from_directory parses;
##   • patch_curve_addresses repoints BOTH of an emitter's curve address dicts — the param
##     `curves` and `color_curves` — by full index, while preserving every other emitter field
##     byte-for-byte (present-keys-only, like the emitter saver). Both, because since the
##     ADR-0089 curve-ownership amendment the explode repoints every use site, not just colour:
##     writing one dict and not the other would leave a curves.json its own emitters.json no
##     longer indexes correctly;
##   • the round-trip is faithful: reloading the serialized curves.json (÷255) reproduces the
##     authored muxed colour within one 8-bit step — the forked, appended curve survives to disk.
##
## Run: godot --path . --quit-after 30 res://tests/ColourKeyframeSaverTest.tscn

const ColourKeyframeSaver = preload("res://src/effects/studio/ColourKeyframeSaver.gd")
const ColourKeyframeSession = preload("res://src/effects/studio/ColourKeyframeSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve
const ColourMux = preload("res://src/effects/studio/ColourMux.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_curves_json_shape_and_renormalize()
	_test_patch_repoints_both_curve_address_dicts_preserving_other_keys()
	_test_forked_curve_round_trips_through_json()

	print("\n=== ColourKeyframeSaverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourKeyframeSaverTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourKeyframeSaverTest")
		get_tree().quit(0)


## to_curves_json emits one {index, values} per curve, values renormalized float→0-255.
func _test_curves_json_shape_and_renormalize() -> void:
	var ed = EffectDataClass.new()
	ed.curves.append(EffectCurveClass.from_array(_const_arr(0.0), 0))
	ed.curves.append(EffectCurveClass.from_array(_const_arr(1.0), 1))
	ed.curves.append(EffectCurveClass.from_array(_const_arr(0.4), 2))  # 0.4*255 = 102
	var arr: Array = ColourKeyframeSaver.to_curves_json(ed)
	_assert_eq(arr.size(), 3, "one entry per curve")
	_assert_eq(int(arr[0]["index"]), 0, "index 0")
	_assert_eq(int(arr[2]["index"]), 2, "index 2")
	_assert_eq(int(arr[0]["values"][0]), 0, "0.0 → 0")
	_assert_eq(int(arr[1]["values"][0]), 255, "1.0 → 255")
	_assert_eq(int(arr[2]["values"][10]), 102, "0.4 → 102")
	_assert_eq((arr[0]["values"] as Array).size(), 160, "160 samples")


## patch_curve_addresses repoints BOTH address dicts by full index and leaves every other key
## intact. The param addresses matter as much as the colour ones: post-explode they are private
## indices past the ROM's 15 slots, and a curves.json saved beside stale param addresses would
## reload every param curve as some other use site's shape.
func _test_patch_repoints_both_curve_address_dicts_preserving_other_keys() -> void:
	var original := [
		{"anim_index": 7, "color_curves": {"r": 0, "g": 0, "b": 0},
			"curves": {"spread": 6, "drag": -1}, "flags": {"x": true}},
		{"anim_index": 3, "color_curves": {"r": 0, "g": 2, "b": 2},
			"curves": {"spread": 5, "drag": -1}, "spread": 99},
	]
	var ed = EffectDataClass.new()
	var em0 = EffectEmitterClass.new()
	em0.color_curves = {"r": 14, "g": 15, "b": 16}
	em0.curves = {"spread": 17, "drag": -1}          # exploded past the ROM's 15 slots
	var em1 = EffectEmitterClass.new()
	em1.color_curves = {"r": 0, "g": 2, "b": 2}
	em1.curves = {"spread": 5, "drag": -1}
	ed.emitters.append(em0)
	ed.emitters.append(em1)

	var patched: Array = ColourKeyframeSaver.patch_curve_addresses(original, ed)
	_assert_eq(int(patched[0]["color_curves"]["r"]), 14, "em0 R repointed")
	_assert_eq(int(patched[0]["color_curves"]["g"]), 15, "em0 G repointed")
	_assert_eq(int(patched[0]["color_curves"]["b"]), 16, "em0 B repointed")
	_assert_eq(int(patched[0]["curves"]["spread"]), 17, "em0 param address repointed too")
	_assert_eq(int(patched[0]["curves"]["drag"]), -1, "…and a use site with no curve stays -1")
	_assert_eq(int(patched[0]["anim_index"]), 7, "em0 anim_index preserved")
	_assert_true(bool(patched[0]["flags"]["x"]), "em0 flags preserved")
	_assert_eq(int(patched[1]["color_curves"]["g"]), 2, "em1 unchanged")
	_assert_eq(int(patched[1]["curves"]["spread"]), 5, "em1 param address unchanged")
	_assert_eq(int(patched[1]["spread"]), 99, "em1 other key preserved")


## End-to-end: an authored keyframe forks + compiles, the saver serializes, and reloading the
## curves.json (÷255) reproduces the authored muxed colour within one 8-bit step.
func _test_forked_curve_round_trips_through_json() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.6, 1.0, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	var picked := Color(0.4, 0.3, 0.5, 1.0)
	sess.place(80, picked)
	sess.apply()

	var arr: Array = ColourKeyframeSaver.to_curves_json(ed)
	var em = ed.emitters[1]
	var ri := int(em.color_curves["r"])
	var gi := int(em.color_curves["g"])
	var bi := int(em.color_curves["b"])
	# Reload the way the game does: value ÷ 255.
	var rv := float(arr[ri]["values"][80]) / 255.0
	var gv := float(arr[gi]["values"][80]) / 255.0
	var bv := float(arr[bi]["values"][80]) / 255.0
	var muxed: Color = ColourMux.mux(Color(rv, gv, bv, 1.0), s)
	_assert_near(muxed.r, picked.r, "round-trip R within 1/255")
	_assert_near(muxed.g, picked.g, "round-trip G within 1/255")
	_assert_near(muxed.b, picked.b, "round-trip B within 1/255")


func _fixture() -> EffectDataClass:
	var ed = EffectDataClass.new()
	ed.curves.append(EffectCurveClass.from_array(_const_arr(0.3), 0))
	ed.curves.append(EffectCurveClass.from_array(_const_arr(0.5), 1))
	ed.curves.append(EffectCurveClass.from_array(_const_arr(0.6), 2))
	var em0 = EffectEmitterClass.new()
	em0.color_curves = {"r": 0, "g": 0, "b": 0}
	em0.flags = {"color_curve_enabled": true}
	var em1 = EffectEmitterClass.new()
	em1.color_curves = {"r": 0, "g": 1, "b": 2}
	em1.flags = {"color_curve_enabled": true}
	ed.emitters.append(em0)
	ed.emitters.append(em1)
	return ed


func _const_arr(v: float) -> Array:
	var a: Array = []
	a.resize(160)
	a.fill(v)
	return a


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _assert_eq(got: int, expected: int, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, expected %d)" % [label, got, expected])


## Within one 8-bit quantization step (the honest limit of a 0-255 curve).
func _assert_near(got: float, expected: float, label: String) -> void:
	if absf(got - expected) <= 1.0 / 255.0 + 0.0005:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
