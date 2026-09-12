extends Node
## Regression: {28} Walk To must write the ORIENTATION source of truth
## (`Unit.facing_angle`), not just the derived `FacingDirection` enum.
##
## The VM sprite renderer picks a unit's pose octant from `facing_angle`
## (UnitDisplay.gd), so a walk that updates only `facing_direction` leaves the
## unit rendering its STALE pre-walk facing for the whole walk. The scenario-6
## chocobo reproduced it: `Warp {Facing 2}` set `facing_angle = 0x800` (WEST),
## then the +X (NORTH) walk wrote only the enum → the chocobo drew WEST while
## moving NORTH = walking sideways. Measured on hardware, the ROM re-faces its
## single facing field (`+0x70`) to the travel cardinal (0x800 → 0xC00); Godot
## must too. See research/working_documents/CHOCOBO_WALK_OCTANT_28.md.
##
## ADR-0057 "one truth, derived views": the walk sets `facing_angle` via the
## forward heading->12bit converter (`PsxNum.heading_to_12bit`); the enum
## follows as a derived view. Both Walk To facing touch points are covered:
##   1. set_walking      — the initial heading.
##   2. set_walk_facing  — a per-segment route turn (mid-walk re-face).
##   3. _op_walk_to       — end-to-end, the {28} handler through ScenarioApply.
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/ScenarioWalkFacingAngleTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainFixture = ExMateriaBattlefield.TerrainFixture
## And the same for `addons/exmateria_platform`, which shed `DisplayPort` — the
## name of a hardware standard — under ADR-0212 dec. 1.
const PsxNum = ExMateriaPlatform.PsxNum

# The map the walk runs on. The double it replaces was UNBOUNDED — every square in
# the plane existed — which ADR-0218 dec. 4 refuses: no map in the game is unbounded,
# and the edge an infinite plane hides is one the real consumer meets. It already
# answered the tile CENTRE (`x + 0.5`), so this file needed no re-basing in X/Z; what
# it did NOT have is a surface height, and a height-0 tile sits at `(12·0 + 1)/28`,
# not at 0.
const MAP_BOUNDS := Rect2i(0, 0, 12, 12)


const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const Facing = ExMateriaSchema.Facing.Direction
const CHOCO_UID := 0x8B          # scenario-6 chocobo (matches the living-doc beat)
const BODY_SPRITE := 0x60        # a generic humanoid whose walk SEQ (slot 6) loops
const WALK_ANIM := 15            # FFT movement-walk anim id

# Canonical wheel: 0x000=E, 0x400=S, 0x800=W, 0xC00=N.
const WEST_12BIT := 0x800
const NORTH_12BIT := 0xC00

var _failed := 0
var _passed := 0


func _ready() -> void:
	var unit = await _build_unit()
	if unit == null:
		_finish()
		return

	var vm = ScenarioVMClass.new()
	add_child(vm)
	vm.units_by_id = {CHOCO_UID: unit}

	# Pre-walk state = the chocobo's Warp: face WEST precisely (0x800). This seeds
	# BOTH stores (facing_angle + the derived enum) the way {24} Warp does.
	unit.scenario_set_facing(WEST_12BIT)

	# --- 1. set_walking writes facing_angle from the +X (NORTH) heading ---------
	var north := PsxNum.heading_to_12bit(1.07, 0.0)   # +X dominant -> 0xC00 NORTH
	vm._world.set_walking(CHOCO_UID, north, WALK_ANIM)
	_expect(unit.facing_angle == NORTH_12BIT,
		"set_walking writes facing_angle NORTH 0xC00 (was WEST 0x800) — got 0x%03X" % unit.facing_angle)
	_expect(int(unit.facing_direction) == int(Facing.NORTH),
		"derived facing_direction follows -> NORTH")

	# --- 2. set_walk_facing re-faces facing_angle on a route turn ---------------
	# The route turns to head -Z (WEST). The per-segment re-face must move the
	# source of truth, not just the enum.
	var west := PsxNum.heading_to_12bit(0.0, -1.0)    # -Z -> 0x800 WEST
	vm._world.set_walk_facing(CHOCO_UID, west)
	_expect(unit.facing_angle == WEST_12BIT,
		"set_walk_facing writes facing_angle WEST 0x800 on a turn — got 0x%03X" % unit.facing_angle)
	_expect(int(unit.facing_direction) == int(Facing.WEST),
		"derived facing_direction follows the turn -> WEST")

	# --- 3. End-to-end: _op_walk_to leaves facing_angle == the travel cardinal --
	# Re-seed the WEST warp facing, place the unit at grid (2,0), and walk it to
	# (5,0) = +X NORTH through the real {28} handler (ScenarioApply.walk_to).
	unit.scenario_set_facing(WEST_12BIT)
	unit.global_position = Vector3(2.5, MapConstants.surface_y(0), 0.5)
	var fixture := TerrainFixture.flat(MAP_BOUNDS)
	add_child(fixture)
	vm.map_composer = fixture
	vm._op_walk_to(_walk_inst(CHOCO_UID, 5, 0, 8))
	_expect(unit.facing_angle == NORTH_12BIT,
		"_op_walk_to (2,0)->(5,0) orients facing_angle NORTH 0xC00 — got 0x%03X" % unit.facing_angle)

	vm.queue_free()
	unit.queue_free()
	_finish()


# --- fixtures ----------------------------------------------------------------

func _build_unit():
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = BODY_SPRITE
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run
	if not unit._initialized or unit.animation_set == null:
		_fail("fixture: unit failed to initialize (sprite 0x%02X)" % BODY_SPRITE)
		return null
	return unit


func _walk_inst(unit_id: int, x: int, y: int, speed: int) -> Dictionary:
	return {
		"name": "Walk To", "opcode": 0x28,
		"params": [
			{"name": "Unit", "value": unit_id},
			{"name": "X", "value": x},
			{"name": "Y", "value": y},
			{"name": "Z", "value": 0},
			{"name": "Speed", "value": speed},
		],
	}


# ⚠️ THERE WAS A `_FakePathfinder` HERE AND IT WENT INERT. It overrode `find_path`,
# which ADR-0226 deleted; it was still installed on `vm._event_pathfinder`, still
# accepted by the typed slot, and never consulted, while this file went on passing.
# The real planner routes to the free target on its own now, over terrain derived
# from this scene's `Lattice`. This test's subject is the FACING angle a walk writes,
# not the route, so a route it did not have to state is the better input.


# --- harness -----------------------------------------------------------------

func _expect(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== ScenarioWalkFacingAngleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioWalkFacingAngleTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioWalkFacingAngleTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWalkFacingAngleTest")
		get_tree().quit(0)
