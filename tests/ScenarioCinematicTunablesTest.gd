extends Node
## Move-2 guard for ADR-0068: the EVTCHR cinematic-scrub overrides (segment / frame)
## are OWNED by ScenarioVM — it binds each to a `scenario.*` Tune slug in _ready — so
## a committed override coalesces at boot AND a live scrub re-drives the override in
## EVERY scene (and survives a scenario reload), with no ScenarioCinematicDebugPanel
## fan-out (decision 12). Before this the panel wrote straight onto the VM node.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioCinematicTunablesTest.tscn

const ScenarioVMScript = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset_overrides()
	# reset_overrides(), not reset(): the OVERRIDES go, the `_static_init` boot registration
	# stands. So every tunable this test's production scene reads — not just the ones it scrubs —
	# still coalesces onto a REGISTERED default rather than Nil (ADR-0068 R3), with
	# no central replay to call. This is the registration PRODUCTION runs on: nothing replays
	# there either (#535, ADR-0173). Plain reset() would clear the declarations and a
	# get_value() inside the spawned node would assert (R5).
	Tune.set_value("scenario.cinematic_segment_override", 5)
	Tune.set_value("scenario.cinematic_frame_override", 220)

	var vm = ScenarioVMScript.new()
	add_child(vm)
	await get_tree().process_frame

	_assert_eq(vm.cinematic_segment_override, 5,
		"scenario.cinematic_segment_override coalesces at spawn")
	_assert_eq(vm.cinematic_frame_override, 220,
		"scenario.cinematic_frame_override coalesces at spawn")

	Tune.set_value("scenario.cinematic_segment_override", 12)
	Tune.set_value("scenario.cinematic_frame_override", 240)
	await get_tree().process_frame

	_assert_eq(vm.cinematic_segment_override, 12,
		"scrubbing scenario.cinematic_segment_override live-updates the VM")
	_assert_eq(vm.cinematic_frame_override, 240,
		"scrubbing scenario.cinematic_frame_override live-updates the VM")

	print("\n=== ScenarioCinematicTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioCinematicTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCinematicTunablesTest")
		get_tree().quit(0)


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])
