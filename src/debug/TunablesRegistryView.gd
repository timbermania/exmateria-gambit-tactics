class_name TunablesRegistryView
extends VBoxContainer
## The debug dashboard's REGISTRY page (ADR-0068): a flat, full-width table of EVERY
## registered Tune slug with the metadata the masonry cards don't show — default,
## range/step, type, dirty — plus an inline editable control per row. The control is
## built by TuneField.build_control, so it BINDS to the same slug as that knob's card
## on the panels page: edit it here and the card follows, and vice-versa (the
## "repeat controllers" sync). Rebuild on show to pick up lazily-registered slugs.
##
## FILTERING IS A VIEW CONCERN, not the model's (ADR-0068 R1 / decision 12): the
## projection stays pure and shared, and only this view decides which of its rows to
## draw. rebuild() re-applies the current query, so it survives the rebuild that
## DebugDashboard._set_page(1) fires on every show — otherwise the box would still
## read "render" over a table that had quietly gone back to showing everything.
##
## FILTERING HIDES ROWS; IT DOES NOT REBUILD THE TABLE. Measured on the live 321-slug
## registry: constructing the table is ~505 ms (1,932 Control nodes — 194 ms of bound
## controls, 213 ms of plain metadata Labels), while toggling `visible` on the six
## cells of every row is ~1 ms. Rebuilding per keystroke therefore cost half a second
## a character, and the worst case was not a keypress but a BACKSPACE: clearing a
## one-character query is a single event that re-materialised all 321 rows. So the
## table is built once and `_apply_query` only changes visibility. All SIX cells of a
## row are toggled together — GridContainer lays out its visible children only, so
## hiding a single cell would shift every row below it into the wrong column.
##
## rebuild() stays the correctness fallback: it re-projects the registry and rebuilds
## the table whenever the structure actually changed (a lazily-registered slug, a
## changed range/type/default), and otherwise just refreshes the volatile cells. The
## two counters below exist purely as guard surfaces for that split.

const Model = preload("res://src/debug/TunablesRegistryModel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const _DIM := Color(0.6, 0.6, 0.65)
## The table's width, and therefore the size of a row's cell group.
const COLUMNS := 6

var _grid: GridContainer
var _count_label: Label
## The live find query, already stripped and lower-cased for matching. "" = show all.
var _query: String = ""

## The built table, one entry per row: { slug, cells, refresh }. `cells` is the row's
## COLUMNS cells, which the filter shows or hides together; `refresh` re-reads the cells
## whose contents change without the table changing shape (the dirty marker, and the
## read-only value of a type with no widget).
var _rows: Array[Dictionary] = []
## The structural fingerprint the current table was built from; a full rebuild happens
## only when this moves.
var _built_signature: String = ""
var _rebuild_calls: int = 0
var _table_builds: int = 0


func _init() -> void:
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Tunables Registry"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var hint := Label.new()
	hint.text = "Every registered tunable. Edits sync with the same knob on the Panels page. Right-click a control: Pin / Reset."
	hint.add_theme_color_override("font_color", _DIM)
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(buttons)

	# The find box rides the button row and NOT `_grid`: rebuild() frees every grid
	# child, so a box parented in there would be destroyed by the very keystroke that
	# filtered — losing focus and eating characters. It also leads the row rather than
	# trailing it, so the dump status label growing does not shove it sideways.
	var find_label := Label.new()
	find_label.text = "Find:"
	find_label.add_theme_color_override("font_color", _DIM)
	buttons.add_child(find_label)

	# tune-exempt: a transient view query over this table, not a value anyone persists.
	var find_edit := LineEdit.new()
	find_edit.placeholder_text = "slug substring"
	find_edit.custom_minimum_size.x = 180
	find_edit.clear_button_enabled = true
	# A keystroke re-filters and NOTHING else: no projection, no node construction.
	# rebuild() here is what made typing cost ~505 ms a character.
	find_edit.text_changed.connect(func(text: String) -> void:
		_query = text.strip_edges().to_lower()
		_apply_query())
	buttons.add_child(find_edit)

	# HBoxContainer separation is uniform, so the gap the readout needs is bought
	# with spacers rather than by pushing the buttons apart too.
	buttons.add_child(_gap(8))

	_count_label = Label.new()
	_count_label.name = "RegistryFilterCount"  # TunablesRegistryViewTest looks it up by this name
	_count_label.custom_minimum_size.x = 74  # a stable gutter before "Pin all dirty"
	_count_label.add_theme_color_override("font_color", _DIM)
	_count_label.add_theme_font_size_override("font_size", 11)
	buttons.add_child(_count_label)

	buttons.add_child(_gap(8))

	var pin_all := Button.new()
	pin_all.text = "Pin all dirty"
	pin_all.pressed.connect(func() -> void:
		Tune.commit()
		rebuild())
	buttons.add_child(pin_all)

	# The materialize bridge (ADR-0068 M4): dump the registry (with
	# captured use-site locations) to the gitignored snapshot the codemod reads.
	# Then, from the package dir: uv run python tools/materialize_tunables.py
	var dump := Button.new()
	dump.text = "Dump tune registry"
	buttons.add_child(dump)

	var dump_status := Label.new()
	dump_status.add_theme_color_override("font_color", _DIM)
	dump_status.add_theme_font_size_override("font_size", 11)
	buttons.add_child(dump_status)

	dump.pressed.connect(func() -> void:
		if Tune.dump_registry():
			dump_status.text = "  wrote %s → run tools/materialize_tunables.py" % \
				Tune.REGISTRY_SNAPSHOT_PATH.get_file()
		else:
			dump_status.text = "  dump FAILED (see log)")

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)


## Re-project the registry and bring the table up to date — the only way lazily
## registered slugs enter the view, so callers rebuild on show. The table's ~1,932
## nodes are reconstructed only when the registry's STRUCTURE moved; otherwise this
## refreshes the volatile cells in place. Either way the current query is re-applied,
## so a rebuild never silently widens the table back to everything.
func rebuild() -> void:
	_rebuild_calls += 1
	var rows: Array = Model.rows(Tune)
	var signature := _signature_of(rows)
	if signature != _built_signature:
		_build_table(rows)
		_built_signature = signature
	else:
		for row: Dictionary in _rows:
			(row["refresh"] as Callable).call()
	_apply_query()


## How many times rebuild() has been CALLED (i.e. the registry re-projected), and how
## many of those actually constructed the table. Two names, because the interesting
## number here is the one that mostly stays put — UI3RegistryView's `rebuild_count()`
## counts rebuilds that happened, and `rebuild_calls()` deliberately does not borrow
## that name for the opposite meaning. Public purely as a GUARD SURFACE: a keystroke
## must move neither, and a page show must move only the first. Graded by a counter
## rather than a wall clock on purpose — a millisecond budget is the most
## contention-sensitive assert this suite can carry, and a wall clock is not what went
## wrong here anyway.
func rebuild_calls() -> int:
	return _rebuild_calls


func table_builds() -> int:
	return _table_builds


## Construct every row's nodes from scratch. ~505 ms on the live registry, so this runs
## on a registry change, not on a keystroke.
func _build_table(rows: Array) -> void:
	for c in _grid.get_children():
		# Hidden as well as freed: queue_free is DEFERRED, so without this the outgoing
		# cells would render for one more frame — and they are all visible, while the
		# incoming ones are about to be filtered. The free stays deferred on purpose;
		# a synchronous free() during a rebuild is the re-entrancy hazard Tune.on_update
		# documents.
		(c as Control).visible = false
		c.queue_free()
	_rows = []
	_add_header()
	for row: Dictionary in rows:
		_add_row(row)
	_table_builds += 1


## Show the rows matching the query and hide the rest — the whole cost of a keystroke.
func _apply_query() -> void:
	var shown: int = 0
	for row: Dictionary in _rows:
		var want := _matches(row["slug"])
		# All COLUMNS of them, together: GridContainer only lays out its VISIBLE
		# children, so a partially hidden row would pull the rows under it out of
		# column alignment.
		for cell: Control in row["cells"]:
			cell.visible = want
		if want:
			shown += 1
	# The denominator is the BUILT table, not a fresh projection. Those agreed when every
	# filter rebuilt; now they can differ for the window between a slug registering and
	# the next show. The built size is the honest one — quoting a live count over a table
	# that does not hold those rows yet would claim rows the page is not rendering.
	if _count_label:
		_count_label.text = "%d tunables" % shown if _query.is_empty() \
			else "%d of %d" % [shown, _rows.size()]


## What the table's SHAPE depends on: the slug set, and per slug everything a cell is
## built out of. The `hint` goes in WHOLE rather than via its `range` rendering — the
## range label of an enum is its KEYS, so an enum whose keys held still while its values
## moved would otherwise keep a control bound to the old ones. Deliberately excludes
## `value` and `dirty`: those change constantly and are already kept current by the
## control's live Tune binding and by the row's refresh closure, neither of which needs
## a node rebuilt.
func _signature_of(rows: Array) -> String:
	var parts := PackedStringArray()
	for row: Dictionary in rows:
		parts.append("%s\t%s\t%s\t%s" % [row["slug"], row["type"], str(row["default"]), str(row["hint"])])
	return "\n".join(parts)


## Case-insensitive substring over the slug — which carries its own namespace, so a
## query of "render." narrows to that namespace for free. The metadata columns are
## deliberately NOT searched: "float" would otherwise match most of the registry.
func _matches(slug: String) -> bool:
	if _query.is_empty():
		return true
	return slug.to_lower().contains(_query)


func _add_header() -> void:
	for h in ["Slug", "Value", "Default", "Range", "Type", ""]:
		var lbl := Label.new()
		lbl.text = h
		lbl.add_theme_color_override("font_color", _DIM)
		lbl.add_theme_font_size_override("font_size", 11)
		_grid.add_child(lbl)


func _add_row(r: Dictionary) -> void:
	var slug := Label.new()
	slug.text = r["slug"]
	slug.add_theme_color_override("font_color", TuneField.TUNABLE_ACCENT)
	_grid.add_child(slug)

	# The dirty marker for THIS row (last column). build_control's on_change refreshes
	# it after an edit or a Pin/Reset without a full rebuild.
	var dirty := _dim_label(" *" if r["dirty"] else "")
	var refresh := func() -> void:
		dirty.text = " *" if Tune.is_dirty(r["slug"]) else ""

	var control: Control = TuneField.build_control(r["slug"], r["default"], r["hint"], refresh)
	if control == null:
		# Unsupported type: a read-only value, with no binding to keep it current — so
		# the row's refresh closure has to re-read it as well as the dirty marker.
		var value_label := _dim_label(str(r["value"]))
		var slug_name: String = r["slug"]
		var plain_refresh := refresh
		refresh = func() -> void:
			# `peek`: the Registry page repaints EVERY slug on rebuild, so reading through
			# `get_value` here would stamp the whole registry as pull-consumed the first time
			# anyone opens the page (Tune.consumer_state).
			value_label.text = str(Tune.peek(slug_name))
			plain_refresh.call()
		control = value_label
	else:
		control.custom_minimum_size.x = 130
	_grid.add_child(control)

	var default_cell := _dim_label(str(r["default"]))
	var range_cell := _dim_label(str(r["range"]))
	var type_cell := _dim_label(str(r["type"]))
	_grid.add_child(default_cell)
	_grid.add_child(range_cell)
	_grid.add_child(type_cell)
	_grid.add_child(dirty)

	# _apply_query shows or hides `cells` as a unit, and rebuild() calls `refresh` when
	# the table is kept but its volatile cells may have moved.
	_rows.append({
		"slug": r["slug"],
		"cells": [slug, control, default_cell, range_cell, type_cell, dirty],
		"refresh": refresh,
	})


func _gap(width: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.x = width
	return spacer


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", _DIM)
	return lbl
