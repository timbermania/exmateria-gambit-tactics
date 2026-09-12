extends Node

## Slice-2 guard (ADR-0068): PSXDisplay.live_par is a facade over the Tune
## tunable "render.pixel_aspect". The public contract (getter, setter+dedup, pixel_aspect
## shader-global write, live_par_changed) is PRESERVED, AND a Tune override now
## drives it — the seam that makes live_par persist + boot-load through Tune.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TunePsxParTest.tscn

const SLUG := "render.pixel_aspect"

var _failed := 0
var _passed := 0
var _signal_count := 0
var _boot_par := 0.0


func _ready() -> void:
	_boot_par = PSXDisplay.live_par
	PSXDisplay.live_par_changed.connect(func(_v): _signal_count += 1)

	_test_setter_drives_getter_and_signal()
	_test_setter_dedups()
	_test_tune_override_drives_live_par()

	Tune.clear(SLUG)
	PSXDisplay.live_par = _boot_par  # restore shared autoload state

	print("\n=== TunePsxParTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TunePsxParTest")
		get_tree().quit(1)
	else:
		print("[PASS] TunePsxParTest")
		get_tree().quit(0)


## PRESERVED: setting live_par updates the getter and emits live_par_changed
## exactly once. (The pixel_aspect shader-global write is exercised by the setter but
## not asserted via RenderingServer.global_shader_parameter_get — it returns null
## for values not pushed through the RS registry; the codebase reads shader
## defaults from ProjectSettings instead, see PSXDisplaySingleSourceTest.)
func _test_setter_drives_getter_and_signal() -> void:
	_signal_count = 0
	PSXDisplay.live_par = 1.37
	_assert_approx(PSXDisplay.live_par, 1.37, "getter reflects the set value")
	_assert_eq(_signal_count, 1, "setter emits live_par_changed once")


## PRESERVED: setting the same value again is a no-op — no second signal.
func _test_setter_dedups() -> void:
	PSXDisplay.live_par = 1.42
	_signal_count = 0
	PSXDisplay.live_par = 1.42
	_assert_eq(_signal_count, 0, "re-setting the same value does not re-emit")


## NEW: driving the Tune tunable directly (as the dashboard / boot-load does)
## pushes through to live_par, the shader global, and the signal.
func _test_tune_override_drives_live_par() -> void:
	_signal_count = 0
	Tune.set_value(SLUG, 1.53)
	_assert_approx(PSXDisplay.live_par, 1.53, "Tune override drives the live_par getter")
	_assert_eq(_signal_count, 1, "Tune override emits live_par_changed")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%.4f, got %.4f" % [label, expected, actual])
