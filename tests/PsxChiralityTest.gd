extends Node
## Pure-math tests for PsxChirality.psx_angles_to_godot_rotation.
##
## ADR-0052 originally proposed reversing yaw direction. Empirical: the
## chapel scene goes black with `-yaw_deg`; the original `(yaw_deg - 360)`
## formula is geometrically correct after the parser-time mesh Z-flip lands
## because camera position mirrors with the mesh, so look-direction is
## preserved. Pitch is unchanged either way.
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/PsxChiralityTest.tscn

const PsxChirality = ExMateriaPlatform.PsxChirality

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_yaw_zero_maps_to_negative_2pi()
	_test_yaw_270deg_chapel_first_shot()
	_test_pitch_unchanged()
	_test_roll_dropped()

	print("\n=== PsxChiralityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PsxChiralityTest")
		get_tree().quit(1)
	else:
		print("[PASS] PsxChiralityTest")
		get_tree().quit(0)


func _assert_almost_equal(got: float, want: float, name: String) -> void:
	if absf(got - want) < 0.0001:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


func _test_yaw_zero_maps_to_negative_2pi() -> void:
	# Original formula keeps `(yaw_deg - 360.0)` for readability; yaw=0 →
	# deg_to_rad(-360) which is geometrically equivalent to 0.
	var r = PsxChirality.psx_angles_to_godot_rotation(0.0, 0.0, 0.0)
	_assert_almost_equal(r.y, deg_to_rad(-360.0), "yaw=0 → -360° ≡ 0°")


func _test_yaw_270deg_chapel_first_shot() -> void:
	# Chapel scenario first Camera opcode has map_rot=3074 ≈ 270°. The
	# camera body is east of the map; the resulting Godot yaw -90° rotates
	# the camera's forward (-Z) toward -X (west, looking back at the map).
	var r = PsxChirality.psx_angles_to_godot_rotation(0.0, 3074.0, 0.0)
	var want := deg_to_rad(3074.0 * 360.0 / 4096.0 - 360.0)
	_assert_almost_equal(r.y, want, "yaw=3074 (~270°) → ~-90°")


func _test_pitch_unchanged() -> void:
	# Pitch passes through the same PSX-angle-to-deg conversion as yaw; we
	# compare against that same conversion so the test isn't fragile to the
	# 4096-units-per-360° quantization.
	var r = PsxChirality.psx_angles_to_godot_rotation(302.0, 0.0, 0.0)
	var want_pitch_deg := 302.0 * 360.0 / 4096.0
	_assert_almost_equal(r.x, deg_to_rad(-want_pitch_deg), "pitch=302 → -pitch_deg")


func _test_roll_dropped() -> void:
	# Roll is discarded by the existing implementation; ADR-0052 doesn't change that.
	var r = PsxChirality.psx_angles_to_godot_rotation(0.0, 0.0, 1024.0)
	_assert_almost_equal(r.z, 0.0, "roll=1024 → z=0 (discarded)")
