extends Node
## Move-2 guard (ADR-0068): ScenarioWeatherDebugPanel's knob rows are built by the
## shared TuneField bound to `weather.*` slugs, not SpinBoxes writing onto the
## ScenarioWeather node — so each carries the accent (pinnable) label AND writes
## through to its slug (which ScenarioWeather coalesces). Built in a bare tree;
## setup() takes an (unused for the rows) vm arg, so null is fine here.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioWeatherPanelTuneFieldTest.tscn

const WeatherPanel = preload("res://src/debug/ScenarioWeatherDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const WeatherScript = preload("res://src/scenarios/ScenarioWeather.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	# The rows are now pure VIEWS — the owner must re-establish its binds after reset
	# (ADR-0068: register_tunables() is the static replay _static_init also calls at class load),
	# or each row renders as an unsupported read-only field with no SpinBox.
	WeatherScript.register_tunables()
	var panel := WeatherPanel.new()
	add_child(panel)
	panel.setup(null)

	var row := _find_row(panel, "Width (PSX px)")
	_assert_true(row != null, "the 'Width (PSX px)' row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Width row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Width row has a SpinBox control")
		if sb:
			sb.value = 4.2
			sb.value_changed.emit(4.2)
			_assert_true(is_equal_approx(float(Tune.bind("weather.drop_width_px", 1.4)), 4.2),
				"scrubbing the row writes through to weather.drop_width_px")
	Tune.clear("weather.drop_width_px")

	panel.queue_free()

	print("\n=== ScenarioWeatherPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioWeatherPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioWeatherPanelTuneFieldTest")
		get_tree().quit(0)


func _find_row(node: Node, label_text: String) -> Control:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var lbl := child.get_child(0) as Label
			if lbl and lbl.text == label_text:
				return child
		var found := _find_row(child, label_text)
		if found:
			return found
	return null


func _first_spinbox(row: Control) -> SpinBox:
	for child in row.get_children():
		if child is SpinBox:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
