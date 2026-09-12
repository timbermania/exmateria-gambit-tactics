extends RefCounted

## Database for FFT sprite metadata.
##
## Loads sprite data from sprites/sprite_types.json at first use
## and provides lookup methods. The JSON is the canonical source — a
## [committed extracted artifact](../../docs/context/01-asset-extraction.md)
## emitted by `tools/parse_sprite_types.py` from BATTLE.BIN offset 0x2D748.
## See CONTEXT.md "Hand-authored data asset" for the loader-pattern rationale.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const SPRITES_PATH := "res://addons/exmateria_almanac/sprites/sprite_types.json"

static var _sprites: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_sprites = JsonAsset.load_dict(SPRITES_PATH)
	_loaded = true


## Normalize an int or string sprite id to the JSON key form ("9A", "00").
static func _key(sprite_id) -> String:
	if sprite_id is String:
		return sprite_id.to_upper()
	return "%02X" % int(sprite_id)


## Get sprite metadata by ID (integer or hex string).
## Returns empty Dictionary if not found.
static func get_sprite(sprite_id) -> Dictionary:
	_ensure_loaded()
	return _sprites.get(_key(sprite_id), {})


## Get the SHP type name for a sprite (e.g., "TYPE1", "MON").
static func get_shp_type(sprite_id) -> String:
	var data = get_sprite(sprite_id)
	return data.get("shp", "")


## Get the SEQ type name for a sprite (e.g., "TYPE1", "MON").
static func get_seq_type(sprite_id) -> String:
	var data = get_sprite(sprite_id)
	return data.get("seq", "")


## Get the sprite's standing height (pixels). Used by the spell-charge
## convergence anchor — PSX original `FUN_8008dc74` at `0x801b1e4c`. See
## `research/working_documents/spell_charge_lines_system.md`.
static func get_height(sprite_id) -> int:
	var data = get_sprite(sprite_id)
	return data.get("height", 0)


## Force reload of sprite data (for debugging / hot edits).
static func reload() -> void:
	_loaded = false
	_sprites = {}
	_ensure_loaded()
