extends Node
## Folds the routed additive tile overlays (PLACEMENT_PLAYER/ENEMY/CONTESTED — the blue Move / red
## Attack highlights) into the display-space fold as a SINGLE baked world-space ArrayMesh (ADR-0074 ④b,
## issue #229). Autoload so any Tile can register.
##
## FIXES THE LIVE BUG: these tiles are GROUND DECALS (geometry = world_quad). The old path staged
## them through the particle pool, whose per-frame engine-fold materialization read only `mode` and
## billboard-interpreted every prim — so on Forward+ the Move/Attack tiles got billboard-projected and
## VANISHED. Baking them as a real world-space mesh wearing the monomorphic `tile_decal_fold` material
## (world_quad / PAR-full / additive, its axes baked not forwarded) fixes it BY CONSTRUCTION.
##
## The decal DRAPES: each corner keeps its own terrain Y, so a highlight on an incline lies on the
## incline (ADR-0250). `world_quad` constrains how the verts are PRODUCED — baked ground positions, never
## expanded about a centroid at draw time — and says nothing about them sharing a Y. The DEPTH is still
## one value per face, from the shared CUSTOM0 centroid; see `_append_tile`.
##
## Every routed tile is a SINGLE solid color per (type, phase) — flat_fill = one constant CLUT index, so
## the barber-pole shimmer is a CPU index-rotation (TileOverlayColor), baked into the mesh's per-vertex
## COLOR. Only additive (mode 1/2/3) flat_fill types route; mode 0 (average) + mode 4 (opaque,
## CURSOR_ACTIVE) stay in-scene. Tile.set_highlight_type() registers a routed type here (no in-scene
## mesh) and clear_highlight() unregisters. ALL active routed tiles bake into ONE carrier per frame.

## Preloaded `Shader` objects, not `String` paths — ADR-0191 dec. 11. A `load()` on a
## mistyped path returns null, a null shader does not raise, and the fold "just stops, with no
## error". That hazard is a property of naming a fold shader from GDScript, not of picking
## between two, so it reaches this block even though dec. 2's rule does not.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

# ADR-0211 dec. 2 — this file referenced its OWN `class_name`, which the
# façade pass deleted. A self-preload restores the spelling with no body edit.
const TileOverlayCompositor = preload("res://addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd")

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")
const TileOverlayColor = preload("res://addons/exmateria_battlefield/overlay/TileOverlayColor.gd")
const TileOverlayConfig = preload("res://addons/exmateria_battlefield/overlay/TileOverlayConfig.gd")

const TILE_DECAL_FOLD_SHADER := preload("res://addons/exmateria_battlefield/overlay/tile_decal_fold.gdshader")
## The TEXTURED routed tile's fold shader — the active-cursor tile, the one overlay that
## samples the RANGETILE sheet instead of resolving to a solid colour (flat_fill = false).
## It gets its own carrier, and therefore its own fold-order key: the flat carrier stamps ONE
## order from the MEAN centroid of every routed tile, which is meaningless to order against a
## particular unit's shadow. See _rebuild_cursor_mesh.
const TILE_OVERLAY_ADD_FOLD_SHADER := preload("res://addons/exmateria_battlefield/overlay/tile_overlay_add_fold.gdshader")
# ⚠️ Was a `res://assets/…` const here. The SECOND namer of the palette, which is exactly
# the argument for ONE injected search root rather than a constant per holder — ADR-0202
# dec. 5 Class B. Resolved through `BattlefieldContent` at call time now.

# Lift the decal just above the tile surface so it wins the reversed-Z depth test against the opaque map
# (mirrors the in-scene Tile.HIGHLIGHT_Y_OFFSET). STANDARD depth + this lift replaces the in-scene
# TILE_OVERLAY(7) forward nudge (which the GPU ot_depth path does not carry).
const DECAL_LIFT := 0.02
# DepthMode.STANDARD — the lifted decal sorts at its natural projected depth (occlusion via plain
# clip.z + DECAL_LIFT; the fold's GPU ot_depth covers mode 0 exactly).
const TILE_DEPTH_MODE := DepthMode.Mode.STANDARD
# Blend modes that route through the fold (additive/sub/add25). average(0) + opaque(4) stay in-scene.
const ROUTED_BLEND_MODES := [1, 2, 3]

var _mesh_instance: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _palette: Image = null
var _active: Dictionary = {}   # Tile -> CellMarking.Kind
var _elapsed: float = 0.0

## The TEXTURED routed tile's own carrier + material (the active cursor). Separate from the
## batched flat-colour one above on two counts: it wears a different shader (GPU CLUT sample
## vs baked vertex COLOR), and it needs its own `render_layer_order`, because ordering it
## against the unit shadow that overlaps it is the whole reason the tile is folded at all.
var _cursor_mesh_instance: MeshInstance3D = null
var _cursor_mat: ShaderMaterial = null
var _range_tex: Texture2D = null
var _range_palette_tex: Texture2D = null


## The live singleton, parented to `/root` so its lifetime matches the autoload it replaces.
## Deferred `add_child` because first touch is inside `Tile.set_highlight_type()`, called
## from a tile's own tree-entry path where the parent is busy. Off-tree for that one frame is
## safe: `_current_camera()` already null-guards `get_tree()` and `_process` returns early
## while `_mesh_instance` is null.
static var _inst: TileOverlayCompositor = null


static func of() -> TileOverlayCompositor:
	if _inst == null or not is_instance_valid(_inst):
		var n := new()
		_inst = n
		n.name = "TileOverlayCompositor"
		Engine.get_main_loop().root.add_child.call_deferred(n)
	return _inst


func _init() -> void:
	_load_palette()


func _load_palette() -> void:
	var palette_path: String = BattlefieldContent.range_palette_path()
	if not palette_path.is_empty():
		var tex: Texture2D = ResourceLoader.load(palette_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if tex != null:
			_range_palette_tex = tex
			_palette = tex.get_image()
	# The indexed RANGETILE sheet — needed only by the TEXTURED carrier (the flat decals
	# resolve on the CPU and sample nothing). Same host-injected content root as the palette.
	var tex_path: String = BattlefieldContent.range_tex_path()
	if not tex_path.is_empty():
		_range_tex = ResourceLoader.load(tex_path, "", ResourceLoader.CACHE_MODE_REUSE)


## True if a highlight type's blend mode routes through the fold (vs staying in-scene). STATIC:
## it reads a const and a static param, so asking the question must not construct the singleton —
## every Tile asks it, and most answers are false.
static func is_routed(type: int) -> bool:
	var bm: int = int(TileOverlayConfig.get_param(type, "blend_mode"))
	return ROUTED_BLEND_MODES.has(bm)


## Register a routed tile (called by Tile.set_highlight_type for an additive flat_fill type).
func register(tile: Node, type: int) -> void:
	_active[tile] = type
	if is_textured(type):
		_ensure_cursor_carrier()
	else:
		_ensure_carrier()


## Does this routed type SAMPLE the RANGETILE sheet (vs resolve to one solid colour)? That is
## the fork between the two carriers, and it is `flat_fill` — the same flag the in-scene shader
## branches on. Only the active-cursor tile answers true today. STATIC for the same reason
## is_routed() is: every register asks, and it reads a static param.
static func is_textured(type: int) -> bool:
	return not bool(TileOverlayConfig.get_param(type, "flat_fill"))


## Unregister a tile (highlight cleared / tile freed). Frees the carrier when the last routed tile goes.
func unregister(tile: Node) -> void:
	_active.erase(tile)
	if _active.is_empty():
		_free_carrier()


## Build the shared baked-mesh carrier under this singleton (idempotent). It renders in the main
## viewport's World3D like any node under /root; the fold collects it by its compositor_layer material.
func _ensure_carrier() -> void:
	if _mesh_instance != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = TILE_DECAL_FOLD_SHADER
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TileDecalFold"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The tiles span the whole highlight range; a generous AABB keeps the batch from frustum-culling.
	_mesh_instance.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	_mesh_instance.material_override = _mat
	add_child(_mesh_instance)


## Build the TEXTURED carrier (idempotent). Same node shape as the flat one; the differences
## are the shader and the fact that it carries at most a handful of tiles (in practice one).
func _ensure_cursor_carrier() -> void:
	if _cursor_mesh_instance != null:
		return
	_cursor_mat = ShaderMaterial.new()
	_cursor_mat.shader = TILE_OVERLAY_ADD_FOLD_SHADER
	_cursor_mat.set_shader_parameter("range_tex", _range_tex)
	_cursor_mat.set_shader_parameter("range_palette", _range_palette_tex)
	_cursor_mesh_instance = MeshInstance3D.new()
	_cursor_mesh_instance.name = "TileCursorDecalFold"
	_cursor_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_mesh_instance.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	_cursor_mesh_instance.material_override = _cursor_mat
	add_child(_cursor_mesh_instance)


func _free_carrier() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
	_mesh_instance = null
	_mat = null
	if _cursor_mesh_instance != null and is_instance_valid(_cursor_mesh_instance):
		_cursor_mesh_instance.queue_free()
	_cursor_mesh_instance = null
	_cursor_mat = null


## The live baked-mesh carrier (null before the first register / after the last unregister). For tests.
func carrier() -> MeshInstance3D:
	return _mesh_instance


## The live TEXTURED carrier (the active-cursor tile), or null while no textured type is routed.
func cursor_carrier() -> MeshInstance3D:
	return _cursor_mesh_instance


func _process(delta: float) -> void:
	_elapsed += delta
	if _active.is_empty():
		return
	var cam: Camera3D = _current_camera()
	var view: Transform3D = cam.get_camera_transform().affine_inverse() if cam else Transform3D()
	# The flat carrier resolves its colours on the CPU, so it needs the palette IMAGE; the
	# textured one samples the sheet on the GPU and needs nothing here.
	if _mesh_instance != null and _palette != null:
		_rebuild_mesh(view)
	if _cursor_mesh_instance != null:
		_rebuild_cursor_mesh(view)


func _current_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_viewport().get_camera_3d()


## Rebuild the baked ArrayMesh from all active tiles (positions static, barber-pole COLOR per frame) and
## re-stamp the batch's fold order via Fold.add. One carrier == one render_layer_order: the tiles are
## additive (order-independent) ground decals that never overlap each other, so a single representative
## bucket (the mean tile centroid) suffices; per-fragment DEPTH (CUSTOM0) handles occlusion vs map/units.
func _rebuild_mesh(view: Transform3D) -> void:
	var manual: int = TileOverlayConfig.of().manual_phase()
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var centroid_sum := Vector3.ZERO
	var tile_count := 0
	for tile in _active:
		if not is_instance_valid(tile):
			continue
		if is_textured(_active[tile]):
			continue  # the cursor tile lives on its own carrier (_rebuild_cursor_mesh)
		if _append_tile(tile, _active[tile], manual, positions, colors, uvs, custom0):
			tile_count += 1
			# The last vertex's CUSTOM0 is this tile's lifted centroid; accumulate for the batch key.
			centroid_sum += Vector3(custom0[custom0.size() - 3], custom0[custom0.size() - 2], custom0[custom0.size() - 1])

	var mesh := ArrayMesh.new()
	if not positions.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		var cf := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, cf)
	_mesh_instance.mesh = mesh

	# Stamp the batch fold order from the mean tile centroid (STANDARD depth). Empty batch -> bucket 0.
	var order_z := 0.0
	if tile_count > 0:
		order_z = DepthMode.ot_order_z(centroid_sum / float(tile_count), view, TILE_DEPTH_MODE)
	Fold.add(_mesh_instance, _mat, order_z)


## Rebuild the TEXTURED carrier (the active-cursor tile) and stamp ITS OWN fold order.
##
## Same baked ground quad as the flat carrier — per-corner terrain Y so it drapes, one shared
## CUSTOM0 centroid so the face has one OT depth (ADR-0009) — with two differences:
##
##  1. REAL UVs. The shader samples the RANGETILE sheet through them (tile_uv_offset +
##     UV * tile_uv_size), so the corners map to a unit square exactly as the in-scene
##     highlight mesh does in Tile.gd. The flat carrier writes Vector2.ZERO because its
##     shader never samples anything.
##  2. ITS OWN ORDER KEY, from its own centroid. This carrier is what the unit shadow is
##     ordered against, and the flat carrier's key — the MEAN centroid of every routed tile
##     on the map — could not answer that question: the shadow must land AFTER the tile it
##     overlaps in the fold scratch (add-then-sub), and that comparison only means anything
##     against the cursor tile's own depth. See UnitShadow._stamp_fold_order / FOLD_RANK.
func _rebuild_cursor_mesh(view: Transform3D) -> void:
	var manual: int = TileOverlayConfig.of().manual_phase()
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var centroid_sum := Vector3.ZERO
	var tile_count := 0
	var type := -1
	for tile in _active:
		if not is_instance_valid(tile) or not is_textured(_active[tile]):
			continue
		if _append_tile(tile, _active[tile], manual, positions, colors, uvs, custom0, true):
			type = int(_active[tile])
			tile_count += 1
			centroid_sum += Vector3(custom0[custom0.size() - 3], custom0[custom0.size() - 2], custom0[custom0.size() - 1])

	var mesh := ArrayMesh.new()
	if not positions.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		var cf := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, cf)
	_cursor_mesh_instance.mesh = mesh
	if tile_count == 0:
		return

	# Push the per-type CLUT params (palette_row / anim_mode / tint / mono / phase_rate /
	# flat_index) + the global UV crop and manual_phase. Params only — apply_to_material would
	# swap in an IN-SCENE shader and the carrier would stop folding.
	TileOverlayConfig.of().apply_params_to_material(_cursor_mat, type)

	var order_z := DepthMode.ot_order_z(centroid_sum / float(tile_count), view, TILE_DEPTH_MODE)
	Fold.add(_cursor_mesh_instance, _cursor_mat, order_z)


## Append one tile's ground-decal quad (2 tris, 6 verts) to the batch arrays. Each corner keeps its OWN
## world Y plus [constant DECAL_LIFT], so the decal DRAPES over the terrain it marks. Per-vertex COLOR =
## the resolved barber-pole color; CUSTOM0 = the shared lifted centroid (ADR-0009 flat face depth).
## Returns false if the tile has no 4-corner quad.
##
## [b]"world_quad" is about BILLBOARDING, not about being level[/b] (ADR-0250). This used to flatten all
## four corners to the centroid Y, and the comment called that "slope dropped — a slope-conforming decal
## would be Path 2". There is no Path 2: `tile.tile_vertices` already ARE the slope-conforming corners
## (`terrain.json` ships four per-corner vertices per tile, and the in-scene highlight path at
## `Tile.gd` uses them verbatim), so conforming costs one expression and no new data. The flatten was
## the billboard fix over-applied — `geometry = world_quad` means the verts are baked GROUND positions
## rather than expanded about a centroid at draw time, which a sloped quad satisfies exactly.
##
## [b]The DEPTH stays flat, and that is a different axis.[/b] CUSTOM0 remains the single shared centroid,
## so `ot_depth` gives the whole quad ONE depth — the PSX GTE's own AVSZ4 model for a face (ADR-0009).
## Per-corner depth would be a real regression and is guarded separately. [MapGridOverlay] is the
## precedent: the other baked world-space mesh in this addon, through the same fold, keeps per-corner Y
## and shares one centroid for exactly this reason.
## `textured` writes the RANGETILE corner UVs instead of Vector2.ZERO — see _rebuild_cursor_mesh.
func _append_tile(tile: Node, type: int, manual_phase: int, positions: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array, custom0: PackedFloat32Array,
		textured: bool = false) -> bool:
	var verts: PackedVector3Array = tile.tile_vertices
	if verts.size() != 4:
		return false
	var xform: Transform3D = tile.global_transform
	var world: Array[Vector3] = []
	var centroid := Vector3.ZERO
	for v in verts:
		var w: Vector3 = xform * v
		world.append(w)
		centroid += w
	centroid /= 4.0
	# The DEPTH anchor is still the single lifted centroid — one face, one OT depth (ADR-0009).
	var c := Vector3(centroid.x, centroid.y + DECAL_LIFT, centroid.z)
	# The textured carrier's shader ignores COLOR (it samples the CLUT itself) and its
	# rebuild does not need `_palette` at all, so don't resolve a colour it will not read —
	# `_tile_color` needs the palette IMAGE, which may legitimately be absent there.
	var color := Color.WHITE if textured else _tile_color(type, manual_phase)
	# Slope-conforming ground quad: each corner at its OWN world Y, lifted clear of the surface it
	# marks. On a Flat tile this is identical to the old centroid flatten, which is why the change is
	# invisible on level ground and obvious on an incline.
	var tl := world[0] + Vector3(0.0, DECAL_LIFT, 0.0)
	var tr := world[1] + Vector3(0.0, DECAL_LIFT, 0.0)
	var br := world[2] + Vector3(0.0, DECAL_LIFT, 0.0)
	var bl := world[3] + Vector3(0.0, DECAL_LIFT, 0.0)
	# The 4 corners map to a unit square, in the SAME order as the corners themselves; the
	# shader scales this into the 14x14 tile sub-rect of the sheet (matching Tile.gd's
	# in-scene highlight mesh). All-zero for the flat carrier, whose shader never samples.
	var corner_uv := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	# Two triangles: (tl, tr, br) and (tl, br, bl). cull_disabled, so winding is irrelevant.
	var quad := [tl, tr, br, tl, br, bl]
	var quad_uv := [0, 1, 2, 0, 2, 3]
	for i in quad.size():
		positions.append(quad[i])
		colors.append(color)
		uvs.append(corner_uv[quad_uv[i]] if textured else Vector2.ZERO)
		custom0.append(c.x); custom0.append(c.y); custom0.append(c.z)
	return true


## The resolved additive color for `type` at the current phase, via the CPU barber-pole (TileOverlayColor).
func _tile_color(type: int, manual_phase: int) -> Color:
	var phase_rate: float = float(TileOverlayConfig.get_param(type, "phase_rate"))
	var phase: int = TileOverlayColor.phase_at(_elapsed, phase_rate, manual_phase)
	# NOTE: srgb_gamma is intentionally NOT passed — the routed tile adds its RAW display-space CLUT
	# color (ADR-0074 endgame, mirror formation_box_fold). The per-type srgb_gamma config param still
	# drives the IN-SCENE tile_overlay.gdshaderinc pow (tonemapped back); it just doesn't touch the fold.
	return TileOverlayColor.flat_color(
		_palette,
		int(TileOverlayConfig.get_param(type, "palette_row")),
		int(TileOverlayConfig.get_param(type, "flat_index")),
		int(TileOverlayConfig.get_param(type, "anim_mode")),
		phase,
		bool(TileOverlayConfig.get_param(type, "mono")),
		TileOverlayConfig.get_param(type, "tint"))
