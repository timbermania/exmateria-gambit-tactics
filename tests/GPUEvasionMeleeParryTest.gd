extends EvasionTestBase

## Attacker: melee sword. Target: w_ev=50 (50% weapon parry / Blade Grasp).
## Expected: ~50% blade_grasp reactions (±25%), rest taking_damage.


func get_test_name() -> String:
	return "GPU Evasion Melee Parry Test"


func get_team0_unit_configs() -> Array:
	return [_melee_attacker()]


func get_team1_unit_configs() -> Array:
	return [_melee_target({"w_ev": 50})]


func _print_results():
	_print_header()
	var total = _observed.size()
	var counts = _get_counts()
	if total < 10:
		print("[FAIL] Too few reactions: %d (need 10+)" % total)
	else:
		var parry_pct = float(counts.get("blade_grasp", 0)) / total * 100.0
		if parry_pct >= 25.0 and parry_pct <= 75.0:
			print("[PASS] blade_grasp rate %.0f%% is within 50±25%%" % parry_pct)
		else:
			print("[FAIL] blade_grasp rate %.0f%% outside 50±25%% range" % parry_pct)
	print("===\n")
