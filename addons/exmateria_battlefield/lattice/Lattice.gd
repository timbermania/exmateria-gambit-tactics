extends RefCounted

## The **lattice port** — `Battlefield`'s synchronous terrain query, and the only
## way anything outside this addon asks what the ground is doing.
##
## ADR-0118 dec. 2 names `lattice` as one of the three ports; ADR-0164 dec. 1
## separates it from the highlight *publish* and from occupancy, and dec. 2 fixes
## the rule that makes it a port at all: **it answers with VALUES.** A `Tile` is a
## `StaticBody3D` living inside this addon and it never crosses the boundary
## (ADR-0164 dec. 4 criterion 3, guarded by `tools/check_lattice_doors.py`).
##
## SIX MEMBERS, and the count is a decision (ADR-0170 dec. 2, ADR-0192 dec. 5,
## amended by ADR-0219 dec. 4 — see "a cell or a column" below):
##
##   terrain_at(cell)      -> TerrainCell   the facts at one CELL, or null
##   ground_at(x, z)       -> TerrainCell   the lowest cell of a COLUMN, or null
##   column_at(x, z)       -> Array[TerrainCell]   every cell of a column, low to high
##   world_position_at(cell) -> Vector3     the grid→world projection, scalar
##   is_cliff_edge(a, b)   -> bool          can a unit walk this edge, or must it jump
##   all_cells()           -> Array[TerrainCell]   the one-shot snapshot consumers index
##
## 🔴 A CELL OR A COLUMN — SAY WHICH (ADR-0219). A column at (x, z) holds up to
## `TerrainCell.LEVEL_COUNT` cells: MAP009 `(4, 11)` is a moat AND the bridge over
## it. Before ADR-0219 the store could physically hold only one, so `terrain_at(x,
## z)` did not have to choose; now it does, and the port makes the choice a caller
## states rather than one it inherits:
##
##   * `terrain_at(cell)` is for a caller that HOLDS a cell key — a unit's
##     `current_cell`, a pathfinder's frontier, a distance-field neighbour. It is
##     exact, and it is the only query that can address the bridge.
##   * `ground_at(x, z)` is for a caller that genuinely addresses a COLUMN and means
##     the ground of it — a camera, a weather emitter, a placement source. It
##     answers the LOWEST level present, which is what every one of those callers
##     silently got before and still wants.
##   * `column_at(x, z)` is for a caller that must consider both — a cursor deciding
##     what the player just clicked.
##
## The three exist rather than one `terrain_at(x, z, level = 0)` because a defaulted
## level is the assumption this ADR exists to make visible: every call site would
## keep compiling and none would have stated anything.
##
## `world_position_at` is a member rather than a `TerrainCell` field because it is the
## one fact that can go stale without terrain changing — it derives from a live node
## transform. ADR-0192 dec. 6 took it off the payload for that reason; a scalar query
## is allocation-free on the per-frame path and staleness-free everywhere.
##
## `is_cliff_edge` is here because `TileTraversalUtils.do_edge_vertices_match` computes
## a TERRAIN fact out of `tile_vertices` + the tile transform, and it lived in
## `src/gpu/`, i.e. in `Battle` (ADR-0164 dec. 2). The vertex math below is that
## function moved, not reimplemented — same epsilon, same ">= 2 shared vertices",
## same translation-only projection.
##
## 🔴 WHY THE STORE HAS NO `class_name` AND THIS DOES. ADR-0192 dec. 4: criterion 1
## scans `class_name`s, so a type without one cannot be in the published set, and a
## door on a class nobody can name is not a door. `TerrainIndex.gd` is `preload`ed by
## the three addon files that need it and is structurally unnameable from outside.
## The runner-up — rename the store to `Lattice` in place and underscore-prefix its
## `Tile`-taking mutators — was rejected because "published" would then be a NAMING
## CONVENTION, which is precisely what criterion 1 exists to replace.
##
## ⚠️ GDScript has no interfaces. "Provably a `Lattice`" is a claim about a
## receiver's DECLARED type and never about subclassing: `extends Lattice` and a real
## `Lattice` seeded with fabricated `TerrainCell`s both satisfy it, and
## `tools/check_lattice_ports.py` arm 1 is written to admit both (ADR-0170 dec. 5).

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")


const TileStore := preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")

## Tolerance for vertex position matching — moved verbatim from
## `TileTraversalUtils.VERTEX_MATCH_EPSILON`, which this port replaced.
const VERTEX_MATCH_EPSILON: float = 0.01

var _store: TileStore = null


func _init(store: TileStore = null) -> void:
	_store = store


## ADDON-INTERNAL. Re-point this port at a freshly built store.
##
## 🔴 THE PORT OBJECT IS STABLE ACROSS A MAP RELOAD, AND THAT IS DELIBERATE. Every
## `change_map` / `rebuild_map` builds a new store, and a consumer that took its
## handle at boot — `CombatHost`, `ScenarioWeather`, `CinematicFacingResolver` — would
## otherwise be left holding a port onto the PREVIOUS map, answering for terrain that
## no longer exists. That is the held-node bug one level up, and it would be worse
## than the one the port removes, because a stale `Lattice` still answers.
##
## `MapComposer` therefore creates ONE `Lattice` for its lifetime and rebinds it here.
## The store is the thing that is replaced; the port is the thing that is held.
func _bind(store: TileStore) -> void:
	_store = store


## The terrain facts at (x, z), or `null` if no tile is indexed there.
##
## A FRESH cell every call, deliberately: `TerrainCell` is `RefCounted` and compares
## by reference, so a cached one would make two `terrain_at` calls for the same cell
## `==` while two for different cells are `!=` — an identity semantics nobody asked
## for. Identity is `cell.grid`, a `Vector3i` (ADR-0166 dec. 3, ADR-0219 dec. 1).
func terrain_at(cell: Vector3i) -> TerrainCell:
	if _store == null:
		return null
	return _cell_of(_store.get_tile(cell))


## The GROUND of the column at (x, z) — its lowest present level — or `null`.
##
## The query for a caller that addresses a column rather than a cell. It is NOT a
## `terrain_at(x, z, 0)` shorthand: a column whose only tile is level 1 answers with
## that tile, because "the lowest thing here" is a question with an answer even when
## level 0 is absent, and "level 0" is a question that would answer `null` and be
## wrong. Eight of the corpus's 202 selectable level-1 tiles sit over an unselectable
## level 0, so this distinction is measured, not hypothetical.
func ground_at(x: int, z: int) -> TerrainCell:
	if _store == null:
		return null
	var tiles := _store.column(x, z)
	return _cell_of(tiles[0]) if not tiles.is_empty() else null


## Every cell of the column at (x, z), lowest level first. Empty if the column is.
##
## For the callers that must consider both levels — a cursor ray resolving what the
## player clicked, a pathfinder asking what an adjacent column offers. Fresh cells,
## for `terrain_at`'s reason.
func column_at(x: int, z: int) -> Array[TerrainCell]:
	var out: Array[TerrainCell] = []
	if _store == null:
		return out
	for tile in _store.column(x, z):
		var c := _cell_of(tile)
		if c != null:
			out.append(c)
	return out


## World-space position of `cell`, or `Vector3.ZERO` if there is no tile.
##
## ⚠️ `Vector3.ZERO` is "no tile" AND a legal position for the tile at the origin.
## Callers that must tell them apart test `terrain_at(x, z) != null` first; every
## caller that does is on the per-step path, not the per-frame one. Returning a
## scalar rather than a nullable object is what keeps the hot path allocation-free,
## which is the whole reason this is a member and not a `TerrainCell` field
## (ADR-0192 dec. 6).
func world_position_at(cell: Vector3i) -> Vector3:
	if _store == null:
		return Vector3.ZERO
	var tile := _store.get_tile(cell)
	return tile.global_position if tile else Vector3.ZERO


## Is the edge between two adjacent cells a CLIFF — i.e. must a unit jump it rather
## than walk it?
##
## True when the two tiles do NOT share at least two vertices on their common edge.
## Note the polarity is inverted from the `do_edge_vertices_match` this replaced:
## that answered "is it a ramp", this answers "is it a cliff", because every one of
## its callers negated it.
##
## Returns `false` when either cell is absent — an edge to nothing is not an edge,
## and both former callers guarded for a null tile and took the non-cliff branch.
## 🔴 THE EDGE MAY CROSS LEVELS AND THE RULE DOES NOT CARE (ADR-0219). `a` and `b`
## are cell keys, so this can be asked of the bridge and the ground beside it. No new
## policy was needed to answer it: the verdict is already computed from WORLD-SPACE
## vertices, so a bridge deck 6 height-units above its neighbour shares no edge
## vertices with it and reports a cliff, exactly as a step of the same size within one
## level does. The level index never enters the arithmetic — it only picks which two
## tiles are being compared.
func is_cliff_edge(a: Vector3i, b: Vector3i) -> bool:
	if _store == null:
		return false
	var ta := _store.get_tile(a)
	var tb := _store.get_tile(b)
	if ta == null or tb == null:
		return false
	return not _edge_vertices_match(ta, tb)


## Every indexed cell, as a one-shot snapshot.
##
## The three `src/` consumers (`DistanceFieldGenerator`, `GPUBatchSimulator.build_map_data`,
## `PlacementPolicy`) each take this ONCE at init and flatten it into their own
## array, so the per-call allocation is init cost, not frame cost (ADR-0164 dec. 2's ⚠️).
func all_cells() -> Array[TerrainCell]:
	var out: Array[TerrainCell] = []
	if _store == null:
		return out
	for tile in _store.get_all_tiles():
		var cell := _cell_of(tile)
		if cell != null:
			out.append(cell)
	return out


#region addon-internal
# 🔴 UNDERSCORED, AND THAT IS LOAD-BEARING. `check_lattice_doors.py` scores PUBLIC
# members only — "a leading `_` is not reachable from outside by convention" — so a
# published `func tiles() -> Array[Tile]` here would put this class straight onto the
# Tile-door register it exists to empty. These two exist for the addon files that
# genuinely need the NODE, and ADR-0192 dec. 5 is explicit that the encapsulation
# unit here is the ADDON, not the class: `MapGridOverlay` bakes `tile_vertices` +
# `global_transform` into a world-space grid mesh, and neither is a `TerrainCell`
# field nor derivable from one. A host file that reaches either is the defect
# `check_lattice_ports.py` arm 1 catches.

## ADDON-INTERNAL. The raw tile at `cell`, or null.
func _tile_at(cell: Vector3i) -> Tile:
	return _store.get_tile(cell) if _store else null


## ADDON-INTERNAL. Every raw tile. `MapGridOverlay.build_from_lattice` is the caller
## ADR-0192 dec. 5 wrote this for.
func _tiles() -> Array[Tile]:
	var empty: Array[Tile] = []
	return _store.get_all_tiles() if _store else empty

#endregion


func _cell_of(tile: Tile) -> TerrainCell:
	if tile == null:
		return null
	var cell := TerrainCell.new()
	cell.grid = tile.cell_key
	cell.height = tile.height
	cell.impassable = tile.impassable
	cell.unselectable = tile.unselectable
	cell.pass_through_only = tile.pass_through_only
	cell.surface_type = tile.surface_type
	return cell


# `TileTraversalUtils.do_edge_vertices_match` + `_get_world_space_vertices`, moved.
# Adjacent tiles share exactly two vertices when their common edge lines up; fewer
# means one face steps off the other and the unit has to jump. The projection is
# translation-only (`vertex + global_position`), as it was in `src/gpu/` — NOT the
# full `global_transform * vertex` `MapGridOverlay` uses, because tiles carry no
# rotation and changing it here would silently move a gameplay threshold.
func _edge_vertices_match(from_tile: Tile, to_tile: Tile) -> bool:
	var from_world := _world_vertices(from_tile)
	var to_world := _world_vertices(to_tile)
	var matches := 0
	for from_v in from_world:
		for to_v in to_world:
			if from_v.distance_to(to_v) < VERTEX_MATCH_EPSILON:
				matches += 1
				break
	return matches >= 2


func _world_vertices(tile: Tile) -> Array[Vector3]:
	var world_vertices: Array[Vector3] = []
	for i in range(4):
		world_vertices.append(tile.tile_vertices[i] + tile.global_position)
	return world_vertices
