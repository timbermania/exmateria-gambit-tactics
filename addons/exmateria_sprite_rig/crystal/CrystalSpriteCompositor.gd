extends RefCounted
## Folds the {92} "turn to crystal" diamond billboard into the display-space fold as a DIRECT node
## (ADR-0074 ④a, issue #229): a camera-facing MeshInstance3D wearing the monomorphic
## `crystal_fold.gdshader` (billboard / alpha_key / NO-PAR / additive), handed to Fold.add each frame.
##
## Supersedes the old pool-borrow path: the crystal no longer stages an ADR-0040 record through
## UnifiedPrimStager into an EffectMultiMeshPool slot — the pool is for genuine high-count particle
## producers, not a one-quad sprite (ADR-0074). CrystalSprite3D owns one of these, calls setup() once
## to build the carrier under itself, then publish_crystal() each frame to advance the animation cell
## and re-stamp fold order. The whole sprite folds (it has no opaque part); the in-scene pow(2.2)
## sRGB->linear is dropped by design (the fold blends in display space).

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

const CRYSTAL_FOLD_SHADER := preload("res://addons/exmateria_sprite_rig/crystal/crystal_fold.gdshader")
# DepthMode.STANDARD — the crystal sorts at the unit's natural projected depth (the fold shader's
# ot_depth(..., 0)); occlusion is exact via the shared opaque depth bind.
const CRYSTAL_DEPTH_MODE := DepthMode.Mode.STANDARD

var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null


## Build the billboard carrier under `parent` (CrystalSprite3D) and wear the crystal_fold material with
## the 8-frame RGBA sheet. `size` is the billboard footprint in WORLD units (width x height). Call once.
func setup(parent: Node3D, sheet: Texture2D, size: Vector2) -> void:
	if parent == null:
		return
	var quad := QuadMesh.new()
	quad.size = size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = quad
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The billboard rewrites MODELVIEW in the vertex stage, so a tight mesh AABB frustum-culls wrongly;
	# a generous custom AABB keeps it drawn whenever the unit is on screen.
	_mesh.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_mat = ShaderMaterial.new()
	_mat.shader = CRYSTAL_FOLD_SHADER
	_mat.set_shader_parameter("crystal_sheet", sheet)
	_mesh.material_override = _mat
	parent.add_child(_mesh)


## Advance to the current animation cell and place the crystal in the fold order.
##   `view`     world->view transform for the OT fold-order key (camera transform inverse).
##   `origin`   the diamond CENTRE in world space (the carrier sits here — CrystalSprite3D's position).
##   `uv_rect`  the current frame's sub-rect (xy origin, zw size, normalized) of the 8-frame sheet. A
##              Vector4, NOT a Color: set_shader_parameter sRGB-linearizes a Color's RGB into a `vec4`
##              uniform, crushing the cell width so every column samples one texel.
## No-op before setup() (a bare unit test with no compositor).
func publish_crystal(view: Transform3D, origin: Vector3, uv_rect: Vector4) -> void:
	if _mesh == null:
		return
	_mesh.visible = true
	_mat.set_shader_parameter("uv_rect", uv_rect)
	var order_z := DepthMode.ot_order_z(origin, view, CRYSTAL_DEPTH_MODE)
	Fold.add(_mesh, _mat, order_z)


## Hide the crystal (mid-spawn / despawn) so nothing folds, keeping the carrier for a cheap re-show.
func publish_empty() -> void:
	if _mesh != null:
		_mesh.visible = false


## Free the carrier when the crystal leaves the tree (unit despawn).
func release() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.queue_free()
	_mesh = null
	_mat = null


## The live carrier (null before setup / after release). For tests + callers that need the node.
func carrier() -> MeshInstance3D:
	return _mesh
