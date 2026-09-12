extends GPUCombatTestBase

## GPU Simultaneous Cinematic Test (issue #118)
##
## Witness that two units finishing a cinematic spell (Fire ct=4) on the
## same GPU tick BOTH deal damage. Pre-#118 the shader stored the live
## cinematic in a battle-scoped header pair ([code]BH_CINEMATIC_CASTER_IDX[/code]
## / [code]BH_CINEMATIC_TIMER[/code]); a same-tick race let the second caster
## stomp the first's slot. The loser still spent MP and stamped its AOE
## target, but never ran its orchestrator and got its stamps wiped by the
## winner's teardown. The fix lifts the single-cinematic invariant by
## promoting the timer to a per-unit field ([code]U_CINEMATIC_TIMER[/code])
## and converting [code]U_PAUSED[/code] to a ref-count.
##
## Layout (Manhattan), separated to isolate AOE radius:
##   MageA   (team 0, ABILITY_FIRE)  at (0, 0)
##   MageB   (team 0, ABILITY_FIRE)  at (0, 10)
##   TargetA (team 1, defenseless)   at (4, 0)
##   TargetB (team 1, defenseless)   at (4, 10)
##
## Both Mages share identical PA=5/MA=12/Faith=100/speed=100/mp=99, so they
## roll the same gambit on the same tick, finish charge_time together, and
## race for the cinematic slot. Each Mage's nearest enemy is its
## column-mate; Fire's effect_area=1 keeps the cast off the other column.
##
## PASS: both TargetA and TargetB take the EXPECTED_BASE_DAMAGE Fire hit
## (168 HP on the Fire / Mage stat block, confirmed by
## [code]GPUOilFireDoubleTest:ControlKnight[/code]).
## FAIL: either target is untouched within max_ticks (the race silently
## void'd one cast).

const ABILITY_FIRE = 16
const TARGET_START_HP = 9999
# Base Fire damage on this PA=5/MA=12/Faith=100 Mage against a Faith=100
# defenseless target. Witnessed by GPUOilFireDoubleTest:ControlKnight.
const EXPECTED_BASE_DAMAGE = 168


func get_test_name() -> String:
	return "GPU Simultaneous Cinematic Test (two Mages cast Fire same tick, both targets must hit for 168)"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "MageA",
			"pos_x": 0, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x04,
		},
		{
			"name": "MageB",
			"pos_x": 0, "pos_z": 10,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x04,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "TargetA",
			"pos_x": 4, "pos_z": 0,
			"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
		},
		{
			"name": "TargetB",
			"pos_x": 4, "pos_z": 10,
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
	if unit_idx == 0 or unit_idx == 1:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# Fire ct=4 -> ~80 ticks charge per cast. Allow generous tail so the post-
	# cinematic re-cast (if the bug is present) still finishes inside the window.
	max_ticks = 1500
	super._ready()


var _target_a_delta: int = 0
var _target_b_delta: int = 0
var _results_printed: bool = false


# Per-target latch + AND-gate completion. Hook combat_loop.hp_changed instead
# of polling state because at time_scale=4.0 multiple cast cycles can land
# between two host-frame polls; the signal fires once per per-tick interpreter
# damage event, so the FIRST drop's magnitude is captured exactly (168 if the
# #118 fix holds), not a cumulative sum.
func on_hp_changed(unit_idx: int, _old_hp: int, _new_hp: int, delta: int) -> void:
	if _results_printed:
		return
	if delta >= 0:
		return  # heal / no-op
	if unit_idx == 2 and _target_a_delta == 0:
		_target_a_delta = -delta
	elif unit_idx == 3 and _target_b_delta == 0:
		_target_b_delta = -delta
	if _target_a_delta > 0 and _target_b_delta > 0:
		_print_results(gpu_state_reader.get_all_unit_states() if gpu_state_reader else [])


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return
	if current_tick >= max_ticks - 1:
		var states = gpu_state_reader.get_all_unit_states()
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var ta_hp := int(states[2].get("hp", TARGET_START_HP)) if states.size() > 2 else TARGET_START_HP - _target_a_delta
	var tb_hp := int(states[3].get("hp", TARGET_START_HP)) if states.size() > 3 else TARGET_START_HP - _target_b_delta
	if _target_a_delta == 0 and ta_hp < TARGET_START_HP:
		_target_a_delta = TARGET_START_HP - ta_hp
	if _target_b_delta == 0 and tb_hp < TARGET_START_HP:
		_target_b_delta = TARGET_START_HP - tb_hp

	print("\n=== SIMULTANEOUS CINEMATIC TEST RESULTS ===")
	print("  TargetA HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, ta_hp, -_target_a_delta])
	print("  TargetB HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, tb_hp, -_target_b_delta])
	print("  Expected: %d on each target" % EXPECTED_BASE_DAMAGE)

	var a_hit := _target_a_delta > 0
	var b_hit := _target_b_delta > 0
	var a_ok := _target_a_delta == EXPECTED_BASE_DAMAGE
	var b_ok := _target_b_delta == EXPECTED_BASE_DAMAGE

	if a_hit and b_hit and a_ok and b_ok:
		print("\n[PASS] both Mages' Fire landed (TargetA=%d, TargetB=%d)" % [
			_target_a_delta, _target_b_delta])
	else:
		var why: Array = []
		if not a_hit: why.append("TargetA wasn't hit within %d ticks (the cinematic race silently void'd MageA's cast)" % max_ticks)
		if not b_hit: why.append("TargetB wasn't hit within %d ticks (the cinematic race silently void'd MageB's cast)" % max_ticks)
		if a_hit and not a_ok:
			why.append("TargetA damage off (got %d, expected %d)" % [_target_a_delta, EXPECTED_BASE_DAMAGE])
		if b_hit and not b_ok:
			why.append("TargetB damage off (got %d, expected %d)" % [_target_b_delta, EXPECTED_BASE_DAMAGE])
		print("\n[FAIL] %s" % ", ".join(why))
	print("==========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
