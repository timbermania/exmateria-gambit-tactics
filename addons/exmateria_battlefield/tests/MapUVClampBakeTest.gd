extends Node
## Pure-logic guard (no GPU/scene): DynamicGeometryBuilder bakes each triangle's UV
## bounding box into CUSTOM2 (RGBA_FLOAT = uv_min.xy, uv_max.xy), so the indexed_color
## shader can clamp texel sampling to the polygon's own atlas patch and stop reading the
## transparent neighbor texel at patch edges (the "background sliver / diagonal speckle"
## seam — covered fragments proven via the magenta discard-probe).
##
## Why the per-TRIANGLE bbox is the right patch rect: a quad's texture patch is split into
## two triangles sharing the diagonal, and each half's 3 UVs already span both u- and both
## v-extremes, so its bbox == the whole patch. Both halves carry the same rect → clamping
## restricts to the patch without introducing a diagonal seam.
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — this test
## is addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . --quit-after 5 res://addons/exmateria_battlefield/tests/MapUVClampBakeTest.tscn)

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const VisualGeometryIndex = preload("res://addons/exmateria_battlefield/terrain/VisualGeometryIndex.gd")


const DynamicGeometryBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicGeometryBuilder.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_custom2_3_carry_triangle_uv_verts()

	print("\n=== MapUVClampBakeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] MapUVClampBakeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] MapUVClampBakeTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapUVClampBakeTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_floats_approx(got: PackedFloat32Array, want: PackedFloat32Array, name: String) -> void:
	if got.size() != want.size():
		_failed += 1
		print("  [FAIL] %s: size got=%d want=%d" % [name, got.size(), want.size()])
		return
	for i in range(want.size()):
		if abs(got[i] - want[i]) > 0.0001:
			_failed += 1
			print("  [FAIL] %s: idx %d got=%f want=%f" % [name, i, got[i], want[i]])
			return
	_passed += 1


# --- fixtures ----------------------------------------------------------------

func _make_triangle(uvs: Array[Vector2]) -> VisualGeometryIndex.TriangleData:
	return VisualGeometryIndex.TriangleData.new(
		0, 0, 0,
		[0, 1, 2] as Array[int],
		[Vector3.ZERO, Vector3.RIGHT, Vector3.BACK] as Array[Vector3],
		uvs,
		[Vector3.UP, Vector3.UP, Vector3.UP] as Array[Vector3],
		0, "StoneFloor", Vector2i(0, 0), ""
	)


# --- tests -------------------------------------------------------------------

## Tracer bullet: the triangle's 3 UV verts are baked constant across the face —
## CUSTOM2 = (v0.xy, v1.xy) and CUSTOM3 = (v2.xy), the SAME values on all 3 vertices,
## so the shader reads them back as per-face constants for the perimeter-aware snap.
func _test_custom2_3_carry_triangle_uv_verts() -> void:
	var builder := DynamicGeometryBuilder.new()
	var tri := _make_triangle([Vector2(0.2, 0.3), Vector2(0.5, 0.3), Vector2(0.2, 0.8)] as Array[Vector2])

	var arrays: Array = builder._build_surface_arrays([tri] as Array[VisualGeometryIndex.TriangleData])
	var custom2: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM2]
	var custom3: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM3]

	# CUSTOM2 = v0.xy, v1.xy per vertex (x3); CUSTOM3 = v2.xy per vertex (x3).
	_assert_floats_approx(custom2, PackedFloat32Array([
		0.2, 0.3, 0.5, 0.3,
		0.2, 0.3, 0.5, 0.3,
		0.2, 0.3, 0.5, 0.3,
	]), "custom2 = (v0,v1) x3")
	_assert_floats_approx(custom3, PackedFloat32Array([
		0.2, 0.8, 0.2, 0.8, 0.2, 0.8,
	]), "custom3 = v2 x3")
