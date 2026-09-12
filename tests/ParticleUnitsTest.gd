extends Node
## TDD guard for ParticleUnits (ADR-0089) — the raw↔human affine for emitter
## parameter authoring, the CameraUnits pattern. Only PROVEN conversions get a
## descriptor: positions/spreads/offsets in tiles (28 raw/tile), angles in degrees
## (4096 raw = 360°), inertia as a × multiplier (4096 raw = ×1.0). Storage, writer
## and runtime stay raw; quantize reports the honest "you'll actually get" tell.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleUnitsTest.tscn

const Units = preload("res://src/effects/studio/ParticleUnits.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_position_tiles()
	_test_angle_degrees()
	_test_inertia_multiplier()
	_test_quantize_honesty()

	print("\n=== ParticleUnitsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleUnitsTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleUnitsTest")
		get_tree().quit(0)


## 28 raw units per tile (the parser's POSITION_DIVISOR).
func _test_position_tiles() -> void:
	_assert_approx(Units.to_display(28, Units.POS_TILES), 1.0, "28 raw = 1 tile")
	_assert_eq(Units.to_raw(-2.0, Units.POS_TILES), -56, "-2 tiles = -56 raw")


## 4096 raw = 360°: quarter turn 1024 = 90°, 45° = 512 exact.
func _test_angle_degrees() -> void:
	_assert_approx(Units.to_display(1024, Units.ANGLE_DEG), 90.0, "1024 raw = 90°")
	_assert_eq(Units.to_raw(45.0, Units.ANGLE_DEG), 512, "45° = 512 raw")


## Inertia raw 4096 = ×1.0 neutral (keep velocity).
func _test_inertia_multiplier() -> void:
	_assert_approx(Units.to_display(4096, Units.INERTIA_X), 1.0, "4096 raw = ×1.0")
	_assert_eq(Units.to_raw(0.5, Units.INERTIA_X), 2048, "×0.5 = 2048 raw")


## The tell fires only when the achieved value differs at the author's own precision:
## 0.01 tiles rounds to raw 0 (achieved 0.00) → warn; ×1.0 inertia is exact → silent.
func _test_quantize_honesty() -> void:
	var q: Dictionary = Units.quantize(0.01, Units.POS_TILES)
	_assert_eq(q.get("raw"), 0, "0.01 tiles rounds to raw 0")
	_assert_true(not bool(q.get("ok", true)), "coarse tile encoding warns")
	_assert_true(bool(Units.quantize(1.0, Units.INERTIA_X).get("ok", false)), "exact value stays silent")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) < 0.0001:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %f, got %f" % [label, expected, actual])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
