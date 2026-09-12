extends Node
# test-kind: logic
# seeded-break: ScenarioApply.walk_to's `if route_steps > 0:` degenerate-case gate becomes `route_steps >= 0` (always true) — the zero-step route re-faces to the zero-vector NORTH, arms the walk anim, supersedes the pending {11} latch, and drops the Sprite-Move home exactly like the pre-fix scn 29 pc 388 defect; the one-tile control arm stays green; GREEN unbroken on the reverted tree
## Regression detector for the ZERO-LENGTH `{28} Walk To` — reported against
## scenario 29 PC 388 (root 28 "Family Meeting", MAP009), where Delita turns 90°,
## plays the walk animation without moving, and then keeps that wrong facing while
## the `{3B}` Sprite Moves slide him into the hug, so he embraces Teta side-on.
##
## The chunk really does ask for it:
##
##     352  {28} Walk To  u=0x04 -> (2,10,L0) Speed 6   a real 1-tile walk
##     388  {28} Walk To  u=0x04 -> (2,10,L0) Speed 4   THE SAME TILE. zero steps.
##     389  {79} Walk To Anim / 390 {29} Wait Walk / 391+ {3B} the hug slide
##
## and nothing re-faces 0x04 between PC 217's `Rotate Unit` and PC 446.
##
## **On hardware a zero-step route latches nothing.** `EventPathfinder` returns
## `reached_target` with a bare `[0]` route buffer (`_route_bytes`), and
## `RomWalkStepper.step()` reads `n = route[0] == 0` and returns before `_arm_walk`
## — no facing is written and no walk anim is armed; the unit stands as it was.
## `ScenarioApply.walk_to`'s pre-face is a Godot-side addition (it exists for a real
## reason — the scenario-6 chocobo faced a frame late) and it had no degenerate case:
## `PsxNum.heading_to_12bit(0, 0)` resolves to NORTH unconditionally, and Delita had
## arrived facing WEST off PC 352, so `0xC00 - 0x800` is exactly the 90° reported.
##
## Corpus scope for the static shape (a `{28}` whose target equals the same unit's
## previous `{28}`/`{24}` placement): scn 29 pc 388 and scn 129 pc 99. Two of 285
## chunks — a narrow conformance fix, not a behaviour change.
##
## Arm 2 is the control. Arm 1 asserts that three things DON'T happen, and three
## things that never happen in a fixture that faces nothing would score it green.
##
## Run: "$GODOT" --path . --quit-after 8 res://tests/ScenarioZeroLengthWalkTest.tscn

# ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
# kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface.
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainFixture = ExMateriaBattlefield.TerrainFixture

# ADR-0212 dec. 1 — `exmateria_platform` declares only `ExMateriaPlatform`; aliasing
# `PsxNum` back keeps this file spelled the way `ScenarioApply` spells it.
const PsxNum = ExMateriaPlatform.PsxNum

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

## ADR-0218 dec. 4 refuses an unbounded fixture: the map edge an infinite plane
## hides is one the real consumer meets.
const MAP_BOUNDS := Rect2i(0, 0, 20, 20)

const UID := 0x000C
const START_CELL := Vector2i(8, 4)
## One tile WEST in the Godot grid (−Z), so the control walk's heading is the same
## WEST the repro's PC 352 left Delita on — the arm cannot pass by re-facing him to
## the value he already held.
const WEST_CELL := Vector2i(8, 3)
const SPEED := 4

## What PC 352 left Delita on, and what PC 388 must not disturb.
const WEST := PsxNum.WEST_12BIT
## And what `heading_to_12bit(0, 0)` returns for the degenerate route — the
## fixture's own statement of the value under test, so this file fails if the
## converter's zero-vector answer ever changes underneath it.
const NORTH := PsxNum.NORTH_12BIT

## A pending `{11}` Unit Anim id, parked to prove the zero-length walk does not
## supersede it: `set_walking` drops the latch because the walk is the newer
## authoritative body anim, and a walk that arms no body anim supersedes nothing.
const PENDING_ANIM := 7

var _passed: int = 0
var _failed: int = 0
## Arms that ran to COMPLETION, by name. A GDScript runtime error aborts only its
## ENCLOSING function and contributes NO failures, so without this register a file
## that died in arm 1 still prints `N passed, 0 failed` and scores [PASS].
var _completed: Dictionary = {}
const ARM_COUNT := 3


# --- fixtures ----------------------------------------------------------------

class FakeUnit extends RefCounted:
	var global_position: Vector3 = Vector3.ZERO
	# Takes the production facing verb rather than a writable `facing_direction`
	# ScenarioWorld can fall back onto (#752); `facing_angle` is the source of truth.
	var facing_angle: int = -1
	var facing_direction: FacingDirection:
		get:
			if facing_angle < 0:
				return FacingDirection.NORTH
			return ExMateriaSpriteRig.AnimationStateController.angle_12bit_to_facing(facing_angle)
	var current_anim_id: int = 0
	# null anim_state: `_op_walk_to` does not touch it and `_end_walk_anim` guards.
	var anim_state = null

	func scenario_set_facing(target_12bit: int) -> void:
		facing_angle = target_12bit

	func play_body(anim_id: int) -> void:
		current_anim_id = anim_id


func _ready() -> void:
	_test_a_zero_length_walk_neither_refaces_nor_walks()
	_test_a_real_walk_still_faces_and_walks()
	_test_a_zero_length_walk_does_not_rebase_the_sprite_move_home()

	print("\n=== ScenarioZeroLengthWalkTest: %d passed, %d failed, %d/%d arms reported ==="
		% [_passed, _failed, _completed.size(), ARM_COUNT])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioZeroLengthWalkTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != ARM_COUNT:
		print("[FAIL] ScenarioZeroLengthWalkTest: only %d of %d arms ran to completion — ran %s"
			% [_completed.size(), ARM_COUNT, str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioZeroLengthWalkTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioZeroLengthWalkTest")
		get_tree().quit(0)


# --- arms --------------------------------------------------------------------

## THE DEFECT. A `{28}` sent to the tile the unit is already standing on must leave
## the unit exactly as hardware leaves it: same facing, no walk anim, and the pending
## `{11}` latch still pending.
func _test_a_zero_length_walk_neither_refaces_nor_walks() -> void:
	var vm := _make_vm()
	var unit: FakeUnit = vm.units_by_id[UID]
	unit.scenario_set_facing(WEST)
	vm.actor(UID).pending_anim = PENDING_ANIM

	# The premise, asserted rather than assumed: the ROM's planner really does hand
	# back a zero-STEP route for a same-tile request (a bare `[0]` count byte), and
	# not a refusal — a refusal would make arm 1 green for the wrong reason, because
	# `walk_to` returns early on an empty plan and touches nothing either way.
	var plan := vm._plan_walk_route(UID, START_CELL.x, START_CELL.y)
	_true(not plan.is_empty(), "fixture: a same-tile {28} is planned, not refused")
	_eq(int((plan["route"] as Array)[0]), 0,
		"fixture: and the route it plans carries zero steps")
	_eq(int((plan["waypoints"] as Array).size()), 1, "fixture: so there is one waypoint")

	vm._op_walk_to(_walk_inst(UID, START_CELL.x, START_CELL.y, SPEED))

	# Read at DISPATCH, before the pump. `_advance_motions` ends the walk anim when
	# the motion retires, and this motion is one frame long — asserting the anim after
	# the pump scores the teardown and would be green through the defect.
	_eq(unit.facing_angle, WEST,
		"a zero-length {28} leaves the unit's facing alone (0x%03X is the zero-vector NORTH)" % NORTH)
	_eq(unit.current_anim_id, 0, "and arms no walk anim")
	_eq(vm.actor(UID).pending_anim, PENDING_ANIM,
		"and does not supersede the pending {11} latch")

	_pump(vm, 240)
	_veq(unit.global_position, _cell_center(START_CELL),
		"and does not move the unit", 1e-3)
	vm.queue_free()
	_completed["zero_length_walk_is_inert"] = true


## The control. Arm 1 scores three absences; this proves the same fixture, one tile
## further, produces all three presences — otherwise arm 1 passes on a rig that
## never faces or animates anything at all.
func _test_a_real_walk_still_faces_and_walks() -> void:
	var vm := _make_vm()
	var unit: FakeUnit = vm.units_by_id[UID]
	unit.scenario_set_facing(NORTH)
	vm.actor(UID).pending_anim = PENDING_ANIM

	vm._op_walk_to(_walk_inst(UID, WEST_CELL.x, WEST_CELL.y, SPEED))

	_eq(unit.facing_angle, WEST, "a one-tile {28} still faces its travel heading")
	_eq(unit.current_anim_id, ScenarioVMClass.FFT_WALK_ANIM_ID, "and still arms the walk anim")
	_eq(vm.actor(UID).pending_anim, -1, "and still supersedes the pending {11} latch")
	_eq(vm.actor(UID).has_home, false, "and still re-bases the Sprite-Move home")

	_pump(vm, 600)
	_veq(unit.global_position, _cell_center(WEST_CELL), "and lands on the tile it was sent to", 0.02)
	vm.queue_free()
	_completed["real_walk_still_faces_and_walks"] = true


## `clear_home` exists for a base RE-PLACEMENT ("Warp Unit, Walk To arrival"). A walk
## that advanced no tile re-placed no base, so the home must survive it — a Sprite
## Move's endpoint is absolute-from-home, and re-capturing home off a unit the
## previous Sprite Move had already offset turns the next one into a relative slide
## that accumulates. Directly exercised by the repro: PC 391/392 are Sprite Moves on
## 0x04, issued immediately after the zero-length walk at PC 388.
func _test_a_zero_length_walk_does_not_rebase_the_sprite_move_home() -> void:
	var vm := _make_vm()
	var unit: FakeUnit = vm.units_by_id[UID]
	var base := _cell_center(START_CELL)
	_veq(vm._world.capture_unit_home(UID), base, "fixture: home captures at the base", 1e-4)
	# What a Sprite Move already in progress leaves behind: the unit off its home by
	# the `+0x60` offset, still inside the same tile, so the following `{28}` to that
	# tile is still the zero-step route under test.
	unit.global_position = base + Vector3(0.25, 0.0, -0.25)

	vm._op_walk_to(_walk_inst(UID, START_CELL.x, START_CELL.y, SPEED))
	_pump(vm, 240)

	_true(vm.actor(UID).has_home, "a zero-length {28} does not drop the captured home")
	_veq(vm._world.capture_unit_home(UID), base,
		"so the next Sprite Move still resolves against the base, not the offset position", 1e-4)
	vm.queue_free()
	_completed["zero_length_walk_keeps_home"] = true


# --- helpers -----------------------------------------------------------------

func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, MapConstants.surface_y(0), cell.y + 0.5)


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	var fixture := TerrainFixture.flat(MAP_BOUNDS)
	add_child(fixture)
	vm.map_composer = fixture
	var unit := FakeUnit.new()
	unit.global_position = _cell_center(START_CELL)
	vm.units_by_id = {UID: unit}
	return vm


## A `{28}` with ALL SEVEN catalog operands. `EventInstructionArgs` names operands by
## CATALOG POSITION, not by the name the caller wrote, so a short list silently shifts
## every name left — a five-operand fixture has no `Speed` at all and the handler
## falls back to its default 8. The two `Unknown`s are load-bearing: the one BEFORE
## `Speed` is its 1/256 fraction (they are one `lhu`), and the one after is the
## movement-cost switch, where 0 flattens every terrain cost to 1.
func _walk_inst(unit_id: int, x: int, y: int, speed: int) -> Dictionary:
	return {
		"name": "Walk To", "opcode": 0x28,
		"params": [
			{"name": "Unit", "value": unit_id},
			{"name": "X", "value": x},
			{"name": "Y", "value": y},
			{"name": "Z", "value": 0},
			{"name": "Unknown", "value": 0},
			{"name": "Speed", "value": speed},
			{"name": "Unknown", "value": 1},
		],
	}


## Drive the VM's motion pump one ROM frame at a time until every motion retires, or
## `limit` frames pass. This is `_advance_frame`'s inner step, minus dispatch.
func _pump(vm: ScenarioVMClass, limit: int) -> void:
	for _i in limit:
		if vm.active_motion_count() == 0:
			return
		vm._advance_motions(1.0 / 60.0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _veq(got: Vector3, want: Vector3, name: String, eps: float = 1e-4) -> void:
	if got.distance_to(want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s (d=%.4f)" % [name, str(got), str(want),
			got.distance_to(want)])
