extends Node
## Move-2 guard (ADR-0068): the PSX color-calibration global psx_gamma is OWNED by PSXDisplay —
## it binds `render.psx_gamma` in _ready (default from project.godot [shader_globals]) and pushes
## the global shader param on change — so a committed override applies at boot in EVERY scene, with
## no panel writing the global (decision 12). PSXDisplay is an autoload, so its binds already
## ran at boot; we assert the registry it produced + coalesce.
##
## The panel that used to view this slug is DELETED (ADR-0151) — it declared nothing, and the
## F3 Registry page renders every registered slug (ADR-0068 dec. 9). This test is now the whole
## ownership guard for render.psx_gamma.
##
## (psx_brightness was RETIRED — ADR-0074 fold endgame: every fold bakes its ÷255→÷128 display-gouraud
## gain per-producer, so there is no shared brightness global / render.psx_brightness tunable left.)
##
## Run: <GODOT> --path . --quit-after 5 res://tests/PsxColorCalibrationTuneTest.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	# PSXDisplay._ready (autoload) already registered this slug with its
	# project.godot default + affordance hint — proof it owns it.
	_assert_approx(Tune.default_of("render.psx_gamma"), 1.4,
		"PSXDisplay registered render.psx_gamma with the project.godot default")

	# render.psx_brightness must be GONE (retired in the ADR-0074 endgame): no default registered.
	_assert_true(Tune.default_of("render.psx_brightness") == null,
		"render.psx_brightness is retired — no longer registered")
	# And the global shader param itself is deleted (RenderingServer returns null for an unknown global).
	_assert_true(RenderingServer.global_shader_parameter_get(&"psx_brightness") == null,
		"the psx_brightness global shader param is deleted")

	# A scrub coalesces (and drives _apply_gamma → the global shader param).
	Tune.set_value("render.psx_gamma", 2.1)
	_assert_approx(Tune.bind("render.psx_gamma", 1.4), 2.1,
		"scrubbing render.psx_gamma coalesces the override")

	Tune.clear("render.psx_gamma")

	print("\n=== PsxColorCalibrationTuneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PsxColorCalibrationTuneTest")
		get_tree().quit(1)
	else:
		print("[PASS] PsxColorCalibrationTuneTest")
		get_tree().quit(0)


func _assert_approx(actual, expected: float, label: String) -> void:
	if actual != null and is_equal_approx(float(actual), expected):
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
