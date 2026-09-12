extends GPUCombatTestBase

## GPU Haste/Slow Movement Test
##
## Tests that Haste doubles movement speed and Slow halves it.
## Three units at same X, moving toward enemies:
## - Hasted unit (STATUS_HASTE bit 19)
## - Normal unit
## - Slowed unit (STATUS_SLOW bit 20)
## Expected: Hasted arrives first, normal second, slowed last.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


func get_test_name() -> String:
	return "GPU Haste/Slow Movement Test"


func get_team0_unit_configs() -> Array:
	# All 3 attackers on the same row (z=2) to eliminate terrain variance.
	# Stagger x so they don't collide; each faces a separate immobile enemy.
	return [
		{
			"name": "HasteUnit",
			"pos_x": 0, "pos_z": 2,
			"hp": 500, "max_hp": 500,
			"pa": 8, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"status_flags_lo": (1 << StatusRegistry.bit(&"haste")),
			"body_sprite_id": 0x02
		},
		{
			"name": "NormalUnit",
			"pos_x": 0, "pos_z": 4,
			"hp": 500, "max_hp": 500,
			"pa": 8, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x03
		},
		{
			"name": "SlowUnit",
			"pos_x": 0, "pos_z": 6,
			"hp": 500, "max_hp": 500,
			"pa": 8, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"status_flags_lo": (1 << StatusRegistry.bit(&"slow")),
			"body_sprite_id": 0x04
		}
	]


func get_team1_unit_configs() -> Array:
	# Immobile enemies on the same rows, far away. move=0 so they stay put.
	return [
		{
			"name": "EnemyA",
			"pos_x": 8, "pos_z": 2,
			"hp": 9999, "max_hp": 9999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05
		},
		{
			"name": "EnemyB",
			"pos_x": 8, "pos_z": 4,
			"hp": 9999, "max_hp": 9999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		},
		{
			"name": "EnemyC",
			"pos_x": 8, "pos_z": 6,
			"hp": 9999, "max_hp": 9999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x07
		}
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


var _first_attack_tick: Dictionary = {}  # unit_idx -> tick of first attack
var _results_printed: bool = false


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if unit_idx < 3 and old_state == GPUConstants.LOGICAL_ACTIVITY_WALKING and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		if not _first_attack_tick.has(unit_idx):
			_first_attack_tick[unit_idx] = current_tick
			print("  -> %s first attack at tick %d" % [units[unit_idx].name, current_tick])
	# Check if all three have attacked
	if _first_attack_tick.size() == 3 and not _results_printed:
		_print_results()


func _print_results():
	if _results_printed:
		return
	_results_printed = true
	var haste_tick = _first_attack_tick.get(0, -1)
	var normal_tick = _first_attack_tick.get(1, -1)
	var slow_tick = _first_attack_tick.get(2, -1)
	print("\n=== HASTE/SLOW TEST RESULTS ===")
	print("  Haste first attack: tick %d" % haste_tick)
	print("  Normal first attack: tick %d" % normal_tick)
	print("  Slow first attack: tick %d" % slow_tick)
	var all_pass = true
	if haste_tick > 0 and normal_tick > 0 and haste_tick < normal_tick:
		print("  [PASS] Hasted unit attacked before normal")
	else:
		print("  [FAIL] Hasted unit did not attack before normal")
		all_pass = false
	if slow_tick > 0 and normal_tick > 0 and slow_tick > normal_tick:
		print("  [PASS] Slowed unit attacked after normal")
	else:
		print("  [FAIL] Slowed unit did not attack after normal")
		all_pass = false
	if all_pass:
		print("[PASS] Haste/Slow test passed")
	else:
		print("[FAIL] Haste/Slow test failed")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s took %d damage, HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results()
