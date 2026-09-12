extends Node
## Move-2 guard for ADR-0068: the boxed-dialogue placement knobs (size scale, gaps,
## offset X/Y, triangle aim, billboard anchor, debug overlays) are OWNED by
## ScenarioDialogueBoxPool — ScenarioVM calls box_pool.bind_tunables(self) at boot,
## binding each to a `dialbox.*` Tune slug — so a committed override coalesces onto the
## live box AND a scrub re-drives it in EVERY scene (and survives a scenario reload),
## with no ScenarioDialogueBoxDebugPanel fan-out (decision 12). box_offset_px (Vector2)
## is split into two float slugs.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioDialogueBoxTunablesTest.tscn

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
	Tune.set_value("dialbox.box_size_scale", 2.0)
	Tune.set_value("dialbox.box_offset_x", 10.0)
	Tune.set_value("dialbox.anchor_to_billboard", false)

	var vm = ScenarioVMScript.new()
	add_child(vm)
	await get_tree().process_frame
	var bp = vm.box_pool

	_assert_approx(bp.box_size_scale, 2.0, "dialbox.box_size_scale coalesces at boot")
	_assert_approx(bp.box_offset_px.x, 10.0, "dialbox.box_offset_x coalesces onto the Vector2.x")
	_assert_true(not bp.anchor_to_billboard, "dialbox.anchor_to_billboard override coalesces at boot")

	Tune.set_value("dialbox.box_size_scale", 0.8)
	Tune.set_value("dialbox.box_gap_above_px", 50.0)
	Tune.set_value("dialbox.box_offset_x", -5.0)
	Tune.set_value("dialbox.box_offset_y", 7.0)
	Tune.set_value("dialbox.tri_aim_scale", 2.5)
	Tune.set_value("dialbox.debug_show_tile_orb", true)
	Tune.set_value("dialbox.anchor_to_billboard", true)
	await get_tree().process_frame

	_assert_approx(bp.box_size_scale, 0.8, "scrubbing dialbox.box_size_scale live-updates")
	_assert_approx(bp.box_gap_above_px, 50.0, "scrubbing dialbox.box_gap_above_px live-updates")
	_assert_approx(bp.box_offset_px.x, -5.0, "scrubbing dialbox.box_offset_x live-updates the Vector2.x")
	_assert_approx(bp.box_offset_px.y, 7.0, "scrubbing dialbox.box_offset_y live-updates the Vector2.y")
	_assert_approx(bp.tri_aim_scale, 2.5, "scrubbing dialbox.tri_aim_scale live-updates")
	_assert_true(bp.debug_show_tile_orb, "scrubbing dialbox.debug_show_tile_orb live-updates")
	_assert_true(bp.anchor_to_billboard, "scrubbing dialbox.anchor_to_billboard live-updates")

	print("\n=== ScenarioDialogueBoxTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioDialogueBoxTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDialogueBoxTunablesTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
