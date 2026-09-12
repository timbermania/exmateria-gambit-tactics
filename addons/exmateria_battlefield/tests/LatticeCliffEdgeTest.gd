extends Node
## Tests for `Lattice.is_cliff_edge` — the port's only real computation, and the
## sole producer of the per-neighbour cliff byte `GPUBatchSimulator` bakes into
## the GPU map buffer.
##
## 🔴 UNTIL ADR-0218 THIS RULE WAS EXECUTED BY NO TEST IN THE SUITE. Not
## under-tested — unexecuted. One double overrode `is_cliff_edge` to `false`
## outright; the other five never set `_store`, so the inherited body
## short-circuited at its null guard and also answered `false`. Six tests asked
## the question and six got a hardcoded no. That measurement is the reason
## ADR-0218 exists, and this file is the half of dec. 7 that runs without a game.
##
## THE RULE: two adjacent faces must share at least two corners, within 0.01 world
## units, or a unit must JUMP the edge rather than walk it. Fewer than two shared
## corners means one face steps off the other. The projection is translation-only
## (`vertex + global_position`) because tiles carry no rotation, and changing that
## would silently move a gameplay threshold.
##
## 🔴 THIS FILE IS ADDON-OWNED AND EVERY LEG IS SYNTHETIC (ADR-0194). The other
## half of dec. 7 lives in the host — `tests/MapBufferBoundsTest.gd` proves a
## seeded cliff reaches the baked buffer through `GPUBatchSimulator.build_map_data`
## — because a rule proven only in here would not have caught the file that
## hardcoded `false`. Neither covers the other's half.
##
## Run: `bash tests/stranger/exmateria_battlefield/run.sh`.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
const TerrainFixture = preload("res://addons/exmateria_battlefield/lattice/TerrainFixture.gd")

## And the schema façade for the cell type (ADR-0212 dec. 1). `TerrainCell.ground(x, z)`
## is how a test that means "the ground of this column" says so since ADR-0219 made the
## key a `Vector3i` — spelling it `Vector3i(x, z, 0)` would bury the level in a literal.
const TerrainCell = ExMateriaSchema.TerrainCell

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_level_ground_is_walkable()
	_test_a_step_is_a_cliff()
	_test_a_ramp_that_meets_its_neighbour_is_walkable()
	_test_a_ramp_that_misses_by_more_than_epsilon_is_a_cliff()
	_test_an_edge_to_nothing_is_not_an_edge()
	_test_a_diagonal_shares_one_corner_and_is_a_cliff()
	_test_a_bridge_deck_and_the_moat_under_it_are_one_column()

	print("\n=== LatticeCliffEdgeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] LatticeCliffEdgeTest")
		get_tree().quit(1)
	else:
		print("[PASS] LatticeCliffEdgeTest")
		get_tree().quit(0)


func _test_level_ground_is_walkable() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 3, 3), 4)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	# Two flat squares at one height share exactly the two corners of their common
	# edge — the minimum the rule accepts.
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(1, 1), TerrainCell.ground(2, 1)),
		"level ground east is walkable")
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(1, 1), TerrainCell.ground(1, 2)),
		"level ground south is walkable")
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(1, 1), TerrainCell.ground(0, 1)),
		"the rule is symmetric — west is walkable too")

	fixture.queue_free()


func _test_a_step_is_a_cliff() -> void:
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(0, 0), 0)
	fixture.put(Vector2i(1, 0), 1)   # one FFT half-step up: 12/28 = 0.4286 world
	fixture.put(Vector2i(2, 0), 0)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert(lattice.is_cliff_edge(TerrainCell.ground(0, 0), TerrainCell.ground(1, 0)),
		"a ONE half-step riser is a cliff — its corners share nothing")
	_assert(lattice.is_cliff_edge(TerrainCell.ground(1, 0), TerrainCell.ground(2, 0)),
		"and so is the drop on the far side")
	# Half a step is still 0.21 world units, which is 21x the 0.01 tolerance —
	# stated so a future epsilon change has to argue with a number.
	_assert(MapConstants.surface_y(1) - MapConstants.surface_y(0) > Lattice.VERTEX_MATCH_EPSILON,
		"one half-step exceeds VERTEX_MATCH_EPSILON by a wide margin")

	fixture.queue_free()


func _test_a_ramp_that_meets_its_neighbour_is_walkable() -> void:
	# The case the game is actually about: a sloped tile bridging two heights. Its
	# high edge is flush with the high neighbour, its low edge with the low one, so
	# a unit walks both — and the SAME two tiles were a cliff apart in the previous
	# leg. GDScript has no rule that turns `slope_type` into lifted corners (the
	# exporter bakes them), so a slope is stated with `put_shape`. That is dec. 6's
	# escape hatch doing the job it was kept for.
	var low := MapConstants.surface_y(0)
	var high := MapConstants.surface_y(2)

	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(0, 0), 0)                 # flat, low
	fixture.put(Vector2i(0, 2), 2)                 # flat, high
	fixture.put_shape(Vector2i(0, 1), PackedVector3Array([
		Vector3(0, high, 2), Vector3(0, low, 1), Vector3(1, low, 1), Vector3(1, high, 2),
	]), 1)                                         # the ramp between them
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert(not lattice.is_cliff_edge(TerrainCell.ground(0, 1), TerrainCell.ground(0, 0)),
		"the ramp's LOW edge meets the low tile — walkable")
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(0, 1), TerrainCell.ground(0, 2)),
		"the ramp's HIGH edge meets the high tile — walkable")
	_assert(lattice.is_cliff_edge(TerrainCell.ground(0, 0), TerrainCell.ground(0, 2)),
		"…and the two flats the ramp joins are not adjacent to each other")

	fixture.queue_free()


func _test_a_ramp_that_misses_by_more_than_epsilon_is_a_cliff() -> void:
	# The tolerance is 0.01 world units and it is a THRESHOLD, not a rounding
	# convenience. A ramp landing 0.02 short of its neighbour is a cliff; the same
	# ramp landing 0.005 short is not.
	var low := MapConstants.surface_y(0)
	var high := MapConstants.surface_y(2)

	var near: Lattice = _ramp_lattice(high - 0.005, low)
	_assert(not near.is_cliff_edge(TerrainCell.ground(0, 1), TerrainCell.ground(0, 2)),
		"a ramp 0.005 short of its neighbour still meets it (< 0.01)")

	var far: Lattice = _ramp_lattice(high - 0.02, low)
	_assert(far.is_cliff_edge(TerrainCell.ground(0, 1), TerrainCell.ground(0, 2)),
		"a ramp 0.02 short of its neighbour does NOT (> 0.01)")


func _test_an_edge_to_nothing_is_not_an_edge() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 2, 2), 5)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	# `false` when either cell is absent: both former callers guarded for a null
	# tile and took the non-cliff branch, so the port answers as they did.
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(1, 1), TerrainCell.ground(2, 1)),
		"an edge to an empty square is not a cliff")
	_assert(not lattice.is_cliff_edge(TerrainCell.ground(9, 9), TerrainCell.ground(9, 8)),
		"nor is an edge between two empty squares")

	fixture.queue_free()


func _test_a_diagonal_shares_one_corner_and_is_a_cliff() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 2, 2), 3)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	# Not a case gameplay asks about — `build_map_data` walks four cardinals — but
	# it is the rule's boundary: ONE shared corner, and one is not two.
	_assert(lattice.is_cliff_edge(TerrainCell.ground(0, 0), TerrainCell.ground(1, 1)),
		"level diagonals share ONE corner, and the rule wants two")

	fixture.queue_free()


func _test_a_bridge_deck_and_the_moat_under_it_are_one_column() -> void:
	# ADR-0219's case, stated as terrain: MAP009 (4,11) is a moat AND the bridge over
	# it. Before the key was a `Vector3i` this fixture could not express the column at
	# all — the second `put` overwrote the first — so no test in the suite could ask
	# the cliff rule a cross-level question.
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(3, 11), 7)                # bank, at deck height
	fixture.put(Vector2i(4, 11), 1)                # the moat floor
	fixture.put(Vector2i(4, 11), 7, {}, 1)         # the BRIDGE over it
	fixture.put(Vector2i(5, 11), 7)                # far bank
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	var deck := Vector3i(4, 11, 1)
	_assert(lattice.terrain_at(deck) != null and lattice.terrain_at(TerrainCell.ground(4, 11)) != null,
		"both cells of the column exist — the level is part of the identity")
	_assert(lattice.column_at(4, 11).size() == 2,
		"and the column reports both of them")

	# 🔴 `is_cliff_edge` NEEDED NO NEW POLICY. Its verdict is computed from the two
	# faces' world-space corners, so an exact cell key is the whole of what it wanted:
	# the deck meets the bank it is flush with, and does not meet the moat six
	# half-steps below — which is the question that used to be unaskable.
	_assert(not lattice.is_cliff_edge(deck, TerrainCell.ground(3, 11)),
		"the deck meets the bank at its own height — walkable")
	_assert(not lattice.is_cliff_edge(deck, TerrainCell.ground(5, 11)),
		"and the far bank too — a bridge is walkable from both ends")
	_assert(lattice.is_cliff_edge(TerrainCell.ground(3, 11), TerrainCell.ground(4, 11)),
		"the bank to the MOAT FLOOR is still a cliff — the deck did not launder it")

	fixture.queue_free()


# A ramp from (0,1) whose HIGH edge sits at `ramp_high` against a flat high tile
# at (0,2), and whose low edge sits at `low` against a flat low tile at (0,0).
func _ramp_lattice(ramp_high: float, low: float) -> Lattice:
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(0, 0), 0)
	fixture.put(Vector2i(0, 2), 2)
	fixture.put_shape(Vector2i(0, 1), PackedVector3Array([
		Vector3(0, ramp_high, 2), Vector3(0, low, 1),
		Vector3(1, low, 1), Vector3(1, ramp_high, 2),
	]), 1)
	add_child(fixture)
	# The handle is bound to a `Lattice`-annotated slot before it leaves: a chained
	# `fixture.lattice.x()` is the duck-typed reach `check_lattice_ports` scores.
	var lattice: Lattice = fixture.lattice
	return lattice


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
