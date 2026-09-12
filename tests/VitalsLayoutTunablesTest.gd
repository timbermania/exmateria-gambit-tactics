extends Node
## Move-2 guard (ADR-0068): the vitals-window layout knobs are OWNED by UIUnitInfoWindow
## — it binds every `vitals.*` slug in _ready (Vector2 split X/Y, per-stat arrays split by
## index) — so a committed override coalesces into the property at boot AND a scrub re-drives
## it, with no VitalsLayoutDebugPanel fan-out (decision 12).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/VitalsLayoutTunablesTest.tscn

const WindowScript = preload("res://src/ui3/UIUnitInfoWindow.gd")
const VitalsPanel = preload("res://src/debug/VitalsLayoutDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Tune.reset_overrides()
	# reset_overrides(), not reset(): the OVERRIDES go, the `_static_init` boot registration
	# stands. So every tunable this test's production scene reads — not just the ones it scrubs —
	# still coalesces onto a REGISTERED default rather than Nil (ADR-0068 R3), with
	# no central replay to call. This is the registration PRODUCTION runs on: nothing replays
	# there either (#535, ADR-0173). Plain reset() would clear the declarations and a
	# get_value() inside the spawned node would assert (R5).
	# Pre-spawn overrides must coalesce when the window binds in _ready.
	Tune.set_value("vitals.portrait_scale", 3.0)
	Tune.set_value("vitals.portrait_pos_x", 50.0)
	Tune.set_value("vitals.label_pos_1_y", 12.0)   # array element
	Tune.set_value("vitals.num_row_y_2", 44.0)     # PackedFloat32Array element

	var w = WindowScript.new()
	add_child(w)
	await get_tree().process_frame

	_assert_approx(w.portrait_scale, 3.0, "vitals.portrait_scale coalesces at spawn")
	_assert_approx(w.portrait_pos.x, 50.0, "vitals.portrait_pos_x coalesces into the Vector2.x")
	_assert_approx(w.label_pos[1].y, 12.0, "vitals.label_pos_1_y coalesces into the array element")
	_assert_approx(w.num_row_y[2], 44.0, "vitals.num_row_y_2 coalesces into the float-array element")

	# Live scrub re-drives the bound window.
	Tune.set_value("vitals.portrait_scale", 5.0)
	Tune.set_value("vitals.bar_pos_2_x", 99.0)
	await get_tree().process_frame
	_assert_approx(w.portrait_scale, 5.0, "scrubbing vitals.portrait_scale live-updates")
	_assert_approx(w.bar_pos[2].x, 99.0, "scrubbing vitals.bar_pos_2_x live-updates the array element")

	# Panel row writes the slug.
	var panel := VitalsPanel.new()
	add_child(panel)
	panel.setup(w)
	var row := _find_row(panel, "Scale X") # portrait "Card pos X"? use a unique label
	# Use the portrait Scale row (unique label "Scale") — find first "Scale".
	row = _find_row(panel, "Scale")
	_assert_true(row != null and _first_spinbox(row) != null, "the portrait Scale row is a TuneField SpinBox")
	if row:
		var sb := _first_spinbox(row)
		sb.value = 2.5
		sb.value_changed.emit(2.5)
		_assert_approx(float(Tune.bind("vitals.portrait_scale", 1.0)), 2.5,
			"scrubbing the Scale row writes through to vitals.portrait_scale")

	panel.queue_free()
	w.queue_free()
	print("\n=== VitalsLayoutTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] VitalsLayoutTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] VitalsLayoutTunablesTest")
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


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected): _passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
