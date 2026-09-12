extends Node
# test-kind: logic
# seeded-break: Unit.reset_scenario_cutscene_state's `_initialized` branch replaced by the pre-fix hardcoded `display.play_body(0)` tent re-arm — 'AFTER scenario-entry reset the unit STILL march-idles (anim_id ≥1), not the tent' + 'reset re-arms the SAME march idle' RED (spawn=4, post-reset=0 — the spawn default clobbered the instant the VM started); the spawn-default arms and the combat-idle-mode arm stay green; GREEN unbroken on the reverted tree
## INTEGRATION guard for change #1 — the spawn combat-idle default must SURVIVE the
## scenario-entry reset. `UnitScenarioSpawnCombatIdleTest` proves `scenario_spawn_facing`
## march-idles a unit in ISOLATION; it never runs the VM's `start()` reset afterwards, so
## it missed the live bug: every scenario boot calls `ScenarioVM.reset_all` →
## `Unit.reset_scenario_cutscene_state`, which re-armed the idle with a HARDCODED
## `play_body(0)` — anim_id 0 is the cinematic TENT (AnimationResolutionMap slot 0), not
## the combat march-in-place idle (slot ≥1). So the spawn default was clobbered the instant
## the VM started: units stood in the tent all through the opener, only the {80}-March
## speaker ever moved. See MARCH_OPCODE_80_SEMANTICS.md §5.2.
##
## This drives the REAL seam: spawn-default a live unit, then run the actual
## `ScenarioVM.reset_all(units_by_id, false)` that `start()` runs, and assert the unit is
## STILL in the march-in-place idle (anim_id ≥1), not the tent (anim_id 0).
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/ScenarioStartPreservesMarchIdleTest.tscn

const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const BODY_SPRITE := 0x60         # generic humanoid: has a real IDLE SEQ + the tent keys
const SPAWN_ANGLE := 0x800        # a sub-cardinal-capable 12-bit facing (West team seed)

var _failed := 0
var _passed := 0


func _ready() -> void:
	var unit = await _build_unit()
	if unit == null:
		_finish()
		return

	# Spawn default: combat march-in-place idle (anim_id ≥1), NOT cinematic.
	unit.scenario_spawn_facing(SPAWN_ANGLE)
	var spawn_slot: int = unit.current_anim_id
	_expect(spawn_slot != 0,
		"spawn default resolves the march-in-place idle (anim_id ≥1), not the tent — got %d" % spawn_slot)
	_expect(not unit.is_cinematic_unit, "spawn default is NOT cinematic")

	# The REAL scenario-entry reset the VM runs at start() (ScenarioVM.gd:1003).
	var vm = ScenarioVMClass.new()
	vm.units_by_id = {0x00: unit}
	vm.reset_all(vm.units_by_id, false)

	# THE INTEGRATION ASSERTION: the reset must re-arm the FAITHFUL default idle for the
	# current mode. is_cinematic_unit was cleared by the reset → the march-in-place idle,
	# not the tent. This is the assertion that went red on the live bug.
	_expect(not unit.is_cinematic_unit,
		"reset leaves the unit in combat-idle mode (is_cinematic_unit == false)")
	var post_reset_slot: int = unit.current_anim_id
	_expect(post_reset_slot != 0,
		"AFTER scenario-entry reset the unit STILL march-idles (anim_id ≥1), not the tent — got %d" % post_reset_slot)
	_expect(post_reset_slot == spawn_slot,
		"reset re-arms the SAME march idle the spawn default chose (spawn=%d, post-reset=%d)" % [
			spawn_slot, post_reset_slot])

	vm.free()
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
	print("\n=== ScenarioStartPreservesMarchIdleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioStartPreservesMarchIdleTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioStartPreservesMarchIdleTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioStartPreservesMarchIdleTest")
		get_tree().quit(0)
