extends RefCounted

## The **highlight publish** — paint a grid cell, keyed by coordinate.
##
## ADR-0164 dec. 1 cut `Tile`'s member surface into three capabilities with three
## client sets and classified each by ADR-0118 dec. 3's test ("a port is a
## synchronous dependency, nothing proceeds without the reply; a schema is
## fire-and-forget"). The terrain query is the `Lattice` PORT. The highlight is a
## **command with no reply**, so it is a PUBLISH, and `src/strategy/` is its only
## external client — 14 lines, all of them a colour going one way.
##
## It exists as its own type because ADR-0192 dec. 4 took `class_name` off the tile
## store: after that the only way to reach a tile NODE from outside the addon was the
## port, and the port answers with values. So the placement sets became `Vector2i`
## (ADR-0164 dec. 2's "it also forces the occupancy keys off object identity",
## ADR-0166 dec. 3's one-type-for-one-concept), and painting them needed the same key.
## `Battle` names a coordinate and a colour; the addon does the lookup.
##
## ⚠️ THE KIND IS `CellMarking.Kind`, AND IT LIVES IN THE SCHEMA — not here, and no
## longer on `Tile` (ADR-0196 dec. 6, superseding ADR-0193 dec. 2 and ADR-0195 dec. 6).
## Both of those declined the move and both priced it as a re-spelling COUNT — 47 here,
## 43 twice elsewhere, 39 in the tree that finally moved it. The count was never the
## blocker. `TileHighlights` is the destination both declines ASSUMED, and it is
## structurally wrong: this file already depends on `Tile` (`_tile`, and `paint`'s own
## body), while `Tile.gd` used the enum at its own declaration — so hosting it here
## re-creates the `Tile.gd → TileHighlights.gd → Tile.gd` cycle ADR-0170 dec. 4
## diagnosed and ADR-0166 dec. 1 closed. The schema has no such edge, and it is where
## both sides can name the value: `src/strategy/` decides which cells are which marking,
## this addon decides what one looks like. Named, never a bare `int`, so the two sides
## still cannot disagree about what `2` means.
##
## ⚠️ A CELL WEARS MORE THAN ONE MARKING AT A TIME, AND THIS IS THE ARBITER
## (ADR-0221). `Tile` renders exactly one, so this holds, per cell, one marking per
## SLOT and hands the tile the topmost occupied one. The slot is DERIVED from the
## kind — `paint` still takes two arguments — because the callers are being relieved
## of arbitration, and a slot parameter would hand it straight back in a new
## spelling. Before this, the cursor and the march pick shared one slot on the node:
## the cursor saved the value it displaced when it ARRIVED and put it back when it
## left, so a selection painted in between was silently erased, and
## `CursorController._process` re-asserted `CURSOR_ACTIVE` every frame to paper over
## the same collision on the one square where it did not show.
##
## 🔴 NOT A SECOND PORT. It returns nothing a caller waits on: `kind_at` answers what
## a cell is SHOWING — the rendered tile, not this table — with an enum, never a node,
## and its principal caller is a test. No `Tile` crosses (`check_lattice_doors.py`).
##
## 🔴 AND IT IS THE ONLY WRITER (ADR-0221 dec. 3). `Tile._set_highlight_type` /
## `_clear_highlight` are underscored addon-internals with exactly one caller — this
## file — and `tools/check_highlight_writer.py` keeps it that way. A second writer
## compiles, runs, and produces a picture that is wrong only in the frames after it.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")


const TileStore := preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")

## The layers a cell's markings stack in, lowest first. `TERRAIN_SET` is what the
## square IS for the phase in progress; `SELECTION` is what the player picked and
## walked away from; `CURSOR` is where the player is looking right now. They are not
## competing answers to one question — they are answers to three, which is why one
## slot could never hold them.
##
## No member of this file takes a `Slot`. It is named because the arbitration has to
## be readable, not because a caller supplies one.
enum Slot { TERRAIN_SET = 0, SELECTION = 1, CURSOR = 2 }

const SLOT_COUNT := 3

var _store: TileStore = null

# Vector3i -> PackedInt32Array[SLOT_COUNT] of `CellMarking.Kind`. The key is the
# `TerrainCell.grid` the producer already holds (ADR-0219 dec. 1, ADR-0166 dec. 3),
# so nothing lifts anything. A cell with every slot empty is ERASED, not kept at
# `NONE` — and a cell the store has no tile for is never recorded at all, because a
# table that accumulated cells the map does not have would be a second, divergent
# store of what terrain exists, and that is `TerrainIndex`'s job.
var _slots: Dictionary = {}


func _init(store: TileStore = null) -> void:
	_store = store


## ADDON-INTERNAL. Re-point at a freshly built store — see `Lattice._bind` for why
## the object is stable across a map reload and the store is what gets replaced.
## The table is DROPPED: every marking in it was a statement about a tile that no
## longer exists.
func _bind(store: TileStore) -> void:
	_store = store
	_slots.clear()


## Paint `cell` with `kind`, in the slot `kind` belongs to. Whatever the other slots
## hold is untouched, and the tile shows the topmost occupied one. A cell with no tile
## is a silent no-op: the placement sets are built from the lattice, so an absent cell
## means the map was rebuilt underneath, which is not the caller's error to handle.
func paint(cell: Vector3i, kind: CellMarking.Kind) -> void:
	_write(cell, _slot_of(kind), kind)


## Drop `cell`'s marking in the slot `kind` belongs to, revealing whatever is beneath
## it. `kind` is which SLOT you mean, not an assertion about what is currently in it —
## clearing `PLACEMENT_PLAYER` off a cell now wearing `PLACEMENT_UNAVAILABLE` empties
## the same slot, because both are the same statement about the square.
func clear(cell: Vector3i, kind: CellMarking.Kind) -> void:
	_write(cell, _slot_of(kind), CellMarking.Kind.NONE)


## What `cell` is currently SHOWING — `NONE` when there is no tile there. Reads the
## rendered tile and not `_slots`, deliberately: a caller asking this is asking about
## the picture, and the table would answer about the top slot even where the tile is
## gone.
func kind_at(cell: Vector3i) -> CellMarking.Kind:
	var tile := _tile(cell)
	return tile.current_highlight_type if tile != null else CellMarking.Kind.NONE


# Which layer a marking lives in. Derived rather than declared on `CellMarking`
# (ADR-0221 dec. 1): the schema names WHAT a marking is so both sides can spell it
# (ADR-0196 dec. 6), while which of several simultaneous markings a tile shows is a
# rendering policy only this file has the state to decide. `NONE` lands on
# `TERRAIN_SET` and needs no special case — `paint(cell, NONE)` empties that slot,
# which is what it reads as.
func _slot_of(kind: CellMarking.Kind) -> int:
	match kind:
		CellMarking.Kind.CURSOR_ACTIVE:
			return Slot.CURSOR
		CellMarking.Kind.SELECTED:
			return Slot.SELECTION
		_:
			return Slot.TERRAIN_SET


func _write(cell: Vector3i, slot: int, kind: CellMarking.Kind) -> void:
	var tile := _tile(cell)
	if tile == null:
		return
	# `PackedInt32Array` is a value type: `get` hands back a copy, so the write-back
	# below is not redundant.
	var slots: PackedInt32Array = _slots.get(cell, PackedInt32Array())
	if slots.is_empty():
		slots.resize(SLOT_COUNT)
	slots[slot] = kind
	var top := _top(slots)
	if top == CellMarking.Kind.NONE:
		_slots.erase(cell)
		tile._clear_highlight()
	else:
		_slots[cell] = slots
		tile._set_highlight_type(top)


func _top(slots: PackedInt32Array) -> CellMarking.Kind:
	for slot in range(SLOT_COUNT - 1, -1, -1):
		if slots[slot] != CellMarking.Kind.NONE:
			return slots[slot]
	return CellMarking.Kind.NONE


# A marking belongs to a CELL, not a column (ADR-0219 dec. 1): two tiles can share
# (x, z) and only one of them is contested / a legal deployment square.
func _tile(cell: Vector3i) -> Tile:
	return _store.get_tile(cell) if _store != null else null
