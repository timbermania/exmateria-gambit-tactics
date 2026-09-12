extends RefCounted

## The ROM equip-picker candidate rules (research/working_documents/ITEM_EQUIPMENT_DATA.md,
## RE round 49) as a pure mapping over items.json (ItemDatabase):
##
##   - slot legality = pure item-ID ranges (world_item_slot_category 0x80125374). The picker
##     never reads the slot_flags record byte; hands accept weapon OR shield
##     (world_equip_candidate_builder 0x80124C54 slot gate).
##   - inclusion (ROM `build`) = party total > 0, total = stock + equipped-across-roster
##     (world_item_party_total 0x801237E4); counts "NN/NN" = equipped / total.
##   - display order = descending item id — the ROM's per-category acquisition lists rebuilt
##     from scratch (world_item_list_sync 0x801221D8 front-inserts an ascending id scan).
##   - row payload = the 12-byte record bytes items.json mirrors 1:1 (byte-compared, 254/254):
##     `graphic` (icon cell), `palette` (icon CLUT selector, CLUT id 0x3FA8+pal), and
##     `item_type_id` → `wtype` (the class byte keying the type-glyph LUT).
##
## `build()` is the ROM-faithful owned-candidates list; `build_catalog()` lists EVERY
## slot-legal item (the port's picker default — the party has no shop economy yet, and the
## product ask is "every item that could go in the slot", job filters out of scope).
## Job equippability (ROM candidate flag 0x4000 → greyed rows) is deliberately NOT here.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")
# The four-arm match below needs the SLOT NAMES, not a unit's numbers, so it reaches
# the vocabulary directly. It used to reach `UnitProgression`, which is `state`; the
# vocabulary was split out by #1123 and is now the SHARED KERNEL's (ADR-0118 dec. 1's
# twelfth row, ADR-0294 dec. 2). This reach is FREE — reaching the kernel is what
# ADR-0202 dec. 2 permits, and it is the reason the move went DOWN rather than into
# the catalogue, which would have made this line almanac -> catalogue and inverted
# the declared edge.
const EquipSlot = ExMateriaSchema.EquipSlot

# ROM item categories (world_item_slot_category 0x80125374). CAT_THROWN covers both the
# throwable weapons (0x7A-0x7F Shuriken/Balls) and chemist items (>=0xF0) — the ROM returns
# the same category 5 for both, and no equip slot accepts it.
const CAT_WEAPON := 0
const CAT_SHIELD := 1
const CAT_HEAD := 2
const CAT_BODY := 3
const CAT_ACCESSORY := 4
const CAT_THROWN := 5

const _MAX_ITEM_ID := 0xFD  # the ROM builder scans ids 1..0xFD


static func slot_category(item_id: int) -> int:
	"""The ROM id-range classifier (0x80125374)."""
	var id := item_id & 0x3ff
	if id < 0x7A:
		return CAT_WEAPON
	if id < 0x80:
		return CAT_THROWN
	if id < 0x90:
		return CAT_SHIELD
	if id < 0xAC:
		return CAT_HEAD
	if id < 0xD0:
		return CAT_BODY
	if id < 0xF0:
		return CAT_ACCESSORY
	return CAT_THROWN


static func legal_for_slot(slot: int, item_id: int) -> bool:
	"""The ROM builder's slot gate (0x80124C54): hands accept weapon OR shield, the
	armor slots are category-exact. `slot` is an `EquipSlot.Slot`."""
	var cat := slot_category(item_id)
	match slot:
		EquipSlot.Slot.RIGHT_HAND, EquipSlot.Slot.LEFT_HAND:
			return cat <= CAT_SHIELD
		EquipSlot.Slot.HEAD:
			return cat == CAT_HEAD
		EquipSlot.Slot.BODY:
			return cat == CAT_BODY
		EquipSlot.Slot.ACCESSORY:
			return cat == CAT_ACCESSORY
	return false


static func build(slot: int, roster: Array, stock: Dictionary = {}) -> Array:
	"""The ROM-faithful candidate list: every slot-legal item the party possesses
	(stock + equipped anywhere on the roster), descending item id. Entries are
	picker rows: {id, name, graphic, palette, wtype, owned, equipped}."""
	var counts := _party_counts(roster, stock)
	var out: Array = []
	for id in _ids_descending():
		if not legal_for_slot(slot, id):
			continue
		var c: Dictionary = counts.get(id, {})
		var total := int(c.get("total", 0))
		if total <= 0:
			continue
		out.append(_entry(id, int(c.get("equipped", 0)), total))
	return out


static func build_catalog(slot: int, roster: Array = [], stock: Dictionary = {}) -> Array:
	"""EVERY slot-legal item (ownership ignored), descending item id — the port picker's
	default listing. Counts still report the real party state (00/NN or 00/00)."""
	var counts := _party_counts(roster, stock)
	var out: Array = []
	for id in _ids_descending():
		if not legal_for_slot(slot, id):
			continue
		var c: Dictionary = counts.get(id, {})
		out.append(_entry(id, int(c.get("equipped", 0)), int(c.get("total", 0))))
	return out


static func _ids_descending() -> Array:
	var ids: Array = []
	for id in range(_MAX_ITEM_ID, 0, -1):
		ids.append(id)
	return ids


static func _party_counts(roster: Array, stock: Dictionary) -> Dictionary:
	"""id → {equipped, total}: equipped = across every roster unit's 5 slots
	(world_item_equipped_count 0x80123764); total = equipped + stock
	(world_item_party_total 0x801237E4)."""
	var counts := {}
	for unit in roster:
		var prog = unit.progression if unit != null else null
		if prog == null:
			continue
		for slot in prog.equipment:
			var id := int(prog.equipment[slot])
			if id <= 0:
				continue
			var c: Dictionary = counts.get_or_add(id, {"equipped": 0, "total": 0})
			c["equipped"] = int(c["equipped"]) + 1
			c["total"] = int(c["total"]) + 1
	for id in stock:
		var c: Dictionary = counts.get_or_add(int(id), {"equipped": 0, "total": 0})
		c["total"] = int(c["total"]) + int(stock[id])
	return counts


static func _entry(id: int, equipped: int, total: int) -> Dictionary:
	var item := ItemDatabase.get_item(id)
	return {
		"id": id,
		"name": String(item.get("name", "Unknown")),
		"graphic": int(item.get("graphic", 0)),
		"palette": int(item.get("palette", 0)),
		"wtype": int(item.get("item_type_id", 0)),
		"equipped": equipped,
		"owned": total,
	}
