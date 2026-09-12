extends Node
## TDD guard for the Effect Studio **shared editor-widget kit** (F1 #264, Half B).
##
## #255 gave the inspector three edit cells hand-built for the screen tween
## (`choice` / `target_color` / `gradient_color`). The per-subsystem authoring
## builds (Palette, Camera, Emitters…) all need the SAME humble primitives —
## spinboxes, dropdowns, checkbox groups, curve painters — so this kit adds the
## generic `editor` shapes ONCE in `EffectKeyframeInspector._edit_cell`:
##
##   * `int`     — a SpinBox with a type-derived range (u8/s8/u16/s16/u32/s32),
##                 optional min/max override and a `bias` for bipolar fields
##                 (the screen signed-byte lesson). Fans `(field_ref, raw)`.
##   * `enum`    — a value-carrying OptionButton (distinct from `choice`, which
##                 fans the INDEX): seeded to the item whose VALUE matches, fans
##                 that item's VALUE.
##   * `bitflags`— a checkbox group over declared masks; each toggle recomputes
##                 the whole word and fans it.
##   * `curve`   — a sparkline bound to a real curve that opens EffectCurvePainter
##                 through the shared on_open seam.
##
## Every editor lowers through the ONE mutate callback (`_on_mutate`, the #255
## EffectEditSession choke point) — the widgets own layout, never mutation logic.
## Seeding a widget must fire NO spurious edit.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioEditorKitTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")
const ParticleUnits = preload("res://src/effects/studio/ParticleUnits.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_int_u8_spinbox_range_seed_and_fan()
	_test_int_s16_signed_range()
	_test_int_min_max_override()
	_test_int_bias_bipolar()
	_test_int_prefix_decorates_the_display()
	_test_unit_cell_seeds_and_fans_human_value()
	_test_flip_sign_authors_game_up_and_commits_opposite()
	_test_enum_carries_value_not_index()
	_test_bitflags_group_recomputes_word()
	_test_curve_editor_opens_painter()
	_test_curve_open_carries_used_window()
	_test_curve_pick_fans_the_chosen_shape_through_field_ref()
	_test_curve_pick_thumbnails_are_whole_curve()
	_test_curve_pick_face_reflects_the_assigned_curve()
	_test_curve_pick_face_label_is_short_not_clipped()
	_test_curve_pick_out_of_choices_value_names_the_shape()
	_test_curve_pick_set_value_syncs_face_without_firing()
	_test_colour_channel_curves_recorded_and_refreshable()
	_test_seeding_fires_no_edit()
	_test_clear_drops_kit_widgets()
	_test_cells_row_renders_a_strip_of_sub_cells()
	_test_sparkline_used_window_api()
	_test_sparkline_linear_mode()
	_test_curve_cell_used_window_reaches_the_sparkline()
	_test_sparkline_windowed_samples_trims_real_window_else_whole()
	_test_sparkline_plot_points_refits_y_to_the_trimmed_window()
	_test_sparkline_plot_points_stretches_short_window_full_width()
	_test_sparkline_absolute_height_maps_to_fixed_range()
	_test_sparkline_untrimmed_width_ignores_the_window()
	_test_sparkline_draw_honors_the_global_toggles()
	_test_sparkline_absolute_mode_marks_the_ceiling()

	print("\n=== EffectStudioEditorKitTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEditorKitTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEditorKitTest")
		get_tree().quit(0)


# --- int -------------------------------------------------------------------

func _test_int_u8_spinbox_range_seed_and_fan() -> void:
	var mutations: Array = []
	var ref := _ref("radius")
	var insp = _show([_int_field("Radius", "u8", 40, ref)], mutations)

	var spins: Array = insp.int_widgets()
	_assert_eq(spins.size(), 1, "an int cell renders ONE spinbox")
	if spins.is_empty():
		return
	var sb = spins[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_eq(int(sb.min_value), 0, "u8 min is 0")
	_assert_eq(int(sb.max_value), 255, "u8 max is 255")
	_assert_eq(int(sb.value), 40, "the spinbox is seeded to the current value")
	_assert_eq(mutations.size(), 0, "seeding fires no edit")

	sb.value = 200   # a real value change emits value_changed synchronously
	_assert_eq(mutations.size(), 1, "changing the spinbox fans one edit")
	if mutations.is_empty():
		return
	_assert_true(mutations[0][0] == ref, "the edit carries the cell's field_ref")
	_assert_eq(mutations[0][1], 200, "the fanned raw is the spinbox integer")


func _test_int_s16_signed_range() -> void:
	var mutations: Array = []
	var ref := _ref("time")
	var insp = _show([_int_field("Time", "s16", -5, ref)], mutations)
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_eq(int(sb.min_value), -32768, "s16 min is -32768")
	_assert_eq(int(sb.max_value), 32767, "s16 max is 32767")
	_assert_eq(int(sb.value), -5, "signed value seeded verbatim")
	sb.value = -300
	_assert_eq(mutations[0][1], -300, "a negative edit fans the signed int straight through")


func _test_int_min_max_override() -> void:
	var insp = _show([_int_field("Blend mode", "u8", 5, _ref("bm"), {"min": 0, "max": 10})], [])
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_eq(int(sb.min_value), 0, "explicit min overrides the type range")
	_assert_eq(int(sb.max_value), 10, "explicit max overrides the type range")


## A bipolar field is stored biased (raw = display + bias). The spinbox shows the
## SIGNED display value; the fanned raw re-adds the bias (the screen signed-byte lesson).
func _test_int_bias_bipolar() -> void:
	var mutations: Array = []
	var ref := _ref("blend_param")
	var insp = _show([_int_field("Amount", "u8", 128, ref, {"bias": 128})], mutations)
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_eq(int(sb.min_value), -128, "u8 with bias 128 shows -128 at the low end")
	_assert_eq(int(sb.max_value), 127, "…and 127 at the high end")
	_assert_eq(int(sb.value), 0, "raw 128 displays as 0 (centred)")
	sb.value = 10
	_assert_eq(mutations[0][1], 138, "display 10 fans raw 138 (10 + bias)")


## A `unit` descriptor (ParticleUnits.POS_TILES: 28 raw/tile) shows the HUMAN value
## and fans RAW — the choke point never sees anything but raw. A plain (unflipped)
## unit cell is magnitude-only: raw 28 shows +1 tile, editing to +3 fans raw 84.
func _test_unit_cell_seeds_and_fans_human_value() -> void:
	var mutations: Array = []
	var ref := _ref("spread_start_y")
	var insp = _show([_int_field("Y", "s16", 28, ref,
		{"unit": ParticleUnits.POS_TILES})], mutations)
	var sb = insp.int_widgets()[0]
	_assert_true(abs(sb.value - 1.0) < 0.001, "raw 28 shows +1 tile")
	_assert_eq(mutations.size(), 0, "seeding fires no edit")
	sb.value = 3.0
	_assert_eq(mutations[0][1], 84, "editing to +3 tiles fans raw 84 (3 · 28)")


## ADR-0089 amendment: a `flip_sign` unit cell authors GAME-UP — it shows −raw/28
## (the value the sim caches) and commits the OPPOSITE raw, so dialing +Y stores a
## negative byte (the PSX `-Y = up` storage) and a game→raw→game round-trip is
## identity. This is the chirality half of the game-unit flip; magnitude still
## routes through the ParticleUnits descriptor untouched.
func _test_flip_sign_authors_game_up_and_commits_opposite() -> void:
	var mutations: Array = []
	var ref := _ref("position_start_y")
	# Fixture: raw position_start_y = -28 (PSX -Y up). The author should see +1 tile.
	var insp = _show([_int_field("Y", "s16", -28, ref,
		{"unit": ParticleUnits.POS_TILES, "flip_sign": true})], mutations)
	var sb = insp.int_widgets()[0]
	_assert_true(abs(sb.value - 1.0) < 0.001, "raw -28 authors as +1 tile (game-up)")
	_assert_eq(mutations.size(), 0, "seeding fires no edit")
	# Dial +2 tiles (up): the stored raw moves the OPPOSITE way (-56).
	sb.value = 2.0
	_assert_eq(mutations.size(), 1, "editing fans one edit")
	_assert_eq(mutations[0][1], -56, "dialing +2 tiles up commits raw -56 (the opposite sign)")
	# Round-trip identity at display precision: re-seeding the committed raw shows +2.
	var insp2 = _show([_int_field("Y", "s16", -56, ref,
		{"unit": ParticleUnits.POS_TILES, "flip_sign": true})], [])
	_assert_true(abs(insp2.int_widgets()[0].value - 2.0) < 0.001,
		"game→raw→game is identity: raw -56 re-authors as +2 tiles")


# --- enum ------------------------------------------------------------------

## Unlike `choice` (index-aligned to ScreenMode), `enum` carries an explicit VALUE
## per item, so a field whose codes aren't 0..N-1 fans the real code.
## A cell-level `prefix` decorates the field's display (e.g. "±" for a symmetric shake
## amplitude) without touching the stored value or the fanned raw — a pure display hint.
func _test_int_prefix_decorates_the_display() -> void:
	var mutations: Array = []
	var ref := _ref("amp")
	var insp = _show([_int_field("X amplitude", "s16", 57, ref, {"prefix": "±"})], mutations)
	var sb = insp.int_widgets()[0]
	_assert_eq(str(sb.prefix), "±", "the cell's prefix reaches the ScrubField")
	_assert_eq(int(sb.value), 57, "prefix does not change the seeded value")
	sb.value = 40
	_assert_eq(mutations[0][1], 40, "prefix does not change the fanned raw")


func _test_enum_carries_value_not_index() -> void:
	var mutations: Array = []
	var ref := _ref("mode")
	var choices := [{"value": 0, "label": "None"}, {"value": 5, "label": "Add"}, {"value": 10, "label": "Sub"}]
	var insp = _show([_enum_field("Mode", 5, choices, ref)], mutations)

	var enums: Array = insp.enum_widgets()
	_assert_eq(enums.size(), 1, "an enum cell renders ONE dropdown")
	if enums.is_empty():
		return
	var ob: OptionButton = enums[0]
	_assert_eq(ob.item_count, 3, "one item per choice")
	_assert_eq(ob.get_item_id(ob.selected), 5, "seeded to the item whose VALUE is current (5), not index 1")
	_assert_eq(mutations.size(), 0, "seeding fires no edit")

	# Select the "Sub" item (value 10, index 2) as a user would.
	ob.selected = 2
	ob.item_selected.emit(2)
	_assert_eq(mutations.size(), 1, "selecting fans one edit")
	_assert_eq(mutations[0][1], 10, "the fanned raw is the item's VALUE (10), not its index (2)")


# --- bitflags --------------------------------------------------------------

func _test_bitflags_group_recomputes_word() -> void:
	var mutations: Array = []
	var ref := _ref("flags")
	var bits := [{"mask": 1, "label": "A"}, {"mask": 2, "label": "B"}, {"mask": 4, "label": "C"}, {"mask": 8, "label": "D"}]
	var insp = _show([_bitflags_field("Flags", 0b0101, bits, ref)], mutations)

	var groups: Array = insp.bitflag_widgets()
	_assert_eq(groups.size(), 1, "a bitflags cell renders ONE checkbox group")
	if groups.is_empty():
		return
	var boxes: Array = groups[0]
	_assert_eq(boxes.size(), 4, "one checkbox per declared bit")
	_assert_true(boxes[0].button_pressed, "bit A (mask 1) is set in 0b0101")
	_assert_true(not boxes[1].button_pressed, "bit B (mask 2) is clear")
	_assert_true(boxes[2].button_pressed, "bit C (mask 4) is set")
	_assert_eq(mutations.size(), 0, "seeding the group fires no edit")

	# Toggle B on → word becomes 0b0111 = 7.
	boxes[1].button_pressed = true
	boxes[1].toggled.emit(true)
	_assert_eq(mutations[-1][1], 7, "toggling B on recomputes the whole word to 7")
	# Toggle A off → word becomes 0b0110 = 6 (running state carried across toggles).
	boxes[0].button_pressed = false
	boxes[0].toggled.emit(false)
	_assert_eq(mutations[-1][1], 6, "a second toggle recomputes from the running word (6)")
	_assert_true(mutations[-1][0] == ref, "each edit carries the cell's field_ref")


# --- curve -----------------------------------------------------------------

## A `curve` editor renders a sparkline bound to a real curve; pressing it opens
## the painter through the same on_open seam the emitter sparklines use.
func _test_curve_editor_opens_painter() -> void:
	var samples := [0.0, 0.5, 1.0]
	var opened := {"idx": -1, "name": ""}
	var insp = _inspector()
	insp.show_target(Target.span("time_scale#0"), [], [_section([_curve_field("Slowdown", 0)])],
		func(_i): return samples,
		func(ci, nm): opened["idx"] = ci; opened["name"] = nm)

	var fired := false
	for s in insp.sparklines():
		if s.is_enabled():
			s.pressed.emit()
			fired = true
			break
	_assert_true(fired, "the curve editor renders an enabled sparkline")
	_assert_eq(opened["idx"], 0, "pressing it opens THAT curve index")
	_assert_eq(opened["name"], "Slowdown", "the open carries the param name")


## ADR-0089 curve-UX amendment — the on_open seam carries `used_n` so the painter
## can veil the same window the sparkline trims (identical datum). A 3-arg consumer
## receives it; the legacy 2-arg callback still works (arity-aware call).
func _test_curve_open_carries_used_window() -> void:
	var opened := {"idx": -1, "name": "", "used_n": -999}
	var insp = _inspector()
	var field := _curve_field("Slowdown", 0)
	field["used_n"] = 40
	insp.show_target(Target.span("time_scale#0"), [], [_section([field])],
		func(_i): return [0.0, 0.5, 1.0],
		func(ci, nm, un): opened["idx"] = ci; opened["name"] = nm; opened["used_n"] = un)
	for s in insp.sparklines():
		if s.is_enabled():
			s.pressed.emit()
			break
	_assert_eq(opened["used_n"], 40, "the open carries the param's used window (same datum as the trim)")


## A pick fans the chosen shape's SAMPLES through the cell's field_ref — one edit, and the
## payload is the whole shape rather than an index, because the picker's verb is COPY since
## the ADR-0089 curve-ownership amendment (there is no shared slot left to point at).
## `none` is the one choice that fans an EMPTY array: it clears the address.
func _test_curve_pick_fans_the_chosen_shape_through_field_ref() -> void:
	var mutations: Array = []
	var ref := _ref("curve_position")
	var insp = _show([_curve_pick_field(ref, 0)], mutations)
	var pickers: Array = insp.curve_pick_widgets()
	_assert_eq(pickers.size(), 1, "a curve_pick cell renders ONE picker")
	if pickers.is_empty():
		return
	pickers[0].pick(2)   # choose "Shape 2"
	_assert_eq(mutations.size(), 1, "picking fans exactly one edit")
	if mutations.is_empty():
		return
	_assert_true(mutations[0][0] == ref, "the edit carries the cell's field_ref")
	_assert_eq(Array(mutations[0][1]).size(), 160, "…and the WHOLE shape (a pick copies)")
	_assert_eq(int(Array(mutations[0][1])[0]), 64, "…the one that was picked")
	pickers[0].pick(0)
	_assert_eq(Array(mutations[1][1]).size(), 0, "none fans an empty array — it clears the address")


## Picker thumbnails browse curve SHAPES, so they draw the WHOLE curve un-trimmed
## (fully bright) — the used-window belongs to the param, identical for every
## candidate, so trimming there would mislead.
func _test_curve_pick_thumbnails_are_whole_curve() -> void:
	var insp = _show([_curve_pick_field(_ref("curve_position"), 0)], [])
	var picker = insp.curve_pick_widgets()[0]
	var thumbs: Array = picker.thumbnails()
	_assert_eq(thumbs.size(), 3, "one thumbnail per choice (none + 2 curves)")
	for t in thumbs:
		_assert_eq(t.used_window(), -1, "a browse thumbnail is whole-curve, un-trimmed")


## The button face shows the ASSIGNED curve as a mini sparkline; picking a new curve
## updates the face to that curve.
func _test_curve_pick_face_reflects_the_assigned_curve() -> void:
	var insp = _show([_curve_pick_field(_ref("curve_position"), 1)], [])
	var picker = insp.curve_pick_widgets()[0]
	_assert_eq(picker.current_value(), 1, "the picker seeds to the shape it draws")
	picker.pick(0)
	_assert_eq(picker.current_value(), 0, "picking none updates the face state")


## The face shows a SHORT label (the choice label with any parenthetical stripped), so a
## label that grows a clarifying parenthetical still reads as a word instead of clipping
## mid-word ("none (l…") in the narrow assignment cell.
func _test_curve_pick_face_label_is_short_not_clipped() -> void:
	var insp = _show([_curve_pick_field(_ref("curve_position"), 0)], [])
	var picker = insp.curve_pick_widgets()[0]
	_assert_eq(picker.face_label_text(), "none", "value 0 face reads 'none'")
	picker.pick(2)
	_assert_eq(picker.face_label_text(), "Shape 2", "a picked shape's face reads its short label")


## A use site can draw a shape nothing ELSE in the effect draws — it is then not in the
## distinct set the grid was built from, so no choice matches. The face names it by what it
## is rather than by a number: a private curve index is an export concern and tells an
## author nothing. (It used to read "Curve N", back when the value WAS a table index.)
func _test_curve_pick_out_of_choices_value_names_the_shape() -> void:
	var insp = _show([_curve_pick_field(_ref("curve_position"), 0)], [])
	var picker = insp.curve_pick_widgets()[0]
	picker.pick(5)   # value 5 is beyond the fixture's choices (which stop at 2)
	_assert_eq(picker.face_label_text(), "this shape",
		"a shape outside the offered set is named, not numbered")


## `set_value` re-syncs the face to a new nibble WITHOUT fanning an edit — the page uses
## it to move a curve_pick onto the forked curve after a recolour (a live in-place refresh,
## not an author-driven pick, so no mutate must fire).
func _test_curve_pick_set_value_syncs_face_without_firing() -> void:
	var mutations: Array = []
	var insp = _show([_curve_pick_field(_ref("curve_position"), 1)], mutations)
	var picker = insp.curve_pick_widgets()[0]
	picker.set_value(2)
	_assert_eq(picker.current_value(), 2, "set_value updates the face state")
	_assert_eq(picker.face_label_text(), "Shape 2", "…and the face label")
	_assert_eq(mutations.size(), 0, "set_value fans NO edit (it is a refresh, not a pick)")


## ADR-0089 colour-keyframe editing-UX amendment (decision 5, the BUG): the three
## `Color (R/G/B) · curve` rows carry a `colour_channel` tag; the inspector records their
## sparkline + curve_pick by channel and exposes a `refresh_colour_channels` seam. A recolour
## FORKS the emitter's colour curves onto fresh indices — the page re-feeds each sparkline
## with the forked curve's live samples and moves each picker onto the forked nibble, so the
## "curves on the left" stop going stale.
func _test_colour_channel_curves_recorded_and_refreshable() -> void:
	var provider := func(i): return [float(i), float(i) + 0.5, float(i) + 1.0]  # distinct per index
	var insp = _inspector()
	insp.show_target(Target.span("kit#0"), [], [_section([
			_colour_curve_field("r", _ref("color_curve_r"), 1),
			_colour_curve_field("g", _ref("color_curve_g"), 1),
			_colour_curve_field("b", _ref("color_curve_b"), 1)])],
		provider, func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass, func(_r, _raw): pass)

	var sparks: Dictionary = insp.colour_channel_sparklines()
	_assert_true(sparks.has("r") and sparks.has("g") and sparks.has("b"),
		"the three colour channel sparklines are recorded by channel")
	var pickers: Dictionary = insp.colour_channel_pickers()
	_assert_true(pickers.has("r") and pickers.has("g") and pickers.has("b"),
		"the three colour channel pickers are recorded by channel")
	if not (sparks.has("g") and pickers.has("b")):
		return

	# The recolour rewrites r/g/b into fresh shapes (here modelled as curves 15/16/17).
	insp.refresh_colour_channels({"r": 15, "g": 16, "b": 17}, provider)
	_assert_eq(Array(sparks["g"].samples()), provider.call(16),
		"refresh re-feeds the G sparkline with the channel's live samples")
	_assert_eq(Array(pickers["b"].face_sparkline().samples()), provider.call(17),
		"…and re-paints the B picker's FACE from those samples, not from an index")
	_assert_eq(pickers["b"].face_label_text(), "this shape",
		"…named, not numbered — a recoloured shape is in no grid and has no shared index")


# --- shared invariants -----------------------------------------------------

func _test_seeding_fires_no_edit() -> void:
	var mutations: Array = []
	_show([
		_int_field("R", "u8", 40, _ref("r")),
		_enum_field("M", 5, [{"value": 5, "label": "x"}], _ref("m")),
		_bitflags_field("F", 3, [{"mask": 1, "label": "a"}, {"mask": 2, "label": "b"}], _ref("f")),
	], mutations)
	_assert_eq(mutations.size(), 0, "seeding a whole mixed section fires zero edits")


func _test_clear_drops_kit_widgets() -> void:
	var insp = _show([_int_field("R", "u8", 1, _ref("r")), _enum_field("M", 0, [{"value": 0, "label": "x"}], _ref("m"))], [])
	_assert_true(insp.int_widgets().size() + insp.enum_widgets().size() == 2, "kit widgets rendered before clear")
	insp.clear()
	_assert_eq(insp.int_widgets().size(), 0, "clear() drops int widgets")
	_assert_eq(insp.enum_widgets().size(), 0, "clear() drops enum widgets")
	_assert_eq(insp.bitflag_widgets().size(), 0, "clear() drops bitflag groups")


# --- fixtures --------------------------------------------------------------

func _inspector():
	var insp = Inspector.new()
	add_child(insp)
	return insp


## Render a single section of edit fields and wire the mutate callback into `sink`.
# --- cells (ADR-0089 two-axis emitter rows) --------------------------------

## A `cells` row is a strip of sub-cells in ONE value column (min/max or X/Y/Z on
## an emitter axis row). Each sub-cell is a full kit editor with its OWN field_ref;
## editing one fans only that cell's edit.
func _test_cells_row_renders_a_strip_of_sub_cells() -> void:
	var mutations: Array = []
	var cells := [
		{"editor": "int", "type": "s16", "value": 28, "label": "X", "field_ref": _ref("px")},
		{"editor": "int", "type": "s16", "value": -28, "label": "Y", "field_ref": _ref("py")},
	]
	var insp = _show([{"name": "Position · at start", "shape": "edit", "editor": "cells",
		"cells": cells}], mutations)
	var spins: Array = insp.int_widgets()
	_assert_eq(spins.size(), 2, "each sub-cell renders its own spinbox")
	if spins.size() < 2:
		return
	_assert_eq(int(spins[0].value), 28, "cell 0 seeds its raw")
	_assert_eq(int(spins[1].value), -28, "cell 1 seeds its raw")
	_assert_eq(mutations.size(), 0, "seeding the strip fires no edit")
	spins[1].value = 5
	_assert_eq(mutations.size(), 1, "editing one cell fans one edit")
	if mutations.is_empty():
		return
	_assert_true(mutations[0][0] == _ref("py"), "the edit carries the SUB-cell's field_ref")


## ADR-0089 decision 5 — the sparkline used-window API: the full 160 samples
## always draw (agreeing with the painter); an optional window N marks samples
## 0..N bright and dims the tail. No/oversized window = fully bright.
func _test_sparkline_used_window_api() -> void:
	var spark = Sparkline.new()
	add_child(spark)
	spark.set_curve([0.0, 0.5, 1.0], true)
	_assert_eq(spark.used_window(), -1, "no window by default (fully bright)")
	spark.set_curve([0.0, 0.5, 1.0], true, 2)
	_assert_eq(spark.used_window(), 2, "set_curve carries the used window")


## ADR-0089 #291 follow-on — the LINEAR glyph: a group with no assigned curve
## still shows its interpolation shape (a straight start→end slope), but it is a
## read-only glyph: not an editable curve (is_enabled false), no used window, and
## it reports linear mode so the header can render it dim + non-clickable.
func _test_sparkline_linear_mode() -> void:
	var spark = Sparkline.new()
	add_child(spark)
	spark.set_linear(2.0, 8.0)
	_assert_true(not spark.is_enabled(), "a linear glyph is not an editable curve")
	_assert_true(spark.is_linear(), "…and reports linear mode")
	_assert_eq(spark.used_window(), -1, "a linear glyph has no used window")
	# set_curve must clear linear mode (widgets are reused across rebuilds).
	spark.set_curve([0.0, 0.5, 1.0], true, 40)
	_assert_true(not spark.is_linear(), "assigning a real curve clears linear mode")


## ADR-0089 curve-UX amendment — the sparkline TRIMS to the used window (reverses
## the old "full 160, tail dimmed"). A real sub-window (0 < N < 160) plots only its
## leading N samples; a wrapping (>= 160), animation-driven (-1), or degenerate
## (<= 0) window plots the WHOLE curve un-trimmed.
func _test_sparkline_windowed_samples_trims_real_window_else_whole() -> void:
	var ten := [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
	_assert_eq(Sparkline.windowed_samples(ten, 4).size(), 4, "0<N<len trims to N samples")
	_assert_eq(Sparkline.windowed_samples(ten, 4)[0], 0.0, "…keeping the leading samples")
	_assert_eq(Sparkline.windowed_samples(ten, -1).size(), 10, "-1 (animation-driven) = whole")
	_assert_eq(Sparkline.windowed_samples(ten, 0).size(), 10, "0 (degenerate) = whole")
	_assert_eq(Sparkline.windowed_samples(ten, 20).size(), 10, "N wider than data = whole")
	var whole: Array = _flat(160, 0.0)
	_assert_eq(Sparkline.windowed_samples(whole, 200).size(), 160, ">=160 wraps = whole curve")


## The trimmed window's Y is re-fit to the PLOTTED samples' own min/max — a spike
## PAST the window no longer squashes the visible part. samples[3]=100 sits outside
## a 2-frame window, so the window [0,1] fills top-to-bottom (value 1 → top).
func _test_sparkline_plot_points_refits_y_to_the_trimmed_window() -> void:
	var pts: PackedVector2Array = Sparkline.plot_points([0.0, 1.0, 0.0, 100.0], 2, Vector2(100, 10))
	_assert_eq(pts.size(), 2, "only the 2-frame window is plotted (spike excluded)")
	if pts.size() < 2:
		return
	# Value 0 → bottom (y≈10), value 1 → top (y≈0). A whole-curve normalize over
	# [0..100] would instead put value 1 near the bottom (y≈9.9) — this distinguishes.
	_assert_true(pts[0].y > 9.0, "the window's min (0) sits at the bottom")
	_assert_true(pts[1].y < 1.0, "the window's max (1) sits at the top — re-fit, not squashed")


## A short window is a full-width shape, not a sliver: the last plotted point sits at
## the sparkline's right edge (X-stretched across the whole width).
func _test_sparkline_plot_points_stretches_short_window_full_width() -> void:
	var pts: PackedVector2Array = Sparkline.plot_points([0.0, 0.25, 0.5, 0.75], 4, Vector2(200, 10))
	_assert_eq(pts.size(), 4, "the 4-frame window plots 4 points")
	if pts.size() < 4:
		return
	_assert_eq(pts[0].x, 0.0, "first point at the left edge")
	_assert_eq(pts[3].x, 200.0, "last point stretched to the right edge (full width)")


## Height normalization OFF (Absolute): Y maps to a FIXED 0..1 range, not the window's
## own min/max — so a low-amplitude curve reads as small (true magnitude). Value 0.5
## sits mid-box; a window re-fit would instead push it to the top.
func _test_sparkline_absolute_height_maps_to_fixed_range() -> void:
	var pts: PackedVector2Array = Sparkline.plot_points([0.0, 0.5], 2, Vector2(100, 10), true, false)
	_assert_eq(pts.size(), 2, "both samples plotted")
	if pts.size() < 2:
		return
	_assert_true(pts[0].y > 9.0, "absolute: value 0 at the bottom")
	_assert_true(abs(pts[1].y - 5.0) < 0.6, "absolute: value 0.5 sits MID-box (not re-fit to the top)")


## Width normalization OFF (Whole): the whole curve draws even with a used window set —
## the trim is skipped, so all samples are plotted.
func _test_sparkline_untrimmed_width_ignores_the_window() -> void:
	var ten := [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
	var trimmed: PackedVector2Array = Sparkline.plot_points(ten, 4, Vector2(100, 10), true, true)
	var whole: PackedVector2Array = Sparkline.plot_points(ten, 4, Vector2(100, 10), false, true)
	_assert_eq(trimmed.size(), 4, "trim on: only the 4-frame window")
	_assert_eq(whole.size(), 10, "trim off: the whole curve regardless of the window")


## The live widget's _draw honors the GLOBAL toggles (studio transport buttons set
## these statics): flipping trim_width off makes a windowed sparkline draw whole.
func _test_sparkline_draw_honors_the_global_toggles() -> void:
	var spark = Sparkline.new()
	add_child(spark)
	spark.set_curve([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], true, 4)
	var before := Sparkline.display_trim_width
	Sparkline.display_trim_width = true
	_assert_eq(spark.plotted_points(Vector2(100, 10)).size(), 4, "trim on → windowed plot")
	Sparkline.display_trim_width = false
	_assert_eq(spark.plotted_points(Vector2(100, 10)).size(), 10, "trim off → whole-curve plot")
	Sparkline.display_trim_width = before   # restore the global for other tests


## Absolute (Fit H off) has no implicit scale — a curve peaking below max sits mid-box
## with nothing marking where 255 is. So absolute mode draws a ceiling/baseline guide
## (the box becomes the 0→max reference); fit mode omits it (the curve fills the box, so
## the top is the curve's own peak, not max — a ceiling line there would mislead).
func _test_sparkline_absolute_mode_marks_the_ceiling() -> void:
	var spark = Sparkline.new()
	add_child(spark)
	spark.set_curve([0.0, 0.3, 0.5], true, -1)
	var h0 := Sparkline.display_normalize_height
	Sparkline.display_normalize_height = true
	_assert_true(not spark.shows_absolute_guides(), "fit mode draws NO ceiling guide")
	Sparkline.display_normalize_height = false
	_assert_true(spark.shows_absolute_guides(), "absolute mode marks the ceiling + baseline")
	spark.set_linear(0.0, 1.0)
	_assert_true(not spark.shows_absolute_guides(), "the no-curve linear glyph never shows guides")
	Sparkline.display_normalize_height = h0


## A curve cell's projector-declared `used_n` rides into the live widget.
func _test_curve_cell_used_window_reaches_the_sparkline() -> void:
	var insp = _show([{"name": "Position · curve", "shape": "edit", "editor": "curve",
		"curve_index": 0, "used_n": 40}], [])
	_assert_eq(insp.sparklines()[0].used_window(), 40, "the cell's used_n lands on the widget")


func _show(fields: Array, sink: Array):
	var insp = _inspector()
	insp.show_target(Target.span("kit#0"), [], [_section(fields)],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): sink.append([ref, raw]))
	return insp


func _section(fields: Array) -> Dictionary:
	return {"title": "Kit", "fields": fields}


func _ref(field: String) -> Dictionary:
	return {"channel": "kit", "context": "for_each", "event_index": 0, "field": field}


func _flat(n: int, v: float) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(v)
	return a


func _int_field(name: String, type: String, value: int, ref: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var f := {"name": name, "shape": "edit", "editor": "int", "type": type, "value": value, "field_ref": ref}
	for k in extra:
		f[k] = extra[k]
	return f


func _enum_field(name: String, value: int, choices: Array, ref: Dictionary) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "enum", "value": value, "choices": choices, "field_ref": ref}


## A curve_pick cell as EmitterParamRows.curve_row emits it since the ADR-0089
## curve-ownership amendment: choices over the effect's DISTINCT SHAPES, each carrying its
## own 0-255 samples (the pick COPIES a shape — there is no shared slot to name).
func _curve_pick_field(ref: Dictionary, value: int) -> Dictionary:
	return {"name": "Position · curve", "shape": "edit", "editor": "curve_pick", "value": value,
		"field_ref": ref, "choices": [
			{"value": 0, "label": "none", "samples": []},
			{"value": 1, "label": "Shape 1", "samples": _ramp(0)},
			{"value": 2, "label": "Shape 2", "samples": _ramp(64)}]}


## A 160-sample 0-255 shape, offset so two of them are distinct.
func _ramp(base: int) -> Array:
	var out: Array = []
	for i in range(160):
		out.append(clampi(base + i, 0, 255))
	return out


## A colour-curve row as EmitterParamRows.color_curve_row emits it — a `cells` strip of a
## curve_pick + a curve sparkline, both tagged with the `colour_channel` the inspector keys on.
func _colour_curve_field(chan: String, ref: Dictionary, value: int) -> Dictionary:
	var choices := [{"value": 0, "label": "none", "samples": []},
		{"value": 1, "label": "Shape 1", "samples": _ramp(0)},
		{"value": 2, "label": "Shape 2", "samples": _ramp(64)}]
	return {"name": "Color (%s) · curve" % chan.to_upper(), "shape": "edit", "editor": "cells",
		"colour_channel": chan, "cells": [
			{"editor": "curve_pick", "value": value, "field_ref": ref, "choices": choices,
				"colour_channel": chan},
			{"editor": "curve", "name": "Color (%s) · curve" % chan.to_upper(),
				"curve_index": value - 1, "used_n": 40, "colour_channel": chan}]}


func _bitflags_field(name: String, value: int, bits: Array, ref: Dictionary) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "bitflags", "value": value, "bits": bits, "field_ref": ref}


func _curve_field(name: String, curve_index: int) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "curve", "curve_index": curve_index}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
