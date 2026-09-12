extends Node
# test-kind: logic
# seeded-break: initial_spawn_facing_12bit special-cases facing_raw 1 to the old bespoke table's rotated entry (0x800 WEST instead of 0x400 SOUTH) — the pre-ADR bespoke-table bug class the test exists to keep out; 'facing_raw 1 → SOUTH (0x400)' reds (got=2048 want=1024); the other three wheel cardinals + the chapel-cast raw-3-faces-NORTH case stay green
## Pins the ENTD `facing_raw` → 12-bit world-angle spawn conversion,
## `ScenarioPlayerScene.initial_spawn_facing_12bit` — the RE-faithful ROM spawn
## rule `angle = Facing << 10` (`0x80087c1c`) shared with the Warp Unit opcode
## via `PsxNum.warp_facing_to_12bit`: 0->EAST, 1->SOUTH, 2->WEST, 3->NORTH.
##
## **History:** the spawn path used to carry a bespoke table
## (`[0x400,0x800,0xC00,0x000]`) rotated one cardinal (+0x400) off this rule,
## plus a hardcoded North override for the chapel rotator cast (0x0C/0x13/0x34)
## to paper over the resulting 90° error. Both are gone. The chapel cast carries
## ENTD `facing_raw = 3`, which lands on NORTH (0xC00) faithfully here — matching
## the live-PSX `+0x70 = 0xC00` capture — so no override is needed; and scenario
## 4 ("Orbonne Battle") enemies (raw 0) now face WEST, Agrias (raw 2) EAST.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCastInitialFacingTest.tscn

const ScenarioPlayerScene = preload("res://src/scenarios/ScenarioPlayerScene.gd")

const EAST := 0x000
const SOUTH := 0x400
const WEST := 0x800
const NORTH := 0xC00

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_faithful_wheel()
	_test_chapel_cast_faces_north()

	print("\n=== ScenarioCastInitialFacingTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCastInitialFacingTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCastInitialFacingTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCastInitialFacingTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- Faithful `Facing << 10` wheel ------------------------------------------

func _test_faithful_wheel() -> void:
	_assert_eq(ScenarioPlayerScene.initial_spawn_facing_12bit(0), EAST,
		"facing_raw 0 → EAST (0x000)")
	_assert_eq(ScenarioPlayerScene.initial_spawn_facing_12bit(1), SOUTH,
		"facing_raw 1 → SOUTH (0x400)")
	_assert_eq(ScenarioPlayerScene.initial_spawn_facing_12bit(2), WEST,
		"facing_raw 2 → WEST (0x800)")
	_assert_eq(ScenarioPlayerScene.initial_spawn_facing_12bit(3), NORTH,
		"facing_raw 3 → NORTH (0xC00)")


# --- Chapel rotator cast faces North with NO override -----------------------

func _test_chapel_cast_faces_north() -> void:
	# Chapel rotators 0x0C/0x13/0x34 carry ENTD facing_raw = 3. The faithful rule
	# lands them on NORTH (0xC00), matching the live-PSX +0x70=0xC00 capture —
	# the old hardcoded override is no longer needed.
	_assert_eq(ScenarioPlayerScene.initial_spawn_facing_12bit(3), NORTH,
		"chapel cast ENTD raw 3 → NORTH faithfully (no override)")
