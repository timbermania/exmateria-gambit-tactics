extends Control

## Screen-space visualization of the camera's deadzone scroll box: exactly the region
## the active tile may roam before the camera scrolls. Lives under a CanvasLayer so it
## overlays the game view; hidden by default, toggled from the Camera debug tab. Purely
## a debug aid — it never participates in the deadzone math itself.
##
## 🔴 IT DOES NOT DERIVE THE RECT, IT ASKS FOR IT. This used to build its own
## `Vector2(size.x * deadzone_width, size.y * deadzone_height)` centred on `size * 0.5`,
## which was a second implementation of the box — and the moment the framing datum moved
## the box's centre off the viewport midpoint (FFT frames its optical centre 40 native px
## low), a re-derivation here would have drawn a rectangle the camera does not use. An
## overlay whose whole job is to show you where the box is has to read the box.

var _camera  # PlayerCamera — asked for deadzone_box_screen_rect()

const LINE_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const DATUM_COLOR := Color(0.3, 0.9, 1.0, 0.5)  # the framing row through the box centre
const FILL_COLOR := Color(1.0, 0.9, 0.2, 0.06)
const LINE_WIDTH := 1.5


func setup(camera) -> void:
	_camera = camera


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat game input
	resized.connect(queue_redraw)


func _draw() -> void:
	if _camera == null:
		return
	var frac: Rect2 = _camera.deadzone_box_screen_rect()
	var rect := Rect2(frac.position * size, frac.size * size)
	draw_rect(rect, FILL_COLOR, true)
	draw_rect(rect, LINE_COLOR, false, LINE_WIDTH)
	# The framing row itself — where the followed tile is held. Without it the box alone
	# cannot show you that its centre is 40 native px low; with it, scrubbing
	# `camera.vertical_datum_px` to 0 visibly walks the line back to the midpoint.
	var cy: float = rect.position.y + rect.size.y * 0.5
	draw_line(Vector2(0.0, cy), Vector2(size.x, cy), DATUM_COLOR, LINE_WIDTH)
