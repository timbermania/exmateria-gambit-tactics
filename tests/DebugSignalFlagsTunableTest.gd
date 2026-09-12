extends Node
## Guard: the setter+signal DebugConfig flags (show_depth / perf_hud_enabled /
## free_camera_enabled) are Tune tunables (ADR-0068 decision 10) with SIGNAL delivery
## — the harder cousins of the plain-var batch. Each property coalesces a committed
## `debug.*` override (getter), routes an assignment through Tune (setter), and a
## bound `_apply_*` emits the flag's existing signal with the coalesced value. The
## signal moving from the setter to the binding is the whole point: now a scrub in
## the generated dashboard (a Tune write, never a property assignment) drives the
## signal and reaches consumers, which a stored-bool setter could not. Before the
## migration the property was a stored bool whose setter ignored Tune — reds this.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/DebugSignalFlagsTunableTest.tscn

# `free_camera_enabled` LEFT this set at #500 — a system owns its own switch
# (ADR-0140 dec. 5). The gate is now PlayerCamera's static var on the
# `camera.free_camera_enabled` slug, read via `PlayerCamera.free_camera()`.
# Its signal was NOT relocated: `free_camera_enabled_changed` had zero `.connect()`
# in the tree — this file's own CASES row was the only reference outside DebugConfig,
# and all three production readers poll — so the push machinery was deleted, not moved.
const CASES := [
	{"flag": "show_depth", "slug": "debug.show_depth", "sig": "show_depth_changed"},
	{"flag": "perf_hud_enabled", "slug": "debug.perf_hud_enabled", "sig": "perf_hud_toggled"},
]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	for c: Dictionary in CASES:
		_test_case(c)

	print("\n=== DebugSignalFlagsTunableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DebugSignalFlagsTunableTest")
		get_tree().quit(1)
	else:
		print("[PASS] DebugSignalFlagsTunableTest")
		get_tree().quit(0)


func _test_case(c: Dictionary) -> void:
	var flag: String = c["flag"]
	var slug: String = c["slug"]
	var sig: String = c["sig"]
	Tune.clear(slug)  # start from the code default (shared autoload)

	# No override -> the property returns the code default (false).
	_check("%s: default false" % flag, DebugConfig.get(flag), false)

	# A committed override coalesces through the property.
	Tune.set_value(slug, true)
	_check("%s: override coalesces through the property" % flag, DebugConfig.get(flag), true)
	Tune.clear(slug)

	# An override change drives the flag's SIGNAL (via the bound _apply_*), the push a
	# dashboard scrub needs — a stored-bool setter only fires on a property assignment.
	var seen: Array = []
	var handler := func(v: bool) -> void: seen.append(v)
	DebugConfig.connect(sig, handler)
	Tune.set_value(slug, true)  # false -> true
	DebugConfig.disconnect(sig, handler)
	Tune.clear(slug)  # restore shared autoload state
	_check("%s: override drives %s(true)" % [flag, sig], seen, [true])


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
