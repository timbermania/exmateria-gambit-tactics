extends Control
## The Effect Studio **frames bar** — the score timeline's ruler, pulled OUT of the
## scrolling lane panel so it floats on its own between the (resizable) keyframe
## inspector above and the channel list below. It stays put — always at the top of
## the channel area — when the inspector grows/shrinks; the old ruler rode inside
## the timeline and so got shoved around by the inspector's fit-to-size height.
##
## It shares the bound timeline's TimelineAxis (one frame↔pixel transform), so its
## frame ticks and playhead marker stay pixel-aligned with the lanes underneath,
## and it owns the seek / zoom / pan surface the in-timeline ruler used to. Pure
## Control, web/WASM-safe. No `class_name` (ADR-0004).

const TimelineAxis = preload("res://src/effects/studio/TimelineAxis.gd")
const LoopRegion = preload("res://src/effects/studio/LoopRegion.gd")

## Scrub intent — same contract as the timeline's own seek_requested; the page
## wires both to one handler.
signal seek_requested(frame: int)

## Loop-region intent (ADR-0090): an Alt+left-drag on the bar defines the inclusive
## `[start, end]` span. Emitted live during the drag (each motion) and on the initial
## press, so the page can preview the band as it's drawn. The page owns the region
## state; the bar only maps the gesture to snapped, ordered, min-length frames.
signal region_changed(start: int, end: int)

const BAR_H: float = 30.0

# Palette matches EffectScoreTimeline so the bar reads as one surface with it.
const COL_RULER := Color(0.14, 0.15, 0.19)
const COL_GUTTER := Color(0.12, 0.13, 0.17)
const COL_TEXT_DIM := Color(0.55, 0.60, 0.70)
const COL_PLAYHEAD := Color(1.0, 0.85, 0.25)
# Derived effect-end stop (matches EffectScoreTimeline.COL_END) — where playback halts.
const COL_END := Color(0.95, 0.38, 0.42)
# Loop region (ADR-0090): matches EffectScoreTimeline's band/edge cyan. The bar shows a
# stronger fill + solid edge grips (the grab handles) than the lanes' faint band.
const COL_LOOP_FILL := Color(0.30, 0.75, 0.95, 0.22)
const COL_LOOP_EDGE := Color(0.40, 0.85, 1.0, 0.95)

var _tl                       # the bound EffectScoreTimeline (shared axis/score/playhead)
var _panning: bool = false
var _pan_last_x: float = 0.0
var _scrubbing: bool = false
# Loop-region create drag (ADR-0090): Alt+left. The anchor is the frame the drag
# started on; each motion re-derives the ordered [anchor, cursor] span. -1 = not dragging.
var _region_dragging: bool = false
var _region_anchor: int = -1
# The current loop region `{start, end}` (or `{}`), mirrored from the page so the bar can
# shade it + offer edge handles. "" = not dragging an edge, else "start"/"end" (ADR-0090).
var _region: Dictionary = {}
var _region_edge_drag: String = ""
# Pixel radius of an edge grab zone (plain-drag an edge to adjust it).
const REGION_GRIP_PX: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = BAR_H


## Bind the timeline this bar mirrors. Shares its axis (draw + hit-test), and
## redraws whenever the timeline's axis pans/zooms or its playhead moves so the two
## never drift.
func bind_timeline(tl) -> void:
	_tl = tl
	if _tl:
		_tl.axis_changed.connect(queue_redraw)
		_tl.playhead_changed.connect(queue_redraw)
	queue_redraw()


# --- Input (the seek / zoom / pan surface) --------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _region_dragging:
		_emit_region(_frame_at_x(event.position.x))
	elif event is InputEventMouseMotion and _region_edge_drag != "":
		_adjust_edge(_frame_at_x(event.position.x))
	elif event is InputEventMouseMotion and _panning:
		_tl.pan_by(event.position.x - _pan_last_x)
		_pan_last_x = event.position.x
	elif event is InputEventMouseMotion and _scrubbing:
		_seek_to_x(event.position.x)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if _tl == null:
		return
	# Ctrl+wheel zooms the frame axis (mirrors the timeline). A plain wheel is
	# ignored here (the bar isn't inside the channel ScrollContainer).
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if event.ctrl_pressed:
			_tl.zoom_at(1.15, event.position.x)
			accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if event.ctrl_pressed:
			_tl.zoom_at(1.0 / 1.15, event.position.x)
			accept_event()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_pan_last_x = event.position.x
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Alt+left creates the loop region (ADR-0090). Checked BEFORE the plain-left scrub
	# arm so the two gestures never fight — plain left still scrubs.
	if event.pressed and event.alt_pressed:
		_region_dragging = true
		_region_anchor = _frame_at_x(event.position.x)
		_emit_region(_region_anchor)  # a click without drag still yields a min-length region
		return
	if event.pressed and event.shift_pressed:
		_panning = true
		_pan_last_x = event.position.x
		return
	if not event.pressed:
		_panning = false
		_scrubbing = false
		_region_dragging = false
		_region_edge_drag = ""
		return
	# A plain press ON a region edge grabs that handle to adjust it (ADR-0090) — checked
	# before the scrub arm so grabbing an edge doesn't also seek. A press anywhere else
	# (including the region interior) still scrubs.
	var edge := _region_edge_at_x(event.position.x)
	if edge != "":
		_region_edge_drag = edge
		return
	# A plain left press on the bar arms a continuous scrub (hold + drag seeks).
	_scrubbing = true
	_seek_to_x(event.position.x)


## Map a local x to a snapped frame and emit the seek. x is clamped to the frame
## area so a drag into the label gutter still resolves to frame 0. The page owns
## moving the playhead (its handler does), which redraws us via playhead_changed.
func _seek_to_x(x: float) -> void:
	seek_requested.emit(_frame_at_x(x))


## Map a local x to a snapped frame. Clamped to the frame area (gutter) so a drag into
## the label gutter still resolves to frame 0. Shared by the scrub and region gestures.
func _frame_at_x(x: float) -> int:
	var gutter: float = _tl.GUTTER_W
	return TimelineAxis.snap(_tl.axis.x_to_frame(maxf(gutter, x)), _tl.snap_step)


## Order the drag [anchor, cursor] into a min-length [start, end] and announce it.
func _emit_region(cursor_frame: int) -> void:
	var r := LoopRegion.from_frames(_region_anchor, cursor_frame)
	region_changed.emit(r["start"], r["end"])


## Adopt the loop region `{start, end}` (or `{}`) mirrored from the page; redraw the shading.
func set_loop_region(region: Dictionary) -> void:
	_region = region if region != null else {}
	queue_redraw()


## Which region edge (if any) sits under x, within the grab radius. "" when no region /
## no edge is under the cursor. The start grip wins a tie (edges only tie on a 1-frame span,
## which the min length forbids).
func _region_edge_at_x(x: float) -> String:
	if _tl == null or not _region.has("start") or not _region.has("end"):
		return ""
	var sx: float = _tl.axis.frame_to_x(float(_region["start"]))
	var ex: float = _tl.axis.frame_to_x(float(_region["end"]))
	if absf(x - sx) <= REGION_GRIP_PX:
		return "start"
	if absf(x - ex) <= REGION_GRIP_PX:
		return "end"
	return ""


## Move the grabbed edge to `frame`, keeping the OTHER edge fixed; order + min-length via
## LoopRegion, then announce (the page re-mirrors it back via set_loop_region).
func _adjust_edge(frame: int) -> void:
	var other: int = int(_region["end"]) if _region_edge_drag == "start" else int(_region["start"])
	var r := LoopRegion.from_frames(other, frame)
	_region = r
	region_changed.emit(r["start"], r["end"])
	queue_redraw()


# --- Draw -----------------------------------------------------------------

func _draw() -> void:
	if _tl == null:
		return
	var axis = _tl.axis
	var gutter: float = _tl.GUTTER_W
	draw_rect(Rect2(Vector2.ZERO, size), COL_RULER)
	draw_rect(Rect2(0.0, 0.0, gutter, size.y), COL_GUTTER)
	var font := get_theme_default_font()
	var max_frame: int = _tl._score.get("max_frame", 0)
	var step := _ruler_step(axis)
	var f := 0
	while f <= max_frame:
		var x: float = axis.frame_to_x(float(f))
		if x >= gutter:
			draw_line(Vector2(x, size.y - 7.0), Vector2(x, size.y), COL_TEXT_DIM, 1.0)
			if font:
				draw_string(font, Vector2(x + 2.0, 12.0), str(f),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)
		f += step
	_draw_loop_region(axis, gutter)
	_draw_end_marker(axis, gutter, font)
	_draw_playhead(axis, gutter)


## The derived effect-end stop, mirrored from the bound timeline (get_end_frame),
## with an "end" label so the ruler names where playback halts.
func _draw_end_marker(axis, gutter: float, font) -> void:
	var end_frame: int = _tl.get_end_frame()
	if end_frame <= 0:
		return
	var x: float = axis.frame_to_x(float(end_frame))
	if x < gutter:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), COL_END, 1.5)
	if font:
		draw_string(font, Vector2(x + 3.0, 11.0), "end",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_END)


## Shade the loop region on the ruler and draw its two edge grips (the plain-drag handles),
## clamped to the frame area (ADR-0090). No-op when no region is set.
func _draw_loop_region(axis, gutter: float) -> void:
	if not _region.has("start") or not _region.has("end"):
		return
	var sx: float = axis.frame_to_x(float(_region["start"]))
	var ex: float = axis.frame_to_x(float(_region["end"]))
	var left: float = maxf(gutter, sx)
	var right: float = maxf(gutter, ex)
	if right > left:
		draw_rect(Rect2(left, 0.0, right - left, size.y), COL_LOOP_FILL)
	# Edge grips: a thicker rule on each boundary that falls inside the frame area.
	if sx >= gutter:
		draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), COL_LOOP_EDGE, 2.5)
	if ex >= gutter:
		draw_line(Vector2(ex, 0.0), Vector2(ex, size.y), COL_LOOP_EDGE, 2.5)


func _draw_playhead(axis, gutter: float) -> void:
	var x: float = axis.frame_to_x(float(_tl.get_playhead()))
	if x < gutter:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), COL_PLAYHEAD, 1.5)
	draw_colored_polygon(
		PackedVector2Array([Vector2(x - 5.0, 0.0), Vector2(x + 5.0, 0.0), Vector2(x, 8.0)]),
		COL_PLAYHEAD)


## Choose a frame tick spacing (1/5/10/30/60/…) so ticks are ~48+ px apart —
## mirrors EffectScoreTimeline._ruler_step against the shared axis.
func _ruler_step(axis) -> int:
	for c in [1, 5, 10, 30, 60, 120, 300, 600]:
		if c * axis.pixels_per_frame >= 48.0:
			return c
	return 600
