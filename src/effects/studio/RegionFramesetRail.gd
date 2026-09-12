extends Control
## THE FRAMESET RAIL — one tick-able thumbnail per frameset the pinned region reaches,
## along the bottom of the texture viewfinder (author, 2026-08-21: *"yeah actual thumbnails
## along the bottom of the texture viewfinder - I guess? we will need to scale them
## dynamically"*).
##
## It is the `Pick` half of the ADR-0099 dec. 5 scope toggle, and it is a PICTURE because
## the thing it selects has no other address. A region's members are named
## `frameset 17 / frame 0`, and censused over all 398 effects with framesets, 91.5% of the
## 3,251 multi-member regions reach outside the frameset on screen — median 3 framesets,
## p90 11, max 71. So the list an author has to consent to is normally a list of sprites
## they cannot see, addressed by a number that means nothing to them. The author's own
## report of this, mid-edit: *"only thumbnail 1 changed. I thought the change was effect
## wide?"* It was; the other five were in framesets no thumbnail on screen could show.
##
## IT PAINTS THROUGH `SequenceSpritePainter`, the same code the sequence strip's thumbnails
## and the viewport's player use, so a tile is a small copy of the player and cannot drift
## into being a different picture of the same frameset.
##
## EACH TILE IS FIT TO ITS OWN SPRITE (2026-08-21), which is the one place this rail must
## NOT copy the sequence strip. The tiles shared one `SequenceTimeline.bounds` box at first,
## for the strip's reason: fit each cell to its own sprite and two framesets that differ
## only in where the sprite sits re-centre into identical pictures, hiding the motion the
## strip exists to show.
##
## That argument does not carry over, and inverts. A strip's row is one animation over TIME,
## where "same picture, moved" is the common case and the shared box is what makes the move
## visible. This row is one REGION's framesets — every member is the SAME sheet rect by
## definition (that is what makes them one region), so there is no "differ only in where
## they sit" case to protect against. What differs is the frame QUAD, which is a transform
## (ADR-0099 dec. 3 as amended), and members of one region are routinely the same texels
## drawn at wildly different scales.
##
## Under a shared box those became invisible. E317 frameset 15's region is the report:
## bounds of 33x33 beside five sprites 5px tall (33x5, 27x5, 21x5, 14x5, 10x5), which fitted
## into the shared 48x33 box occupy **15% of the tile height** — a 3-8px streak in a 24-56px
## tile. Author, 2026-08-21: *"why don't I see the thumbnails on the texture anymore for what
## is selected for multi select?"* They were being drawn, and were unreadable.
##
## Corpus-wide (`tools/census_rail_tile_legibility.gd`, 2920 multi-frameset region rows /
## 15692 tiles): **19.2% of tiles rendered under 25%** of the shared box and 7.1% under 10%;
## **26.4% of rows** had at least one such tile, and on E242 frameset 70 and E454 frameset 20
## EVERY tile was unreadable. The rail's whole job is that the author recognises a sprite
## well enough to tick it, so legibility is the requirement and relative scale is not.
##
## What this costs, said out loud: a tile no longer shows that its member is drawn squashed.
## The frameset number labels it and the scope control's facets state the varying ones, so
## the fact is still on screen — it is no longer in the picture.
##
## ─── WHY IT IS DRAWN AND NOT ASSEMBLED ───
##
## One custom-drawn `Control`, not a `ScrollContainer` over an `HBoxContainer` of tile
## nodes. That would have brought scrolling and hit-testing for free, and this file family
## has been bitten three times by exactly what it would also bring: a container folding its
## content's minimum into an ancestor's (`SCROLL_MODE_DISABLED` blew the facts overlay from
## 248px to 315), a container's minimum skipping invisible children, and a `Control` parent
## silently being the only reason an overlay is free. A rail pinned inside the port must
## contribute ZERO to the tab's minimum size or it pushes the tab into the sequence player;
## drawing it means there is nothing that could.
##
## ─── THE DYNAMIC SCALE ───
##
## `tile_size` is pure and it is the whole of "scale them dynamically": tiles grow to fill
## the rail up to `TILE_MAX` and shrink to fit down to `TILE_MIN`, and past that they stop
## shrinking and the rail scrolls. A floor is not optional — p99 is 31 framesets and the
## max is 71, and 71 tiles across a 798px port is an 11px tile, which is a smear rather
## than a picture and cannot be aimed at.
##
## No `class_name` (ADR-0004).

const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

## The author ticked (or un-ticked) one frameset. The host lowers it into the scope
## control's `toggle_frameset`, which is also what switches the mode to `Pick`.
signal frameset_toggled(frameset_index: int)

## Grow to this, no further: past it a three-frameset region would put three enormous tiles
## across the sheet it is annotating, which is the "giant column" complaint rotated.
const TILE_MAX := 56.0
## Shrink to this, no further — below it the tile stops being a picture and stops being a
## target. 71 tiles (the corpus max) across a measured 798px port would be 11px each.
const TILE_MIN := 24.0
const TILE_GAP := 3.0
const PAD := 4.0
## Room under each tile for its frameset number. The number is not decoration: a tile is a
## sprite, and 2,146 corpus framesets are not visually distinct from another frameset in
## the same effect, so the picture alone cannot always identify which one is ticked.
const LABEL_H := 11.0
const LABEL_SIZE := 9

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.88)
const TILE_BG := Color(0.10, 0.11, 0.15, 1.0)
## The ticked border, and it is `FramesetCanvas.HANDLE_COLOR` on purpose: the yellow box on
## the sheet and the ticked tiles under it are one statement — this rect, these sprites.
const ON_COLOR := Color(1, 1, 0)
## The un-ticked border. NOT fainter than this: at 0.22 it vanished against the backdrop on
## the shot and an un-ticked tile read as a sprite floating with no frame — so the row
## stopped looking like a row of the same kind of thing. The dimmed sprite carries the
## state; the border only has to say "this is still a tile".
const OFF_COLOR := Color(1, 1, 1, 0.38)
## The frameset the viewport is actually showing, marked so the author can tell the sprite
## they are looking at from the ones they are not.
const SHOWN_COLOR := Color(0.45, 0.85, 1.0)

var _framesets: Array = []          # the effect's framesets, for the painter
var _order: Array = []              # frameset indices, in thumbnail order
var _selected: Dictionary = {}      # frameset_index -> true
var _texture: Texture2D = null
var _bound_frameset: int = -1
## One bounds box PER TILE, index-aligned with `_order`. Precomputed at bind rather than in
## `_draw`, for the reason `set_selection` states: a tick is a click on a control the author
## is looking at, and deriving a frameset's bounding quad per tile per frame is a walk of
## every frame's quad on the repaint path.
var _boxes: Array = []
var _scroll: float = 0.0


func _init() -> void:
	# STOP, unlike the facts overlay's PASS. The overlay is metadata the picture must stay
	# reachable through; this is a row of targets, and a click that fell through to the
	# canvas would start a region drag on whatever texel sits behind the tile.
	mouse_filter = Control.MOUSE_FILTER_STOP


## Bind the row. `order` is `FramesetRegionScope.order_framesets(...)` — already in
## thumbnail order — and `selected` is which of them the current scope takes.
func bind_row(framesets: Array, order: Array, selected: Dictionary,
		texture: Texture2D, bound_frameset: int) -> void:
	_framesets = framesets
	_order = order
	_selected = selected
	_texture = texture
	_bound_frameset = bound_frameset
	# ONE BOX PER TILE — see the header for why this rail does NOT share one the way the
	# sequence strip does. A frameset whose quad collapses to nothing keeps a degenerate box
	# and simply paints nothing, which is what it did before; `fit` is what must not be
	# handed a zero extent.
	_boxes = []
	for e in _entries():
		_boxes.append(SequenceTimeline.bounds([e], framesets))
	_scroll = 0.0
	queue_redraw()


## Only the ticks changed — the row is the same. Kept apart from `bind_row` because a tick
## is a mouse click on a control the author is looking at, and re-deriving the boxes on that
## path would recompute every frameset's bounding quad per tick.
func set_selection(selected: Dictionary) -> void:
	_selected = selected
	queue_redraw()


func row() -> Array:
	return _order


## PURE. The tile edge for `n` tiles in `avail` pixels: grow to `TILE_MAX`, shrink to fit,
## and stop at `TILE_MIN` (past which the rail scrolls instead of shrinking further).
static func tile_size(avail: float, n: int) -> float:
	if n <= 0:
		return 0.0
	var each: float = (avail - 2.0 * PAD - float(n - 1) * TILE_GAP) / float(n)
	return clampf(each, TILE_MIN, TILE_MAX)


## PURE. The height a rail of `n` tiles wants at `avail` width. Zero for an empty row, which
## is how the host knows to hide it rather than reserve a strip of empty box — the same
## lesson the scope's member list learned when a one-row list cost 124px.
static func rail_height(avail: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return tile_size(avail, n) + LABEL_H + 2.0 * PAD


## PURE. Tile `i`'s rect inside a rail of `size`, at horizontal scroll `scroll`.
static func tile_rect(i: int, n: int, size: Vector2, scroll: float) -> Rect2:
	var edge := tile_size(size.x, n)
	return Rect2(PAD + float(i) * (edge + TILE_GAP) - scroll, PAD, edge, edge)


## PURE. The width the tiles actually OCCUPY, capped at the rail's own width.
##
## THE BACKDROP IS DRAWN TO THIS AND NOT TO `size.x`, and that is not a cosmetic trim.
## Measured on E066 frameset 59: a 13-tile row at `TILE_MAX` spans 772 of a 1562-unit port,
## so a full-width backdrop laid a translucent scrim over the whole bottom of the sheet —
## including the live yellow box the author is dragging, which is the one thing on the
## surface that must not be dimmed. Screenshotted; the suite was green.
static func used_width(size: Vector2, n: int) -> float:
	if n <= 0:
		return 0.0
	var edge := tile_size(size.x, n)
	return minf(size.x, 2.0 * PAD + float(n) * edge + float(maxi(0, n - 1)) * TILE_GAP)


## PURE. How far the row can be scrolled before it runs out — 0 when it already fits, so a
## rail that fits can never be scrolled off its own left edge.
static func max_scroll(size: Vector2, n: int) -> float:
	if n <= 0:
		return 0.0
	var edge := tile_size(size.x, n)
	var span := 2.0 * PAD + float(n) * edge + float(maxi(0, n - 1)) * TILE_GAP
	return maxf(0.0, span - size.x)


## Built once and cached — `_draw` runs on every hover of the sheet underneath it, and a
## fresh `StyleBoxFlat` per frame is garbage for a constant.
var _bg: StyleBoxFlat = null


func _backdrop() -> StyleBoxFlat:
	if _bg == null:
		_bg = StyleBoxFlat.new()
		_bg.bg_color = BG_COLOR
		_bg.border_color = Color(1, 1, 1, 0.15)
		_bg.set_border_width_all(1)
		_bg.set_corner_radius_all(4)
	return _bg


func _entries() -> Array:
	var out: Array = []
	for f in _order:
		out.append({"frameset": int(f), "offset": Vector2i.ZERO, "has_sprite": true})
	return out


func _draw() -> void:
	if _order.is_empty():
		return
	var n: int = _order.size()
	# Only under the tiles (see `used_width`), and rounded like the facts overlay so the two
	# read as the same kind of thing floating on the same picture.
	draw_style_box(_backdrop(), Rect2(Vector2.ZERO, Vector2(used_width(size, n), size.y)))
	for i in range(n):
		var r := tile_rect(i, n, size, _scroll)
		# CULLED, because the rail scrolls and 71 tiles is a real corpus case: a tile that
		# is off the rail still costs a `sprite_quads` walk per frame if it is drawn.
		if r.position.x + r.size.x < 0.0 or r.position.x > size.x:
			continue
		var f: int = int(_order[i])
		var on: bool = _selected.has(f)
		draw_rect(r, TILE_BG, true)
		var inner := r.grow(-2.0)
		var box: Rect2i = _boxes[i] if i < _boxes.size() else Rect2i()
		SpritePainter.paint_quads(self, _entries()[i], _framesets, box, _texture,
			SpritePainter.fit(box, inner),
			# UN-TICKED TILES ARE DIMMED, NOT HIDDEN. They are still members of the region
			# and still the thing the author is deciding about; a hidden one would say the
			# edit cannot reach it, which is the opposite of true.
			1.0 if on else 0.35)
		# The border carries the tick — a checkbox beside a 24px tile would be wider than
		# the picture it qualifies.
		draw_rect(r, ON_COLOR if on else OFF_COLOR, false, 2.0 if on else 1.0)
		var label := Rect2(r.position.x, r.position.y + r.size.y, r.size.x, LABEL_H)
		var font := get_theme_default_font()
		if font != null:
			draw_string(font, Vector2(label.position.x + 1.0, label.position.y + LABEL_H - 1.0),
				str(f), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2.0, LABEL_SIZE,
				SHOWN_COLOR if f == _bound_frameset else Color(1, 1, 1, 0.6))
	# THE SCROLL CUE, drawn only when there IS more row. A rail that silently ends at its
	# right edge is a rail whose remaining framesets do not exist as far as the author knows
	# — and past p95 (15 framesets) that is most of them.
	if max_scroll(size, n) > 0.0:
		var frac: float = _scroll / max_scroll(size, n)
		var w: float = maxf(24.0, size.x * (size.x / (size.x + max_scroll(size, n))))
		draw_rect(Rect2((size.x - w) * frac, size.y - 2.0, w, 2.0), Color(1, 1, 1, 0.35), true)


func _gui_input(event: InputEvent) -> void:
	var n: int = _order.size()
	if n <= 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_scroll = clampf(_scroll + TILE_MAX, 0.0, max_scroll(size, n))
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_scroll = clampf(_scroll - TILE_MAX, 0.0, max_scroll(size, n))
			queue_redraw()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var hit: int = hit_tile(event.position, n, size, _scroll)
		if hit >= 0:
			frameset_toggled.emit(int(_order[hit]))


## PURE. Which tile `point` lands on, or -1. The LABEL counts as part of its tile: a 24px
## picture with an 11px number under it is one target to the eye, and a strip of dead
## pixels between rows of targets is how a click lands on nothing.
static func hit_tile(point: Vector2, n: int, size: Vector2, scroll: float) -> int:
	for i in range(n):
		var r := tile_rect(i, n, size, scroll)
		if Rect2(r.position, Vector2(r.size.x, r.size.y + LABEL_H)).has_point(point):
			return i
	return -1
