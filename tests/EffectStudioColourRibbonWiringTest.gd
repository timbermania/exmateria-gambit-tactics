extends Node
## The Colour ribbon's CONTENT contract: which curves it resolves, which window it spans,
## which sprite colour it muxes, and what it does when colour is off. Its colours match
## EffectCurve.sample_rgb — the same source the renderer paints with.
##
## THE RIBBON MOVED COLUMNS (ADR-0089 colour-move amendment, 2026-08-20). It used to be
## appended to the inspector's "Particle · over-life" section body, and this test drove a bare
## inspector to reach it. It is now the player column's, hosted by its keyframe track, and the
## page composes it from three production calls: `SequenceCellColour.for_emitter` for the
## curves and the colour-enabled flag, `EmitterLifeWindow.resolve` for the window, and
## `EmitterSpriteColor.representative` for the mux base.
##
## So this test now performs that composition rather than building a widget tree for it —
## the same three functions in the same order `EffectStudioPage._update_sequence_ribbon` uses.
## What it gives up is the plumbing (does the page actually call them, on the right emitter,
## into the right widget), and that is covered on REAL data by
## EffectStudioColourRibbonAcceptanceTest, which drives the whole page against E312 and holds
## the ribbon's bands to the live renderer's own modulate.
##
## Run: godot --path . --quit-after 4 res://tests/EffectStudioColourRibbonWiringTest.tscn

const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const SpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const ColourRibbonClass = preload("res://src/effects/studio/ColourRibbon.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_ribbon_present_and_matches_sample_rgb()
	_test_no_ribbon_when_colour_disabled()
	_test_ribbon_muxes_sprite_base()

	print("\n=== EffectStudioColourRibbonWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColourRibbonWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColourRibbonWiringTest")
		get_tree().quit(0)


func _test_ribbon_present_and_matches_sample_rgb() -> void:
	var ed = _effect(true)
	var ribbon = _column_ribbon(ed)

	_assert_true(ribbon != null and ribbon.visible,
		"colour enabled → the player column shows a Colour ribbon")
	if ribbon != null:
		_assert_true(ribbon.is_shown(), "the ribbon is shown")
		_assert_true(ribbon.has_frame_ruler(), "the column enables the frame ruler")
		var cols: Array = ribbon.colors()
		# THE WINDOW IS THE PARTICLE'S LIFE, and this fixture's lifetime is 48. It reads the
		# same as it did before the move only because this emitter's authored lifetime and
		# its animation happen to agree here; for 1204 of the corpus's 2622 colour-enabled
		# emitters they do not, which is why the axis is now resolved rather than assumed.
		_assert_true(cols.size() == 48, "windowed to the 48-frame lifetime")
		var cr = ed.get_curve(0)
		var cg = ed.get_curve(1)
		var cb = ed.get_curve(2)
		for f in [0, 20, 47]:
			var want: Color = EffectCurveClass.sample_rgb(cr, cg, cb, f)
			_assert_approx(cols[f].r, want.r, "ribbon band %d R ≡ sample_rgb" % f)
			_assert_approx(cols[f].g, want.g, "ribbon band %d G ≡ sample_rgb" % f)
			_assert_approx(cols[f].b, want.b, "ribbon band %d B ≡ sample_rgb" % f)
		ribbon.free()


func _test_no_ribbon_when_colour_disabled() -> void:
	# The ribbon HIDES rather than vanishing now — its slot in the player column is reserved
	# at a declared height precisely so that navigating to a colourless emitter cannot swing
	# the panel's measured chrome and re-size the canvas square under the author.
	var ed = _effect(false)
	var ribbon = _column_ribbon(ed)
	_assert_true(not ribbon.visible, "colour disabled → the ribbon draws nothing")
	_assert_true(ribbon.colors().is_empty(), "…and resolves no bands")
	ribbon.free()


## The full seam: `EmitterSpriteColor.representative` resolves the emitter's representative
## sprite colour and the ribbon muxes it in — so a GREEN-only sprite makes every ribbon band
## R=0/B=0 even though the R/B curves ramp up (the E138 idx0 case).
func _test_ribbon_muxes_sprite_base() -> void:
	var ed = _effect(true)
	# Give the sprite a pure-green region so red/blue are unexpressible.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.75, 0.0, 1.0))
	ed.texture = ImageTexture.create_from_image(img)
	ed.framesets = [{"frames": [{"uv": {"x": 0, "y": 0, "width": 2, "height": 2}}]}]
	ed.animations = [{"opcodes": [{"type": "FRAME", "frameset": 0, "duration": 2}]}]
	ed.emitters[0].anim_index = 0
	ed.emitters[0].anim_param = 0

	var ribbon = _column_ribbon(ed)
	_assert_true(ribbon != null and ribbon.visible, "green-sprite emitter still shows a ribbon")
	if ribbon != null:
		var cols: Array = ribbon.colors()
		var any_nonzero_g := false
		for f in [0, 20, 47]:
			_assert_approx(cols[f].r, 0.0, "band %d R muxed to 0 (green-only sprite)" % f)
			_assert_approx(cols[f].b, 0.0, "band %d B muxed to 0 (green-only sprite)" % f)
			if cols[f].g > 0.001:
				any_nonzero_g = true
		_assert_true(any_nonzero_g, "green channel still lives (the sprite CAN show green)")
	ribbon.free()


# --- fixtures -------------------------------------------------------------

## `EffectStudioPage._update_sequence_ribbon`'s composition for emitter 0, in the same order
## and through the same three production calls, onto a real ColourRibbon. Deliberately NOT a
## second implementation of the rules — every number here comes from the module that owns it.
func _column_ribbon(ed):
	var prov: Dictionary = CellColour.for_emitter(ed, 0)
	var on: bool = prov.get("r") != null
	var window: int = int(LifeWindow.resolve(ed, 0).get("n", -1))
	var base: Color = SpriteColor.representative(ed, 0) if on else Color.WHITE
	var ribbon = ColourRibbonClass.new()
	add_child(ribbon)
	ribbon.set_curves(prov.get("r"), prov.get("g"), prov.get("b"), on, window, true, base)
	remove_child(ribbon)
	return ribbon


## One emitter with colour `enabled`, R/G/B → curves 0/1/2 (a ramp + two flats, so
## sample_rgb is distinct per channel), and a 48-frame lifetime (the used window).
func _effect(enabled: bool):
	var ed = EffectDataClass.new()
	ed.curves.append(EffectCurveClass.from_array(_ramp(1.0), 0))
	ed.curves.append(EffectCurveClass.from_array(_flat(0.25), 1))
	ed.curves.append(EffectCurveClass.from_array(_flat(0.5), 2))
	var em = EffectEmitterClass.new()
	em.color_curves = {"r": 0, "g": 1, "b": 2}
	em.flags = {"color_curve_enabled": enabled, "align_to_velocity": false}
	em.lifetime_min_start = 48
	em.lifetime_max_start = 48
	em.lifetime_min_end = 48
	em.lifetime_max_end = 48
	ed.emitters.append(em)
	return ed


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
