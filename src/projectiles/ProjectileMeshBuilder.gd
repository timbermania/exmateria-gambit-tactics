class_name ProjectileMeshBuilder
extends RefCounted

## Static utility to build ArrayMesh from PSX projectile model data.
## Converts PSX coordinates and colors to Godot format with Gouraud shading.
##
## A projectile model is a multi-face ENSEMBLE (e.g. the arrow is 17 faces), so
## it sorts per face in the one Ordering Table, exactly like the map (ADR-0009):
## each face's AVSZ3/AVSZ4 centroid (via DepthMode) is baked into CUSTOM0 on every
## one of that face's vertices, and projectile_vertex_color.gdshader projects it.
## A split quad feeds both child triangles the SAME 4-vertex centroid so they
## sort as one unit and never z-fight along the split diagonal.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const SCALE_FACTOR := 100.0  # Divide PSX coords by this for Godot units


static func build_mesh(model_data: Dictionary) -> ArrayMesh:
	"""Build an ArrayMesh (vertex color + per-face CUSTOM0 OT depth) from model JSON."""
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()

	var vertices: Array = model_data["vertices"]
	var faces: Array = model_data["faces"]

	# Filter exact duplicate faces to prevent z-fighting
	# Some PSX models have duplicate faces with different colors at same indices
	var seen_faces := {}

	for face in faces:
		var indices: Array = face["indices"]
		var key := str(indices)  # Exact match including order
		if seen_faces.has(key):
			continue  # Skip duplicate
		seen_faces[key] = true

		var face_colors: Array = face["colors"]
		var face_type: String = face["type"]

		# Handle quads by splitting into 2 triangles
		# PSX triangulates as [0,1,2] + [1,2,3] per psx-spx GPU docs.
		# Both child triangles share the quad's 4-vertex centroid (AVSZ4).
		if face_type == "quad":
			var centroid := DepthMode.quad_centroid(
				_vert(vertices, indices[0]), _vert(vertices, indices[1]),
				_vert(vertices, indices[2]), _vert(vertices, indices[3]))
			_add_triangle(positions, colors, custom0, vertices, indices, face_colors, [0, 1, 2], centroid)
			_add_triangle(positions, colors, custom0, vertices, indices, face_colors, [1, 2, 3], centroid)
		else:
			# tri, tri_normal, etc. - all are triangles (AVSZ3 centroid)
			var centroid := DepthMode.tri_centroid(
				_vert(vertices, indices[0]), _vert(vertices, indices[1]), _vert(vertices, indices[2]))
			_add_triangle(positions, colors, custom0, vertices, indices, face_colors, [0, 1, 2], centroid)

	var mesh := ArrayMesh.new()
	if positions.is_empty():
		return mesh

	# No normals needed - PSX Gouraud uses unlit vertex color interpolation
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	var custom_format := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_format)
	return mesh


static func _vert(vertices: Array, idx: int) -> Vector3:
	"""Resolve a vertex index to a scaled (Godot-unit, local-space) position."""
	var v: Array = vertices[idx]
	return Vector3(v[0], v[1], v[2]) / SCALE_FACTOR


static func _add_triangle(positions: PackedVector3Array, colors: PackedColorArray,
						  custom0: PackedFloat32Array, vertices: Array,
						  indices: Array, face_colors: Array, tri_order: Array,
						  centroid: Vector3) -> void:
	"""Append one triangle: scaled positions, per-vertex Gouraud color, shared face centroid in CUSTOM0."""
	for i in tri_order:
		var c: Array = face_colors[i]
		# Set vertex color (RGB 0-255 -> 0.0-1.0)
		colors.append(Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0))
		# Add vertex (PSX coords / SCALE_FACTOR = Godot units)
		positions.append(_vert(vertices, indices[i]))
		# Flat per-face OT depth: same centroid on every vertex of the face
		custom0.append(centroid.x)
		custom0.append(centroid.y)
		custom0.append(centroid.z)
