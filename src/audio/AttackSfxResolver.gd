extends RefCounted

## Resolves a unit's basic-melee attack SFX from its EQUIPPED WEAPON:
##   weapon graphic id -> sound_class -> {swing, hit, block} system-bank slugs.
## The swing plays at the ATTACKING animation onset, the hit at melee impact,
## the block when the target guards.
##
## PROVEN LIVE IN PCSX (2026-06-11): FFT's dispatcher FUN_80082620 keys the
## basic-attack sound off `unit+0x1ab` — which is the EQUIPPED WEAPON's `graphic`
## id — through the weapon->sound-class table at SCUS 0x80062eb8 (byte +5). It is
## the WEAPON, not the unit sprite/job. Ground truth: a Ninja's Dagger (graphic
## 1) and Mythril Knife (graphic 2) each fed their own graphic in -> both class 1;
## a Rune Blade (graphic 0x13) -> class 3. So an Archer holding a sword slashes
## (sword graphic -> class 2/3); it does not play a bow sound. Knife/dagger of the
## same family collapse to one class, so the whole family shares a sound.
##
## The graphic comes straight from the game's own item data
## (ItemDatabase.get_weapon_graphic / items.json `graphic`). No per-job guessing —
## every weapon resolves exactly per the ROM table baked into attack_sounds.json.
## Unarmed (no weapon) = graphic 0 = fists (class 0). Ranged weapons (bow/gun)
## also have a melee class here, but a *ranged* attack fires a projectile whose
## sound comes from the projectile path, not this one.
##
## Referenced by path-preload (not class_name) so a fresh checkout resolves it
## without an editor cache rebuild — same reasoning as SfxCatalog (ADR-0004).
##
## Vault: [[Battle Action SFX]]

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const ATTACK_SOUNDS_PATH := "res://assets/audio/sfx_banks/attack_sounds.json"

# This file used to path-preload `JsonAsset` to stay free of the editor class
# cache. #809 moved the loader into the port, and ADR-0211 dec. 4 rules that a
# HOST may alias a published constant but may NOT preload an addon path — so the
# reach goes through the façade alias above, and the class cache is back in play
# for this script exactly as it is for every other host namer of the port.

const UNARMED_GRAPHIC := 0
const NO_CLASS := -1

static var _loaded: bool = false
static var _by_graphic: Dictionary = {}   # str(graphic) -> {sound_class, swing, hit, block}
static var _by_class: Dictionary = {}      # str(class)   -> {swing, hit, block}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonAsset.load_dict(ATTACK_SOUNDS_PATH)
	_by_graphic = data.get("by_weapon_graphic", {})
	_by_class = data.get("by_sound_class", {})


static func sound_class_for_weapon(weapon_graphic: int) -> int:
	## The basic-melee sound class for an equipped weapon's graphic id, or
	## NO_CLASS (-1) if the graphic isn't in the table.
	_ensure_loaded()
	var row: Dictionary = _by_graphic.get(str(weapon_graphic), {})
	return int(row.get("sound_class", NO_CLASS)) if not row.is_empty() else NO_CLASS


static func attack_sounds_for_weapon(weapon_graphic: int) -> Dictionary:
	## { "swing": slug, "hit": slug, "block": slug } for the weapon's sound class.
	## A field is "" when the graphic is unknown or that sound is silent (null
	## slug in the ROM table).
	_ensure_loaded()
	var row: Dictionary = _by_graphic.get(str(weapon_graphic), {})
	if row.is_empty():
		return {"swing": "", "hit": "", "block": ""}
	return {
		"swing": _slug(row, "swing"),
		"hit": _slug(row, "hit"),
		"block": _slug(row, "block"),
	}


static func _slug(row: Dictionary, key: String) -> String:
	var entry: Dictionary = row.get(key, {})
	var slug: Variant = entry.get("slug", null)
	return String(slug) if slug != null else ""
