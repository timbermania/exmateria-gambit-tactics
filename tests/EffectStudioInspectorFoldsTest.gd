extends Node
## TDD guard for the ADR-0089 inspector presentation (#291) — collapsible
## single-column parameter-group folds in EffectKeyframeInspector.
##
## Group-stamped rows (EmitterParamRows' explicit group identity) cluster into
## one nested fold per parameter group inside their section: fresh inspect =
## collapsed, fold state is remembered per (emitter, group) for the session so
## show_target rebuilds (re-selection / live-reproject) don't reset it, and an
## Expand all / Collapse all control sits on a section that carries folds. The
## width-based two-per-line reflow is deleted inspector-wide: a group grid keeps
## its intrinsic sub-column count no matter how wide the panel is.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioInspectorFoldsTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_group_rows_cluster_into_folds()
	_test_fresh_inspect_collapses_folds()
	_test_toggling_a_fold_shows_its_body()
	_test_fold_state_survives_rebuild()
	_test_fold_state_is_per_emitter()
	_test_expand_all_and_collapse_all()
	_test_bulk_state_survives_rebuild()
	_test_single_column_no_width_reflow()
	_test_collapsed_header_shows_summary()
	_test_inert_group_dims()
	_test_collapsed_header_carries_mini_sparkline_iff_curve()
	_test_non_inert_no_curve_group_shows_linear_shape()
	_test_fixed_widths_align_columns()

	print("\n=== EffectStudioInspectorFoldsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioInspectorFoldsTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioInspectorFoldsTest")
		get_tree().quit(0)


## Two parameter groups + one ungrouped row → two folds hung on the EXPLICIT
## group stamp (never the name prefix), the ungrouped row rendered outside any
## fold. Every row still renders (the fold hides, it doesn't drop).
func _test_group_rows_cluster_into_folds() -> void:
	var insp = _show_groups()
	var folds: Array = insp.param_folds()
	_assert_eq(folds.size(), 2, "two group stamps make two folds")
	if folds.size() < 2:
		return
	_assert_eq(str(folds[0]["key"]), "0:position", "fold key = emitter:group")
	_assert_eq(str(folds[1]["key"]), "0:weight", "second group folds separately")
	_assert_eq(str(folds[0]["label"]), "Position", "fold label is the group label")
	_assert_eq(insp.param_row_count(), 7, "all rows render (2 groups x 3 + 1 ungrouped)")
	_assert_eq(insp.int_widgets().size(), 5, "grouped AND ungrouped edit cells are all built")


## Fresh inspect = every fold collapsed (the summary is the scan surface).
func _test_fresh_inspect_collapses_folds() -> void:
	var insp = _show_groups()
	for fold in insp.param_folds():
		_assert_true(not fold["body"].visible, "fold '%s' starts collapsed" % fold["key"])


## The fold header is the accordion toggle: pressing it reveals the body.
func _test_toggling_a_fold_shows_its_body() -> void:
	var insp = _show_groups()
	var fold: Dictionary = insp.param_folds()[0]
	fold["header"].button_pressed = true
	_assert_true(fold["body"].visible, "expanding a fold shows its rows")
	fold["header"].button_pressed = false
	_assert_true(not fold["body"].visible, "collapsing hides them again")


## Session fold state: expanding a group survives a show_target rebuild
## (re-selection and live-reproject rebuild rows; the fold must not snap shut).
func _test_fold_state_survives_rebuild() -> void:
	var insp = _inspector()
	_show_groups_on(insp)
	insp.param_folds()[0]["header"].button_pressed = true
	_show_groups_on(insp)   # rebuild, same emitter
	var folds: Array = insp.param_folds()
	_assert_true(folds[0]["body"].visible, "the expanded fold stays expanded across a rebuild")
	_assert_true(not folds[1]["body"].visible, "the untouched fold stays collapsed")


## Fold state is keyed per (emitter, group): emitter 1's Position fold does not
## inherit emitter 0's expansion.
func _test_fold_state_is_per_emitter() -> void:
	var insp = _inspector()
	_show_groups_on(insp)
	insp.param_folds()[0]["header"].button_pressed = true
	insp.show_target(Target.span("folds#1"), [], [_grouped_section(1)],
		func(_i): return [], func(_a, _b): pass)
	_assert_true(not insp.param_folds()[0]["body"].visible,
		"another emitter's same-named group starts collapsed")


## A section that carries folds offers Expand all / Collapse all, driving every
## fold in that section at once.
func _test_expand_all_and_collapse_all() -> void:
	var insp = _show_groups()
	var bulk: Array = insp.fold_bulk_buttons()
	_assert_eq(bulk.size(), 1, "the fold-carrying section offers one bulk control")
	if bulk.is_empty():
		return
	bulk[0]["expand"].pressed.emit()
	for fold in insp.param_folds():
		_assert_true(fold["body"].visible, "Expand all opens fold '%s'" % fold["key"])
	bulk[0]["collapse"].pressed.emit()
	for fold in insp.param_folds():
		_assert_true(not fold["body"].visible, "Collapse all shuts fold '%s'" % fold["key"])


## Bulk expansion is remembered like any other fold state.
func _test_bulk_state_survives_rebuild() -> void:
	var insp = _inspector()
	_show_groups_on(insp)
	insp.fold_bulk_buttons()[0]["expand"].pressed.emit()
	_show_groups_on(insp)
	for fold in insp.param_folds():
		_assert_true(fold["body"].visible, "bulk-expanded fold '%s' survives the rebuild" % fold["key"])


## Decision 1: single column inspector-wide. The two-per-line width reflow is
## gone — a wide panel never doubles a group grid's columns.
func _test_single_column_no_width_reflow() -> void:
	var insp = _inspector()
	insp.size = Vector2(1400, 800)   # comfortably past the old 2-line threshold
	_show_groups_on(insp)
	insp.size = Vector2(1500, 800)   # resize after build — no reflow may fire
	var entries: Array = insp.group_grid_columns()
	_assert_true(entries.size() > 0, "group grids exist")
	for e in entries:
		_assert_eq(int(e["columns"]), int(e["sub_cols"]),
			"a group grid keeps its intrinsic sub-columns at any width")


## Decision 3: a collapsed fold header carries the stamp's summary (the scan
## surface) with the full values on its tooltip; expanding hides the summary —
## the editing cells take over.
func _test_collapsed_header_shows_summary() -> void:
	var insp = _inspector()
	insp.show_target(Target.span("folds#s"), [], [_summary_section()],
		func(_i): return [], func(_a, _b): pass)
	var fold: Dictionary = insp.param_folds()[0]
	_assert_true("(1, -1, 0) → (0, 0, 0)" in fold["header"].text,
		"collapsed header shows the start → end summary")
	_assert_true("Position" in fold["header"].text, "…beside the group label")
	_assert_eq(str(fold["header"].tooltip_text), "full: (1, -1, 0) → (0, 0, 0)",
		"full values ride the header tooltip")
	fold["header"].button_pressed = true
	_assert_true(not ("(1, -1, 0)" in fold["header"].text),
		"expanding hides the summary (the cells take over)")
	fold["header"].button_pressed = false
	_assert_true("(1, -1, 0) → (0, 0, 0)" in fold["header"].text,
		"collapsing brings the summary back")


## Decision 3: an inert group (stamp says all zero, no curve) renders dimmed.
func _test_inert_group_dims() -> void:
	var insp = _inspector()
	insp.show_target(Target.span("folds#i"), [], [_summary_section()],
		func(_i): return [], func(_a, _b): pass)
	var folds: Array = insp.param_folds()
	_assert_eq(folds[1]["header"].modulate, Inspector.COL_DIM, "inert fold header dims")
	_assert_eq(folds[0]["header"].modulate, Color.WHITE, "a live fold does not")


## Decision 3+5: a curve-assigned group's collapsed header carries a mini
## sparkline (dimmed by the group's used window); expanding hides it — the
## curve row's own sparkline takes over. No curve → no header spark.
func _test_collapsed_header_carries_mini_sparkline_iff_curve() -> void:
	var insp = _inspector()
	var curved := {"id": "position", "label": "Position", "emitter_index": 0,
		"summary": "(1, 0, 0) → (0, 0, 0)", "inert": false, "curve_index": 0, "used_n": 5}
	var flat := {"id": "weight", "label": "Gravity scale", "emitter_index": 0,
		"summary": "0 → 0", "inert": true, "curve_index": -1, "used_n": -1}
	var fields: Array = []
	for stamp in [curved, flat]:
		fields.append({"name": "%s · at start" % stamp["label"], "shape": "edit",
			"editor": "cells", "group": stamp,
			"cells": [{"editor": "int", "type": "s16", "value": 0, "label": "X",
				"field_ref": _ref(0, str(stamp["id"]) + "_start")}]})
	insp.show_target(Target.span("folds#spark"), [], [{"title": "Emitter", "fields": fields}],
		func(_i): return [0.0, 0.5, 1.0], func(_a, _b): pass)
	var folds: Array = insp.param_folds()
	_assert_true(folds[0]["spark"] != null, "curve-assigned group grows a header sparkline")
	if folds[0]["spark"] != null:
		_assert_true(folds[0]["spark"].visible, "…visible while collapsed")
		_assert_eq(folds[0]["spark"].used_window(), 5, "header spark dims by the group's window")
		folds[0]["header"].button_pressed = true
		_assert_true(not folds[0]["spark"].visible, "expanding hides the header spark")
	_assert_true(folds[1]["spark"] == null, "no curve → no header spark")


## #291 follow-on: a NON-inert group with NO assigned curve still shows a shape —
## the LINEAR interpolation glyph (a straight start→end slope) — so every live
## group in the collapsed list reads its shape at a glance. It is a read-only
## glyph (is_enabled false / linear mode), distinct from a clickable curve spark.
## An INERT group (does nothing) stays blank.
func _test_non_inert_no_curve_group_shows_linear_shape() -> void:
	var insp = _inspector()
	var linear := {"id": "weight", "label": "Gravity scale", "emitter_index": 0,
		"summary": "192 → 0", "inert": false, "curve_index": -1, "used_n": -1,
		"traj": [192.0, 0.0]}
	var inert := {"id": "drag", "label": "Drag", "emitter_index": 0,
		"summary": "(0, 0, 0) → (0, 0, 0)", "inert": true, "curve_index": -1, "traj": [0.0, 0.0]}
	var fields: Array = []
	for stamp in [linear, inert]:
		fields.append({"name": "%s · at start" % stamp["label"], "shape": "edit",
			"editor": "cells", "group": stamp,
			"cells": [{"editor": "int", "type": "s16", "value": 0, "label": "X",
				"field_ref": _ref(0, str(stamp["id"]) + "_start")}]})
	insp.show_target(Target.span("folds#lin"), [], [{"title": "Emitter", "fields": fields}],
		func(_i): return [], func(_a, _b): pass)
	var folds: Array = insp.param_folds()
	_assert_true(folds[0]["spark"] != null, "a non-inert no-curve group grows a linear glyph")
	if folds[0]["spark"] != null:
		_assert_true(folds[0]["spark"].is_linear(), "…rendered as a linear (non-curve) glyph")
		_assert_true(not folds[0]["spark"].is_enabled(), "…read-only (not a clickable curve)")
		_assert_true(folds[0]["spark"].visible, "…visible while collapsed")
		folds[0]["header"].button_pressed = true
		_assert_true(not folds[0]["spark"].visible, "…hidden when the cells take over")
	_assert_true(folds[1]["spark"] == null, "an inert group shows no shape")


## One live summarized group + one inert group, stamps carrying decision-3 keys.
func _summary_section() -> Dictionary:
	var live := {"id": "position", "label": "Position", "emitter_index": 0,
		"summary": "(1, -1, 0) → (0, 0, 0)", "summary_tooltip": "full: (1, -1, 0) → (0, 0, 0)",
		"inert": false}
	var inert := {"id": "weight", "label": "Gravity scale", "emitter_index": 0,
		"summary": "0 → 0", "summary_tooltip": "full: 0–0 → 0–0", "inert": true}
	var fields: Array = []
	for stamp in [live, inert]:
		fields.append({"name": "%s · at start" % stamp["label"], "shape": "edit",
			"editor": "cells", "group": stamp,
			"cells": [{"editor": "int", "type": "s16", "value": 1, "label": "X",
				"field_ref": _ref(0, str(stamp["id"]) + "_start")}]})
	return {"title": "Emitter", "fields": fields}


## Decision 6: the row-name label and each cell type carry FIXED widths (clipped,
## not grown by long text) so columns align across every grid in the inspector.
func _test_fixed_widths_align_columns() -> void:
	var insp = _inspector()
	insp.show_target(Target.span("folds#w"), [], [
		_grouped_section(0),
		{"title": "Config", "fields": [
			{"name": "A very long configuration row name that must not stretch its column",
				"shape": "edit", "editor": "int", "type": "u8", "value": 1,
				"field_ref": _ref(0, "anim_index")},
			{"name": "Target anchor", "shape": "edit", "editor": "enum", "value": 0,
				"choices": [{"value": 0, "label": "WORLD"}],
				"field_ref": _ref(0, "target_anchor_mode")},
		]},
	], func(_i): return [], func(_a, _b): pass)

	for sb in insp.int_widgets():
		_assert_eq(sb.custom_minimum_size.x, Inspector.INT_CELL_WIDTH,
			"every int cell shares the fixed int width")
	for ob in insp.enum_widgets():
		_assert_eq(ob.custom_minimum_size.x, Inspector.ENUM_CELL_WIDTH,
			"every enum cell shares the fixed enum width")
		_assert_true(ob.clip_text, "an enum clips long items instead of growing its column")

	var seen := 0
	var bad := 0
	for grid in insp.find_children("", "GridContainer", true, false):
		var cols: int = grid.columns
		if cols <= 0 or grid.get_child_count() == 0:
			continue
		for i in range(grid.get_child_count()):
			if i % cols != 0:
				continue
			var name_cell = grid.get_child(i)
			if not (name_cell is Label):
				continue
			seen += 1
			if name_cell.custom_minimum_size.x != Inspector.NAME_COL_WIDTH or not name_cell.clip_text:
				bad += 1
	_assert_true(seen > 0, "row-name labels found across the grids")
	_assert_eq(bad, 0, "every row-name label shares the fixed, clipped name width")


# --- fixtures --------------------------------------------------------------

func _inspector():
	var insp = Inspector.new()
	add_child(insp)
	return insp


func _show_groups():
	var insp = _inspector()
	_show_groups_on(insp)
	return insp


func _show_groups_on(insp) -> void:
	insp.show_target(Target.span("folds#0"), [], [_grouped_section(0)],
		func(_i): return [], func(_a, _b): pass)


## A section shaped like the projector's emitter output: two stamped parameter
## groups (Position, Gravity scale) and one ungrouped config-style row.
func _grouped_section(em_idx: int) -> Dictionary:
	var fields: Array = []
	fields += _group_rows("position", "Position", em_idx)
	fields += _group_rows("weight", "Gravity scale", em_idx)
	fields.append({"name": "Animation set", "shape": "edit", "editor": "int",
		"type": "u8", "value": 3, "field_ref": _ref(em_idx, "anim_index")})
	return {"title": "Emitter", "fields": fields}


func _group_rows(gid: String, label: String, em_idx: int) -> Array:
	var stamp := {"id": gid, "label": label, "emitter_index": em_idx}
	return [
		{"name": "%s · at start" % label, "shape": "edit", "editor": "cells", "group": stamp,
			"cells": [{"editor": "int", "type": "s16", "value": 1, "label": "X",
				"field_ref": _ref(em_idx, gid + "_start")}]},
		{"name": "%s · at end" % label, "shape": "edit", "editor": "cells", "group": stamp,
			"cells": [{"editor": "int", "type": "s16", "value": 2, "label": "X",
				"field_ref": _ref(em_idx, gid + "_end")}]},
		{"name": "%s · curve" % label, "shape": "edit", "editor": "enum", "value": 0,
			"choices": [{"value": 0, "label": "none"}], "group": stamp,
			"field_ref": _ref(em_idx, "curve_" + gid)},
	]


func _ref(em_idx: int, field: String) -> Dictionary:
	return {"channel": "emitter", "emitter_index": em_idx, "field": field}


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
