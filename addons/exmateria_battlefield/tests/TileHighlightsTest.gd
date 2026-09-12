extends Node
## Tests for `TileHighlights` — the highlight publish, and the ARBITER of a cell's
## markings (ADR-0221).
##
## 🔴 THIS FILE IS ADDON-OWNED AND EVERY LEG IS SYNTHETIC (ADR-0194). It stands the
## terrain up with `TerrainFixture` (ADR-0218) and reaches nothing but this addon and
## the schema, so it runs under the stranger rig — no map, no host scene, no GPU.
##
## What it exists to pin: a cell wears more than one marking at a time and a `Tile`
## renders exactly ONE of them. Before ADR-0221 that arbitration did not exist —
## three writers shared a single slot on the node, so a march pick landing under the
## cursor was erased when the cursor walked off it, and `CursorController._process`
## re-asserted `CURSOR_ACTIVE` every frame to hide the same collision on the one
## square where it did not show. The legs below are that failure, stated forwards:
##
##   * the topmost occupied slot is what renders, and painting a LOWER slot does not
##     change the picture — the placement repaint that used to erase the cursor;
##   * emptying an upper slot REVEALS what is beneath it — the cursor walking off a
##     pick, which is the reported defect;
##   * the four `PLACEMENT_*` kinds share one slot, because they are one statement
##     about what a square IS;
##   * `clear` names a SLOT, not the value in it;
##   * a cell with no tile records NOTHING, so the table never becomes a second,
##     divergent store of what terrain exists;
##   * `_bind` drops the table — every marking in it described a tile that is gone;
##   * two cells of one COLUMN are independent (ADR-0219 dec. 1).
##
## Run: `bash tests/stranger/exmateria_battlefield/run.sh`, which globs its addon's
## `tests/*.tscn`. ADR-0194 dec. 4 forbids running it as `res://tests/X.tscn` in the
## host project.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are reached
# by path. A `preload` const is a full type: it annotates, `is`-checks and `.new()`s
# exactly as the deleted `class_name` did.
const TerrainFixture = preload("res://addons/exmateria_battlefield/lattice/TerrainFixture.gd")
const TileHighlights = preload("res://addons/exmateria_battlefield/overlay/TileHighlights.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` publishes one name; this keeps the
## use sites below spelled the way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking
const TerrainCell = ExMateriaSchema.TerrainCell

# COUNTERS, not a bare bool (ADR-0194 dec. 12 arm 2). A `[PASS]` printed off
# `not _failed` is true of a run that asserted NOTHING, and a GDScript runtime error
# aborts only its ENCLOSING function while `_ready` carries on — so the verdict pins
# the TOTAL, not just the absence of failures.
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_topmost_slot_renders()
	_test_clearing_the_top_reveals_what_is_under_it()
	_test_a_lower_slot_cannot_change_the_picture()
	_test_the_placement_kinds_share_one_slot()
	_test_clear_names_a_slot_not_a_value()
	_test_a_cell_with_no_tile_records_nothing()
	_test_bind_drops_the_table()
	_test_two_cells_of_a_column_are_independent()

	print("\n=== TileHighlightsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] TileHighlightsTest")
		get_tree().quit(1)
	else:
		print("[PASS] TileHighlightsTest")
		get_tree().quit(0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		print("[FAIL] %s" % msg)
		_failed += 1


# A 3x3 fixture, parented so its tiles have a real `global_position` — the publish
# never reads one, but `Tile._exit_tree` and the compositor do, and a fixture that
# was not in the tree would be testing a different object than production has.
func _fixture(bridge_at: Vector2i = Vector2i(-99, -99)) -> TerrainFixture:
	var fix := TerrainFixture.new()
	for gz in range(3):
		for gx in range(3):
			fix.put(Vector2i(gx, gz))
	if bridge_at.x >= 0:
		fix.put(bridge_at, 4, {}, 1)
	add_child(fix)
	return fix


func _test_the_topmost_slot_renders() -> void:
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(1, 1)

	hl.paint(cell, CellMarking.Kind.PLACEMENT_PLAYER)
	_check(hl.kind_at(cell) == CellMarking.Kind.PLACEMENT_PLAYER,
		"one marking renders itself, got %d" % hl.kind_at(cell))

	# SELECTION sits above TERRAIN_SET, CURSOR above both.
	hl.paint(cell, CellMarking.Kind.SELECTED)
	_check(hl.kind_at(cell) == CellMarking.Kind.SELECTED,
		"SELECTED outranks a placement marking, got %d" % hl.kind_at(cell))
	hl.paint(cell, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl.kind_at(cell) == CellMarking.Kind.CURSOR_ACTIVE,
		"CURSOR_ACTIVE outranks a selection, got %d" % hl.kind_at(cell))
	fix.queue_free()


func _test_clearing_the_top_reveals_what_is_under_it() -> void:
	# THE REPORTED DEFECT, stated forwards. The cursor arrives on a tile that is
	# already a deployment square, the player picks the unit standing there, and the
	# cursor moves on. Every one of those three markings is still true of the cell;
	# only the top one stopped being.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(2, 0)

	hl.paint(cell, CellMarking.Kind.PLACEMENT_PLAYER)
	hl.paint(cell, CellMarking.Kind.CURSOR_ACTIVE)
	hl.paint(cell, CellMarking.Kind.SELECTED)
	hl.clear(cell, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl.kind_at(cell) == CellMarking.Kind.SELECTED,
		"the cursor leaving reveals the SELECTION beneath it, got %d" % hl.kind_at(cell))

	hl.clear(cell, CellMarking.Kind.SELECTED)
	_check(hl.kind_at(cell) == CellMarking.Kind.PLACEMENT_PLAYER,
		"and the selection leaving reveals the placement colour, got %d" % hl.kind_at(cell))

	hl.clear(cell, CellMarking.Kind.PLACEMENT_PLAYER)
	_check(hl.kind_at(cell) == CellMarking.Kind.NONE,
		"an empty cell shows nothing, got %d" % hl.kind_at(cell))
	fix.queue_free()


func _test_a_lower_slot_cannot_change_the_picture() -> void:
	# THE OTHER HALF of the same defect. `highlight_available_for_team` repaints every
	# placement cell on each claim, and one of them is under the cursor. That repaint
	# used to overwrite CURSOR_ACTIVE, which is the whole reason `_process` existed.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(0, 2)

	hl.paint(cell, CellMarking.Kind.CURSOR_ACTIVE)
	hl.paint(cell, CellMarking.Kind.PLACEMENT_ENEMY)
	_check(hl.kind_at(cell) == CellMarking.Kind.CURSOR_ACTIVE,
		"a placement repaint under the cursor does not move the picture, got %d"
			% hl.kind_at(cell))

	# ...and it was recorded, not discarded: it is there when the cursor goes.
	hl.clear(cell, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl.kind_at(cell) == CellMarking.Kind.PLACEMENT_ENEMY,
		"the repaint LANDED in its own slot while the cursor covered it, got %d"
			% hl.kind_at(cell))
	fix.queue_free()


func _test_the_placement_kinds_share_one_slot() -> void:
	# All three are one statement about what the square IS, so they replace each other
	# exactly as they did when there was one slot for everything. There were four until
	# ADR-0258 retired PLACEMENT_CONTESTED.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(1, 0)

	for kind in [CellMarking.Kind.PLACEMENT_PLAYER, CellMarking.Kind.PLACEMENT_ENEMY,
			CellMarking.Kind.PLACEMENT_UNAVAILABLE]:
		hl.paint(cell, kind)
		_check(hl.kind_at(cell) == kind,
			"placement kind %d replaces the previous one, got %d" % [kind, hl.kind_at(cell)])

	hl.clear(cell, CellMarking.Kind.PLACEMENT_PLAYER)
	_check(hl.kind_at(cell) == CellMarking.Kind.NONE,
		"and one clear empties the slot all four share, got %d" % hl.kind_at(cell))
	fix.queue_free()


func _test_clear_names_a_slot_not_a_value() -> void:
	# The retired `PlacementTileHighlighter._clear_all_highlights` walked `player_cells` and cleared
	# with PLACEMENT_PLAYER — on cells that may currently show PLACEMENT_UNAVAILABLE,
	# because a claim repainted them. The argument names which SLOT, not what is in it.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(0, 1)

	hl.paint(cell, CellMarking.Kind.PLACEMENT_UNAVAILABLE)
	hl.clear(cell, CellMarking.Kind.PLACEMENT_PLAYER)
	_check(hl.kind_at(cell) == CellMarking.Kind.NONE,
		"clearing with a sibling kind empties the same slot, got %d" % hl.kind_at(cell))
	fix.queue_free()


func _test_a_cell_with_no_tile_records_nothing() -> void:
	# A table that accumulated cells the map does not have would be a second,
	# divergent store of what terrain exists, and that is `TerrainIndex`'s job.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var nowhere := TerrainCell.ground(9, 9)

	hl.paint(nowhere, CellMarking.Kind.SELECTED)
	_check(hl.kind_at(nowhere) == CellMarking.Kind.NONE,
		"painting a cell with no tile shows nothing, got %d" % hl.kind_at(nowhere))
	_check(not hl._slots.has(nowhere),
		"...and records nothing: the table has %d entr(ies)" % hl._slots.size())
	fix.queue_free()


func _test_bind_drops_the_table() -> void:
	# `_bind` is the map being rebuilt underneath. Every marking held here was a
	# statement about a tile that no longer exists.
	var fix := _fixture()
	var hl: TileHighlights = fix.highlights
	var cell := TerrainCell.ground(1, 2)

	hl.paint(cell, CellMarking.Kind.PLACEMENT_ENEMY)
	hl.paint(cell, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl._slots.size() == 1, "one painted cell, one entry, got %d" % hl._slots.size())

	# A `put` after the first read of `lattice` rebuilds NOW (`TerrainFixture._restate`),
	# which is the production `_bind` path and not a test-only poke.
	fix.put(Vector2i(1, 2), 3)
	_check(hl._slots.is_empty(),
		"a rebuild drops the table, %d entr(ies) survived" % hl._slots.size())
	_check(hl.kind_at(cell) == CellMarking.Kind.NONE,
		"...and the fresh tile wears nothing, got %d" % hl.kind_at(cell))
	fix.queue_free()


func _test_two_cells_of_a_column_are_independent() -> void:
	# A marking belongs to a CELL, not a column (ADR-0219 dec. 1): the moat and the
	# bridge over it are two squares, and only one of them is a legal deployment tile.
	var fix := _fixture(Vector2i(2, 2))
	var hl: TileHighlights = fix.highlights
	var ground := TerrainCell.ground(2, 2)
	var bridge := Vector3i(2, 2, 1)

	hl.paint(ground, CellMarking.Kind.PLACEMENT_PLAYER)
	hl.paint(bridge, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl.kind_at(ground) == CellMarking.Kind.PLACEMENT_PLAYER,
		"the ground keeps its own marking, got %d" % hl.kind_at(ground))
	_check(hl.kind_at(bridge) == CellMarking.Kind.CURSOR_ACTIVE,
		"the bridge above it keeps its own, got %d" % hl.kind_at(bridge))

	hl.clear(bridge, CellMarking.Kind.CURSOR_ACTIVE)
	_check(hl.kind_at(ground) == CellMarking.Kind.PLACEMENT_PLAYER,
		"clearing the bridge leaves the ground alone, got %d" % hl.kind_at(ground))
	fix.queue_free()
