extends GPUCombatTestBase

## GPU Reaction Counter Test
##
## Tests Tier 2 #7 (part 2) — the REACT_COUNTER reaction.
##
## Attacker melee-hits Defender. Defender has Counter equipped and is
## adjacent (distance 1), so the counter fires the same tick. Both hits
## resolve in Phase 3.
##
## Setup:
##   Attacker: pa=10, wp=5, hp=200, no reaction
##   Defender: pa=8,  wp=5, hp=200, REACT_COUNTER (id 0)
##
##   First swing damage on Defender:  pa(10) * wp(5) = 50.
##   Counter damage on Attacker:      pa(8)  * wp(5) = 40.
##
## Expected after the first hit lands:
##   Defender HP: 200 - 50 = 150
##   Attacker HP: 200 - 40 = 160  (counter fired in the same tick)

const REACT_COUNTER = 0

var _initial_attacker_hp: int = -1
var _initial_defender_hp: int = -1
var _post_hit_attacker_hp: int = -1
var _post_hit_defender_hp: int = -1
var _done_logged: bool = false
var _check_timer: float = 0.0


func get_test_name() -> String:
	return "GPU Reaction Counter Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Attacker", "pos_x": 1, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Defender_Counter", "pos_x": 2, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 8, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			"reaction_ability": REACT_COUNTER,
		},
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_attack_gambit()]
	return []  # Defender just stands there


func _ready():
	max_ticks = 400
	super._ready()


func _process(delta):
	super._process(delta)
	if _done_logged or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	if _initial_attacker_hp < 0:
		_initial_attacker_hp = int(states[0].get("hp", 0))
	if _initial_defender_hp < 0:
		_initial_defender_hp = int(states[1].get("hp", 0))

	var a_hp = int(states[0].get("hp", 0))
	var d_hp = int(states[1].get("hp", 0))

	if d_hp < _initial_defender_hp and _post_hit_defender_hp < 0:
		_post_hit_defender_hp = d_hp
		_post_hit_attacker_hp = a_hp
		_print_results()


func _print_results():
	if _done_logged:
		return
	_done_logged = true

	# Attacker swing dmg = 10*5 = 50 → defender HP 200-50 = 150
	# Counter dmg = 8*5 = 40 → attacker HP 200-40 = 160
	var def_expected = 150
	var atk_expected = 160

	print("\n=== REACTION COUNTER TEST RESULTS ===")
	print("  Defender HP: %d (expected %d, init %d)" % [
		_post_hit_defender_hp, def_expected, _initial_defender_hp])
	print("  Attacker HP: %d (expected %d, init %d)" % [
		_post_hit_attacker_hp, atk_expected, _initial_attacker_hp])

	var def_ok = _post_hit_defender_hp == def_expected
	var atk_ok = _post_hit_attacker_hp == atk_expected
	if def_ok and atk_ok:
		print("\n[PASS] Counter fired in the same tick as the triggering hit")
	else:
		var why = []
		if not def_ok:
			why.append("attacker swing did not land cleanly")
		if not atk_ok:
			why.append("counter did not fire / mis-damaged")
		print("\n[FAIL] " + ", ".join(why))
	print("=========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _done_logged:
		_print_results()
