extends Node
## Unit tests for [ScenarioPathMotion] — the world-space ADAPTER over the ROM's own
## `{28} Walk To` stepper. Pure logic: no scene, no VM, no nodes.
##
## 🔴 **THIS FILE DOES NOT TEST THE WALK.** The motion is decided inside
## `ExMateriaBattlefield.RomWalkStepper`, and it is scored where it is decided —
## `addons/exmateria_battlefield/tests/RomWalkStepperTest.gd` replays thirteen live
## PSX captures against it at **43 510 of 43 510 field-frames**. Restating any of
## that here would be a second, weaker copy of a measurement that already exists.
##
## What is genuinely this class's, and therefore what is asserted below:
##
##   * the COORDINATE map — render units (28 per tile edge, 12 per elevation level,
##     Y negative up) to Godot world metres, anchored on the caller's own start
##     waypoint;
##   * the CLOCK — `advance(dt)` seconds against ROM frames, the `max_dur_s` clamp,
##     `dur_s`, and interpolation for a tick rate that is not 60 Hz;
##   * the API `ScenarioActor`/`ScenarioVM`/`ScenarioApply` drive — `position`,
##     `is_done`, `snap_to_end`, `poll_facing_change`, `waypoints`;
##   * and THREE structural facts that would still hold if the adapter had quietly
##     kept modelling the walk itself, so they are the ones that say it did not:
##     the cadence is an integer recurrence and not `224/Speed`, a descent is an
##     accelerating arc and not a lerp, and a climb OVERSHOOTS its destination.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioPathMotionTest.tscn

## World Y per elevation level — the exporter's rule, `12 / 28` PSX units per tile
## (`MapConstants.PSX_UNITS_PER_HALF_STEP / PSX_UNITS_PER_TILE`). The `0.25 *
## TILE_SCALE` = 0.4464 this used to be is the vertex-less FALLBACK's scale, which
## ADR-0218 dec. 5 records as disagreeing with the 0.4286 every shipped
## `terrain.json` bakes.
const LEVEL: float = 12.0 / 28.0

## ROM frames one tile of GROUND costs, by Speed — measured, not predicted.
##
## 🔴 NOT `224/Speed`. That is an approximation of an integer recurrence: a cardinal
## axis normalises to **4095, not 4096**, and the launch gate QUANTISES the position
## three quarters of the way across each tile (`FUN_8006C94C`), throwing the
## sub-unit remainder away once per step. Speed 16 costs 15 frames a tile and not
## 14; Speed 8 costs 30 and not 28. The old model asserted the approximation, and
## `ScenarioApplyTest` asserted it too.
const FRAMES_PER_TILE := {8.0: 30, 10.0: 23, 16.0: 15, 3.5: 66, 32.0: 8}

## Arms that ran to COMPLETION, by name.
##
## 🔴 A GDScript runtime error aborts only its ENCLOSING function. An arm that dies
## part-way — on a malformed fixture, a bad index, a renamed member — contributes
## NO failures, so `_ready` resumes, the counters still read `N passed, 0 failed`,
## and this file prints **[PASS]** over a test that never ran. That is strictly
## worse than a hang: a hang is scored HUNG and somebody looks at it; a false green
## is believed, and its assertion count goes into a commit message as evidence.
##
## The pattern is `BattlefieldProvidesTest`'s, four files away in addons/exmateria_battlefield/tests.
var _completed := {}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_cadence_is_an_integer_recurrence_not_224_over_speed()
	_test_endpoint_is_exactly_the_last_waypoint()
	_test_flat_walk_has_no_vertical_motion()
	_test_descent_is_an_accelerating_arc_not_a_lerp()
	_test_climb_overshoots_its_destination()
	_test_elevation_scale_is_one_level_per_12_of_28()
	_test_turning_route_reports_one_facing_per_turn()
	_test_walk_stays_on_the_route_polyline()
	_test_diagonal_fallback_is_decomposed_into_cardinal_steps()
	_test_sub_frame_dt_interpolates()
	_test_max_dur_clamp()
	_test_snap_to_end()
	_test_degenerate_single_waypoint()
	_test_waypoints_are_preserved_verbatim()
	_test_configure_rom_recovers_what_a_polyline_cannot_state()
	_test_the_wired_path_lands_where_the_wire_did()
	_test_psx_rows_mirrors_z_and_leaves_x_alone()

	print("\n=== ScenarioPathMotionTest: %d passed, %d failed, %d/17 arms reported ==="
		% [_passed, _failed, _completed.size()])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioPathMotionTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != 17:
		# See `_completed`: an aborted arm adds no failures, so the line above is
		# clean while most of this file did not run.
		print("[FAIL] ScenarioPathMotionTest: only %d of 17 arms ran to completion — ran %s"
			% [_completed.size(), str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioPathMotionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioPathMotionTest")
		get_tree().quit(0)


# --- helpers -----------------------------------------------------------------

func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _approx(got: float, want: float, name: String, eps: float = 1e-4) -> void:
	if absf(got - want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _veq(got: Vector3, want: Vector3, name: String, eps: float = 1e-4) -> void:
	if got.distance_to(want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


## Build + configure a motion (60 Hz clock, no clamp). `speed` is the `{28}` Speed
## operand and is FRACTIONAL — 8.8 fixed point, per `ScenarioDecode.walk_to_speed`.
func _make(pts: Array, speed: float = 16.0, max_dur_s: float = INF) -> ScenarioPathMotion:
	var m := ScenarioPathMotion.new()
	m.configure(pts, speed, 60.0, max_dur_s)
	return m


## A straight `+X` route of `n` tiles on flat ground, starting at `(0.5, 0, 0.5)`.
func _straight(n: int, y: float = 0.0) -> Array:
	var pts: Array = []
	for i in n + 1:
		pts.append(Vector3(0.5 + float(i), y, 0.5))
	return pts


## Step `frames` whole ROM frames (dt = 1/60 s each), collecting the position after
## each one.
func _run_frames(m: ScenarioPathMotion, frames: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for _i in range(frames):
		m.advance(1.0 / 60.0)
		out.append(m.position())
	return out


# --- tests -------------------------------------------------------------------

## The whole walk costs `tiles × per_tile + 1`: the ROM's per-tile recurrence, plus
## the ARRIVAL frame, in which the running handler snaps to the destination centre
## and the spent route buffer ends the walk.
func _test_cadence_is_an_integer_recurrence_not_224_over_speed() -> void:
	for speed: float in FRAMES_PER_TILE:
		var per_tile: int = FRAMES_PER_TILE[speed]
		for tiles in [1, 2, 3]:
			var m := _make(_straight(tiles), speed)
			_eq(int(m.total_frames), tiles * per_tile + 1,
				"Speed %.1f, %d tile(s): %d frames" % [speed, tiles, tiles * per_tile + 1])
		var m1 := _make(_straight(2), speed)
		_approx(m1.dur_s, float(2 * per_tile + 1) / 60.0, "Speed %.1f: dur_s" % speed)
		# 🔴 The point of the table: the old `224/Speed` model is WRONG at every
		# speed on it, and low by a whole frame per tile or more.
		_true(per_tile > int(224.0 / speed),
			"Speed %.1f: %d f/tile exceeds 224/Speed = %.1f" % [speed, per_tile, 224.0 / speed])

	# The Speed operand is 8.8 fixed point, so 3.5 is a real operating point and not
	# a rounding of 3 or 4 — five of scenario 29's own `{28}`s are fractional.
	_true(FRAMES_PER_TILE[3.5] != FRAMES_PER_TILE[8.0], "Speed 3.5 is its own cadence")
	var frac := _make(_straight(1), 3.5)
	var whole := _make(_straight(1), 4.0)
	_true(frac.total_frames != whole.total_frames, "Speed 3.5 differs from Speed 4")
	_completed["_test_cadence_is_an_integer_recurrence_not_224_over_speed"] = true



## Whatever the walk did in between, it settles exactly on the seat it was sent to.
func _test_endpoint_is_exactly_the_last_waypoint() -> void:
	for speed: float in FRAMES_PER_TILE:
		var pts := _straight(3)
		var m := _make(pts, speed)
		_run_frames(m, int(m.total_frames))
		_true(m.is_done(), "Speed %.1f: done after total_frames" % speed)
		_veq(m.position(), pts[pts.size() - 1], "Speed %.1f: ends on the last waypoint" % speed)

	# ... and across a level change in each direction.
	var down := [Vector3(0.5, 0, 0.5), Vector3(1.5, -LEVEL, 0.5), Vector3(2.5, -2.0 * LEVEL, 0.5)]
	var md := _make(down)
	_run_frames(md, int(md.total_frames))
	_veq(md.position(), down[2], "descending staircase ends on its last tile")
	var up := [Vector3(0.5, 0, 0.5), Vector3(1.5, LEVEL, 0.5), Vector3(2.5, 2.0 * LEVEL, 0.5)]
	var mu := _make(up)
	_run_frames(mu, int(mu.total_frames))
	_veq(mu.position(), up[2], "climbing staircase ends on its last tile")
	_completed["_test_endpoint_is_exactly_the_last_waypoint"] = true



func _test_flat_walk_has_no_vertical_motion() -> void:
	var m := _make(_straight(3), 16.0)
	var moved: bool = false
	for p in _run_frames(m, int(m.total_frames)):
		if absf(p.y) > 1e-6:
			moved = true
	_true(not moved, "flat route never leaves Y = 0")
	_completed["_test_flat_walk_has_no_vertical_motion"] = true



## A descent is GRAVITY, not a lerp: the per-frame drop grows. The old model called
## this `VMode.FALL` and armed it per tile from the tile's elevation delta; the ROM
## has no such case — the walk states integrate the one gravity themselves.
func _test_descent_is_an_accelerating_arc_not_a_lerp() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, -LEVEL, 0.5)]
	var m := _make(pts, 16.0)
	var track := _run_frames(m, int(m.total_frames))
	var drops: Array[float] = []
	var prev: float = 0.0
	for p in track:
		var d: float = prev - p.y
		if d > 1e-6:
			drops.append(d)
		prev = p.y
	_true(drops.size() >= 3, "the descent has airborne frames (%d)" % drops.size())
	_true(drops[drops.size() - 1] > drops[0],
		"the drop ACCELERATES: last %.5f > first %.5f" % [drops[drops.size() - 1], drops[0]])
	# A lerp would divide the level evenly across its frames; this does not.
	var even: float = LEVEL / float(drops.size())
	_true(absf(drops[0] - even) > 1e-3, "the first drop is not the even share a lerp would take")
	_veq(m.position(), pts[1], "the descent lands exactly on the lower tile")
	_completed["_test_descent_is_an_accelerating_arc_not_a_lerp"] = true



## A climb is the ROM's HOP — launched by `SquareRoot0`, decelerated by the same
## gravity — so it rises ABOVE the destination surface and settles back onto it. A
## ramp, a lerp or any monotone model cannot do that, which is what makes this the
## assertion that the hop is real.
func _test_climb_overshoots_its_destination() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, LEVEL, 0.5)]
	var m := _make(pts, 16.0)
	var peak: float = -INF
	for p in _run_frames(m, int(m.total_frames)):
		peak = maxf(peak, p.y)
	_true(peak > LEVEL + 1e-6, "the hop peaks ABOVE the destination (%.5f > %.5f)" % [peak, LEVEL])
	_approx(peak, 13.0 / 28.0, "the peak is one render unit over the surface")
	_veq(m.position(), pts[1], "and settles exactly onto it")
	_completed["_test_climb_overshoots_its_destination"] = true



## One elevation level is exactly `12/28` in world Y, in BOTH directions and over
## multiple levels. This is the coordinate map, and it is the one thing a
## sign or scale error would show up in.
func _test_elevation_scale_is_one_level_per_12_of_28() -> void:
	for levels in [1, 2, 3]:
		for dir in [1.0, -1.0]:
			var dy: float = dir * float(levels) * LEVEL
			var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, dy, 0.5)]
			var m := _make(pts, 16.0)
			_run_frames(m, int(m.total_frames))
			_approx(m.position().y, dy, "%+d level(s) = %+.5f world Y" % [int(dir) * levels, dy])
	_completed["_test_elevation_scale_is_one_level_per_12_of_28"] = true



## A turn reports its heading ONCE, as a 12-bit orientation angle; a straight route
## reports its own heading once and then -1 forever.
func _test_turning_route_reports_one_facing_per_turn() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5), Vector3(1.5, 0, 1.5)]
	var m := _make(pts, 16.0)
	var reports: Array[int] = []
	for _i in range(int(m.total_frames)):
		m.advance(1.0 / 60.0)
		var f := m.poll_facing_change()
		if f >= 0:
			reports.append(f)
	_eq(reports.size(), 2, "a one-corner route reports two headings")
	_eq(reports[0], ExMateriaPlatform.PsxNum.heading_to_12bit(1.0, 0.0), "first leg faces +X")
	_eq(reports[1], ExMateriaPlatform.PsxNum.heading_to_12bit(0.0, 1.0), "second leg faces +Z")

	var straight := _make(_straight(3), 16.0)
	var n: int = 0
	for _i in range(int(straight.total_frames)):
		straight.advance(1.0 / 60.0)
		if straight.poll_facing_change() >= 0:
			n += 1
	_eq(n, 1, "a straight route reports exactly one heading")
	_completed["_test_turning_route_reports_one_facing_per_turn"] = true



## The unit follows the route polyline: it never leaves the corridor its own
## waypoints describe, corner included.
func _test_walk_stays_on_the_route_polyline() -> void:
	var m := _make([Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5), Vector3(1.5, 0, 1.5)], 16.0)
	var off: bool = false
	for p in _run_frames(m, int(m.total_frames)):
		var on_leg1: bool = absf(p.z - 0.5) < 1e-4 and p.x >= 0.5 - 1e-4 and p.x <= 1.5 + 1e-4
		var on_leg2: bool = absf(p.x - 1.5) < 1e-4 and p.z >= 0.5 - 1e-4 and p.z <= 1.5 + 1e-4
		if not (on_leg1 or on_leg2):
			off = true
	_true(not off, "every frame lies on one of the two legs")
	_completed["_test_walk_stays_on_the_route_polyline"] = true



## The coarse `[start, target]` fallback polyline can be diagonal, and the ROM's
## route buffer has no diagonal to encode it with. It is decomposed X then Z, so
## the walk still arrives — as cardinal steps, which is the only thing the stepper
## can be handed.
func _test_diagonal_fallback_is_decomposed_into_cardinal_steps() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(2.5, 0, 1.5)]
	var m := _make(pts, 16.0)
	_eq(int(m.total_frames), 3 * FRAMES_PER_TILE[16.0] + 1, "2 in X + 1 in Z = 3 cardinal steps")
	_run_frames(m, int(m.total_frames))
	_veq(m.position(), pts[1], "the diagonal fallback still reaches its target")
	_completed["_test_diagonal_fallback_is_decomposed_into_cardinal_steps"] = true



## A clock that is not 60 Hz still reads a smooth path: `position()` interpolates
## between ROM frames rather than returning a staircase.
func _test_sub_frame_dt_interpolates() -> void:
	var m := _make(_straight(2), 16.0)
	var whole := _make(_straight(2), 16.0)
	whole.advance(1.0 / 60.0)
	whole.advance(1.0 / 60.0)
	var f1 := whole.position()
	m.advance(1.0 / 60.0)
	var at1 := m.position()
	m.advance(1.0 / 120.0)
	var half := m.position()
	m.advance(1.0 / 120.0)
	_veq(m.position(), f1, "two half-frames land on the whole frame")
	_true(half.distance_to(at1) <= f1.distance_to(at1) + 1e-6
			and half.distance_to(f1) <= f1.distance_to(at1) + 1e-6,
		"the half-frame sample lies between the two frames")
	_completed["_test_sub_frame_dt_interpolates"] = true



func _test_max_dur_clamp() -> void:
	var full := _make(_straight(3), 16.0)
	var clamped := _make(_straight(3), 16.0, 0.25)
	_approx(clamped.dur_s, 0.25, "duration clamped to max_dur_s")
	_eq(int(clamped.total_frames), 15, "0.25 s at 60 Hz = 15 ROM frames")
	_true(clamped.total_frames < full.total_frames, "the clamp actually shortened it")
	_run_frames(clamped, 15)
	_true(clamped.is_done(), "a clamped walk finishes at the clamp")
	# ⚠️ A clamp stops the walk EARLY, so it does NOT end on the seat. The seat is
	# latched by `ScenarioWorld.seat_unit_cell` when the walk is armed, not by
	# arriving — which is exactly why that latch is on arming (ADR-0219 dec. 6).
	_true(clamped.position().distance_to(Vector3(3.5, 0, 0.5)) > 0.1,
		"a clamped walk stops short of the seat, and the seat latch does not depend on it")
	# But a BURN-THROUGH is asking for the end state, not for where the clamp fell.
	# `_drain_motions_to_target` calls `snap_to_end` to fast-forward a scenario, and a
	# unit left standing wherever a play-through clamp happened to cut is not the end
	# state of anything. The model this replaced put it on the last waypoint too.
	clamped.snap_to_end()
	_veq(clamped.position(), Vector3(3.5, 0, 0.5),
		"snap_to_end reaches the seat even through a clamp")
	_completed["_test_max_dur_clamp"] = true



func _test_snap_to_end() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5), Vector3(1.5, 0, 1.5)]
	var m := _make(pts, 16.0)
	m.advance(1.0 / 60.0)
	m.poll_facing_change()
	m.snap_to_end()
	_true(m.is_done(), "snap_to_end -> is_done")
	_veq(m.position(), pts[2], "snap_to_end -> position == the last waypoint")
	# A burnt-through walk still ends facing the way it walked, or the unit is left
	# pointing down the FIRST leg of a route it has already finished.
	_eq(m.poll_facing_change(), ExMateriaPlatform.PsxNum.heading_to_12bit(0.0, 1.0),
		"snap_to_end drains the turn it skipped")
	_completed["_test_snap_to_end"] = true



func _test_degenerate_single_waypoint() -> void:
	var m := _make([Vector3(2.5, 1.0, 3.5)], 16.0)
	_eq(m.total_frames, 0.0, "one waypoint: no frames")
	_approx(m.dur_s, 0.0, "one waypoint: no duration")
	_true(m.is_done(), "one waypoint: already done")
	_veq(m.position(), Vector3(2.5, 1.0, 3.5), "one waypoint: parked where it started")
	m.advance(1.0)
	_veq(m.position(), Vector3(2.5, 1.0, 3.5), "advancing a finished walk is a no-op")
	var empty := _make([], 16.0)
	_true(empty.is_done(), "no waypoints: already done")
	_veq(empty.position(), Vector3.ZERO, "no waypoints: the origin")
	_completed["_test_degenerate_single_waypoint"] = true



## `waypoints` is the caller's own polyline and stays untouched — `ScenarioApplyTest`
## and `ScenarioSpriteMoveTest` read its last element to name the seat.
func _test_waypoints_are_preserved_verbatim() -> void:
	var pts := [Vector3(0.5, 0, 0.5), Vector3(1.5, LEVEL, 0.5), Vector3(2.5, LEVEL, 0.5)]
	var m := _make(pts, 16.0)
	_eq(m.waypoints.size(), 3, "waypoints kept")
	_veq(m.waypoints[2], pts[2], "the last waypoint is the seat")
	_completed["_test_waypoints_are_preserved_verbatim"] = true



## `configure_rom` is the surface with real TILES behind it, and this is what the
## polyline surface cannot do: a DRAPED tile. `configure` reads one number per tile
## — its height, rounded to a whole level — so a slope is walked flat; the stepper
## reads `slope_height` and `slope_type` and walks the drape as a Y term in the
## direction vector, which is what the ROM does.
##
## Both arms below run the SAME route over the SAME two tiles. The only difference
## is what the caller was able to say about them.
func _test_configure_rom_recovers_what_a_polyline_cannot_state() -> void:
	# A 4x3 PSX strip, all flat at height 0, walked +X from (1,1) to (3,1).
	# Route: a LENGTH byte then two `+X` steps (`dir 0 << 6` = 0x00).
	var route: Array = [2, 0x00, 0x00]
	var flat = _rom_terrain(4, 3, 0)
	var m_flat := ScenarioPathMotion.new()
	m_flat.configure_rom(flat, Vector3i(1, 1, 0), route, 16.0, 60.0, INF, Vector2i.ZERO, 0.0)
	var flat_track := _run_frames(m_flat, int(m_flat.total_frames))
	var flat_moved: bool = false
	for p in flat_track:
		if absf(p.y) > 1e-6:
			flat_moved = true
	_true(not flat_moved, "configure_rom on flat tiles: no vertical motion")
	_veq(m_flat.position(), Vector3(3.5, 0, 1.5), "configure_rom lands on the destination centre")
	# The same walk stated as a polyline agrees, which is what says the two surfaces
	# share one coordinate map rather than two.
	var m_poly := _make([Vector3(1.5, 0, 1.5), Vector3(2.5, 0, 1.5), Vector3(3.5, 0, 1.5)], 16.0)
	_eq(int(m_poly.total_frames), int(m_flat.total_frames),
		"polyline and real-tile arms agree on a flat route")

	# Now drape the middle tile: slope_height 2, InclineEast (0x52), which rises
	# eastward across it. Its HEIGHT is still 0, so a polyline reading the tile's
	# waypoint cannot state any of this.
	var draped = _rom_terrain(4, 3, 0)
	draped.tile(2, 1, 0).slope_h = 2
	draped.tile(2, 1, 0).slope_t = 0x52
	var m_drape := ScenarioPathMotion.new()
	m_drape.configure_rom(draped, Vector3i(1, 1, 0), route, 16.0, 60.0, INF, Vector2i.ZERO, 0.0)
	var peak: float = 0.0
	for p in _run_frames(m_drape, int(m_drape.total_frames)):
		peak = maxf(peak, absf(p.y))
	_true(peak > LEVEL, "the drape lifts the unit off the flat plane (%.5f)" % peak)
	_true(m_drape.total_frames != m_flat.total_frames,
		"and it costs a different number of frames than the flat arm")
	_completed["_test_configure_rom_recovers_what_a_polyline_cannot_state"] = true


## THE WIRED PATH, END TO END — #819 item 5, and the only arm in this file that
## exercises the ADR-0052 mirror.
##
## Every other `configure_rom` arm here passes `psx_rows = 0`, meaning "this frame is
## already Godot-oriented" — so the mirror applied for a REAL map was exercised by
## nothing. That gap is worse than it sounds, and it is the reason this arm walks the
## trajectory instead of reading a return value: a wrong mirror produces a walk of the
## right length, the right shape and the right duration running the WRONG WAY down the
## map, and the plan's own `endpoint` still reads correctly because it is computed
## before the motion runs. Assert the output the way the real consumer consumes it.
func _test_the_wired_path_lands_where_the_wire_did() -> void:
	var fx := _load_json(_ROUTE_FIXTURES + "/control.json")
	if fx.is_empty():
		# ABSENT IS NOT A FAILED ASSERTION. This arm's fixture carries MAP009's tile
		# array verbatim, so `export_standalone.py` excludes it as Square Enix data
		# (register step 9, the user's "no square assets" ruling) and the generator
		# that mints it bakes from `research/`, outside the package -- a clone can
		# never have it. It used to score `_true(not fx.is_empty(), ...)` FIRST and
		# then return, so the absence arrived as a red assertion, which is the one
		# reading it must not have: a missing oracle and a wrong answer are not the
		# same finding. The arm is declared complete so the 17-arm check still
		# distinguishes this from a silent abort.
		print("  [SKIP] wired path — the control fixture is absent, excluded from "
			+ "the standalone repo as Square Enix data (MAP009 tile geometry).")
		_completed["_test_the_wired_path_lands_where_the_wire_did"] = true
		return
	_true(not fx.is_empty(), "wired path: the control fixture loads")
	var Stepper = ExMateriaBattlefield.RomWalkStepper
	var Planner = ExMateriaBattlefield.EventPathfinder
	var nx: int = int((fx["size"] as Array)[0])
	var ny: int = int((fx["size"] as Array)[1])
	var terrain = _terrain_from_fixture(fx, Stepper)
	var start := Vector3i(int(fx["start"][0]), int(fx["start"][1]), int(fx["start"][2]))
	var dest := Vector3i(int(fx["dest"][0]), int(fx["dest"][1]), int(fx["dest"][2]))

	# PLANNED here, not read out of the fixture: the subject is the whole chain, and
	# taking the bytes from the fixture would test the motion alone.
	var plan: Dictionary = Planner.new().plan(terrain, start, dest, Planner.cost_row(1))
	_true(plan["reached_target"], "wired path: the planner reaches the control's target")

	var m := ScenarioPathMotion.new()
	m.configure_rom(terrain, start, Array(plan["route"] as PackedByteArray), 10.0,
		60.0, INF, Vector2i.ZERO, 0.0, ny, [])

	# Walk it, recording the GODOT grid cell under the unit whenever it changes. A LEAP
	# flies OVER a tile, so this is a SUPERSET of the route's cells — subsequence, not
	# equality, is the honest assertion, and it still fails on a mirror.
	var visited: Array[Vector2i] = []
	var guard: int = 0
	while not m.is_done() and guard < 4000:
		var p: Vector3 = m.position()
		var c := Vector2i(int(floor(p.x)), int(floor(p.z)))
		if visited.is_empty() or visited[visited.size() - 1] != c:
			visited.append(c)
		m.advance(1.0 / 60.0)
		guard += 1
	_true(guard < 4000, "wired path: the walk terminates")
	var last: Vector3 = m.position()
	var last_cell := Vector2i(int(floor(last.x)), int(floor(last.z)))
	if visited.is_empty() or visited[visited.size() - 1] != last_cell:
		visited.append(last_cell)

	# The wire's PSX cells, mirrored onto the Godot grid.
	var want: Array[Vector2i] = []
	for c in fx["cells"]:
		want.append(Vector2i(int(c[0]), ny - 1 - int(c[1])))
	_true(want.size() > 0, "wired path: the fixture states a cell sequence")

	_eq(str(visited[0]), str(want[0]),
		"wired path: starts on the wire's first cell, in Godot coordinates")
	_eq(str(visited[visited.size() - 1]), str(want[want.size() - 1]),
		"wired path: and ENDS on the wire's last cell — an unmirrored run lands on "
		+ "Godot z=%d instead of %d" % [int(fx["dest"][1]), ny - 1 - int(fx["dest"][1])])
	var i: int = 0
	for c in visited:
		if i < want.size() and c == want[i]:
			i += 1
	_eq(i, want.size(),
		"wired path: all %d of the wire's cells appear in the trajectory, in order"
			% want.size())
	_approx(last.x - floor(last.x), 0.5, "wired path: the seat is the tile centre in X")
	_approx(last.z - floor(last.z), 0.5, "wired path: the seat is the tile centre in Z")
	_true(nx > 0, "wired path: the fixture states a map width")
	_completed["_test_the_wired_path_lands_where_the_wire_did"] = true


## What `psx_rows` MEANS, stated directly: the same terrain, start and route, run once
## in each frame, land on mirrored Z and identical X.
##
## The arm above would CATCH a mirror bug; this one SAYS what the parameter does, so a
## reader does not have to infer it from a MAP009 capture.
func _test_psx_rows_mirrors_z_and_leaves_x_alone() -> void:
	var terrain = _rom_terrain(6, 6, 0)
	# Two steps in +X — route byte direction 0. X must be untouched by the flip.
	var route: Array = [2, 0x00, 0x00]

	var godot_frame := ScenarioPathMotion.new()
	godot_frame.configure_rom(terrain, Vector3i(1, 2, 0), route, 16.0, 60.0, INF,
		Vector2i.ZERO, 0.0, 0, [])
	godot_frame.snap_to_end()
	var a: Vector3 = godot_frame.position()

	var psx_frame := ScenarioPathMotion.new()
	psx_frame.configure_rom(terrain, Vector3i(1, 2, 0), route, 16.0, 60.0, INF,
		Vector2i.ZERO, 0.0, 6, [])
	psx_frame.snap_to_end()
	var b: Vector3 = psx_frame.position()

	_approx(a.x, b.x, "psx_rows: X is untouched — ADR-0052 mirrors Z only")
	_approx(a.z, 2.5, "psx_rows 0: PSX row 2 IS Godot z 2")
	_approx(b.z, 3.5, "psx_rows 6: PSX row 2 is Godot z 6 - 1 - 2 = 3")
	_approx(a.z + b.z, 6.0, "psx_rows: the two frames reflect about size_z / 2")
	_completed["_test_psx_rows_mirrors_z_and_leaves_x_alone"] = true


## The baked WIRE fixture the arm above reads — the HOST's copy, minted by
## `tools/gen_rom_event_route_fixtures.py` in the same run and from the same dict as
## the addon's.
##
## ⚠️ DELIBERATELY NOT THE ADDON'S COPY. A `tests/` file naming a path into an addon
## root is `check_lattice_scene` criterion 4's whole subject, and this file cannot claim
## the ORACLE channel that exists for exactly this shape: that channel's condition 2
## requires the naming file to name a HOST `res://` path, and this one names none. The
## generator writing both roots is the honest answer — two files, one source, no drift
## possible — rather than adding a host path here to satisfy a predicate.
##
## ⚠️ AND DO NOT SPELL THE ADDON PATH IN A COMMENT EITHER. The scanner is textual and
## cannot tell a comment from code, so the first draft of this very note — which named
## the addon path in order to say it was not being used — scored as a site and reds the
## guard. Say it in words, not in a literal.
const _ROUTE_FIXTURES := "res://tests/fixtures/rom_event_route"


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## A fixture's baked tile array as a `RomWalkStepper.Terrain`. `tiles` is
## `[level][psx_y][x] -> the eight bytes`, in `tile_fields` order.
func _terrain_from_fixture(fx: Dictionary, Stepper):
	var size: Array = fx["size"]
	var src: Array = fx["tiles"]
	var levels: Array = []
	for lvl in Stepper.LEVELS:
		var rows: Array = []
		for y in int(size[1]):
			var row: Array = []
			for x in int(size[0]):
				var t: Array = src[lvl][y][x]
				row.append(Stepper.MapTile.new(int(t[0]), int(t[1]), int(t[2]),
					int(t[3]), int(t[4]), int(t[5]), bool(t[6]), bool(t[7])))
			rows.append(row)
		levels.append(rows)
	return Stepper.Terrain.new(levels, int(size[0]), int(size[1]))


## A `RomWalkStepper.Terrain` of `nx x ny` flat tiles at `height`, on both levels —
## real Tile records, so a test can then drape or flood one of them.
func _rom_terrain(nx: int, ny: int, height: int):
	var Stepper = ExMateriaBattlefield.RomWalkStepper
	var heights: Array = []
	for _lvl in 2:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				row.append(height)
			rows.append(row)
		heights.append(rows)
	return Stepper.terrain_flat(heights, nx, ny)
