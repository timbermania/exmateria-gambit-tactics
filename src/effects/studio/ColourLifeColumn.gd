extends Control
## THE VERTICAL COLOUR COLUMN — the particle's colour over its whole life, drawn DOWN the
## side of the film strip so each thumbnail sits beside the colour it is showing.
##
## The author's answer to *"it looks like the thumbnails should align to the colour ribbon
## but they don't"*, verbatim:
##
##   > the ribbon should run vertical down the side of the thumbnails. yeah, it won't be
##   > linear with frames but that's ok. it shows how colors lerp between thumbnails
##
## and, on a thumbnail that holds for several life frames:
##
##   > each column within each row, is a color. so if i held a keyframe for 3 frames i
##   > would get 3 columns in the row?
##
## So: **ONE ROW PER THUMBNAIL, EQUAL HEIGHT; ONE COLUMN PER LIFE FRAME INSIDE IT.**
##
## THE AXIS IS DELIBERATELY NOT LINEAR IN TIME, and that is the whole point. The horizontal
## ribbon it replaces was linear — `width / n` per frame — which is why it could not line up
## with a strip laid out by opcode, and the two axes visibly parted for 45.9% of colour
## emitters. Here the vertical axis is the STRIP's axis by construction (row i is thumbnail
## i), so they cannot disagree; time is expressed HORIZONTALLY, inside a row, where a
## 6-frame hold reads as six columns and a 1-frame cell as one. 81.8% of corpus rows are a
## single column, which is why "one colour per frameset" nearly holds — and the other 18.2%
## are exactly where it breaks, now visible instead of averaged away.
##
## What this costs, said out loud: two rows are the same height whether they held the
## picture for 1 frame or 128, so the column is not a clock and must not be read as one.
## `ColourKeyframeTrack.band_width`'s "fixed width so two emitters compare" argument
## (2026-08-19) does not carry over — it was an argument about a linear axis.
##
## EVERY LIFE FRAME IS STILL INDIVIDUALLY ADDRESSABLE. `SequenceLifeMap.life_rows`
## partitions `[0, life_n)`, so each age is exactly one (row, column) cell — clickable,
## keyframe-able, deletable. A 3-frame hold is three targets, not one.
##
## No `class_name` (ADR-0004) — preloaded by path like the other effect-studio scripts.

## THE SELECTED LIFE FRAME, or **-1 for "nothing selected"**. A FRAME, not a keyframe index,
## and that is the 2026-08-20 "select is not add" change in one line: *"selecting frames is
## good but adding them by clicking them is not. there needs be a second step to lock it
## into being a keyframe instead of just a frame."*
##
## So a click selects ANY age — most of them are interpolated and have no keyframe at all —
## and the index this used to carry could not name one.
signal frame_selected(frame: int)
## A keyframe the author asked to remove (right-click). Still an INDEX, because a removal can
## only ever target a real keyframe.
signal keyframe_remove_requested(index: int)

## The band's FLOOR width, and the value three wrapped columns can afford. Narrow on
## purpose: this rides beside a 34px thumbnail inside a slot whose width is declared once at
## build, and every pixel it takes comes off the player's square. ADR-0068 static-var home.
##
## 22 IS NOT A JUDGEMENT ABOUT RIBBONS — it is arithmetic. `EffectStudioPage`'s life slot is
## `sequence_life_slot_w(3)` = 198px; take the scrollbar and the two gaps between pairs, and
## divide by three, and each pair gets 58 — of which the thumbnail is 34 and its gap 2. The
## remainder is 22. See `wanted_band` for what happens when the strip does not use all three.
static var band_width: float = 22.0

## THE NARROWEST AN AGE MAY BE DRAWN, before the band gives up and packs them tighter.
##
## Author, on a one-frame sprite held for its whole life: *"things get crazy on the
## keyframes — can we maybe do a minimum width keyframes?"* A row splits the band into one
## sub-column per life frame, so a row owning `t` ages draws each at `band / t`: E088 em1 is
## ONE row of 128 ages in 22px, which is **0.17px an age**. Censused over 3,214 colour
## emitters (`tools/census_colour_column_width.gd`) the 10th percentile column is 1.83px and
## the 1st is 0.50px — under a pixel, so several ages share one and `frame_at` can resolve
## only one of them. 106 of E088's 128 ages are unreachable by ANY click
## (`tools/census_colour_column_reach.gd`): 3.8% of emitters have at least one.
##
## FIVE, because that is the keyframe mark's own footprint (`KF_W` plus its keyline either
## side). Below it the thing that says "this age is a keyframe" cannot fit inside the age it
## is the mark for — which is the picture the author was reporting.
static var min_col_w: float = 5.0

## THE WIDEST THE BAND MAY GROW, however wide the host says there is room for.
##
## 150, and it is the same arithmetic as `band_width` read at its other end: ONE pair inside
## the page's 198px life slot, once the scrollbar and the 34px thumbnail are paid. Three
## pairs afford 22 each, one affords 150 — so the floor and the ceiling are one formula, and
## the band never claims more than the layout was already designed to hand a single column.
##
## A CAP AND NOT A TARGET. Without it a 128-age row takes every pixel the panel has spare
## (measured: 374 on a wide row), and while that moves nothing the author complained about —
## the player's square is capped at `_CANVAS_SIDE` and the slot's declared minimum never
## changes — a ribbon that is five times the width of the thumbnails it annotates is a
## different picture, not a bigger one.
static var band_max: float = 150.0

const COL_KF := Color(0.97, 0.98, 1.0, 1.0)       # a real (deletable) keyframe
const COL_KF_EDGE := Color(0.05, 0.06, 0.09, 0.9) # its dark keyline, so it reads on any hue
const COL_SEL := Color(1.0, 0.95, 0.6, 1.0)       # the SELECTED age, keyframe or not
const COL_HOVER := Color(0.95, 0.96, 1.0, 0.30)   # the cell under the cursor
const COL_GAP := Color(0.10, 0.11, 0.14, 1.0)     # rows with no colour (unreachable)
const KF_W := 3.0                                 # the keyframe bar's width
const ROW_RULE := Color(0.0, 0.0, 0.0, 0.35)      # the hairline between rows

var _rows: Array = []          # SequenceLifeMap.life_rows: [{cell, start, ticks}, …]
var _colors: Array = []        # one Color per life frame, index = age
var _row_h: float = 34.0
## The width this column was actually granted — `band_width` until a host offers a ceiling.
var _band: float = band_width
var _keyframes: Array = []
## The selected AGE (-1 = none). Frame-addressed, so it survives a keyframe being added or
## removed under it without silently re-pointing at a different one.
var _selected_frame: int = -1
var _hover: Vector2 = Vector2(-1, -1)


func _init() -> void:
	custom_minimum_size = Vector2(band_width, 0.0)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP


## Bind the column to a life projection. `row_h` MUST be the strip's cell pitch — the whole
## claim of this surface is that row i sits beside thumbnail i, and a pitch that disagreed
## would break the alignment silently while still drawing a plausible bar.
##
## `ceiling` is how wide the HOST can let this column be — the width its slot has left once
## the pairs actually in use are laid out. Omitted, it is `band_width`, which is exactly the
## pre-2026-08-21 behaviour and is what every caller with no slot to ask gets.
func configure(rows: Array, colors: Array, row_h: float, ceiling: float = -1.0) -> void:
	_rows = rows
	_colors = colors
	_row_h = maxf(1.0, row_h)
	_band = wanted_band(rows, ceiling if ceiling > 0.0 else band_width)
	custom_minimum_size = Vector2(_band, _row_h * float(_rows.size()))
	queue_redraw()


## HOW WIDE THIS COLUMN WANTS TO BE: enough for its widest row to give every age `min_col_w`,
## never under `band_width`, never over what the host says it may take. Pure.
##
## THE ARITHMETIC THAT MAKES THIS AFFORDABLE, and it is the whole reason this is not just
## "make the band bigger": a row is wide exactly when there are FEW rows, because
## `rows x ticks ~= life_n`. Few rows means the strip wraps into fewer pairs, and the pairs it
## does not use leave their share of an already-declared slot on the floor. Measured: one
## visible pair can afford **150px** inside the same 198px slot, two can afford 54, three can
## afford 22 — which is `band_width`, so the floor and the ceiling are one formula seen at
## its two ends.
##
## THE HOST'S SLOT NEVER MOVES, and that is the constraint this is shaped around rather than
## an incidental nicety. `EffectStudioPage` declares the life slot's width ONCE at build
## because a per-emitter bid would make the inspector's right edge a function of which
## emitter is open — the author's *"the animation box is changing in size all the time"*,
## already answered twice. This grows INSIDE that declaration and can never widen it.
##
## What it buys, censused over 3,214 colour emitters: the 10th-percentile column goes 1.83px
## -> 5.00px, and emitters where every age is reachable by some click go 96.7% -> 99.9%.
static func wanted_band(rows: Array, ceiling: float) -> float:
	var widest: int = 0
	for r in rows:
		widest = maxi(widest, maxi(1, int(r.get("ticks", 1))))
	if widest <= 0:
		return band_width
	return clampf(min_col_w * float(widest), band_width, maxf(band_width, minf(ceiling, band_max)))


## The width this column is drawn and hit-tested at. `size.x` once it is in a tree; this is
## the answer before a layout pass, and what a test asserts against.
func band() -> float:
	return _band


## The real keyframes to mark. SEPARATE from the selection now — they used to arrive
## together as (array, index into it), which could not express "this age is selected and is
## not a keyframe", the state the whole two-step gesture exists to have.
func set_keyframes(keyframes: Array) -> void:
	_keyframes = keyframes
	queue_redraw()


func set_selected_frame(frame: int) -> void:
	_selected_frame = frame
	queue_redraw()


func selected_frame() -> int:
	return _selected_frame


## Is the selected age a REAL keyframe, or an interpolated one? The picker's title and its
## ⬥ button both branch on this, and so does whether a pick authors anything.
func selection_is_keyframe() -> bool:
	return keyframe_at_frame(_keyframes, _selected_frame) >= 0


func row_count() -> int:
	return _rows.size()


## The number of life frames this column addresses — `life_n` when the rows came from
## `life_rows`, since those partition `[0, life_n)`.
func frame_count() -> int:
	var n := 0
	for r in _rows:
		n += int(r.get("ticks", 0))
	return n


# --- pure geometry (testable without a scene) -----------------------------

## The life frame at a point, or -1 outside. Pure so the hit test is guarded without a
## viewport — the two mappings below are inverses and a drift between them would mean
## clicking one colour and editing another, which looks like nothing at all.
static func frame_at(pos: Vector2, rows: Array, row_h: float, width: float) -> int:
	if rows.is_empty() or row_h <= 0.0 or width <= 0.0:
		return -1
	if pos.x < 0.0 or pos.x >= width or pos.y < 0.0:
		return -1
	var i: int = int(floor(pos.y / row_h))
	if i < 0 or i >= rows.size():
		return -1
	var row: Dictionary = rows[i]
	var ticks: int = maxi(1, int(row.get("ticks", 1)))
	var k: int = clampi(int(floor(pos.x / width * float(ticks))), 0, ticks - 1)
	return int(row.get("start", 0)) + k


## The rect a life frame occupies, or a zero rect when this column does not address it.
static func rect_of_frame(frame: int, rows: Array, row_h: float, width: float) -> Rect2:
	if frame < 0 or rows.is_empty() or row_h <= 0.0 or width <= 0.0:
		return Rect2()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var start: int = int(row.get("start", 0))
		var ticks: int = maxi(1, int(row.get("ticks", 1)))
		if frame < start or frame >= start + ticks:
			continue
		var k: int = frame - start
		var w: float = width / float(ticks)
		return Rect2(w * float(k), row_h * float(i), w, row_h)
	return Rect2()


## THE KEYFRAME MARK, and it NEVER OUTGROWS THE AGE IT MARKS. It rides the left edge of the
## cell `rect_of_frame` returned, `KF_W` wide where there is room and the cell's own width
## where there is not.
##
## It used to be a flat `KF_W` bar with a 1px keyline grown around it — **5px of footprint on
## a column 1.4px wide** on a 128-age hold, so a keyframe painted over its two neighbours and
## a RUN of adjacent keyframes read as one white block instead of three separate ages. That
## is the second half of the author's *"things get crazy on the keyframes"* and no band width
## fixes it on its own. Pure, so the claim is a rect comparison rather than a screenshot.
static func mark_rect(cell: Rect2) -> Rect2:
	return Rect2(cell.position, Vector2(clampf(cell.size.x, 1.0, KF_W), cell.size.y))


## Which ROW a life frame lands in, or -1. The strip's link: the thumbnail to highlight
## when a keyframe is selected on the column.
static func row_of_frame(frame: int, rows: Array) -> int:
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var start: int = int(row.get("start", 0))
		if frame >= start and frame < start + maxi(1, int(row.get("ticks", 1))):
			return i
	return -1


## Index into `keyframes` of the one at life frame `frame`, or -1. Frame-addressed rather
## than pixel-addressed, because a column can be under a pixel wide on a long hold (128
## frames in a 22px band) and a pixel-radius hit test would make those unreachable.
static func keyframe_at_frame(keyframes: Array, frame: int) -> int:
	if frame < 0:
		return -1
	for i in range(keyframes.size()):
		if int(keyframes[i].get("frame", -1)) == frame:
			return i
	return -1


## How many keyframes address an age this column does not — the dead-zone count, kept for
## the same reason `ColourKeyframeTrack.beyond_count` exists: the Douglas-Peucker import
## always keeps the terminal sample, so every colour emitter carries one at frame 159 and
## dropping them silently is the other way to be wrong.
static func beyond_count(keyframes: Array, rows: Array) -> int:
	var c := 0
	for kf in keyframes:
		if row_of_frame(int(kf.get("frame", -1)), rows) < 0:
			c += 1
	return c


# --- input ---------------------------------------------------------------

## A LEFT CLICK SELECTS AN AGE. It never adds a keyframe — that is the second step, and it
## lives on the picker's ⬥ button (author, 2026-08-20: *"selecting frames is good but adding
## them by clicking them is not"*).
##
## The first build minted a keyframe on every click into an empty column, which meant
## browsing the colour of an age you were only curious about permanently altered the curve.
## It also cost this control its only spare gesture: with "click empty = add" gone, a second
## click on the SELECTED cell can deselect, and that is now the same gesture on every cell
## rather than one that only worked on keyframes.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = event.position
		queue_redraw()
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var frame := frame_at(event.position, _rows, _row_h, size.x)
	if frame < 0:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Removal can only target a REAL keyframe; right-clicking an interpolated age has
		# nothing to remove and must not be read as "remove the one it interpolates from".
		var at := keyframe_at_frame(_keyframes, frame)
		if at >= 0:
			keyframe_remove_requested.emit(at)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected_frame = -1 if frame == _selected_frame else frame
	frame_selected.emit(_selected_frame)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2(-1, -1)
		queue_redraw()


# --- drawing -------------------------------------------------------------

func _draw() -> void:
	var w: float = size.x
	if w <= 0.0:
		return
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var start: int = int(row.get("start", 0))
		var ticks: int = maxi(1, int(row.get("ticks", 1)))
		var y: float = _row_h * float(i)
		var cw: float = w / float(ticks)
		for k in range(ticks):
			var age: int = start + k
			var c: Color = _colors[age] if age >= 0 and age < _colors.size() else COL_GAP
			# CEIL the width, so a sub-pixel column on a long hold still paints something
			# rather than vanishing — 128-frame holds exist and a blank row would read as
			# "no colour here" when the truth is "too many colours to separate".
			draw_rect(Rect2(cw * float(k), y, maxf(1.0, ceil(cw)), _row_h), c)
		# The row hairline is what makes "one row per thumbnail" legible when two
		# neighbouring rows resolve to nearly the same colour.
		if i > 0:
			draw_line(Vector2(0.0, y), Vector2(w, y), ROW_RULE, 1.0)

	# The cell under the cursor, faintly outlined. It telegraphs "a click SELECTS here" — it
	# used to be a solid ghost bar meaning "a click ADDS here", and softening it is the
	# drawing half of the same change: a hover that looks like a pending edit is a lie now.
	if _hover.x >= 0.0:
		var hf := frame_at(_hover, _rows, _row_h, w)
		if hf >= 0 and hf != _selected_frame:
			var gr := rect_of_frame(hf, _rows, _row_h, w)
			if gr.size.x > 0.0:
				draw_rect(gr, COL_HOVER, false, 1.0)

	# TWO MARKS, TWO MEANINGS, and keeping them orthogonal is the point: the OUTLINE says
	# "selected", the BAR says "is a real keyframe". Before the two-step gesture those were
	# the same thing and one mark did both — which is exactly why an interpolated selection
	# had nothing to draw.
	#
	# The bar rides the LEFT EDGE of its column with a dark keyline so it reads against any
	# hue. No separate handle lane: the horizontal track could afford one above the band, a
	# column beside a 34px thumbnail cannot, and every pixel here comes off the player's
	# square.
	for i in range(_keyframes.size()):
		var f: int = int(_keyframes[i].get("frame", -1))
		var r := rect_of_frame(f, _rows, _row_h, w)
		if r.size.x <= 0.0:
			continue
		var bar := mark_rect(r)
		# The keyline only where the age has room for it. It exists so the bar reads against
		# any hue; below the width where it fits INSIDE the age it would be the thing
		# bleeding into the neighbour, which is the defect and not the cure.
		if r.size.x >= bar.size.x + 2.0:
			draw_rect(bar.grow(1.0), COL_KF_EDGE)
		draw_rect(bar, COL_SEL if f == _selected_frame else COL_KF)

	# The selection outline is drawn LAST and independently, so it lands on an interpolated
	# age as readily as on a keyframe.
	if _selected_frame >= 0:
		var sr := rect_of_frame(_selected_frame, _rows, _row_h, w)
		if sr.size.x > 0.0:
			# Widened to at least the keyframe bar, so a sub-pixel column on a long hold is
			# still visibly the selected one.
			draw_rect(Rect2(sr.position, Vector2(maxf(sr.size.x, KF_W + 1.0), sr.size.y)),
				COL_SEL, false, 1.5)
