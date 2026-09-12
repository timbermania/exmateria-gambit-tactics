extends Node
## Guards CrystalSpriteCompositor — the {92} "turn to crystal" diamond, now a DIRECT billboard node in
## the display-space fold (ADR-0074 ④a, issue #229) rather than a pool-borrowing UnifiedPrimStager
## producer. Locks (1) that its shader is a MONOMORPHIC compositor_layer material with the crystal's four
## axes BAKED (billboard / alpha-key / no-PAR / additive), and (2) that the producer builds a direct
## MeshInstance3D carrier and routes it through Fold.add at STANDARD depth. Mirrors
## CallbackFoldRoutingTest's style — pure GDScript + file reads, no GPU / no fork.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CrystalSpriteCompositorTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const CrystalSpriteCompositor = ExMateriaSpriteRig.CrystalSpriteCompositor

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const Producer = ExMateriaSpriteRig.CrystalSpriteCompositor
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _declares_fold(src: String) -> bool:
	# compositor_layer in the RENDER_MODE (line-anchored) — not a mention in a comment.
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
	return re.search(src) != null


func _ready() -> void:
	_test_shader_is_monomorphic_fold()
	_test_producer_builds_direct_carrier()

	if _failed:
		print("[FAIL] CrystalSpriteCompositor test")
	else:
		print("[PASS] CrystalSpriteCompositor: monomorphic compositor_layer shader (billboard/alpha-key/no-PAR/additive) + direct-carrier Fold.add routing at STANDARD depth")
	get_tree().quit()


## The crystal_fold shader IS the contract now (ADR-0074): a compositor_layer material with the four
## axes baked in, not forwarded as data. Read it as text so no GPU/fork is needed to compile it.
func _test_shader_is_monomorphic_fold() -> void:
	# `.resource_path` because the const is a preloaded Shader now (ADR-0191 dec. 11), not a
	# String path. Reading the file as TEXT is still the point — the source contract is checked
	# without a GPU or the fork compiling it.
	var src := FileAccess.get_file_as_string(Producer.CRYSTAL_FOLD_SHADER.resource_path)
	_check(not src.is_empty(), "crystal_fold shader readable")
	_check(_declares_fold(src), "crystal_fold declares compositor_layer in render_mode (routes into the scratch)")
	_check("blend_add" in src, "baked axis: additive blend (blend_add)")
	_check("tex.a < 0.5" in src, "baked axis: alpha-key discard (drops the index-0 key)")
	_check(not ("pixel_aspect" in src), "baked axis: NO PAR (a billboard needs no map stretch)")
	_check("INV_VIEW_MATRIX" in src, "baked axis: camera-facing billboard geometry")


## The producer builds a direct MeshInstance3D carrier and hands it to Fold.add — no pool, no stager.
func _test_producer_builds_direct_carrier() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var prod = Producer.new()
	prod.setup(parent, _dummy_texture(), Vector2(0.94, 1.30))
	var mi = prod.carrier()
	_check(mi != null and mi is MeshInstance3D, "producer builds a MeshInstance3D carrier")
	_check(mi != null and mi.get_parent() == parent, "carrier is parented under the owner node")
	_check(mi != null and mi.mesh is QuadMesh, "carrier is a QuadMesh billboard")
	_check(mi != null and mi.material_override is ShaderMaterial, "carrier wears a ShaderMaterial (compositor_layer)")

	# publish_crystal shows the carrier and stamps STANDARD-depth fold order through Fold.add.
	var view := Transform3D()
	var origin := Vector3(0.0, 0.0, -5.0)
	prod.publish_crystal(view, origin, Vector4(3.0 / 8.0, 0.0, 1.0 / 8.0, 1.0))
	_check(mi != null and mi.visible, "publish_crystal shows the carrier")
	var expect := DepthMode.render_layer_order_for(
		DepthMode.ot_order_z(origin, view, DepthMode.Mode.STANDARD))
	_check(mi != null and mi.render_layer == Fold.FOLD_LAYER,
		"publish_crystal joins the shared fold layer via Fold.add (render_layer membership)")
	_check(mi != null and mi.render_layer_order == expect,
		"publish_crystal stamps render_layer_order via Fold.add at STANDARD depth")

	# publish_empty hides it (nothing folds); release drops the carrier.
	prod.publish_empty()
	_check(mi != null and not mi.visible, "publish_empty hides the carrier (nothing folds)")
	prod.release()
	_check(prod.carrier() == null, "release drops the carrier reference")


func _dummy_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
