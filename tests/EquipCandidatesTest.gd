extends Node
## EquipCandidates guard — the ROM candidate-list rules (ITEM_EQUIPMENT_DATA.md, RE round 49).
## Pure, no GPU.
##
##   §2 slot legality  = pure item-id ranges (world_item_slot_category 0x80125374); the hand
##                       slots accept weapon OR shield (world_equip_candidate_builder 0x80124C54).
##   §3 inclusion      = party total > 0 (stock + equipped-across-roster, world_item_party_total
##                       0x801237E4); counts "NN/NN" = equipped / total.
##   §4 display order  = descending item id (the rebuilt acquisition-list order,
##                       world_item_list_sync 0x801221D8).
##   §8 row payload    = items.json bytes: graphic (icon cell), palette (icon CLUT selector),
##                       item_type_id → wtype (type-glyph key).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EquipCandidatesTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const EquipCandidates = ExMateriaAlmanac.EquipCandidates
const UnitProgression = ExMateriaAlmanac.UnitProgression



var _passed := 0
var _failed := 0


class StubProgression:
	var equipment: Dictionary = {}


class StubUnit:
	var progression = null


func _unit(equips: Dictionary) -> StubUnit:
	var u := StubUnit.new()
	var p := StubProgression.new()
	for slot in equips:
		p.equipment[slot] = equips[slot]
	u.progression = p
	return u


func _ready() -> void:
	# --- §2 the id-range classifier (ROM 0x80125374; worked examples from the live oracle) ---
	_expect(EquipCandidates.slot_category(19) == EquipCandidates.CAT_WEAPON, "Broad Sword (19) → weapon")
	_expect(EquipCandidates.slot_category(0x79) == EquipCandidates.CAT_WEAPON, "id 0x79 → weapon (last)")
	_expect(EquipCandidates.slot_category(122) == EquipCandidates.CAT_THROWN, "Shuriken (0x7A) → thrown/chemist cat 5")
	_expect(EquipCandidates.slot_category(128) == EquipCandidates.CAT_SHIELD, "Escutcheon (0x80) → shield")
	_expect(EquipCandidates.slot_category(157) == EquipCandidates.CAT_HEAD, "Leather Hat (0x9D) → head")
	_expect(EquipCandidates.slot_category(0xAB) == EquipCandidates.CAT_HEAD, "0xAB → head (last)")
	_expect(EquipCandidates.slot_category(0xAC) == EquipCandidates.CAT_BODY, "0xAC → body (first)")
	_expect(EquipCandidates.slot_category(186) == EquipCandidates.CAT_BODY, "Clothes (0xBA) → body")
	_expect(EquipCandidates.slot_category(208) == EquipCandidates.CAT_ACCESSORY, "Battle Boots (0xD0) → accessory")
	_expect(EquipCandidates.slot_category(253) == EquipCandidates.CAT_THROWN, "Phoenix Down (0xFD) → chemist cat 5")

	# --- §2 the slot gate: hands take weapon OR shield; the rest are exact ---
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.RIGHT_HAND, 19), "R.Hand accepts a sword")
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.RIGHT_HAND, 128), "R.Hand accepts a SHIELD (ROM-proven)")
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.LEFT_HAND, 19), "L.Hand accepts a sword")
	_expect(not EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.RIGHT_HAND, 157), "R.Hand rejects a hat")
	_expect(not EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.HEAD, 19), "Head rejects a sword")
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.HEAD, 157), "Head accepts a hat")
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.BODY, 186), "Body accepts Clothes")
	_expect(not EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.BODY, 157), "Body rejects a hat")
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.ACCESSORY, 208), "Accessory accepts boots")
	_expect(not EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.ACCESSORY, 122), "Accessory rejects Shuriken (cat 5)")

	# --- §3 ROM-faithful owned build: inclusion = party total > 0; counts equipped/total ---
	# Roster mirrors the sstate0 oracle shape: 4 units with Broad Sword equipped, one Dagger holder,
	# a Mythril Knife in STOCK only. R.Hand candidates = {19, 2, 1}; counts 4/4, 0/1, 1/1.
	var roster := []
	for i in 4:
		roster.append(_unit({UnitProgression.EquipSlot.RIGHT_HAND: 19, UnitProgression.EquipSlot.HEAD: 157}))
	roster.append(_unit({UnitProgression.EquipSlot.RIGHT_HAND: 1}))
	var stock := {2: 1}
	var hand := EquipCandidates.build(UnitProgression.EquipSlot.RIGHT_HAND, roster, stock)
	var ids := []
	for e in hand:
		ids.append(int(e["id"]))
	_expect(ids == [19, 2, 1], "owned R.Hand candidates desc-id [19,2,1], got %s" % [ids])
	if ids == [19, 2, 1]:
		_expect(int(hand[0]["equipped"]) == 4 and int(hand[0]["owned"]) == 4,
			"Broad Sword counts 4/4, got %d/%d" % [hand[0]["equipped"], hand[0]["owned"]])
		_expect(int(hand[1]["equipped"]) == 0 and int(hand[1]["owned"]) == 1,
			"Mythril Knife counts 0/1 (stock only), got %d/%d" % [hand[1]["equipped"], hand[1]["owned"]])
		_expect(int(hand[2]["equipped"]) == 1 and int(hand[2]["owned"]) == 1,
			"Dagger counts 1/1, got %d/%d" % [hand[2]["equipped"], hand[2]["owned"]])
		# §8 payload bytes come from items.json (ROM truth: 19 → graphic 12, palette 0, class 3 Sword)
		var bs: Dictionary = hand[0]
		_expect(int(bs["graphic"]) == 12 and int(bs["palette"]) == 0 and int(bs["wtype"]) == 3,
			"Broad Sword payload graphic/palette/wtype = 12/0/3, got %s/%s/%s" % [bs["graphic"], bs["palette"], bs["wtype"]])
		_expect(String(bs["name"]) == "Broad Sword", "name from items.json, got %s" % bs["name"])
	var head := EquipCandidates.build(UnitProgression.EquipSlot.HEAD, roster, stock)
	_expect(head.size() == 1 and int(head[0]["id"]) == 157,
		"Head candidates = [157 Leather Hat], got %s" % [head])
	if head.size() == 1:
		_expect(int(head[0]["palette"]) == 11 and int(head[0]["graphic"]) == 90 and int(head[0]["wtype"]) == 21,
			"Leather Hat payload graphic/palette/wtype = 90/11/21, got %s/%s/%s"
			% [head[0]["graphic"], head[0]["palette"], head[0]["wtype"]])

	# --- the full-catalog build (the user's "every item that could go in that slot") ---
	var cat := EquipCandidates.build_catalog(UnitProgression.EquipSlot.HEAD, roster, stock)
	_expect(cat.size() == 0xAC - 0x90, "Head catalog = all 28 head items, got %d" % cat.size())
	if cat.size() >= 2:
		_expect(int(cat[0]["id"]) == 0xAB and int(cat[-1]["id"]) == 0x90,
			"catalog descending id 0xAB..0x90, got %s..%s" % [cat[0]["id"], cat[-1]["id"]])
	# equipped items still carry their counts in the catalog view
	var hat_row := {}
	for e in cat:
		if int(e["id"]) == 157:
			hat_row = e
	_expect(not hat_row.is_empty() and int(hat_row["equipped"]) == 4 and int(hat_row["owned"]) == 4,
		"Leather Hat catalog counts 4/4, got %s" % [hat_row])
	var hands_cat := EquipCandidates.build_catalog(UnitProgression.EquipSlot.LEFT_HAND, roster, stock)
	var has_shield := false
	var has_thrown := false
	for e in hands_cat:
		if EquipCandidates.slot_category(int(e["id"])) == EquipCandidates.CAT_SHIELD:
			has_shield = true
		if EquipCandidates.slot_category(int(e["id"])) == EquipCandidates.CAT_THROWN:
			has_thrown = true
	_expect(has_shield, "hand catalog includes shields")
	_expect(not has_thrown, "hand catalog excludes thrown/chemist (cat 5)")

	if _failed > 0:
		print("[FAIL] EquipCandidatesTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipCandidatesTest: %d checks — slot legality + owned build + catalog build" % _passed)
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
