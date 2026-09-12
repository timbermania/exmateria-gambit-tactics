extends Node3D
## Move-2 guard for ADR-0068: the {3C} weather look knobs (drop intensity/width/length,
## splat intensity/size, straddle gate) are OWNED by ScenarioWeather — it binds each to
## a `weather.*` Tune slug in _ready — so a committed override coalesces the instant the
## VM lazily spawns the node AND a live scrub re-drives it, with no ScenarioWeather-
## DebugPanel fan-out (decision 12). Before this the panel wrote straight onto the node.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioWeatherTunablesTest.tscn

const WeatherScript = preload("res://src/scenarios/ScenarioWeather.gd")

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
	Tune.set_value("weather.drop_intensity", 1.5)
	Tune.set_value("weather.splat_straddle_gate", false)

	var w = WeatherScript.new()
	add_child(w)
	await get_tree().process_frame

	_assert_approx(w.drop_intensity, 1.5, "weather.drop_intensity coalesces at spawn")
	_assert_true(not w.splat_straddle_gate, "weather.splat_straddle_gate override coalesces at spawn")

	Tune.set_value("weather.drop_intensity", 0.5)
	Tune.set_value("weather.drop_width_px", 5.0)
	Tune.set_value("weather.drop_length_scale", 2.5)
	Tune.set_value("weather.splat_intensity", 0.9)
	Tune.set_value("weather.splat_size", 2.0)
	Tune.set_value("weather.splat_straddle_gate", true)
	await get_tree().process_frame

	_assert_approx(w.drop_intensity, 0.5, "scrubbing weather.drop_intensity live-updates")
	_assert_approx(w.drop_width_px, 5.0, "scrubbing weather.drop_width_px live-updates")
	_assert_approx(w.drop_length_scale, 2.5, "scrubbing weather.drop_length_scale live-updates")
	_assert_approx(w.splat_intensity, 0.9, "scrubbing weather.splat_intensity live-updates")
	_assert_approx(w.splat_size, 2.0, "scrubbing weather.splat_size live-updates")
	_assert_true(w.splat_straddle_gate, "scrubbing weather.splat_straddle_gate live-updates")

	print("\n=== ScenarioWeatherTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioWeatherTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWeatherTunablesTest")
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
