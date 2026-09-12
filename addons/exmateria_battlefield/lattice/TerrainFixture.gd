extends Node3D

## The **terrain fixture** — the addon's shipped way to stand a `Lattice` up from
## data, and the only sanctioned lattice test seam (ADR-0218).
##
## 🔴 NOTHING HERE IS FAKE. The tiles are `Tile` nodes minted by
## `DynamicTerrainBuilder`, the store is a `TerrainIndex`, the port is a `Lattice`
## and the cliff rule is `Lattice._edge_vertices_match`. This class states terrain
## and then gets out of the way; every answer a consumer reads is production's.
## That is the entire point. It replaced ten hand-written doubles that between
## them dropped every `TerrainCell` field but `grid`, disagreed four ways about
## where a tile sits, and answered `false` to every cliff question ever asked —
## `is_cliff_edge`, the port's only real computation and the sole producer of the
## per-neighbour cliff byte the GPU map buffer carries, was executed by no test in
## the suite.
##
## ADR-0170 dec. 5 used to sanction two routes for a lattice mock: `extends
## Lattice` and override, or construct a real `Lattice`. Every test took the
## first. ADR-0218 dec. 1 WITHDRAWS it — a class with its own `is_cliff_edge` is
## a second implementation of a gameplay threshold, which is the defect, not the
## seam. This is the second route, made cheap enough that nobody needs the first.
##
## THE INTERFACE IS THREE VERBS AND A PROPERTY (ADR-0218 dec. 6):
##
##     var fix := TerrainFixture.flat(Rect2i(0, 0, 20, 20))   # the common case
##     fix.put(Vector2i(3, 4), 7)                             # one cell, sparse
##     fix.put(Vector2i(3, 4), 7, {"impassable": true})       # …with flags
##     fix.put_shape(Vector2i(5, 5), corners)                 # explicit corners
##     fix.put(Vector2i(4, 11), 7, {}, 1)                     # a BRIDGE over (4,11)
##     TerrainFixture.from_terrain(dict)                      # a real exported map
##     add_child(fix)
##     var lattice: Lattice = fix.lattice                     # builds on first read
##     fix.highlights.paint(cell, CellMarking.Kind.SELECTED)  # the other published surface
##
## A hole is a cell you never `put`. `build()` is not a step: the first read of
## `lattice` performs it, and a `put` after one re-performs it — the port OBJECT
## survives that (`Lattice._bind`), exactly as it survives a `change_map` in
## production, so a handle taken early never goes stale.
##
## ⚠️ TAKING A `terrain.json` DICT DIRECTLY is the right INTERNAL path and the
## wrong interface (dec. 6): it makes every caller learn the exporter's schema in
## order to say "a flat 20×20". The dict is assembled below instead, in the shape
## `DynamicTerrainBuilder.add_terrain` reads — rows of cells with `null` for the
## squares nothing occupies, which is how the real thing states a hole too.
##
## ⚠️ THIS IS A `Node3D` AND THAT IS TWO DECISIONS AT ONCE. It owns the tiles it
## made, so their `global_position` — which the cliff rule projects through — is
## meaningful; and being a node that exposes `lattice` it satisfies BOTH
## duck-typed map probes in the tree, `ScenarioVM._lattice()`'s `"lattice" in
## map_composer` and `TileCursor`/`PlayerCamera`'s `procedural_map_path`. So it
## also replaced the four `class *Map extends Node` wrappers that existed for no
## other reason (dec. 2).
##
## ⚠️ FIXTURE MAPS ARE BOUNDED (dec. 4). `flat` takes a `Rect2i` and there is no
## infinite-plane mode: no map in the game is unbounded, and the map edge an
## unbounded double hides is one its production consumer meets.
##
## ⚠️ FREEING A FIXTURE CONSTRUCTS `TileOverlayCompositor` if nothing else has —
## `Tile._exit_tree` unregisters unconditionally. Harmless where a content root is
## set; one `push_error` in a bare install (ADR-0218 Consequences).
##
## Run the cliff rule it exists to make testable:
##   bash tests/stranger/exmateria_battlefield/run.sh

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
const DynamicTerrainBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicTerrainBuilder.gd")
# The store has no `class_name` (ADR-0192 dec. 4). This is a fourth addon file
# that `preload`s it — the one that hands a FRESH one to the builder per build.
const TerrainIndexStore = preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")
const TileHighlights = preload("res://addons/exmateria_battlefield/overlay/TileHighlights.gd")

## Self-preload, so the static factory below can state what it returns. Legal:
## `preload` of the file it is written in resolves to the already-loading script.
const TerrainFixture = preload("res://addons/exmateria_battlefield/lattice/TerrainFixture.gd")

## `add_terrain`'s doodad id. Every tile a fixture mints belongs to the same
## notional placement; `TerrainIndex` records it and nothing here reads it back.
const DOODAD_ID: String = "fixture"


## The port over this fixture's terrain, built on first read.
##
## 🔴 ONE `Lattice` FOR THIS NODE'S LIFETIME, rebound rather than replaced. A test
## that takes the handle, then `put`s more terrain, then asserts, is holding the
## port it was given — the same reason `MapComposer` creates one `Lattice` and
## `_bind`s each new store into it (see `Lattice._bind`).
var lattice: Lattice:
	get:
		if not _built:
			_build()
		return _lattice


## The highlight publish over this fixture's terrain, alongside the port — the same
## pair `MapComposer` exposes, `_bind` for `_bind` (ADR-0221 dec. 7). A `Lattice`
## with no publish beside it made the addon's own arbitration untestable without a
## map, which is the one thing a fixture must not do. Stable across a rebuild for
## the same reason the port is, and the slot table is dropped on each one.
var highlights: TileHighlights:
	get:
		if not _built:
			_build()
		return _highlights


var _lattice: Lattice = Lattice.new()
var _highlights: TileHighlights = TileHighlights.new()
# Vector3i cell key -> the `terrain.json`-shaped row for that cell. Keyed on the
# CELL and not the column since ADR-0219: a fixture states a bridge by `put`ting
# the same (x, z) at two levels, which is the case the ten deleted doubles could
# not express at all.
var _cells: Dictionary = {}
var _built: bool = false


## A fixture whose every square in `bounds` carries the same `height` and `flags`.
##
## The common case, and the one that used to be written as an unbounded double
## answering `Vector3.ZERO`. `bounds` is in grid coordinates: `Rect2i(0, 0, 20,
## 20)` is the squares (0,0) through (19,19).
static func flat(bounds: Rect2i, height: int = 0, flags: Dictionary = {}) -> TerrainFixture:
	# Level 0 only. A flat plane has no upper storey, and a `flat` that filled both
	# would make every existing caller state a bridge it never asked for.
	var fixture := TerrainFixture.new()
	for gz in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for gx in range(bounds.position.x, bounds.position.x + bounds.size.x):
			fixture.put(Vector2i(gx, gz), height, flags)
	return fixture


## A fixture over a `terrain.json` dict, verbatim — the exporter's own rows, at
## their own coordinates, with nothing re-derived.
##
##     var fix := TerrainFixture.from_terrain(JSON.parse_string(text))
##
## The counterpart to `flat()`, and the reason dec. 6's ⚠️ does not refuse it:
## the dict is off the interface so that saying "a flat 20x20" costs nobody the
## exporter's schema, and a caller holding an `assets/maps/*/terrain.json`
## already has that schema from the exporter. What it buys is that a host test
## over a REAL map no longer has to reach `DynamicTerrainBuilder` for its
## `Array[Tile]` — the Tile door `check_lattice_doors.py` refuses, and refuses
## for the reason ADR-0164 dec. 4 gives: a host that can hold a `Tile` can store
## one, and a stored node is invisible to the port's own criteria.
##
## 🔴 EVERY NON-NULL ROW IS CARRIED ACROSS, INCLUDING THE EMPTY UPPER SLOTS FFT
## ENCODES AS A VALUE. `DynamicTerrainBuilder._slot_is_occupied` is what decides
## which of them mint a tile, and filtering here would hand the caller a map the
## game does not have — over the corpus that is 209 upper tiles across 45 maps,
## not the 14,000 slots the file states.
##
## A `put` afterwards edits the loaded map, which is the point: state MAP009 and
## then change one square, without either half being hand-written.
static func from_terrain(terrain_data: Dictionary) -> TerrainFixture:
	var fixture := TerrainFixture.new()
	var terrain: Variant = terrain_data.get("terrain", {})
	if not terrain is Dictionary:
		return fixture
	# Driven by what the DATA states, exactly as `DynamicTerrainBuilder.add_terrain`
	# is: counting to `LEVEL_COUNT` here would make a third level vanish silently
	# instead of reaching the assert that reports it.
	var level: int = 0
	while terrain.has("level_%d" % level):
		var rows: Variant = terrain["level_%d" % level]
		if rows is Array:
			for z in range(rows.size()):
				var row: Variant = rows[z]
				if not row is Array:
					continue
				for x in range(row.size()):
					var cell: Variant = row[x]
					if not cell is Dictionary:
						continue  # a hole is a `null`, and stays one
					# The row's OWN `x`/`z` win over the array position, because
					# that is which one `_add_level` reads.
					fixture._cells[Vector3i(
						int(cell.get("x", x)), int(cell.get("z", z)), level)] = cell
		level += 1
	return fixture


## State one flat square: its FFT half-step `height` and whatever `flags` say.
##
## `flags` is merged into the tile's `terrain.json` row, so its keys are that
## schema's field names. The four the port hands out as `TerrainCell` descriptors
## are `impassable`, `unselectable`, `pass_through_only` and `surface_type`;
## `depth` counts toward the surface height alongside `height`. Anything else the
## row accepts (`shading`, `thickness`, `normal`, `slope_type`) rides along and is
## read by the tile, not the cell.
##
## The four corners come from `MapConstants.flat_quad` at
## `MapConstants.surface_y`, i.e. the exporter's arithmetic — never by omitting
## `vertices` and taking `DynamicTerrainBuilder`'s fallback, which is a second
## copy of the same rule and the reason dec. 5 extracted the first.
## `level` is the cell key's third component (ADR-0219 dec. 1) — `0` is the ground,
## `1` the bridge/roof plane. `put`ting the same `grid` at both states a column with
## two cells, which is what MAP009 `(4, 11)` is and what no test could say before.
func put(grid: Vector2i, height: int = 0, flags: Dictionary = {},
		level: int = 0) -> void:
	var row := _row(grid, height, flags, level)
	var y := MapConstants.surface_y(height, int(row.get("depth", 0)))
	row["vertices"] = _to_fft(MapConstants.flat_quad(grid.x, grid.y, y))
	_cells[Vector3i(grid.x, grid.y, level)] = row
	_restate()


## State one square by its four WORLD-SPACE corners.
##
## The escape hatch dec. 6 keeps so that a cliff, a slope and a fractional world
## Y are all statable without a second interface — GDScript has no rule that turns
## `slope_type` into which corners lift (the exporter bakes them), so corners are
## the only way to say those things at all.
##
## The tile lands at the MEAN of the four, and its `tile_vertices` are re-expressed
## relative to that centre, because that is what `_create_tile` does to every real
## tile. Four coplanar corners at `y` therefore put the tile at `y`.
##
## ⚠️ `height` IS INDEPENDENT OF THE CORNERS and stays the gameplay half-step —
## what the distance field and the GPU mover compare against a jump range. State
## it when a consumer reads `TerrainCell.height`; leave it when only the geometry
## matters. Nothing reconciles the two, deliberately: a fixture that derived one
## from the other could not state the fractional world heights this exists for.
func put_shape(grid: Vector2i, vertices: PackedVector3Array, height: int = 0,
		flags: Dictionary = {}, level: int = 0) -> void:
	assert(vertices.size() == 4, "a tile has four corners, got %d" % vertices.size())
	var row := _row(grid, height, flags, level)
	row["vertices"] = _to_fft(vertices)
	_cells[Vector3i(grid.x, grid.y, level)] = row
	_restate()


# --- internal ---------------------------------------------------------------

# A `put` BEFORE the first read of `lattice` only accumulates — `flat()` states
# four hundred squares that way and pays for one build. A `put` AFTER one rebuilds
# NOW rather than marking the fixture dirty: the handle a caller already holds is
# the same object across the rebuild (`Lattice._bind`), so a deferred build would
# leave it answering for terrain the fixture no longer states until someone
# happened to touch the property again. That is the staleness the stable port
# object exists to prevent, and a fixture is the last place it should reappear.
func _restate() -> void:
	if _built:
		_build()


# The production path, and it is four lines (ADR-0218 Context). `add_terrain`
# mints the tiles AND fills the store, and hands them back orphan — only a
# `CollisionShape3D` child — so parenting them is the whole of what is left.
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var index := TerrainIndexStore.new()
	var builder := DynamicTerrainBuilder.new()
	builder.initialize(index)
	for tile in builder.add_terrain(_terrain_dict(), DOODAD_ID, Vector2i.ZERO):
		add_child(tile)

	_lattice._bind(index)
	_highlights._bind(index)
	_built = true


# A `terrain.json`-shaped dict over the stated cells: `level_0` rows spanning the
# bounding box, `null` where nothing was `put`. The rows carry their own `x`/`z`,
# which is what `add_terrain` reads, so the array position is redundant — it is
# built dense anyway because the null-skip is a production path and a fixture that
# routed around it would not be exercising the thing it claims to.
func _terrain_dict() -> Dictionary:
	var terrain: Dictionary = {}
	var keys: Array = _cells.keys()
	var levels: Array = []
	for key: Vector3i in keys:
		if not levels.has(key.z):
			levels.append(key.z)
	# `level_0` is always present, even empty — `add_terrain` reads the levels by
	# name and a fixture that stated only a bridge would otherwise hand it a dict
	# with no ground key at all.
	if not levels.has(0):
		levels.append(0)
	for level: int in levels:
		terrain["level_%d" % level] = _level_rows(keys, level)
	return {"terrain": terrain}


# One level's rows, spanning the bounding box of EVERY stated cell — not just this
# level's. The box is shared so the two grids line up index-for-index, which is what
# a `terrain.json` does and what makes a caller's `(x, z)` mean the same square at
# both levels.
func _level_rows(keys: Array, level: int) -> Array:
	var rows: Array = []
	if keys.is_empty():
		return rows

	var min_x: int = keys[0].x
	var max_x: int = keys[0].x
	var min_z: int = keys[0].y
	var max_z: int = keys[0].y
	for key: Vector3i in keys:
		min_x = mini(min_x, key.x)
		max_x = maxi(max_x, key.x)
		min_z = mini(min_z, key.y)
		max_z = maxi(max_z, key.y)

	for gz in range(min_z, max_z + 1):
		var row: Array = []
		for gx in range(min_x, max_x + 1):
			row.append(_cells.get(Vector3i(gx, gz, level), null))
		rows.append(row)
	return rows


func _row(grid: Vector2i, height: int, flags: Dictionary, level: int) -> Dictionary:
	var row: Dictionary = flags.duplicate()
	row["x"] = grid.x
	row["z"] = grid.y
	row["height"] = height
	# A fixture states a cell BECAUSE it wants one, so an upper-level row must clear
	# `DynamicTerrainBuilder._slot_is_occupied` — which reads the emptiness FFT
	# encodes as a value. Neither is overridden if `flags` already said so.
	if level > 0 and not row.has("thickness") and not row.has("unselectable"):
		row["thickness"] = 1
	return row


# `terrain.json` states vertices in FFT units (0.56 per tile) and
# `_create_tile` scales them by `TILE_SCALE` on the way in. Callers here speak
# world units, so this is that scaling inverted — the fixture's ONLY arithmetic
# that is not shared with production, and it exists because production reads a
# file and this reads a caller.
func _to_fft(world_vertices: PackedVector3Array) -> Array:
	var out: Array = []
	for v in world_vertices:
		out.append({
			"x": v.x / MapConstants.TILE_SCALE,
			"y": v.y / MapConstants.TILE_SCALE,
			"z": v.z / MapConstants.TILE_SCALE,
		})
	return out
