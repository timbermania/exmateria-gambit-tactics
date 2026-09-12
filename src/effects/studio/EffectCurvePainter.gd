extends Control
## The Effect Studio **freehand curve painter** — a dense integer-grid Control you
## draw on with the mouse, bound to a real EffectCurve. FFT curves have no control
## points (dense LUTs), so the gesture is a paint stroke: press to place a column,
## drag to sweep, and skipped columns interpolate (CurvePaintModel.stroke_segment).
## ONE painter parameterized by Y-range serves both variants — 0-255 × 160 lerp
## curves and 1-9 × 600 time-slow.
##
## Preview-vs-commit feel (ported from the DAW): the drag mutates a LOCAL grid and
## repaints live; mouse-UP emits the finished stroke as `curve_changed(values)` — ONE
## commit per gesture, which is what makes an undo entry a gesture rather than a pixel.
##
## The painter does NOT write the bound curve. It used to, back when a curve edit was
## ephemeral (no session, no writer); since the ADR-0089 curve-ownership amendment the
## commit is a real edit routed through `EffectEditSession`, and the choke point has to
## see the PRE-edit samples to snapshot them for undo — which it cannot if the painter
## has already overwritten them. So the painter previews and reports; `CurveChannel`
## writes. The bound curve is still held: it is what `bind_curve` reads the grid FROM,
## and what tells a commit there is anything to report.
##
## Pure Control (web/WASM-safe). No `class_name` (ADR-0004).

const CurvePaintModel = preload("res://src/effects/studio/CurvePaintModel.gd")

## The finished stroke as a 0-`vmax` int array — the whole curve, not a delta.
signal curve_changed(values: Array)

const MARGIN: float = 10.0

const COL_BG := Color(0.08, 0.09, 0.12)
const COL_GRID := Color(1, 1, 1, 0.06)
const COL_CURVE := Color(0.45, 0.85, 1.0)
const COL_FILL := Color(0.45, 0.85, 1.0, 0.18)
const COL_TEXT := Color(0.6, 0.66, 0.78)
# The inactive-tail veil + its boundary marker (ADR-0089 curve-UX amendment). The
# veil dims what the sim doesn't consume; the boundary line + N label say where.
const COL_VEIL := Color(0.05, 0.06, 0.08, 0.55)
const COL_BOUNDARY := Color(1.0, 0.72, 0.35, 0.85)
# The emitter-elapsed playhead marker (ADR-0089 amendment): a bright line + two-ended tag
# inside the firing, dimmed to a ghost (with a before/after tell) when out of it.
const COL_MARKER := Color(1.0, 0.86, 0.42, 0.95)
const COL_MARKER_DIM := Color(1.0, 0.86, 0.42, 0.40)
const COL_HINT := Color(0.6, 0.66, 0.78, 0.9)

var _curve
var _grid: Array = []
var _vmin: int = 0
var _vmax: int = 255
var _count: int = 160
var _used_n: int = -1

var _dragging: bool = false
var _last_col: int = 0
var _last_val: int = 0
# The emitter-elapsed playhead marker (ADR-0089 amendment) — a CurvePlayheadMarker payload
# `{present, index, lap, elapsed, frame, state}`, refreshed continuously by the page as the
# playhead sweeps. `{present: false}` (optionally carrying a `hint`) draws no line.
var _marker: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Bind a live EffectCurve and its Y-range. Reads the curve into a local integer
## grid; `_count` follows the curve length (160 lerp / 600 time-slow). `used_n` is
## the ADR-0089 used window (curve-UX amendment): ALL frames stay editable (the
## window can grow), but the inactive tail past N is veiled and frame N is marked.
func bind_curve(curve, vmin: int, vmax: int, used_n: int = -1) -> void:
	_curve = curve
	_vmin = vmin
	_vmax = vmax
	_used_n = used_n
	_count = curve.samples.size()
	_grid = CurvePaintModel.curve_to_grid(curve, vmax)
	queue_redraw()


func grid_values() -> Array:
	return _grid


## The used window fed to bind_curve (-1 = none). Test seam.
func used_window() -> int:
	return _used_n


## Set (or clear) the emitter-elapsed playhead marker (ADR-0089 amendment). The page
## refreshes this continuously so the marker sweeps across the curve during Play/scrub.
## `{present: false}` clears the line (an absent marker may carry a `hint` for the
## no-governing-span case). Marker updates repaint only — the bound curve is untouched.
func set_marker(marker: Dictionary) -> void:
	_marker = marker
	queue_redraw()


## True when a playhead marker line is drawn (a present marker). Test seam.
func has_marker() -> bool:
	return bool(_marker.get("present", false))


## The curve index the marker line sits at, -1 when none. Test seam.
func marker_index() -> int:
	return int(_marker.get("index", -1)) if bool(_marker.get("present", false)) else -1


## The X pixel of curve frame `index` among `count` frames within grid rect `r` — the SAME
## band-centre mapping _draw_curve uses (x = r.x + (i+0.5)/count · r.w), so the line points
## at the frame it samples. Clamped into [0, count−1] so an over-range index (after-firing
## clamp on a wrapped curve) stays on the grid. Pure — a test seam AND _draw's source.
static func marker_x(index: int, count: int, r: Rect2) -> float:
	if count <= 0:
		return r.position.x
	var i := clampi(index, 0, count - 1)
	return r.position.x + (float(i) + 0.5) / float(count) * r.size.x


## The two-ended marker tag (ADR-0089 amendment): `elapsed N · fF` bridges the emitter-
## elapsed coordinate and the absolute effect frame (naming both is what teaches the map);
## a `×N` lap tag marks a wrap past 160 (so a jump back to x=0 isn't read as a glitch); a
## before/after tell marks an out-of-firing clamp. An absent marker shows its `hint` (the
## browsed-emitter case) or nothing. Pure — a test seam AND _draw's source.
static func marker_tag(marker: Dictionary) -> String:
	if not bool(marker.get("present", false)):
		return str(marker.get("hint", ""))
	var s := "elapsed %d · f%d" % [int(marker.get("elapsed", 0)), int(marker.get("frame", 0))]
	if int(marker.get("lap", 0)) >= 1:
		s += "  ×%d" % (int(marker.get("lap", 0)) + 1)
	match str(marker.get("state", "in")):
		"before": s += "  (before firing)"
		"after": s += "  (after firing)"
	return s


## The active-region marks (ADR-0089 curve-UX amendment) — the inverse of the
## sparkline's trim. A real sub-window (0 < N < count) veils the inactive tail
## (N..count] and draws a boundary at frame N; a wrapping (>= count) window has no
## veil; -1 (animation-driven) has no veil but an honest note. Pure — a test seam.
static func active_region(used_n: int, count: int, r: Rect2) -> Dictionary:
	if used_n > 0 and used_n < count:
		var bx: float = r.position.x + float(used_n) / float(count) * r.size.x
		return {"show_veil": true, "boundary_x": bx,
			"veil_rect": Rect2(bx, r.position.y, r.position.x + r.size.x - bx, r.size.y),
			"label": str(used_n), "note": ""}
	var note := "animation-driven — full curve used" if used_n < 0 else ""
	return {"show_veil": false, "boundary_x": 0.0, "veil_rect": Rect2(), "label": "", "note": note}


func _grid_rect() -> Rect2:
	return Rect2(MARGIN, MARGIN, maxf(1.0, size.x - MARGIN * 2.0), maxf(1.0, size.y - MARGIN * 2.0))


# --- Input (paint stroke) -------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _grid.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			var cell := CurvePaintModel.pixel_to_cell(event.position, _grid_rect(), _count, _vmin, _vmax)
			_last_col = cell["col"]
			_last_val = cell["val"]
			CurvePaintModel.stroke_segment(_grid, _last_col, _last_val, _last_col, _last_val, _vmin, _vmax)
			queue_redraw()
		else:
			_dragging = false
			_commit()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var cell := CurvePaintModel.pixel_to_cell(event.position, _grid_rect(), _count, _vmin, _vmax)
		CurvePaintModel.stroke_segment(_grid, _last_col, _last_val, cell["col"], cell["val"], _vmin, _vmax)
		_last_col = cell["col"]
		_last_val = cell["val"]
		queue_redraw()


func _commit() -> void:
	if _curve == null:
		return
	curve_changed.emit(_grid.duplicate())


# --- Draw -----------------------------------------------------------------

func _draw() -> void:
	var r := _grid_rect()
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	_draw_y_gridlines(r)
	if _grid.is_empty():
		return
	_draw_curve(r)
	_draw_active_region(r)
	_draw_marker(r)


## The emitter-elapsed playhead marker (ADR-0089 amendment): a bright vertical line at the
## sampled frame + the two-ended `elapsed N · fF` tag (with a `×N` lap tag / before-after
## tell). Dimmed to a ghost when out of the firing. An absent marker draws only its hint
## (the browsed-emitter "select this emitter's span" case) — never a lying line.
func _draw_marker(r: Rect2) -> void:
	if _marker.is_empty():
		return
	var font := get_theme_default_font()
	var tag := marker_tag(_marker)
	if not bool(_marker.get("present", false)):
		if tag != "" and font:
			draw_string(font, Vector2(r.position.x + 4.0, r.position.y + 11.0), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_HINT)
		return
	var in_firing := str(_marker.get("state", "in")) == "in"
	var col := COL_MARKER if in_firing else COL_MARKER_DIM
	var x := marker_x(int(_marker.get("index", 0)), _count, r)
	draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y), col, 1.0)
	if font == null:
		return
	# Two-ended: the tag rides the TOP of the line, the elapsed coordinate the BOTTOM — the
	# bridge is legible at both ends of the sweep line.
	draw_string(font, Vector2(x + 3.0, r.position.y + 11.0), tag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	draw_string(font, Vector2(x + 3.0, r.position.y + r.size.y - 3.0),
		"e%d" % int(_marker.get("elapsed", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


## Veil the inactive tail past frame N and mark the boundary (ADR-0089 curve-UX
## amendment). No full X ruler (clutter on a wide canvas) — just the veil + a 1px
## line + the N label; -1 shows an honest corner note instead.
func _draw_active_region(r: Rect2) -> void:
	var reg := active_region(_used_n, _count, r)
	var font := get_theme_default_font()
	if reg["show_veil"]:
		draw_rect(reg["veil_rect"], COL_VEIL)
		var bx: float = reg["boundary_x"]
		draw_line(Vector2(bx, r.position.y), Vector2(bx, r.position.y + r.size.y), COL_BOUNDARY, 1.0)
		if font:
			draw_string(font, Vector2(bx + 3.0, r.position.y + 11.0), str(reg["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_BOUNDARY)
	elif str(reg["note"]) != "" and font:
		draw_string(font, Vector2(r.position.x + 4.0, r.position.y + r.size.y - 4.0),
			str(reg["note"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT)


func _draw_y_gridlines(r: Rect2) -> void:
	var font := get_theme_default_font()
	var divisions := 4
	for i in range(divisions + 1):
		var f := float(i) / float(divisions)
		var y := r.position.y + f * r.size.y
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), COL_GRID, 1.0)
		if font:
			var val := int(round(lerpf(float(_vmax), float(_vmin), f)))
			draw_string(font, Vector2(r.position.x + 2.0, y - 2.0), str(val),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT)


func _draw_curve(r: Rect2) -> void:
	var n := _grid.size()
	var span: float = maxi(1, _vmax - _vmin)
	var pts := PackedVector2Array()
	var fill := PackedVector2Array()
	fill.append(Vector2(r.position.x, r.position.y + r.size.y))
	for i in range(n):
		var x := r.position.x + (float(i) + 0.5) / float(n) * r.size.x
		var norm := float(_grid[i] - _vmin) / span
		var y := r.position.y + (1.0 - norm) * r.size.y
		pts.append(Vector2(x, y))
		fill.append(Vector2(x, y))
	fill.append(Vector2(r.position.x + r.size.x, r.position.y + r.size.y))
	if fill.size() >= 3:
		draw_colored_polygon(fill, COL_FILL)
	if pts.size() >= 2:
		draw_polyline(pts, COL_CURVE, 1.5, true)
