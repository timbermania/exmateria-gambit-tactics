extends RefCounted

## Database for FFT deployment-zone records (player START tiles).
##
## Loads encounters/deployment_zones.json at first use and serves a zone
## by its deployment_idx (a scenario's first_squad_deployment_idx /
## second_squad_deployment_idx point here). The JSON is a [committed extracted
## artifact](../../docs/context/12-strategy-phase.md) emitted by
## `tools/parse_placement.py` from EVENT/ATTACK.OUT (0xBBD4 table), with the
## footprint bitmap decoded to real tile coords (the `1 << idx` fix). Pure data,
## GPU/scene-agnostic — the same XDatabase shape as ScenarioDatabase.
##
## A zone is the player's SPAWN tiles: units auto-fill onto them at phase entry,
## then march to a contested objective (ADR-0043 addendum). Empty/idx-0 records
## are dropped at parse time, so a missing key == "no zone" == procedural fallback.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const ZONES_PATH := "res://addons/exmateria_almanac/encounters/deployment_zones.json"

static var _zones: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_zones = JsonAsset.load_dict(ZONES_PATH, "zones")
	_loaded = true


## Get a deployment-zone record by deployment_idx. Returns {} if not found
## (idx 0 or any dropped-empty record), which signals procedural fallback.
static func get_zone(idx: int) -> Dictionary:
	_ensure_loaded()
	return _zones.get(str(idx), {})


## True if a real (non-empty) zone exists for this deployment_idx.
static func has_zone(idx: int) -> bool:
	_ensure_loaded()
	return idx != 0 and _zones.has(str(idx))


## Force reload (debugging / hot edits).
static func reload() -> void:
	_loaded = false
	_zones = {}
	_ensure_loaded()
