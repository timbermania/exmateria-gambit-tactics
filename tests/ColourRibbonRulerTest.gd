extends Node
## Slice C — the frame ruler under the Colour ribbon: tick marks + frame numbers so you
## can read "at frame N the particle is this colour". Reuses the studio ruler-step ladder
## ([1,5,10,30,60,...], ticks ≥ ~48 px apart). Pure step/tick math + the view seams
## (opt-in via set_curves show_ruler, grows the control's height).
##
## Run: godot --path . --quit-after 6 res://tests/ColourRibbonRulerTest.tscn

const EffectCurveClass = ExMateriaEffects.EffectCurve
const ColourRibbon = preload("res://src/effects/studio/ColourRibbon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_ruler_step_ladder()
	_test_ruler_ticks()
	_test_view_opt_in_and_height()

	print("\n=== ColourRibbonRulerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourRibbonRulerTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourRibbonRulerTest")
		get_tree().quit(0)


## Smallest ladder step whose pixel spacing (width/n per frame) is ≥ 48 px.
func _test_ruler_step_ladder() -> void:
	_assert_eq(ColourRibbon.ruler_step(12, 240.0), 5, "12 frames / 240px → step 5 (100px)")
	_assert_eq(ColourRibbon.ruler_step(160, 320.0), 30, "160 frames / 320px → step 30 (60px)")
	_assert_eq(ColourRibbon.ruler_step(12, 600.0), 1, "wide enough → step 1 (50px)")


## Interior ticks are multiples of the step below n (n itself is drawn as its own end marker).
func _test_ruler_ticks() -> void:
	_assert_eq(Array(ColourRibbon.ruler_ticks(12, 240.0)), [0, 5, 10], "12/240 ticks")
	_assert_eq(Array(ColourRibbon.ruler_ticks(160, 320.0)), [0, 30, 60, 90, 120, 150], "160/320 ticks")


func _test_view_opt_in_and_height() -> void:
	var c := _curves()
	var ribbon = ColourRibbon.new()

	ribbon.set_curves(c[0], c[1], c[2], true, 12)
	_assert_true(not ribbon.has_frame_ruler(), "ruler off by default")
	var bare_h: float = ribbon.custom_minimum_size.y

	ribbon.set_curves(c[0], c[1], c[2], true, 12, true)
	_assert_true(ribbon.has_frame_ruler(), "show_ruler=true → ruler on")
	_assert_true(ribbon.custom_minimum_size.y > bare_h, "the ruler adds height under the bands")

	ribbon.free()


func _curves() -> Array:
	return [
		EffectCurveClass.from_array(_ramp(1.0), 0),
		EffectCurveClass.from_array(_ramp(0.5), 1),
		EffectCurveClass.from_array(_ramp(0.25), 2),
	]


func _ramp(scale: float) -> Array:
	var a: Array = []
	a.resize(160)
	for i in range(160):
		a[i] = scale * float(i) / 159.0
	return a


func _assert_eq(got, expected, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, expected %s)" % [label, str(got), str(expected)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
