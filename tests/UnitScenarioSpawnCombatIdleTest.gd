extends Node
## Change #1 guard — a scenario/battle unit spawns into COMBAT IDLE (march-in-place),
## not the cinematic "at-ease" tent. Mirrors the ROM spawn default: every battle sprite
## is built through the status-anim selector FUN_80082eec @ 0x80082EEC, so a healthy unit
## is march-idling the instant it's placed — NOT deployment-inherited, NOT a scenario
## opcode. See research/working_documents/MARCH_OPCODE_80_SEMANTICS.md §2.1 / §4.1 (pc_0
## shows all 11 units cycling combat-idle before any opcode touches them).
##
## The port bug (living doc §5, "inverted model"): scenario spawn seeded every unit via
## `scenario_set_facing`, which sets `is_cinematic_unit = true` → the static tent. Only the
## belated {80} March flipped them back. This pins the FAITHFUL spawn default through the
## NEW public verb `scenario_spawn_facing` (precise facing WITHOUT the cinematic freeze),
## the combat-idle counterpart to the freezing `scenario_set_facing` ({8C}/Warp opcode).
##
## Contrast is the whole point, so this also re-checks the freezing verb still tents —
## `scenario_set_facing` must be untouched (UnitCinematicIdleModeTest depends on it).
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/UnitScenarioSpawnCombatIdleTest.tscn

const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const BODY_SPRITE := 0x60         # generic humanoid: has a real IDLE SEQ + the tent keys
const SPAWN_ANGLE := 0x800        # a sub-cardinal-capable 12-bit facing (West team seed)

var _failed := 0
var _passed := 0


func _ready() -> void:
	var unit = await _build_unit()
	if unit == null:
		_finish()
		return

	# --- Spawn default: combat-idle (march), precise facing, NOT cinematic -------------
	unit.scenario_spawn_facing(SPAWN_ANGLE)
	_expect(unit.facing_angle == SPAWN_ANGLE,
		"spawn seeds the precise 12-bit facing (single source of truth) — got 0x%03X" % unit.facing_angle)
	_expect(not unit.is_cinematic_unit,
		"a spawned battle unit is NOT cinematic (it march-idles, not the tent)")
	unit.update_animation()
	var spawn_slot: int = unit.current_anim_id
	_expect(spawn_slot != 0,
		"spawned unit renders the real march-in-place idle SEQ, not the tent (anim_id 0) — got %d" % spawn_slot)

	# --- The freezing verb is UNCHANGED: scenario_set_facing still tents ---------------
	unit.scenario_set_facing(0xC00)  # NORTH
	_expect(unit.is_cinematic_unit,
		"scenario_set_facing (the {8C}/Warp freeze verb) still marks the unit cinematic")
	unit.update_animation()
	var frozen_slot: int = unit.current_anim_id
	_expect(frozen_slot == 0,
		"scenario_set_facing unit renders the cinematic tent (anim_id 0) — got %d" % frozen_slot)

	_expect(spawn_slot != frozen_slot,
		"spawn-default and freeze verbs resolve to different idle anims (spawn=%d, frozen=%d)" % [
			spawn_slot, frozen_slot])

	unit.queue_free()
	_finish()


func _build_unit():
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = BODY_SPRITE
	add_child(unit)
	await get_tree().process_frame
	if not unit._initialized or unit.animation_set == null:
		_fail("fixture: unit failed to initialize (sprite 0x%02X)" % BODY_SPRITE)
		return null
	return unit


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== UnitScenarioSpawnCombatIdleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] UnitScenarioSpawnCombatIdleTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] UnitScenarioSpawnCombatIdleTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitScenarioSpawnCombatIdleTest")
		get_tree().quit(0)
