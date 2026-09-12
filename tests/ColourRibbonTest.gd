extends Node
## Slices 2 + 3 — the Colour ribbon: the read-only resolved-colour bar under an
## emitter's three R/G/B colour sparklines (CONTEXT.md "Colour ribbon").
##
## Slice 2 (pure): frame_colors(cr, cg, cb, used_n, trim) resolves the OPAQUE colour
## the curves produce at each frame, windowed to the emitter's used region so it aligns
## 1:1 under the sparklines — its frame count equals EffectCurveSparkline.windowed_samples
## for the same window. It reads through EffectCurve.sample_rgb, so it can't drift from
## the renderer.
##
## Slice 3 (view): set_curves feeds the three curves + enabled + window; the ribbon is
## HIDDEN entirely when colour is disabled, and colors() follows the SAME global trim
## toggle the sparklines read (EffectCurveSparkline.display_trim_width) so they move
## together.
##
## Run: godot --path . --quit-after 30 res://tests/ColourRibbonTest.tscn

const EffectCurveClass = ExMateriaEffects.EffectCurve
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")
const ColourRibbon = preload("res://src/effects/studio/ColourRibbon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_frame_colors_match_sample_rgb_opaque()
	_test_frame_count_aligns_with_sparkline_window()
	_test_trim_off_and_unknown_window_are_whole_curve()
	_test_view_hidden_when_disabled()
	_test_view_colors_follow_global_trim_toggle()
	_test_mux_green_base_locks_out_red_and_blue()
	_test_mux_white_base_is_identity()

	print("\n=== ColourRibbonTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourRibbonTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourRibbonTest")
		get_tree().quit(0)


func _curves() -> Array:
	return [
		EffectCurveClass.from_array(_ramp(1.0), 0),
		EffectCurveClass.from_array(_flat(0.25), 1),
		EffectCurveClass.from_array(_ramp(0.5), 2),
	]


## Each band's colour is exactly EffectCurve.sample_rgb at that frame, forced opaque.
func _test_frame_colors_match_sample_rgb_opaque() -> void:
	var c := _curves()
	var cols: Array = ColourRibbon.frame_colors(c[0], c[1], c[2], 48, true)
	_assert_true(cols.size() == 48, "trim window 48 → 48 bands")
	for f in [0, 12, 47]:
		var want: Color = EffectCurveClass.sample_rgb(c[0], c[1], c[2], f)
		_assert_approx(cols[f].r, want.r, "band %d R ≡ sample_rgb" % f)
		_assert_approx(cols[f].g, want.g, "band %d G ≡ sample_rgb" % f)
		_assert_approx(cols[f].b, want.b, "band %d B ≡ sample_rgb" % f)
		_assert_approx(cols[f].a, 1.0, "band %d opaque (a=1)" % f)


## The ribbon's band count is the sparkline's windowed sample count for the same
## window — so column X lines up under column X of the curves.
func _test_frame_count_aligns_with_sparkline_window() -> void:
	var c := _curves()
	for used_n in [24, 48, 100]:
		var ribbon_n: int = ColourRibbon.frame_colors(c[0], c[1], c[2], used_n, true).size()
		var spark_n: int = Sparkline.windowed_samples(c[0].samples, used_n).size()
		_assert_true(ribbon_n == spark_n,
			"window %d: ribbon %d ≡ sparkline %d" % [used_n, ribbon_n, spark_n])


## Trim off, animation-driven (-1), and wrapping (>=160) windows all span the whole
## 160-frame curve — mirroring windowed_samples' fallbacks.
func _test_trim_off_and_unknown_window_are_whole_curve() -> void:
	var c := _curves()
	_assert_true(ColourRibbon.frame_colors(c[0], c[1], c[2], 48, false).size() == 160,
		"trim OFF → whole 160")
	_assert_true(ColourRibbon.frame_colors(c[0], c[1], c[2], -1, true).size() == 160,
		"unknown window (-1) → whole 160")
	_assert_true(ColourRibbon.frame_colors(c[0], c[1], c[2], 160, true).size() == 160,
		"wrapping window (160) → whole 160")


## The view draws nothing when the emitter's colour is disabled.
func _test_view_hidden_when_disabled() -> void:
	var c := _curves()
	var ribbon = ColourRibbon.new()

	ribbon.set_curves(c[0], c[1], c[2], true, 48)
	_assert_true(ribbon.is_shown(), "colour enabled → ribbon shown")

	ribbon.set_curves(c[0], c[1], c[2], false, 48)
	_assert_true(not ribbon.is_shown(), "colour disabled → ribbon hidden")

	ribbon.free()


## colors() honours the SAME global trim toggle the sparklines read, so flipping it
## rescales both together.
func _test_view_colors_follow_global_trim_toggle() -> void:
	var c := _curves()
	var ribbon = ColourRibbon.new()
	ribbon.set_curves(c[0], c[1], c[2], true, 48)

	var prev: bool = Sparkline.display_trim_width
	Sparkline.display_trim_width = true
	_assert_true(ribbon.colors().size() == 48, "toggle ON → trimmed to 48")
	Sparkline.display_trim_width = false
	_assert_true(ribbon.colors().size() == 160, "toggle OFF → whole 160")
	Sparkline.display_trim_width = prev

	ribbon.free()


## MUX (the render truth, ALBEDO = sprite.rgb * modulate.rgb): the resolved curve colour is
## multiplied by the emitter's representative sprite base. A green-only sprite (R=0, B=0 —
## E138 idx0) can NEVER show red or blue, no matter what the curves say — so every band's R
## and B are 0 while the sparklines wiggle. This is why editing curves left the particle green.
func _test_mux_green_base_locks_out_red_and_blue() -> void:
	var c := _curves()   # cr ramps R up, cb ramps B up — both non-zero mid-window
	var green := Color(0.0, 0.75, 0.0)
	var cols: Array = ColourRibbon.frame_colors(c[0], c[1], c[2], 48, true, green)
	for f in [1, 24, 47]:
		var modulate: Color = EffectCurveClass.sample_rgb(c[0], c[1], c[2], f)
		_assert_approx(cols[f].r, 0.0, "band %d R muxed to 0 (sprite has no red)" % f)
		_assert_approx(cols[f].b, 0.0, "band %d B muxed to 0 (sprite has no blue)" % f)
		_assert_approx(cols[f].g, green.g * modulate.g, "band %d G = base.g * modulate.g" % f)


## The default (white) base is the identity multiply — no base supplied ⇒ the ribbon shows
## the pure curve colour, exactly as before (backward compatible).
func _test_mux_white_base_is_identity() -> void:
	var c := _curves()
	var plain: Array = ColourRibbon.frame_colors(c[0], c[1], c[2], 48, true)
	var white: Array = ColourRibbon.frame_colors(c[0], c[1], c[2], 48, true, Color.WHITE)
	for f in [0, 24, 47]:
		_assert_approx(white[f].r, plain[f].r, "band %d white base ≡ pure curve R" % f)
		_assert_approx(white[f].g, plain[f].g, "band %d white base ≡ pure curve G" % f)
		_assert_approx(white[f].b, plain[f].b, "band %d white base ≡ pure curve B" % f)


func _ramp(scale: float) -> Array:
	var a: Array = []
	a.resize(160)
	for i in range(160):
		a[i] = scale * float(i) / 159.0
	return a


func _flat(v: float) -> Array:
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


func _assert_approx(got: float, expected: float, label: String) -> void:
	if is_equal_approx(got, expected) or absf(got - expected) < 0.0005:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
