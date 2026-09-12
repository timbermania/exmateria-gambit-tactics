extends Node
## Guard for the shared ScreenOverlayQuad base — the one identical, footgun-prone
## recipe every full-screen NDC quad ({76}/{3E}/{7D}/{91}) MUST get right: a 2x2
## QuadMesh, the caller's material as material_override, shadows off, and — critically —
## the oversized custom_aabb that keeps the NDC-remapped corners off frustum cull. Getting
## that AABB wrong makes the overlay silently invisible, so this pins it so the four
## effects can share one call instead of re-copying (and re-risking) the block.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScreenOverlayQuadTest.tscn

const OverlayBase = preload("res://src/core/ScreenOverlayQuad.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_quad_plumbing()
	_test_returns_toggleable_instances()
	_test_all_four_overlays_extend_base()

	print("\n=== ScreenOverlayQuadTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScreenOverlayQuadTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScreenOverlayQuadTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenOverlayQuadTest")
		get_tree().quit(0)


# --- Tests -------------------------------------------------------------------

func _test_quad_plumbing() -> void:
	var overlay: ScreenOverlayQuad = OverlayBase.new()
	add_child(overlay)
	var mat := ShaderMaterial.new()
	var mmi := overlay._make_overlay_quad("TestQuad", mat)

	_assert_true(mmi is MeshInstance3D, "returns a MeshInstance3D")
	_assert_eq(mmi.name, "TestQuad", "names the quad as asked")
	_assert_eq(mmi.material_override, mat, "uses the caller's material as override")
	_assert_true(mmi.mesh is QuadMesh, "mesh is a QuadMesh")
	_assert_eq((mmi.mesh as QuadMesh).size, Vector2(2.0, 2.0), "quad size is 2x2")
	_assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"casts no shadow")
	# The footgun: without this AABB the NDC-remapped corners frustum-cull to nothing.
	_assert_eq(mmi.custom_aabb, ScreenOverlayQuad.CULL_AABB,
		"carries the cull-proof custom_aabb (the invisible-overlay footgun)")
	_assert_eq(mmi.get_parent(), overlay, "parented under the overlay node")

	overlay.queue_free()


func _test_returns_toggleable_instances() -> void:
	# The dual-pass effects build two quads under one node; each must be a distinct
	# instance the caller can flip visible/hidden independently.
	var overlay: ScreenOverlayQuad = OverlayBase.new()
	add_child(overlay)
	var a := overlay._make_overlay_quad("A", ShaderMaterial.new())
	var b := overlay._make_overlay_quad("B", ShaderMaterial.new())
	_assert_true(a != b, "each call makes a distinct quad")
	_assert_eq(overlay.get_child_count(), 2, "both quads parented under the overlay")
	a.visible = false
	_assert_true(not a.visible and b.visible, "per-quad visibility is independent")
	overlay.queue_free()


func _test_all_four_overlays_extend_base() -> void:
	# The whole point of the base: the four screen overlays share it. If any one drifts
	# back to a bare Node3D and re-copies the AABB block, this fails.
	for path in [
		"res://src/scenarios/ScenarioDarkScreen.gd",
		"res://src/scenarios/ScenarioColorScreen.gd",
		"res://src/scenarios/ScenarioShowGraphic.gd",
		"res://src/scenarios/ScenarioMapTitle.gd",
	]:
		var inst = load(path).new()
		_assert_true(inst is ScreenOverlayQuad,
			"%s extends ScreenOverlayQuad" % path.get_file())
		(inst as Node).queue_free()


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
