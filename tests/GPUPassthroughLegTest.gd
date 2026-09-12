extends Node
## A PASS-THROUGH STEP IS WALKED ONE TILE EDGE AT A TIME, AND THE UNIT JUMPS.
##
## The mover lands a unit PAST an ally — `find_passthrough_destination`, up to
## `PASSTHROUGH_MAX_TILES` in a straight line — so `GPUMovementVisualizer` is
## handed a `from_cell` and a `to_cell` that are not adjacent, with terrain
## between them the unit had to climb. Read as ONE edge, the reported case (a row
## of heights `1 2 1`, an ally on the 2) has `y_delta == 0`, takes the flat
## branch, and lerps the sprite in a straight line at the starting height —
## 0.429 world units, one full half-step, INSIDE the tile it should have hopped
## onto and off. That is the "units walk through walls" report, and the arms
## below are written to fail on it: arm 1 samples every tick of the rendered path
## and asserts it never sinks below the surface it is passing over.
##
## Pure GDScript over a `TerrainFixture` — no RenderingDevice and no GPU. The
## terrain, the tiles, the store, the port and the cliff rule are all
## production's (ADR-0218); only the heights are stated here.
##
## The GPU half of the same fix — `get_move_ticks` summing per-edge costs instead
## of measuring one edge end to end — is not reachable from here; it rides the
## shader's own scenarios (`tests/gambit_scenarios/scenarios_G_pathfinding.gd`
## G4a/G4b).

# ADR-0211 dec. 4 — the addon's facade is its whole symbol surface, so these three
# come through `ExMateriaBattlefield` and not through `preload()` of an addon path.
# The two preloads this replaces were UNLISTED reaches on `check_lattice_scene`'s
# burn-down; every other host test that wants a `TerrainFixture` already spells it
# this way. `Lattice` is here so the `fixture.lattice` fetches below can be
# annotated, which `check_lattice_ports` arm 2 requires (ENFORCING, ADR-0192 dec. 7).
const Lattice = ExMateriaBattlefield.Lattice
const TerrainFixture = ExMateriaBattlefield.TerrainFixture
const MapConstants = ExMateriaBattlefield.MapConstants
const TerrainCell = ExMateriaSchema.TerrainCell
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

## The GPU's budget for the whole step. Any value works — the legs divide it —
## and a coarse one is the honest case: the sampler must not depend on the
## boundaries landing on tick multiples.
const STEP_TICKS: int = 40

var _failed := false


func _ready() -> void:
	_test_a_passthrough_over_a_raised_tile_does_not_enter_it()
	_test_a_passthrough_over_a_raised_tile_jumps()
	_test_a_flat_passthrough_stays_a_walk()
	_test_a_passthrough_ends_on_its_destination()
	_test_one_edge_is_untouched()
	_test_a_hurried_cliff_step_still_travels()

	if _failed:
		print("[FAIL] GPUPassthroughLegTest")
		get_tree().quit(1)
	else:
		print("[PASS] GPUPassthroughLegTest")
		get_tree().quit(0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


# The reported shape: one row, heights 1 2 1, walked west to east past an ally
# standing on the 2.
func _row(heights: Array) -> TerrainFixture:
	var fixture := TerrainFixture.new()
	for x in range(heights.size()):
		fixture.put(Vector2i(x, 0), int(heights[x]))
	add_child(fixture)
	return fixture


func _visualizer(fixture: TerrainFixture, from_x: int, to_x: int) -> GPUMovementVisualizer:
	var lattice: Lattice = fixture.lattice
	var from_cell := TerrainCell.ground(from_x, 0)
	var viz := GPUMovementVisualizer.new()
	viz.start_movement(from_cell, TerrainCell.ground(to_x, 0), lattice,
		lattice.world_position_at(from_cell), 3)
	viz.set_gpu_total_ticks(STEP_TICKS)
	return viz


func _test_a_passthrough_over_a_raised_tile_does_not_enter_it() -> void:
	var fixture := _row([1, 2, 1])
	var viz := _visualizer(fixture, 0, 2)

	# The surface of the tile in the middle. The sprite's feet may touch it and
	# may fly above it; anything below is inside the terrain.
	var raised_surface := MapConstants.surface_y(2)
	var deepest := 1000.0
	for timer in range(STEP_TICKS, -1, -1):
		var p: Vector3 = viz.calculate_position(timer)
		if p.x >= 1.0 and p.x < 2.0:
			deepest = minf(deepest, p.y - raised_surface)
	_check(deepest > -0.01,
		"the rendered path sinks %.3f into the tile it passes over (was -0.429)" % deepest)

	fixture.queue_free()


func _test_a_passthrough_over_a_raised_tile_jumps() -> void:
	var fixture := _row([1, 2, 1])
	var viz := _visualizer(fixture, 0, 2)

	_check(viz.is_cliff_move, "a pass-through that climbs a half-step is a cliff move")

	var jumped := false
	var walked := false
	for timer in range(STEP_TICKS, -1, -1):
		var activity: int = viz.get_activity(timer)
		if activity == DisplayActivity.Activity.JUMPING \
			or activity == DisplayActivity.Activity.LANDING:
			jumped = true
		elif activity == DisplayActivity.Activity.WALKING:
			walked = true
	_check(jumped, "the unit plays a jump somewhere across the raised tile")
	_check(not walked, "no edge of a 1-2-1 pass-through is a walk — both are cliffs")

	fixture.queue_free()


func _test_a_flat_passthrough_stays_a_walk() -> void:
	var fixture := _row([1, 1, 1])
	var viz := _visualizer(fixture, 0, 2)

	_check(not viz.is_cliff_move, "level ground is not a cliff, however many tiles of it")
	for timer in range(STEP_TICKS, -1, -1):
		if viz.get_activity(timer) != DisplayActivity.Activity.WALKING:
			_check(false, "a flat pass-through is a walk at tick %d" % timer)
			break
	# And it is still a straight line at one height.
	var start_y: float = viz.calculate_position(STEP_TICKS).y
	for timer in range(STEP_TICKS, -1, -1):
		if absf(viz.calculate_position(timer).y - start_y) > 0.001:
			_check(false, "a flat pass-through leaves the ground at tick %d" % timer)
			break

	fixture.queue_free()


func _test_a_passthrough_ends_on_its_destination() -> void:
	var fixture := _row([1, 2, 1])
	var lattice: Lattice = fixture.lattice
	var viz := _visualizer(fixture, 0, 2)

	var destination: Vector3 = lattice.world_position_at(TerrainCell.ground(2, 0))
	_check(viz.calculate_position(0).distance_to(destination) < 0.001,
		"timer 0 is the destination, not wherever the last leg's share ran out")
	_check(viz.end_pos.distance_to(destination) < 0.001,
		"`end_pos` is the destination — the bridge reads it for facing")

	fixture.queue_free()


# The one-edge path builds no legs and must behave exactly as it did before.
func _test_one_edge_is_untouched() -> void:
	var fixture := _row([1, 2])
	var lattice: Lattice = fixture.lattice
	var from_cell := TerrainCell.ground(0, 0)

	var viz := GPUMovementVisualizer.new()
	viz.start_movement(from_cell, TerrainCell.ground(1, 0), lattice,
		lattice.world_position_at(from_cell), 3)
	viz.set_gpu_total_ticks(STEP_TICKS)

	_check(viz.is_cliff_move, "a single half-step up is still a cliff move")
	# The wind-up phase is the signature of the untouched single-edge path: the
	# sprite holds its start position while the JUMPING animation plays.
	_check(viz.calculate_position(STEP_TICKS).distance_to(
		lattice.world_position_at(from_cell)) < 0.001,
		"the cliff wind-up still holds the start position")
	_check(viz.get_activity(STEP_TICKS) == DisplayActivity.Activity.JUMPING,
		"the cliff wind-up still plays JUMPING")

	fixture.queue_free()


# The GPU's budget is not the CPU's nominal cost: `write_movement_step` HALVES it
# under HASTE and a pass-through leg gets only a share of one. A cliff move's
# wind-up plus its landing is a fixed 40 ticks, so an unscaled budget at or under
# that put every tick in the wind-up branch — the sprite stood still for the whole
# move and then appeared at the destination. A hasted cliff step is 23 ticks.
func _test_a_hurried_cliff_step_still_travels() -> void:
	var fixture := _row([1, 2])
	var lattice: Lattice = fixture.lattice
	var from_cell := TerrainCell.ground(0, 0)
	var origin: Vector3 = lattice.world_position_at(from_cell)

	var viz := GPUMovementVisualizer.new()
	viz.start_movement(from_cell, TerrainCell.ground(1, 0), lattice, origin, 3)
	var hurried := maxi(viz.total_ticks / 2, 1)
	viz.set_gpu_total_ticks(hurried)

	var travelled := false
	for timer in range(hurried, -1, -1):
		var p: Vector3 = viz.calculate_position(timer)
		var d: float = p.distance_to(origin)
		if d > 0.01 and p.distance_to(viz.end_pos) > 0.01:
			travelled = true
	_check(travelled,
		"a hasted cliff step is rendered in flight, not held at its start then teleported")

	fixture.queue_free()
