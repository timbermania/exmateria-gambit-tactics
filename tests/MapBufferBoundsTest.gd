extends Node3D
# test-kind: logic
# seeded-break: build_map_data's OOB-skip guard disabled (`if gx < 0 or gx >= map_width or gz < 0 or gz >= map_height:` → `if false:`); 'out-of-bounds tile did not write into the hole cell' RED (expected 0, got 99 — the stray impassable cell wraps into the hole slot) and 'far out-of-bounds tile skipped, size intact' RED (index '618' past the cliff table, build_map_data aborts); the in-bounds write arm, the seeded-cliff arm, and the level-1 offset arm stay green; GREEN unbroken on the reverted tree

## Regression guard for GPUBatchSimulator.build_map_data (the index-936 crash).
##
## The map storage buffer is sized from the DistanceFieldGenerator's bounds,
## which are the bounding box of the WALKABLE tiles only. The fill loop, however,
## iterates every cell the lattice reports — ALL of them, impassable ones included.
## An impassable cell sitting outside the walkable box computes an index past the
## buffer (or, worse, wraps into a *different* in-bounds cell and corrupts it),
## which is exactly the `Invalid assignment of index '936'` crash that killed
## GPU-simulator init.
##
## The buffer is indexed on the walkable grid, so out-of-bounds cells (which are
## impassable and unreachable anyway) must simply be skipped.
##
## 🔴 THE DOUBLE'S `is_cliff_edge` WAS A HARDCODED `false`, AND IT IS GONE.
## This file used to carry a `Lattice` subclass whose cliff answer was a constant —
## with a comment defending it, because the node fixture it replaced had produced
## `false` everywhere too (four identical zero vertices per tile made every pair
## coincident). Two implementations agreed and both were wrong: `build_map_data`
## reads that member once per cell per direction and bakes it into a QUARTER of the
## buffer, so a quarter of the buffer was written from a constant, here and in the
## five other files that answered the same way. `TerrainFixture` (ADR-0218) hands
## over a real `Lattice` over real `Tile`s, so the cliff bytes come from terrain and
## `_test_a_seeded_cliff_reaches_the_baked_buffer` is finally able to fail.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/MapBufferBoundsTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
const TerrainFixture = ExMateriaBattlefield.TerrainFixture


var _passed: int = 0
var _failed: int = 0

## 🔴 THE ARMS THAT RAN TO COMPLETION, AND THIS FILE NEEDS IT MORE THAN MOST.
## A GDScript error aborts only its ENCLOSING function, so an arm that dies
## partway — indexing off a buffer that changed size, a fixture that failed to
## build — returns quietly to `_ready` and contributes NO failures. The counts
## then read `N passed, 0 failed` and this file prints **[PASS]** over arms that
## never executed. That is strictly worse than a hang: a hang is scored, a false
## green is believed.
##
## Not hypothetical here. Seeding `MAP_PLANES_PER_LEVEL` back to four cliff
## planes shrinks the buffer, and the level-1 arm below then indexes past its end
## on its FIRST read — every assertion after that point silently does not happen.
## The pattern is `addons/exmateria_battlefield/tests/BattlefieldProvidesTest.gd`,
## whose own docstring records the incident that bought it: five of seven
## functions did nothing and the verdict block printed [PASS] on `2 passed, 0
## failed`. A `_passed == 0 and _failed == 0` guard cannot catch that, because
## some assertions genuinely did pass.
var _completed: Array[String] = []

const ARM_COUNT := 5


func _ready() -> void:
	_test_out_of_bounds_tile_does_not_corrupt_in_bounds_cell()
	_test_far_out_of_bounds_tile_does_not_overflow()
	_test_in_bounds_tiles_written_correctly()
	_test_a_seeded_cliff_reaches_the_baked_buffer()
	_test_level_1_lands_at_the_offsets_a_reader_computes()

	print("\n=== MapBufferBoundsTest: %d passed, %d failed, %d/%d arms reported ==="
		% [_passed, _failed, _completed.size(), ARM_COUNT])
	if _passed == 0 and _failed == 0:
		print("[FAIL] MapBufferBoundsTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != ARM_COUNT:
		print("[FAIL] MapBufferBoundsTest: only %d of %d arms ran to completion — %s"
			% [_completed.size(), ARM_COUNT, str(_completed)])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] MapBufferBoundsTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapBufferBoundsTest")
		get_tree().quit(0)


# Walkable 3x3 grid MINUS the (2,1) cell (a hole), so index 5 is unoccupied by a
# real tile. Bounds derived from these 8 cells: min=(0,0), 3x3, total_tiles=9.
const MIN_X := 0
const MIN_Z := 0
const MAP_W := 3
const MAP_H := 3
const TOTAL := MAP_W * MAP_H  # 9

# The buffer's whole length in tiles' worth of ints, both levels (ADR-0224
# dec. 2): `(heights + traversable + cliff x 4 x 2 target levels) x 2 levels`.
#
# 🔴 A LITERAL, AND IT WAS BRIEFLY NOT ONE. This assertion read `TOTAL * 6`
# before ADR-0224 and was changed to `GPUBatchSimulator.MAP_PLANES_PER_LEVEL *
# TerrainCell.LEVEL_COUNT` — "taken from the subject rather than restated",
# which is the right instinct everywhere except here, where the subject IS the
# thing under test. An arm that reads its expectation out of the code it guards
# follows that constant to any value and can never object to one. That matters
# more than usual on this buffer: ADR-0224 states its size two ways (dec. 2 says
# twelve planes; dec. 3's eight cliff bits per cell make it twenty), so a reader
# "correcting" the constant to match dec. 2 is a live possibility and this file
# is one of two places that would say no.
const PLANES := 20


# The 3x3-minus-one grid, as a fixture in the tree. The heights are `x*10 + z`, kept
# from the hand-fabricated cells so the index assertions read the same numbers — they
# are FFT half-steps and a 30-step neighbour gap is nothing production would build,
# but this file is about where a height lands in the buffer, not about terrain.
#
# ⚠️ THE FIXTURE IS A NODE IN THE TREE and is freed with this test. That is what the
# node plumbing ADR-0170 dec. 6 removed cost: `is_cliff_edge` reads `tile_vertices`
# and `global_position`, so the tiles have to exist. The plumbing is the fixture's
# now — four lines here, none of them about tiles.
func _build_fixture() -> TerrainFixture:
	var fixture := TerrainFixture.new()
	for z in range(MAP_H):
		for x in range(MAP_W):
			if x == 2 and z == 1:
				continue  # the hole → idx 5 stays empty
			fixture.put(Vector2i(x, z), x * 10 + z)
	add_child(fixture)
	return fixture


## The heart of the bug: an out-of-bounds impassable cell whose index WRAPS into
## a valid in-bounds cell. Without the bounds guard it corrupts that cell.
func _test_out_of_bounds_tile_does_not_corrupt_in_bounds_cell() -> void:
	var fixture := _build_fixture()
	# Stray impassable cell at (5,0): gx=5 ≥ MAP_W. Unguarded idx = 0*3 + 5 = 5,
	# which is the (2,1) hole cell — so height 99 would land on a live cell.
	fixture.put(Vector2i(5, 0), 99, {"impassable": true})
	var lat: Lattice = fixture.lattice

	var data := GPUBatchSimulator.build_map_data(lat, MIN_X, MIN_Z, MAP_W, MAP_H)

	_assert_eq(data.size(), TOTAL * PLANES, "buffer sized to walkable grid (9 * 10 * 2)")
	# Height section, idx 5 (the hole): must stay 0, NOT the stray cell's 99.
	_assert_eq(data[5], 0, "out-of-bounds tile did not write into the hole cell")
	_completed.append("_test_out_of_bounds_tile_does_not_corrupt_in_bounds_cell")


## A cell far outside bounds computes an index past the whole buffer — the exact
## `index '936'` overflow. With the guard it is skipped, not indexed.
func _test_far_out_of_bounds_tile_does_not_overflow() -> void:
	var fixture := _build_fixture()
	fixture.put(Vector2i(0, 50), 7, {"impassable": true})  # gz=50 → idx 150 ≫ 54
	var lat: Lattice = fixture.lattice

	var data := GPUBatchSimulator.build_map_data(lat, MIN_X, MIN_Z, MAP_W, MAP_H)
	_assert_eq(data.size(), TOTAL * PLANES, "far out-of-bounds tile skipped, size intact")
	_completed.append("_test_far_out_of_bounds_tile_does_not_overflow")


func _test_in_bounds_tiles_written_correctly() -> void:
	var lat: Lattice = _build_fixture().lattice
	var data := GPUBatchSimulator.build_map_data(lat, MIN_X, MIN_Z, MAP_W, MAP_H)

	# Cell (1,0): idx = 0*3 + 1 = 1, height = 10, passable.
	_assert_eq(data[1], 10, "in-bounds tile height written at its cell")
	_assert_eq(data[TOTAL + 1], 1, "in-bounds passable tile marked traversable")
	# Hole cell (2,1) has no cell: traversable defaults to 0.
	_assert_eq(data[TOTAL + 5], 0, "empty hole cell not traversable")
	_completed.append("_test_in_bounds_tiles_written_correctly")


# --- ADR-0218 dec. 7, the HOST half ------------------------------------------
# The addon half (`addons/exmateria_battlefield/tests/LatticeCliffEdgeTest.gd`)
# proves the RULE without a game. This proves the DELIVERY: that the port's verdict
# survives `build_map_data` and lands on the right byte of the right cell. Neither
# covers the other's half — a rule proven only in the addon would not have caught the
# file that answered `false`, because that file never called the rule.

# Cliff bytes live at `total_tiles*2 + idx*4 + dir`, and the directions are
# `build_map_data`'s own order: N(+X), E(+Z), S(-X), W(-Z).
#
# 🔴 THAT OFFSET IS UNCHANGED BY ADR-0224 and this file is one of the reasons it
# had to be. The buffer now carries eight cliff verdicts per cell — one per
# (direction, TARGET level) — but as two 4-wide groups, target level 0 first, so
# the ground-to-ground group sits exactly where the four used to. Everything this
# fixture states is level 0, so `_cliff_byte` addresses the ground-to-ground
# group and reads what it always read. The target-level-1 group is
# `total_tiles*6 + idx*4 + dir` and is all zeros here; the corpus-wide proof that
# level 0's bytes did not move is `tests/GPUMapBufferLevelRatchetTest.gd`.
const DIR_NORTH := 0   # +X
const DIR_EAST := 1    # +Z
const DIR_SOUTH := 2   # -X
const DIR_WEST := 3    # -Z


func _cliff_byte(data: PackedInt32Array, gx: int, gz: int, dir: int) -> int:
	return data[TOTAL * 2 + (gz * MAP_W + gx) * 4 + dir]


func _test_a_seeded_cliff_reaches_the_baked_buffer() -> void:
	# A two-half-step riser down the x=0/x=1 seam: column 0 at height 0, columns 1
	# and 2 at height 2. The riser's faces share no corner, so that seam is a cliff
	# and EVERY other edge on the map is level — which is what makes the assertions
	# below two-sided instead of "something is nonzero somewhere".
	var fixture := TerrainFixture.new()
	for z in range(MAP_H):
		fixture.put(Vector2i(0, z), 0)
		fixture.put(Vector2i(1, z), 2)
		fixture.put(Vector2i(2, z), 2)
	add_child(fixture)
	var lat: Lattice = fixture.lattice

	var data := GPUBatchSimulator.build_map_data(lat, MIN_X, MIN_Z, MAP_W, MAP_H)

	# The seam, from both sides. `is_cliff_edge` is symmetric, and the fill loop
	# visits each cell independently, so a one-sided bake is a real failure mode.
	_assert_eq(_cliff_byte(data, 0, 1, DIR_NORTH), 1,
		"the riser is a cliff looking +X from the low column")
	_assert_eq(_cliff_byte(data, 1, 1, DIR_SOUTH), 1,
		"…and looking -X from the high column")

	# Level ground on the same map, in the same buffer. This is the arm the hardcoded
	# `false` passed and the arm above is the one it could not: a constant answer is
	# only detectable when both answers are demanded of one run.
	_assert_eq(_cliff_byte(data, 1, 1, DIR_EAST), 0,
		"level ground along the high column is walkable (+Z)")
	_assert_eq(_cliff_byte(data, 1, 1, DIR_WEST), 0,
		"…and walkable (-Z)")
	# The far seam is level too — 1 and 2 are both height 2.
	_assert_eq(_cliff_byte(data, 1, 1, DIR_NORTH), 0,
		"two columns at one height are not a cliff")
	# An edge to nothing is not an edge: (2,1) has no +X neighbour on this map.
	_assert_eq(_cliff_byte(data, 2, 1, DIR_NORTH), 0,
		"the map edge bakes 0 — there is no neighbour to step off onto")
	_completed.append("_test_a_seeded_cliff_reaches_the_baked_buffer")


# --- ADR-0224 dec. 2/3, the LEVEL-1 half -------------------------------------
# The arm above proves the port's cliff verdict reaches the buffer's ground-to-
# ground group at the offset it has always sat at. This proves the other three
# groups exist, are addressable, and hold the right cell.
#
# 🔴 THESE ARE THE OFFSETS A READER COMPUTES, WRITTEN OUT AS LITERALS. That is
# the whole point of the arm: a size assertion — even one stated as a literal —
# is a claim a future editor can update in the same commit that moves the layout,
# because the test will be red and updating it will look like the fix. An
# assertion that a level-1 height lands at `total_tiles*10 + idx` cannot be
# satisfied that way; it fails exactly when a plane count shifts underneath it,
# which is also the moment every existing shader offset silently starts reading
# the wrong plane.
const L1_HEIGHT_BASE := TOTAL * 10
const L1_TRAVERSABLE_BASE := TOTAL * 11
const L0_CLIFF_TO_L1_BASE := TOTAL * 6


## A bridge deck over (1,1): ground at height 0 everywhere, one level-1 cell at
## height 9 — MAP083's gap (records 405/406), which is the defect ADR-0224 exists
## for and the one column where the two heights must NOT be confusable.
func _test_level_1_lands_at_the_offsets_a_reader_computes() -> void:
	var fixture := TerrainFixture.new()
	for z in range(MAP_H):
		for x in range(MAP_W):
			fixture.put(Vector2i(x, z), 0)
	fixture.put(Vector2i(1, 1), 9, {}, 1)
	add_child(fixture)
	var lat: Lattice = fixture.lattice

	var data := GPUBatchSimulator.build_map_data(lat, MIN_X, MIN_Z, MAP_W, MAP_H)
	var idx := 1 * MAP_W + 1  # (1,1) -> 4

	_assert_eq(data.size(), TOTAL * PLANES, "buffer holds both levels")

	# The deck, at its own level's offsets — and the floor under it, unmoved.
	_assert_eq(data[L1_HEIGHT_BASE + idx], 9, "the level-1 height lands in the level-1 block")
	_assert_eq(data[L1_TRAVERSABLE_BASE + idx], 1, "the level-1 cell is traversable there")
	_assert_eq(data[idx], 0, "the level-0 height under it is untouched")

	# A column with no deck has an EMPTY level-1 slot. Without this the arm above
	# passes on a build that fills the whole upper block with the ground plane.
	var bare := 0 * MAP_W + 0
	_assert_eq(data[L1_HEIGHT_BASE + bare], 0, "a column with no deck has no level-1 height")
	_assert_eq(data[L1_TRAVERSABLE_BASE + bare], 0, "…and nothing traversable there")

	# The cliff table's second group is addressable and answers about the DECK.
	# Stepping +X from (0,1) to a level-1 cell 9 half-steps up is a cliff; the
	# same step to level 0 is flat ground. One buffer, two verdicts, and the
	# ground-to-ground group must not have moved to make room for the other.
	_assert_eq(data[L0_CLIFF_TO_L1_BASE + (1 * MAP_W + 0) * 4 + DIR_NORTH], 1,
		"stepping +X onto the deck is a cliff, in the target-level-1 group")
	_assert_eq(_cliff_byte(data, 0, 1, DIR_NORTH), 0,
		"…while the same step along the ground is flat, in the group that never moved")
	_completed.append("_test_level_1_lands_at_the_offsets_a_reader_computes")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
