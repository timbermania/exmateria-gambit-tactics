extends GPUCombatTestBase

## GPU Throw Stone Test
##
## Tests ThrowStone ability (ID 148) - instant-cast ranged ability.
## ThrowStone: MP 0, CT 0 (instant), Range 4.
## Expected: Thrower pelts fleeing Runner with stones.

const ABILITY_THROW_STONE = 148


func get_test_name() -> String:
	return "GPU Throw Stone Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Thrower",
		"pos_x": 0, "pos_z": 0,
		"hp": 100, "max_hp": 100,
		"pa": 10, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Runner",
		"pos_x": 2, "pos_z": 0,
		"hp": 100, "max_hp": 100,
		"pa": 10, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		# Thrower throws stones at enemy
		return [make_ability_gambit(ABILITY_THROW_STONE, GPUConstants.TARGET_NEAREST_ENEMY)]
	else:
		# Runner flees to far corner
		return [make_move_to_gambit(9, 14)]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s throwing stone" % units[unit_idx].name)
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		print("  -> %s running away!" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit by stone for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] Throw Stone combat resolved - Team %d won" % winning_team)
	else:
		print("\n[FAIL] Throw Stone combat ended in a draw")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
