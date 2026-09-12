extends GPUCombatTestBase

## GPU Weapon Fire Weak Test (issue #116)
##
## Witnesses the basic-attack weapon-element weak-scale. Same shape as
## [code]GPUWeaponFireHalfTest[/code] but the half mask is replaced with the
## weak mask. Expected ratio: weak_damage = control_damage * 2.
##
## Layout (Manhattan):
##   Fighter_Weak    (team 0) at (0, 0)  -- Flame Rod
##   Fighter_Control (team 0) at (0, 5)  -- Flame Rod
##   Weak_Target     (team 1) at (1, 0)  -- element_weak_mask = Fire
##   Control_Target  (team 1) at (1, 5)  -- no element defense
##
## PASS: weak_delta == control_delta * 2 (both > 0).
## FAIL: ratio differs, or a target wasn't hit.

const FLAME_ROD_ID = 53
const FIRE_BIT_MASK = 1 << 1
const TARGET_START_HP = 500


func get_test_name() -> String:
	return "GPU Weapon Fire Weak Test (Flame Rod ratio 2x vs control)"


func _fighter_cfg(name: String, pos_x: int, pos_z: int) -> Dictionary:
	return {
		"name": name,
		"pos_x": pos_x, "pos_z": pos_z,
		"hp": 500, "max_hp": 500,
		"pa": 12, "ma": 5, "wp": 3,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
		"weapon_id": FLAME_ROD_ID,
	}


func _target_cfg(name: String, pos_x: int, pos_z: int, weak_mask: int) -> Dictionary:
	return {
		"name": name,
		"pos_x": pos_x, "pos_z": pos_z,
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"element_weak_mask": weak_mask,
	}


func get_team0_unit_configs() -> Array:
	return [
		_fighter_cfg("FighterWeak",    0, 0),
		_fighter_cfg("FighterControl", 0, 5),
	]


func get_team1_unit_configs() -> Array:
	return [
		_target_cfg("WeakTarget",    1, 0, FIRE_BIT_MASK),
		_target_cfg("ControlTarget", 1, 5, 0),
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_attack_gambit()]
	return []


func _ready() -> void:
	max_ticks = 800
	super._ready()


var _hits_seen: bool = false
var _weak_delta: int = 0
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

	var weak_hp := int(states[2].get("hp", TARGET_START_HP))
	var control_hp := int(states[3].get("hp", TARGET_START_HP))

	if not _hits_seen and (weak_hp < TARGET_START_HP or control_hp < TARGET_START_HP):
		_hits_seen = true
		_weak_delta = TARGET_START_HP - weak_hp
		_control_delta = TARGET_START_HP - control_hp
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var weak_hp := int(states[2].get("hp", TARGET_START_HP))
	var control_hp := int(states[3].get("hp", TARGET_START_HP))
	var weak_mask := int(states[2].get("element_weak_mask", 0))
	if _weak_delta == 0:    _weak_delta = TARGET_START_HP - weak_hp
	if _control_delta == 0: _control_delta = TARGET_START_HP - control_hp

	print("\n=== WEAPON FIRE WEAK TEST RESULTS ===")
	print("  WeakTarget    HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, weak_hp, -_weak_delta])
	print("  ControlTarget HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, control_hp, -_control_delta])
	print("  WeakTarget element_weak_mask = 0x%02X (Fire bit %s)" % [
		weak_mask,
		"SET" if (weak_mask & FIRE_BIT_MASK) != 0 else "missing"])

	var preseed_ok := (weak_mask & FIRE_BIT_MASK) != 0
	var both_hit := _weak_delta > 0 and _control_delta > 0
	var ratio_ok := both_hit and _weak_delta == _control_delta * 2

	if preseed_ok and both_hit and ratio_ok:
		print("\n[PASS] Weak doubled Flame Rod damage (%d vs control %d, ratio 2.0)" % [
			_weak_delta, _control_delta])
	else:
		var why: Array = []
		if not preseed_ok: why.append("weak mask missing Fire bit")
		if not both_hit:   why.append("at least one target wasn't hit (weak=%d control=%d)" % [_weak_delta, _control_delta])
		if both_hit and not ratio_ok:
			why.append("ratio != 2.0 (weak=%d, control=%d, expected weak=%d)" % [
				_weak_delta, _control_delta, _control_delta * 2])
		print("\n[FAIL] %s" % ", ".join(why))
	print("======================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
