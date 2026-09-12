extends Node
## End-to-end test that drives ScenarioVM through the REAL Orbonne Prayer
## chunk (`assets/scenarios/scenario_1_chunk.json` — confusingly named, this
## is actually scenario 2's cinematic; 26 Display Messages, sourced from
## `cinematic_event_chunk_0x8004A6BC.bin`). The test:
##
##   * Spawns light FakeUnits for the chapel cast (0x000C, 0x0013, 0x0034)
##     with initial cardinal = NORTH, matching the PSX live RAM state seen
##     in `event_unit_anim_decode.md` 2026-06-24 "later 2" capture
##     (`+0x70 = 0xC00` for both 0x0013 and 0x0034 before the first rotate).
##   * Enables play-through to skip Display Message halts.
##   * Drives `_tick_once` to completion (with a safety cap).
##   * Records every `scenario_rotate` call per unit, then asserts the full
##     trajectory of cardinal snaps matches the chunk's hand-decoded order.
##
## If this test fails, ScenarioVM's dispatch / decode / Facing-mode resolver
## has regressed. If it passes but the visible game still looks wrong, the
## bug is in production INITIAL facing (ENTD spawn defaults != cinematic
## starting facing) — see `ScenarioCastInitialFacingTest.gd` for that.
##
## Run: "$GODOT" --path . --quit-after 15 res://tests/ScenarioChapelChoreographyTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const FacingDirection = ExMateriaSchema.Facing.Direction
const CHUNK_JSON_PATH := "res://assets/scenarios/scenario_1_chunk.json"

var _passed: int = 0
var _failed: int = 0


# Minimal Unit stand-in: scenario_rotate records the call and snaps the
# tracked cardinal via the same static helper a real Unit uses. Unit Anim
# opcodes are also serviced so the VM doesn't trip on the cinematic 0x200+
# range it can't render today.
class FakeAnimSet extends RefCounted:
	var type1_seq: Dictionary = {}
	func _init() -> void:
		# Include both low-range and high-range keys so _op_unit_anim never
		# falls back to idle for this test's purposes (we don't care about
		# anim content, just that the dispatcher reaches every Rotate Unit
		# without halting).
		for k in ["2", "3"]:
			type1_seq[k] = {}

class FakePlayback extends RefCounted:
	var anim_id: String = ""
	func start(new_anim_id: String, _seqs: Dictionary, _start: int = 0) -> void:
		anim_id = new_anim_id

# The render module owns the BODY playback (issue #144); ScenarioVM's Unit-Anim
# readiness guard reads `unit.display.type1_playback`, so the fake models it.
class FakeDisplay extends RefCounted:
	var type1_playback: FakePlayback
	func _init(pb: FakePlayback) -> void:
		type1_playback = pb

class FakeUnit extends RefCounted:
	var animation_set: FakeAnimSet
	var display: FakeDisplay
	var type1_playback: FakePlayback
	var cardinal: int = FacingDirection.NORTH
	var rotate_log: Array = []  # [{target_12bit, cardinal_after}]
	# Service the Unit Anim path so the VM doesn't error (this test only asserts
	# the rotate trajectory): _op_unit_anim writes current_anim_id directly for
	# both ranges (raw for EVTCHR >= 0x258, event_anim_id+1 for the low range).
	var current_anim_id: int = 0
	# Stubs for VM paths that touch these unconditionally (rotate handler reads
	# `unit.anim_state`/`facing_angle`; show/hide writes `visible`). Null/`-1`
	# keeps absolute-mode rotates on the baseline path so scenario_rotate is
	# still reached and logged. Added when these VM features (acf871c6,
	# 6d2e7f48) outgrew the original fixture.
	var anim_state = null
	var facing_angle: int = -1
	var visible: bool = false
	func _init() -> void:
		animation_set = FakeAnimSet.new()
		type1_playback = FakePlayback.new()
		display = FakeDisplay.new(type1_playback)
	# The VM funnels body anims through the facade `play_body` (issue #144, C3b);
	# the double mirrors it onto `current_anim_id` the way real Unit does.
	func play_body(anim_id: int) -> void:
		current_anim_id = anim_id
	func scenario_rotate(target_12bit: int, _direction: int, _speed: int,
			_delay: int) -> void:
		cardinal = AnimationStateController.angle_12bit_to_facing(target_12bit)
		rotate_log.append({
			"target_12bit": target_12bit,
			"cardinal_after": cardinal,
		})


func _ready() -> void:
	_test_chapel_rotate_trajectory()

	print("\n=== ScenarioChapelChoreographyTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioChapelChoreographyTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioChapelChoreographyTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioChapelChoreographyTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- Choreography drive + assertions -----------------------------------------

func _test_chapel_rotate_trajectory() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_assert_eq(vm.load_chunk_json(CHUNK_JSON_PATH), true, "chunk JSON loads")

	# Chapel cast with PSX initial state (NORTH for all three per the live
	# capture in event_unit_anim_decode.md).
	var units := {
		0x000C: FakeUnit.new(),  # Gafgarion / narrator
		0x0013: FakeUnit.new(),  # Priest / Agrias (one of the rotators)
		0x0034: FakeUnit.new(),  # Agrias / Priest (other rotator)
	}
	vm.units_by_id = units
	vm.play_through_skip_unknown = true  # skip dialogues + unhandled
	vm.start()

	# Drive the VM to completion. Cap is generous: every Wait is clamped to
	# play_through_max_ticks=60, chunk has ~600 Waits — so 50k iterations
	# is well above the worst case (~36k) and well under "takes seconds".
	var steps := 0
	while vm.is_running() and steps < 200000:
		vm._tick_once()
		steps += 1
	print("  drove VM for %d ticks (running=%s, pc=%d/%d)" %
		[steps, str(vm.is_running()), vm.get_pc(), vm.get_instructions().size()])

	# Assert the full rotate sequence for each chapel-cast unit. Cardinals
	# derived from the chunk's Rotate Unit ops + the Facing-mode dispatch:
	#   absolute mode (Facing < 0x10) → target = Facing × 0x100
	#   AnimationStateController.angle_12bit_to_facing snaps to the cardinal on
	#   the CANONICAL world wheel (0x000=E, 0x400=S, 0x800=W, 0xC00=N).
	# Initial cardinal = NORTH for all (PSX state).
	#
	# Order matters: the chunk fires rotates in chunk-offset order.

	# Unit 0x0034 — three rotates in the chapel-cast window:
	#   off 0x021D Facing=0x04 → 0x400 → SOUTH
	#   off 0x0446 Facing=0x09 → 0x900 → WEST
	#   off 0x05F8 Facing=0x04 → 0x400 → SOUTH
	_assert_unit_trajectory(units[0x0034], "0x0034", [
		[0x400, FacingDirection.SOUTH],
		[0x900, FacingDirection.WEST],
		[0x400, FacingDirection.SOUTH],
	])

	# Unit 0x0013 — four rotates:
	#   off 0x0227 Facing=0x02 → 0x200 → EAST (PSX truncate: [0x000, 0x400))
	#   off 0x0456 Facing=0x0D → 0xD00 → NORTH (PSX truncate: [0xC00, 0x1000))
	#   off 0x047C Facing=0x00 → 0x000 → EAST
	#   off 0x05BA Facing=0x04 → 0x400 → SOUTH
	_assert_unit_trajectory(units[0x0013], "0x0013", [
		[0x200, FacingDirection.EAST],
		[0xD00, FacingDirection.NORTH],
		[0x000, FacingDirection.EAST],
		[0x400, FacingDirection.SOUTH],
	])

	# Unit 0x000C — two rotates:
	#   off 0x0466 Facing=0x04 → 0x400 → SOUTH
	#   off 0x048F Facing=0x08 → 0x800 → WEST
	_assert_unit_trajectory(units[0x000C], "0x000C", [
		[0x400, FacingDirection.SOUTH],
		[0x800, FacingDirection.WEST],
	])

	vm.queue_free()


func _assert_unit_trajectory(unit: FakeUnit, label: String,
		expected: Array) -> void:
	_assert_eq(unit.rotate_log.size(), expected.size(),
		"%s rotate count" % label)
	var n := mini(unit.rotate_log.size(), expected.size())
	for i in range(n):
		var got: Dictionary = unit.rotate_log[i]
		_assert_eq(int(got["target_12bit"]), int(expected[i][0]),
			"%s rotate[%d] target_12bit" % [label, i])
		_assert_eq(int(got["cardinal_after"]), int(expected[i][1]),
			"%s rotate[%d] cardinal" % [label, i])
