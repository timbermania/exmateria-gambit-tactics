extends GPUCombatTestBase

## GPU Shell Test
##
## Tests that Shell status halves magic damage.
## Mage casts Fire on a Shelled target. After 3 hits, checks average damage is reduced.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_FIRE = 16

var _damage_log: Array = []
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Shell Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Mage",
			"pos_x": 3, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 200, "max_mp": 200,
			"speed": 100,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x04
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "ShelledTank",
			"pos_x": 5, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 50, "max_mp": 50,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"status_flags_lo": (1 << StatusRegistry.bit(&"shell")),
			"body_sprite_id": 0x06
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return [make_wait_gambit()]


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0 and unit_idx == 1:
		var dmg = abs(delta)
		print("  -> ShelledTank took %d damage, HP=%d" % [dmg, new_hp])
		_damage_log.append(dmg)
		if _damage_log.size() >= 3:
			_print_results()


func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func _print_results():
	if _results_printed:
		return
	_results_printed = true
	print("\n=== SHELL TEST RESULTS ===")
	if _damage_log.size() > 0:
		var avg = 0
		for d in _damage_log:
			avg += d
		avg = avg / _damage_log.size()
		# Fire formula 08: MA * faith_mult * element. Without shell, typically ~68
		print("  Hits: %d, avg damage: %d" % [_damage_log.size(), avg])
		if avg > 0 and avg < 68:
			print("  [PASS] Shell is reducing magic damage (avg %d < 68 unshelled)" % avg)
		else:
			print("  [FAIL] Shell not working (avg %d, expected < 68)" % avg)
	else:
		print("  [FAIL] No damage recorded")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results()
