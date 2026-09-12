extends StaticBody3D

## Vault: [[Display Space Blend Fold]]
## Vault: [[Tile Overlay]]

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")
const TileOverlayCompositor = preload("res://addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd")
const TileOverlayConfig = preload("res://addons/exmateria_battlefield/overlay/TileOverlayConfig.gd")


# Constants for highlight rendering
const HIGHLIGHT_Y_OFFSET: float = 0.01  # Offset above tile surface to prevent z-fighting
const FALLBACK_HIGHLIGHT_Y: float = 0.03  # Y position for flat quad fallback
const HIGHLIGHT_ALPHA: float = 0.5  # Transparency of highlight overlay

## The marking vocabulary moved to the SCHEMA at loop pass 8 — `CellMarking.Kind`, in
## `addons/exmateria_schema/lattice/`, values unchanged (ADR-0196 dec. 6, superseding
## ADR-0193 dec. 2 and ADR-0195 dec. 6). `src/strategy/` decides which cells wear which
## marking, so a host had to compile against `Battlefield` in order to say "contested";
## that was ADR-0164 dec. 4 criterion 1's largest namer and `tools/check_lattice_publish.py`
## is what measures it. What stays here is what a marking LOOKS like, which is
## `TileOverlayConfig`'s — see the comment on the range atlas below.

# ROM-ripped range-tile texture + palette LUT (parse_range_tiles.py). Sampled by
# tile_overlay_mode*.gdshader; rows are blue(0)/red(1)/yellowA(2)/yellowB(3). The *look*
# per highlight type lives in TileOverlayConfig (a class_name singleton; tunable via the F3
# "Tiles" panel) — FFT's color meanings are decoupled from our placement semantics
# (see CONTEXT.md "Battle range-overlay tile").
# ⚠️ The two paths below used to be `res://assets/…` consts here. They are now composed
# from the host-injected content root (ADR-0202 dec. 5 Class B — the addon can never ship
# a ROM rip, so the LITERAL is the defect and the dependency stays as a contract). See
# `BattlefieldContent`, which holds the refusal a bare project gets.
static var _range_tex: Texture2D = null
static var _range_palette: Texture2D = null
static var _range_missing_warned: bool = false

static func _ensure_range_textures() -> void:
	var tex_path: String = BattlefieldContent.range_tex_path()
	var palette_path: String = BattlefieldContent.range_palette_path()
	if _range_tex == null and not tex_path.is_empty():
		_range_tex = ResourceLoader.load(tex_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if _range_palette == null and not palette_path.is_empty():
		_range_palette = ResourceLoader.load(palette_path, "", ResourceLoader.CACHE_MODE_REUSE)
	# Fail loud (once) rather than silently rendering a blank tile: RANGETILE is
	# gitignored + regenerated per-machine, and NOT produced by every asset
	# regen path. A null here = the active-cursor tile / HUD digits will be empty.
	# An unset content root reports itself once from `BattlefieldContent.resolve`, so
	# this arm stays quiet in that case rather than printing the same install gap twice.
	if tex_path.is_empty() or palette_path.is_empty():
		return
	if (_range_tex == null or _range_palette == null) and not _range_missing_warned:
		_range_missing_warned = true
		push_error("Tile: RANGETILE textures missing (%s / %s) — the cursor highlight tile will be blank. Regenerate from the package root with: uv run python tools/parse_range_tiles.py" % [tex_path, palette_path])


## The ROM-derived range atlas, loaded once. `null` until a host supplies a content root.
##
## Public because `tile_cursor_opaque.tres` no longer carries these two as `ext_resource`s
## — no setting can fix an `ext_resource`, so the material takes them at runtime and
## `TileCursor` binds them from here (ADR-0202 dec. 5 Class B).
static func range_texture() -> Texture2D:
	_ensure_range_textures()
	return _range_tex


## The range atlas's palette LUT. `null` until a host supplies a content root.
static func range_palette_texture() -> Texture2D:
	_ensure_range_textures()
	return _range_palette

## Current highlight type (for tracking)
var current_highlight_type: CellMarking.Kind = CellMarking.Kind.NONE

# Grid position
var grid_x: int
var grid_z: int

## Which of the column's terrain levels this tile is (ADR-0219 dec. 1). `0` is the
## ground; `1` is the bridge/roof plane the ROM's `tile_ptr(x, z, level)` strides to
## and we used to drop. NOT a height and not a world Z — see `TerrainCell.grid`.
var level: int = 0

## This tile's cell identity, `(grid_x, grid_z, level)` — the key `TerrainIndex`
## files it under and the `Vector3i` every occupancy `Dictionary` uses. Read this
## rather than rebuilding it from the three ints, so the store and the port cannot
## disagree about what a cell is.
var cell_key: Vector3i:
	get: return Vector3i(grid_x, grid_z, level)
var tile_vertices: PackedVector3Array = PackedVector3Array([])

# Terrain properties (from terrain.json)
var surface_type: String = "Unknown"
var height: int = 0
var slope_type: String = "Flat"
var impassable: bool = false
var unselectable: bool = false
var pass_through_only: bool = false
var depth: int = 0
var slope_height: int = 0
var thickness: int = 0
var shading: int = 1
var normal: Vector3 = Vector3.UP

# Occupancy is NOT here. This file used to carry `reserved_by: Unit` under the
# claim "the ONLY occupation tracking variable ... both reservation AND current
# occupation". It was neither, and three audit passes were misled by those two
# sentences before ADR-0166 measured the concept and found SIX spellings, five of
# them `Battle`'s. The one that lived here was written once by
# `Unit.place_on_tile`, never released in gameplay, read for no decision, and its
# one guard ran after the position it guarded was already assigned. It is deleted
# (ADR-0166 dec. 2), not inverted and not retyped.
#
# Occupancy lives in `Battle`, in two claims with two arbiters (ADR-0166 dec. 5):
#   - deployment assignment  -> `DeploymentAssignment` (tile -> unit, CPU-side, no GPU
#     battle exists yet). Was `PlacementTileSet.claim_tile` until ADR-0258 retired the
#     deployment march; the ARBITER moved, the two-claims shape did not.
#   - instantaneous standing -> `is_tile_occupied` in the GPU mover, DERIVED per
#     tick from the unit positions the simulator already owns.

# Highlight system
var highlight_mesh: MeshInstance3D = null
var shader_material: ShaderMaterial = null

func _ready():
	add_to_group("tiles")
	# Live re-apply when the Tiles debug panel twists a knob (TileOverlayConfig
	# broadcasts; only currently-highlighted tiles refresh).
	TileOverlayConfig.of().changed.connect(_on_overlay_config_changed)


func _on_overlay_config_changed() -> void:
	if current_highlight_type != CellMarking.Kind.NONE and shader_material:
		TileOverlayConfig.of().apply_to_material(shader_material, current_highlight_type)

## ADDON-INTERNAL, and the underscore is the decision (ADR-0221 dec. 3). A cell wears
## more than one marking at a time and this node renders exactly ONE of them, so the
## arbitration lives in `TileHighlights` — the only caller of this and of
## `_clear_highlight`, kept sole by `tools/check_highlight_writer.py`. It used to be
## public with three writers and no arbiter, which is how a march pick could be erased
## by the cursor walking off it. Rendering stays here; the underscore moved the
## AUTHORITY, not the mesh. Same spelling as `Lattice._tile_at` / `_tiles`
## (ADR-0164 dec. 2).
func _set_highlight_type(type: CellMarking.Kind) -> void:
	"""Set highlight with specific type and color.

	Args:
		type: CellMarking.Kind value for the highlight color
	"""
	if type == CellMarking.Kind.NONE:
		_clear_highlight()
		return

	current_highlight_type = type

	# Hybrid routing (COMPOSITOR_INPUT_CONTRACT_GENERALIZATION.md §4a): additive (blend 1/2/3)
	# flat_fill overlays fold through the display-space compositor as a solid-color decal — register
	# with the TileOverlayCompositor and draw NO in-scene mesh. Average(0) + opaque(4) stay in-scene.
	if TileOverlayCompositor.is_routed(type):
		if highlight_mesh:
			highlight_mesh.visible = false
		TileOverlayCompositor.of().register(self, type)
		return
	# In-scene path (average / opaque): unregister in case we were routed a moment ago.
	TileOverlayCompositor.of().unregister(self)

	if not highlight_mesh:
		# Create highlight mesh on first use
		highlight_mesh = MeshInstance3D.new()

		if tile_vertices.size() == 4:
			# Create slope-conforming mesh from vertices with CUSTOM0 centroid
			var arrays = []
			arrays.resize(Mesh.ARRAY_MAX)

			# Offset vertices slightly above tile for visibility
			var highlight_vertices = PackedVector3Array([])
			for v in tile_vertices:
				highlight_vertices.append(v + Vector3(0, HIGHLIGHT_Y_OFFSET, 0))

			# GTE-style CUSTOM0: 4-vertex centroid (AVSZ4 match)
			var centroid := Vector3.ZERO
			for v in tile_vertices:
				centroid += v
			centroid /= 4.0
			var custom0 := PackedFloat32Array()
			for _i in 4:
				custom0.append(centroid.x)
				custom0.append(centroid.y)
				custom0.append(centroid.z)

			# UVs map the 4 corners to a unit square; the shader scales this into
			# the 14x14 tile sub-rect of the RANGETILE sheet.
			var uvs := PackedVector2Array([
				Vector2(0.0, 0.0), Vector2(1.0, 0.0),
				Vector2(1.0, 1.0), Vector2(0.0, 1.0),
			])

			arrays[Mesh.ARRAY_VERTEX] = highlight_vertices
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
			arrays[Mesh.ARRAY_CUSTOM0] = custom0
			arrays[Mesh.ARRAY_TEX_UV] = uvs

			# Create mesh with CUSTOM0 format
			var array_mesh = ArrayMesh.new()
			var custom_format := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_format)
			highlight_mesh.mesh = array_mesh
		else:
			# Fallback to flat quad if no vertices
			var quad_mesh = QuadMesh.new()
			quad_mesh.size = Vector2(1.0, 1.0)
			highlight_mesh.mesh = quad_mesh
			highlight_mesh.position.y = FALLBACK_HIGHLIGHT_Y
			highlight_mesh.rotation.x = -PI / 2

		add_child(highlight_mesh)

		# Load shader material + the shared ROM range-tile texture/palette.
		shader_material = load("res://addons/exmateria_battlefield/overlay/tile_overlay.tres").duplicate()
		highlight_mesh.material_override = shader_material
		_ensure_range_textures()
		shader_material.set_shader_parameter("range_tex", _range_tex)
		shader_material.set_shader_parameter("range_palette", _range_palette)

	# Push the per-type look (palette / fill / animation / blend mode) + global UV crop
	# from TileOverlayConfig. Tunable live via the F3 "Tiles" panel.
	TileOverlayConfig.of().apply_to_material(shader_material, type)
	highlight_mesh.visible = true

## ADDON-INTERNAL — see `_set_highlight_type` (ADR-0221 dec. 3).
func _clear_highlight():
	current_highlight_type = CellMarking.Kind.NONE
	# Drop any routed registration + hide the in-scene mesh (whichever path was active).
	TileOverlayCompositor.of().unregister(self)
	if highlight_mesh:
		highlight_mesh.visible = false


func _exit_tree() -> void:
	# A routed tile freed while highlighted must leave the compositor's active set (else its slot never
	# releases and a stale invalid ref lingers).
	TileOverlayCompositor.of().unregister(self)
