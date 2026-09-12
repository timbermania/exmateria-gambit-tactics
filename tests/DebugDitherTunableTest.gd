extends Node
## Guard: DebugConfig.psx_dither_enabled is a Tune tunable (ADR-0068 decision 10 —
## debug-only preferences bind like anything else). It is the bool analog of the
## live_par migration: the property coalesces a committed `render.psx_dither_enabled`
## override OVER the project.godot [shader_globals] default, the setter routes
## writes through Tune, and an `_apply` callback pushes the `psx_dither_enabled`
## global shader parameter + emits `psx_dither_changed`. Before the migration the
## property was a hardcoded stored bool (a rival default that ignored Tune), which
## reds this guard.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/DebugDitherTunableTest.tscn

const SLUG := "render.psx_dither_enabled"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_coalesces_override()
	_test_override_drives_signal()
	_test_clear_falls_back_to_default()

	print("\n=== DebugDitherTunableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DebugDitherTunableTest")
		get_tree().quit(1)
	else:
		print("[PASS] DebugDitherTunableTest")
		get_tree().quit(0)


## A committed override reads back through the property — the whole point of the
## tunable. Default is true (project.godot); overriding to false must flip the read.
func _test_coalesces_override() -> void:
	Tune.set_value(SLUG, false)
	_check("override false coalesces through the property", DebugConfig.psx_dither_enabled, false)
	Tune.clear(SLUG)  # restore shared autoload state


## A scrub reaches the running game: an override change drives the bound
## `_apply_dither`, which emits `psx_dither_changed` with the coalesced value. This
## is the two-way binding decision 10 exists for (the push a poll read can't do).
func _test_override_drives_signal() -> void:
	var seen: Array = []
	var handler := func(v: bool) -> void: seen.append(v)
	DebugConfig.psx_dither_changed.connect(handler)
	Tune.set_value(SLUG, false)  # default true -> false, not deduped
	DebugConfig.psx_dither_changed.disconnect(handler)
	Tune.clear(SLUG)  # restore shared autoload state
	_check("override emits psx_dither_changed(false)", seen == [false], true)


## With no override, the property returns the single-home default sourced from
## project.godot [shader_globals] (true) — not a rival hardcoded literal.
func _test_clear_falls_back_to_default() -> void:
	Tune.set_value(SLUG, false)
	Tune.clear(SLUG)
	var default_val: bool = bool(ProjectSettings.get_setting(
		"shader_globals/psx_dither_enabled", {}).get("value", true))
	_check("clear falls back to the project.godot default", DebugConfig.psx_dither_enabled, default_val)


func _check(label: String, actual: bool, expected: bool) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
