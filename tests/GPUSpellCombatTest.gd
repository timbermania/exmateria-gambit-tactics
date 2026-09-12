extends GPUCombatTestBase

## GPU Spell Combat Test
##
## Tests spell casting with Fire (ID 16).
## Fire: MP 6, CT 4 (40 ticks), Range 4, Magic damage.
## Expected: Units charge, then cast Fire dealing magic damage.

const ABILITY_FIRE = 16


func get_test_name() -> String:
	return "GPU Spell Combat Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Mage",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 10, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x04
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "EnemyMage",
		"pos_x": 3, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 10, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x06
	}]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s charging Fire spell" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE:
		print("  -> %s cast Fire!" % units[unit_idx].name)
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
		print("  -> %s moving to get in range" % units[unit_idx].name)
	# Issue #118 regression witness: after cinematic teardown the caster
	# returns to IDLE; U_PAUSED is a ref-count and must land at exactly 0 on
	# both mages between rounds. A leak would carry > 0 across cycles and
	# silently stall future combat (the "5+ wallclock minutes" handoff smell).
	if new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and gpu_state_reader:
		var states = gpu_state_reader.get_all_unit_states()
		if states.size() >= 2:
			var p0 := int(states[0].get("paused", -1))
			var p1 := int(states[1].get("paused", -1))
			if p0 != 0 or p1 != 0:
				print("\n[FAIL] #118 ref-count leak: paused(0,1)=(%d,%d) at IDLE return tick %d unit_idx=%d" % [
					p0, p1, current_tick, unit_idx])


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return
	# End test when both mages are out of MP (can't cast Fire which costs 6 MP)
	var states = gpu_state_reader.get_all_unit_states()
	if states.size() >= 2:
		var mp0 = states[0].get("mp", 99)
		var mp1 = states[1].get("mp", 99)
		var state0 = states[0].get("state", 0)
		var state1 = states[1].get("state", 0)
		# Wait until both are IDLE and out of MP
		if mp0 < 6 and mp1 < 6 and state0 == GPUConstants.LOGICAL_ACTIVITY_IDLE and state1 == GPUConstants.LOGICAL_ACTIVITY_IDLE:
			print("\n[PASS] Spell combat test complete - both mages out of MP (Mage=%d, EnemyMage=%d)" % [mp0, mp1])
			_rlog.log_entry("TEST_PASS", {"reason": "both_out_of_mp", "mp0": mp0, "mp1": mp1})
			_rlog.output()
			victory_achieved = true
			combat_active = false
			get_tree().quit()


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit by Fire for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] Spell combat resolved - Team %d won" % winning_team)
	else:
		print("\n[PASS] Spell combat resolved - draw (both mages eliminated)")
