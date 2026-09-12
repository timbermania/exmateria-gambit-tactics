extends Node
## Per-tick logger for the chapel-cinematic 6-Camera fusion bracket.
##
## This test mirrors PSX `probe_camera_chain_writes.py`: drives the real
## ScenarioVM (with a StubCamera) through the same opcodes the chapel
## chunk contains (immediate Camera at PC=56, Fusion Start, 6 Cameras at
## PCs 122/139/156/173/190/207, Fusion End) and writes one row per
## simulated 60 Hz tick to
## `user://last_run/godot_camera_chain_writes.jsonl`.
##
## Each row carries (tick, x_opcode_equiv, y, z, ortho_equiv_zoom) so the
## post-processor can diff against the PSX trace:
## https://[…]/scenario_1_captures/last_run/probe_camera_chain_writes.jsonl
##
## Conversion back to PSX-comparable units:
##   - opcode X = round(godot_pos.x * SCENARIO_POSITION_DIVISOR)
##   - opcode Y = round(godot_pos.z * SCENARIO_POSITION_DIVISOR)
##     (Godot Y-up vs PSX Z-fwd swap; see `_apply_camera_pose_no_block`)
##   - PSX scratch X = opcode X * 1024 (the 10-bit fractional shift
##     verified by PSX probe — `scratch_X / opcode_X = 1024`)
##
## Pass/fail: prints PASS if the per-tick trace covers the full 6-segment
## chain (first tick's X is near 2040, last tick's X is near 840 in
## opcode units). Detailed diff happens in the Python analyzer.
##
## Run via:
##   "$GODOT" --path . --quit-after 12 res://tests/ScenarioChapelChainTraceTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


class TrackingCamera extends Node3D:
	var size: float = 8.0
	var focus_point: Node3D
	var camera  # self-ref, exposes .size
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
	var vm: ScenarioVMClass = ScenarioVMClass.new()
	add_child(vm)
	var cam := TrackingCamera.new()
	add_child(cam)
	vm.player_camera = cam

	# This test validates the spline TRAJECTORY in opcode space — it re-derives
	# opcode units from the Godot body via `pos * SCENARIO_POSITION_DIVISOR`
	# (lines below). That inversion is only exact for the raw, un-offset mapping.
	# The old constant camera_position_offset that biased X is gone (removed #139,
	# ADR-0057 — the camera body is a Placement, consumed raw), so only the H1
	# framing pivot still needs isolating here:
	#   - `camera_backrotate_pivot` (the H1 framing fix) rotates the body by the
	#     view basis, which `pos * 112` can't invert without the per-tick angle.
	vm.camera_director.camera_backrotate_pivot = false
	#   - `camera_aim_floor_y` (the F8/F9 vertical fix) replaces the body Y with a
	#     map-tile floor_y; this VM-only path wires no `map_composer` so it would
	#     no-op anyway, but pin it OFF so the `-pos.y * 112` opcode-Z re-derivation
	#     in the loop stays exact regardless of the field default.
	vm.camera_director.camera_aim_floor_y = false

	# Immediate Camera op (chapel chunk PC=56): X=2040, Y=488, Z=64964,
	# Angle=750, MapRot=3074, CamRot=0, Zoom=8192, Time=1 → snaps the
	# camera to the initial chapel pose.
	vm.camera_director._op_camera(_make_camera_inst(2040, 488, 64964, 750, 3074, 0, 8192, 1))

	# Open the bracket and queue the 6 Cameras (chapel chunk PCs
	# 122/139/156/173/190/207) verbatim.
	vm.camera_director._op_camera_fusion_start({})
	vm.camera_director._op_camera(_make_camera_inst(1528, 488, 65172, 510, 3074, 0, 5952, 260))
	vm.camera_director._op_camera(_make_camera_inst(1448, 488, 65208, 350, 3202, 0, 4128,  80))
	vm.camera_director._op_camera(_make_camera_inst(1256, 488, 65208, 334, 3314, 0, 4032,  68))
	vm.camera_director._op_camera(_make_camera_inst(1000, 496, 65256, 318, 3442, 0, 3808,  56))
	vm.camera_director._op_camera(_make_camera_inst( 872, 500, 65316, 308, 3552, 0, 4096,  32))
	vm.camera_director._op_camera(_make_camera_inst( 840, 504, 65316, 302, 3584, 0, 4096,  48))
	vm.camera_director._op_camera_fusion_end({})

	# Drive the lerp chain. Total Time = 544 ticks (chapel sum); we
	# sample 600 ticks (10 s) to capture the full chain + a tail.
	var tick_dt: float = 1.0 / 60.0
	var rows: PackedStringArray = PackedStringArray()
	rows.append('{"comment": "Godot mirror of PSX probe_camera_chain_writes; '
		+ 'opcode_X = round(pos.x * %.1f); PSX scratch X = opcode_X * 1024"}'
		% ScenarioVMClass.SCENARIO_POSITION_DIVISOR)

	for tick in range(600):
		vm._process(tick_dt)
		# Re-derive opcode-equivalent X/Y/Z so we can diff against PSX
		# scratch / 1024.
		var px: float = cam.last_pos.x * ScenarioVMClass.SCENARIO_POSITION_DIVISOR
		var pz: float = -cam.last_pos.y * ScenarioVMClass.SCENARIO_POSITION_DIVISOR
		var py: float = cam.last_pos.z * ScenarioVMClass.SCENARIO_POSITION_DIVISOR
		# Reverse `ortho = ortho_at_1x * 4096 / zoom` → zoom = ortho_at_1x * 4096 / ortho
		var zoom_eq: float = vm.camera_director.camera_ortho_at_1x_zoom * 4096.0 / max(0.001, cam.last_ortho)
		rows.append('{"tick":%d, "godot_x":%.4f, "godot_y":%.4f, "godot_z":%.4f, '
			% [tick, cam.last_pos.x, cam.last_pos.y, cam.last_pos.z]
			+ '"opcode_x":%.2f, "opcode_y":%.2f, "opcode_z":%.2f, '
			% [px, py, pz]
			+ '"ortho":%.4f, "zoom_eq":%.2f, "takeover_count":%d}'
			% [cam.last_ortho, zoom_eq, cam.takeover_count])

	var out_path := "user://last_run/godot_camera_chain_writes.jsonl"
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		_failed += 1
		print("[FAIL] could not open %s" % out_path)
		_finish()
		return
	for r in rows:
		f.store_line(r)
	f.close()
	print("wrote %d rows to %s (abs: %s)" %
		[rows.size(), out_path, ProjectSettings.globalize_path(out_path)])

	# Smoke checks: first sample after immediate Camera should sit near
	# X = 2040 / 112 ≈ 18.21; last sample should be near 840 / 112 ≈ 7.5.
	var initial_x: float = cam.last_pos.x  # filled by the LAST tick's apply_takeover
	# Re-run a single tick of just the immediate to capture the start.
	# Instead, read tick 0's row: opcode_x near 2040.
	# Re-parse row 1 (first non-comment).
	var first_row := rows[1]  # tick=0
	var first_opcode_x := _extract_float(first_row, "opcode_x")
	var last_row := rows[rows.size() - 1]
	var last_opcode_x := _extract_float(last_row, "opcode_x")

	_assert_near(first_opcode_x, 2040.0, 50.0,
		"first-tick opcode X near chapel-init 2040 (got %.2f)" % first_opcode_x)
	_assert_near(last_opcode_x, 840.0, 50.0,
		"last-tick opcode X near seg-6 target 840 (got %.2f)" % last_opcode_x)

	_finish()


func _extract_float(jsonl_row: String, key: String) -> float:
	# Quick-and-dirty: find `"key":<num>`.
	var needle := "\"%s\":" % key
	var i := jsonl_row.find(needle)
	if i < 0:
		return NAN
	var rest := jsonl_row.substr(i + needle.length()).strip_edges()
	# Read up to next comma or close-brace.
	var j := 0
	while j < rest.length():
		var c := rest.unicode_at(j)
		var is_digit_or_punct := (c >= 48 and c <= 57) or c == 46 or c == 45 or c == 43 or c == 101 or c == 69  # 0-9 . - + e E
		if not is_digit_or_punct:
			break
		j += 1
	return float(rest.substr(0, j))


func _assert_near(got: float, want: float, tol: float, name: String) -> void:
	if absf(got - want) <= tol:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	print("\n=== ScenarioChapelChainTraceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioChapelChainTraceTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioChapelChainTraceTest")
		get_tree().quit(0)
