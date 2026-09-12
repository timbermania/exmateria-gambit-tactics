extends RefCounted

## Database for FFT scenario records (the encounter-setup table).
##
## Loads scenario data from encounters/scenarios.json at first use and
## serves records by scenario_id. The JSON is the canonical source — a
## [committed extracted artifact](../../docs/context/08-scenario.md) emitted by
## `tools/parse_scenarios.py` from EVENT/ATTACK.OUT joined with the wiki-label
## name tables. Pure data, GPU/scene-agnostic — the same XDatabase shape as
## SpriteDatabase / JobDatabase. The scenario picker queries it for names
## without booting any orchestration ([ScenarioLoader](../scenario/ScenarioLoader.gd)
## applies a scenario). See CONTEXT.md "ScenarioDatabase".

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const SCENARIOS_PATH := "res://addons/exmateria_almanac/encounters/scenarios.json"

static var _scenarios: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	# The artifact wraps records under a "scenarios" object keyed by id-string.
	_scenarios = JsonAsset.load_dict(SCENARIOS_PATH, "scenarios")
	_loaded = true


## Get a scenario record by ID. Returns empty Dictionary if not found.
static func get_scenario(id: int) -> Dictionary:
	_ensure_loaded()
	return _scenarios.get(str(id), {})


## All scenario ids, ascending. Used by the picker.
static func all_ids() -> Array[int]:
	_ensure_loaded()
	var ids: Array[int] = []
	for key in _scenarios.keys():
		ids.append(int(key))
	ids.sort()
	return ids


## Picker rows: [{ "id": int, "scenario_name": String }, ...], ascending by id.
static func list_for_picker() -> Array:
	_ensure_loaded()
	var rows: Array = []
	for id in all_ids():
		var rec: Dictionary = _scenarios.get(str(id), {})
		rows.append({
			"id": id,
			"scenario_name": rec.get("scenario_name", "Scenario %d" % id),
		})
	return rows


## Force reload of scenario data (for debugging / hot edits).
static func reload() -> void:
	_loaded = false
	_scenarios = {}
	_ensure_loaded()
