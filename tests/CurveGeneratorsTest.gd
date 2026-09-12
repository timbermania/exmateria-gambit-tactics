extends Node
## TDD guard for CurveGenerators — the 16 parametric curve-shape generators ported from
## `effect-editor/ui/curve_generators.lua` (ADR-0089 curve-ownership amendment, decision
## 4: shapes are GENERATED, not browsed from a library).
##
## The port is checked against a GOLDEN captured by running the original Lua module
## itself (`tests/goldens/curve_generators_golden.json`, 34 parameter cases × 160
## samples). That is the point of the fixture: "they port directly" is a claim about
## another language's arithmetic. Two of the cases exist only to pin the idiom that
## genuinely differs — Lua's `%` on floats is a FLOORED modulo, so a NEGATIVE phase
## through `triangle_wave` needs `fposmod`, and a plain `fmod` produces a different
## curve. Every mainline case passes with either, which is exactly why those two are here.
##
## The properties below cover what the golden cannot: the domain contract every caller
## depends on (160 samples of 0-255 ints) and the identity curve, which is decision 5's
## load-bearing claim rather than a port detail.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CurveGeneratorsTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const CurveGenerators = preload("res://src/effects/studio/CurveGenerators.gd")
const ParticlePhysicsClass = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const GOLDEN := "res://tests/goldens/curve_generators_golden.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_matches_the_lua_golden()
	_test_every_generator_returns_the_curve_domain()
	_test_constant_zero_is_the_identity_curve()
	_test_manipulators_pad_a_short_input()

	print("\n=== CurveGeneratorsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CurveGeneratorsTest")
		get_tree().quit(1)
	else:
		print("[PASS] CurveGeneratorsTest")
		get_tree().quit(0)


## Element for element against the Lua module's own output. The five manipulators are
## fed the `_base` case's curve, exactly as the golden's generator fed them.
func _test_matches_the_lua_golden() -> void:
	var cases = _read_golden()
	_assert_true(cases is Array and cases.size() >= 34,
		"the golden loads (%s cases)" % ("none" if not (cases is Array) else str(cases.size())))
	if not (cases is Array):
		return
	var base: Array = []
	for case in cases:
		if str(case.get("fn", "")) == "_base":
			base = Array(case.get("values", []))
	_assert_eq(base.size(), 160, "the golden carries the manipulators' input curve")

	var checked := 0
	for case in cases:
		var fn: String = str(case.get("fn", ""))
		if fn == "_base":
			continue
		var args: Array = Array(case.get("args", []))
		var want: Array = Array(case.get("values", []))
		var got: Array = _invoke(fn, args, base)
		if got.is_empty():
			_assert_true(false, "no port for generator '%s'" % fn)
			continue
		checked += 1
		var first_bad := -1
		for i in range(mini(got.size(), want.size())):
			if int(got[i]) != int(want[i]):
				first_bad = i
				break
		if got.size() != want.size():
			_assert_eq(got.size(), want.size(), "%s%s returns 160 samples" % [fn, str(args)])
		elif first_bad >= 0:
			_assert_true(false, "%s%s matches Lua — first divergence at sample %d (got %d, Lua %d)"
				% [fn, str(args), first_bad, int(got[first_bad]), int(want[first_bad])])
		else:
			_passed += 1
	_assert_eq(checked, cases.size() - 1, "every golden case was replayed through the port")


## The domain contract: 160 samples, every one an int in [0, 255]. Callers bridge these
## straight into an EffectCurve through CurvePaintModel.grid_to_curve, which divides by
## 255 — an out-of-range sample would silently become an out-of-range normalized value.
func _test_every_generator_returns_the_curve_domain() -> void:
	var base: Array = CurveGenerators.s_curve(0, 159, 0, 255)
	var produced := {
		"linear": CurveGenerators.linear(0, 159, 0, 255),
		"ease_in": CurveGenerators.ease_in(0, 159, 0, 255),
		"ease_out": CurveGenerators.ease_out(0, 159, 0, 255),
		"s_curve": base,
		"exponential_in": CurveGenerators.exponential_in(0, 159, 0, 255),
		"exponential_out": CurveGenerators.exponential_out(0, 159, 0, 255),
		"sine_wave": CurveGenerators.sine_wave(0, 159, 0, 255),
		"triangle_wave": CurveGenerators.triangle_wave(0, 159, 0, 255),
		"sawtooth": CurveGenerators.sawtooth(0, 159, 0, 255),
		"pulse": CurveGenerators.pulse(0, 159, 0, 255),
		"constant": CurveGenerators.constant(128),
		# Fed values that would leave the domain if a rail were missing.
		"invert": CurveGenerators.invert(base),
		"reverse": CurveGenerators.reverse(base),
		"scale": CurveGenerators.scale(base, 8.0, 128),
		"shift": CurveGenerators.shift(base, 400),
		"copy": CurveGenerators.copy(base),
	}
	_assert_eq(produced.size(), 16, "all 16 generators are ported")
	for name in produced:
		var curve: Array = produced[name]
		var bad := -1
		for i in range(curve.size()):
			if typeof(curve[i]) != TYPE_INT or int(curve[i]) < 0 or int(curve[i]) > 255:
				bad = i
				break
		_assert_eq(curve.size(), 160, "%s returns 160 samples" % name)
		_assert_eq(bad, -1, "%s stays in 0-255 ints (sample %d = %s)"
			% [name, bad, "-" if bad < 0 else str(curve[bad])])


## Decision 5, the reason a use site with no curve mints `constant(0)`: it is an EXACT
## no-op, not an approximate one. No curve makes the sim hold the START values, and an
## all-zero curve lerps to `min_start` at every frame. (ADR-0089 line 40 and the picker's
## `none` glyph both described "no curve" as a linear start→end ramp; the sim does no
## such ramp, which is why this is testable at all.)
func _test_constant_zero_is_the_identity_curve() -> void:
	var identity: Array = CurveGenerators.constant(0)
	var nonzero := 0
	for v in identity:
		if int(v) != 0:
			nonzero += 1
	_assert_eq(nonzero, 0, "constant(0) is all zeros")

	var curve := EffectCurve.new()
	curve.samples.resize(identity.size())
	for i in range(identity.size()):
		curve.samples[i] = float(identity[i]) / 255.0
	var rng := RandomNumberGenerator.new()
	var mismatches: Array = []
	for frame in [0, 1, 13, 159, 160, 401]:
		var without: float = ParticlePhysicsClass.interpolate_range(3.0, 3.0, 11.0, 11.0, null, frame, rng)
		var with_identity: float = ParticlePhysicsClass.interpolate_range(3.0, 3.0, 11.0, 11.0, curve, frame, rng)
		if not is_equal_approx(without, with_identity):
			mismatches.append("f%d: %f vs %f" % [frame, without, with_identity])
	_assert_eq(mismatches.size(), 0,
		"a use site that gains constant(0) renders identically to one with no curve — %s"
		% str(mismatches))


## The manipulators are handed whatever a use site's curve holds, and a curve loaded from
## a short/odd record is not guaranteed to be 160 long. They pad rather than truncate or
## index past the end (the Lua `curve[i] or 0` idiom).
func _test_manipulators_pad_a_short_input() -> void:
	var short: Array = [10, 20, 30]
	_assert_eq(CurveGenerators.copy(short).size(), 160, "copy pads a short input to 160")
	_assert_eq(int(CurveGenerators.copy(short)[2]), 30, "copy keeps the samples it was given")
	_assert_eq(int(CurveGenerators.copy(short)[3]), 0, "copy pads with 0")
	_assert_eq(int(CurveGenerators.invert(short)[159]), 255, "invert reads a missing sample as 0")
	_assert_eq(int(CurveGenerators.reverse(short)[157]), 30, "reverse maps the tail to the head")


# --- helpers ---------------------------------------------------------------

## Dispatch one golden case onto the port. The manipulators take the golden's `_base`
## curve as their first argument; the generators take their recorded parameters.
func _invoke(fn: String, args: Array, base: Array) -> Array:
	match fn:
		"linear": return CurveGenerators.linear(int(args[0]), int(args[1]), float(args[2]), float(args[3]))
		"ease_in": return CurveGenerators.ease_in(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 2.0)
		"ease_out": return CurveGenerators.ease_out(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 2.0)
		"s_curve": return CurveGenerators.s_curve(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 2.0)
		"exponential_in": return CurveGenerators.exponential_in(int(args[0]), int(args[1]),
			float(args[2]), float(args[3]), float(args[4]) if args.size() > 4 else 10.0)
		"exponential_out": return CurveGenerators.exponential_out(int(args[0]), int(args[1]),
			float(args[2]), float(args[3]), float(args[4]) if args.size() > 4 else 10.0)
		"sine_wave": return CurveGenerators.sine_wave(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 1.0,
			float(args[5]) if args.size() > 5 else 0.0)
		"triangle_wave": return CurveGenerators.triangle_wave(int(args[0]), int(args[1]),
			float(args[2]), float(args[3]), float(args[4]) if args.size() > 4 else 1.0,
			float(args[5]) if args.size() > 5 else 0.0)
		"sawtooth": return CurveGenerators.sawtooth(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 1.0)
		"pulse": return CurveGenerators.pulse(int(args[0]), int(args[1]), float(args[2]),
			float(args[3]), float(args[4]) if args.size() > 4 else 1.0,
			float(args[5]) if args.size() > 5 else 0.5)
		"constant": return CurveGenerators.constant(float(args[0]))
		"invert": return CurveGenerators.invert(base)
		"reverse": return CurveGenerators.reverse(base)
		"scale": return CurveGenerators.scale(base, float(args[0]), float(args[1]))
		"shift": return CurveGenerators.shift(base, float(args[0]))
		"copy": return CurveGenerators.copy(base)
	return []


func _read_golden():
	if not FileAccess.file_exists(GOLDEN):
		return null
	var f := FileAccess.open(GOLDEN, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


# --- harness ---------------------------------------------------------------

func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(got), str(want)])
