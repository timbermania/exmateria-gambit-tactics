extends RefCounted
## THE EXPORTED-MAP CORPUS, AND THE ONE MEASUREMENT TAKEN OVER IT.
##
## Shared by `tools/gen_map_buffer_golden.gd` (which writes the golden) and
## `tests/GPUMapBufferLevelRatchetTest.gd` (which checks it). One file, because a
## golden and its ratchet that measure two slightly different things are a green
## test about nothing — the generator ran against the OLD `build_map_data` and
## the test runs against the NEW one, so the only thing keeping them comparable
## is that `measure()` is literally the same code on both sides.
##
## ⚠️ `measure()` IS FROZEN BY ADR-0224 dec. 8. It hashes the map buffer's first
## `GROUND_PREFIX_PLANES * total_tiles` ints — which was the WHOLE buffer before
## the widening and is the level-0 compatibility prefix after it. That identity
## is the ratchet; changing what this function measures retires it.
##
## PR B ADDS a measurement, `dist_ground_sha`, and does not change one. The
## distance field widened to `(LEVEL_COUNT * total_tiles)^2` (ADR-0224 dec. 1), so
## `dist_sha` — a hash of the whole flat array — stopped being comparable to the
## golden's. The tempting response is to re-take the golden, and it would prove
## nothing: a hash of the new array agrees with itself by construction.
##
## 🔴 THE GOLDEN DID NOT NEED RE-TAKING, because the golden's `dist_sha` ALREADY
## IS the ground submatrix. Before the widening the flat array was exactly the
## `total_tiles x total_tiles` ground-to-ground block, laid out row-major with
## stride `total_tiles`. `dist_ground_sha` pulls that same block back out of the
## widened array (stride `LEVEL_COUNT * total_tiles`) and hashes it the same way,
## so the arm compares the same bytes across the change — which is what dec. 8
## asked for and what a re-taken hash would have thrown away. The test pins the
## claim rather than trusting this comment: it asserts the golden's `dist_size`
## is `total_tiles^2`, i.e. that the golden was taken on a one-plane field.
##
## Not a test: no `.tscn`, so `tools/check_test_list_coverage.py`'s universe
## never sees it (same shape as `GPUCombatTestBase.gd`).

# ADR-0211 dec. 4 -- the addon's facade is its whole symbol surface.
const Lattice = ExMateriaBattlefield.Lattice
const TerrainFixture = ExMateriaBattlefield.TerrainFixture
const TerrainCell = ExMateriaSchema.TerrainCell

const MAPS_DIR := "res://assets/maps"
const GOLDEN_PATH := "res://tests/data/map_buffer_golden.json"

## The level-0 block's width in planes: `heights | traversable | cliff x 4`.
## Before ADR-0224 this was the entire map buffer; after it, it is the prefix
## dec. 2's level-major layout promises to leave untouched. Both readings are
## the same six planes, which is the whole point.
const GROUND_PREFIX_PLANES := 6


## Every exported map with a `terrain.json`, sorted. 119 in the corpus.
static func map_names() -> PackedStringArray:
	var names := PackedStringArray()
	var d := DirAccess.open(MAPS_DIR)
	if d == null:
		return names
	for entry in d.get_directories():
		if FileAccess.file_exists("%s/%s/terrain.json" % [MAPS_DIR, entry]):
			names.append(entry)
	names.sort()
	return names


## One map's `terrain.json`, in the shape `DynamicTerrainBuilder.add_terrain`
## reads. Empty on any read/parse failure -- the caller reports it by name.
static func load_terrain(map_name: String) -> Dictionary:
	var f := FileAccess.open("%s/%s/terrain.json" % [MAPS_DIR, map_name], FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## The measurement, and it is FROZEN (see the class docstring).
##
## Runs the distance field to get the bounds `build_map_data` is indexed on --
## the same order `GPUBatchSimulator._create_buffers` does it in -- then hashes
## the two arrays ADR-0224 dec. 8 puts under the ratchet.
static func measure(lattice: Lattice) -> Dictionary:
	var field := DistanceFieldGenerator.new()
	field.generate(lattice)
	var bounds: Dictionary = field.get_stats()["bounds"]
	var min_x: int = bounds["min_x"]
	var min_z: int = bounds["min_z"]
	var width: int = bounds["max_x"] - min_x + 1
	var height: int = bounds["max_z"] - min_z + 1
	var total_tiles := width * height

	var map_data := GPUBatchSimulator.build_map_data(lattice, min_x, min_z, width, height)
	var flat := field.get_flat_distances()

	return {
		"min_x": min_x,
		"min_z": min_z,
		"width": width,
		"height": height,
		"total_tiles": total_tiles,
		"map_size": map_data.size(),
		"ground_sha": _sha(map_data.slice(0, total_tiles * GROUND_PREFIX_PLANES)),
		"dist_size": flat.size(),
		"dist_sha": _sha(flat),
		"dist_ground_sha": _sha(ground_submatrix(flat, total_tiles)),
		"dist_upper_sources": upper_source_nodes(flat, total_tiles),
	}


## How many level-1 NODES the distance field actually flooded from.
##
## The field runs one BFS per walkable cell and a source's distance to itself is
## 0, so `flat[n * stride + n] == 0` says node `n` was a source. A node that is
## impassable, or that no cell was ever minted for, is never a source and keeps
## the `-1` fill. Counting the zeros on the diagonal above `total_tiles` is
## therefore the field's own census of its upper plane, taken off the exported
## bytes rather than off the lattice it was built from.
##
## This is the distance field's arm 8: every other arm here stays green if the
## field allocates `(2T)^2` ints and floods only the ground, and this is the one
## that fails on a widening that never landed. Returns 0 on a pre-widening
## (one-plane) array, where the range is empty, and -1 on a non-square one.
static func upper_source_nodes(flat: PackedInt32Array, total_tiles: int) -> int:
	var stride := roundi(sqrt(float(flat.size())))
	if stride * stride != flat.size() or total_tiles <= 0:
		return -1
	var count := 0
	for node in range(total_tiles, stride):
		if flat[node * stride + node] == 0:
			count += 1
	return count


## The ground-to-ground block of a distance matrix, whatever the matrix's stride.
##
## The flat field is row-major over CELL node ids, `level * total_tiles + z * w + x`
## (ADR-0224 dec. 1), so the level-0 nodes are ids `[0, total_tiles)` and the
## ground-to-ground distances are the top-left `total_tiles x total_tiles` corner
## — contiguous in neither direction once a second plane exists.
##
## On a PRE-widening array (`stride == total_tiles`) this returns the array
## unchanged, which is exactly why the golden taken then is a valid expectation
## for what this returns now.
static func ground_submatrix(flat: PackedInt32Array, total_tiles: int) -> PackedInt32Array:
	# The stride is read off the array rather than passed in, so this one function
	# is correct for both the pre-widening square (`stride == total_tiles`) and the
	# widened one (`stride == LEVEL_COUNT * total_tiles`) with no caller stating
	# which it holds. `roundi` and then a squared check, not a bare `int(sqrt(...))`
	# — a truncating cast turns a float that landed a hair under the integer into a
	# silently-off-by-one stride, and every hash below it would still be a hash.
	var stride := roundi(sqrt(float(flat.size())))
	var out := PackedInt32Array()
	if stride * stride != flat.size() or stride < total_tiles or total_tiles <= 0:
		# Not a square matrix, or too small to hold the ground block. Empty, so the
		# caller reports it by name rather than hashing a plausible-looking prefix.
		return out
	out.resize(total_tiles * total_tiles)
	for from_idx in range(total_tiles):
		for to_idx in range(total_tiles):
			out[from_idx * total_tiles + to_idx] = flat[from_idx * stride + to_idx]
	return out


## A real map's port, through the addon's own seam (ADR-0218). The fixture is
## parented BEFORE `lattice` is read, because the first read builds the tiles and
## the cliff rule projects through their `global_position`.
##
## `TerrainFixture.from_terrain` rather than `DynamicTerrainBuilder.add_terrain`
## directly: that method returns `Array[Tile]`, and a host file naming it puts a
## Tile door on `check_lattice_doors.py`'s register (ADR-0164 dec. 4 criterion 3).
static func build_lattice(terrain: Dictionary, parent: Node) -> Lattice:
	var fixture := TerrainFixture.from_terrain(terrain)
	parent.add_child(fixture)
	# Annotated, not inferred: `check_lattice_ports.py` dec. 3 wants a handle fetch
	# to land in a `Lattice`-typed slot, and a `:=` here reads as untyped.
	var lattice: Lattice = fixture.lattice
	return lattice


## Does this map mint any cell above the ground? 45 of the 119 do (ADR-0224 /
## ADR-0219 P3, via `DynamicTerrainBuilder._slot_is_occupied`); the other 74 are
## dec. 8's A/B population.
static func has_upper_cells(lattice: Lattice) -> bool:
	for cell in lattice.all_cells():
		if cell.grid.z != TerrainCell.GROUND_LEVEL:
			return true
	return false


static func read_golden() -> Dictionary:
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {}
	var maps: Variant = parsed.get("maps", {})
	return maps if maps is Dictionary else {}


static func _sha(ints: PackedInt32Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(ints.to_byte_array())
	return ctx.finish().hex_encode()
