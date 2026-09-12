extends Node
# test-kind: logic
# seeded-break: Unit._on_facing_direction_changed gains the pre-fix clobber — a `update_animation()` call that re-resolves the body from `activity` (still IDLE) on every cardinal flip; detectors C (walk current_anim_id survives) and A (walk clock keeps its own SEQ key) red, B (BODY stays on own SPR atlas) stays green as documented; GREEN unbroken on the reverted tree
## Regression detector for the "Gafgarion slides to the door with no walk
## animation" bug (handoff_gafgarion_slide_no_anim.md).
##
## The visible-only symptom (body frozen on a pose while the position lerps) is
## why the first fix shipped green but wrong: the mock-based walker tests never
## exercised REAL frame advance on a REAL Unit through the scenario path.
##
## This test builds a real Unit (full sprite-init + animation_set + playback +
## SpriteLayerManager material), then drives the exact door-exit choreography
## through the REAL ScenarioVM handlers:
##   1. a cinematic-range Unit Anim (0x260) that arms the EVTCHR walker and
##      binds the BODY layer to the shared segment atlas,
##   2. the walker runs to completion (as it does before the exit),
##   3. a low-range walk Unit Anim (0x03) — the door-exit walk,
##   4. a Sprite Move slide's worth of per-frame `_process` ticks.
##
## Detectors:
##   C. WALK CLOCK SURVIVES (the real one): a concurrent `Rotate Unit` cascade
##      flips the cardinal mid-slide; each flip must NOT re-resolve the body
##      from `activity` (still IDLE) and clobber the scenario's walk
##      `current_anim_id`. That clobber was the root cause of the freeze.
##   A. WALK CLOCK KEEPS TICKING its own SEQ key (a clobber re-arms the clock
##      onto the idle key). "Frames changed" alone is a FALSE NEGATIVE — the
##      clobbered idle pose still repaints on facing changes.
##   B. ATLAS BINDING: the BODY `type1_tex` stays the unit's own SPR, NOT the
##      shared EVTCHR `segment_###.tga` (documents that cinematic-mode was a
##      red herring for this freeze — B is green with and without the fix).
##
## Run via: <GODOT> --path . --quit-after 8 res://tests/ScenarioWalkFrameAdvanceTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"

const WALK_ANIM := 0x03          # event anim 3 = walk (→ current_anim_id 4, clock slot 6)
const CINE_ANIM := 0x260         # seg0 local 8: EVTCHR frame then a <0xD2 restore + Pause
const GAFG_UID := 0x17           # Gafgarion's roster uid (door-exit actor)
const BODY_SPRITE := 0x60        # a generic humanoid whose walk SEQ (slot 6) loops

var _failed := 0
var _passed := 0


func _ready() -> void:
	# --- Build a real, fully-initialized Unit --------------------------------
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = BODY_SPRITE
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run

	if not unit._initialized or unit.display.type1_playback == null or unit.animation_set == null:
		_fail("fixture: unit failed to initialize (sprite 0x%02X)" % BODY_SPRITE)
		_finish()
		return

	# Guard the fixture: the walk clock slot must actually loop, else this test
	# would false-freeze for a reason unrelated to the bug under test.
	var walk_clock := "6"  # (WALK_ANIM+1 - 1)*2
	if not unit.animation_set.type1_seq.has(walk_clock):
		_fail("fixture: sprite 0x%02X has no walk clock slot '%s'" % [BODY_SPRITE, walk_clock])
		_finish()
		return

	var vm = ScenarioVMClass.new()

	# --- 1. Cinematic Unit Anim: arm the walker, bind the EVTCHR atlas --------
	# {11} now LATCHES at dispatch (`_apply_unit_animation`) and paints on the next
	# elapsed tick. This test asserts frame-advance/atlas-binding, not latch timing,
	# and reads `current_anim_id` immediately, so it drives the PAINT half directly.
	vm._paint_unit_animation(unit, GAFG_UID, CINE_ANIM)
	# 2. Run the walker + unit process to completion (as the intro cinematic does).
	for i in range(20):
		vm._tick_cinematic_walkers()
		unit._process(1.0 / 60.0)

	# --- 3. Door-exit choreography (block@340), in VM opcode order -----------
	# The real block drains these in ONE frame (Sprite Move sets no wait_ticks):
	#   Rotate Unit (arms a stepper that turns over the NEXT frames) → walk anim.
	# The rotate stepper then flips the cardinal frame-by-frame DURING the slide,
	# and each cardinal flip must NOT clobber the scenario-driven walk clock.
	# Seed a baseline facing so the rotation actually STEPS across cardinals
	# (a cardinal flip is what fires `facing_direction_changed`).
	unit.facing_angle = 0x000                              # byte 0 (East)
	if unit.anim_state:
		unit.anim_state.set_facing(FacingDirection.EAST)
	unit.scenario_rotate(0x800, 1, 1, 0)  # CW sweep byte 0→8, speed 1: crosses S→W
	vm._paint_unit_animation(unit, GAFG_UID, WALK_ANIM)  # paint half (see note above)
	var walk_anim_id: int = unit.current_anim_id  # = 4; the value the walk armed

	# --- 4. A Sprite Move slide's worth of ticks -----------------------------
	# (Sprite Move deliberately attaches no anim; the walk must animate on its
	# own via the per-frame playback the {11} Unit Anim armed.) The rotation
	# stepper advances every tick, mirroring ScenarioVM._tick_unit_rotations.
	var walk_clock_key: String = unit.display.type1_playback.anim_id  # the walk SEQ clock key
	var anim_frames_seen := {}
	var atlas_had_segment := false
	var walk_id_survived := true
	var walk_clock_survived := true
	for i in range(45):
		unit._tick_rotate()           # the concurrent rotation cascade
		unit._process(1.0 / 60.0)
		vm._tick_cinematic_walkers()  # catch a walker re-arming/repainting EVTCHR
		if unit.current_anim_id != walk_anim_id:
			walk_id_survived = false  # something clobbered the walk anim id
		if unit.display.type1_playback.anim_id != walk_clock_key:
			walk_clock_survived = false  # walk clock got re-armed onto another key
		anim_frames_seen[int(unit.display.type1_playback.anim_frame)] = true
		var tex = unit.material.get_shader_parameter("type1_tex")
		if tex != null and str(tex.resource_path).contains("segment_"):
			atlas_had_segment = true

	# --- Detector C: the walk clock must survive the concurrent rotation -----
	_expect(walk_id_survived,
		"C: walk current_anim_id (%d) survives the rotation cascade (a facing flip must not re-resolve it to idle)" % walk_anim_id)

	# --- Detector A: the walk SEQ clock keeps ticking its OWN key ------------
	# (A cardinal-flip clobber re-arms the clock onto the idle key — the walk
	# stops cycling even though the idle pose still repaints on facing changes,
	# which is why "frames changed" alone is a false-negative.)
	_expect(walk_clock_survived and anim_frames_seen.keys().size() > 1,
		"A: walk clock '%s' keeps advancing its own key (survived=%s, distinct anim_frames=%d)" % [
			walk_clock, str(walk_clock_survived), anim_frames_seen.keys().size()])

	# --- Detector B: BODY must be on the unit's own SPR, not EVTCHR ----------
	_expect(not atlas_had_segment,
		"B: BODY stays on own SPR during slide (never re-bound to segment_ EVTCHR atlas)")

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
	print("\n=== ScenarioWalkFrameAdvanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioWalkFrameAdvanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWalkFrameAdvanceTest")
		get_tree().quit(0)
