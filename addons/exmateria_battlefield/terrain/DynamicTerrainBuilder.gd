extends RefCounted

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")

## ADR-0211 dec. 4 — the addon's façade is its whole symbol surface; one alias line
## per file keeps the use sites spelled the way they were.
const TerrainCell = ExMateriaSchema.TerrainCell


const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
# The store has no `class_name` (ADR-0192 dec. 4); this is one of the three addon
# files that `preload` it — the one that FILLS it.
const TerrainIndexStore = preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")
## Builds terrain tiles dynamically for doodad placement.
##
## Supports incremental operations:
## - Add tiles from doodad terrain data with coordinate transformation
## - Remove tiles in bounds from index
## - Returns tile nodes for scene tree management
##
## Used by MapComposer for dynamic doodad placement.

# Dependencies (set via initialize)
var terrain_index: TerrainIndexStore


## Initialize builder with terrain index.
##
## Args:
##     p_terrain_index: the tile store to populate and query
func initialize(p_terrain_index: TerrainIndexStore) -> void:
	terrain_index = p_terrain_index


## Add terrain tiles from doodad with coordinate transformation.
##
## Args:
##     terrain_data: terrain.json data from doodad
##     doodad_id: Unique ID for this doodad placement
##     offset: Tile coordinate offset (e.g., Vector2i(10, 5) to place at grid (10,5))
##
## Returns:
##     Array of MeshInstance3D tile nodes to add to scene tree
##
## Transforms:
##     - Grid coordinates: add offset to tile x,z
##     - Vertex positions: add (offset.x, 0, offset.y) in world space
func add_terrain(terrain_data: Dictionary, doodad_id: String, offset: Vector2i) -> Array[Tile]:
	var tiles: Array[Tile] = []
	var terrain: Dictionary = terrain_data.terrain

	# BOTH LEVELS (ADR-0219 dec. 5). This function read `terrain.level_0` and stopped,
	# and because `MapComposer` loads the base map through the DOODAD path, that one
	# line was the loss site for every map in the game — `grep -rn "level_1"
	# --include=*.gd` returned zero across the whole tree. The bridge Algus walks over
	# at MAP009 `(4, 11)` is a level-1 tile; without this loop he walks under it.
	# Driven by what the DATA states, not by counting to `LEVEL_COUNT`: the bound is
	# a fact about the ROM's terrain block, and reading it as a loop limit would make
	# a third level vanish silently instead of reporting itself.
	var level: int = 0
	while terrain.has("level_%d" % level):
		var rows: Variant = terrain["level_%d" % level]
		if rows is Array:
			assert(level < TerrainCell.LEVEL_COUNT,
				"terrain level %d exceeds the ROM's bound of %d (ADR-0219)" %
				[level, TerrainCell.LEVEL_COUNT])
			tiles.append_array(_add_level(rows, level, doodad_id, offset))
		level += 1

	return tiles


# One level of a `terrain.json` grid. `level` is the cell key's third component.
func _add_level(rows: Array, level: int, doodad_id: String, offset: Vector2i) -> Array[Tile]:
	var tiles: Array[Tile] = []

	# Iterate through 2D grid (z is outer, x is inner)
	for z in range(rows.size()):
		var row = rows[z]
		if not row is Array:
			continue

		for x in range(row.size()):
			var tile_data = row[x]

			# Skip null tiles (sparse grid support)
			if tile_data == null:
				continue

			if not tile_data is Dictionary:
				continue

			if not _slot_is_occupied(tile_data, level):
				continue

			# Get grid coordinates from tile data and transform
			var src_grid_x = tile_data.get("x", x)
			var src_grid_z = tile_data.get("z", z)
			var grid_x = src_grid_x + offset.x
			var grid_z = src_grid_z + offset.y

			# Create tile with transformed coordinates
			var tile = _create_tile(tile_data, grid_x, grid_z, level, offset)
			tiles.append(tile)

			# Add to terrain index
			terrain_index.add_tile(tile, doodad_id)

	return tiles


# Does this slot hold a tile at all?
#
# FFT writes every column's every level as a full 8-byte record, so "absent" is a
# VALUE, not a missing entry — an empty upper slot exports as `NaturalSurface`, height
# 0, thickness 0, `unselectable`. Level 0 is exempt because the ground is the thing a
# map's bounding box is drawn around: 77 of the corpus's 14,465 level-0 slots read as
# all-zero and every one of them has been minted since the map loader existed, so
# applying this test there would delete terrain rather than stop inventing it.
#
# At level 1 the test is `thickness > 0 OR selectable`: a slab that DRAWS is a tile
# even where the map forbids targeting it (7 in the corpus), and a slot the map marks
# selectable is a tile even where it draws nothing (3). Together they mint 209 tiles
# across 45 maps, containing all 202 of the selectable level-1 tiles ADR-0219 P3 counts.
static func _slot_is_occupied(tile_data: Dictionary, level: int) -> bool:
	if level == 0:
		return true
	return int(tile_data.get("thickness", 0)) > 0 \
		or not bool(tile_data.get("unselectable", false))


## Remove terrain tiles in bounds from index.
##
## Args:
##     bounds: Rect2i defining area in tile coordinates (position + size)
##
## Returns:
##     Array of removed Tile nodes (caller should remove from scene tree)
func remove_terrain_in_bounds(bounds: Rect2i) -> Array[Tile]:
	var removed_tiles: Array[Tile] = []

	var min_x = bounds.position.x
	var min_z = bounds.position.y
	var max_x = bounds.position.x + bounds.size.x - 1
	var max_z = bounds.position.y + bounds.size.y - 1

	# EVERY LEVEL of every column in bounds. `bounds` is a `Rect2i` and stays one:
	# a doodad occupies a footprint, and the whole of a column is what leaves with it
	# (ADR-0219 — bounds address columns, keys address cells).
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			for tile in terrain_index.column(x, z):
				removed_tiles.append(tile)
				terrain_index.remove_tile(tile.cell_key)

	return removed_tiles


## Create a single Tile node from terrain data.
##
## Args:
##     data: Tile data from terrain.json
##     grid_x: Transformed grid X coordinate
##     grid_z: Transformed grid Z coordinate
##     level: Terrain level — the cell key's third component (ADR-0219 dec. 1)
##     offset: Coordinate offset used for vertex transformation
##
## Returns:
##     Configured Tile node
func _create_tile(data: Dictionary, grid_x: int, grid_z: int, level: int,
		offset: Vector2i) -> Tile:
	var tile = Tile.new()
	# The level is in the NAME as well as the key: two tiles now legitimately share
	# (x, z), and a scene tree with two `Tile_4_11` children under one map is a
	# debugging trap for the next reader.
	tile.name = "Tile_%d_%d_L%d" % [grid_x, grid_z, level]

	# Set grid position (already transformed)
	tile.grid_x = grid_x
	tile.grid_z = grid_z
	tile.level = level

	# Set terrain properties
	tile.surface_type = data.get("surface_type", "Unknown")
	tile.height = data.get("height", 0)
	tile.slope_type = data.get("slope_type", "Flat")
	tile.impassable = data.get("impassable", false)
	tile.unselectable = data.get("unselectable", false)
	tile.pass_through_only = data.get("pass_through_only", false)
	tile.depth = data.get("depth", 0)
	tile.slope_height = data.get("slope_height", 0)
	tile.thickness = data.get("thickness", 0)
	tile.shading = data.get("shading", 1)

	# Store normal vector
	if data.has("normal"):
		var n = data.normal
		tile.normal = Vector3(n.x, n.y, n.z)

	# Parse and transform vertices from FFT space to Godot space
	var vertices = PackedVector3Array()
	if data.has("vertices") and data.vertices is Array and data.vertices.size() == 4:
		for v in data.vertices:
			vertices.append(_fft_vertex_to_godot([v.x, v.y, v.z], offset))
	else:
		push_warning("Tile %d,%d L%d has invalid vertices, using default" % [grid_x, grid_z, level])
		# Create default flat quad (already in 1.0 scale).
		#
		# BOTH halves are `MapConstants`' now, not this file's — the HEIGHT since
		# ADR-0218 dec. 5, the WINDING since #749. This used to state each rule a
		# second time and disagree with the exporter on both: `height * 0.25 *
		# TILE_SCALE` = 0.4464h against the exporter's 0.4286h + 0.0357, and the
		# reverse corner cycle. Reachable only by omitting a field no shipped
		# `terrain.json` omits, which is why neither disagreement ever surfaced.
		var y = MapConstants.surface_y(data.get("height", 0), data.get("depth", 0))
		vertices = MapConstants.flat_quad(grid_x, grid_z, y)

	# Calculate tile center position
	var center = (vertices[0] + vertices[1] + vertices[2] + vertices[3]) / 4.0
	tile.position = center

	# Convert vertices to local space (relative to center)
	var local_vertices = PackedVector3Array()
	for v in vertices:
		local_vertices.append(v - center)

	# Store vertices (used by highlight system)
	tile.tile_vertices = local_vertices

	# Create collision shape (relative to tile center)
	_create_collision_shape(tile, local_vertices)

	# Configure collision layers
	tile.collision_layer = 2  # Layer 2 for tile selection
	tile.collision_mask = 0   # Tiles don't collide with anything

	return tile


## Create collision shape for tile.
##
## Args:
##     tile: Tile node to add collision to
##     local_vertices: Vertices in local space (relative to tile center)
func _create_collision_shape(tile: Tile, local_vertices: PackedVector3Array):
	# Create convex shape
	var collision = CollisionShape3D.new()
	var convex_shape = ConvexPolygonShape3D.new()

	# Set vertices (4 corners)
	convex_shape.points = local_vertices

	collision.shape = convex_shape
	tile.add_child(collision)


## Transform vertex from FFT space to Godot space with tile offset.
func _fft_vertex_to_godot(fft_position: Array, tile_offset: Vector2i) -> Vector3:
	var fft_offset_x = float(tile_offset.x) / MapConstants.TILE_SCALE
	var fft_offset_z = float(tile_offset.y) / MapConstants.TILE_SCALE
	return Vector3(
		(fft_position[0] + fft_offset_x) * MapConstants.TILE_SCALE,
		fft_position[1] * MapConstants.TILE_SCALE,
		(fft_position[2] + fft_offset_z) * MapConstants.TILE_SCALE
	)
