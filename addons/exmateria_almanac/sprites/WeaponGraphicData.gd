extends RefCounted

## Per-item battle-graphic data parsed from BATTLE.BIN's table at 0x2d3e4
## (see tools/parse_weapon_graphic_data.py). 144 entries — item ids 0x00..0x7F
## for weapons and 0x80..0x8F for shields.
##
## **Keyed by item id**, NOT by the FFTPatcher `graphic` field in items.json.
## That `graphic` field is the menu-icon sprite index and has no role in
## battle rendering (ffhacktics wiki "Item Graphics in Battle"). Passing the
## wrong key here samples the wrong region of WEP1.tga — e.g. Rod (item_id 51)
## samples Excalibur's row (item_id 35) when keyed by `items.json[51].graphic`.
##
## Each entry carries the WEP1 palette (held-weapon overlay), the EFF1 palette
## (swoosh / weapon gleam / swing-blur overlay; mostly 0 = default, non-zero
## for special weapons), and the vertical pixel offset into WEP1.tga that
## picks the specific weapon's row. The ffhacktics wiki labels the low nibble
## as "WEP2 palette" — that's almost certainly mislabeled: WEP2 aliases the
## same pixel bytes as WEP1 (per Shishi), and across 128 weapons X never
## equals Y when both are non-zero, which fits "default overlay unless this
## weapon has a custom effect color" not "alternate-angle of the same held
## weapon".
##
## ROM-derived; regenerate the JSON with parse_weapon_graphic_data.py
## if BATTLE.BIN changes.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const DATA_PATH := "res://addons/exmateria_almanac/sprites/weapon_graphic_data.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_data = JsonAsset.load_dict(DATA_PATH)
	_loaded = true


static func get_v_offset(item_id: int) -> int:
	_ensure_loaded()
	var entry: Dictionary = _data.get(str(item_id), {})
	return int(entry.get("wep1_v_offset_pixels", 0))


static func get_wep1_palette(item_id: int) -> int:
	_ensure_loaded()
	var entry: Dictionary = _data.get(str(item_id), {})
	return int(entry.get("wep1_palette", 0))


static func get_eff1_palette(item_id: int) -> int:
	_ensure_loaded()
	var entry: Dictionary = _data.get(str(item_id), {})
	return int(entry.get("eff1_palette", 0))
