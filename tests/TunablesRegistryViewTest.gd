extends Node
## Guard for the REGISTRY page view (ADR-0068): TunablesRegistryView builds a table
## row per registered slug and its value cell is a TuneField-bound control — so an
## edit in the registry writes the slug (and thus syncs with that knob's panel card).
##
## The find box is graded by what the page EMITS, never by "a LineEdit exists": the
## arms drive the real `text_changed` signal and assert the resulting ROW SLUGS. They
## also assert the box SURVIVES a rebuild — it lives outside `_grid`, whose children
## `_build_table()` frees, so a box parented into the grid would be destroyed by one.
##
## Filtering HIDES rows rather than rebuilding the table (the table is ~1,932 Control
## nodes and ~505 ms on the live 321-slug registry, so a keystroke must not reach it).
## Two things follow for the arms here. `_row_slugs` reads `visible`, which also makes
## it the guard for the column-alignment gotcha: GridContainer lays out only its visible
## children, so a row hidden in fewer than all six cells breaks the stride and the arms
## read garbage slugs. And the split is graded by the view's two COUNTERS — a wall-clock
## budget would be the flakiest assert in the suite, and 2 slugs would not show it.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TunablesRegistryViewTest.tscn

const View = preload("res://src/debug/TunablesRegistryView.gd")
const COLUMNS := View.COLUMNS
const PIN_PATH := "user://registry_view_test_pin.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	Tune.bind("render.scale", 8.0, {"min": 1.0, "max": 20.0, "step": 0.1})
	Tune.bind("debug.map", false)

	var view := View.new()
	add_child(view)
	view.rebuild()

	var grid := _find_grid(view)
	_assert_true(grid != null, "the view contains a GridContainer")
	if grid:
		# 6 columns: a header row + one row per slug (2) = 18 children.
		_assert_eq("grid = header + one row per slug", grid.get_child_count(), 18)
		# Slugs sort debug.map (row 0) then render.scale (row 1). Value cell is column 1.
		var scale_value := grid.get_child(6 + 6 + 1)  # header(6) + row0(6) + col1
		_assert_true(scale_value is SpinBox, "render.scale value cell is a bound SpinBox")
		if scale_value is SpinBox:
			scale_value.value = 5.0
			_assert_eq("editing the registry control writes the slug",
				float(Tune.bind("render.scale", 0.0)), 5.0)
		var map_value := grid.get_child(6 + 1)  # header(6) + row0 col1
		_assert_true(map_value is CheckBox, "debug.map value cell is a bound CheckBox")
	Tune.clear("render.scale")

	# --- the find box -------------------------------------------------------
	var edit := _find_filter_edit(view)
	_assert_true(edit != null, "the view has a find LineEdit outside the grid")
	if edit and grid:
		# It must not be a child of _grid: rebuild() frees every grid child, so a box
		# in there dies on the keystroke that filtered. Prove it by REFILTERING.
		_drive(edit, "render")
		_assert_true(is_instance_valid(edit) and not edit.is_queued_for_deletion(),
			"the find box survives the rebuild its own edit triggers")
		_assert_eq("a query narrows the table to the matching slugs",
			_row_slugs(grid), ["render.scale"])

		_drive(edit, "RENDER")
		_assert_eq("the match is case-insensitive", _row_slugs(grid), ["render.scale"])

		_drive(edit, "  render  ")
		_assert_eq("surrounding whitespace is stripped, not matched",
			_row_slugs(grid), ["render.scale"])

		_drive(edit, "zzz")
		_assert_eq("a query matching nothing empties the table", _row_slugs(grid), [])

		_drive(edit, "")
		_assert_eq("clearing the query restores every row",
			_row_slugs(grid), ["debug.map", "render.scale"])

		# The count readout is the only feedback for "0 of 2" — assert it moves too.
		var count: Label = view.find_child("RegistryFilterCount", true, false)
		_assert_true(count != null, "the view has a RegistryFilterCount readout")
		if count:
			_assert_eq("the readout counts the whole registry when unfiltered",
				count.text, "2 tunables")
			_drive(edit, "debug")
			_assert_eq("the readout counts matches vs total when filtered",
				count.text, "1 of 2")

		# DebugDashboard._set_page(1) calls rebuild() on every show. The query is a
		# view field, so the box and the table must not disagree after that call.
		_drive(edit, "debug")
		view.rebuild()
		_assert_eq("an external rebuild() re-applies the current query, not 'all'",
			_row_slugs(grid), ["debug.map"])
		_assert_eq("...and the box keeps its text across that rebuild", edit.text, "debug")

		# --- what a keystroke is allowed to cost ----------------------------
		# The bug this page was fixed for: rebuild() built ~1,932 Control nodes, so
		# every keystroke cost ~505 ms and a BACKSPACE to empty cost the same in one
		# event. Filtering must now touch neither the projection nor the node tree.
		_assert_true(view.has_method("table_builds") and view.has_method("rebuild_calls"),
			"the view exposes rebuild_calls()/table_builds() counters")
		if view.has_method("table_builds") and view.has_method("rebuild_calls"):
			var builds0: int = view.table_builds()
			var calls0: int = view.rebuild_calls()
			for q in ["r", "re", "ren", "rend", "render", ""]:
				_drive(edit, q)
			_assert_eq("a burst of keystrokes builds no table",
				view.table_builds(), builds0)
			_assert_eq("...and does not re-project the registry either",
				view.rebuild_calls(), calls0)

			# DebugDashboard._set_page(1) rebuilds on every show. With the registry
			# unchanged that must re-project (how a lazy slug is noticed) and stop.
			view.rebuild()
			view.rebuild()
			_assert_eq("a show over an unchanged registry builds no table",
				view.table_builds(), builds0)
			_assert_eq("...but it DID re-project", view.rebuild_calls(), calls0 + 2)

			# Dirty is a VOLATILE cell, not part of the table's shape: scrubbing a slug
			# and pinning it must both be absorbed by the refresh pass. A rebuild here
			# would put the ~505 ms back on the page-show every knob is dialed.
			Tune.set_value("debug.map", true)
			view.rebuild()
			_assert_eq("a dirty slug does not rebuild the table",
				view.table_builds(), builds0)
			var dirty_cell := _cell(grid, "debug.map", 5)
			_assert_eq("a scrubbed slug shows its dirty marker", dirty_cell.text, " *")
			Tune.commit(PIN_PATH)
			view.rebuild()
			_assert_eq("committing clears the marker on the next rebuild",
				dirty_cell.text, "")
			_assert_eq("...without rebuilding the table to do it",
				view.table_builds(), builds0)

			# A lazily registered slug is the one thing that must still cost a rebuild.
			# The query is set FIRST and left alone across it: a freshly built row is
			# visible by default, so a rebuild that forgot to re-apply the query would
			# quietly show the whole registry — and only an arm that never re-drives
			# the box in between can see that.
			_drive(edit, "late")
			_assert_eq("nothing matches 'late' before the slug exists",
				_row_slugs(grid), [])
			Tune.bind("late.arrival", 3)
			view.rebuild()
			_assert_eq("a newly registered slug rebuilds the table",
				view.table_builds(), builds0 + 1)
			_assert_eq("...and the freshly built table is still filtered by the query",
				_row_slugs(grid), ["late.arrival"])
			_assert_true(is_instance_valid(edit) and not edit.is_queued_for_deletion(),
				"the find box survives a real table rebuild")
			_drive(edit, "")
			_assert_eq("...and clearing shows it alongside the rest", _row_slugs(grid),
				["debug.map", "late.arrival", "render.scale"])

			# The invariant hiding rows newly RESTS on: a filtered-out row is still in
			# the tree, so its TuneField binding is still live and must track a write
			# that lands while it is hidden. Freeing the row made this true for nothing;
			# hiding it makes it the thing that keeps an unhidden row honest.
			_drive(edit, "debug")  # render.scale's row is now hidden
			Tune.set_value("render.scale", 12.5)
			_drive(edit, "render")  # ...and back
			var scale_cell := _cell(grid, "render.scale", 1)
			_assert_true(scale_cell is SpinBox, "the unhidden value cell is still its SpinBox")
			if scale_cell is SpinBox:
				_assert_eq("a hidden row's binding tracked a write made while it was hidden",
					(scale_cell as SpinBox).value, 12.5)
			_assert_eq("...without rebuilding the table to notice",
				view.table_builds(), builds0 + 1)

	view.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PIN_PATH))

	print("\n=== TunablesRegistryViewTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TunablesRegistryViewTest")
		get_tree().quit(1)
	else:
		print("[PASS] TunablesRegistryViewTest")
		get_tree().quit(0)


## The find box, looked up the way the page lays it out: a direct child of the view
## or of one of its direct-child rows. Deliberately NOT recursive — every SpinBox on
## the page embeds its own LineEdit, and a recursive search finds one of those first.
func _find_filter_edit(view: Node) -> LineEdit:
	for child in view.get_children():
		if child is LineEdit:
			return child
		if child is GridContainer:
			continue
		for grandchild in child.get_children():
			if grandchild is LineEdit:
				return grandchild
	return null


## Type as a user does: setting `.text` alone does NOT emit text_changed, so an arm
## that only assigns it passes against a box wired to nothing.
func _drive(edit: LineEdit, query: String) -> void:
	edit.text = query
	edit.text_changed.emit(query)


## The slug cell (column 0) of every row the table is currently SHOWING. "Shown" is
## `visible`, because filtering hides a row's six cells instead of freeing them. The
## `is_queued_for_deletion()` filter still matters for the real rebuild path, which
## queue_free()s the previous table — deferred, so those cells are still present, and
## still visible, for the rest of the frame.
func _row_slugs(grid: GridContainer) -> Array:
	var live := _live_cells(grid, true)
	var out: Array = []
	var i := COLUMNS  # skip the header row
	while i < live.size():
		out.append((live[i] as Label).text)
		i += COLUMNS
	return out


## Cell `column` of the row whose slug cell reads `slug`. Deliberately does NOT filter on
## `visible` the way _row_slugs does — its callers ask about rows the filter has hidden,
## which is the whole point of the arms that use it. Reads the grid rather than the
## view's bookkeeping: the page is graded by what it renders.
func _cell(grid: GridContainer, slug: String, column: int) -> Control:
	var live := _live_cells(grid, false)
	var i := COLUMNS
	while i + COLUMNS - 1 < live.size():
		if (live[i] as Label).text == slug:
			return live[i + column]
		i += COLUMNS
	return null


## The table's cells in render order, minus the outgoing cells of a table that was just
## rebuilt — queue_free() is DEFERRED, so those are still children for the rest of the
## frame. `visible_only` additionally drops the rows the filter has hidden.
func _live_cells(grid: GridContainer, visible_only: bool) -> Array:
	var live: Array = []
	for c in grid.get_children():
		if c.is_queued_for_deletion():
			continue
		if visible_only and not (c as Control).visible:
			continue
		live.append(c)
	return live


func _find_grid(node: Node) -> GridContainer:
	for child in node.get_children():
		if child is GridContainer:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)


func _assert_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
