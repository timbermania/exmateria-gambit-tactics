extends Node
## TDD guard for CameraUnits — the pure raw↔human affine + quantization tell that
## lets the Effect Studio camera inspector author in DEGREES / TILES / ZOOM-× while
## storage, the byte writer, and the runtime stay RAW s16 (authoring-boundary only).
##
## Unit facts (independent source of truth — do NOT re-derive from the code's factor):
##   * Angles: 4096 raw = 360°  → 90°=1024, 180°=2048, 45°=512, 360°=4096 (worked by hand).
##   * Position: ~28 raw = 1 tile.
##   * Zoom: 4096 raw = 1.0× baseline.
##
## The tell is HONEST, not paranoid: it fires only when the round-trip changes the value
## shown at the author's own precision — round(achieved, decimals) != round(typed, decimals).
## At 0.1° the raw encoding (0.088°/unit) is FINER than the display, so angles never trip
## it; a coarser unit like tiles at 0.01 does.
##
## Seams under test (pre-agreed):
##   1. CameraUnits.to_raw(display, unit)     -> int    (deg/tiles/× → raw s16)
##   2. CameraUnits.to_display(raw, unit)     -> float  (inverse)
##   3. CameraUnits.quantize(display, unit)   -> {raw, achieved_display, ok, reason}
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraUnitsTest.tscn

const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_degrees_to_raw_known_pairs()
	_test_raw_to_degrees_known_pairs()
	_test_tiles_and_zoom_known_pairs()
	_test_roundtrip_is_stable()
	_test_tell_silent_when_angle_shows_the_typed_value()
	_test_tell_fires_when_tiles_cannot_show_the_typed_value()

	print("\n=== CameraUnitsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraUnitsTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraUnitsTest")
		get_tree().quit(0)


func _test_degrees_to_raw_known_pairs() -> void:
	_assert_eq(CameraUnits.to_raw(90.0, CameraUnits.ANGLE_DEG), 1024, "90° → raw 1024")
	_assert_eq(CameraUnits.to_raw(180.0, CameraUnits.ANGLE_DEG), 2048, "180° → raw 2048")
	_assert_eq(CameraUnits.to_raw(45.0, CameraUnits.ANGLE_DEG), 512, "45° → raw 512")
	_assert_eq(CameraUnits.to_raw(360.0, CameraUnits.ANGLE_DEG), 4096, "360° → raw 4096")
	# 30° is NOT an integer number of raw units (341.33…) — round to nearest.
	_assert_eq(CameraUnits.to_raw(30.0, CameraUnits.ANGLE_DEG), 341, "30° → raw 341 (rounded)")


func _test_raw_to_degrees_known_pairs() -> void:
	_assert_close(CameraUnits.to_display(1024, CameraUnits.ANGLE_DEG), 90.0, "raw 1024 → 90°")
	_assert_close(CameraUnits.to_display(2048, CameraUnits.ANGLE_DEG), 180.0, "raw 2048 → 180°")
	_assert_close(CameraUnits.to_display(512, CameraUnits.ANGLE_DEG), 45.0, "raw 512 → 45°")


func _test_tiles_and_zoom_known_pairs() -> void:
	_assert_eq(CameraUnits.to_raw(1.0, CameraUnits.POS_TILES), 28, "1 tile → raw 28")
	_assert_close(CameraUnits.to_display(56, CameraUnits.POS_TILES), 2.0, "raw 56 → 2 tiles")
	_assert_eq(CameraUnits.to_raw(1.0, CameraUnits.ZOOM_X), 4096, "1.0× → raw 4096")
	_assert_eq(CameraUnits.to_raw(2.0, CameraUnits.ZOOM_X), 8192, "2.0× → raw 8192")
	_assert_close(CameraUnits.to_display(2048, CameraUnits.ZOOM_X), 0.5, "raw 2048 → 0.5×")


func _test_roundtrip_is_stable() -> void:
	# raw → display → raw returns the same raw for representable values.
	for raw in [0, 512, 1024, -1024, 2048]:
		var back: int = CameraUnits.to_raw(CameraUnits.to_display(raw, CameraUnits.ANGLE_DEG), CameraUnits.ANGLE_DEG)
		_assert_eq(back, raw, "angle raw %d survives round-trip" % raw)


func _test_tell_silent_when_angle_shows_the_typed_value() -> void:
	# At 0.1°, the raw grid is finer than the display, so a typed degree always shows back.
	for deg in [90.0, 45.0, 30.0, 12.5]:
		var q: Dictionary = CameraUnits.quantize(deg, CameraUnits.ANGLE_DEG)
		_assert_true(q["ok"], "angle %s° is faithful at 0.1° (tell silent)" % str(deg))


func _test_tell_fires_when_tiles_cannot_show_the_typed_value() -> void:
	# 1.01 tiles → round(1.01·28)=28 → 28/28 = 1.00 tiles ≠ 1.01, so the tell must fire and
	# report the achieved value the author will actually get.
	var q: Dictionary = CameraUnits.quantize(1.01, CameraUnits.POS_TILES)
	_assert_eq(q["raw"], 28, "1.01 tiles → raw 28")
	_assert_false(q["ok"], "1.01 tiles is NOT representable at 0.01 (tell fires)")
	_assert_close(q["achieved_display"], 1.00, "tell reports achieved 1.00 tiles")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_close(actual: float, expected: float, label: String) -> void:
	if abs(actual - expected) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_false(cond: bool, label: String) -> void:
	if not cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected false" % label)
