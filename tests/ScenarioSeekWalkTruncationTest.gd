extends Node
# test-kind: logic
# seeded-break: ScenarioVM._advance_motions' is_done arm loses `m.snap_to_end()` + the end-position write (restored pre-fix pump that dropped a clamped motion wherever the clock ran out); 'a clamped walk is left on its endpoint, not where the clamp fell' RED (got=(1.43,0,0.5) mid-route, want=(3.5,0,0.5) — the unit is abandoned ~1/3 into the trajectory while its seat latches the END); the seek-arms-whole-route, seeked-walk-lands, and walk-anim-to-idle arms stay green; GREEN unbroken on the reverted tree
## Regression detector for "seek to a PC and the units are in the wrong places" —
## reported against scenario 29, where the seeked cast never hops the Igros moat.
##
## The seek (`ScenarioVM._begin_fast_play`) forces `play_through_skip_unknown` on
## for the whole fast-play, and that flag makes `_play_through_max_dur_s()` return
## `play_through_max_ticks / 60` = **1.0 s**. Measured live on scenario 29 at PC
## 148 (`--scenario=29 --rewind-pc=148`), the three `{28}` walks dispatched on the
## way in are 169, 215 and 215 ROM frames long and every one of them was armed at
## **60**. A unit walked a quarter of its route and was left standing in the river.
##
## Two independent defects produced that, and this file scores them separately:
##
##   A. **the walk was clamped at all.** A `{28}`'s duration is EMERGENT — the
##      stepper runs the whole route at arm time and the frame count is what came
##      out — and it is bounded by construction (127 route bytes; the longest
##      shipped corpus route is 12 tiles). The cap exists so an orientation race
##      can't stall a seek on an 8-minute camera slide; a walk cannot be 8 minutes,
##      so it must not be capped. Arms 1 and 2.
##   B. **a clamped motion was abandoned wherever the clamp fell.** The motion pump
##      reacts to `is_done()` by dropping the motion and ending the walk anim, and
##      never puts the unit on the trajectory's END — so the transform disagrees
##      with the seat `ScenarioApply.walk_to` latched at ARM time (ADR-0219 dec. 6),
##      and `_unit_cell` then discards the latched level. Arm 3, which arms a clamp
##      DIRECTLY so it stays a test of the pump after A is fixed.
##
## ⚠️ Arm 2 exists because arm 1 reads a number the pipeline had not yet consumed.
## A frame count can be right while the walk still lands somewhere else; arm 2 pumps
## the motion the way `_advance_frame` does and asks where the unit actually ended.
##
## Run: "$GODOT" --path . --quit-after 8 res://tests/ScenarioSeekWalkTruncationTest.tscn

# ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
# kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line
# per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainFixture = ExMateriaBattlefield.TerrainFixture

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

## ADR-0218 dec. 4 refuses an unbounded fixture: the map edge an infinite plane
## hides is one the real consumer meets. 20x20 contains every walk below.
const MAP_BOUNDS := Rect2i(0, 0, 20, 20)

## The walking unit's chunk id, and the walk this file drives: (8,4) -> (4,4), four
## tiles of flat ground at Speed 4. That is ~57 ROM frames a tile — comfortably over
## the 60-frame play-through cap, which is the whole point of the fixture.
const UID := 0x000C
const START_CELL := Vector2i(8, 4)
const TARGET_CELL := Vector2i(4, 4)
const SPEED := 4

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
	_test_a_seek_arms_the_whole_route_not_the_first_second()
	_test_a_seeked_walk_lands_on_the_tile_it_was_sent_to()
	_test_a_clamped_motion_still_ends_at_its_endpoint()

	print("\n=== ScenarioSeekWalkTruncationTest: %d passed, %d failed, %d/%d arms reported ==="
		% [_passed, _failed, _completed.size(), ARM_COUNT])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioSeekWalkTruncationTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != ARM_COUNT:
		print("[FAIL] ScenarioSeekWalkTruncationTest: only %d of %d arms ran to completion — ran %s"
			% [_completed.size(), ARM_COUNT, str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioSeekWalkTruncationTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioSeekWalkTruncationTest")
		get_tree().quit(0)


# --- arms --------------------------------------------------------------------

## A. The seek forces `play_through_skip_unknown` on. Under it, the SAME `{28}` must
## arm the SAME number of ROM frames it arms during a normal play — a walk is not a
## clampable motion.
func _test_a_seek_arms_the_whole_route_not_the_first_second() -> void:
	var normal := _dispatch_walk(false)
	var seeking := _dispatch_walk(true)
	# The fixture asserts its OWN speed: an operand list one entry short reads `Speed`
	# as absent and the handler quietly walks at its default 8, halving the route.
	_eq(normal.stepper.mag, (SPEED * 256) << 1, "fixture: the walk runs at Speed %d" % SPEED)
	_true(normal.total_frames > 60.0,
		"fixture: the control walk is longer than the 60-frame cap (got %.0f)" % normal.total_frames)
	_eq(int(seeking.total_frames), int(normal.total_frames),
		"a walk dispatched under play-through arms its whole route")
	_approx(seeking.dur_s, normal.dur_s, "and reports the same duration")
	_completed["seek_arms_whole_route"] = true


## And the frame count being right is not the same as the walk ENDING right — pump
## the motion the way `ScenarioVM._advance_frame` does and ask the transform.
func _test_a_seeked_walk_lands_on_the_tile_it_was_sent_to() -> void:
	var vm := _make_vm()
	vm.play_through_skip_unknown = true
	var unit: FakeUnit = vm.units_by_id[UID]
	vm._op_walk_to(_walk_inst(UID, TARGET_CELL.x, TARGET_CELL.y, SPEED))
	_pump(vm, 1200)
	# The oracle is the destination the OPCODE named, computed here rather than read
	# back off the plan — a value the pipeline produced cannot say the pipeline
	# delivered it (a mirrored coordinate map prints a correct endpoint and walks the
	# other way).
	var want := Vector3(TARGET_CELL.x + 0.5, MapConstants.surface_y(0), TARGET_CELL.y + 0.5)
	_veq(unit.global_position, want, "a seeked walk ends on its target tile", 0.02)
	_eq(vm.active_motion_count(), 0, "and the motion is retired")
	vm.queue_free()
	_completed["seeked_walk_lands"] = true


## B. Whatever clamps a motion — a play-through cap, a future one — the pump must
## leave the unit at the trajectory's END, not wherever the clock was cut. The seat
## is latched on ARM (ADR-0219 dec. 6), so a unit abandoned mid-route is a unit whose
## transform and logical cell disagree. Clamped DIRECTLY here so this stays an
## assertion about the pump once the `{28}` caller stops clamping.
func _test_a_clamped_motion_still_ends_at_its_endpoint() -> void:
	var vm := _make_vm()
	var unit: FakeUnit = vm.units_by_id[UID]
	var pts: Array = []
	for i in 4:
		pts.append(Vector3(0.5 + float(i), 0.0, 0.5))
	var m := ScenarioPathMotion.new()
	m.configure(pts, 16.0, 60.0, 0.25)  # 15 frames of a ~46-frame walk
	_true(m.total_frames < 46.0, "fixture: the clamp actually shortened the walk")
	unit.global_position = pts[0]
	unit.current_anim_id = ScenarioVMClass.FFT_WALK_ANIM_ID
	vm.actor(UID).motion = m
	_pump(vm, 120)
	_veq(unit.global_position, pts[pts.size() - 1],
		"a clamped walk is left on its endpoint, not where the clamp fell", 1e-3)
	_eq(unit.current_anim_id, 0, "and the walk anim is returned to idle")
	vm.queue_free()
	_completed["clamped_motion_ends_at_endpoint"] = true


# --- helpers -----------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	var fixture := TerrainFixture.flat(MAP_BOUNDS)
	add_child(fixture)
	vm.map_composer = fixture
	var unit := FakeUnit.new()
	unit.global_position = Vector3(START_CELL.x + 0.5, MapConstants.surface_y(0),
		START_CELL.y + 0.5)
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


## Dispatch the fixture walk with play-through in the given state and hand back the
## motion it armed.
func _dispatch_walk(play_through: bool) -> ScenarioPathMotion:
	var vm := _make_vm()
	vm.play_through_skip_unknown = play_through
	vm._op_walk_to(_walk_inst(UID, TARGET_CELL.x, TARGET_CELL.y, SPEED))
	var m: ScenarioPathMotion = vm.actor(UID).motion
	vm.queue_free()
	return m


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


func _approx(got: float, want: float, name: String, eps: float = 1e-4) -> void:
	if absf(got - want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


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
