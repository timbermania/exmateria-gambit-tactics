extends RefCounted

## Weapon Animation Selector
##
## Maps (item_type_id, vertical_angle, use_back) to a WEP1.SEQ slot id, plus
## frame-offset helpers for the WEP1 / WEP2 / EFF1 SHP zero-frames.
##
## Both halves are ROM-derived:
##
## - Slot selection: `weapon_wep1_anim_ids.json` (parsed by
##   `tools/parse_weapon_wep1_anim_ids.py`) joins
##   `weapon_animation_ids.json` (BATTLE.BIN 0x2d364 = per-item-type BODY
##   slot) with the `QueueSpriteAnim` opcode embedded in each TYPE1.SEQ
##   slot. The opcode is the engine's own statement of "which WEP1 slot
##   does this BODY animation drive."
##
## - Frame offsets: the host reads section 1 of each WEP/EFF SHP file
##   (parsed by `tools/parse_zero_frames.py`) and answers the three
##   `*_frame_offset` queries on `ContentPort`.
##
## The earlier hand-authored `WeaponCategory` enum + `CATEGORY_BASE` +
## `HAS_HEIGHT_VARIANTS` + `get_category_from_item_type` chain was a
## restatement of the WEP1.SEQ file layout — it produced the right
## answers because the layout it described is fixed by ROM, but it had
## no provenance and a future ROM change would not have flagged it.
## The JSON-backed path retires that whole chain.

# ADR-0223 dec. 8 — this line USED to name `JsonAsset` where `src/data/`
# declared it, which is ARM7_BURN_DOWN #809 and goal #5 unmet on the TYPE
# axis. The file moved to the port; naming the port is what a portable addon
# is ALLOWED to do (ADR-0139 dec. 12, `plugin.cfg` `deps=`), and the spelling
# below is unchanged (ADR-0212 dec. 1).
const JsonAsset = ExMateriaPlatform.JsonAsset

## `ContentPort` is `addons/exmateria_sprite_rig`'s, published on the addon's one
## global name; this aliases it back so the call sites below stay a verb rather
## than a façade walk (ADR-0211 dec. 4, ADR-0217 dec. 9). The port replaces a
## direct name for a host content store: this file no longer compiles against one.
const ContentPort = ExMateriaSpriteRig.ContentPort

enum VerticalAngle {
	HIGH,  # Attacking upward
	MID,   # Same level attack
	LOW    # Attacking downward
}

const _DATA_PATH := "res://addons/exmateria_sprite_rig/resources/weapon_wep1_anim_ids.json"
const _VERT_KEYS: Array[String] = ["high", "mid", "low"]

static var _data: Dictionary = {}
# Reverse-index: WEP1 anim id → [vertical, use_back]. Built at load
# time from _data so `remap_wep_anim_id` can decode an embedded source
# anim id back into (height, facing) without a hand-typed category map.
static var _reverse: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = JsonAsset.load_dict(_DATA_PATH)
	for type_key in _data:
		var entry: Dictionary = _data[type_key]
		for vert_idx in range(_VERT_KEYS.size()):
			var k: String = _VERT_KEYS[vert_idx]
			if not entry.has(k):
				continue
			var front_id := int(entry[k])
			# Front-facing variant
			if not _reverse.has(front_id):
				_reverse[front_id] = [vert_idx, false]
			# Back-facing variant is +1 by WEP1.SEQ convention
			var back_id := front_id + 1
			if not _reverse.has(back_id):
				_reverse[back_id] = [vert_idx, true]


static func get_vertical_angle(attacker_height: float, target_height: float) -> VerticalAngle:
	"""Calculate vertical angle from height difference.

	Uses thresholds to determine if attack is high, mid, or low:
	- High: Target is 1+ tiles above attacker
	- Low: Target is 1+ tiles below attacker
	- Mid: Target is within 1 tile of attacker's height

	Args:
		attacker_height: Attacker tile Y position
		target_height: Target tile Y position

	Returns:
		VerticalAngle enum value
	"""
	var height_diff = target_height - attacker_height

	if height_diff >= 1.0:
		return VerticalAngle.HIGH
	elif height_diff <= -1.0:
		return VerticalAngle.LOW
	else:
		return VerticalAngle.MID


static func get_wep_animation_id(item_type_id: int, vertical_angle: VerticalAngle, use_back: bool) -> int:
	"""Get WEP1 animation ID for the given parameters.

	Reads the ROM-joined table at `weapon_wep1_anim_ids.json`. Front-
	facing variants live at the keyed id; back-facing variants are
	front+1 (WEP1.SEQ slot convention).

	Args:
		item_type_id: Item type ID from ItemDatabase
		vertical_angle: HIGH, MID, or LOW based on target elevation
		use_back: true for back-facing variant, false for front

	Returns:
		WEP1 animation ID, or 0 if the item type has no entry (Unarmed,
		Shield, and throw items 32-34 fall out of this table — the
		caller in AnimationResolutionMap.resolve_attack handles those
		paths separately).
	"""
	_ensure_loaded()
	var entry: Dictionary = _data.get(str(item_type_id), {})
	if entry.is_empty():
		return 0
	var key: String = _VERT_KEYS[int(vertical_angle)]
	var front_id := int(entry.get(key, 0))
	return front_id + (1 if use_back else 0)


static func remap_wep_anim_id(original_anim_id: int, target_item_type_id: int) -> int:
	"""Remap a WEP1 animation ID to the correct animation for the equipped weapon.

	REACT BODY slots embed `QueueSpriteAnim` opcodes that may reference
	WEP1 slots authored for a different weapon than the unit has
	equipped. Decode the source anim id's (height, facing) via the
	reverse-index built from the ROM-joined table, then forward through
	`get_wep_animation_id` for the target weapon.

	Args:
		original_anim_id: WEP1 anim_id from QueueSpriteAnim opcode
		target_item_type_id: Item type ID of the equipped weapon

	Returns:
		Remapped WEP1 animation ID. Pass-through if the source id isn't
		in the reverse-index (unknown slot — better to play the original
		than guess wrong) or the target has no entry in the forward
		table (Unarmed / Shield / throw).
	"""
	_ensure_loaded()
	var decoded = _reverse.get(original_anim_id, null)
	if decoded == null:
		return original_anim_id
	var vertical: int = decoded[0]
	var use_back: bool = decoded[1]
	var target_entry: Dictionary = _data.get(str(target_item_type_id), {})
	if target_entry.is_empty():
		return original_anim_id
	return get_wep_animation_id(target_item_type_id, vertical as VerticalAngle, use_back)


## Frame-offset lookups (the "zero frame" base indices for WEP1 / WEP2 / EFF1)
## are ROM-derived — they live in section 1 of each WEP/EFF SHP file, parsed
## by tools/parse_zero_frames.py and read at runtime through `ContentPort`.
## The hand-typed FFTorama tables this file used to carry were retired; the
## ROM-extract surfaced one off-by-15 bug in the WEP2 Shuriken entry
## (was 420, ROM says 435 — latent because Shuriken is "unused" in WEP2).


static func get_wep_frame_offset(item_type_id: int, uses_wep2: bool = false) -> int:
	"""Get the WEP SHP frame offset for the given weapon type.

	The WEP SEQ animations use relative frame IDs (0, 1, 2...).
	This offset is added to those IDs to get the actual SHP frame.
	TYPE2 sprites use WEP2 SHP which has different frame boundaries.

	Example: Bow animation uses SEQ frame 3 → SHP frame 192+3 = 195 (WEP1)
	"""
	if uses_wep2:
		return ContentPort.wep2_frame_offset(item_type_id)
	return ContentPort.wep1_frame_offset(item_type_id)


static func get_eff1_frame_offset(item_type_id: int) -> int:
	"""Get the EFF1 SHP frame offset for the given weapon type.

	The EFF1 SEQ animations use relative frame IDs (0, 1, 2...). This offset
	is added to those IDs to get the actual SHP frame.

	Example: Bow eff1 animation uses SEQ frame 3 → SHP frame 90+3 = 93
	"""
	return ContentPort.eff1_frame_offset(item_type_id)
