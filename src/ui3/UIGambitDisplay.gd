@tool
class_name UIGambitDisplay
extends UIWindow
## Gambit display component showing multiple gambit rows with sentence-based text.
##
## Uses @export properties with setters for all configuration.
## Origin is at TOP-LEFT; rows extend DOWN.
##
## Each row contains:
## - UIFrame (background)
## - UIText for row number ("1.", "2.", etc.)
## - 6 UIText sentence lines matching UI2 format:
##   - Line 0: Action (e.g., "Cure Them")
##   - Line 1: When + Target (e.g., "when Nearest Ally Unit")
##   - Lines 2-5: Conditions (e.g., "is HP < 50%", "and MP > 20%", etc.)
## - UIClickableField (if enable_click_areas)

## Emitted when a gambit row is clicked
signal row_clicked(row_index: int)

#region Configuration Exports


## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_mark_layout_dirty()

## Number of gambit rows to display
@export var row_count: int = 4:
	set(value):
		var new_count = maxi(0, value)
		if row_count == new_count:
			return
		row_count = new_count
		_rebuild_rows()
		_mark_layout_dirty()

## Spacing between rows in virtual pixels
@export var row_spacing: float = 2.0:
	set(value):
		if row_spacing == value:
			return
		row_spacing = value
		_mark_layout_dirty()

#endregion

#region Frame Configuration

@export_group("Frame")

## Show the dialog frame around each row
@export var show_frame: bool = true:
	set(value):
		if show_frame == value:
			return
		show_frame = value
		_apply_frame_settings()

## Size of each row frame in virtual pixels (145 x 50 for 6 sentence lines)
@export var frame_size: Vector2 = Vector2(145, 50):
	set(value):
		if frame_size == value:
			return
		frame_size = value
		_apply_frame_settings()
		_mark_layout_dirty()

#endregion

#region Text Configuration

@export_group("Text")

## Position offset for row number text (e.g., "1.")
@export var number_offset: Vector2 = Vector2(10, -3):
	set(value):
		if number_offset == value:
			return
		number_offset = value
		_apply_text_settings()

## Number text scale (separate from sentence line scale)
@export var number_scale: float = 0.7:
	set(value):
		if number_scale == value:
			return
		number_scale = value
		_apply_text_settings()

## Text scale multiplier
@export var text_scale: float = 0.6:
	set(value):
		if text_scale == value:
			return
		text_scale = value
		_apply_text_settings()

## Font palette (0=MENU, 1=STAT, etc.)
@export var text_palette: int = 0:
	set(value):
		if text_palette == value:
			return
		text_palette = value
		_apply_text_settings()

## Space character width in pixels (-1.0 for font default)
@export var text_space_width: float = 1.0:
	set(value):
		if text_space_width == value:
			return
		text_space_width = value
		_apply_text_settings()

#endregion

#region Click Area Configuration

@export_group("Click Areas")

## Enable click areas on rows
@export var enable_click_areas: bool = true:
	set(value):
		if enable_click_areas == value:
			return
		enable_click_areas = value
		_rebuild_click_areas()

## Show debug visualization for click areas
@export var show_click_area_debug: bool = false:
	set(value):
		if show_click_area_debug == value:
			return
		show_click_area_debug = value
		_update_click_area_debug_visibility()

#endregion

#region Sentence Line Configuration

@export_group("Sentence Lines")

## Position offset for first sentence line (action line)
@export var sentence_start_offset: Vector2 = Vector2(22, 0):
	set(value):
		if sentence_start_offset == value:
			return
		sentence_start_offset = value
		_mark_layout_dirty()

## Vertical spacing between sentence lines
@export var sentence_line_spacing: float = 7.0:
	set(value):
		if sentence_line_spacing == value:
			return
		sentence_line_spacing = value
		_mark_layout_dirty()

#endregion

#region Internal State

## Internal row data structure
class GambitRow:
	var frame: UIFrame
	var number_text: UIText
	var sentence_lines: Array[UIText] = []  # 6 sentence line texts
	var click_area: UIClickableField

var _rows: Array[GambitRow] = []

#endregion


func _build_children() -> void:
	_rebuild_rows()


#region Row Management

func _rebuild_rows() -> void:
	# Remove excess rows
	while _rows.size() > row_count:
		var row = _rows.pop_back()
		_free_row(row)

	# Add new rows
	while _rows.size() < row_count:
		var row = _create_row(_rows.size())
		_rows.append(row)

	_apply_frame_settings()
	_apply_text_settings()
	_rebuild_click_areas()


func _create_row(index: int) -> GambitRow:
	var row = GambitRow.new()

	# Create frame
	row.frame = UIFrame.new()
	row.frame.frame_size = frame_size
	row.frame.visible = show_frame
	add_child(row.frame)

	# Create number text
	row.number_text = UIText.new()
	row.number_text.text = "%d." % (index + 1)
	add_child(row.number_text)

	# Create 6 sentence line texts (matching UI2 gambit format)
	# Line 0: Action (e.g., "Cure Them")
	# Line 1: When + Target (e.g., "when Nearest Ally Unit")
	# Line 2-5: Conditions (e.g., "is HP < 50%", "and MP > 20%", etc.)
	for i in range(6):
		var line_text = UIText.new()
		line_text.text = ""
		add_child(line_text)
		row.sentence_lines.append(line_text)

	return row


func _free_row(row: GambitRow) -> void:
	if row.frame and is_instance_valid(row.frame):
		row.frame.queue_free()
	if row.number_text and is_instance_valid(row.number_text):
		row.number_text.queue_free()
	for line_text in row.sentence_lines:
		if line_text and is_instance_valid(line_text):
			line_text.queue_free()
	row.sentence_lines.clear()
	if row.click_area and is_instance_valid(row.click_area):
		row.click_area.queue_free()


func _apply_frame_settings() -> void:
	for row in _rows:
		if row.frame and is_instance_valid(row.frame):
			row.frame.frame_size = frame_size
			row.frame.pixels_per_unit = pixels_per_unit
			row.frame.visible = show_frame


func _apply_text_settings() -> void:
	var ppu_scaled = pixels_per_unit * text_scale
	var ppu_number = pixels_per_unit * number_scale
	var palette_enum = text_palette as UIChar.FontPalette

	for i in range(_rows.size()):
		var row = _rows[i]

		# Number text (uses number_scale instead of text_scale)
		if row.number_text and is_instance_valid(row.number_text):
			row.number_text.text = "%d." % (i + 1)
			row.number_text.pixels_per_unit = ppu_number
			row.number_text.space_width = text_space_width
			row.number_text.set_palette(palette_enum)

		# Sentence line texts (6 lines per row)
		for line_text in row.sentence_lines:
			if line_text and is_instance_valid(line_text):
				line_text.pixels_per_unit = ppu_scaled
				line_text.space_width = text_space_width
				line_text.set_palette(palette_enum)

	_mark_layout_dirty()


func _update_layout() -> void:
	var row_height = frame_size.y + row_spacing

	for i in range(_rows.size()):
		var row = _rows[i]
		var y_offset = -i * row_height * pixels_per_unit

		# Position frame
		if row.frame and is_instance_valid(row.frame):
			row.frame.position = Vector3(0, y_offset, -0.01)
			row.frame.pixels_per_unit = pixels_per_unit

		# Position number text
		if row.number_text and is_instance_valid(row.number_text):
			row.number_text.position = Vector3(
				number_offset.x * pixels_per_unit,
				y_offset - number_offset.y * pixels_per_unit,
				0.01
			)

		# Position sentence lines (6 lines per row)
		for line_idx in range(row.sentence_lines.size()):
			var line_text = row.sentence_lines[line_idx]
			if line_text and is_instance_valid(line_text):
				line_text.position = Vector3(
					sentence_start_offset.x * pixels_per_unit,
					y_offset - (sentence_start_offset.y + line_idx * sentence_line_spacing) * pixels_per_unit,
					0.01
				)

	_update_click_area_positions()

#endregion


#region Click Area Management

func _rebuild_click_areas() -> void:
	# Clear existing click areas
	for row in _rows:
		if row.click_area and is_instance_valid(row.click_area):
			row.click_area.queue_free()
			row.click_area = null

	if not enable_click_areas:
		return

	# Create click areas for each row
	for i in range(_rows.size()):
		var row = _rows[i]
		var click_area = UIClickableField.new()
		add_child(click_area)
		click_area.clicked.connect(_on_click_area_clicked)
		row.click_area = click_area

	_update_click_area_positions()


func _update_click_area_positions() -> void:
	if not enable_click_areas:
		return

	var row_height = frame_size.y + row_spacing

	for i in range(_rows.size()):
		var row = _rows[i]
		if not row.click_area or not is_instance_valid(row.click_area):
			continue

		var y_offset_px = i * row_height

		# Click area covers the entire row
		var rect = Rect2(
			0,
			y_offset_px,
			frame_size.x,
			frame_size.y
		)

		row.click_area.configure("gambit_row", i, rect, pixels_per_unit, show_click_area_debug)


func _update_click_area_debug_visibility() -> void:
	for row in _rows:
		if row.click_area and is_instance_valid(row.click_area):
			row.click_area.set_debug_visible(show_click_area_debug)


func _on_click_area_clicked(_field_type: String, field_index: int) -> void:
	row_clicked.emit(field_index)

#endregion


#region Public API

## Update a gambit row's sentence lines (6 lines from GambitProse.sentence_lines())
## lines[0] = Action (e.g., "Cure Them")
## lines[1] = When + Target (e.g., "when Nearest Ally Unit")
## lines[2-5] = Conditions (e.g., "is HP < 50%", "and MP > 20%", etc.)
func update_row_lines(index: int, lines: Array) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row = _rows[index]
	for i in range(mini(lines.size(), row.sentence_lines.size())):
		if row.sentence_lines[i] and is_instance_valid(row.sentence_lines[i]):
			row.sentence_lines[i].text = lines[i] if lines[i] else ""
	# Clear remaining lines if array is shorter
	for i in range(lines.size(), row.sentence_lines.size()):
		if row.sentence_lines[i] and is_instance_valid(row.sentence_lines[i]):
			row.sentence_lines[i].text = ""


## Legacy 2-line API for compatibility (maps to 6-line format)
## Clear all rows to default "---" text on first line only
func clear_rows() -> void:
	for row in _rows:
		# Set first line to "---", clear the rest
		if row.sentence_lines.size() > 0 and row.sentence_lines[0] and is_instance_valid(row.sentence_lines[0]):
			row.sentence_lines[0].text = "---"
		for i in range(1, row.sentence_lines.size()):
			if row.sentence_lines[i] and is_instance_valid(row.sentence_lines[i]):
				row.sentence_lines[i].text = ""


## Get the number of rows
func get_row_count() -> int:
	return _rows.size()


## Set visibility of all click area debug meshes
func set_click_areas_visible(debug_visible: bool) -> void:
	show_click_area_debug = debug_visible

#endregion


#region Editor Preview

func _populate_editor_preview() -> void:
	update_row_lines(0, ["Cure Them", "when Nearest Ally Unit", "is HP < 50%", "", "", ""])
	update_row_lines(1, ["Attack", "when Nearest Enemy Unit", "is HP < 70%", "and Self MP > 20%", "", ""])
	update_row_lines(2, ["Throw Stone", "when Farthest Enemy Unit", "", "", "", ""])
	update_row_lines(3, ["---", "", "", "", "", ""])

#endregion
