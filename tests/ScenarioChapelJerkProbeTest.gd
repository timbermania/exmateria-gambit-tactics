extends Node
## Mid-chain glitch detector for the chapel fusion-chain spline.
##
## User report (post-spline-default): "halfway through the chain the camera
## skips really fast then catches itself." The bit-exact PSX parity test
## (ScenarioChapelChainSplineTest) PASSES — so if a glitch exists in Godot
## that PSX doesn't have, it must live in some layer OTHER than the spline
## math (e.g. host-fps batching, transform race, dialog overlay, debug panel).
##
## This probe drives the same chapel chain BUT:
##   1. Dumps every tick's per-axis scratch + Godot-side camera pose to disk.
##   2. Computes per-tick Δ (velocity), Δ² (accel), Δ³ (jerk) for X/Y/Z.
##   3. Flags ticks whose jerk magnitude exceeds an empirical threshold AND
##      whose velocity also spikes (filters out the natural seg-2→3 peak).
##   4. Cross-checks against the same PSX trace the parity test uses — if PSX
##      shows the same jerk at the same tick, the artifact is FFT-faithful
##      and the user is perceiving an authentic FFT quirk; otherwise the
##      glitch is Godot-side and the trace pin-points it.
##
## Run via:
##   "$GODOT" --path . --quit-after 30 res://tests/ScenarioChapelJerkProbeTest.tscn
##
## Output (always written, even on PASS):
##   user://last_run/godot_camera_chain_jerk_trace.jsonl

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

# The PSX capture this cross-checks against is NOT in the repo (it is a
# PCSX-Redux probe dump). Drop one at this path to enable the cross-check.
# The previous default was an absolute path into a checkout that does not
# exist on this machine, so the PSX arm has been silently inert.
# NOT an env var: ADR-0051 keeps configuration out of src/ and tests/.
const PSX_TRACE_PATH := "user://psx_captures/probe_camera_chain_writes.jsonl"
const OUT_PATH := "user://last_run/godot_camera_chain_jerk_trace.jsonl"

# Per-tick |velocity| (opcode units/tick) gate. The natural peak on chapel
# is ~4.8/tick (seg 4); we want to catch ANY non-trivial-velocity tick
# whose jerk is suspect, so 1.0 lets through the whole motion phase.
const VEL_SPIKE_OPCODE_PER_TICK := 1.0
# Per-tick |jerk| (opcode/tick³). Empirically the chapel chain runs with
# max jerk ~1.5/tick³ in the mid-segment turn-over. Anything above that
# is a candidate for the perceived "skip-and-catch".
const JERK_SPIKE_OPCODE_PER_TICK3 := 1.0


func _ready() -> void:
	var psx_trace: Array = _load_psx_trace()
	var psx_start := -1
	if not psx_trace.is_empty():
		psx_start = _find_psx_chain_start(psx_trace)

	# Chain-only baseline (no cleanup Camera firing mid-chain).
	var trace_baseline: Array = _run_chain(false)

	# Repro for the live-player glitch: PC=48 cleanup Camera fires mid-chain.
	# Live-paced Wait sum (PC=32→PC=48 = 180+86+148 = 414 ticks at the
	# auto-cleared Display Message) lands the override around chain tick
	# 414 — that's peak-velocity territory (start of seg 5 in spline ticks).
	# The test simulates this at +414 test ticks after chain start.
	var trace_with_cleanup: Array = _run_chain(false, 415)

	var bs := _find_godot_chain_start(trace_baseline)
	var bc := _find_godot_chain_start(trace_with_cleanup)
	if bs < 0:
		print("[FAIL] baseline: spline never moved"); get_tree().quit(1); return
	if bc < 0:
		print("[FAIL] cleanup-injected: spline never moved"); get_tree().quit(1); return

	# Compare the two traces: any tick where they differ by > 1 opcode is
	# a tick where the cleanup-lerp diverged the camera from the spline's
	# trajectory. Largest divergence = worst-case snap.
	var max_dx: float = 0.0
	var bad_tick: int = -1
	var bad_baseline: float = 0.0
	var bad_cleanup: float = 0.0
	var first_diverge: int = -1
	var n := mini(trace_baseline.size() - bs, trace_with_cleanup.size() - bc)
	for i in range(n):
		var b: float = float(trace_baseline[bs + i]["x"])
		var c: float = float(trace_with_cleanup[bc + i]["x"])
		var d := absf(b - c)
		if d > 0.5 and first_diverge < 0:
			first_diverge = i
		if d > max_dx:
			max_dx = d
			bad_tick = i
			bad_baseline = b
			bad_cleanup = c
	print("[info] Cleanup-injected vs baseline (chain tick relative):")
	print("  first divergence > 0.5 opcode: tick +%d" % first_diverge)
	print("  max |Δx| = %.2f at tick +%d  (baseline=%.2f, with_cleanup=%.2f)" %
		[max_dx, bad_tick, bad_baseline, bad_cleanup])

	# Snap detection: per-tick |Δx| between consecutive ticks of the
	# cleanup-injected run that exceed natural peak velocity (~4.8/tick)
	# signal the lerp racing the camera.
	print("[info] Per-tick velocity spikes in cleanup-injected trace (|dx| > 6):")
	var spikes := []
	for i in range(bc + 1, trace_with_cleanup.size()):
		var dx := float(trace_with_cleanup[i]["x"]) - float(trace_with_cleanup[i - 1]["x"])
		if absf(dx) > 6.0:
			spikes.append({"tick": i - bc, "x": trace_with_cleanup[i]["x"], "dx": dx})
	for s in spikes:
		print("  *** chain tick +%d  x=%.2f  dx=%.2f opcode/tick ***" %
			[s["tick"], s["x"], s["dx"]])
	if spikes.is_empty():
		print("  (no per-tick velocity spike > 6 — clean trajectory)")

	# Pass/fail: a non-fusion Camera mid-spline must not produce ANY snap.
	# `max_dx == 0` means the cleanup was no-op'd (spline-active guard fired);
	# anything > 0 means the parallel-lerp leaked through. Fail loud so a
	# regression of `_op_camera`'s spline-active early-return is visible.
	if max_dx > 0.5 or not spikes.is_empty():
		print("[FAIL] chapel cleanup Camera races the active spline " +
			"(max Δ vs baseline = %.2f opcode, %d velocity spikes)" %
			[max_dx, spikes.size()])
		get_tree().quit(1)
		return
	print("[PASS] cleanup-injected trace bit-identical to baseline " +
		"— spline-active guard intercepted PC=48-style override")

	# Detection uses the baseline trace for the standard jerk analysis.
	var trace: Array = trace_baseline
	var godot_start: int = bs

	# Write the trace to disk first so it's available for offline analysis
	# regardless of what the threshold detector finds.
	DirAccess.make_dir_recursive_absolute("user://last_run/")
	var out := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	for row in trace:
		out.store_line(JSON.stringify(row))
	out.close()
	print("[info] wrote %d ticks to %s" % [trace.size(), OUT_PATH])

	# Detect jerk spikes on each axis the user could perceive — X is the
	# dominant lateral sweep, but Y (height), Z (depth), and ortho (zoom)
	# all contribute to perceived camera motion. A glitch in any one shows
	# up as a per-frame snap of the framed scene.
	for axis_key in ["x", "y_height", "z_depth", "ortho"]:
		var godot_kinks := _detect_kinks(trace, godot_start, axis_key)
		print("[info] Godot %s-axis kinks (|jerk| > %.2f, |vel| > %.2f):"
			% [axis_key, JERK_SPIKE_OPCODE_PER_TICK3, VEL_SPIKE_OPCODE_PER_TICK])
		for k in godot_kinks:
			print("  tick %d  val=%.3f  v=%.3f  a=%.3f  j=%.3f%s" %
				[k["tick"], k["v_at"], k["v"], k["a"], k["j"],
				 "  (segment boundary)" if k["near_boundary"] else ""])
		if godot_kinks.is_empty():
			print("  (no kinks above threshold)")

	# PSX cross-check — only the X axis is in the probe.
	if psx_start >= 0:
		var psx_godot_like := _psx_to_godot_like(psx_trace, psx_start)
		var psx_kinks := _detect_kinks(psx_godot_like, 0, "x")
		var godot_x_kinks := _detect_kinks(trace, godot_start, "x")
		var godot_only := _diff_kinks(godot_x_kinks, psx_kinks, 2)
		print("[info] Godot-only X-axis kinks (no PSX twin within ±2 ticks):")
		if godot_only.is_empty():
			print("  none — every Godot X jerk spike has a PSX twin (= FFT-faithful)")
		else:
			for k in godot_only:
				print("  *** tick %d  x=%.2f  v=%.2f  j=%.2f  ***" %
					[k["tick"], k["v_at"], k["v"], k["j"]])

	# Per-segment summary for each axis (eye-tunable).
	_report_per_segment(trace, godot_start, "x")
	_report_per_segment(trace, godot_start, "y_height")
	_report_per_segment(trace, godot_start, "z_depth")
	_report_per_segment(trace, godot_start, "ortho")

	get_tree().quit(0)


func _run_chain(variable_dt: bool, fire_cleanup_at_tick: int = -1) -> Array:
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var cam := _TrackingCamera.new()
	add_child(cam)
	vm.player_camera = cam
	vm.camera_director.use_camera_chain_spline = true

	vm.camera_director._op_camera(_cam(2040, 488, 64964, 750, 3074, 0, 8192, 1))
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_cam(1528, 488, 65172, 510, 3074, 0, 5952, 260))
	vm.camera_director._op_camera(_cam(1448, 488, 65208, 350, 3202, 0, 4128,  80))
	vm.camera_director._op_camera(_cam(1256, 488, 65208, 334, 3314, 0, 4032,  68))
	vm.camera_director._op_camera(_cam(1000, 496, 65256, 318, 3442, 0, 3808,  56))
	vm.camera_director._op_camera(_cam( 872, 500, 65316, 308, 3552, 0, 4096,  32))
	vm.camera_director._op_camera(_cam( 840, 504, 65316, 302, 3584, 0, 4096,  48))
	vm.camera_director._op_camera_fusion_end({})

	var trace: Array = []
	# camera_position_offset removed (#139, ADR-0057); body consumed raw → ZERO.
	var pos_off: Vector3 = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC07A  # deterministic
	for tick in range(600):
		# Chapel PC=48 cleanup Camera fires during the chain on the live
		# player (Wait sum from PC=32 fusion_end through PC=48 ≈ 414 ticks
		# at the auto-paced Display Message). If `fire_cleanup_at_tick` is
		# set, simulate the same op at that tick. Without the fix this
		# starts a 4-tick lerp in parallel with the still-running spline
		# and races the camera toward the cleanup pose ~15× the spline's
		# natural per-tick velocity — the "skip really fast then catch
		# itself" the user reports.
		if tick == fire_cleanup_at_tick:
			vm.camera_director._op_camera(_cam(840, 504, 65316, 302, 3584, 0, 4096, 4))

		var dt: float = 1.0 / 60.0
		if variable_dt:
			# Alternate 1/30 and 1/120 to stress the host-fps batcher
			# without making the test non-deterministic.
			dt = (1.0 / 30.0) if (tick % 2 == 0) else (1.0 / 120.0)
		vm._process(dt)
		var p: Vector3 = cam.last_pos - pos_off
		trace.append({
			"tick": tick,
			"x": p.x * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"y_height": -p.y * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"z_depth":  p.z * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"ortho": cam.last_ortho,
		})
	vm.queue_free()
	cam.queue_free()
	return trace


func _find_godot_chain_start(trace: Array) -> int:
	for i in range(trace.size()):
		if absf(float(trace[i]["x"]) - 2040.0) > 1.0:
			return i
	return -1


func _diff_runs(a: Array, sa: int, b: Array, sb: int) -> void:
	# Compare position by tick index from the chain start of each run.
	# In variable-dt mode the chain ticks at the same WALL-CLOCK rate, but
	# each Godot frame batches a different count of spline ticks, so the
	# trace[].x at tick i may sample a different chain-internal phase.
	# We compute the max |Δ x| as a coarse "did they end up at the same
	# place" signal.
	var n: int = mini(a.size() - sa, b.size() - sb)
	var max_dx: float = 0.0
	var bad_tick: int = -1
	for i in range(n):
		var d := absf(float(a[sa + i]["x"]) - float(b[sb + i]["x"]))
		if d > max_dx:
			max_dx = d
			bad_tick = i
	print("  max Δx = %.3f opcode (at tick +%d after chain start)" % [max_dx, bad_tick])


func _cam(x: int, y: int, z: int, angle: int, map_rot: int, cam_rot: int,
		zoom: int, time_ticks: int) -> Dictionary:
	return {
		"name": "Camera", "opcode": 0x19,
		"offset": 0,
		"params": [
			{"name": "X", "value": x, "bytes": 2},
			{"name": "Z", "value": z, "bytes": 2},
			{"name": "Y", "value": y, "bytes": 2},
			{"name": "Angle", "value": angle, "bytes": 2},
			{"name": "Map Rotation", "value": map_rot, "bytes": 2},
			{"name": "Camera Rotation", "value": cam_rot, "bytes": 2},
			{"name": "Zoom", "value": zoom, "bytes": 2},
			{"name": "Time", "value": time_ticks, "bytes": 2},
		]
	}


# Convert PSX scratch trace (X in scratch units = opcode<<10) into the same
# shape the Godot trace uses, so the kink detector can run on both.
func _psx_to_godot_like(psx: Array, start: int) -> Array:
	var out: Array = []
	for i in range(start, psx.size()):
		var r: Dictionary = psx[i]
		out.append({
			"tick": i - start,
			"x": float(r.get("x", 0)) / 1024.0,
		})
	return out


# Forward-diff velocity, accel, jerk from a trace of dicts with "tick" + "x".
# Flags ticks whose |jerk| AND |vel| exceed thresholds. Near-boundary flag
# helps the eye separate natural seg transitions from genuine glitches.
const _SEG_END_TICKS := [260, 340, 408, 464, 496, 544]
const _BOUNDARY_TOL := 2

func _detect_kinks(trace: Array, start: int, key: String) -> Array:
	var kinks: Array = []
	# 3-tick window: need ticks i, i-1, i-2, i-3 for forward-diff jerk.
	for i in range(start + 3, trace.size()):
		var v: float = float(trace[i][key]) - float(trace[i - 1][key])
		var v1: float = float(trace[i - 1][key]) - float(trace[i - 2][key])
		var v2: float = float(trace[i - 2][key]) - float(trace[i - 3][key])
		var a: float = v - v1
		var a1: float = v1 - v2
		var j: float = a - a1
		if absf(j) >= JERK_SPIKE_OPCODE_PER_TICK3 and absf(v) >= VEL_SPIKE_OPCODE_PER_TICK:
			var tick_rel: int = trace[i].get("tick", i - start)
			var near := false
			for b in _SEG_END_TICKS:
				if abs(tick_rel - b) <= _BOUNDARY_TOL:
					near = true
					break
			kinks.append({
				"tick": tick_rel,
				"v_at": float(trace[i][key]),
				"v": v, "a": a, "j": j,
				"near_boundary": near,
			})
	return kinks


# Return kinks in A that don't have a near-tick (±tol) twin in B.
func _diff_kinks(a: Array, b: Array, tol: int) -> Array:
	var out: Array = []
	for ka in a:
		var matched := false
		for kb in b:
			if abs(int(ka["tick"]) - int(kb["tick"])) <= tol:
				matched = true
				break
		if not matched:
			out.append(ka)
	return out


func _report_per_segment(trace: Array, start: int, key: String) -> void:
	var bounds := [0, 260, 340, 408, 464, 496, 544]
	print("[info] per-segment %s-axis velocity range (units/tick):" % key)
	for s in range(bounds.size() - 1):
		var lo: int = start + int(bounds[s])
		var hi: int = start + int(bounds[s + 1])
		if hi >= trace.size():
			continue
		var vmin: float = 1e9
		var vmax: float = -1e9
		var jmax: float = 0.0
		var jmax_tick: int = -1
		for t in range(lo + 3, hi):
			var v: float = float(trace[t][key]) - float(trace[t - 1][key])
			var v1: float = float(trace[t - 1][key]) - float(trace[t - 2][key])
			var v2: float = float(trace[t - 2][key]) - float(trace[t - 3][key])
			var a: float = v - v1
			var a1: float = v1 - v2
			var j: float = a - a1
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
			if absf(j) > jmax:
				jmax = absf(j)
				jmax_tick = t - start
		print("  seg %d (tick %d..%d): v ∈ [%.4f, %.4f]   max |jerk| = %.4f @ tick %d" %
			[s + 1, bounds[s], bounds[s + 1], vmin, vmax, jmax, jmax_tick])


func _load_psx_trace() -> Array:
	if not FileAccess.file_exists(PSX_TRACE_PATH):
		# Say so. Every PSX-vs-Godot comparison below is gated on this array being
		# non-empty, so a missing capture does not fail the test — it removes the
		# FFT-faithfulness arm entirely, and used to do that without a word.
		print("[INFO] PSX trace absent at %s — the PSX cross-check arm is INERT "
			% PSX_TRACE_PATH + "(drop a PCSX probe dump there to enable it)")
		return []
	var f := FileAccess.open(PSX_TRACE_PATH, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or not line.begins_with("tick"):
			continue
		var d := {}
		for tok in line.split("\t"):
			if "=" not in tok:
				continue
			var kv := tok.split("=", false, 1)
			if kv.size() != 2:
				continue
			var k: String = kv[0]
			var v: String = kv[1]
			var clean := ""
			for ch in v:
				if (ch >= "0" and ch <= "9") or ch == "-":
					clean += ch
				else:
					break
			if not clean.is_empty():
				d[k] = int(clean)
		if not d.is_empty():
			out.append(d)
	f.close()
	out.sort_custom(func(a, b): return int(a.get("cyc", 0)) < int(b.get("cyc", 0)))
	return out


func _find_psx_chain_start(rows: Array) -> int:
	var reached := false
	for i in range(rows.size()):
		var x: int = int(rows[i].get("x", 0))
		if x == 2088960:
			reached = true
		elif reached and x != 2088960 and x != 0:
			return i
	return -1


class _TrackingCamera extends Node3D:
	var size: float = 8.0
	var focus_point: Node3D
	var camera
	var last_pos: Vector3 = Vector3.ZERO
	var last_rot: Vector3 = Vector3.ZERO
	var last_ortho: float = 8.0

	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = self

	func request_takeover(_owner) -> void:
		pass

	func apply_takeover(pos: Vector3, rot: Vector3, ortho: float) -> void:
		last_pos = pos
		last_rot = rot
		last_ortho = ortho
		global_position = pos
		focus_point.global_rotation = rot
		size = ortho
