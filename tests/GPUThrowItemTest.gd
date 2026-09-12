extends GPUCombatTestBase

## GPU Throw Item Test
##
## Tests item throwing - Potion thrown at distant ally.
## Item flies in arc, lands, spawns E260 effect, heals target.

const ABILITY_POTION = 368

func get_test_name() -> String:
	return "GPU Throw Item Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Chemist",
			"pos_x": 0, "pos_z": 0,
			"hp": 100, "max_hp": 100,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x03
		},
		{
			"name": "Wounded",
			"pos_x": 3, "pos_z": 3,  # Distant ally
			"hp": 20, "max_hp": 100,  # Damaged
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05
		}
	]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Enemy",
		"pos_x": 8, "pos_z": 0,
		"hp": 100, "max_hp": 100,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x07
	}]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		if unit_idx == 0:
			# Chemist throws potion at nearest wounded ally
			return [make_item_gambit(ABILITY_POTION, GPUConstants.TARGET_LOWEST_HP_ALLY)]
		else:
			# Wounded just waits
			return []
	else:
		# Enemy does nothing
		return []


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s preparing to throw item" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta > 0:
		print("  -> %s healed for %d! HP=%d" % [units[unit_idx].name, delta, new_hp])


func on_victory(_winning_team: int):
	pass


func _process(delta):
	super._process(delta)

	# End test after target is fully healed or timeout
	if current_tick >= 200 and combat_active:
		var states = gpu_state_reader.get_all_unit_states()
		if states.size() > 1 and states[1]["hp"] >= 100:
			print("\n[PASS] Throw item test passed - ally fully healed")
			_rlog.log_entry("TEST_PASS", {"reason": "ally_fully_healed"})
			_rlog.output()
			victory_achieved = true
			combat_active = false
			get_tree().quit()
		elif current_tick >= 800:
			print("\n[TIMEOUT] Test ended at tick %d" % current_tick)
			_rlog.log_entry("TEST_TIMEOUT", {"tick": current_tick})
			_rlog.output()
			combat_active = false
			get_tree().quit()
