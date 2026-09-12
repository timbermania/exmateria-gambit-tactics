extends Node
## Slice 1 — the SINGLE colour resolve both the particle renderer and the Colour
## ribbon read, so the ribbon (a read-only studio view) can never drift from what
## the renderer actually paints.
##
## EffectCurve.sample_rgb(cr, cg, cb, frame) is that source. This proves (a) it
## composes the three per-channel curves at a frame exactly as expected, and (b)
## the renderer's _compute_color_modulate routes through it — same RGB for the same
## curves + age. If someone re-inlines the renderer sampling, the parity assertion
## breaks.
##
## Run: godot --path . --quit-after 30 res://tests/ColourRibbonResolveParityTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve
const RendererClass = preload("res://addons/exmateria_effects/render/EffectParticleRenderer.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_sample_rgb_composes_three_channels()
	_test_renderer_routes_through_sample_rgb()

	print("\n=== ColourRibbonResolveParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourRibbonResolveParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourRibbonResolveParityTest")
		get_tree().quit(0)


## sample_rgb picks r from cr, g from cg, b from cb at the SAME frame. Ramp curves
## (value == index/159) give an independent expected literal per frame.
func _test_sample_rgb_composes_three_channels() -> void:
	var cr = EffectCurveClass.from_array(_ramp(1.0), 0)   # sample_by_frame(f) == f/159
	var cg = EffectCurveClass.from_array(_flat(0.25), 1)
	var cb = EffectCurveClass.from_array(_ramp(0.5), 2)   # == 0.5 * f/159

	var c: Color = EffectCurveClass.sample_rgb(cr, cg, cb, 40)
	_assert_approx(c.r, 40.0 / 159.0, "sample_rgb R = cr @40")
	_assert_approx(c.g, 0.25, "sample_rgb G = cg @40 (flat)")
	_assert_approx(c.b, 0.5 * 40.0 / 159.0, "sample_rgb B = cb @40")


## The renderer must delegate to sample_rgb: _compute_color_modulate for a particle
## of age N carries the same RGB as sample_rgb(cr, cg, cb, N).
func _test_renderer_routes_through_sample_rgb() -> void:
	var ed = EffectDataClass.new()
	var cr = EffectCurveClass.from_array(_ramp(1.0), 0)
	var cg = EffectCurveClass.from_array(_flat(0.25), 1)
	var cb = EffectCurveClass.from_array(_ramp(0.5), 2)
	ed.curves.append(cr)
	ed.curves.append(cg)
	ed.curves.append(cb)
	var em = EffectEmitterClass.new()
	em.color_curves = {"r": 0, "g": 1, "b": 2}
	em.flags = {"color_curve_enabled": true, "align_to_velocity": false}
	ed.emitters.append(em)

	var rend = RendererClass.new()
	rend.effect_data = ed
	rend._setup_emitter_caches()

	for age in [0, 5, 40, 159]:
		var expected: Color = EffectCurveClass.sample_rgb(cr, cg, cb, age)
		var got: Color = rend._compute_color_modulate(_particle(0, age))
		_assert_approx(got.r, expected.r, "renderer R ≡ sample_rgb @%d" % age)
		_assert_approx(got.g, expected.g, "renderer G ≡ sample_rgb @%d" % age)
		_assert_approx(got.b, expected.b, "renderer B ≡ sample_rgb @%d" % age)


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


func _particle(emitter_index: int, age: int):
	var p = ParticleClass.new()
	p.emitter_index = emitter_index
	p.age = age
	return p


func _assert_approx(got: float, expected: float, label: String) -> void:
	if is_equal_approx(got, expected) or absf(got - expected) < 0.0005:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
