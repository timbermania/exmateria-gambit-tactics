@tool
class_name UIText
extends Node3D
## Text assembly using UIChar elements with top-left anchoring.
##
## Assembles UIChar meshes to render text in 3D space.
## Origin is at TOP-LEFT of first character; text flows RIGHT and DOWN.
##
## Supports:
## - Word wrapping with max_width
## - Tab alignment with {@N} commands
## - Typewriter effect via visible_chars
## - Multiple palette modes (MENU, STAT, CUSTOM)
##
## Vault: [[Dialogue Font Palette]]
## Vault: [[Display Message Opcode]]
## Vault: [[Typewriter Text Cadence]]

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

## #1271 — `DebugConfig` is a host autoload, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6), so the identifier is undefined in a
## stranger project. The flags were already `Tune` slugs; `UIDebug` reads them
## through the platform port. ADR-0308.
const UIDebug = preload("res://src/ui3/UIDebug.gd")

## The text to display
@export var text: String = "":
	set(value):
		if text == value:
			return  # Skip rebuild if unchanged
		text = value
		_rebuild_text()

## Font color/tint
@export var font_color: Color = Color.WHITE:
	set(value):
		font_color = value
		_update_color()

## World units per virtual pixel
@export var pixels_per_unit: float = 0.04:
	set(value):
		pixels_per_unit = value
		_rebuild_text()

## Pixel aspect ratio. Defaults to 1.25 per ADR-0036. (The citation used to read
## `= PSXDisplay.PAR`; that constant had zero readers and is deleted — ADR-0152.
## This 1.25 is an initial value: `PSXDisplay.live_ui_par` overwrites it on the
## first sync, and its own default is 1.0. Tracked as UI's, not Render's.)
## PSX-authored text needs the 1.25x horizontal stretch. Set to 1.0 for
## non-PSX UI. Authoring with PAR off and flipping later shifts every
## center- and right-aligned position; pick one and stick.
@export var pixel_aspect_ratio: float = 1.25:
	set(value):
		pixel_aspect_ratio = value
		_rebuild_text()

## Extra spacing between characters in virtual pixels
@export var character_spacing: float = 0.0:
	set(value):
		character_spacing = value
		_rebuild_text()

## Override width for space character in virtual pixels (-1 = use font default)
@export var space_width: float = -1.0:
	set(value):
		space_width = value
		_rebuild_text()

## Maximum width in virtual pixels before wrapping (-1 = no wrap)
@export var max_width: float = -1.0:
	set(value):
		max_width = value
		_rebuild_text()

## Line spacing in virtual pixels (added between lines)
@export var line_spacing: float = 2.0:
	set(value):
		line_spacing = value
		_rebuild_text()

## Number of visible characters (-1 = all visible, used for typewriter effect)
@export var visible_chars: int = -1:
	set(value):
		visible_chars = value
		_update_visibility()

## Material render priority for all characters (higher = renders on top)
@export var render_priority: int = 0:
	set(value):
		render_priority = value
		_update_render_priority()

## Font palette (MENU=0, STAT=1, CUSTOM=2)
@export var palette: UIChar.FontPalette = UIChar.FontPalette.MENU:
	set(value):
		if _current_palette == value and palette == value:
			return
		_current_palette = value
		palette = value
		_apply_palette(value)

## Text scale multiplier (alternative to using node transform scale)
@export var text_scale: float = 1.0:
	set(value):
		if text_scale == value:
			return
		text_scale = value
		scale = Vector3(text_scale, text_scale, 1.0)

var _font: UIFont
var _char_nodes: Array[UIChar] = []
var _line_count: int = 1
var _text_width: float = 0.0   # Width in world units
var _text_height: float = 0.0  # Height in world units
var _current_palette: UIChar.FontPalette = UIChar.FontPalette.MENU
var _custom_colors: Dictionary = {}
var _stroke_enabled: bool = false
var _stroke_color: Color = Color.BLACK
var _stroke_padding: float = 0.0


func _ready() -> void:
	UIChar._ensure_shared_resources()
	_font = UIChar._shared_font
	if not Engine.is_editor_hint():
		if not is_equal_approx(pixel_aspect_ratio, DisplayPort.live_ui_par()):
			pixel_aspect_ratio = DisplayPort.live_ui_par()
	_rebuild_text()
	if not Engine.is_editor_hint():
		# The is-connected guard lives on the port now — a re-added element runs
		# `_ready()` again and `Signal.connect` raises on a duplicate.
		DisplayPort.connect_live_ui_par_changed(_on_live_ui_par_changed)


func _on_live_ui_par_changed(value: float) -> void:
	pixel_aspect_ratio = value


## Force a rebuild of all characters (useful when font mappings change)
func refresh() -> void:
	_rebuild_text()


func _rebuild_text() -> void:
	# Clear existing character nodes
	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.queue_free()
	_char_nodes.clear()
	_line_count = 1
	_text_width = 0.0
	_text_height = 0.0

	if not _font or text.is_empty():
		return

	# Split on explicit newlines first, then word-wrap each segment
	var raw_lines = text.split("\n")
	var lines: Array[String] = []
	for raw_line in raw_lines:
		if max_width > 0:
			lines.append_array(_wrap_text(raw_line, max_width))
		else:
			lines.append(raw_line)

	_line_count = lines.size()

	# Create character nodes for each line
	# Origin is at top-left, so y_offset starts at 0 and goes negative
	var y_offset: float = 0.0
	var max_line_width: float = 0.0
	var char_height_world = _font.char_height * pixels_per_unit

	for line_idx in range(lines.size()):
		var line = lines[line_idx]
		var x_offset: float = 0.0
		var i: int = 0

		while i < line.length():
			# Check for tab command: {@N} - jump to pixel position N
			if i + 2 < line.length() and line[i] == "{" and line[i + 1] == "@":
				var end_brace = line.find("}", i + 2)
				if end_brace > i + 2:
					var num_str = line.substr(i + 2, end_brace - i - 2)
					if num_str.is_valid_int():
						var target_px = float(int(num_str))
						# Jump to target pixel position (apply PAR since it's in virtual pixels)
						x_offset = target_px * pixel_aspect_ratio * pixels_per_unit
						if UIDebug.iteration():
							print("[UIText] {@%d} -> x_offset=%.3f" % [int(target_px), x_offset])
						i = end_brace + 1
						continue

			var c = line[i]
			var char_node = UIChar.new()
			char_node.character = c
			char_node.font_color = font_color
			char_node.pixels_per_unit = pixels_per_unit
			char_node.pixel_aspect_ratio = pixel_aspect_ratio
			char_node.render_priority = render_priority

			# Position character (top-left anchoring: y goes negative)
			char_node.position.x = x_offset
			char_node.position.y = y_offset

			add_child(char_node)
			_char_nodes.append(char_node)

			# Apply current palette to new char
			_apply_palette_to_char(char_node)

			# Advance by character's actual width + spacing
			var display_width = _get_space_width() if c == " " else _font.get_char_width(c)
			var stroke_extra = _stroke_padding * 2.0
			x_offset += ((display_width + stroke_extra) * pixel_aspect_ratio + character_spacing) * pixels_per_unit
			i += 1

		# Track maximum line width
		if x_offset > max_line_width:
			max_line_width = x_offset

		# Move down for next line (negative Y = down in 3D space)
		if line_idx < lines.size() - 1:
			y_offset -= char_height_world + (line_spacing * pixels_per_unit)

	# Calculate total text dimensions
	_text_width = max_line_width
	_text_height = char_height_world * _line_count + (line_spacing * pixels_per_unit) * (_line_count - 1)

	# Apply visibility setting to new nodes
	_update_visibility()


func _get_space_width() -> float:
	if space_width >= 0:
		return space_width
	return _font.get_char_width(" ")


func _wrap_text(input_text: String, wrap_width: float) -> Array[String]:
	var lines: Array[String] = []
	var effective_space_width = _get_space_width() + character_spacing

	# Count and preserve leading spaces
	var leading_spaces = 0
	for c in input_text:
		if c == " ":
			leading_spaces += 1
		else:
			break

	var leading_space_str = " ".repeat(leading_spaces)
	var trimmed_text = input_text.substr(leading_spaces)

	if trimmed_text.is_empty():
		if leading_spaces > 0:
			lines.append(input_text)
		return lines

	var words = trimmed_text.split(" ")
	var current_line = leading_space_str
	var current_width: float = leading_spaces * effective_space_width * pixel_aspect_ratio
	var pending_spaces: int = 0

	for word in words:
		if word.is_empty():
			pending_spaces += 1
			continue

		var word_width = _measure_word(word)
		var spaces_to_add = maxi(pending_spaces, 1) if current_line != leading_space_str else 0
		var spaces_width = spaces_to_add * effective_space_width * pixel_aspect_ratio

		if current_line == leading_space_str:
			current_line += word
			current_width += word_width
		elif current_width + spaces_width + word_width <= wrap_width:
			current_line += " ".repeat(spaces_to_add) + word
			current_width += spaces_width + word_width
		else:
			lines.append(current_line)
			current_line = word
			current_width = word_width

		pending_spaces = 0

	if not current_line.is_empty():
		lines.append(current_line)

	return lines


func _measure_word(word: String) -> float:
	var width: float = 0.0
	var stroke_extra = _stroke_padding * 2.0
	for i in range(word.length()):
		width += (_font.get_char_width(word[i]) + stroke_extra) * pixel_aspect_ratio
		if i < word.length() - 1:
			width += character_spacing
	return width


func _update_color() -> void:
	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.font_color = font_color


## Tint a contiguous run of characters `[start, end)` (indices into the
## character-node list, which EXCLUDES newlines) to `color`. Applied on top of
## the active palette as a per-char `font_color` multiply. Used for rich-text
## runs such as DialogueBox's `{Color 08}` speaker-name header. Note: a
## `_rebuild_text()` resets every char back to the global `font_color`, so
## re-apply runs after any rebuild.
func set_char_color_run(start: int, end: int, color: Color) -> void:
	var lo := maxi(0, start)
	var hi := mini(end, _char_nodes.size())
	for i in range(lo, hi):
		if is_instance_valid(_char_nodes[i]):
			_char_nodes[i].font_color = color


## Recolor a contiguous run `[start, end)` (char-node indices, newlines
## excluded) via the shader's 3-level CUSTOM remap: the baked atlas body ramp
## (slots 1-3) is replaced by (`light`,`mid`,`dark`) per glyph-pixel level. This
## is how DialogueBox paints the `{Color 08}` speaker name in the real ROM
## speaker ramp (CLUT slots 9-11) — a faithful index-offset, not a tint.
## `dark`/`mid`/`light` replace baked px3/px2/px1 respectively.
func set_char_clut_run(start: int, end: int, dark: Color, mid: Color, light: Color) -> void:
	var lo := maxi(0, start)
	var hi := mini(end, _char_nodes.size())
	for i in range(lo, hi):
		if is_instance_valid(_char_nodes[i]):
			_char_nodes[i].font_color = Color.WHITE
			_char_nodes[i].set_custom_colors(dark, mid, light)


## Reset a contiguous run `[start, end)` to render the atlas directly — the
## ROM dialog BODY ramp (CLUT slots 1-3), MENU palette, no tint. Used for the
## `{Color 00}` body run.
func set_char_plain_run(start: int, end: int) -> void:
	var lo := maxi(0, start)
	var hi := mini(end, _char_nodes.size())
	for i in range(lo, hi):
		if is_instance_valid(_char_nodes[i]):
			_char_nodes[i].font_color = Color.WHITE
			_char_nodes[i].set_palette(UIChar.FontPalette.MENU)


## Number of character nodes (excludes newlines). Exposes the typewriter
## reveal range for `visible_chars`.
func get_char_node_count() -> int:
	return _char_nodes.size()


func _update_visibility() -> void:
	for i in range(_char_nodes.size()):
		if is_instance_valid(_char_nodes[i]):
			_char_nodes[i].visible = (visible_chars < 0 or i < visible_chars)


func _update_render_priority() -> void:
	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.render_priority = render_priority


func _apply_palette_to_char(char_node: UIChar) -> void:
	if _current_palette == UIChar.FontPalette.CUSTOM and not _custom_colors.is_empty():
		char_node.set_custom_colors(
			_custom_colors.get("dark", Color.BLACK),
			_custom_colors.get("mid", Color.GRAY),
			_custom_colors.get("light", Color.WHITE)
		)
		char_node.set_stroke(_stroke_enabled, _stroke_color)
	else:
		char_node.set_palette(_current_palette)
		# Apply explicit stroke for non-STAT palettes
		if _current_palette != UIChar.FontPalette.STAT:
			char_node.set_stroke(_stroke_enabled, _stroke_color)


## Get the size of the text in world units
func get_text_size() -> Vector2:
	return Vector2(_text_width, _text_height)


## Get the width of the text in world units
## Get the height of the text in world units
## Get the number of lines
## Get the total number of characters
## Show all characters instantly
## Set the font color palette for all characters
func set_palette(new_palette: UIChar.FontPalette) -> void:
	palette = new_palette  # Goes through property setter


func _apply_palette(new_palette: UIChar.FontPalette) -> void:
	_custom_colors.clear()

	# Update stroke padding based on palette
	var new_stroke_padding = 1.0 if new_palette == UIChar.FontPalette.STAT else 0.0
	var needs_rebuild = new_stroke_padding != _stroke_padding
	_stroke_padding = new_stroke_padding

	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.set_palette(new_palette)

	if needs_rebuild:
		_rebuild_text()


## Set custom palette colors for all characters
## dark/mid/light replace the corresponding atlas colors by nearest-match
func set_custom_colors(dark: Color, mid: Color, light: Color) -> void:
	_current_palette = UIChar.FontPalette.CUSTOM
	_custom_colors = {"dark": dark, "mid": mid, "light": light}
	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.set_custom_colors(dark, mid, light)


## Enable/disable stroke outline around all characters
func set_stroke(enabled: bool, color: Color = Color.BLACK) -> void:
	_stroke_enabled = enabled
	_stroke_color = color

	var new_stroke_padding = 1.0 if enabled else 0.0
	var needs_rebuild = new_stroke_padding != _stroke_padding
	_stroke_padding = new_stroke_padding

	for char_node in _char_nodes:
		if is_instance_valid(char_node):
			char_node.set_stroke(enabled, color)

	if needs_rebuild:
		_rebuild_text()


## Get current palette
func get_palette() -> UIChar.FontPalette:
	return _current_palette
