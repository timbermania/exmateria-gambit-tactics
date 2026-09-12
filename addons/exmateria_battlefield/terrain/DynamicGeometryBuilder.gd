extends RefCounted

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const MapLightingConfig = preload("res://addons/exmateria_battlefield/assembly/MapLightingConfig.gd")
const SkirtConfig = preload("res://addons/exmateria_battlefield/terrain/SkirtConfig.gd")
const SkirtGeometryGenerator = preload("res://addons/exmateria_battlefield/terrain/SkirtGeometryGenerator.gd")
const VisualGeometryIndex = preload("res://addons/exmateria_battlefield/terrain/VisualGeometryIndex.gd")


const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
const BlackUnlitShader = preload("res://addons/exmateria_battlefield/terrain/black_unlit.gdshader")
const PaletteAnimationTable = preload("res://addons/exmateria_battlefield/texturing/PaletteAnimationTable.gd")

# ADR-0212 dec. 1 — the platform addon publishes one global name; `TunePort` is
# reached through it, spelled the way every other owner in this addon spells it.
const TunePort = ExMateriaPlatform.TunePort
## Builds geometry meshes dynamically from VisualGeometryIndex.
##
## Supports incremental operations:
## - Add geometry from doodads with coordinate transformation
## - Remove geometry in bounds via soft-deletion
## - Rebuild mesh from active (non-deleted) triangles only
##
## Used by MapComposer for dynamic doodad placement.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Map Tint]]
## Vault: [[Terrain Render Pipeline]]

## Emitted for every map `ShaderMaterial` this builder creates (#589). The
## material is an OUTPUT of `Battlefield`; who wants one is not this system's
## business. `TintedSurfaces.register_surface` (`MapTintOverlay.register_material`
## until #1224 merged the two registries) used to be called from
## `_create_material` directly, which made a terrain builder name an `Effects`
## autoload — ADR-0157 dec. 2's outbound debt, and one of the three lines
## ADR-0175 dec. 5 ruled invert rather than sever (all three are functional).
##
## Materials are created LAZILY, per surface type, during every `rebuild_mesh`
## — including the ones a doodad add/remove triggers long after the map first
## composed. So a subscriber that only drains `map_materials()` once would go
## stale, and one that only connects would miss everything built before it
## arrived. `BattlefieldWiring.wire_map` does both, which is why the drain and
## the signal are published together rather than either alone.
signal map_material_created(material: ShaderMaterial)

# Dependencies (set via initialize)
var visual_index: VisualGeometryIndex
var palette_texture: Texture2D  # Can be ImageTexture or CompressedTexture2D (from PNG)
var indexed_texture: Texture2D
var shader: Shader
var manifest_data: Dictionary

# Global vertex array (accumulated across all added geometry)
# Maps vertex positions to indices for deduplication
var _vertex_map: Dictionary = {}  # "x,y,z" -> vertex_index
var _vertices: Array[Vector3] = []  # Array of Vector3 positions

# Material cache (reused across mesh rebuilds)
var _material_cache: Dictionary = {}  # surface_type -> Material (ShaderMaterial or StandardMaterial3D)

# Per-palette animation schedule for this map (PaletteAnimationTable.build), memoized on
# first material. Empty until then — `build` always returns 5 keys, so empty means unbuilt.
var _palette_anim_table: Dictionary = {}

# Skirt generation (extracted to separate class for maintainability)
var _skirt_generator: SkirtGeometryGenerator

# Map bounds for boundary detection (set by MapComposer after placing base map)
var map_bounds: Rect2i = Rect2i():
	set(value):
		map_bounds = value
		if _skirt_generator:
			_skirt_generator.set_map_bounds(value)


## Initialize builder with dependencies.
##
## Args:
##     p_visual_index: VisualGeometryIndex to populate and query
##     p_palette_texture: Palette texture for indexed color rendering
##     p_indexed_texture: Source texture with indexed colors
##     p_shader: Shader for materials
##     p_manifest_data: Manifest data for lighting configuration
func initialize(
	p_visual_index: VisualGeometryIndex,
	p_palette_texture: Texture2D,  # Can be ImageTexture or CompressedTexture2D (from PNG)
	p_indexed_texture: Texture2D,
	p_shader: Shader,
	p_manifest_data: Dictionary
) -> void:
	visual_index = p_visual_index
	palette_texture = p_palette_texture
	indexed_texture = p_indexed_texture
	shader = p_shader
	manifest_data = p_manifest_data

	# Initialize skirt generator with dependencies
	_skirt_generator = SkirtGeometryGenerator.new()
	_skirt_generator.initialize(visual_index, _add_vertex, map_bounds)


## Swap the indexed (color-index) atlas texture on every live material.
##
## Used by the field-object texture animator (event-script {55} Use Field
## Object): it builds a mutable ImageTexture clone of the imported atlas and
## blits animation frames into it. All map ShaderMaterials share the same
## `indexed_texture` uniform reference, so this repoints them in one pass.
## Materials without the uniform (e.g. the black-unlit untextured material)
## ignore the parameter harmlessly.
func swap_indexed_texture(tex: Texture2D) -> void:
	indexed_texture = tex
	for mat in _material_cache.values():
		if mat is ShaderMaterial:
			mat.set_shader_parameter("indexed_texture", tex)


## Repoint every map material at a mutable palette texture, so palette-kind field
## objects ({55} Use Field Object, mode 0x0D) become visible when the animator
## blits animation-frame rows over base palette rows. Mirror of
## swap_indexed_texture for the `palette_texture` uniform.
func swap_palette_texture(tex: Texture2D) -> void:
	palette_texture = tex
	for mat in _material_cache.values():
		if mat is ShaderMaterial:
			mat.set_shader_parameter("palette_texture", tex)


## Add geometry from a doodad with coordinate transformation.
##
## Args:
##     geometry_data: geometry_linked.json data (with TriangleMetadata)
##     doodad_id: Unique ID for this doodad placement
##     offset: Tile coordinate offset (e.g., Vector2i(10, 5) to place at grid (10,5))
##
## Transforms:
##     - Vertex positions: add (offset.x, 0, offset.y) in world space
##     - Tile coords in TriangleMetadata: add (offset.x, offset.y) in grid space
func add_geometry(geometry_data: Dictionary, doodad_id: String, offset: Vector2i) -> void:
	var primitives = geometry_data.Meshes.PrimaryMesh.Primitives
	var source_vertices = geometry_data.Meshes.PrimaryMesh.Vertices

	# Stale-asset guard: the per-polygon visible-angles bitfield (mesh +0xB0)
	# was added to the exporter after the curated maps were first parsed. A
	# geometry_linked.json with no "VisibleAngles" key was exported by the old
	# parser, so every polygon silently falls back to v_angles=0 ("always
	# visible") and the shader cull never fires — near-camera walls obscure
	# units. Warn loudly instead of failing silent. Fix: re-run
	#   (cd tools && uv run python parse_all_maps.py ../project-assets/fft-extract/MAP --force)
	if not primitives.is_empty() and not primitives[0].has("VisibleAngles"):
		push_warning(
			"DynamicGeometryBuilder: doodad '%s' geometry has no 'VisibleAngles' " % doodad_id +
			"(stale map export) — visible-angles cull disabled, geometry will obscure units. " +
			"Re-parse maps: (cd tools && uv run python parse_all_maps.py ../project-assets/fft-extract/MAP --force)"
		)


	var tri_count = 0

	# Process each primitive
	for prim_idx in range(primitives.size()):
		var primitive = primitives[prim_idx]

		# Determine if this is an untextured primitive (black border polygons)
		var is_untextured = (primitive.PaletteId == null)

		var indices = primitive.Indices
		var metadata = primitive.TriangleMetadata
		var face_centroids = primitive.get("FaceCentroids", [])
		var visible_angles_arr = primitive.get("VisibleAngles", [])

		# Process each triangle
		for tri_idx in range(metadata.size()):
			var tri_meta = metadata[tri_idx]

			# Get vertex indices for this triangle
			var base_idx = tri_idx * 3
			var v0_src_idx = indices[base_idx]
			var v1_src_idx = indices[base_idx + 1]
			var v2_src_idx = indices[base_idx + 2]

			# Get source vertex positions and transform them
			var v0_pos = _get_transformed_vertex(source_vertices[v0_src_idx], offset)
			var v1_pos = _get_transformed_vertex(source_vertices[v1_src_idx], offset)
			var v2_pos = _get_transformed_vertex(source_vertices[v2_src_idx], offset)

			# Get source vertex UVs (no transformation needed)
			var v0_uv = _get_vertex_uv(source_vertices[v0_src_idx])
			var v1_uv = _get_vertex_uv(source_vertices[v1_src_idx])
			var v2_uv = _get_vertex_uv(source_vertices[v2_src_idx])

			# Get source vertex normals (use per-vertex normals from source data or calculate face normal)
			var v0_normal = _get_vertex_normal(source_vertices[v0_src_idx], v0_pos, v1_pos, v2_pos)
			var v1_normal = _get_vertex_normal(source_vertices[v1_src_idx], v0_pos, v1_pos, v2_pos)
			var v2_normal = _get_vertex_normal(source_vertices[v2_src_idx], v0_pos, v1_pos, v2_pos)

			# Add vertices to global array (with deduplication)
			var v0_idx = _add_vertex(v0_pos)
			var v1_idx = _add_vertex(v1_pos)
			var v2_idx = _add_vertex(v2_pos)

			# Transform tile coordinates
			var src_tile_coords = tri_meta.tile_coords
			var transformed_tile_coords = Vector2i(
				src_tile_coords[0] + offset.x,
				src_tile_coords[1] + offset.y
			)

			# Determine surface type and palette for this triangle
			# Untextured primitives use MapConstants.SURFACE_UNTEXTURED surface type for black rendering
			var surface_type = MapConstants.SURFACE_UNTEXTURED if is_untextured else tri_meta.surface_type
			var palette_id = 0 if is_untextured else primitive.PaletteId

			# Read pre-computed face centroid (GTE AVSZ4: 4-vertex avg for quads)
			var fc := Vector3.ZERO
			if tri_idx < face_centroids.size():
				var fc_data = face_centroids[tri_idx]
				fc = Vector3(
					float(fc_data[0]) * MapConstants.TILE_SCALE + float(offset.x),
					float(fc_data[1]) * MapConstants.TILE_SCALE,
					float(fc_data[2]) * MapConstants.TILE_SCALE + float(offset.y)
				)

			# Per-polygon visible-angles bitfield (FFT mesh-resource +0xB0). 0 = always visible.
			var v_angles: int = 0
			if tri_idx < visible_angles_arr.size():
				v_angles = int(visible_angles_arr[tri_idx])

			# Add triangle to visual index
			visual_index.add_triangle(
				prim_idx,
				tri_idx,
				[v0_idx, v1_idx, v2_idx],
				v0_pos,
				v1_pos,
				v2_pos,
				v0_uv,
				v1_uv,
				v2_uv,
				v0_normal,
				v1_normal,
				v2_normal,
				palette_id,
				surface_type,
				transformed_tile_coords,
				doodad_id,
				fc,
				v_angles
			)

			tri_count += 1



## Remove geometry in rectangular bounds via soft-deletion.
##
## Args:
##     bounds: Rect2i defining area in tile coordinates (position + size)
##
## Returns:
##     Array of triangle indices that were deleted
func remove_geometry_in_bounds(bounds: Rect2i) -> Array[int]:
	return visual_index.soft_delete_triangles_in_bounds(bounds)


## Rebuild mesh from active triangles in VisualGeometryIndex.
##
## Queries all active (non-deleted) triangles, batches by surface type,
## and creates a multi-surface mesh with materials.
##
## Returns:
##     MeshInstance3D with rendered geometry
func rebuild_mesh() -> MeshInstance3D:
	# Generate skirts before batching triangles (clears previous skirts internally)
	_skirt_generator.generate_all_skirts()


	# Get all active triangles from index
	var active_count = visual_index.get_active_triangle_count()

	# Batch triangles by surface type
	var surface_batches = _batch_triangles_by_surface()


	# Build mesh
	var mesh_instance = _build_multisurface_mesh(surface_batches)


	return mesh_instance


## Get transformed vertex position (apply coordinate offset and FFT->Godot scale).
func _get_transformed_vertex(source_vertex: Dictionary, offset: Vector2i) -> Vector3:
	var fft_position = source_vertex.Position
	var fft_offset_x = float(offset.x) / MapConstants.TILE_SCALE
	var fft_offset_z = float(offset.y) / MapConstants.TILE_SCALE
	return Vector3(
		(fft_position[0] + fft_offset_x) * MapConstants.TILE_SCALE,
		fft_position[1] * MapConstants.TILE_SCALE,
		(fft_position[2] + fft_offset_z) * MapConstants.TILE_SCALE
	)


## Get vertex UV coordinates.
func _get_vertex_uv(source_vertex: Dictionary) -> Vector2:
	var uv = source_vertex.UV
	return Vector2(uv[0], uv[1])


## Get vertex normal (from source data or calculate face normal).
##
## Args:
##     source_vertex: Source vertex dictionary from geometry data
##     v0, v1, v2: Triangle vertex positions (for face normal calculation fallback)
##
## Returns:
##     Normalized Vector3 normal
func _get_vertex_normal(source_vertex: Dictionary, v0: Vector3, v1: Vector3, v2: Vector3) -> Vector3:
	# Use per-vertex normal from source data if available
	if source_vertex.has("Normal"):
		var norm = source_vertex.Normal
		return Vector3(norm[0], norm[1], norm[2]).normalized()

	# Otherwise calculate face normal
	var edge1 = v1 - v0
	var edge2 = v2 - v0
	return edge1.cross(edge2).normalized()


## Add vertex to global array with deduplication.
##
## Returns:
##     Global vertex index
func _add_vertex(pos: Vector3) -> int:
	var key = "%f,%f,%f" % [pos.x, pos.y, pos.z]

	if _vertex_map.has(key):
		return _vertex_map[key]

	var idx = _vertices.size()
	_vertices.append(pos)
	_vertex_map[key] = idx
	return idx


## Batch all active triangles by surface type.
##
## Returns:
##     Dictionary: surface_type -> Array[TriangleData]
func _batch_triangles_by_surface() -> Dictionary:
	var batches: Dictionary = {}

	# Get all surface types
	var surface_types = visual_index.get_surface_types()

	for surface_type in surface_types:
		var triangles = visual_index.get_triangles_by_surface_type(surface_type)
		if triangles.size() > 0:
			batches[surface_type] = triangles

	return batches


## Build multi-surface mesh from batched triangles.
##
## Args:
##     surface_batches: Dictionary of surface_type -> Array[TriangleData]
##
## Returns:
##     MeshInstance3D with one surface per batch
func _build_multisurface_mesh(surface_batches: Dictionary) -> MeshInstance3D:
	var array_mesh = ArrayMesh.new()
	var surface_idx = 0

	for surface_type in surface_batches.keys():
		var triangles = surface_batches[surface_type]

		# CUSTOM0 = RGB_FLOAT face centroid (flat-depth, OT-style).
		# CUSTOM1 = R_FLOAT per-triangle FFT visible-angles bitfield (0..0xFFFF),
		# read by the shader for the PSX renderer's per-polygon backface cull
		# (see DEPTH_MODE_RENDER_ORDER_GUIDE.md Stage 4).
		var surface_arrays = _build_surface_arrays(triangles)
		# CUSTOM2 = RGBA_FLOAT (v0.xy, v1.xy) + CUSTOM3 = RG_FLOAT (v2.xy): the triangle's
		# 3 UV verts, read by the shader's perimeter-aware snap (neighbor-bleed seam fix).
		var custom_format = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | \
			(Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | \
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | \
			(Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays, [], {}, custom_format)

		# Get or create material for this surface (cached for UI compatibility)
		if not _material_cache.has(surface_type):
			_material_cache[surface_type] = _create_material(surface_type)
		var material = _material_cache[surface_type]
		array_mesh.surface_set_material(surface_idx, material)

		surface_idx += 1

	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return mesh_instance


## Build surface arrays for a batch of triangles.
##
## Args:
##     triangles: Array[TriangleData] for this surface
##
## Returns:
##     Array of mesh arrays (positions, uvs, colors, etc.)
func _build_surface_arrays(triangles: Array[VisualGeometryIndex.TriangleData]) -> Array:
	var positions = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	var custom0 = PackedFloat32Array()
	var custom1 = PackedFloat32Array()
	var custom2 = PackedFloat32Array()
	var custom3 = PackedFloat32Array()

	for tri_data in triangles:
		# Get triangle vertices
		var v0 = tri_data.positions[0]
		var v1 = tri_data.positions[1]
		var v2 = tri_data.positions[2]

		# Add positions
		positions.append(v0)
		positions.append(v1)
		positions.append(v2)

		# Add normals (from stored triangle data - per-vertex normals from source)
		normals.append(tri_data.normals[0])
		normals.append(tri_data.normals[1])
		normals.append(tri_data.normals[2])

		# UVs (from stored triangle data)
		uvs.append(tri_data.uvs[0])
		uvs.append(tri_data.uvs[1])
		uvs.append(tri_data.uvs[2])

		# Colors: Encode palette_id in red channel (0-15 → 0.0-1.0)
		# Shader reads this to determine which palette row to use
		var palette_id_normalized = float(tri_data.palette_id) / MapConstants.MAX_PALETTE_ID_FLOAT
		var palette_color = Color(palette_id_normalized, 0, 0, 1)
		colors.append(palette_color)
		colors.append(palette_color)
		colors.append(palette_color)

		# PSX OT-style: bake face centroid into CUSTOM0 (flat depth per face)
		# For quads: pre-computed 4-vertex average (GTE AVSZ4 match)
		# For standalone triangles: 3-vertex average
		var centroid: Vector3 = tri_data.face_centroid
		for _i in range(3):
			custom0.append(centroid.x)
			custom0.append(centroid.y)
			custom0.append(centroid.z)

		# Per-triangle FFT visible-angles bitfield → CUSTOM1.r (same value on all
		# 3 vertices). Float roundtrips a 16-bit int losslessly.
		var v_angles_f := float(tri_data.visible_angles)
		custom1.append(v_angles_f)
		custom1.append(v_angles_f)
		custom1.append(v_angles_f)

		# The triangle's 3 UV verts → CUSTOM2 (v0.xy, v1.xy) + CUSTOM3 (v2.xy), the SAME
		# three verts on all 3 vertices so the shader reads them back as per-face constants.
		# The perimeter-aware snap (indexed_color.gdshader uv_snap_*) uses them to compute
		# barycentric perimeter-closeness and pull edge samples toward the triangle centroid,
		# off the neighbor-patch texels (the boulder green-diagonal bleed).
		var uv0: Vector2 = tri_data.uvs[0]
		var uv1: Vector2 = tri_data.uvs[1]
		var uv2: Vector2 = tri_data.uvs[2]
		for _j in range(3):
			custom2.append(uv0.x)
			custom2.append(uv0.y)
			custom2.append(uv1.x)
			custom2.append(uv1.y)
			custom3.append(uv2.x)
			custom3.append(uv2.y)

	# Create arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_CUSTOM2] = custom2
	arrays[Mesh.ARRAY_CUSTOM3] = custom3

	return arrays


## Create material for a surface type.
##
## Args:
##     surface_type: Surface type string (e.g., "Wall", "Waterway", MapConstants.SURFACE_UNTEXTURED)
##
## Returns:
##     Material with configured parameters (ShaderMaterial or StandardMaterial3D)
func _create_material(surface_type: String) -> Material:
	# Special case: Untextured primitives (black border polygons)
	# GaneshaDx renders these with BasicEffect (unlit) and pure black color
	if surface_type == MapConstants.SURFACE_UNTEXTURED:
		var black_material = ShaderMaterial.new()
		black_material.shader = BlackUnlitShader
		return black_material

	var material = ShaderMaterial.new()
	material.shader = shader

	# Set textures (shared across all materials)
	material.set_shader_parameter("indexed_texture", indexed_texture)
	material.set_shader_parameter("palette_texture", palette_texture)
	# Apply lighting uniforms (shared across all materials)
	# If we already have cached ShaderMaterials, copy lighting from one of them
	# (so UI adjustments are preserved for new materials)
	var reference_material: ShaderMaterial = null
	for cached_mat in _material_cache.values():
		if cached_mat is ShaderMaterial:
			reference_material = cached_mat
			break

	if reference_material:
		_copy_lighting_parameters(material, reference_material)
	else:
		# First ShaderMaterial - use manifest defaults
		MapLightingConfig.apply_to_material(material, manifest_data)

	# Configure surface-specific effects.
	#
	# The two used to share one gate — `surface_type in WATER_SURFACES` turned on BOTH
	# the waves and the palette animation. Only one of them is a property of the surface.
	# The waves are: a sine displacement of a horizontal water plane is meaningless on a
	# wall. The palette animation is NOT: it belongs to the CLUT and runs on whatever
	# polygons sample it, so gating it on the surface type froze every animated palette
	# that a floor tile does not carry. In MAP009 (Citadel of Igros) that is the
	# waterfalls — palettes 5 and 7 are 100% `Wall` triangles, and 74 of palette 2's 152
	# are too, so the flat water cycled and the falling water did not.
	if surface_type in MapConstants.WATER_SURFACES:
		# `water_surface_offset` is set here, NOT under the wave toggle: it is a
		# diagnostic lift of the water plane (default 0.0) and is independent of the
		# waves. Non-zero, it opens a 1-px-per-0.01 crack at every water/non-water
		# join — see SkirtConfig.PROPERTY_META.
		material.set_shader_parameter("water_surface_offset", SkirtConfig.water_surface_offset)
		material.set_shader_parameter("wave_height", MapConstants.WATER_WAVE_HEIGHT)
		material.set_shader_parameter("wave_frequency", MapConstants.WATER_WAVE_FREQUENCY)
		material.set_shader_parameter("wave_speed", MapConstants.WATER_WAVE_SPEED_BASE / MapConstants.ANIMATION_TICKS_PER_SECOND)
	material.set_shader_parameter("enable_waves", _waves_on(surface_type))

	# Per-palette animation schedule from the manifest — the same table on every
	# material, because the shader picks the row by the polygon's own palette id.
	PaletteAnimationTable.apply_to_material(material, _palette_animation_table())

	# Publish it. The `Engine.is_editor_hint()` guard that used to wrap the
	# `MapTintOverlay.register_material` call here is GONE and not merely moved (the verb
	# is `TintedSurfaces.register_surface(SURFACE_MAP, mat)` since #1224):
	# it existed so an editor-time build would not push materials into a runtime
	# autoload, and with the reach inverted there is no subscriber in the editor
	# to push to — `BattlefieldWiring` is called by scene roots at runtime only.
	map_material_created.emit(material)

	return material


## Every map `ShaderMaterial` built so far — the REPLAY half of
## `map_material_created`, for a subscriber that arrives after composition
## (which every scene root does: the builder is constructed inside `_build_map`,
## so nothing outside can connect before the first materials exist).
##
## `_material_cache` also holds `StandardMaterial3D` for untextured surfaces;
## those are filtered out because the tint seam is a shader uniform.
func map_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for mat in _material_cache.values():
		if mat is ShaderMaterial:
			out.append(mat)
	return out


## Copy lighting parameters from reference material to new material.
##
## Used when creating materials for new surface types to ensure they
## inherit any lighting adjustments made via CombinedLightingUI.
##
## Args:
##     dest_material: New material to set parameters on
##     src_material: Existing material to copy parameters from
func _copy_lighting_parameters(dest_material: ShaderMaterial, src_material: ShaderMaterial) -> void:
	# List of all lighting-related shader parameters (GaneshaDx-compatible)
	var lighting_params = [
		"ambient_light",
		"light1_color",
		"light1_direction",
		"light1_boost",
		"light2_color",
		"light2_direction",
		"light2_boost",
		"light3_color",
		"light3_direction",
		"light3_boost"
	]

	# Copy each parameter from source to destination
	for param_name in lighting_params:
		var value = src_material.get_shader_parameter(param_name)
		if value != null:
			dest_material.set_shader_parameter(param_name, value)


## The map's per-palette animation schedule, built once per builder.
##
## `PaletteAnimationTable.build` is the whole rule; this is only the manifest read and
## the cache, so every material this builder creates hands the shader the same arrays.
func _palette_animation_table() -> Dictionary:
	if _palette_anim_table.is_empty():
		var animations: Dictionary = manifest_data.get("animations", {})
		_palette_anim_table = PaletteAnimationTable.build(animations.get("palette_animations", []))
	return _palette_anim_table


# --- the water-wave toggle (ADR-0068) ----------------------------------------------
#
# OWNED HERE, not in the debug panel (R1): this builder is the production class that
# binds the slug, pull-reads it, and applies it to the shader uniform. The slug name, the
# scrubbable `static var` default (materialize's home — the R6 follower rewrites this
# literal initializer) and the panel hint all live on the owner. MapRenderDebugPanel is a
# pure VIEW that names only the slug string.
#
# The default is OFF, which is the behaviour change the toggle exists to deliver: the
# sine displacement is an invention, not something the PSX renderer does — FFT's water
# moves by cycling its CLUT, which is the palette animation right above. Leaving the knob
# in the registry rather than deleting the code keeps the effect one scrub away.
const _WATER_WAVES_SLUG := "map.water_waves"
static var _water_waves_default := false
const _WATER_WAVES_HINT := {}


## Bind at class load — this addon's classes have no central replay (ADR-0173 deleted
## `Tune.register_all()`), so each owner registers its own slugs the way SkirtConfig and
## SkirtGeometryGenerator do. Editor-guarded because `Tune` is a non-@tool placeholder there.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	if Engine.is_editor_hint():
		return
	TunePort.bind(_WATER_WAVES_SLUG, _water_waves_default, _WATER_WAVES_HINT)


## Should `surface_type` wave? Water surfaces only, and only while the knob is on.
func _waves_on(surface_type: String) -> bool:
	if not surface_type in MapConstants.WATER_SURFACES:
		return false
	if Engine.is_editor_hint():
		return _water_waves_default
	return TunePort.get_value(_WATER_WAVES_SLUG, _water_waves_default)


## Re-push `enable_waves` onto the materials already built, so a scrub of
## `map.water_waves` applies live instead of waiting for the next map rebuild.
## `_material_cache` is keyed by surface type, which is what makes the water subset
## addressable from here and nowhere else. Driven by MapComposer's `on_update`.
func apply_water_waves() -> void:
	for surface_type: String in _material_cache:
		var mat = _material_cache[surface_type]
		if mat is ShaderMaterial:
			mat.set_shader_parameter("enable_waves", _waves_on(surface_type))
