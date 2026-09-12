extends RefCounted
## Folds the tile cursor's SEMI-TRANS (STP=1) outline into the display-space fold as a DIRECT billboard
## node (ADR-0074 ④c, issue #229): a MeshInstance3D wearing a monomorphic cursor_fold material (paletted
## billboard, STP-window discard, anchor-PAR, TILE_OVERLAY depth), handed to Fold.add each frame.
##
## Supersedes the old pool-borrow path: the cursor no longer stages an ADR-0040 record through
## UnifiedPrimStager into an EffectMultiMeshPool slot (the pool is for genuine high-count particle
## producers, not a one-quad sprite). The cursor's OPAQUE body still draws in-scene (canvas + depth);
## this folds ONLY the outline. The sprite hangs UP from its pivot (the dagger tip): the QuadMesh is
## centre-offset so its bottom edge sits at the model origin.
##
## Palette: the cursor samples the indexed RANGETILE sheet -> its 9-row RANGETILE CLUT (BATTLE.BIN slot
## 4); the material carries both textures + palette_rows=9 + the CLUT row.
##
## BLEND is the one axis the cursor picks at runtime (the cursor.blend_mode debug knob): setup() builds
## one monomorphic material per SEMI mode (mix/add/sub, + add25 = add with level_scale 0.25) and
## publish() SELECTS one by mode. That is material selection among monomorphic shaders, not an
## übershader (ADR-0074) — the callback picks its material the same way.

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

const CURSOR_FOLD_SUB := preload("res://addons/exmateria_battlefield/cursor/cursor_fold_sub.gdshader")
const CURSOR_FOLD_ADD := preload("res://addons/exmateria_battlefield/cursor/cursor_fold_add.gdshader")
const CURSOR_FOLD_MIX := preload("res://addons/exmateria_battlefield/cursor/cursor_fold_mix.gdshader")
# SEMI blend mode (0 mix / 1 add / 2 sub / 3 add25) -> fold shader. add25 reuses the add shader with
# level_scale 0.25 (set per-material below), so it maps to the same file.
const MODE_SHADER := {0: CURSOR_FOLD_MIX, 1: CURSOR_FOLD_ADD, 2: CURSOR_FOLD_SUB, 3: CURSOR_FOLD_ADD}
# Subtractive (2) — the shipped default, used when a caller passes an out-of-range blend mode.
const CURSOR_DEFAULT_MODE := 2
# DepthMode TILE_OVERLAY — the floating cursor sorts in front of the tile + range overlays (same mode
# the in-scene cursor shader used). Occlusion for mode 7 is approximate (the GPU ot_depth covers 0..5)
# but the cursor floats above the map with nothing to occlude it (handoff-sanctioned).
const CURSOR_DEPTH_MODE := DepthMode.Mode.TILE_OVERLAY

var _mesh: MeshInstance3D = null
var _mats: Dictionary = {}   # SEMI mode -> ShaderMaterial


## Build the billboard carrier under `parent` (TileCursor) and its per-mode monomorphic materials, wearing
## the indexed RANGETILE sheet + its CLUT. `palette_rows` is the CLUT height (9 for RANGETILE). Call once.
func setup(parent: Node3D, range_tex: Texture2D, range_palette: Texture2D, palette_rows: int) -> void:
	if parent == null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.mesh = QuadMesh.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The billboard rewrites MODELVIEW in the vertex stage, so a generous AABB keeps it from culling.
	_mesh.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_mesh.visible = false
	for mode in MODE_SHADER:
		var m := ShaderMaterial.new()
		m.shader = MODE_SHADER[mode]
		m.set_shader_parameter("range_sheet", range_tex)
		m.set_shader_parameter("palette_texture", range_palette)
		m.set_shader_parameter("palette_rows", float(palette_rows))
		m.set_shader_parameter("level_scale", 0.25 if mode == 3 else 1.0)
		_mats[mode] = m
	parent.add_child(_mesh)


## Place the outline billboard and stamp its fold order.
##   `view`        world->view transform for the OT fold-order key.
##   `origin`      the sprite PIVOT (dagger TIP) in world space — the billboard hangs UP from here.
##   `half_width`  billboard half-width in WORLD units (CURSOR_ASPECT_W * 0.5 * cursor_scale).
##   `height`      full sprite height in WORLD units (cursor_scale) — the sprite hangs up from the tip.
##   `uv_rect`     the sprite's RANGETILE sub-rect (xy origin, zw size, normalized). A Vector4, NOT a
##                 Color: set_shader_parameter sRGB-linearizes a Color's RGB into a `vec4` uniform,
##                 crushing the U-width (0.0508 -> ~0.003) and collapsing the sample onto one column.
##   `palette_row` CLUT row (cursor = 4); `blend_mode` the SEMI mode (0 mix/1 add/2 sub/3 add25).
##   `stretch`     cursor_stretch / fx_stretch — the shader's anchor-PAR re-applies psx_fx_stretch to the
##                 billboard width, so dividing it out here yields the cursor's own psx_cursor_stretch.
func publish_cursor(view: Transform3D, origin: Vector3, half_width: float, height: float,
		uv_rect: Vector4, palette_row: int, blend_mode: int, stretch: float) -> void:
	if _mesh == null:
		return
	var mode: int = blend_mode if _mats.has(blend_mode) else CURSOR_DEFAULT_MODE
	var mat: ShaderMaterial = _mats[mode]
	mat.set_shader_parameter("uv_rect", uv_rect)
	mat.set_shader_parameter("palette_row", float(palette_row))
	# The QuadMesh hangs UP from the tip: centre-offset it so the bottom edge sits at the model origin.
	var quad: QuadMesh = _mesh.mesh
	quad.size = Vector2(2.0 * half_width * stretch, height)
	quad.center_offset = Vector3(0.0, height * 0.5, 0.0)
	_mesh.visible = true
	_mesh.global_position = origin
	var order_z := DepthMode.ot_order_z(origin, view, CURSOR_DEPTH_MODE)
	Fold.add(_mesh, mat, order_z)


## Hide the outline (cursor hidden / off-grid) so nothing folds, keeping the carrier for a cheap re-show.
func publish_empty() -> void:
	if _mesh != null:
		_mesh.visible = false


## Free the carrier when the cursor leaves the tree.
func release() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.queue_free()
	_mesh = null
	_mats = {}


## The live carrier (null before setup / after release). For tests + callers that need the node.
func carrier() -> MeshInstance3D:
	return _mesh
