extends EvasionTestBase

## Attacker: melee sword. Target: c_ev=30, s_ev=30, w_ev=30 (90% total miss).
## Expected: mix of evade, shield_block, blade_grasp, and ~10% taking_damage.


func get_test_name() -> String:
	return "GPU Evasion Mixed Test"


func get_team0_unit_configs() -> Array:
	return [_melee_attacker()]


func get_team1_unit_configs() -> Array:
	return [_melee_target({"shield_id": 129, "c_ev": 30, "s_ev": 30, "w_ev": 30})]


func _print_results():
	_print_header()
	var total = _observed.size()
	var counts = _get_counts()

	if total == 0:
		print("[FAIL] No reactions observed")
		print("===\n")
		return

	var has_evade = counts.get("evade", 0) > 0
	var has_block = counts.get("shield_block", 0) > 0
	var has_parry = counts.get("blade_grasp", 0) > 0
	var hit_rate = float(counts.get("taking_damage", 0)) / max(1, total) * 100.0

	var pass_all = true
	if not has_evade:
		print("[FAIL] No evade reactions observed (expected ~30%%)")
		pass_all = false
	if not has_block:
		print("[FAIL] No shield_block reactions observed (expected ~30%%)")
		pass_all = false
	if not has_parry:
		print("[FAIL] No blade_grasp reactions observed (expected ~30%%)")
		pass_all = false
	if hit_rate > 25.0:
		print("[FAIL] Hit rate %.0f%% exceeds 25%% tolerance (expected ~10%%)" % hit_rate)
		pass_all = false

	if pass_all:
		print("[PASS] All 3 miss types present, hit rate %.0f%%" % hit_rate)
	print("===\n")
