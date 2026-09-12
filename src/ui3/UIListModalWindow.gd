@tool
class_name UIListModalWindow
extends UIModalWindow
## A modal window whose content is a single scrollable list of typed rows —
## the shape the equipment / job / ability pickers share. Subclasses declare
## their own row type (a RefCounted inner class) and override three hooks:
##
##   build_rows(...) -> Array        # query database -> rows (called by subclass)
##   _columns() -> Array             # declare the row's column schema
##   _on_picked(row)                 # emit the picker's typed signal
##   _preview_rows() -> Array        # editor-preview rows (defaults to [])
##
## The base owns the row skeleton (container + Content + ClickableField), data
## ingress (`set_rows`), selection routing (both keyboard-Enter and mouse-click
## funnel into `_dispatch_pick` → `_on_picked` → `close`), frame sizing, and the
## editor-preview path. Subclasses no longer wire either click pathway.
##
## Subclass entry points (`show_for_*`) store per-picker state and call
## `_open_with_rows(rows, title, world_pos)`. See CONTEXT.md "Combat UI windows".


## Canonical defaults - update these when tuning values in editor
const _CODE_DEFAULTS = {
	"menu_width": 210.0,
	"item_spacing": 0.0,
	"content_offset": Vector2(8, 8),
	"padding_bottom": 3.0,
	"item_height": 12.0,
	"title_offset": Vector2(4, -4),
}

#region Configuration Exports


## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Overall scale multiplier
@export var assembly_scale: float = 1.0:
	set(value):
		if assembly_scale == value:
			return
		assembly_scale = value
		_mark_layout_dirty()

## Width of the popup in virtual pixels
@export var menu_width: float = 210.0:
	set(value):
		if menu_width == value:
			return
		menu_width = value
		_mark_layout_dirty()

## Maximum number of visible items
@export var max_visible_items: int = 12:
	set(value):
		if max_visible_items == value:
			return
		max_visible_items = value
		_push(_scroll_list, &"visible_count", value)
		_mark_layout_dirty()

## Spacing between items in virtual pixels
@export var item_spacing: float = 0.0:
	set(value):
		if item_spacing == value:
			return
		item_spacing = value
		_push(_scroll_list, &"item_spacing", value)
		_mark_layout_dirty()

## Content offset from frame top-left
@export var content_offset: Vector2 = Vector2(8, 8):
	set(value):
		if content_offset == value:
			return
		content_offset = value
		_mark_layout_dirty()

## Bottom padding after items
@export var padding_bottom: float = 3.0:
	set(value):
		if padding_bottom == value:
			return
		padding_bottom = value
		_mark_layout_dirty()

## Show the frame background
@export var show_frame: bool = true:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		_push(_frame, &"visible", value)

#endregion

#region Title Configuration

@export_group("Title")

## Title text
@export var title_text: String = "Select Item":
	set(value):
		if title_text == value:
			return
		title_text = value
		_push(_title, &"text", value)

## Title offset from top-left
@export var title_offset: Vector2 = Vector2(4, -4):
	set(value):
		if title_offset == value:
			return
		title_offset = value
		_mark_layout_dirty()

## Title text scale
@export var title_scale: float = 0.7:
	set(value):
		if title_scale == value:
			return
		title_scale = value
		_mark_layout_dirty()

## Title text palette (1 = STAT for titles)
@export var title_palette: int = 1:
	set(value):
		if title_palette == value:
			return
		title_palette = value
		if _title:
			_title.set_palette(title_palette)

#endregion

#region Item Text Configuration

@export_group("Items")

## Item text scale
@export var item_scale: float = 0.7:
	set(value):
		if item_scale == value:
			return
		item_scale = value
		_mark_layout_dirty()

## Item text palette
@export var item_palette: int = 0:
	set(value):
		if item_palette == value:
			return
		item_palette = value
		_mark_layout_dirty()

## Item row height in virtual pixels
@export var item_height: float = 12.0:
	set(value):
		if item_height == value:
			return
		item_height = value
		_push(_scroll_list, &"virtual_item_height", value)
		_mark_layout_dirty()

## Space width for text elements (1.0 = consistent FFT style)
@export var text_space_width: float = 1.0:
	set(value):
		if text_space_width == value:
			return
		text_space_width = value
		_mark_layout_dirty()

#endregion

#region Internal State

var _frame: UIFrame
var _title: UIText
var _scroll_list: UIScrollableList
var _click_outside_area: Area3D

#endregion


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		_check_defaults_sync()
	visible = false


## Check if scene values differ from code defaults and print warnings
func _check_defaults_sync() -> void:
	var defaults = _get_all_defaults()
	for prop in defaults:
		var scene_value = get(prop)
		var code_default = defaults[prop]
		if not _values_equal(scene_value, code_default):
			print("[%s] Sync needed: %s = %s (code default: %s)" % [
				name, prop, scene_value, code_default
			])


## Override in subclasses to add subclass-specific defaults
func _get_all_defaults() -> Dictionary:
	return _CODE_DEFAULTS.duplicate()


## Compare values handling Vector2 properly
func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Vector2:
		return a.is_equal_approx(b)
	return a == b


func _build_children() -> void:
	# Frame background
	_frame = UIFrame.new()
	_frame.pixels_per_unit = pixels_per_unit
	_frame.visible = show_frame
	_frame.position.z = -0.01  # Behind content
	add_child(_frame)

	# Title text
	_title = UIText.new()
	_title.text = title_text
	_title.pixels_per_unit = pixels_per_unit * title_scale
	_title.space_width = text_space_width
	_title.set_palette(title_palette)
	add_child(_title)

	# Scrollable list — virtual mode only; the row skeleton is owned here.
	_scroll_list = UIScrollableList.new()
	_scroll_list.virtual_mode = true
	_scroll_list.virtual_item_factory = _skeleton_factory
	_scroll_list.virtual_item_height = item_height
	_scroll_list.pixels_per_unit = pixels_per_unit
	_scroll_list.visible_count = max_visible_items
	_scroll_list.item_spacing = item_spacing
	_scroll_list.show_scroll_indicators = false
	_scroll_list.item_selected.connect(_on_keyboard_pick)
	_scroll_list.cancelled.connect(close)
	add_child(_scroll_list)

	# Click outside detection
	_setup_click_outside_detection()


func _setup_click_outside_detection() -> void:
	_click_outside_area = Area3D.new()
	_click_outside_area.input_ray_pickable = false  # Start disabled, enable when opened
	_click_outside_area.monitoring = false

	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 0.01)
	collision.shape = box
	_click_outside_area.add_child(collision)
	_click_outside_area.position.z = -0.1  # Behind frame

	_click_outside_area.input_event.connect(_on_outside_click)
	add_child(_click_outside_area)


func _update_layout() -> void:
	var ppu = pixels_per_unit * assembly_scale

	if _frame:
		_frame.pixels_per_unit = ppu
		var calculated_height = content_offset.y + _calculate_items_height() + padding_bottom
		_frame.frame_size = Vector2(menu_width, calculated_height)

	if _title:
		_title.pixels_per_unit = ppu * title_scale
		_title.position = Vector3(
			title_offset.x * ppu,
			-title_offset.y * ppu,
			0.01
		)

	if _scroll_list:
		_scroll_list.pixels_per_unit = ppu
		_scroll_list.position = Vector3(
			content_offset.x * ppu,
			-content_offset.y * ppu,
			0.0
		)


func _calculate_items_height() -> float:
	var count = mini(_scroll_list.get_item_count() if _scroll_list else 0, max_visible_items)
	if count <= 0:
		count = max_visible_items  # Use max for default sizing
	return count * item_height + (count - 1) * item_spacing


#region Public API — typed-row contract

## Replace the list contents with a typed row array. The element type is
## subclass-defined (a RefCounted inner class); the base only forwards it to
## the scroll list and resizes the frame.
func set_rows(rows: Array) -> void:
	if not _scroll_list:
		return
	_scroll_list.set_virtual_data(rows)
	_update_frame_size()


## Subclass entry-point helper. Stores the title, replaces the rows, opens.
## Subclass `show_for_*` methods call this after storing their picker-specific
## state (e.g. `_current_slot`, `_current_unit`).
func _open_with_rows(rows: Array, new_title: String, world_position: Vector3 = Vector3.ZERO) -> void:
	title_text = new_title
	set_rows(rows)
	open_at(world_position)


## Open the popup at an optional world position. Sub-entry points usually call
## `_open_with_rows` instead. Named `open_at` (not `open`) since the UIComponent
## base-swap (ADR-0088 Amendment 5) — `UI3Element.open()` is the transition verb.
func open_at(world_position: Vector3 = Vector3.ZERO) -> void:
	if world_position != Vector3.ZERO:
		position = world_position
	visible = true
	if _click_outside_area:
		_click_outside_area.input_ray_pickable = true
	if _scroll_list:
		_scroll_list.activate()


## Teardown before hiding (base UIModalWindow.close() hides + emits closed).
func _on_closing() -> void:
	if _click_outside_area:
		_click_outside_area.input_ray_pickable = false
	if _scroll_list:
		_scroll_list.deactivate()
		_scroll_list.clear_virtual_data()


## Number of rows currently in the list.
func get_row_count() -> int:
	return _scroll_list.get_item_count() if _scroll_list else 0

#endregion


#region Subclass hooks

## Override to handle a selection. Both keyboard-Enter and mouse-click on a row
## funnel here, with `row` being the typed payload the subclass passed to
## `set_rows`. `close()` is called automatically after this returns.
func _on_picked(_row: Variant) -> void:
	pass


## Declare the row's column schema. Each column is a Dictionary:
##   "child":           StringName  — child node name under `content` (required)
##   "field":           StringName  — row property to read; expected String (required)
##   "offset_x_prop":   StringName  — @export name to read for x offset
##                                    (default ""; "" means don't touch position.x)
##   "scale_prop":      StringName  — @export name to read for scale (default "item_scale")
##   "palette_prop":    StringName  — @export name to read for palette (default "item_palette")
##   "hide_when_empty": bool        — hide the node when value is "" (default false)
##
## Row classes carry pre-formatted display strings (not raw values) for any field
## a column references — the schema is data, not code. Mirrors ADR-0016's
## `const`-without-`extract`-Callable rule for the gambit encode schema.
func _columns() -> Array:
	return []


## Renders a row by looping `_columns()`. Subclasses typically override `_columns`
## instead of this. For custom layouts that don't fit the column model, overriding
## `_render_row` itself is the escape hatch.
func _render_row(row: Variant, content: Node3D) -> void:
	if row == null:
		return
	var ppu: float = pixels_per_unit * assembly_scale
	for col in _columns():
		_render_column(row, content, col, ppu)


func _render_column(row: Variant, content: Node3D, col: Dictionary, ppu: float) -> void:
	var field: StringName = col["field"]
	var value: String = str(row.get(field))
	var scale: float = float(get(col.get("scale_prop", &"item_scale")))
	var palette: int = int(get(col.get("palette_prop", &"item_palette")))
	var off_prop: StringName = col.get("offset_x_prop", &"")
	var offset_x_px: float = NAN if off_prop == &"" else float(get(off_prop))
	UIRowColumnRenderer.paint(
		content, col["child"], value,
		ppu, scale, palette, text_space_width,
		offset_x_px, col.get("hide_when_empty", false),
	)


## Override to supply rows for the editor preview. Called by
## `_populate_editor_preview` so the editor path uses the same rendering as
## runtime.
func _preview_rows() -> Array:
	return []

#endregion


#region Internal — skeleton factory & selection routing

## The virtual_item_factory the scroll list calls per visible row. The base
## owns the container + Content node + click area; subclass renders into Content.
func _skeleton_factory(idx: int, row: Variant, existing: Node3D) -> Node3D:
	var node: Node3D = existing if existing else _make_row_skeleton()
	# Re-bind click area to this row's index (binding is per-row, factory may
	# pull a node from the pool that was bound to a different index).
	var click := node.get_node("ClickArea") as UIClickableField
	if click:
		var ppu = pixels_per_unit * assembly_scale
		click.configure("row", idx, Rect2(0, 0, menu_width - 16, item_height), ppu, false)
		for c in click.clicked.get_connections():
			click.clicked.disconnect(c.callable)
		click.clicked.connect(_on_row_clicked.bind(idx))

	var content := node.get_node("Content") as Node3D
	_render_row(row, content)
	return node


func _make_row_skeleton() -> Node3D:
	var node = Node3D.new()

	var content = Node3D.new()
	content.name = "Content"
	node.add_child(content)

	var click = UIClickableField.new()
	click.name = "ClickArea"
	node.add_child(click)

	return node


## Mouse-click on a row.
func _on_row_clicked(_field_type: String, _field_index: int, row_index: int) -> void:
	_dispatch_pick(row_index)


## Keyboard-Enter on a highlighted row.
func _on_keyboard_pick(row_index: int, _row_data: Variant) -> void:
	_dispatch_pick(row_index)


## Single funnel for any selection. Looks up the typed row from the scroll
## list, hands it to the subclass, then closes.
func _dispatch_pick(row_index: int) -> void:
	if row_index < 0 or row_index >= _scroll_list.get_item_count():
		return
	var row: Variant = _scroll_list.get_item_data(row_index)
	_on_picked(row)
	close()


func _update_frame_size() -> void:
	if _frame:
		var calculated_height = content_offset.y + _calculate_items_height() + padding_bottom
		_frame.frame_size = Vector2(menu_width, calculated_height)


func _on_outside_click(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			close()

#endregion


## Override of UIComponent's editor-preview hook. Calls subclass `_preview_rows`
## so the editor path drives the same `_render_row` the runtime does.
func _populate_editor_preview() -> void:
	if _scroll_list:
		_scroll_list.clear_virtual_data()
	set_rows(_preview_rows())


#region Input Handling

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

#endregion
