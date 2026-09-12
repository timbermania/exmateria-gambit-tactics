extends Node3D

## Debug-only tile grid + per-tile center cross + per-tile "X,Z" grid-coord
## label, drawn as ONE PRIMITIVE_LINES mesh over the terrain (labels are
## billboarded Label3Ds). Lets you see how centered a unit's feet anchor sits on
## its tile AND read off the grid_x/grid_z of any tile at a glance. Map-attached,
## so it renders through the PAR seam (Pattern 1, pixel_aspect_full) and the unified
## OT depth (TILE_OVERLAY) like every other battle mesh — see
## grid_overlay.gdshader. Owned/toggled by ScenarioUnitAlignmentDebugPanel;
## rebuilt against the live map on scene reload.
##
## The overlay is `top_level` so its geometry lives in absolute world space
## regardless of where it is parented — build_from_lattice() bakes each tile's
## LOCAL vertices (Tile.tile_vertices) into world space via the tile transform.
## Vault: [[GTE World-to-Screen Transform]]

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")


const GridShader := preload("res://addons/exmateria_battlefield/debug/grid_overlay.gdshader")
const DepthModeScript := ExMateriaSchema.DepthMode

const Y_LIFT := 0.02       ## world units above the tile face so the lines clear it
const CROSS_ARM := 0.16    ## half-length of the center-cross arms (tile = 1.0 unit)

const EDGE_COLOR := Color(0.0, 0.85, 0.9)    ## cyan tile borders
const CENTER_COLOR := Color(1.0, 0.8, 0.0)   ## amber center cross (tile center)

const LABEL_COLOR := Color(1.0, 1.0, 1.0)    ## white "X,Z" grid-coord text
const LABEL_OUTLINE := Color(0.0, 0.0, 0.0)  ## black outline for contrast on any terrain
const LABEL_FONT_SIZE := 48                  ## rasterized glyph size (sharpness)
const LABEL_PIXEL_SIZE := 0.005              ## world units per glyph pixel (0.005*48 ≈ 0.24u tall)
const LABEL_Y_LIFT := 0.05                   ## extra world-Y so text floats above the center cross

var _mesh_instance: MeshInstance3D
var _labels_root: Node3D


func _ready() -> void:
	# Absolute world space: build_from_lattice bakes world-space vertices, so the
	# mesh must not inherit the map/parent transform.
	top_level = true
	transform = Transform3D.IDENTITY


## (Re)build the line mesh from the map's lattice.
##
## 🔴 TAKES THE PORT AND READS THE STORE BEHIND IT (ADR-0192 dec. 5). The former
## signature was `build_from_tiles(tiles: Array)` and its one caller —
## `ScenarioUnitAlignmentDebugPanel`, a `Cutscene` file — fetched
## `map.get_all_tiles()` and handed the `Array[Tile]` straight back into this file,
## which is itself inside the addon. The crossing was pure ceremony.
##
## It could not be repaired by re-typing, because this is the ONE consumer ADR-0170
## dec. 2's "every read above is a `TerrainCell` field; none needs the node" is false
## on: the mesh needs `tile_vertices` (four tile-LOCAL verts) AND `global_transform`,
## and neither is on ADR-0164 dec. 2's field list nor derivable from it. The two
## repairs that keep the crossing were both rejected — world-space `vertices` on
## `TerrainCell` would allocate four `Vector3` per tile for three consumers that
## never read them, and a fifth `cell_outline(x, z)` port member would publish
## geometry to serve a debug panel whose consumer is already inside the addon.
##
## Deleting a crossing beats re-typing one. `_tiles()` is the addon-internal back
## door that makes it possible, and it is a door only addon files can open — correct,
## because the ADDON is the encapsulation unit here, not the class.
func build_from_lattice(lattice: Lattice) -> void:
	_clear()
	var tiles: Array = lattice._tiles() if lattice != null else []
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()

	# Container for the per-tile grid-coord labels so _clear() can drop them all.
	_labels_root = Node3D.new()
	add_child(_labels_root)

	for tile in tiles:
		if tile == null or not is_instance_valid(tile):
			continue
		var tv: PackedVector3Array = tile.tile_vertices
		if tv.size() != 4:
			continue
		# tile_vertices are tile-LOCAL; bake to world via the tile transform.
		var xform: Transform3D = tile.global_transform
		var w := PackedVector3Array()
		var centroid := Vector3.ZERO
		for v in tv:
			var wv: Vector3 = xform * v + Vector3(0.0, Y_LIFT, 0.0)
			w.append(wv)
			centroid += wv
		centroid /= 4.0

		# Four tile edges.
		for i in 4:
			_add_seg(verts, colors, custom0, w[i], w[(i + 1) % 4], centroid, EDGE_COLOR)
		# Center cross on the tile plane (world X and Z arms through the centroid).
		_add_seg(verts, colors, custom0,
			centroid - Vector3(CROSS_ARM, 0.0, 0.0), centroid + Vector3(CROSS_ARM, 0.0, 0.0),
			centroid, CENTER_COLOR)
		_add_seg(verts, colors, custom0,
			centroid - Vector3(0.0, 0.0, CROSS_ARM), centroid + Vector3(0.0, 0.0, CROSS_ARM),
			centroid, CENTER_COLOR)

		# "X,Z" grid-coord label floating over the tile center.
		_add_label(centroid, tile.grid_x, tile.grid_z)

	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0

	var am := ArrayMesh.new()
	var fmt := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays, [], {}, fmt)

	var mat := ShaderMaterial.new()
	mat.shader = GridShader
	DepthModeScript.apply(mat, DepthModeScript.Mode.TILE_OVERLAY)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = am
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _add_seg(verts: PackedVector3Array, colors: PackedColorArray, custom0: PackedFloat32Array,
		a: Vector3, b: Vector3, centroid: Vector3, col: Color) -> void:
	verts.append(a)
	verts.append(b)
	colors.append(col)
	colors.append(col)
	# CUSTOM0 = flat world centroid on BOTH endpoints (one depth for the whole line).
	for _n in 2:
		custom0.append(centroid.x)
		custom0.append(centroid.y)
		custom0.append(centroid.z)


## Billboarded, always-on-top "grid_x,grid_z" text at the tile centroid.
func _add_label(centroid: Vector3, grid_x: int, grid_z: int) -> void:
	var lbl := Label3D.new()
	lbl.text = "%d,%d" % [grid_x, grid_z]
	lbl.position = centroid + Vector3(0.0, LABEL_Y_LIFT, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true              # always readable, even under terrain lips
	lbl.fixed_size = false                # scale with distance so far tiles read smaller
	lbl.font_size = LABEL_FONT_SIZE
	lbl.pixel_size = LABEL_PIXEL_SIZE
	lbl.modulate = LABEL_COLOR
	lbl.outline_size = 12
	lbl.outline_modulate = LABEL_OUTLINE
	_labels_root.add_child(lbl)


func _clear() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
	_mesh_instance = null
	if _labels_root and is_instance_valid(_labels_root):
		_labels_root.queue_free()
	_labels_root = null
