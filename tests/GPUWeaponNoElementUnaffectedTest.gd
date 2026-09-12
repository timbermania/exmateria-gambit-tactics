extends GPUCombatTestBase

## GPU Weapon No-Element Unaffected Test (issue #116)
##
## Witnesses [code]element_id == 0[/code] as a clean pass-through: a non-
## elemental weapon (Broad Sword, id 19, no [code]weapon.elements[/code])
## attacking a Fire-Absorb target deals normal damage -- the target does NOT
## heal. Locks in the [code]apply_weapon_element_defense[/code] short-circuit
## when the attacker has no weapon_element to project. Companion to
## [code]GPUWeaponFireAbsorbTest[/code]: same target, same defense, swap the
## weapon, and the absorb does not fire.
##
## Layout (Manhattan):
##   Fighter      (team 0, Broad Sword, basic attack) at (0, 0)
##   FireAbsorb   (team 1, element_absorb_mask = Fire) at (1, 0)
##
## PASS: target HP DROPS below start (damage lands normally; no absorb).
## FAIL: HP rises (would mean the absorb fired against a non-elemental weapon)
## or stays flat (no attack landed at all).

const BROAD_SWORD_ID = 19
const FIRE_BIT_MASK = 1 << 1
const TARGET_START_HP = 200


func get_test_name() -> String:
	return "GPU Weapon No-Element Unaffected Test (Broad Sword on Fire-Absorb)"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "BroadSwordFighter",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 12, "ma": 5, "wp": 4,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
		"weapon_id": BROAD_SWORD_ID,
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "FireAbsorbTarget",
		"pos_x": 1, "pos_z": 0,
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"element_absorb_mask": FIRE_BIT_MASK,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_attack_gambit()]
	return []


func _ready() -> void:
	max_ticks = 800
	super._ready()


var _hit_witnessed_tick: int = -1
var _hp_delta: int = 0
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	var hp_now := int(states[1].get("hp", TARGET_START_HP))
	if _hit_witnessed_tick < 0 and hp_now != TARGET_START_HP:
		_hit_witnessed_tick = current_tick
		_hp_delta = hp_now - TARGET_START_HP
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var hp_now := int(states[1].get("hp", TARGET_START_HP))
	var absorb_mask := int(states[1].get("element_absorb_mask", 0))
	var attacker_w_element := int(states[0].get("weapon_element", -1))

	print("\n=== WEAPON NO-ELEMENT UNAFFECTED TEST RESULTS ===")
	print("  Target HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, hp_now, hp_now - TARGET_START_HP])
	print("  Attacker weapon_element = %d (0 expected for Broad Sword)" % attacker_w_element)
	print("  Target element_absorb_mask = 0x%02X (Fire bit %s -- preseeded)" % [
		absorb_mask,
		"SET" if (absorb_mask & FIRE_BIT_MASK) != 0 else "missing"])

	var weapon_no_element := attacker_w_element == 0
	var preseed_ok := (absorb_mask & FIRE_BIT_MASK) != 0
	var hp_dropped := _hit_witnessed_tick >= 0 and hp_now < TARGET_START_HP
	if weapon_no_element and preseed_ok and hp_dropped:
		print("\n[PASS] Non-elemental Broad Sword deals normal damage (HP %+d), absorb did NOT fire" % _hp_delta)
	else:
		var why: Array = []
		if not weapon_no_element: why.append("Broad Sword weapon_element != 0 (encode bug)")
		if not preseed_ok:        why.append("target preseed missing Fire absorb (test rig bug)")
		if not hp_dropped:        why.append("target HP did not drop; either no hit OR absorb wrongly fired (delta=%+d)" % _hp_delta)
		print("\n[FAIL] %s" % ", ".join(why))
	print("==================================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
