extends GPUCombatTestBase

## GPU Oil × Fire × Absorb Composition Test (issue #112)
##
## Witnesses the ordering decision in PRD #112's status overlay: ROM applies the
## Oil ×2 BEFORE the equipment-defense matrix, so an Oiled target equipped with
## Fire-Absorb heals for [b]2× baseline[/b] (the doubled amount sign-flips to
## heal). ROM authority: BATTLE.BIN [code]FUN_80186FF8[/code] at
## [code]0x80187000[/code] (Oil ×2) then equipment matrix
## [code]FUN_80184E98[/code] at [code]0x80184E98[/code] (Absorb wins).
##
## Layout (Manhattan):
##   Mage      (team 0, caster, Fire gambit)         at (0, 0)
##   OilAbsorb (team 1, Oil + Fire-Absorb mask)      at (4, 0)
##   Control   (team 1, identical sans Oil/Absorb)   at (4, 1)
##
## PASS: OilAbsorb HP rises by 2 × ControlKnight's HP drop.
## FAIL: ratio differs (×1 would mean Oil didn't fire; sign wrong would mean
## Absorb didn't compose).

const ABILITY_FIRE = 16
const STATUS_OIL_BIT = 30
const ELEMENT_FIRE = 1
const FIRE_BIT_MASK = 1 << ELEMENT_FIRE
const TARGET_START_HP = 100
const TARGET_MAX_HP = 999  # well above start so the heal isn't capped


func get_test_name() -> String:
	return "GPU Oil×Fire×Absorb Composition Test (Oil + Absorb heals 2× baseline)"


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
			"name": "OilAbsorbKnight",
			"pos_x": 4, "pos_z": 0,
			"hp": TARGET_START_HP, "max_hp": TARGET_MAX_HP,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			"status_flags_lo": 1 << STATUS_OIL_BIT,
			"element_absorb_mask": FIRE_BIT_MASK,
		},
		{
			"name": "ControlKnight",
			"pos_x": 4, "pos_z": 1,
			"hp": 500, "max_hp": 500,
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


var _oilabsorb_delta: int = 0  # signed (positive = heal)
var _control_delta: int = 0    # positive damage amount
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

	var oilabsorb_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", 500))

	# Per-target latch + AND-gate completion: AOE Phase 1 lands on the two
	# targets across separate snapshots, so a single-shot "either changed"
	# capture races whichever HP updates first. Latch each delta independently
	# and only print once both have registered (model:
	# GPUWeaponElementNoStatusTest:128-167).
	if _oilabsorb_delta == 0 and oilabsorb_hp != TARGET_START_HP:
		_oilabsorb_delta = oilabsorb_hp - TARGET_START_HP
	if _control_delta == 0 and control_hp < 500:
		_control_delta = 500 - control_hp
	if _oilabsorb_delta != 0 and _control_delta > 0:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var oilabsorb_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", 500))
	var oilabsorb_flags := int(states[1].get("status_flags_lo", 0))
	var oilabsorb_absorb_mask := int(states[1].get("element_absorb_mask", 0))
	if _oilabsorb_delta == 0: _oilabsorb_delta = oilabsorb_hp - TARGET_START_HP
	if _control_delta == 0:   _control_delta = 500 - control_hp

	print("\n=== OIL × FIRE × ABSORB COMPOSITION TEST RESULTS ===")
	print("  OilAbsorbKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, oilabsorb_hp, _oilabsorb_delta])
	print("  ControlKnight   HP: start=500, now=%d (delta=%+d)" % [
		control_hp, -_control_delta])
	print("  OilAbsorbKnight status_flags_lo = 0x%08X (Oil bit %s)" % [
		oilabsorb_flags,
		"SET" if (oilabsorb_flags & (1 << STATUS_OIL_BIT)) != 0 else "missing"])
	print("  OilAbsorbKnight element_absorb_mask = 0x%02X (Fire bit %s)" % [
		oilabsorb_absorb_mask,
		"SET" if (oilabsorb_absorb_mask & FIRE_BIT_MASK) != 0 else "missing"])

	var preseed_oil := (oilabsorb_flags & (1 << STATUS_OIL_BIT)) != 0
	var preseed_absorb := (oilabsorb_absorb_mask & FIRE_BIT_MASK) != 0
	var heal_witnessed := _oilabsorb_delta > 0
	var control_hit := _control_delta > 0
	var ratio_ok := heal_witnessed and control_hit and _oilabsorb_delta == _control_delta * 2

	if preseed_oil and preseed_absorb and heal_witnessed and control_hit and ratio_ok:
		print("\n[PASS] Oil×Fire×Absorb composed to 2× heal (+%d vs control damage %d)" % [
			_oilabsorb_delta, _control_delta])
	else:
		var why: Array = []
		if not preseed_oil:    why.append("status_flags_lo missing Oil bit")
		if not preseed_absorb: why.append("element_absorb_mask missing Fire bit")
		if not heal_witnessed: why.append("OilAbsorbKnight did not heal (delta=%+d)" % _oilabsorb_delta)
		if not control_hit:    why.append("ControlKnight wasn't hit (no baseline)")
		if heal_witnessed and control_hit and not ratio_ok:
			why.append("ratio != 2.0 (heal=%d, baseline damage=%d, expected heal=%d)" % [
				_oilabsorb_delta, _control_delta, _control_delta * 2])
		print("\n[FAIL] %s" % ", ".join(why))
	print("=====================================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
