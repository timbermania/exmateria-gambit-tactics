class_name UIScrollableList
extends Node3D
## Scrollable list component using visibility-toggle scrolling.
##
## Shows a fixed number of items at a time, hiding items outside the visible range.
## Supports mouse wheel scrolling, arrow key navigation, and item selection.

## #1271 — `DebugConfig` is a host autoload, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6), so the identifier is undefined in a
## stranger project. The flags were already `Tune` slugs; `UIDebug` reads them
## through the platform port. ADR-0308.
const UIDebug = preload("res://src/ui3/UIDebug.gd")

## Emitted when an item is selected (clicked)
signal item_selected(index: int, item_data: Variant)

## Emitted when selection is cancelled (ESC pressed)
signal cancelled()

## Emitted when scroll position changes
signal scroll_changed(offset: int)

## Maximum number of visible items
@export var visible_count: int = 6:
	set(value):
		var new_value = maxi(1, value)
		if visible_count == new_value:
			return
		visible_count = new_value
		_update_visibility()

## Spacing between items in virtual pixels
@export var item_spacing: float = 2.0:
	set(value):
		if item_spacing == value:
			return
		item_spacing = value
		_update_visibility()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04

## Whether to show scroll indicators
@export var show_scroll_indicators: bool = true

## Currently highlighted item index (for keyboard navigation)
var highlighted_index: int = -1:
	set(value):
		var old_value = highlighted_index
		var item_count = get_item_count()
		highlighted_index = clampi(value, 0, item_count - 1) if item_count > 0 else -1
		if old_value != highlighted_index:
			_update_highlight()
			_ensure_highlighted_visible()

## Current scroll offset (first visible item index)
var scroll_offset: int = 0:
	set(value):
		var max_offset = maxi(0, get_item_count() - visible_count)
		var new_offset = clampi(value, 0, max_offset)
		if scroll_offset != new_offset:
			scroll_offset = new_offset
			if virtual_mode:
				_rebuild_virtual_nodes()
			else:
				_update_visibility()
			scroll_changed.emit(scroll_offset)

## Items in the list: Array of {node: Node3D, data: Variant, height: float}
var _items: Array[Dictionary] = []

## Scroll indicator nodes
var _up_indicator: UIText
var _down_indicator: UIText

## Whether we're currently accepting input
var _active: bool = false

## Batch mode - when true, add_item() defers _update_visibility() calls
var _batch_mode: bool = false

#region Virtual Scrolling Mode

## Virtual scrolling mode - only creates nodes for visible items
var virtual_mode: bool = false

## Callback to create/update item node for virtual mode
## Signature: func(index: int, data: Variant, existing_node: Node3D) -> Node3D
var virtual_item_factory: Callable

## Item height for virtual mode (in virtual pixels)
var virtual_item_height: float = 16.0

## Data array for virtual mode (items without nodes)
var _virtual_data: Array = []

## Pool of reusable nodes for virtual mode
var _virtual_node_pool: Array[Node3D] = []

## Map of visible index -> node for virtual mode
var _virtual_visible_nodes: Dictionary = {}  # int -> Node3D

#endregion


func _ready() -> void:
	_setup_scroll_indicators()


func _input(event: InputEvent) -> void:
	if not _active or not visible:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed:
			match mouse_event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					scroll_offset -= 1
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					scroll_offset += 1
					get_viewport().set_input_as_handled()

	elif event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed:
			match key_event.keycode:
				KEY_UP:
					highlighted_index -= 1
					get_viewport().set_input_as_handled()
				KEY_DOWN:
					highlighted_index += 1
					get_viewport().set_input_as_handled()
				KEY_ENTER, KEY_KP_ENTER:
					var item_count = get_item_count()
					if highlighted_index >= 0 and highlighted_index < item_count:
						var item_data = get_item_data(highlighted_index)
						item_selected.emit(highlighted_index, item_data)
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					if UIDebug.iteration():
						print("[UIScrollableList] ESC pressed, emitting cancelled")
					cancelled.emit()
					get_viewport().set_input_as_handled()


func _setup_scroll_indicators() -> void:
	if not show_scroll_indicators:
		return

	# Up indicator (shown when can scroll up)
	_up_indicator = UIText.new()
	_up_indicator.text = "^"  # Will be positioned above list
	_up_indicator.pixels_per_unit = pixels_per_unit
	_up_indicator.visible = false
	add_child(_up_indicator)

	# Down indicator (shown when can scroll down)
	_down_indicator = UIText.new()
	_down_indicator.text = "v"  # Will be positioned below list
	_down_indicator.pixels_per_unit = pixels_per_unit
	_down_indicator.visible = false
	add_child(_down_indicator)


## Begin batch mode - defers visibility updates until end_batch() is called.
## Use this when adding many items at once to avoid O(n²) performance.
## End batch mode and perform a single visibility update.
func end_batch() -> void:
	_batch_mode = false
	_update_visibility()


## Add an item to the list.
## node: The visual node to display for this item
## data: Optional data associated with this item
## height: Height of the item in virtual pixels
func add_item(node: Node3D, data: Variant = null, height: float = 16.0) -> int:
	add_child(node)
	_items.append({
		"node": node,
		"data": data,
		"height": height
	})
	if not _batch_mode:
		_update_visibility()
	return _items.size() - 1


## Clear all items from the list
func clear_items() -> void:
	for item in _items:
		var node = item.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_items.clear()
	scroll_offset = 0
	highlighted_index = -1
	_update_visibility()


## Get item data at index (works in both modes)
func get_item_data(index: int) -> Variant:
	if virtual_mode:
		if index >= 0 and index < _virtual_data.size():
			return _virtual_data[index]
		return null
	if index >= 0 and index < _items.size():
		return _items[index].get("data")
	return null


## Get item count (works in both modes)
func get_item_count() -> int:
	if virtual_mode:
		return _virtual_data.size()
	return _items.size()


## Activate the list (start accepting input)
func activate() -> void:
	_active = true
	if _items.size() > 0 and highlighted_index < 0:
		highlighted_index = 0


## Deactivate the list (stop accepting input)
func deactivate() -> void:
	_active = false


## Check if list is active
func is_active() -> bool:
	return _active


func _update_visibility() -> void:
	var y_offset: float = 0.0
	var visible_end = scroll_offset + visible_count

	for i in range(_items.size()):
		var item = _items[i]
		var node = item.get("node")
		if not is_instance_valid(node):
			continue

		var is_visible = i >= scroll_offset and i < visible_end
		node.visible = is_visible

		if is_visible:
			# Position visible items compactly
			var visible_idx = i - scroll_offset
			node.position.y = -y_offset
			y_offset += (item.get("height", 16.0) + item_spacing) * pixels_per_unit

	_update_scroll_indicators()


func _update_scroll_indicators() -> void:
	if not show_scroll_indicators:
		return

	var item_count = get_item_count()
	var can_scroll_up = scroll_offset > 0
	var can_scroll_down = scroll_offset + visible_count < item_count

	if _up_indicator:
		_up_indicator.visible = can_scroll_up
		# Position above the list
		_up_indicator.position = Vector3(0, 8 * pixels_per_unit, 0.02)

	if _down_indicator:
		_down_indicator.visible = can_scroll_down
		# Position below the visible items
		var total_height = _calculate_visible_height()
		_down_indicator.position = Vector3(0, -(total_height + 4 * pixels_per_unit), 0.02)


func _calculate_visible_height() -> float:
	var height: float = 0.0
	var item_count = get_item_count()
	var visible_end = mini(scroll_offset + visible_count, item_count)

	if virtual_mode:
		# In virtual mode, all items have the same height
		var num_visible = visible_end - scroll_offset
		if num_visible > 0:
			height = num_visible * (virtual_item_height + item_spacing) * pixels_per_unit
	else:
		for i in range(scroll_offset, visible_end):
			var item = _items[i]
			height += (item.get("height", 16.0) + item_spacing) * pixels_per_unit
	return height


func _update_highlight() -> void:
	# Override in subclass to show highlight effect
	pass


func _ensure_highlighted_visible() -> void:
	if highlighted_index < 0:
		return

	# Scroll to keep highlighted item visible
	if highlighted_index < scroll_offset:
		scroll_offset = highlighted_index
	elif highlighted_index >= scroll_offset + visible_count:
		scroll_offset = highlighted_index - visible_count + 1


#region Virtual Mode Methods

## Set all item data at once for virtual mode. No nodes are created immediately.
## Only visible items will have nodes created on demand.
func set_virtual_data(data: Array) -> void:
	if not virtual_mode:
		push_warning("[UIScrollableList] set_virtual_data called but virtual_mode is false")
		return

	_virtual_data = data.duplicate()
	scroll_offset = 0
	highlighted_index = 0 if data.size() > 0 else -1
	_rebuild_virtual_nodes()


## Clear all data and nodes for virtual mode
func clear_virtual_data() -> void:
	# Free all visible nodes
	for node in _virtual_visible_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_virtual_visible_nodes.clear()

	# Free pooled nodes
	for node in _virtual_node_pool:
		if is_instance_valid(node):
			node.queue_free()
	_virtual_node_pool.clear()

	_virtual_data.clear()
	scroll_offset = 0
	highlighted_index = -1


## Rebuild visible nodes for virtual mode based on current scroll_offset
func _rebuild_virtual_nodes() -> void:
	if not virtual_mode or not virtual_item_factory.is_valid():
		return

	var visible_start = scroll_offset
	var visible_end = mini(scroll_offset + visible_count, _virtual_data.size())

	# Return nodes outside visible range to pool
	var to_remove: Array[int] = []
	for idx in _virtual_visible_nodes:
		if idx < visible_start or idx >= visible_end:
			var node = _virtual_visible_nodes[idx] as Node3D
			if is_instance_valid(node):
				node.visible = false
				_virtual_node_pool.append(node)
			to_remove.append(idx)
	for idx in to_remove:
		_virtual_visible_nodes.erase(idx)

	# Create/update nodes for visible items
	var y_offset: float = 0.0
	for i in range(visible_start, visible_end):
		var data = _virtual_data[i]
		var existing_node: Node3D = _virtual_visible_nodes.get(i)

		# Reuse from pool if needed and available
		if existing_node == null and _virtual_node_pool.size() > 0:
			existing_node = _virtual_node_pool.pop_back()

		# Call factory to create or update the node
		var node: Node3D = virtual_item_factory.call(i, data, existing_node)

		# If factory returned a new node (not the existing one), add it as child
		if existing_node == null and node != null:
			add_child(node)

		if node:
			node.visible = true
			node.position.y = -y_offset
			_virtual_visible_nodes[i] = node

		y_offset += (virtual_item_height + item_spacing) * pixels_per_unit

	_update_scroll_indicators()

#endregion
