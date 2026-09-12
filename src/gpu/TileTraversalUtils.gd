class_name TileTraversalUtils
extends Node

# Facing utility for grid-based movement: which way a unit turns to step from one
# cell to the next.
#
# 🔴 `do_edge_vertices_match` AND `VERTEX_MATCH_EPSILON` USED TO LIVE HERE and are
# now `Lattice.is_cliff_edge` (ADR-0164 dec. 2, built at pass 6). They computed a
# TERRAIN fact — whether two faces share an edge — out of `tile_vertices` plus the
# tile transform, off two `Tile` NODES, in `src/gpu/`, i.e. in `Battle`. That is
# `Battlefield`'s fact and `Battlefield`'s data; keeping it here is what forced two
# `Battle` files to hold tile nodes just to ask it. The polarity is inverted at the
# port because both callers negated the answer.
#
# What is left takes COORDINATES and needs no map at all.

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

## A facing is a GRID-AXIS question and the level does not enter it (ADR-0219). The
## cells are `Vector3i` now, but a unit stepping from the bridge deck down to the bank
## faces the direction it travelled, not "down" — the level flip is a discrete field
## retirement, not a movement axis (dec. 6). `.x`/`.y` still mean grid X and grid Z, so
## the arithmetic below is unchanged.
static func get_facing_direction_for_step(from_cell: Vector3i, to_cell: Vector3i) -> FacingDirection:
	# Direction the unit should face when stepping between cells.
	# Literal world mapping: +X=NORTH, -X=SOUTH, +Z=EAST, -Z=WEST.
	var dx = to_cell.x - from_cell.x
	var dz = to_cell.y - from_cell.y

	if dx > 0:
		return FacingDirection.NORTH
	elif dx < 0:
		return FacingDirection.SOUTH
	elif dz > 0:
		return FacingDirection.EAST
	elif dz < 0:
		return FacingDirection.WEST

	# Fallback (shouldn't happen for adjacent tiles)
	return FacingDirection.NORTH
