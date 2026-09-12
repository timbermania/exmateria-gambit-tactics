extends RefCounted

## Element name -> AB_ELEMENT-bit translation (#110).
##
## The single encode-boundary site for converting parser-emitted element-name
## arrays from [code]items.json[/code] into the 8-bit element masks the
## compute shader reads from [code]U_ELEMENT_{ABSORB,CANCEL,HALF,WEAK}_MASK[/code].
## Bit indexing matches [code]GPUAbilityLoader.ELEMENT_MAP[/code] -- Fire=1
## through Dark=8 -- so the spell-side AB_ELEMENT and the target-side defense
## bit line up 1:1 (a Fire spell tests bit 1 on the unit's masks).
##
## The four masks compose across every equipped slot; this loader walks the
## five [code]EquipSlot.Slot[/code] values, ORs the per-slot element
## arrays, and returns one struct of four masks. The shared accessor is used by
##
##   - [code]GPUCombatPacker._extract_unit_config[/code] (arena, live Unit)
##   - [code]GPUCombatTestBase._build_gpu_config[/code] (test cfg path)
##
## so the two encode sites cannot disagree about precedence or slot coverage.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")

const ELEMENT_MAP: Dictionary = {
	"Fire": 1, "Ice": 2, "Lightning": 3, "Wind": 4,
	"Earth": 5, "Water": 6, "Holy": 7, "Dark": 8,
}


static func mask_from_names(names: Array) -> int:
	"""OR-combine element bits for each name. Unknown names are silently
	skipped (FFT only has the eight elements above)."""
	var mask := 0
	for n in names:
		var bit: int = int(ELEMENT_MAP.get(String(n), 0))
		if bit > 0:
			mask |= (1 << bit)
	return mask


static func defense_for_equipment(equipment: Dictionary) -> Dictionary:
	"""Compose the four element-defense masks across every equipped slot.

	[param equipment] is a dict keyed by [code]EquipSlot.Slot[/code]
	-> item_id (the same shape [code]UnitProgression.equipment[/code] holds).
	Items at -1 contribute nothing. Returns a dict of four masks; absent
	defenses round-trip to 0."""
	var absorb := 0
	var cancel := 0
	var half := 0
	var weak := 0
	for slot in equipment.keys():
		var item_id: int = int(equipment[slot])
		if item_id < 0:
			continue
		var elements = ItemDatabase.get_elements(item_id)
		absorb |= mask_from_names(elements.get("absorb", []))
		cancel |= mask_from_names(elements.get("cancel", []))
		half   |= mask_from_names(elements.get("half", []))
		weak   |= mask_from_names(elements.get("weak", []))
	return {
		"absorb_mask": absorb,
		"cancel_mask": cancel,
		"half_mask": half,
		"weak_mask": weak,
	}


static func strengthen_for_equipment(equipment: Dictionary) -> int:
	"""OR-fold the BoostElem byte across every equipped slot (attacker-side).

	Mirrors BATTLE.BIN [code]FUN_80185FFC[/code] at [code]ram:80185FFC[/code]
	via the SCUS aggregation loop at [code]0x8005C788[/code]: equipped items'
	[code]BoostElem[/code] fields OR together into unit [code]+0x71[/code],
	which the per-formula handlers test against the ability's element bit
	for the 5/4 (1.25x) AbPower scale. Items at -1 contribute nothing;
	absent strengthen rounds-trip to 0."""
	var mask := 0
	for slot in equipment.keys():
		var item_id: int = int(equipment[slot])
		if item_id < 0:
			continue
		mask |= mask_from_names(ItemDatabase.get_elements(item_id).get("strengthen", []))
	return mask
