extends GPUCombatTestBase

## GPU Weapon Fire Absorb Test (issue #116)
##
## Witnesses the basic-attack weapon-element absorb flip: an attacker wielding
## Flame Rod (id 53, weapon.elements = ["Fire"]) basic-attacks a target whose
## element_absorb_mask carries the Fire bit, and the target HEALS instead of
## taking damage. Mirrors BATTLE.BIN [code]FUN_80186FD0[/code] at
## [code]0x80186FD0[/code]: the one-instruction wrapper that reads
## CurrentAbilityData.CurrentWeaponElement and tail-calls the equipment-
## defense matrix [code]FUN_80184E98[/code]. No status overlay -- weapon path
## explicitly skips [code]FUN_80186FF8[/code] (locked in by
## GPUWeaponElementNoStatusTest below).
##
## Layout (Manhattan):
##   Fighter (team 0, Flame Rod, basic attack) at (0, 0)
##   Target  (team 1, element_absorb_mask = Fire) at (1, 0)
##
## PASS: Target HP rises above starting HP (any positive delta).
## FAIL: HP stays flat or drops -- absorb didn't fire on the weapon path.

const FLAME_ROD_ID = 53
const FIRE_BIT_MASK = 1 << 1  # ElementEncoder.ELEMENT_MAP "Fire" = 1
const TARGET_START_HP = 100
const TARGET_MAX_HP = 999  # well above start so the heal isn't capped


func get_test_name() -> String:
	return "GPU Weapon Fire Absorb Test (Flame Rod basic attack vs Fire-absorb target)"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "FlameRodFighter",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 12, "ma": 5, "wp": 3,  # Flame Rod WP=3, PA*WP baseline = 36
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
		"weapon_id": FLAME_ROD_ID,
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "FireAbsorbTarget",
		"pos_x": 1, "pos_z": 0,
		"hp": TARGET_START_HP, "max_hp": TARGET_MAX_HP,
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


var _absorb_witnessed_tick: int = -1
var _absorb_hp_delta: int = 0
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
	if _absorb_witnessed_tick < 0 and hp_now > TARGET_START_HP:
		_absorb_witnessed_tick = current_tick
		_absorb_hp_delta = hp_now - TARGET_START_HP
		_print_results(states)
		return

	if hp_now < TARGET_START_HP:
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
	var attacker_w_element := int(states[0].get("weapon_element", 0))

	print("\n=== WEAPON FIRE ABSORB TEST RESULTS ===")
	print("  Target HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, hp_now, hp_now - TARGET_START_HP])
	print("  Attacker weapon_element = %d (Fire=1 expected)" % attacker_w_element)
	print("  Target element_absorb_mask = 0x%02X (Fire bit %s)" % [
		absorb_mask,
		"SET" if (absorb_mask & FIRE_BIT_MASK) != 0 else "missing"])
	print("  absorb_witness_tick = %d" % _absorb_witnessed_tick)

	var preseed_ok := (absorb_mask & FIRE_BIT_MASK) != 0
	var weapon_ok := attacker_w_element == 1
	var hp_up := _absorb_witnessed_tick >= 0 and hp_now > TARGET_START_HP
	if preseed_ok and weapon_ok and hp_up:
		print("\n[PASS] Flame Rod basic attack absorbed by Fire-Absorb target (HP +%d)" % _absorb_hp_delta)
	else:
		var why: Array = []
		if not preseed_ok: why.append("target element_absorb_mask missing Fire bit")
		if not weapon_ok:  why.append("attacker weapon_element not 1 (Flame Rod encode failed)")
		if not hp_up:      why.append("HP did not rise within %d ticks" % max_ticks)
		print("\n[FAIL] %s" % ", ".join(why))
	print("========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
