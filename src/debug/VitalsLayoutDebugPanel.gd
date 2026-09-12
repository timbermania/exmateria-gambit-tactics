class_name VitalsLayoutDebugPanel
extends BaseDebugPanel
## Live position-tuning surface for the bottom-left vitals window ([UIUnitInfoWindow]).
##
## Every piece is a shared TuneField row bound to a `vitals.*` slug (ADR-0068 move 2):
## UIUnitInfoWindow OWNS its layout (it binds every knob in _ready), so this panel is just
## a VIEW (decision 12) — a dialed-in value persists + applies at boot in any scene. Vector2
## props are split into X/Y rows; the per-stat arrays (label_pos / bar_pos / num_row_y) into
## per-index rows. The window is only visible while a unit is inspected (click a unit, or the
## "Preview unit" button here); "Print Values" dumps the coalesced numbers to bake as defaults.

const TuneField = preload("res://src/debug/TuneField.gd")

const _POS := {"min": -200.0, "max": 400.0, "step": 0.5}
const _SCALE := {"min": 0.05, "max": 8.0, "step": 0.05}
const _BRIGHT := {"min": 0.0, "max": 16.0, "step": 0.1}
const _OFF := {"min": -100.0, "max": 100.0, "step": 0.5}
const _STAT_NAMES := ["Hp", "Mp", "Ct"]

var _window: UIUnitInfoWindow
var _field_inspect: FieldInspectController
var _unit_provider: Callable


func setup(window: UIUnitInfoWindow, field_inspect: FieldInspectController = null,
		unit_provider: Callable = Callable()) -> void:
	panel_title = "Vitals Layout"
	panel_category = Category.DESIGNER
	_window = window
	_field_inspect = field_inspect
	_unit_provider = unit_provider
	_build_ui()


## Re-point at a NEW window without rebuilding the UI — see `FormationDebugPanel.rebind`.
## `field_inspect` / `unit_provider` are NOT re-taken: the formation host has never passed
## them (it calls `setup(window)` with one argument), so a rebind that reset them to their
## defaults would be a change dressed as a no-op.
func rebind(window: UIUnitInfoWindow) -> void:
	_window = window


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(300, 0)
	add_child(root)

	if _window == null:
		add_label(root, "No vitals window bound.")
		return

	if _field_inspect != null:
		var btns := add_button_row(root)
		var show_btn := Button.new()
		show_btn.text = "Preview unit"
		show_btn.pressed.connect(_on_preview_pressed)
		btns.add_child(show_btn)
		var hide_btn := Button.new()
		hide_btn.text = "Hide"
		hide_btn.pressed.connect(func(): _field_inspect.dismiss())
		btns.add_child(hide_btn)

	var grid := create_collapsible_section(root, "Pixel grid (PPU)", true)
	add_label(grid, "px/texel = ppu*960/cam.size; integer = even")
	_scalar(grid, "pixels_per_unit", "pixels_per_unit", {"min": 0.005, "max": 0.5, "step": 0.00125})

	var portrait := create_collapsible_section(root, "Portrait")
	_scalar(portrait, "Show frame", "show_portrait_frame")
	_vec2(portrait, "Card pos", "portrait_pos", _POS)
	_vec2(portrait, "Frame size", "frame_size", {"min": 0.0, "max": 400.0, "step": 0.5})
	_vec2(portrait, "Inset", "portrait_offset", _OFF)
	_scalar(portrait, "Scale", "portrait_scale", _SCALE)

	var band := create_collapsible_section(root, "Band")
	_vec2(band, "Size", "band_size", {"min": 0.0, "max": 600.0, "step": 0.5})

	var lvexp := create_collapsible_section(root, "Lv. / Exp.")
	_vec2(lvexp, "Lv label", "lv_pos", _POS)
	_vec2(lvexp, "Lv num +", "lv_num_offset", _OFF)
	_vec2(lvexp, "Exp label", "exp_pos", _POS)
	_vec2(lvexp, "Exp num +", "exp_num_offset", _OFF)

	var labels := create_collapsible_section(root, "Stat labels")
	for i in 3:
		_vec2_el(labels, _STAT_NAMES[i] + " label", "label_pos", i, _POS)

	var bars := create_collapsible_section(root, "Bars")
	for i in 3:
		_vec2_el(bars, _STAT_NAMES[i] + " bar", "bar_pos", i, _POS)
	_vec2(bars, "Track size", "bar_track_size", {"min": 0.0, "max": 128.0, "step": 0.5})
	_vec2(bars, "Track inset", "bar_track_offset", {"min": -32.0, "max": 32.0, "step": 0.5})
	_scalar(bars, "Brightness", "bar_brightness", _BRIGHT)
	_scalar(bars, "Track brightness", "bar_track_brightness", _BRIGHT)

	var nums := create_collapsible_section(root, "Numbers (cur/max)")
	_scalar(nums, "Scale", "num_scale", _SCALE)
	_scalar(nums, "Divider x (cur)", "num_divider_x", _POS)
	for i in 3:
		_float_el(nums, _STAT_NAMES[i] + " row y", "num_row_y", i, _POS)
	_vec2(nums, "Slash +", "slash_offset", _OFF)
	_vec2(nums, "Max +", "max_offset", _OFF)

	add_separator(root)
	add_print_values_button(root, "Print Values (bake)")


# --- TuneField row builders (defaults read from the live window, matching the owner) ---

func _scalar(parent: Control, label_text: String, prop: String, hint: Dictionary = {}) -> void:
	TuneField.add(parent, label_text, "vitals." + prop, _window.get(prop), hint)


func _vec2(parent: Control, label_text: String, prop: String, hint: Dictionary = {}) -> void:
	var v: Vector2 = _window.get(prop)
	TuneField.add(parent, label_text + " X", "vitals.%s_x" % prop, v.x, hint)
	TuneField.add(parent, label_text + " Y", "vitals.%s_y" % prop, v.y, hint)


func _vec2_el(parent: Control, label_text: String, prop: String, idx: int, hint: Dictionary = {}) -> void:
	var v: Vector2 = _window.get(prop)[idx]
	TuneField.add(parent, label_text + " X", "vitals.%s_%d_x" % [prop, idx], v.x, hint)
	TuneField.add(parent, label_text + " Y", "vitals.%s_%d_y" % [prop, idx], v.y, hint)


func _float_el(parent: Control, label_text: String, prop: String, idx: int, hint: Dictionary = {}) -> void:
	TuneField.add(parent, label_text, "vitals.%s_%d" % [prop, idx], float(_window.get(prop)[idx]), hint)


func _on_preview_pressed() -> void:
	if _field_inspect == null or not _unit_provider.is_valid():
		return
	var units = _unit_provider.call()
	if units is Array and not units.is_empty():
		_field_inspect.inspect_unit(units[0])


func _on_print_values() -> void:
	if _window == null:
		return
	print("")
	print("# --- UIUnitInfoWindow layout (paste as @export defaults) ---")
	for p in ["portrait_pos", "frame_size", "portrait_offset", "band_size", "lv_pos",
			"lv_num_offset", "exp_pos", "exp_num_offset", "bar_track_size", "bar_track_offset",
			"slash_offset", "max_offset"]:
		print("%-16s = %s" % [p, _window.get(p)])
	for p in ["pixels_per_unit", "portrait_scale", "bar_brightness", "bar_track_brightness",
			"num_scale", "num_divider_x", "show_portrait_frame"]:
		print("%-16s = %s" % [p, _window.get(p)])
	print("%-16s = %s" % ["label_pos", _window.label_pos])
	print("%-16s = %s" % ["bar_pos", _window.bar_pos])
	print("%-16s = %s" % ["num_row_y", _window.num_row_y])
	print("# ----------------------------------------------------------")
	print("")
