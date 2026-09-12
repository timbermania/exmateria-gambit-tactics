class_name UnitShadow
extends RefCounted

## Faithful FFT PSX unit shadow renderer.
##
## Source of truth: research/working_documents/UNIT_SHADOW_RENDERING.md.
##
## The PSX shadow is a single POLY_FT4 (GPU code 0x2E): a FIXED 20x20 world-unit
## textured quad, pinned to the terrain tile under the unit's *animated ground*
## position, subtractively blended (TPAGE 0x5F / ABR mode 2), draped onto slopes,
## and inserted at the unit's own depth. Crucially it is NOT welded to the sprite:
## the footprint never scales with jump/fly height, never fades, and never
## billboards to the camera — it just slides along the ground and snaps its Y to
## whatever tile it is over. Only the sprite billboards; the shadow is a ground decal.
##
## This replaces the earlier made-up blob (camera-facing, grows +50%/unit of height,
## fades with height, multiply-blended). See §6 of the living doc for the full gap list.

## Footprint: PSX +/-10 world units = 20 units, and one FFT tile is 28 units
## (PsxMagnitude.UNITS_PER_TILE) = 1.0 Godot unit (MapConstants: FFT tile scaled to
## 1.0). So the quad is 20/28 = 0.714 Godot units square. Set on the mesh in Unit.tscn;
## kept here as the authoritative source for reference / rebuilds.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## The shadow's two shaders — the display-space fold twin and its in-scene fallback.
## Preloaded `Shader` OBJECTS, never paths (ADR-0191 dec. 11): a `load()` on a mistyped
## path returns null and a null shader here does not raise — the fold "just stops, with
## no error". Fold.shader() picks between them on Fold.owns().
const SHADOW_FOLD_SHADER := preload("res://assets/shaders/shadow_blob_fold.gdshader")
const SHADOW_SCENE_SHADER := preload("res://assets/shaders/shadow_blob.gdshader")

## Fold sub-bucket rank (DepthMode.render_layer_order_for). The ground decals the shadow
## overlaps — the additive cursor / placement tile overlays — stamp rank 0, so a shadow that
## lands in the SAME OT bucket as the tile it drapes still paints AFTER it. That order is the
## whole point: PSX blends in the display framebuffer with a per-step clamp, and clamping is
## non-commutative — add-then-sub leaves `255 - s` where sub-then-add saturates to white and
## erases the shadow. The bucket (unit rep point, one hair nearer than the tile) normally
## decides this on its own; the rank is what makes it decided rather than lucky.
const FOLD_RANK := 1

const FOOTPRINT: float = 20.0 / 28.0  # 0.714... Godot units

# References (set during initialization)
var _shadow_mesh: MeshInstance3D
var _shadow_raycast: RayCast3D
var _shadow_material: ShaderMaterial

## Show flag — the PSX unit[0x298]. Toggled by anim opcode 0xE0 (HideShadow) /
## 0xE1 (ShowShadow) and event instruction 0x4E ("Unit Shadow"). Default on.
var _enabled: bool = true

## Last OT representative point pushed by update() — the SAME world point the sprite
## projects. The shader gets it as a uniform (per-fragment DEPTH) and the fold stamp
## gets it as the CPU ordering key, so both keys are the one point, never two spellings.
var _depth_point: Vector3 = Vector3.ZERO


func initialize(shadow_mesh: MeshInstance3D, shadow_raycast: RayCast3D, _camera_renderer = null) -> void:
	"""Initialize shadow with node references.

	Args:
		shadow_mesh: The MeshInstance3D used to render the shadow (flat quad, FACE_Y).
		shadow_raycast: The RayCast3D used to sample terrain height/normal under the unit.
		_camera_renderer: Unused — the shadow is ground-locked and never billboards.
			Kept in the signature so callers don't have to change.
	"""
	_shadow_mesh = shadow_mesh
	_shadow_raycast = shadow_raycast

	_initialize_material()


func _initialize_material() -> void:
	"""Duplicate the shadow material (so per-unit intensity could differ) and ensure
	the ROM shadow texture is bound."""
	if not _shadow_mesh or not _shadow_mesh.mesh:
		return

	# For PrimitiveMesh (QuadMesh) the material lives on .material.
	var base_shadow_mat = _shadow_mesh.mesh.surface_get_material(0)
	if not base_shadow_mat and _shadow_mesh.mesh is PrimitiveMesh:
		base_shadow_mat = _shadow_mesh.mesh.material

	if base_shadow_mat:
		_shadow_material = base_shadow_mat.duplicate()
		_shadow_mesh.mesh = _shadow_mesh.mesh.duplicate()
		if _shadow_mesh.mesh is PrimitiveMesh:
			_shadow_mesh.mesh.material = _shadow_material
		else:
			_shadow_mesh.mesh.surface_set_material(0, _shadow_material)

	# Bind the ROM-extracted 20x20 radial blob if the scene didn't already.
	if _shadow_material and _shadow_material.get_shader_parameter("shadow_tex") == null:
		var tex = load("res://assets/materials/unit_shadow.png")
		if tex:
			_shadow_material.set_shader_parameter("shadow_tex", tex)

	# Push the unified OT-depth calibration (ADR-0009). The shadow is a single quad on
	# the per-object path in SHADOW mode: it does NOT sort by its own geometry — it
	# co-sorts with the unit by projecting the SAME point the sprite does (pushed each
	# frame as `unit_depth_point` in update()), faithful to the PSX inserting the shadow
	# at the unit's own OT slot. It thus inherits the unit's front-of-terrain bucket
	# (never z-fights the floor) and sorts one hair behind the sprite. See
	# shadow_blob.gdshader and UNIT_SHADOW_RENDERING.md §2.
	if _shadow_material:
		DepthMode.apply(_shadow_material, DepthMode.Mode.SHADOW)
		# On the Forward+ fork the blob is a display-space fold member; off-fork it draws
		# in-scene. Same fragment either way — the twin adds only `compositor_layer`.
		_shadow_material.shader = Fold.shader(SHADOW_FOLD_SHADER, SHADOW_SCENE_SHADER)


func set_enabled(enabled: bool) -> void:
	"""Set the PSX show-flag (unit[0x298]). When false the shadow is hidden regardless
	of ground; maps to anim opcode 0xE0 HideShadow / event 0x4E."""
	_enabled = enabled
	if not enabled and _shadow_mesh:
		_shadow_mesh.visible = false


func update(unit_global_position: Vector3, unit_depth_point: Vector3 = Vector3.INF) -> void:
	"""Pin the shadow to the terrain under the unit's animated ground X/Z, and co-sort
	its DEPTH with the unit sprite.

	GEOMETRY and DEPTH are decoupled — exactly as on PSX:
	- GEOMETRY: the quad sits on the terrain. The unit's own vertical position is
	  ignored for the shadow's Y — we raycast straight down to the surface (matching the
	  PSX which sets every corner to the *tile* surface height and discards the airborne
	  unit Y), then orient the quad to the terrain normal so it lies flat on slopes.
	  Size is constant; no opacity fade; no camera billboarding.
	- DEPTH: sorts NOT by the quad's own ground point but by the UNIT's representative
	  point (`unit_depth_point`, the same world point the sprite projects). Pushed to the
	  shader so shadow-vs-world sorting == sprite-vs-world sorting — reproducing the PSX
	  inserting the shadow at the unit's own OT slot (ot_base + unit[0x128]*4). This is
	  what keeps the shadow off the floor it drapes AND under the sprite.

	Args:
		unit_global_position: The unit's current global position. Only X/Z are used to
			place the decal; Y comes from the terrain raycast.
		unit_depth_point: The sprite's OT representative point (mesh origin +
			depth_center_height), for co-sorting. Vector3.INF (default) leaves the last
			value in place — callers that know it should always pass it.
	"""
	if not _shadow_mesh or not _shadow_raycast:
		return

	# Feed the sprite's depth key to the shadow shader so it co-sorts with the unit.
	if unit_depth_point.x != INF:
		_depth_point = unit_depth_point
		if _shadow_material:
			_shadow_material.set_shader_parameter("unit_depth_point", unit_depth_point)

	if not _enabled:
		_shadow_mesh.visible = false
		return

	# The raycast is parented to the unit and points straight down; force an update
	# since we sample it outside the physics step.
	_shadow_raycast.force_raycast_update()

	if not _shadow_raycast.is_colliding():
		# Unit over the void — nothing to cast onto.
		_shadow_mesh.visible = false
		return

	_shadow_mesh.visible = true
	var hit_point: Vector3 = _shadow_raycast.get_collision_point()
	var normal: Vector3 = _shadow_raycast.get_collision_normal()
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP

	# Build a basis whose local +Y (the FACE_Y quad's normal) aligns with the terrain
	# normal, draping the flat quad onto the slope. In-plane orientation is arbitrary —
	# the blob is radially symmetric — so any perpendicular pair works.
	var up: Vector3 = normal.normalized()
	var ref: Vector3 = Vector3.FORWARD
	if absf(up.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(up).normalized()
	var z_axis: Vector3 = up.cross(x_axis).normalized()

	# Place the quad exactly on the terrain surface — no world-space lift. Sort ordering
	# is owned entirely by the unified OT depth: the shadow shader writes DEPTH via SHADOW
	# mode (9 — NOT TILE_OVERLAY, which this comment used to name), which nudges the decal
	# in front of the tile it drapes and behind the sprite. That retires the old world-space
	# Y bias (ADR-0009: the DepthMode nudge replaces littered magic-number depth offsets).
	_shadow_mesh.global_transform = Transform3D(
		Basis(x_axis, up, z_axis),
		Vector3(unit_global_position.x, hit_point.y, unit_global_position.z)
	)

	_stamp_fold_order()


## Re-stamp the shadow's display-space fold membership + order key (ADR-0074). Called every
## frame the shadow is visible, because the key is camera-relative: `Fold.add` is idempotent
## and only `order_z` moves. NO-OP off-fork (Fold.add self-gates on Fold.owns()), where the
## in-scene twin draws instead.
##
## The key is the UNIT's representative point in SHADOW mode — the same quantity the shader
## writes as DEPTH, one hair behind the sprite — NOT the quad's ground origin. That is what
## puts the blob in the unit's OT bucket (PSX `ot_base + unit[0x128]*4`), one bucket in front
## of the tile it drapes, so the additive tile overlays composite FIRST and the subtraction
## lands on top of them. FOLD_RANK settles the same-bucket case.
func _stamp_fold_order() -> void:
	if _shadow_material == null:
		return
	var cam: Camera3D = _current_camera()
	if cam == null:
		return
	var view: Transform3D = cam.get_camera_transform().affine_inverse()
	var order_z: float = DepthMode.ot_order_z(_depth_point, view, DepthMode.Mode.SHADOW)
	Fold.add(_shadow_mesh, _shadow_material, order_z, FOLD_RANK)


## The viewport camera the fold order is measured against, or null while the mesh is off-tree
## (a unit mid-spawn) — guarded, because this runs from the per-frame update path.
func _current_camera() -> Camera3D:
	if _shadow_mesh == null or not _shadow_mesh.is_inside_tree():
		return null
	var vp: Viewport = _shadow_mesh.get_viewport()
	return vp.get_camera_3d() if vp != null else null
