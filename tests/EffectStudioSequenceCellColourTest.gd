extends Node
## TDD guard for the SEQUENCE CELL COLOUR — the two pure derivations ADR-0103 rests on,
## neither of which needs a scene, a node or the page.
##
##   * the RIBBON CUT (dec. 2 + dec. 6-CORRECTED): cell k owns ages [a_k, a_k + n_k) and
##     draws `colour(a_k + (t mod n_k))` — NO offset. This asserted `+1` until 2026-08-20
##     on dec. 6's Godot trace; the ROM read that decision was filed pending says the PSX
##     increments the colour phase AFTER the draw (`0x801A2FE0` renders, `0x801A301C`
##     increments `0x50`, spawn stores `0x50 = 0`), so frame k is painted with sample k.
##     The ribbon was right all along and the Godot renderer is the surface that drifted.
##     Kept as a named guard rather than deleted, because "feels right" cuts both ways:
##     this is now the assertion that a re-introduced `+1` has to get past.
##   * the COLOUR PROVENANCE ladder (dec. 4): which emitter's curves a strip is tinted by,
##     and the NAMED rung the answer came from. This is the assertable red ADR-0103's
##     consequences call for — browse a sequence and drill the same sequence from an
##     emitter span, and the same target must answer `only`/`first` vs `origin`.
##
## Rects cannot see a tint (a tinted thumbnail and an untinted one have identical
## geometry), so the assertion is on the COLOUR HANDED TO THE PAINTER, never on the drawn
## result. One screenshot then confirms the wiring.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EffectStudioSequenceCellColourTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve
const EffectData = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter

const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_hold_of_one_is_a_still_by_arithmetic()
	_test_a_long_hold_loops_through_its_own_piece()
	_test_the_pieces_are_cut_at_opcode_boundaries()
	_test_the_first_and_last_rows_finally_carry_colour()
	_test_a_row_that_occupies_no_time_is_a_still_at_its_boundary()
	_test_no_curves_is_the_identity()
	_test_browsing_one_applicable_emitter_is_the_only_rung()
	_test_browsing_several_names_the_first_and_counts_the_rest()
	_test_no_colour_enabled_emitter_is_the_none_rung()
	_test_drilling_from_an_emitter_is_the_origin_rung()
	_test_the_lens_is_part_of_applicability()
	_test_the_rung_is_always_named_in_the_title()

	print("\n=== EffectStudioSequenceCellColourTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceCellColourTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceCellColourTest")
		get_tree().quit(0)


# --- the ribbon cut ---------------------------------------------------------

func _test_a_hold_of_one_is_a_still_by_arithmetic() -> void:
	# duration 2 -> n_k == 1, which is 83.6% of the corpus. No static-vs-animated
	# branch exists: the loop IS the still when the piece is one frame long.
	var tr: Array = SequenceTimeline.trace(_anim())
	var c0: Color = CellColour.cell_color(tr[0], _ramp(), _zero(), _zero(), 0)
	var c9: Color = CellColour.cell_color(tr[0], _ramp(), _zero(), _zero(), 9)
	_assert_eq(c0, c9, "a one-frame piece draws the same colour at every t")
	# Cell 0 is a_k = 0 and the PSX pairs frame k with sample k, so this is sample 0.
	# `_ramp()` makes the two answers 0/255 and 1/255 — a one-LSB difference no screenshot
	# could ever separate, which is exactly why it is asserted numerically here.
	_assert_near(c0.r, 0.0, "cell 0 samples a_k, not a_k + 1 (dec. 6-CORRECTED: the ROM "
		+ "increments the colour phase at 0x801A301C, AFTER the draw at 0x801A2FE0)")


func _test_a_long_hold_loops_through_its_own_piece() -> void:
	# The third FRAME holds duration 16 -> n_k == 8: the 1.3% of cells a single swatch
	# cannot describe, where the corpus carries 30-150/255 of intra-piece travel.
	var tr: Array = SequenceTimeline.trace(_anim())
	var start: int = int(tr[3].get("tick_start", -1))
	_assert_eq(int(tr[3].get("ticks", 0)), 8, "the duration-16 opcode owns 8 ages")
	for t in range(8):
		_assert_near(CellColour.cell_color(tr[3], _ramp(), _zero(), _zero(), t).r,
			float(start + t) / 255.0, "t=%d walks its own piece" % t)
	_assert_eq(CellColour.cell_color(tr[3], _ramp(), _zero(), _zero(), 8),
		CellColour.cell_color(tr[3], _ramp(), _zero(), _zero(), 0),
		"and it WRAPS at n_k rather than running into the next cell's piece")


func _test_the_pieces_are_cut_at_opcode_boundaries() -> void:
	# The cut is the trace's own dwell — the same numbers the player's transport walks,
	# so a cell's piece and the playhead's position cannot disagree.
	var tr: Array = SequenceTimeline.trace(_anim())
	var starts: Array = []
	for e in tr:
		if int(e.get("ticks", 0)) > 0:
			starts.append(int(e.get("cut_start", -1)))
	_assert_eq(starts, [0, 1, 2, 10], "consecutive pieces tile the life with no gap")
	for e in tr:
		if int(e.get("ticks", 0)) > 0:
			_assert_eq(int(e.get("cut_start", -1)), int(e.get("tick_start", -2)),
				"and a cell that occupies time opens its window exactly at its dwell")


func _test_the_first_and_last_rows_finally_carry_colour() -> void:
	# THE COLOUR HOLE THE FENCEPOST AMENDMENT CLOSES. `SET_OFFSET` and `LOOP` both carry
	# `ticks == 0`, so before 2026-08-20 the first and last thumbnails of every corpus
	# strip were plain white BY CONSTRUCTION — "the strip has more rows than ages". They
	# are now positions on the clock, so they sample it like any other row.
	var tr: Array = SequenceTimeline.trace(_corpus_shaped_anim())
	var total: int = SequenceTimeline.total_ticks(tr)
	_assert_eq(str(tr[0].get("type", "")), "SET_OFFSET", "the first row is the spare start slot")
	_assert_eq(str(tr[tr.size() - 1].get("type", "")), "LOOP", "and the last is the spare end slot")
	# `_ramp` is r = age/255, so the sample IS the age and can be read straight off.
	_assert_near(CellColour.cell_color(tr[0], _ramp(), _zero(), _zero(), 0).r, 0.0,
		"the first row samples tick 0 — no longer the identity white")
	_assert_near(CellColour.cell_color(tr[tr.size() - 1], _ramp(), _zero(), _zero(), 0).r,
		float(total - 1) / 255.0,
		"and the last row samples the animation's LAST TICK. Under the old `+1` it sampled "
		+ "`total`, one PAST the end of the clock — the spare end slot was reaching off the "
		+ "animation entirely, and only a curve long enough to have a value there hid it")
	_assert_true(CellColour.cell_color(tr[0], _ramp(), _zero(), _zero(), 0) != CellColour.IDENTITY,
		"neither end is the untinted white it was before the amendment")


func _test_a_row_that_occupies_no_time_is_a_still_at_its_boundary() -> void:
	# A mid-stream offset opcode still appends nothing to the baked array. Under the new
	# model it is not therefore AGELESS — it stands for the boundary it sits on, which is
	# the last tick of the dwell before it, and it draws that tick's colour. One rule for
	# every row is what keeps `cell_color` free of a special case for the two ends.
	var tr: Array = SequenceTimeline.trace(_anim())
	_assert_eq(str(tr[2].get("type", "")), "ADD_OFFSET", "cell 2 is an offset opcode")
	_assert_eq(int(tr[2].get("ticks", -1)), 0, "and it still owns no dwell at all")
	_assert_eq(int(tr[2].get("cut_ticks", -1)), 1, "but its window is a still, never a hole")
	_assert_near(CellColour.cell_color(tr[2], _ramp(), _zero(), _zero(), 0).r, 1.0 / 255.0,
		"which resolves at the boundary it sits on — its `cut_start`, the last tick of the "
		+ "dwell before it, and not one past it")
	_assert_eq(CellColour.cell_color(tr[2], _ramp(), _zero(), _zero(), 0),
		CellColour.cell_color(tr[2], _ramp(), _zero(), _zero(), 6),
		"and the cut's phase cannot walk a one-tick window anywhere")


## The corpus shape every one of the 2,428 animations has, at its smallest: a leading
## SET_OFFSET, FRAMEs, a terminal frame, a trailing LOOP. `_anim()` above deliberately
## is NOT this — it opens on a FRAME — so the two ends need their own fixture.
func _corpus_shaped_anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 4, "depth_mode": 1},
		{"type": "FRAME", "frameset": 1, "duration": 0, "depth_mode": 1},
		{"type": "LOOP"},
	]}


func _test_no_curves_is_the_identity() -> void:
	var tr: Array = SequenceTimeline.trace(_anim())
	_assert_eq(CellColour.cell_color(tr[0], null, null, null, 0), CellColour.IDENTITY,
		"a cell with no curves draws exactly the white it draws today")


# --- the provenance ladder --------------------------------------------------

func _test_browsing_one_applicable_emitter_is_the_only_rung() -> void:
	# 61.5% of browsable targets.
	var ed = _effect([{"anim": 0, "group": 0, "on": true, "rgb": [0, 1, 1]}])
	var p: Dictionary = CellColour.provenance([], ed, 0, 0)
	_assert_eq(str(p.get("rung", "")), "only", "one applicable emitter fires the `only` rung")
	_assert_eq(int(p.get("emitter_index", -1)), 0, "and it names that emitter")
	_assert_true(p.get("r") != null, "and it carries that emitter's resolved curves")


func _test_browsing_several_names_the_first_and_counts_the_rest() -> void:
	# 23.5% of targets, of which 15.9% genuinely disagree by a median 144/255 — which is
	# why "first applicable" is only honest LABELLED, and why the count rides the rung.
	var ed = _effect([
		{"anim": 0, "group": 0, "on": true, "rgb": [0, 1, 1]},
		{"anim": 0, "group": 0, "on": true, "rgb": [1, 0, 1]},
		{"anim": 0, "group": 0, "on": true, "rgb": [1, 1, 0]},
	])
	var p: Dictionary = CellColour.provenance([], ed, 0, 0)
	_assert_eq(str(p.get("rung", "")), "first", "several applicable emitters fire `first`")
	_assert_eq(int(p.get("emitter_index", -1)), 0, "the first applicable is the one used")
	_assert_eq(int(p.get("others", -1)), 2, "and the OTHERS are counted, never hidden")


func _test_no_colour_enabled_emitter_is_the_none_rung() -> void:
	# 15.0% of targets. `none` is not an error — it is the render, which is white.
	var ed = _effect([{"anim": 0, "group": 0, "on": false, "rgb": [0, 1, 1]}])
	var p: Dictionary = CellColour.provenance([], ed, 0, 0)
	_assert_eq(str(p.get("rung", "")), "none", "colour disabled ⇒ no applicable emitter")
	_assert_eq(p.get("r"), null, "and no curves, so the strip stays exactly as white as today")
	var tr: Array = SequenceTimeline.trace(_anim())
	_assert_eq(CellColour.cell_color(tr[0], p.get("r"), p.get("g"), p.get("b"), 0),
		CellColour.IDENTITY, "which the cut honours by handing the painter the identity")


func _test_drilling_from_an_emitter_is_the_origin_rung() -> void:
	# THE SAME TARGET, opened two ways, must answer differently: a strip's target is a
	# sequence seen through a lens and never an emitter, so the tint is conditional on
	# how you arrived. Emitter 1 is not even the first applicable — the trail is.
	var ed = _effect([
		{"anim": 0, "group": 0, "on": true, "rgb": [0, 1, 1]},
		{"anim": 0, "group": 0, "on": true, "rgb": [1, 0, 1]},
	])
	var browsed: Dictionary = CellColour.provenance([Target.animation(0, 0)], ed, 0, 0)
	_assert_eq(str(browsed.get("rung", "")), "first", "browsed, the trail holds no emitter")
	_assert_eq(int(browsed.get("emitter_index", -1)), 0, "so the first applicable answers")
	var drilled: Dictionary = CellColour.provenance(
		[Target.emitter(1), Target.animation(0, 0)], ed, 0, 0)
	_assert_eq(str(drilled.get("rung", "")), "origin", "drilled, the ancestor emitter wins")
	_assert_eq(int(drilled.get("emitter_index", -1)), 1, "and it is the emitter drilled FROM")


func _test_the_lens_is_part_of_applicability() -> void:
	# Applicable == anim_index AND anim_param (the frameset-group lens) AND colour on.
	# An emitter playing the same sequence at another group is a different target.
	var ed = _effect([
		{"anim": 0, "group": 1, "on": true, "rgb": [0, 1, 1]},
		{"anim": 1, "group": 0, "on": true, "rgb": [1, 0, 1]},
	])
	_assert_eq(str(CellColour.provenance([], ed, 0, 0).get("rung", "")), "none",
		"neither the other group nor the other sequence is applicable here")
	_assert_eq(int(CellColour.provenance([], ed, 0, 1).get("emitter_index", -1)), 0,
		"the group-1 emitter answers for the group-1 lens")


func _test_the_rung_is_always_named_in_the_title() -> void:
	# Dec. 5: the rung rides the focus block's EXISTING title, which costs 0px in a
	# ~268px inspector row. Every rung says which one it fired on.
	var seen: Dictionary = {}
	for rung in ["origin", "only", "first", "none"]:
		var s: String = CellColour.title_suffix({"rung": rung, "emitter_index": 3, "others": 2})
		_assert_true(s != "", "the `%s` rung says something rather than falling silent" % rung)
		seen[s] = true
	_assert_eq(seen.size(), 4, "and the four rungs read differently from each other")
	for rung in ["origin", "only", "first"]:
		_assert_true(CellColour.title_suffix({"rung": rung, "emitter_index": 3, "others": 2})
			.find("3") >= 0, "the `%s` rung NAMES the emitter it tinted by" % rung)
	_assert_true(CellColour.title_suffix({"rung": "first", "emitter_index": 3, "others": 2})
		.find("2") >= 0, "`first` carries the count of the others it did not pick")
	_assert_true(CellColour.title_suffix({"rung": "none", "emitter_index": -1, "others": 0})
		.find("-1") < 0, "`none` names no emitter rather than printing a sentinel")


# --- fixtures ---------------------------------------------------------------

## Four FRAME opcodes with an offset between two of them: ages 0, 1, 2-9, 10.
func _anim() -> Dictionary:
	return {"index": 0, "opcodes": [
		{"type": "FRAME", "frameset": 0, "duration": 2},
		{"type": "FRAME", "frameset": 0, "duration": 2},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 4},
		{"type": "FRAME", "frameset": 0, "duration": 16},
		{"type": "FRAME", "frameset": 0, "duration": 3},
	]}


## A curve whose sample AT INDEX f is f/255 — so a resolved channel reads back the exact
## age it was sampled at, which is what makes the frame-to-sample pairing assertable.
func _ramp() -> EffectCurve:
	var vals: Array = []
	for i in range(160):
		vals.append(float(i) / 255.0)
	return EffectCurve.from_array(vals)


func _zero() -> EffectCurve:
	var vals: Array = []
	vals.resize(160)
	vals.fill(0.0)
	return EffectCurve.from_array(vals)


## An EffectData carrying `specs` emitters and three curves they can point at.
func _effect(specs: Array) -> EffectData:
	var ed := EffectData.new()
	ed.animations = [_anim(), _anim()]
	ed.curves = [_ramp(), _zero(), _ramp()]
	for i in range(specs.size()):
		var s: Dictionary = specs[i]
		var em := EffectEmitter.new()
		em.index = i
		em.anim_index = int(s.get("anim", 0))
		em.anim_param = int(s.get("group", 0))
		em.flags = {"color_curve_enabled": bool(s.get("on", true))}
		var rgb: Array = s.get("rgb", [0, 1, 2])
		em.color_curves = {"r": int(rgb[0]), "g": int(rgb[1]), "b": int(rgb[2])}
		ed.emitters.append(em)
	return ed


# --- harness ----------------------------------------------------------------

func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


func _assert_near(actual: float, expected: float, msg: String) -> void:
	if absf(actual - expected) < 0.002:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %f\n         actual:   %f" % [msg, expected, actual])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
