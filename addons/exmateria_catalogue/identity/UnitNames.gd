extends RefCounted

## The FFT special_name table: an ENTD slot's `special_name` id -> the canonical
## story-character display name. This is the battle-cast SOURCING KEY (decision
## #181): a slot whose `special_name` resolves here is a CANONICAL story unit
## (look it up / build it FIXED); one that does not is a FACTORY-derived generic.
##
## Pure data, scene/GPU-agnostic (same static-load shape as the other X databases).
## Source of truth: identity/unit_names.json — INSIDE this addon (ADR-0251 dec. 2),
## transcribed from the vendored
## FFTPatcher UnitNames.xml by tools/build_unit_names.py. Only ids with a real name
## are present — blank/unused ids intentionally do NOT resolve (they fall through to
## the factory path).

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const PATH := "res://addons/exmateria_catalogue/identity/unit_names.json"

static var _names: Dictionary = {}   # decimal-id String -> name String
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_names = JsonAsset.load_dict(PATH).get("names", {})


## The canonical display name for `special_name`, or "" if it is not a known
## story id (a blank/unused entry or a factory-generic marker).
static func resolve(special_name: int) -> String:
	_ensure_loaded()
	return _names.get(str(special_name), "")


## True iff `special_name` names a canonical story character.
static func has(special_name: int) -> bool:
	_ensure_loaded()
	return _names.has(str(special_name))


## The lower-cased canonical name — the CharacterCatalog slug ("agrias"), or "".
static func slug_of(special_name: int) -> String:
	return resolve(special_name).to_lower()
