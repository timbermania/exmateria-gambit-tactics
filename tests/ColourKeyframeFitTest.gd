extends Node
## Slice 2 — curve → colour-keyframe IMPORT and the compile-down back to dense curves
## (ADR-0089 colour-keyframe amendment, decision 8: "Enter = import, not replace").
##
## Keyframing an emitter that already has a ROM colour curve fits joint colour keyframes
## to its 160 muxed samples (breakpoint detection), so there is no visual jump. This proves:
##   • EXACT for piecewise-linear ROM curves — import then compile_to_curves reproduces
##     the source samples byte-for-byte, and `exact` is true;
##   • keyframes hold the MUXED colour T = S ⊙ curve at each breakpoint frame;
##   • an HONEST-QUANTIZATION tell for genuinely curvy segments — `exact` is false and a
##     bounded `max_error` is reported rather than silently approximating;
##   • compile-down lerps the muxed target LINEARLY then inverse-muxes, so a single dense
##     curve is recovered inside the reachable box.
##
## Run: godot --path . --quit-after 30 res://tests/ColourKeyframeFitTest.tscn

const ColourKeyframeFit = preload("res://src/effects/studio/ColourKeyframeFit.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_piecewise_linear_imports_exactly()
	_test_keyframes_hold_curve_colour()
	_test_every_curve_value_is_authorable()
	_test_curvy_reports_honest_tell()
	_test_the_dead_zone_cannot_starve_the_live_window()
	_test_the_split_keeps_the_tail()
	_test_no_life_is_the_old_global_fit()

	print("\n=== ColourKeyframeFitTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourKeyframeFitTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourKeyframeFitTest")
		get_tree().quit(0)


## A piecewise-linear curve set imports to keyframes at its vertices and compiles back to
## the exact source samples — the "no visual jump" guarantee for the common ROM curves.
func _test_piecewise_linear_imports_exactly() -> void:
	# R: triangle 0→1 @80 →0.  G: flat 0.4.  B: 0 until 40 then ramp to 0.6.
	var cr := EffectCurveClass.from_array(_piecewise([[0, 0.0], [80, 1.0], [159, 0.0]]), 0)
	var cg := EffectCurveClass.from_array(_piecewise([[0, 0.4], [159, 0.4]]), 1)
	var cb := EffectCurveClass.from_array(_piecewise([[0, 0.0], [40, 0.0], [159, 0.6]]), 2)

	var fit: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb)
	_assert_true(fit.get("exact", false), "piecewise-linear import is exact")

	var frames := []
	for kf in fit["keyframes"]:
		frames.append(kf["frame"])
	# The joint breakpoints are the union of every channel's vertices.
	_assert_true(frames.has(0) and frames.has(159), "endpoints kept")
	_assert_true(frames.has(40) and frames.has(80), "interior breakpoints kept")

	var back: Dictionary = ColourKeyframeFit.compile_to_curves(fit["keyframes"])
	for f in [0, 20, 40, 60, 80, 120, 159]:
		_assert_approx(back["r"][f], cr.sample_by_frame(f), "compiled R @%d" % f)
		_assert_approx(back["g"][f], cg.sample_by_frame(f), "compiled G @%d" % f)
		_assert_approx(back["b"][f], cb.sample_by_frame(f), "compiled B @%d" % f)


## Each keyframe stores the CURVE triple — the value the sample table holds — not the muxed
## output (ADR-0089 decision 4, amended 2026-08-21). It used to store `S ⊙ curve`, and the
## sprite texel is out of this module entirely now: nothing here can be given one.
func _test_keyframes_hold_curve_colour() -> void:
	var cr := EffectCurveClass.from_array(_piecewise([[0, 0.0], [80, 1.0], [159, 0.0]]), 0)
	var cg := EffectCurveClass.from_array(_piecewise([[0, 0.4], [159, 0.4]]), 1)
	var cb := EffectCurveClass.from_array(_piecewise([[0, 0.0], [40, 0.0], [159, 0.6]]), 2)
	var fit: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb)
	for kf in fit["keyframes"]:
		var f: int = kf["frame"]
		var col: Color = kf["color"]
		_assert_approx(col.r, cr.sample_by_frame(f), "kf@%d curve R" % f)
		_assert_approx(col.g, cg.sample_by_frame(f), "kf@%d curve G" % f)
		_assert_approx(col.b, cb.sample_by_frame(f), "kf@%d curve B" % f)


## THE FULL UNIT CUBE COMPILES THROUGH — the whole of the author's ask. A keyframe holding
## (1,1,1) writes curve 1.0 in every channel, and one holding (0,0,0) writes 0.0, for ANY
## sprite. Under the muxed model this was the corner you could never reach: the pick was
## projected into `[0,S.r]×[0,S.g]×[0,S.b]` first, and 97.5% of corpus colour emitters have no
## channel whose byte slider could even hold 255.
func _test_every_curve_value_is_authorable() -> void:
	var kfs: Array = [
		{"frame": 0, "color": Color(0.0, 0.0, 0.0, 1.0)},
		{"frame": 80, "color": Color(1.0, 1.0, 1.0, 1.0)},
		{"frame": 159, "color": Color(0.0, 0.0, 0.0, 1.0)},
	]
	var back: Dictionary = ColourKeyframeFit.compile_to_curves(kfs)
	for chan in ["r", "g", "b"]:
		_assert_approx(back[chan][0], 0.0, "black corner compiles to 0 (%s)" % chan)
		_assert_approx(back[chan][80], 1.0, "white corner compiles to 1 (%s)" % chan)
	# And the midpoint is the plain lerp — no sprite anywhere in the maths.
	_assert_approx(back["r"][40], 0.5, "midpoint lerps in curve space")


## A genuinely curvy (sinusoidal) channel can't be captured exactly by a bounded keyframe
## budget — the fit reports exact=false and a real max_error rather than lying.
func _test_curvy_reports_honest_tell() -> void:
	var sine: Array = []
	sine.resize(160)
	for i in range(160):
		sine[i] = 0.5 + 0.45 * sin(float(i) / 159.0 * TAU * 3.0)  # 3 cycles
	var cr := EffectCurveClass.from_array(sine, 0)
	var cg := EffectCurveClass.from_array(_piecewise([[0, 0.5], [159, 0.5]]), 1)
	var cb := EffectCurveClass.from_array(_piecewise([[0, 0.5], [159, 0.5]]), 2)

	var fit: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb)
	_assert_true(not fit.get("exact", true), "curvy import is NOT exact")
	_assert_true(float(fit.get("max_error", 0.0)) > 0.0, "curvy reports a max_error tell")
	# ...but the fit is still bounded: the compiled curve stays within max_error of source.
	var back: Dictionary = ColourKeyframeFit.compile_to_curves(fit["keyframes"])
	var worst := 0.0
	for f in range(160):
		worst = maxf(worst, absf(back["r"][f] - cr.sample_by_frame(f)))
	_assert_true(worst <= float(fit["max_error"]) + 0.0005, "compiled stays within reported error")


## THE DEAD ZONE MUST NOT SPEND THE LIVE WINDOW'S KEYFRAMES (2026-08-21).
##
## The report was *"when I turn color on the keyframes don't get added"*. It was true and it
## was not the mint: `_douglas_peucker` had ONE budget for all 160 samples, and a ROM curve
## whose tail oscillates spends it there — on ages past `life_n`, which the renderer never
## samples and the column neither draws nor lets you click. Measured over 605 colour-off
## corpus emitters, 291 (48.1%) were left with ONE keyframe or none inside the life; after
## the split, 58 (9.6%), and those are genuinely flat across their life.
##
## This is the shape of it, minimal: a live window with real structure, and a tail noisy
## enough to exhaust the budget on its own.
func _test_the_dead_zone_cannot_starve_the_live_window() -> void:
	var a: Array = []
	a.resize(160)
	# ages 0-9: a zig-zag with four distinct vertices — what the author came to author.
	for f in range(10):
		a[f] = [0.1, 0.9, 0.2, 0.8][f % 4]
	# ages 10-159: a fast sine, far more deviation than the live window has, so a single
	# global budget goes here in its entirety.
	for f in range(10, 160):
		a[f] = 0.5 + 0.45 * sin(float(f) * 0.7)
	var c := EffectCurveClass.from_array(a, 0)

	var global: Dictionary = ColourKeyframeFit.import_from_curves(c, c, c)
	var split: Dictionary = ColourKeyframeFit.import_from_curves(c, c, c, 10)
	var g_in := _count_below(global["keyframes"], 10)
	var s_in := _count_below(split["keyframes"], 10)
	# The starvation itself, asserted — so this test fails if the global fit ever stops
	# being the wrong thing and someone deletes the split as unnecessary.
	_assert_true(g_in <= 1,
		"ONE budget starves the live window (%d keyframes in ages 0-9 of a 4-vertex zigzag)" % g_in)
	_assert_true(s_in >= 4,
		"…a per-region budget does not: %d keyframes inside the life, one per vertex" % s_in)


## NOTHING IS TRUNCATED. The other repair — refit to `[0, life_n)` — is on CONTEXT.md's
## *Colour dead zone* _Avoid_ list, and rightly: `compile_to_curves` writes all 160 samples
## back from the keyframes, so a fit that stopped at `life_n` would flatten the tail's real
## bytes to fix what looked like a drawing bug. The split fits BOTH regions, so the tail is
## represented at least as well as it was before.
func _test_the_split_keeps_the_tail() -> void:
	var a: Array = []
	a.resize(160)
	for f in range(160):
		a[f] = 0.5 + 0.45 * sin(float(f) * 0.35)
	var c := EffectCurveClass.from_array(a, 0)
	var split: Dictionary = ColourKeyframeFit.import_from_curves(c, c, c, 12)
	var beyond := 0
	for kf in split["keyframes"]:
		if int(kf["frame"]) >= 12:
			beyond += 1
	_assert_true(beyond >= 2,
		"the tail keeps its own keyframes (%d past the life) — a truncating fit would " % beyond
		+ "compile the dead samples FLAT, rewriting bytes to fix a drawing bug")
	# The terminal sample specifically: DP always keeps it, and every corpus colour emitter
	# has one at 159. Losing it would let the compile hold the wrong colour to the end.
	_assert_true(_count_at(split["keyframes"], 159) == 1, "…including the terminal sample at 159")


## OMITTING `life_n` IS THE OLD BEHAVIOUR, EXACTLY. The parameter is opt-in because only the
## session layer has an emitter to resolve a life from; every other caller must be unchanged.
func _test_no_life_is_the_old_global_fit() -> void:
	var cr := EffectCurveClass.from_array(_piecewise([[0, 0.0], [80, 1.0], [159, 0.0]]), 0)
	var cg := EffectCurveClass.from_array(_piecewise([[0, 0.4], [159, 0.4]]), 1)
	var cb := EffectCurveClass.from_array(_piecewise([[0, 0.0], [40, 0.0], [159, 0.6]]), 2)
	var bare: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb)
	for life in [-1, 0, 1, 160, 1000]:
		var same: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb, life)
		_assert_true(_frames_of(same["keyframes"]) == _frames_of(bare["keyframes"]),
			"life_n=%d is outside (1, 160) and fits globally, exactly as omitting it does" % life)


func _count_below(keyframes: Array, n: int) -> int:
	var c := 0
	for kf in keyframes:
		if int(kf["frame"]) < n:
			c += 1
	return c


func _count_at(keyframes: Array, f: int) -> int:
	var c := 0
	for kf in keyframes:
		if int(kf["frame"]) == f:
			c += 1
	return c


func _frames_of(keyframes: Array) -> Array:
	var out: Array = []
	for kf in keyframes:
		out.append(int(kf["frame"]))
	return out


## Build a 160-sample array that is piecewise-linear between the given [frame, value] vertices.
func _piecewise(vertices: Array) -> Array:
	var a: Array = []
	a.resize(160)
	for i in range(vertices.size() - 1):
		var f0: int = vertices[i][0]
		var v0: float = vertices[i][1]
		var f1: int = vertices[i + 1][0]
		var v1: float = vertices[i + 1][1]
		for f in range(f0, f1 + 1):
			var t := float(f - f0) / float(f1 - f0)
			a[f] = v0 + (v1 - v0) * t
	return a


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _assert_approx(got: float, expected: float, label: String) -> void:
	if is_equal_approx(got, expected) or absf(got - expected) < 0.0006:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
