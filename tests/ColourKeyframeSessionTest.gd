extends Node
## Slice 4 — the colour-keyframe EDIT SESSION: place/move/delete joint colour keyframes and the
## per-emitter copy-on-write fork of the shared curve table (ADR-0089 colour-keyframe amendment,
## decisions 5/7/8). The session is the authoring layer; the dense 160-sample curves stay the
## compiled artifact fed to the renderer.
##
## This proves:
##   • begin() IMPORTS keyframes from the emitter's current ROM curves (no jump);
##   • the FIRST edit forks the emitter's three channels into three INDEPENDENT curves,
##     appended to the table so a shared curve used by other emitters is never corrupted;
##   • place/move/delete keep keyframes sorted and joint, and the compiled curve at a
##     keyframe frame IS the picked colour — unprojected (decision 4, amended 2026-08-21:
##     the keyframe holds the curve, not the muxed output, so no sprite stands between the
##     pick and the sample);
##   • re-applying after a second edit REUSES the forked indices (no unbounded curve growth);
##   • a dead channel (gamut S.k == 0) is REPORTED and still authored — the curve holds what
##     was picked and `renders_as` is what goes black.
##
## Run: godot --path . --quit-after 30 res://tests/ColourKeyframeSessionTest.tscn

const ColourKeyframeSession = preload("res://src/effects/studio/ColourKeyframeSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve
const CurveExplode = ExMateriaEffects.CurveExplode
const ColourMux = preload("res://src/effects/studio/ColourMux.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_begin_imports_current_colour()
	_test_the_channels_are_already_independent_so_nothing_forks()
	_test_another_emitters_curve_is_untouched()
	_test_place_changes_the_compiled_colour()
	_test_second_edit_reuses_forked_indices()
	_test_dead_channel_is_reported_not_locked()
	_test_add_is_visual_noop_until_recoloured()

	print("\n=== ColourKeyframeSessionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourKeyframeSessionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourKeyframeSessionTest")
		get_tree().quit(0)


# Two emitters both alias curve 0 for red; emitter 1 has distinct g/b curves. Editing emitter 1
# must fork without touching curve 0 (still red for emitter 0).
func _fixture() -> EffectDataClass:
	var ed = EffectDataClass.new()
	ed.curves.append(EffectCurveClass.from_array(_piecewise([[0, 0.2], [159, 0.8]]), 0))  # shared red
	ed.curves.append(EffectCurveClass.from_array(_piecewise([[0, 0.5], [80, 1.0], [159, 0.0]]), 1))
	ed.curves.append(EffectCurveClass.from_array(_piecewise([[0, 0.0], [159, 0.6]]), 2))
	var em0 = EffectEmitterClass.new()
	em0.color_curves = {"r": 0, "g": 0, "b": 0}
	em0.flags = {"color_curve_enabled": true}
	var em1 = EffectEmitterClass.new()
	em1.color_curves = {"r": 0, "g": 1, "b": 2}
	em1.flags = {"color_curve_enabled": true}
	ed.emitters.append(em0)
	ed.emitters.append(em1)
	# EXPLODE, exactly as load does (ADR-0089 curve-ownership amendment). The hand-built
	# table above is the ROM's SHARED shape — em0's three channels and em1's red all name
	# slot 0 — which is no longer a state the authoring model can be in. Skipping this would
	# test the session against data that cannot reach it.
	CurveExplode.explode(ed)
	return ed


## begin() imports keyframes fitted to the emitter's current curves, so compiling them straight
## back (no edits) reproduces the original muxed colour — the "no visual jump" guarantee.
func _test_begin_imports_current_colour() -> void:
	var ed = _fixture()
	var s := Color(0.75, 0.5, 0.9, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	_assert_true(sess.keyframe_count() >= 2, "imported keyframes")
	sess.apply()  # compile even with no edits
	var em = ed.emitters[1]
	for f in [0, 40, 80, 120, 159]:
		var want := ColourMux.mux(_orig_colour(_fixture(), 1, f), s)  # original muxed colour
		var got := _muxed_now(ed, em, s, f)
		_assert_approx(got.r, want.r, "import R @%d" % f)
		_assert_approx(got.g, want.g, "import G @%d" % f)
		_assert_approx(got.b, want.b, "import B @%d" % f)


## The three channels are ALREADY independent when the session opens, and an edit appends
## nothing. This test used to assert the opposite half of the same guarantee — that the first
## edit FORKED three fresh curves — which was the right answer while the table was shared and
## is dead work now that the explode has already done it unconditionally. A fork here would
## only append a duplicate of a curve nobody else can see.
func _test_the_channels_are_already_independent_so_nothing_forks() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.8, 0.8, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	var before: int = ed.curves.size()
	var em = ed.emitters[1]
	var ri := int(em.color_curves["r"])
	var gi := int(em.color_curves["g"])
	var bi := int(em.color_curves["b"])
	_assert_true(ri != gi and gi != bi and ri != bi, "3 independent curve indices at begin()")
	sess.place(80, Color(0.4, 0.2, 0.6, 1.0))
	sess.apply()
	_assert_eq(ed.curves.size(), before, "an edit appends NO curves — there is nothing to fork")
	_assert_eq(int(em.color_curves["r"]), ri, "…and the channel still points where it did")


## Another emitter's colour curve is byte-identical after emitter 1's edit. Emitter 0's three
## channels and emitter 1's red all named ROM slot 0; before the explode this edit moved all
## four, which is the fault the whole amendment exists to fix.
func _test_another_emitters_curve_is_untouched() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.8, 0.8, 1.0)
	var idx0: int = int(ed.emitters[0].color_curves["r"])
	var before: Array = (ed.curves[idx0].samples as Array).duplicate()
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	sess.place(80, Color(0.4, 0.2, 0.6, 1.0))
	sess.apply()
	_assert_eq(int(ed.emitters[0].color_curves["r"]), idx0, "emitter 0 still on its own curve")
	var after: Array = ed.curves[idx0].samples
	var same := before.size() == after.size()
	for i in range(mini(before.size(), after.size())):
		if absf(float(before[i]) - float(after[i])) > 0.0001:
			same = false
	_assert_true(same, "the other emitter's curve samples are unchanged")


## A placed keyframe drives the compiled curve, and the SAMPLE is the pick — not a projection
## of it. The colour here would have been crushed in two channels by the old box clamp against
## this sprite; it survives whole, and what the sprite makes of it is a separate, stated fact.
func _test_place_changes_the_compiled_colour() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.6, 1.0, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	var picked := Color(0.9, 0.75, 0.5, 1.0)  # R and G BOTH outside the old reachable box
	sess.place(80, picked)
	sess.apply()
	var em = ed.emitters[1]
	for chan in ["r", "g", "b"]:
		var ci := int(em.color_curves[chan])
		_assert_approx(ed.curves[ci].sample_by_frame(80), picked[chan],
			"placed keyframe writes the pick verbatim (%s)" % chan)
	# …and the render is the pick muxed through the sprite — the bound, reported.
	var got := _muxed_now(ed, em, s, 80)
	_assert_approx(got.r, picked.r * s.r, "renders as picked ⊙ S (R)")
	_assert_approx(got.g, picked.g * s.g, "renders as picked ⊙ S (G)")


## Editing again reuses the already-forked curve indices — no unbounded table growth.
func _test_second_edit_reuses_forked_indices() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.8, 0.8, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	sess.place(40, Color(0.3, 0.3, 0.3, 1.0))
	sess.apply()
	var em = ed.emitters[1]
	var ri := int(em.color_curves["r"])
	var n_after_first: int = ed.curves.size()
	sess.place(120, Color(0.5, 0.1, 0.2, 1.0))
	sess.apply()
	_assert_eq(ed.curves.size(), n_after_first, "no new curves on second edit")
	_assert_eq(int(em.color_curves["r"]), ri, "reused forked R index")


## A dead channel (gamut S.k == 0) is REPORTED and still authored. It used to compile to a
## locked 0 curve whatever was picked — a silent rewrite of the author's value in a channel
## 4.2% of corpus colour emitters have. The curve now holds what was picked, `renders_as` is
## what goes black, and `dead_channels` is what says why.
func _test_dead_channel_is_reported_not_locked() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.0, 0.6, 1.0)  # green dead
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	sess.place(80, Color(0.4, 0.9, 0.3, 1.0))
	sess.apply()
	var gi := int(ed.emitters[1].color_curves["g"])
	_assert_approx(ed.curves[gi].sample_by_frame(80), 0.9, "the dead channel's pick is authored")
	_assert_approx(sess.renders_as(80).g, 0.0, "…and renders black")
	_assert_eq(int(sess.dead_channels()["g"]), 1, "…and the session says which channel it is")
	_assert_eq(int(sess.dead_channels()["r"]), 0, "…and which are alive")


## add(frame) seeds the new keyframe with the CURVE colour already at that age (curve_at), so
## the compiled colour there is unchanged until it is recoloured — adding a keyframe is a visual
## no-op.
func _test_add_is_visual_noop_until_recoloured() -> void:
	var ed = _fixture()
	var s := Color(0.8, 0.7, 0.9, 1.0)
	var sess = ColourKeyframeSession.new()
	sess.begin(ed, 1, s)
	var before := sess.curve_at(60)      # the curve value at age 60
	var idx := sess.add(60)
	_assert_true(idx >= 0, "add returns the new keyframe index")
	_assert_eq(sess.index_of_frame(60), idx, "keyframe now exists at age 60")
	var after := sess.curve_at(60)
	_assert_approx(after.r, before.r, "add keeps colour @60 R")
	_assert_approx(after.g, before.g, "add keeps colour @60 G")
	_assert_approx(after.b, before.b, "add keeps colour @60 B")
	# Recolour that keyframe → the compiled CURVE at 60 becomes the picked colour, verbatim.
	sess.place(60, Color(0.1, 0.6, 0.2, 1.0))
	sess.apply()
	var em = ed.emitters[1]
	_assert_approx(ed.curves[int(em.color_curves["r"])].sample_by_frame(60), 0.1, "recoloured @60 R")
	_assert_approx(ed.curves[int(em.color_curves["g"])].sample_by_frame(60), 0.6, "recoloured @60 G")
	_assert_approx(ed.curves[int(em.color_curves["b"])].sample_by_frame(60), 0.2, "recoloured @60 B")


# --- helpers ---------------------------------------------------------------

func _orig_colour(ed, emitter_index: int, f: int) -> Color:
	var em = ed.emitters[emitter_index]
	return Color(
		ed.curves[int(em.color_curves["r"])].sample_by_frame(f),
		ed.curves[int(em.color_curves["g"])].sample_by_frame(f),
		ed.curves[int(em.color_curves["b"])].sample_by_frame(f), 1.0)


func _muxed_now(ed, em, s: Color, f: int) -> Color:
	var curve := Color(
		ed.curves[int(em.color_curves["r"])].sample_by_frame(f),
		ed.curves[int(em.color_curves["g"])].sample_by_frame(f),
		ed.curves[int(em.color_curves["b"])].sample_by_frame(f), 1.0)
	return ColourMux.mux(curve, s)


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


func _assert_eq(got: int, expected: int, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, expected %d)" % [label, got, expected])


func _assert_approx(got: float, expected: float, label: String) -> void:
	if is_equal_approx(got, expected) or absf(got - expected) < 0.0008:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
