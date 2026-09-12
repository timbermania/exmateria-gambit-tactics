extends GPUCombatTestBase

## GPU Protect Test
##
## Tests that Protect status halves physical damage.
## Fighter attacks a Protected target. After 3 hits, checks average damage < 50.
## Unprotected PA(10)*WP(5) = 50. With Protect, expected ~33.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


var _damage_log: Array = []
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Protect Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Fighter",
			"pos_x": 3, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "ProtectedTank",
			"pos_x": 4, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"status_flags_lo": (1 << StatusRegistry.bit(&"protect")),
			"body_sprite_id": 0x05
		},
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0 and unit_idx == 1:
		var dmg = abs(delta)
		print("  -> ProtectedTank took %d damage, HP=%d" % [dmg, new_hp])
		_damage_log.append(dmg)
		if _damage_log.size() >= 3:
			_print_results()


func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func _print_results():
	if _results_printed:
		return
	_results_printed = true
	print("\n=== PROTECT TEST RESULTS ===")
	if _damage_log.size() > 0:
		var avg = 0
		for d in _damage_log:
			avg += d
		avg = avg / _damage_log.size()
		var unprotected = 50  # PA(10) * WP(5)
		print("  Hits: %d, avg damage: %d (unprotected would be %d)" % [_damage_log.size(), avg, unprotected])
		if avg < unprotected:
			print("  [PASS] Protect is reducing physical damage (avg %d < %d)" % [avg, unprotected])
		else:
			print("  [FAIL] Protect not working (avg %d >= %d)" % [avg, unprotected])
	else:
		print("  [FAIL] No damage recorded")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results()
