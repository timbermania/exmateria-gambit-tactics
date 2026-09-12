extends Node
## Golden-value guard for PsxMagnitude — the ONE home for PSX continuous-magnitude ↔
## game-unit conversions (ADR-0091). This is consolidation, not invention: every
## number here is the byte-validated mapping already proven by parse_effect.py /
## EmitterChannel. The literals are independent ground truth (28 world units per
## tile, 4096 = one full turn, the radial/accel divisors documented in
## parse_effect.py), NOT recomputed the way PsxMagnitude computes them — so this test
## can disagree with a regression. Pure static functions: no scene, no nodes.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/PsxMagnitudeTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4). `PsxMagnitude` joined the list
## at #1220, when the PSX trio came home from `src/effects/` and lost its three
## bare `class_name`s on the way; the subject of this test is the same file at a
## new address, which is why the golden values below did not move.
const PsxNum = ExMateriaPlatform.PsxNum
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_base_constants()
	_test_angle()
	_test_tiles()
	_test_radial_velocity()
	_test_accel_and_homing()
	_test_round_trips()

	print("\n=== PsxMagnitudeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] PsxMagnitudeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] PsxMagnitudeTest")
		get_tree().quit(1)
	else:
		print("[PASS] PsxMagnitudeTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _approx(got: float, want: float, name: String) -> void:
	if is_equal_approx(got, want) or absf(got - want) < 1e-6:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _test_base_constants() -> void:
	# The universal bases live once (ADR-0091 §2): 4096 = one full turn (identical
	# to PsxNum.TURN_12BIT), 28 = world units per tile.
	_eq(PsxMagnitude.FULL_TURN, 4096, "FULL_TURN == 4096")
	_eq(PsxMagnitude.FULL_TURN, PsxNum.TURN_12BIT, "FULL_TURN shares PsxNum.TURN_12BIT")
	_eq(PsxMagnitude.UNITS_PER_TILE, 28, "UNITS_PER_TILE == 28")
	_eq(PsxMagnitude.UNITS_PER_TILE, PsxNum.UNITS_PER_TILE, "UNITS_PER_TILE shares PsxNum.UNITS_PER_TILE")


func _test_angle() -> void:
	# 4096 = 360° = TAU rad (parse_effect.py convert_angle).
	_approx(PsxMagnitude.angle_to_rad(0), 0.0, "angle_to_rad 0")
	_approx(PsxMagnitude.angle_to_rad(4096), TAU, "angle_to_rad full turn -> TAU")
	_approx(PsxMagnitude.angle_to_rad(1024), TAU / 4.0, "angle_to_rad quarter -> TAU/4")
	_approx(PsxMagnitude.angle_to_deg(4096), 360.0, "angle_to_deg full turn -> 360")
	_approx(PsxMagnitude.angle_to_deg(2048), 180.0, "angle_to_deg half -> 180")
	# game -> raw (studio round-trip / byte-exact write side).
	_approx(PsxMagnitude.rad_to_angle(TAU), 4096.0, "rad_to_angle TAU -> 4096")
	_approx(PsxMagnitude.deg_to_angle(360.0), 4096.0, "deg_to_angle 360 -> 4096")
	_approx(PsxMagnitude.deg_to_angle(90.0), 1024.0, "deg_to_angle 90 -> 1024")


func _test_tiles() -> void:
	# 28 FFT world units per Godot tile (parse_effect.py POSITION_DIVISOR).
	_approx(PsxMagnitude.tile_to_game(28), 1.0, "tile_to_game 28 -> 1.0")
	_approx(PsxMagnitude.tile_to_game(56), 2.0, "tile_to_game 56 -> 2.0")
	_approx(PsxMagnitude.tile_to_game(-28), -1.0, "tile_to_game -28 -> -1.0")
	_approx(PsxMagnitude.game_to_tile(1.0), 28.0, "game_to_tile 1.0 -> 28")
	_approx(PsxMagnitude.game_to_tile(2.5), 70.0, "game_to_tile 2.5 -> 70")


func _test_radial_velocity() -> void:
	# radial * 8 / 4096 / 28 = radial / 14336 (parse_effect.py VELOCITY_DIVISOR).
	_approx(PsxMagnitude.radial_velocity_to_game(14336), 1.0, "radial_to_game 14336 -> 1.0")
	_approx(PsxMagnitude.radial_velocity_to_game(7168), 0.5, "radial_to_game 7168 -> 0.5")
	_approx(PsxMagnitude.game_to_radial_velocity(1.0), 14336.0, "game_to_radial 1.0 -> 14336")


func _test_accel_and_homing() -> void:
	# accel / 4096 / 28 = accel / 114688 (parse_effect.py ACCEL_DIVISOR). Homing
	# shares the accel scale (convert_homing_strength).
	_approx(PsxMagnitude.accel_to_game(114688), 1.0, "accel_to_game 114688 -> 1.0")
	_approx(PsxMagnitude.accel_to_game(57344), 0.5, "accel_to_game 57344 -> 0.5")
	_approx(PsxMagnitude.game_to_accel(1.0), 114688.0, "game_to_accel 1.0 -> 114688")


func _test_round_trips() -> void:
	# game_to_raw(raw_to_game(x)) recovers x for representative raws.
	for raw in [0, 1, 100, -100, 4095, 16384]:
		_approx(PsxMagnitude.game_to_tile(PsxMagnitude.tile_to_game(raw)), float(raw), "tile round-trip %d" % raw)
		_approx(PsxMagnitude.game_to_radial_velocity(PsxMagnitude.radial_velocity_to_game(raw)), float(raw), "radial round-trip %d" % raw)
		_approx(PsxMagnitude.game_to_accel(PsxMagnitude.accel_to_game(raw)), float(raw), "accel round-trip %d" % raw)
	for raw in [0, 512, 1024, 2048, 4096]:
		_approx(PsxMagnitude.rad_to_angle(PsxMagnitude.angle_to_rad(raw)), float(raw), "angle round-trip %d" % raw)
