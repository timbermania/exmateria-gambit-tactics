extends Node
# test-kind: logic
# seeded-break: ScenarioVM._apply_unit_animation gains the pre-fix synchronous `unit.play_body(anim_id + 1)` paint at dispatch — 'dispatch: pose UNCHANGED at {11} dispatch' RED (current_anim_id=4, still 3 — the pose painted on the {11} itself instead of the FOLLOWING Wait, inverting the PSX latch timing); the latch-set, consume-paint/clear, Gap-B frame-hold, Gap-C step-resume, and walk-clobber arms stay green; GREEN unbroken on the reverted tree
## Guard for the {11} Unit Anim pending-pose latch (living doc
## SCENARIO_WAIT_SEMANTICS.md §6b / §7b Finding 5 / §8i-j).
##
## PSX RE (confirmed static + live): {11} Unit Anim does NOT paint the pose at
## dispatch — the writer `set_unit_animation_with_flags` only LATCHES `anim_id+1`
## into `unit+0x0C`. The per-frame consumer `FUN_80085C0C` paints it into the
## visible slot `+0x1DC` on the NEXT elapsed frame and clears the latch. So the
## visible pose update lands on the Wait that FOLLOWS the {11}, not on {11} itself
## (live: parked-217 shows the latch SET/unpainted, parked-218 shows it painted).
##
## Godot used to paint synchronously at dispatch (`_apply_unit_animation` →
## `play_body`), inverting that timing. This test mechanizes the fix — the pc216
## latch, painted during the pc217 Wait, one tick later:
##   1. DISPATCH tick: the latch entry records `pending_anim` and paints NOTHING.
##   2. CONSUME tick: `_consume_pending_body_anims` paints the pose and clears the
##      latch.
##   3. OFF-BY-ONE (Gap B): the consume tick paints SEQ frame 0 and SKIPS this
##      unit's `advance_frame` that tick (marked in `_painted_this_tick`); the
##      FOLLOWING tick advances it to frame 1.
##   4. PARK/STEP (Gap C): the consume is an event-clock transition, not a
##      render-clock advance, so it runs even on a `_ff_skip_first_visual` tick.
##
## Run via: <GODOT> --path . --quit-after 8 res://tests/ScenarioUnitAnimLatchTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"

const IDLE_ANIM := 0x02          # baseline pose (event anim 2 → current_anim_id 3)
const WALK_ANIM := 0x03          # latched pose  (event anim 3 → current_anim_id 4)
const UID := 0x17
const BODY_SPRITE := 0x60        # a generic humanoid whose walk SEQ (slot 6) loops

var _failed := 0
var _passed := 0


func _ready() -> void:
	# --- Build a real, fully-initialized Unit (mirror ScenarioWalkFrameAdvanceTest) ---
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
	# The tick painter flips scenario units to SCENARIO-owned; do it up front so the
	# SEQ frame only advances on our explicit `_advance_scenario_anim` calls (ADR-0083).
	unit.clock_owner = ClockOwner.SCENARIO

	# --- Baseline: paint an initial idle pose so the "prior pose" is known -----
	# Use the paint verb directly (not the latch) so setup doesn't depend on the
	# timing under test. play_body stores anim_id verbatim; idle 0x02 → id 3.
	unit.play_body(IDLE_ANIM + 1)
	var prior_id: int = unit.current_anim_id
	_expect(prior_id == IDLE_ANIM + 1,
		"fixture: baseline pose painted (current_anim_id=%d, want %d)" % [prior_id, IDLE_ANIM + 1])

	# =====================================================================
	# 1. DISPATCH tick — {11} latches only; the visible pose is UNCHANGED
	# =====================================================================
	var ok := vm._apply_unit_animation(unit, UID, WALK_ANIM)
	_expect(ok, "dispatch: latch entry returned true (unit ready)")
	_expect(unit.current_anim_id == prior_id,
		"dispatch: pose UNCHANGED at {11} dispatch (current_anim_id=%d, still %d)" %
			[unit.current_anim_id, prior_id])
	_expect(vm.actor(UID).pending_anim == WALK_ANIM,
		"dispatch: pending_anim latched (=%d, want %d)" % [vm.actor(UID).pending_anim, WALK_ANIM])

	# =====================================================================
	# 2. CONSUME tick — the next visuals phase paints the pose, clears latch
	# =====================================================================
	vm._painted_this_tick.clear()
	vm._consume_pending_body_anims()
	_expect(unit.current_anim_id == WALK_ANIM + 1,
		"consume: pose PAINTED (current_anim_id=%d, want %d)" % [unit.current_anim_id, WALK_ANIM + 1])
	_expect(vm.actor(UID).pending_anim == -1,
		"consume: latch cleared (pending_anim=%d, want -1)" % vm.actor(UID).pending_anim)
	_expect(UID in vm._painted_this_tick,
		"consume: uid recorded in _painted_this_tick")

	# --- 3. OFF-BY-ONE (Gap B): consume paints frame 0, skips advance this tick ---
	# The rest of the visuals phase runs; the painted unit must be skipped so
	# frame 0 is HELD this tick (PSX consumer zeroes the frame counter, no advance).
	vm._advance_scenario_anim()
	var f_consume: int = int(unit.display.type1_playback.anim_frame)
	_expect(f_consume == 0,
		"Gap B: SEQ frame HELD at 0 on the consume tick (frame=%d)" % f_consume)

	# --- Following tick: latch empty, unit no longer marked → frame advances ---
	vm._painted_this_tick.clear()
	vm._consume_pending_body_anims()   # nothing pending now
	vm._advance_scenario_anim()
	var f_next: int = int(unit.display.type1_playback.anim_frame)
	_expect(f_next == 1,
		"Gap B: SEQ frame advances to 1 on the FOLLOWING tick (frame=%d)" % f_next)

	# =====================================================================
	# 4. PARK/STEP (Gap C): consume is an event-clock step — runs even when
	#    the render-clock visual advance is skipped (_ff_skip_first_visual).
	# =====================================================================
	unit.play_body(IDLE_ANIM + 1)                     # reset to a known prior pose
	vm._apply_unit_animation(unit, UID, WALK_ANIM)    # re-latch
	vm._ff_active = true
	vm._ff_skip_first_visual = true
	vm._painted_this_tick.clear()
	vm._consume_pending_body_anims()                  # must still paint on a skip tick
	_expect(unit.current_anim_id == WALK_ANIM + 1,
		"Gap C: consume paints even on a skipped-visual (step-resume) tick (current_anim_id=%d)" %
			unit.current_anim_id)

	# =====================================================================
	# 5. WALK-CLOBBER GUARD — a {28} Walk To that FOLLOWS a still-pending {11}
	#    (no Wait between them) must NOT let the stale latch paint over the walk.
	# =====================================================================
	# Scenario 6 Agrias (0x34): pc263 {11} Unit Anim(2) then pc264 {28} Walk To with
	# no Wait. The Walk To is the newer authoritative body-anim (last-write-wins on
	# the PSX +0x0C slot; real FFT shows her walking). If the pc263 latch survived,
	# the next consume tick would paint idle 0x02 OVER the walk and she'd glide in a
	# frozen idle pose ("walking but isn't"). set_walking must clear the latch.
	vm._ff_active = false
	vm._ff_skip_first_visual = false
	vm.actor(UID).pending_anim = IDLE_ANIM            # re-arm a stale {11} idle latch
	vm._world.set_walking(UID, 0xC00, WALK_ANIM)      # the following {28} walk write
	_expect(vm.actor(UID).pending_anim == -1,
		"walk-clobber: set_walking clears the stale {11} latch (pending_anim=%d, want -1)" %
			vm.actor(UID).pending_anim)
	# And a consume tick after the walk leaves the walk pose intact (nothing to paint).
	unit.play_body(WALK_ANIM + 1)                     # the walk pose set_walking painted
	vm._painted_this_tick.clear()
	vm._consume_pending_body_anims()
	_expect(unit.current_anim_id == WALK_ANIM + 1,
		"walk-clobber: walk pose survives the next consume tick (current_anim_id=%d, want %d)" %
			[unit.current_anim_id, WALK_ANIM + 1])

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
	print("\n=== ScenarioUnitAnimLatchTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioUnitAnimLatchTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioUnitAnimLatchTest")
		get_tree().quit(0)
