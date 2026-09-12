extends RefCounted

## Generates skirt geometry for water and land boundaries.
##
## Skirts fill visual gaps at terrain boundaries:
## - Water skirts: Vertical quads extending downward at water edges
## - Land skirts: Mirrored triangles or drop quads at land-water boundaries
##
## This class is a helper for DynamicGeometryBuilder, extracting the ~450 lines
## of skirt-specific logic into a focused, testable unit.

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const TunePort = ExMateriaPlatform.TunePort

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const SkirtConfig = preload("res://addons/exmateria_battlefield/terrain/SkirtConfig.gd")
const VisualGeometryIndex = preload("res://addons/exmateria_battlefield/terrain/VisualGeometryIndex.gd")


const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")

# --- the land-skirt verbosity gate, owned HERE ---------------------------------
# ADR-0140 dec. 5: *a system logs itself; there is no inter-system logging.* This
# gate is read on 10 lines and all ten are in this file, so `Battlefield` reaching
# `Debug` for it was the gate living outside the class that prints through it. The
# home is now the production owner, as ADR-0068 requires of any tunable, on the
# system's own `skirt.*` namespace. Second instance of dec. 5, after
# `ExMateriaEffectSfx.audio_monitor_enabled` (#408) — same shape.
#
# The two `map_debug_enabled` gates left in this file are NOT the same case and are
# deliberately untouched: that flag is one of dec. 5's three SHARED gates (25 refs
# here, 9 in `Battle`, 1 in `Debug`), and dec. 5 SPLITS those rather than relocating
# them. Relocating a shared gate would point two more systems at this one.
#
# The read is a PULL rather than an `on_update` push because this class is a
# `RefCounted` rebuilt per map compose: there is no stable instance to hold a
# subscription. The old getter pulled through `Tune.get_value` too, so the cost is
# unchanged — one registry lookup less, in fact, since it also re-checked
# `is_registered` on every gate.
const LAND_SKIRT_DEBUG_SLUG := "skirt.land_debug"
static var LAND_SKIRT_DEBUG_DEFAULT := false


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Static so `_static_init` can call it at class load — the only thing that runs this bind —
## and so the ADR-0173 guards can call it to read back which slugs this owner binds.
static func register_tunables() -> void:
	TunePort.bind(LAND_SKIRT_DEBUG_SLUG, LAND_SKIRT_DEBUG_DEFAULT)


## The gate. Reads the coalesced override live, so a scrub in the Skirt panel or
## the generated dashboard reaches the next rebuild without a restart.
static func land_skirt_debug() -> bool:
	if Engine.is_editor_hint():
		return LAND_SKIRT_DEBUG_DEFAULT
	return TunePort.get_value(LAND_SKIRT_DEBUG_SLUG, LAND_SKIRT_DEBUG_DEFAULT)

# Dependencies (set via initialize)
var _visual_index: VisualGeometryIndex
var _vertex_adder: Callable  # Reference to DynamicGeometryBuilder._add_vertex
var _map_bounds: Rect2i

# Track generated triangle indices for clearing before regeneration
var _generated_indices: Array[int] = []

# Role of a sibling triangle's vertex against the primary's water-edge frame.
# Used by _find_sibling_triangle to pre-classify the sibling so _add_sibling_skirt_mirror
# doesn't re-derive it.
enum _SiblingRole { WATER_V0, WATER_V1, PRIMARY_V2, OTHER }


## Initialize the generator with required dependencies.
##
## Args:
##     visual_index: The VisualGeometryIndex for triangle operations
##     vertex_adder: Callable that adds a vertex and returns its index (for deduplication)
##     map_bounds: Rect2i defining the map boundaries in tile coordinates
func initialize(visual_index: VisualGeometryIndex, vertex_adder: Callable, map_bounds: Rect2i) -> void:
	_visual_index = visual_index
	_vertex_adder = vertex_adder
	_map_bounds = map_bounds


## Update map bounds (called when map changes).
func set_map_bounds(bounds: Rect2i) -> void:
	_map_bounds = bounds


## Clear all previously generated skirt triangles.
## Call this before regenerating skirts.
func clear_skirts() -> void:
	for idx in _generated_indices:
		var tri = _visual_index.get_triangle(idx)
		if tri:
			tri.deleted = true
	_generated_indices.clear()


## Generate all skirt types.
## Returns the array of generated triangle indices.
func generate_all_skirts() -> Array[int]:
	clear_skirts()
	_generate_water_skirts()
	_generate_land_skirts()
	return _generated_indices


## Generate vertical skirt geometry ONLY for water boundary edges.
## Boundary = edge where water meets non-water or void.
func _generate_water_skirts() -> void:
	if not SkirtConfig.water_skirt_enabled:
		return

	var skirt_count = 0
	var start_tri_count = _visual_index.get_triangle_count()

	for surface_type in MapConstants.WATER_SURFACES:
		var triangles = _visual_index.get_triangles_by_surface_type(surface_type)

		for tri in triangles:
			if tri.deleted:
				continue

			# Check each of the 3 edges for boundary condition
			for edge_idx in range(3):
				if _is_water_boundary_edge(tri, edge_idx):
					var v0 = tri.positions[edge_idx]
					var v1 = tri.positions[(edge_idx + 1) % 3]
					var v2 = tri.positions[(edge_idx + 2) % 3]  # Third vertex (for inset direction)

					_add_water_skirt_quad(v0, v1, v2, tri)
					skirt_count += 1

	# Track added skirt triangles (each quad = 2 triangles)
	var end_tri_count = _visual_index.get_triangle_count()
	for i in range(start_tri_count, end_tri_count):
		_generated_indices.append(i)



## Check if an edge of a water triangle is a boundary (water meets non-water or void).
## Returns false if edge borders MapConstants.SURFACE_UNTEXTURED geometry (existing map border).
func _is_water_boundary_edge(tri: VisualGeometryIndex.TriangleData, edge_idx: int) -> bool:
	var v_indices = tri.vertex_indices
	var triangles_on_edge = _visual_index.get_triangles_on_edge(
		v_indices[edge_idx], v_indices[(edge_idx + 1) % 3]
	)

	# Edge with no opposing triangle = boundary (to void).
	if triangles_on_edge.size() <= 1:
		return true

	# Check if any neighbor is non-water (but not Untextured - that's existing border geometry)
	for neighbor_idx in triangles_on_edge:
		if neighbor_idx != tri.triangle_index:
			var neighbor = _visual_index.get_triangle(neighbor_idx)
			if neighbor and not neighbor.deleted:
				# Skip edges bordering Untextured - existing border geometry covers this
				if neighbor.surface_type == MapConstants.SURFACE_UNTEXTURED:
					return false
				if neighbor.surface_type not in MapConstants.WATER_SURFACES:
					return true  # Neighbor is non-water = boundary

	return false  # All neighbors are water = interior edge


## Add a skirt quad extending downward from a water boundary edge.
## v0, v1 = edge vertices, v2 = third vertex of triangle (for inset direction)
func _add_water_skirt_quad(v0: Vector3, v1: Vector3, v2: Vector3, source_tri: VisualGeometryIndex.TriangleData) -> void:
	var depth = SkirtConfig.water_skirt_depth
	var inset = SkirtConfig.water_skirt_inset

	# Calculate inset direction perpendicular to edge, pointing toward interior
	var edge_dir = _get_edge_direction(v0, v1)
	var perpendicular = _get_perpendicular_xz(edge_dir)
	var edge_center = (v0 + v1) / 2.0
	var inset_dir = _orient_perpendicular_toward(perpendicular, edge_center, v2)

	# Inset top vertices slightly
	var v0_top = v0 + inset_dir * inset
	var v1_top = v1 + inset_dir * inset
	# Floor at Y=0 so the skirt can never poke below the map's side-wall geometry
	# (visible when the camera angles toward a side face).
	var v0_bottom = Vector3(v0_top.x, maxf(v0_top.y - depth, 0.0), v0_top.z)
	var v1_bottom = Vector3(v1_top.x, maxf(v1_top.y - depth, 0.0), v1_top.z)

	# Skip if entirely degenerate (both edge vertices already at or below the floor).
	if v0_top.y <= 0.0 and v1_top.y <= 0.0:
		return

	# Use center UV of source triangle (solid color)
	var center_uv = (source_tri.uvs[0] + source_tri.uvs[1] + source_tri.uvs[2]) / 3.0

	# Calculate outward-facing normal (perpendicular to edge in XZ plane)
	var normal = _get_perpendicular_xz(edge_dir)

	# Add vertices to global array
	var v0t_idx = _vertex_adder.call(v0_top)
	var v1t_idx = _vertex_adder.call(v1_top)
	var v0b_idx = _vertex_adder.call(v0_bottom)
	var v1b_idx = _vertex_adder.call(v1_bottom)

	# Triangle 1: v0_top -> v1_top -> v1_bottom
	_visual_index.add_triangle(
		-1, -1,
		[v0t_idx, v1t_idx, v1b_idx],
		v0_top, v1_top, v1_bottom,
		center_uv, center_uv, center_uv,
		normal, normal, normal,
		source_tri.palette_id,
		source_tri.surface_type,
		source_tri.tile_coords,
		""
	)

	# Triangle 2: v0_top -> v1_bottom -> v0_bottom
	_visual_index.add_triangle(
		-1, -1,
		[v0t_idx, v1b_idx, v0b_idx],
		v0_top, v1_bottom, v0_bottom,
		center_uv, center_uv, center_uv,
		normal, normal, normal,
		source_tri.palette_id,
		source_tri.surface_type,
		source_tri.tile_coords,
		""
	)


## Generate mirrored geometry for land edges that border water.
## Mirrors the original triangle across the water-boundary edge for seamless texture continuation.
func _generate_land_skirts() -> void:
	if not SkirtConfig.land_skirt_enabled:
		return

	# Debug: Log map bounds at start
	if land_skirt_debug():
		print("=== LAND SKIRT GENERATION ===")
		print("Map bounds (tile coords): %s" % _map_bounds)
		print("World bounds: min_x=%s, max_x=%s, min_z=%s, max_z=%s" % [
			_map_bounds.position.x,
			_map_bounds.position.x + _map_bounds.size.x,
			_map_bounds.position.y,
			_map_bounds.position.y + _map_bounds.size.y
		])

	var skirt_count = 0
	var start_tri_count = _visual_index.get_triangle_count()

	# Get all surface types that are NOT water
	var surface_types = _visual_index.get_surface_types()

	for surface_type in surface_types:
		if surface_type in MapConstants.WATER_SURFACES:
			continue  # Skip water surfaces
		if surface_type == MapConstants.SURFACE_UNTEXTURED:
			continue  # Skip black border polygons

		var triangles = _visual_index.get_triangles_by_surface_type(surface_type)

		for tri in triangles:
			if tri.deleted:
				continue

			# Check each edge for water boundary
			for edge_idx in range(3):
				var water_neighbor = _get_water_neighbor(tri, edge_idx)
				if water_neighbor:
					var v0 = tri.positions[edge_idx]
					var v1 = tri.positions[(edge_idx + 1) % 3]

					# Skip edges at map boundary (don't create skirts at map edges)
					var boundary_info = _is_edge_at_map_boundary(v0, v1)
					if boundary_info.at_min_x or boundary_info.at_max_x or boundary_info.at_min_z or boundary_info.at_max_z:
						if land_skirt_debug():
							print("=== SKIPPING LAND SKIRT AT MAP BOUNDARY ===")
							print("  Edge: v0=%s, v1=%s" % [v0, v1])
							print("  Boundary info: %s" % boundary_info)
						continue

					# Debug: Print tile info for all water boundaries
					if land_skirt_debug():
						print("=== LAND-WATER BOUNDARY at tile %s ===" % tri.tile_coords)
						print("  Land tri: surface=%s, positions=%s" % [tri.surface_type, tri.positions])
						print("  Water tri: surface=%s, positions=%s" % [water_neighbor.surface_type, water_neighbor.positions])
						print("  Edge idx=%d: v0=%s, v1=%s" % [edge_idx, v0, v1])

					# Check if this is a head-on boundary (cliff) or sloped boundary
					var is_head_on = _is_head_on_boundary(tri, edge_idx, water_neighbor)
					if land_skirt_debug():
						print("  -> is_head_on: %s" % is_head_on)

					if is_head_on:
						# Head-on cliff: use vertical drop skirt
						# No sibling needed - the quad covers the full edge
						_add_land_drop_skirt(tri, edge_idx, water_neighbor)
						skirt_count += 1
					else:
						# Sloped boundary: use existing mirror logic
						var primary_mirror_verts = _add_land_skirt_mirror(tri, edge_idx)
						if primary_mirror_verts.is_empty():
							continue  # Degenerate triangle, skip
						skirt_count += 1

						# Find and mirror sibling triangle (other half of quad).
						# Finder pre-classifies which slot of the sibling holds which
						# role against the primary's vertex frame; the mirror function
						# consumes the classification rather than re-deriving it.
						var sibling_match = _find_sibling_triangle(tri, edge_idx)
						if not sibling_match.is_empty():
							_add_sibling_skirt_mirror(sibling_match, primary_mirror_verts)
							skirt_count += 1

	# Track added skirt triangles (mirrored geometry = 1 triangle per edge)
	var end_tri_count = _visual_index.get_triangle_count()
	for i in range(start_tri_count, end_tri_count):
		_generated_indices.append(i)



## Check if a triangle is at the map boundary (any edge borders void or Untextured).
func _is_triangle_at_map_boundary(tri: VisualGeometryIndex.TriangleData) -> bool:
	var v_indices = tri.vertex_indices
	for edge_idx in range(3):
		var triangles_on_edge = _visual_index.get_triangles_on_edge(
			v_indices[edge_idx], v_indices[(edge_idx + 1) % 3]
		)

		# Size <= 1 means no opposing triangle = borders void.
		if triangles_on_edge.size() <= 1:
			return true

		# Edge borders existing Untextured map-border geometry.
		for neighbor_idx in triangles_on_edge:
			if neighbor_idx != tri.triangle_index:
				var neighbor = _visual_index.get_triangle(neighbor_idx)
				if neighbor and not neighbor.deleted and neighbor.surface_type == MapConstants.SURFACE_UNTEXTURED:
					return true

	return false


## Check if an edge of a land triangle borders water. Returns the water triangle if found.
## Returns null if edge borders void, Untextured geometry (map border), or non-water surfaces.
## Also returns null if the water neighbor is at the map boundary.
func _get_water_neighbor(tri: VisualGeometryIndex.TriangleData, edge_idx: int) -> VisualGeometryIndex.TriangleData:
	var v_indices = tri.vertex_indices
	var triangles_on_edge = _visual_index.get_triangles_on_edge(
		v_indices[edge_idx], v_indices[(edge_idx + 1) % 3]
	)
	if triangles_on_edge.is_empty():
		return null  # No neighbor = map edge, not water boundary

	# Check neighbors - skip if any is Untextured (existing border geometry)
	var water_neighbor: VisualGeometryIndex.TriangleData = null
	for neighbor_idx in triangles_on_edge:
		if neighbor_idx != tri.triangle_index:
			var neighbor = _visual_index.get_triangle(neighbor_idx)
			if neighbor and not neighbor.deleted:
				# If any neighbor is Untextured, don't generate land skirt
				# (existing border geometry already covers this edge)
				if neighbor.surface_type == MapConstants.SURFACE_UNTEXTURED:
					return null
				if neighbor.surface_type in MapConstants.WATER_SURFACES:
					water_neighbor = neighbor

	# Don't generate land skirt if the water is at the map boundary
	if water_neighbor and _is_triangle_at_map_boundary(water_neighbor):
		if land_skirt_debug():
			print("=== SKIPPING: WATER NEIGHBOR AT MAP BOUNDARY ===")
			print("  water tile_coords: %s" % water_neighbor.tile_coords)
		return null

	return water_neighbor


## Check if a land-water boundary is "head-on" (cliff/wall) vs sloped.
## Head-on boundaries need vertical drop skirts instead of mirrored geometry.
##
## Detection criteria:
## 1. Land edge is significantly HIGHER than water surface
## 2. AND the land is NOT sloping down toward the edge (third vertex at same level as edge)
func _is_head_on_boundary(land_tri: VisualGeometryIndex.TriangleData, edge_idx: int, _water_tri: VisualGeometryIndex.TriangleData) -> bool:
	var v0 = land_tri.positions[edge_idx]
	var v1 = land_tri.positions[(edge_idx + 1) % 3]
	var v2 = land_tri.positions[(edge_idx + 2) % 3]

	# Get the minimum Y of the water edge (land's boundary)
	var edge_min_y = minf(v0.y, v1.y)

	# Check if land is sloping down toward the edge
	# If v2 (third vertex) is significantly higher than the edge, the land slopes down
	# toward water - in that case, mirrored geometry extends downward and works well
	var v2_above_edge = v2.y - edge_min_y

	# Debug: Always print the computed values
	if land_skirt_debug():
		print("  _is_head_on_boundary check:")
		print("    v0=%s, v1=%s, v2=%s" % [v0, v1, v2])
		print("    edge_min_y=%.4f, v2.y=%.4f" % [edge_min_y, v2.y])
		print("    v2_above_edge=%.4f (tolerance=%.4f)" % [v2_above_edge, SkirtConfig.head_on_slope_tolerance])

	# If v2 is significantly above the edge, land slopes down toward water
	# Mirror geometry will extend downward, which works well
	if v2_above_edge > SkirtConfig.head_on_slope_tolerance:
		if land_skirt_debug():
			print("    -> SLOPED: v2 is %.4f above edge, using mirror" % v2_above_edge)
		return false  # Sloped - use mirror

	# Land is flat or nearly flat at the water edge
	# Mirror would create horizontal geometry that z-fights with water
	# Use vertical drop skirt instead
	if land_skirt_debug():
		print("    -> FLAT: v2 is only %.4f above edge, using drop skirt" % v2_above_edge)

	return true


## Add a vertical drop skirt for head-on land-water boundaries.
## Creates a vertical quad extending from the land edge down below the water surface.
func _add_land_drop_skirt(land_tri: VisualGeometryIndex.TriangleData, edge_idx: int, water_tri: VisualGeometryIndex.TriangleData) -> void:
	var v0 = land_tri.positions[edge_idx]
	var v1 = land_tri.positions[(edge_idx + 1) % 3]
	var v2 = land_tri.positions[(edge_idx + 2) % 3]

	# Calculate drop target (below water surface), floored at Y=0 so the skirt
	# never extends below the map's side-wall geometry.
	var water_avg_y = (water_tri.positions[0].y + water_tri.positions[1].y + water_tri.positions[2].y) / 3.0
	var drop_target_y = maxf(water_avg_y - SkirtConfig.head_on_drop_depth, 0.0)

	# Skip if the drop quad would be zero-height (edge already at or below floor).
	if drop_target_y >= minf(v0.y, v1.y):
		return

	# Calculate inset direction (perpendicular to edge, pointing toward land interior)
	var edge_dir = _get_edge_direction(v0, v1)
	var perpendicular = _get_perpendicular_xz(edge_dir)
	var edge_center = (v0 + v1) / 2.0
	perpendicular = _orient_perpendicular_toward(perpendicular, edge_center, v2)

	# Top vertices (at land edge, slightly inset toward interior)
	var v0_top = v0 + perpendicular * SkirtConfig.head_on_inset
	var v1_top = v1 + perpendicular * SkirtConfig.head_on_inset

	# Bottom vertices (same XZ, dropped below water)
	var v0_bottom = Vector3(v0_top.x, drop_target_y, v0_top.z)
	var v1_bottom = Vector3(v1_top.x, drop_target_y, v1_top.z)

	# Normal points outward (away from land interior)
	var normal = -perpendicular

	# Use center UV of source triangle (solid color)
	var center_uv = (land_tri.uvs[0] + land_tri.uvs[1] + land_tri.uvs[2]) / 3.0

	# Add vertices to global array
	var v0t_idx = _vertex_adder.call(v0_top)
	var v1t_idx = _vertex_adder.call(v1_top)
	var v0b_idx = _vertex_adder.call(v0_bottom)
	var v1b_idx = _vertex_adder.call(v1_bottom)

	# Add quad as 2 triangles
	# Winding order must be CCW when viewed from the normal direction (toward water)
	# The normal points away from land (-perpendicular), so we view from that side
	# Triangle 1: v0_top -> v1_bottom -> v1_top (covers upper-left half of quad)
	_visual_index.add_triangle(
		-1, -1,
		[v0t_idx, v1b_idx, v1t_idx],
		v0_top, v1_bottom, v1_top,
		center_uv, center_uv, center_uv,
		normal, normal, normal,
		land_tri.palette_id,
		land_tri.surface_type,
		land_tri.tile_coords,
		""
	)

	# Triangle 2: v0_top -> v0_bottom -> v1_bottom (covers lower-right half of quad)
	_visual_index.add_triangle(
		-1, -1,
		[v0t_idx, v0b_idx, v1b_idx],
		v0_top, v0_bottom, v1_bottom,
		center_uv, center_uv, center_uv,
		normal, normal, normal,
		land_tri.palette_id,
		land_tri.surface_type,
		land_tri.tile_coords,
		""
	)

	if land_skirt_debug():
		print("=== DROP SKIRT CREATED ===")
		print("  Top edge: %s -> %s" % [v0_top, v1_top])
		print("  Bottom edge: %s -> %s" % [v0_bottom, v1_bottom])
		print("  Drop depth: %.3f (water_y=%.3f, target_y=%.3f)" % [SkirtConfig.head_on_drop_depth, water_avg_y, drop_target_y])


## Add a mirrored triangle extending from a land edge that borders water.
## Mirrors the source triangle across the water-boundary edge, preserving UVs.
##
## Returns: Dictionary with the EXACT mirrored vertex positions for sibling to use:
##   { "water_v0": Vector3, "water_v1": Vector3, "v2_mirrored": Vector3 }
##   Returns empty dictionary if triangle is degenerate.
func _add_land_skirt_mirror(source_tri: VisualGeometryIndex.TriangleData, edge_idx: int) -> Dictionary:
	# Get edge vertices and the third vertex to mirror
	var v0 = source_tri.positions[edge_idx]
	var v1 = source_tri.positions[(edge_idx + 1) % 3]
	var v2 = source_tri.positions[(edge_idx + 2) % 3]

	# Get corresponding UVs
	var uv0 = source_tri.uvs[edge_idx]
	var uv1 = source_tri.uvs[(edge_idx + 1) % 3]
	var uv2 = source_tri.uvs[(edge_idx + 2) % 3]

	# Get corresponding normals
	var n0 = source_tri.normals[edge_idx]
	var n1 = source_tri.normals[(edge_idx + 1) % 3]
	var n2 = source_tri.normals[(edge_idx + 2) % 3]

	# Mirror v2 across the edge line (v0-v1).
	# Floor mirrored Y at 0 so a tall land triangle can't push the skirt below
	# the map's side-wall geometry. The clamped position propagates to the
	# sibling via the returned dict, keeping the diagonal seam seamless.
	var edge_dir = _get_edge_direction(v0, v1)
	var v2_mirror = _mirror_point_across_edge(v2, v0, edge_dir)
	v2_mirror.y = maxf(v2_mirror.y, 0.0)

	# Skip degenerate triangles (mirrored vertex too close to edge)
	# Calculate projection point for distance check
	var v2_to_v0 = v2 - v0
	var projection_length = v2_to_v0.dot(edge_dir)
	var projection_point = v0 + edge_dir * projection_length
	var mirror_dist = v2_mirror.distance_to(projection_point)
	if mirror_dist < 0.001:
		return {}

	# Mirror the normal for v2 as well (reflect across edge plane)
	var n2_mirror = _mirror_normal_across_edge(n2, edge_dir)

	# Add vertices to global array
	var v0_idx = _vertex_adder.call(v0)
	var v1_idx = _vertex_adder.call(v1)
	var v2_mirror_idx = _vertex_adder.call(v2_mirror)

	# Add mirrored triangle with reversed winding order
	# Original: v0 -> v1 -> v2 (counter-clockwise when viewed from front)
	# Mirrored: v0 -> v2_mirror -> v1 (maintains CCW when viewed from the other side)
	_visual_index.add_triangle(
		-1, -1,
		[v0_idx, v2_mirror_idx, v1_idx],
		v0, v2_mirror, v1,
		uv0, uv2, uv1,  # Same UVs in mirrored order
		n0, n2_mirror, n1,  # Normals with v2's mirrored
		source_tri.palette_id,
		source_tri.surface_type,
		source_tri.tile_coords,
		""
	)

	if land_skirt_debug():
		print("=== PRIMARY MIRROR CREATED ===")
		print("  Triangle vertices (in order): [%s, %s, %s]" % [v0, v2_mirror, v1])
		print("  Edges: %s->%s, %s->%s, %s->%s" % [v0, v2_mirror, v2_mirror, v1, v1, v0])

	# Return the EXACT positions used for the mirrored primary triangle
	# The sibling MUST use these exact same positions for shared vertices
	return {
		"water_v0": v0,
		"water_v1": v1,
		"primary_v2": v2,
		"v2_mirrored": v2_mirror,
		"edge_dir": edge_dir
	}


## Find the sibling triangle that shares a non-water edge with the primary triangle.
## The sibling is the other half of a quad, sharing the diagonal edge.
## Find the sibling triangle that shares a non-water edge with the primary.
## Returns a dict { "triangle": TriangleData, "roles": Array[int] } where
## `roles[i]` is the `_SiblingRole` of `triangle.positions[i]` against the
## primary's water-edge frame, or {} if no valid sibling exists.
func _find_sibling_triangle(primary_tri: VisualGeometryIndex.TriangleData, water_edge_idx: int) -> Dictionary:
	var water_v0 = primary_tri.positions[water_edge_idx]
	var water_v1 = primary_tri.positions[(water_edge_idx + 1) % 3]
	var primary_v2 = primary_tri.positions[(water_edge_idx + 2) % 3]
	var tolerance = 0.01

	# Tile bounds — sibling's "other" vertex must lie within this XZ box to
	# guarantee it's the other half of the SAME tile and not a neighbor tile.
	var min_x = minf(minf(water_v0.x, water_v1.x), primary_v2.x) - tolerance
	var max_x = maxf(maxf(water_v0.x, water_v1.x), primary_v2.x) + tolerance
	var min_z = minf(minf(water_v0.z, water_v1.z), primary_v2.z) - tolerance
	var max_z = maxf(maxf(water_v0.z, water_v1.z), primary_v2.z) + tolerance

	# Walk the two non-water edges looking for a sibling on the other side.
	for non_water_offset in [1, 2]:
		var actual_idx = (water_edge_idx + non_water_offset) % 3
		var ev0_idx = primary_tri.vertex_indices[actual_idx]
		var ev1_idx = primary_tri.vertex_indices[(actual_idx + 1) % 3]

		for neighbor_idx in _visual_index.get_triangles_on_edge(ev0_idx, ev1_idx):
			if neighbor_idx == primary_tri.triangle_index:
				continue

			var neighbor = _visual_index.get_triangle(neighbor_idx)
			if not neighbor or neighbor.deleted:
				continue
			if neighbor.surface_type in MapConstants.WATER_SURFACES:
				continue
			if neighbor.surface_type == MapConstants.SURFACE_UNTEXTURED:
				continue

			var roles = _classify_sibling_vertices(neighbor, water_v0, water_v1, primary_v2, tolerance)
			if roles.is_empty():
				continue  # Not a 1+1+1 sibling shape.

			# Reject siblings whose "other" vertex sits outside the primary tile.
			var other_slot = roles.find(_SiblingRole.OTHER)
			var other_pos = neighbor.positions[other_slot]
			var in_bounds = (other_pos.x >= min_x and other_pos.x <= max_x and
							 other_pos.z >= min_z and other_pos.z <= max_z)
			if not in_bounds:
				continue

			return {"triangle": neighbor, "roles": roles}

	return {}


## Classify a candidate sibling's three vertices against the primary's frame.
## Returns an Array[int] of size 3 with `_SiblingRole` per slot, or [] if the
## triangle isn't a valid sibling (must have exactly one water-endpoint slot,
## one shared-diagonal slot, and one "other" slot).
func _classify_sibling_vertices(neighbor: VisualGeometryIndex.TriangleData, water_v0: Vector3, water_v1: Vector3, primary_v2: Vector3, tolerance: float) -> Array[int]:
	var roles: Array[int] = [_SiblingRole.OTHER, _SiblingRole.OTHER, _SiblingRole.OTHER]
	var water_count = 0
	var diagonal_count = 0
	var other_count = 0

	for i in range(3):
		var pos = neighbor.positions[i]
		if pos.distance_to(water_v0) < tolerance:
			roles[i] = _SiblingRole.WATER_V0
			water_count += 1
		elif pos.distance_to(water_v1) < tolerance:
			roles[i] = _SiblingRole.WATER_V1
			water_count += 1
		elif pos.distance_to(primary_v2) < tolerance:
			roles[i] = _SiblingRole.PRIMARY_V2
			diagonal_count += 1
		else:
			roles[i] = _SiblingRole.OTHER
			other_count += 1

	if water_count != 1 or diagonal_count != 1 or other_count != 1:
		return []
	return roles


## Add a mirrored sibling triangle, mirroring across the primary triangle's
## water edge. The finder pre-classifies each sibling slot's role; this
## function copies shared positions verbatim from the primary's mirror dict
## so the diagonal seam between the two mirrored triangles is bit-identical.
func _add_sibling_skirt_mirror(sibling_match: Dictionary, primary_mirror_verts: Dictionary) -> void:
	var sibling_tri: VisualGeometryIndex.TriangleData = sibling_match["triangle"]
	var roles: Array[int] = sibling_match["roles"]

	var water_v0: Vector3 = primary_mirror_verts["water_v0"]
	var water_v1: Vector3 = primary_mirror_verts["water_v1"]
	var primary_v2_mirrored: Vector3 = primary_mirror_verts["v2_mirrored"]
	var edge_dir: Vector3 = primary_mirror_verts["edge_dir"]

	var mirrored_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var mirrored_uvs: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var mirrored_normals: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var water_idx = -1
	var p2m_idx = -1
	var has_water_v0 = false
	var has_water_v1 = false

	for i in range(3):
		mirrored_uvs[i] = sibling_tri.uvs[i]
		var normal = sibling_tri.normals[i]
		match roles[i]:
			_SiblingRole.WATER_V0:
				mirrored_positions[i] = water_v0
				mirrored_normals[i] = normal
				water_idx = i
				has_water_v0 = true
			_SiblingRole.WATER_V1:
				mirrored_positions[i] = water_v1
				mirrored_normals[i] = normal
				water_idx = i
				has_water_v1 = true
			_SiblingRole.PRIMARY_V2:
				mirrored_positions[i] = primary_v2_mirrored
				mirrored_normals[i] = _mirror_normal_across_edge(normal, edge_dir)
				p2m_idx = i
			_:
				# OTHER: independently mirror, floored at Y=0 (see _add_land_skirt_mirror).
				var mirrored_pos = _mirror_point_across_edge(sibling_tri.positions[i], water_v0, edge_dir)
				mirrored_pos.y = maxf(mirrored_pos.y, 0.0)
				mirrored_positions[i] = mirrored_pos
				mirrored_normals[i] = _mirror_normal_across_edge(normal, edge_dir)

	# Skip degenerate triangles (mirrored vertex collapsed onto edge).
	var edge1 = mirrored_positions[1] - mirrored_positions[0]
	var edge2 = mirrored_positions[2] - mirrored_positions[0]
	if edge1.cross(edge2).length() < 0.001:
		return

	# Winding flip: mirroring across the water edge reflects the source triangle,
	# which inverts its CCW winding. We restore CCW (as viewed from the camera-
	# facing side, i.e. away from where the original triangle pointed) by checking
	# the modular order of the two slots that pair with the primary's diagonal:
	#   - if our shared water vertex is water_v0, slot order water_v0 → primary_v2
	#     must be water_idx == (p2m_idx + 1) % 3 for CCW;
	#   - if it's water_v1, the order primary_v2 → water_v1 must be
	#     p2m_idx == (water_idx + 1) % 3 for CCW.
	# Either inequality means the natural slot order is CW and we swap slots 1↔2.
	var needs_flip = false
	if has_water_v0:
		needs_flip = water_idx != (p2m_idx + 1) % 3
	elif has_water_v1:
		needs_flip = p2m_idx != (water_idx + 1) % 3

	var v0_global_idx = _vertex_adder.call(mirrored_positions[0])
	var v1_global_idx = _vertex_adder.call(mirrored_positions[1])
	var v2_global_idx = _vertex_adder.call(mirrored_positions[2])

	if needs_flip:
		_visual_index.add_triangle(
			-1, -1,
			[v0_global_idx, v2_global_idx, v1_global_idx],
			mirrored_positions[0], mirrored_positions[2], mirrored_positions[1],
			mirrored_uvs[0], mirrored_uvs[2], mirrored_uvs[1],
			mirrored_normals[0], mirrored_normals[2], mirrored_normals[1],
			sibling_tri.palette_id,
			sibling_tri.surface_type,
			sibling_tri.tile_coords,
			""
		)
	else:
		_visual_index.add_triangle(
			-1, -1,
			[v0_global_idx, v1_global_idx, v2_global_idx],
			mirrored_positions[0], mirrored_positions[1], mirrored_positions[2],
			mirrored_uvs[0], mirrored_uvs[1], mirrored_uvs[2],
			mirrored_normals[0], mirrored_normals[1], mirrored_normals[2],
			sibling_tri.palette_id,
			sibling_tri.surface_type,
			sibling_tri.tile_coords,
			""
		)


## Check if an edge is at the map boundary based on world-space position.
## Returns a dictionary with information about which boundary the edge is at.
func _is_edge_at_map_boundary(v0: Vector3, v1: Vector3) -> Dictionary:
	var edge_dir = (v1 - v0).normalized()
	var threshold = 0.1

	var result = {
		"parallel_to_x": abs(edge_dir.z) < threshold,
		"parallel_to_z": abs(edge_dir.x) < threshold,
		"at_min_x": false,
		"at_max_x": false,
		"at_min_z": false,
		"at_max_z": false
	}

	# Map bounds are in tile coordinates; world space uses 1:1 mapping (tile coord = world x/z)
	var world_min_x = float(_map_bounds.position.x)
	var world_max_x = float(_map_bounds.position.x + _map_bounds.size.x)
	var world_min_z = float(_map_bounds.position.y)
	var world_max_z = float(_map_bounds.position.y + _map_bounds.size.y)

	var pos_threshold = 0.1

	# Edge runs north-south (parallel to Z axis), check X position
	if result.parallel_to_z:
		if abs(v0.x - world_min_x) < pos_threshold and abs(v1.x - world_min_x) < pos_threshold:
			result.at_min_x = true
		if abs(v0.x - world_max_x) < pos_threshold and abs(v1.x - world_max_x) < pos_threshold:
			result.at_max_x = true

	# Edge runs east-west (parallel to X axis), check Z position
	if result.parallel_to_x:
		if abs(v0.z - world_min_z) < pos_threshold and abs(v1.z - world_min_z) < pos_threshold:
			result.at_min_z = true
		if abs(v0.z - world_max_z) < pos_threshold and abs(v1.z - world_max_z) < pos_threshold:
			result.at_max_z = true

	return result


# --- Geometry helper functions (inlined from GeometryHelpers) ---

func _get_edge_direction(v0: Vector3, v1: Vector3) -> Vector3:
	return (v1 - v0).normalized()


func _get_perpendicular_xz(edge_dir: Vector3) -> Vector3:
	return Vector3(-edge_dir.z, 0, edge_dir.x)


func _orient_perpendicular_toward(perp: Vector3, edge_center: Vector3, target: Vector3) -> Vector3:
	var to_target = target - edge_center
	to_target.y = 0
	if perp.dot(to_target) < 0:
		return -perp
	return perp


func _mirror_point_across_edge(point: Vector3, edge_v0: Vector3, edge_dir: Vector3) -> Vector3:
	var to_point = point - edge_v0
	var proj_len = to_point.dot(edge_dir)
	var proj_point = edge_v0 + edge_dir * proj_len
	var perp = point - proj_point
	return proj_point - perp


func _mirror_normal_across_edge(normal: Vector3, edge_dir: Vector3) -> Vector3:
	var edge_component = edge_dir * normal.dot(edge_dir)
	var perp = normal - edge_component
	return edge_component - perp
