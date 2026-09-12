extends RefCounted
## Selects which units to consider for gambit conditions or actions.
##
## Separates "who to check" from "how to pick one" using pool types
## and resolution strategies.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/gambits/TargetSelector.gd")
# ADR-0202 dec. 2 / ADR-0280 dec. 3 — `UnitRole` is the SHARED KERNEL's, not this
# addon's: ADR-0118 dec. 1's eleventh schema row, reached through the kernel's
# facade rather than by path because a `res://` literal leaving this addon root
# is arm 6 and this addon's arm-6 burn-down is EMPTY. Every reach INTO the
# kernel is free. `plugin.cfg`'s `deps=` declares it so the stranger rig stages
# it (#1159).
const UnitRole = ExMateriaSchema.UnitRole

## Pool type: defines which units to consider
enum PoolType {
	SELF,           ## Only the actor
	TRIGGERING,     ## The unit that triggered the gambit (set during evaluation)
	SPECIFIC_UNITS, ## Named units from a list
	TEAM_FILTER     ## All units matching team + optional role filter
}

## Resolution strategy: how to pick one unit from multiple candidates.
##
## === DEPTH IS A RESOLUTION, AND THAT IS WHY THERE IS NO NEW FIELD (ADR-0285) ================
##
## [constant NEAREST_FIRST] and [constant NEAREST_ONLY] run the IDENTICAL search — same path
## metric, same self-skip, same KO filter. They differ in HOW MANY candidates the pool is
## willing to offer: the first hands the slot's conditions rank 0, then rank 1, then rank 2…
## until one passes; the second hands them rank 0 and stops. So the condition FILTERS a pool
## under `NEAREST_FIRST` and GATES one unit under `NEAREST_ONLY`, and the sentence the player
## reads changes from *"an ally who is hurt"* to *"the nearest ally, if they are hurt"*.
##
## 🔴 [constant NEAREST_FIRST] WAS CALLED `NEAREST`, AND THE RENAME IS THE POINT OF THE TICKET.
## It is the member that is NOT "the nearest" — it is the pool search that merely STARTS there,
## and the kernel has always walked past rank 0 for it (`stage_compute.glsl`, Pass 2's rank
## loop). The surface's `Nearest Ally` row was that value under a label describing only its
## first guess, which is the exact defect ADR-0285 removes; leaving the domain member called
## `NEAREST` would have rebuilt that defect one layer down, where no screen test can see it.
## The int positions do not move, so the rename is free and no save migrates.
enum ResolutionStrategy {
	## Closest by PATH cost — travel distance, level-aware, walls counted — as the FIRST
	## guess, not the only one. The kernel retries ranks 1, 2, 3… (`find_nth_nearest`) when
	## rank 0 fails the slot's conditions, so this names the whole team as a pool that
	## happens to be walked in proximity order. The `To` column spells it `Ally` / `Foe`.
	NEAREST_FIRST,
	MOST_CRITICAL,  ## Lowest HP percentage
	HIGHEST_STAT,   ## Highest value of specified stat
	LOWEST_STAT,    ## Lowest value of specified stat
	FIRST_IN_ROSTER, ## First in roster order
	## The nearest by the SAME metric as [constant NEAREST_FIRST], and nobody else. Pass 2's
	## retry guard does not list this pool's GPU types, so a rank-0 candidate who fails the
	## condition ends the slot for the tick. The `To` column spells it `Nearest Ally` /
	## `Nearest Foe`. APPENDED, never inserted: `to_dict`/`from_dict` serialise the int.
	NEAREST_ONLY,
}

## Team filter for TEAM_FILTER pool type
enum TeamFilter {
	FRIENDLY,  ## Same team as actor
	ENEMY,     ## Opposite team from actor
	ANY        ## Any team
}

## The pool type
var pool_type: PoolType = PoolType.SELF

## Team filter (used when pool_type == TEAM_FILTER)
var team_filter: TeamFilter = TeamFilter.FRIENDLY

## Role filter (used when pool_type == TEAM_FILTER, -1 = any role)
var role_filter: UnitRole.Role = UnitRole.Role.ANY

## Specific unit names (used when pool_type == SPECIFIC_UNITS)
var unit_names: Array[String] = []

## Resolution strategy for selecting from multiple candidates
var resolution: ResolutionStrategy = ResolutionStrategy.NEAREST_FIRST

## Admit KO'd units into the pool (used when pool_type == TEAM_FILTER).
##
## Every pool is KO-BLIND by default: the kernel drops [code]is_unit_dead[/code]
## candidates before any condition sees them, which is why
## [constant GambitCondition.Type.IS_KO] could be decided but never REACHED (#1102).
## Setting this admits the corpse and leaves the slot's conditions to discriminate
## — the pool says who may be LOOKED at, the condition says what must be true.
## Only FRIENDLY + NEAREST_FIRST has a GPU spelling today ([code]TARGET_NEAREST_ALLY_OR_KO[/code]);
## any other combination is UNSUPPORTED at the encoder rather than silently KO-blind (ADR-0023).
var include_ko: bool = false

## Stat name for HIGHEST_STAT/LOWEST_STAT resolution
var stat_name: StringName = &""


func _to_string() -> String:
	match pool_type:
		PoolType.SELF:
			return "Self"
		PoolType.TRIGGERING:
			return "Triggering"
		PoolType.SPECIFIC_UNITS:
			return "Units(%s)" % ", ".join(unit_names)
		PoolType.TEAM_FILTER:
			var team_str = TeamFilter.keys()[team_filter]
			var role_str = UnitRole.get_role_name(role_filter)
			var ko_str = " (incl. KO)" if include_ko else ""
			if role_filter == UnitRole.Role.ANY:
				return "Any %s%s" % [team_str.capitalize(), ko_str]
			return "%s %s%s" % [role_str, team_str.capitalize(), ko_str]
	return "Unknown"


## Get structured data for UI display
func get_ui_display_data() -> Dictionary:
	return {
		"pool_type": PoolType.keys()[pool_type],
		"team_filter": TeamFilter.keys()[team_filter] if pool_type == PoolType.TEAM_FILTER else "",
		"role_filter": UnitRole.get_role_name(role_filter),
		"resolution": ResolutionStrategy.keys()[resolution],
		"include_ko": include_ko,
		"description": _to_string()
	}


# ============================================================================
# STATIC FACTORY METHODS
# ============================================================================

## Target self only
static func self_() -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.SELF
	return ts


## Target the unit that triggered this gambit
static func triggering() -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.TRIGGERING
	return ts


## Target friendly units (allies including self)
static func friendlies(role: UnitRole.Role = UnitRole.Role.ANY) -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.TEAM_FILTER
	ts.team_filter = TeamFilter.FRIENDLY
	ts.role_filter = role
	return ts


## Target friendly units INCLUDING the KO'd — the one pool a corpse survives.
##
## Pair with [method GambitCondition.is_ko] to reach the fallen ally, or with
## [method GambitCondition.is_alive] to get the KO-blind pool's behaviour back
## explicitly. Without a condition it is just [method friendlies] with the dead
## ranked in.
static func friendlies_or_ko(role: UnitRole.Role = UnitRole.Role.ANY) -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.TEAM_FILTER
	ts.team_filter = TeamFilter.FRIENDLY
	ts.role_filter = role
	ts.include_ko = true
	return ts


## Target enemy units
static func enemies(role: UnitRole.Role = UnitRole.Role.ANY) -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.TEAM_FILTER
	ts.team_filter = TeamFilter.ENEMY
	ts.role_filter = role
	return ts


## Target any unit (both teams)
## Target specific named units
static func specific(names: Array[String]) -> _Self:
	var ts = _Self.new()
	ts.pool_type = PoolType.SPECIFIC_UNITS
	ts.unit_names = names
	return ts


## Modify resolution strategy and return self (builder pattern)
func with_resolution(res: ResolutionStrategy, stat: StringName = &"") -> _Self:
	resolution = res
	stat_name = stat
	return self


# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Convert to dictionary for JSON serialization."""
	return {
		"pool_type": pool_type,
		"team_filter": team_filter,
		"role_filter": role_filter,
		"unit_names": Array(unit_names),
		"resolution": resolution,
		"stat_name": String(stat_name),
		"include_ko": include_ko,
	}


static func from_dict(data: Dictionary) -> _Self:
	"""Create from dictionary (JSON deserialization)."""
	var t = _Self.new()
	t.pool_type = data.get("pool_type", PoolType.SELF)
	t.team_filter = data.get("team_filter", TeamFilter.ANY)
	t.role_filter = data.get("role_filter", UnitRole.Role.ANY)
	t.unit_names.clear()
	for unit_name in data.get("unit_names", []):
		t.unit_names.append(unit_name)
	t.resolution = data.get("resolution", ResolutionStrategy.NEAREST_FIRST)
	t.stat_name = StringName(data.get("stat_name", ""))
	t.include_ko = data.get("include_ko", false)
	return t
