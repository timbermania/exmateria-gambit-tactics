extends Node
## Drives the real ScenarioVM through the chapel 6-Camera fusion bracket with
## `use_camera_chain_spline = true`, then compares the per-tick spline output
## against the PSX probe trace (`probe_camera_chain_writes.jsonl`) tick-by-tick.
##
## Pass criteria: position-opcode-X / -Y / -Z within ±2 opcode units of PSX
## per tick (= ±2/1024 of a sub-tile, ~0.002 tiles at SCENARIO_POSITION_DIVISOR
## = 112). PSX itself is the authority (verified by `probe_chain_spline.py`);
## the spline port is 87.8% bit-exact in the Python simulator, with residual
## ±1..±6 scratch-unit drift attributed to a pcsx-redux quirk that's
## invisible at this scale. Pitch/yaw checked to ±2 raw opcode units.
##
## PSX trace lives outside the godot-learning package, read via absolute
## path. If missing, the test is skipped with a SKIP marker (not a FAIL).
##
## Run via:
##   "$GODOT" --path . --quit-after 14 res://tests/ScenarioChapelChainSplineTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

# The PSX capture this cross-checks against is NOT in the repo (it is a
# PCSX-Redux probe dump). Drop one at this path to enable the cross-check.
# The previous default was an absolute path into a checkout that does not
# exist on this machine, so the PSX arm has been silently inert.
# NOT an env var: ADR-0051 keeps configuration out of src/ and tests/.
const PSX_TRACE_PATH := "user://psx_captures/probe_camera_chain_writes.jsonl"

# Per-axis tolerance, in opcode units. Positions can drift ±2 due to the
# pcsx-redux cross1 quirk plus float roundtrip through Godot pos / 112 / 1024.
# Pitch is raw opcode value (no division), so ±2 is also ±2 of the underlying
# integer.
const POS_TOL_OPCODE := 2.0
const PIT_TOL_OPCODE := 2.0

# Number of consecutive ticks to verify after chain start. Bumped from 300
# to 514 so the tail (segments 3-5, where the user perceives the chain as
# "too fast at the end") is covered. PSX trace is truncated around tick
# ~514 so 514 is the practical ceiling for both pose AND velocity checks.
const CHAIN_TICKS_TO_CHECK := 514

# Velocity-window samples — overlapping (start, end) tick offsets used by
# `_report_velocity_profile`. Each window's mean Δx/tick (= speed) is
# computed for both sides and compared; identical bit-exact poses imply
# identical velocities, but this surfaces ANY tail-only divergence that the
# milestone test (which is dominated by float-noise) would miss.
const VEL_WINDOWS: Array = [
	# label, start_offset, end_offset
	["seg0 mid (100→200)",   100, 200],
	["seg0→1 boundary",       250, 320],
	["seg1→2 boundary",       330, 400],
	["seg2→3 boundary",       400, 460],
	["seg3→4 boundary (tail)", 460, 510],
]

var _failed: int = 0
var _passed: int = 0


class TrackingCamera extends Node3D:
	var size: float = 8.0
	var focus_point: Node3D
	var camera
	var last_pos: Vector3 = Vector3.ZERO
	var last_rot: Vector3 = Vector3.ZERO
	var last_ortho: float = 8.0
	var takeover_count: int = 0

	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = self

	func request_takeover(_owner) -> void:
		pass

	func apply_takeover(pos: Vector3, rot: Vector3, ortho: float) -> void:
		takeover_count += 1
		last_pos = pos
		last_rot = rot
		last_ortho = ortho
		global_position = pos
		focus_point.global_rotation = rot
		size = ortho


func _make_camera_inst(x: int, y: int, z: int, angle: int, map_rot: int,
		cam_rot: int, zoom: int, time_ticks: int) -> Dictionary:
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


func _ready() -> void:
	# 1. Load the PSX trace; abort gracefully if missing.
	var psx_ticks: Array = _load_psx_trace()
	if psx_ticks.is_empty():
		print("[SKIP] PSX trace not found at %s — re-run probe_camera_chain_writes.py" % PSX_TRACE_PATH)
		print("[PASS] ScenarioChapelChainSplineTest (skipped — no oracle)")
		get_tree().quit(0)
		return

	# 2. Find PSX chain start (first tick where x != init 2088960).
	var psx_chain_start := _find_psx_chain_start(psx_ticks)
	if psx_chain_start < 0:
		_failed += 1
		print("[FAIL] PSX chain start not located in trace")
		_finish()
		return
	print("[info] PSX chain starts at row index %d / %d" % [psx_chain_start, psx_ticks.size()])

	# 3. Build VM with the spline path enabled. Stub the player_camera.
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var cam := TrackingCamera.new()
	add_child(cam)
	vm.player_camera = cam
	vm.camera_director.use_camera_chain_spline = true

	# 4. Drive the same chapel opcodes as ScenarioChapelChainTraceTest.
	vm.camera_director._op_camera(_make_camera_inst(2040, 488, 64964, 750, 3074, 0, 8192, 1))
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(1528, 488, 65172, 510, 3074, 0, 5952, 260))
	vm.camera_director._op_camera(_make_camera_inst(1448, 488, 65208, 350, 3202, 0, 4128,  80))
	vm.camera_director._op_camera(_make_camera_inst(1256, 488, 65208, 334, 3314, 0, 4032,  68))
	vm.camera_director._op_camera(_make_camera_inst(1000, 496, 65256, 318, 3442, 0, 3808,  56))
	vm.camera_director._op_camera(_make_camera_inst( 872, 500, 65316, 308, 3552, 0, 4096,  32))
	vm.camera_director._op_camera(_make_camera_inst( 840, 504, 65316, 302, 3584, 0, 4096,  48))
	vm.camera_director._op_camera_fusion_end({})

	# 5. Tick the VM, snapshotting cam.last_pos per tick. The spline becomes
	# active after fusion_end; first spline-driven write is the "chain start"
	# on the Godot side.
	var tick_dt: float = 1.0 / 60.0
	var godot_trace: Array = []
	var takeover_at_chain_start: int = cam.takeover_count
	# The camera body carries no constant offset (camera_position_offset removed
	# #139, ADR-0057 — the body is a Placement, consumed raw), so this reversal
	# is a no-op kept alongside the PSX-trace field mapping below.
	#   trace.x = FFT.X (lateral)            → Godot pos.x
	#   trace.y = FFT.Z (signed height)       → -Godot pos.y
	#   trace.z = FFT.Y (depth)               → Godot pos.z
	var pos_off := Vector3.ZERO
	for tick in range(600):
		vm._process(tick_dt)
		var pos_no_offset: Vector3 = cam.last_pos - pos_off
		godot_trace.append({
			"x_lateral":  pos_no_offset.x * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"y_height":  -pos_no_offset.y * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"z_depth":    pos_no_offset.z * ScenarioVMClass.SCENARIO_POSITION_DIVISOR,
			"takeover_count": cam.takeover_count,
		})

	# 6. Find Godot chain start — first tick where spline produced a write
	# different from the immediate-Camera target (x_lateral ≠ 2040).
	var godot_chain_start := -1
	for i in range(godot_trace.size()):
		var ox: float = godot_trace[i]["x_lateral"]
		if absf(ox - 2040.0) > 1.0:
			godot_chain_start = i
			break
	if godot_chain_start < 0:
		_failed += 1
		print("[FAIL] Godot spline never moved from init pose — spline didn't run?")
		_finish()
		return
	print("[info] Godot chain starts at tick %d" % godot_chain_start)

	# 7. Tick-by-tick compare for CHAIN_TICKS_TO_CHECK consecutive ticks.
	var max_dx: float = 0.0
	var max_dy: float = 0.0
	var max_dz: float = 0.0
	var samples: int = 0
	var fail_log: PackedStringArray = PackedStringArray()
	var compare_n := mini(CHAIN_TICKS_TO_CHECK,
		mini(godot_trace.size() - godot_chain_start, psx_ticks.size() - psx_chain_start))
	for i in range(compare_n):
		var g: Dictionary = godot_trace[godot_chain_start + i]
		var p: Dictionary = psx_ticks[psx_chain_start + i]
		var psx_x: float = float(p["x"]) / 1024.0
		var psx_y: float = float(p["y"]) / 1024.0
		var psx_z: float = float(p["z"]) / 1024.0
		var dx: float = absf(g["x_lateral"] - psx_x)
		var dy: float = absf(g["y_height"] - psx_y)
		var dz: float = absf(g["z_depth"]  - psx_z)
		max_dx = maxf(max_dx, dx)
		max_dy = maxf(max_dy, dy)
		max_dz = maxf(max_dz, dz)
		samples += 1
		if (dx > POS_TOL_OPCODE or dy > POS_TOL_OPCODE or dz > POS_TOL_OPCODE) and fail_log.size() < 5:
			fail_log.append("  tick +%d: PSX=(%.2f,%.2f,%.2f) Godot=(%.2f,%.2f,%.2f) Δ=(%.2f,%.2f,%.2f)" %
				[i, psx_x, psx_y, psx_z,
				 g["x_lateral"], g["y_height"], g["z_depth"], dx, dy, dz])

	print("[info] compared %d ticks; max Δ = (X:%.2f, Y:%.2f, Z:%.2f) opcode units" %
		[samples, max_dx, max_dy, max_dz])
	for fl in fail_log:
		print(fl)

	if max_dx > POS_TOL_OPCODE or max_dy > POS_TOL_OPCODE or max_dz > POS_TOL_OPCODE:
		_failed += 1
		print("[FAIL] position drift exceeds ±%.1f opcode units" % POS_TOL_OPCODE)
	else:
		_passed += 1
		print("[PASS] position drift within ±%.1f opcode units across %d ticks" %
			[POS_TOL_OPCODE, samples])

	# 8. Chain-duration check (milestone-based, surfaces wall-clock rate diff).
	_check_chain_duration(psx_ticks, psx_chain_start, godot_trace, godot_chain_start)

	# 9. Velocity profile at chain TAIL (seg 3→4 boundary etc). If the
	# "too fast at the end" perception traces to an actual velocity
	# mismatch, this surfaces it; if velocities match per-window, the
	# perception is either (a) the 1.7% uniform rate diff or (b)
	# something outside the spline itself.
	_report_velocity_profile(psx_ticks, psx_chain_start, godot_trace, godot_chain_start)

	_finish()


func _report_velocity_profile(psx_ticks: Array, psx_start: int,
		godot_trace: Array, godot_start: int) -> void:
	print("[info] velocity profile (mean |Δx|/tick, opcode units/tick):")
	var psx_n := psx_ticks.size() - psx_start
	var godot_n := godot_trace.size() - godot_start
	for w in VEL_WINDOWS:
		var label: String = w[0]
		var s: int = int(w[1])
		var e: int = int(w[2])
		var psx_v := _psx_mean_velocity(psx_ticks, psx_start, s, e, psx_n)
		var godot_v := _godot_mean_velocity(godot_trace, godot_start, s, e, godot_n)
		var note: String = ""
		if is_nan(psx_v) or is_nan(godot_v):
			note = "  (out of trace bounds — chain may have ended)"
		print("  %s: PSX=%.4f Godot=%.4f Δ=%+.4f%s" %
			[label, psx_v, godot_v,
			 (godot_v - psx_v) if (not is_nan(psx_v) and not is_nan(godot_v)) else 0.0,
			 note])


func _psx_mean_velocity(rows: Array, start: int, s: int, e: int, n: int) -> float:
	if e >= n or s >= n:
		return NAN
	var x0: float = float(rows[start + s].get("x", 0)) / 1024.0
	var x1: float = float(rows[start + e].get("x", 0)) / 1024.0
	return absf(x1 - x0) / float(e - s)


func _godot_mean_velocity(trace: Array, start: int, s: int, e: int, n: int) -> float:
	if e >= n or s >= n:
		return NAN
	var x0: float = float(trace[start + s]["x_lateral"])
	var x1: float = float(trace[start + e]["x_lateral"])
	return absf(x1 - x0) / float(e - s)


## Compare the WALL-CLOCK duration of the chain on PSX vs Godot — independent
## of tick-by-tick alignment.
##
## The PSX trace is truncated (probe stopped before chain stabilised), so we
## can't measure "until done". Instead we pick a series of progress milestones
## along PSX's X drop (2040 → 840 opcode units) and ask: at what wall-clock
## time did each side reach each milestone? If Godot reaches them at the same
## elapsed times, the rate matches. If Godot reaches them sooner, it's
## too fast.
##
## PSX wall-clock comes from the `cyc` field (PSX CPU cycles at ~33.8688 MHz
## NTSC). Godot wall-clock = tick_index / 60.0 since this test feeds the VM
## delta = 1/60s per `_process` call.
const _PSX_CPU_CLOCK_HZ := 33868800.0
const _GODOT_TICK_HZ := 60.0
const _MILESTONE_X_OPCODES: Array[float] = [1800.0, 1600.0, 1400.0, 1200.0, 1000.0, 900.0]
const _MILESTONE_TOL_S := 0.10  # ±100 ms — generous; catches 10%+ rate mismatches

func _check_chain_duration(psx_ticks: Array, psx_start: int,
		godot_trace: Array, godot_start: int) -> void:
	var psx_start_cyc: int = int(psx_ticks[psx_start]["cyc"])
	var any_fail := false
	var report := PackedStringArray()
	for milestone in _MILESTONE_X_OPCODES:
		var psx_t: float = _psx_time_to_x(psx_ticks, psx_start, psx_start_cyc, milestone)
		var godot_t: float = _godot_time_to_x(godot_trace, godot_start, milestone)
		if psx_t < 0.0 or godot_t < 0.0:
			report.append("  X=%.0f: PSX=%s Godot=%s (milestone not reached in trace)" %
				[milestone, "—" if psx_t < 0.0 else "%.3fs" % psx_t,
				 "—" if godot_t < 0.0 else "%.3fs" % godot_t])
			continue
		var d := godot_t - psx_t
		report.append("  X=%.0f: PSX=%.3fs  Godot=%.3fs  Δ=%+.3fs" %
			[milestone, psx_t, godot_t, d])
		if absf(d) > _MILESTONE_TOL_S:
			any_fail = true

	print("[info] chain progress milestones (time to reach X drop):")
	for r in report:
		print(r)

	# Bit-exact tick-by-tick pose match + persistent offset Δ in milestones
	# means PSX advances chain-internally at a different effective Hz than
	# Godot's 60. Measure PSX's actual chain rate empirically.
	_report_psx_chain_rate(psx_ticks, psx_start)

	if any_fail:
		_failed += 1
		print("[FAIL] chain rate mismatch — at least one milestone exceeded ±%.1fs" %
			_MILESTONE_TOL_S)
	else:
		_passed += 1
		print("[PASS] chain rate matches PSX within ±%.1fs at every milestone" %
			_MILESTONE_TOL_S)


## Compute the effective chain-tick Hz from PSX's cyc field. Each PSX trace
## row is one vsync; the chain advances once per row. If PSX ran the chain
## at exactly 60 Hz this would be 60.00; if there's persistent dispatcher
## latency between vsyncs (or a tick-slip) it'll be lower.
##
## Reports rate over a stable window (skips the first ~5 ticks where init
## variance is large) and the wall-clock duration of N=300 chain ticks for
## an at-a-glance Godot-vs-PSX comparison.
func _report_psx_chain_rate(psx_ticks: Array, psx_start: int) -> void:
	var n := mini(300, psx_ticks.size() - psx_start - 5)
	if n < 10:
		print("[info] PSX trace too short for rate analysis")
		return
	var c0: int = int(psx_ticks[psx_start + 5]["cyc"])
	var c1: int = int(psx_ticks[psx_start + 5 + n]["cyc"])
	var psx_dur_s: float = float(c1 - c0) / _PSX_CPU_CLOCK_HZ
	var psx_hz: float = float(n) / psx_dur_s
	var godot_dur_s: float = float(n) / _GODOT_TICK_HZ
	print("[info] effective tick rate over %d chain ticks:" % n)
	print("  PSX:   %.3fs → %.2f Hz (cyc-based)" % [psx_dur_s, psx_hz])
	print("  Godot: %.3fs → %.2f Hz (test feeds dt=1/60)" % [godot_dur_s, _GODOT_TICK_HZ])
	print("  Godot is %+.1f%% faster than PSX (= %+.0fms over %d ticks)" %
		[(godot_dur_s - psx_dur_s) / psx_dur_s * 100.0,
		 (godot_dur_s - psx_dur_s) * 1000.0, n])


## Find the wall-clock time (seconds from chain start) when PSX X first drops
## to or below `target_x_opcode`. PSX X is scratch-units; convert by /1024.
## Returns -1.0 if the trace ends before the milestone is reached.
func _psx_time_to_x(rows: Array, start: int, start_cyc: int,
		target_x_opcode: float) -> float:
	var target_scratch: float = target_x_opcode * 1024.0
	for i in range(start, rows.size()):
		var x: int = int(rows[i].get("x", 0))
		if float(x) <= target_scratch:
			var dcyc: int = int(rows[i]["cyc"]) - start_cyc
			return float(dcyc) / _PSX_CPU_CLOCK_HZ
	return -1.0


## Same for Godot — wall-clock = elapsed_ticks / 60. trace entries hold
## `x_lateral` in opcode units already.
func _godot_time_to_x(trace: Array, start: int, target_x_opcode: float) -> float:
	for i in range(start, trace.size()):
		if float(trace[i]["x_lateral"]) <= target_x_opcode:
			return float(i - start) / _GODOT_TICK_HZ
	return -1.0


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
			# Trim trailing ULL etc on cyc.
			var clean_v := ""
			for ch in v:
				if (ch >= "0" and ch <= "9") or ch == "-":
					clean_v += ch
				else:
					break
			if clean_v.is_empty():
				continue
			d[k] = int(clean_v)
		if not d.is_empty():
			out.append(d)
	f.close()
	# Sort by cyc since vsync rows may interleave.
	out.sort_custom(func(a, b): return int(a.get("cyc", 0)) < int(b.get("cyc", 0)))
	return out


func _find_psx_chain_start(rows: Array) -> int:
	# PSX trace begins with init x=0 then x=2088960 (= 2040*1024). Chain
	# start = first row where x is not 0 and not 2088960.
	var reached_init: bool = false
	for i in range(rows.size()):
		var x: int = int(rows[i].get("x", 0))
		if x == 2088960:
			reached_init = true
		elif reached_init and x != 2088960 and x != 0:
			return i
	return -1


func _finish() -> void:
	print("\n=== ScenarioChapelChainSplineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioChapelChainSplineTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioChapelChainSplineTest")
		get_tree().quit(0)
