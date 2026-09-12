extends Node
## Tests for the Unit-side `scenario_rotate(target_12bit, …)` API that
## ScenarioVM's 0x2D Rotate Unit handler calls. The 12-bit angle convention
## (0=S, 0x400=E, 0x800=W, 0xC00=N) comes from PSX RAM at `unit+0x70` —
## see `research/working_documents/scenario_1_captures/event_unit_anim_decode.md`.
##
## v1 snaps the 12-bit angle to the nearest cardinal (4-way) FacingDirection
## the sprite system already uses. The per-frame interpolation curve
## (`0x8016d9d8 + handle*7` tick consumer) is still undecoded — Direction,
## Speed, and Delay are accepted but ignored for now.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/UnitScenarioRotateTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const FacingDirection = ExMateriaSchema.Facing.Direction
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_angle_12bit_to_facing_axis_values()
	_test_scenario_rotate_snaps_to_cardinal()
	_test_scenario_rotate_aligned_snaps_immediately()
	_test_reset_scenario_cutscene_state()

	print("\n=== UnitScenarioRotateTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] UnitScenarioRotateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] UnitScenarioRotateTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitScenarioRotateTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


# --- Cycle 9: 12-bit angle → FacingDirection cardinal snap -------------------

func _test_angle_12bit_to_facing_axis_values() -> void:
	# PSX truncate formula: `cardinal_idx = (angle >> 10) & 3`. Sectors are
	# byte-boundary aligned. Verified against the disassembly of
	# FUN_8006bbfc at 0x8006bc3c–0x8006bc40 (`srl v0,v0,0xa; andi v0,v0,0xff`).
	# See HANDOFF_sprite_cardinal_mapping.md Path A finding.
	#
	# Exact byte anchors: byte 0x0/0x4/0x8/0xC map to E/S/W/N on the CANONICAL
	# world wheel (0x000=E, 0x400=S — harmonized 2026-06-30, un-swapped from the
	# old E/S-swapped labeling).
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x000),
		FacingDirection.EAST, "0x000 → EAST")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x400),
		FacingDirection.SOUTH, "0x400 → SOUTH")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x800),
		FacingDirection.WEST, "0x800 → WEST")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0xC00),
		FacingDirection.NORTH, "0xC00 → NORTH")
	# Mid-sector bytes stay in their PSX truncate sector (lower byte anchor's
	# cardinal).
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x200),
		FacingDirection.EAST, "0x200 → EAST (truncate; [0x000, 0x400))")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x3FF),
		FacingDirection.EAST, "0x3FF → EAST (last byte of truncate 0)")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0x900),
		FacingDirection.WEST, "0x900 → WEST (pose_idx 2)")
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0xD00),
		FacingDirection.NORTH, "0xD00 → NORTH (pose_idx 3)")
	# Wrap: 0xFFF is in the [0xC00, 0x1000) NORTH sector.
	_assert_eq(AnimationStateController.angle_12bit_to_facing(0xFFF),
		FacingDirection.NORTH, "0xFFF → NORTH (pose_idx 3, NOT SOUTH)")


# --- Cycle 10: Unit.scenario_rotate steps anim_state to the target cardinal --

func _test_scenario_rotate_snaps_to_cardinal() -> void:
	# Construct Unit + AnimationStateController without going through Unit._ready
	# (which expects scene-instantiated children like UnitMesh). Manual wiring:
	# the @onready bind is just sugar for "before user _ready code"; an
	# explicit assignment before tree-attachment is equivalent for the
	# scenario_rotate path that only touches `anim_state.set_facing`.
	#
	# NOTE: since ce313bd7 (FFT-faithful rotate interpolation) scenario_rotate no
	# longer snaps `anim_state` immediately — it arms a `_rotate_state` stepper
	# that advances one 16-direction notch per `_tick_rotate()` (driven 60 Hz by
	# ScenarioVM._tick_unit_rotations). The cardinal only updates as the stepper
	# runs, so each rotation is ticked to completion before asserting. The
	# already-aligned case (target == current byte) still snaps in one call.
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	# Pre-set facing to North so the first rotation (→ South) isn't a no-op.
	asc.current_facing = FacingDirection.NORTH

	unit.scenario_rotate(0x400, 0, 0, 0)  # North → South (0x400 = SOUTH, canonical)
	_drain_rotate(unit)
	_assert_eq(asc.current_facing, FacingDirection.SOUTH,
		"scenario_rotate(0x400) → anim_state.current_facing = SOUTH (after stepping)")

	unit.scenario_rotate(0x000, 0, 0, 0)  # South → East (0x000 = EAST, canonical)
	_drain_rotate(unit)
	_assert_eq(asc.current_facing, FacingDirection.EAST,
		"scenario_rotate(0x000) → anim_state.current_facing = EAST (after stepping)")

	unit.scenario_rotate(0xC00, 0, 0, 0)  # East → North
	_drain_rotate(unit)
	_assert_eq(asc.current_facing, FacingDirection.NORTH,
		"scenario_rotate(0xC00) → anim_state.current_facing = NORTH (after stepping)")

	unit.free()
	asc.free()


# --- Cycle 11: already-aligned rotation snaps in one call (no stepper) -------

func _test_scenario_rotate_aligned_snaps_immediately() -> void:
	# When the target byte equals the current facing byte, scenario_rotate takes
	# the already-aligned fast path: it snaps `anim_state` and clears any
	# `_rotate_state` in a single call without arming the per-tick stepper.
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = FacingDirection.EAST  # internal 0x000, byte 0x0 (canonical)

	unit.scenario_rotate(0x000, 0, 0, 0)  # East → East (same byte 0x0)
	_assert_true(unit._rotate_state.is_empty(),
		"already-aligned scenario_rotate arms NO stepper")
	_assert_eq(asc.current_facing, FacingDirection.EAST,
		"already-aligned scenario_rotate keeps facing EAST")

	unit.free()
	asc.free()


# --- Cycle 12: reset_scenario_cutscene_state zeroes the 3 fields + cancels ---

func _test_reset_scenario_cutscene_state() -> void:
	# The Unit-owned half of ADR-0064's reset: ScenarioVM.reset_all calls this per
	# live unit on scene rewind so no stale facing / in-flight rotate / anim leaks
	# across a live-VM restart. Zeroes the three cutscene fields and cancels any
	# in-flight scenario_rotate stepper (mirrors the PSX FUN_8013f20c teardown).
	var unit := Unit.new()
	var asc := AnimationStateController.new()
	unit.anim_state = asc
	asc.current_facing = FacingDirection.NORTH

	# Dirty all three fields: arm an in-flight (multi-step) rotate so _rotate_state
	# is non-empty, seed a precise facing_angle, and set a live anim id.
	unit.scenario_rotate(0x400, 1, 0, 0)  # North → South, CW: arms the stepper
	unit.play_body(15)
	_assert_true(not unit._rotate_state.is_empty(), "precondition: rotate stepper armed")
	_assert_true(unit.facing_angle >= 0, "precondition: facing_angle seeded")

	unit.reset_scenario_cutscene_state()

	_assert_eq(unit.facing_angle, -1, "reset: facing_angle → -1 sentinel")
	_assert_true(unit._rotate_state.is_empty(), "reset: in-flight rotate cancelled")
	_assert_eq(unit.current_anim_id, 0, "reset: current_anim_id → 0")

	unit.free()
	asc.free()


# Tick an armed `scenario_rotate` stepper to completion (mirrors what
# ScenarioVM._tick_unit_rotations does each 60 Hz tick), with a safety cap so a
# stuck rotation can't hang the test.
func _drain_rotate(unit: Unit) -> void:
	var safety := 256
	while not unit._rotate_state.is_empty() and safety > 0:
		unit._tick_rotate()
		safety -= 1
