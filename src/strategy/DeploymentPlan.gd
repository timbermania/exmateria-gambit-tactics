class_name DeploymentPlan
extends RefCounted

## The v1 snap-deployment assignment (wayfinder #234 D): map the player's owned units,
## in deploy order, onto a battle's deployment-zone tiles — deterministic, Ramza first,
## capped by `max_squad_size`. Pure + scene-free; the live placement (`Unit.place_on_tile`
## per assignment) is the scene bridge, verified headful.
##
## The interactive FFT-faithful deployment screen it was a placeholder for now EXISTS —
## [DeploymentAssignment], the assignment the player edits (ADR-0242, #892) — and it
## delegates its auto-fill here, so this stayed rather than being replaced: the plan is ONE
## assignment, computed, and that is exactly what `GPUArena`'s placement path and the gambit
## host's debug fill both want. It beat the retired `StrategyPhaseManager` auto-march, which
## targeted contested objective tiles and granted an unfaithful deploy-jump: a snap onto the
## zone is simpler AND more faithful (FFT places, then starts — symmetric with Orbonne's
## `cinematic_place`), and ADR-0258 retired the march on exactly that reasoning.


## Assign `owned` units onto `zone_tiles` in list order, capped by `cap` (and by however
## many tiles exist). Returns an ordered Array of `{ "unit": <owned item>, "tile": [x, y] }`
## — one per placed unit, collision-free (each tile used at most once, since assignment is
## index-parallel). A roster larger than `cap` is clamped (over-cap SELECTION is C's fog —
## for Gariland the roster == cap, so this is an identity fill); a smaller roster fills the
## prefix and leaves the remaining tiles empty.
static func assign(owned: Array, zone_tiles: Array, cap: int) -> Array:
	var limit := mini(mini(owned.size(), zone_tiles.size()), maxi(cap, 0))
	var out: Array = []
	for i in range(limit):
		out.append({"unit": owned[i], "tile": zone_tiles[i]})
	return out
