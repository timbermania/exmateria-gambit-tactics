class_name CompassOverlay
extends Control

## Screen-space compass that projects the four world cardinal directions
## through the live camera transform, so you stay oriented while the
## isometric camera pans/rotates/tilts during a scenario.
##
## World convention (godot-learning/CLAUDE.md):
##   +X = NORTH, -X = SOUTH, +Z = EAST, -Z = WEST, +Y = UP.
##
## Each cardinal's on-screen heading is `(d·camRight, -d·camUp)` — exactly the
## direction you'd move on screen if you walked that way. Normalized to a fixed
## radius so all four labels sit on the dial regardless of camera tilt; the
## marker's opacity dims as a direction tilts away from the screen plane (into
## or out of the screen) so foreshortening reads as fade, not a misleading
## squash. NORTH is drawn red, the rest white. Each cardinal also carries its
## signed world-axis (`+X`/`-X`/`+Z`/`-Z`) as a secondary label so you never
## have to guess which of X/Z maps to which direction.

const _RADIUS := 34.0
const _MARGIN := Vector2(58, 58)  # from the top-right corner to the dial center

var _camera: Camera3D = null

const _CARDINALS := [
	{"label": "N", "axis": "+X", "dir": Vector3(1, 0, 0), "color": Color(1.0, 0.30, 0.25)},
	{"label": "E", "axis": "+Z", "dir": Vector3(0, 0, 1), "color": Color(0.95, 0.95, 0.95)},
	{"label": "S", "axis": "-X", "dir": Vector3(-1, 0, 0), "color": Color(0.95, 0.95, 0.95)},
	{"label": "W", "axis": "-Z", "dir": Vector3(0, 0, -1), "color": Color(0.95, 0.95, 0.95)},
]


func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)


func _process(_delta: float) -> void:
	if _camera != null:
		queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	# Dial center: inset from the control's right edge (top-right corner).
	var center := Vector2(size.x - _MARGIN.x, _MARGIN.y)
	var font := ThemeDB.fallback_font
	var font_size := 15

	# Dial backdrop + ring.
	draw_circle(center, _RADIUS + 8.0, Color(0, 0, 0, 0.45))
	draw_arc(center, _RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.5, true)

	var basis := _camera.global_transform.basis
	var cam_right := basis.x
	var cam_up := basis.y

	for c in _CARDINALS:
		var d: Vector3 = c["dir"]
		var sx := d.dot(cam_right)
		var sy := -d.dot(cam_up)
		var screen := Vector2(sx, sy)
		if screen.length() < 0.0001:
			# Direction points straight into/out of the screen — no heading.
			continue
		var dir2 := screen.normalized()
		# Tilt-into-screen factor: 1.0 when the direction lies in the screen
		# plane, →0 as it points along the camera's view axis.
		var alpha: float = clampf(screen.length(), 0.25, 1.0)
		var col: Color = c["color"]
		col.a = alpha
		var tip := center + dir2 * _RADIUS
		draw_line(center, tip, col, 2.0, true)
		var label_pos := center + dir2 * (_RADIUS + 11.0)
		var ts := font.get_string_size(c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, label_pos - ts * 0.5 + Vector2(0, ts.y * 0.35),
			c["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
		# Secondary signed-axis tag (+X/-X/+Z/-Z) just beyond the letter, so the
		# X<->NS / Z<->EW mapping is always visible on the dial.
		var axis_size := 10
		var axis_col := col
		axis_col.a = col.a * 0.85
		var axis_pos := center + dir2 * (_RADIUS + 23.0)
		var axs := font.get_string_size(c["axis"], HORIZONTAL_ALIGNMENT_LEFT, -1, axis_size)
		draw_string(font, axis_pos - axs * 0.5 + Vector2(0, axs.y * 0.35),
			c["axis"], HORIZONTAL_ALIGNMENT_LEFT, -1, axis_size, axis_col)

	# Vertical world-Y axis: a fixed up/down line through the dial center,
	# +Y on top and -Y on the bottom (Y is always screen-vertical, it does not
	# rotate with the camera the way the ground cardinals do).
	var y_col := Color(0.7, 0.85, 1.0, 0.85)
	var y_top := center - Vector2(0, _RADIUS)
	var y_bot := center + Vector2(0, _RADIUS)
	draw_line(y_top, y_bot, y_col, 2.0, true)
	var y_size := 11
	var yp := font.get_string_size("+Y", HORIZONTAL_ALIGNMENT_LEFT, -1, y_size)
	draw_string(font, y_top - yp * 0.5 - Vector2(0, 5.0),
		"+Y", HORIZONTAL_ALIGNMENT_LEFT, -1, y_size, y_col)
	var yn := font.get_string_size("-Y", HORIZONTAL_ALIGNMENT_LEFT, -1, y_size)
	draw_string(font, y_bot - yn * 0.5 + Vector2(0, yn.y + 4.0),
		"-Y", HORIZONTAL_ALIGNMENT_LEFT, -1, y_size, y_col)

	draw_circle(center, 2.5, Color(1, 1, 1, 0.8))
