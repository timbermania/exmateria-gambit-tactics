extends Node
## Scores [EventPathfinder] — the `{28} Walk To` ROUTING half — against the PSX wire.
##
## The fixtures under `tests/fixtures/rom_event_route/` are baked by
## `tools/gen_rom_event_route_fixtures.py` out of the live PCSX captures in
## `research/scenario29_walk_vs_jump/evidence/`, each with the post-patch MAP009
## tile array its arm ran against. So this is scored against HARDWARE, and it needs
## no `res://assets/maps` — an asset SYMLINK, absent from a bare worktree, and a
## test that reached for it would go red for a reason that has nothing to do with
## routing.
##
## 🔴 **TWO TIERS, AND THEY ARE NOT THE SAME CLAIM.** The fixture's own `tier` field
## says which, and this file prints the split rather than one总 number:
##
##   * **WIRE** — 18 arms. What the ROM DID. Two independent measurements come out
##     of those logs and both are scored where they exist: `cells`, the tile sequence
##     off the per-frame `tile=` column (8 arms), and `route`, the emitted bytes off
##     the `rb=` column or the run report's OBSERVED line (12 arms). Three of the
##     twelve are REFUSALS — arm P watched the route buffer stay empty for 3338
##     frames — and a refusal is scored as hard as a route.
##   * **CROSS-CHECK** — 6 shipped corpus routes on MAP009/012/057, predicted by
##     `rom_event_flood.py`. Two independent transcriptions agreeing is real evidence
##     about the READING, and it is strictly weaker than a measurement. Labelled as
##     such here because ADR-0225 dec. 3 and 4 are the precedent: a test file that
##     lets the two blur together launders a shared misreading into a pass.
##
## ⚠️ The INVENTORY is asserted, not just the mismatch count. A generator that bakes
## two fixtures scores "0 differ" over two fixtures, which reads exactly like a pass.
##
## Run: "$GODOT" --path . --quit-after 5 res://addons/exmateria_battlefield/tests/EventPathfinderTest.tscn

const EventPathfinder = preload("res://addons/exmateria_battlefield/pathfinding/EventPathfinder.gd")
const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")
const RomTerrain = preload("res://addons/exmateria_battlefield/terrain/RomTerrain.gd")

const FIXTURE_DIR := "res://addons/exmateria_battlefield/tests/fixtures/rom_event_route"

## What the generator last baked. Pinned so a fixture set that silently SHRINKS —
## a renamed evidence file, a parse that stops matching, a generator half-edited —
## is a failure and not a smaller clean run.
const EXPECT_WIRE: int = 18
const EXPECT_CROSS: int = 6
const EXPECT_WIRE_ROUTE_SCORED: int = 12
const EXPECT_WIRE_CELL_SCORED: int = 8

const ARM_COUNT: int = 7

## Arms that ran to COMPLETION, by name.
##
## 🔴 A GDScript runtime error aborts only its ENCLOSING function. An arm that dies
## part-way contributes NO failures, so `_ready` resumes, the counters read
## `N passed, 0 failed`, and this file prints **[PASS]** over a test that never ran.
## Worse than a hang: a hang is scored HUNG and somebody looks. Same pattern as
## `RomWalkStepperTest` and `BattlefieldProvidesTest`.
var _completed := {}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_constants_are_the_rom_literals()
	_test_the_cost_row_is_the_scus_row()
	_test_the_reader_flips_z_and_resolves_both_enums()
	_test_the_wire_arms()
	_test_a_refusal_is_a_no_op()
	_test_the_cross_check_tier()
	_test_the_questions_the_bfs_test_asked()

	print("\n=== EventPathfinderTest: %d passed, %d failed, %d/%d arms reported ==="
		% [_passed, _failed, _completed.size(), ARM_COUNT])
	if _passed == 0 and _failed == 0:
		print("[FAIL] EventPathfinderTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != ARM_COUNT:
		print("[FAIL] EventPathfinderTest: only %d of %d arms ran to completion — ran %s"
			% [_completed.size(), ARM_COUNT, str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] EventPathfinderTest")
		get_tree().quit(1)
	else:
		print("[PASS] EventPathfinderTest")
		get_tree().quit(0)


# --- arm 1: the literals ------------------------------------------------------

func _test_the_constants_are_the_rom_literals() -> void:
	_eq(EventPathfinder.WALK_TO_CLIMB, 3,
		"the handler's literal is 3 (`ori a3,zero,0x3` @ 0x8013E634)")
	_eq(EventPathfinder.CLIMB_CEILING, 7,
		"the climb argument clamps at 7 (`sltiu v0,v0,0x8` @ 0x80178424)")
	_eq(EventPathfinder.MOVE_BUDGET, 0x7C, "the move budget is 124")
	_eq(EventPathfinder.CLEARANCE, 6, "vertical clearance is 6 half-levels")
	_eq(EventPathfinder.MODES, 2,
		"the flood relaxes BOTH levels of a column — a level change is free (ADR-0219)")
	# The leap span is the whole of #803 and it is derived, not written down: the one
	# literal 3 fans out into `3 >> 1 == 1`, which is why a `{28}` walk clears exactly
	# one tile and arm K's two-wide channel is not leapable.
	_eq(EventPathfinder.WALK_TO_CLIMB >> 1, 1,
		"the max leap span is `climb >> 1` = ONE extra tile")
	_eq(EventPathfinder.DIRS.size(), 4, "four directions, no diagonals")
	# Two tables, two jobs (research README §17.3/§17.7): the flood's expansion order
	# and the route byte's direction encoding are DIFFERENT permutations, and the one
	# time they were conflated it scrambled a 32-variant model search.
	var flood_order: Array = []
	for d in EventPathfinder.DIRS:
		flood_order.append(Vector2i(d.x, d.y))
	_eq(str(flood_order), str([Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(0, -1)]), "the flood expands +X, +Y, -X, -Y")
	var byte_order: Array = []
	for i in 4:
		for k in EventPathfinder.ROUTE_BITS:
			if EventPathfinder.ROUTE_BITS[k].x == i << 6:
				byte_order.append(k)
	_eq(str(byte_order), str([Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, -1), Vector2i(0, 1)]), "the route BYTE encodes +X, -X, -Y, +Y")
	_true(str(flood_order) != str(byte_order),
		"the two direction tables are NOT the same permutation")
	_completed["constants"] = true


# --- arm 2: the cost row ------------------------------------------------------

func _test_the_cost_row_is_the_scus_row() -> void:
	var row := EventPathfinder.cost_row(1)
	_eq(row.size(), 64, "the cost row is 64 usable bytes, not 256 (`surface & 0x3F`)")
	_eq(row[0x03], 1, "Grassland costs 1")
	_eq(row[0x0E], 2, "Waterway costs 2 — the reason the moat is worth leaping")
	_eq(row[0x11], 2, "Sea costs 2")
	_eq(row[0x1C], 0xFF, "Obstacle costs 0xFF")
	_eq(row[0x12], 0xFF, "Lava costs 0xFF")
	_eq(EventPathfinder.cost_row(4)[0x09], 4, "Swamp is weather-substituted")
	_eq(EventPathfinder.cost_row(1)[0x09], 1, "... and reads the substituted value")
	var flat := EventPathfinder.flat_cost_row()
	_eq(flat[0x0E], 1, "the `{28}` operand's `+8 == 0` flattens Waterway to 1")
	_eq(flat[0x1C], 1, "... and an Obstacle with it")
	_completed["cost_row"] = true


# --- arm 3: the reader --------------------------------------------------------

func _test_the_reader_flips_z_and_resolves_both_enums() -> void:
	_eq(RomTerrain.SLOPE_BYTE.size(), 13, "thirteen slope types")
	# 🔴 SIXTY-FOUR SINCE `3a9abd72f`, AND THE NUMBER IS THE ARGUMENT RATHER THAN A COUNT.
	# `byte0 & 0x3F` is 0..63, so a name table that is TOTAL is what repo-root ADR-0004 dec. 11
	# requires before a surface may be spelled by name at all — the same ruling takes SLOPE
	# as raw ints because `TerrainSlopeTypes` is 13-of-256 and can never be total. At 50 the
	# table did NOT qualify: `parse` fell through to `NaturalSurface` for 0x32-0x3F, and
	# 0x3F is on 367 tiles across 28 arrangements with cost `FF` in all four movetypes, so
	# the planner routed through walls with no crash and no red. This pin is what would
	# catch the table LOSING members again, so 64 has to be asserted, not tolerated.
	_eq(RomTerrain.SURFACE_BYTE.size(), 64, "sixty-four surface types — TOTAL over `byte0 & 0x3F`")
	_eq(int(RomTerrain.SURFACE_BYTE["CrossSection"]), 0x3F,
		"0x3F is CrossSection — the member whose absence made the table non-total")
	_eq(int(RomTerrain.SURFACE_BYTE["Waterway"]), 0x0E, "Waterway is byte 14")
	_eq(int(RomTerrain.SURFACE_BYTE["Obstacle"]), 0x1C, "Obstacle is byte 28")
	_eq(int(RomTerrain.SLOPE_BYTE["InclineNorth"]), 0x85, "InclineNorth is byte 133")
	_eq(RomTerrain.map_name_for(9), "MAP009", "the map name is zero-padded to three")
	# The Z FLIP, on a literal `terrain.json` shape with no assets anywhere near it.
	# Exporter row 0 is Godot grid Z 0, and ADR-0052 mirrors it onto PSX row ny-1.
	# Skipping this returns a plausible route on a MIRRORED map and never throws.
	var doc := {
		"size_x": 2, "size_z": 3,
		"level_0": [
			[_row(0, "Grassland", "Flat"), _row(1, "Grassland", "Flat")],
			[_row(2, "Waterway", "Flat"), _row(3, "Grassland", "Flat")],
			[_row(4, "Grassland", "InclineNorth"), _row(5, "Obstacle", "Flat")],
		],
		"level_1": [
			[_row(0, "Grassland", "Flat"), _row(0, "Grassland", "Flat")],
			[_row(0, "Grassland", "Flat"), _row(0, "Grassland", "Flat")],
			[_row(0, "Grassland", "Flat"), _row(0, "Grassland", "Flat")],
		],
	}
	var t = RomTerrain.from_json(doc)
	_true(t != null, "the reader built a terrain")
	_eq(t.nx, 2, "size_x survives")
	_eq(t.ny, 3, "size_z survives")
	_eq(t.tile(0, 2, 0).height, 0, "exporter row 0 lands on PSX row ny-1 = 2")
	_eq(t.tile(0, 0, 0).height, 4, "exporter row 2 lands on PSX row 0")
	_eq(t.tile(0, 1, 0).surface, 0x0E, "the surface NAME resolved to its byte")
	_eq(t.tile(1, 0, 0).surface, 0x1C, "... and Obstacle with it")
	_eq(t.tile(0, 0, 0).slope_t, 0x85, "the slope NAME resolved to its byte")
	_eq(t.tile(0, 1, 0).depth, 1, "depth survives — a field `TerrainCell` has never had")
	_eq(t.tile(0, 1, 0).thickness, 2, "thickness survives, and only the routing half reads it")
	_true(t.tile(1, 0, 0).impassable, "impassable survives")
	# An unknown NAME reads as byte 0 rather than raising, because `Flat` and
	# `NaturalSurface` are both 0 and both are what an unclassified tile behaves as.
	var odd := RomTerrain.from_json({
		"size_x": 1, "size_z": 1,
		"level_0": [[{"surface_type": "NoSuchSurface", "slope_type": "NoSuchSlope"}]],
		"level_1": [[{}]]})
	_eq(odd.tile(0, 0, 0).surface, 0, "an unknown surface name reads as 0")
	_eq(odd.tile(0, 0, 0).slope_t, 0, "an unknown slope name reads as 0")
	_completed["reader"] = true


func _row(height: int, surface: String, slope: String) -> Dictionary:
	return {
		"height": height, "depth": 1 if surface == "Waterway" else 0,
		"slope_height": 3 if slope != "Flat" else 0,
		"slope_type": slope, "surface_type": surface,
		"thickness": 2, "impassable": surface == "Obstacle",
		"unselectable": false,
	}


# --- arm 4: the wire ----------------------------------------------------------

func _test_the_wire_arms() -> void:
	if not _fixtures_present():
		_skip("wire")
		_completed["wire"] = true
		return
	var index := _json(FIXTURE_DIR + "/index.json")
	var wire: Array = index.get("wire", [])
	_eq(wire.size(), EXPECT_WIRE, "the generator baked %d WIRE arms" % EXPECT_WIRE)
	_eq((index.get("wire_route_scored", []) as Array).size(), EXPECT_WIRE_ROUTE_SCORED,
		"%d of them state a route on the wire" % EXPECT_WIRE_ROUTE_SCORED)
	_eq((index.get("wire_cells_scored", []) as Array).size(), EXPECT_WIRE_CELL_SCORED,
		"%d of them state a cell sequence on the wire" % EXPECT_WIRE_CELL_SCORED)
	var routes_scored: int = 0
	var cells_scored: int = 0
	for name in wire:
		var fx := _json("%s/%s.json" % [FIXTURE_DIR, name])
		var got := _plan(fx)
		var want_route: Array = fx.get("route", [])
		if not want_route.is_empty():
			routes_scored += 1
			_eq(_hex(got["route"]), _hex(PackedByteArray(want_route)),
				"WIRE %s route (%s) — %s" % [name, fx.get("route_source", ""),
					_short(fx.get("label", ""))])
		var want_cells: Array = fx.get("cells", [])
		if not want_cells.is_empty():
			cells_scored += 1
			_eq(_cells(got["cells"]), _cells_raw(want_cells),
				"WIRE %s cells (%s)" % [name, fx.get("cells_source", "")])
	_eq(routes_scored, EXPECT_WIRE_ROUTE_SCORED, "every route-bearing WIRE arm was scored")
	_eq(cells_scored, EXPECT_WIRE_CELL_SCORED, "every cell-bearing WIRE arm was scored")
	_completed["wire"] = true


# --- arm 5: the refusal -------------------------------------------------------

func _test_a_refusal_is_a_no_op() -> void:
	# `FUN_8017813C` returns NULL and the whole opcode does nothing. There is no
	# "nearest reachable tile" anywhere in the ROM, so a caller that substitutes one
	# is inventing behaviour — which is what the shipped BFS did.
	if not _fixtures_present():
		_skip("refusal")
		_completed["refusal"] = true
		return
	var refusals: int = 0
	for name in ["P", "R1", "R2"]:
		var fx := _json("%s/%s.json" % [FIXTURE_DIR, name])
		_true(bool(fx.get("refused", false)), "%s is baked as a REFUSAL" % name)
		var got := _plan(fx)
		_true(not got["reached_target"], "%s: the walk is refused" % name)
		_true((got["route"] as PackedByteArray).is_empty(),
			"%s: NO route is emitted at all" % name)
		_eq(str(got["endpoint"]), str(_v3(fx["start"])),
			"%s: the endpoint is the START — the unit does not move" % name)
		_true(String(got["refused"]) != "", "%s: the refusal names its reason" % name)
		refusals += 1
	_eq(refusals, 3, "all three refusal arms ran")
	# R0 is the NEGATIVE CONTROL and it is the arm that makes the three above mean
	# something: same tile, depth 0, the height raised instead — and the route is
	# unchanged. Without it "the walk was refused" is consistent with the patch
	# breaking the map.
	var r0 := _json("%s/R0.json" % FIXTURE_DIR)
	var got0 := _plan(r0)
	_true(got0["reached_target"],
		"R0 negative control: depth 0 + a height change still routes")
	_eq(_hex(got0["route"]), _hex(PackedByteArray(r0["route"])),
		"R0 negative control: the route is unchanged")
	_completed["refusal"] = true


# --- arm 6: the cross-check ---------------------------------------------------

func _test_the_cross_check_tier() -> void:
	if not _fixtures_present():
		_skip("cross_check")
		_completed["cross_check"] = true
		return
	var index := _json(FIXTURE_DIR + "/index.json")
	var cross: Array = index.get("cross_check", [])
	_eq(cross.size(), EXPECT_CROSS, "the generator baked %d CROSS-CHECK cases" % EXPECT_CROSS)
	for name in cross:
		var fx := _json("%s/%s.json" % [FIXTURE_DIR, name])
		var got := _plan(fx)
		_eq(_hex(got["route"]), _hex(PackedByteArray(fx["route"])),
			"CROSS-CHECK %s route — NOT a wire measurement: %s"
				% [name, _short(fx.get("label", ""))])
		_eq(_cells(got["cells"]), _cells_raw(fx["cells"]),
			"CROSS-CHECK %s cells — NOT a wire measurement" % name)
	_completed["cross_check"] = true


# --- arm 7: what the retired BFS test asked -----------------------------------
#
# `ScenarioEventPathfinderTest` drove the uniform-cost BFS this file replaced, over
# a `MockNav` duck type that no longer exists, and it is deleted with it. Its twelve
# arms did not all survive the replacement and the split is the point:
#
#   free target exact        -> every WIRE arm; the route ends ON the target
#   impassable detour        -> WIRE arms M (a ceiling) and I (an Obstacle)
#   walk_to_climb literal    -> arm 1
#   start level is an input  -> WIRE arm O, and the corpus level-bit cases
#   the climb keeps the walk
#     out of the water       -> SUPERSEDED. It does not: the ROM LEAPS the moat,
#                               which is the whole of #803. The control arm is the
#                               measurement that arm was guessing at.
#   unreachable -> nearest   -> SUPERSEDED, and it was never the ROM. There is no
#                               nearest-tile fallback in `FUN_8017813C`; an
#                               unreachable target is a NO-OP. Arms P/R1/R2.
#   tie-break +X before -Z   -> SUPERSEDED. The ROM's walk-back tie-break is span,
#                               then roughness, then same-direction — not a
#                               discovery order. Arm 1 pins both tables instead.
#
# The five below are the ones that are still real questions and that no baked
# capture happens to ask. They run on SYNTHETIC terrain, which is why they are here
# and not in the fixtures: each isolates one rule to one tile.
func _test_the_questions_the_bfs_test_asked() -> void:
	var cost := EventPathfinder.cost_row(1)

	# (a) START == TARGET. `_walk_back` returns an EMPTY chain, which is a valid
	# zero-step route and NOT a failure — the corpus contains two, and reading the
	# empty list as "no chain" invents a ship-gate violation that is not there.
	var flat = _synthetic(3, 3, 5)
	var here := EventPathfinder.new().plan(flat, Vector3i(1, 1, 0), Vector3i(1, 1, 0), cost)
	_true(here["reached_target"], "start == target: the walk is not refused")
	_eq(_hex(here["route"]), "00", "start == target: a route of ZERO steps")
	_eq(_cells(here["cells"]), "(1,1,0)", "start == target: the unit stays put")

	# (b) THE CLIMB GATE. `stateB+0x02` is `climb << 1` = 6 half-levels, compared
	# against a doubled height delta — so three whole levels step and four do not.
	var step3 = _synthetic(2, 1, 0)
	step3.tiles[0][0][1].height = 3
	_true(EventPathfinder.new().plan(step3, Vector3i(0, 0, 0), Vector3i(1, 0, 0),
		cost)["reached_target"], "climb gate: a 3-level step is walkable")
	var step4 = _synthetic(2, 1, 0)
	step4.tiles[0][0][1].height = 4
	_true(not EventPathfinder.new().plan(step4, Vector3i(0, 0, 0), Vector3i(1, 0, 0),
		cost)["reached_target"], "climb gate: a 4-level step is not")

	# (c) THE CLIMB ARGUMENT CLAMPS AT 7. There is no "no limit" to ask for, and the
	# clamp is THIS file's — the Python transcription takes an already-clamped
	# `jump_stat`, so it is not an oracle here and asking it would have said an
	# 8-level step at climb 99 is walkable. `sltiu v0,v0,0x8` @ `0x80178424` is.
	# Seven whole levels IS clearable at climb 7 (`7 << 1 == 14` half-levels, and
	# the compare is `>`), so the arm has to reach for eight.
	var tall = _synthetic(2, 1, 0)
	tall.tiles[0][0][1].height = 7
	_true(EventPathfinder.new().plan(tall, Vector3i(0, 0, 0), Vector3i(1, 0, 0),
		cost, 7)["reached_target"], "climb 7 clears exactly 7 whole levels")
	var taller = _synthetic(2, 1, 0)
	taller.tiles[0][0][1].height = 8
	var at7 := EventPathfinder.new().plan(taller, Vector3i(0, 0, 0), Vector3i(1, 0, 0), cost, 7)
	var at99 := EventPathfinder.new().plan(taller, Vector3i(0, 0, 0), Vector3i(1, 0, 0), cost, 99)
	_true(not at7["reached_target"], "climb 7 does not clear eight")
	_eq(str(at99["reached_target"]), str(at7["reached_target"]),
		"climb 99 plans exactly as climb 7 — the argument is clamped, not honoured")

	# (d) A BRIDGE DECK IS THE ROUTE ACROSS A MOAT — ADR-0219's case, and the one
	# that needs the flood to relax BOTH levels of a column. The middle column's
	# ground is eight half-levels down; its level-1 deck is level with the walker.
	# The route must take the DECK, and say so in route bit 5.
	var moat = _synthetic(3, 1, 5)
	moat.tiles[0][0][1].height = 1
	moat.tiles[0][0][1].surface = 0x0E
	moat.tiles[0][0][1].depth = 1
	moat.tiles[1][0][1].height = 5
	moat.tiles[1][0][1].surface = 0x03
	# ... and the deck has to be SELECTABLE. `_synthetic` mints level 1 unselectable
	# because that is what an absent upper tile is, and leaving the flag set here
	# reads as a moat with no bridge — the arm passes for the wrong reason.
	moat.tiles[1][0][1].unselectable = false
	var crossed := EventPathfinder.new().plan(moat, Vector3i(0, 0, 0), Vector3i(2, 0, 0), cost)
	_true(crossed["reached_target"], "bridge deck: the far bank is reachable")
	_eq(_cells(crossed["cells"]), "(0,0,0) (1,0,1) (2,0,0)",
		"bridge deck: the route goes over the DECK, not through the water")
	_true(int((crossed["route"] as PackedByteArray)[1]) & 0x20 != 0,
		"bridge deck: the step onto it carries route bit 5, the LEVEL bit")

	# (e) OTHER UNITS DO NOT BLOCK, and after the replacement that is STRUCTURAL
	# rather than behavioural: the ROM's `a0 = 3` map build skips the occupancy
	# phase entirely, so this class has no occupancy input to ignore. The old test
	# proved it by handing in a nav with no `is_occupied` and watching nothing call
	# it; the honest form of the same claim now is that no such surface exists.
	var members: Array = []
	for m in EventPathfinder.new().get_script().get_script_method_list():
		members.append(String(m["name"]))
	for m in EventPathfinder.new().get_script().get_script_property_list():
		members.append(String(m["name"]))
	var occupancy: Array = []
	for m in members:
		var low: String = String(m).to_lower()
		if low.contains("occup") or low.contains("unit") or low.contains("nav"):
			occupancy.append(m)
	_eq(str(occupancy), "[]",
		"terrain-only routing: the planner has no occupancy surface at all")
	_completed["bfs_questions"] = true


## A flat `nx` x `ny` map at `height`, Grassland, on both levels — the neutral board
## the synthetic arms above patch one tile of. Level 1 is UNSELECTABLE, which is what
## an absent upper tile is: the ceiling query skips it and the pass map denies it.
func _synthetic(nx: int, ny: int, height: int):
	var levels: Array = []
	for lvl in RomWalkStepper.LEVELS:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				row.append(RomWalkStepper.MapTile.new(
					0x03, height if lvl == 0 else 0, 0, 0, 0, 0, false, lvl == 1))
			rows.append(row)
		levels.append(rows)
	return RomWalkStepper.Terrain.new(levels, nx, ny)


# --- helpers ------------------------------------------------------------------

func _plan(fx: Dictionary) -> Dictionary:
	var pf := EventPathfinder.new()
	var cost: PackedInt32Array = EventPathfinder.flat_cost_row() \
		if bool(fx.get("flat_cost", false)) \
		else EventPathfinder.cost_row(int(fx.get("weather_cost", 1)))
	return pf.plan(_terrain(fx), _v3(fx["start"]), _v3(fx["dest"]), cost)


## The fixture's baked tile array as a [RomWalkStepper.Terrain]. `tiles` is
## `[level][psx_y][x] -> the eight bytes`, in `tile_fields` order.
func _terrain(fx: Dictionary):
	var size: Array = fx["size"]
	var src: Array = fx["tiles"]
	var levels: Array = []
	for lvl in RomWalkStepper.LEVELS:
		var rows: Array = []
		for y in int(size[1]):
			var row: Array = []
			for x in int(size[0]):
				var t: Array = src[lvl][y][x]
				row.append(RomWalkStepper.MapTile.new(
					int(t[0]), int(t[1]), int(t[2]), int(t[3]), int(t[4]),
					int(t[5]), bool(t[6]), bool(t[7])))
			rows.append(row)
		levels.append(rows)
	return RomWalkStepper.Terrain.new(levels, int(size[0]), int(size[1]))


static func _v3(a: Array) -> Vector3i:
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func _hex(b: PackedByteArray) -> String:
	var out: PackedStringArray = []
	for v in b:
		out.append("%02X" % v)
	return " ".join(out)


static func _cells(cells: Array) -> String:
	var out: PackedStringArray = []
	for c in cells:
		out.append("(%d,%d,%d)" % [c.x, c.y, c.z])
	return " ".join(out)


static func _cells_raw(cells: Array) -> String:
	var out: PackedStringArray = []
	for c in cells:
		out.append("(%d,%d,%d)" % [int(c[0]), int(c[1]), int(c[2])])
	return " ".join(out)


static func _short(s: String) -> String:
	return s.substr(0, 70)


## Whether this checkout has the baked route corpus at all.
##
## ABSENT IS NOT WRONG in a standalone clone. Every case carries its map's tile
## array verbatim -- MAP009, MAP012 and MAP057, eight fields per tile -- so
## `export_standalone.py` excludes the whole fixture directory as Square Enix data
## (register step 9, the user's "no square assets" ruling), and
## `tools/gen_rom_event_route_fixtures.py` cannot rebuild it there: it bakes from
## `research/`, outside the package. Permanent, not a bootstrap step.
##
## Checked ONCE, by index, and consulted by the three arms that read the corpus
## (wire / refusal / cross_check). The other four arms are literals, the SCUS cost
## row, the reader's enum tables and synthetic terrain -- none of them touch a
## fixture -- so a clone still scores 4 of 7 arms rather than losing the file.
func _fixtures_present() -> bool:
	return FileAccess.file_exists(FIXTURE_DIR + "/index.json")


## The line the three skipping arms print, so the reason is in the log exactly once
## per arm rather than implied by silence.
func _skip(arm: String) -> void:
	print("  [SKIP] %s — the baked route corpus is absent, excluded from the "
		% arm + "standalone repo as Square Enix data (verbatim map tile geometry).")


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[EventPathfinderTest] missing fixture %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _eq(got, want, what: String) -> void:
	if str(got) == str(want):
		_passed += 1
	else:
		_failed += 1
		print("  [fail] %s\n           got  %s\n           want %s" % [what, str(got), str(want)])


func _true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [fail] %s" % what)
