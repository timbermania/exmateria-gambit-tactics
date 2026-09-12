extends GPUCombatTestBase

## GPU Strengthen-Elem Fire Test (issue #117; two-Mage shape under #118)
##
## Witnesses the attacker-side Strengthen-Elem (BoostElem) 1.25x multiplier
## relationally — no hard-coded baseline. Two identical Mages cast Fire on
## isolated targets on the same tick:
##
##   StrengthenMage equips a synthetic Black-Robe-like strengthen_items list
##   (Black Robe id 205 OR-folds Fire/Lightning/Ice into the BoostElem byte
##   at +0x71) and fires at StrengthenTarget. ControlMage has no
##   strengthen_items and fires at ControlTarget. The two targets are
##   defenseless and stat-identical so the ONLY difference in the queued
##   damage is the attacker-side BoostElem branch in
##   [code]apply_damage_to_target[/code].
##
##   PASS predicate: strengthen_delta == (control_delta * 5) / 4
##                   (integer floor — matches the AbPower x 5/4 stage in
##                   [code]FUN_80185FFC[/code] at [code]ram:80185FFC[/code]).
##
## #118 unblocks this shape: pre-fix, two cinematics finishing on the same
## tick raced for the battle-scoped BH_CINEMATIC_CASTER_IDX slot and the
## loser's AoE stamp got wiped. Post-fix, both cinematics run concurrently
## and both targets take their respective hits — so this test doubles as a
## #118 regression witness alongside [code]GPUSimultaneousCinematicTest[/code].
##
## Layout (Manhattan, on the same row pair so both Mages have a unique
## nearest enemy):
##   StrengthenMage   (team 0) at (0, 0)   ControlMage     (team 0) at (0, 2)
##   StrengthenTarget (team 1) at (4, 0)   ControlTarget   (team 1) at (4, 2)

const ABILITY_FIRE = 16
const BLACK_ROBE_ID = 205
const TARGET_START_HP = 500


func get_test_name() -> String:
	return "GPU Strengthen-Elem Fire Test (two-Mage relational, 5/4)"


func get_team0_unit_configs() -> Array:
	var common = {
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 12, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 99, "max_mp": 99,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
	}
	var strengthen = common.duplicate()
	strengthen["name"] = "StrengthenMage"
	strengthen["pos_x"] = 0
	strengthen["pos_z"] = 0
	strengthen["strengthen_items"] = [BLACK_ROBE_ID]
	var control = common.duplicate()
	control["name"] = "ControlMage"
	control["pos_x"] = 0
	control["pos_z"] = 2
	return [strengthen, control]


func get_team1_unit_configs() -> Array:
	var common = {
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
	}
	var strengthen_target = common.duplicate()
	strengthen_target["name"] = "StrengthenTarget"
	strengthen_target["pos_x"] = 4
	strengthen_target["pos_z"] = 0
	var control_target = common.duplicate()
	control_target["name"] = "ControlTarget"
	control_target["pos_x"] = 4
	control_target["pos_z"] = 2
	return [strengthen_target, control_target]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	max_ticks = 1500
	super._ready()


var _strengthen_delta: int = 0
var _control_delta: int = 0
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 4:
		return

	# StrengthenTarget = team1 idx 0 -> overall unit index 2
	# ControlTarget    = team1 idx 1 -> overall unit index 3
	var st_hp := int(states[2].get("hp", TARGET_START_HP))
	var ct_hp := int(states[3].get("hp", TARGET_START_HP))
	if _strengthen_delta == 0 and st_hp < TARGET_START_HP:
		_strengthen_delta = TARGET_START_HP - st_hp
	if _control_delta == 0 and ct_hp < TARGET_START_HP:
		_control_delta = TARGET_START_HP - ct_hp

	if _strengthen_delta > 0 and _control_delta > 0:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var st_hp := int(states[2].get("hp", TARGET_START_HP))
	var ct_hp := int(states[3].get("hp", TARGET_START_HP))
	var mage_mask := int(states[0].get("strengthen_mask", 0))
	if _strengthen_delta == 0:
		_strengthen_delta = TARGET_START_HP - st_hp
	if _control_delta == 0:
		_control_delta = TARGET_START_HP - ct_hp

	var expected_strengthen := (_control_delta * 5) / 4

	print("\n=== STRENGTHEN-ELEM FIRE TEST RESULTS ===")
	print("  ControlTarget    HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, ct_hp, -_control_delta])
	print("  StrengthenTarget HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, st_hp, -_strengthen_delta])
	print("  StrengthenMage.strengthen_mask = 0x%02X (Fire bit %s)" % [
		mage_mask, "SET" if (mage_mask & (1 << 1)) != 0 else "missing"])
	print("  Expected strengthen_delta = (control_delta * 5) / 4 = %d" % expected_strengthen)

	var preseed_ok := (mage_mask & (1 << 1)) != 0
	var control_hit := _control_delta > 0
	var strengthen_hit := _strengthen_delta > 0
	var ratio_ok := control_hit and _strengthen_delta == expected_strengthen

	if preseed_ok and control_hit and strengthen_hit and ratio_ok:
		print("\n[PASS] Strengthen-Elem scaled Fire %d -> %d (5/4 of control)" % [
			_control_delta, _strengthen_delta])
	else:
		var why: Array = []
		if not preseed_ok:    why.append("strengthen_mask encode failed (got 0x%02X, expected Fire bit set)" % mage_mask)
		if not control_hit:   why.append("ControlTarget never hit within %d ticks" % max_ticks)
		if not strengthen_hit: why.append("StrengthenTarget never hit within %d ticks" % max_ticks)
		if control_hit and strengthen_hit and not ratio_ok:
			why.append("ratio off (got %d, expected %d = control %d * 5/4)" % [
				_strengthen_delta, expected_strengthen, _control_delta])
		print("\n[FAIL] %s" % ", ".join(why))
	print("==========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
