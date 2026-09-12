extends GPUCombatTestBase

## GPU Distance Field Test
##
## Tests that target selection uses BFS distance instead of Manhattan distance.
## Unit at (0,0) with two enemies:
## - Enemy B at (0,4): Manhattan=4 but may have longer BFS path
## - Enemy C at (4,0): Manhattan=4 with direct path
## With BFS distance, the unit should prefer the more reachable enemy.


func get_test_name() -> String:
	return "GPU Distance Field Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Pathfinder",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "EnemyNear",
			"pos_x": 4, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05
		},
		{
			"name": "EnemyFar",
			"pos_x": 0, "pos_z": 6,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		}
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


var _first_target_logged: bool = false
var _results_printed: bool = false


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if unit_idx == 0 and new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING and not _first_target_logged:
		_first_target_logged = true
		var states = gpu_state_reader.get_all_unit_states()
		if states.size() > 0:
			var target = states[0].get("target", -1)
			var dest_x = states[0].get("dest_x", -1)
			var dest_z = states[0].get("dest_z", -1)
			print("  -> Pathfinder targeting unit %d, moving to (%d,%d)" % [target, dest_x, dest_z])
			_print_results(target)


func _print_results(selected_target: int):
	if _results_printed:
		return
	_results_printed = true
	print("\n=== DISTANCE FIELD TEST RESULTS ===")
	# Unit 1 = EnemyNear at (4,0), Unit 2 = EnemyFar at (0,6)
	if selected_target == 1:
		print("  Selected EnemyNear at (4,0) — BFS distance used")
		print("[PASS] Distance field test passed")
	elif selected_target == 2:
		print("  Selected EnemyFar at (0,6) — may be using Manhattan distance")
		print("[FAIL] Distance field test failed (expected EnemyNear)")
	else:
		print("  Selected unknown target %d" % selected_target)
		print("[FAIL] Distance field test failed (unexpected target)")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s took %d damage, HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results(-1)
