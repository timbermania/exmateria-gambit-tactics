extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: calculate_spell_damage's formula 8/12 (Faith-scaled Dmg/Heal) divisor in combat_combat.glslinc - `/ 10000` -> `/ 20000` (halves Cure's heal amount 68 -> 34) - all 3 in-radius allies heal for 34 instead of 68, so each `healed for 34 (expected 68)` gate trips -> `[FAIL] AOE heal test failed`; GREEN unbroken on the reverted tree

## GPU AOE Heal Test
##
## Tests that AOE healing spells correctly heal multiple allies.
## Cure (ID 1): formula 12, Y=14, range 4, ct 4, effect_area 1 (AOE radius 1)
##
## Setup:
## - Team 0: Healer at (0,0), Wounded A at (3,0), Wounded B at (3,1), Wounded C at (4,0)
## - Team 1: Dummy at (8,8) (immobile, keeps combat alive)
##
## Healer casts Cure targeting lowest HP ally. AOE centers on that unit.
## Wounded B and C are within Manhattan distance 1 of Wounded A.
## GPU smart targeting: healing only hits allies (caster's team).
##
## Expected: All 3 wounded allies heal for 68 each (MA=10 * Y=14 * 70 * 70 / 10000).
## PASS: All 3 wounded units receive healing.
## FAIL: Fewer than 3 healed, or timeout.

const ABILITY_ID = 1  # Cure
const EXPECTED_HEAL = 68

var _healed_units: Dictionary = {}  # unit_idx -> heal amount
var _done: bool = false


func get_test_name() -> String:
	return "GPU AOE Heal Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Healer",
			"pos_x": 0, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 10, "ma": 10, "wp": 8,
			"brave": 50, "faith": 70,
			"mp": 200, "max_mp": 200,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x04,
		},
		{
			"name": "WoundedA",
			"pos_x": 3, "pos_z": 0,
			"hp": 500, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
		{
			"name": "WoundedB",
			"pos_x": 3, "pos_z": 1,
			"hp": 500, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
		{
			"name": "WoundedC",
			"pos_x": 4, "pos_z": 0,
			"hp": 500, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Dummy",
		"pos_x": 8, "pos_z": 8,
		"hp": 999, "max_hp": 999,
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x06,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_ID, GPUConstants.TARGET_LOWEST_HP_ALLY)]
	# Everyone else stays put
	return []


func _ready():
	max_ticks = 2000
	super._ready()
	print("\n  AOE Heal: Cure (area=1) centered on wounded cluster at (3,0)/(3,1)/(4,0)")
	print("  Expected: all 3 wounded heal for %d each" % EXPECTED_HEAL)


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if _done:
		return
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if delta > 0:
		print("  [HEAL] %s healed for %d  HP: %d -> %d" % [unit_name, delta, old_hp, new_hp])
		# Track heals on wounded units (indices 1, 2, 3)
		if unit_idx >= 1 and unit_idx <= 3:
			_healed_units[unit_idx] = delta
		# Check if all 3 wounded have been healed
		if _healed_units.size() >= 3:
			_print_results()


func _print_results():
	if _done:
		return
	_done = true
	print("\n=== AOE HEAL TEST RESULTS ===")
	var all_pass = true
	for idx in [1, 2, 3]:
		var unit_name = units[idx].name if idx < units.size() else "Unit%d" % idx
		if _healed_units.has(idx):
			var heal = _healed_units[idx]
			if heal == EXPECTED_HEAL:
				print("  [PASS] %s healed for %d (expected %d)" % [unit_name, heal, EXPECTED_HEAL])
			else:
				print("  [FAIL] %s healed for %d (expected %d)" % [unit_name, heal, EXPECTED_HEAL])
				all_pass = false
		else:
			print("  [FAIL] %s was not healed" % unit_name)
			all_pass = false
	if all_pass:
		print("[PASS] AOE heal test passed - all 3 allies healed correctly")
	else:
		print("[FAIL] AOE heal test failed")
	print("=== END RESULTS ===")
	_rlog.log_entry("TEST_%s" % ("PASS" if all_pass else "FAIL"), {
		"healed_count": _healed_units.size(),
		"heals": str(_healed_units),
	})
	_rlog.output()
	victory_achieved = true
	combat_active = false
	get_tree().quit()


func on_victory(winning_team: int):
	if not _done:
		print("\n[FAIL] AOE heal: fewer than 3 allies healed before victory (got %d)" % _healed_units.size())
		_rlog.log_entry("TEST_FAIL", {"reason": "insufficient_heals", "count": _healed_units.size()})
		_rlog.output()
