extends Node3D
# test-kind: logic
# seeded-break: GPUBatchSimulator.build_map_data writes the GROUND height into the upper levels' height plane (the ADR-0224 opening defect: the shader answered get_tile_height(x,z) level-0 instead of the cell's own level); all 125 'the buffer's level-1 height is the packer's U_HEIGHT' + MAP083's 'the deck reads h9 at its own level' (expected 9, got 0) RED; the level-0 ground plane, the P6 adjacency equality, the sweep, the 35/125 census, and the ROM DIRECTIONS/MODES/CLIMB cross-checks stay green; GREEN unbroken on the reverted tree

## ADR-0224's P4 and P6, over every map in the corpus that mints a walkable
## upper cell — 125 cells across 35 maps.
##
## THIS TEST TOUCHES NO GPU. Everything it asserts is a claim about two things
## that are computed on the CPU and then handed to the shader: the map buffer's
## height planes (`GPUBatchSimulator.build_map_data`) and the distance field's
## flat matrix (`DistanceFieldGenerator.get_flat_distances`). A GPU run proves
## the shader READS them; this proves they say the right thing, over the whole
## population rather than the one map a headful run can afford.
##
## The arms:
##
##   P4  — the number the shader now reads at a unit's OWN level is the number
##         the packer put in `U_HEIGHT`. ADR-0224 opens with these two
##         disagreeing: `GPUCombatPacker` packs `lattice.terrain_at(cell).height`
##         (the level-1 cell, correctly) while the shader answered
##         `get_tile_height(x, z)` — the level-0 height for the same column. On
##         MAP083 those differ by 9.
##
##   P4b — and they REALLY differed. Asserting agreement alone is green on a map
##         where both levels happen to hold the same height, so the corpus is
##         also counted by how many upper cells sit over a DIFFERENT ground
##         height. That count is the defect's own population.
##
##   P6  — `EventPathfinder` and the GPU distance field agree, cell for cell.
##         ADR-0224 dec. 5 adopts ADR-0219 dec. 6 VERBATIM rather than restating
##         it, and this is the arm that says so: the event mover floods
##         `nav.cells_at(x, z)` and the field's `_compute_neighbors` enumerates
##         the same column, so for the same start, target and climb the two must
##         return the same step count and the same reachable/unreachable verdict.
##         A divergence means dec. 5 was restated.
##
##   sweep — every walkable upper cell was flooded by the field, and the corpus
##         census (35 maps / 125 cells) still holds.
##
## 🔴 P6 WAS A STEP-COUNT EQUALITY AND IS NOW AN ADJACENCY EQUALITY. That is not
## a weakening; it is the arm finally testing what dec. 5 actually says.
##
## The original form compared `EventPathfinder.find_path`'s step count against
## `get_distance`, which was only meaningful while BOTH sides were uniform-cost
## BFS over the same graph. #822 landed the ROM's `{28} Walk To` planner
## (`plan(terrain, start, dest, cost, climb)`): a move-BUDGET flood with
## per-surface costs and a second expander that can span TWO tiles. `find_path`
## and its `nav` duck type no longer exist, and a step count against a distance
## field stopped comparing like with like the moment one side could leap.
##
## What dec. 5 rules is ADJACENCY, not search: *"Four column-to-column
## neighbours; every admissible cell of the target column is a candidate, low to
## high; the climb gate decides."* Both movers must agree on THAT however
## differently they then search it. So the arm now compares the adjacency
## relation, read two ways that share no code:
##
##   - the GPU side, off the EXPORTED matrix — the cells at distance exactly 1
##     from a source ARE that source's neighbours, so this reads the artifact the
##     shader is handed rather than any internal of the generator;
##   - the port side, from `Lattice.column_at` plus the climb gate — the same
##     terrain facts, asked directly.
##
## And the ROM's own numbers are now a THIRD reading, published by the port of
## `FUN_80178CA4`'s sibling: `EventPathfinder.DIRECTIONS == 4` and
## `MODES == 2` — *"the flood relaxes TWO records per column — level 0 and
## level 1 ... changing terrain level costs nothing and is not a fifth
## direction"*. That is dec. 5's `4 x 2` expansion confirmed from the ROM rather
## than from this repo, which is a better oracle than the old arm ever had.
##
## ⚠️ WHAT THIS ARM NO LONGER CLAIMS, and nobody should read it as claiming: that
## the two movers produce the same ROUTE. They do not, and after #822 they cannot
## — the event mover has terrain costs and a one-tile leap the GPU mover has
## neither of. Whether that divergence is FINE (they answer different questions;
## the ROM really does have two pathfinders, `FUN_8017813C` for `{28} Walk To`
## and `FUN_80178CA4` for gameplay, and only the gameplay one folds in unit
## occupancy) or a DEFECT (a player watches a cutscene cross the moat and then
## cannot do it themselves) is an open decision for the user, recorded in this
## PR and not settled here. Measured stake: 12 of these 125 cells reach no ground
## cell at all under the GPU field's single baked climb of 3.
##
## ⚠️ THE NAV ADAPTER BELOW IS NOT A RULE. `EventPathfinder` takes a duck-typed
## `nav`; this one forwards straight to `Lattice.column_at` / `terrain_at`, which
## is what `ScenarioVM`'s production adapter forwards to as well. Nothing here
## decides walkability, height or what a column offers — the port does, so the
## two movers are compared over the SAME terrain facts and a disagreement can
## only be about the search.
##
## Run: <GODOT> --path . --quit-after 100000 res://tests/GPUBridgeMoverAcceptanceTest.tscn

const MapBufferCorpus = preload("res://tests/MapBufferCorpus.gd")
const Lattice = ExMateriaBattlefield.Lattice
const EventPathfinder = ExMateriaBattlefield.EventPathfinder
const TerrainCell = ExMateriaSchema.TerrainCell

## ADR-0224 / ADR-0219 P3, and the same numbers `GPUMapBufferLevelRatchetTest`
## states. Literals for the same reason they are literals there: an arm that
## reads its expectation out of the subject follows it to any value.
const MAPS_WITH_WALKABLE_UPPER := 35
const WALKABLE_UPPER_CELLS := 125

## `DistanceFieldGenerator.generate`'s default, and `EventPathfinder` is handed
## the same number so the two searches are gated identically. ADR-0224 dec. 7
## records that this threshold is per-FIELD and not per-unit, and does not fix it.
const CLIMB := 3

## The four column-to-column steps, in this file's own words rather than fetched
## from either mover — an arm that imports its expectation from a subject follows
## that subject to any value. Cross-checked against `EventPathfinder.DIRECTIONS`
## and `MODES` below, which are the ROM's numbers and a genuinely independent
## oracle.
const NEIGHBOUR_STEPS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

## The defect ADR-0224 opens with, named by its own numbers so this file fails
## if the map it argues from stops saying what it says.
const DEFECT_MAP := "MAP083"
const DEFECT_CELL := Vector3i(4, 6, 1)
const DEFECT_GROUND_HEIGHT := 0
const DEFECT_UPPER_HEIGHT := 9

var _passed: int = 0
var _failed: int = 0

## 🔴 ARMS-RUN, NOT FAILURES. A GDScript error aborts ONLY its enclosing
## function, so a raise inside `_assert_defect_map` returns to `_ready`, which
## carries on to `_report()` and prints `N passed, 0 failed` over a section that
## never executed. Counting failures cannot see that; only counting COMPLETIONS
## can. Each section stamps itself at its END, and `_report` refuses a verdict
## unless every expected stamp is present.
##
## This was not hypothetical for this file and it has since HAPPENED.
## `EventPathfinder.find_path` — the whole subject of the P6 arm as first written
## — was deleted by #822, and the call raised rather than returning a wrong
## number. The register is what turned that into a red instead of a green test
## that checks nothing. The arm was then rebuilt on what survives (see above).
const EXPECTED_SECTIONS := ["corpus_walk", "census", "defect_map"]
var _completed: Dictionary = {}


## The port's own answer to "what is adjacent to this cell", and it decides
## nothing itself: `column_at` says what a column holds, `impassable` and the
## height gate are the port's facts. This is dec. 5's rule stated directly —
## four column-to-column steps, every admissible cell of the target column, the
## climb gate rejecting the rest.
##
## Shares no code with `DistanceFieldGenerator`, which answers the same question
## from a private `_cells` snapshot. Two implementations of one rule is the point;
## a helper that called the generator would be a tautology.
static func port_neighbours(lattice: Lattice, cell: Vector3i, climb: int) -> Array:
	var here = lattice.terrain_at(cell)
	if here == null:
		return []
	var out: Array = []
	for step in NEIGHBOUR_STEPS:
		for neighbour in lattice.column_at(cell.x + step.x, cell.y + step.y):
			if neighbour.impassable:
				continue
			if absi(neighbour.height - here.height) > climb:
				continue
			out.append(neighbour.grid)
	out.sort()
	return out


func _ready() -> void:
	var maps_with_upper := 0
	var upper_cells := 0
	var upper_over_different_height := 0
	var p6_pairs := 0
	var upper_reaching_no_ground := 0

	for map_name in MapBufferCorpus.map_names():
		var terrain: Dictionary = MapBufferCorpus.load_terrain(map_name)
		if terrain.is_empty():
			_fail("%s: terrain.json unreadable" % map_name)
			continue
		var lattice: Lattice = MapBufferCorpus.build_lattice(terrain, self)

		var walkable_upper := _walkable_upper_cells(lattice)
		if walkable_upper.is_empty():
			_teardown()
			continue
		maps_with_upper += 1
		upper_cells += walkable_upper.size()

		var field := DistanceFieldGenerator.new()
		field.generate(lattice)
		var bounds: Dictionary = field.get_stats()["bounds"]
		var min_x: int = bounds["min_x"]
		var min_z: int = bounds["min_z"]
		var width: int = bounds["max_x"] - min_x + 1
		var height: int = bounds["max_z"] - min_z + 1
		var total_tiles := width * height
		var map_data := GPUBatchSimulator.build_map_data(lattice, min_x, min_z, width, height)
		var flat := field.get_flat_distances()
		var stride := field.node_count()


		for grid in walkable_upper:
			var cell = lattice.terrain_at(grid)
			var idx := (grid.y - min_z) * width + (grid.x - min_x)

			# --- P4 -----------------------------------------------------------
			# The height plane of the unit's OWN level, at the offset the shader's
			# `get_tile_height(x, z, level)` computes: `level * PLANES_PER_LEVEL *
			# T + z * width + x`. Compared against the port's `TerrainCell.height`,
			# which is what `GPUCombatPacker` packs into `U_HEIGHT`.
			var buffer_offset := _height_offset(grid.z, idx, total_tiles)
			if buffer_offset < 0 or buffer_offset >= map_data.size():
				_fail("%s %s: height offset %d is outside a %d-int buffer" % [
					map_name, grid, buffer_offset, map_data.size()])
				continue
			_eq(map_data[buffer_offset], cell.height,
				"%s %s: the buffer's level-%d height is the packer's U_HEIGHT" % [
					map_name, grid, grid.z])

			# --- P4b ----------------------------------------------------------
			var ground = lattice.terrain_at(TerrainCell.ground(grid.x, grid.y))
			if ground != null and ground.height != cell.height:
				upper_over_different_height += 1
				_eq(map_data[_height_offset(TerrainCell.GROUND_LEVEL, idx, total_tiles)],
					ground.height,
					"%s %s: the level-0 plane still holds the GROUND height" % [
						map_name, grid])

			# --- the sweep ----------------------------------------------------
			var self_node := field.node_index(grid.x, grid.y, grid.z)
			_eq(flat[self_node * stride + self_node], 0,
				"%s %s: the field flooded from this cell" % [map_name, grid])
			var reaches_ground := false
			for gz in range(min_z, min_z + height):
				for gx in range(min_x, min_x + width):
					if flat[self_node * stride + field.node_index(gx, gz, 0)] >= 0:
						reaches_ground = true
						break
				if reaches_ground:
					break
			if not reaches_ground:
				upper_reaching_no_ground += 1

			# --- P6 — ADJACENCY, which is what dec. 5 actually rules ----------
			# The GPU side is read off the EXPORTED matrix: a cell at distance
			# exactly 1 from this source IS a neighbour of it. That reads the
			# artifact the shader is handed, not an internal of the generator, so
			# it also catches a field whose neighbour list is right and whose
			# export is not.
			var field_adjacent: Array = []
			for to_level in range(TerrainCell.LEVEL_COUNT):
				for gz in range(min_z, min_z + height):
					for gx in range(min_x, min_x + width):
						if flat[self_node * stride
								+ field.node_index(gx, gz, to_level)] == 1:
							field_adjacent.append(Vector3i(gx, gz, to_level))
			field_adjacent.sort()
			var port_adjacent := port_neighbours(lattice, grid, CLIMB)
			p6_pairs += port_adjacent.size()
			_eq(field_adjacent, port_adjacent,
				"%s %s: the field's neighbours are the port's admissible cells" % [
					map_name, grid])

		_teardown()

	_completed["corpus_walk"] = true

	# --- the corpus census ------------------------------------------------------
	_eq(maps_with_upper, MAPS_WITH_WALKABLE_UPPER, "maps minting a WALKABLE upper cell")
	_eq(upper_cells, WALKABLE_UPPER_CELLS, "walkable upper cells in the corpus")
	_completed["census"] = true

	# --- the defect's own numbers ----------------------------------------------
	_assert_defect_map()

	print("[info] %d of the %d walkable upper cells sit over a ground cell of a DIFFERENT height" % [
		upper_over_different_height, upper_cells])
	print("[info] %d upper cells reach no ground cell at climb %d" % [
		upper_reaching_no_ground, CLIMB])
	print("[info] P6 compared %d adjacency edges across %d upper cells" % [
		p6_pairs, upper_cells])

	_report()


## `level * MAP_PLANES_PER_LEVEL * total_tiles + idx` — the address the shader's
## `get_tile_height` computes, written out here rather than read off
## `GPUBatchSimulator.MAP_PLANES_PER_LEVEL`. An arm that fetches its expectation
## from the subject's own constant follows that constant to any value.
func _height_offset(level: int, idx: int, total_tiles: int) -> int:
	return level * 10 * total_tiles + idx


## MAP083 (4, 6) is ADR-0224's own worked example — record 405's deployment cell.
## Stated by its numbers so this file goes red if the map it argues from changes,
## rather than quietly proving something about a different bridge.
func _assert_defect_map() -> void:
	var terrain: Dictionary = MapBufferCorpus.load_terrain(DEFECT_MAP)
	if terrain.is_empty():
		_fail("%s: terrain.json unreadable" % DEFECT_MAP)
		return
	var lattice: Lattice = MapBufferCorpus.build_lattice(terrain, self)
	var field := DistanceFieldGenerator.new()
	field.generate(lattice)
	var bounds: Dictionary = field.get_stats()["bounds"]
	var min_x: int = bounds["min_x"]
	var min_z: int = bounds["min_z"]
	var width: int = bounds["max_x"] - min_x + 1
	var height: int = bounds["max_z"] - min_z + 1
	var total_tiles := width * height
	var map_data := GPUBatchSimulator.build_map_data(lattice, min_x, min_z, width, height)
	var idx := (DEFECT_CELL.y - min_z) * width + (DEFECT_CELL.x - min_x)

	_eq(map_data[_height_offset(DEFECT_CELL.z, idx, total_tiles)], DEFECT_UPPER_HEIGHT,
		"%s %s: the deck reads h%d at its own level" % [
			DEFECT_MAP, DEFECT_CELL, DEFECT_UPPER_HEIGHT])
	_eq(map_data[_height_offset(TerrainCell.GROUND_LEVEL, idx, total_tiles)], DEFECT_GROUND_HEIGHT,
		"%s %s: the column's GROUND still reads h%d" % [
			DEFECT_MAP, DEFECT_CELL, DEFECT_GROUND_HEIGHT])

	# P5's terrain precondition, GPU-free: the deck is not a dead end. A route off
	# it exists and its first step changes (x, z), because dec. 5 admits no
	# in-place level change — there is no "descend where you stand" move to find.
	# P5's terrain precondition, GPU-free: the deck is not a dead end. The route
	# ITSELF — and that no step in it holds (x, z) while changing level — is
	# asserted end to end by `GPUBridgeDescentTest`, which runs the real compute
	# pipeline on this same cell. Here it is only that the field says a ground
	# cell is reachable at all, so a red in the descent test can be read as the
	# MOVER failing rather than the terrain being sealed.
	var flat := field.get_flat_distances()
	var stride := field.node_count()
	var deck_node := field.node_index(DEFECT_CELL.x, DEFECT_CELL.y, DEFECT_CELL.z)
	var best := -1
	for gz in range(min_z, min_z + height):
		for gx in range(min_x, min_x + width):
			var d: int = flat[deck_node * stride + field.node_index(gx, gz, 0)]
			if d > 0 and (best < 0 or d < best):
				best = d
	if best < 0:
		_fail("%s: the deck %s reaches no ground cell — the terrain is sealed" % [
			DEFECT_MAP, DEFECT_CELL])
	else:
		_passed += 1

	# The two movers' shared adjacency, cross-checked against the ROM's OWN
	# numbers rather than this repo's. `EventPathfinder` is the port of the `{28}`
	# planner and publishes `stateA+0x54` and `stateA+0x55` as constants: four
	# directions, and TWO records relaxed per column — "changing terrain level
	# costs nothing and is not a fifth direction". That is ADR-0224 dec. 5's
	# `4 x 2` expansion, confirmed from the ROM, and it is the one cross-mover
	# oracle that survived #822 replacing the event mover wholesale.
	_eq(EventPathfinder.DIRECTIONS, NEIGHBOUR_STEPS.size(),
		"the event mover walks the same four column-to-column directions")
	_eq(EventPathfinder.MODES, TerrainCell.LEVEL_COUNT,
		"the event mover relaxes one record per LEVEL, like the GPU field")
	_eq(EventPathfinder.WALK_TO_CLIMB, CLIMB,
		"the event mover's climb literal is the field's baked threshold")
	_teardown()
	# Last line of the function on purpose: a raise anywhere above returns to the
	# caller without this stamp, and `_report` turns that into a red.
	_completed["defect_map"] = true


func _walkable_upper_cells(lattice: Lattice) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in lattice.all_cells():
		if cell.grid.z == TerrainCell.GROUND_LEVEL:
			continue
		if cell.impassable:
			continue
		out.append(cell.grid)
	out.sort()
	return out


func _teardown() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func _eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_fail("%s - expected %s, got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed += 1
	print("[FAIL] %s" % message)


func _report() -> void:
	for section in EXPECTED_SECTIONS:
		if not _completed.get(section, false):
			_failed += 1
			print("[FAIL] section '%s' never completed — an arm was aborted, not passed. A GDScript error aborts its enclosing function; the counters below describe the arms that DID run." % section)
	print("\n=== GPUBridgeMoverAcceptanceTest: %d passed, %d failed, %d/%d sections ===" % [
		_passed, _failed, _completed.size(), EXPECTED_SECTIONS.size()])
	print("[PASS] GPUBridgeMoverAcceptanceTest" if _failed == 0 else "[FAIL] GPUBridgeMoverAcceptanceTest")
	get_tree().quit(1 if _failed > 0 else 0)
