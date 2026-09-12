extends Node
## Characterization + regression guard for the combat-vs-cinematic IDLE mode
## discriminator (ADR-0053 / ADR-0057 Stage 2).
##
## Two distinct idle animations exist (AnimationResolutionMap._resolve_state_for_type):
##   * CINEMATIC idle — scenario VM units collapse to anim_id 0, the pose-octant
##     "at-ease" TENT (Sub-tables A+B, the chapel rotating stance).
##   * COMBAT / gameplay idle — units resolve to their real standing idle SEQ
##     (front 6 -> anim_id 4), the SEQ-range cardinal-collapse path.
##
## Historically the discriminator was the OVERLOADED `facing_angle >= 0` sentinel
## ("-1 == combat"). Stage 2 de-overloads it: the mode moves to an explicit flag so
## `facing_angle` can become an always-valid single source of truth without flipping
## every combat unit into the cinematic tent. This test pins the behavior through the
## PUBLIC verbs (not the raw sentinel), so it holds across that refactor:
##   - a plain combat-faced unit renders the real idle SEQ, and
##   - a scenario-faced unit (scenario_set_facing) renders the tent,
## even after combat units start carrying a real facing_angle (Slice B).
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/UnitCinematicIdleModeTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const BODY_SPRITE := 0x60         # generic humanoid: has a real IDLE SEQ + the tent keys

var _failed := 0
var _passed := 0


func _ready() -> void:
	var unit = await _build_unit()
	if unit == null:
		_finish()
		return

	# --- Combat mode: a plain unit renders its real idle SEQ (not the tent) ------
	# Give it a COMBAT facing first: the setter now writes a real facing_angle (>= 0),
	# so this proves the de-overloading — a valid facing_angle must NOT flip a combat
	# unit into the cinematic tent (that coupling was the old `facing_angle >= 0` mode
	# discriminator; mode now lives on the explicit is_cinematic_unit flag).
	unit.facing_direction = FacingDirection.EAST
	_expect(unit.facing_angle >= 0,
		"combat facing write sets a real facing_angle (single source of truth) — got 0x%03X" % unit.facing_angle)
	_expect(not unit.is_cinematic_unit,
		"a combat facing write does NOT mark the unit cinematic")
	unit.update_animation()
	var combat_slot: int = unit.current_anim_id
	_expect(combat_slot != 0,
		"combat unit renders the real idle SEQ, not the tent (anim_id 0) — got %d" % combat_slot)

	# --- Cinematic mode: a scenario-faced unit renders the pose-octant tent ------
	# scenario_set_facing is the {8C}/Warp instant-face verb — it marks the unit a
	# scenario/cinematic unit (whatever the underlying mechanism).
	unit.scenario_set_facing(0xC00)  # NORTH
	unit.update_animation()
	var cine_slot: int = unit.current_anim_id
	_expect(cine_slot == 0,
		"scenario-faced unit renders the cinematic tent (anim_id 0) — got %d" % cine_slot)

	_expect(combat_slot != cine_slot,
		"the two idle modes resolve to different body anims (combat=%d, cinematic=%d)" % [
			combat_slot, cine_slot])

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
	print("\n=== UnitCinematicIdleModeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] UnitCinematicIdleModeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] UnitCinematicIdleModeTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitCinematicIdleModeTest")
		get_tree().quit(0)
