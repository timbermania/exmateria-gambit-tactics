extends Node
## Move-2 guard (ADR-0068): ScenarioDialogueBoxDebugPanel's rows are built by the
## shared TuneField bound to `dialbox.*` slugs, not SpinBoxes/CheckBoxes writing onto
## _vm.box_pool — so each carries the accent (pinnable) label AND writes through to its
## slug (which the pool coalesces). Built in a bare tree; setup() takes an (unused) vm.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioDialogueBoxPanelTuneFieldTest.tscn

const BoxPanel = preload("res://src/debug/ScenarioDialogueBoxDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const BoxPoolScript = preload("res://src/scenarios/ScenarioDialogueBoxPool.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	Tune.reset()
	# The rows are now pure VIEWS — the owner must re-establish its binds after reset
	# (ADR-0068: register_tunables() is the static replay _static_init also calls at class load),
	# or each row renders as an unsupported read-only field with no control.
	BoxPoolScript.register_tunables()
	var panel := BoxPanel.new()
	add_child(panel)
	panel.setup(null)

	var row := _find_row(panel, "Size scale")
	_assert_true(row != null, "the 'Size scale' row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Size scale row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Size scale row has a SpinBox control")
		if sb:
			sb.value = 2.1
			sb.value_changed.emit(2.1)
			_assert_true(is_equal_approx(float(Tune.bind("dialbox.box_size_scale", 1.35)), 2.1),
				"scrubbing the row writes through to dialbox.box_size_scale")
	Tune.clear("dialbox.box_size_scale")

	# The Vector2 offset is split into two float-slug rows.
	var y_row := _find_row(panel, "Y (down+)")
	_assert_true(y_row != null and _first_spinbox(y_row) != null,
		"box_offset_px is split into an X and a Y TuneField row")

	panel.queue_free()

	print("\n=== ScenarioDialogueBoxPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioDialogueBoxPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDialogueBoxPanelTuneFieldTest")
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
