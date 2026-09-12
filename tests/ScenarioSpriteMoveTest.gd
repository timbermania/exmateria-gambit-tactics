extends Node
## Focused unit test for the {3B} Sprite Move / {6E} Sprite Move Beta / {6F}
## Wait Sprite Move opcodes in ScenarioVM (see SPRITE_MOVE_INVESTIGATION.md,
## ROM handler FUN_80149C48). Sprite Move is a per-unit straight-line position
## lerp (NOT a pathfind, NOT an animation/facing). This test drives the
## handlers directly with synthetic instructions against real Node3D mock
## units so positions are observable, and asserts:
##   * absolute-target conversion (28 opcode-units = 1 tile; signed; the operand
##     is an absolute PSX target, so repeat moves travel operand2-operand1)
##   * the eased interpolation reaches the target
##   * easing curves per Type + weight, pinned bit-exact to live PSX traces
##   * {6F} blocks the calling context for the move's remaining duration
##   * concurrent per-unit moves coexist
##   * {6E} Beta derives duration from Speed (4·distance / speed)
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioSpriteMoveTest.tscn

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


const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0


# Minimal mock unit for {28} Walk To, which (unlike Sprite Move) faces the unit and
# reads `anim_state`. anim_state stays null (the handler guards every access).
#
# The double takes `scenario_set_facing` — the SAME verb the real `Unit` offers —
# rather than exposing a writable `facing_direction` for `ScenarioWorld` to fall back
# onto (#752). It is shaped like `Unit`: `facing_angle` is the single truth and the
# cardinal is derived through the production converter (ADR-0057), so the double can
# disagree neither with itself nor with `Unit` about how an angle becomes a cardinal.
class MockWalkUnit extends Node3D:
	var anim_state = null
	# The 12-bit orientation angle; `-1` = never faced (mirrors `Unit.facing_angle`).
	var facing_angle: int = -1
	var facing_direction: FacingDirection:
		get:
			if facing_angle < 0:
				return FacingDirection.NORTH
			return AnimationStateController.angle_12bit_to_facing(facing_angle)

	func scenario_set_facing(target_12bit: int) -> void:
		facing_angle = target_12bit


# The map every Walk To test here runs on: a flat 20x20 at FFT height 0, stood up by
# the addon's own fixture (ADR-0218). It replaces a `Lattice` subclass that answered
# `Vector3.ZERO` for every square and a `extends Node` wrapper that existed only to
# carry it — a `Node3D` exposing `lattice` is what `ScenarioVM._lattice()` probes for,
# so the wrapper had nothing left to do.
#
# The bound is the same 0..19 the mock enforced by hand, and it is still what stops the
# event pathfinder's flood: off the fixture there is no tile, exactly as off the real
# store there is none.
const MAP_BOUNDS := Rect2i(0, 0, 20, 20)

# 🔴 A HEIGHT-0 TILE IS NOT AT Y=0. Its surface is `(12·0 + 1)/28` = 0.0357 world
# units — the exporter's half-step arithmetic, which `MapConstants.surface_y` owns
# since ADR-0218 dec. 5. The mock answered a flat `Vector3.ZERO`, so every Walk To
# world-Y expectation in this file was written against a surface production does not
# have. They are re-based onto this (dec. 3). The Sprite Move assertions are NOT: that
# opcode offsets a unit from wherever it stands and never asks the lattice anything,
# which is why those expectations keep their literal 0 and these do not.
var _ground_y: float = MapConstants.surface_y(0)


func _install_map(vm: Object) -> TerrainFixture:
	var fixture := TerrainFixture.flat(MAP_BOUNDS)
	vm.map_composer = fixture
	add_child(fixture)
	return fixture


func _ready() -> void:
	_run()
	print("\n=== ScenarioSpriteMoveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioSpriteMoveTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioSpriteMoveTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioSpriteMoveTest")
		get_tree().quit(0)


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _assert_near(got: float, want: float, name: String, eps: float = 0.01) -> void:
	if absf(got - want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%.4f want=%.4f" % [name, got, want])


func _assert_vec(got: Vector3, want: Vector3, name: String, eps: float = 0.01) -> void:
	if got.distance_to(want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# Synthetic opcode instruction matching the disassembler's params shape.
func _sprite_move_inst(unit: int, dx: int, dz: int, dy: int, type: int, time: int) -> Dictionary:
	return {"name": "Sprite Move", "opcode": 0x3B, "params": [
		{"name": "Unit", "value": unit}, {"name": "+X", "value": dx},
		{"name": "+Z", "value": dz}, {"name": "+Y", "value": dy},
		{"name": "Type", "value": type}, {"name": "Unknown", "value": 1},
		{"name": "Time", "value": time}]}


func _beta_inst(unit: int, dx: int, dz: int, dy: int, type: int, speed: int) -> Dictionary:
	return {"name": "Sprite Move Beta", "opcode": 0x6E, "params": [
		{"name": "Unit", "value": unit}, {"name": "+X", "value": dx},
		{"name": "+Z", "value": dz}, {"name": "+Y", "value": dy},
		{"name": "Type", "value": type}, {"name": "Unknown", "value": 1},
		{"name": "Speed", "value": speed}]}


func _wait_inst(unit: int) -> Dictionary:
	return {"name": "Wait Sprite Move", "opcode": 0x6F, "params": [{"name": "Unit", "value": unit}]}


# {28} Walk To: Unit, X, Y(=grid Z row), Z(height), Unknown, Speed.
func _walk_to_inst(unit: int, x: int, y: int, speed: int) -> Dictionary:
	return {"name": "Walk To", "opcode": 0x28, "params": [
		{"name": "Unit", "value": unit}, {"name": "X", "value": x},
		{"name": "Y", "value": y}, {"name": "Z", "value": 0},
		{"name": "Unknown", "value": 0}, {"name": "Speed", "value": speed}]}


func _wait_walk_inst(unit: int) -> Dictionary:
	return {"name": "Wait Walk", "opcode": 0x29, "params": [{"name": "Unit", "value": unit}]}


func _make_vm() -> Object:
	var vm = ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)  # drive timing deterministically, no auto _process
	vm.start()
	return vm


# In-flight motion for a uid, or null. Motions now live on the per-unit
# ScenarioActor (ADR-0064), not a flat `vm.motions` dict. Untyped: a Sprite Move is
# a ScenarioMotion, a Walk To is a ScenarioPathMotion (sibling stepper).
func _motion_of(vm, uid: int):
	var a = vm.peek_actor(uid)
	return a.motion if a != null else null


# The seat/endpoint a Walk To ScenarioPathMotion targets (its last route waypoint) —
# the path-motion analogue of a ScenarioMotion's `.target`.
func _walk_endpoint_of(vm, uid: int) -> Vector3:
	var m = _motion_of(vm, uid)
	return m.waypoints[m.waypoints.size() - 1] if m != null else Vector3.INF


func _add_unit(vm: Object, uid: int, pos: Vector3) -> Node3D:
	var u := Node3D.new()
	add_child(u)
	u.global_position = pos
	vm.units_by_id[uid] = u
	return u


func _run() -> void:
	_test_basic_move()
	_test_negative_delta()
	_test_absolute_target()
	_test_easing_curves()
	_test_curve_matches_hardware_trace()
	_test_wait_blocks()
	_test_motion_watchdog_is_duration_derived()
	_test_concurrent()
	_test_sprite_move_axis_mapping()
	_test_beta_speed()
	_test_walk_to()
	_test_walk_to_consumes_preflipped_rows()
	_test_walk_to_walks_through_occupant()
	_test_base_position_for_dialogue_box()


# Baked scenario_1 {3B}: unit 0x13 +X=0x1C (28) over Time=0x28 (40), linear.
# 28 opcode-units = 1 tile, so the target is start + (1,0,0) in Godot.
func _test_basic_move() -> void:
	var vm := _make_vm()
	var u := _add_unit(vm, 0x13, Vector3.ZERO)
	vm._op_sprite_move(_sprite_move_inst(0x13, 28, 0, 0, 0, 40))
	_assert(_motion_of(vm, 0x13) != null, "basic: move record armed")
	var rec: ScenarioMotion = _motion_of(vm, 0x13)
	_assert_vec(rec.target, Vector3(1, 0, 0), "basic: target = start + 1 tile X")
	_assert_near(float(rec.dur_s), 40.0 / 60.0, "basic: dur = Time/60")

	# Halfway through (linear): position ~ 0.5 tile.
	vm._advance_motions((40.0 / 60.0) * 0.5)
	_assert_near(u.global_position.x, 0.5, "basic: half-way x")
	# Finish: lands exactly on target and the record is popped.
	vm._advance_motions(40.0 / 60.0)
	_assert_vec(u.global_position, Vector3(1, 0, 0), "basic: reaches target")
	_assert(_motion_of(vm, 0x13) == null, "basic: record cleared at done")
	vm.queue_free()


# Signed delta: +X = 0xFFE4 (65508 u16 = -28) → 1 tile the other way.
func _test_negative_delta() -> void:
	var vm := _make_vm()
	var u := _add_unit(vm, 0x17, Vector3(5, 0, 5))
	vm._op_sprite_move(_sprite_move_inst(0x17, 65508, 0, 0, 0, 1))
	var rec: ScenarioMotion = _motion_of(vm, 0x17)
	_assert_vec(rec.target, Vector3(4, 0, 5), "neg: target = start - 1 tile X")
	vm._advance_motions(1.0)  # Time=1 → snaps within a frame
	_assert_vec(u.global_position, Vector3(4, 0, 5), "neg: reaches target")
	vm.queue_free()


# The operand is the absolute value of the unit's position-OFFSET field (+0x60),
# which the renderer adds to its base (+0x40); so the move's endpoint is
# `home + operand`, NOT a per-move delta (verified on hardware:
# orbonne_three_actors_walk_in offsets a unit to -28 via a T=1 move, then moves
# it with operand 0 and it returns to home (offset 0), NOT to home-28). A second
# move travels (operand2 - operand1) but always ends at home + operand2.
func _test_absolute_target() -> void:
	var vm := _make_vm()
	var u := _add_unit(vm, 0x21, Vector3.ZERO)
	# Move 1: absolute target +X=-28 → 1 tile left (first move deltas from 0).
	vm._op_sprite_move(_sprite_move_inst(0x21, 65508, 0, 0, 0, 1))  # 65508 = -28
	vm._advance_motions(1.0)
	_assert_vec(u.global_position, Vector3(-1, 0, 0), "abs: move1 lands at -1 tile")
	# Move 2: absolute target +X=0 → travels +28 (0 - (-28)), back to origin.
	vm._op_sprite_move(_sprite_move_inst(0x21, 0, 0, 0, 0, 28))
	var rec: ScenarioMotion = _motion_of(vm, 0x21)
	_assert_vec(rec.target, Vector3(0, 0, 0), "abs: move2 target = origin (+28 travel)")
	vm._advance_motions(1.0)
	_assert_vec(u.global_position, Vector3(0, 0, 0), "abs: move2 lands back at origin")
	# Move 3: absolute target +X=-14 → travels -14 (-14 - 0) → half tile left.
	vm._op_sprite_move(_sprite_move_inst(0x21, 65522, 0, 0, 0, 28))  # 65522 = -14
	vm._advance_motions(1.0)
	_assert_vec(u.global_position, Vector3(-0.5, 0, 0), "abs: move3 lands at -0.5 tile")
	vm.queue_free()


# Bit-exact reproduction of FUN_80146940's per-frame committed integer position
# for one axis (8.8 fixed point, muldiv_64 truncate-toward-zero, +0xff negative
# fixup, unsigned >>8). Returns the written integer opcode-unit. Used to pin the
# runtime float curve against the captured hardware traces.
static func _trunc_div(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if ((a < 0) == (b < 0)) else -q


static func _muldiv(a: int, b: int, c: int) -> int:
	return _trunc_div(a * b, c)


static func _rom_curve_fixed(easing: int, weight: int, t: int, time_t: int, start_u: int, tgt_u: int) -> int:
	var sf := start_u << 8
	var df := (tgt_u - start_u) << 8
	var w := weight
	var cw := 16 - w
	var pos := 0
	match easing:
		1:
			var t1 := _muldiv(df * 2 * w + df * cw + df * cw, t, time_t << 5)
			var t2 := _muldiv(df * 2 * w, (time_t - t) * t, time_t * (time_t << 5))
			pos = t1 + t2 + sf
		2:
			var hh := time_t / 2
			if hh == 0:
				hh = 1
			if 2 * t < time_t:
				var i8 := _muldiv(df * 2 * w, t, hh)
				i8 = _muldiv(i8 + df * cw * 2, t, hh << 6)
				pos = i8 + sf
			else:
				var u := t - hh
				var i5 := _muldiv(df * 2 * w, hh - u, hh)
				var i10 := _muldiv(df * 2 * w + i5 + df * cw * 2, u, hh << 6)
				pos = i10 + sf + _trunc_div(df, 2)
		3:
			var i8 := _muldiv(df * 2 * w, t, time_t)
			i8 = _muldiv(i8 + df * cw * 2, t, time_t << 5)
			pos = i8 + sf
		_:
			pos = sf + _muldiv(df, t, time_t)
	var p := pos + (0xff if pos < 0 else 0)
	return (p & 0xFFFFFFFF) >> 8


# Pin the runtime float curve to the live PSX per-frame position traces captured
# in research/.../scripts/probe_sprite_move_{trace,curves}.py. Two checks per
# trace: (a) the integer ROM reference reproduces it bit-exact (locks the
# derivation), and (b) the runtime float `ScenarioMotion.curve` is within 1
# opcode-unit (sub-pixel; pure truncation rounding) of every captured frame.
func _test_curve_matches_hardware_trace() -> void:
	var vm := _make_vm()
	# Priest {3B}: unit 0x13, 0→28 over T=40, Type 0, weight 1 (orbonne_priest_walk).
	var priest := PackedInt32Array([0, 1, 2, 2, 3, 4, 4, 5, 6, 7, 7, 8, 9, 9, 10, 11,
		11, 12, 13, 14, 14, 15, 16, 16, 17, 18, 18, 19, 20, 21, 21, 22, 23, 23, 24,
		25, 25, 26, 27])  # frames t=1..39
	# Type 1 weight 16 (operand-patched), same 0→28/T=40 move (ease-out).
	var t1w16 := PackedInt32Array([1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16,
		17, 17, 18, 19, 20, 21, 21, 22, 22, 23, 24, 24, 25, 25, 25, 26, 26, 26, 27,
		27, 27, 27, 27, 27, 27])
	_assert_curve_trace(vm, 0, 1, priest, "trace: priest Type0 w1")
	_assert_curve_trace(vm, 1, 16, t1w16, "trace: Type1 w16 (ease-out)")
	vm.queue_free()


func _assert_curve_trace(vm: Object, easing: int, weight: int, hw: PackedInt32Array, tag: String) -> void:
	var time_t := 40
	var ref_exact := true
	var float_ok := true
	var worst := 0.0
	for i in hw.size():
		var t := i + 1
		# (a) integer ROM reference must match hardware exactly.
		if _rom_curve_fixed(easing, weight, t, time_t, 0, 28) != hw[i]:
			ref_exact = false
		# (b) runtime float curve within 1 opcode-unit of hardware.
		var fpred: float = ScenarioMotion.curve(easing, float(t) / float(time_t), weight) * 28.0
		var err: float = absf(fpred - float(hw[i]))
		worst = maxf(worst, err)
		if err > 1.0:
			float_ok = false
	_assert(ref_exact, "%s: integer ROM reference reproduces trace bit-exact" % tag)
	_assert(float_ok, "%s: float curve within 1u of trace (worst=%.3f)" % [tag, worst])


# Easing curves per Type at the midpoint, parameterised by `weight`. Values are
# the verified ROM closed forms (FUN_80146940). `weight` dominates: the baked
# scenario-1 data is all weight=1 (near-linear); weight=16 gives the strong
# quadratic curves the prior impl hard-coded.
func _test_easing_curves() -> void:
	var vm := _make_vm()
	# weight=1 (the baked case): every non-linear curve is barely off linear.
	_assert_near(ScenarioMotion.curve(0, 0.5, 1), 0.5, "ease: linear @0.5")
	_assert_near(ScenarioMotion.curve(1, 0.5, 1), 0.515625, "ease: type1 w1 @0.5")
	_assert_near(ScenarioMotion.curve(2, 0.5, 1), 0.5, "ease: type2 w1 @0.5")
	_assert_near(ScenarioMotion.curve(3, 0.5, 1), 0.484375, "ease: type3 w1 @0.5")
	# weight=16 (strong curves): type1 → ease-out 1-(1-f)², type3 → ease-in f².
	_assert_near(ScenarioMotion.curve(1, 0.5, 16), 0.75, "ease: type1 w16 @0.5 (ease-out)")
	_assert_near(ScenarioMotion.curve(2, 0.5, 16), 0.5, "ease: type2 w16 @0.5 (in-out)")
	_assert_near(ScenarioMotion.curve(3, 0.5, 16), 0.25, "ease: type3 w16 @0.5 (ease-in)")
	_assert_near(ScenarioMotion.curve(3, 0.25, 16), 0.0625, "ease: type3 w16 @0.25 (=0.25²)")
	# weight=0 collapses every curve to linear.
	for ty in [1, 2, 3]:
		_assert_near(ScenarioMotion.curve(ty, 0.3, 0), 0.3, "ease: type %d w0 = linear" % ty)
	# Endpoints are pinned for every curve at both weight extremes.
	for ty in [0, 1, 2, 3]:
		for w in [1, 16]:
			_assert_near(ScenarioMotion.curve(ty, 0.0, w), 0.0, "ease: type %d w%d @0" % [ty, w])
			_assert_near(ScenarioMotion.curve(ty, 1.0, w), 1.0, "ease: type %d w%d @1" % [ty, w])
	vm.queue_free()


# {6F} Wait Sprite Move now arms a `motion_done` PREDICATE barrier (ADR-0055),
# not a tick countdown: the context holds while the move is in-flight and releases
# the instant it completes (the live decode stream is `3b 6f` for the same unit).
func _test_wait_blocks() -> void:
	var vm := _make_vm()
	_add_unit(vm, 0x13, Vector3.ZERO)
	vm._op_sprite_move(_sprite_move_inst(0x13, 28, 0, 0, 0, 40))
	vm._op_wait_sprite_move(_wait_inst(0x13))
	_assert(vm._current_ctx.wait_until.is_valid(),
		"wait: blocks the caller (motion_done predicate armed)")
	# Predicate holds mid-move, releases once the move reaches its target.
	_assert(vm._current_ctx.wait_until.call() == false, "wait: predicate holds mid-move")
	vm._advance_motions(40.0 / 60.0)
	_assert(vm._current_ctx.wait_until.call() == true, "wait: predicate releases at target")

	# Wait on a unit with no active move → no block (predicate never armed).
	vm._current_ctx.wait_until = Callable()
	vm._op_wait_sprite_move(_wait_inst(0x99))
	_assert(not vm._current_ctx.wait_until.is_valid(), "wait: no active move → no block")
	vm.queue_free()


# The predicate barrier inherits `_arm_wait_until`'s watchdog, which the old
# tick-countdown waits lacked — so a motion wait passes a DURATION-DERIVED budget
# (ADR-0055): floored at the 600-tick (10 s) default for short motions/rotate, but
# extended for a legitimately long slide so it isn't clipped mid-flight.
func _test_motion_watchdog_is_duration_derived() -> void:
	var vm := _make_vm()
	# No motion for this uid → default 600-tick ceiling (also the rotate fallback).
	_assert(vm._motion_watchdog(0x99) == 600, "watchdog: no motion → 600-tick default")
	# A 20 s motion (1200 ticks) extends the budget well past the default.
	var m := ScenarioMotion.new()
	m.dur_s = 20.0
	vm.actor(0x20).motion = m
	_assert(vm._motion_watchdog(0x20) > 600, "watchdog: long motion extends past 600")
	vm.queue_free()


# Concurrent per-unit moves (orbonne_three_actors_walk_in): independent records
# that advance together.
func _test_concurrent() -> void:
	var vm := _make_vm()
	var a := _add_unit(vm, 0x02, Vector3.ZERO)
	var b := _add_unit(vm, 0x17, Vector3(10, 0, 0))
	vm._op_sprite_move(_sprite_move_inst(0x02, 28, 0, 0, 0, 60))
	# +Y is the PSX DEPTH axis; ADR-0052 mirrors it, so a +Y delta moves the unit
	# toward -Z in Godot (more PSX-depth = less Godot-Z). See _start_sprite_move.
	vm._op_sprite_move(_sprite_move_inst(0x17, 0, 0, 28, 0, 60))  # +Y(depth) → -Z
	_assert(vm.active_motion_count() == 2, "concurrent: two records coexist")
	vm._advance_motions(1.0)  # 60 frames = 1.0s → both complete
	_assert_vec(a.global_position, Vector3(1, 0, 0), "concurrent: unit A moved +X")
	_assert_vec(b.global_position, Vector3(10, 0, -1), "concurrent: unit B moved +Y depth → -Z")
	_assert(vm.active_motion_count() == 0, "concurrent: both cleared")
	vm.queue_free()


# ADR-0052 axis mapping for a Sprite Move RELATIVE delta (the audit guard): the
# 180°-about-X rotation negates the two flipped axes, so from a single +28 (=1
# tile) on each operand axis, the unit must move +X, -Y (height: Y-down→Y-up),
# and -Z (depth mirror). A regression on any axis sign fails here. Operand arg
# order is (dx=+X, dz=+Z height, dy=+Y depth).
func _test_sprite_move_axis_mapping() -> void:
	var vm := _make_vm()
	var ux := _add_unit(vm, 0x40, Vector3.ZERO)
	var uy := _add_unit(vm, 0x41, Vector3.ZERO)
	var uz := _add_unit(vm, 0x42, Vector3.ZERO)
	vm._op_sprite_move(_sprite_move_inst(0x40, 28, 0, 0, 0, 1))   # +X lateral
	vm._op_sprite_move(_sprite_move_inst(0x41, 0, 28, 0, 0, 1))   # +Z height
	vm._op_sprite_move(_sprite_move_inst(0x42, 0, 0, 28, 0, 1))   # +Y depth
	vm._advance_motions(1.0)
	_assert_vec(ux.global_position, Vector3(1, 0, 0), "axis: +X → world +X")
	_assert_vec(uy.global_position, Vector3(0, -1, 0), "axis: +Z height → world -Y")
	_assert_vec(uz.global_position, Vector3(0, 0, -1), "axis: +Y depth → world -Z (mirror)")
	vm.queue_free()


# {6E} Beta: duration is 4·distance / speed frames (the ROM's `sqrt(Σ Δ²·0x10)`
# puts a ×4 over the raw distance). dx=56 (2 tiles, |Δpsx|=56), speed=28 →
# 4·56/28 = 8 frames → ~0.133s.
func _test_beta_speed() -> void:
	var vm := _make_vm()
	var u := _add_unit(vm, 0x05, Vector3.ZERO)
	vm._op_sprite_move_beta(_beta_inst(0x05, 56, 0, 0, 0, 28))
	var rec: ScenarioMotion = _motion_of(vm, 0x05)
	_assert_vec(rec.target, Vector3(2, 0, 0), "beta: target = start + 2 tiles X")
	_assert_near(float(rec.dur_s), 8.0 / 60.0, "beta: dur = 4·dist/speed/60")
	vm._advance_motions(1.0)
	_assert_vec(u.global_position, Vector3(2, 0, 0), "beta: reaches target")
	vm.queue_free()


func _add_walk_unit(vm: Object, uid: int, pos: Vector3) -> Node3D:
	var u := MockWalkUnit.new()
	add_child(u)
	u.global_position = pos
	vm.units_by_id[uid] = u
	return u


# {28} Walk To: grid relocation to the seat tile centre (X+0.5, Y+0.5), advancing
# the unit's home; {29} Wait Walk blocks the caller until it arrives. This is the
# opcode whose missing impl stranded the chapel walk-ins at the entry column
# (HANDOFF_unit_tile_alignment.md, 2026-06-28).
func _test_walk_to() -> void:
	var vm := _make_vm()
	_install_map(vm)
	# Start at tile (1,4) centre; walk to seat (3,4).
	var u := _add_walk_unit(vm, 0x17, Vector3(1.5, _ground_y, 4.5))
	vm._op_walk_to(_walk_to_inst(0x17, 3, 4, 8))
	_assert(_motion_of(vm, 0x17) != null, "walk: record armed")
	var rec = _motion_of(vm, 0x17)
	_assert_vec(_walk_endpoint_of(vm, 0x17), Vector3(3.5, _ground_y, 4.5),
		"walk: endpoint = seat tile centre")
	# Faces the travel heading: +X dominant → NORTH (0). Assert the ANGLE too: NORTH
	# is also the double's never-faced default, so the cardinal arm alone passes on a
	# walk that writes no facing at all (#752).
	_assert(u.facing_angle == 0xC00, "walk: writes the +X orientation angle 0xC00")
	_assert(u.facing_direction == 0, "walk: faces +X travel (NORTH)")
	# {29} Wait Walk arms the same motion_done predicate barrier (ADR-0055).
	vm._op_wait_walk(_wait_walk_inst(0x17))
	_assert(vm._current_ctx.wait_until.is_valid(), "walk: Wait Walk blocks the caller (predicate)")
	# Drains to the seat and clears the record.
	vm._advance_motions(rec.dur_s)
	_assert_vec(u.global_position, Vector3(3.5, _ground_y, 4.5), "walk: reaches seat")
	_assert(_motion_of(vm, 0x17) == null, "walk: record cleared at arrival")
	# A later Sprite Move re-captures home from the seat (offset 0 there): the walk
	# cleared the actor's captured home, so has_home is false.
	_assert(not vm.actor(0x17).has_home,
		"walk: move-home reset so next Sprite Move re-captures the seat")
	# Wait Walk on a unit with no active walk → no block (predicate never armed).
	vm._current_ctx.wait_until = Callable()
	vm._op_wait_walk(_wait_walk_inst(0x99))
	_assert(not vm._current_ctx.wait_until.is_valid(), "walk: no active walk → no block")
	vm.queue_free()


# ADR-0057 consume-raw GUARD (the depth-flip moved HOME to the parser, #141):
# the scenario chunk now arrives Godot-native (extract_event pre-flips every
# placement Event-Y row), so the VM consumes Walk To rows RAW — no runtime
# mirror. The operands below are the chunk's PRE-FLIPPED rows (what the parser
# emits for the MAP062 chapel, size_z=10: Ramza's raw row 3 → 6, etc.), and the
# units must land on exactly those rows. Ramza (chunk row 6) is still the canary
# — a resurrected runtime flip would strand him at 10-1-6=3 (the "Ramza in the
# background" report). The chirality itself is now guarded parser-side in
# tools/test_extract_event.py; the flip math lives in PsxNumTest.
func _test_walk_to_consumes_preflipped_rows() -> void:
	var vm := _make_vm()
	vm.map_size_z = 10
	_install_map(vm)
	var z_for := func(row: int) -> float: return float(row) + 0.5
	# (chunk uid, seat X, PRE-FLIPPED seat row, speed, expected tile-centre world)
	var cases := [
		[0x17, 3, 5, 8, Vector3(3.5, _ground_y, z_for.call(5))],  # chunk 23 Gafgarion (raw 4 → 5)
		[0x02, 2, 6, 8, Vector3(2.5, _ground_y, z_for.call(6))],  # chunk  2 Ramza     (raw 3 → 6)
		[0x83, 2, 4, 5, Vector3(2.5, _ground_y, z_for.call(4))],  # chunk 131 squire   (raw 5 → 4)
	]
	for c in cases:
		var uid: int = c[0]
		# Unit starts at its WARP tile (warp row == walk row for these, so the
		# walk only advances X — exactly as on PSX).
		var u := _add_walk_unit(vm, uid, Vector3(1.5, _ground_y, z_for.call(c[2])))
		vm._op_walk_to(_walk_to_inst(uid, c[1], c[2], c[3]))
		var rec = _motion_of(vm, uid)
		vm._advance_motions(rec.dur_s)
		_assert_vec(u.global_position, c[4],
			"consume-raw: chunk uid 0x%02X lands on the pre-flipped seat" % uid)
	vm.queue_free()


# {28} Walk To onto an OCCUPIED tile: FFT's event pathfinder (EventPathfinder,
# port of ROM FUN_8017813c) refuses to stack and halts on the adjacent free tile.
# Synthetic case (the scenario-1 chapel never actually occupies a Walk To target,
# so the path-through is behaviour-neutral there): a walker at grid (5,5) Walk To
# Units do NOT block the event {28} Walk To (ROM a0=3 terrain-only map build —
# EventPathfinder header; live: scn6 instr 334 Agrias walks through Delita). A
# Walk To to (6,4) with another unit STANDING on (6,4) still routes straight
# through and lands EXACTLY on (6,4), stacked on the occupant — the pathfinder
# never sees the unit. (Was the old occupancy stop-short model, now corrected.)
func _test_walk_to_walks_through_occupant() -> void:
	var vm := _make_vm()
	_install_map(vm)
	var ovelia := _add_walk_unit(vm, 0x0C, Vector3(5.5, _ground_y, 5.5))   # grid (5,5)
	var _occupant := _add_walk_unit(vm, 0x00, Vector3(6.5, _ground_y, 4.5))  # grid (6,4) = target
	vm._op_walk_to(_walk_to_inst(0x0C, 6, 4, 4))
	_assert(_motion_of(vm, 0x0C) != null, "walkthru: walk armed")
	var rec = _motion_of(vm, 0x0C)
	# Endpoint is the literal target (6,4) despite the occupant standing there.
	_assert_vec(_walk_endpoint_of(vm, 0x0C), Vector3(6.5, _ground_y, 4.5),
		"walkthru: endpoint = target (6,4) centre")
	vm._advance_motions(rec.dur_s)
	_assert_vec(ovelia.global_position, Vector3(6.5, _ground_y, 4.5),
		"walkthru: Ovelia lands ON the target (6,4)")
	vm.queue_free()


# The dialogue box anchor fix (decode §9.6/§9.7): PSX projects the speaker's BASE
# SVECTOR (`unit+0x40` = tile), not the drawn sprite at `base + 0x60`. Simon's
# carry pose Sprite-Moves his sprite ~64u left of his tile, and the authored
# `X58/fineX60` operands are pose-compensation tuned against that displacement.
# `ScenarioVM.sprite_move_base_position()` is the datum the box pool anchors on;
# `ScenarioDialogueBoxPool._place_box_on_unit` slides the ROOT-B drawn-sprite
# anchor back to the base by subtracting (work − base). This test pins the
# accessor's semantics and the slide arithmetic so a regression can't silently
# re-strand the tail.
func _test_base_position_for_dialogue_box() -> void:
	var vm := _make_vm()
	# 1. Never-moved unit: base == its current world position (offset 0). The box
	#    anchor slide (work − base) is then ZERO — non-displaced boxes are untouched.
	var still := _add_unit(vm, 0x40, Vector3(2, 0, 3))
	_assert_vec(vm.sprite_move_base_position(still), Vector3(2, 0, 3),
		"base: never-moved unit → base == current position")
	_assert_vec(still.global_position - vm.sprite_move_base_position(still), Vector3.ZERO,
		"base: never-moved unit → box anchor slide is zero (ROOT-B preserved)")

	# 2. Pose-displaced unit (Simon's carry): Sprite Move unit 0x13 by −64u in X
	#    (the scenario_1 #273 `+X=65472` = −64, ×1 tile via the 28-unit divisor is
	#    a −2.285-tile lateral slide). After the move completes, the unit node sits
	#    at the WORK position (base+offset), but base_position() still returns the
	#    captured tile — that split is exactly what the box needs.
	var simon := _add_unit(vm, 0x13, Vector3(5, 0, 4))
	vm._op_sprite_move(_sprite_move_inst(0x13, -64, 0, 0, 0, 10))
	var rec: ScenarioMotion = _motion_of(vm, 0x13)
	vm._advance_motions(float(rec.dur_s))  # run the move to completion
	var base: Vector3 = vm.sprite_move_base_position(simon)
	_assert_vec(base, Vector3(5, 0, 4), "base: moved unit → base stays the pre-move tile")
	# The unit is now displaced left; the drawn sprite (work) is NOT the base.
	_assert(simon.global_position.distance_to(base) > 1.0,
		"base: moved unit → drawn sprite (work) is displaced from base")
	# The box anchor slide recovers exactly the pose offset, so the box re-anchors
	# on the tile the operands were authored against (undoing ROOT-B's double-comp).
	var slide: Vector3 = simon.global_position - base
	_assert_near(slide.x, -64.0 / 28.0, "base: anchor slide.x == pose offset (−64u = −2.285 tiles)")
	vm.queue_free()
