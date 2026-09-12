extends Node
## Guard for ADR-0068 Color support: Color is a first-class Tune type. Type inference
## picks a ColorPickerButton, and — the part that isn't free — a committed Color
## override round-trips through the JSON staging file (stored as [r,g,b,a], coerced
## back to Color on read). Pure-logic (no GPU), bare tree.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TuneColorTest.tscn

const TuneField = preload("res://src/debug/TuneField.gd")
const TMP_PATH := "user://tune_color_test_overrides.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_coalesce_and_type()
	_test_json_round_trip()
	_test_control_build_and_edit()

	print("\n=== TuneColorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TuneColorTest")
		get_tree().quit(1)
	else:
		print("[PASS] TuneColorTest")
		get_tree().quit(0)


func _test_coalesce_and_type() -> void:
	Tune.reset()
	var default := Color(0.1, 0.2, 0.3, 1.0)
	# No override → bind() returns the code default Color verbatim.
	_assert_color(Tune.bind("font.test_dark", default), default, "bind() returns the Color default when unset")
	# Type inference resolves to the color control kind.
	_assert_true(TuneField._control_kind(default, {}) == "color",
		"a Color default infers the 'color' control kind")
	# A scrub coalesces the override, still a Color on read.
	Tune.set_value("font.test_dark", Color(0.9, 0.8, 0.7, 1.0))
	_assert_color(Tune.bind("font.test_dark", default), Color(0.9, 0.8, 0.7, 1.0),
		"a scrubbed Color override coalesces over the default")


func _test_json_round_trip() -> void:
	Tune.reset()
	var default := Color.BLACK
	var picked := Color(0.25, 0.5, 0.75, 0.5)
	Tune.bind("font.test_stroke", default)  # register
	Tune.set_value("font.test_stroke", picked)
	_assert_true(Tune.commit(TMP_PATH), "committing a Color override writes the file")

	# Fresh slate, then reload from disk — the override must come back as a Color.
	Tune.reset()
	Tune.load_overrides(TMP_PATH)
	_assert_color(Tune.bind("font.test_stroke", default), picked,
		"a committed Color survives save→reload (JSON [r,g,b,a] → Color)")
	_assert_true(not Tune.is_dirty("font.test_stroke"),
		"the reloaded Color is not dirty (stored form matches committed baseline)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


func _test_control_build_and_edit() -> void:
	Tune.reset()
	var default := Color(0.2, 0.4, 0.6, 1.0)
	var control := TuneField.build_control("font.test_light", default)
	_assert_true(control is ColorPickerButton, "build_control makes a ColorPickerButton for a Color slug")
	if control is ColorPickerButton:
		add_child(control)
		_assert_color(control.color, default, "the control shows the coalesced Color")
		# Simulate a user pick → writes through to the slug.
		control.color = Color(0.11, 0.22, 0.33, 1.0)
		control.color_changed.emit(Color(0.11, 0.22, 0.33, 1.0))
		_assert_color(Tune.bind("font.test_light", default), Color(0.11, 0.22, 0.33, 1.0),
			"editing the ColorPickerButton writes through to the slug")
		control.free()


func _assert_color(actual: Variant, expected: Color, label: String) -> void:
	if actual is Color and actual.is_equal_approx(expected):
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
