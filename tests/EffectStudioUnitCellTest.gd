extends Node
## TDD guard for the UNIT-tagged `int` cell in EffectKeyframeInspector — the symmetric
## raw↔human affine that lets the camera inspector author in degrees while the value that
## crosses the #255 choke point stays RAW. A cell carrying `unit: CameraUnits.ANGLE_DEG`
## SEEDS the SpinBox with the human value (raw 1024 → 90.0°) and FANS the raw back
## (typed 45.0° → raw 512) through the ONE mutate callback. Storage never sees degrees.
##
## This is the F1 `int` cell (EffectStudioEditorKitTest) extended with a `scale` term on
## top of the existing `bias` affine — a bias-only cell (no unit) must still behave exactly
## as before, so those cases are re-asserted here as a regression fence.
##
## Seam under test (pre-agreed): EffectKeyframeInspector `int` cell, driven via int_widgets().
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioUnitCellTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_angle_cell_seeds_degrees()
	_test_angle_cell_fans_raw()
	_test_angle_cell_step_and_suffix()
	_test_zoom_cell_seeds_and_fans()
	_test_no_tell_when_value_is_representable()
	_test_tell_hint_shows_achieved_when_unrepresentable()
	_test_plain_int_cell_unchanged()

	print("\n=== EffectStudioUnitCellTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioUnitCellTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioUnitCellTest")
		get_tree().quit(0)


## A cell seeded with raw 1024 and unit ANGLE_DEG shows 90.0° in its SpinBox — the author
## reads degrees, not the 4096-circle raw.
func _test_angle_cell_seeds_degrees() -> void:
	var insp = _show([_unit_field("Yaw", "s16", 1024, _ref("angle_y"), CameraUnits.ANGLE_DEG)], [])
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_close(sb.value, 90.0, "raw 1024 seeds 90.0° in the spinbox")


## Typing 45.0° fans raw 512 (not 45) through the mutate callback — the choke point stays raw.
func _test_angle_cell_fans_raw() -> void:
	var mutations: Array = []
	var ref := _ref("angle_y")
	var insp = _show([_unit_field("Yaw", "s16", 1024, ref, CameraUnits.ANGLE_DEG)], mutations)
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	sb.value = 45.0
	_assert_eq(mutations.size(), 1, "changing the degree spinbox fans one edit")
	if mutations.is_empty():
		return
	_assert_true(mutations[0][0] == ref, "the edit carries the cell's field_ref")
	_assert_eq(mutations[0][1], 512, "45.0° fans RAW 512, not 45")


## The degree cell steps by 0.1° and shows the ° suffix (1-decimal precision, the design).
func _test_angle_cell_step_and_suffix() -> void:
	var insp = _show([_unit_field("Yaw", "s16", 0, _ref("angle_y"), CameraUnits.ANGLE_DEG)], [])
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_close(sb.step, 0.1, "degree cell steps by 0.1°")
	_assert_eq(sb.suffix, "°", "degree cell shows the ° suffix")


## Zoom uses the same affine at a different scale: raw 8192 → 2.0×, typed 0.5× → raw 2048.
func _test_zoom_cell_seeds_and_fans() -> void:
	var mutations: Array = []
	var ref := _ref("zoom")
	var insp = _show([_unit_field("Zoom", "s16", 8192, ref, CameraUnits.ZOOM_X)], mutations)
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_close(sb.value, 2.0, "raw 8192 seeds 2.0×")
	sb.value = 0.5
	_assert_eq(mutations[0][1], 2048, "0.5× fans raw 2048")


## A seeded value that round-trips cleanly (raw 28 = exactly 1.00 tiles) shows no tell.
func _test_no_tell_when_value_is_representable() -> void:
	var insp = _show([_unit_field("X", "s16", 28, _ref("position_x"), CameraUnits.POS_TILES)], [])
	var hint: Label = insp.unit_hints()[0]
	_assert_eq(hint.text, "", "a representable value shows no quantization tell")


## Typing a tile value the 0.01 grid can't hit (1.01 → raw 28 → 1.00) surfaces an inline
## tell reporting the value the author will ACTUALLY get — no silent rounding.
func _test_tell_hint_shows_achieved_when_unrepresentable() -> void:
	var insp = _show([_unit_field("X", "s16", 0, _ref("position_x"), CameraUnits.POS_TILES)], [])
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	var hint: Label = insp.unit_hints()[0]
	sb.value = 1.01
	_assert_true(hint.text.contains("1.00"), "the tell reports the achieved 1.00 tiles (got '%s')" % hint.text)


## Regression fence: an int cell with NO unit behaves exactly as the F1 kit did — integer
## step, raw value seeded and fanned verbatim.
func _test_plain_int_cell_unchanged() -> void:
	var mutations: Array = []
	var ref := _ref("param")
	var insp = _show([_plain_int("Radius", "u8", 40, ref)], mutations)
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	_assert_eq(int(sb.value), 40, "plain int seeds the raw verbatim")
	_assert_eq(sb.step, 1.0, "plain int steps by 1")
	sb.value = 200
	_assert_eq(mutations[0][1], 200, "plain int fans the raw verbatim")


# --- fixtures --------------------------------------------------------------

func _show(fields: Array, sink: Array):
	var insp = Inspector.new()
	add_child(insp)
	insp.show_target(Target.span("unit#0"), [], [{"title": "Cam", "fields": fields}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): sink.append([ref, raw]))
	return insp


func _ref(field: String) -> Dictionary:
	return {"channel": "camera", "context": "for_each", "ordinal": 0, "field": field}


func _unit_field(name: String, type: String, value: int, ref: Dictionary, unit: Dictionary) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "int", "type": type, "value": value,
		"field_ref": ref, "unit": unit}


func _plain_int(name: String, type: String, value: int, ref: Dictionary) -> Dictionary:
	return {"name": name, "shape": "edit", "editor": "int", "type": type, "value": value, "field_ref": ref}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_close(actual: float, expected: float, label: String) -> void:
	if abs(actual - expected) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
