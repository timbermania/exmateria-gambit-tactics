extends RefCounted

## Semantic labels for the global FFT SFX banks (system, env).
##
## Loads the hand-authored assets/audio/sfx_banks/sfx_bank_names.json so the
## sound player can address bank slots by name ("gun_shot_loud_1") instead of a
## magic id (0x5B). The label set is wiki knowledge (Event Instructions {21} /
## {6B}; see research/wiki_articles/event_instructions_sound.md) and is NOT
## ISO-derived — the .feds bank blobs are; this names their slots.
##
## Referenced by path-preload (not class_name) so a fresh checkout resolves it
## without an editor cache rebuild — the ADR-0004 convention (its `BaseRoster` example
## is retired; `tools/check_path_extends.py` now enforces the rule itself).
##
## Vault: [[Event Sound OpCodes]]
## Vault: [[Scenario Table]]

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const NAMES_PATH := "res://assets/audio/sfx_banks/sfx_bank_names.json"

# This file used to path-preload `JsonAsset` to stay free of the editor class
# cache. #809 moved the loader into the port, and ADR-0211 dec. 4 rules that a
# HOST may alias a published constant but may NOT preload an addon path — so the
# reach goes through the façade alias above, and the class cache is back in play
# for this script exactly as it is for every other host namer of the port.

static var _loaded: bool = false
static var _banks: Dictionary = {}         # bank -> { str(slot) -> {name,slug,loop,hex} }
static var _slug_to_slot: Dictionary = {}  # bank -> { slug -> int(slot) }


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data := JsonAsset.load_dict(NAMES_PATH)
	for bank in data.keys():
		if String(bank).begins_with("_"):
			continue  # skip the _comment provenance field
		var sounds: Dictionary = data[bank]
		_banks[bank] = sounds
		var s2s: Dictionary = {}
		for slot_str in sounds.keys():
			s2s[sounds[slot_str]["slug"]] = int(slot_str)
		_slug_to_slot[bank] = s2s


static func slot_for(bank: String, slug: String) -> int:
	## Resolve a semantic slug to its bank slot, or -1 if unknown.
	_ensure_loaded()
	return int(_slug_to_slot.get(bank, {}).get(slug, -1))


static func name_for(bank: String, slot: int) -> String:
	## Human-readable name for a bank slot ("" if unknown).
	_ensure_loaded()
	var e: Dictionary = _banks.get(bank, {}).get(str(slot), {})
	return e.get("name", "")


static func slug_for(bank: String, slot: int) -> String:
	## Stable slug for a bank slot ("" if unknown).
	_ensure_loaded()
	var e: Dictionary = _banks.get(bank, {}).get(str(slot), {})
	return e.get("slug", "")


static func is_loop(bank: String, slot: int) -> bool:
	## Whether the slot is a looping/continuous sound (wiki '*' marker).
	_ensure_loaded()
	var e: Dictionary = _banks.get(bank, {}).get(str(slot), {})
	return bool(e.get("loop", false))


static func bank_sounds(bank: String) -> Dictionary:
	## All labels for a bank: { str(slot) -> {name,slug,loop,hex} }. For debug UIs.
	_ensure_loaded()
	return _banks.get(bank, {})
