class_name RosterTimeline
extends RefCounted

## The DERIVED story timeline: for every scenario group, where it sits in story order,
## the world-map state a Seek to it must install, and the roster it should arrive with.
##
## This is the ROM's own answer to two questions the navigator used to guess at:
##
## [b]"Which node should the world map offer?"[/b] A Seek re-roots the PLAN but not the
## WORLD STATE, so `var[110]` stayed at 1 and the map kept offering Beoulve Residence —
## the walk then chained forward hop by hop through the entire game. [method enter_vars]
## is the state to install instead, read off the group's own `enter` script conditions.
##
## [b]"Who is in the party?"[/b] [method roster_before] is the fold of ENTD
## `join_after_event` flags over the groups that precede this one (ADR-0201 dec.10). It
## replaces the four hand-authored mutation keys, two of which were measurably wrong.
##
## [b]"Who does this battle SPAWN?"[/b] [method appearances_for] is the named cast of a
## battle group's own ENTD record — the units that must exist in the Catalog for their
## slots to bind to a real identity rather than be rebuilt from the raw slot (ADR-0201
## dec.6/7). An appearance is NOT a recruitment (ADR-0078: catalogue membership is not
## owned membership), and it fires only at a slug's FIRST battle, so a later re-bind can
## never clobber a Character the player has been levelling.
##
## Pure data, scene/GPU-agnostic — the same static-load shape as [UnitNames]. Source of
## truth: assets/scenarios/roster_timeline.json, derived by tools/build_roster_timeline.py.
## Regenerate it; never hand-edit it.
##
## [b]Known gaps, all declared in the asset's own `_coverage`:[/b] special_name 115..127
## has no NAME (UnitNames.xml stops at 0x48), so five real recruits — Worker 8 among them —
## mint as generic `entd<record>_<slot>` slugs; no LEAVE is derived, so a departing guest
## stays in the roster; 68 of the 155 groups are ordered by group-root id rather than by
## derivation; and three units are recruited and then stand Red at a later battle
## ([method recruited_red_conflicts]).
##
## Recruitment itself is NOT a gap any more. "Worker 8 is recruited by an event opcode"
## was false: he carries `join_after_event` at ENTD 291 slot 3 and was dropped by a
## team_color filter in the generator, now removed.
##
## Run guard: "$GODOT" --path . --quit-after 5 res://tests/RosterTimelineTest.tscn

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const PATH := "res://assets/scenarios/roster_timeline.json"

static var _groups: Dictionary = {}
static var _order: Array = []
static var _coverage: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonAsset.load_dict(PATH)
	_groups = data.get("groups", {})
	_order = data.get("order", [])
	_coverage = data.get("_coverage", {})


## True when `root` is a known scenario group root.
static func has_group(root: int) -> bool:
	_ensure_loaded()
	return _groups.has(str(root))


static func _group(root: int) -> Dictionary:
	_ensure_loaded()
	return _groups.get(str(root), {})


## Every group root in story order.
static func order() -> Array[int]:
	_ensure_loaded()
	var out: Array[int] = []
	for root in _order:
		out.append(int(root))
	return out


## `root`'s index in story order, or -1 if unknown.
static func position(root: int) -> int:
	return int(_group(root).get("position", -1))


## The group's map name, as the derivation read it off the scenario record. "" when the
## root is unknown. Display only — nothing keys off it.
static func map_name(root: int) -> String:
	return String(_group(root).get("map_name", ""))


## --- the world-map seek state (Ask C) ---------------------------------------

## True when this group is offered by a world-map node at all. A group reached only by
## chaining (Bethla Garrison) has no enter state and a Seek to it cannot re-root the map.
static func has_enter(root: int) -> bool:
	return _group(root).get("enter", null) != null


## The variable state to install so the map offers THIS group: `{var_index: value}`.
## Empty when the group is never entered from the map.
static func enter_vars(root: int) -> Dictionary:
	var enter = _group(root).get("enter", null)
	if enter == null:
		return {}
	var out: Dictionary = {}
	for key in enter.get("vars", {}):
		out[int(key)] = int(enter["vars"][key])
	return out


## True when installing [method enter_vars] leaves exactly this group's node live. False
## means the Seek is still allowed but the map is ambiguous there — either a `party has
## job` condition this port does not model (nothing goes live) or a genuine tie.
static func enter_is_exclusive(root: int) -> bool:
	var enter = _group(root).get("enter", null)
	return enter != null and bool(enter.get("exclusive", false))


## Every variable any `enter` script tests — the exact set a Seek resets before writing
## the target's. Deliberately not "the whole store": var 528 is a map node-reveal flag.
static func gating_vars() -> Array[int]:
	_ensure_loaded()
	# JSON numbers parse as float; return real ints so callers can `has(110)`.
	var out: Array[int] = []
	for idx in _coverage.get("enter_gating_vars", []):
		out.append(int(idx))
	return out


## --- the roster (Ask D) ------------------------------------------------------

## The slugs the player should already own on arriving at `root` — the fold of every
## recruit granted by the groups before it.
static func roster_before(root: int) -> Array:
	return (_group(root).get("roster_before", []) as Array).duplicate()


## The CatalogueReplay deltas this group grants at its end. Each carries `recruit` (the
## permanent join) or `repeat` (a guest re-appearance), plus the raw ENTD `slot`.
static func joins_for(root: int) -> Array:
	return (_group(root).get("joins", []) as Array).duplicate(true)


## Only the deltas that permanently recruit — guest re-appearances excluded.
static func recruits_for(root: int) -> Array:
	var out: Array = []
	for delta in joins_for(root):
		if bool(delta.get("recruit", false)):
			out.append(delta)
	return out


## --- the battle cast (ADR-0201 dec.6/7) --------------------------------------

## The named units this battle group's own ENTD spawns, as `join` deltas carrying the raw
## ENTD `slot`. Empty for a linear group, and empty for a battle whose named cast is
## already catalogued by an earlier one — the derivation binds each slug ONCE, at its
## first battle. Never owned: an appearance is not a recruitment.
static func appearances_for(root: int) -> Array:
	return (_group(root).get("appearances", []) as Array).duplicate(true)


## The scenario id of this battle group's OPENER beat, or -1 for a linear group. The
## opener is the first action a battle contributes, so it is the only key whose deltas
## land BEFORE the fight — which is what an appearance needs.
static func opener_scenario_id(root: int) -> int:
	var sid = _group(root).get("opener_scenario_id", null)
	return -1 if sid == null else int(sid)


## The transition-graph node kind of a group ("battle" / "quiet" / "cinematic_latch"),
## or "" when the root is unknown.
static func node_kind(root: int) -> String:
	return String(_group(root).get("node_kind", ""))


## --- the declared contradictions ---------------------------------------------

## Units already RECRUITED who stand on the RED team at a later battle: rows of
## `{slug, position, root, entd_idx, slot_index, special_name}`, in story order.
##
## Unfiltered by `own`, because the generator asserts no deployability (ADR-0216 dec.8):
## Algus and Gafgarion are here as canon — they turn on you and are never owned — so a
## consumer narrows the register by its own never-owned set. Exactly one row survives
## that: Rafa. Her true recruit point is still unknown — but NOT for the reason this once
## gave. It is a guest-vs-join call the ENTD flags cannot make, not an unparsed opcode.
static func recruited_red_conflicts() -> Array:
	_ensure_loaded()
	return (_coverage.get("recruited_red_conflicts", []) as Array).duplicate(true)
