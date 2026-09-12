extends RefCounted

## The FFT special_name -> birthday (month, day) table: the ROM data behind a
## unique's zodiac sign in the formation info panel (§14.6).
##
## FFT stores no zodiac byte — the sign is DERIVED from the birthday
## ([ExMateriaSchema.Zodiac.zodiac_from_birthday]). A unit built from a raw ENTD slot
## already carries its birthday ([Character.from_entd_slot] reads it directly);
## this table is for the OTHER path — the formation "show all templates" catalogue
## view, whose uniques are minted from the template store (which has no birthday).
## There [AllTemplatesSeeder] looks the unique's `special_name` up here to show its
## real glyph instead of the default.
##
## Pure data, scene/GPU-agnostic (same static-load shape as [UnitNames]). Source of
## truth: identity/unit_birthdays.json — INSIDE this addon (ADR-0251 dec. 2),
## extracted from the committed ENTD
## dump by tools/parse_unit_birthdays.py. Only special_names with a CONCRETE (non-
## Random) birthday are present — a unit that is Random in every ENTD appearance is
## intentionally absent (it has no fixed sign; the caller keeps the default).

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

# ADR-0118 dec. 1's TWELFTH schema row (ADR-0294 dec. 2). This file used to alias
# `ExMateriaAlmanac.UnitProgression` for one call, and those two lines were this
# addon's entire arm-5 debt against a package it never holds an instance of — it
# reached a unit's numbers in order to read a stored boundary table. The
# derivation is the kernel's now and this file names no sibling addon but the port.
const Zodiac = ExMateriaSchema.Zodiac

const PATH := "res://addons/exmateria_catalogue/identity/unit_birthdays.json"

static var _birthdays: Dictionary = {}   # decimal-special_name String -> [month, day]
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_birthdays = JsonAsset.load_dict(PATH).get("birthdays", {})


## True iff `special_name` has a known concrete birthday (and thus a fixed zodiac).
static func has(special_name: int) -> bool:
	_ensure_loaded()
	return _birthdays.has(str(special_name))


## The `[month, day]` birthday for `special_name`, or `[]` if none is known.
static func birthday_of(special_name: int) -> Array:
	_ensure_loaded()
	return _birthdays.get(str(special_name), [])


## The tropical zodiac sign ([ExMateriaSchema.Zodiac].Sign, 0..11) for `special_name`, or
## -1 when no concrete birthday is known — the caller then keeps the unit's default.
static func zodiac_of(special_name: int) -> int:
	var bd := birthday_of(special_name)
	if bd.size() != 2:
		return -1
	return Zodiac.zodiac_from_birthday(int(bd[0]), int(bd[1]))
