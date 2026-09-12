class_name PlacementPolicy
extends RefCounted

## `Battle`'s answer to **may a unit stand here** — one question, one place.
##
## Was `PlacementTileGenerator`, and it generated a procedural board: two
## flood-grown islands on opposite map edges plus Poisson-sampled contested tiles
## for the deployment march to walk to. ADR-0258 retired the march, and with it
## every consumer of that board. What survives is the half that was never about the
## march at all — the water rule — so the name follows the surviving job
## (ADR-0258 dec. 5).
##
## One consumer today: the W7 stress fixture (`GPUArena --stress-units=N`), which
## needs free ground for the clones the deployment zone does not cover.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell


var _lattice: Lattice


func _init(lattice: Lattice):
	_lattice = lattice


## Every cell a unit may be deployed onto — the PUBLIC spelling of the policy below.
##
## The W7 stress fixture (`GPUArena --stress-units=N`) needs the same answer for the
## tiles the deployment zone does not cover, and re-deriving the water rule outside
## `Battle` is exactly what ADR-0192 dec. 6 / ADR-0166 dec. 1 refuse. One forwarder
## keeps the policy in its one place.
func placement_cells() -> Array[Vector3i]:
	return _get_valid_placement_cells()


## Every cell a unit may be deployed onto.
##
## 🔴 THE WATER RULE STAYS HERE, IN `Battle`, AND THAT IS ADR-0192 dec. 6's DECISION.
## `unselectable` / `pass_through_only` / `surface_type` are the three thin
## `TerrainCell` fields, and this function is their only `src/` reader. Collapsing
## them into a `placeable` flag on the cell was rejected because which surfaces this
## game refuses to DEPLOY onto is `Battle`'s policy, and the cell is a type the shared
## kernel owns — ADR-0166 dec. 1 is explicit that the map does not hold another
## system's design decision.
func _get_valid_placement_cells() -> Array[Vector3i]:
	var valid: Array[Vector3i] = []
	if _lattice == null:
		return valid
	for cell in _lattice.all_cells():
		# 🔴 THE GROUND PLANE, and it is the same declaration `DistanceFieldGenerator`
		# and the compute shader's own column indexing make (ADR-0219 Consequences;
		# `build_map_data` itself carries both planes since ADR-0224). A unit
		# deployed here is moved by the GPU battle sim, which indexes one slot per
		# column, so offering it a bridge deck the mover cannot represent would deploy
		# units onto terrain that does not exist as far as combat is concerned.
		if cell.grid.z != TerrainCell.GROUND_LEVEL:
			continue
		if _is_valid_for_placement(cell):
			valid.append(cell.grid)
	return valid


func _is_valid_for_placement(cell: TerrainCell) -> bool:
	"""Check if a cell can be used for placement."""
	if cell.impassable:
		return false
	if cell.unselectable:
		return false
	if cell.pass_through_only:
		return false
	# Exclude water surfaces
	if cell.surface_type in ["Water", "Waterway", "River", "Sea", "Lava"]:
		return false
	return true
