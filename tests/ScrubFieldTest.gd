extends Node
## TDD guard for ScrubField — the Godot-editor-style "scrubby" number field the Effect
## Studio inspector uses instead of a plain SpinBox. The field IS the slider: drag left/right
## to adjust, click to type an exact value, scroll to nudge, Shift = coarse (×10), Ctrl =
## fine (×0.1). It exposes the SAME surface the inspector already drove on SpinBox
## (`value` / `value_changed` / `min_value` / `max_value` / `step` / `suffix` /
## `set_value_no_signal`) so it is a drop-in.
##
## The interactions are tested by feeding synthetic InputEvents straight into `_gui_input`,
## and the value math by the public `value` property — no real mouse needed.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScrubFieldTest.tscn

const ScrubField = preload("res://src/effects/studio/ScrubField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_value_set_get_and_signal_on_change()
	_test_seed_no_signal_and_no_signal_on_unchanged()
	_test_clamp_and_snap_to_step()
	_test_drag_adjusts_by_pixels_times_step()
	_test_shift_is_coarse_ctrl_is_fine()
	_test_scrub_sensitivity_decouples_drag_speed_from_step()
	_test_scroll_wheel_steps()
	_test_click_without_drag_opens_typing_and_commit_sets_value()

	print("\n=== ScrubFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScrubFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScrubFieldTest")
		get_tree().quit(0)


func _new(min_v: float, max_v: float, step: float) -> Control:
	var sf = ScrubField.new()
	add_child(sf)
	sf.min_value = min_v
	sf.max_value = max_v
	sf.step = step
	return sf


func _test_value_set_get_and_signal_on_change() -> void:
	var sf = _new(-1000, 1000, 1.0)
	var seen: Array = []
	sf.value_changed.connect(func(v): seen.append(v))
	sf.value = 42.0
	_assert_close(sf.value, 42.0, "value round-trips through the property")
	_assert_eq(seen.size(), 1, "a value change emits value_changed once")
	_assert_close(seen[0], 42.0, "the signal carries the new value")


func _test_seed_no_signal_and_no_signal_on_unchanged() -> void:
	var sf = _new(0, 255, 1.0)
	var seen: Array = []
	sf.value_changed.connect(func(v): seen.append(v))
	sf.set_value_no_signal(40.0)
	_assert_close(sf.value, 40.0, "set_value_no_signal seeds the value")
	_assert_eq(seen.size(), 0, "seeding fires no signal")
	sf.value = 40.0
	_assert_eq(seen.size(), 0, "re-setting the same value fires no signal")


func _test_clamp_and_snap_to_step() -> void:
	var sf = _new(0, 10, 1.0)
	sf.value = 999.0
	_assert_close(sf.value, 10.0, "value clamps to max_value")
	sf.value = -5.0
	_assert_close(sf.value, 0.0, "value clamps to min_value")
	var deg = _new(-360, 360, 0.1)
	deg.value = 12.34
	_assert_close(deg.value, 12.3, "value snaps to the step grid (0.1)")


func _test_drag_adjusts_by_pixels_times_step() -> void:
	var sf = _new(-1000, 1000, 0.1)
	sf.set_value_no_signal(0.0)
	_press(sf, Vector2(10, 5))
	_drag(sf, Vector2(20, 0))   # +20px at step 0.1 → +2.0
	_assert_close(sf.value, 2.0, "a +20px drag at step 0.1 adds 2.0")
	_drag(sf, Vector2(-5, 0))   # -5px → -0.5
	_assert_close(sf.value, 1.5, "a -5px drag subtracts 0.5")
	_release(sf)
	_assert_false(sf.is_editing(), "a drag does not open the typing field")


func _test_shift_is_coarse_ctrl_is_fine() -> void:
	var sf = _new(-10000, 10000, 0.1)
	sf.set_value_no_signal(0.0)
	_press(sf, Vector2(0, 0))
	_drag(sf, Vector2(10, 0), true, false)   # Shift → ×10 → +10px·0.1·10 = +10.0
	_assert_close(sf.value, 10.0, "Shift makes the drag coarse (×10)")
	_release(sf)
	sf.set_value_no_signal(0.0)
	_press(sf, Vector2(0, 0))
	_drag(sf, Vector2(10, 0), false, true)   # Ctrl → ×0.1 → +10px·0.1·0.1 = +0.1
	_assert_close(sf.value, 0.1, "Ctrl makes the drag fine (×0.1)")


## Drag speed is a separate knob from the type/scroll step: a fine-grained field (0.1° step)
## can still scrub fast (1°/px) without changing how precise typing/scroll are. The wheel keeps
## stepping by `step`, unaffected by scrub_sensitivity.
func _test_scrub_sensitivity_decouples_drag_speed_from_step() -> void:
	var sf = _new(-10000, 10000, 0.1)
	sf.scrub_sensitivity = 1.0   # 1.0 value-unit per pixel (not step)
	sf.set_value_no_signal(0.0)
	_press(sf, Vector2(0, 0))
	_drag(sf, Vector2(20, 0))    # +20px · 1.0/px = +20.0 (NOT 20·0.1)
	_assert_close(sf.value, 20.0, "drag uses scrub_sensitivity, not step")
	_release(sf)
	_wheel(sf, false)            # wheel still steps by `step` = 0.1
	_assert_close(sf.value, 19.9, "the scroll wheel still nudges by one step")


func _test_scroll_wheel_steps() -> void:
	var sf = _new(-100, 100, 0.5)
	sf.set_value_no_signal(1.0)
	_wheel(sf, true)
	_assert_close(sf.value, 1.5, "scroll up adds one step")
	_wheel(sf, false)
	_wheel(sf, false)
	_assert_close(sf.value, 0.5, "scroll down subtracts one step each")


func _test_click_without_drag_opens_typing_and_commit_sets_value() -> void:
	var sf = _new(-1000, 1000, 0.1)
	var seen: Array = []
	sf.value_changed.connect(func(v): seen.append(v))
	sf.set_value_no_signal(5.0)
	_press(sf, Vector2(10, 5))
	_release(sf)   # no motion between press and release → a click
	_assert_true(sf.is_editing(), "a click (no drag) opens the typing field")
	sf.commit_text("90")
	_assert_close(sf.value, 90.0, "typing 90 and committing sets the value")
	_assert_eq(seen.size(), 1, "the typed commit fans one change")
	_assert_false(sf.is_editing(), "committing closes the typing field")


# --- synthetic input helpers ------------------------------------------------

func _press(sf, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	sf._gui_input(e)


func _drag(sf, rel: Vector2, shift := false, ctrl := false) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	sf._gui_input(e)


func _release(sf) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	sf._gui_input(e)


func _wheel(sf, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	sf._gui_input(e)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_close(actual: float, expected: float, label: String) -> void:
	if abs(actual - expected) < 0.001:
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


func _assert_false(cond: bool, label: String) -> void:
	if not cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected false" % label)
