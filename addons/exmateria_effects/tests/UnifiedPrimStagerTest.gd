extends Node
## Guards UnifiedPrimStager — the single-sourced 24-float transparent-prim record + parallel
## ordering keys + order()->upload_unified publish ceremony extracted from EffectParticleRenderer
## and TrapEffect (COMPOSITOR_DEPENDENCY_MAP.md §6.2). Pure GDScript, no GPU / no MultiMesh, so it
## runs headless-safe like TrapUnifiedPublishTest.
##
## Invariants locked here (the byte contract the two producers used to each hand-roll):
##   - append() lays out the exact ADR-0040 24-float record: 3x4 ROW-MAJOR transform, color rgba,
##     custom(uv_rect) rgba, [20] per-prim level_scale (mode3/ADD25 = 0.25 else 1.0), [21..23] pad;
##   - the parallel mode / ot_order_z depth / age keys are populated per prim;
##   - mode resolution is NOT done here — append() takes an already-resolved mode int;
##   - publish() OT-depth-orders the staging and forwards it verbatim to pool.upload_unified,
##     no-op-safe on a null pool / negative slot.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/UnifiedPrimStagerTest.tscn

const OTDepthPrimOrder = preload("res://addons/exmateria_effects/render/OTDepthPrimOrder.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const StagerScript = ExMateriaEffects.UnifiedPrimStager

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_record_layout_byte_exact()
	_test_level_scale_by_mode()
	_test_packing_matches_multimesh_buffer()
	_test_depth_and_age_keys()
	_test_publish_forwards_ordered_to_pool()
	_test_publish_noop_on_invalid_target()

	if _failed:
		print("[FAIL] UnifiedPrimStager test")
	else:
		print("[PASS] UnifiedPrimStager: 24-float record layout; level_scale by mode; MultiMesh byte-equivalence; depth/age keys; publish forwards ordered to pool; publish no-op on invalid target")
	get_tree().quit()


# A known prim's inputs, and the 24-float record they must produce.
func _known_basis() -> Basis:
	return Basis(
		Vector3(-8.0, -8.0, 8.0),   # col0: tl_x, tl_y, tr_x
		Vector3(-8.0, -8.0, 8.0),   # col1: tr_y, bl_x, bl_y
		Vector3(8.0, 8.0, 1.0))     # col2: br_x, br_y, depth_mode


func _test_record_layout_byte_exact() -> void:
	var stager = StagerScript.new()
	stager.begin(Transform3D())
	var basis := _known_basis()
	var origin := Vector3(2.0, 3.0, 4.0)
	var color := Color(0.25, 0.5, 0.75, 1.0)
	var uv := Color(0.1, 0.2, 0.3, 0.4)
	stager.append(basis, origin, color, uv, 1, 1, 7.0)  # mode 1 (add) -> level 1.0

	_check(stager.count() == 1, "count() == 1 after one append")
	var s: PackedFloat32Array = stager.records()
	_check(s.size() == 24, "record is 24 floats (got %d)" % s.size())

	# 3x4 ROW-MAJOR: row r = (col0[r], col1[r], col2[r], origin[r])
	var expected := PackedFloat32Array([
		basis.x.x, basis.y.x, basis.z.x, origin.x,   # row 0
		basis.x.y, basis.y.y, basis.z.y, origin.y,   # row 1
		basis.x.z, basis.y.z, basis.z.z, origin.z,   # row 2
		color.r, color.g, color.b, color.a,          # color rgba
		uv.r, uv.g, uv.b, uv.a,                       # custom (uv_rect) rgba
		1.0, 0.0, 0.0, 0.0,                           # [20] level_scale + [21..23] pad
	])
	for i in range(24):
		_check(is_equal_approx(s[i], expected[i]), "record[%d] = %f (expected %f)" % [i, s[i], expected[i]])


func _test_level_scale_by_mode() -> void:
	# mode 3 (ADD25) -> level_scale 0.25 at [20]; every other mode -> 1.0.
	for mode in [0, 1, 2, 3]:
		var stager = StagerScript.new()
		stager.begin(Transform3D())
		stager.append(_known_basis(), Vector3.ZERO, Color.WHITE, Color(0, 0, 0, 0), mode, 1, 0.0)
		var lvl: float = stager.records()[20]
		var want: float = 0.25 if mode == 3 else 1.0
		_check(is_equal_approx(lvl, want), "mode %d -> level_scale %f (expected %f)" % [mode, lvl, want])


## #218/#220 CORE GUARD (preserved from the retired CombatDisplaySpaceCompositeTest, #228 Phase 3):
## append()'s FIRST 20 floats must be BYTE-IDENTICAL to what a real MultiMesh RD buffer stores for the
## same transform/color/custom — the ADR-0040 MultiMesh-compatibility contract the engine-fold's SSBO
## read assumes. The sibling _test_record_layout_byte_exact locks the layout against a hand-authored
## spec; THIS locks it against Godot's own multimesh_get_buffer serializer (independent source of truth),
## so a row-major transpose or a Godot format change can't drift the packing under the fold. A drift
## here silently corrupts every folded prim.
func _test_packing_matches_multimesh_buffer() -> void:
	var cases := [
		{"basis": Basis(Vector3(-8, -8, 8), Vector3(-8, -8, 8), Vector3(8, 8, 0.0)),
			"origin": Vector3(0.3, -0.7, 1.1),
			"color": Color(1.0, 0.5, 0.25, 1.0), "custom": Color(0.1, 0.2, 0.8, 0.9), "mode": 1},
		{"basis": Basis(Vector3(-6, -9, 7), Vector3(-5, -4, 6), Vector3(9, 3, 2.0)),
			"origin": Vector3(-1.2, 0.4, -0.6),
			"color": Color(0.2, 0.9, 0.1, 0.0), "custom": Color(0.5, 0.5, 0.3, 0.3), "mode": 3},
		{"basis": Basis(Vector3(-8, -8, 8), Vector3(8, -8, 8), Vector3(8, 8, 4.0)),
			"origin": Vector3(2.0, 2.0, 2.0),
			"color": Color(0.0, 0.0, 0.0, 1.0), "custom": Color(0.9, 0.1, 0.7, 0.2), "mode": 2},
	]

	# Path 1: a real MultiMesh's RD buffer (the 20-float ADR-0040 packing Godot itself produces).
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = cases.size()
	for i in range(cases.size()):
		mm.set_instance_transform(i, Transform3D(cases[i]["basis"], cases[i]["origin"]))
		mm.set_instance_color(i, cases[i]["color"])
		mm.set_instance_custom_data(i, cases[i]["custom"])
	var mm_floats: PackedFloat32Array = RenderingServer.multimesh_get_buffer(mm.get_rid())
	_check(mm_floats.size() == cases.size() * 20, "packing: MultiMesh buffer is 20 floats/instance")

	# Path 2: UnifiedPrimStager.append() — the surviving producer's packing. Compare [0..19].
	var stager = StagerScript.new()
	stager.begin(Transform3D())
	for c in cases:
		stager.append(c["basis"], c["origin"], c["color"], c["custom"], c["mode"], 1, 0.0)
	var recs: PackedFloat32Array = stager.records()
	_check(recs.size() == cases.size() * 24, "packing: stager records are 24 floats/instance")

	var first_bad := -1
	for i in range(cases.size()):
		for f in range(20):
			if absf(mm_floats[i * 20 + f] - recs[i * 24 + f]) > 1e-6 and first_bad < 0:
				first_bad = i * 24 + f
	if first_bad >= 0:
		_check(false, "packing byte-equivalence: first mismatch at record float %d" % first_bad)
	else:
		_check(true, "packing byte-equivalence: append()[0..19] == MultiMesh buffer per-instance (ADR-0040)")


func _test_depth_and_age_keys() -> void:
	# The depth key is DepthMode.ot_order_z(origin, view, depth_mode) computed inside append using
	# the view handed to begin(); the age key is passed through verbatim.
	var view := Transform3D().translated(Vector3(0, 0, -5))
	var origin := Vector3(1.0, 2.0, 3.0)
	var stager = StagerScript.new()
	stager.begin(view)
	stager.append(_known_basis(), origin, Color.WHITE, Color(0, 0, 0, 0), 2, 1, 42.0)
	_check(stager.modes()[0] == 2, "mode key passed through (got %d)" % stager.modes()[0])
	_check(is_equal_approx(stager.ages()[0], 42.0), "age key passed through (got %f)" % stager.ages()[0])
	var want_depth: float = DepthMode.ot_order_z(origin, view, 1)
	_check(is_equal_approx(stager.depths()[0], want_depth),
		"depth key = ot_order_z(origin, view, mode) (got %f expected %f)" % [stager.depths()[0], want_depth])


# A fake pool that records the last upload_unified call.
class FakePool:
	extends Node
	var last := {}
	func upload_unified(slot: int, bytes: PackedByteArray, count: int, runs: Array,
			use_palette: bool = false, palette_tex: RID = RID(), palette_rows: int = 16) -> void:
		last = {"slot": slot, "bytes": bytes, "count": count, "runs": runs,
			"use_palette": use_palette, "palette_tex": palette_tex, "palette_rows": palette_rows}


func _test_publish_forwards_ordered_to_pool() -> void:
	var stager = StagerScript.new()
	stager.begin(Transform3D())
	# Two prims at different depths; publish must forward the ordered result + total count.
	stager.append(_known_basis(), Vector3(0, 0, -1), Color.WHITE, Color(0, 0, 0, 0), 1, 1, 1.0)
	stager.append(_known_basis(), Vector3(0, 0, -3), Color.WHITE, Color(0, 0, 0, 0), 2, 1, 2.0)
	var pool := FakePool.new()
	add_child(pool)
	stager.publish(pool, 5, true, RID(), 9)

	_check(pool.last.get("slot", -99) == 5, "publish forwards the slot index")
	_check(pool.last.get("count", -1) == 2, "publish forwards total count == 2")
	_check(pool.last.get("use_palette", false) == true, "publish forwards use_palette")
	_check(pool.last.get("palette_rows", -1) == 9, "publish forwards palette_rows (non-16 CLUT height)")
	# ADR-0074 ⑤: the fragment/geometry/PAR axes are no longer forwarded — the remaining pool producers
	# are monomorphic (particle contract), and the light producers that varied them are direct fold nodes.
	_check(not pool.last.has("discard_mode"), "publish no longer forwards discard_mode (axis stripped)")
	_check(not pool.last.has("geometry_mode"), "publish no longer forwards geometry_mode (axis stripped)")
	_check(not pool.last.has("par_mode"), "publish no longer forwards par_mode (axis stripped)")
	# The forwarded bytes are the OT-ordered unified buffer (2 prims * 24 floats * 4 bytes).
	var expect_bytes: Dictionary = OTDepthPrimOrder.order(stager.records(), stager.modes(), stager.depths(), stager.ages())
	var want: PackedByteArray = (expect_bytes["unified"] as PackedFloat32Array).to_byte_array()
	_check(pool.last.get("bytes", PackedByteArray()) == want, "publish forwards the OT-ordered unified bytes")
	pool.queue_free()


func _test_publish_noop_on_invalid_target() -> void:
	var stager = StagerScript.new()
	stager.begin(Transform3D())
	stager.append(_known_basis(), Vector3.ZERO, Color.WHITE, Color(0, 0, 0, 0), 1, 1, 0.0)
	# Null pool / negative slot must not crash (matches the producers' guard).
	stager.publish(null, 0)
	stager.publish(FakePool.new(), -1)
	_check(true, "publish is no-op-safe on null pool / negative slot")
