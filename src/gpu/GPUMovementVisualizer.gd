class_name GPUMovementVisualizer
extends RefCounted

## GPU Movement Visualizer
##
## Handles visual movement calculation for GPU-driven combat.
## Detects cliff vs ramp movement and calculates appropriate paths:
## - Ramp: Linear interpolation with WALKING animation
## - Cliff: Arc path (rounded-L) with JUMPING/LANDING animations
##
## Uses GPU timer ticks to determine movement phase and position.
##
## 🔴 A GPU STEP CAN SPAN MORE THAN ONE TILE, and it is not one edge measured end
## to end. `find_passthrough_destination` (stage_pathfind/attack/spell) lands a
## unit PAST an ally, up to `PASSTHROUGH_MAX_TILES` away, in a straight line — so
## `from_cell` and `to_cell` here are up to eight tiles apart with terrain between
## them that the unit had to climb. Read as a single edge, the user's own case —
## heights `1 2 1` in a row, an ally on the 2 — has `y_delta == 0`, takes the flat
## branch, and lerps the sprite in a straight line at the starting height THROUGH
## the half-step it should have hopped onto and off. That is the "units walk
## through walls" report, and it is why a multi-tile move is decomposed into one
## LEG per tile edge below (`_legs`), each leg a `GPUMovementVisualizer` of its
## own asking the same cliff question about a genuinely adjacent pair.
##
## A one-edge move builds no legs and every field below means exactly what it
## meant before — that path is untouched.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the schema façade for the cell type (ADR-0212 dec. 1) — `TerrainCell.ground`
## and `TerrainCell.LEVEL_COUNT` are what the per-tile walk below states a column
## with, rather than burying the level in a `Vector3i` literal.
const TerrainCell = ExMateriaSchema.TerrainCell

## Self-preload, so a leg can be one of these. Legal — `preload` of the file it is
## written in resolves to the already-loading script — and it is what the file
## needs: naming the class by its own `class_name` from inside itself is a cycle
## GDScript resolves to a bare `GDScript` with no `new()`, which fails at RUNTIME,
## in the caller, with the class_name looking innocent. Same trick, same reason, as
## `TerrainFixture`'s.
const MovementLeg = preload("res://src/gpu/GPUMovementVisualizer.gd")


# Arc geometry constant
const ARC_RADIUS: float = 0.5

## Jump a caller that does not know the unit's falls back to. `UnitProgression
## .get_jump()`'s own default, and `GPUCombatPacker`'s for the `U_JUMP` field, so a
## leg walk that has to guess guesses what the mover would have read.
const DEFAULT_JUMP: int = 3

# Dynamic timing (calculated per-movement)
var total_ticks: int = 0
var jumping_ticks: int = 0
var arc_ticks: int = 0
var landing_ticks: int = 0

# GPU-captured timing (source of truth for phase boundaries)
var gpu_total_ticks: int = 0  # Captured from GPU's initial timer when movement starts

# Movement type
var is_cliff_move: bool = false
var y_delta: float = 0.0

# Arc geometry (only used for cliff moves)
var arc_corner: Vector3 = Vector3.ZERO
var arc_horizontal_dir: Vector3 = Vector3.RIGHT
var arc_effective_radius: float = 0.0
var arc_segment_1_end: Vector3 = Vector3.ZERO
var arc_segment_2_end: Vector3 = Vector3.ZERO
var arc_total_length: float = 0.0
var arc_segment_1_length: float = 0.0
var arc_segment_2_length: float = 0.0
var arc_segment_3_length: float = 0.0

# Cell references — grid COORDINATES, not `Tile` nodes. ADR-0166 dec. 3's
# "one type for one concept": the same `Vector2i` the GPU state, holder 4 and
# the deployment keys all use, so nothing here holds a node whose lifetime it
# does not own (this object outlives a `change_map` that frees every tile).
var from_cell: Vector3i = Vector3i.ZERO
var to_cell: Vector3i = Vector3i.ZERO
var start_pos: Vector3 = Vector3.ZERO
var end_pos: Vector3 = Vector3.ZERO

## One `GPUMovementVisualizer` per TILE EDGE of a multi-tile pass-through step,
## in travel order, or EMPTY for the ordinary one-edge step every field above
## already describes. A leg is exactly what this class models, so a leg is one of
## these rather than a second geometry type: the cliff question it asks is the
## same `lattice.is_cliff_edge`, about a pair that really is adjacent.
var _legs: Array[MovementLeg] = []

## The legs' own summed `total_ticks`. The GPU's budget for the whole step is
## divided across the legs in this proportion, so a climb inside a pass-through
## gets the ticks a climb costs even when the two ENDPOINTS are level.
var _legs_nominal_ticks: int = 1


## Initialize movement between two cells
## Detects whether this is a cliff jump or ramp/flat movement
## Calculates dynamic timing based on movement type and distance
##
## `jump` is the MOVER'S jump, and it is here for one reason: a column can hold
## more than one cell (ADR-0219 dec. 5), so "which cell of the tile between us did
## the unit actually cross?" is a question only the unit's jump answers. It is
## unused for a one-edge step, where both cells are given.
func start_movement(p_from_cell: Vector3i, p_to_cell: Vector3i, lattice: Lattice,
		current_visual_pos: Vector3, jump: int = DEFAULT_JUMP) -> void:
	from_cell = p_from_cell
	to_cell = p_to_cell
	start_pos = current_visual_pos
	end_pos = lattice.world_position_at(p_to_cell)
	_legs.clear()

	# A pass-through step spans several tiles and is walked one edge at a time.
	# `_build_legs` returns false when the path cannot be resolved (a column with
	# no cell this unit could have crossed, or a step that is not on one grid
	# axis) — then this falls through to the end-to-end reading below, which is
	# what it always did.
	if _build_legs(_straight_path(p_from_cell, p_to_cell, lattice, jump), lattice):
		return

	# Cliff vs ramp is the PORT's verdict (ADR-0164 dec. 2). It used to be
	# `TileTraversalUtils.do_edge_vertices_match(from_tile, to_tile)` — a `Battle`
	# function reading `tile_vertices` + the tile transform off two nodes, i.e. a
	# terrain fact computed outside the addon that owns the terrain. Note the
	# polarity flip: the port answers "is it a cliff", which is what both callers
	# actually asked, each by negating the old answer.
	var vertices_match := not lattice.is_cliff_edge(p_from_cell, p_to_cell)
	y_delta = end_pos.y - start_pos.y

	if vertices_match or absf(y_delta) < 0.01:
		# Ramp or flat - use linear movement
		is_cliff_move = false
		_setup_flat_timing()
	else:
		# Cliff - use arc movement
		is_cliff_move = true
		_setup_arc_geometry()
		_setup_cliff_timing()


#region Pass-through legs

## The cells a unit crosses stepping from `a` to `b` in a straight line, `a` and
## `b` included. Two entries for the ordinary adjacent step.
##
## The INTERMEDIATE cells are the ones this has to derive, and it derives them the
## way the mover chose them: `find_passthrough_destination` takes the first
## admissible cell of each column, LOW TO HIGH, gated by the same
## `abs(height - previous height) <= jump` against the height it is stepping FROM
## (stage_pathfind.glsl, and the identical copies in stage_attack / stage_spell).
## Picking by smallest height delta instead would read as more physical and would
## put a second traversal rule in the tree — the exact objection that comment
## records.
##
## An empty return means "not resolvable": the two cells are not on one grid axis,
## or a column between them has no cell this unit could have crossed. The caller
## falls back rather than guessing.
func _straight_path(a: Vector3i, b: Vector3i, lattice: Lattice, jump: int) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	var path: Array[Vector3i] = [a]
	# `.x` is grid X and `.y` is grid Z — `.z` is the LEVEL and is not an axis of
	# travel (ADR-0219 dec. 6: a step never changes level in place).
	var dx := b.x - a.x
	var dz := b.y - a.y
	if dx != 0 and dz != 0:
		return empty
	var span := absi(dx) + absi(dz)
	if span <= 1:
		path.append(b)
		return path

	var step := Vector2i(signi(dx), signi(dz))
	var standing: TerrainCell = lattice.terrain_at(a)
	if standing == null:
		return empty
	for i in range(1, span):
		var column := Vector2i(a.x + step.x * i, a.y + step.y * i)
		var crossed := _crossed_cell(column, lattice, standing.height, jump)
		if crossed == TerrainCell.NONE:
			return empty
		path.append(crossed)
		standing = lattice.terrain_at(crossed)
		if standing == null:
			return empty
	path.append(b)
	return path


## The cell of `column` a unit at `from_height` with `jump` steps onto: the lowest
## traversable level within jump, low to high. `TerrainCell.NONE` when the column
## has none — the schema's own "no such cell", which is what `_straight_path`
## reads to give up rather than guess.
func _crossed_cell(column: Vector2i, lattice: Lattice, from_height: int,
		jump: int) -> Vector3i:
	for level in range(TerrainCell.LEVEL_COUNT):
		var cell := Vector3i(column.x, column.y, level)
		var terrain: TerrainCell = lattice.terrain_at(cell)
		if terrain == null or terrain.impassable:
			continue
		if absi(terrain.height - from_height) > jump:
			continue
		return cell
	return TerrainCell.NONE


## Build one leg per edge of `path`. Returns false — and leaves `_legs` empty —
## for a path with fewer than three cells, which is every ordinary step.
func _build_legs(path: Array[Vector3i], lattice: Lattice) -> bool:
	if path.size() < 3:
		return false

	var nominal := 0
	var world := start_pos
	for i in range(path.size() - 1):
		var leg := MovementLeg.new()
		leg.start_movement(path[i], path[i + 1], lattice, world)
		world = leg.end_pos
		nominal += leg.total_ticks
		_legs.append(leg)

	_legs_nominal_ticks = maxi(nominal, 1)
	total_ticks = _legs_nominal_ticks
	# The move as a whole is a cliff move when ANY edge of it is — what the bridge
	# and the diagnostics read this for is "did this step involve a jump".
	is_cliff_move = false
	for leg in _legs:
		if leg.is_cliff_move:
			is_cliff_move = true
			break
	y_delta = end_pos.y - start_pos.y
	# The last leg's own end is the destination; take it so a caller reading
	# `end_pos` and a caller sampling the path cannot disagree by a float.
	end_pos = _legs[-1].end_pos
	return true


## The leg the whole-move `timer` falls in, and that leg's own countdown, as
## `[leg, leg_timer]`.
##
## The GPU hands down ONE budget for the whole step. It is divided in proportion
## to the legs' own `total_ticks`, so the climb inside a pass-through gets the
## ticks a climb costs — which is the half of "make them actually jump" that is
## about time rather than about geometry.
func _resolve_leg(timer: float) -> Array:
	var total: int = gpu_total_ticks if gpu_total_ticks > 0 else total_ticks
	if total <= 0:
		return [_legs[-1], 0.0]

	var elapsed := clampf(float(total) - timer, 0.0, float(total))
	var prefix := 0
	for i in range(_legs.size()):
		var leg: MovementLeg = _legs[i]
		var window_start := (prefix * total) / _legs_nominal_ticks
		prefix += leg.total_ticks
		var window_end := total if i == _legs.size() - 1 \
			else (prefix * total) / _legs_nominal_ticks
		if elapsed >= window_end and i < _legs.size() - 1:
			continue
		var window := maxi(window_end - window_start, 1)
		leg.set_gpu_total_ticks(window)
		return [leg, clampf(float(window) - (elapsed - float(window_start)), 0.0, float(window))]
	return [_legs[-1], 0.0]

#endregion


## Calculate timing for flat/ramp movement
func _setup_flat_timing() -> void:
	var distance = start_pos.distance_to(end_pos)
	total_ticks = MovementTimingConfig.get_flat_move_ticks(distance)
	# No phases for flat movement
	jumping_ticks = 0
	arc_ticks = total_ticks
	landing_ticks = 0


## Calculate timing for cliff movement (JUMPING + ARC + LANDING)
## Uses speed-scaled getters so CPU phase boundaries match GPU timing
func _setup_cliff_timing() -> void:
	jumping_ticks = MovementTimingConfig.get_cliff_jumping_ticks()
	landing_ticks = MovementTimingConfig.get_cliff_landing_ticks()
	arc_ticks = MovementTimingConfig.get_cliff_arc_ticks(arc_total_length)
	total_ticks = jumping_ticks + arc_ticks + landing_ticks


## Get the total ticks for this movement
## Set GPU's total ticks (source of truth for phase boundaries)
func set_gpu_total_ticks(ticks: int) -> void:
	gpu_total_ticks = ticks


## Calculate world position for given timer value.
##
## 🔴 `timer` IS A FLOAT AND THE FRACTION IS THE WHOLE POINT (#1206). The GPU counts it
## down in whole ticks, but the renderer samples this function on a clock that is not
## phase-locked to the tick — at 144 Hz against the 60 Hz tick, 58% of rendered frames bank
## less than one tick. Handed the integer, this returned a bit-identical Vector3 on every
## one of them and the unit visibly strobed. The caller passes the integer countdown carried
## back by the un-simulated remainder of the current tick, so a walk advances every frame.
##
## Every path below CLAMPS its parameter to the move's own span, so a fractional timer can
## never place a unit outside the arc the sim committed to.
func calculate_position(timer: float) -> Vector3:
	if not _legs.is_empty():
		var leg := _resolve_leg(timer)
		return (leg[0] as MovementLeg).calculate_position(leg[1])

	var effective_total = gpu_total_ticks if gpu_total_ticks > 0 else total_ticks

	if effective_total <= 0:
		return end_pos

	if not is_cliff_move:
		# Linear interpolation for ramps/flat movement
		var progress = 1.0 - (float(timer) / float(effective_total))
		progress = clampf(progress, 0.0, 1.0)
		return start_pos.lerp(end_pos, progress)

	# Cliff movement phases: JUMPING -> ARC -> LANDING
	var scaled_jumping := _scale_phase(jumping_ticks, effective_total)
	var scaled_landing := _scale_phase(landing_ticks, effective_total)
	var jumping_end_timer = effective_total - scaled_jumping
	var landing_start_timer = scaled_landing
	var effective_arc_ticks = effective_total - scaled_jumping - scaled_landing

	if timer > jumping_end_timer:
		return start_pos  # Phase 1: JUMPING (wind-up)
	elif timer <= landing_start_timer:
		return end_pos  # Phase 3: LANDING
	else:
		# Phase 2: ARC movement
		var arc_progress = 1.0 - (float(timer - landing_start_timer) / float(effective_arc_ticks))
		arc_progress = clampf(arc_progress, 0.0, 1.0)
		return _interpolate_arc_position(arc_progress)


## Get animation state for given timer value. Takes the same fractional timer as
## `calculate_position` so the POSE a frame draws is the one belonging to the POSITION it
## draws — the phase boundary simply lands on whichever side of the sub-tick it falls.
func get_activity(timer: float) -> DisplayActivity.Activity:
	if not _legs.is_empty():
		var leg := _resolve_leg(timer)
		return (leg[0] as MovementLeg).get_activity(leg[1])

	if not is_cliff_move:
		return DisplayActivity.Activity.WALKING

	var effective_total = gpu_total_ticks if gpu_total_ticks > 0 else total_ticks
	var jumping_end_timer = effective_total - _scale_phase(jumping_ticks, effective_total)

	if timer > jumping_end_timer:
		return DisplayActivity.Activity.JUMPING
	elif timer <= _scale_phase(landing_ticks, effective_total):
		return DisplayActivity.Activity.LANDING
	else:
		return DisplayActivity.Activity.JUMPING


## A phase boundary of this move's own `total_ticks`, expressed on the budget the
## GPU actually handed down. The identity when the two agree, which is the
## ordinary case and why this changes nothing for a step nobody hurried.
##
## 🔴 THEY DISAGREE MORE OFTEN THAN THE PHASE CONSTANTS ADMIT. `write_movement_step`
## HALVES the budget under HASTE and DOUBLES it under SLOW, and a pass-through leg
## receives only its SHARE of one. Unscaled, a cliff move's wind-up (22 frames) plus
## its landing (18) is a fixed 40 ticks, so any budget at or under that left
## `jumping_end_timer` at or below zero — every sampled tick took the wind-up branch,
## the sprite stood at its start position for the whole move and then appeared at the
## destination. A hasted cliff step is 23 ticks and did exactly that.
func _scale_phase(phase_ticks: int, effective_total: int) -> int:
	if total_ticks <= 0:
		return phase_ticks
	return (phase_ticks * effective_total) / total_ticks


## Check if this is a cliff move
#region Arc Geometry

func _setup_arc_geometry() -> void:
	"""Initialize rounded-L arc movement for cliff traversal.
	Ported from MovementAnimator._setup_arc_movement()"""

	# Calculate horizontal direction (XZ plane)
	var horizontal_delta = Vector3(end_pos.x - start_pos.x, 0, end_pos.z - start_pos.z)
	var horizontal_dist = horizontal_delta.length()
	arc_horizontal_dir = horizontal_delta.normalized() if horizontal_dist > 0.001 else Vector3.RIGHT

	var vertical_dist = absf(end_pos.y - start_pos.y)

	# Clamp radius to available space
	arc_effective_radius = minf(ARC_RADIUS, minf(vertical_dist * 0.5, horizontal_dist * 0.5))

	if y_delta > 0:
		# JUMP UP: vertical first, then horizontal
		arc_corner = Vector3(start_pos.x, end_pos.y, start_pos.z)
		arc_segment_1_end = arc_corner - Vector3(0, arc_effective_radius, 0)
		arc_segment_2_end = arc_corner + arc_horizontal_dir * arc_effective_radius
	else:
		# JUMP DOWN: horizontal first, then vertical
		arc_corner = Vector3(end_pos.x, start_pos.y, end_pos.z)
		arc_segment_1_end = arc_corner - arc_horizontal_dir * arc_effective_radius
		arc_segment_2_end = arc_corner - Vector3(0, arc_effective_radius, 0)

	# Calculate segment lengths
	arc_segment_1_length = start_pos.distance_to(arc_segment_1_end)
	arc_segment_2_length = (PI / 2.0) * arc_effective_radius  # Quarter circle
	arc_segment_3_length = arc_segment_2_end.distance_to(end_pos)
	arc_total_length = arc_segment_1_length + arc_segment_2_length + arc_segment_3_length


func _interpolate_arc_position(progress: float) -> Vector3:
	"""Interpolate along rounded-L path.
	Ported from MovementAnimator._interpolate_arc_position()

	Args:
		progress: 0-1 progress along arc path

	Returns:
		World position along the arc
	"""
	if arc_total_length <= 0.0:
		return end_pos

	# Convert progress to distance along path
	var dist_along_path = progress * arc_total_length

	if dist_along_path <= arc_segment_1_length:
		# Segment 1: straight toward corner
		var t = dist_along_path / arc_segment_1_length if arc_segment_1_length > 0 else 1.0
		return start_pos.lerp(arc_segment_1_end, t)

	elif dist_along_path <= arc_segment_1_length + arc_segment_2_length:
		# Segment 2: arc around corner
		var arc_dist = dist_along_path - arc_segment_1_length
		var arc_t = arc_dist / arc_segment_2_length if arc_segment_2_length > 0 else 1.0
		var angle = arc_t * (PI / 2.0)  # 0 to 90 degrees

		if y_delta > 0:
			# JUMP UP: arc from below-corner to side-of-corner
			return arc_corner + Vector3(
				arc_horizontal_dir.x * sin(angle) * arc_effective_radius,
				-cos(angle) * arc_effective_radius,
				arc_horizontal_dir.z * sin(angle) * arc_effective_radius
			)
		else:
			# JUMP DOWN: arc from side-of-corner to below-corner
			return arc_corner + Vector3(
				-arc_horizontal_dir.x * cos(angle) * arc_effective_radius,
				-sin(angle) * arc_effective_radius,
				-arc_horizontal_dir.z * cos(angle) * arc_effective_radius
			)
	else:
		# Segment 3: straight to destination
		var seg3_dist = dist_along_path - arc_segment_1_length - arc_segment_2_length
		var t = seg3_dist / arc_segment_3_length if arc_segment_3_length > 0 else 1.0
		return arc_segment_2_end.lerp(end_pos, t)

#endregion
