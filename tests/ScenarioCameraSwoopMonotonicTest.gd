extends Node
## REGRESSION guard for BUG #1 — the fusion-swoop vertical jerk
## (`handoff_scenario_camera_vertical_followup.md`, living doc F11/F12).
##
## ROOT CAUSE (F11): `camera_aim_floor_y` re-pinned the camera body Y to the
## terrain floor EVERY tick. During the swoop the body sweeps laterally across
## tiles of wildly different height, so the per-tick pin produced ±5–8 tile
## vertical jumps instead of a smooth descent.
##
## STATIC + DYNAMIC proof (F12) that the pin is wrong here: the PSX scenario
## camera Y is a PURE interpolated opcode value — never a per-tile terrain pin.
##   - event Camera writer FUN_801474a4 @ 0x801474a4 → base + opcode delta, no
##     terrain read; ticker camera_per_vsync_ticker @ 0x801439c0 latches scratch
##     pos → GTE with no tile lookup (only a GLOBAL datum DAT_80165ff0<<12, =0 in
##     chapel). The camera is married to a tile ONLY in the effect-camera
##     tile-source path FUN_801aab90 @ 0x801aab90 (Y=−height·12), unused here.
##   - live capture `probe_camera_swoop_terrain.py`: work_position.y descends
##     SMOOTHLY opcode_Z −572→−220, no terrain snapping.
##
## FIX: `_apply_chain_spline_pose` passes `aim_floor=false` (raw descent during
## motion); the floored settle is re-applied once when the chain drains
## (`_settle_camera_onto_floor`). This test would have caught BUG #1 (the
## `ScenarioCameraFloorAimCalibTest` only checks the SETTLED frame, so it stayed
## green through the regression).
##
## Harness: drive the REAL ScenarioVM through the chapel 6-Camera fusion bracket
## (same opcodes as `ScenarioChapelChainTraceTest`) with `camera_aim_floor_y` ON
## and a MOCK map whose tile heights JUMP between adjacent columns (incl. "trap"
## heights 8.18 / 0.46 / 1.0 OUTSIDE the raw descent band). Assert:
##   1. During the swoop the body Y stays in the raw band [1.4, 5.6] (never snaps
##      to a trap tile) and has no tick-to-tick jump > MAX_JUMP — i.e. SMOOTH.
##   2. After the chain drains + settles, the body Y IS the floored value at the
##      final tile (≈3.25) — proving floor-aim still fires for the settled shot.
##
## Run headful (NEVER --headless). Picked up by tests/run_all_tests.sh.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainFixture = ExMateriaBattlefield.TerrainFixture


const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

const RAW_BAND_LO := 1.4          # raw swoop Y range is ~[1.96, 5.11]
const RAW_BAND_HI := 5.6
const MAX_JUMP := 0.75            # raw descent moves <0.02/tick; F11 jumps were 5–8
const SETTLE_FLOOR_Y := 3.25      # mock floor at the final tile (col 7)
const SETTLE_TOL := 0.35

var _failed: int = 0
var _passed: int = 0


## The JUMPY map this gate is built on. Columns 13/12/11/10 carry "trap" floors
## (8.18 / 0.46 / 0.46 / 1.0) that sit OUTSIDE the raw descent band [1.4, 5.6] — so
## if the camera ever pinned to terrain mid-swoop the body Y would leave the band and
## assertion 1 fails. Every other column is 3.0, and the settle column (7) is 3.25,
## which is `SETTLE_FLOOR_Y`.
##
## 🔴 THESE ARE NOT FFT HALF-STEPS AND THEY ARE STATED AS CORNERS FOR THAT REASON.
## 8.18 and 0.46 are world units picked to straddle the band; no `height` integer
## produces them (`surface_y` is `(12h + 1)/28`, a 0.43-unit ladder). `put_shape` is
## ADR-0218 dec. 6's escape hatch and this is the case it was kept for — a fixture
## restricted to `put` could not state this map at all. `flat_quad` puts the four
## corners where the exporter would, so the tile lands at its own centre and
## `world_position_at(x, z).y` is exactly the number below, which is the only thing
## `_framed_floor_y` reads.
##
## The `height` argument is the gameplay half-step and is only read by the director's
## focal-tile LOG line; it is the rounded world Y, as the double's `terrain_at` made it.
const COLUMN_Y := {
	18: 5.0, 17: 5.0, 16: 5.0, 15: 4.8, 14: 4.5,
	13: 8.18, 12: 0.46, 11: 0.46, 10: 1.0,
	9: 3.46, 8: 3.46, 7: 3.25, 6: 3.25,
}
const DEFAULT_COLUMN_Y := 3.0

## ⚠️ BOUNDED (ADR-0218 dec. 4), where the double was an infinite plane answering for
## every square in the world. `_framed_floor_y` falls back to the body's own Y off-grid,
## so the bound has to contain the whole swoop — that is a real fact about this scene
## the unbounded double was hiding, and it is asserted below rather than assumed.
const MAP_BOUNDS := Rect2i(0, 0, 24, 16)


func _build_map() -> TerrainFixture:
	var fixture := TerrainFixture.new()
	for gz in range(MAP_BOUNDS.position.y, MAP_BOUNDS.position.y + MAP_BOUNDS.size.y):
		for gx in range(MAP_BOUNDS.position.x, MAP_BOUNDS.position.x + MAP_BOUNDS.size.x):
			var y: float = COLUMN_Y.get(gx, DEFAULT_COLUMN_Y)
			fixture.put_shape(Vector2i(gx, gz), MapConstants.flat_quad(gx, gz, y),
				int(round(y)))
	return fixture


class TrackingCamera extends Node3D:
	var size: float = 8.0
	var focus_point: Node3D
	var camera
	func _init() -> void:
		focus_point = Node3D.new()
		add_child(focus_point)
		camera = self
	func request_takeover(_owner) -> void:
		pass
	func apply_takeover(pos: Vector3, rot: Vector3, ortho: float) -> void:
		global_position = pos
		focus_point.global_rotation = rot
		size = ortho


func _make_camera_inst(x: int, y: int, z: int, angle: int, map_rot: int,
		cam_rot: int, zoom: int, time_ticks: int) -> Dictionary:
	return {"name": "Camera", "opcode": 0x19, "offset": 0, "params": [
		{"name": "X", "value": x, "bytes": 2},
		{"name": "Z", "value": z, "bytes": 2},
		{"name": "Y", "value": y, "bytes": 2},
		{"name": "Angle", "value": angle, "bytes": 2},
		{"name": "Map Rotation", "value": map_rot, "bytes": 2},
		{"name": "Camera Rotation", "value": cam_rot, "bytes": 2},
		{"name": "Zoom", "value": zoom, "bytes": 2},
		{"name": "Time", "value": time_ticks, "bytes": 2}]}


func _ready() -> void:
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var cam := TrackingCamera.new()
	add_child(cam)
	vm.player_camera = cam
	var map := _build_map()
	add_child(map)
	vm.map_composer = map
	vm.map_size_z = 10

	# The fix under test: floor-aim ON, offset zeroed (so body.x re-derivation is
	# clean and the raw band assertions hold). Empirical-orientation baseline.
	vm.camera_director.camera_aim_floor_y = true
	vm.camera_director.camera_backrotate_pivot = false
	# Isolate the floor-aim swoop behaviour: hold OFF the authentic vertical-datum fix
	# (F20), whose ortho-scaled view-up shift would widen the raw descent band this gate
	# asserts. Its swoop smoothness (a gradual zoom-scaled offset) is verified headful;
	# here we guard only that floor-aim never per-tick-pins to a trap tile (F11).
	vm.camera_director.camera_vertical_datum = false

	# Chapel chunk: immediate Camera (PC=56) then the 6-Camera fusion bracket
	# (PCs 122/139/156/173/190/207). Z values are raw u16 (e.g. 64964 = −572).
	vm.camera_director._op_camera(_make_camera_inst(2040, 488, 64964, 750, 3074, 0, 8192, 1))
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(1528, 488, 65172, 510, 3074, 0, 5952, 260))
	vm.camera_director._op_camera(_make_camera_inst(1448, 488, 65208, 350, 3202, 0, 4128,  80))
	vm.camera_director._op_camera(_make_camera_inst(1256, 488, 65208, 334, 3314, 0, 4032,  68))
	vm.camera_director._op_camera(_make_camera_inst(1000, 496, 65256, 318, 3442, 0, 3808,  56))
	vm.camera_director._op_camera(_make_camera_inst( 872, 500, 65316, 308, 3552, 0, 4096,  32))
	vm.camera_director._op_camera(_make_camera_inst( 840, 504, 65316, 302, 3584, 0, 4096,  48))
	vm.camera_director._op_camera_fusion_end({})

	# Drive 600 ticks (chain sum 544 + drain + 12-tick settle + tail). Record
	# body Y each tick.
	var tick_dt: float = 1.0 / 60.0
	var ys: PackedFloat32Array = PackedFloat32Array()
	for tick in range(600):
		vm._process(tick_dt)
		ys.append(cam.global_position.y)

	# --- Assertion 1: smooth swoop (no terrain pin) over the spline window. ---
	# Use ticks [10, 520]: safely inside the 544-tick chain, before drain+settle.
	var worst_jump := 0.0
	var worst_jump_tick := -1
	var out_of_band := 0
	var worst_band_y := 3.0
	for t in range(10, 521):
		var y: float = ys[t]
		if y < RAW_BAND_LO or y > RAW_BAND_HI:
			out_of_band += 1
			if absf(y - 3.0) > absf(worst_band_y - 3.0):
				worst_band_y = y
		var dj: float = absf(ys[t] - ys[t - 1])
		if dj > worst_jump:
			worst_jump = dj
			worst_jump_tick = t

	_check(out_of_band == 0,
		("swoop body Y stays in raw band [%.1f,%.1f] — never pins to a trap tile "
		+ "(%d ticks out of band, worst Y=%.2f)") % [
			RAW_BAND_LO, RAW_BAND_HI, out_of_band, worst_band_y])
	_check(worst_jump <= MAX_JUMP,
		"swoop body Y is smooth — max tick-to-tick jump %.3f ≤ %.2f (at tick %d)" % [
			worst_jump, MAX_JUMP, worst_jump_tick])

	# --- Assertion 2: floored settle after drain (floor-aim still fires). ---
	# The bound is load-bearing: off-grid, `_framed_floor_y` hands back the body's own
	# Y and the settle assertion below would be measuring nothing at all. The double
	# this replaced was unbounded, so it could not have told anyone (ADR-0218 dec. 4).
	var final_grid := Vector2i(
		int(floor(cam.global_position.x)), int(floor(cam.global_position.z)))
	_check(MAP_BOUNDS.has_point(final_grid),
		"the settled body sits on a stated tile %s, not off the fixture's edge"
			% str(final_grid))

	var final_y: float = ys[ys.size() - 1]
	_check(absf(final_y - SETTLE_FLOOR_Y) <= SETTLE_TOL,
		("settled body Y %.3f lands on the framed floor %.2f (±%.2f) — floor-aim "
		+ "fires for the at-rest shot") % [final_y, SETTLE_FLOOR_Y, SETTLE_TOL])
	# And it must have risen off the RAW final (~1.96) — proving the settle ease
	# actually re-applied the floor, not just held the raw swoop end.
	_check(final_y >= 2.5,
		"settled body Y %.3f rose off the raw swoop-end (~1.96) onto the floor" % final_y)

	_finish()


func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  [ok] %s" % name)
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	print("\n=== ScenarioCameraSwoopMonotonicTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or _passed == 0:
		print("[FAIL] ScenarioCameraSwoopMonotonicTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraSwoopMonotonicTest")
		get_tree().quit(0)
