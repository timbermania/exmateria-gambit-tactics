class_name UIDropdown
extends Node3D
## Dropdown selector component for UI.
##
## Click to expand and show options in a list below.
## Click an option or outside to collapse.
## Uses UIFrame + UIText + UIClickableField.

## Emitted when an option is selected
signal option_selected(index: int, value: String)

## Emitted when dropdown is opened/closed
signal toggled(is_open: bool)

## Available options
@export var options: Array[String] = []:
	set(value):
		options = value
		_update_display()

## Currently selected option index
@export var selected_index: int = 0:
	set(value):
		if selected_index == value:
			return
		selected_index = clampi(value, 0, options.size() - 1) if options.size() > 0 else -1
		_update_display()

## Width of the dropdown in virtual pixels
@export var width: float = 100.0:
	set(value):
		width = value
		_update_layout()

## Height of each option row in virtual pixels
@export var row_height: float = 16.0:
	set(value):
		if row_height == value:
			return
		row_height = value
		_update_layout()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_update_pixels_per_unit()

## Text palette for display text
@export var text_palette: int = 0:
	set(value):
		if text_palette == value:
			return
		text_palette = value
		_update_text_palette()

## Space width for text (-1.0 uses default)
@export var space_width: float = -1.0:
	set(value):
		if space_width == value:
			return
		space_width = value
		_update_space_width()

## Text scale multiplier
@export var text_scale: float = 1.0:
	set(value):
		if text_scale == value:
			return
		text_scale = value
		_update_text_scale()

## Text horizontal offset in virtual pixels
@export var text_offset_x: float = 6.0:
	set(value):
		if text_offset_x == value:
			return
		text_offset_x = value
		_update_layout()

## Text vertical offset in virtual pixels
@export var text_offset_y: float = 6.0:
	set(value):
		if text_offset_y == value:
			return
		text_offset_y = value
		_update_layout()

## Maximum number of options visible when dropdown is open
@export var max_visible_options: int = 20:
	set(value):
		if max_visible_options == value:
			return
		max_visible_options = value
		if _option_list:
			_option_list.visible_count = max_visible_options
		_update_list_size()

## Render priority for frame and text
@export var render_priority: int = 0:
	set(value):
		if render_priority == value:
			return
		render_priority = value
		_update_render_priorities()

## Whether to show the frame background
@export var show_frame: bool = true:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		if _frame:
			_frame.visible = show_frame

## Whether the dropdown is disabled (cannot be clicked)
@export var disabled: bool = false:
	set(value):
		if disabled == value:
			return
		disabled = value
		_update_disabled_state()

## Whether dropdown is expanded
var is_open: bool = false

## Tracks the currently open dropdown so only one can be open at a time
static var _currently_open: UIDropdown = null


## Close whichever dropdown is currently open (if any).
## Call this from other UI systems when a non-dropdown action occurs.
static func close_any_open() -> void:
	if _currently_open and is_instance_valid(_currently_open):
		_currently_open._close()

# Visual components
var _frame: UIFrame
var _text: UIText
var _click_area: UIClickableField
var _option_list: UIScrollableList
var _list_frame: UIFrame
var _display_override: String = ""


func _ready() -> void:
	_setup_components()
	_update_layout()
	_update_display()


func _setup_components() -> void:
	# Main frame (always visible)
	_frame = UIFrame.new()
	_frame.pixels_per_unit = pixels_per_unit
	_frame.render_priority = render_priority
	_frame.visible = show_frame
	add_child(_frame)

	# Display text (shows selected option)
	_text = UIText.new()
	_text.pixels_per_unit = pixels_per_unit
	_text.render_priority = render_priority
	_text.position.z = 0.01
	_text.scale = Vector3(text_scale, text_scale, 1.0)
	_text.set_palette(text_palette)
	if space_width >= 0.0:
		_text.space_width = space_width
	add_child(_text)

	# Click area to toggle dropdown
	_click_area = UIClickableField.new()
	_click_area.field_type = "dropdown"
	_click_area.clicked.connect(_on_main_clicked)
	add_child(_click_area)

	# Option list container (hidden by default)
	_list_frame = UIFrame.new()
	_list_frame.pixels_per_unit = pixels_per_unit
	_list_frame.render_priority = render_priority
	_list_frame.visible = false
	add_child(_list_frame)

	_option_list = UIScrollableList.new()
	_option_list.pixels_per_unit = pixels_per_unit
	_option_list.visible_count = max_visible_options
	_option_list.item_spacing = 1.0
	_option_list.show_scroll_indicators = false  # Avoid stray "v" character rendering issues
	_option_list.item_selected.connect(_on_option_selected)
	_option_list.cancelled.connect(_close)
	_list_frame.add_child(_option_list)


func _update_layout() -> void:
	if not _frame:
		return

	var padding = 4.0
	var arrow_space = 12.0  # Space for dropdown arrow

	# Main frame size
	_frame.frame_size = Vector2(width, row_height + padding * 2)

	# Text position (inside frame with offset)
	if _text:
		_text.position = Vector3(
			text_offset_x * pixels_per_unit,
			-text_offset_y * pixels_per_unit,
			0.01
		)
		_text.max_width = width - padding * 2 - arrow_space

	# Click area covers the main frame
	if _click_area:
		_click_area.configure(
			"dropdown", 0,
			Rect2(0, 0, width, row_height + padding * 2),
			pixels_per_unit, false
		)

	# List frame positioned below main frame
	if _list_frame:
		var frame_height = _frame.frame_size.y
		_list_frame.position.y = -frame_height * pixels_per_unit

	_update_list_size()


func _update_list_size() -> void:
	if not _list_frame or not _option_list:
		return

	var visible_options = mini(options.size(), _option_list.visible_count)
	var list_height = visible_options * (row_height + _option_list.item_spacing)
	var padding = 4.0

	_list_frame.frame_size = Vector2(width, list_height + padding * 2)

	# Position option list inside frame
	_option_list.position = Vector3(
		padding * pixels_per_unit,
		-padding * pixels_per_unit,
		0.01
	)


func _update_display() -> void:
	if not _text:
		return

	if not _display_override.is_empty():
		_text.text = _display_override
	elif selected_index >= 0 and selected_index < options.size():
		_text.text = options[selected_index]
	else:
		_text.text = ""


func _on_main_clicked(_type: String, _index: int) -> void:
	if disabled:
		return
	if is_open:
		_close()
	else:
		_open()


func _update_disabled_state() -> void:
	if _text:
		_text.set_palette(UIChar.FontPalette.DISABLED if disabled else text_palette)


func _open() -> void:
	if is_open:
		return

	# Close any other open dropdown first
	if _currently_open and _currently_open != self and is_instance_valid(_currently_open):
		_currently_open._close()
	_currently_open = self

	is_open = true

	_list_frame.position.z = 0.1

	_rebuild_options()

	_list_frame.visible = true
	_option_list.visible = true
	_option_list.activate()
	_option_list.highlighted_index = selected_index

	toggled.emit(true)


func _close() -> void:
	if not is_open:
		return

	if _currently_open == self:
		_currently_open = null

	is_open = false
	_list_frame.visible = false
	_option_list.visible = false
	_option_list.deactivate()

	_list_frame.position.z = 0.0

	toggled.emit(false)


func _rebuild_options() -> void:
	_option_list.clear_items()

	for i in range(options.size()):
		# Container for text + click area as siblings
		# This prevents the click area from inheriting the text's scale
		var container = Node3D.new()

		# Option text (scaled)
		var option_text = UIText.new()
		option_text.text = options[i]
		option_text.pixels_per_unit = pixels_per_unit
		option_text.scale = Vector3(text_scale, text_scale, 1.0)
		option_text.max_width = -1.0  # No wrapping - dropdown options should be single line
		option_text.render_priority = render_priority
		if space_width >= 0.0:
			option_text.space_width = space_width
		container.add_child(option_text)

		# Click area as sibling (NOT child of scaled text)
		var click_area = UIClickableField.new()
		click_area.field_type = "option"
		click_area.field_index = i
		click_area.configure("option", i, Rect2(0, 0, width - 8.0, row_height), pixels_per_unit)
		click_area.clicked.connect(_on_option_clicked)
		container.add_child(click_area)

		_option_list.add_item(container, options[i], row_height)

	_update_list_size()


func _on_option_selected(index: int, _data: Variant) -> void:
	_display_override = ""
	selected_index = index
	option_selected.emit(index, options[index] if index < options.size() else "")
	_close()


func _on_option_clicked(_type: String, index: int) -> void:
	_display_override = ""
	selected_index = index
	option_selected.emit(index, options[index] if index < options.size() else "")
	_close()


## Set options and optionally select one
func set_options(new_options: Array[String], default_index: int = 0) -> void:
	options = new_options
	selected_index = default_index
	_update_display()


## Get currently selected value
func get_selected_value() -> String:
	if selected_index >= 0 and selected_index < options.size():
		return options[selected_index]
	return ""


## Select option by value (returns true if found)
func select_by_value(value: String) -> bool:
	for i in range(options.size()):
		if options[i] == value:
			selected_index = i
			return true
	return false


## Set a display override (shows this text instead of the selected option)
func set_display_override(display_text: String) -> void:
	_display_override = display_text
	_update_display()


## Clear the display override (reverts to showing the selected option)
func clear_display_override() -> void:
	_display_override = ""
	_update_display()


func _update_text_palette() -> void:
	if _text:
		_text.set_palette(UIChar.FontPalette.DISABLED if disabled else text_palette)


func _update_space_width() -> void:
	if _text:
		_text.space_width = space_width


func _update_text_scale() -> void:
	if _text:
		_text.scale = Vector3(text_scale, text_scale, 1.0)


func _update_pixels_per_unit() -> void:
	if _frame:
		_frame.pixels_per_unit = pixels_per_unit
	if _text:
		_text.pixels_per_unit = pixels_per_unit
	if _list_frame:
		_list_frame.pixels_per_unit = pixels_per_unit
	if _option_list:
		_option_list.pixels_per_unit = pixels_per_unit
	_update_layout()


func _update_render_priorities() -> void:
	if _frame:
		_frame.render_priority = render_priority
	if _text:
		_text.render_priority = render_priority
