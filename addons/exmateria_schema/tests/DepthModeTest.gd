extends Node
## DepthMode centroid fixture test (ADR-0009). Pure GDScript — no mesh, no GPU,
## no scene geometry. Locks the AVSZ representative-point rule the per-face OT
## builders share (EffectCallback._quad, ProjectileMeshBuilder):
##
##   1. tri_centroid  = AVSZ3 — the 3-vertex average.
##   2. quad_centroid = AVSZ4 — the 4-vertex average, order-independent.
##   3. The split-quad invariant: a quad's centroid is NOT either child
##      triangle's centroid, so feeding both split tris the quad centroid
##      (what the builders do) is what prevents z-fighting along the diagonal.
##
## Run: bash tests/stranger/exmateria_schema/run.sh   (ADR-0194 — this test is
## addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . res://addons/exmateria_schema/tests/DepthModeTest.tscn)

## ADR-0194 dec. 12 arm 2, added in the commit that moved this file and the only
## edit a move-only loop permits. The threaded `failed` boolean below can report
## THAT something broke and never how much ran, so a green line here described a
## run of unknown size — and a test that moves to a different project and quietly
## stops asserting looks exactly like one that passes.

## The subject, reached by `preload` path: an addon-owned test names its addon's
## internals the way the addon itself does (ADR-0212 dec. 1, ADR-0194).
const DepthMode = preload("res://addons/exmateria_schema/compositing_key/DepthMode.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var failed := false

	# 1. tri_centroid is the 3-vertex average (AVSZ3).
	var t := DepthMode.tri_centroid(Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(0, 3, 6))
	failed = _expect(t.is_equal_approx(Vector3(1, 1, 2)), "tri_centroid is the 3-vertex average", failed)

	# 2. quad_centroid is the 4-vertex average (AVSZ4)...
	var a := Vector3(0, 0, 0)
	var b := Vector3(2, 0, 0)
	var c := Vector3(0, 2, 1)
	var d := Vector3(2, 2, 1)
	var q := DepthMode.quad_centroid(a, b, c, d)
	failed = _expect(q.is_equal_approx(Vector3(1, 1, 0.5)), "quad_centroid is the 4-vertex average", failed)
	# ...and is order-independent (winding/split order must not move the point).
	failed = _expect(
		DepthMode.quad_centroid(d, c, b, a).is_equal_approx(q),
		"quad_centroid is order-independent", failed)

	# 3. Split-quad invariant: the quad centroid differs from either child tri's
	# centroid for a non-planar quad. Both split tris [0,1,2] and [1,2,3] must
	# therefore be baked the QUAD centroid (not their own), or they project to
	# different depths and z-fight along the split diagonal. This is the reason
	# the builders pass the shared centroid to both triangles.
	var tri_abc := DepthMode.tri_centroid(a, b, c)
	var tri_bcd := DepthMode.tri_centroid(b, c, d)
	failed = _expect(not q.is_equal_approx(tri_abc), "quad centroid != tri [0,1,2] centroid", failed)
	failed = _expect(not q.is_equal_approx(tri_bcd), "quad centroid != tri [1,2,3] centroid", failed)

	# Planar quad sanity: a flat quad's centroid lies on its plane (z stays 0).
	var flat := DepthMode.quad_centroid(
		Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0))
	failed = _expect(flat.is_equal_approx(Vector3.ZERO), "planar quad centroid is its center", failed)

	# 4. render_layer_order_for is the single fold-order encoding (ADR-0074): the OT depth BUCKET
	# (× RANK_STRIDE) is the primary key, a submission-stream `rank` the sub-bucket tie-break. One home
	# shared by the producers (Fold.add, EngineFoldCompositor); an int32 key (compositor_layer's
	# render_layer_order) replacing the old float sorting_offset — no float32-ULP cliff, no NaN.
	var bucket_z := 3.0 * DepthMode.UNITS_PER_OT_BUCKET   # exactly bucket 3
	failed = _expect(
		DepthMode.render_layer_order_for(bucket_z) == 3 * DepthMode.RANK_STRIDE,
		"render_layer_order_for(order_z) is round(order_z / UNITS_PER_OT_BUCKET) * RANK_STRIDE", failed)
	# rank defaults to 0 — a lone quad sits exactly on its bucket * RANK_STRIDE.
	failed = _expect(
		DepthMode.render_layer_order_for(bucket_z, 0) == 3 * DepthMode.RANK_STRIDE,
		"render_layer_order_for default rank is 0 (lone quad on its bucket)", failed)
	# A non-zero rank adds to the bucket base, staying strictly under RANK_STRIDE so depth stays primary.
	failed = _expect(
		DepthMode.render_layer_order_for(bucket_z, 5) == 3 * DepthMode.RANK_STRIDE + 5,
		"render_layer_order_for rank adds rank within the bucket stride", failed)
	failed = _expect(DepthMode.RANK_STRIDE > 0 and DepthMode.RANK_STRIDE == (1 << 10),
		"RANK_STRIDE is a positive sub-bucket stride (1 << 10)", failed)
	# Negative depth (behind the camera-space origin) rounds like any other — the per-frame normalize
	# lives in OTDepthPrimOrder, not here.
	failed = _expect(
		DepthMode.render_layer_order_for(-2.0 * DepthMode.UNITS_PER_OT_BUCKET) == -2 * DepthMode.RANK_STRIDE,
		"render_layer_order_for handles negative depth", failed)
	# Shared-scale interleave ACROSS a bucket boundary (incl. negative buckets): a max-rank prim in the
	# lower bucket must still sort strictly BELOW a rank-0 prim in the next bucket up — the int key makes
	# the depth bucket dominate regardless of rank. (bucket -2, rank RANK_STRIDE-1) < (bucket -1, rank 0).
	failed = _expect(
		DepthMode.render_layer_order_for(-2.0 * DepthMode.UNITS_PER_OT_BUCKET, DepthMode.RANK_STRIDE - 1)
			< DepthMode.render_layer_order_for(-1.0 * DepthMode.UNITS_PER_OT_BUCKET, 0),
		"render_layer_order_for: max-rank in a bucket stays below rank-0 of the next bucket (RANK_STRIDE boundary)", failed)

	# 5. ot_depth is the CPU mirror of ot_depth.gdshaderinc (#219) — a few modes against
	# hand-computed values so the CPU ordering matches the shader's raster depth. Preserved from
	# the retired CombatDisplaySpaceCompositeTest (#228 Phase 3): DepthMode survives, its GLSL
	# cross-check does not.
	var pt := Vector3(0.3, -0.4, 0.7)
	failed = _expect(DepthMode.ot_depth(Vector3(9, 9, 9), Projection(), Transform3D(), 2) == DepthMode.FIXED_FRONT_DEPTH,
		"ot_depth mode2 FIXED_FRONT = 0.9999", failed)
	failed = _expect(DepthMode.ot_depth(Vector3(1, 2, 3), Projection(), Transform3D(), 3) == DepthMode.FIXED_BACK_DEPTH,
		"ot_depth mode3 FIXED_BACK = 0.0001", failed)
	failed = _expect(DepthMode.ot_depth(Vector3.ZERO, Projection(), Transform3D(), 4) == DepthMode.FIXED_16_DEPTH,
		"ot_depth mode4 FIXED_16 = 0.9990", failed)
	# STANDARD (mode 0) with identity proj/view = projected z of the point. Identity Projection
	# has w=1, so base = point.z.
	var std := DepthMode.ot_depth(pt, Projection(), Transform3D(), 0)
	failed = _expect(absf(std - 0.7) < 1e-6, "ot_depth mode0 STANDARD identity = point.z", failed)
	# PULL_FORWARD_8 (mode 1) adds 8 * UNITS_PER_OT_BUCKET * proj.z.z on top of base (identity proj.z.z == 1).
	var pf8_depth := DepthMode.ot_depth(pt, Projection(), Transform3D(), 1)
	failed = _expect(absf(pf8_depth - (0.7 + 8.0 * DepthMode.UNITS_PER_OT_BUCKET)) < 1e-6,
		"ot_depth mode1 PULL_FORWARD_8 = z + 8*0.19*proj.z.z", failed)

	# 6. ot_order_z is the view-space-Z FOLD-ORDER key, DISTINCT from ot_depth's reversed-Z raster
	# mirror (#212). view-Z + world-unit bias; farther sorts SMALLER (folds first); a forward pull
	# moves a prim NEARER (larger view-Z); ordered fixed-mode sentinels.
	failed = _expect(absf(DepthMode.ot_order_z(pt, Transform3D(), 0) - 0.7) < 1e-6,
		"ot_order_z mode0 STANDARD identity view = point.z", failed)
	var pf8_z := DepthMode.ot_order_z(pt, Transform3D(), 1)
	failed = _expect(absf(pf8_z - (0.7 + 8.0 * DepthMode.UNITS_PER_OT_BUCKET)) < 1e-6,
		"ot_order_z mode1 PULL_FORWARD_8 = z + 8*0.19", failed)
	failed = _expect(pf8_z > 0.7, "ot_order_z: PULL_FORWARD moves the prim NEARER (larger view-Z)", failed)
	var far_z := DepthMode.ot_order_z(Vector3(0, 0, -10.0), Transform3D(), 0)
	var near_z := DepthMode.ot_order_z(Vector3(0, 0, -5.0), Transform3D(), 0)
	failed = _expect(far_z < near_z, "ot_order_z: farther point (more negative view-Z) sorts smaller (folds first)", failed)
	failed = _expect(DepthMode.ot_order_z(Vector3(9, 9, 9), Transform3D(), 2) == DepthMode.ORDER_Z_FIXED_FRONT,
		"ot_order_z mode2 FIXED_FRONT sentinel", failed)
	failed = _expect(DepthMode.ot_order_z(Vector3.ZERO, Transform3D(), 4) == DepthMode.ORDER_Z_FIXED_16,
		"ot_order_z mode4 FIXED_16 sentinel", failed)
	failed = _expect(DepthMode.ot_order_z(Vector3(1, 2, 3), Transform3D(), 3) == DepthMode.ORDER_Z_FIXED_BACK,
		"ot_order_z mode3 FIXED_BACK sentinel", failed)
	failed = _expect(DepthMode.ORDER_Z_FIXED_FRONT > DepthMode.ORDER_Z_FIXED_16
		and DepthMode.ORDER_Z_FIXED_16 > DepthMode.ORDER_Z_FIXED_BACK,
		"ot_order_z sentinels ordered FRONT(near) > 16 > BACK(far)", failed)

	# 7. rung_z is the DEPTH-LADDER conversion (ADR-0077): a UI rung index -> world-space Z, one
	# PSX OT bucket per rung. It is the third derivation from UNITS_PER_OT_BUCKET and, until this
	# test existed, the only one with no home — four ui3 scenes each carried a private copy and
	# three more inlined the multiply (CONTEXT.md "Fold order" -> _Avoid_ bans exactly that).
	failed = _expect(DepthMode.rung_z(0) == 0.0, "rung_z(0) is the unlifted plane", failed)
	failed = _expect(absf(DepthMode.rung_z(1) - DepthMode.UNITS_PER_OT_BUCKET) < 1e-6,
		"rung_z(1) is one OT bucket", failed)
	failed = _expect(absf(DepthMode.rung_z(5) - 5.0 * DepthMode.UNITS_PER_OT_BUCKET) < 1e-6,
		"rung_z(n) is n OT buckets", failed)
	failed = _expect(absf(DepthMode.rung_z(-3) + 3.0 * DepthMode.UNITS_PER_OT_BUCKET) < 1e-6,
		"rung_z handles a negative rung (below the ladder base)", failed)
	# Larger rung = NEARER the ortho camera = drawn on top. The ladder's whole ordering claim.
	failed = _expect(DepthMode.rung_z(9) > DepthMode.rung_z(3),
		"rung_z is monotonic: a higher rung is nearer", failed)
	# The JOIN that makes the ladder one thing: a rung IS an OT bucket, so a carrier lifted to
	# rung k lands on fold-order bucket k. This is why one bucket per rung was chosen (ADR-0077)
	# and it only holds while rung_z and render_layer_order_for share UNITS_PER_OT_BUCKET.
	for k: int in [0, 1, 3, 10]:
		failed = _expect(
			DepthMode.render_layer_order_for(DepthMode.rung_z(k)) == k * DepthMode.RANK_STRIDE,
			"rung %d folds into layer-order bucket %d (rung_z <-> render_layer_order_for)" % [k, k], failed)
	# Adjacent rungs never collide in fold order — the separation the ladder is FOR.
	failed = _expect(
		DepthMode.render_layer_order_for(DepthMode.rung_z(4))
			< DepthMode.render_layer_order_for(DepthMode.rung_z(5)),
		"adjacent rungs land in distinct, ordered fold buckets", failed)

	if _passed + _failed == 0:
		print("[FAIL] ran zero assertions — nothing was checked, which is not a pass")
		failed = true
	print("=== DepthModeTest: %d passed, %d failed ===" % [_passed, _failed])

	if failed:
		print("[FAIL] DepthMode centroid test")
	else:
		print("[PASS] DepthMode: AVSZ3/AVSZ4 centroids + split-quad invariant + render_layer_order_for + ot_depth CPU port + ot_order_z fold key + rung_z depth ladder")
	get_tree().quit()


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		_failed += 1
		print("[FAIL] %s" % label)
		return true
	_passed += 1
	return failed_so_far
