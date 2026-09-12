extends Control
## A Godot-editor-style "scrubby" number field for the Effect Studio inspector. The field IS
## the slider — no separate track:
##   * drag LEFT/RIGHT to adjust (value += pixels · step, with a HSIZE cursor);
##   * click (no drag) to type an exact value;
##   * scroll wheel to nudge by one step;
##   * Shift = coarse (×10), Ctrl = fine (×0.1).
## It mirrors the SpinBox surface the inspector already drove (`value` / `value_changed` /
## `min_value` / `max_value` / `step` / `suffix` / `set_value_no_signal`), so it drops in
## wherever a numeric cell was a SpinBox. Web/WASM-safe (pure Control), no `class_name`
## (ADR-0004). EditorSpinSlider (the engine's own version) is editor-only and unavailable in
## a running scene, so this replicates its feel.

signal value_changed(value: float)

# SpinBox-compatible knobs (plain vars — the inspector sets these before seeding).
var min_value: float = 0.0
var max_value: float = 100.0
var step: float = 1.0
var suffix: String = ""
var prefix: String = ""
var editable: bool = true
# Drag speed in value-units per pixel, DECOUPLED from `step` (which governs typing/scroll
# precision). 0 = fall back to `step` (so a plain integer field scrubs 1/px). The inspector
# sets a comfortable per-unit value (~1°/px, ~0.1 tiles/px) so fine steps don't scrub glacially.
var scrub_sensitivity: float = 0.0

# Pixels-to-value: one pixel of drag moves the value by `step`. Shift/Ctrl scale this.
const _COARSE := 10.0
const _FINE := 0.1
const _DRAG_THRESHOLD := 3.0

var _value: float = 0.0
var _display: Label
var _edit: LineEdit
var _bg: StyleBoxFlat
var _dragging := false
var _pressed := false
var _moved := 0.0


var value: float:
	get:
		return _value
	set(v):
		_apply(v, true)


func _ready() -> void:
	custom_minimum_size = Vector2(96, 24)
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	clip_contents = true

	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0.14, 0.16, 0.20)
	_bg.border_color = Color(0.28, 0.32, 0.40)
	_bg.set_border_width_all(1)
	_bg.set_corner_radius_all(3)
	_bg.set_content_margin_all(3)

	_display = Label.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.modulate = Color(0.90, 0.93, 0.98)
	add_child(_display)

	_edit = LineEdit.new()
	_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.select_all_on_focus = true
	_edit.visible = false
	_edit.text_submitted.connect(func(t): commit_text(t))
	_edit.focus_exited.connect(func(): if _edit.visible: commit_text(_edit.text))
	add_child(_edit)

	_refresh_text()


func _draw() -> void:
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))


## SpinBox-compatible seed that fans no edit.
func set_value_no_signal(v: float) -> void:
	_apply(v, false)


func _apply(v: float, emit: bool) -> void:
	var snapped: float = _snap(v)
	var clamped: float = clampf(snapped, min_value, max_value)
	var changed: bool = not is_equal_approx(clamped, _value)
	_value = clamped
	_refresh_text()
	if emit and changed:
		value_changed.emit(_value)


func _snap(v: float) -> float:
	if step <= 0.0:
		return v
	return round(v / step) * step


func _decimals() -> int:
	if step >= 1.0 or step <= 0.0:
		return 0
	return int(ceil(-log(step) / log(10.0) - 0.0001))


func _refresh_text() -> void:
	if _display == null:
		return
	var d: int = _decimals()
	_display.text = "%s%s%s" % [prefix, String.num(_value, d).pad_decimals(d), suffix]


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pressed = true
					_dragging = false
					_moved = 0.0
					accept_event()
				else:
					if _pressed and not _dragging:
						_begin_edit()   # a click (no drag) → type
					_pressed = false
					_dragging = false
					accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_apply(_value + _step_for(event.shift_pressed, event.ctrl_pressed), true)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_apply(_value - _step_for(event.shift_pressed, event.ctrl_pressed), true)
					accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_moved += absf(event.relative.x)
		if _moved > _DRAG_THRESHOLD:
			_dragging = true
		if _dragging and event.relative.x != 0.0:
			var base: float = scrub_sensitivity if scrub_sensitivity > 0.0 else step
			_apply(_value + event.relative.x * _scaled(base, event.shift_pressed, event.ctrl_pressed), true)
		accept_event()


# The wheel nudges by one `step` (modified); drag uses scrub_sensitivity via _scaled.
func _step_for(shift: bool, ctrl: bool) -> float:
	return _scaled(step, shift, ctrl)


func _scaled(base: float, shift: bool, ctrl: bool) -> float:
	if shift:
		base *= _COARSE
	if ctrl:
		base *= _FINE
	return base


func _begin_edit() -> void:
	_edit.text = String.num(_value, _decimals())
	_edit.visible = true
	_edit.grab_focus()
	_edit.select_all()


## Parse and commit typed text (accepts a bare number; ignores junk), then close the field.
func commit_text(t: String) -> void:
	var s := t.strip_edges()
	if s.is_valid_float():
		_apply(s.to_float(), true)
	elif s.is_valid_int():
		_apply(float(s.to_int()), true)
	_edit.visible = false


## Test seam: is the typing field open?
func is_editing() -> bool:
	return _edit != null and _edit.visible
