extends RefCounted

## Spatial index for visual geometry triangles.
##
## Provides fast queries for triangles by:
## - Tile coordinates (which triangles belong to a tile)
## - Surface type (find all water, walls, etc.)
## - Spatial bounds (rectangular area queries)
## - Edge adjacency (find neighboring triangles)
##
## Stores metadata for each triangle: surface_type, tile_coords, vertex positions.

## Triangle metadata structure
class TriangleData:
	var triangle_index: int  # Index in triangles array
	var primitive_index: int  # Which primitive this triangle belongs to
	var metadata_index: int  # Index in primitive's TriangleMetadata array
	var vertex_indices: Array[int] = []  # 3 vertex indices into global vertex array
	var positions: Array[Vector3] = []  # 3 vertex positions (world space)
	var uvs: Array[Vector2] = []  # 3 vertex UV coordinates (for indexed texture sampling)
	var normals: Array[Vector3] = []  # 3 vertex normals (for lighting)
	var face_centroid: Vector3  # GTE AVSZ4-style centroid (4-vertex avg for quads, 3 for tris)
	var palette_id: int  # Palette ID (0-15) for indexed color rendering
	var surface_type: String  # "Waterway", "StoneFloor", etc.
	var tile_coords: Vector2i  # Grid coordinates (x, z) or (-1, -1) for walls
	var doodad_id: String  # Doodad that owns this triangle (empty for static)
	var deleted: bool = false  # Soft-delete flag (triangles marked deleted are skipped in queries)
	var visible_angles: int = 0  # FFT per-polygon visible-angles bitfield (mesh-resource +0xB0)

	func _init(
		tri_idx: int,
		prim_idx: int,
		meta_idx: int,
		v_indices: Array[int],
		v_positions: Array[Vector3],
		v_uvs: Array[Vector2],
		v_normals: Array[Vector3],
		pal_id: int,
		surf_type: String,
		t_coords: Vector2i,
		d_id: String,
		f_centroid: Vector3 = Vector3.ZERO,
		v_angles: int = 0
	):
		triangle_index = tri_idx
		primitive_index = prim_idx
		metadata_index = meta_idx
		vertex_indices = v_indices
		positions = v_positions
		uvs = v_uvs
		normals = v_normals
		palette_id = pal_id
		surface_type = surf_type
		tile_coords = t_coords
		doodad_id = d_id
		deleted = false
		visible_angles = v_angles
		# Use provided centroid, or compute 3-vertex average as fallback
		if f_centroid == Vector3.ZERO:
			face_centroid = (v_positions[0] + v_positions[1] + v_positions[2]) / 3.0
		else:
			face_centroid = f_centroid


# Triangle storage (linear array for iteration)
var _triangles: Array[TriangleData] = []

# Tile coordinate index: "x,z" -> Array[int] (triangle indices)
var _tile_index: Dictionary = {}

# Surface type index: surface_type -> Array[int] (triangle indices)
var _surface_index: Dictionary = {}

# Edge adjacency index: edge_key -> Array[int] (triangle indices sharing this edge)
# Edge key format: "v0_idx,v1_idx" where v0_idx < v1_idx (canonical ordering)
var _edge_index: Dictionary = {}



## Add a triangle to the index.
##
## Args:
##     primitive_index: Which primitive this triangle belongs to
##     metadata_index: Index in primitive's TriangleMetadata array
##     vertex_indices: Array of 3 vertex indices [v0, v1, v2]
##     v0, v1, v2: Vertex positions in world space
##     uv0, uv1, uv2: UV coordinates for indexed texture sampling
##     n0, n1, n2: Vertex normals for lighting
##     palette_id: Palette ID (0-15) for color lookup
##     surface_type: Surface type string (from TriangleMetadata)
##     tile_coords: Tile coordinates as Vector2i (from TriangleMetadata)
##     doodad_id: Doodad ID (empty string for static maps)
func add_triangle(
	primitive_index: int,
	metadata_index: int,
	vertex_indices: Array[int],
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2,
	n0: Vector3,
	n1: Vector3,
	n2: Vector3,
	palette_id: int,
	surface_type: String,
	tile_coords: Vector2i,
	doodad_id: String = "",
	face_centroid: Vector3 = Vector3.ZERO,
	visible_angles: int = 0
) -> void:
	var triangle_index = _triangles.size()

	# Create triangle data
	var tri_data = TriangleData.new(
		triangle_index,
		primitive_index,
		metadata_index,
		vertex_indices,
		[v0, v1, v2],
		[uv0, uv1, uv2],
		[n0, n1, n2],
		palette_id,
		surface_type,
		tile_coords,
		doodad_id,
		face_centroid,
		visible_angles
	)

	# Store in main array
	_triangles.append(tri_data)

	# Index by tile coordinates
	var tile_key = _make_tile_key(tile_coords.x, tile_coords.y)
	if not _tile_index.has(tile_key):
		_tile_index[tile_key] = []
	_tile_index[tile_key].append(triangle_index)

	# Index by surface type
	if not _surface_index.has(surface_type):
		_surface_index[surface_type] = []
	_surface_index[surface_type].append(triangle_index)

	# Index by edges (for adjacency queries)
	var v0_idx = vertex_indices[0]
	var v1_idx = vertex_indices[1]
	var v2_idx = vertex_indices[2]

	for edge_pair in [[v0_idx, v1_idx], [v1_idx, v2_idx], [v2_idx, v0_idx]]:
		var edge_key = _make_edge_key(edge_pair[0], edge_pair[1])
		if not _edge_index.has(edge_key):
			_edge_index[edge_key] = []
		_edge_index[edge_key].append(triangle_index)



## Get all triangles with a specific surface type.
##
## Args:
##     surface_type: Surface type string (e.g., "Waterway", "StoneFloor")
##
## Returns:
##     Array of TriangleData with this surface type (empty if none, skips deleted)
func get_triangles_by_surface_type(surface_type: String) -> Array[TriangleData]:
	var result: Array[TriangleData] = []

	if _surface_index.has(surface_type):
		for tri_idx in _surface_index[surface_type]:
			var tri_data = _triangles[tri_idx]
			if tri_data != null and not tri_data.deleted:
				result.append(tri_data)

	return result


## Get triangle data by index.
##
## Args:
##     triangle_index: Index in triangles array
##
## Returns:
##     TriangleData or null if out of bounds
func get_triangle(triangle_index: int) -> TriangleData:
	if triangle_index >= 0 and triangle_index < _triangles.size():
		return _triangles[triangle_index]
	return null


## Get total number of triangles in index (including deleted).
##
## Returns:
##     Total triangle count (including soft-deleted triangles)
func get_triangle_count() -> int:
	return _triangles.size()


## Get number of active (non-deleted) triangles.
##
## Returns:
##     Count of triangles not marked as deleted
func get_active_triangle_count() -> int:
	var count = 0
	for tri_data in _triangles:
		if tri_data != null and not tri_data.deleted:
			count += 1
	return count


## Get all surface types present in the index.
##
## Returns:
##     Array of surface type strings
func get_surface_types() -> Array[String]:
	var result: Array[String] = []
	result.assign(_surface_index.keys())
	return result


## Soft-delete a triangle (mark as deleted, don't remove from indices).
##
## Args:
##     triangle_index: Index of triangle to soft-delete
##
## Returns:
##     true if marked deleted, false if not found or already deleted
func soft_delete_triangle(triangle_index: int) -> bool:
	if triangle_index < 0 or triangle_index >= _triangles.size():
		return false

	var tri_data = _triangles[triangle_index]
	if tri_data == null or tri_data.deleted:
		return false

	tri_data.deleted = true
	return true


## Soft-delete all triangles in a rectangular bounds.
##
## Args:
##     bounds: Rect2i defining the area (position and size in tile coordinates)
##
## Returns:
##     Array of triangle indices that were deleted
func soft_delete_triangles_in_bounds(bounds: Rect2i) -> Array[int]:
	var min_x = bounds.position.x
	var min_z = bounds.position.y
	var max_x = bounds.position.x + bounds.size.x - 1
	var max_z = bounds.position.y + bounds.size.y - 1

	var deleted_indices: Array[int] = []
	var seen: Dictionary = {}

	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var tile_key = _make_tile_key(x, z)
			if _tile_index.has(tile_key):
				for tri_idx in _tile_index[tile_key]:
					if not seen.has(tri_idx):
						if soft_delete_triangle(tri_idx):
							deleted_indices.append(tri_idx)
						seen[tri_idx] = true

	return deleted_indices


## Get triangle indices sharing the edge defined by two vertex indices.
##
## Returns an empty array if the edge is not in the index. Callers can treat
## size <= 1 as "boundary" (no opposing triangle).
func get_triangles_on_edge(v0_idx: int, v1_idx: int) -> Array:
	var edge_key = _make_edge_key(v0_idx, v1_idx)
	if not _edge_index.has(edge_key):
		return []
	return _edge_index[edge_key]


## Clear all triangles from the index.
func clear() -> void:
	_triangles.clear()
	_tile_index.clear()
	_surface_index.clear()
	_edge_index.clear()


# Helper: Create tile key from coordinates
func _make_tile_key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]


# Helper: Create edge key from two vertex indices (canonical ordering)
func _make_edge_key(v0: int, v1: int) -> String:
	# Use canonical ordering: smaller index first
	if v0 < v1:
		return "%d,%d" % [v0, v1]
	else:
		return "%d,%d" % [v1, v0]
