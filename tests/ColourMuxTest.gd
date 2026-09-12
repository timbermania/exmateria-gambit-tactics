extends Node
## Slice 1 — the pure colour mux and its inverse (ADR-0089 colour-keyframe amendment).
##
## Render is `ALBEDO = S ⊙ curve`, a per-channel multiply against the sprite's representative
## texel `S`. This module is that multiply, its inverse, and the two clamps. This proves:
##   • inverse_mux is T ⊘ S per channel, with a dead channel (S.k == 0) locked at 0;
##   • the reachable box clamp keeps a colour inside [0,S.r]×[0,S.g]×[0,S.b] — still the
##     definition of what CAN render, though since 2026-08-21 nothing applies it to a pick;
##   • `clamp_unit` bounds a CURVE triple by [0,1] and by nothing else — the authoring space
##     after ADR-0089 decision 4's second amendment, and the reason every value from
##     [0,0,0] to [255,255,255] is now reachable in the picker for every sprite;
##   • a known dense curve round-trips (mux → inverse_mux) exactly on live channels;
##   • the forward mux is byte-identical to the Colour ribbon's read path — the ribbon and the
##     picker's "renders as" swatch can never disagree.
##
## Run: godot --path . --quit-after 30 res://tests/ColourMuxTest.tscn

const ColourMux = preload("res://src/effects/studio/ColourMux.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve
const ColourRibbon = preload("res://src/effects/studio/ColourRibbon.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_inverse_mux_divides_per_channel()
	_test_inverse_mux_dead_channel_locks_zero()
	_test_clamp_to_box_bounds_each_channel()
	_test_clamp_unit_bounds_only_by_one()
	_test_clamp_unit_admits_the_whole_cube()
	_test_dense_curve_round_trips()
	_test_forward_mux_matches_ribbon_read_path()

	print("\n=== ColourMuxTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourMuxTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourMuxTest")
		get_tree().quit(0)


## curve = T ⊘ S per channel — the exact inverse of the render multiply, so
## S ⊙ curve == T for any T inside the reachable box.
func _test_inverse_mux_divides_per_channel() -> void:
	var s := Color(0.8, 0.6, 0.5, 1.0)
	var t := Color(0.4, 0.3, 0.25, 1.0)
	var curve: Color = ColourMux.inverse_mux(t, s)
	_assert_approx(curve.r, 0.5, "inverse R = 0.4/0.8")
	_assert_approx(curve.g, 0.5, "inverse G = 0.3/0.6")
	_assert_approx(curve.b, 0.5, "inverse B = 0.25/0.5")


## A dead channel (sprite texel 0 in that channel) can never be lit by any curve
## value, so the inverse locks it at 0 rather than dividing by zero.
func _test_inverse_mux_dead_channel_locks_zero() -> void:
	var s := Color(0.8, 0.0, 0.5, 1.0)  # green dead
	var t := Color(0.4, 0.9, 0.25, 1.0)  # T.g is out of box; must not blow up
	var curve: Color = ColourMux.inverse_mux(t, s)
	_assert_approx(curve.r, 0.5, "inverse R still divides")
	_assert_approx(curve.g, 0.0, "inverse G locked 0 on dead channel")
	_assert_approx(curve.b, 0.5, "inverse B still divides")


## The reachable box is [0,S.r]×[0,S.g]×[0,S.b]; clamp keeps a picked colour inside it,
## so the inverse mux stays in [0,1] and the picker never offers an unreachable colour.
func _test_clamp_to_box_bounds_each_channel() -> void:
	var s := Color(0.8, 0.6, 0.0, 1.0)  # blue dead
	var picked := Color(1.0, 0.3, 0.5, 1.0)  # R over box, B outside dead channel
	var boxed: Color = ColourMux.clamp_to_box(picked, s)
	_assert_approx(boxed.r, 0.8, "clamp R to S.r")
	_assert_approx(boxed.g, 0.3, "clamp G unchanged (in box)")
	_assert_approx(boxed.b, 0.0, "clamp B to 0 (dead channel)")


## `clamp_unit` is the AUTHORING clamp, and the sprite is not in it. A curve triple is bounded
## by [0,1] — the byte range a sample holds — and by nothing else.
func _test_clamp_unit_bounds_only_by_one() -> void:
	var c: Color = ColourMux.clamp_unit(Color(1.4, -0.3, 0.62, 1.0))
	_assert_approx(c.r, 1.0, "clamp_unit R to 1")
	_assert_approx(c.g, 0.0, "clamp_unit G to 0")
	_assert_approx(c.b, 0.62, "clamp_unit B unchanged")
	_assert_approx(c.a, 1.0, "clamp_unit is opaque")


## THE WHOLE CUBE SURVIVES, FOR A SPRITE THAT WOULD HAVE CRUSHED IT. This is the author's ask
## stated as an assertion: against `S = (0.06, 0.75, 0.0)` — a sprite with a nearly-dark red
## channel and a DEAD blue one — `clamp_to_box` collapses white to (0.06, 0.75, 0) and black
## corners with it, while `clamp_unit` passes every corner of [0,1]³ through untouched.
func _test_clamp_unit_admits_the_whole_cube() -> void:
	var s := Color(0.06, 0.75, 0.0, 1.0)
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var boxed: Color = ColourMux.clamp_to_box(white, s)
	_assert_true(boxed.r < 0.99 and boxed.b <= 0.0, "the box would have crushed white")
	for corner in [Color(0,0,0,1), Color(1,1,1,1), Color(1,0,0,1), Color(0,0,1,1)]:
		var kept: Color = ColourMux.clamp_unit(corner)
		_assert_approx(kept.r, corner.r, "corner R survives clamp_unit")
		_assert_approx(kept.g, corner.g, "corner G survives clamp_unit")
		_assert_approx(kept.b, corner.b, "corner B survives clamp_unit")
	# …and what the sprite makes of the extreme pick is REPORTED, not imposed: the blue channel
	# renders black because a multiply cannot add light the sprite lacks. That is physics, and
	# it is now the "renders as" swatch's job to say so rather than the picker's to prevent it.
	var renders: Color = ColourMux.mux(white, s)
	_assert_approx(renders.b, 0.0, "a dead channel still renders black")
	_assert_approx(renders.g, 0.75, "a live channel renders the sprite's own value")


## A keyframe compiled down reproduces a known dense curve: mux the curve to its rendered
## colour per frame (the muxed target a keyframe would hold), then inverse_mux back — on a
## live channel this recovers the original curve sample exactly (S constant per emitter).
func _test_dense_curve_round_trips() -> void:
	var s := Color(0.75, 0.5, 0.9, 1.0)  # all channels live
	var cr := EffectCurveClass.from_array(_ramp(1.0), 0)
	var cg := EffectCurveClass.from_array(_flat(0.4), 1)
	var cb := EffectCurveClass.from_array(_ramp(0.5), 2)
	for f in [0, 5, 40, 100, 159]:
		var curve := EffectCurveClass.sample_rgb(cr, cg, cb, f)  # (cr,cg,cb) at f
		var target: Color = ColourMux.mux(curve, s)              # what a keyframe holds
		var back: Color = ColourMux.inverse_mux(target, s)       # compiled-down curve
		_assert_approx(back.r, curve.r, "round-trip R @%d" % f)
		_assert_approx(back.g, curve.g, "round-trip G @%d" % f)
		_assert_approx(back.b, curve.b, "round-trip B @%d" % f)


## The forward mux must be byte-identical to the ribbon read path, so the picker preview
## and the ribbon (both derived from S ⊙ curve) can never disagree. Compare against the
## ribbon's own frame_colors output for the same curves + sprite base.
func _test_forward_mux_matches_ribbon_read_path() -> void:
	var s := Color(0.75, 0.5, 0.9, 1.0)
	var cr := EffectCurveClass.from_array(_ramp(1.0), 0)
	var cg := EffectCurveClass.from_array(_flat(0.4), 1)
	var cb := EffectCurveClass.from_array(_ramp(0.5), 2)
	var ribbon_cols: Array = ColourRibbon.frame_colors(cr, cg, cb, -1, false, s)
	for f in [0, 40, 159]:
		var curve := EffectCurveClass.sample_rgb(cr, cg, cb, f)
		var muxed: Color = ColourMux.mux(curve, s)
		var expected: Color = ribbon_cols[f]
		_assert_approx(muxed.r, expected.r, "mux ≡ ribbon R @%d" % f)
		_assert_approx(muxed.g, expected.g, "mux ≡ ribbon G @%d" % f)
		_assert_approx(muxed.b, expected.b, "mux ≡ ribbon B @%d" % f)


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
