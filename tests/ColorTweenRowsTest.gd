extends Node
## TDD guard for ColorTweenRows (ADR-0087 dec. 14) — the ONE builder both colour
## projectors (palette + screen) assemble their harmonized rows from. Sharing the builder is
## what makes drift impossible: the row names, editors, choice lists, and honest-tell labels
## exist in exactly one place, and each lane feeds in only its per-lane descriptor facts
## (address/field_refs, the ×2 flag, its derived enabled state, its seed).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ColorTweenRowsTest.tscn

const Rows = preload("res://src/effects/studio/ColorTweenRows.gd")
const Labels = preload("res://src/effects/studio/ColorModeLabels.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_enabled_row_is_the_harmonized_choice()
	_test_delta_row_label_tells_the_engine_doubling()
	_test_blend_mode_row_single_sources_the_labels()
	_test_duration_row_is_the_boundary_int()
	_test_tint_row_carries_refs_and_optional_seed()

	print("\n=== ColorTweenRowsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColorTweenRowsTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorTweenRowsTest")
		get_tree().quit(0)


func _test_enabled_row_is_the_harmonized_choice() -> void:
	var ref := {"channel": "screen", "field": "enabled"}
	var on := Rows.enabled_row(true, ref)
	_assert_eq(on.get("name", ""), "Enabled", "the row is named Enabled")
	_assert_eq(on.get("editor", ""), "choice", "…a choice toggle")
	_assert_eq(int(on.get("value", -1)), 1, "…seeded from the lane's derived state")
	_assert_true(on.get("choices", []) == ["Disabled", "Enabled"], "…with the one choice list")
	_assert_true(on.get("field_ref", {}) == ref, "…addressing the lane's enabled field")
	_assert_eq(int(Rows.enabled_row(false, ref).get("value", -1)), 0, "disabled seeds 0")


func _test_delta_row_label_tells_the_engine_doubling() -> void:
	var refs := {"r": {"field": "start_r"}, "g": {"field": "start_g"}, "b": {"field": "start_b"}}
	var x2 := Rows.delta_row(Vector3i(1, 2, 3), refs, true)
	_assert_eq(x2.get("name", ""), "Tint Δ (applied ×2)", "the ×2 lane tells the doubling in the label")
	_assert_eq(Rows.delta_row(Vector3i.ZERO, refs, false).get("name", ""), "Tint Δ",
		"the 1× lane shows the plain Δ label")
	_assert_eq(x2.get("editor", ""), "signed_rgb", "…a signed_rgb editor")
	_assert_eq(x2.get("seed", Vector3i.ZERO), Vector3i(1, 2, 3), "…seeded with the raw bytes")
	_assert_true(x2.get("field_refs", {}) == refs, "…carrying the lane's byte addresses")


func _test_blend_mode_row_single_sources_the_labels() -> void:
	var ref := {"channel": "palette", "field": "blend_mode"}
	var row := Rows.blend_mode_row(5, ref)
	_assert_eq(row.get("name", ""), "Blend mode", "the row is named Blend mode")
	_assert_eq(row.get("editor", ""), "enum", "…a value-carrying enum")
	_assert_eq(int(row.get("value", -1)), 5, "…seeded to the current mode")
	_assert_true(row.get("choices", []) == Labels.choices(),
		"…offering exactly the shared ColorModeLabels choices")


func _test_duration_row_is_the_boundary_int() -> void:
	var ref := {"channel": "screen", "field": "duration"}
	var row := Rows.duration_row(24, ref)
	_assert_eq(row.get("name", ""), "Duration", "the row is named Duration")
	_assert_eq(row.get("editor", ""), "int", "…an int cell")
	_assert_eq(int(row.get("min", -1)), 1, "…floored at 1 frame")
	_assert_eq(row.get("type", ""), "u16", "…with the u16 range")
	_assert_eq(int(row.get("value", -1)), 24, "…seeded to the duration")


func _test_tint_row_carries_refs_and_optional_seed() -> void:
	var refs := {"r": {"field": "r"}, "g": {"field": "g"}, "b": {"field": "b"}}
	var seeded := Rows.tint_row("Tint", refs, Color(0.1, 0.2, 0.3))
	_assert_eq(seeded.get("editor", ""), "target_color", "the tint row is the result-picker")
	_assert_eq(seeded.get("seed", Color.BLACK), Color(0.1, 0.2, 0.3),
		"a lane that knows its seed carries it")
	var unseeded := Rows.tint_row("Color", refs)
	_assert_true(not unseeded.has("seed"),
		"a lane whose seed is runtime-injected (screen) carries none")
	_assert_eq(unseeded.get("name", ""), "Color", "the lane names its own tint row")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
