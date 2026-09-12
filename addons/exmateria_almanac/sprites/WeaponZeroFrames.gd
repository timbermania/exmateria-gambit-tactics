extends RefCounted

## Per-weapon-family SHP-frame base indices ("zero frames"), parsed from
## section 1 of WEP1.SHP / WEP2.SHP / EFF1.SHP (see tools/parse_zero_frames.py).
##
## Resolves "which SHP frame does my attack at logical step N look at?":
##
##     shp_frame = WeaponZeroFrames.get_wep1_offset(item_type_id) + anim_frame
##
## Combined with WeaponGraphicData.get_v_offset(graphic) (which picks the
## texture-row of WEP1.tga for the specific weapon graphic), this gives the
## full sample location.
##
## item_type_id keys are baked at parse time — callers pass item_type_id
## directly with no remap. item_type_ids 20..31 and 34 (Consumable) have no
## entry; lookups return 0.
##
## ROM-derived; regenerate the JSON with parse_zero_frames.py if any of the
## three SHP files change.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const DATA_PATH := "res://addons/exmateria_almanac/sprites/wep_zero_frames.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_data = JsonAsset.load_dict(DATA_PATH)
	_loaded = true


static func _lookup(sheet: String, item_type_id: int) -> int:
	_ensure_loaded()
	var sheet_map: Dictionary = _data.get(sheet, {})
	return int(sheet_map.get(str(item_type_id), 0))


static func get_wep1_offset(item_type_id: int) -> int:
	return _lookup("wep1", item_type_id)


static func get_wep2_offset(item_type_id: int) -> int:
	return _lookup("wep2", item_type_id)


static func get_eff1_offset(item_type_id: int) -> int:
	return _lookup("eff1", item_type_id)
