extends Node
# test-kind: logic
# seeded-break: Unit.start_attack_with_anim_id's funnel call dispatches display.play_body(0) instead of display.play_body(anim_id) — the pre-fix bug state where the throw never updates current_anim_id; 'throw funnels current_anim_id -> 77' + 'body clock runs on throw front slot 152' RED and all 16 facing/camera painter asserts RED (painter resolves the stale idle pose-octant frames 2/8, not the throw-slot frames front=77/back=141); the 'primed to idle' precondition stays green; GREEN unbroken on the reverted tree
## Characterization test for issue #151 — item-throw body clock/painter dispatch.
##
## The item-throw path runs the body clock on the Throw Weapon SEQ (slots 152/153)
## but, pre-fix, never updated `current_anim_id` — so `_paint_body_variant`
## (Path-D dispatch, ADR-0053) kept resolving frames off the STALE id while the
## clock advanced the throw. Clock and painter diverged; the throw frames only
## rendered when `current_anim_id` coincidentally already matched.
##
## The fix funnels the throw through `display.play_body(anim_id)` — the single
## Path-D seam — so painter + clock share one source of truth. The throw is just
## Path-D anim_id 77: `clock_key = (77-1)*2 = 152`, and the painter derives
## `seq_key = (77-1)*2 + back = 152` (front) / `153` (back) per facing.
##
## Scene-free fixture (same pattern as UnitDisplayPaintGoldenTest): a bare
## `Unit.new()` holding only what the painters read. Asserts:
##   1. after the throw, `current_anim_id == 77` (the funnel updated the dispatch
##      key — the bug was that it stayed stale),
##   2. the body clock runs on the front throw slot ("152"),
##   3. the TYPE1 painter loads the THROW slot's frame (152/153) at the clock's
##      `anim_frame`, NOT the idle frame it resolved from the stale id pre-fix.
##
## Run headful; reads stdout; auto-quits.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController
const AnimationFrameCalculator = ExMateriaSpriteRig.AnimationFrameCalculator

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const UnitProgressionClass = ExMateriaAlmanac.UnitProgression

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

# Same proven fixture as the paint golden: female Chemist with a Blaze Gun.
const JOB := "4b"
const WEAPON := 74
const IS_FEMALE := true

# Throw Weapon: Path-D anim_id 77 ↔ TYPE1 SEQ slots 152 (front) / 153 (back).
const THROW_ANIM_ID := 77
const THROW_FRONT_SLOT := "152"
const THROW_BACK_SLOT := "153"

# FacingDirection: NORTH, EAST, SOUTH, WEST.
const FACINGS := [0, 1, 2, 3]
const FACING_NAME := ["N", "E", "S", "W"]
const CAMERAS := [
	{"quad": 0, "psx": 0xE00},
	{"quad": 1, "psx": 0xA00},
	{"quad": 2, "psx": 0x600},
	{"quad": 3, "psx": 0x200},
]
# A clock frame past 0 so we prove the painter reads the THROW slot at the clock
# position, not just frame 0.
const FRAME_SAMPLE := 2


## Record-only SpriteLayerManager stand-in (mirrors the golden's SpyLayers).
class SpyLayers extends SpriteLayerManager:
	var last_body_frame: int = -1

	func load_frame_by_id(layer: SpriteLayer, frame_id: int, is_first_frame: bool = false) -> void:
		if int(layer) == int(SpriteLayer.TYPE1):
			last_body_frame = int(frame_id)


var _failed := false


func _ready() -> void:
	DebugConfig.iteration_debug_enabled = false

	var unit = _make_unit()
	if unit == null:
		print("[FAIL] UnitThrowBodyDispatchTest: fixture failed to initialize")
		get_tree().quit()
		return

	var display = unit.display
	var seq: Dictionary = unit.animation_set.type1_seq
	if not seq.has(THROW_FRONT_SLOT) or not seq.has(THROW_BACK_SLOT):
		# The throw is a shared TYPE1 animation; the fixture must carry it or the
		# characterization is meaningless — fail loudly rather than skip.
		print("[FAIL] fixture sprite lacks Throw Weapon SEQ slots %s/%s" % [THROW_FRONT_SLOT, THROW_BACK_SLOT])
		unit.free()
		get_tree().quit()
		return

	# Prime a STALE, non-throw dispatch id: idle (current_anim_id 0). Pre-fix this
	# is exactly what made the painter resolve idle while the clock ran the throw.
	display.play_body(0)
	_expect(unit.current_anim_id == 0, "precondition: primed to idle (current_anim_id 0)")

	# Trigger the throw through the funnel seam.
	unit.start_attack_with_anim_id(THROW_ANIM_ID)

	# 1. The funnel updated the dispatch key (the bug: it stayed 0).
	_expect(unit.current_anim_id == THROW_ANIM_ID,
		"throw funnels current_anim_id -> %d (was left stale pre-fix)" % THROW_ANIM_ID)
	# 2. The body clock runs on the front throw slot.
	_expect(display.type1_playback.anim_id == THROW_FRONT_SLOT,
		"body clock runs on throw front slot %s" % THROW_FRONT_SLOT)

	# 3. The painter resolves the THROW slot's frame for every facing/camera —
	#    never the idle frame it picked from the stale id pre-fix.
	var spy: SpyLayers = unit.sprite_layers
	display.type1_playback.anim_frame = FRAME_SAMPLE
	for fi in FACINGS.size():
		for c in CAMERAS:
			display.set_view({
				"facing": FACINGS[fi],
				"facing_angle": -1,
				"camera_quadrant": c["quad"],
				"camera_angle_12bit": c["psx"],
			})
			spy.last_body_frame = -1
			display._render_camera_variant()
			var got := spy.last_body_frame
			var front_frame := AnimationFrameCalculator.get_frame_at(THROW_FRONT_SLOT, FRAME_SAMPLE, seq)
			var back_frame := AnimationFrameCalculator.get_frame_at(THROW_BACK_SLOT, FRAME_SAMPLE, seq)
			var tag := "%s|q%d" % [FACING_NAME[fi], c["quad"]]
			_expect(got == front_frame or got == back_frame,
				"throw %s: body frame %d is a Throw slot frame (front=%d/back=%d)"
					% [tag, got, front_frame, back_frame])

	spy.free()
	unit.anim_state.free()
	unit.free()

	if _failed:
		print("[FAIL] UnitThrowBodyDispatchTest")
	else:
		print("[PASS] UnitThrowBodyDispatchTest: throw funnels through play_body — clock+painter agree on SEQ 152/153")
	get_tree().quit()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s" % label)


# --- fixture (trimmed copy of UnitDisplayPaintGoldenTest._make_unit) ----------

func _make_unit():
	var unit := Unit.new()
	unit.name = "ThrowDispatchFixture"
	unit.body_sprite_id = JobDatabase.get_sprite_id(JOB, IS_FEMALE)

	if not unit._initialize_animation_set():
		return null

	# The throw path sets ATTACKING via `anim_state.current_state`, so — unlike
	# the golden fixture that only drives play_body directly — this fixture needs
	# a real state controller.
	unit.anim_state = AnimationStateController.new()

	var mat := UnitAssets.base_material().duplicate()
	unit.material = mat

	var spy := SpyLayers.new()
	spy.material = mat
	unit.sprite_layers = spy

	unit._initialized = true

	var prog = UnitProgressionClass.new()
	prog.initialize(UnitProgressionClass.BaseStatType.FEMALE, JOB)
	prog.equipment[UnitProgressionClass.EquipSlot.RIGHT_HAND] = WEAPON
	unit.unit_progression = prog
	unit.update_weapon_sprite()

	# Boot the standing idle SEQ (Unit._ready's final step) so the idle prime is a
	# real transition, matching the golden fixture.
	unit.update_animation()

	if unit.animation_set == null or unit.material == null:
		return null
	return unit
