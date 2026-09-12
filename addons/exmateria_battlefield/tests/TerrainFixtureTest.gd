extends Node
## Tests for `TerrainFixture` — the addon's shipped way to stand a `Lattice` up
## from data (ADR-0218 dec. 2).
##
## 🔴 THIS FILE IS ADDON-OWNED AND EVERY LEG IS SYNTHETIC (ADR-0194). The fixture
## reaches nothing but its own addon: `DynamicTerrainBuilder`, `TerrainIndex`,
## `Tile`, `Lattice`, `MapConstants`. There is no host content in any assertion,
## so it runs under the stranger rig, which is what a fixture published for host
## tests to use had better be able to do.
##
## What is pinned, and why each one is a thing the ten doubles this replaced got
## wrong (ADR-0218 Context):
##
##   * the tile-centre convention — `world_position_at` is `(gx+0.5, y, gz+0.5)`,
##     which the doubles spelled four different ways, three of them wrong;
##   * every `TerrainCell` field arrives, not just `grid` — five of six doubles
##     dropped `height` and all six dropped `unselectable`, `pass_through_only`
##     and `surface_type` on the floor;
##   * maps are BOUNDED (dec. 4) — three doubles were not, so their consumers
##     never met a map edge;
##   * the half-step height rule is the exporter's, and the fallback in
##     `DynamicTerrainBuilder` now agrees with it (dec. 5) — as does its corner
##     ORDER, which dec. 5 left open and #749 closed.
##
## The cliff rule gets its own file, `LatticeCliffEdgeTest.gd` — it is the port's
## only real computation and dec. 7 is about it specifically.
##
## Run: `bash tests/stranger/exmateria_battlefield/run.sh`, which globs its
## addon's `tests/*.tscn`. ADR-0194 dec. 4 forbids running it as
## `res://tests/X.tscn` in the host project.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const MapConstants = preload("res://addons/exmateria_battlefield/lattice/MapConstants.gd")
const TerrainFixture = preload("res://addons/exmateria_battlefield/lattice/TerrainFixture.gd")
const DynamicTerrainBuilder = preload("res://addons/exmateria_battlefield/terrain/DynamicTerrainBuilder.gd")
const TerrainIndexStore = preload("res://addons/exmateria_battlefield/lattice/TerrainIndex.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` publishes one name; this keeps the
## use sites below spelled the way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

const EPS: float = 0.0005

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_flat_is_bounded()
	_test_tile_centre_convention()
	_test_half_step_height_rule()
	_test_every_cell_field_arrives()
	_test_a_hole_is_a_cell_never_put()
	_test_put_shape_states_a_fractional_world_y()
	_test_the_port_object_survives_a_rebuild()
	_test_the_builder_fallback_states_no_rule_of_its_own()
	_test_a_column_holds_two_cells()

	print("\n=== TerrainFixtureTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 or _failed > 0:
		print("[FAIL] TerrainFixtureTest")
		get_tree().quit(1)
	else:
		print("[PASS] TerrainFixtureTest")
		get_tree().quit(0)


# --- dec. 4: fixture maps are bounded ----------------------------------------

func _test_flat_is_bounded() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 3, 3))
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert_eq(lattice.all_cells().size(), 9, "flat(3x3) indexes nine cells")
	_assert_true(lattice.terrain_at(TerrainCell.ground(1, 1)) != null, "an in-bounds square has a cell")
	_assert_true(lattice.terrain_at(TerrainCell.ground(3, 0)) == null, "one square past the east edge is null")
	_assert_true(lattice.terrain_at(TerrainCell.ground(-1, 0)) == null, "one square west of the origin is null")
	_assert_true(lattice.terrain_at(TerrainCell.ground(0, 3)) == null, "one square past the south edge is null")
	# The unbounded doubles answered `Vector3.ZERO` here rather than nothing.
	_assert_true(lattice.world_position_at(TerrainCell.ground(3, 0)) == Vector3.ZERO,
		"an absent square has no world position")

	fixture.queue_free()


# --- dec. 3: production's tile-centre convention is the only convention -------

func _test_tile_centre_convention() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 4, 4))
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	# A tile sits at the MEAN of its four world corners, so a flat square spanning
	# [gx, gx+1] x [gz, gz+1] is centred at gx+0.5 / gz+0.5. Corner (`(x, y, z)`),
	# origin (`Vector3.ZERO`) and node-position spellings were all in the tree.
	var y0: float = MapConstants.surface_y(0)
	_assert_vec(lattice.world_position_at(TerrainCell.ground(1, 2)), Vector3(1.5, y0, 2.5),
		"world_position_at(1,2) is the tile CENTRE")
	_assert_vec(lattice.world_position_at(TerrainCell.ground(0, 0)), Vector3(0.5, y0, 0.5),
		"the origin square is centred at (0.5, ., 0.5), not at the origin")

	# And the corners are re-expressed relative to that centre — a zero centroid is
	# what lets `Lattice._world_vertices` stay translation-only.
	var tile := lattice._tile_at(TerrainCell.ground(1, 2))
	var centroid := Vector3.ZERO
	for v in tile.tile_vertices:
		centroid += v
	_assert_vec(centroid / 4.0, Vector3.ZERO, "tile_vertices sum to zero about the centre")

	fixture.queue_free()


# --- dec. 5: one height -> vertex rule ---------------------------------------

func _test_half_step_height_rule() -> void:
	# The exporter's arithmetic, stated as a number rather than re-derived:
	# `base_y = (height + depth) * 12 + 1`, in PSX units, over the 28 a tile spans.
	# Multiplying the answer BACK into PSX units is what keeps the expectation
	# independent of the divisor — and keeps the tile span reached through its one
	# owner rather than re-typed as a literal 28 (ADR-0091). A shipped
	# `terrain.json` would be the other witness and is HOST content a stranger
	# project does not have (ADR-0194 dec. 4), so the constants are checked here and
	# the map corpus is checked by the exporter's own round trip.
	var per_tile: float = float(MapConstants.PSX_UNITS_PER_TILE)
	_assert_near(MapConstants.surface_y(0) * per_tile, 1.0, "h=0 sits one PSX unit proud")
	_assert_near(MapConstants.surface_y(10) * per_tile, 121.0, "h=10 -> 12h+1 = 121")
	_assert_near(MapConstants.surface_y(12) * per_tile, 145.0, "h=12 -> 145")
	_assert_near(MapConstants.surface_y(10, 2) * per_tile, 145.0, "depth counts as height does")
	# The rule the fallback used to write instead: 0.25 * h * TILE_SCALE.
	_assert_true(absf(MapConstants.surface_y(10) - 10.0 * 0.25 * MapConstants.TILE_SCALE) > 0.1,
		"the rule is NOT the fallback's old 0.4464h (they differ by >0.1 at h=10)")

	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(0, 0), 12)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice
	_assert_near(lattice.world_position_at(TerrainCell.ground(0, 0)).y * per_tile, 145.0,
		"a put(h=12) square surfaces at the exporter's Y")
	fixture.queue_free()


# --- dec. 3 / the Context measurement: the doubles dropped five of six fields --

func _test_every_cell_field_arrives() -> void:
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(2, 3), 7, {
		"impassable": true,
		"unselectable": true,
		"pass_through_only": true,
		"surface_type": "Waterway",
	})
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	var cell: TerrainCell = lattice.terrain_at(TerrainCell.ground(2, 3))
	_assert_true(cell != null, "the stated square has a cell")
	if cell != null:
		_assert_true(cell.grid == TerrainCell.ground(2, 3), "cell.grid")
		_assert_eq(cell.height, 7, "cell.height — five of six doubles dropped this")
		_assert_true(cell.impassable, "cell.impassable")
		_assert_true(cell.unselectable, "cell.unselectable — NOTHING seeded this before")
		_assert_true(cell.pass_through_only, "cell.pass_through_only — likewise")
		_assert_eq(cell.surface_type, "Waterway", "cell.surface_type — likewise")

	fixture.queue_free()


func _test_a_hole_is_a_cell_never_put() -> void:
	var fixture := TerrainFixture.new()
	for gz in range(3):
		for gx in range(3):
			if gx == 2 and gz == 1:
				continue
			fixture.put(Vector2i(gx, gz), 0)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert_eq(lattice.all_cells().size(), 8, "eight cells over a 3x3 with one hole")
	_assert_true(lattice.terrain_at(TerrainCell.ground(2, 1)) == null, "the hole answers null")
	_assert_true(lattice.terrain_at(TerrainCell.ground(2, 0)) != null, "its neighbour does not")

	fixture.queue_free()


# --- dec. 6: put_shape is what makes a fractional world Y statable ------------

func _test_put_shape_states_a_fractional_world_y() -> void:
	var fixture := TerrainFixture.new()
	# 3.25 is a real load-bearing number — `ScenarioCameraSwoopMonotonicTest`'s
	# settled floor — and it is OFF the half-step ladder: `(12h+1)/28 = 3.25` wants
	# `h = 7.5`. No `put` can state it, which is the whole reason `put_shape` exists
	# (dec. 8: the swoop test's 8.18 / 0.46 / 3.25 convert because of this verb).
	var y := 3.25
	fixture.put_shape(Vector2i(7, 4), PackedVector3Array([
		Vector3(7, y, 5), Vector3(7, y, 4), Vector3(8, y, 4), Vector3(8, y, 5),
	]))
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert_vec(lattice.world_position_at(TerrainCell.ground(7, 4)), Vector3(7.5, y, 4.5),
		"put_shape lands the tile at the mean of the corners it was given")

	fixture.queue_free()


# --- the port object is stable across a rebuild -------------------------------

func _test_the_port_object_survives_a_rebuild() -> void:
	var fixture := TerrainFixture.flat(Rect2i(0, 0, 2, 2))
	add_child(fixture)
	var lattice: Lattice = fixture.lattice
	_assert_eq(lattice.all_cells().size(), 4, "four cells before")

	fixture.put(Vector2i(5, 5), 3)
	# The SAME handle, taken before the put, must see the new terrain — the reason
	# `Lattice._bind` exists at all (a consumer that took its handle at boot would
	# otherwise answer for the previous map).
	_assert_eq(lattice.all_cells().size(), 5, "the handle taken earlier sees the new cell")
	var again: Lattice = fixture.lattice
	_assert_true(again == lattice, "and it is the same port object")

	fixture.queue_free()


# --- dec. 5's side effect: the fallback now agrees ----------------------------

func _test_the_builder_fallback_states_no_rule_of_its_own() -> void:
	# The private flat-quad fallback fires for a row missing `vertices` — a row no
	# shipped `terrain.json` produces, which is how it came to disagree with the
	# exporter TWICE, unnoticed: on height (`0.25 * h * TILE_SCALE` = 0.4464h vs
	# 0.4286h + 0.0357, ADR-0218 dec. 5) and on corner order (the reverse cycle,
	# #749). Driving the builder directly is the only way to reach it, and these
	# are the assertions that close both.
	# (It `push_warning`s by design; that is the builder telling the truth.)
	var index: TerrainIndexStore = TerrainIndexStore.new()
	var builder := DynamicTerrainBuilder.new()
	builder.initialize(index)
	builder.add_terrain({"terrain": {"level_0": [[
		{"x": 0, "z": 0, "height": 10},
		{"x": 2, "z": 3, "height": 4},
	]]}}, "fallback", Vector2i.ZERO)

	var tile := index.get_tile(TerrainCell.ground(0, 0))
	_assert_true(tile != null, "the fallback still mints a tile")
	if tile != null:
		_assert_near(tile.position.y, MapConstants.surface_y(10),
			"a vertex-less row surfaces at the SHARED rule, not the old 0.4464h")
		tile.free()

	# The corner order, spelled out rather than fetched from `flat_quad`. Asking
	# the fallback to match the function it now calls would assert nothing; the
	# order below is the exporter's, read off `assets/maps/*/terrain.json` — all
	# 28,930 shipped tiles carry it — so this leg fails if EITHER side moves.
	# A non-origin tile, because the reversed cycle this replaced also had four
	# distinct corners and differed only in which index held which.
	var far := index.get_tile(TerrainCell.ground(2, 3))
	_assert_true(far != null, "the fallback mints a tile away from the origin too")
	if far != null:
		var y: float = MapConstants.surface_y(4)
		var want := [
			Vector3(2.0, y, 4.0), Vector3(2.0, y, 3.0),
			Vector3(3.0, y, 3.0), Vector3(3.0, y, 4.0),
		]
		_assert_eq(far.tile_vertices.size(), 4, "the fallback quad has four corners")
		if far.tile_vertices.size() == 4:
			for i in 4:
				# `tile_vertices` are tile-LOCAL, as Lattice reads them.
				_assert_vec(far.tile_vertices[i] + far.position, want[i],
					"fallback corner %d is the EXPORTER's, not this file's" % i)
		far.free()


# --- harness ------------------------------------------------------------------

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_near(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) <= EPS:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %.6f, got %.6f" % [label, expected, actual])


func _assert_vec(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= EPS:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


# --- ADR-0219: a fixture can state a BRIDGE -----------------------------------

func _test_a_column_holds_two_cells() -> void:
	# `flat` fills level 0 only, so a fixture states an upper storey the same way the
	# ROM does: the same (x, z) at a second level. Before ADR-0219 the second `put`
	# REPLACED the first — the fixture could not express the case at all, which is
	# why nothing in the suite ever asked this question.
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(4, 11), 1, {"surface_type": "WaterPlant"})
	fixture.put(Vector2i(4, 11), 7, {"surface_type": "Bridge"}, 1)
	fixture.put(Vector2i(5, 11), 7)
	add_child(fixture)
	var lattice: Lattice = fixture.lattice

	_assert_eq(lattice.all_cells().size(), 3, "two cells in one column, plus the bank")

	var moat: TerrainCell = lattice.terrain_at(TerrainCell.ground(4, 11))
	var deck: TerrainCell = lattice.terrain_at(Vector3i(4, 11, 1))
	_assert_true(moat != null and deck != null, "both cells of the column answer")
	if moat != null and deck != null:
		_assert_eq(moat.height, 1, "the ground cell keeps its own height")
		_assert_eq(deck.height, 7, "and the level-1 cell keeps its own")
		_assert_eq(deck.surface_type, "Bridge",
			"the level is part of the identity, so the descriptors do not overwrite")
		_assert_eq(moat.surface_type, "WaterPlant", "…in either direction")

	# `ground_at` is the COLUMN question and answers the LOWEST cell present — which
	# is not a synonym for level 0: 8 of the 202 selectable level-1 tiles in the
	# corpus sit over a level 0 that is not there at all.
	var ground: TerrainCell = lattice.ground_at(4, 11)
	_assert_true(ground != null and ground.grid == TerrainCell.ground(4, 11),
		"ground_at answers the lowest cell of the column")

	var column: Array = lattice.column_at(4, 11)
	_assert_eq(column.size(), 2, "column_at answers both")
	if column.size() == 2:
		_assert_true(column[0].grid.z < column[1].grid.z, "…low to high")
	_assert_eq(lattice.column_at(5, 11).size(), 1, "a one-cell column answers one")
	_assert_eq(lattice.column_at(9, 9).size(), 0, "and an empty square answers none")

	fixture.queue_free()
