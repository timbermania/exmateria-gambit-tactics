extends Node
## Regression test for {28} Walk To's *movement walk animation*.
##
## Ground truth (PSX, pcsx-agent, 2026-06-30 — see
## research/working_documents/scenario_1_captures/HANDOFF_walk_to_animation.md):
## Ovelia's idx-201 Walk To holds unit+0x1DC (SEQ key) = 29 the whole walk, SHP
## frame (+0x1E0) ping-ponging 14-18 — byte-exact to type3_seq.json["29"]. The
## ROM selects this via anim_id 15 (0x0F) → SEQ key (anim_id-1)*2 + front/back
## = seq 28 (front) / 29 (back). It is NOT the combat resolver's seq 8/9 ("fast"
## walk), and the cadence is the SEQ's own authored waits (NOT scaled by Speed).
##
## This pins: (1) the FFT_WALK_ANIM_ID constant + its formula link to clock_key
## 28; (2) that the seq-28/29 walk asset matches the live capture (so it can't
## silently regress); (3) that _op_walk_to arms current_anim_id 15 (Path D), NOT
## anim_state=WALKING; (4) that _end_walk_anim returns the walk to idle.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioWalkToAnimTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainFixture = ExMateriaBattlefield.TerrainFixture

# The map the {28} handler walks on. It used to be an UNBOUNDED `Lattice` subclass
# answering `Vector3.ZERO` for every square in the plane; ADR-0218 dec. 4 refuses an
# unbounded fixture, because the map edge an infinite plane hides is one the real
# consumer meets. 20x20 comfortably contains the (8,4) -> (6,4) walk below.
const MAP_BOUNDS := Rect2i(0, 0, 20, 20)


const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


# --- Mocks -------------------------------------------------------------------

class FakeUnit extends RefCounted:
	var global_position: Vector3 = Vector3.ZERO
	# Takes the production facing verb rather than a writable `facing_direction`
	# ScenarioWorld can fall back onto (#752); `facing_angle` is the source of truth
	# and the cardinal is derived, exactly as on the real `Unit`.
	var facing_angle: int = -1
	var facing_direction: FacingDirection:
		get:
			if facing_angle < 0:
				return FacingDirection.NORTH
			return AnimationStateController.angle_12bit_to_facing(facing_angle)
	var current_anim_id: int = 0
	# null anim_state: _op_walk_to no longer touches it; _end_walk_anim's
	# `anim_state != null` guard short-circuits.
	var anim_state = null

	func scenario_set_facing(target_12bit: int) -> void:
		facing_angle = target_12bit

	# The VM funnels body anims through the facade `play_body` (issue #144, C3b);
	# the double mirrors it onto `current_anim_id` the way real Unit does.
	func play_body(anim_id: int) -> void:
		current_anim_id = anim_id

# ⚠️ THERE WAS A `FakePathfinder` HERE AND IT WENT INERT. It subclassed
# `EventPathfinder` to override `find_path`, which ADR-0226 deleted — so it was
# still being installed on `vm._event_pathfinder`, still accepted by the typed slot,
# and never consulted, while this file went on passing. The real planner runs now,
# over terrain derived from this scene's own `Lattice`, and reaches the free target
# on its own; that is a stronger arm than the stub was, and it is the ROM's answer
# rather than an assumed one. This test's subject is the walk ANIMATION, not the
# route, so it wants a route it did not have to state.


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	return vm


func _make_walk_inst(unit_id: int, x: int, y: int, speed: int) -> Dictionary:
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


func _ready() -> void:
	_test_constant_and_formula()
	_test_walk_seq_asset_matches_psx_capture()
	_test_op_walk_to_arms_anim_15()
	_test_end_walk_anim_resets_to_idle()

	print("\n=== ScenarioWalkToAnimTest: %d passed, %d failed ===" % [_passed, _failed])
	# Emit the runner's verdict marker. run_all_tests.sh scores on `[PASS]`/`[FAIL]`
	# (:2153-2158); the prose "RESULT:" line matches none of its three rules, so
	# without this the test scored NO_VERDICT while passing all 16 assertions.
	if _failed > 0:
		print("[FAIL] ScenarioWalkToAnimTest")
		print("RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWalkToAnimTest")
		print("RESULT: PASS")
		get_tree().quit(0)


# --- Cycle 1: the constant + its link to the SEQ-key formula ------------------

func _test_constant_and_formula() -> void:
	# anim_id 15 is the FFT movement walk; (anim_id-1)*2 = 28 is the clock_key
	# Unit._arm_anim_id_clock arms (front), with +1 (=29) chosen for the back.
	_assert_eq(ScenarioVMClass.FFT_WALK_ANIM_ID, 15, "FFT_WALK_ANIM_ID == 15")
	_assert_eq((ScenarioVMClass.FFT_WALK_ANIM_ID - 1) * 2, 28,
		"(15-1)*2 == 28 (clock_key for seq 28 front)")


# --- Cycle 2: the seq-28/29 walk asset matches the live PSX capture ------------

func _test_walk_seq_asset_matches_psx_capture() -> void:
	# Live PSX: SHP frame (+0x1E0) ping-ponged 15,14,15,16,17,18,17,16 → loop.
	var expected_back := [15, 14, 15, 16, 17, 18, 17, 16]
	var expected_front := [10, 9, 10, 11, 12, 13, 12, 11]
	for path: String in ["res://assets/sprites/animations/type3_seq.json",
			"res://assets/sprites/animations/type1_seq.json"]:
		var seqs: Dictionary = _load_seq(path)
		var fname := path.get_file()
		_assert_true(seqs.has("29"), "%s has seq 29" % fname)
		_assert_true(seqs.has("28"), "%s has seq 28" % fname)
		_assert_eq(_frames_of(seqs.get("29", [])), expected_back,
			"%s seq 29 frames == PSX back-walk capture" % fname)
		_assert_eq(_frames_of(seqs.get("28", [])), expected_front,
			"%s seq 28 frames == PSX front-walk" % fname)
		# It must LOOP (IncrementLoop terminator), like the real walk.
		var last: Dictionary = (seqs["29"] as Array).back()
		_assert_eq(str(last.get("op_code_name", "")), "IncrementLoop",
			"%s seq 29 loops" % fname)


# --- Cycle 3: _op_walk_to arms anim_id 15 (Path D), not WALKING ----------------

func _test_op_walk_to_arms_anim_15() -> void:
	var vm := _make_vm()
	# The fixture is a node and goes IN the tree — the double never was (its
	# `global_position` was a plain field), and a tile's is only meaningful once its
	# parent's is.
	var fixture := TerrainFixture.flat(MAP_BOUNDS)
	add_child(fixture)
	vm.map_composer = fixture
	var fake := FakeUnit.new()
	fake.global_position = Vector3(8.5, MapConstants.surface_y(0), 4.5)
	vm.units_by_id = {0x000C: fake}

	vm._op_walk_to(_make_walk_inst(0x000C, 6, 4, 4))

	_assert_eq(fake.current_anim_id, ScenarioVMClass.FFT_WALK_ANIM_ID,
		"_op_walk_to arms current_anim_id = 15 (seq 28/29 walk)")
	# It must NOT route through the combat WALKING activity (that path picks
	# seq 8/9 AND freezes the clock via the 0-duration multiplier).
	_assert_true(fake.anim_state == null,
		"_op_walk_to does not set the WALKING activity")
	vm.queue_free()


# --- Cycle 4: _end_walk_anim returns the walk to idle -------------------------

func _test_end_walk_anim_resets_to_idle() -> void:
	var vm := _make_vm()
	# A unit mid-walk (anim 15) is reset to the idle anchor (0) on arrival.
	var walking := FakeUnit.new()
	walking.current_anim_id = ScenarioVMClass.FFT_WALK_ANIM_ID
	vm._end_walk_anim(walking)
	_assert_eq(walking.current_anim_id, 0, "_end_walk_anim resets 15 -> 0 (idle)")

	# A unit on some OTHER anim is left alone (don't clobber a re-armed body).
	var other := FakeUnit.new()
	other.current_anim_id = 7
	vm._end_walk_anim(other)
	_assert_eq(other.current_anim_id, 7, "_end_walk_anim leaves non-walk anim untouched")
	vm.queue_free()


# --- helpers -----------------------------------------------------------------

func _load_seq(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("could not open %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Dictionary else {}

func _frames_of(seq: Array) -> Array:
	var out: Array = []
	for e in seq:
		if str(e.get("op_code_name", "")) == "LoadFrameWait":
			out.append(int(e.get("op_code_param_0", -1)))
	return out

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s  (got %s, expected %s)" % [label, str(actual), str(expected)])

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % label)

func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: %s" % label)
