extends EvasionTestBase

## Attacker: melee sword. Target: c_ev=50 (50% class evade).
## Expected: ~50% evade reactions (±25%), rest taking_damage.


func get_test_name() -> String:
	return "GPU Evasion Melee Evade Test"


func get_team0_unit_configs() -> Array:
	return [_melee_attacker()]


func get_team1_unit_configs() -> Array:
	return [_melee_target({"c_ev": 50})]


func _print_results():
	_print_header()
	var total = _observed.size()
	var counts = _get_counts()
	if total < 10:
		print("[FAIL] Too few reactions: %d (need 10+)" % total)
	else:
		var evade_pct = float(counts.get("evade", 0)) / total * 100.0
		if evade_pct >= 25.0 and evade_pct <= 75.0:
			print("[PASS] evade rate %.0f%% is within 50±25%%" % evade_pct)
		else:
			print("[FAIL] evade rate %.0f%% outside 50±25%% range" % evade_pct)
	print("===\n")
