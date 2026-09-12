extends Node
## Locks the OT depth-ordering contract at its OWN public seam — OTDepthPrimOrder.order().
##
## This ordering is SHARED: the engine-fold path (EngineFoldCompositor) stamps each run's
## sorting_offset from the order() result via DepthMode.render_layer_order_for, and the pool
## producers (EffectParticleRenderer, TrapEffect) stage through UnifiedPrimStager.order().
## The cases were extracted verbatim from CombatDisplaySpaceCompositeTest when the raw-RD GLSL
## compositor was retired (#228 Phase 3) so the shared ordering keeps its coverage independent
## of the deleted path. RD-free (pure function).
##
## Contract (see OTDepthPrimOrder): draw order = (1) depth bucket far->near, then (2) within-bucket
## tie-break by AGE descending (newest folds last / on top), else submission order. Runs collapse
## adjacent same-DIRECTION spans (add {1,3} / sub {2}; mix {0} always solo).
##
## Run: <GODOT> --path . res://tests/OTDepthPrimOrderTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const PrimOrder = preload("res://addons/exmateria_effects/render/OTDepthPrimOrder.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_prim_order_empty()
	_test_prim_order_far_first()
	_test_prim_order_tie_break()
	_test_prim_order_age_tie_break()
	_test_prim_order_depth_separates_over_age()
	_test_prim_order_fixed_absolute()
	_test_prim_order_interleaved_runs()
	_test_prim_order_adjacent_collapse()
	_test_prim_order_records_verbatim()
	_test_prim_order_direction_grouping()

	if _failed:
		print("[FAIL] OTDepthPrimOrder test")
	else:
		print("[PASS] OTDepthPrimOrder: empty, far-first, tie-break, age-tie-break, depth-beats-age, fixed-absolute, interleaved-runs, adjacent-collapse, records-verbatim, direction-grouping")
	get_tree().quit()


## #219: empty input yields an empty unified buffer and no runs.
func _test_prim_order_empty() -> void:
	var r := PrimOrder.order(PackedFloat32Array(), PackedInt32Array(), PackedFloat32Array())
	_check(r["unified"].is_empty(), "prim_order empty: no unified floats")
	_check((r["runs"] as Array).is_empty(), "prim_order empty: no runs")


## Two prims: the DEEPER one (smaller ordering depth d) is emitted FIRST regardless of the
## submission order (far -> near fold; nearest drawn last wins the top).
func _test_prim_order_far_first() -> void:
	# Submit near prim (d=0.9) FIRST, far prim (d=0.1) second. Output must be far then near.
	var recs := _mk_records([100.0, 200.0])   # tag float per prim
	var modes := PackedInt32Array([1, 1])
	var depths := PackedFloat32Array([0.9, 0.1])
	var r := PrimOrder.order(recs, modes, depths)
	var u: PackedFloat32Array = r["unified"]
	_check(u[0] == 200.0, "prim_order far-first: far prim (d=0.1) emitted first (tag %f)" % u[0])
	_check(u[24] == 100.0, "prim_order far-first: near prim (d=0.9) emitted last (tag %f)" % u[24])


## Equal-depth (same bucket), NO ages: within-bucket order falls back to submission order
## (stable). Same-direction (all add) so it commutes — the buffer order is submission order.
func _test_prim_order_tie_break() -> void:
	var recs := _mk_records([10.0, 20.0, 30.0])
	var modes := PackedInt32Array([1, 1, 1])
	var depths := PackedFloat32Array([0.5, 0.5, 0.5])   # all equal
	var r := PrimOrder.order(recs, modes, depths)
	var u: PackedFloat32Array = r["unified"]
	_check(u[0] == 10.0 and u[24] == 20.0 and u[48] == 30.0,
		"prim_order tie-break (no ages): equal-depth keeps submission order (10,20,30) got (%f,%f,%f)" % [u[0], u[24], u[48]])


## #212 DEMI: equal-depth SUB + ADD. `age` = elapsed frames since spawn, so the NEWER
## particle has the SMALLER age and must fold LAST = ON TOP (PSX newest-on-top). In DEMI the
## white additive (emitter idx3) spawns f36-49 = LATER = newer = smaller age than the black
## subtractive (emitter idx1, f22-38 = older = larger age); so the white must land on top and
## its core survives. This guards the age DIRECTION (older folds first/behind, newer last/top).
func _test_prim_order_age_tie_break() -> void:
	# Same depth bucket. Realistic ages observed at (say) effect-frame 48:
	#   sub spawned ~f22 -> age 26 (OLDER);  add spawned ~f38 -> age 10 (NEWER).
	var recs := _mk_records([111.0, 222.0])   # 111 = sub (older), 222 = add (newer)
	var modes := PackedInt32Array([2, 1])      # sub, add
	var depths := PackedFloat32Array([0.5, 0.5])
	var ages := PackedFloat32Array([26.0, 10.0])   # sub older, add newer
	var r := PrimOrder.order(recs, modes, depths, ages)
	var u: PackedFloat32Array = r["unified"]
	# Older sub folds first (behind); newer add (smaller age) folds LAST = on top.
	_check(u[0] == 111.0 and u[24] == 222.0,
		"prim_order age tie-break: newer ADD (smaller age) folds last/on-top; got (%f,%f)" % [u[0], u[24]])
	var runs: Array = r["runs"]
	_check(runs.size() == 2 and runs[0]["mode"] == 2 and runs[1]["mode"] == 1,
		"prim_order age tie-break: [sub run(old), add run(new)] so add draws on top, got %d runs" % runs.size())
	# Symmetry: if the SUB were the newer one (smaller age), IT folds on top — age is the key,
	# not blend direction (not an add-on-top hack).
	var r2 := PrimOrder.order(_mk_records([111.0, 222.0]), PackedInt32Array([2, 1]),
		PackedFloat32Array([0.5, 0.5]), PackedFloat32Array([10.0, 26.0]))  # sub newer, add older
	var u2: PackedFloat32Array = r2["unified"]
	_check(u2[0] == 222.0 and u2[24] == 111.0,
		"prim_order age tie-break: newer SUB (smaller age) folds on top (age is the key, not blend dir)")


## #212 CORE FIX: two OPPOSITE-direction prims separated by Δz > 0.19 (one 0.19-u bucket) must
## land in DIFFERENT buckets so DEPTH decides — the age tie-break must NOT reorder across buckets.
## Pre-fix (clampf[0,1]) both realistic view-Z depths (~ -5) clamped to bucket 0, so the age key
## carried 100% of the order (the collapse). Now round(d/0.19) separates them; the nearer prim
## folds last (on top) regardless of which is newer.
func _test_prim_order_depth_separates_over_age() -> void:
	# add is FARTHER (view-Z -5.5), sub is NEARER (view-Z -5.0); Δ=0.5 > 0.19 => different buckets.
	# add is NEWER (age 10), sub OLDER (age 26): if only age decided, the newer add would fold last.
	# Depth must win: the nearer sub folds LAST (on top).
	var recs := _mk_records([111.0, 222.0])   # 111 = add (far, newer), 222 = sub (near, older)
	var modes := PackedInt32Array([1, 2])       # add, sub
	var depths := PackedFloat32Array([-5.5, -5.0])
	var ages := PackedFloat32Array([10.0, 26.0])   # add newer, sub older
	var r := PrimOrder.order(recs, modes, depths, ages)
	var u: PackedFloat32Array = r["unified"]
	_check(u[0] == 111.0 and u[24] == 222.0,
		"depth-beats-age: Δz>0.19 separates buckets; nearer folds last regardless of age, got (%f,%f)" % [u[0], u[24]])
	var runs: Array = r["runs"]
	_check(runs.size() == 2 and runs[0]["mode"] == 1 and runs[1]["mode"] == 2,
		"depth-beats-age: far add run then near sub run (depth order, not age), got %d runs" % runs.size())


## #212: fixed depth modes are ABSOLUTE OT slots. ot_order_z returns view-Z sentinels
## (ORDER_Z_FIXED_BACK far, _FRONT near); order() normalizes them alongside the relative prims and
## the span clamp keeps key_max bounded. A FIXED_FRONT, a relative mid, and a FIXED_BACK must fold
## [back, relative, front] (far -> near) — the sentinels sit outside the relative content extent.
func _test_prim_order_fixed_absolute() -> void:
	# Submit front, relative, back; expect depth order back(far) -> relative -> front(near).
	var recs := _mk_records([1.0, 2.0, 3.0])   # 1 = front, 2 = relative, 3 = back
	var modes := PackedInt32Array([1, 1, 1])    # all add (direction irrelevant here)
	var depths := PackedFloat32Array([DepthMode.ORDER_Z_FIXED_FRONT, -5.0, DepthMode.ORDER_Z_FIXED_BACK])
	var r := PrimOrder.order(recs, modes, depths)
	var u: PackedFloat32Array = r["unified"]
	_check(u[0] == 3.0 and u[24] == 2.0 and u[48] == 1.0,
		"fixed-absolute: order back(far) -> relative -> front(near), got (%f,%f,%f)" % [u[0], u[24], u[48]])


## Interleaved directions by depth: order [add, sub, add] => 3 runs (add/sub/add break at every
## direction change). Each run carries stride 24 (slice C unified record).
func _test_prim_order_interleaved_runs() -> void:
	# Submit: prim0 add @0.1 (far), prim1 sub @0.5 (mid), prim2 add @0.9 (near).
	var recs := _mk_records([0.0, 1.0, 2.0])
	var modes := PackedInt32Array([1, 2, 1])          # add, sub, add
	var depths := PackedFloat32Array([0.1, 0.5, 0.9])
	var r := PrimOrder.order(recs, modes, depths)
	var runs: Array = r["runs"]
	_check(runs.size() == 3, "prim_order interleaved: 3 runs (directions interleave), got %d" % runs.size())
	if runs.size() == 3:
		_check(runs[0]["mode"] == 1 and runs[0]["base"] == 0 and runs[0]["count"] == 1, "run0 = {add, base 0, count 1}")
		_check(runs[1]["mode"] == 2 and runs[1]["base"] == 1 and runs[1]["count"] == 1, "run1 = {sub, base 1, count 1}")
		_check(runs[2]["mode"] == 1 and runs[2]["base"] == 2 and runs[2]["count"] == 1, "run2 = {add, base 2, count 1}")
		_check(runs[0]["stride"] == 24 and runs[1]["stride"] == 24 and runs[2]["stride"] == 24,
			"prim_order interleaved: every run carries the unified stride 24")


## Adjacent same-mode prims in depth order collapse into ONE run (base/count correct).
func _test_prim_order_adjacent_collapse() -> void:
	# Two adds far, then a sub near: depth order add(0.1), add(0.3), sub(0.9) => runs [{add,0,2},{sub,2,1}].
	var recs := _mk_records([0.0, 1.0, 2.0])
	var modes := PackedInt32Array([1, 1, 2])
	var depths := PackedFloat32Array([0.1, 0.3, 0.9])
	var r := PrimOrder.order(recs, modes, depths)
	var runs: Array = r["runs"]
	_check(runs.size() == 2, "prim_order collapse: adjacent same-mode -> 2 runs, got %d" % runs.size())
	if runs.size() == 2:
		_check(runs[0]["mode"] == 1 and runs[0]["base"] == 0 and runs[0]["count"] == 2, "run0 collapsed = {add, base 0, count 2}")
		_check(runs[1]["mode"] == 2 and runs[1]["base"] == 2 and runs[1]["count"] == 1, "run1 = {sub, base 2, count 1}")


## Records are carried VERBATIM: each prim's 24 floats land intact at its output slot.
func _test_prim_order_records_verbatim() -> void:
	# Build 3 prims with a distinct fingerprint per float, submit near->far, check reorder + integrity.
	var n := 3
	var recs := PackedFloat32Array()
	for i in range(n):
		for f in range(24):
			recs.push_back(float(i) * 100.0 + float(f))   # prim i float f = i*100+f
	var modes := PackedInt32Array([1, 2, 3])
	var depths := PackedFloat32Array([0.9, 0.5, 0.1])       # near, mid, far
	var r := PrimOrder.order(recs, modes, depths)
	var u: PackedFloat32Array = r["unified"]
	# Output order far->near = prim2, prim1, prim0.
	var expect_prim := [2, 1, 0]
	var ok := true
	for out_i in range(n):
		var pi: int = expect_prim[out_i]
		for f in range(24):
			if u[out_i * 24 + f] != float(pi) * 100.0 + float(f):
				ok = false
	_check(ok, "prim_order verbatim: all 24 floats of each prim carried to its depth-ordered slot")


## Slice C (#220): runs collapse by DIRECTION, not mode. add = {1,3}, sub = {2}, mix = {0}
## always solo. run.mode is the direction's representative (1/2/0). Depths ascend so the
## depth order equals the submission order for each case (no reordering to reason about).
func _test_prim_order_direction_grouping() -> void:
	# [1,3,1] all add-direction and adjacent => ONE add run, count 3, base 0, rep mode 1.
	var d3 := PackedFloat32Array([0.1, 0.2, 0.3])
	var r := PrimOrder.order(_mk_records([0, 0, 0]), PackedInt32Array([1, 3, 1]), d3)
	var runs: Array = r["runs"]
	_check(runs.size() == 1, "dir-group [1,3,1]: one add run (mode1+mode3 merge), got %d" % runs.size())
	if runs.size() == 1:
		_check(runs[0]["mode"] == 1 and runs[0]["base"] == 0 and runs[0]["count"] == 3 and runs[0]["stride"] == 24,
			"dir-group [1,3,1]: {mode 1 (add rep), base 0, count 3, stride 24}")

	# [1,2,1] add/sub/add => three runs (every direction change breaks).
	r = PrimOrder.order(_mk_records([0, 0, 0]), PackedInt32Array([1, 2, 1]), d3)
	runs = r["runs"]
	_check(runs.size() == 3, "dir-group [1,2,1]: three runs (add/sub/add), got %d" % runs.size())
	if runs.size() == 3:
		_check(runs[0]["mode"] == 1 and runs[1]["mode"] == 2 and runs[2]["mode"] == 1,
			"dir-group [1,2,1]: rep modes add/sub/add")

	# [0,0] two mix prims => TWO solo runs (mix never merges).
	r = PrimOrder.order(_mk_records([0, 0]), PackedInt32Array([0, 0]), PackedFloat32Array([0.1, 0.2]))
	runs = r["runs"]
	_check(runs.size() == 2, "dir-group [0,0]: two solo mix runs (mix never merges), got %d" % runs.size())
	if runs.size() == 2:
		_check(runs[0]["mode"] == 0 and runs[0]["count"] == 1 and runs[1]["mode"] == 0 and runs[1]["count"] == 1,
			"dir-group [0,0]: each mix run is solo {mode 0, count 1}")

	# [1,3,2,3] => add{1,3} run, sub{2} run, add{3} run = 3 runs (base/count correct).
	var d4 := PackedFloat32Array([0.1, 0.2, 0.3, 0.4])
	r = PrimOrder.order(_mk_records([0, 0, 0, 0]), PackedInt32Array([1, 3, 2, 3]), d4)
	runs = r["runs"]
	_check(runs.size() == 3, "dir-group [1,3,2,3]: add{1,3}/sub/add = 3 runs, got %d" % runs.size())
	if runs.size() == 3:
		_check(runs[0]["mode"] == 1 and runs[0]["base"] == 0 and runs[0]["count"] == 2,
			"dir-group [1,3,2,3]: run0 add {base 0, count 2}")
		_check(runs[1]["mode"] == 2 and runs[1]["base"] == 2 and runs[1]["count"] == 1,
			"dir-group [1,3,2,3]: run1 sub {base 2, count 1}")
		_check(runs[2]["mode"] == 1 and runs[2]["base"] == 3 and runs[2]["count"] == 1,
			"dir-group [1,3,2,3]: run2 add {base 3, count 1}")


## Build N tag-only 24-float records (slice C stride): each prim's float 0 = its tag, rest
## zero. Lets a test assert which prim landed where by reading the first float of a 24-float slot.
func _mk_records(tags: Array) -> PackedFloat32Array:
	var recs := PackedFloat32Array()
	for t in tags:
		recs.push_back(float(t))
		for _f in range(23):
			recs.push_back(0.0)
	return recs
