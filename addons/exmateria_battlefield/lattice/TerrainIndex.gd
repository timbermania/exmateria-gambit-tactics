extends RefCounted

## The tile STORE — a spatial index of `Tile` nodes with O(1) lookup by grid
## coordinates, and the thing `Lattice` reads to answer the port.
##
## 🔴 THIS FILE HAS NO `class_name`, AND THAT IS THE DECISION (ADR-0192 dec. 4).
## ADR-0164 dec. 4 criterion 1 scans `class_name`s, so a type without one cannot be
## in the published set — and a door on a class nobody can name is not a door. Both
## of its query methods return `Tile`, a `StaticBody3D` this addon owns; publishing
## the store means publishing the node, which is what ADR-0164 dec. 2 refused.
##
## The runner-up was renaming this class to `Lattice` in place and underscore-
## prefixing `add_tile` / `remove_tile` / `clear`. It is cheaper and it was rejected:
## "published" would then be a NAMING CONVENTION, which is exactly what criterion 1
## exists to replace, and `add_tile(tile: Tile)` would stay on the published class
## with four `tests/` files naming it (`check_lattice_doors.py` arm 3).
##
## Three files `preload` it, all inside this addon: `Lattice.gd` (which wraps it),
## `MapComposer.gd` (which builds it) and `DynamicTerrainBuilder.gd` (which fills
## it). Anything outside the addon asks `Lattice` instead.
##
## Tracks which doodad each tile belongs to for future dynamic modifications.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")

## ADR-0211 dec. 4 — the addon's façade is its whole symbol surface; one alias line
## per file keeps the use sites spelled the way they were.
const TerrainCell = ExMateriaSchema.TerrainCell


# Cell key `Vector3i(x, z, level)` -> Tile.
#
# ADR-0219 dec. 4 deleted the `_make_key(x, z) -> String` this used to hold, and
# did NOT widen it to take a level: a `String` key is a second spelling of an
# identity ADR-0166 dec. 3 already ruled must be ONE type, and the `Vector2i`
# version of it could only hold one tile per column — iterating `level_1` against
# it would have OVERWRITTEN the level-0 tile, trading a hole in the bridge for a
# hole in the moat.
var _tiles: Dictionary = {}

# Cell key -> true, bucketed by column `Vector2i(x, z)`, so `column` is O(levels)
# rather than a scan of the whole map. Kept in step with `_tiles` by `add_tile` /
# `remove_tile` / `clear` and by nothing else.
var _columns: Dictionary = {}


## Add a tile to the index, under its own `cell_key`.
##
## Args:
##     tile: The Tile node to add
##     doodad_id: ID of doodad this tile belongs to (empty string for static maps)
func add_tile(tile: Tile, _doodad_id: String = "") -> void:
	var key := tile.cell_key
	_tiles[key] = tile
	var col := Vector2i(key.x, key.y)
	if not _columns.has(col):
		_columns[col] = {}
	_columns[col][key] = true


## Get the tile at a cell.
##
## Args:
##     cell: `Vector3i(x, z, level)` — the whole identity, level included
##
## Returns:
##     Tile at that cell, or null if not found
func get_tile(cell: Vector3i) -> Tile:
	return _tiles.get(cell, null)


## Every tile in the column at (x, z), lowest level first.
##
## Up to `TerrainCell.LEVEL_COUNT` of them, and usually one. This is the query a
## caller has when it addresses a COLUMN rather than a cell — a cursor ray, a
## camera, an event pathfinder deciding what is adjacent (ADR-0219: the level axis
## is not a step direction; adjacency is column-to-column).
func column(x: int, z: int) -> Array[Tile]:
	var out: Array[Tile] = []
	var levels: Array = _columns.get(Vector2i(x, z), {}).keys()
	# Lowest level first, and sorted rather than counted up to `LEVEL_COUNT`: the
	# ROM's bound is a fact about shipped DATA, not a limit this store imposes, and
	# a fixture stating a level outside it must not silently vanish here.
	levels.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z < b.z)
	for key: Vector3i in levels:
		out.append(_tiles[key])
	return out


## Get all tiles in the index.
##
## Returns:
##     Array of all Tile nodes
func get_all_tiles() -> Array[Tile]:
	var result: Array[Tile] = []
	for tile in _tiles.values():
		result.append(tile)
	return result


## Remove a tile from the index.
##
## Args:
##     cell: `Vector3i(x, z, level)` — the whole identity, level included
##
## Returns:
##     true if tile was removed, false if not found
func remove_tile(cell: Vector3i) -> bool:
	if not _tiles.has(cell):
		return false
	_tiles.erase(cell)
	var col := Vector2i(cell.x, cell.y)
	var bucket: Dictionary = _columns.get(col, {})
	bucket.erase(cell)
	if bucket.is_empty():
		_columns.erase(col)
	return true


## Clear all tiles from the index.
func clear() -> void:
	_tiles.clear()
	_columns.clear()
