extends Node
## Move-2 guard (ADR-0068): PSXDisplay.live_ui_par is now a facade over the Tune tunable
## "render.ui_pixel_aspect" (same shape as live_par) — bound in _ready, getter coalesces,
## setter routes through Tune, _apply_ui_par emits live_ui_par_changed. UIDisplayDebugPanel
## is a TuneField view. So an override applies at boot in any scene, not just via the panel.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/UiDisplayPanelTuneFieldTest.tscn

const UiPanel = preload("res://src/debug/UIDisplayDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const SLUG := "render.ui_pixel_aspect"

var _passed := 0
var _failed := 0
var _signal_count := 0
var _boot := 0.0


func _ready() -> void:
	_boot = PSXDisplay.live_ui_par
	PSXDisplay.live_ui_par_changed.connect(func(_v): _signal_count += 1)

	# Owner: PSXDisplay bound the slug at boot with the code default.
	_assert_true(is_equal_approx(Tune.default_of(SLUG), 1.0),
		"PSXDisplay registered render.ui_pixel_aspect with the 1.0 default")

	# A Tune override drives the facade + emits the signal once.
	_signal_count = 0
	Tune.set_value(SLUG, 1.5)
	_assert_true(is_equal_approx(PSXDisplay.live_ui_par, 1.5),
		"a render.ui_pixel_aspect override drives PSXDisplay.live_ui_par")
	_assert_true(_signal_count == 1, "the override emits live_ui_par_changed once")

	# The setter routes through Tune (getter reflects it).
	PSXDisplay.live_ui_par = 1.2
	_assert_true(is_equal_approx(float(Tune.bind(SLUG, 1.0)), 1.2),
		"setting live_ui_par writes the slug")

	# Panel row is TuneField-built and writes the slug.
	var panel := UiPanel.new()
	add_child(panel)
	panel.setup()
	var row := _find_row(panel, "PSX UI PAR (mesh-width)")
	_assert_true(row != null and _first_spinbox(row) != null, "the UI PAR row is a TuneField SpinBox")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the UI PAR row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		sb.value = 1.75
		sb.value_changed.emit(1.75)
		_assert_true(is_equal_approx(float(Tune.bind(SLUG, 1.0)), 1.75),
			"scrubbing the row writes through to the slug")

	Tune.clear(SLUG)
	PSXDisplay.live_ui_par = _boot  # restore shared autoload state
	panel.queue_free()

	print("\n=== UiDisplayPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UiDisplayPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] UiDisplayPanelTuneFieldTest")
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
