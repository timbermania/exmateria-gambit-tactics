extends EvasionTestBase

## Attacker: melee sword. Target: 0% evasion.
## Expected: 100% taking_damage reactions.


func get_test_name() -> String:
	return "GPU Evasion Melee Hit Test"


func get_team0_unit_configs() -> Array:
	return [_melee_attacker()]


func get_team1_unit_configs() -> Array:
	return [_melee_target({"c_ev": 0, "s_ev": 0, "w_ev": 0})]


func _print_results():
	_print_header()
	var total = _observed.size()
	var counts = _get_counts()
	if total == 0:
		print("[FAIL] No reactions observed")
	elif counts.get("taking_damage", 0) == total:
		print("[PASS] All %d reactions were taking_damage" % total)
	else:
		print("[FAIL] Expected 100%% taking_damage, got %s" % str(counts))
	print("===\n")
