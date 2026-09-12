@tool
class_name UIRosterBar
extends UIWindow
## Roster bar displaying multiple portrait frames in a row or column.
##
## Uses @export properties with setters for all configuration.
## Origin is at TOP-LEFT; frames extend RIGHT (horizontal) or DOWN (vertical).
##
## This component is designed to work without external JSON config - all
## settings are stored in the scene file via @export properties.

## ADR-0211 dec. 4 — the host autoload `EventBus` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so the live
## vitals subscription goes through the platform port. #1274 / ADR-0308.
const EventPort = ExMateriaPlatform.EventPort

## Emitted when a frame is clicked
signal frame_clicked(frame_index: int)

## Emitted when unit stats change (for data binding)
signal stats_updated(frame_index: int)

## Layout orientation constants
const HORIZONTAL: int = 0
const VERTICAL: int = 1

#region Configuration Exports


## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Layout direction (0 = HORIZONTAL, 1 = VERTICAL)
@export_range(0, 1) var orientation: int = HORIZONTAL:
	set(value):
		if orientation == value:
			return
		orientation = value
		_mark_layout_dirty()

## Spacing between frames in virtual pixels
@export var spacing: float = 9.0:
	set(value):
		if spacing == value:
			return
		spacing = value
		_mark_layout_dirty()

## Number of portrait frames to display
@export var frame_count: int = 4:
	set(value):
		var new_count = maxi(0, value)
		if frame_count == new_count:
			return
		frame_count = new_count
		_rebuild_frames()
		_mark_layout_dirty()

#endregion

#region Frame Template Configuration

## Show the dialog frame around each portrait
@export_group("Frame Template")
@export var show_frame: bool = true:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		_apply_template_to_all()

## Global scale for frames
@export var assembly_scale: float = 1.0:
	set(value):
		if assembly_scale == value:
			return
		assembly_scale = value
		_apply_template_to_all()

## Size of each frame in virtual pixels
@export var frame_size: Vector2 = Vector2(44, 51):
	set(value):
		if frame_size == value:
			return
		frame_size = value
		_apply_template_to_all()
		_mark_layout_dirty()

## Portrait position offset from top-left (in virtual pixels)
@export var portrait_offset: Vector2 = Vector2(1, 1):
	set(value):
		if portrait_offset == value:
			return
		portrait_offset = value
		_apply_template_to_all()

## Portrait flip (horizontal mirror)
@export var portrait_flipped: bool = false:
	set(value):
		if portrait_flipped == value:
			return
		portrait_flipped = value
		_apply_template_to_all()

## Individual portrait scale
@export var portrait_scale: float = 1.0:
	set(value):
		if portrait_scale == value:
			return
		portrait_scale = value
		_apply_template_to_all()

#endregion

#region Stats Text Configuration

## Stats text items configuration (applied to all frames)
## Array of dictionaries with: text, offset_x, offset_y, palette, scale, space_width, binding_type
@export_group("Stats Text")
@export var stats_template: Array[Dictionary] = []:
	set(value):
		if stats_template == value:
			return
		stats_template = value
		_apply_stats_template_to_all()

#endregion

#region Click Area Configuration

## Enable click areas on frames
@export_group("Click Areas")
@export var enable_click_areas: bool = true:
	set(value):
		if enable_click_areas == value:
			return
		enable_click_areas = value
		_rebuild_click_areas()

## Padding around frame for click detection (in virtual pixels)
@export var click_area_padding: Vector2 = Vector2(2, 2):
	set(value):
		if click_area_padding == value:
			return
		click_area_padding = value
		_rebuild_click_areas()

## Show debug visualization for click areas
@export var show_click_area_debug: bool = false:
	set(value):
		if show_click_area_debug == value:
			return
		show_click_area_debug = value
		_update_click_area_debug_visibility()

#endregion

#region Internal State

var _frames: Array[UIPortraitFrame] = []
var _click_areas: Array[UIClickableField] = []
var _units: Array = []  # Unit references for data binding

#endregion


func _ready() -> void:
	super._ready()

	# Live HP/MP through the platform port -- an addon may not name the `EventBus`
	# autoload (#1274). No-op without a bus, which is the right identity here.
	if not Engine.is_editor_hint():
		EventPort.connect_unit_hp_changed(_on_eventbus_hp_changed)
		EventPort.connect_unit_mp_changed(_on_eventbus_mp_changed)


func _build_children() -> void:
	_rebuild_frames()


#region Frame Management

func _rebuild_frames() -> void:
	# Remove excess frames
	while _frames.size() > frame_count:
		var frame = _frames.pop_back()
		if is_instance_valid(frame):
			frame.queue_free()

	# Remove excess click areas
	while _click_areas.size() > frame_count:
		var click_area = _click_areas.pop_back()
		if is_instance_valid(click_area):
			click_area.queue_free()

	# Remove excess unit references
	while _units.size() > frame_count:
		_units.pop_back()

	# Add new frames
	while _frames.size() < frame_count:
		var frame = UIPortraitFrame.new()
		add_child(frame)
		_frames.append(frame)
		_units.append(null)

	_apply_template_to_all()
	_rebuild_click_areas()


func _apply_template_to_all() -> void:
	for frame in _frames:
		if not is_instance_valid(frame):
			continue

		frame.pixels_per_unit = pixels_per_unit * assembly_scale
		frame.show_frame = show_frame
		frame.frame_size = frame_size
		frame.portrait_offset = portrait_offset
		frame.portrait_flipped = portrait_flipped
		frame.portrait_scale = portrait_scale

	_apply_stats_template_to_all()


func _apply_stats_template_to_all() -> void:
	for i in range(_frames.size()):
		var frame = _frames[i]
		if not is_instance_valid(frame):
			continue

		frame.clear_stats()

		var unit = _units[i] if i < _units.size() else null

		for item in stats_template:
			var text: String
			if item.has("binding_type") and unit:
				text = UIDataBinding.resolve_binding(unit, item)
			else:
				text = item.get("text", item.get("fallback", ""))

			var offset_x: float = item.get("offset_x", 0.0)
			var offset_y: float = item.get("offset_y", 0.0)
			var palette: UIChar.FontPalette = item.get("palette", UIChar.FontPalette.STAT)
			var scale: float = item.get("scale", 1.0)
			var space_width: float = item.get("space_width", -1.0)

			frame.add_stats(text, Vector2(offset_x, offset_y), palette, scale, space_width)


func _update_layout() -> void:
	var ppu = pixels_per_unit * assembly_scale

	for i in range(_frames.size()):
		var frame = _frames[i]
		if not is_instance_valid(frame):
			continue

		frame.pixels_per_unit = ppu

		var pos = Vector3.ZERO
		if orientation == HORIZONTAL:
			var offset_x: float = 0.0
			for j in range(i):
				offset_x += frame_size.x + spacing
			pos.x = offset_x * ppu
		else:
			var offset_y: float = 0.0
			for j in range(i):
				offset_y += frame_size.y + spacing
			pos.y = -offset_y * ppu  # Y goes negative (down)

		frame.position = pos

	_update_click_area_positions()

#endregion


#region Click Area Management

func _rebuild_click_areas() -> void:
	# Clear existing click areas
	for click_area in _click_areas:
		if is_instance_valid(click_area):
			click_area.queue_free()
	_click_areas.clear()

	if not enable_click_areas:
		return

	# Create click areas for each frame
	for i in range(_frames.size()):
		var click_area = UIClickableField.new()
		add_child(click_area)
		click_area.clicked.connect(_on_click_area_clicked)
		_click_areas.append(click_area)

	_update_click_area_positions()


func _update_click_area_positions() -> void:
	if not enable_click_areas:
		return

	var ppu = pixels_per_unit * assembly_scale

	for i in range(_click_areas.size()):
		if i >= _frames.size():
			break

		var click_area = _click_areas[i]
		var frame = _frames[i]

		if not is_instance_valid(click_area) or not is_instance_valid(frame):
			continue

		var rect = Rect2(
			-click_area_padding.x,
			-click_area_padding.y,
			frame_size.x + click_area_padding.x * 2,
			frame_size.y + click_area_padding.y * 2
		)

		click_area.configure("roster_frame", i, rect, ppu, show_click_area_debug)
		# Add frame position to the configured position (configure sets position relative to origin)
		var local_offset = click_area.position
		click_area.position = Vector3(
			frame.position.x + local_offset.x,
			frame.position.y + local_offset.y,
			local_offset.z  # Keep z = 0.5
		)


func _update_click_area_debug_visibility() -> void:
	for click_area in _click_areas:
		if is_instance_valid(click_area):
			click_area.set_debug_visible(show_click_area_debug)


func _on_click_area_clicked(_field_type: String, field_index: int) -> void:
	frame_clicked.emit(field_index)

#endregion


#region Public API

## Get a frame by index
func get_frame(index: int) -> UIPortraitFrame:
	if index >= 0 and index < _frames.size():
		return _frames[index]
	return null


## Get all frames
## Get frame count
## Set the unit reference for a specific frame (for data binding)
func set_frame_unit(index: int, unit: Node) -> void:
	while _units.size() <= index:
		_units.append(null)

	var old_unit = _units[index]

	# Disconnect from old unit's stats_changed signal (for level up / job changes)
	if old_unit and old_unit.has_signal("stats_changed"):
		if old_unit.is_connected("stats_changed", _on_unit_stats_changed.bind(index)):
			old_unit.disconnect("stats_changed", _on_unit_stats_changed.bind(index))

	_units[index] = unit

	# Connect to new unit's stats_changed signal (for level up / job changes)
	# HP/MP changes arrive on the port subscription wired in `_ready()`
	if unit and unit.has_signal("stats_changed"):
		unit.connect("stats_changed", _on_unit_stats_changed.bind(index))

	# Update frame with new unit data
	refresh_frame_stats(index)


## Set sprite ID for a specific frame
func set_frame_sprite_id(index: int, sprite_id: int) -> void:
	if index < 0 or index >= _frames.size():
		return

	var frame = _frames[index]
	if is_instance_valid(frame):
		if sprite_id >= 0:
			# Front the flat sheet with the bound unit's OWNED template portrait
			# (#205) when it resolved to a folder; blank folder → flat sprite id,
			# which stays load-bearing (folders are generated + gitignored).
			frame.display_from_template(_template_folder_for(index), sprite_id)
		else:
			frame.clear_portrait()


## The template folder of the unit bound to `index`, or "" when unbound / a unit
## that carries no folder (generics). `set_frame_unit` runs before this at every
## call site, so the reference is in place.
func _template_folder_for(index: int) -> String:
	var unit = _units[index] if index < _units.size() else null
	if is_instance_valid(unit):
		var folder = unit.get("template_folder")
		if folder != null:
			return str(folder)
	return ""


## Update stats text for a specific frame's stats element
## Refresh all frames from their bound units
#endregion


#region Data Binding

func _on_unit_stats_changed(index: int) -> void:
	refresh_frame_stats(index)
	stats_updated.emit(index)


func _on_eventbus_hp_changed(unit: Node, _old_hp: int, _new_hp: int) -> void:
	# Find which frame index has this unit and refresh it
	for i in range(_units.size()):
		if _units[i] == unit:
			refresh_frame_stats(i)
			stats_updated.emit(i)
			return


func _on_eventbus_mp_changed(unit: Node, _old_mp: int, _new_mp: int) -> void:
	# Find which frame index has this unit and refresh it
	for i in range(_units.size()):
		if _units[i] == unit:
			refresh_frame_stats(i)
			stats_updated.emit(i)
			return


func refresh_frame_stats(index: int) -> void:
	if index < 0 or index >= _frames.size():
		return

	var frame = _frames[index]
	var unit = _units[index] if index < _units.size() else null

	if not is_instance_valid(frame):
		return

	frame.clear_stats()

	for item in stats_template:
		var text: String
		if item.has("binding_type") and unit:
			text = UIDataBinding.resolve_binding(unit, item)
		else:
			text = item.get("text", item.get("fallback", ""))

		var offset_x: float = item.get("offset_x", 0.0)
		var offset_y: float = item.get("offset_y", 0.0)
		var palette: UIChar.FontPalette = item.get("palette", UIChar.FontPalette.STAT)
		var scale: float = item.get("scale", 1.0)
		var space_width: float = item.get("space_width", -1.0)

		frame.add_stats(text, Vector2(offset_x, offset_y), palette, scale, space_width)

#endregion
