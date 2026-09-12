@tool
class_name UIPortraitFrame
extends Node3D
## Portrait card with optional frame, portrait, and stats text.
##
## Origin is at TOP-LEFT; all components extend RIGHT and DOWN.
## Combines UIFrame (optional), UIPortrait, and UIText for stats.

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_update_layout()

## Show the dialog frame around components
@export var show_frame: bool = true:
	set(value):
		show_frame = value
		if _frame:
			_frame.visible = show_frame
		_update_layout()

## Global scale for entire assembly
@export var assembly_scale: float = 1.0:
	set(value):
		assembly_scale = value
		_update_layout()

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

## Individual portrait scale
@export var portrait_scale: float = 1.0:
	set(value):
		portrait_scale = value
		_update_layout()


## Frame size in virtual pixels (used when show_frame is true)
@export var frame_size: Vector2 = Vector2(120, 60):
	set(value):
		frame_size = value
		_update_layout()

var _frame: UIFrame
var _portrait: UIPortrait
var _stats_elements: Array[UIText] = []
var _stats_configs: Array[Dictionary] = []  # {offset, text, palette, scale, space_width}


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
	add_child(_portrait)


func _update_layout() -> void:
	var ppu = pixels_per_unit * assembly_scale

	# Update frame
	if _frame:
		_frame.frame_size = frame_size
		_frame.pixels_per_unit = ppu
		_frame.position = Vector3(0, 0, -0.1)  # Behind other elements

	# Update portrait position and scale
	if _portrait:
		var portrait_ppu = ppu * portrait_scale
		_portrait.pixels_per_unit = portrait_ppu
		# Position from top-left (Y goes negative)
		_portrait.position = Vector3(
			portrait_offset.x * ppu,
			-portrait_offset.y * ppu,
			0.0
		)

	# Update all stats elements
	for i in range(_stats_elements.size()):
		_update_stats_element(i)


func _update_stats_element(index: int) -> void:
	if index >= _stats_elements.size() or index >= _stats_configs.size():
		return

	var stats_elem = _stats_elements[index]
	var config = _stats_configs[index]

	if not is_instance_valid(stats_elem):
		return

	var ppu = pixels_per_unit * assembly_scale
	var offset: Vector2 = config.get("offset", Vector2.ZERO)
	var scale: float = config.get("scale", 1.0)

	stats_elem.pixels_per_unit = ppu * scale
	stats_elem.position = Vector3(
		offset.x * ppu,
		-offset.y * ppu,
		0.1  # In front of portrait
	)


## Display portrait for a sprite ID
func display_sprite_id(sprite_id: int) -> void:
	if _portrait:
		_portrait.display_sprite_id(sprite_id)


## Display the portrait from a unit's template folder (ADR-0072 #203), falling
## back to `fallback_sprite_id` on the shared sprite sheet when the folder is
## absent. Passthrough to [UIPortrait.display_from_template].
func display_from_template(template_folder: String, fallback_sprite_id: int) -> void:
	if _portrait:
		_portrait.display_from_template(template_folder, fallback_sprite_id)


## Add a stats text element.
## Returns the index of the added element.
func add_stats(text: String, offset: Vector2, palette: UIChar.FontPalette = UIChar.FontPalette.STAT, scale: float = 1.0, space_width: float = -1.0) -> int:
	var stats_elem = UIText.new()
	stats_elem.text = text
	if space_width >= 0.0:
		stats_elem.space_width = space_width
	add_child(stats_elem)
	_stats_elements.append(stats_elem)

	var config = {
		"offset": offset,
		"text": text,
		"palette": palette,
		"scale": scale,
		"space_width": space_width
	}
	_stats_configs.append(config)

	var index = _stats_elements.size() - 1
	_update_stats_element(index)

	# Apply palette after layout
	_apply_stats_palette(index)

	return index


func _apply_stats_palette(index: int) -> void:
	if index < _stats_elements.size() and index < _stats_configs.size():
		var stats_elem = _stats_elements[index]
		var config = _stats_configs[index]
		if is_instance_valid(stats_elem):
			stats_elem.set_palette(config.get("palette", UIChar.FontPalette.STAT))


## Update stats text content at a specific index
## Set stats offset for an element
## Set stats palette for an element
## Set stats scale for an element
## Set stats space_width for an element
## Remove stats element at a specific index
## Get the number of stats elements
## Get a stats element by index
## Clear all stats elements
func clear_stats() -> void:
	for stats_elem in _stats_elements:
		if is_instance_valid(stats_elem):
			stats_elem.queue_free()
	_stats_elements.clear()
	_stats_configs.clear()


## Set frame visibility
func set_frame_visible(visible: bool) -> void:
	show_frame = visible


## Set portrait flip
func set_portrait_flipped(flipped: bool) -> void:
	portrait_flipped = flipped


## Set assembly scale (affects all components)
## Clear the portrait
func clear_portrait() -> void:
	if _portrait:
		_portrait.clear()


## Get the portrait component
func get_portrait() -> UIPortrait:
	return _portrait


## Get the frame component
func get_frame() -> UIFrame:
	return _frame
