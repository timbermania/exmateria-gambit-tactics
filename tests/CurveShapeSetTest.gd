extends Node
## TDD guard for the SHAPE half of the ADR-0089 curve-ownership amendment: the distinct
## shape set (decision 4), the picker's copy verb (decision 3), and the identity mint
## (decision 5).
##
## The distinction this whole file exists to hold: a **shape** is a distinct 160-sample
## sequence; a **use site's curve** is an instance of one. After the explode an effect
## holds a median of 22 curves drawing a median of 8 distinct shapes. Counting the array
## where the shape set is meant is the mistake the design is most likely to grow — a
## 22-tile grid showing 8 pictures would be worse than the dropdown it replaced, and the
## PSX budget would read 22/15 for an effect that fits fine.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CurveShapeSetTest.tscn

const CurveShapeSet = preload("res://src/effects/studio/CurveShapeSet.gd")
const CurveChannel = preload("res://src/effects/studio/CurveChannel.gd")
const CurveExplode = ExMateriaEffects.CurveExplode
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitterClass = ExMateriaEffects.EffectEmitter
const EffectCurveClass = ExMateriaEffects.EffectCurve
const CurveGenerators = preload("res://src/effects/studio/CurveGenerators.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_shapes_dedup_by_value_not_by_curve()
	_test_a_use_site_with_no_curve_costs_no_shape()
	_test_ordinal_names_the_shape_a_use_site_draws()
	_test_the_gauge_counts_shapes_against_fifteen()
	_test_a_pick_copies_the_shape_and_links_nothing()
	_test_a_pick_on_an_empty_use_site_mints_a_curve()
	_test_picking_none_clears_the_address_without_renumbering()
	_test_a_pick_undoes_exactly()

	print("\n=== CurveShapeSetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CurveShapeSetTest")
		get_tree().quit(1)
	else:
		print("[PASS] CurveShapeSetTest")
		get_tree().quit(0)


# --- the shape set ---------------------------------------------------------

## Four use sites, two of them drawing the same picture: two SHAPES, four curves. The dedup
## is by the quantized 0-255 bytes — the ones the compiler will actually write — so the
## count here cannot flatter the count there.
func _test_shapes_dedup_by_value_not_by_curve() -> void:
	var ed := _fixture()
	_assert_eq(ed.curves.size(), 4, "four private curves, one per use site")
	var shapes: Array = CurveShapeSet.shapes(ed)
	_assert_eq(shapes.size(), 2, "…drawing TWO distinct shapes")
	var counts: Array = []
	for sh in shapes:
		counts.append(sh["sites"].size())
	_assert_eq(str(counts), str([3, 1]), "shape 1 has 3 use sites, shape 2 has 1")
	_assert_eq(Array(shapes[0]["grid"]).size(), 160, "a shape carries the whole 160 samples")


## "No curve" is the ABSENCE of a shape, not a shape — it costs no slot, so a use site
## without one contributes nothing to the budget.
func _test_a_use_site_with_no_curve_costs_no_shape() -> void:
	var ed := _fixture()
	var before: int = CurveShapeSet.shapes(ed).size()
	CurveExplode.set_site_index(ed, 1, "b", "colour", -1)
	_assert_eq(CurveShapeSet.shapes(ed).size(), before,
		"clearing one of three sites drawing a shape keeps the shape")
	CurveExplode.set_site_index(ed, 0, "spread", "param", -1)
	CurveExplode.set_site_index(ed, 1, "r", "colour", -1)
	_assert_eq(CurveShapeSet.shapes(ed).size(), before - 1,
		"clearing the LAST site drawing a shape drops it from the set")


## A picker's face asks "which shape is this", never "which index" — an index is an export
## concern and, after the explode, a private array position that tells an author nothing.
func _test_ordinal_names_the_shape_a_use_site_draws() -> void:
	var ed := _fixture()
	var shapes: Array = CurveShapeSet.shapes(ed)
	_assert_eq(CurveShapeSet.ordinal_for(shapes, 0, "spread", "param"), 0, "emitter 0 draws shape 1")
	_assert_eq(CurveShapeSet.ordinal_for(shapes, 1, "g", "colour"), 1, "emitter 1's G draws shape 2")
	_assert_eq(CurveShapeSet.ordinal_for(shapes, 0, "drag", "param"), -1,
		"a use site with no curve draws no shape")


## Decision 4: distinct shapes = curves the compiler must emit = consumption against 15.
## One number, two purposes. Decision 6's refusal is only fair because this is watchable.
func _test_the_gauge_counts_shapes_against_fifteen() -> void:
	var ed := _fixture()
	var g: Dictionary = CurveShapeSet.gauge(ed)
	_assert_eq(int(g["count"]), 2, "the gauge counts SHAPES (2), not curves (4)")
	_assert_eq(int(g["budget"]), 15, "…against the ROM's 15 slots")
	_assert_eq(int(g["spare"]), 13, "…reporting the spare headroom")
	_assert_true(not bool(g["over"]), "two shapes is not an overrun")
	_assert_true("2/15" in CurveShapeSet.gauge_text(ed), "the label reads N/15")

	# Author past the table: every use site gets its own distinct shape, plus enough new
	# ones to break 15. Authoring is unbounded by design — the COMPILER refuses, and it can
	# only do that fairly because the gauge said so first.
	for i in range(20):
		var em = EffectEmitterClass.new()
		em.curves = {"spread": -1}
		em.color_curves = {}
		ed.emitters.append(em)
		CurveChannel.assign_shape(ed, _site(ed.emitters.size() - 1, "spread", "param"),
			CurveGenerators.constant(i + 3))
	var over: Dictionary = CurveShapeSet.gauge(ed)
	_assert_true(int(over["count"]) > 15, "authoring can exceed the table (%d shapes)" % int(over["count"]))
	_assert_true(bool(over["over"]), "…and the gauge says so")
	_assert_true("over the PSX table" in CurveShapeSet.gauge_text(ed),
		"…out loud, not left to the reader to subtract")


# --- the pick verb ---------------------------------------------------------

## Decision 3: the picker COPIES. Picking a shape another use site draws writes those
## samples into THIS site's own curve; the two sites keep separate curves, so reshaping
## one afterwards moves nothing.
func _test_a_pick_copies_the_shape_and_links_nothing() -> void:
	var ed := _fixture()
	var shapes: Array = CurveShapeSet.shapes(ed)
	var source_idx: int = CurveExplode.site_index(ed, 1, "g", "colour")
	var target_idx: int = CurveExplode.site_index(ed, 0, "spread", "param")
	var before: int = ed.curves.size()

	CurveChannel.assign_shape(ed, _site(0, "spread", "param"), shapes[1]["grid"])
	_assert_eq(ed.curves.size(), before, "a site that HAD a curve mints nothing")
	_assert_eq(CurveExplode.site_index(ed, 0, "spread", "param"), target_idx,
		"…and keeps its own index — the pick did not repoint it at the source")
	_assert_true(target_idx != source_idx, "the two use sites are still separate curves")
	_assert_eq(str(CurveChannel.to_grid(ed.curves[target_idx])), str(shapes[1]["grid"]),
		"the picked shape landed")

	# Nothing links: reshaping the target leaves the source alone.
	var source_before: Array = CurveChannel.to_grid(ed.curves[source_idx])
	CurveChannel.apply_raw(ed, {"curve_index": target_idx}, CurveGenerators.constant(200))
	_assert_eq(str(CurveChannel.to_grid(ed.curves[source_idx])), str(source_before),
		"reshaping the copy moves nothing else")


## Decision 5: a use site with no curve MINTS one. It is appended (so no index renumbers)
## and it is the identity — all zeros — so adding a curve changes nothing until it is
## painted. Exact, not approximate: no curve makes the sim hold the START values.
func _test_a_pick_on_an_empty_use_site_mints_a_curve() -> void:
	var ed := _fixture()
	_assert_eq(CurveExplode.site_index(ed, 0, "drag", "param"), -1, "the site starts with no curve")
	var before: int = ed.curves.size()

	# The mint on its own, without a pick: pure identity, nothing painted.
	var minted: int = CurveExplode.mint_identity(ed, 0, "drag", "param")
	_assert_eq(minted, before, "the minted curve is APPENDED (no index renumbers)")
	_assert_eq(ed.curves.size(), before + 1, "exactly one curve appended")
	var nonzero := 0
	for v in CurveChannel.to_grid(ed.curves[minted]):
		if int(v) != 0:
			nonzero += 1
	_assert_eq(nonzero, 0, "…and it is the IDENTITY — all zeros, a true no-op")
	_assert_eq(int(ed.curves[minted].index), -1,
		"a minted curve claims no provenance (it came from no ROM slot)")
	_assert_eq(CurveExplode.mint_identity(ed, 0, "drag", "param"), minted,
		"minting twice returns the existing curve rather than appending again")

	# And now a real pick onto a site that had none: mint, then fill.
	var ed2 := _fixture()
	var shapes: Array = CurveShapeSet.shapes(ed2)
	var n: int = ed2.curves.size()
	CurveChannel.assign_shape(ed2, _site(0, "drag", "param"), shapes[0]["grid"])
	_assert_eq(ed2.curves.size(), n + 1, "the pick minted the missing curve")
	var idx: int = CurveExplode.site_index(ed2, 0, "drag", "param")
	_assert_eq(str(CurveChannel.to_grid(ed2.curves[idx])), str(shapes[0]["grid"]),
		"…and filled it with the picked shape")


## Picking `none` clears the ADDRESS, not the array. Removing the entry would renumber
## every index above it, which is the one thing the private-index model cannot survive.
func _test_picking_none_clears_the_address_without_renumbering() -> void:
	var ed := _fixture()
	var other: int = CurveExplode.site_index(ed, 1, "g", "colour")
	var n: int = ed.curves.size()
	CurveChannel.assign_shape(ed, _site(0, "spread", "param"), [])
	_assert_eq(CurveExplode.site_index(ed, 0, "spread", "param"), -1, "the site now has no curve")
	_assert_eq(ed.curves.size(), n, "the array is unchanged — no entry removed, nothing renumbered")
	_assert_eq(CurveExplode.site_index(ed, 1, "g", "colour"), other,
		"every other use site still resolves to the same index")
	var again: Dictionary = CurveChannel.assign_shape(ed, _site(0, "spread", "param"), [])
	_assert_true(bool(again.get("no_edit", false)), "clearing an already-clear site records nothing")


## A pick can mint AND overwrite, so its undo is a snapshot, not a scalar replay of a value
## that may not have existed. Through the choke point it unwinds exactly: the minted curve
## goes away, the address goes back, and overwritten samples are restored.
func _test_a_pick_undoes_exactly() -> void:
	var ed := _fixture()
	var session := EffectEditSession.new(ed)
	var shapes: Array = CurveShapeSet.shapes(ed)

	# (a) a pick that OVERWRITES an existing curve
	var target: int = CurveExplode.site_index(ed, 0, "spread", "param")
	var before_samples: Array = CurveChannel.to_grid(ed.curves[target])
	var n: int = ed.curves.size()
	session.apply_edit(_site(0, "spread", "param"), shapes[1]["grid"])
	_assert_true(str(CurveChannel.to_grid(ed.curves[target])) != str(before_samples),
		"the pick changed the curve")
	_assert_true(session.undo(), "the pick is on the undo stack")
	_assert_eq(str(CurveChannel.to_grid(ed.curves[target])), str(before_samples),
		"undo restores the overwritten samples")
	_assert_eq(ed.curves.size(), n, "…and the array size")

	# (b) a pick that MINTS
	session.apply_edit(_site(0, "drag", "param"), shapes[0]["grid"])
	_assert_eq(ed.curves.size(), n + 1, "the mint appended")
	_assert_true(session.undo(), "the mint is on the undo stack")
	_assert_eq(ed.curves.size(), n, "undo drops the minted curve")
	_assert_eq(CurveExplode.site_index(ed, 0, "drag", "param"), -1,
		"…and puts the use site back to having no curve")


# --- helpers ---------------------------------------------------------------

## A `curve_assign` field_ref addressing one use site.
func _site(emitter_index: int, slot: String, kind: String) -> Dictionary:
	return {"channel": "curve_assign", "emitter_index": emitter_index,
		"slot": slot, "kind": kind}


## Two emitters, four use sites, TWO distinct shapes — built the way the ROM does it (three
## sites naming one shared slot) and then exploded, exactly as load does.
func _fixture() -> EffectDataClass:
	var ed = EffectDataClass.new()
	ed.curves.append(_curve(CurveGenerators.s_curve(0, 159, 0, 255), 0))
	ed.curves.append(_curve(CurveGenerators.sine_wave(0, 159, 20, 200, 2.0), 1))
	var em0 = EffectEmitterClass.new()
	em0.curves = {"spread": 0, "drag": -1}
	em0.color_curves = {}
	var em1 = EffectEmitterClass.new()
	em1.curves = {}
	em1.color_curves = {"r": 0, "g": 1, "b": 0}
	ed.emitters.append(em0)
	ed.emitters.append(em1)
	CurveExplode.explode(ed)
	return ed


func _curve(grid: Array, idx: int):
	var normalized: Array = []
	for v in grid:
		normalized.append(float(v) / 255.0)
	return EffectCurveClass.from_array(normalized, idx)


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
