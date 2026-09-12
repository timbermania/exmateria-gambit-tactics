extends EvasionTestBase

## Attacker: bow. Target: s_ev=50, shield_id=129 (50% shield block).
## Expected: ~50% shield_block reactions (±25%), rest taking_damage.


func get_test_name() -> String:
	return "GPU Evasion Ranged Block Test"


func get_result_tick() -> int:
	return 1500


func get_team0_unit_configs() -> Array:
	return [_ranged_attacker()]


func get_team1_unit_configs() -> Array:
	return [_ranged_target({"shield_id": 129, "s_ev": 50})]


func _print_results():
	_print_header()
	var total = _observed.size()
	var counts = _get_counts()
	if total < 10:
		print("[FAIL] Too few reactions: %d (need 10+)" % total)
	else:
		var block_pct = float(counts.get("shield_block", 0)) / total * 100.0
		if block_pct >= 25.0 and block_pct <= 75.0:
			print("[PASS] shield_block rate %.0f%% is within 50±25%%" % block_pct)
		else:
			print("[FAIL] shield_block rate %.0f%% outside 50±25%% range" % block_pct)
	print("===\n")
