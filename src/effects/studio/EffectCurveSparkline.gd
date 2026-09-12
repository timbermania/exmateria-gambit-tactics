extends Control
## A tiny inline drawing of one EffectCurve — the per-param curve affordance in the
## keyframe inspector. The curve IS a facet of the param (CONTEXT "Param shape"), so
## the sparkline sits ON the param's row and is itself the click target: pressing it
## opens the freehand painter for THIS param's curve, never off the keyframe. A
## disabled/pinned param (no curve) draws a greyed flat line — no glide to show.
##
## Web/WASM-safe pure Control; no `class_name` (ADR-0004). Draws a normalized
## polyline of the curve samples so the thumbnail and the full painter read the same
## shape (single source of truth = the samples).

signal pressed

# Global display toggles (ADR-0089 curve-UX — studio transport "Fit H" / "Fit W"
# buttons flip these). Height ON = Y re-fit to the plotted window's own min/max
# (shape); OFF = a fixed 0..1 range (true magnitude, comparable across rows). Width
# ON = trim to the used window `0..N` X-stretched (the active part); OFF = draw the
# whole 160-sample curve. Both default to the curve-UX amendment's behaviour.
static var display_normalize_height: bool = true
static var display_trim_width: bool = true

const COL_LINE := Color(0.55, 0.80, 0.95)
const COL_DISABLED := Color(0.34, 0.37, 0.44)
# The emitter-elapsed playhead marker (ADR-0089 amendment): a bright line inside the
# firing, dimmed to a ghost when the playhead sits before/after it (clamped to an edge).
const COL_MARKER := Color(1.0, 0.86, 0.42, 0.95)
const COL_MARKER_DIM := Color(1.0, 0.86, 0.42, 0.35)
# Absolute-mode reference frame (Fit H off): a faint ceiling (max) + baseline (0) so
# the box reads as the 0→max gauge — a curve touching the top line is maxed. Only in
# absolute mode; fit mode re-fits Y, so its top is the curve's own peak, not max.
const COL_GUIDE := Color(0.55, 0.80, 0.95, 0.22)
# A LINEAR glyph (#291 follow-on) — a group with NO assigned curve still shows
# its straight start→end interpolation slope, drawn dim so it reads as secondary
# to a real (bright, clickable) curve.
const COL_LINEAR := Color(0.44, 0.48, 0.56)

var _samples: PackedFloat32Array = PackedFloat32Array()
var _enabled: bool = true
var _used_n: int = -1
var _linear: bool = false
# The emitter-elapsed playhead marker (ADR-0089 amendment). Only emitter-clocked curves
# get one (set by the inspector); an absent/empty marker draws no line.
var _marker: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(52.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Feed the curve's samples (any Y-range — normalized here for display) and the
## param's enabled state. Empty/disabled ⇒ a greyed flat line. `used_n` is the
## ADR-0089 used window: a real sub-window (0 < N < 160) TRIMS the sparkline to its
## leading N samples, X-stretched to full width and Y re-fit to that window (a
## post-window spike no longer squashes the visible part — curve-UX amendment); a
## wrapping (>= 160) or animation-driven (-1) window falls back to the whole curve.
func set_curve(samples: Array, enabled: bool, used_n: int = -1) -> void:
	_samples = PackedFloat32Array(samples)
	_enabled = enabled
	_used_n = used_n
	_linear = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	queue_redraw()


## The LINEAR interpolation glyph (#291): a straight slope from `start_v` to
## `end_v` (normalized here), for a group with no assigned curve. Read-only — not
## an editable curve — so it draws dim and never opens the painter.
func set_linear(start_v: float, end_v: float) -> void:
	_samples = PackedFloat32Array([start_v, end_v])
	_linear = true
	_enabled = false
	_used_n = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


## True when showing the read-only linear-interpolation glyph (no assigned curve).
func is_linear() -> bool:
	return _linear


## The used window fed to set_curve (-1 = none — fully bright). Test seam.
func used_window() -> int:
	return _used_n


## The raw samples last fed (a live in-place recolour re-feeds these; a test seam that
## proves the sparkline tracks the forked curve rather than a stale snapshot).
func samples() -> PackedFloat32Array:
	return _samples


## Set (or clear) the emitter-elapsed playhead marker (ADR-0089 amendment). `marker` is
## a CurvePlayheadMarker payload — `{present, index, lap, state}`. `{present: false}` (or
## an empty dict) clears it. The inspector calls this ONLY on emitter-clocked sparklines;
## age-clocked (over-life) ones never receive it, so they draw no line.
func set_marker(marker: Dictionary) -> void:
	_marker = marker if bool(marker.get("present", false)) else {}
	queue_redraw()


## True when a playhead marker line is drawn. Test seam.
func has_marker() -> bool:
	return not _marker.is_empty()


## The curve index the marker line sits at (`elapsed % 160`), -1 when none. Test seam.
func marker_index() -> int:
	return int(_marker.get("index", -1)) if not _marker.is_empty() else -1


## The X pixel of drawn sample `index` among `n_drawn` plotted samples across `width` —
## the SAME mapping plot_points uses (x = width · i/(n−1)), so the line points at its
## sample. Clamped into [0, n_drawn−1] so the after-firing edge-clamp never runs off the
## canvas. Pure — a test seam AND the single source _draw reads.
static func marker_x(index: int, n_drawn: int, width: float) -> float:
	if n_drawn < 2:
		return 0.0
	var i := clampi(index, 0, n_drawn - 1)
	return width * float(i) / float(n_drawn - 1)


## The samples actually plotted (ADR-0089 curve-UX amendment). A real sub-window
## (0 < N < 160, N < len) TRIMS to its leading N samples so a short window fills the
## width; a wrapping (>= 160), animation-driven (-1), degenerate (<= 0), or
## data-wide window plots the WHOLE curve un-trimmed. Pure — a test seam.
static func windowed_samples(samples, used_n: int) -> PackedFloat32Array:
	var s := PackedFloat32Array(samples)
	if used_n > 0 and used_n < 160 and used_n < s.size():
		return s.slice(0, maxi(used_n, 2))
	return s


## The polyline points for the curve branch. `trim` (width): true = window-trim
## (windowed_samples); false = the whole curve regardless of the window. `normalize`
## (height): true = Y re-fit to the PLOTTED samples' own min/max (shape — a post-window
## spike no longer squashes the visible part); false = a FIXED 0..1 range (true
## magnitude, comparable across rows). X stretches across the full width. Pure — _draw
## plots these; returns empty (<2 points) when there is nothing to draw.
static func plot_points(samples, used_n: int, sz: Vector2, trim: bool = true,
		normalize: bool = true) -> PackedVector2Array:
	var plot := windowed_samples(samples, used_n if trim else -1)
	var pts := PackedVector2Array()
	var n := plot.size()
	if n < 2:
		return pts
	var lo := 0.0
	var hi := 1.0
	if normalize:
		lo = plot[0]
		hi = plot[0]
		for v in plot:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var span := maxf(hi - lo, 0.0001)
	for i in n:
		var x := sz.x * float(i) / float(n - 1)
		var yn := clampf((plot[i] - lo) / span, 0.0, 1.0)  # 0..1 within the range
		pts.append(Vector2(x, sz.y - yn * sz.y))  # invert (Godot y-down)
	return pts


## The points _draw plots for this widget's curve, honoring the GLOBAL toggles
## (display_trim_width / display_normalize_height). A test seam AND the single source
## _draw reads, so the toggles and the render never diverge.
func plotted_points(sz: Vector2) -> PackedVector2Array:
	return plot_points(_samples, _used_n, sz, display_trim_width, display_normalize_height)


## True when _draw should mark the absolute 0→max reference frame: absolute height mode
## (Fit H off) on a real curve — in fit mode the box top is the curve's own peak (not
## max), so a ceiling line there would lie; the no-curve linear glyph has no scale.
func shows_absolute_guides() -> bool:
	return not display_normalize_height and not _linear and _enabled and _samples.size() >= 2


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var sz := size
	# Nothing to plot: a disabled param with no linear glyph draws the flat grey line.
	if _samples.size() < 2 or not (_enabled or _linear):
		var y := sz.y * 0.5
		draw_line(Vector2(0.0, y), Vector2(sz.x, y), COL_DISABLED, 1.0)
		return
	# A no-curve glyph is dim and window-less (never trimmed). The value is CONSTANT
	# at start (the end is inert without a curve), so a near-zero span draws a FLAT
	# line — showing a start→end slope would imply a glide that never happens (#291).
	if _linear:
		var lo := _samples[0]
		var hi := _samples[0]
		for v in _samples:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		if hi - lo <= 0.0002:
			var ym := sz.y * 0.5
			draw_line(Vector2(0.0, ym), Vector2(sz.x, ym), COL_LINEAR, 1.0)
		else:
			var lpts := plot_points(_samples, -1, sz)
			draw_polyline(lpts, COL_LINEAR, 1.0, true)
		return

	# Absolute mode (Fit H off) has no implicit scale, so mark the 0→max reference frame:
	# a faint ceiling (max) at the top + baseline (0) at the bottom. The curve touching the
	# ceiling reads as maxed. Drawn UNDER the polyline. Fit mode omits it (top = own peak).
	if shows_absolute_guides():
		draw_line(Vector2(0.0, 0.5), Vector2(sz.x, 0.5), COL_GUIDE, 1.0)
		draw_line(Vector2(0.0, sz.y - 0.5), Vector2(sz.x, sz.y - 0.5), COL_GUIDE, 1.0)

	# Used window (ADR-0089 curve-UX amendment), subject to the global Fit H / Fit W
	# toggles: width trims to 0..N (or whole), height re-fits to the window (or a fixed
	# 0..1 range). One bright polyline — the dim unused tail is gone (trimming replaced it).
	var pts := plotted_points(sz)
	if pts.size() >= 2:
		draw_polyline(pts, COL_LINE, 1.0, true)

	# The emitter-elapsed playhead marker (ADR-0089 amendment): a bare vertical line at
	# the sampled index, mapped into the same drawn window as the polyline. Dimmed to a
	# ghost when out of the firing (clamped to an edge) so it reads as "not sampling here".
	_draw_marker(sz)


## Draw the playhead marker line at the sampled index, over the same drawn-sample window
## the polyline uses (so a trimmed sparkline and its marker share one X mapping). Dim when
## the playhead is before/after the firing (the clamped-to-edge, not-sampling-here tell).
func _draw_marker(sz: Vector2) -> void:
	if _marker.is_empty():
		return
	var n_drawn := plotted_points(sz).size()
	if n_drawn < 2:
		return
	var x := marker_x(int(_marker.get("index", 0)), n_drawn, sz.x)
	var col := COL_MARKER if str(_marker.get("state", "in")) == "in" else COL_MARKER_DIM
	draw_line(Vector2(x, 0.0), Vector2(x, sz.y), col, 1.0)
