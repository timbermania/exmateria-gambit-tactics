extends Node
# test-kind: logic
# seeded-break: change TIER_NEVER in ShopAvailabilityDatabase.gd from 20 to 21, or
#   flip the shift in is_stocked() from (0x8000 >> slot) to (1 << slot).
## ShopAvailabilityDatabase guard — the ROM's shop gate and its story timeline.
##
## The gate is `FUN_8012502C` (WORLD.BIN): an item is stocked only if the shop's
## bit is set in its big-endian u16 slot mask at 0x8018D844 + id*2, AND the
## reached tier is >= rec[10] (0x80062EC2 + id*12).
##
##   @0x8012518C/98  the mask read, hi byte then lo byte  -> big-endian
##   @0x801251A8/AC  and mask, (0x8000 >> shop_slot); zero -> not stocked
##   @0x801251BC     lbu rec[10]
##   @0x801251C8/CC  slt tier, avail; taken -> not unlocked yet
##
## The timeline half comes from the 44 `Zero 0x6F; Add n` pairs in TEST.EVT,
## whose event index IS a scenario_id. Citations:
## research/working_documents/ITEM_AVAILABILITY_TIMELINE.md.
##
## Pure data, no frame, no GPU.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/ShopAvailabilityDatabaseTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface.
const ShopAvailabilityDatabase = ExMateriaAlmanac.ShopAvailabilityDatabase

var _passed := 0
var _failed := 0


func _ready() -> void:
	# --- the tier byte, rec[10] ------------------------------------------------
	_expect(ShopAvailabilityDatabase.tier_of(1) == 1, "Dagger (1) is tier 1")
	_expect(ShopAvailabilityDatabase.tier_of(19) == 1, "Broad Sword (19) is tier 1")
	_expect(ShopAvailabilityDatabase.tier_of(35) == ShopAvailabilityDatabase.TIER_NEVER,
		"Excalibur (35) is never sold, got %d" % ShopAvailabilityDatabase.tier_of(35))
	_expect(ShopAvailabilityDatabase.tier_of(999) == 0, "unknown id yields 0")

	# --- the gate, tier half ---------------------------------------------------
	_expect(not ShopAvailabilityDatabase.is_stocked(4, 3), "Mage Masher (tier 4) absent at tier 3")
	_expect(ShopAvailabilityDatabase.is_stocked(4, 4), "Mage Masher present at tier 4")
	_expect(ShopAvailabilityDatabase.is_stocked(4, 15), "a tier never un-stocks an item")
	_expect(not ShopAvailabilityDatabase.is_stocked(35, 16),
		"tier 16 — the highest the scripts ever assign — still cannot buy Excalibur")

	# --- the gate, mask half ---------------------------------------------------
	# Guns (Romanda Gun 71) carry mask 0x0011: slots 11 and 15 only. A `1 << slot`
	# reading of the same word would pass slots 0 and 4 instead.
	_expect(ShopAvailabilityDatabase.slot_mask_of(71) == 0x0011,
		"Romanda Gun mask is 0x0011, got 0x%04X" % ShopAvailabilityDatabase.slot_mask_of(71))
	_expect(ShopAvailabilityDatabase.is_stocked(71, 15, 11), "Romanda Gun sold at slot 11")
	_expect(ShopAvailabilityDatabase.is_stocked(71, 15, 15), "Romanda Gun sold at slot 15")
	_expect(not ShopAvailabilityDatabase.is_stocked(71, 15, 0), "Romanda Gun NOT sold at slot 0")
	_expect(not ShopAvailabilityDatabase.is_stocked(71, 15, 4), "Romanda Gun NOT sold at slot 4")
	# Ids >= 0x64 are the Fur Shop / Soldier Office, which FUN_8012502C rejects.
	_expect(not ShopAvailabilityDatabase.is_stocked(1, 15, 0x65), "facility id 0x65 stocks nothing")
	# Slot -1 asks "any shop at all".
	_expect(ShopAvailabilityDatabase.is_stocked(71, 15), "any-shop query finds the gun")

	# --- the timeline ----------------------------------------------------------
	var t1 := ShopAvailabilityDatabase.unlock_for_tier(1)
	_expect(int(t1.get("unlock_scenario_id", -1)) == 12,
		"tier 1 opens at scenario 12, got %s" % [t1.get("unlock_scenario_id")])
	_expect(int(ShopAvailabilityDatabase.unlock_for_tier(15).get("unlock_scenario_id", -1)) == 427,
		"tier 15 opens at scenario 427 (The Mystery of Lucavi)")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(0) == 0, "nothing is stocked before scenario 12")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(11) == 0, "scenario 11 is still tier 0")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(12) == 1, "scenario 12 reaches tier 1")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(28) == 1, "tier holds between assignments")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(29) == 2, "scenario 29 reaches tier 2")
	_expect(ShopAvailabilityDatabase.tier_at_scenario(499) == 16, "the last assignment is tier 16")
	_expect(ShopAvailabilityDatabase.unlock_scenario_of(1) == 12, "Dagger unlocks at scenario 12")
	_expect(ShopAvailabilityDatabase.unlock_scenario_of(35) == -1, "Excalibur has no unlock scenario")

	# --- the sets --------------------------------------------------------------
	_expect(ShopAvailabilityDatabase.items_at_tier(1).size() == 14,
		"tier 1 adds 14 items, got %d" % ShopAvailabilityDatabase.items_at_tier(1).size())
	_expect(ShopAvailabilityDatabase.items_at_tier(15).size() == 1, "tier 15 adds exactly one item")
	_expect(ShopAvailabilityDatabase.items_at_tier(16).is_empty(),
		"tier 16 exists in the scripts but no item carries availability 16")
	_expect(ShopAvailabilityDatabase.all_tiers() == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
		"sixteen tiers, ascending, got %s" % [ShopAvailabilityDatabase.all_tiers()])
	var early := ShopAvailabilityDatabase.stock_for(1)
	var late := ShopAvailabilityDatabase.stock_for(14)
	_expect(early.size() == 14, "tier 1 stocks 14 items across all shops, got %d" % early.size())
	_expect(late.size() > early.size(), "stock only grows: %d -> %d" % [early.size(), late.size()])
	_expect(late.size() == 197, "tiers 1..14 stock 197 items, got %d" % late.size())

	# --- enemy_level, the ROM's own power index --------------------------------
	_expect(ShopAvailabilityDatabase.enemy_level_of(1) == 1, "Dagger rolls onto enemies from level 1")
	_expect(ShopAvailabilityDatabase.enemy_level_of(35) == 96, "Excalibur rolls from level 96")

	if _failed > 0:
		print("[FAIL] ShopAvailabilityDatabaseTest: %d of %d checks failed" % [_failed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] ShopAvailabilityDatabaseTest: %d checks — tier byte, both gate halves, timeline, sets" % _passed)
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
