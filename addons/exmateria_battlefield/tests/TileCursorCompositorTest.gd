extends Node
## Guards TileCursorCompositor — the tile cursor's SEMI-TRANS outline, now a DIRECT billboard node in
## the display-space fold (ADR-0074 ④c, issue #229) rather than a pool-staged UnifiedPrimStager producer.
## Locks (1) the monomorphic cursor_fold shader contract (compositor_layer + baked billboard / paletted /
## STP-window / anchor-PAR axes), (2) that the producer builds a direct MeshInstance3D carrier and routes
## through Fold.add at TILE_OVERLAY depth, and (3) that the cursor.blend_mode knob SELECTS a monomorphic
## blend material (sub/add/mix) — material selection, not an übershader. Pure GDScript + file reads.
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — this test
## is addon-owned and runs in a STRANGER project, not in the host. Directly:
## <GODOT> --path . res://addons/exmateria_battlefield/tests/TileCursorCompositorTest.tscn)

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const Producer = preload("res://addons/exmateria_battlefield/cursor/TileCursorCompositor.gd")

var _failed := false

## ADR-0194 dec. 12 arm 2, added in the commit that moved this file and the only
## edit a move-only loop permits. The `_failed` boolean above can report THAT
## something broke and never how much ran, so a green line described a run of
## unknown size — and a test that moves to a different project and quietly stops
## asserting looks exactly like one that passes.
var _passes: int = 0
var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("[FAIL] %s" % msg)
		_failed = true
	else:
		_passes += 1


func _declares_fold(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
	return re.search(src) != null


func _ready() -> void:
	_test_shader_is_monomorphic_fold()
	_test_producer_builds_direct_carrier()
	_test_blend_mode_selects_material()

	if _passes + _fails == 0:
		print("[FAIL] ran zero assertions — nothing was checked, which is not a pass")
		_failed = true
	print("=== TileCursorCompositorTest: %d passed, %d failed ===" % [_passes, _fails])

	if _failed:
		print("[FAIL] TileCursorCompositor test")
	else:
		print("[PASS] TileCursorCompositor: monomorphic cursor_fold shaders (paletted/billboard/STP-window/anchor-PAR) + direct-carrier Fold.add at TILE_OVERLAY + blend-mode material selection")
	get_tree().quit()


## The cursor_fold materials ARE the contract: three monomorphic wrappers (blend only) over a shared body.
func _test_shader_is_monomorphic_fold() -> void:
	var sub := FileAccess.get_file_as_string(Producer.CURSOR_FOLD_SUB.resource_path)
	var add := FileAccess.get_file_as_string(Producer.CURSOR_FOLD_ADD.resource_path)
	var mix := FileAccess.get_file_as_string(Producer.CURSOR_FOLD_MIX.resource_path)
	var body := FileAccess.get_file_as_string("res://addons/exmateria_battlefield/cursor/cursor_fold.gdshaderinc")
	# Each wrapper declares compositor_layer + exactly its own blend (monomorphic — no in-shader branching).
	_check(_declares_fold(sub) and "blend_sub" in sub, "cursor_fold_sub: compositor_layer + blend_sub")
	_check(_declares_fold(add) and "blend_add" in add, "cursor_fold_add: compositor_layer + blend_add")
	_check(_declares_fold(mix) and "blend_mix" in mix, "cursor_fold_mix: compositor_layer + blend_mix")
	# The shared body bakes the cursor's other four axes.
	_check(not body.is_empty(), "cursor_fold body readable")
	_check("INV_VIEW_MATRIX" in body, "baked axis: camera-facing billboard geometry")
	_check("palette_texture" in body and "range_sheet" in body, "baked axis: paletted RANGETILE sampling")
	_check("col.a > 0.9" in body, "baked axis: STP-window discard (drop opaque)")
	_check("pixel_aspect" in body, "baked axis: anchor-PAR")


## The producer builds a direct MeshInstance3D carrier and routes it via Fold.add at TILE_OVERLAY depth.
func _test_producer_builds_direct_carrier() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var prod = Producer.new()
	prod.setup(parent, _dummy_indexed(), _dummy_palette(), 9)
	var mi = prod.carrier()
	_check(mi != null and mi is MeshInstance3D, "producer builds a MeshInstance3D carrier")
	_check(mi != null and mi.get_parent() == parent, "carrier is parented under the owner node")
	_check(mi != null and mi.mesh is QuadMesh, "carrier is a QuadMesh billboard")

	var view := Transform3D()
	var origin := Vector3(0.0, 1.0, -5.0)
	prod.publish_cursor(view, origin, 0.4, 1.0, Vector4(0.1, 0.2, 0.3, 0.4), 4, 2, 1.0)
	_check(mi != null and mi.visible, "publish_cursor shows the carrier")
	var expect := DepthMode.render_layer_order_for(
		DepthMode.ot_order_z(origin, view, DepthMode.Mode.TILE_OVERLAY))
	_check(mi != null and mi.render_layer == Fold.FOLD_LAYER,
		"publish_cursor joins the shared fold layer via Fold.add (render_layer membership)")
	_check(mi != null and mi.render_layer_order == expect,
		"publish_cursor stamps render_layer_order via Fold.add at TILE_OVERLAY depth")
	# The QuadMesh hangs up from the tip (bottom edge at the model origin).
	var quad: QuadMesh = mi.mesh
	_check(is_equal_approx(quad.center_offset.y, 0.5), "QuadMesh centre-offset hangs the sprite up from the tip")

	prod.publish_empty()
	_check(mi != null and not mi.visible, "publish_empty hides the carrier (nothing folds)")
	prod.release()
	_check(prod.carrier() == null, "release drops the carrier reference")


## The cursor.blend_mode knob selects a monomorphic blend material (sub/add), not an in-shader branch.
func _test_blend_mode_selects_material() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var prod = Producer.new()
	prod.setup(parent, _dummy_indexed(), _dummy_palette(), 9)
	var mi = prod.carrier()
	var view := Transform3D()
	var origin := Vector3.ZERO

	prod.publish_cursor(view, origin, 0.4, 1.0, Vector4(0, 0, 1, 1), 4, 2, 1.0)  # subtractive
	# IDENTITY, not path equality: MODE_SHADER holds preloaded Shaders now (Amendment 4 §2), so this
	# asserts the material wears THE const rather than any shader that happens to share its path.
	_check(mi.material_override is ShaderMaterial and mi.material_override.shader == Producer.CURSOR_FOLD_SUB,
		"blend_mode 2 selects the subtractive material")
	prod.publish_cursor(view, origin, 0.4, 1.0, Vector4(0, 0, 1, 1), 4, 1, 1.0)  # additive
	_check(mi.material_override.shader == Producer.CURSOR_FOLD_ADD,
		"blend_mode 1 selects the additive material")

	prod.release()


func _dummy_indexed() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)


func _dummy_palette() -> ImageTexture:
	var img := Image.create(16, 9, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
