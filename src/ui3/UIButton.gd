@tool
class_name UIButton
extends UIComponent
## Clickable button component for UI3 with optional built-in frame.
##
## Combines UIFrame + UIText + UIClickableField into a reusable button.
## Emits pressed(button_id) signal when clicked.
##
## Layout/build/dirty-flag machinery comes from [UIComponent].

## Emitted when the button is clicked
signal pressed(button_id: String)

#region Configuration Exports


## Button identifier (passed with pressed signal)
@export var button_id: String = "":
	set(value):
		if button_id == value:
			return
		button_id = value

## Text displayed on the button
@export var text: String = "Button":
	set(value):
		if text == value:
			return
		text = value
		_push(_text_node, &"text", value)

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Render priority for text and frame (higher renders in front)
@export var render_priority: int = 0:
	set(value):
		if render_priority == value:
			return
		render_priority = value
		_push(_text_node, &"render_priority", value)
		_push(_frame, &"render_priority", value)

## Whether the button is disabled (no click response)
@export var disabled: bool = false:
	set(value):
		if disabled == value:
			return
		disabled = value
		_update_disabled_state()

#endregion

#region Frame Configuration

@export_group("Frame")

## Show the frame background
@export var show_frame: bool = false:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		_push(_frame, &"visible", value)

## Frame size in virtual pixels
@export var frame_size: Vector2 = Vector2(50, 20):
	set(value):
		if frame_size == value:
			return
		frame_size = value
		_mark_layout_dirty()

#endregion

#region Text Configuration

@export_group("Text")

## Text scale multiplier
@export var text_scale: float = 1.0:
	set(value):
		if text_scale == value:
			return
		text_scale = value
		_mark_layout_dirty()

## Text palette (0=MENU, 1=STAT, etc.)
@export var text_palette: int = 0:
	set(value):
		if text_palette == value:
			return
		text_palette = value
		if _text_node:
			_text_node.set_palette(text_palette)

## Text offset within button (virtual pixels)
@export var text_offset: Vector2 = Vector2(2, 2):
	set(value):
		if text_offset == value:
			return
		text_offset = value
		_mark_layout_dirty()

## Space width override for text (-1 = font default, 1.0 = FFT consistent)
@export var space_width: float = 1.0:
	set(value):
		if space_width == value:
			return
		space_width = value
		_push(_text_node, &"space_width", value)

#endregion

#region Click Area Configuration

@export_group("Click Area")

## Click area offset from button origin (virtual pixels)
@export var click_area_offset: Vector2 = Vector2(0, 0):
	set(value):
		if click_area_offset == value:
			return
		click_area_offset = value
		_mark_layout_dirty()

## Click area size in virtual pixels (negative values = use frame_size)
@export var click_area_size: Vector2 = Vector2(-1, -1):
	set(value):
		if click_area_size == value:
			return
		click_area_size = value
		_mark_layout_dirty()

#endregion

#region Internal State

var _frame: UIFrame
var _text_node: UIText
var _click_area: UIClickableField
var _debug_visible: bool = false

#endregion


func _build_children() -> void:
	# Create frame (behind everything)
	_frame = UIFrame.new()
	_frame.name = "Frame"
	_frame.frame_size = frame_size
	_frame.pixels_per_unit = pixels_per_unit
	_frame.render_priority = render_priority
	_frame.visible = show_frame
	_frame.position.z = -0.01  # Behind text
	add_child(_frame)

	# Create text node
	_text_node = UIText.new()
	_text_node.name = "ButtonText"
	_text_node.text = text
	_text_node.pixels_per_unit = pixels_per_unit * text_scale
	_text_node.space_width = space_width
	_text_node.render_priority = render_priority
	_text_node.set_palette(text_palette)
	add_child(_text_node)

	# Create click area
	_click_area = UIClickableField.new()
	_click_area.name = "ClickArea"
	_click_area.clicked.connect(_on_click_area_clicked)
	add_child(_click_area)

	_update_disabled_state()


func _update_layout() -> void:
	if not _built:
		return

	var ppu = pixels_per_unit

	# Update frame
	if _frame:
		_frame.frame_size = frame_size
		_frame.pixels_per_unit = ppu
		_frame.render_priority = render_priority

	# Update text position and scale
	if _text_node:
		_text_node.position = Vector3(
			text_offset.x * ppu,
			-text_offset.y * ppu,
			0.01
		)
		_text_node.pixels_per_unit = ppu * text_scale

	# Update click area
	if _click_area:
		var effective_size = _get_effective_click_area_size()
		_click_area.configure(
			"button",
			0,
			Rect2(click_area_offset.x, click_area_offset.y, effective_size.x, effective_size.y),
			ppu,
			_debug_visible
		)


## Get effective click area size (uses frame_size if click_area_size has negative values)
func _get_effective_click_area_size() -> Vector2:
	return Vector2(
		click_area_size.x if click_area_size.x >= 0 else frame_size.x,
		click_area_size.y if click_area_size.y >= 0 else frame_size.y
	)


func _update_disabled_state() -> void:
	if _click_area:
		_click_area.input_ray_pickable = not disabled

	# Change text appearance when disabled
	if _text_node:
		_text_node.font_color = Color(0.5, 0.5, 0.5) if disabled else Color.WHITE


func _on_click_area_clicked(_field_type: String, _field_index: int) -> void:
	if not disabled:
		pressed.emit(button_id)


#region Public API

## Set debug visibility for click area
func set_debug_visible(show: bool) -> void:
	_debug_visible = show
	if _click_area:
		_click_area.set_debug_visible(show)


## Get current debug visibility state
func is_debug_visible() -> bool:
	return _debug_visible

#endregion
