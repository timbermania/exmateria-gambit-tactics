extends RefCounted

## Database for FFT BattleConditionals — the battle "director" sets.
##
## Loads encounters/battle_conditionals.json (the committed extracted
## artifact emitted by `tools/export_battle_conditionals.py` from EVENT/BTLEVT.BIN)
## and serves one *set* per `battle_conditionals_id`. A set is a list of
## conditions; each condition is a list of requirement checks terminated by a
## single `Run Scenario N` result — the only *result* opcode in the generated
## [BattleConditionalOpcode] enum (ADR-0059); every other opcode is a
## requirement. During a battle the engine fires the first condition whose
## requirements all hold — `Run Scenario N` is how the story advances to the
## next scenario (see ScenarioDirector, and
## research/working_documents/SCENARIO_LOADING.md §3.2.5).
##
## The records this class serves carry `run_scenario` as a resolved integer
## field: `tools/export_battle_conditionals.py` consumes the opcode when it
## decodes BTLEVT.BIN, so nothing downstream of the JSON ever compares against
## the opcode value. ADR-0251 dec. 5 — this class held a
## `const OP_RUN_SCENARIO` off that enum which no caller had ever read, and
## deleting it (rather than aliasing or inlining it) is what lets this addon
## open with an EMPTY arm-7 burn-down.
##
## Pure data, GPU/scene-agnostic — same static-load shape as ScenarioDatabase.
## The interpreter lives in [ScenarioDirector]; this class only serves records.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const BC_PATH := "res://addons/exmateria_almanac/encounters/battle_conditionals.json"

static var _sets: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_sets = JsonAsset.load_dict(BC_PATH, "sets")


## The raw set record for a battle_conditionals_id, or {} if none.
## Shape: { "conditions": [ { "requirements": [...], "run_scenario": int|null,
##          "commands": [...] } ], "bytecode_start": int }.
static func get_set(bc_id: int) -> Dictionary:
	_ensure_loaded()
	return _sets.get(str(bc_id), {})


## True when a set exists for this id (bc_id 0 is the unused stub).
static func has_set(bc_id: int) -> bool:
	_ensure_loaded()
	return _sets.has(str(bc_id))


## All battle_conditionals_ids that have a set, ascending.
static func all_ids() -> Array[int]:
	_ensure_loaded()
	var ids: Array[int] = []
	for key in _sets.keys():
		ids.append(int(key))
	ids.sort()
	return ids
