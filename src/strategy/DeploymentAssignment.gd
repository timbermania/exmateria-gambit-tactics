class_name DeploymentAssignment
extends RefCounted

## The DEPLOYMENT ASSIGNMENT: which of your units stands on which deployment-zone tile,
## as the player is editing it (ADR-0242, design S9).
##
## ENTD offers n units and the ATTACK.OUT zone offers m tiles; this is the mapping
## between them, and it is the whole content of the deployment decision. Two questions
## at once — **who fights** (the squad cap is usually smaller than the roster, so some
## units stay BENCHED) and **where they stand**.
##
## PURE and scene-free. It holds each unit as an opaque `Object` — identity and a
## display name are the whole of what it asks — and never touches a `Unit`'s own API, a
## map, or the GPU: the placement itself (`Unit.place_on_tile` per row, in one
## pass) is the host's, at commit. That is not tidiness — deployment happens BEFORE the
## GPU battle exists (`boot_battle` is what puts units in the buffer), so an assignment
## that wrote through as you edited would have nothing to write to.
##
## The same fact is why there is no snapshot here and no `cancel`: [TurnDirector] takes
## a snapshot per TURN taker and deliberately holds none in `DEPLOYMENT`, so "throw my
## placements away" is [method clear] over CPU state, not a restore. There is nothing to
## undo because nothing was done yet.
##
## Its relationship to [DeploymentPlan] is one line: the plan is ONE assignment,
## computed; this is the assignment the player edits. [method auto_fill] delegates to it,
## so the debug path and the automatic path cannot drift apart.
##
## A MANDATORY unit is never placed FOR the player, but the field holds a slot open for
## one: see [method effective_cap]. Deployment refuses the placement that would strand it,
## rather than refusing the squad at the commit — which is the difference between a rule
## the player can act on and a rule that tells them the zone they just filled is wrong.

## No tile — the answer for a benched unit. `Vector2i` has no null.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase

const NO_TILE := Vector2i(-1, -1)

## The ATTACK.OUT scenario flag that makes Ramza mandatory during deployment (bit 0),
## already decoded into `scenarios.json` as `ramza_mandatory`.
const RAMZA_MANDATORY_KEY := "ramza_mandatory"

## The zone tiles this assignment may use, in the table's own order. Never mutated.
var tiles: Array[Vector2i] = []
## How many units may take the field — the zone record's `max_squad_size`, floored by
## the number of tiles and the size of the roster (a cap you cannot reach is not a cap).
var cap: int = 0

## Every unit that MAY be deployed, in roster order. The bench is this minus the placed.
var _candidates: Array = []
## Units that must be on the field before the assignment can be committed.
var _mandatory: Array = []
var _unit_by_tile: Dictionary = {}       # Vector2i -> unit
var _tile_by_unit: Dictionary = {}       # unit instance id -> Vector2i


## The assignment a scenario opens with: `candidates` (the player's own units, from
## [ScenarioCast]) over the scenario's first-squad deployment zone, with the mandatory
## unit resolved from the scenario's own flag. Every unit starts BENCHED — an empty
## assignment is the honest starting state, and [method auto_fill] is one call away.
##
## `slug_of` answers a unit's catalogue slug (the host passes
## `UnitSpawn.CHARACTER_SLUG_META`'s reader); it is a Callable so this class never has to
## know what a `Unit` is.
static func for_scenario(candidates: Array, scenario_id: int,
		slug_of: Callable = Callable()) -> DeploymentAssignment:
	var scenario: Dictionary = ScenarioDatabase.get_scenario(scenario_id)
	var zone: Dictionary = DeploymentZoneDatabase.get_zone(
		int(scenario.get("first_squad_deployment_idx", 0)))
	var mandatory: Array = []
	if bool(scenario.get(RAMZA_MANDATORY_KEY, false)) and slug_of.is_valid():
		for unit in candidates:
			if str(slug_of.call(unit)) == StoryMutationScript.RAMZA_SLUG:
				mandatory.append(unit)
	return DeploymentAssignment.new(candidates, zone, mandatory)


func _init(candidates: Array = [], zone: Dictionary = {}, mandatory: Array = []) -> void:
	_candidates = candidates.duplicate()
	_mandatory = mandatory.duplicate()
	for t in zone.get("tiles", []):
		tiles.append(Vector2i(int(t[0]), int(t[1])))
	# Floored by the two things that can make a declared cap unreachable. `max_squad_size`
	# defaults to the roster size, not to 0: a zone record with no cap means "bring
	# everyone who fits", and defaulting to 0 would silently forbid deployment entirely.
	cap = mini(mini(int(zone.get("max_squad_size", _candidates.size())), tiles.size()),
		_candidates.size())


# === Editing ==================================================================

## Stand `unit` on `tile`. Returns false and changes nothing when the move is illegal —
## an unknown unit, a tile outside the zone, a tile already taken, a bench unit that would
## push the squad over [member cap], or a NON-mandatory bench unit that would eat a slot
## [method reserved_slots] is holding. MOVING an already-placed unit is always legal (it
## does not change the squad size), which is what makes dragging a unit around the zone
## free while adding a seventh body is not.
func place(unit, tile: Vector2i) -> bool:
	if unit == null or not _candidates.has(unit):
		return false
	if not tiles.has(tile):
		return false
	if _unit_by_tile.has(tile) and _unit_by_tile[tile] != unit:
		return false
	if not is_placed(unit) and placed_count() >= effective_cap(unit):
		return false
	unplace(unit)
	_unit_by_tile[tile] = unit
	_tile_by_unit[unit.get_instance_id()] = tile
	return true


## Take `unit` off the field and back onto the bench. Returns false if it was not on it.
func unplace(unit) -> bool:
	if unit == null or not _tile_by_unit.has(unit.get_instance_id()):
		return false
	var tile: Vector2i = _tile_by_unit[unit.get_instance_id()]
	_unit_by_tile.erase(tile)
	_tile_by_unit.erase(unit.get_instance_id())
	return true


## Slots the mandatory units are holding: how many mandatory candidates are NOT yet on
## the field. Gariland reserves 1 until Ramza is down, then 0.
func reserved_slots() -> int:
	var held := 0
	for unit in _mandatory:
		if not is_placed(unit):
			held += 1
	return held


## The cap as it applies to `unit` — [member cap] less the slots [method reserved_slots]
## is holding, except for a mandatory unit itself, which is what those slots are FOR.
##
## The reserve is the difference between refusing a squad and refusing a PLACEMENT. Without
## it a player fills all five Gariland tiles with cadets, presses start, and is told "Ramza
## must be deployed" with the zone full and no indication of whom to bench — legal all the
## way to the commit and then refused at it. With it the fifth tile simply will not take a
## cadet, which says the same thing at the moment the player can act on it.
func effective_cap(unit = null) -> int:
	if unit != null and is_mandatory(unit):
		return cap
	return cap - reserved_slots()


## Bench everyone — the screen-level "throw my placements away".
##
## This is what CANCEL means in deployment, and it is why [TurnDirector.cancel] refuses
## the `DEPLOYMENT` state instead of answering it: there is no pre-turn image to restore
## because nothing has been written anywhere yet.
func clear() -> void:
	_unit_by_tile.clear()
	_tile_by_unit.clear()


## Fill the field automatically — the debug/test path, mirroring `--combat-autostart`.
## Mandatory units are hoisted to the front FIRST, so the flag is
## honoured by construction rather than by a claim about roster order, then
## [DeploymentPlan.assign] does the capped index-parallel fill it already owns.
func auto_fill() -> void:
	clear()
	var order: Array = _mandatory.duplicate()
	for unit in _candidates:
		if not order.has(unit):
			order.append(unit)
	for row in DeploymentPlan.assign(order, tiles, cap):
		place(row["unit"], row["tile"])


# === Reading ==================================================================

func is_placed(unit) -> bool:
	return unit != null and _tile_by_unit.has(unit.get_instance_id())


## Where `unit` stands, or [constant NO_TILE] if it is benched.
func tile_of(unit) -> Vector2i:
	if unit == null:
		return NO_TILE
	return _tile_by_unit.get(unit.get_instance_id(), NO_TILE)


## Who stands on `tile`, or null.
func unit_at(tile: Vector2i):
	return _unit_by_tile.get(tile, null)


func placed_count() -> int:
	return _unit_by_tile.size()


## The squad, as `[{ "unit": ..., "tile": Vector2i }]` in ZONE-TILE order — the order the
## host walks to place them, so the field fills the way the table reads.
func squad() -> Array:
	var out: Array = []
	for tile in tiles:
		if _unit_by_tile.has(tile):
			out.append({"unit": _unit_by_tile[tile], "tile": tile})
	return out


## The candidates left off the field, in roster order.
func benched() -> Array:
	var out: Array = []
	for unit in _candidates:
		if not is_placed(unit):
			out.append(unit)
	return out


func candidates() -> Array:
	return _candidates.duplicate()


func is_mandatory(unit) -> bool:
	return _mandatory.has(unit)


## Zone tiles nobody is standing on.
func free_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile in tiles:
		if not _unit_by_tile.has(tile):
			out.append(tile)
	return out


## What still stops this assignment being committed — empty means "start the battle".
##
## Reported as a LIST rather than a bool because the deployment screen has to say which
## rule you tripped; "commit is greyed out" with no reason is the shape of UI that makes
## a player think the game is broken.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if tiles.is_empty():
		out.append("this scenario has no deployment zone")
	if placed_count() == 0:
		out.append("no unit is deployed")
	if placed_count() > cap:
		out.append("squad of %d exceeds the zone's cap of %d" % [placed_count(), cap])
	for unit in _mandatory:
		if not is_placed(unit):
			out.append("%s must be deployed" % _label(unit))
	return out


func is_committable() -> bool:
	return problems().is_empty()


## A unit's display name for a message. `name` is display and identity is the catalogue
## slug (ADR-0180), so this is only ever read out loud — never compared.
func _label(unit) -> String:
	if unit != null and "name" in unit:
		return str(unit.name)
	return str(unit)
