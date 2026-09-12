extends Control
## The interactive colour-keyframe editor drawn WITH the Colour ribbon (ADR-0089 colour-keyframe
## amendment, editing-UX amendment 2026-08-13). The ribbon stays a PURE read-out; this control is
## a transparent interactive OVERLAY that HOSTS the ribbon as a child (so the coloured band itself
## is the click target — the band "feels clickable" without breaking the ribbon's pure-view
## contract) and draws the keyframe HANDLES in a high-contrast LANE ABOVE the band (the small
## on-band dots were hard to see against the colours).
##
## Real-vs-interpolated is unmistakable (decision 3): a SOLID handle = a real (deletable) keyframe,
## with a thin tick down to its band column; the empty lane between handles = interpolated; a GHOST
## handle under the cursor on an empty spot telegraphs that a click will ADD one; the selected
## handle is highlighted. Click near a solid handle SELECTS it; click an empty spot ADDS a keyframe
## there (seeded with the colour already present, so adding changes nothing until you recolour it).
##
## It shares the ribbon's PARTICLE-AGE axis (0 → the particle's lifetime) — the domain a colour
## curve actually lives in (NOT the emitter/timeline playhead: one playhead frame has many
## particles alive at many ages, so "the colour at the playhead" is ambiguous).
##
## No `class_name` (ADR-0004) — preloaded by path.

## The selected keyframe's index, or **-1 for "nothing selected"** — the same sentinel
## `selected_index()` and `set_keyframes` already carry. Emitted with -1 when a click
## toggles the selected handle off, which is how the colour picker gets closed.
signal keyframe_selected(index: int)
signal frame_added(frame: int)
signal keyframe_remove_requested(index: int)

const LANE_H := 16.0        # the handle lane above the band
const HANDLE_W := 7.0       # solid handle marker width
const HANDLE_H := 9.0       # solid handle marker height
const HIT_PX := 6.0
const COL_LANE := Color(0.14, 0.15, 0.19, 1.0)     # the lane backdrop (high contrast for handles)
const COL_HANDLE := Color(0.90, 0.92, 0.98, 1.0)   # a solid (real) keyframe handle
const COL_SEL := Color(1.0, 0.95, 0.6, 1.0)        # the selected handle
const COL_GHOST := Color(0.90, 0.92, 0.98, 0.4)    # the add-here ghost under the cursor
const COL_TICK := Color(0.72, 0.76, 0.84, 0.85)    # the thin tick from a handle to its band column

## THE BAND'S FIXED WIDTH (ADR-0068 static-var home; author's rule, 2026-08-19: "make it
## fixed width, the distance between frames is a function of total frames").
##
## It used to take HALF the section body through EXPAND_FILL, so it grew and shrank with the
## window and with whatever else shared the row — 432px on a 903px inspector, 567 on an
## 1187px one. Two consequences, both bad: the same emitter looked different at two window
## sizes, and two emitters could never be compared because their pixels-per-frame differed
## for reasons that had nothing to do with their curves. Fixed, `width / n` is a pure
## function of the life window, so a 2-frame life gets fat bands and a 40-frame life thin
## ones — and that difference now MEANS something.
##
## 260 against the corpus: 2621 colour emitters across 400 effects have a median life window
## of 16 bands (p25 11, p75 21, p90 32, p95 40, p99 65). At 260 the median frame is 16.2px —
## comfortably wider than a 7px handle — and 93.7% of emitters clear 7px/frame. The tail
## pays: at p95 (40 bands) a frame is 6.5px and adjacent handles touch. That is the trade the
## author asked for, `nearest_keyframe` still resolves the clicks, and this is a static var
## so the number can be moved without a rebuild.
static var band_width: float = 260.0

var _n: int = 160
var _keyframes: Array = []
var _selected: int = -1
var _band_height: float = 0.0
var _hover_x: float = -1.0


func _init() -> void:
	# DECLARED here, not by the caller: the width is the track's own contract with the ribbon
	# it hosts (which is anchored to full width), so a container that stretched it would
	# silently change every frame's pixel width. SHRINK_BEGIN is the other half of that —
	# EXPAND_FILL is what made the band a share of the panel.
	custom_minimum_size = Vector2(band_width, LANE_H)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP  # the editor: it consumes clicks over the whole strip


## The age-window frame count (must match the ribbon's used_n / trim so handles line up 1:1).
func configure(n: int) -> void:
	_n = maxi(1, n)
	queue_redraw()


## Host the pure ribbon inside the band region below the lane (the overlay owns the clicks). The
## ribbon is parented and anchored to the band strip; the track grows to lane + band height. The
## ribbon keeps MOUSE_FILTER_IGNORE so events fall through to THIS control's _gui_input.
func set_ribbon(ribbon: Control, band_height: float) -> void:
	_band_height = maxf(0.0, band_height)
	if ribbon.get_parent() != self:
		add_child(ribbon)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor the ribbon to a fixed-height strip pinned below the lane, full width.
	ribbon.anchor_left = 0.0
	ribbon.anchor_right = 1.0
	ribbon.anchor_top = 0.0
	ribbon.anchor_bottom = 0.0
	ribbon.offset_left = 0.0
	ribbon.offset_right = 0.0
	ribbon.offset_top = LANE_H
	ribbon.offset_bottom = LANE_H + _band_height
	custom_minimum_size = Vector2(custom_minimum_size.x, LANE_H + _band_height)
	queue_redraw()


## How many of the CURRENT keyframes are in the dead zone — the instance-level read of
## `beyond_count`, so the page can state it without knowing the window.
func keyframes_past_life() -> int:
	return beyond_count(_keyframes, _n)


func set_keyframes(keyframes: Array, selected: int) -> void:
	_keyframes = keyframes
	_selected = selected
	queue_redraw()


func selected_index() -> int:
	return _selected


## The y where the band starts (just below the handle lane). Test seam.
func band_top() -> float:
	return LANE_H


## The y the handles are drawn at (mid-lane, above the band). Test seam.
func handle_y() -> float:
	return LANE_H * 0.5


## The age frame a click would ADD at when hovering pixel `x` over an EMPTY spot, or -1 when the
## cursor is over a real handle (a click there SELECTS, so no ghost / no accidental add). Drives
## the ghost handle. Pure (given the current size + keyframes).
func ghost_frame(x: float) -> int:
	if nearest_keyframe(_keyframes, x, size.x, _n, HIT_PX) >= 0:
		return -1
	return frame_at_x(x, size.x, _n)


# --- pure axis maths (shared with ColourRibbon's band placement) -----------

## Pixel x → age frame: floor(x / width · n), clamped to [0, n-1].
static func frame_at_x(x: float, width: float, n: int) -> int:
	if width <= 0.0 or n <= 0:
		return 0
	return clampi(int(floor(x / width * float(n))), 0, n - 1)


## Age frame → left-edge pixel (width · f / n) — matches ColourRibbon band i's left edge.
static func x_of_frame(frame: int, width: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return width * float(frame) / float(n)


## Is `frame` an age the particle actually reaches — i.e. inside the band the ribbon paints?
##
## THE TRACK'S DOMAIN IS THE RIBBON'S WINDOW, and this is the whole of that rule. Keyframes
## arrive from a Douglas-Peucker fit over all 160 curve samples (`ColourKeyframeFit`), and DP
## always keeps the terminal point — so every colour emitter in the corpus carries one at
## frame 159, while `_n` is `life_n`, the particle's lifetime (median 16). Everything between
## is the DEAD ZONE: `life_n` is `life.max()`, the upper bound of what the renderer ever
## reads, so a keyframe past it edits samples the game never looks at.
##
## Before this existed, `x_of_frame` was applied to them unclamped and the track does not
## clip, so they painted outside the control entirely — on E317 emitter 3, frames 20 and 26
## at x=540 and x=702 of a 432px track, and frame 159 at x=4293. All 27 colour emitters
## sampled did it. They are neither drawn nor hit now; `beyond_count` states how many, because
## dropping them without saying so is the other way to be wrong.
static func in_window(frame: int, n: int) -> bool:
	return frame >= 0 and frame < n


## How many keyframes fall in the dead zone, so the author can see that the fit carries points
## they cannot reach from here. Reported in the hint LINE above the band, not drawn in the lane:
## the first attempt painted it at the right edge and it landed on top of the last two handles,
## which is exactly where keyframes crowd on a short window.
static func beyond_count(keyframes: Array, n: int) -> int:
	var c := 0
	for kf in keyframes:
		if not in_window(int(kf["frame"]), n):
			c += 1
	return c


## Index of the keyframe whose marker is within `hit_px` of pixel `x`, nearest wins, or -1.
## Dead-zone keyframes are skipped — they have no position on this axis to be near. The
## returned index is into the ORIGINAL array (the page maps it straight back to
## `_colour_keyframes` for delete/recolour), so this filters rather than compacts.
static func nearest_keyframe(keyframes: Array, x: float, width: float, n: int, hit_px: float) -> int:
	var best := -1
	var best_d := hit_px
	for i in range(keyframes.size()):
		if not in_window(int(keyframes[i]["frame"]), n):
			continue
		var mx := x_of_frame(int(keyframes[i]["frame"]), width, n)
		var d := absf(x - mx)
		if d <= best_d:
			best_d = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = event.position.x
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		var x: float = event.position.x
		var idx := nearest_keyframe(_keyframes, x, size.x, _n, HIT_PX)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click a real handle → request its removal (the curve interps across the gap).
			if idx >= 0:
				keyframe_remove_requested.emit(idx)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if idx >= 0:
				# CLICKING THE SELECTED HANDLE AGAIN DESELECTS IT — the only free gesture
				# on this control, and the one the picker needs to have a way to close.
				# Clicking empty space is already taken (it ADDS), so "click off to
				# deselect" was not available; a toggle on the handle is.
				_selected = -1 if idx == _selected else idx
				keyframe_selected.emit(_selected)
			else:
				frame_added.emit(frame_at_x(x, size.x, _n))
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_x = -1.0
		queue_redraw()


func _draw() -> void:
	# The lane backdrop (high contrast so the pale handles read against it).
	draw_rect(Rect2(0.0, 0.0, size.x, LANE_H), COL_LANE)
	var hy := handle_y()

	# Ghost handle under the cursor on an EMPTY spot — telegraphs "a click adds here".
	if _hover_x >= 0.0 and ghost_frame(_hover_x) >= 0:
		_draw_handle(_hover_x, hy, COL_GHOST)

	# Solid handles = real (deletable) keyframes, each with a thin tick to its band column.
	# ONLY the ones inside the life window — see `in_window` for why the others exist and why
	# drawing them meant painting outside this control.
	for i in range(_keyframes.size()):
		var kf: Dictionary = _keyframes[i]
		if not in_window(int(kf["frame"]), _n):
			continue
		var mx: float = x_of_frame(int(kf["frame"]), size.x, _n)
		var col: Color = COL_SEL if i == _selected else COL_HANDLE
		if _band_height > 0.0:
			draw_line(Vector2(mx, hy + HANDLE_H * 0.5), Vector2(mx, LANE_H + _band_height), COL_TICK, 1.0)
		else:
			draw_line(Vector2(mx, hy + HANDLE_H * 0.5), Vector2(mx, LANE_H), COL_TICK, 1.0)
		_draw_handle(mx, hy, col)
		if i == _selected:
			draw_rect(_handle_rect(mx, hy), COL_SEL, false, 1.5)


## One handle marker (a filled diamond-ish rect) centred at (x, y).
func _draw_handle(x: float, y: float, col: Color) -> void:
	draw_rect(_handle_rect(x, y), col)


func _handle_rect(x: float, y: float) -> Rect2:
	return Rect2(x - HANDLE_W * 0.5, y - HANDLE_H * 0.5, HANDLE_W, HANDLE_H)
