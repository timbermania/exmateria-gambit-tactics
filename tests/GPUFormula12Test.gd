extends GPUCombatTestBase

## GPU Formula 12 Test -- Healing: MA * Y * CasterFaith * TargetFaith / 10000
##
## Cure (ID 1): formula 12, Y=14, range 4, ct 4, healing, effect_area 1
## Cure is AOE — the GPU's smart targeting only heals ALLIES of the caster.
## So the healer must target a damaged ally, not an enemy.
##
## Caster: MA=10, Faith=70. Target ally: Faith=70, starts damaged (500/999)
## Expected heal: 10 * 14 * 70 * 70 / 10000 = 68

const ABILITY_ID = 1  # Cure
const EXPECTED = 68

var _done: bool = false


func get_test_name() -> String:
	return "GPU Formula 12 Test (Faith Healing)"


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
			"name": "Wounded",
			"pos_x": 1, "pos_z": 0,
			"hp": 500, "max_hp": 999,  # Damaged so healing is observable
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
		"pos_x": 8, "pos_z": 0,
		"hp": 999, "max_hp": 999,
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x06,
		"gambits": [make_move_to_gambit(8, 0)],
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		# Healer casts Cure on lowest HP ally (the wounded unit)
		return [make_spell_gambit(ABILITY_ID, GPUConstants.TARGET_LOWEST_HP_ALLY)]
	elif unit_idx == 1:
		# Wounded just stays put
		return [make_move_to_gambit(1, 0)]
	else:
		# Dummy stays put
		return [make_move_to_gambit(8, 0)]


func _ready():
	max_ticks = 2000
	super._ready()
	print("\n  Expected heal: MA(10) * Y(14) * Faith(70) * Faith(70) / 10000 = %d" % EXPECTED)


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if _done:
		return
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if unit_idx == 1 and delta > 0:
		var actual = delta
		var status = "PASS" if actual == EXPECTED else "FAIL"
		_done = true
		print("\n[%s] Formula 12 (Faith Healing): expected=%d actual=%d  (HP: %d->%d)" % [
			status, EXPECTED, actual, old_hp, new_hp])
		_rlog.log_entry("TEST_%s" % status, {"expected": EXPECTED, "actual": actual})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()
	elif delta < 0:
		print("  [DAMAGE] %s hit for %d  HP: %d -> %d" % [unit_name, abs(delta), old_hp, new_hp])
	elif delta > 0:
		print("  [HEAL] %s healed for %d  HP: %d -> %d" % [unit_name, delta, old_hp, new_hp])


func on_victory(winning_team: int):
	if not _done:
		print("\n[FAIL] Formula 12: no healing observed before victory")
		_rlog.log_entry("TEST_FAIL", {"reason": "no_heal_observed"})
		_rlog.output()
