extends Node
# test-kind: logic
# seeded-break: ScenarioVM._paint_revealed_unit_anims's drain loop no-oped (the reveal drain stops draining the pending {11} latch) — the reveal frame wears the previous pose (current_anim_id=3, want 4), the latch stays pending, and the uid is not recorded in _painted_this_tick — all three red; the already-visible §8i latch control, the no-{11} bare reveal, and the idempotent-{44} arms stay green; GREEN unbroken on the reverted tree
## Guard for the {44} Draw Unit REVEAL POSE — the scenario-29 pc 76 one-frame
## unit flash (issue: "at pc 93 a unit spawns on top of Algus, then moves one
## frame later — it's a flash").
##
## THE DEFECT. {11} Unit Anim does not paint at dispatch: it LATCHES, and
## `_consume_pending_body_anims` paints on the NEXT elapsed tick (the PSX `+0x0C`
## slot / `FUN_80085C0C` consumer — SCENARIO_WAIT_SEMANTICS.md §6b/§8g-k, guarded
## by ScenarioUnitAnimLatchTest). {44} Draw Unit, by contrast, flipped `visible`
## IMMEDIATELY. So a script that reveals a unit and dresses it in the SAME tick —
##     76 Draw Unit  Unit=8
##     77 Unit Anim   Units=8, Animation=601+41
##     78 Sprite Move Unit=8
## — rendered ONE frame of the unit wearing its PREVIOUS pose. In scenario 29
## that previous pose is the spawn default: unit 8 is a tiny thrown EVTCHR prop,
## but for that single frame it drew its full-size TYPE1 human sprite, seated
## directly over unit 7. A whole extra character blinked on top of Algus.
##
## THE RULE THIS PINS. A reveal must not render a pose the same tick's script has
## already superseded. `_paint_revealed_unit_anims()` runs at the end of the
## dispatch tick and drains the pending latch for units revealed THAT tick only.
## Arm 2 is the no-trade control: an ALREADY-VISIBLE unit keeps the one-tick latch
## (§8i is not weakened — there the previous pose is a pose the player was already
## looking at, and PSX shows it for that frame).
##
## Run via: <GODOT> --path . --quit-after 8 res://tests/ScenarioDrawUnitRevealPoseTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"

const IDLE_ANIM := 0x02          # the spawn-default pose (event anim 2 → id 3)
const PROP_ANIM := 0x03          # the pose {11} dresses the reveal in (→ id 4)
const UID := 0x08                # scenario 29's thrown prop
const BODY_SPRITE := 0x60        # a generic humanoid whose SEQs resolve

var _failed := 0
var _passed := 0


func _ready() -> void:
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = BODY_SPRITE
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run

	if not unit._initialized or unit.display.type1_playback == null or unit.animation_set == null:
		_fail("fixture: unit failed to initialize (sprite 0x%02X)" % BODY_SPRITE)
		_finish()
		return

	var vm = ScenarioVMClass.new()
	vm.units_by_id[UID] = unit
	unit.clock_owner = ClockOwner.SCENARIO
	var world: ScenarioWorld = vm._world

	# =====================================================================
	# 1. THE DEFECT — reveal + {11} in ONE dispatch tick must land TOGETHER
	# =====================================================================
	unit.play_body(IDLE_ANIM + 1)          # the spawn-default pose ({44} has not run)
	unit.visible = false                   # held hidden, exactly as pc 41 Add Draw=1 leaves it
	_expect(unit.current_anim_id == IDLE_ANIM + 1,
		"fixture: prior pose painted (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, IDLE_ANIM + 1])

	# The pc76 / pc77 pair, dispatched on the same tick by the block context.
	ScenarioApply.draw_unit(UID, world)
	vm._apply_unit_animation(unit, UID, PROP_ANIM)
	_expect(unit.visible, "reveal: {44} Draw Unit made the sprite visible")
	_expect(vm.actor(UID).pending_anim == PROP_ANIM,
		"reveal: {11} latched the new pose (pending_anim=%d, want %d)" %
			[vm.actor(UID).pending_anim, PROP_ANIM])

	# End of the dispatch tick — the reveal drain runs before the frame is drawn.
	vm._painted_this_tick.clear()
	vm._paint_revealed_unit_anims()
	_expect(unit.current_anim_id == PROP_ANIM + 1,
		"reveal: the REVEAL FRAME already wears the new pose (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, PROP_ANIM + 1])
	_expect(vm.actor(UID).pending_anim == -1,
		"reveal: latch cleared by the reveal drain (pending_anim=%d, want -1)" %
			vm.actor(UID).pending_anim)
	_expect(UID in vm._painted_this_tick,
		"reveal: uid recorded in _painted_this_tick (no double frame-advance this tick)")

	# The reveal set is per-tick: a second drain with nothing revealed is a no-op.
	vm._paint_revealed_unit_anims()
	_expect(vm._revealed_this_tick.is_empty(),
		"reveal: the revealed-this-tick set is drained, not sticky")

	# =====================================================================
	# 2. NO TRADE — an ALREADY-VISIBLE unit keeps the §8i one-tick latch
	# =====================================================================
	unit.play_body(IDLE_ANIM + 1)
	_expect(unit.visible, "control: unit is already on screen")
	vm._apply_unit_animation(unit, UID, PROP_ANIM)
	vm._painted_this_tick.clear()
	vm._paint_revealed_unit_anims()
	_expect(unit.current_anim_id == IDLE_ANIM + 1,
		"control: no reveal this tick → pose UNCHANGED, latch still pending (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, IDLE_ANIM + 1])
	_expect(vm.actor(UID).pending_anim == PROP_ANIM,
		"control: the {11} latch survives to the normal consume tick (pending_anim=%d, want %d)" %
			[vm.actor(UID).pending_anim, PROP_ANIM])
	vm._consume_pending_body_anims()
	_expect(unit.current_anim_id == PROP_ANIM + 1,
		"control: the normal consume tick paints it (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, PROP_ANIM + 1])

	# =====================================================================
	# 3. A REVEAL WITH NO {11} leaves the pose alone (and does not crash)
	# =====================================================================
	unit.play_body(IDLE_ANIM + 1)
	ScenarioApply.erase_unit(UID, world)
	_expect(not unit.visible, "erase: {46} Erase Unit hid the sprite")
	ScenarioApply.draw_unit(UID, world)
	vm._painted_this_tick.clear()
	vm._paint_revealed_unit_anims()
	_expect(unit.current_anim_id == IDLE_ANIM + 1,
		"bare reveal: no pending {11} → pose untouched (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, IDLE_ANIM + 1])

	# =====================================================================
	# 4. A REDUNDANT {44} on a VISIBLE unit is not a reveal
	# =====================================================================
	# ScenarioApply.draw_unit is idempotent; re-issuing it must not arm the drain,
	# or an already-visible unit would lose the §8i latch through the back door.
	ScenarioApply.draw_unit(UID, world)
	_expect(vm._revealed_this_tick.is_empty(),
		"idempotent {44}: a visible→visible write does not count as a reveal")

	vm.free()
	unit.queue_free()
	_finish()


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== ScenarioDrawUnitRevealPoseTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioDrawUnitRevealPoseTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDrawUnitRevealPoseTest")
		get_tree().quit(0)
