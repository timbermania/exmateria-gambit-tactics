class_name DistanceFieldGenerator
extends RefCounted

## Distance Field Generator for GPU Combat Simulation
##
## Precomputes shortest path distances between all walkable tiles using BFS.
## Exports a flat distance array for GPU upload.
##
## Usage:
##   var generator = DistanceFieldGenerator.new()
##   generator.generate(lattice, jump_range)
##   var flat = generator.get_flat_distances()  # For GPU upload

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell


# Distance field storage
# Key: "x,z" string for source tile
# Value: Dictionary mapping "x,z" -> distance
var _distances: Dictionary = {}

# Neighbor cache for pathfinding
# Key: "x,z" string for tile
# Value: Array of neighbor coordinate strings
var _neighbors: Dictionary = {}

# Map bounds
var _min_x: int = 0
var _max_x: int = 0
var _min_z: int = 0
var _max_z: int = 0

# Every cell on the map, keyed by grid position. Built ONCE per generate() from
# `Lattice.all_cells()` — the neighbour scan below needs impassable cells too (a
# walkable tile's neighbour may be impassable and must be REJECTED, not missed), so
# this is the whole map rather than `_walkable`. Replaces a per-neighbour
# `get_tile(nx, nz)` on the store: `terrain_at` mints a fresh `TerrainCell` every
# call by design (identity is `cell.grid`, ADR-0166 dec. 3), so calling it 4x per
# tile inside the hot loop would allocate where a Dictionary read does not.
var _cells: Dictionary = {}   # Vector3i cell key -> TerrainCell
var _jump_range: float = 3.0

# Stats
var _tile_count: int = 0
var _generation_time_ms: float = 0.0


func generate(lattice: Lattice, jump_range: float = 3.0) -> void:
	"""Generate distance field for all walkable cells.

	Args:
		lattice: the terrain port (ADR-0164 dec. 2) — this reads only cell FACTS
			(`grid`, `height`, `impassable`), never the tile node
		jump_range: Maximum jump height for traversal
	"""
	_jump_range = jump_range
	_distances.clear()
	_neighbors.clear()
	_cells.clear()

	var start_time = Time.get_ticks_msec()

	# One snapshot at init — ADR-0164 dec. 2's ⚠️ names this shape by name: not a
	# bulk read, a precomputed table taken once.
	var cells := lattice.all_cells() if lattice != null else ([] as Array[TerrainCell])
	var walkable_cells: Array[TerrainCell] = []

	# 🔴 THIS FIELD IS TWO PLANES (ADR-0224 dec. 1), and the filter that used to
	# stand here is gone. It dropped every `grid.z != GROUND_LEVEL` cell because a
	# node id was a COLUMN — one slot per (x, z) — so a second cell in the same
	# column would overwrite the first in `_cells` and whichever `all_cells()`
	# happened to yield last would win, silently and per-run.
	#
	# The node id is now a CELL: `level * total_tiles + (z - min_z) * width +
	# (x - min_x)`, dense over `LEVEL_COUNT` planes. Two cells in one column get two
	# ids, so there is nothing left to collide and nothing left to filter. Dense and
	# not sparse is dec. 1's ruling: `get_distance` is 22 shader call sites in the
	# innermost loop of the mover, and an indirection table there costs more than the
	# 0.7 MB a sparse plane would save.
	#
	# ⚠️ This is the change that is NOT inert. The flat matrix's stride is the node
	# count, so doubling the nodes moves `get_distance` for every reader — which is
	# exactly why ADR-0224 dec. 2 kept it out of the storage PR and put it here.
	for cell in cells:
		_cells[cell.grid] = cell
		if not cell.impassable:
			walkable_cells.append(cell)

	_tile_count = walkable_cells.size()

	# Calculate bounds
	if walkable_cells.size() > 0:
		_min_x = walkable_cells[0].grid.x
		_max_x = walkable_cells[0].grid.x
		_min_z = walkable_cells[0].grid.y
		_max_z = walkable_cells[0].grid.y

		for cell in walkable_cells:
			_min_x = mini(_min_x, cell.grid.x)
			_max_x = maxi(_max_x, cell.grid.x)
			_min_z = mini(_min_z, cell.grid.y)
			_max_z = maxi(_max_z, cell.grid.y)

	# Precompute neighbors for each cell
	for cell in walkable_cells:
		var key = _tile_key(cell.grid.x, cell.grid.y, cell.grid.z)
		_neighbors[key] = _compute_neighbors(cell)

	# Run BFS from each cell to compute distances
	for source in walkable_cells:
		_compute_distances_from(source, walkable_cells)

	_generation_time_ms = Time.get_ticks_msec() - start_time

	if DebugConfig.simulation_debug_enabled:
		print("[DistanceField] Generated for %d tiles in %.1fms" % [_tile_count, _generation_time_ms])


## The BFS's node identity, and it is a CELL not a column (ADR-0224 dec. 1).
## `level` is `TerrainCell.grid.z` — the ⚠️ that has cost this line of work more
## time than anything else is that `grid.z` is a LEVEL, while the `z` argument
## here is a grid Z.
func _tile_key(x: int, z: int, level: int) -> String:
	return "%d,%d,%d" % [x, z, level]


func _compute_neighbors(cell: TerrainCell) -> Array[String]:
	"""Compute traversable neighbors for a cell.

	IMPORTANT: Uses cell.height (FFT half-steps) for height comparison,
	matching the GPU shader logic exactly. This ensures distance field
	paths are actually traversable by units on the GPU.
	"""
	var neighbors: Array[String] = []

	# Four column-to-column neighbours, and EVERY admissible cell of the target
	# column is a candidate — ADR-0224 dec. 5 adopts ADR-0219 dec. 6 verbatim
	# rather than restating it, because the two movers must not come to disagree
	# about the same bridge. `EventPathfinder` floods `nav.cells_at(x, z)` and lets
	# the climb gate reject the rest; this enqueues the same candidate set and lets
	# the same height rule reject the rest.
	#
	# There is no fifth or sixth move and no in-place level change: a unit standing
	# under a bridge cannot step onto the deck above it, because the deck is not a
	# neighbour of its own column. It walks to the ramp like everything else.
	for dir in [[0, 1], [1, 0], [0, -1], [-1, 0]]:
		var nx = cell.grid.x + dir[0]
		var nz = cell.grid.y + dir[1]
		for level in range(TerrainCell.LEVEL_COUNT):
			var neighbor: TerrainCell = _cells.get(Vector3i(nx, nz, level), null)

			if not neighbor:
				continue
			if neighbor.impassable:
				continue

			# Use cell.height directly (FFT half-steps) - matches GPU shader logic
			# GPU shader does: abs(to_h - from_h) > jump
			# So we allow if: abs(height_diff) <= jump_range
			#
			# THIS is the gate that decides the level, and it is the only one. A
			# deck 9 half-steps over its floor is unreachable from the floor under
			# the baked `jump_range`, which is correct and is why no separate
			# cross-level rule is invented here (ADR-0224 dec. 7 records that the
			# baked threshold is per-FIELD, not per-unit, and does not fix it).
			var height_diff = abs(neighbor.height - cell.height)
			if height_diff <= _jump_range:
				neighbors.append(_tile_key(nx, nz, level))
			elif DebugConfig.iteration_debug_enabled:
				print("[DistanceField] BLOCKED: (%d,%d,L%d) h=%d -> (%d,%d,L%d) h=%d, diff=%d > jump=%d" % [
					cell.grid.x, cell.grid.y, cell.grid.z, cell.height,
					nx, nz, level, neighbor.height,
					height_diff, _jump_range
				])

	return neighbors


func _compute_distances_from(source: TerrainCell, _all_cells: Array[TerrainCell]) -> void:
	"""BFS from source cell to compute distances to all reachable cells."""
	var source_key = _tile_key(source.grid.x, source.grid.y, source.grid.z)
	var distances: Dictionary = {}
	distances[source_key] = 0

	var frontier: Array[String] = [source_key]
	var frontier_idx = 0

	while frontier_idx < frontier.size():
		var current_key = frontier[frontier_idx]
		frontier_idx += 1

		var current_dist = distances[current_key]
		var neighbors = _neighbors.get(current_key, [])

		for neighbor_key in neighbors:
			if not distances.has(neighbor_key):
				distances[neighbor_key] = current_dist + 1
				frontier.append(neighbor_key)

	_distances[source_key] = distances


func get_stats() -> Dictionary:
	"""Get generation statistics."""
	return {
		"tile_count": _tile_count,
		"generation_time_ms": _generation_time_ms,
		"bounds": {
			"min_x": _min_x,
			"max_x": _max_x,
			"min_z": _min_z,
			"max_z": _max_z
		}
	}


func get_flat_distances() -> PackedInt32Array:
	"""Export distances as flat array for GPU upload.

	Format: a dense pairwise matrix over CELLS, not columns (ADR-0224 dec. 1).
	A node id is `level * total_tiles + (z - min_z) * width + (x - min_x)`, and
	the matrix is row-major with stride `node_count()`:

		flat[from_node * node_count + to_node]

	Returns: array of size `(LEVEL_COUNT * width * height)^2`.

	🔴 THE STRIDE MOVED. Before ADR-0224 it was `total_tiles`, so every reader of
	`get_distance` — 22 shader call sites — computes a different address against
	this array than it did. That is why dec. 2 could not stage this half inertly
	and why it lands with the shader pass rather than with the map buffer.

	Level 0's SUBMATRIX is still byte-identical on the 74 maps that mint no upper
	cell (dec. 8): they have no level-1 node to route through, so no ground pair's
	distance can move. `GPUMapBufferLevelRatchetTest`'s arm 4 is that claim, and it
	checks it against the golden's pre-widening `dist_sha` rather than a re-taken
	hash — the bytes it compares are the same bytes, addressed differently.

	Value encoding:
		-1 = unreachable
		>=0 = distance in tiles
	"""
	var width = _max_x - _min_x + 1
	var height = _max_z - _min_z + 1
	var total_tiles = width * height
	var nodes = total_tiles * TerrainCell.LEVEL_COUNT
	var flat: PackedInt32Array = PackedInt32Array()
	flat.resize(nodes * nodes)

	# Initialize all to -1 (unreachable)
	flat.fill(-1)

	# Fill in distances
	for from_level in range(TerrainCell.LEVEL_COUNT):
		for from_z in range(_min_z, _max_z + 1):
			for from_x in range(_min_x, _max_x + 1):
				var from_key = _tile_key(from_x, from_z, from_level)

				if not _distances.has(from_key):
					continue

				var from_idx = from_level * total_tiles \
					+ (from_z - _min_z) * width + (from_x - _min_x)
				var distances = _distances[from_key]
				for to_level in range(TerrainCell.LEVEL_COUNT):
					for to_z in range(_min_z, _max_z + 1):
						for to_x in range(_min_x, _max_x + 1):
							var to_key = _tile_key(to_x, to_z, to_level)
							var to_idx = to_level * total_tiles \
								+ (to_z - _min_z) * width + (to_x - _min_x)
							var flat_idx = from_idx * nodes + to_idx

							flat[flat_idx] = distances.get(to_key, -1)

	return flat


## The node id the flat matrix is addressed by, and the shader's `get_distance`
## computes the same expression. Exposed so a test can name a cell rather than
## re-deriving the arithmetic — an assertion that recomputes the subject's own
## index cannot catch the subject getting it wrong.
func node_index(x: int, z: int, level: int) -> int:
	var width = _max_x - _min_x + 1
	var height = _max_z - _min_z + 1
	return level * (width * height) + (z - _min_z) * width + (x - _min_x)


## `LEVEL_COUNT * width * height` — the matrix's stride, and its side length.
func node_count() -> int:
	var width = _max_x - _min_x + 1
	var height = _max_z - _min_z + 1
	return width * height * TerrainCell.LEVEL_COUNT
