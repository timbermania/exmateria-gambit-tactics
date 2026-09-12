extends Node
## Pins the Warp Unit (0x5F) facing decode + facing_angle seeding.
##
## **Why this test exists.** The female knight (chunk-unit 0x84) walks into the
## chapel and is NEVER rotated afterward (the event stream only makes OTHER
## units face her). Her on-screen facing is therefore whatever the Warp opcode
## left her at.
##
## **GROUND TRUTH (2026-06-29, writer PC captured — `female_knight_facing_
## GROUND_TRUTH.md`).** The female knight settles facing **NORTH**
## (`+0x70 = 0xC00`). The ROM spawn-init writer (`0x80087c1c`, `<<10`) sets the
## RAW PSX 12-bit world angle directly from the Warp Facing field:
##   field 0 -> 0x000 EAST   1 -> 0x400 SOUTH   2 -> 0x800 WEST   3 -> 0xc00 NORTH
## Her Facing field = 3 -> 0xC00 = NORTH. The prior `Facing=3 -> 0x000 (SOUTH)`
## decode was a wrong-beat/wrong-node mis-capture and is DISPROVEN.
##
## `_op_warp_unit` therefore seeds `facing_angle` with the RAW PSX angle via
## `Unit.scenario_set_facing`. The render consumes it directly: the idle
## pose-octant composes the camera yaw (`get_pose_octant`, the PSX
## `FUN_80085c0c` formula) and the yellow facing arrow
## (`Unit.facing_angle_to_world_radians`) maps the raw angle to the world
## cardinal — anchored at byte 0xC = NORTH = 0 rad.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWarpFacingTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const FacingDirection = ExMateriaSchema.Facing.Direction
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_warp_decode_is_raw_psx_shift()
	_test_warp_facing3_is_north()
	_test_arrow_anchors_raw_psx_wheel()
	_test_scenario_set_facing_seeds_angle()

	print("\n=== ScenarioWarpFacingTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWarpFacingTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWarpFacingTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWarpFacingTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_approx(got: float, want: float, name: String) -> void:
	if is_equal_approx(got, want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


# --- Warp facing decode ------------------------------------------------------

## Mirror of the decode in `ScenarioVM._op_warp_unit` (kept in lockstep): the
## RAW PSX 12-bit world angle is `(Facing << 10) & 0xFFF`.
func _warp_decode_12bit(fft_facing: int) -> int:
	return (fft_facing << 10) & 0xFFF


func _test_warp_decode_is_raw_psx_shift() -> void:
	# ROM-writer field convention -> RAW PSX world angle (0x000=E .. 0xC00=N).
	_assert_eq(_warp_decode_12bit(0), 0x000, "Warp Facing=0 -> 0x000 (EAST)")
	_assert_eq(_warp_decode_12bit(1), 0x400, "Warp Facing=1 -> 0x400 (SOUTH)")
	_assert_eq(_warp_decode_12bit(2), 0x800, "Warp Facing=2 -> 0x800 (WEST)")
	_assert_eq(_warp_decode_12bit(3), 0xC00, "Warp Facing=3 -> 0xC00 (NORTH)")


func _test_warp_facing3_is_north() -> void:
	# THE female-knight fix: Warp Facing=3 must land on NORTH (0xC00), not the
	# old wrong 0x000.
	_assert_eq(_warp_decode_12bit(3), 0xC00, "Warp Facing=3 -> 12-bit 0xC00 (NORTH)")


func _test_arrow_anchors_raw_psx_wheel() -> void:
	# The yellow facing arrow is the authoritative on-screen render direction.
	# `facing_angle_to_world_radians` maps the raw PSX wheel onto Godot world
	# cardinals (+X=NORTH at 0 rad, rotating toward +Z=EAST). A vector (1,0,0)
	# rotated by rotation.y=theta becomes (cos, 0, -sin):
	#   0xC00 NORTH -> 0       rad -> +X
	#   0x400 SOUTH -> PI      rad -> -X
	#   0x800 WEST  -> PI/2    rad -> -Z
	#   0x000 EAST  -> 3*PI/2  rad -> +Z
	_assert_approx(Unit.facing_angle_to_world_radians(0xC00), 0.0,
		"arrow(0xC00) = 0 rad (NORTH / +X)")
	_assert_approx(Unit.facing_angle_to_world_radians(0x400), PI,
		"arrow(0x400) = PI rad (SOUTH / -X)")
	_assert_approx(Unit.facing_angle_to_world_radians(0x800), PI / 2.0,
		"arrow(0x800) = PI/2 rad (WEST / -Z)")
	_assert_approx(Unit.facing_angle_to_world_radians(0x000), 3.0 * PI / 2.0,
		"arrow(0x000) = 3PI/2 rad (EAST / +Z)")


func _test_scenario_set_facing_seeds_angle() -> void:
	# The Unit-side contract _op_warp_unit relies on: scenario_set_facing writes
	# the precise raw facing_angle (>= 0, so the arrow/octant stop using the -1
	# cardinal fallback).
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc

	unit.scenario_set_facing(0xC00)  # NORTH (the female-knight warp result)
	_assert_eq(int(unit.facing_angle), 0xC00,
		"scenario_set_facing(0xC00) seeds facing_angle=0xC00 (not -1 fallback)")
	_assert_eq(int(unit.facing_direction), int(FacingDirection.NORTH),
		"scenario_set_facing(0xC00) snaps cardinal to NORTH")

	unit.free()
	asc.free()
