@tool
class_name UIMenuFrame
extends UIWindow
## Flexible frame with optional portrait and arbitrary text elements.
##
## Origin is at TOP-LEFT; all components extend RIGHT and DOWN.
## Supports multiple independently-configured text elements.
## Can have click areas attached to text elements.

## #1271 — `DebugConfig` is a host autoload, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6), so the identifier is undefined in a
## stranger project. The flags were already `Tune` slugs; `UIDebug` reads them
## through the platform port. ADR-0308.
const UIDebug = preload("res://src/ui3/UIDebug.gd")

## Emitted when a text field with a click area is clicked
signal text_field_clicked(text_index: int)


## Size of the frame in virtual pixels
@export var frame_size: Vector2 = Vector2(200, 100):
	set(value):
		frame_size = value
		_update_layout()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_layout()

## Show the portrait
@export var show_portrait: bool = false:
	set(value):
		show_portrait = value
		if _portrait:
			_portrait.visible = show_portrait

## Portrait position offset from top-left (in virtual pixels)
@export var portrait_offset: Vector2 = Vector2(4, 4):
	set(value):
		portrait_offset = value
		_update_layout()

## Portrait flip (horizontal mirror)
@export var portrait_flipped: bool = false:
	set(value):
		portrait_flipped = value
		if _portrait:
			_portrait.flipped = portrait_flipped

## Show or hide the frame background
@export var show_frame: bool = true:
	set(value):
		show_frame = value
		if _frame:
			_frame.visible = show_frame

var _frame: UIFrame
var _portrait: UIPortrait
var _text_elements: Array[UIText] = []
var _text_configs: Array[Dictionary] = []  # {offset, palette, scale, spacing}
var _click_areas: Array[UIClickableField] = []
var _dropdown_elements: Array = []  # Array of UIDropdown
var _dropdown_configs: Array[Dictionary] = []  # {offset, width, scale, palette, space_width}


func _ready() -> void:
	_setup_frame()
	_setup_portrait()
	_update_layout()


func _setup_frame() -> void:
	_frame = UIFrame.new()
	_frame.frame_size = frame_size
	_frame.visible = show_frame
	add_child(_frame)


func _setup_portrait() -> void:
	_portrait = UIPortrait.new()
	_portrait.flipped = portrait_flipped
	_portrait.visible = show_portrait
	add_child(_portrait)


func _update_layout() -> void:
	# Update frame
	if _frame:
		_frame.frame_size = frame_size
		_frame.pixels_per_unit = pixels_per_unit
		_frame.position = Vector3(0, 0, -0.1)  # Behind other elements

	# Update portrait position
	if _portrait:
		_portrait.pixels_per_unit = pixels_per_unit
		_portrait.position = Vector3(
			portrait_offset.x * pixels_per_unit,
			-portrait_offset.y * pixels_per_unit,
			0.0
		)

	# Update all text elements
	for i in range(_text_elements.size()):
		_update_text_element(i)

	# Update all dropdown elements
	for i in range(_dropdown_elements.size()):
		_update_dropdown_element(i)


func _update_text_element(index: int) -> void:
	if index >= _text_elements.size() or index >= _text_configs.size():
		return

	var text_elem = _text_elements[index]
	var config = _text_configs[index]

	if not is_instance_valid(text_elem):
		return

	var offset: Vector2 = config.get("offset", Vector2.ZERO)
	var scale: float = config.get("scale", 1.0)
	var space_width: float = config.get("space_width", -1.0)

	text_elem.pixels_per_unit = pixels_per_unit * scale
	text_elem.space_width = space_width
	text_elem.position = Vector3(
		offset.x * pixels_per_unit,
		-offset.y * pixels_per_unit,
		0.1
	)


## Add a text element to the menu.
## Returns the index of the added element.
func add_text(text: String, offset: Vector2, palette: UIChar.FontPalette = UIChar.FontPalette.MENU) -> int:
	var text_elem = UIText.new()
	text_elem.text = text
	add_child(text_elem)
	_text_elements.append(text_elem)

	var config = {
		"offset": offset,
		"palette": palette,
		"scale": 1.0,
		"spacing": 0.0
	}
	_text_configs.append(config)

	var index = _text_elements.size() - 1
	_update_text_element(index)

	# Apply palette after layout
	_apply_text_palette(index)

	return index


func _apply_text_palette(index: int) -> void:
	if index < _text_elements.size() and index < _text_configs.size():
		var text_elem = _text_elements[index]
		var config = _text_configs[index]
		if is_instance_valid(text_elem):
			text_elem.set_palette(config.get("palette", UIChar.FontPalette.MENU))


## Update text content at a specific index
func update_text(index: int, new_text: String) -> void:
	if index >= 0 and index < _text_elements.size():
		var text_elem = _text_elements[index]
		if is_instance_valid(text_elem):
			if text_elem.text == new_text:
				return  # Skip if unchanged
			text_elem.text = new_text


## Remove text element at a specific index
## Get a text element by index
## Get the number of text elements
## Set text offset for an element
## Set text scale for an element
func set_text_scale(index: int, scale: float) -> void:
	if index >= 0 and index < _text_configs.size():
		_text_configs[index]["scale"] = scale
		_update_text_element(index)


## Set text palette for an element
## Set text space width for an element (-1 for default)
func set_text_space_width(index: int, space_width: float) -> void:
	if index >= 0 and index < _text_configs.size():
		_text_configs[index]["space_width"] = space_width
		_update_text_element(index)


## Set text visibility for an element
## Set portrait sprite ID
## Set portrait visibility
## Set portrait flip
func set_portrait_flipped(flipped: bool) -> void:
	portrait_flipped = flipped


## Clear all text elements
#region Dropdown Elements

func _update_dropdown_element(index: int) -> void:
	if index >= _dropdown_elements.size() or index >= _dropdown_configs.size():
		return

	var dd = _dropdown_elements[index]
	var config = _dropdown_configs[index]

	if not is_instance_valid(dd):
		return

	var offset: Vector2 = config.get("offset", Vector2.ZERO)
	var scale: float = config.get("scale", 1.0)
	var width: float = config.get("width", 140.0)
	var space_width: float = config.get("space_width", -1.0)

	dd.pixels_per_unit = pixels_per_unit * scale
	dd.width = width
	if space_width >= 0.0:
		dd.space_width = space_width
	dd.position = Vector3(
		offset.x * pixels_per_unit,
		-offset.y * pixels_per_unit,
		0.2
	)


## Add a dropdown element to the menu.
## Returns the index of the added element.
## Get a dropdown element by index
## Get the number of dropdown elements
## Set dropdown offset
## Set dropdown scale
## Set dropdown width
## Set dropdown palette
## Set dropdown options
## Set dropdown selected index
## Set dropdown space width
## Clear all dropdown elements
#endregion


## Get the frame component
func get_frame() -> UIFrame:
	return _frame


## Set frame visibility
func set_frame_visible(visible: bool) -> void:
	show_frame = visible


## Get the portrait component
func get_portrait() -> UIPortrait:
	return _portrait


## Resize the frame
#region Click Areas

## Add a click area for a text element at the given index.
## Returns the click area for further configuration, or null if index is invalid.
## padding: Extra pixels around the text bounds (x = horizontal, y = vertical)
## size_override: If x > 0, use as width instead of auto-calculated. If y > 0, use as height.
func add_text_click_area(text_index: int, field_type: String, padding: Vector2 = Vector2(2, 1), size_override: Vector2 = Vector2.ZERO) -> UIClickableField:
	if UIDebug.iteration():
		print("[UIMenuFrame] add_text_click_area: text_index=%d, _text_elements.size()=%d" % [text_index, _text_elements.size()])
	if text_index < 0 or text_index >= _text_elements.size():
		if UIDebug.iteration():
			print("[UIMenuFrame] FAILED: text_index out of range")
		return null

	var text_elem = _text_elements[text_index]
	if not is_instance_valid(text_elem):
		if UIDebug.iteration():
			print("[UIMenuFrame] FAILED: text_elem not valid")
		return null

	var config = _text_configs[text_index]
	var offset: Vector2 = config.get("offset", Vector2.ZERO)
	var scale: float = config.get("scale", 1.0)

	# Get text size in virtual pixels
	var text_size = text_elem.get_text_size()
	# Convert from world units back to virtual pixels
	var text_width_px = text_size.x / (pixels_per_unit * scale)
	var text_height_px = text_size.y / (pixels_per_unit * scale)

	# If text is empty, use a minimum size
	if text_width_px < 8:
		text_width_px = 40  # Minimum clickable width

	# Apply size_override if provided (allows explicit sizing to avoid overlaps)
	if size_override.x > 0:
		text_width_px = size_override.x
	if size_override.y > 0:
		text_height_px = size_override.y

	# Create click area rect with padding
	var rect = Rect2(
		offset.x - padding.x,
		offset.y - padding.y,
		text_width_px + padding.x * 2,
		text_height_px + padding.y * 2
	)

	var click_area = UIClickableField.new()
	add_child(click_area)
	click_area.configure(field_type, text_index, rect, pixels_per_unit, false)
	click_area.clicked.connect(_on_click_area_clicked)
	_click_areas.append(click_area)

	return click_area


## Set visibility of all click area debug meshes
func set_click_areas_visible(debug_visible: bool) -> void:
	for area in _click_areas:
		if is_instance_valid(area):
			area.set_debug_visible(debug_visible)


## Clear all click areas
## Get all click areas
func _on_click_area_clicked(field_type: String, field_index: int) -> void:
	text_field_clicked.emit(field_index)

#endregion
