extends Node
## Regression: the particle renderer's per-emitter colour-curve cache
## (_emitter_color_curve_{r,g,b}) is derived ONCE in _setup_emitter_caches() at
## initialize() and was never rebuilt — so an Effect Studio colour-curve edit (enable
## toggle, curve reassignment) updated the model but left the renderer sampling stale
## data. _compute_color_modulate kept modulating after "colour off", and a reassigned
## curve kept sampling the old index. This drove the E312 emitter-idx0 "colour curves
## do nothing" report.
##
## The renderer now exposes refresh_emitter_caches() (the host calls it on every emitter
## edit — see EffectStudioColorCurveLiveEditTest for the wiring). This test proves the
## mechanism directly, asset-free: the stale read reproduces without a refresh, and the
## refresh makes the toggle + the reassignment take effect.
##
## Run: godot --path . --quit-after 30 res://tests/EffectParticleRendererColorCurveRefreshTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve
const RendererClass = preload("res://addons/exmateria_effects/render/EffectParticleRenderer.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_toggle_off_needs_refresh_to_go_white()
	_test_reassignment_needs_refresh_to_sample_new_curve()

	print("\n=== EffectParticleRendererColorCurveRefreshTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectParticleRendererColorCurveRefreshTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectParticleRendererColorCurveRefreshTest")
		get_tree().quit(0)


## Toggling colour OFF (as EmitterChannel does: em.flags["color_curve_enabled"] = false)
## must make the modulate go white — but ONLY after the renderer cache is refreshed. The
## stale read (no refresh) is asserted first so the regression is explicit.
func _test_toggle_off_needs_refresh_to_go_white() -> void:
	var ed = _effect_with_colour()
	var rend = RendererClass.new()
	rend.effect_data = ed
	rend._setup_emitter_caches()

	var base := rend._compute_color_modulate(_particle(0, 5))
	_assert_true(base.r > 0.4 and base.g < 0.1, "enabled: modulate reads the R curve (red-ish)")

	# Studio flips the derived flag off (EmitterChannel._recompute_flags).
	ed.get_emitter(0).flags["color_curve_enabled"] = false

	var stale := rend._compute_color_modulate(_particle(0, 5))
	_assert_true(stale.r > 0.4, "STALE without refresh: modulate still coloured (the bug)")

	rend.refresh_emitter_caches()
	var fixed := rend._compute_color_modulate(_particle(0, 5))
	_assert_true(fixed.r == 1.0 and fixed.g == 1.0 and fixed.b == 1.0,
		"after refresh: colour-off modulate is white")


## Reassigning which curve index feeds R must change what the modulate samples — but
## again only after a refresh (the renderer caches the curve OBJECT, not the index).
func _test_reassignment_needs_refresh_to_sample_new_curve() -> void:
	var ed = _effect_with_colour()
	var rend = RendererClass.new()
	rend.effect_data = ed
	rend._setup_emitter_caches()

	var before := rend._compute_color_modulate(_particle(0, 5)).r
	_assert_true(is_equal_approx(before, 0.8), "R samples curve idx0 (0.8) at load")

	# Studio reassigns R to curve idx 2 (a distinct, dimmer curve).
	ed.get_emitter(0).color_curves["r"] = 2

	var stale := rend._compute_color_modulate(_particle(0, 5)).r
	_assert_true(is_equal_approx(stale, 0.8), "STALE without refresh: still samples idx0 (the bug)")

	rend.refresh_emitter_caches()
	var fixed := rend._compute_color_modulate(_particle(0, 5)).r
	_assert_true(is_equal_approx(fixed, 0.2), "after refresh: samples the reassigned idx2 (0.2)")


## One emitter, colour ON, R/G/B -> curves 0/1/1. Curves are flat-per-index so
## sample_by_frame is deterministic regardless of age: idx0=0.8, idx1=0.0, idx2=0.2.
func _effect_with_colour():
	var ed = EffectDataClass.new()
	ed.curves.append(EffectCurveClass.from_array(_flat(0.8), 0))
	ed.curves.append(EffectCurveClass.from_array(_flat(0.0), 1))
	ed.curves.append(EffectCurveClass.from_array(_flat(0.2), 2))
	var em = EffectEmitterClass.new()
	em.color_curves = {"r": 0, "g": 1, "b": 1}
	em.flags = {"color_curve_enabled": true, "align_to_velocity": false}
	ed.emitters.append(em)
	return ed


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


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
