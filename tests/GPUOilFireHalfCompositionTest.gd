extends GPUCombatTestBase

## GPU Oil × Fire × Half Composition Test (issue #112)
##
## Witnesses the ordering decision in PRD #112's status overlay: ROM applies the
## Oil ×2 BEFORE the equipment-defense matrix, so an Oiled target equipped with
## Fire-Half nets ×2 × ½ = [b]×1[/b]. Same final damage as a plain control.
## ROM authority: BATTLE.BIN [code]FUN_80186FF8[/code] at [code]0x80187000[/code]
## (Oil branch) and [code]FUN_80184E98[/code] at [code]0x80184E98[/code] (Half
## branch) called sequentially.
##
## Layout (Manhattan):
##   Mage       (team 0, caster, Fire gambit)              at (0, 0)
##   OilHalf    (team 1, Oil + Fire-Half mask)              at (4, 0)
##   Control    (team 1, identical sans Oil/Half)           at (4, 1)
##
## PASS: OilHalf HP delta == Control HP delta (and both > 0).
## FAIL: ratio differs (e.g. ×2 if Oil fired without Half, or ½ if Half fired
## without Oil).

const ABILITY_FIRE = 16
const STATUS_OIL_BIT = 30
const ELEMENT_FIRE = 1
const FIRE_BIT_MASK = 1 << ELEMENT_FIRE
const TARGET_START_HP = 500


func get_test_name() -> String:
	return "GPU Oil×Fire×Half Composition Test (Oil + Fire-Half nets ×1)"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Mage",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 12, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 99, "max_mp": 99,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
	}]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "OilHalfKnight",
			"pos_x": 4, "pos_z": 0,
			"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			"status_flags_lo": 1 << STATUS_OIL_BIT,
			"element_half_mask": FIRE_BIT_MASK,
		},
		{
			"name": "ControlKnight",
			"pos_x": 4, "pos_z": 1,
			"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	max_ticks = 1500
	super._ready()


var _oilhalf_delta: int = 0
var _control_delta: int = 0
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 3:
		return

	var oilhalf_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", TARGET_START_HP))

	# Per-target latch + AND-gate completion: AOE Phase 1 lands on the two
	# targets across separate snapshots, so a single-shot "either changed"
	# capture races whichever HP updates first.
	if _oilhalf_delta == 0 and oilhalf_hp < TARGET_START_HP:
		_oilhalf_delta = TARGET_START_HP - oilhalf_hp
	if _control_delta == 0 and control_hp < TARGET_START_HP:
		_control_delta = TARGET_START_HP - control_hp
	if _oilhalf_delta > 0 and _control_delta > 0:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var oilhalf_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", TARGET_START_HP))
	var oilhalf_flags := int(states[1].get("status_flags_lo", 0))
	var oilhalf_half_mask := int(states[1].get("element_half_mask", 0))
	if _oilhalf_delta == 0: _oilhalf_delta = TARGET_START_HP - oilhalf_hp
	if _control_delta == 0: _control_delta = TARGET_START_HP - control_hp

	print("\n=== OIL × FIRE × HALF COMPOSITION TEST RESULTS ===")
	print("  OilHalfKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, oilhalf_hp, -_oilhalf_delta])
	print("  ControlKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, control_hp, -_control_delta])
	print("  OilHalfKnight status_flags_lo = 0x%08X (Oil bit %s)" % [
		oilhalf_flags,
		"SET" if (oilhalf_flags & (1 << STATUS_OIL_BIT)) != 0 else "missing"])
	print("  OilHalfKnight element_half_mask = 0x%02X (Fire bit %s)" % [
		oilhalf_half_mask,
		"SET" if (oilhalf_half_mask & FIRE_BIT_MASK) != 0 else "missing"])

	var preseed_oil := (oilhalf_flags & (1 << STATUS_OIL_BIT)) != 0
	var preseed_half := (oilhalf_half_mask & FIRE_BIT_MASK) != 0
	var both_hit := _oilhalf_delta > 0 and _control_delta > 0
	var ratio_ok := both_hit and _oilhalf_delta == _control_delta

	if preseed_oil and preseed_half and both_hit and ratio_ok:
		print("\n[PASS] Oil×Fire×Half composed to ×1 (oilhalf %d == control %d)" % [
			_oilhalf_delta, _control_delta])
	else:
		var why: Array = []
		if not preseed_oil:  why.append("status_flags_lo missing Oil bit")
		if not preseed_half: why.append("element_half_mask missing Fire bit")
		if not both_hit:     why.append("at least one target wasn't hit (oilhalf=%d control=%d)" % [_oilhalf_delta, _control_delta])
		if both_hit and not ratio_ok:
			why.append("damage mismatch (oilhalf=%d, control=%d, expected equal)" % [
				_oilhalf_delta, _control_delta])
		print("\n[FAIL] %s" % ", ".join(why))
	print("===================================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
