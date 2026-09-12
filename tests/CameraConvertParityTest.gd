extends Node
## Parity guard for the PsxChirality → PsxMagnitude repoint + CameraCalibration extraction
## (ADR-0091 step 3). Pins the golden numbers of the magnitude conversions and the
## calibrated zoom↔ortho mapping so the consolidation proves byte/behaviour identical.
## Values are independent ground truth (28 raw = 1 tile, 4096 raw = 360° / 1.0× zoom,
## GODOT_CAMERA_SIZE = 12.6 calibration), worked by hand — NOT recomputed the code's way.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraConvertParityTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const PsxChirality = ExMateriaPlatform.PsxChirality
const CameraCalibration = ExMateriaPlatform.CameraCalibration

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_angle()
	_test_position_with_yflip()
	_test_zoom_via_facade()
	_test_zoom_via_calib()

	print("\n=== CameraConvertParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraConvertParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraConvertParityTest")
		get_tree().quit(0)


func _close(got: float, want: float, name: String) -> void:
	if absf(got - want) < 0.001:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


func _vclose(got: Vector3, want: Vector3, name: String) -> void:
	if got.distance_to(want) < 0.001:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _test_angle() -> void:
	_close(PsxMagnitude.angle_to_deg(4096.0), 360.0, "angle 4096 -> 360")
	_close(PsxMagnitude.angle_to_deg(2048.0), 180.0, "angle 2048 -> 180")
	_close(PsxMagnitude.angle_to_deg(1024.0), 90.0, "angle 1024 -> 90")
	_close(PsxMagnitude.deg_to_angle(360.0), 4096.0, "deg 360 -> 4096")
	_close(PsxMagnitude.deg_to_angle(90.0), 1024.0, "deg 90 -> 1024")


func _test_position_with_yflip() -> void:
	# 28 raw = 1 tile; Y flips (FFT -Y up, chirality preserved through the conversion).
	_vclose(PsxChirality.psx_position_to_godot(Vector3(28, 28, 28)), Vector3(1, -1, 1), "pos 28,28,28 -> 1,-1,1")
	_vclose(PsxChirality.psx_position_to_godot(Vector3(56, -28, 0)), Vector3(2, 1, 0), "pos 56,-28,0 -> 2,1,0")
	_vclose(PsxChirality.godot_position_to_psx(Vector3(1, 1, 1)), Vector3(28, -28, 28), "godot 1,1,1 -> 28,-28,28")


func _test_zoom_via_facade() -> void:
	# 4096 raw = 1.0× → ortho == GODOT_CAMERA_SIZE 12.6; 8192 = 2× → 6.3; 0 guarded to 12.6.
	_close(CameraCalibration.zoom_to_ortho_size(4096.0), 12.6, "zoom 4096 -> ortho 12.6")
	_close(CameraCalibration.zoom_to_ortho_size(8192.0), 6.3, "zoom 8192 -> ortho 6.3")
	_close(CameraCalibration.zoom_to_ortho_size(0.0), 12.6, "zoom 0 guarded -> 12.6")
	_close(CameraCalibration.ortho_size_to_zoom(12.6), 4096.0, "ortho 12.6 -> zoom 4096")
	_close(CameraCalibration.ortho_size_to_zoom(6.3), 8192.0, "ortho 6.3 -> zoom 8192")


func _test_zoom_via_calib() -> void:
	# CameraCalibration owns the calibrated mapping; the facade must delegate to identical numbers.
	_close(CameraCalibration.zoom_to_ortho_size(4096.0), 12.6, "calib zoom 4096 -> 12.6")
	_close(CameraCalibration.ortho_size_to_zoom(6.3), 8192.0, "calib ortho 6.3 -> 8192")
	_close(CameraCalibration.GODOT_CAMERA_SIZE, 12.6, "GODOT_CAMERA_SIZE == 12.6")
