class_name ScenarioGroupDatabase
extends RefCounted

## Database for FFT [scenario group]s — the maximal contiguous runs of scenarios
## sharing one (map_id, entd_idx): a root/setup scenario that loads the world plus
## the member scenarios that are event-script deltas on that world.
##
## Loads assets/scenarios/scenario_groups.json (155 groups, emitted by
## `tools/export_scenario_groups.py`) and serves lookups the [Path] planner and its
## F3 front-ends need: root + battle_conditionals_id for any scenario, and the group
## membership. Pure data, GPU/scene-agnostic — same static-load shape as
## [BattleConditionalDatabase] / ScenarioDatabase. The route planner lives in
## [ScenarioPath]; this class only serves records.
##
## Group record shape:
##   { "group_root_id": int, "map_id": int, "map_name": String, "entd_idx": int,
##     "battle_conditionals_id": int,
##     "members": [ { "scenario_id": int, "role": String, "name": String } ],
##     "successor": String, "successor_scenario_id": int }

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const GROUPS_PATH := "res://assets/scenarios/scenario_groups.json"

static var _groups: Array = []
static var _by_root: Dictionary = {}       # group_root_id -> group
static var _group_of: Dictionary = {}      # any member scenario_id -> group
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_groups = JsonAsset.load_dict(GROUPS_PATH).get("groups", [])
	for g in _groups:
		var root := int(g.get("group_root_id", -1))
		if root >= 0:
			_by_root[root] = g
		for m in g.get("members", []):
			_group_of[int(m.get("scenario_id", -1))] = g


## Every group record, in file order (ascending by root).
static func all_groups() -> Array:
	_ensure_loaded()
	return _groups


## The group rooted at `root_id`, or {} if none.
static func get_group_by_root(root_id: int) -> Dictionary:
	_ensure_loaded()
	return _by_root.get(int(root_id), {})


## The group that CONTAINS `scenario_id` (as its root or any member), or {} if the
## scenario belongs to no known group.
static func get_group_for_scenario(scenario_id: int) -> Dictionary:
	_ensure_loaded()
	return _group_of.get(int(scenario_id), {})


## The battle_conditionals_id governing `scenario_id`'s group, or -1 if unknown.
## (Only the root carries it; this resolves it from any member.)
static func bc_id_for_scenario(scenario_id: int) -> int:
	var g := get_group_for_scenario(scenario_id)
	if g.is_empty():
		return -1
	return int(g.get("battle_conditionals_id", -1))


## The setup-root scenario id for `scenario_id`'s group, or -1 if unknown.
static func root_for_scenario(scenario_id: int) -> int:
	var g := get_group_for_scenario(scenario_id)
	if g.is_empty():
		return -1
	return int(g.get("group_root_id", -1))
