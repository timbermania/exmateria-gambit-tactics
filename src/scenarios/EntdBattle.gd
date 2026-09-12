class_name EntdBattle
extends RefCounted

## ENTD-driven battle-init helpers for the game navigator (HANDOFF_navigator_run_1to7.md
## T3, decision #180). The Orbonne battle is built by partitioning the ALREADY-spawned
## world units by the ENTD `team_color` (Blue -> team0, Red -> team1) and handing the
## two teams to CombatLoop.start_battle. GPUArena composes the same way since ADR-0180
## retired the hardcoded per-side rosters it used to split on.
##
## This class holds the PURE, scene-free pieces of that bridge (team partitioning);
## the live `start_entd_battle(entd_record, map, seed)` scene bridge — which spawns
## the Units and calls the loop — lives on the navigator Node and is verified headful.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

## ENTD `team_color`: 0=Blue, 1=Red, 2=Green, 3=LightBlue (ENTD_FORMAT.md flags2).
## The empty-slot sentinel `unit_id` (a record with no unit).
const ENTD_EMPTY_UID := 0xFF

## ENTD `special_name`s of present-but-non-combatant story NPCs to keep OUT of the
## auto-battle (Orbonne: Ovelia 0x0C, the abduction target — she stands, she doesn't
## fight). A protected NPC left in never engages, so the GPU sim's "all survivors
## victorious" check never fires -> no victory handoff. General NPC detection: follow-up.
const NON_COMBATANT_SPECIALS := [0x0C]

## The extracted ENTD table (XDatabase shape: `{"records": {"<idx>": {...}}}`).
const ENTD_JSON_PATH := "res://assets/scenarios/entd.json"

static var _records: Dictionary = {}
static var _records_loaded: bool = false


## One ENTD record by its string key ("388" = Gariland), or null if unknown. Lazily
## loaded and cached for the process — the file is ~1 MB and the per-scene readers that
## used to open it re-parsed the whole thing on every call.
static func record(record_key: String) -> Variant:
	if not _records_loaded:
		_records = JsonAsset.load_dict(ENTD_JSON_PATH, "records")
		_records_loaded = true
	return _records.get(record_key, null)


## The slots of `entd_record` that are ACTUALLY on the field and meant to fight — the
## battle roster both hosts compose from. Three exclusions, each with a reason:
##   - the empty-slot sentinel (`unit_id` 0xFF) is not a unit;
##   - `always_present == false` slots are event-JOIN units (Delita 0x05 at Orbonne, the
##     abduct chocobo, the control-dups) that are not on the field at battle start —
##     excluding them matches the PSX presence gate used at spawn;
##   - [constant NON_COMBATANT_SPECIALS] are present but protected (see above).
## `entd_record` may be null (-> []). Pure: slot dicts are returned unchanged.
static func combatant_slots(entd_record) -> Array:
	var out: Array = []
	if entd_record == null:
		return out
	for slot in entd_record.get("slots", []):
		if int(slot.get("unit_id", ENTD_EMPTY_UID)) == ENTD_EMPTY_UID:
			continue
		if not bool(slot.get("flags2_decoded", {}).get("always_present", false)):
			continue
		if int(slot.get("special_name", ENTD_EMPTY_UID)) in NON_COMBATANT_SPECIALS:
			continue
		out.append(slot)
	return out


## The combat team index (0 or 1) for an ENTD `team_color`. Blue (0) is team0 (the
## player side at Orbonne); every other color routes to team1 (the enemy side).
static func team_index_for_color(team_color: int) -> int:
	return 0 if team_color == 0 else 1


## The named binary team policy (wayfinder #234 A): Blue → team0, every other color →
## team1. CombatLoop is hard 2-team, so all of green/light-blue collapse to team1; this
## is the SINGLE hook where any future N-faction/alliance split would reopen. Alias of
## team_index_for_color under the name the seam design uses.
static func team_of(team_color: int) -> int:
	return team_index_for_color(team_color)


## Compose the two combat sides for a roster-fed battle (wayfinder #234 A2):
##   team0 = deployed_owned  ∪  ENTD-blue slots
##   team1 = ENTD-non-blue slots
## `deployed_owned` are the player's already-placed units (any list; empty at Orbonne,
## the DEGENERATE case that yields the baked ENTD-blue cast unchanged). `entd_slots`
## are ENTD slot dicts, partitioned by `team_of(team_color)`; empty slots (0xFF) drop.
## Deployed units lead team0, in their given order, ahead of the ENTD-blue guests
## (e.g. Delita).
##
## `team0_spawn` / `team1_spawn` are optional per-side transforms applied to that side's
## ENTD slots before combining — the seam the live path uses to combat-ready the raw
## slots into `Unit`s (deployed_owned units are already live and pass through untouched).
## Omit both (the default) for the pure slots-in/slots-out contract the guard test pins.
static func compose_teams(deployed_owned: Array, entd_slots: Array,
		team0_spawn := Callable(), team1_spawn := Callable()) -> Dictionary:
	var split := split_slots(entd_slots)
	var blue: Array = team0_spawn.call(split["team0"]) if team0_spawn.is_valid() else split["team0"]
	var red: Array = team1_spawn.call(split["team1"]) if team1_spawn.is_valid() else split["team1"]
	var team0: Array = deployed_owned.duplicate()
	team0.append_array(blue)
	return {"team0": team0, "team1": red}


## Partition a list of ENTD slots into { "team0": [...], "team1": [...] } by
## team_color, skipping empty slots. Slot dicts are returned unchanged (the caller
## still owns spawning + placement); this only decides the sides.
static func split_slots(slots: Array) -> Dictionary:
	var out := {"team0": [], "team1": []}
	for slot in slots:
		if int(slot.get("unit_id", ENTD_EMPTY_UID)) == ENTD_EMPTY_UID:
			continue
		var key := "team0" if team_index_for_color(int(slot.get("team_color", 0))) == 0 else "team1"
		out[key].append(slot)
	return out
