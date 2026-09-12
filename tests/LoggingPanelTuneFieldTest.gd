extends Node
## Move-2 guard (ADR-0068): LoggingDebugPanel's flag rows are built by the shared
## TuneField, not hand-rolled CheckBoxes — so each carries the accent (pinnable) label
## AND writes through to its `debug.*` slug (which DebugConfig coalesces). Catches a
## revert of the in-place TuneField migration. Built in a bare tree.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/LoggingPanelTuneFieldTest.tscn

const LoggingPanel = preload("res://src/debug/LoggingDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	var panel := LoggingPanel.new()
	add_child(panel)
	panel.setup()

	# The row for each flag is a TuneField CheckBox: an accent label + write-through.
	var row := _find_checkbox_row(panel, "Map Debug")
	_assert_true(row != null, "the 'Map Debug' row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Map Debug row carries the TuneField accent label")
		var cb := _first_checkbox(row)
		_assert_true(cb != null, "the Map Debug row has a CheckBox control")
		if cb:
			cb.button_pressed = true
			cb.toggled.emit(true)
			_assert_true(bool(Tune.bind("debug.map_debug_enabled", false)),
				"toggling the row writes through to debug.map_debug_enabled")
			_assert_true(DebugConfig.map_debug_enabled,
				"and DebugConfig.map_debug_enabled coalesces the same value")
	Tune.clear("debug.map_debug_enabled")

	panel.queue_free()

	print("\n=== LoggingPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] LoggingPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] LoggingPanelTuneFieldTest")
		get_tree().quit(0)


## Find the TuneField row (HBoxContainer) whose first child Label has `text`.
func _find_checkbox_row(node: Node, label_text: String) -> Control:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var lbl := child.get_child(0) as Label
			if lbl and lbl.text == label_text:
				return child
		var found := _find_checkbox_row(child, label_text)
		if found:
			return found
	return null


func _first_checkbox(row: Control) -> CheckBox:
	for child in row.get_children():
		if child is CheckBox:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
