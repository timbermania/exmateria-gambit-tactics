extends GPUCombatTestBase

## GPU Oil × Fire Double Test (issue #112)
##
## Witnesses the status-driven Oil×Fire doubling added in PRD #112. An Oiled
## target takes [b]2×[/b] Fire damage relative to an identical control. Mirrors
## BATTLE.BIN [code]FUN_80186FF8[/code] at [code]0x80187000[/code]: the Oil
## branch doubles AbPower BEFORE the equipment-defense matrix at
## [code]0x801870E0[/code] runs.
##
## Layout (Manhattan):
##   Mage    (team 0, caster, Fire gambit)         at (0, 0)
##   Oiled   (team 1, status_flags_lo = OIL bit)   at (4, 0)
##   Control (team 1, identical sans Oil)          at (4, 1)
##
## Fire AOE radius 1 -> both targets hit by a single cast (same precedent the
## AOE Combat Test relies on). We compare per-target HP deltas after the cast.
##
## PASS: Oiled HP delta == 2 × Control HP delta (and both > 0).
## FAIL: ratio differs, or one target wasn't hit, or doubling wasn't applied.

const ABILITY_FIRE = 16
const STATUS_OIL_BIT = 30
const TARGET_START_HP = 500


func get_test_name() -> String:
	return "GPU Oil×Fire Double Test (Fire on Oiled vs Control)"


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
			"name": "OiledKnight",
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
	# Fire ct=4 -> ~80 ticks charge + anim + projectile + AOE resolve.
	max_ticks = 1500
	super._ready()


var _oiled_delta: int = 0
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

	var oiled_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", TARGET_START_HP))

	# Per-target latch + AND-gate completion: AOE Phase 1 lands on the two
	# targets across separate snapshots, so a single-shot "either changed"
	# capture races whichever HP updates first.
	if _oiled_delta == 0 and oiled_hp < TARGET_START_HP:
		_oiled_delta = TARGET_START_HP - oiled_hp
	if _control_delta == 0 and control_hp < TARGET_START_HP:
		_control_delta = TARGET_START_HP - control_hp
	if _oiled_delta > 0 and _control_delta > 0:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var oiled_hp := int(states[1].get("hp", TARGET_START_HP))
	var control_hp := int(states[2].get("hp", TARGET_START_HP))
	var oiled_flags := int(states[1].get("status_flags_lo", 0))
	if _oiled_delta == 0:   _oiled_delta = TARGET_START_HP - oiled_hp
	if _control_delta == 0: _control_delta = TARGET_START_HP - control_hp

	print("\n=== OIL × FIRE DOUBLE TEST RESULTS ===")
	print("  OiledKnight  HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, oiled_hp, -_oiled_delta])
	print("  ControlKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, control_hp, -_control_delta])
	print("  OiledKnight status_flags_lo = 0x%08X (Oil bit %s)" % [
		oiled_flags,
		"SET" if (oiled_flags & (1 << STATUS_OIL_BIT)) != 0 else "missing"])

	var preseed_ok := (oiled_flags & (1 << STATUS_OIL_BIT)) != 0
	var both_hit := _oiled_delta > 0 and _control_delta > 0
	var ratio_ok := both_hit and _oiled_delta == _control_delta * 2

	if preseed_ok and both_hit and ratio_ok:
		print("\n[PASS] Oil doubled Fire damage (%d vs control %d, ratio 2.0)" % [
			_oiled_delta, _control_delta])
	else:
		var why: Array = []
		if not preseed_ok: why.append("status_flags_lo missing Oil bit (encode failed)")
		if not both_hit:   why.append("at least one target wasn't hit (oiled=%d control=%d)" % [_oiled_delta, _control_delta])
		if both_hit and not ratio_ok:
			why.append("ratio != 2.0 (oiled=%d, control=%d, expected oiled=%d)" % [
				_oiled_delta, _control_delta, _control_delta * 2])
		print("\n[FAIL] %s" % ", ".join(why))
	print("=======================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
