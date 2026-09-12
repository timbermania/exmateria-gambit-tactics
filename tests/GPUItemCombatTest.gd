extends GPUCombatTestBase

## GPU Item Combat Test
##
## Tests item usage with Potion (ability ID 368).
## Units start damaged and use Potion on self.
## Expected: HP increases, units heal themselves.

const ABILITY_POTION = 368


func _ready():
	# Enable debug logging for item animation debugging
	DebugConfig.iteration_debug_enabled = true
	super._ready()


func get_test_name() -> String:
	return "GPU Item Combat Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Healer",
		"pos_x": 0, "pos_z": 0,
		"hp": 20, "max_hp": 100,  # Damaged
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "EnemyHealer",
		"pos_x": 3, "pos_z": 0,
		"hp": 20, "max_hp": 100,  # Damaged
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x07
	}]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_item_gambit(ABILITY_POTION, GPUConstants.TARGET_SELF)]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s using Potion" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE:
		print("  -> %s finished using item" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta > 0:
		print("  -> %s healed for %d! HP=%d" % [units[unit_idx].name, delta, new_hp])


func on_victory(_winning_team: int):
	pass  # Self-healing test doesn't end in victory


func _process(delta):
	super._process(delta)

	# End test after 300 ticks if healing occurred
	if current_tick >= 300 and gpu_state_reader and combat_active:
		var states = gpu_state_reader.get_all_unit_states()
		var any_healed = false
		for s in states:
			if s["hp"] > 20:
				any_healed = true

		if any_healed:
			print("\n[PASS] Item test passed - units healed themselves")
			_rlog.log_entry("TEST_PASS", {"reason": "units_healed"})
			_rlog.output()
			victory_achieved = true
			combat_active = false
			get_tree().quit()
		else:
			print("\n[FAIL] No healing occurred after 300 ticks")
			_rlog.log_entry("TEST_FAIL", {"reason": "no_healing"})
			_rlog.output()
			combat_active = false
			get_tree().quit()
