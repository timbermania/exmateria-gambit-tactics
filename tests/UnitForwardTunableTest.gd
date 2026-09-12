extends Node3D
## Move-2 guard for ADR-0068: the UNIT-mode forward nudge (ot_unit_forward,
## ADR-0009) is OWNED by Unit — it binds `render.ot_unit_forward` onto the unit's
## own material — so a committed override coalesces onto a freshly spawned unit AND a
## live scrub re-drives every unit's material, in EVERY scene, with no
## UnitShaderDebugPanel fan-out over a units accessor (decision 12). Before this the
## panel iterated a units list and pushed the param onto each material directly.
##
## Spawns a real Unit against a real map+camera (like UnitVisualDefaultsTuneTest), NOT
## the GPUArena roster path, to dodge the roster-spawn native crash.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/UnitForwardTunableTest.tscn

@onready var map: Node3D = $ProceduralMap

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Override must be live BEFORE the unit spawns so its material bind coalesces it.
	Tune.reset_overrides()
	# reset_overrides(), not reset(): the OVERRIDES go, the `_static_init` boot registration
	# stands. So every tunable this test's production scene reads — not just the ones it scrubs —
	# still coalesces onto a REGISTERED default rather than Nil (ADR-0068 R3), with
	# no central replay to call. This is the registration PRODUCTION runs on: nothing replays
	# there either (#535, ADR-0173). Plain reset() would clear the declarations and a
	# get_value() inside the spawned node would assert (R5).
	Tune.set_value("render.ot_unit_forward", 0.5)

	await get_tree().process_frame
	map.change_map("MAP042")
	await get_tree().process_frame

	var unit_scene = load("res://assets/scenes/Unit.tscn")
	var unit: Unit = unit_scene.instantiate()
	unit.name = "TestUnit"
	add_child(unit)
	await get_tree().process_frame
	unit.body_sprite_id = 0x01
	unit.place_on_tile(5, 6, map)
	await get_tree().process_frame

	_assert_approx(float(unit.material.get_shader_parameter("ot_unit_forward")), 0.5,
		"render.ot_unit_forward override coalesces onto the unit material at spawn")

	# Live re-apply: a scrub after spawn re-drives the already-on-screen unit.
	Tune.set_value("render.ot_unit_forward", 0.9)
	await get_tree().process_frame
	_assert_approx(float(unit.material.get_shader_parameter("ot_unit_forward")), 0.9,
		"scrubbing render.ot_unit_forward live-updates the spawned unit material")

	print("\n=== UnitForwardTunableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UnitForwardTunableTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitForwardTunableTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])
