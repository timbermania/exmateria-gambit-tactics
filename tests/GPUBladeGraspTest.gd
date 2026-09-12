extends GPUCombatTestBase

## GPU Blade Grasp Test
##
## Tests Tier 2 #7 part 3 — REACT_BLADE_GRASP.
##
## A high-PA defender with Blade Grasp gets a second evasion roll against
## melee attacks at chance = min(target.PA * 5, 95)%. With target.PA = 20
## the chance is capped at 95%; over many swings the defender should evade
## the vast majority. The test runs the simulation for enough ticks that
## a non-Blade-Grasp baseline would have killed the defender, and asserts
## the actual HP loss is well below the no-reaction baseline.

const REACT_BLADE_GRASP = 4


func get_test_name() -> String:
	return "GPU Blade Grasp Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Attacker", "pos_x": 1, "pos_z": 0,
			"hp": 999, "max_hp": 999, "pa": 10, "ma": 5, "wp": 5,
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
			"name": "BladeGrasper", "pos_x": 2, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 20, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			"reaction_ability": REACT_BLADE_GRASP,
		},
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	return [make_attack_gambit()] if team == 0 else []


var _initial_def_hp: int = -1
var _final_def_hp: int = -1
var _results_printed: bool = false
var _check_timer: float = 0.0


func _ready():
	max_ticks = 1000
	super._ready()


func _process(delta):
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	if _initial_def_hp < 0:
		_initial_def_hp = int(states[1].get("hp", 0))

	# Sample at tick 600 — enough for ~12 attempted swings (cycle is
	# ~50 ticks each) so the statistical assertion is meaningful.
	if current_tick >= 600 and not _results_printed:
		_final_def_hp = int(states[1].get("hp", 0))
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	var lost = _initial_def_hp - _final_def_hp
	# Each landed melee swing costs 50 HP (pa 10 * wp 5). Without Blade
	# Grasp, ~12 swings × 50 = ~600 HP lost by tick 600. With Blade Grasp
	# at 95% chance, expected hits ≈ 12 × 0.05 = 0.6; expected loss ≈ 30.
	# Pass threshold: < 200 HP lost (= < 4 hits, ~16× higher than expected).
	var threshold = 200
	var ok = lost < threshold

	print("\n=== BLADE GRASP TEST RESULTS ===")
	print("  Defender HP: %d (initial %d, lost %d)" % [
		_final_def_hp, _initial_def_hp, lost])
	print("  Threshold: < %d HP loss" % threshold)
	if ok:
		print("[PASS] Blade Grasp absorbed most melee swings")
	else:
		print("[FAIL] Defender took %d HP — reaction not firing or chance too low" % lost)
	print("==================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		if s.size() >= 2:
			_final_def_hp = int(s[1].get("hp", -1))
		_print_results()
