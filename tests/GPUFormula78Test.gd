extends GPUCombatTestBase

## GPU Formula 78 Test -- MA * Y (no faith scaling)
##
## IceBracelet (ID 248): formula 78, Y=12, range 2, ct 0
## Caster: MA=10 → expected damage = 10 * 12 = 120

const ABILITY_ID = 248  # IceBracelet
const EXPECTED = 120

var _done: bool = false


func get_test_name() -> String:
	return "GPU Formula 78 Test (Monster MA*Y)"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Caster",
		"pos_x": 0, "pos_z": 0,
		"hp": 999, "max_hp": 999,
		"pa": 10, "ma": 10, "wp": 8,
		"brave": 50, "faith": 70,
		"mp": 200, "max_mp": 200,
		"speed": 100, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19, "body_sprite_id": 0x02,
		"gambits": [make_ability_gambit(ABILITY_ID)],
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 2, "pos_z": 0,  # Range 2 -- must be within reach
		"hp": 999, "max_hp": 999,
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 0, "max_mp": 0,
		"speed": 10, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05,
		"gambits": [make_move_to_gambit(2, 0)],
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	var all_configs = get_team0_unit_configs() + get_team1_unit_configs()
	if unit_idx < all_configs.size():
		return all_configs[unit_idx].get("gambits", [make_attack_gambit()])
	return [make_attack_gambit()]


func _ready():
	max_ticks = 2000
	super._ready()
	print("\n  Expected: MA(10) * Y(12) = %d" % EXPECTED)


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if _done:
		return
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if unit_idx == 1 and delta < 0:
		var actual = abs(delta)
		var status = "PASS" if actual == EXPECTED else "FAIL"
		_done = true
		print("\n[%s] Formula 78 (Monster MA*Y): expected=%d actual=%d  (HP: %d->%d)" % [
			status, EXPECTED, actual, old_hp, new_hp])
		_rlog.log_entry("TEST_%s" % status, {"expected": EXPECTED, "actual": actual})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()
	elif delta < 0:
		print("  [DAMAGE] %s hit for %d  HP: %d -> %d" % [unit_name, abs(delta), old_hp, new_hp])


func on_victory(winning_team: int):
	if not _done:
		print("\n[FAIL] Formula 78: no damage observed before victory")
		_rlog.log_entry("TEST_FAIL", {"reason": "no_damage_observed"})
		_rlog.output()
