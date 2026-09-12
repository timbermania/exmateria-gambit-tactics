extends Node
## Move-2 guard (bare tree, ADR-0068): FontDebugPanel's rows are built by the shared
## TuneField bound to `font.*` slugs, not ColorPickerButtons writing UIChar statics — so
## each carries the accent (pinnable) label AND writes through to its slug (which UIChar
## coalesces). Colors resolve to a ColorPickerButton (the new Color type support).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/FontPanelTuneFieldTest.tscn

const FontPanel = preload("res://src/debug/FontDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	var panel := FontPanel.new()
	add_child(panel)
	panel.setup(null)

	# A color row is a ColorPickerButton bound to its slug, with the accent label.
	var row := _find_row(panel, "Dark:")
	_assert_true(row != null, "a 'Dark:' color row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Dark row carries the TuneField accent label")
		var cp := _first_of(row, "ColorPickerButton") as ColorPickerButton
		_assert_true(cp != null, "the Dark row control is a ColorPickerButton")
		if cp:
			var picked := Color(0.1, 0.7, 0.2, 1.0)
			cp.color = picked
			cp.color_changed.emit(picked)
			# There are 3 "Dark:" rows (menu/stat/disabled) — the FIRST is menu.
			var got: Color = Tune.bind("font.menu_dark", Color.BLACK)
			_assert_true(got.is_equal_approx(picked),
				"scrubbing the first Dark row writes through to font.menu_dark")

	# The stroke-enabled row is a bool CheckBox bound to its slug.
	var srow := _find_row(panel, "Stroke")
	_assert_true(srow != null and _first_of(srow, "CheckBox") != null,
		"the Stroke row is a CheckBox (bool TuneField)")

	Tune.clear("font.menu_dark")
	panel.queue_free()

	print("\n=== FontPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FontPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] FontPanelTuneFieldTest")
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


func _first_of(row: Control, cls: String) -> Node:
	for child in row.get_children():
		if child.is_class(cls):
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
