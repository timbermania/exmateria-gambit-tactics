class_name MovementComponent
extends Node

## Tracks the unit's current logical CELL — a grid coordinate, not a tile node.
##
## The GPU compute shader is the source of truth for movement.
## GPUVisualBridge syncs the GPU position back to this property.
##
## 🔴 THIS USED TO BE `var current_logical_tile: Tile`, i.e. ADR-0166's **holder 4**:
## a live `StaticBody3D` from inside `Battlefield`, held per unit and updated per
## step, across 51 lines in 20 files of which exactly three carried the type name.
## That is why it needed its own acceptance criterion — ADR-0164's criteria 1 and 2
## both pass on a stored node (retype the three to `Node3D` and both are satisfied
## while 51 sites still hold tiles), which is what ADR-0166 dec. 4's producer-side
## Tile-door register exists to catch.
##
## `Vector3i` over `TerrainCell`, on ADR-0166 dec. 3's three reasons in weight order
## — unchanged by ADR-0219 dec. 3, which corrected only the ARITY. Every one of them
## holds for a `Vector3i` without a word altered: it compares by value, it is still one
## type for one concept, and it is still not a snapshot.
##   1. EQUALITY. `GPUArena._player_unit_on_tile` compares this against the cell under
##      the cursor. A `RefCounted` `TerrainCell` compares by REFERENCE, so two
##      `terrain_at` calls for one cell would be `!=` — the comparison would silently
##      get subtler rather than break. `Vector3i` compares by value, permanently.
##   2. One type for one concept: the same key the deployment assignment and the GPU state
##      already use.
##   3. Staleness. A `TerrainCell` is a snapshot (ADR-0164 dec. 2's 🔴) and a per-tick
##      unit field is the worst place in the tree to hold one. Anyone needing `height`
##      or a world position asks the port with this coordinate, so no snapshot outlives
##      its query.

## "Not on the grid" is `TerrainCell.NONE`, the schema's own sentinel — NOT a
## constant of this file's. ADR-0166 dec. 3 puts the absence state on a sentinel
## rather than a second `has_cell` field, and the same value has to answer holder 3's
## claim maps and `Battle`'s "no destination"; a second constant meaning the same
## thing would re-open the one-type-for-one-concept question dec. 3 closed.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

## The unit's cell, `(grid_x, grid_z, level)`.
##
## 🔴 `.z` IS THE TERRAIN LEVEL, CARRIED AND NEVER INFERRED (ADR-0219 dec. 3/6). A
## unit's position without its level is not a position — it is the exact ambiguity
## that put Algus in the Igros moat while the ROM had him on the bridge above it. The
## ROM stores it as its own byte at actor `+0x82` and RETIRES it as its own discrete
## event mid-walk; there is no half-level state anywhere in its model, so nothing here
## may derive one from a height.
var current_cell: Vector3i = TerrainCell.NONE

var _unit: Unit = null

func _ready():
	_unit = get_parent() as Unit
	if not _unit:
		push_error("[MovementComponent] Parent must be a Unit!")
		queue_free()

func _exit_tree() -> void:
	current_cell = TerrainCell.NONE
	_unit = null

## Called by Unit.place_on_tile() after spawning.
##
## Takes NO map, and that is ADR-0170 dec. 3's "one of the twelve is deleted, not
## re-pointed". The grid axes derive from the unit's OWN transform, so the line that
## stood here — a `get_tile(int(pos.x), int(pos.z))` on a duck-typed map handle, one
## of the register's fifteen — had nothing left to look up once the holder stopped
## storing a node. The `map: Node3D` parameter went dead with it, across all callers.
##
## `level` is the one thing the transform cannot answer and is therefore PASSED
## (ADR-0219 dec. 6): a bridge deck and the water under it are the same two grid axes,
## and the only way to tell which one a unit is standing on is to be told by whoever
## put it there. Deriving it from world Y would be exactly the height-band inference
## the ADR's alternative (d) rejects — MAP012's level-1 floor is `h15` over an `h0`
## while MAP057's bridge is `h8` over an `h1`, so no threshold separates them.
func initialize_logical_position(level: int = TerrainCell.GROUND_LEVEL) -> void:
	if not _unit:
		return
	var pos = _unit.global_position
	current_cell = Vector3i(int(pos.x), int(pos.z), level)
