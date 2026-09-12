extends Node3D
# test-kind: logic
# seeded-break: GPUBatchSimulator.build_map_data skips every non-ground level (`continue` when level != GROUND_LEVEL — the ADR-0224 widening writes nothing above level 0); 'traversable bits set in the level-1 block' RED (expected 125, got 0) — the arm the docstring names for a widening that never landed; the level-0 byte-identity ratchet, the golden arms, the growth ratio, and the distance-field arms stay green; GREEN unbroken on the reverted tree

## ADR-0224's P1, over the whole exported map corpus.
##
## The GPU map buffer grew a second plane so a unit can stand on a bridge
## (ADR-0224 dec. 1/2/3). Dec. 8 refuses a feature flag and puts the assurance
## HERE instead: the buffer is LEVEL-MAJOR, so level 0 occupies exactly the bytes
## it occupied before the widening, and the 74 exported maps that mint no cell
## above the ground must therefore come out byte-identical to what they held at
## `3f4658f3c`. That property is the only mechanical proof that widening the
## storage moved nothing, and it is what lets the shader pass land separately.
##
## 🔴 THE GOLDEN WAS TAKEN BEFORE THE WIDENING and regenerating it disarms every
## arm below — see `tools/gen_map_buffer_golden.gd`. `tests/MapBufferCorpus.gd`
## holds the measurement both sides run, so the golden and this test cannot drift
## into measuring different things.
##
## The arms, and what each one alone would let through:
##   1. corpus census        — a shrunken corpus, or an empty A/B population
##   2. golden coverage      — a map added and the golden never retaken
##   3. ground-prefix sha    — THE RATCHET: level 0's bytes moved
##   4. distance-field ground submatrix — level 0's ROUTES moved (PR B: the
##      field widened to two planes, and the arm survived the widening because
##      the golden's `dist_sha` already IS the ground block — see below)
##   5. bounds              — the walkable box moved
##   6. buffer size         — the buffer did not actually grow
##   7. inert upper block   — the 74 gained a non-zero byte from nowhere
##   8. the upper block is POPULATED — arms 1-7 are all green if the widening
##      writes nothing at all, so this is the arm that says it landed
##   9. the golden was taken on a SIX-plane buffer — a regenerated golden
##  10. the level-1 bytes land at the literal offsets a READER computes
##  11. the field grew by LEVEL_COUNT^2, stated against the GOLDEN's length
##  12. the field's upper plane is POPULATED — the distance-field analogue of
##      arm 8, and the arm that fails on a widening that allocated and flooded
##      nothing
##
## 🔴 ARM 4 IS THE ONE PR B MOVED, AND IT WAS NOT RE-TAKEN. ADR-0224 dec. 1
## quadruples the flat matrix, so `dist_sha` — a hash of the whole array — stopped
## being comparable and the obvious response is to regenerate the golden. That
## would prove nothing: a hash of the new array agrees with itself. Instead the
## arm now compares the golden's `dist_sha` against `dist_ground_sha`, the
## ground-to-ground block pulled back out of the widened matrix, because before
## the widening the whole array WAS that block. Same bytes, different address.
## Arm 4b pins that reading of the golden rather than trusting this paragraph.
##
## Arm 4 is scoped to the 74. On a map that mints a walkable level-1 cell a
## ground-to-ground route may legitimately shorten by hopping through the upper
## plane, so byte-identity there would be asserting the widening did nothing.
## Dec. 8 scopes its A/B to the 74 for the same reason. How many of the 45 DID
## move is reported as a number, not asserted — it is a measurement of what the
## second plane changed, and nothing in the ADR predicts it.
##
## 🔴 ARMS 9 AND 10 EXIST BECAUSE THE OBVIOUS SIZE CHECK CANNOT FAIL. An arm that
## asserts `map_data.size() == total_tiles * MAP_PLANES_PER_LEVEL * LEVEL_COUNT`
## reads the number it is checking out of the subject, so it follows that constant
## to any value and objects to none — and this file's whole reason to exist is a
## layout ADR-0224 states two ways (dec. 2 says twelve planes, dec. 3's eight cliff
## bits per cell make it twenty). Asserting `MAP_PLANES_PER_LEVEL == 10` only moves
## that one hop: it is still a claim about the constant, and it stays green if the
## layout later migrates to a header the packer no longer reads.
##
## So the layout is pinned two ways that a constant edit cannot satisfy. Arm 9
## leans on the GOLDEN, which was written by a tool that had no idea it would be
## evidence and agrees across all 119 maps. Arm 10 asserts the literal OFFSETS a
## consumer computes, which is the buffer's actual contract.
##
## Run: <GODOT> --path . --quit-after 100000 res://tests/GPUMapBufferLevelRatchetTest.tscn

const MapBufferCorpus = preload("res://tests/MapBufferCorpus.gd")
const Lattice = ExMateriaBattlefield.Lattice
const TerrainCell = ExMateriaSchema.TerrainCell

## `10 planes x 2 levels` — each level's block is the pre-ADR-0224 buffer
## (`heights | traversable | cliff x 4`) plus a second 4-wide cliff group for the
## other target level. A LITERAL, not `GPUBatchSimulator.MAP_PLANES_PER_LEVEL`:
## an arm that reads its expectation out of the subject follows that constant to
## any value and objects to none.
const TOTAL_PLANES := 20

## `LEVEL_COUNT^2`. The distance field is a PAIRWISE matrix over nodes, so adding
## a second plane multiplies it by four, not two. A literal for the same reason
## `TOTAL_PLANES` is one.
const LEVEL_SQUARED := 4

## ADR-0224 / ADR-0219 P3, as counted by `DynamicTerrainBuilder._slot_is_occupied`
## over `assets/maps/*/terrain.json`. Stated rather than derived because these are
## the numbers every sizing argument in ADR-0224 rests on: if the corpus stops
## holding them, the ADR's A/B population is not what it says it is.
##
## ⚠️ THEY DESCRIBE THE EXPORT, NOT THE ROM, AND THE EXPORT IS KNOWN LOSSY.
## `tools/fft_exporter/__main__.py` writes `MapArrangementState.PRIMARY` and
## discards the other five arrangements, and only 119 of the ROM's 128 maps are
## exported at all (#792). MAP058 is that issue's named counterexample AND IT IS
## ONE OF THE 74: its export carries zero level-1 tiles, yet scenarios 235 and
## 236 both `Warp Unit` to `(4, 10)` with `Z=1`. So at least one of the 74 is a
## false member, and 125 is a FLOOR on the walkable upper cells, not the count.
##
## That does not weaken the arms these feed — dec. 8's A/B population only has to
## be a set of maps whose buffers must not move, and it is one whichever
## arrangement the exporter picks. It changes how a future red should be READ: if
## #792 lands and non-primary arrangements start being written, arms 1, 7 and 8
## go red TOGETHER, and that is the export changing rather than the map buffer
## breaking. Re-take the three numbers, say which commit moved them, and leave
## `build_map_data` alone.
const CORPUS_MAPS := 119
const MAPS_WITHOUT_UPPER := 74
const WALKABLE_UPPER_CELLS := 125

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var golden := MapBufferCorpus.read_golden()
	if golden.is_empty():
		_fail("golden %s is missing or unreadable" % MapBufferCorpus.GOLDEN_PATH)
		_report()
		return

	var names := MapBufferCorpus.map_names()
	var without_upper := 0
	var walkable_upper := 0
	var upper_traversable_bits := 0
	var field_upper_sources := 0
	var ground_routes_moved := 0

	for map_name in names:
		var terrain: Dictionary = MapBufferCorpus.load_terrain(map_name)
		if terrain.is_empty():
			_fail("%s: terrain.json unreadable" % map_name)
			continue
		var lattice: Lattice = MapBufferCorpus.build_lattice(terrain, self)
		var has_upper := MapBufferCorpus.has_upper_cells(lattice)
		if not has_upper:
			without_upper += 1

		if not golden.has(map_name):
			# Arm 2. A map with no golden row is not a red about this map — it is
			# a red about the ratchet, which now covers less than it claims.
			_fail("%s: no golden row (the corpus grew and the golden was not retaken)" % map_name)
			_teardown()
			continue
		var want: Dictionary = golden[map_name]
		var got := MapBufferCorpus.measure(lattice)

		# Arm 5 — the walkable box the buffer is indexed on.
		_eq(got["min_x"], int(want["min_x"]), "%s min_x" % map_name)
		_eq(got["min_z"], int(want["min_z"]), "%s min_z" % map_name)
		_eq(got["width"], int(want["width"]), "%s width" % map_name)
		_eq(got["height"], int(want["height"]), "%s height" % map_name)

		# Arm 3 — THE RATCHET. Level 0's six planes, byte for byte.
		_eq(got["ground_sha"], String(want["ground_sha"]),
			"%s level-0 block is byte-identical" % map_name)

		var total_tiles: int = got["total_tiles"]

		# Arm 4b — THE GOLDEN'S FIELD WAS ONE PLANE, and this is what lets arm 4
		# read its `dist_sha` as a ground-submatrix hash. Same shape as arm 9: a
		# statement about which artifact the golden describes, checked against the
		# golden's own recorded length rather than against any current constant.
		_eq(int(want["dist_size"]), total_tiles * total_tiles,
			"%s golden's distance field was one plane" % map_name)

		# Arm 11 — the field grew by LEVEL_COUNT^2 (it is a pairwise matrix, so
		# doubling the nodes quadruples it). Cross-multiplied against the GOLDEN's
		# length so it stays integer-exact and never reads its expectation out of
		# the subject.
		_eq(got["dist_size"], int(want["dist_size"]) * LEVEL_SQUARED,
			"%s distance field is %dx the pre-ADR-0224 field" % [map_name, LEVEL_SQUARED])

		# Arm 4 — THE RATCHET, second half. Level 0's ROUTES, byte for byte, on the
		# 74 maps dec. 8 scopes its A/B to. `dist_ground_sha` is the widened
		# matrix's top-left `total_tiles x total_tiles` corner; the golden's
		# `dist_sha` is the whole pre-widening array, which was exactly that corner.
		if not has_upper:
			_eq(got["dist_ground_sha"], String(want["dist_sha"]),
				"%s ground-to-ground distances are byte-identical" % map_name)
		elif got["dist_ground_sha"] != String(want["dist_sha"]):
			# Not an arm. A map with a walkable deck may legitimately route a
			# ground pair over it, and no decision in ADR-0224 predicts how many
			# do. Counted so the number is on the record instead of inferred.
			ground_routes_moved += 1

		# Arm 12 — the field's upper plane is populated. Every arm above is green
		# if `get_flat_distances` allocates four times the ints and floods only the
		# ground plane, which is precisely the widening-that-did-nothing this
		# whole file exists to refuse.
		var upper_sources: int = got["dist_upper_sources"]
		if upper_sources < 0:
			_fail("%s: distance field is not a square matrix (%d ints)" % [
				map_name, int(got["dist_size"])])
		elif not has_upper and upper_sources != 0:
			_fail("%s mints no upper cell but the field flooded %d level-1 nodes" % [
				map_name, upper_sources])
		else:
			if not has_upper:
				_passed += 1
			field_upper_sources += upper_sources

		# Arm 9 — THE GOLDEN IS A WITNESS, and this is what makes it one. Its
		# `map_size` was recorded by `gen_map_buffer_golden.gd` against the
		# pre-widening buffer, which was six planes and one level. Nothing else
		# in this file would notice a REGENERATED golden — and regenerating it
		# silently disarms arms 3 and 4, which are the ratchet. This says out
		# loud which buffer the golden describes.
		_eq(int(want["map_size"]), total_tiles * MapBufferCorpus.GROUND_PREFIX_PLANES,
			"%s golden was taken on a %d-plane, single-level buffer" % [
				map_name, MapBufferCorpus.GROUND_PREFIX_PLANES])

		# Arm 6 — the buffer grew, stated as a whole-number ratio against the
		# GOLDEN's length rather than against `MAP_PLANES_PER_LEVEL`. Cross-
		# multiplied so it stays integer-exact, and phrased about two measured
		# buffers rather than about the constant that sized one of them.
		_eq(got["map_size"] * MapBufferCorpus.GROUND_PREFIX_PLANES,
			int(want["map_size"]) * TOTAL_PLANES,
			"%s buffer is %d/%d of the pre-ADR-0224 buffer" % [
				map_name, TOTAL_PLANES, MapBufferCorpus.GROUND_PREFIX_PLANES])

		var stats := _upper_stats(lattice, got)
		if stats.get("short_buffer", false):
			# Already reported by name. Folding its zeros into the corpus totals
			# would red arms 1 and 8 as well and bury the one arm that said why.
			_teardown()
			continue
		walkable_upper += stats["walkable_cells"]
		upper_traversable_bits += stats["traversable_bits"]

		# Arm 7 — on a map with no upper cell, every int past level 0's block is
		# zero. This is dec. 8's A/B population stated positively: the widening
		# did not merely leave level 0 alone, it wrote nothing at all.
		if not has_upper and stats["nonzero_past_ground"] != 0:
			_fail("%s mints no upper cell but %d ints past the level-0 block are non-zero" % [
				map_name, stats["nonzero_past_ground"]])
		elif not has_upper:
			_passed += 1

		_teardown()

	# Arm 1 — the corpus, and dec. 8's A/B population inside it.
	_eq(names.size(), CORPUS_MAPS, "exported maps with a terrain.json")
	_eq(without_upper, MAPS_WITHOUT_UPPER, "maps minting no cell above the ground")

	# Arm 8 — the upper block is actually written. Every arm above stays green if
	# `build_map_data` allocates twenty planes and fills only the first six, so
	# this is the arm that fails on a widening that never landed. The two counts
	# are taken two different ways — one off the lattice, one off the buffer — so
	# they also catch an upper cell landing on the wrong index.
	_eq(walkable_upper, WALKABLE_UPPER_CELLS,
		"walkable level-1 cells in the corpus (ADR-0224 sizing)")
	_eq(upper_traversable_bits, WALKABLE_UPPER_CELLS,
		"traversable bits set in the level-1 block")

	# Arm 12's corpus total. Taken a THIRD way — off the exported distance
	# matrix's diagonal — so it also catches an upper cell that reached the map
	# buffer but not the field, which is the shape a half-applied widening takes.
	_eq(field_upper_sources, WALKABLE_UPPER_CELLS,
		"level-1 nodes the distance field flooded from")

	print("[info] %d of the %d maps with upper cells route a ground pair differently now" % [
		ground_routes_moved, CORPUS_MAPS - MAPS_WITHOUT_UPPER])

	_report()


## Everything this test wants to know about one map's upper half, in one pass:
## the lattice's own count of walkable level-1 cells, the buffer's count of
## traversable bits in the level-1 block, and whether anything at all was written
## past the level-0 block.
## `measured` is `MapBufferCorpus.measure`'s row, so the distance field is not
## generated a second time -- it is the expensive half and it has already run.
func _upper_stats(lattice: Lattice, measured: Dictionary) -> Dictionary:
	var min_x: int = measured["min_x"]
	var min_z: int = measured["min_z"]
	var width: int = measured["width"]
	var height: int = measured["height"]
	var total_tiles: int = measured["total_tiles"]
	var data := GPUBatchSimulator.build_map_data(lattice, min_x, min_z, width, height)

	# 🔴 A TEST MUST FAIL, NOT HANG, and this one did. Seeding the defect this
	# file exists to catch — `MAP_PLANES_PER_LEVEL` "corrected" to dec. 2's four
	# cliff planes — shrinks the buffer, and the reads below then index off the
	# end. A GDScript index error aborts only its enclosing function, so
	# `_upper_stats` returned nothing, `_ready` died on the missing key, no
	# verdict was ever printed, and the scene sat there until `--quit-after`
	# 100000 frames ran out. The runner scores that HUNG, which is a red about
	# the harness rather than a red that names the layout.
	#
	# So the size is checked BEFORE anything is indexed, and a short buffer is
	# reported and returned from rather than walked into.
	if data.size() < total_tiles * TOTAL_PLANES:
		_fail("buffer is %d ints, expected %d (%d tiles x %d planes) — the layout moved" % [
			data.size(), total_tiles * TOTAL_PLANES, total_tiles, TOTAL_PLANES])
		return {"walkable_cells": 0, "traversable_bits": 0, "nonzero_past_ground": 0,
			"short_buffer": true}

	var walkable := 0
	for cell in lattice.all_cells():
		if cell.grid.z == TerrainCell.GROUND_LEVEL or cell.impassable:
			continue
		var gx := cell.grid.x - min_x
		var gz := cell.grid.y - min_z
		if gx < 0 or gx >= width or gz < 0 or gz >= height:
			# ADR-0224 sizing: zero of the 125 lie outside the ground plane's
			# walkable box, so this branch never runs -- and says so if it does.
			_fail("upper cell %s lies outside the walkable box" % str(cell.grid))
			continue
		walkable += 1

	var ground_block := total_tiles * MapBufferCorpus.GROUND_PREFIX_PLANES
	var level_block := total_tiles * GPUBatchSimulator.MAP_PLANES_PER_LEVEL
	var traversable_base := level_block + total_tiles
	var bits := 0
	for idx in range(total_tiles):
		if data[traversable_base + idx] != 0:
			bits += 1

	var nonzero := 0
	for i in range(ground_block, data.size()):
		if data[i] != 0:
			nonzero += 1

	return {
		"walkable_cells": walkable,
		"traversable_bits": bits,
		"nonzero_past_ground": nonzero,
	}


func _teardown() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func _eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s - expected %s, got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed += 1
	print("[FAIL] %s" % message)


func _report() -> void:
	print("\n=== GPUMapBufferLevelRatchetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] GPUMapBufferLevelRatchetTest")
		get_tree().quit(1)
	else:
		print("[PASS] GPUMapBufferLevelRatchetTest")
		get_tree().quit(0)
