extends Node
# test-kind: logic
# seeded-break: Unit.reset_scenario_cutscene_state's `if not preserve_pose:` guard replaced by `if true:` (restores the documented pre-fix UNCONDITIONAL idle re-arm) — 'preserve_pose=true keeps combat current_anim_id' + 'pose preserved' RED (got=0 want=42, a KO'd unit's corpse slot stands up); the default/explicit-false reset arms and the reset_all/start VM plumbing arms stay green; GREEN unbroken on the reverted tree
## Combat -> scenario POSE CARRY at the victory-beat `start()` (the "dead units
## stand up before the scn6 fade" bug).
##
## After a navigator battle wins, control hands to the woven victory beat (scn6),
## which runs `ScenarioVM.start(false)` on the SAME live world units (decision
## #180). `start()` -> `reset_all` -> `Unit.reset_scenario_cutscene_state()`, whose
## last act was an unconditional `display.play_body(0)` — re-arming the IDLE clock
## on EVERY unit. That clobbered the combat-committed pose (`current_anim_id`): a
## KO'd unit's DEAD corpse slot and a critical survivor's kneel both got reset to
## idle, so they visibly "stood up" a moment before the {43} fade swept them.
##
## The fix: scenario mode has no dead/alive, only a unit and its `current_anim_id`.
## At the combat->scenario handoff we MIGRATE the combat pose across ONCE by
## PRESERVING `current_anim_id` (and the live clock frame — re-arming would replay
## the death fall) instead of forcing 0. This is a per-call opt-in
## (`preserve_pose` / `preserve_combat_poses`), so the ordinary rewind/replay path
## (`set_rewind_target`, and every non-victory `start()`) keeps its clean idle
## baseline. The `is_cinematic_unit`/`facing_angle` reset is UNCHANGED — a battle
## unit has no cutscene facing yet; scn6's own rotate/face opcodes flip it cinematic
## per-unit when they turn it.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCombatPoseCarryTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


## Fake registered unit that records the `preserve_pose` arg `reset_all` forwards,
## exposing just the surface `reset_all`/`start` touch (`has_method`, `tick_based`).
class SpyUnit extends RefCounted:
	# Mirror the real Unit (ADR-0083): owner is settable, tick_based is derived.
	var clock_owner: ClockOwner = ClockOwner.SELF
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var reset_calls: Array = []
	func reset_scenario_cutscene_state(preserve_pose: bool = false) -> void:
		reset_calls.append(preserve_pose)


func _ready() -> void:
	_test_unit_preserves_pose_when_asked()
	_test_unit_resets_pose_by_default()
	_test_unit_still_clears_facing_when_preserving()
	_test_reset_all_forwards_preserve_flag()
	_test_start_forwards_preserve_to_reset()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioCombatPoseCarryTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCombatPoseCarryTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCombatPoseCarryTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCombatPoseCarryTest")
		get_tree().quit(0)


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_eq(got, want, name: String) -> void:
	_assert_true(got == want, "%s (got=%s want=%s)" % [name, str(got), str(want)])


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)  # _ready -> handler registration + valid _current_ctx + box_pool
	_vms.append(vm)
	return vm


# --- Unit-level: the actual pose carry --------------------------------------

# A unit carrying a combat pose (non-idle `current_anim_id`, e.g. a DEAD corpse
# slot or a critical kneel) KEEPS it through `reset_scenario_cutscene_state(true)`.
func _test_unit_preserves_pose_when_asked() -> void:
	var unit := Unit.new()
	unit.play_body(42)  # stand in for a combat-committed pose (corpse / kneel / …)
	unit.reset_scenario_cutscene_state(true)
	_assert_eq(unit.current_anim_id, 42, "preserve_pose=true keeps combat current_anim_id")
	unit.free()


# The default (rewind/replay, every non-victory start) still snaps to idle 0.
func _test_unit_resets_pose_by_default() -> void:
	var unit := Unit.new()
	unit.play_body(42)
	unit.reset_scenario_cutscene_state()  # default preserve_pose=false
	_assert_eq(unit.current_anim_id, 0, "default reset snaps current_anim_id to idle 0")
	var unit2 := Unit.new()
	unit2.play_body(42)
	unit2.reset_scenario_cutscene_state(false)  # explicit false
	_assert_eq(unit2.current_anim_id, 0, "explicit preserve_pose=false snaps to idle 0")
	unit.free()
	unit2.free()


# Preserving the POSE must NOT preserve the cutscene facing: a battle unit has no
# precise cutscene facing yet, so facing_angle -> -1 and is_cinematic_unit -> false
# regardless (scn6's rotate/face opcodes re-arm those per unit).
func _test_unit_still_clears_facing_when_preserving() -> void:
	var unit := Unit.new()
	unit.play_body(42)
	unit.facing_angle = 0x300
	unit.is_cinematic_unit = true
	unit.reset_scenario_cutscene_state(true)
	_assert_eq(unit.current_anim_id, 42, "pose preserved")
	_assert_eq(unit.facing_angle, -1, "facing_angle still cleared to -1 sentinel")
	_assert_eq(unit.is_cinematic_unit, false, "is_cinematic_unit still cleared")
	unit.free()


# --- VM plumbing: start(preserve) -> reset_all(preserve) -> unit -------------

func _test_reset_all_forwards_preserve_flag() -> void:
	var vm := _make_vm()
	var spy := SpyUnit.new()
	vm.reset_all({7: spy}, true)
	_assert_eq(spy.reset_calls, [true], "reset_all(units, true) forwards preserve_pose=true")
	var spy2 := SpyUnit.new()
	vm.reset_all({7: spy2})  # default
	_assert_eq(spy2.reset_calls, [false], "reset_all default forwards preserve_pose=false")


func _test_start_forwards_preserve_to_reset() -> void:
	var vm := _make_vm()
	var spy := SpyUnit.new()
	vm.units_by_id[7] = spy
	vm.start(false, true)  # victory-beat handoff: fresh=false, preserve combat poses
	_assert_eq(spy.reset_calls, [true], "start(false, true) preserves combat poses via reset_all")

	var vm2 := _make_vm()
	var spy2 := SpyUnit.new()
	vm2.units_by_id[7] = spy2
	vm2.start(false)  # ordinary member advance / boot: no preserve
	_assert_eq(spy2.reset_calls, [false], "start(false) default does not preserve poses")
